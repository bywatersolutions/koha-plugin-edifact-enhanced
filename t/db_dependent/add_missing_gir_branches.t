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
use Test::NoWarnings;

use t::lib::TestBuilder;

use Koha::Database;
use Koha::Plugin::Com::ByWaterSolutions::EdifactEnhanced;
use Koha::Plugin::Com::ByWaterSolutions::EdifactEnhanced::Edifact;

my $schema  = Koha::Database->new->schema;
my $builder = t::lib::TestBuilder->new;

# _add_missing_gir_branches writes into Koha::Edifact::Line's GIR data directly,
# because Line has no setter for it. Every check here reads the result back
# through Line's own girfield and number_of_girs, so these tests fail if core
# changes how Line stores GIR data.

# A real Koha::Edifact::Line, parsed from a one line invoice
sub _invoice_line {
    my ( $quantity, @girs ) = @_;
    my $invoic = join q{},
        q{UNA:+.? },
        q{'UNB+UNOC:3+5013546027173+5013546098818+230101:0000+0000000001},
        q{'UNH+00001+INVOIC:D:96A:UN},
        q{'BGM+380+INV-GIR-001+9},
        q{'DTM+137:20240115:102},
        q{'LIN+1++9780000000002:EN},
        q{'QTY+47:} . $quantity,
        ( map { q{'} . $_ } @girs ),
        q{'MOA+203:10.00},
        q{'RFF+LI:1},
        q{'UNS+S},
        q{'CNT+2:1},
        q{'UNT+10+00001},
        q{'UNZ+1+0000000001'};

    my ($msg) = @{ Koha::Plugin::Com::ByWaterSolutions::EdifactEnhanced::Edifact->new( { transmission => $invoic } )->message_array };
    return $msg->lineitems->[0];
}

# An order with one linked item per homebranch given, in itemnumber order
sub _build_order {
    my (@homebranches) = @_;

    my $biblio = $builder->build_sample_biblio;
    my $order  = $builder->build_object(
        {
            class => 'Koha::Acquisition::Orders',
            value => { biblionumber => $biblio->biblionumber, quantity => scalar @homebranches },
        }
    );

    for my $homebranch (@homebranches) {
        my $item = $builder->build_sample_item( { biblionumber => $biblio->biblionumber, homebranch => $homebranch } );
        $builder->build(
            {
                source => 'AqordersItem',
                value  => { ordernumber => $order->ordernumber, itemnumber => $item->itemnumber },
            }
        );
    }

    return $order;
}

sub _add_missing_gir_branches {
    my ( $line, $order, $quantity ) = @_;
    my $plugin = Koha::Plugin::Com::ByWaterSolutions::EdifactEnhanced->new( { enable_plugins => 1, cgi => CGI->new } );
    Koha::Plugin::Com::ByWaterSolutions::EdifactEnhanced::_add_missing_gir_branches( $plugin, $line, $order, $quantity );
    return;
}

subtest 'a line with no GIR segments gets the homebranches of the items on the order' => sub {
    plan tests => 5;
    $schema->storage->txn_begin;

    my @libraries = map { $builder->build_object( { class => 'Koha::Libraries' } )->branchcode } 1 .. 3;
    my $order     = _build_order(@libraries);
    my $line      = _invoice_line(2);

    isa_ok( $line, 'Koha::Edifact::Line', 'the line under test' );

    _add_missing_gir_branches( $line, $order, 2 );

    is( $line->number_of_girs, 2, 'one GIR for each copy invoiced' );
    is( $line->girfield( 'branch', 0 ), $libraries[0], 'first copy has the first item homebranch' );
    is( $line->girfield( 'branch', 1 ), $libraries[1], 'second copy has the second item homebranch' );
    is( $line->girfield( 'branch', 2 ), undef,         'no branch beyond the copies invoiced' );

    $schema->storage->txn_rollback;
};

subtest 'GIR branches sent by the vendor are kept' => sub {
    plan tests => 2;
    $schema->storage->txn_begin;

    my @libraries = map { $builder->build_object( { class => 'Koha::Libraries' } )->branchcode } 1 .. 3;
    my $order     = _build_order(@libraries);
    my $line      = _invoice_line( 1, "GIR+001+$libraries[2]:LLO" );

    _add_missing_gir_branches( $line, $order, 1 );

    is( $line->number_of_girs,          1,             'still one GIR' );
    is( $line->girfield( 'branch', 0 ), $libraries[2], 'the vendor GIR branch was not replaced' );

    $schema->storage->txn_rollback;
};

subtest 'other GIR data on a copy is kept when its branch is filled in' => sub {
    plan tests => 3;
    $schema->storage->txn_begin;

    my @libraries = map { $builder->build_object( { class => 'Koha::Libraries' } )->branchcode } 1 .. 2;
    my $order     = _build_order(@libraries);
    my $line      = _invoice_line( 1, 'GIR+001+SEQ42:LSQ' );

    _add_missing_gir_branches( $line, $order, 1 );

    is( $line->number_of_girs, 1, 'still one GIR' );
    is( $line->girfield( 'branch',        0 ), $libraries[0], 'the branch was filled in' );
    is( $line->girfield( 'sequence_code', 0 ), 'SEQ42',       'the sequence code sent by the vendor is still there' );

    $schema->storage->txn_rollback;
};
