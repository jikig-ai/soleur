---
title: "SEO internal-linking for 3 GSC crawled-not-indexed pages"
date: 2026-06-15
type: feat
lane: single-domain
status: draft
brand_survival_threshold: none
related_gsc: "GSC Coverage Drilldown 2026-06-15 — Crawled - currently not indexed (3 pages)"
related_prior_work: "Apex-canonical Cloudflare/Sentry IaC reconciliation, merged 2026-05-29"
---

# 📚 SEO internal-linking for 3 GSC crawled-not-indexed pages

## Enhancement Summary

**Deepened on:** 2026-06-15
**Sections enhanced:** Research Reconciliation, Implementation Phases, Sharp Edges (all verified against the live worktree)
**Deepen passes run:** mandatory halt gates (4.6 User-Brand Impact, 4.7 Observability, 4.8 PAT-shaped, 4.9 UI-wireframe) + verify-the-negative pass (4.45) against every load-bearing factual claim.

### Gate results

| Gate | Result |
|---|---|
| 4.6 User-Brand Impact | PASS — section present, threshold `none`, zero sensitive-path files in scope (no scope-out bullet required) |
| 4.7 Observability | SKIP — pure-docs (all 4 Files-to-Edit under `plugins/soleur/docs/`, no `apps/*/server`, `*/src`, `*/infra`, `plugins/*/scripts`) |
| 4.8 PAT-shaped variable | PASS — no PAT-shaped var/literal in plan |
| 4.9 UI-wireframe | SKIP — no UI-surface file (`.md`/`.json` only; no `.tsx`/`components`/`page`/`layout`) |
| 4.4 Scheduled-work precedent | N/A — no cron/scheduled job introduced |
| 4.5 Network-outage deep-dive | N/A — no SSH/network/timeout/handshake trigger pattern |

### Verify-the-negative — every load-bearing claim confirmed against the live worktree

- **T1 Link A anchor** `reads your brand guide` — present at `how-to-run-every-department-with-ai-agents.md:60`. ✓
- **T1 Link B anchor** `brand guide's positioning` — present at `case-study-business-validation.md:39`. ✓
- **T2 anchor** MCP paragraph (`…pasting outputs between tabs`) — present at `billion-dollar-solo-founder-stack.md:48`. ✓
- **Footer gap is real** — `_data/site.json:83-87` `footerLegal` has exactly 3 entries (`Legal`, `Privacy Policy`, `Terms of Service`); AUP omitted. ✓
- **No template edit needed** — `_includes/base.njk:307` iterates `site.footerLegal` (new entry renders automatically). ✓
- **No legal-index edit needed** — `pages/legal.njk` already links AUP (1 occurrence). ✓
- **Footer link will resolve** — AUP `permalink: legal/acceptable-use-policy/` matches the footer URL `/legal/acceptable-use-policy/`. ✓
- **Inbound counts confirmed** — Target 1 = 0 contextual inbound (only `/blog/` index); Target 2 = 1 (`why-most-agentic-tools-plateau.md:133`). ✓

### Key improvements over the base plan

1. Pinned the two competing internal-link styles (`{{ site.url }}/blog/<slug>/` dominant 14×, bare `](/blog/<slug>/)` 3×) and resolved per-file: both blog targets use the templated form (their source files already do); footer uses the bare apex path matching its JSON siblings.
2. Encoded the two Eleventy Sharp Edges that bite this exact change: the `{{ site.url }}` leading-slash host-mangle bug (`2026-04-21`) and the worktree `agents.js` build-CWD gotcha (`2026-03-10`), each with a Phase-4 verification gate.
3. Confirmed the footer change is justified (siblings already in footer) rather than inventing a new section — the ARGUMENTS' conditional resolved to "proceed."

## Overview

