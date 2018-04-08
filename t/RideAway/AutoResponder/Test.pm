#!/usr/bin/env perl
package RideAway::AutoResponder::Test;
use 5.006;
use strict;
use warnings;
use base qw(Test::Class);
use Test::More;
use Test::Deep;
use Test::Exception;
use RideAway::AutoResponder;
use Test::MockObject;
use Test::MockObject::Extends;
use DateTime;
use Time::HiRes qw(usleep sleep);
use File::Slurp;
use FindBin qw($Bin);
use Log::Log4perl;
my $logger = Log::Log4perl::get_logger();

sub rideaway_test_startup : Test(startup) {
    my $self = shift;

    # Not sure if we even get this html body,but leaving it for now
    $self->{sample_email_html_body}      = read_file( "$Bin/../t/data/sample_ride_html.txt", binmode => ':utf8' );
    $self->{sample_email_retour_qp_body} = read_file( "$Bin/../t/data/sample_retour_ride_qp.txt", binmode => ':utf8' );
    $self->{sample_email_single_qp_body} = read_file( "$Bin/../t/data/sample_single_ride_qp.txt", binmode => ':utf8' );
    $self->{sample_email_single_v2_qp_body} = read_file( "$Bin/../t/data/sample_sample_ride_formatv2_qp.txt", binmode => ':utf8' );
    $self->{sample_afwijzing}            = read_file( "$Bin/../t/data/sample_afwijzing.html", binmode => ':utf8' );
    $self->{sample_locked_for_others}    = read_file( "$Bin/../t/data/sample_locked_for_others.html", binmode => ':utf8' );
    $self->{sample_locked_for_me}        = read_file( "$Bin/../t/data/sample_locked_for_me.html", binmode => ':utf8' );
    $self->{bekijk_reserve_qp_body}      = read_file( "$Bin/../t/data/sample_bekijk_reserve_qp.txt", binmode => ':utf8' );

}

sub rideaway_test_setup : Test(setup) {
    my $self = shift;

    my $rd  = RideAway::AutoResponder->new(config_file => "$Bin/../t/data/config.test.ini");
    $rd->is_test_mode(1);
    $rd = Test::MockObject::Extends->new($rd);


    my $imap = $self->_mock_imap();
    $rd->imap($imap);
    $self->{rd} = $rd;

    my $schema = $rd->schema;
    $self->{schema} = $schema;
    $schema->txn_begin; # <-- low level
}

sub teardown : Test(teardown) {
    my $schema = shift->{schema};
    diag("Roll Back");
    $schema->txn_rollback;
    #schema->txn_commit;
}

sub test_send_message :Test(no_plan) {
    my $self = shift;

    my $rd = $self->{rd};

    my $teleg = Test::MockObject->new;
    $teleg->set_isa('WWW::Telegram::BotAPI');
    my @args;
    $teleg->mock('sendMessage', sub { shift; push @args, shift } );
    $rd->telegram($teleg);
    my $telegram_msg = 'Hi there telegram';

    $rd->send_message($telegram_msg);
    cmp_deeply($args[0],
        {
            chat_id => $rd->telegram_chat_id,
            text    => $telegram_msg,
        }
    ), 'message passed correctly to teleg'
         or diag explain @args;

    $teleg->mock('sendMessage', sub { die 'I AM DYING FOR A TEST, DONT WORRY'; } );
    my $tm = Test::MockObject->new;
    $tm->set_isa('Net::SMS::TextmagicRest');
    $tm->mock('send', sub { 'Sent via SMS' } );
    @args = ();
    $tm->mock('send', sub { shift; push @args, @_ } );
    $rd->text_magic($tm);
    my $msg = 'telegram will die and text magix will send this as sms';

    $rd->send_message($msg);
    cmp_deeply(\@args,
        [
            text   => $msg,
            phones => ['+' . $rd->phone],
        ]
    ), 'message passed correctly to text magix'
         or diag explain @args;


}


