package P5iq::Command::Index;
use v5.14;

use P5iq;
use P5iq::Analyzer;

use PPI;

use File::Next;
use JSON qw(to_json);
use Parallel::ForkManager;

use Git::Wrapper;
use Sys::Info;
use constant NCPU => Sys::Info->new->device('CPU')->count;

sub run {
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

sub is_perl {
    my ($file) = @_;

    return 1 if $file =~ / \.(?: t|p[ml]|pm6|pod|comp ) $/xi;
    return 0 if $file =~ / \. /xi;

    if (open my $fh, '<', $file) {
        my $line = <$fh>;
        return 1 if $line =~ m{^#!.*perl};
    }

    return 0;
}

sub scan_this_dir {
    my ($srcdir, $cb) = @_;

    $srcdir =~ s!/+\z!!;

    my $forkman = Parallel::ForkManager->new( NCPU - 1 );

    if (-d "$srcdir/.git") {
        my $git = Git::Wrapper->new($srcdir);
        my @files = $git->RUN("ls-files");
        for my $file (map { "$srcdir/$_" } @files) {
            $forkman->start and next;
            $cb->($file) if is_perl($file);
            $forkman->finish;
        }
    } else {
        my $files = File::Next::files({ file_filter => sub { is_perl($File::Next::name) } }, $srcdir);
        while ( defined ( my $file = $files->() ) ) {
            $forkman->start and next;
            $cb->($file);
            $forkman->finish;
        }
    }
    $forkman->wait_all_children;
}

sub index_perl_source_code {
    my ($args, $file) = @_;
    my $ppi_doc = PPI::Document->new($file) or return;

    my $features = P5iq::Analyzer::analyze_for_index($ppi_doc);

    $args->{project} //= "";
    for my $type (keys %$features) {
        for (@{ $features->{$type} }) {
            $_->{file} = $file;
            $_->{project} = $args->{project};
        }
        say "[$$] index\t$file\t" . scalar(@{ $features->{$type} }) . " $type features";
    }
    delete_by_file($file);
    index_these($features);
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
    my @todo;
    $es->scan_scroll(
        index => P5iq::idx(),
        body => { query => { term => { file => $file }}, _source => [], size => 1000 },
        on_response => sub {
            my ($status, $res) = @_;
            return 0 if $status ne "200";
            for (@{$res->{hits}{hits}}) {
                push @todo, [ $_->{_type}, $_->{_id} ];
            }
            return 1;
        }
    );

    while (my @batch = splice(@todo, 0, 10000)) {
        say "[$$] delete\t$file\told features: " . scalar(@batch);
        $es->bulk(
            index => P5iq::idx(),
            body => [ map { +{ delete => { _type => $_->[0], _id => $_->[1] } } } @batch ]
        );
    }
}

sub index_these {
    state $es = es_object();
    my $features = shift;
    for my $type (keys %$features) {
        $es->bulk(
            index => P5iq::idx(),
            type  => $type,
            body => [ map { ({index => {}}, $_) } @{$features->{$type}} ]
        );
    }
}

sub index_git_recent_changes {
    my ($args, @dirs) = @_;
    for my $srcdir (@dirs) {
        process_git_dir(
            $srcdir,
            sub {
                my ($files_changed) = @_;
                for (@$files_changed) {
                    my $file = $srcdir . "/" . $_;
                    index_perl_source_code($args, $file);
                }
            }
        );
    }
}

sub process_git_dir {
    my ($dir, $cb) = @_;
    my $git = Git::Wrapper->new($dir);
    my ($base_commit) = $git->log(-n => 1);
    $git->RUN('pull');
    my ($latest_commit) = $git->log(-n => 1);

    return if $base_commit->id eq $latest_commit->id;

    say $base_commit->id . "..." . $latest_commit->id;

    my @commits = $git->log({ raw => 1 }, $base_commit->id . ".." . $latest_commit->id);

    my %files_changed;
    for my $commit (@commits) {
        my @files_modified = grep { is_perl($_) } map { $_->filename } $commit->modifications;
        @files_changed{@files_modified} = (1)x@files_modified;
    }
    $cb->([ keys %files_changed ]);
}

1;
