---
title: gh workflow run requires the workflow file on the default branch — feature-branch dispatch returns 404
date: 2026-04-21
pr: 2717
issue: 2715
problem_type: integration_issue
component: ci_workflows
tags: [github-actions, workflow-dispatch, pre-merge-verification, gh-cli, ci-planning]
category: integration-issues
severity: medium
synced_to: [plan, work, qa]
---

# Learning: `gh workflow run` requires the workflow file on the default branch — feature-branch dispatch returns 404

## Problem

The plan for PR #2717 (`ops: add pre-flight Anthropic spend-cap guard`)
prescribed a Phase 1 exit check: add a temporary
`.github/workflows/test-anthropic-preflight.yml` with
`workflow_dispatch`, trigger via `gh workflow run`, poll until complete,
verify both the OK path (200 → `ok=true`) and the cap-exhausted mock
path (400 + `"specified API usage limits"` → `ok=false`). The test
workflow was to be deleted before PR merge.

The plan also required the composite action under test
(`.github/actions/anthropic-preflight/action.yml`) to carry an
`ANTHROPIC_PREFLIGHT_MOCK_RESPONSE` env-var short-circuit — a mock
branch in production code whose sole consumer was the temporary test
workflow above.

After committing and pushing the test workflow on the feature branch:

```bash
gh workflow run test-anthropic-preflight.yml \
  --ref feat-one-shot-2715-preflight-spend-cap-guard \
  -f scenario=ok
```

returned:

```text
HTTP 404: workflow test-anthropic-preflight.yml not found on the default branch
(https://api.github.com/repos/jikig-ai/soleur/actions/workflows/test-anthropic-preflight.yml)
```

The same 404 returned for `scenario=cap-exhausted`. Neither of the
plan's "trigger + verify" steps was executable pre-merge.

Downstream fallout:

- The temporary test workflow had to be deleted from the PR (it could
  not be triggered on the feature branch and was not worth merging to
  main just to trigger once).
- The mock short-circuit in `action.yml` became dead code the moment
  the test workflow was deleted. Grep across the worktree returned
  zero consumers; the plan's acceptance criterion for the mock became
  syntactically-true-but-semantically-empty.
- The review phase (security-sentinel + code-quality-analyst)
  independently flagged the mock branch as a P2 insider-bypass vector
  — a committer could set the env at job scope and force `ok=true`
  on a cap day, re-enabling spend. The fix was to delete the mock
  entirely, which then meant the T2 cap-exhausted scenario had no
  automated pre-merge coverage at all.

## Root cause

`workflow_dispatch` is looked up by workflow **name**, and GitHub's
enumeration step reads only the default branch (`main` here). The
`--ref <feature-branch>` parameter on `gh workflow run` tells GitHub
**which branch to run against**, not **which branch to find the
workflow file on**. Since the workflow file did not exist on `main`,
GitHub's first lookup returned 404 before it ever considered `--ref`.

Documented constraint (GitHub docs,
`/en/actions/how-tos/manage-runs/manually-run`): "The workflow file
must exist on the default branch of the repository before the
workflow can be run manually."

The plan assumed a model where `gh workflow run --ref <branch>` would
dispatch a branch-local workflow in the branch-local environment.
That model is wrong. The practical result: **a new workflow file added
by a PR is not dispatchable until the PR is merged to main.**

## Solution

Workarounds applied to PR #2717 during review:

1. **Extract the shell body and run locally with mocked inputs.** The
   composite action's bash `run:` block was extracted by awk from
   `action.yml`, then executed with synthesized `HTTP_CODE` /
   `BODY_FILE` values covering every branch (200, 400+cap, 503, 529,
   000, 400-non-cap, 401, `sk-*`-redaction). This is deterministic,
   requires no runner, and is fast enough to run on every iteration
   of the composite action body. See `/tmp/preflight-local-test.sh`
   in the PR's review commit for the harness shape.

2. **Delete the mock branch from production code.** Once local
   verification replaced the test workflow, the
   `ANTHROPIC_PREFLIGHT_MOCK_RESPONSE` short-circuit had no consumer
   and was a net-negative surface (dead code + insider-bypass path).

