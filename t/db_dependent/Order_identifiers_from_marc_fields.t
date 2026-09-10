#!/usr/bin/perl

# This file is part of Koha.
#
# Koha is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.
#
# Koha is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with Koha; if not, see <http://www.gnu.org/licenses>.

use Modern::Perl;

use CGI;
use MARC::Field;
use MARC::Record;
use Test::More tests => 7;
use Test::NoWarnings;
use Test::Warn;

use t::lib::Mocks;
use t::lib::TestBuilder;

use C4::Biblio qw( ModBiblio );
use Koha::Database;
use Koha::Items;
use Koha::Plugin::Com::ByWaterSolutions::EdifactEnhanced;
use Koha::Plugin::Com::ByWaterSolutions::EdifactEnhanced::Edifact::Order;

my $schema  = Koha::Database->new->schema;
my $builder = t::lib::TestBuilder->new;

# Every subtest passes all of these so a previously configured plugin on the
# test system can't leak settings into the order line under test
my %BASE_SETTINGS = (
    lin_use_item_field           => q{},
    lin_use_item_field_qualifier => q{},
    lin_use_marc_field           => q{},
    lin_use_marc_field_qualifier => q{},
    lin_use_ean                  => '0',
    lin_use_issn                 => '0',
    lin_use_isbn                 => '0',
    lin_force_first_isbn         => '0',
    lin_use_invalid_isbn13       => '0',
    lin_use_invalid_isbn_any     => '0',
    lin_use_upc                  => '0',
    lin_use_product_id           => '0',
    pia_send_lin                 => '0',
    pia_limit                    => '0',
    pia_marc_fields              => q{},
    pia_use_ean                  => '0',
    pia_use_issn                 => '0',
    pia_use_isbn10               => '0',
    pia_use_isbn13               => '0',
    pia_use_upc                  => '0',
    pia_use_product_id           => '0',
    gir_disable                  => '1',
);

# The record needs an ISBN so biblioitems.isbn is set, order_line() splits
# it without checking for undef
my $isbn_field   = MARC::Field->new( '020', '', '', a => '9780306406157' );
my $asin_field   = MARC::Field->new( '037', '', '', a => 'B08XYZ1234', b => 'Amazon' );
my $second_asin  = MARC::Field->new( '037', '', '', a => 'B08SECOND' );
my $offer_field  = MARC::Field->new( '949', '', '', o => 'OFFER+ID:1?' );
my $pia_yaml     = "- field: 037\$a\n  qualifier: SA\n- field: 949\$o\n  qualifier: IN\n";
my $pia_reversed = "- field: 949\$o\n  qualifier: IN\n- field: 037\$a\n  qualifier: SA\n";

sub _new_plugin {
    my (%settings) = @_;
    my $plugin = Koha::Plugin::Com::ByWaterSolutions::EdifactEnhanced->new( { enable_plugins => 1, cgi => CGI->new } );
    $plugin->store_data( { %BASE_SETTINGS, %settings } );
    return $plugin;
}

# Build the fixtures order_line() touches: vendor, sender library EAN, basket
# and one orderline on a bib carrying the MARC fields under test
sub _build_order_fixture {
    my (%args) = @_;

    my $vendor = $builder->build_object(
        {
            class => 'Koha::Acquisition::Booksellers',
            value => { name => 'Test Vendor' },
        }
    );

    my $sender_ean = $builder->build(
        {
            source => 'EdifactEan',
            value  => {
                description       => 'TEST',
                ean               => '5099999999990',
                id_code_qualifier => '14',
                branchcode        => undef,
            },
        }
    );
    my $sender = $schema->resultset('EdifactEan')->find( $sender_ean->{ee_id} );

    my $basket = $builder->build_object(
        {
            class => 'Koha::Acquisition::Baskets',
            value => { booksellerid => $vendor->id },
        }
    );

    my $biblio = $builder->build_sample_biblio;
    my $record = $biblio->metadata->record;
    $record->append_fields( @{ $args{marc_fields} } );
    ModBiblio( $record, $biblio->biblionumber, $biblio->frameworkcode );

    # order_line() walks DBIx::Class relations, so it needs the schema row
    my $orderline_obj = $builder->build_object(
        {
            class => 'Koha::Acquisition::Orders',
            value => {
                basketno     => $basket->basketno,
                biblionumber => $biblio->biblionumber,
                quantity     => 1,
                line_item_id => $args{line_item_id},
            }
        }
    );
    my $orderline = $schema->resultset('Aqorder')->find( $orderline_obj->ordernumber );

    if ( $args{item_note} ) {
        my $item = $builder->build_sample_item(
            {
                biblionumber        => $biblio->biblionumber,
                itemnotes_nonpublic => $args{item_note},
            }
        );
        $builder->build(
            {
                source => 'AqordersItem',
                value  => {
                    ordernumber => $orderline_obj->ordernumber,
                    itemnumber  => $item->itemnumber,
                },
            }
        );
    }

    return ( $vendor, $sender, $orderline );
}

