# Learning: Hand-authoring blog + distribution content bypasses skill-enforced format guarantees

## Problem

Shipping the loop-engineering post (#5088), two classes of format bug surfaced only at CI / publish-prep:

1. **Missing `ogImage`** — the blog post had no `ogImage` frontmatter; `seo-aeo-drift-guard.test.ts`
   (#4753) red-lit `test-bun` because every post must carry a bespoke OG image.
2. **Distribution file unpublishable** — the social draft used free-form section headings
   (`## X / Twitter (thread)`, `## LinkedIn (company)`), relative `/blog/` URLs, and an unparseable
   tweet format. `content-publisher.sh` parses *exact* headings (`## X/Twitter Thread`,
   `## LinkedIn Company Page` via `channel_to_section`), needs absolute `soleur.ai` URLs, UTM params,
   and `**Tweet N**` / numbered tweet structure within 280 chars. None of it would have posted — the
   publisher would have skipped the channels and filed "manual posting required" issues.

## Root cause

Both the blog post and the distribution draft were **hand-authored in `/work` Phase 5**, bypassing the
skills that already encode the correct contract:

- `content-writer` Phase 4.5 makes `ogImage` mandatory (generate or reuse).
- `social-distribute` (SKILL.md §§5.1-5.7 + the UTM table) already prescribes the exact publisher
  section headings, absolute URLs, UTM, and per-tweet 280-char limits.

The skills were right; bypassing them dropped the enforcement. The format errors were mine, not the
skills'.

## Solution

1. **Use the skills.** Author blog posts via `content-writer` and distribution content via
   `social-distribute` rather than freehand — they enforce ogImage + the publisher's input contract.
2. **Mechanical backstop (new):** `plugins/soleur/test/distribution-content-format.test.ts` validates
   every `status: scheduled|draft` distribution file at CI — required `## <Section>` heading per
   declared channel, absolute posted-body URLs (frontmatter excluded), no Liquid markers, and labeled
   X tweets ≤280. This moves the publisher's silent runtime failure (skip + file an issue) left to CI,
   catching a malformed file regardless of how it was authored. The guard immediately surfaced (then
   cleared as false-positives) three legacy drafts — proving the value of validating posted-body-only.
3. **`content-writer` Phase 4.5** now documents an explicit reuse-an-on-theme-`og-*.png` fallback so
   the field is never omitted when image generation is unavailable.

## Key Insight

When a skill already encodes a downstream system's input contract (a publisher's parser, a CI guard's
required field), hand-authoring the artifact "to save a step" silently drops every guarantee the skill
provides — and the failure surfaces at the worst time (CI red, or a dead link posted to a real brand
account). Either invoke the skill, or add a mechanical guard that enforces the contract independently
of the authoring path. Prefer both.

## Tags
category: workflow-patterns
module: content-writer, social-distribute, content-publisher
issue: 5088
