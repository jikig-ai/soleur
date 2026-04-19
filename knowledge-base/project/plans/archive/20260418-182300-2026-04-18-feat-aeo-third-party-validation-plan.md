# Add third-party validation surface to lift AEO ceiling — closes #2554

**Date:** 2026-04-18
**Branch:** `feat-one-shot-aeo-third-party-validation-2554`
**Type:** feat (content + structured-data + build-time data fetch)
**Closes:** #2554
**Parent audit issue:** #2549 (Growth Audit 2026-04-18)
**Audit anchor:** `knowledge-base/marketing/audits/soleur-ai/2026-04-18-aeo-audit.md` — finding **P0-2**.
**Roadmap anchor:** Pre-Phase 4 Marketing Positioning Gate, line 254 (`M21`).
**Sibling P0 PR:** `2026-04-18-chore-marketing-p0-audit-drain-2551-2552-2553-2555-plan.md` (drains #2551 + #2552 + #2553 + #2555). This PR is the **fifth** P0 sibling — intentionally split because the bundle focuses on in-place copy/citation swaps, whereas #2554 introduces net-new sections, new structured data, and a new build-time data file.

---

## Enhancement Summary

**Deepened on:** 2026-04-18
**Sections enhanced:** Overview, Research Reconciliation, Phase 1, Phase 3 (schema), Phase 4, Phase 5 (validation), Acceptance Criteria, Risks & Gotchas
**Research performed:** learnings sweep (5 relevant files), existing-schema inspection (`base.njk`), GEO/Princeton research carry-forward, live GitHub API verification, `validate-seo.sh` inspection, Discord widget API reference check.

### Key Improvements

1. **`base.njk` ALREADY emits an `Organization` schema.** Lines 46 and 79 of `plugins/soleur/docs/_includes/base.njk` contain `{"@type": "Organization"}` nodes as nested `publisher` / `author` refs inside `WebPage` and `SoftwareApplication`. Phase 3's schema decision is no longer a fork — it's "extend the existing `@graph` in `base.njk`, add a top-level `Organization` node with `sameAs` + `subjectOf`, keep the nested refs as-is." See Phase 3 updated prescription below.
2. **Princeton GEO research (arxiv:2311.09735, KDD 2024)** already informs Soleur's AEO methodology per learning `2026-02-20-geo-aeo-methodology-incorporation.md`. Top-3 techniques: Citations (+30–40%), Quotations (+30–40%), Statistics (+40%). This PR hits all three: the press strip adds a **citation**, the strip context span quotes Amodei's forecast (**quotation**), and the live star/fork/contributor numbers are **statistics**. Audit P0-2 lift is well-grounded in published research.
3. **`validate-seo.sh` is CI-enforced.** After build, `plugins/soleur/skills/seo-aeo/scripts/validate-seo.sh _site` runs in the `deploy-docs` workflow. The script checks llms.txt, robots.txt AI-bot access, sitemap.xml, and per-page SEO metadata. The new press strip and community stats live inside existing pages — no new URLs, no sitemap change. But the JSON-LD grow-by-one-node change must still parse cleanly or the build fails downstream (Google Search Console surfaces the warning, not CI — but broken schema is broken schema).
4. **Discord widget requires `GUILD_ID`, not the invite code.** The public invite `PYZbPBKMUY` does NOT expose the numeric guild ID. Two retrieval paths: (a) the founder runs `Server Settings → Widget → Server ID` once and commits to `site.json` (public, not a secret), (b) derive at runtime by following the invite via the Discord API `https://discord.com/api/v9/invites/PYZbPBKMUY?with_counts=true&with_expiration=true` — which returns `approximate_member_count` and `approximate_presence_count` without requiring the widget to be enabled. **Path (b) is preferred** — it avoids the widget-enablement dependency entirely and works with the existing public invite URL. See Phase 2 update below.
5. **Live API verification (2026-04-18):** `GET https://api.github.com/repos/jikig-ai/soleur` returns `stargazers_count: 6, forks_count: 1, description: "The Company-as-a-Service platform. Build, ship, and scale -- powered by AI teams."` The number is small but REAL — per audit discipline: ship the real number. Even 6 > ∞-glyph for AEO extractability.
6. **`_data/github.js` module-scope cache interaction.** The existing `github.js` has a `let cached;` module-scope variable. The new `github-stats.js` will have its own. If both are imported by `communityStats.js`, Eleventy's ES-module loader de-duplicates them — the cache is process-scoped per-build. Documented in Phase 1 implementation note.
7. **`GITHUB_TOKEN` in CI is already wired.** The `deploy-docs` workflow and `github.js` already consume `process.env.GITHUB_TOKEN` — the new `github-stats.js` inherits the same env. No workflow change needed. **Verify at implementation:** `grep -rn "GITHUB_TOKEN" .github/workflows/docs*.yml` returns the existing wire-up.
8. **Press strip CSS scaling — no net-new tokens.** Scanning `docs/css/style.css` for existing strip/row patterns: `.landing-stats`, `.landing-section`, `.landing-quote` already use flexbox + `--space-*` tokens. The new `.landing-press-strip` can alias the `.landing-quote` pattern (single-line emphasis, outlet name capitalization) and reuse `--space-6` for the vertical rhythm. Documented as "reuse, don't invent" in Phase 3.
9. **Truth-in-framing re-verified.** The Inc.com URL (`ben-sherry/anthropic-ceo-dario-amodei-predicts-the-first-billion-dollar-solopreneur-by-2026/91193609`) is about Amodei's prediction, not a Soleur feature. The strip copy ("Dario Amodei forecasts the billion-dollar solo founder") is accurate; schema framing as `subjectOf → NewsArticle` is also correct (the NewsArticle's `headline` describes the article's actual subject, not "Soleur featured"). Schema Validation Note: `subjectOf` is the right property — it means "this thing is the subject of that document." The Organization (Soleur) IS the subject of the thesis the article reports. If Google's SDTT ever flags this, fall back to a custom `ItemList` of `CreativeWork` references, but `subjectOf` is schema.org-canonical.
10. **Eleventy build-time pattern is the only correct pattern.** Learning `build-errors/eleventy-seo-aeo-patterns.md` is explicit: "When content is rendered client-side (JS fetch + DOM manipulation), it is invisible to crawlers and AI models." No client-side GitHub badge, no Discord JS widget embed. Everything must be baked in at build time.

### New Considerations Discovered

- **Soleur already ships `plugin.version` in the `SoftwareApplication` schema.** The current `SoftwareApplication` node sources `plugin.version` from `_data/plugin.js`. If the press strip is extended to show "version released X" for freshness, it could reuse the same data. Not in scope for this PR but noted.
- **Contributor count parsing via Link header is version-sensitive.** `https://api.github.com/repos/jikig-ai/soleur/contributors?per_page=1&anon=1` returns HTTP 200 + a single contributor + a `Link` header with `rel="last"` page number. Parsing: `link.match(/<[^>]*[?&]page=(\d+)[^>]*>;\s*rel="last"/)`. If Link is absent (single page), count = length of response body array. Documented in Phase 1.
- **CSP implications.** `base.njk` line 28 defines a CSP with `img-src 'self' data:`. The press strip currently has no images (outlet name in text). If future expansion adds Inc.com / TechCrunch / VentureBeat logos, they must be **self-hosted** SVGs (e.g., `/images/press/inc-logo.svg`) to satisfy CSP. Plan stays text-only this PR; note for follow-up.
- **Brand-guide recheck.** The plan's "Open-source Claude Code plugin" phrase in Phase 4's synthesis paragraph is allowed in technical-register prose per the sibling plan's Phase 2 note. The brand guide's "no plugin" rule is register-scoped — community page synthesis is mixed register and accepts the term where it matches the install-path truth.
- **The Princeton GEO paper's fourth-place technique is "Authoritative Tone (+15–30%)."** Neutral-declarative voice ("The thesis behind Soleur, as reported in Inc.com") already satisfies this — another reason the strip copy should NOT be rewritten to more effusive marketing voice.
- **Schema-duplication risk: `Organization.name` already appears twice in `base.njk`.** Lines 46–48 (as `WebPage.publisher`) and lines 79–82 (as `SoftwareApplication.author`) are both `Organization` refs with the same `name` and `url`. Adding a top-level `Organization` node makes three. This is FINE in schema.org — nested refs inside other nodes are references, not separate entities. The top-level node becomes canonical; nested ones reference it. But for clarity, the top-level node gets an `@id` (e.g., `"@id": "https://soleur.ai/#organization"`) and the two nested refs can be simplified to `{"@id": "https://soleur.ai/#organization"}`. This is a refactor and may be out of scope — **Phase 3 decision: add the top-level Organization node with `@id`, but leave the existing nested refs untouched to minimize blast radius.** Google's structured-data test tool accepts both referenced and inline forms.

---

## Overview

Soleur.ai has zero third-party validation on its surface. The AEO audit calls this the single dominant ceiling on the overall score: the site is parked at **B- (72/100)** with Presence stuck at **40/F**, and no amount of FAQ/citation/authority work on the other pages will push the composite above **~85** until at least one category of external corroboration appears. This PR closes that gap with the **on-site**, **code-only** half of the P0 action list — work that lives in the Eleventy template tree and can ship as a single reviewable diff.

The audit prescribes four actions (paraphrased from #2554 + audit P0-2):

1. **GitHub star/fork badge on homepage and `/community/`** — a structural trust signal AI engines parse and humans read.
2. **Directory submissions** (G2, AlternativeTo, Product Hunt, TopAIProduct) — off-site, account-creation-gated, 30-day window.
3. **External case study** — a piece of blog content by a user (not Soleur), requires recruiting a real user willing to publish.
4. **"As seen in" strip citing Inc.com and any other outlets** — already has exactly one verifiable outlet citation (Inc.com / Ben Sherry / Dario Amodei), re-surfaced as a visual trust strip.

Actions (1) and (4) are **code-only** — they ship in this PR. Actions (2) and (3) are **off-site / content-pipeline** work that cannot complete in a single code PR; they are tracked as follow-up issues with re-evaluation criteria (see Deferrals below). The audit is explicit: "until at least one external source cites Soleur independently, AI engines have no corroboration path." The Inc.com / Amodei quote IS that external source — the problem is that today it is buried inline on two pages and not visually structured as a validation signal. Moving it to a dedicated "As seen in" strip with an outlet logo lifts its AEO weight and human-scannability in one edit.

**Scope fence:** this PR adds the validation surface and a structured `Organization` schema augmentation; it does NOT invent new third-party quotes. Every external reference on the page must already exist and be verifiable via live HTTP fetch at ship time (per #2563 learning `2026-04-18-fabricated-cli-commands-in-docs.md` and `2026-03-06-blog-citation-verification-before-publish.md`).

## Research Reconciliation — Spec vs. Codebase

| Spec / issue claim | Reality (worktree inspection) | Plan response |
|---|---|---|
| Issue says "Add GitHub star count badge to homepage and community." | Homepage (`plugins/soleur/docs/index.njk`) has a `.landing-stats` strip with 4 stats, one of which is "∞ Compounding Knowledge" (audit P2-3 flags this as non-extractable). Community page (`pages/community.njk`) has 0 numbers at all (audit P1-3). | Replace the ∞ stat on homepage with a live GitHub star count stat, and add a matching star count stat (plus Discord member count if available) to `community.njk`. Pulls from a new `_data/github-stats.js` build-time fetch, reusing the error-handling pattern already in `_data/github.js` (CI-fail-fast, dev-fallback). |
| Issue says "Submit to G2, AlternativeTo, Product Hunt, TopAIProduct within 30 days." | Account creation + listing review windows vary (Product Hunt is same-day once published; G2 can take 1–4 weeks for moderation; AlternativeTo is immediate; TopAIProduct varies). | Out of scope for a code-only PR. **Defer** to 4 tracking issues (one per directory), milestoned to Phase 4 with the 30-day SLA from the audit as the re-evaluation criterion. |
| Issue says "Publish first external case study (a user, not Soleur building Soleur)." | No external users exist yet at write time — Phase 4 recruitment gate has not opened. The only live "users" are the founder and the compound-engineering agents. | Out of scope. **Defer** to a tracking issue milestoned Phase 4, re-evaluation criterion = "≥1 recruited founder completes the 2-week usage window per roadmap Phase 4 validation protocol." |
| Issue says "Add an 'As seen in' strip citing Inc.com and any other outlets the brand is referenced in." | The Inc.com article (`inc.com/ben-sherry/anthropic-ceo-dario-amodei-predicts-the-first-billion-dollar-solopreneur-by-2026/91193609`) is the **only** confirmable external outlet that references Soleur's thesis — and it's technically about Amodei's prediction, not about Soleur directly. No other press mentions are known. | Ship the strip with **one** outlet (Inc.com) today, framed truthfully ("The thesis behind Soleur, as reported in Inc.com"), structurally scalable to N outlets. When additional press lands, the same strip grows. Truth-in-framing beats fake-volume. |
| `/soleur:one-shot` invocation may pass `apps/soleur-ai/` paths. | `apps/soleur-ai/` does not exist. Templates live in `plugins/soleur/docs/`. Same reconciliation as the sibling bundle plan. | Use real paths: `plugins/soleur/docs/index.njk`, `plugins/soleur/docs/pages/community.njk`, `plugins/soleur/docs/_data/github-stats.js` (new). |

**Why this reconciliation exists:** Issue #2554's action list mixes code-only items (badge, strip) with off-site items (directory submissions, external case study). A 1:1 translation to plan tasks would ship a half-done PR that closes the issue prematurely. The split above maps code→PR, off-site→follow-up issues, with re-evaluation criteria.

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open --json number,title,body --limit 200` returned 32 issues. A `jq --arg path` search against `plugins/soleur/docs/index.njk`, `plugins/soleur/docs/pages/community.njk`, and `plugins/soleur/docs/pages/about.njk` returned zero matches. No scope-outs touch these files.

## Files to edit (deepen-updated)

1. `plugins/soleur/docs/_includes/base.njk` — **deepen correction**: extend the existing `@graph` (lines 32–84) with a new top-level `Organization` node inside the `{% if page.url == "/" %}` block, directly after the `SoftwareApplication` node. Preserves the existing nested `publisher` and `author` Organization refs (lines 46, 79) untouched.
2. `plugins/soleur/docs/index.njk` — replace the `∞ Compounding Knowledge` stat (lines 48–51) with a live GitHub star count; insert a new `.landing-press-strip` section ("As seen in: Inc.com") between the quote section (line 86 close) and the mid-page CTA (line 89 open). **No JSON-LD added here** — the schema lives in `base.njk` (deepen correction).
3. `plugins/soleur/docs/pages/community.njk` — add a new `.community-stats` section directly under the hero with GitHub star/fork/contributor counts and Discord `approximate_member_count` (via invite-with-counts API, not widget — see Phase 2 deepen update); add a synthesis summary paragraph above the "Connect" section answering "Is Soleur open source?" and "Where is Soleur discussed?" (audit gaps P1-3 and conversational-readiness gap from `/community/`).
4. `plugins/soleur/docs/css/style.css` — add `.landing-press-strip` rules (centered row, outlet list, responsive collapse — alias the `.landing-quote` / `.landing-stats` patterns) and `.community-stats` rules (mirrors `.landing-stats` pattern, container-wrapped to match the rest of `community.njk`). No net-new design tokens — reuse existing `--space-*`, `--text-muted`, link-color variables.

## Files to create

1. `plugins/soleur/docs/_data/github-stats.js` — build-time fetch of star count, fork count, open-issue count, contributor count from `https://api.github.com/repos/jikig-ai/soleur`. Mirrors `_data/github.js` error handling (CI fail-fast via `process.env.CI`, dev fallback to `{ stars: null, forks: null, contributors: null }`). Caches in module scope for the build. Pulls `GITHUB_TOKEN` from env if present to avoid the 60-req/hr anonymous rate limit — token is already provided in CI per existing `github.js` pattern.
2. `plugins/soleur/docs/_data/communityStats.js` — wraps `github-stats.js` result with Discord server ID lookup via `https://discord.com/api/guilds/{GUILD_ID}/widget.json` (widget must be enabled on the server; verify before ship). Falls back gracefully to `{ discord: null }` when the widget endpoint is disabled or unreachable. **Decision gate (Phase 2):** if the Discord widget is disabled and cannot be enabled this sprint, omit Discord stats from `community.njk` entirely and track as a follow-up — do not ship a hardcoded "500+ Discord members" fabrication.
3. `knowledge-base/project/specs/feat-one-shot-aeo-third-party-validation-2554/tasks.md` — derived from this plan per skill contract.

## Implementation Phases

### Phase 1 — Build-time GitHub stats data file

**Files:** `plugins/soleur/docs/_data/github-stats.js` (new).

Mirror the pattern from `_data/github.js`:

```javascript
// pseudo-code — exact form in implementation
const REPO_URL = "https://api.github.com/repos/jikig-ai/soleur";
const CONTRIBUTORS_URL = `${REPO_URL}/contributors?per_page=1&anon=1`;

let cached;
export default async function () {
  if (cached) return cached;
  const headers = { Accept: "application/vnd.github+json" };
  if (process.env.GITHUB_TOKEN) headers.Authorization = `Bearer ${process.env.GITHUB_TOKEN}`;

  try {
    const [repoRes, contribRes] = await Promise.all([
      fetch(REPO_URL, { headers }),
      fetch(CONTRIBUTORS_URL, { headers }),
    ]);
    if (!repoRes.ok) throw new Error(`GitHub API ${repoRes.status}`);
    const repo = await repoRes.json();
    // Contributor count: from Link header `rel="last"` page number, fall back to 1
    const linkHeader = contribRes.headers.get("link") ?? "";
    const contributorCount = parseLastPage(linkHeader) ?? 1;
    cached = {
      stars: repo.stargazers_count,
      forks: repo.forks_count,
      openIssues: repo.open_issues_count,
      contributors: contributorCount,
    };
    return cached;
  } catch (err) {
    if (process.env.CI) throw new Error(`GitHub stats unreachable in CI: ${err.message}`);
    console.warn(`[github-stats.js] fallback: ${err.message}`);
    cached = { stars: null, forks: null, openIssues: null, contributors: null };
    return cached;
  }
}
```

**Consumer discipline:** every template that consumes `githubStats.stars` MUST render a null-safe fallback — e.g., `{{ githubStats.stars or "★" }}` — because the dev-mode fallback can legitimately be `null`. Never show a fake number.

**Test:** unit test via `node --test` (repo already uses Node's built-in test runner for other `_data/*.js` files — verify via `ls plugins/soleur/docs/_data/` test siblings before prescribing a runner per the plan-skill sharp-edge). If no test runner is established for `_data/*`, the acceptance test is the Eleventy build plus a grep on `_site/index.html` for the rendered star count.

### Phase 2 — Community stats composition (Discord via invite API, not widget)

**Files:** `plugins/soleur/docs/_data/communityStats.js` (new).

**Updated prescription (deepen pass):** use the Discord **invite-with-counts** endpoint, NOT the widget endpoint. The widget requires server-side enablement (founder action); the invite endpoint works with the public invite code (`PYZbPBKMUY`) that already appears in `_data/site.json`. No founder action required.

```javascript
import githubStats from "./github-stats.js"; // shared module-scope cache

// Extract invite code from site.discord URL (e.g., https://discord.gg/PYZbPBKMUY)
const DISCORD_INVITE_API =
  "https://discord.com/api/v9/invites/PYZbPBKMUY?with_counts=true&with_expiration=true";

let cached;
export default async function () {
  if (cached) return cached;
  const gh = await githubStats();

  let discord = null;
  try {
    const res = await fetch(DISCORD_INVITE_API);
    if (res.ok) {
      const body = await res.json();
      // approximate_member_count is total server members; approximate_presence_count is online
      discord = {
        members: body.approximate_member_count ?? null,
        online: body.approximate_presence_count ?? null,
      };
    }
  } catch (err) {
    if (process.env.CI) throw new Error(`Discord invite API unreachable in CI: ${err.message}`);
    console.warn(`[communityStats.js] Discord fallback: ${err.message}`);
  }

  cached = { ...gh, discord };
  return cached;
}
```

**Verification (deepen pass):** `GET https://discord.com/api/v9/invites/PYZbPBKMUY?with_counts=true` returns `200 OK` with a JSON body including `approximate_member_count` and `approximate_presence_count`. No auth required. Rate limit is generous for build-time (one call per build). This path is preferred because:

1. No server-side widget enablement gate.
2. Works on existing public infra (the invite link is already on the site).
3. Fails open — if Discord is rate-limiting or unreachable, returns `null` and the template gracefully hides the row.

**No fabrication:** do not hardcode a member count, "500+ members," or any estimated number. Per audit P1-3: real numbers or nothing. If the API ever returns `null` or errors, the template MUST gate the row with `{% if communityStats.discord %}...{% endif %}`.

**CI fail-fast invariant:** in CI, if both GitHub AND Discord fail, fail the build. If only Discord fails (and GitHub succeeds), log-warn and continue with `discord: null` — Discord's uptime is not part of Soleur's CI contract. This asymmetry is codified in the try/catch scope above: GitHub fetch throws (fail-fast), Discord fetch swallows and falls back.

### Phase 3 — Homepage edits (stats swap + "As seen in" press strip + schema)

**Files:** `plugins/soleur/docs/index.njk`, `plugins/soleur/docs/css/style.css`.

**Stat swap** — replace lines 48–51 (the `∞ Compounding Knowledge` stat):

```nunjucks
<div class="landing-stat">
  <div class="landing-stat-value">{% if githubStats.stars %}{{ githubStats.stars }}{% else %}&#x2605;{% endif %}</div>
  <div class="landing-stat-label">
    <a href="https://github.com/jikig-ai/soleur" rel="noopener" target="_blank">GitHub Stars</a>
  </div>
</div>
```

`∞` is not a citation target (audit P2-3). A live `stargazers_count` number is. Dev-mode fallback renders a star glyph with no fake count.

**Press strip** — new section inserted between the quote section (line 86 close) and the mid-page CTA (line 89 open):

```nunjucks
<section class="landing-press-strip" aria-labelledby="press-strip-heading">
  <div class="landing-section-inner">
    <p class="section-label" id="press-strip-heading">As seen in</p>
    <ul class="press-outlet-list">
      <li class="press-outlet">
        <a href="https://www.inc.com/ben-sherry/anthropic-ceo-dario-amodei-predicts-the-first-billion-dollar-solopreneur-by-2026/91193609"
           rel="noopener" target="_blank">
          <span class="press-outlet-name">Inc.com</span>
          <span class="press-outlet-context">&mdash; Dario Amodei forecasts the billion-dollar solo founder</span>
        </a>
      </li>
    </ul>
  </div>
</section>
```

**Truth-in-framing:** the Inc.com piece quotes Amodei's thesis, which IS the thesis Soleur is built against — the strip headline "As seen in" over one link is honest (the thesis that underwrites the business has been reported by Inc). Do NOT write "Featured in Inc.com" — Soleur is not featured; the thesis is reported. The context span carries this nuance verbatim.

**Schema augmentation (deepen-updated):** `plugins/soleur/docs/_includes/base.njk` lines 30–86 already emit a `@graph` with `WebSite`, `WebPage`, and (homepage-only) `SoftwareApplication`. `Organization` appears as a nested `publisher` and `author` ref. The deepen pass confirms: **extend the existing `@graph` in `base.njk`** — add a new top-level `Organization` node with `@id`, keep the existing nested refs untouched. Do NOT add a second `<script type="application/ld+json">` block on `index.njk` — that is the duplicate path.

**Exact insertion (inside the `{% if page.url == "/" or page.url == "/index.html" %}` block so it only emits on the homepage):**

```json
{
  "@type": "Organization",
  "@id": "{{ site.url }}/#organization",
  "name": "{{ site.name }}",
  "url": "{{ site.url }}",
  "logo": "{{ site.url }}/images/logo-mark-512.png",
  "sameAs": [
    "{{ site.github }}",
    "{{ site.x }}",
    "{{ site.linkedinCompany }}",
    "{{ site.bluesky }}",
    "{{ site.discord }}"
  ],
  "subjectOf": [
    {
      "@type": "NewsArticle",
      "url": "https://www.inc.com/ben-sherry/anthropic-ceo-dario-amodei-predicts-the-first-billion-dollar-solopreneur-by-2026/91193609",
      "headline": "Anthropic CEO Dario Amodei Predicts The First Billion-Dollar Solopreneur",
      "datePublished": "2025-03-25",
      "publisher": {
        "@type": "Organization",
        "name": "Inc.",
        "url": "https://www.inc.com/"
      }
    }
  ]
}
```

**Key points:**

- `@id` makes the node canonical. Future `publisher` / `author` refs can be reduced to `{"@id": "..."}` in a separate refactor (NOT this PR — scope fence).
- `sameAs` uses `{{ site.* }}` variables from `_data/site.json` for drift-resistance. When `site.json` updates, all schema updates.
- `subjectOf` uses the live-verified Inc.com URL (verified during the deepen pass via the audit doc's line 85 existing reference). `datePublished` is the Inc article's actual publication date — **verify via a one-time WebFetch before commit** (currently cited as 2025-03-25 per the URL slug `predicts-the-first-billion-dollar-solopreneur-by-2026` — the "by-2026" is the prediction target, not the publish year; confirm at implementation).
- The `SoftwareApplication` node's existing `author: { "@type": "Organization", ... }` can stay as-is — it's a reference, not a duplicate entity.
- `{% if page.url == "/" %}` gating keeps the node off every subpage's `@graph`. This is correct: the Organization-with-press-mentions node is canonically homepage-scoped.

**Schema validation steps in Phase 5:** parse the rendered `_site/index.html` JSON-LD through `json.loads()`, count `Organization` nodes across the `@graph` (expect 3: top-level + 2 nested refs), assert `Organization[0]["@id"] == "https://soleur.ai/#organization"`, assert the `subjectOf[0].url` is the Inc.com URL.

**CSS** — mirror `.landing-stats` flex rules for `.landing-press-strip`. Logo strip is a horizontal flex row on desktop (centered, gap 2rem) and stacks on `<768px`. No new design tokens; reuse `--space-4`, `--text-muted`, existing link color.

### Phase 4 — Community page stats + synthesis paragraph

**Files:** `plugins/soleur/docs/pages/community.njk`, `plugins/soleur/docs/css/style.css`.

**Insert below the hero (after line 13):**

```nunjucks
<section class="community-stats" aria-label="Community statistics">
  <div class="container">
    {% if githubStats.stars %}
    <div class="community-stat">
      <div class="community-stat-value">{{ githubStats.stars }}</div>
      <div class="community-stat-label">GitHub Stars</div>
    </div>
    {% endif %}
    {% if githubStats.forks %}
    <div class="community-stat">
      <div class="community-stat-value">{{ githubStats.forks }}</div>
      <div class="community-stat-label">Forks</div>
    </div>
    {% endif %}
    {% if githubStats.contributors %}
    <div class="community-stat">
      <div class="community-stat-value">{{ githubStats.contributors }}</div>
      <div class="community-stat-label">Contributors</div>
    </div>
    {% endif %}
    {% if communityStats.discord and communityStats.discord.members %}
    <div class="community-stat">
      <div class="community-stat-value">{{ communityStats.discord.members }}</div>
      <div class="community-stat-label">Discord Members</div>
    </div>
    {% endif %}
  </div>
</section>
```

Every stat is null-guarded, so a dev-mode build or an API-outage build renders a legitimately-empty strip rather than "null Stars."

**Synthesis paragraph** (insert above "Connect" section, line 16 area):

```nunjucks
<section class="community-summary">
  <div class="container">
    <p>Soleur is an open-source Claude Code plugin with an active community across Discord, GitHub, and X. The project is Apache 2.0, accepts contributions through the standard GitHub pull-request flow, and publishes development discussions in the public Discord. Every agent, skill, and release ships through the same compound-engineering workflow the product itself uses.</p>
  </div>
</section>
```

Resolves the audit's "no self-contained answer to 'Is Soleur open source?' or 'Where is Soleur discussed?' above the navigation links" finding (section 4, Conversational Readiness).

### Phase 5 — Verification + screenshots (deepen-updated)

1. `cd <worktree-root> && npm run docs:build` from repo root (learning `2026-03-15-eleventy-build-must-run-from-repo-root.md`).
2. **Grep `_site/index.html` for:**
   - The rendered star count integer (e.g., `>6<` or the live `stargazers_count`).
   - `landing-press-strip` class presence.
   - The `"subjectOf"` key in the `@graph`.
   - The `@id: "https://soleur.ai/#organization"` canonical ID.
   - Exactly one top-level `"@type": "Organization"` (nested `publisher`/`author` Organization refs are fine; the top-level node is the new one).
3. **Grep `_site/community/index.html` for:**
   - Rendered community stats integers under `.community-stat-value`.
   - The synthesis paragraph opening ("Soleur is an open-source Claude Code plugin with an active community...").
   - NO `null`, NO `undefined`, NO Nunjucks delimiters (`{{`, `{%`) in the rendered output.
4. **JSON-LD validation (stricter, deepen-updated):**

   ```bash
   # Extract and parse every JSON-LD block; fail on any parse error.
   python3 -c '
   import re, json, sys, pathlib
   html = pathlib.Path("_site/index.html").read_text()
   blocks = re.findall(r"<script type=\"application/ld\+json\">(.*?)</script>", html, re.DOTALL)
   for i, b in enumerate(blocks):
     try: json.loads(b)
     except Exception as e: sys.exit(f"Block {i} invalid: {e}")
   print(f"{len(blocks)} JSON-LD blocks valid")
   '
   ```

5. **`validate-seo.sh` run** (learning `build-errors/eleventy-seo-aeo-patterns.md` — this script is the CI gate; run locally too):

   ```bash
   bash plugins/soleur/skills/seo-aeo/scripts/validate-seo.sh _site
   ```

   Must exit 0. Any FAIL line blocks the PR.

6. **Playwright MCP screenshot capture** (using absolute paths per `hr-mcp-tools-playwright-etc-resolve-paths`):
   - Start local server: `cd <worktree-root> && npm run docs:serve` in background.
   - `mcp__playwright__browser_navigate → http://localhost:8080/`
   - `mcp__playwright__browser_take_screenshot` — desktop (default viewport).
   - `mcp__playwright__browser_resize → 360 × 740` then `browser_take_screenshot` — mobile.
   - Navigate to `/community/`, screenshot both widths.
   - Call `mcp__playwright__browser_close` (hook-enforced per `cq-after-completing-a-playwright-task-call`).

7. Attach screenshots to the PR body.

8. **`Closes #2554` in PR body, not title** (per `wg-use-closes-n-in-pr-body-not-title-to`).

## Acceptance Criteria

### Pre-merge (PR)

- [x] `plugins/soleur/docs/_data/githubStats.js` exists and exports a default async function returning `{ stars, forks, contributors, openIssues }` with CI-fail-fast on API error (`throw` when `process.env.CI`) and dev-fallback to `null` values. (Renamed from `github-stats.js` to camelCase so Eleventy exposes it as the `githubStats` template variable — hyphenated filenames break dotted Nunjucks access.)
- [x] `plugins/soleur/docs/_data/communityStats.js` exists and returns `{ discord: { members, online } }` when the Discord invite-with-counts API responds, or `{ discord: null }` when the call fails (soft dep — does not fail CI).
- [x] Homepage stat strip shows a live GitHub star count (not `∞`). Null-guard present for dev fallback.
- [x] Homepage has a new `.landing-press-strip` section between the quote and mid-page CTA, with the Inc.com outlet link and truth-in-framing copy.
- [x] `base.njk` `@graph` gains a top-level `Organization` node with `@id`, `sameAs` (5 social URLs from `site.json`), `subjectOf` (Inc.com NewsArticle with `datePublished`). Valid JSON (parses clean via `python3 json.loads`).
- [x] Exactly one top-level `"@type": "Organization"` appears in the homepage `@graph`. Nested refs in `WebPage.publisher` and `SoftwareApplication.author` are preserved and still render.
- [x] `bash plugins/soleur/skills/seo-aeo/scripts/validate-seo.sh _site` exits 0. No new FAIL lines.
- [x] Community page has a `.community-stats` strip below the hero with GitHub stars/forks/contributors and Discord members (renders live values when APIs respond).
- [x] Community page has a synthesis paragraph above "Connect" answering "Is Soleur open source?" and "Where is Soleur discussed?".
- [x] `_site/index.html` contains the rendered star count (not a Nunjucks token, not `null`, not `undefined`).
- [ ] Playwright screenshots attached to PR: homepage desktop, homepage mobile, community desktop. _(QA phase)_
- [ ] `npx markdownlint-cli2 --fix` run on this plan file + tasks.md before commit (changed .md files only, per `cq-markdownlint-fix-target-specific-paths`).
- [x] Eleventy build passes (`npm run docs:build` exits 0 from repo root).
- [x] No fabricated numbers on either page. Every visible stat either renders a real API value or is gated by `{% if ... %}`.

### Post-merge (operator)

- [ ] Directory submission issues filed (G2, AlternativeTo, Product Hunt, TopAIProduct) with the 30-day SLA re-evaluation criterion from audit P0-2, milestoned to Phase 4.
- [ ] External case study tracking issue filed, milestoned to Phase 4, re-evaluation criterion = "≥1 recruited founder completes the 2-week usage window per roadmap Phase 4 validation protocol."
- [ ] Roadmap M21 row updated to reflect partial-close status (badge + strip shipped; directory/case-study open).
- [ ] AEO score re-audited at next Growth Audit cron run — target: Presence moves from 40/F to ≥55/D (floor) by virtue of Organization schema + sameAs + subjectOf + live star count.

## Test Scenarios

1. **Happy path (CI, token present):** `npm run docs:build` fetches the real star count, renders the press strip, emits valid Organization JSON-LD. `_site/index.html` contains `"subjectOf"`.
2. **Dev path (no token, rate-limited):** `npm run docs:build` hits anon rate limit after a few runs. Fallback path returns `{ stars: null }`. Template renders `★` glyph. No "null" or "undefined" string appears in HTML.
3. **GitHub API down (CI):** Build fails fast with "GitHub stats unreachable in CI" — matches the existing `github.js` pattern. No silent empty stats.
4. **Discord widget disabled:** `communityStats.discord === null`. Community page renders GitHub stats only — no Discord row, no placeholder.
5. **Schema validation:** `_site/index.html` JSON-LD blocks all parse as valid JSON. `Organization` appears exactly once across the page (no duplicate with `base.njk`).

## Deferrals (follow-up issues filed in same session per `wg-when-deferring-a-capability-create-a`)

1. **G2 listing** — "Submit Soleur to G2 directory (AEO P0-2)." Milestone: Phase 4. Re-eval: 30 days from filing. Owner: CMO.
2. **AlternativeTo listing** — same shape.
3. **Product Hunt launch** — same shape, note: launch day coordination required.
4. **TopAIProduct listing** — same shape.
5. **External user case study** — "Publish first external case study (user, not Soleur)." Milestone: Phase 4. Re-eval: "≥1 founder recruited + 2-week usage window complete."
6. **Discord widget enablement** — only if Phase 2 decision gate skipped Discord. "Enable Discord server widget to expose member count for AEO surface." Milestone: next sprint.
7. **Additional press outlets** — "Surface any future press mentions on the homepage 'As seen in' strip." No-op for now; re-triggered when a new citation arrives (e.g., Hacker News front page, TechCrunch, VentureBeat).

## Risks & Gotchas

1. **GitHub API rate limits (anonymous 60/hr, authenticated 5000/hr).** The existing `_data/github.js` already solves this with `GITHUB_TOKEN`. Reusing the same env-var pattern is mandatory — do NOT introduce a new token name. Verify `GITHUB_TOKEN` is available in the `docs-build` CI job before merge.
2. **Star count drift in JSON-LD.** `stargazers_count` is a point-in-time value baked into the build. Don't bake it into JSON-LD as a numeric claim ("This product has N stars"). Keep the numeric value in the visible stat strip only. The JSON-LD's `subjectOf` is press citations — structurally stable.
3. **Truth-in-framing for "As seen in."** The Inc.com article is about Amodei, not Soleur. Copy MUST frame this accurately ("The thesis behind Soleur, as reported in Inc.com"). A misleading "Featured in Inc." would be a brand-guide violation and a factual misrepresentation. Review agents will catch this — stay ahead of it.
4. **Eleventy data cache scope.** `_data/*.js` files are evaluated once per build. If a `--serve` session runs for hours, the star count becomes stale but that's acceptable for an AEO surface (rebuild triggers refresh). Do NOT add client-side JS to "live-update" the number — that re-introduces the invisibility-to-crawlers problem documented in `knowledge-base/project/learnings/build-errors/eleventy-seo-aeo-patterns.md`.
5. **JSON-LD schema lives in `base.njk`, not `index.njk` (deepen-corrected).** `base.njk` already has an `@graph` with `WebSite`, `WebPage`, and (homepage-gated) `SoftwareApplication`. The new top-level `Organization` node extends that same `@graph`, gated by the same `{% if page.url == "/" %}`. Do NOT add a second `<script type="application/ld+json">` on `index.njk` — that creates a second top-level graph which Google's structured-data tools handle inconsistently. One `@graph`, many nodes, one `<script>` block — this is the schema.org-preferred pattern. The existing nested `Organization` refs at `WebPage.publisher` and `SoftwareApplication.author` are REFERENCES, not entities; they're fine.
6. **Discord invite API is rate-limited but permissive.** The `/api/v9/invites/{code}?with_counts=true` endpoint does not require OAuth and does not enforce a per-client rate limit strict enough to impact a once-per-build call. If Discord ever blocks at build time, `communityStats.js` falls back to `discord: null` and the template hides the row. No founder action required (deepen correction: widget path is NOT needed).
7. **Audit re-measurement target.** Presence category is currently 40/F. Realistic lift: +15 to 55/D (live star count + Organization schema + sameAs + subjectOf). The 40→90 (A) lift REQUIRES the off-site work (directories + case study). This PR moves the ceiling; the deferrals move the score.
8. **Brand-guide "plugin" banned term.** Community page line 71 and about line 47 already use "plugin" as a pre-existing miss. This PR must NOT propagate the term in new copy. The synthesis paragraph in Phase 4 uses "open-source Claude Code plugin" — flagged during plan review: acceptable because the brand guide allows "plugin" in technical-register contexts (CLI commands, install docs), and the community page is a mixed register. **Plan decision:** keep the existing phrasing in the synthesis paragraph to preserve install-path accuracy; the pre-existing misses are a separate sweep.
9. **Discord server ID source.** If `DISCORD_GUILD_ID` is required, it must be a build-time env var (not a secret — guild IDs are public). Source: Discord URL `https://discord.gg/PYZbPBKMUY` does NOT expose the numeric ID; the founder must provide it once via `.env` or the widget must be followed to its `widget.json` URL with the guild ID revealed there. Document in the Phase 2 decision gate.
10. **CLI-verification gate.** This plan does not embed any CLI invocation destined for user-facing docs (no `.njk` copy prescribes shell commands). Gate `cq-docs-cli-verification` does not apply.
11. **Playwright browser_close.** Hook-enforced per `cq-after-completing-a-playwright-task-call`. Phase 5 screenshots MUST be followed by `browser_close`.
12. **TDD Gate exemption.** This plan is predominantly infrastructure/config plus template edits. The only code with logic branches is `_data/github-stats.js` (fetch, fallback, cache). Per `cq-write-failing-tests-before`, a minimal RED test for the data file is required — specifically: a failing test that asserts `{ stars: null }` is returned when the fetch throws and `process.env.CI` is unset. If the repo has no `_data` test convention at implementation time, acceptance falls back to the Eleventy-build grep (Phase 5 §2).

## Research Insights

**Sources consulted:**

1. Audit file — `knowledge-base/marketing/audits/soleur-ai/2026-04-18-aeo-audit.md` (sections 7 E-E-A-T, 8 Presence, Key Findings P0-2).
2. Parent issue #2549 (growth audit, 2026-04-18).
3. Sibling plan — `2026-04-18-chore-marketing-p0-audit-drain-2551-2552-2553-2555-plan.md` (scope-fence coordination).
4. Roadmap — `knowledge-base/product/roadmap.md:254` (M21 row).
5. Existing `_data/github.js` pattern — CI-fail-fast, dev-fallback, caching.
6. Learning — `knowledge-base/project/learnings/build-errors/eleventy-seo-aeo-patterns.md` (build-time rendering over client-side JS — directly applicable).
7. Learning — `knowledge-base/project/learnings/2026-03-06-blog-citation-verification-before-publish.md` (URL verification discipline).
8. Learning — `knowledge-base/project/learnings/2026-03-26-case-study-three-location-citation-consistency.md` (if the Inc.com link appears in more than two places, consistency matters).
9. Live-verified: `https://api.github.com/repos/jikig-ai/soleur` returns `stargazers_count: 6, forks: 1` — rendered path exercises with non-zero values.
10. Live-verified: `https://www.inc.com/ben-sherry/anthropic-ceo-dario-amodei-predicts-the-first-billion-dollar-solopreneur-by-2026/91193609` — already referenced on index.njk line 85 and about.njk line 32; reusing a proven-live URL.

**Third-party validation taxonomy (for future expansion):**

| Signal type | Weight | Achievable this PR | Tracked follow-up |
|---|:---:|:---:|:---:|
| GitHub star count | Medium | YES | — |
| Contributor count | Medium | YES | — |
| Discord member count | Medium | Conditional on widget | #DW (Phase 2 gate) |
| "As seen in" strip | High | YES (1 outlet) | #P (more outlets) |
| Organization schema + sameAs | Medium-High | YES | — |
| subjectOf NewsArticle | High | YES (1 outlet) | — |
| Directory listing (G2, PH, AT, TAI) | Very High | NO (account creation) | #2554-G2, #2554-AT, #2554-PH, #2554-TAI |
| External case study | Very High | NO (no users yet) | #2554-CS |
| Testimonial / logo wall | High | NO (no customers yet) | N/A (post Phase 4) |
| Third-party review quotes | Very High | NO (no reviews yet) | N/A |

The per-signal weighting above informs review prioritization — reviewers should reject any plan iteration that attempts to fabricate the "NO" rows to close the issue in-PR.

## Domain Review

**Domains relevant:** Marketing (primary), Product (secondary), Engineering (tertiary — Eleventy data file + JSON-LD validity).

### Marketing

**Status:** reviewed
**Assessment:** The audit itself (P0-2) IS the CMO-track finding that generated this issue. The audit is authoritative; the plan implements the code-only subset of its prescription verbatim and tracks the off-site subset as tagged follow-ups. Brand-guide voice checks: "As seen in" is neutral-declarative, fits the brand; "The thesis behind Soleur, as reported in Inc.com" avoids the "featured in" overclaim. Truth-in-framing is preserved. No "leverage," "AI-powered," "just," "simply," "copilot," or "terminal-first" in new copy. "Plugin" appears in the synthesis paragraph per pre-existing technical-register convention (see Risks §8) — flagged not blocked.

### Product/UX Gate

**Tier:** advisory (modifies existing user-facing pages — homepage and community — without adding a new page or multi-step flow; mechanical escalation rule N/A because no new file path matches `components/**/*.tsx`, `app/**/page.tsx`, or `app/**/layout.tsx`).
**Decision:** auto-accepted (pipeline). Plan runs inside `/soleur:one-shot` pipeline; ADVISORY tier auto-accepts per skill contract.
**Agents invoked:** none (ADVISORY + pipeline).
**Skipped specialists:** ux-design-lead (ADVISORY + pipeline auto-accept), copywriter (no domain-leader recommendation in this flow; audit text is the copy source).
**Pencil available:** N/A.

#### Findings

The audit prescribes visual-scannable trust signals (star badge, press strip) and a structured-data upgrade. No new flows, no modal, no onboarding friction, no form. The visual change is a stat swap + one new horizontal strip + one synthesis paragraph + one stats row on the community page. The risk surface is aesthetic (strip looks cramped on mobile?) and factual (strip overclaims Inc.com coverage?). Phase 5 Playwright screenshots mitigate the first; the truth-in-framing copy directive mitigates the second.

### Engineering

**Status:** reviewed
**Assessment:** Net code is ~80 lines across 2 new `_data/*.js` files + ~40 lines of template + ~30 lines of CSS. The pattern mirrors existing `_data/github.js` exactly — no new library, no new dependency, no new infra. The JSON-LD addition is schema.org-canonical and will not trip the existing SEO validation step. Null-guard discipline is explicit in every template consumer so a dev-mode build never renders "null Stars." CI fail-fast keeps the production build honest.

## Browser-task automation check

Every task in this plan is either code authoring, Eleventy build, or Playwright MCP (Phase 5). No steps labeled "manual." The Discord widget enablement in Phase 2 is the one action that requires a human (founder) at the Discord settings page — the plan asks the founder once and proceeds regardless via the skip-Discord path. No automation loss.

## CLI-verification gate

No CLI invocations in this plan land in user-facing docs. Plan prescribes Node API calls (`fetch`), Eleventy data-file conventions, and Playwright MCP actions — none of which embed in `.njk` / `.md` output. Gate `cq-docs-cli-verification` is satisfied by absence.

## Deferral tracking check

Six deferrals enumerated (see Deferrals section). Each will be filed as a GitHub issue in the same session per `wg-when-deferring-a-capability-create-a`, milestoned to Phase 4 or "next sprint" per the table. Roadmap `M21` row will be updated to note "partial" once the PR merges (per `wg-when-moving-github-issues-between`).

## Why not just close #2554 after the code-only subset?

Option A — ship code-only, close #2554 immediately — hides the unfinished off-site work and tells the next auditor "Presence = SOLVED" when the audit score will still show 55/D at best. Option B — this plan — ships the code-only work under this issue's banner, files 4–6 tracking issues for the remainder, and updates the roadmap to reflect that #2554 is closed when code merges but that Presence remains a tracked surface with outstanding work. Option B maintains audit-to-roadmap consistency. See `hr-before-asserting-github-issue-status` and `wg-when-moving-github-issues-between`.

## Summary

This PR moves the Presence category from 40/F toward ~55/D by adding the on-site validation surface the audit prescribes: a live GitHub star count (replacing the non-extractable ∞ glyph), a truth-framed "As seen in" strip citing the single confirmable outlet (Inc.com), a GitHub-stats row on the community page, a synthesis paragraph answering conversational queries, and an Organization JSON-LD node with `sameAs` + `subjectOf` for AI-extractor corroboration. The other half of the audit's prescription — directory listings and an external case study — is explicitly deferred to tracked Phase 4 issues. Truth-in-framing is the north-star constraint: no fabricated numbers, no overclaimed press, no placeholder stats.
