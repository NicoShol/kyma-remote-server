-- Prod database, schemas and roles (openai-ads-api/docs/2026-10-26_prod-database-plan.md, step 1).
-- Same layout as openai-ads-api/infra/postgres/initdb/01-kyma.sh, without passwords and without kyma_test.
-- Run once by install.sh, as the postgres superuser.
\set ON_ERROR_STOP on

create role kyma_ingest login;                    -- writes; peer auth for Unix user deploy, no password
create role kyma_reader nologin;                  -- group holding the select grants
create role reader_deploy login in role kyma_reader;   -- the laptop's and the server's read-only login
alter role reader_deploy set default_transaction_read_only = on;
-- one reader_<machine> per other machine: add-reader.sh

create database kyma owner kyma_ingest;
revoke all on database kyma from public;
grant connect on database kyma to kyma_ingest, kyma_reader;
-- on the database, not on the roles: settings on a group role aren't inherited by its members
alter database kyma set search_path = ads, ga, public;
alter database kyma set timezone = 'Europe/Paris';

\connect kyma
create schema ads authorization kyma_ingest;
create schema ga authorization kyma_ingest;
grant usage on schema ads, ga to kyma_reader;
-- views are dropped and re-created on every run: grant on future objects, not just existing ones
alter default privileges for role kyma_ingest in schema ads, ga grant select on tables to kyma_reader;