3. **Defer the live OK-path check to post-merge.** The plan already
   specified `gh workflow run scheduled-daily-triage.yml` as the
   cheapest real-API probe. That workflow **is** on main, so
   `workflow_dispatch` works. Run it after merge per
   `wg-after-merging-a-pr-that-adds-or-modifies`.

## Prevention

When a plan needs pre-merge verification of a new CI workflow or new
composite action, choose ONE of:

1. **Wire the check as a new job in an existing workflow that already
   runs on `pull_request`.** Pull-request-triggered workflows execute
   with the PR head's files available — `uses:
   ./.github/actions/<new-action>` resolves on the PR branch. This is
   the fastest path from "action committed" to "action tested in CI"
   without the default-branch round-trip. Downside: adds a small
   conditional step to an existing workflow; revert if not useful.

2. **Extract the logic into a shell script or module that can be
   unit-tested locally.** For composite actions whose body is bash,
   extract the body into `scripts/<name>.sh` called by a one-line
   `run: bash scripts/<name>.sh` in the action. The script is then
   trivially testable via `bash scripts/<name>.sh` with mocked env
   vars and no runner dependency.

3. **Explicitly defer to post-merge.** If (1) and (2) are too
   invasive, write the plan's acceptance criterion as
   "post-merge: trigger via `gh workflow run <existing-workflow>.yml`
   and verify steps 1–N in the run log." Do NOT plan a
   `workflow_dispatch`-triggered test workflow for pre-merge
   validation.

**Never plan:** "add a temporary test workflow with
`workflow_dispatch`, trigger from the feature branch, delete before
merge." GitHub's default-branch requirement makes step 2 impossible.

## Session errors

1. **Plan prescribed an infeasible pre-merge verification path.** —
   Recovery: switched to local bash-body harness. **Prevention:** plan
   and deepen-plan skills should flag `workflow_dispatch`-based
   pre-merge verification for new workflow files as a hard blocker
   during review. Cross-reference this learning in the plan skill's
   Sharp Edges.

2. **Mock short-circuit in `action.yml` was created solely to serve a
   test workflow that could never run pre-merge.** Production code
   carrying a mock branch with no consumer is both dead code and an
   insider-bypass vector (P2 per review). — Recovery: deleted the
   mock in the review phase. **Prevention:** when a plan specifies a
   "CI-only mock" in production code, verify the mock has at least
   one production-safe consumer committed in the same PR; if the
   intended consumer is a workflow file, verify the dispatch path
   actually works before accepting the plan.

3. **`yamllint` and `shellcheck` not installed locally; had to
   bootstrap during Phase 1 linting.** — Recovery: `pipx install
   yamllint` and manual `curl + tar` of shellcheck binary to
   `~/.local/bin`. **Prevention:** add both to the worktree bootstrap
   checklist or a dev-setup script.

4. **`actionlint` by file-path argument misparses composite action
   files.** Passing `actionlint .github/actions/<name>/action.yml`
   directly produces spurious "workflow syntax" errors because
   actionlint treats any named argument as a workflow file. —
   Recovery: run `actionlint` with no args (auto-discovery handles
   both workflows and actions correctly). **Prevention:** document
   the auto-discovery pattern in the skill that invokes actionlint
   (work Phase 3 Quality Check and review §CLI-Verification).

5. **PreToolUse security hook false-positive block on a safe
   workflow write.** The first `Write` of `test-anthropic-preflight.yml`
   returned a hook-error containing an informational block about
   `github.event.*` injection patterns — but the workflow did not
   reference any untrusted inputs. Retry of the identical write
   succeeded. — Recovery: retried the write. **Prevention:** the
   hook could skip the block when the content does not reference any
   `github.event.*` or `${{ github.*.body }}` expressions (narrow the
   trigger). Low priority — a one-time retry is cheap.

## References

- PR #2717 (this PR) — preflight spend-cap guard; review commit
  `ecdab8f3` documents the local harness workaround
- Issue #2715 — original symptom (8 failed workflow runs on cap day)
- GitHub docs — `/en/actions/how-tos/manage-runs/manually-run`
  ("The workflow file must exist on the default branch")
- `knowledge-base/project/learnings/integration-issues/claude-code-action-unsupported-push-event-and-doppler-only-secrets-20260416.md`
  — adjacent CI-platform-constraint learning
