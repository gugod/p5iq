###Status
[![Build Status](https://travis-ci.org/gugod/p5iq.png)](https://travis-ci.org/gugod/p5iq)

# Configuration

By default it requires an Elasticsearch instance running on 'localhost:9200'.
This can be controled with the following environment variable:

    P5IQ_ELASTICSEARCH_HOSTPORT=example.com:9200

# Setup

## Install dependencies

    cpanm -L local/ --installdeps .

# Web UI

    bin/p5iq-plackup
    # open http://localhost:5000/

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
