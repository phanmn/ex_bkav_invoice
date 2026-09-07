defmodule ExBkavInvoice.Invoice do
  @moduledoc """
  One invoice to send to eHoadon, in named fields.

  eHoadon's `InvoiceDataWS` is a nested map of `BuyerTaxCode`, `PayMethodID`,
  `ListInvoiceDetailsWS` and two dozen siblings, most of which must be present
  even when empty — it rejects a null where it wants `""`. Building that by hand
  means every caller learns the shape, repeats the boilerplate, and gets no
  warning when a key is misspelled.

  This struct is that shape with the boilerplate defaulted: fill in the buyer,
  the lines and the identity, and `to_map/1` produces what the service expects.

  ## Identity

  `partner_invoice_string_id` is your own id for the invoice, and eHoadon uses it
  to recognise one it has already accepted — which is what makes a retry safe.
  Set it to something stable per invoice, such as the order id.

  ## Amounts

  Each line carries a net `amount` and a separate `tax_amount`; eHoadon expects
  the split, not a gross figure. An invoice whose lines do not add up to its
  total is rejected, so a caller working back from gross amounts has to place
  any rounding drift deliberately rather than letting it fall where it may.
  """

  @type t :: %__MODULE__{
          partner_invoice_string_id: String.t() | nil,
          partner_invoice_id: integer(),
          invoice_type_id: integer(),
          date: DateTime.t() | String.t() | nil,
          buyer_name: String.t() | nil,
          buyer_tax_code: String.t() | nil,
          buyer_unit_name: String.t() | nil,
          buyer_address: String.t() | nil,
          buyer_bank_account: String.t() | nil,
          pay_method_id: integer(),
          receive_type_id: integer(),
          receiver_email: String.t() | nil,
          receiver_mobile: String.t() | nil,
          receiver_name: String.t() | nil,
          receiver_address: String.t() | nil,
          note: String.t() | nil,
          bill_code: String.t() | nil,
          currency: String.t(),
          exchange_rate: float(),
          details: [ExBkavInvoice.InvoiceDetail.t()],
          attachments: [map()]
        }

  defstruct partner_invoice_string_id: nil,
            partner_invoice_id: 0,
            invoice_type_id: 1,
            date: nil,
            buyer_name: nil,
            buyer_tax_code: nil,
            buyer_unit_name: nil,
            buyer_address: nil,
            buyer_bank_account: nil,
            pay_method_id: 2,
            # 1 = email only. Asking eHoadon to send an SMS without a number is
            # an error rather than a no-op, so this is the safe default.
            receive_type_id: 1,
            receiver_email: nil,
            receiver_mobile: nil,
            receiver_name: nil,
            receiver_address: nil,
            note: nil,
            bill_code: nil,
            currency: "VND",
            exchange_rate: 1.0,
            details: [],
            attachments: []

  @doc """
  Renders the invoice as the `InvoiceDataWS` map eHoadon expects.

  Unset strings become `""` rather than null, and `date` defaults to now, both
  because eHoadon rejects the alternatives.

  ## Examples

      iex> invoice = %ExBkavInvoice.Invoice{
      ...>   partner_invoice_string_id: "order-1",
      ...>   buyer_name: "CÔNG TY ABC",
      ...>   buyer_tax_code: "0312345678",
      ...>   date: ~U[2026-09-07 10:00:00Z],
      ...>   details: [%ExBkavInvoice.InvoiceDetail{name: "Vé", quantity: 1, amount: 100, tax_amount: 10}]
      ...> }
      iex> map = ExBkavInvoice.Invoice.to_map(invoice)
      iex> map["PartnerInvoiceStringID"]
      "order-1"
      iex> map["Invoice"]["BuyerTaxCode"]
      "0312345678"
      iex> [detail] = map["ListInvoiceDetailsWS"]
      iex> {detail["Amount"], detail["TaxAmount"]}
      {100, 10}
  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = invoice) do
    %{
      "Invoice" => header(invoice),
      "ListInvoiceDetailsWS" => Enum.map(invoice.details, &ExBkavInvoice.InvoiceDetail.to_map/1),
      "ListInvoiceAttachFileWS" => invoice.attachments,
      "PartnerInvoiceID" => invoice.partner_invoice_id,
      "PartnerInvoiceStringID" => text(invoice.partner_invoice_string_id)
    }
  end

  defp header(invoice) do
    %{
      "InvoiceTypeID" => invoice.invoice_type_id,
      "InvoiceDate" => date(invoice.date),
      "BuyerName" => text(invoice.buyer_name),
      "BuyerTaxCode" => text(invoice.buyer_tax_code),
      "BuyerUnitName" => text(invoice.buyer_unit_name),
      "BuyerAddress" => text(invoice.buyer_address),
      "BuyerBankAccount" => text(invoice.buyer_bank_account),
      "PayMethodID" => invoice.pay_method_id,
      "ReceiveTypeID" => invoice.receive_type_id,
      "ReceiverEmail" => text(invoice.receiver_email),
      "ReceiverMobile" => text(invoice.receiver_mobile),
      "ReceiverName" => text(invoice.receiver_name),
      "ReceiverAddress" => text(invoice.receiver_address),
      "Note" => text(invoice.note),
      "BillCode" => text(invoice.bill_code),
      "CurrencyID" => text(invoice.currency),
      "ExchangeRate" => invoice.exchange_rate
    }
  end

  defp date(nil), do: DateTime.to_iso8601(DateTime.utc_now())
  defp date(%DateTime{} = at), do: DateTime.to_iso8601(at)
  defp date(at) when is_binary(at), do: at

  @doc false
  @spec text(String.t() | nil) :: String.t()
  def text(nil), do: ""
  def text(value) when is_binary(value), do: String.trim(value)
end
