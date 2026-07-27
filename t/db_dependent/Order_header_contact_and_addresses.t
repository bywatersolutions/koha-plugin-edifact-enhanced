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
use Test::More tests => 4;

use t::lib::TestBuilder;

use Koha::Database;
use Koha::Plugin::Com::ByWaterSolutions::EdifactEnhanced;
use Koha::Plugin::Com::ByWaterSolutions::EdifactEnhanced::Edifact::Order;

my $schema  = Koha::Database->new->schema;
my $builder = t::lib::TestBuilder->new;

# Every subtest passes all of these so a previously configured plugin on the
# test system can't leak settings into the message under test
my %BASE_SETTINGS = (
    buyer_san_in_nadby       => '0',
    branch_ean_in_nadby      => '0',
    send_basketname          => '0',
    order_contact_name       => q{},
    order_contact_email      => q{},
    send_shipto_address      => '0',
    shipto_address_qualifier => q{},
    send_billto_address      => '0',
    billto_address_qualifier => q{},
);

sub _new_plugin {
    my (%settings) = @_;
    my $plugin = Koha::Plugin::Com::ByWaterSolutions::EdifactEnhanced->new(
        { enable_plugins => 1, cgi => CGI->new } );
    $plugin->store_data( { %BASE_SETTINGS, %settings } );
    return $plugin;
}

# Build the fixtures order_msg_header() touches: vendor EDI account,
# sender library EAN, and a basket with one orderline
sub _build_header_fixture {
    my (%args) = @_;

    my $vendor_edi = $builder->build(
        {
            source => 'VendorEdiAccount',
            value  => {
                san               => '1234567',
                id_code_qualifier => '31B',
                plugin            => 'Koha::Plugin::Com::ByWaterSolutions::EdifactEnhanced',
            },
        }
    );
    my $vendor = $schema->resultset('VendorEdiAccount')->find( $vendor_edi->{id} );

    my $sender_ean = $builder->build(
        {
            source => 'EdifactEan',
            value  => {
                description       => 'TEST',
                ean               => '5099999999990',
                id_code_qualifier => '14',
                branchcode        => $args{ean_branchcode},
            },
        }
    );
    my $sender = $schema->resultset('EdifactEan')->find( $sender_ean->{ee_id} );

    my $basket = $builder->build_object(
        {
            class => 'Koha::Acquisition::Baskets',
            value => {
                deliveryplace => $args{deliveryplace},
                billingplace  => $args{billingplace},
            },
        }
    );
    my $orderline_obj = $builder->build_object(
        {
            class => 'Koha::Acquisition::Orders',
            value => { basketno => $basket->basketno },
        }
    );
    my $orderline = $schema->resultset('Aqorder')->find( $orderline_obj->ordernumber );

    return ( $vendor, $sender, $orderline );
}

sub _header_segs {
    my ( $plugin, $vendor, $sender, $orderline ) = @_;

    my $edi_order = Koha::Plugin::Com::ByWaterSolutions::EdifactEnhanced::Edifact::Order->new(
        {
            orderlines => [$orderline],
            vendor     => $vendor,
            ean        => $sender,
            plugin     => $plugin,
        }
    );
    $edi_order->order_msg_header;
    return @{ $edi_order->{segs} };
}

sub _build_library {
    my (%address) = @_;
    return $builder->build_object( { class => 'Koha::Libraries', value => \%address } );
}

subtest 'order contact CTA and COM segments' => sub {
    plan tests => 4;
    $schema->storage->txn_begin;

    my ( $vendor, $sender, $orderline ) = _build_header_fixture();

    my $plugin = _new_plugin(
        order_contact_name  => 'EDI Team',
        order_contact_email => 'orders@example.com',
    );
    my @segs = _header_segs( $plugin, $vendor, $sender, $orderline );

    my ($cta) = grep { /^CTA/ } @segs;
    is( $cta, "CTA+OC+:EDI Team'", 'CTA+OC segment contains the contact name' );

    my ($com) = grep { /^COM/ } @segs;
    is( $com, "COM+orders\@example.com:EM'", 'COM segment contains the contact email' );

    my ($cta_index) = grep { $segs[$_] =~ /^CTA/ } 0 .. $#segs;
    my ($su_index)  = grep { $segs[$_] =~ /^NAD\+SU/ } 0 .. $#segs;
    ok( $cta_index < $su_index, 'contact segments are sent before the supplier NAD' );

    $plugin = _new_plugin( order_contact_email => 'orders@example.com' );
    @segs = _header_segs( $plugin, $vendor, $sender, $orderline );
    ($cta) = grep { /^CTA/ } @segs;
    is( $cta, "CTA+OC'", 'CTA+OC is still sent when only an email is configured' );

    $schema->storage->txn_rollback;
};

