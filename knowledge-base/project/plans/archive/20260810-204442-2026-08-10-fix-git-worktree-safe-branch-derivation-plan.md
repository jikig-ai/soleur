---
title: "fix(git-worktree): derive safe_branch once — slash-bearing branches must not nest, run unleased, or be reaped"
date: 2026-08-10
type: bug-fix
issue: 7408
branch: feat-one-shot-7408-worktree-safe-branch-derivation
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# fix(git-worktree): derive `safe_branch` once in the worktree producer

`Closes #7408`

> **Lane note.** `knowledge-base/project/specs/feat-one-shot-7408-worktree-safe-branch-derivation/spec.md` does not exist (this plan is the first artifact on the branch), so `lane:` could not be carried forward. Defaulted to `cross-domain` (TR2 fail-closed).

## Enhancement Summary

**Deepened on:** 2026-08-10 (run inline by `one-shot`; the planning subagent reported it had substituted a five-agent panel for this skill, so the skill was re-run against `PLAN_PIPELINE_PREFIX`)

**Halt gates — all pass or correctly skip:**

| Gate | Result |
|---|---|
| 4.5 network-outage | skip — the only `ssh` hits are `NO ssh required` in `discoverability_test`; not a connectivity plan |
| 4.55 downtime & cutover | skip — no infra reboot/replace, no lock-taking DDL, no router change |
| 4.6 user-brand impact | **pass** — concrete body, threshold `single-user incident`, `requires_cpo_signoff: true` |
| 4.7 observability | **pass** — 5/5 fields non-placeholder, layer 7 cited, `discoverability_test.command` SSH-free |
| 4.8 PAT-shaped variable | **pass** — no match on any of the four shapes |
| 4.9 UI wireframe | skip — no UI surface (`.sh`, `SKILL.md`, ADR `.md`) |
| 4.10 encryption posture | skip — no new store or cross-component connection |

**Verification checklist — resolved live, not from memory:**

- All 4 cited rule IDs are **active** in `AGENTS.md`/`AGENTS.rules.md`: `cq-cite-content-anchor-not-line-number`, `cq-write-failing-tests-before`, `hr-observability-layer-citation`, `wg-ui-feature-requires-pen-wireframe`. No fabricated or retired IDs.
- `ADR-099-git-surface-topology.md` exists (plan edits, does not create — no ordinal derivation needed).
- Precedent suite `plugins/soleur/test/worktree-manager-sandbox-tmp-sweep.test.sh` exists.
- All seven named functions exist at content anchors; the enumeration **independently reconfirms** that `remove_worktree` does not exist and that `copy_env_to_worktree` does.
- No AC uses a repo-wide grep, so the self-matching-plan failure class does not apply here.
- Bash strict-mode risk is already handled: the plan states sourcing imports `set -euo pipefail` and the preamble `exit 3`s outside a git repo, so the suite sources inside the fixture repo.

### Key Improvement

**AC13 was withdrawn — it was an unsatisfiable acceptance criterion aimed at the implementer.** It mandated a `$PWD` guard in `cleanup_orphan_worktree_dirs` that revision **R3 had already cut as unreachable**, and that Phase 3b ("specified and then **cut**") and `tasks.md` 3b.5 ("Not added") both record as cut. Because `tasks.md` 5.3 said "Walk AC1–AC13", `/work` would have been driven to implement a guard the plan deliberately rejected — the exact "propagate the correction in the same pass" failure this skill's checklist names, since `tasks.md` is the contract `/work` executes against. Fixed in both files.

### Checked and Found Sound (no change)

- `copy_env_to_worktree` initially read as a gap — the reconciliation table names it while Files-to-Edit omits it. It is **not** a gap: R4 cut it deliberately (pure consumer, no refname caller, auto-detect path already `basename`s), the reconciliation row says so, and `tasks.md` 3.7 records it. Plan is self-consistent.
- ~~The merge-order analysis against PR #7407 is measured from `gh pr diff` — hunks are disjoint.~~ **FALSIFIED at review.** It was measured, and the measurement went stale within hours: #7407 grew from `+289/-75` to `+3070/-105` and now edits `MARKER_RE` in `git-lock-marker-telemetry.ts`, the exact expression this PR also edits. A measurement of a moving target is a claim with a shelf life — see §Merge-Order Dependency.

## Overview

`plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh` ships in the Soleur plugin and runs on customers' machines. Its **producer** (`create_worktree`) derives the worktree directory path and the session-lease key from the **raw git branch name**, while its **consumer** (`cleanup_merged_worktrees`) assumes a **slugified** directory name — and says so in a comment:

> `# This is essential because branch names use slashes (feat/fix-x) but worktree directories use hyphens (feat-fix-x), so we cannot construct paths from branch names.`

The invariant is already asserted in the codebase. The producer simply never honored it. For any slash-bearing branch that mismatch is not cosmetic — it is **unattended destruction of uncommitted work**, reachable today.

This plan makes the producer honor the invariant **by construction** rather than by convention: one shared derivation helper, used by every site that turns a branch name into a directory name or a lease key.

**Every claim in this plan was measured in a scratch repository, not inferred.** The measurements are reproduced inline below.

## Measured Mechanism

Each row was reproduced in a throwaway git repo (`git init -b main`, one commit) or by sourcing `.claude/hooks/lib/session-state.sh` directly. No row is derived from reading code alone.

| # | Step | Command | Measured result |
|---|---|---|---|
| 1 | Nesting is real | `git worktree add -b ci/rule-metrics .worktrees/ci/rule-metrics main` | Succeeds. `find` shows `.worktrees` → `.worktrees/ci` → `.worktrees/ci/rule-metrics` — **three levels** |
| 2 | Git registers the LEAF only | `git worktree list --porcelain` | `worktree …/.worktrees/ci/rule-metrics`. `.worktrees/ci` is **absent** from the registry |
| 3 | The reaper's glob sees the INTERMEDIATE | `for d in .worktrees/*/` | Yields `.worktrees/ci` with `has_dotgit=no`, `is_link=no`, `bare=no` — **every guard falls through** to `rm -rf --one-file-system -- "$dir"` |
| 4 | The lease is refused | `_validate_worktree_name 'ci/rule-metrics'` | **REJECT** (regex is `^[A-Za-z0-9._-]+$`) |
| 5 | …so creation runs unleased | `acquire_lease 'ci/rule-metrics' probe 5` | **rc=1**. Call site is `_acquire_worktree_lease … \|\| true` → creation proceeds **UNLEASED** |
| 6 | The slug is lease-valid | `acquire_lease 'ci-rule-metrics' probe 5` | **rc=0**; `is_lease_active 'ci-rule-metrics'` → **ACTIVE** |
| 7 | The fix shape works | `git worktree add -b ci/rule-metrics .worktrees/ci-rule-metrics main` | `.worktrees/ci-rule-metrics` at **two levels**; `rev-parse --abbrev-ref HEAD` → **`ci/rule-metrics`** (branch preserved); path is **REGISTERED** *and* `has_dotgit=yes` — double protection |

