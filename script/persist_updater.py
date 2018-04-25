#!/usr/bin/env python

import sqlite3

conn = sqlite3.connect('/home/feyruz/sandbox/RideAway-AutoResponder/rideaway.db')

# Do this instead
ride_id = (13,)
conn.execute('UPDATE ride set should_persist = 1 WHERE id=?', ride_id)

# Save (commit) the changes
conn.commit()

# We can also close the connection if we are done with it.
# Just be sure any changes have been committed or they will be lost.
conn.close()