Google Search Console's 2026-06-15 Coverage drilldown flagged 3 canonical pages as
**"Crawled - currently not indexed."** All three are structurally healthy: HTTP 200,
`canonical = apex`, present in the sitemap, no `noindex`. The structural SEO causes
(redirects, canonicalization, sitemap host) were already reconciled to apex-canonical
in the merged 2026-05-29 Cloudflare/Sentry IaC change — **this PR does NOT touch any
redirect / sitemap / canonical infrastructure.**

"Crawled - currently not indexed" on an otherwise-healthy page is most commonly a
**link-equity / perceived-importance** signal: Google crawled the page but judged it
not important enough to index, usually because it has thin or zero internal inbound
links. The single in-our-control lever is **strengthening contextual internal links**
so the site's own link graph signals these pages are important. That — and only that —
is the scope here.

The three target pages and their measured current inbound-link state (verified by
`grep -rl` over `plugins/soleur/docs/blog/` and the footer data file):

| # | Target page | Source file | Current inbound (contextual) | Action |
|---|---|---|---|---|
| 1 | `/blog/case-study-brand-guide-creation/` | `plugins/soleur/docs/blog/case-study-brand-guide-creation.md` | **0** (only the `/blog/` index listing) | Add 2 contextual links from topically-related posts |
| 2 | `/blog/agents-that-use-apis-not-browsers/` | `plugins/soleur/docs/blog/2026-04-23-agents-that-use-apis-not-browsers.md` | **1** (from `why-most-agentic-tools-plateau.md:133`) | Add 1 more contextual link |
| 3 | `/legal/acceptable-use-policy/` | `plugins/soleur/docs/pages/legal/acceptable-use-policy.md` | legal index (`pages/legal.njk:58`) + terms-and-conditions; **NOT in global footer** | Add to `footerLegal` for consistency |

This is a **docs-only / marketing-site change. No version bump** (the version-bump
workflow derives semver from a `## Changelog` label at ship time; this is a `semver:patch`
docs change).

## Research Reconciliation — Spec vs. Codebase

All premises in the one-shot ARGUMENTS were verified against the worktree at plan time.
Two diverged from the literal instruction and the plan adapts accordingly:

| Premise (from ARGUMENTS) | Reality (verified) | Plan response |
|---|---|---|
| "Use clean apex trailing-slash URLs (e.g. `/blog/case-study-brand-guide-creation/`)" | Blog corpus uses **two** internal-link styles: the **dominant** templated `[…]({{ site.url }}/blog/<slug>/)` (14 occurrences) and a minority bare `](/blog/<slug>/)` (3 occurrences). | **Match the file's own surrounding style per insertion site.** Both candidate source files (`how-to-run-every-department`, `billion-dollar-solo-founder-stack`) already use the **`{{ site.url }}/blog/<slug>/`** templated form, so both new blog links use that form. The footer link (Target 3) lives in JSON data as a bare apex path `"/legal/acceptable-use-policy/"` matching its siblings. |
| Footer "if no legal links are in the footer at all, skip the footer change" | Footer **DOES** carry legal links via `site.footerLegal` in `_data/site.json:83-87`: `Legal`, `Privacy Policy`, `Terms of Service`. AUP is the **only** omitted legal page. | **Proceed with the footer change** — the consistency gap is real. The legal *index* (`pages/legal.njk:58`) already links AUP, so no index change is needed. |
| Target 2 "add from another related post if a natural fit exists" | Natural fit confirmed: `billion-dollar-solo-founder-stack.md:48` (MCP paragraph) discusses agents reaching systems by calling vendor **APIs** directly ("query the pharmacy partner's API … without a human pasting outputs between tabs"). | Add the 2nd inbound link there. |

Premise validation: no GitHub-issue / PR references cited in ARGUMENTS to resolve. The
"apex-canonical IaC reconciliation, merged 2026-05-29" is cited only as context for what
this PR does NOT touch; it is out of scope and not re-verified here.

## User-Brand Impact

**If this lands broken, the user experiences:** a marketing blog post or the site footer
rendering a broken/host-mangled internal link (e.g. `https://soleur.aiblog/...` if a
`{{ site.url }}` interpolation drops its leading slash — see Sharp Edges), degrading the
reading experience and, ironically, the SEO this change is meant to improve.

