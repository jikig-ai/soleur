---
title: "Tasks — three structurally-unfailable gates (#6721, #6723, #6724)"
branch: feat-one-shot-6721-6723-6724-gitleaks-scan-gaps-ship-signal
lane: cross-domain
plan: knowledge-base/project/plans/2026-07-19-fix-three-structurally-unfailable-gates-plan.md
---

# Tasks

Derived from `2026-07-19-fix-three-structurally-unfailable-gates-plan.md`.

**Ordering is load-bearing.** Within each issue, the mutation proof lands RED before the fix, and every contract change precedes its consumer.

## Phase 0 — Preconditions

- [x] 0.1 Confirm `gitleaks version` prints `8.24.2`.
- [x] 0.2 Confirm current branch is not `main`.
- [x] 0.3 Re-run baseline P0.1 (#6723 bypass live → rc=0) and reconcile if it diverges.
- [x] 0.4 Re-run baseline P0.2 / P0.3 (#6724 Signal 1 vacuous → non-empty; branch-scoped → empty).
- [x] 0.5 Capture a pre-change working-tree finding baseline for the AC12 comparison.

## Phase 1 — #6721 merge-commit coverage

- [x] 1.1 Create `plugins/soleur/test/gitleaks-merge-commit.test.sh`: throwaway repo, genuine 2-parent merge, synthesized DSN present in neither parent.
- [x] 1.1.1 Assert `--no-merges HEAD` → rc=0 (the bug).
- [x] 1.1.2 Assert `-m HEAD` → rc=1 (the fix).
- [x] 1.1.3 Assert `--cc HEAD` → rc=0 explicitly (the silent-no-op trap).
- [x] 1.1.4 Follow the sibling convention: `command -v gitleaks` skip guard, `mktemp -d` + `trap` cleanup, runtime-assembled DSN literals.
- [x] 1.2 Add `--log-opts="-m --all"` to the weekly-cron scan step in `.github/workflows/secret-scan.yml`.
- [x] 1.2.1 Verify the bare `-m` form (without `--all`) appears nowhere — it silently narrows breadth to `HEAD`.
- [x] 1.3 Add a `gitleaks dir .` step to the cron job.
- [x] 1.4 Correct the `push:main` step comment that currently describes #6721 as unfixed; record the `--cc` trap there.
- [x] 1.5 Close the PR-time window (deepen finding, not in the issue): the PR / merge_group jobs also miss conflict-resolution secrets (measured rc=0).
- [x] 1.5.1 Build the `-m`-coupling fixture deliberately (clean merge of a main commit carrying a known finding; scan the PR range both ways). The first attempt was INCONCLUSIVE — do not record it as "no coupling".
- [x] 1.5.2 Choose `gitleaks dir` (default, understood failure mode) or `-m` (only if 1.5.1 clears coupling); add the step to the PR and merge_group jobs.
- [x] 1.5.3 Record the 1.5.1 result — including "inconclusive" — in the PR body (AC6c).
- [x] 1.6 Run mutation proof AC2: drop `-m`, confirm the suite goes RED, capture output, restore.
- [x] 1.7 Run mutation proof AC6b: synthetic PR-shape range spanning a conflict-resolution secret flips rc=0 → rc=1 under the shipped PR job config.

## Phase 2 — #6723 DSN allowlist bypass

- [x] 2.1 Extend `plugins/soleur/test/gitleaks-rules.test.sh` T7 with 4 multi-`@` rows (`multi-at-password`, `multi-at-user`, `multi-at-secret`, `multi-at-redacted`).
- [x] 2.1.1 Confirm the new rows are RED against the current config before applying the fix.
- [x] 2.1.2 Add the THREE P0-1 regression rows (`postgres://user:<admin:R3alPassw0rd@prod.db.internal>@x.com` shape). These are detected TODAY and silenced by the issue's unhardened candidate — they must be RED against that candidate and GREEN against the hardened form.
- [x] 2.2 Widen the rule regex password class to span to the last `@`.
- [x] 2.3 Anchor the allowlist `regexes` entry with `^`/`$` **AND harden both bracket branches to `<[^>@:]+>`**. Do NOT ship the issue's `<[^>]+>` form — it regresses detection.
- [x] 2.3.1 Confirm T8 still reports exactly one `regexes` entry (2 triple-quote runs) — modify the existing entry, never add a second.
- [x] 2.4 Add the **anchored** `^plugins/soleur/skills/review/SKILL\.md$` path-allowlist entry. The leading `^` is load-bearing — unanchored, any parent directory launders a real DSN.
- [x] 2.4.2 Add T10: block-scoped `paths` arity guard pinned to the shipped entry count (nothing currently guards `paths`).
- [x] 2.4.3 Move T8/T9/T10 ABOVE the `command -v gitleaks` skip guard (pure config-text assertions).
- [x] 2.4.4 Add the `Allowlist-Widened-By: <name>` trailer to the `.gitleaks.toml` commit; expect `allowlist-diff` red + ack path.
- [x] 2.4.1 Record rationale + compensating controls in-config per the file's existing comment convention.
- [x] 2.5 Verify AC11: full main-ancestry scan under the shipped config returns rc=0.
- [x] 2.6 Verify AC12: working-tree scan introduces no finding absent from the 0.5 baseline.
- [x] 2.7 Add T9 anchor-mutation guard asserting both `^` and `$` are present.
- [x] 2.8 Run mutation proofs AC8 (revert regex → multi-`@` rows RED) and AC9 (remove either anchor → T9 RED); capture output, restore.

## Phase 3 — #6724 review-evidence signals

- [x] 3.1 **Contract first:** create `plugins/soleur/skills/review/scripts/emit-review-trailer.sh` doing `git commit --allow-empty` with the `Reviewed-By-Soleur:` trailer, and INVOKE it from a step that runs in BOTH pipeline and direct mode. Do not describe a `git commit` line in prose — the existing prose convention has measured zero compliance.
- [x] 3.1.0 **P0:** without `--allow-empty`, a zero-finding review makes no commit → no trailer → the gate DENIES a genuinely-reviewed branch with no escape hatch. Prove with AC17a.
- [x] 3.1.1 Enumerate the in-flight-branch impact set for the trailer (AC18) — do not assume it is empty; record the result for the PR body.
- [x] 3.2 Branch-scope Signal 1 in `plugins/soleur/skills/ship/SKILL.md` Phase 1.5 Step 1, using `xargs -r`.
- [x] 3.2.1 Verify the Phase 5.5 pointer text still accurately describes the changed Phase 1.5 signals.
- [x] 3.3 Branch-scope Check 1 in `.claude/hooks/pre-merge-rebase.sh` (the actual `deny` gate — not named in the issue).
- [x] 3.3.1 Branch-scope Check 1 in `.openhands/hooks/pre-merge-rebase.sh` — THIRD copy, byte-identical, named by neither the issue nor plan v1.
- [x] 3.3.2 **P0:** move `git fetch origin main` ABOVE the review-evidence gate, and use the commit-scoped `git log origin/main..HEAD --name-only -- todos/` form — otherwise the hook's own auto-sync (it merges origin/main in and pushes) makes the gate re-vacuous on the second merge attempt.
- [x] 3.3.3 Give `init_git_repo` an optional bare `origin` with `main` pushed; fix T2 (currently has no remote and will fail on rule_id mismatch after scoping).
- [x] 3.3.4 Seed the vacuity case's `todos/` on MAIN pre-fork, never on the feature branch.
- [x] 3.3.5 Update `test/pre-merge-rebase.test.ts` (9 `addReviewEvidence` sites).
- [x] 3.4 Converge the drifted Signal 2 regex across both copies (trailer + retained legacy alternatives).
- [x] 3.5 Update `todos/` seeding in `.claude/hooks/pre-merge-rebase.test.sh` and `pre-merge-rebase-headless.test.sh` so seeds still mean "review ran" under branch scoping.
- [x] 3.6 Add the vacuity regression case: fresh branch off `origin/main`, real-shaped `todos/`, no review → hook MUST deny.
- [x] 3.7 Run mutation proof AC14: revert Check 1 to the repo-global grep, confirm 3.6 goes RED, capture output, restore.
- [x] 3.8 Verify AC16: no occurrence of the unscoped `grep -rl "code-review" todos/` remains in either file.

## Phase 4 — Documentation

Update `knowledge-base/engineering/operations/secret-scanning.md` by content anchor (not line number):

- [x] 4.1 `## Ref scope per event` table — update every changed row; add the new `gitleaks dir` steps as rows.
- [x] 4.2 `**Blind spot: merge-commit-exclusive content.**` — rewrite as closed; replace with the `--cc` trap + measured rc table.
- [x] 4.3 `### Placeholder-regex allowlist — database-url-with-password` — anchored `^…$` semantics; whole-match not contains-a-placeholder.
- [x] 4.4 `### Allowlist semantics — read this carefully` — add the `review/SKILL.md` path carve-out + rationale.
- [x] 4.5 `## Author-Side Pitfalls` — add the `--cc` trap and "a line waiver cannot clear a history finding".

## Phase 5 — Verification & exit

- [x] 5.1 `bash plugins/soleur/test/gitleaks-rules.test.sh` exits 0.
- [x] 5.2 `bash plugins/soleur/test/gitleaks-merge-commit.test.sh` exits 0.
- [x] 5.3 `bash .claude/hooks/pre-merge-rebase.test.sh` exits 0.
- [x] 5.4 `bash .claude/hooks/pre-merge-rebase-headless.test.sh` exits 0.
- [x] 5.5 Full repo test suite exit gate.
- [ ] 5.6 Paste every mutation proof's RED output into the PR body (AC21) — an unexercised mutation claim is the defect class being fixed.
- [ ] 5.7 PR body states the #6721 direction-1+2 divergence with measured costs (AC19).
- [ ] 5.8 PR body records the #6724 scope extension to `pre-merge-rebase.sh` (AC20).
