---
title: "fix: main red after #12521 — baseline regens, merge-group literals, ADR-276 MD032, apt retry repair"
type: fix
date: 2026-11-10
slug: fix-ci-main-red-baseline-literals-apt-repair
branch: feat-one-shot-12593-ci-repair
issue: 12593
closes: [12593]
lane: cross-domain
domain: engineering
priority: p1-high
brand_survival_threshold: none
---

# fix: main red after #12521 — baseline regens, merge-group literals, ADR-276 MD032, apt retry repair

## Enhancement Summary

**Deepened on:** 2026-11-10 (inline pass — the Devin-CLI pipeline seat has no spawn tool; the per-section/review-agent fan-outs this skill prescribes in parallel were discharged sequentially inline, disclosed per `Reviewed-Coverage: sequential-fallback`)

**Sections enhanced:** Gates verified — 4.6 User-Brand Impact (present, `none` + non-empty scope-out reason for the `apps/*/infra/` sensitive path), 4.7 Observability (5 fields, allowlisted `grep` probe, literal expected output, <15s), 4.8 PAT (clean), 4.9 UI wireframe (non-UI, skipped), 4.10 Encryption (no new store/connection, skipped), 4.11 Guard Contract (no NEW guard authored — the diff re-pins existing guards to live truth and adds a bounded repair step; documented below), 4.12 Scope Check (exactly 1 unfenced occurrence, all asks mapped), 4.13 Task Design (no new autonomous task, skipped). 4.5 network-outage and 4.55 downtime gates: triggers absent.

### Key Improvements

1. **Live values verified, not transcribed from the issue** — `bash scripts/probe-merge-group-coverage.sh` prints `contexts=13 producers=12` on this branch's base; the fixture suite prints `SITES=2523 … vs baseline 2522`; markdownlint reproduces `MD032` at ADR-276:694 exactly.
2. **Apt repair placed INSIDE the existing per-attempt `timeout`** — a wedged `dpkg --configure -a` burns its own attempt allotment, never an unbounded window; elapsed is charged to `spent` via the existing `dt` measurement, preserving the budget contract.
3. **Repair gated on `try > 1`** — attempt 1 is byte-identical to today, so every existing apt-bounded test row that asserts attempt-1 call counts (A1, A13, A14, A17…) needs no re-derivation; a `dpkg` stub in the suite keeps retries hermetic on the host.
4. **Collision handled by construction** — sibling PR #12560 (#12559) covers defects 3+4 only and is red on legs defects 1+2 cause; this PR covers all four deterministic defects plus the apt retry hole, so whichever lands first un-reds the other.

## Overview

PR #12521 (b258336e) merged red, leaving four deterministic red checks on `main` plus two flake-class items (issue #12593). This plan repairs the four deterministic defects with the suites' own documented maintenance paths and fixes the apt retry-poisoning hole the issue scopes in:

