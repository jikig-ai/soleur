---
title: "feat(seo): migrate blog redirects to Cloudflare edge 301s and delete meta-refresh machinery"
type: feat
date: 2026-09-18
slug: blog-redirects-edge-migration
branch: feat-one-shot-3328-gsc-indexing-cleanup
issue: 3328
closes: 3328
lane: cross-domain
domain: seo / web-platform-infra
brand_survival_threshold: aggregate pattern
---

# feat(seo): migrate blog redirects to Cloudflare edge 301s and delete meta-refresh machinery

Closes #3328

## Enhancement Summary

**Deepened on:** 2026-09-18
**Sections enhanced:** 7 (Encryption Posture → schema YAML; consolidated Files to
Create/Edit/Delete; Downtime & Cutover; precedent-diff row; `include_subdomains`
proxied-subdomain claim corrected; #3379 status corrected; pillar-series member
shape pinned to `{url, relation}`)
**Research agents used:** sequential-fallback — no Task/agent tool in this
harness; all deepen passes (gate checks, verify-the-negative, post-edit
self-audit, precedent grep, issue-state verification) executed inline in order.

### Key Improvements

1. `## Encryption Posture` rewritten in the ledger schema shape (the deepen
   4.10 halt requires fielded `at_rest`/`in_transit` entries, not prose).
2. Consolidated `## Files to Create/Edit/Delete` added — the observability,
   UI-surface, and diff-scope gates all key on these lists.
3. `## Downtime & Cutover` added: the two-merge structure IS the zero-downtime
   path (additive edge rules verified live before origin stubs are deleted;
   CF Pages deploys are atomic).
4. Verify-the-negative pass corrected two claims: `include_subdomains` affects
   proxied subdomains `app`/`deploy`/`ssh`/`registry`/`www` (no `preview`
   record exists in the zone), and #3379 is CLOSED, not an open tracker.
5. `www-apex-canonicalizer{,-mutation}.test.sh` compatibility verified by
   reading the harness — `dynamic "item"` appended after the explicit items is
   outside the green-row reorder span region.

### New Considerations Discovered

- `seo-bulk-redirects.tf`'s own header comment references
  `page-redirects.njk` — added to the PR-B comment-cleanup task.
- The pillar-series member shape is `{ url, relation: "pillar"|"cluster" }`;
  titles resolve via `collections.blog` — the plan now names which post holds
  `relation: "pillar"` in each new series.

## Deepen-Plan Gate Results

Run 2026-09-18 (sequential inline passes — no Task tool available).

| Gate | Result |
|---|---|
| 4.4 Precedent-diff | PASS — bulk-redirect item precedent lives in the same file; deviation (`dynamic "item"` vs 69 explicit `item {}` blocks) diffed in Dependencies & Risks |
| 4.45 verify-the-negative | PASS-with-fix — `include_subdomains` claim corrected (enumerated proxied records: app/deploy/ssh/registry/www/apex; no `preview` record) |
| 4.45 post-edit self-audit | PASS — residual-reference grep enumerated 10 files naming the deleted machinery; all covered (4 deletions, 6 edits including `seo-bulk-redirects.tf` comment) |
| 4.5 Network-outage | SKIP — no trigger patterns; `cloudflare_list` has no file/remote-exec provisioner or SSH connection block |
| 4.55 Downtime & Cutover | FIRED — `## Downtime & Cutover` section added; zero-downtime-by-construction |
| 4.6 User-Brand Impact | PASS — section present, threshold `aggregate pattern` |
| 4.7 Observability | PASS — 5-field section; `discoverability_test.command` verb `curl` is allowlisted, no SSH |
| 4.8 PAT-shaped variable | PASS — zero regex hits |
| 4.9 UI-Wireframe | FIRES on glob (`**/*.njk`) → resolved per Excluded clause: two `.njk` files are DELETED machine-facing stub generators (not user surfaces), the third touch is a comment-only `sitemap.njk` edit — "pure copy … no structural/layout change". Same resolution shape as `2026-08-11-fix-plugin-delivery-path-plan.md`'s recorded determination. Not a general `.njk` licence — `ux-design-lead` consult is the remedy if challenged. |
| 4.10 Encryption Posture | FIRED on `.tf` → section rewritten in schema YAML (was prose — would have failed field checks) |
| 4.11 Guard Contract | PASS — `python3 scripts/lint-guard-contract.py` green (2 guard entries, matrix ≥3 rows each) |

## Overview

Google Search Console's "Why pages aren't indexed" report for `sc-domain:soleur.ai`
(76 URLs, all live-verified 2026-09-18 — see
`knowledge-base/project/specs/feat-one-shot-3328-gsc-indexing-cleanup/gsc-evidence.md`)
distills to three actionable items:

1. **#3328 (open):** 23 blog date-slug URLs (`/blog/YYYY-MM-DD-<slug>/` and
   `/index.html` shape) are served HTTP-200 meta-refresh stubs generated at
   Eleventy build time from `plugins/soleur/docs/_data/blogRedirects.js`.
   Meta-refresh + canonical is a non-deterministic indexing signal (one flagged
   URL sits in the "Excluded by noindex" bucket on a `?utm_` variant). Migrate
   the 23 pairs to Cloudflare Bulk Redirects — the account-level product already
   proven in `apps/web-platform/infra/seo-bulk-redirects.tf` — then delete the
   meta-refresh machinery and repurpose its CI guards.
2. **Internal-link equity** for 5 canonical pages Google crawled but declined
   to index (`/blog/soleur-vs-polsia/`, `/blog/why-most-agentic-tools-plateau/`,
   `/blog/ai-agents-for-solo-founders/`, `/legal/gdpr-policy/`,
   `/legal/data-protection-disclosure/`), per the documented remediation
   pattern in `knowledge-base/project/learnings/2026-06-15-gsc-crawled-not-indexed-remediation-is-internal-linking.md`.
3. **`api.soleur.ai` X-Robots-Tag** — resolved to **no work**: the transform
   rule already exists in `cloudflare_ruleset.seo_response_headers` and is a
   documented no-op while `api.soleur.ai` is a DNS-only CNAME; the
   re-evaluation was closed under #3379. See Research Reconciliation.

Spec lacks valid `lane:` — defaulted to cross-domain (TR2 fail-closed). No
`spec.md` exists for this branch; `gsc-evidence.md` is the planning input.

## Problem Statement

Blog posts renamed from date-prefixed filenames to canonical slugs depend on
Eleventy-generated stub pages (`docs/blog/redirects.njk` fed by
`_data/blogRedirects.js`) to forward `/blog/2026-03-24-vibe-coding-vs-agentic-engineering/`
→ `/blog/vibe-coding-vs-agentic-engineering/`. The stubs serve `HTTP 200` with
`<meta http-equiv="refresh" content="0;url=…">` + `<meta name="robots"
content="noindex">`, a signal Google classifies non-deterministically (learning
`2026-05-05-gsc-indexing-triage-patterns.md`, Insight 2). The page-level
equivalents (`/pages/*.html`) were migrated to deterministic edge 301s under
#3296/#5082; #3328 is the deferred deletion/migration follow-up whose
pre-conditions are now met (edge 301s live since ~June, verified in evidence).

