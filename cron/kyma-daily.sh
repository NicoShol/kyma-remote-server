#!/bin/bash
# Update of the prod database, as deploy, 4 times a day (openai-ads-api/docs/2026-10-26_prod-database-plan.md,
# step 6): OpenAI Ads and Thrad (openai-ads-api/tools/daily_update.py), then Google Analytics
# (google-analytics-export/main.py). One log per day in ~/kyma/logs/ (every run of the day
# appends to it), kept 60 days.
#
# Everything here is in UTC, the server's time zone: the schedule, the log, the dates of
# "today", and the update_time that ads_db.py writes (the laptop writes Paris time instead;
# thrad_db.py always writes UTC with a Z).
# crontab of deploy, at 00:00, 06:00, 12:00 and 18:00 UTC:
#   0 0,6,12,18 * * * /home/deploy/kyma-setup/cron/kyma-daily.sh
# By hand, now: ~/kyma-setup/cron/kyma-daily.sh
# The code isn't pulled here: updating it stays deliberate, with deploy/update-code.sh.
set -uo pipefail
export PATH="$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin"   # cron's PATH has no uv
export LC_ALL=C.UTF-8
LOGS=$HOME/kyma/logs
mkdir -p "$LOGS"
log="$LOGS/daily-$(date +%F).log"
exec 9>"$LOGS/.daily.lock"
if ! flock -n 9; then
  echo "$(date '+%F %T') an update is already running: skipped" >> "$log"
  exit 0
fi

status=0
{
  echo "=== $(date '+%F %T %Z') start"
  cd "$HOME/kyma/openai-ads-api" && uv run --frozen --no-dev tools/daily_update.py || status=1
  cd "$HOME/kyma/google-analytics-export" && uv run --frozen --no-dev main.py || status=1   # reads ./cle.json
  echo "=== $(date '+%F %T %Z') end, $([ $status = 0 ] && echo OK || echo FAILED)"
} >> "$log" 2>&1
find "$LOGS" -name 'daily-*.log' -mtime +60 -delete
exit $status
