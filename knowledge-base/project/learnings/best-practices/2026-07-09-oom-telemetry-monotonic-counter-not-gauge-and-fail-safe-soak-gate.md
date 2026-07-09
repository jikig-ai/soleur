---
title: "OOM telemetry on a fast crash loop needs a monotonic counter, not a point-sampled gauge; and a sentinel-filtering soak gate must require ≥1 positive sample before PASS"
date: 2026-07-09
category: best-practices
module: observability
issue: 6288
tags: [observability, oom, cgroup-v2, telemetry, follow-through, soak-gate, cloud-init, ugrep]
---

# OOM confirmation: monotonic counter beats point-sampled gauge; fail-safe soak gates must assert on positive evidence

## Problem

#6288 enriched the `SOLEUR_ZOT_DISK` cloud-init reporter so a no-SSH registry host could
self-report OOM-vs-not to Better Stack, plus a soak follow-through probe that auto-closes the issue
once the restart-loop plateaus. The implementation passed its own tests + a manual dry-run, but
multi-agent review surfaced three telemetry-design defects that green CI could not catch — each a
reusable trap for any "instrument a blind/headless surface" change.

## Key insights

### 1. On a fast crash loop sampled slowly, confirm OOM with a MONOTONIC cgroup counter, not a gauge

The reporter first confirmed OOM via `zot_anon_mb` = `memory.stat` `anon` (container anonymous RSS)
— a **point-in-time gauge**. But zot crashed every ~15 s while cron sampled every 5 min, so the odds
a sample landed on the pre-OOM anon peak were tiny; the gauge systematically reads a mid-scan (low)
value and the OOM confirmation **false-negatives**. The fix: emit `memory.events` `oom_kill` — a
**monotonic** container-cgroup OOM-kill counter (same cgroup dir). Any nonzero value on the newest
boot proves the cgroup OOM-killed the process, regardless of when you sample. This is the
container-scoped analog of a journald `oom-kill` window count, and it's exactly what the in-repo
precedent `container-restart-monitor.sh` already read (`memory.events`, not `memory.stat`).

**Rule:** when telemetry point-samples a surface that changes faster than the sample interval, key
the *decision* on a monotonic counter (restart count, `oom_kill` count, WAL bytes) — reserve gauges
(`anon`, `mem_used`, queue depth) for context only. A gauge on a fast loop is a coin flip.

### 2. A fail-safe gate that FILTERS sentinels must require ≥1 positive sample before it may PASS

The soak probe filtered `-1` inspect-miss sentinels out of every check (`zot_restarts`,
`zot_anon_mb`). That made it *fail-open by omission*: if `docker inspect` returned empty for the
whole window (daemon fault, container never created, format drift), every FAIL check no-op'd on
sentinels and the probe exited 0 — vacuously closing #6288 while zot was actually DOWN. Filtering
bad data is correct; treating "all data filtered out" as PASS is not. The fix: after filtering,
require ≥1 non-sentinel sample or return TRANSIENT. Three independent review agents converged here.

**Rule:** a soak/health gate that discards sentinel/invalid rows must assert on *positive evidence*,
not on the *absence of negative evidence*. "Window filled but no usable data" is TRANSIENT, never PASS.

### 3. Free-text in a flat `key=value` telemetry line is both a JSON hazard and a spoof vector

`zot_last_err` (a bounded tail of container logs) rode the same space-delimited line as the trusted
fields. Two traps: (a) Go crash traces are tab-indented and a raw C0/DEL byte or mid-sequence UTF-8
is invalid unescaped in a JSON string (RFC 8259) → Better Stack rejects the WHOLE payload in the
exact crash case the field exists for; fix = normalize whitespace-controls to space then keep only
printable ASCII, *then* strip `"`/`\`. (b) A crafted log line containing `exit_code=137`/`boot_id=…`
would be matched by the downstream probe's unanchored greps; fix = put the free-text field LAST and
strip everything from its first occurrence before parsing any trusted field.

**Rule:** any free-text field appended to a structured log line must be (a) reduced to a
JSON-string-safe charset at emit time, and (b) placed last + cut off before field parsing at
consume time. Never trust an unanchored `grep key=` over a line that also carries attacker/vendor free text.

## Session Errors

1. **[forwarded] Concurrent editor/linter touched plan+tasks mid-authoring** — Recovery: reconciled to a consistent state, no data lost. Prevention: one-off external-tooling race; no workflow change.
2. **[forwarded] `betterstack-query.sh` returned oversized output (journald noise)** — Recovery: filtered to the `SOLEUR_ZOT_DISK` marker. Prevention: always pass `--grep <MARKER>` when pulling a specific structured event from a shared Logs table; the default table is noisy.
3. **Called the `Monitor` tool to wait on a background agent** — with wrong params (`timeout` vs `timeout_ms`, missing `description`, schema not loaded) → InputValidationError. Recovery: dropped it — harness auto-notifies when a background agent completes. Prevention: do NOT poll async `Agent`/subagent completion with `Monitor`; the `<task-notification>` fires automatically. Reserve `Monitor` for external state the harness cannot track.
4. **`assert "<desc>" "[ -n \"$LINE_ASSIGN\" ]"` expanded `$LINE_ASSIGN` at call time** — its embedded `"` broke the `eval` quoting → false test FAIL. Recovery: defer the expansion with `\$LINE_ASSIGN` so it evaluates inside the assert's `eval` (matching the sibling field-loop assertions). Prevention: in an `eval`-based `assert "$desc" "$cond"` harness, any shell var referenced in `$cond` whose value can contain quotes MUST be written `\$VAR` (deferred), never `$VAR` (call-time).
5. **`grep -qF '--memory …'` parsed the leading `--` as an option under ugrep** → false test FAIL. Recovery: dropped the leading `--` from the fixed-string anchor. Prevention: the host `grep` is **ugrep** (AGENTS already notes its NUL-data-flag quirk) — a fixed string that starts with `--` must use `grep -F -- 'pat'` or drop the leading dashes. Same ugrep-divergence class as the existing NUL-data note.

## Related

- `apps/web-platform/infra/cloud-init-registry.yml` — the reporter (`SOLEUR_ZOT_DISK`)
- `scripts/followthroughs/zot-restart-plateau-6288.sh` — the soak probe
- `container-restart-monitor.sh` — the in-repo precedent that reads `memory.events`
- [[2026-07-09-terraform-source-guard-must-key-on-arming-class-not-ignore-changes-value]] — sibling #6288-area observability-guard learning
- ADR-062 (container `--memory` cap pattern), ADR-096 (self-hosted zot)
