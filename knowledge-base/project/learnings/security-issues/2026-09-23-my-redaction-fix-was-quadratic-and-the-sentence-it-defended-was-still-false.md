---
title: "My redaction fix was quadratic, its class claim was false, and the sentence it defended was still false"
date: 2026-09-23
category: security-issues
module: apps/web-platform/server (observability, logger, sentry-scrub, pii-redact)
tags: [redaction, redos, privacy-policy, gdpr, observability, mutation-testing]
issue: 8532
pr: 8617
---

# Learning: a value-redaction fix has three independent ways to be wrong

## Problem

`docs/legal/privacy-policy.md` promised "the plaintext recipient address is never
stored". A refused outbound send broke it: two `OutboundComplianceError` throws
interpolated the address, and the `email_send` catch mirrored the error through
`reportSilentFallback` into journald (web host root disk), Better Stack and
Sentry (the issue title). The first fix removed the interpolations and added an
emitter-side redaction regex. An 11-agent review then found that fix wrong in
three independent directions.

## Solution

1. **Cost.** The redaction regex `[A-Za-z0-9._%+'-]+@…` had no left anchor, so
   the engine retried from every position in a long run with no valid address
   after it: O(n²), measured at 13 s on 64k characters and ~41 s on 100k, on every
   silent-fallback emit. Six of eleven agents measured it independently. Fixed
   with a run-start lookbehind `(?<![local-char])` (1-3 ms on the same inputs)
   plus a fail-closed 256 KiB input cap, pinned by adversarial timing tests.
2. **Reach.** The comment said "before ANY sink". It covered `Error.message`,
   `stack` and `cause` in three emitters. It missed plain-object vendor errors
   (supabase-js and Resend return objects, not Errors), own properties
   (PostgREST `details`), `AggregateError.errors`, direct `log.error({ err })`
   calls (captured raw by `logger.ts` mirrorToSentry), and direct
   `Sentry.captureException` calls. It could also THROW (non-string message,
   null stack, DOMException), turning an error report into a crash, and it fell
   open past its depth cap. Fixed at three seams: a leaf `server/pii-redact.ts`
   (never throws; walks every shape; maps cycles onto the copy), the
   `logger.ts` `logMethod` hook (every logger and child, before mirrorToSentry),
   and a value layer in `sentry-scrub.ts` (every string in every event).
3. **Truth.** Even with every log sink clean, the sentence stayed false: the
   recipient and body persist in the drafting agent conversation (`messages`,
   SDK session JSONL, #3418), in an aborted turn's `completed_actions` summary,
   and in the offline review-gate email Resend keeps for 30 days. Code fixed the
   last two; the CLO scoped the published sentence to "our outbound-email
   records", with dated Corrected notices in three published documents.

## Key Insight

For a redaction fix, ask three separate questions and test each separately:
**what does it cost on hostile input**, **what shapes reach the sink without
passing through it**, and **is the promise it defends true of the whole system
or only of the path you fixed**. A green suite answers none of them. The third
is a legal question, not a code one: route it to the CLO before the PR is
ready, because "fix the code, keep the sentence" silently assumes the code is
the only store.

## Session Errors

1. **My first redaction regex was O(n²).** Recovery: run-start lookbehind + input
   cap + timing tests. **Prevention:** any regex run over unbounded log or error
   text gets an adversarial timing row (100k-char run, no match) in the same
   commit that adds it; see the review-skill routing bullet added with this
   learning.
2. **A comment claimed the fix covered "ANY sink".** Recovery: three-seam fix and
   narrowed comments. **Prevention:** write a coverage claim only after
   enumerating the emitters by grep (`captureException|log\.error\(\{ *err`),
   and name the ones not covered.
3. **The plan assumed the code fix would make the published sentence true.**
   Recovery: CLO ruling scoped the sentence. **Prevention:** when a plan's
   premise is "fix the code, keep the sentence", enumerate every store of the
   subject value (transcripts, notification payloads, persisted summaries), not
   only the path that surfaced the defect.
4. **M10 survived the mutation battery.** Every KEEP fixture had a single-digit
   last version segment, which the 2-char TLD minimum already rejected, so the
   digit-free-TLD rule was unpinned. Recovery: `lodash@4.17.21` fixtures.
   **Prevention:** fixture the case where only the rule under test decides.
5. **`git merge --ff-only` failed on the plan branch**, which had pushed commits
   diverging from main. Recovery: merged `origin/main`. **Prevention:** one-off;
   use a merge on any pushed branch rather than a rebase.
6. **A 1,000-run `gh api` soak scan exceeded the 600 s foreground limit.**
   Recovery: it continued in the background. **Prevention:** launch any
   per-run API loop over more than ~200 runs with `run_in_background` from the
   start.
7. **Two waiting turns closed with a future-tense commitment**, tripping the
   unkept-promise stop hook. **Prevention:** a turn that waits on agents ends
   with an explicit `<stop>BLOCKED: …</stop>` naming what it waits on.
8. **The CLO's first ruling used a blockquote supersession form** the Article 30
   register does not use; it corrected itself to in-cell Superseded/AMENDMENT
   markers. **Prevention:** ask the CLO to read the target file's amendment
   convention before drafting text for it.

## Tags

category: security-issues
module: apps/web-platform/server
