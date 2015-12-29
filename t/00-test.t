#!/usr/bin/env perl

use v5.14;
use warnings;

use Test::More;
use Test::Deep;
use Capture::Tiny qw(capture);
#use LWP::Simple qw(get);

plan tests => 2;

$ENV{P5IQ_INDEX} = "p5iq_$$";
END {
    P5iq::delete_all();
}

use Data::Dumper;

use P5iq::Index;
use P5iq::Search;
use P5iq;

diag "P5IQ_INDEX: $ENV{P5IQ_INDEX}";
is P5iq::idx(), $ENV{P5IQ_INDEX}, 'idx() as expected';

# this call is forking which breaks the END block so for now we call the external command.
# P5iq::Index::index_dirs('lib');
#diag get 'http://127.0.0.1:9200/_stats?pretty=1';

system $^X, 'bin/p5iq-index', 't/corpus';

P5iq->es->post(index => P5iq::idx(), command => "_refresh");

P5iq::Search::locate_sub(
    {},
    "this",
    sub {
        my $res = shift;
        ok($res->{hits}{total} >= 1);
    }
);
