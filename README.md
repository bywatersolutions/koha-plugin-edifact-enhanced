# Koha Enhanced Edifact Plugin

A Koha Edifact plugin that replicates the existing Edifact behavior with additional options. 
This plugin is depends on code that was made available in the 16.05 release of Koha.

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

### PIA values

Within each LIN segment can be multiple PIA segments.
This section controls which values of looked for and sent in PIA segments.
These options are not mutually exclusive. For each identifier type selected, a PIA segment will be sent.

#### EAN

Send the EAN as a PIA identifier

#### ISSN

Send the ISSN as a PIA identifier

#### ISBN-10

Send all ISBN-10s as LIN identifiers.

#### ISBN-13

Send all ISBN-13s as LIN identifiers.
