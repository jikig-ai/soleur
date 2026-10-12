---
title: Vector's journald source admits by OR-over-fields, so SYSLOG_IDENTIFIER=systemd ships via the PRIORITY arm — and consumers bind a path-scoped control
status: adopting
date: 2026-10-12
supersedes: none
issue: 9963
related: [9963, 6551, 8875, 9939]
related_adrs: [ADR-192]
tags: [observability, vector, journald, betterstack, control-row]
brand_survival_threshold: none
---

# ADR-286: Vector's journald source admits by OR-over-fields, so SYSLOG_IDENTIFIER=systemd ships via the PRIORITY arm — and consumers bind a path-scoped control

## Status

**Adopting — 2026-10-12 (#9963).** It becomes `accepted` when the
`SOLEUR_SYSTEMD_JOURNALD_CONTROL` row is observed end-to-end on
`soleur-inngest-prd` (emitted on the dedicated inngest host after the next
`apply_target=inngest-host-replace` dispatch, read back through
`betterstack-assert-absence.sh --control-require` and the rehearsal capture's
`systemd_path_check`). Until then the emit half is unexercised in prod; the
mechanism half is verified against Vector 0.43.1 source and the live row record.
The ordinal is provisional: 286 was free on `origin/main` and no open PR claimed
it on 2026-10-12; `soleur:ship` re-derives it.

## Context

`apps/web-platform/infra/vector.toml` documents three journald sources, and for
months the surrounding text carried a journalctl-AND mental model: that
`include_units` and `include_matches` compose as AND, the way `journalctl`'s own
match args do. Under that model three facts were written down as unexplained:
`SYSLOG_IDENTIFIER=systemd` "Failed to start" rows appearing in Better Stack
(#9963), a live row no source in the file admits (#6551), and observed
PRIORITY-6 inngest lines shipping despite a "INFO+DEBUG drop at source" comment
(`betterstack-logs-alerts.tf`).

The model is wrong. Vector 0.43.1's journald source spawns
`journalctl --follow --all --show-cursor --output=json` with **no match args**
and filters client-side; `contains_match` is `record.iter().any(...)` — an OR
over all record fields, and `include_units` merges into
`include_matches._SYSTEMD_UNIT`. So `[sources.inngest_journald]` admits
`_SYSTEMD_UNIT=inngest-server.service` (any priority) **OR**
`PRIORITY ∈ {0..4}` (any unit, any identifier). Under the real evaluator each
"unexplained" row has a delivery path: PID-1 `Failed to start` rows
(PRIORITY 3) ride the PRIORITY arm to `sinks.betterstack` → Logs source
2457081, PRIORITY-6 inngest lines ride the unit arm, PRIORITY≤2 rows
double-admit via Sources 1+2, and PRIORITY≤4 Source-4 tag rows double-admit via
Sources 1+4.

## Decision

1. **Record the semantics, do not re-architect them.** The source-header
   comments in `vector.toml` now state the OR-over-fields evaluator, the
   systemd delivery path, and both double-admission windows. Semantic
   re-architecture of Sources 1/2 (AND-composition, dedupe) is deferred: the
   OR-arm is load-bearing on purpose — Source 2's PRIORITY≤2 window is the
   crit-row sink pinned for #7898 — so changing admission is a separate
   quota/dedupe decision owned by open issues #6551 and #8875.

2. **Consumers bind a PATH-SCOPED control, not a marker-scoped one.** A
   `SOLEUR_SYSTEMD_JOURNALD_CONTROL` row is emitted hourly as
   `/usr/bin/logger -t systemd -p err` inside `inngest-server-probe.sh` —
   deliberately spoofing `SYSLOG_IDENTIFIER=systemd`, because the property
   under test is that THAT field shape transits the PRIORITY arm, not that the
   marker string survives a search. Marker-substring controls are forgeable by
   the measured contamination class (webhook/issue-body replays carrying the
   marker under a different ident). Reads therefore bind the field, not the
   string: `betterstack-assert-absence.sh` gains a repeatable
   `--control-require <substring>` AND'd into the control predicate (the
   systemd recipe requires `"SYSLOG_IDENTIFIER":"systemd"`), and the rehearsal
   capture's `systemd_path_check` counts marker+field jointly. This is the
   read-side convention ADR-192 established, applied one level down at the
   source-of-truth field.

3. **The `systemd` tag never joins the Source-4 allowlist.** Adding it to
   `include_matches.SYSLOG_IDENTIFIER` would ship all PID-1 chatter — the quota
   cost the allowlist exists to bound. The control rides Source 1's PRIORITY
   arm instead; the `vector-pii-scrub` suite carries the exemption-registry
   entry recording that derivation, plus a never-add pin.

## Consequences

- The "unexplained delivery" framing in vector.toml, `inngest-bootstrap.sh`,
  and `workspaces-luks-verify.yml` is retired; the mechanism is now the
  documented contract, and the suites pin drift on both directions (emit
  removed, priority narrowed, tag allowlisted).
- `soleur-inngest-prd` reports `unshipping` until the dedicated host is
  replaced — the designed conservative verdict, since the emit reaches that
  host only via `apply_target=inngest-host-replace`. vector.toml comment
  changes reach web-1 via the `terraform_data.journald_persistent` replace on
  the next apply.
- Better Stack ingest volume is unchanged on web hosts and +~24 rows/day per
  probe host — trivially within the quota budget #7577 guards.
- #6551 and #8875 inherit the verified mechanism; their remaining work is the
  semantic decision this ADR explicitly does not take.
