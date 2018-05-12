package RideAway::AutoResponder;


use Moose;
use MooseX::Configuration;

use Mail::IMAPClient;
use DateTime;
use Time::HiRes qw(sleep);
use namespace::autoclean;
use MIME::QuotedPrint;
use RideAway::Schema;
use Log::Log4perl;
use Net::SMS::TextmagicRest;
use WWW::Telegram::BotAPI;
use File::Touch;

my $logger = Log::Log4perl::get_logger();

has imap_server => (
    is            => 'ro',
    isa           => 'Str',
    section       => 'email',
    key           => 'server',
);

has dsn => (
    is            => 'ro',
    isa           => 'Any',
    section       => 'db',
    key           => 'dsn',
);

has telegram_token => (
    is            => 'ro',
    isa           => 'Any',
    section       => 'telegram',
    key           => 'token',
);

has persistent_mode_is_on => (
    is            => 'ro',
    isa           => 'Any',
    section       => 'ride',
    key           => 'persist',
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

has text_magic => (
    is            => 'rw',
    isa           => 'Net::SMS::TextmagicRest',
    lazy          => '1',
    builder       => '_build_text_magic',
);

sub _build_text_magic {
    my $self = shift;
    my $tm = Net::SMS::TextmagicRest->new(
        username => $self->sms_username,
        token    => $self->sms_token,
    );
    return $tm;
}

sub _build_telegram {
    my $self = shift;

    my $api = WWW::Telegram::BotAPI->new (
        token => $self->telegram_token,
    );
    return $api;
}

has schema => (
    is            => 'ro',
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

has imap_password => (
    is            => 'ro',
    isa           => 'Str',
    section       => 'email',
    key           => 'password',
);

has imap_username => (
    is            => 'ro',
    isa           => 'Str',
    section       => 'email',
    key           => 'username',
);

has imap_debug_file => (
    is            => 'ro',
    isa           => 'Str',
    section       => 'email',
    key           => 'debug_file',
);

has sms_username => (
    is            => 'ro',
    isa           => 'Str',
    section       => 'sms',
    key           => 'username',
);

has sms_token => (
    is            => 'ro',
    isa           => 'Str',
    section       => 'sms',
    key           => 'token',
);

has phone => (
    is            => 'ro',
    isa           => 'Num',
    section       => 'sms',
    key           => 'phone',
);

has 'imap' => (
    is => 'rw',
    isa => 'Mail::IMAPClient',
    builder => '_build_imap',
    lazy => 1,
);

sub _build_imap {
    my $self = shift;

    my $client;
    eval {
        $client = Mail::IMAPClient->new(
            Server    => $self->imap_server,
            User      => $self->imap_username,
            Password  => $self->imap_password,
            Ssl       => 1,
            Debug     => 1,
            Keepalive => 1,
            Debug_fh  => IO::File->new(">>" . $self->imap_debug_file)
                || die "Can't open imap debugging output file for write: $!\n"
        ) or die $@;
    };
    if (my $err = $@) { die $err; }
    return $client;
}

has poll_seconds => (
    is            => 'ro',
    isa           => 'Num',
    section       => 'timer',
    key           => 'poll_seconds',
    documentation => 'seconds to poll emails, (idle time)'
);

has is_test_mode => (
    is            => 'rw',
    isa           => 'Bool',
    default => 0,
);

=head1 METHODS

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

=head2 send_message

=cut

sub send_message {
    my ($self, $message) = @_;
    eval {
        $self->telegram->sendMessage ({
            chat_id => $self->telegram_chat_id,
            text    => $message,
        });
    };
    if (my $err = $@) {
        $logger->error("couldnt send via telegram [$err]. Trying sms:");
        $self->text_magic->send(
            text    =>  $message,
            phones  => ['+'. $self->phone ],
        );
    }
}

=head2 run

=cut

sub run {
    my ($self) = @_;

    $logger->debug('Enter run');
    my $imap = $self->imap;

    $imap->select("Inbox") or $logger->logdie("Could not select Inbox: $@");
    my $tag;
    unless ( $tag = $imap->idle ) {
        $logger->error("couldnt get the tag $@");
        $self->gracefully_end();
        exit;
    }
    my $seconds_to_go =  $self->poll_seconds;
    $logger->debug("Gonna poll for $seconds_to_go seconds!");

    my $retry = 3;

    POLLING:
    while($seconds_to_go > 0) {

        my $idlemsgs;
        unless ($idlemsgs = $imap->idle_data ) {
            $logger->error("idle_data failed:[$@]");
            $self->gracefully_end();
            last POLLING;
        }

        if ($idlemsgs && @{$idlemsgs} > 0 ) {
            unless ( $imap->done($tag) ) {
                $logger->error("Error from done: $@");
                last POLLING;
            }
            my @msgids = $self->get_message_ids($idlemsgs);
            my @rides  = $self->fetch_rides(\@msgids);
            RIDE:
            foreach my $ride ( @rides ) {
                if ( $self->ride_passes_criteria($ride) ) {
                    $self->apply_to_ride($ride);
                    # some leeway:
                    $seconds_to_go -= 5 unless $self->is_test_mode;
                }
                else {
                    eval {
                        $self->send_telegram(
                            sprintf "Ignoring: Date:[%s], Price:[%s], Van: [%s...], Naar: [%s...], ID: [%s], Link [%s]",
                            $ride->ride_dt,
                            $ride->price,
                            substr( $ride->location_from, 0, 50 ),
                            substr( $ride->location_to, 0, 50 ),
                            $ride->id,
                            $ride->url
                        );
                    };
                    $ride->update( { should_persist => 1 } )
                        if  $ride->status->code eq 'locked_for_others'
                            && $self->persistent_mode_is_on;
                }
            }
            unless ( $tag = $imap->idle ) {
                $logger->error("couldnt get the tag: $@");
                $self->_disconnect;
                exit 1;
            }
        }

        $logger->debug(sprintf "Polling %.2f", $seconds_to_go) if int(rand(10000) >= 9990);
        sleep(0.01);
        $seconds_to_go -= 0.01;
    }
    $self->_disconnect($tag);
}


sub apply_to_ride {
    my ($self, $ride) = @_;

    my $status = $ride->apply;
    if ($status->code eq 'locked_for_me') {
        $self->send_telegram(
            sprintf "**BINGO A RIDE IS LOCKED** Date:[%s], Price:[%s], Van: [%s...], Naar: [%s...], ID: [%s], Link [%s]",
            $ride->ride_dt,
            $ride->price,
            substr( $ride->location_from, 0, 50 ),
            substr( $ride->location_to, 0, 50 ),
            $ride->id,
            $ride->url );
    }
    elsif ($status->code eq 'locked_for_others') {
        $self->send_telegram(
                sprintf "SOMEONE-ELSE locked: Date:[%s], Price:[%s], Van: [%s...], Naar: [%s...]. Should I try to snatch it back? If yes, type /p %d",
                $ride->ride_dt,
                $ride->price,
                substr( $ride->location_from, 0, 50 ),
                substr( $ride->location_to, 0, 50 ),
                $ride->id );
    }
    else {
        $self->send_telegram( sprintf "Failed to get: Status: [%s], [%s...]", $status->code, substr( $ride->location_from, 0, 50 ) );
    }
}

sub ride_passes_criteria {
    my ($self, $ride) = @_;

    my $code = $ride->status->code;
    unless ($code eq 'new') {
        $logger->warn("Ride status is not 'new' [$code]");
        return 0;
    }
    my $created_hour = $ride->created_dt->hour;
    if ($created_hour <= 3 ) {
        $logger->info( sprintf "Assuming yavuz is asleep");
        return 0 if $created_hour <= 3;
    }

    my $hour = $ride->ride_dt->hour;
    return 0 if ($hour >= 22 or $hour < 4) and $ride->price <= 150;
    return 1 if $ride->location_to =~ /schiphol/i or $ride->location_from =~ /schiphol/i;
    return 1 if $ride->price >= 150;
    return 0;
}

sub _disconnect {
    my ($self, $tag) = @_;

    my $imap = $self->imap;
    if ($tag) {
        $imap->done($tag) or $logger->error("Error from done: $@");
    }
    $imap->close;
    $imap->disconnect;
}

sub fetch_rides {
    my ( $self, $msgids ) = @_;

    die 'no array ref of nums'
        unless $msgids and ref $msgids eq 'ARRAY';

    $logger->debug( sprintf "enter fetch_rides: msg ids [%s]", join ',', @{$msgids} );

    my $imap = $self->imap;
    my @rides;
    foreach my $msg_id ( @{$msgids} ) {
        my $body_string = $imap->body_string($msg_id)
            or die "Could not body_string: $@\n";

        my $body = $imap->Strip_cr($body_string);

        if ( $self->is_a_ride_email($body) ) {
            my $ride = $self->make_ride( $body, $msg_id );
            if ($ride) {
                push @rides, $ride;
            }
            else {
                $logger->error( "Failed to create the ride object for [$msg_id]" );
            }
        }
        else {
            $logger->info( "Email $msg_id has been analysed but doesn't look like a Ride");
        }
    }
    return @rides;
}

sub is_a_ride_email {
    my ( $self, $email_body ) = @_;

    $logger->logdie('havent received any email body string')
        unless $email_body;

    if ($email_body =~ /Bekijk hier de reservering/ms) {
        $logger->info( "'Bekijk hier de reservering', skipping" );
        return undef;
    }

    return 1 if $email_body =~ /Er is een nieuwe boeking toegevoegd aan de rittenlijst/g;

    return undef;
}

sub _parse_non_html {
    my ($self, $body) = @_;

    $body = decode_qp($body);
    my ($van,
        $naar,
        $prijs,
        $datum,
        $url,
    );
    my ($is_retour_reis) = $body =~ /(Type reis:Retour reis)/ms;
    ($url)          = $body =~ /.+href="(https.+?)">ACCEPTEER.+/ms;
    ($van, $naar)   = $body =~ /\d+Van:\s*(.+?)Naar:\s*(.+?)Aantal/ms;
    ($prijs)        = $body =~ /Totaalprijs:.+?EUR (\d+)/ms;
    ($datum)        = $body =~ /Ophaaldatum.+?:\D*(.+?)(Datum|\s*Type)/ms;
    if (!$datum) {
        ($datum) = $body =~ /Datum en tijd van aankomst:\s*(.+?)(Datum|\s*Type)/ms;
    }
    $url =~ s/(?:\r\n?|\n|>|<)//g if $url;

    return { ride_dt       => $self->_parse_date($datum),
             location_from => $van   || ' ',
             location_to   => $naar  || ' ',
             url           => $url,
             price         => $prijs || -1, };
}

sub _parse_html {
    my ($self, $body) = @_;
    my ($url)                = $body =~ /.*(https:\/\/.+?)">ACCEPTEER/ms;
    my ($van, $naar, $datum) = $body =~ /.*?Boekingsnummer:.+?Van:\s*(.+?)Naar:\s*(.+?)Aantal.+?tijdstip:(.+?)\s*Type vervoer/msi;
    my ($prijs)              = $body =~ /.*?U ontvangt:EUR (\d+)/msi;

    unless ($url) {
        $logger->info("no url could be parsed!");
        return undef;
    }

    if ($url =~ /=3D/) {
        $logger->info("wont do HTML parse as I see =3D in the parsed URL, probably quoted-printable!");
        return undef;
    }


    return { ride_dt       => $self->_parse_date($datum),
             location_from => $van || 'VOID',
             location_to   => $naar || 'VOID',
             url           => $url,
             price         => $prijs || -1, };
}

sub make_ride {
    my ($self, $email_body, $msg_id) = @_;

    $logger->logdie('havent received any email body string')
        unless $email_body;

    my $rs          = $self->schema->resultset('Ride');
    my $status_rs   = $self->schema->resultset('Status');
    my $status_new  = $status_rs->search( { code => 'new' } )->single;
    my $status_fail = $status_rs->search( { code => 'failed' } )->single;

    # first attempt
    my $data = $self->_parse_non_html($email_body);

    if (not $data) {
        $logger->debug("Parsing failed. I will try another parser...");
        $data = $self->_parse_html($email_body);
    }

    my $ride;
    eval {
        $ride = $rs->create(
           {
             %{ $data },
             created_dt => DateTime->now(time_zone => "Europe/London"),
             raw_email  => $email_body,
             num_people => -1,
             sms_sent => 0,
             status => $status_new,
             msgid => $msg_id
            }
        );
    };
    if (my $err = $@) {
        $rs->create(
           {
             created_dt => DateTime->now(time_zone => "Europe/London"),
             ride_dt    => DateTime->now(time_zone => "Europe/London"),
             location_from => 'unknown location' . rand(10),
             raw_email  => $email_body,
             status => $status_fail,
             msgid => $msg_id
            } );

        $logger->error(sprintf "error parsing email body: [%s] [%s]", $err, $email_body)
            unless $self->is_test_mode;
        return undef;
    }
    return $ride;
}

sub _parse_date {
    my ( $self, $dutch_date ) = @_;
    my $dt;
    eval {
        # $dutch_date: expect something like this:
        # '28 Maart 2018 10:30',
        my %month_of = (
                         JANUARI   => 1,
                         FEBRUARI  => 2,
                         MAART     => 3,
                         APRIL     => 4,
                         MEI       => 5,
                         JUNI      => 6,
                         JULI      => 7,
                         AUGUSTUS  => 8,
                         SEPTEMBER => 9,
                         OKTOBER   => 10,
                         NOVEMBER  => 11,
                         DECEMBER  => 12,
                       );

        my ($day, $maand, $year, $time) = split(/\s+/, $dutch_date);
        my $month_nr = $month_of{uc($maand)};
        my ($hour, $minute) = split(':', $time);
        $dt = DateTime->new(
                   year => $year,
                   month => $month_nr,
                   day => $day,
                   hour => $hour,
                   minute => $minute,
               );
    };
    if (my $err = $@) {
        $logger->error("couldnt parse date returning current date");
        $dt = DateTime->now(time_zone => "Europe/London");
    }

    return $dt;
}

sub get_message_ids {
    my ($self, $idlemsgs) = @_;
    $logger->debug(sprintf 'enter get_message_ids, idlemsgs:[%s]', join ',', @{$idlemsgs});
    my @ids;
    foreach my $msg (@{$idlemsgs}) {
        if (my ($id) = $msg =~ /\b([0-9]+) EXISTS/) {
            push @ids, $id;
        }
    }
    return @ids;
}

sub gracefully_end {
    my ($self) = @_;

    $logger->debug('graceful disconnect request is being carried out now');
    my $imap = $self->imap;
    $imap->close;
    $imap->disconnect;
}

__PACKAGE__->meta->make_immutable;
