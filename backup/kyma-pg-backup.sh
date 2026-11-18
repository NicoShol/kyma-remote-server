#!/bin/bash
# Daily pg_dump of the prod kyma database, as deploy (openai-ads-api/docs/old/2026-10-26_prod-database-plan.md,
# step 7; docs/2026-11-13_database-backups-plan.md, § 4.1 to 4.3). Times are UTC, like the rest of the
# server. Kept 60 days, and pulled by the laptop (clients/macos/pull-backups.sh) so a copy lives off
# the server.
# crontab of deploy, once a day, after the 06:00 update:
#   30 6 * * * /home/deploy/kyma-setup/backup/kyma-pg-backup.sh >> /home/deploy/kyma/logs/backup.log 2>&1
# Restore (into an empty database owned by kyma_ingest; grants come back from install.sh, add-app-role.sh
# and the migrations):
#   pg_restore --no-owner --no-acl --role=kyma_ingest -d <db> kyma-YYYY-MM-DD.dump
#
# Dumps as kyma_backup_read (postgres/add-backup-role.sh): it reads every schema, app's private tables
# included. Each dump is checked before it's kept: readable, every schema there, key tables there, not
# much smaller than the previous one. Any failure: no dump kept, nothing left behind, exit 1, the
# reason in the log. With HEALTHCHECK_URL in ~/kyma-setup/backup/.env (healthchecks.io, never in git),
# a good dump pings it and a failure pings its /fail: no ping for a day sends an email.
set -euo pipefail
export LC_ALL=C.UTF-8
DEST=$HOME/backups/kyma-pg   # apart from ~/backups/kyma-*.sqlite3, which are kyma-website's
ROLE=kyma_backup_read
SCHEMAS=(ads ga app)
# Tables a usable dump must have, with their data: the ones nothing else can rebuild first.
TABLES=("app clients" "app advertisers" "app ad_accounts" "app users" "app ad_account_keys" "app api_tokens"
        "ads report" "ads campaign_accounts")
# %: a dump below this share of the previous one is refused (a table emptied, a dump cut short). After a
# shrink on purpose (a big purge), run it once by hand with KYMA_BACKUP_MIN_RATIO=0.
MIN_RATIO=${KYMA_BACKUP_MIN_RATIO:-50}

HEALTHCHECK_URL=""
env_file="$(dirname "$0")/.env"
[ -f "$env_file" ] && HEALTHCHECK_URL=$(sed -n 's/^HEALTHCHECK_URL=//p' "$env_file" | tail -1)

mkdir -p "$DEST"
chmod 700 "$DEST"
out="$DEST/kyma-$(date -u +%F).dump"
part="$out.part"
list=$(mktemp)
trap 'rm -f "$part" "$list"' EXIT   # never a .part left behind, whatever happens

ping() {   # $1: "" (success) or /fail; never the cause of a failure itself
  [ -n "$HEALTHCHECK_URL" ] && curl -fsS -m 10 --retry 3 -o /dev/null "$HEALTHCHECK_URL$1" || true
}
fail() {
  echo "$(date -u '+%F %T UTC') FAILED: $*" >&2
  ping /fail
  exit 1
}

pg_dump -U "$ROLE" -Fc kyma > "$part" || fail "pg_dump as $ROLE (see above)"

# 1. readable
pg_restore --list "$part" > "$list" 2>/dev/null || fail "pg_restore can't read the dump"
# 2. every schema
for s in "${SCHEMAS[@]}"; do
  grep -qE "^[0-9]+; [0-9]+ [0-9]+ SCHEMA - $s " "$list" || fail "schema $s is missing from the dump"
done
# 3. key tables, with their data
for t in "${TABLES[@]}"; do
  grep -qE "^[0-9]+; [0-9]+ [0-9]+ TABLE DATA ${t} " "$list" || fail "the data of ${t/ /.} is missing from the dump"
done
# 4. not much smaller than the previous good one
size=$(stat -c %s "$part")
previous=$(ls -1t "$DEST"/kyma-*.dump 2>/dev/null | grep -v "^$out$" | head -1 || true)
if [ -n "$previous" ]; then
  before=$(stat -c %s "$previous")
  [ $((size * 100)) -ge $((before * MIN_RATIO)) ] \
    || fail "the dump is $size bytes, under $MIN_RATIO % of the previous one ($(basename "$previous"), $before bytes)"
fi

mv "$part" "$out"
find "$DEST" -name 'kyma-*.dump' -mtime +60 -delete
find "$DEST" -name 'kyma-*.dump.part' -delete   # left by the failed dumps of before this check
ping ""
echo "$(date -u '+%F %T UTC') $out $(du -h "$out" | cut -f1), checked: ${SCHEMAS[*]}, ${#TABLES[@]} key tables"
