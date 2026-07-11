#!/usr/bin/env bash
#
# Install and configure Suricata as an IDS on Ubuntu/Debian.
# Usage:  sudo ./scripts/install.sh <capture-interface>
# Example: sudo ./scripts/install.sh eth0
#
set -euo pipefail

IFACE="${1:-}"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ $EUID -ne 0 ]]; then
    echo "ERROR: run as root (sudo $0 <interface>)" >&2
    exit 1
fi

if [[ -z "$IFACE" ]]; then
    echo "Usage: sudo $0 <capture-interface>" >&2
    echo "Available interfaces:" >&2
    ip -br link | awk '{print "  " $1}' >&2
    exit 1
fi

if ! ip link show "$IFACE" &>/dev/null; then
    echo "ERROR: interface '$IFACE' not found" >&2
    exit 1
fi

echo "==> Installing Suricata (interface: $IFACE)"

. /etc/os-release
if [[ "${ID:-}" == "ubuntu" ]]; then
    apt-get update -qq
    apt-get install -y software-properties-common
    add-apt-repository -y ppa:oisf/suricata-stable   # latest stable from upstream
    apt-get update -qq
fi
apt-get install -y suricata suricata-update jq ethtool

echo "==> Deploying configuration"
install -m 640 -o root -g suricata "$REPO_DIR/config/suricata.yaml" /etc/suricata/suricata.yaml
install -m 644 "$REPO_DIR/config/local.rules" /var/lib/suricata/rules/local.rules

# Point the config at the requested interface (repo default is ens18)
sed -i "s/interface: ens18/interface: $IFACE/g" /etc/suricata/suricata.yaml

# Make sure the packaged service uses af-packet on our interface
if [[ -f /etc/default/suricata ]]; then
    sed -i 's/^LISTENMODE=.*/LISTENMODE=af-packet/' /etc/default/suricata || true
    sed -i "s/^IFACE=.*/IFACE=$IFACE/" /etc/default/suricata || true
fi

echo "==> Fetching rulesets (free sources, broad MITRE ATT&CK coverage)"
suricata-update update-sources || true
suricata-update enable-source et/open || true                    # main ruleset, ATT&CK-tagged
suricata-update enable-source oisf/trafficid || true             # protocol/app identification
suricata-update enable-source sslbl/ssl-fp-blacklist || true     # abuse.ch malware TLS certs
suricata-update enable-source sslbl/ja3-fingerprints || true     # abuse.ch malware JA3 hashes
suricata-update enable-source stamus/lateral || true             # lateral-movement detection
# Optional, noisier threat-hunting rules — enable once tuned:
# suricata-update enable-source tgreen/hunting || true
suricata-update --no-test

echo "==> Disabling NIC offloading on $IFACE"
"$REPO_DIR/scripts/tune-interface.sh" "$IFACE"

echo "==> Installing daily rule-update cron job"
install -m 755 "$REPO_DIR/scripts/update-rules.sh" /usr/local/bin/suricata-update-rules
cat > /etc/cron.d/suricata-update <<'EOF'
# Update Suricata rulesets daily at 03:15 and hot-reload
15 3 * * * root /usr/local/bin/suricata-update-rules >> /var/log/suricata/rule-update.log 2>&1
EOF

echo "==> Installing systemd override (auto-restart on failure)"
if [[ -d "$REPO_DIR/systemd/suricata.service.d" ]]; then
    mkdir -p /etc/systemd/system/suricata.service.d
    cp "$REPO_DIR/systemd/suricata.service.d/override.conf" /etc/systemd/system/suricata.service.d/
    systemctl daemon-reload
fi

echo "==> Validating configuration"
suricata -T -c /etc/suricata/suricata.yaml -v

echo "==> Starting service"
systemctl enable suricata
systemctl restart suricata
sleep 3
systemctl --no-pager status suricata

cat <<EOF

============================================================
Suricata is running on interface: $IFACE

Next steps:
  1. Edit HOME_NET in /etc/suricata/suricata.yaml to match
     YOUR internal ranges, then: sudo systemctl restart suricata
  2. Test:   curl -s http://testmynids.org/uid/index.html
             tail -f /var/log/suricata/fast.log
  3. Splunk: see splunk/README.md in this repo
============================================================
EOF
