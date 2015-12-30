package P5iq::Info;
use v5.14;
use strict;
use warnings;

use P5iq::Search;

sub project {
    my ($project_name) = @_;

    my $info = {};
    P5iq::Search::es_search({
        body => {
            query => { term => { project => $project_name } },
            size => 0,
            aggregations => {
                files_count => {
                    cardinality => { field => "file" },
                },
                files => {
                    terms => { field => "file", size => 25 },
                }
            }
        }
    }, sub {
        my $res = shift;
        if ($res->{hits}{total} > 0) {
            $info->{files} = [ map { +{ name => $_->{key} } } @{ $res->{aggregations}{files}{buckets} } ];
            $info->{files_count} = $res->{aggregations}{files_count}{value};
        }
    });


    P5iq::Search::es_search({
        body => {
            query => {
                constant_score => {
                    query => {
                        bool => {
                            must => [
                                { term => { project => $project_name } },
                                { term => { tags    => "package:def" } },
                            ]
                        }
                    }
                }
            },
            size => 0,
            aggregations => {
                packages => {
                    terms => { field => "tags", include => "package:name=.*", size => 0 },
                }
            }
        }
    }, sub {
        my $res = shift;
        if ($res->{hits}{total} > 0) {
            $info->{packages} = [ map { +{ name => substr($_->{key}, 13) } } @{ $res->{aggregations}{packages}{buckets} } ];
        }
    });
    
    if (keys %$info == 0) {
        return undef;
    }
    return $info;
}

1;
