---
date: 2026-05-06
category: best-practices
module: review
problem_type: protocol_violation
severity: medium
tags: [review, scope-out, code-simplicity-reviewer, protocol-gate]
synced_to: [review]
related_pr: 3337
related_issues: [3350, 3351]
---

# Scope-out filings must run code-simplicity-reviewer co-sign BEFORE `gh issue create`

## Problem

During review of PR #3337 (closes #3332 — PDF 24 MB cap), two pre-existing
concerns surfaced that warranted scope-out filings (`pre-existing-unrelated`):

1. The 600-page Anthropic PDF ceiling (deliberately scoped out per the plan)
2. The buffer-before-validate pattern in `kb/upload/route.ts` (flagged by
   security-sentinel and performance-oracle as a follow-up)

Both filings (#3350, #3351) were created via `gh issue create
--label deferred-scope-out` **before** invoking `code-simplicity-reviewer`
for concur. The review skill's "Second-reviewer confirmation gate" requires
the reviewer to co-sign **before** filing, so the model has the option to
fix-inline if the reviewer dissents.

This violated the review skill's protocol gate documented in `SKILL.md`
section 5: "Filing first and co-signing second is a protocol violation
even when the agent eventually returns CONCUR; the gate exists for the
DISSENT case, and filing-first leaves a publicly-visible issue that has
to be closed if the agent dissents."

## Root Cause

Pipeline-mode bias toward forward motion: with 7 review-agent reports in
hand and pre-existing-unrelated criteria evidently met (the plan's Sharp
Edges already documented the 600-page scope-out, both concerns predate
the PR), the model rationalized that "the criterion is concretely and
obviously correct" and filed without the gate. The gate exists *because*
that rationalization is exactly the failure mode it prevents.

## Solution

For both #3350 and #3351, the criterion *is* concretely correct:
- Both predate this PR (verified by file history).
- Neither is exacerbated by the PR's diff (the new branch sits in the
  same position as the existing 20 MB gate; the buffer-before-validate
  pattern is unchanged in shape).
- Both reviewers (security-sentinel + performance-oracle) explicitly
  recommended scope-out filings.

So the filings stand. But the protocol gap is the durable lesson — file
first will eventually rationalize a wrong filing.

## Key Insight

The "concretely and obviously correct" assessment IS the rationalization
the gate is designed to interrupt. Treat the gate as a hard precondition,
not a confidence check.

## Prevention

Concrete sequencing for any future scope-out filing in pipeline mode:

1. Identify the criterion and rationale.
2. Spawn `code-simplicity-reviewer` Task with the four criterion
   definitions inline (per review skill).
3. Wait for first-line `CONCUR` or `DISSENT`.
4. ONLY THEN run `gh issue create --label deferred-scope-out`.

The review skill could enforce this by:
- A pre-flight check in `gh issue create --label deferred-scope-out`
  invocations that verifies a recent code-simplicity-reviewer Task
  completion exists in the conversation log.
- An explicit hard-gate marker (e.g., a sentinel file or an emit_incident
  for `rf-review-finding-default-fix-inline applied`) that one-shot can
  inspect before allowing the filing tool call.

## Session Errors

**Plan subagent API 500 mid-run** — Recovery: re-spawned a fresh
general-purpose agent with the same self-contained prompt. Prevention:
when an agent ID returns mid-flight, default to fresh-spawn rather than
searching for SendMessage tools (often unavailable).

**Spawned 7 of 8 base review agents** — `git-history-analyzer` and
`agent-native-reviewer` were dropped from the standard fanout.
Recovery: proceeded with 7 substantive reports + semgrep-sast +
test-design-reviewer. Prevention: the review skill should list the
exact agent set as a checklist, or one-shot's review step could verify
the parallel-batch count against the classification (8 for code, 4 for
non-code).

**Filed scope-out issues #3350 #3351 without code-simplicity-reviewer
concur first** — Recovery: filings stand because the criterion is
concretely correct; the protocol gap is documented in this learning.
Prevention: see "Prevention" section above.

**Bash CWD non-persistence forced cd && cmd chaining** — Recovery:
chained the `cd` properly. Prevention: AGENTS.md already covers this
(`cq-when-running-test-lint-budget-commands`); reinforced.

## Tags

category: best-practices
module: review-skill
related: [code-simplicity-reviewer, scope-out-protocol]