**Reachability.** `git ls-remote --heads origin | sed 's#.*refs/heads/##' | grep -c '/'` returns **29** (do NOT use `grep '/'` on the raw output — every line contains `refs/heads/`, so it matches all 60): `ci/*` ×14, `dependabot/*` ×8, `bot-fix/*` ×4, `gh-readonly-queue/*` ×2, `chore/*` ×1.

**Blast radius of the reaper.** `cleanup_orphan_worktree_dirs` runs at session start, `work` Phase 0, and `ship` Phase 7 Step 4. It reaps only directories that are **both** unregistered **and** `.git`-less, so a *registered* worktree is never its target — the defect here is that the nested layout puts an unregistered **intermediate** in its path. (It also carries no `$PWD` guard, unlike `cleanup_merged_worktrees`; that gap is real but unreachable given the registered+`.git` chain — see R3.)

## Research Reconciliation — Spec vs. Codebase

| Issue-body claim | Reality (measured) | Plan response |
|---|---|---|
| Slash-bearing branches nest, run unleased, get `rm -rf`'d | **CONFIRMED** — rows 1–5 above | Fix as scoped |
| 29 slash-bearing branches: `ci/*`, `bot-fix/*`, `chore/*` | Count **exact (29)**; composition also includes `dependabot/*` ×8 and `gh-readonly-queue/*` ×2, which the body omits | No scope change — `dependabot/*` is the *most* likely to be checked out by an automated flow, which strengthens the severity |
| "`switch_worktree` / `remove_worktree` symmetry" | **There is no `remove_worktree` function.** `grep -nE '^[a-z_]+\(\) \{' …` yields ~30 functions, none named `remove_worktree`; the nearest are `switch_worktree`, `copy_env_to_worktree`, `cleanup_worktrees`. The `main()` `case` block has no `remove` verb | Drop `remove_worktree` from scope. Apply the slugify to `switch_worktree` (operator convenience) and, load-bearingly, to `create_worktree`'s own `switch_worktree "$branch_name"` re-entry call. `copy_env_to_worktree` was considered and cut — it is a pure consumer with no refname caller (R4) |
| `create_for_feature` carries the same mismatch | **PARTLY FALSE.** The raw-vs-slug difference is real, but the *archival* consequence is not: the two `spec_dir`s have **different roots** — `create_for_feature` writes under `$worktree_path`, `cleanup_merged_worktrees` reads under `$GIT_ROOT` (the bare root), with an in-code comment saying that read is backward-compat for legacy pre-#2815 layouts. The in-worktree spec is never archived by that path for **any** branch name | Keep the slug change (the dir should match the worktree basename), but restate AC6 as self-consistency and drop the archival claim — see R6 |
| "Blast radius nil — `tr '/' '-'` is identity for every non-slash name" | **CONFIRMED for the real corpus.** All 29 slash-bearing branches, and **all** origin branches, are lease-valid under `tr '/' '-'` (0 failures, measured). All but one of 1530 committed spec dirs match `^[A-Za-z0-9._-]+$` | Proceed. The single exception (`verify-canusетool-caching-876`, which contains Cyrillic homoglyphs) is pre-existing and untouched by this change |
| Implied: `tr '/' '-'` makes the lease key valid | **FALSE IN GENERAL.** Measured: `feat+foo`, `fix(scope)/bar`, `user@host/topic`, `a,b/c`, `wip;x`, `ci/rule=metrics` are all valid git branch names that **still fail** `_validate_worktree_name` after `tr '/' '-'` | **AC3 is scoped to the measured corpus, not asserted universally.** Plan discriminates the residual class in telemetry (FR4) but does **not** abort — measurement showed the residual class has no data-loss path once nesting is fixed (see R1) |
| Secondary damage: `scripts/test-all.sh` assumes two levels | **CONFIRMED** — it prints `Run from a worktree instead: cd .worktrees/<name> && bash ../../scripts/test-all.sh` in its bare-repo guard | No code change needed; the fix *restores* the two-level assumption. Called out as a Test Scenario |

**Corroborating precedent (not in the issue body).** Three independent places already encode the flat-slug convention, so this fix conforms the producer to a convention the rest of the system has always assumed:

1. `cleanup_merged_worktrees`'s own comment and its `safe_branch=$(echo "$branch" | tr '/' '-')`.
2. `apps/web-platform/test/server/inngest/cron-claude-eval-substrate.test.ts` asserts the bot-fix agent may run `git worktree add .worktrees/bot-fix-4321-foo -b bot-fix/4321-foo origin/main` — branch slashed, directory flat.
3. `plugins/soleur/skills/fix-issue/SKILL.md` documents the fallback `git worktree add .worktrees/bot-fix-<ISSUE_NUMBER>-<SLUG> -b bot-fix/<ISSUE_NUMBER>-<SLUG> origin/main`.

**A fourth, independent copy of the transform exists** at `plugins/soleur/skills/archive-kb/scripts/archive-kb.sh` (`safe=$(echo "$branch" | tr '/' '-')`). It runs in a separate process with no path-safety role, so it is **not** edited by this plan — but it is named in the PR body so a future edit to the transform knows the full call set.

### Live evidence that directory↔branch divergence is already reachable

Enumerating every worktree on this machine and comparing `basename` against `rev-parse --abbrev-ref HEAD` returns one divergence **today**:

```
DIVERGES: dir=fix-6808-heartbeat-wire  branch=docs-redaction-fails-open
```

This is a **pre-existing defect unrelated to slug derivation** — neither name contains a slash, and the measured corpus contains **zero** slug collisions. `create_worktree`'s existing-directory arm switches to it automatically under `--yes` without announcing the mismatch. A guard for this was drafted as FR5 and then **cut to its own issue** (R2): that arm is the resume path for `one-shot`/`work`, and turning it into an abort inside a data-loss bug fix would ship a live regression in the autonomous loop. Recorded here because the investigation surfaced it.

## User-Brand Impact

**If this lands broken, the user experiences:** their worktree directory silently disappearing mid-session — `cd` fails, the editor shows every file as deleted, and uncommitted work written since the last commit is gone with no error, no prompt, and no recovery path. Because the reaper fires at session start, the loss is typically discovered at the *beginning* of the next session, disconnected from the action that caused it.

**If this leaks, the user's *workflow and unpushed source code* is exposed via:** destruction rather than disclosure — `rm -rf --one-file-system -- "$dir"` on a directory git never registered. There is no backup: the branch exists but the working-tree delta does not.

**Brand-survival threshold:** `single-user incident`

One founder losing an afternoon's uncommitted work to a tool that was supposed to be managing their branches for them is a trust event Soleur does not recover from by explaining the shell mechanics. Per Phase 2.6 Step 3, `requires_cpo_signoff: true` is set in frontmatter and `user-impact-reviewer` is invoked at review time.

## Implementation Phases

Phases are ordered by **dependency direction**, not by file. The shared helper (contract) must exist before any caller consumes it.

