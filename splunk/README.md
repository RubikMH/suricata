# Shipping Suricata events to Splunk

Suricata writes everything to `/var/log/suricata/eve.json` (one JSON event
per line). There are two good ways to get that into Splunk.

## Option A — Universal Forwarder (recommended)

Reliable, buffered, handles restarts and backpressure for you.

**1. On the indexer / Splunk Cloud:** create an index named `suricata` and
install the free **Splunk TA for Suricata** from Splunkbase (it provides
sourcetype parsing + CIM field mappings so alerts work with Enterprise
Security and the Suricata dashboards). If you'd rather not use the TA, copy
`props.conf` from this directory instead.

**2. On the Suricata sensor:** install the Splunk Universal Forwarder, then:

```bash
sudo mkdir -p /opt/splunkforwarder/etc/apps/suricata_inputs/local
sudo cp inputs.conf /opt/splunkforwarder/etc/apps/suricata_inputs/local/
sudo /opt/splunkforwarder/bin/splunk add forward-server <indexer-host>:9997
sudo /opt/splunkforwarder/bin/splunk restart
```

**3. Verify in Splunk:**

```
index=suricata sourcetype=suricata | stats count by event_type
index=suricata event_type=alert | table _time src_ip dest_ip alert.signature alert.severity
```

## Option B — HTTP Event Collector (no forwarder install)

If you can't install a forwarder, use the Suricata **filetype: redis** or a
lightweight shipper. The simplest zero-dependency approach is `curl` +
`inotify`, but for production use **Fluent Bit**:

```ini
# /etc/fluent-bit/fluent-bit.conf
[INPUT]
    Name          tail
    Path          /var/log/suricata/eve.json
    Parser        json
    Tag           suricata
    DB            /var/lib/fluent-bit/suricata.db

[OUTPUT]
    Name          splunk
    Match         suricata
    Host          <splunk-host>
    Port          8088
    TLS           On
    Splunk_Token  <your-HEC-token>
    Event_Index   suricata
    Event_Sourcetype suricata
```

Enable HEC in Splunk under *Settings → Data Inputs → HTTP Event Collector*,
create a token scoped to the `suricata` index, and put it in the config
above (keep the token out of git!).

## Useful starter searches

```
# Top alert signatures last 24h
index=suricata event_type=alert earliest=-24h
| stats count by alert.signature, alert.severity | sort -count

# Who is my noisiest internal host?
index=suricata event_type=alert
| stats count dc(alert.signature) as sigs by src_ip | sort -count

# DNS queries to newly-seen domains
index=suricata event_type=dns dns.type=query
| stats earliest(_time) as first_seen count by dns.rrname
| where first_seen > relative_time(now(), "-1d")

# TLS JA3 fingerprint hunting
index=suricata event_type=tls | stats count by tls.ja3.hash, tls.sni

# Sensor health: kernel packet drops (should be ~0)
index=suricata event_type=stats
| timechart max(stats.capture.kernel_drops) as drops
```

## Volume warning

`eve.json` with flow/http/dns/tls logging enabled generates a LOT of data —
plan roughly **1–3 GB/day per 100 Mbps of average traffic**, which counts
against your Splunk license. If license is tight, trim the `types:` list in
`suricata.yaml` (e.g. keep only `alert`, `anomaly`, `stats`) — alerts alone
are a tiny fraction of the volume.
