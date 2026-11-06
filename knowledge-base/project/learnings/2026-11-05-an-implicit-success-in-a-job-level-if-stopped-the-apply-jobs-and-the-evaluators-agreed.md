# Learning: a job-level `if:` with no status-check function is implicitly `success() && <expr>` — reading `needs.X.result` does not suppress it, and a skipped need stopped the apply jobs

## Problem

PR #12153 (issues #11923, #11920) put a reviewer-gated `approve` job in front of the write jobs in `.github/workflows/key-rotate.yml` and `.github/workflows/inngest-key-rotate.yml`. The apply jobs' `if:` already read `needs.approve.result` inside a `(mode == 'plan' || needs.approve.result == 'success')` disjunct, so plan mode — where `approve` is skipped by its own `if:` — was expected to still run `apply`/`apply1`. It cannot: a job-level `if:` that calls no status-check function evaluates as `success() && <expr>`; `success()` is false when any entry in `needs:` did not succeed (a **skipped** need counts); and referencing `needs.<job>.result` inside the expression is an ordinary context read, not a status-check function — it does not drop the implicit `success()`. So the skipped `approve` made apply/apply1 skip on every plan-mode dispatch.

The workflow test evaluators had independently encoded the same wrong model in both suites, so the tests were green on a workflow whose plan path could never run — a test that models platform semantics wrong hides the bug it exists to catch.

## Solution

Prepend a status-check function so the explicit disjunct — not the implicit `success()` — decides (commit d7f9da2552):

```yaml
# Before:
if: ${{ github.event_name == 'workflow_dispatch' && needs.guard.result == 'success' && ... && (needs.guard.outputs.mode == 'plan' || needs.approve.result == 'success') }}
# After:
if: ${{ !cancelled() && github.event_name == 'workflow_dispatch' && needs.guard.result == 'success' && ... && (needs.guard.outputs.mode == 'plan' || needs.approve.result == 'success') }}
```

`!cancelled()` is a status-check function, so the implicit `success()` is dropped and the expression means "run unless cancelled, and only if the disjunct holds". The evaluators' suppression was reverted and both workflow suites now carry `no_cancelled` mutants that assert every gate-bearing job skips when the run is cancelled, so the wrong model cannot regress silently.

## Key Insight

In GitHub Actions, any job `if:` that names a `needs:` entry and calls no status-check function (`success()`, `failure()`, `always()`, `cancelled()`, `!cancelled()`) is really `success() && <expr>` — and a skipped need fails `success()`. Reading `needs.X.result` or `needs.X.outputs` inside the expression changes nothing about that. When a new conditional need joins a job's `needs:` list, ask "can this need be skipped, and does the `if:` contain a status-check function?" — and check the test harness's own model of the same platform rule, because a wrong evaluator and a wrong workflow cancel each other out. Sibling mechanism, same session: `2026-11-05-an-allow-skipped-needs-allowance-leaked-an-approval-failure-into-three-downstream-write-jobs.md`.

## Session Errors

1. **Plan write denied by `iac-plan-write-guard.sh` for the phrase `out-of-band`** (forwarded from the plan phase). Recovery: reworded — no operator provisioning steps. **Prevention:** already hook-enforced; the deny was the control working.
2. **Plan-phase subagent had no spawn tool, so all fan-outs ran inline sequentially.** Recovery: `Reviewed-Coverage: sequential-fallback` disclosed in the plan; six technical forks recorded as `pending - assumed:` rows and resolved by the ruling gate. **Prevention:** environmental — the fallback path worked as designed.
3. **Premise drift: the brief's `scripts/ci-deploy.sh` is actually `apps/web-platform/infra/ci-deploy.sh`.** Recovery: corrected in the plan; the parent plan is referenced at its archived path. **Prevention:** resolve every path a brief names with `ls`/`find` before it becomes a plan premise.
4. **`lint-shell-capture-exit` FAIL on the new restart-vector test rows: `x=$(grep -oE ... | head -1)` under `set -e` dies on no-match.** Recovery: `|| true` inside the substitution (commit 534cfb640d). **Prevention:** already enforced — the existing lint caught the class; a command-substituted capture that may legitimately be empty needs `|| true` and an empty-sentinel check in the assert arm.

## Tags
category: logic-errors
module: .github/workflows/key-rotate.yml, .github/workflows/inngest-key-rotate.yml, apps/web-platform/infra/key-rotate-workflow.test.sh, apps/web-platform/infra/inngest-key-rotate-workflow.test.sh
