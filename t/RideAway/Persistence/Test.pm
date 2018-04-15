#!/usr/bin/env perl
package RideAway::Persistence::Test;
use 5.006;
use strict;
use warnings;
use base qw(Test::Class);
use Test::More;
use Test::Deep;
use Test::Exception;
use Test::Differences;
use Test::MockObject;
use Mock::Quick;
use List::Util qw(sum);
use Log::Log4perl;
my $logger = Log::Log4perl::get_logger();

# MockSleep MUST be USEd before 'RideAway::Persistence' in order to take over 'sleep;
# use Test::MockSleep;
use RideAway::Persistence;

use Test::MockObject::Extends;
use Config::IniFiles;
use FindBin qw($Bin);


sub startup : Test(startup) {
    my $self = shift;
}

sub setup : Test(setup) {
    my $self = shift;

    my $persist = RideAway::Persistence->new(config_file => "$Bin/../t/data/config.test.ini");

    $persist = Test::MockObject::Extends->new($persist);
    $persist->mock('send_telegram', sub { shift;
                                          my $msg = shift;
                                          $logger->debug("Sending TELEGRAM: [$msg]" )
                                        });
    my $schema  = $persist->schema;
    $self->{schema} = $schema;
    $self->{persist} = $persist;
}

sub teardown : Test(teardown) {
    my $schema = shift->{schema};
}

sub test_schema_struct :Test(no_plan) {
    my $self = shift;

    my $test_db =  `sqlite3 $Bin/../t/data/rideaway_test.db \'.schema\'`;
    my $live_db =  `sqlite3 $Bin/../rideaway.db \'.schema\'`;
    is ($test_db, $live_db, 'test and live db have identical structure');
}

sub test_config_struct :Test(no_plan) {
    my $self = shift;

    my $test_cfg = Config::IniFiles->new( -file => "$Bin/../t/data/config.test.ini" );
    my $live_cfg = Config::IniFiles->new( -file => "$Bin/../config/config.live.ini" );

    eq_or_diff(
        [sort $test_cfg->Sections],
        [sort $live_cfg->Sections],
        'test and config ini have identical sections'
    );

    foreach my $sect ($test_cfg->Sections) {
        eq_or_diff(
            [sort $test_cfg->Parameters($sect) ],
            [sort $live_cfg->Parameters($sect) ],
            "parameter keys of Section [$sect] agree between live and config"
        );
    }
}

