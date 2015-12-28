package P5iq;
use v5.14;

use PPIx::LineToSub;
use Elastijk;

sub idx {
    return $ENV{P5IQ_INDEX} // 'p5iq';
}

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
    unless ($es->exists( index => idx() )) {
        my ($status, $res) = $es->put(
            index => idx(),
            body  => {
                mappings => {
                    p5_node => {
                        properties => {
                            project       => { "type" => "string", "index" => "not_analyzed" },
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
                    p5_statement => {
                        properties => {
                            project       => { "type" => "string", "index" => "not_analyzed" },
                            file          => { "type" => "string", "index" => "not_analyzed" },
                            line_number   => { "type" => "integer" },
                            class         => { "type" => "string", "index" => "not_analyzed" },
                            token_content => { "type" => "string" },
                            token_class   => { "type" => "string","index" => "not_analyzed" },
                            tags          => { "type" => "string","index" => "not_analyzed" },
                        }
                    }
                }
            }
        );
    }
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

sub delete_all {
    my $es = es();
    $es->delete(
        index => idx(),
    );
}

1;
