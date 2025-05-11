#!/bin/sh

[ -z "$VNDB_GEN" ] && VNDB_GEN=gen
[ -z "$VNDB_VAR" ] && VNDB_VAR=var

mkdir -p "$VNDB_VAR/static"

[ -e "$VNDB_VAR/conf.pl" ] || cp conf_example.pl "$VNDB_VAR/conf.pl"

# Symlink for compatibility with old URLs
[ -e "$VNDB_VAR/static/g" ] || ln -s "$(realpath $VNDB_GEN/static)" "$VNDB_VAR/static/g"

cd "$VNDB_VAR"
mkdir -p tmp log

for d in ch ch.orig cv cv.orig cv.t sf sf.orig sf.t; do
    for i in `seq -w 0 1 99`; do
        mkdir -p static/$d/$i
    done
done
[ -e static/st ] || ln -s sf.t static/st
