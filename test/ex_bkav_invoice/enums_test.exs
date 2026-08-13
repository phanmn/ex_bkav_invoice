defmodule ExBkavInvoice.EnumsTest do
  use ExUnit.Case, async: true

  doctest ExBkavInvoice.Enums

  describe "lookups" do
    test "label known ids" do
      assert ExBkavInvoice.Enums.invoice_status(2) == "Đã phát hành"
      assert ExBkavInvoice.Enums.tax_status(33) == "Thuế đã duyệt"
      assert ExBkavInvoice.Enums.invoice_type(1) == "Hóa đơn Giá trị gia tăng"
      assert ExBkavInvoice.Enums.pay_method(3) == "TM/CK"
      assert ExBkavInvoice.Enums.item_type(0) == "Hàng hoá dịch vụ"
      assert ExBkavInvoice.Enums.receive_type(3) == "Email & SMS"
    end

    test "return nil for unknown ids rather than raising" do
      assert ExBkavInvoice.Enums.invoice_status(999) == nil
      assert ExBkavInvoice.Enums.tax_status(-1) == nil
      assert ExBkavInvoice.Enums.pay_method(37) == nil
    end
  end

  describe "tax_rate/1" do
    test "maps the ordinary VAT rates" do
      assert ExBkavInvoice.Enums.tax_rate(1) == 0.0
      assert ExBkavInvoice.Enums.tax_rate(2) == 5.0
      assert ExBkavInvoice.Enums.tax_rate(3) == 10.0
      assert ExBkavInvoice.Enums.tax_rate(9) == 8.0
    end

    test "keeps the negative sentinels for non-taxed categories" do
      assert ExBkavInvoice.Enums.tax_rate(4) == -1.0
      assert ExBkavInvoice.Enums.tax_rate(5) == -2.0
      assert ExBkavInvoice.Enums.tax_rate(6) == -4.0
    end

    test "every rate id has a matching label" do
      for id <- Map.keys(ExBkavInvoice.Enums.tax_rates()) do
        assert ExBkavInvoice.Enums.tax_rate_label(id), "TaxRateID #{id} has no label"
      end
    end
  end

  describe "issued?/1" do
    test "true for statuses that mean the invoice has been signed" do
      assert ExBkavInvoice.Enums.issued?(2)
      assert ExBkavInvoice.Enums.issued?(6)
      assert ExBkavInvoice.Enums.issued?(8)
      assert ExBkavInvoice.Enums.issued?(15)
    end

    test "false for drafts and numbered-but-unsigned invoices" do
      refute ExBkavInvoice.Enums.issued?(1)
      refute ExBkavInvoice.Enums.issued?(11)
      refute ExBkavInvoice.Enums.issued?(5)
      refute ExBkavInvoice.Enums.issued?(7)
    end
  end
end
