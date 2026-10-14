---
title: "Bespoke OG images for the 11 imageless blog posts"
type: content
issue: 4753
branch: feat-one-shot-4753-bespoke-og-images
milestone: "Phase 4: Validate + Scale"
lane: cross-domain  # no spec.md for this branch — defaulted to cross-domain (TR2 fail-closed)
brand_survival_threshold: none
---

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->

# 📚 Bespoke OG images for the 11 imageless blog posts (#4753)

> Spec lacks valid `lane:` — defaulted to `cross-domain` (TR2 fail-closed); no `knowledge-base/project/specs/feat-one-shot-4753-bespoke-og-images/spec.md` exists.

## Enhancement Summary

**Deepened on:** 2026-06-02
**Sections enhanced:** Verify, Phase 3 (drift-guard edit), Sharp Edges, Research Insights

### Key Improvements (this deepen pass)

1. **Corrected the test runner**: there is NO `plugins/soleur/package.json`.
   The runner is repo-root `scripts/test-all.sh` (root `package.json
   scripts.test`); the drift-guard runs in the `bun test plugins/soleur/`
   shard at `scripts/test-all.sh:168`. Targeted command:
   `bun test plugins/soleur/test/seo-aeo-drift-guard.test.ts` from repo root.
   (Three references in the plan were fixed.)
2. **Made Phase 3 implementable**: pinned the exact CURRENT assertion
   (lines 621-624) and a concrete REPLACEMENT using only already-imported
   `expect` and the in-scope `without` array — no new imports.
3. **Confirmed case-study posts are genuinely asserted** (not skipped):
   `blog.json` permalink + `sourcePosts()` slug-derivation produce a slug
   that matches the built path for dateless `case-study-*` filenames, so
   sub-test (a)'s `existsSync` guard does not silently skip the 5 case studies.

### Deepen Gate Results

- **4.4 Precedent-Diff:** the only pattern-bound behavior is the test edit;
  precedent is sub-test (a) in the same file (`seo-aeo-drift-guard.test.ts`),
  diffed inline in Phase 3. No SQL/atomic-write/lock/RPC patterns. No new
  scheduled job (Inngest/cron check N/A).
- **4.6 User-Brand Impact:** PRESENT, threshold `none`, no sensitive-path
  match on Files-to-Edit/Create, scope-out reason present. PASS.
- **4.7 Observability:** the only non-`.md` edit is a **test** file
  (`plugins/soleur/test/…`), not under any Phase 2.9 code-class path
  (`apps/*/{server,src,infra}`, `plugins/*/scripts/`). Pure-docs/data + test
  edit → skip rule applies; section present and documents the skip. PASS.
- **4.8 PAT-shaped variable halt:** no match. PASS.
- **Verified-live citations:** issue #3173 (CLOSED issue, not a PR);
  `base.njk:14,21`, `blog-post.njk:26`, `eleventy.config.js:66`,
  `INPUT="plugins/soleur/docs"` — all read directly. `BlogPosting.image` is a
  string (`jsonLdSafe`-wrapped), matching the guard's string comparison.

## Overview

11 of 27 blog posts under `plugins/soleur/docs/blog/` carry no `ogImage:`
frontmatter and therefore fall back to the site-wide default
`images/og-image.png` for their `BlogPosting.image` JSON-LD plus their
OpenGraph / Twitter card. Bespoke 1200×630 images improve social CTR and
AEO image-entity signals.

The JSON-LD / template plumbing is **already done** — #3173 confirmed
`base.njk` and `blog-post.njk` thread per-post `ogImage` correctly and
shipped a drift-guard (`plugins/soleur/test/seo-aeo-drift-guard.test.ts`,
Test 12) pinning the behavior. This issue is the **design/content
workstream** that #3173 scoped out: produce 11 bespoke images, drop them in
`plugins/soleur/docs/images/blog/`, and add one `ogImage:` line per post.

