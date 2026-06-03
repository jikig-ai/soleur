---
title: "Docs-site structured-data & canonical-signal cleanup (#3174 + #3173 + #3172 + #3171)"
type: fix
date: 2026-06-01
branch: feat-one-shot-mktg-schema-canonical-3171-3174
milestone: "Phase 4: Validate + Scale"
lane: single-domain
closes: [3174, 3173, 3172, 3171]
pattern_ref: PR #2486 (one PR, multiple closures)
requires_cpo_signoff: false
---

# Docs-site structured-data & canonical-signal cleanup

## Enhancement Summary

**Deepened on:** 2026-06-01
**Sections enhanced:** Overview reconciliation, Phase 4 (#3171 scope), Risks, Acceptance Criteria
**Gates run:** 4.4 (precedent-diff), 4.45 (verify-the-negative), 4.6 (User-Brand Impact — PASS, threshold `none`), 4.7 (Observability — PASS), 4.8 (PAT-shaped variable — PASS, no matches). Phase 4.5 (network-outage) did not trigger.
**Research agents:** Task subagents unavailable in this environment; deepening performed via direct codebase verification of every load-bearing claim.

### Key Improvements (from verify-the-negative pass)
1. **#3171 CI-gate coverage RESOLVED, not "verify-and-maybe-extend".** `validate-seo.sh:122` iterates `find "$SITE_DIR" -name '*.html' -not -name '404.html'` — ALL HTML including `_site/blog/<slug>/index.html`. The FAQ gate at line 198 (`faq-(item|question|answer|list)` ⇒ `"@type": "FAQPage"`) therefore ALREADY covers blog surfaces. No `validate-seo.sh` edit is needed. The only net-new for #3171 is the **Q/A-text-parity** drift-guard assertion (the CI gate checks presence, not parity — per its own comment, parity is delegated to review).
2. **`jsonLdSafe` filter location + behavior confirmed.** Lives at repo-root `eleventy.config.js:30` (NOT `docs/`), applies all three escapes (`<\/`, ` `, ` `). The docs:build runs `cd ../../../ && npx @11ty/eleventy` from repo root, so the root config is the active one. Risks citation is accurate.
3. **`company-as-a-service.njk` Person scope-out confirmed correct.** Line 212 is an `Article.author` byline (`name`/`url`/`jobTitle` only) — NOT a founder-bio/ProfilePage node. Adding `knowsAbout`/`description` to a byline would be semantically wrong. #3174 correctly targets only `blog-post.njk` (BlogPosting.author) + `about.njk` (ProfilePage.mainEntity).

### New Considerations Discovered
- `validate-seo.sh` edit is removed from `## Files to Edit` — the gate already covers all surfaces. This SHRINKS the PR (fewer files), reinforcing the #2486 net-negative pattern.
- The Q/A-parity assertion has a direct precedent at `seo-aeo-drift-guard.test.ts:137` (#2707 pricing FAQ) — reuse its HTML-entity normalization, no novel pattern needed (Phase 4.4 precedent-diff: precedent EXISTS).

🐛 / ✨ One focused PR draining four `domain/marketing` Phase-4 issues on the Eleventy docs
site (`plugins/soleur/docs`). All four are JSON-LD / head-template / canonical-host concerns.
Following the **PR #2486 pattern**: one PR, multiple closures, net-negative on the backlog.

PR body MUST contain (each on its own line, in the body — NOT the title):

```
Closes #3174
Closes #3173
Closes #3172
Closes #3171
```

## Overview

The four issues, as originally framed, assume the docs site emits broken/missing structured
data and split canonical signals. **Premise validation (Phase 0.6) found the codebase is
substantially further along than the issue bodies imply** — prior PRs (#2707, #2711, #2948,
#3297, #4577, #4584) already shipped most of the mechanism. This PR is therefore an
**audit + targeted gap-fill**, not a build. The Research Reconciliation table below is the
load-bearing section: every phase estimate flows from reality, not from the (partly stale)
issue prose.

Net scope after reconciliation:

- **#3174 (Person.knowsAbout):** Already split `jobTitle`/`description` correctly in
  `blog-post.njk`. Real gaps: (a) `site.author.credentials` (used as `knowsAbout`) holds
  role/bio-ish strings (`"Founder, Soleur"`, `"15+ years in distributed systems"`) rather
  than topical areas; (b) the `about.njk` ProfilePage Person node has NO `knowsAbout` and NO
  `description`. Fix: add a topical `knowsAbout` array to `site.json`, point both Person nodes
  at it, and add `description` to the ProfilePage Person.
- **#3173 (BlogPosting.image):** Template `blog-post.njk:26` ALREADY threads the per-post
  `ogImage` variable into `BlogPosting.image`. The "generic site-wide image" claim is stale at
  the template level. Real residual: 11 of 26 posts lack `ogImage` frontmatter and fall
  through to the default `og-image.png`. All 14 bespoke OG images that DO exist are already
  wired (zero orphans). Fix: confirm template wiring with a drift-guard assertion; the 11
  imageless posts keep the default until bespoke images are designed (image generation is a
  design task, scoped out with a tracking issue).
- **#3172 (canonical host):** **Premise is inverted and already resolved.** Live edge does
  `www → 301 → apex` (host-preserving, GitHub-Pages-owned), and ALL url signals already point
  to apex via `{{ site.url }}` = `https://soleur.ai` (canonical, og:url, sitemap, JSON-LD,
  llms.txt). PRs #4577/#4584 flipped the IaC apex-ward; the old `apex→www` regime is gone.
  CI guard (`www-apex-canonicalizer.test.sh`) + Sentry uptime monitor already protect it. Fix:
  audit-confirm zero residual canonical-bearing `www.` references (only legitimate external
  links remain) and close as already-aligned with a documented verification.
- **#3171 (FAQPage JSON-LD):** FAQPage JSON-LD is ALREADY present on every page with a `faq-`
  block, and `validate-seo.sh:198` already FAILS the build (per #2948) if a page renders `faq-`
  markup without FAQPage JSON-LD. Real gaps: (a) the CI gate loops over `pages/*` only — verify
  blog posts with FAQ blocks are covered; (b) presence ≠ Q/A text parity (the CI gate only
  checks presence; parity is delegated to `/soleur:review` per the gate comment). Fix: extend
  the drift-guard to assert FAQ-block ⇒ FAQPage across ALL surfaces (pages + blog) and add a
  Q/A-text-parity assertion.

## Research Reconciliation — Spec vs. Codebase

| Issue claim (spec) | Codebase reality (verified 2026-06-01) | Plan response |
|---|---|---|
| #3174: `Person.knowsAbout` holds role/bio strings | `blog-post.njk:32-36`: `jobTitle`/`description` already split; `knowsAbout` = `site.author.credentials` = `["Founder, Soleur", "15+ years in distributed systems"]` (role/bio-ish, not topical) | Add `site.author.knowsAbout` topical array; repoint both Person nodes; keep `credentials` for the visible author card |
| #3174: "every layout that emits a Person node" | Two Person emitters: `blog-post.njk` (BlogPosting.author) + `about.njk:145` (ProfilePage.mainEntity). `company-as-a-service.njk:212` Person has only name/jobTitle (author byline, not a founder-bio node) | Edit `blog-post.njk` + `about.njk`; leave `company-as-a-service.njk` byline node (scoped rationale below) |
| #3174: `about.njk` ProfilePage Person | Has `jobTitle: "Founder"` but NO `knowsAbout`, NO `description` | Add both fields, sourced from `site.json` |
| #3173: `BlogPosting.image` uses generic site-wide OG image | `blog-post.njk:26` ALREADY uses `(site.url + "/images/" + (ogImage if ogImage else "og-image.png"))` — per-post variable IS threaded | Template is correct; add drift-guard assertion. Residual = 11/26 posts lack `ogImage` frontmatter |
| #3173: per-post images available | 14 bespoke `images/blog/og-*.png` exist; ALL 14 are already wired (zero orphan images); 11 posts have no bespoke image | Imageless posts keep default fallback; file tracking issue for bespoke-image design (out of scope for a JSON-LD PR) |
| #3172: "Apex 301-redirects to www" | **INVERTED.** `dns.tf:202` + `seo-rulesets.tf:15`: live edge is `www → 301 → apex`, host-preserving, GitHub-Pages-owned. `docs/CNAME = soleur.ai` (apex) | Premise stale; canonical direction already apex-ward |
| #3172: canonical/og:url/sitemap/JSON-LD point to apex while redirect favors www (split) | All signals use `{{ site.url }}` = `https://soleur.ai`; `site.json:3` = apex; sitemap, llms.txt, base.njk canonical+og:url all apex. NO split exists | Audit-confirm; close as already-aligned. No host edits needed |
| #3172: sweep `www.` references | Only residual `www.` = external links (Contributor Covenant, Cloudflare DPA, BLS, Robert Half, Payscale, Levels.fyi, LinkedIn, inc.com) — none are canonical-bearing | No edits; document the audit grep in the PR body |
| #3172: existing guards | `www-apex-canonicalizer.test.sh` (config-drift) + `sentry_uptime_monitor.soleur_www` (runtime) + `seo-aeo-drift-guard.test.ts:394` (sitemap apex-only) already exist | Rely on existing guards; do not duplicate |
| #3171: "FAQPage JSON-LD presence is unconfirmed" | FAQPage JSON-LD present on 9 pages + ~20 blog posts with FAQ; `validate-seo.sh:198` (per #2948) already FAILS build if `faq-` markup present without FAQPage | Confirm CI gate covers blog surfaces; add Q/A-parity assertion |
| #3171: CI gate scope | `validate-seo.sh` FAQ gate (line 192-204) loops over `_site/<page>/index.html` for `pages/*` — verify blog `_site/blog/<slug>/index.html` is in the loop | Extend gate/drift-guard to cover blog FAQ surfaces if not already |

**Premise Validation note (Phase 0.6):** All 4 issues OPEN, none closed by a merged PR
(`gh issue view` confirmed). Reference PR #2486 confirmed MERGED with `Closes #2467/#2468/#2469`
each on its own line in the body — the one-PR-multiple-closures pattern. Audit refs
(`knowledge-base/marketing/audits/soleur-ai/2026-05-04-seo-audit.md` and `-content-plan.md`)
exist. **#3172's premise is inverted and already resolved by #4577/#4584** — surfaced here
rather than planned against. The plan re-scopes #3172 from "fix split signals" to
"audit-confirm alignment + close."

## User-Brand Impact

**If this lands broken, the user experiences:** malformed JSON-LD in a page `<head>` could
cause Google to drop the Rich Result (FAQ rich snippet, author/sitelinks), reducing organic
discoverability of the marketing site — but never a runtime/app failure (static docs site).
**If this leaks, the user's data is exposed via:** N/A — no user data on the public docs site;
the only "data" is the founder's already-public bio/social links in `site.json`.
**Brand-survival threshold:** none — public marketing-site structured-data; no regulated data,
no per-user surface. (Threshold `none`; diff touches no sensitive path per preflight Check 6
regex — docs `.njk`/`.json`/`.md` only.)

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1 (#3174):** `site.json` gains `author.knowsAbout` = an array of ≥4 actual topical
      areas (e.g., `["AI agents", "Autonomous software engineering", "Distributed systems",
      "Developer tooling", "Company-as-a-Service"]`). `author.credentials` (role/bio strings)
      retained for the visible author card only.
- [ ] **AC2 (#3174):** `blog-post.njk` Person `knowsAbout` field reads `site.author.knowsAbout`
      (not `site.author.credentials`); `jobTitle` and `description` unchanged.
      Verify: `grep -n 'knowsAbout.*site.author.knowsAbout' plugins/soleur/docs/_includes/blog-post.njk` returns 1.
- [ ] **AC3 (#3174):** `about.njk` ProfilePage Person node gains `description`
      (= `site.author.bio`) and `knowsAbout` (= `site.author.knowsAbout`), both via
      `jsonLdSafe | safe`.
      Verify: `grep -cE '"(description|knowsAbout)":' plugins/soleur/docs/pages/about.njk` ≥ 2 inside the ProfilePage block.
- [ ] **AC4 (#3174):** Every rendered Person JSON-LD node parses as valid JSON (extract each
      `<script type="application/ld+json">` from `_site/`, pipe through `jq .`, exit 0). No
      `knowsAbout` value is a role/bio sentence; each entry is a noun-phrase topical area.
- [ ] **AC5 (#3173):** `blog-post.njk:26` BlogPosting.image confirmed threading per-post
      `ogImage`. Add a `seo-aeo-drift-guard.test.ts` assertion: for every blog post that sets
      `ogImage:` frontmatter, the rendered `BlogPosting.image` ends in that exact filename (not
      `og-image.png`). Verify the assertion runs and passes: `bun test plugins/soleur/test/seo-aeo-drift-guard.test.ts`.
- [ ] **AC6 (#3172):** Zero canonical-bearing `www.` references in docs source. Run and paste
      output into PR body:
      `grep -rn 'www\.soleur' plugins/soleur/docs/_data plugins/soleur/docs/_includes plugins/soleur/docs/pages plugins/soleur/docs/index.njk plugins/soleur/docs/llms.txt.njk plugins/soleur/docs/sitemap.njk` returns 0.
- [ ] **AC7 (#3172):** All canonical signals resolve to apex in built output. From `_site/`:
      `rel="canonical"`, `og:url`, sitemap `<loc>`, llms.txt links, and JSON-LD `url` fields
      all begin `https://soleur.ai/` (never `www.`). Verify via `seo-aeo-drift-guard.test.ts`
      existing apex-host assertions (lines 394-450) stay green.
- [ ] **AC8 (#3171):** Every docs surface (pages + blog) that renders a `faq-(item|question|answer|list)`
      block also emits a `"@type": "FAQPage"` JSON-LD block. **Already enforced** by
      `validate-seo.sh` — its `find "$SITE_DIR" -name '*.html'` loop (line 122) covers blog
      slugs, and the FAQ gate (line 198) fails the build on any FAQ-block-without-FAQPage. AC =
      confirm the CI gate stays green after the build (`validate-seo.sh _site` exits 0). No gate
      edit needed.
- [ ] **AC9 (#3171):** Q/A-text parity — for at least the highest-traffic FAQ surfaces
      (`pricing`, `about`, `company-as-a-service`), each visible `faq-answer` text has a
      matching `acceptedAnswer.text` (codepoint-exact, modulo `jsonLdSafe` escaping). Add a
      drift-guard test row asserting parity on these surfaces.
- [ ] **AC10 (build):** `npm run docs:build` (Eleventy) completes clean; `_site/` produced.
- [ ] **AC11 (validation):** `bash plugins/soleur/skills/seo-aeo/scripts/validate-seo.sh _site`
      exits 0. `bun test plugins/soleur/test/seo-aeo-drift-guard.test.ts plugins/soleur/test/validate-seo.test.ts plugins/soleur/test/jsonld-escaping.test.ts` all green.
- [ ] **AC12 (closures):** PR body contains `Closes #3174`, `Closes #3173`, `Closes #3172`,
      `Closes #3171`, each on its own line.

### Post-merge (operator)

- [ ] **AC13:** None automatable-by-this-PR remain. Bespoke OG-image design for the 11
      imageless posts is tracked in a follow-up issue (see Deferrals). `Automation: not feasible
      because image generation is a design/creative task requiring the gemini-imagegen or Pencil
      pipeline, out of scope for a structured-data PR.`

## Implementation Phases

### Phase 1 — #3174 Person topical fields (RED→GREEN)
1. Add `author.knowsAbout` topical array to `plugins/soleur/docs/_data/site.json`.
2. Repoint `blog-post.njk:36` `knowsAbout` from `site.author.credentials` → `site.author.knowsAbout`.
3. Add `description` + `knowsAbout` to the `about.njk` ProfilePage Person node (lines ~145-161).
4. Extend `seo-aeo-drift-guard.test.ts` (#2711 block) to assert `knowsAbout` is the topical
   array and present on both Person emitters.

### Phase 2 — #3173 BlogPosting.image confirmation
1. Confirm `blog-post.njk:26` wiring (no change expected).
2. Add drift-guard assertion: posts with `ogImage:` frontmatter render that exact image in
   `BlogPosting.image`.
3. File deferral issue for bespoke OG images on the 11 imageless posts.

### Phase 3 — #3172 canonical-host audit
1. Run the AC6 grep; confirm zero canonical-bearing `www.` references.
2. Confirm built-output apex alignment via existing drift-guard (AC7).
3. No source edits expected. Document the audit + the #4577/#4584 prior-art in the PR body.

### Phase 4 — #3171 FAQPage coverage + parity
1. Coverage CONFIRMED at deepen time: `validate-seo.sh:122` (`find … -name '*.html'`) already
   loops over blog slugs, and the FAQ gate (line 198) already fails on FAQ-block-without-FAQPage
   across pages + blog. No gate edit. Verify the gate stays green post-build.
2. Add Q/A-text-parity drift-guard rows for `pricing`/`about`/`company-as-a-service`, reusing the
   HTML-entity normalization from the `#2707` precedent at `seo-aeo-drift-guard.test.ts:137`.

### Phase 5 — Build + validate + ship
1. `npm run docs:build`; run all SEO/JSON-LD tests + `validate-seo.sh`.
2. Open PR with the four `Closes #N` lines + the AC6 grep output + reconciliation summary.

## Files to Edit

- `plugins/soleur/docs/_data/site.json` — add `author.knowsAbout` topical array.
- `plugins/soleur/docs/_includes/blog-post.njk` — repoint `knowsAbout` (line 36).
- `plugins/soleur/docs/pages/about.njk` — add `description` + `knowsAbout` to ProfilePage Person.
- `plugins/soleur/test/seo-aeo-drift-guard.test.ts` — new assertions: topical `knowsAbout` on
  both Person emitters, per-post `BlogPosting.image`, Q/A parity on key FAQ surfaces.
- `plugins/soleur/skills/seo-aeo/scripts/validate-seo.sh` — **NOT edited.** Deepen-time
  verification confirmed the `find … -name '*.html'` loop (line 122) + FAQ gate (line 198)
  already cover all surfaces including blog. Listed here only to record the resolved check.

## Files to Create

- None (all edits are to existing files).

## Open Code-Review Overlap

1 open code-review issue touches a planned file:
- **#2965** (build-time critical-CSS extractor for `base.njk`, deferred from #2960) — **Acknowledge.**
  Different concern (CSS perf, not structured data). This PR does not touch the critical-CSS
  surface of `base.njk`; #2965 remains open for its own cycle.

## Domain Review

**Domains relevant:** Marketing (SEO/structured-data is the CMO's surface).

### Marketing
**Status:** reviewed (self-assessed; Task subagents unavailable in this environment)
**Assessment:** This is a CMO-domain SEO/AEO cleanup. The `knowsAbout` topical areas and FAQ
parity are AEO (AI-engine-optimization) signals; the canonical-host audit is SEO. No new
user-facing pages or flows. Audit refs cite the 2026-05-04 SEO audit + content plan. No
copywriter needed (no net-new prose beyond a ≤6-word topical-area list). No conversion/pricing
specialist needed.

### Product/UX Gate
Product domain NOT relevant — no new pages, no new components, no user flows. Tier: **NONE**.
No `components/**/*.tsx` or `app/**/page.tsx` created. Mechanical escalation does not fire.

## Infrastructure (IaC)

Skipped — this PR introduces NO new infrastructure. The canonical-host substrate
(`dns.tf`, `seo-rulesets.tf`, the GitHub-Pages-owned www→apex 301, the Sentry uptime monitor)
already exists and is NOT touched. #3172 is an audit-only confirmation that the EXISTING IaC
(shipped in #4577/#4584) already aligns all signals apex-ward. Pure docs-source change against
already-provisioned infra.

## Observability

Skipped — pure docs-source/template change. The static docs site has no runtime/server
surface. Structured-data correctness is guarded at BUILD time by `validate-seo.sh` (CI gate in
`deploy-docs.yml:75`) and `seo-aeo-drift-guard.test.ts`; runtime canonical-host drift is guarded
by the pre-existing `sentry_uptime_monitor.soleur_www` (= 301). No new dark surface introduced.

## GDPR / Compliance Gate

Skipped — no regulated-data surface. The only personal data is the founder's already-public
bio/social links in `site.json` (self-published, no third-party data, no processing activity).

## Deferrals

- **Bespoke OG images for 11 imageless blog posts (#3173 residual):** file a `domain/marketing`
  + `priority/p3-low` tracking issue. Re-eval criteria: when the gemini-imagegen/Pencil OG-image
  pipeline runs a batch for the remaining posts. Until then those posts use the default
  `og-image.png` (acceptable — template wiring is correct; the fallback is intentional). Cite
  milestone `Phase 4: Validate + Scale`.

## Risks & Mitigations

- **JSON-LD escaping:** all new `site.json`-sourced fields MUST pass through `| jsonLdSafe | safe`
  (NOT raw `dump`) — the `jsonLdSafe` filter (`eleventy.config.js:30`) applies the three required
  escapes (`</` → `<\/`, U+2028, U+2029) per learning
  `knowledge-base/project/learnings/2026-04-19-jsonld-dump-filter-not-enough-needs-jsonLdSafe.md`
  and `knowledge-base/project/learnings/integration-issues/2026-04-22-faqpage-jsonld-block-terminator-escape-placement.md`.
  The `knowsAbout` array and `description` are short controlled strings, but use the filter for
  consistency + breakout safety.
- **Canonical-constant grep (#3172):** per learning
  `knowledge-base/project/learnings/2026-05-29-canonical-constant-flip-must-grep-consumers-that-assert-old-value.md`,
  do NOT introduce any new hardcoded host literal — always use `{{ site.url }}`. The AC6 grep enforces this.
- **FAQ Q/A parity escaping (#3171):** the parity assertion must compare the JSON-LD
  `acceptedAnswer.text` AFTER `jsonLdSafe` decode against the visible `faq-answer` text — the
  rendered HTML entity forms (`&mdash;`, `&ndash;`) vs the JSON-LD em-dash must be normalized.
  Precedent: `seo-aeo-drift-guard.test.ts:137` (#2707 pricing FAQ parity) — reuse its
  normalization approach. No precedent for blog-surface FAQ parity; the assertion is a small
  extension of the #2707 pattern.
- **`validate-seo.sh` awk/grep scope (#3171):** if extending the FAQ gate to blog surfaces, the
  page-loop currently iterates a `pages` list; verify the blog slug glob is added without
  breaking the existing `_site/<page>/index.html` path shape.

## Test Strategy

Runner is `bun test` (existing SEO tests are `*.test.ts` under `plugins/soleur/test/`). Build is
Eleventy via `npm run docs:build` (`plugins/soleur/docs/package.json`). No new test framework.
All new assertions extend the existing `seo-aeo-drift-guard.test.ts` and reuse `validate-seo.sh`.
JSON-LD validity is checked by extracting `<script type="application/ld+json">` blocks from
`_site/` and piping through `jq`.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder
  text, or omits the threshold will fail `deepen-plan` Phase 4.6. (Filled above; threshold `none`.)
- #3172's issue body asserts the OPPOSITE of live reality (claims `apex→www`; live is `www→apex`).
  Do NOT "fix" the canonical direction — it is already correct. The work is audit + close.
- `blog-post.njk:26` already threads `ogImage` — do NOT re-implement #3173 as if the template is
  broken; the residual is missing frontmatter on 11 posts, not a template bug.
- The `validate-seo.sh` FAQ gate checks PRESENCE, not parity (per its own comment); parity is the
  net-new assertion this PR adds to the drift-guard, NOT to the CI shell gate.
