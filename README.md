# Koha Enhanced Edifact Plugin

A Koha Edifact plugin that replicates the existing Edifact behavior with additional options. 
This plugin is depends on code that was made available in the 16.05 release of Koha.


# :warning: PSA

Some vendors insert line break characters every 80 characters by default. This can cause unexpected behavior when processing incoming EDI messages in Koha, using plugins or not! Please ask your vendors to *not* send line breaks in their EDI messages.

## Configuration options

### Buyer SAN

Some vendors require an additional buyer identification code to be sent in additionan the the ones Koha already sends.

#### Buyer Qualifier

Defines who assigned this SAN. This should be provided by your vendor.

#### Buyer SAN

The identifier itself. This should also be provided by your vendor.

#### Fields to send in

A given vendor may need the Buyer SAN to be sent in different parts of the Order message.

##### Header

If this option is selected, the Buyer SAN will sent in the Order header, and will replace the Library EAN as the datum that 
is sent as the buyer identifier in the header.

##### NAD+BY

If this option is selected, the Buyer SAN will appear as an additional NAD+BY segment in the Order. This option is independent of the Header option.
of the Header option. If both are checked, the Buyer SAN will be sent in the header *and* in a NAD+BY segment. If only this
option is checked, the Library EAN will be sent in the header and the Buyer SAN will be sent in a NAD+BY segment.

### Library EAN

This section controls where in the Order the Library EAN is sent to the Vendor.
The Library EAN is the identifier that is selected by the librarian at the time the Order is sent to the vendor via Edifact.

#### Fields to send in

The Library EAN may be sent in different parts of the Order message.

The Library EAN is always sent in the Order header, unless the Buyer SAN "Header" option above is selected to replace it there.

##### NAD+BY

If this option is selected, the Library EAN will also appear as an additional NAD+BY segment in the Order.

### File suffixes

Vendors often use different file suffixes for the various Edifact messages the may be send.
This section allows you to configure the file suffixes for your vendor

### Order file

This section lets you set the suffix for the Order messages you will transmit to your vendor.

### Invoice file

This section lets you set the suffix for the Invoices messages Koha will look for from the vendor.

### Append .dl to processed files

When enabled, downloaded invoice files are renamed on the vendor server by
appending `.dl` to the original filename after a successful download.

For example:

`invoice_20260909121212.EIN` → `invoice_20260909121212.EIN.dl`

This option is useful for vendors that expect downloaded files to be marked as
processed by appending `.dl`, rather than by modifying the existing file suffix.

When this option is disabled, the plugin retains its default behavior of changing
the first character of the three-character file suffix to `E` (for example,
`.INV` becomes `.ENV`). If the resulting filename would be unchanged, such as
with an `.EIN` file, no rename is attempted.

### LIN values

Each order line in Koha generates an LIN segment in an Edifact Order message.
These LIN segments may contain an item identifier.
This section allows you to specify which, if any identifiers are transmitted.
You may check all that apply.
The first valid identifier will be used and the rest ignored.
If you have specified a line item id for an order, it will be used in preference to the identifiers specified here.
The order of precedence is:
1. Item field
2. MARC field
3. Line item id
4. EAN
5. ISSN
6. ISBN
7. UPC
8. Product ID

#### MARC field

Send a value from the bibliographic record as the LIN identifier.
Enter the field and subfield holding the identifier ( e.g. 037$a ) and the item number type qualifier the vendor expects for it ( e.g. SA ). Both are required.
The first occurrence of the field is used, and the value is escaped for EDIFACT.
This is for vendors whose own product identifier is catalogued in the record, such as Amazon Business ASINs in 037$a.
Anything found in the configured field is sent, so make sure it only ever holds that vendor's identifier.

#### EAN

Send the EAN as the LIN identifier

#### ISSN

Send the ISSN as the LIN identifier

#### ISBN

Send the ISBN as the LIN identifier.
This identifier must be an ISBN-13.
The plugin will find all ISBNs related to this order line from the record and use the last valid ISBN-13 it finds.
If no native ISBN-13 is found, it will convert the first first valid ISBN-10 to an ISBN-13 and send that as the identifier.

The ISBN field has further options:

##### Force the use of the first ISBN if sending ISBN in the LIN segment.

This allows the plugin to ensure that the first ISBN is the only one that might be used for the LIN segment.

##### Allow invalid ISBN-13s to be used for the LIN segment. ISBN must be exactly 13 characters.

If the vendor uses invalid ISBN-13s as internal identifiers ( such as Baker & Taylor ), this option will allow invalid ISBN-13s to be used in the LIN segment.

##### Allow the use of any invalid ISBN in the LIN segment.

This option will allow even invalid ISBNs that do not have 13 characters to be transmitted in the LIN segment. Best practice is to try for invalid ISBN-13s first.

#### UPC

Send the UPC as the LIN identifier.
The UPC must be stored in the MARC record in field 024$a.

#### Product ID

Send the Product ID as the LIN identifier.
The Product ID must be stored in the MARC record in field 028$a.

### PIA values

Within each LIN segment can be multiple PIA segments.
This section controls which values of looked for and sent in PIA segments.
These options are not mutually exclusive. For each identifier type selected, a PIA segment will be sent.

#### EAN

Send the EAN as a PIA identifier

#### ISSN

Send the ISSN as a PIA identifier

