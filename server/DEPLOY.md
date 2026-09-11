# Deploying the SelahBeat server

SelahBeat is one Node process plus one SQLite file. It is designed to sit
alongside other sites on a server you already run — no Docker, no database
server, no new infrastructure.

The catalog seeds itself on first boot, so there is no separate seed step.

> If you ever want a self-contained box instead, `Dockerfile` and
> `docker-compose.yml` are still in this directory and work as-is. Everything
> below is the no-Docker path.

---

## 0. Check two things first

```bash
node --version        # needs 18.18 or newer; Next.js 15 will not run on older
sudo ss -lntp | grep 3411    # must print nothing
```

If `3411` is taken, pick another free port and use it consistently in
`/etc/selahbeat.env` and your nginx/Caddy config.

If your other apps use per-project Node versions (nvm, asdf), note the **absolute**
path from `which node` — systemd does not read your shell profile, and the unit
file assumes `/usr/bin/node`.

## 1. Create a service account and directories

Running as its own user keeps a compromise of this app away from your other
sites.

```bash
sudo useradd --system --home /opt/selahbeat --shell /usr/sbin/nologin selahbeat
sudo mkdir -p /opt/selahbeat /var/lib/selahbeat
sudo chown -R selahbeat:selahbeat /opt/selahbeat /var/lib/selahbeat
```

`/var/lib/selahbeat` holds the database and is deliberately outside the
deployed tree, so redeploying can never overwrite it.

## 2. Copy the code up and build

`better-sqlite3` is a native module and ships no prebuilt binary for Node 22+,
so it compiles from source on install. Without these, `npm ci` fails with
`gyp ERR!`:

```bash
sudo apt-get install -y build-essential python3
```

From your Mac:

```bash
rsync -av --exclude node_modules --exclude .next --exclude data \
  server/ YOUR-SERVER:/tmp/selahbeat-src/
```

On the server:

```bash
sudo rsync -a /tmp/selahbeat-src/ /opt/selahbeat/
sudo chown -R selahbeat:selahbeat /opt/selahbeat
cd /opt/selahbeat
sudo -u selahbeat npm ci
sudo -u selahbeat npm run build
```

The build's postbuild step copies the static assets and the seed catalog into
the standalone tree, so `/opt/selahbeat/.next/standalone` is self-contained.

## 3. Environment

```bash
sudo tee /etc/selahbeat.env > /dev/null <<'ENV'
PORT=3411
DATABASE_PATH=/var/lib/selahbeat/selahbeat.db
ADMIN_PASSWORD=<a long random password>
SESSION_SECRET=<paste the output of: openssl rand -hex 32>
GITHUB_REPO=0xt1m/selahbeat
ENV
sudo chmod 600 /etc/selahbeat.env
```

## 4. Run it under systemd

```bash
sudo cp /opt/selahbeat/deploy/selahbeat.service /etc/systemd/system/
# if `which node` was not /usr/bin/node:
#   sudo sed -i 's|/usr/bin/node|/your/path/to/node|' /etc/systemd/system/selahbeat.service
sudo systemctl daemon-reload
sudo systemctl enable --now selahbeat
sudo systemctl status selahbeat --no-pager
```

Confirm it started and populated the catalog:

```bash
sudo journalctl -u selahbeat -n 30 --no-pager
curl -s http://127.0.0.1:3411/v1/version
```

You should see `[selahbeat] seeded 76 songs` on the very first start only.

## 5. Point your existing web server at it

**Do not replace your main nginx.conf or Caddyfile** — your other sites live
there. Add a new block.

### nginx

```bash
sudo cp /opt/selahbeat/deploy/nginx-selahbeat.conf /etc/nginx/sites-available/selahbeat
sudo ln -s /etc/nginx/sites-available/selahbeat /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx
sudo certbot --nginx -d selahbeat.com
```

### Caddy

```bash
sudo tee -a /etc/caddy/Caddyfile < /opt/selahbeat/deploy/caddy-selahbeat.snippet
sudo caddy validate --config /etc/caddy/Caddyfile
sudo systemctl reload caddy
```

Caddy gets the certificate itself; there is no certbot step.

## 6. DNS

Point an **A record** for `selahbeat.com` at your server's IP. With nginx,
certbot needs this resolving before it can issue a certificate; with Caddy, the
same applies on first request.

```bash
dig +short selahbeat.com
```

## 7. Verify

```bash
curl -s https://selahbeat.com/v1/version
curl -s "https://selahbeat.com/v1/catalog?since=0" | head -c 160
curl -s -o /dev/null -w "privacy %{http_code}\n" https://selahbeat.com/privacy
curl -s -o /dev/null -w "support %{http_code}\n" https://selahbeat.com/support
```

Then sign in at `https://selahbeat.com/admin` with `ADMIN_PASSWORD`.

Both apps already default to `https://selahbeat.com`, so catalog sync starts
working the moment this is live — no app release needed.

---

## Deploying an update

```bash
# From your Mac
rsync -av --exclude node_modules --exclude .next --exclude data \
  server/ YOUR-SERVER:/tmp/selahbeat-src/

# On the server
sudo rsync -a /tmp/selahbeat-src/ /opt/selahbeat/
sudo chown -R selahbeat:selahbeat /opt/selahbeat
cd /opt/selahbeat && sudo -u selahbeat npm ci && sudo -u selahbeat npm run build
sudo systemctl restart selahbeat
```

The database is in `/var/lib/selahbeat`, untouched by any of this.

## Backups

The whole catalog is a single file:

```bash
ssh YOUR-SERVER 'sudo cat /var/lib/selahbeat/selahbeat.db' \
  > selahbeat-backup-$(date +%F).db
```

Worth a weekly cron job once you have corrected enough tempos to mind losing
them. Restore by stopping the service, replacing the file, and starting again.

## Troubleshooting

| Symptom | Cause |
|---|---|
| `node: command not found` in the journal | `ExecStart` points at `/usr/bin/node`; set it to your real `which node` |
| `EADDRINUSE` | Another app already has that port; change `PORT` in `/etc/selahbeat.env` and the proxy config |
| `502` from nginx/Caddy | The service is down — `sudo journalctl -u selahbeat -n 50` |
| `EACCES` writing the database | `/var/lib/selahbeat` not owned by `selahbeat`, or missing from `ReadWritePaths` |
| Your other sites stopped working | The main nginx.conf or Caddyfile was replaced rather than added to — restore it and use the `sites-available` / append approach above |
| Catalog empty | The build's postbuild step did not run; re-run `npm run build` and check `.next/standalone/catalog/` exists |
| `gyp ERR!` during `npm ci` | Missing `build-essential` / `python3` — better-sqlite3 compiles from source |
| Gets a certificate but shows another site | Another server block already claims `selahbeat.com`, or is the default; check `nginx -T` |
