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

use t::lib::Mocks;
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
    gir_disable                  => '1',
);

sub _new_plugin {
    my (%settings) = @_;
    my $plugin = Koha::Plugin::Com::ByWaterSolutions::EdifactEnhanced->new( { enable_plugins => 1, cgi => CGI->new } );
    $plugin->store_data( { %BASE_SETTINGS, %settings } );
    return $plugin;
}

# Build the fixtures order_line() touches: vendor, sender library EAN, basket
# and one orderline on a bib that has both an ISBN-10 and an ISBN-13
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
            value => { booksellerid => $vendor->id },
        }
    );

    my $biblio = $builder->build_sample_biblio;
    my $record = $biblio->metadata->record;
    $record->append_fields(
        MARC::Field->new( '020', '', '', a => '0306406152' ),
        MARC::Field->new( '020', '', '', a => '9780306406157' ),
    );
    ModBiblio( $record, $biblio->biblionumber, $biblio->frameworkcode );

    # order_line() walks DBIx::Class relations, so it needs the schema row.
    # The line item id keeps the LIN identifier away from the ISBNs
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

    return ( $vendor, $sender, $orderline );
}

sub _pia_segs {
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
    return [ grep { /^PIA\+/ } @{ $edi_order->{segs} } ];
}

subtest 'PIA ISBN-10 and ISBN-13 option tests' => sub {
    plan tests => 4;
    $schema->storage->txn_begin;
    t::lib::Mocks::mock_preference( 'AcqCreateItem', 'cataloguing' );

    my ( $vendor, $sender, $orderline ) = _build_order_fixture();

    my $segs = _pia_segs( _new_plugin( pia_use_isbn10 => '1' ), $vendor, $sender, $orderline );
    is_deeply( $segs, ["PIA+1+0306406152:IB'"], 'ISBN-10 alone sends only the ISBN-10' );

    $segs = _pia_segs( _new_plugin( pia_use_isbn13 => '1' ), $vendor, $sender, $orderline );
    is_deeply( $segs, ["PIA+1+9780306406157:EN'"], 'ISBN-13 alone sends only the ISBN-13' );

    $segs = _pia_segs( _new_plugin( pia_use_isbn10 => '1', pia_use_isbn13 => '1' ), $vendor, $sender, $orderline );
    is_deeply(
        $segs,
        [ "PIA+1+0306406152:IB'", "PIA+1+9780306406157:EN'" ],
        'both options send both, in the order they appear in the record'
    );

    $segs = _pia_segs( _new_plugin(), $vendor, $sender, $orderline );
    is_deeply( $segs, [], 'neither option sends no ISBN PIAs' );

    $schema->storage->txn_rollback;
};
