#!/usr/bin/env bash
#
# Prepare a NIC for packet capture: disable all offloading features that
# would hand Suricata merged/rewritten frames instead of what was on the wire.
# Usage: sudo ./scripts/tune-interface.sh <interface>
#
set -euo pipefail

IFACE="${1:?Usage: $0 <interface>}"

for feature in gro lro tso gso rx tx sg rxvlan txvlan; do
    ethtool -K "$IFACE" "$feature" off 2>/dev/null || true
done

# Capture NIC should be up and promiscuous, but needs no IP address
ip link set "$IFACE" promisc on
ip link set "$IFACE" up

echo "Offloading disabled and promiscuous mode enabled on $IFACE:"
ethtool -k "$IFACE" | grep -E 'generic-(receive|segmentation)|tcp-segmentation|large-receive' || true

# Persist across reboots via a systemd oneshot unit
UNIT=/etc/systemd/system/capture-tune@.service
if [[ ! -f "$UNIT" ]]; then
    cat > "$UNIT" <<'EOF'
[Unit]
Description=Disable NIC offloading for packet capture on %i
After=network.target
Before=suricata.service

[Service]
Type=oneshot
ExecStart=/usr/sbin/ethtool -K %i gro off lro off tso off gso off rx off tx off sg off
ExecStart=/usr/sbin/ip link set %i promisc on
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
fi
systemctl enable "capture-tune@${IFACE}.service" 2>/dev/null || true
