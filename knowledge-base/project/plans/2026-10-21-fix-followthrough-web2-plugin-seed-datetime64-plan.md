---
title: "fix(followthrough): web2-plugin-seed-8743 probe can never grade — toDateTime() rejects DateTime64 marker literal"
type: fix
date: 2026-10-21
slug: fix-followthrough-web2-plugin-seed-datetime64
branch: feat-one-shot-10741-followthrough-datetime64
issue: 10741
closes: 10741
lane: cross-domain
domain: engineering
priority: p2-medium
brand_survival_threshold: none
---

# fix(followthrough): web2-plugin-seed-8743 probe can never grade — toDateTime() rejects DateTime64 marker literal

## Overview

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed).

The #8743 deploy-seeding soak probe (`scripts/followthroughs/web2-plugin-seed-8743.sh`) can never reach a verdict. Its scan query computes `minIf(dt, ...) AS first_marker_dt` over Better Stack's ClickHouse, where `dt` is `DateTime64` — the value comes back carrying microseconds (e.g. `2026-10-21 03:26:45.242796`). The absence query then embeds that literal verbatim in `toDateTime('${first_marker_dt}')`, and ClickHouse rejects the fractional part (Code: 6, HTTP 400), so every sweep exits 2 = NOT YET and tracker #8743 can never close. Sweeper run 39558817568 (2026-10-21) surfaced the exact error:

```
NOT YET: betterstack-query.sh exited 22: curl: (22) The requested URL returned error: 400
Code: 6. DB::Exception: Cannot parse string '2026-10-21 03:26:45.242796' as DateTime: syntax error at position 19
```

The fix substitutes a `DateTime64`-tolerant parse in the absence query, adds a fractional-marker fixture to the probe's test suite, and records the completed sibling sweep under `scripts/followthroughs/` for the same `toDateTime('<variable-timestamp>')` shape. The marker's existence also confirms the #8743 fix under test has already exercised soleur-web-2 — grading is the only thing blocked.

## Research Insights

### Premise Validation (Phase 0.6 — checked live 2026-10-21)

