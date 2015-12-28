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

    my $TypeLineColumn = {
        properties => {
            tag    => { type => "String", index => "not_analyzed" },
            line   => { type => "integer" },
            column => { type => "integer" }
        }
    };

    my @GenericFields = (
        project       => { "type" => "string", "index" => "not_analyzed" },
        file          => { "type" => "string", "index" => "not_analyzed" },
        class         => { "type" => "string", "index" => "not_analyzed" },
        content       => { "type" => "string", "index" => "not_analyzed" },
        tags          => { "type" => "string","index" => "not_analyzed" },
        location      => $TypeLineColumn,
        scope         => {
            properties => {
                tag    => { type => "String", index => "not_analyzed" },
                begin => $TypeLineColumn,
                end   => $TypeLineColumn,
            }
        }
    );

    unless ($es->exists( index => idx() )) {
        my ($status, $res) = $es->put(
            index => idx(),
            body  => {
                settings => {
                    "index.mapper.dynamic" => 0
                },
                mappings => {
                    p5_node => { properties => {
                        (@GenericFields),
                        token_content => { "type" => "string" },
                        token_class   => { "type" => "string","index" => "not_analyzed" },
                    } },
                    p5_token => { properties => { @GenericFields } },
                    p5_sub => { properties => { @GenericFields } },
                    p5_package => { properties => { @GenericFields } },
                    p5_statement => { properties => { @GenericFields } },
                    p5_dependency => { properties => { @GenericFields } },
                }
            }
        );
    }
}

sub delete_all {
    my $es = es();
    $es->delete(
        index => idx(),
    );
}

1;
