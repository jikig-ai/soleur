---
title: "chore(archive-kb): archive the #8710 pin-redeploy and #5274 dirty-journal KB artifacts"
date: 2026-09-25
slug: chore-archive-8710-5274-kb-artifacts
branch: feat-one-shot-archive-8710-5274-plans
issue: 5274
type: chore
lane: cross-domain
draft_pr: 8842
related: [8710, 8755, 5274, 8711, 8776, 8211]
---

# chore(archive-kb): archive the #8710 pin-redeploy and #5274 dirty-journal KB artifacts

## Overview

Two features merged on 2026-09-24 left their plan and spec directory at the live paths. This PR
moves them into `archive/` with `plugins/soleur/skills/archive-kb/scripts/archive-kb.sh`, which
uses `git mv` and adds a timestamp prefix. It is a rename-only change: no file content changes.

| Feature | Merged as | Plan | Spec dir (3 files each: decision-challenges.md, session-state.md, tasks.md) |
|---|---|---|---|
| #8710 pin-redeploy gate keys on the apply step | PR #8755 (2026-09-24T22:06Z) | `plans/2026-09-24-fix-pin-redeploy-gate-keys-on-apply-step-plan.md` | `specs/feat-one-shot-8710-pin-redeploy-plan-only-gate/` |
| #5274 git-data dirty journal via dm snapshot | PR #8711 (2026-09-24T14:49Z) | `plans/2026-09-24-fix-git-data-plaintext-dirty-journal-dm-snapshot-plan.md` | `specs/feat-one-shot-git-data-dirty-journal-dm-snapshot/` |

**Out of scope, do not move:** `plans/2026-09-22-feat-git-data-cutover-real-modes-plan.md` and
`specs/feat-one-shot-8211-git-data-cutover-real-modes/`. #8211 is still OPEN and its PR2 has not
merged yet. The legal audit files under `knowledge-base/legal/audits/`, including the #8634 one,
are also not touched.

## Research Insights

**Premise validation (run 2026-09-25 against `origin/main` 51a5541a1a):** PR #8755 and PR #8711 are
both MERGED. #8710 is CLOSED. #5274 is OPEN and stays open, so the PR body says `Ref #5274`, not
`Closes`. #8211 is OPEN, which confirms the exclusion above. All 8 source paths exist in this
worktree.

**Mechanism (archive-kb SKILL.md + script, read in full):**

- The script picks ONE slug per run, either from the branch or passed as an argument. It globs
  `plans/*<slug>*` and probes `specs/feat-<slug>`. This branch's name does not match either feature,
  so every run needs an explicit slug.
- In both features the plan's slug differs from the spec's slug. That is the known discovery gap
  (#8416/#7400). The script now prints `WARNING: found a spec ... but NO plan` for a partial run.
  So each feature needs **two runs**, one per slug, which makes four runs in total. #8757 is the
  precedent: it ran once per slug.
- Dry runs (executed at plan time) each resolve to exactly one artifact, with no extra matches:
  - `one-shot-8710-pin-redeploy-plan-only-gate` → the spec dir only
  - `fix-pin-redeploy-gate-keys-on-apply-step` → the plan only
  - `one-shot-git-data-dirty-journal-dm-snapshot` → the spec dir only
  - `fix-git-data-plaintext-dirty-journal-dm-snapshot` → the plan only
- Each run creates its own timestamp (`%Y%m%d-%H%M%S`), so the four prefixes may differ by a few
  seconds. The #8757 precedent has the same shape (`210147` / `210149`). No test depends on them
  matching.
- The script only runs `git add` and `git mv`. It does not commit, and it does not rewrite
  references or touch `PROMOTED_FILES`.

**Inbound-reference sweep.** Command, run from the worktree root:

```bash
for p in 2026-09-24-fix-pin-redeploy-gate-keys-on-apply-step-plan feat-one-shot-8710-pin-redeploy-plan-only-gate \
         2026-09-24-fix-git-data-plaintext-dirty-journal-dm-snapshot-plan feat-one-shot-git-data-dirty-journal-dm-snapshot; do
  git grep -n -F "$p" -- ':!**/archive/**' ':!*.json'; done
```

Hits, with how each is handled:

- **Self-references inside the moved artifacts.** Examples: tasks.md/session-state.md name their
  own plan, the plan's `branch:` key, and the plan's pointer to its decision-challenges.md. These
  are point-in-time records. They move together into `archive/` and are **not rewritten**, which
  matches #8757.
- **`plugins/soleur/test/preflight-discoverability-test.test.ts` (the `#5274 (2026-09-24): +1 (24 -> 25)` comment).**
  This is a provenance comment that names the plan by basename. The basename survives the move
  (only a timestamp prefix is added), and the #8611 entry sets the precedent of leaving such a
  comment as-is. **Not rewritten.** The G1 test that this comment annotates walks `plans/`
  **recursively**, `archive/` included. So `BASELINE_DECLARED_PROBES = 29` is unchanged by the move.
- `*.json` was checked separately: `git grep` over `*.json` finds zero hits, so nothing in
  `.github/enforcement-contracts.json` or any other registry needs a change.

**Result: no in-repo reference needs rewriting.**

**Out-of-repo pointers that go stale:**

- Issue #8776 (OPEN), "Decision challenges for PR #8755", cites
  `Source: knowledge-base/project/specs/feat-one-shot-8710-pin-redeploy-plan-only-gate/decision-challenges.md`.
  → Post one comment there with the archived path. The issue body is left unchanged.
- The #8711 spec's `decision-challenges.md` DC-1 (the adopted-LUKS replace arm in the rung-2
  rehearsal) was **never filed** as an `action-required` issue. There is no hit in the
  action-required list, in the PR #8711 body, or in an issue search. Its #8755 sibling was filed as
  #8776. After the move, the only record of that dissent sits in an archive directory. → File one
  `action-required` issue in the #8776 shape that cites the archived path, so the move does not
  bury it. This is ~2 min of work, and `ship` Phase 6 step 2.5 already required the issue.

