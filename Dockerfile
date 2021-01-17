FROM alpine:3.13
MAINTAINER Yorhel <contact@vndb.org>

ENV VNDB_DOCKER_VERSION=6
CMD /var/www/util/docker-init.sh

RUN apk add --no-cache \
        build-base \
        curl \
        git \
        graphviz \
        imagemagick \
        perl-algorithm-diff-xs \
        perl-anyevent \
        perl-app-cpanminus \
        perl-dbd-pg \
        perl-dev \
        perl-json-xs \
        perl-module-build \
        postgresql \
        postgresql-dev \
        sassc \
        wget \
        zlib-dev \
    && cpanm -nq \
        AnyEvent::HTTP \
        AnyEvent::IRC \
        AnyEvent::Pg \
        Crypt::ScryptKDF \
        Crypt::URandom \
        HTTP::Server::Simple \
        PerlIO::gzip \
        SQL::Interp \
        Text::MultiMarkdown \
        git://g.blicky.net/tuwf.git \
    && curl -sL https://github.com/elm/compiler/releases/download/0.19.1/binary-for-linux-64-bit.gz | zcat >/usr/bin/elm \
    && chmod 755 /usr/bin/elm