sub _order_line_segs {
    my ( $plugin, $vendor, $sender, $orderline ) = @_;

    my $edi_order = Koha::Plugin::Com::ByWaterSolutions::EdifactEnhanced::Edifact::Order->new(
        {
            orderlines => [$orderline],
            vendor     => $vendor,
            ean        => $sender,
            plugin     => $plugin,
        }
    );
    $edi_order->order_line( 1, $orderline );
    return @{ $edi_order->{segs} };
}

sub _lin_seg {
    return ( grep { /^LIN\+/ } @_ )[0];
}

sub _pia_segs {
    return [ grep { /^PIA\+/ } @_ ];
}

sub _lin_and_pia_segs {
    return [ grep { /^LIN\+|^PIA\+/ } @_ ];
}

subtest '_get_marc_values() tests' => sub {
    plan tests => 8;

    my $record = MARC::Record->new;
    $record->append_fields(
        MARC::Field->new( '001', 'CONTROL001' ),
        MARC::Field->new( '037', '', '', a => ' B08XYZ1234 ', b => 'Amazon' ),
        MARC::Field->new( '037', '', '', a => 'B08SECOND' ),
        MARC::Field->new( '037', '', '', a => 'B08SECOND' ),
        MARC::Field->new( '949', '', '', o => '   ' ),
    );

    my $get_values = \&Koha::Plugin::Com::ByWaterSolutions::EdifactEnhanced::Edifact::Order::_get_marc_values;

    is_deeply(
        [ $get_values->( $record, '037$a' ) ],
        [ 'B08XYZ1234', 'B08SECOND' ],
        'every occurrence of the subfield is returned in record order, trimmed and without duplicates'
    );
    is_deeply(
        [ $get_values->( $record, ' 037$a ' ) ],
        [ 'B08XYZ1234', 'B08SECOND' ],
        'whitespace around the spec is ignored'
    );
    is_deeply( [ $get_values->( $record, '001' ) ],   ['CONTROL001'], 'a bare tag returns the control field data' );
    is_deeply( [ $get_values->( $record, '949$o' ) ], [],             'blank subfields are dropped' );
    is_deeply( [ $get_values->( $record, '035$a' ) ], [],             'a tag the record lacks returns nothing' );
    is_deeply( [ $get_values->( $record, '37$a' ) ],  [],             'a malformed tag returns nothing' );
    is_deeply( [ $get_values->( $record, q{} ) ],     [],             'an empty spec returns nothing' );
    is_deeply( [ $get_values->( undef,   '037$a' ) ], [],             'no record returns nothing' );
};

subtest 'LIN from MARC field tests' => sub {
    plan tests => 4;
    $schema->storage->txn_begin;
    t::lib::Mocks::mock_preference( 'AcqCreateItem', 'cataloguing' );

    my ( $vendor, $sender, $orderline ) =
        _build_order_fixture( marc_fields => [ $isbn_field, $asin_field, $second_asin, $offer_field ] );

    my @segs = _order_line_segs(
        _new_plugin( lin_use_marc_field => '037$a', lin_use_marc_field_qualifier => 'SA' ),
        $vendor, $sender, $orderline
    );
    is( _lin_seg(@segs), "LIN+1++B08XYZ1234:SA'", 'the first occurrence of the configured field is the LIN identifier' );
    is_deeply( _pia_segs(@segs), [], 'no PIA segments are sent without PIA options' );

    @segs = _order_line_segs(
        _new_plugin( lin_use_marc_field => '949$o', lin_use_marc_field_qualifier => 'IN' ),
        $vendor, $sender, $orderline
    );
    is( _lin_seg(@segs), "LIN+1++OFFER?+ID?:1??:IN'", 'EDIFACT service characters in the value are escaped' );

    @segs = _order_line_segs(
        _new_plugin( lin_use_marc_field => '037$a', lin_use_marc_field_qualifier => 'SA', pia_send_lin => '1' ),
        $vendor, $sender, $orderline
    );
    is_deeply( _pia_segs(@segs), ["PIA+1+B08XYZ1234:SA'"], 'pia_send_lin repeats the MARC field identifier as a PIA' );

    $schema->storage->txn_rollback;
};

