-- This file defines a custom 'vndbtag' and 'vndbid' type plus a bunch of
-- utility functions.
-- This file must be loaded into the 'vndb' database as a superuser, e.g.:
--
--   psql -U postgres vndb -f sql/vndbid.sql
--
-- The 'vndbtag' type provides an efficient way of working with short strings
-- that match "[a-z]{1,3}". Its primary purpose is to designate the type of
-- 'vndbid's, but it could also be used as an enum-like type.
--
-- The 'vndbid' type represents an identifier used on the site and is
-- essentially a (vndbtag,integer) tuple, e.g. 'v17', 'r102', 'sf500'.
-- The Main advantage of this type is convenience and domain separation.
-- Comparing vndbids of different types will always return false, so it's less
-- prone to errors.
--
-- Constructing an ID:
--
--   'v1'::vndbid
--   vndbid('v', 1)
--
-- Extracting info:
--
--   vndbid_type('v1') or ~id  -- 'v'
--   vndbid_num('v1')  or #id  -- 1
--
-- Efficient filtering on the type:
--
--   id ^= 'v'
--
-- Is equivalent to, but faster than:
--
--   vndbid_type(id) = 'v'
--
-- It's also possible to enforce a specific type:
--
--   CREATE TABLE example (
--      id vndbid(v) NOT NULL  -- similar to a check constraint (id ^= 'v')
--   )
--
CREATE TYPE vndbtag;

CREATE FUNCTION vndbtag_in(cstring)           RETURNS vndbtag AS 'vndbfuncs' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;
CREATE FUNCTION vndbtag_out(vndbtag)          RETURNS cstring AS 'vndbfuncs' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;
CREATE FUNCTION vndbtag_recv(internal)        RETURNS vndbtag AS 'vndbfuncs' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;
CREATE FUNCTION vndbtag_send(vndbtag)         RETURNS bytea   AS 'int2send' LANGUAGE internal IMMUTABLE STRICT PARALLEL SAFE;
CREATE FUNCTION vndbtag_cmp(vndbtag, vndbtag) RETURNS int     AS 'btint2cmp' LANGUAGE internal IMMUTABLE STRICT PARALLEL SAFE;
CREATE FUNCTION vndbtag_lt(vndbtag, vndbtag)  RETURNS boolean AS 'int2lt' LANGUAGE internal IMMUTABLE STRICT PARALLEL SAFE;
CREATE FUNCTION vndbtag_le(vndbtag, vndbtag)  RETURNS boolean AS 'int2le' LANGUAGE internal IMMUTABLE STRICT PARALLEL SAFE;
CREATE FUNCTION vndbtag_eq(vndbtag, vndbtag)  RETURNS boolean AS 'int2eq' LANGUAGE internal IMMUTABLE STRICT PARALLEL SAFE;
CREATE FUNCTION vndbtag_ge(vndbtag, vndbtag)  RETURNS boolean AS 'int2ge' LANGUAGE internal IMMUTABLE STRICT PARALLEL SAFE;
CREATE FUNCTION vndbtag_gt(vndbtag, vndbtag)  RETURNS boolean AS 'int2gt' LANGUAGE internal IMMUTABLE STRICT PARALLEL SAFE;
CREATE FUNCTION vndbtag_ne(vndbtag, vndbtag)  RETURNS boolean AS 'int2ne' LANGUAGE internal IMMUTABLE STRICT PARALLEL SAFE;
CREATE FUNCTION vndbtag_hash(vndbtag)         RETURNS int     AS 'hashint2' LANGUAGE internal IMMUTABLE STRICT PARALLEL SAFE;
CREATE FUNCTION vndbtag_hash64(vndbtag,bigint)RETURNS bigint  AS 'hashint2extended' LANGUAGE internal IMMUTABLE STRICT PARALLEL SAFE;

CREATE TYPE vndbtag (
    input = vndbtag_in,
    output = vndbtag_out,
    receive = vndbtag_recv,
    send = vndbtag_send,
    like = int2
);

