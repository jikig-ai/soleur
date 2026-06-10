# Learning: Workflow agent() spawns skip PostToolUse hooks (executed model lives in transcripts), and review skeptics mutation-probe the live worktree

## Problem

Two empirical harness facts surfaced while implementing #3791 (model-tier pins):

1. The plan assumed the `agent-token-tee.sh` PostToolUse hook could attribute model tiers for Workflow-runtime `agent()` spawns. A one-spawn probe (`agent(prompt, {model:'haiku', label:'capture-probe'})`) showed the hook **never fires for workflow spawns** — `.claude/.session-tokens.jsonl` gains no row; only direct Agent-tool spawns emit PostToolUse.
2. During the acceptance review run, the full `scripts/test-all.sh` suite failed on the brand-new `workflow-model-pins.test.ts` with an `// evasion test` block (`evil-dq`/`evil-tpl`/label-less `model: 'opus'`) injected into `plan-review.workflow.js` — content nobody committed. A review-workflow skeptic verifying the `pin-allowlist-regex-evasion` finding had performed a non-vacuity **mutation probe on the live worktree** (inject → run test → revert). The file was clean again minutes later; the suite failure was transient.

## Solution

1. **Telemetry re-routing (ADR-053):** the tee-hook `model` field covers direct spawns only; workflow-pin verification uses the run transcript — `grep -ho '"model":"[^"]*"' <run-transcript-dir>/agent-*.jsonl | sort | uniq -c` — which carries the **executed** model (stronger than request-side `tool_input.model`). Acceptance evidence: pinned `classify` ran `claude-sonnet-4-6` while all 30 judgment spawns ran the session model.
2. **Mutation probe response:** verified the file was clean at HEAD and in the worktree, attributed the transient failure to the probe, and **adopted the probe's findings** — hardened the drift-guard against all three quote forms, label-less pins, identifier-form values (raw `\bmodel\s*:` key-count must equal the allowlist size), and proved non-vacuity with a deliberate inject→red→revert cycle.

## Key Insight

- **Workflow-runtime subagents are invisible to PostToolUse hooks.** Any telemetry/guard design that assumes hook coverage of workflow spawns is structurally broken; the workflow transcript dir (`subagents/workflows/<run-id>/agent-*.jsonl`) is the execution-side evidence channel, and assistant messages there carry the concrete executed model ID.
- **A test failure DURING a live review-workflow run may be a skeptic's mutation probe, not a regression.** Check `git status` + HEAD cleanliness before debugging; re-run the suite after the review completes. And treat the probe as free red-team input — its evasion forms are the exact cases the guard should cover.
- Source-reading drift-guards must match **all JS quote forms and the bare key**, not the style convention the author used — single-quote-only regexes are one `"` away from vacuous.

## Session Errors

1. **ADR ordinal collision (P1 at review)** — authored ADR-051 while main (brought in by my own mid-session rebase) already had ADR-051/052. Recovery: rename to ADR-053 + 16-file reference sweep. Prevention: after ANY rebase, re-run `bash scripts/check-adr-ordinals.sh` if the branch adds an ADR; pick the ordinal AFTER the rebase, not from the pre-branch listing.
2. **Sweep loop aborted after 1 file** — `while read; do [[ -f ]] && grep -l; done < list | xargs sed` stopped at the first non-existent path under the harness's errexit. Recovery: single `grep -rl | xargs sed` form. Prevention: avoid `[[ ]] &&` as the last command of a loop body in harness bash; use explicit `if`.
3. **Non-fast-forward push after rebase** — expected consequence of rebasing a pushed branch; resolved with `--force-with-lease`. Prevention: none needed (correct flow), just expect it.

## Tags

category: workflow-patterns
module: workflow-runtime, hooks, review
