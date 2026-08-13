defmodule ExBkavInvoice.Fixtures do
  @moduledoc false

  # A syntactically valid PartnerToken: 32 base64 bytes of key, 16 of IV.
  @key :binary.copy(<<7>>, 32)
  @iv :binary.copy(<<3>>, 16)

  def key, do: @key
  def iv, do: @iv

  def token, do: Base.encode64(@key) <> ":" <> Base.encode64(@iv)

  def config(opts \\ []) do
    [
      partner_guid: "d414d2d2-74d0-4417-a1a2-38f589822c98",
      partner_token: token(),
      endpoint: :demo
    ]
    |> Keyword.merge(opts)
    |> ExBkavInvoice.Config.new!()
  end

  @doc "Builds the SOAP envelope eHoadon would answer with, carrying `body` as JSON."
  def soap_response(body, config, operation \\ :execute_command) do
    {:ok, payload} = body |> Jason.encode!() |> ExBkavInvoice.Codec.encode(config)
    element = element_name(operation)

    """
    <?xml version="1.0" encoding="utf-8"?>
    <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
      <soap:Body>
        <#{element}ExBkavInvoice.Response xmlns="http://tempuri.org/">
          <#{element}Result>#{payload}</#{element}Result>
        </#{element}ExBkavInvoice.Response>
      </soap:Body>
    </soap:Envelope>
    """
  end

  defp element_name(:execute_command), do: "ExecuteCommand"
  defp element_name(:exec_command), do: "ExecCommand"

  @doc "The successful create-invoice response from Bkav's sample code."
  def create_invoice_body do
    %{
      "Status" => 0,
      "Object" =>
        Jason.encode!([
          %{
            "PartnerInvoiceID" => 1,
            "PartnerInvoiceStringID" => "",
            "InvoiceGUID" => "9ebd0c34-8ac4-40b3-9cf9-da800da38af9",
            "InvoiceForm" => "01GTKT0/001",
            "InvoiceSerial" => "AB/19E",
            "InvoiceNo" => 1,
            "MTC" => "RTO9YKG38",
            "Status" => 0,
            "MessLog" => ""
          }
        ]),
      "isOk" => true,
      "isError" => false
    }
  end
end
