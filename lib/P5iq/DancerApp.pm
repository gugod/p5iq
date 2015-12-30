package P5iq::DancerApp;
use Dancer2;

use P5iq::Search;
use P5iq::Info;

use Data::Dumper;

our $VERSION = '0.1';

get '/' => sub {
    my $query = params->{'q'};
    my $search_args = params->{'search_args'};

    my $results;
    my $freq_results;

    if (defined $search_args && length $search_args) {
        if ($search_args eq "variable_lvalue") {
            $results->{lvalue} = locate_variable( $query, 'lvalue' );
            $freq_results->{hash_keys} = freq_hash_keys( $query );
        }

        if ($search_args eq "variable_in-string") {
            $results->{'in-string'} = locate_variable( $query, 'in-string' );
            $freq_results->{hash_keys} = freq_hash_keys( $query );
        }

        if ( $search_args eq "sub_method" ) {
            $results->{method} = locate_sub( $query, 'method' );
            $freq_results->{invocant} = freq_invocant( $query );
            $freq_results->{res} = freq_args( $query );
        }

        if ( $search_args eq "sub_function" ) {
            $results->{function} = locate_sub( $query, 'function' );
            $freq_results->{invocant} = freq_invocant( $query );
            $freq_results->{res} = freq_args( $query );
        }

        if ( $search_args eq "value" ) {
            $results->{value} = locate_value( $query, 'value');
        }
    }
    elsif( defined $query && length $query ) {
        $results->{lvalue} = locate_variable( $query, 'lvalue');
        $results->{'in-string'} = locate_variable( $query, 'in-string');
        $results->{method} = locate_sub( $query, 'method' );
        $results->{function} = locate_sub( $query, 'function' );
        $results->{value} = locate_value( $query, 'value' );

        $freq_results->{hash_keys} = freq_hash_keys( $query );
        $freq_results->{invocant} = freq_invocant( $query );
        $freq_results->{res} = freq_args( $query );
    }

    my $stash = {
        'query' => $query,
        'search_args' => $search_args,
        'results' => $results,
        'freq_results' => $freq_results,
    };

    fleshen_global_content($stash);
    get_result_abstract($results);

    template 'index', $stash;
};

get "/project" => sub {
    my $project_name = params->{'n'};
    my $project_info = P5iq::Info::project($project_name);

    if (!$project_info) {
        send_error("Not found", 404);
    }

    if ($project_info->{packages}) {
        for (@{$project_info->{packages}}) {
            $_->{url} = uri_for("/package", { project => $project_name, n => $_->{name} });
        }
    }

    my $stash = {};
    $stash->{project_info} = $project_info;

    fleshen_global_content($stash);
    template project => $stash;
};

get "/package" => sub {
    my $package_name = params->{n};
    my $project_name = params->{project};
    my $package_info = P5iq::Info::package($package_name, { project => $project_name });

    if (!$package_info) {
        send_error("Not found", 404);
    }

    if ($package_info->{subroutines}) {
        for (@{$package_info->{subroutines}}) {
            $_->{url} = uri_for("/subroutine", { project => $project_name, package => $package_name, n => $_->{name} });
        }
    }

    my $stash = {};
    $stash->{package_info} = $package_info;

    fleshen_global_content($stash);
    template package => $stash;
};

get "/subroutine" => sub {
    my $stash = {};
    fleshen_global_content($stash);
    template subroutine => $stash;
};

get "/nothing" => sub {
    my $stash = {};
    fleshen_global_content($stash);
    template nothing => $stash;
};

my $default_call_back = sub {
    my $res = shift;
    my @ret;
    foreach ( @{$res->{hits}{hits}} ){
        my $src = $_->{_source};
        push @ret, {
            file  => $src->{file},
            start => $src->{location}->{begin}->{line},
            end   => $src->{location}->{end}->{line},
        }
    }
    return \@ret;
};

sub fleshen_global_content {
    my ($stash) = @_;

    my @projects = map {
        +{
            name => $_,
            url  => uri_for("/project", {n => $_})
       }
    } @{P5iq::Search::list_project()};

    $stash->{global_projects} = \@projects;

    $stash->{global_search_query} = param("q");
}

sub locate_variable{
    my ($query, $args) = @_;
    my %args = ( $args => 1 );
    P5iq::Search::locate_variable(\%args, $query, $default_call_back);
}

sub locate_sub{
    my ($query, $args) = @_;
    my %args = ( $args => 1 );
    P5iq::Search::locate_sub(\%args, $query, $default_call_back);
}

sub locate_value{
    my ($query, $args) = @_;
    my %args = ( $args => 1 );
    P5iq::Search::locate_value(\%args, $query, $default_call_back);
}

sub freq_hash_keys {
    my ($query) = @_;
    my %args;
    P5iq::Search::frequency_hash_keys(\%args, $query,
        sub {
            my $res = shift;
            my @ret;
            for (@{$res->{aggregations}{hash_keys}{buckets}}) {
                my $k = substr($_->{key}, length('subscript::content=') - 1 );
                push @ret, {
                    doc_count => $_->{doc_count},
                    content => $k,
                }
            }
            return \@ret;
        }
    );
}

sub freq_invocant {
    my ($query) = @_;
    my %args;
    P5iq::Search::frequency_invocant(\%args, $query,
        sub {
            my $res = shift;
            my @ret;
            for (@{$res->{aggregations}{invocant}{buckets}}) {
                my $k = $_->{key} =~ s/^method:context=//r;
                push @ret, {
                    doc_count => $_->{doc_count},
                    content => $k,
                }
            }
            return \@ret;
        }
    );
}

sub freq_args {
    my ($query) = @_;
    my %args;
    P5iq::Search::frequency_invocant(\%args, $query,
        sub {
            my $res = shift;
            my @ret;
            for (@{$res->{aggregations}{args}{buckets}}) {
                my (undef,$k) = split("=", $_->{key}, 2);
                push @ret, {
                    doc_count => $_->{doc_count},
                    content => $k,
                }
            }
            return \@ret;
        }
    );
}

sub get_result_abstract {
    my ($results) = @_;
    for my $type (keys %$results){
        for my $res (@{$results->{$type}}){
            $res->{content} = `sed -n '$res->{start}, $res->{end}p' $res->{file}`;
        }
    }
}

true;
