defmodule ExBkavInvoice do
  @moduledoc """
  ExBkavInvoice.Client for the Bkav eHoadon electronic-invoice web service.

  > #### Bkav eHoadon, not eHoaDon Online {: .warning}
  >
  > Two unrelated Vietnamese providers use nearly the same name. This library
  > talks to **Bkav Corporation's** eHoadon (`ws.ehoadon.vn`, SOAP, PartnerGUID
  > + PartnerToken). It is *not* a client for eHoaDon Online
  > (`*.ehoadon.net`, REST + bearer token).

  ## Getting connected

  Bkav issues a `PartnerGUID` and a `PartnerToken` per sending point. Before the
  web service will accept anything, that account must already exist on
  `van.ehoadon.vn` (or `demo.ehoadon.vn` for testing) **with an invoice template
  and an issued number range registered** — the service has no API for either,
  so this is a manual setup step with Bkav.

      config =
        ExBkavInvoice.Config.new!(
          partner_guid: System.fetch_env!("BKAV_PARTNER_GUID"),
          partner_token: System.fetch_env!("BKAV_PARTNER_TOKEN"),
          endpoint: System.fetch_env!("BKAV_ENDPOINT")
        )

  `:endpoint` is the full web-service URL and has no default — which host you
  talk to is deployment configuration, so it belongs in your config rather than
  in this library. Bkav's own hosts are
  `https://wsdemo.ehoadon.vn/WSPublicEHoaDon.asmx` for testing and
  `https://ws.ehoadon.vn/WSPublicEHoaDon.asmx` for production.

  ## Issuing an invoice

  Creating and signing are separate steps. `create_invoice/3` puts the invoice on
  eHoadon; nothing reaches the tax authority until it is signed — either by an
  accountant on the web UI with a USB token, or through `sign/3` if the account
  uses an HSM certificate.

      invoice = %{
        "Invoice" => %{
          "InvoiceTypeID" => 1,
          "InvoiceDate" => DateTime.to_iso8601(DateTime.utc_now()),
          "BuyerName" => "Nguyen Van A",
          "BuyerTaxCode" => "0123456789",
          "BuyerUnitName" => "CONG TY ABC",
          "BuyerAddress" => "So 632, Duong A, Q. Hai Ba Trung",
          "PayMethodID" => 3,
          "ReceiveTypeID" => 1,
          "ReceiverEmail" => "ke.toan@example.com",
          "CurrencyID" => "VND",
          "ExchangeRate" => 1.0
        },
        "ListInvoiceDetailsWS" => [
          %{
            "ItemName" => "Khoá học Elixir",
            "UnitName" => "Khoá",
            "Qty" => 1.0,
            "Price" => 1_000_000.0,
            "Amount" => 1_000_000.0,
            "TaxRateID" => 3,
            "TaxRate" => 10.0,
            "TaxAmount" => 100_000.0
          }
        ],
        "PartnerInvoiceID" => 0,
        "PartnerInvoiceStringID" => order_id
      }

      {:ok, response} = ExBkavInvoice.create_invoice(config, [invoice])
      {[created], []} = ExBkavInvoice.Response.split_results(response)
      created["InvoiceGUID"]

  ## Idempotency

  `PartnerInvoiceID` (numeric) or `PartnerInvoiceStringID` (string) is your own
  id for the invoice, and it is the only thing stopping a retry from issuing a
  duplicate — a real tax document that then has to be formally voided. Always
  send one, use exactly one of the two, and keep it stable across retries.

  ## Beyond the documented commands

  `ExBkavInvoice.Client.exec/4` takes any `CmdType` with any payload, so a command
  Bkav adds later needs no change here:

      ExBkavInvoice.Client.exec(config, 853, %{
        "InvoiceDateFrom" => "2026-01-01",
        "InvoiceDateTo" => "2026-01-31",
        "PageNumber" => 1
      })
  """

  @type result :: {:ok, ExBkavInvoice.Response.t()} | {:error, ExBkavInvoice.Error.t()}

  @doc """
  Creates invoices from a list of invoice maps.

  `:cmd_type` picks who assigns the form, serial and number; it defaults to
  `:create_draft` (`100`), which lets Bkav assign the form and serial and leaves
  the invoice as a deletable draft. `ExBkavInvoice.Command` explains the five
  variants and when a different one is appropriate.

  Bkav caps a single invoice at 10,000 line items.
  """
  @spec create_invoice(ExBkavInvoice.Config.t(), [map()], keyword()) :: result()
  def create_invoice(%ExBkavInvoice.Config{} = config, invoices, opts \\ [])
      when is_list(invoices) do
    {cmd_type, opts} = Keyword.pop(opts, :cmd_type, :create_draft)
    ExBkavInvoice.Client.exec(config, cmd_type, invoices, opts)
  end

  @doc """
  Updates invoices that have not been signed yet.

  Which command to use depends on how you identify the invoice: `:update_by_partner_id`
  (`200`, the default), `:update_by_identity` (`203`, by form_serial_number) or
  `:update_by_guid` (`204`).
  """
  @spec update_invoice(ExBkavInvoice.Config.t(), [map()], keyword()) :: result()
  def update_invoice(%ExBkavInvoice.Config{} = config, invoices, opts \\ [])
      when is_list(invoices) do
    {cmd_type, opts} = Keyword.pop(opts, :cmd_type, :update_by_partner_id)
    ExBkavInvoice.Client.exec(config, cmd_type, invoices, opts)
  end

  @doc """
  Voids an already-issued invoice (hủy), giving a reason.

  A voided invoice stays in tax reporting. To remove an invoice that was never
  issued, use `delete_invoice/3` instead.
  """
  @spec cancel_invoice(ExBkavInvoice.Config.t(), String.t(), String.t(), keyword()) :: result()
  def cancel_invoice(%ExBkavInvoice.Config{} = config, invoice_guid, reason, opts \\ []) do
    object = [%{"Invoice" => %{"InvoiceGUID" => invoice_guid, "Reason" => reason}}]
    ExBkavInvoice.Client.exec(config, :cancel_by_guid, object, opts)
  end

  @doc """
  Deletes an invoice that has not been issued (xóa bỏ), giving a reason.

  eHoadon only accepts this when the invoice's number is the highest currently
  allocated in its range, because deleting from the middle would break the
  continuity rule invoice numbering has to satisfy.
  """
  @spec delete_invoice(ExBkavInvoice.Config.t(), String.t(), String.t(), keyword()) :: result()
  def delete_invoice(%ExBkavInvoice.Config{} = config, invoice_guid, reason, opts \\ []) do
    object = [%{"Invoice" => %{"InvoiceGUID" => invoice_guid, "Reason" => reason}}]
    ExBkavInvoice.Client.exec(config, :delete_by_guid, object, opts)
  end

  @doc """
  Signs and issues an invoice using an HSM certificate.

  Only accounts configured for HSM (server-held) signing can use this. Accounts
  on a USB token sign through the eHoadon web UI instead, and there is no API
  equivalent. This is the step that submits the invoice to the tax authority.
  """
  @spec sign(ExBkavInvoice.Config.t(), String.t(), keyword()) :: result()
  def sign(%ExBkavInvoice.Config{} = config, invoice_guid, opts \\ []) do
    ExBkavInvoice.Client.exec(config, :sign, invoice_guid, opts)
  end

  @doc """
  Signs several invoices in one call.

  The envelope reports failure if *any* invoice fails, so check
  `ExBkavInvoice.Response.split_results/1` rather than assuming all or nothing.
  """
  @spec sign_many(ExBkavInvoice.Config.t(), [String.t()], keyword()) :: result()
  def sign_many(%ExBkavInvoice.Config{} = config, invoice_guids, opts \\ [])
      when is_list(invoice_guids) do
    object = Enum.map(invoice_guids, &%{"InvoiceGUID" => &1})
    ExBkavInvoice.Client.exec(config, :sign_many, object, opts)
  end

  @doc """
  Fetches one invoice in full, by `InvoiceGUID`, `PartnerInvoiceID` or
  `PartnerInvoiceStringID`.
  """
  @spec get_invoice(ExBkavInvoice.Config.t(), String.t() | integer(), keyword()) :: result()
  def get_invoice(%ExBkavInvoice.Config{} = config, identifier, opts \\ []) do
    ExBkavInvoice.Client.exec(config, :get_invoice, identifier, opts)
  end

  @doc """
  Fetches only an invoice's `InvoiceStatusID`.

  Label it with `ExBkavInvoice.Enums.invoice_status/1`.
  """
  @spec get_status(ExBkavInvoice.Config.t(), String.t(), keyword()) :: result()
  def get_status(%ExBkavInvoice.Config{} = config, invoice_guid, opts \\ []) do
    ExBkavInvoice.Client.exec(config, :get_status, invoice_guid, opts)
  end

  @doc """
  Fetches an invoice's Bkav status together with its tax-authority status and
  code (`850`).

  This is the call that tells you whether the tax authority actually accepted
  the invoice — `get_status/3` only reports eHoadon's own view.
  `ExBkavInvoice.Response.describe_tax_status/1` labels the result.
  """
  @spec get_tax_status(ExBkavInvoice.Config.t(), String.t(), keyword()) :: result()
  def get_tax_status(%ExBkavInvoice.Config{} = config, invoice_guid, opts \\ []) do
    ExBkavInvoice.Client.exec(config, :get_tax_status, invoice_guid, opts)
  end

  @doc """
  Fetches invoices created within a date range, one page at a time (`853`).
  """
  @spec get_by_date(
          ExBkavInvoice.Config.t(),
          Date.t() | String.t(),
          Date.t() | String.t(),
          keyword()
        ) ::
          result()
  def get_by_date(%ExBkavInvoice.Config{} = config, from, to, opts \\ []) do
    {page, opts} = Keyword.pop(opts, :page, 1)

    object = %{
      "InvoiceDateFrom" => to_date_string(from),
      "InvoiceDateTo" => to_date_string(to),
      "PageNumber" => page
    }

    ExBkavInvoice.Client.exec(config, :get_by_date, object, opts)
  end

  @doc """
  Fetches invoices by form, serial and number range (`810`).

  Bkav caps each call at 30 invoices.
  """
  @spec get_range(
          ExBkavInvoice.Config.t(),
          String.t(),
          String.t(),
          integer(),
          integer(),
          keyword()
        ) :: result()
  def get_range(%ExBkavInvoice.Config{} = config, form, serial, from_no, to_no, opts \\ []) do
    object = %{
      "InvoiceForm" => form,
      "InvoiceSerial" => serial,
      "FromInvoiceNo" => from_no,
      "ToInvoiceNo" => to_no
    }

    ExBkavInvoice.Client.exec(config, :get_range, object, opts)
  end

  @doc """
  Fetches an invoice's PDF (`808`) as raw bytes, decoded from the base64 eHoadon
  returns.
  """
  @spec get_pdf(ExBkavInvoice.Config.t(), String.t() | integer(), keyword()) ::
          {:ok, binary()} | {:error, ExBkavInvoice.Error.t()}
  def get_pdf(%ExBkavInvoice.Config{} = config, identifier, opts \\ []) do
    with {:ok, response} <- ExBkavInvoice.Client.exec(config, :get_pdf, identifier, opts) do
      decode_document(response, "PDF")
    end
  end

  @doc """
  Fetches an invoice's signed XML (`809`) as raw bytes.

  This is the legally meaningful artefact — keep it, not just the PDF.
  """
  @spec get_xml(ExBkavInvoice.Config.t(), String.t() | integer(), keyword()) ::
          {:ok, binary()} | {:error, ExBkavInvoice.Error.t()}
  def get_xml(%ExBkavInvoice.Config{} = config, identifier, opts \\ []) do
    with {:ok, response} <- ExBkavInvoice.Client.exec(config, :get_xml, identifier, opts) do
      decode_document(response, "XML")
    end
  end

  @doc """
  Looks up a company by tax code (`904`).

  Useful for validating `BuyerTaxCode` before issuing, since a wrong tax code on
  an issued invoice can only be corrected by replacing the invoice.
  """
  @spec lookup_company(ExBkavInvoice.Config.t(), String.t(), keyword()) :: result()
  def lookup_company(%ExBkavInvoice.Config{} = config, tax_code, opts \\ []) do
    ExBkavInvoice.Client.exec(config, :lookup_company, tax_code, opts)
  end

  @doc """
  Re-sends the lookup-code email for an invoice (`901`).
  """
  @spec resend_lookup_email(ExBkavInvoice.Config.t(), String.t(), keyword()) :: result()
  def resend_lookup_email(%ExBkavInvoice.Config{} = config, invoice_guid, opts \\ []) do
    ExBkavInvoice.Client.exec(config, :resend_lookup_email, invoice_guid, opts)
  end

  @doc """
  Sends the lookup email for an invoice to a specific address (`911`).
  """
  @spec send_lookup_email(ExBkavInvoice.Config.t(), String.t(), String.t(), keyword()) :: result()
  def send_lookup_email(%ExBkavInvoice.Config{} = config, invoice_guid, email, opts \\ []) do
    object = [
      %{
        "Invoice" => %{
          "InvoiceGUID" => invoice_guid,
          "ReceiverEmail" => email,
          "ReceiverMobile" => ""
        }
      }
    ]

    ExBkavInvoice.Client.exec(config, :send_lookup_email, object, opts)
  end

  defp decode_document(%ExBkavInvoice.Response{object: object}, key) do
    with {:ok, encoded} <- extract_document(object, key),
         {:ok, bytes} <- Base.decode64(encoded, ignore: :whitespace) do
      {:ok, bytes}
    else
      :error -> {:error, ExBkavInvoice.Error.codec("#{key} payload is not valid base64")}
      {:error, %ExBkavInvoice.Error{}} = error -> error
    end
  end

  defp extract_document(%{} = object, key) do
    case Map.get(object, key) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _ -> {:error, ExBkavInvoice.Error.api("response carried no #{key} document")}
    end
  end

  defp extract_document([first | _], key), do: extract_document(first, key)
  defp extract_document(value, _key) when is_binary(value), do: {:ok, value}

  defp extract_document(_, key),
    do: {:error, ExBkavInvoice.Error.api("response carried no #{key} document")}

  defp to_date_string(%Date{} = date), do: Date.to_iso8601(date)
  defp to_date_string(value) when is_binary(value), do: value
end
