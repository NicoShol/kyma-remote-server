#!/bin/bash
# Gives the server's cron what it needs to call the APIs (openai-ads-api/docs/old/2026-10-26_prod-database-plan.md,
# step 6). Run on the laptop, after the repos are cloned in ~/kyma on the server:
#   bash ~/kyma/remote-server/clients/push-secrets.sh
# The secrets go through ssh's stdin (never on a command line), into mode-600 files on the server.
# Re-run it after changing the master key. Nothing is printed but the names of the settings.
# The ad platforms' API keys are in the database, encrypted
# (openai-ads-api/docs/webapp/2026-11-09_api_keys_stored_encrypted_master_key_env.md): the server
# only needs the master key that opens them (SECRETS_MASTER_KEYS, SECRETS_ACTIVE_KEK of the
# laptop's openai-ads-api/.env). Its old api_keys.toml and .env keys are removed.
set -euo pipefail
SERVER=deploy@46.224.142.195
ADS=$HOME/kyma/openai-ads-api
GA=$HOME/kyma/google-analytics-export
# The server writes as Unix user deploy through the local socket (peer auth): no password.
DB='DATABASE_URL=postgresql://kyma_ingest@/kyma?host=/var/run/postgresql
DATABASE_URL_RO=postgresql://reader_deploy@/kyma?host=/var/run/postgresql'

# Checked with the repo's own vault.py: prints the provider and the active key's id, never a key.
echo "$ADS/.env master key:"
(cd "$ADS" && uv run --quiet python -c '
import vault
print("  " + vault.registry().describe())') || { echo "Fix SECRETS_MASTER_KEYS / SECRETS_ACTIVE_KEK in $ADS/.env first: nothing was copied." >&2; exit 1; }
master=$(grep -E '^(SECRETS_MASTER_KEYS|SECRETS_ACTIVE_KEK|SECRETS_KEY_PROVIDER)=' "$ADS/.env" || true)
printf '%s\n' "$master" | grep -q '^SECRETS_MASTER_KEYS=' || { echo "SECRETS_MASTER_KEYS must be in $ADS/.env" >&2; exit 1; }
[ -f "$GA/cle.json" ] || { echo "Missing $GA/cle.json" >&2; exit 1; }

printf '# Written by remote-server/clients/push-secrets.sh\n%s\n%s\n' "$DB" "$master" \
  | ssh "$SERVER" 'test -d ~/kyma/openai-ads-api && umask 077 && cat > ~/kyma/openai-ads-api/.env'
ssh "$SERVER" 'rm -f ~/kyma/openai-ads-api/api_keys.toml'   # the keys are in the database now
printf '# Written by remote-server/clients/push-secrets.sh\n%s\n' "$DB" \
  | ssh "$SERVER" 'test -d ~/kyma/google-analytics-export && umask 077 && cat > ~/kyma/google-analytics-export/.env'
ssh "$SERVER" 'test -d ~/kyma/google-analytics-export && umask 077 && cat > ~/kyma/google-analytics-export/cle.json' < "$GA/cle.json"

ssh "$SERVER" 'cd ~/kyma && for f in openai-ads-api/.env openai-ads-api/api_keys.toml google-analytics-export/.env google-analytics-export/cle.json; do
  [ -f "$f" ] || continue
  printf "%s %s: " "$(stat -c %a "$f")" "$f"
  case $f in
    *.env) grep -v "^#" "$f" | cut -d= -f1 | tr "\n" " ";;
    *) echo -n "$(wc -c < "$f") bytes";;
  esac; echo; done'
