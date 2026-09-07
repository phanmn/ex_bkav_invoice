defmodule ExBkavInvoice.InvoiceDetail do
  @moduledoc """
  One line of an `ExBkavInvoice.Invoice`.

  `amount` is the line net and `tax_amount` the VAT on it; eHoadon wants them
  apart, and the invoice is rejected if the lines do not add up to its total.
  `unit_price` is per unit of `quantity`, also net.

  `tax_rate_id` and `tax_rate` have to agree — the id names the rate on the
  document and the rate is what the amounts were computed with, so setting one
  without the other produces an invoice that reads as a different rate than it
  was priced at. See `ExBkavInvoice.Enums.tax_rate/1`.
  """

  @type t :: %__MODULE__{
          name: String.t() | nil,
          unit_name: String.t() | nil,
          quantity: integer(),
          unit_price: integer() | float(),
          amount: integer() | float(),
          tax_rate_id: integer(),
          tax_rate: float(),
          tax_amount: integer() | float(),
          discount_rate: float(),
          discount_amount: integer() | float(),
          discount?: boolean(),
          item_type_id: integer(),
          user_define_details: String.t() | nil
        }

  defstruct name: nil,
            unit_name: nil,
            quantity: 1,
            unit_price: 0,
            amount: 0,
            # 1 = 0%, which is wrong in an obvious rather than a silent way. The
            # rate is an accounting decision, so there is no safe default.
            tax_rate_id: 1,
            tax_rate: 0.0,
            tax_amount: 0,
            discount_rate: 0.0,
            discount_amount: 0.0,
            discount?: false,
            item_type_id: 0,
            user_define_details: nil

  @doc """
  Renders the line as the `InvoiceDetailsWS` map eHoadon expects.
  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = detail) do
    %{
      "ItemName" => ExBkavInvoice.Invoice.text(detail.name),
      "UnitName" => ExBkavInvoice.Invoice.text(detail.unit_name),
      "Qty" => detail.quantity,
      "Price" => detail.unit_price,
      "Amount" => detail.amount,
      "TaxRateID" => detail.tax_rate_id,
      "TaxRate" => detail.tax_rate,
      "TaxAmount" => detail.tax_amount,
      "DiscountRate" => detail.discount_rate,
      "DiscountAmount" => detail.discount_amount,
      "IsDiscount" => detail.discount?,
      "ItemTypeID" => detail.item_type_id,
      "UserDefineDetails" => ExBkavInvoice.Invoice.text(detail.user_define_details)
    }
  end
end
