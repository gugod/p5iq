package P5iq::DancerApp;
use Dancer2;

use P5iq::DancerApp::Utils qw(
    locate_variable
    locate_sub
    locate_value
    freq_hash_keys
    freq_invocant
    freq_args
    count_lines_file
    read_lines_file
);
use HTML::Escape qw/escape_html/;
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
    fleshen_file_url($results);

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

    if ($project_info->{subroutines}) {
        for (@{$project_info->{subroutines}}) {
            $_->{url} = uri_for("/subroutine", { project => $project_name, n => $_->{name} });
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

    if ($package_info->{dependencies}) {
        for (@{$package_info->{dependencies}}) {
            $_->{url} = uri_for("/package", { project => $project_name, n => $_->{name} });
        }
    }

    if ($package_info->{files}) {
        for (@{$package_info->{files}}) {
            $_->{url} = uri_for("/file", { name=> $_->{name} });
        }
    }

    my $stash = {};
    $stash->{package_info} = $package_info;

    fleshen_global_content($stash);
    template package => $stash;
};

get "/subroutine" => sub {
    my $subroutine_name = params->{n};
    my $project_name = params->{project};
    my $package_name = params->{package};

    my $subroutine_info = P5iq::Info::subroutine($subroutine_name, { package => $package_name, project => $project_name });

    if ($subroutine_info->{definitions}) {
        for (@{$subroutine_info->{definitions}}) {
            $_->{url} = uri_for(
                "/file", 
                { 
                    name => $_->{file}, 
                    start => $_->{location}->{begin}->{line},
                    end => $_->{location}->{end}->{line},
                }
            );
        }
    }
    
    if ($subroutine_info->{function_calls}) {
        for (@{$subroutine_info->{function_calls}}) {
            $_->{url} = uri_for(
                "/file", 
                { 
                    name => $_->{file}, 
                    start => $_->{location}->{begin}->{line},
                }
            );
        }
    }
    
    if ($subroutine_info->{method_invocations}) {
        for (@{$subroutine_info->{method_invocations}}) {
            $_->{url} = uri_for(
                "/file", 
                { 
                    name => $_->{file}, 
                    start => $_->{location}->{begin}->{line},
                }
            );
        }
    }

    my $stash = { subroutine_info => $subroutine_info };
    fleshen_global_content($stash);
    template subroutine => $stash;
};

get "/nothing" => sub {
    my $stash = {};
    fleshen_global_content($stash);
    template nothing => $stash;
};

get "/file" => sub {
    my $name = params->{name};
    my $start = params->{start};
    my $end = params->{end};
  
    my $total_line_number = count_lines_file($name);
    my $sln = $start;
    my $eln = $end;
    if( !$sln && !$eln){
        $sln = 1;
        $eln = $total_line_number;
    }
    elsif( !$eln || $eln == $sln ){
        my $tmp = $sln;
        $sln = ($tmp - 5) < 1 ? 1 : ($tmp - 5);
        $eln= ($tmp + 5) > $total_line_number ? $total_line_number : ($tmp + 5);
    }

    my $abstract = read_lines_file($name, $sln, $eln);

    escape_html( $abstract );
    my $stash = {
        name => $name,
        start_ln => $start,
        end_ln => $end,
        abstract => $abstract,
    };
    fleshen_global_content($stash);
    template file => $stash;
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

sub fleshen_file_url{
    my ($results) = @_;
    for my $type (keys %$results){
        for my $res (@{$results->{$type}}){
            $res->{url} = uri_for("/file",
                {
                    name => $res->{file},
                    start => $res->{start},
                    end => $res->{end},
                }
            );
        }
    }
}


true;
