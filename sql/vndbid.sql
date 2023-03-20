-- This file defines a custom 'vndbid' base type and a bunch of utility functions.
-- This file must be loaded into the 'vndb' database as a superuser, e.g.:
--
--   psql -U postgres vndb -f sql/vndbid.sql
--
-- A 'vndbid' represents an identifier used on the site and is essentially a
-- (type,number) tuple, e.g. 'v17', 'r102', 'sf500'. It is not strictly limited
-- to database entries with an edit history, any type-prefixed integer could be
-- added here.
--
-- Main advantage of this type is convenience and domain separation. Comparing
-- vndbids of different types will always return false, so it's less prone to
-- errors. Values are interally represented as a 32bit integer, so they're
-- pretty efficient as well.
--
-- Constructing an ID:
--
--   'v1'::vndbid
--   vndbid('v', 1)
--
-- Extracting info:
--
--   vndbid_type('v1') -- 'v'
--   vndbid_num('v1') -- 1
--
-- Efficient filtering on the type:
--
--   id BETWEEN 'v1' AND vndbid_max('v')
--
-- Is equivalent to, but faster than:
--
--   vndbid_type(id) = 'v'
--
CREATE TYPE vndbid;

CREATE FUNCTION vndbid_in(cstring)           RETURNS vndbid  AS 'vndbfuncs' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;
CREATE FUNCTION vndbid_out(vndbid)           RETURNS cstring AS 'vndbfuncs' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;
CREATE FUNCTION vndbid_recv(internal)        RETURNS vndbid  AS 'vndbfuncs' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;
CREATE FUNCTION vndbid_send(vndbid)          RETURNS bytea   AS 'vndbfuncs' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;
CREATE FUNCTION vndbid_cmp(vndbid, vndbid)   RETURNS int     AS 'vndbfuncs' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;
CREATE FUNCTION vndbid_lt(vndbid, vndbid)    RETURNS boolean AS 'vndbfuncs' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;
CREATE FUNCTION vndbid_le(vndbid, vndbid)    RETURNS boolean AS 'vndbfuncs' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;
CREATE FUNCTION vndbid_eq(vndbid, vndbid)    RETURNS boolean AS 'vndbfuncs' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;
CREATE FUNCTION vndbid_ge(vndbid, vndbid)    RETURNS boolean AS 'vndbfuncs' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;
CREATE FUNCTION vndbid_gt(vndbid, vndbid)    RETURNS boolean AS 'vndbfuncs' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;
CREATE FUNCTION vndbid_ne(vndbid, vndbid)    RETURNS boolean AS 'vndbfuncs' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;
CREATE FUNCTION vndbid_sortsupport(internal) RETURNS void    AS 'vndbfuncs' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;
CREATE FUNCTION vndbid_hash(vndbid)          RETURNS int     AS 'vndbfuncs' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;
CREATE FUNCTION vndbid(text, int)            RETURNS vndbid  AS 'vndbfuncs' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;
CREATE FUNCTION vndbid_type(vndbid)          RETURNS text    AS 'vndbfuncs' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;
CREATE FUNCTION vndbid_num(vndbid)           RETURNS int     AS 'vndbfuncs' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;
CREATE FUNCTION vndbid_max(text)             RETURNS vndbid  AS 'vndbfuncs' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;

CREATE TYPE vndbid (
    internallength = 4,
    input = vndbid_in,
    output = vndbid_out,
    receive = vndbid_recv,
    send = vndbid_send,
    alignment = int4,
    passedbyvalue
);

CREATE OPERATOR <  (leftarg = vndbid, rightarg = vndbid, procedure = vndbid_lt, commutator = > , negator = >=, restrict = scalarltsel, join = scalarltjoinsel);
CREATE OPERATOR <= (leftarg = vndbid, rightarg = vndbid, procedure = vndbid_le, commutator = >=, negator = > , restrict = scalarlesel, join = scalarlejoinsel);
CREATE OPERATOR =  (leftarg = vndbid, rightarg = vndbid, procedure = vndbid_eq, commutator = = , negator = <>, restrict = eqsel,       join = eqjoinsel, HASHES, MERGES);
CREATE OPERATOR <> (leftarg = vndbid, rightarg = vndbid, procedure = vndbid_ne, commutator = <>, negator = =,  restrict = neqsel,      join = neqjoinsel);
CREATE OPERATOR >= (leftarg = vndbid, rightarg = vndbid, procedure = vndbid_ge, commutator = <=, negator = < , restrict = scalargesel, join = scalargejoinsel);
CREATE OPERATOR >  (leftarg = vndbid, rightarg = vndbid, procedure = vndbid_gt, commutator = < , negator = <=, restrict = scalargtsel, join = scalargtjoinsel);

CREATE OPERATOR CLASS vndbid_btree_ops DEFAULT FOR TYPE vndbid USING btree AS
    OPERATOR 1 <,
    OPERATOR 2 <=,
    OPERATOR 3 =,
    OPERATOR 4 >=,
    OPERATOR 5 >,
    FUNCTION 1 vndbid_cmp(vndbid, vndbid),
    FUNCTION 2 vndbid_sortsupport(internal),
    FUNCTION 4 btequalimage(oid);

CREATE OPERATOR CLASS vndbid_hash_ops DEFAULT FOR TYPE vndbid USING hash AS
    OPERATOR 1 =,
    FUNCTION 1 vndbid_hash(vndbid);


-- Unrelated to the vndbid type, but put here because this file is, ultimately, where all extensions are loaded.
CREATE EXTENSION unaccent;
CREATE EXTENSION pg_trgm;
