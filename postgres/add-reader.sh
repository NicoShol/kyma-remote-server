#!/bin/bash
# Step 8 of openai-ads-api/docs/2026-10-26_prod-database-plan.md: lets one more machine read the kyma
# database. From the operator's laptop:
#   ssh -t deploy@46.224.142.195 "sudo ~/kyma-setup/postgres/add-reader.sh <machine> '<ssh-public-key>'"
# Creates the read-only login reader_<machine> with a random password, and adds the machine's key to
# pgtunnel (tunnel to 127.0.0.1:5432 only). Prints the password once: pass it on through a password manager.
set -euo pipefail
export LC_ALL=C.UTF-8   # the Mac sends LC_CTYPE=UTF-8, which the server lacks
[ "$(id -u)" = 0 ] || { echo "Run it with sudo." >&2; exit 1; }
[ $# = 2 ] || { echo "Usage: add-reader.sh <machine> '<ssh-public-key>'" >&2; exit 1; }
machine=$1
keys=/home/pgtunnel/.ssh/authorized_keys

[[ $machine =~ ^[a-z0-9_]+$ ]] || { echo "<machine>: lowercase letters, digits and _ only." >&2; exit 1; }
[ "$machine" != deploy ] || { echo "reader_deploy is the laptop's own login: choose another name." >&2; exit 1; }
role=reader_$machine
pg() { sudo -u postgres psql -X -q -v ON_ERROR_STOP=1 "$@"; }
if [ "$(pg -tAc "select 1 from pg_roles where rolname = '$role'")" = 1 ]; then
  echo "$role already exists: remove-reader.sh $machine first to replace it." >&2; exit 1
fi

# Only the type and the key itself are kept: options or a comment sent with it never reach the file.
# Line breaks (a key copied from a wrapped terminal) count as spaces.
read -r type blob _ <<< "$(tr -s '[:space:]' ' ' <<< "$2")"
case $type in
  ssh-ed25519|ecdsa-sha2-nistp256|ecdsa-sha2-nistp384|ecdsa-sha2-nistp521|ssh-rsa) ;;
  *) echo "Not an SSH public key (type '$type')." >&2; exit 1 ;;
esac
[[ $blob =~ ^[A-Za-z0-9+/]+=*$ ]] || { echo "Not an SSH public key." >&2; exit 1; }
fingerprint=$(ssh-keygen -l -f /dev/stdin <<< "$type $blob") || { echo "Not a valid SSH public key." >&2; exit 1; }
if grep -qF " $blob " "$keys"; then echo "This key is already there: $(grep -F " $blob " "$keys" | awk '{print $NF}')." >&2; exit 1; fi

pw=$(openssl rand -base64 32 | tr -dc 'A-Za-z0-9' | head -c 32)
# Through stdin, never a command line. log_min_error_statement keeps the statement out of the log if it fails.
pg -d kyma <<SQL
set log_min_error_statement = panic;
\set pw '$pw'
create role $role login in role kyma_reader connection limit 5 password :'pw';
alter role $role set default_transaction_read_only = on;
alter role $role set statement_timeout = '60s';
SQL
echo "restrict,port-forwarding,permitopen=\"127.0.0.1:5432\" $type $blob $role" >> "$keys"

cat <<EOF

Added $role.
  key:      $fingerprint
  password: $pw
  (shown once only: put it in the password manager now, and clear this terminal)

Server host key, for the reader to check on its first connection:
$(for f in /etc/ssh/ssh_host_ed25519_key.pub /etc/ssh/ssh_host_ecdsa_key.pub; do [ -f "$f" ] && ssh-keygen -l -f "$f"; done)
EOF
