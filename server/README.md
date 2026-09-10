# SelahBeat server

Next.js app serving three things from one process:

- **`/v1/*`** — the JSON API the macOS/iOS app talks to
- **`/admin`** — song catalog management (password-protected)
- **`/`** — the landing page and download link

SQLite is the database; on EC2 it lives on a mounted volume at `/data`.

## Local development

```bash
npm install
cp .env.example .env.local        # then set ADMIN_PASSWORD and SESSION_SECRET
npm run seed                      # loads catalog/seed-songs.json
npm run dev                       # http://localhost:3000
```

## API

| Endpoint | Purpose |
|---|---|
| `GET /v1/catalog?since=<revision>` | Delta sync. `since=0` returns a full snapshot; steady state returns a few hundred bytes. |
| `GET /v1/songs/search?q=&limit=` | Fallback search, for when the catalog outgrows a full local mirror. |
| `GET /v1/version` | Health check and current catalog revision. |

### Why delta sync rather than search-per-keystroke

The app downloads the catalog once and keeps it. Tempo lookup then works with
no connection — which matters, because church wifi tends to fail exactly when
someone needs it. Every write stamps a row with the next value of a global
revision counter, so "everything since N" is one indexed range scan.

**Song ids are permanent.** Clients key their imported copies on the slug, so
reusing or renumbering an id orphans every install. Renaming a song is fine.

## Deploying to EC2

```bash
cp .env.example .env              # set ADMIN_PASSWORD, SESSION_SECRET, SITE_ADDRESS
docker compose up -d --build
```

Caddy handles TLS automatically once `SITE_ADDRESS` is a real domain pointed at
the instance. Back up by copying the single `.db` file out of the volume.
