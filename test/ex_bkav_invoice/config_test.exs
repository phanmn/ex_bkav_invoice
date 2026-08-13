defmodule ExBkavInvoice.ConfigTest do
  use ExUnit.Case, async: true

  doctest ExBkavInvoice.Config

  describe "parse_token/1" do
    test "splits Bkav's documented example into a 32-byte key and 16-byte IV" do
      token = "54dSxtErH+vsKKfL4PKaoerNYE6dwzmpzkLAxity8F4=:+bRSEW7FUEnzLy9xjuP5wA=="

      assert {:ok, key, iv} = ExBkavInvoice.Config.parse_token(token)
      assert byte_size(key) == 32
      assert byte_size(iv) == 16
    end

    test "rejects a token without a separator" do
      assert {:error, %ExBkavInvoice.Error{kind: :config, message: message}} =
               ExBkavInvoice.Config.parse_token(Base.encode64(ExBkavInvoice.Fixtures.key()))

      assert message =~ "base64(key):base64(iv)"
    end

    test "rejects a key of the wrong length" do
      token = Base.encode64(<<1, 2, 3>>) <> ":" <> Base.encode64(ExBkavInvoice.Fixtures.iv())

      assert {:error, %ExBkavInvoice.Error{kind: :config, message: message}} =
               ExBkavInvoice.Config.parse_token(token)

      assert message =~ "32 bytes"
    end

    test "rejects an IV of the wrong length" do
      token = Base.encode64(ExBkavInvoice.Fixtures.key()) <> ":" <> Base.encode64(<<1, 2, 3>>)

      assert {:error, %ExBkavInvoice.Error{kind: :config, message: message}} =
               ExBkavInvoice.Config.parse_token(token)

      assert message =~ "16 bytes"
    end

    test "rejects non-base64 halves" do
      assert {:error, %ExBkavInvoice.Error{kind: :config}} =
               ExBkavInvoice.Config.parse_token("not base64:also not")
    end
  end

  describe "new/1" do
    test "defaults to the demo endpoint" do
      assert {:ok, config} =
               ExBkavInvoice.Config.new(
                 partner_guid: "g",
                 partner_token: ExBkavInvoice.Fixtures.token()
               )

      assert config.url == ExBkavInvoice.Config.endpoints().demo
    end

    test "resolves the production endpoint" do
      assert {:ok, config} =
               ExBkavInvoice.Config.new(
                 partner_guid: "g",
                 partner_token: ExBkavInvoice.Fixtures.token(),
                 endpoint: :production
               )

      assert config.url == "https://ws.ehoadon.vn/WSPublicEHoaDon.asmx"
    end

    test "accepts an explicit URL" do
      assert {:ok, config} =
               ExBkavInvoice.Config.new(
                 partner_guid: "g",
                 partner_token: ExBkavInvoice.Fixtures.token(),
                 endpoint: "http://localhost:4001/ws"
               )

      assert config.url == "http://localhost:4001/ws"
    end

    test "accepts raw key and iv instead of a token" do
      assert {:ok, config} =
               ExBkavInvoice.Config.new(
                 partner_guid: "g",
                 key: ExBkavInvoice.Fixtures.key(),
                 iv: ExBkavInvoice.Fixtures.iv()
               )

      assert config.key == ExBkavInvoice.Fixtures.key()
    end

    test "requires a partner_guid" do
      assert {:error, %ExBkavInvoice.Error{kind: :config, message: message}} =
               ExBkavInvoice.Config.new(partner_token: ExBkavInvoice.Fixtures.token())

      assert message =~ "partner_guid"
    end

    test "requires credentials" do
      assert {:error, %ExBkavInvoice.Error{kind: :config, message: message}} =
               ExBkavInvoice.Config.new(partner_guid: "g")

      assert message =~ "partner_token"
    end

    test "rejects an unknown endpoint name" do
      assert {:error, %ExBkavInvoice.Error{kind: :config}} =
               ExBkavInvoice.Config.new(
                 partner_guid: "g",
                 partner_token: ExBkavInvoice.Fixtures.token(),
                 endpoint: :staging
               )
    end
  end

  describe "new!/1" do
    test "raises on invalid input" do
      assert_raise ExBkavInvoice.Error, ~r/partner_guid/, fn -> ExBkavInvoice.Config.new!([]) end
    end
  end
end
