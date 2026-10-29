# Connecting to the prod Postgres from the laptop

How the operator's laptop reaches the `kyma` database on the server (46.224.142.195), and why no password is needed. For the setup itself, see `openai-ads-api/docs/2026-10-26_prod-database-plan.md` (steps 1, 2 and 4). For reader machines, see `openai-ads-api/HOWTO_DB.md` §7.

**In short:** an SSH tunnel, run as `deploy`, brings Postgres to `localhost:5433`. Postgres trusts the Unix user `deploy`, so the SSH key is the only credential.

## The connection fields

Connection string (read-only):

```
postgresql://reader_deploy@localhost:5433/kyma
```

Or, field by field (VS Code's Database Client, DBeaver, TablePlus…):

| Field | Value | What it means |
|---|---|---|
| **Host** | `localhost` | The laptop itself. The client never talks to the server directly, only to the tunnel's entrance on the laptop. |
| **Port** | `5433` | Where the tunnel listens. Port `5432` on the laptop is the local test container, a different database (its `kyma` is a stale copy from 2026-10-26). |
| **Username** | `reader_deploy` | A **Postgres** login, not a Unix account. `reader_deploy` can only read; `kyma_ingest` can write. No other login works through this tunnel. |
| **Password** | *(empty)* | Not needed: the server identifies the caller another way (step 4 below). |
| **Database** | `kyma` | The prod database. Tables are in the `ads` and `ga` schemas. |
| **SSL** | off | The tunnel is already encrypted. |

The connection string packs the same fields: `postgresql://<user>@<host>:<port>/<database>`.

To write (only when you mean to change data): `postgresql://kyma_ingest@localhost:5433/kyma`.

## The route

```
client ──► localhost:5433 ══════ SSH, encrypted ══════► server 46.224.142.195
          (the laptop)      as Unix user "deploy"      │
                                                       ▼
                                 Postgres's socket file /var/run/postgresql/.s.PGSQL.5432
                                                       │
                                                       ▼
                                 Postgres: "who is on the other end? → deploy" → OK
```

### 1. The tunnel, on the laptop

The launchd agent `eu.kyma.pg-tunnel` (`clients/macos/eu.kyma.pg-tunnel.plist`) keeps this command running:

```
ssh -N -L 127.0.0.1:5433:/var/run/postgresql/.s.PGSQL.5432 deploy@46.224.142.195
```

- `-L` listens on port 5433 of the laptop, and forwards whatever arrives there, encrypted, to the server.
- `-N` opens no shell: the session only carries traffic.
- macOS starts it at login and restarts it if it drops.

### 2. SSH, on the server

The server accepts the connection because the laptop's SSH key is allowed for the `deploy` account: the same access as `ssh deploy@46.224.142.195`. So the tunnel's far end runs as Unix user `deploy` on the server.

### 3. The far end: a socket file, not a network port

The tunnel ends at the file `/var/run/postgresql/.s.PGSQL.5432`. It's a Unix socket: how programs on the same machine reach Postgres without the network. So Postgres sees a **local** connection, which its messages show as `host "[local]"`.

Postgres listens only on the server itself (`listen_addresses = 'localhost'`), and port 5432 is closed from outside.

### 4. Postgres decides whether to let you in

Postgres reads its rules (`postgres/pg_hba.conf`) top to bottom, and the first matching line decides. The laptop's connection matches:

```
local   kyma   kyma_ingest,reader_deploy   peer map=deploy
```

- **`local`:** a connection through the socket file.
- **`kyma`:** only the `kyma` database.
- **`kyma_ingest,reader_deploy`:** only these two logins. Any other username gets `no pg_hba.conf entry for host "[local]", user "…"`.
- **`peer`:** Postgres asks the server's operating system which Unix user is on the other end of the socket. The answer is `deploy`, since the tunnel runs as `deploy`. The operating system vouches for it, so no password is needed.
- **`map=deploy`:** `postgres/pg_ident.conf` says that Unix user `deploy`, and nobody else, may log in as `kyma_ingest` or `reader_deploy`.

### 5. Once logged in

- **Read-only:** `reader_deploy` has `default_transaction_read_only = on`, so any write fails.
- **What it can read:** it's a member of the `kyma_reader` group, which may read every table and view in `ads` and `ga`.
- **Defaults:** the database sets `search_path = ads, ga, public`, so `select * from report` works without the `ads.` prefix. Its time zone is Europe/Paris.

## Why it's built this way

- **Writing means being `deploy`:** having SSH access to `deploy` is the same as being allowed to write. Only the laptop and the server's own daily job (`cron/kyma-daily.sh`) have it.
- **Nothing to leak:** no write password exists anywhere.

## Reader machines take another route

A reader machine (for example `reader_jeanne`) takes a different route:

- **SSH account:** it uses `pgtunnel`, which can only reach `127.0.0.1:5432` on the server and gets no shell (`ssh/10-pgtunnel.conf`).
- **Way in:** it arrives over the server's internal network, not through the socket file. So it falls under the other rule:
  ```
  host    kyma    +kyma_reader    127.0.0.1/32    scram-sha-256
  ```
- **Password:** that rule asks for a password, its own `reader_<machine>` one.
- **Both halves needed:** the SSH key and the Postgres password. Either one alone gives nothing.
- **Managing them:** `postgres/add-reader.sh`, `remove-reader.sh` and `list-readers.sh`.

## When it doesn't connect

| Symptom | Cause | Fix |
|---|---|---|
| `connection refused` on 5433 | the tunnel is down | `launchctl print gui/$(id -u)/eu.kyma.pg-tunnel \| grep "state ="` should say `running`. Restart it with `launchctl kickstart -k gui/$(id -u)/eu.kyma.pg-tunnel`, and check its log with `tail ~/Library/Logs/kyma-pg-tunnel.log`. |
| `no pg_hba.conf entry for host "[local]", user "…"` | the username isn't `reader_deploy` or `kyma_ingest` | Fix the username. |
| The data looks old | connected to port 5432, the local test container | Use port `5433`. |
| `cannot execute … in a read-only transaction` | writing as `reader_deploy` | Expected. Use `kyma_ingest` only if you mean to write. |
| The tunnel keeps restarting | `ssh deploy@46.224.142.195` fails: network or SSH key | Fix SSH first. The tunnel uses the same access. |
