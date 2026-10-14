---
title: "fix(test-all): a sibling merge's release tag no longer reddens a green battery — tags join the shared_store softening"
date: 2026-09-07
slug: fix-repo-write-boundary-tag-shared-store-softening
branch: feat-one-shot-7795-tag-shared-store-softening
issue: 7795
closes: 7795
type: fix
lane: cross-domain
domain: engineering
priority: p2-medium
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

## Overview

`scripts/lib/repo-write-boundary.sh` classifies a created-or-moved `refs/tags/*` as FATAL
with no `shared_store` branch. A release tag that a concurrent session's merge publishes
arrives in the shared bare-repo ref store via a fetch inside the run, and turns an
otherwise-green `scripts/test-all.sh` battery RED at the epilogue. The classifier already
softens a deleted non-tag ref and a moved default branch to REPORT when sibling worktrees
exist; the created/moved tag arm was never wired into that branch. This plan closes the
false positive while keeping the tag DELETION arm FATAL and keeping tags FATAL on the
fail-closed no-sibling path.

## Research Insights

### Premise Validation (Phase 0.6)

| Cited premise | Checked how | Verdict |
|---|---|---|
| Issue #7795 still open, not already fixed | `gh issue view 7795 --json state,closedByPullRequestsReferences` | **Holds** — `OPEN`, no closing PR |
| `scripts/lib/repo-write-boundary.sh:506` is the created/moved tag arm | read the file | **Holds** — the arm is inside `repo_boundary_classify`'s created-or-moved loop; `shared_store` is set at `:475` and already gates `:492` (deleted non-tag) and `:511` (moved default branch) |
| #7553 / #7652 are the incident class the guard was filed for | `gh issue view` both | **Holds** — both `CLOSED`, titles match the fixture-`cd`-failure class |
| PR #7770 is the source of the measured report | issue body | **Holds** — cited as found at the ship-time full-battery gate |
| An ADR records this classification decision | `grep -rl 'repo-write-boundary\|shared_store\|shared ref store' knowledge-base/engineering/architecture/decisions/` | **Refuted** — 0 hits. The design record lives only in the file's own comment blocks plus archived #7652 plan/spec artifacts. No ADR is falsified by this change |
| *(claim surfaced by a research subagent)* ADR-133 documents the shared-store softening | `grep -c 'shared_store\|refs/tags' ADR-133-*.md` → **0** | **Refuted — do not propagate.** The quoted text is from `repo-write-boundary.sh`'s own comments, not ADR-133 (which is about tmpfs contention and an advisory lock). Cited here so the mis-attribution dies at plan time |

**The load-bearing premise reversal.** The archived #7652 plan
(`knowledge-base/project/plans/archive/20260827-143501-2026-08-26-fix-7652-fixture-dir-assert-and-boundary-scope-plan.md:433-441`)
accepted this exact residual *by design*:

> *Accepted residual:* `tagOpt` is unset, so a sibling `fetch` during a run writes tags and produces a
> FATAL. Sibling fetches are rare inside a gate window and the printed diff names the tag, so this
> adjudicates in seconds.

The justifying premise — **"sibling fetches are rare inside a gate window"** — is now measured false.
`plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh:2731` runs `git fetch --prune` inside
`cleanup_merged_worktrees()`, which `/work` Phase 0 runs at the **start of every session** on this
machine (`wg-at-session-start-run-bash-plugins-soleur`). With 5–12 concurrent worktrees and a release
published on essentially every labelled merge, a sibling fetch inside a ~15-minute gate window is the
common case, not a rare one. This plan reverses an accepted residual whose premise was refuted by
measurement — it is not discovering an unwired arm.

### Measured facts established at plan time

**Probe 1 — what a plain `git fetch` does to `refs/tags/**` (run live, 2026-09-07).**
Two throwaway repos over a bare origin; origin gains a *moved* `v1.0` and a *new* `v2.0`; consumer runs
a bare `git fetch origin`:

```
    From /tmp/.../origin
       2825f55..a2fd350  main       -> origin/main
     * [new tag]         v2.0       -> v2.0
--- consumer tags after fetch: v1.0  v2.0
--- v1.0 in consumer still points at: c1        # origin moved it to c2; the local tag did NOT move
```

- A fetch **creates** new tags in `refs/tags/**` (tag auto-following).
- A fetch **does not move** an existing local tag.
- `git fetch --prune` (the `cleanup-merged` form) prunes remote-tracking refs only; pruning tags needs
  `--prune-tags`, which that call site does not pass — so a sibling cannot **delete** a tag either.

This is the whole basis of the harm partition below: **sibling-routine tag traffic is creation, and only
creation.** A tag *move* (`git tag -f`, or a forced `+refs/tags/*` refspec) and a tag *deletion* are not
things a sibling produces in passing.

**Probe 2 — the one in-battery fetch that can write a tag into the live repo.**
`scripts/plugin-delivery-canary.sh:335` runs `git -C "$root" fetch --depth 1 origin "$sha"` where
`root="$(git rev-parse --show-toplevel)"` (`:325`) — the **live** repo — but only when
`git cat-file -e "${sha}^{commit}"` misses. The battery's other fetch,
`scripts/lib/legal-base-ref.sh:55`, passes `--no-tags` and cannot write one. So on a no-sibling
checkout there is a real path by which **this run** authors a tag — which makes the fail-closed FATAL
on that path a *true* positive by attribution, not a residual to be softened away.

### The classifier as it stands

`scripts/lib/repo-write-boundary.sh`:

- `_repo_boundary_dim_refs` (`:200`) measures `git show-ref --heads --tags`. Its comment justifies
  excluding `refs/remotes/**` as *"a fetch is the only thing that writes it"* — **incomplete**, since a
  fetch also writes `refs/tags/**`. That incompleteness is precisely why tags were left at full strength.
- `elsewhere` (`:380`) is read from the **BEFORE** snapshot's `wt` family with `<none>` filtered out; there
  is deliberately **no** re-derivation fallback, because re-deriving after the window closes is the
  laundering hole three reviewers independently found. `shared_store=1` iff `elsewhere` is non-empty (`:475`).
- Created/moved loop: `bsha` is empty for a **create** and non-empty-and-different for a **move** — so the
  create/move distinction is already available at zero cost, with no new measurement.
- Deleted loop (`:488`): `refs/tags/*|"$own_branch")` → FATAL unconditionally.

### Test surface (`scripts/lib/repo-write-boundary.test.sh`, 44 arms)

Real git repos under `mktemp -d`; siblings are real `git worktree add` invocations via `sibling_probe()`
(`:742`); `_repo_boundary_branches_elsewhere` is **never** mocked. Helpers: `pass`/`fail`/`ck`, a
`passes+fails == asserted` conservation check (`:719`), and `MIN_ASSERTIONS=44` (`:851`).

Only two arms touch tags, and **the create/move split is exactly what separates them**:

- **Arm 36** (`:637`, no-sibling): creates `refs/tags/probe-tag`, asserts only that `probe-tag` appears in
  the verdict. Severity-agnostic.
- **Arm 43** (`:811`, sibling): creates the tag *before* the BEFORE snapshot, then `git tag -f` — a **move**.
  Asserts `^FATAL[[:space:]]+refs.*probe-tag.*tag`, labelled *"sibling presence does NOT launder a TAG move:
  still FATAL"*. A deliberate non-vacuity arm.
- **No arm exercises tag DELETION at all** (`grep` for `tag -d`/`--delete` → 0). A real coverage gap this
  plan closes.

Because arm 43 tests a **move**, a create-only softening leaves it green **verbatim** — no deliberate
anti-laundering assertion is inverted, and arm 36 (a create on a *no-sibling* fixture) also stays green.

### Institutional learnings that bind

- `knowledge-base/project/learnings/2026-05-05-defense-relaxation-must-name-new-ceiling.md` — *"For every
  plan that removes or relaxes a load-bearing constraint … the plan MUST answer: what was the previous
  defense protecting against, beyond the symptom we're fixing? What new defense covers that threat surface
  now?"* Discharged in **§Defense Relaxation Analysis**.
- `knowledge-base/project/learnings/2026-08-27-i-committed-the-defect-class-i-was-closing-eleven-times.md:203`
  — *"arms 42-43 exist so that sibling presence can never launder HEAD, our own branch, or a tag."* Under a
  create-only softening this stays **true for the move shape arm 43 actually tests**; the sentence becomes
  imprecise, not false, and gets a one-line precision note rather than a rewrite.
- `knowledge-base/project/learnings/2026-05-04-vacuous-red-via-shared-fixture-and-toolchain-pinning.md` —
  *"the RED harness must select inputs that ONLY the branch-under-test can handle."* Drives the mutation
  matrix's create-vs-move separation.
- `knowledge-base/project/learnings/2026-05-12-type-widening-cascades-and-write-boundary-sentinels.md` —
  write-boundary sentinels must cover every site the property applies to (`hr-write-boundary-sentinel-sweep-all-write-sites`).

### Conventions

- Suite discovery is by glob, no manifest: `scripts/test-all.sh:77-90` includes `scripts/lib/*.test.sh`, so
  `repo-write-boundary.test.sh` is already registered and lands in `TEST_GROUP=scripts`.
- `scripts/guard-vacuity-floor.test.sh:630` holds `MIN_FIRING_SUITES=38`; `repo-write-boundary.test.sh`
  counts as one firing suite and has **no** per-file assertion pin, so the suite's own `MIN_ASSERTIONS`
  ratchet is the only floor that moves.
- `scripts/lint-guard-contract.py` rejects a `## Guard Contract` entry missing `**Property.**` /
  `**Assembly.**`, containing a placeholder in either, or carrying `< 3` mutation-matrix rows.
- Consumer: `scripts/test-all.sh` samples BEFORE at `:1130` and AFTER at `:2187`, classifies at `:2191`,
  and only the FATAL branch (`:2217`) increments `failed`, which alone drives `exit 1` (`:2406`).