### Phase 0 — Preconditions (no code)

1. Confirm `_validate_worktree_name`'s regex is still `^[A-Za-z0-9._-]+$` in `.claude/hooks/lib/session-state.sh` (anchor: `_validate_worktree_name() {`). The fix's correctness is defined against it.
2. Confirm `scripts/test-all.sh` still discovers both suite locations. Anchor: the `for f in plugins/soleur/test/*.test.sh plugins/soleur/skills/*/test/*.test.sh …` loop. The new suite must land in a discovered glob or it will never run.
3. Re-read `plugins/soleur/test/test-helpers.sh` for the available assertions: `assert_eq`, `assert_contains`, `assert_file_exists`, `assert_file_not_exists`, `print_results`.
4. `git fetch origin && git log --oneline origin/main -1` — confirm PR #7407 has not yet merged, and record the base SHA (see §Merge-Order Dependency).

### Phase 1 — RED: the regression suite (before any source change)

Create `plugins/soleur/test/worktree-manager-safe-branch-sanitization.test.sh`, following the fixture shape used by `plugins/soleur/test/worktree-manager-feature-spec-dir.test.sh` (seed repo → `git clone --bare` → invoke the manager as a subprocess with `--yes`).

Arms required:

| Arm | Asserts |
|---|---|
| A1 | `create ci/rule-metrics` produces `.worktrees/ci-rule-metrics` and **no** `.worktrees/ci` directory exists |
| A2 | The created branch is exactly `ci/rule-metrics` (`git -C <wt> rev-parse --abbrev-ref HEAD`) — the slug must not leak into the ref |
| A3 | `basename` of the worktree path passes `_validate_worktree_name`, and a lease file exists for that key |
| A4 | **The survival arm.** With the worktree live, run `cleanup_orphan_worktree_dirs` and assert the worktree directory still exists and still contains its uncommitted file |
| A5 | `feature a/b` writes its spec dir at the slugified path that `cleanup_merged_worktrees` will later look for |
| A6 | Identity: `create feat-plain-name` is byte-identical in outcome to today (no slug applied where none is needed) |
| A7 | **Verify-the-verifier.** Copy the SUT to a sandbox, revert the derivation to the raw branch name, re-run A1+A4 against the copy, assert they **FAIL** |
| A8 | Phase 3b descendant guard: pre-built nested layout survives the reaper (AC11) — build the nesting **directly with `git worktree add`**, not via the fixed manager, since the manager can no longer produce it |
| A9 | **Descendant-guard boundary.** `.worktrees/ci-foo` registered + `.worktrees/ci` a true unregistered orphan → `ci` **IS** reaped. Pins that the guard uses a path-boundary match (`"$dir"/*`), not a string-prefix match, and so did not over-trigger into disabling the reaper (AC12) |

**A7 is not optional.** A4 alone is satisfiable by a suite that has stopped detecting: it passes both before and after a correct fix if the harness never actually nests. Precedent for the sandbox-mutation shape exists in this repo — `scripts/test-all.sh` documents the ADR-170 rule-body linter's *"verify-the-verifier case that re-introduces the real defect into a tree copy"* and the registry gate's mutation battery, which *"sandboxes its own copies of both SUTs, so it neither mutates the worktree nor depends on suite ordering."* Mirror that: mutate a **copy**, never the working tree.

**A4 must run the reaper from outside the worktree under test.** `cleanup_orphan_worktree_dirs` has no `$PWD` guard, so a test that happens to `cd` into the target proves nothing about the guard chain being exercised.

Run the suite. It MUST fail on A1/A4/A5 before Phase 2 begins (`cq-write-failing-tests-before`).

### Phase 2 — GREEN: the shared derivation helper (contract)

Add one helper near the other private helpers in `worktree-manager.sh` (alongside `_rm_errno` / `_acquire_worktree_lease`):

- **Name:** `_safe_worktree_name`
- **Behavior:** `tr '/' '-'` — byte-identical to the transform `cleanup_merged_worktrees` already performs, so producer and consumer agree **by construction**.
- **The helper is a PURE TRANSFORM.** It never validates, never returns non-zero, never aborts. Three lines. This is what makes routing `cleanup_merged_worktrees` through it genuinely behavior-identical (see R2 below).

- **FR4 — observability only, no abort.** In `_acquire_worktree_lease`, split the existing failure marker's `reason=` field: emit `reason=name-not-keyable` when `_validate_worktree_name` rejects the key, and keep `reason=rc-nonzero` otherwise. Creation proceeds exactly as today.

  **This replaces a fail-closed abort that the plan originally specified.** See §Plan Review Revisions R1 — the abort rested on a premise that measurement falsified, and it would have regressed legal git refnames like `feat(auth)/login` from *working* to *hard refusal*. The marker that FR4 originally proposed to add **already exists and already fires** on exactly this path; only the `reason=` discrimination was missing.

### Phase 3 — GREEN: route every producer through the helper

Cite content anchors, not line numbers.

1. **`create_worktree`** — derive `safe_branch` once immediately after the empty-name guard. Change `local worktree_path="$WORKTREE_DIR/$branch_name"` → `"$WORKTREE_DIR/$safe_branch"`. Change `_acquire_worktree_lease "$branch_name" create trap` → `"$safe_branch"`. Change the re-entry arm `_acquire_worktree_lease "$branch_name" create-reentry notrap` → `"$safe_branch"`. **Leave `git worktree add $TRACK_FLAG -b "$branch_name" "$worktree_path" "$BASE_REF"` untouched** — the ref keeps the raw name.
2. **`create_for_feature`** — same derivation from `branch_name` (`feat-$name`, which nests whenever `$name` contains a slash). Change `worktree_path`, `spec_dir` (→ `…/specs/$safe_branch`, agreeing with `cleanup_merged_worktrees`), the `feature` lease key, and the `feature-reentry` lease key. Leave its `git worktree add … -b "$branch_name"` untouched.
3. **`switch_worktree`** — slugify the operator-supplied argument before both `local worktree_path="$WORKTREE_DIR/$worktree_name"` and `_acquire_worktree_lease "$worktree_name" switch notrap`, so `switch ci/rule-metrics` resolves to the real directory. Update the existing comment that reads *"For everything create or feature made, that equals the branch name"* — after this change it equals the **slug** of the branch name.
5. **`cleanup_merged_worktrees`** — replace the inline `safe_branch=$(echo "$branch" | tr '/' '-')` with a call to the helper. Behavior-identical today; the point is that a future edit to the transform can no longer desynchronize producer from consumer.

6. **The re-entry call site.** `create_worktree`'s existing-directory arm ends with `switch_worktree "$branch_name"` — passing the **raw** branch name one line after the lease key is slugified. Pass `$safe_branch` here. This is the one call site that genuinely requires step 3's change; without it the resume path breaks for slash branches. *(Not named in the issue body; surfaced at plan review.)*

### Phase 3b — GREEN: reaper hardening (remediation, not defense-in-depth)

