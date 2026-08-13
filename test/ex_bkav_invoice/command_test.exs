defmodule ExBkavInvoice.CommandTest do
  use ExUnit.Case, async: true

  doctest ExBkavInvoice.Command

  describe "resolve/1" do
    test "maps the five creation commands to Bkav's codes" do
      assert ExBkavInvoice.Command.resolve(:create_draft) == {:ok, 100}
      assert ExBkavInvoice.Command.resolve(:create_numbered) == {:ok, 101}
      assert ExBkavInvoice.Command.resolve(:create_draft_own_serial) == {:ok, 110}
      assert ExBkavInvoice.Command.resolve(:create_own_number) == {:ok, 111}
      assert ExBkavInvoice.Command.resolve(:create_bkav_number) == {:ok, 112}
    end

    test "passes integers through so unlisted codes still work" do
      assert ExBkavInvoice.Command.resolve(1234) == {:ok, 1234}
    end

    test "rejects unknown names" do
      assert ExBkavInvoice.Command.resolve(:definitely_not_a_command) == :error
      assert ExBkavInvoice.Command.resolve("100") == :error
    end
  end

  describe "all/0" do
    test "codes are unique" do
      codes = ExBkavInvoice.Command.all() |> Map.values()

      assert length(codes) == length(Enum.uniq(codes))
    end
  end

  describe "object_input?/1" do
    test "creation commands take a list of invoice objects" do
      assert ExBkavInvoice.Command.object_input?(:create_draft)
      assert ExBkavInvoice.Command.object_input?(:sign_many)
    end

    test "lookups take a bare identifier" do
      refute ExBkavInvoice.Command.object_input?(:get_invoice)
      refute ExBkavInvoice.Command.object_input?(:get_status)
      refute ExBkavInvoice.Command.object_input?(:sign)
    end
  end
end
