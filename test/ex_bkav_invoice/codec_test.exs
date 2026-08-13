defmodule ExBkavInvoice.CodecTest do
  use ExUnit.Case, async: true

  doctest ExBkavInvoice.Codec

  setup do
    {:ok, config: ExBkavInvoice.Fixtures.config()}
  end

  describe "encode/2 and decode/2" do
    test "round-trip returns the original payload", %{config: config} do
      payload = ~s({"CmdType":100,"CommandObject":[]})

      assert {:ok, encoded} = ExBkavInvoice.Codec.encode(payload, config)
      assert {:ok, ^payload} = ExBkavInvoice.Codec.decode(encoded, config)
    end

    test "round-trips multi-byte Vietnamese text", %{config: config} do
      payload = ~s({"BuyerUnitName":"CÔNG TY CỔ PHẦN BKAV — Hà Nội"})

      assert {:ok, encoded} = ExBkavInvoice.Codec.encode(payload, config)
      assert {:ok, ^payload} = ExBkavInvoice.Codec.decode(encoded, config)
    end

    test "output is base64", %{config: config} do
      assert {:ok, encoded} = ExBkavInvoice.Codec.encode("payload", config)
      assert {:ok, _} = Base.decode64(encoded)
    end

    test "round-trips under every compression setting" do
      for compression <- [:gzip, :deflate, :zlib, :none] do
        config = ExBkavInvoice.Fixtures.config(compression: compression)
        payload = String.duplicate("hoá đơn ", 200)

        assert {:ok, encoded} = ExBkavInvoice.Codec.encode(payload, config)

        assert {:ok, ^payload} = ExBkavInvoice.Codec.decode(encoded, config),
               "failed for #{compression}"
      end
    end

    test "decodes a response compressed differently from the request", %{config: config} do
      deflate_config = ExBkavInvoice.Fixtures.config(compression: :deflate)
      payload = ~s({"Status":0})

      # The service answered with gzip while this config sends deflate.
      assert {:ok, encoded} = ExBkavInvoice.Codec.encode(payload, config)
      assert {:ok, ^payload} = ExBkavInvoice.Codec.decode(encoded, deflate_config)
    end
  end

  describe "decode/2 with unexpected bodies" do
    test "passes through plaintext JSON", %{config: config} do
      # eHoadon returns a rejected command type as bare, unencrypted JSON.
      body =
        Jason.encode!(%{
          "Status" => 1,
          "Object" => "CommandType is not valid (200)",
          "isOk" => false
        })

      assert {:ok, ^body} = ExBkavInvoice.Codec.decode(body, config)
    end

    test "passes the body through when the credentials do not match", %{config: config} do
      other =
        ExBkavInvoice.Fixtures.config(
          key: :binary.copy(<<9>>, 32),
          iv: ExBkavInvoice.Fixtures.iv(),
          partner_token: nil
        )

      assert {:ok, encoded} = ExBkavInvoice.Codec.encode(~s({"Status":0}), config)
      assert {:ok, passed_through} = ExBkavInvoice.Codec.decode(encoded, other)
      assert passed_through == encoded
    end
  end

  describe "pad/1 and unpad/1" do
    test "always adds padding, even on an exact block boundary" do
      exact = :binary.copy("a", 16)

      assert byte_size(ExBkavInvoice.Codec.pad(exact)) == 32
      assert {:ok, ^exact} = ExBkavInvoice.Codec.unpad(ExBkavInvoice.Codec.pad(exact))
    end

    test "round-trips every length within a block" do
      for size <- 0..32 do
        data = :binary.copy("x", size)
        padded = ExBkavInvoice.Codec.pad(data)

        assert rem(byte_size(padded), 16) == 0
        assert {:ok, ^data} = ExBkavInvoice.Codec.unpad(padded)
      end
    end

    test "rejects an inconsistent trailer with Bkav's own wording" do
      assert {:error, %ExBkavInvoice.Error{kind: :codec, message: message}} =
               ExBkavInvoice.Codec.unpad(<<1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 4, 4>>)

      assert message == "Padding is invalid and cannot be removed"
    end

    test "rejects an empty input" do
      assert {:error, %ExBkavInvoice.Error{kind: :codec}} = ExBkavInvoice.Codec.unpad("")
    end

    test "rejects a padding byte larger than the block size" do
      assert {:error, %ExBkavInvoice.Error{kind: :codec}} =
               ExBkavInvoice.Codec.unpad(:binary.copy(<<200>>, 16))
    end
  end

  describe "decrypt/3" do
    test "rejects ciphertext that is not a whole number of blocks", %{config: config} do
      assert {:error, %ExBkavInvoice.Error{kind: :codec, message: message}} =
               ExBkavInvoice.Codec.decrypt("short", config.key, config.iv)

      assert message =~ "whole number of AES blocks"
    end
  end

  describe "decompress/2" do
    test "recognises gzip regardless of the configured algorithm" do
      compressed = :zlib.gzip("hello")

      assert {:ok, "hello"} = ExBkavInvoice.Codec.decompress(compressed, :deflate)
    end

    test "recognises a zlib stream regardless of the configured algorithm" do
      compressed = :zlib.compress("hello")

      assert {:ok, "hello"} = ExBkavInvoice.Codec.decompress(compressed, :gzip)
    end

    test "leaves uncompressed data alone when it cannot be inflated" do
      assert {:ok, "not compressed at all"} =
               ExBkavInvoice.Codec.decompress("not compressed at all", :gzip)
    end
  end
end