Fixing the producer stops *new* nesting. It does **nothing** for a worktree that is *already* nested on a customer's disk — that directory stays reapable at the next session start. Because the plugin is already installed on at least one external machine, the reaper must be made safe for the state the field is in, not only the state the fix produces. Both CTO and CPO called for this to be folded in rather than deferred.

Two guards in `cleanup_orphan_worktree_dirs`, both placed with the existing guard chain (symlink / bare-layout / `.git`-entry), before the `rm -rf`. *(Revised at review: the second guard is NOT the `$PWD` check R3 cut — it is a filesystem backstop. The registry-based descendant check is a string comparison and misses a live checkout whenever git reports the path differently: symlinked `.worktrees/`, a newline-truncated porcelain record, or a lost registry entry. All three were reproduced destroying planted work.)*:

1. **Descendant guard.** If any path in `registered_paths` is a **descendant** of `$dir`, the directory is an intermediate holding a live worktree — skip it and warn. This is the direct antidote to the measured failure: `.worktrees/ci` is unregistered, but `.worktrees/ci/rule-metrics` *is* registered beneath it.

   **The match must be `"$dir"/*`, never `"$dir"*`.** A bare prefix match treats `.worktrees/ci-foo` as a descendant of `.worktrees/ci` — a sibling, not a child. That would make the guard skip *legitimate* orphans whenever any registered worktree shares a name prefix, silently disabling the reaper for a whole family of directories. The trailing slash is what makes it a path-boundary test rather than a string-prefix test. Add a test arm covering exactly this: `.worktrees/ci-foo` registered, `.worktrees/ci` an unregistered true orphan → `ci` **is** reaped.
This is a pure skip-and-warn addition. It cannot cause a directory to be deleted that would survive today, so the change is strictly non-destructive relative to current behavior.

A second guard (`$PWD` containment, mirroring `cleanup_merged_worktrees`) was specified and then **cut** — see §Plan Review Revisions R3. It is unreachable: the reaper only deletes directories that are both unregistered **and** `.git`-less, and a worktree you are standing in is registered.

### Phase 4 — Documentation

1. `plugins/soleur/skills/git-worktree/SKILL.md` §Sharp Edges — one entry: a slash-bearing branch produces a hyphenated directory; the ref keeps its slashes; the directory basename is the lease key.
2. `knowledge-base/engineering/architecture/decisions/ADR-099-git-surface-topology.md` — one bullet appended to the existing *"Idiom rules that follow from the topology"* list (see §Architecture Decision).

### Phase 5 — Verification

Run the full suite from a worktree: `bash scripts/test-all.sh`. Record the pass count.

## Files to Edit

| File | Change |
|---|---|
| `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh` | Add `_safe_worktree_name` (pure transform); route `create_worktree`, `create_for_feature`, `switch_worktree`, `cleanup_merged_worktrees` through it; pass `$safe_branch` at the `switch_worktree` re-entry call; split `reason=` on the existing lease-failure marker; add the descendant guard to `cleanup_orphan_worktree_dirs` |
| `plugins/soleur/skills/git-worktree/SKILL.md` | §Sharp Edges entry (body only — **no `description:` change**, so the 1800-word skill-description budget is untouched and Phase 1.8 does not apply) |
| `knowledge-base/engineering/architecture/decisions/ADR-099-git-surface-topology.md` | One idiom bullet |

## Files to Create

| File | Purpose |
|---|---|
| `plugins/soleur/test/worktree-manager-safe-branch-sanitization.test.sh` | Arms A1–A9, plus mutants M1/M2. **Must `source` the script and call `cleanup_orphan_worktree_dirs` directly** — there is no CLI verb for it (its only call sites are inside `cleanup_merged_worktrees`, which locks, deletes remote branches and closes PRs). Precedent: `plugins/soleur/test/worktree-manager-sandbox-tmp-sweep.test.sh`. Sourcing imports `set -euo pipefail` and the preamble `exit 3`s outside a git repo, so source inside the fixture repo. |

**Not edited (verified):** `.claude/hooks/lib/session-state.sh` — the fix conforms to `_validate_worktree_name`; it does not relax it. Widening that regex would weaken a guard shared by every lease consumer, and issue **#7409** (session-state lease library unresolvable from plugin-cache installs) is the separate, explicitly out-of-scope workstream on that file.

## Acceptance Criteria

### Pre-merge (PR)

- [x] **AC1** — `create ci/rule-metrics` produces `.worktrees/ci-rule-metrics`, exactly two levels below repo root, and `.worktrees/ci` does not exist. Verify: `test -d .worktrees/ci-rule-metrics && test ! -e .worktrees/ci`. **Not** `find .worktrees -maxdepth 2 -type d` — `-maxdepth` counts from the start path, so that command prints the nested `.worktrees/ci/rule-metrics` *and* every top-level directory inside a correct worktree. It discriminates nothing (plan review P1-7).
- [x] **AC2** — The created ref is exactly `ci/rule-metrics`. Verify: `git -C .worktrees/ci-rule-metrics rev-parse --abbrev-ref HEAD` prints `ci/rule-metrics`.
- [x] **AC3** — The lease key equals the directory basename **and** passes `_validate_worktree_name`, **for every branch name currently on origin** (measured: 29/29 slash-bearing, and all origin branches, satisfy this under `tr '/' '-'`). For any residual input where the slug is not lease-keyable, the existing `SOLEUR_WORKTREE_LEASE_ACQUIRE_FAILED` marker carries `reason=name-not-keyable`. *(Corrected at review: this AC named a `SOLEUR_WORKTREE_NAME_UNSAFE` sentinel, which is residue from the pre-R1 fail-closed design and exists nowhere in the repo — a checked box asserting a string no code emits.)* *(AC restated from the issue body, which asserted the unqualified universal — measurement shows `tr '/' '-'` does not deliver it for all valid git refnames.)*
- [x] **AC4** — A slash-branch worktree with an uncommitted file survives `cleanup_orphan_worktree_dirs`, invoked from outside that worktree.
- [x] **AC5** — **Mutation-tested with TWO independent mutants.** A single derivation-only mutant is *defeated by this same PR*: on it, `create ci/rule-metrics` nests, the reaper reaches `.worktrees/ci`, and Phase 3b's descendant guard skips it — so the worktree survives and A4 goes **green on the mutant**. Both reviewers converged on this. Required instead:
  - **M1** (pins the producer fix): revert the derivation **and** the descendant guard → A1 and A4 must both FAIL.
  - **M2** (pins the remediation): revert only the descendant guard, keep the producer fix, build the nested layout directly with `git worktree add` → A8 must FAIL.

  Name which artifact each mutant edits (helper body vs. individual call sites); "the derivation" is now several sites and the answer changes the result.
