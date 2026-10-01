---
title: "chore(merge): stop the pre-merge sync from invalidating a green SHA (merge queue or disjoint-delta policy)"
type: chore
date: 2026-10-01
slug: chore-premerge-sync-stale-sha
branch: feat-one-shot-9401-premerge-sync-stale-sha
issue: 9401
closes: 9401
lane: cross-domain
---

# chore(merge): stop the pre-merge sync from invalidating a green SHA

## Overview

`.claude/hooks/pre-merge-rebase.sh` merges `origin/main` into the PR branch and
pushes on every `gh pr merge` invocation it can resolve to the session's own
checkout, whenever `merge-base(HEAD, origin/main)` is behind `origin/main`.
With `main` landing roughly hourly and one CI cycle costing ~15–25 min
(measured baseline in `## Research Insights`), a green head is stale before
its merge lands: each hook sync mints a new head SHA that
restarts the whole required-check set. Issue #9401 measured four wasted cycles
on PR #9339. The issue's preferred remedy — GitHub's merge queue — is already
adopted-and-reverted on this repo (ADR-032 amendment, PR #5800 deadlocked on
CodeQL `merge_group` status; upstream `codeql-action#1537` verified still OPEN
2026-10-01), so this plan takes the disjoint-delta arm: skip the hook sync when
the incoming base delta shares no file with the PR's diff, extend
`admin-merge-ready.sh`'s was-green carryover to a provably docs-only local
merge, and fix the `-R`/`--repo`/`GH_REPO`/`GH_HOST` invocation forms so the
PR-head resolver still engages when `gh` is scoped to this same repository.

## Research Reconciliation — Spec vs. Codebase

| Spec/issue claim | Codebase reality | Plan response |
|---|---|---|
| "Prefer GitHub's merge queue so CI runs once on the queue's merge result" (#9401) | Merge queue was adopted in #5780/PR #5800, deadlocked `main`, and was reverted 2026-06-30: `infra/github/ruleset-ci-required.tf` header records the revert; ADR-032's amendment records that a blocking required `CodeQL` check and a merge queue are mutually exclusive; `gh api repos/github/codeql-action/issues/1537` returns `open` today. | Merge queue is out of scope — tracked by #4856 (ruleset IaC) gated on #5840 (upstream CodeQL). This plan ships the disjoint-delta policy only. |
| "`gh pr merge -R` from another checkout did not skip it" | Confirmed in code: the resolver sets `MERGE_TARGET_WHY` for ANY `-R`/`--repo`/`GH_REPO`/`GH_HOST` sighting (pre-merge-rebase.sh, the `_merge_args`/`MERGE_TARGET_WHY` chain), which degrades to state L — `PR_HEAD_OID` stays empty so the own-checkout sync-skip (`PR_HEAD_OID != "" && OWN_CHECKOUT != 1`) never fires and the sync runs against whatever branch the session is anchored on. | Normalize the `-R`/`--repo`/`GH_REPO` operand and compare against the session checkout's `origin`; same-repo invocations resolve the PR head normally, foreign repos keep state-L degradation. |
| "let `admin-merge-ready.sh` accept green-on-X plus a disjoint docs-only delta since X" | The script's `--green-sha` carryover already proves a *GitHub-verified* 2-parent merge (`parents[0]==G`, second parent ancestor-or-equal of base) but refuses any locally-created merge (`carryover-unverified`) — including the unsigned merge this hook itself pushes. | Extend carryover with a local-merge arm that substitutes GitHub signature verification with an API-derived clean-merge proof plus a docs-only + PR-file-disjoint bound on the merged delta. |

## Research Insights

### Premise Validation (Phase 0.6)

- `gh issue view 9401` — OPEN, `type/chore`, `priority/p2-medium`, `meta/machinery`, `deferred-scope-out`. Premise intact.
- Cited files exist on this branch (identical to `origin/main` for this fresh worktree): `.claude/hooks/pre-merge-rebase.sh` (580 lines) and `plugins/soleur/scripts/admin-merge-ready.sh` (375 lines).
- `gh pr view 9339` — MERGED 2026-10-01T18:59:18Z, matching the issue's observation source.
- Related issues all confirmed OPEN and left out of scope per the issue context: #4856 (merge-queue ruleset), #5840 (CodeQL `merge_group` blocker), #8683 (`sync-pr-behind.sh` livelock — a *different* sync surface), #8791 (residual cwd-scoped follow-ups in this hook), #9340 (battery-gate follow-ups).
- Mechanism-vs-ADR check: `merge_queue` is in ADR-032's *reverted* set, not merely an unconsidered alternative — re-proposing it would repeat a measured deadlock. Disjoint-delta has no ADR conflict; it refines the enforcement of constitution line "Before creating a PR or merging, merge latest origin/main into the feature branch [hook-enforced: pre-merge-rebase.sh]".

### Property List (Phase 0.6b)

1. A merge of a green, verified head SHA is not invalidated by a hook sync whose incoming base delta shares no file with the PR's diff.
2. `gh pr merge -R owner/repo N` (and `--repo`/`GH_REPO`/`GH_HOST` forms) scoped to this repository resolves the PR head exactly as the flagless form — review-evidence range, own-checkout detection, and the state-P sync-skip all engage.
3. A green certification can carry to a new head when the delta added on top of the green SHA is provably a clean merge of base content that is docs-only and disjoint from the PR's file list.
4. Bounds are preserved: overlapping deltas still sync; foreign-repo `-R` still degrades to state L; `UNTRUSTED-CI`/`DIRTY`/smuggled-edit shapes still refuse at the admin gate.

### Cut List (Phase 0.6b)

- **GitHub merge queue** — property 1's alternative implementation — cut: reverted 2026-06-30 (ADR-032 amendment); blocked upstream by `codeql-action#1537` (OPEN as of today, verified via `gh api`). Owned by #4856+#5840.
- **Shared `.claude/hooks/lib/pr-head.sh` extraction** — cut: #8791 prescribes it "once a second hook needs the PR-head resolver"; this change keeps one consumer.
- **Applying the disjoint-skip to `plugins/soleur/scripts/sync-pr-behind.sh`** — cut: that surface is #8683's contested-design scope-out; the poll-loop sync has different callers and trade-offs. Noted as the natural follow-up.
- **A `SOLEUR_*` env-var force-sync escape hatch** — cut: `gh pr update-branch N` already produces the server-side verified merge without touching the hook; the property ("let me force a sync") is covered by an existing mechanism.

### Measured cost baseline (Phase 0.6c)

The justification is a cost saving, so the baseline is measured, not asserted.
Issue #9401 reports ~25 min/CI cycle and 4 wasted cycles on PR #9339 (~100 min
of CI plus the human/agent wait between them). Re-measured 2026-10-01 against
the three most recent completed `main` CI runs
(`gh run list --branch main --workflow CI --limit 3` → `gh api .../jobs`): the
longest shard `test-scripts` is now 10–18 min (sharded 7-way since #7907; the
34–36 min figure in `settle-then-admin-merge.md` predates that). One avoided
disjoint sync therefore saves roughly one full CI cycle (~15–20 min of wall
time and the full runner-minute cost of the required-check set) per occurrence,
plus breaks the head-churn loop that made #9339 re-verify four times.