#### ISBN-10

Send all ISBN-10s as PIA identifiers.

#### ISBN-13

Send all ISBN-13s as PIA identifiers.

#### UPC

Send the UPC as a PIA identifier.
The UPC must be stored in the MARC record in field 024$a.

#### Product ID

Send the Product ID as a PIA identifier.
The Product ID must be stored in the MARC record in field 028$a.

#### MARC fields

Send values from the bibliographic record as additional PIA identifiers.
The setting is a YAML list, sent in the order written, where each entry has the field and subfield and the item number type qualifier the vendor expects:

```yaml
- field: 037$a
  qualifier: SA
- field: 949$o
  qualifier: IN
```

One PIA segment is sent per occurrence of each field and the value is escaped for EDIFACT.
A value already sent in the LIN segment is skipped.
These are sent before the identifiers above, so the PIA limit doesn't leave them out.
Amazon Business, for example, wants the ASIN ( 037$a ) and the Amazon Offer ID, which has no standard MARC field so a local 9xx field is used.

### GIR values

Each item on an order is represented by a set of GIR values. The default for Koha is:
* LLO - Owning library
* LST - Item type
* LSQ - Shelving location
* LSM - Call number

This section allows you to replace this default list with your own values. The setting should contain a list of key/value pairs of the format:
key: value
The space after the colon is important. Don't forget it!
The key is the name of the GIR field to be sent ( e.g. LLO, LST, etc. )
The value is the name of any column in the Koha items table ( e.g. homebranch, itemnumber, itemcallnumber, etc )

This setting completely replaces the GIR segements sent by default. The values are not additional.

### Order contact and addresses

#### Contact name and email

Some vendors require a contact for the account the order is being placed under. If set, the contact name is sent in a CTA+OC segment and the email in a COM segment, directly after the buyer NAD segments in the order header. For Amazon Business, the email must be the email address used to log in and order on Amazon Business, which may differ from any email stored in Koha.

#### Ship-to and bill-to addresses

Some vendors require the full ship-to and bill-to name and address in the order rather than just the buyer identifier. These options send NAD segments containing the library name, street address, city, state, zip and country. The ship-to address comes from the basket's delivery library and the bill-to address from the basket's billing library, falling back to the library EAN's branch if the basket doesn't specify one. The NAD party qualifiers are selectable ( DP or ST for ship-to, IV or BT for bill-to ), your vendor's EDI specification should say which ones they expect. The address data comes straight from the library's record in Koha administration, so make sure those addresses are filled in, and note that some vendors require a two letter state code and a two letter country code.

### Other ORDER configurations

#### Send basket name

By default Koha sends the basket number as the order identifier. This option sends the basket name instead. This is useful if you need to contact the vendor to look into a particular order, as the basket name is easier to look up and tell the vendor. It's possible that a vendor may not be able to handle an alphanumeric order identifier, but all vendors we've worked with so far can.

### Other INVOICE configurations

#### Shipping budget from order line

Set the invoice shipping cost fund to the fund used for the last order line of an invoice.
The use of the last order line is arbitrary. The feature basically assumes that all the order lines on the given invoice use the same fund. By always using the last one we can know which fund was used deterministicaly.

#### Close invoice on receipt

When an invoice is received, set it to closed automatically.
This option is mildly dangerous but highly convenient. It assumes a vendor will always get your shipments to you correctly.

### Invoice adjustment filters

Each rule under *Invoice Adjustments from MOA Segments* matches a MOA qualifier. Because a qualifier alone often can't tell two charges apart, a rule can also carry filters tested against the segments governing the MOA. Click a rule's **Filters** button to edit them. A rule with no filters matches on the qualifier alone, and where a rule has several filters all of them must match.

| Field | Meaning |
| --- | --- |
| Segment | A segment tag such as `ALC`, `TAX`, `PAT`, `AJT`, `FTX` or `RFF`; `MOA` for the amount segment itself (element `0.0` is the qualifier, `0.1` the amount, `0.2` the currency); or one of the pseudo-fields `section` (`header`, `line` or `summary`), `line` or `currency`. |
| Element | A position within that segment, such as `4` or `4.0`. Leave it empty to test the value against every part of the segment, which is what you want when a vendor doesn't put the code where the standard says it goes. |
| Operator | `=`, `!=`, `contains` or `matches regex`. |
| Value | Compared ignoring case and surrounding spaces. |

`!=` passes when nothing in the segment matches, so it also passes when the segment isn't there at all.

Tick **Shipping** on a rule to add its matched amounts to the invoice shipping cost instead of creating an adjustment. This routes a charge, like `FGT` freight a vendor buries under a shared `MOA+8`, into the shipping cost rather than an adjustment. The reason, note, budget and encumber fields don't apply to a shipping rule.

For the four charges a vendor might send on one invoice, four rules each filtering `ALC` / `4.0` / `=` on its own code will put each charge on its own adjustment against its own fund:

| MOA Qualifier | Filter | Reason | Budget ID |
| --- | --- | --- | --- |
| 8 | `ALC` `4.0` `=` `C&P` | Cataloging | 12 |
| 8 | `ALC` `4.0` `=` `JKT` | Supplies | 14 |
| 8 | `ALC` `4.0` `=` `RFI` | Supplies | 14 |
| 8 | `ALC` `4.0` `=` `LFG` | Supplies | 14 |

