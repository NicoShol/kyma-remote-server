#!/bin/bash
# Lets one reader machine read the encrypted API keys (app.ad_account_keys), or takes it back. From the laptop:
#   ssh -t deploy@46.224.142.195 "sudo ~/kyma-setup/postgres/grant-keys.sh <machine>"
#   ssh -t deploy@46.224.142.195 "sudo ~/kyma-setup/postgres/grant-keys.sh <machine> --revoke"
# openai-ads-api's migration app/0005 keeps that table from every reader; this adds it back for reader_<machine>
# only, through the group kyma_key_reader. The login stays read-only, and gains nothing else.
# Decrypting also needs the master key (SECRETS_MASTER_KEYS), which this doesn't give: pass it on through the
# password manager. Whoever has both can read every client's key in clear. After a --revoke, rotating the master
# key isn't enough: the keys already decrypted are out, so ask the clients for new ones if trust is gone.
# Safe to re-run.
set -euo pipefail
export LC_ALL=C.UTF-8   # the Mac sends LC_CTYPE=UTF-8, which the server lacks
[ "$(id -u)" = 0 ] || { echo "Run it with sudo." >&2; exit 1; }
[ $# = 1 ] || { [ $# = 2 ] && [ "$2" = --revoke ]; } || { echo "Usage: grant-keys.sh <machine> [--revoke]" >&2; exit 1; }
machine=$1
[[ $machine =~ ^[a-z0-9_]+$ ]] || { echo "<machine>: lowercase letters, digits and _ only." >&2; exit 1; }
[ "$machine" != deploy ] || { echo "reader_deploy is the laptop's own login: the laptop reads the keys as kyma_ingest." >&2; exit 1; }
role=reader_$machine
pg() { sudo -u postgres psql -X -q -v ON_ERROR_STOP=1 -d kyma "$@"; }
[ "$(pg -tAc "select 1 from pg_roles where rolname = '$role'")" = 1 ] || { echo "No role $role: add-reader.sh $machine first." >&2; exit 1; }

if [ "${2:-}" = --revoke ]; then
  pg <<SQL
revoke kyma_key_reader from $role;
select count(pg_terminate_backend(pid)) as sessions_ended from pg_stat_activity where usename = '$role';
SQL
  echo "$role can no longer read app.ad_account_keys (its open sessions were ended)."
  exit 0
fi

pg <<SQL
do \$\$
begin
  if not exists (select from pg_roles where rolname = 'kyma_key_reader') then
    create role kyma_key_reader nologin;
  end if;
end \$\$;
grant usage on schema app to kyma_key_reader;
grant select on app.ad_account_keys to kyma_key_reader;
grant kyma_key_reader to $role;
SQL

cat <<EOF
$role can read app.ad_account_keys (ciphertext only).
On that machine, in openai-ads-api's .env:
  SECRETS_MASTER_KEYS=...   SECRETS_ACTIVE_KEK=...   (from the password manager)
  API_KEYS_DB=postgresql://$role:<password>@localhost:<tunnel port>/kyma
Check there (decrypts, prints only a count):
  uv run python -c "import api_keys; print(len(api_keys.keys('openai')), 'openai keys')"
Who has it: list-readers.sh (column APIKEYS)
EOF
