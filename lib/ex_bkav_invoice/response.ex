defmodule ExBkavInvoice.Response do
  @moduledoc """
  The envelope every command answers with, and the per-invoice results inside it.

  eHoadon replies with a fixed shape:

      {"Status": 0, "Object": ..., "Code": null, "isOk": true, "isError": false}

  `Status` is `0` for success and `1` for failure. `Object` is overloaded: it may
  be a number (`801`), a boolean (`901`), a real array (`300`, `850`), or — most
  often — a **JSON document encoded as a string**, which `parse/1` decodes a
  second time so callers never have to.
  """

  @type t :: %__MODULE__{
          status: integer(),
          object: term(),
          code: String.t() | nil,
          raw: map()
        }

  defstruct [:status, :object, :code, :raw]

  @doc """
  Turns a decoded JSON body into `{:ok, t}` or an `:api` error.
  """
  @spec parse(map()) :: {:ok, t()} | {:error, ExBkavInvoice.Error.t()}
  def parse(%{} = body) do
    status = body["Status"]
    object = decode_object(body["Object"])
    code = body["Code"]

    if success?(body, status) do
      {:ok, %__MODULE__{status: status, object: object, code: code, raw: body}}
    else
      {:error, ExBkavInvoice.Error.api(error_message(object), code, body)}
    end
  end

  # `isError` is authoritative when present: command 206 answers a partial signing
  # failure with isError true, and trusting Status alone would let it through.
  defp success?(%{"isError" => true}, _status), do: false
  defp success?(%{"isOk" => false}, _status), do: false
  defp success?(_body, status), do: status in [0, nil]

  defp error_message(object) when is_binary(object) and object != "", do: object
  defp error_message(%{"Msg" => msg}) when is_binary(msg) and msg != "", do: msg
  defp error_message(%{"MessLog" => log}) when is_binary(log) and log != "", do: log
  defp error_message(nil), do: "eHoadon rejected the command"
  defp error_message(object), do: inspect(object)

  # Object arrives either as a real JSON value or as a string holding one. Only
  # strings that open like a document are re-decoded, so a plain payload such as
  # a file path or base64 PDF is left alone.
  defp decode_object(object) when is_binary(object) do
    trimmed = String.trim_leading(object)

    if String.starts_with?(trimmed, ["[", "{"]) do
      case Jason.decode(trimmed) do
        {:ok, decoded} -> decoded
        {:error, _} -> object
      end
    else
      object
    end
  end

  defp decode_object(object), do: object

  @doc """
  The per-invoice results a creation, update, void or attachment command returns.

  Each entry carries the ids you need to reconcile with your own records:

    * `"PartnerInvoiceID"` / `"PartnerInvoiceStringID"` — the id you sent
    * `"InvoiceGUID"` — eHoadon's id, needed for signing, voiding and lookups
    * `"InvoiceForm"`, `"InvoiceSerial"`, `"InvoiceNo"` — the assigned identity
    * `"MTC"` — the lookup code (mã tra cứu) buyers use on tracuu.ehoadon.vn
    * `"Status"` — `0` or `1` **for this invoice alone**
    * `"MessLog"` — why this invoice failed
  """
  @spec invoice_results(t()) :: [map()]
  def invoice_results(%__MODULE__{object: object}) when is_list(object), do: object
  def invoice_results(%__MODULE__{object: %{} = object}), do: [object]
  def invoice_results(%__MODULE__{}), do: []

  @doc """
  Splits `invoice_results/1` into `{succeeded, failed}`.

  A batch can come back with `Status: 0` at the envelope level while individual
  invoices inside it failed, so anything that submits more than one invoice at a
  time has to look here rather than stopping at `parse/1`.
  """
  @spec split_results(t()) :: {[map()], [map()]}
  def split_results(%__MODULE__{} = response) do
    response
    |> invoice_results()
    |> Enum.split_with(&(Map.get(&1, "Status", 0) == 0))
  end

  @doc """
  Annotates a `850` tax-status response with the labels for its numeric codes.
  """
  @spec describe_tax_status(t()) :: [map()]
  def describe_tax_status(%__MODULE__{} = response) do
    response
    |> invoice_results()
    |> Enum.map(fn entry ->
      entry
      |> Map.put("BkavStatusName", ExBkavInvoice.Enums.invoice_status(entry["BkavStatus"]))
      |> Map.put("TaxStatusName", ExBkavInvoice.Enums.tax_status(entry["TaxStatus"]))
    end)
  end
end
