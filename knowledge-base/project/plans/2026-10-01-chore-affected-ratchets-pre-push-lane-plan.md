---
title: "chore(ci): add a fast affected-ratchets pre-push lane for CI-only failures"
type: chore
date: 2026-10-01
slug: chore-affected-ratchets-pre-push-lane
branch: feat-one-shot-9400-prepush-ratchet-lane
issue: 9400
closes: 9400
priority: p2-medium
domain: engineering
lane: cross-domain
brand_survival_threshold: none
requires_cpo_signoff: false
---

# chore(ci): add a fast affected-ratchets pre-push lane for CI-only failures

## Enhancement Summary

**Deepened on:** 2026-10-01 (inline deepen pass — no subagent fan-out
available in this execution context; halt gates 4.6–4.11 run mechanically)

### Key Improvements
1. Verified all five named members exist on this branch with exact
   invocations (incl. the two `--check-highwater` CI forms at ci.yml:229/287
   and `lint-rule-bodies.py --check --base` at ci.yml:510).
2. Corrected the premise scan: `grok-pre-push-gate.sh` already fetches
   origin/main + runs one merge-base lint (Grok arm only) — narrowed the
   gap claim to "no merged-tree evaluation anywhere", which is what the issue
   actually needs.
3. Added the git-env-scrub parity requirements (`hook-git-env-coverage`,
   `git-env-list-parity`, `SSH_ASKPASS`), portability pattern
   (`timeout`→`gtimeout`→bare), and shard-manifest regeneration task.
4. Guard Contract matrix covers all five observed failure classes as
   mutation rows plus dispatch-vacuity, stop-at-first, lifecycle-reorder and
   harness must-PASS rows — lint-verified (`lint-guard-contract.py`: rc 0).

### New Considerations Discovered
- `test-affected-kb-consumers` costs a full selection walk (~4–11 min) —
  unconditional inclusion would break the 1–2 min budget; resolved via the
  conditional tier (three triggers).
- `plugin-root-anchoring.test.ts` (the wider CI gate) needs
  `apps/web-platform/node_modules`, absent in the scratch worktree — the lane
  covers F3 via `plugin-root-anchor-debt.sh` (documented residual; the
  vitest guard stays CI-side).
- `GIT_LOCATION_VARS` is a six-site pinned constant — the lane is a seventh
  consumer; its suite must assert the same set.

## Overview

PR #9339 (merged 2026-10-01) spent an 11-seat review and ~8 CI cycles on a small
disk-leak fix because five failures existed only in CI. The local gate
(`scripts/test-all.sh --affected`, ~25–40 min of 145 always-on ratchets plus
edge suites) is the wrong cost shape for catching them pre-push, and — more
fundamentally — it runs on the **unmerged** tree, so ratchets that land on
`origin/main` after the branch forked are structurally invisible to it.

