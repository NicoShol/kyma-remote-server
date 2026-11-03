#!/bin/bash
# Gives the server's cron what it needs to call the APIs (openai-ads-api/docs/old/2026-10-26_prod-database-plan.md,
# step 6). Run on the laptop, after the repos are cloned in ~/kyma on the server:
#   bash ~/kyma/remote-server/clients/push-secrets.sh
# The keys go through ssh's stdin (never on a command line), into mode-600 files on the server.
# Re-run it after changing a key. Nothing is printed but the names of the settings.
# Several ad accounts (openai-ads-api/docs/2026-11-03_several-ad-accounts-plan.md): with
# openai-ads-api/api_keys.toml on the laptop, it's checked, copied, and replaces the two keys
# of .env; without it, the server's copy is removed, so .env's keys are used again.
set -euo pipefail
SERVER=deploy@46.224.142.195
ADS=$HOME/kyma/openai-ads-api
GA=$HOME/kyma/google-analytics-export
# The server writes as Unix user deploy through the local socket (peer auth): no password.
DB='DATABASE_URL=postgresql://kyma_ingest@/kyma?host=/var/run/postgresql
DATABASE_URL_RO=postgresql://reader_deploy@/kyma?host=/var/run/postgresql'

KEYS_FILE=$ADS/api_keys.toml
if [ -f "$KEYS_FILE" ]; then
  # Read with the repo's own api_keys.py: prints platform, account and label, never a key.
  echo "$KEYS_FILE:"
  (cd "$ADS" && API_KEYS_FILE="$KEYS_FILE" uv run --quiet python -c '
import api_keys
ks = [k for p in api_keys.PLATFORMS for k in api_keys.keys(p)]
if not ks:
    raise SystemExit("no [[key]]")
for k in ks:
    print(f"  {k}")') || { echo "Fix $KEYS_FILE first: nothing was copied." >&2; exit 1; }
  env_lines=$DB
else
  keys=$(grep -E '^(OPENAI_ADS_API_KEY|THRAD_ADS_API_KEY)=' "$ADS/.env")
  [ "$(printf '%s\n' "$keys" | wc -l)" -eq 2 ] || { echo "Expected both API keys in $ADS/.env" >&2; exit 1; }
  env_lines=$(printf '%s\n%s' "$keys" "$DB")
fi
[ -f "$GA/cle.json" ] || { echo "Missing $GA/cle.json" >&2; exit 1; }

printf '# Written by remote-server/clients/push-secrets.sh\n%s\n' "$env_lines" \
  | ssh "$SERVER" 'test -d ~/kyma/openai-ads-api && umask 077 && cat > ~/kyma/openai-ads-api/.env'
if [ -f "$KEYS_FILE" ]; then
  ssh "$SERVER" 'test -d ~/kyma/openai-ads-api && umask 077 && cat > ~/kyma/openai-ads-api/api_keys.toml' < "$KEYS_FILE"
else
  ssh "$SERVER" 'rm -f ~/kyma/openai-ads-api/api_keys.toml'   # else it would still win over .env
fi
printf '# Written by remote-server/clients/push-secrets.sh\n%s\n' "$DB" \
  | ssh "$SERVER" 'test -d ~/kyma/google-analytics-export && umask 077 && cat > ~/kyma/google-analytics-export/.env'
ssh "$SERVER" 'test -d ~/kyma/google-analytics-export && umask 077 && cat > ~/kyma/google-analytics-export/cle.json' < "$GA/cle.json"

ssh "$SERVER" 'cd ~/kyma && for f in openai-ads-api/.env openai-ads-api/api_keys.toml google-analytics-export/.env google-analytics-export/cle.json; do
  [ -f "$f" ] || continue
  printf "%s %s: " "$(stat -c %a "$f")" "$f"
  case $f in
    *.env) grep -v "^#" "$f" | cut -d= -f1 | tr "\n" " ";;
    *.toml) echo -n "$(grep -c "^\[\[key\]\]" "$f") key(s)";;
    *) echo -n "$(wc -c < "$f") bytes";;
  esac; echo; done'
