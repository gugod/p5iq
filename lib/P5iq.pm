package P5iq;
use v5.18;

sub es {
    state $es = do {
        my ($es_host, $es_port) = ("localhost", "9200");
        if (defined($ENV{P5IQ_ELASTICSEARCH_HOSTPORT})) {
            ($es_host, $es_port) = split(":", $ENV{P5IQ_ELASTICSEARCH_HOSTPORT});
        }
        Elastijk->new(
            host => $es_host,
            port => $es_port,
        );
    };
    return $es;
}

sub analyze_for_index {
    my ($ppi_doc) = @_;

    my @doc;
    for my $statement (@{ $ppi_doc->find('PPI::Statement') ||[] }) {
        my $location = $statement->location;
        my $doc = {
            location      => join("\0",@{$location}[0,1]),
            content       => $statement->content,
            class         => $statement->class,
            token_content => [],
            token_class   => [],
            tags          => [],
        };
        for my $c ($statement->schildren) {
            push @{$doc->{token_content}}, $c->content;
            push @{$doc->{token_class}}, $c->class;
        }
        push @doc, $doc;
    }

    for my $s (@{ $ppi_doc->find('PPI::Structure::Subscript') ||[] }) {
        my @c = ( $s );
        my $p = $s;
        while ($p = $p->sprevious_sibling) {
            unshift @c, $p;
            last if $p->isa("PPI::Token::Symbol");
        }
        my $location = $c[0]->location;
        my $doc = {
            location      => join("\0",@{$location}[0,1]),
            content       => join("", @c),
            class         => 'PPI::Structure::Subscript',
            token_content => [map { $_->content } @c],
            token_class   => [map { $_->class }   @c],
            tags          => [
                "subscript:symbol=$c[0]",
                "subscript:container=" . join("", map { $_->content } @c[0..$#c-1] ),
                "subscript:content=$s",
            ],
        };
        push @doc, $doc;
    }
    return @doc;
}

sub analyze_for_query {
    my ($ppi_doc) = @_;
    my @tokens = grep { $_->significant } $ppi_doc->tokens;

    my $es_query = {
        bool => {
            must   => [ (map { +{ term => { "token_class" => $_->class } } } @tokens) ],
            should => [ (map { +{ match => { token_content => $_->content } } } @tokens) ]
        }
    };

    return $es_query;
}

1;