CREATE OPERATOR <  (leftarg = vndbtag, rightarg = vndbtag, procedure = vndbtag_lt, commutator = > , negator = >=, restrict = scalarltsel, join = scalarltjoinsel);
CREATE OPERATOR <= (leftarg = vndbtag, rightarg = vndbtag, procedure = vndbtag_le, commutator = >=, negator = > , restrict = scalarlesel, join = scalarlejoinsel);
CREATE OPERATOR =  (leftarg = vndbtag, rightarg = vndbtag, procedure = vndbtag_eq, commutator = = , negator = <>, restrict = eqsel,       join = eqjoinsel, HASHES, MERGES);
CREATE OPERATOR <> (leftarg = vndbtag, rightarg = vndbtag, procedure = vndbtag_ne, commutator = <>, negator = =,  restrict = neqsel,      join = neqjoinsel);
CREATE OPERATOR >= (leftarg = vndbtag, rightarg = vndbtag, procedure = vndbtag_ge, commutator = <=, negator = < , restrict = scalargesel, join = scalargejoinsel);
CREATE OPERATOR >  (leftarg = vndbtag, rightarg = vndbtag, procedure = vndbtag_gt, commutator = < , negator = <=, restrict = scalargtsel, join = scalargtjoinsel);

CREATE OPERATOR CLASS vndbtag_btree_ops DEFAULT FOR TYPE vndbtag USING btree AS
    OPERATOR 1 <,
    OPERATOR 2 <=,
    OPERATOR 3 =,
    OPERATOR 4 >=,
    OPERATOR 5 >,
    FUNCTION 1 vndbtag_cmp(vndbtag, vndbtag),
    FUNCTION 2 btint2sortsupport(internal),
    FUNCTION 4 btequalimage(oid);

CREATE OPERATOR CLASS vndbtag_hash_ops DEFAULT FOR TYPE vndbtag USING hash AS
    OPERATOR 1 =,
    FUNCTION 1 vndbtag_hash(vndbtag),
    FUNCTION 2 vndbtag_hash64(vndbtag, bigint);




CREATE TYPE vndbid;

CREATE FUNCTION vndbid_in(cstring,oid,integer)RETURNS vndbid AS 'vndbfuncs', 'vndbid2_in' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;
CREATE FUNCTION vndbid_out(vndbid)           RETURNS cstring AS 'vndbfuncs', 'vndbid2_out' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;
CREATE FUNCTION vndbid_typ_in(cstring[])     RETURNS integer AS 'vndbfuncs', 'vndbid2_typ_in' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;
CREATE FUNCTION vndbid_typ_out(integer)      RETURNS cstring AS 'vndbfuncs', 'vndbid2_typ_out' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;
CREATE FUNCTION vndbid_cast(vndbid,integer)  RETURNS vndbid  AS 'vndbfuncs', 'vndbid2_cast' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;
CREATE FUNCTION vndbid_recv(internal)        RETURNS vndbid  AS 'vndbfuncs', 'vndbid2_recv' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;
CREATE FUNCTION vndbid_send(vndbid)          RETURNS bytea   AS 'int8send' LANGUAGE internal IMMUTABLE STRICT PARALLEL SAFE;
CREATE FUNCTION vndbid_cmp(vndbid, vndbid)   RETURNS int     AS 'btint8cmp' LANGUAGE internal IMMUTABLE STRICT PARALLEL SAFE;
CREATE FUNCTION vndbid_lt(vndbid, vndbid)    RETURNS boolean AS 'int8lt' LANGUAGE internal IMMUTABLE STRICT PARALLEL SAFE;
CREATE FUNCTION vndbid_le(vndbid, vndbid)    RETURNS boolean AS 'int8le' LANGUAGE internal IMMUTABLE STRICT PARALLEL SAFE;
CREATE FUNCTION vndbid_eq(vndbid, vndbid)    RETURNS boolean AS 'int8eq' LANGUAGE internal IMMUTABLE STRICT PARALLEL SAFE;
CREATE FUNCTION vndbid_ge(vndbid, vndbid)    RETURNS boolean AS 'int8ge' LANGUAGE internal IMMUTABLE STRICT PARALLEL SAFE;
CREATE FUNCTION vndbid_gt(vndbid, vndbid)    RETURNS boolean AS 'int8gt' LANGUAGE internal IMMUTABLE STRICT PARALLEL SAFE;
CREATE FUNCTION vndbid_ne(vndbid, vndbid)    RETURNS boolean AS 'int8ne' LANGUAGE internal IMMUTABLE STRICT PARALLEL SAFE;
CREATE FUNCTION vndbid_hash(vndbid)          RETURNS int     AS 'hashint8' LANGUAGE internal IMMUTABLE STRICT PARALLEL SAFE;
CREATE FUNCTION vndbid_hash64(vndbid,bigint) RETURNS bigint  AS 'hashint8extended' LANGUAGE internal IMMUTABLE STRICT PARALLEL SAFE;
CREATE FUNCTION vndbid(vndbtag, bigint)      RETURNS vndbid  AS 'vndbfuncs', 'vndbid2' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;
CREATE FUNCTION vndbid_type(vndbid)          RETURNS vndbtag AS 'vndbfuncs', 'vndbid2_type' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;
CREATE FUNCTION vndbid_istype_sup(internal)  RETURNS internal AS'vndbfuncs', 'vndbid2_istype_sup' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;
CREATE FUNCTION vndbid_istype(vndbid,vndbtag)RETURNS boolean AS 'vndbfuncs', 'vndbid2_istype' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE SUPPORT vndbid_istype_sup;
CREATE FUNCTION vndbid_num(vndbid)           RETURNS bigint  AS 'vndbfuncs', 'vndbid2_num' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;
CREATE FUNCTION vndbid_max(vndbtag)          RETURNS vndbid  AS 'vndbfuncs', 'vndbid2_max' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;

