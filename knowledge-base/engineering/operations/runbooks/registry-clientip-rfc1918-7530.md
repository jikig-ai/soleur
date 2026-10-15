---
title: "registry-clientip-not-rfc1918 alert - a non-private clientIP reached Better Stack"
category: runbook
tags: [registry, zot, better-stack, gdpr, clientip, alert]
---

# `registry_clientip_not_rfc1918` fired (#7530)

The Better Stack Logs alert `soleur-registry-clientip-not-rfc1918-prd`
(`logtail_exploration_alert.registry_clientip_not_rfc1918` in
`apps/web-platform/infra/betterstack-logs-alerts.tf`) alerts when a registry-plane row shipped to
Better Stack source 2457081 carries a **first `clientIP` that is address-shaped and outside 10/8,
172.16/12 and 192.168/16**. It checks every 5 minutes over a 15-minute window and fires on a single row.

**The alert is one email to the team surface.** It sets `email = true` and
`push`, `call`, `sms` and `critical_alert` all false, and `var.betterstack_paid_tier` defaults to `false`,
so there is no escalation policy: a human learns of it when they read that email, and nothing opens a
GitHub issue or notifies an agent by itself. The words "page" and "paged" in older records mean this email.

**Everything below runs from the Better Stack query connection, Terraform and GitHub Actions. There is
no SSH in this runbook.**

## Why this alert is a legal event, not only an ops one

The alert is the **observable signature of the public-ingress re-evaluation trigger having fired**, named in the last `re_evaluation_triggers` entry of the 2026-08 counsel review
(`knowledge-base/legal/audits/2026-08-counsel-review-7440.md`): public ingress to zot may have
started, which means `clientIP` **may now be Art. 4(1) personal data on rows already in flight**.
The condition the CLO accepted was that every observable `clientIP` is RFC1918 (the estate's own
hosts behind the Cloudflare tunnel and a deny-all-public firewall). The shipper does not mask
`clientIP` (ADR-211: it is detected and alerted, not masked), so a public address is already stored
once the alert evaluates.

What the alert is not:

- It is **detection, not prevention**. Latency is up to about 20 minutes (300 s check, 900 s window,
  plus ingest). Say "monitored and alerted by email" in any record, never "guaranteed".
- Its **disk arm has no live positive control**: the live probe found 0 `SOLEUR_ZOT_DISK` rows carrying a
  `clientIP` in 7 days, so only the shipper arm has a measured population. A dead disk arm reads as
  healthy (`treat_as_zero`). Do not credit that arm with coverage it has not demonstrated.
- It is **sampled over shipped rows only**. The shipper rate-caps ordinary rows to 17 per tick; a
  topology change would produce many public rows, so detection is adequate, but a low-rate public
  prober inside the high-volume private stream can be sampled out for some time. Rows the shipper drops
  never reach Better Stack (they stay in the host-local journald log under its size bound).
