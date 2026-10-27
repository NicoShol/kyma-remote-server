#!/bin/bash
# Step 2 of openai-ads-api/docs/2026-10-26_prod-database-plan.md: the pgtunnel SSH account.
# Run on the server, from the folder holding these files, keeping another deploy session open:
#   sudo bash setup-pgtunnel.sh
# Safe to re-run. sshd is only reloaded once the new config passes sshd -t and leaves deploy unchanged.
set -euo pipefail
cd "$(dirname "$0")"
[ "$(id -u)" = 0 ] || { echo "Run it with sudo." >&2; exit 1; }
conf=/etc/ssh/sshd_config.d/10-pgtunnel.conf
show() { sshd -T -C "user=$1,host=check,addr=192.0.2.1" | grep -E '^(allowtcpforwarding|permitopen|allowstreamlocalforwarding|allowagentforwarding|x11forwarding|permittunnel|permittty|forcecommand) ' | sort; }

if ! id pgtunnel >/dev/null 2>&1; then
  echo "--- creating the pgtunnel user (no shell, no password)"
  useradd --create-home --shell /usr/sbin/nologin pgtunnel
fi
# root owns the keys: only add-reader.sh / remove-reader.sh (run with sudo) change them
install -d -m 755 -o root -g root /home/pgtunnel/.ssh
[ -f /home/pgtunnel/.ssh/authorized_keys ] || install -m 644 -o root -g root /dev/null /home/pgtunnel/.ssh/authorized_keys

backup=/root/sshd_config.d.before-pgtunnel
[ -d "$backup" ] || cp -a /etc/ssh/sshd_config.d "$backup"
before=$(show deploy)
install -m 644 -o root -g root 10-pgtunnel.conf "$conf"
if ! sshd -t; then
  rm -f "$conf"; echo "sshd -t failed: config removed, sshd untouched." >&2; exit 1
fi
if [ "$(show deploy)" != "$before" ]; then
  rm -f "$conf"; echo "The config would change deploy's settings: removed, sshd untouched." >&2; exit 1
fi
systemctl reload ssh

echo "--- deploy (unchanged):"; show deploy
echo "--- pgtunnel:"; show pgtunnel
echo "Done. Keep this session open and check a new 'ssh deploy@...' login works before closing it."
