---
module: CI/CD
date: 2026-03-30
problem_type: integration_issue
component: development_workflow
symptoms:
  - "Deploy job fires when Docker build fails"
  - "Version output is available before Docker build completes"
  - "Spurious deploy webhooks trigger canary rollback on non-existent images"
root_cause: logic_error
resolution_type: config_change
severity: high
tags: [ci-cd, github-actions, deploy-gate, docker, always-function]
---

# Learning: Gate deploy job on Docker build success via dedicated output

## Problem

The deploy job in `web-platform-release.yml` used `always() && needs.release.outputs.version != ''` to decide whether to deploy. The `version` output is computed in an early step (before Docker build), so it's available regardless of whether Docker build+push succeeded. When Docker build failed, deploy still fired, the server attempted `docker pull` on a non-existent image, and the canary pattern rolled back.

Additionally, the Docker login and build steps were conditioned on `steps.create_release.outputs.released == 'true'`, which is `'false'` on retry (when the release already exists), preventing Docker rebuild even when the image was never successfully pushed.

## Investigation

1. Traced step execution order in `reusable-release.yml`: `check_changed` -> `version` -> `idempotency` -> `create_release` -> Docker login -> Docker build
2. Identified that `version.outputs.next` is set before Docker build runs, making it unsuitable as a deploy gate
3. Confirmed that `steps.X.outcome` works for `uses:` actions (not just `run:` steps) per GitHub Actions docs
4. Verified that Docker push to GHCR is idempotent (re-pushing same tag is safe)

## Solution

1. Added `docker_pushed` output to `reusable-release.yml` — a boolean gate set to `'true'` only when `steps.docker_build.outcome == 'success'`
2. Changed Docker login/build conditions from `steps.create_release.outputs.released == 'true'` to `steps.version.outputs.next != ''` — enables retry when release exists but image wasn't pushed
3. Replaced `needs.release.outputs.version != ''` with `needs.release.outputs.docker_pushed == 'true'` in both `web-platform-release.yml` and `telegram-bridge-release.yml` deploy conditions
4. Added `always()` to `telegram-bridge-release.yml` deploy condition for consistency with web-platform (needed for retry semantics)

Output chain: `steps.docker_pushed.outputs.pushed` -> job output `docker_pushed` (with `|| 'false'` fallback) -> workflow output `docker_pushed` -> caller `needs.release.outputs.docker_pushed`

## Key Insight

When gating downstream jobs on upstream step success in GitHub Actions, use a **dedicated boolean output** set only on success rather than re-using a pre-computed value. The `version` output was a poor deploy gate because it's set early in the pipeline. The `docker_pushed` output is set late (after Docker build) and defaults to `'false'` via the `|| 'false'` fallback, making it a proper boolean gate that correctly handles: first run (true), retry (true if Docker succeeds), failure (false), and cancellation (false).

The `always()` function is required when using this pattern with `needs:` dependencies — without it, GitHub Actions skips the job entirely when upstream jobs fail, and the `if:` condition never evaluates.

## Session Errors

1. **Wrong path for `setup-ralph-loop.sh`** — Used `./plugins/soleur/skills/scripts/setup-ralph-loop.sh` instead of `plugins/soleur/scripts/setup-ralph-loop.sh`. Recovery: globbed for the file. **Prevention:** Use canonical paths; the `scripts/` directory is at the plugin root, not under `skills/`.
2. **Review agents rate-limited (2/4)** — Architecture-strategist and code-simplicity-reviewer hit usage rate limits. Recovery: fallback gate proceeded with the 2 agents that returned results. **Prevention:** Expected during high-usage periods; the review skill's binary fallback gate handles this correctly.

## Prevention

- When adding outputs to reusable workflows, trace the full output chain: step output -> job output -> workflow output -> caller `needs` reference. Each level requires explicit mapping.
- Use `|| 'false'` fallbacks on boolean job outputs to prevent empty-string-as-truthy edge cases.
- When changing step conditions that gate on upstream step outputs, verify all three execution paths: first run, retry (idempotency skip), and failure.

## Cross-References

- Related: `knowledge-base/project/learnings/2026-03-20-ci-deploy-reliability-and-mock-trace-testing.md` — earlier fix that changed deploy gate from `released == 'true'` to `version != ''`; this learning supersedes that approach with the stronger `docker_pushed` gate
- Issue: [#1317](https://github.com/jikig-ai/soleur/issues/1317)
- Parent issue: [#1307](https://github.com/jikig-ai/soleur/issues/1307)

## Tags

category: integration-issues
