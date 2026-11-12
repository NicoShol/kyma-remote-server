#!/bin/bash
# Installs (or refreshes) the platform's user service and (re)starts it, as deploy, no sudo:
#   ssh deploy@46.224.142.195 '~/kyma-setup/platform/start.sh'
# After install.sh (linger). Then waits for http://127.0.0.1:8780/healthz: both database logins
# answer. Later restarts: deploy/update-code.sh, after a merge.
set -euo pipefail
cd "$(dirname "$0")"
export XDG_RUNTIME_DIR=/run/user/$(id -u)
[ "$(loginctl show-user "$(id -un)" -p Linger --value)" = yes ] \
  || { echo "Linger is off for $(id -un): run sudo bash ~/kyma-setup/platform/install.sh first." >&2; exit 1; }
grep -q '^DATABASE_URL_RO=' ~/kyma/openai-ads-api/.env \
  || { echo "~/kyma/openai-ads-api/.env has no DATABASE_URL_RO (the reader login): see its README." >&2; exit 1; }

mkdir -p ~/.config/systemd/user
install -m 644 kyma-platform.service ~/.config/systemd/user/kyma-platform.service
systemctl --user daemon-reload
systemctl --user enable --quiet kyma-platform
systemctl --user restart kyma-platform
for _ in $(seq 1 30); do
  if curl -sf http://127.0.0.1:8780/healthz; then
    echo; echo "kyma-platform is up: https://kyma-solutions.eu/platform/ and https://kyma-solutions.eu/v1/docs"
    exit 0
  fi
  sleep 1
done
echo "kyma-platform isn't healthy after 30 s:" >&2
systemctl --user status kyma-platform --no-pager -n 0 >&2 || true
journalctl --user -u kyma-platform -n 40 --no-pager >&2 || true
exit 1
