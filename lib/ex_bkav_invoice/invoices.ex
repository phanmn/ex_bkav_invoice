defmodule ExBkavInvoice.Invoices do
  @moduledoc """
  Creating and signing one invoice, in the caller's terms rather than Bkav's.

  The rest of this library speaks eHoadon's protocol: commands, the `Status` /
  `Object` envelope, `InvoiceGUID` and `MTC` keys, `ExBkavInvoice.Error` with a
  `:kind`. That is the right shape for talking to the service and the wrong
  shape for an application, which ends up restating eHoadon's vocabulary and
  re-implementing its quirks at every call site.

  This module is the boundary. It answers `{:ok, ExBkavInvoice.InvoiceResult.t()}`
  or `{:error, ExBkavInvoice.Error{}}` — named fields on both sides, no Bkav keys
  and no envelope. A rejected invoice becomes an `:api` error like any other
  refusal, so a caller reads `message`, `code` and `kind` (or
  `ExBkavInvoice.Error.retryable?/1`) without caring which layer said no.

  It also owns the two traps that otherwise leak outwards:

    * A batch answers `Status: 0` at the envelope level even when the one invoice
      inside it failed, so the per-invoice status is what decides. `create/3`
      reports that failure as `{:error, _}` rather than a success with nothing in
      it.
    * Signing is what issues the invoice (phát hành) and needs an HSM account.
      `sign/3` answers `:ok` or `{:error, _}`; a failure does not undo the
      creation, so the draft still exists on eHoadon either way.
  """

  @doc """
  Creates one invoice and returns what eHoadon allocated for it.

  `invoice` is an `ExBkavInvoice.Invoice`, or a raw `InvoiceDataWS` map for
  anything the struct does not cover. Options are those of
  `ExBkavInvoice.create_invoice/3` — notably `:cmd_type`, which defaults to
  `:create_draft` and leaves the invoice a deletable draft with no number.

  Use `ExBkavInvoice.create_invoice/3` directly to send a batch.
  """
  @spec create(ExBkavInvoice.Config.t(), ExBkavInvoice.Invoice.t() | map(), keyword()) ::
          {:ok, ExBkavInvoice.InvoiceResult.t()} | {:error, ExBkavInvoice.Error.t()}
  def create(%ExBkavInvoice.Config{} = config, invoice, opts \\ []) when is_map(invoice) do
    case ExBkavInvoice.create_invoice(config, [payload(invoice)], opts) do
      {:ok, response} -> single_result(response)
      {:error, error} -> {:error, error}
    end
  end

  @doc """
  Signs an invoice, issuing it to the tax authority.

  Only works on an account with an HSM certificate.
  """
  @spec sign(ExBkavInvoice.Config.t(), String.t(), keyword()) ::
          :ok | {:error, ExBkavInvoice.Error.t()}
  def sign(%ExBkavInvoice.Config{} = config, invoice_guid, opts \\ [])
      when is_binary(invoice_guid) do
    case ExBkavInvoice.sign(config, invoice_guid, opts) do
      {:ok, _response} -> :ok
      {:error, error} -> {:error, error}
    end
  end

  defp payload(%ExBkavInvoice.Invoice{} = invoice), do: ExBkavInvoice.Invoice.to_map(invoice)
  defp payload(%{} = invoice), do: invoice

  defp single_result(response) do
    case ExBkavInvoice.Response.split_results(response) do
      {[result], []} ->
        {:ok, ExBkavInvoice.InvoiceResult.from_map(result)}

      {_created, [failed | _]} ->
        {:error, ExBkavInvoice.Error.api(failure_message(failed))}

      {[], []} ->
        {:error, ExBkavInvoice.Error.api("eHoadon returned no invoice result")}
    end
  end

  defp failure_message(%{"MessLog" => log}) when is_binary(log) and log != "", do: log
  defp failure_message(_failed), do: "eHoadon rejected the invoice"
end
