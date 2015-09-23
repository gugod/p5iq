package P5iq::Search;
use v5.18;

use P5iq;

use PPI;
use JSON qw(to_json);
use Elastijk;


sub locate_symbols {
    my ($query_string, $size, $symbol, $sub_named) = @_;

    my $ppi_doc = PPI::Document->new( \$query_string );
    
    my $es_query;
    
    if ($symbol) {
        my @symbols = grep { $_->isa("PPI::Token") } $ppi_doc->tokens;
        $es_query = {
            bool => {
                must => [
                    (map{ (+{ term => { content => $_->content } },{term => { class => $_->class }}) } @symbols)
                ],
            }
        };
    } elsif($sub_named) {
        my @t = grep { $_->isa("PPI::Token::Word") } $ppi_doc->tokens;
        $es_query = {
            bool => {
                must => [
                    map { +{ term => { tags => "sub:named=$_" } } } @t
                ]
            }
        };    
    }
    
    if (!$es_query) {
        die "Not sure what you're looking for...";
    }
    
    my ($status, $res) = P5iq->es->search(
        index => "p5iq",
        body  => {
            query => $es_query,
            size  => $size,
        }
    );
    if ($status eq '200') {
        for (@{ $res->{hits}{hits} }) {
            my $src =$_->{_source};
            say join(":", $src->{file}, $src->{line_number}) . ": " . $_->{_source}{content};
        }
    } else {
        say "Query Error: " . to_json($res);
    }
}


1;

