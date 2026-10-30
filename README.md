# remote-server

Setup of the organisation server `46.224.142.195` (Ubuntu 26.04, arm64), as applied to it.
Everything installed on the server comes from here, so the server can be rebuilt from this repo
and a database dump. The plan and its reasons: `openai-ads-api/docs/2026-10-26_prod-database-plan.md`.

**No secrets in this repo** (passwords, API keys, `cle.json`): they live only on the machines that use them.

| Folder | What | Installed by |
|---|---|---|
| `postgres/` | Postgres 17 (apt.postgresql.org): config, `pg_hba`/`pg_ident`, the `kyma` database and roles | `sudo bash install.sh` (step 1) |
| `postgres/add-app-role.sh` | The Kyma platform's schema `app` and its login `kyma_app` (writes `app` only; no password, peer auth as `deploy`) | `ssh -t deploy@… "sudo bash ~/kyma-setup/postgres/add-app-role.sh"`; also run by `install.sh` |
| `postgres/*-reader*.sh` | `add-reader.sh <machine> '<key>'`, `remove-reader.sh <machine>`, `list-readers.sh`: the reader machines (role `reader_<machine>` + `pgtunnel` key) | `ssh -t deploy@… "sudo ~/kyma-setup/postgres/<script> …"` (step 8) |
| `ssh/` | The `pgtunnel` account: reader machines can only forward to Postgres | `sudo bash setup-pgtunnel.sh` (step 2) |
| `cron/` | `kyma-daily.sh`: the update of the prod database as `deploy`, 4 times a day (00:00, 06:00, 12:00, 18:00 UTC), one log per day in `~/kyma/logs/` | `deploy`'s crontab (step 6) |
| `deploy/` | `update-code.sh [repo…]`: brings the server's clones of openai-ads-api and google-analytics-export up to date with `main` (`git pull --ff-only` + `uv sync`), after a PR is merged. Waits for a running daily update; stops on local changes | `ssh deploy@46.224.142.195 '~/kyma-setup/deploy/update-code.sh'` |
| `backup/` | `kyma-pg-backup.sh`: daily `pg_dump` of `kyma` (06:30 UTC) into `~/backups/kyma-pg/`, kept 60 days | `deploy`'s crontab (step 7) |
| `clients/push-secrets.sh` | Copies the API keys and `cle.json` to the server's clones (mode 600, through SSH's stdin) | run on the laptop (step 6) |
| `clients/macos/` | The laptop's tunnel (`eu.kyma.pg-tunnel.plist`): localhost:5433 → the server's Postgres socket, as `deploy` | copy to `~/Library/LaunchAgents/`, `launchctl bootstrap` (step 4) |
| `clients/macos/` | `pull-backups.sh` + `eu.kyma.pg-backup-pull.plist`: the laptop pulls the dumps to `~/Backups/kyma/server/` at 19:00 (local time) | same (step 7) |
| `howtos/` | `postgre-connexion.md`: how the laptop connects to the prod Postgres (fields, tunnel, `pg_hba`), and what to do when it doesn't | to read |

## Applying a change

The server's `sudo` asks for a password, so copy the folder as `deploy`, then run the script yourself:

```
scp -r postgres ssh deploy@46.224.142.195:kyma-setup/
ssh -t deploy@46.224.142.195 'sudo bash ~/kyma-setup/postgres/install.sh'
```

## Access model

- **Writes:** Unix user `deploy` only, through peer auth on the Postgres socket; no write password exists.
  - `kyma_ingest` writes `ads` and `ga` (ingestion).
  - `kyma_app` writes `app` only: the Kyma platform's clients, advertisers and who owns which ad account. It reads `ads` and `ga` as a reader.
- **Reads:** one `reader_<machine>` login per machine, through the `pgtunnel` SSH account (step 2).
- Postgres listens on localhost only; port 5432 is never opened in `ufw`.
# kyma-remote-server

## Time zone

The server runs on **UTC**, and so does everything it does: cron schedules, logs, and the times it stores.
Since plan C (`openai-ads-api/docs/2026-10-29_utc-plan.md`), every stored time is UTC wherever it was
written, laptop included: `update_time` with a `Z`, OpenAI's report keyed on the UTC hour, GA's hours and
days in UTC. Only OpenAI's own conversions and reach stay on Paris days: the API has nothing else.

## GitHub access

The server clones with one **read-only deploy key per repo** (`~/.ssh/gh_<repo>`, through the host aliases
`github-ads` and `github-ga` in `~/.ssh/config`); the `github.com` entry is kyma-website's own key.
Revoke a key in the repo's Settings → Deploy keys.

## Restoring a dump

Into an empty database owned by `kyma_ingest`, so the restored tables belong to it:
```
pg_restore --no-owner --no-acl --role=kyma_ingest -d <database> kyma-YYYY-MM-DD.dump
```
