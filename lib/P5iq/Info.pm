package P5iq::Info;
use v5.14;
use strict;
use warnings;

use P5iq::Search;

sub project {
    my ($project_name) = @_;
    my $info = {};
    __fleshen_project_info_files($info, $project_name);
    __fleshen_project_info_packages($info, $project_name);
    __fleshen_project_info_subroutines($info, $project_name);
    return undef if keys %$info == 0;
    return $info;
}

sub package {
    my ($name, $options) = @_;
    my $info = {};
    __fleshen_package_info_files($info, $name, $options);
    __fleshen_package_info_subroutines($info, $name, $options);
    __fleshen_package_info_dependencies($info, $name, $options);
    return undef if keys %$info == 0;
    return $info;
}

sub subroutine {
    my ($name, $options) = @_;
    my $info = {};
    __fleshen_subroutine_info_definitions($info, $name, $options);
    __fleshen_subroutine_info_function_calls($info, $name, $options);
    __fleshen_subroutine_info_method_invocations($info, $name, $options);
    __fleshen_subroutine_info_dependencies($info, $name, $options);
    return undef if keys %$info == 0;
    return $info;
}

sub __fleshen_project_info_packages {
    my ($info, $project_name) = @_;
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
}

sub __fleshen_project_info_files {
    my ($info, $project_name) = @_;
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
}

sub __fleshen_project_info_subroutines {
    my ($info, $name, $options) = @_;

    P5iq::Search::es_search({
        body => {
            query => {
                bool => {
                    must => [
                        { term => { project => $name } },
                        { term => { tags    => "subroutine:def" } },
                    ]
                }
            },
            size => 0,
            aggregations => {
                subroutines => {
                    terms => { field => "tags", include => "subroutine:name=.*", size => 0 },
                }
            }
        }
    }, sub {
        my $res = shift;
        if ($res->{hits}{total} > 0) {
            $info->{subroutines} = [ map { +{ name => substr($_->{key}, 16) } } @{ $res->{aggregations}{subroutines}{buckets} } ];
        }
    });
}

sub __fleshen_package_info_files {
    my ($info, $name, $options) = @_;

    P5iq::Search::es_search({
        body => {
            query => {
                constant_score => {
                    query => {
                        bool => {
                            must => [
                                (defined($options->{project}) ? { term => { project => $options->{project} } } : ()),
                                { term => { tags    => "package:def" } },
                                { term => { tags    => "package:name=$name" } },
                            ]
                        }
                    }
                }
            },
            size => 0,
            aggregations => {
                files => {
                    terms => { field => "file", size => 0 },
                }
            }
        }
    }, sub {
        my $res = shift;
        if ($res->{hits}{total} > 0) {
            $info->{files} = [ map { +{ name => $_->{key} } } @{ $res->{aggregations}{files}{buckets} } ];
        }
    });
}

sub __fleshen_package_info_subroutines {
    my ($info, $name, $options) = @_;

    P5iq::Search::es_search({
        body => {
            query => {
                bool => {
                    must => [
                        (defined($options->{project}) ? { term => { project => $options->{project} } } : ()),
                        { term => { tags => "subroutine:def" } },
                        { term => { tags => "package:name=$name" } },
                    ]
                }
            },
            size => 0,
            aggregations => {
                subroutines => {
                    terms => { field => "tags", include => "subroutine:name=.*", size => 0 },
                }
            }
        }
    }, sub {
        my $res = shift;
        if ($res->{hits}{total} > 0) {
            $info->{subroutines} = [ map { +{ name => substr($_->{key}, 16) } } @{ $res->{aggregations}{subroutines}{buckets} } ];
        }
    });
}

