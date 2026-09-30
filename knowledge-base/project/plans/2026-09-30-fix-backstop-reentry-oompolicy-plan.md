---
title: "fix: memory-backstop re-entry refresh drops creation-only OOMPolicy"
type: fix
date: 2026-09-30
slug: fix-backstop-reentry-oompolicy
branch: feat-one-shot-9246-oompolicy-reentry
issue: 9246
closes: 9246
priority: medium
domain: engineering
brand_survival_threshold: none
lane: cross-domain
---

# fix: memory-backstop re-entry refresh drops OOMPolicy from SetUnitProperties

## Enhancement Summary

**Deepened on:** 2026-09-30 (inline deepen — this run executes inside a pipeline subagent with no Task/Workflow spawn capability; all deepen-plan halt gates were executed mechanically and the fan-out lenses were applied as inline verification passes)

**Gates run (all PASS):** 4.4 precedent-diff (call shape mirrors `repair_eval_scope` at `memory-backstop.sh:438–445`, the in-file precedent #9239 shipped; no novel pattern), 4.6 user-brand (section present, `none` threshold, zero sensitive-path matches in Files-to-Edit), 4.7 observability (5-field block, allowlisted `grep` probe verb, literal `3` expected output), 4.8 PAT regex (no hits), 4.9 UI-wireframe (no UI-surface files — skip), 4.10 encryption (no new store/connection — skip), 4.11 guard contract (`lint-guard-contract.py` green, 1 entry, assembly is structural — four named `SetUnitProperties` chokepoints + a whole-file count pin; matrix rows include a dispatch row, a second-member row, a must-PASS row, and a harness row). 4.5 network-outage skipped (no trigger tokens in Overview/Problem; no terraform-apply surface). 4.55 downtime/cutover skipped (no infra/DDL/deploy class change).

**Corrections applied by the deepen pass:**

1. The `OOMPolicy` literal count is **4 today** (:369/:798/:833 creation + :862 the defect), 3 post-fix — the Technical Considerations anchor note now states both values so the M11 author does not read the post-fix count as the pre-fix census.
2. Static pin strengthened from "assert no OOMPolicy in the re-entry call" to a **whitelist** of the four cap properties (Guard Contract row 2: a different non-runtime property — e.g. `BindsTo` — must also red; an OOMPolicy-only blacklist would pass it) plus a fail-closed non-empty-extraction requirement (row 3 dispatch).
3. M11 carries an **empirical version probe** — a host whose systemd accepts `OOMPolicy` on scopes cannot observe the defect, so the row prints a skip note rather than a verdict (the alternative, an unconditional row, silently survives pre-261).

### New Considerations Discovered

- The re-entry failure is *silent* in the common case: the readback asserts observed caps, so when they already match the constants the failed refresh still logs `applied` — it only goes loud (`scope_caps_unverified`) when caps are stale. The defect's true cost is that cap tuning never propagates on re-entry, which is the refresh's stated purpose.
- `#8008`'s live-arm ledger guidance binds the new `T21-reentry-converge` label: it must enter `LIVE_LABELS` and be `live_mark`ed only on emission, `skip`-marked otherwise.
- `plugins/soleur/test/fixture-relative-assert.baseline.txt` pins per-file flagged-operand counts; the battery currently contributes zero rows, so M11 must reuse the existing `mk_mutant`/`run_synthetic`-family helpers rather than introduce new unguarded fixture writes.

## Overview

The re-entry cap refresh in `.claude/hooks/memory-backstop.sh` (the `"$scope"`-targeted `SetUnitProperties` call inside the already-adopted branch of `main`, ~line 855–863) sends five properties including `OOMPolicy`. systemd 261 rejects `OOMPolicy` on scopes (`Cannot set property OOMPolicy, or unknown property`) and `SetUnitProperties` is all-or-nothing, so every `resume|clear|compact` re-entry fails the refresh — the caps can never be re-converged on current systemd without a session restart or a sibling's `repair_stale_scopes` pass. The fix mirrors the `repair_eval_scope` arm shipped in #9239: drop `OOMPolicy` from the call and decrement the arity `5` → `4`. `OOMPolicy` stays where it is valid — the three `StartTransientUnit` creation sites — because it is creation-only on scopes and every hook version has created scopes with `OOMPolicy=continue`, so nothing on that axis is ever stale. Coverage: a CI-side static pin in `memory-backstop.test.sh` plus a live-arm reconvergence assertion, and mutation-battery row M11 that re-adds `OOMPolicy` to the re-entry call and asserts the cap refresh stops converging (a reintroduction reds).

## Problem Statement / Motivation

`SetUnitProperties` on a scope rejects `OOMPolicy` on systemd 261 (measured while building the #9239 repair path — the host this plan was written on runs `systemd 261 (261.2-1-arch)`), and the call is all-or-nothing: one rejected property drops `MemoryHigh`, `MemoryMax`, `MemorySwapMax` and `TasksMax` with it. The re-entry branch exists so that *"a changed cap lands without a session restart"* (the hook's own comment at the call site). On systemd 261 it can never do that: every `/clear`, resume and compact takes the branch, issues the call, fails, and — because the readback asserts *observed* values — reports `applied` whenever the existing caps already match, or `scope_caps_unverified` when they are stale. The failure is therefore silent precisely in the common case and the refresh's whole purpose is dead on current systemd.

The `repair_stale_scopes` arm added in #9239 hit the identical defect during its own build and was fixed by dropping `OOMPolicy` from its `SetUnitProperties` call (`repair_eval_scope`, `.claude/hooks/memory-backstop.sh` comment block ~:413–417). The re-entry call site predates that work and was deliberately not fixed inside #9239's PR — filed as #9246.

## Proposed Solution

One call-site change plus its pinned coverage, mirroring the repair arm exactly:

**Edit — `.claude/hooks/memory-backstop.sh`, the re-entry refresh (~:855–863, inside the `else` arm of `if (( start_rc != 0 ))`):**

```bash
      "${TO[@]}" busctl --user call org.freedesktop.systemd1 /org/freedesktop/systemd1 \
        org.freedesktop.systemd1.Manager SetUnitProperties "sba(sv)" \
        "$scope" true 4 \
        "MemoryHigh" "t" "$SCOPE_HIGH_BYTES" \
        "MemoryMax" "t" "$SCOPE_MAX_BYTES" \
        "MemorySwapMax" "t" 0 \
        "TasksMax" "t" "$SCOPE_TASKS_MAX" \
        >/dev/null 2>&1
```

- Arity `5` → `4`; drop the `"OOMPolicy" "s" "continue" \` line.
- Add a comment above the call mirroring `repair_eval_scope`'s: `OOMPolicy` is creation-only on scopes — measured on systemd 261, `SetUnitProperties` rejects it and the all-or-nothing call drops the four caps with it; every hook version has created scopes with `OOMPolicy=continue`, so the existing value persists and there is nothing on that axis to refresh.
- Bump `readonly BACKSTOP_REVISION` `2` → `3` — a behavioural wire change; the revision-bump guard (`scripts/check-backstop-revision.sh`, required check) fails the PR without it, and an un-bumped change is undeliverable to stale-checkout sessions.

**Re-vendor** — `plugins/soleur/hooks/memory-backstop.sh` is pinned byte-identical by `plugins/soleur/test/backstop-parity.test.ts`; regenerate with `cp .claude/hooks/memory-backstop.sh plugins/soleur/hooks/ && chmod 0755`. A `plugins/` copy receives the bump automatically via the copy.

**Coverage (the "reintroduction reds" ask from the issue):**

1. *Static pin* in `.claude/hooks/memory-backstop.test.sh` (fixture half — runs in CI with no systemd): extract the `"$scope"`-targeted `SetUnitProperties` block (the re-entry call — uniquely identified by its unit operand; the slice calls target `"$SLICE_NAME"`/`"soleur.slice"` and the repair call targets `"$u"`) and assert it carries `true 4`, all four cap properties, and no `OOMPolicy`; extraction-empty is a `fail`, never a vacuous pass. Assert `grep -c '"OOMPolicy" "s" "continue"' "$HOOK"` is exactly `3` — the creation sites in `sweep_unadopted_agents`, main's `StartTransientUnit`, and the pid-reuse `StartTransientUnit` — so a fix that stripped creation-site `OOMPolicy` (breaking the OOM semantics T8/M2a verify) also reds.
2. *Live-arm pin* in the same file: inside the existing `applied` e2e arm, before the already-scheduled re-entry `run_real_hook` (~:1464), degrade the adopted scope's `TasksMax` to `37984` via a direct runtime `SetUnitProperties` (raising a bound is harmless while set — the incident's own stale shape), then assert after the run that `TasksMax` read back `4096` and the new ledger line is `outcome:"applied"`. On the pre-fix hook under systemd 261 this reds both ways (TasksMax stays `37984`, ledger records `scope_caps_unverified`); post-fix it greens. Add the label (`T21-reentry-converge`) to `LIVE_LABELS` and `live_mark`/`skip` it per the #8008 emission-vs-reachability guidance.
3. *Mutation battery row M11* in `.claude/hooks/memory-backstop-mutation-battery.sh` (manual live suite): a mutant that re-adds `"OOMPolicy" "s" "continue"` to the re-entry call and bumps its arity `4` → `5` — the #9246 regression shape. Arms mirror M7/M10: `mutated_or_die` the landing; a baseline arm first proves the unmutated hook reconverges a deliberately-degraded `TasksMax` between two hook runs on one synthetic wrapper (M7's `run_reentry` shape); the mutant arm leaves the cap degraded → `report` records KILLED. Version-gated by an empirical probe — issue a real `SetUnitProperties` carrying `OOMPolicy` against the scope created in the arm; if the host's systemd accepts it (pre-261), print a skip note and count neither killed nor survived, because the defect class does not exist there.

## Technical Considerations

- **`OOMPolicy` persistence without the refresh.** `SetUnitProperties` writes only the listed properties; unlisted properties are untouched, and `OOMPolicy` is not runtime-settable at all. Scopes keep the `continue` value set at `StartTransientUnit` — verified: all three creation sites (:369, :798, :833) carry it and the T8 live readback asserts `OOMPolicy=continue`. Removing it from the refresh cannot unset it.
- **Arity is positional truth.** The `a(sv)` array count must equal the property count; the M3 precedent (`fail 10` anchor silently stopped matching when the arity moved) is why the mutation anchors on `"$scope" true N`, not a bare property grep.
- **Mutation anchors must isolate the re-entry call.** `"TasksMax" "t" "$SCOPE_TASKS_MAX"` appears in five places; `"OOMPolicy" "s" "continue"` in four today (:369, :798, :833 creation sites + :862 the defect — three post-fix). The M11 edit keys on the `"$scope" true 4` block (the only `"$scope"`-targeted `SetUnitProperties`), the same idiom M10 used to isolate `"$u"`.
- **Where the pin lives.** The fixture-half assertion reds in CI; the battery is a manual live suite (deliberately not `*.test.sh` — needs a user bus, ~2 min). Both layers are needed: the static pin catches shape reintroduction anywhere, the live arm and M11 catch it behaviourally on systemd ≥261.
- **Fixture-relative-assert baseline.** The hook edit removes a line and adds a comment — no new flagged operands (the file's 3 pinned sites are untouched). The M11 row reuses `mk_mutant`/`run_synthetic`-family helpers and `busctl` calls only — the battery currently produces zero flagged rows. Verify `plugins/soleur/test/fixture-relative-assert.test.sh` stays green; if the scanner reports a new site, prefer rewriting to the existing guarded helpers over regenerating the baseline.
- **Live-arm safety.** The degrade step writes `TasksMax=37984` — strictly *raising* a bound on the suite's own adopted scope, the incident's stale shape — and the very next hook run restores it. No `MemoryMax` lowering (a throttle/kill risk to the suite itself) and no new `soleurtest-*` unit is needed.

## Research Insights

**Subagent fan-out note:** this run executes inside a one-shot pipeline subagent with no Task/Skill spawn capability — the `soleur:engineering:research:*` and discovery-agent fan-outs of Phases 1/1.5/1.5b and the plan-review panel were performed inline via grep/read/gh. Community/functional overlap: N/A — repo-internal hook/systemd machinery; no community artifact covers it. No uncovered stacks detected (Phase 1.5 signature scan: no flutter/rust/elixir/go/swift/kotlin/php signature files relevant — the change is bash + systemd D-Bus calls on covered ground).

**Premise Validation (Phase 0.6):**

- `#9246` — **OPEN** (`gh issue view` verified), no closing PR references; title and body match the pipeline context.
- `#9239` / PR #9241 — **MERGED** 2026-09-30 (`69fcf4b5`). The `repair_stale_scopes`/`repair_eval_scope` arm exists in `.claude/hooks/memory-backstop.sh` (:429–448) and its `SetUnitProperties` call already excludes `OOMPolicy` — the mirror the issue prescribes.
- Defect site verified on this worktree (fresh from `origin/main`): the `"$scope"`-targeted `SetUnitProperties` at ~:855–863 carries `true 5` with `"OOMPolicy" "s" "continue"` (:862).
- Proposed mechanism vs ADR corpus: `grep` of `knowledge-base/engineering/architecture/decisions/` for `OOMPolicy`/`SetUnitProperties` returns ADR-161 (records `OOMPolicy=continue` as a *creation-time* scope property — consistent, unchanged) and ADR-261 (Decision records `OOMPolicy` excluded from the repair set precisely because it is creation-only and the call is all-or-nothing — this fix *applies* that recorded decision to the sibling call site). No rejected-alternative collision.
- Deferred items from the PR #9241 review comment (`gh api .../issues/9241/comments`): "distinguishing stale-vs-deliberately-raised caps needs a cap-tagging design (candidate follow-up); flock-timeout arm skipped; Guard-3 non-exclusivity and guard self-editability are meta-limits; same-uid-trust notes (managed-lib seam, hooks.json wrapper miss) are inside the documented model." — all OUT OF SCOPE per the pipeline brief; no work planned on them.

**Property List (Phase 0.6b):**

- P1 — On systemd 261, a `resume|clear|compact` re-entry converges the scope onto the current cap constants (a changed cap lands without a session restart, per the call site's own contract).
- P2 — `OOMPolicy=continue` remains set on every scope the hook creates (the kill-largest-task semantics T8/M2a verify).
- P3 — A reintroduction of a creation-only property into the re-entry call is caught — statically in CI, behaviourally on a live bus.
- P4 — The fix is deliverable to stale-checkout sessions (revision bump + vendored copy parity), the same delivery contract Guard 1/Guard 2 enforce for every hook change.

**Cut List (Phase 0.6b):**

- *Split `OOMPolicy` into a separate best-effort `SetUnitProperties` call* (the issue's offered alternative) — CUT. It buys no property in the list: `OOMPolicy` is creation-only on scopes, so the call could only ever fail (systemd ≥261) or set the value the unit already has. The repair arm's exclusion rationale applies verbatim.
- *Making the refresh call non-all-or-nothing (per-property retry loop)* — CUT. Five × the D-Bus calls under a 30 s flock for zero observable gain; the four-cap call is already the minimal refresh set.
- *Extracting the cap-property list into a shared variable/function used by both refresh and repair* — CUT for this fix. Two call sites, four properties, and the repair call's `|| { … }` continuation differs from the refresh's ignore-rc shape; a shared abstraction would merge two idioms that drift differently. Noted, not needed.

**Key file map:**

- `.claude/hooks/memory-backstop.sh` — 1097 lines. `BACKSTOP_REVISION=2` :74; cap constants :79–85; `repair_eval_scope` :429 (the correct call shape, comment :413–417); `repair_stale_scopes` :450; `StartTransientUnit` sites carrying `OOMPolicy` :369 (sweep), :798 (main), :833 (pid-reuse); **the defect**: re-entry `SetUnitProperties` :855–863; readback/`scope_caps_unverified` :917–948; exec guard `BASH_SOURCE==$0` near :1090.
- `plugins/soleur/hooks/memory-backstop.sh` — vendored byte-identical copy (payload only, unregistered in `hooks.json`); pinned by `plugins/soleur/test/backstop-parity.test.ts`.
- `.claude/hooks/memory-backstop.test.sh` — CI suite, two arms. T2 wiring count :285–294 (`_scope_tasks_props == 5` — unchanged by this fix); AC7 repair fixture with argv-aware `systemctl`/`busctl` stubs :789–953 (the stub conventions to reuse); e2e `run_real_hook` helper :1266–1269; re-entry run + BindsTo/terminal_scope assertions :1462–1500; `LIVE_LABELS` ledger :75–80.
- `.claude/hooks/memory-backstop-mutation-battery.sh` — manual live battery; `run_synthetic` :52, `run_reentry` :309, `report`/`mutated_or_die` :92/:157, M10 repair-verify arm :468–532 (the two-arm stale-cap pattern M11 mirrors); summary+exit :535.
- `.claude/hooks/memory-backstop-resolve.sh` — resolver orders copies by `BACKSTOP_REVISION` grep; untouched.
- `scripts/check-backstop-revision.sh` — required-check: hook in the merge-base diff ⇒ `BACKSTOP_REVISION` strictly increased.
- `.claude/hooks/README.md` :946 — the sentence "(a pre-existing defect in the re-entry refresh path is tracked as #9246)" becomes stale on merge; update it.
- `.claude/settings.json` SessionStart binds `memory-backstop-resolve.sh` under `startup|resume|clear|compact` — verified; unchanged.
- `plugins/soleur/test/fixture-relative-assert.baseline.txt` — pins per-file flagged-operand counts (`memory-backstop.sh`:3, `.test.sh`:31, battery: none). No drift expected; verify, don't regenerate reflexively.

**Relevant learnings / precedent:** `2026-08-10-a-guard-that-cannot-be-driven-red-is-vacuous` (mutation matrix before the guard); the M3/M10 battery comments (stale-arity anchors silently stop matching — anchor on the call's unit operand); `memory-backstop.test.sh`'s no-env-seam convention (functions take path/command arguments; argv-aware stubs on `PATH`).

## Open Code-Review Overlap

One open `code-review` issue touches files this plan edits:

- **#7208** — "memory backstop (#7166): post-merge hardening" — targets `memory-backstop.test.sh` sweep coverage and `memory-backstop-mutation-battery.sh` coverage gaps (incl. "the re-entry refresh call is never mutated by anything except M7"). **Disposition: acknowledge.** M11 narrows exactly that listed gap for the OOMPolicy axis but does not close the umbrella's remaining items (identity-walk mutants, M3 landing check, per-mutant positive controls). #7208 stays open.
- **#8008** — "memory-backstop.test.sh live-arm ledger records reachability, not emission" — constrains `live_mark` placement for the new live label. **Disposition: acknowledge.** The `T21-reentry-converge` label is added to `LIVE_LABELS`, `live_mark`ed only when the assertion actually executes, and `skip`-marked otherwise.

## User-Brand Impact

- **If this lands broken, the user experiences:** the same failure shape the hook exists to prevent — sessions whose caps can never refresh run on stale bounds until restart; on a regression (e.g. the refresh call malformed) the readback still fires `scope_caps_unverified` and the operator gets a banner, so "broken" surfaces loudly rather than silently unprotected.
- **If this leaks, the user's [data / workflow / money] is exposed via:** no data-egress path; the change removes a property from a runtime D-Bus call and edits tests. The vendored copy re-ships through the pre-existing plugin-update channel — no new distribution surface.
- **Brand-survival threshold:** `none`

## Observability

```yaml
liveness_signal:
  what: ledger line outcome:"applied" in .claude/.memory-backstop.jsonl on re-entry, with the four scope caps read back equal to the shipped constants — the readback block is the in-surface signal this fix restores to honesty
  cadence: per SessionStart event (startup|resume|clear|compact)
  alert_target: operator-visible systemMessage banner on outcome:"failed"
  configured_in: .claude/hooks/memory-backstop.sh (readback/emit block ~:915–948)
error_reporting:
  destination: .claude/.memory-backstop.jsonl (per-checkout ledger) + systemMessage stdout channel
  fail_loud: reason:"scope_caps_unverified" when readback differs from constants — unchanged contract; post-fix it fires only on genuine non-convergence, not on every systemd-261 re-entry
failure_modes:
  - mode: creation-only property reintroduced into the re-entry call
    detection: static call-shape pin in memory-backstop.test.sh (CI, always runs) + M11 mutation row + T21 live reconvergence assertion (live hosts)
    alert_route: test failure at the change; at runtime scope_caps_unverified when caps are stale
  - mode: vendored plugin copy drifts from the repo hook
    detection: backstop-parity.test.ts byte-equality
    alert_route: required test failure
  - mode: hook changed without BACKSTOP_REVISION bump (undeliverable to stale checkouts)
    detection: scripts/check-backstop-revision.sh in pr-quality-guards
    alert_route: required-PR-check failure
logs:
  where: .claude/.memory-backstop.jsonl per checkout
  retention: rotated by lib/log-rotation.sh (existing)
discoverability_test:
  command: grep -c '"OOMPolicy" "s" "continue"' .claude/hooks/memory-backstop.sh
  expected_output: "3"
```

## Guard Contract

### Guard 1 — re-entry refresh carries only runtime-settable caps

**Property.** Every `SetUnitProperties` call the hook issues on a scope carries only runtime-settable cap properties (`MemoryHigh`, `MemoryMax`, `MemorySwapMax`, `TasksMax`) — a creation-only property (e.g. `OOMPolicy`, `BindsTo`) in the all-or-nothing call disables the entire refresh on systemd ≥261.

**Assembly.** The `SetUnitProperties` call sites in `.claude/hooks/memory-backstop.sh` — `"$SLICE_NAME"` (fleet caps + `ManagedOOMPreference`), `"soleur.slice"` (parent-slice preference), `"$scope"` (re-entry refresh — this fix), `"$u"` (`repair_eval_scope`, already pinned by AC7). The chokepoints are (a) the static call-shape pin in `memory-backstop.test.sh` extracting the `"$scope"`-targeted block, and (b) mutation-battery M11 measuring live convergence; the OOMPolicy-count pin quantifies over the *whole file* so a property that merely moves call sites still reds.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Re-add `"OOMPolicy" "s" "continue"` to the re-entry call (arity `4`→`5`) — the #9246 regression | RED — static shape pin + count pin (3→4); M11 behavioural RED on systemd ≥261 |
| 2 | Add a *different* non-runtime property (e.g. `"BindsTo" "as" 1 …`) to the re-entry call — a second member after a compliant first | RED — the pin whitelists the four caps, never blacklists OOMPolicy specifically |
| 3 | Retarget/rename the re-entry call so no `"$scope"`-targeted `SetUnitProperties` exists | RED — extraction-empty fails; the pin cannot vacuously pass on a missing call (dispatch row) |
| 4 | Reorder the four cap properties within the re-entry call (TasksMax listed first) | PASS — must-PASS non-canonical input: order is not the property |
| 5 | Suite mutation: drop `TasksMax` from the pin's expected whitelist | RED on the unmutated hook — proves the assertion reads the real call, not a constant (harness row) |

M11's own anti-vacuity: `mutated_or_die` on the re-add, a baseline arm that must reconverge before the mutant's verdict counts, and the empirical OOMPolicy-rejection probe gating the row on systemd version.

## Files to Create

- None. (All coverage lands as edits to existing suites; the branch's `tasks.md` is pipeline bookkeeping, not a deliverable.)

## Files to Edit

- `.claude/hooks/memory-backstop.sh` — drop `"OOMPolicy" "s" "continue"` + arity `5`→`4` in the re-entry `SetUnitProperties` (~:855–863); add the creation-only rationale comment; `BACKSTOP_REVISION` `2`→`3`.
- `plugins/soleur/hooks/memory-backstop.sh` — re-vendor via `cp .claude/hooks/memory-backstop.sh plugins/soleur/hooks/ && chmod 0755` (byte-identical pin).
- `.claude/hooks/memory-backstop.test.sh` — fixture-half pin (re-entry call shape + OOMPolicy count == 3) beside the T2 wiring check (~:285); live arm: degrade `TasksMax`→`37984` before the existing re-entry `run_real_hook` (~:1464), assert `4096` + `outcome:"applied"`; new `T21-reentry-converge` entry in `LIVE_LABELS` with mark/skip placement per #8008.
- `.claude/hooks/memory-backstop-mutation-battery.sh` — new M11 row after M10 (before the `killed=/survived=` summary): version probe → baseline reconvergence positive control → OOMPolicy-reintroduction mutant verdict.
- `.claude/hooks/README.md` — update the stale "(a pre-existing defect in the re-entry refresh path is tracked as #9246)" parenthetical (:946) to state the re-entry refresh now applies the same exclusion.

## Implementation Phases

### Phase 1: Failing tests first (cq-write-failing-tests-before)

- 1.1 Add the fixture-half pin to `memory-backstop.test.sh` (extract `"$scope"`-targeted `SetUnitProperties`; assert `true 4`, four caps, no `OOMPolicy`, non-empty extraction; assert OOMPolicy count == 3). RED on the current hook (call carries `true 5` + OOMPolicy; count 4).
- 1.2 Add the live-arm degrade/reconverge assertion + `T21-reentry-converge` label. RED on systemd ≥261 (TasksMax stays `37984`, ledger `scope_caps_unverified`).
- 1.3 Add battery row M11. Verify it greens on the post-fix shape and the reintroduction mutant is KILLED.

### Phase 2: Hook fix + vendored copy

- 2.1 `.claude/hooks/memory-backstop.sh`: drop the OOMPolicy line, `5`→`4`, add the comment, bump `BACKSTOP_REVISION` to `3`. `bash -n` clean.
- 2.2 `cp` to `plugins/soleur/hooks/memory-backstop.sh`, `chmod 0755`.
- 2.3 `.claude/hooks/README.md` parenthetical update.

### Phase 3: Verification

- 3.1 `bash .claude/hooks/memory-backstop.test.sh` — fixture arm green; live arm green on this systemd-261 host (run standalone, not under lefthook, per the file's own skip note at :1504).
- 3.2 `bash .claude/hooks/memory-backstop-mutation-battery.sh "$PWD"` — all rows green incl. M11.
- 3.3 `bun test plugins/soleur/test/backstop-parity.test.ts`; `bash plugins/soleur/test/fixture-relative-assert.test.sh` — no drift; `bash scripts/check-backstop-revision.sh` locally if feasible (needs `origin/main` merge-base).
- 3.4 `bash scripts/test-all.sh` (or the shard containing the hook suites) green.

## Acceptance Criteria

- [ ] AC1: The re-entry `SetUnitProperties` call targets `"$scope"` with `true 4` carrying exactly `MemoryHigh`, `MemoryMax`, `MemorySwapMax`, `TasksMax` — no `OOMPolicy` (static pin green; `bash -n` clean).
- [ ] AC2: `"OOMPolicy" "s" "continue"` appears exactly 3× in the hook — the three `StartTransientUnit` creation sites (:369, :798, :833) — so the OOM semantics of scope creation are unchanged.
- [ ] AC3: `BACKSTOP_REVISION` strictly greater than `origin/main`'s `2` (bumped to `3`); `check-backstop-revision.sh` satisfied.
- [ ] AC4: `plugins/soleur/hooks/memory-backstop.sh` byte-identical to the repo hook; `backstop-parity.test.ts` green.
- [ ] AC5: On a live systemd ≥261 bus, the suite's re-entry run reconverges a scope degraded to `TasksMax=37984` back to `4096` and logs `outcome:"applied"` (label `T21-reentry-converge` marked or explicitly skipped per the ledger).
- [ ] AC6: Battery row M11: a mutant reintroducing `OOMPolicy` into the re-entry call leaves the degraded cap unconverged → KILLED; the baseline arm reconverges (positive control); hosts whose systemd accepts `OOMPolicy` on scopes print a skip note instead of a verdict.
- [ ] AC7: README no longer describes the re-entry OOMPolicy defect as open/tracked.
- [ ] AC8: `memory-backstop.test.sh`, `memory-backstop-mutation-battery.sh`, `backstop-parity.test.ts`, `fixture-relative-assert.test.sh`, and `check-backstop-revision.sh` all green; no baseline regeneration needed (or regenerated with the new rows individually justified).

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — repo-internal hook/systemd bug fix on an existing engineering surface. No UI-surface files in Files-to-Edit/Create, so the mechanical Product/UX override does not fire. Deferred trust-model notes from the PR #9241 review (operator-raise cap-tagging design, managed-lib seam, guard self-editability) are acknowledged as out of scope above.

## Test Scenarios

- Given a session scope already exists with stale caps, when SessionStart fires a re-entry (`resume`/`clear`/`compact`), then `SetUnitProperties` succeeds and the four caps converge — verified live by the `T21` degrade→reconverge arm on systemd 261.
- Given a mutant hook with `OOMPolicy` reintroduced into the re-entry call, when the battery runs M11 on systemd ≥261, then the refresh call fails, the degraded cap stays stale, and the mutant is KILLED.
- Given a host whose systemd accepts `OOMPolicy` on scopes (pre-261), when M11's probe runs, then the row prints a skip note and counts neither killed nor survived.
- Given a static read of the hook, when the `"$scope"`-targeted `SetUnitProperties` block is extracted, then it carries `true 4` and the four caps — and the file holds exactly three `OOMPolicy` creation sites.
- Given the vendored plugin copy, when `backstop-parity.test.ts` runs, then byte-equality and marker presence hold (Guard 2).
- Given the PR diff touches the hook, when `check-backstop-revision.sh` runs, then `BACKSTOP_REVISION` is strictly greater than merge-base (Guard: revision bump).

## Success Metrics

- On this host (systemd 261), post-merge ledger lines on `resume`/`clear`/`compact` show `outcome:"applied"` for adopted sessions — `scope_caps_unverified` stops firing on every re-entry with stale-free caps and stops *masking* a never-applied refresh.
- A cap-constant change propagates to existing sessions on their next SessionStart without restarts — the refresh's documented purpose is restored on current systemd.
- Battery M11 + the static pin make the property-set exclusion machine-enforced: a reintroduction reds in CI and (on ≥261) in the live battery.

## Dependencies & Risks

- **systemd-version sensitivity.** The defect only manifests where `SetUnitProperties` rejects scope `OOMPolicy` (measured 261). Pre-261 hosts were *working* — the fix is safe there too (the property is still set at creation; the refresh merely stops sending an extra member). M11's empirical probe keeps the battery honest on older hosts.
- **Re-entry branch reachability in tests.** The fixture arm exercises `main` only end-to-end on the live path; the static pin is the CI-red layer — both are required, matching how AC7 pins the repair call.
- **Revision-bump discipline.** `BACKSTOP_REVISION` `2`→`3` in the same edit; `check-backstop-revision.sh` is the required check that makes a missing bump impossible to merge.
- **Scope of the fix.** Deliberately excludes the PR #9241 deferred items (cap-tagging design for operator raises, managed-lib seam, guard self-editability) and the remaining #7208 umbrella items — a re-entry *scope-leak* style mutation (scope-name `$RANDOM`) remains uncovered per #7208 A; M11 covers only the OOMPolicy axis it names.

### Sharp Edges

- Never `systemctl set-property` without `--runtime` / never drop `runtime=true` from `SetUnitProperties` — persistent mutation of the operator's systemd config is the M5 class.
- Arity and property list must move together — a property-line removal without the `5`→`4` produces a malformed call that fails *for a different reason* (M2 header's measured lesson).
- M11's mutation must land inside the `"$scope"`-targeted call only — `/g`-less first-match edits on shared literals (`"TasksMax"`, `"OOMPolicy"`) hit the wrong site (M2a/M10's measured lesson); anchor on the unit operand.
- `mutated_or_die` + baseline positive control + version probe are the row's anti-vacuity set — a mutation that doesn't land, or a host where the rejection doesn't exist, must not report a verdict.
- The static pin's block extraction (e.g. `awk '/SetUnitProperties/,/\>\/dev\/null/'`) must not let its start and end patterns match the same line, and must first select the `"$scope"`-targeted call before asserting property membership — `SetUnitProperties` appears four times in the hook, so an unanchored range reads the wrong call (sharp-edges `awk '/A/,/B/'` entry).
- Never `source`/`eval` a candidate hook to read its revision — grep only (ADR-156 posture, applies to any new helper touching the marker).
- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6 — filled above.
- Headless-mode note: no AskUserQuestion gates were run; this run executes inside a pipeline subagent.

## References & Research

- Issue: #9246 (OPEN — this plan closes it); parent work: #9239 / PR #9241 (`69fcf4b5`, merged 2026-09-30).
- ADR-161 (memory-backstop via systemd transient scopes — `OOMPolicy=continue` as creation-time property), ADR-261 (version-independent hook resolution — records the repair-set exclusion rationale this fix extends to the re-entry call), ADR-156 (untrusted-input posture for candidate hooks).
- Sibling plan: `knowledge-base/project/plans/2026-09-29-fix-backstop-hook-version-resolution-plan.md` (structure mirrored).
- Deferred-with-rationale record: PR #9241 review comment (cap-tagging candidate follow-up; managed-lib seam; guard self-editability) — documented trust-model notes, out of scope.
- systemd reference: `SetUnitProperties` runtime-property semantics and the all-or-nothing contract are documented inline in the hook (~:405–417, :909–914) and measured on systemd 261 on this host.