subtest 'ship-to and bill-to NAD segments from the basket libraries' => sub {
    plan tests => 4;
    $schema->storage->txn_begin;

    my $shipto_library = _build_library(
        branchname     => "St. Mary's Library",
        branchaddress1 => '123 Main St',
        branchaddress2 => 'Suite 5',
        branchaddress3 => undef,
        branchcity     => 'Springfield',
        branchstate    => 'PA',
        branchzip      => '19064',
        branchcountry  => 'US',
    );
    my $billto_library = _build_library(
        branchname     => 'Business Office',
        branchaddress1 => '456 Elm St',
        branchaddress2 => undef,
        branchaddress3 => undef,
        branchcity     => 'Springfield',
        branchstate    => 'PA',
        branchzip      => '19064',
        branchcountry  => 'US',
    );

    my ( $vendor, $sender, $orderline ) = _build_header_fixture(
        deliveryplace => $shipto_library->branchcode,
        billingplace  => $billto_library->branchcode,
    );

    my $plugin = _new_plugin(
        send_shipto_address => '1',
        send_billto_address => '1',
    );
    my @segs = _header_segs( $plugin, $vendor, $sender, $orderline );

    my ($shipto) = grep { /^NAD\+DP/ } @segs;
    is(
        $shipto,
        "NAD+DP+++St. Mary?'s Library+123 Main St:Suite 5+Springfield+PA+19064+US'",
        'ship-to NAD contains the delivery library name and address, escaped'
    );

    my ($billto) = grep { /^NAD\+IV/ } @segs;
    is(
        $billto,
        "NAD+IV+++Business Office+456 Elm St+Springfield+PA+19064+US'",
        'bill-to NAD contains the billing library name and address'
    );

    $plugin = _new_plugin(
        send_shipto_address      => '1',
        shipto_address_qualifier => 'ST',
        send_billto_address      => '1',
        billto_address_qualifier => 'BT',
    );
    @segs = _header_segs( $plugin, $vendor, $sender, $orderline );

    ok( ( grep { /^NAD\+ST/ } @segs ), 'ship-to NAD uses the configured ST qualifier' );
    ok( ( grep { /^NAD\+BT/ } @segs ), 'bill-to NAD uses the configured BT qualifier' );

    $schema->storage->txn_rollback;
};

subtest 'ship-to falls back to the library EAN branch' => sub {
    plan tests => 2;
    $schema->storage->txn_begin;

    my $ean_library = _build_library(
        branchname     => 'Northside',
        branchaddress1 => '1 Oak Ave',
        branchaddress2 => undef,
        branchaddress3 => undef,
        branchcity     => 'Mediapolis',
        branchstate    => 'IA',
        branchzip      => '52637',
        branchcountry  => 'US',
    );

    my $plugin = _new_plugin( send_shipto_address => '1' );

    my ( $vendor, $sender, $orderline ) = _build_header_fixture(
        deliveryplace  => undef,
        ean_branchcode => $ean_library->branchcode,
    );
    my @segs = _header_segs( $plugin, $vendor, $sender, $orderline );
    my ($shipto) = grep { /^NAD\+DP/ } @segs;
    is(
        $shipto,
        "NAD+DP+++Northside+1 Oak Ave+Mediapolis+IA+52637+US'",
        'EAN branch address is used when the basket has no delivery library'
    );

    ( $vendor, $sender, $orderline ) = _build_header_fixture(
        deliveryplace  => undef,
        ean_branchcode => undef,
    );
    @segs = _header_segs( $plugin, $vendor, $sender, $orderline );
    ok( !( grep { /^NAD\+DP/ } @segs ), 'no ship-to NAD when no branch can be found' );

    $schema->storage->txn_rollback;
};

subtest 'trailing empty address components are trimmed' => sub {
    plan tests => 1;
    $schema->storage->txn_begin;

    my $library = _build_library(
        branchname     => 'Northside',
        branchaddress1 => '1 Oak Ave',
        branchaddress2 => undef,
        branchaddress3 => undef,
        branchcity     => 'Mediapolis',
        branchstate    => undef,
        branchzip      => '52637',
        branchcountry  => undef,
    );

    my ( $vendor, $sender, $orderline ) = _build_header_fixture( deliveryplace => $library->branchcode );

    my $plugin = _new_plugin( send_shipto_address => '1' );
    my @segs = _header_segs( $plugin, $vendor, $sender, $orderline );
    my ($shipto) = grep { /^NAD\+DP/ } @segs;
    is(
        $shipto,
        "NAD+DP+++Northside+1 Oak Ave+Mediapolis++52637'",
        'empty middle components are kept, trailing empty components are trimmed'
    );

    $schema->storage->txn_rollback;
};
