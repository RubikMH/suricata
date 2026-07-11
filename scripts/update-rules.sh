#!/usr/bin/env bash
#
# Refresh Suricata rulesets and hot-reload the engine (no restart, no
# packet loss). Installed to /usr/local/bin/suricata-update-rules and run
# daily from /etc/cron.d/suricata-update.
#
set -euo pipefail

echo "[$(date -Is)] updating rulesets"
suricata-update --no-test=false

# Hot-reload: tell the running daemon to re-read rule files
if suricatasc -c reload-rules >/dev/null 2>&1; then
    echo "[$(date -Is)] rules reloaded via unix socket"
else
    # Fallback if the unix socket isn't available
    systemctl kill -s USR2 suricata
    echo "[$(date -Is)] rules reloaded via SIGUSR2"
fi
