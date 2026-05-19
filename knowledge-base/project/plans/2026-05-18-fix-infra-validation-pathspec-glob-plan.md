---
title: "fix(ci): infra-validation pathspec glob silently skips nested infra-only diffs"
date: 2026-05-18
type: bug-fix
classification: ci-ops
lane: single-domain
status: planned
branch: feat-one-shot-4012-infra-pathspec
related_workflows:
  - .github/workflows/infra-validation.yml
related_issues: [4012]
related_evidence_prs: [3985, 4002, 4003]
sentry_alert: none
requires_cpo_signoff: false
---

# fix(ci): `.github/workflows/infra-validation.yml` pathspec silently skips nested infra-only diffs

## Enhancement Summary

**Deepened on:** 2026-05-18
**Plan author lens:** CI-ops single-domain, threshold=none with no sensitive-path overlap (the file under change — `.github/workflows/infra-validation.yml` — matches the canonical sensitive-path regex group `\.github/workflows/.*infra-validation.*\.ya?ml$`; scope-out below is non-applicable because the edit is to detection logic, no IaC apply path / secret / data surface is touched; `requires_cpo_signoff: false`).
**Research applied:** live `git diff` reproduction on commit `7e6f6726` (verified on `main`), live `gh pr view 3985 / 4002 / 4003` state checks (all MERGED 2026-05-18), `scripts/test-all.sh` walkthrough to identify the ONLY test directory it auto-discovers (`plugins/soleur/test/*.test.sh`), `ls plugins/soleur/test/auto-close-scanner.test.sh` for the canonical test-file template, `test-helpers.sh` discovery, AGENTS.md grep for cited rule IDs (`hr-when-a-plan-specifies-relative-paths-e-g` active, `wg-use-closes-n-in-pr-body-not-title-to` active — neither retired), learning `2026-03-21-lefthook-gobwas-glob-double-star.md` (sibling failure-mode class), learning `2026-04-28-plan-globs-must-be-verified-against-repo-structure.md`, learning `2026-05-09-pathspec-regex-translation-and-classifier-piggyback.md` (pathspec→regex equivalence verification — directly applicable to this plan's AC1+AC5), Quality Checks bullet on pathspec→regex translation verification.

### Key Improvements over the initial draft

1. **AC6 was wrong about `bun run test` covering the new test.** Reading `scripts/test-all.sh` directly: the file ONLY auto-walks `plugins/soleur/test/*.test.sh` via `for f in plugins/soleur/test/*.test.sh; do … run_suite "$f" bash "$f"; done`. It does NOT auto-discover `scripts/*.test.sh`, `apps/web-platform/infra/*.test.sh`, or `.github/workflows/*.test.sh`. **Plan response:** locked the test-file location to `plugins/soleur/test/infra-validation-detect.test.sh` — the only path that gets the `bun run test` wiring for free. AC6 verification step rewritten to `bash plugins/soleur/test/infra-validation-detect.test.sh` AND `bun run test` (must include the new suite). Phase 0.4's two-candidate choice collapses to one — co-location next to the workflow loses CI wiring.
2. **AC9 was post-merge-vague.** Original draft asked to `workflow_dispatch` against PR #4003. PR #4003 is MERGED (2026-05-18T15:22:56Z) — there is no open PR branch to dispatch against. **Plan response:** AC9 rewritten as "verify on the NEXT infra-touching PR opened against `main`" + an explicit `workflow_dispatch` alternative against `main` (the dispatch branch at line 49 uses `find`, not `git diff`, so it would not exercise the fix — explicit acknowledgement that the actual end-to-end test requires a live PR diff). Added a one-line `gh run list --workflow=infra-validation.yml --limit 5 --json status,conclusion,event,headBranch` query as the verification probe.
3. **Test-helpers leverage discovered.** `plugins/soleur/test/test-helpers.sh` provides `assert_file_exists` and (per the auto-close-scanner template) a complete shell-assertion vocabulary. Phase 1.1 RED now prescribes `source "$SCRIPT_DIR/test-helpers.sh"` to inherit the project's assertion conventions instead of inventing test assertions inline. Reduces the diff and makes the new test indistinguishable in style from its 30+ siblings.
4. **Pathspec→regex equivalence gate inherited from learning 2026-05-09-pathspec-regex-translation-and-classifier-piggyback.md.** That learning's prescription (verify equivalence with fixture inputs covering top-level, single-ancestor, AND deep-nested shapes) is the exact failure mode in scope here. Plan's AC5 fixture list (4 scenarios) is upgraded to 6 scenarios to cover the explicit three-shape matrix on BOTH `apps/<x>/infra/` and `infra/<x>/` arms — see AC5 below. Also added an explicit `diff -u <(git diff --name-only -- <new-form>) <(<grep -E pipeline> < git-diff-output)` equivalence check in Phase 1.2 GREEN so the fix path is not just "passes the synthetic test" but ALSO "matches the canonical baseline on a real commit".
5. **`grep -E ... || true` under `bash -e` semantics empirically verified.** Plan v1 noted the trap as a Sharp Edge; v2 includes the live verification: `set -e; result=$(echo -e "foo.txt\nbar.txt" | grep -E '^apps/' || true); echo "result=[$result]"; echo "exit=$?"` returns `result=[]` + `exit=0`. The `|| true` does NOT mask exit code 1 from the OUTER pipeline because the workflow step does not set `pipefail`. Validates Option B is safe in the workflow's bash context. Added the verification command verbatim to AC1.
6. **Bug class re-framed.** Issue body claimed "nested files silently missed." Reproduction shows DIRECT-CHILD files are ALSO missed by the `'apps/*/infra/'` (trailing-slash, no `**`) pathspec — git pathspec `*` does not span `/`, so the trailing slash on `apps/*/infra/` requires the path to be EXACTLY `apps/<x>/infra/<file-at-depth-0>` AND the `*` to match a single component AND the slash to be the directory-marker. In practice, `'apps/*/infra/'` with a single `*` matches NOTHING beneath `apps/*/infra/` because the trailing slash is interpreted as a directory pathspec that requires `**` to recurse. Reframing rejects the partial issue framing in favor of the codebase-confirmed reality. (This was already captured in v1's "Research Reconciliation" table; v2 promotes it to the deepen Insights for first-pass reader.)
7. **Sentry/operator visibility.** Issue body says workflow status reports `success`. Cross-checked: matrix-zero in GitHub Actions returns success when ALL upstream jobs (`detect-changes`) succeed, regardless of `if:`-skipped downstream jobs. No Sentry / alert / heartbeat surfaces this defect — by design (it is internal CI integrity, not vendor-cron heartbeat). The only operator-visible signal is the absence of `validate (apps/web-platform/infra)` in the PR's check list. Post-fix, that signal is restored. No new observability instrumentation required.

### Research Insights

**Lefthook gobwas-glob `**` semantics (learning `2026-03-21-lefthook-gobwas-glob-double-star.md`):** Documents the sibling failure mode where Lefthook's default gobwas matcher treats `**` as "1+ directories," not "0+" — opposite of git pathspec where `**` (with `:(glob)` magic) DOES match 0+ directories. The two are siblings of the same class: glob semantics differ across tools, and the failure is silent zero-match. This plan adds the git-pathspec data point to the same class.

**Git pathspec semantics (verified):** Default git pathspec (no `:(glob)` prefix) treats `*` as `fnmatch` with `PATHNAME=0` — `*` matches anything INCLUDING `/`. That means `'apps/*'` matches `apps/foo/bar`. However, `'apps/*/infra/'` with the trailing `/` is interpreted as "match files in directory `apps/*/infra/`" — and `*` here is doing single-component glob (not pathname-traversal). The combined result: `'apps/*/infra/'` matches only when the file path equals `apps/<something>/infra/<file>` AND further nesting is undefined behavior across git versions. `:(glob)apps/*/infra/**` opts into glob-magic where `**` traverses subdirectories explicitly. Empirical confirmation on `git 2.53.0` against commit `7e6f6726`: trailing-slash form returns empty; `:(glob)apps/*/infra/**` returns both expected files; `grep -E '^apps/[^/]+/infra/'` filter returns both expected files.

**Bash `-e` + `grep | … | grep -E ... || true` interaction (verified empirically):** Under `set -e` WITHOUT `set -o pipefail`, a failing component in a pipeline does NOT propagate to the outer script — only the LAST command's exit code matters. The workflow's `run:` block does not set `pipefail`. Therefore, `grep -E '<pattern>' || true` is safe: even if `grep` returns 1, the `|| true` flips it to 0, AND the downstream `sed | sort -u | jq` stages process the empty stream into `[]`. No `set -o pipefail` is set; no special handling needed beyond `|| true`. (If `pipefail` is ever added to the step, the `|| true` still works because it terminates a fresh subshell at that operator.)

**Workflow_dispatch fallback at line 49 uses bash globbing (NOT git pathspec):** `find apps/*/infra -maxdepth 0 -type d` shell-expands `apps/*/infra` at glob-time (bash glob crosses `*` differently from git pathspec — bash glob's `*` does NOT cross `/` either, BUT the entire expression is path-literal: bash expands `apps/*/infra` to `apps/cla-evidence/infra apps/web-platform/infra` correctly because `*` matches the single directory component between `apps/` and `/infra`). `find -maxdepth 0` then validates each expanded path. Works correctly today; out of scope for this PR.

**`scripts/test-all.sh` test discovery (verified):** Reads `for f in plugins/soleur/test/*.test.sh; do … done`. The runner walks ONE directory ONLY. Tests outside that directory (`scripts/lint-*.test.sh`, `apps/web-platform/infra/*.test.sh`, `.claude/hooks/*.test.sh`) are NOT auto-discovered — they run via dedicated workflows (`apps/web-platform/infra/ci-deploy.test.sh` runs in `infra-validation.yml` itself; `.claude/hooks/*.test.sh` runs in `pr-quality-guards.yml`). The new infra-validation-detect test is a SHELL test of a SHELL pipeline — colocate with siblings of the same class: `plugins/soleur/test/`.

### New Considerations Discovered

- **Plan-time SHA verification.** AC2 cites commit `7e6f6726` for replay. Verified via `git rev-parse 7e6f6726` (returns `7e6f672621d342ff3cbb2362fc71fa4109d37a6e`) AND `git merge-base --is-ancestor 7e6f6726 main` (returns 0). The commit IS on main; replay is durable.
- **PR #3985 / #4002 / #4003 are MERGED.** Plan v1's AC9 prescribed re-dispatching against PR #4003; impossible post-merge. AC9 now uses "next infra PR" as the canonical verification.
- **The `paths:` trigger at lines 13-15 is correct and out of scope** — confirmed; GitHub Actions glob `**` is fnmatch-with-FNM_PATHNAME, which matches `apps/web-platform/infra/sentry/uptime-monitors.tf`. The defect is ONLY in the git-pathspec detect-changes step.
- **No multi-surface invocation.** `grep -rn "apps/\*/infra/'" .github/` returns exactly one hit (the detect-changes step at line 53). No sibling skill, hook, workflow, or script re-uses this pathspec form. The fix is single-site.
- **No AGENTS.md rule citations in the plan body to verify against retired-rule registry.** Implicit rule references (`wg-use-closes-n-in-pr-body-not-title-to`, `hr-when-a-plan-specifies-relative-paths-e-g`) verified active.

## Summary

`.github/workflows/infra-validation.yml` line 53 enumerates changed infra directories via:

```bash
git diff --name-only "origin/${BASE_REF}...HEAD" -- 'apps/*/infra/' 'infra/' \
  | sed -E '…' | sort -u | jq -R -s -c 'split("\n") | map(select(. != ""))'
```

The pathspec `'apps/*/infra/'` (single `*`, trailing slash, no `**`) does NOT span directory separators in default git pathspec semantics. Result: the `detect-changes.outputs.directories` is `[]` for PRs that touch infra files, the gated `validate` / `plan` matrices fan out to zero jobs, and the workflow reports `success` (matrix-zero is a no-op success in GitHub Actions). The bug is silent — there is no failure signal anywhere, just absence.

**Bug reproduced** at commit `7e6f6726` (the soleur.ai uptime-alerting commit referenced by issue #4012):

```bash
$ git diff --name-only 7e6f6726^..7e6f6726 -- 'apps/*/infra/' 'infra/'
(empty)

$ git diff --name-only 7e6f6726^..7e6f6726
apps/web-platform/infra/sentry/uptime-monitors.tf
apps/web-platform/infra/uptime-alerts.tf
knowledge-base/project/plans/2026-05-18-feat-soleur-ai-uptime-alerting-plan.md
knowledge-base/project/specs/worktree-agent-accdfe82004a40a5f/session-state.md
```

Two of the four changed files live under `apps/*/infra/`. The pathspec filter returned zero. Same defect against `'infra/'` for `infra/github/` changes (one-level nesting, identical failure mode).

Three documented production hits (per issue body): PR #3985, PR #4002, PR #4003 — every recent infra-touching PR was silently skipped.

The fix is a one-line rewrite of `detect-changes`. The supporting test is a `.test.sh` fixture asserting non-empty matrix output for a synthetic nested-infra diff so this regression cannot land silently again.

## User-Brand Impact

**If this lands broken, the user experiences:** No user-facing surface — this is CI internal. The end users affected are Soleur operators reviewing infra PRs who falsely believe `terraform validate` / `terraform fmt -check` / per-app `main.test.sh` ran on their diff. The user-visible failure mode is downstream: a Terraform config with a syntax error or fmt drift, or a CLA-evidence governance assertion failure, lands on `main` and breaks `apply-*.yml` at apply-time (already happened — see issue evidence on PR #3985/#4002/#4003 where infra changes shipped with only operator-local validation).

**If this leaks, the user's [data / workflow / money] is exposed via:** Not a data leak. The exposure is operational integrity: a broken Terraform root reaches `main`, `apply-deploy-pipeline-fix.yml` / `apply-sentry-infra.yml` / `apply-github-infra.yml` fail at apply, infra drifts, and the next dependent PR's plan output is unreadable. No customer-data path is affected by this CI bug.

**Brand-survival threshold:** none — CI gate hardening on an internal observability/integrity surface. The defect class is operational decay, not user incident. (Sensitive-path scope-out: `.github/workflows/infra-validation.yml` matches the `apps/web-platform/infra/` regex weakly, but the edit is to the detection logic — not to any Terraform resource, IAM policy, schema, or auth flow. No regulated-data surface is touched.)

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1 — Detection rewrite lands.** `.github/workflows/infra-validation.yml` `detect-changes` job uses one of the two equivalent forms below (final choice decided in Phase 1 after Plan Review):
  - **Option A — `:(glob)` magic:** `git diff --name-only "origin/${BASE_REF}...HEAD" -- ':(glob)apps/*/infra/**' ':(glob)infra/*/**'`
  - **Option B — drop pathspec, filter in `grep -E`:** `git diff --name-only "origin/${BASE_REF}...HEAD" | grep -E '^(apps/[^/]+/infra|infra/[^/]+)/'`
- [ ] **AC2 — Verify on real commit.** `bash -c 'cd <worktree-root> && git diff --name-only 7e6f6726^..7e6f6726 -- <new-detection-form>'` returns at least `apps/web-platform/infra/sentry/uptime-monitors.tf` AND `apps/web-platform/infra/uptime-alerts.tf`. Capture output in the PR body's Evidence block.
- [ ] **AC3 — Workflow-dispatch branch unchanged.** Line 49's `find apps/*/infra -maxdepth 0 -type d` workflow_dispatch fallback is NOT rewritten — it operates on the live worktree (no git diff), works correctly today, is tested via `find` not pathspec. Diff scope: lines 52-57 only.
- [ ] **AC4 — Comments updated to match.** Lines 41-47 comment block updated to reflect the new detection form. The "single-ancestor directory" collapse semantics stay the same (`apps/[^/]+/infra` and `infra/[^/]+` regex anchors in the sed-collapse pipeline).
- [ ] **AC5 — Fixture test asserts non-empty matrix (six-scenario shape matrix).** A new test file at `plugins/soleur/test/infra-validation-detect.test.sh` (canonical location — `scripts/test-all.sh` auto-walks this directory only) sources `plugins/soleur/test/test-helpers.sh` and wraps the detection one-liner in a shell function `detect_infra_dirs()` that reads `stdin`. Asserts the following six scenarios per the pathspec→regex translation learning (`2026-05-09-pathspec-regex-translation-and-classifier-piggyback.md`) three-shape coverage:
  1. **`apps/<x>/infra/` direct child** — input `apps/web-platform/infra/uptime-alerts.tf` → matrix `["apps/web-platform/infra"]`.
  2. **`apps/<x>/infra/` single-ancestor nested** — input `apps/web-platform/infra/sentry/uptime-monitors.tf` → matrix `["apps/web-platform/infra"]`.
  3. **`apps/<x>/infra/` deep-nested** — input `apps/web-platform/infra/test-fixtures/audit-bwrap/foo.tf` → matrix `["apps/web-platform/infra"]`.
  4. **`infra/<x>/` direct child** — input `infra/github/main.tf` → matrix `["infra/github"]`.
  5. **`infra/<x>/` deep-nested** — input `infra/github/deeply/nested/foo.tf` → matrix `["infra/github"]`.
  6. **Mixed + non-infra controls** — input has both `apps/web-platform/infra/uptime-alerts.tf` AND `apps/cla-evidence/infra/main.tf` AND `infra/github/main.tf` AND non-infra controls `apps/web-platform/server/route.ts`, `knowledge-base/project/plans/foo.md` → matrix `["apps/cla-evidence/infra","apps/web-platform/infra","infra/github"]` (sorted, non-infra filtered).
  7. **Empty / zero-match** — input `apps/web-platform/server/route.ts` only → matrix `[]` (verifies the `grep || true` + downstream-collapse behavior under bash `-e`).
- [ ] **AC6 — Test wired into existing test runner.** Verify via `bun run test` (which calls `bash scripts/test-all.sh`, which `for f in plugins/soleur/test/*.test.sh; do run_suite "$f" bash "$f"; done`). Confirm the new test name appears in the test runner's stdout with `[ok] plugins/soleur/test/infra-validation-detect.test.sh`. Direct invocation `bash plugins/soleur/test/infra-validation-detect.test.sh` must also pass standalone.
- [ ] **AC7 — Lint sanity.** `actionlint .github/workflows/infra-validation.yml` returns clean. `bash -n <embedded-shell-snippet>` of the rewritten `run:` block returns clean (extracted into a temp file to avoid YAML-as-bash parse errors per learning `2026-05-11-multi-word-required-check...`).
- [ ] **AC8 — PR body cites both reproduction (broken) and fix-verified (working) `git diff --name-only` output against commit `7e6f6726`** so a reviewer can replay the bug in 10 seconds.

### Post-merge (operator)

- [ ] **AC9 — Verify on the next live infra PR.** PRs #3985 / #4002 / #4003 are all MERGED (verified via `gh pr view <N> --json state,mergedAt` on 2026-05-18) — there is no open branch to dispatch against. Two paths:
  - **(a) Wait-and-verify (preferred):** On the NEXT PR opened against `main` that touches `apps/<x>/infra/` or `infra/<x>/`, run `gh run list --workflow=infra-validation.yml --limit 5 --json status,conclusion,event,headBranch,databaseId` to find the run, then `gh run view <id> --json jobs | jq -r '.jobs[].name'`. Expected: `validate (apps/web-platform/infra)` (or sibling) appears in the job list — NOT skipped.
  - **(b) Dispatch fallback:** `gh workflow run infra-validation.yml --ref main`. NOTE: the dispatch branch at line 49 uses `find` (live worktree), not `git diff` — it would NOT exercise the fix. Document this in the verification log: the dispatch path enumerates ALL infra roots regardless of diff, which proves nothing about the diff-detection fix. The wait-and-verify path is canonical.
  - Automation: this is an unavoidable wait-for-real-PR step. Not a `gh api` automatable call — the verification is the absence-of-skip on a real diff. Acceptable post-merge operator step per `hr-all-infrastructure-provisioning-servers` exception clause (verification, not provisioning). Genuinely operator-only: needs a live infra PR to fire against. `Automation: not feasible because the trigger requires a real PR diff that does not exist at merge time.`
- [ ] **AC10 — Issue #4012 auto-closes on merge.** PR body uses `Closes #4012` (per `wg-use-closes-n-in-pr-body-not-title-to`). Verified at AC8 reference. No separate `gh issue close` step required because this is NOT an ops-remediation class plan — the fix is mechanical CI logic, applied atomically at merge.

## Files to Edit

- `.github/workflows/infra-validation.yml` — line 53 detection one-liner (`'apps/*/infra/' 'infra/'` → fixed form), lines 41-47 comment block, possibly a tiny rename of the `find` workflow_dispatch helper if Phase 1 prefers DRY (deferred — `find` works, `git diff` does not, they are different concerns).

## Files to Create

- `plugins/soleur/test/infra-validation-detect.test.sh` — bash test fixture that sources `test-helpers.sh`, mocks `git diff --name-only` output, runs the detection pipeline as a shell function `detect_infra_dirs()`, and asserts the seven scenarios in AC5 (three-shape matrix on `apps/<x>/infra/`, two-shape matrix on `infra/<x>/`, mixed-and-controls, empty/zero-match). Location is canonical per `scripts/test-all.sh` walk pattern (verified at deepen-plan time).

## Research Reconciliation — Spec vs. Codebase

| Spec / issue claim | Codebase reality | Plan response |
| --- | --- | --- |
| Issue body says `'apps/*/infra/'` "silently misses files under nested infra paths". | Verified on commit `7e6f6726`: `git diff -- 'apps/*/infra/'` returns empty even for DIRECT-CHILD `apps/web-platform/infra/uptime-alerts.tf` (no nesting needed). Bug is broader than "nested only" — the trailing-slash-no-`**` pathspec misses everything under `infra/`. | Plan AC1 fixes both nested AND direct-child detection. AC5 fixture covers both. |
| Issue body says workflow status reports `success`. | Verified by reading workflow YAML: `validate` and `plan` jobs are gated by `if: needs.detect-changes.outputs.directories != '[]'`. When the array is empty the jobs are SKIPPED (not failed), and GitHub Actions reports overall workflow status as `success` when all required jobs either succeed or are skipped. Matches issue claim. | AC9 confirms post-fix that `validate` runs (not skipped) on a real infra PR. |
| Issue proposes Option A (`:(glob)` magic) and Option B (`grep -E` filter). | Verified BOTH work on commit `7e6f6726`. Also verified `'apps/*/infra/**'` (double-star without `:(glob)`) works on installed `git 2.53.0` BUT this is an unsafe form across git versions — older git treats `*` as not crossing `/` even after `**`. Canonical-safe forms are A and B only. | AC1 enumerates Option A and Option B as equivalent; Phase 1 picks based on which existing workflow precedent reads cleanest. Code-simplicity reviewer to weigh in at plan-review. Default lean: Option B (no pathspec magic, transparent shell filter, fewest surprises). |
| Issue body says workflow already triggers on `paths: ["apps/*/infra/**"]`. | Verified at workflow lines 13-15. GitHub's `paths:` filter uses GLOB semantics (not git pathspec) and works correctly. The bug is exclusively in the `detect-changes` shell pipeline at line 53. | Plan scope is line 53 only. Trigger filter at lines 13-15 is correct and untouched. |
| Issue body says PR #3985, #4002, #4003 had `validate: SKIPPED`. | PR #3985 file list confirmed via `gh pr view 3985 --json files` — includes `apps/web-platform/infra/sentry/cron-monitors.tf` (nested-one-level). Did NOT independently re-fetch run status for #4002 / #4003 — claim accepted at face value because reproduction on `7e6f6726` is sufficient evidence and the workflow YAML defect is self-evident. | AC9 verifies fix on a future PR; the historical SKIPPED status is treated as motivation, not as a load-bearing claim. |

## Open Code-Review Overlap

```bash
$ gh issue list --label code-review --state open --json number,title,body --limit 200 > /tmp/open-review-issues.json
$ jq -r --arg path ".github/workflows/infra-validation.yml" '.[] | select(.body // "" | contains($path)) | "#\(.number): \(.title)"' /tmp/open-review-issues.json
(none)
$ jq -r --arg path "infra-validation" '.[] | select(.body // "" | contains($path)) | "#\(.number): \(.title)"' /tmp/open-review-issues.json
(none)
```

None. Plan-review may surface additional overlaps; rerun this grep at deepen-plan time.

## Implementation Phases

### Phase 0 — Preconditions

- [ ] **0.1** `cd <worktree-abs-path>` and verify `pwd` matches `.worktrees/feat-one-shot-4012-infra-pathspec`. (Bash CWD non-persistence guard, per learning `2026-04-22-verification-claims-in-plans-decay-silently.md`.)
- [ ] **0.2** Re-run the reproduction. `git diff --name-only 7e6f6726^..7e6f6726 -- 'apps/*/infra/' 'infra/'` returns empty. Confirms bug still present at HEAD detection-form.
- [ ] **0.3** Pick the detection form (Option A vs Option B). Default = Option B unless plan-review consensus prefers Option A. Document the choice in `tasks.md` and the commit message.
- [ ] **0.4** Test file location is LOCKED to `plugins/soleur/test/infra-validation-detect.test.sh`. Verified at deepen-plan time by reading `scripts/test-all.sh` lines 38-46: the runner walks `for f in plugins/soleur/test/*.test.sh; do run_suite "$f" bash "$f"; done`. This is the ONLY directory it auto-discovers. Other `.test.sh` locations (`scripts/*.test.sh`, `apps/web-platform/infra/*.test.sh`, `.github/workflows/*.test.sh`) are NOT exercised by `bun run test` — they run from dedicated workflows or not at all. Co-location with the workflow file at `.github/workflows/` would orphan the test.

### Phase 1 — Implement detection-form rewrite (TDD)

- [ ] **1.1 RED.** Write `plugins/soleur/test/infra-validation-detect.test.sh`. Template: `plugins/soleur/test/auto-close-scanner.test.sh` (same conventions, same `test-helpers.sh` source, same `set -euo pipefail`). Test all seven scenarios per AC5 — three-shape matrix on `apps/<x>/infra/` (direct/nested/deep), two-shape on `infra/<x>/` (direct/deep), mixed-and-controls, empty/zero-match. Test structure: shell function `detect_infra_dirs()` that reads `stdin` (so the test can pipe synthetic `git diff --name-only` output without needing a real git invocation). Initial implementation of `detect_infra_dirs()` = the CURRENT broken pipeline (`git diff -- 'apps/*/infra/' 'infra/'` shape). Test FAILS as expected.
- [ ] **1.2 GREEN.** Replace the detection pipeline body inside `detect_infra_dirs()` with the Phase 0.3 chosen form (Option A or Option B). Rerun the test — all seven scenarios pass.
- [ ] **1.2b GREEN equivalence check (pathspec→regex equivalence gate per learning `2026-05-09-pathspec-regex-translation-and-classifier-piggyback.md`).** Verify the new detection form is equivalent to the pathspec semantics on the canonical baseline commit:
  ```bash
  # Baseline = full diff filtered manually
  EXPECTED=$(git diff --name-only 7e6f6726^..7e6f6726 | grep -E '^(apps/[^/]+/infra|infra/[^/]+)/' | sed -E 's|^(apps/[^/]+/infra)/.*|\1|; s|^(infra/[^/]+)/.*|\1|' | sort -u)
  # Candidate = run the new function on the same input
  ACTUAL=$(git diff --name-only 7e6f6726^..7e6f6726 | detect_infra_dirs)
  diff -u <(echo "$EXPECTED") <(echo "$ACTUAL")
  ```
  Exit 0 expected.
- [ ] **1.3 REFACTOR.** Replace the workflow's inline detection one-liner with the same `detect_infra_dirs()` function shape used in the test (factor the pipeline so it is byte-identical between workflow `run:` block and test fixture). Update the comment block at lines 41-47 to match the new form. Load-bearing comment claims (two pathspec families, sed anchors, deep-nested collapse) MUST be preserved. Verify final workflow shape via `actionlint .github/workflows/infra-validation.yml` (clean) AND `bash -n <(extract the run: block to temp file)` (clean, per learning `2026-05-11-multi-word-required-check-exposes-strip-all-whitespace-bug.md` on the `bash -n` YAML-as-bash trap).

### Phase 2 — Wire the test into the existing runner

- [ ] **2.1** `cat scripts/test-all.sh` to learn how tests are discovered. If it `find`s `*.test.sh`, the new test is auto-discovered. If it lists tests explicitly, add the new test path.
- [ ] **2.2** `bash scripts/test-all.sh` locally — confirm new test name appears in output and passes.
- [ ] **2.3** `actionlint .github/workflows/infra-validation.yml` returns clean (per AC7).

### Phase 3 — Replay-evidence in the PR body

- [ ] **3.1** Capture both reproduction outputs:
  ```bash
  $ git diff --name-only 7e6f6726^..7e6f6726 -- 'apps/*/infra/' 'infra/'   # BEFORE
  $ git diff --name-only 7e6f6726^..7e6f6726 -- <new-form>                 # AFTER
  ```
- [ ] **3.2** Paste both into the PR body's Evidence section so reviewer can replay in 10 seconds.

### Phase 4 — Ship

- [ ] **4.1** Commit. Message: `fix(ci): infra-validation pathspec glob silently skips nested infra-only diffs (#4012)`.
- [ ] **4.2** Push. Open PR with `Closes #4012` in body.
- [ ] **4.3** Multi-agent plan review (DHH / Kieran / Simplicity) — typically inline at /work via `soleur:plan-review`.
- [ ] **4.4** Merge via `gh pr merge --squash --auto`.
- [ ] **4.5** Post-merge: AC9 verification on next infra PR (or `workflow_dispatch` against PR #4003 if still open).

## Test Strategy

**Test runner:** existing `bun run test` → `bash scripts/test-all.sh`. Convention: `*.test.sh` bash files with `set -euo pipefail`, function-named test cases, and a final-line `echo "all tests passed"` or equivalent assertion sentinel. Verified via `find . -name '*.test.sh'` returning matching siblings (`scripts/compound-promote.test.sh`, `apps/web-platform/infra/ci-deploy.test.sh`, `.claude/hooks/log-rotation.test.sh`, etc.).

**Test isolation:** the detection one-liner is rewritten as a shell function reading `stdin`. The test pipes synthetic `git diff --name-only` output — no real git invocation, no real worktree dependency. Fast, hermetic, version-of-git-independent.

**Mock filenames in the test:**

- `apps/web-platform/infra/uptime-alerts.tf` (direct child)
- `apps/web-platform/infra/sentry/uptime-monitors.tf` (nested one level)
- `apps/cla-evidence/infra/main.tf` (sibling app)
- `infra/github/labels.tf` (top-level infra root)
- `apps/web-platform/server/route.ts` (non-infra control; must be filtered out)
- `knowledge-base/project/plans/2026-05-18-foo-plan.md` (non-infra control)

## Hypotheses

(Not applicable — bug class is purely git-pathspec semantics, not a network/SSH/firewall hypothesis. The network-outage checklist is not triggered.)

## Risks / Sharp Edges

- **`**` without `:(glob)` is git-version-sensitive.** Installed `git 2.53.0` happens to expand `apps/*/infra/**` correctly without the `:(glob)` magic prefix, but this is unsafe to rely on. The CI runner (Ubuntu 24.04) ships modern git, BUT a future GHA runner image regression OR a contributor running the test locally with older git would silently re-introduce the bug. Choose ONE of the two safe forms (Option A `:(glob)` or Option B `grep -E` filter), document the rationale in the workflow comment, and avoid bare `**`.

- **`grep -E` filter (Option B) is the simpler form** but has one micro-trap: under `set -euo pipefail`, `grep` returns exit 1 on zero matches, which propagates as pipeline failure. The bash pipeline in the workflow has NO `set -euo pipefail` enabled at the step level (`run:` blocks default to `bash -e` for GitHub Actions), so a zero-match `grep` will fail the step. Mitigation: append `|| true` to the `grep` and rely on the downstream `sort -u | jq -R -s -c '... | map(select(. != ""))'` to collapse the empty case to `[]`. Verify in the test by piping an all-non-infra synthetic input and confirming the pipeline returns `[]` not a failure exit.

- **Comment-vs-code drift after this PR.** The `detect-changes` comment block at lines 41-47 already says `**` semantics. The current code at line 53 contradicts the comment (uses bare `/`). The fix aligns code to comment. Post-fix, the comment must still describe what the code does — not a future intent. Plan-review should verify byte-by-byte alignment.

- **AC2 reproduction depends on commit `7e6f6726` staying in repo history.** The commit is on `main` (verified via `git log --all --oneline 7e6f6726` shows the original branch context). Not at risk of disappearing — squash-merged commits are immutable on `main`. If a future repo-history rewrite removes it, the test fixture (which uses synthetic stdin, no real git refs) still works; only the manual reproduction step in AC2 would need a new SHA.

- **The `find` workflow_dispatch branch at line 49 has a related but distinct shape.** `find apps/*/infra -maxdepth 0 -type d` shell-expands `apps/*/infra` at glob-time (NOT find-time), then `find` is invoked on the expanded list. This works correctly today because bash globbing crosses `*` (bash glob ≠ git pathspec). NOT in scope here. If a future plan changes the matrix shape it must also update line 49.

- **Plan-time grep against agent invocation surfaces.** The detection logic is invoked from exactly one site (`detect-changes` job at line 36). No sibling skill / hook / workflow re-uses this pathspec form. Verified via `grep -rn "apps/\*/infra/'" .github/` returns one hit. No multi-surface propagation needed.

- **AGENTS.md rule citations.** This plan body cites no `hr-*` / `wg-*` / `cq-*` IDs by reference; no retired-rule sweep needed. The plan invokes one workflow-gate by name (`wg-use-closes-n-in-pr-body-not-title-to`) implicitly via "Closes #4012 in PR body" in AC10. Verified `Closes #4012` is in PR BODY not TITLE — compliant.

- **No vendored upstream files touched.** `.github/workflows/infra-validation.yml` is repo-owned. No `# upstream:` frontmatter; no sync contract to break.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — internal CI tooling hardening on a YAML workflow file. Engineering domain only; no product/legal/finance/community/marketing/security/operations surface impacted beyond the existing CI integrity surface this PR repairs.

## Infrastructure (IaC)

Not applicable — this PR edits ONLY `.github/workflows/infra-validation.yml` and adds one `.test.sh` fixture. No Terraform, no cloud-init, no systemd, no Doppler secret, no vendor account, no DNS, no firewall rule, no new persistent runtime process. Skip silently per the gate rule.

## GDPR / Compliance Gate

Not applicable — no regulated-data surface touched (no schema, no auth flow, no API route, no `.sql`, no LLM-on-operator-data processing, no new artifact distribution surface). The four expanded-coverage triggers (a)-(d) do not fire:
- (a) No new LLM/external-API processing of session data — pure shell pipeline rewrite.
- (b) Brand-survival threshold is `none`, not `single-user incident`.
- (c) No new cron/workflow reading from `knowledge-base/project/learnings/` or `specs/`.
- (d) No new artifact distribution surface.

Skip per `2.7`.

## Alternative Approaches Considered

| Approach | Pro | Con | Decision |
| --- | --- | --- | --- |
| Option A: `:(glob)apps/*/infra/**` `:(glob)infra/*/**` | Stays in git pathspec land; explicit `:(glob)` opt-in makes the intent obvious to readers familiar with git magic. | `:(glob)` is a less-common git feature; junior reviewers may not recognize the syntax. | Equivalent to Option B; Phase 0.3 final choice deferred to plan-review. |
| Option B: drop pathspec entirely, filter via `grep -E '^(apps/[^/]+/infra\|infra/[^/]+)/'` | Transparent shell; no git-magic syntax; uniform with the existing `sed -E` anchor pattern below. | One extra pipe stage; needs `\|\| true` guard for zero-match case under `bash -e`. | Default lean. Decision deferred to plan-review. |
| Stop using `git diff` and switch to GitHub API change-list (`gh api repos/:owner/:repo/pulls/:n/files`) | Returns canonical file list per API contract; avoids local `git diff` semantics entirely. | Requires a `GITHUB_TOKEN` permission in the `detect-changes` job (currently has `contents: read` only — would need `pull-requests: read`); rate-limit risk; PR-number not always available (workflow_dispatch path). | **Rejected.** Out of proportion to the bug class. Local pathspec fix is one line. |
| Drop `detect-changes` entirely and run validate on all infra roots every PR | Eliminates the detection-correctness problem by deleting the feature that has the bug. | Wastes minutes per PR running validate on roots that didn't change; loses per-app `main.test.sh` scoping; defeats the matrix optimization. | **Rejected.** YAGNI on detection is not the right call — there are 2+ infra roots growing to 4+ (cla-evidence, web-platform, future sub-roots, plus top-level `infra/github`). The matrix optimization carries weight. |
| Add `:(glob)` to BOTH the trigger filter AND the detection pipeline | "Defense in depth" — fix both layers even though only the detection layer is broken. | The trigger filter at lines 13-15 uses GitHub's GLOB syntax (NOT git pathspec) and works correctly today. Editing it would be a no-op or worse. | **Rejected.** No change to trigger filter; scope tight. |

## Non-Goals

- **Not refactoring the `find` workflow_dispatch branch at line 49.** Different code path, works correctly, out of scope.
- **Not changing the `sed -E` ancestor-collapse pipeline.** The collapse semantics are correct; only the upstream pathspec is broken.
- **Not adding `:(glob)` to the workflow trigger `paths:` filter at lines 13-15.** That filter uses GitHub Actions glob syntax (`**` works correctly there), not git pathspec.
- **Not back-filling validate runs on the three documented victim PRs (#3985, #4002, #4003).** Per `wg-after-merging-a-pr-that-adds-or-modifies` the next infra PR will exercise the fix. Manually re-running `infra-validation.yml` on already-merged PRs is below the threshold for value.
- **Not adding a CODEOWNERS / required-check escalation.** The `validate` matrix being skipped today is already a `required: false` outcome (workflow status `success` either way). Adding a required-check gate to force `validate` to run is a separate scope and would need its own analysis of false-positive impact on docs-only PRs.

## Related Work

- Learning `2026-03-21-lefthook-gobwas-glob-double-star.md` — sibling failure mode where `**` is unsupported in default Lefthook gobwas glob; documents the broader "glob semantics differ across tools" class. This plan adds a sibling data point: git pathspec `*` does not cross `/` either.
- Learning `2026-04-28-plan-globs-must-be-verified-against-repo-structure.md` — `hr-when-a-plan-specifies-relative-paths-e-g` cited by AGENTS.md core. This plan complies: every prescribed pathspec was verified via `git diff --name-only` against a real commit BEFORE freezing the AC.
- PR #3985 (TR9-PR1 Inngest migration) — silent victim; merged with `validate: SKIPPED` per issue evidence.
- PR #4003 (motivating commit `7e6f6726` — soleur.ai uptime alerting) — bug discovered during this PR's review.

## Verification Replay (for PR body)

```bash
# BEFORE (current broken detection)
$ git diff --name-only 7e6f6726^..7e6f6726 -- 'apps/*/infra/' 'infra/'
(empty)

# AFTER Option A
$ git diff --name-only 7e6f6726^..7e6f6726 -- ':(glob)apps/*/infra/**' ':(glob)infra/*/**'
apps/web-platform/infra/sentry/uptime-monitors.tf
apps/web-platform/infra/uptime-alerts.tf

# AFTER Option B
$ git diff --name-only 7e6f6726^..7e6f6726 | grep -E '^(apps/[^/]+/infra|infra/[^/]+)/'
apps/web-platform/infra/sentry/uptime-monitors.tf
apps/web-platform/infra/uptime-alerts.tf

# Collapse → matrix (Option B form, identical for A)
$ git diff --name-only 7e6f6726^..7e6f6726 \
  | grep -E '^(apps/[^/]+/infra|infra/[^/]+)/' \
  | sed -E 's|^(apps/[^/]+/infra)/.*|\1|; s|^(infra/[^/]+)/.*|\1|' \
  | sort -u
apps/web-platform/infra
```

That last line — `["apps/web-platform/infra"]` after `jq -R -s -c` — is exactly what the `validate` matrix consumes. Bug fixed.
