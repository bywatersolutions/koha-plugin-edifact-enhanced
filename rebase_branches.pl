#!/usr/bin/env perl
use strict;
use warnings;

use JSON::PP;
use Data::Dumper;

qx(git config --global user.email kyle\@bywatersolutions.com);
warn "Failed to set git email\n" if $? != 0;

qx(git config --global user.name \"Kyle M Hall\");
warn "Failed to set git name\n" if $? != 0;

my $TAG      = $ENV{TAG}      // '';
my $GH_TOKEN = $ENV{GH_TOKEN} // '';

print "TAG: $TAG\n";

my $full_repo = $ENV{GITHUB_REPOSITORY} // '';
my ( $org, $repo ) = split m{/}, $full_repo, 2;

print "Org:  $org\n";
print "Repo: $repo\n";

print "\nNot koha-plugin-edifact-enhanced, exiting\n" && exit 0 unless $repo eq "koha-plugin-edifact-enhanced";

my @repos = get_other_repos(
    org     => 'bywatersolutions',
    pattern => '^koha-plugin-edifact',
);

warn "FOUND REPOS " . Data::Dumper::Dumper( \@repos );

my $failures = 0;
foreach my $repo (@repos) {
    warn "WORKING ON $repo";

    qx(git remote add $repo https://$GH_TOKEN:$GH_TOKEN\@github.com/bywatersolutions/$repo.git);
    warn "Failed to add remote for $repo\n" if $? != 0;

    warn "Fetching $repo";
    qx(git fetch $repo);
    if ( $? != 0 ) {
        warn "Fetch of $repo failed: $?\n";
        $failures++;
        next;
    }

    warn "Checking out main for $repo";
    qx(git checkout $repo/main);
    if ( $? != 0 ) {
        warn "Checkout of $repo/main failed: $?\n";
        $failures++;
        next;
    }

    warn "CURRENT DIR & FILES: " . qx{pwd; find . -type f};

    warn "Rebasing against origin/main";
    qx(git rebase origin/main);
    if ( $? != 0 ) {
        warn "Rebase of main failed: $?\n";
        $failures++;
        next;
    }
    print "Rebased main\n";

    warn "CURRENT DIR & FILES: " . qx{pwd; find . -type f};

    warn "Pushing new version";
    qx(git push -f $repo HEAD:main);
    if ( $? != 0 ) {
        warn "Push of main to $repo failed: $?\n";
        $failures++;
        next;
    }

    print "Pushed to main for $repo\n";

    if ( $TAG ne 'main' ) {
        my $tagname = "$TAG";
        qx(git tag $tagname);
        warn "Tagging $tagname failed: $?\n" if $? != 0;

        qx(git push $repo $tagname);
        if ( $? != 0 ) {
            warn "Push of $tagname failed: $?\n";
        } else {
            print "Pushed $tagname\n";
        }
    } else {
        print "Not a tag, not pushing new tags\n";
    }
}

qx(git checkout origin/main);
warn "Checkout of origin/main failed: $?\n" if $? != 0;

sub get_other_repos {
    my (%args)  = @_;
    my $org     = $args{org}     // die "org is required";
    my $pattern = $args{pattern} // die "pattern is required";

    my @matches;
    my $page = 1;

    while (1) {
        my $url = "https://api.github.com/orgs/$org/repos?per_page=100&page=$page";

        warn "FETCHING $url\n";

        # Run curl and capture output
        my $json = qx(curl -s "$url");

        unless ($json) {
            warn "Failed to fetch repos: no response\n";
            exit 1;
        }

        my $repos = eval { decode_json($json) };
        if ($@) {
            warn "Failed to decode JSON: $@\n";
            exit 1;
        }

        last unless @$repos;    # no more results

        foreach my $repo (@$repos) {
            push @matches, $repo->{name} if $repo->{name} =~ /$pattern/;
        }

        $page++;
    }

    warn "Found repos: " . Data::Dumper::Dumper( \@matches );

    return @matches;
}
