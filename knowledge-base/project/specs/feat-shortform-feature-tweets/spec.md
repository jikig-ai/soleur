---
feature: shortform-feature-tweets
lane: cross-domain
brand_survival_threshold: single-user incident
status: draft
issue: 5021
date: 2026-06-08
branch: feat-shortform-feature-tweets
pr: 5017
brainstorm: knowledge-base/project/brainstorms/2026-06-08-shortform-feature-tweets-brainstorm.md
---

# Spec — Short-Form Feature Tweets from Shipped PRs

## Problem Statement

The only route to social distribution today is `social-distribute`, which makes a **long-form blog
post a hard prerequisite** (`social-distribute/SKILL.md:35`). `changelog` analyzes merged PRs and
classifies user-facing features by label but emits only an internal Discord changelog. So a feature
"just shipped to production" cannot become a short-form X post unless someone first writes a blog —
which a solo founder rarely does. The result is a chronic cadence gap: social posting is coupled to
blog-writing instead of to ship events that already happen.

## Goals

1. A new `soleur:feature-tweet` skill that converts a merged PR into a **draft** short-form X post
   (single tweet or 2–3 tweet thread) written to the existing `distribution-content` format — no blog required.
2. `/soleur:postmerge` invokes the skill **after its production-health check passes**, so only
   verified-live features are drafted. Standalone `/soleur:feature-tweet #<pr>` works as a catch-up path.
3. Reuse the existing `content-publisher.sh` cron pipeline, `extract_tweets` parser, and
   `lint-distribution-content.sh` gate verbatim — no new publishing path.
4. Enforce the CLO brand-survival guardrails (exclusion floor + approval gate + sanitization) so a
   single bad public tweet cannot ship.
5. Extend `brand-guide.md`'s `### X` channel notes with ship-tweet voice (lead build-in-public peers,
   hook buyers with a concrete benefit); the skill validates drafts inline against it.

## Non-Goals

- Straight-through auto-posting to X (draft-only day one; auto-publish needs paid X API + legal review).
- X paid API tier / browser thread-discovery (deferred in `2026-03-10-x-engage-dogfood-brainstorm.md`).
- Per-merge auto-trigger on every PR (postmerge + user-facing label gating only).
- Multiple tweet variants per platform (publisher is one-section-per-channel).
- Image/screenshot generation for tweets.
- A separate brand-voice-reviewer agent (inline brand-guide validation only).

## Functional Requirements

- **FR1 — Generator skill.** `soleur:feature-tweet` accepts a merged PR number (or list), reads PR
  title/body/labels via the shared helper (TR2), and produces a draft
  `knowledge-base/marketing/distribution-content/<YYYY-MM-DD>-<slug>.md`.
- **FR2 — Output format.** The file carries frontmatter (`title`, `type: feature-launch`,
  `publish_date: ""`, `channels`, `status: draft`, `pr_reference: "#<n>"`) and a single
  `## X/Twitter Thread` section in **canonical numbered format** (hook = tweet 1; subsequent tweets
  prefixed `2/`, `3/`). Single-tweet output = hook only.
- **FR3 — Fail-closed exclusion (mandatory).** PRs labeled `security`, `type/security`, `infra`,
  `internal`, or `dark-launch`/flagged, OR touching path globs (auth, migrations, secrets, CI/infra),
  are excluded. **Unlabeled or ambiguous PRs default to excluded.** Only `type/feature` + `user-facing`
  PRs are eligible.
- **FR4 — Content sanitization (mandatory).** Generated copy states user-facing benefit only — no
  implementation/diff detail, no contributor PII/author attribution, no customer names; run an explicit
  customer-name/NDA scan that label-filtering cannot catch.
- **FR5 — Approval gate (mandatory).** Files are written `status: draft`. The operator flips
  `publish_date` + `status: scheduled` to release; the skill never queues straight-through.
- **FR6 — postmerge hook.** `/soleur:postmerge` calls the skill only after the prod-health check
  passes; on a non-feature/excluded PR it is a silent no-op.
- **FR7 — Lint gate.** The skill runs `lint-distribution-content.sh` against the assembled file before
  finishing; Liquid markers are rendered/stripped first.
- **FR8 — Voice.** Voice is derived inline from `brand-guide.md` `## Voice` + `## Channel Notes > ### X`;
  author identity is read from `site.author.name`, never inferred.

## Technical Requirements

- **TR1 — Reuse publisher contract.** Exact heading `## X/Twitter Thread`; valid X channel token `x`;
  discovery requires `status` + `publish_date`; publish acts only on `status: scheduled` with
  `publish_date == today`. (`content-publisher.sh:183,784-815`.)
- **TR2 — Shared merged-PR helper.** Extract `changelog`'s inline `gh` logic into
  `scripts/lib/recent-merged-prs.sh` (time window + label filter + user-facing classification);
  both `changelog` and `feature-tweet` consume it to prevent drift.
- **TR3 — Numbered-format + count assertion.** Emit canonical numbered format and add a test asserting
  "author N tweets → publisher extracts N" to guard the silent 5→1 collapse regression class (#2496).
- **TR4 — Discord safety (if `discord` channel included).** `allowed_mentions:{parse:[]}`, `username: "Sol"`
  + avatar, `~1800`-char truncation, webhook fallback.
- **TR5 — No naked numbers.** Any statistic in generated copy must be verified against a source or omitted.
- **TR6 — Scope calibration.** Day-one scope = generation + existing publish path; defer speculative
  automation (>3-new-files / building-for-an-account-that-doesn't-exist heuristic).

## Open Questions

- Default channels for ship tweets: `x` only vs `x, bluesky` (LinkedIn personal-profile automation is
  ToS-restricted). Lean `x, bluesky`.
- Whether the postmerge hook batches multiple PRs from one deploy or drafts one tweet per feature PR.
