#!/bin/sh

VER=`test -f /vndb/Dockerfile && grep VNDB_DOCKER_VERSION= /vndb/Dockerfile | sed -E s/^.+=//`
PGVER=17

if [ -z "$VER" -o -z "$VNDB_DOCKER_VERSION" -o "$VER" != "$VNDB_DOCKER_VERSION" ]; then
    echo "The Docker image version ($VNDB_DOCKER_VERSION) does not match the version in the currently checked out source code ($VER)."
    echo
    echo "Please rebuild the Docker image and try again:"
    echo
    echo "  docker rmi vndb"
    echo "  docker build -t vndb ."
    echo
    echo "Check README.md for instructions."
    echo
    exit 1
fi


# Should run as root
mkdevuser() {
    # Create a new user with the same UID and GID as the owner of the VNDB
    # directory. This allows for convenient exchange of files without worrying
    # about permission stuff.
    # If the owner is root, we're probably running under Docker for Mac or
    # similar and don't need to match UID/GID. See https://vndb.org/t9959 #38
    # to #44.
    USER_UID=`stat -c '%u' /vndb`
    USER_GID=`stat -c '%g' /vndb`
    if test $USER_UID -eq 0; then
        addgroup devgroup
        adduser -s /bin/sh devuser
    else
        addgroup -g $USER_GID devgroup
        adduser -s /bin/sh -u $USER_UID -G devgroup -D devuser
    fi
    install -d -o devuser -g devgroup /run/postgresql
}


# Should run as root
installvndbid() {
    mkdir -p /tmp/vndbid
    cp /vndb/sql/c/vndbfuncs.c /vndb/sql/c/Makefile /tmp/vndbid
    make -C /tmp/vndbid install || exit
}


# Should run as devuser
pg_start() {
    cd /vndb
    make -j4
    util/setup-var.sh

    if [ ! -d docker/pg$PGVER ]; then
        mkdir -p docker/pg$PGVER
        initdb -D docker/pg$PGVER --locale en_US.UTF-8 -A trust
    fi
    pg_ctl -D /vndb/docker/pg$PGVER -l /vndb/docker/pg$PGVER/logfile start

    if test -f docker/pg$PGVER/vndb-init-done; then
        echo
        echo "Database initialization already done."
        echo
        return
    fi

    echo "============================================================="
    echo
    echo "Database has not been initialized yet, doing that now."
    echo "If you want to have some data to play around with,"
    echo "I can download and install a development database for you."
    echo "For information, see https://vndb.org/d8#3"
    echo
    echo "Enter n to setup an empty database, y to download the dev database."
    [ -f dump.sql ] && echo "  Or e to import the existing dump.sql."
    read -p "Choice: " opt

    psql postgres -f sql/superuser_init.sql
    psql -U devuser vndb -f sql/vndbid.sql
    echo "ALTER ROLE vndb       LOGIN" | psql postgres
    echo "ALTER ROLE vndb_site  LOGIN" | psql postgres
    echo "ALTER ROLE vndb_multi LOGIN" | psql postgres

    if [ $opt = e ]
    then
        psql -U vndb -f dump.sql
    elif [ $opt = y ]
    then
        curl -sL https://dl.vndb.org/dump/vndb-dev-latest.tar.gz | tar -C docker/var -xzf-
        psql -U vndb -f docker/var/dump.sql
        rm docker/var/dump.sql
    else
        psql -U vndb -f sql/all.sql
    fi

    touch docker/pg$PGVER/vndb-init-done

    echo
    echo "Database initialization done!"
    echo
}


# Should run as devuser
devshell() {
    cd /vndb
    util/vndb-dev-server.pl
    sh
}


case "$1" in
    '')
        mkdevuser
        installvndbid
        su devuser -c '/vndb/util/docker-init.sh pg_start'
        exec su devuser -c '/vndb/util/docker-init.sh devshell'
        ;;
    pg_start)
        pg_start
        ;;
    devshell)
        devshell
        ;;
esac
