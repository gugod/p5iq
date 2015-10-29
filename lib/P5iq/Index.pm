package P5iq::Index;
use v5.18;

use P5iq;
use PPI;

use File::Next;
use JSON qw(to_json);
use Elastijk;
use Parallel::ForkManager;

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

    my $forkman = Parallel::ForkManager->new(2);

    my $files = File::Next::files({ file_filter => sub { is_perl($File::Next::name) } }, $srcdir);
    while ( defined ( my $file = $files->() ) ) {
        $forkman->start and next;
        $cb->($file);
        $forkman->finish;
    }
    $forkman->wait_all_children;
}

sub index_perl_source_code {
    my ($file) = @_;
    say "<<< $file";
    my $ppi_doc = PPI::Document->new($file) or return;

    my @features = P5iq::analyze_for_index($ppi_doc);

    for (@features) {
        $_->{file} = $file;
    }
    say ">>> " . scalar(@features) . " features";

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
        index => "p5iq",
        command => "_query",
        body => { query => { term => { file => $file }}}
    );
}

sub index_these {
    state $es = es_object();
    my $features = shift;
    $es->bulk(
        index => "p5iq",
        type  => "p5_node",
        body => [ map { ({index => {}}, $_) } @$features ]
    );
}

sub index_dirs {
    my (@dirs) = @_;

    for my $srcdir (@dirs) {
        scan_this_dir($srcdir, \&index_perl_source_code );
    }
    say "### optimizing index";
    es_object->post( command => "_optimize", uri_param => {  max_num_segments  => 1 } );
}


1;