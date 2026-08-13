defmodule ExBkavInvoice.ResponseTest do
  use ExUnit.Case, async: true

  describe "parse/1" do
    test "decodes an Object that arrives as a JSON string" do
      body = %{
        "Status" => 0,
        "Object" => ~s([{"InvoiceGUID":"abc","Status":0,"MessLog":""}]),
        "isOk" => true,
        "isError" => false
      }

      assert {:ok, response} = ExBkavInvoice.Response.parse(body)
      assert [%{"InvoiceGUID" => "abc"}] = response.object
    end

    test "leaves a non-JSON string Object alone" do
      body = %{"Status" => 0, "Object" => "/Invoice_View/C23TYY-00000007.pdf", "isOk" => true}

      assert {:ok, response} = ExBkavInvoice.Response.parse(body)
      assert response.object == "/Invoice_View/C23TYY-00000007.pdf"
    end

    test "keeps a numeric Object as-is" do
      assert {:ok, response} =
               ExBkavInvoice.Response.parse(%{"Status" => 0, "Object" => 2, "isOk" => true})

      assert response.object == 2
    end

    test "keeps a boolean Object as-is" do
      assert {:ok, response} =
               ExBkavInvoice.Response.parse(%{"Status" => 0, "Object" => true, "isOk" => true})

      assert response.object == true
    end

    test "keeps an already-decoded array as-is" do
      body = %{
        "Status" => 0,
        "Object" => [%{"InvoiceGUID" => "abc", "Status" => 0, "Msg" => ""}],
        "isOk" => true
      }

      assert {:ok, response} = ExBkavInvoice.Response.parse(body)
      assert [%{"InvoiceGUID" => "abc"}] = response.object
    end

    test "reports Status 1 as an api error carrying Bkav's code" do
      body = %{
        "Status" => 1,
        "Object" => "Hóa đơn không tồn tại trên hệ thống",
        "Code" => "EHD0000124",
        "isOk" => false,
        "isError" => true
      }

      assert {:error, %ExBkavInvoice.Error{kind: :api, code: "EHD0000124", message: message}} =
               ExBkavInvoice.Response.parse(body)

      assert message == "Hóa đơn không tồn tại trên hệ thống"
    end

    test "trusts isError even when Status says success" do
      body = %{"Status" => 0, "Object" => "boom", "isOk" => false, "isError" => true}

      assert {:error, %ExBkavInvoice.Error{kind: :api}} = ExBkavInvoice.Response.parse(body)
    end

    test "handles the unencrypted credential-mismatch reply" do
      body = %{
        "Status" => 1,
        "Object" => "CommandType is not valid (200)",
        "isOk" => false,
        "isError" => true
      }

      assert {:error, %ExBkavInvoice.Error{kind: :api, message: "CommandType is not valid (200)"}} =
               ExBkavInvoice.Response.parse(body)
    end
  end

  describe "split_results/1" do
    test "separates per-invoice failures from an envelope that reported success" do
      body = %{
        "Status" => 0,
        "isOk" => true,
        "Object" =>
          Jason.encode!([
            %{"PartnerInvoiceID" => 1, "Status" => 0, "MessLog" => ""},
            %{"PartnerInvoiceID" => 2, "Status" => 1, "MessLog" => "Hóa đơn không liên tục"}
          ])
      }

      assert {:ok, response} = ExBkavInvoice.Response.parse(body)
      assert {[ok], [failed]} = ExBkavInvoice.Response.split_results(response)
      assert ok["PartnerInvoiceID"] == 1
      assert failed["MessLog"] == "Hóa đơn không liên tục"
    end

    test "treats a bare map as a single result" do
      assert {:ok, response} =
               ExBkavInvoice.Response.parse(%{
                 "Status" => 0,
                 "Object" => %{"Status" => 0},
                 "isOk" => true
               })

      assert {[_], []} = ExBkavInvoice.Response.split_results(response)
    end

    test "returns empty lists for a scalar Object" do
      assert {:ok, response} =
               ExBkavInvoice.Response.parse(%{"Status" => 0, "Object" => 2, "isOk" => true})

      assert {[], []} = ExBkavInvoice.Response.split_results(response)
    end
  end

  describe "describe_tax_status/1" do
    test "labels the numeric Bkav and tax statuses" do
      body = %{
        "Status" => 0,
        "isOk" => true,
        "Object" => [
          %{
            "BkavStatus" => 2,
            "TaxStatus" => 33,
            "TaxAuthorityCode" => "00968F",
            "ErrorContent" => ""
          }
        ]
      }

      assert {:ok, response} = ExBkavInvoice.Response.parse(body)
      assert [entry] = ExBkavInvoice.Response.describe_tax_status(response)
      assert entry["BkavStatusName"] == "Đã phát hành"
      assert entry["TaxStatusName"] == "Thuế đã duyệt"
    end
  end
end