This is a marketing/content change against an already-provisioned static
surface. No new infrastructure, no new code paths, no schema. The only
load-bearing technical constraint is a drift-guard assertion that requires
**at least one imageless post to remain** (see Research Reconciliation +
Sharp Edges).

## Research Reconciliation — Spec vs. Codebase

| Claim (issue body) | Reality (verified on this branch) | Plan response |
|---|---|---|
| "11 of 26 blog posts have no `ogImage:`" | **11 imageless** confirmed via the issue's own grep; total is now **27** posts (26 → 27, one post added since the issue was filed). | Use the 11-post list verified below; the count of 11 holds, total drift is cosmetic. |
| "scoped out of #3173 which confirmed the template threads per-post `ogImage`" | `#3173` is a CLOSED **issue** (`[p1-high](seo): Fix BlogPosting.image…`). `base.njk:14,21` + `blog-post.njk:26` thread `ogImage` with `og-image.png` default; #3173 drift-guard is `seo-aeo-drift-guard.test.ts` Test 12 (lines 551-626). | Premise holds. Plumbing is done; this PR only adds data (images + frontmatter). |
| "drift-guard will assert each one threads through to `BlogPosting.image`" | Test 12 has **two** sub-tests: (a) posts *with* `ogImage` thread the exact filename (lines 587-608); (b) posts *without* `ogImage` fall back to `og-image.png` **and asserts `checked > 0`** (lines 610-625). | **Sub-test (b) FAILS if all 11 get images** (imageless population → 0 → vacuous-pass guard trips). Plan keeps ≥1 imageless OR edits the guard. See decision below. |
| "design (or generate via `/soleur:gemini-imagegen`)" | `GEMINI_API_KEY` **present in `soleur/dev` Doppler** (read-only `get`); `gemini-imagegen` skill exists with a Phase 0 quota pre-flight (free-tier keys may return `429 limit:0`). | Use `gemini-imagegen` as primary; SVG-render fallback if quota is zero (see Phase 1). |

### Premise Validation note