- [x] **AC6** — **Self-consistency, not archival agreement:** `basename(spec_dir) == basename(worktree_path) == safe_branch`. The issue's original framing ("agrees with `cleanup_merged_worktrees`") is **not satisfiable by any implementation** — see R6.
- [x] **AC7** — Identity preserved: for a non-slash branch, the created path, lease key, spec dir, and ref are unchanged from `origin/main` behavior.
- [ ] **AC8** — `bash scripts/test-all.sh` passes from a worktree, with the new suite discovered (its name appears in the run output).
- [x] **AC9** — `bash -n plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh` and `shellcheck` (if the repo gates on it) are clean for the changed regions.
- [ ] **AC10** — PR body contains `Closes #7408`, does **not** scope in #7409, and names the untouched fourth transform copy at `plugins/soleur/skills/archive-kb/scripts/archive-kb.sh`.
- [x] **AC11** — **Phase 3b descendant guard.** Given a pre-existing nested layout (`.worktrees/ci/rule-metrics` registered, `.worktrees/ci` not), `cleanup_orphan_worktree_dirs` **skips** `.worktrees/ci` and both directories survive. This is the remediation arm for worktrees already on disk.
- [x] **AC12** — **The descendant guard does not over-trigger.** With `.worktrees/ci-foo` registered and `.worktrees/ci` a genuine unregistered orphan, the reaper still **removes** `.worktrees/ci`. A guard that skips it has used a string-prefix match instead of a path-boundary match and has silently disabled orphan reaping for every name-prefix family.
- ~~**AC13** — **Phase 3b `$PWD` guard.**~~ **WITHDRAWN — do not implement.** This AC survived the revision that cut the guard it tests; it contradicts R3, Phase 3b ("specified and then **cut**"), and tasks.md 3b.5 ("Not added"). The guard is unreachable: the reaper deletes only directories that are both unregistered **and** `.git`-less, and a worktree you are standing in is registered. Retained struck-through rather than deleted so the numbering of AC1–AC12 stays stable across the review trail. *(Caught at deepen-plan; see R3.)*

### Post-merge (operator)

None. This is a pure code + docs change on an already-provisioned surface; no migration, no infrastructure, no vendor step, no secret. Existing worktrees are unaffected — the transform is identity for every directory currently on disk (measured against the live `.worktrees/` listing, all of which are non-slash names).

## Merge-Order Dependency

**PR #7407 is a live OPEN DRAFT on the same file** (`+289/-75` on `worktree-manager.sh`) and also edits `ADR-099-git-surface-topology.md`.

> **SUPERSEDED 2026-08-10 (review) — re-measure before acting on anything below.** The table
> that follows was written against #7407 at `+289/-75` and concluded the hunks were "disjoint".
> Both halves of that are now false. Re-measured at review time, #7407 is **`+3070/-105`** and
> its file set has grown to include **`apps/web-platform/server/git-lock-marker-telemetry.ts`
> — specifically `MARKER_RE`**, the exact expression this PR also edits to register
> `SOLEUR_ORPHAN_SKIP_DESCENDANT` and `SOLEUR_WORKTREE_SLUG_COLLISION` — plus
> `git-lock-marker-telemetry.test.ts`, `ADR-099`, and hunks inside `create_worktree`
> (`@@ -643,62 +895,137`) and `create_for_feature`, which the original analysis placed
> entirely below line ~650.
>
> So a **real textual conflict is now expected**, not merely possible, and it lands on a
> one-line regex where a botched resolution silently drops a marker from the extractor —
> failing green, since an unregistered marker is simply never ingested. Whichever PR merges
> second must re-run `apps/web-platform/test/git-lock-marker-telemetry.test.ts` (the drift
> guard catches exactly this) plus the full `worktree-manager-*` suite, and must confirm the
> union of both PRs' markers survives in `MARKER_RE` rather than one side's alternation
> replacing the other's.
>
> This is a committed artifact a future reader would otherwise trust; the measurement below
> is retained only to show what the sequencing decision was originally based on.

**Sequencing decision: land #7407 first, then rebase this branch on top.** It is the older, larger, already-drafted change; rebasing this smaller diff onto it is cheaper than the reverse.

| Risk | Mitigation |
|---|---|
| Same-file conflict | **Measured, not assumed.** `gh pr diff 7407` shows its `worktree-manager.sh` hunks at `@@ -4,14`, `@@ -156,8` (`ensure_git_root_absolute`), `@@ -412,6` (`_config_target_masked`), `@@ -445,11` (`atomic_git_config`), and `@@ -544,14 +580,107` (`ensure_bare_config`) — **all within the first ~650 lines**. This plan's targets begin at `create_worktree` (~line 1279) and run to `cleanup_merged_worktrees` (~line 2049). The hunk ranges are **disjoint**; three-way merge should be clean. |
| Line-number drift | #7407 grows `ensure_bare_config` from 14 to 107 lines (net ~+214 on the file), so **every line number below it shifts**. This is why Phase 3 specifies content anchors and never line numbers (`cq-cite-content-anchor-not-line-number`). Do not port this plan's edits by line offset after a rebase. |
| Adjacency at the call site | Both `create_worktree` and `create_for_feature` **open** with `if ! ensure_bare_config; then`. #7407 rewrites that function's *body*, not these call sites, and no #7407 hunk reaches line 1279+. The call sites are untouched by both PRs — but re-read them after rebase rather than assuming. |
| Gratuitous reformatting | **Hard constraint:** touch only the specific assignments and call arguments named in Phase 3. No re-indentation, no comment rewrapping, no reordering of untouched regions. |
| ADR-099 collision | Both PRs edit the same ADR. Append this plan's bullet at the **end** of the "Idiom rules" list to minimize overlap, and re-read the file after any rebase. |
| Test-file collision | #7407 adds `worktree-manager-bare-in-dotgit-layout.test.sh` and modifies `worktree-manager-atomic-config.test.sh` / `-stale-lock-diag.test.sh`. This plan adds a **new, differently-named** suite and modifies none of those. No collision. |

Whichever merges second rebases and re-runs `scripts/test-all.sh` in full.

## Open Code-Review Overlap

**None.** Queried all 64 open `code-review` issues; zero bodies mention `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh`, `plugins/soleur/skills/git-worktree/SKILL.md`, `.claude/hooks/lib/session-state.sh`, or `scripts/test-all.sh`.

## Domain Review

**Domains relevant:** Engineering (CTO), Product (CPO)

### Engineering

**Status:** reviewed
**Assessment:**

1. **Shared helper — yes.** Duplicating `tr` at five sites is the failure mode that produced this bug; prior worktree-manager rounds recurred from exactly that. Folded into Phase 2 + Phase 3 step 5. Also identified a **fourth** copy of the transform at `plugins/soleur/skills/archive-kb/scripts/archive-kb.sh` (verified) — separate process, no path-safety role, left untouched but named in the PR body.
2. **Transform: keep `tr '/' '-'`, but fail closed.** Option (B) (`tr -c`) was rejected on a ground this plan had not considered: it *manufactures* collisions (`déjà/vu` and `dêjà/vu` collapse to the same slug). The abort must live **inside the helper, before** `_acquire_worktree_lease`, so the existing `|| true` still covers genuine lease-service failures. Folded into FR4.
3. **Collision guard — scope in, not defer.** Cited the live divergence on this machine (independently verified above). Folded into FR5.
4. **Reaper hardening — scope in, and it is remediation rather than defense-in-depth**, because already-nested directories on installed machines stay reapable after the producer is fixed. Folded into Phase 3b.
5. **Merge order:** land #7407 first and rebase. Its `ensure_bare_config` rewrite is the first statement of both create functions — re-verified here at hunk level (disjoint; see §Merge-Order Dependency).
6. **No new ADR** — amend ADR-099's existing idiom list. Confirmed in §Architecture Decision.