subtest 'LIN from MARC field cascade tests' => sub {
    plan tests => 5;
    $schema->storage->txn_begin;
    t::lib::Mocks::mock_preference( 'AcqCreateItem', 'cataloguing' );

    my %marc_config = ( lin_use_marc_field => '037$a', lin_use_marc_field_qualifier => 'SA' );

    # The record has no 037, so the MARC field option has nothing to send
    my ( $vendor, $sender, $orderline ) =
        _build_order_fixture( marc_fields => [$isbn_field], line_item_id => 'LINE-ITEM-1' );
    my @segs = _order_line_segs( _new_plugin(%marc_config), $vendor, $sender, $orderline );
    is( _lin_seg(@segs), "LIN+1++LINE-ITEM-1:EN'", 'falls through to the line item id when the record lacks the field' );

    ( $vendor, $sender, $orderline ) =
        _build_order_fixture( marc_fields => [ $isbn_field, $asin_field ], line_item_id => 'LINE-ITEM-1' );
    @segs = _order_line_segs( _new_plugin(%marc_config), $vendor, $sender, $orderline );
    is( _lin_seg(@segs), "LIN+1++B08XYZ1234:SA'", 'the MARC field outranks the line item id' );

    @segs = _order_line_segs(
        _new_plugin( lin_use_marc_field => '037$a', lin_use_marc_field_qualifier => q{} ),
        $vendor, $sender, $orderline
    );
    is( _lin_seg(@segs), "LIN+1++LINE-ITEM-1:EN'", 'the option is inactive without a qualifier' );

    # An item field value wins over the MARC field, which is used when the
    # item field yields nothing, here because the item no longer exists
    ( $vendor, $sender, $orderline ) =
        _build_order_fixture( marc_fields => [ $isbn_field, $asin_field ], item_note => 'INTERNAL-LIN-XYZ' );
    my %both_config = ( %marc_config, lin_use_item_field => 'itemnotes_nonpublic', lin_use_item_field_qualifier => 'IB' );
    @segs = _order_line_segs( _new_plugin(%both_config), $vendor, $sender, $orderline );
    is( _lin_seg(@segs), "LIN+1++INTERNAL-LIN-XYZ:IB'", 'an item field value still wins over the MARC field' );

    my ($aqorder_item) = $orderline->aqorders_items;
    Koha::Items->find( $aqorder_item->itemnumber )->delete;
    @segs = _order_line_segs( _new_plugin(%both_config), $vendor, $sender, $orderline );
    is( _lin_seg(@segs), "LIN+1++B08XYZ1234:SA'", 'the MARC field is used when the item field yields nothing' );

    $schema->storage->txn_rollback;
};

