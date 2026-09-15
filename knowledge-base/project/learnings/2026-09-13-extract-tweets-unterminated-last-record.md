# Learning: extract_tweets' last record is unterminated — `while read` drops it, and push the branch before the review panel

## Problem

While validating a distribution-content file for PR #8121, two ad-hoc checks over `extract_tweets` (scripts/content-publisher.sh) silently under-counted:

1. Pre-compaction: a malformed-thread counterexample counted newline-separated records instead of the publisher's RS-separated (`\x1e`) tweets, reporting `malformed count: 2` for a single unnumbered block (true count: 1).
2. Post-compaction: `extract_tweets "$F" | while IFS= read -r t; do …` printed tweets 1 and 2 and dropped tweet 3, because the function's final record is not newline-terminated and POSIX `read` returns non-zero on the last unterminated "line" — the loop body never runs for it.

Both produced a count that read as a result while measuring the wrong tokenization. The publisher's own consumers are awk-based and unaffected; the foot-gun bites anyone doing ad-hoc `while read` validation of a thread's tweet count — exactly the check every scheduled-content PR runs.

Separately: the review panel was spawned while the branch was unpushed (`feat-announce-devin-support` remote held only the init commit). git-history-analyzer caught it as a finding, but the violation of `rf-before-spawning-review-agents-push-the` was mine — the skill's Step 1 setup checklist never says "push".

## Solution

For tweet-count validation, count the publisher's RS separators, never `while read` over the stream:

```bash
extract_tweets "$F" | awk 'BEGIN{RS="\x1e"} {gsub(/^\n+|\n+$/,"",$0); if(length($0)>0) printf "tweet %d: %d chars\n", NR, length($0)}'
```

For the push gap: `git push` ran immediately when the agent reported the remote held only the init commit; a one-line step added to review SKILL.md Step 1 pushes before the panel spawns.

## Key Insight

Two instances, one root: **a counting instrument keyed on the wrong separator is a result that never happened.** `while read` measures newline-terminated lines; `extract_tweets` emits `\x1e`-separated records. The fix is not a better loop — it is counting the delimiter the producer actually uses. (Same class as "grep -c counts lines, a second literal on one line evades it" — the token a check iterates must be the token the format defines.)

## Session Errors

- **Malformed-thread counterexample counted records not tweets** — Recovery: RS-aware recount (true: 1) — Prevention: count `extract_tweets` output by `\x1e`, never by `while read` or `\n`.
- **`while read` dropped the last (unterminated) tweet in re-validation** — Recovery: same RS-aware awk — Prevention: same as above; note `content-publisher.sh` is a declared non-goal of content PRs, so the contract stays as-is.
- **Review panel spawned before `git push`** — Recovery: pushed on the agent's P1 finding — Prevention: review SKILL.md Step 1 now carries an explicit push step (`rf-before-spawning-review-agents-push-the`).
- **`ls agents/` returned nothing** — Recovery: `find` located `agents/engineering/<area>/` subdirs — Prevention: agent files are namespaced two levels deep, not flat.
- **Forwarded (plan phase):** planning subagent had no Task tool (fan-outs inlined per harness adapter); `git push` skipped by pipeline scope (same root as the review-panel deviation); lefthook regenerated `INDEX.md` inside the feat commit (benign); an elided learning path was expanded during deepen-plan.

## Tags

category: workflow-issues
module: content-publisher / review-skill
