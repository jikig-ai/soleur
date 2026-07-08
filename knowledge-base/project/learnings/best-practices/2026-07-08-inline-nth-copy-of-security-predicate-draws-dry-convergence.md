---
date: 2026-07-08
category: best-practices
module: apps/web-platform/server
tags: [security, dry, fail-closed, code-review, plugin-path, adr-093]
pr: 6225
issue: 6223
---

# Learning: inlining the Nth copy of a security-relevant predicate draws multi-agent DRY convergence — extract the shared symbol at work-time

## Problem

The #6223 fix hardened `buildAgentEnv`'s `CLAUDE_PLUGIN_ROOT` injection to fail-closed
(ADR-093), reusing the plugin-path guard family's test-env bypass predicate
`process.env.VITEST || process.env.NODE_ENV === "test"`. The straightforward
implementation **inlined a third copy** of that predicate (it already existed twice in
`plugin-path.ts` — `getPluginPath` + `assertTrustedPluginPath`) and added a code comment
promising the copies "cannot drift."

At review, **4 of 6 agents independently flagged the triplication** (user-impact P3,
security-sentinel P3, code-quality P3, architecture-strategist **P2**). The P2 framing was
the sharp one: a drift *toward more permissive* in any one copy is a security-relevant
**fail-open** (it would neuter the guard on a live dispatch), and a prose comment is not
enforcement.

## Solution

Extract a single exported predicate `isPluginPathTestEnv()` in `plugin-path.ts` and consume
it at all three sites. The "cannot drift" guarantee the comment merely *asserted* is now
**mechanically true** — there is one definition, so the three sinks cannot diverge. tsc +
the full plugin-path/agent-env suites stayed green (behavior-preserving).

## Key Insight

- **A code comment claiming two (or three) copies stay identical is documentation, not
  enforcement.** When a fix reuses a **security-relevant** predicate/literal that already
  exists inline in K places, do not add copy K+1 — extract a shared symbol at work-time.
  The cost is trivial (one exported function + imports) and it removes the entire drift
  class rather than promising against it.
- **This is a predictable review outcome, so pre-empt it.** A verbatim, well-reviewed plan
  can still land a DRY/fail-open smell that multi-agent review reliably converges on. If the
  plan says "reuse predicate X (canonical in file Y)" and X is a copy-pasted inline literal,
  the work-phase move is *extract-and-import*, not *inline-and-comment* — treat the plan's
  "keep it identical" note as a signal to DRY, not a license to duplicate.
- **Fail-open direction matters for severity.** Duplicated *test-bypass* predicates on a
  fail-closed security guard are worse than ordinary duplication: a permissive divergence
  silently disables the guard in production. That is why one agent correctly rated it P2 while
  three rated it P3 — sort by *which way the drift fails*.

## Session Errors

- **`git push` rejected (non-fast-forward)** after `/work` rebased the branch onto fresh
  `origin/main` (the plan subagent had already pushed the pre-rebase plan/tasks commits).
  Recovery: `git push --force-with-lease`. Prevention: this is expected when a one-shot run
  rebases a branch whose plan commit was already pushed; `--force-with-lease` is the standard,
  lease-safe recovery — not a defect. One-off/expected.
- **Concurrent review-agent worktree contamination:** `agent-env.ts` was reported "modified
  on disk" mid-edit because `test-design-reviewer` reverts source in place to verify RED.
  Recovery: re-read the file before editing. Prevention: already documented in
  `review/SKILL.md` §Sharp Edges ("Concurrent mutating agents contaminate the shared
  worktree") — synthesize against committed HEAD, re-read before edits.
- **Automated (non-Soleur) plugin security review flagged a stale HIGH** on
  `env.CLAUDE_PLUGIN_ROOT = opts.pluginPath` — it scanned the *removed* line; its suggested
  fix was verbatim the shipped code. Recovery: acknowledged, no change. Prevention: diff-scope
  automated findings against the *committed* diff before acting; a HIGH whose suggested fix
  equals the current code is scanning a pre-fix state. One-off.

## Related

- ADR-093 (2026-07-08 amendment, now "pinned") · #6156 PR (surfaced the P1) · #6154 (residual
  family migrations, distinct).
- `knowledge-base/project/learnings/bug-fixes/2026-07-06-connected-repo-shadows-deployed-plugin-via-workspace-relative-path.md`
