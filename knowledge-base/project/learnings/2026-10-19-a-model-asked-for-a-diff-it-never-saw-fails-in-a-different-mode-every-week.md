---
title: a model asked for line-numbered output over a file it was never shown fails in a different mode every week -- fix the contract, not the mode
date: 2026-10-19
category: integration-issues
module: apps/web-platform/server/inngest/functions/cron-compound-promote.ts
tags: [compound-promote, llm-contract, server-derived-diff, git-apply, spawn-close-vs-exit, sentry-message-path, followthrough-probe]
issue: 10552
pr: 10553
---

# Learning: stop asking the model to author what the server can derive

## Problem

The weekly `cron-compound-promote` proposed two clusters on 2026-09-27, 10-04 and 10-11 and opened zero PRs: every
proposal was refused `diff-underivable-apply`. The three runs failed `git apply` in three different ways (no `@@`
hunk; hunk counts that disagreed with the body; an `@@` line that was not a parseable header). The prompt gave the
model only the first ten lines of each learning and the byte count of the target, never the target, yet the schema
required `proposed_diff_unified`, a unified diff with real line numbers and real context lines.

## Solution

Take the hunk away from the model. Phase 2 shows it the real file text and asks for an anchor line (copied
verbatim, must occur exactly once) plus the lines to insert; the server validates both, splices into the HEAD text and
derives the diff with `git diff --no-index --no-prefix`. Every downstream gate reads the same
`proposed_diff_unified` it always read, and the three observed modes cannot reach `checkDiffPaths`.

## Key Insight

A per-mode repair (`--recount` for one mode, a header normaliser for another, a hunk synthesiser for the third) is a
denylist over a string the model writes and still cannot make context lines match a file it never saw. When an output
is *derivable*, deleting the model's authorship of it removes the whole failure class. The price is that the text the
model DOES still write now lands in an always-loaded corpus, so the content constraints (printable ASCII, caps, one
new id per line, no `hr-`/`wg-` token anywhere, no fence/comment/link/URL, credential shapes) are the real control and
need their own adversarial review: a 9-seat panel found the first version of that guard bypassable with a second
`[id: ...]` token on one line, because a greedy regex checked only the last one.

## Session Errors

1. **`gh issue create` blocked by the filing hook** (unreadable `$VAR` body path, missing `--milestone`, no filing
   exit). Recovery: write the body with the Write tool first, pass a literal absolute path, add `--milestone` and
   `--label meta/machinery`. **Prevention:** none needed (the hook worked); one-off.
2. **A guard regex that checked one id per line greedily** (`^- .*\[id: (?!hr-)(...)\]`), shipped by me and found
   independently by three seats. Recovery: count `[id` tokens, require exactly one, refuse any `hr-`/`wg-` token.
   **Prevention:** for any "this line must not contain X" guard, test the line with X present *twice* and in prose.
3. **Probe input unreachable under the sweeper** (`FT10552_DEPLOY_FLOOR` was required but the sweeper runs probes under
   `env -i` and forwards only `secrets=` names bound in the workflow `env:`), so the probe would exit 3 forever.
   Recovery: derive the floor from git (committer time of the adding commit + 3h) with the env var as an override.
   **Prevention:** routed into `followthrough-convention.md` (a probe's required inputs must be derivable or
   forwardable under `env -i`).
4. **Sentry `op`/`cause` tags silently dropped**: `reportSilentFallback(new Error(...))` logs first and the pino
   mirror captures the same Error, so Sentry drops the tagged capture (#8629, already documented in
   `anthropic-credit.ts`). Recovery: `reportSilentFallback(null, { message, tags })`. **Prevention:** already covered
   by the in-code comment; the unit tests now assert the `null` + `tags` call shape.
5. **`spawnGitCapture` resolved on `exit`, not `close`** (pre-existing): stdout can be undelivered at `exit`, so under
   load a successful `git ls-tree` read as empty ("path absent") and a test flaked only when run beside other files.
   Recovery: resolve on `close`; a source-pinned test forbids any `exit` listener. **Prevention:** the sibling
   `cron-weekly-analytics.ts` and `cron-content-vendor-drift.ts` had the same listeners; fixed in this PR (three
   one-line changes, 393 sibling tests green) after the filing gate refused a separate issue for a fix this small.
6. **Two tests of mine were wrong, not the code** (an append row used a non-bullet for the rules file; a hand-written
   hunk with wrong counts). **Prevention:** generate expected diffs with git, never by hand; one-off.
7. **Mutation harness prefix match** (`M1` also selected `M10..M12`). One-off.
8. **Stop hook fired twice on closing text naming a future action.** Recovery: end with one `Paused:` sentence.
   **Prevention:** already enforced by the hook.
9. **CTO spawn budget (2) exhausted before two late technical rows were written**, so they were recorded as prose
   dispositions rather than ruling rows. **Prevention:** batch every plan-time technical row into the first spawn.

## Tags

category: integration-issues
module: apps/web-platform/server/inngest/functions/cron-compound-promote.ts
