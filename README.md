# ExBkavInvoice

Elixir client for the **Bkav eHoadon** electronic-invoice web service
(hóa đơn điện tử), covering the `WSPublicEHoaDon.asmx` SOAP API.

> **Bkav eHoadon, not eHoaDon Online.** Two unrelated Vietnamese providers use
> nearly the same name. This library targets **Bkav Corporation's** eHoadon
> (`ws.ehoadon.vn`, SOAP, PartnerGUID + PartnerToken). It is *not* a client for
> eHoaDon Online (`*.ehoadon.net`, REST + bearer token).

## Installation

```elixir
def deps do
  [{:ex_bkav_invoice, path: "../ex_bkav_invoice"}]
end
```

## Before you can call anything

Bkav issues a `PartnerGUID` and a `PartnerToken` per *sending point* — a branch,
a shop, or an individual accountant. The account must already exist on
`van.ehoadon.vn` (or `demo.ehoadon.vn` for testing) **with an invoice template
(mẫu số) and an issued number range (dải số) registered**. Neither has an API,
so that part is manual setup with Bkav.

```elixir
config =
  ExBkavInvoice.Config.new!(
    partner_guid: System.fetch_env!("BKAV_PARTNER_GUID"),
    partner_token: System.fetch_env!("BKAV_PARTNER_TOKEN"),
    endpoint: System.fetch_env!("BKAV_ENDPOINT")
  )
```

`:endpoint` is the full web-service URL and has **no default**. Which host you
talk to is deployment configuration, so it comes from your config rather than
from a name baked into this library — and a missing endpoint fails loudly
instead of quietly issuing invoices against a test host.

For reference, Bkav's own hosts:

| Environment | Web UI | Web service |
|-------------|--------|-------------|
| Testing | `demo.ehoadon.vn` | `https://wsdemo.ehoadon.vn/WSPublicEHoaDon.asmx` |
| Production | `van.ehoadon.vn` | `https://ws.ehoadon.vn/WSPublicEHoaDon.asmx` |

## Issuing an invoice

Creating and signing are separate steps. Nothing reaches the tax authority until
the invoice is signed — by an accountant in the web UI with a USB token, or via
`sign/3` if the account uses an HSM certificate.

```elixir
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

created["InvoiceGUID"]  # Bkav's id — needed for signing, voiding, lookups
created["MTC"]          # lookup code the buyer uses on tracuu.ehoadon.vn
```

### Batches fail partially

A batch can return `Status: 0` at the envelope level while individual invoices
inside it failed. Always go through `split_results/1` rather than stopping at the
`{:ok, _}`:

```elixir
{:ok, response} = ExBkavInvoice.create_invoice(config, invoices)

case ExBkavInvoice.Response.split_results(response) do
  {created, []} -> handle_created(created)
  {created, failed} -> handle_partial(created, failed)  # failed[]["MessLog"] says why
end
```

### Idempotency

`PartnerInvoiceID` (numeric) or `PartnerInvoiceStringID` (string) is *your* id for
the invoice, and it is the only thing stopping a retry from issuing a duplicate —
a real tax document that then has to be formally voided. Always send one, use
exactly one of the two, and keep it stable across retries.

## Choosing a creation command

The five creation commands differ only in who owns the form, serial and number:

| CmdType | Form & serial | Invoice number | Resulting state |
|---------|---------------|----------------|-----------------|
| `:create_draft` (100) | Bkav | none | mới tạo — deletable draft |
| `:create_numbered` (101) | Bkav | Bkav | chờ |
| `:create_draft_own_serial` (110) | yours | none | mới tạo |
| `:create_own_number` (111) | yours | yours | chờ |
| `:create_bkav_number` (112) | yours | Bkav | chờ |

Prefer a draft variant unless your system is the system of record for invoice
numbering — once numbered, invoice numbers must stay monotonic with respect to
invoice date within a form/serial pair, or eHoadon rejects the call.

## Correcting an issued invoice

Once signed, an invoice can no longer be updated or deleted, only:

* **voided** (hủy) — `cancel_invoice/4`, stays in tax reporting
* **replaced** (thay thế) — `:create_replacement`, with `OriginalInvoiceIdentify`
* **adjusted** (điều chỉnh) — `:create_adjustment`, with `IsIncrease` per line

`ExBkavInvoice.Enums.issued?/1` tells you which path applies for a given
`InvoiceStatusID`.

## Checking what the tax authority did

`get_status/3` reports only eHoadon's view. `get_tax_status/3` (command 850) is
the one that says whether the tax authority accepted the invoice:

```elixir
{:ok, response} = ExBkavInvoice.get_tax_status(config, invoice_guid)
[%{"TaxStatusName" => name}] = ExBkavInvoice.Response.describe_tax_status(response)
```

## Commands not wrapped here

`ExBkavInvoice.Client.exec/4` takes any `CmdType` with any payload, so a command
this library does not wrap — or one Bkav adds later — still works:

```elixir
ExBkavInvoice.Client.exec(config, 853, %{
  "InvoiceDateFrom" => "2026-01-01",
  "InvoiceDateTo" => "2026-01-31",
  "PageNumber" => 1
})
```

`ExBkavInvoice.Command.all/0` lists every code the library knows by name.

## Wire format

Per Bkav's integration diagram, the payload on `EncryptedCommandData` is:

```
JSON -> compress -> AES-256-CBC (PKCS#7) -> Base64
```

The `PartnerToken` carries both halves of the key material as
`base64(key):base64(iv)` — 32 bytes of key, 16 of IV.

### If your first call fails

Bkav's FAQ documents the compression step but never names the algorithm, and the
two plausible readings of their .NET sample disagree on the bytes: `GZipStream`
yields a gzip container, `DeflateStream` yields raw deflate. This library
defaults to `:gzip`. If the service rejects your first request, try:

```elixir
ExBkavInvoice.Config.new!(..., compression: :deflate)
```

Responses are sniffed by container, so only the request direction is affected.

A `Padding is invalid and cannot be removed` error means the `PartnerGUID` and
`PartnerToken` do not match — eHoadon reports credential mismatches that way
rather than as an auth error.

## Errors

Every call returns `{:ok, %ExBkavInvoice.Response{}}` or
`{:error, %ExBkavInvoice.Error{}}`. `:kind` says where it broke, which is what
decides whether a retry can help:

| kind | meaning | retryable |
|------|---------|-----------|
| `:config` | bad credentials or options | no |
| `:codec` | compress/encrypt/decode failed | no |
| `:transport` | the HTTP call failed | usually |
| `:soap` | SOAP fault or missing result element | maybe |
| `:api` | reached eHoadon, which answered `Status: 1` | depends on `:code` |

## Testing against it

`:req_options` is merged into every request, so a `Plug` stub swaps out the
network without touching the encryption path:

```elixir
ExBkavInvoice.Config.new!(
  partner_guid: "test",
  partner_token: token,
  endpoint: "https://wsdemo.example.test/WSPublicEHoaDon.asmx",
  req_options: [plug: fn conn -> ... end]
)
```

## License

MIT