**Guards that apply to KB archive moves, and how to run each:**

| Guard | Applies? | Command / note |
|---|---|---|
| `preflight-discoverability-test` G1 (plan-count baseline) | Yes. It is a recursive walk, so the count stays 29 | `cd plugins/soleur && bun test test/preflight-discoverability-test.test.ts -t G1`. Baseline passes on this tree. |
| `scripts/kb-drift-walker.sh` (broken intra-KB `](x.md)` links; skips `archive/`) | Yes, as a local check. In CI it runs only on a schedule, not as a PR gate | `bash scripts/kb-drift-walker.sh \| jq -c .counts`. Baseline is `{"broken_link":128,"broken_anchor":120}`, all pre-existing. It must not increase. |
| secret-scan `rename-guard` | Exempt. Renames from allowlisted paths to allowlisted paths have the archive-kb shape (SKILL.md §Notes) | No label needed |
| `markdown-lint` (`--repo-sweep`) | No-op. `.markdownlintignore` excludes `knowledge-base/project/` | none |
| `PROMOTED_FILES` (`scripts/guard-vacuity-floor.test.sh`) | Not touched by this diff | If a `git merge origin/main` conflicts there, resolve it as a **union** of both sides. Never pick one side, and never raise the ratchet. |
| `knowledge-base/INDEX.md` | Not tracked on main (ADR-174 builds it at generation time) | none |
| `plugins/soleur/skills/archive-kb/test/archive-kb-partial-run.test.sh` | Not needed. The script is unchanged | none |

**Code-review overlap:** None. All 4 paths were checked against 81 open `code-review` issues.

**Property list:** (P1) After merge, neither feature's plan or spec sits at a live path. (P2) The
history of each file is kept, as an R100 rename. (P3) No live reference points at a path that no
longer exists. (P4) Each feature's decision-challenge record stays reachable from an open issue.
(P5) #8211's artifacts do not move.

**Cut list:** Rewriting references inside the moved artifacts is cut, because they are
point-in-time records per the #8757 precedent. Changing the archive-kb discovery logic is cut,
because #7400 tracks that. Collapsing the four runs into one timestamp is cut, because it buys no
property.

**Process note:** Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed). This is a MINIMAL, mechanical plan. The Phase 1 research subagents and
functional-discovery were not spawned; every finding above comes from direct greps, dry runs and
`gh` reads. Domain Review, Observability, IaC, Encryption, ADR/C4 and Guard Contract all have no
trigger, since nothing outside `knowledge-base/project/` changes.

## Implementation

1. From the worktree root, run `archive-kb.sh` once per slug. Its path is
   `plugins/soleur/skills/archive-kb/scripts/archive-kb.sh`.

   ```bash
   S=plugins/soleur/skills/archive-kb/scripts/archive-kb.sh
   for s in one-shot-8710-pin-redeploy-plan-only-gate fix-pin-redeploy-gate-keys-on-apply-step \
            one-shot-git-data-dirty-journal-dm-snapshot fix-git-data-plaintext-dirty-journal-dm-snapshot; do
     bash "$S" "$s"; done
   ```

   The per-run `WARNING ... NO plan` / `NO spec` lines are expected, because the sibling slug's run
   covers the other half. Each run must report `Archived 1 artifact(s)`.
2. Commit with the message `chore(archive-kb): archive #8710 pin-redeploy and #5274 dirty-journal KB artifacts`.
3. Run the checks in Acceptance Criteria.
4. Handle the out-of-repo pointers:
   - Comment on #8776 with the new archived path of `decision-challenges.md`.
   - File the missing DC-1 `action-required` issue for PR #8711. Title:
     `Decision challenges for PR #8711 (git-data dirty journal): adopted-LUKS replace arm in the rung-2 rehearsal`.
     The body carries DC-1's direction, addition, cost, and how to cut it, plus a `Source:` line
     with the archived path.
