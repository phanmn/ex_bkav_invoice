defmodule ExBkavInvoice.InvoiceResult do
  @moduledoc """
  What eHoadon did with one invoice, in named fields.

  The wire form is a map keyed by Bkav's own names — `InvoiceGUID`, `MTC`,
  `MessLog` and so on. Handing that map to a caller makes every caller learn
  eHoadon's vocabulary and re-implement its quirks, so `ExBkavInvoice.Invoices`
  returns this instead.

  `no` is worth singling out: with the default `:create_draft` command it comes
  back `0`, because the invoice number is allocated at signing rather than at
  creation. A caller that treats it as the invoice's identity before the
  invoice is signed is reading a number that does not exist yet.
  """

  @type t :: %__MODULE__{
          guid: String.t() | nil,
          form: String.t() | nil,
          serial: String.t() | nil,
          no: integer() | nil,
          lookup_code: String.t() | nil,
          partner_invoice_id: integer() | nil,
          partner_invoice_string_id: String.t() | nil
        }

  defstruct [
    :guid,
    :form,
    :serial,
    :no,
    :lookup_code,
    :partner_invoice_id,
    :partner_invoice_string_id
  ]

  @doc """
  Builds a result from one entry of `ExBkavInvoice.Response.invoice_results/1`.

  ## Examples

      iex> ExBkavInvoice.InvoiceResult.from_map(%{
      ...>   "InvoiceGUID" => "9ebd0c34-8ac4-40b3-9cf9-da800da38af9",
      ...>   "InvoiceForm" => "01GTKT0/001",
      ...>   "InvoiceSerial" => "AB/19E",
      ...>   "InvoiceNo" => 0,
      ...>   "MTC" => "RTO9YKG38"
      ...> })
      %ExBkavInvoice.InvoiceResult{
        guid: "9ebd0c34-8ac4-40b3-9cf9-da800da38af9",
        form: "01GTKT0/001",
        serial: "AB/19E",
        no: 0,
        lookup_code: "RTO9YKG38",
        partner_invoice_id: nil,
        partner_invoice_string_id: nil
      }
  """
  @spec from_map(map()) :: t()
  def from_map(%{} = result) do
    %__MODULE__{
      guid: blank_to_nil(result["InvoiceGUID"]),
      form: blank_to_nil(result["InvoiceForm"]),
      serial: blank_to_nil(result["InvoiceSerial"]),
      no: result["InvoiceNo"],
      lookup_code: blank_to_nil(result["MTC"]),
      partner_invoice_id: result["PartnerInvoiceID"],
      partner_invoice_string_id: blank_to_nil(result["PartnerInvoiceStringID"])
    }
  end

  # eHoadon fills unset string fields with "" rather than omitting them, and a
  # caller storing those would record an empty serial as though one were issued.
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value
end
