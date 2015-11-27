package P5iq::Index;
use v5.14;

use P5iq;
use PPI;

use File::Next;
use JSON qw(to_json);
use Parallel::ForkManager;

use Sys::Info;
use constant NCPU => Sys::Info->new->device('CPU')->count;

sub is_perl {
    my ($file) = @_;

    return 1 if $file =~ / \.p[ml] $/x;
    return if $file =~ / \.swp $/x;
    if (open my $fh, '<', $file) {
        my $line = <$fh>;
        return 1 if $line =~ m{^#!.*perl};
    }
    return;
}

sub scan_this_dir {
    my ($srcdir, $cb) = @_;

    my $forkman = Parallel::ForkManager->new( NCPU - 1 );

    my $files = File::Next::files({ file_filter => sub { is_perl($File::Next::name) } }, $srcdir);
    while ( defined ( my $file = $files->() ) ) {
        $forkman->start and next;
        $cb->($file);
        $forkman->finish;
    }
    $forkman->wait_all_children;
}

sub index_perl_source_code {
    my ($args, $file) = @_;
    my $ppi_doc = PPI::Document->new($file) or return;

    my @features = P5iq::analyze_for_index($ppi_doc);

    $args->{project} //= "";
    for (@features) {
        $_->{file} = $file;
        $_->{project} = $args->{project};
    }
    say "[$$] index\t$file\t" . scalar(@features) . " features";

    delete_by_file($file);
    index_these(\@features);
}

sub es_object {
    state $es;

    unless ($es) {
        $es = P5iq->es;
        P5iq::create_index_if_not_exist();
    }

    return $es;
}

sub delete_by_file {
    state $es = es_object();
    my $file = shift;
    $es->delete(
        index => P5iq::idx(),
        command => "_query",
        body => { query => { term => { file => $file }}}
    );
}

sub index_these {
    state $es = es_object();
    my $features = shift;
    $es->bulk(
        index => P5iq::idx(),
        type  => "p5_node",
        body => [ map { ({index => {}}, $_) } @$features ]
    );
}

sub index_dirs {
    my ($args, @dirs) = @_;

    for my $srcdir (@dirs) {
        scan_this_dir(
            $srcdir,
            sub {
                index_perl_source_code($args, $_[0]);
            }
        );
    }
}


1;