CREATE TYPE vndbid (
    input = vndbid_in,
    output = vndbid_out,
    typmod_in = vndbid_typ_in,
    typmod_out = vndbid_typ_out,
    receive = vndbid_recv,
    send = vndbid_send,
    like = int8
);

CREATE OPERATOR <  (leftarg = vndbid, rightarg = vndbid, procedure = vndbid_lt, commutator = > , negator = >=, restrict = scalarltsel, join = scalarltjoinsel);
CREATE OPERATOR <= (leftarg = vndbid, rightarg = vndbid, procedure = vndbid_le, commutator = >=, negator = > , restrict = scalarlesel, join = scalarlejoinsel);
CREATE OPERATOR =  (leftarg = vndbid, rightarg = vndbid, procedure = vndbid_eq, commutator = = , negator = <>, restrict = eqsel,       join = eqjoinsel, HASHES, MERGES);
CREATE OPERATOR <> (leftarg = vndbid, rightarg = vndbid, procedure = vndbid_ne, commutator = <>, negator = =,  restrict = neqsel,      join = neqjoinsel);
CREATE OPERATOR >= (leftarg = vndbid, rightarg = vndbid, procedure = vndbid_ge, commutator = <=, negator = < , restrict = scalargesel, join = scalargejoinsel);
CREATE OPERATOR >  (leftarg = vndbid, rightarg = vndbid, procedure = vndbid_gt, commutator = < , negator = <=, restrict = scalargtsel, join = scalargtjoinsel);

CREATE OPERATOR ~  (rightarg = vndbid, procedure = vndbid_type);
CREATE OPERATOR #  (rightarg = vndbid, procedure = vndbid_num);
CREATE OPERATOR ^= (leftarg = vndbid, rightarg = vndbtag, procedure = vndbid_istype, restrict = neqsel, join = neqjoinsel);

CREATE CAST (vndbid AS vndbid) WITH FUNCTION vndbid_cast(vndbid, integer) AS IMPLICIT;

CREATE OPERATOR CLASS vndbid_btree_ops DEFAULT FOR TYPE vndbid USING btree AS
    OPERATOR 1 <,
    OPERATOR 2 <=,
    OPERATOR 3 =,
    OPERATOR 4 >=,
    OPERATOR 5 >,
    FUNCTION 1 vndbid_cmp(vndbid, vndbid),
    FUNCTION 2 btint8sortsupport(internal),
    FUNCTION 4 btequalimage(oid);

CREATE OPERATOR CLASS vndbid_hash_ops DEFAULT FOR TYPE vndbid USING hash AS
    OPERATOR 1 =,
    FUNCTION 1 vndbid_hash(vndbid),
    FUNCTION 2 vndbid_hash64(vndbid, bigint);



-- Unrelated to the vndbid type, but put here because this file is, ultimately, where all extensions are loaded.
CREATE EXTENSION unaccent;
CREATE EXTENSION pg_trgm;