### Functional overlap (Phase 1.5b, inline — no Task runtime)

- `admin-merge-ready.sh --green-sha` (PR #8582) is the closest existing mechanism; this plan extends it rather than duplicating it.
- `sync-pr-behind.sh` is the sibling sync surface (three callers: ship Phase 7, merge-pr §5.2, standalone) — deliberately not modified; see #8683.
- `resolve-regenerable-conflicts.sh` is invoked by the same hook's merge-failure path and is unaffected.
- `gh pr update-branch` is the GitHub-side sync path that produces the verified-merge shape `--green-sha` already accepts — it is the prescribed force-sync escape.
- Community discovery: no stack signatures outside the covered set (TypeScript/bash/git/GitHub-CLI); skipped per reference skip-condition.
- External research: skipped — the mechanism is repo-internal machinery with dense local context (hook, gate script, runbook, ADR-032, four learnings); the one external fact (`codeql-action#1537` state) was verified live via `gh api`.

### Institutional learnings applied

- `2026-06-02-auto-merge-livelock-fast-moving-main.md` — the livelock this issue extends; its amplifier list already names this hook ("a pre-merge PreToolUse hook re-synced the branch on each `gh pr merge` attempt").
- `2026-09-19-githubs-merge-ref-runs-your-prs-own-defect-against-it.md` — disjointness is file-level; semantic coupling (main deletes a symbol the PR calls) is the residual risk, caught by the push-to-main CI run rather than prevented pre-merge. The plan discloses this bound.
- `2026-09-24-8611-merge-tail-six-frictions-and-a-stale-reaper.md` and the `settle-then-admin-merge.md` "detached worktree" trap (PR #9048) — the exact friction this plan removes: the workaround exists only because the hook rewrites the head.
- ADR-235 / `resolve-regenerable-conflicts.sh` — the merge-failure path is unchanged; `model.likec4.json` remains the only regenerable committed artifact.

### CLAUDE.md / constitution conventions carried

- constitution: "Before creating a PR or merging, merge latest origin/main into the feature branch — [hook-enforced: pre-merge-rebase.sh]". The disjoint skip is an enforcement refinement; the plan annotates the hook header AND the constitution line so the recorded rule does not silently diverge from behavior.
- Hook error-handling contract (header of the file): fail-open on infrastructure errors, fail-closed on logical errors — the disjointness computation must fail TOWARD syncing (status quo) on any error, never toward skipping.
- `emit_incident`/`headless_or_stderr`/`hook-input.sh` helper reuse; no new incident rule is added (a skip is not a deny).

## Problem Statement / Motivation

`strict_required_status_checks_policy = true` on the CI Required ruleset means a
PR must be up-to-date with `main` to merge. The hook enforces this by merging
`origin/main` and pushing — which mints a new head SHA every time. With `main`
moving ~hourly and CI at ~15–25 min, the sequence *green → sync → new SHA →
CI → stale* repeats until merge (4 cycles on #9339; similar on #8474, #8611,
#7896 per the linked learnings). Two adjacent defects compound it: `-R`-scoped
invocations degrade the PR-head resolver to state L so the sync runs against an
arbitrary checkout and the evidence gate reads the wrong range; and
`admin-merge-ready.sh --green-sha` refuses the unsigned merge commit the hook
itself produces, so even a contentless sync burns a full re-verification.

## Proposed Solution

Three coordinated changes, no merge queue:

1. **Disjoint-delta sync skip (hook).** After the existing
   `MERGE_BASE == REMOTE_MAIN` up-to-date check and before `acquire_lock
   rebase-main`, compute `PR_FILES = diff --name-only MERGE_BASE HEAD` and
   `INCOMING = diff --name-only MERGE_BASE origin/main`. If the sorted-set
   intersection is empty, do NOT merge or push: emit `additionalContext`
   carrying the literal token `delta disjoint` (this exact string is the
   observability/AC anchor) naming both counts, and exit 0 so `gh pr merge`
   proceeds. Any computation failure (diff error, empty `MERGE_BASE`) falls
   through to the existing sync — the failure direction preserves today's
   behavior. Non-admin merges then receive GitHub's own not-up-to-date refusal
   (the agent's next step is `--auto` or the admin-merge flow); `--admin`
   merges land the certified SHA unmodified.
2. **Same-repo `-R` resolution (hook).** In the `MERGE_TARGET_WHY` chain,
   parse the repo operand of `-R <o/r>`, `-R<o/r>` (attached form), `--repo
   <o/r>`, `--repo=<o/r>`, `GH_REPO=<o/r>` and `GH_HOST=<h>`; normalize against the session checkout's
   `origin` remote URL (`owner/repo` extraction from `https://`, `ssh://git@`,
   and `git@host:` forms; `.git` suffix stripped; case-folded). Same-repo →
   strip the flag+operand from `_scan_args` before the bare-number checks so
   the resolver proceeds to state O/P as usual. Different or unresolvable →
   keep today's `MERGE_TARGET_WHY` denial path (state L). An origin whose URL
   is not a GitHub remote (local-path fixture) cannot prove same-repo → stays
   refused, matching today.
3. **Local-merge docs-only carryover (`admin-merge-ready.sh`).** Extend the
   `--green-sha` arm: when `<sha>` fails the verified-merge shape, evaluate a
   local-merge arm before refusing — requires (a) exactly 2 parents with
   `parents[0].sha == <green-sha>`; (b) `compare(parents[1]...<base>)` is
   `ahead|identical` (unchanged); (c) every file in `compare(<green-sha>...
   <sha>)` appears in `compare(merge_base(<green-sha>, parents[1])...
   parents[1])` with a byte-identical `patch` — proving the merge added only
   the base side's content verbatim (patch equality, not path membership: a
   conflict-resolution edit to a file the base delta ALSO touched shares the
   path but yields a different patch; files lacking a `patch` field — too
   large/binary — fail closed as non-docs); (d) every added file matches the
   docs-only classifier
   `^(knowledge-base/|docs/|plugins/soleur/skills/|.*\.md$)` and is absent from
   the PR's own file list (already fetched for `UNTRUSTED-CI`). All four hold →
   grade `<green-sha>`'s contexts with reason token `carryover-local-docs`;
   any failure → not-ready with the existing `carryover-*` reason family.
   The verified-merge arm stays strictly stronger and is evaluated first; the
   new arm needs an explicit opt-in flag (e.g. `--allow-local-merge`) so the
   bare `--green-sha` contract is not silently widened.

### Implementation Phases

#### Phase 1: Hook disjoint-delta skip + tests (RED first)

- New cases in `.claude/hooks/pre-merge-rebase.test.sh`: (T-disjoint) origin/main
  advances on files outside the PR diff → hook exits 0, emits `delta disjoint`,
  HEAD unchanged, no push; (T-overlap) incoming delta touches a PR file → sync
  runs (merge commit + push); (T-failopen) induced diff failure → sync runs.
- Implement the check in `.claude/hooks/pre-merge-rebase.sh` between the
  up-to-date early exit and `acquire_lock rebase-main`; update the header
  comment documenting the new policy.

#### Phase 2: Same-repo `-R` resolution + tests

- New cases: `-R`-same-repo resolves the PR head (resolver reaches state P/O
  rather than L; evidence range is the PR head, not session HEAD) and `-R`
  foreign-repo keeps the state-L behavior. Fixture note: the suites' origins
  are local paths, so same-repo fixtures must set a URL-shaped `origin`
  (`git remote set-url` is offline-safe — the operand comparison uses
  `remote get-url`, not fetch) plus the existing `gh` stub.
- Implement operand extraction + normalization in the `MERGE_TARGET_WHY`
  chain; strip the flag before the bare-number token check.

#### Phase 3: `admin-merge-ready.sh` local-merge carryover + tests

- New cases in `plugins/soleur/scripts/admin-merge-ready.test.sh`: local
  2-parent merge of G + docs-only disjoint delta + `--allow-local-merge` →
  ready with `reason=carryover-local-docs`; code-file delta → not-ready;
  smuggled file (not in base delta) → not-ready; wrong first parent →
  not-ready; flag absent → unchanged `carryover-unverified` refusal.
- Implement the arm inside `check_once`'s `GREEN_SHA` block; document the new
  arm in the script header and `usage()`; mirror-check
  `plugins/soleur/test/admin-merge-ready-wiring.test.sh` for flag/usage pins.

#### Phase 4: Docs + ADR

- Update `settle-then-admin-merge.md` (the detached-worktree bullet now only
  applies to overlapping deltas; `--green-sha` section gains the local-merge
  arm), `ship/SKILL.md` Phase 7 paragraph and `merge-pr/SKILL.md` §5.2 mirror
  (the "was-green carryover" sentences), and the constitution's
  `[hook-enforced: pre-merge-rebase.sh]` annotation.
- Author the ADR per `## Architecture Decision (ADR/C4)` below.

#### Phase 5: Sweep + ship hygiene

- `grep -rn 'delta disjoint\|allow-local-merge' plugins/ .claude/ docs/` for
  consistent token spelling; verify `test/pre-merge-rebase.test.ts`,
  `-parity.test.sh`, `-headless.test.sh`, `incident-sandbox-coverage.test.sh`
  still pass unchanged.

## Alternative Approaches Considered

| Approach | Rejected because |
|---|---|
| GitHub merge queue | Adopted-and-reverted (PR #5800 deadlock); blocked upstream by `codeql-action#1537` — verified OPEN. Tracked by #4856/#5840; not re-proposable. |
| Skip sync unconditionally when head is green | A green head may predate a main-side change that overlaps the PR's files — the up-to-date invariant is load-bearing there; disjointness is the provable subset. |
| Extend disjoint-skip to `sync-pr-behind.sh` (poll loop) | #8683's contested-design scope-out; different callers (3 call sites) and a settle-first design question this issue does not own. |
| Merge-tree recomputation (`git merge-tree --write-tree G B`) as the local-merge proof | Requires the commits to be local; `admin-merge-ready.sh` is deliberately API-only (it runs wherever `gh` is authenticated, including detached worktrees and CI). The compare-subset proof is the API equivalent. |
| Require only docs-only (no disjointness) on the carryover delta | Kept both filters: disjointness is free (the PR file list is already fetched for UNTRUSTED-CI) and removes even textual doc overlap. |

## Non-Goals

- Re-adopting or re-proposing the merge queue (#4856, gated on #5840).
- Changing `sync-pr-behind.sh`, ship Phase 7, or merge-pr §5.2 poll logic (#8683).
- The remaining #8791 items (PR-URL spellings, `main`-checkout skip, `ship-unpushed-commits-gate.sh` cwd-scoping, `lib/pr-head.sh` extraction) — acknowledged overlap, not folded in.
- Relaxing `UNTRUSTED-CI`, DIRTY, or any review-evidence gate semantics.

## User-Brand Impact

- **If this lands broken, the user experiences:** a maintainer-side merge gate that either still livelocks (wasted CI) or, worst case, admin-merges a head whose green was voided by an overlapping delta — surfacing as a red `main` caught by the post-merge push run, not as a customer-facing artifact.
- **If this leaks, the user's [data / workflow / money] is exposed via:** no data exposure surface — the change alters when merge machinery rewrites a branch; a wrong disjointness verdict could merge an unverified head, which is a workflow-integrity risk bounded by the push-run CI on `main`.
- **Brand-survival threshold:** `none`
- `threshold: none, reason: internal merge-machinery policy; no end-user or regulated-data surface is touched (.claude/hooks/ + plugins/soleur/scripts/ only, and the worst case lands as a red main CI run)`

## Observability

```yaml
liveness_signal:
  what: "Hook emits additionalContext 'delta disjoint' on skip / 'merged origin/main' on sync; admin-merge-ready emits SOLEUR_ADMIN_MERGE_READY verdict=… reason=carryover-local-docs on the new arm"
  cadence: "per-invocation"
  alert_target: "agent transcript (additionalContext) / operator stderr via headless_or_stderr"
  configured_in: ".claude/hooks/pre-merge-rebase.sh; plugins/soleur/scripts/admin-merge-ready.sh"
error_reporting:
  destination: "emit_incident ledger .claude/.rule-incidents.jsonl (deny paths only — unchanged); headless log under $GIT_COMMON_DIR/soleur-session-state/logs/"
  fail_loud: "PreToolUse deny JSON on conflict/push failure (unchanged); not-ready exit 1 with carryover-* reason on the new arm"
failure_modes:
  - mode: "disjointness computation fails (diff error, empty merge-base)"
    detection: "hook falls through to the existing sync — failure direction is status quo"
    alert_route: "headless_or_stderr warn line"
  - mode: "carryover arm mis-evaluates (API shape drift)"
    detection: "unparseable compare/commit body → exit 3 error, never a silent pass"
    alert_route: "marker line verdict=error"
logs:
  where: "per-PPID headless logs ($GIT_COMMON_DIR/soleur-session-state/logs/) and incident ledger"
  retention: "log-rotation.sh policy (unchanged)"
discoverability_test:
  command: "bash plugins/soleur/scripts/admin-merge-ready.sh --help"
  expected_output: "SOLEUR_ADMIN_MERGE_READY"
```

## Architecture Decision (ADR/C4)

This change re-scopes what certifies a merge head: green-SHA carryover extends
from "GitHub-verified merge only" to "GitHub-verified OR clean-merge-proven +
docs-only-disjoint", and the hook's unconditional sync gains a disjointness
exception — a merge-policy trust-boundary decision a future engineer would be
misled without (the recorded rule today is unconditional).

### ADR

- New **ADR-264** (provisional — subject to the ship-time `adr-ordinals`
  collision gate and renumbering sweep): "Green-SHA certification may carry
  across a provably docs-only disjoint delta; pre-merge sync is conditional on
  file-set overlap". Authored via `soleur:architecture` in this PR.

### C4 views

- No view changes. External-actor/system enumeration checked against all three
  model files (`model.c4`, `views.c4`, `spec.c4`): the only external system
  involved is GitHub (already modeled — `webapp -> github` edges and the GitHub
  Pages/CI elements); no new actor, vendor, data store, or access relationship
  is introduced — `.claude/hooks/` and `plugins/soleur/scripts/` are repo
  internals the C4 model deliberately does not enumerate.

### Sequencing

- ADR ships in this PR (not deferred) per `wg-architecture-decision-is-a-plan-deliverable`.

## Guard Contract

### Guard 1 — disjoint-delta sync skip (`.claude/hooks/pre-merge-rebase.sh`)

**Property.** When the sync block is reached (session cwd is the PR's own
checkout at-or-ahead of its pushed head, or state L) and `merge-base(HEAD,
origin/main) != origin/main`, the hook pushes a new head only if
`files(merge-base..origin/main) ∩ files(merge-base..HEAD) ≠ ∅`; a disjoint
incoming delta leaves HEAD byte-identical — no merge commit, no push.

**Assembly.** The single sync site in the hook (`acquire_lock rebase-main` →
`git merge origin/main` → `git push`) — every auto-sync funnels through it; the
disjointness evaluation consumes the already-computed `MERGE_BASE`/`REMOTE_MAIN`
and must run before the lock. No second sync path exists in this hook;
`sync-pr-behind.sh` is a different surface (out of scope, #8683).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Compute the incoming delta reversed (`diff HEAD MERGE_BASE` or `diff MERGE_BASE HEAD` on both sides) → disjoint fixture must still skip | RED |
| 2 | Compute the disjoint verdict but execute the merge/push anyway (check not wired to the skip) → disjoint fixture asserts `git rev-parse HEAD` unchanged | RED |
| 3 | Overlap via unanchored substring match so `docs/a.md` "overlaps" `docs/a.md.bak` → suffix-collision fixture must still sync | RED |
| 4 | Delta with a second added file where only the second overlaps the PR set → must sync (a check that examines only the first member misses it) | RED |
| 5 | (harness) Drop the `delta disjoint` literal from the emitted context → suite asserting the marker fails even though exit is 0 — a guard that only checks the exit code cannot see the skip arm vs. the up-to-date arm | RED |
| 6 | (harness, must-PASS) Incoming delta empty (already up-to-date) → exits 0 via the earlier arm; suite distinguishes by marker so this is a non-canonical PASS input | PASS |

### Guard 2 — same-repo `-R`/`--repo`/`GH_REPO`/`GH_HOST` resolution

**Property.** A `gh pr merge` invocation scoped to the same repository as the
session checkout resolves the PR head exactly as the flagless form (evidence
range = PR head; own-checkout detection and state-P sync-skip engage); an
invocation scoped to a different or unresolvable repository keeps state-L
degradation.

**Assembly.** The `MERGE_TARGET_WHY` chain's repo-pointer arms (`-R`/`--repo`
grep arm, `GH_(REPO|HOST)=` arm) plus `_merge_args` token extraction — the only
sites deciding "which repository" and "which number".

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Accept any `-R` operand as same-repo unconditionally → foreign-repo fixture falsely resolves the head (review gate reads the PR's commits for a merge elsewhere) | RED |
| 2 | Compare operands without normalization (`git@github.com:o/r.git` ≠ `o/r`, `.git` suffix, scheme/case variants) → same-repo `-R` fixture stays state-L | RED |
| 3 | Strip `-R <operand>` from `$SCAN` but not `$CMD` (or vice versa) → the scan/cmd divergence arm denies and resolution never engages | RED |
| 4 | (guard's own dispatch) Strip only `-R` but leave `--repo=`/`GH_REPO=` unhandled → fixture using `--repo=owner/repo` still degrades → assembly is the flag-family, not one spelling | RED |
| 5 | (harness, must-PASS) `gh pr merge N -R owner/repo` (flag AFTER the number, same repo) resolves → proves the suite is not keyed on flag position | PASS |

### Guard 3 — docs-only local-merge green carryover (`admin-merge-ready.sh`)

**Property.** `--green-sha G --allow-local-merge` certifies head H only when H
has exactly parents `[G, B]`, `compare(B...base)` is `ahead|identical`, the file
set of `compare(G...H)` ⊆ the file set of `compare(merge_base(G,B)...B)` (clean
merge — nothing beyond what B contributed), and every file in that added set is
docs-classified and absent from the PR's file list; otherwise refuse with a
`carryover-*` reason. Precondition-holds-but-property-fails row required: a
clean merge adding a code file satisfies the shape checks and MUST still refuse.

**Assembly.** The `GREEN_SHA` block inside `check_once` — the only carryover
decision site — plus the `marker`/`finish` contract (`reason=` token names the
arm taken) and the PR file list already fetched for `UNTRUSTED-CI`. The merge
block in `settle-then-admin-merge.md` is the sole sanctioned caller shape.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Drop the subset proof (any 2-parent merge passes) → fixture whose merge adds a file outside the base delta (smuggled edit) must refuse | RED |
| 2 | Drop docs-only + PR-disjointness filters → fixture merging a code-file delta must refuse | RED |
| 3 | Accept a head whose `parents[0] != G`, or a non-merge head → wrong-parent/single-parent fixture must refuse | RED |
| 4 | New arm reachable WITHOUT `--allow-local-merge` → bare-`--green-sha` local-merge fixture must still refuse (`carryover-unverified`) — the flag is the opt-in | RED |
| 5 | (guard's own dispatch) Emit verdict=ready with a reason token outside the `carryover-*` family, or no reason → suite asserting `reason=carryover-local-docs` fails | RED |
| 6 | (harness, must-PASS) Docs-only delta touching a `knowledge-base/` path the PR does not list → ready via the new reason | PASS |

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open --limit 200` (87 open)
queried 2026-10-01 for `.claude/hooks/pre-merge-rebase.sh`,
`plugins/soleur/scripts/admin-merge-ready.sh`,
`plugins/soleur/skills/ship/references/settle-then-admin-merge.md`, and
`plugins/soleur/scripts/sync-pr-behind.sh` — zero body matches.

## Files to Edit

- `.claude/hooks/pre-merge-rebase.sh` — disjoint-delta skip; same-repo `-R` operand normalization
- `plugins/soleur/scripts/admin-merge-ready.sh` — `--allow-local-merge` carryover arm; header + `usage()` updates
- `.claude/hooks/pre-merge-rebase.test.sh` — new T-disjoint / T-overlap / T-failopen / -R cases
- `plugins/soleur/scripts/admin-merge-ready.test.sh` — carryover-arm cases
- `test/pre-merge-rebase.test.ts` — `-R` resolution coverage if the stubbed-arg shape allows (evaluate at implementation; the `.claude` fixture suite is the primary home)
- `plugins/soleur/test/admin-merge-ready-wiring.test.sh` — update only if it pins the usage text / flag surface
- `plugins/soleur/skills/ship/references/settle-then-admin-merge.md` — detached-worktree bullet scoped to overlapping deltas; `--green-sha` section gains the local-merge arm (reference files carry no byte ceiling)
- `plugins/soleur/skills/ship/SKILL.md` — was-green carryover sentence ONLY, net ≤ ~300 bytes: `skill-body-budget.json` pins `ship` at 274000 and the file is at 273665 on this branch (335 bytes headroom, measured 2026-10-01 against `lint-skill-body-budget.py --base origin/main` semantics — net added bytes, not gross). Prefer compressing adjacent prose over a straight addition.
- `plugins/soleur/skills/merge-pr/SKILL.md` — the was-green carryover sentence (not a lifecycle skill; unbudgeted)
- `knowledge-base/project/constitution.md` — annotate the `[hook-enforced: pre-merge-rebase.sh]` line with the disjoint-delta exception
- `knowledge-base/engineering/architecture/decisions/ADR-264-*.md` — new (provisional ordinal)

## Files to Create

- `knowledge-base/engineering/architecture/decisions/ADR-264-<slug>.md` (also listed above as an edit-target on create)

## Domain Review

**Domains relevant:** engineering (CTO/devex lens)

### Engineering

**Status:** reviewed (inline — this pipeline context has no Task-subagent runtime; sequential single-pass assessment, `Reviewed-Coverage: sequential-fallback`)

**Assessment:** devex-facing merge-machinery change. It loosens a
hook-enforced invariant ("merge latest origin/main before merging") in a
bounded, provable way — bounded because file-set disjointness is computed, not
assumed, and the residual semantic-coupling risk is caught by the push-to-main
CI run. No production serving surface is affected.

### Product/UX Gate

Not applicable — no UI-surface file in Files to Edit/Create (mechanical
override did not fire; subjective tier NONE).

## Acceptance Criteria

- [ ] AC1 (issue acceptance): an admin merge of a verified SHA is not rewritten by the hook when the delta is disjoint — `gh pr merge --admin --match-head-commit <sha>` from the PR's own checkout, with `origin/main` ahead only on files outside the PR diff, leaves the head at `<sha>` and the merge lands.
- [ ] AC2: with an overlapping incoming delta the hook retains today's behavior (merge + push) — `T-overlap` fixture.
- [ ] AC3: any failure computing disjointness (diff error, unresolvable merge-base) falls through to the existing sync path — fail toward status quo.
- [ ] AC4: `gh pr merge -R owner/repo <N>` scoped to this repository resolves the PR head (evidence range + state-P skip engage); scoped to another repository it degrades to state L exactly as today.
- [ ] AC5: `admin-merge-ready.sh <N> <sha> --green-sha <G> --allow-local-merge` exits 0 for a clean local merge whose added delta is docs-only and disjoint from the PR files, and refuses (not-ready, `carryover-*`) for code deltas, smuggled files, wrong parentage, or a missing flag.
- [ ] AC6: all existing suites pass: `.claude/hooks/pre-merge-rebase{,-parity,-headless}.test.sh`, `plugins/soleur/scripts/admin-merge-ready.test.sh`, `plugins/soleur/test/admin-merge-ready-wiring.test.sh`, `test/pre-merge-rebase.test.ts`, `incident-sandbox-coverage.test.sh`.
- [ ] AC7: `settle-then-admin-merge.md`, `ship/SKILL.md` Phase 7, `merge-pr/SKILL.md` §5.2 and the constitution annotation reflect the new behavior; ADR-264 (provisional) exists and `lint-guard-contract.py` passes on this plan.

## Test Scenarios

- Given a branch behind `origin/main` on disjoint files, when `gh pr merge` is invoked from the PR's checkout, then the hook exits 0 with `delta disjoint` context and HEAD is unchanged (no merge commit, no push).
- Given the same state but an overlapping file, when invoked, then the hook merges and pushes as today.
- Given `gh pr merge -R this-repo <N>` from a foreign checkout, when invoked, then the resolver reads PR `<N>`'s head and the sync is skipped (state P).
- Given `gh pr merge -R other/repo <N>`, when invoked, then `MERGE_TARGET_WHY` fires and evidence/sync behave as today's state L.
- Given `admin-merge-ready.sh --green-sha G --allow-local-merge` on head H=merge(G, docs-only-delta), when run, then verdict=ready with `reason=carryover-local-docs`.
- Given the same but a code-file delta or a smuggled file, when run, then verdict=not-ready.
- Regression: `-R` operand unparseable or origin non-GitHub → refused (state L), never resolved.

## Success Metrics

- On a PR merging during a busy-main window with a disjoint delta, zero head rewrites between green certification and merge (vs. up to 4 observed on #9339).
- No regression in the review-evidence gate (all existing deny paths unchanged).

## Dependencies & Risks

- **Semantic coupling past file-level disjointness**: main may change file A in a way that breaks PR file B without sharing a path (rename, API contract). File-disjointness cannot see that. Mitigation: the post-merge push run on `main` catches it; the admin arm additionally bounds merged deltas to docs-only. Accepted residual, disclosed here and in the ADR.
- **Squash vs. merge commit shape**: `--green-sha` requires a 2-parent merge head — squash merges produce a single parent and never carry over (unchanged).
- **`gh api compare` semantics**: the subset proof relies on `merge_base_commit` + `files[]` from the three-dot compare API; a >300-file or paginated delta must fail closed to `not-ready`, mirroring the existing `incomplete-files` posture.
- **Constitution drift**: the recorded rule must be annotated in the same PR or documented behavior diverges from the hook.
- **Related open issues**: #8683 (poll-loop sync — same invalidation pattern on a different surface; natural follow-up), #8791 (the `-R` fix partially addresses its "PR-ref spellings" item — comment there post-merge), #9340.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6.
- The disjoint check must run BEFORE `acquire_lock rebase-main`; inside the lock it would still serialize and could hold the lock across an early exit.
- Do NOT extend the skip to `sync-pr-behind.sh` here — that surface is #8683's contested-design scope-out.
- `gh api --paginate` emits one JSON array per page — slurp with `jq -s 'add // []'` before `--argjson`/storage (constitution line 32).
- `MERGE_TARGET_WHY`'s deny text is user-visible; new reasons must not include PR-controlled strings (file paths are excluded from marker output for that reason in admin-merge-ready.sh).
- The hook runs under `set -eo pipefail` without `-u` — a grep/comm pipeline that exits non-zero on no-match must carry `|| true` exactly where the existing code does.
- `_merge_args` splits command text on `^|&&|\|\||;|\s--\s`; `&`/`|` are also redirect operators and `$(...)`/`#` are overloaded — the `-R` operand extraction must run on the detector's own anchored segments and the raw-vs-stripped (`$SCAN` vs `$CMD`) agreement check must still see identical residues after flag-stripping (plan-sharp-edges entries on shell-text segmentation and invocation-binding).
- ADR-264's ordinal is a claim, not a reservation: enumerate it across pushed `origin/*` refs (not only `origin/main`) at implementation start, and the ship-time `adr-ordinals` gate re-verifies before merge.
- Hook ordering is pinned: `ship-unpushed-commits-gate.sh` runs AFTER `pre-merge-rebase.sh` (`.claude/settings.json`; T11 in `ship-unpushed-commits-gate.test.sh`). A disjoint skip changes the head that gate counts only in the no-op direction — keep T11 green; do not reorder.
- `admin-merge-ready.sh` pagination: the `compare` files list truncates at ~300 files per page — slurp pages and fail closed (`error`, not `not-ready`) when the file count cannot be proven complete, mirroring the existing `incomplete-files` posture.

## References & Research

- Issue: #9401 (this work); observation source PR #9339 (merged 2026-10-01)
- Hook: `.claude/hooks/pre-merge-rebase.sh` (resolver `MERGE_TARGET_WHY` chain ~lines 190-280; sync block ~lines 480-579)
- Gate: `plugins/soleur/scripts/admin-merge-ready.sh` (`--green-sha` arm in `check_once`, ~lines 218-251)
- Runbook: `plugins/soleur/skills/ship/references/settle-then-admin-merge.md` (detached-worktree trap, PR #9048)
- ADR-032 amendment 2026-06-30 (merge queue adopted→deadlocked→reverted); post-mortem `knowledge-base/engineering/operations/post-mortems/merge-queue-codeql-merge-group-deadlock-postmortem.md`
- Learnings: `2026-06-02-auto-merge-livelock-fast-moving-main.md`, `2026-09-19-githubs-merge-ref-runs-your-prs-own-defect-against-it.md`, `2026-09-24-8611-merge-tail-six-frictions-and-a-stale-reaper.md`
- Related (out of scope): #4856, #5840, #8683, #8791, #9340
- Upstream: `github/codeql-action#1537` (OPEN, verified 2026-10-01)
