# Adopting a GitHub merge queue: wire EVERY required-context producer, across ALL rulesets, for `merge_group`

**Date:** 2026-06-30
**Issue:** #5780 (PR-1)
**Tags:** category: integration-issues, module: ci/github-rulesets

## Problem

Adopting a GitHub merge queue on `main` requires that **every** required status
check reports on the queue's `merge_group` temp ref (`gh-readonly-queue/main/pr-N-<sha>`).
A required check whose workflow never fires on `merge_group` leaves the queue
entry **pending forever** — the queue stalls on the first PR. The naive plan
("add `merge_group:` to the 7 CI-Required producer workflows") was insufficient
in three ways, each caught at a later pipeline phase than it should have been.

## Root causes & the three traps

1. **Job-level `pull_request` gates inside a producer workflow.** Adding
   `merge_group:` to a workflow's `on:` is NOT enough if a job that produces a
   *required* context has `if: github.event_name == 'pull_request'`. On
   `merge_group` that job is **skipped** → the required context never posts →
   stall. In secret-scan.yml, `waiver discipline`, `rename-guard`, and
   `allowlist-diff` were all job-level PR-gated. Enumerate producers at the
   **job** level, not the workflow level.

2. **More than one ruleset gates `main`.** Producers were enumerated from the
   "CI Required" ruleset (16 contexts) only. `main` is **also** gated by a
   "CLA Required" ruleset (`cla-check` + `cla-evidence`, see
   `scripts/required-checks.txt`). Those producers (`cla.yml`/`cla-evidence.yml`)
   are `pull_request_target`/`issue_comment`-driven and cannot run on
   `merge_group` → first-PR stall. **Enumerate required-check producers across
   ALL rulesets targeting `main`, never a single ruleset.**

3. **Event-shape divergence in diff-base logic.** Jobs that compute a diff base
   from `github.base_ref` / `github.event.pull_request.*.sha` get an **empty**
   value on `merge_group` (only `github.event.merge_group.{base_sha,head_sha}`
   are populated). Two sub-failures: (a) a *vacuous pass* — an empty base that
   falls through to "nothing changed → exit 0" forges a green required context
   (legal-doc `enforce` had to **hard-fail** on empty base instead); (b) a
   *false-fail* — `tc-document-sha-guard`'s TC_VERSION-bump bypass silently
   no-ops on `merge_group` (empty `github.base_ref`), turning a legitimately-green
   PR red-on-queue. Branch every diff-base on `event_name == 'merge_group'`.

## Solution (the patterns)

- **Pattern A — re-scan the candidate** for cheap, pure-diff, label-independent
  required jobs: derive base/head from `merge_group.{base_sha,head_sha}` and
  re-run. Strictly safer (validates the projected merge). These also fail
  *closed* on an empty base (the `git diff` errors under `set -euo pipefail`),
  so an explicit empty-base guard is optional for them.
- **Pattern B — trust the pre-queue PR run** for required jobs whose verdict
  depends on PR-only context a `merge_group` event cannot see (a label, a PR
  comment): post a SUCCESS without re-running. **Sound only because of the
  entry-gate guarantee** (next section), plus a re-scanning Pattern-A backstop
  for any projected-base divergence.
- **Synthetic check-runs for author-property gates** (CLA): use the **Checks
  API** (`POST repos/{repo}/check-runs`), NOT the Statuses API, under the
  default `GITHUB_TOKEN` — the ruleset matches Check Runs from a specific
  integration_id (15368 = the github-actions App). An external/app token posts
  under a different integration_id and **fails the ruleset match**, silently
  re-breaking the queue. `checks: write` only; no checkout.

## Key insight — the merge-queue entry-gate premise (load-bearing, verify it)

GitHub docs ("Managing a merge queue"): *"Once a pull request has passed all
required branch protection checks, a user with write access can add the pull
request to the queue."* Then the same checks are **re-evaluated** on the merge
group. This two-stage gate is what makes Pattern B and the CLA synthetic sound:
a PR can only reach a `merge_group` event by being green-on-head first, so
re-posting an author-property or already-acked gate as green on the candidate
accurately reflects state proven at admission. **If you build any
trust-pre-queue pass, cite this premise — don't assume it.** (Architecture
review flagged it as asserted-not-cited; a WebFetch of the docs confirmed it.)

## Observability split

A stall probe (`mergeQueue.entries` pending > threshold via `gh api graphql`,
GITHUB_TOKEN-only) is **config-presence-blind**: it cannot see a *silently
disabled* queue (rule removed → no entries → nothing to find). Drift detection
of the `merge_queue` rule needs a `terraform plan` (Administration-scoped) and
belongs in the scheduled-terraform-drift cron, NOT bolted into the stall probe
(which would force app-secrets into a no-app-secrets GH cron). Keep stall
detection and drift detection as separate concerns with separate auth.

## Session Errors

1. **Planning subagent hit the Anthropic session usage limit** (first attempt,
   no artifact emitted). Recovery: retried the subagent; it succeeded. Prevention:
   on a subagent that dies with a usage-limit/rate-limit result, re-spawn rather
   than falling back to inline (which shares the same budget); a partial-artifact
   recovery check first avoids redoing completed work.
2. **YAML parse error: colon in an unquoted `run:` scalar.** `run: echo "x: y"`
   → "mapping values are not allowed in this context." Recovery: use a block
   scalar (`run: |`). Prevention: for any single-line `run:` whose value contains
   `: `, use `run: |`.
3. **iac-routing PreToolUse hook false-positived on documentation prose** twice
   (the words "out-of-band" and credential/PAT framing read as manual-infra),
   despite the plan's `iac-routing-ack` comment. Recovery: reworded to IaC-neutral
   language ("removed without a matching Terraform change"). Prevention: in
   plan/spec prose, avoid "out-of-band", "mint", "PAT", "operator"-framed
   sentences when describing IaC; the ack comment does not exempt new edit text.
4. **shellcheck SC2016 disable directive scope.** A `# shellcheck disable` before
   a multi-line `resp=$(...)` did not cover a later `printf` line. Recovery:
   restructured (moved a jq prefix-match into awk to drop the shell-lookalike
   var) + placed a disable directly before the remaining printf. Prevention:
   a disable directive covers the next command only; place it immediately before
   the flagged line.
5. **Plan-gap class (5-8 above): plan under-specified the producer set, missed a
   second ruleset, and missed an event-shape bypass.** Recovery: traced the
   actual producers at /work + multi-agent review caught the rest; all fixed
   inline. Prevention: the three traps in this learning — enumerate at job level,
   across all rulesets, and branch every diff-base on the merge_group event.

## Prevention

When adding `merge_group` support for a merge queue:
- Map each required `context` string (from **every** ruleset on the branch) to
  its emitting **job**, and confirm that job runs AND posts on `merge_group`.
- Grep `git grep -n 'github.event.pull_request\|github.base_ref' .github/workflows/`
  and branch each one on the merge_group event (empty base = hard-fail, never
  vacuous-pass).
- Cite the GitHub entry-gate premise for any trust-pre-queue pass.
