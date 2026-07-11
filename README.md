# Suricata IDS → Splunk Setup

Complete configuration package for running Suricata as a network IDS and
shipping its alerts/events to Splunk.

## Repository layout

```
├── config/
│   ├── suricata.yaml          # Main Suricata config (IDS mode, EVE JSON output)
│   └── local.rules            # Your custom rules
├── scripts/
│   ├── install.sh             # Install Suricata + rules on Ubuntu/Debian
│   ├── tune-interface.sh      # Disable NIC offloading on the capture interface
│   └── update-rules.sh        # Update rulesets (run from cron)
├── splunk/
│   ├── inputs.conf            # Splunk Universal Forwarder: monitor eve.json
│   ├── props.conf             # Correct JSON parsing / timestamps in Splunk
│   └── README.md              # Splunk-side setup (UF and HEC options)
└── systemd/
    └── suricata.service.d/override.conf   # Service hardening/restart policy
```

## Quick start

### 1. Network settings (already set for this deployment)

`config/suricata.yaml` is preconfigured for:

- **`HOME_NET`**: `192.168.30.0/27` — add any other internal ranges you own
- **Capture interface**: `ens18`

If either changes, edit them at the top of the file. `HOME_NET` is the
single most important tuning knob: almost every rule decides direction
based on it.

### 2. Install

```bash
sudo ./scripts/install.sh ens18
```

The script:
1. Installs Suricata from the OISF stable PPA (Ubuntu) or distro repo (Debian)
2. Copies `config/suricata.yaml` and `config/local.rules` into `/etc/suricata/`
3. Runs `suricata-update` to fetch the free **ET Open** ruleset
4. Disables NIC offloading (required for correct capture)
5. Validates the config (`suricata -T`) and starts the service

### 3. Verify it works

```bash
sudo systemctl status suricata
sudo tail -f /var/log/suricata/eve.json | jq 'select(.event_type=="alert")'

# Trigger a harmless test alert (ET Open rule 2100498):
curl -s http://testmynids.org/uid/index.html
```

You should see a `GPL ATTACK_RESPONSE id check returned root` alert.

### 4. Send events to Splunk

See [`splunk/README.md`](splunk/README.md). Short version:

- **Recommended:** install the Splunk **Universal Forwarder** on the Suricata
  box, drop `splunk/inputs.conf` into it, and install the free
  **"Splunk TA for Suricata"** (or use `splunk/props.conf`) on your indexers.
- In Splunk, install the **"Splunk App for Suricata"** dashboards, or just
  search `index=suricata sourcetype=suricata event_type=alert`.

## MITRE ATT&CK coverage

Alerts are tagged with MITRE technique IDs (from ET Open metadata and our
custom rules in `config/local.rules`), and
`splunk/lookups/mitre_techniques.csv` maps them against the full technique
list. See [`splunk/MITRE-COVERAGE.md`](splunk/MITRE-COVERAGE.md) for the
Splunk searches and an honest breakdown of what a network IDS can and
cannot detect from that list.

## Where to put the sensor

An IDS only sees what its NIC sees. To "capture anything in my network":

| Option | How |
|---|---|
| **SPAN/mirror port** (best) | Configure your switch to mirror all traffic to the port the sensor's capture NIC is plugged into |
| **Network TAP** | Inline hardware tap on your uplink, feed to the sensor |
| **On the gateway/firewall** | Run Suricata directly on the router box, listening on the LAN interface |

A sensor on a normal access port only sees its own traffic plus broadcast —
that is **not** enough for network-wide IDS.

## Ongoing operations

- **Rules update daily** — `install.sh` sets up a cron job calling
  `scripts/update-rules.sh` (suricata-update + reload, no restart needed).
- **Log rotation** — handled by the logrotate config the package ships;
  eve.json can grow fast (GBs/day on busy networks).
- **Tuning noise** — after a week, list your top alerts:
  ```bash
  jq -r 'select(.event_type=="alert") | .alert.signature' /var/log/suricata/eve.json | sort | uniq -c | sort -rn | head -20
  ```
  Suppress false positives in `/etc/suricata/disable.conf` (by SID) and rerun
  `suricata-update`.

## Health checks

```bash
sudo suricata -T -c /etc/suricata/suricata.yaml -v   # config test
sudo suricatasc -c uptime                            # talk to running daemon
jq 'select(.event_type=="stats") | .stats.capture' /var/log/suricata/eve.json | tail -1
# capture.kernel_drops should stay near 0 — if it grows, increase af-packet
# ring-size / threads in suricata.yaml
```
