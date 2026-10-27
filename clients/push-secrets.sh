#!/bin/bash
# Gives the server's cron what it needs to call the APIs (openai-ads-api/docs/2026-10-26_prod-database-plan.md,
# step 6). Run on the laptop, after the repos are cloned in ~/kyma on the server:
#   bash ~/kyma/remote-server/clients/push-secrets.sh
# The keys go through ssh's stdin (never on a command line), into mode-600 files on the server.
# Re-run it after changing a key. Nothing is printed but the names of the settings.
set -euo pipefail
SERVER=deploy@46.224.142.195
ADS=$HOME/kyma/openai-ads-api
GA=$HOME/kyma/google-analytics-export
# The server writes as Unix user deploy through the local socket (peer auth): no password.
DB='DATABASE_URL=postgresql://kyma_ingest@/kyma?host=/var/run/postgresql
DATABASE_URL_RO=postgresql://reader_deploy@/kyma?host=/var/run/postgresql'

keys=$(grep -E '^(OPENAI_ADS_API_KEY|THRAD_ADS_API_KEY)=' "$ADS/.env")
[ "$(printf '%s\n' "$keys" | wc -l)" -eq 2 ] || { echo "Expected both API keys in $ADS/.env" >&2; exit 1; }
[ -f "$GA/cle.json" ] || { echo "Missing $GA/cle.json" >&2; exit 1; }

printf '# Written by remote-server/clients/push-secrets.sh\n%s\n%s\n' "$keys" "$DB" \
  | ssh "$SERVER" 'test -d ~/kyma/openai-ads-api && umask 077 && cat > ~/kyma/openai-ads-api/.env'
printf '# Written by remote-server/clients/push-secrets.sh\n%s\n' "$DB" \
  | ssh "$SERVER" 'test -d ~/kyma/google-analytics-export && umask 077 && cat > ~/kyma/google-analytics-export/.env'
ssh "$SERVER" 'test -d ~/kyma/google-analytics-export && umask 077 && cat > ~/kyma/google-analytics-export/cle.json' < "$GA/cle.json"

ssh "$SERVER" 'cd ~/kyma && for f in openai-ads-api/.env google-analytics-export/.env google-analytics-export/cle.json; do
  printf "%s %s: " "$(stat -c %a "$f")" "$f"; case $f in *.env) grep -v "^#" "$f" | cut -d= -f1 | tr "\n" " ";; *) echo -n "$(wc -c < "$f") bytes";; esac; echo; done'
