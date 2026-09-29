---
title: "fix: bun-test pre-commit gate selects from the staged set — runner-changed no longer degrades every commit on a runner-diff branch"
type: fix
date: 2026-09-29
slug: fix-bun-test-hook-runner-changed
branch: feat-one-shot-9173-bun-test-runner-changed
issue: 9173
closes: 9173
priority: p2-medium
domain: engineering
lane: cross-domain
brand_survival_threshold: none
---

# fix: bun-test pre-commit gate selects from the staged set — runner-changed no longer degrades every commit on a runner-diff branch

## Overview

`lefthook`'s `bun-test` pre-commit hook runs `bash scripts/test-all.sh --affected` whenever a commit stages a `*.{ts,tsx,js,jsx}` file. The affected-selection diff (`_diff_names`) is built from `origin/main...HEAD`, `HEAD`, and the untracked set — a *branch* answer to what is a *commit* question. Once a branch touches `scripts/test-all.sh` or `scripts/lib/test-affected-paths.sh`, the `runner-changed` fallback degrades **every subsequent commit's** hook run to the ~4h full battery, which crosses `TC_RUNTIME_CEILING_S` and makes ts-touching commits unlandable through hooks (measured on #9136: three refused/killed/queued attempts; the commit only landed via a side-branch cherry-pick plus `LEFTHOOK_EXCLUDE` under authorization).

The fix gives the hook a **commit-scoped selection**: a new `--affected-scope=staged` flag switches the selection diff to `git diff --cached`, so the gate answers "which suites can *this commit* move" — which is what a pre-commit gate is for. The branch-scope default is byte-identical for every other invocation (operator `--affected`, ship Phase 4, CI legs). Under staged scope, `runner-changed` resolves to the bounded selection the edge machinery already produces (runner-edged suites via declared self-edges, plus the unconditional always-on runner-SUT battery) instead of the full corpus — with a loud telemetry note — because a full-battery fallback inside a pre-commit hook is the wall this issue exists to remove.

## Problem Statement / Motivation

The `runner-changed` fallback is a correct fail-safe pointed at the wrong unit of work. It exists because "a diff touching the runner or the index could be narrowing the very selection this run is about to apply" (`scripts/test-all.sh`, the `runner-changed` arm of the affected pre-pass). That reasoning holds for the *diff under test* — but a pre-commit hook's diff under test is the commit, and `_diff_names` answers with the branch. Consequence: any branch that both registers a suite (every suite registration touches `test-affected-paths.sh`) and edits a `.ts/.js` file puts a ~4h battery inside every ts-staging commit, where it gets killed by the runtime ceiling or queues ~20+ min on the test-all advisory lock behind sibling batteries.

The bypasses this creates are worse than the defect: `LEFTHOOK_EXCLUDE`/`--no-verify` skip **every** pre-commit hook (gitleaks included), and the side-branch + cherry-pick route skips them too. Recurrence is structural, not incidental — observability-adjacent work routinely pairs a `test-affected-paths.sh` registration edit with a `MARKER_RE`/`SOLEUR_*` assertion edit in a `*.test.ts` (e.g. `plugins/soleur/test/debug-probe-residue.test.sh`).

## Proposed Solution

**Chosen approach — issue option (a), staged-file scoping, with the runner-changed arm narrowed inside that scope (the safe half of option (c)):**

1. **New flag `--affected-scope=staged`** in `scripts/test-all.sh` (enum `branch`|`staged`, default `branch`; unknown value or combination with `--full` → `exit 2`, matching the `TEST_GROUP` validation precedent). The flag is valid only when an affected axis will consume `_diff_names` — `--affected`, the local default, or `TEST_GROUP=affected` (it scopes the heuristic axis's diff equally well); under a non-affected `TEST_GROUP` or `--full` it exits 2 rather than silently scoping nothing. Under `staged`, the `_diff_names` assembly derives from `git -c core.quotePath=false diff --cached --name-only` plus the `--name-status -M` form (rename-source parity with the existing assembly), and the two detection arms (`_diff_detect_ok`/`_diff_head_ok`) are both set from the staged commands' success so every downstream fail-safe reads them unmodified; the `HEAD`, `origin/main...HEAD`, and untracked appends are skipped — untracked content is definitionally not in the commit. A failed staged-diff detection arms the existing `undecidable-diff` fallback (fail toward coverage, unchanged ladder).
2. **`runner-changed` under staged scope degrades to bounded selection, not the full battery.** The staged set itself contains the runner/index paths when the commit stages them, so the declared self-edges in `test-affected-paths.sh` (every edge set self-includes both files) plus argv self-edges select the runner's own suites, and every runner-SUT suite is unconditional via `ALWAYS_ON_SUITES` — including `scripts/test-all-affected`, the classifier's own mutation battery. The run emits a distinct loud note (e.g. `AFFECTED_RUNNER_IN_SCOPE reason=runner-changed`) rather than `AFFECTED_FALLBACK`, since no full-battery fallback occurred and `_aff_fallback` staying empty keeps the run refusal-exempt by construction (ADR-196 re-check applies to degraded-full runs only). Branch scope keeps `runner-changed` → full battery unchanged.
3. **`lefthook.yml` `bun-test` hook** invokes `bash scripts/test-all.sh --affected --affected-scope=staged` behind a bounded queue budget (`TC_QUEUE_TIMEOUT=300`): on expiry `tc_acquire` proceeds with the `LOCK_CONTENDED_PROCEEDING` banner by design (it never aborts), capping worst-case commit latency at ~5 min of queue plus a narrow run instead of an unbounded wait behind sibling batteries. The `skip: merge` stanza and glob are untouched.
4. **Telemetry:** every staged-scope run prints `AFFECTED_SCOPE scope=staged` beside the existing `MODE=` line, so a hook log always names which diff selected.
5. **Mutation coverage:** new sandbox arms in `scripts/test-all-affected.test.sh` (seam at the staged-diff derivation point, same pattern as `SANDBOX_DIFF_NAMES`), and the stanza pin `plugins/soleur/test/lefthook-bun-test-merge-skip.test.sh` updated for the new `run:` line.
6. **ADR-242 amendment** recording the scope axis and the staged-scope `runner-changed` semantics (see `## Architecture Decision (ADR/C4)`).

**Why a flag, not an env var:** an exported `SOLEUR_*` env inherits into the runner's own nested `--enumerate-commands` self-call and into any later session shell — presence is not ownership (learning `2026-09-28-an-exported-session-env-var-forked-nested-runner-behavior.md`, #8940/#9034). A flag on the lefthook `run:` line cannot leak, needs no provenance machinery, and is greppable at the one call site that is allowed to say it. This dissolves issue option (b)'s "sanctioned narrow-mode env with `SOLEUR_ALLOW_FULL_GATE`-style provenance rules" — the provenance the env would need is the property the flag has for free.

**Why `git diff --cached` in-runner, not lefthook `{staged_files}`:** the index is the authority on what the commit contains; `{staged_files}` arrives space-separated (path-with-spaces fragility) and duplicates a derivation git already does. The `GIT_*` unset in the runner's hook-isolation block precedes the diff assembly, so post-unset `git diff --cached` rediscovers the worktree index — the real staged set — with no dependence on hook-exported env. It is also stash-agnostic: correct whether or not lefthook's unstaged-stash behavior is on (the `no_stash` question belongs to #8045).

**Rejected alternatives** (full reasoning in `## Alternative Approaches Considered`): (b) `TEST_GROUP=commit-scope` — new group axis duplicates the existing narrow selector and needs `want_*` plumbing for the same property; (c) alone — keeps branch-diff over-selection on every commit and the use-the-suspect-selector-to-pick-runner-suites trust hole, while still needing staged plumbing; (d) selection-logic vs registration-data discrimination — the pathname trigger cannot see edit kind without fragile diff-content inspection, and the dangerous class (edge-set narrowing) is data-shaped, already covered by self-inclusion + the always-on census + unclassified-selects-anyway.

## Technical Considerations

- **Architecture impact:** amends ADR-242's fallback ladder — `runner-changed` becomes scope-aware. No new subsystem; one flag, one diff-source branch, one scope-aware fallback arm, one hook line.
- **Safety argument:** the hook is advisory fast-feedback; the authoritative nets are untouched — CI's required `test` context (ruleset 14145388) runs the full group legs on the PR head, and ship Phase 4's `--affected` keeps branch scope and degrades to full on runner diffs exactly as today.
- **Accepted residual:** a commit that stages a *selector-corrupting* runner edit could narrow the selector it runs under (a staged-scope decline the corrupted code itself computed). Bounded by: a fully-broken classifier fails the run loudly (hook exit ≠ 0 blocks the commit — fail-closed at the block point); the always-on runner-SUT battery is unconditional; and CI runs the full battery on the PR regardless. The alternative equilibrium — measured in the issue — is operators bypassing *all* hooks via `LEFTHOOK_EXCLUDE`/`--no-verify`, which is zero coverage including gitleaks.
- **Queue bound:** `TC_QUEUE_TIMEOUT` (default `$TC_LOCK_TIMEOUT`=3600) is the ticket-queue wait budget; 300 s bounds the hook's worst-case pre-run wait. A narrow run proceeding after the bound costs a sibling battery a few minutes of contention — the same tradeoff the sibling-refusal already accepts by exempting affected runs.
- **Ordering invariant:** the staged-diff derivation must land in the same position the branch assembly occupies — before `_infra_in_diff` derivation and before the pre-pass — so every downstream consumer (`_diff_touches`, the runner-changed arm, `_suite_affected`-era seams) reads the scope it asked for. The existing sandbox seam sits after the assembly; the staged arm needs an equivalent injection at the staged source.
- **NFR impacts:** none on production surfaces; developer-latency and gate-integrity properties of local machinery (see `knowledge-base/engineering/architecture/nfr-register.md` classes: reliability of the gate, not a runtime NFR).
- **Edge cases (SpecFlow pass):** `git commit --amend` → staged set is the amend delta — correct; merge commits → hook already `skip: merge`; partial staging (`git add -p`) → gate sees exactly what is committed — correct; `git commit -a` → tracked modifications are staged — seen; brand-new staged file → `--name-only`/`--name-status` list it — self-edge selects it; empty index under the flag → detection succeeds with an empty set → the existing zero-selected refusal applies (only reachable when nothing is staged, which the hook glob already prevents); flag under `CI=` → declines are bypassed there anyway — inert; flag outside a hook → gates on the caller's index — documented as hook-intended, harmless to a local advisory gate.
- **Fixture hazard constraint (#8800):** the new sandbox arms must not reuse `build_census_sandbox()`'s `cp -al`/`ln -sfn` pattern for any write-path — arms mutate only the real-copied sandbox runner, never a shared-inode path into the live tree.

## User-Brand Impact

- **If this lands broken, the user experiences:** a plugin-repo contributor hits either a regressed pre-commit gate (battery returns — commits unlandable through hooks again) or a silently under-selecting staged scope (a ts commit green-lights with its relevant suites declined — the coverage gap surfaces only when CI's full battery runs on the PR).
- **If this leaks, the user's [data / workflow / money] is exposed via:** workflow only — no user data or credentials cross this surface; a wrong gate influences which tests run, never which secrets are reachable.
- **Brand-survival threshold:** `none` — internal developer tooling; the authoritative merge gate (CI full battery) is untouched by this change.

## Research Insights

- **Relevant code:** `scripts/test-all.sh` — flag-parse `while/case` (anchors `--affected`/`--full`/`--print-affected-set`), `_diff_names` assembly (HEAD + `origin/main...HEAD` + `--name-status -M` + untracked arms), `_diff_touches` decline predicate, affected pre-pass (`_aff_fallback` ladder: `force-all`|`index-missing`|`undecidable-diff`|`runner-changed`), degraded-full refusal re-check (ADR-196), `run_suite` chokepoint selection via `_aff_sel[$_shard_ordinal]`; `scripts/lib/test-affected-paths.sh` — `ALWAYS_ON_SUITES` (~140 entries incl. every runner-SUT suite) + declared `AFFECTED_<LABEL>_PATHS` edge arrays that self-include both runner files; `lefthook.yml` `bun-test` stanza (`skip: merge`, pinned by `plugins/soleur/test/lefthook-bun-test-merge-skip.test.sh`); `scripts/lib/test-contention.sh` — `TC_QUEUE_TIMEOUT` defaults to `TC_LOCK_TIMEOUT` (3600), expiry proceeds with banner, never aborts.
- **Governing ADRs:** ADR-242 (the `--affected` design this amends — Decision 3 minted `runner-changed`; Decision 4 made affected runs refusal-exempt *unless degraded*, which is exactly the wall this issue hits); ADR-196 (refusals bind to measured conditions; degraded runs re-check); ADR-183 (full battery at ship/CI, not implementation exit — a 4h pre-commit contradicts the ordering); ADR-181 (declines are counted verdicts); ADR-133 (advisory lock semantics).
- **Institutional learnings:** `2026-09-28-an-exported-session-env-var-forked-nested-runner-behavior.md` (presence-gated env is not ownership — drives flag-not-env); `2026-09-20-every-defect-in-my-fix-was-a-sentence-i-could-have-run.md` (#8322-era: run the mutation, not the description); `2026-03-21-lefthook-gobwas-glob-double-star.md` (hook glob semantics); `2026-06-06-lefthook-pre-push-push-files-and-dual-glob-depth1.md` (lefthook file-list plumbing precedent).
- **Test harness:** `scripts/test-all-affected.test.sh` sandbox arms inject `SANDBOX_DIFF_NAMES`/`SANDBOX_DETECT_OK`/`SANDBOX_HEAD_OK`/`SANDBOX_SIBLINGS` into a copied runner and neuter suite execution into `RAN` records — the new arms follow the same shape with a seam at the staged-diff derivation.
- **Related issues/PRs:** #9173 (this), #8045 (sibling — false-RED instrument fix + `no_stash` hypothesis; `Ref`, not closed by this plan), #9136 (merged PR where the wall was measured), #8322/#8591 (the two affected axes), #8800 (fixture write-through hazard constraining new arms), #8659/#7942 (open code-review overlaps — see below).
- **Premise Validation:** issue #9173 OPEN (verified `gh issue view`); cited anchors held — `runner-changed` arm present (`_aff_fallback="runner-changed"`), `lefthook.yml` bun-test stanza present (`glob: "*.{ts,tsx,js,jsx}"`, `run: bash scripts/test-all.sh --affected`), `TC_RUNTIME_CEILING_S` armed; sibling #8045 OPEN and non-duplicate; ADR corpus read — no ADR rejects staged-scope (ADR-242 Decision 4's exemption already encodes the intent this fix completes); issue's `~line 2577` anchor drifted to ~2638 (cosmetic) and its `git-lock-marker-telemetry.test.ts` name is approximate (`MARKER_RE` actually lives in `plugins/soleur/test/debug-probe-residue.test.sh`).
- **Property List (Phase 0.6b):** (P1) a commit staging only ts/js on a runner-touching branch lands through the hook in bounded time; (P2) a commit staging runner/index edits still exercises the runner's own suites at commit time; (P3) branch-scope invocations keep byte-identical semantics incl. the full-degradation ladder; (P4) scope and degradation are loud in telemetry — never silent narrowing.
- **Cut List (Phase 0.6b):** option (b) env+provenance (property = narrow invocation; already bought by a flag without provenance machinery); option (c) alone (same plumbing cost, keeps branch-diff over-selection + self-trust hole); option (d) logic-vs-data discrimination (pathname trigger can't see edit kind; the dangerous narrowing edit is data-shaped and already covered by self-inclusion/census/unclassified-selects); lefthook `{staged_files}` argv pass (space-separated fragility; index is authoritative); `no_stash` hook toggle (#8045's scope; `--cached` is stash-agnostic).
- **Value-Proposition Measurement (Phase 0.6c):** the saving is measured, not hypothesized — issue #9173 records the degraded run at 527 suites / ~3667 s vs the affected gate's narrow run, plus three blocked hook attempts (refusal, ~11-min ceiling kill, 20+ min lock queue). Command producing the number: the session log cited in the issue (`AFFECTED_FALLBACK reason=runner-changed` → ceiling exit); suite-count delta verifiable post-change via `bash scripts/test-all.sh --affected --affected-scope=staged --print-affected-set` vs `--print-affected-set` alone.

## Research Reconciliation — Spec vs. Codebase

| Issue/spec claim | Codebase reality | Plan response |
|---|---|---|
| `runner-changed` fallback at `test-all.sh` ~line 2577 | Present at ~line 2638 (`_aff_fallback="runner-changed"` grep anchor) — cosmetic drift | Cite symbol anchor, not line number |
| `git-lock-marker-telemetry.test.ts` carries `MARKER_RE` | `MARKER_RE` lives in `plugins/soleur/test/debug-probe-residue.test.sh`; the pairing pattern (registration + ts edit) is accurate | Use the real filename in examples |
| Hook runs "the whole battery" on runner-diff branches | Precisely: `--affected` degrades to full selection via the fallback ladder; always-on ratchets run in every affected run regardless | Plan targets the degradation trigger's diff source |
| Fix must touch hook AND runner | Confirmed — hook carries the flag; runner carries the scope; both pinned by existing suites | Files-to-Edit lists both |

## Open Code-Review Overlap

3 open scope-outs touch planned files:

- **#8800** (`test-all-affected.test.sh` + `test-affected-paths.sh` — census-sandbox `cp -al`/`ln -sfn` write-through hazard): **Acknowledge** — different concern (fixture inode sharing vs selection scope); carried forward as a *constraint*: new arms mutate only real-copied sandbox paths. Do not ride this fix.
- **#8659** (`test-all.sh` body mention — EXIT-trap/incident-sandbox leak across suites): **Acknowledge** — orthogonal subsystem (test-helpers trap composition), untouched by the diff-source change.
- **#7942** (`test-all.sh` body mention — two `*.mutation.sh` batteries run in no gate): **Acknowledge** — registration/gate-coverage concern, orthogonal; this plan adds arms inside an already-gated suite.

## Implementation Phases

### Phase 1: Runner flag + staged diff source

- `scripts/test-all.sh`: add `--affected-scope=<branch|staged>` to the flag-parse `while/case` and `--help` (enum validated, `exit 2` on unknown value / `--full` combination / non-affected combination); in the `_diff_names` assembly, branch the diff source on scope — staged scope runs `git -c core.quotePath=false diff --cached --name-only` + `--name-status -M` and skips the `HEAD`, `origin/main...HEAD`, and untracked appends; staged-diff detection failure sets `undecidable-diff` on the existing ladder.
- Success criterion: `--print-affected-set` under staged scope emits receipts keyed on the index, not the branch diff.

### Phase 2: Scope-aware runner-changed + hook wiring

- `scripts/test-all.sh`: in the pre-pass, the `runner-changed` arm gains a scope conjunct — branch scope keeps the full-battery fallback byte-identical; staged scope leaves `_aff_fallback` empty and emits the scoped note + `AFFECTED_SCOPE scope=staged` on every staged run.
- `lefthook.yml`: `run:` becomes `TC_QUEUE_TIMEOUT=300 bash scripts/test-all.sh --affected --affected-scope=staged`; stanza comment documents why (commit-scoped gate; bounded queue; CI is the full net).
- Success criterion: on a fixture branch touching `test-all.sh`, a staged ts file produces `MODE=affected` + `AFFECTED_SCOPE scope=staged` with no `AFFECTED_FALLBACK`.

### Phase 3: Mutation coverage + stanza pin + ADR amendment

- `scripts/test-all-affected.test.sh`: new seam at the staged-diff derivation (e.g. `SANDBOX_STAGED_NAMES`) + arms per `## Test Scenarios` (write failing first — `cq-write-failing-tests-before`); keep every existing arm byte-stable (branch-scope regression net).
- `plugins/soleur/test/lefthook-bun-test-merge-skip.test.sh`: update the stanza pin for the new `run:` line while keeping the `skip: merge` assertion.
- `knowledge-base/engineering/architecture/decisions/ADR-242-*.md`: amend `## Decision` (scope axis; staged-scope `runner-changed` semantics; flag-not-env rationale) + `## Alternatives Considered` (record options b/c/d with rejection reasons).
- Success criterion: new arms RED before the runner change, GREEN after; branch-scope arms unchanged green.

## Alternative Approaches Considered

| Approach | Verdict | Why |
|---|---|---|
| (a) Staged-scope selection for the hook (chosen) | **Adopt** | The hook's unit of work is the commit; moves the fail-safe onto the run whose diff contains the runner; composes with bounded runner-changed; flag form dissolves (b)'s provenance problem |
| (b) `TEST_GROUP=commit-scope` + provenance env | Reject | Duplicates the existing `TEST_GROUP=affected` narrow axis with new `want_*` plumbing; env provenance is the wrong channel (presence ≠ ownership, leaks into the nested enumerate self-call); a flag buys the property outright |
| (c) runner-changed → runner suites + staged set (alone) | Reject as sole fix | Still needs staged plumbing; keeps branch-diff over-selection on every commit of a runner branch; keeps the self-trust hole without the per-commit semantics that make it safe. Its bounded-degradation half is adopted *inside* staged scope |
| (d) runner-changed distinguishes logic vs data edits | Reject | Pathname trigger cannot see edit kind without fragile diff-content inspection; the dangerous edit (edge narrowing) is data-shaped and already covered — every declared edge set self-includes the index file, removed always-on memberships surface as unclassified (runs anyway + census linter reds) |
| Pass `{staged_files}` to the runner | Reject | Space-separated argv fragility; index derivation in-runner is authoritative and seam-testable |
| `no_stash` on the hook | Out of scope | #8045's hypothesis for the false-RED symptom; `git diff --cached` is stash-agnostic |
| Do nothing (status quo: bypass via `LEFTHOOK_EXCLUDE`/cherry-pick) | Reject | Measured operator behavior routes around the hook — disabling gitleaks and every sibling check |

## Files to Create

None (plan/spec artifacts aside).

## Files to Edit

- `scripts/test-all.sh` — flag parse + `--help`, `_diff_names` assembly scope branch, `runner-changed` arm scope conjunct, `AFFECTED_SCOPE`/runner-in-scope telemetry.
- `lefthook.yml` — `bun-test` `run:` line + stanza comment.
- `scripts/test-all-affected.test.sh` — `SANDBOX_STAGED_NAMES`-class seam + new arms.
- `plugins/soleur/test/lefthook-bun-test-merge-skip.test.sh` — stanza pin update.
- `knowledge-base/engineering/architecture/decisions/ADR-242-the-local-gate-defaults-to-affected-suites-and-always-on-ratchets.md` — amendment.

## Observability

```yaml
liveness_signal:
  what: "per-run AFFECTED_SCOPE / MODE / AFFECTED_FALLBACK telemetry lines emitted by test-all.sh; the gate's liveness is a hook run that completes under TC_RUNTIME_CEILING_S with the scope line present"
  cadence: "per invocation (every matching commit)"
  alert_target: "committer via hook stdout/stderr — a missing AFFECTED_SCOPE line on a staged-scope run is itself the anomaly"
  configured_in: "scripts/test-all.sh (affected pre-pass telemetry block)"
error_reporting:
  destination: "git-commit hook output (stdout/stderr shown by lefthook); TEST_TIMING_LOG rows per suite"
  fail_loud: "AFFECTED_UNRESOLVED / AFFECTED_FALLBACK banners and rc=4 refusals print named reasons; a degraded run can never read as a narrow one"
failure_modes:
  - mode: "staged-diff detection failure (git diff --cached fails under hook env)"
    detection: "_diff_detect_ok arm → undecidable-diff → full battery with banner"
    alert_route: "hook output — commit blocked until resolved or bypassed"
  - mode: "selector corrupted by a staged runner edit (bounded-miss residual)"
    detection: "always-on runner-SUT battery (incl. scripts/test-all-affected) is unconditional; residual gap surfaces at CI full battery on the PR"
    alert_route: "CI required 'test' context (ruleset 14145388)"
logs:
  where: "lefthook hook output in the committing terminal; TEST_TIMING_LOG when set"
  retention: "terminal scrollback; timing log retention per existing runner convention"
discoverability_test:
  command: "bash scripts/test-all.sh --help"
  expected_output: "--affected-scope"
```

## Guard Contract

### Guard 1 — staged-scope selection boundary

**Property.** Under `--affected-scope=staged`, every diff-based selection decision keys on the staged set alone: a branch that touches the runner/index cannot degrade a commit that does not stage it, and a commit that does stage it still selects the runner's own suites.

**Assembly.** The `_diff_names` derivation block in `scripts/test-all.sh` (the scope-switched source), the flag-parse arm (the only entry point that can set the scope), the `runner-changed` arm in the affected pre-pass (the chokepoint where scope changes behavior), and the lefthook `run:` line (the sole sanctioned staged-scope invocation). One chokepoint per side: `_diff_names` for the input, `_aff_fallback`/`_aff_sel` for the effect.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Staged-scope arm silently reads `origin/main...HEAD` instead of `--cached` | RED — arm: branch touches runner, staged set is ts-only → must show no full-battery fallback |
| 2 | Flag parses but never switches the diff source (guard's own dispatch — flag accepted, behavior identical) | RED — the staged-scope arms measure a diff that exists only in the index |
| 3 | Staged set gains a SECOND ts path after a compliant first | RED if selection ignores the second path — its edged suite must appear in `RAN`/`AFFECTED_CLASS` |
| 4 | Reorder: move the staged-diff append after the runner-changed arm (order/lifetime row) | RED — the arm reads a `_diff_names` that predates the scope |
| 5 | Harness row: suite arm asserts on a renamed telemetry token not emitted | RED — the harness checks its own anchor exists |
| 6 | Must-PASS non-canonical: staged scope on a clean index + branch touching unrelated paths | PASS — narrow selection, `AFFECTED_SCOPE scope=staged` printed, zero runner-changed |

**Anchor.** Not applicable — the guard compares a runtime-derived set, not a stored value.

### Guard 2 — flag mis-combination rejection

**Property.** `--affected-scope` is only meaningful on the affected axis: combined with `--full`, an unknown enum value, or a non-affected `TEST_GROUP` it exits 2 with usage rather than silently scoping a run it does not describe.

**Assembly.** The flag-parse `while/case` + the post-parse validation block in `scripts/test-all.sh`; `--help` text naming the flag.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Drop the `--full` combination check | RED — `--affected-scope=staged --full` must exit 2 |
| 2 | Accept an unlisted enum value (dispatch row — the validator passes everything) | RED — `--affected-scope=bogus` must exit 2 |
| 3 | Accept the flag under `TEST_GROUP=scripts` (second disallowed combination after the first compliant one) | RED — scope without the affected axis must exit 2 |
| 4 | Must-PASS non-canonical: `--affected-scope=branch` explicitly | PASS — the default spelled out is not an error |

**Anchor.** Not applicable.

## Domain Review

**Domains relevant:** engineering

### Engineering

**Status:** reviewed (inline — this harness exposes no Task/subagent spawn; assessment performed by the planning orchestrator against the domain question)

**Assessment:** Does this feature require significant architectural decisions, infrastructure changes, system design, or technical debt resolution beyond normal implementation? Yes in the narrow sense — it amends the affected-gate's selection semantics governed by ADR-242, which is why the ADR amendment is a plan deliverable rather than a follow-up. No new substrate, trust boundary toward production, or infra resource is introduced; the blast radius is developer-local gating bounded by CI's full battery. The engineering risk concentrates in two places the design addresses directly: (1) fail-safe direction on every new code path (detection failure → `undecidable-diff` → full; flag misuse → `exit 2`), and (2) the self-referential trust caveat of a runner gating its own edits — narrowed to the staged set, documented in the ADR amendment, backstopped by CI.

### Product/UX Gate

**Tier:** none — no user-facing surface; `## Files to Edit`/`## Files to Create` contain no `components/**/*.tsx`, `app/**/page.tsx`, or `app/**/layout.tsx` path, and no UI-surface term matches the mechanical override list.
**Decision:** skipped (no UI surface)
**Agents invoked:** none
**Skipped specialists:** none
**Pencil available:** N/A (no UI surface)

## GDPR Gate (Phase 2.7 findings)

Skipped — the diff touches no regulated-data surface (no schema, migration, auth flow, API route, or `.sql`), and none of the (a)–(d) extended triggers fire: no LLM processing of session data, `brand_survival_threshold` is `none`, no cron/workflow reads learnings/specs, and no new artifact distribution surface is created (the flag is repo-internal machinery).

## Acceptance Criteria

- [ ] AC1: `bash scripts/test-all.sh --affected --affected-scope=staged` derives `_diff_names` from `git diff --cached` (name-only + `--name-status -M` rename sources) and does not consult `origin/main...HEAD`, the `HEAD` diff, or the untracked set for selection.
- [ ] AC2: On a branch whose diff touches `scripts/test-all.sh`/`scripts/lib/test-affected-paths.sh`, a commit staging only `*.{ts,tsx,js,jsx}` files runs the hook to completion without `AFFECTED_FALLBACK reason=runner-changed` — bounded selection, `AFFECTED_SCOPE scope=staged` emitted.
- [ ] AC3: A commit that *does* stage a runner/index path selects the runner-edged suites plus the always-on battery and emits the runner-in-scope note — bounded, under the runtime ceiling, never the 527-class full battery.
- [ ] AC4: `bash scripts/test-all.sh --affected` without the flag is byte-identical in behavior to `origin/main`, including `runner-changed` → full-battery degradation — pinned by the existing `test-all-affected.test.sh` arms staying green unmodified in semantics.
- [ ] AC5: `--affected-scope` with an unknown value, with `--full`, or under a non-affected `TEST_GROUP` exits 2 with usage; `--affected-scope=branch` is accepted and equals the default; under `TEST_GROUP=affected` the flag scopes the heuristic axis's diff the same way.
- [ ] AC6: `lefthook.yml` `bun-test` runs `TC_QUEUE_TIMEOUT=300 bash scripts/test-all.sh --affected --affected-scope=staged`, retains `skip: merge` and the `*.{ts,tsx,js,jsx}` glob, and the stanza comment states the scope contract.
- [ ] AC7: ADR-242 carries the amendment (scope axis + staged-scope `runner-changed` semantics + rejected alternatives b/c/d).
- [ ] AC8: Each new sandbox arm is mutation-checked — reverting its targeted line (the staged diff source, the flag parse, the scope conjunct) drives that arm RED. Arms are written and observed failing against the unmodified runner before the runner change lands (`cq-write-failing-tests-before`).
- [ ] AC9: `git diff --cached` detection failure under staged scope arms `undecidable-diff` → full battery with banner (fail toward coverage).
- [ ] AC10: No new env var is introduced for scope selection; the staged seam used by tests is `SANDBOX_*`-prefixed and documented beside the existing seams.

## Test Scenarios

- Given a branch touching `test-all.sh` and a staged set containing only `foo.test.ts`, when `--affected-scope=staged` runs, then `_diff_names` contains the staged path, no `runner-changed` fallback fires, and `AFFECTED_SCOPE scope=staged` prints.
- Given the same branch and a staged set containing `test-all.sh` + `foo.test.ts`, when the run executes, then runner-edged suites (declared self-edges + argv self-edges) and all always-on suites select, the runner-in-scope note prints, and no full-battery banner appears.
- Given `SANDBOX_STAGED_NAMES` unset and `--affected-scope=staged` in the sandbox, when `git diff --cached` fails, then `AFFECTED_FALLBACK reason=undecidable-diff` prints and the run degrades to full.
- Given `--affected-scope=staged --full`, when parsing completes, then exit 2 with usage — before any suite runs.
- Given `--affected-scope=staged` under `TEST_GROUP=scripts`, when parsing completes, then exit 2 — the scope describes only the affected axis.
- Given a branch-diff-only file (committed earlier, unstaged now), when the hook runs staged scope, then that file does not influence selection.
- Given a rename staged via `git mv` on a declared edge path, when `--name-status -M` staged form is read, then both source and destination are matchable (rename-source parity).
- Given the lefthook stanza, when the merge-skip pin suite runs, then `skip: merge` and the new `run:` line are both asserted.

## Success Metrics

- A ts-staging commit on a runner-touching branch lands through hooks in minutes (target: hook wall time bounded by narrow selection + ≤300 s queue) — verifiable by timing the hook on a fixture branch shaped like #9136's.
- Zero `AFFECTED_FALLBACK reason=runner-changed` lines in staged-scope hook logs; `AFFECTED_SCOPE scope=staged` present on every such run.
- Branch-scope `runner-changed` behavior unchanged — existing mutation battery green without semantic edits.

## Dependencies & Risks

- **Risk — staged scope under-covers a commit whose semantics depend on earlier branch commits.** Mitigated by design intent: the hook gates the commit; earlier commits were gated by their own hook runs, and CI's full battery on the PR head is the merge gate (ruleset 14145388). Recorded in the ADR amendment.
- **Risk — `git diff --cached` under exotic hook states (bare repo, detached HEAD mid-rebase).** Bare-repo guard already exists upstream of the derivation; detection failure → `undecidable-diff` → full (fail-safe direction preserved).
- **Risk — `TC_QUEUE_TIMEOUT=300` expiry proceeds a narrow run concurrently with a sibling battery.** Accepted: the sibling-refusal already exempts affected runs for this reason; the banner makes the concurrency loud. If contention flakiness appears, the knob is tunable per-hook without touching the runner.
- **Dependency — #8800 fixture constraint:** new arms must not write through shared-inode/symlinked fixture paths; build arms on the real-copied sandbox runner only.
- **Risk — flag spelling bikeshed.** `--affected-scope=staged` is the contract this plan asserts; an equivalent spelling is acceptable only if the AC wording and stanza pin are updated in the same change.

## Architecture Decision (ADR/C4)

### ADR

**Amend** `knowledge-base/engineering/architecture/decisions/ADR-242-the-local-gate-defaults-to-affected-suites-and-always-on-ratchets.md` — new decision point recording: (i) the affected gate gains a *diff-source scope* axis (`branch` default / `staged`), (ii) under `staged` the `runner-changed` fallback resolves to bounded edge selection + the unconditional always-on runner-SUT battery with a loud note instead of the full battery, because the unit of work at a pre-commit gate is the commit and the full-corpus fail-safe at that position is a measured denial-of-commit, (iii) the scope is flag-selected not env-selected (presence ≠ ownership — the var would inherit into the nested enumerate self-call), (iv) `## Alternatives Considered` gains the issue's options (b)/(c)/(d) with their rejection reasons. `### Sequencing`: none — the amendment lands with the code in the same PR.

### C4 views

**No C4 impact.** Enumerated per the completeness mandate against `model.c4`/`views.c4`/`spec.c4`: (a) external human actors — none new (the change concerns a developer-local pre-commit hook; no actor gains or loses a modeled relationship), (b) external systems/vendors — none touched, (c) containers/data stores — none (the runner is repo-local tooling absent from the model by design), (d) actor↔surface access relationships — unchanged. A `grep` for `test-all|lefthook|pre-commit` over `model.c4` returns no element, consistent with the model covering deployed/runtime architecture rather than repo-local dev machinery.

## References & Research

- Issue: #9173 (this work); related #8045 (`Ref` — false-RED/ABORT instrument + `no_stash` hypothesis, not a work target here); measured on PR #9136.
- Machinery: `scripts/test-all.sh` (`_diff_names` assembly, `_affected_classify`, `_aff_fallback` ladder, `run_suite` chokepoint), `scripts/lib/test-affected-paths.sh` (`ALWAYS_ON_SUITES`, declared edge arrays + self-inclusion), `scripts/lib/test-contention.sh` (`TC_QUEUE_TIMEOUT`), `lefthook.yml` `bun-test` stanza.
- Decisions: ADR-242 (amended by this work), ADR-196, ADR-183, ADR-181, ADR-133.
- Learnings: `2026-09-28-an-exported-session-env-var-forked-nested-runner-behavior.md`, `2026-09-20-every-defect-in-my-fix-was-a-sentence-i-could-have-run.md`, `2026-03-21-lefthook-gobwas-glob-double-star.md`, `2026-06-06-lefthook-pre-push-push-files-and-dual-glob-depth1.md`.
- Open overlaps: #8800, #8659, #7942 (dispositions above).
