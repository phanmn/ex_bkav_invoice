defmodule ExBkavInvoice.Invoices do
  @moduledoc """
  Creating and signing one invoice, in the caller's terms rather than Bkav's.

  The rest of this library speaks eHoadon's protocol: commands, the `Status` /
  `Object` envelope, `InvoiceGUID` and `MTC` keys, `ExBkavInvoice.Error` with a
  `:kind`. That is the right shape for talking to the service and the wrong
  shape for an application, which ends up restating eHoadon's vocabulary and
  re-implementing its quirks at every call site.

  This module is the boundary. It answers `{:ok, ExBkavInvoice.InvoiceResult.t()}`
  or `{:error, message}` where `message` is a plain string ready to log or store,
  and it owns the two traps that otherwise leak outwards:

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

  `invoice` is a single `InvoiceDataWS` map. Options are those of
  `ExBkavInvoice.create_invoice/3` — notably `:cmd_type`, which defaults to
  `:create_draft` and leaves the invoice a deletable draft with no number.

  Use `ExBkavInvoice.create_invoice/3` directly to send a batch.
  """
  @spec create(ExBkavInvoice.Config.t(), map(), keyword()) ::
          {:ok, ExBkavInvoice.InvoiceResult.t()} | {:error, String.t()}
  def create(%ExBkavInvoice.Config{} = config, invoice, opts \\ []) when is_map(invoice) do
    case ExBkavInvoice.create_invoice(config, [invoice], opts) do
      {:ok, response} -> single_result(response)
      {:error, error} -> {:error, describe(error)}
    end
  end

  @doc """
  Signs an invoice, issuing it to the tax authority.

  Only works on an account with an HSM certificate.
  """
  @spec sign(ExBkavInvoice.Config.t(), String.t(), keyword()) :: :ok | {:error, String.t()}
  def sign(%ExBkavInvoice.Config{} = config, invoice_guid, opts \\ [])
      when is_binary(invoice_guid) do
    case ExBkavInvoice.sign(config, invoice_guid, opts) do
      {:ok, _response} -> :ok
      {:error, error} -> {:error, describe(error)}
    end
  end

  defp single_result(response) do
    case ExBkavInvoice.Response.split_results(response) do
      {[result], []} -> {:ok, ExBkavInvoice.InvoiceResult.from_map(result)}
      {_created, [failed | _]} -> {:error, failure_message(failed)}
      {[], []} -> {:error, "eHoadon returned no invoice result"}
    end
  end

  defp failure_message(%{"MessLog" => log}) when is_binary(log) and log != "", do: log
  defp failure_message(_failed), do: "eHoadon rejected the invoice"

  defp describe(%ExBkavInvoice.Error{} = error), do: Exception.message(error)
end