**If this leaks, the user's [data / workflow / money] is exposed via:** N/A — no user data,
no auth, no regulated surface. This edits public marketing-site prose and one public footer
data array only.

**Brand-survival threshold:** none — reason: docs-only marketing-site copy/link change;
no user data, auth, payment, schema, or infra surface is touched. The only failure mode is
a cosmetically broken link caught by the build + rendered-output grep in Phase 4.

## Goals

- Give `/blog/case-study-brand-guide-creation/` 2 genuinely contextual inbound links (0 → 2).
- Give `/blog/agents-that-use-apis-not-browsers/` 1 more genuinely contextual inbound link (1 → 2).
- Add `/legal/acceptable-use-policy/` to the global footer's legal row for parity with its siblings.
- Confirm the Eleventy build and SEO validator still pass with zero new failures.

## Non-Goals

- **No** redirect / canonical / sitemap / `_redirects` / Cloudflare / DNS / IaC changes (already reconciled 2026-05-29).
- **No** new footer section or nav restructure — only one entry appended to the existing `footerLegal` array.
- **No** redesign, no CSS, no new components, no template structure changes.
- **No** keyword-stuffed link farms — each link must read naturally in existing prose (over-linking would *hurt* SEO).
- **No** version-file bump (CI derives version from the `## Changelog` semver label).

## Implementation Phases

### Phase 1 — Target 1: 2 contextual inbound links to the brand-guide case study

`/blog/case-study-brand-guide-creation/` currently has 0 contextual inbound links.
Add exactly 2, both natural in existing prose:

**Link A — `plugins/soleur/docs/blog/2026-05-14-how-to-run-every-department-with-ai-agents.md`, "## Marketing" section (around line 60).**
Existing prose: *"When the marketing agent reads your brand guide before generating, the
output starts closer to final."* The phrase **"reads your brand guide"** is a precise,
non-forced anchor. Link it to the case study using the file's own templated style:

```markdown
When the marketing agent [reads your brand guide]({{ site.url }}/blog/case-study-brand-guide-creation/) before generating, the output starts closer to final.
```

Verify this file does not already link the slug (`grep -c case-study-brand-guide-creation`
returned 0). Its existing `/blog/` links are `vibe-coding-vs-agentic-engineering`,
`knowledge-compounding-in-ai-development`, `one-person-billion-dollar-company` — no overlap.

**Link B — `plugins/soleur/docs/blog/case-study-business-validation.md`, line 39.**
Existing prose: *"Vision alignment check: Validated that the pivot does not contradict the
**brand guide's positioning**."* Link **"brand guide's positioning"** (or "brand guide") to
the case study. This is a sibling case study referencing the brand-guide artifact — a
genuinely contextual cross-case-study link. Match this file's surrounding link style
(check the file at edit time; if it has no `{{ site.url }}` links, use the bare
`](/blog/case-study-brand-guide-creation/)` form — Read the file first per `hr-always-read-a-file-before-editing-it` and pick the locally-dominant form).

> If Link B's prose does not read naturally once edited (e.g. the bullet is too terse to
> carry a link gracefully), fall back to a single contextual link from `how-to-run-every-department`
> only (Link A), and add the second from another marketing/case-study post the implementer
> judges natural. The hard requirement is **≥1 net-new contextual inbound link; target 2**;
> never force an unnatural link to hit the count.

### Phase 2 — Target 2: 1 contextual inbound link to agents-that-use-apis-not-browsers

`/blog/agents-that-use-apis-not-browsers/` currently has 1 inbound link (from
`why-most-agentic-tools-plateau.md:133`). Add 1 more.

