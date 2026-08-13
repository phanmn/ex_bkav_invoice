defmodule ExBkavInvoice.Soap do
  @moduledoc """
  Envelope building and result extraction for `WSPublicEHoaDon.asmx`.

  The service exposes two operations that differ only in whether the payload is
  protected:

    * `ExecuteCommand(PartnerGUID, EncryptedCommandData)` — the compressed,
      encrypted, base64 payload described in `ExBkavInvoice.Codec`.
    * `ExecCommand(partnerGUID, CommandData)` — the same command as plain XML.
      Bkav documents it for debugging; it puts invoice data on the wire in the
      clear, so `ExBkavInvoice` only uses `ExecuteCommand`.

  Note the casing difference on the GUID parameter between the two: `PartnerGUID`
  for one, `partnerGUID` for the other. The service is case-sensitive.
  """

  @namespace "http://tempuri.org/"

  @type operation :: :execute_command | :exec_command

  @doc """
  Wraps `payload` in a SOAP 1.1 envelope for `operation`.
  """
  @spec envelope(operation(), String.t(), String.t()) :: String.t()
  def envelope(operation, partner_guid, payload) do
    {action, guid_param, data_param} = parts(operation)

    """
    <?xml version="1.0" encoding="utf-8"?>
    <soap:Envelope xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
      <soap:Body>
        <#{action} xmlns="#{@namespace}">
          <#{guid_param}>#{escape(partner_guid)}</#{guid_param}>
          <#{data_param}>#{escape(payload)}</#{data_param}>
        </#{action}>
      </soap:Body>
    </soap:Envelope>
    """
  end

  @doc """
  The `SOAPAction` header value for `operation`.
  """
  @spec soap_action(operation()) :: String.t()
  def soap_action(operation) do
    {action, _, _} = parts(operation)
    @namespace <> action
  end

  @doc """
  Pulls the `*Result` string out of a response envelope.

  A `soap:Fault` is reported as `{:error, %ExBkavInvoice.Error{kind: :soap}}` with
  the fault string as the message.
  """
  @spec extract_result(binary(), operation()) ::
          {:ok, String.t()} | {:error, ExBkavInvoice.Error.t()}
  def extract_result(body, operation) when is_binary(body) do
    {action, _, _} = parts(operation)

    case capture(body, "#{action}Result") do
      {:ok, result} -> {:ok, unescape(result)}
      :error -> fault_or_error(body)
    end
  end

  defp fault_or_error(body) do
    case capture(body, "faultstring") do
      {:ok, fault} -> {:error, ExBkavInvoice.Error.soap(unescape(fault))}
      :error -> {:error, ExBkavInvoice.Error.soap("no result element in SOAP response", body)}
    end
  end

  # The result is a single text node, so a non-greedy scan between the tags is
  # enough and avoids pulling in an XML parser (and its entity-expansion
  # surface) for a one-element extraction. Namespace prefixes are optional on
  # both the element and the closing tag.
  defp capture(body, tag) do
    ~r{<(?:[\w.-]+:)?#{tag}(?:\s[^>]*)?>(.*?)</(?:[\w.-]+:)?#{tag}>}s
    |> Regex.run(body, capture: :all_but_first)
    |> case do
      [captured] -> {:ok, captured}
      _ -> :error
    end
  end

  defp parts(:execute_command), do: {"ExecuteCommand", "PartnerGUID", "EncryptedCommandData"}
  defp parts(:exec_command), do: {"ExecCommand", "partnerGUID", "CommandData"}

  @doc false
  @spec escape(String.t()) :: String.t()
  def escape(value) do
    value
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&apos;")
  end

  @doc false
  @spec unescape(String.t()) :: String.t()
  def unescape(value) do
    value
    |> String.replace("&lt;", "<")
    |> String.replace("&gt;", ">")
    |> String.replace("&quot;", "\"")
    |> String.replace("&apos;", "'")
    |> String.replace("&amp;", "&")
  end
end
