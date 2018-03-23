use utf8;
package RideAway::Schema::Result::Status;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

RideAway::Schema::Result::Status

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

=head1 TABLE: C<status>

=cut

__PACKAGE__->table("status");

=head1 ACCESSORS

=head2 id

  data_type: 'integer'
  is_auto_increment: 1
  is_nullable: 0

=head2 code

  data_type: 'text'
  is_nullable: 0

=cut

__PACKAGE__->add_columns(
  "id",
  { data_type => "integer", is_auto_increment => 1, is_nullable => 0 },
  "code",
  { data_type => "text", is_nullable => 0 },
);

=head1 PRIMARY KEY

=over 4

=item * L</id>

=back

=cut

__PACKAGE__->set_primary_key("id");

=head1 UNIQUE CONSTRAINTS

=head2 C<code_unique>

=over 4

=item * L</code>

=back

=cut

__PACKAGE__->add_unique_constraint("code_unique", ["code"]);

=head1 RELATIONS

=head2 rides

Type: has_many

Related object: L<RideAway::Schema::Result::Ride>

=cut

__PACKAGE__->has_many(
  "rides",
  "RideAway::Schema::Result::Ride",
  { "foreign.status_id" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);


# Created by DBIx::Class::Schema::Loader v0.07049 @ 2018-03-25 20:30:30
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:fF/9sYGqs/+hZIBF0rQ4Rw


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
