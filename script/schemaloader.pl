#!/usr/bin/env perl

use Modern::Perl;

use DBIx::RunSQL;
use DBIx::Class::Schema::Loader 'make_schema_at';

my $test_dbh = DBIx::RunSQL->create(
    dsn     => 'dbi:SQLite:dbname=:memory:',
    sql     => 'db/schema.sql',
    force   => 1,
    verbose => 1,
);

make_schema_at( 'RideAway::Schema',
    {
        components => [ 'InflateColumn::DateTime' ],
        debug => 1,
        dump_directory => './lib' ,
    },
    [ sub { $test_dbh }, {} ]
);
