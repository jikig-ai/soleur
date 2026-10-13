---
title: "feat(web): soleur.ai license-claim correction + KISS homepage declutter"
date: 2026-06-08
type: feat
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
cpo_signoff: APPROVE-WITH-CONDITIONS (2026-06-08, plan-time)
issue: 5038
pr: 5036
branch: feat-web-kiss-license-fix
brainstorm: knowledge-base/project/brainstorms/2026-06-08-web-kiss-license-fix-brainstorm.md
spec: knowledge-base/project/specs/feat-web-kiss-license-fix/spec.md
wireframe: knowledge-base/product/design/website/homepage-kiss-declutter.pen
---

# feat(web): soleur.ai license-claim correction + KISS homepage declutter

✨ Two separable changes to the public marketing site (the Eleventy site at
`plugins/soleur/docs/`, served at soleur.ai), shipped as **two commits on one branch**
so the legally-urgent license correction is never blocked by the gate-exposed declutter.

## Overview

The live site claims, present-tense, that Soleur is "Apache-2.0 open source." The actual
current license is **BSL 1.1** (`BUSL-1.1`); Soleur already migrated Apache→BSL (see
`knowledge-base/project/learnings/2026-02-24-bsl-license-migration-pattern.md`) but the
marketing site was never swept — this is stale Apache-era drift. BSL converts to Apache-2.0
only four years after each release, and **BSL 1.1 is not OSI-approved, so "open source" is
itself a misrepresentation**, not only the word "Apache."

**Commit 1 (license sweep + guard):** correct every present-tense license claim and add a
CI regression guard. **Commit 2 (KISS declutter):** apply the UX lead's documented KISS
principle (`plugins/soleur/agents/product/design/ux-design-lead.md:45`) to `index.njk` per
the committed wireframe.

CPO signed off **APPROVE-WITH-CONDITIONS** at plan time (threshold = single-user incident).
Conditions are folded into the phases and ACs below.

## Research Reconciliation — Spec vs. Codebase

| Spec / brainstorm claim | Codebase reality (verified) | Plan response |
|---|---|---|
| "14 files" need the license sweep | Authoritative `git grep` shows claims also in `pages/agents.njk:31`, `pages/company-as-a-service.njk:192`, `pages/vision.njk:175`, and `getting-started.njk` has ~15 hits (not 1). The set is larger and not centralized (`_data/site.json` holds no license string). | Sweep is **grep-derived**, not a fixed list. Phase 0 re-runs the authoritative grep and Files-to-Edit is its output. |
| License fix is "text-only, no test impact" | `seo-aeo-drift-guard.test.ts:843-847` **hard-asserts** `/getting-started/` cites `https://www.apache.org/...LICENSE-2.0`. The sweep removes that citation → the test fails. | **Coupled edit** in Commit 1: update the test's mandated-citation host to the BSL/LICENSE URL the page will now cite. |
| Add a regression guard (new file) | `plugins/soleur/test/marketing-content-drift.test.ts` already walks site copy (`walkSiteCopy`) with an allowlist mechanism; Test 2 (banned `\bSpark\b`) is the exact template. Auto-run by `bun test plugins/soleur/` (`ci.yml:324`). | Guard is a **new test case in that file**, not a new file. |
| Declutter: "fold standalone newsletter into final CTA" | The standalone newsletter is a **site-wide include** (`base.njk:254 {% include "newsletter-form.njk" %}`), not an index.njk element, and posts `tag=newsletter` — a **different Buttondown segment** from the waitlist (`tag=waitlist`). | **DROP the newsletter-fold** (spec-flow defect: global include + segment loss). See Non-Goals. |
| JSON-LD twins editable as plain prose | License-claim FAQ twins (`index.njk:253,269`; `pricing.njk:355`; `about.njk:126`) are **static JSON string literals** (no `jsonLdSafe` filter). Interpolated twins require `(...) | jsonLdSafe | safe`. | Hand-edit prose **and** static twin, keep JSON valid. Do not introduce raw interpolation without the filter. |
| Closure grep can return zero (spec AC) | `pages/legal/{terms-and-conditions:199, gdpr-policy:84, disclaimer:43}.md` legitimately say "converts to Apache-2.0" — the naive grep never reaches zero (plan-review P0-A). | AC + guard **exclude `pages/legal/**`** and present-tense-anchor (skip `converts\|change date\|Prior versions\|remain under`). |
| "open source" misrepresentation = blanket ban | A blanket "open source" ban false-positives on legitimate **ecosystem** usage (`claude-code-plugins.njk`, MCP "open standard", contribution practices). The defect is *Soleur-subject* claims only (plan-review P0-C/D). | Guard bans Soleur-subject phrasings (`is open source`, `open-source version/platform`, `open source under`), not bare "open source". `getting-started.njk:32` definition lead corrected (was routed to defer). |