sub test_run : Test(no_plan) {
    my $self = shift;
    my $schema = $self->{schema};
    my $persist = $self->{persist};

    my $still_locked = $schema->resultset('Status')
     ->search( { code => 'locked_for_others' } )
     ->single;

    my $locked_for_me = $schema->resultset('Status')
     ->search( { code => 'locked_for_me' } )
     ->single;

    my $unknown = $schema->resultset('Status')
     ->search( { code => 'unknown' } )
     ->single;

    my @sleep_secs;
    $persist->mock('_sleep_ride', sub { 0 } );
    $persist->mock('_sleep_retry', sub { shift; push @sleep_secs, shift } );

    can_ok($persist, (qw/persistent_mode_is_on/));

    subtest 'shouldnt apply when persistent mode is off' => sub {
            $schema->txn_begin; # <-- low level
            $persist->set_always('apply_to_ride', $still_locked );
            $persist->set_always('persistent_mode_is_on', 0);
            my ($ride) = $self->_make_reapplicable_rides(1);
            $persist->mock('_get_rides',   sub { $ride });
            my @calls;
            $ride->mock('apply', sub { push @calls, 1; return $still_locked } );
            $persist->run();
            is(scalar @calls, 0 );
            $schema->txn_rollback;
            $persist->unmock('_get_rides');
            $persist->unmock('apply');
            $persist->unmock('apply_to_ride');
    };

    subtest 'should persist up to max_retries' => sub {
        $schema->txn_begin;
        $persist->set_always('apply_to_ride', $still_locked );
        $persist->set_always('persistent_mode_is_on', 1);
        $persist->max_run_time(50000); # ridiculous amount, enough to make the retries
        my ($ride) = $self->_make_reapplicable_rides(1);
        $persist->max_retries(3);
        $persist->run();
        $ride = $schema->resultset('Ride')->find($ride->id);
        is($ride->retries, 3 );
        $schema->txn_rollback;
        $persist->unmock('apply_to_ride');
    };

    subtest 'should break if ride has a non "locked_for_others" status' => sub {
        $schema->txn_begin;
        $persist->set_always('persistent_mode_is_on', 1);

        my $control = qtakeover 'RideAway::Schema::Result::Ride' => ();
        my $tries = 0;
        $control->override('apply' => sub {
                                             my $self = shift;
                                             $self->update({status => $unknown});
                                             return $unknown;
                                          } );
        my ($ride) = $self->_make_reapplicable_rides(1);
        $persist->max_retries(18);
        $persist->run();
        $ride = $schema->resultset('Ride')->find($ride->id);
        is($ride->retries, 1 );
        $schema->txn_rollback;
        $control = undef;
        $persist->unmock('apply_to_ride');
    };

    subtest 'when locked for me, it sends me telegram' => sub {
        $schema->txn_begin;
        $persist->set_always('persistent_mode_is_on', 1);

        my @calls;
        $persist->mock('send_telegram', sub { shift; push @calls, shift });

        my $control = qtakeover 'RideAway::Schema::Result::Ride' => ();
        my $tries = 0;
        $control->override('apply' => sub {
                                             my $self = shift;
                                             $self->update({status => $locked_for_me});
                                             return $locked_for_me;
                                          } );

        my ($ride) = $self->_make_reapplicable_rides(1);
        $persist->run();
        my @bingo = grep { /BINGO/ } @calls;
        is(scalar @bingo, 1, 'got one telegram message with BINGO inside it');
        $schema->txn_rollback;

        $control = undef;
        $persist->unmock('apply_to_ride');
    };

    subtest 'sleep and retry time span behaviour' => sub {
        $schema->txn_begin;
        $persist->set_always('apply_to_ride', $still_locked );
        $persist->set_always('persistent_mode_is_on', 1);
        $persist->max_run_time(60); # 60 seconds to go
        my ($ride) = $self->_make_reapplicable_rides(1);
        $persist->max_retries(1000);
        $persist->run();

        $ride->discard_changes;

        # simulate running the script a 15 times

        @sleep_secs = ();
        for (1..17) { # if it ran 17 times..., lets see what number of retries would take place:
            $persist->run;
        }

        $ride->discard_changes;

        # would apply on average 3x per run (per 60 seconds) if wait_retry = int(rand(15)) + 10
        # so expect around ~30-40 re-applications in 17 runs
        cmp_ok($ride->retries, '<', 50, 'applied less than max range' );
        cmp_ok($ride->retries, '>', 20, 'applied more than min range' );
        diag explain $ride->retries . ' <---- ACTUAL APPLICATION COUNT';

        my $num_calls = @sleep_secs;
        my $total_wait = sum @sleep_secs;
        diag explain join '-', @sleep_secs, '<--- ACTUAL WAIT SECONDS';
        my $avg_wait_span = $total_wait/$num_calls;
        cmp_ok($avg_wait_span, '<', 50, 'below wait span max' );
        cmp_ok($avg_wait_span, '>', 10, 'above wait span min' );
        diag explain $avg_wait_span . ' <---- ACTUAL WAIT SPAN';
        diag 'Avg - span:'.  $total_wait/$num_calls . ' seconds between calls';


        $schema->txn_rollback;
        $persist->unmock('apply_to_ride');
    };


}

sub test_get_rides_to_reapply : Test(no_plan) {
    my $self = shift;
    my $schema = $self->{schema};

    $schema->txn_begin; # <-- low level
    $self->_make_reapplicable_rides(10);
    $self->_make_ride() for (1..5);

    my $ride_rs = $schema->resultset('Ride')->reapplicable_rides;
    is($ride_rs->count, 10);

    my $persist = $self->{persist};
    my @rides = $persist->_get_rides;

    is(scalar @rides, 10);
    diag("Roll Back");
    $schema->txn_rollback;
}

sub _make_reapplicable_rides {
    my ($self, $quantity) = @_;
    my $schema = $self->{schema};

    my $locked_for_others = $schema
                 ->resultset('Status')
                 ->search( { code => 'locked_for_others' } )
                 ->single;

    my @rides = map { $self->_make_ride($locked_for_others, 1) } (1..$quantity);
    return @rides;
}

my $unique_maker = 1;
sub _make_ride {
    my ($self, $status, $should_persist) = @_;
    my $rs = $self->{schema}->resultset('Ride');
    $status ||=  $self->{schema}->resultset('Status')->search( { code => 'new' } )->single;
    my $ride = $rs->create(
          {
            created_dt => DateTime->now(time_zone => "Europe/London"),
            ride_dt    => DateTime->now(time_zone => "Europe/London")->add( months => int(rand(10)), days => int(rand(1000)) ),
            location_from => 'GothamCity- ' . $unique_maker++,
            location_to => 'amsterdam',
            num_people => 2,
            url => 'https://www.example.com',
            msgid => 12345,
            price => 10.5,
            sms_sent => 0,
            status => $status,
            should_persist => $should_persist || 0,
        } );
    return Test::MockObject::Extends->new($ride);
}

1;
