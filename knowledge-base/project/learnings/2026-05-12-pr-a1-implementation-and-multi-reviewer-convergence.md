# Learning: Multi-reviewer convergence, SDK onText cumulative-block contract, and exhaustiveness-mirror pattern

## Problem

PR-A1 of #3603 implemented W2 (abort flush) + W8 (replace-not-append) for the cc-soleur-go transcript-persistence path. Three classes of issue surfaced during the implementation + review cycle:

1. **Latent O(n²) string accumulation** in `cc-dispatcher.ts:1054`'s `onText` callback. The pre-fix `accumulatedAssistantText += text` looked correct ("accumulate each emission") but was wrong against the SDK contract: each `onText` carries the CUMULATIVE block text per SDKAssistantMessage (per `soleur-go-runner.ts:1571-1600`, `text = block.text` is the full block), not a delta. Append produced quadratic copies AND a UI-vs-DB divergence the user saw live as "AC11 verification ping shows only the answer; DB has the answer + a hidden routing preamble" (AC11 evidence, conversation `deadbeef-dead-beef-dead-beefdeadbeef`).

2. **Bare-negation status discriminator bypassed an existing typed-exhaustiveness rail.** The W2 abort flush was guarded by `if (end.status !== "completed")`. The same file already had `TERMINAL_WORKFLOW_END_STATUSES` (a typed `ReadonlySet<WorkflowEndStatus>`) plus a compile-time exhaustiveness rail (`_workflowEndExhaustive: Record<WorkflowEndStatus, string>` at `cc-dispatcher.ts:165-167`). The new bare negation would silently route ANY future `WorkflowEnd` variant through the abort path without a TS error. Pattern-recognition reviewer flagged this as P1.

3. **Multi-line comment edit left an orphan sentence fragment.** The Edit replaced a 6-line comment block by matching from line 2 onward; line 1 (`// Per-turn assistant text accumulator. Reset to "" inside`) was left dangling as a half-sentence preceding the new block. Code-quality AND security reviewers independently flagged this — strong convergence signal.

## Solution

### Fix shape applied

```ts
// cc-dispatcher.ts:1023 (W8 fix — replace not append)
// Pre-fix:
accumulatedAssistantText += text;
// Post-fix:
accumulatedAssistantText = text;
```

```ts
// cc-dispatcher.ts:148-167 (mirror the existing exhaustiveness rail for the new branch)
const ABORT_FLUSH_STATUSES: ReadonlySet<WorkflowEndStatus> = new Set<WorkflowEndStatus>([
  "cost_ceiling", "runner_runaway", "user_aborted",
  "idle_timeout", "plugin_load_failure", "internal_error",
]);

// Compile-time exhaustiveness rail — Exclude<WorkflowEndStatus, "completed"> is the
// algebraic complement; this Record forces the set above to cover it.
type AbortFlushStatus = Exclude<WorkflowEndStatus, "completed">;
const _abortFlushExhaustive: Record<AbortFlushStatus, true> = {
  cost_ceiling: true, runner_runaway: true, user_aborted: true,
  idle_timeout: true, plugin_load_failure: true, internal_error: true,
};
void _abortFlushExhaustive;

// Then at the call site (was `if (end.status !== "completed")`):
if (ABORT_FLUSH_STATUSES.has(end.status)) { ... }
```

### Multi-reviewer convergence as a signal

Six review agents ran in parallel on the diff: security-sentinel, architecture-strategist, code-quality-analyst, performance-oracle, test-design-reviewer, pattern-recognition-specialist. Two findings emerged from 2+ reviewers — both were genuine and worth applying:

- Orphan comment line 1009 (code-quality + security)
- Extract op-slug ternary to a single `const` (performance + code-quality + architecture + pattern-recognition — 4-way convergence)

Findings unique to one reviewer were a mix of real-but-defer (e.g., rename suggestions) and aesthetic-only (e.g., `it.each` vs `for...of`). The convergence threshold ("3+ reviewers agree") was a reliable filter for "fix this commit-time" vs "defer to follow-up."

## Key Insight

**When a file already has a typed exhaustiveness rail for a discriminated union, new branches MUST mirror that pattern.** A bare negation (`if (x.status !== "completed")`) compiles without error today but silently absorbs future variant additions — exactly the bug the rail was built to prevent on the positive-coverage side. The cheap fix: introduce a sibling set + `Record<Exclude<Union, "matched-variant">, true>` rail. The pattern is grep-able (`_<X>Exhaustive`).

**`onText` from the Claude Agent SDK delivers cumulative block text, not deltas.** The chat-state-machine REPLACE semantic at `chat-state-machine.ts:477` is correct precisely because of this. Server-side accumulators that `+=` on every `onText` produce O(n²) memory + a UI-vs-persistence divergence that surfaces as "message changed after reload."

**Multi-reviewer convergence at 3+ is a hard filter.** It's faster than re-deriving "is this a real finding?" for every P2/P3 — if 3+ agents independently spot the same smell, apply the fix. Single-reviewer P2s are usually correct but cheaper to triage individually.

**Edit-of-multi-line-comment-blocks must include the first line in `old_string`.** Otherwise the leading sentence dangles. Both review agents that read the diff at the line-level caught this; the runtime impact is zero but the readability hit is real.

## Session Errors

1. **Bash CWD reverted to bare repo path mid-session.** Recovery: switched to absolute paths via `$WT` env var. Prevention: when in a worktree, prefix bash chains with `WT=<abs-path> &&` from the start, don't rely on a single `cd` persisting.

2. **Initial Phase 0.4 finding was wrong.** Reported 4 `WorkflowEnd` statuses; actually 7. Recovery: corrected during W2 test design; updated plan + session-state. Prevention: when enumerating discriminated-union variants, read the TYPE DECLARATION directly (`Read` the file region with the `export type X = ` block), not a status-string grep.

3. **`/soleur:gdpr-gate` skill not invocable via Skill tool.** Recovery: spawned `legal-compliance-auditor` agent as functional substitute. Prevention: when a skill isn't directly callable, fall back to its underlying agent — informational.

4. **Playwright browser session died mid-AC11 verification, OTP rate-limited on retry.** Recovery: pivoted to DB-side verification via Supabase service role REST API (functionally equivalent for `api-messages.ts` SELECT-style hydration). Prevention: for prod verifications, use storage-state preload via `bot-signin.ts` or pre-loaded password grant rather than the OTP UI flow — already documented at `plugins/soleur/skills/qa/SKILL.md:149`.

5. **Orphan comment fragment after Edit on multi-line block.** Two reviewers (code-quality + security) independently flagged it. Recovery: deleted the orphan line in a follow-up commit. Prevention: when replacing a multi-line comment block via Edit, include the FIRST line in `old_string` even if the replacement begins with different opening prose.

## Tags

category: process
module: cc-dispatcher
related:
  - knowledge-base/project/learnings/2026-05-11-brainstorm-grep-approach-hook-before-spawning-leaders.md
  - knowledge-base/project/learnings/2026-05-07-brainstorm-verify-referenced-pr-state-and-leader-infra-claims.md
issues:
  - "#3603 (hardening umbrella)"
prs:
  - "#3602 (PR-A1 — W2 + W8)"
