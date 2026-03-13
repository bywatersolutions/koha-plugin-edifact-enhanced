#!/usr/bin/env perl
use strict;
use warnings;

use feature 'say';

use JSON::PP;
use Data::Dumper;

qx(git config --global user.email kyle\@bywatersolutions.com);
say "Failed to set git email" if $? != 0;

qx(git config --global user.name \"Kyle M Hall\");
say "Failed to set git name" if $? != 0;

my $TAG      = $ENV{TAG}      // '';
my $GH_TOKEN = $ENV{GH_TOKEN} // '';

say "TAG: $TAG";

my $full_repo = $ENV{GITHUB_REPOSITORY} // '';
my ( $org, $repo ) = split m{/}, $full_repo, 2;

say "Org:  $org";
say "Repo: $repo";

say "\nNot koha-plugin-edifact-enhanced, exiting" && exit 0 unless $repo eq "koha-plugin-edifact-enhanced";

qx(git remote);
qx(git fetch origin);

my @repos = get_other_repos(
    org     => 'bywatersolutions',
    pattern => '^koha-plugin-edifact',
);

say "FOUND REPOS " . Data::Dumper::Dumper( \@repos );

my $failures = 0;
foreach my $repo (@repos) {
    next if $repo eq 'koha-plugin-edifact-enhanced';
    next if $repo eq 'koha-plugin-edifact-enhanced-docs';

    say "WORKING ON $repo";

    qx(git remote add $repo https://x-access-token:$GH_TOKEN\@github.com/bywatersolutions/$repo.git);
    say "Failed to add remote for $repo" if $? != 0;

    say "Fetching $repo";
    qx(git fetch $repo);
    if ( $? != 0 ) {
        say "Fetch of $repo failed: $?";
        $failures++;
        next;
    }

    say "Checking out main for $repo";
    qx(git checkout $repo/main);
    if ( $? != 0 ) {
        say "Checkout of $repo/main failed: $?";
        $failures++;
        next;
    }

    say "Rebasing against origin/main";
    qx(git rebase origin/main);
    if ( $? != 0 ) {
        say "Rebase of main failed: $?";
        qx(git rebase --abort);
        $failures++;
        next;
    }
    say "Rebased $repo/main against origin/main";

    say "Pushing new version to main for $repo";
    qx(git push -f $repo HEAD:refs/heads/main);
    if ( $? != 0 ) {
        say "Push of main to $repo failed: $?";
        $failures++;
        next;
    }

    say "Pushed to main for $repo";

    if ( $TAG ne 'main' ) {
        my $postfix = $repo;
        $postfix =~ s/koha-plugin-edifact-//;

        my $tagname = "$TAG-$postfix";
        qx(git tag $tagname);
        say "Tagging $tagname failed: $?" if $? != 0;

        qx(git push $repo $tagname);
        if ( $? != 0 ) {
            say "Push of tag $tagname failed for $repo: $?";
        } else {
            say "Pushed tag $tagname for $repo";
        }
    } else {
        say "Not a tag, not pushing new tags";
    }
}

qx(git checkout origin/main);
say "Checkout of origin/main failed: $?" if $? != 0;

sub get_other_repos {
    my (%args)  = @_;
    my $org     = $args{org}     // die "org is required";
    my $pattern = $args{pattern} // die "pattern is required";

    my @matches;
    my $page = 1;

    while (1) {
        my $url = "https://api.github.com/orgs/$org/repos?per_page=100&page=$page";

        say "FETCHING $url";

        # Run curl and capture output
        my $json = qx(curl -s "$url");

        unless ($json) {
            say "Failed to fetch repos: no response";
            exit 1;
        }

        my $repos = eval { decode_json($json) };
        if ($@) {
            say "Failed to decode JSON: $@";
            exit 1;
        }

        last unless @$repos;    # no more results

        foreach my $repo (@$repos) {
            push @matches, $repo->{name} if $repo->{name} =~ /$pattern/;
        }

        $page++;
    }

    return @matches;
}

exit $failures > 0 ? 1 : 0;