# proves that the ini file is being read correctly
sub test_config_from_ini : Test(no_plan) {
    my $self = shift;

    my $rd = $self->{rd};
    is($rd->imap_server,     'my.test.server.address', 'test server');
    is($rd->imap_password,   'very secret', 'test passwd');
    is($rd->imap_username,   'willy wonka', 'username');
    is($rd->imap_debug_file, 'logs/imap.test.log', 'debug file');
    is($rd->sms_username,    'bob dylan', 'sms username');
    is($rd->sms_token,       'token', 'sms token');
    is($rd->phone,           '44741234566', 'phone');
    is($rd->telegram_chat_id, '-54354354343', 'telegram chat id');
    is($rd->telegram_token,   '34243243242342309432432', 'telegram token');
}

sub test_poll_emails : Test(3) {
    my $self = shift;

    my $rd   = $self->{rd};

    isa_ok( $rd,       'RideAway::AutoResponder' );
    isa_ok( $rd->imap, 'Mail::IMAPClient' );

    $rd->imap->mock('idle_data', sub { ['* 17 EXISTS'] });

    my $ride = $self->_make_ride;
    $ride->mock('apply', sub { my $status = Test::MockObject->new;
                                $status->set_always('code', 'applied!');
                                return $status;
                             } );

    $rd->mock('fetch_rides', sub { ( $ride ) } );

    my $start_time = DateTime->now(time_zone => "Europe/London");

    my $requested_duration = $rd->poll_seconds; # in seconds

    $rd->run;

    my $now_time  = DateTime->now(time_zone => "Europe/London");

    my $duration = $now_time - $start_time;
    my $actual_hunting_time = $duration->in_units('seconds');

    my $leeway = 60; #seconds extra time, just in case.

    my $is_in_range = sub {
        my $num_to_check = shift;
        if ( $num_to_check >= $requested_duration
                &&
              $num_to_check < ( $requested_duration + $leeway )
           )
        {
            return 1;
        }

        return 0;
    };

    is($is_in_range->($actual_hunting_time), 1, 'Hunt was ended within reasonable time') or diag $actual_hunting_time;
}


sub test_get_message_ids : Test(1) {
    my $self = shift;

    my $rd   = $self->{rd};
    my $idle_data = [
                        '* 17 EXISTS',
                        '* 18 EXISTS',
                    ];

    cmp_deeply( [$rd->get_message_ids($idle_data)],
                [ 17, 18 ],
                'Got the expected message_ids' );
}

sub test_fetch_rides : Test(3) {
    my $self = shift;

    my $rd    = $self->{rd};
    $rd->set_true('is_a_ride_email');

    $rd->mock(
        'make_ride',
        sub {
            my $ride = Test::MockObject->new;
            $ride->set_isa('RideAway::Schema::Result::Ride');
            $ride->mock('id', sub { 1 } );
            return $ride;
        }
    );

    my $imap = $self->_mock_imap();
    $imap
        ->mock('Strip_cr', sub { } )
        ->mock('body_string', sub { $self->{sample_email_single_qp_body} } );

    $rd->imap($imap);

    throws_ok { $rd->fetch_rides()
    } qr/no array ref of nums/,
    'error ok';

    my @rides;
    lives_ok { @rides = $rd->fetch_rides([17]) } 'lives';

    my ($ride) =  @rides;
    isa_ok($ride, 'RideAway::Schema::Result::Ride');
}


sub test_is_a_ride_email : Test(no_plan) {
    my $self = shift;

    my $rd = $self->{rd};

    throws_ok {
        $rd->is_a_ride_email()
    } qr/havent received any email body string/,
    'error ok';

    is($rd->is_a_ride_email('Nonsense')                           , undef, 'correctly dismissed Nonsense body');
    is($rd->is_a_ride_email($self->{sample_email_single_qp_body}) , 1, 'correctly accepted single trip');
    is($rd->is_a_ride_email($self->{bekijk_reserve_qp_body})      , undef, 'correctly rejected bekijk reservering');
}


