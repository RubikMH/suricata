# Mapping Suricata alerts to your MITRE ATT&CK technique list

Your `mitre_techniques.json` contains **697 techniques** across the full
Enterprise matrix. This page explains how detection maps to that list, and
— honestly — what a network IDS can and cannot see.

## How the mapping works

1. **ET Open rules are ATT&CK-tagged.** Thousands of rules carry
   `mitre_tactic_id` / `mitre_technique_id` metadata. Because
   `suricata.yaml` sets `metadata: yes` on the alert output, those tags
   arrive in Splunk as `alert.metadata.mitre_technique_id`.
2. **Our custom rules** in `config/local.rules` carry the same metadata
   fields (scanning, brute force, lateral movement, DNS tunneling, exfil,
   cleartext creds, tool transfer).
3. **`lookups/mitre_techniques.csv`** (generated from your JSON) lets
   Splunk enrich every alert with the technique name, tactics, and
   platforms from *your* list.

## Splunk setup

Upload the lookup once:
*Settings → Lookups → Lookup table files → Add new* →
`mitre_techniques.csv`, then create a lookup definition named
`mitre_techniques`.

### Alerts enriched with your technique list

```
index=suricata event_type=alert
| spath output=technique_id path=alert.metadata.mitre_technique_id{}
| mvexpand technique_id
| lookup mitre_techniques technique_id OUTPUT technique_name tactics
| stats count by technique_id technique_name tactics
| sort -count
```

### ATT&CK coverage board — which of your 697 techniques fired

```
| inputlookup mitre_techniques
| join type=left technique_id [
    search index=suricata event_type=alert earliest=-30d
    | spath output=technique_id path=alert.metadata.mitre_technique_id{}
    | mvexpand technique_id
    | stats count as alerts by technique_id ]
| eval alerts=coalesce(alerts, 0), detected=if(alerts>0, "yes", "no")
| stats count by tactics detected
```

### Alerts by tactic over time

```
index=suricata event_type=alert
| spath output=tactic path=alert.metadata.mitre_tactic_id{}
| mvexpand tactic
| timechart span=1h count by tactic
```

## What Suricata WILL cover from your list

Techniques with a **network footprint** — roughly these tactics:

| Tactic | Examples Suricata detects |
|---|---|
| Reconnaissance / Discovery | T1046 port scans, T1018 ping sweeps, T1595 active scanning |
| Initial Access | T1190 exploit web apps (huge ET coverage), T1566 phishing URLs/attachments |
| Credential Access | T1110 brute force, T1040 cleartext creds, T1557 MitM/relay artifacts |
| Lateral Movement | T1021 RDP/SMB/WinRM/SSH between hosts (plus stamus/lateral ruleset) |
| Command & Control | T1071 app-layer C2, T1071.004 DNS C2, T1568 DGA, T1572 tunneling, T1090 proxies, T1105 tool transfer, JA3/SSL blacklists for malware families |
| Exfiltration | T1048 alt-protocol exfil, T1041 exfil over C2, T1567 exfil to web services |
| Impact | T1498/T1499 DoS patterns, ransomware C2 check-ins |

## What Suricata CANNOT cover (and what to add)

A large share of your list — most of **Persistence, Privilege Escalation,
Stealth/Defense Impairment, Execution** — happens *inside hosts* (registry
keys, scheduled tasks, process injection, token theft). No network sensor
sees those. Encrypted traffic also hides content (though JA3/JA4, SNI, and
certificate rules still catch a lot of malware C2).

To approach full-matrix coverage, feed Splunk from hosts too:

- **Windows:** Sysmon + Splunk Universal Forwarder (or Wazuh) — covers the
  Execution/Persistence/PrivEsc columns.
- **Linux:** auditd or Wazuh agent.
- Both integrate with the same Splunk index strategy, and Splunk's free
  **"Splunk Security Essentials"** app scores your ATT&CK coverage across
  all data sources.

Suricata + host telemetry together is what actually covers a list like
yours; Suricata alone realistically covers the network-visible third of it.