1. `plugins/soleur/test/fixture-relative-assert.baseline.txt` — regenerate via the suite's own `--write-baseline` (live: 13 `scripts/ci-oracle-review.sh` sites vs baseline 12; `SITES=2523` vs baseline `2522`).
2. `plugins/soleur/test/required-checks-merge-group-coverage.test.sh` — eight `contexts=14 producers=13` expected literals are stale after the `affected-index-ratchet` context deletion; the engine prints `contexts=13 producers=12` live. Update the eight literals (lines 297, 300, 326, 375, 377, 379, 381, 383). The `contexts=12 producers=11` at line 641 is a synthetic control input to `engine_skipped` (C1b) — values are arbitrary there; audit result: no change.
3. `scripts/test-affected-kb-consumers.baseline.txt` — regenerate via the suite's own `--write-baseline`; expected delta is exactly 5 `scripts/ci-oracle-review<TAB>knowledge-base*` rows sorting in at ~line 165-169 (after the 5 `ci-oracle-lane` rows, before `ci-push-dedupe`).
4. `knowledge-base/engineering/architecture/decisions/ADR-276-…-authority.md:694` — MD032: a `- 2026-11-09 S4 retired…` bullet follows the `Notes:` paragraph with no blank line. Insert one blank line.
5. `apps/web-platform/infra/lib/apt-bounded.sh` — `_gd_apt_install_bounded_cycle` retries apt without repairing a mid-configure cap-kill, so `dpkg was interrupted` (rc 100) poisons every subsequent attempt. Add a `dpkg --configure -a` repair inside the same bounded attempt, before each retry (the file's header already names this accepted limit — update it). Regression row added in `apps/web-platform/infra/apt-bounded.test.sh` with a `dpkg` stub.
6. SKIP — `git-data-rung2-boot-evidence.env` staleness gates `deploy-script-tests-fixed`, which is NOT in the required canonical set (`scripts/ci-required-ruleset-canonical-required-status-checks.json`); the refresh needs a real `--ref main` rung-2 rehearsal on dedicated infra, not a code edit. Recorded as remaining work in the PR body.

## Research Insights

### Relevant file paths (verified on this branch's base, 2026-11-10)

- `plugins/soleur/test/fixture-relative-assert.test.sh` — self-documents the regen: `bash plugins/soleur/test/fixture-relative-assert.test.sh --write-baseline` (baseline header lines 6-8). Live failure: `baseline rows differ from live` + `SITES=2523, hit-lines=2523, files=430 vs baseline 2522 over 430`.
- `plugins/soleur/test/required-checks-merge-group-coverage.test.sh:104-107` — the `engine_green` floor parses `merge-group-coverage=OK contexts=N producers=M` from the engine; the eight `row_green … "contexts=14 producers=13"` call sites pin the live values. Engine: `scripts/probe-merge-group-coverage.sh` → live `contexts=13 producers=12`.
- `scripts/test-affected-kb-consumers.test.sh:400-405` — `--write-baseline` runs the embedded oracle (`baseline` mode) over `test-all.sh --print-selection` + `--enumerate-commands` output, then `LC_ALL=C sort -u`. argv-code rows carry NO classification column (label<TAB>path), so the 5 new rows need no `false-positive:` reason.
- `apps/web-platform/infra/lib/apt-bounded.sh:216-276` — the retry loop; `:243-248` the single `timeout -k 5 "$allot" bash -c '…'` attempt; `:80-81` the header's accepted-limit note this fix removes.
- `apps/web-platform/infra/apt-bounded.test.sh:46-123` — stub-`apt-get` harness (exact-argv; records one line per call to `GD_STUB_CALLS`); `:127-143` `run_helper` puts `$STUB` first on PATH.
- `scripts/ci-required-ruleset-canonical-required-status-checks.json` — 11 required contexts; `deploy-script-tests-fixed` absent → item 6 out of scope.

### Institutional learnings

- Baseline ratchets are row-by-row equal in BOTH directions (header: "a fall reddens exactly like a rise") — regen must produce ONLY the expected delta; any unrelated rewrite is itself a finding to explain.
- `required-checks-merge-group-coverage` literals are maintenance constants: when the required context set deliberately changes (#9729 retired `affected-index-ratchet`), the expected literals move in the same repair — the suite's RED output already proves the engine works.
- `knowledge-base/project/learnings/test-failures/2026-11-10-a-canary-diff-proved-the-baseline-stale-and-naming-a-file-is-a-read-to-a-one-hop-oracle.md` (sibling #12560's own record, on its branch): naming `knowledge-base` in argv IS a read to the one-hop oracle — the 5 `ci-oracle-review` rows are genuine new uncovered references the baseline must record.

### Premise Validation (Phase 0.6)

All four deterministic defects reproduced live on this branch (2026-11-10): fixture suite 2 FAILs (rows differ; SITES 2523 vs 2522); merge-group battery 8 FAILs all of shape `expected GREEN with contexts=14 producers=13 (rc=0)` against an engine printing `contexts=13 producers=12`; markdownlint `MD032` at ADR-276:694; kb-consumers baseline verified missing `ci-oracle-review` rows (grep returns zero; the sort position after `ci-oracle-lane` rows matches the issue's `164a165,169`). Cited issues verified: #12593 OPEN (this work), #12521 MERGED (the red merge — contextual), #12562 OPEN (pin-bump PR these reds block). Collision: PR #12560 OPEN/MERGEABLE, closes #12559, covers defects 3+4 only, itself failing `test`/`test-scripts` legs that defects 1+2 cause — complementary overlap; both regenerated artifacts are deterministic so whichever lands second merges identically. No ADR rejects a proposed mechanism (bug fixes on existing surfaces).

### Property List (Phase 0.6b)

1. `main`'s four deterministic red checks go green: fixture-relative-assert, required-checks-merge-group-coverage, test-affected-kb-consumers, markdown-lint.
2. A mid-configure cap-kill no longer poisons every subsequent apt attempt in `_gd_apt_install_bounded_cycle`.
3. Every regeneration produces exactly the issue-named delta and nothing else.
4. No guard is weakened: every escape used is the suite's own documented regen path.

### Cut List (Phase 0.6b)

- **Editing the baselines by hand** → property 1/3 → both suites ship `--write-baseline`; hand-editing bypasses the oracle and risks unclassified rows (c1 gate).
- **`apt-get -f install` instead of `dpkg --configure -a`** → property 2 → heavier (resolves deps, may fetch); `dpkg --configure -a` is the exact repair the interruption message prescribes.
- **Repair OUTSIDE the attempt `timeout`** → property 2 → a wedged repair would burn budget unaccounted; inside `bash -c` it's capped and charged by the existing `dt` accounting.
- **Unconditional repair on attempt 1** → property 2 → adds a host-dpkg call to a clean first attempt for zero benefit; `try > 1` keeps attempt-1 semantics byte-identical (the header documents the unit suite runs on the host).
- **Refreshing `git-data-rung2-boot-evidence.env`** → property 1 → requires a real rehearsal host run (`--ref main` dispatch + fresh evidence commit by design, never auto-committed); not a code fix, and its gate is non-required. Deferred in the PR body.

## Research Reconciliation — Spec vs. Codebase

| Issue claim | Reality (verified) | Plan response |
|---|---|---|
| "live has 13 ci-oracle-review.sh sites vs baseline 12; SITES 2523 vs 2522" | Confirmed: suite prints `SITES=2523 … vs baseline 2522`; baseline line 462 reads `12\tscripts/ci-oracle-review.sh` | Regen, then verify the diff touches only the expected rows + totals |
| "hardcoded `contexts=14 producers=13` literals … plus a `12/11` line near 641 to audit" | 8 literals at the named lines; line 641's `contexts=12 producers=11` is a synthetic C1b control input — arbitrary by design | Update the 8; leave 641, record the audit |
| "missing 5 `scripts/ci-oracle-review → knowledge-base*` rows (diff at ~164a165,169)" | Baseline has zero `ci-oracle-review` rows; the sort point sits after the five `ci-oracle-lane` rows at ~160-164 | Regen; assert the delta is exactly +5 rows and nothing else |
| "MD032 … :694" | Confirmed by `npx markdownlint` — bullet after `Notes:` paragraph without a blank line | Insert one blank line before `- 2026-11-09 S4 retired` |
| "apt `dpkg was interrupted` poison … fix = repair before each retry" | Confirmed: retry loop re-enters apt with no dpkg repair; header `:80-81` names the accepted limit | Bounded `dpkg --configure -a` on retries + stub + regression row + header update |

## Problem Statement / Motivation

`main` is red on four deterministic checks after #12521's red merge; authored PR #12562 and epic #9927's a1 precondition are blocked behind it, and sibling #12560 cannot go green until defects 1+2 land. The apt retry hole turns one environmental stall into three wasted attempts (flake-class but named in the issue).

## User-Brand Impact

**If this lands broken, the user experiences:** continued red `main` CI blocking every open PR's merge queue — no user-facing artifact (this is repo-internal CI machinery).
**If this leaks, the user's [data / workflow / money] is exposed via:** nothing — the diff contains baselines, test literals, a doc blank line, and a container-side dpkg repair step; no user data path.
**Brand-survival threshold:** none

- `threshold: none, reason: the touched `apps/web-platform/infra/` files are CI test-fixture machinery (bounded apt for git-data rehearsal containers) — they never run in production serving paths and carry no user data.`

## Observability

```yaml
liveness_signal:
  what: the repaired suites' own required-check verdicts on main (fixture-relative-assert, merge-group-coverage, kb-consumers, markdown-lint) plus `FIXTURE_APT_CAUSE`/`FIXTURE_APT_FAILED` markers the bounded-apt cycle already emits
  cadence: every PR + merge_group + main push run
  alert_target: the red check itself (merge queue blocks); apt declines surface as SKIP (loud) / FAIL rows in git-data suite logs
  configured_in: .github/workflows/*.yml existing check registrations — unchanged
error_reporting:
  destination: stderr `FIXTURE_APT_CAUSE: <cause> stage=<update|install|repair> attempt=<n> …` line already emitted by the cycle; this fix adds `stage=repair` as a new observable stage value
  fail_loud: yes — rc 100 + bare `FIXTURE_APT_FAILED` marker is already the decline contract; unchanged
failure_modes:
  - mode: mid-configure cap-kill poisons retry (the defect being fixed)
    detection: `GD_APT_STAGE=repair` line in the apt log followed by a successful update/install, or repeated `stage=update attempt>1` lines without repair
    alert_route: suite FAIL row / SKIP (loud) in the git-data rehearsal legs
  - mode: a wedged `dpkg --configure -a` stalls the retry
    detection: `FIXTURE_APT_CAUSE: timeout stage=repair` — bounded by the same per-attempt cap
    alert_route: same marker path as any other timeout
logs:
  where: `$GD_APT_LOG` (in-container) + CI job log (stderr cause line + scrubbed tail)
  retention: GitHub Actions run-log retention (90 days default)
discoverability_test:
  command: grep -o 'GD_APT_STAGE=repair' apps/web-platform/infra/lib/apt-bounded.sh
  expected_output: GD_APT_STAGE=repair
```

## Files to Edit

- `plugins/soleur/test/fixture-relative-assert.baseline.txt` — `--write-baseline` regen (expected: `ci-oracle-review.sh` 12→13, SITES 2522→2523, +1 row).
- `plugins/soleur/test/required-checks-merge-group-coverage.test.sh` — eight `contexts=14 producers=13` → `contexts=13 producers=12`.
- `scripts/test-affected-kb-consumers.baseline.txt` — `--write-baseline` regen (expected: +5 `scripts/ci-oracle-review<TAB>knowledge-base*` rows only).
- `knowledge-base/engineering/architecture/decisions/ADR-276-demand-first-hosted-runner-budget-merge-group-is-the-full-battery-authority.md` — one blank line before the `- 2026-11-09 S4 retired` bullet (line ~694).
- `apps/web-platform/infra/lib/apt-bounded.sh` — retry-time `dpkg --configure -a` inside the bounded attempt; header note `:80-81` updated to describe the repair.
- `apps/web-platform/infra/apt-bounded.test.sh` — `dpkg` stub + one regression row (poisoned-dpkg → repair → success).

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-12593-ci-repair/tasks.md`, `session-state.md`, `decision-challenges.md` (pipeline artifacts).

## Implementation Phases

### Phase 1 — Deterministic main-red repairs (tasks 1.1–1.4)

1.1. `bash plugins/soleur/test/fixture-relative-assert.test.sh --write-baseline`; diff-verify the delta is only the issue-named rows/totals; re-run suite → green.
1.2. Replace the eight `contexts=14 producers=13` literals with `contexts=13 producers=12` (lines 297, 300, 326, 375, 377, 379, 381, 383); re-run the mutation battery → green. Audit note: line 641 `12/11` is a synthetic control input — unchanged.
1.3. `bash scripts/test-affected-kb-consumers.test.sh --write-baseline`; diff-verify exactly +5 `ci-oracle-review` rows; re-run the ratchet → green.
1.4. Insert the blank line before `- 2026-11-09 S4 retired` in ADR-276; `npx markdownlint` → clean.

### Phase 2 — Apt retry repair (tasks 2.1–2.2)

2.1. In `_gd_apt_install_bounded_cycle`, pass `try` into the bounded `bash -c`; when `try > 1`, run `echo GD_APT_STAGE=repair; dpkg --configure -a || true` before `GD_APT_STAGE=update`. Update the header `:80-81` accepted-limit note to describe the repair.
2.2. In `apt-bounded.test.sh`: add a `$STUB/dpkg` stub logging to its own file (never `GD_STUB_CALLS` — call-count rows pin it), a `dpkg-poisoned` apt mode (first call exits 100 with the `dpkg was interrupted` message, then ok), and a row asserting: repair runs on retry, apt recovers, rc 0. Run the suite → green.

### Phase 3 — Verify + commit (task 3.1)

3.1. Re-run all four repaired suites plus `apt-bounded.test.sh`; `git diff` sanity (only expected deltas); commit per work-skill conventions.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "regenerate (live has 13 `scripts/ci-oracle-review.sh` sites vs baseline 12; SITES 2523 vs 2522)" [issue #12593] | Phase 1.1 / Files-to-Edit baseline | mapped |
| 2 | "hardcoded `contexts=14 producers=13` literals … are wrong after the `affected-index-ratchet` context deletion; live counts are 13 contexts / 12 producers" [issue #12593] | Phase 1.2 / test file literals | mapped |
| 3 | "`scripts/test-affected-kb-consumers.baseline.txt` — missing 5 `scripts/ci-oracle-review → knowledge-base*` rows" [issue #12593] | Phase 1.3 / baseline regen | mapped |
| 4 | "MD032 markdown-lint error. Fix the lint violation minimally (list spacing)" [issue #12593] | Phase 1.4 / ADR-276 blank line | mapped |
| 5 | "add a `dpkg --configure -a` (or `apt-get -f install`) repair BEFORE each retry so a mid-configure cap-kill doesn't poison subsequent attempts" [issue #12593] | Phase 2 / apt-bounded.sh + test row | mapped |
| 6 | "stale `git-data-rung2-boot-evidence.env` (needs a `--ref main` rung-2 rehearsal) — only include if it fails a REQUIRED check" [dispatch brief] | — | descoped — justification: `deploy-script-tests-fixed` is absent from the required canonical JSON and the file is a deliberately non-auto-committed rehearsal artifact; recorded as remaining in the PR body |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Baseline regens ×2 | "Regenerate `plugins/soleur/test/fixture-relative-assert.baseline.txt`", "Regenerate per the suite's own regen mechanism" | asked |
| Literal updates ×8 | "hardcoded `contexts=14 producers=13` literals … are wrong" | asked |
| ADR-276 blank line | "Fix the lint violation minimally (list spacing)" | asked |
| dpkg repair + test row | "add a `dpkg --configure -a` … repair BEFORE each retry … update its regression test if one exists" | asked |
| Verify-live-before-edit step | "Verify the true live values before editing — do not guess" | asked |
| Delta-only regen verification | "Verify each baseline regen produces ONLY the expected delta" | asked |
| `dpkg` stub + `GD_APT_STAGE=repair` stage label | — | inferred — justification: the suite's stub harness is exact-argv and must model every binary the lib invokes; a named stage preserves the scrubbed-cause observability the file's own contract requires |
| Header note update in apt-bounded.sh | "the file's header already names this accepted limit" | inferred — justification: the header would otherwise document a limit the diff removes — leaving it stale falsifies the file's own contract |

### Split Assessment

- Subsystems touched: 3 — `plugins/soleur/test/` (ratchet baselines + literals), `scripts/` (kb-consumers baseline), `apps/web-platform/infra/` (apt-bounded lib + test) + 1 KB doc (ADR-276)
- Planned files: 6 code/data + 3 pipeline artifacts | Estimated changed lines: ~60 (mostly generated TSV)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR — one CI-repair batch per the issue; splitting would leave some legs red and serialize the unblock.

## Acceptance Criteria

- AC1: `bash plugins/soleur/test/fixture-relative-assert.test.sh` exits 0; `git diff` on the baseline shows only the +1 `ci-oracle-review.sh` site delta and SITES/hit-lines 2522→2523.
- AC2: `bash plugins/soleur/test/required-checks-merge-group-coverage.test.sh` exits 0 (73/73); zero remaining `contexts=14 producers=13` literals; line 641 unchanged.
- AC3: `bash scripts/test-affected-kb-consumers.test.sh` exits 0; `git diff` on the baseline shows exactly +5 `scripts/ci-oracle-review<TAB>knowledge-base*` rows and no other change.
- AC4: `npx markdownlint knowledge-base/engineering/architecture/decisions/ADR-276-…-authority.md` exits 0; the diff is exactly +1 blank line.
- AC5: `bash apps/web-platform/infra/apt-bounded.test.sh` exits 0 including the new poisoned-dpkg regression row; the lib's repair runs inside the per-attempt `timeout` and only on `try > 1`.
- AC6: `git diff` on `apt-bounded.sh` names `dpkg --configure -a` inside the bounded attempt; the `:80-81` header note no longer claims no repair runs.
- AC7: `deploy-script-tests-fixed` / rung-2 evidence refresh is NOT in this diff; the PR body names it as remaining work.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure/tooling change (CI ratchet baselines, test literals, container-apt repair).

## Test Scenarios

| # | Scenario | Command | Expected |
|---|----------|---------|----------|
| T1 | fixture baseline regen green | `bash plugins/soleur/test/fixture-relative-assert.test.sh` | `63 assertion(s)` all pass |
| T2 | merge-group literals green | `bash plugins/soleur/test/required-checks-merge-group-coverage.test.sh` | `73 passed, 0 failed` |
| T3 | kb-consumers baseline green | `bash scripts/test-affected-kb-consumers.test.sh` | all rows pass |
| T4 | MD032 cleared | `npx markdownlint knowledge-base/engineering/architecture/decisions/ADR-276-demand-first-hosted-runner-budget-merge-group-is-the-full-battery-authority.md` | exit 0, no output |
| T5 | apt repair regression row | `bash apps/web-platform/infra/apt-bounded.test.sh` | suite green incl. new row |

## Dependencies & Risks

- **PR #12560 overlap:** it carries the same two regenerated/lint files for #12559. Both sides produce the baseline deterministically — a same-content merge is clean; the ADR blank-line fix may differ textually but is one line. Whichever merges first un-reds the other's failing legs. Tracked at ship Phase 7 sync.
- **Mutation-battery pass floor:** `EXPECTED_PASSES=73` pins row count — my diff adds no rows, so the floor stands.
- **apt suite host hermeticity:** the new `dpkg` stub must NOT write to `GD_STUB_CALLS` (call-count rows pin it) — it gets its own calls file.
- **A stale `origin/main` could re-red the literals** if another required-context change lands before merge — ship Phase 7 sync re-verifies the engine output before merge.

## Open Code-Review Overlap

None — `gh issue list --label code-review --state open` queried 2026-11-10; no issue body names any of the six edited files (checked each path with `jq --arg`).
