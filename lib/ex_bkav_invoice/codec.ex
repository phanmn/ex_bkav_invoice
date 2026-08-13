defmodule ExBkavInvoice.Codec do
  @moduledoc """
  The wire encoding eHoadon expects on `EncryptedCommandData`.

  Outbound, per Bkav's integration diagram:

      JSON/XML string -> gzip -> AES-256-CBC -> Base64

  Inbound is the mirror image: Base64 -> decrypt -> gunzip.

  ## Padding

  AES-CBC requires input in whole 16-byte blocks, and the padding is PKCS#7.
  A wrong `PartnerGUID`/`PartnerToken` pair decrypts to bytes whose trailing
  padding is nonsense, which is why eHoadon answers a credential mismatch with
  `"Padding is invalid and cannot be removed"` rather than an auth error.
  """

  @block_size 16

  @doc """
  Compresses, encrypts and base64-encodes `payload` for `EncryptedCommandData`.
  """
  @spec encode(binary(), ExBkavInvoice.Config.t()) ::
          {:ok, String.t()} | {:error, ExBkavInvoice.Error.t()}
  def encode(payload, %ExBkavInvoice.Config{} = config) when is_binary(payload) do
    with {:ok, ciphertext} <- encrypt(:zlib.gzip(payload), config.key, config.iv) do
      {:ok, Base.encode64(ciphertext)}
    end
  end

  @doc """
  Reverses `encode/2`.

  eHoadon does not always encrypt what it sends back — a rejected command type,
  for instance, returns bare JSON — so a body that is not valid base64, or that
  fails to decrypt, is passed through untouched rather than raising.
  """
  @spec decode(binary(), ExBkavInvoice.Config.t()) ::
          {:ok, binary()} | {:error, ExBkavInvoice.Error.t()}
  def decode(body, %ExBkavInvoice.Config{} = config) when is_binary(body) do
    with {:ok, ciphertext} <- decode64(body),
         {:ok, plaintext} <- decrypt(ciphertext, config.key, config.iv) do
      {:ok, decompress(plaintext)}
    else
      {:error, %ExBkavInvoice.Error{kind: :codec}} -> {:ok, body}
      other -> other
    end
  end

  @doc false
  @spec encrypt(binary(), binary(), binary()) ::
          {:ok, binary()} | {:error, ExBkavInvoice.Error.t()}
  def encrypt(data, key, iv) do
    {:ok, :crypto.crypto_one_time(:aes_256_cbc, key, iv, pad(data), true)}
  rescue
    e -> {:error, ExBkavInvoice.Error.codec("AES-256-CBC encryption failed", e)}
  end

  @doc false
  @spec decrypt(binary(), binary(), binary()) ::
          {:ok, binary()} | {:error, ExBkavInvoice.Error.t()}
  def decrypt(data, _key, _iv)
      when byte_size(data) == 0 or rem(byte_size(data), @block_size) != 0,
      do: {:error, ExBkavInvoice.Error.codec("ciphertext is not a whole number of AES blocks")}

  def decrypt(data, key, iv) do
    :aes_256_cbc
    |> :crypto.crypto_one_time(key, iv, data, false)
    |> unpad()
  rescue
    e -> {:error, ExBkavInvoice.Error.codec("AES-256-CBC decryption failed", e)}
  end

  @doc """
  Applies PKCS#7 padding, always adding at least one byte.
  """
  @spec pad(binary()) :: binary()
  def pad(data) do
    padding = @block_size - rem(byte_size(data), @block_size)
    data <> :binary.copy(<<padding>>, padding)
  end

  @doc """
  Strips PKCS#7 padding, rejecting any block whose trailer is inconsistent.
  """
  @spec unpad(binary()) :: {:ok, binary()} | {:error, ExBkavInvoice.Error.t()}
  def unpad(data) when byte_size(data) > 0 do
    padding = :binary.last(data)

    if padding in 1..@block_size and padding <= byte_size(data) do
      size = byte_size(data) - padding
      <<body::binary-size(size), trailer::binary>> = data

      if trailer == :binary.copy(<<padding>>, padding) do
        {:ok, body}
      else
        {:error, ExBkavInvoice.Error.codec("Padding is invalid and cannot be removed")}
      end
    else
      {:error, ExBkavInvoice.Error.codec("Padding is invalid and cannot be removed")}
    end
  end

  def unpad(_),
    do: {:error, ExBkavInvoice.Error.codec("Padding is invalid and cannot be removed")}

  @doc """
  Gunzips `data`, returning it unchanged when it carries no gzip header.

  Not every response is compressed — some error replies come back as bare JSON —
  so this leans on the two-byte gzip magic rather than assuming.
  """
  @spec decompress(binary()) :: binary()
  def decompress(<<0x1F, 0x8B, _::binary>> = data) do
    :zlib.gunzip(data)
  rescue
    _ -> data
  end

  def decompress(data), do: data

  defp decode64(body) do
    case Base.decode64(body, ignore: :whitespace) do
      {:ok, decoded} -> {:ok, decoded}
      :error -> {:error, ExBkavInvoice.Error.codec("response body is not base64")}
    end
  end
end