sub test_make_ride : Test(no_plan) {
    my $self = shift;

    my $rd = $self->{rd};

    throws_ok {
        $rd->make_ride()
    }
    qr/havent received any email body string/, 'error ok';

    my $msgid = 123;
    my $struct = $rd->_parse_html( $self->{sample_email_html_body} );

    cmp_deeply(
        $struct,
        {
            location_from => 'Camping Het Amsterdamse Bos, Kleine Noorddijk, Amstelveen, Niederlande',
            location_to   => 'AMS: Amsterdam Airport Schiphol&nbsp;',
            price         => '29',
            ride_dt       =>
                all(
                    isa('DateTime'),
                    methods(
                        day   => 29,
                        month => 4,
                        year  => 2018,
                    ),
                ),
            url        => 'https://www.example.com/partner/?entity=4917&token=cb2552e7ddade0383230dcba0881f728&url=booking|308401|81b992877bff192c09d5eb55bfb2cf9b'
        }
        , 'HTML parse ok'

    );

    my $ride = $rd->make_ride( $self->{sample_email_retour_qp_body}, $msgid );
    is( ref($ride), 'RideAway::Schema::Result::Ride' );

    cmp_deeply(
        $ride,
        methods(
            location_from => 'CC Rotterdam, Netherlands',
            location_to   => 'RTM: Rotterdam The Hague Airport&nbsp;',
            price         => '75',
            ride_dt       =>
                all(
                    isa('DateTime'),
                    methods(
                        day   => 13,
                        month => 4,
                        year  => 2018,
                    ),
                ),
            num_people => -1,
            msgid      => $msgid,
            sms_sent   => 0,
            created_dt => isa('DateTime'),
            status     => methods( code => 'new' ),
            url        => 'https://www.example.com/partner/?entity=4917&token=abcdefg7ddade0383230dcba0881f728&url=booking|309271|3870734cc8a86bfc30a9c2919cad335f'
        )
        , 'NON HTML parse retour reis ok'
    );

    $ride = $rd->make_ride( $self->{sample_email_single_qp_body}, $msgid );
    is( ref($ride), 'RideAway::Schema::Result::Ride' );
    cmp_deeply(
        $ride,
        methods(
            location_from => "'t Hotel, Leliegracht, Amsterdam, Netherlands",
            location_to   => 'AMS: Amsterdam Airport Schiphol&nbsp;',
            price         => '38',
            ride_dt       =>
                all(
                    isa('DateTime'),
                    methods(
                        day   => 29,
                        month => 3,
                        year  => 2018,
                    ),
                ),
            num_people => -1,
            msgid      => $msgid,
            sms_sent   => 0,
            created_dt => isa('DateTime'),
            status     => methods( code => 'new' ),
            url        => 'https://www.example.com/partner/?entity=4917&token=111112e7ddade0383230dcba0881f728&url=booking|309275|c94bc1270c72c2073f9b01ebcc77c825'
        )
        , 'NON HTML parse single reis ok'
    );

    $ride = $rd->make_ride( $self->{sample_email_single_v2_qp_body}, $msgid );
    is( ref($ride), 'RideAway::Schema::Result::Ride' );
    cmp_deeply(
        $ride,
        methods(
            location_from => "RTM: Rotterdam The Hague Airport",
            location_to   => 'Johanneshoevelaan ,  XB, Wassenaar, Nederland&nbsp;',
            price         => '42',
            ride_dt       =>
                all(
                    isa('DateTime'),
                    methods(
                        day   => 3,
                        month => 4,
                        year  => 2018,
                    ),
                ),
            num_people => -1,
            msgid      => $msgid,
            sms_sent   => 0,
            created_dt => isa('DateTime'),
            status     => methods( code => 'new' ),
            url        => 'https://www.example.com/partner/?entity=4917&token=111111173231356d60ca67e0e01ba375&url=booking|311868|4267ec8a908e4800a24c179949db05b9'
        )
        , 'NON HTML parse single reis ok'
    );
}


