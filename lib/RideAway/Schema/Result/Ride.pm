use utf8;
package RideAway::Schema::Result::Ride;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

RideAway::Schema::Result::Ride

=cut

use strict;
use warnings;

use base 'DBIx::Class::Core';

=head1 COMPONENTS LOADED

=over 4

=item * L<DBIx::Class::InflateColumn::DateTime>

=back

=cut

__PACKAGE__->load_components("InflateColumn::DateTime");

=head1 TABLE: C<ride>

=cut

__PACKAGE__->table("ride");

=head1 ACCESSORS

=head2 id

  data_type: 'integer'
  is_auto_increment: 1
  is_nullable: 0

=head2 ride_dt

  data_type: 'datetime'
  is_nullable: 0

=head2 created_dt

  data_type: 'datetime'
  is_nullable: 0

=head2 location_from

  data_type: 'text'
  is_nullable: 1

=head2 location_to

  data_type: 'text'
  is_nullable: 1

=head2 msgid

  data_type: 'int'
  is_nullable: 1

=head2 price

  data_type: 'float'
  is_nullable: 1

=head2 raw_email

  data_type: 'text'
  is_nullable: 1

=head2 num_people

  data_type: 'int'
  is_nullable: 1

=head2 url

  data_type: 'text'
  is_nullable: 1

=head2 sms_sent

  data_type: 'int'
  default_value: 0
  is_nullable: 1

=head2 status_id

  data_type: 'integer'
  is_foreign_key: 1
  is_nullable: 0

=cut

__PACKAGE__->add_columns(
  "id",
  { data_type => "integer", is_auto_increment => 1, is_nullable => 0 },
  "ride_dt",
  { data_type => "datetime", is_nullable => 0 },
  "created_dt",
  { data_type => "datetime", is_nullable => 0 },
  "location_from",
  { data_type => "text", is_nullable => 1 },
  "location_to",
  { data_type => "text", is_nullable => 1 },
  "msgid",
  { data_type => "int", is_nullable => 1 },
  "price",
  { data_type => "float", is_nullable => 1 },
  "raw_email",
  { data_type => "text", is_nullable => 1 },
  "num_people",
  { data_type => "int", is_nullable => 1 },
  "url",
  { data_type => "text", is_nullable => 1 },
  "sms_sent",
  { data_type => "int", default_value => 0, is_nullable => 1 },
  "status_id",
  { data_type => "integer", is_foreign_key => 1, is_nullable => 0 },
);

=head1 PRIMARY KEY

=over 4

=item * L</id>

=back

=cut

__PACKAGE__->set_primary_key("id");

=head1 UNIQUE CONSTRAINTS

=head2 C<ride_dt_location_from_unique>

=over 4

=item * L</ride_dt>

=item * L</location_from>

=back

=cut

__PACKAGE__->add_unique_constraint("ride_dt_location_from_unique", ["ride_dt", "location_from"]);

=head1 RELATIONS

=head2 responses

Type: has_many

Related object: L<RideAway::Schema::Result::Response>

=cut

__PACKAGE__->has_many(
  "responses",
  "RideAway::Schema::Result::Response",
  { "foreign.ride_id" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 status

Type: belongs_to

Related object: L<RideAway::Schema::Result::Status>

=cut

__PACKAGE__->belongs_to(
  "status",
  "RideAway::Schema::Result::Status",
  { id => "status_id" },
  { is_deferrable => 0, on_delete => "NO ACTION", on_update => "NO ACTION" },
);


# Created by DBIx::Class::Schema::Loader v0.07049 @ 2018-03-26 12:40:14
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:pwXlts0GjeN9DYU8iuQLbQ

use WWW::Mechanize;
use DateTime;
use Log::Log4perl;
my $logger = Log::Log4perl::get_logger();

=head2 apply

=cut

sub apply {
    my ($self) = @_;

    unless ($self->status->code eq 'new') {
        $logger->warn(sprintf 'ride is not new! [%s, %s], wont apply!',
                        $self->created_dt,
                        $self->id
                    );
        return undef;
    }

    my $decoded_content = $self->_get_decoded_content;
    $self->create_related(
        'responses',
        {
            created_dt => DateTime->now(time_zone => "Europe/London"),
            decoded_content => $decoded_content,
        }
    );

    # RideAway::Schema::Result::Status
    my $status = $self->_analyse($decoded_content);

    return $status;
}

sub _analyse {
    my ($self, $decoded_content) = @_;

    $logger->warn('No decoded content here') unless $decoded_content;
    die 'No content' unless $decoded_content;

    my $status;
    my $status_rs = $self->result_source->schema->resultset('Status');
    if ($decoded_content =~ /Deze boeking is voor u voor \d+? minuten vergrendeld/ms ) {
        $status = $status_rs->search( { code => 'locked_for_me' } )->single;
        $logger->info(sprintf 'Ride is locked for US! - [%s, %s]!', $self->created_dt, $self->id);
    }
    elsif ($decoded_content =~ /boeking is al door iemand anders opgepakt/ms ) {
        $status = $status_rs->search( { code => 'rejected' } )->single;
        $logger->info(sprintf 'Bad luck! Ride is taken by someone else! - [%s, %s]!', $self->created_dt, $self->id);
    }
    elsif ($decoded_content =~ /dit moment vergrendeld door een andere partner./ms ) {
        $status = $status_rs->search( { code => 'locked_for_others' } )->single;
        $logger->info(sprintf 'Arghh. Ride is locked for others - [%s, %s]!', $self->created_dt, $self->id);
    }
    else {
        $status = $status_rs->search( { code => 'unknown' } )->single;
        $logger->info(
            sprintf 'Automated analysis could not reveal the response, rife for manual analysis + test? - [%s, %s]!',
                $self->created_dt,
                $self->id
        );
    }
    $self->update({status => $status });
    return $status;
}

{
    my $mech = WWW::Mechanize->new();
    $mech->agent_alias( 'Mac Safari' );
    sub _get_decoded_content {
        my $self = shift;

        $logger->info(sprintf 'I am APPLYING for this ride - [%s, %s, %s]!', $self->created_dt, $self->id, $self->url );
        my $http_response = $mech->get($self->url);
        my $decoded = $http_response->decoded_content;
       $logger->info(sprintf 'Mechanize HTTP response code: [%s]', $mech->status);
       return $decoded;
    }
}

1;