### Property List (Phase 0.6b)

- **P1** A `refs/tags/*` that appears between the two boundary samples on a checkout where sibling
  worktrees share the ref store does not change the run's exit code.
- **P2** A `refs/tags/*` created where this run is the only candidate author (no sibling worktree — every
  CI runner) still fails the gate.
- **P3** A `refs/tags/*` that is **moved** or **deleted** fails the gate in every regime.
- **P4** Every ref delta is printed and named in every regime — softening never produces silence.

### Cut List (Phase 0.6b)

| Mechanism proposed | Property it would buy | What already covers it → verdict |
|---|---|---|
| Issue Option 1 *as literally worded* — soften created **and moved** tags | P1 | Moves are not sibling-routine traffic (Probe 1), so the move half buys **no** property while costing arm 43. **Cut to create-only.** |
| Issue Option 2 — `git ls-remote --tags origin <name>` to discriminate fetched from authored | P1 | The `shared_store` predicate at `:475` already buys P1. Option 2 additionally **re-derives a classification input after the window closes**, which is the exact laundering shape the `wt` dimension's design comment (`:270-285`) exists to prevent, and adds a network dependency with no defined offline disposition. **Cut.** |
| Issue Option 3 — per-suite snapshotting | attribution | Genuinely correct and far larger than this issue; the issue itself scopes it out. **Cut, tracked as a deferral.** |
| Drop `refs/tags/**` from the measured set, mirroring the `refs/remotes/**` exclusion | P1 | Gives up P2 **and** P3 entirely — a suite deleting a release tag would become invisible. **Cut.** |

### Value proposition (Phase 0.6c)

Not a cost saving; a **signal-integrity** saving, and it is quantified from the issue's own measurement
rather than asserted: one full `TEST_GROUP=all` battery reported `352 passed, 1 failed` where the single
failure was the epilogue reacting to `refs/tags/v3.258.3` — a tag created by `github-actions[bot]` at
`2026-09-03T12:39:48Z` from a different PR — against `353 passed, 0 failed` for the same battery on the
same branch before that tag existed. The false-positive rate is therefore *one per sibling release
landing inside the window*, which at this repo's merge cadence is the common case for a ~15-minute battery.

## Open Code-Review Overlap

`gh issue list --label code-review --state open --limit 200` → 63 open issues; each of
`scripts/lib/repo-write-boundary.sh`, `scripts/lib/repo-write-boundary.test.sh`, `scripts/test-all.sh`
and `scripts/guard-vacuity-floor.test.sh` matched **zero** bodies. **None.**

## Research Reconciliation — Spec vs. Codebase

