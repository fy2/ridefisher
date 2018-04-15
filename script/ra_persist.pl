#!/usr/bin/env perl
use strict;
use warnings;
use FindBin qw($Bin);
use lib "$Bin/../lib";
use Log::Log4perl;
use RideAway::Persistence;

Log::Log4perl::init_and_watch("$Bin/../config/log4perl_persist.conf",10);

my $persist = RideAway::Persistence->new(config_file => "$Bin/../config/config.live.ini");
$persist->run;
