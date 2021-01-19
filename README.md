# The VNDB.org Source Code

## Quick and dirty setup using Docker

Setup:

```
  docker build -t vndb .
```

Run (will run on the foreground):

```
  docker run -ti --name vndb -p 3000:3000 -v "`pwd`":/var/www --rm vndb
```

If you need another terminal into the container while it's running:

```
  docker exec -ti vndb su -l devuser  # development shell (files are at /var/www)
  docker exec -ti vndb psql -U vndb   # postgres shell
```

To start Multi, the optional application server:

```
  docker exec -ti vndb su -l devuser -c 'make -C /var/www multi-restart'
```

It will run in the background for as long as the container is alive. Logs are
written to `data/log/multi.log`.

The PostgreSQL database will be stored in `data/docker-pg/` and the uploaded
files in `static/{ch,cv,sf,st}`. If you want to restart with a clean slate, you
can stop the container and run:

```
  # Might want to make a backup of these dirs first if you have any interesting data.
  rm -rf data/docker-pg static/{ch,cv,sf,st}
```


## Requirements (when not using Docker)

Global requirements:

- Linux, or an OS that resembles Linux. Chances are VNDB won't run on Windows.
- A standard C build system (make/gcc/etc)
- PostgreSQL 10+ (including development files)
- Perl 5.26+
- Elm 0.19.1
- Graphviz
- ImageMagick
- sassc

**Perl modules** (core modules are not listed):

General:
- AnyEvent
- Crypt::ScryptKDF
- Crypt::URandom
- DBD::Pg
- DBI
- JSON::XS
- PerlIO::gzip

util/vndb.pl (the web backend):
- Algorithm::Diff::XS
- SQL::Interp
- Text::MultiMarkdown
- TUWF
- HTTP::Server::Simple

util/multi.pl (application server, optional):
- AnyEvent::HTTP
- AnyEvent::IRC
- AnyEvent::Pg


## Manual setup

- Make sure all the required dependencies (see above) are installed. Hint: See
  the Docker file for Alpine Linux commands, other distributions will be similar.
  For non-root setup, check out cpanminus & local::lib.
- Run the build system:

```
  make
```

- Setup a PostgreSQL server and make sure you can login with some admin user
- Build the *vndbfuncs* PostgreSQL library:

```
  make -C sql/c
```

- Copy `sql/c/vndbfuncs.so` to the appropriate directory (either run
  `sudo make -C sql/c install` or see `pg_config --pkglibdir` or
  `SHOW dynamic_library_path`)
- Initialize the VNDB database (assuming 'postgres' is a superuser):

```
  # Create the database & roles
  psql -U postgres -f sql/superuser_init.sql
  psql -U postgres vndb -f sql/vndbid.sql

  # Set a password for each database role:
  echo "ALTER ROLE vndb       LOGIN PASSWORD 'pwd1'" | psql -U postgres
  echo "ALTER ROLE vndb_site  LOGIN PASSWORD 'pwd2'" | psql -U postgres
  echo "ALTER ROLE vndb_multi LOGIN PASSWORD 'pwd3'" | psql -U postgres

  # OPTION 1: Create an empty database:
  psql -U vndb -f sql/all.sql

  # OPTION 2: Import the development database (https://vndb.org/d8#3):
  curl -L https://dl.vndb.org/dump/vndb-dev-latest.tar.gz | tar -xzf-
  psql -U vndb -f dump.sql
  rm dump.sql
```

- Update `data/conf.pl` with the proper credentials for *vndb_site* and
  *vndb_multi*.
- Now simply run:

```
  util/vndb-dev-server.pl
```

- (Optional) To start Multi, the application server:

```
  make multi-restart
```


# License

GNU AGPL, see COPYING file for details.
