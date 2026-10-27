#!/bin/bash
# Daily pg_dump of the prod kyma database, as deploy (openai-ads-api/docs/2026-10-26_prod-database-plan.md,
# step 7). Times are UTC, like the rest of the server. Kept 60 days, and pulled by the laptop
# (clients/macos/pull-backups.sh) so a copy lives off the server.
# crontab of deploy, after the daily update (06:00):
#   30 6 * * * /home/deploy/kyma-setup/backup/kyma-pg-backup.sh >> /home/deploy/kyma/logs/backup.log 2>&1
# Restore (into an empty database): pg_restore -U kyma_ingest -d <db> --no-owner kyma-YYYY-MM-DD.dump
set -euo pipefail
export LC_ALL=C.UTF-8
DEST=$HOME/backups/kyma-pg   # apart from ~/backups/kyma-*.sqlite3, which are kyma-website's
mkdir -p "$DEST"
chmod 700 "$DEST"
out="$DEST/kyma-$(date -u +%F).dump"
# kyma_ingest owns ads and ga (peer auth as deploy): the dump is complete. A failed dump never replaces a good one.
pg_dump -U kyma_ingest -Fc kyma > "$out.part"
mv "$out.part" "$out"
find "$DEST" -name 'kyma-*.dump' -mtime +60 -delete
echo "$(date -u '+%F %T UTC') $out $(du -h "$out" | cut -f1)"
