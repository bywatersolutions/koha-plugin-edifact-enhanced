# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/2.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

> This changelog is curated and grouped by minor release series rather than by
> individual tag. Releases that contained only CI, build, or version-bump
> changes are omitted, and the foundational 2.1.x development series is
> summarized rather than enumerated commit by commit.

## [Unreleased]

## [4.3.x] - 2026-06

### Fixed

- Strip a leading period from `order_file_suffix` and `invoice_file_suffix` so a
  value like `.CEI` no longer breaks invoice download matching or produces a
  doubled period (`ordr123..CEO`) in order filenames.
- Skip the `.` and `..` directory entries when downloading invoice files over
  FTP/SFTP.
- Take the buyer SAN username from the file transport rather than the EDI
  account, and warn when `buyer_san_use_username` is set but the file transport
  has no username configured.
- Fix `buyer_san_in_header` / `buyer_san_use_username` for Koha 25.11+.

## [4.2.x] - 2026-05

### Changed

- Receipt handling now uses the plugin's internal `_receipt_items` instead of
  `Koha::EDI::receipt_items`.

### Fixed

- Skip the "LIN from item field" feature for orderlines that have no associated
  item.

## [4.1.x] - 2026-03

### Fixed

- Restore invoice-download action logging and re-allow invoices that have no
  file suffix.

## [4.0.x] - 2026-03

First release of the modern transport rewrite.

### Added

- Add the ability to skip files that have previously been downloaded.
- Add the ability to specify which MOA segments generate invoice adjustments.

### Changed

- **Breaking:** Reworked invoice receiving and downloading to use Koha's modern
  `Koha::File::Transport` system, closely matching Koha 25.05/25.11. This
  release requires **Koha 25.11+**.

### Fixed

- Handle FTP listings where the filename field contains more than just the
  filename.
- Look up `skip_previously_downloaded_files` once per run instead of per file.
- Prevent leading newlines in message segments from breaking invoice
  processing.
- Filter out empty segments that crashed invoice processing.
- Fix the plugin incorrectly referencing the vendor-specific `EdifactWhitehots`
  module.

## [3.9.x] - 2025-11

### Fixed

- Fix a bug that could cause an infinite loop when invoice data was malformed.

## [3.8.x] - 2025-09

### Fixed

- Skip invoices that have no bookseller instead of failing.
- Don't error on an invalid order number for `set_bookseller_from_order_basket`.
- Fix loop-increment issues (missing increment and stray `next` calls) when
  processing invoices.
- Fix the `Net::SFTP::Foreign` call used to remove a remote file.

## [3.6.x] - 2024-10

### Added

- Add the ability to skip sending GIR segments on a per Library EAN basis.

### Changed

- Quote booleans as strings to reduce noise in the settings change diff.
- Log changes to plugin settings.

### Fixed

- Fix a regex so multiple settings no longer conflict with one another.

## [3.5.x] - 2024-08

### Added

- Add an SFTP keepalive.

### Fixed

- Convert right single quotes to apostrophes when encoding/escaping text.

## [3.4.x] - 2024-04

### Changed

- Update for Koha's branch rename from `master` to `main`.

### Fixed

- Fix a regex error in `Order.pm`.

## [3.2.x] - 2024-01

### Added

- Store and transmit a Buyer SAN per Library EAN via the Library EAN
  description.

### Changed

- Default the PIA segment limit to 25.

## [3.1.x] - 2023-12

### Added

- Add support for MOA+79 shipment charges.

## [3.0.x] - 2023-11

### Changed

- Decrypt EDI account passwords before use, for Koha versions that store them
  encrypted.
- Bundle all `.kpz` builds into a single release.

### Fixed

- Fix string concatenation in the FTP error message.
- Include the vendor IDs in the mismatched-vendor-record error message.

## [2.12.x] - 2023-05

### Changed

- Update the plugin for Koha 22.11.00, 22.05.06, 21.11.14 and higher.
- Make invoice file extension matching case-insensitive.

### Fixed

- `pia_limit` is now always an empty string, never null.

## [2.11.x] - 2023-04

### Fixed

- Make `add_itemnote_on_receipt` and `lin_use_item_field_clear_on_invoice` work
  together when they use the same column.

## [2.10.x] - 2023-04

### Added

- Log invoice downloads to the action logs.
- Rename downloaded files when an invoice file extension is specified.

### Fixed

- Skip EDI vendor records that have no password.
- Only log a file download when the file is not being skipped.

## [2.9.x] - 2023-03

### Fixed

- If an incoming file has the wrong EDI vendor/account set, correct it so the
  right plugin can process the invoice next time.

## [2.8.x] - 2022-12

### Fixed

- Update the message vendor when updating the invoice vendor.

## [2.7.x] - 2022-12

### Changed

- Check basket `effective_create_items` instead of `AcqCreateItem` when
  generating GIR fields.

### Fixed

- Wrap generated GIR segments in try/catch so one bad segment can't abort the
  order.

## [2.6.x] - 2022-11

### Changed

- Make the plugin compatible with Koha 22.11+ (update `sftp_download()`, drop
  `GetMarcBiblio`, call `find` on `Koha::Biblios`).

### Fixed

- Don't crash if an invoice has no line items.
- Don't add a second line terminator when an IMD segment already ends with an
  unescaped one.

> A later backport release (v2.6.6, 2024) carried the settings-diff
> boolean-quoting fix onto this series for older Koha installs.

## [2.5.x] - 2022-07

### Added

- Specify a budget id to use for shipping fees on an invoice.
- Update order pricing/tax from invoices, and update invoice fields when the
  invoice already exists.

