defmodule ExBkavInvoice.ErrorTest do
  use ExUnit.Case, async: true

  doctest ExBkavInvoice.Error

  describe "retryable?/1" do
    test "only a call that did not complete is worth repeating" do
      assert ExBkavInvoice.Error.retryable?(ExBkavInvoice.Error.transport("timeout"))

      refute ExBkavInvoice.Error.retryable?(ExBkavInvoice.Error.api("rejected"))
      refute ExBkavInvoice.Error.retryable?(ExBkavInvoice.Error.config("no endpoint"))
      refute ExBkavInvoice.Error.retryable?(ExBkavInvoice.Error.codec("unreadable"))
      refute ExBkavInvoice.Error.retryable?(ExBkavInvoice.Error.soap("fault"))
    end
  end
end
