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
use Test::More tests => 2;
use Test::NoWarnings;

use t::lib::TestBuilder;

use C4::Biblio qw( ModBiblio );
use Koha::Database;
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
    gir_disable                  => '0',
    gir_value_replacements_map   => q{},
    split_gir                    => '0',
);

sub _new_plugin {
    my (%settings) = @_;
    my $plugin = Koha::Plugin::Com::ByWaterSolutions::EdifactEnhanced->new( { enable_plugins => 1, cgi => CGI->new } );
    $plugin->store_data( { %BASE_SETTINGS, %settings } );
    return $plugin;
}

# Build the fixtures gir_segments() touches for a basket that creates items
# at ordering time: vendor, sender library EAN, basket, an orderline on a
# bib carrying 037$a, and one item linked to the orderline
sub _build_order_fixture {
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
            value => { booksellerid => $vendor->id, create_items => 'ordering' },
        }
    );

    # The record needs an ISBN so biblioitems.isbn is set, order_line() splits
    # it without checking for undef
    my $biblio = $builder->build_sample_biblio;
    my $record = $biblio->metadata->record;
    $record->append_fields(
        MARC::Field->new( '020', '', '', a => '9780306406157' ),
        MARC::Field->new( '037', '', '', a => 'B08XYZ1234', b => 'Amazon' ),
    );
    ModBiblio( $record, $biblio->biblionumber, $biblio->frameworkcode );

    # order_line() walks DBIx::Class relations, so it needs the schema row
    my $orderline_obj = $builder->build_object(
        {
            class => 'Koha::Acquisition::Orders',
            value => {
                basketno     => $basket->basketno,
                biblionumber => $biblio->biblionumber,
                quantity     => 1,
                line_item_id => 'LINE-ITEM-1',
            }
        }
    );
    my $orderline = $schema->resultset('Aqorder')->find( $orderline_obj->ordernumber );

    my $item = $builder->build_sample_item( { biblionumber => $biblio->biblionumber } );
    $builder->build(
        {
            source => 'AqordersItem',
            value  => {
                ordernumber => $orderline_obj->ordernumber,
                itemnumber  => $item->itemnumber,
            },
        }
    );

    return ( $vendor, $sender, $orderline, $item );
}

sub _gir_segs {
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
    return [ grep { /^GIR\+/ } @{ $edi_order->{segs} } ];
}

subtest 'GIR mapping from a MARC field tests' => sub {
    plan tests => 2;
    $schema->storage->txn_begin;

    my ( $vendor, $sender, $orderline, $item ) = _build_order_fixture();
    my $itype = $item->itype;

    # Mapped tags are emitted in sorted order, so LSM comes before LST
    my $segs = _gir_segs( _new_plugin( gir_mapping => "LSM: 037\$a\nLST: itype\n" ), $vendor, $sender, $orderline );
    is_deeply( $segs, ["GIR+001+B08XYZ1234:LSM+$itype:LST'"], 'a MARC field mapping sends the value from the record' );

    $segs = _gir_segs( _new_plugin( gir_mapping => "LSM: 035\$a\nLST: itype\n" ), $vendor, $sender, $orderline );
    is_deeply( $segs, ["GIR+001+$itype:LST'"], 'a MARC field the record lacks adds nothing to the segment' );

    $schema->storage->txn_rollback;
};
