package P5iq::DancerApp::API;

use Dancer2;
use P5iq::DancerApp::Utils qw(
    locate_variable
    locate_sub
    locate_value
    freq_hash_keys
    freq_invocant
    freq_args
    count_lines_file
    read_lines_file
);
use Data::Dumper;

set serializer => 'JSON';

get '/' => sub {
    my $query = params->{'q'};

    my $result = locate_variable( $query, 'lvalue' );

    return {
        result => $result,
    };
};

true;
