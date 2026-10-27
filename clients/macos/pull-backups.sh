#!/bin/bash
# Pulls the server's daily database dumps to the laptop, so a copy lives off the server
# (openai-ads-api/docs/2026-10-26_prod-database-plan.md, step 7). Run by eu.kyma.pg-backup-pull.plist
# at 19:00, or by hand. Never deletes on the server; keeps 60 days here.
set -euo pipefail
DEST="$HOME/Backups/kyma/server"
mkdir -p "$DEST"
rsync -a -e "ssh -o BatchMode=yes" deploy@46.224.142.195:backups/kyma-pg/ "$DEST/"
find "$DEST" -name 'kyma-*.dump' -mtime +60 -delete
latest=$(ls -1t "$DEST"/kyma-*.dump 2>/dev/null | head -1)
echo "$(date '+%F %T') pulled; latest: ${latest:-none} $( [ -n "$latest" ] && du -h "$latest" | cut -f1)"