subtest 'PIA from MARC fields tests' => sub {
    plan tests => 4;
    $schema->storage->txn_begin;
    t::lib::Mocks::mock_preference( 'AcqCreateItem', 'cataloguing' );

    my ( $vendor, $sender, $orderline ) =
        _build_order_fixture( marc_fields => [ $isbn_field, $asin_field, $offer_field ], line_item_id => 'LINE-ITEM-1' );

    my @segs = _order_line_segs( _new_plugin( pia_marc_fields => $pia_yaml ), $vendor, $sender, $orderline );
    is_deeply(
        _pia_segs(@segs),
        [ "PIA+1+B08XYZ1234:SA'", "PIA+1+OFFER?+ID?:1??:IN'" ],
        'one PIA per configured field, in the configured order, with the value escaped'
    );

    @segs = _order_line_segs( _new_plugin( pia_marc_fields => $pia_reversed ), $vendor, $sender, $orderline );
    is_deeply(
        _pia_segs(@segs),
        [ "PIA+1+OFFER?+ID?:1??:IN'", "PIA+1+B08XYZ1234:SA'" ],
        'the order of the configuration is the order of the segments'
    );

    my %lin_and_pia = ( pia_marc_fields => $pia_yaml, lin_use_marc_field => '037$a', lin_use_marc_field_qualifier => 'SA' );
    @segs = _order_line_segs( _new_plugin(%lin_and_pia), $vendor, $sender, $orderline );
    is_deeply(
        _lin_and_pia_segs(@segs),
        [ "LIN+1++B08XYZ1234:SA'", "PIA+1+OFFER?+ID?:1??:IN'" ],
        'a value already sent in the LIN is not repeated as a PIA'
    );

    ( $vendor, $sender, $orderline ) = _build_order_fixture( marc_fields => [ $isbn_field, $asin_field, $second_asin ] );
    @segs = _order_line_segs( _new_plugin(%lin_and_pia), $vendor, $sender, $orderline );
    is_deeply(
        _lin_and_pia_segs(@segs),
        [ "LIN+1++B08XYZ1234:SA'", "PIA+1+B08SECOND:SA'" ],
        'a repeated field sends its other occurrences as PIAs'
    );

    $schema->storage->txn_rollback;
};

subtest 'PIA from MARC fields function code and limit tests' => sub {
    plan tests => 2;
    $schema->storage->txn_begin;
    t::lib::Mocks::mock_preference( 'AcqCreateItem', 'cataloguing' );

    # Nothing is configured for the LIN, so the LIN segment carries no identifier
    my ( $vendor, $sender, $orderline ) =
        _build_order_fixture( marc_fields => [ $isbn_field, $asin_field, $offer_field ] );

    my @segs = _order_line_segs( _new_plugin( pia_marc_fields => $pia_yaml, pia_limit => '2' ), $vendor, $sender, $orderline );
    is_deeply(
        _lin_and_pia_segs(@segs),
        [ "LIN+1'", "PIA+5+B08XYZ1234:SA'", "PIA+1+OFFER?+ID?:1??:IN'" ],
        'without a LIN identifier the first PIA is the product identification and the rest are additional'
    );

    @segs = _order_line_segs( _new_plugin( pia_marc_fields => $pia_yaml, pia_limit => '1' ), $vendor, $sender, $orderline );
    is_deeply( _pia_segs(@segs), ["PIA+5+B08XYZ1234:SA'"], 'the PIA limit is honoured' );

    $schema->storage->txn_rollback;
};

subtest 'PIA from MARC fields configuration error tests' => sub {
    plan tests => 6;
    $schema->storage->txn_begin;
    t::lib::Mocks::mock_preference( 'AcqCreateItem', 'cataloguing' );

    my ( $vendor, $sender, $orderline ) =
        _build_order_fixture( marc_fields => [ $isbn_field, $asin_field, $offer_field ], line_item_id => 'LINE-ITEM-1' );

    my @segs;
    warning_like {
        @segs = _order_line_segs( _new_plugin( pia_marc_fields => "- field: 037\$a\n qualifier: SA\n" ), $vendor, $sender, $orderline );
    }
    qr/ERROR PARSING pia_marc_fields/, 'malformed YAML is reported';
    is_deeply( _lin_and_pia_segs(@segs), ["LIN+1++LINE-ITEM-1:EN'"], 'and the order line is still generated, without PIAs' );

    warning_like {
        @segs = _order_line_segs( _new_plugin( pia_marc_fields => "037\$a: SA\n" ), $vendor, $sender, $orderline );
    }
    qr/expected a YAML list/, 'a mapping instead of a list is reported';
    is_deeply( _pia_segs(@segs), [], 'and sends no PIAs' );

    warning_like {
        @segs = _order_line_segs(
            _new_plugin( pia_marc_fields => "- field: 037\$a\n- field: 949\$o\n  qualifier: IN\n" ),
            $vendor, $sender, $orderline
        );
    }
    qr/SKIPPING pia_marc_fields entry/, 'an entry without a qualifier is reported';
    is_deeply( _pia_segs(@segs), ["PIA+1+OFFER?+ID?:1??:IN'"], 'and the complete entry is still sent' );

    $schema->storage->txn_rollback;
};
