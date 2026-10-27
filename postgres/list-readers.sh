#!/bin/bash
# Step 8 of openai-ads-api/docs/2026-10-26_prod-database-plan.md: who can read, and when they last did.
#   ssh -t deploy@46.224.142.195 "sudo ~/kyma-setup/postgres/list-readers.sh"
# A role without a key line, or a key line without a role, is shown as such: neither half alone reads anything.
set -euo pipefail
export LC_ALL=C.UTF-8   # the Mac sends LC_CTYPE=UTF-8, which the server lacks
[ "$(id -u)" = 0 ] || { echo "Run it with sudo." >&2; exit 1; }
keys=/home/pgtunnel/.ssh/authorized_keys
log=/var/log/postgresql/postgresql-17-main.log   # rotated weekly: "never" means not since the last rotation

roles=$(sudo -u postgres psql -XtAc "select rolname from pg_roles where rolname like 'reader\_%' and rolname <> 'reader_deploy' order by 1")
key_roles=$(awk '{print $NF}' "$keys" | sort -u)
printf '%-24s %-5s %-5s %s\n' ROLE ROLE KEY "LAST CONNECTION (server log, Europe/Paris)"
for r in $(printf '%s\n%s\n' "$roles" "$key_roles" | grep . | sort -u); do
  has_role=$(grep -qx "$r" <<< "$roles" && echo yes || echo NO)
  has_key=$(grep -qx "$r" <<< "$key_roles" && echo yes || echo NO)
  last=$(grep -h "connection authorized: user=$r " "$log" 2>/dev/null | tail -1 | cut -c1-19)
  printf '%-24s %-5s %-5s %s\n' "$r" "$has_role" "$has_key" "${last:-never}"
done
echo
echo "key fingerprints:"
while read -r line; do
  [ -n "$line" ] && echo "  $(ssh-keygen -l -f /dev/stdin <<< "${line#* }")"
done < "$keys"
echo "open pgtunnel SSH sessions: $(pgrep -c -u pgtunnel sshd || true)"
