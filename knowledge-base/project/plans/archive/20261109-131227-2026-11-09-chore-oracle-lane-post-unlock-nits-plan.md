---
title: "chore(ci): oracle-lane post-unlock comment/test nits (deferred scope-out from #12300 review)"
type: chore
priority: p3-low
domain: engineering
brand_survival_threshold: none
requires_cpo_signoff: false
lane: cross-domain
date: 2026-11-09
slug: chore-oracle-lane-post-unlock-nits
branch: feat-one-shot-12375-oracle-lane-nits
issue: 12375
closes: 12375
---

# chore(ci): oracle-lane post-unlock comment/test nits

## Enhancement Summary

**Deepened on:** 2026-11-09
**Sections enhanced:** 5 (Observability added per Phase 4.7 halt; Technical Considerations, Acceptance Criteria, Test Scenarios, Files to Edit tightened)
**Coverage disclosure:** `Reviewed-Coverage: sequential-fallback` — this deepener is a sub-subagent with no Task tool; every fan-out the skill prescribes (per-section research, learnings application, the review-agent discovery pass) was executed inline and sequentially by this process against each role's definition, not by spawned agents. Halt gates 4.6–4.13 were run mechanically where the skill gives a command (PAT regex, unfenced Scope-Check count, `lint-guard-contract.py`, sensitive-path regex, UI glob scan).

### Key Improvements

1. **`## Observability` section added** — deepen-plan Phase 4.7 fires on any non-pure-docs Files-to-Edit; the section declares the battery's own verdict lines as the liveness signal and a 15-second-safe `grep` discoverability probe.
2. **Both prescribed seds verified live against the driver** — `s| && \[ "\$locked" = false \]||` lands on `ci-oracle-lane.sh:384` and `s|\[ "\${ORACLE_LANE_LOCKED:-}" = 1 \]|[ -n "${ORACLE_LANE_LOCKED:-}" ]|` lands on `:137`; both mutants `bash -n` clean. The first draft's `\["\$locked"` (missing the space after `[`) was caught and corrected by the sharp-edges pass.
3. **`MIN_ROWS`/`MIN_MUTANTS` floor note** — deepen-pass read of the verdict block confirmed the floors are minimums (no bump required); optional re-derive recorded.

### New Considerations Discovered

- **Comment-rewrite scope discipline:** the two ci.yml blocks carry accurate context alongside the stale sentence (the `if:` non-empty compare explanation, the ORACLE_HEAD_OK event-agnostic binding, the `S4` input descriptions). Rewrites MUST be scoped to the lock sentences only — replacing the whole comment block would lose accurate content. Recorded as an implementation constraint.
- **Sweep value selection:** `{0, true, on}` chosen — `on` is the highest-value member (the plausible "same as the switch" fat-finger), `0` and `true` cover the numeric/string truthy spellings. `01`, `"1"`, `1␣` are also non-`1` but add no discrimination the three chosen values don't already give.

## Overview

GitHub issue #12375 collects four P3 review nits deferred out of the oracle-lane activation review (PR #12300, merged 2026-11-08) so the unlock diff stayed narrow. The oracle-only fast lane is now armed (`CI_ORACLE_LANE=on` since 2026-11-08), which makes the lock-era comments in `.github/workflows/ci.yml` affirmatively false, leaves the mutation battery carrying a label that misdescribes what its `O-LOCK` mutant proves, leaves the `ORACLE_LANE_LOCKED` env re-lock's exact-`1` semantics unpinned by any non-`1` value, and leaves one `cmp -s` sentinel read as redundant with no stated intent. This change rewrites the stale comments to post-activation semantics, makes the battery discriminate the lock conjunct itself, sweeps non-`1` lock values, and resolves the sentinel's intent — all inside CI/test tooling, no production or product surface.

Spec lacks valid `lane:` — no `spec.md` exists for this branch (plan entered directly from issue); defaulted to `cross-domain` (TR2 fail-closed).

## Problem Statement / Motivation

Four small defects survived the activation PR review by explicit deferral:

