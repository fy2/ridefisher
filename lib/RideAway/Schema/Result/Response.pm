use utf8;
package RideAway::Schema::Result::Response;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

RideAway::Schema::Result::Response

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

=head1 TABLE: C<response>

=cut

__PACKAGE__->table("response");

=head1 ACCESSORS

=head2 id

  data_type: 'integer'
  is_auto_increment: 1
  is_nullable: 0

=head2 created_dt

  data_type: 'datetime'
  is_nullable: 0

=head2 ride_id

  data_type: 'integer'
  is_foreign_key: 1
  is_nullable: 0

=head2 decoded_content

  data_type: (empty string)
  is_nullable: 0

=cut

__PACKAGE__->add_columns(
  "id",
  { data_type => "integer", is_auto_increment => 1, is_nullable => 0 },
  "created_dt",
  { data_type => "datetime", is_nullable => 0 },
  "ride_id",
  { data_type => "integer", is_foreign_key => 1, is_nullable => 0 },
  "decoded_content",
  { data_type => "", is_nullable => 0 },
);

=head1 PRIMARY KEY

=over 4

=item * L</id>

=back

=cut

__PACKAGE__->set_primary_key("id");

=head1 RELATIONS

=head2 ride

Type: belongs_to

Related object: L<RideAway::Schema::Result::Ride>

=cut

__PACKAGE__->belongs_to(
  "ride",
  "RideAway::Schema::Result::Ride",
  { id => "ride_id" },
  { is_deferrable => 0, on_delete => "NO ACTION", on_update => "NO ACTION" },
);


# Created by DBIx::Class::Schema::Loader v0.07049 @ 2018-03-25 23:03:53
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:rvyZs8qe8uTdi8VqW8zLRg


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
