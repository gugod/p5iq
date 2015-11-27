package P5iq::Search;
use v5.14;

use P5iq;

use PPI;
use JSON qw(to_json);

sub es_search {
    my ($search_param, $cb) = @_;
    $search_param->{index} //= P5iq::idx();
    my ($status, $res) = P5iq->es->search(%$search_param);
    if ($status eq '200') {
        $cb->($res);
    } else {
        say "Query Error: " . to_json($res);
    }
}

sub locate_symbols {
    my ($query_string, $size, $symbol, $sub_named) = @_;
    my $res = _locate_symbols($query_string, $size, $symbol, $sub_named);
    for (sort { $a->{_source}{file} cmp $b->{_source}{file} or $a->{_source}{line_number} <=> $b->{_source}{line_number} } @{ $res }) {
        my $src =$_->{_source};
        say join(":", $src->{file}, $src->{line_number}) . ": " . $_->{_source}{content};
    }
    return;
}

sub _locate_symbols {
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
        return $res->{hits}{hits};
    } else {
        say "Query Error: " . to_json($res);
        return [];
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

sub search_p5iq_index {
    my $res = _search_p5iq_index(@_);
    for (@{ $res }) {
        my $src =$_->{_source};
        say join(":", $src->{file}, $src->{line_number}) . "\n" . $_->{_source}{content} . "\n";
    }
}

sub _search_p5iq_index {
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
        return $res->{hits}{hits};
    } else {
        say "Query Error: " . to_json($res);
    }
}

sub locate_variable {
    my ($args, $query_string, $cb) = @_;

    my @conditions = (
        (defined($args->{in})     ? { prefix => { file => $args->{in}  } }   : ())
    );

    if ($args->{"in-string"}) {
        push @conditions, (
            { prefix => { class => "PPI::Token::Quote" } },
            (define($query_string) ? { regexp => { content => ".*\Q${query_string}\E.*" } } : ()),
        );
    } else {
        push @conditions, (
            (defined($args->{def})    ? { term => { tags => "in:statement:variable:defined" } } :()),
            (defined($args->{lvalue}) ? { term => { tags => "variable:lvalue" }} : ()),
            (defined($args->{rvalue}) ? { term => { tags => "variable:rvalue" }} : ()),
            (defined($query_string)   ? { term => { tags => "symbol:actual=${query_string}" } } :()),
            +{ term => { tags => "in:statement:variable" } },
        );
    }

    es_search({
        body  => {
            size  => $args->{size} // 25,
            query => { bool => { must => \@conditions } }
        }
    }, $cb);
}

sub locate_value {
    my ($args, $query_string, $cb) = @_;
    my @conditions = (
        (defined($args->{in})   ? { prefix => { file => $args->{in}  } }   : ()),
        (defined($query_string) ? { regexp => { content => ".*\Q${query_string}\E.*" } } :()),
    );

    es_search({
        body  => {
            size  => $args->{size} // 25,
            query => { bool => {
                should => [
                    +{ prefix => { class => "PPI::Token::Number" } },
                    +{ prefix => { class => "PPI::Token::Quote" }  }
                ],
                must => \@conditions
            } }
        }
    }, $cb);
}

sub locate_sub {
    my ($args, $query_string, $cb) = @_;

    my @conditions = (
        (defined($query_string) ? { term => { tags => "subroutine:name=$query_string" } } : ()),
        (defined($args->{in})   ? { prefix => { file => $args->{in}  } }   : ()),
    );

    if ($args->{call}) {
        push @conditions, { term => { tags => "subroutine:call" } };
    } elsif ($args->{function}) {
        push @conditions, { term => { tags => "function:call" } };
    } elsif ($args->{method}) {
        push @conditions, { term => { tags => "method:call" } };
    } else {
        push @conditions, { term => { tags => "subroutine:def" } };
    }

    es_search({
        body  => {
            size  => $args->{size} // 25,
            query => {
                bool => { must => \@conditions }
            }
        }
    }, $cb);
}

sub frequency_hash_keys {
    my ($args, $query_string, $cb) = @_;

    my @conditions = (
        { term => { tags => "subscript:symbol=$query_string" } },
        (defined($args->{in})     ? { prefix => { file => $args->{in}  } }   : ())
    );

    es_search({
        body  => {
            size  => $args->{size} // 25,
            query => {
                bool => { must => \@conditions }
            },
            aggregations => {
                hash_keys => {
                    terms => {
                        field => "tags",
                        include => ".*content.*",
                        exclude => ".*]",
                        size => 0,
                    }
                }
            }
        }
    }, $cb);
}

sub frequency_args {
    my ($args, $query_string, $cb) = @_;

    my @conditions = (
        { term => { tags => "function:call" } },
        { term => { tags => "function:name=$query_string" } },
        (defined($args->{in})     ? { prefix => { file => $args->{in}  } }   : ())
    );

    es_search({
        body  => {
            size  => $args->{size} // 25,
            query => {
                bool => { must => \@conditions }
            },
            aggregations => {
                args => {
                    terms => {
                        field => "tags",
                        include => "function:arglist=.*",
                        size => 0,
                    }
                }
            }
        }
    }, $cb);
}

sub frequency_values {
    my ($args, $query_string, $cb) = @_;

    my @conditions = (
        (defined($query_string) ? { term => { "content" => $query_string } } : ()),
        (defined($args->{in})   ? { prefix => { file => $args->{in}  } }     : ())
    );

    es_search({
        body  => {
            size  => 0,
            query => {
                constant_score => {
                    filter => {
                        and => [
                            @conditions,
                            {
                                or => [
                                    +{ prefix => { class => "PPI::Token::Number" } },
                                    +{ prefix => { class => "PPI::Token::Quote" }  }
                                ]
                            }
                        ]
                    }
                }
            },
            aggregations => {
                values => {
                    terms => {
                        field => "content",
                        size  => $args->{size} // 25,
                    }
                }
            }
        }
    }, $cb);
}

sub frequency_invocant {
    my ($args, $query_string, $cb) = @_;

    my @conditions = (
        { term => { tags => "method:call" } },
        (defined($query_string) ? { term => { tags => "method:name=$query_string" } } : ()),
        (defined($args->{in})   ? { prefix => { file => $args->{in}  } }     : ())
    );

    es_search({
        body  => {
            size  => 0,
            query => {
                constant_score => {
                    filter => {
                        and => \@conditions
                    }
                }
            },
            aggregations => {
                invocant => {
                    terms => {
                        field => "tags",
                        include => "method:context=.*",
                        size  => $args->{size} // 25,
                    }
                }
            }
        }
    }, $cb);
}

sub frequency_token {
    my ($args, $query_string, $cb) = @_;

    my @conditions = (
        { prefix => { "class" => $args->{class} // "PPI::Token" } },
        (defined($args->{in})   ? { prefix => { file => $args->{in}  } }     : ())
    );

    es_search({
        body  => {
            size  => 0,
            query => {
                constant_score => {
                    filter => {
                        and => \@conditions
                    }
                }
            },
            aggregations => {
                token => {
                    terms => {
                        field => "content",
                        size  => $args->{size} // 25,
                    }
                }
            }
        }
    }, $cb);
}

1;
