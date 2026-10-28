---
title: Running soleur:one-shot on OpenCode — depth-1 harness adaptations that keep every gate real
date: 2026-10-28
category: workflow-patterns
tags: [workflow-patterns, one-shot, opencode, subagent-nesting, sequential-fallback, review-panel]
---

# Learning: Running soleur:one-shot on OpenCode — depth-1 harness adaptations that keep every gate real

## Problem

`soleur:one-shot` assumes a harness where spawned children can themselves run child skills and where an advisor semantic tier (`resolveAdvisorTier()`) is resolvable. On OpenCode the adapter's **nesting depth is one** (INSTRUCTIONS.md: "A spawned child must not spawn further children"), there is no advisor-tier SKU map, and operator-typed skills render as **bare ids**. A naive port either deadlocks (a planning child told to fan out research agents it may not spawn) or silently degrades (steps skipped "for tokens").

## Solution

Every gate ran; only the EXECUTION SHAPE adapted, each with a disclosure:

1. **Plan + deepen child ran `plan`/`deepen-plan` inline and sequentially** (explicitly forbidden from spawning), disclosed in the plan's Enhancement Summary as `Reviewed-Coverage: sequential-fallback`. The compaction-boundary benefit of one-shot's isolated-planning subagent is preserved; the research fan-out is what degraded, honestly labeled.
2. **Step 4.5 advisor consult**: the batched CTO Rule-interface spawn ruled D1–D7; the separate consult ran as ONE `engineering/review/architecture-strategist` spawn on the session-inherited model — the disclosed tier substitution, per the ruling's own branch ("if the parent's harness cannot resolve the advisor tier, the skip stands disclosed, never silent"). A ruling is NOT a consult (#10552) — they were kept as separate obligations and separate artifacts.
3. **Review panel, fix round, verification pass all ran as real parallel depth-1 subagents** from the session (the leader), so `Reviewed-Coverage: full 11/11` and `Reviewed-Fix-Round` trailers carry no fallback label.
4. **Canonical `bash "${CLAUDE_PLUGIN_ROOT}/..."` calls**: the literal resolved root was typed into each fence (gates in go.md run with the env var set per-command, matching the OpenCode row's "set CLAUDE_PLUGIN_ROOT ... and re-run").
5. **`fix-round-seats.sh --finding-seats` takes registry LEAF names** (`security-sentinel`), not path-style spawn ids (`engineering/review/security-sentinel`) — the registry vocabulary differs from the subagent-tool vocabulary.
6. **Guard-shape fix validation on a child-less harness**: the structural-enumeration seat's sandbox mutants (`scripts/soleur-sandbox.sh`) plus in-suite positive controls (D9pc, D12c synthetic-write-flag control, D-pc PROFILES non-empty control) replaced the usual "another agent will catch it" layer.

## Key Insight

Depth-1 constrains WHO fans out, not WHETHER a step runs. The compliant pattern is: sequential-fallback inside children with disclosure, parallel seats only from the leader, and positive controls wherever a negative pin is the only witness. A pipeline that silently inlines the review fan-out into the leader's own context is the actual violation — the fan-out either happens at depth-1 or is disclosed as not happening.

## Session Errors

1. **subagent spawn rejected on a leading space in the path id** (` engineering/review/code-simplicity-reviewer`) — the error names the id verbatim; recoverable by one retry. — **Prevention:** copy agent ids from the harness's advertised list without re-typing; a spawn-key typo is a one-off, no rule needed.
2. **`declare "$var=…"` did not reach the mock child** in a dynamic-env loop — prefix-on-function-call and `export` put the value in the child's environment; top-level `declare` does not export. 5 spurious suite FAILs until switched to `export`+`unset`. — **Prevention:** when setting a fixture env var by NAME (loop), `export "$name=$value"`; the suite's `VAR=x run …` idiom works precisely because it exports for the call. (Recurring class for bash suites that fake envs dynamically.)
3. **D12c implicit-write regex shipped VACUOUS** — `(^|[[:space:]])-(-d|-T|…)` demands an extra dash before alternatives that already carry theirs; every real flag NOMATCHes and the guard passes unconditionally; two fix-round seats converged on it. — **Prevention:** a `src_lacks`-style negative pin whose pattern starts with a dash needs a SYNTHETIC POSITIVE CONTROL in the same suite (file with the bad shape, assert the pattern matches it) — extended the existing vacuous-pin doctrine (`cq-assert-anchor-not-bare-token`; #7695 #8418 learnings) to dynamic-pattern guards specifically.
4. **Commit landed while `lint-guard-contract` had exit 1** — the new `###`-headed amendments block under `## Guard Contract` was parsed as a third guard entry (Property/Assembly/matrix required); the FAIL line printed, the batch commit proceeded, the heading was demoted to bold prose after. Caught before push of the final state. — **Prevention:** in compound command chains, gate the commit on the lint (`lint … && git commit`), not newline-separated steps; the `hr-when-a-command-exits-non-zero-or-prints` rule already covers the class — this was sequencing, not a missing rule.
5. **Two `edit` calls failed exact-match** because the file had just been re-shaped by an earlier batch in the same block — resolved by re-reading the current region (never from remembered text). — **Prevention:** already-rule-covered (`hr-always-read-a-file-before-editing-it`).
6. **`worktree-manager draft-pr` raced the manual `git push -u`** — interleaved output showed `* [new branch]` AND `! [remote rejected]` in one tail; truth required an `ls-remote` probe, which showed the branch existed and draft-pr had meanwhile created its own init commit. — **Prevention:** on branch-state ambiguity, probe `git ls-remote` + `git log origin/main..HEAD` rather than trusting merged tail output of a raced pair.
7. **`fix-round-seats.sh` emitted `unknown-seat:` for path-style ids** — see Solution #5. — **Prevention:** pass registry leaves.
8. **Forwarded (planning child, pre-compaction)**: `gh api` jq rendered `database_id` null in the child env (premise validation fell back to timestamp+content match, disclosed in Research Insights); one edit consumed a sentence tail and was repaired by re-read before any gate ran. — **Prevention:** children must forward their errors into session-state.md `### Errors` (the pipeline's designed channel) — worked as designed.
9. **`guard-vacuity-floor.test.sh` exceeded the 120 s default tool timeout** locally; passed at 600 s. — **Prevention:** known-heavy suites get explicit timeouts on first local invocation (`wg-when-a-test-runner-crashes…` adjacent).

## Tags
category: workflow-patterns
module: skills/one-shot, harness adapters (opencode)