### Fixed

- Koha 21.11 compatibility fixes.
- Add a segment terminator when a segment doesn't already end with one (or ends
  with an escaped terminator).

## [2.4.x] - 2021-11

### Added

- Add tax to the amount in the shipping-costs field.
- Update order pricing based on Koha's own calculations.

## [2.3.x] - 2021-10

### Added

- Set the invoice vendor from the first invoiced item's basket.

### Removed

- Remove unused templates.

## [2.2.x] - 2021-05

### Fixed

- Re-use an existing Koha invoice when re-processing an EDI invoice message.

## [2.1.x] - 2018-2021

Foundational development series. The plugin began as a customization of the
Ingram EDI plugin (briefly named `EdifactIngram`) and was generalized into
`EdifactEnhanced`. Highlights of what was built up over this series:

### Added

- GIR segment control: specify GIR segment contents, send arbitrary MARC and
  aqorder fields, map GIR subfield values to other values, set subfields to
  static strings, split GIR every 5 tags, and disable GIR sending entirely.
- LIN/PIA control: use arbitrary item fields, EAN, ISBN, UPC and Midwest
  product id in the LIN and PIA segments; force the first ISBN; limit the number
  of PIA segments; clear the LIN item field on receipt.
- Shipment charges via MOA+8, MOA+124, MOA+131 and MOA+304, with each charge
  type individually selectable and the option to add tax to shipping.
- Buyer SAN handling: send Buyer SAN and Library EAN as NAD+BY segments or in
  the header, use the first part of the Library EAN as the Buyer SAN, and send
  the EDI vendor username as the Buyer SAN.
- Invoicing options: set not-for-loan status on receipt, optionally overlay item
  price and/or replacement price, set a shipping budget and close the invoice on
  receipt, make the "Received via EDIFACT" item note optional, ignore duplicate
  receipts, and support standing orders.
- Send the basket name instead of the basket number in the BGM segment, and send
  the fund code in RFF+BFN.
- Warn on the configuration page when a required Perl module is missing.

### Changed

- Don't require the UNA service string advice; assume the default instead.

### Fixed

- Numerous fixes for Koha API changes and EDIFACT encoding/escaping over the
  life of the series.

[Unreleased]: https://github.com/bywatersolutions/koha-plugin-edifact-enhanced/compare/v4.3.3...HEAD
[4.3.x]: https://github.com/bywatersolutions/koha-plugin-edifact-enhanced/compare/v4.2.6...v4.3.3
[4.2.x]: https://github.com/bywatersolutions/koha-plugin-edifact-enhanced/compare/v4.1.1...v4.2.6
[4.1.x]: https://github.com/bywatersolutions/koha-plugin-edifact-enhanced/compare/v4.0.26...v4.1.1
[4.0.x]: https://github.com/bywatersolutions/koha-plugin-edifact-enhanced/compare/v3.9.29...v4.0.26
[3.9.x]: https://github.com/bywatersolutions/koha-plugin-edifact-enhanced/compare/v3.8.25...v3.9.29
[3.8.x]: https://github.com/bywatersolutions/koha-plugin-edifact-enhanced/compare/v3.7.0...v3.8.25
[3.6.x]: https://github.com/bywatersolutions/koha-plugin-edifact-enhanced/compare/v3.5.2...v3.6.9
[3.5.x]: https://github.com/bywatersolutions/koha-plugin-edifact-enhanced/compare/v3.4.1...v3.5.2
[3.4.x]: https://github.com/bywatersolutions/koha-plugin-edifact-enhanced/compare/v3.2.0...v3.4.1
[3.2.x]: https://github.com/bywatersolutions/koha-plugin-edifact-enhanced/compare/v3.1.0...v3.2.0
[3.1.x]: https://github.com/bywatersolutions/koha-plugin-edifact-enhanced/compare/v3.0.12...v3.1.0
[3.0.x]: https://github.com/bywatersolutions/koha-plugin-edifact-enhanced/compare/v2.12.1...v3.0.12
[2.12.x]: https://github.com/bywatersolutions/koha-plugin-edifact-enhanced/compare/v2.11.2...v2.12.1
[2.11.x]: https://github.com/bywatersolutions/koha-plugin-edifact-enhanced/compare/v2.10.0...v2.11.2
[2.10.x]: https://github.com/bywatersolutions/koha-plugin-edifact-enhanced/compare/v2.9.0...v2.10.0
[2.9.x]: https://github.com/bywatersolutions/koha-plugin-edifact-enhanced/compare/v2.8.2...v2.9.0
[2.8.x]: https://github.com/bywatersolutions/koha-plugin-edifact-enhanced/compare/v2.7.0...v2.8.2
[2.7.x]: https://github.com/bywatersolutions/koha-plugin-edifact-enhanced/compare/v2.6.5...v2.7.0
[2.6.x]: https://github.com/bywatersolutions/koha-plugin-edifact-enhanced/compare/v2.5.4...v2.6.5
[2.5.x]: https://github.com/bywatersolutions/koha-plugin-edifact-enhanced/compare/v2.4.0...v2.5.4
[2.4.x]: https://github.com/bywatersolutions/koha-plugin-edifact-enhanced/compare/v2.3.4...v2.4.0
[2.3.x]: https://github.com/bywatersolutions/koha-plugin-edifact-enhanced/compare/v2.2.13...v2.3.4
[2.2.x]: https://github.com/bywatersolutions/koha-plugin-edifact-enhanced/compare/v2.1.74...v2.2.13
[2.1.x]: https://github.com/bywatersolutions/koha-plugin-edifact-enhanced/releases/tag/v2.1.74