1. **False lock claims in workflow comments.** `.github/workflows/ci.yml` still asserts "While `ORACLE_LANE_LOCKED=1` stands in the driver, `active` never becomes `true`" (oracle-selection job header, ~L443) and "While `ORACLE_LANE_LOCKED=1` stands in the driver, `active` is always `false` and nothing is tolerated" (aggregator env comment, ~L2437). The committed `readonly ORACLE_LANE_LOCKED=1` literal was removed from `scripts/ci-oracle-lane.sh` by #12300 — these comments now describe a gate that does not exist, on the repo's most load-bearing skip lever.
2. **Mutation-battery label misdescription.** `scripts/ci-oracle-lane.test.sh:1552` labels `mutate "O-LOCK the arm ignores the lock"` but uses `kill_guard O-ARM` on `$UNLOCKED` driven by `row_switch` — it deletes the whole arm line and proves arm-presence, not lock-conjunct detection. Nothing in the battery proves a mutant that drops *only* the `locked` conjunct would be caught.
3. **`ORACLE_LANE_LOCKED` negative-value sweep gap.** `row_lock()` (test L939-957) pins `ORACLE_LANE_LOCKED=1` (locked) and unset (unlocked) only. `SWITCH` gets a 13-value invalid sweep in `row_switch`; the lock gets none. A `-n`-style loosening of `O-LOCK-READ` (`[ "${ORACLE_LANE_LOCKED:-}" = 1 ]` at driver L137) would silently re-darken the lane — safe direction, but a semantics gap: under today's pins, `-n` is observationally identical to `= 1`.
4. **`cmp -s` recipe pin reads as redundant.** Test L1060-61 pins `cmp -s "$PRISTINE" "$UNLOCKED"` == 0, which follows deterministically from `_lockn == 0` given `LOCK_RE` drives both the count and the recipe — its residual property (recipe blast-radius sentinel) is unstated.

## Research Insights

**Premise validation (Phase 0.6):** Issue #12375 is OPEN; its premises verified against the live tree. PR #12300 is MERGED (2026-11-08T07:12Z), #12156 CLOSED, epic #11556 OPEN. All four cited code sites exist but the issue's line numbers drifted ~100-300 lines (`~L429-437` → actual L432-444; `~L2346` → actual L2437; `~L1371` → actual L1552; `~L1051-52` → actual L1060-61) — expected, per the corpus learning that literal ranges stale. `gh issue view 12375` supplies the authoritative item list; the plan anchors by content, not line number. Collision precheck: PR #12475 names #12375 but is this pipeline's own empty draft (`feat-one-shot-12375-oracle-lane-nits`, 0 files) — not a foreign duplicate; two foreign `test-all.sh` runs in an unrelated worktree reported and disregarded. ADR corpus check (mechanism): ADR-276 + its 2026-11-07/08 amendments document the unlock and env re-lock design; the ask's mechanisms (comment edits, battery rows) conflict with no ADR decision or rejected alternative.

**Mechanism minimality (Phase 0.6b).**

*Property List:* (P1) every live comment describing the oracle lane's lock state asserts post-unlock truth; (P2) the mutation battery discriminates the O-ARM `locked` conjunct specifically, and every mutant label names what its row proves; (P3) the `O-LOCK-READ` exact-`1` compare is pinned against non-`1` values so a `-n` loosening is provably detected; (P4) the `cmp -s` pin carries stated intent.

*Cut List:* none — every mechanism the issue proposes buys a named property; no existing mechanism on `origin/main` covers any of them (that is why the issue exists).

**Value-proposition measurement (Phase 0.6c):** not applicable — no cost/performance saving is claimed.

**Repo research (inline, sequential-fallback — this planner has no Task tool; roles executed in-process):**

- `scripts/ci-oracle-lane.sh:137` — `[ "${ORACLE_LANE_LOCKED:-}" = 1 ] && locked=true  # GUARD:O-LOCK-READ` — the env re-lock, exact-`1` compare.
- `scripts/ci-oracle-lane.sh:384` — `{ [ "$oracle_only" = true ] && [ "$sw" = on ] && [ "$locked" = false ]; } && { active=true; skip_legs="$would_skip"; } || true  # GUARD:O-ARM` — the conjunct the surgical mutant removes.
- `scripts/ci-oracle-lane.test.sh:243-245` — `LOCK_RE='^readonly ORACLE_LANE_LOCKED=1([[:space:]]+#.*)?$'`; `UNLOCKED` produced by `sed -E "/$LOCK_RE/d" "$PRISTINE"`.
- `scripts/ci-oracle-lane.test.sh:916-957` — `row_switch` (13-value invalid sweep to mirror) and `row_lock` (insertion point).
- `scripts/ci-oracle-lane.test.sh:1490-1514` — `mutate()` contract: asserts the sed LANDED (`cmp -s` non-identical) and is well-formed (`bash -n`), then drives the named rows in PROBE mode and requires ≥1 check failure.
- `scripts/ci-pr-selection.test.sh:1455` — sibling precedent for the surgical lock-conjunct mutant: `'s| \&\& \[ "\$locked" = false \]; then  # GUARD:G2-13-ARM$|; then|'` driven by `row_lock`. This is the ported shape.
- `scripts/ci-pr-selection.test.sh:1454` and sibling `O-SWITCH` mutant at oracle test L1549 — `-n`-loosening mutant precedent (`'s|\[ "\${SWITCH:-}" = on \]|[ -n "${SWITCH:-}" ]|'`).
- `scripts/ci-pr-selection.sh:90` — `readonly PR_AFFECTED_LOCKED=1` **still stands**: the ci.yml L2430 pr-selection lock comment is accurate and MUST NOT be touched.
- `drive()` contract (test L533+): `KEY=VALUE` args append to `env -i` after defaults (later wins); `UNSET:SWITCH` removes a default. `ORACLE_LANE_LOCKED=<v>` needs no UNSET machinery — the default env carries no lock var.

