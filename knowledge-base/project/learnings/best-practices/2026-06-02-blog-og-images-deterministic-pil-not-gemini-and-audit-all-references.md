---
title: "Blog OG images are deterministic PIL vector art (not Gemini); audit ALL ogImage references, not just the new ones"
date: 2026-06-02
category: best-practices
module: plugins/soleur/docs
issue: 4753
tags: [og-images, eleventy, seo, aeo, brand, pil, drift-guard]
---

# Learning: Bespoke blog OG images — match the textless sibling pattern with deterministic PIL, and audit every reference

## Problem

Issue #4753 asked for bespoke 1200×630 OG images for 11 imageless blog posts.
The plan prescribed `/soleur:gemini-imagegen` as the primary generator with an
SVG-render fallback, and described compositions with "white headline" text and a
"Case Study" gold ALL-CAPS label.

Two things the plan got wrong about the *actual* on-disk state:

1. **The existing ~16 sibling OG images carry ZERO text.** They are precise,
   abstract gold-on-dark vector geometry — a Soleur hexagon `X` competitor glyph
   for vs-posts, force-directed node graphs, radial sun bursts. Sampled palette:
   bg `#1A1A1A` (not the brand guide's `#0A0A0A`), gold `#C9A962`→`#DCBE6E`.
   An AI image generator (Gemini) cannot reproduce crisp vector line-art or
   legible geometry and would have produced visually-inconsistent slop next to
   the shipped 16.

2. **A 12th post already had a 404'ing OG card.** While auditing that *every*
   `ogImage` value resolves to a file on disk (not just the 11 I was adding),
   `2026-05-15-skill-libraries-vs-workflow-plugins.md` (shipped in #3798)
   referenced `og-skill-libraries-vs-workflow-plugins.png` that was **never
   committed** — a live 404 social card, invisible to CI.

## Solution

- **Generate with Python PIL, not Gemini.** PIL 12.x ships in this environment.
  Render at 3× supersample, draw thin gold strokes as opaque blends precomputed
  over the flat bg (PIL `ImageDraw.line`/`ellipse`/`polygon` don't alpha-composite
  on RGB), then LANCZOS-downscale to 1200×630. Deterministic, quota-free, and a
  pixel-perfect match for the abstract sibling style. Keep the generator in `/tmp`
  (the existing 16 PNGs have no committed generator — match that precedent; the
  PNG is the artifact).
- **Match on-disk siblings over plan prose.** When a plan's visual brief conflicts
  with the actual shipped assets, the shipped assets win for brand consistency.
  Went textless; relied on bespoke *variation* (not text) for the social-CTR/AEO
  benefit the issue wanted.
- **Audit ALL references, not just your diff.** One-liner:
  `for f in plugins/soleur/docs/blog/*.md; do v=$(grep -m1 '^ogImage:' "$f" | sed -E 's/.*"([^"]*)".*/\1/'); [ -n "$v" ] && [ ! -f "plugins/soleur/docs/images/$v" ] && echo "MISSING $v ($f)"; done`
  Fixed the pre-existing 404 inline (1 new image; the post already referenced it →
  cheaper to fix than to file).
- **Relax the drift-guard by inverting the floor, don't delete it.** Imaging all 11
  emptied the imageless population, so `seo-aeo-drift-guard.test.ts` Test 12
  sub-test (b)'s `expect(checked).toBeGreaterThan(0)` floor (an anti-vacuous-pass
  guard) would now fail. Replaced it with `expect(without.length).toBe(0)` — pins
  the intended end-state (zero imageless posts), still fails if a post *loses* its
  ogImage, and the per-post fallback loop stays armed for any future imageless
  post. The #3173 per-post-threading regression is owned by sub-test (a), untouched.

## Key Insight

`ogImage` threads through the template as `{{ site.url }}/images/{{ ogImage }}`,
and neither the Eleventy build nor the drift-guard validate that the referenced
PNG **exists on disk** — they only assert the frontmatter value renders into
`BlogPosting.image`. So a post can ship green with a 404'ing social card forever.
When touching OG images, the cheapest high-value check is "does every `ogImage`
value resolve to a real 1200×630 file," run across the whole corpus.

## Session Errors

1. **Task subagent tool unavailable in the planning env** (forwarded from
   session-state). — Recovery: plan/deepen gates run inline. — Prevention: none
   needed; planning produced a complete, verified plan.
2. **IaC-routing PreToolUse hook blocked a planning write** because the plan prose
   contained the literal `doppler secrets set` inside a *description of what the
   plan does NOT do* (the only Doppler interaction is a read). — Recovery: reworded
   to read-only phrasing + added `<!-- iac-routing-ack: plan-phase-2-8-reviewed -->`.
   — Prevention: in plan prose, describe a read as `doppler secrets get … --plain`;
   avoid quoting write-verb literals even in negative/explanatory sentences. Already
   covered by the existing `iac-routing-ack` opt-out; no new hook warranted.
3. **`git diff | grep` probe exited 127 with `ZSH_VERSION: unbound variable`** —
   shell-snapshot noise under `set -u`; the diff output was still readable. —
   Prevention: don't trust a trailing pipeline's exit code under the snapshot's
   `set -u`; read the captured output, not just `$?`.
4. **Foreground `sleep 30` blocked by the harness.** — Recovery: read the
   background task's output file directly. — Prevention: use Monitor/background
   polling, never a foreground sleep, to wait on a condition.
5. **`security-sentinel` miscounted new PNGs (26 vs actual 12)** — it listed the
   whole images dir (14 pre-existing + 12 new). — Recovery: cross-checked against
   `git status`/`git diff --name-only` (authoritative). — Prevention: trust
   `git diff origin/main...HEAD --name-only` for new-file counts, not a directory
   listing; agent file-counts are advisory.
6. **Discovered a pre-existing 404** (skill-libraries OG image missing from #3798).
   — Recovery: fixed inline with a matching on-brand image. — Prevention: the
   audit-all-references one-liner above; consider a CI drift-guard sub-test that
   asserts every `ogImage` value resolves to a file (out of scope here, noted).