- It does **not** cover a public address in a top-level field other than `clientIP`, IPv4-mapped IPv6
  beyond the `::ffff:` form, or a renamed or reordered field. The grade depends on zot writing
  `clientIP` before `method`, `path` and `headers`, and on the field name; `treat_as_zero` makes a
  renamed field read as healthy forever. The drift guard pins the zot image digest the order was
  verified against (see [After a zot version bump](#after-a-zot-version-bump)).
- Its **producer anchors are sampled coverage**. Only the two anchored emitters are graded (the shipper
  envelope for host `soleur-registry` and the `SOLEUR_ZOT_DISK` heartbeat). Other registry-plane markers
  (`SOLEUR_ZOT_LOG_DROPPED`, `SOLEUR_ZOT_LOG_BOOT`, `SOLEUR_PRIVATE_NIC`) match neither anchor, and a host
  renamed in Terraform without the anchor literal moving reads as healthy. The alert suite pins the anchor
  literals to the template and to the server name; it does not enumerate every emitter.
- The vendor processing the rows is Better Stack s.r.o., whose Data Processing Agreement is
  **PENDING** (not executed). Quote that status in any legal record.

## Triage, in this order

### 1. Read the rows without writing an address anywhere

**Never paste an address into an issue, a PR, a comment, a chat or a ticket.** The point of this alert is
that such an address is personal data. Work with counts and time windows only.

Counts per hour of the matching rows (no value is selected, so nothing needs redacting). Run it
with the query connection described in [`betterstack-log-query.md`](./betterstack-log-query.md).
Invocation: `doppler run -p soleur -c prd_terraform -- bash scripts/betterstack-query.sh "<the SQL>"`
(the script takes raw SQL when the first argument starts with SELECT, WITH or SHOW and substitutes
`$BS_TABLE` and `$BS_TABLE_S3`; pass the SQL from a quoted heredoc so the shell does not expand it):

```sql
SELECT toStartOfHour(dt) AS hour, count() AS rows
FROM (SELECT dt, raw FROM remote($BS_TABLE)
      UNION ALL SELECT dt, raw FROM s3Cluster(primary, $BS_TABLE_S3) WHERE _row_type = 1)
WHERE dt > now() - INTERVAL 7 DAY
  AND (startsWith(raw, '{"message":"SOLEUR_ZOT_LOG shipper=zot-log-shipper host=soleur-registry ')
    OR startsWith(raw, '{"message":"SOLEUR_ZOT_DISK '))
  AND arrayExists(n -> (match(n, '^[0-9]{1,3}([.][0-9]{1,3}){3}')
        AND NOT match(n, '^(10[.]|192[.]168[.]|172[.](1[6-9]|2[0-9]|3[01])[.])'))
      OR length(n) - length(replaceAll(n, ':', '')) >= 2,
    [replaceRegexpOne(extract(JSONExtractString(raw, 'message'), 'clientIP[:=]"?([^ ,}"]+)'), '^[[]?(::ffff:)?', '')])
GROUP BY hour ORDER BY hour FORMAT JSONEachRow
```

Record: the first and last hour with a non-zero count (the **exposure window**) and the **total row
count**. Those two numbers are what the legal record needs; the address is not.

Then split the flagged rows by **class**, counts only (same extraction and window as above; no value is
selected). Dry-run read-only on 2026-10-15 over the live 7-day window: every count was 0.

```sql
SELECT
  countIf(match(v, '^127[.]')) AS loopback,
  countIf(match(v, '^169[.]254[.]')) AS link_local,
  countIf(match(v, '^100[.](6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])[.]')) AS cgnat,
  countIf(length(v) - length(replaceAll(v, ':', '')) >= 2) AS ipv6_shaped,
  countIf(match(v, '^[0-9]{1,3}([.][0-9]{1,3}){3}')
          AND NOT match(v, '^(10[.]|192[.]168[.]|172[.](1[6-9]|2[0-9]|3[01])[.]|127[.]|169[.]254[.]|100[.](6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])[.])')) AS other_ipv4,
  count() AS flagged_total
FROM (
  SELECT replaceRegexpOne(extract(JSONExtractString(raw, 'message'), 'clientIP[:=]"?([^ ,}"]+)'), '^[[]?(::ffff:)?', '') AS v
  FROM (SELECT dt, raw FROM remote($BS_TABLE)
        UNION ALL SELECT dt, raw FROM s3Cluster(primary, $BS_TABLE_S3) WHERE _row_type = 1)
  WHERE dt > now() - INTERVAL 7 DAY
    AND (startsWith(raw, '{"message":"SOLEUR_ZOT_LOG shipper=zot-log-shipper host=soleur-registry ')
      OR startsWith(raw, '{"message":"SOLEUR_ZOT_DISK '))
)
WHERE (match(v, '^[0-9]{1,3}([.][0-9]{1,3}){3}') AND NOT match(v, '^(10[.]|192[.]168[.]|172[.](1[6-9]|2[0-9]|3[01])[.])'))
   OR length(v) - length(replaceAll(v, ':', '')) >= 2
FORMAT JSONEachRow
```

`loopback`, `link_local` and `cgnat` are the three non-RFC1918 IPv4 ranges a platform component can
produce by accident; `ipv6_shaped` is any value with two or more colons (an IPv6 loopback `::1` counts
here); `other_ipv4` is everything else address-shaped, the class that means real public ingress. To see
whether a class **clusters right after a registry host replace**, rerun the first query with
`toStartOfMinute(dt)` in place of `toStartOfHour(dt)` and `dt > <the new boot's first-row time>` bounded
to the first 30 minutes (still counts only). The new boot's first-row time (an empty result prints the
epoch `1970-01-01`, meaning no row carries that id in the window; dry-run 2026-10-15):

```sql
SELECT min(dt) AS first_row_of_boot
FROM remote($BS_TABLE)
WHERE dt > now() - INTERVAL 6 HOUR
  AND startsWith(raw, '{"message":"SOLEUR_ZOT_DISK ')
  AND position(raw, 'boot_id=<the new boot id>') > 0
FORMAT JSONEachRow
```

Decide whether the alert is real before escalating:

- **Boot-time loopback value** (`loopback` above is the only non-zero class). A readiness probe on the
  registry host that surfaces as a loopback address alerts by design. If the rows cluster in the first
  minutes after a registry host replace and the count is small and stops, the predicate is narrowed **with that evidence** (a reviewed edit
  to `registry_clientip_not_rfc1918_sql` and its drift guard), not ignored.
- **Docker or NAT value** (`link_local` or `cgnat` only; Docker's own bridge ranges are RFC1918 and never
  flag). The same: evidence first, then a reviewed predicate edit.
- **Anything else is the real condition** (`other_ipv4`, or `ipv6_shaped` beyond a boot-time `::1`). Go to step 2.

### 2. Fix the cause before anything else

Public ingress is a topology change. In order:

1. `hcloud_firewall.registry` in `apps/web-platform/infra/zot-registry.tf`: it must declare **no inbound
   rule** (deny-all-public). An added rule is the likely cause; remove it through a reviewed PR and the
   normal Terraform path. Check that `hcloud_firewall_attachment.registry` in the same file is still
   declared: an unattached firewall is the same exposure. The no-SSH read of the LIVE firewall is the
   scheduled drift workflow (`gh workflow run scheduled-terraform-drift.yml`, then read its result: it
   compares live state to Terraform state for `apps/web-platform/infra`); the declaration in the `.tf`
   file alone proves intent, not the live attachment.
2. `apps/web-platform/infra/tunnel.tf`: the Cloudflare tunnel ingress for the registry hostname forwards
   to the private address only. A change that forwards an original public client address into zot's log
   fields (a proxy-protocol or forwarded-header setting) produces the same signature.
3. Confirm closure with the per-hour query above: the count returns to zero for two consecutive hours.

The alert auto-resolves after 30 quiet minutes. **That does not mean the exposure was handled.**

### 3. Record the exposure, counts only

Open a GitHub issue (`gh issue create --label action-required --title "registry clientIP exposure <date>" --body-file <file>`; the title carries no address) holding: the exposure window,
the total affected row count, the cause once known, and the date the cause was closed. Source 2457081
**retains rows 90 days** (Art. 30 register PA-8 section (f), #7772; rows older than the hot window are
read through the S3 archive described in `betterstack-log-query.md`, and the archive's own retention is
not recorded in the register). Whether affected rows can be
selectively redacted or deleted is a **CLO decision**: verify what Better Stack supports, do not assume
selective delete exists.

### 4. Is it a personal-data breach?

The alert is **not automatically an Art. 33 breach**. A public client address appearing in a log field
is an Art. 4(1) data-minimisation and lawfulness question first. It becomes a breach question if any
non-estate address made an **authenticated** pull or push (the rows carry a `username` field before
`clientIP`; a pull by a service principal from a non-estate address is the case to look for, by count,
by reading the row shape rather than the address).

- If any non-estate address made an authenticated request: route to
  [`recommended-tools.md#breach-notice-triage`](../../../legal/recommended-tools.md#breach-notice-triage).
  The **72-hour** Art. 33 clock runs from awareness. The channel is one email with no escalation, so
  treat the alert email's **delivery time** as the earliest candidate for awareness, record both the
  delivery time and the time it was read, and let the CLO fix the anchor. Do not state the read time as
  the start of the clock.
- The CLO agent classifies; the optional operator veto recorded in the 2026-08 record stands.
- External counsel is engaged if public ingress is **sustained with identifiable clients** or there was
  **any authenticated non-estate access**.

### 5. Close the loop

- Add a dated line to the #7530 tracker (counts and window only): `gh issue comment 7530 --body-file <file>`. It may
  already be closed by the follow-through probe's first PASS: comment on it anyway, or open an `action-required`
  issue that links it, so the record has one home.
- If the cause was a topology change that stays, the CLO re-reviews the PA-8 register entry
  (`knowledge-base/legal/article-30-register.md`) before the next shipper change; the `clientIP`
  condition of ADR-211 no longer holds and masking becomes a decision again, owned by the CLO.

## After a zot version bump

A change of `zot_image_amd64` in `zot-registry.tf` fails
`apps/web-platform/test/infra/registry-clientip-not-rfc1918-alert.test.sh` until someone has:

1. re-run the live **population check** (the first query with the `AND NOT match(...)` private-range
   line removed must return the whole private population, and the as-written query must return NO
   ROWS, since it groups by hour and a quiet state has none), and
2. re-verified the **field order** on fresh rows from the new image, counts only: the number of rows
   where `position(m, 'clientIP') < position(m, 'method')` must equal the number of rows checked
   (dry-run 2026-10-15: 106 of 106; the query reads the hot table for the last hour, so run it when the
   new image has been serving traffic and the count of rows checked is non-zero):

   ```sql
   SELECT countIf(position(m, 'clientIP') < position(m, 'method')) AS clientip_before_method, count() AS rows_checked
   FROM (SELECT JSONExtractString(raw, 'message') AS m
         FROM remote($BS_TABLE)
         WHERE dt > now() - INTERVAL 1 HOUR
           AND startsWith(raw, '{"message":"SOLEUR_ZOT_LOG shipper=zot-log-shipper host=soleur-registry ')
           AND position(JSONExtractString(raw, 'message'), 'clientIP') > 0
           AND position(JSONExtractString(raw, 'message'), 'method') > 0)
   FORMAT JSONEachRow
   ```

   and, for `path` and `headers`, the same comparison with that word in place of `method`, and
3. updated `VERIFIED_ZOT_IMAGE` in the suite and the `FIELD ORDER VERIFIED AGAINST` line in the `.tf`.

The #7530 follow-through probe (`scripts/followthroughs/registry-clientip-alert-7530.sh`) re-runs the
classification table, the as-written count and the private-flagged control after the merge.

## Related

- Alert source and its live-probe record: `apps/web-platform/infra/betterstack-logs-alerts.tf`
  (section `#7530: a registry-plane clientIP that is not RFC1918`).
- Decisions: ADR-218 (native Logs alerts are Terraform-managed), ADR-211 (clientIP is not masked), ADR-184
  (the shipper whose rate-cap sampling and field order this alert consumes).
- The dormant regression probe `zot-log-channel-7440.sh` is tracked separately as #10321; it is not what
  enforces this condition.
- Dispatcher and host replace: [`registry-host-replace-dispatch.md`](./registry-host-replace-dispatch.md).

## After the first graded PASS

The legal records written with this alert say it is **NOT in force** until the merge, the push apply that
creates it and the #7530 follow-through probe's PASS over the new boot's window. The probe's PASS comment
points here (it closes #7530). **The operator who reads that comment owns the re-dating and the CLO attests the
wording.** Open an `action-required` issue first, unconditionally, listing the five places below (`gh issue create
--label action-required --title "Re-date the registry clientIP alert legal records" --body-file <file>`) so the
obligation outlives #7530, then re-date each from "NOT in force" to "in force, graded <date>, counts only" and
close that issue:

1. `knowledge-base/legal/article-30-register.md`, PA-8 (c) and (g): search `registry_clientip_not_rfc1918`.
2. `knowledge-base/legal/audits/2026-08-counsel-review-7440.md`: section 12, the bullet that follows the
   `Superseded 2026-10-14 (#7530)` callout.
3. The same file's frontmatter key `clientip_monitoring_pointer`.
4. ADR-211: the amendment sentence "NOT in force until PR #10320 is merged".
5. ADR-218: the sentence beginning "Delivery state:" inside the `**Parameters.**` bullet of the #7530 amendment (it
   reads "not treated as an enforced invariant", not "NOT in force"; search for the former).

The measured population is the **shipper arm only** (the disk arm has no live positive control), so the
re-dated wording must not claim the disk arm is graded. Nothing automatic does any of this.
