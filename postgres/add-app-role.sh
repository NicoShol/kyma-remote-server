#!/bin/bash
# The Kyma platform's own schema and login (openai-ads-api: webapp/, docs/webapp/2026-10-30_campaign-ownership-plan.md):
#   schema app   what the platform decides itself: clients, advertisers, which ad account is whose, the view
#                campaign_owners. Readers (kyma_reader) can read it.
#   kyma_app     the only login that writes app; none of ads or ga (those stay kyma_ingest's). It reads them
#                through kyma_reader. No password: peer auth for Unix user deploy (pg_ident.conf), on the server
#                or through the laptop's socket tunnel, exactly like kyma_ingest.
# From the laptop, after copying the folder (README, "Applying a change"):
#   ssh -t deploy@46.224.142.195 'sudo bash ~/kyma-setup/postgres/add-app-role.sh'
# Also run by install.sh. Safe to re-run: installs pg_hba/pg_ident (a reload, not a restart), creates what's
# missing, and removes a password kyma_app may have had (the first version of the script gave it one).
set -euo pipefail
export LC_ALL=C.UTF-8   # the Mac sends LC_CTYPE=UTF-8, which the server lacks
cd "$(dirname "$0")"
[ "$(id -u)" = 0 ] || { echo "Run it with sudo." >&2; exit 1; }

conf=/etc/postgresql/17/main
for f in pg_hba.conf pg_ident.conf; do
  install -m 640 -o postgres -g postgres "$f" "$conf/$f"
done
systemctl reload postgresql@17-main   # pg_hba and pg_ident are read again on reload

sudo -u postgres psql -X -q -v ON_ERROR_STOP=1 -d kyma <<'SQL'
do $$
begin
  if not exists (select from pg_roles where rolname = 'kyma_app') then
    create role kyma_app login;
  end if;
end $$;
alter role kyma_app password null;
grant kyma_reader to kyma_app;
alter role kyma_app connection limit 10;
alter role kyma_app set statement_timeout = '30s';

create schema if not exists app authorization kyma_app;
grant usage on schema app to kyma_reader;
alter default privileges for role kyma_app in schema app grant select on tables to kyma_reader;
grant select on all tables in schema app to kyma_reader;
SQL

echo "kyma_app is ready (no password: peer auth as deploy). Check as deploy:"
echo "    psql -U kyma_app kyma -c 'select current_user'"
echo "Platform setup (openai-ads-api, README \"Plateforme Kyma\"), with"
echo "    PLATFORM_DATABASE_URL=postgresql://kyma_app@localhost:5433/kyma           # laptop, through the tunnel"
echo "    PLATFORM_DATABASE_URL=postgresql://kyma_app@/kyma?host=/var/run/postgresql # on the server"
