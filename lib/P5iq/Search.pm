package P5iq::Search;
use v5.14;

use P5iq;

use PPI;
use JSON qw(to_json);

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
    } else {
        my @t = grep { $_->isa("PPI::Token::Symbol") } $ppi_doc->tokens;
        $es_query = {
            bool => {
                must => [
                    map { +{ term => { tags => "symbol:actual=$_" } } } @t
                ]
            }
        };
    }

    if (!$es_query) {
        die "Not sure what you're looking for...";
    }

    my ($status, $res) = P5iq->es->search(
        index => P5iq::idx(),
        body  => {
            query => $es_query,
            size  => $size,
        }
    );
    if ($status eq '200') {
        for (sort { $a->{_source}{file} cmp $b->{_source}{file} or $a->{_source}{line_number} <=> $b->{_source}{line_number} } @{ $res->{hits}{hits} }) {
            my $src =$_->{_source};
            say join(":", $src->{file}, $src->{line_number}) . ": " . $_->{_source}{content};
        }
    } else {
        say "Query Error: " . to_json($res);
    }
}

sub locate_hash_keys {
    my ($query_string, $size) = @_;
    my $ppi_doc = PPI::Document->new( \$query_string );
    my @t = grep { $_->isa("PPI::Token::Symbol") } $ppi_doc->tokens;
    my ($status, $res) = P5iq->es->search(
        index => P5iq::idx(),
        body  => {
            query => {
                bool => {
                    must => [
                        map { +{ term => { tags => "subscript:symbol=$_" } } } @t
                    ]
                },
            },
            aggs => {
                hash_keys => {
                    terms => {
                        field => "tags",
                        include => ".*content.*",
                        exclude => ".*]",
                        size => 0,
                    }
                },
            }
        }
    );
    if ($status eq '200') {
        my @keys = map{ $_->{key} = substr($_->{key}, length('subscript::content=') - 1 ); $_->{key} }
            @{ $res->{aggregations}{hash_keys}{buckets} };
        say join("\n", @keys);
    } else {
        say "Query Error: " . to_json($res);
    }
}

sub locate_hash_name {
    my ($query_string, $size) = @_;
    my ($status, $res) = P5iq->es->search(
        index => P5iq::idx(),
        body  => {
            query => {
                bool => {
                    must => [
                        +{ term => { tags => "subscript:content={$query_string}" } }
                    ]
                },
            },
            aggs => {
                hash_name => {
                    terms => {
                        field => "tags",
                        include => "subscript:symbol.*",
                        size => 0,
                    }
                },
            }
        }
    );
    if ($status eq '200') {
        my @keys = map{ $_->{key} = substr($_->{key}, length('subscript:symbol=') ); $_->{key} }
            @{ $res->{aggregations}{hash_name}{buckets} };
        say join("\n", @keys);
    } else {
        say "Query Error: " . to_json($res);
    }
}

sub locate_var_def {
    my ($query_string, $size) = @_;
    say "size= $size";
    my ($status, $res) = P5iq->es->search(
        index => P5iq::idx(),
        body  => {
            size => $size,
            query => {
                bool => {
                    must => [
                        +{ term => { content => "$query_string" } },
                        +{ term => { tags => "in:statement:variable:defined" } }
                    ]
                }
            }
        }
    );
    if ($status eq '200') {
        for (@{ $res->{hits}{hits} }) {
            my $src =$_->{_source};
            say join(":", $src->{file}, $src->{line_number});
        }
    } else {
        say "Query Error: " . to_json($res);
    }
}

sub locate_arglist {
    my ($query_string, $size) = @_;
    $size //= 10;

    my ($status, $res) = P5iq->es->search(
        index => P5iq::idx(),
        body  => {
            size  => 0,
            query => {
                bool => {
                    must => [
                        +{ term => { tags => "function:call" } },
                        +{ term => { tags => "function:name=$query_string" } },
                    ]
                },
            },
            aggs => {
                hash_keys => {
                    terms => {
                        size  => $size,
                        field => "tags",
                        include => "function:arglist=.*"
                    }
                },
            }
        }
    );
    if ($status eq '200') {
        my @keys = map{ $_->{key} = substr($_->{key},17); $_->{key} }
        @{ $res->{aggregations}{hash_keys}{buckets} };
        say join("\n", @keys);
    } else {
        say "Query Error: " . to_json($res);
    }

}

sub locate_function_calls {
    my ($query_string, $size) = @_;
    $size //= 10;

    my ($status, $res) = P5iq->es->search(
        index => P5iq::idx(),
        body  => {
            size  => $size,
            query => {
                bool => {
                    must => [
                        +{ term => { tags => "function:call" } },
                        +{ term => { tags => "function:name=$query_string" } },
                    ]
                },
            }
        }
    );
    if ($status eq '200') {
        for (@{ $res->{hits}{hits} }) {
            my $src =$_->{_source};
            say join(":", $src->{file}, $src->{line_number}, $src->{row_number});
        }
    } else {
        say "Query Error: " . to_json($res);
    }
}

sub locate_method_calls {
    my ($query_string, $size) = @_;
    $size //= 10;

    my ($status, $res) = P5iq->es->search(
        index => P5iq::idx(),
        body  => {
            size  => $size,
            query => {
                bool => {
                    must => [
                        +{ term => { tags => "method:call" } },
                        +{ term => { tags => "method:name=$query_string" } },
                    ]
                },
            },
            aggs => {
                method_context => {
                    terms => {
                        size  => $size,
                        field => "tags",
                        include => "method:context=.*"
                    }
                },
            }
        }
    );
    if ($status eq '200') {
        my @keys = map{ $_->{key} = substr($_->{key},15); $_->{key} } @{ $res->{aggregations}{method_context}{buckets} };
        say join("\n", @keys);
    } else {
        say "Query Error: " . to_json($res);
    }
}

sub search_p5iq_index {
    my ($query_string, $size) = @_;
    $size //= 10;

    my $es_query = P5iq::analyze_for_query( PPI::Document->new( \$query_string ) );

    my ($status, $res) = P5iq->es->search(
        index => P5iq::idx(),
        body  => {
            query => $es_query,
            size  => $size,
        }
    );
    if ($status eq '200') {
        for (@{ $res->{hits}{hits} }) {
            my $src =$_->{_source};
            say join(":", $src->{file}, $src->{line_number}) . "\n" . $_->{_source}{content} . "\n";
        }
    } else {
        say "Query Error: " . to_json($res);
    }
}


1;
