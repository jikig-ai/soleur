---
title: "fix: main red after #8578 — bound queue-health issue probe, regen fixture baseline, register the new monitor"
date: 2026-09-22
slug: fix-main-red-queue-health-monitor-drift
branch: feat-one-shot-8586-main-red
issue: 8586
closes: [8586, 8587]
type: fix
lane: cross-domain
---

# fix: main red after #8578 — bound queue-health issue probe, regen fixture baseline, register the new monitor

## Enhancement Summary

**Deepened on:** 2026-09-22 (sequential fallback — no Task-agent fan-out in this harness)
**Sections enhanced:** Acceptance Criteria (gate-scope fix), Files to Edit (audit-script trailing
clause), new "Deepen-Plan Pass" section with halt-gate verdicts and citation verification.

### Key improvements

1. AC1/Phase 4.1 corrected from a `-t`-filtered run to the full `components.test.ts` gate file
   (the CI `test-bun` invocation is `bash scripts/test-all.sh bun` → `bun test plugins/soleur/`).
2. The `sentry-monitors-audit.sh` edit now covers the un-pinned trailing "promoted to 58" clause,
   not just the T25-grepped count line.
3. ADR-033 scheduled-work disposition recorded: the workflow's GH-cron+Sentry shape predates this
   plan (#8578); re-homing is a flagged follow-up, not this PR.

### New considerations discovered

- `gh issue list` without `-L` silently caps at 30 — the invisible default is the defect class the
  #6793 gate forbids; `-L 200` is self-draining across the 30-min cadence if accumulation ever
  exceeds it.
- All cited issues/rules verified live: #8586 OPEN, #8587 CLOSED, #8583 OPEN, #6793/#8450 CLOSED.

## Overview

Merge commit `a13abac721` (PR #8578, the standing Actions queue-health monitor) landed on `main`
with a red check set, and the next merge commit `e4ccff634d` (PR #8510) inherited the identical
failures — verified same-suite, same-delta on both commits (#8586). Four suites fail, all traced
to registration/baseline drift from #8578 rather than to product code:

1. `test-bun` — `components.test.ts` "no executable-surface probe omits -L/--limit without a
   principled exemption" flags the auto-resolve enumeration probe in
   `.github/workflows/scheduled-actions-queue-health.yml` (the `gh issue list --search` call that
   feeds a `for` loop closing issues — an enumerator, not an exempt existence drill).
2. `test-scripts` — `fixture-relative-assert.test.sh` baseline is stale: live SITES=1569 over
   FILES=296 vs baseline 1567/295; the delta is one new row,
   `2\tscripts/actions-queue-health.test.sh` (the unit-test file #8578 added).
3. `test-scripts` — `sentry-monitors-audit.test.sh` T25 "prose counts match the Terraform root":
   the new `sentry_cron_monitor.scheduled_actions_queue_health` raised the tf-root count to 59;
   `apps/web-platform/infra/sentry/README.md` still cites 58 and the Class D comment in
   `apps/web-platform/scripts/sentry-monitors-audit.sh` still cites 58.
4. `test-webplat` — `function-registry-count.test.ts` (c2): `scheduled-actions-queue-health` is a
   `cron-monitors.tf` resource name that maps to no registered cron function and is absent from
   the `NON_INNGEST_MONITORS` allow-list.

The `tenant-integration` failure on the same commits is OUT OF SCOPE (unrelated dev-Supabase
content drift on migration 138, remediated separately — see #8583).

## Problem Statement / Motivation

Every main build stays red until these land, which masks real regressions on subsequent merges —
#8510's merge-commit reds were all inherited noise. The fixes are mechanical and each was
reproduced locally at plan time (see Research Insights).

## Proposed Solution

Four surgical edits, one per failing gate:

- Bound the enumeration probe in `scheduled-actions-queue-health.yml` with `-L 200` (the issue's
  suggested bound; the loop closes at most a handful of `[ci/actions-queue-health]` issues, so 200
  is generous). Bound the two sibling existence drills with `-L 1` as defensive hardening — they
  are exempt today (`.[0].number // empty` + no post-search narrowing) but #8587 directs a sibling
  review, and an explicit cap makes them robust if the exemption rules tighten.
- Regenerate the fixture-relative-assert baseline via the suite's own
  `--write-baseline` flag (the guarded regen path — it refuses to write on scanner failure).
- Update the two T25-pinned prose counts to 59 (README bullet + the audit script's Class D
  addendum line, keeping the `N \`resource "sentry_cron_monitor"\` blocks` one-line pattern T25
  greps).
- Add `"scheduled-actions-queue-health"` to `NON_INNGEST_MONITORS` in
  `function-registry-count.test.ts` with a comment in the file's established convention
  (GHA-fired, no `cron-*.ts` counterpart, no `SENTRY_MONITOR_SLUG`, terminal `sentry-heartbeat`
  step posts the check-in — same class as `scheduled-inngest-health` /
  `scheduled-prod-version-drift`).

## Research Insights

### Premise Validation (Phase 0.6)

- `gh issue view 8586` — OPEN, title "Main red after #8578: test-bun probe gate + stale fixture
  baseline + sentry/cron-monitor suites". Premise holds.
- `gh issue view 8587` — **CLOSED** (2026-09-22, no closing PR — closed manually). The one-shot
  arguments describe it as "open"; it is not. `Closes #8587` in the PR body is still correct per
  the directive — it is idempotent on a closed issue and records that this PR resolves the defect
  the issue tracked.
- `git merge-base --is-ancestor` confirms both `a13abac721` and `e4ccff634d` are ancestors of this
  worktree's HEAD; `git show a13abac721 --stat` shows #8578 touched exactly 6 files (workflow,
  cron-monitors.tf, runbook KB doc, probe script, probe test, test-all.sh registration) — the
  registration omissions this plan repairs.
- `git show origin/main` paths: all five files-to-edit exist on main.

### Reproduction at plan time (all four failures verified locally)

- `bun test plugins/soleur/test/components.test.ts -t "no executable-surface probe omits -L"` →
  1 fail, offender:
  `.github/workflows/scheduled-actions-queue-health.yml: gh issue list --repo "$GH_REPO" --state open  --search 'in:title "[ci/actions-queue-health"` (the line-190 loop probe).
- `bash plugins/soleur/test/fixture-relative-assert.test.sh` → arm A FAIL: baseline rows differ
  (`182a183 > 2\tscripts/actions-queue-health.test.sh`); arm B FAIL: independent totals disagree
  (SITES=1569/files=296 vs baseline 1567/295). Third FAIL line is the suite's deliberate
  self-test, retracted by design.
- `bash apps/web-platform/scripts/sentry-monitors-audit.test.sh` → T25 FAIL ×2: "README
  cron-monitor count disagrees with the tf root (59)" and "the script's Class D comment cites a
  stale cron count (tf root says 59)". Derived live: n_cron=59, n_salert=32, n_alert=0.
- `cd apps/web-platform && npx vitest run test/server/inngest/function-registry-count.test.ts` →
  (c2) FAIL: `expected [ 'scheduled-actions-queue-health' ] to deeply equal []` — the other 8
  assertions pass, including (c) the SENTRY_MONITOR_SLUG ↔ tf direction.
- `npx vitest run test/server/inngest/sentry-monitor-iac-parity.test.ts` → 18/18 PASS already
  (workflow `monitor-slug` ↔ tf `name` parity holds; crontab `*/30 * * * *` mirrors on both
  sides). No edit needed there.
- `bash plugins/soleur/test/fixture-dir-operand-assert.test.sh` → 71/71 PASS — only the
  relative-assert baseline is stale, not its sibling.

### Property List (Phase 0.6b)

1. Every `gh pr|issue list --search` command on an executable surface carries an explicit
   `-L`/`--limit` cap OR qualifies for the existence-drill / `linked:issue #N` exemption
   (#6793 gate property).
2. `fixture-relative-assert.baseline.txt` equals the live residue set row-for-row (equality, not
   a floor — both arms).
3. Every `sentry_cron_monitor` `name` in `cron-monitors.tf` maps to a `SENTRY_MONITOR_SLUG` or a
   `NON_INNGEST_MONITORS` entry (c2 property).
4. Prose that cites the tf-root resource counts (README, audit-script comment) agrees with the
   derived counts (T25 property).

### Cut List (Phase 0.6b)

- None. The issue prescribes the mechanism directly; every edit buys a property above. No new
  machinery is proposed. Alternatives considered and rejected: fixing the 2 residue sites in
  `actions-queue-health.test.sh` instead of regenerating the baseline (the baseline is a
  deliberate residue ledger — "EVERY FAMILY IS GRANDFATHERED"; the issue prescribes regen, and
  rewriting the test file to satisfy a residue scanner is scope creep on a red-main fix).

### Relevant file paths

- `.github/workflows/scheduled-actions-queue-health.yml` — probes at lines ~121, ~168, ~190.
- `plugins/soleur/test/components.test.ts` — the #6793 gate (`findUnlimitedProbes`, exemptions at
  `HAS_LIMIT`/`EXISTENCE_DRILL`/`POST_SEARCH_NARROWING`/`BOUNDED_LINKED_ISSUE`, ~line 739-775).
- `plugins/soleur/test/fixture-relative-assert.test.sh` + `.baseline.txt` — regen via
  `--write-baseline` (guarded: refuses on scanner failure or a wrong-looking scan, ~line 57-83).
- `apps/web-platform/test/server/inngest/function-registry-count.test.ts` — `NON_INNGEST_MONITORS`
  set (line ~83).
- `apps/web-platform/infra/sentry/README.md` — `**58 cron monitors**` bullet (line ~35).
- `apps/web-platform/scripts/sentry-monitors-audit.sh` — Class D comment addendum citing `58
  \`resource "sentry_cron_monitor"\` blocks` (~line 1107).
- `apps/web-platform/infra/sentry/cron-monitors.tf` — the monitor resource (line ~1443); context
  only, NOT edited.

### CLAUDE.md conventions

- Client/server import boundary documented in `apps/web-platform/server/README.md` — not touched.
- `cq-test-fixtures-synthesized-only`, `cq-assert-anchor-not-bare-token` apply to any comment/test
  text we add.

## Research Reconciliation — Spec vs. Codebase

No `spec.md` exists for this branch (no brainstorm ran — direct one-shot entry). Reconciling the
issue/args claims against measured reality instead:

| Claim | Reality (measured) | Plan response |
|---|---|---|
| #8587 is an open issue this PR resolves | #8587 is CLOSED (manual, no PR) | Carry `Closes #8587` anyway per directive; note the state |
| Issue table: "the probe" trips the unlimited gate | Exactly ONE probe trips it — the line-190 enumeration loop. The two `.[0].number // empty` drills are exempt | Bound the flagged probe; bound the siblings defensively per #8587's "review the sibling probe" directive |
| Issue table: sentry-monitors-audit "needs triage — likely unregistered/unmapped monitor surface" | Triage resolved: T25 prose-count parity — two stale counts (58 vs live 59) | Update README bullet + script Class D addendum |
| Issue table: function-registry-count (c2) "plausibly the new workflow isn't in the mapping" | Confirmed — `phantom: [ 'scheduled-actions-queue-health' ]`; fix is `NON_INNGEST_MONITORS` membership, not a cron function | Add the slug with a class-convention comment |
| tenant-integration red on both commits | Out of scope per issue — dev-Supabase drift on migration 138 (#8583) | No action; do not gate this PR on it |

## Technical Considerations

- **`-L` placement.** The gate's `HAS_LIMIT` regex (`/(?:^|\s)(?:-L|--limit)(?:[=\s]|$)/`) accepts
  `-L 200` anywhere in the command as a space-separated token; the attached form `-L200` would NOT
  match and would stay flagged (fail-closed by design). Use the space-separated form.
- **Why `-L 200` on the enumeration loop.** It feeds `for n in $(...)` closing every open
  `[ci/actions-queue-health]` issue; the live set is ≤2 (one UNDER_ASSIGNED + one UNKNOWN issue).
  200 is the bound the issue suggests — generous headroom that still satisfies the gate.
- **Why `-L 1` on the two drills.** Both are `--jq '.[0].number // empty'` existence checks —
  `-L 1` is the exact bound the drill consumes, identical semantics, and documents the cap so the
  exemption is no longer load-bearing.
- **T25's grep shape.** The script-comment assertion is
  `grep -q "${n_cron} \`resource \"sentry_cron_monitor\"\` blocks"` — the count must appear on ONE
  line in exactly that shape inside `sentry-monitors-audit.sh`. Update the existing 2026-09-17
  addendum (currently "58") to "59" and name the queue-health monitor as the third addition; do
  not disturb the historical "56 … re-verified 2026-08-19" sentence (it is a dated claim about the
  live org, deliberately left standing).
- **NON_INNGEST_MONITORS comment convention.** Each entry carries a multi-line justification
  naming the firing mechanism (GHA `schedule:`), the workflow file, why no `cron-*.ts`/
  `SENTRY_MONITOR_SLUG` exists, and the same-class siblings. Match it.
- **Baseline regen is a WRITE to a tracked file** — run it on this branch, inspect the diff (expect
  exactly `+2\tscripts/actions-queue-health.test.sh` and header-count updates if any), and commit
  it in the same commit set as the other edits per the baseline header's own instruction
  ("Regenerate deliberately, in the same commit as the source edit that earned it" — here the
  earning edit is on main already; the regen rides with the repair).
- **No other registry enumerates this surface.** Verified by grep: `scheduled-prod-version-drift`
  and `scheduled-machinery-drift` membership lists live only in `function-registry-count.test.ts`
  (`NON_INNGEST_MONITORS`) and `sentry-monitor-iac-parity.test.ts` (which already passes — its
  cohort assertions name three other slugs explicitly). `test-all.sh` auto-discovers
  `apps/web-platform/scripts/*.test.sh`; `scripts/actions-queue-health.test.sh` was already
  registered by #8578. `lint-workflow-errexit-capture.py` is a scanner, not a registry.

## Files to Edit

| File | Edit |
|---|---|
| `.github/workflows/scheduled-actions-queue-health.yml` | Add `-L 200` to the auto-resolve enumeration probe (~line 190); add `-L 1` to the two existence-drill probes (~lines 121, 168) |
| `plugins/soleur/test/fixture-relative-assert.baseline.txt` | Regenerate via `bash plugins/soleur/test/fixture-relative-assert.test.sh --write-baseline` (adds `2\tscripts/actions-queue-health.test.sh` row; SITES 1567→1569, files 295→296) |
| `apps/web-platform/test/server/inngest/function-registry-count.test.ts` | Add `"scheduled-actions-queue-health"` to `NON_INNGEST_MONITORS` with a class-convention comment (GHA-fired `scheduled-actions-queue-health.yml`, no `cron-*.ts` counterpart, no `SENTRY_MONITOR_SLUG`; terminal `sentry-heartbeat` step posts the check-in; same class as `scheduled-inngest-health`) |
| `apps/web-platform/infra/sentry/README.md` | `**58 cron monitors**` → `**59 cron monitors**` (~line 35) |
| `apps/web-platform/scripts/sentry-monitors-audit.sh` | Class D addendum (~lines 1107-1114): `58 \`resource "sentry_cron_monitor"\` blocks` → `59` on the declaration-count line, name `scheduled-actions-queue-health` as the third post-verification addition, AND update the trailing "silently promoted to 58" clause to 59 (T25 greps only the count line, but leaving 58 there misstates the addendum). Keep the dated 2026-08-19 "56 … live" sentence standing — it is a claim about the live org at that date |

## Files to Create

None.

## Implementation Phases

### Phase 1: Bound the issue probes

- 1.1 Add `-L 200` to the enumeration probe in the "Auto-resolve queue-health issues when healthy"
  step (`.github/workflows/scheduled-actions-queue-health.yml`, the `for n in $(gh issue list …)`
  line ~190).
- 1.2 Add `-L 1` to the two `EXISTING=$(gh issue list … --jq '.[0].number // empty')` drills
  (~lines 121, 168).

### Phase 2: Regenerate the fixture-relative-assert baseline

- 2.1 `bash plugins/soleur/test/fixture-relative-assert.test.sh --write-baseline`
- 2.2 `git diff` the baseline — expect exactly one new data row
  (`2\tscripts/actions-queue-health.test.sh`); abort and investigate if anything else moved.

### Phase 3: Register the monitor and repair the prose counts

- 3.1 Add `"scheduled-actions-queue-health"` to `NON_INNGEST_MONITORS` in
  `function-registry-count.test.ts` with the convention comment.
- 3.2 README.md: `58` → `59` cron monitors.
- 3.3 `sentry-monitors-audit.sh` Class D addendum: `58` → `59` blocks, naming the queue-health
  monitor.

### Phase 4: Verify all four gates green locally

- 4.1 `bun test plugins/soleur/test/components.test.ts` (full file — the gate file for `test-bun`)
- 4.2 `bash plugins/soleur/test/fixture-relative-assert.test.sh` (expect only the deliberate
  retracted self-test line in the ledger and a clean exit)
- 4.3 `bash apps/web-platform/scripts/sentry-monitors-audit.test.sh` (expect 52/52)
- 4.4 `cd apps/web-platform && npx vitest run test/server/inngest/function-registry-count.test.ts`
  (expect 9/9)

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing directly — this is CI machinery. The
  indirect exposure is a red main continuing to mask real product regressions on subsequent
  merges (the #8510 inheritance pattern), which is the user-facing harm the issue exists to stop.
- **If this leaks, the user's [data / workflow / money] is exposed via:** no exposure vector — the
  change edits CI probe flags, test allow-lists, a README count, and a scanner baseline; no
  secrets, user data, or product surface is touched.
- **Brand-survival threshold:** `none`
- `threshold: none, reason: the only sensitive-path match (apps/web-platform/infra/ via
  infra/sentry/README.md) is a documentation count fix — no resource, credential, or runtime
  behavior changes.`

## Observability

```yaml
liveness_signal:
  what: Sentry cron monitor `scheduled-actions-queue-health` (missed check-in pages; UNDER_ASSIGNED flips heartbeat to error)
  cadence: every 30 min via .github/workflows/scheduled-actions-queue-health.yml on.schedule
  alert_target: Sentry issue + [ci/actions-queue-health] GitHub issue (action-required on UNDER_ASSIGNED)
  configured_in: apps/web-platform/infra/sentry/cron-monitors.tf (resource sentry_cron_monitor.scheduled_actions_queue_health) + the workflow's terminal sentry-heartbeat step
error_reporting:
  destination: Sentry cron check-in (status=error on UNDER_ASSIGNED) + GitHub issue filing
  fail_loud: SOLEUR_ACTIONS_QUEUE_HEALTH verdict=… log line on every run; [ci/actions-queue-health] issue on UNDER_ASSIGNED/UNKNOWN
failure_modes:
  - mode: enumeration probe silently truncates the issue set it closes
    detection: test-bun components.test.ts unlimited-probe gate (this PR re-greens it)
    alert_route: red CI on the offending PR
  - mode: monitor itself starved of a runner
    detection: missed Sentry check-in (self-referential liveness)
    alert_route: Sentry page via sentry_cron_monitor
logs:
  where: GitHub Actions run log for the scheduled workflow
  retention: GitHub Actions default retention
discoverability_test:
  command: grep -c 'monitor-slug: scheduled-actions-queue-health' .github/workflows/scheduled-actions-queue-health.yml
  expected_output: "1"
```

## Acceptance Criteria

- [ ] AC1: `bun test plugins/soleur/test/components.test.ts` exits 0 — the full gate file, not a
  `-t` filter (CI's `test-bun` runs `bun test plugins/soleur/` recursively via
  `bash scripts/test-all.sh bun`); `findUnlimitedProbes` over the live corpus returns `[]`.
- [ ] AC2: `bash plugins/soleur/test/fixture-relative-assert.test.sh` exits 0 — arm A row-equality
  and arm B independent-totals both pass (SITES=1569/FILES=296 == baseline).
- [ ] AC3: `bash apps/web-platform/scripts/sentry-monitors-audit.test.sh` exits 0 — T25 prose
  parity holds (README + script comment both cite 59).
- [ ] AC4: `cd apps/web-platform && npx vitest run test/server/inngest/function-registry-count.test.ts`
  passes — (c2) phantom set is empty.
- [ ] AC5: No other suite regresses — `git diff --name-only origin/main...HEAD` lists only the
  five Files-to-Edit rows plus `knowledge-base/` planning artifacts; the four gate commands above
  stay green post-change, plus `bash plugins/soleur/test/fixture-dir-operand-assert.test.sh` and
  `npx vitest run test/server/inngest/sentry-monitor-iac-parity.test.ts` as sibling controls.
- [ ] AC6: The enumeration probe's `-L` uses the space-separated form (`-L 200`, not `-L200`) —
  the gate's `HAS_LIMIT` regex only recognizes separated/`=`-separated forms.
- [ ] AC7: The baseline diff adds exactly the `scripts/actions-queue-health.test.sh` row (count 2)
  and nothing else — any other drift is investigated before commit.
- [ ] AC8: PR body carries `Closes #8586` and `Closes #8587`, each on its own body line.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — CI/test-machinery repair on an existing monitoring
surface.

## Test Scenarios

- Given the bounded probes land, when `findUnlimitedProbes` scans the workflow, then the file
  contributes zero offenders (existence drills now carry `-L 1`; the enumerator carries `-L 200`).
- Given a regenerated baseline, when the scanner runs on the unchanged corpus, then row-for-row
  equality and independent totals agree.
- Given `scheduled-actions-queue-health` in `NON_INNGEST_MONITORS`, when (c2) enumerates
  `cron-monitors.tf` names, then the phantom set is empty — and (d) still passes (the slug is not
  a `SENTRY_MONITOR_SLUG`, so `KNOWN_UNMONITORED_SLUGS` is untouched).
- Given README/script comments updated to 59, when T25 derives n_cron=59 from the tf root, then
  both greps match.
- Regression: verify `sentry-monitor-iac-parity.test.ts` stays green (18/18) — it is adjacent
  coverage over the same slug.

## Success Metrics

- `main` is green on the next merge commit: `test-bun`, `test-scripts` (both shards),
  `test-webplat` pass with the four named failures resolved.
- `gh run list --branch main` shows the post-merge run green modulo the known out-of-scope
  `tenant-integration` failure tracked by #8583.

## Dependencies & Risks

- **Risk: another stale surface.** If a fifth gate trips on the same #8578 delta (not observed —
  the issue's failure table and local reproduction agree on exactly four), treat it the same way:
  reproduce locally, register/regen, extend this PR rather than spinning a follow-up.
- **Risk: baseline regen sweeps unrelated drift.** Mitigated by AC7's exact-diff assertion — the
  regen is inspected before commit.
- **No external dependencies;** no infra apply needed (the `cron-monitors.tf` resource is already
  on main; this PR does not touch `.tf`).

## Open Code-Review Overlap

None — `gh issue list --label code-review --state open` bodies contain no reference to any of the
five files-to-edit (checked 2026-09-22).

## References & Research

- Issue: #8586 (primary), #8587 (already closed manually; closed here again for audit trail),
  #8583 (out-of-scope tenant-integration), #8578 (the PR that introduced the drift), #6793 (the
  unlimited-probe gate), #8450 (the incident the monitor watches for).
- Gate internals: `plugins/soleur/test/components.test.ts` `findUnlimitedProbes` /
  `HAS_LIMIT` / `EXISTENCE_DRILL` / `POST_SEARCH_NARROWING` (~lines 734-775).
- Monitor IaC: `apps/web-platform/infra/sentry/cron-monitors.tf` `sentry_cron_monitor.scheduled_actions_queue_health`
  (~line 1443) — comment documents the slug-parity contract.
- Baseline contract: `plugins/soleur/test/fixture-relative-assert.baseline.txt` header (regen
  command, row-equality semantics).

## Sharp Edges

- The gate flags ONLY the enumeration probe; the two `.[0].number // empty` drills are exempt
  today. Bounding them anyway is deliberate (#8587's sibling-review directive) — do not "simplify"
  the fix back to one probe and leave the review unaddressed.
- `HAS_LIMIT` does NOT recognize the attached `-L200` form — space-separated `-L 200` is required
  (fail-closed contract).
- The T25 script-comment grep needs `59 \`resource "sentry_cron_monitor"\` blocks` on ONE line —
  a wrapped line fails the grep even if the number is right.
- `--write-baseline` refuses to write if the scan fails or looks wrong; do not hand-edit the
  baseline to force it.
- `tenant-integration` stays red after this PR — that is #8583's job, not a regression signal for
  this change.
- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder
  text, or omits the threshold will fail `deepen-plan` Phase 4.6. This plan's is filled.

## Deepen-Plan Pass — 2026-09-22

Executed sequentially by the planning session (no Task-agent fan-out available in this harness;
verdicts are the gates' own, not a delegated review).

### Halt-gate verdicts

| Gate | Verdict | Evidence |
|---|---|---|
| 4.4 Precedent-diff / scheduled-work | PASS (non-triggering) | Plan introduces no scheduled job — the trigger was chosen by merged PR #8578. Precedent inventory: 55 `cron-*.ts` Inngest functions vs 17 `scheduled-*.yml` workflows; see ADR-033 note below |
| 4.45 Verify-the-negative | PASS | `HAS_LIMIT` regex confirmed at `components.test.ts:739` — `-L200` fails the `[=\s]`/EOL tail after `-L`; "no other registry" re-verified via `git grep` on sibling slugs |
| 4.5 Network-outage | SKIP | Zero trigger patterns (SSH/timeout/5xx/handshake); no tf apply with provisioners |
| 4.55 Downtime & Cutover | SKIP | No infra-replace, DDL, or deploy-surface edits |
| 4.6 User-Brand Impact | PASS | Section present; `threshold: none` carries a `reason:` scope-out covering the `apps/[^/]+/infra/` sensitive-path match (README.md doc-only) |
| 4.7 Observability | PASS | All 5 fields non-empty/non-placeholder; `discoverability_test.command` is `grep -c` (allowlisted verb, no SSH, sub-15s, no shell-active chars for Check 10); `expected_output: "1"` is a matchable literal — verified live: prints `1`, rc=0 |
| 4.8 PAT-shaped variables | PASS | Regex sweep: zero hits |
| 4.9 UI wireframe | SKIP | No UI-surface files |
| 4.10 Encryption posture | SKIP (recorded) | Files-to-Edit match no trigger glob; prose token "queue" is the monitor's subject (GitHub-side Actions queue read via `gh`), not a store this plan provisions; no new persistent store or connection |
| 4.11 Guard Contract | SKIP (recorded) | Files to Create: none; the plan satisfies an EXISTING gate (`components.test.ts`) rather than authoring a guard/gate/drift-check |

### Citation verification (all live)

- #8586 OPEN; #8587 CLOSED (manual, no PR); #8583 OPEN ("in-place edits to already-applied
  migrations drift dev ledger") — matches the out-of-scope claim; #6793 CLOSED ("extend the gh
  --search `--state` explicitness lint") — matches gate provenance; #8450 CLOSED (the
  concurrency-ceiling incident) — matches monitor provenance; #8578 merge commit `a13abac721`
  verified ancestor with a 6-file stat.
- Rule IDs cited in this plan (`cq-test-fixtures-synthesized-only`,
  `cq-assert-anchor-not-bare-token`) resolve ACTIVE in `AGENTS.md`.
- `bash scripts/test-all.sh bun` confirmed as the CI `test-bun` invocation (ci.yml:983-984);
  AC1 was corrected from a `-t`-filtered run to the full gate file.

### Learnings applied

- `knowledge-base/project/learnings/2026-09-22-actions-queue-under-assignment-metrics-and-monitor.md`
  (written by the #8578 session): the missed-check-in-pages design (`checkin_margin == interval`,
  heartbeat `if: always()`) is exactly what this plan's Observability section asserts — consistent.
  Its `gh api --paginate --jq` per-page filter warning does not bear on `gh issue list -L` (a
  row cap, not pagination).
- `plan-sharp-edges.md` full pass: AC1 now runs the gate's own scope; AC5's diff-scope claim is a
  `git diff --name-only` post-condition; markdownlint clean (0 issues).

### Refinements folded in by this pass

1. The Class D addendum's trailing "silently promoted to 58" clause (line ~1112) must move to 59
   alongside the grep-pinned count line — T25 does not pin it, but leaving it stale misstates the
   addendum's own arithmetic.
2. **ADR-033 disposition recorded:** `scheduled-actions-queue-health.yml` is a GH Actions cron with
   Sentry integration, which sits outside the "purely git/repo-scoped" GH-cron carve-out — but this
   plan introduces no scheduled job; re-homing the merged monitor to Inngest is an architectural
   decision out of scope for a red-main repair. The learning file's own rationale cuts the other
   way for the failure that matters: when GH runners are starved the monitor cannot run at all, so
   the external `sentry_cron_monitor` missed-check-in is the designed coverage. Candidate follow-up
   issue, not this PR.
3. `-L 200` semantics noted: if >200 open `[ci/actions-queue-health]` issues ever accumulate, one
   healthy run closes the first 200 and the next 30-min run continues — self-draining under the
   bound. (Unbounded, `gh issue list` silently defaults to 30 — which is precisely the invisible
   cap the #6793 gate exists to forbid.)
