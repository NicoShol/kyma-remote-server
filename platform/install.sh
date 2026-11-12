#!/bin/bash
# The Kyma platform on kyma-solutions.eu (openai-ads-api docs/webapp/2026-11-10_public-api-plan.md, P2),
# the part that needs sudo. Once, then after changing a file of this folder. From the laptop:
#   scp -r platform deploy@46.224.142.195:kyma-setup/
#   ssh -t deploy@46.224.142.195 'sudo bash ~/kyma-setup/platform/install.sh'
# then, as deploy (no sudo): ~/kyma-setup/platform/start.sh
#
# 1. linger for deploy: its user services (kyma-platform) run without a login, and start at boot;
# 2. nginx: the request limits (conf.d), the platform's locations (snippets), and one include line
#    in the website's HTTPS server block (/etc/nginx/sites-available/kyma-solutions.eu), added
#    once after its client_max_body_size line. The site's file is copied first; if nginx -t
#    fails, everything is put back as it was and nginx isn't reloaded.
# The website's repo (kyma-website, deploy/nginx-kyma-solutions.eu.conf) keeps a snapshot of the
# site's file: add the same include line there.
# Safe to re-run.
set -euo pipefail
export LC_ALL=C.UTF-8
cd "$(dirname "$0")"
[ "$(id -u)" = 0 ] || { echo "Run it with sudo." >&2; exit 1; }

SITE=/etc/nginx/sites-available/kyma-solutions.eu
INCLUDE="include /etc/nginx/snippets/kyma-platform.conf;"
[ -f "$SITE" ] || { echo "$SITE is missing: the website's nginx site comes first (kyma-website)." >&2; exit 1; }

loginctl enable-linger deploy
echo "linger: $(loginctl show-user deploy -p Linger --value)"

backup=$(mktemp -d)
cp -a "$SITE" "$backup/site"
for f in /etc/nginx/conf.d/kyma-platform-zones.conf /etc/nginx/snippets/kyma-platform.conf \
         /etc/nginx/snippets/kyma-platform-proxy.conf; do
  [ -f "$f" ] && cp -a "$f" "$backup/$(basename "$f")"
done
restore() {
  echo "nginx -t failed: putting everything back." >&2
  cp -a "$backup/site" "$SITE"
  for f in kyma-platform-zones.conf; do
    if [ -f "$backup/$f" ]; then cp -a "$backup/$f" /etc/nginx/conf.d/; else rm -f "/etc/nginx/conf.d/$f"; fi
  done
  for f in kyma-platform.conf kyma-platform-proxy.conf; do
    if [ -f "$backup/$f" ]; then cp -a "$backup/$f" /etc/nginx/snippets/; else rm -f "/etc/nginx/snippets/$f"; fi
  done
  nginx -t
  exit 1
}

install -m 644 nginx-platform-zones.conf /etc/nginx/conf.d/kyma-platform-zones.conf
install -m 644 nginx-platform.conf /etc/nginx/snippets/kyma-platform.conf
install -m 644 nginx-platform-proxy.conf /etc/nginx/snippets/kyma-platform-proxy.conf

if grep -qF "$INCLUDE" "$SITE"; then
  echo "$SITE already includes the platform"
else
  # After the first client_max_body_size: the HTTPS server block (certbot's redirect block has none).
  grep -q '^\s*client_max_body_size' "$SITE" || { echo "No client_max_body_size line in $SITE: add the include by hand." >&2; restore; }
  sed -i "0,/^\s*client_max_body_size.*;/s||&\n\n    # The Kyma platform: /platform/, /api/, /v1/ (remote-server platform/)\n    $INCLUDE|" "$SITE"
  echo "added to $SITE: $INCLUDE"
fi

nginx -t || restore
systemctl reload nginx
echo "nginx reloaded. Backup of the previous files: $backup"
echo "Next, as deploy: ~/kyma-setup/platform/start.sh"
