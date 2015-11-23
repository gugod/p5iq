#!/usr/bin/env perl

use v5.14;
use warnings;

use Test::More;
use Test::Deep;
use Capture::Tiny qw(capture);
#use LWP::Simple qw(get);

plan tests => 3;

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
my $ID = re('^[\w-]{20,}$');
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

#diag get 'http://127.0.0.1:9200/_stats?pretty=1';
#diag explain(P5iq->es->search( index => $ENV{P5IQ_INDEX}, body => { size => 5000 }));

my $res = P5iq::Search::_search_p5iq_index('unshift');
cmp_deeply $res, [
   {
     '_id' => $ID,
     '_index' => $ENV{P5IQ_INDEX},
     '_score' => $SCORE,
     '_source' => {
       'class' => 'PPI::Structure::Subscript',
       'content' => '$args->location->[1]',
       'file' => 't/corpus/lib/P5iq.pm',
       'line_number' => 149,
       'row_number' => 30,
       'tags' => [
         'subscript:symbol=$args',
         'subscript:container=$args->location->',
         'subscript:content=[1]'
       ],
       'token_class' => [
         'PPI::Token::Symbol',
         'PPI::Token::Operator',
         'PPI::Token::Word',
         'PPI::Token::Operator',
         'PPI::Structure::Subscript'
       ],
       'token_content' => [
         '$args',
         '->',
         'location',
         '->',
         '[1]'
       ]
     },
     '_type' => 'p5_node'
   },
   {
     '_id' => $ID,
     '_index' => $ENV{P5IQ_INDEX},
     '_score' => $SCORE,
     '_source' => {
       'class' => 'PPI::Structure::Subscript',
       'content' => '$method->location->[0]',
       'file' => 't/corpus/lib/P5iq.pm',
       'line_number' => 190,
       'row_number' => 30,
       'tags' => [
         'subscript:symbol=$method',
         'subscript:container=$method->location->',
         'subscript:content=[0]'
       ],
       'token_class' => [
         'PPI::Token::Symbol',
         'PPI::Token::Operator',
         'PPI::Token::Word',
         'PPI::Token::Operator',
         'PPI::Structure::Subscript'
       ],
       'token_content' => [
         '$method',
         '->',
         'location',
         '->',
         '[0]'
       ]
     },
     '_type' => 'p5_node'
   },
   {
     '_id' => $ID,
     '_index' => $ENV{P5IQ_INDEX},
     '_score' => $SCORE,
     '_source' => {
       'class' => 'PPI::Structure::Subscript',
       'content' => '$s->location->[0]',
       'file' => 't/corpus/lib/P5iq.pm',
       'line_number' => 148,
       'row_number' => 30,
       'tags' => [
         'subscript:symbol=$s',
         'subscript:container=$s->location->',
         'subscript:content=[0]'
       ],
       'token_class' => [
         'PPI::Token::Symbol',
         'PPI::Token::Operator',
         'PPI::Token::Word',
         'PPI::Token::Operator',
         'PPI::Structure::Subscript'
       ],
       'token_content' => [
         '$s',
         '->',
         'location',
         '->',
         '[0]'
       ]
     },
     '_type' => 'p5_node'
   },
   {
     '_id' => $ID,
     '_index' => $ENV{P5IQ_INDEX},
     '_score' => $SCORE,
     '_source' => {
       'class' => 'PPI::Structure::Subscript',
       'content' => '$method->location->[1]',
       'file' => 't/corpus/lib/P5iq.pm',
       'line_number' => 191,
       'row_number' => 30,
       'tags' => [
         'subscript:symbol=$method',
         'subscript:container=$method->location->',
         'subscript:content=[1]'
       ],
       'token_class' => [
         'PPI::Token::Symbol',
         'PPI::Token::Operator',
         'PPI::Token::Word',
         'PPI::Token::Operator',
         'PPI::Structure::Subscript'
       ],
       'token_content' => [
         '$method',
         '->',
         'location',
         '->',
         '[1]'
       ]
     },
     '_type' => 'p5_node'
   }
], 'search';


