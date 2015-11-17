#!/usr/bin/env perl

use v5.14;
use warnings;

use Test::More;
use Test::Deep;
use Capture::Tiny qw(capture);
use LWP::Simple qw(get);

plan tests => 2;

$ENV{P5IQ_INDEX} = "p5iq_$$";
END {
    P5iq::delete_all();
}

use P5iq::Index;
use P5iq::Search;
use P5iq;

diag "P5IQ_INDEX: $ENV{P5IQ_INDEX}";
is P5iq::idx(), $ENV{P5IQ_INDEX}, 'idx() as expected';

# this call is forking which breaks the END block so for now we call the external command.
# P5iq::Index::index_dirs('lib');
#diag get 'http://127.0.0.1:9200/_stats?pretty=1';
system $^X, 'bin/p5iq-index', 't/corpus';
sleep 4; # TODO: It seems after the index script finished we still have to wait for the indexing to really be done
my $ID = re('^[\w-]{22,}$');
my $SCORE = re('^\d\.\d+$');

{
    my $res = P5iq::Search::_locate_symbols('unshift', 10, 1, 0);
    cmp_deeply $res, bag(
         {
           '_id' => $ID,
           '_index' => $ENV{P5IQ_INDEX},
           '_score' => $SCORE,
           '_source' => {
             'class' => 'PPI::Token::Word',
             'content' => 'unshift',
             'file' => 't/corpus/lib/P5iq.pm',
             'line_number' => 110,
             'row_number' => 13,
             'tags' => []
           },
           '_type' => 'p5_node'
         },
         {
           '_id' => $ID,
           '_index' => $ENV{P5IQ_INDEX},
           '_score' => $SCORE,
           '_source' => {
             'class' => 'PPI::Token::Word',
             'content' => 'unshift',
             'file' => 't/corpus/lib/P5iq.pm',
             'line_number' => 181,
             'row_number' => 13,
             'tags' => []
           },
           '_type' => 'p5_node'
         }
    ), '_locate_symbols unshift';
}

#my ($stdout, $stderr, $exit) = capture {
#    P5iq::Search::locate_symbols('unshift', 10, 1, 0);
#};
#is $stdout, "lib/P5iq.pm:105: unshift\nlib/P5iq.pm:176: unshift\n";

#diag get 'http://127.0.0.1:9200/_stats?pretty=1';
#diag explain(P5iq->es->search( index => $ENV{P5IQ_INDEX}, body => { size => 5000 }));


my $res = P5iq::Search::_search_p5iq_index('unshift');
#diag explain $res;

