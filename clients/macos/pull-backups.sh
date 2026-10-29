#!/bin/bash
# Pulls the server's daily database dumps to the laptop, so a copy lives off the server
# (openai-ads-api/docs/2026-10-26_prod-database-plan.md, step 7). Run by eu.kyma.pg-backup-pull.plist
# at 19:00, or by hand. Never deletes on the server; keeps 60 days here.
# A run missed while the Mac sleeps starts on wake, often before the network is back:
# up to 10 tries, a minute apart, before giving up until the next day.
set -euo pipefail
DEST="$HOME/Backups/kyma/server"
mkdir -p "$DEST"
for try in 1 2 3 4 5 6 7 8 9 10; do
  rsync -a -e "ssh -o BatchMode=yes -o ConnectTimeout=20" deploy@46.224.142.195:backups/kyma-pg/ "$DEST/" && break
  if [ "$try" = 10 ]; then
    echo "$(date '+%F %T') FAILED after 10 tries: nothing pulled" >&2
    exit 1
  fi
  echo "$(date '+%F %T') try $try failed, next in 60 s" >&2
  sleep 60
done
find "$DEST" -name 'kyma-*.dump' -mtime +60 -delete
latest=$(ls -1t "$DEST"/kyma-*.dump 2>/dev/null | head -1)
echo "$(date '+%F %T') pulled; latest: ${latest:-none} $( [ -n "$latest" ] && du -h "$latest" | cut -f1)"