| Cited premise | Result |
|---|---|
| #10741 open | **OPEN** — labels `priority/p2-medium`, `type/bug`, `domain/engineering`, `meta/machinery`; `closedByPullRequestsReferences` empty |
| `scripts/followthroughs/web2-plugin-seed-8743.sh` on `origin/main` | Present, defect verbatim at the `ABSENCE_SQL` `WHERE dt >= toDateTime('${first_marker_dt}')` line; probe introduced by merged commit `57dda4c2` (PR #10577, issue #8743) |
| `dt` is `DateTime64` | Confirmed three ways: the production value carries microseconds; `send-failed-alert-probe-8097.test.sh:186` already expects fractional `row_dt=2026-09-13T14:25:50.123`; prior learnings record the column as `DateTime64(6, 'UTC')` |
| `SCAN_SQL`'s `toDateTime('${SINCE_SQL}')` unaffected | Confirmed — `SINCE_SQL` is formatted `date -u -d ... '+%Y-%m-%d %H:%M:%S'` (probe:132), no fraction |
| Sweeper run 39558817568 | Cited by the issue as the surfacing dispatch; probe exit 2 is the deterministic outcome |

No stale premises. This is a fix plan, not a build plan — the cited artifact exists and misbehaves exactly as described.

### Property List (Phase 0.6b)

- P1: the absence query accepts the marker literal in the shape ClickHouse actually renders it (`DateTime64`, fractional seconds) — the probe can reach PASS/FAIL.
- P2: the absence floor keeps sub-second precision — a `fchmodat2` row earlier in the same second as the first marker stays pre-marker (flooring to the second can false-FAIL the P1 tracker).
- P3: the suite drives red on the pre-fix shape — a revert to `toDateTime('<fractional literal>')` is caught without a live ClickHouse.
- P4: no sibling probe carries the same query-derived-dt-into-`toDateTime` shape — the defect class is closed, not just the instance.

### Mechanism minimality check (Phase 0.6b)

| Proposed mechanism | Property | Already covered by? | Verdict |
|---|---|---|---|
| `toDateTime64('${first_marker_dt}', 6)` in `ABSENCE_SQL` | P1, P2 | Nothing on `origin/main` — the code IS the mechanism | KEEP (issue's named fix) |
| Bash fraction-strip `first_marker_dt="${first_marker_dt%%.*}"` + keep `toDateTime` | P1 only | — | CUT — floors the boundary to the second; a same-second pre-marker `fchmodat2` row grades post-marker → false FAIL on a P1 tracker (violates P2) |
| `parseDateTime64BestEffort('${first_marker_dt}', …, 'UTC')` | P1, P2 | Precedent exists (`registry-clientip-alert-7530.sh:473`, `inngest-provision-rehearsal-capture.sh:211`) | CUT as prescribed fix — BestEffort is looser than needed for a known-shape literal; kept as recorded alternative |
| Fractional-marker fixture + stub-side ClickHouse strictness emulation in `web2-plugin-seed-8743.test.sh` | P3 | Existing stub answers every query shape (a looser-than-production stub — the 2026-09-21 learning class) | KEEP |
| Standing lint over `toDateTime('${var}')` under `scripts/followthroughs/` | P4 durably | — | CUT — cannot distinguish a fraction-free literal (`${SINCE_SQL}`, legitimate) from a dt-derived value without provenance analysis; a regex would false-positive on this very file's line 151. The audit is a one-time census, recorded below |
| `date -d` normalization client-side | P1 | — | CUT — re-implementing a server-side predicate client-side with weaker parsing is a named anti-pattern (`2026-09-18-the-measured-facts-…` §item 19) |

### Sibling sweep census (the ask's third item — performed at plan time)

Mechanical grep `toDateTime|toDateTime64|parseDateTime` over `scripts/followthroughs/` plus a `_dt`-feeding-SQL review:

| Probe | Shape | Verdict |
|---|---|---|
| `web2-plugin-seed-8743.sh:230` | `toDateTime('${first_marker_dt}')` — dt-derived, fraction-carrying | **DEFECT — this fix** |
| `web2-plugin-seed-8743.sh:151` | `toDateTime('${SINCE_SQL}')` — formatted `%Y-%m-%d %H:%M:%S`, no fraction | safe |
| `anthropic-double-bill-8611.sh:91` | `toDateTime(${floor_s})` — epoch integer literal | safe |
| `registry-clientip-alert-7530.sh:473` | `parseDateTime64BestEffort('…', 3, 'UTC')` | safe (fraction-tolerant parser) |
| `inngest-provision-rehearsal-capture.sh:211,501` | `parseDateTime64BestEffort` | safe |
| `git-data-rung2-evidence-capture.sh:625` | `parseDateTimeBestEffort('${SENTRY_SINCE}')` | safe (BestEffort) |
| `zot-restart-plateau-6288.sh:91-96` | `date -d "$first_dt"` on query-derived dt | safe — GNU `date` (9.12 verified) parses fractional seconds; failure arm already exits 2 TRANSIENT |
| `send-failed-alert-probe-8097.sh:288-295` | `date -u -d "${row_dt} UTC"` on query-derived dt | safe — same `date -d` tolerance; suite already pins a fractional `row_dt` |
| `inngest-cutover-flip-rollout-7761.sh`, `inngest-tls-soak-10136.sh`, `compound-promote-draft-edit-10552.sh` | `_dt` vars feed `date -d`/jq, never re-embedded into `toDateTime` SQL | safe |

**Sweep result: line 230 is the only site.** No other fix edits required; the census table lands in the PR body.

### Institutional learnings applied

- `2026-09-18-my-supersession-pointer-named-the-wrong-bracket` §Session Errors 1 — Better Stack rejected `T…Z` ISO as `DateTime64(6,'UTC')` behind `curl: (22) 400`: same strict-parse class.
- `2026-07-18-rca-code-level-root-cause-licenses-fix-…` §Session Errors 1 — `T…Z` → DateTime64 TYPE_MISMATCH; recovery was the space-separated literal. Documents the accepted literal grammar.
- `2026-09-21-curl-retry-flags-…-stubs-were-looser-than-the-code` — a stub that answers shapes production rejects makes mutants invisible: the fixture's stub arm must MODEL ClickHouse's rejection (return the Code: 6 body + nonzero rc), not just answer generously.
- `2026-05-18-defensive-regex-fixture-must-cover-all-anchor-positions` — fixture format variants include fractional seconds.
- `followthrough-convention.md` — exit-code contract (0/1/2/3/78), retirement line already present in the probe header.

### Conventions / file map

- Probe seam: `FT8743_QUERY_SH` env override → stub at `scripts/followthroughs/web2-plugin-seed-8743.test.sh:41-52`; the stub logs every invocation (`INVOCATION` sentinel + full SQL) to `STUB_CALLS` — the calls log is available for a SQL-shape pin.
- Suite registration: `scripts/test-all.sh:5869` — `run_suite "scripts/web2-plugin-seed-8743" bash scripts/followthroughs/web2-plugin-seed-8743.test.sh`; anti-vacuity floor at test.sh:164 (`passes -lt 17`).
- `run_one` (probe:161-183) treats any `betterstack-query.sh` nonzero rc or a body carrying `Code: \d+`/`DB::Exception` as NOT YET — so a stubbed Code-6 response on the absence arm reproduces the production failure mode faithfully.
- TAB-joined decode (probe:190) already tolerates the marker's embedded space; a fractional literal adds only a `.` — no decode change needed. The defensive shape gate (probe:224, `^[0-9]{4}-[0-9]{2}-[0-9]{2}`) already accepts the fractional rendering.
- CLAUDE.md conventions: `#!/usr/bin/env bash`, `set -uo pipefail`, `[[ ]]`, synthesized fixtures only (`cq-test-fixtures-synthesized-only`).

## Files to Edit

- `scripts/followthroughs/web2-plugin-seed-8743.sh` — line 230: `toDateTime('${first_marker_dt}')` → `toDateTime64('${first_marker_dt}', 6)`; adjacent comment (221-223) updated to name the fractional `DateTime64` rendering.
- `scripts/followthroughs/web2-plugin-seed-8743.test.sh` — stub arm emulating ClickHouse's Code-6 rejection; fractional-marker case; SQL-shape pin on the calls log; anti-vacuity floor 17→19.

## Files to Create

None.

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing end-user-facing — the concrete artifact is a wrong verdict comment on internal tracker #8743 (a false FAIL reads "the abort path is still live"; a vacuous PASS silently closes a real soak).
- **If this leaks, the user's [data / workflow / money] is exposed via:** no exposure vector — the probe reads journald-derived Better Stack rows through an already-injected read credential and emits counts + timestamps into a private tracker comment.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** the only touched surface is a repo-local verification script and its fixture suite — no user data path, credential scope, or payment/auth surface changes.

## Observability

The deliverable IS observability machinery (a follow-through probe); this block describes its signal path.

```yaml
liveness_signal:
  what: "SOLEUR_WEB2_SEED_ASSERT verdict line + the sweeper's daily verdict comment on #8743"
  cadence: daily (scheduled-followthrough-sweeper.yml)
  alert_target: "tracker issue #8743 comment thread"
  configured_in: "scripts/followthroughs/web2-plugin-seed-8743.sh directive header + .github/workflows/scheduled-followthrough-sweeper.yml"
error_reporting:
  destination: "sweeper comment (last-4KB capture) on #8743"
  fail_loud: "exit 1 FAIL comment names post_fix_fchmod_rows; exit 2/3 comments name the failing arm and the betterstack-query.sh rc"
failure_modes:
  - mode: "absence query rejects the marker literal (this defect's class)"
    detection: "NOT YET comment carrying 'betterstack-query.sh exited' + the ClickHouse Code fragment; fractional fixture case in the suite"
    alert_route: "#8743 comment → operator"
  - mode: "channel dark (control_rows=0)"
    detection: "CANNOT ESTABLISH comment"
    alert_route: "#8743 comment → operator"
logs:
  where: "GitHub Actions run log for the sweeper + the SOLEUR_WEB2_SEED_ASSERT line in the captured tail"
  retention: "Actions log retention window; the comment persists on the issue"
discoverability_test:
  command: grep -c "toDateTime64(" scripts/followthroughs/web2-plugin-seed-8743.sh
  expected_output: "1"
```

## Guard Contract

### Guard 1 — fractional-marker fixture + stub-side ClickHouse strictness

**Property.** The absence query must parse the marker literal in the shape ClickHouse renders it (`DateTime64`, fractional seconds) while preserving the sub-second floor — a probe whose SQL rejects its own scan's output can never grade.

**Assembly.** The probe's two SQL bodies (`SCAN_SQL`, `ABSENCE_SQL`) as emitted through `run_one`; every query passes the stub's `case "$*"` dispatch in `web2-plugin-seed-8743.test.sh`, which is the chokepoint where ClickHouse's parse strictness is modeled (an `*first_marker_dt*` arm for the scan, a `toDateTime('<fractional literal>')` Code-6 arm for the strictness emulation, the `*` fallthrough for counts).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Restore `toDateTime('${first_marker_dt}')` in the probe | RED — the stub's strictness arm returns Code: 6 / rc 22 on the fractional fixture, probe exits 2, case wants 0 |
| 2 | Delete the stub's strictness arm (guard's own dispatch — stub answers every `toDateTime('…fraction…')` shape as if valid) | RED — the SQL-shape pin asserting `toDateTime64(` in the calls log fails under a `toDateTime` revert that now passes vacuously; the presence assertion for the strictness arm itself fails |
| 3 | Fractional `first_marker_dt` fixture where the calls-log pin pattern is satisfied but the probe embeds the WRONG literal (e.g. `first_marker_dt` replaced by `SINCE_SQL`) | RED — the pin greps the exact marker literal `toDateTime64('2026-10-19 05:12:33.456789'`, not any `toDateTime64(` |
| 4 | Harness: drop the fraction from the fixture (`first_marker_dt` = `2026-10-19 05:12:33`, no `.456789`) | RED — the pin pattern names the fractional literal; proves the fixture drives the property, not a constant |
| 5 | Must-PASS variant: marker literal carrying a different valid fraction (e.g. `…33.000001`) | PASS — the contract permits any fraction ClickHouse emits; the strictness arm keys on `toDateTime(` only |
| 6 | Bump: delete the new cases without raising the anti-vacuity floor | RED — `passes -lt N` floor counts the new assertions |

## Open Code-Review Overlap

Check ran 2026-10-21 against open `code-review` issues for `scripts/followthroughs/web2-plugin-seed-8743{,.test}.sh`: **no per-file matches**. Substring hits on `scripts/followthroughs/` dispositioned:

- #8659 (test-helpers EXIT-trap census): **acknowledge** — this suite does not source `test-helpers` (verified), so it is not a member of that scope-out's census.
- #10462/#10463/#10464 (zot fill-rate probe reviews), #8800 (census sandbox fixture), #8435 (gsc-indexing-drain evidence): **acknowledge** — different probes, unrelated concern.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "use toDateTime64 in the absence query (or equivalent)" [issue #10741 Fix §] | FR-1 / Files-to-Edit `web2-plugin-seed-8743.sh:230` | mapped |
| 2 | "add a fractional-marker fixture to scripts/followthroughs/web2-plugin-seed-8743.test.sh" [brief; issue: "Update …test.sh to cover a fractional first_marker_dt fixture"] | FR-2 / Files-to-Edit `web2-plugin-seed-8743.test.sh` | mapped |
| 3 | "sweep sibling probes under scripts/followthroughs/ for the same toDateTime('<variable-timestamp>') shape" [brief; issue: "check sibling probes"] | Research Insights census table + AC-4 + PR-body record | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `web2-plugin-seed-8743.sh` `toDateTime64` edit | "use toDateTime64 in the absence query (or equivalent)" | asked |
| `web2-plugin-seed-8743.test.sh` fixture additions | "add a fractional-marker fixture" | asked |
| Stub-side Code-6 strictness arm | "add a fractional-marker fixture" | inferred — justification: without modeling ClickHouse's rejection the fixture answers a query shape production refuses; the case is vacuous green on the pre-fix code (2026-09-21 stub-fidelity learning) |
| Calls-log `toDateTime64` SQL-shape pin | "use toDateTime64 in the absence query" | asked — pins the named fix (and its boundary-preservation property) rather than the fraction-stripping equivalent |
| Anti-vacuity floor bump 17→19 | — | inferred — justification: the suite's own floor contract requires the expected count to track added assertions, else the floor lies |
| Sibling census table + PR-body record | "sweep sibling probes under scripts/followthroughs/" | asked |

### Split Assessment

- Subsystems touched: 1 — `scripts`
- Planned files: 2 | Estimated changed lines: ~40
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

- [ ] `scripts/followthroughs/web2-plugin-seed-8743.sh` absence query parses a `DateTime64`-rendered marker: `grep -n "toDateTime64('\${first_marker_dt}'" scripts/followthroughs/web2-plugin-seed-8743.sh` matches at the `ABSENCE_SQL` WHERE clause, and `toDateTime('${first_marker_dt}')` no longer appears.
- [ ] `bash scripts/followthroughs/web2-plugin-seed-8743.test.sh` exits 0 with the new fractional-marker case(s) included, and the anti-vacuity floor equals the new expected pass count (17 + added assertions; prescribe ≥2: the fractional PASS case and the calls-log `toDateTime64` pin).
- [ ] Mutation check (run once locally, recorded in the commit message; the revert itself is never committed): restoring `toDateTime('${first_marker_dt}')` (pre-fix shape) drives the suite RED on the fractional fixture.
- [ ] Sibling sweep re-run post-change: `grep -rn "toDateTime" scripts/followthroughs/` matches only the census-exempt sites — `toDateTime('${SINCE_SQL}')` (fraction-free literal), `toDateTime(${floor_s})` (epoch int), `*BestEffort*` parsers, and the new test-side Code-6 emulation pattern inside `web2-plugin-seed-8743.test.sh` — with no second dt-derived `toDateTime('<variable>')` call site. The census table in this plan is the recorded artifact (ship renders PR-body content from artifacts).
- [ ] No `## Scope Check` BLOCKED marker; `git status` clean at handoff; probe file stays executable (`test -x`).

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — internal CI/verification machinery. The mechanical UI-surface override does not fire (no `components/**/*.tsx`, `app/**/page.tsx`, or `app/**/layout.tsx` in Files to Create/Edit); the GDPR gate finds no regulated-data surface (no schema/auth/API-route/`.sql` edits; the probe reads an existing telemetry store under already-wired read credentials); no new infrastructure (Phase 2.8 skips); no new persistent store or cross-component connection (Phase 2.11 skips); no architectural decision (Phase 2.10 skips — a like-for-like function call on an existing probe).

## Test Scenarios

- **(unit)** Given the stub scan returns `first_marker_dt = "2026-10-19 05:12:33.456789"` and the absence count returns `n=0`, when the probe runs, then it exits 0 (PASS) — on the pre-fix code it exits 2.
- **(unit)** Given the probe emits `ABSENCE_SQL`, then the `STUB_CALLS` log's second `INVOCATION` block contains `toDateTime64('2026-10-19 05:12:33.456789'` (pins fraction-preserving parse).
- **(unit)** Given any query carrying `toDateTime('<literal with a fraction>')`, then the stub returns the ClickHouse-shaped `Code: 6` rejection with nonzero rc — modeling production strictness (the `toDateTime64(` spelling must NOT trip this arm).
- **(unit)** Given a marker literal carrying a different valid fraction (`…33.000001`), when the probe runs, then it still PASSes (the strictness arm keys on `toDateTime(`, never `toDateTime64(`).
- **(integration)** Given the merged probe, when `scheduled-followthrough-sweeper.yml` next runs, then #8743 receives a real verdict (PASS/FAIL/NOT YET-on-evidence) instead of the parse-failure NOT YET — verified on the first sweep post-merge via the posted comment.

## Context

- `SCAN_SQL`'s own `toDateTime('${SINCE_SQL}')` (probe:151) is intentionally untouched — `SINCE_SQL` is formatted without a fraction; changing it would be mechanism without a property.
- `first_marker_dt` on an empty `minIf` renders `1970-01-01 00:00:00.000000` under `DateTime64`; that arm is already excluded by `marker_rows > 0` and parses cleanly under `toDateTime64` anyway.
- The probe's `verdict` line embeds `first_marker_dt` verbatim — the fractional rendering is informational only; no emit change needed.

## References

- Issue: #10741; tracker under verification: #8743; probe introduced by PR #10577 (commit `57dda4c2`)
- Sweeper run that surfaced the defect: 39558817568 (`scheduled-followthrough-sweeper.yml` manual dispatch)
- Convention: `knowledge-base/engineering/operations/runbooks/followthrough-convention.md`
- Learnings: `2026-09-18-my-supersession-pointer-named-the-wrong-bracket`, `2026-07-18-rca-code-level-root-cause-licenses-fix-when-host-discriminator-unavailable`, `2026-09-21-curl-retry-flags-…-stubs-were-looser-than-the-code`, `2026-05-18-defensive-regex-fixture-must-cover-all-anchor-positions`
