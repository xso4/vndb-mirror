#!/bin/sh

[ -z "$VNDB_VAR" ] && VNDB_VAR=var

mkdir -p "$VNDB_VAR/dl/dump" "$VNDB_VAR/dl/img" "$VNDB_VAR/tmp"

# Keep only the last (non-symlink) files matching the given pattern, delete the rest.
cleanup() {
  (
    cd "$VNDB_VAR/dl/dump"
    for f in $(find . -type f -name "$1" | sort | head -n -1); do
      rm "$f"
    done
  )
  util/dl-gendir.pl
}


dumpfile() {
  FN=$1
  LATEST=$2
  CMD=$3
  test -f "$VNDB_VAR/dl/dump/$FN" && echo "$FN already exists" && return
  util/dbdump.pl $CMD "$VNDB_VAR/tmp/$FN"
  mv "$VNDB_VAR/tmp/$FN" "$VNDB_VAR/dl/dump/$FN"
  ln -sf "$FN" "$VNDB_VAR/dl/dump/$LATEST"
  util/dl-gendir.pl
}

cleanup "vndb-dev-*.tar.gz"

cleanup "vndb-votes-*.gz"
dumpfile "vndb-votes-`date +%F`.gz" "vndb-votes-latest.gz" export-votes

cleanup "vndb-tags-*.json.gz"
dumpfile "vndb-tags-`date +%F`.json.gz" "vndb-tags-latest.json.gz" export-tags

cleanup "vndb-traits-*.json.gz"
dumpfile "vndb-traits-`date +%F`.json.gz" "vndb-traits-latest.json.gz" export-traits

cleanup "vndb-db-*.tar.zst"
dumpfile "vndb-db-`date +%F`.tar.zst" "vndb-db-latest.tar.zst" export-db

util/dbdump.pl export-img "$VNDB_VAR/dl/img"
