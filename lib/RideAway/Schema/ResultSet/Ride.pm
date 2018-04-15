package RideAway::Schema::ResultSet::Ride;

use strict;
use warnings;
use base 'DBIx::Class::ResultSet';


sub reapplicable_rides {
    my $self = shift;
    my $locked_for_others = $self->result_source
                                ->schema
                                ->resultset('Status')
                                ->search( { code => 'locked_for_others' } )
                                ->single;

    $self->search(
        {
            should_persist => 1,
            status_id => $locked_for_others->id
        }
    );
}

1;
