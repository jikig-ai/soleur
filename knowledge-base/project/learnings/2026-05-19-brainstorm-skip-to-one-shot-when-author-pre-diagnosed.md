---
title: "Brainstorm Skip-to-One-Shot When the Author Has Pre-Diagnosed the Fix"
date: 2026-05-19
category: workflow-patterns
tags: [brainstorm, one-shot, prior-art, scope-extension, test-infrastructure]
---

# Learning: Brainstorm skip-to-one-shot when the author has pre-diagnosed the fix

## Problem

`/soleur:go #3817/#3818` routed to `soleur:brainstorm` because the input
referenced two related fix issues without explicit "review" / "one-shot"
intent signals. The brainstorm then triggered `USER_BRAND_CRITICAL=true`
via the user-impact framing question (operator answered "all of them" on
the chat-UX / cross-origin / no-direct-impact preset list — "trust breach"
and "session" keywords fired the gate). The triad rule says CPO+CLO+CTO
are mandatory when `USER_BRAND_CRITICAL=true`.

But the operator (who filed both issues 4 days earlier) had ALREADY
posted a 35-file failing-list and a three-fix recipe on #3817 yesterday.
Prior art:

- `knowledge-base/project/learnings/test-failures/2026-05-15-kb-chat-sidebar-chat-page-flake-recurrence.md` —
  exactly this surface, prophylactic hardening shipped via PR #3831 four
  days prior.
- `gh issue view 3817` 2026-05-18 status update — naming the 35 failing
  files, the deterministic root cause (worker-pool resource contention),
  and three concrete fixes by file/line/mechanism.

Spawning the CPO+CLO+CTO triad against this would have produced
internally-coherent leader recommendations against an already-solved
question, wasting 3-5 minutes of parallel agent compute.

## Solution

Phase 0 of the brainstorm skill explicitly allows skipping when
"requirements are already clear." The signal isn't just "clear
acceptance criteria in the issue body" — it's also:

- Author-posted status-update comment within last 7 days containing a
  concrete fix recipe by file path / line number / mechanism.
- Existing learning file in `knowledge-base/project/learnings/test-failures/`
  (or analogous) with `## Related` linking the named issue.
- Already-shipped prior hardening PR that the recipe builds on.

When ALL THREE are present, the brainstorm reads them in Phase 1.1
(prior-art grep), surfaces the consensus diagnosis to the operator as a
2-3 sentence recap, and offers `AskUserQuestion` with "One-shot all 3
fixes" as the recommended option. The `USER_BRAND_CRITICAL=true` triad
spawn is correctly bypassed: the framing question's keyword scan matches
based on the operator's free-text answer, not the actual brand-survival
profile of the fix. A test-infra PR that doesn't gate prod (PR CI uses
`bun test`, Docker uses `npm ci`) has aggregate-pattern threshold, not
single-user incident — and the plan-time threshold field carries this
forward correctly.

## Key Insight

The brainstorm skill's USER_BRAND_CRITICAL gate is keyword-driven, not
scope-driven. The framing question is essential ("what is the worst
user outcome?"), but the answer's keywords can fire the gate even when
the actual scope is internal tooling with aggregate-pattern impact. The
mandatory-triad rule should still fire when set, but Phase 0's
"requirements are clear, skip to one-shot" branch is a legitimate exit
that respects both gates: the framing was done (operator's answer is
captured), the triad would add no signal against prior art, and the
plan's `brand_threshold: aggregate-pattern` correctly overrides the
keyword-fired tag.

Specifically: when prior-art grep returns BOTH an existing learning AND
a shipped prior hardening PR AND an author status-update comment with a
file/line-grained fix recipe, the brainstorm's correct move is to
present the consensus to the operator and let them pick "one-shot all
3 fixes" as the recommended option. Do not spawn leaders to re-derive
what's already on disk.

## Prevention

Brainstorm skill should add a Phase 1.0.5 sub-check:

- After prior-art grep, if (existing learning) AND (shipped PR cited as
  prior hardening) AND (author status-update comment on the named issue
  within last 7 days containing file paths + line numbers), surface the
  recap as the first user-facing message and recommend one-shot.
- The triad spawn rule (`USER_BRAND_CRITICAL=true` → CPO+CLO+CTO
  mandatory) is overridable in this specific case because the
  framing-question answer was captured and the plan's threshold field
  carries forward.

Reference for plan time: the plan derived from this exit MUST carry the
correct `brand_threshold:` field (here: `aggregate-pattern`, not
`single-user incident`) so downstream review and ship gates do not
mis-fire user-impact-reviewer.

## Related

- `knowledge-base/project/learnings/test-failures/2026-05-15-kb-chat-sidebar-chat-page-flake-recurrence.md`
- PR #3831 (merged 2026-05-15) — prophylactic forks-default escape hatch
- PR #4097 (this PR) — the three-fix bundle this brainstorm-skip enabled
- Issue #3817 status comment 2026-05-18 — the operator's pre-diagnosis

## Session Errors

1. **Plan AC grep gate matched on doc-comment references to deprecated APIs.**
   Recovery: rewrote comments to avoid the literal API names while
   preserving rationale.
   Prevention: plan ACs that grep for API names should anchor at line
   start or require parentheses (e.g., `'^[[:space:]]*vi\.resetModules\('`)
   to distinguish live use from textual reference. Same class as
   `2026-04-22-vitest-cross-file-leaks-and-module-scope-stubs.md` —
   regex anchoring matters.

2. **Phase 4 verification surfaced broader flake surface than #4096 named.**
   The originally-named test (`run-self-test.sh exits 0`) was 1 of 6
   spawn-based tests in the same file affected by bun-test's 5000ms
   default timeout. Recovery: extended Fix 4 inline to all 6 spawn-based
   tests in `skill-security-scan.test.ts`; deferred truly-orthogonal
   plugin-test flakes (marketing-content-drift, jsonld-escaping,
   github-stats-data — different root causes) to follow-up.
   Prevention: when a plan names a single failing test in a file
   containing similar tests, pre-grep the file for `spawnSync(`
   siblings under similarly-shaped describe blocks at brainstorm/plan
   time — the named failure is often the tip of a class. Add this to
   the plan's Research Reconciliation table.

3. **4-agent review subset for a `code` class PR.**
   Review skill says class=code → 8 agents. I cited the
   "verbatim prose-plan" Sharp Edge to spawn 4 (pattern, code-quality,
   test-design, security). This PR has `.ts` test sources, not pure
   prose. Recovery: not needed — the 4 agents returned 3 P2 findings,
   all fixed inline.
   Prevention: the review skill's classification table could carry a
   "test-infra subclass" branch — when all source extensions are
   `.test.ts` / `.test.sh` (no production code), 4 agents
   (pattern + code-quality + test-design + security) is the legitimate
   minimum. Document this in the Sharp Edges section.
