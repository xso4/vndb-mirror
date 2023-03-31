# SQL Update Scripts

This directory contains scripts to keep the live database schema synchronized
with the code in the git repo, in particular with the definitions in the `sql/`
directory.

## Naming scheme

```sh
`date +%F`-description.sql
```

The date is the date on which the script is applied to the production database.
For work-in-progress updates where that date is not yet known, use a `wip-`
prefix instead.

(The older `update_{date}.sql` naming scheme is deprecated)

## Applying the updates

Do not blindly apply these scripts in order and expect them to work. Since the
scripts were written for the sole purpose of updating the live production
database - which only needs to happen once per update - I often take some
shortcuts:

- The scripts often directly import other scripts from `sql/`. Later changes to
  files in `sql/` may break the update scripts, so generally the safest way to
  apply a particular script is to find the latest commit where the script has
  been edited, then do a checkout of that commit and run the script in that
  context.
- Always run `make` before running a script, it may rely on `sql/editfunc.sql`.
- Not all changes get an update script. Sometimes just running `sql/func.sql`
  is sufficient to apply a change. In rare cases an update requires a full dump
  & reload using `util/dbdump.pl export-data`, such as changes to column order
  (which I sometimes do around a PostgreSQL version upgrade since those can
  benefit from a dump & reload anyway) or changes to the definition of an
  important data type (`vndbid` in particular, but such changes should be very
  rare).

## Downtime

I'm not consistent with respect to whether these scripts can be run without
downtime. Most scripts work just fine while the site is up and running, others
may require that the site is taken down for a few minutes.

Likewise, some scripts will leave the database in a state that an already
running process can't deal with. That may result in some 500 errors until the
process is restarted with the new code.

Scripts often contain comments regarding the above. They're worth reading
before applying, in any case.
