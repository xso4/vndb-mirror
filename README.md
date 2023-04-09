# The VNDB.org Source Code

## How to contribute

First, a warning: VNDB's code base is a ~~little~~ *very* weird when compared
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
- PostgreSQL 15+ (including development files)
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


## Production Deployment

The above instructions are suitable for a development environment. For a
production environment, you'll really want to use FastCGI instead of the shitty
built-in web server. Make sure to install the `FCGI` Perl module to do that.
In the past I've used Apache (with `mod_fcgid`) and Lighttpd, but my current
setup is based on nginx. Since nginx does not come with a FastCGI process
manager, I use [spawn-fcgi](https://git.lighttpd.net/lighttpd/spawn-fcgi) in
combination with [multiwatch](https://git.lighttpd.net/lighttpd/multiwatch):

```sh
spawn-fcgi -s /tmp/vndb-fastcgi.sock -u vndb -g vndb -- \
    /usr/bin/multiwatch -f 6 -r 10000 -s TERM /path/to/vndb/util/vndb.pl
```

There is a slow memory "leak" in the Perl backend, so you'll want to reload the
vndb.pl processes once in a while. One way to do that is by setting
`fastcgi_max_requests` in data/conf.pl, but it is also safe to reload the
processes by running a `pkill vndb.pl` at any time.

For optimized static assets, run `make prod` as part of your deployment
procedure. This has some additional dependencies, see the Makefile for details.

With the above taken care of, the nginx configuration for a single-domain setup
looks something like this:

```nginx
root /path/to/vndb/static;

location @fcgi {
  include /etc/nginx/fastcgi_params;
  # The following can be used to trick TUWF into thinking we're running on
  # HTTPS, useful if this nginx instance is behind a reverse proxy that does
  # the HTTPS termination.
  #fastcgi_param HTTPS 1;
  fastcgi_pass unix:/tmp/vndb-fastcgi.sock;
}

location / {
  expires 1y;
  gzip_static on;
  gzip_http_version 1.0;
  # If you have the brotli plugin:
  #brotli_static on;
  rewrite ^/g/icons\.png /g/icons.opt.png;
  rewrite ^/g/elm\.js    /g/elm.min.js;
  rewrite ^/g/basic\.js  /g/basic.min.js;
  try_files $uri /path/to/vndb/static/$uri @fcgi;
}
```

# License

GNU AGPL, see COPYING file for details.
