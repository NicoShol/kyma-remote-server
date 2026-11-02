#!/bin/bash
# Brings the server's clones up to date with GitHub's main, as deploy: git pull, then uv sync.
# The daily update (cron/kyma-daily.sh) never pulls by itself: run this after merging a PR.
#   from the laptop: ssh deploy@46.224.142.195 '~/kyma-setup/deploy/update-code.sh'
#   one repo only:   ssh deploy@46.224.142.195 '~/kyma-setup/deploy/update-code.sh openai-ads-api'
# Waits for a running daily update to finish (same lock), so the code never changes under it.
# cron/kyma-daily.sh runs it at the start of every update, holding that lock: KYMA_LOCK_HELD=1.
# Stops on a clone with local changes or not on main, and pulls fast-forward only: the
# server never makes commits of its own. Then applies openai-ads-api's schema migrations
# (tools/migrate.py, docs/webapp/2026-11-02_migrations-plan.md): ads as kyma_ingest, app as
# kyma_app, both by peer auth as deploy. A failed migration stops here, before the next daily
# update runs against tables the code doesn't expect. Log: ~/kyma/logs/update-code.log (UTC).
set -euo pipefail
export PATH="$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin"
export LC_ALL=C.UTF-8
REPOS=(openai-ads-api google-analytics-export)
LOGS=$HOME/kyma/logs
mkdir -p "$LOGS"
exec > >(tee -a "$LOGS/update-code.log") 2>&1

for r in "$@"; do
  [[ " ${REPOS[*]} " == *" $r "* ]] || { echo "Unknown repo: $r (known: ${REPOS[*]})"; exit 1; }
done
[ $# -gt 0 ] && REPOS=("$@")

if [ "${KYMA_LOCK_HELD:-}" != 1 ]; then
  exec 9>"$LOGS/.daily.lock"
  if ! flock -n 9; then
    echo "A daily update is running: waiting for it (up to 30 min)..."
    flock -w 1800 9 || { echo "Still running after 30 min: nothing changed."; exit 1; }
  fi
fi

echo "=== $(date '+%F %T %Z') update-code ${REPOS[*]}"
for r in "${REPOS[@]}"; do
  cd "$HOME/kyma/$r"
  branch=$(git branch --show-current)
  [ "$branch" = main ] || { echo "$r: on branch '$branch', not main: stopped."; exit 1; }
  if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
    echo "$r: local changes, stopped (nothing pulled):"; git status --short --untracked-files=no; exit 1
  fi
  before=$(git rev-parse HEAD)
  git pull --ff-only --quiet
  if [ "$before" = "$(git rev-parse HEAD)" ]; then
    echo "$r: already up to date ($(git log --oneline -1))"
  else
    echo "$r: $(git rev-parse --short "$before") -> $(git rev-parse --short HEAD)"
    git log --oneline "$before..HEAD" | sed 's/^/  /'
  fi
  uv sync --frozen --no-dev --quiet
done

if [[ " ${REPOS[*]} " == *" openai-ads-api "* ]]; then
  cd "$HOME/kyma/openai-ads-api"
  echo "--- schema migrations"
  uv run --frozen --no-dev tools/migrate.py ads --apply      # DATABASE_URL in .env: kyma_ingest
  uv run --frozen --no-dev tools/migrate.py app --apply --db 'postgresql://kyma_app@/kyma?host=/var/run/postgresql'
  uv run --frozen --no-dev tools/migrate.py --status
fi
echo "=== $(date '+%F %T %Z') done"