This plan adds a **fast pre-push lane**: a standalone script that fetches
`origin/main`, materializes the *merged* branch+main tree in a scratch git
worktree (never mutating the operator's branch), and runs only the cheap
ratchet/lint suites a diff can trip — plus a condition-triggered expensive
tier — printing a per-member receipt. It wires into `lefthook.yml`'s
`pre-push:` section and stays directly invocable.

## Problem Statement / Motivation

The five CI-only failures on #9339, with the fix commits that closed them:

| # | CI-only failure | Fix commit | Local blind spot |
|---|---|---|---|
| F1 | class-b highwater after a main merge | `21c2efa184` (snap `lint-trap-tempfile-ownership.highwater` to 71) | ratchet runs on the unmerged tree; main's class-b population is absent |
| F2 | kb-consumers baseline (ratchet landed on main after the fork) | `61c5105a25` (+5 rows in `test-affected-kb-consumers.baseline.txt`) | the ratchet file itself did not exist in the branch checkout |
| F3 | plugin-root anchoring | tripped by branch edits to `plugins/soleur/**/*.md` (e.g. `work-scratch-sandboxes.md`) | `plugin-root-anchor-debt.sh` is cheap but nobody ran it pre-push |
| F4 | vitest absent in some CI shards | `bbaaf27468` (gate vitest leaf on `SOLEUR_REQUIRE_VITEST` in `test-scratch-residue.sh`) | local runs have `apps/web-platform/node_modules` present; the shard env (no vitest) is never simulated |
| F5 | tmpfs-vs-ext4 difference in a test | scratch-residue/tmp-purge test changes (`bbaaf27468`, `de9fa5e643` area) | local `/tmp` is tmpfs; CI `/tmp` is ext4 — suites see a different filesystem |

"Skipping the full local battery was the operator's call; nothing cheap stood
in for it" (issue body). The cost asymmetry is the defect: the only local gate
costs ~25+ minutes, so rational operators skip it, and cheap-to-compute
verdicts arrive via CI instead — each cycle ~10-20 min of wall clock plus
CI spend.

## Research Insights

### Premise Validation (Phase 0.6)

- `#9400` is OPEN, unblocked; `#9339` is MERGED (2026-10-01T18:59Z). Premise holds.
- Every suite the issue names exists on this branch and was located:
  `lint-trap-tempfile-ownership.py --check-highwater` (+ sibling `.highwater`
  consumers), `scripts/test-affected-kb-consumers.test.sh` +
  `.baseline.txt`, `scripts/plugin-root-anchor-debt.sh` +
  `apps/web-platform/test/plugin-root-anchoring.test.ts`,
  `plugins/soleur/test/lib/fixture-scan.py` consumers
  (`fixture-relative-assert`, `fixture-dir-operand-assert`,
  `fixture-cd-containment` `.test.sh`), `scripts/lint-skill-body-budget.py`.
- Existing pre-push machinery (the mechanism-minimality scan): `lefthook.yml`
  `pre-push:` holds only file-scoped lints (client-pii-grep,
  questionnaire-identity, rejected-register); `scripts/hooks/pre-push` (opt-in
  via `core.hooksPath`) execs `test-all.sh --affected`;
  `plugins/soleur/scripts/grok-pre-push-gate.sh` (Grok arm) runs the same
  `--affected` plus build/fidelity — and already `git fetch`es origin/main and
  runs `lint-rule-bodies.py --check --base <merge-base>` in its fast phase
  (`grok-pre-push-gate.sh` phase 1). **None performs `git merge origin/main`
  or evaluates a merged tree** — fetching + merge-base arithmetic is not
  merge materialization, so the merged-tree property the issue asks for is
  uncovered anywhere locally. The Grok gate's phase-1 overlap is partial
  (one merge-base lint) and Grok-arm-only; this lane generalizes that arm to
  lefthook/standalone and adds the merged-tree semantics it lacks.

### Property List (Phase 0.6b)

- **P1 — cheap net.** A pre-push check with a wall-clock cost low enough that
  skipping it is no longer the rational call (issue: ~1–2 min for the common
  case).
- **P2 — post-merge visibility.** Ratchets evaluate the tree CI will see —
  branch+`origin/main` merged — so baselines and ratchets that arrived via
  main (F1, F2) are exercised locally.
- **P3 — failure-class coverage.** Each of F1–F5 is reproducible by a lane
  member or by the lane's environment shaping on the pre-fix commits.
- **P4 — honest verdict.** The lane prints what it ran, what it skipped and
  why; "ratchet lane passed", never "tests verified" (CLO wording rule from
  the #9307 brainstorm); a member that did not run is never counted as passed.

### Cut List (Phase 0.6b)

- **"Run `test-all.sh --affected` faster" as the mechanism** — rejected:
  always-on floor is ~145 suites / 22–39 min measured (ADR-242); the cost is
  the membership, not the runner. Covered by the curated member list instead.
- **`git merge origin/main` into the operator's branch in the lane** —
  rejected: a pre-push hook writing merge commits onto a possibly-dirty
  working tree is a mutation a hook must not own. The scratch worktree buys
  P2 with zero branch mutation.
- **`git merge-tree`/`git archive` materialization without a worktree** —
  rejected: lane members are git-aware (`git ls-files`, `--check-highwater`'s
  merge-base compare, `--base` args); a bare archive has no `.git` and breaks
  them. The linked worktree shares the object store, so all of it just works.
- **A fourth "selector" over the affected registry** — rejected (cf. #8621's
  open convergence debt): the lane's member list is curated and the
  branch-touched tier is a plain `git diff --name-only` filter, not a new
  edge-classification mechanism.

### Measurements (Phase 0.6c — the value proposition is a cost claim, so it is measured)

- `bash scripts/test-all.sh --print-selection` on this worktree (clean tree,
  empty branch diff): **4m17s real**, selected=119 (all always_on) of 538
  registrations. This is the floor any selection-machinery-based lane pays.
- `scripts/test-affected-kb-consumers.test.sh` documents its own cost as "a
  full `--print-selection` walk (~11 min of derive today)" in
  `scripts/lib/test-affected-paths.sh` (comment above
  `AFFECTED_SCRIPTS_TEST_AFFECTED_KB_CONSUMERS_PATHS`).
- `scripts/plugin-root-anchor-debt.sh` is a `git grep` over
  `plugins/soleur/**/*.md` — seconds.
- `lint-skill-body-budget.py` is ~0.1 s per its lefthook registration comment
  (lefthook.yml `skill-body-budget-lint`).
- **Consequence:** the issue's "1–2 minute" budget holds for the fast tier
  (highwater lints, anchor probe, fixture-scan suites, byte budget — all
  seconds-scale) but is unattainable if `test-affected-kb-consumers` runs
  unconditionally. The lane therefore carries a **conditional tier** (below);
  the issue's acceptance criterion is preserved because the trigger fires on
  exactly the conditions under which the ratchet can newly fail.

### Institutional learnings that apply

- `2026-10-01-anchoring-a-matcher-flips-its-error-direction-and-the-ratchet-i-wrote-never-ran.md`
  — register new suites explicitly (`run_suite` + orphan census); verify the
  suite runs before believing the plan's sentence.
- `2026-10-01-an-ambient-ci-variable-is-inherited-by-every-nested-runner-and-a-gate-on-it-needs-a-scrub.md`
  — the lane must run members under a scrubbed env (`CI`/`GITHUB_*`
  inheritance has produced false-local-green before).
- `2026-09-27-a-blocking-gate-diffing-against-moving-main-fails-on-drift-...`
  (ship SKILL.md §3010) — a base-side red after a merge is not necessarily
  yours; the receipt distinguishes `merge` from `member` failures.
- `ship/SKILL.md` §1645 — merge-base-relative lints (`lint-rule-bodies.py
  --base`, `lint-skill-body-budget.py --base`) are the recurring CI-only
  catch; both belong in the fast tier.
- `2026-06-06-lefthook-pre-push-push-files-and-dual-glob-depth1.md` —
  `{staged_files}` is empty at pre-push; the lane takes no file args at all
  (it derives its own diff), which sidesteps the whole class.
- `lefthook.yml` `bun-test` comment — "no pre-push battery exists … by design
  (ADR-183)". This lane does not contradict ADR-183: CI remains the merge
  gate; the lane is an advisory-quality net, never a claimed equivalent.

## Research Reconciliation — Spec vs. Codebase

| Issue/spec claim | Codebase reality | Plan response |
|---|---|---|
| "1–2 minute lane" running `kb-consumers` among others | `test-affected-kb-consumers` alone costs a full selection walk (~4–11 min measured/documented) | Conditional tier: kb-consumers runs when its trigger fires (below); fast tier stays seconds-scale. The 1–2 min figure describes the fast tier; the issue's intent (catch the failure locally) is preserved |
| "after merging current origin/main" | No existing local mechanism merges main; ratchets are git-aware so archive materialization fails | Scratch worktree: `git worktree add --detach` + in-scratch `git merge origin/main` |
| Five failures reproduce "through the lane" | F4/F5 are environmental (shard toolchain, filesystem), not diff-trippable ratchets | Lane adds a **branch-touched-suite tier** run inside the deps-free scratch worktree under a disk-backed TMPDIR — the shard condition and ext4 backing both reproduced by construction |
| "nothing cheap stood in for" the battery | `scripts/hooks/pre-push` exists but execs the ~25 min `--affected` | Lane is a new, genuinely cheap rung; it is *also* inserted as stage 1 of `scripts/hooks/pre-push` |

## Proposed Solution

New script `scripts/pre-push-ratchet-lane.sh`:

1. **Resolve diff.** `base=$(git merge-base origin/main HEAD)`; if the branch
   has no diff vs `origin/main`, print the receipt and exit 0 (nothing to
   gate — mirrors `scripts/hooks/pre-push`'s early exit).
2. **Fetch + materialize merged tree.** `git fetch origin main` (bounded);
   `git worktree add --detach "$SCRATCH" HEAD`; `git -C "$SCRATCH" merge
   --no-edit origin/main`. Merge conflict → `verdict=MERGE_CONFLICT`, exit 2
   (distinct from a member failure — the receipt names which). Fetch failure →
   degrade arm: run on the unmerged checkout with `merge=skipped:<reason>` in
   the receipt (fail-toward-coverage, per the #9307 brainstorm's CTO note).
3. **Fast tier (always run, seconds-scale):**
   - `python3 scripts/lint-trap-tempfile-ownership.py --check-highwater`
   - `bash scripts/lint-supabase-deprecated-endpoints.sh --check-highwater`
   - the remaining committed `.highwater` consumers enumerated at
     implementation time (`lint-diagnosis-claims`, `alarm-issue-filing-guard`,
     `lint-workflow-step-env-refs` — each invoked the way its CI/test
     registration does)
   - `bash scripts/plugin-root-anchor-debt.sh`
   - `bash plugins/soleur/test/fixture-relative-assert.test.sh`,
     `fixture-dir-operand-assert.test.sh`, `fixture-cd-containment.test.sh`
   - `python3 scripts/lint-skill-body-budget.py --base "$(git -C "$SCRATCH"
     merge-base origin/main HEAD)"`
   - `python3 scripts/lint-rule-bodies.py --check --base "$(git -C "$SCRATCH"
     merge-base origin/main HEAD)"` (ship SKILL §1645's merge-base arm —
     same CI-only-failure class)
   All run **inside the scratch worktree** on the merged tree.
4. **Branch-touched tier:** `git diff --name-only "$base"...HEAD` filtered to
   `*.test.sh`/`test_*.sh` suite files; run each directly (cap ~12, per-member
   timeout) inside the scratch worktree — which carries **no node_modules**,
   reproducing the vitest-absent shard (F4) — under `TMPDIR` pinned to a
   disk-backed root (`scripts/lib/scratch-root.sh` or `/var/tmp`),
   reproducing CI's ext4 backing (F5), with `env -i`-style scrubbing of
   `CI`/`GITHUB_*`/`LEFTHOOK*` per the ambient-variable learning.
5. **Conditional tier:** `bash scripts/test-affected-kb-consumers.test.sh`
   runs when any of: (a) the merged-tree diff vs the *old* merge-base touches
   its declared inputs (`scripts/test-all.sh`,
   `scripts/lib/test-affected-paths.sh`, its own file/baseline — i.e., the
   ratchet or its edges changed on either side); (b) the branch diff touched a
   `*.test.sh` file containing a literal `knowledge-base/` reference
   (cheap `git diff -U0 | grep` trigger — the exact F2 shape); (c) a new
   `*.baseline.txt` under `scripts/` appears in the merge delta. Otherwise the
   receipt prints `skip:<reason>` for it.
6. **Receipt + exit contract.** Per-member `name | verdict | seconds` lines
   and a final `RATCHET_LANE verdict=PASS|RED|ABORT` line. Exit 0 pass,
   1 member-red, 2 infrastructure-abort (no verdict). Wording per CLO: "ratchet
   lane" verdicts, never "tests verified". `--print-members` is a pure-print
   arm — it emits the member table and exits before any fetch, worktree, or
   suite runs (preflight Check 10 executes it read-only under a 15 s cap).
7. **Cleanup.** `git worktree remove --force "$SCRATCH"` via `trap … EXIT` —
   and per the #8288/#8352 learning, the exit-site table (below, Guard
   Contract) enumerates every exit path relative to the first worktree
   mutation.

## Technical Considerations

- **Git-hook env scrubbing.** Like `scripts/hooks/pre-push` and `lefthook.yml`'s
  `plugin-component-test`, the lane must `unset` the full git-location family
  (`GIT_DIR GIT_INDEX_FILE GIT_WORK_TREE GIT_COMMON_DIR
  GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE
  GIT_TEMPLATE_DIR GIT_EXEC_PATH`, plus `SSH_ASKPASS` — the one execution
  vector with no `GIT_` prefix) before spawning anything — lefthook/git
  export these, and a scratch worktree's nested git calls would otherwise
  target the parent repo. The canonical list is `GIT_LOCATION_VARS` in
  `plugins/soleur/test/lib/git-fixture-env.ts`, pinned across six sites by
  `plugins/soleur/test/git-env-list-parity.test.sh`; the lane becomes a
  seventh consumer and its suite asserts the same set. Two hooks already gate
  this shape: `hook-git-env-coverage.test.sh` enumerates every lefthook `run:`
  (via a real YAML parse, `plugins/soleur/test/lib/lefthook-commands.py`) and
  every `scripts/hooks/` file — keep the lefthook entry as a bare
  `bash scripts/pre-push-ratchet-lane.sh` (no runner token in the `run:`) and
  put the `unset` inside the lane script. Trace vars turn OFF via `unset`,
  never `GIT_TRACE=0`/`GIT_CURL_VERBOSE=0` — those are presence-checked, so
  `=0` ENABLES them (#8474).
- **Portability.** The lane runs on every host the repo develops on — macOS
  included. For any timeout use the repo's `timeout`→`gtimeout`→bare fallback
  pattern (`.claude/hooks/git-commit-secret-scan.sh`), never a bare `timeout`.
- **Shard manifest.** The lane's suite lands in the `test-scripts` group;
  untabled labels hash-fallback, but the committed
  `scripts/suite-shard-legs.tsv` should be regenerated
  (`python3 scripts/regenerate-shard-manifest.py --write`) — the runner's own
  error text prescribes it.
- **Worktree location.** `mktemp -d` under a disk-backed root — NOT inside the
  repo tree (untracked clutter, and `.worktrees/` sibling convention) — e.g.
  `"${TMPDIR:-/var/tmp}/prepush-lane.XXXXXX"`. `git worktree add` into it.
  **Precedent diff (Phase 4.4):** the repo's existing worktree machinery is
  `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh` — a
  session-lifecycle manager (leases, stale-branch healing, registry sync). The
  lane deliberately does NOT reuse it: it needs an ephemeral, detached,
  merged-tree checkout, not a named session worktree; plain `git worktree add
  --detach` + `merge` + `remove --force` is the whole surface, and adding a
  lease/registry dependency to a 2-minute hook would invert the cost contract.
  Fixture-side precedent for env scrubbing is
  `plugins/soleur/test/lib/git-fixture-env.ts` (`GIT_LOCATION_VARS`).
- **ADR-133 lock interplay.** The lane must NOT take `test-all.sh`'s
  `tc_acquire` flock — it is a deliberate narrow gate; suites it invokes are
  standalone (`run_suite` wraps them, but the underlying scripts run
  directly). Verify no member itself acquires the lock.
- **Suite registration.** The lane's own test suite
  (`scripts/pre-push-ratchet-lane.test.sh`) needs an explicit `run_suite` line
  in `scripts/test-all.sh` plus a declared edge set in
  `scripts/lib/test-affected-paths.sh` — the registration-not-glob lesson of
  the kb-consumers ratchet.
- **Byte-budget headroom.** If a pointer line lands in `work`/`ship` SKILL.md,
  `python3 scripts/lint-skill-body-budget.py --base "$(git merge-base
  origin/main HEAD)"` must be run first — the file is at-capacity-sensitive.
- **Runtime ceiling.** Fast tier budgeted ≤ ~2 min wall clock; conditional
  tier adds its own bounded window; the receipt reports per-member seconds so
  budget drift is observable, not asserted.

## Implementation Phases

### Phase 1 — Lane script + suite

- Write `scripts/pre-push-ratchet-lane.sh` per Proposed Solution.
- Write `scripts/pre-push-ratchet-lane.test.sh`: the Guard Contract mutation
  matrix below over fixture worktrees; register via `run_suite` in
  `scripts/test-all.sh` and a declared edge set in
  `scripts/lib/test-affected-paths.sh` covering
  `scripts/pre-push-ratchet-lane.*`, `scripts/lib/scratch-root.sh`, and the
  member list it invokes.
- **Member-parity check inside the suite:** assert every lane member's argv
  matches the argv its `run_suite` registration (or CI step) uses — the member
  table is curated, so drift between "what the lane runs" and "what CI runs"
  is the identified failure mode (sharp edge: census with a red unclassified
  bucket, not a name list pinned to the day it was written).
- **Exit-code verification:** before freezing member invocations, run each
  once against the real tree and record its actual rc semantics (sharp edge:
  prescribed exit codes must be verified in the target environment, e.g.
  `git diff --quiet` returning 1 vs the assumed 128).
- Verify registration with `bash scripts/lint-orphan-test-suites.sh`, then
  `python3 scripts/regenerate-shard-manifest.py --write` if the shard legs
  move.

### Phase 2 — Wiring

- `lefthook.yml` `pre-push:`: add a `ratchet-lane` command entry (no glob —
  the lane derives its own diff; `{push_files}` is irrelevant here).
- `scripts/hooks/pre-push`: insert the lane as stage 1 before the
  `--affected` exec (opt-in hook gets the cheap net first).
- Docs pointer: one line in `plugins/soleur/skills/ship/SKILL.md` or
  `work/SKILL.md` — only if `lint-skill-body-budget` shows headroom; else
  document in a runbook and record the deferral.

### Phase 3 — Reproduction verification + ADR

- For each of F1–F5, apply the fix-commit reversal on a throwaway branch and
  drive the lane RED (the acceptance matrix; commands below).
- Amend ADR-242 (new local gate tier) — see Architecture Decision section.
- Update the plan file + tasks to reflect as-built member timing.

## Files to Create

- `scripts/pre-push-ratchet-lane.sh`
- `scripts/pre-push-ratchet-lane.test.sh`

## Files to Edit

- `lefthook.yml` — `pre-push:` command entry
- `scripts/hooks/pre-push` — lane as stage 1
- `scripts/test-all.sh` — `run_suite` registration for the lane's suite
- `scripts/lib/test-affected-paths.sh` — declared edge set for the lane's suite
- `knowledge-base/engineering/architecture/decisions/ADR-242-the-local-gate-defaults-to-affected-suites-and-always-on-ratchets.md` — amendment
- `plugins/soleur/skills/ship/SKILL.md` or `plugins/soleur/skills/work/SKILL.md` — one-line pointer, conditional on byte headroom

## Open Code-Review Overlap

Checked `gh issue list --label code-review --state open` bodies against every
path above (two-stage `--json` → `jq --arg`, 2026-10-01):

- **#8659** (33 suites replace `test-helpers`' composed EXIT trap; leak the
  incident sandbox on direct runs) — **Acknowledge.** The lane invokes suite
  scripts directly, which is exactly the direct-run path #8659 covers; the
  lane's own suite must use the canonical fixture/env helpers, and members
  known-leaky on direct run go on the skip list with a receipt note rather
  than silently green.
- **#7942** (`*.mutation.sh` files run in no gate) — **Acknowledge.** The
  lane's suite is named `*.test.sh` and registered, not a floating mutation
  file.
- **#8800** (census sandbox shares inodes/symlinks with live repo) —
  **Acknowledge.** The lane's scratch is a real `git worktree` checkout —
  separate inodes by construction — never a hardlink/symlink materialization.

No fold-ins: none of the three asks to change the files this plan creates.

## User-Brand Impact

- **If this lands broken, the user experiences:** (operator-facing artifact)
  a pre-push hook that either false-REDs every push — blocking the pipeline
  the way a wedged gate does — or false-green reports "ratchet lane passed"
  while shipping a tree that reds the required `test` context on arrival,
  reproducing the exact eight-cycle CI bill this exists to remove.
- **If this leaks, the user's [data / workflow / money] is exposed via:** no
  regulated-data surface; worst case is workflow/cost — a misleading receipt
  teaches operators to distrust every local gate (the `--print-affected-set`
  class-confusion precedent).
- **Brand-survival threshold:** `none` — no user data, no product surface,
  no sensitive-path diff (regex-checked: `scripts/*`, `lefthook.yml`,
  `scripts/hooks/*`, `knowledge-base/*`, SKILL.md pointer only).

## Observability

The lane is dev-tooling, not a deployed surface; its receipt IS its telemetry.

```yaml
liveness_signal:
  what: "RATCHET_LANE verdict=PASS|RED|ABORT receipt line printed per invocation"
  cadence: per-push (lefthook) / per-invocation (standalone)
  alert_target: operator's push output
  configured_in: "scripts/pre-push-ratchet-lane.sh (receipt emitter) + lefthook.yml pre-push entry"
error_reporting:
  destination: "stderr + receipt (no Sentry — local tool; per ADR-183 it is not the merge gate)"
  fail_loud: "exit 1/2 with per-member verdict lines; ABORT names the infra arm (fetch/worktree/merge)"
failure_modes:
  - mode: "fetch origin/main fails (offline)"
    detection: "receipt merge=skipped:<reason>; lane still runs members on the unmerged tree"
    alert_route: "stderr"
  - mode: "merge conflict between branch and origin/main"
    detection: "verdict=MERGE_CONFLICT exit 2 — distinct from member RED"
    alert_route: "stderr"
  - mode: "scratch worktree leak on abort"
    detection: "leftover /var/tmp/prepush-lane.* dirs; `git worktree list` shows the stale path"
    alert_route: "stderr cleanup warning + trap-based removal"
logs:
  where: "stdout/stderr of the push or direct invocation; nothing persists"
  retention: "terminal scrollback"
discoverability_test:
  command: bash scripts/pre-push-ratchet-lane.sh --print-members
  expected_output: "test-affected-kb-consumers"
```

## Architecture Decision (ADR/C4)

### ADR

- **Amend** `ADR-242-the-local-gate-defaults-to-affected-suites-and-always-on-ratchets.md`
  (`## Amendment — 2026-10-xx`): the local gate gains a third, narrower tier —
  the pre-push ratchet lane — run on the merged branch+main tree in a scratch
  worktree. Records why a curated member list (not the affected selector)
  exists alongside `--affected`, and reaffirms ADR-183: no local run is the
  merge gate. (The sibling brainstorm's CTO already recommended an ADR
  extending ADR-242 for the related gate work.)

### C4 views

**No C4 impact.** Completeness-mandate enumeration (all three of
`model.c4`/`views.c4`/`spec.c4` read, 2026-10-01): the lane introduces **(a) no
new external human actor** — its user is the operator/agent-runtime pair
already modeled (`founder`, `claude`/`devin` plugin surfaces); **(b) no new
external system** — `git fetch`/`push` to the GitHub remote is the existing
`github` element's relationship; **(c) no new container or data store** — the
scratch worktree is process-local disk; **(d) no changed access relationship**
— it reads the same repo the agent already reads. Dev-local gating tiers are
not modeled at C4 granularity today (`test-all.sh`, lefthook, and the Grok
pre-push gate appear nowhere in the model), so there is nothing to update and
no existing description falsified.

### Sequencing

The ADR amendment lands in this PR (not deferred).

## Guard Contract

### Guard 1 — pre-push ratchet lane (`scripts/pre-push-ratchet-lane.sh`)

**Property.** Every lane member that reports non-zero on the merged
branch+`origin/main` tree fails the lane before the push completes — no member
verdict is silently skipped, substituted, or swallowed.

**Assembly.** The chokepoint is the member table inside
`scripts/pre-push-ratchet-lane.sh` (one row per member: fast-tier commands +
the branch-touched suite list + the conditional-tier trigger) and the
worktree lifecycle (`worktree add` → in-scratch `merge` → member loop →
`worktree remove`). Members drift; the assembly is the dispatch loop's
"every member produces exactly one receipt line and one verdict" contract,
enforced by the member-count floor row below.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Revert `21c2efa184` (lower committed `lint-trap-tempfile-ownership.highwater` below the merged-tree census) in the scratch | RED via fast-tier highwater member — proves merged-tree evaluation (F1) |
| 2 | Drop the five `61c5105a25` rows from `test-affected-kb-consumers.baseline.txt` on a branch that touches a kb-reading `*.test.sh` | conditional trigger fires AND RED — proves both the trigger and the member (F2) |
| 3 | Introduce a `{CLAUDE_PLUGIN_ROOT=…}`-class token into a `plugins/soleur/**/*.md` file | RED via `plugin-root-anchor-debt.sh` (F3 shape) |
| 4 | Un-gate the vitest leaf in `test-scratch-residue.sh` (revert `bbaaf27468` semantics) on a branch touching that file | RED in the deps-free scratch — vitest absent, leaf runs unconditional (F4) |
| 5 | Empty the member table / make dispatch report "0 ran" and exit 0 | RED — a lane that measured nothing cannot pass (own-dispatch row) |
| 6 | Two failing members where the loop stops at the first | RED *and* the receipt lists both — a stop-at-first dispatch is the defect |
| 7 | Run members before the in-scratch merge (reorder the lifecycle) | RED — reorder row observing inside the merge window: pre-merge evaluation misses F1/F2 by construction |
| 8 | `git fetch` fails (point `origin` at a bogus URL in fixture) | receipt `merge=skipped:…`, lane still evaluates members, distinct verdict text — degrade declared, not silent |
| 9 | `git worktree add` fails | exit 2 ABORT, not exit 0 — infra abort is not a pass |
| 10 | Member prints PASS text but exits non-zero | RED — verdict is the exit code, never the banner |
| 11 | Harness row: lane suite's own fixture wiring — run the suite against a scratch where the merged tree is clean and member order differs from the canonical list | PASS — must-PASS non-canonical input proves the gate isn't a reject-everything stub |

**Anchor.** The lane compares stored baselines (`.highwater`,
`.baseline.txt`, skill-budget ceilings) against the *merged* tree — a
weakening must therefore move both the baseline AND the population, which is
exactly the cross-PR drift the merge materialization exposes.

**Exit-site table (relative to first write — the `git worktree add`):**

| Exit point | Position vs first write | `worktree remove` guaranteed? |
|---|---|---|
| fetch failure (before add) | before | n/a — no scratch exists |
| add failure | at write | scratch absent or partial; `git worktree prune` fallback |
| merge conflict | after | trap removes scratch with the conflict state preserved in receipt |
| member red | after | trap removes |
| PASS | after | trap removes |
| SIGTERM/SIGINT | after | trap removes (`EXIT INT TERM HUP`) |

## Domain Review

**Domains relevant:** Engineering

### Engineering

**Status:** reviewed (carry-forward — no agent spawn in this pipeline context)

**Assessment:** The #9307 umbrella brainstorm's CTO assessment applies
directly: ship a script with a testable contract (selected set + reason +
fallback reason) rather than skill prose; every path fails toward coverage and
prints what it skipped; refuse vacuous zero-member dispatch. Applied here as:
the member table is a literal, the receipt is the contract, and row 5 of the
mutation matrix is the vacuity check. Serial local execution is accepted by
design (#8231 stays the parallelism track; this lane's cost bound is member
count, not scheduling).

**Brainstorm-recommended specialists:** none (the carry-forward brainstorm's
specialist recommendations were for the parent gate work, already shipped).

No UI surface: Files-to-Create/Edit contain no path matching the shared
UI-surface glob superset (`components/**`, `app/**/page.tsx`, `*.njk`,
`*.html`, etc.) — mechanical override does not fire; Product/UX gate NONE.
CMO omitted under the operator-facing-dev-tooling rationale
(`hr-new-skills-agents-or-user-facing`); CPO not required — no user-facing
product capability.

## Acceptance Criteria

- [x] `bash scripts/pre-push-ratchet-lane.sh` on a clean in-sync branch prints
      a per-member receipt and exits 0 in ≤ ~2 min (fast tier; measured, not
      asserted).
- [x] **AC-F1:** with `21c2efa184` reverted (highwater below merged census),
      the lane exits non-zero and the receipt names the highwater member.
- [x] **AC-F2:** with `61c5105a25` reverted on a branch touching a kb-reading
      suite, the conditional tier fires and exits non-zero naming
      `test-affected-kb-consumers`.
- [x] **AC-F3:** with a plugin-root anchor-debt token added to a
      `plugins/soleur/**/*.md` file, the lane exits non-zero naming
      `plugin-root-anchor-debt`.
- [x] **AC-F4:** with the vitest leaf un-gated on a branch touching
      `test-scratch-residue.sh`, the lane's branch-touched tier runs it in the
      deps-free scratch and exits non-zero.
- [x] **AC-F5:** the tmpfs-vs-ext4-sensitive suite identified during
      implementation (candidate: `test-scratch-residue.sh` /
      `test-tmp-purge.sh` arms fixed around `bbaaf27468`/`de9fa5e643` —
      confirm against #9339 CI logs) reds the lane when its pre-fix form runs
      under the lane's disk-backed TMPDIR shaping; if the failure proves
      unreproducible locally the AC is rewritten during `soleur:work` with the
      evidence, not silently dropped.
- [x] The lane merges `origin/main` inside a scratch worktree: the operator's
      branch tip and working tree are byte-identical before and after a run
      (asserted by the suite via `git rev-parse HEAD` + `git status --porcelain`).
- [x] Merge-conflict, fetch-failure, and worktree-add-failure arms each print
      their distinct receipt verdicts (never a bare 0).
- [x] `lefthook.yml` `pre-push:` carries the `ratchet-lane` entry;
      `scripts/hooks/pre-push` runs the lane before the `--affected` exec.
- [x] `scripts/pre-push-ratchet-lane.test.sh` is registered in
      `scripts/test-all.sh`, carries a declared edge set, and
      `lint-orphan-test-suites.sh` reports it non-orphan.
- [x] ADR-242 amendment committed in this PR.
- [x] Receipt wording is "ratchet lane" verdicts throughout — no "tests
      verified"/"all green" phrasing.

## Test Scenarios

- Given a branch in sync with origin/main, when the lane runs, then it prints
  one receipt line per member and exits 0 within the fast-tier budget.
- Given a branch one commit behind a main that moved a `.highwater`, when the
  lane runs, then the fast-tier highwater member reds on the merged tree and
  the push hook blocks.
- Given `origin` unreachable, when the lane runs, then the receipt shows
  `merge=skipped:<reason>` and members still evaluate the unmerged tree.
- Given a merge conflict, when the lane runs, then `verdict=MERGE_CONFLICT`
  (exit 2), the receipt names the conflicting side, and no member result is
  reported as a failure.
- Given the lane's own suite mutating the member table to empty, when the
  suite runs, then dispatch refuses to report success (vacuity row).
- Deterministic verification: `bash scripts/pre-push-ratchet-lane.test.sh`
  (the suite IS the mutation harness); `bash
  scripts/lint-orphan-test-suites.sh` for registration.

## Success Metrics

- The five #9339 failure classes reproduce locally through the lane on their
  pre-fix commit states (the acceptance matrix above — the issue's own
  acceptance test).
- Fast-tier wall clock ≤ ~2 min on a quiet host; per-member seconds printed so
  drift is measured, not felt.
- Zero branch/working-tree mutation by the lane (verified in-suite).

## Dependencies & Risks

- **Conditional-tier budget honesty.** When the kb-consumers trigger fires,
  the lane is ~4–11 min, not 1–2. The receipt discloses per-member time; the
  trigger is deliberately narrow (kb-reading suite touched, ratchet inputs
  changed, new baseline on main) — a wider trigger makes the lane the slow
  gate it exists to avoid.
- **`test-all.sh` registration is a runner self-edge.** Editing
  `test-all.sh`/`test-affected-paths.sh` degrades this PR's own `--affected`
  runs to fuller coverage (by design, ADR-242) — expect the heavier local gate
  on this branch's own push; CI unaffected.
- **Direct-run member leakage.** #8659 documents suites whose direct run
  leaks the incident sandbox; members exhibiting it are skipped-with-receipt
  until fixed upstream (fold-in declined — separate scope).
- **Worktree hygiene.** `git worktree add` on a dirty or mid-rebase checkout,
  and orphaned scratch dirs after a kill -9, are handled by the exit-site
  table + `git worktree prune` note; the suite asserts cleanup.
- **Lefthook absence.** Cloud/sandbox hosts run `core.hooksPath=/dev/null`;
  the lane is still directly invocable and runs inside `scripts/hooks/pre-push`
  — the lefthook entry is one of two surfaces, not the only net.
- **Stale fork point.** A very old merge-base makes `--base` lints compare
  against an old ceiling file; acceptable — same semantics CI applies.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or omits the threshold
  fails `deepen-plan` Phase 4.6 — filled above.
- The lane's `-name-only` diff for the branch-touched tier must split rename
  rows (`R100<TAB>old<TAB>new`) — or use `--name-only` only where renames
  don't matter; the #9306 matcher learning applies verbatim.
- Never `producer | grep -q` under pipefail in the suite — capture rc on its
  own line (work SKILL.md authoring rule).
- Do not describe the lane as the merge gate anywhere (ADR-183; CLO wording):
  receipt text and PR body say "ratchet lane passed".
- If a pointer lands in a lifecycle SKILL.md, check
  `lint-skill-body-budget.py --base` headroom BEFORE committing — the file
  has been within bytes of ceiling before (#8302-era budget).
- The scratch worktree's suites see no `node_modules`: members that *require*
  it (the plugin-root-anchoring vitest suite) are intentionally covered by the
  bash probe instead — record the coverage boundary in the receipt, don't
  paper over it.

## References & Research

- Issue: #9400; parent cost-reduction context: #9339 (merged) — fix commits
  `21c2efa184`, `61c5105a25`, `bbaaf27468`, `de9fa5e643`, `917a823d62`.
- ADR-242 (affected default + always-on ratchets); ADR-183 (no local run is
  the merge gate); ADR-262 (`--pr-gated` batteries); #8621 (selector
  convergence — open; this plan deliberately adds no new selector).
- Existing surfaces: `lefthook.yml` (`pre-commit` + `pre-push`),
  `scripts/hooks/pre-push`, `plugins/soleur/scripts/grok-pre-push-gate.sh`,
  `scripts/lib/test-affected-paths.sh` (`ALWAYS_ON_SUITES`, declared edges).
- Brainstorm: `2026-09-30-affected-parallel-test-gate-brainstorm.md` (CTO/CLO
  findings carried forward).
- Learnings: `2026-10-01-anchoring-a-matcher-…`, `2026-10-01-an-ambient-ci-variable-…`,
  `2026-09-14-the-runner-i-watched-…`, `2026-06-06-lefthook-pre-push-…`.
