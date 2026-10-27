#!/bin/bash
# Step 8 of openai-ads-api/docs/2026-10-26_prod-database-plan.md: cuts one reader machine off. From the laptop:
#   ssh -t deploy@46.224.142.195 "sudo ~/kyma-setup/postgres/remove-reader.sh <machine>"
# Removes its pgtunnel key, ends its database sessions and drops reader_<machine>. Safe to re-run.
set -euo pipefail
export LC_ALL=C.UTF-8   # the Mac sends LC_CTYPE=UTF-8, which the server lacks
[ "$(id -u)" = 0 ] || { echo "Run it with sudo." >&2; exit 1; }
[ $# = 1 ] || { echo "Usage: remove-reader.sh <machine>" >&2; exit 1; }
machine=$1
keys=/home/pgtunnel/.ssh/authorized_keys
[[ $machine =~ ^[a-z0-9_]+$ ]] || { echo "<machine>: lowercase letters, digits and _ only." >&2; exit 1; }
[ "$machine" != deploy ] || { echo "reader_deploy is the laptop's own login, not a reader machine." >&2; exit 1; }
role=reader_$machine

kept=$(mktemp)
grep -v " $role\$" "$keys" > "$kept" || true
removed=$(( $(wc -l < "$keys") - $(wc -l < "$kept") ))
install -m 644 -o root -g root "$kept" "$keys"
rm -f "$kept"
echo "key lines removed: $removed"

sudo -u postgres psql -X -q -v ON_ERROR_STOP=1 -d kyma <<SQL
select count(pg_terminate_backend(pid)) as sessions_ended from pg_stat_activity where usename = '$role';
drop role if exists $role;
SQL
echo "role $role dropped (if it existed)"

# A removed key doesn't close a tunnel already open. The other readers' tunnels reconnect by themselves.
pkill -u pgtunnel && echo "pgtunnel SSH sessions ended" || echo "no pgtunnel SSH session open"
