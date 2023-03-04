#!/bin/sh

mkdir -p dl/dump dl/img dl/tmp

die() {
  echo $1
  exit 1
}

# Keep only the last (non-symlink) files matching the given pattern, delete the rest.
cleanup() {
  PAT=$1
  DEL=`find dl/dump -type f -name "$PAT" | sort | head -n -1`
  [ -n "$DEL" ] && rm "$DEL"
  util/dl-gendir.pl
}


dumpfile() {
  FN=$1
  LATEST=$2
  CMD=$3
  test -f "dl/dump/$FN" && echo "$FN already exists" && return
  util/dbdump.pl $CMD "dl/tmp/$FN"
  mv "dl/tmp/$FN" "dl/dump/$FN"
  ln -sf "$FN" "dl/dump/$LATEST"
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

util/dbdump.pl export-img dl/img
