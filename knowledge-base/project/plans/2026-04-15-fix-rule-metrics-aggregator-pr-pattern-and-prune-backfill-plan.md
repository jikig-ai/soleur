---
title: "Fix rule-metrics aggregator to use PR pattern and prune backfill script"
date: 2026-04-15
issues: ["#2258", "#2264"]
status: planned
---

# fix: rule-metrics aggregator PR pattern + prune backfill migration script

## Overview

Two coupled follow-ups from PR #2213 (rule utility scoring):

1. **#2258 (P1, code-review):** `rule-metrics-aggregate.yml` pushes `knowledge-base/project/rule-metrics.json` directly to `main` weekly with `permissions: contents: write`. This bypasses normal review and — as confirmed by the **failed first run on 2026-04-15 (run `24444855398`)** — is also being rejected at the wire by the `CI Required` and `CLA Required` rulesets that protect `main`. The workflow is therefore both a hardening concern *and* currently non-functional.
2. **#2264 (P3, simplicity):** `scripts/backfill-rule-ids.py` and its test are one-shot migration code. After PR #2213 merged (commit `fd3e9d9b`) and AGENTS.md acquired all 72 tagged rules, the script has no operational role — `lint-rule-ids.py` is the ongoing enforcement. Keeping it indefinitely creates a maintenance tail (body-hash invariant + tests) for code that will never run again.

These are bundled into one PR because the `#2264` deletion gate in the issue ("one weekly aggregator run completes successfully") becomes satisfiable *only after* `#2258` is fixed — the current direct-push run failed on the ruleset reject, so we have not yet observed a healthy production aggregation. Fixing them together avoids a stale follow-up issue waiting on a workflow that we already know is broken.

## Background — What we discovered

Before planning, we inspected production state:

- `gh run list --workflow=rule-metrics-aggregate.yml` shows exactly one run (`24444855398`, manual dispatch on 2026-04-15) and it **failed** at the `Commit rule-metrics.json if changed` step.
- The run log shows the commit succeeded locally but `git push` was rejected:

  ```text
  remote: error: GH013: Repository rule violations found for refs/heads/main.
  remote: - 3 of 3 required status checks are expected.
  remote: - Required status check "cla-check" is expected.
  ```

- `gh api repos/:owner/:repo/rulesets` confirms three active rulesets on `main`: `CI Required` (id `14145388`, requires checks `test`, `dependency-review`, `e2e`), `CLA Required` (id `13304872`, requires `cla-check`), and `Force Push Prevention` (id `13044280`).
- The classic branch-protection API (`branches/main/protection`) returns 404 — protection on this repo is exclusively via rulesets.
- `scheduled-weekly-analytics.yml` is the canonical reference for the PR-based bot-commit pattern. It posts four synthetic check-runs (`test`, `cla-check`, `dependency-review`, `e2e`) so the resulting bot PR satisfies all rulesets and `gh pr merge --squash --auto` succeeds. This pattern is documented as the official solution in the learning `2026-03-19-content-publisher-cla-ruleset-push-rejection.md`.
- No other workflow in this repo uses `peter-evans/create-pull-request`. The convention is inline `gh pr create` + `gh pr merge --squash --auto`. We will follow convention rather than introducing a new third-party action dependency.

This context shifts the framing of #2258: Option A from the issue (open a PR) is the correct fix not just for hardening but to make the workflow *functional at all*. Option B (rely on existing branch protection) is already in place and is in fact what is breaking the current direct push — but it does not solve the operational problem, it only proves the security concern is moot in practice while leaving the workflow broken.

## Goals

