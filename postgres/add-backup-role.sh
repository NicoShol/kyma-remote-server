#!/bin/bash
# The backups' own login (openai-ads-api docs/2026-11-13_database-backups-plan.md, § 4.1):
#   kyma_backup_read   reads every table of kyma (Postgres' pg_read_all_data: select on all tables,
#                      views and sequences, usage on all schemas), writes nothing. No password:
#                      peer auth for Unix user deploy (pg_ident.conf), like kyma_ingest and kyma_app:
#                      on the server, or through the laptop's socket tunnel (as deploy). No TCP line.
# backup/kyma-pg-backup.sh dumps as it. It replaces kyma_ingest there: that login owns ads and ga
# but not schema app (kyma_app's), whose private tables (logins, keys, tokens, access) made every
# dump fail from 2026-10-31.
# From the laptop, after copying the folder (README, "Applying a change"):
#   ssh -t deploy@46.224.142.195 'sudo bash ~/kyma-setup/postgres/add-backup-role.sh'
# Also run by install.sh. Safe to re-run: installs pg_hba/pg_ident (a reload), creates what's missing.
set -euo pipefail
export LC_ALL=C.UTF-8
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
  if not exists (select from pg_roles where rolname = 'kyma_backup_read') then
    create role kyma_backup_read login;
  end if;
end $$;
alter role kyma_backup_read password null;
grant pg_read_all_data to kyma_backup_read;
grant connect on database kyma to kyma_backup_read;   -- the database revokes it from public
alter role kyma_backup_read set default_transaction_read_only = on;
alter role kyma_backup_read connection limit 2;
SQL

echo "kyma_backup_read is ready (reads everything, writes nothing; peer auth as deploy). Check as deploy:"
echo "    psql -U kyma_backup_read kyma -c 'select count(*) from app.users'"
echo "    ~/kyma-setup/backup/kyma-pg-backup.sh"