Checked: issue #3173 (`gh issue view` → CLOSED issue, not a PR — premise
that "template already threads ogImage" holds); the 11 imageless posts (the
issue's grep reproduced verbatim → exactly 11); `base.njk` /
`blog-post.njk` thread points (present at the cited lines); the drift-guard
(`seo-aeo-drift-guard.test.ts` Test 12 exists and runs a live Eleventy
build in `beforeAll`); image passthrough (`eleventy.config.js:66` copies
`docs/images` → `_site/images`); `GEMINI_API_KEY` (present in Doppler
`soleur/dev`, read-only access). **Stale:** the "26 posts" total (now 27) —
cosmetic, the 11-imageless figure is the load-bearing number and it holds.
No blocking premise was stale.

## Problem

Imageless posts emit `"image": "https://soleur.ai/images/og-image.png"` in
their `BlogPosting` JSON-LD and the same default in their OG/Twitter card
`<meta>` — generic, identical across 11 posts, weak for social CTR and AEO
image-entity association.

### The 11 imageless posts (verified 2026-06-02)

Regenerate with:
`for f in plugins/soleur/docs/blog/*.md; do grep -q '^ogImage:' "$f" || echo "$f"; done`

| # | Source post | Title (image brief) | Prescribed image filename | Built slug |
|---|---|---|---|---|
| 1 | `2026-03-17-soleur-vs-notion-custom-agents.md` | Soleur vs. Notion Custom Agents | `og-soleur-vs-notion-custom-agents.png` | `soleur-vs-notion-custom-agents` |
| 2 | `2026-03-26-soleur-vs-polsia.md` | Soleur vs. Polsia | `og-soleur-vs-polsia.png` | `soleur-vs-polsia` |
| 3 | `2026-03-29-credential-helper-isolation-sandboxed-environments.md` | Credential Helper Isolation | `og-credential-helper-isolation.png` | `credential-helper-isolation-sandboxed-environments` |
| 4 | `2026-03-29-your-ai-team-works-from-your-actual-codebase.md` | Your AI Team Works From Your Actual Codebase | `og-ai-team-from-your-codebase.png` | `your-ai-team-works-from-your-actual-codebase` |
| 5 | `2026-03-31-soleur-vs-paperclip.md` | Soleur vs. Paperclip | `og-soleur-vs-paperclip.png` | `soleur-vs-paperclip` |
| 6 | `2026-05-14-how-to-run-every-department-with-ai-agents.md` | Run Every Department with AI Agents | `og-run-every-department.png` | `how-to-run-every-department-with-ai-agents` |
| 7 | `case-study-brand-guide-creation.md` | Case Study: Brand Guide Creation | `og-case-study-brand-guide.png` | `case-study-brand-guide-creation` |
| 8 | `case-study-business-validation.md` | Case Study: Business Validation | `og-case-study-business-validation.png` | `case-study-business-validation` |
| 9 | `case-study-competitive-intelligence.md` | Case Study: Competitive Intelligence | `og-case-study-competitive-intelligence.png` | `case-study-competitive-intelligence` |
| 10 | `case-study-legal-document-generation.md` | Case Study: Legal Document Generation | `og-case-study-legal-documents.png` | `case-study-legal-document-generation` |
| 11 | `case-study-operations-management.md` | Case Study: Operations Management | `og-case-study-operations.png` | `case-study-operations-management` |

(Filenames are not required to mirror the slug — the drift-guard asserts
the frontmatter value renders, not a naming convention. The `og-<topic>`
shape matches existing siblings under `docs/images/blog/`.)

## User-Brand Impact

**If this lands broken, the user experiences:** a blog post whose social
card 404s (missing image file) or whose Eleventy build fails CI (the
drift-guard runs a full build) — i.e. a broken share preview when the post
is posted to X/LinkedIn/Discord.

**If this leaks, the user's [data / workflow / money] is exposed via:** N/A
— these are public marketing images on a public docs site; no
user/operator data is involved.

**Brand-survival threshold:** none — public marketing asset change, no
user-data surface, no single-user incident vector. (Sensitive-path scope-out:
`threshold: none, reason: public docs-site marketing images only — no
schema/auth/API/user-data surface touched`.)

## The drift-guard decision (load-bearing)

`seo-aeo-drift-guard.test.ts` Test 12 sub-test (b) iterates posts **without**
`ogImage` and asserts `expect(checked, "at least one imageless post asserted
against built HTML").toBeGreaterThan(0)` (lines 621-624). Today 11 posts
satisfy it. If this PR adds `ogImage:` to **all 11**, `checked` becomes 0
and the test **fails** with the vacuous-pass guard.

**Chosen approach: image all 11 AND retire sub-test (b)'s hard floor.**
Rationale: sub-test (b)'s purpose is to prove the *default-fallback path*
still works, but once the codebase intentionally has zero imageless posts,
the floor is asserting against an empty set by design — it is no longer a
drift signal, it is a constraint that this very PR is meant to remove.
Keeping one post artificially imageless to satisfy a test would be
tail-wagging-dog. The plan therefore:

- Adds `ogImage:` to all 11 posts (the issue's actual goal).
- Edits Test 12 sub-test (b): replace the `checked > 0` floor with an
  assertion that **tolerates an empty imageless set** while still proving
  the fallback *mechanism* for any imageless post that exists. Preferred
  concrete edit: keep the per-post fallback assertion inside the loop (so a
  *future* imageless post is still checked), and replace the hard
  `expect(checked).toBeGreaterThan(0)` with `expect(without.length).toBe(0)`
  plus a comment documenting the intended end-state (all posts imaged).
- Sub-test (a) (`posts with ogImage thread the exact filename`) is
  **untouched** and now covers all 11 new images — this is the positive
  drift-guard the issue references.

This is the one code edit in an otherwise content-only PR. It is in scope
because the issue body explicitly says "the existing #3173 drift-guard will
then assert each one threads through" — making the guard pass on the new
end-state is part of delivering the issue.

## Implementation Phases

### Phase 0 — Preconditions (no code)

1. Confirm the 11-post list is still exactly 11 (re-run the grep above). If
   a new post was added/removed since this plan, reconcile the table.
2. Confirm `GEMINI_API_KEY` resolves read-only:
   `doppler secrets get GEMINI_API_KEY -p soleur -c dev --plain >/dev/null && echo ok`.
3. Run the `gemini-imagegen` Phase 0 quota pre-flight (the
   `gemini-3-pro-image-preview` 1×1 probe). Record the verdict. If quota is
   `limit:0`, switch to the SVG-render fallback (Phase 1, option B) — do NOT
   block the content work on a free-tier quota wall.
4. Read `knowledge-base/marketing/brand-guide.md` §Visual Direction (Solar
   Forge) to anchor the design brief.

### Phase 1 — Generate the 11 images (design workstream)

**Visual template (match existing siblings):** dark `#0A0A0A` canvas,
thin gold (`#C9A962`) line-art geometry, white (`#FFFFFF`) headline, Inter
typography, no photographic content. Reference: existing
`docs/images/blog/og-soleur-vs-cursor.png` uses
`[Soleur hexagon mark] · X · [competitor glyph]` for vs-posts. Output
**1200×630 PNG, 8-bit RGB** (verified dimension of all existing OG images).

**Composition by post class:**

- **`soleur-vs-*` (Notion, Polsia, Paperclip):**
  `[Soleur hex] X [competitor mark]` line-art, matching `og-soleur-vs-cursor.png`.
- **Concept posts (credential isolation, AI-team-from-codebase, run-every-department):**
  single centered line-art motif + post title in white. Pull motif from the
  topic (lock/shield for credential isolation; nested folders for codebase;
  department grid for run-every-department).
- **Case studies (5):** consistent "Case Study" badge (gold ALL-CAPS label
  per brand §Section Labels) + topic glyph + short title, so the 5 read as a
  set.

**Option A (primary): `/soleur:gemini-imagegen`** — generate each image with
a prompt encoding the Solar Forge palette + 1200×630 aspect + the
composition above. Save to `plugins/soleur/docs/images/blog/og-<name>.png`
per the table.

**Option B (fallback, if Gemini quota = 0): SVG → PNG render.** Hand-author
an SVG per the template (dark bg, gold line-art, Inter text) and rasterize to
1200×630 PNG (e.g. `resvg`/`rsvg-convert`, or a headless Chromium screenshot
of an HTML/CSS card). Deterministic, on-brand, quota-free. Verify each
output: `file <png>` must report `1200 x 630`.

**Quality gate per image:** open in `Read` (visual inspection) — confirm
on-brand palette, legible title at thumbnail scale, no AI-slop artifacts, no
text clipping. Re-generate any that fail.

### Phase 2 — Wire the frontmatter

For each of the 11 posts, insert one line into the YAML frontmatter (after
`description:`, matching sibling shape `ogImage: "blog/og-soleur-vs-cursor.png"`):

```yaml
ogImage: "blog/og-<name>.png"
```

Path is **relative to `/images/`** — the template renders
`{{ site.url }}/images/{{ ogImage }}` → `https://soleur.ai/images/blog/og-<name>.png`.
Do NOT prefix with `/images/` or `images/` (the template adds it).

`ogImageAlt:` is optional and **no existing post sets it** — the default
(`site.name + ' - ' + site.tagline`) applies. Out of scope unless a reviewer
requests per-post alt text (see Non-Goals).

### Phase 3 — Update the drift-guard (the one code edit)

Edit `plugins/soleur/test/seo-aeo-drift-guard.test.ts` Test 12 sub-test (b)
(verified at lines 610-625) per the decision above. The current trailing
assertion is the floor that trips:

```ts
// CURRENT (lines 621-624) — fails when zero posts are imageless:
expect(
  checked,
  "at least one imageless post asserted against built HTML",
).toBeGreaterThan(0);
```

Prescribed replacement — keep the per-post fallback assertion inside the
loop (so a *future* imageless post is still checked against the default),
and replace the floor with an end-state assertion documenting that all posts
are now imaged:

```ts
// REPLACEMENT — tolerates the intended end-state (every post imaged) while
// still asserting the fallback for any imageless post that does exist.
// As of #4753 all blog posts carry bespoke ogImage; `without` is expected
// empty. The loop above still guards a future imageless post.
expect(
  without.length,
  "all blog posts now carry bespoke ogImage (#4753); add the default-fallback " +
    "assertion back to the loop if a new imageless post is introduced",
).toBe(0);
```

This uses only the `expect` already imported from `bun:test` (line 13) and
the `without` array already in scope (line 611) — no new imports. Sub-test
(a) (lines 587-608) is **untouched**; it now asserts all 11 new images
thread correctly. Keep the `sourcePosts()` / `blogPostingImage()` helpers
(lines 563-585) unchanged — they already drive both sub-tests.

### Phase 4 — Verify

1. Targeted (fast): from the repo root, `bun test
   plugins/soleur/test/seo-aeo-drift-guard.test.ts` — the test runs a live
   Eleventy build in `beforeAll` (so it exercises image passthrough + JSON-LD
   threading end-to-end). Full suite: `bash scripts/test-all.sh` from the repo
   root (root `package.json` `scripts.test`; the drift-guard runs inside the
   `bun test plugins/soleur/` shard at `scripts/test-all.sh:168`). **Do not
   hardcode a per-package runner** — there is no `plugins/soleur/package.json`;
   the runner is the repo-root `scripts/test-all.sh`.
2. Spot-check one built post:
   `grep -o '"image": "[^"]*"' _site/blog/soleur-vs-polsia/index.html`
   → must be `https://soleur.ai/images/blog/og-soleur-vs-polsia.png`, not the default.
3. Confirm every referenced image exists on disk:
   for each `ogImage` value, `test -f "plugins/soleur/docs/images/${value}"`.

## Files to Edit

- `plugins/soleur/docs/blog/2026-03-17-soleur-vs-notion-custom-agents.md` — add `ogImage:`
- `plugins/soleur/docs/blog/2026-03-26-soleur-vs-polsia.md` — add `ogImage:`
- `plugins/soleur/docs/blog/2026-03-29-credential-helper-isolation-sandboxed-environments.md` — add `ogImage:`
- `plugins/soleur/docs/blog/2026-03-29-your-ai-team-works-from-your-actual-codebase.md` — add `ogImage:`
- `plugins/soleur/docs/blog/2026-03-31-soleur-vs-paperclip.md` — add `ogImage:`
- `plugins/soleur/docs/blog/2026-05-14-how-to-run-every-department-with-ai-agents.md` — add `ogImage:`
- `plugins/soleur/docs/blog/case-study-brand-guide-creation.md` — add `ogImage:`
- `plugins/soleur/docs/blog/case-study-business-validation.md` — add `ogImage:`
- `plugins/soleur/docs/blog/case-study-competitive-intelligence.md` — add `ogImage:`
- `plugins/soleur/docs/blog/case-study-legal-document-generation.md` — add `ogImage:`
- `plugins/soleur/docs/blog/case-study-operations-management.md` — add `ogImage:`
- `plugins/soleur/test/seo-aeo-drift-guard.test.ts` — relax Test 12 sub-test (b) imageless-floor (see Phase 3)

## Files to Create

- `plugins/soleur/docs/images/blog/og-soleur-vs-notion-custom-agents.png` (1200×630)
- `plugins/soleur/docs/images/blog/og-soleur-vs-polsia.png` (1200×630)
- `plugins/soleur/docs/images/blog/og-credential-helper-isolation.png` (1200×630)
- `plugins/soleur/docs/images/blog/og-ai-team-from-your-codebase.png` (1200×630)
- `plugins/soleur/docs/images/blog/og-soleur-vs-paperclip.png` (1200×630)
- `plugins/soleur/docs/images/blog/og-run-every-department.png` (1200×630)
- `plugins/soleur/docs/images/blog/og-case-study-brand-guide.png` (1200×630)
- `plugins/soleur/docs/images/blog/og-case-study-business-validation.png` (1200×630)
- `plugins/soleur/docs/images/blog/og-case-study-competitive-intelligence.png` (1200×630)
- `plugins/soleur/docs/images/blog/og-case-study-legal-documents.png` (1200×630)
- `plugins/soleur/docs/images/blog/og-case-study-operations.png` (1200×630)

## Acceptance Criteria

### Pre-merge (PR)

- [x] All 11 posts in the table carry an `ogImage:` line matching
      `^ogImage:\s*"blog/og-[a-z0-9-]+\.png"$`.
- [x] All 11 PNG files exist under `plugins/soleur/docs/images/blog/`, each
      reporting `1200 x 630` via `file`.
- [x] Each image visually inspected (`Read`): on-brand Solar Forge palette,
      legible title, no slop/clipping artifacts.
- [x] `seo-aeo-drift-guard.test.ts` Test 12 sub-test (a) passes — every one
      of the 11 new `ogImage` values renders as
      `https://soleur.ai/images/blog/og-<name>.png` in `BlogPosting.image`,
      and none equals `…/images/og-image.png`.
- [x] Test 12 sub-test (b) passes with zero imageless posts (the relaxed
      floor), and still covers a hypothetical future imageless post.
- [x] Full `bash scripts/test-all.sh` (repo root) is green (Eleventy build
      + all drift-guards). (`bun` shard 5/5 + `scripts` shard 86/86 green
      locally; `webplat` shard has no import path to `plugins/soleur/docs`
      and runs on the PR in CI.)
- [x] Spot-check: built `soleur-vs-polsia` `BlogPosting.image` is the bespoke
      URL, not the default (asserted by Test 12 sub-test (a), which threads
      every post with `ogImage` and rejects the default).
- [ ] PR body uses `Closes #4753`, has a `## Changelog` section, and a
      `semver:patch` label (content/data + a test relaxation — no new component).

> **Discovered-defect inline fix:** the audit found a 12th post
> (`2026-05-15-skill-libraries-vs-workflow-plugins.md`, introduced by #3798)
> whose `ogImage:` line points to a PNG that was never committed → its social
> card 404s in production. Fixed inline (1 new on-brand image; the post already
> references it) since it is the same subsystem and the exact 404-card user
> impact #4753 targets, and is cheaper to fix than to file.

### Post-merge (operator)

- [ ] None. The docs site rebuilds and deploys via the existing GitHub Pages
      workflow on merge to main; no manual step. (Optional, automatable:
      validate a live OG card with a social-card debugger via Playwright MCP
      once deployed — not required for merge.)

## Domain Review

**Domains relevant:** Marketing (CMO)

### Marketing (CMO)

**Status:** reviewed (inline — Task subagent unavailable in this environment;
assessment done directly against `brand-guide.md`)
**Assessment:** This is a pure marketing-asset workstream (the issue carries
`domain/marketing`). The 11 images must follow the brand guide's **Solar
Forge** visual direction: `#0A0A0A` canvas, gold accent `#C9A962`, white
headlines, Inter type, thin gold line-art (no photography, no AI-slop
gradients). The 5 case-study images should read as a coherent set (shared
"Case Study" gold ALL-CAPS label per brand §Section Labels). The 3 `vs-*`
images should match the existing `[Soleur hex] X [competitor]` line-art
composition for visual consistency with shipped vs-posts. No copy changes,
no positioning changes — visual assets only. Brand-voice review (copywriter)
not required: no new prose ships (alt text uses the existing default).

### Product/UX Gate

Not triggered. No new user-facing page, flow, or component file
(`components/**/*.tsx`, `app/**/page.tsx`, `app/**/layout.tsx`) is created.
This is static-asset + frontmatter + one test edit. Tier: **NONE**.

## Infrastructure (IaC)

None. No server, service, cron, secret write, vendor account, DNS, or
firewall rule. The `GEMINI_API_KEY` is **read** (not written) from Doppler
`soleur/dev` via `doppler secrets get … --plain`; reading an existing secret
is not provisioning. Images are static files copied by the existing Eleventy
passthrough (`eleventy.config.js:66`) and served by the already-provisioned
GitHub Pages deploy. Phase 2.8 trigger scan: no `ssh`, no `systemctl`, no
secret mutation, no vendor-dashboard step. IaC routing acknowledged at the
top of this plan (`iac-routing-ack`) — the only Doppler interaction is a
read of a pre-existing key, which the gate's exemption for
"pure code/content change against an already-provisioned surface" covers.

## Observability

Not applicable. No file under `apps/*/server/`, `apps/*/src/`,
`apps/*/infra/`, or `plugins/*/scripts/` is edited; no new infrastructure
surface. The only code edit is a **test file** (`seo-aeo-drift-guard.test.ts`),
which is itself the observability for this change — it fails CI if any image
stops threading. Per the Phase 2.9 skip rule (pure-docs/data + a test edit,
no runtime code or infra surface), no `## Observability` 5-field schema is
required. The drift-guard IS the discoverability test: `bun test
plugins/soleur/test/seo-aeo-drift-guard.test.ts` (repo root, no `ssh`) → green.

## Open Code-Review Overlap

None. Queried `gh issue list --label code-review --state open`; no open
scope-out names any of the files in scope (the 11 blog `.md` posts, the
11 new PNGs, or `seo-aeo-drift-guard.test.ts`).

## Test Scenarios

1. **Positive thread (×11):** each new `ogImage` renders the exact bespoke
   URL in `BlogPosting.image` (Test 12 sub-test (a), already in the suite —
   now exercises 11 more posts automatically).
2. **No default leakage:** none of the 11 renders `…/images/og-image.png`.
3. **Empty imageless set tolerated:** Test 12 sub-test (b) passes when the
   imageless population is 0 (the relaxed floor) and still loops over any
   future imageless post.
4. **Image presence on disk:** every `ogImage` value resolves to an existing
   1200×630 PNG.
5. **Build integrity:** the live Eleventy build in `beforeAll` succeeds with
   the new passthrough images (no broken-link / missing-file failure).

## Non-Goals / Out of Scope

- **Per-post `ogImageAlt:` text.** No existing post sets it; the default
  applies. Adding bespoke alt text for all 11 (and a drift-guard for it) is a
  separate AEO-accessibility improvement. **Deferral:** if a reviewer wants
  per-post OG alt text, file a follow-up issue (re-eval criterion: when an AEO
  audit flags generic OG alt as a gap; milestone Phase 4). Not blocking.
- **Re-designing the existing 16 imaged posts.** Out of scope — they already
  have bespoke images.
- **Imagen / photographic OG images.** Brand direction is line-art Solar
  Forge; photographic style is a brand decision, not this issue.

## Alternative Approaches Considered

| Approach | Why not chosen |
|---|---|
| Keep 1 post imageless to satisfy the drift-guard floor | Tail-wags-dog; leaves the issue's goal (all 11 imaged) deliberately incomplete to appease a test whose purpose is moot once zero posts are imageless. |
| Generate via an external design tool (Figma/Canva) by hand | Slower, not automatable, no reproducibility. `gemini-imagegen` (or SVG-render fallback) keeps it in-session and on-brand. |
| Reuse a shared image across multiple posts (like `2026-06-01-claude-code-plugin-vs-skill-vs-mcp.md` reuses `og-best-claude-code-plugins-2026.png`) | The issue explicitly asks for **bespoke** per-post images for CTR/AEO entity signals; reuse defeats the purpose. |

## Sharp Edges

- **The drift-guard's imageless floor (`toBeGreaterThan(0)` at
  seo-aeo-drift-guard.test.ts:621-624) FAILS once all 11 posts are imaged.**
  This is the single non-obvious blocker — a content-only diff would turn CI
  red. Phase 3 is mandatory, not optional.
- **`ogImage` path is relative to `/images/`, not the repo.** The template
  renders `{{ site.url }}/images/{{ ogImage }}`. Write `blog/og-X.png`, never
  `/images/blog/og-X.png` or `images/blog/og-X.png` — a leading prefix
  double-renders to `…/images/images/…` and 404s.
- **Case-study posts have no date in their filename**, so their Eleventy
  fileSlug = the full filename (e.g. `case-study-operations-management`) with
  no date-strip — unlike dated posts. Verified: `blog.json` sets
  `permalink: "blog/{{ page.fileSlug }}/index.html"`, so each builds to
  `_site/blog/case-study-X/index.html`, and `sourcePosts()`'s slug-derivation
  (`replace(/^\d{4}-\d{2}-\d{2}-/, "")`) leaves the dateless filename
  unchanged → the derived slug matches the built path, so **sub-test (a) does
  NOT skip the 5 case-study posts** (it asserts all 5 new images, not silently
  passes over them via the `if (!existsSync(built)) continue` guard). The
  image *filename* is independent of the slug (the guard asserts the
  frontmatter value, not a naming convention), so the `og-case-study-*` names
  are fine.
- **The test runs a real Eleventy build in `beforeAll`** — a missing PNG or
  malformed frontmatter fails the *whole* suite at build time, not just
  Test 12. Verify all 11 files exist before running tests.
- **A plan whose `## User-Brand Impact` section is empty, contains only
  `TBD`/`TODO`/placeholder text, or omits the threshold will fail
  `deepen-plan` Phase 4.6.** This section is filled (threshold: none, with a
  sensitive-path scope-out reason).
- **Free-tier Gemini quota may be `limit:0`** — do not block the content work
  on it; the SVG-render fallback (Phase 1 option B) is deterministic and
  on-brand. Run the Phase 0 quota probe first.

## Research Insights

- **Template threading (verified):** `base.njk:14,21` (`og:image`,
  `twitter:image`) and `blog-post.njk:26` (`BlogPosting.image`) both use
  `ogImage | default('og-image.png')`. #3173 confirmed this.
- **Image passthrough (verified):** `eleventy.config.js:66` →
  `addPassthroughCopy({ "<INPUT>/images": "images" })`. Build runs from repo
  root (`docs/package.json`: `cd ../../../ && npx @11ty/eleventy`).
- **Existing OG image format (verified):** all `1200 x 630, 8-bit RGB PNG`;
  named `og-<topic>.png`; visual style = dark canvas + thin gold line-art.
- **Brand palette (verified, `brand-guide.md` §Visual Direction):** Solar
  Forge — bg `#0A0A0A`, surface `#141414`, gold accent `#C9A962`, gold
  gradient `#D4B36A`→`#B8923E`, text `#FFFFFF`, Inter type, ALL-CAPS gold
  section labels (letterSpacing 3).
- **`GEMINI_API_KEY` (verified):** present in Doppler `soleur/dev`
  (read-only). `gemini-imagegen` Phase 0 quota pre-flight required before
  bulk generation.
- **Test runner (verified):** repo-root `package.json scripts.test` =
  `bash scripts/test-all.sh`; the drift-guard runs in the `bun test
  plugins/soleur/` shard (`scripts/test-all.sh:168`). There is **no**
  `plugins/soleur/package.json`. Targeted: `bun test
  plugins/soleur/test/seo-aeo-drift-guard.test.ts` from repo root.
  `bunfig.toml [test]` excludes worktree dirs — run from the worktree root.
- **One existing reuse precedent:** `2026-06-01-claude-code-plugin-vs-skill-vs-mcp.md`
  reuses `og-best-claude-code-plugins-2026.png` (not bespoke) — explicitly
  NOT the pattern to follow here.