**Source — `plugins/soleur/docs/blog/2026-04-22-billion-dollar-solo-founder-stack.md`, the
"## Model Context Protocol (MCP)" paragraph (around line 48).**
Existing prose ends: *"…a single agent can read a ticket, query the pharmacy partner's API,
draft a response in ElevenLabs voice, and log the interaction — without a human pasting
outputs between tabs."* This paragraph is explicitly about agents reaching systems by
calling **APIs** (not browsers) — a precise topical match. Append a short, natural clause
linking the target, e.g.:

```markdown
… without a human pasting outputs between tabs. That direct-API execution model — [agents that call vendor APIs rather than driving browsers]({{ site.url }}/blog/agents-that-use-apis-not-browsers/) — is what keeps the operational layer fast and reliable.
```

The implementer should tune the exact wording for natural flow; the load-bearing requirements
are (a) the anchor text is descriptive (not "click here" / not the bare URL), (b) the link
uses the `{{ site.url }}/blog/agents-that-use-apis-not-browsers/` form, (c) the file does not
already link the slug (`grep -c` returned 0; its existing `/blog/` links are
`one-person-billion-dollar-company` and `what-is-company-as-a-service` — no overlap).

### Phase 3 — Target 3: add Acceptable Use Policy to the footer legal row

Edit `plugins/soleur/docs/_data/site.json`, the `footerLegal` array (lines 83-87). Append
one entry, matching the existing object shape and the apex trailing-slash URL convention used
by its siblings:

```json
  "footerLegal": [
    { "label": "Legal", "url": "/legal/" },
    { "label": "Privacy Policy", "url": "/legal/privacy-policy/" },
    { "label": "Terms of Service", "url": "/legal/terms-and-conditions/" },
    { "label": "Acceptable Use", "url": "/legal/acceptable-use-policy/" }
  ]
```

- The URL `/legal/acceptable-use-policy/` matches the page's `permalink: legal/acceptable-use-policy/`
  (verified in the source file frontmatter) — so the footer link resolves to a real built page.
