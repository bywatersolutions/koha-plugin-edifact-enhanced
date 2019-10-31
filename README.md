# Koha Enhanced Edifact Plugin

A Koha Edifact plugin that replicates the existing Edifact behavior with additional options. 
This plugin is depends on code that was made available in the 16.05 release of Koha.

This plugin requires Business::Barcode::EAN13 to be installed.

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

##### Header

If this option is selected, the Library EAN will sent in the Order header.
This is the default Koha Edifact behavior and this option is mutually exclusive with the Buyer SAN in the Header option.

##### NAD+BY

If this option is selected, the Library EAN will appear as an additional NAD+BY segment in the Order.
This option is independent of the Header option. 
If both are checked, the Library EAN will be sent in the header *and* in a NAD+BY segment.

### File suffixes

Vendors often use different file suffixes for the various Edifact messages the may be send.
This section allows you to configure the file suffixes for your vendor

### Order file

This section lets you set the suffix for the Order messages you will transmit to your vendor.

### Invoice file

This section lets you set the suffix for the Invoices messages Koha will look for from the vendor.

### LIN values

Each order line in Koha generates an LIN segment in an Edifact Order message.
These LIN segments may contain an item identifier.
This section allows you to specify which, if any identifiers are transmitted.
You may check all that apply.
The first valid identifier will be used and the rest ignored.
If you have specified a line item id for an order, it will be used in preference to the identifiers specified here.
The order of precedence is:
1. Line item id
2. EAN
3. ISSN
4. ISBN

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