## User-Brand Impact

**If this lands broken, the user experiences:** a half-corrected site that still says
"Apache-2.0" in a comparison table, FAQ rich snippet, or the site-wide meta summary — i.e.
the live misrepresentation persists where a visitor reads it.

**If this leaks, the user's rights are exposed via:** a visitor relies on the "Apache-2.0"
claim to fork or self-host Soleur under Apache freedoms (e.g. standing up a competing hosted
service, which BSL 1.1 forbids until the change date), then discovers the real license — a
license-reliance trust + legal-exposure breach. The claim also propagates into search/AI
answers via JSON-LD, widening reach beyond the homepage.

**Brand-survival threshold:** single-user incident. The correction must be exhaustive for
Tier A; CPO sign-off obtained at plan time; `user-impact-reviewer` runs at PR review.

## Implementation Phases

### Phase 0 — Asserting-consumer + scope sweep (verification, no edits)

1. Re-run the authoritative claim inventory and freeze Files-to-Edit:
   `git grep -in "apache\|open source\|open-source\|LICENSE-2\.0" -- 'plugins/soleur/docs/_includes/**' 'plugins/soleur/docs/pages/**' 'plugins/soleur/docs/index.njk' 'plugins/soleur/docs/blog/**'`
2. Grep **asserting consumers** of the old value (constant-flip learning
   `2026-05-29-canonical-constant-flip-must-grep-consumers-that-assert-old-value.md`):
   `git grep -in "apache\|open source\|LICENSE-2\.0" -- 'plugins/soleur/test/**' '.github/workflows/**'`
   Triage each hit: does it **assert** the old value? Known: `seo-aeo-drift-guard.test.ts:843-847`
   (Apache citation), and check `seo-aeo-drift-guard.test.ts` Test 16 (marketing-copy invariants)
   and `deploy-docs.yml` for any canonical/host grep gate.
