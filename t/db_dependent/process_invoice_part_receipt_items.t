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
use Test::More tests => 3;
use Test::NoWarnings;

use t::lib::Mocks;
use t::lib::TestBuilder;

use Koha::Acquisition::Invoices;
use Koha::Acquisition::Orders;
use Koha::Database;
use Koha::Items;
use Koha::Plugins;
use Koha::Plugin::Com::ByWaterSolutions::EdifactEnhanced;

my $schema  = Koha::Database->new->schema;
my $builder = t::lib::TestBuilder->new;

# edifact_process_invoice routes through Koha::Plugins::Handler->run, which
# requires the plugin's methods to be present in the koha_plugins_methods table
Koha::Plugins->new( { enable_plugins => 1 } )->InstallPlugins( { include => ['Koha::Plugin::Com::ByWaterSolutions::EdifactEnhanced'] } );

# Every subtest passes all of these so a previously configured plugin on the
# test system can't change how the invoice is processed
my %BASE_SETTINGS = (
    skip_nonmatching_san_suffix         => '0',
    set_bookseller_from_order_basket    => '0',
    update_pricing_from_vendor_settings => '0',
    ignore_duplicate_reciepts           => '0',
    ship_budget_from_orderline          => '0',
    add_tax_to_shipping_costs           => '0',
    close_invoice_on_receipt            => '0',
    no_update_item_price                => 'update_neither',
    set_nfl_on_receipt                  => q{},
    lin_use_item_field_clear_on_invoice => '0',
    add_itemnote_on_receipt             => '0',
    invoice_adjustment_rules            => '[]',
);