5. Set the PR #8842 body. It must contain `Ref #5274` and must **not** contain `Closes #5274`, `Fixes #5274` or
   `Resolves #5274`. Also reference #8755, #8711 and #8776, and the new DC-1 issue.

## User-Brand Impact

**If this lands broken, the user experiences:** nothing user-facing. The worst case is a stale
in-repo pointer to a moved KB file, which an agent resolves with `git log --follow`.
**If this leaks, the user's data / workflow / money is exposed via:** no vector. The change is renames
inside `knowledge-base/project/` of already-public planning records.
**Brand-survival threshold:** none

- threshold: none, reason: rename-only move of already-merged planning artifacts inside knowledge-base/project/, no code, config, or data path touched.

## Acceptance Criteria

- [ ] AC1: `git diff --name-status -M origin/main...HEAD` shows exactly 8 `R100` renames. The two
      plans go into `knowledge-base/project/plans/archive/<ts>-<name>`, and the six spec files go
      into `knowledge-base/project/specs/archive/<ts>-feat-<slug>/`. The only other entries allowed
      are this PR's own pipeline artifacts: this plan file and
      `knowledge-base/project/specs/feat-one-shot-archive-8710-5274-plans/*`
      (tasks.md, session-state.md, decision-challenges.md).
- [ ] AC2: `test ! -e` succeeds for all 4 source paths, and this command prints `8` (it printed
      `0` at plan time):
      `git ls-files 'knowledge-base/project/plans/archive/*-2026-09-24-fix-pin-redeploy-gate-keys-on-apply-step-plan.md' 'knowledge-base/project/plans/archive/*-2026-09-24-fix-git-data-plaintext-dirty-journal-dm-snapshot-plan.md' 'knowledge-base/project/specs/archive/*-feat-one-shot-8710-pin-redeploy-plan-only-gate/*' 'knowledge-base/project/specs/archive/*-feat-one-shot-git-data-dirty-journal-dm-snapshot/*' | wc -l`.
      The pattern names each basename exactly, because the #8710 plan's basename contains no `8710`.
- [ ] AC3: `plans/2026-09-22-feat-git-data-cutover-real-modes-plan.md` and
      `specs/feat-one-shot-8211-git-data-cutover-real-modes/` are still at their live paths.
- [ ] AC4: The inbound-reference sweep in Research Insights, run on the final tree, returns only the
      preflight-discoverability-test comment. Add two more exclusions to the sweep for this PR's own
      migration records, which must cite the old paths:
      `':!knowledge-base/project/plans/2026-09-25-chore-archive-8710-5274-kb-artifacts-plan.md'`
      and `':!knowledge-base/project/specs/feat-one-shot-archive-8710-5274-plans/**'`.
      The moved self-references are now under `archive/` and are excluded already.
- [ ] AC5: `cd plugins/soleur && bun test test/preflight-discoverability-test.test.ts -t G1` passes (count stays 29).
- [ ] AC6: The `bash scripts/kb-drift-walker.sh | jq -c .counts` values are ≤ 128 broken links and
      ≤ 120 broken anchors.
- [ ] AC7: #8776 has a comment with the archived path, and a DC-1 `action-required` issue for PR #8711 exists.
- [ ] AC8: The PR body contains `Ref #5274` and does not match `(Closes|Fixes|Resolves) #5274`.
      Afterwards, `gh issue view 5274 --json state` is still `OPEN`.
- [ ] AC9 (pre-merge): Every required check reports `pass` **by name** on the exact head SHA.
      Check it with `gh pr view 8842 --json headRefOid,statusCheckRollup`: the SHA the rollup is
      reported against must equal `headRefOid`, and no required context may be pending or absent.
      If `main` moves and a merge is needed, resolve any `PROMOTED_FILES` conflict as a union, then
      re-verify on the new head SHA.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected. This is a rename-only KB housekeeping change.

## Open Code-Review Overlap

None.

## Sharp Edges

- A diff-scope AC must list the files the pipeline writes (plan-sharp-edges.md, #8207), so AC1
  allows this PR's own `specs/feat-one-shot-archive-8710-5274-plans/` artifacts. Without that
  allowance, `soleur:work` would tick AC1 while it is false.
- Do not run `archive-kb.sh` without a slug on this branch. It would derive
  `one-shot-archive-8710-5274-plans` and archive **this PR's own** spec dir.
- A plan whose `## User-Brand Impact` section is empty or has no threshold fails deepen-plan
  Phase 4.6. This one declares `none` with a reason.
