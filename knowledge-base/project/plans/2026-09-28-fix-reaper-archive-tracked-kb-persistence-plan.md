---
title: "fix: reaper archives tracked KB files via mv — next session's reset --hard resurrects live copies (stranded spec twins)"
date: 2026-09-28
slug: reaper-archive-tracked-kb-persistence
branch: feat-one-shot-9127-reaper-archive-persistence
issue: 9127
closes: 9127
type: fix
lane: procedural
domain: engineering
priority: medium
brand_survival_threshold: none
---

# fix: reaper archives tracked KB files via mv — next session's reset --hard resurrects live copies (stranded spec twins)

## Overview

`cleanup_merged_worktrees` in `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh`
archives knowledge-base artifacts — the reaped feature's spec dir (the `spec_dir` move inside the
reap loop) and its brainstorm/plan files (`archive_kb_files`) — with plain `mv`. On a checkout
where those artifacts are **tracked** (a non-bare clone parked on `main`, e.g. the Concierge
agent workspace of ADR-099 or an operator's plain clone), each reap leaves unstaged deletions
plus untracked `archive/` copies. The same function's SOLEUR-GUARD-MAINRESET block then reads
that state as "stale debris" and runs `git reset --hard HEAD` — which restores the moved tracked
files to their live paths while the untracked `archive/` copies persist. Result: the feature's
spec lives at both `specs/feat-<x>/` and `specs/archive/<ts>-feat-<x>/` forever, and every
subsequent reap re-fires the same cycle for new merged features.

Three live spec dirs are stranded on `origin/main` today (verified): `feat-devin-upstream-asks-posture`,
`feat-one-shot-7946-7947-sentry-org-token-and-snapshot-redaction`, `feat-pluggable-web-agent-engines`
— each with an `specs/archive/` twin. The twins are **complementary halves, not copies**: sessions
kept writing to the resurrected live path after the reap-time snapshot was taken, so live-only files
(`tasks.md`, `decision-challenges.md`, `phase-0-measurement.md`, `migration-checklist.md`,
`upstream-asks.md`) exist on the live side. `diff -rq` confirms **zero same-name content conflicts** —
dedup is a union merge, never a blind delete.

## Problem Statement / Motivation

The defect class is that **reaper archive writes have no persistence owner**. Plain `mv` produces a
worktree mutation that nothing commits: direct commits to `main` are hook- and constitution-prohibited,
so on a `main` checkout the move can never reach history; the next `reset --hard` reverts the tracked
half while the untracked archive copy survives — an asymmetric revert that manufactures a twin. The
existing test suite cannot see the class because its fixtures are untracked files, where `mv` is
tracking-agnostic (#9127's own diagnosis, verified independently in this plan's Research Insights).

The issue names three candidate approaches and requires one be chosen; it also requires `git rm -r`
of the three live stranded dirs. This plan selects **option (c)** — `git mv` plus stage+commit via
the existing session-start commit path — as interpreted against the repo's actual commit machinery,
with the rejections of (a) and (b) recorded below.

## Proposed Solution

### Decision: option (c) — `git mv` + stage+commit via the existing commit path

The repo's only sanctioned route for a reap-produced change to reach `main` is a **commit on a
non-`main` branch that rides the normal PR flow**. That path already exists: the script itself
commits `chore: initialize $branch` inside feature worktrees (`worktree-manager.sh`, `create_draft_pr`),
and session commits on a feature branch routinely carry whatever the index holds. Option (c) means:

1. **Where a commit is legal** (a checkout on a feature branch — the worktree case, or any
   non-`main`/`master`, non-detached branch): the reaper performs `git mv` (which stages the
   rename) and then, once per reaped branch, a **pathspec-scoped `git commit`** recording *only*
   that branch's archive-move paths (spec dir + brainstorm + plan files batched into one
   `chore(archive-kb)` commit) — never the session's other staged work. On commit failure the
   staged payload is left and a `SOLEUR_REAP_ARCHIVE_STAGED` marker is emitted, so the session's
   own commits still carry it.
2. **Where no commit may land** (checkout on `main`/`master`, detached `HEAD`, or the bare root —
   the defect surface): the tracked artifacts are **not moved at all**. The reaper emits
   `SOLEUR_REAP_ARCHIVE_DEFERRED slug=<slug> reason=<main-checkout|detached|bare>` and leaves the
   live files in place. No worktree mutation is produced, so there is nothing for `reset --hard`
   to asymmetrically revert — the defect is removed at the producer, not patched downstream.
   Archival for that feature is deferred to the next reap that runs in a committable context
   (a worktree session), which re-derives the same move from the still-live paths. This is
   ADR-195's report-not-reap doctrine applied to a persistence boundary: when the environment
   cannot carry the write, do not make the write.
3. **Untracked artifacts** (bare-root stale mirrors, never-committed scratch): plain `mv`,
   unchanged — no resurrection mechanism applies to untracked paths, and the existing no-clobber
   guard (`[[ -e "$archive_path" ]]`) stays.

The single classification probe is "is this artifact tracked in HEAD" — `git ls-files
--error-unmatch` on a worktree checkout, with `git ls-tree HEAD` as the bare-repo equivalent.
All three archive sites (spec-dir block + both `archive_kb_files` call sites) route through one
new helper so the rule has one chokepoint.

### Why not (a) — a sanctioned auto-commit on `main`

- **Push cannot reach `main`.** The `CI Required` and `CLA Required` rulesets apply
  `required_status_checks` to `~DEFAULT_BRANCH` — a pushed commit has no checks and is rejected;
  the repo's merge route is PR-only in practice (verified against `gh api repos/jikig-ai/soleur/rulesets`).
- **A never-pushed local commit breaks the checkout.** Local `main` = `origin/main` + the reap
  commit diverges the moment origin advances; `git pull --ff-only origin main` (the same-run tail
  of this very function) then fails permanently, leaving local `main` stale — a worse defect than
  the one being fixed.
- **Policy.** "Never allow agents to work directly on the default branch" is constitutional;
  a sanctioned carve-out inside the script would be a policy exception requiring an ADR and a
  hook/CLA story — machinery weight wholly disproportionate to a janitorial move.

### Why not (b) — dirty-check classifies reap-produced dirt as non-stale

- **It never persists.** Skipping the reset keeps the uncommitted deletions in the worktree, but
  nothing ever lands the move in history: `git status` stays permanently dirty, the live dirs
  remain *tracked* on `origin/main` for every other checkout (fresh clones, `sync_bare_files`
  mirrors, other machines still see live+archive), and any future unrelated `reset --hard`,
  `stash`, or checkout silently resurrects the twins again.
- **It degrades the reset's retained purpose.** Once reap-dirt is legitimized as a standing dirty
  class, partitioning it from real debris requires per-path surgery the dirty-check does not have;
  mixed reap+debris states either skip both (debris persists) or reset both (resurrection returns).
- It is a mitigation of the symptom on one checkout, not a fix for the named defect class —
  "no persistence owner" remains true under it.

### Why (c) survives review

- `git mv` makes the move a **staged index rename** (legible to `git status`/`git diff --cached`,
  history-following) instead of an invisible unlink+create.
- The commit rides an **existing, sanctioned path** — the feature branch's own commit→PR→merge
  flow — so no new write authority is created.
- On the one surface where no legal path exists (`main`), the move is deferred with a durable
  marker instead of being produced and destroyed — the sentinel makes the deferral observable,
  and the follow-through probe (`scripts/followthroughs/reaper-archive-stranded-spec-9113.sh`)
  already counts the residual twin population as the re-eval trigger.

### Dedup of the three stranded spec dirs (this PR)

For each pair, union-merge live-only files into the archive twin via `git mv`, then `git rm -r`
the live dir:

| Live dir | Archive twin | Live-only files to merge |
|---|---|---|
| `specs/feat-devin-upstream-asks-posture` | `specs/archive/20260917-155554-…` | `tasks.md`, `upstream-asks.md` |
| `specs/feat-one-shot-7946-7947-sentry-org-token-and-snapshot-redaction` | `specs/archive/20260909-173031-…` | `decision-challenges.md`, `phase-0-measurement.md` |
| `specs/feat-pluggable-web-agent-engines` | `specs/archive/20260915-173141-…` | `migration-checklist.md` |

`diff -rq` verified zero same-name conflicts, so the merge is deterministic. `decision-challenges.md`
is archived with its spec — ADR-084's live-path requirement bound only until that feature's `ship`
Phase 6, which already ran (the feature merged 2026-09). Verify post-merge: no live∩archive name
intersection remains; `git ls-files` shows each spec only under `archive/`; the follow-through
probe's twin count drops to 0 and the tracker closes on the next sweep.

## Technical Considerations

- **`archive_kb_files` is tracking-agnostic today** — its `mv` succeeds identically on tracked and
  untracked files, which is why the fixture suite (untracked files only) cannot see the class.
  The new tests must use **tracked** fixtures (committed to the fixture repo's `main`) or they
  reproduce the blind spot they are meant to close.
- **The commit must be pathspec-scoped.** `git commit` without a pathspec sweeps the whole index;
  inside a session's worktree that would commit the session's unrelated staged work. The
  scoped form commits only the rename's deletion+addition paths. A test pins that a pre-staged
  unrelated file is left uncommitted.
- **Author identity.** The chore commit reuses `ensure_worktree_identity` (the same helper the
  `chore: initialize` path relies on; bot-shape discrimination per ADR-099's inverted-authority
  rule) rather than inventing identity.
- **Lefthook runs.** The scoped commit is a real `git commit` and fires `lefthook` (markdown-lint
  needs a pin-verified binary). Hook failure → commit fails → the staged fallback
  (`SOLEUR_REAP_ARCHIVE_STAGED`) covers it; do **not** `LEFTHOOK=0` — that is a detected bypass
  (`detect_bypass` in `.claude/hooks/lib/incidents.sh`).
- **ADR-174 interaction.** Spec-dir archival is already superseded in part: INDEX.md exclusion is
  the de-indexing mechanism for `project/specs/` (#7399, status *Adopting*), and #7400 tracks
  retiring `archive-kb.sh`'s spec/plan discovery paths. This fix does **not** extend the archival
  convention's life — it makes the reaper's remaining archive writes safe while #7400 decides their
  retirement. Plans and brainstorms still depend on archive moves for de-indexing, so the
  persistence fix is required regardless of the spec-dir direction.
- **Ordering inside `cleanup_merged_worktrees`.** The branch/committability probe is computed once
  before the reap loop (not per artifact); the MAINRESET block is unchanged — under the new rule it
  never sees reap-produced dirt because none is produced.
- **`set -euo pipefail` discipline** (constitution): `git ls-files --error-unmatch` exits non-zero
  for untracked — classify via `if ! …; then`, never bare; `git mv` for an untracked source fails
  with "not under version control" and must fall back to `mv` without aborting the reap.
- **No new `ssh`, cron, or infra surface** — a local git-behavior fix inside an existing script.

## User-Brand Impact

- **If this lands broken, the user experiences:** an operator/agent sees a merged feature's spec
  dir silently live *and* archived (INDEX pollution, duplicated discovery rows) or, in the worse
  arm, a reap commit sweeps unrelated staged work onto a feature branch.
- **If this leaks, the user's [data / workflow / money] is exposed via:** nothing — the artifact
  surface is the operator's own KB markdown; no user data, credentials, or egress.
- **Brand-survival threshold:** `none`
- `threshold: none, reason: internal dev-tooling change confined to local git operations on the
  operator's own repository; no user-data, auth, secret, or production surface is touched.`

## Observability

```yaml
liveness_signal:
  what: "SOLEUR_REAP_ARCHIVE_COMMITTED / SOLEUR_REAP_ARCHIVE_DEFERRED / SOLEUR_REAP_ARCHIVE_STAGED markers emitted on stdout per reap that archives tracked artifacts; twin-count probe scripts/followthroughs/reaper-archive-stranded-spec-9113.sh as the population-level re-eval counter"
  cadence: "per cleanup-merged run (session start / post-merge); probe via scheduled-followthrough-sweeper"
  alert_target: "agent transcript + follow-through issue #9127 re-eval trigger"
  configured_in: "plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh (new emits); scripts/followthroughs/reaper-archive-stranded-spec-9113.sh (existing)"

error_reporting:
  destination: "stdout markers (SOLEUR_* convention — stderr is invisible under claude --bg) + headless_or_stderr warn lines for failures"
  fail_loud: "SOLEUR_REAP_ARCHIVE_STAGED when the scoped commit fails; the archive move is then legible in `git status` as a staged rename"

failure_modes:
  - mode: "deferred-forever: every reap on a never-committable checkout emits DEFERRED and the spec stays live"
    detection: "DEFERRED marker repeats across session-start transcripts; probe twin count stays >0 when an archive twin already exists"
    alert_route: "follow-through probe re-eval trigger on issue #9127"
  - mode: "scoped commit fails (lefthook, identity, mid-index state)"
    detection: "SOLEUR_REAP_ARCHIVE_STAGED emitted; staged rename visible in git status"
    alert_route: "session's own commit flow carries the staged rename"
  - mode: "tracked-check regression (tracked file mv'd on main again)"
    detection: "new test suite fixture: tracked spec dir on main + reap + reset --hard = twin → RED"
    alert_route: "CI via plugins/soleur/skills/git-worktree/test/reap-archive-persistence.test.sh"

logs:
  where: "session transcript (stdout markers) + headless_or_stderr diagnostics"
  retention: "session-scoped; markers are greppable in transcripts and the probe is durable"

discoverability_test:
  command: "grep -n 'SOLEUR_REAP_ARCHIVE_DEFERRED' plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh"
  expected_output: "SOLEUR_REAP_ARCHIVE_DEFERRED"
```

## Architecture Decision (ADR/C4)

Choosing "who owns persistence of reap-produced archive writes" is a cross-cutting invariant —
every future consumer of `cleanup_merged_worktrees` must honor that tracked artifacts move only
where a commit path exists. The test "would a competent engineer reading only the existing ADRs
be misled?" answers yes: ADR-195/ADR-250 cover reclamation *ownership* for processes/scratch, not
KB-artifact persistence across checkout classes.

- **ADR:** create provisional **ADR-256** — "Reaper archive writes persist via the checkout's commit
  path; deferred on non-committable checkouts" (decision + the (a)/(b) rejected alternatives with
  the ruleset and divergence evidence above). Ordinal is provisional — `soleur:ship`'s ADR-Ordinal
  Collision Gate re-verifies against `origin/main`; on renumber, sweep `grep -rn 'ADR-256'
  knowledge-base/project/{plans,specs}/feat-one-shot-9127-reaper-archive-persistence/` plus this
  plan's AC in the same edit.
- **C4 views:** **no C4 impact.** Enumerated per the completeness mandate against
  `model.c4`/`views.c4`/`spec.c4`: (a) external human actors — none new (the reaper runs inside
  `platform.plugin` machinery dispatched at session start; the `devin`/`founder` actors already
  exist); (b) external systems/vendors — none (pure local git operations; `gh` is not invoked by
  the changed path); (c) containers/data stores — none new (no store added; `workspacesVolume`
  and git-data topology unchanged); (d) actor↔surface relationships — unchanged. The
  `devin -> platform.plugin` edge already names session-start `cleanup-merged` dispatch; this
  change alters its internal persistence semantics, not the edge.
- **Sequencing:** the ADR is authored in this PR describing the landed behavior (status
  `accepted`); no deferred follow-up.

## Guard Contract

### Guard 1 — reap archive persistence ownership

**Property.** `cleanup_merged_worktrees` never leaves a tracked KB artifact in an unpersisted
moved state: every tracked archive move is committed on a legal branch in the same reap run, or
the move is not made at all (DEFERRED).

**Assembly.** Three archive sites — the spec-dir block and both `archive_kb_files` call sites
(brainstorms, plans) — channeled through the single new persistence helper (the chokepoint), fed
by the once-per-run committability probe (`IS_BARE`, `current_branch`) and the per-artifact
tracked probe (`ls-files --error-unmatch` / `ls-tree HEAD`). A fourth site added later without the
helper is itself the defect class.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Revert the committable arm to plain `mv` on a feature branch | RED — the chore-commit assertion finds no `chore(archive-kb)` commit |
| 2 | Treat `main` as committable (drop the branch check) | RED — main-checkout fixture expects `SOLEUR_REAP_ARCHIVE_DEFERRED` and no commit attempt |
| 3 | Drop the tracked probe (mv everything blindly) | RED — no-resurrection regression: tracked fixture on main + reap + `reset --hard` produces a twin |
| 4 | Helper always emits DEFERRED without consulting the probes (vacuous dispatch) | RED — committable-arm test asserts a commit exists |
| 5 | Add a fourth archive site that bypasses the helper | RED — census assert: every `mv`/`git mv` of KB artifacts routes through the helper |
| 6 | Fixture precondition neutered (spec dir not committed — "tracked" fixture is really untracked) | RED — suite asserts the fixture file is tracked before the reap runs, so a vacuous fixture fails loudly |
| 7 | Must-PASS: untracked fixture spec dir | PASS — plain `mv` arm is a contract-permitted variant |

## Files to Edit

- `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh` — committability probe,
  persistence helper, `git mv` arm, DEFERRED/STAGED/COMMITTED sentinels.
- `plugins/soleur/skills/git-worktree/SKILL.md` — document the two new sentinels and the
  commit-path-gated persistence rule in the reaper sections (body only; `description:` untouched —
  Phase 1.8 budget check not applicable).
- `scripts/lib/test-affected-paths.sh` — declared `AFFECTED_…_REAP_ARCHIVE_PERSISTENCE_TEST_SH_PATHS`
  array (same shape as the five sibling git-worktree entries; subject unreachable by derived edges).
- `scripts/suite-shard-legs.tsv` — row for the new suite (or regenerate via
  `scripts/regenerate-shard-manifest.py`; untabled labels hash-fallback but a declared row keeps
  shard balance deterministic).
- `knowledge-base/project/specs/archive/20260917-155554-feat-devin-upstream-asks-posture/` —
  `git mv` in `tasks.md`, `upstream-asks.md`.
- `knowledge-base/project/specs/archive/20260909-173031-feat-one-shot-7946-7947-sentry-org-token-and-snapshot-redaction/` —
  `git mv` in `decision-challenges.md`, `phase-0-measurement.md`.
- `knowledge-base/project/specs/archive/20260915-173141-feat-pluggable-web-agent-engines/` —
  `git mv` in `migration-checklist.md`.
- `knowledge-base/project/specs/feat-devin-upstream-asks-posture/` — `git rm -r` after merge.
- `knowledge-base/project/specs/feat-one-shot-7946-7947-sentry-org-token-and-snapshot-redaction/` —
  `git rm -r` after merge.
- `knowledge-base/project/specs/feat-pluggable-web-agent-engines/` — `git rm -r` after merge.

## Files to Create

- `plugins/soleur/skills/git-worktree/test/reap-archive-persistence.test.sh` — fixture suite per
  the established `mktemp`-repo + `cdx` containment pattern (see `lease-protects-active.test.sh`).
- `knowledge-base/engineering/architecture/decisions/ADR-256-reaper-archive-persistence-commit-path.md`
  — provisional ordinal per the ADR section above.

## Acceptance Criteria

- [ ] **AC1** — On a feature-branch checkout, a reap that archives a *tracked* spec dir / plan /
  brainstorm produces a `chore(archive-kb)` commit on the current branch whose touched-path set
  equals exactly the archive-move set (verified: `git show --name-only --format= <sha>` lists the
  moved paths and nothing else; `git show --name-status` shows `R100`-class renames), and emits
  `SOLEUR_REAP_ARCHIVE_COMMITTED`.
- [ ] **AC2** — On a `main`/`master` or detached checkout, a reap moves **no** tracked artifact:
  live paths remain on disk *and* in the index, no archive copy is created, and
  `SOLEUR_REAP_ARCHIVE_DEFERRED … reason=…` is emitted per skipped slug.
- [ ] **AC3** — Regression: on a `main` checkout with a tracked spec dir, `cleanup-merged` followed
  by `git reset --hard HEAD` leaves **no** live+archive twin (both the same-run reset and a
  second-run reset are covered).
- [ ] **AC4** — Untracked artifacts still archive via plain `mv`, and the no-clobber
  (`[[ -e archive_path ]]`) behavior is unchanged.
- [ ] **AC5** — The scoped commit never sweeps unrelated staged work: a pre-staged unrelated file
  is still staged-and-uncommitted after the reap.
- [ ] **AC6** — The three stranded spec dirs are deduped: live-only files moved into each archive
  twin, live dirs `git rm -r`'d, `comm -12` of live vs stripped archive names for those three
  slugs returns empty, and `git ls-files` shows the spec content only under `specs/archive/`.
- [ ] **AC7** — New suite `reap-archive-persistence.test.sh` registered: auto-discovered by the
  `plugins/soleur/skills/*/test/*.test.sh` glob, a declared-edge array in
  `scripts/lib/test-affected-paths.sh`, and a `scripts/suite-shard-legs.tsv` row.
- [ ] **AC8** — Provisional `ADR-256-*.md` created; plan AC naming the ordinal stays consistent if
  `soleur:ship` renumbers (sweep per the ADR section).
- [ ] **AC9** — `git-worktree/SKILL.md` documents the persistence rule and both sentinels;
  `description:` frontmatter untouched.

## Test Scenarios

- **Given** a fixture clone on `main` with a *tracked* spec dir for a merged branch, **when**
  `cleanup-merged` runs, **then** no `mv` occurs, `SOLEUR_REAP_ARCHIVE_DEFERRED` is emitted with
  `reason=main-checkout`, the live dir remains tracked and on disk, and the tree is clean.
- **Given** the same fixture, **when** a subsequent `git reset --hard HEAD` runs (same-run and
  next-run), **then** no live+archive twin exists afterward.
- **Given** a fixture clone on a feature branch with a tracked spec dir for a merged branch,
  **when** `cleanup-merged` runs, **then** the rename is committed on the feature branch in a
  `chore(archive-kb)` commit, `git status` is clean of the move, and a pre-staged unrelated file
  is untouched.
- **Given** a feature-branch checkout where `git commit` fails (lefthook absent/identity missing),
  **when** the reap archives, **then** the moves remain staged and `SOLEUR_REAP_ARCHIVE_STAGED`
  is emitted.
- **Given** an untracked spec dir on any checkout, **when** the reap runs, **then** plain `mv`
  archives it exactly as today.
- **Given** a bare repo whose HEAD tracks the spec path (stale on-disk mirror), **when** the reap
  runs, **then** the mirror is deferred (not churned into a second archive copy `sync_bare_files`
  would only re-materialize).
- **Given** the three stranded pairs, **when** the dedup lands, **then** `diff -r` of each merged
  archive twin covers the union of both sides and no live dir remains.
- **Verification commands:**
  - `bash plugins/soleur/skills/git-worktree/test/reap-archive-persistence.test.sh` → `0 failed`
  - `bash scripts/followthroughs/reaper-archive-stranded-spec-9113.sh` → exits 0 with
    `twin count changed` once the dedup is on the probed tree
  - `comm -12 <(ls knowledge-base/project/specs | grep ^feat | sort) <(ls knowledge-base/project/specs/archive | sed -E 's/^[0-9]{8}-[0-9]{6}-//; s/^[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{6}-//' | sort)` → excludes the three deduped slugs

## Success Metrics

- Zero live+archive spec twins reachable by any checkout class after this PR merges (the probe's
  baseline of 3 transitions to 0 and the tracker closes).
- No resurrection reachable in a fresh fixture replay of the issue's scenario.
- The reaper emits a greppable marker for every tracked-archive decision (committed / staged /
  deferred) — the "no persistence owner" class becomes observable at the decision point.

## Dependencies & Risks

- **Deferred archival can wait indefinitely** on a checkout that never runs worktree sessions —
  accepted: the spec stays live (the pre-defect state), the marker and probe keep it visible; an
  auto chore-branch+PR path is recorded as a rejected heavyweight alternative (Alternatives).
- **Scoped-commit sweeps nothing extra** — pinned by AC5 test; the pathspec form is the only
  commit shape used.
- **Lefthook markdown-lint needs a pin-verified binary** — commit failure degrades to STAGED,
  not to a reap abort (constitution `set -e` discipline: the commit runs inside a captured-error
  `if` arm).
- **`git ls-tree HEAD` on unborn-HEAD or missing HEAD** — guarded (`|| true` + empty check), same
  pattern as the existing unborn-HEAD handling in MAINRESET.
- **Slash-bearing branch names** — the committability probe keys on `rev-parse --abbrev-ref HEAD`,
  not the worktree dir name; consistent with the `#7408` lease-key fix.
- **#8496** (`[gone]`-branch merge-evidence gap) touches `cleanup_merged_worktrees` but a different
  region — acknowledged, not folded in (see Open Code-Review Overlap).

## Alternative Approaches Considered

| Option | Verdict | Why |
|---|---|---|
| (a) Direct auto-commit on `main` | Rejected | Push rejected by `required_status_checks` rulesets; local-only commit diverges and permanently breaks `pull --ff-only`; unconstitutional commit-on-main carve-out |
| (b) Dirty-check classifies reap-dirt as non-stale | Rejected | Mitigation, not persistence — permanent uncommitted deletions, tracking-level twins remain on `origin/main`, dirty-check partition problem; the "no persistence owner" class survives |
| (c) `git mv` + stage+commit via existing session-start commit path | **Selected** | Persists through the sanctioned feature-branch commit→PR flow; defers-with-marker where no legal path exists; smallest correct mechanism |
| Auto chore-branch+PR inside the reaper on `main` | Deferred (not built) | Functionally complete but heavyweight: branch lifecycle + push + `gh pr create` + auto-merge + CLA/CI dependencies inside a session-start path; revisit only if the DEFERRED marker proves archival never lands in practice |
| Retire reaper KB archival entirely now | Out of scope | Plans/brainstorms still need archive moves for INDEX de-indexing (ADR-174 scoped exclusion to `project/specs/` only); #7400 owns the retirement question |

## Research Insights

**Premise validation (Phase 0.6).** Every cited artifact verified against `origin/main`:

- PR #9113 — MERGED 2026-09-28 (`fix(git-worktree): align reap archive stamps to compact YYYYMMDD-HHMMSS`); the scope-out that produced #9127 is live.
- `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh` — `archive_kb_files` at the
  `archive_kb_files() {` definition (plain `mv` confirmed), spec-dir `mv` inside
  `cleanup_merged_worktrees`, SOLEUR-GUARD-MAINRESET block present (the dirty-check + `reset --hard HEAD`
  on `main`/`master` is as described; it fires in the **same run's tail**, not only "next session").
- `scripts/followthroughs/reaper-archive-stranded-spec-9113.sh` — exists; counts live∩archive
  name intersection at the probed repo root; baseline 3; re-eval on count change.
- The three stranded live dirs + archive twins — all confirmed on `origin/main` via `git ls-tree`.
  **New finding:** twins are complementary halves (zero same-name conflicts) — dedup must union-merge,
  not blind-delete.
- Mechanism-vs-ADR check — grepped `knowledge-base/engineering/architecture/decisions/` for
  auto-commit / reset --hard / session-start / main-checkout mechanisms: ADR-099 (non-bare
  Concierge workspace — the defect surface), ADR-174 (INDEX exclusion supersedes spec archival —
  adopting), ADR-250 (ownership-keyed reclamation — composes, different substrate), ADR-195
  (report-not-reap for unattributable orphans — doctrine this fix borrows for the no-commit-path
  arm). No ADR rejects the chosen mechanism; ADR-054 (bot/cron PR write path) and the
  `chore: initialize` script-internal commit are supporting precedent.

**Property List (Phase 0.6b).**

- P1: a reaper archive move of a *tracked* KB artifact lands in git history in the same reap run,
  or the move is not made — never an uncommittable mutation that a later reset reverts asymmetrically.
- P2: no commit lands on `main` directly (constitution + `required_status_checks` rulesets make
  direct pushes unreachable in practice).
- P3: the three verified stranded live spec dirs are deduped — union-merge live-only files into
  the archive twins, `git rm -r` live, zero same-name conflicts already verified.
- P4: the fix is test-visible — new suite uses *tracked* fixtures, closing the untracked-fixture
  blind spot the issue names.
- P5: the dirty-check's retained purpose (#8400) is untouched — it never sees reap dirt because
  none is produced.

**Cut List.**

- Option (a) → buys P1 but violates P2 (push rejected; divergence breaks ff-pull) — cut.
- Option (b) → does not buy P1 (no persistence; permanent dirty state; degrades P5) — cut.
- Auto chore-branch+PR machinery → buys P1 on `main` at ~an order more machinery than the
  sentinel+worktree-carry path needs; cut now, recorded as the escape hatch if DEFERRED proves
  archival never lands.
- Dirty-check reclassification entirely → unnecessary once reap dirt is never produced — cut.

**Relevant file paths.**

- `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh` — `archive_kb_files()` (plain `mv`),
  spec-dir archive block + both `archive_kb_files` call sites inside `cleanup_merged_worktrees`,
  SOLEUR-GUARD-MAINRESET block (dirty-check + `reset --hard HEAD`), `create_draft_pr` +
  `git commit --allow-empty -m "chore: initialize $branch"` (script-internal commit precedent),
  `sync_bare_files` (bare-root mirrors materialize HEAD — the same twin class by a different
  mechanism: `checkout-index` resurrects moved tracked files on the bare root's disk view),
  `ensure_worktree_identity`, `_sanitize_marker_field`, `headless_or_stderr`.
- `plugins/soleur/skills/archive-kb/scripts/archive-kb.sh` — `git add` + `git mv` precedent
  (stages the rename on a feature branch; commits ride the session's flow — the model this fix
  imports into the reaper).
- `scripts/followthroughs/reaper-archive-stranded-spec-9113.sh` — the re-eval probe (unchanged).
- `plugins/soleur/scripts/precommit-guard.sh` + `.claude/hooks/guardrails.sh` — the
  commit-on-main prohibition (agent-side; script-internal commits are the `chore: initialize`
  precedent — on non-main branches only).
- `scripts/lib/test-affected-paths.sh`, `scripts/suite-shard-legs.tsv` — new-suite registration points.
- `plugins/soleur/skills/git-worktree/test/*.test.sh` — the five sibling suites' fixture pattern
  (`mktemp` repo + `cdx` containment + GIT_DIR tripwire).

**Institutional learnings applied.**

- `2026-09-24-a-reaper-whose-trigger-isnt-installed-is-a-no-op.md` — a reaper whose trigger is
  not installed is a no-op; the DEFERRED marker keeps the no-commit-path arm observable rather
  than silently inert.
- `2026-08-20-every-guard-i-fixed-was-narrower-than-the-claim-it-carried.md` — fixture sandboxing
  and `cdx` containment discipline for the new suite.
- `2026-04-21-concurrent-cleanup-merged-wipes-active-worktree.md` (seed of
  `lease-protects-active.test.sh`) — the reaper's blast radius demands fixture tests with real
  git state, not mocks.
- `2026-08-10` kb-archival-convention brainstorm (feat-kb-archival-convention) — archival's real
  benefit is INDEX.md row removal; the spec-dir side is superseded by ADR-174's index exclusion.
- #8400 (in-code) — MAINRESET's premise reordering; kept untouched.

**External/community.** No community stack/agent overlaps (internal bash/git machinery; the
functional sibling is the repo's own `archive-kb.sh`). Community-discovery stack scan: no
signature files matched (no flutter/rust/elixir/go/swift/kotlin/php signatures relevant to this
change). Functional-overlap check ran inline (no Task tool on this harness): nothing to install.

**Conventions.** SOLEUR_* markers on stdout (stderr invisible under `claude --bg`);
`_sanitize_marker_field` for contributor-derived values; `set -euo pipefail` failure capture via
`if …; then rc=0; else rc=$?; fi`; comments use grep-stable symbol anchors, never line numbers.

## Research Reconciliation — Spec vs. Codebase

| Issue claim | Codebase reality (verified) | Plan response |
|---|---|---|
| "`mv` at worktree-manager.sh:~3357 / ~2493" | Correct functions; line numbers drifted — `archive_kb_files` definition ~2471, spec-dir block ~3343–3369, MAINRESET ~3462–3519 | Anchor all references on symbol names (`archive_kb_files`, `SOLEUR-GUARD-MAINRESET`, `cleanup_merged_worktrees`), never line numbers |
| "reset --hard at the *next* session-start" | The reset also fires in the *same run's* tail (`if cleaned>0` → non-bare branch) | Fix at the producer (no reap dirt), not at the reset timing |
| "3 spec dirs exist live AND archived" | Confirmed — and they have **diverged**: live-only files exist on the live side (sessions kept writing post-resurrection) | Dedup is union-merge then `git rm -r`, not blind `git rm -r` |
| "`git mv` alone is NOT the fix" | Confirmed — `reset --hard` discards staged state identically | `git mv` is paired with a same-run scoped commit on committable checkouts and a no-move defer on main |
| "(c) the *existing* session-start commit path" | No session-start commit-on-main exists; the existing path is the feature-branch commit flow (`chore: initialize` precedent + session commits carrying the index) | (c) implemented as: commit on non-main branches via the script's own path; defer on main |
| "direct commits to main are hook-prohibited" | True for agent-issued commands (guardrails.sh + precommit-guard.sh); and even a script-internal commit cannot *reach* main — `required_status_checks` rulesets gate the branch, and an unpushed local commit breaks `pull --ff-only` | (a) rejected on both policy and mechanics |

## Open Code-Review Overlap

- **#9127** — this issue itself (the plan's subject).
- **#8496** `review: cleanup-merged never gh-queries [gone] branches that have no worktree` —
  **Acknowledge.** Touches `cleanup_merged_worktrees` but a different region (merge-evidence
  querying vs. archive persistence); orthogonal concern, not folded in.
- `## Files to Edit` paths (`worktree-manager.sh`, `SKILL.md`, test/tsv registration files,
  spec dirs): no other open code-review issue bodies reference them.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — internal repo-tooling change confined to a maintenance
script, its tests, and KB bookkeeping. No UI-surface files in either file list, so the mechanical
Product/UX override does not fire; tier N/A.

## References & Research

- Issue: #9127 (labels: `code-review`, `follow-through`, `deferred-scope-out`, `meta/machinery`)
- Precedent PR: #9087 (`chore(archive-kb): archive the #9035 spec dir` — dedicated PR landing an
  uncommitted reaper move; proves the dedup shape this PR repeats)
- Source PR: #9113 (merged 2026-09-28 — the scope-out that produced this issue)
- ADRs: ADR-174 (index exclusion supersedes per-feature archival — adopting), ADR-195
  (report-not-reap), ADR-250 (ownership-keyed reclamation), ADR-099 (git surface topology —
  non-bare Concierge), ADR-054 (safe-commit bot write path)
- Sibling code: `plugins/soleur/skills/archive-kb/scripts/archive-kb.sh` (`git add` + `git mv`
  precedent), `plugins/soleur/scripts/precommit-guard.sh`, `.claude/hooks/guardrails.sh`
  (`guardrails:block-commit-on-main`)
- Probe: `scripts/followthroughs/reaper-archive-stranded-spec-9113.sh`
- Follow-through directive on #9127: `script=scripts/followthroughs/reaper-archive-stranded-spec-9113.sh
  earliest=2026-09-28T00:00:00Z secrets=GH_TOKEN` — the probe's re-eval trigger (twin-count
  transition) is satisfied by the dedup landing.

## Sharp Edges

- The dedup is **union-merge, not delete**: live-only files exist on the live side of all three
  pairs (sessions kept writing after resurrection). Blind `git rm -r` loses `tasks.md`,
  `decision-challenges.md`, `phase-0-measurement.md`, `migration-checklist.md`, `upstream-asks.md`.
- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder
  text, or omits the threshold will fail `deepen-plan` Phase 4.6 — filled above.
- The ADR ordinal (256) is provisional; a sibling PR can claim it during the pipeline — the
  `adr-ordinals` required check and `soleur:ship`'s gate are the catch, and a renumber must sweep
  this plan + AC8 + tasks.md in the same edit.
- `git mv` inside the reaper must handle "not under version control" per file — a mixed
  tracked/untracked batch cannot use one code path; classify per artifact.
- The commit is pathspec-scoped precisely so it cannot sweep the session's unrelated staged work —
  AC5 is the pin, not a nicety.
- New `.test.sh` under `plugins/soleur/skills/*/test/` is auto-discovered but still needs the
  `test-affected-paths.sh` declared-edge array and a `suite-shard-legs.tsv` row, or the
  affected-paths runner cannot reach it and shard balance hash-falls.