### Product

**Status:** reviewed
**Assessment:**

1. **Threshold confirmed as `single-user incident`**, and materially sharper than assumed: the plugin is live on an external alpha tester's machine, so this is not a hypothetical customer surface.
2. **User experience of the failure:** not "a directory vanished" but *the agent contradicting itself* — it reports work saved, then the work is gone. Nothing surfaces in the operator digest, so the user has no route to understanding what happened. Reinforces the fail-closed choice.
3. **Fail closed, without a warning path** — converged with CTO independently. A non-technical operator will not read a sentinel; a refusal is legible, destroyed work is not.
4. **The directory name is user-visible** (`fix-issue/SKILL.md` documents the path, and operators `cd` into it), so the flat slug must match documented convention — it does (verified: three independent sites already encode it).
5. **Collision must abort, never silently reuse.** Converged with CTO.
6. **Already-nested directories must not become orphans at upgrade.** Converged with CTO — folded into Phase 3b.

> **Plan review partially overturned this domain pass.** Items CTO-2/3/4 and CPO-3/5/6 each proposed a guard without re-checking the guard chains already in the file. R1–R4 record what was cut and why. The domain pass's durable contributions were the shared-helper decision, the merge-order sequencing, the ADR disposition, and the descendant guard.

### Product/UX Gate

**Tier:** none
**Decision:** n/a — no user-facing surface
**Agents invoked:** cpo
**Skipped specialists:** none
**Pencil available:** N/A (no UI surface)

The mechanical UI-surface override was evaluated against `## Files to Edit` and `## Files to Create`: no path matches `components/**/*.tsx`, `app/**/page.tsx`, `app/**/layout.tsx`, or any UI-surface glob. All four paths are a shell script, a skill markdown, an ADR, and a shell test. Product is relevant **only** via the `single-user incident` threshold (Phase 2.6 Step 3 CPO sign-off), not via a UI surface, so no wireframe is required and `wg-ui-feature-requires-pen-wireframe` does not fire.

#### Findings

CPO consulted on threshold confirmation, the concrete user-facing artifact of the failure, whether an at-risk worktree should surface anything to the user, whether the visible directory-name change matters, and the disposition of the reaper's missing `$PWD` guard.

## Observability

The changed file executes on TWO surfaces, and the first draft of this block named only one.

**Layer 7** — a customer's self-hosted CLI (`hr-observability-layer-citation`). Signal path: the `SOLEUR_*` stdout marker stream the sibling worktree markers already use, read by the agent from the tool result, plus the unconditional stderr summary.

