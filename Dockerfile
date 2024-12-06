FROM alpine:3.21
MAINTAINER Yorhel <contact@vndb.org>

ENV VNDB_DOCKER_VERSION=15
ENV VNDB_GEN=/vndb/docker/gen
ENV VNDB_VAR=/vndb/docker/var
CMD /vndb/util/docker-init.sh

RUN apk add --no-cache \
        build-base \
        curl \
        git \
        graphviz \
        vips-dev \
        perl-algorithm-diff-xs \
        perl-anyevent \
        perl-anyevent-http \
        perl-app-cpanminus \
        perl-crypt-urandom \
        perl-dbd-pg \
        perl-dev \
        perl-http-server-simple \
        perl-json-xs \
        perl-module-build \
        postgresql17 \
        postgresql17-contrib \
        postgresql17-dev \
        sassc \
        wget \
        zlib-dev \
    && cpanm -nq \
        AnyEvent::IRC \
        AnyEvent::Pg \
        Crypt::ScryptKDF \
        PerlIO::gzip \
        SQL::Interp \
        Text::MultiMarkdown \
        git://g.blicky.net/tuwf.git \
    && curl -sL https://github.com/elm/compiler/releases/download/0.19.1/binary-for-linux-64-bit.gz | zcat >/usr/bin/elm \
    && chmod 755 /usr/bin/elm
