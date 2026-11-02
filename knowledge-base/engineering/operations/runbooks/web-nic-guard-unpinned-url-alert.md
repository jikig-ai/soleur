# Runbook: soleur-web-nic-guard-unpinned-url-prd (the nic guard refused to POST to an unpinned ingest URL)

**Alert:** Better Stack Logs exploration alert `soleur-web-nic-guard-unpinned-url-prd`
(`logtail_exploration_alert.web_nic_guard_unpinned_url` in
`apps/web-platform/infra/betterstack-logs-alerts.tf`) — #9639 F8.
**Substrate:** `apps/web-platform/infra/web-private-nic-guard.sh` + its
`/etc/default/web-private-nic-guard` env file; Doppler `web_nic_guard` secrets.

## What it means

`web-private-nic-guard.sh` refuses to send the Better Stack token to a destination other
than the pinned ingest URL (`INGEST_URL_PINNED`, a `readonly` literal inside the script).
When `BETTERSTACK_INGEST_URL` is set but does not equal the pin, the guard logs

```text
[nic] unpinned_url: refusing to send the Better Stack token to an unpinned destination — SOLEUR_PRIVATE_NIC not shipped: <LINE>
```

to stderr — journald-tagged `SYSLOG_IDENTIFIER='web-nic-guard'`, shipped to Better Stack
by Vector Source 4 — sets `SHIP_REFUSED=true`, and **withholds its liveness beat**: a
guard that cannot report must not claim health. So this alert can coincide with a
`web_nic_guard` heartbeat lapse — the host is healthy but cannot report, and the absent
beat will read as guard-down. This alert exists because that refusal mode was previously
visible only through a post-merge log query; it is what names the cause when the beat
lapses.

The predicate deliberately has **no host conjunct**: the guard runs on web-1 (SSH
provisioner) and is baked for web-2-class hosts via cloud-init; either host can refuse.

## Diagnosis (no SSH — hr-no-ssh-fallback-in-runbooks)

1. **Read back the rows** with the standing query
   (`scripts/betterstack-query.sh`, prd source `2457081`):

   ```sql
   SELECT dt, raw
   FROM remote(<source>)
   WHERE dt BETWEEN <start> AND <end>
     AND JSONExtractString(raw, 'SYSLOG_IDENTIFIER') = 'web-nic-guard'
     AND position(JSONExtractString(raw, 'message'), 'unpinned_url') > 0
   ```

   Each row's `message` embeds the full `SOLEUR_PRIVATE_NIC` LINE (nic_ok, addresses,
   imds fields) — which host, and what the guard observed.
2. **Inspect the Doppler value**, never echo it: the guard reads `BETTERSTACK_INGEST_URL`
   from `doppler run` (project `soleur`, config `prd`). A value that drifted from the
   pinned `https://s2457081.eu-fsn-3.betterstackdata.com/` URL is the cause. Compare
   lengths/hosts, not contents, if it must be inspected (`doppler secrets get
   BETTERSTACK_INGEST_URL --plain | sha256sum` against a known-good hash).
3. **Check whether the pin changed deliberately.** If the ingest URL was rotated on
   purpose, `INGEST_URL_PINNED` in `web-private-nic-guard.sh` must move with it (it is a
   `readonly` literal baked into the script — a deliberate decision so an environment
   value can never redirect the token; drift guard:
   `web-private-nic-guard.test.sh`).

## Remediation

- **Value drifted** → correct `BETTERSTACK_INGEST_URL` in Doppler back to the pinned URL.
  The next guard tick posts again and the beat resumes; this alert auto-resolves after
  ~10 quiet minutes (auto-resolution does NOT mean the cause was fixed — verify the
  value).
- **Pin needs moving** (a legitimate new ingest endpoint) → update
  `INGEST_URL_PINNED` in `web-private-nic-guard.sh`, its drift-guard expectations, and
  the Doppler value together.
- Do NOT treat a heartbeat-lapse page on `web_nic_guard` as host-down until this alert's
  rows have been checked — the refusal arm withholds the beat on a healthy host.
