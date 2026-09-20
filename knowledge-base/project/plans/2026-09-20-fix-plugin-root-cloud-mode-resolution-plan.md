---
title: "fix: plugin-root / cloud-mode resolution — worktree-less reap guards, capability-gated session-start dispatch, fleet identity selection"
date: 2026-09-20
slug: fix-plugin-root-cloud-mode-resolution
branch: feat-one-shot-8400-8401-8402-plugin-root-cloud-mode
issue: 8400
closes: [8400, 8401, 8402]
type: bug
priority: p2-medium
domain: engineering
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

## Enhancement Summary

**Deepened on:** 2026-09-20 · **Reviewers:** 7 (DHH, Kieran, code-simplicity,
architecture-strategist, spec-flow, CTO-devex, CPO) + a scoped advisor consult.

### Key improvements

1. **Phase 2 was reversed twice.** The brief's mechanism (move the cache arms into the shared
   resolver) is named and forbidden by ADR-179; the replacement (an arm-agnostic capability gate)
   had a measured fleet-wide blast radius. The shipped design is a capability feature-detect
   **narrowed to the `devin-cache` arm**, which closes the ADR's ground and leaves every other arm
   untouched.
2. **A falsified research premise was caught and corrected.** "No test drives the reap loop
   end-to-end" was false — `lease-protects-active.test.sh` is 1015 lines that do. The consequence
   was material: its arming-hold stamp is required for Guard 1's central mutation rows to be able
   to go RED at all.
3. **A claim marked "verified at plan time" was falsified by execution.** The R6b breakage
   prediction was reasoned from reading the fixture, not run. A reviewer ran it; R6b is indifferent
   to the gate. The claim is struck in place, with the lesson attached.
4. **Two new sentinels would have reddened a CI gate nobody had listed** —
   `git-lock-marker-telemetry.test.ts` derives its scan set from the very directory the script
   lives in.
5. **An ambient-machine dependency was found before it shipped:** `/opt/.devin/plugins` has no test
   override, and widening the arms to three fences triples an exposure that flips MUST-PASS rows on
   exactly the hosts this change targets.

### Gate verification (all mechanical, run at deepen time)

