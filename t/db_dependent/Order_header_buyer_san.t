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
use Test::More tests => 6;
use Test::NoWarnings;

use t::lib::TestBuilder;

use Koha::Database;
use Koha::Plugin::Com::ByWaterSolutions::EdifactEnhanced;
use Koha::Plugin::Com::ByWaterSolutions::EdifactEnhanced::Edifact::Order;

my $schema  = Koha::Database->new->schema;
my $builder = t::lib::TestBuilder->new;

# Every subtest passes all of these so a previously configured plugin on the
# test system can't leak settings into the message under test
my %BASE_SETTINGS = (
    buyer_san                                      => q{},
    buyer_id_code_qualifier                        => '31B',
    buyer_san_in_header                            => '1',
    buyer_san_in_nadby                             => '1',
    branch_ean_in_nadby                            => '1',
    buyer_san_extract_from_library_ean_description => '0',
    buyer_san_use_username                         => '0',
    buyer_san_use_library_ean_split_first_part     => '0',
    send_basketname                                => '0',
    order_contact_name                             => q{},
    order_contact_email                            => q{},
    send_shipto_address                            => '0',
    send_billto_address                            => '0',
);

sub _new_plugin {
    my (%settings) = @_;
    my $plugin = Koha::Plugin::Com::ByWaterSolutions::EdifactEnhanced->new( { enable_plugins => 1, cgi => CGI->new } );
    $plugin->store_data( { %BASE_SETTINGS, %settings } );
    return $plugin;
}

# Build the fixtures interchange_header() and order_msg_header() touch: vendor
# EDI account ( optionally with a file transport ), sender library EAN, and a
# basket with one orderline
sub _build_header_fixture {
    my (%args) = @_;

    my $file_transport_id;
    if ( $args{user_name} ) {
        my $file_transport = $builder->build_object(
            {
                class => 'Koha::File::Transports',
                value => { user_name => $args{user_name} },
            }
        );
        $file_transport_id = $file_transport->id;
    }

    my $vendor_edi = $builder->build(
        {
            source => 'VendorEdiAccount',
            value  => {
                san               => '7607164',
                id_code_qualifier => '31B',
                plugin            => 'Koha::Plugin::Com::ByWaterSolutions::EdifactEnhanced',
                file_transport_id => $file_transport_id,
            },
        }
    );
    my $vendor = $schema->resultset('VendorEdiAccount')->find( $vendor_edi->{id} );

    my $sender_ean = $builder->build(
        {
            source => 'EdifactEan',
            value  => {
                description       => $args{description} // 'TEST',
                ean               => $args{ean}         // 'Book Only',
                id_code_qualifier => '91',
            },
        }
    );
    my $sender = $schema->resultset('EdifactEan')->find( $sender_ean->{ee_id} );

    my $basket        = $builder->build_object( { class => 'Koha::Acquisition::Baskets' } );
    my $orderline_obj = $builder->build_object(
        {
            class => 'Koha::Acquisition::Orders',
            value => { basketno => $basket->basketno },
        }
    );
    my $orderline = $schema->resultset('Aqorder')->find( $orderline_obj->ordernumber );

    return ( $vendor, $sender, $orderline );
}

sub _new_order {
    my ( $plugin, $vendor, $sender, $orderline ) = @_;

    my $edi_order = Koha::Plugin::Com::ByWaterSolutions::EdifactEnhanced::Edifact::Order->new(
        {
            orderlines => [$orderline],
            vendor     => $vendor,
            ean        => $sender,
            plugin     => $plugin,
        }
    );

    # encode() sets this before building the UNB, we call interchange_header() directly
    $edi_order->{interchange_control_reference} = 1;

    return $edi_order;
}

sub _buyer_nads {
    my ($edi_order) = @_;
    $edi_order->order_msg_header;
    return grep { /^NAD\+BY/ } @{ $edi_order->{segs} };
}

