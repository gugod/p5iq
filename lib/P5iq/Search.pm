package P5iq::Search;
use v5.14;

use P5iq;
use P5iq::Analyzer;

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

sub search_with_query_string  {
    my ($args, $query_string, $cb) = @_;
    my $ppi_doc = PPI::Document->new( \$query_string );
    my $analysis = P5iq::Analyzer::analyze_for_index($ppi_doc);
    if ($analysis->{p5_sub}) {
        for my $d (@{$analysis->{p5_sub}}) {
            es_search({
                type => "p5_sub",
                body => {
                    query => {
                        dis_max => {
                            queries => [
                                { term => { class => $d->{class} } },
                                { term => { content => $d->{content} } },
                                { terms => { "tags" => $d->{tags} } },
                            ]
                        }
                    }
                },
            }, $cb)
        }
    } else {
        die "Unimplemented";
    }
}

sub locate_variable {
    my ($args, $query_string, $cb) = @_;

    my @conditions = (
        (defined($args->{in})     ? { prefix => { file => $args->{in}  } }   : ())
    );

    if ($args->{"in-string"}) {
        push @conditions, (
            { term => { tags => "variable:in-string" } },
            (defined($query_string) ? { term => { tags => "symbol:actual=${query_string}" } } : ()),
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

    if ($args->{call}) {
        locate_sub_call($args, $query_string, $cb);
        return;
    }

    my @conditions = (
        (defined($args->{in})   ? { prefix => { file => $args->{in}  } }   : ()),
    );

    if ($args->{function}) {
        push @conditions, { term => { tags => "function:call" } };
        push @conditions, { term => { tags => "function:name=$query_string" } };
    } elsif ($args->{method}) {
        push @conditions, { term => { tags => "method:call" } };
        push @conditions, { term => { tags => "method:name=$query_string" } };
    } else {
        push @conditions, { term => { tags => "subroutine:def" } };
        push @conditions, { term => { tags => "subroutine:name=$query_string" } };
    }

    es_search({
        body  => {
            size  => $args->{size} // 25,
            query => {
                bool => {
                    must => \@conditions
                }
            }
        }
    }, $cb);
}

sub locate_sub_call {
    my ($args, $query_string, $cb) = @_;

    my @conditions = (
        (defined($args->{in})   ? { prefix => { file => $args->{in}  } }   : ()),
    );

    es_search({
        body  => {
            size  => $args->{size} // 25,
            query => {
                bool => {
                    should => [
                        {
                            bool => {
                                must => [
                                    { term => { tags => "function:call" } },
                                    { term => { tags => "function:name=$query_string" } }
                                ]
                            }
                        },
                        {
                            bool => {
                                must => [
                                    { term => { tags => "method:call" } },
                                    { term => { tags => "method:name=$query_string" } }
                                ]
                            }
                        }
                    ],
                    must => \@conditions
                }
            }
        }
    }, $cb);
}

sub locate_pod {
    my ($args, $query_string, $cb) = @_;

    my @conditions = (
        (defined($args->{in})     ? { prefix => { file => $args->{in}  } }   : ())
    );

    es_search({
        type => "p5_pod",
        body => {
            size  => $args->{size} // 25,
            query => {
                bool => {
                    should => [
                        { term => {title => $query_string} },
#                        { term => {text  => $query_string} },
                    ],
                    must => \@conditions
                }
            }
        }
    }, $cb);
}

sub frequency_operator {
    my ($args, $query_string, $cb) = @_;

    my @conditions = (
        (defined($args->{in}) ? { prefix => { file => $args->{in}  } }   : ())
    );
    es_search({
        body  => {
            size  => 1,
            query => {
                constant_score => { filter => {
                    and => [
                        { term => { _type => "p5_op" } },
                        { term => { class => "PPI::Token::Operator" } },
                        @conditions
                    ],
                    defined($query_string) ? (
                        or => [
                            { "term" => { "tags" => "symbol:before=$query_string" } },
                            { "term" => { "tags" => "symbol:after=$query_string" } }
                        ]
                    ):(),
                } }
            },
            aggregations => {
                operator => {
                    terms => {
                        field => "content",
                        size => $args->{size} // 25,
                    }
                }
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

sub frequency_hash_names {
    my ($args, $query_string, $cb) = @_;

    my @conditions = (
        { term => { tags => "subscript:content={$query_string}" } },
        (defined($args->{in})     ? { prefix => { file => $args->{in}  } }   : ())
    );

    es_search({
        body  => {
            size  => $args->{size} // 25,
            query => {
                bool => { must => \@conditions }
            },
            aggregations => {
                hash_names => {
                    terms => {
                        field => "tags",
                        include => "subscript:symbol.*",
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
                        include => "method:invocant=.*",
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

sub frequency_token_class {
    my ($args, $query_string, $cb) = @_;

    my @conditions = (
        { prefix => { "class" => "PPI::Token" } },
        (defined($args->{in})   ? { prefix => { file => $args->{in}  } }     : ())
    );

    es_search({
        body  => {
            size  => 0,
            query => {
                constant_score => { filter => { and => \@conditions } }
            },
            aggregations => {
                token_class => {
                    terms => {
                        field => "class",
                        size  => $args->{size} // 25,
                    }
                }
            }
        }
    }, $cb);
}

sub list_project {
    my @projects;
    es_search({
        body  => {
            size  => 0,
            query => { match_all => {} },
            aggregations => {
                projects => {
                    terms => {
                        field => "project",
                        size  => 0,
                    }
                }
            }
        }
    }, sub {
        my $res = shift;
        for (@{ $res->{aggregations}{projects}{buckets} }) {
            push(@projects, $_->{key}) if $_->{key} ne "";
        }
    });

    return \@projects;
}

1;
