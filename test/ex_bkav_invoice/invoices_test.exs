defmodule ExBkavInvoice.InvoicesTest do
  use ExUnit.Case, async: true

  doctest ExBkavInvoice.InvoiceResult

  defp responding(body) do
    config = ExBkavInvoice.Fixtures.config()

    plug = fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("text/xml")
      |> Plug.Conn.resp(200, ExBkavInvoice.Fixtures.soap_response(body, config))
    end

    ExBkavInvoice.Fixtures.config(req_options: [plug: plug])
  end

  defp envelope(object),
    do: %{"Status" => 0, "isOk" => true, "isError" => false, "Object" => object}

  defp created(overrides \\ %{}) do
    envelope([
      Map.merge(
        %{
          "Status" => 0,
          "InvoiceGUID" => "9ebd0c34-8ac4-40b3-9cf9-da800da38af9",
          "InvoiceForm" => "01GTKT0/001",
          "InvoiceSerial" => "AB/19E",
          "InvoiceNo" => 0,
          "MTC" => "RTO9YKG38",
          "PartnerInvoiceStringID" => "order-1"
        },
        overrides
      )
    ])
  end

  describe "create/3" do
    test "returns what eHoadon allocated, in named fields" do
      assert {:ok, result} = ExBkavInvoice.Invoices.create(responding(created()), %{})

      assert result == %ExBkavInvoice.InvoiceResult{
               guid: "9ebd0c34-8ac4-40b3-9cf9-da800da38af9",
               form: "01GTKT0/001",
               serial: "AB/19E",
               no: 0,
               lookup_code: "RTO9YKG38",
               partner_invoice_id: nil,
               partner_invoice_string_id: "order-1"
             }
    end

    # The envelope says Status 0 while the one invoice inside it failed; reading
    # only the envelope would report a success carrying no invoice at all.
    test "reports a per-invoice failure even when the envelope succeeded" do
      config = responding(created(%{"Status" => 1, "MessLog" => "Mã số thuế không hợp lệ"}))

      assert {:error, error} = ExBkavInvoice.Invoices.create(config, %{})
      assert error.message == "Mã số thuế không hợp lệ"
      assert error.kind == :api
      # Bkav's per-invoice result carries no code of its own.
      assert error.code == nil
      # The invoice has to change before another attempt means anything.
      refute ExBkavInvoice.Error.retryable?(error)
    end

    test "falls back to a stated reason when a rejection carries no message" do
      config = responding(created(%{"Status" => 1, "MessLog" => ""}))

      assert {:error, %{message: "eHoadon rejected the invoice"}} =
               ExBkavInvoice.Invoices.create(config, %{})
    end

    test "reports an envelope with no invoice in it" do
      config = responding(envelope([]))

      assert {:error, %{message: "eHoadon returned no invoice result"}} =
               ExBkavInvoice.Invoices.create(config, %{})
    end

    test "keeps Bkav's error code as a field rather than burying it in the text" do
      config =
        responding(%{
          "Status" => 1,
          "Object" => "Hóa đơn không tồn tại",
          "Code" => "EHD0000124",
          "isOk" => false,
          "isError" => true
        })

      assert {:error, error} = ExBkavInvoice.Invoices.create(config, %{})
      assert error.message == "Hóa đơn không tồn tại"
      assert error.code == "EHD0000124"
      assert error.kind == :api
      refute ExBkavInvoice.Error.retryable?(error)
    end

    test "reports a transport failure as a plain message" do
      config =
        ExBkavInvoice.Fixtures.config(
          req_options: [plug: fn conn -> Plug.Conn.resp(conn, 500, "boom") end, retry: false]
        )

      assert {:error, error} = ExBkavInvoice.Invoices.create(config, %{})
      assert error.message =~ "HTTP 500"
      assert error.kind == :transport
      # A call that never completed is the one failure worth repeating.
      assert ExBkavInvoice.Error.retryable?(error)
    end

    # The plain-text server failure carries its support reference in [#...],
    # which is what Bkav asks for; it belongs in a field, not only in prose.
    test "lifts the support reference out of a plain-text server failure" do
      text =
        "Có lỗi xảy ra. Xin vui lòng thử lại sau (lỗi đã được thông báo cho quản trị) " <>
          "[!|639243877390345577|!] [#428068]"

      plug = fn conn ->
        Plug.Conn.resp(conn, 200, ExBkavInvoice.Fixtures.plain_soap_response(text))
      end

      config = ExBkavInvoice.Fixtures.config(req_options: [plug: plug])

      assert {:error, error} = ExBkavInvoice.Invoices.create(config, %{})
      assert error.code == "428068"
      assert error.message == text
      assert error.kind == :api
    end

    test "empties eHoadon's blank strings rather than storing them" do
      config = responding(created(%{"InvoiceSerial" => "", "MTC" => ""}))

      assert {:ok, result} = ExBkavInvoice.Invoices.create(config, %{})
      assert result.serial == nil
      assert result.lookup_code == nil
    end
  end

  describe "sign/3" do
    test "answers :ok when eHoadon signed the invoice" do
      assert :ok = ExBkavInvoice.Invoices.sign(responding(envelope(true)), "guid")
    end

    test "reports a signing refusal as a plain message" do
      config =
        responding(%{"Status" => 1, "Object" => "no HSM", "isOk" => false, "isError" => true})

      assert {:error, error} = ExBkavInvoice.Invoices.sign(config, "guid")
      assert error.message =~ "no HSM"
      assert error.kind == :api
    end
  end
end