**Stale-comment census (write-boundary sentinel sweep, `hr-write-boundary-sentinel-sweep-all-write-sites`):** `grep -rn` for `ORACLE_LANE_LOCKED` / `stands in the driver` / `locked dark phase` / `dark launch` across live files found exactly FOUR stale comment sites — the two the issue names plus two same-class instances it did not: `apps/web-platform/test/c4-likec4-version-pin.test.ts:262-264` and `scripts/ci-draft-light.test.sh:99`. Confirmed NOT stale: ci.yml:2430 (pr-selection lock — `PR_AFFECTED_LOCKED=1` still stands), c4 test:256-257 (same lock), driver + battery headers (already post-activation), runbook `knowledge-base/engineering/operations/runbooks/ci-oracle-lane.md` (already updated), ADR-276 amendments + archived plans/specs (point-in-time records by convention).

**Applicable institutional learnings:**

- `2026-11-07-a-pin-whose-harness-runs-only-arg-two-passes-vacuously.md` — "mutate-probe every new pin: delete the thing it pins and watch it go red"; the new sweep rows get exactly that probe via the `-n` loosening mutant.
- `2026-08-09-my-tests-pinned-a-constant-by-indexing-it-and-my-mutants-read-as-survivors.md` — a mutation battery is only as trustworthy as its harness; `mutate()`'s landed + well-formed assertions cover the harness half.
- `2026-11-07-a-row-resplit-stales-every-literal-range-in-the-corpus.md` — anchor assertions by content, never line number; the issue's ~L numbers already drifted.
- `2026-11-05-a-classifier-run-from-the-candidate-tree-can-be-forged-by-the-diff-it-judges.md` — oracle-lane context: the classifier's authority model.

**Research coverage disclosure:** `soleur:engineering:research:repo-research-analyst` and `soleur:engineering:research:learnings-researcher` roles were executed inline and sequentially by this planner (no Task tool in subagent context) — `Reviewed-Coverage: sequential-fallback`. `soleur:engineering:discovery:functional-discovery` (Phase 1.5b): assessed inline — the "functionality" is editing this repo's own committed files; community-registry overlap is impossible by construction; skipped. External research (Phase 1.6/1.6b): skipped — internal CI test tooling with a precisely-scoped issue and verified code references; no unfamiliar territory. `soleur:engineering:cto` (Phase 2.5 Engineering domain + technical rulings): emulated inline via the agent's Rule interface with repo-verified evidence; rulings recorded in `knowledge-base/project/specs/<branch>/decision-challenges.md`.

## Research Reconciliation — Spec vs. Codebase

| Claim | Reality | Plan response |
|---|---|---|
| [issue] "ci.yml ~L429-437 oracle-selection comment; ~L2346 aggregator env comment" | Stale comments at ci.yml:432-444 and ci.yml:2437 (drifted) | Anchor edits by comment content; ACs grep text, not line numbers |
| [issue] "mutant ~L1371" | Row at test:1552 | Same — content anchor |
| [issue] "cmp -s pin ~L1051-52" | Pin at test:1060-61 | Same — content anchor |
| [issue] names two comment sites | Four live stale sites exist (sentinel sweep): + c4-likec4-version-pin.test.ts:262-264, + ci-draft-light.test.sh:99 | Fold in as inferred scope (justified in Scope Check + `operator (scope)` row) |
| [implicit] pr-selection lock comments equally stale | `PR_AFFECTED_LOCKED=1` still stands at ci-pr-selection.sh:90 — those comments are accurate | Explicit non-goal: do not touch them; AC pins they are unchanged |