sub __fleshen_package_info_dependencies {
    my ($info, $name, $options) = @_;
    P5iq::Search::es_search({
        body => {
            query => {
                bool => {
                    must => [
                        (defined($options->{project}) ? { term => { project => $options->{project} } } : ()),
                        { term => { tags => "package:dependency" } },
                        { term => { tags => "package:name=$name" } },
                    ]
                }
            },
            size => 25,
        }
    }, sub {
        my $res = shift;
        if ($res->{hits}{total} > 0) {
            my @x;
            for (@{ $res->{hits}{hits} }) {
                my $src = $_->{_source};
                for (@{$src->{content}}) {
                    push @x, { name => $_ }
                }
            }
            $info->{dependencies} = \@x;
        }
    });
}

sub __fleshen_subroutine_info_definitions {
    my ($info, $name, $options) = @_;

    P5iq::Search::es_search({
        body => {
            query => {
                bool => {
                    must => [
                        (defined($options->{project}) ? { term => { project => $options->{project} } } : ()),
                        (defined($options->{package}) ? { term => { tags => "package:name=".$options->{package} } } : ()),
                        { term => { tags    => "subroutine:def" } },
                        { term => { content => $name } },
                    ]
                }
            },
            size => 25,
        }
    }, sub {
        my $res = shift;
        if ($res->{hits}{total} > 0) {
            my @defs;
            for (@{ $res->{hits}{hits} }) {
                my $src = $_->{_source};
                push @defs, {
                    file => $src->{file},
                    location => $src->{location},
                };
            }
            $info->{definitions} = \@defs;
        }
    });
}

sub __fleshen_subroutine_info_function_calls {
    my ($info, $name, $options) = @_;

    P5iq::Search::es_search({
        body => {
            query => {
                bool => {
                    must => [
                        (defined($options->{project}) ? { term => { project => $options->{project} } } : ()),
                        { term => { tags => "function:call" } },
                        { term => { tags => "function:name=$name" } },
                    ],
                    (defined($options->{package}) ? (
                     should => [
                         { term => { tags => "function:namespace=".$options->{package} } }
                     ]):())
                }
            },
            size => 25,
        }
    }, sub {
        my $res = shift;
        if ($res->{hits}{total} > 0) {
            my @x;
            for (@{ $res->{hits}{hits} }) {
                my $src = $_->{_source};
                push @x, {
                    file => $src->{file},
                    location => $src->{location},
                };
            }
            $info->{function_calls} = \@x;
        }
    });
}

sub __fleshen_subroutine_info_method_invocations {
    my ($info, $name, $options) = @_;

    P5iq::Search::es_search({
        body => {
            query => {
                bool => {
                    must => [
                        (defined($options->{project}) ? { term => { project => $options->{project} } } : ()),
                        { term => { tags => "method:call" } },
                        { term => { tags => "method:name=$name" } },
                    ],
                    (defined($options->{package}) ? (
                        should => [ { term => { tags => "method:invocant=" . $options->{package} } } ]
                    ):())
                }
            },
            size => 25,
        }
    }, sub {
        my $res = shift;
        if ($res->{hits}{total} > 0) {
            my @x;
            for (@{ $res->{hits}{hits} }) {
                my $src = $_->{_source};
                push @x, {
                    file => $src->{file},
                    location => $src->{location},
                };
            }
            $info->{method_invocations} = \@x;
        }
    });
}

sub __fleshen_subroutine_info_dependencies {
    my ($info, $name, $options) = @_;

    P5iq::Search::es_search({
        body => {
            query => {
                bool => {
                    must => [
                        (defined($options->{project}) ? { term => { project => $options->{project} } } : ()),
                        # (defined($options->{package}) ? { term => { tags => "in:package=".$options->{package} } } : ()),
                        { term => { tags => "in:sub=$name" } },
                        { terms => { tags => ["function:call", "method:call"]} },
                    ]
                }
            },
            size => 25,
        }
    }, sub {
        my $res = shift;
        if ($res->{hits}{total} > 0) {
            my @x;
            for (@{ $res->{hits}{hits} }) {
                my $src = $_->{_source};
                next unless defined($src->{gist});
                push @x, {
                    gist => $src->{gist},
                    file => $src->{file},
                    location => $src->{location},
                };
            }
            $info->{dependencies} = \@x;
        }
    });
}

1;
