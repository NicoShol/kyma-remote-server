# remote-server

Setup of the organisation server `46.224.142.195` (Ubuntu 26.04, arm64), as applied to it.
Everything installed on the server comes from here, so the server can be rebuilt from this repo
and a database dump. The plan and its reasons: `openai-ads-api/docs/2026-10-26_prod-database-plan.md`.

**No secrets in this repo** (passwords, API keys, `cle.json`): they live only on the machines that use them.

| Folder | What | Installed by |
|---|---|---|
| `postgres/` | Postgres 17 (apt.postgresql.org): config, `pg_hba`/`pg_ident`, the `kyma` database and roles | `sudo bash install.sh` (step 1) |
| `postgres/*-reader*.sh` | `add-reader.sh <machine> '<key>'`, `remove-reader.sh <machine>`, `list-readers.sh`: the reader machines (role `reader_<machine>` + `pgtunnel` key) | `ssh -t deploy@… "sudo ~/kyma-setup/postgres/<script> …"` (step 8) |
| `ssh/` | The `pgtunnel` account: reader machines can only forward to Postgres | `sudo bash setup-pgtunnel.sh` (step 2) |
| `cron/` | `kyma-daily.sh`: the daily update of the prod database as `deploy` (06:00 UTC), logs in `~/kyma/logs/` | `deploy`'s crontab (step 6) |
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

- **Writes:** Unix user `deploy` only (peer auth to `kyma_ingest` on the Postgres socket); no write password exists.
- **Reads:** one `reader_<machine>` login per machine, through the `pgtunnel` SSH account (step 2).
- Postgres listens on localhost only; port 5432 is never opened in `ufw`.
# kyma-remote-server

## Time zone

The server runs on **UTC**, and so does everything it does: cron schedules, logs, and the `update_time` that
`ads_db.py` writes there. The laptop writes Paris time; `thrad_db.py` always writes UTC (with a `Z`).

## GitHub access

The server clones with one **read-only deploy key per repo** (`~/.ssh/gh_<repo>`, through the host aliases
`github-ads` and `github-ga` in `~/.ssh/config`); the `github.com` entry is kyma-website's own key.
Revoke a key in the repo's Settings → Deploy keys.

## Restoring a dump

Into an empty database owned by `kyma_ingest`, so the restored tables belong to it:
```
pg_restore --no-owner --no-acl --role=kyma_ingest -d <database> kyma-YYYY-MM-DD.dump
```
