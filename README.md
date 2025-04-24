# The VNDB.org Source Code

## How to contribute

First, a warning: VNDB's code base is slightly unusual when compared
to many other web projects, don't expect to be productive very fast or
solutions to be very obvious. This is by design; VNDB's code is optimized so
that **I** can reason about its reliability and performance while being
productive. Also unlike many other open source software projects, don't expect
me to hold your hand during the process. You're the one who wants to implement
something, so you better be motivated to see it through.

Second, another warning: don't send me a pull request out of the blue and
expect me to merge it. Before you start coding, it's often best to open an
issue to discuss what you want to do and how you plan to implement it. There's
a good chance I already have some ideas on the topic. For larger and more
impactful changes to the database schema or the UI, it's often best to discuss
these on the [discussion board](https://vndb.org/t/db) first so everyone can
chime in with ideas.


## Directory layout

css/
:   CSS files. The files in *css/skins/* are processed with *sassc* and bunbled
    into a single minified CSS file for each skin.

icons/
:   SVG & PNG icons that are merged into a *icons.svg* and *icons.png* sprite
    file. See *icons/README.md* for more details.

js/
:   Front-end code written in Javascript. See *js/README.md* for more details.

lib/
:   This is where all the backend Perl code lives. Notable subdirectories:

    Multi/
    :   Single-process event-based application that runs the old API and
        various background services.

    VNDB/
    :   General utility modules shared between *Multi*, *VNWeb* and some
        tools in *util/*.

    VNWeb/
    :   The VNDB website backend.

sql/
:   PostgreSQL script files to initialize a fresh database schema with all
    assorted tables, functions, indices and attributes. Most of these scripts
    are idempotent and can also be used to load new features into an existing
    database, but see the *util/updates/README.md* for more details.

static/
:   Static assets. *static/s/* contains images used by CSS skins and
    miscellaneous files go into *static/f/*.

t/
:   Test scripts.

util/
:   Command-line utilities for various tasks. See *util/README.md* for details.

With some exceptions, commands and scripts generally assume that they are run
from this top-level source directory.

Directories not in this source repository, but still very important:

gen/ (or `$VNDB_GEN`)
:   This is where all build-time generated files go, such as optimized static
    assets, compiled code and intermediate build artifacts. This is essentially
    the output directory for everything created by the top-level `Makefile`.

    This directory can be freely deleted at any time, it can be recreated with
    `make`.

    This directory can be changed by setting the `VNDB_GEN` environment
    variable. Just be sure to have this variable set and pointed to the same
    directory for every VNDB-related command you run. This variable and the
    full path it points to must not contain any spaces since the Makefile can't
    handle that.

var/ (or `$VNDB_VAR`)
:   The directory for run-time managed files, such as configuration, logs and
    uploaded images. This is also where you can store other site-specific
    files. Additional public assets can be saved into *var/static/*.


## Quick and dirty setup using Docker

Setup:

```
docker build --progress=plain -t vndb .
```

Run (will run on the foreground):

```
docker run -ti --name vndb -p 3000:3000 -v "`pwd`":/vndb --rm vndb
```

If you need another terminal into the container while it's running:

```
docker exec -ti vndb su -l devuser  # development shell (files are at /vndb)
docker exec -ti vndb psql -U vndb   # postgres shell
```

To start Multi, the optional application server:

```
docker exec -ti vndb su -l devuser -c /vndb/util/multi.pl
```

All data is stored in the *docker/* directory. The `$VNDB_GEN` and `$VNDB_VAR`
environment variables inside the container point into this directory and the
PostgreSQL data files are also in there.  If you want to restart with a clean
slate, you can stop the container and delete or rename that directory.


## Requirements (when not using Docker)

Global requirements:

- Linux, or an OS that resembles Linux. Chances are VNDB won't run on Windows.
- A standard C build system (GNU make, gcc/clang, etc)
- PostgreSQL 17+ (including development files)
- Perl 5.36+ (untested, might need 5.40+ instead)
- Graphviz
- libvips
- sassc

**Perl modules** (core modules are not listed):

General:
- AnyEvent
- Crypt::ScryptKDF
- Crypt::URandom
- DBD::Pg
- DBI

util/vndb.pl (the web backend):
- Algorithm::Diff::XS
- FU
- SQL::Interp
- Text::MultiMarkdown

util/multi.pl (application server, optional):
- AnyEvent::HTTP
- AnyEvent::IRC
- AnyEvent::Pg
- JSON::XS


## Manual setup

- Make sure all the required dependencies (see above) are installed. Hint: See
  the Docker file for Alpine Linux commands, other distributions will be similar.
  For non-root setup, check out cpanminus & local::lib.
- Run the build system:

```
make -j8
```

- Initialize your *var/* directory:

```
util/setup-var.sh
```

- Setup a PostgreSQL server and make sure you can login with some admin user
- Build the *vndbfuncs* PostgreSQL library:

```
make -C sql/c
```

- Copy *sql/c/vndbfuncs.so* to the appropriate directory (either run
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
curl -L https://dl.vndb.org/dump/vndb-dev-latest.tar.gz | tar -C var -xzf-
psql -U vndb -f var/dump.sql
rm var/dump.sql
```

- Update *var/conf.pl* with the proper credentials for *vndb_site* and
  *vndb_multi*.
- Now simply run:

```
util/vndb-dev-server.pl
```

- (Optional) To run Multi, the application server:

```
util/multi.pl
```


## Production Deployment

The above instructions are suitable for a development environment. For a
production environment, you'll really want to use FastCGI instead of the shitty
built-in web server. Make sure you have the `FCGI` Perl module installed, then
point a FastCGI-capable web server to *util/vndb.pl*.  Apache (with
`mod_fcgid`) and Lighttpd can be used for this, but my current setup is based
on nginx.  Since nginx does not come with a FastCGI process manager, I use
[spawn-fcgi](https://git.lighttpd.net/lighttpd/spawn-fcgi) in combination with
[multiwatch](https://git.lighttpd.net/lighttpd/multiwatch):

```sh
spawn-fcgi -s /tmp/vndb-fastcgi.sock -u vndb -g vndb -- \
    /usr/bin/multiwatch -f 6 -r 10000 -s TERM /path/to/vndb/util/vndb.pl
```

There is a slow memory "leak" in the Perl backend, so you'll want to reload the
vndb.pl processes once in a while. One way to do that is by setting
`fastcgi_max_requests` in *var/conf.pl*, but it is also safe to reload the
processes by running a `pkill vndb.pl` at any time.

For optimized static assets, run `make prod` as part of your deployment
procedure. This has some additional dependencies, see the Makefile for details.

With the above taken care of, the nginx configuration for a single-domain setup
looks something like this:

```nginx
server {
  ...

  root /path/to/vndb;
  expires 1y;
  gzip_static on;
  gzip_http_version 1.0;
  brotli_static on;
  try_files /var/static$uri /gen/static$uri /static$uri @fcgi;

  location @fcgi {
    expires off;
    include /etc/nginx/fastcgi_params;
    # The following can be used to trick TUWF into thinking we're running on
    # HTTPS, useful if this nginx instance is behind a reverse proxy that does
    # the HTTPS termination.
    #fastcgi_param HTTPS 1;
    fastcgi_pass unix:/tmp/vndb-fastcgi.sock;
  }
}
```

# License

AGPL-3.0-only, see COPYING file for details.
