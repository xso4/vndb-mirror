-- This script should be run before all other scripts and as a PostgreSQL
-- superuser. It will create the VNDB database and required users.
-- All other SQL scripts should be run by the 'vndb' user.

-- In order to "activate" a user, i.e. to allow login, you need to manually run
-- the following for each user you want to activate:
--   ALTER ROLE rolename LOGIN PASSWORD 'password';

CREATE ROLE vndb;
CREATE DATABASE vndb OWNER vndb;

-- The website
CREATE ROLE vndb_site;
ALTER ROLE vndb_site SET client_min_messages TO WARNING;
ALTER ROLE vndb_site SET statement_timeout TO 10000;
-- Multi
CREATE ROLE vndb_multi;