subtest 'buyer SAN extracted from the library EAN description' => sub {
    plan tests => 2;
    $schema->storage->txn_begin;

    my ( $vendor, $sender, $orderline ) = _build_header_fixture( description => 'Summit Follett EDI SAN:{3105261}' );
    my $plugin    = _new_plugin( buyer_san_extract_from_library_ean_description => '1' );
    my $edi_order = _new_order( $plugin, $vendor, $sender, $orderline );

    like( $edi_order->interchange_header, qr/^UNB\+UNOC:3\+3105261:31B\+7607164:31B\+/, 'UNB sender is the extracted SAN' );
    is_deeply(
        [ _buyer_nads($edi_order) ],
        [ "NAD+BY+3105261::31B'", "NAD+BY+Book Only::91'" ],
        'buyer SAN NAD+BY is sent before the library EAN NAD+BY'
    );

    $schema->storage->txn_rollback;
};

subtest 'buyer SAN from the file transport user name' => sub {
    plan tests => 2;
    $schema->storage->txn_begin;

    my ( $vendor, $sender, $orderline ) = _build_header_fixture( user_name => 'WarrenCoNJ-3505898' );
    my $plugin    = _new_plugin( buyer_san_use_username => '1' );
    my $edi_order = _new_order( $plugin, $vendor, $sender, $orderline );

    like( $edi_order->interchange_header, qr/^UNB\+UNOC:3\+WarrenCoNJ-3505898:31B\+/, 'UNB sender is the user name' );
    is_deeply(
        [ _buyer_nads($edi_order) ],
        [ "NAD+BY+WarrenCoNJ-3505898::31B'", "NAD+BY+Book Only::91'" ],
        'user name is sent in NAD+BY'
    );

    $schema->storage->txn_rollback;
};

subtest 'buyer SAN from the first part of the library EAN' => sub {
    plan tests => 2;
    $schema->storage->txn_begin;

    my ( $vendor, $sender, $orderline ) = _build_header_fixture( ean => '3505898 SR' );
    my $plugin    = _new_plugin( buyer_san_use_library_ean_split_first_part => '1' );
    my $edi_order = _new_order( $plugin, $vendor, $sender, $orderline );

    like( $edi_order->interchange_header, qr/^UNB\+UNOC:3\+3505898:31B\+/, 'UNB sender is the first part of the EAN' );
    is_deeply(
        [ _buyer_nads($edi_order) ],
        [ "NAD+BY+3505898::31B'", "NAD+BY+3505898 SR::91'" ],
        'first part of the EAN is sent in NAD+BY'
    );

    $schema->storage->txn_rollback;
};

subtest 'buyer SAN from the plugin setting' => sub {
    plan tests => 2;
    $schema->storage->txn_begin;

    my ( $vendor, $sender, $orderline ) = _build_header_fixture();
    my $plugin    = _new_plugin( buyer_san => '3378454' );
    my $edi_order = _new_order( $plugin, $vendor, $sender, $orderline );

    like( $edi_order->interchange_header, qr/^UNB\+UNOC:3\+3378454:31B\+/, 'UNB sender is the configured SAN' );
    is_deeply(
        [ _buyer_nads($edi_order) ],
        [ "NAD+BY+3378454::31B'", "NAD+BY+Book Only::91'" ],
        'configured SAN is sent in NAD+BY'
    );

    $schema->storage->txn_rollback;
};

subtest 'no buyer SAN can be resolved' => sub {
    plan tests => 2;
    $schema->storage->txn_begin;

    my ( $vendor, $sender, $orderline ) = _build_header_fixture( description => 'No SAN here' );
    my $plugin    = _new_plugin( buyer_san_extract_from_library_ean_description => '1' );
    my $edi_order = _new_order( $plugin, $vendor, $sender, $orderline );

    like( $edi_order->interchange_header, qr/^UNB\+UNOC:3\+Book Only:91\+/, 'UNB sender falls back to the library EAN' );
    is_deeply( [ _buyer_nads($edi_order) ], ["NAD+BY+Book Only::91'"], 'only the library EAN NAD+BY is sent' );

    $schema->storage->txn_rollback;
};