Separately, 5 healthy canonical pages sit in "Crawled – currently not indexed" —
Google's discretionary "not important enough yet" call. The in-repo lever is
contextual internal links; the homepage and nav currently pass zero links to
blog/cluster surfaces (measured: `index.njk` contains zero `blog/` hrefs).

## Proposed Solution

Two merges, matching the established verify-then-delete pattern
(#3296 shipped edge rules first; #3328 is the deletion follow-up):

- **PR-A (Phase 1 — infra, additive-only):** extend
  `cloudflare_list.legal_redirects` in
  `apps/web-platform/infra/seo-bulk-redirects.tf` with a
  `local.blog_redirect_pairs` map (23 date-slug → canonical-slug entries) and a
  `dynamic "item"` block emitting 69 redirect items (all three URL shapes per slug).
  No new Terraform resources, no new ruleset rules, no workflow edits — the
  list is already in the apply workflow's `-target` allow-list and the account
  ruleset already binds it. Merge fires `apply-web-platform-infra.yml`, then a
  curl suite verifies all 69 source URLs return `301` to the correct canonical.
- **PR-B (Phase 2 — deletion + guards + links):** after the Phase-1 apply is
  verified live, delete the four meta-refresh files, repurpose the affected CI
  guards (they currently *assert stub existence* and will go red on deletion),
  remove the now-dead validate-seo skip block, and land the internal-link
  edits (`_data/pillars.js` series, `site.json` footerLegal, `pillar:`
  frontmatter, bounded in-prose links). Re-verify all 19 `pageRedirects`
  `from` paths against the live edge before deleting per
  `hr-bulk-delete-per-item-live-infra-role-check`.

Single-PR delivery was rejected: a merge races `deploy-docs.yml` (stub
deletion) against `apply-web-platform-infra.yml` (edge 301 creation); a docs
deploy landing first — or a failed apply — leaves 69 URL shapes serving 404
with no stub and no edge rule. Additive-first sequencing means a failed apply
costs nothing (stubs still serve) and satisfies verify-then-delete literally.

## Technical Approach

### Architecture

Redirect serving today (the layer being deleted):

```text
plugins/soleur/docs/blog/*.md filenames ──► _data/blogRedirects.js (build-time
  date-prefix regex) ──► blog/redirects.njk pagination ──►
  _site/blog/<date-slug>/index.html (HTTP 200 meta-refresh stub, noindex)
```

Redirect serving after (edge, consistent with the existing legal/blog-reslug
items in the same list):

```text
local.blog_redirect_pairs (static map in seo-bulk-redirects.tf)
  ──► dynamic "item" × 3 URL shapes ──► cloudflare_list.legal_redirects
  ──► cloudflare_ruleset.bulk_redirects (account, http_request_redirect,
      rule 1 already binds $legal_redirects) ──► edge 301
```

Design constraints honored:

- **Zone `http_request_dynamic_redirect` quota is FULL (10/10)** — confirmed in
  `seo-rulesets.tf` (8 page redirects + terms rename + load-bearing HTTPS
  catch-all). Bulk Redirects (`http_request_redirect`, account-level) is a
  separate Free-tier product — 10,000 URL quota measured in
  `learnings/2026-06-09-cloudflare-bulk-redirects-v4-schema-and-phase-order.md`.
- **Provider is `cloudflare/cloudflare` 4.52.7 (`~> 4.0`)** — v4 BLOCK syntax
  (`item { value { redirect { … } } }`); string enums (`"enabled"`/`"disabled"`),
  never booleans. `terraform validate` is the drift catch.
- **`www-apex-canonicalizer.test.sh` asserts `bulk_redirects` binds exactly two
  rules** ("a third is an unreviewed redirect surface") and their order
  (`legal_redirects` first, `www_canonical` second). A new `blog_redirects`
  list + third rule would violate that committed guard; extending the existing
  list does not touch it. This decides the list question.
- **Item semantics mirror the legal entries:** `status_code = 301`,
  `include_subdomains = "enabled"` (www date-slug variants collapse to apex
  canonical in one hop; the every-proxied-subdomain caveat applies — zone
  proxied records are `app`, `deploy`, `ssh`, `registry`, `www`, apex; no
  `preview` record exists. None serves `/blog/*` content, so a stray
  `app.soleur.ai/blog/<date-slug>/` request that 404s today would instead 301
  to the apex canonical — a strict improvement, consistent with the accepted
  caveat on the 13 existing items),
  `preserve_query_string = "enabled"` (the flagged GSC URL was a `?utm_`
  variant; dropping params loses attribution). All three URL shapes
  (`<slug>/`, `<slug>/index.html`, and the bare no-slash `<slug>`) are
  separate exact-match keys, per the `what-is-company-as-a-service` precedent
  in the same file. The bare shape matters: Bulk Redirects match
  `http.request.full_uri` exactly, so without it a bare URL relies on the
  origin's trailing-slash redirect today and would 404 after PR-B deletes the
  meta-refresh stubs.
- **Single Redirects evaluate before Bulk Redirects** — the zone ruleset is
  disjoint (no `/blog/YYYY-MM-DD-*` rules), so no interaction.

The 23 pairs (derived from `plugins/soleur/docs/blog/*.md` filenames —
`YYYY-MM-DD-` prefix stripped is the canonical slug, matching
`DATE_PREFIX_RE` in `blogRedirects.js`):

| Date slug | Canonical slug |
|---|---|
| 2026-03-16-soleur-vs-anthropic-cowork | soleur-vs-anthropic-cowork |
| 2026-03-17-soleur-vs-notion-custom-agents | soleur-vs-notion-custom-agents |
| 2026-03-19-soleur-vs-cursor | soleur-vs-cursor |
| 2026-03-24-ai-agents-for-solo-founders | ai-agents-for-solo-founders |
| 2026-03-24-vibe-coding-vs-agentic-engineering | vibe-coding-vs-agentic-engineering |
| 2026-03-26-soleur-vs-polsia | soleur-vs-polsia |
| 2026-03-29-credential-helper-isolation-sandboxed-environments | credential-helper-isolation-sandboxed-environments |
| 2026-03-29-your-ai-team-works-from-your-actual-codebase | your-ai-team-works-from-your-actual-codebase |
| 2026-03-31-soleur-vs-paperclip | soleur-vs-paperclip |
| 2026-04-21-one-person-billion-dollar-company | one-person-billion-dollar-company |
| 2026-04-21-soleur-vs-devin | soleur-vs-devin |
| 2026-04-22-billion-dollar-solo-founder-stack | billion-dollar-solo-founder-stack |
| 2026-04-23-agents-that-use-apis-not-browsers | agents-that-use-apis-not-browsers |
| 2026-04-23-knowledge-compounding-in-ai-development | knowledge-compounding-in-ai-development |
| 2026-04-30-best-claude-code-plugins-2026 | best-claude-code-plugins-2026 |
| 2026-05-05-soleur-vs-tanka | soleur-vs-tanka |
| 2026-05-07-soleur-vs-crewai | soleur-vs-crewai |
| 2026-05-12-company-as-a-service-platform | company-as-a-service-platform |
| 2026-05-14-how-to-run-every-department-with-ai-agents | how-to-run-every-department-with-ai-agents |
| 2026-05-15-skill-libraries-vs-workflow-plugins | skill-libraries-vs-workflow-plugins |
| 2026-06-01-claude-code-plugin-vs-skill-vs-mcp | claude-code-plugin-vs-skill-vs-mcp |
| 2026-06-12-loop-engineering-for-your-whole-company | loop-engineering-for-your-whole-company |
| 2026-06-15-best-ai-tools-for-solo-founders-2026 | best-ai-tools-for-solo-founders-2026 |

### Implementation Phases

#### Phase 1 — Edge 301s (PR-A: `apps/web-platform/infra/seo-bulk-redirects.tf` only)

- Add at file scope (before `resource "cloudflare_list" "legal_redirects"`):

  ```hcl
  locals {
    # Migrated from plugins/soleur/docs/_data/blogRedirects.js (deleted in PR-B).
    # Static map, not fileset() derivation — see plan Alternatives.
    blog_redirect_pairs = {
      "2026-03-16-soleur-vs-anthropic-cowork" = "soleur-vs-anthropic-cowork"
      # … all 23 pairs from the table above …
    }
    blog_redirect_items = flatten([
      for date_slug, canonical in local.blog_redirect_pairs : [
        { source = "soleur.ai/blog/${date_slug}/",           target = "https://soleur.ai/blog/${canonical}/" },
        { source = "soleur.ai/blog/${date_slug}/index.html", target = "https://soleur.ai/blog/${canonical}/" },
        { source = "soleur.ai/blog/${date_slug}",            target = "https://soleur.ai/blog/${canonical}/" },
      ]
    ])
  }
  ```

- Inside `cloudflare_list.legal_redirects`, append after the explicit items:

  ```hcl
  dynamic "item" {
    for_each = local.blog_redirect_items
    content {
      value {
        redirect {
          source_url            = item.value.source
          target_url            = item.value.target
          status_code           = 301
          include_subdomains    = "enabled"
          preserve_query_string = "enabled"
        }
      }
    }
  }
  ```

- Update the list `description` and the header comment to reflect
  "legal + blog reslug + blog date-slugs" (the `legal_redirects` name stays —
  renaming ripples through the ruleset `expression`, the workflow `-target`
  allow-list, and the live CF object for zero behavioral gain; precedent
  documented in the file).
- Validate: `terraform validate` in `apps/web-platform/infra/`; run
  `bash apps/web-platform/infra/www-apex-canonicalizer.test.sh` and
  `bash apps/web-platform/infra/www-apex-canonicalizer-mutation.test.sh` —
  both must stay green (2 rules, bind order unchanged).
- Merge → `apply-web-platform-infra.yml` auto-applies (the merge is the
  authorization; `[skip-web-platform-apply]` must NOT be in the message).
- Post-merge verification (all as `curl -sI -A Googlebot`): every one of the
  69 source URLs returns `301` with `location:` equal to the mapped canonical;
  spot-check `https://www.soleur.ai/blog/2026-03-24-vibe-coding-vs-agentic-engineering/`
  is a **single** hop to the apex canonical (include_subdomains), and
  `https://soleur.ai/blog/vibe-coding-vs-agentic-engineering/` returns `200`.

#### Phase 2 — Deletion + guard repurposing + internal links (PR-B)

Precondition: Phase-1 apply verified live (69/69). Before deleting
`pageRedirects.js`, re-curl all 19 `from` paths (8 zone `pages/*.html` + 10
`pages/legal/*.html` bulk items — `terms-of-service.html` included — + 1 blog
reslug = 19; the evidence file verified them once; this is the
`hr-bulk-delete-per-item-live-infra-role-check` per-item re-verification at
implementation time).

- Delete: `plugins/soleur/docs/page-redirects.njk`,
  `plugins/soleur/docs/_data/pageRedirects.js`,
  `plugins/soleur/docs/blog/redirects.njk`,
  `plugins/soleur/docs/_data/blogRedirects.js`.
- `scripts/validate-blog-links.sh` (actual path — the evidence file cites a
  stale `plugins/soleur/docs/scripts/` location): replace the
  "Redirect page validation" block (the `for md_file in
  "$BLOG_DIR"/[0-9][0-9][0-9][0-9]-…` loop asserting stub existence) with the
  bidirectional parity guard in Guard Contract §Guard 1.
- `plugins/soleur/skills/seo-aeo/scripts/validate-seo.sh`: delete the
  "Skip instant meta-refresh redirects" block — a future stub must now fail
  full SEO validation (missing canonical) instead of being silently skipped.
- `plugins/soleur/test/validate-seo.test.ts`: rewrite
  `test("passes when an instant redirect page is present (meta refresh
  content=0)")` → assert `exitCode === 1` and the canonical failure line (the
  fixture stub has no `<link rel="canonical">`).
- `plugins/soleur/test/seo-aeo-drift-guard.test.ts`:
  - `test("legacy terms-of-service redirect stub resolves to
    terms-and-conditions")` → repoint at `seo-bulk-redirects.tf` source: assert
    the file contains `source_url = "soleur.ai/pages/legal/terms-of-service.html"`
    and `target_url = "https://soleur.ai/legal/terms-and-conditions/"`.
  - `describe("GSC interim — every meta-refresh redirect stub is noindex")` →
    replace with the Guard 2 zero-stub fence + a tf-source assertion that the
    9 legal `source_url`s still exist in `seo-bulk-redirects.tf` (preserves the
    parity property against the new canonical source).
  - `isMetaRefreshStub` predicate stays — it is the shared skip-predicate for
    unrelated guards, not an existence assertion.
- `plugins/soleur/docs/sitemap.njk`: update the stale comment referencing
  `page-redirects.njk` (no code change — stubs were never in the sitemap).
- `plugins/soleur/skills/seo-aeo/SKILL.md`: the bare-relative-href sweep list
  mentions `page-redirects.njk`; update the reference.
- `apps/web-platform/infra/seo-bulk-redirects.tf`: the header comment
  references `page-redirects.njk` as the fallback this list replaced; update
  wording post-deletion (comment-only edit → empty apply, harmless).
- Internal links:
  - `plugins/soleur/docs/_data/pillars.js`: add two series using the existing
    member shape `{ url: "/blog/<slug>/", relation: "pillar" | "cluster" }`
    (titles resolve via `collections.blog` in `pillar-series.njk`):
    - `soleur-comparisons` — `soleur-vs-devin` as `pillar` (highest-intent
      comparison), the other 7 vs-posts as `cluster` members;
      `soleur-vs-polsia` gains 7 inbound aside links.
    - `agentic-solo-founder` — `ai-agents-for-solo-founders` as `pillar`,
      cluster members `why-most-agentic-tools-plateau`,
      `knowledge-compounding-in-ai-development`,
      `your-ai-team-works-from-your-actual-codebase`,
      `best-ai-tools-for-solo-founders-2026`,
      `loop-engineering-for-your-whole-company`; both unindexed targets gain
      5 inbound each.
  - Add `pillar: <series-key>` to the 14 member posts' frontmatter
    (`2026-03-16/17/19/26/31-soleur-vs-*.md`, `2026-04-21-soleur-vs-devin.md`,
    `2026-05-05-soleur-vs-tanka.md`, `2026-05-07-soleur-vs-crewai.md` for the
    comparisons series; `2026-03-24-ai-agents-for-solo-founders.md`,
    `why-most-agentic-tools-plateau.md`,
    `2026-04-23-knowledge-compounding-in-ai-development.md`,
    `2026-03-29-your-ai-team-works-from-your-actual-codebase.md`,
    `2026-06-15-best-ai-tools-for-solo-founders-2026.md`,
    `2026-06-12-loop-engineering-for-your-whole-company.md` for the cluster).
    `billion-dollar-solo-founder-stack` and
    `one-person-billion-dollar-company` are already in the existing series —
    `pillar:` is a single key, do not reassign.
  - `plugins/soleur/docs/_data/site.json`: append
    `{ "label": "GDPR Policy", "url": "/legal/gdpr-policy/" }` and
    `{ "label": "Data Protection", "url": "/legal/data-protection-disclosure/" }`
    to `footerLegal` — site-wide footer links on every page (currently only
    `/legal/`, privacy, terms, AUP are footer-linked).
  - Bounded judgment: up to 2 additional genuinely-contextual in-prose links
    per target post where a natural anchor already exists in a topically
    adjacent high-traffic post — never a keyword-stuffed block (learning
    Insight 2). The series/footer edits above are the deterministic part; this
    is optional.
- Build + verify: `npx @11ty/eleventy` →
  `grep -rl 'http-equiv="refresh"' _site` returns nothing; rendered asides
  contain the target URLs; footer renders the two new legal links; run the
  host-mangle corpus grep `grep -rEoh 'https://soleur\.ai[a-zA-Z]' _site/blog/`
  and fix any surfaced broken links in scope (learning Insight 3);
  `bun test plugins/soleur/test/validate-seo.test.ts
  plugins/soleur/test/seo-aeo-drift-guard.test.ts` and
  `bash scripts/validate-blog-links.sh _site` green.

#### Phase 3 — Post-merge

- `deploy-docs.yml` publishes the stub-free site; edge 301s already serve the
  date-slugs (Phase 1). Re-run the 69-URL curl spot-check live.
- File a GSC re-verification follow-up issue (deferral tracking): re-pull the
  "Why pages aren't indexed" report ~2–4 weeks post-merge to confirm the
  noindex-bucket entry and crawled-not-indexed rows drain. Index state is
  Google-controlled and lags — observational, not an AC. Filed as **#8332**
  during planning (deferral-tracking gate).

## Files to Create

None — all changes are edits or deletions of existing files.

## Files to Edit

**PR-A:** `apps/web-platform/infra/seo-bulk-redirects.tf`

**PR-B:**
- `scripts/validate-blog-links.sh` — parity guard replaces stub-existence block
- `plugins/soleur/skills/seo-aeo/scripts/validate-seo.sh` — remove skip block
- `plugins/soleur/test/validate-seo.test.ts` — flip instant-redirect test
- `plugins/soleur/test/seo-aeo-drift-guard.test.ts` — zero-stub fence + tf-source assertions
- `plugins/soleur/docs/sitemap.njk` — stale comment update
- `plugins/soleur/skills/seo-aeo/SKILL.md` — stale `page-redirects.njk` reference
- `plugins/soleur/docs/_data/site.json` — +2 `footerLegal` entries
- `plugins/soleur/docs/_data/pillars.js` — +2 series
- `apps/web-platform/infra/seo-bulk-redirects.tf` — header comment references the now-deleted `page-redirects.njk`; update wording (comment-only edit → empty apply, harmless)
- 14 blog post frontmatter `pillar:` additions (8 vs-posts + 6 cluster posts, listed in Phase 2)
- Up to 2 existing blog posts per target for bounded in-prose links (optional, judgment)

**Pipeline artifacts (not implementation):** this plan file,
`knowledge-base/project/specs/feat-one-shot-3328-gsc-indexing-cleanup/tasks.md`,
`session-state.md`, `knowledge-base/INDEX.md` (regenerated by hook).

## Files to Delete

- `plugins/soleur/docs/page-redirects.njk`
- `plugins/soleur/docs/_data/pageRedirects.js`
- `plugins/soleur/docs/blog/redirects.njk`
- `plugins/soleur/docs/_data/blogRedirects.js`

## Alternative Approaches Considered

| Approach | Verdict | Why |
|---|---|---|
| Build-time JSON export (`blog-redirects.json` + `jsondecode` + `dynamic`) | Rejected | #3328 calls it "more maintainable," but it adds a generator script, a committed artifact, and a CI freshness guard to ferry data Terraform can hold directly — and creates a drift window between the docs build and the infra apply pipelines. Most machinery for the same property. |
| `fileset()` derivation in HCL (`${path.module}/../../../plugins/soleur/docs/blog`) | Rejected | Auto-syncs (identical semantics to the deleted code) but makes an infra plan depend on docs content: a docs-side rename silently changes the *next* unrelated apply, and it makes the parity guard tautological (guard and source share one derivation). Infra diffs should be explicit and reviewable. |
| **Static `local.blog_redirect_pairs` map + `dynamic "item"`** | **Chosen** | Explicit, reviewable 23-line map; the bidirectional parity guard in `validate-blog-links.sh` preserves the "every date-prefixed file has a redirect" property the build-time code gave for free — enforced at CI time instead of build time. |
| 69 explicit `item {}` blocks | Rejected | Matches file style but ~690 near-identical lines vs ~40 with a map+dynamic; same compiled result. |
| New `cloudflare_list.blog_redirects` + third ruleset rule | Rejected | `www-apex-canonicalizer.test.sh` asserts `bulk_redirects` binds **exactly two** rules ("a third is an unreviewed redirect surface"); a new list also needs a `-target` allow-list edit in `apply-web-platform-infra.yml` and re-opens the cross-list precedence question the `www_canonical` comment flags as undocumented. More machinery, same property, trips a committed guard. |
| Single PR (infra + deletions together) | Rejected | Merge-time race between `deploy-docs.yml` (stub removal) and `apply-web-platform-infra.yml` (edge 301 creation); a docs deploy landing first — or a failed apply — 404s 69 URL shapes. Violates verify-then-delete (`hr-bulk-delete-per-item-live-infra-role-check`) for the 23 new redirects. |
| New X-Robots-Tag transform rule for `api.soleur.ai` | Rejected | Rule already exists (`seo-rulesets.tf` `seo_response_headers`, api rule); verified no-op because the host is a DNS-only CNAME — the blocker is DNS topology owned by #3379, not a missing rule. |

## Research Reconciliation — Spec vs. Codebase

| Evidence/issue claim | Codebase reality | Plan response |
|---|---|---|
| `plugins/soleur/docs/scripts/validate-blog-links.sh` | Actual path is `scripts/validate-blog-links.sh` (repo root) | Corrected path used throughout |
| api.soleur.ai "candidate for X-Robots-Tag (Terraform transform rule if one exists)" | Rule exists at `seo-rulesets.tf` `seo_response_headers`; documented no-op (DNS-only CNAME → Supabase); #3379 owns re-evaluation | Out of scope; no new work |
| #3328: "JSON export is more maintainable" | Two viable derivations exist; static map + parity guard is the smallest mechanism that keeps the coverage property | Static map chosen (Alternatives) |
| "23 date-prefixed blog slugs" | Confirmed: `ls plugins/soleur/docs/blog/ \| grep -cE '^[0-9]{4}-'` = 23 | Enumerated in the pairs table |
| "all 19 pageRedirects entries covered by live edge 301s" | Structurally confirmed: 8 zone rules + 9 bulk legal + ToS (zone+bulk) + blog reslug (bulk) | Re-verified per-item before deletion |
| Zone redirect quota full (10/10) | Confirmed in `seo-rulesets.tf` header | Bulk Redirects path used |
| `footerLegal` covers all legal pages | Only 4 of 9 legal pages footer-linked; gdpr + data-protection missing | +2 `site.json` entries |

## Research Insights

**Relevant files (verified on this branch):**
`apps/web-platform/infra/seo-bulk-redirects.tf` (the proven pattern; list +
account ruleset + ordering contract), `apps/web-platform/infra/seo-rulesets.tf`
(zone quota 10/10; api.soleur.ai noindex rule already present but dormant),
`.github/workflows/apply-web-platform-infra.yml` (`-target` allow-list already
contains `cloudflare_list.legal_redirects`,
`cloudflare_list.www_canonical`, `cloudflare_ruleset.bulk_redirects`),
`.github/workflows/deploy-docs.yml` (wrangler deploy of `_site` to Cloudflare
Pages — the deletion side's deploy path), `scripts/validate-blog-links.sh`
(redirect-validation block), `plugins/soleur/test/seo-aeo-drift-guard.test.ts`
(`isMetaRefreshStub`, sitemap guard, ToS stub test, noindex-stub describe),
`plugins/soleur/test/validate-seo.test.ts` (skip-behavior tests),
`apps/web-platform/infra/www-apex-canonicalizer.test.sh` (exactly-2-rules
guard), `plugins/soleur/docs/_data/pillars.js` + `_includes/pillar-series.njk`
+ `blog-post.njk` (existing internal-link machinery), `site.json`
(`footerLegal`), `plugins/soleur/docs/blog/blog.json`
(`permalink: blog/{{ page.fileSlug }}/index.html` — Eleventy strips the date
prefix from `fileSlug`, so canonical = post-date slug; confirmed by the live
stub targets in evidence).

**Premise Validation (Phase 0.6):** #3328 verified OPEN
(`feat(seo): migrate blog redirects + delete page-redirects meta-refresh
templates`, no closing PR). All cited files exist except the
`validate-blog-links.sh` path correction above. `api.soleur.ai` noindex is
already-built-but-dormant (#3379), not missing — stale premise corrected. ADR
corpus grep (redirect/bulk/cloudflare): no ADR prescribes meta-refresh; ADR-130
(token widen — done, #5092), ADR-194 (docs→CF Pages), ADR-204 (redirect
health→Better Stack) are compatible context. #8143/#8144 OPEN — same
internal-linking root-cause class on pillar pages; disjoint URL sets.

**Property List (Phase 0.6b):**
P1 — all 69 date-slug URL shapes return edge 301s to canonicals.
P2 — all 19 `pageRedirects` `from` paths keep resolving after deletion.
P3 — meta-refresh machinery deleted with zero residual consumers and green CI.
P4 — a new date-prefixed blog file cannot silently lack an edge redirect.
P5 — the 5 unindexed canonicals gain contextual internal links.
P6 — no meta-refresh stub can be reintroduced silently.

**Cut List (Phase 0.6b):**
new `blog_redirects` list + third rule → P1 already covered by extending
`legal_redirects` (also trips the exactly-2-rules guard) — cut.
JSON export pipeline → P1 covered by the static map at lower machinery — cut.
`fileset()` derivation → P1 covered; adds cross-tree plan dependency + makes
the P4 guard tautological — cut.
api.soleur.ai transform rule → property already built (dormant by DNS
topology, #3379) — cut.

**Learnings applied:** `2026-06-09-cloudflare-bulk-redirects-v4-schema-and-phase-order.md`
(v4 string enums; Single-before-Bulk order; `from_list` resource binding;
10k quota), `2026-05-05-gsc-indexing-triage-patterns.md` (meta-refresh
non-determinism), `2026-06-15-gsc-crawled-not-indexed-remediation-is-internal-linking.md`
(internal-link lever; host-mangle corpus grep; fix broken links in scope),
`2026-06-01-gsc-page-with-redirect-is-historical-memory-verify-against-build.md`
(buckets are memory, verify live), `2026-07-06-gsc-coverage-report-is-playwright-pullable-after-operator-signin.md`
(GSC re-pull path for the Phase-3 follow-up).

## User-Brand Impact

- **If this lands broken, the user experiences:** a search result or external
  link to `/blog/YYYY-MM-DD-<slug>/` or `/pages/<slug>.html` serving `404`
  instead of reaching the canonical post/page — dead links on the public
  marketing surface (SEO equity and visitor trust).
- **If this leaks, the user's [data / workflow / money] is exposed via:** no
  data exposure vector — the change touches public redirect config and docs
  content only. Worst case is availability/indexability degradation, not
  disclosure.
- **Brand-survival threshold:** `aggregate pattern` — a broken redirect set is
  a public-facing degradation affecting many anonymous visitors, not a
  single-user breach. No CPO sign-off required at this threshold.

## Observability

```yaml
liveness_signal:
  what:            scheduled-terraform-drift.yml reconciles declared vs live infra (catches a list item that fails to apply or drifts); post-merge curl suite verifies all 69 source URLs return 301; betteruptime_monitor.soleur_www_redirect (existing) covers the www-redirect class
  cadence:         drift workflow on schedule; curl suite once post-merge per phase
  alert_target:    drift detector files an infra-drift labeled issue; apply failure = red workflow run on main
  configured_in:   .github/workflows/scheduled-terraform-drift.yml; .github/workflows/apply-web-platform-infra.yml; apps/web-platform/infra/uptime-alerts.tf (betteruptime_monitor.soleur_www_redirect)

error_reporting:
  destination:     GitHub Actions run status on main (apply-web-platform-infra.yml, deploy-docs.yml); drift issues labeled infra-drift
  fail_loud:       apply job red on main; any of the 69 curls returning non-301 or wrong location

failure_modes:
  - mode:          Phase-1 apply fails (token/quota/schema)
    detection:     red apply-web-platform-infra.yml run on main
    alert_route:   Actions failure on the merge; date-slugs still serve stubs (additive-only = zero blast radius)
  - mode:          list item applied with wrong target
    detection:     post-merge curl loop compares location header to the pairs table
    alert_route:   fix-forward infra PR (list edit re-applies on merge)
  - mode:          stub deleted while edge rule absent
    detection:     prevented by construction — PR-B precondition requires 69/69 verified 301s
    alert_route:   n/a (ordering gate)
logs:
  where:           GitHub Actions logs (apply + deploy runs); terraform plan output in the apply run shows the +69 item diff
  retention:       Actions retention (90 days default)

discoverability_test:
  command:         curl -sI -A Googlebot https://soleur.ai/pages/legal/privacy-policy.html
  expected_output: HTTP/2 301 with location: https://soleur.ai/legal/privacy-policy/ (proves the account bulk-redirect phase is live; a blog date-slug URL is the Phase-1 equivalent once applied)
```

## Encryption Posture

Triggered by the `.tf` file in Files to Edit. The change introduces no
persistent store; `cloudflare_list` items are configuration rows on an existing
account-level Cloudflare resource. No new cross-component connection is
created — redirect serving rides the existing proxied edge.

```yaml
at_rest:
  - store: none introduced by this change
    mechanism: not-applicable — no persistent store is created. The added
               list items are vendor-side configuration rows inside the
               existing cloudflare_list.legal_redirects object, not a new
               store class (no volume, bucket, table, queue, cache, or log
               sink is declared).
    evidence: Files to Edit declares one .tf file; the diff adds a locals
              block and a dynamic item stanza inside an existing list
              resource — no new resource blocks of any kind.
    defends_against: not-applicable — no data at rest is created, so there is
                     no at-rest threat surface to defend.
    does_not_defend: does not alter the posture of the existing list object
                     or any other store — list contents (public URL pairs)
                     persist under Cloudflare's own controls outside this
                     repo's boundary, unchanged by this plan.
    disclosed_as: no disclosure change — the rows contain only public URL
                  strings; no new data category.
    live_verification: `terraform plan` post-change shows `+69` item additions
                       inside cloudflare_list.legal_redirects and zero new
                       resources (`Plan: 0 to add, 1 to change, 0 to destroy`
                       shape at the list level).

in_transit:
  - connection: visitor/crawler -> Cloudflare edge -> 301 response (existing
                proxied serving; this plan adds rules to an existing phase,
                not a new connection)
    tls: yes — the request and 301 legs are served over the existing CF edge
         TLS termination for soleur.ai and its proxied subdomains; the
         load-bearing HTTPS-upgrade catch-all (seo-rulesets.tf Rule 10) is
         unchanged.
    cert_verification: on — nothing in this change disables verification; the
                       verification commands are plain `curl -sI` with no -k
                       or --insecure flags.
    does_not_defend: request path and any query string remain visible to the
                     Cloudflare edge (they already were); preserve_query_string
                     deliberately forwards ?utm_* params to the canonical URL,
                     so the params travel in the 301 Location header — by
                     design, for attribution.
    disclosed_as: existing CF edge disclosure, unchanged — same vendor, same
                  terminated-TLS surface, no new data category.

exception: none — no plaintext store and no disabled certificate
           verification, so no tracking_issue / expires_on block is required.
```

## Infrastructure (IaC)

### Terraform changes

- `apps/web-platform/infra/seo-bulk-redirects.tf` — extend
  `cloudflare_list.legal_redirects` (+69 items via `local.blog_redirect_pairs`
  map + `dynamic "item"`); comment/description updates. No new resources.
- Providers: existing `cloudflare.rulesets` alias (`cloudflare/cloudflare`
  4.52.7 `~> 4.0`), account-scoped (`var.cf_account_id`). No new variables —
  no `TF_VAR_*` provisioning needed (the
  no-default-variable/Doppler sequencing hazard does not apply).

### Apply path

Merge-triggered `apply-web-platform-infra.yml` — the `-target` allow-list
already contains `cloudflare_list.legal_redirects` and
`cloudflare_ruleset.bulk_redirects`; no workflow edit. Blast radius:
additive-only list items — a failed or partial apply cannot degrade any URL
that resolves today (stubs remain live until PR-B).

### Distinctness / drift safeguards

Single environment (prod zone/account only — no dev twin for the CF edge, by
existing design). `scheduled-terraform-drift.yml` reconciles declared vs live.
The pre-apply entrypoint gate (ADR-136) protects whole-list ruleset phases —
this change adds list *items* inside an existing list, not a new
`kind=root`/`kind=zone` entrypoint, so it does not alter that surface.

### Vendor-tier reality check

Cloudflare Free tier: zone `http_request_dynamic_redirect` is FULL (10/10) —
bypassed by design. Bulk Redirects quota is 10,000 URLs across lists
(measured 2026-06-09); +69 on the existing list is trivially within quota.
`regex_replace()` consolidation remains Business-tier — not used.

## Downtime & Cutover

**Trigger assessment:** redirect-layer change on a live public surface —
treated as router-class for scrutiny, though no serving resource is rebooted,
replaced, or drained.

**Offline-inducing operation:** none in isolation. The only window where a URL
could fail is a *mis-sequenced* cutover (origin stubs deleted before edge 301s
exist) — which is exactly what the two-merge structure eliminates:

- **Phase 1 (additive):** `cloudflare_list` item additions apply in place on an
  existing account ruleset — Cloudflare evaluates the updated list atomically;
  no in-flight request is dropped and no stub is touched. Failure mode: apply
  errors → zero blast radius, stubs still serve.
- **Cutover proof:** the 69/69 curl suite IS the per-stage verification — edge
  301s must be observed live before PR-B may merge (hard precondition, not a
  checklist nicety).
- **Phase 2 (removal):** `deploy-docs.yml` publishes `_site` to Cloudflare
  Pages via `wrangler pages deploy` — Pages deploys are atomic
  (new-deployment cutover, no drain needed). At that moment every deleted-stub
  path is already served at the edge; the origin is never consulted for those
  paths.
- **Rollback:** a bad list item → fix-forward list edit re-applies on merge
  (seconds); a bad deletion → revert PR-B restores stubs (edge 301s continue
  serving regardless — revert is belt, not load-bearing).

No residual downtime is accepted; no maintenance window or operator sign-off
is needed.

## Guard Contract

### Guard 1 — blog date-slug ↔ bulk-redirect parity (repurposed `scripts/validate-blog-links.sh` redirect block)

**Property.** Every date-prefixed file under `plugins/soleur/docs/blog/` has a
matching `soleur.ai/blog/<date-slug>/` entry in `local.blog_redirect_pairs`
in `seo-bulk-redirects.tf`, and every date-slug key in that map corresponds to
a live date-prefixed file — the coverage property `blogRedirects.js` provided
at build time, enforced at CI time.

**Assembly.** One chokepoint per side: the file glob
`plugins/soleur/docs/blog/[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]-*.md`
(same pattern class as `DATE_PREFIX_RE`) and the `blog_redirect_pairs` map
keys in `apps/web-platform/infra/seo-bulk-redirects.tf`. The guard extracts
both sets and diffs them — it is NOT a literal-name list, so membership is
discovered, not pinned. Includes an anti-vacuity floor: the file side must
contain ≥1 member or the guard fails (a glob that silently matches nothing
must not read as "all covered").

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Add `plugins/soleur/docs/blog/2026-10-01-new-post.md` without a map entry | RED |
| 2 | Delete the guard's parity-diff loop (dispatch removed → 0 members checked) | RED via anti-vacuity floor |
| 3 | With one covered member, add a second date-prefixed file covering only the first | RED |
| 4 | Remove a `blog_redirect_pairs` key while the file still exists | RED |
| 5 | Harness: rename `2026-03-16-soleur-vs-anthropic-cowork.md` → `soleur-vs-anthropic-cowork.md` (file side loses a member; map keeps stale key) | RED — stale map key flagged, keeping the redirect honest is the correct fix (target still resolves) |

**Anchor.** The guard compares the live file tree against the committed map —
no stored hash; a weakening requires editing both sides in one commit, which
is exactly the reviewable diff the design intends.

### Guard 2 — meta-refresh reintroduction fence (`seo-aeo-drift-guard.test.ts` + `validate-seo.sh`)

**Property.** The built site contains zero meta-refresh redirect stubs, and no
page can serve one while evading SEO validation.

**Assembly.** Every `.html` emitted into `_site/` (the walk chokepoint in
`seo-aeo-drift-guard.test.ts`) — a reintroduced stub is any new template
emitting `<meta http-equiv="refresh">` — plus the `validate-seo.sh` page loop
which, with the skip block removed, applies full SEO checks to any such page.
Two chokepoints exist by design (built-output walk + validator), and the guard
states both.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Re-add `docs/blog/redirects.njk` emitting a stub page | RED — zero-stub fence (`toBe(0)`) |
| 2 | Restore the `content="0"` skip block in `validate-seo.sh` | RED — flipped `validate-seo.test.ts` test requires a stub page to FAIL |
| 3 | Emit `http-equiv="refresh"` inside a >2 kB page (bypasses `isMetaRefreshStub`'s size gate) | RED — full SEO validation fails on missing canonical |
| 4 | Harness: ordinary canonical page with canonical link + robots meta | MUST-PASS — fence must not reject all HTML |

**Anchor.** Predicate-based fence over the built tree — no stored value; the
build output itself is the anchor.

## Domain Review

**Domains relevant:** Marketing, Engineering

### Marketing

**Status:** reviewed (inline — Task fan-out unavailable in this harness)
**Assessment:** This is a pure SEO-surface change: deterministic 301s replace a
non-deterministic indexing signal (fixes a GSC noindex-bucket entry), and
internal-link equity targets Google's "crawled, not indexed" judgment on 5
canonical pages. Messaging/copy is untouched; the pillar-series aside and
footer links are existing components. No new public-facing claims. Relevant to
#8143/#8144 (same root-cause class, disjoint surfaces — noted as context, not
absorbed).

### Engineering

**Status:** reviewed (inline — Task fan-out unavailable in this harness)
**Assessment:** Extends a proven account-level Cloudflare pattern; avoids the
full zone quota by design. Load-bearing constraints verified in-repo: v4 block
syntax, `from_list` binding already present, exactly-2-rules guard in
`www-apex-canonicalizer.test.sh`, `-target` allow-list already covers the
list. Main risk class is sequencing (verify-then-delete), addressed by the
two-merge structure. No new substrate, credential, or trust boundary.

### Product/UX Gate

**Tier:** advisory (mechanical override fired — `**/*.njk` deletions and
pillar-series/footer changes touch the UI-surface glob; all changes modify
existing surfaces, none create pages/components/flows)
**Decision:** auto-accepted (pipeline)
**Agents invoked:** none
**Skipped specialists:** none required at advisory tier
**Pencil available:** N/A (no new UI surface)

#### Findings

The pillar-series aside already renders on every `pillar:`-frontmatter post
via `blog-post.njk`; series membership reuses that component. Footer links
extend an existing `footerLegal` list. Redirect stubs are machine-facing
artifacts no human sees rendered (instant refresh).

## Open Code-Review Overlap

None — 65 open `code-review` issues queried; zero bodies contain any planned
file path.

## Acceptance Criteria

**Phase 1 (PR-A):**

- [ ] `cloudflare_list.legal_redirects` contains 69 new redirect items derived
  from `local.blog_redirect_pairs` (23 date-slugs × `/<slug>/` +
  `/<slug>/index.html` + bare `/<slug>` shapes), each `status_code = 301`,
  `include_subdomains = "enabled"`, `preserve_query_string = "enabled"`,
  targeting `https://soleur.ai/blog/<canonical-slug>/`
- [ ] `cloudflare_ruleset.bulk_redirects` is unchanged — still exactly 2 rules
  in the same bind order; `bash apps/web-platform/infra/www-apex-canonicalizer.test.sh`
  and `…-mutation.test.sh` pass
- [ ] `terraform validate` passes in `apps/web-platform/infra/`
- [ ] No workflow edits — the merge-triggered apply covers the list via the
  existing `-target` allow-list
- [ ] Post-apply, all 69 source URLs return `301` to the mapped canonical via
  `curl -sI -A Googlebot` (loop over the pairs table), including a single-hop
  `www.` variant check

**Phase 2 (PR-B):**

- [ ] PR-B merges only after Phase-1 apply verification (69/69) is recorded
- [ ] All 19 `pageRedirects` `from` paths re-verified live `301` before
  `pageRedirects.js` deletion (per-item, curl output in PR evidence)
- [ ] `plugins/soleur/docs/page-redirects.njk`,
  `plugins/soleur/docs/_data/pageRedirects.js`,
  `plugins/soleur/docs/blog/redirects.njk`,
  `plugins/soleur/docs/_data/blogRedirects.js` deleted; residual-reference
  grep `grep -rn "pageRedirects\|blogRedirects\|page-redirects.njk\|blog/redirects.njk" plugins/ scripts/ .github/`
  returns only comments describing the deletion (or nothing)
- [ ] `scripts/validate-blog-links.sh` parity guard implements Guard 1
  (bidirectional + anti-vacuity floor) and passes on the real tree
- [ ] `validate-seo.sh` skip block removed; `validate-seo.test.ts` flipped test
  asserts the stub page FAILS (exit 1)
- [ ] `seo-aeo-drift-guard.test.ts` stub-existence tests replaced per Guard 2
  (zero-stub fence + tf-source assertions); `bun test` on both files green
- [ ] `_site` rebuild emits zero `http-equiv="refresh"` pages
- [ ] `site.json` `footerLegal` includes `/legal/gdpr-policy/` and
  `/legal/data-protection-disclosure/`; rendered footer verified in `_site`
- [ ] `_data/pillars.js` contains `soleur-comparisons` and
  `agentic-solo-founder` series; the 3 target posts are members; `pillar:`
  frontmatter present on all member posts; rendered asides in
  `_site/blog/<slug>/index.html` link sibling members
- [ ] Host-mangle corpus grep `grep -rEoh 'https://soleur\.ai[a-zA-Z]' _site/blog/`
  is clean (pre-existing broken links fixed in scope per learning Insight 3)
- [ ] PR body contains `Closes #3328` on its own line
- [ ] Diff scope limited to the listed files plus pipeline artifacts
  (`knowledge-base/project/plans/…`, `knowledge-base/project/specs/<branch>/{tasks.md,session-state.md}`,
  `knowledge-base/INDEX.md` if regenerated)

## Test Scenarios

- Given a new date-prefixed file `2026-10-01-x.md` with no map entry, when
  `bash scripts/validate-blog-links.sh _site` runs, then it exits 1 naming the
  uncovered slug (Guard 1, matrix row 1).
- Given the parity loop deleted, when the script runs, then the anti-vacuity
  floor fails it (Guard 1, matrix row 2).
- Given a file renamed to drop its date prefix while its map key remains, when
  the script runs, then the stale-key direction fails (Guard 1, matrix row 5).
- Given `docs/blog/redirects.njk` re-added emitting a stub, when the
  drift-guard suite runs, then the zero-stub fence is RED (Guard 2, row 1).
- Given the validate-seo skip block restored, when `validate-seo.test.ts`
  runs, then the flipped test is RED (Guard 2, row 2).
- Given the Phase-1 apply completed, when
  `for s in <69 sources>; do curl -sI -A Googlebot "https://$s" | head -1; done`
  runs, then every line is `HTTP/2 301` and each `location:` matches the pairs
  table.
- Given `https://www.soleur.ai/blog/2026-03-24-vibe-coding-vs-agentic-engineering/`,
  when fetched, then a single `301` lands on
  `https://soleur.ai/blog/vibe-coding-vs-agentic-engineering/` (not the
  www→apex-then-bulk two-hop path).
- Given PR-B merged, when `_site` rebuilds, then
  `grep -rl 'http-equiv="refresh"' _site` returns empty and
  `/blog/<date-slug>/` is absent from `_site` while still 301-ing at the edge.

## Success Metrics

- All 69 date-slug URL shapes serve deterministic edge 301s (GSC
  "Page with redirect" + "Excluded by noindex" buckets drain on re-crawl —
  observational lag, tracked by the Phase-3 follow-up issue).
- Zero meta-refresh stub machinery in the repo; CI suite green.
- The 5 target pages gain ≥5 new contextual inbound links each (measurable in
  `_site` output: aside + footer render).

## Dependencies & Risks

- **Sequencing dependency:** PR-B's merge precondition is PR-A's verified
  apply. If `apply-web-platform-infra.yml` fails, PR-B must not merge — the
  failure is cheap precisely because deletions are deferred.
- **CF token scope:** account-level `Account Rulesets:Edit` +
  `Account Filter Lists:Edit` already present post-#5092 (scope ledger in
  `variables.tf`); list items ride the existing binding — no new API surface,
  so the ADR-130/Sharp-Edges credential probe is satisfied by the existing
  live items (known-granted control: the list already applies).
- **`include_subdomains` caveat (inherited):** new items match every proxied
  subdomain (`app`/`deploy`/`ssh`/`registry`/`www`) — none serves `/blog/*`
  content; a stray request 404s today and would 301 to the apex canonical
  post-change. Same accepted caveat as the 13 existing items.
- **Precedent diff (4.4 gate):** sibling precedent = the 13 explicit
  `item { value { redirect { … } } }` blocks in the same file. This plan's
  `dynamic "item"` emits byte-identical compiled config (same five fields,
  same types) — the deviation is authoring form only: a 23-pair map + ~10-line
  stanza instead of ~690 near-identical lines. Verified the deviation is
  invisible to the committed guards: the canonicalizer test's span regex
  (`^\s*item\s*\{`) counts only literal blocks in `www_canonical` (still 1)
  and the mutation harness's reorder row operates on the explicit-item span
  region in `legal_redirects`, which the appended dynamic block sits outside.
  If a reviewer prefers precedent-exact form, 69 explicit items is the
  one-line fallback — rejected in Alternatives on reviewability, not
  correctness.
- **Cross-list precedence:** a `www.soleur.ai/blog/<date>/` request matches
  both the extended `legal_redirects` item and `www_canonical`; rule order
  (legal first, www second — guarded by `www-apex-canonicalizer.test.sh`)
  makes the specific redirect win → single hop. Verified by AC spot-check.
- **Eleventy `fileSlug` assumption:** canonical = filename minus date prefix.
  Verified against live stub targets in evidence; a post with a `permalink:`
  override would break the assumption — none of the 23 files declares one
  (grep-verified at planning time).
- **Deferral tracking:** GSC re-verification (Phase-3 issue); `api.soleur.ai`
  noindex → existing tracker #3379; homepage/nav pillar-page links →
  #8143/#8144. No new deferred items beyond these.

## References & Research

- Ground truth: `knowledge-base/project/specs/feat-one-shot-3328-gsc-indexing-cleanup/gsc-evidence.md`
- Issue: #3328 (OPEN); prior art #3297/#3296 (first GSC triage + zone rules),
  #5082 (legal-page Bulk Redirects), #3367 (bulk-redirect refactor tracker),
  #4577 (apex reconcile), #7640/ADR-194 (docs → Cloudflare Pages),
  #3379 (api.soleur.ai dormancy tracker)
- Code: `apps/web-platform/infra/seo-bulk-redirects.tf` (pattern),
  `apps/web-platform/infra/seo-rulesets.tf` (zone rules + dormant api rule),
  `plugins/soleur/docs/_data/blogRedirects.js` (`DATE_PREFIX_RE` semantics),
  `scripts/validate-blog-links.sh`,
  `plugins/soleur/test/seo-aeo-drift-guard.test.ts`
- Learnings: `2026-06-09-cloudflare-bulk-redirects-v4-schema-and-phase-order.md`,
  `2026-05-05-gsc-indexing-triage-patterns.md`,
  `2026-06-15-gsc-crawled-not-indexed-remediation-is-internal-linking.md`,
  `2026-06-01-gsc-page-with-redirect-is-historical-memory-verify-against-build.md`,
  `2026-07-06-gsc-coverage-report-is-playwright-pullable-after-operator-signin.md`
- Architecture: ADR-130, ADR-136 (pre-apply entrypoint gate), ADR-194, ADR-204