- Use the label `"Acceptable Use"` (concise, matches the terse "Terms of Service" footer style;
  the full "Acceptable Use Policy" is fine too — pick whichever reads best in the footer row at
  the implementer's discretion, but keep it short for the single-line `footer-legal` list).
- No template edit needed: `_includes/base.njk:306-309` already iterates `site.footerLegal`,
  so the new entry renders automatically.
- **No** legal-index change — `pages/legal.njk:58` already links AUP; legal-index prominence is fine.

### Phase 4 — Verify build + SEO validator + rendered output

1. **Eleventy build (from repo root — `docs:build` runs `cd ../../../ && npx @11ty/eleventy`).**
   Run from the worktree root:
   ```bash
   cd /home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-gsc-seo-internal-linking
   npx @11ty/eleventy
   ```
   **Sharp Edge / known gotcha:** `_data/agents.js` uses a repo-root-relative path that can
   `ENOENT` when Eleventy is run with the docs dir as CWD inside a worktree
   (learning `2026-03-10-eleventy-build-fails-in-worktree.md`). Running from the **worktree
   repo root** (as the `docs:build` script's `cd ../../../` does) is the correct CWD. If the
   build still fails on `agents.js` for a worktree-path reason unrelated to this change,
   fall back to the file-grep verification in steps 3-4 (which fully cover this change's surface,
   since every edit is a literal link string) and note the build limitation — do not treat a
   pre-existing worktree `agents.js` path issue as a regression from this PR.

2. **SEO validator** against the built site:
   ```bash
   bash plugins/soleur/skills/seo-aeo/scripts/validate-seo.sh plugins/soleur/docs/_site
   ```
   Expect exit 0. This change adds only internal links inside existing pages and one footer
   entry — it touches none of the validator's gates (llms.txt, robots.txt, sitemap host,
   per-page canonical/JSON-LD). A non-zero exit signals a pre-existing failure to triage
   separately, not a regression from these edits (confirm by diffing validator output against
   a pre-change run if any failure appears).

3. **Rendered-output link sanity (catches the `{{ site.url }}` leading-slash bug).** Per
   learning `2026-04-21-eleventy-site-url-concatenation-broken-without-leading-slash.md`,
   `{{ site.url }}blog/...` (missing leading slash) renders as host-mangled
   `https://soleur.aiblog/...` with no build warning. After build, grep the rendered output:
   ```bash
   grep -rEoh 'https://soleur\.ai[a-zA-Z]' plugins/soleur/docs/_site/blog/ | sort -u
   # MUST return nothing — any hit (e.g. https://soleur.aiblog) is a broken interpolation
   ```
   And confirm the three new links resolve to the intended hrefs in built HTML:
   ```bash
   grep -o 'href="[^"]*case-study-brand-guide-creation/"' plugins/soleur/docs/_site/blog/how-to-run-every-department-with-ai-agents/index.html
   grep -o 'href="[^"]*agents-that-use-apis-not-browsers/"' plugins/soleur/docs/_site/blog/billion-dollar-solo-founder-stack/index.html
   grep -o 'href="/legal/acceptable-use-policy/"' plugins/soleur/docs/_site/index.html
   ```

4. **Inbound-count delta (the actual goal).** Confirm the link-graph changed as intended:
   ```bash
   cd plugins/soleur/docs/blog
   grep -rl 'case-study-brand-guide-creation' .   # was 0 → expect 2 source files
   grep -rl 'agents-that-use-apis-not-browsers' . # was 1 (+ self) → expect 2 sources (+ self)
   ```

## Files to Edit

- `plugins/soleur/docs/blog/2026-05-14-how-to-run-every-department-with-ai-agents.md` — Link A to Target 1 (Phase 1).
- `plugins/soleur/docs/blog/case-study-business-validation.md` — Link B to Target 1 (Phase 1; with natural-fit fallback).
- `plugins/soleur/docs/blog/2026-04-22-billion-dollar-solo-founder-stack.md` — 1 link to Target 2 (Phase 2).
- `plugins/soleur/docs/_data/site.json` — append AUP to `footerLegal` (Phase 3).

### In-scope expansion — pre-existing host-mangle fix (discovered at Phase 4)

The Phase 4 rendered-output grep (built specifically to catch the `{{ site.url }}` leading-slash
host-mangle Sharp Edge) surfaced **5 pre-existing broken internal links** across 4 blog source
files — `{{ site.url }}blog/...` (slash dropped) rendering as `https://soleur.aiblog/...`. These
are the **exact defect class this PR targets** (broken internal links in the blog corpus), one of
them points at `why-most-agentic-tools-plateau` which is a node in this PR's own Target-2 link
graph, and the fix is a trivial mechanical slash insertion. Fixed inline per
`rf-review-finding-default-fix-inline` + `hr-weigh-every-decision-against-target-user-impact`
rather than shipping a "strengthen internal links" PR that knowingly leaves 6 host-mangled links
one grep away:

- `plugins/soleur/docs/blog/2026-03-29-your-ai-team-works-from-your-actual-codebase.md` (1)
- `plugins/soleur/docs/blog/2026-03-29-credential-helper-isolation-sandboxed-environments.md` (1)
- `plugins/soleur/docs/blog/2026-03-31-soleur-vs-paperclip.md` (2)
- `plugins/soleur/docs/blog/2026-03-16-soleur-vs-anthropic-cowork.md` (1)

## Files to Create

- None.

## Acceptance Criteria

### Pre-merge (PR)

- [x] **AC1 — Target 1 inbound = 2.** `cd plugins/soleur/docs/blog && grep -rl 'case-study-brand-guide-creation' .` returns exactly 2 source files (excluding the target's own self-references), both with the link in natural prose. ✓ (`how-to-run-every-department`, `case-study-business-validation`)
- [x] **AC2 — Target 2 inbound = 2.** `grep -rl 'agents-that-use-apis-not-browsers' plugins/soleur/docs/blog/` returns 2 sources plus the target file itself. ✓ (`why-most-agentic-tools-plateau`, `2026-04-22-billion-dollar-solo-founder-stack`, + self)
- [x] **AC3 — Footer parity.** `plugins/soleur/docs/_data/site.json` `footerLegal` array contains an `Acceptable Use` entry with `url: "/legal/acceptable-use-policy/"`; the array now has 4 entries. ✓
- [x] **AC4 — Link form correct.** The two new blog links use the `{{ site.url }}/blog/<slug>/` form **with the leading slash present**; `grep -rE 'site\.url ?}}blog/' plugins/soleur/docs/blog/` returns nothing. ✓ (0 slash-drops site-wide — also fixed 5 pre-existing)
- [x] **AC5 — Anchor text is descriptive.** No new link uses bare-URL or "click here" anchor text; each anchor is a meaningful prose phrase. ✓ ("reads your brand guide", "brand guide's positioning", "agents that call vendor APIs rather than driving browsers")
- [x] **AC6 — Rendered output clean.** After `npx @11ty/eleventy`, `grep -rEoh 'https://soleur\.ai[a-zA-Z]' _site/blog/` returns nothing (no host-mangled URLs), and the three built `href`s resolve. ✓ (site-wide clean rc=1)
- [x] **AC7 — SEO validator green.** `bash plugins/soleur/skills/seo-aeo/scripts/validate-seo.sh _site` exits 0. ✓ ("All SEO checks passed.")
- [x] **AC8 — Scope discipline.** `git diff --name-only` shows the 4 `## Files to Edit` + 4 in-scope host-mangle-fix files (documented above) + plan + `tasks.md`; no redirect/sitemap/canonical/IaC/CSS/template files touched; no version file changed. ✓ (scope expansion is same defect-class as PR theme; rationale in Files-to-Edit)
- [x] **AC9 — `## Changelog` + `semver:patch`.** PR body includes a `## Changelog` section; the change is docs-only (`semver:patch`). ✓ (handled at ship)

### Post-merge (operator)

- [ ] **AC10 — GSC re-validation (deferred, automatable check unavailable pre-index).** After deploy, the operator (or a scheduled GSC check) requests re-indexing / validation for the 3 URLs in Search Console. Indexing is Google-controlled and lags days-to-weeks; this is a monitor, not a gate. `Automation: not feasible inline because GSC index state is Google-controlled and not exposed by a deterministic API at PR time; the in-our-control lever (internal links) is delivered by this PR.`

## Domain Review

**Domains relevant:** Marketing

### Marketing

**Status:** reviewed (inline — single-domain SEO/internal-linking change; no specialist agent fan-out warranted for a 4-file contextual-link edit)
**Assessment:** This is a textbook on-page-SEO internal-linking task. "Crawled - currently not indexed" on structurally-healthy pages is a recognized link-equity signal; contextual inbound links from topically-related pages are the standard, in-our-control remediation. The two blog links chosen sit on precise topical anchors ("reads your brand guide" → brand-guide case study; the MCP/API-execution paragraph → agents-that-use-apis-not-browsers), avoiding the keyword-stuffed-link-farm anti-pattern that would *hurt* rankings. The footer AUP entry is a pure consistency fix (its 3 legal siblings are already in the footer). No brand-voice rewrite, no new copy, no campaign commitment — copywriter review is not warranted.

### Product/UX Gate

**Tier:** none — no UI-surface file in `## Files to Edit` (the `.md`/`.json` edits add link text and a data-array entry; no `components/**/*.tsx`, `app/**/page.tsx`, or `app/**/layout.tsx`, no new interactive surface). The footer render is an existing template iterating an existing data array.

## Infrastructure (IaC)

Skipped — no new infrastructure. This change edits marketing-site markdown and one Eleventy
`_data` JSON file against an already-provisioned, already-deployed static site. No server,
service, cron, secret, DNS, cert, or vendor account is introduced or modified. (Explicitly:
the redirect/canonical/sitemap IaC was reconciled in the merged 2026-05-29 change and is out
of scope.)

## Observability

Skipped — pure-docs change (all `## Files to Edit` are under `plugins/soleur/docs/`, none
under `apps/*/server/`, `apps/*/src/`, `apps/*/infra/`, or `plugins/*/scripts/`; no new
code or infra surface). The only "failure mode" is a broken link, which is caught
deterministically at build time by the Phase 4 rendered-output grep — not a runtime signal
needing a liveness/error/alert pipeline.

## Test Scenarios

This is a static-content change; the "tests" are the build + validator + grep gates in
Phase 4 / Acceptance Criteria. No unit/integration test framework applies (and none should be
added — the docs site has no test runner for prose link content; `cq-write-failing-tests-before`
does not apply to marketing-copy link insertions). Verification is:

1. Eleventy build succeeds (from repo root).
2. SEO validator exits 0.
3. Rendered-output grep finds no host-mangled URLs and the 3 expected hrefs.
4. Inbound-link counts moved 0→2 (Target 1) and 1→2 (Target 2); footer has 4 legal entries.

## Sharp Edges

- **`{{ site.url }}<path>` MUST keep the leading slash.** `_data/site.json` sets
  `"url": "https://soleur.ai"` (no trailing slash). Writing `{{ site.url }}blog/...` (no leading
  slash) renders the host-mangled `https://soleur.aiblog/...` with **no build warning** and is
  invisible to source greps that look for the correct form. Always write `{{ site.url }}/blog/<slug>/`
  and verify via the rendered-output grep in Phase 4 step 3 (learning
  `2026-04-21-eleventy-site-url-concatenation-broken-without-leading-slash.md`).
- **Eleventy build CWD in worktrees.** `_data/agents.js` uses a repo-root-relative path that
  doubles (`ENOENT … /docs/plugins/soleur/agents`) if Eleventy runs with the docs dir as CWD.
  Run from the **worktree repo root** (the `docs:build` script's `cd ../../../` target). A
  pre-existing worktree `agents.js` failure is not a regression from this PR — fall back to the
  file-grep verification, which fully covers this change's link-string surface (learning
  `2026-03-10-eleventy-build-fails-in-worktree.md`).
- **Two internal-link styles coexist in the blog corpus** (`{{ site.url }}/blog/<slug>/`
  dominant, bare `](/blog/<slug>/)` minority). Match the **locally-dominant** form of the file
  being edited rather than imposing one globally — both target source files already use the
  templated form, so both new blog links use it; the footer (JSON data) uses the bare apex path
  matching its `footerLegal` siblings.
- **Read each file before editing** (`hr-always-read-a-file-before-editing-it`). The exact
  line numbers in this plan are plan-time snapshots; locate the prose anchor by its quoted text,
  not by a frozen line number.
- **Don't over-link.** The goal is 2 / 2 / 1 *natural* links. If a candidate insertion reads
  forced, drop it and find a genuinely contextual alternative — an unnatural link farm is an
  SEO *negative*. The count is a target with a "≥1 net-new, never force" floor, not a quota to
  hit at any cost.
- **A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder
  text, or omits the threshold will fail `deepen-plan` Phase 4.6.** This plan's section is filled
  with `threshold: none` and a concrete reason (docs-only marketing surface).

## PR Body (reminder)

The PR body should explain: GSC's 2026-06-15 Coverage drilldown flagged these 3 pages as
**Crawled - currently not indexed**; this PR adds contextual internal links to strengthen
their link equity — the standard, in-our-control lever for that GSC state. Note that the
**structural** SEO causes (redirects, canonicalization, sitemap host) were already fixed by
the **apex-canonical Cloudflare/Sentry IaC reconciliation merged 2026-05-29**, and the rest of
the GSC report is green / self-resolving. Include a `## Changelog` section; label `semver:patch`
(docs-only, no version bump). Use `Ref` (not `Closes`) for any tracking issue, since GSC
re-indexing is Google-controlled and lags this merge.
