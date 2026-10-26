# remote-server

Setup of the organisation server `46.224.142.195` (Ubuntu 26.04, arm64), as applied to it.
Everything installed on the server comes from here, so the server can be rebuilt from this repo
and a database dump. The plan and its reasons: `openai-ads-api/docs/2026-10-26_prod-database-plan.md`.

**No secrets in this repo** (passwords, API keys, `cle.json`): they live only on the machines that use them.

| Folder | What | Installed by |
|---|---|---|
| `postgres/` | Postgres 17 (apt.postgresql.org): config, `pg_hba`/`pg_ident`, the `kyma` database and roles | `sudo bash install.sh` (step 1) |

## Applying a change

The server's `sudo` asks for a password, so copy the folder as `deploy`, then run the script yourself:

```
scp -r postgres deploy@46.224.142.195:kyma-setup
ssh -t deploy@46.224.142.195 'sudo bash ~/kyma-setup/install.sh'
```

## Access model

- **Writes:** Unix user `deploy` only (peer auth to `kyma_ingest` on the Postgres socket); no write password exists.
- **Reads:** one `reader_<machine>` login per machine, through the `pgtunnel` SSH account (step 2, to come).
- Postgres listens on localhost only; port 5432 is never opened in `ufw`.
# kyma-remote-server