| Gate | Result |
|---|---|
| 4.6 User-Brand Impact | PASS — present, non-empty, threshold `single-user incident` |
| 4.7 Observability | PASS — all 5 fields present; `discoverability_test` verb `bash` is allowlisted, runs in ~0.05s (inside the 15s cap), `expected_output` is a single matchable literal |
| 4.8 PAT-shaped variable | PASS — no matches |
| 4.9 UI wireframe | SKIP — 0 UI-surface paths in `## Files to Edit` / `## Files to Create` (the 2 whole-file regex hits are the Product/UX Gate prose *naming* the globs to record their absence — the absence-grep self-match trap, confirmed by scoping the grep to the gate's real input) |
| 4.10 Encryption Posture | SKIP — no persistent store, no new cross-component connection |
| 4.11 Guard Contract | PASS — `lint-guard-contract.py` green, 3 entries; assemblies are structural (chokepoints and derived scans, not member lists) |
| 4.5 / 4.55 | SKIP — no network-outage trigger, no downtime-inducing operation |

### Citation verification

- **12 of 12** cited AGENTS rule IDs resolve as **active** — none fabricated, none retired.
- **15 of 15** cited `#N` resolve live, and each title matches the semantic role the plan assigns
  it (#7408 slash-bearing branches, #7409 lease library, #7442 silent-skip, #7474
  identity-is-not-freshness, #8308 the three no-op gates, #5454 the fail-closed origin).
  #8400/#8401/#8402 all OPEN.
- Every cited `knowledge-base/**.md` path resolves on disk.
- `lint-infra-no-human-steps.py` green on the plan and the decision-challenges record.

### Read this first

`## Plan Review Consolidation` is authoritative where it conflicts with an earlier section, and
`## Sharp Edges` carries the traps that will otherwise be rediscovered at implementation time. Two
design questions (`/opt` containment under test; fleet full-recipe vs pointer) are listed in
`tasks.md` Phase 0 and must close **before** RED-phase work.

## Overview

Three coupled defects in how Soleur resolves a plugin root and decides whether it is running in a
Devin cloud session, plus the destructive session-start operation that resolution dispatches.

1. `cleanup-merged` in `worktree-manager.sh` gates every safety guard on a non-empty worktree path,
   so a merged branch whose worktree was already removed reaches the branch-delete calls with no
   guard applied — while the banner at the top of the file advertises a fail-closed posture.
2. The `go` skill's Step 0 session-start resolver reads only two arms, so a Devin cloud session with
   no exported plugin-root variable reports `plugin-root-unverified` and skips the gate entirely.
   The two Devin cache arms exist already, confined to Step 0.5, held back by defect 1.
3. The `soleur-cloud-mode` block replicated across the skill fleet selects a Devin plugin root by
   file basename, with no identity check, and then executes what it finds.

Defect 1 is the gate on defect 2: widening Step 0 widens what dispatches `cleanup-merged`, so the
reap-scope fix lands first in the same change.

## Research Insights

### Premise Validation (Phase 0.6)

Checked every reference the brief cites. `gh issue view` reports **#8400, #8401, #8402 all OPEN**,
none with a closing PR, so the ordering premise (#8401 gated on #8400) still holds. Every code
anchor named in #8400 was verified against the file as it stands and **all of them are accurate**:
`worktree-manager.sh` is 3461 lines; the fail-closed banner is the four `[warn]` lines at `:81-84`
(the specific claim is at `:82`); `all_stale_branches` is assembled at `:2773`; the worktree-path
conjuncts are at `:2851` (currently-active), `:2868` (lease), `:2890` (recent-commit grace), `:2905`
(uncommitted changes) and `:2942` (worktree removal); the destructive calls are at `:2954`
(`git push origin --delete`), `:2960` (`git branch -D`) and `:2999`
(`git -C "$GIT_ROOT" reset --hard HEAD`). ADR-178 §Context states the operation is
**unrecoverable** ("delete the worktree, delete the local branch, delete the remote branch, and
close the PR"). Three premises in the brief needed correction, all recorded under *Premise
corrections* below. No stale premise blocks the plan.

### Premise corrections (measured, not asserted)

1. **The three resolver copies all live in `plugins/soleur/commands/go.md`, not "go.md/SKILL.md".**
   `plugins/soleur/skills/go/SKILL.md` is a 27-line Devin-shim stub carrying no resolver at all.
   The three pinned fences are the `## Step 0.0: Workspace Readiness Gate`,
   `## Step 0.5: Cloud Mode detection` and `## Step 0: Session-Start Preamble` bash fences of
   `go.md`, gate names `readiness` / `cloud-detect` / `session-start`.
2. **The `soleur-cloud-mode` fleet is 67 marker blocks, not ~74; the basename-recipe cohort is 69
   files / 70 occurrences.** Measured with `grep -rl 'soleur-cloud-mode:start'`: 64 plugin
   `skills/*/SKILL.md` + 3 `devin/skills/*/SKILL.md` = 67, which is exactly the cardinality
   `devin-cloud-mode.test.ts` pins (`expect(marked.length).toBe(67)`). A separate
   `grep -rn 'find /opt/\.devin/plugins -name'` finds **70 occurrences in 69 files**: the 67 marker
   blocks, plus **two files outside the marker fleet** and **one executable line inside a marker
   file's body**. Those three extras are the part of the cohort a marker-block-only sweep silently
   misses — see *The full #8402 cohort* below. 69 matches the issue title's own count.
3. **Widening Step 0 does not make `cleanup-merged` run on a Devin *cloud* session.** The brief and
   #8401 both frame the win as "a Devin cloud session stops emitting
   `SOLEUR_SESSION_START_SKIPPED reason=plugin-root-unverified`", which is true but incomplete.
   Step 0's dispatch is gated a second time, on the classifier: after resolving a root it runs
   `cloud-detect.sh` and only `local` or `not-local:no-devin-env` set `SESSION_OK=true`. A real
   cloud session returns some other `not-local:<reason>`, so after the fix it emits
   `SOLEUR_SESSION_START_SKIPPED reason=cloud-session verdict=<v>` — an accurate marker instead of
   a misattributing one, but still no dispatch. **The surface that newly reaches `cleanup-merged`
   is the Devin CLI / Devin Desktop local session that does not export `CLAUDE_PLUGIN_ROOT`**
   (classifier returns `local`), plus any workspace whose classifier returns `no-devin-env` while a
   populated `/opt/.devin/plugins` exists. That is the real blast radius #8400 has to cover, and
   the plan states it that way rather than repeating the cloud framing.

### Surface A — `cleanup-merged` (#8400)

- **The lease key is derivable from the branch name alone.** `_acquire_worktree_lease`'s header
  says `$1 branch name — this IS the lease key`, and all four create/feature call sites pass
  `"$safe_branch"` (`= _safe_worktree_name "$branch" = tr '/' '-'`). The `switch` call site passes
  `basename "$worktree_path"` and its own comment records that since #7408 the two are equal. The
  reap loop already computes `safe_branch` at the top of each iteration, so
  `is_lease_active "$safe_branch"` needs **no new machinery** — the `[[ -n "$worktree_path" ]] &&`
  conjunct at `:2868` is the only thing suppressing it. This is the single most important finding
  for #8400: the lease guard is not *inexpressible* for worktree-less branches, it is merely
  *unreached*.
- **The recent-commit grace guard has the same property.** `git log -1 --format=%ct HEAD` inside
  the worktree is replaceable by `git log -1 --format=%ct "refs/heads/$branch"` against the repo,
  which works with or without a worktree.
- **Two guards genuinely have no worktree-less analogue** and are correctly skipped: `:2851`
  (`$PWD` inside the worktree) and `:2905` (`git status --porcelain` of the worktree). A fix that
  claims to "extend all five" would be overstating; the plan says four→two→two explicitly.
- **`reset --hard HEAD` at `:2999` is the genuinely unrecoverable call**, and its own guard is
  ordered wrong. It fires when `${#cleaned[@]} -gt 0` and the non-bare `$GIT_ROOT` has a dirty
  index or worktree. The comment justifies it with "direct commits to main are prohibited
  (hook-enforced)" — but the `current_branch != main` check that would make that premise true runs
  **after** the reset, at `:3000-3003`. A non-bare checkout parked on a feature branch with
  uncommitted work is reset before anything verifies it is on main.
- **`gone_branches` is not a merged set.** It is built from `git for-each-ref … %(upstream:track)`
  filtered on `[gone]`, which means "the upstream ref disappeared", not "merged". `git branch -D`
  is a *force* delete that ignores merge status. This is a real fail-open, but it is **not
  worktree-specific** — a `[gone]`-unmerged branch with a worktree is exposed identically. Scoped
  out to its own issue rather than folded in (see *Cut List*).
- **CORRECTED (plan review, HIGH).** An earlier draft of this section claimed "no test drives the
  reap loop end-to-end today." **That was false**, and it was a universal negative asserted after
  checking two files — the exact class this repo's sharp-edges catalogue warns about.
  `plugins/soleur/skills/git-worktree/test/lease-protects-active.test.sh` is **1015 lines** that do
  exactly that: it synthesizes a bare fixture repo, merges `feat-victim` into `main`, adds
  worktrees, mints a real lease against a live PID, and invokes `bash "$WM" cleanup-merged`,
  asserting what survived. The premise check enumerated `worktree-manager-stale-lock-diag.test.sh`
  and `session-state.test.sh` T18a and missed the one suite whose *filename* is the subject.
  (`stale-lock-diag.test.sh:305` does invoke `cleanup-merged`, but only to assert it does not abort
  under `set -e` when `ensure_bare_config` wedges; it stages no branch. `session-state.test.sh:808`
  is an `awk` body-grep, a static check.)

- **And the consequence is a plan defect, not just a citation error.**
  `lease-protects-active.test.sh:181-186` pre-stamps the arming hold, with this comment:

  > "Pre-stamp the #7409 first-run arming hold. Every scenario below asserts what the reaper does
  > with a lease present or absent; the hold suppresses reaping **entirely** on a store's first
  > armed run, so without this stamp *"the victim survived"* would pass for the wrong reason in
  > every one of them."

  Measured: it is the **only** file in `plugins/soleur/` other than the script itself that mentions
  `reaper-armed`. The Phase 1 fixture spec originally never mentioned stamping it. Without the
  stamp, Test 3 (the must-PASS "it **is** reaped" control) **fails**, Tests 1-2 pass for the wrong
  reason, and **Guard 1 mutation rows 1 and 2 do not go RED** — which are the plan's entire proof
  that the lease widening works. Phase 1 step 1 now requires the stamp explicitly.

- **The arming hold is ONE-SHOT PER REPOSITORY, and must not be cited as ongoing coverage.**
  `_session_state_root()` resolves under `git rev-parse --git-common-dir`, and the stamp is written
  *before* the loop specifically so it cannot re-arm. It fires exactly once in a repository's
  lifetime. An earlier draft leaned on it three times as cover for the worktree-less residual; for
  every session after the first armed run it contributes nothing. **The residual is covered by the
  commit-age grace alone**, and the PR body must say so.
- **The harness the new test copies already exists.** `worktree-manager-safe-branch-sanitization.test.sh`
  is the closest sibling: it sources `test-helpers.sh` (which arms the git tripwire and provides
  `git_fixture_env <dir>`), clears every `GIT_*` env var, sets `TMPDIR=${TMPDIR:-/var/tmp}`,
  `source`s `worktree-manager.sh` inside a fixture repo in a subshell (the `BASH_SOURCE == $0`
  guard keeps `main()` from running), calls internal functions directly, and builds *mutant copies*
  of the script whose mutation is asserted to have landed via `diff` against a pristine copy.
  `worktree-manager-heal-stale-branch.test.sh:57-90` is the `gh` PATH-stub factory;
  `worktree-manager-porcelain-sigpipe.test.sh:92` is the `git` PATH-stub precedent — that is how
  `git push origin --delete` is captured without a real remote.
- **Dispatch sites for `cleanup-merged`:** `plugins/soleur/commands/go.md:243` (Step 0), the
  AGENTS.rules.md session-start gates `wg-at-session-start-run-bash-plugins-soleur` +
  `wg-at-session-start-after-cleanup-merged`, and `.claude/hooks/guardrails.sh:188` names it in a
  deny-message as the sanctioned alternative to `rm -rf`.

### Surface B — the three resolver fences (#8401)

- **`go-session-gates.test.sh` R9 actively asserts the confinement being lifted.** Its per-gate
  loop counts occurrences of `devin/cli/plugins/cache|/opt/\.devin/plugins` in each fence's
  comment-stripped code and branches: `cloud-detect` must have `>= 2`, **every other gate must have
  exactly `0`** ("Copying them into Step 0 would make the MUTATING gate newly reachable on a
  harness where it has always skipped"). This row is the mechanical expression of ADR-179 decision
  11 and it is the thing that goes red first. It must be rewritten as part of the change, not
  discovered at CI.
- **R8 pins byte-identity of the bytes between `# --- soleur plugin-root resolver` and
  `# --- end resolver ---`, across all three fences**, plus "the snippet holds
  `${CLAUDE_PLUGIN_ROOT}` exactly once" per gate. The Devin arms currently sit **after**
  `# --- end resolver ---` in the cloud-detect fence, which is precisely why byte-identity holds
  today with only one fence carrying them.
- **R5c is the row to copy** (`go-session-gates.test.sh:586-593`): it builds
  `$TMP_ROOT/home-devin/.local/share/devin/cli/plugins/cache/soleur-abc123` via `mk_root … soleur`,
  runs `run_gate "${FENCE_LITERAL[1]}" "$ws" "$CACHE_HOME"` and asserts
  `gate=cloud-detect source=devin-cache verified=true` plus `not-local:no-devin-env` (proving the
  real `cloud-detect.sh` ran from the cache root). The session-start analogue asserts
  `gate=session-start source=devin-cache verified=true` and `R1_EFFECT[2]`, which is the literal
  `STUB_WORKTREE_MANAGER argv=cleanup-merged` (`go-session-gates.test.sh:444`).
- **`mk_root` already stubs the manager and already documents this bug.** Its comment reads:
  "STUB, never the real manager: the real one reaches `git push origin --delete`, `git branch -D`
  and `reset --hard HEAD` for merged branches with no worktree." The test fixture knew; the script
  did not.
- **Only the `$HOME` cache arm is testable in-suite.** `/opt/.devin/plugins` is not writable in a
  fixture, so the second arm is covered by the static R9 occurrence count, not behaviourally. The
  plan says so rather than implying both arms are exercised.
- **ADR-179 A11 is a settled rejection, and R6b is its MUST-PASS witness.** A11 rejected asserting
  that the resolved root lies outside the working tree, on three grounds (it guards an unreachable
  operand; it breaks dogfooding on every plain clone where the plugin root *is* inside the tree;
  and it re-adds a CWD-resident trust decision that §R1 removed). Its stated consequence: "the
  identity preflight is **defence-in-depth**, not the load-bearing control." R6b
  (`go-session-gates.test.sh:605-610`) plants a decoy whose manifest claims `"name":"soleur"`,
  asserts the gate accepts it *and* that `decoy_ran` returns `DECOY_EXECUTED`, with the comment:
  "If this row ever fails, someone added a trust assertion the ADR declined — supersede A11 first."
  Nothing in this plan may weaken R6b or restate the preflight as authentication.

### Surface C — the `soleur-cloud-mode` block (#8402)

- **Current recipe (identical in all 67 copies), from `plugins/soleur/skills/work/SKILL.md:7`,
  which `devin-cloud-mode.test.ts` treats as canonical:**
  `resolve the script via `find /opt/.devin/plugins -name cloud-detect.sh | head -1``, and for the
  commit guard, "`precommit-guard.sh` (same plugin `scripts/` dir, same `find` recipe)". So one
  prose recipe governs the resolution of **two** executed scripts.
- **The drift guard is `plugins/soleur/test/devin-cloud-mode.test.ts` §"soleur-cloud-mode marker
  fleet"**, two tests: *every marked SKILL.md carries exactly one byte-identical block* (canonical
  = `skills/work/SKILL.md`, `markerBlock()` extracts with
  `/<!-- soleur-cloud-mode:start -->[\s\S]*?<!-- soleur-cloud-mode:end -->/`, asserts
  `expect(markerBlock(p)).toBe(canonical)` and `expect(marked.length).toBe(67)`), and *every FR4
  union member is marked* over a hand-listed `UNION` of 20 secrets/prod skills. **The guard pins
  that the copies agree with each other; nothing pins what they SAY.** A canonical block with the
  basename recipe passes at 67/67. That is the vacuity the new expectation closes.
- **There is no generator.** `grep -r 'soleur-cloud-mode' plugins/soleur/scripts/ scripts/` returns
  nothing; the test's own comment calls the block "a replicated literal". The sweep is a scripted
  in-place edit of 69 files, and the durable mechanism is the strengthened drift guard, not a new
  generator.
- **The full #8402 cohort — 70 occurrences, 69 files:**
  - 67 × marker block in `plugins/soleur/{skills,devin/skills}/*/SKILL.md` (prose recipe).
  - `plugins/soleur/skills/work/SKILL.md:758` — **an executable line, not prose**:
    `[ -f "$GUARD" ] || GUARD="$(find /opt/.devin/plugins -name precommit-guard.sh 2>/dev/null | head -1)"`
    followed by `bash "$GUARD" …`. This is the one site in the cohort that a shell actually runs,
    and it is invisible to a marker-block sweep because it sits in the skill body.
  - `plugins/soleur/devin/INSTRUCTIONS.md:113` — the prose recipe in the Devin harness contract,
    the document every other copy points at.
  - `plugins/soleur/AGENTS.md:311` — rule `[id: cloud-detect-before-pipeline]` in the plugin's
    always-loaded rules file. Verified **not** covered by the rule-body-weakening gate:
    `scripts/lint-rule-bodies.py` has `SIDECARS = ("AGENTS.rules.md",)` and neither
    `.claude/rule-body-hashes.txt` nor `scripts/migrated-rule-ids.txt` carries this id, so editing
    the body needs no WORM ack. `cq-rule-ids-are-immutable` still applies: the id does not change.

### Institutional learnings that bear on this change

- `2026-02-22-cleanup-merged-path-mismatch.md` — this exact function, the same failure shape: a
  guard that reads as protection while the path it keys on cannot match. The fix then was to stop
  *constructing* paths and read `git worktree list --porcelain`; the fix now is to stop *requiring*
  a path for a guard whose key is derivable from the branch.
- `2026-02-19-never-use-delete-branch-with-parallel-worktrees.md` — the documentation-vs-enforcement
  gap in the same subsystem: the written rule described a narrower guard than the hook enforced.
  #8400 is the mirror image (banner claims more than the code enforces), which is the worse
  direction.
- `2026-03-28-pretooluse-hook-guard-ordering-matters.md` — a guard placed after an early exit never
  fires. Directly applicable to the `reset --hard` / `current_branch != main` ordering defect.
- `2026-04-23-hostname-prefix-guard-and-strict-mode-pipefail.md` and
  `2026-03-03-set-euo-pipefail-upgrade-pitfalls.md` — `worktree-manager.sh` runs under
  `set -euo pipefail` and `cleanup_merged_worktrees` is invoked bare, so any new unguarded non-zero
  return aborts everything after it (the file's own comment at `:2708-2719` records this exact
  trap). Every new guard command needs `|| true` or an `if` wrapper.
- `2026-02-22-shell-expansion-codebase-wide-fix.md`, `2026-02-22-skill-count-propagation-locations.md`,
  `2026-02-22-command-substitution-in-plugin-markdown.md` — three independent records of the same
  class: a codebase-wide sweep planned from a memorised file list misses copies, and the pattern
  recurs where the initial grep scope was too narrow. This is why the #8402 cohort was measured
  with two different greps (marker presence *and* recipe literal) and why they disagree by 3.
- `2026-02-22-archiving-slug-extraction-must-match-branch-conventions.md` — a fix applied to one
  copy of duplicated logic and not the others reproduced the original bug. Applies to the
  `work/SKILL.md:758` executable line.

### CLAUDE.md / AGENTS.md conventions in force here

`hr-always-read-a-file-before-editing-it`; `hr-verify-repo-capability-claim-before-assert` (every
capability claim above cites the command that produced it); `cq-write-failing-tests-before`;
`cq-cite-content-anchor-not-line-number` and `cq-assert-anchor-not-bare-token` (the new test rows
assert on marker strings, and the sweep anchors on the marker comments, never on line numbers);
`cq-test-fixtures-synthesized-only`; `cq-rule-ids-are-immutable`; `hr-observability-layer-citation`
(this is layer 7 — a customer's own terminal is the only sink for a local plugin run);
`wg-when-deferring-a-capability-create-a` (the two scope-outs below each get an issue).

### Property List (Phase 0.6b)

| # | Property (observable outcome) |
|---|---|
| P1 | For a stale branch with **no** worktree, `cleanup-merged` applies the session-lease decision and the recent-commit grace decision before deleting any ref. |
| P2 | `git -C "$GIT_ROOT" reset --hard HEAD` cannot discard uncommitted work in a non-bare checkout that is not on `main`/`master`. |
| P3 | The `:81-84` warning block states a scope that matches what the code enforces (it names branches, not only worktrees). |
| P4 | A test drives a merged branch with no worktree through the reap loop and records which of the three destructive calls it reaches. |
| P5 | A session-start gate on a Devin CLI host with no `*_PLUGIN_ROOT` exported resolves a plugin root from the Devin cache, and the non-destructive session-start work (`git worktree list`, the `.mcp.json` restore) runs. |
| P10 | The session-start gate dispatches `cleanup-merged` **only** from a root whose reaper declares the branch-keyed-guard capability; a root without it produces a named skip, no dispatch, and **no loss of the non-destructive session-start work**. (Added at plan review: the capability gate was the plan's largest mechanism and had no property, so P5 as originally worded was contradicted by it.) |
| P6 | The three resolver copies in `go.md` remain one artifact (byte-identical between the anchors). |
| P7 | Every copy of the cloud-mode recipe selects the Devin plugin root by `plugin.json` identity, `[ -d ]`-gated, over both documented cache paths. |
| P8 | A drift guard fails if any copy reverts to basename selection, and fails if a copy is missed. |
| P9 | ADR-179 decision 11 describes the confinement as lifted and records why, and no document still asserts the identity preflight is authentication. |

### Cut List (Phase 0.6b — mechanisms removed before research)

| Mechanism proposed | Property it would buy | Why it is cut |
|---|---|---|
| A dry-run / "would reap" confirmation pass before the first destructive run | operator sees the first reap coming | Already on `origin/main`: the **ONE-TIME ARMING HOLD** (`worktree-manager.sh:2797-2836`) stamps `$(_session_state_root)/reaper-armed` and gives the first armed run a dry pass. Verified it is **not** worktree-path-gated, so it already covers worktree-less branches. |
| A new telemetry stream for reap decisions | reaps are observable | Already on `origin/main`: the `SOLEUR_WORKTREE_LEASE_LIB_OK` / `_MISSING` / `SOLEUR_WORKTREE_REAPER_ARMED` sentinel family, all on **stdout** because stderr is invisible under `claude --bg`. Extend that family; do not invent a sink. |
| A generator script that writes the `soleur-cloud-mode` block into the fleet | 69 copies stay in sync | The drift guard (`devin-cloud-mode.test.ts`) already buys sync. A generator adds a second source of truth and a generation-drift failure mode for a one-time edit. Sweep with a scripted in-place edit; strengthen the guard. |
| Re-verifying merged-ness (`git merge-base --is-ancestor`) before `git branch -D` | no force-delete of an unmerged `[gone]` ref | Real, but **not the property #8400 is about** — a `[gone]`-unmerged branch *with* a worktree is exposed identically, so this is a different cohort and a different guard. Scoped out with a filed issue rather than folded in. |
| Moving the Devin cache arms into the shared resolver with no further gate (the brief's #8401 mechanism) | Step 0 resolves on a Devin host | **Cut on an ADR, not on cost.** ADR-179 §"Why arm 3 is confined to Step 0.5" names this mechanism and forbids it, on a second ground #8400 does not close: the dispatched `worktree-manager.sh` is a cached copy of unknown age. Replaced by a capability feature-detect on the dispatch (Phase 2), which addresses the ground. This is the Phase 0.6 item-4 class — the brief proposed the exact mechanism an ADR had already rejected by name. |
| A "trust the Devin cache root" authentication mechanism | the executed script is genuinely ours | **ADR-179 A11 rejected this**, and `go-session-gates.test.sh` R6b is a MUST-PASS row pinning the rejection. The identity preflight stays a shape check. Reversing it means superseding A11 first. |

### Value-Proposition Measurement (Phase 0.6c)

Not applicable: no phase of this plan is justified by a cost or performance saving. The
justifications are correctness (P1–P4), reachability (P5) and consistency/defence-in-depth (P7–P8).
Recorded explicitly so the absence is a finding rather than an omission.

### Open Code-Review Overlap

**None.** `gh issue list --label code-review --state open --json number,title,body --limit 200`
returned 65 issues; each planned path was tested with `jq --arg path … contains($path)` and none
matched. **Non-vacuity control:** the same query over the substrings `worktree` (2 hits — #7208,
#2349), `plugins/soleur` (7 hits) and `cloud` (1 hit) returns results, so the zero is a real zero
rather than a broken filter. Nearest neighbours, both non-overlapping: #7942 (two `*.mutation.sh`
batteries under `plugins/soleur/test/` run in no gate — relevant if this plan adds a mutation
battery; it does not, it adds mutant *arms inside* a `.test.sh`, the
`safe-branch-sanitization.test.sh` pattern, which the aggregator does run) and #4133 (observability
schema parity test).

> **Lane note (TR2 fail-closed).** No `spec.md` exists for this branch yet, so no `lane:` could be
> carried forward and the frontmatter defaults to `cross-domain`. The `## Domain Review` sweep found
> only Engineering relevant, i.e. the *measured* lane is `single-domain`; the fail-closed default is
> recorded rather than overridden, and it only widens the Phase 2.5 fan-out, which already ran.

## Problem Statement

Three defects sit on one dependency chain, which is why they ship together.

**#8400 — a fail-closed banner over a guard set that does not cover the case.** `cleanup-merged` is
the only destructive operation Soleur runs unattended, at session start, usually under
`claude --bg` where stderr is invisible. ADR-178 §Context calls it unrecoverable. Its stale-branch
set is a union of three detectors, two of which (`git branch --merged main`, `[gone]` upstreams)
routinely contain branches with no worktree — a worktree removed by hand, a branch created and
merged from a plain clone, a worktree reaped on an earlier pass whose branch survived. For every
one of those branches, all five safety guards short-circuit on `[[ -n "$worktree_path" ]]` and the
loop proceeds to delete the remote ref (closing the PR), force-delete the local ref, and — if the
main checkout is dirty — `reset --hard HEAD` over it. Meanwhile `:82` tells the operator cleanup
"will REFUSE to reap any worktree (fail-closed)". The gap was found while writing a plan, not by a
test, and the fixture in `go-session-gates.test.sh` `mk_root` already documents it in a comment:
"STUB, never the real manager: the real one reaches `git push origin --delete`, `git branch -D` and
`reset --hard HEAD` for merged branches with no worktree."

**#8401 — a session-start gate that cannot resolve itself on a whole harness.** `go.md` Step 0
resolves the plugin root from two arms (the loader-substituted `${CLAUDE_PLUGIN_ROOT}` token, then
`GROK_PLUGIN_ROOT`). On a Devin host where neither is exported it emits
`SOLEUR_SESSION_START_SKIPPED reason=plugin-root-unverified` and every session-start gate — the
reaper, `git worktree list`, the `.mcp.json` restore — silently does not run. The two Devin cache
arms that would resolve it already exist and are measured working; they are confined to Step 0.5
because Step 0 dispatches the operation #8400 describes. The confinement is not an oversight, it is
a load-bearing decision recorded in ADR-179 decision 11 and mechanically enforced by
`go-session-gates.test.sh` R9. Lifting it requires fixing #8400 first, in the same change, or the
widening hands a newly-reachable destructive operation to a harness that has never run it.

**#8402 — an executed path selected by filename.** The `soleur-cloud-mode` contract tells every
skill in the fleet to locate `cloud-detect.sh` and `precommit-guard.sh` under the Devin plugin
cache with `find /opt/.devin/plugins -name <script> | head -1` — first match by basename wins, and
the block then runs it. `go.md`'s Step 0.5 arm selects the same cache by identity
(`.claude-plugin/plugin.json` containing `"name":"soleur"`), `[ -d ]`-gated so a non-Devin box
searches nothing. The entry point is strictly stricter than the 69 files that resemble it. This is
a consistency and defence-in-depth gap, and ADR-179 A11 is explicit that the identity preflight is
a **shape check, not authentication** — a planted directory containing `{"name":"soleur"}` passes,
and `go-session-gates.test.sh` R6b is a MUST-PASS row asserting exactly that. Nothing in this
change may be described as stopping an attacker.

## Proposed Solution

Fix the reap scope first, then lift the confinement it was gating, then bring the fleet's recipe in
line with the entry point's — one PR, in that order, because the second is unsafe without the first
and the third is the cohort audit the second's recipe implies.

## Technical Approach

### Architecture

Nothing structural moves. Three existing mechanisms are corrected in place:

1. **`cleanup_merged_worktrees`'s guard set** stops keying on a worktree path for the two
   decisions whose key is derivable from the branch, and the main-checkout update stops running
   before it has established that the checkout is on `main`.
2. **The `go.md` resolver** absorbs the Devin cache arms into the bytes the R8 byte-identity pin
   already covers, so the three gates stay one artifact rather than becoming three variants.
3. **The `soleur-cloud-mode` recipe** becomes one recipe, and its drift guard starts pinning what
   the copies *say*, not only that they agree.

No new persistent store and no new cross-component connection, so Phase 2.11's Encryption Posture
gate does not fire — recorded here so the absence is an assessment rather than an omission.

### Implementation Phases

#### Phase 1: #8400 — make the reap guards reachable for worktree-less branches

All edits in `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh`. Anchor on content,
never on the line numbers quoted above.

1. **Write the failing suite first** (`cq-write-failing-tests-before`):
   `plugins/soleur/test/worktree-manager-cleanup-merged-no-worktree.test.sh`, modelled on
   `worktree-manager-safe-branch-sanitization.test.sh`. Clear every `GIT_*` env var, source
   `test-helpers.sh`, set `TMPDIR="${TMPDIR:-/var/tmp}"`, build a synthesized fixture repo
   (`cq-test-fixtures-synthesized-only`) with a branch merged into `main` and **no** worktree, and
   PATH-stub `git` and `gh` so `push origin --delete` and `branch -D` are *recorded* rather than
   executed (the `git` stub pattern is `worktree-manager-porcelain-sigpipe.test.sh`, the `gh` stub
   factory is `worktree-manager-heal-stale-branch.test.sh`). Drive the case through
   `cleanup_merged_worktrees` in a subshell and assert **which** of the three destructive calls it
   reaches — this is #8400's ask 2 and it is a characterization assertion, red before the fix.
2. **Lease guard — drop the path conjunct.** The check becomes one that always evaluates
   `is_lease_active "$safe_branch"` and, when a worktree path exists whose basename differs from
   `$safe_branch` (a legacy pre-#7408 layout), evaluates that key too, holding the branch if
   **either** reports active. Write the second key **inside** the `if` condition guarded on
   `[[ -n "$worktree_path" ]]`: `basename ""` yields an empty key and `_lease_file ""` is harmless
   today but is not a contract. Fail-closed by construction: with no lease library the stub returns
   0 for every key, so nothing is reaped. Keep the existing `_SS_LIB_MISSING` two-message split so
   the "lease library missing, refusing to reap" line still distinguishes the stub from a real
   lease.

   **State this as a behaviour change, not a side effect.** Dropping the path conjunct makes the
   `_SS_LIB_MISSING` stub (`is_lease_active() { return 0; }`) apply to *every* stale branch rather
   than only worktree-bearing ones. On a machine missing `session-state.sh`, branch cleanup now
   stops entirely and refs accumulate indefinitely. That is the intended fail-closed semantics and
   it is what makes the reworded banner true — but it is a real regression in cleanup throughput on
   a torn install and belongs in the PR body, not in a footnote. The per-branch
   `(skip) $branch - lease library missing, refusing to reap (fail-closed)` line is what keeps it
   visible.

   **What this arm actually covers, stated precisely, because "the guard now applies" is not the
   same claim as "the case is now guarded".** Every lease is minted by `create`, `create-for-feature`
   or `switch`, and all three have a worktree. So the state this arm newly protects is exactly
   *"a lease outlived its worktree"* — a hand-removed worktree, a crashed session, a `git worktree
   remove` that did not delete the branch — held until the lease window expires or
   `sweep_orphan_leases` reaps it. **It does NOT protect a session working on a merged or `[gone]`
   branch inside a plain clone, because nothing in that flow mints a lease at all.** That case is
   covered only by step 3's ten-minute commit-age grace and by the one-time arming hold. The
   residual is therefore: *a live plain-clone session, on a merged or `[gone]` branch, with no
   lease and no commit in the last ten minutes, is still reapable.* It is bounded — for a merged
   branch the commits are on `main`, for a `[gone]` branch the local ref is reflog-recoverable, and
   the remote delete is gated on the remote ref still existing — but it is real, and the PR body
   says so rather than claiming the class is closed.

   **Known, bounded false-HOLDs, in the safe direction.** `_safe_worktree_name` is `tr '/' '-'`, so
   `feat/x` and `feat-x` collapse to one lease key and a live worktree on one holds the other —
   bounded by the lease window and reaped on a later pass. A within-window lease whose worktree was
   removed by hand also holds its branch for up to that window, because `sweep_orphan_leases` only
   deletes leases *past* their own window. Both are "not deleted this pass", which is the direction
   `is_lease_active`'s own comment asks for.
3. **Recent-commit grace — add the worktree-less arm.** When `-n "$worktree_path" && -d
   "$worktree_path"`, keep today's `git -C "$worktree_path" log -1 --format=%ct HEAD` read exactly
   as it is (no behaviour change for branches that have a worktree). When there is no worktree,
   read `git log -1 --format=%ct "refs/heads/$branch"` from the repo and apply the same
   `<600s || negative` clock-skew predicate. Print a distinct `(skip)` reason so the two arms are
   distinguishable in a terminal.

   **Do not describe this as a symmetric analogue of the worktree grace — it is not measuring the
   same thing.** The worktree arm measures *operator activity* (a commit made in the worktree the
   operator is sitting in). The ref arm measures *commit recency of a merged ref*. For a
   squash-merged branch — the cohort `gh_merged_branches` exists for — the branch tip is the last
   feature commit, frequently minutes old at merge time, so this arm will hold essentially every
   freshly squash-merged branch for ten minutes on the first pass and reap it on the next. That is
   cheap and fails in the right direction, and it is worth keeping, but the property it buys on
   that cohort is small. On the `git branch --merged main` cohort (tip is an old ancestor) it
   passes through with no effect.
4. **Main-checkout update — establish the precondition before the destructive call.** The reset is
   today guarded by the dirty check, i.e. it fires *only* in the destructive case, and the
   `current_branch != main` test that would justify its "direct commits to main are prohibited"
   premise runs after it. Hoisting the test is necessary but not sufficient: `git checkout main`
   with a dirty tree **refuses**, so "check, then check out main, then reset" still leaves a dirty
   feature branch being reset. The correct shape is three ordered steps:
   1. read `current_branch` with `|| true`;
   2. if it is **empty or** not `main`/`master`, skip the reset, the checkout **and** the pull
      entirely, and say so on **stdout** (stderr is invisible under `claude --bg` — the file's
      own comment beside the `LEASE_LIB_MISSING` emit). **Superseded 2026-09-20 (#8400):** `SOLEUR_WORKTREE_MAIN_UPDATE_SKIPPED` was demoted during implementation per challenge B5 below and never shipped. What ships is two plain stdout lines — `Skipped stale-index reset: checkout is on '<b>', not main/master` and `Skipped main checkout: uncommitted changes on '<b>' (switching would carry them onto main)`. Read every mention of the marker in this plan as naming those lines. Also note the premise in
      the paragraph above is measured FALSE: `git checkout main` with a dirty tree does NOT
      always refuse — it succeeds whenever the dirty paths would not be overwritten, which is
      the ordinary case of editing a file that also exists on main, and it then carries the edit
      onto `main` for the next session's reset to destroy. The tree state is read once and gates
      both the reset and the checkout. Empty is an unmeasured state and fails closed with the rest, per
      the AP-021 discipline the cloud-detect fence already cites;
   3. only on a confirmed `main`/`master` do the dirty check and the reset.

   This is an anomalous state, so unlike the per-branch `(skip)` lines it earns a sentinel.

   **Scope:** this whole block is the `IS_BARE=false` arm. In a bare layout — which is this repo's
   own and the one `create` produces — the reset never runs at all; the bare arm updates
   `refs/heads/main` by fetch/`update-ref` and calls `sync_bare_files`. So the change affects plain
   clones only.

   **The defence being narrowed has a side-effect role, named per the defence-relaxation rule.**
   The block's stated purpose is "after cleanup, update main checkout so next worktree branches
   from latest"; skipping it when the checkout is parked off `main` drops that freshness pull for
   that run, so a subsequent `create` in a non-bare clone may branch from a stale local `main`
   until a later run finds the checkout on `main`. That is the accepted cost: a stale base is
   recoverable by a rebase, discarded uncommitted work is not.

   **The `reset --hard` is kept, and the PR body says why rather than leaving it implicit.** Its
   premise — "direct commits to main are prohibited, so a dirty index here is stale debris" — is
   true once the gate above establishes the checkout is on `main`. Deleting the reset instead would
   leave the subsequent `pull --ff-only` failing on index drift, which is the condition it was
   added for. Reordering makes the premise true; it does not make the step gratuitous.

5. **Plant the reaper capability token** that Phase 2 step 2 feature-detects: a literal
   `SOLEUR_WORKTREE_REAP_CAPABILITY=branch-keyed-guards-v1` in the script, echoed on stdout at load
   beside `SOLEUR_WORKTREE_LEASE_LIB_OK`. It names the capability this phase adds, not a version.
6. **Banner.** After step 2 the `:82-83` claim becomes true *by extension* rather than needing to
   be narrowed: with no lease library every branch — worktree or not — reads as held. Reword it to
   say so ("will REFUSE to reap any worktree **or delete any branch**") so the text states the
   scope the code now enforces. Both of #8400's alternatives are satisfied by one change; the plan
   does not pick one over the other.
7. **`set -euo pipefail` discipline — six named abort sites.** `worktree-manager.sh` sets
   `-euo pipefail` at the top and `cleanup_merged_worktrees` is invoked **bare**, so an uncaught
   non-zero does not merely return: it exits the script, skipping `cleanup_orphan_worktree_dirs`,
   `cleanup_claude_tmp`, the runaway-process kill and the summary. The function's own header
   already records this for `sweep_orphan_leases`. Each new construct is written as follows:
   1. the `git log -1 --format=%ct "refs/heads/$branch"` read — a ref that vanished between the
      `all_stale_branches` snapshot and the read exits 128. Mirror the existing idiom exactly:
      `local last_commit_age` on its own line, then `last_commit_age=$(… 2>/dev/null || true)`. A
      bare `local x=$(cmd)` masks the status only because `local`'s own status wins; do not rely on
      that;
   2. no new `(( … ))` as a bare statement — an expression evaluating to 0 returns rc 1. The
      existing `(( _delta < 0 || _delta < 600 ))` is safe only because it sits inside an `if`, and
      the file's own comment records that this safety is positional, not intrinsic;
   3. never `is_lease_active … && { …; continue; }` — `set -e` exempts non-final members of an
      `&&` list, not the list itself, so a false predicate makes the whole statement rc 1 and
      aborts. Use `if`;
   4. the hoisted `current_branch=$(git … rev-parse --abbrev-ref HEAD)` needs `|| true`: a detached
      or corrupt HEAD exits non-zero, and after the hoist that abort lands *before* the reset,
      taking out the orphan-dir and tmp reapers on a state that previously survived;
   5. keep `git ls-remote --exit-code` inside its `if`; any new guard inserted between it and the
      delete stays inside a condition;
   6. the new suite inherits the options when it sources the script — copy
      `worktree-manager-safe-branch-sanitization.test.sh`'s harness verbatim rather than
      re-deriving it, and include at least one mutant that **aborts** rather than mis-reaps, or the
      suite cannot see classes 1 and 4.

#### Phase 2: #8401 — make Step 0 resolvable on Devin, and capability-gate what it dispatches

**This phase was redesigned after reading ADR-179 §"Why arm 3 is confined to Step 0.5". The
mechanism the brief proposed — move the cache arms into the shared resolver — is named and
forbidden there:**

> "#8401 must NOT be resolved by moving the cache arms into the shared resolver: measured on an
> ordinary LOCAL box — where `cloud-detect.sh` returns `not-local:no-devin-env`, so the
> session-class gate passes — that makes Step 0 dispatch `cleanup-merged` out of a stale
> `0.0.0-unversioned` Devin cache selected by `find … | head -1`."

The confinement rests on **two** grounds, and #8400 closes only one of them:

| Ground | Closed by Phase 1? |
|---|---|
| A worktree-less merged branch skips every per-branch guard | **Yes** |
| Arm 3 resolves a **cached copy** of `worktree-manager.sh`, version unknown, chosen by `head -1` among possibly several | **No** — Phase 1 edits the repo's script; the cache holds a different file on disk, of unbounded age |

Phase 1 lands in the repository. The artifact arm 3 executes is not that file. So
"#8400 fixed ⇒ #8401 safe" breaks at the artifact boundary, and an `R5c`-analogue row would not
catch it: `mk_root` builds the fixture cache by copying `$PAYLOAD`, so the fixture is always
in-sync and **structurally cannot exhibit staleness**. A green row there is vacuous on the property
that matters. ADR-179 also names two guards outside #8400's list that Phase 1 does not touch: the
one-time arming hold (which is not per-branch and already covers this class) and
`cleanup_orphan_worktree_dirs`, which runs after the loop regardless and reaches
`rm -rf --one-file-system` at `worktree-manager.sh:2590`.

**The design that addresses the ground rather than ignoring it: feature-detect the reaper's
capability before dispatching it.** "Feature-detect, never sniff" is the repo's own doctrine for
this surface (the Devin cloud-parity brainstorm's D3, and the reason `cloud-detect.sh` is
sentinel-based rather than env-based).

1. **Phase 1 plants a capability token in the shipped script.** `worktree-manager.sh` gains a
   literal `SOLEUR_WORKTREE_REAP_CAPABILITY=branch-keyed-guards-v1`, emitted on **stdout** at load
   beside `SOLEUR_WORKTREE_LEASE_LIB_OK` so it is observable at runtime, and present as a literal
   so it is greppable statically. The token names the *capability* (per-branch guards keyed on the
   branch rather than on a worktree path), not a version.
2. **Step 0 gates its dispatch on that token.** Inside the existing `[ -f "${ROOT}/skills/…/worktree-manager.sh" ]`
   check — kept nested rather than conjoined, because `#7474` requires the presence check and the
   invocation to share a subprocess and `plugin-root-anchoring.test.ts` P6 anchors on a `[ -f` at
   statement start — a `grep -q` for the token decides between dispatching and emitting
   `SOLEUR_SESSION_START_SKIPPED reason=reaper-capability-unverified`. A cache copy that predates
   Phase 1 is refused, by name, instead of run. **Superseded by blocking correction B1 below:**
   this paragraph argued the gate should be arm-agnostic, "which is strictly more than the
   confinement ever did". The panel MEASURED that blast radius — the arm-agnostic form stops
   reaping for every long-lived worktree in this repository on a pre-merge branch and every
   marketplace install between releases, because their `worktree-manager.sh` predates Phase 1
   too. What ships is `[ "$VERIFIED" = true ] && [ "$SRC" = devin-cache ]`, with
   `REAP_CAP=not-applicable` initialised above it so the other arms are untouched. That closes
   ADR-179's ground exactly and no more.

   **Path pinning is part of the design, not an implementation detail.** The `grep -q` and the
   `bash` invocation MUST operate on the same `${ROOT}`-derived path, resolved once by the
   resolver, with **no `find` re-run between them**. A check that re-resolves is check-A /
   execute-B across two independent `head -1` calls, which is the defect one level down from the
   one this gate closes. Mutation row 10 in Guard 2 drives exactly that.

   **The token attests a contract; it does not authenticate.** Wording throughout the code
   comments, the ADR amendment and the PR body is "attests that this root's reaper carries the
   branch-keyed guards", never "verifies" or "trusts". A planted root can declare the token as
   trivially as it can declare `{"name":"soleur"}` — which is the A11 position, one level down,
   and is why item 5's R6b change below is a restatement of A11 rather than a weakening of it.
3. **Only then move the Devin cache arms inside the resolver anchors**, replicated byte-identically
   into all three fences. With step 2 in place the consequence ADR-179 cites no longer follows for
   the mutating gate.

   **But ADR-179's second ground is a property of the ARM, not of the reaper, and the arm is now in
   three fences — so the amendment must enumerate what each gate executes from a possibly-stale
   cache, not just the one this plan gates.** The enumeration:

   | Gate | What it executes from the resolved root | Disposition |
   |---|---|---|
   | `session-start` | `worktree-manager.sh cleanup-merged` — mutating, unrecoverable | **Gated** by the capability token (step 2) |
   | `cloud-detect` | `scripts/cloud-detect.sh` — read-only classifier, one `bash` exec, no `git` mutation | **Already dispositioned** by ADR-179 ("It is not zero … One `bash` exec, no `git` mutation"). Unchanged by this plan |
   | `readiness` | `skills/git-worktree/scripts/git-repo-readiness-diag.sh` — read-only probe, emits `SOLEUR_GIT_REPO_DIAG` | **Newly exposed by this change** and tolerated on the same reasoning as `cloud-detect`: read-only, one exec, no `git` mutation, and the fallback arm it replaces already ran bare `git rev-parse` calls. The amendment records this as a *new* acceptance, not an inherited one |

   Stating it this way is the point: the plan closes the ground for one consumer and relocates the
   arm for three, so the two it does not gate are named and justified rather than silently carried.
4. **Amend ADR-179 decision 11 in this same PR** (Phase 2.10 — the ADR is a deliverable, never a
   follow-up). The amendment supersedes the blanket "must NOT" with the narrower rule it was
   standing in for: *Step 0 may resolve from any arm; it may dispatch `cleanup-merged` only from a
   root whose reaper carries the guard capability.* It records both original grounds, which closed
   each one, and that the residual (`cleanup_orphan_worktree_dirs` → `rm -rf --one-file-system`) is
   now behind the same capability gate because the gate covers the whole dispatch, not just the
   reap loop. An ADR that says "must NOT" cannot be contradicted by a PR that does not amend it.
5. **Test rows in `go-session-gates.test.sh`:**
   - **R11 (the load-bearing new row):** a verified root whose `worktree-manager.sh` **lacks** the
     capability token → assert `SOLEUR_SESSION_START_SKIPPED reason=reaper-capability-unverified`
     and `want_not_in "$out" "STUB_WORKTREE_MANAGER"`. This is the row that proves the gate; without
     it the capability check is decoration.
   - **R5d:** session-start resolves from the Devin CLI cache → `gate=session-start
     source=devin-cache verified=true` **and** `${R1_EFFECT[2]}`. Requires `mk_root` to plant the
     capability token in its stub manager — a harness change, recorded here so it is not discovered
     at run time.
   - **R5e:** the readiness analogue, `gate=readiness source=devin-cache verified=true` plus
     `${R1_EFFECT[0]}`.
   - **R9:** the per-gate cache-path predicate flips from `cloud-detect >= 2, others == 0` to
     `>= 2` for all three, keeping the occurrence-count idiom (both paths sit on one `for d in …`
     line, so a *line* count reports 1 for a correct fence — the row's own comment records that
     trap).
   - **`mk_decoy_root` must plant the capability token in its decoy `worktree-manager.sh`, or
     R6b goes RED.** Verified: `mk_decoy_root` writes a decoy at
     `<root>/skills/git-worktree/scripts/worktree-manager.sh` that echoes `DECOY_EXECUTED`, and
     R6b asserts `decoy_ran()` returns `DECOY_EXECUTED` for **all three** gates — including
     `session-start`. With the capability gate and a token-less decoy, session-start would refuse
     to dispatch and R6b would fail. **The fix is to plant the token in the decoy, and that is a
     restatement of A11, not a weakening of it:** the token is a declaration a planted root can
     make as easily as `{"name":"soleur"}`, so a decoy that carries it is exactly the limitation
     R6b exists to document. Do NOT "fix" a red R6b by relaxing the gate.
   - Coverage limit, stated rather than implied: only the
     `$HOME/.local/share/devin/cli/plugins/cache` arm is exercisable in a fixture.
     `/opt/.devin/plugins` is not writable under test and is covered by R9's static occurrence
     count alone. The resolver's `head -1` among several identity-matching manifests is
     nondeterministic by construction; the capability gate is what makes a wrong pick fail closed
     rather than run, and that is the property to state — not that the pick is correct.
6. **Out of scope, named:** Step 0.5 still *executes* `cloud-detect.sh` from a possibly-stale cache
   root. ADR-179 already dispositioned that ("one `bash` exec, no `git` mutation") and this plan
   does not reopen it.

#### Phase 3: #8402 — one recipe across the cohort

**Commit order is load-bearing: the guard is strengthened BEFORE the sweep, in its own commit.**
`devin-cloud-mode.test.ts` today pins *agreement* and *cardinality*, never *content* — a sweep that
replaces all 67 blocks with something wrong-but-uniform stays green. Sweeping first makes 69 files
of near-identical diff unreviewable behind a guard that cannot tell right from wrong; strengthening
first makes the sweep mechanically verifiable.

1. **Commit 1 — strengthen the drift guard** (`plugins/soleur/test/devin-cloud-mode.test.ts`), red
   against the current tree:
   - positive: the canonical block contains both cache paths, the `.claude-plugin/plugin.json` path
     predicate and `'"name"[[:space:]]*:[[:space:]]*"soleur"'`, and is `[ -d ]`-gated;
   - negative, over a **derived** population: no file under `plugins/soleur/` contains
     `-name cloud-detect.sh` or `-name precommit-guard.sh`. The population is derived at test time
     by scanning for `/opt/\.devin/plugins` and `devin/cli/plugins/cache`, not from a member list —
     this is what reaches the three sites the marker-block test structurally cannot see;
   - **the exemption mechanism, designed now rather than retrofitted after 69 files are edited.**
     A scan over every file under `plugins/soleur/` for the basename recipe necessarily hits the
     one file that must *quote* it: this guard itself, whose detector pattern contains the literal.
     Without an exemption the guard false-fails on its own body — the "absence-grep over a scope
     that legitimately documents the forbidden token" trap. The design: **exactly one allowlisted
     path, `plugins/soleur/test/devin-cloud-mode.test.ts`, with an assertion that the allowlist has
     exactly one entry**, so it cannot grow silently into the hole the guard exists to close. The
     planted positive is synthesized into a temp directory and never committed, so it needs no
     exemption. Nothing under `knowledge-base/` needs one either — the scan is scoped to
     `plugins/soleur/`, and the plan, the ADR and the learnings that quote the old recipe all live
     outside it;
   - **match the SHAPE, not one literal.** The property is "selects a Devin-cache executable by
     filename", and `-name cloud-detect.sh` is one spelling of it. The detector matches a `find`
     under a Devin cache path selecting by `-name`/`-iname` on any script basename, so
     `-name 'cloud-detect*'`, `-iname`, or a third script name is caught too. A literal-only scan
     is a universal negative over one member of a set of mechanisms;
   - non-vacuity: the derived population is non-empty and at least as large as the known
     non-marker site count, and a synthesized temp file carrying the basename recipe is run through
     the same detector helper and must be reported as a violation (a detector that reports nothing
     on a planted positive reds the suite);
   - keep `expect(marked.length).toBe(67)` and **pair it with set identity** — assert the sorted
     list of marked paths, not only its length, so an add-one-delete-one diff cannot satisfy the
     floor.
2. **Commit 2 — author the new canonical block** in `plugins/soleur/skills/work/SKILL.md`, which is
   what the test reads as canonical. `[ -d ]`-gated, identity-selected over both documented cache
   paths, deriving the root as `${MANIFEST%/.claude-plugin/plugin.json}` and naming **both**
   scripts relative to it (`scripts/cloud-detect.sh`, `scripts/precommit-guard.sh`) — one
   resolution, two consumers, which is what the current "same `find` recipe" phrasing was gesturing
   at. Carry a one-clause scope note that the identity check is a shape check, not authentication
   (ADR-179 A11). `${CLAUDE_PLUGIN_ROOT}` stays braced and is legitimate here: ADR-179 A10 measured
   the loader substituting the braced token on the skill surface too.
3. **Commit 2 — sweep all 67 marker blocks** with a scripted in-place replacement anchored on the
   `<!-- soleur-cloud-mode:start -->` / `:end` comments, never on line numbers, so every copy moves
   in the same commit (a partial sweep reds the byte-identity test, which is that guard working as
   intended).
4. **Commit 2 — the three non-marker sites, each with its own treatment.** A uniform
   string-substitution across these is wrong; they differ in kind:

   | Site | Treatment |
   |---|---|
   | `plugins/soleur/skills/work/SKILL.md:758` — the **executable** `GUARD="$(find … -name precommit-guard.sh …)"` line | Key the identity predicate on `.claude-plugin/plugin.json` naming `soleur` and then **append** `/scripts/precommit-guard.sh`, never on the script's basename. **And fix the fail-open on the next line while editing it:** `[ -n "$GUARD" ] && bash "$GUARD" …` is followed by an unconditional `git commit`, so an unresolved guard silently proceeds to commit — the opposite of what a commit-on-main backstop should do in the one session type where it is load-bearing. Emit `SOLEUR_PRECOMMIT_GUARD_UNRESOLVED` on the empty arm so the silence becomes visible. Whether it should *refuse* rather than warn is a separate behaviour decision and is filed, not decided here. |
   | `plugins/soleur/devin/INSTRUCTIONS.md:113` | **Rewrite the paragraph, do not substitute the string.** The sentence explains *why* (“the managed plugin cache; the lock file is `/opt/.devin/plugins/lock.json`”) and a pasted shell recipe breaks the prose. The directory reference itself stays — naming the directory is permitted, selecting by basename is not. |
   | `plugins/soleur/AGENTS.md:311`, rule `[id: cloud-detect-before-pipeline]` | **A pointer, not the recipe.** This is a single-line rule body in the customer-shipped always-loaded rules file; a multi-line identity-selected recipe cannot live on one line legibly. Point to `devin/INSTRUCTIONS.md` §Detection and let the recipe live there. The id is immutable (`cq-rule-ids-are-immutable`); verified not covered by `scripts/lint-rule-bodies.py` (`SIDECARS = ("AGENTS.rules.md",)`), so no WORM ack is owed. |

5. **What goes red, measured.** The byte-identity test reds on any partial marker sweep — that one
   is working as intended. Nothing gates the other three sites today: `devin-harness.test.ts`,
   `devin-plugin.test.ts` and `harness.test.ts` pin no `find` literal, and
   `apps/web-platform/test/plugin-root-anchoring.test.ts`'s
   `GATE_SCRIPT_RE = /^(?:redact-.+\.(?:sh|py)|digest-scrub\.sh|playwright-mcp-redact-proxy\.py)$/`
   does not match `precommit-guard.sh`, so the anchoring suite's skills axis never sees that
   executable line — unguarded before, and guarded after only by commit 1's derived scan. That gap
   is why commit 1 exists.
6. **R6b is not at risk.** The sweep *adds* the same shape check R6b documents the limits of, where
   there was none. It moves the fleet toward R6b's semantics, not away, and nothing here promotes
   the identity check to authentication. A11 stands untouched.

#### Phase 4: records, gates and scope-outs

1. Amend **ADR-179 decision 11** (Phase 2 step 4). The ordinal is an amendment to an existing ADR,
   so no new ordinal is claimed and the collision gate has nothing to catch.
2. Update the **`devin -> platform.plugin` C4 edge** description — see
   `## Architecture Decision (ADR/C4)` — and run
   `bash plugins/soleur/test/c4-count-parity.test.sh` plus
   `apps/web-platform/test/c4-code-syntax.test.ts` and `c4-render.test.ts`.
3. File the scope-outs (`wg-when-deferring-a-capability-create-a`), each with what was deferred,
   why, and its re-evaluation criterion:
   - **`[gone]` is not `merged`, and `git branch -D` is a force delete.** An unmerged branch whose
     upstream was deleted is force-deleted by `cleanup-merged`. Not worktree-specific — equally
     true with a worktree — so it is a different cohort and a different guard. Re-evaluate when the
     branch-deletion path is next touched.
   - **`cleanup_orphan_worktree_dirs` reaches `rm -rf --one-file-system` after the loop,
     unconditionally.** ADR-179 names it as one of the two non-per-branch guards outside #8400's
     list. Phase 2's capability gate keeps a stale reaper from running it at all, but within a
     current reaper it is still ungated by anything per-branch. Re-evaluate with the orphan-dir
     reaper's own contract.
   - **`precommit-guard.sh` is outside `GATE_SCRIPT_RE`** in
     `apps/web-platform/test/plugin-root-anchoring.test.ts`, so its resolution is unguarded by the
     anchoring suite's skills axis. Phase 3 commit 1's derived scan covers the *recipe*; the
     anchoring contract is a separate mechanism. Re-evaluate when that suite's gate-script set is
     next widened.
   - **Should the commit-on-main backstop REFUSE when unresolved, rather than warn?** Phase 3 makes
     the silence visible; whether an unresolved guard should block `git commit` outright is a
     behaviour decision with its own blast radius on non-Devin sessions.

## Alternative Approaches Considered

| Approach | Verdict |
|---|---|
| **#8400: reword the `:82` banner only, leave the guards as they are** (the issue's second option) | **Rejected.** It makes the documentation honest and leaves an unattended, unrecoverable operation running with no applicable guard on a branch class that occurs routinely. It is also strictly more work than the fix: the lease key is already `$safe_branch`, so the guard costs one conjunct. |
| **#8400: skip worktree-less branches entirely** | **Rejected.** Fail-closed but it strands `[gone]` and merged refs in the bare repo forever, and `cleanup-merged`'s ref hygiene is a real function. Extending the guards preserves the function and the safety. |
| **#8400: re-verify merged-ness before `git branch -D`** | **Scoped out** to its own issue. Real (`[gone]` ≠ merged and `-D` is a force delete) but not worktree-specific, so it is a different cohort and a different guard. Folding it in would make this PR's guard contract quantify over two unrelated properties. |
| **#8401: move the cache arms into the shared resolver and stop there** (the brief's mechanism) | **Rejected — named and forbidden by ADR-179 §"Why arm 3 is confined to Step 0.5".** The confinement rests on two grounds and #8400 closes only the first; the second (the dispatched `worktree-manager.sh` is a *cached copy* of unknown age, chosen by `head -1`) survives untouched, because Phase 1 edits the repo's file and the cache holds a different one. The proposed `R5c`-analogue row could not catch it either: `mk_root` builds the fixture cache by copying `$PAYLOAD`, so the fixture is always in-sync and structurally cannot exhibit staleness. |
| **#8401: duplicate the cache arms as a separate pinned fragment in Step 0.5 + Step 0.0 only, leaving `session-start` at zero arms** | **Rejected.** Admissible — both are read-only — but it resolves nothing: ADR-179 records that Step 0.0 "already answers correctly through its inline `git rev-parse` fallback", so widening readiness buys almost nothing, and `session-start` stays dead on the harness #8401 is about. It also creates a second replicated literal needing its own drift guard. |
| **#8401: close it as superseded by ADR-179 decision 11** | **Rejected.** It is a real defect — every session-start gate (reaper, `git worktree list`, `.mcp.json` restore) is silently dead on a whole harness class — and closing it leaves the gate dead rather than making it safe. The ADR forbids one *mechanism*, not the outcome; it says #8401 is "explicitly gated on the script-side fix #8400", i.e. it contemplated resolution. |
| **#8401: version-pin arm 3 (compare the cache manifest's `version` to the repo's)** | **Rejected** in favour of feature detection. Version comparison is a sniff: it breaks on a fork, a local build, or any manifest whose version string does not sort the way the comparison assumes, and it asserts something the gate cannot verify. `SOLEUR_WORKTREE_REAP_CAPABILITY` names the capability the dispatch actually depends on, which is the repo's own doctrine for this surface. |
| **#8402: generate the block into the fleet from a template** | **Rejected** (Cut List). The drift guard already buys sync; a generator adds a second source of truth and a generation-drift mode for a one-time edit. |
| **#8402: make the identity check load-bearing (verify a signature, or assert the root is outside the working tree)** | **Rejected — already settled.** ADR-179 A11 rejected the out-of-tree assertion on three grounds and `go-session-gates.test.sh` R6b is a MUST-PASS row pinning the rejection. Reversing it means superseding A11 first. |
| **Three separate PRs** | **Rejected.** #8401 is explicitly gated on #8400 and widening the resolver without the guard fix is the exact hazard ADR-179 decision 11 records. #8402 is the cohort audit of the recipe #8401 propagates; splitting it leaves the entry point stricter than the fleet for another cycle. |

## User-Brand Impact

- **If this lands broken, the user experiences:** their own branches and pull requests disappearing
  at session start — `cleanup-merged` runs unattended, under `claude --bg` where stderr is invisible,
  and a wrong guard either deletes a branch a live session is working on (too permissive) or stops
  reaping entirely so `.worktrees/` and the ref namespace grow without bound (too strict). A wrong
  `go.md` resolver edit is worse in a different direction: it makes the destructive operation newly
  reachable on a harness where it has never run, on that harness's first session.
- **If this leaks, the user's workflow is exposed via:** the `soleur-cloud-mode` block instructs
  every skill in the fleet to locate and **execute** two scripts out of a shared plugin cache. The
  current basename selection accepts any directory under that cache holding a file with the right
  name. The exposure vector is a co-tenant or stale entry in the Devin plugin cache whose
  `cloud-detect.sh` or `precommit-guard.sh` is executed by a Soleur session — and
  `precommit-guard.sh` is the one that runs immediately before `git commit`. The identity preflight
  narrows that to directories carrying a `plugin.json` claiming `"name":"soleur"`; it does **not**
  authenticate, and this plan does not claim it does.
- **The threshold names the worst case, not the whole shape.** The reap failure mode is
  per-install, which is `single-user incident` and is the label that maximises review coverage here
  (`user-impact-reviewer` exits on `aggregate pattern`, and the panel drops from five agents to
  three). But two of this change's failure modes are **fleet-wide**: a permanent
  `reaper-capability-unverified` skip, and a wrong-but-uniform 69-file sweep. No gate in this repo
  currently keys on that dimension — filed as a `meta/machinery` issue, because the taxonomy
  inversion (the broader label buying less scrutiny) is a workflow defect and not this PR's job.
- **Brand-survival threshold:** `single-user incident`

*Threshold-driven sign-off:* `requires_cpo_signoff: true` in the frontmatter. CPO sign-off is
required at plan time before `soleur:work` begins — see `## Domain Review`.
`soleur:engineering:review:user-impact-reviewer` is invoked at review time per
`plugins/soleur/skills/review/SKILL.md`'s conditional-agent block.

## Observability

Layer 7 (`hr-observability-layer-citation`): this is plugin code that executes on a customer's own
CLI. There is no server-side sink for an installed user's local run and inventing one would be a
new egress surface — the file's own comment at the `SOLEUR_WORKTREE_LEASE_LIB_OK` emit records
exactly this. The operator's terminal is the sink, which is why every marker in this family goes to
**stdout**, not stderr: `cleanup-merged` runs under `claude --bg`, where stderr is invisible. In
this repo's own CI the same lines land in the job log, and `SOLEUR_GIT_REPO_DIAG` is additionally
mirrored to Better Stack by the server-side telemetry hook.

```yaml
liveness_signal:
  what:            "SOLEUR_WORKTREE_* stdout sentinel family emitted by every worktree-manager.sh invocation (LEASE_LIB_OK | LEASE_LIB_MISSING | REAPER_ARMED | REAP_CAPABILITY | REAPED | REAP_PARTIAL | SLUG_COLLISION | LEASE_ACQUIRE_FAILED; REAP_CAPABILITY, REAPED and REAP_PARTIAL are the three this change adds), plus SOLEUR_PLUGIN_ROOT_RESOLVE gate=<g> source=<s> verified=<b> from each go.md session gate and SOLEUR_SESSION_START_SKIPPED reason=reaper-capability-unverified source=<arm> from the Step 0 capability gate"
  cadence:         "per invocation — once per session start, and on every explicit worktree-manager.sh call"
  alert_target:    "the operator's own terminal (layer 7); in this repo's CI, the job log; SOLEUR_GIT_REPO_DIAG additionally to Better Stack via the server-side telemetry hook"
  configured_in:   "plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh (load-time lease-library block and the cleanup_merged_worktrees reap loop) and plugins/soleur/commands/go.md (the three gate fences)"

error_reporting:
  destination:     "installed user: stdout only, by design (layer 7, no egress surface). This repo: .claude/hooks/lib/incidents.sh -> .claude/.rule-incidents.jsonl, and the Better Stack mirror of SOLEUR_GIT_REPO_DIAG."
  fail_loud:       "SOLEUR_WORKTREE_LEASE_LIB_MISSING path=<p> reason=fail-closed-no-reap on stdout, followed by the four-line [warn] block on stderr; nothing is reaped while it is present"

failure_modes:
  - mode:          "lease library unresolvable (torn or legacy install) — every branch reads as held and cleanup silently stops doing anything"
    detection:     "SOLEUR_WORKTREE_LEASE_LIB_MISSING on stdout at load, once per invocation, emitted from the surface itself"
    alert_route:   "operator terminal; the [warn] block names the one-line git checkout that restores it"
  - mode:          "the non-bare main checkout is parked on a feature branch with uncommitted work when a reap succeeds — the pre-fix path reset --hard over it"
    detection:     "two plain stdout lines, NOT a SOLEUR_* sentinel: `Skipped stale-index reset: checkout is on '<b>', not main/master` and `Skipped main checkout: uncommitted changes on '<b>' (switching would carry them onto main)`. SUPERSEDED: this row said `SOLEUR_WORKTREE_MAIN_UPDATE_SKIPPED reason=not-on-main branch=<b> (new in this change)` and that marker was never shipped. It was demoted during implementation because a non-bare clone parked on a feature branch is the ORDINARY developer state, and a sentinel on it would page at happy-path volume while owing a git-lock-telemetry disposition it does not earn. The plan is corrected here rather than quietly: a declared-but-absent marker is what a consumer greps for and never finds."
    alert_route:   "operator terminal"
  - mode:          "a reap deletes a branch the operator still wanted — the single irreversible write in this function"
    detection:     "SOLEUR_WORKTREE_REAPED branch=<b> sha=<short> local=yes remote=<y|n> on stdout, once PER REAP, ungated by verbose (verbose is `[[ -t 1 ]]`, so a gated line is invisible under `claude --bg`, the mode session-start actually runs in). The sha= field is the recovery handle: `git branch <b> <sha>`."
    alert_route:   "operator terminal; mirrored to Better Stack via MARKER_RE in apps/web-platform/server/git-lock-marker-telemetry.ts"
  - mode:          "the remote ref was deleted (closing the PR) but the local delete then failed — a partial state downstream of the irreversible write"
    detection:     "SOLEUR_WORKTREE_REAP_PARTIAL branch=<b> local=no remote=<y|n> rc=<n> on stdout, followed by git's own error text. The cause is MEASURED, never named (AP-021) — `-D` never refuses for merge reasons, and the reachable causes are a live worktree holding the branch and a ref that vanished mid-run."
    alert_route:   "operator terminal; _HALT-group MARKER_RE mirror to Better Stack"
  - mode:          "a Step 0 dispatch resolves a CACHED worktree-manager.sh that predates the branch-keyed guards"
    detection:     "SOLEUR_SESSION_START_SKIPPED reason=reaper-capability-unverified source=<arm> on stdout; the reaper that WOULD have run emits SOLEUR_WORKTREE_REAP_CAPABILITY=branch-keyed-guards at load, and its absence is what the gate greps for"
    alert_route:   "operator terminal; go-session-gates.test.sh R11 in CI"
  - mode:          "a Devin CLI session newly reaches cleanup-merged after the Step 0 widening"
    detection:     "SOLEUR_PLUGIN_ROOT_RESOLVE gate=session-start source=devin-cache verified=true followed by the reaper's own output; the discriminating fields are gate/source/verified, so 'which arm resolved it' and 'did the dispatch happen' are one event, not an inference"
    alert_route:   "operator terminal; go-session-gates.test.sh R5d in CI"
  - mode:          "a cloud-mode block copy drifts back to basename selection, or a new skill ships without the block"
    detection:     "plugins/soleur/test/devin-cloud-mode.test.ts fails — byte-identity, the 67 cardinality pin, and (new) the repo-wide absence of -name cloud-detect.sh / -name precommit-guard.sh under plugins/soleur/"
    alert_route:   "CI required check on the PR"

logs:
  where:           "operator terminal scrollback for an installed user; GitHub Actions job log for this repo's CI runs; .claude/.rule-incidents.jsonl for repo-local hook telemetry"
  retention:       "terminal scrollback (session-lifetime, not durable); GitHub Actions default log retention; .rule-incidents.jsonl rotated by .claude/hooks/lib/log-rotation.sh"

discoverability_test:
  command:         "bash plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh list"
  expected_output: "SOLEUR_WORKTREE_LEASE_LIB_OK"
```

Measured: the probe returns in ~0.05s, well inside preflight Check 10's 15s cap; first token `bash`
is on `PROBE_VERB_ALLOWLIST`; no `ssh`; the expected output is the literal sentinel prefix the
command prints, not a description of it. No `credentials_required` — the property (is the lease
layer, on which every hold now depends, resolvable from this checkout?) has an unauthenticated
probe, so declaring one would waive a check that can actually run.

## Guard Contract

Three guards ship in this change. Each matrix below was written from the design, before the guard,
per Phase 2.12.

### Guard 1 — worktree-less reap decision (`cleanup_merged_worktrees`)

**Property.** No stale branch is deleted by `cleanup_merged_worktrees` without the session-lease
decision and the commit-age decision having been *evaluated for that branch*, whether or not it has
a worktree — and the main-checkout `reset --hard HEAD` runs only after the checkout has been
established to be on `main`/`master`.

**Assembly.** The chokepoint is the single `for branch in $all_stale_branches` loop body in
`cleanup_merged_worktrees` — every ref deletion this function performs flows through it. Inside the
loop the destructive call sites are `git push origin --delete` and `git branch -D`; the third,
`git -C "$GIT_ROOT" reset --hard HEAD`, sits in the post-loop summary block and is reached iff
`${#cleaned[@]} -gt 0`, so it is in the assembly by data dependency even though it is outside the
loop. **There is a second chokepoint the property does NOT quantify over, stated so the scope is
not read wider than it is:** `heal_stale_branch` carries its own `git push origin --delete` /
`git branch -D` pair (`worktree-manager.sh` ~`:1803` / ~`:1828`) on the `create` path. It is a
different function with a different precondition (an explicit `create` on a branch the operator
named) and this guard does not reach it. A property about *that* pair needs its own contract.

**Exit-site table, by position relative to the FIRST write.** The loop's first write into the
user's tree is the spec-directory `mv` into `archive/`; everything before it is non-mutating.

| Position | Site | Kind |
|---|---|---|
| before write 1 | `continue` — worktree is the CWD | guard exit, clean |
| before write 1 | `continue` — one-time arming hold (`_reaper_first_run`) | guard exit, clean; **not** worktree-path-gated, so it already covers this branch class |
| before write 1 | `continue` — active lease | guard exit, clean — **currently unreachable without a worktree; Phase 1 step 2 makes it reachable** |
| before write 1 | `continue` — recent commit / clock skew | guard exit, clean — **currently unreachable without a worktree; Phase 1 step 3 adds the branch-ref arm** |
| before write 1 | `continue` — uncommitted changes | guard exit, clean; genuinely N/A with no worktree |
| **write 1** | `mv "$spec_dir" "$archive_path"` | mutation |
| write 2 | `archive_kb_files` × 2 (brainstorms, plans) | mutation |
| after write 2 | `continue` — `git worktree remove` failed even with `--force` | **partial-state exit**: the spec dir and kb artifacts are already archived. Pre-existing; named here because the contract requires the table, not folded into this change's scope |
| write 3 | `git push origin --delete` | mutation (closes the PR) |
| write 4 | `git branch -D` | mutation (force delete) |
| post-loop | `git -C "$GIT_ROOT" reset --hard HEAD` | mutation — **Phase 1 step 4 moves its precondition (`current_branch` is main) in front of it** |

Every guard resolves before write 1 today, and the two new arms are inserted in the same region, so
the fix does not move any decision across a write boundary.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Restore the `[[ -n "$worktree_path" ]] &&` conjunct on the lease check | RED — the worktree-less fixture reaches `git branch -D` while holding a live lease |
| 2 | Neuter `is_lease_active` to `return 1` for every key (the pre-#5454 fail-open) while the fixture holds a live lease on the branch | RED |
| 3 | Add a **second** worktree-less stale branch after a compliant first (first held by lease, second not) and change the loop's `continue` to `break` | RED — a check that stops at the first member is the defect class itself |
| 4 | **Own dispatch:** make the fixture produce an empty `all_stale_branches` (or point the suite at a repo with no stale branch) | RED — the suite asserts a floor on how many branches it actually drove through the loop; a run that reaches the early `[[ -z "$all_stale_branches" ]]` return and reports success is vacuous |
| 5 | **Reorder:** move the `current_branch != main` check back below `reset --hard HEAD` | RED — the fixture's non-bare checkout is parked on a feature branch with an uncommitted file, and only a case that observes *inside* that window sees the loss. A delete-only mutation of the reset would red any case that reads the tree at all, which is why this row moves the check rather than removing it |
| 6 | Revert the `:82-83` warning text to the worktree-only wording | RED — a static row asserts the banner names branch deletion, so the documented scope cannot drift back below the enforced one |

**Harness rows.**

- *Suite mutation (must drive the suite RED):* delete one `want_*` call from the worktree-less row.
  The suite carries an expected-assertion-count check, paired with per-row identity assertions so
  that substituting one row for another cannot keep the count — a count alone is satisfiable by
  add-one-delete-one.
- *must-PASS input that is NOT the canonical:* (a) a stale branch **with** a worktree, unleased,
  clean, last commit older than the grace window — must still be reaped exactly as today; the fix
  must not degrade into a blanket refusal. (b) a slash-bearing branch (`ci/rule-metrics`) whose
  `safe_branch` differs from the raw name — the lease key must still resolve. Both are differences
  the contract explicitly permits.

**Anchor.** This guard executes the shipped script rather than comparing it to a stored value, so
there is no hash to weaken. The one stored constant is the assertion-count floor, anchored as above
by per-row identity assertions. The mutant arms are built by transforming a **copy** of the shipped
script and each mutation is asserted to have landed via `diff` against a pristine copy
(`worktree-manager-safe-branch-sanitization.test.sh`'s pattern), so a silently-missed anchor makes
the mutant identical to the real script and the arm fails loudly instead of passing vacuously.

### Guard 2 — one resolver across the three `go.md` gates (`go-session-gates.test.sh`)

**Property.** All three `go.md` gate fences resolve the plugin root through the same four-arm
resolver, byte-identically; each one behaviourally reaches its own dispatch when the Devin cache
arm is the only arm that can resolve; and `session-start` dispatches `cleanup-merged` **only** from
a root whose `worktree-manager.sh` carries the reap-capability token, on every arm.

**Assembly.** The structural chokepoint is `extract_fence()` applied over the `GATE_ANCHORS` array
— three whole-line heading anchors — together with R10's assertion that `go.md` carries **no bash
fence outside the declared anchors**, which is what makes the three-member enumeration a closed set
rather than a snapshot. The resolver bytes within each fence are delimited by
`# --- soleur plugin-root resolver` / `# --- end resolver ---`. Moving the Devin arms inside those
delimiters is precisely what brings them into this assembly; leaving them outside is what made the
current single-copy placement expressible at all.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Remove the Devin cache arms from **one** fence only | RED — R8 byte-identity (`readiness == cloud-detect`, `cloud-detect == session-start`) |
| 2 | Rename a gate heading (`## Step 0.5: Cloud Mode detection (renamed)`) | RED — `extract_fence`'s whole-line equality plus R10's fence count; this is the mutation that previously SURVIVED a prefix match |
| 3 | Add a **fourth** bash fence to `go.md` carrying its own resolver | RED — R10's "no bash fence outside the declared gate anchors" count; a second member added after a compliant first |
| 4 | **Own dispatch:** make `extract_fence` return empty for all three anchors | RED — R8's "a resolver snippet is EMPTY" row and R10's per-gate non-empty-body rows; a suite that checks three empty strings for equality and passes is the vacuity this row exists for |
| 5 | Let the session-start fence resolve the cache arm but delete its `worktree-manager.sh` invocation | RED — R5d asserts `${R1_EFFECT[2]}` (`STUB_WORKTREE_MANAGER argv=cleanup-merged`), so the row proves the dispatch was reached, not merely that a root resolved |
| 6 | Reintroduce the confinement (strip the arms from `readiness` and `session-start`) | RED — R9's rewritten per-gate `>= 2` occurrence count, and R5d/R5e behaviourally |
| 7 | **Remove the capability `grep -q` from the session-start fence, keeping the `[ -f ]` check** | RED — R11 plants a verified root whose manager lacks the token and asserts `reason=reaper-capability-unverified` plus `want_not_in … STUB_WORKTREE_MANAGER`. This is the row that makes the whole Phase 2 widening admissible; if it can be removed while the suite stays green, the ADR amendment rests on nothing |
| 8 | Invert the capability check (dispatch when the token is ABSENT) | RED — R5d asserts the dispatch happens on a token-bearing root and R11 asserts it does not on a token-less one; a single row could not distinguish these, which is why both ship |
| 9 | **Own dispatch, second form:** strip the capability token from `worktree-manager.sh` itself while leaving the fence intact | RED — R5d's `${R1_EFFECT[2]}` stops appearing, so the token's producer and its consumer are pinned together rather than each assuming the other |
| 10 | Re-resolve the path between the `grep -q` and the `bash` — check one root, execute another | RED — a static row asserts the fence's dispatch arm contains no second `find` and that the `grep` operand and the `bash` operand are the same `${ROOT}`-derived string. Check-A/execute-B is the defect one level down from the one the gate closes, and no behavioural row can see it |
| 11 | Plant the capability token in `mk_decoy_root`'s decoy and then *relax* the gate so a token-less root dispatches anyway | RED — R11 still asserts the token-less refusal. Stated because the tempting "fix" for a red R6b is to weaken the gate, and this row makes that route red rather than green |

**Harness rows.**

- *Suite mutation:* shrink `GATE_ANCHORS` to two entries. R10's
  `count_fences == ${#GATE_ANCHORS[@]}` would then pass vacuously, so the suite gains a row
  asserting `${#GATE_ANCHORS[@]}` equals an **independently derived** count of `^## Step` headings
  in `go.md` that are followed by a bash fence. Without it the guard's own population is
  self-declared.
- *must-PASS input that is NOT the canonical:* a cache root at a different directory name
  (`soleur-zzz999`, not `soleur-abc123`) whose `plugin.json` carries extra keys and non-canonical
  whitespace around `"name"` (`"name"  :  "soleur"`) — must still resolve, because the grep pattern
  is `'"name"[[:space:]]*:[[:space:]]*"soleur"'`. **And R6b stays a MUST-PASS row unchanged:** a
  decoy manifest claiming `"name":"soleur"` is accepted and its payload executes. Nothing in this
  change may make R6b red.

**Anchor.** R8 compares the three copies **to each other**, so it proves consistency, not
integrity: one diff can edit all three copies and the test together. The integrity anchor is
outside the commit — ADR-179 decision 11 (amended by this PR, CODEOWNERS-reviewed) and R6b's
documented MUST-PASS status, whose own comment reads "If this row ever fails, someone added a trust
assertion the ADR declined — supersede A11 first, then change this row." A weakening therefore has
to move the ADR in the same review, not just the bytes.

### Guard 3 — one cloud-cache recipe across the shipped cohort (`devin-cloud-mode.test.ts`)

**Property.** No file shipped under `plugins/soleur/` instructs an agent to locate an executable in
the Devin plugin cache **by filename**; every such instruction selects by `.claude-plugin/plugin.json`
identity, `[ -d ]`-gated, over both documented cache paths.

**Assembly.** **The 67-member marker list is a snapshot, not the assembly.** The population this
property quantifies over is *every file under `plugins/soleur/` that names a Devin plugin-cache
path*, derived at test time by scanning for `/opt/\.devin/plugins` and `devin/cli/plugins/cache`.
Measured today that derivation yields **69 files / 70 occurrences**: the 67 `soleur-cloud-mode`
marker blocks, plus three sites the marker-block test structurally cannot see —
`plugins/soleur/skills/work/SKILL.md`'s executable `GUARD="$(find … -name precommit-guard.sh …)"`
line in the skill body, `plugins/soleur/devin/INSTRUCTIONS.md`, and `plugins/soleur/AGENTS.md`'s
`[id: cloud-detect-before-pipeline]` rule body. The existing byte-identity + cardinality test is a
**sub-guard over one subset** of the population; the derived scan is the guard over the population.
Both ship.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Revert one marker copy to `find /opt/.devin/plugins -name cloud-detect.sh \| head -1` | RED — byte-identity against the canonical, and the derived negative scan |
| 2 | Revert **`plugins/soleur/AGENTS.md`'s rule body** to the basename recipe | RED via the derived scan **only** — the marker-block test never opens that file. This row is what proves the new scan does work the old guard did not, and it is the reason the assembly is derived rather than listed |
| 3 | Add a new skill carrying the marker block with the old recipe | RED — byte-identity; the `67` cardinality also moves, which must be a deliberate edit |
| 4 | **Own dispatch:** point the derived scan at a directory that does not exist, so it returns zero files | RED — a non-vacuity control asserts the derived population is non-empty and at least as large as the known non-marker sites, so a scan that finds nothing fails instead of passing |
| 5 | Add a **second** non-marker site (a new `plugins/soleur/devin/*.md` carrying the basename recipe) after a compliant first | RED — the scan quantifies over every member; a check that stops at the first is the defect class |
| 6 | Replace the canonical block's identity `find` with one that drops the `[ -d ]` guard or one cache path | RED — the positive content assertions (both cache paths present, `.claude-plugin/plugin.json` path predicate present, `"name"…"soleur"` predicate present) |

**Harness rows.**

- *Suite mutation:* change the derived scan's pattern to one that cannot match (`-name zzz`). The
  suite carries a **planted-positive self-test**: a synthesized temp file containing the basename
  recipe is run through the same detector helper and must be reported as a violation. A detector
  that reports nothing on a planted positive reds the suite, so a neutered pattern cannot pass.
- *must-PASS input that is NOT the canonical:* a file under `plugins/soleur/` that names
  `/opt/.devin/plugins` in a path-only sense with no basename selection — `devin/INSTRUCTIONS.md`'s
  "the lock file is `/opt/.devin/plugins/lock.json`" is exactly this, and it must PASS. The
  contract forbids selecting by basename, not mentioning the directory.

**Anchor.** The stored value here is the cardinality `expect(marked.length).toBe(67)`, and a `>= N`
or `== N` floor survives any substitution that keeps N — an add-one-delete-one diff satisfies it
exactly. It is therefore paired with **set identity**: the suite asserts the sorted list of marked
paths, not only its length, so swapping one member for another has to edit a reviewed list. The
derived scan's population is re-derived from the filesystem on every run rather than stored, so it
carries no self-certifying hash.

## Architecture Decision (ADR/C4)

Detection fires on two triggers: this plan **reverses part of an existing ADR** (ADR-179 decision
11's "must NOT"), and it introduces a **dispatch/trust boundary change** — a new cross-cutting
invariant that a session gate may dispatch a destructive operation only from a root whose artifact
declares the capability the gate depends on.

### ADR

**Amend `ADR-179-bare-plugin-root-anchor-for-customer-facing-executables.md`, decision 11.** No new
ordinal is claimed, so there is nothing for `soleur:ship`'s ADR-Ordinal Collision Gate to catch;
`adr-ordinals` should stay green on this PR. The amendment:

- restates the **two** grounds the confinement rested on, and which change closes each: the
  per-branch guard gap (Phase 1) and the stale-cached-artifact problem (Phase 2's capability gate);
- supersedes the blanket *"#8401 must NOT be resolved by moving the cache arms into the shared
  resolver"* with the narrower rule it was standing in for: **Step 0 may resolve from any arm; it
  may dispatch `cleanup-merged` only from a root whose reaper declares
  `SOLEUR_WORKTREE_REAP_CAPABILITY`** — a feature detect, never a version sniff, and **scoped to
  the `devin-cache` arm** (superseded here per B1: the arm-agnostic form was measured to stop
  reaping on the token and `GROK_PLUGIN_ROOT` arms too, which the confinement never did);
- records that the residual ADR-179 names (`cleanup_orphan_worktree_dirs` →
  `rm -rf --one-file-system`) is now behind the same gate, because the gate covers the whole
  dispatch rather than the reap loop alone, and that the remaining per-branch gap in that function
  is filed;
- records that the "recorded inconsistency" paragraph — go.md stricter than the fleet block — is
  **closed** by Phase 3, and updates its `#8402` reference accordingly;
- leaves **A11 untouched** and re-states its consequence verbatim: the identity preflight is
  defence-in-depth, not the load-bearing control, and `go-session-gates.test.sh` R6b stays a
  MUST-PASS row.

*Considered and rejected:* minting a new ADR (next free ordinal would be ADR-233) for the
capability-gate rule. It exists only to make decision 11's outcome admissible, so splitting one
decision across two records would leave a reader of decision 11 with a "must NOT" and no pointer to
the thing that lifted it. If review disagrees, the ordinal above is **provisional** — a sibling PR
can claim it during the pipeline, `soleur:ship` re-verifies against `origin/main`, and a renumber
must sweep this plan, `tasks.md` and every AC naming the ordinal in the same edit.

### C4 views

**Container view — two edge descriptions change; no element, actor or boundary moves.**

1. `devin -> platform.plugin` (`model.c4`, the edge whose current description is "Loads skills,
   AGENTS.md rules, and MCP in both substrates; plugin subagents and SessionStart/SessionEnd hooks
   only on local") gains how the plugin root **resolves** on this harness: all three `/soleur:go`
   session gates now resolve from the Devin plugin cache (`$HOME/.local/share/devin/cli/plugins/cache`,
   `/opt/.devin/plugins`), `[ -d ]`-gated and identity-selected on `.claude-plugin/plugin.json`
   naming `soleur`, and the session-start gate dispatches `cleanup-merged` only from a root
   declaring `SOLEUR_WORKTREE_REAP_CAPABILITY` (ADR-179 decision 11 as amended).
2. `grokBuild -> plugin` (`model.c4:423`) currently reads "the plugin root resolves from the
   loader-substituted `${CLAUDE_PLUGIN_ROOT}` token first, then `GROK_PLUGIN_ROOT` (ADR-179
   decision 11)". That enumeration becomes **incomplete** once the resolver carries a third arm in
   all three fences, so the edge description is falsified by this change and must be corrected in
   the same commit — the "fix any element description the change falsifies" limb of the C4
   completeness mandate.

**Enumeration performed, per the completeness mandate — all three `.c4` files read, not grepped for
the feature's own noun:**

| Class | Finding |
|---|---|
| External **human actors** | `founder` is the only one on these edges. Nobody new sends or receives anything; the change alters how a machine resolves a path. Already modelled. |
| External **systems / vendors** | `devin` (system "Devin (CLI + Cloud)", `model.c4:22`), `grokBuild`, `codex`. All three already modelled, all already `#external`, all already carried in the `containers` view's include list (`views.c4:27` adds `devin` explicitly). No new vendor, no new webhook, no new outbound API. |
| **Containers / data stores** | None. No new store, no new queue, no new host. The Devin plugin cache is a directory on the harness's own machine, inside the already-modelled `devin` boundary — it is not a Soleur-owned store and does not become a C4 element. |
| **Actor↔surface access relationships** | One changes in *description* only (item 1 above); one is falsified and corrected (item 2). No edge is added, removed or re-pointed, so no `views.c4` `include` line changes and no element needs an `#external` tag it does not have. |

**Cardinalities.** The derived counts `model.c4` embeds (58 cron monitors, the 14/44 `github ->
sentry` split) are untouched by this change. Per the mandate, that claim is backed by a green
`bash plugins/soleur/test/c4-count-parity.test.sh` run, not by reasoning about actors —
`apps/web-platform/test/c4-code-syntax.test.ts` and `c4-render.test.ts` run alongside it.

### Sequencing

The decision is true the moment Phase 1 and Phase 2 land together; nothing here is soak-gated, so
the ADR is authored at `accepted`, not `adopting`, and Phase 2.9.1's Follow-Through Enrollment does
not fire.

## Domain Review

**Domains relevant:** Engineering

### Engineering (CTO)

**Status:** reviewed

**Assessment:** The advisory **reversed Phase 2**. It located ADR-179's explicit
*"#8401 must NOT be resolved by moving the cache arms into the shared resolver"* and established
that the confinement rests on a second ground the plan had not addressed — arm 3 executes a
*cached copy* of `worktree-manager.sh` of unbounded age, so fixing the repository's script does not
fix the artifact that runs. It also observed that the proposed `R5c`-analogue row is structurally
incapable of catching it, because `mk_root` builds the fixture cache by copying `$PAYLOAD` and is
therefore always in-sync. Both claims were verified independently against the ADR text and the test
harness before being adopted. Phase 2 was rewritten around a capability feature-detect on the
dispatch, which addresses the ground rather than overriding it, plus an explicit amendment to
decision 11.

Also adopted (all mechanical, all verified): guard the `basename` operand inside the `[[ -n
"$worktree_path" ]]` condition; state the `_SS_LIB_MISSING` scope widening as a behaviour change;
describe the `refs/heads/$branch` grace honestly (it holds freshly squash-merged branches for ten
minutes and buys little on that cohort) rather than as a symmetric analogue; correct the
reset-reorder shape, because `git checkout main` refuses on a dirty tree and the naive reorder
still resets; six named `set -euo pipefail` abort sites; per-site treatment for the three
non-marker `#8402` sites (pointer in the plugin `AGENTS.md` rule body, paragraph rewrite in
`INSTRUCTIONS.md`, identity-keyed append for the executable line); the `[ -n "$GUARD" ] && bash …`
fail-open next to that line; guard-before-sweep commit ordering; and `precommit-guard.sh`'s absence
from `GATE_SCRIPT_RE`.

**Not adopted — recorded as a decision challenge, not silently dropped:** the recommendation to
split into three PRs (and to drop #8401). The three-PR split contradicts the operator's stated
direction for this pipeline, so per `decision-principles.md` it is surfaced rather than applied —
see `knowledge-base/project/specs/<branch>/decision-challenges.md`, which `soleur:ship` renders
into the PR body and files as an `action-required` issue. The *within-PR* commit ordering the
advisory asks for is adopted in full, which recovers most of the reviewability argument: Phase 1 is
its own commit, Phase 3's guard strengthening precedes its 69-file sweep, and the sweep commit is
mechanical.

### Product/UX Gate

Not applicable. The mechanical UI-surface override does not fire: no path in `## Files to Edit` or
`## Files to Create` matches the UI-surface term list or glob superset — no `components/**/*.tsx`,
no `app/**/page.tsx`, no `app/**/layout.tsx`, no route or template. The change is bash, markdown
contracts and tests. Product tier: NONE.

### Domains assessed and found not relevant

Marketing, Sales, Finance, Support, Operations — no campaign, deal, cost, ticket or infrastructure
surface. **Legal** was assessed explicitly rather than skipped, because a sibling brainstorm
(2026-09-15) flagged `devin/INSTRUCTIONS.md:91`'s credential-guard claim as a legal surface tied to
the PA-8/PA-31 register: this change does not touch that line, adds no new data processing, and
alters no published claim. The one claims-accuracy obligation it does carry — not describing the
identity preflight as authentication — is handled in the PR body and enforced by ADR-179 A11 and
R6b, not by a legal-document edit.

### GDPR / compliance (Phase 2.7)

Does not fire. No regulated-data surface (no schema, migration, auth flow, API route or `.sql`),
and none of the four expansion triggers hold: no LLM/external-API processing of session-derived
data, no new cron or workflow reading `knowledge-base/`, and no new artifact-distribution surface
(this modifies an existing shipped plugin, it does not add a distribution channel). The
`single-user incident` threshold **is** declared, which is expansion trigger (b), so the gate is
recorded as assessed rather than skipped silently: the change adds one telemetry line family, all
of it on the operator's own stdout, and `go-session-gates.test.sh` R9 already pins that the
`SOLEUR_PLUGIN_ROOT_RESOLVE` marker never interpolates the resolved path — filesystem paths stay
out of telemetry, which is the property that made the original GDPR assessment true and which this
change preserves.

### Infrastructure-as-Code (Phase 2.8)

Does not fire. No server, service, cron, vendor account, DNS record, cert, secret, firewall rule or
monitoring webhook. No detection phrase appears in the plan: no remote-shell step, no `systemctl`,
no Doppler secret-write command, no vendor-dashboard click-through, no operator-run provisioning.

### Encryption Posture (Phase 2.11)

Does not fire. No persistent store and no new cross-component or network connection. No `.tf`, no
`supabase/migrations/*.sql`, no `cloud-init*.yaml`, no `docker-compose*.yaml` in the file lists.
Recorded so the absence is an assessment rather than an omission.

## Files to Edit

Every path below was confirmed present in the working tree; every count is measured, not estimated.

**Phase 1 (#8400)**

- `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh` — the `[warn]` banner block, the
  reap loop's lease and grace guards, the post-loop non-bare main-update tail, and the new
  `SOLEUR_WORKTREE_REAP_CAPABILITY` token + stdout emit.

**Phase 2 (#8401)**

- `plugins/soleur/commands/go.md` — the three gate fences (`## Step 0.0: Workspace Readiness Gate`,
  `## Step 0.5: Cloud Mode detection`, `## Step 0: Session-Start Preamble`): the resolver block
  gains the Devin cache arms inside its anchors, and the session-start dispatch gains the
  capability `grep -q`. The resolver's header comment, which currently states the confinement
  rationale, is rewritten.
- `plugins/soleur/test/go-session-gates.test.sh` — R9's per-gate cache-path predicate; new rows
  R5d, R5e, R11; `mk_root` plants the capability token in its stub manager; the
  `${#GATE_ANCHORS[@]}` self-derivation harness row.
- `knowledge-base/engineering/architecture/decisions/ADR-179-bare-plugin-root-anchor-for-customer-facing-executables.md`
  — decision 11 amendment.

**Phase 3 (#8402) — 69 files in two commits**

- `plugins/soleur/test/devin-cloud-mode.test.ts` — **commit 1**, alone: content assertions, the
  derived negative scan, the planted-positive self-test, the non-vacuity floor, set identity
  alongside the `67` cardinality.
- `plugins/soleur/skills/work/SKILL.md` — **commit 2**: the canonical marker block **and** the
  separate executable `GUARD=…` line plus its fail-open marker. This file is edited twice for two
  different reasons and both must land.
- 63 further `plugins/soleur/skills/*/SKILL.md` and 3 `plugins/soleur/devin/skills/*/SKILL.md` —
  commit 2, marker block only, scripted in-place replacement anchored on the marker comments.
  (67 marker blocks total, which is the cardinality `devin-cloud-mode.test.ts` pins.)
- `plugins/soleur/devin/INSTRUCTIONS.md` — commit 2, paragraph rewrite.
- `plugins/soleur/AGENTS.md` — commit 2, rule `[id: cloud-detect-before-pipeline]` body becomes a
  pointer. Id unchanged.

**Phase 4**

- `knowledge-base/engineering/architecture/diagrams/model.c4` — the `devin -> platform.plugin` and
  `grokBuild -> plugin` edge descriptions.

**Not edited, verified:** `plugins/soleur/skills/go/SKILL.md` carries no resolver (it is a 27-line
Devin shim; it does carry the marker block, so it is one of the 67). No `SKILL.md` frontmatter
`description:` is touched anywhere in this change — the `soleur-cloud-mode` block sits in the body,
below the closing `---` — so the Phase 1.8 skill-description word-budget check does not fire at
either its Phase 1 or its Step 2 re-check.

## Files to Create

- `plugins/soleur/test/worktree-manager-cleanup-merged-no-worktree.test.sh` — the Phase 1 suite.

**Registration is automatic, and that was verified rather than assumed.** `scripts/test-all.sh`
carries `SUITE_GLOBS`, whose first entry is `plugins/soleur/test/*.test.sh`, and its own comment
records that a hardcoded array "would freeze today's matches into the array and silently stop
registering files added later". So the new suite needs no registry edit. The two count-aware
neighbours were checked and neither pins a literal: `scripts-shard-totality.test.sh` derives
`REF_N`/`LEGS_N` at run time, and `fanout-suite-scope.test.sh` asserts `>= MIN_REGISTERED` floors.

**One stale comment will result.** `scripts/test-all.sh`'s `TEST_GROUP` documentation says the
`scripts` shard is "11 pre-suite bash/python + 21 `plugins/soleur/test/*.test.sh`"; the new suite
makes that 22. It is prose, not an assertion, so nothing reddens — update it in the same commit so
the number does not rot.

## Acceptance Criteria

### Functional Requirements

- [ ] **FR1** — For a stale branch with no worktree that holds an active lease under its
  `_safe_worktree_name` key, `cleanup_merged_worktrees` reaches neither `git push origin --delete`
  nor `git branch -D`. (`worktree-manager.sh`, the reap loop's lease guard; asserted by
  `worktree-manager-cleanup-merged-no-worktree.test.sh`.)
- [ ] **FR2** — For a stale branch with no worktree whose ref tip is newer than the grace window,
  the loop skips it with a `(skip)` reason distinct from the worktree arm's.
  (`worktree-manager.sh`, the grace guard.)
- [ ] **FR3** — When the non-bare `$GIT_ROOT` is not on `main`/`master`, or its branch cannot be
  read, `cleanup_merged_worktrees` performs no `reset --hard`, no `checkout` and no `pull`, and
  says so on stdout in plain prose. **Superseded 2026-09-20 (#8400):** `SOLEUR_WORKTREE_MAIN_UPDATE_SKIPPED` was demoted during implementation per challenge B5 below and never shipped. What ships is two plain stdout lines — `Skipped stale-index reset: checkout is on '<b>', not main/master` and `Skipped main checkout: uncommitted changes on '<b>' (switching would carry them onto main)`. Read every mention of the marker in this plan as naming those lines.
  (`worktree-manager.sh`, post-loop non-bare tail. Asserted by A11/M3 in
  `worktree-manager-cleanup-merged-no-worktree.test.sh`.)
- [ ] **FR4** — `worktree-manager.sh` declares `SOLEUR_WORKTREE_REAP_CAPABILITY=branch-keyed-guards`
  as a literal and emits it on stdout at load. **Superseded 2026-09-20:** the `-v1` suffix was
  dropped per challenge B5 below — the token names the CAPABILITY, not a version, and the gate
  tests set membership so adding a capability stays additive.
- [ ] **FR5** — The `[warn]` block that fires when `session-state.sh` is unresolvable states that
  cleanup will refuse to reap any worktree **or delete any branch**.
  (`worktree-manager.sh`, the `_SS_LIB_MISSING` arm.)
- [ ] **FR6** — All three `go.md` gate fences carry both Devin cache paths inside the resolver
  anchors, and the bytes between those anchors are identical across the three.
  (`go.md`; `go-session-gates.test.sh` R8 + R9.)
- [ ] **FR7** — On a host where only the Devin cache arm can resolve, the session-start gate emits
  `SOLEUR_PLUGIN_ROOT_RESOLVE gate=session-start source=devin-cache verified=true` and dispatches
  `cleanup-merged`. (`go.md` Step 0; `go-session-gates.test.sh` R5d.)
- [ ] **FR8** — A verified root whose `worktree-manager.sh` lacks the capability token produces
  `SOLEUR_SESSION_START_SKIPPED reason=reaper-capability-unverified` and **no** dispatch.
  (`go.md` Step 0; `go-session-gates.test.sh` R11.)
- [ ] **FR8b** — The capability `grep -q` and the `cleanup-merged` invocation operate on the same
  `${ROOT}`-derived path with no re-resolution between them. (`go.md` Step 0; Guard 2 row 10.)
- [ ] **FR8c** — `go-session-gates.test.sh` R6b remains green and **unmodified**, including its
  harness. Measured at plan review: R6b's session-start leg never reaches the decoy reaper (the
  decoy classifier's banner is not an accepted verdict, so `SESSION_OK=false`), so the capability
  gate is indifferent to it. No `mk_decoy_root` change is needed or wanted.
- [ ] **FR8d** — On `reaper-capability-unverified`, `git worktree list` **and** the `.mcp.json`
  restore still run. The gate wraps the `cleanup-merged` invocation only — not the `[ -f ]` arm
  that also holds `git worktree list`, and not the restore that is deliberately its sibling.
  Without this, a stale install reproduces the exact three-gates-die-together defect #8401 exists
  to fix. (`go.md` Step 0; asserted by R11's positive `want_in`s, not only its `want_not_in`.)
- [ ] **FR13** — Each new `SOLEUR_*` sentinel carries an explicit disposition in
  `apps/web-platform/server/git-lock-marker-telemetry.ts`:
  `SOLEUR_WORKTREE_REAP_CAPABILITY` joins `SUCCESS_PATH_CONTROL_SIGNALS` (it is emitted on every
  invocation, exactly like `SOLEUR_WORKTREE_LEASE_LIB_OK`);
  `SOLEUR_WORKTREE_MAIN_UPDATE_SKIPPED` does not ship (see above), so it owes no disposition.
  What shipped instead: `SOLEUR_WORKTREE_REAPED` and `SOLEUR_WORKTREE_REAP_PARTIAL` join
  `MARKER_RE` (the latter in the `_HALT` group), and `PRECOMMIT_GUARD` joins `_HALT` too.
- [ ] **FR9** — No file under `plugins/soleur/` selects a Devin-cache executable by filename
  (`find <cache> … -name/-iname <script>`), with exactly one allowlisted path — the guard file
  itself — and an assertion that the allowlist holds exactly one entry.
  (`devin-cloud-mode.test.ts`, derived negative scan.)
- [ ] **FR10** — The canonical `soleur-cloud-mode` block is `[ -d ]`-gated, names both documented
  cache paths, and selects on `.claude-plugin/plugin.json` containing
  `"name"[[:space:]]*:[[:space:]]*"soleur"`; all 67 copies are byte-identical to it and the marked
  path *set* matches a committed list. (`devin-cloud-mode.test.ts`.)
- [ ] **FR11** — `work/SKILL.md`'s commit-on-main backstop emits
  `SOLEUR_PRECOMMIT_GUARD_UNRESOLVED` when no guard resolves, instead of proceeding silently.
- [ ] **FR12** — ADR-179 decision 11 records the confinement as lifted, names both original grounds
  and what closed each, and leaves A11 and R6b untouched. The `model.c4` `devin -> platform.plugin`
  and `grokBuild -> plugin` edge descriptions match the shipped arm order.

### Non-Functional Requirements

- [ ] **NFR1** — No new `set -euo pipefail` abort path in `cleanup_merged_worktrees`: the function
  still reaches `cleanup_orphan_worktree_dirs` and `cleanup_claude_tmp` when a new guard's
  underlying command fails. Driven by a mutant arm that makes `git log` on the ref fail.
- [ ] **NFR2** — `go.md`'s fences remain POSIX and option-free: no `xargs -r`, `readlink -f`,
  `stat -c`, `sed -i`, `timeout `, no `set -e/-u/-o pipefail`, no unbraced `$CLAUDE_PLUGIN_ROOT`.
  (`go-session-gates.test.sh` R9's existing ban rows, unchanged.)
- [ ] **NFR3** — `SOLEUR_PLUGIN_ROOT_RESOLVE` still carries no filesystem path. (R9, unchanged.)
- [ ] **NFR4** — Behaviour is unchanged for a stale branch that **has** a worktree: unleased, clean
  and old, it is still reaped.
- [ ] **NFR5** — `go-session-gates.test.sh` R6b stays green and unmodified, harness included. A red
  R6b means a trust assertion ADR-179 A11 declined has been added, and A11 must be superseded
  before that row moves.
- [ ] **NFR6** — `go-session-gates.test.sh`'s `MIN_ASSERTIONS` floor is raised by the number of
  assertions the new rows add. Its own comment says raising it is part of adding a row (147 → 155
  when R3f/R3g/R3h landed); leaving it is the "floor slack is attack budget" condition the suite
  warns about.

### Quality Gates

- [ ] `bash plugins/soleur/test/worktree-manager-cleanup-merged-no-worktree.test.sh` — green, with
  every mutant arm asserted to have landed via `diff` against a pristine copy.
- [ ] `bash plugins/soleur/test/go-session-gates.test.sh` — green, including R6b.
- [ ] `bash plugins/soleur/test/worktree-manager-safe-branch-sanitization.test.sh`,
  `-stale-lock-diag`, `-heal-stale-branch`, `-porcelain-sigpipe`, `-atomic-config`,
  `-bare-in-dotgit-layout` — green (the reap loop's existing neighbours).
- [ ] `plugins/soleur/test/devin-cloud-mode.test.ts` — green after commit 1 only if the sweep has
  landed; **red between commit 1 and commit 2 is expected and is the point**.
- [ ] `bash plugins/soleur/test/c4-count-parity.test.sh`,
  `apps/web-platform/test/c4-code-syntax.test.ts`, `c4-render.test.ts` — green.
- [ ] `plugins/soleur/test/session-state.test.sh` T18a (the static check that
  `cleanup_merged_worktrees` still invokes `sweep_orphan_leases`) — green.
- [ ] `python3 scripts/lint-guard-contract.py` over this plan — green.
- [ ] `python3 scripts/lint-rule-bodies.py --check --base "$(git merge-base origin/main HEAD)"` —
  green, and expected to be a no-op: the edited rule body is in `plugins/soleur/AGENTS.md`, which
  is outside `SIDECARS`.
- [ ] `soleur:preflight` Check 10 executes this plan's `discoverability_test` and matches
  `SOLEUR_WORKTREE_LEASE_LIB_OK`.
- [ ] `scripts/test-all.sh`'s `scripts`-shard comment updated from 21 to 22
  `plugins/soleur/test/*.test.sh` suites (prose only — no gate asserts it).
- [ ] **The authoritative green is the gate's own invocation — `bash scripts/test-all.sh`** (which
  is `package.json` `scripts.test`, and what CI runs). The per-file commands above are for the
  RED/GREEN loop; an AC that claims "CI is green" from a hand-enumerated file list is pinned to a
  different set than the gate. Note `test-all.sh`'s exit contract: `3` is UNRESOLVED (a killed or
  declined suite), which is **not** green.
- [ ] **Consumer sweep for the `worktree-manager.sh` output change.** Phase 1 changes what the
  script prints (a new load-time token line, two new `(skip)` reasons, the `SOLEUR_WORKTREE_REAPED`
  and `SOLEUR_WORKTREE_REAP_PARTIAL` sentinels, and two plain off-main lines — not the
  `SOLEUR_WORKTREE_MAIN_UPDATE_SKIPPED` marker this plan originally declared). Every consumer that *executes these bytes* or
  greps this output must be re-run, not only the suites whose names match:
  `git grep -l 'worktree-manager.sh' -- '*.test.ts' '*.test.sh' '.github' 'scripts' '.claude'`
  returned 21 files at plan time, spanning `apps/web-platform/test/` (`plugin-root-anchoring`,
  `plugin-root-list-carveout-coupling`, `git-lock-marker-telemetry`, `safe-bash`, two
  `server/inngest/` suites), `plugins/soleur/skills/git-worktree/test/` (5 suites),
  `plugins/soleur/skills/incident/test/redact-sentinel.test.sh`, `plugins/soleur/test/` (several),
  and `.claude/hooks/guardrails.sh`. `test-all.sh` covers them; the list is here so a targeted
  re-run cannot silently miss the orphan suites.

## Test Scenarios

### Acceptance tests (RED-phase targets)

1. **Worktree-less + live lease.** Fixture: `main`, branch `feat-gone-a` merged into it, no
   worktree, a lease file for key `feat-gone-a` inside its window. Drive
   `cleanup_merged_worktrees`. Assert: the `git` stub recorded **no** `push origin --delete` and
   **no** `branch -D` for it, and stdout carries `(skip) feat-gone-a - active lease`.
2. **Worktree-less + fresh ref tip.** Same shape, no lease, branch tip committed 60s ago. Assert:
   no deletion, and the branch-ref `(skip)` reason.
3. **Worktree-less + no lease + old tip.** Assert: it **is** reaped — both deletions recorded. This
   is the must-PASS control that the fix has not become a blanket refusal.
4. **Non-bare `$GIT_ROOT` parked off main with an uncommitted file, after a successful reap.**
   Assert: the file still exists and no `reset --hard` is recorded. **Superseded:** the marker
   named here was demoted; assert the plain `Skipped stale-index reset: …` line instead. Shipped
   as A11 + mutant M3.
5. **Step 0 on a Devin-cache-only host, token-bearing root.** `gate=session-start
   source=devin-cache verified=true` **and** `STUB_WORKTREE_MANAGER argv=cleanup-merged`.
6. **Step 0 on a verified root whose manager lacks the token.**
   `reason=reaper-capability-unverified`, and `STUB_WORKTREE_MANAGER` absent from stdout.
7. **Derived negative scan.** No `-name cloud-detect.sh` / `-name precommit-guard.sh` anywhere
   under `plugins/soleur/`, with the population floor and the planted-positive self-test asserting
   the scanner is not vacuous.

### Regression tests

8. **Worktree-bearing branch, unleased, clean, old** — still reaped (NFR4).
9. **Slash-bearing branch** (`ci/rule-metrics`) — `safe_branch` differs from the raw name; the
   lease key still resolves. Guards the #7408 class against a re-introduction by this change.
10. **No lease library** (`session-state.sh` removed from the fixture root) — nothing reaped, for
    worktree-bearing **and** worktree-less branches, and the reworded `[warn]` block is emitted.
11. **R6b unchanged** — a decoy manifest claiming `soleur` is accepted and its payload executes.

### Edge cases

12. **Branch ref vanishes between snapshot and read** — `git log` on it exits 128; the function
    continues and still reaches `cleanup_orphan_worktree_dirs` (NFR1).
13. **`$GIT_ROOT` on a detached HEAD** — `current_branch` read is empty; the whole main-update
    block is skipped with the marker, and the function does not abort.
14. **Two worktree-less stale branches, first held, second not** — both are evaluated; the loop
    does not stop at the first.
15. **Empty `all_stale_branches`** — the suite's own floor fails rather than reporting success over
    zero driven branches.

### Integration verification (for `soleur:qa`)

16. Run `/soleur:go` in this worktree and read the three `SOLEUR_PLUGIN_ROOT_RESOLVE` lines: all
    three gates report `verified=true`, and the session-start gate either dispatches or names a
    reason — never silence.
17. `bash plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh list` prints both
    `SOLEUR_WORKTREE_LEASE_LIB_OK` and `SOLEUR_WORKTREE_REAP_CAPABILITY=branch-keyed-guards-v1`.

## Success Metrics

- `SOLEUR_SESSION_START_SKIPPED reason=plugin-root-unverified` no longer occurs on a Devin CLI host
  that carries a Soleur plugin cache; the session either runs the gates or names a specific reason
  (`cloud-session verdict=<v>`, `reaper-capability-unverified`, `classifier-absent`).
- Zero branch deletions by `cleanup-merged` for branches holding a live lease, measured by the new
  suite rather than by absence of complaints.
- The recipe-divergence count between `go.md` and the shipped fleet goes from 70 occurrences in 69
  files to zero, enforced by a derived scan rather than a member list.

## Dependencies & Prerequisites

- **#8400 → #8401 is a real ordering dependency inside this PR**, and it is only *partially*
  satisfied by Phase 1: Phase 1 closes the guard gap in the repository's script, and Phase 2's
  capability gate is what makes that closure reach the artifact a Devin session would actually run.
  Both must land before the resolver arms move; a commit order that widens the resolver first
  reintroduces exactly what ADR-179 forbids.
- Phase 3 commit 1 (guard strengthening) must precede commit 2 (the sweep).
- No external service, credential or infrastructure prerequisite.

## Risk Analysis & Mitigation

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| The lease-key swap over-holds and cleanup stops reaping | Medium | Low (refs accumulate; recoverable) | Bounded by the lease window and `sweep_orphan_leases`; Test 3 and Test 8 are must-PASS controls that reaping still happens |
| On a torn install (no `session-state.sh`) branch cleanup now stops entirely, not just worktree cleanup | High on that install class | Low (accumulation), and it is the intended fail-closed direction | Stated in the PR body as a behaviour change, not a footnote; the per-branch `(skip) … lease library missing` line keeps it visible; the `[warn]` block already names the one-line restore |
| The capability gate becomes a permanent skip on a customer whose install never updates | Medium | Medium (session-start maintenance silently stops) | The skip is **named** (`reason=reaper-capability-unverified`), not silent, which is the whole marker doctrine here; the reason string tells the operator to update the plugin |
| The 69-file sweep lands something wrong-but-uniform | Medium without commit 1 | High (customer-shipped surface) | Commit 1 strengthens the guard to pin content before commit 2 exists; the derived scan reaches the three sites the byte-identity test cannot see |
| The ADR-179 amendment is read as promoting the identity preflight to authentication | Medium | High (an overstated security claim in a shipped record) | A11 and R6b are left untouched and re-stated; the PR body carries the scope note verbatim; FR/NFR5 makes a red R6b a blocking condition |
| Renumbering churn if review asks for a new ADR instead of an amendment | Low | Low | The ordinal is marked provisional and the renumber-sweep obligation is stated in the ADR section |
| The new bash suite is vacuous (passes over zero driven branches) | Medium — this is the common failure shape for fixture suites | High (a green guard over an unfixed defect) | Mutation row 4 and Test 15 make the floor an asserted property; every mutant is `diff`-confirmed to have landed |

## Future Considerations

- The four scope-outs in Phase 4 each get an issue; the `[gone]`-is-not-`merged` one is the most
  likely to become a real incident and is the natural next change in this function.
- `mk_root`'s fixture cache is always in-sync with `$PAYLOAD`, so no test in this repo can exercise
  a genuinely stale cache. A fixture that *pins* an old copy of `worktree-manager.sh` would let
  R11 assert the capability gate against the real hazard rather than a synthesized absence. Worth
  doing once the token exists.
- If a second capability ever needs gating, `SOLEUR_WORKTREE_REAP_CAPABILITY` should become a
  space-separated set rather than a single token, and the fence should test for membership. Not
  built now (YAGNI), but the token's name is chosen so it can.

## Documentation Plan

- ADR-179 decision 11 amendment (Phase 2 step 4) — the primary record.
- `plugins/soleur/devin/INSTRUCTIONS.md` §Detection — becomes the single place the identity-selected
  recipe is written out in full, since the plugin `AGENTS.md` rule now points here.
- `plugins/soleur/AGENTS.md` rule `[id: cloud-detect-before-pipeline]` — pointer.
- `model.c4` — two edge descriptions.
- PR body — the `Closes` lines, the behaviour-change note about torn installs, and the shape-check
  scope note quoted from ADR-179 A11.

## References & Research

### Internal references

- `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh` — the `[warn]` block, the reap
  loop, `_safe_worktree_name`, `_acquire_worktree_lease`, `cleanup_orphan_worktree_dirs`.
- `plugins/soleur/commands/go.md` — Steps 0.0 / 0.5 / 0.
- `plugins/soleur/test/go-session-gates.test.sh` — R5c, R6b, R8, R9, R10, `mk_root`, `deliver`,
  `extract_fence`, `resolver_snippet`, `code_lines`, `R1_EFFECT`.
- `plugins/soleur/test/devin-cloud-mode.test.ts` — the marker-fleet drift pin.
- `plugins/soleur/test/worktree-manager-safe-branch-sanitization.test.sh` — the harness this plan's
  new suite copies.
- `knowledge-base/engineering/architecture/decisions/ADR-179-...` — decision 11, A10, A11, the
  Codex divergence note, the recorded fleet inconsistency.
- `knowledge-base/engineering/architecture/decisions/ADR-178-shared-bash-primitives-ship-in-plugin.md`
  — §Context, "unrecoverable".
- The learnings enumerated under `## Research Insights`.

### External references

None. Phase 1.6 recorded the decision to skip external research: every authority for this change is
in-repo (the script, the ADRs, the test harnesses), and the topic has no external API, library or
vendor surface.

### Related work

- #8308 — restored Step 0's session-start gate and added the Devin cache arms to Step 0.5; the
  parent of all three issues here.
- #7409 / ADR-178 — shipped `session-state.sh` inside the plugin; the reason a lease layer exists
  to key on at all.
- #7408 — the slash-bearing-branch derivation defect; the reason `_safe_worktree_name` exists and
  the reason the lease key and the worktree basename agree.
- #7442 / #7474 — the silent-skip and identity-is-not-freshness classes the marker doctrine in
  `go.md` comes from.
- #8159 / #8205 — the Devin cloud-parity and matcher-audit work this sits inside.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder
  text, or omits the threshold will fail `deepen-plan` Phase 4.6. Fill it before requesting
  `deepen-plan` or `soleur:work`.
- **The line numbers quoted throughout this plan were accurate on 2026-09-20 and will drift the
  moment Phase 1 edits the file.** Every edit and every assertion anchors on content — marker
  comments, heading anchors, function names, literal strings — never on a line number
  (`cq-cite-content-anchor-not-line-number`).
- **`devin-cloud-mode.test.ts` is expected to be RED between Phase 3 commit 1 and commit 2.** A
  `soleur:work` run that treats the intermediate red as a failure and "fixes" it by weakening the
  new assertions has destroyed the entire point of the ordering.
- **`go-session-gates.test.sh` R6b is a MUST-PASS row that asserts a limitation.** If it goes red,
  do not fix the row. Something has added the trust assertion ADR-179 A11 rejected, and A11 must be
  superseded first.
- **STRUCK — this claim was FALSE, and it is recorded rather than deleted because the way it was
  made is the lesson.** An earlier revision carried a sharp edge asserting "R6b will go RED the
  moment the capability gate lands, unless `mk_decoy_root` plants the token", marked *"Verified at
  plan time"*. It was **reasoned from reading the fixture, never executed**. Plan review
  reproduced R6b's session-start leg for real and measured the opposite: the decoy
  `cloud-detect.sh` runs **first** and prints `DECOY_EXECUTED …`, which is neither `local` nor
  `not-local:no-devin-env`, so `SESSION_OK=false`, the `elif` arm fires, and **the decoy
  `worktree-manager.sh` is never reached today** — the capability check sits downstream of a gate
  that already refuses. R6b stays green with or without the token, and `decoy_ran()` is
  `[ -s "$DECOY_LOG" ]`, a single boolean over a shared ledger that the decoy *classifier* has
  already written to, so it cannot say which decoy ran.
  **The real finding, which is more useful:** R6b's session-start leg is a witness that a
  *classifier* under a claimed root executes — a legitimate A11 witness — and is **not**, and after
  this change still will not be, a witness that a decoy *reaper* executes. `R11` does all the real
  work for the mutating dispatch. A decoy-reaper witness would need a decoy whose `cloud-detect.sh`
  prints `local`.
  **Never write "verified at plan time" for a claim that was not executed.**
- **The derived negative scan will match this guard's own body.** The detector pattern contains the
  literal it searches for. The allowlist is exactly one path and the suite asserts that. Do not
  grow it.
- **The lease widening does not close the whole worktree-less class.** It covers "a lease outlived
  its worktree". A plain-clone session mints no lease and is covered only by the ten-minute
  commit-age grace and the arming hold. Say that in the PR body; do not claim the class is closed.
- **Phase order is load-bearing, not stylistic.** Phase 1 produces the capability token; Phase 2
  consumes it. Running Phase 2 first ships a fence whose `grep -q` can never match, i.e. a
  permanently skipped session-start gate that looks like a working one.
- **The PR body must not describe the identity preflight as authentication.** It is a shape check;
  a planted `{"name":"soleur"}` directory passes. This is consistency and defence-in-depth.

## Plan Revisions

Recorded so a reader can see which claims were falsified and by what, rather than reading a plan
that looks like it was right the first time.

| # | Revision | Source | What it changed |
|---|---|---|---|
| R1 | Phase 2 rewritten from "move the arms into the shared resolver" to "capability-gate the dispatch, then move the arms, then amend the ADR" | CTO domain review, verified against ADR-179 §"Why arm 3 is confined to Step 0.5" | The brief's mechanism is named and forbidden by the ADR, on a second ground (`head -1` selects a *cached copy* of unknown age) that Phase 1 does not close. The proposed `R5c`-analogue row could not have caught it: `mk_root` copies `$PAYLOAD`, so the fixture cache is always in-sync |
| R2 | The capability gate's coverage enumerated per gate, not just for the reaper | Advisor consult (ADR-083 gate) | Ground 2 is a property of the *arm*; the arm now sits in three fences. `cloud-detect`'s exec was already dispositioned by ADR-179; `readiness`'s is a **new** acceptance and the amendment records it as one |
| R3 | Check-path / exec-path pinning made an explicit requirement + Guard 2 row 10 | Advisor consult | A `grep -q` that re-resolves is check-A / execute-B across two `head -1` calls — the same defect one level down, and invisible to every behavioural row |
| R4 | `mk_decoy_root` must plant the capability token | Advisor consult, verified against `go-session-gates.test.sh` | R6b asserts the decoy EXECUTES for **all three** gates. A token-less decoy plus the new gate turns a MUST-PASS row red. Planting the token restates A11 (a declaration is forgeable); relaxing the gate would contradict it |
| R5 | The lease widening's actual coverage narrowed in the prose, and the residual stated | Advisor consult | Every lease is minted alongside a worktree, so the arm covers "a lease outlived its worktree" — not "a plain-clone session on a merged branch", which mints no lease and is covered only by the grace window and the arming hold |
| R6 | Phase 3's exemption mechanism designed before the sweep, and the detector widened from one literal to the shape | Advisor consult + the absence-grep-self-match and universal-negative sharp edges | The scan matches the guard's own body; a path allowlist retrofitted after 69 edits is the rework. Exactly one allowlisted path, asserted. And `-name cloud-detect.sh` is one spelling of "selects by filename" |
| R7 | `reset --hard HEAD` scope narrowed to the non-bare arm, the dropped freshness side-effect role named, and its retention justified | Advisor consult + the defence-relaxation sharp edge | The bare layout never reaches it. Skipping the block when parked off `main` drops the "branch from latest" pull for that run — a stale base is recoverable, discarded work is not |
| R8 | Quality Gates now name `bash scripts/test-all.sh` as the authoritative invocation, plus the 21-file consumer sweep | The gate's-own-invocation and executes-these-bytes sharp edges | A hand-enumerated file list is pinned to a different set than the gate; the orphan suites under `skills/*/test/` are the ones a name-matched re-run misses |
| R9 | Premise corrections 1–3 in `## Research Insights` | Direct measurement | The three resolver copies are all in `go.md` (not `go.md`/`SKILL.md`); the fleet is 67 blocks / 69 cohort files (not ~74); widening Step 0 does **not** make a Devin *cloud* session dispatch, because the classifier gates it a second time |

### Verification log (shell forms live-executed at plan time, 2026-09-20)

| Command | Result |
|---|---|
| `bash plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh list` | prints `SOLEUR_WORKTREE_LEASE_LIB_OK path=…` in ~0.05s — the `discoverability_test` |
| `git log -1 --format=%ct refs/heads/<absent>` | `rc=128`, `fatal: ambiguous argument` — confirms the `\|\| true` requirement in Phase 1 step 7.1 |
| `python3 scripts/lint-guard-contract.py <this plan>` | `scanned 1 plan file(s), 1 with a Guard Contract, 3 guard entries`, rc 0 |
| `git grep -l 'worktree-manager.sh' -- '*.test.ts' '*.test.sh' '.github' 'scripts' '.claude'` | 21 files — the consumer sweep list |
| `grep -rl 'soleur-cloud-mode:start'` / `grep -rn 'find /opt/\.devin/plugins -name'` | 67 marker blocks; 70 occurrences in 69 files |
| `python3 -c "…json… package.json scripts"` | `test` is `bash scripts/test-all.sh` — the authoritative gate invocation |
| `gh label list` | `deferred-scope-out`, `domain/engineering`, `meta/machinery`, `priority/p3-low`, `type/bug` all exist — the scope-out issues' labels are real |
| `grep -oE 'knowledge-base/[^ ]+\.md' <this plan> \| while read f; do [ -f "$f" ] \|\| echo BROKEN; done` | no output — every cited knowledge-base path resolves |

### Scoped advisor consult (Phase 4.5)

Run against a curated payload (Overview + phases + the riskiest phase), not the transcript, per
ADR-083. It returned R2–R7 above. Its one flag rather than recommendation — *"P1 keeps
`reset --hard HEAD` and only reorders it; discarding uncommitted work in the operator's main
checkout as a side effect of cleanup deserves an explicit justification in the PR body, or
deletion"* — is answered in Phase 1 step 4 and carried into the Documentation Plan as a required
PR-body line.

## Plan Review Consolidation (7-agent panel)

Panel: DHH, Kieran, code-simplicity, architecture-strategist, spec-flow (5-agent eng panel, escalated
by the `single-user incident` threshold) + CTO (devex lens) and CPO (product sign-off, relevance-gated).
**This section is authoritative where it conflicts with an earlier section.** Every finding below was
re-verified against the tree before adoption; the panel's own measurements are marked.

### Blocking corrections — these change what gets implemented

**B1. The capability gate narrows to the `devin-cache` arm.** (DHH: cut it entirely; code-simplicity:
narrow it; both fired on the same scope, and the consolidation rule prefers the smaller mechanism.)
The arm-agnostic form had a **live blast radius measured by the panel**: after it landed, *every*
root whose `worktree-manager.sh` predates Phase 1 — every long-lived worktree in this repository on
a pre-merge branch, and every marketplace install between releases — would emit
`reaper-capability-unverified` and stop reaping. The gate now reads
`[ "$SRC" = devin-cache ] && ! grep -q <token> …`, which closes ADR-179's ground exactly and leaves
the token arm untouched. The ADR amendment shortens accordingly: the confinement was never about
resolution, it was about this one `bash` call, and it now says so.

**B2. The gate must not take the non-destructive work with it** (spec-flow A2, new FR8d). `git
worktree list` sits *inside* the same `[ -f … ]` then-arm as the dispatch; the `.mcp.json` restore
is deliberately its sibling. `want_not_in "$out" "STUB_WORKTREE_MANAGER"` passes for three different
implementations, one of which kills all three gates together — the defect #8401 exists to fix.
R11 gains positive `want_in`s, and Guard 2 gains a *hoist the `grep -q` above the `[ -f ]`
structure → RED* row.

**B3. The session-start fence executes TWO artifacts from the resolved root, not one**
(architecture H1, verified: `go.md` `SESSION_VERDICT="$(bash "${ROOT}/scripts/cloud-detect.sh" …)"`).
The enumeration marked `cloud-detect.sh` "already dispositioned, unchanged by this plan" — false for
*this* fence, whose root was never cache-resolvable before. Worse, it made the blast-radius bound
**circular**: premise correction 3 argues a Devin cloud session still will not dispatch *because the
classifier says so*, while the change makes the classifier itself cache-resolvable. Honest severity:
`cloud-detect.sh` is 4 days old and its only other commit touched comments, so no divergent cached
copy exists today — this is structural, not live. **Resolution:** state the invariant as *the gate
covers every artifact in the dispatch **decision chain**, not only the artifact dispatched*, and
implement it (a second capability grep on the classifier, same path-pinning rule). Add a Guard 2
mutation row for the classifier — no current row touches it.

**B4. Fold the `[gone]` ancestry check into Phase 1** (architecture H2). It was scoped out as "a
different cohort", which is true in isolation — but Phase 2 newly exposes precisely that cohort:
the Devin CLI plain-clone session, where **nothing mints a lease at all**. The residual reduces to
*merged-or-`[gone]`, no lease, no commit in 10 minutes* → `git push origin --delete` (closes the PR)
then force-delete. That is the single worst outcome in the change. `git merge-base --is-ancestor` is
two lines inside the existing `if`. Fold it in; do not defer it.

**B5. Two new sentinels red an existing CI gate** (Kieran P0-1, measured with both regexes).
`apps/web-platform/test/git-lock-marker-telemetry.test.ts` derives its scan set from
`plugins/soleur/skills/*/scripts/*.sh` — which includes `worktree-manager.sh` — and collects
sentinels wholesale. Both new literals score `collected=yes, mirrored=false` and fail
`expect(...).toBe(1)`. `apps/web-platform/server/git-lock-marker-telemetry.ts` joins
`## Files to Edit`, that suite joins `## Quality Gates`, and FR13 states each sentinel's
disposition.

**B6. The Phase 1 fixture MUST pre-stamp `$(_session_state_root)/reaper-armed`** (CTO-devex, HIGH;
independently confirmed). Without it Test 3 fails, Tests 1-2 pass for the wrong reason, and Guard 1
mutation rows 1-2 — the plan's entire proof that the lease widening works — do not go RED. The
harness model is `lease-protects-active.test.sh`, which is the only file in `plugins/soleur/` other
than the script that mentions `reaper-armed`. Prefer **adding scenarios to that suite** over a tenth
`worktree-manager-*` file; if a separate file is kept for the mutant-copy style, say which harness
contributes what (`safe-branch-sanitization.test.sh` for the `diff`-confirmed mutant technique,
`lease-protects-active.test.sh` for the reap fixture and the arming stamp).

**B7. Phase 2's internal order is inverted** (spec-flow E2). As numbered, step 2 alone reds nothing
(see B10) but step 3 alone reds **R9** (`others == 0`), discovering at CI a row the plan itself says
"must be rewritten as part of the change, not discovered at CI" — and inverting
`cq-write-failing-tests-before`. **New order: harness first** (R9 predicate rewritten, R5d/R11 added
RED, `mk_root` gains a token-less mode) **→ gate → arms → ADR.**

**B8. Phase 1 step 4 over-corrects** (Kieran P1-2). The defect is `reset --hard` on a **dirty**
off-main checkout. Skipping reset *and* checkout *and* pull for every off-main checkout also removes
the **clean** case, where today's code safely checks out `main` and pulls — the ordinary state of a
plain-clone dogfooder. Minimal correct fix: **gate only the `reset --hard` on being on
`main`/`master`**; leave the clean-tree `checkout main` + `pull` reachable.

**B9. `work/SKILL.md` has TWO fail-opens, and the plan closed one** (Kieran P1-4). Verified: even
when `GUARD` resolves **and the guard refuses**, `git commit` runs anyway — no `&&`, no `|| exit`,
no `if`. FR11 as written would ship a marker on a backstop that still cannot block a commit.
Restructure so the commit is reachable only through a guard that resolved *and* passed. The
Problem Statement's implicit claim that the guard works when it resolves is corrected.

**B10. The dual lease key is KEPT, and its rationale corrected** (Kieran P1-1, overriding
code-simplicity's cut). code-simplicity cut it as defending a state "the plan proved cannot exist".
Kieran found a **live** divergent producer: `switch_worktree`'s LEGACY-NESTED FALLBACK reassigns
`worktree_path="$WORKTREE_DIR/$worktree_name"`, so `switch ci/foo` against `.worktrees/ci/foo` leases
key `foo` while `_safe_worktree_name "ci/foo"` is `ci-foo`. The dual key is right; the rationale
("a legacy pre-#7408 layout") was a guess that happened to land correctly. Write it as the live code
path it is, or a future simplification deletes it as dead. Also: the edit is **two** changes, not
one — the path conjunct *and* the key spelling — and the key change is the one that can regress.
`switch_worktree`'s own "since #7408 that equals the SLUG" comment goes stale and is in scope.

### Corrections to measured claims

| # | Claim as written | Measured | Source |
|---|---|---|---|
| C1 | "R6b will go RED unless `mk_decoy_root` plants the token — verified at plan time" | **False.** Reproduced live: the decoy classifier's banner is not an accepted verdict, so `SESSION_OK=false` and the decoy reaper is never reached. R6b is indifferent to the gate. The claim was reasoned, not executed. | Kieran P0-2 |
| C2 | "No test drives the reap loop end-to-end today" | **False.** `lease-protects-active.test.sh`, 1015 lines, does exactly that. | CTO-devex |
| C3 | The arming hold covers the worktree-less residual | **One-shot per repository.** The stamp is written before the loop so it cannot re-arm. Coverage for session 2 onward is the commit-age grace **alone**. | spec-flow B2, architecture H2 |
| C4 | Guard 3's derived population is "69 files / 70 occurrences" | **71 files** by the stated derivation; 69/70 is the *narrower* `find … -name` grep. Two members unnamed: `plugins/soleur/commands/go.md` (the canonical correct recipe — the best must-PASS witness available) and `plugins/soleur/test/go-session-gates.test.sh`. The non-vacuity floor was calibrated on the wrong number. | architecture M4, spec-flow P1 (both independently) |
| C5 | Test 13: "detached HEAD — `current_branch` read is empty"; step 7.4: "a detached or corrupt HEAD exits non-zero" | **Detached HEAD → `HEAD`, rc 0.** Unborn HEAD → `HEAD` on stdout, rc 128. `\|\| true` is still required, for the *unborn* case. Test 13 as written would pass through the `!= main` arm — green for a reason its description denies. | Kieran P1-3, confirmed independently |
| C6 | Verification-log census commands | The spellings shown return **79 files / 78-in-72** repo-wide; the 67 and 70-in-69 figures are correct only scoped to `plugins/soleur/`. The scoping is right; the log must show the command actually run. | Kieran P2-1 |
| C7 | "ADR-179 §'Why arm 3 is confined to Step 0.5'"; "two grounds"; "names two guards outside #8400's list"; "the collision gate has nothing to catch" | Not a section (a bolded run-in sentence in Decision 11). "Two grounds" is this plan's restructuring — the ADR argues one ground and states the stale-cache point as a forward directive. "That list" means the ADR's own enumeration, not #8400's. `check-adr-ordinals.sh` guards **filename** ordinals only; there is no gate on decision/amendment ordinals. | Kieran P2-5 |
| C8 | ADR-179 A10 restated flatly as establishing braced-token substitution on the skill surface | A10's own item 5 says **"Do not restate this as 'proven' flatly"** — it was measured with a synthetic single-skill plugin, one session, one environment. One clause fixes it. | Kieran P2-6 |

### Adopted simplifications

- **Cut R5e** (the readiness behavioural row): R8 byte-identity + R9 counts + R5c already cover it.
- **Cut the "exactly one allowlisted path" mechanism.** Assemble the detector pattern from fragments
  so the guard does not quote its own forbidden literal; the allowlist and the assertion-about-the-
  allowlist both disappear. This also resolves C4's awkward question of whether
  `go-session-gates.test.sh` would need to be allowlisted too.
- **Cut set identity in favour of a derived form**: assert the cardinality **and** that every
  `plugins/soleur/skills/*/SKILL.md` is marked — derived, not a committed 67-path list that every
  new skill must edit.
- **Cut Guard 2's proposed `${#GATE_ANCHORS[@]}` harness row** (Kieran P2-3): R10 already carries an
  independently-derived count three lines below (`grep -c '^```bash$'`), which reds if the array
  shrinks. The stated justification was false.
- **Drop the `-v1` suffix**; test **membership** in a space-separated value from day one
  (`case " $VAL " in *" branch-keyed-guards "*`). A version literal re-imports the version-sniff
  failure mode the Alternatives table rejected; set membership is additive forever.
- **Demote `SOLEUR_WORKTREE_MAIN_UPDATE_SKIPPED`** out of the `SOLEUR_*` family, or justify it: a
  non-bare clone parked on a feature branch is the *ordinary* developer state, and the file's own
  doctrine reserves sentinels for anomalous states. (Interacts with B5 — a plain human line in the
  style of `Updated main to latest` needs no telemetry disposition at all.)

### Operator-experience conditions (CPO sign-off: SIGNED-OFF WITH CONDITIONS)

- **CPO-C1 / spec-flow A1 / CTO-2a — both fail-closed states must name the ACTION.** `go.md` already
  carries an operator marker-interpretation list where every reason gets plain-language cause,
  remedy and a defect-vs-configuration disposition. Add a row for `reaper-capability-unverified`
  (*"your plugin install predates the branch-keyed reap guards — a stale install, not a defect:
  `claude plugin update soleur@soleur-marketplace` or `devin plugins update soleur`, then restart"*),
  and put that list in `## Files to Edit` — it was not there. Emit `source=${SRC}` on the refusal so
  the operator learns *which* root was refused; the three arms have three remedies.
- **CPO-C1b / spec-flow C1 — the torn-install remedy is printed on the invisible stream.** The
  `[warn]` restore line goes to **stderr**, which this plan says twice is invisible under
  `claude --bg`. FR5 as written rewords a line nobody in that mode sees. Carry the fix on the
  **stdout** sentinel, and correct the remedy itself: `git checkout origin/main -- plugins/…` cannot
  work for a marketplace user with no Soleur checkout. Both states share one remedy: update or
  reinstall the plugin.
- **spec-flow B1 — the destructive event is the only event here with no sentinel.**
  `Deleted remote branch:` is `verbose`-gated, i.e. invisible in the mode this runs in. Emit
  `SOLEUR_WORKTREE_REAPED branch=<b> local=<y/n> remote=<y/n>` unconditionally on stdout, with a
  one-line recovery pointer on the summary. Add it to `## Observability`.
- **CPO-C2 — file the plain-clone residual as its own scope-out issue** with a re-evaluation
  criterion. It is the residual on the destructive path and currently lives only in plan prose.
- **CPO-C3 — bind the no-authentication scope note to downstream copy.** `soleur:changelog`,
  `soleur:release-announce` and `soleur:feature-tweet` read PR titles and linked issues; #8402's
  title ("resolves the Devin cache by basename with no `name=soleur` check") will very plausibly
  generate *"prevents executing untrusted scripts."* State in the PR body that generated copy must
  say "consistency and defence-in-depth", never "prevents"/"protects"/"secures". Keep `type/bug`;
  do **not** add `type/security`.
- **CPO-C4 / spec-flow D4 — split Phase 3 commit 2** into **2a** (canonical block + the 67-file
  mechanical marker sweep, verifiable by re-running the sweep), **2b** (the three bespoke
  non-marker sites), and **2c** (`work/SKILL.md`'s executable `GUARD=` line + B9's fail-open fix —
  a behavioural change that must not hide inside a 67-file uniform diff).

### Ambient-dependency findings (the standing `cq-ac-must-not-depend-on-concurrent-sessions` check)

- **X1 (HIGH, spec-flow + Kieran P2-7) — `/opt/.devin/plugins` is an absolute path with no
  override.** `run_gate` overrides `$HOME`, so the `$HOME` cache arm is contained; `/opt` is not.
  On a host with a populated `/opt/.devin/plugins` carrying a `"name":"soleur"` manifest — i.e.
  **exactly a Devin CLI host, the audience #8401 exists for** — pre-existing MUST-PASS rows change
  verdict with no diff change: R4 (`source=none`), R6 (`verified=false` on the evil decoy, which
  falls through to `/opt`), R6c (`dispatched nothing`). The exposure exists today for one fence;
  Phase 2 **triples** it. **Resolution required before implementation:** add an override
  (`SOLEUR_DEVIN_CACHE_ROOTS` or equivalent) consumed by the fences and set to a scratch path by
  `run_gate`, or add an AC naming the dependency and the hosts on which the suite is not
  authoritative. Do not ship a MUST-PASS suite whose verdict is a property of the machine.
- **X2 (HIGH) — Test Scenario 16 dispatches the real reaper.** "Run `/soleur:go` in this worktree"
  runs unstubbed `cleanup-merged` against the operator's shared bare repo while sibling worktrees
  exist, as the verification step for a change to the reaper. Replace with an isolated fence
  invocation in the `go-session-gates.test.sh` style, or a scratch `SOLEUR_SESSION_STATE_ROOT` plus
  a stubbed manager.
- **X3 — the `discoverability_test` asserts a property of the machine.** Matching
  `SOLEUR_WORKTREE_LEASE_LIB_OK` fails exactly in the torn-install state this plan documents as a
  *supported, fail-closed* state. A supported state must not red a quality gate. Either probe a
  property of the diff, or state the precondition.
- **X4/X5 — the 21-file consumer sweep and the `merge-base origin/main` lint** are both tree/clone
  state. Keep them as guidance; do not phrase them as acceptance criteria.
- **X6 — Success Metric 1 has no measurement path.** `/opt` is not writable under test, only the
  `$HOME` arm is fixture-exercisable, and layer 7 has no sink. Restate it as a property a test
  asserts, or drop it.

### Recorded, not adopted

- **DHH: cut the capability gate entirely** in favour of `SRC != devin-cache` (resolve but never
  dispatch from a cache root). Sound and smaller, but it does not deliver #8401's stated acceptance
  (`source=devin-cache` reaching the stubbed manager) and would make `Closes #8401` a claim the
  change does not support. Narrowing (B1) keeps the outcome and removes the blast radius.
  **This is a User-Challenge — it changes what "closes #8401" means — and is recorded as DC3.**
- **DHH: cut the `refs/heads/$branch` grace arm** (it buys little on both cohorts, by this plan's
  own measurement). **Not adopted**, on code-simplicity's counter: after C3 it is the **only**
  cover for the plain-clone residual, and at `single-user incident` thin cover beats none.
- **DHH: ~600-line target, merge the five repeated refrains to one home each, cut the
  "not applicable" gate sections and `## Plan Revisions`.** The repetition finding is correct and
  the refrain-merge should happen; the gate-section records stay, because a later reader cannot tell
  "assessed and not applicable" from "never considered".
- **CTO-devex: commit the sweep as `plugins/soleur/scripts/sync-cloud-mode-block.sh`.** The
  detection-vs-synchronisation distinction is right and the script is being written anyway. Deferred
  only because it enlarges an already-large PR; **filed**, with the trigger being the third
  fleet-wide edit.
- **CTO-devex / spec-flow P2 / Kieran P2-8: the canonical block grows ~8× and is replicated 67× into
  bodies that load into agent context.** No gate fires (`description:` is untouched), and the plan
  never measured it. **Measure the delta before the sweep**, and decide then whether the fleet gets
  the full recipe or a pointer to `devin/INSTRUCTIONS.md` §Detection — the treatment already chosen
  for `plugins/soleur/AGENTS.md`. Changing this after 67 files are edited is the rework.
  The irreducible core is the **root-resolution recipe only**: a pointer cannot carry it, because
  reading `INSTRUCTIONS.md` requires the root the recipe resolves. That bootstrap circularity is
  worth one sentence in the ADR so it is not re-proposed.
- **architecture H3 / AP-025:** the gate is a boundary interceptor at one of three dispatch sites,
  where the register prescribes a self-refusal the artifact carries. **The deviation is necessary
  here** — a self-refusal cannot be retrofitted into copies that are already cached, which is
  exactly the population the gate exists for. Say so in the amendment rather than leaving it
  unexamined, and pair it with a carried refusal as the durable control.
- **architecture M3 — the C4 sweep must cover ELEMENT descriptions, not only relationships.**
  `model.c4` element `plugin` says `session-state.sh` "gates worktree **reaping**" — falsified by
  Phase 1 extending it to branch deletion, the *identical* falsification P3 requires be fixed in the
  script banner. Same sentence, same widening, one surface swept and one not. Adopted into the C4
  task; recorded here because the method gap (relationships only) is the reusable lesson.
- **architecture M7 — number the new invariant `A16`** rather than burying it in decision 11 prose;
  the A10-A15 series exists and Guard 2 cites the amendment as its integrity anchor.
- **architecture M1/M2 — the token decays to a constant** (once cache populations turn over it is
  permanently true) while the confinement it replaces is lifted **permanently**. Record the
  asymmetry and a renewal discipline: any future change to the reaper's destructive surface mints a
  new capability. And correct the `head -1` claim — the gate makes a **pre-capability** wrong pick
  fail closed; a wrong pick that carries the token still runs. Leave that as a named residual.
- **architecture M6 — Step 0.0's acceptance is argued on the wrong axis.** "Read-only, no `git`
  mutation" drops the limb ADR-179 was careful to include: the verdict **steers the agent**.
  Concretely, `git-repo-readiness-diag.sh`'s output is a STOP/GO decision for the whole session and
  feeds `SOLEUR_GIT_REPO_DIAG` into Better Stack. Probably still acceptable — but argue it on the
  axes that apply.
- **spec-flow A3 — the RESOLVE echo's placement is undecided.** Moving the arms inside the anchors
  means the arm's own `echo` moves too; nothing pins "exactly one RESOLVE line per gate"
  (`grep -F` is a presence check). Decide it, add the row, and add a `source=` value for a
  searched-but-unmatched cache (`devin-cache-nomatch`) — otherwise "no cache directory" and "a cache
  with no Soleur manifest" collapse into `source=none` with two different remedies.
- **spec-flow A4 — Phase 2 falsifies an existing operator bullet** (`source=none` on a
  read-from-disk harness → "set `CLAUDE_PLUGIN_ROOT`") the moment a third arm runs there. The plan
  applies the falsification test rigorously to a C4 edge and not at all to operator prose with a
  shorter path to a customer.
- **spec-flow D1/D2 — never push between Phase 3's two commits** (a pushed commit 1 is a genuinely
  red required check), and move the "intentional RED" note out of `## Quality Gates`, which is a
  merge checklist. State the merge condition positively: at PR head, the drift guard is green.
- **Kieran P2-2/P2-4** — raise `MIN_ASSERTIONS`; `mk_root` needs a *present-but-token-less* mode
  (its third parameter only omits a file), following the R3c/R3h overwrite pattern.
- **L1 (AP-023 mechanics)** — anti-vacuity floors report with `printf >&2` + `exit 1`, never through
  the suite's own `fail`/`bad` helper, and the case counter increments at the **call site**, never
  inside `$( )`. Applies to Guard 1's assertion floor and Guard 3's population floor.
- **CPO recommendation** — add one sentence to `## User-Brand Impact` naming the fleet-wide
  dimension `single-user incident` does not cover (the fail-closed block and the sweep are
  per-install *and* fleet-wide), and file a `meta/machinery` issue on the threshold-taxonomy
  inversion: `aggregate pattern` escalates nothing and trips `user-impact-reviewer`'s own exit
  clause, so the broader label buys **less** scrutiny.

### Panel verdicts

| Reviewer | Verdict |
|---|---|
| Kieran (correctness) | Not blocking on design; **blocking on P0-1 and P0-2** before RED-phase work |
| architecture-strategist | **PROCEED WITH REQUIRED AMENDMENTS** — three HIGH findings closed before implementation |
| DHH (simplification) | Over-architected, not uniformly; Phase 1 earns its ceremony, Phase 2 did not |
| code-simplicity | **Proceed with simplifications** — ~10-12% of hand-written surface; two to do before implementation |
| spec-flow | Strong plan; every finding is a journey gap, not a reasoning gap |
| CTO (devex) | One falsified premise propagating into a vacuous guard (HIGH); rest is shape advice |
| CPO (product) | **SIGNED-OFF WITH CONDITIONS** (C1-C4) |