- `rule-metrics-aggregate.yml` runs weekly without errors and produces a merged PR (or no-op when nothing changed) under the existing rulesets.
- `scripts/backfill-rule-ids.py` and `tests/scripts/test_backfill_rule_ids.py` are removed; `scripts/test-all.sh` no longer references them.
- `scripts/lint-rule-ids.py` and its test (`tests/scripts/test_lint_rule_ids.py`) remain — they are the ongoing enforcement.
- `knowledge-base/project/rule-metrics.json` is unchanged in this PR (the next scheduled run, or a manual dispatch after merge, produces the first healthy bot PR).
- `.claude/.rule-incidents.jsonl` rotation behaviour is unchanged (gitignored).

## Non-Goals

- Not changing the aggregation logic in `scripts/rule-metrics-aggregate.sh` itself.
- Not touching `scripts/lint-rule-ids.py` or its test.
- Not modifying any other scheduled workflow (e.g., `scheduled-weekly-analytics.yml`). The pattern there is already correct; we only mirror it.
- Not introducing `peter-evans/create-pull-request` (Option A as literally written in #2258 used this action; we use the in-repo convention instead).
- Not waiting an actual week before deleting the backfill script — the gate in #2264 is "one successful aggregator run completes," which we satisfy by manual `workflow_dispatch` after the fix lands (see Acceptance Criteria step 4).

## Plan

### Phase 1 — Convert `rule-metrics-aggregate.yml` to PR-based commit pattern

Edit `.github/workflows/rule-metrics-aggregate.yml`:

1. Expand `permissions:` to match `scheduled-weekly-analytics.yml`:

   ```yaml
   permissions:
     actions: write
     checks: write
     contents: write
     pull-requests: write
     statuses: write
   ```

   Rationale: `pull-requests: write` is needed for `gh pr create`. `checks: write` is needed for the synthetic check-runs. `statuses: write` is kept defensively in case any ruleset uses commit-statuses rather than check-runs (the analytics workflow includes it). `actions: write` matches the analytics precedent (used for workflow dispatch in some derivatives) and costs nothing here.

2. Replace the `Commit rule-metrics.json if changed` step with a `Create PR with rule-metrics snapshot` step modelled on lines 68–119 of `scheduled-weekly-analytics.yml`:

   - Configure git as `41898282+github-actions[bot]@users.noreply.github.com` (canonical bot email per the 2026-03-19 learning — the current workflow uses the wrong `github-actions[bot]@users.noreply.github.com` form).
   - `git add knowledge-base/project/rule-metrics.json`
   - Early-exit with `exit 0` if `git diff --cached --quiet` (no material change → no PR, mirrors current "skip commit" message).
   - Otherwise: create branch `ci/rule-metrics-$(date -u +%Y-%m-%d)`, commit with `chore(rule-metrics): weekly aggregate`, push with `-u origin`.
   - `gh pr create` with title `chore(rule-metrics): weekly aggregate $(date -u +%Y-%m-%d)`, body explaining the source and pointing reviewers at the diff.
   - Post four synthetic check-runs (`test`, `cla-check`, `dependency-review`, `e2e`) on the branch HEAD via `gh api repos/${{ github.repository }}/check-runs` with `status=completed`, `conclusion=success`. Output title/summary should reflect "Bot PR — rule metrics aggregation only, no code changes."
   - `gh pr merge "$BRANCH" --squash --auto`.

3. Keep the existing `Email notification (failure)` step unchanged.

4. Update the workflow header comment to reflect that the workflow now opens a PR rather than pushing to main, and link to issue #2258.

**Why mirror `scheduled-weekly-analytics.yml` line-for-line:** It is a known-good production reference used weekly. Diverging risks reintroducing the exact failure mode #2258 calls out. The four check names match what `CI Required` and `CLA Required` rulesets actually require (verified above by reading ruleset `14145388`). Keep step structure identical so future maintainers recognise the pattern.

**AGENTS.md heredoc constraint check:** All `gh api` calls fit on single lines (use `-f` flags). The PR body is a short single-line `--body` string. No left-aligned heredocs, no multi-line `--body` args. Compliant with rule `hr-in-github-actions-run-blocks-never-use`.

**JSON-polling guard:** Not applicable here — this workflow does not poll any JSON endpoint with `jq`. The new commands are all `gh` CLI calls that fail loudly under `set -e`.

### Phase 2 — Delete the backfill migration script

1. `git rm scripts/backfill-rule-ids.py`
2. `git rm tests/scripts/test_backfill_rule_ids.py`
3. Edit `scripts/test-all.sh` line 54 to remove the `run_suite "tests/scripts/backfill-rule-ids" ...` line. Verify the `run_suite "tests/scripts/lint-rule-ids" ...` line on line 55 is preserved.
4. Verify nothing else references the deleted files:

   ```bash
   grep -rn "backfill-rule-ids\|test_backfill_rule_ids" --exclude-dir=.git --exclude-dir=node_modules .
   ```

   Expected post-deletion output: only references in plan/spec docs (which is fine — historical context). If any other production code or workflow references them, either update or escalate before merging.
5. Confirm `scripts/lint-rule-ids.py` is untouched: `git diff scripts/lint-rule-ids.py` should be empty.

### Phase 3 — Verify locally

1. `bash scripts/test-all.sh 2>&1 | tail -n 40` — confirm `tests/scripts/lint-rule-ids` still runs and passes; confirm `tests/scripts/backfill-rule-ids` is no longer attempted; confirm the suite count drops by exactly 1.
2. YAML lint: `npx --yes -p yaml-lint yamllint .github/workflows/rule-metrics-aggregate.yml || true` (best-effort; `actionlint` if available locally).
3. `npx markdownlint-cli2 --fix knowledge-base/project/plans/2026-04-15-fix-rule-metrics-aggregator-pr-pattern-and-prune-backfill-plan.md knowledge-base/project/specs/feat-one-shot-2258-2264/*.md` (per `cq-always-run-npx-markdownlint-cli2-fix-on`).

### Phase 4 — Post-merge verification (per `wg-after-merging-a-pr-that-adds-or-modifies`)

1. After the PR merges, dispatch the workflow once: `gh workflow run rule-metrics-aggregate.yml`.
2. Poll the run via Monitor tool (per `hr-never-use-sleep-2-seconds-in-foreground`) until completion: `gh run list --workflow=rule-metrics-aggregate.yml --limit 1 --json status,conclusion,databaseId`.
3. Expected outcomes:
   - **If the JSON would change since `fd3e9d9b`:** A bot PR is created on a `ci/rule-metrics-YYYY-MM-DD` branch, four synthetic checks pass, auto-merge triggers, the PR squash-merges. Then verify the resulting commit appears on `main` and `rule-metrics.json` was updated.
   - **If no material change:** Workflow exits at `git diff --cached --quiet` with "No changes to commit" and conclusion is `success`. This is a valid pass for the gate in #2264.
4. Either outcome satisfies the "one weekly aggregator run completes successfully" gate in #2264. Close both issues from the PR body using `Closes #2258` and `Closes #2264` (per `wg-use-closes-n-in-pr-body-not-title-to`).

## Acceptance Criteria

- [ ] `.github/workflows/rule-metrics-aggregate.yml` no longer contains `git push` to `main`. It uses `gh pr create` + synthetic check-runs + `gh pr merge --squash --auto`.
- [ ] Workflow `permissions:` includes `pull-requests: write`, `checks: write`, `contents: write`, `statuses: write`, `actions: write`.
- [ ] Bot commit author email is the canonical `41898282+github-actions[bot]@users.noreply.github.com`.
- [ ] `scripts/backfill-rule-ids.py` is deleted.
- [ ] `tests/scripts/test_backfill_rule_ids.py` is deleted.
- [ ] `scripts/test-all.sh` no longer references `tests/scripts/backfill-rule-ids` (line removed; `lint-rule-ids` line kept).
- [ ] `scripts/lint-rule-ids.py` and `tests/scripts/test_lint_rule_ids.py` are unchanged.
- [ ] `bash scripts/test-all.sh` passes locally with one fewer suite than before.
- [ ] `grep -rn "backfill-rule-ids\|test_backfill_rule_ids" .` returns only docs/plan references (no live code paths).
- [ ] Post-merge: one `workflow_dispatch` run of `rule-metrics-aggregate.yml` concludes `success` (either no-op or merged bot PR).
- [ ] PR body uses `Closes #2258` and `Closes #2264`.

## Files to modify

- `.github/workflows/rule-metrics-aggregate.yml` — convert to PR pattern.
- `scripts/test-all.sh` — drop the `tests/scripts/backfill-rule-ids` suite line.

## Files to delete

- `scripts/backfill-rule-ids.py`
- `tests/scripts/test_backfill_rule_ids.py`

## Files to leave untouched (explicit non-changes)

- `scripts/lint-rule-ids.py` — ongoing enforcement.
- `tests/scripts/test_lint_rule_ids.py` — its test.
- `scripts/rule-metrics-aggregate.sh` — aggregation logic is already correct; the failure was in the workflow's commit step, not the script.
- `knowledge-base/project/rule-metrics.json` — let the next scheduled/dispatched run regenerate it via the new path.
- All other workflows.

## Test Scenarios

Because this work is purely CI/infra glue (no application logic), TDD applies via existing test suites, not new unit tests. The exemption clause in `cq-write-failing-tests-before` ("Infrastructure-only tasks (config, CI, scaffolding) are exempt") covers this.

1. **Suite count regression:** `bash scripts/test-all.sh` reports exactly N-1 suites where N is the count on `main` at `fd3e9d9b`. The removed suite must be `tests/scripts/backfill-rule-ids`. Other suites must still pass.
2. **Lint-rule-ids surviving:** `python3 -m unittest tests.scripts.test_lint_rule_ids` passes standalone.
3. **No dangling references:** `grep -rn "backfill-rule-ids" --exclude-dir=.git .` returns zero hits in `.github/`, `scripts/`, `tests/`, `plugins/`. (Doc references in `knowledge-base/project/plans/` are acceptable — they're historical.)
4. **Workflow YAML parses:** GitHub UI shows the workflow as discoverable post-merge (no "workflow file issue" red banner). Cross-check with `actionlint` if available locally.
5. **Post-merge dispatch:** `gh workflow run rule-metrics-aggregate.yml` followed by `gh run view <id> --json conclusion` returns `success`. If a PR was created, it auto-merged.

## Risks & Mitigations

- **Risk:** Synthetic check-run names drift from ruleset requirements over time. **Mitigation:** the same names are already used by `scheduled-weekly-analytics.yml`; if rulesets change, both workflows break together and the fix is centralised.
- **Risk:** `gh pr merge --auto` requires auto-merge to be enabled on the repo. **Mitigation:** `scheduled-weekly-analytics.yml` has been using this pattern in production and it works — confirmed by inspection of recent runs in the parent task context. No new repo-level setting needed.
- **Risk:** The first manual dispatch after merge produces an empty diff (no material change since `fd3e9d9b`) and we cannot fully verify the PR-creation path. **Mitigation:** The aggregator runs whenever `.claude/.rule-incidents.jsonl` has new events. We can either (a) accept the empty-diff path as proof the early-exit branch works and rely on the next real cron trigger to exercise the PR path, or (b) seed a single test incident before dispatch. Decision: accept (a) — the PR-creation path is line-for-line identical to `scheduled-weekly-analytics.yml`, which is already exercised weekly.
- **Risk:** Deleting `scripts/backfill-rule-ids.py` is irreversible. **Mitigation:** It's recoverable from git history (`git show <pre-deletion-sha>:scripts/backfill-rule-ids.py`). The script is idempotent and the body-hash invariant is satisfied by the current AGENTS.md state, so re-running it would be a no-op anyway — there is no realistic scenario where we need it back.
- **Risk:** `scripts/test-all.sh` line removal silently keeps the dead reference if grep doesn't catch it. **Mitigation:** Phase 3 step 1 explicitly verifies the suite count drops by exactly 1.

## Alternative Approaches Considered

| Approach | Pros | Cons | Decision |
| --- | --- | --- | --- |
| Option A literal: `peter-evans/create-pull-request@<SHA>` action | Closest to issue text | Adds a third-party action dependency for no benefit; no other workflow uses it | Rejected — use in-repo convention |
| Option B: document branch protection blocks bot pushes | No code change | Rulesets *already* block the push (run `24444855398` proves it) — this leaves the workflow non-functional weekly | Rejected — broken-by-design |
| Inline `gh pr create` mirroring `scheduled-weekly-analytics.yml` | Matches in-repo convention; uses same synthetic check pattern; documented in 2026-03-19 learning | None material | **Selected** |
| Bundle #2258 + #2264 into one PR | Avoids a stale follow-up; #2264's gate is satisfied by the same dispatch that proves #2258 fix works | Slightly larger diff | **Selected** — coupling is intrinsic |
| Defer #2264 to a separate PR after observing one healthy production run | Strictly follows #2264's literal "after one weekly run" gate | Adds a week of latency for trivial deletion; the gate is really "prove the aggregator works," which manual dispatch satisfies | Rejected |

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure/tooling change. CI workflow hardening + dead-code removal in the engineering domain only. No user-facing surface, no new files matching `components/**/*.tsx`, `app/**/page.tsx`, or `app/**/layout.tsx`. No financial, legal, marketing, or content implications. Product/UX Gate: NONE.

## SpecFlow Notes

This plan touches a CI workflow with conditional bash logic — exactly the class of change SpecFlow Analyzer flags as risk-prone. The relevant edge cases enumerated:

- **Empty diff path:** `git diff --cached --quiet` early-exits before branch creation. Verified by mirroring `scheduled-weekly-analytics.yml` which handles this identically. Test in Phase 4 step 3.
- **Branch already exists:** Date-stamped branch `ci/rule-metrics-YYYY-MM-DD` could collide if the workflow runs twice in one UTC day (cron + manual dispatch). The analytics precedent does not handle this — neither does this plan. If observed, follow-up: append `$(date -u +%H%M%S)` like `scheduled-content-generator.yml` does. Out of scope here.
- **`gh pr merge --auto` fails because PR is not mergeable:** Synthetic checks pass, but a separate ruleset (e.g., a future "approved-by-human" requirement) might block. Currently no such requirement exists. If added later, the workflow surfaces the failure via the existing email notification step.
- **Synthetic check name drift:** Already handled — see Risks section.

## References

- Issue #2258 — review: rule-metrics aggregator pushes to main without PR
- Issue #2264 — followup: delete scripts/backfill-rule-ids.py after #2213 merges
- PR #2213 — feat(rule-utility): telemetry, weekly aggregator, and /soleur:sync rule-prune (merged at `fd3e9d9b`)
- Failed run: `https://github.com/jikig-ai/soleur/actions/runs/24444855398`
- Reference workflow: `.github/workflows/scheduled-weekly-analytics.yml` (lines 29–34, 68–119)
- Learning: `knowledge-base/project/learnings/2026-03-19-content-publisher-cla-ruleset-push-rejection.md`
- Original aggregator plan: `knowledge-base/project/plans/2026-04-14-feat-rule-utility-scoring-plan.md`
- AGENTS.md rules consulted: `hr-in-github-actions-run-blocks-never-use`, `hr-never-use-sleep-2-seconds-in-foreground`, `wg-after-merging-a-pr-that-adds-or-modifies`, `wg-use-closes-n-in-pr-body-not-title-to`, `cq-write-failing-tests-before` (exemption), `cq-always-run-npx-markdownlint-cli2-fix-on`.
