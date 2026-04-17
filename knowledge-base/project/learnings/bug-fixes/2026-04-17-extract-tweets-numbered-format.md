---
date: 2026-04-17
category: bug-fixes
module: content-publisher
problem_type: authoring_parser_contract
severity: P2
pr_reference: "#2496"
---

# extract_tweets silently collapsed a 5-tweet thread to 1 tweet (2026-04-17)

## Problem

The 2026-04-17 repo-connection launch produced a distribution content file whose `## X/Twitter Thread` section used the numbered authoring convention (hook, then `2/ ...`, `3/ ...`, `4/ ...`, `5/ ...`). `content-publisher.sh` at cron time logged `[ok] X thread posted successfully (1 tweets)` and went green — silently posting only the hook. Tweets 2-5 were concatenated into the hook's buffer and dropped when it exceeded 280 chars (the last-tweet path truncated or X rejected silently).

## Root Cause

`social-distribute` Phase 5.2 prescribes two authoring formats:
- Labeled: `**Tweet N (label) -- N chars:**` preceding each tweet (dropped at extraction).
- Numbered: hook + subsequent tweets prefixed `N/ ` on a fresh line (prefix preserved).

`extract_tweets` only split on `^\*\*Tweet [0-9]` — the labeled convention. When the skill emitted the numbered convention (which it's allowed to), no split points existed; the entire section became a single blob. The publisher's success branch then reported "posted successfully (1 tweets)" because the buffer contained exactly one record.

Two classes of contract bug in one:
1. **Parser didn't match the skill's documented output.** Two documented authoring formats, one parser branch.
2. **No assertion on tweet count vs. section structure.** If `extract_tweets` produces 1 record but the section contains `2/`, `3/` markers, that's a tell — the parser silently accepts it.

## Solution

Two-mode extractor:

1. **Mode detection** scans the section for `^[[:space:]]*\*\*Tweet[[:space:]]+[0-9]`. Present → labeled mode (original behavior, regression-guarded). Absent → numbered mode.
2. **Numbered mode** tracks an expected sequence number (starts at 2). Only lines matching `^N/ ` where `N == expected` trigger a split; the prefix is preserved. Sequence guard prevents prose like `1/3 of devs` or `4/5 users say` from being sliced mid-tweet.
3. **Leading-whitespace tolerance** in the labeled regex defends against indented labels inside lists.

Tests: 4 happy-path + 1 labeled-format regression + 4 edge cases (single-tweet, prose fraction guard, hook-as-`1/`, labeled-with-`N/`-in-body). All pass.

## Key Insight

**When a producer has two valid output formats, the consumer must accept both OR the producer must be forced to one.** This extractor trusted that the producer would always label — the skill's own docs explicitly allowed both. The publisher should also emit a *warning-with-Sentry* (per `cq-silent-fallback-must-mirror-to-sentry`) if `extract_tweets` returns 1 record but the section has 2+ `N/` or `**Tweet N` markers: a mismatch between parsed structure and raw signal is a legit silent-fallback and deserves mirroring. Out of scope for this PR; good candidate for follow-up.

## Session Errors

- **Markdownlint corrupted hashtags in the test fixture.** `#solofounder #buildinpublic` was rewritten to `# solofounder #buildinpublic` (space after first `#`, which semantically converts it to a heading). Recovery: added `<!-- markdownlint-disable-next-line MD018 -->` pragma (same pattern used in live distribution content files). **Prevention:** When writing new distribution-content test fixtures, copy the pragma pattern from an existing live file rather than relying on markdownlint's fix output.

## Cross-references

- PR #2491 — the Liquid-marker leak that first exposed the broken announcement; surfaced this bug during retroactive remediation.
- `knowledge-base/project/learnings/bug-fixes/2026-04-17-distribution-content-liquid-marker-leak.md` — sibling learning.
- `plugins/soleur/skills/social-distribute/SKILL.md` Phase 5.2 — the authoring spec that was already correct; the parser just didn't match it.
