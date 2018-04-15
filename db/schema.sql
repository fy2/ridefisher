DROP TABLE IF EXISTS ride;
DROP TABLE IF EXISTS status;
DROP TABLE IF EXISTS response;
DROP INDEX IF EXISTS code_idx;
DROP INDEX IF EXISTS status_id_idx;
DROP INDEX IF EXISTS ride_dt_idx;

CREATE TABLE status (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    code TEXT NOT NULL
);
CREATE UNIQUE INDEX code_idx ON status(code);


INSERT INTO status (code) values ('new');
INSERT INTO status (code) values ('rejected');
INSERT INTO status (code) values ('locked_for_me');
INSERT INTO status (code) values ('locked_for_others');
INSERT INTO status (code) values ('accepted');
INSERT INTO status (code) values ('unknown');
INSERT INTO status (code) values ('failed');

CREATE TABLE ride (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    ride_dt DATETIME NOT NULL,
    created_dt DATETIME NOT NULL,
    location_from TEXT,
    location_to TEXT,
    msgid INT,
    price FLOAT,
    raw_email TEXT,
    num_people INT,
    url TEXT,
    sms_sent INT DEFAULT 0,
    status_id INTEGER NOT NULL,
    FOREIGN KEY(status_id) REFERENCES status(id)
);
CREATE INDEX status_id_idx ON ride(status_id);
CREATE UNIQUE INDEX ride_dt_idx ON ride(ride_dt, location_from);

CREATE TABLE response (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    created_dt DATETIME NOT NULL,
    ride_id INTEGER NOT NULL,
    decoded_content NOT NULL,
    FOREIGN KEY(ride_id) REFERENCES ride(id)
);

-- Patch 001
ALTER TABLE ride ADD COLUMN should_persist BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE ride ADD COLUMN retries INTEGER NOT NULL DEFAULT 0;
