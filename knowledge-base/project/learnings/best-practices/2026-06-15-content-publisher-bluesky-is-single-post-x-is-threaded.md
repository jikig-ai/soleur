# Learning: content-publisher posts Bluesky as ONE post; only X is thread-split

## Problem

Extending `feature-tweet` to cross-post ship tweets to Bluesky, the natural
assumption was that Bluesky mirrors X — write a `## Bluesky` section with `2/`,
`3/` numbered posts the way `## X/Twitter Thread` does, and the publisher splits
them. It does not. `content-publisher.sh`:
- **X:** `extract_tweets` (≈:264) splits the `## X/Twitter Thread` section on
  `N/ ` boundaries and posts each as a reply-chained tweet (280-char each).
- **Bluesky:** `post_bluesky` (≈:683) takes the ENTIRE `## Bluesky` section as a
  single `$content` string and posts it as ONE post, truncating the whole section
  at 300 chars (`cut -c1-297` + "…"). There is NO `extract_tweets` equivalent.

So a `2/`-numbered Bluesky "thread" authored by analogy to X would be
concatenated into one post and silently truncated — the `2/` markers would appear
as literal text inside a single post, then cut at 300 chars.

## Solution

For Bluesky, author a SINGLE self-contained post ≤300 chars (the whole `## Bluesky`
section), no `2/`/`3/` prefixes. The `feature-tweet` SKILL.md Step 4 + template
now prescribe exactly that. The validator (`validate-tweet-draft.sh`) requires a
non-empty `## Bluesky` section (structural only — it does not length-check, by
design, same as the pre-existing X 280 path; length is enforced at generation).

## Key Insight

When a multi-channel publisher "supports" a channel, "supported" is not
"symmetric." Before mirroring channel A's authoring format onto channel B, read
B's actual post function — per-channel post/limit/threading semantics diverge
(X = reply-chained thread split on `N/`; Bluesky = one post, hard 300-char
truncation). The channel→section heading map (`extract_section`) being symmetric
does NOT imply the post path is.

Process note: this work targeted an EXISTING open issue (#5022, "Bluesky channel
for short-form ship tweets", deferred from #5021), not a new sub-issue. The
one-shot collision gate only scans `#N` in the invocation args — when those args
describe *new* work in prose (no `#N`), search `gh issue list --state open` for
the same scope before filing, so a deferred-follow-up issue gets closed rather
than duplicated.

## Tags
category: best-practices
module: scripts/content-publisher.sh, plugins/soleur/skills/feature-tweet
