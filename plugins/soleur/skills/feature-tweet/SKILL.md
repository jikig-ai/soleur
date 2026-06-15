---
name: feature-tweet
description: "This skill should be used when converting a merged, verified-live PR into a draft short-form X post (single tweet or up-to-3-tweet thread) for operator approval."
---

# feature-tweet

Convert a feature **just shipped to production** (a merged PR, verified live)
into a **draft** short-form X post — written to the existing
`knowledge-base/marketing/distribution-content/*.md` format and drained by the
existing `content-publisher.sh` cron. No new publishing path; nothing
reaches X until the operator flips `status: draft` → `scheduled`.

Invoked by `/soleur:postmerge` after its production-health check passes (only
tweet what actually deployed), and runnable standalone as a catch-up path:

```
/soleur:feature-tweet #<pr>
```

The brand-critical floor is the deterministic, fail-closed eligibility filter
`tweet-eligibility.sh` (under the repo's scripts/lib directory). A forbidden PR (security/infra/non-product/
unlabeled) is excluded **before** any draft is generated, so it never reaches
the operator's approval queue.

## Arguments

- `#<pr>` (required) — the merged PR number. Accept `123` or `#123`.
- `--headless` — non-interactive; never posts (drafts only, same as default).

## Step 1 — Eligibility (fail-closed, run FIRST)

```bash
bash scripts/lib/tweet-eligibility.sh <pr>
```

- Exit 0 + `eligible` → continue.
- Exit non-zero + `excluded: <reason>` → **stop. Write no file.** Print the
  reason and exit. This is a silent no-op from the operator's perspective (no
  draft, no error escalation) — exclusion is the designed outcome, not a fault.

Never second-guess or override the filter. Any uncertainty (missing labels,
`gh` error, deny label, deny path) is `excluded` by design.

## Step 2 — Idempotency

Search existing drafts for this PR before generating:

```bash
grep -rl 'pr_reference: "#<pr>"' knowledge-base/marketing/distribution-content/ 2>/dev/null
```

If a file matches, **no-op** with a message naming the existing path — do not
overwrite an operator-edited draft.

## Step 3 — Fetch PR context

```bash
gh pr view <pr> --json title,body,url
```

Read the author identity for any copy that references a person from
`plugins/soleur/docs/_data/site.json` → `author.name` ("Jean Deruelle"). **Never
infer a name** from the PR; contributor names are PII and are excluded.

## Step 4 — Generate the X thread AND the Bluesky post (sanitized, voice-aligned)

Generate copy for BOTH channels (the publisher cross-posts to X and Bluesky).
Follow `knowledge-base/marketing/brand-guide.md` → `### X/Twitter` and its
`#### Ship Tweets (feature-launch)` sub-section. Hard rules:

- **X shape:** single tweet (hook only) OR a numbered thread of **at most 3**
  tweets. Tweet 1 = the hook (no prefix, no "thread" announcement). Tweets 2–3
  are prefixed `2/`, `3/` on a fresh line (the canonical numbered format the
  publisher's `extract_tweets` parses).
- **X limit: 280 characters per tweet**, enforced during generation, not trimmed
  after.
- **Bluesky shape + limit:** a **single post**, **300 characters total** for the
  whole `## Bluesky` section. The publisher (`post_bluesky`) posts the entire
  section as ONE Bluesky post — it does NOT split a numbered thread (no
  `extract_tweets` equivalent), and truncates the section at 300 chars. So write
  one self-contained post; do NOT use `2/`/`3/` prefixes here. Adapt the copy to
  Bluesky — do NOT clone the X hook verbatim: Bluesky carries no hashtags
  (brand-guide `### Bluesky`). Lead the same one buyer benefit in plainer register.
- **Sanitization (mandatory — benefit only), applied to BOTH channels:**
  - No implementation/diff detail. State the user-facing benefit, not how it was
    built.
  - **No contributor names or author attribution** (PII; no marketing consent).
  - **No customer names** — run an explicit customer-name/NDA scan over the PR
    title and body; if a proper noun could be a customer, omit it.
  - **No naked numbers** — any statistic must be verifiable from the PR or
    omitted.
- Present-tense "just shipped X" framing; lead the build-in-public peer voice,
  land one concrete buyer benefit. General register (plain language).
- Links (if any) go in the **final** post of each channel only. A ship tweet has
  no blog, so `blog_url` is omitted entirely.

## Step 5 — Write the draft file

Path: `knowledge-base/marketing/distribution-content/<YYYY-MM-DD>-<slug>.md`
where `<slug>` is the PR title with its `feat(...)` prefix stripped and
slugified.

Frontmatter + body:

```markdown
---
title: "<concise benefit-framed title>"
type: feature-launch
publish_date: ""
channels: x, bluesky
status: draft
pr_reference: "#<pr>"
issue_reference: "#<issue>"   # only if the PR closes one; else omit
---

<!-- To publish: set BOTH publish_date AND status: scheduled -->

## X/Twitter Thread

<hook tweet>

2/ <body tweet>

3/ <final tweet, link only if applicable>

## Bluesky

<single adapted post — ≤300 chars total, no hashtags, no 2//3/ prefixes>
```

`publish_date: ""` + `status: draft` is the intentionally-parked state
(`content-publisher.sh` skips it). `channels: x, bluesky` cross-posts to both —
the publisher requires one body section per channel, so the `## X/Twitter Thread`
AND `## Bluesky` sections are BOTH mandatory (the structural gate in Step 6
rejects a draft missing either).

## Step 6 — Structural assertion (skill-owned gate — NOT lint)

```bash
bash scripts/lib/validate-tweet-draft.sh <file>
```

Asserts a non-empty `title`, `status: draft`, a `channels` value including BOTH
`x` and `bluesky`, and non-empty `## X/Twitter Thread` AND `## Bluesky` sections.
On non-zero exit, **delete the file** (`rm -f <file>`) and abort — leave no
partial draft. This is the field/heading gate; the Liquid linter validates
neither.

## Step 7 — Lint (Liquid markers)

```bash
bash scripts/lint-distribution-content.sh <file>
```

On non-zero exit, delete the file and abort.

## Output

On success, print the draft path and the explicit operator instruction:

> Draft written to `<path>`. To publish: set BOTH `publish_date` and
> `status: scheduled`. The existing content-publisher cron posts it on date.

Headless mode never posts — it only writes the draft and prints the path.

## Multi-PR contract (v1)

One tweet per eligible PR. `/soleur:postmerge` passes its single bound PR
number; batching multiple PRs from one deploy is deferred. A `/soleur:merge-pr`-
only flow bypasses the postmerge hook by design — run standalone
`/soleur:feature-tweet #<pr>` as the recovery path.
