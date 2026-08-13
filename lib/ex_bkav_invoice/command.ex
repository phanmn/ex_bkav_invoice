defmodule ExBkavInvoice.Command do
  @moduledoc """
  The `CmdType` codes eHoadon accepts over the web service.

  ## Choosing a creation command

  The five creation commands differ only in who owns the invoice form (mẫu số),
  the serial (ký hiệu) and the invoice number (số hóa đơn):

  | CmdType | Form & serial | Invoice number | Resulting state |
  |---------|---------------|----------------|-----------------|
  | `100` | Bkav | none (0) | mới tạo — a draft, still deletable |
  | `101` | Bkav | Bkav, returned to you | chờ — numbered, awaiting signature |
  | `110` | yours | none (0) | mới tạo |
  | `111` | yours | yours | chờ |
  | `112` | yours | Bkav, returned to you | chờ |

  A *mới tạo* invoice is a draft: it carries no number and can be deleted
  outright. A *chờ* invoice already holds a number, so correcting it means
  updating or formally voiding it — and once numbered, the numbers must stay
  monotonic with respect to invoice date within a form/serial pair, or eHoadon
  rejects the call.

  Prefer `100`/`110` unless your system is the system of record for invoice
  numbering.
  """

  @commands %{
    # Creation
    create_draft: 100,
    create_numbered: 101,
    create_draft_own_serial: 110,
    create_own_number: 111,
    create_bkav_number: 112,
    # Replacement (thay thế) and adjustment (điều chỉnh)
    create_replacement_draft: 120,
    create_adjustment_draft: 121,
    create_discount_adjustment: 122,
    create_replacement: 123,
    create_adjustment: 124,
    create_external_adjustment_draft: 125,
    create_discount_adjustment_numbered: 126,
    create_external_adjustment: 127,
    create_external_replacement: 128,
    create_external_replacement_draft: 129,
    # Updating an unissued invoice
    update_by_partner_id: 200,
    update_by_identity: 203,
    update_by_guid: 204,
    # Voiding an issued invoice (hủy) / deleting an unissued one (xóa bỏ)
    cancel_by_guid: 201,
    cancel_by_partner_id: 202,
    delete_by_partner_id: 301,
    delete_by_guid: 303,
    # HSM signing
    sign: 205,
    sign_many: 206,
    # Explanations to the tax authority (giải trình)
    explain: 300,
    explain_replaced: 304,
    # Attachments
    attach_by_partner_id: 502,
    attach_by_guid: 503,
    # Reads
    get_invoice: 800,
    get_status: 801,
    get_history: 802,
    get_converted_link: 804,
    get_pdf: 808,
    get_xml: 809,
    get_range: 810,
    get_presentation: 811,
    get_converted: 812,
    get_invoice_xml: 813,
    get_bc26_report: 814,
    get_attachment_list: 815,
    get_presentation_link: 816,
    get_04ss_link: 817,
    get_04ss_pdf: 818,
    get_tax_status: 850,
    get_by_date: 853,
    # Miscellaneous
    resend_lookup_email: 901,
    lookup_company: 904,
    send_lookup_email: 911,
    # Point-of-sale bills
    create_bill: 1014,
    create_invoice_from_bill: 1026,
    get_bill: 1027
  }

  @type name :: atom()

  @doc """
  Resolves a command name to its numeric `CmdType`.

  A number passes through, so callers can use a code Bkav added after this
  library was written.

      iex> ExBkavInvoice.Command.resolve(:create_own_number)
      {:ok, 111}

      iex> ExBkavInvoice.Command.resolve(999)
      {:ok, 999}

      iex> ExBkavInvoice.Command.resolve(:nope)
      :error
  """
  @spec resolve(name() | integer()) :: {:ok, integer()} | :error
  def resolve(cmd_type) when is_integer(cmd_type), do: {:ok, cmd_type}

  def resolve(name) when is_atom(name) do
    case Map.fetch(@commands, name) do
      {:ok, code} -> {:ok, code}
      :error -> :error
    end
  end

  def resolve(_), do: :error

  @doc "All known commands, as a name => `CmdType` map."
  @spec all() :: %{atom() => integer()}
  def all, do: @commands

  @doc """
  Whether a command's `CommandObject` is a list of invoice objects rather than a
  bare identifier.

  Commands marked "Đầu vào là Object" in Bkav's appendix take
  `[%{"Invoice" => ..., "ListInvoiceDetailsWS" => ...}]`; the rest take a plain
  GUID, partner id, or a small map of parameters.
  """
  @spec object_input?(name() | integer()) :: boolean()
  def object_input?(cmd_type) do
    case resolve(cmd_type) do
      {:ok, code} -> code in object_input_codes()
      :error -> false
    end
  end

  defp object_input_codes do
    [100, 101, 110, 111, 112] ++
      [120, 121, 122, 123, 124, 125, 126, 127, 128, 129] ++
      [200, 203, 204, 201, 202, 301, 303] ++
      [206, 300, 304, 502, 503, 804, 816, 817, 818, 911]
  end
end