**Layers 1-2** — the hosted platform. `cleanup_orphan_worktree_dirs` IS reached there: `plugins/soleur/commands/go.md` Step 0 runs `cleanup-merged` verbatim as its session preamble, and that plugin is loaded by the same options object that registers the `Bash` PostToolUse hook. So the markers reach `git-lock-marker-telemetry.ts` -> pino -> Sentry. *(Corrected at review: this block originally asserted "there is no server-side surface", which is contradicted by an in-repo comment on the very extractor these markers depend on — and the block's own `alert_route: marker extractor` named the hosted mechanism while the header denied it existed.)* Hosted coverage requires the marker to be registered in `MARKER_RE`; both new markers are.

```yaml
liveness_signal:
  what: "SOLEUR_WORKTREE_LEASE_ACQUIRE_FAILED absence — after this fix, a slash-bearing branch must NOT emit it"
  cadence: "every create/feature/switch invocation"
  alert_target: "marker extractor -> platform-integrity review"
  configured_in: "plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh (_acquire_worktree_lease)"

error_reporting:
  destination: "stdout SOLEUR_* sentinel + headless_or_stderr warn (the existing layer-7 convention in this script)"
  fail_loud: true

failure_modes:
  - mode: "slug is still not lease-keyable (branch contains a character outside [A-Za-z0-9._-] that is not '/'); worktree runs unleased but is NOT reapable (R1)"
    detection: "SOLEUR_WORKTREE_LEASE_ACQUIRE_FAILED … reason=name-not-keyable — the marker already fires; this PR adds the reason= discrimination (FR4)"
    alert_route: "marker extractor; distinguishes 'the slug transform was insufficient' from 'the lease layer is absent', which today are indistinguishable"
  - mode: "an already-nested worktree (created before this fix) is presented to the reaper"
    detection: "SOLEUR_ORPHAN_SKIP_DESCENDANT dir=… reason=holds-live-worktree (registry match) or reason=holds-checkout-on-disk (filesystem backstop)"
    alert_route: "cli-stdout marker (layer 7) + marker extractor -> pino -> Sentry (hosted). Corrected at review: this read 'the ABSENCE of a removal is the positive signal', which is not a detection route — an absence assertion cannot distinguish 'the guard fired' from 'the reaper never ran'. The shipped code emits a positive, named marker."
  - mode: "lease layer absent entirely (plugin-cache install)"
    detection: "SOLEUR_WORKTREE_LEASE_LIB_MISSING at load (pre-existing)"
    alert_route: "tracked separately as #7409 — explicitly out of scope"
  - mode: "orphan reaper cannot remove a directory"
    detection: "SOLEUR_ORPHAN_UNREMOVABLE count=… cleaned=… errno=… (pre-existing)"
    alert_route: "marker extractor"

logs:
  where: "operator terminal + captured tool_response markers"
  retention: "session-scoped"

discoverability_test:
  command: "bash plugins/soleur/test/worktree-manager-safe-branch-sanitization.test.sh 2>&1 | tail -3"
  expected_output: "Passed: 36 / Failed: 0 / ALL TESTS PASSED. NO ssh, no network, no credentials. Corrected at review — the previous probe was broken THREE ways: (a) it asserted a RELATIVE .worktrees/ path while WORKTREE_DIR anchors to the bare root, so it failed on a CORRECT implementation whenever run from a worktree; (b) it sent stdout to /dev/null, discarding the very SOLEUR_* marker stream it was meant to demonstrate; (c) it created a real branch, worktree and >=4h lease with no teardown, needing network and a multi-minute install. The suite exercises both new markers in synthesized fixtures and cleans up after itself."
```

The two failure modes above are discriminated by **distinct** sentinels carrying the raw branch and the derived slug in the same event, so a single marker decides *which* of them fired — rather than a shared boolean that would leave the two hypotheses tied.

## Architecture Decision (ADR/C4)

### ADR

**Amend `ADR-099-git-surface-topology.md`** — no new ADR. ADR-099 already owns the "idiom rules for code that touches git surfaces" list, and this is exactly such a rule. Append one bullet:

> Never derive a filesystem path or a lease key from a **raw git refname**. Refnames may contain `/` (and other characters outside `[A-Za-z0-9._-]`); worktree directory names may not. The worktree directory basename is the **slugified** branch name, and that basename **is** the session-lease key — `create_worktree`, `create_for_feature`, `switch_worktree` and `cleanup_merged_worktrees` must all derive it through the one shared helper so producer and consumer cannot desynchronize. Keep the raw refname for `git worktree add -b`.

The ordinal is not at risk (this amends an existing accepted ADR rather than claiming a new number), so the ship-time ADR-ordinal collision gate is a no-op for this PR. Note PR #7407 also edits ADR-099 — see §Merge-Order Dependency.

### C4 views

**No C4 impact.** Per the C4 completeness mandate this was checked by reading all three model files (`model.c4`, `views.c4`, `spec.c4`), not by a single keyword grep. Enumerated for this change:

- **External human actors:** none. The change is internal to a CLI script; no new correspondent, reviewer, or recipient.
- **External systems / vendors:** none. No new webhook, outbound API, or third-party store.
- **Containers / data stores touched:** none. The lease files are process-local state under the session-state root, which the C4 model does not represent.
- **Actor↔surface access relationships:** unchanged. No ownership or sharing semantics move.

The three `worktree` hits in `model.c4` (`coordinator -> supabase "Reads worktree lease"`, the sticky-router description, and the workspaces-volume description) all describe the **server-side per-user worktree lease held in Postgres** under ADR-068 — a structurally different mechanism from the CLI's file-based `session-state.sh` leases under `.worktrees/`. This change touches only the latter, which is not modeled.

### Sequencing

None required. The decision is true the moment the code merges.

## Plan Review Revisions

The plan-review panel overturned four items that the Phase 2.5 domain review had *added*. Recorded because the failure pattern is instructive: two reviewers each proposed a guard, and neither re-checked whether the guard chains already in the file made it redundant. A 13-line fix had become a 15-AC plan.

**R1 — FR4's fail-closed abort: CUT. Replaced with a `reason=` field on the marker that already fires.**

The abort rested on the plan's own assertion that *"a warning would permit an unleased worktree that the reaper is entitled to delete."* **Measured, and false.** Once nesting is fixed, a flat-but-unleased worktree is protected by:

- `cleanup_orphan_worktree_dirs` — contains **zero** references to the lease (verified by grepping the whole function). It reaps only directories that are unregistered **and** `.git`-less; a flat worktree is both registered and has a `.git` file, so it is skipped twice over.
- `cleanup_merged_worktrees` — reaches deletion only for an already-merged/`[gone]` branch, and only after a `$PWD` guard, a **recent-commit grace window** (`_delta < 600` → `continue`), and an **uncommitted-changes guard** (`git status --porcelain` non-empty → `continue`).

The uncommitted-changes guard is precisely the protection for the harm this issue is about. So the residual class had **no data-loss path**, and the abort's real net effect would have been a **regression**: `create 'feat(auth)/login'` — a legal refname and a common convention — going from *working* to *hard refusal*. Separately, `_acquire_worktree_lease` **already emits** `SOLEUR_WORKTREE_LEASE_ACQUIRE_FAILED` on exactly this path, and its inline comment already names slash-bearing names as the cause; only the `reason=` discrimination was missing. FR4 now buys the full observability benefit in two lines.

This also retires **FR4a** (the `local x=$(cmd)` exit-status trap) and its AC: with the helper reduced to a pure transform that never returns non-zero, the trap has nothing to swallow. The measurement stands and is worth remembering, but it no longer applies here.

**R2 — FR5's collision guard: CUT to its own issue.**

The cited evidence (`fix-6808-heartbeat-wire` ↔ `docs-redaction-fails-open`) is **not a slug collision** — neither name contains a slash, and the measured corpus contains zero collisions. It is a real but unrelated pre-existing defect. Worse, the existing-directory arm is the **resume path for `one-shot`/`work`** (its own comment says so), and that divergent worktree exists on this machine now — so FR5's first observable effect would have been `create fix-6808-heartbeat-wire` failing hard under `--yes` on the operator's own box. Shipping an abort into the autonomous loop's resume path inside a data-loss bug fix is the coupling that makes bug fixes risky.

**R3 — The `$PWD` guard in the orphan reaper: CUT.** Unreachable. The reaper deletes only unregistered, `.git`-less directories; a worktree you are standing in is registered. Symmetry with `cleanup_merged_worktrees` is aesthetic — the two functions guard different states.

**R4 — `copy_env_to_worktree` slugify: CUT.** A pure consumer with no refname caller; its auto-detect path already does `basename`. It was added because an enumeration found it, not because anything needed it.

**R5 — ADDED: `create_worktree`'s re-entry call site.** The arm ends with `switch_worktree "$branch_name"` — the **raw** name, one line after the lease key is slugified. This is the one call site that genuinely requires the change, and the plan had covered it only by accident via the blanket slugify inside `switch_worktree`. Now fixed at the source (Phase 3 step 6).

**R6 — AC6's premise is false; the acceptance criterion is restated.** The issue's fourth AC ("`create_for_feature`'s spec dir agrees with `cleanup_merged_worktrees`") is **unsatisfiable by any implementation**, and both reviewers found it independently. The two `spec_dir` variables have different roots — `create_for_feature` writes under `$worktree_path`; `cleanup_merged_worktrees` reads under `$GIT_ROOT` (the bare root) and its own comment says that read is backward-compat for legacy pre-#2815 layouts. The in-worktree spec is never archived by that path for *any* branch name, slashed or not. The slug change is still worth making (the spec dir should match the worktree basename), but as **self-consistency**, not archival agreement. The archival-gap claim is withdrawn from the reconciliation table.

**R7 — AC5 needs two mutants, because Phase 3b defeats the single one.** The plan built the vacuity it warned against: on a derivation-only mutant, the descendant guard makes the nested worktree survive, so the survival arm goes green on the mutant. M1/M2 split recorded in AC5.

**R8 — Verification commands corrected.** AC1's `find .worktrees -maxdepth 2 -type d` is green under the defect (depth 2 prints the nested path *and* every top-level dir inside a correct worktree); the observability `discoverability_test` had the same shape and would have returned ~20 on a **correct** implementation. Both replaced with `test -d … && test ! -e …`. Two published measurement commands were also non-reproducible as written (`grep '/'` on raw `ls-remote` matches all 60 branches because every line contains `refs/heads/`; the function-enumeration regex yields ~30 functions, not 3). The *numbers* were right — they came from the correct commands actually run — but the plan must publish commands that reproduce.

**R9 — The test suite cannot reach the reaper through the CLI.** `cleanup_orphan_worktree_dirs` has **no `main()` verb**; its only call sites are inside `cleanup_merged_worktrees`, which acquires a lock, deletes remote branches and closes PRs. The suite must `source` the script and call the function directly (precedent: `worktree-manager-sandbox-tmp-sweep.test.sh`). Phase 1's "invoke as a subprocess with `--yes`" was wrong for every reaper arm.

**Net effect:** ~180 lines of delivered code/test removed, ~45% of planned delivery. Kept: the pure-transform shared helper, the descendant guard, and arms A1–A9. The descendant guard survives review as arguably more valuable than the producer fix — it is the only thing that helps a customer who already has a nested worktree on disk.

## Risks & Mitigations

| # | Risk | Likelihood | Mitigation |
|---|---|---|---|
| R2 | Suite passes vacuously — the harness never actually nests, so A4 is green before and after the fix | Medium | **AC5 mutation arm is mandatory** and sandbox-scoped (mutates a copy, never the worktree) |
| R3 | Conflict with PR #7407 | Medium | Disjoint function sets; no reformatting of untouched regions; whichever merges second rebases and re-runs the full suite |
| R5 | Changing the shared helper later silently desynchronizes producer and consumer again | Low | That is precisely what routing `cleanup_merged_worktrees` through the same helper (Phase 3 step 5) prevents |
| R6 | A user has a live nested worktree right now, created before this fix — fixing the producer does nothing for it | Medium (plugin is installed on an external machine) | **Addressed by Phase 3b**, which is the reason that phase is scoped in. The descendant guard makes an already-nested layout survive the reaper, so the pre-existing state becomes safe without a migration. No `mv`/`rm` migration is proposed — performing one would itself have to move live directories, the exact operation whose miscarriage caused this issue. The SKILL.md Sharp Edge documents the manual cleanup path. |

## Alternative Approaches Considered

| Approach | Verdict |
|---|---|
| **Widen the transform to `tr -c 'A-Za-z0-9._-' '-'`** (safe-by-construction for every git refname) | **Rejected.** Three measured reasons. (1) It **manufactures collisions** — `déjà/vu` and `dêjà/vu` collapse to the same slug, so it trades a loud refusal for a silent wrong-worktree, which is the failure class FR5 exists to stop. (2) It mangles non-ASCII (`déjà/vu` → `d--j---vu`; `tr` is byte-oriented). (3) It delivers **zero** benefit on the real corpus — 0 of 29 slash-bearing branches and 0 of all origin branches need it. The residual class needs no transform change at all — measurement (R1) shows it carries no data-loss path once nesting is fixed; FR4's `reason=` field makes it visible if that ever changes. |
| **Relax `_validate_worktree_name` to accept `/`** | Rejected. It is a shared guard for every lease consumer, and slashes in a lease *filename* would create the same nesting problem one directory over. Fix the producer, not the validator. |
| **Harden `cleanup_orphan_worktree_dirs`** (descendant guard + `$PWD` guard) | **Adopted — Phase 3b.** Initially framed as deferrable defense-in-depth; CTO and CPO independently reframed it as **remediation**: fixing the producer does nothing for worktrees already nested on installed machines, and the plugin is live on an external tester's disk. Both guards are skip-and-warn only, so neither can delete anything that survives today. **Revised at review:** the `$PWD` guard was cut (R3) and what shipped alongside the descendant guard is a filesystem backstop — see Phase 3b. |
| **Migrate existing nested worktrees automatically** | Rejected. Any migration must `mv` or `rm` live directories — the exact operation whose miscarriage caused this issue. Phase 3b's descendant guard makes the pre-existing state *safe* instead, which achieves the goal without moving anything. Manual cleanup documented in the SKILL.md Sharp Edge. |
| **Fail closed on a non-keyable slug** (the plan's v2 position, added at Phase 2.5) | **Rejected at plan review — see R1.** The premise that an unleased flat worktree is reapable was measured false; the abort would have regressed legal refnames like `feat(auth)/login` with no data-loss risk averted. Reduced to a `reason=` field on the marker that already fires. |
| **Scope in #7409** (lease library unresolvable from plugin-cache installs) | Rejected — explicitly out of scope per the issue. It ships separately. Worth noting the interaction: on a plugin-cache install with no lease library, `_acquire_worktree_lease` returns early and the reaper fails **closed**, so this fix's lease-key correctness is moot there until #7409 lands. That does not change this fix's value — the *nesting* half of the defect is independent of the lease layer. |

## Test Scenarios

| # | Scenario | Expected |
|---|---|---|
| T1 | `create ci/rule-metrics` | `.worktrees/ci-rule-metrics`; no `.worktrees/ci` |
| T2 | `create dependabot/npm_and_yarn/foo-1.2.3` (three components) | `.worktrees/dependabot-npm_and_yarn-foo-1.2.3`; underscores survive (they are inside the allowlist) |
| T3 | `create feat-plain` | Byte-identical to `origin/main` behavior |
| T4 | `feature a/b` | Spec dir at the slugified path `cleanup_merged_worktrees` will look for |
| T5 | `switch ci/rule-metrics` | Resolves to `.worktrees/ci-rule-metrics` |
| T6 | Live slash-branch worktree + `cleanup_orphan_worktree_dirs` run from elsewhere | Worktree and its uncommitted file survive |
| T7 | Sandbox copy with the derivation reverted | T1 and T6 **fail** (mutation arm) |
| T8 | From the slash-branch worktree: `bash ../../scripts/test-all.sh` | Resolves — the two-level assumption in test-all.sh's bare-repo guard now holds |
| T9 | `cleanup_merged_worktrees` on a merged slash branch | Worktree removed, spec archived — path agreement end-to-end |
| T10 | Pre-built nested layout (`git worktree add` directly) + reaper | `.worktrees/ci` and its registered descendant both survive |

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. Fill it before requesting deepen-plan or `/work`.
- **`tr '/' '-'` is not a sanitizer.** It fixes one character class. Six valid git branch shapes measured in this plan remain lease-invalid after it. Do not let AC3 be read as an unqualified universal — it is scoped to the measured corpus plus a **reported** escape (`reason=name-not-keyable`). *(Corrected at review: this read "fail-closed escape", which R1 cut — nothing aborts; the residual class runs unleased and says so.)*
- **Phase 3b's nesting fixture cannot be built with the fixed manager.** After the fix, `create` can no longer produce a nested layout — so A11/T13 must construct it with a direct `git worktree add`, or the test will silently assert nothing.
- **AC4 is vacuous without AC5.** A survival test passes trivially if the fixture never reproduces the nesting. The mutation arm is the only thing that proves the suite detects the real defect.
- **Do not `cd` into the worktree under test before invoking the reaper.** `cleanup_orphan_worktree_dirs` has no `$PWD` guard; a test that stands inside its target exercises a different path than production.
- **Keep the raw branch name on `git worktree add -b`.** Slugifying the ref would silently rename users' branches and break every `origin/<branch>` correspondence — the opposite of the fix.