## Proposed Solution

Four independent one-to-few-line changes in one PR:

1. **Comment rewrites (4 sites).** Replace each stale lock claim — and ONLY the lock sentences — with post-activation semantics (the surrounding accurate text stays: the `if:` non-empty compare explanation, the ORACLE_HEAD_OK event-agnostic binding, the S4 input descriptions): the compile-time `readonly ORACLE_LANE_LOCKED=1` was removed by #12300 on 2026-11-08; `ORACLE_LANE_LOCKED=1` in env remains as an unwired dark-mode revert path; `active` becomes `true` on an oracle-only diff with `SWITCH=on` and no env re-lock. The "SWITCHED OFF, THEN DARK AND LOCKED" staging header becomes armed-state phrasing. The ci-draft-light parenthetical is rephrased to name the live distinction (`ORACLE_LANE_LOCKED=1` env re-lock leaves `oracle_only` true while `active` stays false).
2. **Battery label + surgical mutant.** Retitle `mutate "O-LOCK the arm ignores the lock" "$UNLOCKED" "$(kill_guard O-ARM)" row_switch` to name arm-presence; add `mutate "O-LOCK the arm's lock conjunct is dropped" "$PRISTINE" 's| && \[ "\$locked" = false \]||' row_lock`, porting the sibling's proven shape (ci-pr-selection.test.sh:1455). Only `row_lock` can kill it — it drives `ORACLE_LANE_LOCKED=1` and asserts `active=false`; with the conjunct gone the mutant arms under the re-lock.
3. **Negative-value sweep in `row_lock`.** After the existing `ORACLE_LANE_LOCKED=1` block, a `for v in 0 true on` loop: `drive accept "$d" "SWITCH=on" "ORACLE_LANE_LOCKED=$v"` asserting `active=true`, `skip_legs=$ORACLE_FIVE`, `locked` notice field `false` — the exact-`1` semantics, pinned.
4. **`cmp -s` intent annotation.** One comment line above the check naming the residual property: `_lockn` pins the lock literal absent; the `cmp` pin bounds the recipe's blast radius — a `LOCK_RE`/recipe edit matching anything else reds here while `_lockn` stays green, and `$UNLOCKED` is the file `row_switch` + three mutants are measured against.
5. **`-n` loosening mutant** (the probe the new pins are for): `mutate "O-LOCK the lock-read is loosened to non-empty" "$PRISTINE" 's|\[ "\${ORACLE_LANE_LOCKED:-}" = 1 \]|[ -n "${ORACLE_LANE_LOCKED:-}" ]|' row_lock` — survives today's pins (identical observable under `=1`/unset), killed by the new sweep.

## Technical Considerations