| Claim (issue #7795) | Reality | Plan response |
|---|---|---|
| "the created/moved tag arm was never wired into that branch" | True as code, **misleading as history**. The archived #7652 plan wired it deliberately and recorded an *accepted residual* for exactly this case. | Frame the change as a **premise reversal**, not an omission. Record the refuted premise at the new arm. |
| Option 1: soften "created **or moved**" tags | A fetch cannot move a local tag (Probe 1). The move half buys no property and costs test arm 43. | Adopt a **narrower** Option 1: **create-only**. |
| Option 2: `git ls-remote --tags origin` discriminates fetched from authored | It discriminates the **wrong property**. `scripts/plugin-delivery-canary.sh:335` fetches with tag auto-follow, so a tag this run authored would also be "on origin" and would launder. It also re-derives a classification input after the window closes. | **Reject**, with this reason recorded. |
| "Keep tags FATAL on the fail-closed no-sibling path (CI), which is where a suite-created tag would matter" | Correct, and sharper than stated: `scripts/plugin-delivery-canary.sh:335` is a real in-battery author. | Keep FATAL **and** remove the author (see Phase 3). |
| *(plan v1's own claim)* "the sweep found two more live-repo fetch sites, so fix all three" | **Half right, and the wrong half was mine.** `lint-migration-fk-preconditions.sh:102` genuinely is *not* battery-reachable — its fetch is gated behind `--from-pr-diff`, which its own `.test.sh` never passes and only `.github/workflows/tenant-integration.yml:145` does. But `run-migrations.sh:200` **is** reachable and my "no test invokes it" evidence was a **`head -5`-truncated grep** — the exact latent-false-negative the plan skill warns about for absence claims. | Drop `lint-migration-fk-preconditions.sh`; **restore `run-migrations.sh` to scope**. |
| *(plan v2's own claim)* "`run-migrations.sh:200` is release-path with no test invoking it" | **Refuted by measurement.** `apps/web-platform/scripts/run-migrations-schema-probe.test.sh` matches `SUITE_GLOBS` (`test-all.sh:88`) and runs under `TEST_GROUP=scripts`/`all` — the exact group this plan's own Phase 5 invokes. It copies the real script to a tmp dir and runs it four times (`:109,:134,:164,:224`) **without `cd`-ing**, so the unconditional `git fetch --quiet origin main` at `:200` runs with the **live repo as cwd**. Executed at plan time: the run created `/tmp/run-migrations-fetch.err`, proving the code path fires. | A **third** battery-reachable live-repo fetch, and one that auto-follows tags. In scope for Phase 3. |
| *(plan v1's own claim)* "after Phase 3 no in-battery path can create a tag" | **Refuted at plan-review (spec-flow P0).** The hand-typed sweep roots omitted `plugins/soleur/test/`, `plugins/soleur/skills/*/test/`, `plugins/soleur/scripts/`, `.claude/hooks/` — including `worktree-manager.sh:2731`, the very fetch this plan names as the tag author, which 15 battery suites drive. | Do **not** claim the author set is closed. State the residual honestly, and defer the real sweep with its root set derived from `scripts/test-all.sh --print-suite-globs` (`:96`) rather than hand-typed. |

## User-Brand Impact

- **If this lands broken (too permissive), the user experiences:** a `353 passed, 0 failed` battery carrying a
  `[REPORT] [refs] refs/tags/<name> (tag) was created` line for a tag a *suite* wrote — one stray tag in their
  own repository, additive, removable with `git tag -d`. No commit, no branch, no working-tree change: HEAD,
  the tree, this worktree's branch, tag **moves** and tag **deletions** all stay FATAL.
  **The bound above is only true while the tag's name is inert, and the first implementation did not enforce
  that** (found at review, fixed before merge). `refs/tags/<n>` resolves ahead of `refs/heads/<n>`, so a
  softened tag sharing a local branch's name silently captures every later `git log/diff/merge/push <n>` for
  that branch. The guard now derives its shadow set from the measured `refs/heads/*` rather than from
  worktree-checked-out branches only; before that narrowing, 18 of this machine's local branches — including
  the operator's own `backup-pre-*` recovery branches — were shadowable at REPORT.
- **If this lands broken (too noisy — i.e. if it is not fixed), the user experiences:** `[FATAL] A SUITE WROTE
  TO THE LIVE REPOSITORY` on a healthy repo roughly once per sibling release landing inside a ~15-minute
  battery, plus the FATAL branch's recovery next-action, on a repository that needs no recovery. By the third
  occurrence the banner is noise, and the #7553/#7652 firing it exists to make visible is invisible.
- **If this leaks, the user's workflow is exposed via:** nothing. This code reads and classifies local git ref
  names; it transmits nothing, stores nothing, and (by rejecting Option 2) opens no network connection.
- **Brand-survival threshold:** `single-user incident`

The two directions are **not** symmetric, and the asymmetry is the case for shipping: the permissive direction
is bounded and printed, the noisy direction is unbounded and silent — it removes the protection by training
dismissal. CPO sign-off recorded in §Domain Review.

## The Change

Split the existing `refs/tags/*)` arm of the created-or-moved loop in `repo_boundary_classify` on `bsha`,
which the loop **already computes** (empty ⇒ the ref is new; non-empty-and-different ⇒ it moved). No new
measurement, no new input, no network:

| Tag event | `shared_store` set (sibling worktrees) | no `shared_store` (CI, single-worktree) |
|---|---|---|
| **created**, collision-free name | `REPORT` — **the only cell that changes** | `FATAL` |
| **created**, name collides (below) | `FATAL` | `FATAL` |
| **moved** | `FATAL` | `FATAL` |
| **deleted** | `FATAL` | `FATAL` |

### The name-collision guard (added at deepen-plan; security-sentinel P1, verified live)

A tag **creation** alone reaches move-grade harm, without moving anything, because
`refs/tags/<n>` resolves **before** `refs/heads/<n>` and `refs/remotes/<n>` in gitrevisions. Measured at
plan time on a throwaway repo — creating a tag literally named `origin/main` while leaving the real
remote-tracking ref untouched:

```
real origin/main   = a5a6179
planted tag        = 3219116
git rev-parse origin/main -> 3219116  (exit 0)      # the tag wins; warning only
git rev-parse origin/main...HEAD                     # resolves via the tag: YES
```

That is not academic here: `scripts/test-all.sh:780` and `:794`, and the `/work`, `/qa` and `/ship` gates,
all scope against the **bare** name `origin/main...HEAD`. A softened creation would silently rescope every
subsequent gate to attacker-chosen content with the exit code unchanged.

**So the CREATED arm stays FATAL when the tag's short name** equals `own_short`, equals `$default_branch`,
appears in `elsewhere`, **or contains a `/`**. Only the collision-free remainder is softened.

**This costs nothing.** Measured on this repo: **3054 tags, zero contain a `/`**, and none is named `main`,
`master`, `HEAD` or `origin` — real release tags are `v3.262.3` / `web-v0.261.4` shaped. Every input the guard
needs is already in scope at the arm (`own_short` `:382`, `default_branch` `:372`, `elsewhere` `:380`).

Why the create/move line is the right one, in one sentence each:

1. **A fetch creates tags and cannot move one** — measured live at plan time (Probe 1), and `--prune` without
   `--prune-tags` deletes none.
2. **A sibling fetches on every session start** — `worktree-manager.sh:2731` inside `cleanup_merged_worktrees()`,
   which `/work` Phase 0 runs per `wg-at-session-start-run-bash-plugins-soleur`.
3. **The known escape shape is only *partly* on the hard side — stated as a residual, not a guarantee.**
   `apps/web-platform/server/git-data-client.ts:244` carries `+refs/soleur/worktrees/<id>/tags/*:refs/tags/*`,
   the repo's only forced tag refspec. Plan v1 claimed this "lands on the FATAL side"; **that claim was false
   and is withdrawn** (architecture-strategist P0). A forced refspec *creates* as readily as it moves, and the
   call's own doc comment describes grafting a peer's tag namespace in, so a grafted tag name absent locally
   classifies as **created** → softened on a machine with siblings. It runs with `{ cwd: workspacePath }`, so
   reaching the live repo requires a cwd escape of the #7553/#7652 class; the *heads* half of that refspec
   targets `refs/remotes/git-data/*`, which `--heads --tags` does not measure at all, so the tag arm is the
   only detector for that shape. **Bounded harder than plan v1 stated** (security-sentinel P2):
   `gitWithPrivateKeyAuth` is mocked in the battery (`apps/web-platform/test/git-data-client.test.ts:19`,
   `ensure-workspace-repo.test.ts:84`), and this guard runs **only** inside `scripts/test-all.sh` — it never
   watches the production server path where the graft actually executes. So it is a narrow residual, not an
   escape the softening admits, and it does **not** block this change. Tracked in §Non-Goals; the collision
   guard above independently blocks the highest-harm instance of it (a grafted peer tag whose name contains a
   `/`, which every `refs/soleur/worktrees/<id>/tags/*` graft target does).
4. **Every way the *discriminator* can be wrong is fail-closed.** A `+refs/tags/*` refspec, `fetch --force --tags`,
   or `fetch.pruneTags=true` would let a sibling move or delete a tag; on such a machine this design yields a
   *false FATAL* — today's failure mode, rarer — and never a laundered pass. Verified on this machine: git
   2.53.0, `remote.origin.fetch = +refs/heads/*:refs/remotes/origin/*`, `tagOpt` unset, `fetch.prune`/
   `fetch.pruneTags` unset. This asymmetry goes in the arm comment; it is the design's strongest justification.

## Defense Relaxation Analysis

Required by `knowledge-base/project/learnings/2026-05-05-defense-relaxation-must-name-new-ceiling.md`.

**What the unconditional tag FATAL was bounding, beyond the reported symptom.** Exactly one in-battery author:
`scripts/plugin-delivery-canary.sh:335`, which fetches into `git rev-parse --show-toplevel` — the live repo —
when the delivered sha is missing locally. Under the new partition that true positive survives only where the
canary almost never fires (CI, single-worktree) and is softened to REPORT on the machine where it does fire
(the operator's, where siblings are always present). **The class would be functionally uncovered exactly where
it triggers.**

**Plan v1's ceiling was false and is withdrawn.** It claimed that adding `--no-tags` to three fetches meant
"no path reachable from `scripts/test-all.sh` can create a tag," so the softening gave up nothing measurable.
Plan-review refuted both halves: two of the three sites are not battery-reachable at all, and the hand-typed
root set omitted `plugins/soleur/test/`, `plugins/soleur/skills/*/test/`, `plugins/soleur/scripts/` and
`.claude/hooks/` — which between them carry at least ten bare live-repo fetches, including
`worktree-manager.sh:2731`, the very fetch this plan names as the tag author, driven by 15 battery suites.
**The author set is not closed, and this plan does not close it.**

**The real ceiling, in three parts.**

1. **CI stays strict, unconditionally.** `elsewhere` is empty on every single-worktree runner, so every tag event
   in CI — created, moved, deleted — remains FATAL. The relaxation exists only where attribution is genuinely
   impossible, and the fail-closed path is the one that gates merges.
2. **Only the creation cell moves.** Tag moves and tag deletions stay FATAL in every regime, as do HEAD, the
   working tree, this worktree's own branch, and every non-tag ref the existing arms already cover. The softened
   set is one cell of a 3x2 table.
3. **Nothing becomes silent.** A REPORT is printed, named with its ref, and counted in the summary observation
   field (`test-all.sh:2334`). The class the guard was filed for (#7553/#7652 — a fixture whose `cd` fails)
   lands on HEAD, the tree and our own branch, all still FATAL.

**What is given up, stated plainly and without hedging.** On a machine with sibling worktrees, a tag *created*
in the live repo by anything — a sibling's fetch **or a suite of this run** — is REPORT rather than FATAL, and
the classifier cannot tell those apart by construction. Two known creators exist inside the battery
(`plugin-delivery-canary.sh:335`, and `worktree-manager.sh:2731` as driven by its suites); this plan closes the
first and defers the rest. The `git-data-client.ts:244` graft escape (§The Change item 3) is likewise not closed.
Both residuals are tracked in §Non-Goals with an explicit trigger. Removing one known author with a one-line
`--no-tags` is worth doing on its own merits and is in scope; claiming it closes the class is not.

## Files to Edit

- `scripts/lib/repo-write-boundary.sh` — split the `refs/tags/*)` created-or-moved arm on `bsha`; correct the
  `shared_store` design comment (currently *"tags too, since sibling traffic does not routinely move them"*);
  correct `_repo_boundary_dim_refs`'s `--heads --tags` rationale, which justifies excluding `refs/remotes/**`
  as *"a fetch is the only thing that writes it"* without noting that a fetch also writes `refs/tags/**` —
  the incompleteness that left tags at full strength.
- `scripts/lib/repo-write-boundary.test.sh` — **tighten** arm 36's assertion in place (presence → presence +
  `FATAL` + end-anchored `was created$`), leave arm 43 **verbatim**, add arms 45-49 (below), raise
  `MIN_ASSERTIONS` 44 → 50.
- `scripts/plugin-delivery-canary.sh` — `--no-tags` on the live-repo fetch at `:335`.
- `apps/web-platform/scripts/run-migrations.sh` — `--no-tags` on the live-repo fetch at `:200`. Battery-reachable
  via `run-migrations-schema-probe.test.sh` (measured, above). The fetch exists only to refresh `origin/main`
  for the unmerged-apply gate, so tags are not wanted; confirm no downstream consumer needs them.
- `scripts/lib/repo-write-boundary.sh` (second edit, security-sentinel Q5) — `_repo_boundary_branches_elsewhere`
  at `:302` does `here="$(git rev-parse --show-toplevel 2>/dev/null)" || here=""`, and the loop's
  `[[ -n "$here" && ... ]] ||` then emits **every** branch — including our own — as `elsewhere`, setting
  `shared_store=1`. That is **fail-open in the lib**, saved today only by a caller-side bare-repo guard 900
  lines away at `test-all.sh:236-240`. Change to `|| return 1`: `_repo_state:270` already routes a non-zero
  return to `wt: not-measured`, which arm 44 proves withholds the softening. One line, fail-closed, and it
  matters more now because this change adds a new consumer of `shared_store`.
- `knowledge-base/engineering/architecture/decisions/ADR-<next>-repo-write-boundary-harm-partition.md` — **new**;
  see §Architecture Decision.
- `knowledge-base/project/learnings/2026-08-27-i-committed-the-defect-class-i-was-closing-eleven-times.md` —
  one-line precision note at the line reading *"arms 42-43 exist so that sibling presence can never launder
  HEAD, our own branch, or a tag"*: arm 43 tests a tag **move**, which still cannot be laundered.

## Files Deliberately NOT Edited

Kept out of `## Files to Edit` so a path extraction over that section cannot read them as targets.

`knowledge-base/project/plans/archive/20260827-143501-*` and
`knowledge-base/project/specs/archive/20260827-163448-*` are point-in-time migration records that must keep
stating the residual as it was accepted then (the `**/archive/**` carve-out convention).
`apps/web-platform/scripts/lint-migration-fk-preconditions.sh` is **out of scope**: its fetch is gated behind
`--from-pr-diff`, which only `.github/workflows/tenant-integration.yml:145` passes and its own `.test.sh` never
does, so it is genuinely not battery-reachable.

`run-migrations.sh` was out of scope in plan v2 on DHH's P0 ("release-path code must not ride a test-gate PR")
and is now **back in scope**, because the premise that put it out was refuted by measurement (§Research
Reconciliation). DHH's underlying concern stands and is answered rather than dismissed: the edit is a single
`--no-tags` flag on a fetch whose only purpose is refreshing `origin/main`, it changes no migration logic, and
`run-migrations-schema-probe.test.sh` covers the file in the same battery.

## Files to Create

- One ADR (see §Architecture Decision). The ordinal is **provisional** — re-derive it against every `origin/*`
  ref immediately before merge, since a sibling PR can claim it mid-pipeline, and sweep this plan and
  `tasks.md` for the old number if it moves.

## Implementation Phases

Ordered contract-before-consumer and RED-before-GREEN (`cq-write-failing-tests-before`).

### Phase 1 — RED: pin the partition before changing it

In `scripts/lib/repo-write-boundary.test.sh`, using the existing `sibling_probe()` / `new_probe()` helpers and
the `-c tag.gpgSign=false` guard arm 36 documents (the global gitconfig forces signed/annotated tags):

**Anti-vacuity requirement on every new assertion.** Today's detail string is `(tag) was created or moved`, so a
regex ending `was created` **prefix-matches it** and would pass vacuously before the Phase 2 change (Kieran P2).
Every new assertion must anchor end-of-line — `\(tag\) was created$` — and each arm must assert the presence of
its expected line, never merely the absence of `FATAL`. Every arm that writes a tag must carry
`-c tag.gpgSign=false` (and `-c tag.forceSignAnnotated=false` where it creates a lightweight tag): the global
gitconfig forces signed/annotated tags, which arm 36's comment already documents as a fixture trap.

- **Arm 36 — tightened in place, not duplicated.** It already creates a tag on a `new_probe` (no sibling) and
  asserts only that `probe-tag` appears. Tighten to `^FATAL[[:space:]]+refs.*probe-tag \(tag\) was created$`.
  This is a strictly *stronger* assertion on an existing arm, and it delivers the no-sibling fail-closed control
  without a twin arm (DHH P1).
**Fixture hermeticity — fix at the seam, not per arm** (test-design P0-2). `state()` / `classify_in()` pin
`GIT_CONFIG_GLOBAL=/dev/null`, but the **fixture mutations do not** — which is exactly why arm 36 needs
`-c tag.gpgSign=false`. Arms 47/48 create commits, so on any machine with global commit signing they break.
Add a `pgit()` wrapper running fixture git under `GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null`
and route the new arms through it, rather than copying `-c` flags five times. **Do NOT** set
`commit.gpgsign=false` inside `new_probe`: arm 4 writes exactly that key as its fixture and would go vacuous.
Note also that plan v1's parenthetical was inverted — `tag.forceSignAnnotated` governs **annotated** tags, so
it is the Guard Contract's must-PASS *annotated-tag* row that is left unguarded without the wrapper.

- **Arm 45** sibling + tag **created**, collision-free name ⇒ `REPORT`, end-anchored. *Fails today.* The RED
  that motivates the change.
- **Arm 46** sibling + tag **deleted** ⇒ `FATAL`. Closes a real coverage gap — **no arm exercises tag deletion
  at all** (`grep` for `tag -d`/`--delete` in the suite → 0 hits). Passes today and after, non-vacuously.
  **Copy arm 40's anchor shape** (`:774`): `grep -qE '^FATAL[[:space:]]+refs.*probe-tag.*DELETED' && ! grep -qE
  '^FATAL[[:space:]]+refs.*<other>'`. A bare `^FATAL[[:space:]]+refs` would match the sibling branch line and
  pass vacuously (test-design Q4).
- **Arm 47** sibling + **two** tag deltas in one run (one created, one moved) ⇒ one `REPORT` **and** one `FATAL`
  in the same verdict, each naming its own tag. *Fails today.* Pins that the partition is per-ref and cannot
  stop at the first member.
- **Arm 48** sibling + a tag created **and** the default branch moved in the same run ⇒ two `REPORT` lines and
  **zero** `FATAL`. *Fails today.* This is the **measured incident shape**: the bot merge that published
  `v3.258.3` also moved `main`, and arms 45-47 are tags-only, so without this arm the actual reported scenario
  is never exercised end-to-end (spec-flow P1). Scope the negative to `^FATAL[[:space:]]+refs`, so an unrelated
  dimension cannot flip it.
- **Arm 49 — the collision guard.** Sibling + a created tag named `origin/main` (contains `/`) ⇒ `FATAL`; and a
  created tag whose name equals `$default_branch` ⇒ `FATAL`. *Fails today* in the sense that it fails against
  the Phase-2 code unless the collision guard is implemented — it is the arm that makes §The Change's
  collision guard real rather than prose.
- **Arm 50 — the epilogue wiring** (test-design P0-1, observability finding 3). Every other arm asserts
  `repo_boundary_classify` **stdout**, but property P1 is about the run's **exit code**, and the Guard Contract's
  Assembly quantifies over `test-all.sh:2217`/`:2406` — coverage no arm currently buys. A mutation making the
  epilogue count REPORT lines into `failed` passes arms 45-49 green. Drive the sandboxed runner the way arms
  23/24/26 already do and assert a REPORT-only run exits 0 while a FATAL run exits 1. (Arm 27 asserts only that
  the exit contract *documents* the REPORT class — not that it behaves that way.)

Raise `MIN_ASSERTIONS` 44 → 44 + the number of new arms (**52** as landed; see AC1). **Assert the floor
and `0 failed`, not a hardcoded pass count** — plan v1
hardcoded the count in three places and was already off by one (Kieran P1, simplicity). Note honestly that
`MIN_ASSERTIONS` is a **deletion** detector, not a **weakening** detector (test-design P1-4): weakening arm 45
back to `grep -q probe-tag` still passes, still counts, and conservation still balances. The mutation matrix is
what catches that, and it runs at author time — this is a known limit of the floor, not a claim against it.

**Cut at plan-review, with reasons:** the `wt`-unmeasured arm (arm 44 already pins that property at the
`shared_store`/`elsewhere` level the new arm reads, and the reorder mutation still reddens via arms 35 and 44 —
DHH + simplicity), and the fetch-based git-semantics fixture (it pins git's behaviour rather than this
classifier's, would redden on an unrelated git upgrade, and defends a mode §The Change item 4 already shows is
fail-closed — DHH + simplicity).

### Phase 2 — GREEN: the classifier

- **2a.** Split the `refs/tags/*)` arm on `bsha` per §The Change. Emit distinct details — `(tag) was created` /
  `(tag) was moved` — instead of today's ambiguous `(tag) was created or moved`. Verify both existing tag arms
  still match: arm 43's `^FATAL[[:space:]]+refs.*probe-tag.*tag` matches `… refs/tags/probe-tag (tag) was moved`
  (the `(tag)` literal supplies the trailing `tag`), and arm 36's `grep -q 'probe-tag'` is severity-agnostic.
- **2b.** Rewrite the two stale comments named in §Files to Edit, and record **at the new arm**: the reversed
  premise plus its measurement (the archived #7652 residual said sibling fetches are rare inside a gate window;
  `worktree-manager.sh:2731` runs one at every session start); the fail-closed asymmetry from §The Change item 4;
  the residual from §The Change item 3; and the caveat that `-z "$bsha"` means *absent from the BEFORE
  measurement*, not *did not exist* — `_repo_boundary_dim_refs` treats `show-ref` rc=1-with-empty-output as
  measured-and-empty, so an empty BEFORE refs family reads every AFTER tag as created (architecture P2).

**Cut at plan-review — the REPORT disposition line (plan v1 Phase 2c, CPO condition 1).** It is not implementable
as specified and would be harmful if forced: `repo_boundary_next_action` is keyed on **dimension**, not event
(`repo-write-boundary.sh:616-624`), so one `refs` string serves tag-created, branch-moved and deleted alike; and
the proposed text required an attribution fact the REPORT branch explicitly refuses to compute, so on the actual
incident shape it would tell a non-technical founder to delete a real release tag (spec-flow P1). The `[REPORT]`
block already states the class and names the ref. Recorded as an accepted divergence from CPO condition 1 in
§Domain Review rather than silently dropped; a correct event-keyed disposition is deferred with the sweep.

### Phase 3 — remove the two battery-reachable tag authors we can close cheaply

Add `--no-tags` to both, after confirming neither has a downstream consumer that needs tags:

- `scripts/plugin-delivery-canary.sh:335` — the fetch exists only to make `$sha` available to `git archive`.
- `apps/web-platform/scripts/run-migrations.sh:200` — the fetch exists only to refresh `origin/main` for the
  unmerged-apply gate.

Assert both in **`plugin-delivery-canary.test.sh` and `run-migrations-schema-probe.test.sh` respectively**, each
of which has its own independent assertion counter — **not** in `repo-write-boundary.test.sh`. Putting a
source-grep arm under the classifier's `MIN_ASSERTIONS` would reintroduce the exact shared-floor shape this plan
cut Guard 2 for (test-design P1-3). Anchor each assertion on the specific fetch command, not a bare `--no-tags`
grep, which would pass if the flag landed on any other fetch in the file.

In-repo precedent: `apps/cla-evidence/scripts/ccla-add.sh:213-215` — *"`git fetch` auto-follows tags, and writing
157 of them into the caller's repository to read one JSON file is a side effect nobody asked for"* — and
`scripts/lib/legal-base-ref.sh:55`.

This removes **two** known authors. It does not close the class — `worktree-manager.sh:2731` and the rest of the
`plugins/` and `.claude/hooks/` fetch population remain. See §Defense Relaxation Analysis and §Non-Goals.

**Cut at plan-review — the structural sweep guard (plan v1 Guard 2 / Phase 4).** Its hand-typed root set omitted
the battery globs that carry most live-repo fetches, so it could have gone green with its own property false
(spec-flow P0, Kieran P1); its AC could not even see the exemption comments it specified, which sit on preceding
lines (Kieran P1); it shared `MIN_ASSERTIONS` with the classifier arms, so classifier arms could be deleted while
the floor stayed green on sweep arms (architecture P2); and it was authored *after* the fix that made the tree
clean, so it never had a RED window (spec-flow P1). Deferred to its own issue with the root set derived from
`scripts/test-all.sh --print-suite-globs` (`:96`) rather than hand-typed, and built RED-first.

### Phase 4 — the ADR

Write the ADR named in §Architecture Decision.

### Phase 5 — verification

`bash scripts/lib/repo-write-boundary.test.sh`; `bash scripts/guard-vacuity-floor.test.sh`;
`python3 scripts/lint-guard-contract.py` against this plan; `bash scripts/plugin-delivery-canary.test.sh`;
`bash plugins/soleur/test/c4-count-parity.test.sh`; `TEST_GROUP=scripts bash scripts/test-all.sh`.

## Guard Contract

### Guard 1 — the refs/tags harm partition

**Property.** A `refs/tags/*` delta observed between the two boundary samples is classified `REPORT` **only**
when all three hold: it is a *creation*; the BEFORE snapshot measured at least one sibling worktree; and the
tag's short name collides with nothing that git resolves ahead of it — not `own_short`, not `$default_branch`,
not a member of `elsewhere`, and containing no `/`. Every other tag delta — any move, any deletion, any creation
on a checkout with no sibling, and any creation whose name could shadow a branch or remote-tracking ref — is
`FATAL`, increments `failed`, and drives the runner's `exit 1`. No tag delta is ever silent.

The two detail strings `(tag) was created` and `(tag) was moved` are **part of this contract, not output
formatting**: they are what arms 45/47/48 discriminate on, so renaming them silently weakens the arms while
preserving the partition (test-design Q2). A change to either is a contract change.

**Assembly.** The property quantifies over the single chokepoint `repo_boundary_classify` in
`scripts/lib/repo-write-boundary.sh` and everything that feeds or consumes its verdict: the created-or-moved
loop's `case "$name"` (all four arms: `refs/tags/*`, `"$own_branch"`, `"refs/heads/$default_branch"`, default)
and its `bsha`/`asha` derivation; the deleted loop's `case` (`refs/tags/*|"$own_branch"` and default); the
`shared_store` assignment at `:475` and its sole input `elsewhere` at `:380`, which is read from the BEFORE
snapshot's `wt` family with `<none>` filtered and has **no** re-derivation fallback; the `wt` manifest row
written by `_repo_state`; the measured ref universe `_repo_boundary_dim_refs` produces (`git show-ref --heads
--tags`, which bounds what the property can quantify over at all); and the two consumer sites in
`scripts/test-all.sh` — the BEFORE sample at `:1130`, the AFTER sample at `:2187`, the classify call at `:2191`,
and the FATAL branch at `:2217` whose `failed` increment is the *only* thing that reaches `exit 1` at `:2406`.
There is exactly one classifier and one consumer; both are named here.

**Mutation matrix.**

| Mutation | Why it must fail (RED) |
|---|---|
| Drop the `-z "$bsha"` conjunct so a **moved** tag also softens under `shared_store` | Arm 43 (`git tag -f` under a sibling) must go RED. This is the shape the repo's only forced tag refspec (`git-data-client.ts:244`) produces when it retargets rather than grafts. |
| Drop the `-n "$shared_store"` conjunct so a created tag softens unconditionally | Arm 36 (tightened: no-sibling create ⇒ `FATAL`) must go RED — the fail-closed CI path would be gone. |
| Move the `refs/tags/*` case into the **deleted** loop's soft branch | Arm 46 (sibling + tag deleted) must go RED. |
| **Reorder / lifetime:** compute `elsewhere` at classify time (`_repo_boundary_branches_elsewhere`) instead of reading the BEFORE snapshot's `wt` family | Arms 35 and 44 must go RED. The property is about the measurement *window*: a suite running `git worktree add -b probe` mid-run would manufacture the siblings that soften its own tag write. A delete-only battery cannot see this — only a row that moves *when* the input is read can. |
| **Second member:** `break` out of the created-or-moved loop after the first classified ref | Arm 47 (two tag deltas in one run) must go RED; a partition that stops at the first member is the defect, not a partial fix. |
| **Cross-dimension:** classify tags only when the refs delta contains *nothing else* | Arm 48 must go RED. The measured incident moved `main` **and** created a tag in the same run; a tags-only reading of the arm passes every tags-only fixture while failing the real shape. |
| **Own dispatch:** make `repo_boundary_classify` `return 0` before the refs block, or make `_repo_boundary_dim_refs` drop `--tags` | Arms 36, 43, 45-50 must go RED and the suite must fail its `MIN_ASSERTIONS` floor, rather than reporting "nothing changed, all clean" and exiting 0. |
| **Vacuous-RED:** write the new assertions un-anchored (`was created` rather than `was created$`) | Arms 45/47/48 must FAIL to distinguish pre- and post-fix output, because `was created` prefix-matches today's `was created or moved`. The anchor is what makes the RED real (Kieran P2). |
| **Collision guard:** drop any one of the four collision conjuncts (`own_short`, `$default_branch`, `elsewhere` membership, contains `/`) | Arm 49 must go RED. A created tag named `origin/main` shadows the remote-tracking ref in gitrevisions — verified live — and `test-all.sh:780`/`:794` plus the `/work`, `/qa` and `/ship` gates all resolve that bare name, so dropping a conjunct silently rescopes every downstream gate. |
| **Exit-code wiring:** make the epilogue count REPORT lines into `failed` (`test-all.sh:2217`) | Arm 50 must go RED. Arms 45-49 assert classifier stdout only and all stay green under this mutation, while property P1 — "does not change the run's exit code" — is false. |
| **Fail-open input:** revert `_repo_boundary_branches_elsewhere`'s `here` read to `|| here=""` | A bare-repo / unreadable-toplevel fixture must go RED. With `here=""` every branch reads as `elsewhere`, so `shared_store=1` is manufactured and the softening applies where no sibling exists. |

**Harness rows.**

| Harness edit (the SUITE, not the guard) | Required outcome |
|---|---|
| Neuter arm 45's fixture so no tag is created, leaving the verdict empty | Must be RED. The arm must assert it *observed* a `refs/tags/probe-tag` classification line, not merely that no `FATAL` appeared — an absence-only assertion passes on an empty verdict. |
| Delete arms 45-50 outright | Must be RED via the `MIN_ASSERTIONS` floor (44 → 50) and the `passes+fails == asserted` conservation check at `:719`. |
| Drop `-c tag.gpgSign=false` from a new arm | Must be RED **legibly**, not environment-dependently: the global gitconfig forces signed/annotated tags, so a bare `git tag` fails fixture setup. Each arm must hard-fail setup with a named message the way arm 36 does at `:649-651`, never fall through to a misleading assertion failure (spec-flow P1). |
| **Must-PASS, non-canonical:** an *annotated* tag created under a sibling | Must PASS as `REPORT` (arm 52). A severity partition must not depend on tag object type, and arms 45-49 all create LIGHTWEIGHT tags — an annotated tag puts a different sha through the same `bsha`/`asha` compare. |
| ~~a tag created under a sibling whose name contains a `/` (`refs/tags/rel/1.0`) must PASS as `REPORT`~~ | **WITHDRAWN at /work — it contradicted this contract's own Property.** This row predates the collision guard, which was added at deepen-plan (security-sentinel P1) and which the Property, AC9 and a mutation-matrix row all state makes a `/`-containing name **FATAL**. Field-exact matching handles `/` for *reporting*; it says nothing about severity. Kept struck through rather than deleted so the contradiction is visible rather than tidied away. Arm 49's first fixture is exactly `refs/tags/origin/main`. |

## Observability

The strict Phase 2.9 trigger set (`apps/*/server`, `apps/*/src`, `apps/*/infra`, `plugins/*/scripts`, or new
infrastructure) does **not** match `scripts/lib/`, and this plan introduces no production surface. The block is
supplied anyway because the deliverable is a guard whose failure mode is silence.

**Layer citation (`hr-observability-layer-citation`), stated rather than left implicit.** Layers 1-6 are
**N/A** — there is no server surface, no route, no Inngest function, no cron, no host. Layer 7 (code executing
on a customer's self-hosted CLI) is **N/A** here too: this classifier runs under `scripts/test-all.sh`, which is
this repo's own dev/CI gate, not a `plugins/` artifact shipped to a customer. The covering channel is the
**synchronous runner exit code plus the CI job log** — a layer-6 analogue. Every `alert_route` below resolves to
that channel; where it does not, the mode says so explicitly.

**Probe honesty.** `discoverability_test.command` exercises the *library*, while `liveness_signal` is the
*epilogue and exit code*. Arms 21/22 already pin part of the consumer wiring (the lib is sourced above
`tc_acquire`; exactly two `_repo_state` call sites), and new **arm 50** closes the rest by asserting a
REPORT-only run exits 0 and a FATAL run exits 1 — without it the probe could pass green while the FATAL→`failed`
→`exit 1` chain is severed (observability review P2, test-design P0-1).

```yaml
liveness_signal:
  what: the boundary epilogue block `scripts/test-all.sh` prints after the AFTER snapshot — `[FATAL] A SUITE
        WROTE TO THE LIVE REPOSITORY` or `[REPORT] A SHARED store changed…`, plus the per-line `[refs]` details
        and the summary observation field
  cadence: every `scripts/test-all.sh` invocation — the `/work` Phase 2 exit shard set, the `/ship` Phase 4
        full battery (ADR-183), and CI's test job
  alert_target: the runner's exit code (1 whenever any FATAL is present), surfaced as the CI job status and as
        the local terminal verdict
  configured_in: scripts/test-all.sh:1130 (BEFORE), :2187 (AFTER), :2191 (classify), :2211-2296 (render)
error_reporting:
  destination: the runner's stderr epilogue, and the non-zero exit propagated to the CI job
  fail_loud: yes — a FATAL increments `failed` at :2217, and `failed` alone drives `exit 1` at :2406. A REPORT
        is printed and counted in the summary observation field at :2334, so the soft class is never silence.
failure_modes:
  - mode: the softening is too broad — a tag a suite authored is REPORTed instead of failing the run. NOTE this
        is a KNOWN, ACCEPTED residual under `shared_store`, not a hypothetical: the classifier cannot separate
        a suite-authored tag from a fetched one, and known battery creators remain (see §Defense Relaxation
        Analysis). Detection below covers the arms that bound it, NOT the residual itself.
    detection: arms 43, 46, 47 (moves, deletions and per-ref partitioning stay FATAL) and arm 36 (the
        no-sibling fail-closed path) in scripts/lib/repo-write-boundary.test.sh; arm 49 pins the one author
        this plan removes
    alert_route: suite exit 1 → `scripts/test-all.sh` exit 1 → CI test job failure
  - mode: the softening fails to apply and the sibling-release false positive returns
    detection: arm 45
    alert_route: same
  - mode: the softening is bought by a MISSING measurement (`wt` uncaptured on one side)
    detection: arm 48, mirroring arm 44
    alert_route: same
  - mode: the classifier goes vacuous — emits nothing and the epilogue reports a clean run
    detection: MIN_ASSERTIONS=50 inside the suite, plus the MIN_FIRING_SUITES=38 population ratchet at
        scripts/guard-vacuity-floor.test.sh:630, which counts this suite as a firing suite
    alert_route: same
  - mode: THE ACCEPTED RESIDUAL ITSELF — a real suite-authored tag creation goes unpunished under
        `shared_store`. Declared as its own mode because the five modes above are all guard-REGRESSION modes,
        and this is the one live-failure mode the plan actually accepts (observability review P1).
    detection: a runtime signal DOES exist and must not be described as absent — the
        `[REPORT] A SHARED store changed…` block at test-all.sh:2247 names the ref, and the summary
        observation field at :2334 counts it
    alert_route: NO exit code, human read only. This is the honest limit: the signal is printed, never
        actioned. The review path is §Non-Goals issue 1 (the battery tag-author sweep), whose trigger is
        immediate for exactly this reason.
  - mode: a future git version or fetch config makes a fetch clobber an existing tag, falsifying the
        create/move discriminator
    detection: none by test — deliberately so. The failure direction is a FALSE FATAL (§The Change item 4), so
        it surfaces as a red gate naming the tag, which is today's behaviour and self-announcing. A dedicated
        arm was cut at plan-review as testing git rather than this classifier.
    alert_route: the existing FATAL epilogue, naming the ref
logs:
  where: the runner's stdout/stderr; for CI runs, captured in the GitHub Actions job log for the test job
  retention: GitHub Actions default log retention for CI runs; local runs are terminal-scoped and not retained
discoverability_test:
  command: bash scripts/lib/repo-write-boundary.test.sh
  expected_output: exit 0, final line of the form `repo-write-boundary.test.sh: <N> passed, 0 failed, <N>
        assertion(s) executed (floor 50)` with N >= 50 — the floor and `0 failed` are the assertion, not a
        hardcoded pass count
```

## Architecture Decision (ADR/C4)

**One ADR is created.** Plan v1 filed none, reasoning that `grep -rl 'repo-write-boundary|write boundary|
shared_store|shared ref store' knowledge-base/engineering/architecture/decisions/` returns **0 hits**, so no ADR
is amended or falsified. That remains true and is why `wg-architecture-decision-is-a-plan-deliverable` is not
*literally* triggered. Architecture-strategist's advisory is adopted anyway, and it is the stronger argument:
the FATAL/REPORT/UNMEASURABLE partition — *attribution, not severity* — **is** an architectural contract, this
change is its **third** exemption, the plan itself concedes a fourth would make the soft class the default, and
its only record today is a comment block no index reaches. Write
`ADR-<next>-repo-write-boundary-harm-partition.md` recording: the partition and its rationale; the measurement
invariant (classification inputs come from the BEFORE snapshot, never re-derived at classify time); and an
**exemption ledger** listing all three exemptions with the evidence that justified each — so the fourth request
is visibly the fourth. The ordinal is provisional (see §Files to Create).

**C4: no impact**, checked against all three model files (`knowledge-base/engineering/architecture/diagrams/`
`model.c4`, `views.c4`, `spec.c4`) rather than by grepping the feature's own noun. Enumerated for this change:
(a) **external human actors** — none; the change adds no correspondent, reviewer or recipient. (b) **external
systems/vendors** — none; Option 2 was rejected specifically because it would have added a network call to
`origin`, so no new integration edge exists. (c) **containers/data stores** — none; no store is read or written.
(d) **actor↔surface access relationships** — none; this is a local test-runner classifier with no surface an
actor reaches. Cardinality backstop: the change adds no workflow, cron monitor or heartbeat slug, so the counts
`model.c4` embeds in edge prose do not move; `plugins/soleur/test/c4-count-parity.test.sh` — the real path of
the parity *script*, which lives under `plugins/soleur/test/` rather than the `apps/web-platform/test/`
directory named in the plan-skill mandate (that directory does exist and holds 600+ files; only this script is
elsewhere — Kieran P2) — is prescribed as AC12 to back that conclusion with a green run rather than reasoning.

## Acceptance Criteria

### Pre-merge (PR)

All criteria are pre-merge; this plan has no post-merge steps.

1. `bash scripts/lib/repo-write-boundary.test.sh` exits 0, its final line reports `0 failed`, and its passed
   count equals the printed floor, which is **`44 + <new arms>`** — derived at /work, not carried from
   here. It landed at **52**: the plan projected 50 for arms 45-50, and /work added two more that the
   Guard Contract's own rows demand and the arm list had missed — arm 51 for the *Fail-open input*
   mutation row (nothing else exercised `_repo_boundary_branches_elsewhere`'s return), and arm 52 for
   the *must-PASS annotated tag* harness row. Assert the floor and zero failures, **never** a hardcoded
   pass count (plan v1 hardcoded it in three places and was already off by one).
2. Arm 43 is unchanged: extracting its body from both revisions and diffing is empty —
   `diff <(git show origin/main:scripts/lib/repo-write-boundary.test.sh | sed -n '/--- 43\./,/--- 44\./p')
   <(sed -n '/--- 43\./,/--- 44\./p' scripts/lib/repo-write-boundary.test.sh)` prints nothing. (Arm 36 is
   deliberately *strengthened*, not preserved, so it is excluded from this AC — a presence-only assertion
   gaining a severity anchor is not an inversion. Plan v1's version of this AC named a whole-file `git diff`
   that could not scope to an arm body and was non-empty by construction — Kieran P1.)
3. A sibling-worktree fixture whose only delta is a **created** tag yields exactly one line matching
   `^REPORT[[:space:]]+refs.*\(tag\) was created$` and **zero** `^FATAL` lines (arm 45). The `$` anchor is
   load-bearing: without it the pattern prefix-matches today's `was created or moved` and the arm passes
   vacuously pre-fix.
4. A no-sibling fixture whose only delta is a created tag yields `^FATAL[[:space:]]+refs.*\(tag\) was created$`
   (arm 36, tightened).
5. A sibling fixture whose only delta is a **deleted** tag yields `^FATAL[[:space:]]+refs.*was DELETED` (arm 46).
6. A sibling fixture with one created **and** one moved tag yields exactly one `REPORT` and one `FATAL`, each
   naming its own tag (arm 47).
7. A sibling fixture with a created tag **and** a moved default branch — the measured incident shape — yields
   two `REPORT` lines and zero `FATAL` lines (arm 48).
8. `sed -n '507p' scripts/lib/repo-write-boundary.sh | grep -c 'created or moved'` returns `0`, **and**
   `grep -c 'created or moved' scripts/lib/repo-write-boundary.sh` returns `3` — the three non-tag arms at
   `:519`, `:521`, `:523` are deliberately untouched. (Plan v1 demanded `0` repo-wide, which is unsatisfiable
   without out-of-scope edits: the literal appears 4 times, only one of which is the tag arm — Kieran + spec-flow P0.)
9. A sibling fixture + a created tag named `origin/main` yields `^FATAL`, and so does one whose name equals
   `$default_branch` (arm 49 — the collision guard). Neither yields a `REPORT`.
9b. A REPORT-only run exits **0**; a run with a FATAL exits **1** (arm 50 — the epilogue wiring the
   Guard Contract's Assembly claims). **Mechanism changed at /work:** "drive the sandboxed runner the
   way arms 23/24/26 do" is not available for this property. Those arms reach only the runner's early
   *refusal* path (they exit 2 before any suite); reaching the EPILOGUE means running the whole battery,
   ~45 minutes per arm and holding the repo-global advisory lock, twice. Instead arm 50 extracts the two
   regions of the REAL runner that carry the chain — anchored on the content `if [[ -n "$_repo_verdict" ]]; then`
   and `_repo_boundary_reported=1`, never on a line number — and executes them verbatim under the
   runner's own `set -euo pipefail`. The extraction hard-fails if either anchor is missing, so a refactor
   that moves the chain reports a FIXTURE error rather than silently testing nothing.
9c. `scripts/plugin-delivery-canary.sh:335` and `apps/web-platform/scripts/run-migrations.sh:200` both carry
   `--no-tags`, each asserted in its **own** suite (`plugin-delivery-canary.test.sh`,
   `run-migrations-schema-probe.test.sh`) anchored on the specific fetch command, not a bare flag grep. Both
   suites exit 0.
9d. `_repo_boundary_branches_elsewhere` fails **closed**: with `git rev-parse --show-toplevel` unreadable it
   returns non-zero, `_repo_state` records `wt: not-measured`, and the softening is withheld (the arm-44 path).
10. The comment at the `shared_store` block no longer contains `tags too, since sibling traffic does not
    routinely move them`, and the new arm's comment records all four of: `worktree-manager.sh:2731`; the
    fail-closed asymmetry; the `git-data-client.ts:244` graft residual; and the `-z "$bsha"` =
    *absent-from-the-BEFORE-measurement* caveat.
11. `bash scripts/guard-vacuity-floor.test.sh` exits 0 (`repo-write-boundary.test.sh` still counted as a firing
    suite; `MIN_FIRING_SUITES=38` unchanged).
12. `python3 scripts/lint-guard-contract.py` passes against this plan file;
    `python3 scripts/lint-infra-no-human-steps.py` passes against it; and
    `bash plugins/soleur/test/c4-count-parity.test.sh` exits 0.
13. `TEST_GROUP=scripts bash scripts/test-all.sh` exits 0 with no `[FATAL]` boundary block.
14. Every `knowledge-base/` path cited in this plan resolves **except** the deliberately-cited-as-absent
    `knowledge-base/project/specs/<branch>/spec.md` in §Notes and the provisional ADR filename, which are
    excluded by name from the check. (Plan v1's version of this AC was self-falsifying — its own command flagged
    the spec path the plan itself states does not exist — Kieran P1.)
15. **Three** tracking issues exist and are linked in the PR body, each carrying its re-evaluation
    trigger: **#7917** the battery tag-author sweep, **#7918** the graft residual, **#7919** the
    manifest-driven renderer + per-suite snapshotting. This AC said "two" while §Non-Goals said
    three; the count is reconciled to three here. The mandated `code-simplicity-reviewer` CONCUR
    gate DISSENTED on folding the last two into one tracker — they share no code, no surface and no
    trigger, so a merged tracker's first trigger would reopen an issue whose other half is stale and
    cannot be closed. Net issue flow for this PR: closing 1, filing 3, **net +2**.
16. The new ADR exists, its ordinal was re-derived against all `origin/*` refs immediately before merge, and no
    other artifact in this branch cites a stale ordinal:
    `grep -rn 'ADR-<chosen>' knowledge-base/project/{plans,specs}/` resolves consistently.

## Test Scenarios

Every scenario is a `mutation → guard reddens` pair, per ADR-180; the `command → output` shape belongs in the
Acceptance Criteria above.

| # | Mutation applied to the tree | Expected |
|---|---|---|
| T1 | Revert the `-z "$bsha"` conjunct (moved tags soften too) | arm 43 RED |
| T2 | Revert the `-n "$shared_store"` conjunct (creates soften always) | arm 36 RED |
| T3 | Route tag deletions through the soft branch | arm 46 RED |
| T4 | Re-derive `elsewhere` at classify time | arms 35 + 44 RED |
| T5 | `break` after the first classified ref | arm 47 RED |
| T6 | Classify tags only when the refs delta is tags-only | arm 48 RED (the measured incident shape) |
| T7 | `return 0` before the refs block in `repo_boundary_classify` | arms 36, 43, 45-50 RED + `MIN_ASSERTIONS` floor RED |
| T8 | Drop `--tags` from `_repo_boundary_dim_refs` | arms 36, 45-48 RED |
| T9 | Write the new assertions un-anchored (`was created`, no `$`) | arms 45/47/48 pass pre-fix ⇒ the harness is vacuous; the anchored form is what makes RED real |
| T10 | Strip `--no-tags` from `plugin-delivery-canary.sh:335` | arm 49 RED |
| T11 | Neuter arm 45's fixture so the verdict is empty | arm 45 RED (asserts presence, not absence) |
| T12 | Drop `-c tag.gpgSign=false` from a new arm | fixture setup hard-fails with a named message, not a misleading assertion failure |
| T13 | *(must-PASS)* an annotated tag created under a sibling | `REPORT`, suite green (arm 52). The `rel/1.0` half is **withdrawn** — see the struck harness row above; a `/` in the name is FATAL by the collision guard. |

## Precedent Diff (deepen-plan Phase 4.4)

The pattern-bound behaviour here is a `shared_store`-gated arm inside `repo_boundary_classify`'s
created-or-moved `case`. **Precedent exists in the same `case` statement** — the
`"refs/heads/$default_branch")` arm at `:510-515` is the canonical form, so the new arm must mirror it rather
than invent a shape:

```bash
          "refs/heads/$default_branch")                     # <- the precedent
            if [[ -n "$shared_store" ]]; then
              printf 'REPORT\trefs\t%s is the default branch and it moved (the sibling `git pull` shape)\n' "$name"
            else
              printf 'FATAL\trefs\t%s is the default branch and it moved\n' "$name"
            fi ;;
```

Diff against the planned tag arm: **same** `if [[ -n "$shared_store" ]]` test, **same** REPORT/FATAL ordering,
**same** convention of naming the producing shape in the REPORT detail (`the sibling git pull shape` →
`the fetched-release-tag shape`). The **only** structural addition is the `-z "$bsha"` conjunct, which the
default arm at `:516-524` has no need for because heads legitimately move under sibling traffic while tags do
not. No novel pattern is introduced.

Also checked: the plan introduces no scheduled job, so the Phase 4.4 scheduled-work sub-gate (Inngest vs GH
Actions cron, ADR-033) is not applicable — the repo has 54 `cron-*` Inngest functions and this plan adds none.

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| An operator's git config (`+refs/tags/*` refspec, `fetch --force --tags`, `fetch.pruneTags=true`) lets a sibling move or delete a tag, so "moves are never sibling-routine" is false on that machine. | Fail-closed by construction: the result is a *false FATAL* — today's behaviour, rarer — never a laundered pass. Recorded in the arm comment (AC10). Verified absent on this machine: git 2.53.0, no `tagOpt`, no `fetch.prune*`, `remote.origin.fetch = +refs/heads/*:refs/remotes/origin/*`. |
| `--no-tags` on a fetch whose downstream consumer needs tags. | Phase 3 requires per-site confirmation before the flag is added, with a declared exemption as the alternative. `run-migrations.sh:200` is the one to check first — it runs in the release path, not only the battery. |
| Changing the detail string breaks an existing assertion. | AC2 + AC8. Arm 43's regex was checked against the new `… (tag) was moved` output at plan time: the literal `(tag)` supplies the trailing `tag` its pattern needs. |
| `scripts/plugin-delivery-canary.test.sh` asserts on the canary's exact fetch invocation. | Its fetch-related assertions are about which *sha* was fetched (`net/pin` rows), not the flag list; Phase 5 re-runs that suite regardless. |
| Repeat softening of this guard erodes it; enough exemptions make the soft class the default. | **Ordinal corrected at /work — this row said "the third softening" and that is not reproducible from history.** `git log -S'shared_store'` over the library returns exactly two commits, so #7795 is the **second decision event** and the **sixth softened cell**; [ADR-207](../../engineering/architecture/decisions/ADR-207-repo-write-boundary-harm-partition.md) carries the ledger and the correction. Deferral filed with an explicit **trigger**, not open-ended (CPO condition 3), so the seventh cell is visibly the seventh. |
| Reviewers read the archived #7652 residual as current precedent. | Phase 2b records the reversal at the new arm; the archived artifacts stay untouched as point-in-time records. |
| **The softening's safety rests on an author set this plan does not close.** Under `shared_store` the classifier cannot distinguish a suite-authored tag from a fetched one, and known battery creators remain after Phase 3. | Stated without hedging in §Defense Relaxation Analysis, bounded by the three-part ceiling (CI strict, creation-cell only, nothing silent), and tracked as §Non-Goals issue 1 with an *immediate* trigger. This is the plan's single largest accepted risk and must not be described as closed. |
| Plan v1 asserted three claims that review refuted (the graft "lands on the FATAL side"; "no in-battery path can create a tag"; the manifest-based deferral rationale). | All three withdrawn in place with the refutation recorded, rather than quietly edited — the same discipline the boundary file applies to its own comments. |

## Alternative Approaches Considered

| Approach | Why not |
|---|---|
| **Issue Option 1 verbatim** — soften created **and** moved tags | A fetch cannot move a local tag (Probe 1), so the move half buys no property; it would cost test arm 43, a deliberate non-vacuity assertion, and would soften the one shape the repo's only forced tag refspec (`git-data-client.ts:244`) produces. |
| **Issue Option 2** — `git ls-remote --tags origin <name>` | Discriminates the **wrong property**: a tag this run authored via the canary's auto-following fetch is also "on origin", so it would launder rather than discriminate. It re-derives a classification input *after* the measurement window closes — the exact laundering shape the `wt` design forbids — and adds a network call with no defined offline disposition (it would also newly trigger the Encryption Posture gate, which this plan otherwise skips: no store, no new cross-component connection). |
| **Issue Option 3** — snapshot per suite | Correct and much larger than this issue; deferred with a trigger (below). |
| **Drop `refs/tags/**` from the measured set**, mirroring the `refs/remotes/**` exclusion | Gives up the move and delete arms entirely — a suite deleting a release tag would become invisible. |
| **Sharper discriminator: tag created AND ≥1 `refs/remotes/*` delta ⇒ REPORT** (CTO §3) | Genuinely sharper than `shared_store` and still pure BEFORE/AFTER measurement. Plan v1 deferred it on the grounds that widening `_repo_boundary_dim_refs` "changes the manifest and therefore the inspected claim" — **that reasoning is mechanically wrong** and is withdrawn: `repo_boundary_render_inspected` iterates manifest *rows*, and widening `show-ref` adds no row (architecture P1). Deferred for two sounder reasons: (a) remotes deltas would flow into a refs harm partition that has no arm for them, so the correct shape is a **fifth dimension**, which *does* move the manifest; (b) `repo_boundary_render_not_inspected` ends in a **hardcoded heredoc** that literally lists `- remote-tracking refs (refs/remotes/**)`, so the not-inspected half of the operator claim is not rendered from the check — the file's own claim-cannot-outrun-the-check invariant, violated in its own renderer. That heredoc is the real blocker and is recorded as the debt. |

## Non-Goals / Deferrals

Three tracking issues, all created in the same PR and linked from its body (AC15), each with an explicit
re-evaluation **trigger** rather than an open date:

1. **The battery tag-author sweep — filed as #7917.** Assert that no `git fetch` reachable from
   `scripts/test-all.sh` writes tags into the live repository. **Correction applied at /work:** this plan
   prescribed deriving the root set from `scripts/test-all.sh --print-suite-globs` alone, and that
   prescription is itself incomplete in the same way it was written to fix. Measured: the globs return 9
   entries and `scripts/*.test.sh` is deliberately NOT among them — the runner registers 77 such suites by
   hand — and `tests/scripts/` appears in neither. The root set is `SUITE_GLOBS` **union** the explicit
   `run_suite` registrations. Root set derived, never
   hand-typed — plan v1's hand-typed roots omitted `plugins/soleur/test/`, `plugins/soleur/skills/*/test/`,
   `plugins/soleur/scripts/` and `.claude/hooks/`, which carry at least ten bare live-repo fetches including
   `worktree-manager.sh:2731`. Build it **RED first** (observe it name every offending site before fixing any),
   give it its own assertion counter rather than sharing `MIN_ASSERTIONS`, and make its AC use `-B2` so it can
   actually see exemption comments, which sit on preceding lines. *Trigger: immediately — this is the residual
   that bounds §Defense Relaxation Analysis.*
2. **The `git-data-client.ts:244` graft residual — filed as #7918.** On a shared store this plan's softening blinds the one
   escape shape where a forced `+refs/soleur/worktrees/<id>/tags/*:refs/tags/*` graft creates tags in the live
   repo under a cwd escape, and the heads half of that refspec is invisible to `--heads --tags`. *Trigger: the
   next change to `ensure-workspace-repo` or the graft call site, or any recurrence of the #7553/#7652 class.*
3. **Per-suite snapshotting** (Option 3) and **widening to a fifth `refs/remotes/**` dimension** (the sharper
   discriminator), blocked on `repo_boundary_render_not_inspected`'s hardcoded heredoc — **filed as #7919**.
   Narrowed at /work: the function's opening loop ALREADY derives from `repo_boundary_manifest()`, and only
   the trailing `cat <<'EOF'` is a literal — so the blocker is a small self-contained fix, not a rewrite. *Trigger: the next time
   any dimension needs a fourth exemption from the FATAL class, implement real per-suite attribution instead of
   adding the exemption.*

Also out of scope: an **event-keyed** REPORT disposition line (`repo_boundary_next_action` is dimension-keyed;
see Phase 2's cut note) — folded into issue 3. And **rewriting the archived #7652 plan/spec**, which are
point-in-time records.

## Domain Review

**Domains relevant:** engineering, product

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Discriminator correct — a repo-wide grep for tag writers outside tests found exactly three
non-test paths, and the split puts the only force-move author (`git-data-client.ts:244`, the repo's only forced
tag refspec) on the FATAL side. Local config corroborates Probe 1. Identified one real gap and required it in
scope: the unconditional FATAL was bounding `plugin-delivery-canary.sh:335`, whose true positive would survive
only where it never fires — closed by the `--no-tags` sweep (Phase 3/4) with in-repo precedent at
`ccla-add.sh:213-215`. Endorsed no-ADR, conditional on recording the reversed premise at the new arm (Phase 2b),
and flagged that the deferred remotes-widening *would* require one. Named a sharper discriminator and
recommended deferring it. Complexity: small.

### Product/UX Gate

**Tier:** none — no user-facing surface. `## Files to Edit` contains no path matching the UI-surface term list
or glob superset (no `components/**/*.tsx`, `app/**/page.tsx`, `app/**/layout.tsx`), so the mechanical override
does not fire. `ux-design-lead` is not applicable (`wg-ui-feature-requires-pen-wireframe` does not reach a
change with no UI surface).

### Product (CPO) — sign-off, required by `brand_survival_threshold: single-user incident`

**Status:** reviewed
**Decision:** **APPROVE**, conditional on three items, all addressed below.

1. Add a disposition line to the `[REPORT]` branch — `repo_boundary_next_action` renders only in the FATAL
   branch (`test-all.sh:2229`), so a REPORT names a delta with no next step. → **not adopted as specified**;
   see the divergence note below and §Non-Goals issue 3.
2. Supply `## User-Brand Impact` and the `§Defense Relaxation Analysis` the plan referenced. → both present above.
3. File the Option-3 deferral with a **trigger**, not open-ended. → §Non-Goals.

**Assessment:** the threshold is correctly stated and the risk is **asymmetric**. Too-permissive is bounded
(creation is additive; it cannot move or delete a ref or touch HEAD/tree/uncommitted work, all of which stay
FATAL) and stays printed and counted. Too-noisy is unbounded: it trains dismissal of the one banner that names
the #7553 class, and a guard the founder has learned to skip is a guard that does not exist. For a
non-technical solo founder the noisy direction is the greater brand risk because it removes the protection
*silently*. The narrowing (create-only, sibling-only) matches the measured-benign set exactly. CI staying strict
on every single-worktree runner is the named new ceiling.

**Agents invoked:** cto, cpo, plus a `model: fable` scoped advisor consult (ADR-083)
**Skipped specialists:** none

**Divergence from CPO condition 1, recorded rather than silently dropped:** the REPORT disposition line is cut.
It is not implementable as specified (`repo_boundary_next_action` is dimension-keyed, not event-keyed) and the
proposed text would tell a non-technical founder to delete a real release tag on the actual incident shape
(spec-flow P1). The underlying concern — a REPORT should not be a dead end — is real and is folded into
§Non-Goals issue 3 as an event-keyed disposition.

### Plan Review (5-agent panel, escalated by the `single-user incident` threshold)

Panel: dhh-rails-reviewer, kieran-rails-reviewer, code-simplicity-reviewer, architecture-strategist,
spec-flow-analyzer. **Nine findings applied; the plan shrank materially and three of its claims were refuted.**

| Finding | Class | Disposition |
|---|---|---|
| **P0** (architecture) — "the graft lands on the FATAL side" is false; a forced refspec creates as readily as it moves, so the escape shape is laundered under `shared_store` | mechanical | Claim withdrawn; residual stated in §The Change item 3 and tracked as §Non-Goals issue 2 |
| **P0** (spec-flow, Kieran) — Guard 2's hand-typed root set omitted the battery globs carrying most live-repo fetches, including `worktree-manager.sh:2731`, the very fetch the plan names as the author | mechanical | Guard 2 and the exhaustive Phase 3 **cut**; deferred with the root set derived from `--print-suite-globs`; the false "no in-battery author remains" ceiling withdrawn |
| **P0** (Kieran, spec-flow) — AC10 unsatisfiable: `grep -c 'created or moved'` is 4, only one of which is the tag arm | mechanical | AC8 rewritten to assert line 507 specifically and `3` repo-wide |
| **P1** (Kieran) — AC1 arm arithmetic off by one; the count was hardcoded in three places | mechanical | Assert the floor and `0 failed`, never a hardcoded pass count |
| **P1** (Kieran) — AC2 could not scope a diff to an arm body and was non-empty by construction | mechanical | Rewritten as a `sed`-extracted range diff, scoped to arm 43 only |
| **P1** (Kieran) — AC14 self-falsifying: its own command flagged the spec path the plan states does not exist | mechanical | Exclusions named explicitly |
| **P2** (Kieran) — `was created` prefix-matches today's `was created or moved`, so unanchored new arms pass vacuously pre-fix | mechanical | End-anchoring made a stated requirement, a mutation-matrix row, and T9 |
| **P1** (spec-flow) — the measured incident (tag created **and** `main` moved) was never exercised; new arms were tags-only. Arms also lacked arm 36's `-c tag.gpgSign=false` fixture guard | mechanical | Arm 48 added; the gpgSign guard made a requirement and a harness row |
| **P1** (spec-flow) — Phase 2c not implementable and harmful as specified | mechanical | Cut, with the divergence from CPO condition 1 recorded above |
| **P1** (architecture) — the deferral's stated reason was mechanically wrong (`render_inspected` iterates manifest rows) | mechanical | Restated on the real blocker: `render_not_inspected`'s hardcoded heredoc |
| **P1** (architecture) — advisory: file one ADR recording the partition + an exemption ledger | taste → accepted | §Architecture Decision now files one |
| **P0** (DHH) — Guard 2 / Phase 3 are a separate concern; `run-migrations.sh` is release-path code that must not ride a test-gate PR | taste → accepted | Scope cut to the one battery-reachable author; the other two sites verified **not** battery-reachable and dropped |
| **P1** (DHH, simplicity) — three of plan v1's proposed arms were redundant, or tested git rather than this code | taste → accepted | v1's no-sibling-create arm folded into a **tightened arm 36**; v1's `wt`-withheld arm and v1's fetch-based git-semantics arm **cut**. Note the numbering: v2's live arms 46 and 48 are *different, new* arms (tag deletion; the tag + default-branch incident shape) and are unaffected by this row |
| **P2** (DHH) — the `single-user incident` threshold is ceremony for a local dev-gate tweak | taste → **rejected, with reason** | The threshold is what convened the escalated panel that found the P0s above, including a false claim that would have shipped a laundering shape. It paid for itself. |

### Scoped advisor consult (Phase 4.5, `model: fable`)

Verdict: approach sound, and **every way the discriminator can be wrong is fail-closed**. Three findings folded
in: (a) the config asymmetry now stated explicitly in the arm comment (AC10) — *"the plan's strongest
justification, currently only implicit"*; (b) a stronger reason to reject Option 2 — origin-existence does not
discriminate *author*, since the canary's auto-following fetch would make this run's own write "on origin";
(c) pin the measured git behaviour with a **fetch-based** fixture rather than `git tag` — *subsequently cut by
the plan-review panel* (DHH + simplicity: it tests git, not this classifier, and the mode it defends is already
fail-closed); the residual is recorded as a `failure_modes` entry with `detection: none by test` instead.
Independently
converged with the CTO on the `--no-tags` scope addition.

### Compliance gates

- **GDPR (Phase 2.7):** the canonical regulated-data regex does not match (no schema, migration, auth flow, API
  route or `.sql`), and none of the expansion triggers (a), (c), (d) fire — no LLM/external-API processing of
  operator data, no cron reading `learnings/` or `specs/`, no new artifact distribution surface. Trigger (b)
  fires only because the plan declares `single-user incident`. Advisory: the diff processes **no personal data
  of any kind** — it reads local git ref *names* and classifies them. No lawful-basis, Art. 9 or Art. 30 finding.
- **IaC routing (Phase 2.8):** skipped — no server, service, cron, vendor account, DNS record, cert, secret or
  firewall rule. No detection phrase present.
- **Encryption posture (Phase 2.11):** skipped — no persistent store and no new cross-component connection.
  Rejecting Option 2 is what keeps this true.

## Notes

- Spec carry-forward: `knowledge-base/project/specs/feat-one-shot-7795-tag-shared-store-softening/spec.md` does
  not exist, so no `lane:` could be carried forward. Spec lacks valid lane: — defaulted to cross-domain (TR2
  fail-closed).
- **Sharp edge for `deepen-plan` / `/work`:** a plan whose `## User-Brand Impact` section is empty, contains only
  `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. The section above is
  complete; keep it that way through any revision.