# One invoice line receiving $quantity copies of $ordernumber, with a GIR branch
# for each copy when @branches is given. Brodart invoices carry no GIR segments.
sub _invoic_string {
    my ( $supplier_san, $ordernumber, $quantity, @branches ) = @_;
    return join q{},
        q{UNA:+.? },
        q{'UNB+UNOC:3+} . $supplier_san . q{+5013546098818+230101:0000+0000000003},
        q{'UNH+00003+INVOIC:D:96A:UN},
        q{'BGM+380+INV-PART-001+9},
        q{'DTM+137:20240115:102},
        q{'NAD+BY+12345::9},
        q{'NAD+SU+} . $supplier_san . q{::9},
        q{'LIN+1++9780000000002:EN},
        q{'QTY+47:} . $quantity,
        ( map { q{'GIR+} . sprintf( '%03d', $_ + 1 ) . q{+} . $branches[$_] . q{:LLO} } 0 .. $#branches ),
        q{'MOA+203:} . sprintf( '%.2f', 10 * $quantity ),
        q{'PRI+AAA:10.00},
        q{'RFF+LI:} . $ordernumber,
        q{'UNS+S},
        q{'CNT+2:1},
        q{'MOA+86:} . sprintf( '%.2f', 10 * $quantity ),
        q{'UNT+15+00003},
        q{'UNZ+1+0000000003'};
}

# An open order with one copy, and one linked item, per homebranch given
sub _build_order {
    my ( $vendor, @homebranches ) = @_;

    my $basket = $builder->build_object(
        {
            class => 'Koha::Acquisition::Baskets',
            value => { booksellerid => $vendor->id, is_standing => 0 },
        }
    );
    my $biblio = $builder->build_sample_biblio;
    my $order  = $builder->build_object(
        {
            class => 'Koha::Acquisition::Orders',
            value => {
                basketno         => $basket->basketno,
                biblionumber     => $biblio->biblionumber,
                quantity         => scalar @homebranches,
                quantityreceived => 0,
                orderstatus      => 'ordered',
                datereceived     => undef,
                invoiceid        => undef,
            }
        }
    );

    for my $homebranch (@homebranches) {
        my $item = $builder->build_sample_item( { biblionumber => $biblio->biblionumber, homebranch => $homebranch } );

        # Cleared so we can tell which items _receipt_items updated
        $item->booksellerid(undef)->store;

        $builder->build(
            {
                source => 'AqordersItem',
                value  => { ordernumber => $order->ordernumber, itemnumber => $item->itemnumber },
            }
        );
    }

    return $order;
}

sub _process_invoice {
    my ( $vendor, $san, $body ) = @_;

    my $file_transport = $builder->build( { source => 'FileTransport', value => { transport => 'local' } } );
    my $edi_account    = $builder->build(
        {
            source => 'VendorEdiAccount',
            value  => {
                description       => 'TEST',
                vendor_id         => $vendor->id,
                file_transport_id => $file_transport->{file_transport_id},
                plugin            => 'Koha::Plugin::Com::ByWaterSolutions::EdifactEnhanced',
                san               => $san,
                shipment_budget   => undef,
            }
        }
    );
    my $msg = $builder->build(
        {
            source => 'EdifactMessage',
            value  => {
                vendor_id    => $vendor->id,
                edi_acct     => $edi_account->{id},
                message_type => 'INVOIC',
                status       => 'new',
                deleted      => 0,
                filename     => "test-part-$$-" . int( rand 1_000_000 ) . ".CEI",
                raw_msg      => $body,
                basketno     => undef,
            }
        }
    );

    my $plugin = Koha::Plugin::Com::ByWaterSolutions::EdifactEnhanced->new( { enable_plugins => 1, cgi => CGI->new } );
    $plugin->store_data( \%BASE_SETTINGS );

    {
        local $SIG{__WARN__} = sub { };
        $plugin->edifact_process_invoice( { invoice => $schema->resultset('EdifactMessage')->find( $msg->{id} ) } );
    }

    return Koha::Acquisition::Invoices->search( { invoicenumber => 'INV-PART-001' } )->next;
}

sub _linked_items {
    my ($ordernumber) = @_;
    my @itemnumbers =
        map { $_->itemnumber } $schema->resultset('AqordersItem')->search( { ordernumber => $ordernumber } )->all;
    return Koha::Items->search( { itemnumber => \@itemnumbers }, { order_by => 'itemnumber' } )->as_list;
}

subtest 'part receipt without GIR segments links the received copies to the new order' => sub {
    plan tests => 6;
    $schema->storage->txn_begin;
    t::lib::Mocks::mock_preference( 'AcqCreateItem',                   'ordering' );
    t::lib::Mocks::mock_preference( 'AcqItemSetSubfieldsWhenReceived', q{} );

    my $san     = '5099999000075';
    my $vendor  = $builder->build_object( { class => 'Koha::Acquisition::Booksellers' } );
    my $library = $builder->build_object( { class => 'Koha::Libraries' } );
    my $order   = _build_order( $vendor, ( $library->branchcode ) x 3 );

    my $invoice  = _process_invoice( $vendor, $san, _invoic_string( $san, $order->ordernumber, 2 ) );
    my $received = Koha::Acquisition::Orders->search( { invoiceid => $invoice->invoiceid } )->next;
    $order->discard_changes;

    is( $order->quantity,    1,         'one copy left on the original order' );
    is( $received->quantity, 2,         'two copies on the received order' );
    is( $order->orderstatus, 'partial', 'original order is partial' );

    my @received_items  = _linked_items( $received->ordernumber );
    my @remaining_items = _linked_items( $order->ordernumber );
    is( scalar @received_items,  2, 'two items moved to the received order' );
    is( scalar @remaining_items, 1, 'one item left on the original order' );
    is_deeply(
        [ map { $_->booksellerid } @received_items ],
        [ $vendor->id, $vendor->id ],
        'receipt updates were applied to the received items'
    );

    $schema->storage->txn_rollback;
};

subtest 'part receipt with GIR segments moves the item at the GIR branch' => sub {
    plan tests => 2;
    $schema->storage->txn_begin;
    t::lib::Mocks::mock_preference( 'AcqCreateItem',                   'ordering' );
    t::lib::Mocks::mock_preference( 'AcqItemSetSubfieldsWhenReceived', q{} );

    my $san       = '5099999000082';
    my $vendor    = $builder->build_object( { class => 'Koha::Acquisition::Booksellers' } );
    my @libraries = map { $builder->build_object( { class => 'Koha::Libraries' } )->branchcode } 1 .. 3;
    my $order     = _build_order( $vendor, @libraries );

    my $invoice  = _process_invoice( $vendor, $san, _invoic_string( $san, $order->ordernumber, 1, $libraries[2] ) );
    my $received = Koha::Acquisition::Orders->search( { invoiceid => $invoice->invoiceid } )->next;

    is_deeply(
        [ map { $_->homebranch } _linked_items( $received->ordernumber ) ],
        [ $libraries[2] ],
        'the item at the GIR branch moved to the received order'
    );
    is_deeply(
        [ map { $_->homebranch } _linked_items( $order->ordernumber ) ],
        [ @libraries[ 0, 1 ] ],
        'the items at the other branches stayed on the original order'
    );

    $schema->storage->txn_rollback;
};
