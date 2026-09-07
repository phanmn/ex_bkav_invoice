defmodule ExBkavInvoice.InvoiceTest do
  use ExUnit.Case, async: true

  doctest ExBkavInvoice.Invoice

  defp invoice(attrs \\ []) do
    struct!(
      %ExBkavInvoice.Invoice{
        partner_invoice_string_id: "order-1",
        buyer_name: "CÔNG TY ABC",
        buyer_tax_code: "0312345678",
        date: ~U[2026-09-07 10:00:00Z]
      },
      attrs
    )
  end

  describe "to_map/1" do
    test "renders the identity eHoadon deduplicates retries on" do
      map = ExBkavInvoice.Invoice.to_map(invoice())

      assert map["PartnerInvoiceStringID"] == "order-1"
      assert map["PartnerInvoiceID"] == 0
    end

    # eHoadon rejects a null where it wants an empty string, so every optional
    # field has to be present rather than omitted.
    test "sends unset strings as empty rather than null" do
      header = ExBkavInvoice.Invoice.to_map(invoice())["Invoice"]

      for key <- ~w(BuyerUnitName BuyerAddress BuyerBankAccount ReceiverEmail
                    ReceiverMobile ReceiverName ReceiverAddress Note BillCode) do
        assert header[key] == "", "#{key} should be an empty string, got #{inspect(header[key])}"
      end
    end

    test "trims what it is given" do
      header = ExBkavInvoice.Invoice.to_map(invoice(buyer_tax_code: "  0312345678  "))["Invoice"]

      assert header["BuyerTaxCode"] == "0312345678"
    end

    test "defaults to email delivery, bank transfer and VND" do
      header = ExBkavInvoice.Invoice.to_map(invoice())["Invoice"]

      assert header["ReceiveTypeID"] == 1
      assert header["PayMethodID"] == 2
      assert header["CurrencyID"] == "VND"
      assert header["ExchangeRate"] == 1.0
      assert header["InvoiceTypeID"] == 1
    end

    test "formats the invoice date as ISO 8601" do
      header = ExBkavInvoice.Invoice.to_map(invoice())["Invoice"]

      assert header["InvoiceDate"] == "2026-09-07T10:00:00Z"
    end

    test "dates an invoice that carries no date to now" do
      header = ExBkavInvoice.Invoice.to_map(invoice(date: nil))["Invoice"]

      assert {:ok, _, _} = DateTime.from_iso8601(header["InvoiceDate"])
    end

    test "renders each line with its net amount and tax kept apart" do
      detail = %ExBkavInvoice.InvoiceDetail{
        name: "Vé sự kiện",
        unit_name: "Vé",
        quantity: 2,
        unit_price: 50,
        amount: 100,
        tax_rate_id: 3,
        tax_rate: 10.0,
        tax_amount: 10
      }

      assert [rendered] =
               ExBkavInvoice.Invoice.to_map(invoice(details: [detail]))["ListInvoiceDetailsWS"]

      assert rendered["ItemName"] == "Vé sự kiện"
      assert rendered["Qty"] == 2
      assert rendered["Price"] == 50
      assert rendered["Amount"] == 100
      assert rendered["TaxRateID"] == 3
      assert rendered["TaxRate"] == 10.0
      assert rendered["TaxAmount"] == 10
      assert rendered["IsDiscount"] == false
    end

    test "sends no lines and no attachments as empty lists" do
      map = ExBkavInvoice.Invoice.to_map(invoice())

      assert map["ListInvoiceDetailsWS"] == []
      assert map["ListInvoiceAttachFileWS"] == []
    end
  end

  test "create/3 accepts the struct and sends what to_map/1 renders" do
    config = ExBkavInvoice.Fixtures.config()

    plug = fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)

      [payload] =
        ~r{<EncryptedCommandData>(.*?)</EncryptedCommandData>}s
        |> Regex.run(body, capture: :all_but_first)

      {:ok, json} = ExBkavInvoice.Codec.decode(ExBkavInvoice.Soap.unescape(payload), config)
      %{"CommandObject" => [sent]} = Jason.decode!(json)

      assert sent["PartnerInvoiceStringID"] == "order-1"
      assert sent["Invoice"]["BuyerTaxCode"] == "0312345678"

      body = %{
        "Status" => 0,
        "isOk" => true,
        "Object" => [%{"Status" => 0, "InvoiceGUID" => "g", "MTC" => "m"}]
      }

      Plug.Conn.resp(conn, 200, ExBkavInvoice.Fixtures.soap_response(body, config))
    end

    assert {:ok, result} =
             ExBkavInvoice.Invoices.create(
               ExBkavInvoice.Fixtures.config(req_options: [plug: plug]),
               invoice()
             )

    assert result.lookup_code == "m"
  end
end