sub test_applying : Test(no_plan) {
    my $self = shift;

    my $rd = $self->{rd};
    my $ride;
    SKIP: {
        eval { $ride = $rd->make_ride( $self->{sample_email_single_qp_body} ) };
        skip "ride couldn't be made: $@", 2 if $@;

        $ride = Test::MockObject::Extends->new($ride);

        my $status_rs = $self->{schema}->resultset('Status');

        my $status_unknown = $status_rs->search({ code => 'unknown'})->single;
        my $status_new     = $status_rs->search({ code => 'new'})->single;
        $ride->update({status => $status_unknown });

        # shouldn't apply unless the ride is new or locked for others:
        is( $ride->apply, undef, 'returns undef unless the Ride is "new" or "locked_for_others" statuses' );


        subtest 'new msg, but the response rejects me because someone else got it' => sub {
            # should apply
            $ride->update({status => $status_new });
            $ride->mock('_get_decoded_content', sub { $self->{sample_afwijzing} } );

            $ride->apply();

            is($ride->status->code, 'rejected', 'decoded content indicated someone else has the ride');
        };

        subtest 'new msg, but locked for someone else' => sub {
            # should apply
            $ride->update({status => $status_new });
            $ride->mock('_get_decoded_content', sub { $self->{sample_locked_for_others} } );

            $ride->apply();

            is($ride->status->code, 'locked_for_others', 'decoded content indicated ride is locked for others');
        };

        subtest 'new msg, but locked for me else' => sub {
            # should apply
            $ride->update({status => $status_new });
            $ride->mock('_get_decoded_content', sub { $self->{sample_locked_for_me} } );

            $ride->apply();

            is($ride->status->code, 'locked_for_me', 'decoded content indicated ride is locked for me');
        };
    };
}

sub test_database_storage : Test(no_plan) {
    my $self = shift;

    my $rd = $self->{rd};

    my $date = DateTime->now(time_zone => "Europe/London");
    $rd->mock('_parse_date', sub { $date } );
    my $ride;
    SKIP: {
        eval { $ride = $rd->make_ride( $self->{sample_email_single_qp_body} ) };
        skip "ride couldn't be made: $@", 2 if $@;

        my $rs;
        lives_ok { $rs = $rd->schema->resultset('Ride') } 'lives';
        is( $rs->count, 1, 'found the row' );
    };

    $ride = $rd->make_ride( $self->{sample_email_single_qp_body} );
    is( $ride, undef, 'should be allowed to make the same ride twice');
}

sub test__get_decoded_content : Test(no_plan) {
    my $self = shift;
    my $ride = $self->_make_ride;

    my $decoded;
    lives_ok { $decoded = $ride->_get_decoded_content } '_get_decoded_content lives';

    # Default URL in $ride is https://example.com, so we expect some string
    # like this in the response:
    like(
        $decoded,
        qr/This domain is established to be used.+/ms,
        'decoded content is like example.com (this test requires internet conn.)'
    );
}

sub _mock_imap {
    my ($self, $args) = @_;

    my $mock_imap = Test::MockObject->new;
    $mock_imap->set_isa('Mail::IMAPClient');

    $mock_imap
    ->set_true('select')
    ->set_always('idle', 3)
    ->mock('idle_data', sub { [] })
    ->set_true('done')
    ->set_true('close')
    ->set_true('disconnect');

    return $mock_imap;
}

sub _make_ride {
    my $self = shift;

    my $rs = $self->{schema}->resultset('Ride');
    my $ride = $rs->create(
          {
            created_dt => DateTime->now(time_zone => "Europe/London"),
            ride_dt    => DateTime->now(time_zone => "Europe/London")->add( months => int(rand(10)), days => int(rand(1000)) ),
            location_from => 'schiphol',
            location_to => 'amsterdam',
            num_people => 2,
            url => 'https://www.example.com',
            msgid => 12345,
            price => 10.5,
            sms_sent => 0,
            status_id => $self->{schema}->resultset('Status')->search( { code => 'new' } )->single->id,
          } );
    return Test::MockObject::Extends->new($ride);

}
1;
