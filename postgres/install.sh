#!/bin/bash
# Step 1 of openai-ads-api/docs/2026-10-26_prod-database-plan.md: Postgres 17 from apt.postgresql.org, its
# config, and the kyma database. Run on the server, from the folder holding these files:
#   sudo bash install.sh
# Safe to re-run: the config is re-installed, the database is only created when missing.
set -euo pipefail
cd "$(dirname "$0")"
[ "$(id -u)" = 0 ] || { echo "Run it with sudo." >&2; exit 1; }

echo "--- firewall (5432 must not be allowed)"
ufw status verbose || true
if ufw status | grep -qw 5432; then echo "ufw allows 5432: remove that rule first." >&2; exit 1; fi

if ! grep -rqs apt.postgresql.org /etc/apt/sources.list.d/; then
  echo "--- adding apt.postgresql.org"
  apt-get update
  apt-get install -y postgresql-common
  /usr/share/postgresql-common/pgdg/apt.postgresql.org.sh -y
fi
echo "--- installing postgresql-17"   # not the 'postgresql' package, which would bring 18
apt-get install -y postgresql-17

conf=/etc/postgresql/17/main
for f in pg_hba.conf pg_ident.conf; do
  [ -f "$conf/$f.orig" ] || cp -p "$conf/$f" "$conf/$f.orig"   # the package's version, kept once
  install -m 640 -o postgres -g postgres "$f" "$conf/$f"
done
install -m 644 -o postgres -g postgres kyma.conf "$conf/conf.d/kyma.conf"
systemctl restart postgresql@17-main     # listen_addresses and shared_buffers need a restart
systemctl enable postgresql@17-main

if [ "$(sudo -u postgres psql -tAc "select 1 from pg_database where datname = 'kyma'")" != 1 ]; then
  echo "--- creating the kyma database and roles"
  sudo -u postgres psql -q < 01-kyma-prod.sql
fi

echo "--- the platform's role and schema"
bash add-app-role.sh

echo "--- listening"
ss -tlnp | grep -E 'postgres|:5432' || true
sudo -u postgres psql -tAc "select version()"
echo "Done. Check as deploy: psql -U kyma_ingest kyma -c 'select current_user'"
