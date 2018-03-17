#!perl -T
use 5.006;
use strict;
use warnings;
use Test::More;

plan tests => 1;

BEGIN {
    use_ok( 'RideAway::AutoResponder' ) || print "Bail out!\n";
}

diag( "Testing RideAway::AutoResponder $RideAway::AutoResponder::VERSION, Perl $], $^X" );
