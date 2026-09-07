defmodule ExBkavInvoice.ClientTest do
  use ExUnit.Case, async: true

  # Stands in for eHoadon: decrypts what the client sent, hands it to `handler`,
  # and encrypts whatever comes back — so a test exercises the whole pipeline
  # rather than a mocked-out middle.
  defp endpoint(config, handler) do
    fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      payload = sent_payload(body)
      {:ok, json} = ExBkavInvoice.Codec.decode(payload, config)
      command = Jason.decode!(json)

      conn
      |> Plug.Conn.put_resp_content_type("text/xml")
      |> Plug.Conn.resp(
        200,
        ExBkavInvoice.Fixtures.soap_response(handler.(command, conn), config)
      )
    end
  end

  defp config_with(handler) do
    config = ExBkavInvoice.Fixtures.config()
    ExBkavInvoice.Fixtures.config(req_options: [plug: endpoint(config, handler)])
  end

  describe "exec/4" do
    test "sends the resolved CmdType and the command object" do
      config = config_with(fn command, _conn -> send_back(command) end)

      assert {:ok, response} =
               ExBkavInvoice.Client.exec(config, :create_own_number, [%{"a" => 1}])

      assert response.object["CmdType"] == 111
      assert response.object["CommandObject"] == [%{"a" => 1}]
    end

    test "passes a numeric CmdType through untouched" do
      config = config_with(fn command, _conn -> send_back(command) end)

      assert {:ok, response} = ExBkavInvoice.Client.exec(config, 853, %{"PageNumber" => 1})
      assert response.object["CmdType"] == 853
    end

    test "sets the SOAP action header for the operation" do
      config =
        config_with(fn _command, conn ->
          [action] = Plug.Conn.get_req_header(conn, "soapaction")
          %{"Status" => 0, "Object" => action, "isOk" => true}
        end)

      assert {:ok, response} = ExBkavInvoice.Client.exec(config, :get_status, "guid")
      assert response.object == ~s("http://tempuri.org/ExecuteCommand")
    end

    test "parses a real create-invoice response" do
      config = config_with(fn _command, _conn -> ExBkavInvoice.Fixtures.create_invoice_body() end)

      assert {:ok, response} = ExBkavInvoice.Client.exec(config, :create_draft, [])
      assert {[created], []} = ExBkavInvoice.Response.split_results(response)
      assert created["InvoiceGUID"] == "9ebd0c34-8ac4-40b3-9cf9-da800da38af9"
      assert created["MTC"] == "RTO9YKG38"
    end

    test "surfaces an api error with its code" do
      body = %{
        "Status" => 1,
        "Object" => "Hóa đơn không tồn tại trên hệ thống",
        "Code" => "EHD0000124",
        "isOk" => false,
        "isError" => true
      }

      config = config_with(fn _command, _conn -> body end)

      assert {:error, %ExBkavInvoice.Error{kind: :api, code: "EHD0000124"}} =
               ExBkavInvoice.Client.exec(config, :sign, "missing-guid")
    end

    test "rejects an unknown command before touching the network" do
      config =
        ExBkavInvoice.Fixtures.config(
          req_options: [plug: fn _ -> flunk("should not be called") end]
        )

      assert {:error, %ExBkavInvoice.Error{kind: :config, message: message}} =
               ExBkavInvoice.Client.exec(config, :not_a_command, [])

      assert message =~ "unknown command"
    end

    test "reports a non-2xx response as a transport error" do
      plug = fn conn -> Plug.Conn.resp(conn, 500, "boom") end
      config = ExBkavInvoice.Fixtures.config(req_options: [plug: plug, retry: false])

      assert {:error, %ExBkavInvoice.Error{kind: :transport, message: message}} =
               ExBkavInvoice.Client.exec(config, :get_status, "guid")

      assert message =~ "HTTP 500"
    end

    test "reports a SOAP fault" do
      fault = """
      <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
        <soap:Body><soap:Fault><faultstring>Server error</faultstring></soap:Fault></soap:Body>
      </soap:Envelope>
      """

      plug = fn conn -> Plug.Conn.resp(conn, 200, fault) end
      config = ExBkavInvoice.Fixtures.config(req_options: [plug: plug])

      assert {:error, %ExBkavInvoice.Error{kind: :soap, message: "Server error"}} =
               ExBkavInvoice.Client.exec(config, :get_status, "guid")
    end

    test "handles an unencrypted error reply" do
      # A GUID/token mismatch comes back as bare JSON, not an encrypted payload.
      body =
        Jason.encode!(%{
          "Status" => 1,
          "Object" => "CommandType is not valid (200)",
          "isOk" => false,
          "isError" => true
        })

      plug = fn conn ->
        Plug.Conn.resp(conn, 200, "<ExecuteCommandResult>#{body}</ExecuteCommandResult>")
      end

      config = ExBkavInvoice.Fixtures.config(req_options: [plug: plug])

      assert {:error, %ExBkavInvoice.Error{kind: :api, message: "CommandType is not valid (200)"}} =
               ExBkavInvoice.Client.exec(config, :get_status, "guid")
    end

    # A request eHoadon cannot process is answered with a sentence rather than
    # the JSON envelope. That is eHoadon refusing, not a decoding problem here,
    # and reporting it as `:codec` would hide what it said.
    test "reports a plain-text refusal as an api error carrying eHoadon's words" do
      text = ExBkavInvoice.Fixtures.server_error_text()
      config = plain_reply(text)

      assert {:error, %ExBkavInvoice.Error{} = error} =
               ExBkavInvoice.Client.exec(config, :create_draft, [])

      assert error.kind == :api
      assert error.message == text
      # Bkav's support team asks for this reference.
      assert error.code == "428068"
      assert error.reason == text
    end

    test "drops the display marker from a refusal meant to be shown" do
      config = plain_reply(~s([MessageForUser] PartnerGUID "0000" không hợp lệ))

      assert {:error, %ExBkavInvoice.Error{kind: :api} = error} =
               ExBkavInvoice.Client.exec(config, :get_status, "guid")

      assert error.message == ~s(PartnerGUID "0000" không hợp lệ)
      assert error.code == nil
    end

    test "reports a bare JSON string refusal as an api error" do
      plug = fn conn ->
        Plug.Conn.resp(conn, 200, "<ExecuteCommandResult>\"sai token\"</ExecuteCommandResult>")
      end

      config = ExBkavInvoice.Fixtures.config(req_options: [plug: plug])

      assert {:error, %ExBkavInvoice.Error{kind: :api, message: "sai token"}} =
               ExBkavInvoice.Client.exec(config, :get_status, "guid")
    end

    # Nothing was said, so there is nothing to report but the decoding failure.
    test "still reports a codec error when the reply says nothing" do
      config = plain_reply("   ")

      assert {:error, %ExBkavInvoice.Error{kind: :codec, message: message}} =
               ExBkavInvoice.Client.exec(config, :get_status, "guid")

      assert message =~ "could not decode"
    end

    test "still reports a codec error for a reply that is not text" do
      config = plain_reply(<<0xFF, 0xFE, 0xFD>>)

      assert {:error, %ExBkavInvoice.Error{kind: :codec}} =
               ExBkavInvoice.Client.exec(config, :get_status, "guid")
    end
  end

  defp plain_reply(text) do
    plug = fn conn ->
      Plug.Conn.resp(conn, 200, ExBkavInvoice.Fixtures.plain_soap_response(text))
    end

    ExBkavInvoice.Fixtures.config(req_options: [plug: plug])
  end

  describe "exec!/4" do
    test "raises on error" do
      config =
        ExBkavInvoice.Fixtures.config(req_options: [plug: fn _ -> flunk("unreachable") end])

      assert_raise ExBkavInvoice.Error, ~r/unknown command/, fn ->
        ExBkavInvoice.Client.exec!(config, :nope, [])
      end
    end
  end

  defp send_back(command) do
    %{"Status" => 0, "Object" => Jason.encode!(command), "isOk" => true, "isError" => false}
  end

  defp sent_payload(body) do
    [payload] =
      Regex.run(~r{<EncryptedCommandData>(.*?)</EncryptedCommandData>}s, body,
        capture: :all_but_first
      )

    payload
  end
end
