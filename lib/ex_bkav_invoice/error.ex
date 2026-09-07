defmodule ExBkavInvoice.Error do
  @moduledoc """
  A failure anywhere in the request pipeline.

  `:kind` says *where* it went wrong, which is what usually decides whether a
  retry can help:

    * `:config` — bad credentials or options; retrying will not help.
    * `:codec` — compress/encrypt/encode failed, or a response said nothing that
      could be read. A GUID or token mismatch surfaces here as
      `"Padding is invalid and cannot be removed"`.
    * `:transport` — the HTTP call itself failed; usually retryable.
    * `:soap` — a SOAP fault, or a body without a result element.
    * `:api` — the call reached eHoadon and it refused. Usually that is
      `Status: 1` in the JSON envelope, but a request eHoadon cannot process at
      all is answered with a bare sentence instead, and that is reported here
      too — the message is then eHoadon's own words. `:code` holds Bkav's error
      code (e.g. `"EHD0000124"`), or the `[#428068]` support reference from a
      plain-text refusal, when present.
  """

  @type kind :: :config | :codec | :transport | :soap | :api

  @type t :: %__MODULE__{
          kind: kind(),
          message: String.t(),
          code: String.t() | nil,
          reason: term()
        }

  defexception [:kind, :message, :code, :reason]

  @impl true
  def message(%__MODULE__{kind: kind, message: message, code: nil}),
    do: "[#{kind}] #{message}"

  def message(%__MODULE__{kind: kind, message: message, code: code}),
    do: "[#{kind}] #{message} (#{code})"

  @doc false
  def config(message), do: %__MODULE__{kind: :config, message: message}

  @doc false
  def codec(message, reason \\ nil),
    do: %__MODULE__{kind: :codec, message: message, reason: reason}

  @doc false
  def transport(message, reason \\ nil),
    do: %__MODULE__{kind: :transport, message: message, reason: reason}

  @doc false
  def soap(message, reason \\ nil),
    do: %__MODULE__{kind: :soap, message: message, reason: reason}

  @doc false
  def api(message, code \\ nil, reason \\ nil),
    do: %__MODULE__{kind: :api, message: message, code: code, reason: reason}
end
