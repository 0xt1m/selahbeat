#!/usr/bin/env bash
#
# Watches the live site for the thing that actually happened: HTML served from
# selahbeat.com carrying a script nobody wrote.
#
# In October 2026 a cache-poisoning bug in Next.js let an attacker put a data:
# URI script into the homepage, which drew a fake CAPTCHA telling visitors to
# paste an infostealer into Terminal. It ran for days because nothing was
# watching, and the request that did it had rotated out of the logs by the
# time anyone looked. This runs every five minutes, says so loudly, and keeps
# the evidence.
#
# Installed by deploy/install-monitoring.sh.
set -uo pipefail

URL="https://selahbeat.com/"
API="https://selahbeat.com/api/v1/version"
LOG="/var/log/selahbeat-canary.log"
STATE="/var/lib/selahbeat-canary.state"
EVIDENCE="/var/log/selahbeat-evidence"

log() { echo "$(date -Is) $*" >> "$LOG"; }

alert() {
    log "ALERT $*"
    # Loud in the journal too, so `journalctl -p err` surfaces it without
    # anyone knowing this file exists.
    logger -p daemon.err -t selahbeat-canary "$*"
}

body=$(curl -s --max-time 20 -A 'selahbeat-canary' "$URL" 2>/dev/null) || true

if [[ -z "$body" ]]; then
    alert "site returned nothing"
    echo bad > "$STATE"
    exit 1
fi

problems=()

# 1. Inline or data: URI scripts. This site has none - every script it serves
#    is a file under /_next/. A data: URI script is how the injection arrived.
if grep -qE '<script[^>]*src="(data:|javascript:)' <<< "$body"; then
    problems+=("data-uri script tag")
fi

# 2. Scripts loaded from anywhere but this origin.
foreign=$(grep -oE '<script[^>]*src="https?://[^"]+' <<< "$body" \
          | grep -v 'selahbeat\.com' | head -3 || true)
if [[ -n "$foreign" ]]; then
    problems+=("third-party script: $(tr '\n' ' ' <<< "$foreign")")
fi

# 3. Signatures of this malware family: blockchain-hosted loaders, and the
#    fake verification lure they draw once they run.
if grep -qiE 'eth_call|bnbchain|binance\.org|eval\(atob|not a robot|recaptcha' <<< "$body"; then
    problems+=("malware signature in page")
fi

# 4. The API answering, so a silent outage is noticed as well as a compromise.
if ! curl -fs --max-time 15 "$API" > /dev/null 2>&1; then
    problems+=("api not answering")
fi

if (( ${#problems[@]} > 0 )); then
    alert "site looks compromised: ${problems[*]}"
    # Keep the page this time, rather than discovering days later that the
    # only copy rotated away.
    mkdir -p "$EVIDENCE"
    printf '%s' "$body" > "$EVIDENCE/page-$(date +%Y%m%dT%H%M%S).html"
    # Thirty days of evidence is plenty, and bounded.
    find "$EVIDENCE" -type f -mtime +30 -delete 2>/dev/null || true
    echo bad > "$STATE"
    exit 1
fi

if [[ "$(cat "$STATE" 2>/dev/null || echo ok)" != "ok" ]]; then
    log "RECOVERED site is clean again"
    logger -p daemon.warning -t selahbeat-canary "site is clean again"
fi

echo ok > "$STATE"
log "ok"
