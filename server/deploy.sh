#!/usr/bin/env bash
#
# Deploy the SelahBeat server to a host that already has it installed.
#
#   ./deploy.sh                         # deploy to the default host
#   SELAHBEAT_SERVER=ubuntu@1.2.3.4 ./deploy.sh
#   ./deploy.sh --restart-only          # no upload, just bounce the service
#
# First-time setup (creating the user, directories, systemd unit and web server
# block) is in DEPLOY.md — this script only handles subsequent deploys.
set -euo pipefail

SERVER="${SELAHBEAT_SERVER:-ubuntu@0xt1m.com}"
REMOTE_DIR="${SELAHBEAT_REMOTE_DIR:-/opt/selahbeat}"
STAGING="/tmp/selahbeat-src"
SERVICE="selahbeat"
PORT="${SELAHBEAT_PORT:-3411}"
DOMAIN="${SELAHBEAT_DOMAIN:-selahbeat.com}"

RESTART_ONLY=false
[[ "${1:-}" == "--restart-only" ]] && RESTART_ONLY=true

bold() { printf '\033[1m%s\033[0m\n' "$1"; }
fail() { printf '\033[31m%s\033[0m\n' "$1" >&2; exit 1; }

cd "$(dirname "$0")"
[[ -f package.json ]] || fail "Run this from the server/ directory."

bold "→ Checking $SERVER"
ssh -o ConnectTimeout=10 "$SERVER" "test -d $REMOTE_DIR" \
  || fail "$REMOTE_DIR not found on $SERVER. Do the first-time setup in DEPLOY.md."

if [[ "$RESTART_ONLY" == false ]]; then
  bold "→ Uploading"
  rsync -az --delete \
    --exclude node_modules --exclude .next --exclude data --exclude '.env*' \
    ./ "$SERVER:$STAGING/"

  bold "→ Installing and building"
  # npm ci recompiles better-sqlite3 from source and takes about a minute, so
  # it only runs when the lockfile actually changed.
  ssh "$SERVER" "bash -euo pipefail -s" <<REMOTE
    sudo rsync -a --delete \
      --exclude node_modules --exclude .next \
      $STAGING/ $REMOTE_DIR/
    sudo chown -R selahbeat:selahbeat $REMOTE_DIR
    cd $REMOTE_DIR

    NEW_HASH=\$(sha256sum package-lock.json | cut -d' ' -f1)
    OLD_HASH=\$(cat .deploy-lock-hash 2>/dev/null || echo none)

    if [[ "\$NEW_HASH" != "\$OLD_HASH" || ! -d node_modules ]]; then
      echo "   dependencies changed - running npm ci"
      sudo -u selahbeat npm ci --no-audit --no-fund
      echo "\$NEW_HASH" | sudo -u selahbeat tee .deploy-lock-hash > /dev/null
    else
      echo "   dependencies unchanged - skipping npm ci"
    fi

    sudo -u selahbeat npm run build
REMOTE
fi

bold "→ Restarting $SERVICE"
ssh "$SERVER" "sudo systemctl restart $SERVICE"

bold "→ Health check"
ssh "$SERVER" "bash -euo pipefail -s" <<REMOTE
  for i in \$(seq 1 30); do
    if curl -fsS "http://127.0.0.1:$PORT/v1/version" > /tmp/sb-health 2>/dev/null; then
      echo "   \$(cat /tmp/sb-health)"
      exit 0
    fi
    sleep 1
  done
  echo "   service did not answer on port $PORT" >&2
  sudo journalctl -u $SERVICE -n 30 --no-pager >&2
  exit 1
REMOTE

# Public check is advisory: DNS or TLS may not be ready on a first deploy.
if curl -fsS --max-time 10 "https://$DOMAIN/v1/version" > /dev/null 2>&1; then
  bold "✓ Live at https://$DOMAIN"
else
  printf '\033[33m%s\033[0m\n' "✓ Deployed, but https://$DOMAIN did not respond (DNS or TLS not ready yet)"
fi