- **Verification approach:** the whole change is inside the suite's own machinery — `mutate()` self-verifies each row landed and was detected; `bash scripts/ci-oracle-lane.test.sh` green is the gate. ci.yml edits are comment-only (no `run:`/`env:`/`if:` change) so they pay the oracle exclusion list (full battery) — expected and cheap on a docs-sized diff.
- **Base choice for the surgical mutant:** `$PRISTINE`, matching the sibling — the mutant must be measured against the real driver, not the (currently byte-identical) neutralized copy.
- **No new fixture needed:** `accept` (already used by `row_lock`) produces the oracle-only diff the arm needs.
- **Sed anchoring:** the simple `s| && \[ "\$locked" = false \]||` expression is safe (verified live at plan time: lands on driver:384, `bash -n` clean) — `grep` confirms `[ "$locked" = false ]` appears on exactly one driver line; `mutate()`'s landed-check is the backstop. The sibling's `GUARD:`-suffix anchor is available if the unanchored form ever matches a second site.
- **Assertion/mutant floors:** the battery's `MIN_ROWS=400` and `MIN_MUTANTS=20` are floors, not exact counts — the ~15 new check rows and 2 new mutants stay comfortably above both. The floor block's own comment says "re-derive after adding a row" via `bash scripts/ci-oracle-lane.test.sh | tail -1`; raising `MIN_ROWS` to the new measured total is optional hardening, not required (the floor's job is catching removed rows, and bumping it only tightens). Implementer may bump it to the fresh count in the same commit — cheap and keeps the derivation comment honest.
- **NFR impacts:** none — CI-internal comments and test assertions; no runtime, security boundary, or data surface change.

## Alternative Approaches Considered

| Option | Verdict |
|---|---|
| Retitle-only for item 2 | **Rejected (CTO ruling T1)** — fixes the label but leaves the lock conjunct unproven: a conjunct-dropping mutant survives today's battery |
| Surgical mutant + retitle for item 2 | **Adopted (CTO ruling T1)** — sibling precedent, closes the property, ~1 line |
| Drop the `cmp -s` pin for item 4 | **Rejected (CTO ruling T2)** — loses the recipe blast-radius sentinel that `_lockn` does not give |
| Annotate `cmp -s` as intentional | **Adopted (CTO ruling T2)** — one comment line preserves the sentinel and resolves the nit |
| Defer the two extra stale-comment sites | **Rejected** — identical defect class found by the mandated repo-wide sweep; leaving them preserves the false-confidence signal the issue names (folded in as inferred scope; `operator (scope)` row recorded) |

## Files to Edit

- `.github/workflows/ci.yml` — oracle-selection job header comment (~L432-444, comment-only) and aggregator env comment (~L2437, comment-only). The pr-selection lock comment (~L2430) is explicitly untouched.
- `scripts/ci-oracle-lane.test.sh` — `row_lock()` sweep loop (after the `ORACLE_LANE_LOCKED=1` assertions), retitle of the `kill_guard O-ARM` mutant, new surgical `O-ARM` conjunct mutant, new `-n`-loosening `O-LOCK-READ` mutant, intent comment at the `cmp -s` pin.
- `apps/web-platform/test/c4-likec4-version-pin.test.ts` — oracle-lane comment ~L262-264 (comment-only).
- `scripts/ci-draft-light.test.sh` — parenthetical comment ~L99 (comment-only).

## Files to Create

None.

## Open Code-Review Overlap

None — `gh issue list --label code-review --state open` bodies searched for both file paths on 2026-11-09; zero matches.

## User-Brand Impact

- **If this lands broken, the user experiences:** a red `ci-oracle-lane` battery blocking merges in this repo — the plugin's CI stalls its own release train; a wrong comment edit could re-instill false confidence in the lane's lock state, which is a maintainer-facing hazard, not a user-facing artifact.
- **If this leaks, the user's [data / workflow / money] is exposed via:** nothing — the diff touches CI comments and a test harness; it carries no user data, credentials, or tenant surface.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** the diff is confined to internal CI/test files with no user data, auth, or production surface; worst case is a red gate blocking merges, not a user-visible defect.

## Observability

```yaml
liveness_signal:
  what: "the ci-oracle-lane mutation battery's own verdict lines (`mutation battery: K/K killed`, `ci-oracle-lane.test.sh: N rows, P passed, F failed`) and the GUARD anchors on the driver"
  cadence: "per-PR (the battery runs in the test leg on every pull_request/merge_group) + local on-demand"
  alert_target: "the PR's required check status"
  configured_in: ".github/workflows/ci.yml (test leg) + scripts/ci-oracle-lane.test.sh"
error_reporting:
  destination: "GitHub Actions step output and PR check status"
  fail_loud: "non-zero exit from scripts/ci-oracle-lane.test.sh reds the check; `surviving mutants` names each undetected edit on stderr"
failure_modes:
  - mode: "battery loses discrimination (a mutant survives)"
    detection: "the battery's own MUT_KILLED < MUT_TOTAL verdict plus the surviving-mutants stderr list — this change adds two mutants to that machinery"
    alert_route: "PR check failure (blocks merge)"
  - mode: "stale lock-era comment claims re-accumulate"
    detection: "code review only — the defect class is prose and has no mechanical signal; the cmp -s annotation is the stated-intent record that prevents the same question recurring"
    alert_route: "PR review"
logs:
  where: "GitHub Actions run logs (test leg) and local stdout"
  retention: "GitHub run-log retention (~90 days)"
discoverability_test:
  command: grep -c 'GUARD:O-ARM' scripts/ci-oracle-lane.sh
  expected_output: "1"
```

## Guard Contract

### Guard 1 — the O-LOCK / O-ARM mutation discrimination in `scripts/ci-oracle-lane.test.sh`

**Property.** A driver edit that drops only the arm's `locked` conjunct, or loosens the `O-LOCK-READ` exact-`1` compare, is detected by the battery — the lane cannot be silently re-darkened or silently armed under a re-lock.

**Assembly.** Every `mutate` row in the battery block (~L1518-1561) and every `check_eq`/`check_true` row in `row_lock`/`row_switch` measured via `drive()`; the chokepoint is `mutate()` itself (a row that skips it is invisible) and `row_lock` (the only row driving `ORACLE_LANE_LOCKED`).

**Mutation matrix:**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | Remove ` && [ "$locked" = false ]` from the `GUARD:O-ARM` line of the driver | RED — killed by `row_lock` via the new surgical mutant |
| 2 | Loosen `[ "${ORACLE_LANE_LOCKED:-}" = 1 ]` to `[ -n "${ORACLE_LANE_LOCKED:-}" ]` in the driver | RED — killed by the new non-`1` sweep in `row_lock` via the `-n` mutant row; guard's own dispatch: if the sweep never runs, this survives and the battery must report SURVIVED, not green |
| 3 | Change `= 1` to `= 0` in `O-LOCK-READ` (inverted compare; a second wrong member after the compliant `=1`) | RED — the existing `ORACLE_LANE_LOCKED=1` drive asserts `active=false` → `locked` never sets → check fails |
| 4 | Harness edit: in the new sweep, assert `active=false` for `ORACLE_LANE_LOCKED=0` (edit to the SUITE, not the driver) | RED — the unmutated driver yields `active=true`; the check must fail on baseline |
| 5 | Must-PASS non-canonical input: `ORACLE_LANE_LOCKED= ` (whitespace) or `ORACLE_LANE_LOCKED=` (explicit empty) is NOT `1` | PASS semantics — `active=true`; confirms the guard is not a reject-everything stub |

**Anchor.** The mutants anchor on committed driver text (`GUARD:O-ARM`, `O-LOCK-READ` lines) and `mutate()` asserts each sed LANDED; a driver edit that evades both anchors must also defeat the `O-LITERAL`/`check_true` greps pinning `ORACLE_LANE_LOCKED:-` in `$PRISTINE` — one diff cannot move both the pin and the thing pinned without reddening `_lockn`/O-LOCK static rows.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "**`ci.yml` stale lock-era comments** — `.github/workflows/ci.yml` (~L429-437 `oracle-selection` comment; ~L2346 aggregator env comment) still say \"While `ORACLE_LANE_LOCKED=1` stands in the driver, `active` never becomes `true` … nothing is tolerated\". … Suggested: one-line comment tidy in any next workflow-touching PR." [issue #12375] | Files-to-Edit ci.yml / Phase 1 / FR-1, AC-1..3 | mapped |
| 2 | "**Mutation battery label misdescribe** — `scripts/ci-oracle-lane.test.sh` (~L1371): mutant `\"O-LOCK the arm ignores the lock\"` uses `kill_guard O-ARM`, deleting the whole arm — proves arm-presence, not lock-conjunct detection. Retitle, or add a surgical `lock` conjunct mutant driven by `row_lock` (test-design seat)." [issue #12375] | Files-to-Edit test.sh / Phase 2 / FR-2, AC-4 | mapped |
| 3 | "**`ORACLE_LANE_LOCKED` negative-value sweep** — `row_lock()` pins only `=1` and unset; `SWITCH` gets a 13-value invalid sweep, the lock gets none. … Add 2-3 non-`1` values (`0`, `true`, `on`) asserting `active=true`." [issue #12375] | Files-to-Edit test.sh / Phase 3 / FR-3, AC-5 | mapped |
| 4 | "**`cmp -s` recipe pin redundancy** — `ci-oracle-lane.test.sh` (~L1051-52): the `cmp -s \"$PRISTINE\" \"$UNLOCKED\"` no-op pin is logically redundant with `_lockn == 0`. Harmless belt-and-suspenders; either annotate as intentional or drop." [issue #12375] | Files-to-Edit test.sh / Phase 4 / FR-4, AC-6 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| ci.yml comment rewrites (2 sites) | asks 1 | asked |
| Mutant retitle + surgical `O-ARM` conjunct mutant | "Retitle, or add a surgical `lock` conjunct mutant driven by `row_lock` (test-design seat)." | asked (both arms of the either/or taken per CTO ruling T1) |
| `row_lock` non-`1` sweep (`0`/`true`/`on`) | "Add 2-3 non-`1` values (`0`, `true`, `on`) asserting `active=true`." | asked |
| `cmp -s` intent annotation | "either annotate as intentional or drop" | asked (annotate arm per CTO ruling T2) |
| `mutate` row: `-n` loosening of `O-LOCK-READ` driven by `row_lock` | — | inferred — justification: the issue's own threat model names "a `-n`-style loosening of `O-LOCK-READ`"; the repo's battery convention (learning 2026-11-07) requires every new pin be proven by a mutant, and only this row proves the sweep discriminates — without it the sweep is unverified assertion code |
| c4-likec4-version-pin.test.ts comment fix | — | inferred — justification: identical stale-lock defect found by the mandated repo-wide `ORACLE_LANE_LOCKED` sweep; leaving it preserves the exact false-confidence signal the issue names (`operator (scope)` row in decision-challenges.md) |
| ci-draft-light.test.sh comment fix | — | inferred — justification: same defect class ("locked dark phase" present-tense claim); same `operator (scope)` row |

### Split Assessment

- Subsystems touched: 3 — `.github`, `scripts`, `apps/web-platform` (a single comment in `apps/web-platform/test/`)
- Planned files: 4 | Estimated changed lines: ~35
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR — all under thresholds; the two extra files are comment-only and inseparable in defect class

## Acceptance Criteria

- [ ] AC-1: `grep -n 'ORACLE_LANE_LOCKED' .github/workflows/ci.yml` returns zero comment lines claiming a lock literal "stands in the driver" or that `active` "never becomes"/"is always" `false`; both rewritten comments describe the env re-lock as an unwired revert path and `active` as reachable post-arm.
- [ ] AC-2: the pr-selection S4 comment ("While the activation lock holds", ~L2430) and the `PR_AFFECTED_LOCKED` references in `scripts/ci-pr-selection.sh`/its suite are byte-unchanged by this diff (`git diff` shows no hunk touching them).
- [ ] AC-3: `apps/web-platform/test/c4-likec4-version-pin.test.ts` and `scripts/ci-draft-light.test.sh` contain no present-tense "stands in the driver"/"locked dark phase" lock claims about `ORACLE_LANE_LOCKED`.
- [ ] AC-4: the battery has no `mutate` row whose label claims lock-conjunct detection while killing `O-ARM` wholesale; the retitled row names arm-presence; a `mutate` row sed-removing ` && [ "$locked" = false ]` from the `GUARD:O-ARM` line of `$PRISTINE` driven by `row_lock` exists.
- [ ] AC-5: `row_lock` drives `accept` under `SWITCH=on` with `ORACLE_LANE_LOCKED` ∈ {`0`, `true`, `on`} asserting `active=true`, `skip_legs=$ORACLE_FIVE`, notice `locked=false`.
- [ ] AC-6: a `mutate` row loosening `O-LOCK-READ` `= 1` to `[ -n … ]` driven by `row_lock` exists; the `cmp -s "$PRISTINE" "$UNLOCKED"` pin carries an intent comment naming the recipe-blast-radius property.
- [ ] AC-7: `bash scripts/ci-oracle-lane.test.sh` exits 0 printing `mutation battery: K/K killed` with K equal to the row count and zero entries under `surviving mutants` — all control rows green and every mutant killed (the new surgical and `-n` mutants included; their rows appearing in the battery is what makes AC-4/AC-5 verifiable rather than asserted).
- [ ] AC-8: `bash -n scripts/ci-oracle-lane.test.sh` clean; no non-comment line of `.github/workflows/ci.yml`, `apps/web-platform/test/c4-likec4-version-pin.test.ts`, or `scripts/ci-draft-light.test.sh` changed (`git diff` shows only `+`/`-` lines beginning with comment syntax in those files).

## Domain Review

**Domains relevant:** Engineering

### Engineering

**Status:** reviewed
**Assessment:** Small precisely-scoped tech-debt on the repo's most load-bearing CI lever. Two technical forks (retitle-vs-mutant, annotate-vs-drop) ruled by the CTO Rule interface emulated inline (no Task tool in subagent context) — both favor the stricter/coverage-preserving arm; rulings and dissent recorded in `decision-challenges.md`. No architecture decision; ADR-276's amendments already record the unlock semantics these comments must now match. Risk: LOW — the suite's own `mutate()` contract self-verifies every added row.

No UI-surface files in Files to Edit (`.github/workflows/ci.yml`, `scripts/*.sh`, `apps/web-platform/test/*.ts` — none match the ui-surface-terms glob set) → Product tier NONE; all other domains assessed not relevant.

## Test Scenarios

- Given the unlocked driver, when `bash scripts/ci-oracle-lane.test.sh` runs, then exit 0 with `control:` and `MUT_KILLED == MUT_TOTAL` (battery green). — `integration`
- Given the new surgical mutant applied to a copy (`sed 's| && \[ "\$locked" = false \]||'` on `GUARD:O-ARM`), when `row_lock` drives it with `ORACLE_LANE_LOCKED=1`, then `active=true` where the contract demands `false` → probe FAILs → mutant recorded killed. — `unit` (harness-internal)
- Given the `-n` loosening mutant, when `row_lock` drives `ORACLE_LANE_LOCKED=0`, then `locked=true` → `active=false` → sweep check FAILs → killed; on today's (pre-change) suite the same mutant SURVIVES — proving the sweep, not the mutant, is what reddens it. — `unit`
- Given ci.yml post-edit, when `grep -c 'stands in the driver' .github/workflows/ci.yml` runs, then output `0` for oracle-lane contexts while the pr-selection lock comment still reads "While the activation lock holds". — `unit`
- Regression: unchanged battery rows must stay green — the retitle is label-only, the sweep and mutants are additive; `git diff scripts/ci-oracle-lane.test.sh` shows no deleted `check_`/`mutate` line except the retitled label text. — `integration`

## Success Metrics

- `bash scripts/ci-oracle-lane.test.sh` green on the branch with the two new mutants killed (visible in the battery's killed-count output).
- Zero remaining live-file comment claims of a standing `ORACLE_LANE_LOCKED` literal outside point-in-time records (`grep` census returns only the env-re-lock descriptions).

## Dependencies & Risks

- **Risk:** the surgical sed under-matches a future O-ARM line reshape → `mutate()`'s landed-check fails loudly at battery time (self-defending; mitigated by anchoring on the `GUARD:O-ARM` suffix if needed).
- **Risk:** `row_lock` sweep adds 3 `drive()` executions (~seconds each on the fixture) — negligible vs the suite's existing ~30 drives.
- **Risk:** a sibling PR touching `ci.yml`'s oracle-selection block or the battery could conflict — small, text-local.
- **Dependencies:** none beyond the issue; no CI variable or runner change.

## References & Research

- Issue: #12375 (this plan's sole source of asks); context PR #12300, issue #12156, epic #11556.
- ADR-276 + amendments (`knowledge-base/engineering/architecture/decisions/ADR-276-demand-first-hosted-runner-budget-merge-group-is-the-full-battery-authority.md`) — unlock semantics the comments must match.
- Sibling precedent: `scripts/ci-pr-selection.test.sh:1455` (surgical lock-conjunct mutant), `:1454` (lock-read kill mutant), oracle test:1549 (`-n` SWITCH mutant shape).
- Driver anchors: `scripts/ci-oracle-lane.sh:137` (O-LOCK-READ), `:384` (O-ARM), `:90-92` region headers.
- Learnings: `2026-11-07-a-pin-whose-harness-runs-only-arg-two-passes-vacuously.md`, `2026-08-09-my-tests-pinned-a-constant-by-indexing-it-and-my-mutants-read-as-survivors.md`, `2026-11-07-a-row-resplit-stales-every-literal-range-in-the-corpus.md`, `2026-11-05-a-classifier-run-from-the-candidate-tree-can-be-forged-by-the-diff-it-judges.md`.
- Runbook: `knowledge-base/engineering/operations/runbooks/ci-oracle-lane.md` (already post-activation — the style the rewritten comments should match).

## Implementation Phases

1. **Comments.** Rewrite the four stale comment sites (ci.yml ×2, c4 test, ci-draft-light) to post-activation semantics per Proposed Solution item 1. Do not touch any non-comment line or the pr-selection lock comments.
2. **Battery labels + surgical mutant.** Retitle the `kill_guard O-ARM` row to name arm-presence; add the `O-ARM` conjunct-drop mutant on `$PRISTINE` driven by `row_lock`.
3. **`row_lock` sweep.** Add the `for v in 0 true on` loop after the existing `ORACLE_LANE_LOCKED=1` assertions, asserting `active`/`skip_legs`/notice-`locked` per AC-5.
4. **`-n` mutant + `cmp -s` annotation.** Add the `-n`-loosening mutant row driven by `row_lock`; add the intent comment at the `cmp -s` pin.
5. **Verify.** `bash scripts/ci-oracle-lane.test.sh` (green, all mutants killed); `bash -n` clean; `git diff` confirms comment-only changes in the three non-battery files.
