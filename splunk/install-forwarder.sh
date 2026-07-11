#!/usr/bin/env bash
#
# Install & configure the Splunk Universal Forwarder on the Suricata sensor
# to ship /var/log/suricata/eve.json to a separate Splunk indexer.
#
# Usage:
#   sudo ./install-forwarder.sh <indexer-ip> [receiving-port]
# Example:
#   sudo ./install-forwarder.sh 192.168.30.10 9997
#
# You must download the Splunk Universal Forwarder .deb first (free, needs a
# Splunk account) from https://www.splunk.com/en_us/download/universal-forwarder.html
# and place it next to this script, OR set UF_DEB=/path/to/it.
#
set -euo pipefail

INDEXER="${1:?Usage: sudo $0 <indexer-ip> [port]}"
PORT="${2:-9997}"
SPLUNK_HOME=/opt/splunkforwarder
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UF_DEB="${UF_DEB:-$(ls -1 "$REPO_DIR"/splunkforwarder-*.deb 2>/dev/null | head -1 || true)}"

if [[ $EUID -ne 0 ]]; then echo "Run as root." >&2; exit 1; fi

# 1. Install the forwarder if not present
if [[ ! -x "$SPLUNK_HOME/bin/splunk" ]]; then
    if [[ -z "$UF_DEB" || ! -f "$UF_DEB" ]]; then
        echo "ERROR: Universal Forwarder .deb not found." >&2
        echo "Download it from Splunk and put it next to this script, or set UF_DEB=/path." >&2
        exit 1
    fi
    echo "==> Installing Universal Forwarder from $UF_DEB"
    dpkg -i "$UF_DEB"
fi

# 2. Let the forwarder's service account read Suricata's logs
#    (UF runs as user 'splunkfwd' by default on recent versions)
if id splunkfwd &>/dev/null; then
    usermod -aG suricata splunkfwd || true
fi
# eve.json must be group-readable by the suricata group
chmod 750 /var/log/suricata || true

# 3. Deploy the monitor input
mkdir -p "$SPLUNK_HOME/etc/apps/suricata_inputs/local"
cp "$REPO_DIR/inputs.conf" "$SPLUNK_HOME/etc/apps/suricata_inputs/local/inputs.conf"

# 4. Accept the license, set forward destination, enable boot-start
"$SPLUNK_HOME/bin/splunk" start --accept-license --answer-yes --no-prompt
"$SPLUNK_HOME/bin/splunk" add forward-server "${INDEXER}:${PORT}" || true
"$SPLUNK_HOME/bin/splunk" enable boot-start -user splunkfwd || true
"$SPLUNK_HOME/bin/splunk" restart

echo
echo "==> Forwarder installed. Verify the connection is ACTIVE:"
echo "    sudo $SPLUNK_HOME/bin/splunk list forward-server"
echo "==> On the indexer, confirm data with:"
echo "    index=suricata sourcetype=suricata | stats count by event_type"
