---
title: "fix: infra-privileged-tier-census G4c diffs the moving origin/main tip — use merge-base"
date: 2026-10-11
slug: fix-tier-census-g4c-merge-base
branch: feat-one-shot-9956-tier-census-g4c
issue: 9956
closes: 9956
type: fix
lane: cross-domain
---

# fix: infra-privileged-tier-census G4c diffs the moving origin/main tip — use merge-base

## Overview

`tests/scripts/test-infra-privileged-tier-census.sh` row G4c compares the set of
`resource` blocks declared by the base ref against the set declared at HEAD and
requires every missing address to be claimed by a `removed { lifecycle { destroy =
false } }` block, an `INTENDED_DESTROYS` entry, or a `RETIRED_STATE_ABSENT` entry.
The base ref defaults to the `origin/main` **tip**, a moving target: a resource
block added on main after a PR's merge ref (or last local merge) was computed
reads to G4c as a resource *the PR deleted*, so the row goes red on drift the PR
never touched. Issue #9956 filed this against PR #9946 CI run 38087685142, where
the six egress resources #9529 *added* on main (`logtail_exploration.egress_gw_*`,
`logtail_exploration_alert.egress_gw_*`, `terraform_data.egress_gateway{,_web2}`)
reported as orphans because the fetched `pull/9946/merge` ref predated the merge.

The issue frames #9529 as having *deleted* the resources; premise validation
against the squash commit shows it only added them (`git show 149a5d3b4e --
'apps/web-platform/infra/*.tf'` has zero `-resource` lines), and all six blocks
are still declared on `origin/main` today. The defect is therefore the base
semantics, not a missing `removed` claim: G4c's base should be the merge-base of
HEAD and `origin/main` — the tree the diff under test actually diverged from —
which attributes deletions to the diff that made them and is immune to both
main-tip drift and stale merge refs.

## Problem Statement / Motivation

- **Observed failure:** `test-scripts (3/8)` on PR #9946 (run 38087685142, job
  114320074962) printed `FAIL G4c … orphans=['apps/web-platform/infra
  logtail_exploration.egress_gw_deny_spike', … 'terraform_data.egress…` — six
  addresses #9529 had *added* on main hours earlier, reported as deletions.
