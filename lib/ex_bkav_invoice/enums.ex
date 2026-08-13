defmodule ExBkavInvoice.Enums do
  @moduledoc """
  The numeric code tables from Bkav's appendix, with lookups.

  Every table keeps Bkav's Vietnamese labels verbatim — they are the terms that
  appear in eHoadon's own UI and in tax filings, so translating them here would
  only make reconciling with an accountant harder.
  """

  invoice_status = %{
    1 => "Mới tạo",
    2 => "Đã phát hành",
    3 => "Đã hủy",
    4 => "Đã xóa",
    5 => "Chờ thay thế",
    6 => "Thay thế",
    7 => "Chờ điều chỉnh",
    8 => "Điều chỉnh",
    9 => "Bị thay thế",
    10 => "Bị điều chỉnh",
    11 => "Trống (đã cấp số, chờ ký)",
    12 => "Không sử dụng",
    13 => "Chờ hủy",
    14 => "Chờ điều chỉnh chiết khấu",
    15 => "Điều chỉnh chiết khấu"
  }

  tax_status = %{
    0 => "Chưa có trạng thái của CQT",
    32 => "Chờ Thuế xử lý",
    33 => "Thuế đã duyệt",
    34 => "Cần rà soát",
    35 => "Cấp mã bị lỗi",
    36 => "Chờ cấp mã",
    37 => "Có sai sót",
    38 => "Lỗi được CQT trả về",
    39 => "Lỗi khi đẩy vào Queue của Thuế"
  }

  invoice_type = %{
    1 => "Hóa đơn Giá trị gia tăng",
    2 => "Hóa đơn bán hàng",
    4 => "Hóa đơn bán hàng (khu PTQ)",
    5 => "Phiếu xuất kho & vận chuyển nội bộ",
    6 => "Phiếu xuất kho gửi bán hàng đại lý",
    7 => "Biên lai thu phí không điền sẵn mệnh giá",
    8 => "Biên lai thu phí điền sẵn mệnh giá",
    9 => "Hóa đơn bán tài sản công",
    10 => "Tem, vé, thẻ điện tử là Hóa đơn GTGT",
    11 => "Tem, vé, thẻ điện tử là Hóa đơn BH"
  }

  # TaxRateID 4/5/6 use negative sentinel rates: they are not percentages but
  # markers for "not subject to tax", "not declared" and "contractor tax".
  tax_rate = %{
    1 => 0.0,
    2 => 5.0,
    3 => 10.0,
    4 => -1.0,
    5 => -2.0,
    6 => -4.0,
    7 => 3.5,
    8 => 7.0,
    9 => 8.0
  }

  tax_rate_label = %{
    1 => "0%",
    2 => "5%",
    3 => "10%",
    4 => "Không chịu thuế",
    5 => "Không kê khai thuế",
    6 => "Thuế nhà thầu",
    7 => "5% x 70%",
    8 => "10% x 70%",
    9 => "8%"
  }

  item_type = %{
    0 => "Hàng hoá dịch vụ",
    1 => "Thuế khác",
    2 => "Phí khác",
    3 => "Phí phục vụ",
    4 => "Ghi chú",
    5 => "Phụ thu",
    6 => "Phí hoàn",
    7 => "Lệ phí",
    8 => "Phí an ninh",
    9 => "Số tiền bằng chữ",
    10 => "Tiền đất giảm trừ khi tính thuế",
    11 => "Điều chỉnh hoá đơn ngoài hệ thống",
    12 => "Diễn giải hàng hóa đi kèm có đánh STT",
    13 => "Diễn giải hàng hóa đi kèm không đánh STT",
    14 => "Phí dịch vụ cho hóa đơn hoàn vé",
    15 => "Hàng hoá khuyến mãi",
    16 => "Giảm 20% mức tỷ lệ % trên doanh thu",
    17 => "Thuế tiêu thụ đặc biệt",
    21 => "Hàng hóa là xe ô tô, xe mô tô",
    22 => "Dịch vụ vận chuyển",
    23 => "Dịch vụ vận chuyển trên nền tảng số, TMĐT"
  }

  pay_method = %{
    1 => "TM",
    2 => "CK",
    3 => "TM/CK",
    4 => "Xuất hàng cho chi nhánh",
    5 => "Hàng biếu tặng",
    6 => "Cấn trừ công nợ",
    7 => "Trả hàng",
    8 => "Khuyến mại không thu tiền",
    9 => "Xuất sử dụng",
    10 => "Không thu tiền",
    11 => "D/A",
    12 => "D/P",
    13 => "TT",
    14 => "L/C",
    15 => "Công nợ",
    16 => "Nhờ thu",
    17 => "TM/CK/B",
    18 => "Thẻ tín dụng",
    19 => "CK/Cấn trừ công nợ",
    20 => "Hàng hóa",
    21 => "Hàng mẫu",
    22 => "Thẻ",
    23 => "Bù trừ công nợ",
    24 => "Qua LAZADA",
    25 => "Qua TIKI",
    26 => "Xuất hóa đơn nội bộ",
    27 => "T/T",
    28 => "TTR",
    29 => "TM/CK/Qua LAZADA",
    30 => "TM/CK/Qua TIKI",
    31 => "TM/Thẻ",
    32 => "CK/Thẻ",
    33 => "TM/CK/Thẻ",
    34 => "CK/LC",
    35 => "L/C at sight",
    36 => "Xuất hàng hoá, dịch vụ trả thay lương",
    38 => "CAD",
    39 => "Qua SHOPEE",
    40 => "TM/CK/Qua SHOPEE",
    41 => "Cho vay/Cho mượn",
    42 => "Ví điện tử",
    43 => "Điểm",
    44 => "Voucher"
  }

  receive_type = %{
    1 => "Email",
    2 => "SMS",
    3 => "Email & SMS",
    4 => "Chuyển phát nhanh"
  }

  tables = [
    {:invoice_status, invoice_status},
    {:tax_status, tax_status},
    {:invoice_type, invoice_type},
    {:tax_rate_label, tax_rate_label},
    {:item_type, item_type},
    {:pay_method, pay_method},
    {:receive_type, receive_type}
  ]

  for {name, table} <- tables do
    @doc "The full `#{name}` table, keyed by its numeric id."
    @spec unquote(name)() :: %{integer() => String.t()}
    def unquote(name)(), do: unquote(Macro.escape(table))

    @doc "Labels a `#{name}` id, or `nil` when the id is unknown."
    @spec unquote(name)(integer()) :: String.t() | nil
    def unquote(name)(id), do: Map.get(unquote(Macro.escape(table)), id)
  end

  @tax_rate tax_rate

  @doc """
  The percentage that goes in `TaxRate` for a given `TaxRateID`.

      iex> ExBkavInvoice.Enums.tax_rate(3)
      10.0

      iex> ExBkavInvoice.Enums.tax_rate(4)
      -1.0
  """
  @spec tax_rate(integer()) :: float() | nil
  def tax_rate(tax_rate_id), do: Map.get(@tax_rate, tax_rate_id)

  @doc "The full `TaxRateID` => `TaxRate` table."
  @spec tax_rates() :: %{integer() => float()}
  def tax_rates, do: @tax_rate

  @issued_statuses [2, 6, 8, 15]

  @doc """
  Whether an `InvoiceStatusID` means the invoice has been signed and issued.

  Issued invoices can no longer be updated or deleted — only voided, replaced or
  adjusted — so this is the check that decides which correction path applies.
  """
  @spec issued?(integer()) :: boolean()
  def issued?(status_id), do: status_id in @issued_statuses
end
