defmodule ExBkavInvoice.SoapTest do
  use ExUnit.Case, async: true

  describe "envelope/3" do
    test "uses the encrypted parameter names for ExecuteCommand" do
      envelope = ExBkavInvoice.Soap.envelope(:execute_command, "guid-1", "cGF5bG9hZA==")

      assert envelope =~ "<ExecuteCommand xmlns=\"http://tempuri.org/\">"
      assert envelope =~ "<PartnerGUID>guid-1</PartnerGUID>"
      assert envelope =~ "<EncryptedCommandData>cGF5bG9hZA==</EncryptedCommandData>"
    end

    test "uses the lowercase guid parameter for ExecCommand" do
      envelope = ExBkavInvoice.Soap.envelope(:exec_command, "guid-1", "<CommandData/>")

      assert envelope =~ "<partnerGUID>guid-1</partnerGUID>"
      assert envelope =~ "<CommandData>"
    end

    test "escapes payload characters that would break the envelope" do
      envelope = ExBkavInvoice.Soap.envelope(:exec_command, "guid", ~s(<a b="c">&</a>))

      assert envelope =~ "&lt;a b=&quot;c&quot;&gt;&amp;&lt;/a&gt;"
      refute envelope =~ ~s(<a b="c">)
    end
  end

  describe "soap_action/1" do
    test "namespaces the operation" do
      assert ExBkavInvoice.Soap.soap_action(:execute_command) ==
               "http://tempuri.org/ExecuteCommand"

      assert ExBkavInvoice.Soap.soap_action(:exec_command) == "http://tempuri.org/ExecCommand"
    end
  end

  describe "extract_result/2" do
    test "pulls the result out of a well-formed response" do
      body = """
      <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
        <soap:Body>
          <ExecuteCommandResponse xmlns="http://tempuri.org/">
            <ExecuteCommandResult>cGF5bG9hZA==</ExecuteCommandResult>
          </ExecuteCommandResponse>
        </soap:Body>
      </soap:Envelope>
      """

      assert {:ok, "cGF5bG9hZA=="} = ExBkavInvoice.Soap.extract_result(body, :execute_command)
    end

    test "unescapes an XML-escaped JSON result" do
      body = """
      <ExecuteCommandResponse><ExecuteCommandResult>{&quot;Status&quot;:1,&quot;Object&quot;:&quot;a &amp; b&quot;}</ExecuteCommandResult></ExecuteCommandResponse>
      """

      assert {:ok, result} = ExBkavInvoice.Soap.extract_result(body, :execute_command)
      assert result == ~s({"Status":1,"Object":"a & b"})
    end

    test "handles a namespace-prefixed result element" do
      body = ~s(<ns:ExecuteCommandResult xmlns:ns="x">abc</ns:ExecuteCommandResult>)

      assert {:ok, "abc"} = ExBkavInvoice.Soap.extract_result(body, :execute_command)
    end

    test "spans newlines inside the result" do
      body = "<ExecuteCommandResult>line one\nline two</ExecuteCommandResult>"

      assert {:ok, "line one\nline two"} =
               ExBkavInvoice.Soap.extract_result(body, :execute_command)
    end

    test "reports a SOAP fault as a soap error" do
      body = """
      <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
        <soap:Body>
          <soap:Fault>
            <faultcode>soap:Server</faultcode>
            <faultstring>Server was unable to process request.</faultstring>
          </soap:Fault>
        </soap:Body>
      </soap:Envelope>
      """

      assert {:error, %ExBkavInvoice.Error{kind: :soap, message: message}} =
               ExBkavInvoice.Soap.extract_result(body, :execute_command)

      assert message == "Server was unable to process request."
    end

    test "reports a body with no result element" do
      assert {:error, %ExBkavInvoice.Error{kind: :soap}} =
               ExBkavInvoice.Soap.extract_result("<html>oops</html>", :execute_command)
    end

    test "does not confuse the two operations' result elements" do
      body = "<ExecCommandResult>abc</ExecCommandResult>"

      assert {:error, %ExBkavInvoice.Error{kind: :soap}} =
               ExBkavInvoice.Soap.extract_result(body, :execute_command)

      assert {:ok, "abc"} = ExBkavInvoice.Soap.extract_result(body, :exec_command)
    end
  end
end
