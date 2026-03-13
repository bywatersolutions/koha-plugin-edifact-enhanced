#!/usr/bin/env perl

use Modern::Perl;

use File::Find;
use File::Slurp qw(read_file write_file);

my $vendor = shift @ARGV or die "Usage: $0 <VendorNameInCamelCase>\n";

# Split CamelCase into separate words, keeping acronyms together
# e.g., MyLibraryVendor -> "My Library Vendor", Enhanced -> "Enhanced", MyEnhancedVendor -> "My Enhanced Vendor"
my $vendor_name = $vendor;
$vendor_name =~ s/([a-z])([A-Z])/$1 $2/g;
$vendor_name =~ s/([A-Z]+)([A-Z][a-z])/$1 $2/g;

my $vendor_lower_dashed = lc(join('-', split(' ', $vendor_name)));

my $base_dir = 'Koha/Plugin/Com/ByWaterSolutions';

# Step 1: Rename directory and .pm file using git mv
my $old_dir = "$base_dir/EdifactEnhanced";
my $new_dir = "$base_dir/Edifact$vendor";
my $old_pm  = "$base_dir/EdifactEnhanced.pm";
my $new_pm  = "$base_dir/Edifact$vendor.pm";

if ( -d $old_dir ) {
    system( 'git', 'mv', $old_dir, $new_dir ) == 0
        or die "Failed to git mv $old_dir -> $new_dir\n";
}

if ( -f $old_pm ) {
    system( 'git', 'mv', $old_pm, $new_pm ) == 0
        or die "Failed to git mv $old_pm -> $new_pm\n";
}

# Commit the renames
system( 'git', 'add', '-A' ) == 0 or die "Failed to git add\n";
system( 'git', 'commit', '-m', "$vendor_name - Rename files [Vendor]" ) == 0
    or die "Failed to commit renames\n";

# Update description in package.json
if ( -f 'package.json' ) {
    my $content = read_file('package.json');
    $content =~ s/"description":\s*".*?"/"description": "Koha Edifact Plugin - $vendor_name"/;
    write_file( 'package.json', $content );
}

# Update name in $metadata in the .pm file
if ( -f $new_pm ) {
    my $content = read_file($new_pm);
    $content =~ s/Edifact - Enhanced/Edifact - $vendor_name/;
    $content =~ s/Edifact Enhanced plugin/Edifact plugin for $vendor_name/;
    write_file( $new_pm, $content );
}


#Update file contents
my @files;
find(
    {
        wanted => sub {
            return unless -f $_;
            return if $File::Find::name =~ m{/\.git/};
            return if $File::Find::name =~ m{/node_modules/};
            return if $File::Find::name =~ /rename_edi_plugin.pl/;

            my $content = read_file($_);
            if ( $content =~ /enhanced/i ) {
                push @files, $File::Find::name;
            }
        },
        no_chdir => 1,
    },
    '.'
);

# Do the mass rename last so the above actually work, any special cases should be handled above
for my $file (@files) {
    my $content = read_file($file);
    $content =~ s/Enhanced/$vendor/g;
    $content =~ s/enhanced/$vendor_lower_dashed/g;
    write_file( $file, $content );
}


# Commit the content updates
system( 'git', 'add', '-A' ) == 0 or die "Failed to git add\n";
system( 'git', 'commit', '-m', "$vendor_name - Update files [Vendor]" ) == 0
    or die "Failed to commit content updates\n";

print "Renamed plugin to Edifact$vendor\n";
print "Vendor name: $vendor_name\n";
