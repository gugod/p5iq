#!/usr/bin/env perl

use strict;
use warnings;
use File::Spec;
use FindBin;
use lib "${FindBin::Bin}/../local/lib/perl5";
use lib "${FindBin::Bin}/../lib";

my $appdir = $FindBin::Bin;

$ENV{DANCER_CONFDIR} = $appdir;
$ENV{DANCER_ENVDIR} = "$appdir/environments";
$ENV{DANCER_PUBLIC} = "$appdir/public";
$ENV{DANCER_VIEWS}  = "$appdir/views";

require P5iq::DancerApp;
P5iq::DancerApp->import( with => { appdir => $appdir} );

P5iq::DancerApp->psgi_app;

