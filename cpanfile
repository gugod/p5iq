requires "Dancer2"                => "0.159002";
requires 'Clone::PP'              => 0;
requires 'DDP'                    => 0;
requires 'Elastijk'               => 0;
requires 'File::Next'             => 0;
requires 'Git::Wrapper'           => '0.045';
requires 'JSON'                   => 0;
requires 'List::MoreUtils'        => 0;
requires 'PPI'                    => 0;
requires 'PPIx::LineToSub'        => 0;
requires 'Parallel::ForkManager'  => 0;
requires 'Pod::POM'               => 0;
requires 'Sys::Info'              => 0;
requires 'Sys::Info::Device::CPU' => 0;
requires 'Plack::Runner'          => 0;
requires 'YAML'                   => 0;
requires 'Template'               => 0;
requires 'Gazelle'                => 0;
requires 'HTML::Escape'           => 0;


recommends "YAML"             => "0";
recommends "URL::Encode::XS"  => "0";
recommends "CGI::Deurl::XS"   => "0";
recommends "HTTP::Parser::XS" => "0";

on "test" => sub {
    requires "Test::More"            => "0";
    requires "HTTP::Request::Common" => "0";
};
