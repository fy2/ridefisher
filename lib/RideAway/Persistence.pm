package RideAway::Persistence;

use Moose;
use MooseX::Configuration;

use namespace::autoclean;
use RideAway::Schema;
use Log::Log4perl;
use WWW::Telegram::BotAPI;

my $logger = Log::Log4perl::get_logger();

has dsn => (
    is            => 'ro',
    isa           => 'Any',
    section       => 'db',
    key           => 'dsn',
);

has persistent_mode_is_on => (
    is            => 'ro',
    isa           => 'Any',
    section       => 'ride',
    key           => 'persist',
);

has max_retries => (
    is            => 'rw',
    isa           => 'Num',
    default        => 15,
    section       => 'ride',
    key           => 'max_retries',
);


has max_run_time => (
    is            => 'rw',
    isa           => 'Num',
    default       =>  60,
);

has minimum_wait_time => (
    is            => 'rw',
    isa           => 'Num',
    default       =>  20,
);

has telegram_chat_id => (
    is            => 'ro',
    isa           => 'Str',
    section       => 'telegram',
    key           => 'chat_id',
);

has telegram => (
    is            => 'rw',
    isa           => 'WWW::Telegram::BotAPI',
    lazy          => '1',
    builder       => '_build_telegram',
);

sub _build_telegram {
    my $self = shift;

    my $api = WWW::Telegram::BotAPI->new (
        token => $self->telegram_token,
    );
    return $api;
}

has schema => (
    is            => 'rw',
    isa           => 'Any',
    lazy          => 1,
    builder       => '_build_schema',
);

sub _build_schema {
    my $self = shift;

    RideAway::Schema->connect(
         $self->dsn,
         undef,
         undef,
         { on_connect_do => ['PRAGMA foreign_keys = ON',
                             'PRAGMA encoding="UTF-8"',
                             'PRAGMA quick_check'
                            ]
        }
    );
}

sub run {
    my $self = shift;


    my $seconds_to_try = $self->max_run_time;
    my $persistent_mode_is_on = $self->persistent_mode_is_on;
    $logger->debug(sprintf 'Enter run max_run_time [%d], max_retry [%d], persitency [%d]', $seconds_to_try, $self->max_retries, $persistent_mode_is_on);
    return unless $persistent_mode_is_on;

    RUN:
    while( $seconds_to_try > 0) {
        my @rides = $self->_get_rides; # reapplicable rides
        unless (@rides) {
            $logger->debug("No rides waiting, exiting run");
            last RUN unless @rides;
        }

        foreach my $ride (@rides) {
            my $retries = $ride->retries;
            my $retries_to_go = $self->max_retries - $retries;
            $self->send_telegram(
                sprintf(
                    'Activated Persistence on Ride: [%d], [%s]. Re-applying! [%d] retries to go on this ride.',
                    $ride->id,
                    substr( $ride->location_from, 0, 50 ),
                    $retries_to_go,
            ));

            my $status = $self->apply_to_ride($ride);
            $ride->update({retries => $retries + 1});
            my $wait = $self->_wait_between_ride_clicks;
            #            $logger->debug("going to wait $wait secs until processing next reapplicable ride!");
            $self->_sleep_ride($wait);
            $seconds_to_try -= $wait;
        }

        my $wait_retry = $self->_wait_retry;
        $self->send_telegram(sprintf 'Next update in [%d] seconds', $wait_retry);
        #        $logger->debug("going to wait $wait_retry until next round of batch process!");
        $self->_sleep_retry($wait_retry);
        $seconds_to_try -= $wait_retry;
    }
}

sub _sleep_ride {
    my ($self, $how_many_secs) = @_;
    sleep($how_many_secs);
}

sub _sleep_retry {
    my ($self, $how_many_secs) = @_;
    sleep($how_many_secs);
}


sub _wait_between_ride_clicks {
    int(rand(5)) + 3;
}

sub _wait_retry {
    my $self = shift;
    int(rand(30)) + 5;
}

sub apply_to_ride {
    my ($self, $ride) = @_;

    my $status = $ride->apply;
    if ($status->code eq 'locked_for_me') {
        $self->send_telegram(
            sprintf(
                "**BINGO LOCKED ON PERSISTENCE** Date:[%s], Price:[%s], Van: [%s...], Naar: [%s...], ID: [%s], Link [%s]",
                $ride->ride_dt,
                $ride->price,
                substr( $ride->location_from, 0, 50 ),
                substr( $ride->location_to, 0, 50 ),
                $ride->id,
                $ride->url
        ));
    }
    else {
        $self->send_telegram( sprintf "Giving up on ride id: [%d], Van: [%s...] because I have received status: [%s]",
                                  $ride->id,
                                  substr( $ride->location_from, 0, 50 ),
                                  $status->code,

                            );
    }
    return $status;
}

sub _get_rides {
    my $self = shift;

    my $schema = $self->schema;
    my $ride_rs = $self->schema->resultset('Ride');
    my @rides = $ride_rs->reapplicable_rides->search(
                    { retries => { '<' => $self->max_retries } }
                );
    return @rides;
}

=head2 send_telegram

=cut

sub send_telegram {
    my ($self, $message) = @_;
    return if $self->is_test_mode;
    eval {
        $self->telegram->sendMessage ({
            chat_id => $self->telegram_chat_id,
            text    => $message,
        });
    };
    if (my $err = $@) {
        $logger->error("couldnt send via telegram [$err].");
    }
}

__PACKAGE__->meta->make_immutable;
