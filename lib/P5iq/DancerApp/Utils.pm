package P5iq::DancerApp::Utils;

use P5iq::Search;
use P5iq::Info;

use Exporter 'import';
@EXPORT_OK = qw(
    locate_variable
    locate_sub
    locate_value
    freq_hash_keys
    freq_invocant
    freq_args
    count_lines_file
    read_lines_file
);


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

sub count_lines_file {
    my ($filename) = @_;
    my $line = 0;
    open(my $fh, "<", $filename) or die $!;
    local $/ = "\n";
    while (<$fh>) {
        $line++;
    }
    close($fh);
    return $line;
}

sub read_lines_file {
    my ($filename, $start_line, $end_line) = @_;
    open(my $fh, "<", $filename) or die $!;
    my $line = 0;
    my $abstract = "";
    local $/ = "\n";
    while (<$fh>) {
        $line++;
        if ($start_line <= $line && $line <= $end_line) {
            $abstract .= $_;
        }
    }
    close($fh);
    return $abstract;
}

