#!/usr/bin/env perl
use strict;
use warnings;
use FindBin qw($Bin);
use lib "$Bin/../lib";
use Log::Log4perl;
use RideAway::AutoResponder;

Log::Log4perl::init_and_watch("$Bin/../config/log4perl.conf",10);

my $logger = Log::Log4perl::get_logger();
if (-e "/home/feyruz/sandbox/RideAway-AutoResponder/stop") {
    $logger->warn('Nothing to be done, found a stop file');
    exit 0;
}

my $rd  = RideAway::AutoResponder->new(config_file => "$Bin/../config/config.live.ini");
$rd->run;
