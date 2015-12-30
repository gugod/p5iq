package P5iq::DancerApp;
use Dancer2;

use P5iq::Search;
use P5iq::Info;

use Data::Dumper;

our $VERSION = '0.1';

get '/' => sub {
    my $query = params->{'q'};
    my $search_args = params->{'search_args'};

    my $res;
    my $freq_hash_keys_res;
    my $freq_args_res;
    my $freq_invocant_res;

    if (defined $search_args) {
        if ($search_args =~ /^variable_/) {
            $res = locate_variable( $query, (substr $search_args, 9));
            $freq_hash_keys_res = freq_hash_keys( $query );
        } elsif ( $search_args =~ /^sub_/ ) {
            $res = locate_sub( $query, (substr $search_args, 4));
            $freq_invocant_res = freq_invocant( $query );
            $freq_args_res = freq_args( $query );
        } elsif ( $search_args =~ /^value/ ) {
            $res = locate_value( $query, $search_args);
        }
    }

    my $stash = {
        'query' => $query,
        'search_args' => $search_args,
        'results' => $res,
        'freq_hash_keys' => $freq_hash_keys_res,
        'freq_invocant' => $freq_invocant_res,
        'freq_args' => $freq_args_res,
    };

    fleshen_global_content($stash);

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
            file => $src->{file},
                 line_number  => $src->{line_number},
                 content  => $src->{content},
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

true;
