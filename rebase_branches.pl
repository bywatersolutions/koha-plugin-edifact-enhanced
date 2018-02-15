#!/usr/bin/env perl

use strict;
use warnings;

my $cmd = q{git branch -r | grep --invert-match master};
my @branches = `$cmd`;

foreach my $b ( @branches ) {
    my ( undef, $branch ) = split('/', $b );

    print "BRANCH: $branch";

    $cmd = qq{git checkout origin/$branch};
    print "$cmd\n";
    `$cmd`;
    print "$? ERROR: $!\n" && exit 1 if $? != 0;

    $cmd = q{git rebase origin/master};
    print "$cmd\n";
    `$cmd`;
    print "$? ERROR: $!\n" && exit 1 if $? != 0;

    $cmd = qq{git push -f origin HEAD:$branch};
    print "$cmd\n";
    `$cmd`;
    print "$? ERROR: $!\n" && exit 1 if $? != 0;
}
