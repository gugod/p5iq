# Configuration

By default it requires an Elasticsearch instance running on 'localhost:9200'.
This can be controled with the following environment variable:

    P5IQ_ELASTICSEARCH_HOSTPORT=example.com:9200

# command synopsis

## Index some content

    p5iq-index ~/src/App-perlbrew
    p5iq-index ~/src/perl

## Locate symbols

    p5iq-locate '$foo'
    p5iq-locate '%foo'

## Search statements

    p5iq-search '$foo->bar()'
    p5iq-search ' $v eq "bar" '
    
# License

MIT License: http://gugod.mit-license.org/
