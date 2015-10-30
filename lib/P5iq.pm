package P5iq;
use v5.18;

use PPIx::LineToSub;

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

sub create_index_if_not_exist {
    my $es = es();
    unless ($es->exists( index => "p5iq" )) {
        my ($status, $res) = $es->put(
            index => "p5iq",
            body  => {
                mappings => {
                    p5_node => {
                        properties => {
                            file          => { "type" => "string", "index" => "not_analyzed" },
                            line_number   => { "type" => "integer" },
                            row_number    => { "type" => "integer" },
                            class         => { "type" => "string", "index" => "not_analyzed" },
                            content       => { "type" => "string", "index" => "not_analyzed" },
                            token_content => { "type" => "string" },
                            token_class   => { "type" => "string","index" => "not_analyzed" },
                            tags          => { "type" => "string","index" => "not_analyzed" },
                        }
                    },
                }
            }
        );
    }
}

sub extract_token {
    my ($ppi_doc) = @_;
    my @doc;
    for my $x ( $ppi_doc->tokens ) {
        next unless $x->significant;
        my $location = $x->location;
        my $doc = {
            line_number => $location->[0],
            row_number  => $location->[1],
            content  => $x->content,
            class    => $x->class,
            tags     => [],
        };
        if (ref($x) eq 'PPI::Token::Symbol') {
            push @{$doc->{tags}}, (
                'symbol:actual='    . $x->symbol,
                'symbol:canonical=' . $x->canonical
            );
            if ( ref(my $x_parent = $x->parent) eq 'PPI::Statement::Variable' ) {
                push @{$doc->{tags}}, (
                    'in:statement:variable'
                );
                my $ns = $x->snext_sibling;
                if( ref($ns) eq 'PPI::Token::Operator' && $ns->content eq '=' ){
                    push @{$doc->{tags}}, (
                        'in:statement:variable:defined'
                    );
                }
            }
        }
        push @doc, $doc;
    }
    return @doc;
}

sub extract_subscript {
    my ($ppi_doc) = @_;
    my @doc;
    for my $s (@{ $ppi_doc->find('PPI::Structure::Subscript') ||[] }) {
        my @c = ( $s );
        my $p = $s;
        while ($p = $p->sprevious_sibling) {
            unshift @c, $p;
            last if $p->isa("PPI::Token::Symbol");
        }
        my $location = $c[0]->location;
        my $doc = {
            line_number   => $location->[0],
            row_number    => $location->[1],
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

sub extract_function_calls {
    my ($ppi_doc) = @_;
    my @doc;

    # Look for all "word followed by a list within parenthesis"
    # foo(); foo(1,2,3); foo( bar(1,2,3), 4)
    for my $s (@{ $ppi_doc->find('PPI::Token::Word') ||[]}) {
        next unless ref($s->parent) eq 'PPI::Statement';

        my $prev = $s->sprevious_sibling;
        next if ($prev && ref($prev) eq 'PPI::Token::Operator' && $prev->content eq "->");

        my $args = $s->snext_sibling;
        next unless ref($args) eq 'PPI::Structure::List';

        push @doc, {
            line_number   => $s->location->[0],
            row_number    => $args->location->[1],
            content       => join("", "$s", "$args"),
            class         => 'P5iq::FunctionCall',
            tags          => [
                "function:call",
                "function:name=$s",
                "function:arglist=$args"
            ],
        };
    }

    # TODO: Look for all "word followed by a list not within parenthesis"
    # foo; foo 1,2; foo bar(1,2,3), 4;

    return @doc;
}

sub analyze_for_index {
    my ($ppi_doc) = @_;

    $ppi_doc->index_line_to_sub;

    my @doc;
    push @doc, extract_token($ppi_doc);
    push @doc, extract_subscript($ppi_doc);
    push @doc, extract_function_calls($ppi_doc);
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