3. `npm install` already ran in the worktree; confirm `ls node_modules/@11ty/eleventy/package.json`
   exists (worktrees don't share node_modules; raw `npx @11ty/eleventy` silently hangs without it).

### Phase 1 — Commit 1: license sweep + regression guard

**Two claim classes (replaces the earlier Tier A/B framing per plan-review).** A *Soleur-subject
license claim* = any copy that tells the reader **Soleur** is Apache-licensed or open-source. A
*generic/ecosystem* "open source" = accurate statements about the plugin ecosystem, MCP being an
"open standard", contribution practices, or the code of conduct — these are **kept** (true, not
license claims). Only Soleur-subject claims are corrected.

**Phrasing contract (from CLO + CPO):**
- Hero badge / terse surfaces → **"Source-available — BSL 1.1"**, and either carry the clause
  "converts to Apache-2.0 four years after each release" **or** link the canonical explainer:
  the T&C licensing section (`pages/legal/terms-and-conditions.md:188-199`, already correct and
  reader-friendly). A terse "BSL 1.1" with no clause and no link is a dead-end term (spec-flow #2).
- Never flatten to "not open source" (contradicts the T&C, which says it *converts* to Apache).
- Marketing surfaces may use the **version-flat** phrasing, but must not contradict the canonical
  carve-out in T&C: *"versions v3.0.10 and earlier remain Apache-2.0; later versions convert after
  4 years."* Do not assert "all versions are BSL" (architecture P1.4).

**SWEEP NOW — all Soleur-subject claims across evergreen surfaces (pages + includes + index + blog
comparison tables). This collapses the former Tier-A/Tier-B-evergreen into one sweep so no
"gray-zone" page is left half-corrected (architecture P0.1/P0.3, spec-flow #3/#5/#6):**
- `_includes/page-freshness.njk:20 AND :22` — both `_summary` branches carry "Apache-2.0 open
  source"; edit BOTH (site-wide meta — highest reach; a one-branch miss persists on half the site).
- `_includes/base.njk:103,106` — Offer "Self-Hosted (Open Source)" / "Free and open source".
- `index.njk:16` (hero "the open-source Company-as-a-Service platform"), `:33` CTA ("Or try the
  open-source version" → reconcile wording with `:281` which already says "free self-hosted
  version"; pick ONE — recommend "Or self-host it free →"), `:197,205` prose + `:253,269` JSON-LD
  twins.
- `pages/about.njk:33,51,74` positioning + `:81/:123` FAQ `<summary>`/`name` "Is Soleur open
  source?" + `:82/:126` answer prose/twin (FAQ answer prose pinned below).
- `pages/getting-started.njk` — `:32` page-definition lead ("Soleur is an open-source Claude Code
  platform" — **must** change; it's the AI-extractability exemplar), `:19` CTA, `:36` Apache link,
  `:47,50` section copy, FAQ prose `:163,167,171,175,187` + JSON-LD twins `:203,211,219,227,251`.
- `pages/pricing.njk:28,49` CTAs + `:303/:355` FAQ prose/twin.
- `pages/community.njk:47` ("an open-source Company-as-a-Service platform... The project is Apache
  2.0"). KEEP `:104,147` (generic "open source best practices" link + Contributor-Covenant code of
  conduct — ecosystem, not a Soleur license claim).
- `pages/compare-soleur-vs-cursor.njk:32,78,83,119,129` + `compare-soleur-vs-devin.njk:36,82,87,129`
  (prose + table cells "Open source (Apache 2.0)" + "install the open source version" CTAs).
- `pages/vision.njk:175`, `pages/agents.njk:31`, `pages/company-as-a-service.njk:192` (generic
  Soleur-subject "open source" positioning — reword to source-available).
- `pages/legal.njk:23` ("Soleur is an open-source project maintained by Jikigai" — sibling
  `legal/*.md` already say source-available; this index page is the inconsistent one, spec-flow #5).
- **KEEP (ecosystem, not Soleur license claims):** `pages/claude-code-plugins.njk:114,156,236`
  (generic plugin-ecosystem "open source"), MCP "open standard" references.
- **Blog comparison tables/prose (Apache claims only):** for each `blog/*.md` with an explicit
  Apache hit (3 files: `2026-03-16-...cowork`, `2026-03-17-...notion`, plus table cells), replace
  "Apache-2.0"/"Apache 2.0" → "source-available (BSL 1.1)". Generic blog-body "open source"
  positioning is DEFERRED (below).

**Pinned FAQ answer prose** (spec-flow #1 — the "Is Soleur open source?" FAQ must still answer the
user's real question: can I self-host free / inspect / modify). Use, in `about.njk:82/:126` and the
parallel `index.njk:197/:253`:
> "Soleur is source-available under BSL 1.1 — free to self-host for individual and internal business
> use, fully inspectable on GitHub, and it converts to Apache-2.0 four years after each release."

Reframe the `<summary>`/`name` from "Is Soleur open source?" to "Is Soleur free to self-host?" (keeps
`<summary>` ↔ FAQPage `name` parity that seo-aeo Test 1/13 enforces).

**DEFER (one filed CMO-owned follow-up issue, CPO condition 1):** dated **blog-post body** generic
"open source" *positioning* (narrative framing in the 12 comparison posts), excluding the explicit
Apache claims fixed above. Enumerate the deferred blog files in the guard allowlist comment + link
the issue. Rationale: blog bodies are append-only/dated, low-reliance, and the brand guide treats
open-source credibility as a positioning asset — a CMO call, not a typo. (DHH dissented, preferring
to sweep blog bodies now; CPO ruling governs at this threshold.)

**Coupled test edit:** update `seo-aeo-drift-guard.test.ts:843-847` — change the mandated
external-citation host from `apache.org` to **the in-repo `LICENSE`** the getting-started page now
cites: `{{ site.github }}/blob/main/LICENSE` (host `github.com`). Pin this single target (not
mariadb.com) so page edit + test edit can't diverge (Kieran P1-1, code-simplicity). Keep the ≥2
distinct-citation + Claude-docs + MCP-spec assertions intact.

**Regression guard (new test case in `marketing-content-drift.test.ts`):**
- (a) Over `walkSiteCopy(...)` (`_includes`/`pages`/`index.njk`, all `.njk`): assert **zero**
  Soleur-subject offenders — regex set: `Apache[- ]2`, `LICENSE-2\.0`, `Apache.*licensed`,
  `open[- ]source (version|Company-as-a-Service|Claude Code platform)`, `is open source`,
  `open source under`. **Anchor present-tense and exclude legitimate survivors:** skip lines
  matching `converts|change date|Prior versions|remain under` (the BSL→Apache conversion language).
  Add an explicit `pages/legal/**` skip with a comment mirroring the existing `PROSE_NUMERAL_ALLOWLIST`
  pattern — defensive even though `walkSiteCopy` is `.njk`-only and legal is `.md` (Kieran P1-2,
  architecture P0.2). Do NOT ban bare "open source" (false-positives on kept ecosystem usage).
- (b) Separate assertion over `blog/**.md`: **zero** explicit present-tense Apache-2.0 license claim
  (same present-tense exclusions). Distinct from (a) because blog's ban set is narrower (generic
  positioning deferred) — the two assertions cannot be merged. Documented in a comment.
- Allowlist comment: enumerate the deferred blog files + link the CMO follow-up issue (#5043).

**Out-of-scope, verified (architecture P1.3):** `README.md` and `plugin.json` already carry the
correct `BUSL-1.1` / source-available language and are NOT rendered into the Eleventy site
(`marketing-content-drift.test.ts:90-93` excludes README) — no edit needed.

### Phase 2 — Commit 2: KISS homepage declutter (`index.njk`)

Per wireframe `homepage-kiss-declutter.pen`:
- **CUT** the duplicate mid-page CTA: `<section class="landing-cta-mid">` at `index.njk:108`.
- **Hero `.hero-cta` (`:31-35`):** keep only the secondary link `:33` (reworded per Tier B,
  e.g. "Or self-host it free →"); **drop** `:32` "See Pricing & Join Waitlist" and `:34`
  "How Soleur compares" anchor. (/pricing/ + compare section stay reachable via nav/footer/scroll
  — spec-flow confirmed no stranded path.)
- **Final CTA `.landing-cta` (`:277-278`):** keep the form/button and its `.newsletter-status`
  aria-live node + success/error JS (do NOT drop them); replace **only** the H2 text at `:278`
  (verbatim repeat of the hero H1 "Stop hiring. Start delegating.") with a distinct closing line.
- **Compress** "This Is the Way" (`:59-60`) prose where it re-explains memory/compounding-KB
  already carried by the (kept) Compare section.
- **KEEP unchanged:** stats strip, departments section, workflow, Compare section, FAQ, footer,
  and the site-wide `newsletter-form.njk` include.
- **Gate clearance:** after the edit, build from repo root (`npm run docs:build` / the `docs:build`
  script — never raw `npx` from `docs/`) and run both `check-critical-css-coverage.mjs` and
  `screenshot-gate.mjs`. Risk is LOW (removing `landing-cta-mid` only reduces above-fold classes;
  `.hero-cta` is not an above-fold prefix; the screenshot gate's `.landing-cta h2` element is
  preserved), but if any above-fold selector shifts, re-inline its rule into `base.njk:140-215`.

## Files to Edit

- `plugins/soleur/docs/_includes/page-freshness.njk` (meta summary — both `:20` and `:22` branches)
- `plugins/soleur/docs/_includes/base.njk` (Offer schema; possible critical-CSS re-inline)
- `plugins/soleur/docs/index.njk` (Soleur-subject claims + declutter — Commit 2; `:33`↔`:281` reconcile)
- `plugins/soleur/docs/pages/about.njk`, `pricing.njk`, `getting-started.njk` (incl. `:32` definition
  + `:19` CTA + FAQ twins), `community.njk` (`:47` only — keep `:104,147` ecosystem),
  `compare-soleur-vs-cursor.njk`, `compare-soleur-vs-devin.njk`, `vision.njk`, `agents.njk`,
  `company-as-a-service.njk`, `legal.njk` (`:23`)
- **Keep (do NOT edit):** `pages/claude-code-plugins.njk` (generic plugin-ecosystem "open source")
- `plugins/soleur/docs/blog/*.md` (explicit Apache claims only — per Phase 0 grep; generic blog-body
  positioning deferred to the CMO follow-up issue (#5043))
- `plugins/soleur/test/marketing-content-drift.test.ts` (new regression-guard test case)
- `plugins/soleur/test/seo-aeo-drift-guard.test.ts` (coupled citation-host update)

## Files to Create

- None. (Regression guard extends an existing test file.)

## Acceptance Criteria

### Pre-merge (PR)
- [ ] Closure grep returns **zero**, with the legal dir excluded and present-tense anchored
  (the legal pages legitimately say "converts to Apache-2.0"):
  `git grep -inE "Apache[- ]2|LICENSE-2\.0|Apache-2\.0 licensed" -- 'plugins/soleur/docs/' ':!plugins/soleur/docs/pages/legal/' | grep -viE "converts|change date|Prior versions|remain under"`
  (P0-A: without the `:!legal` exclusion + present-tense filter this grep can never reach zero —
  `gdpr-policy.md:84`, `terms-and-conditions.md:199`, `disclaimer.md:43` are correct survivors).
- [ ] New `marketing-content-drift.test.ts` case fails on a seeded "Apache-2.0 licensed" line and
  passes on the swept tree; `bun test plugins/soleur/test/marketing-content-drift.test.ts` green.
- [ ] `seo-aeo-drift-guard.test.ts` green (Apache citation assertion updated to BSL/LICENSE host).
- [ ] `bun test plugins/soleur/` and the docs CI (`critical-css-gate`) green; `index.njk` declutter
  matches the wireframe; FAQ/Compare/stats/newsletter-include unchanged.
- [ ] Tier B deferral issue filed and linked in the guard allowlist comment.
- [ ] PR body uses `Ref #5038` (not `Closes`) — closure happens post-merge after deploy verify.

### Post-merge (operator/automated)
- [ ] `deploy-docs.yml` redeploys; spot-check live soleur.ai homepage + meta + a compare page show
  "source-available (BSL 1.1)" and no "Apache-2.0" (automatable via WebFetch).
- [ ] `gh issue close 5038` after live verification.

## Domain Review

**Domains relevant:** Legal, Marketing, Engineering, Product

Carried forward from brainstorm `## Domain Assessments` + plan-time CPO/spec-flow.

### Legal (CLO)
**Status:** reviewed
**Assessment:** BSL 1.1 not OSI-approved → "open source" itself is the misrepresentation. Phrasing
"source-available (BSL 1.1, converts to Apache-2.0 after 4 yrs)". Full cure requires Tier A
everywhere incl. blog tables/JSON-LD. Canonical `docs/legal/*` already correct.

### Marketing (CMO)
**Status:** reviewed
**Assessment:** Moderate declutter — cut duplicate mid-page CTA, collapse hero CTAs, de-dupe final
headline, compress prose overlap. Keep FAQ/Compare/stats (AEO + link-equity). Waitlist is primary action.

### Engineering (CTO)
**Status:** reviewed
**Assessment:** MEDIUM risk, no infra/data impact. 14+ non-centralized claim sites; mind JSON-LD
twins. Declutter can shift above-fold selectors → keep it a separable commit, re-inline if needed.

### Product/UX Gate
**Tier:** blocking
**Decision:** reviewed
**Agents invoked:** ux-design-lead (brainstorm Phase 3.55), spec-flow-analyzer, cpo
**Skipped specialists:** copywriter (CMO owned messaging in brainstorm; not separately recommended)
**Pencil available:** yes (wireframe committed at `knowledge-base/product/design/website/homepage-kiss-declutter.pen`, referenced in spec FR5)

#### Findings
- **CPO SIGN-OFF: APPROVE-WITH-CONDITIONS** — Tier A everywhere; Tier B blog-positioning deferred
  to a filed CMO issue (enumerated in allowlist); verify `page-freshness.njk` swept; guard asserts
  zero Apache anywhere. All conditions encoded in Phase 1 + ACs.
- **spec-flow:** newsletter-fold is a defect (global `base.njk` include, distinct `tag=newsletter`
  segment) → **dropped from scope**. Hero (form + one link) is complete; /pricing/ + compare reachable
  via nav/footer/scroll; final-CTA `.newsletter-status` node must be preserved.

## Infrastructure (IaC)

None. No server, secret, vendor, DNS, or persistent runtime process introduced — the regression
guard is a bun-test case auto-discovered by existing CI (`ci.yml` `test-bun` job).

## Observability

Skipped — pure docs (`.njk`/`.md`) + a test-guard change. No new code-class file under
`apps/*/server|src|infra` or `plugins/*/scripts`, and no new runtime/infra surface.

## Open Code-Review Overlap

1 open scope-out touches a planned file: **#3531** ([flake] `marketing-content-drift.test.ts`
`beforeAll docs:build` exceeds 5s hook timeout). **Disposition: Acknowledge** — different concern.
The new guard test case reuses the in-process `walkSiteCopy` source-walk (no build), so it does not
add to the flaky `beforeAll` build hook. The flake remains tracked under #3531.

## Test Scenarios

- Seeded-negative: a line containing "Apache-2.0 licensed" in any `pages/**`/`index.njk` fails the
  new guard (proves the guard bites).
- Swept-positive: post-sweep tree passes the guard.
- JSON-LD validity: each edited `<script type="application/ld+json">` block still parses as JSON
  (manual — no test parses JSON-LD).
- Declutter: critical-CSS static + screenshot gates pass; wireframe parity by eye.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or placeholder fails `deepen-plan` Phase 4.6 —
  this one is filled and CPO-signed.
- **JSON-LD twin sync is not auto-guarded:** `seo-aeo-drift-guard` Test 1/13 match FAQPage `name` to
  `<summary>`, NOT the answer body — prose↔twin answer drift is invisible to CI. Hand-sync both, and
  keep punctuation JSON-valid (literal `</script>` terminator, em-dashes as raw UTF-8).
- **Worktree build:** always build from repo root via the `docs:build` script; raw `npx @11ty/eleventy`
  from `docs/` silently hangs (missing node_modules) or doubles `_data` paths.
- **Two-commit ordering:** Commit 1 (license + guard + coupled test) must land before Commit 2
  (declutter) so a screenshot-gate failure on the declutter never blocks the legal correction.

## Risks & Mitigations

- **Risk:** sweep misses a JSON-LD twin → site disagrees with its own rich snippet. **Mitigation:**
  Phase 0 grep is the closure; every prose edit pairs with its twin line; guard catches regressions.
- **Risk:** declutter trips the critical-CSS screenshot gate. **Mitigation:** LOW (no above-fold class
  added; `.landing-cta h2` preserved); run both gates pre-merge; re-inline into `base.njk` if needed.
- **Risk:** Tier B deferral silently widens. **Mitigation:** guard allowlist enumerates exact files +
  links the follow-up issue (CPO condition).
