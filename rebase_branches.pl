#!/usr/bin/env perl
use strict;
use warnings;

use HTTP::Tiny;
use JSON::PP;

qx(git config --global user.email kyle\@bywatersolutions.com);
warn "Failed to set git email\n" if $? != 0;

qx(git config --global user.name "Kyle M Hall");
warn "Failed to set git name\n" if $? != 0;

my $TAG      = $ENV{TAG} // '';
my $GH_TOKEN = $ENV{GH_TOKEN} // '';

print "TAG: $TAG\n";

my $full_repo = $ENV{GITHUB_REPOSITORY} // '';
my ($org, $repo) = split m{/}, $full_repo, 2;

print "Org:  $org\n";
print "Repo: $repo\n";

print "\nNot koha-plugin-edifact-enhanced, exiting\n" && exit 0 unless $repo eq "koha-plugin-edifact-enhanced";

my @repos = get_other_repos(
    org     => 'bywatersolutions',
    pattern => '^koha-plugin-edifact',
    token   => $GH_TOKEN,
);

my $failures = 0;
foreach my $repo (@repos) {
    qx(git remote add $repo git\@github.com:bywatersolutions/$repo.git);
    warn "Failed to add remote for $repo\n" if $? != 0;

    qx(git fetch $repo);
    if ($? != 0) {
        warn "Fetch of $repo failed: $?\n";
        $failures++;
        next;
    }

    qx(git checkout $repo/main);
    if ($? != 0) {
        warn "Checkout of $repo/main failed: $?\n";
        $failures++;
        next;
    }
    print "Checked out origin/main\n";

    qx(git rebase origin/main);
    if ($? != 0) {
        warn "Rebase of main failed: $?\n";
        $failures++;
        next;
    }
    print "Rebased main\n";

    qx(git push -f https://$GH_TOKEN:$GH_TOKEN\@github.com/bywatersolutions/$repo.git HEAD:main);
    if ($? != 0) {
        warn "Push of main to $repo failed: $?\n";
        $failures++;
        next;
    }

    print "Pushed to main for $repo\n";

    if ($TAG ne 'main') {
        my $tagname = "$TAG-main";
        qx(git tag $tagname);
        warn "Tagging $tagname failed: $?\n" if $? != 0;

        qx(git push https://$GH_TOKEN:$GH_TOKEN\@github.com/bywatersolutions/$repo.git $tagname);
        if ($? != 0) {
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
    my (%args) = @_;
    my $org     = $args{org}     // die "org is required";
    my $pattern = $args{pattern} // die "pattern is required";
    my $token   = $args{token}   // '';

    my $http = HTTP::Tiny->new(
        default_headers => {
            'Accept' => 'application/vnd.github.v3+json',
            $token ? ('Authorization' => "token $token") : (),
        }
    );

    my @matches;
    my $page = 1;

    while (1) {
        my $url = "https://api.github.com/orgs/$org/repos?per_page=100&page=$page";
        warn "FETCHING $url";
        my $res = $http->get($url);

        unless ($res->{success}) {
            warn "Failed to fetch repos: $res->{status} $res->{reason}\n";
            last;
        }

        my $repos = decode_json($res->{content});
        last unless @$repos; # no more results

        foreach my $repo (@$repos) {
            push @matches, $repo->{name} if $repo->{name} =~ /$pattern/;
        }

        $page++;
    }

    return @matches;
}