- **Mechanism:** in that CI run the checkout was `refs/remotes/pull/9946/merge`,
  a merge ref computed while main was still at `3ef5aa6` (pre-#9529), while the
  fetch placed `origin/main` at the post-#9529 tip. `base_declared` (tip) held the
  six resources; `declared_addrs` (stale merge ref) did not → orphans → red.
- **Same class, prior incident:** PR #8904 / learning
  `knowledge-base/project/learnings/workflow-issues/2026-09-27-a-blocking-gate-diffing-against-moving-main-fails-on-drift-and-staging-then-merging-deadlocks.md`
  — a `.tf` file added on main after the last local merge read as a resource the
  branch deleted, blocking the lefthook `bun-test` gate for ~6h. That learning's
  "remedy is currency" was a workaround for the same root cause.
- **Why now:** every open PR whose checkout or merge ref predates the latest
  `.tf` resource addition on main reds G4c until git/GitHub refreshes the ref —
  a recurring false-red on the highest-severity row of the Tier-B census.

## Research Reconciliation — Spec vs. Codebase

| Spec/issue claim | Codebase reality | Plan response |
|---|---|---|
| "#9529 deleted `resource` blocks from apps/web-platform/infra without `removed {}` claims" | `git show 149a5d3b4e -- 'apps/web-platform/infra/*.tf'` contains only `+resource` lines (six additions, zero deletions); all six blocks still exist on `origin/main` (`betterstack-logs-alerts.tf:1181,1202,1237,1258`, `server.tf:2686,2764`) | Do **not** add `removed` blocks or `INTENDED_DESTROYS`/`RETIRED_STATE_ABSENT` entries — the addresses are live and declared; a `removed {}` from a still-declared address is itself a contract violation. Fix the guard's base instead |
| "G4c red **on main**" | The failing run was a `pull_request` event on `chore-9855-salvage`, not a main push; on push-to-main `base == HEAD` so the row is vacuously green | Scope the fix to the PR/local-gate diff path where the false attribution lives |
| "if the egress-gateway deletion was intended-destroy, that intent needs declaring" | There is no deletion to intend — the resources are live | Descoped; no declaration needed |
| (implicit) "the base ref is `origin/main`" | ADR-282 §Consequence for the anchor describes the intended semantics as "the merge-base diff the census computes for G4c" — the implementation diverged from the recorded architecture | Merge-base aligns the code with the ADR's description; no ADR reversal |

## Proposed Solution

Change the default G4c base in `tests/scripts/test-infra-privileged-tier-census.sh`
from the `origin/main` tip to `git merge-base HEAD origin/main`, with a fallback
that preserves today's semantics when no merge base exists:

```bash
# (shape, not literal) — resolution helper near the current BASE_REF line
if [ -n "${IPT_BASE_REF:-}" ]; then
  BASE_REF="$IPT_BASE_REF"
elif BASE_REF="$(git -C "$REPODIR" merge-base HEAD origin/main 2>/dev/null)" && [ -n "$BASE_REF" ]; then
  : # resolved — the tree the diff under test actually diverged from
else
  BASE_REF="origin/main"   # no merge base (no origin/main / shallow / non-git REPODIR): pre-#9956 semantics
fi
```

Why merge-base is the correct base (each case enumerated):

- **PR deletes a resource block** — the block is declared at the merge-base and
  absent at HEAD → orphan → red, exactly as intended. A deletion is only possible
  relative to a tree that declared it, and the merge-base is that tree.
- **Resource added on main after the fork point** — not in `base_declared` → never
  an orphan. When the PR lands, a three-way merge keeps the addition, so the tip
  diff was reporting a deletion the landing would never perform (the #8904/#9956
  false-red class — eliminated, not waived).
- **Stale `pull/N/merge` ref** — merge-base(HEAD, tip) equals the merge ref's own
  second parent, the tree the merge was actually computed against → consistent
  base regardless of tip movement. No dependence on GitHub recomputing the ref.
- **Branch deletes a resource main also forgot (with `removed {}`)** — the claim
  block travels into HEAD with main's change → `forgotten_addrs` covers it → green.
- **Push-to-main runs** — merge-base(HEAD=tip, tip) = tip → vacuous, same as today.
- **No merge base (missing `origin/main`, shallow clone, non-git `IPT_REPO_ROOT`)**
  → fallback to `origin/main` = today's behaviour; if that is unresolvable too,
  `BASEDIR=""` → G4c reports "base unavailable" and fails closed, same as today.
- **`IPT_BASE_REF` set** — honored verbatim (escape hatch preserved).

What the tip-diff covered that merge-base does not: nothing true-positive. A
resource *deleted on main already* is absent from the tip and invisible to both
bases. A deletion by the diff under test is visible to both; only the tip invents
deletions the diff never made.

## Technical Considerations

- **One resolution site, one materialization chokepoint.** `BASE_REF` is set at
  `tests/scripts/test-infra-privileged-tier-census.sh:82`; the base tree is
  materialized by the `git ls-tree`/`git show` loop at `:1939-1952`. Extract the
  pair into a small helper (e.g. `resolve_base_ref <repodir>` +
  `materialize_base_dir <repodir> <ref> <destdir>`) so the new fixture leg drives
  the *production* code path rather than a copy.
- **All git calls stay `-C "$REPODIR"`-qualified** (worktree-safe; HEAD resolves
  per-checkout). This is also what makes the CI merge-ref case work — HEAD is
  `pull/N/merge` there and the local branch tip under lefthook.
- **Criss-cross histories:** `git merge-base` prints one best base; adequate — the
  check needs *a* common ancestor that declared the deleted block, not all of them.
- **Doc updates in the same file:** the seam comment at `:69` (says `default
  origin/main`) and the G4c comment block at `:874` ("$BASE_ROOT is the base ref's
  copy") must name the merge-base semantics; the `check("G4c: …")` wording ("the
  base ref declares") stays accurate.
- **Fixture leg shape (suite conventions):** a synthetic `git init` repo under
  `$T` with `refs/remotes/origin/main` materialized via `git update-ref` — the
  same no-touch-of-caller-tree discipline the base materialization already uses.
  The compliant `.github` fixture tree (`$FIX/tree/.github`) is reused as `GHDIR`;
  only the G4c TSV row is read (`wf_row`), so unrelated fixture-row verdicts are
  out of scope by convention.
- **Attack-surface note:** no new inputs — `IPT_BASE_REF` was already an env seam;
  `git merge-base` output is a SHA consumed by `git ls-tree`/`git show`.
- **NFRs:** performance negligible (one `merge-base` call); no security boundary
  moved (the guard's contract — deletions must be claimed — is unchanged; only
  attribution of the diff is corrected).

### Alternative Approaches Considered

| Alternative | Why rejected |
|---|---|
| Add `removed { from = <addr> }` blocks for the six addresses (the issue's literal remedy) | Infeasible: the addresses are still declared resources on main. A `removed {}` from a still-declared address would itself violate the guard's contract and cannot coexist with the `resource` block. |
| `INTENDED_DESTROYS` / `RETIRED_STATE_ABSENT` entries | Both are claims about deletions; nothing was deleted. `RETIRED_STATE_ABSENT` would additionally trip G4g (address *is* declared at HEAD). |
| Base = `pull_request.base.sha` / `github.event` plumbing | Couples a CI-agnostic suite to GitHub context vars and is unavailable to the local lefthook gate; merge-base derives the same fork point locally in both environments. |
| Keep tip-diff; document "merge main first" harder | Perpetuates a recurring false-red on the highest-severity row; the #8904 incident cost ~6h and #9956 re-filed the same class a fortnight later. |
| Re-fetch/recompute the merge ref before running | The suite cannot control GitHub's lazy merge-ref recomputation; merge-base makes the computation correct for whatever HEAD actually is. |

## User-Brand Impact

- **If this lands broken, the user experiences:** two broken shapes, named: (a) a
  false *red* keeps blocking unrelated PRs on `.tf` drift they never touched —
  operator-facing CI friction, no user artifact; (b) a false *green* would let a
  real unclaimed deletion through — the deleted resource then plans a plain
  DESTROY at the next apply, and for the App-identity class this guard exists to
  protect that is every connected user's installation-token mint broken.
- **If this leaks, the user's [data / workflow / money] is exposed via:** no new
  exposure — the change reads git object metadata only, writes nothing outside
  the suite's own `$T`, and does not weaken the claim requirement.
- **Brand-survival threshold:** `aggregate pattern`
- **Threshold decision (challengeable):** the guard's blast radius is the
  shared infra boundary (a false green on a real deletion is a fleet/user-wide
  event, not a single user's incident), but this change narrows only the
  *attribution base* and adds RED fixture coverage for the true-positive path,
  so per-PR CPO sign-off is not warranted.

## Observability

The suite is itself the observability surface for the credential boundary; the
change is verified by the suite's own fixture legs plus this presence probe.

```yaml
liveness_signal:
  what: "test-all shard row `tests/scripts/infra-privileged-tier-census` — G4c verdict line"
  cadence: "per PR (affected-shard) and per local commit gate run"
  alert_target: "CI check failure / lefthook refusal"
  configured_in: "scripts/test-all.sh run_suite registration"
error_reporting:
  destination: "suite stdout FAIL line naming orphans= plus IPT_G4_* stderr counters"
  fail_loud: "exit 1 with the G4c FAIL row listing orphan addresses"
failure_modes:
  - mode: "merge-base unresolvable (no origin/main, shallow, non-git REPODIR)"
    detection: "G4c reports 'base unavailable' (fail-closed, preserved from today)"
    alert_route: "CI red on the suite row"
  - mode: "regression to tip-diff semantics"
    detection: "new fixture leg: main-side post-fork addition absent from HEAD is NOT an orphan — a tip-diff reintroduction reds it"
    alert_route: "CI red on the suite row"
logs:
  where: "CI job log (test-scripts shard) / local run stdout+stderr"
  retention: "GitHub Actions run retention"
discoverability_test:
  command: grep -n merge-base tests/scripts/test-infra-privileged-tier-census.sh
  expected_output: merge-base
```

## Guard Contract

The deliverable modifies a guard's decision mechanism, so the contract covers the
changed surface — the BASE_REF→BASEDIR path that feeds `base_declared`.

### Guard 1 — G4c base resolution (merge-base attribution)

**Property.** A `resource` block is an orphan candidate iff the diff under test
deletes it: declared at the merge-base of HEAD and `origin/main` and absent at
HEAD, never because a third party added it on main after the fork point — and
when no base can be resolved the row fails closed.

**Assembly.** The single chokepoint is the BASE_REF resolution +
`git ls-tree`/`git show` materialization in
`tests/scripts/test-infra-privileged-tier-census.sh` feeding `base_declared` in
`ipt.py`; every base declaration flows through it for both `GUARD4_ROOTS`
(`apps/web-platform/infra`, `apps/web-platform/infra/git-data-root-key`). The
override seam is `IPT_BASE_REF`; the fallback seam is `origin/main` (pre-#9956
semantics). HEAD-side declarations are read through `read_tf`/`declared_in`
(unchanged, out of scope).

**Mutation matrix:**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | Synthetic repo: feature branch deletes `resource` block B declared at merge-base, no `removed {}` claim | RED — orphans names B (dispatch row: proves the row still fires on a real deletion) |
| 2 | Same repo, main adds `resource` block C after the merge-base while HEAD lacks it | GREEN for C — the #9956 regression; a tip-diff reintroduction reds it |
| 3 | Same repo, second base-declared block B2; HEAD deletes only B2 | RED — orphans names B2 and not B (second-member-after-compliant-first) |
| 4 | Same repo, deletion of B covered by `removed { from = doppler_secret.gone_b; lifecycle { destroy = false } }` | GREEN — the claim path is intact under the new base |
| 5 | `IPT_BASE_REF=<tip SHA>` on the same fixture | RED listing C — override honored verbatim and the leg proves the fixture discriminates old vs new semantics |
| 6 | Repo with no `origin/main` and `IPT_BASE_REF` unset | G4c reports "base unavailable" — fail-closed preserved |

Rows 1, 3–6 are suite/harness rows against the materialization; row 2 is the
must-PASS input that differs from the canonical only in the direction the
contract now permits (additions on main do not attribute).

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "tests/scripts/test-infra-privileged-tier-census.sh row G4c fails on main" | FR-1 (merge-base base) / Files-to-Edit entry 1 / AC1–AC6 | mapped |
| 2 | "the guard is red for every PR whose base predates #9529 once it syncs main" | FR-1 + fixture leg rows 2 and 5 (AC3, AC5) | mapped |
| 3 | "a deleted resource block with no removed{destroy=false} plans a plain DESTROY at next apply — if the egress-gateway deletion was intended-destroy, that intent needs declaring per the guard's contract" | — | descoped — justification: premise refuted by the squash diff (zero `-resource` lines; all six addresses still declared and live on `origin/main`), so there is nothing to declare; see Research Reconciliation |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `tests/scripts/test-infra-privileged-tier-census.sh` base-ref resolution → merge-base | "row G4c fails on main" / "the guard is red for every PR whose base predates #9529" | inferred — justification: the issue's named remedy (`removed {}` claims) is infeasible because nothing was deleted; merge-base is the minimal mechanism that makes G4c attribute deletions to the diff that made them |
| Synthetic-git fixture legs in the same suite | "row G4c fails on main" | inferred — justification: the suite's own mutation-matrix contract (this file's Guard Contract conventions) requires a discriminating leg proving the new base semantics both ways |
| Seam/doc comment updates in the same file | "row G4c fails on main" | inferred — justification: the header's `default origin/main` text would otherwise lie about the shipped mechanism |

### Split Assessment

- Subsystems touched: 1 — `tests/`
- Planned files: 1 | Estimated changed lines: ~120 (resolution + helper extraction + fixture legs + comments)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

- [ ] **AC1.** `grep -n 'merge-base' tests/scripts/test-infra-privileged-tier-census.sh` returns the resolution line(s); the `IPT_BASE_REF`-unset default resolves to `git merge-base HEAD origin/main` output, not the literal `origin/main` tip.
- [ ] **AC2.** With `IPT_BASE_REF=<sha>` exported, the base materializes verbatim from `<sha>` (override preserved).
- [ ] **AC3.** New fixture leg: synthetic repo where `origin/main` adds a `resource` block after the merge-base and HEAD lacks it → the G4c TSV row for that leg reports the added address **absent** from orphans; the identical fixture under `IPT_BASE_REF=<tip sha>` reports it present (leg discriminates old vs new semantics).
- [ ] **AC4.** Fixture leg: HEAD's own unclaimed deletion is reported as an orphan; adding `removed { from = <addr>; lifecycle { destroy = false } }` at HEAD greens it.
- [ ] **AC5.** No-resolvable-base leg (`IPT_BASE_REF` unset, no `origin/main`, merge-base fails) → G4c reports "base unavailable" and the suite exits non-zero (fail-closed preserved).
- [ ] **AC6.** `bash tests/scripts/test-infra-privileged-tier-census.sh` exits 0 in this worktree (all pre-existing rows plus new legs green).
- [ ] **AC7.** The seam comment documenting `IPT_BASE_REF` names the merge-base default (`grep -n 'IPT_BASE_REF' tests/scripts/test-infra-privileged-tier-census.sh` shows the updated text).

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure/tooling change to a CI
guard's diff base. The closest lens is Engineering (guard semantics); leader
fan-out is unavailable on this harness, so the semantic analysis is inlined in
Proposed Solution / Technical Considerations and left for PR review.

### Product/UX Gate

Mechanical UI-surface check: Files-to-Edit/Create contain no UI-surface paths —
tier NONE, gate skipped.

## Open Code-Review Overlap

None — `gh issue list --label code-review --state open` bodies searched for
`tests/scripts/test-infra-privileged-tier-census.sh`; zero hits.

## Test Scenarios

- **Given** a synthetic repo with resource blocks A and B at the merge-base and
  resource C added on `origin/main` after the fork, **when** the suite resolves
  the base, **then** `base_declared` contains {A, B} and not C. *(unit — fixture
  leg, production materialization path)*
- **Given** HEAD deletes B with no `removed {}`, **when** G4c runs, **then** the
  row is RED and `orphans` names B but not C. *(unit — mutation matrix rows 1–2)*
- **Given** HEAD deletes only B2 of two base-declared blocks, **when** G4c runs,
  **then** orphans names B2 and not B. *(unit — second-member row)*
- **Given** HEAD deletes B and carries `removed { lifecycle { destroy = false }
  }` for it, **when** G4c runs, **then** the row is GREEN. *(unit — claim path)*
- **Given** `IPT_BASE_REF=<tip>` is exported, **when** the suite resolves the
  base, **then** the tip is used verbatim and C reads as an orphan. *(unit —
  override + discrimination proof)*
- **Given** no merge base exists, **when** the suite resolves the base, **then**
  the origin/main fallback engages; with no origin/main either, the row reports
  "base unavailable". *(unit — fail-closed regression)*
- **Regression (live):** PR #9946's failure mode — a HEAD whose tree predates a
  main-side `.tf` addition no longer reds G4c on that addition. *(integration —
  covered by the fixture legs; the live tree has no real orphans today)*

## Success Metrics

- G4c greens on PRs whose diff deletes nothing, regardless of how far `origin/main`
  has advanced past the fork point (the #9956 / #8904 false-red class eliminated).
- G4c still reds on the suite's own fixture deletion legs and on any real
  unclaimed `.tf` deletion (no loss of the guard's true-positive coverage).

## Dependencies & Risks

- **Fetch depth:** `git merge-base` needs shared history. CI fetches all branch
  refs with no `--depth` (run 38087685142 checkout log); local worktrees share the
  full object store. A hypothetical shallow environment degrades to today's tip
  semantics via the fallback — never blind. *Risk: low.*
- **`IPT_REPO_ROOT` pointing at a non-git tree** (fixture legs pass trees
  directly to `ipt.py`, but a caller could point the seam anywhere): merge-base
  fails → fallback → `ls-tree` fails → "base unavailable" fail-closed, identical
  to today. *Risk: none (preserved behaviour).*
- **Fork-points with no common ancestor** (orphan branches): merge-base fails →
  tip fallback → today's (noisier) semantics. Acceptable residual, strictly
  rarer than today's failure surface.
- **Suite wall-time:** new fixture legs add seconds (one small `git init` + ~5
  commits + ipt.py invocations), inside shard leg 3's budget.

## References & Research

- Failing run: PR #9946, run 38087685142 job 114320074962 (2026-10-10T21:52Z) —
  checkout `refs/remotes/pull/9946/merge` (merge of `7b9585e` into `3ef5aa6`),
  `origin/main` fetched at post-#9529 tip; `orphans=` lists the six #9529 additions.
- Commit `149a5d3b4e` (squash of #9529): six `+resource` lines under
  `apps/web-platform/infra/`, zero `-resource` lines.
- `tests/scripts/test-infra-privileged-tier-census.sh`: `BASE_REF` at `:82`,
  `GUARD4_ROOTS` at `:141`, base materialization at `:1939-1952`, G4c row at
  `:944-948`, allowances `INTENDED_DESTROYS`/`RETIRED_STATE_ABSENT`/`G4_PROTECTED`
  at `:894-932`, seam comment at `:69`.
- ADR-282 §Consequence for the anchor (`decisions/ADR-282-sole-copy-luks-volume-protection-set.md:233`):
  already describes G4c as "the merge-base diff the census computes" — this fix
  aligns implementation with the recorded architecture.
- Prior incident: learning `2026-09-27-a-blocking-gate-diffing-against-moving-main-fails-on-drift-and-staging-then-merging-deadlocks.md`
  (PR #8904) and `plugins/soleur/skills/ship/SKILL.md` tip-drift bullet;
  sharp-edge precedent `plan-sharp-edges.md` "AC that proves 'this PR does not
  touch X' must diff against the merge-base, not the moving tip".

## Research Insights

**Premise validation (Phase 0.6).** Cited artifacts verified: #9956 is OPEN;
commit `149a5d3b4e` exists and *adds* the six resources (premise partially stale —
the "deleted" framing is refuted); `tests/scripts/test-infra-privileged-tier-census.sh`
exists on `origin/main` (3930 lines); the six addresses are all still declared on
`origin/main`. The stale premise changes the plan's shape from "declare removal
claims" to "fix the guard's base semantics".

**Property list (Phase 0.6b).** P1: every resource-block deletion the diff under
test makes is claimed (`removed {}`/`INTENDED_DESTROYS`/`RETIRED_STATE_ABSENT`) —
existing property, preserved. P2: nothing the diff did not delete is attributed
to it — the broken property, this plan. P3: unresolvable base fails closed —
existing property, preserved via the fallback.

**Cut list (Phase 0.6b).** `removed {}` blocks for the six addresses → buys
"silence G4c" but is infeasible (addresses still declared; `removed {}` from a
live `resource` is itself a contract violation). `INTENDED_DESTROYS` /
`RETIRED_STATE_ABSENT` entries → same refutation; G4g additionally rejects a
retired entry for a re-declared address. CI-side base-sha plumbing → superseded
by merge-base, which derives the same fork point without GitHub-context
coupling.

**Local research.** No dedicated Task agents on this harness — repo research and
learnings were gathered inline: the suite's G4a–G4h rows, allowances and
probe machinery read directly; sibling Guard-3 census has no base-diff row;
`plugins/soleur/test/terraform-target-parity.test.ts` greps only `G4H_EXPECTED`
(unaffected); `plugins/soleur/test/operator-9321-stages.test.sh:299` runs the
full suite (stays green under merge-base); affected-paths selection already
includes the suite file (`scripts/lib/test-affected-paths.sh`
`AFFECTED_TESTS_SCRIPTS_INFRA_PRIVILEGED_TIER_CENSUS_PATHS`).

**Learnings applied.** #8904 drift incident (same class, workaround-only remedy);
the merge-base-vs-tip sharp edge; `cq-test-fixtures-synthesized-only` (the git
fixture is built in `$T`, not committed); suite conventions for mutation legs
(`wf_row`, `mutate`, TSV-row-scoped verdicts).

**Spec flow (Phase 3, inline).** Edge cases enumerated: missing `origin/main`,
shallow history, non-git `REPODIR`, orphan-branch HEAD, criss-cross merge bases,
explicit `IPT_BASE_REF`, detached HEAD (CI merge ref), `pull/N/merge` staleness,
`forgotten_addrs` interplay on synced branches. Each is bound to a fallback arm
or a fixture leg above.

Spec lacks valid `lane:` — defaulted to cross-domain (TR2 fail-closed).

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or omits the threshold
  will fail `deepen-plan` Phase 4.6 — it is filled above.
- The fixture leg must drive the production resolution/materialization path
  (extracted helpers), not a re-implementation — a fixture that duplicates the
  logic proves the fixture, not the guard.
- `git merge-base` must be invoked `-C "$REPODIR"` like every other git call in
  the file; an unqualified call resolves HEAD in the wrong repository when the
  suite runs under `IPT_REPO_ROOT`.
- Do not "fix" by adding `IPT_BASE_REF` exports in CI workflows — that spreads
  the workaround across jobs and leaves the local lefthook path broken.
