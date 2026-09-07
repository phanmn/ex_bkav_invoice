defmodule ExBkavInvoice.Client do
  @moduledoc """
  Carries one command to eHoadon and brings the answer back.

  The full round trip is:

      command map -> JSON -> compress -> AES-256 -> Base64
        -> SOAP envelope -> HTTP POST
        -> *Result element -> Base64 -> decrypt -> decompress -> JSON
        -> ExBkavInvoice.Response
  """

  @doc """
  Runs `cmd_type` with `command_object` and returns the parsed response.

  `command_object` goes into the payload untouched, so it must already match the
  shape Bkav documents for that command — a list of invoice maps for the
  creation commands, a bare GUID string for `800`/`801`, and so on.
  See `ExBkavInvoice.Command.object_input?/1`.

  ## Options

    * `:operation` — `:execute_command` (default) or `:exec_command`. The latter
      sends the command as unencrypted XML and is only useful when reproducing a
      request against Bkav's support team.
    * any other option is merged into the `Req` request for this call.
  """
  @spec exec(
          ExBkavInvoice.Config.t(),
          ExBkavInvoice.Command.name() | integer(),
          term(),
          keyword()
        ) ::
          {:ok, ExBkavInvoice.Response.t()} | {:error, ExBkavInvoice.Error.t()}
  def exec(%ExBkavInvoice.Config{} = config, cmd_type, command_object, opts \\ []) do
    with {:ok, code} <- resolve(cmd_type),
         {:ok, json} <- encode_json(%{"CmdType" => code, "CommandObject" => command_object}),
         {:ok, payload} <- ExBkavInvoice.Codec.encode(json, config),
         {:ok, body} <- post(config, payload, opts),
         {:ok, result} <- ExBkavInvoice.Soap.extract_result(body, operation(opts)),
         {:ok, plaintext} <- ExBkavInvoice.Codec.decode(result, config),
         {:ok, decoded} <- decode_json(plaintext) do
      ExBkavInvoice.Response.parse(decoded)
    end
  end

  @doc """
  Like `exec/4` but raises `ExBkavInvoice.Error` instead of returning it.
  """
  @spec exec!(
          ExBkavInvoice.Config.t(),
          ExBkavInvoice.Command.name() | integer(),
          term(),
          keyword()
        ) :: ExBkavInvoice.Response.t()
  def exec!(%ExBkavInvoice.Config{} = config, cmd_type, command_object, opts \\ []) do
    case exec(config, cmd_type, command_object, opts) do
      {:ok, response} -> response
      {:error, error} -> raise error
    end
  end

  defp post(config, payload, opts) do
    operation = operation(opts)
    envelope = ExBkavInvoice.Soap.envelope(operation, config.partner_guid, payload)

    request_options =
      config.req_options
      |> Keyword.merge(Keyword.drop(opts, [:operation]))
      |> Keyword.merge(
        url: config.url,
        method: :post,
        body: envelope,
        headers: [
          {"content-type", "text/xml; charset=utf-8"},
          {"soapaction", ~s("#{ExBkavInvoice.Soap.soap_action(operation)}")}
        ]
      )

    case Req.request(request_options) do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
        {:ok, to_string(body)}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, ExBkavInvoice.Error.transport("eHoadon returned HTTP #{status}", body)}

      {:error, reason} ->
        {:error, ExBkavInvoice.Error.transport("request to #{config.url} failed", reason)}
    end
  end

  defp resolve(cmd_type) do
    case ExBkavInvoice.Command.resolve(cmd_type) do
      {:ok, code} -> {:ok, code}
      :error -> {:error, ExBkavInvoice.Error.config("unknown command #{inspect(cmd_type)}")}
    end
  end

  defp encode_json(payload) do
    case Jason.encode(payload) do
      {:ok, json} ->
        {:ok, json}

      {:error, reason} ->
        {:error, ExBkavInvoice.Error.codec("could not encode command as JSON", reason)}
    end
  end

  defp decode_json(plaintext) do
    case Jason.decode(plaintext) do
      {:ok, %{} = decoded} -> {:ok, decoded}
      {:ok, other} -> {:error, not_an_envelope(other, plaintext)}
      {:error, reason} -> {:error, not_an_envelope(plaintext, plaintext, reason)}
    end
  end

  # eHoadon does not always answer with the JSON envelope. A request it cannot
  # process at all comes back as a bare sentence, which is a real answer from the
  # service rather than a decoding problem on this side:
  #
  #     Có lỗi xảy ra. Xin vui lòng thử lại sau (lỗi đã được thông báo cho quản
  #     trị) [!|639243877390345577|!] [#428068]
  #
  #     [MessageForUser] PartnerGUID "..." không hợp lệ
  #
  # Reporting those as `:codec` sends the reader looking for a decoding bug and
  # buries the one line saying what eHoadon objected to — including the reference
  # its support team asks for. So anything legible is reported as `:api`, and
  # `:codec` is kept for a body that genuinely says nothing.
  defp not_an_envelope(value, plaintext, reason \\ nil) do
    case message_text(value) do
      nil -> ExBkavInvoice.Error.codec("could not decode the eHoadon response", reason || value)
      text -> ExBkavInvoice.Error.api(text, support_reference(text), plaintext)
    end
  end

  # `[MessageForUser]` marks a message as meant for display; it is not part of
  # what eHoadon says, so it is dropped.
  defp message_text(value) when is_binary(value) do
    if String.valid?(value) do
      value
      |> String.replace_prefix("[MessageForUser]", "")
      |> String.trim()
      |> case do
        "" -> nil
        text -> text
      end
    end
  end

  defp message_text(_value), do: nil

  # Bkav tags a server-side failure with `[#428068]` and its support team asks
  # for that number, so it is lifted into `:code` where callers already look.
  defp support_reference(text) do
    case Regex.run(~r/\[#(\d+)\]/, text, capture: :all_but_first) do
      [reference] -> reference
      nil -> nil
    end
  end

  defp operation(opts), do: Keyword.get(opts, :operation, :execute_command)
end
