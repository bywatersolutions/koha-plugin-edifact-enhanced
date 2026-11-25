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
use File::Temp qw( tempdir );
use Test::MockModule;
use Test::More tests => 3;
use Test::NoWarnings;

use Koha::Database;
use Koha::Plugin::Com::ByWaterSolutions::EdifactEnhanced;

my $schema = Koha::Database->new->schema;

my $plugin_class = 'Koha::Plugin::Com::ByWaterSolutions::EdifactEnhanced';

# Koha calls install from the plugin constructor the first time it sees a plugin with no stored data
sub _first_install {
    $schema->resultset('PluginData')->search( { plugin_class => $plugin_class } )->delete;
    return $plugin_class->new( { enable_plugins => 1, cgi => CGI->new } );
}

subtest 'install() tests' => sub {
    plan tests => 5;
    $schema->storage->txn_begin;

    # Stand in for a vendor plugin by pointing the bundle at a directory holding a defaults.yaml
    my $bundle_path = tempdir( CLEANUP => 1 );
    open my $fh, '>', "$bundle_path/defaults.yaml" or die "Cannot write defaults.yaml: $!";
    print $fh <<'YAML';
---
order_file_suffix: epo
send_basketname: 1
split_gir: 0
gir_mapping: |
  LLO: homebranch
  LST: itype
YAML
    close $fh;
    my $mock = Test::MockModule->new($plugin_class);
    $mock->mock( 'mbf_dir', sub { return $bundle_path } );

    my $plugin = _first_install();
    is( $plugin->retrieve_data('__INSTALLED__'),     '1',   'the plugin is installed' );
    is( $plugin->retrieve_data('order_file_suffix'), 'epo', 'a text setting is stored' );
    is( $plugin->retrieve_data('split_gir'),         '0',   'a zero is stored, not skipped' );
    is( $plugin->retrieve_data('gir_mapping'), "LLO: homebranch\nLST: itype\n", 'a multi-line setting keeps its lines' );

    $plugin->store_data( { order_file_suffix => 'ord' } );
    $plugin = $plugin_class->new( { enable_plugins => 1, cgi => CGI->new } );
    is( $plugin->retrieve_data('order_file_suffix'), 'ord', 'loading an installed plugin leaves a changed setting alone' );

    $schema->storage->txn_rollback;
};

subtest 'install() without a defaults file' => sub {
    plan tests => 2;
    $schema->storage->txn_begin;

    my $plugin = _first_install();
    is( $plugin->retrieve_data('__INSTALLED__'),     '1',   'the plugin is installed' );
    is( $plugin->retrieve_data('order_file_suffix'), undef, 'no settings are stored' );

    $schema->storage->txn_rollback;
};
