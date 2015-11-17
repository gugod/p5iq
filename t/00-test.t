#!/usr/bin/env perl

use v5.14;
use warnings;

use Test::More;
use Capture::Tiny qw(capture);

plan tests => 1;

$ENV{P5IQ_INDEX} = "p5iq_$$";
END {
    P5iq::delete_all();
}

diag "P5IQ_INDEX: $ENV{P5IQ_INDEX}";

use P5iq::Index;
use P5iq::Search;

P5iq::Index::index_dirs('lib');

my ($stdout, $stderr, $exit) = capture {
    P5iq::Search::locate_symbols('unshift', 10, 1, 0);
};
is $stdout, "lib/P5iq.pm:105: unshift\nlib/P5iq.pm:176: unshift\n";


($stdout, $stderr, $exit) = capture {
    P5iq::Search::search_p5iq_index('shift', 10);
};
#diag $stdout;

