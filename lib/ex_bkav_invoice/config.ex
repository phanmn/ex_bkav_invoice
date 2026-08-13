defmodule ExBkavInvoice.Config do
  @moduledoc """
  Connection settings for one Bkav eHoadon endpoint.

  A `PartnerGUID` identifies the *point* sending data to Bkav (a branch, a shop,
  or an individual accountant), so an application that issues invoices for
  several branches holds one config per branch rather than one globally.
  """

  @type t :: %__MODULE__{
          partner_guid: String.t(),
          key: binary(),
          iv: binary(),
          url: String.t(),
          req_options: keyword()
        }

  @enforce_keys [:partner_guid, :key, :iv, :url]
  defstruct [:partner_guid, :key, :iv, :url, req_options: []]

  @doc """
  Builds a config, raising on invalid credentials.

  ## Options

    * `:partner_guid` — required, the GUID Bkav issued for this sending point.
    * `:partner_token` — required, the token Bkav issued, in its native
      `base64(key):base64(iv)` form. Alternatively pass `:key` and `:iv` as raw
      binaries.
    * `:endpoint` — required, the full web-service URL. Which host you talk to is
      deployment configuration, so it comes from you rather than from a name
      baked into this library.
    * `:req_options` — merged into every `Req` request (`:receive_timeout`,
      `:retry`, `:plug` for tests, …).

  ## Examples

      iex> config = ExBkavInvoice.Config.new!(
      ...>   partner_guid: "d414d2d2-74d0-4417-a1a2-38f589822c98",
      ...>   partner_token: "54dSxtErH+vsKKfL4PKaoerNYE6dwzmpzkLAxity8F4=:+bRSEW7FUEnzLy9xjuP5wA==",
      ...>   endpoint: "https://ws.ehoadon.vn/WSPublicEHoaDon.asmx"
      ...> )
      iex> byte_size(config.key)
      32

  Omitting the endpoint is an error rather than a guess:

      iex> ExBkavInvoice.Config.new(
      ...>   partner_guid: "guid",
      ...>   partner_token: "54dSxtErH+vsKKfL4PKaoerNYE6dwzmpzkLAxity8F4=:+bRSEW7FUEnzLy9xjuP5wA=="
      ...> )
      {:error, %ExBkavInvoice.Error{
        kind: :config,
        message: "endpoint is required",
        code: nil,
        reason: nil
      }}
  """
  @spec new!(keyword()) :: t()
  def new!(opts) do
    case new(opts) do
      {:ok, config} -> config
      {:error, error} -> raise error
    end
  end

  @doc """
  Builds a config, returning `{:error, %ExBkavInvoice.Error{}}` on invalid input.
  """
  @spec new(keyword()) :: {:ok, t()} | {:error, ExBkavInvoice.Error.t()}
  def new(opts) do
    with {:ok, guid} <- fetch_guid(opts),
         {:ok, key, iv} <- fetch_secret(opts),
         {:ok, url} <- fetch_url(opts) do
      {:ok,
       %__MODULE__{
         partner_guid: guid,
         key: key,
         iv: iv,
         url: url,
         req_options: Keyword.get(opts, :req_options, [])
       }}
    end
  end

  @doc """
  Splits a `PartnerToken` into its raw AES-256 key and CBC initialisation vector.

  Bkav distributes the token as `base64(key):base64(iv)`; the decoded key must be
  32 bytes (AES-256) and the IV 16 bytes (one AES block).
  """
  @spec parse_token(String.t()) :: {:ok, binary(), binary()} | {:error, ExBkavInvoice.Error.t()}
  def parse_token(token) when is_binary(token) do
    with [key_b64, iv_b64] <- String.split(token, ":", parts: 2),
         {:ok, key} <- decode64(key_b64, "key"),
         {:ok, iv} <- decode64(iv_b64, "IV") do
      validate_sizes(key, iv)
    else
      {:error, %ExBkavInvoice.Error{}} = error ->
        error

      _ ->
        {:error,
         ExBkavInvoice.Error.config("partner_token must look like base64(key):base64(iv)")}
    end
  end

  def parse_token(_), do: {:error, ExBkavInvoice.Error.config("partner_token must be a string")}

  defp validate_sizes(key, iv) do
    cond do
      byte_size(key) != 32 ->
        {:error,
         ExBkavInvoice.Error.config(
           "partner_token key must decode to 32 bytes, got #{byte_size(key)}"
         )}

      byte_size(iv) != 16 ->
        {:error,
         ExBkavInvoice.Error.config(
           "partner_token IV must decode to 16 bytes, got #{byte_size(iv)}"
         )}

      true ->
        {:ok, key, iv}
    end
  end

  defp decode64(value, label) do
    case Base.decode64(String.trim(value)) do
      {:ok, decoded} -> {:ok, decoded}
      :error -> {:error, ExBkavInvoice.Error.config("partner_token #{label} is not valid base64")}
    end
  end

  defp fetch_guid(opts) do
    case Keyword.get(opts, :partner_guid) do
      guid when is_binary(guid) and guid != "" -> {:ok, guid}
      _ -> {:error, ExBkavInvoice.Error.config("partner_guid is required")}
    end
  end

  defp fetch_secret(opts) do
    case {Keyword.get(opts, :partner_token), Keyword.get(opts, :key), Keyword.get(opts, :iv)} do
      {nil, key, iv} when is_binary(key) and is_binary(iv) ->
        validate_sizes(key, iv)

      {nil, _, _} ->
        {:error, ExBkavInvoice.Error.config("partner_token (or key and iv) is required")}

      {token, _, _} ->
        parse_token(token)
    end
  end

  # Deliberately has no default. Defaulting to a test host would let a caller who
  # forgot to configure an endpoint succeed at every step while issuing invoices
  # that never reach the real tax authority; defaulting to a live one would be
  # worse. Whichever host you want, say so.
  defp fetch_url(opts) do
    case Keyword.fetch(opts, :endpoint) do
      {:ok, url} when is_binary(url) and url != "" ->
        {:ok, url}

      {:ok, other} ->
        {:error,
         ExBkavInvoice.Error.config("endpoint must be a URL string, got #{inspect(other)}")}

      :error ->
        {:error, ExBkavInvoice.Error.config("endpoint is required")}
    end
  end
end
