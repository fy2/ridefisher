#!/usr/bin/env perl
use RideAway::AutoResponder::Test;
use Log::Log4perl;
use FindBin qw($Bin);
# Check config every 10 secs
Log::Log4perl::init_and_watch("$Bin/../config/log4perl.test.conf",10);

Test::Class->runtests();
