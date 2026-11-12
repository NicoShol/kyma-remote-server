# remote-server

Setup of the organisation server `46.224.142.195` (Ubuntu 26.04, arm64), as applied to it.
Everything installed on the server comes from here, so the server can be rebuilt from this repo
and a database dump. The plan and its reasons: `openai-ads-api/docs/old/2026-10-26_prod-database-plan.md`.

**No secrets in this repo** (passwords, API keys, `cle.json`): they live only on the machines that use them.

| Folder | What | Installed by |
|---|---|---|
| `postgres/` | Postgres 17 (apt.postgresql.org): config, `pg_hba`/`pg_ident`, the `kyma` database and roles | `sudo bash install.sh` (step 1) |
| `postgres/add-app-role.sh` | The Kyma platform's schema `app` and its login `kyma_app` (writes `app` only; no password, peer auth as `deploy`) | `ssh -t deploy@… "sudo bash ~/kyma-setup/postgres/add-app-role.sh"`; also run by `install.sh` |
| `postgres/*-reader*.sh` | `add-reader.sh <machine> '<key>'`, `remove-reader.sh <machine>`, `list-readers.sh`: the reader machines (role `reader_<machine>` + `pgtunnel` key) | `ssh -t deploy@… "sudo ~/kyma-setup/postgres/<script> …"` (step 8) |
| `ssh/` | The `pgtunnel` account: reader machines can only forward to Postgres | `sudo bash setup-pgtunnel.sh` (step 2) |
| `cron/` | `kyma-daily.sh`: the update of the prod database as `deploy`, 4 times a day (00:00, 06:00, 12:00, 18:00 UTC), one log per day in `~/kyma/logs/`. Each run first deploys GitHub's `main` (`update-code.sh`: pull, `uv sync`, migrations) and logs the commit it ran | `deploy`'s crontab (step 6) |
| `deploy/` | `update-code.sh [repo…]`: brings the server's clones of openai-ads-api and google-analytics-export up to date with `main` (`git pull --ff-only` + `uv sync`), after a PR is merged, then applies the schema migrations (`tools/migrate.py`): openai-ads-api's `ads` as `kyma_ingest` and `app` as `kyma_app`, then google-analytics-export's `ga` as `kyma_ingest`. Waits for a running daily update; stops on local changes or a failed migration | `ssh deploy@46.224.142.195 '~/kyma-setup/deploy/update-code.sh'` |
| `platform/` | The Kyma platform (openai-ads-api `webapp/api/run.py`: the page, `/api`, the public API `/v1`) on **https://kyma-solutions.eu**, next to the website: `/platform/` (the page), `/api/`, `/v1/` (docs at `/v1/docs`). A systemd **user** service of `deploy` (`kyma-platform`, on 127.0.0.1:8780), behind nginx: a snippet included by one line in the website's server block, plus request limits per address (logins 10/min, API 10/s, 20 connections) and for the whole server (logins 60/min, API 100/s). `update-code.sh` restarts it after new code | `sudo bash install.sh` once (linger, nginx), then `start.sh` as `deploy` (below, "Hosting the platform") |
| `backup/` | `kyma-pg-backup.sh`: daily `pg_dump` of `kyma` (06:30 UTC) into `~/backups/kyma-pg/`, kept 60 days | `deploy`'s crontab (step 7) |
| `clients/push-secrets.sh` | Copies the master key of the encrypted API keys (`SECRETS_MASTER_KEYS`, `SECRETS_ACTIVE_KEK` of the laptop's `openai-ads-api/.env`, checked first) and `cle.json` to the server's clones (mode 600, through SSH's stdin). The API keys themselves are in the database (openai-ads-api `docs/webapp/2026-11-09_api_keys_stored_encrypted_master_key_env.md`); removes the server's old `api_keys.toml` | run on the laptop (step 6), and after changing the master key |
| `clients/macos/` | The laptop's tunnel (`eu.kyma.pg-tunnel.plist`): localhost:5433 → the server's Postgres socket, as `deploy` | copy to `~/Library/LaunchAgents/`, `launchctl bootstrap` (step 4) |
| `clients/macos/` | `pull-backups.sh` + `eu.kyma.pg-backup-pull.plist`: the laptop pulls the dumps to `~/Backups/kyma/server/` at 19:00 (local time) | same (step 7) |
| `howtos/` | `postgre-connexion.md`: how the laptop connects to the prod Postgres (fields, tunnel, `pg_hba`), and what to do when it doesn't | to read |

## Applying a change

The server's `sudo` asks for a password, so copy the folder as `deploy`, then run the script yourself:

```
scp -r postgres ssh deploy@46.224.142.195:kyma-setup/
ssh -t deploy@46.224.142.195 'sudo bash ~/kyma-setup/postgres/install.sh'
```

## Hosting the platform

openai-ads-api's `docs/webapp/2026-11-10_public-api-plan.md`, P2. The platform shares kyma-solutions.eu
(and its certificate) with the website: nginx sends `/platform/`, `/api/` and `/v1/` to it, everything else
to the website. Nothing to add in DNS.

1. **Code:** openai-ads-api's `main` with P2 merged, on the server (`deploy/update-code.sh`, or the next daily update).
2. **Files:** `scp -r platform deploy deploy@46.224.142.195:kyma-setup/` (`deploy/` too: its `update-code.sh` restarts the platform).
3. **Once, with sudo:** `ssh -t deploy@46.224.142.195 'sudo bash ~/kyma-setup/platform/install.sh'`
   - linger for `deploy` (its user services run without a login, and at boot);
   - nginx: `conf.d/kyma-platform-zones.conf`, `snippets/kyma-platform.conf` and `kyma-platform-proxy.conf`,
     and `include /etc/nginx/snippets/kyma-platform.conf;` added to `/etc/nginx/sites-available/kyma-solutions.eu`
     after its `client_max_body_size` line. A failed `nginx -t` puts everything back.
   - **Then add the same include line to kyma-website's snapshot** (`deploy/nginx-kyma-solutions.eu.conf`),
     so the website's repo matches the server.
4. **As deploy:** `ssh deploy@46.224.142.195 '~/kyma-setup/platform/start.sh'`: installs
   `~/.config/systemd/user/kyma-platform.service`, starts it and waits for `http://127.0.0.1:8780/healthz`.
5. **Check from the laptop:** `curl -s https://kyma-solutions.eu/v1/me` answers
   `{"error": {"code": "unauthorized", …}}`; https://kyma-solutions.eu/platform/ shows the login;
   https://kyma-solutions.eu/v1/docs the API's documentation.
6. **Users and tokens** (openai-ads-api's README): with `PLATFORM_BASE_URL=https://kyma-solutions.eu/platform`
   in the laptop's `.env`, `webapp/admin.py users add|link` print links to the hosted page.

Every day after: `update-code.sh` (after a merge, and at the start of each daily update) restarts the platform
when openai-ads-api's code changed, after its migrations, then checks `/healthz`.

- **Status and output:** `systemctl --user status kyma-platform`, `journalctl --user -u kyma-platform -n 50` (as `deploy`).
- **Requests:** `/var/log/nginx/kyma-platform.access.log`; every `/v1` call also in `app.api_requests` (90 days).
- **Stop it:** `systemctl --user disable --now kyma-platform`; nginx then answers 502 on the three paths.
  To give them back to the website, remove the include line and `sudo systemctl reload nginx`.

## Access model

- **Writes:** Unix user `deploy` only, through peer auth on the Postgres socket; no write password exists.
  - `kyma_ingest` writes `ads` and `ga` (ingestion).
  - `kyma_app` writes `app` only: the Kyma platform's clients, advertisers and who owns which ad account. It reads `ads` and `ga` as a reader.
- **Reads:** one `reader_<machine>` login per machine, through the `pgtunnel` SSH account (step 2).
- Postgres listens on localhost only; port 5432 is never opened in `ufw`.
# kyma-remote-server

## Time zone

The server runs on **UTC**, and so does everything it does: cron schedules, logs, and the times it stores.
Since plan C (`openai-ads-api/docs/old/2026-10-29_utc-plan.md`), every stored time is UTC wherever it was
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
