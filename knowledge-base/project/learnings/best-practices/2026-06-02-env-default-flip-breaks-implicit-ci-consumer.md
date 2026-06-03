---
title: "Flipping a bash env-var DEFAULT silently breaks any CI step that relies on the hardcoded default"
date: 2026-06-02
category: best-practices
tags: [bash, env-defaults, ci-workflows, blast-radius, hooks, tdd]
issue: 3800
pr: 4806
---

# Learning: env-var default flips have an implicit CI-consumer blast radius

## Problem

PR #4806 flipped a one-line bash default — `SOLEUR_DEFER_DRYRUN="${SOLEUR_DEFER_DRYRUN:-1}"` → `:-0}` — in `.claude/hooks/prod-write-defer-gate.sh` (the F2 prod-write defer gate, dry-run → enforce). A grep for consumers of the variable across `*.ts/*.sh/*.js` returned only the hook + its unit test, which reads as "sole consumer, safe one-line change."

That grep misses a class of consumer: a CI step that **never exports the variable and silently relies on the hardcoded default**. `.github/workflows/test-pretooluse-hooks.yml` Test 6 ran `terraform apply` through the real claude-code-action runtime and asserted `kind=would_defer` (dry-run telemetry). It worked only because the hardcoded default was `1`. After the flip it would have run in enforce mode, emitted `defer_requested` + `permissionDecision=defer`, and produced a false-FAIL against the `would_defer` assertion — green-CI today, confusing-signal tomorrow.

## Solution

Two moves, both in the same PR as the flip:

1. **Pin the old default explicitly at the implicit consumer.** Added `env: SOLEUR_DEFER_DRYRUN: "1"` at the claude-code-action step so the hook subprocess inherits it and Test 6 still exercises dry-run telemetry. The implicit dependency is now explicit.
2. **Add a RED-first test for the default-when-UNSET path.** Every existing test in the 61-case suite pinned the env var, so a silent revert of `:-0` back to `:-1` would pass all of them. Added `D4 default-unset enforce` using `env -i` (no `SOLEUR_DEFER_DRYRUN` passed) — the sole guard against a silent revert. Verified RED against the pre-flip default, GREEN after.

## Key Insight

When you flip a `${VAR:-default}` value, the consumer sweep must include surfaces that **depend on the default by omission**, not just surfaces that read the variable by name. A `grep VAR` finds explicit readers; it cannot find a CI step / cron / test that relies on the unset-fallback. Two cheap gates close the gap:

- Ask "which runner invokes this code WITHOUT setting the var?" and pin the old value there.
- For any default-bearing branch, add one test that runs with the var genuinely unset (`env -i`), since a suite that always pins the var cannot detect a default revert.

A bonus pattern from this PR: a 14-day-telemetry re-evaluation gate (the issue's precondition) is verifiable mechanically before the flip — classify the dry-run `would_defer` rows into real-prod-write vs heredoc/issue-body false-positives, and confirm the gate's intent (a phantom-matching rule with no real demand) is not met.

## Session Errors

1. **Agent fan-out unavailable in the planning-subagent context (no Task tool).** plan-review's 5-agent panel and deepen-plan's sub-agents could not spawn. **Recovery:** the load-bearing deepen value (hard gates 4.6/4.7/4.8, verify-the-negative, live citation checks) was executed mechanically; all passed. **Prevention:** known limitation — see [[2026-05-12-task-subagent-prompt-text-only]]; nested subagents inherit prompt text only and cannot spawn further Task agents. No workflow change warranted.
2. **IaC-routing PreToolUse hook false-positive on the plan body.** The plan quotes `doppler secrets set` / `terraform apply` verb-phrases the F2 gate matches, so the first plan-write was blocked. **Recovery:** documented `<!-- iac-routing-ack: plan-phase-2-8-reviewed -->` opt-out. **Prevention:** this is the exact heredoc/issue-body false-positive class PR #4806's deferred follow-up already tracks (regex fires on a verb-phrase inside a `<<EOF` body or `gh issue --body`). Already covered; no new rule.

## Tags
category: best-practices
module: .claude/hooks
