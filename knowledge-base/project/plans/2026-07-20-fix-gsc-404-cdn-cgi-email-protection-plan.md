---
title: "fix: GSC 'Not found (404)' — Cloudflare email-obfuscation /cdn-cgi/ crawl leak"
date: 2026-07-20
type: bug-fix
lane: cross-domain
brand_survival_threshold: none
requires_cpo_signoff: false
branch: feat-one-shot-gsc-404-cdn-cgi-email-protection
related_issues: ["#3379"]
---

# fix: GSC "Not found (404)" — Cloudflare email-obfuscation `/cdn-cgi/` crawl leak

> **Lane note:** no `spec.md` exists for this branch, so `lane:` could not be carried
> forward. Defaulted to `cross-domain` (TR2 fail-closed).
>
> **[Updated 2026-07-20]** Revised after 6-agent plan review. Phase 4 (api.soleur.ai
> probe) cut on unanimous panel finding; the `validate-seo.sh` edit replaced with a
> repo-local test; two User-Challenges recorded in
> `knowledge-base/project/specs/feat-one-shot-gsc-404-cdn-cgi-email-protection/decision-challenges.md`.

## Overview

Google Search Console's `soleur.ai-Coverage-Validation-2026-07-20` export reports a
**failed** validation for "Not found (404)" across 4 URLs. This plan fixes the one URL
with a live repo-side defect and documents why the other three are deliberately untouched.

The defect: **Cloudflare Email Obfuscation (Scrape Shield) is enabled on the `soleur.ai`
zone and rewrites `mailto:` hrefs and plaintext addresses in the served marketing-site
HTML into `/cdn-cgi/l/email-protection` links.** Googlebot follows them and gets a 404.

**Remedy: add `Disallow: /cdn-cgi/` to the marketing site's `robots.txt`** — Cloudflare's
own documented best practice — rather than disabling Email Obfuscation. See
[Decision](#decision).

**Change set: 2 files.** One directive in a static file, plus one repo-local test.

## Root Cause — verified live

Verified 2026-07-20 by fetching served HTML as Googlebot UA. The hypothesis reproduced
exactly.

**Site-wide occurrence census** (counted with `grep -o … | wc -l`, not `grep -c`):

| Page | Occurrences |
|---|---|
| `/legal/privacy-policy/` | **20** |
| `/legal/terms-and-conditions/` | 7 |
| `/getting-started/` | 2 |
| `/pricing/` | 1 |
| `/`, `/changelog/` | 0 |
| **Total** | **30** |

Two structurally different rewrite forms exist. On `/getting-started/`:

**Form 1 — fragment form** (rewrite of the `mailto:` href at
`plugins/soleur/docs/pages/getting-started.njk`, the anchor whose source href begins
`mailto:ops@jikigai.com?subject=`):

```html
<a href="/cdn-cgi/l/email-protection#5837282b18323133313f3931763b3735672b2d3a323d3b2c65...">
  Founding cohort &mdash; limited to 10. Book intro …</a>
```

**Form 2 — bare form** (obfuscation of the *plaintext* `<code>ops@jikigai.com</code>`
fallback). **This is the crawlable one Googlebot followed:**

```html
<code><a href="/cdn-cgi/l/email-protection" class="__cf_email__"
   data-cfemail="214e5152614b484a484640480f424e4c">[email&#160;protected]</a></code>
```

Both resolve to `/cdn-cgi/l/email-protection` once a crawler strips the fragment.
Cloudflare also injects the decoder `/cdn-cgi/scripts/5c5dd728/cloudflare-static/email-decode.min.js`.

**Edge-injected, not committed:** `grep -rn 'cdn-cgi' plugins/soleur/docs/` returns
**zero**. Source ships plain `mailto:`; Cloudflare rewrites at the edge. Plaintext
`ops@jikigai.com` appears **0 times** in served HTML.

**Consequence for gate design:** because the rewrite happens at the edge, the built
artifact *never* contains `/cdn-cgi/`. A build-time gate asserting "built HTML is free of
`/cdn-cgi/l/email-protection`" would be **structurally incapable of failing**. Only the
robots.txt invariant is deterministically checkable in CI.

## Per-URL disposition

| URL | GSC | Verified live | Disposition |
|---|---|---|---|
| `soleur.ai/cdn-cgi/l/email-protection` | **Failed** | 404 | **FIXED** — `Disallow: /cdn-cgi/` in apex `robots.txt` |
| `www.soleur.ai/cdn-cgi/l/email-protection` | Pending | 404 | **FIXED by the same change.** `www.soleur.ai/robots.txt` `301`s to the apex file (verified) — one file covers both hosts. Note the redirect itself is not controlled by this repo. |
| `api.soleur.ai/` | Pending | 404, no `x-robots-tag` | **NO CHANGE.** DNS-only CNAME → `ifsccnjhymdmidffkzhl.supabase.co` (verified via `dig`), so Cloudflare Rules on our zone never see it and we don't control the Supabase gateway to serve a `robots.txt`. An `X-Robots-Tag` rule already exists at `apps/web-platform/infra/seo-rulesets.tf` (the `seo_response_headers` ruleset's api rule) and is deliberately dormant. Owned by **#3379** (OPEN, `p3-low`), whose two re-evaluation criteria are unchanged by this PR. Non-indexability is **already asserted** by 3 existing tests in `apps/web-platform/test/seo-rulesets-noindex.test.ts` (the api-rule presence, exact-header, and `#3379`-reference tests). No new work. |
| `soleur.ai/pages/legal/terms-of-service.html` | Pending | `301` → canonical, final `200` | **NO CHANGE — deliberately.** Already correct; clears on next crawl. Per `knowledge-base/project/learnings/2026-06-01-gsc-page-with-redirect-is-historical-memory-verify-against-build.md`, this row shape is Google's historical memory, not a live defect. Adding a redirect, canonical, or sitemap entry would create a chain or soft-404 and make it worse. |

## Decision

### Option A (rejected) — disable Email Obfuscation zone-wide

`cloudflare_zone_settings_override.soleur_ai` + `email_obfuscation = "off"`.

**Rejected because:**

1. **Zone-wide blast radius, applied to production automatically.** The setting is
   per-zone, so it also changes `app.soleur.ai` and every other host.
   `cloudflare_zone_settings_override.soleur_ai` is **inside** the `-target=` allow-list
   at `.github/workflows/apply-web-platform-infra.yml:322`, so it auto-applies on merge.
   Fixing a report-hygiene issue with a zone-wide production infra apply is
   disproportionate. **This is the load-bearing objection.**
2. **It exposes two addresses whose spam-load has real cost.** `legal@jikigai.com`
   (used throughout `plugins/soleur/docs/pages/legal/`) is the **GDPR/DSAR and
   automated-decision contestation channel** — a DSAR lost in a spam flood has statutory
   consequences, not just annoyance. `ops@jikigai.com` is the founder inbox *and* the
   founding-cohort conversion channel; flooding it degrades response latency to the
   highest-intent prospects.

   *Calibration:* obfuscation is **cheap friction, not a security control.** Cloudflare's
   `data-cfemail` is a single-byte XOR whose key is the first hex byte — publicly
   documented and decoded by off-the-shelf scrapers. It stops naive regex harvesters and
   nothing else. The argument above rests on "free friction worth keeping", not on
   "removing a control".
3. Leaves the other `/cdn-cgi/` crawl surfaces (`challenge-platform/`, `rum`, `trace`)
   crawlable — a recurring source of the same GSC noise.

### Option C (rejected, but closer than A) — host-scoped Configuration Rule

A `cloudflare_ruleset` in the `http_config_settings` phase with
`email_obfuscation = false` scoped by `http.host in {"soleur.ai" "www.soleur.ai"}`.

This **defeats Option A's blast-radius objection** — `app.soleur.ai` and every other host
keep obfuscation — and it removes the hrefs from the link graph entirely, which is a
strictly stronger fix for the GSC row than hiding them from crawlers. It is Terraform-native
and the repo already has 5 `cloudflare_ruleset` resources to pattern-match against (though
no `http_config_settings` phase ruleset exists yet, so it would be a new resource).

**Rejected for this PR** on proportionality: it is a new production infra resource on an
auto-applying path, to fix a 404 that Google states does not harm ranking. **But it is the
correct escalation** if the risk in [Risks](#risks--mitigations) row 1 materialises, and it
is recorded as a User-Challenge (see [Open questions](#open-questions-for-the-operator))
because a reasonable reviewer would choose it over Option B up front.

### Option B (chosen) — `Disallow: /cdn-cgi/` in `plugins/soleur/docs/robots.txt`

1. **Cloudflare's own documented best practice**, verbatim: *"As a best practice, update
   your `robots.txt` file to include `Disallow: /cdn-cgi/`."* —
   [developers.cloudflare.com/fundamentals/reference/cdn-cgi-endpoint/](https://developers.cloudflare.com/fundamentals/reference/cdn-cgi-endpoint/)
   (fetched 2026-07-20). This **reverses** the common assumption that `/cdn-cgi/` must
   stay crawlable.
2. Keeps the free anti-spam friction on `legal@` and `ops@`.
3. Fixes the whole `/cdn-cgi/` class, not just `email-protection`.
4. One line in committed source, passthrough-copied to the artifact
   (`eleventy.config.js:69`), therefore deterministically gate-able in CI.
5. Covers apex **and** `www` via the existing 301.
6. **No Terraform change, no production apply, no infra blast radius.**

**Two notes a future reviewer will otherwise re-derive:**

- **Cloudflare Images:** the vendor page notes that sites using image transformations need
  `Allow: /cdn-cgi/image/` *above* the `Disallow`. `grep` for
  `cdn-cgi/image|cloudflare_image|imagedelivery` returns **zero** — not in use. The
  condition is recorded in the test file (not in the public `robots.txt`, which would make
  the file its own false-positive; see [Sharp Edges](#sharp-edges)).
- **Blocked JS is intentional and harmless.** The disallow also stops Googlebot fetching
  `email-decode.min.js` and the challenge-platform scripts. Blocking JS is normally an SEO
  smell; here the only thing that script renders is an email address, which is not content
  Google needs. Cloudflare's guidance accounts for this.
- **CSP is a non-issue either way.** The site's strict hash-based CSP
  (`plugins/soleur/docs/_includes/base.njk:30`) is `script-src 'self' https://plausible.io`
  + 3 hashes. The decoder is an *external same-origin* script, so `'self'` permits it. No
  interaction with this change.

## Implementation Phases

### Phase 1 — RED

1. Create `plugins/soleur/test/robots-cdn-cgi.test.ts` (runner: **`bun:test`**, matching
   the sibling `plugins/soleur/test/validate-seo.test.ts:1`). Assert, reading
   `plugins/soleur/docs/robots.txt` from disk:
   - it contains a line matching `/^\s*disallow:\s*\/cdn-cgi\//im` (anchored directive,
     case-insensitive — robots.txt directives are case-insensitive per RFC 9309, and
     `cq-assert-anchor-not-bare-token` requires an anchor, not a bare substring);
   - it contains **no** `^\s*User-agent:\s*Googlebot` stanza. *Why:* Googlebot obeys the
     `*` group **only if** no Googlebot-specific group exists. If one were ever added, the
     `*` group becomes inert for the one crawler this plan is about, and a
     directive-presence assertion would still pass. This closes that hole;
   - `eleventy.config.js` still contains the `robots.txt` passthrough-copy line, so the
     directive reaches the built artifact.
2. Confirm RED: `bun test plugins/soleur/test/robots-cdn-cgi.test.ts`

### Phase 2 — GREEN

3. Edit `plugins/soleur/docs/robots.txt` to:

   ```text
   User-agent: *
   Allow: /

   # Cloudflare-internal endpoints; 404/204 to crawlers.
   # https://developers.cloudflare.com/fundamentals/reference/cdn-cgi-endpoint/
   Disallow: /cdn-cgi/

   Sitemap: https://soleur.ai/sitemap.xml
   ```

   **Ordering note:** robots.txt resolves `Allow`/`Disallow` conflicts by **longest match**,
   not file order (RFC 9309) — `/cdn-cgi/` (9 chars) beats `/` (1 char), so `Allow: /` does
   not defeat it. Do not "fix" this file by reordering.

4. Confirm GREEN: `bun test plugins/soleur/test/robots-cdn-cgi.test.ts`
5. Build and confirm the artifact carries it: `npx @11ty/eleventy` then
   `grep -iE '^\s*disallow:\s*/cdn-cgi/' _site/robots.txt`
6. Confirm no regression in the existing SEO gate, exactly as `deploy-docs.yml:75` runs it:
   `bash plugins/soleur/skills/seo-aeo/scripts/validate-seo.sh _site`

## Files to Edit

- `plugins/soleur/docs/robots.txt` — the directive + a 2-line vendor-citation comment.

## Files to Create

- `plugins/soleur/test/robots-cdn-cgi.test.ts` — the gate.

**Explicitly NOT edited, and why:**

- `plugins/soleur/skills/seo-aeo/scripts/validate-seo.sh` — **deliberately not touched.**
  This script is a **distributed plugin skill**, shipped to Soleur users and invoked by
  `.openhands/skills/seo-aeo-analyst/SKILL.md` and two Inngest cron prompts. Making
  `Disallow: /cdn-cgi/` a hard FAIL there would impose a Cloudflare-specific requirement on
  every consumer site, including sites not behind Cloudflare where the directive is
  meaningless. The gate belongs in a repo-local test. *(This also avoids a real defect: the
  shared `setupSite()` fixture at `plugins/soleur/test/validate-seo.test.ts:41` defaults to
  `"User-agent: *\nAllow: /\n"`, and 8 tests assert exit 0 against it — an unconditional
  check would have turned the currently-green 21-test suite red.)*
- `apps/web-platform/infra/**` — no Terraform change (see [Decision](#decision)).
- `plugins/soleur/docs/pages/*.njk` — the `mailto:` sources stay as-is. **But a real
  user-facing defect was identified here and is being deliberately deferred, not
  overlooked** — see [Deferred](#deferred-cta-fallback-rendering-defect).

## Deferred: CTA fallback rendering defect

Two independent reviewers (architecture + CMO) surfaced a user-facing defect that this
plan's SEO framing did not set out to fix. Recording it so it is visibly deferred rather
than silently dropped.

`plugins/soleur/docs/pages/getting-started.njk:22` deliberately ships a
graceful-degradation fallback beside the founding-cohort CTA:

```html
<span class="hero-meta-fallback">(or email <code>ops@jikigai.com</code>)</span>
```

Cloudflare rewrites it to render literally as **`[email protected]`**. The fallback is not
degraded — it is *inverted*: the one element whose entire job is to show a copyable address
now shows a string that is not an address. To Soleur's stated beachhead audience
(technical builders), that is a recognisable broken-Cloudflare artifact on a page selling
engineering competence. The same applies to `mailto:hello@soleur.ai` at
`plugins/soleur/docs/pages/pricing.njk:275`.

Severity is bounded: the hero's **primary** CTA (`Join the waitlist` → `/pricing/#waitlist`)
and **secondary** CTA (`Run the self-hosted version today`) are unaffected; only the
tertiary `hero-meta` line is.

**Recommended fix (not in this PR):** wrap the fallback in `<!--email_off-->` and write the
address in a non-harvestable human form (`ops at jikigai dot com`). Do **not** simply
`<!--email_off-->` the plaintext — that publishes a harvestable address and reintroduces
exactly the exposure Option A was rejected for.

**Action:** `/work` files a tracking issue for this with the above analysis. It is out of
scope here because it changes operator-stated scope — recorded as a User-Challenge in
`decision-challenges.md`.

## Acceptance Criteria

### Pre-merge (PR)

1. `plugins/soleur/test/robots-cdn-cgi.test.ts` passes, and its assertions cover: the
   anchored `Disallow: /cdn-cgi/` directive, the absence of a `User-agent: Googlebot`
   stanza, and the `eleventy.config.js` passthrough line.
2. The gate is **capable of failing**: temporarily removing the directive from
   `plugins/soleur/docs/robots.txt` makes the test fail; restoring it makes it pass.
   (Guards against a structurally-unfailable gate — cf. commit `7f84318dc`.)
3. After `npx @11ty/eleventy`, `grep -iE '^\s*disallow:\s*/cdn-cgi/' _site/robots.txt`
   matches — proving passthrough-copy carries the directive to the deployed artifact.
4. `bash plugins/soleur/skills/seo-aeo/scripts/validate-seo.sh _site` still exits `0`
   (no regression in the existing SEO gate). *Verified achievable at plan time — see
   [Preflight](#preflight).*
5. `bun test plugins/soleur/test/` passes in full — specifically, the pre-existing
   21-test `validate-seo.test.ts` suite is still green (proving the distributed skill and
   its shared fixture were left untouched).
6. `git diff --name-only origin/main...HEAD` contains no files under
   `apps/web-platform/infra/` — proving the chosen remedy required no production infra apply.
7. PR body uses `Ref #3379`, **not** `Closes` — #3379 is not resolved by this PR and its
   re-evaluation criteria are unchanged.

### Post-merge (operator)

8. `deploy-docs.yml` succeeded for the merge SHA:
   `gh run list --workflow=deploy-docs.yml --branch=main --limit=1 --json conclusion,headSha`
9. **Live confirmation, with propagation tolerance.** `deploy-docs.yml` documents a
   **~15-minute GitHub Pages re-propagation window** (observed 2026-05-29, #4573/#4578), and
   the apex is Cloudflare-proxied, so a single-shot curl can read a stale body and
   falsely look like failure:

   ```bash
   for i in $(seq 1 10); do
     curl -sS -H 'Cache-Control: no-cache' https://soleur.ai/robots.txt \
       | grep -iqE '^\s*disallow:\s*/cdn-cgi/' && { echo "apex OK"; break; }
     echo "attempt $i: not yet propagated"; sleep 120
   done
   curl -sSL -H 'Cache-Control: no-cache' https://www.soleur.ai/robots.txt \
     | grep -iE '^\s*disallow:\s*/cdn-cgi/'
   ```

   Both must ultimately print the directive. (The second proves the `www` 301 inherits it.)

10. **Semantic confirmation of Google's own parse** — converts the presence-of-directive
    proxy into the actual invariant. In GSC → **URL Inspection**, live-test
    `https://soleur.ai/cdn-cgi/l/email-protection` and confirm it reports
    **"Blocked by robots.txt"**. This is the precondition for step 11.

11. **GSC re-validation.** *Precondition:* step 9 green **and** step 10 reports "Blocked by
    robots.txt". Google caches `robots.txt` for roughly **24h**, so do not trigger before
    then — a premature click fails the run and GSC imposes a cooldown before retry.

    *Action:* GSC → **Page indexing → "Not found (404)" → Validate Fix.**

    *Post-condition:* the validation state reads "Validation passed", or the two
    `/cdn-cgi/` rows leave the report. Google's validation runs take **up to 28 days**.

    *If instead they migrate to "Indexed, though blocked by robots.txt"*, that is the
    documented Low–Medium risk case — escalate per [Risks](#risks--mitigations) row 1.
    Do not read this criterion as a promise; it is the expected outcome, not a guaranteed one.

    *`Automation: not feasible because` Google Search Console exposes no public API for
    triggering a coverage-issue validation run or reading its state. The Search Console API
    covers Search Analytics, sitemaps, and URL Inspection only — there is no
    validation-trigger endpoint. This is a genuine human-only step; do not re-litigate
    automating it.*

12. **Feedback loop.** `/work` files a follow-up issue, due 28 days post-merge, to re-check
    the GSC "Not found (404)" report and confirm all four rows cleared. Without this, a
    non-clear is silent until the next ad-hoc export. (A `scripts/followthroughs/` probe is
    **not** usable here — it would need to read GSC, which has no API per step 11.)

## Rollback

**Trigger:** soleur.ai marketing pages begin dropping out of Google's index — watched via
the GSC **Pages** report's valid-page count, or a `site:soleur.ai` result count, checked at
step 12's 28-day mark and any time an anomaly is suspected.

**Mechanism:** `git revert` the commit. `plugins/soleur/docs/robots.txt` is inside
`deploy-docs.yml`'s path filter, so the revert redeploys itself — no manual publish step.

**Time-to-effect is asymmetric and must be expected.** Removing a `Disallow` does **not**
restore crawling immediately. Google re-reads `robots.txt` on its own ~24h cadence, then
re-crawl and re-index take further days. An operator expecting instant recovery will
escalate wrongly. Budget ~1 week for full recovery.

## Risks & Mitigations

| Risk | Likelihood | Mitigation |
|---|---|---|
| **URLs migrate to "Indexed, though blocked by robots.txt" rather than dropping.** The 30 hrefs **remain** in the served HTML, so Google keeps seeing internal links to a now-uncrawlable URL — and the disallow removes the very signal (the 404) that would otherwise have dropped it organically. **This repo hit this exact trap before:** `app.soleur.ai/` was indexed *because* robots.txt blocked the crawl, preventing Googlebot from reading the `noindex` (see the `app.soleur.ai` comment block in `apps/web-platform/infra/seo-rulesets.tf`). | Low–Medium | The precedent differs on the axis that matters: `app.soleur.ai/` served a **200 page**; `/cdn-cgi/l/email-protection` returns a **404 with no body**, and Google does not index contentless 404s. **This is the plan's weakest argument and is flagged as such** — a reviewer argued the operative condition in the precedent was *linked + disallowed*, which does hold here (30 internal links). **Defined escalation:** if step 11 surfaces this migration, adopt **Option C** (host-scoped Configuration Rule disabling obfuscation for `soleur.ai`/`www.soleur.ai` only), which removes the hrefs from the link graph entirely. Recorded as a User-Challenge. |
| **Over-broad disallow de-indexes the site.** A typo (`Disallow: /`) would remove soleur.ai from search — top of funnel for a pre-revenue product. | Low | AC1 asserts the exact anchored directive; AC2 proves the gate can fail; the pre-existing validator independently checks no AI-bot stanza carries `Disallow: /`. [Preflight](#preflight) confirmed no validator regression. [Rollback](#rollback) defined. |
| **A `User-agent: Googlebot` stanza is added later**, silently making the `*` group inert for Googlebot. | Low | AC1's second assertion fails the build if such a stanza appears. |
| **Cloudflare Images adopted later**, silently de-indexing transformed images. | Low | Condition recorded in the test file; `grep` confirms zero current usage. |
| **`www` coverage depends on a 301 this repo does not control.** | Low | AC9's second curl proves it at operator-check time. |

## Preflight (executed 2026-07-20)

The proposed `robots.txt` was run against the **real** validator before this plan was
frozen — the concern being that adding a `Disallow` line might trip the validator's AI-bot
stanza detector, whose own header comment warns it "only checks the line immediately after
User-agent":

```text
PASS: robots.txt exists
PASS: robots.txt does not block GPTBot / PerplexityBot / ClaudeBot / Google-Extended
PASS: sitemap host matches robots.txt Sitemap line
```

**No regression.** (Other `FAIL:` lines in that run came from a deliberately minimal
fixture — missing `llms.txt`, canonical, JSON-LD — not from the change. A full real build
was separately confirmed to pass the validator with `EXIT=0`.)

## Observability

```yaml
liveness_signal:
  what: "https://soleur.ai/robots.txt serves a line matching (?i)^\\s*disallow:\\s*/cdn-cgi/"
  cadence: "on every merge to main touching plugins/soleur/docs/** (deploy-docs.yml), plus CI on every PR (bun test)"
  alert_target: "GitHub Actions job failure annotation"
  configured_in: "plugins/soleur/test/robots-cdn-cgi.test.ts (CI) + .github/workflows/deploy-docs.yml"

error_reporting:
  destination: "GitHub Actions job failure; bun test prints the failing assertion"
  fail_loud: true

failure_modes:
  - mode: "robots.txt loses the /cdn-cgi/ disallow (regression or bad edit)"
    detection: "plugins/soleur/test/robots-cdn-cgi.test.ts anchored-directive assertion"
    alert_route: "CI fails on the PR -> merge blocked"
  - mode: "robots.txt not passthrough-copied into _site (eleventy config regression)"
    detection: "same test asserts the eleventy.config.js passthrough line; validate-seo.sh 'robots.txt exists' check on _site"
    alert_route: "CI fails; deploy-docs.yml fails before GitHub Pages publish"
  - mode: "a User-agent: Googlebot stanza is introduced, making the * group inert"
    detection: "same test asserts no Googlebot stanza exists"
    alert_route: "CI fails on the PR"

logs:
  where: "GitHub Actions run logs (bun test output; deploy-docs.yml validate-seo.sh stdout)"
  retention: "90 days"

discoverability_test:
  command: "curl -sS https://soleur.ai/robots.txt | grep -iE '^\\s*disallow:\\s*/cdn-cgi/'"
  expected_output: "Disallow: /cdn-cgi/"
```

No SSH in any verification path.

## Infrastructure (IaC)

**No Terraform change.** Asserted by AC6. Nothing in `## Files to Edit` sits under
`apps/web-platform/infra/`, so `apply-web-platform-infra.yml` will not fire. No new servers,
secrets, vendors, DNS records, or runtime processes.

The rejected Options A and C *would* have been infra — see [Decision](#decision) for the
auto-apply reasoning that drove the rejection.

## Architecture Decision (ADR/C4)

**No ADR.** A crawl-exclusion directive plus a CI check changes no ownership/tenancy
boundary, substrate, integration pattern, or trust boundary, and reverses no existing ADR.

**C4:** the external actors involved (Googlebot, Cloudflare, GitHub Pages) and their
relationships are unchanged — this narrows *which paths* Googlebot requests, adding no
element, container, data store, or access relationship. No `.c4` edit in scope.

*Reviewer dissent, recorded:* architecture-strategist argued an ADR is warranted because the
PR sets a reusable precedent ("when the edge injects artifacts that leak into the crawl
graph, hide them from crawlers rather than stopping their emission") while explicitly
rejecting the Terraform-native alternative. Deferred — if Option C is later adopted per the
escalation path, that reversal is the natural ADR trigger.

## Domain Review

**Domains relevant:** Marketing (SEO), Engineering

- **Marketing (SEO):** correctly scoped as report hygiene, **not** ranking recovery —
  Google states 404s do not harm ranking, so the purchase is GSC cleanliness. The plan
  must not promise ranking improvements (AC11 wording adjusted accordingly). Preserving
  obfuscation protects the `legal@` DSAR channel and the `ops@` conversion SLA.
- **Engineering:** minimal blast radius — one static file plus one repo-local test, no
  infra apply, no migration, no runtime code. The distributed-skill boundary
  (`validate-seo.sh`) is deliberately not crossed.

**Product/UX Gate:** not applicable — no UI-surface paths in `## Files to Edit` /
`## Files to Create`. The mechanical UI-surface override did not fire. (The deferred
`.njk` CTA-fallback defect is a *product* concern and is explicitly recorded above rather
than folded in silently.)

## GDPR / Compliance Gate

**Skipped** — no regulated-data surface: no schema, migration, auth flow, API route, or
`.sql` file; no new processing activity or distribution surface. Threshold `none`.

Noted inversely: the rejected Option A would have de-obfuscated `legal@jikigai.com`, the
DSAR intake channel — a compliance-relevant reason to keep obfuscation.

## User-Brand Impact

**If this lands broken, the user experiences:** a malformed `robots.txt` at
`https://soleur.ai/robots.txt` — realistically an over-broad `Disallow` that de-indexes the
marketing site, removing Soleur from search results.

**If this leaks, the user's data / workflow / money is exposed via:** nothing. A
crawl-exclusion directive in a public static file touches no user data, credentials,
authenticated surface, or production infrastructure. The *rejected* Option A **would** have
had an exposure vector (de-obfuscating the DSAR and founder inboxes) — part of why it lost.

**Brand-survival threshold:** `none`

*Justification:* no sensitive-path files are touched — only a static `robots.txt` and a test.

## Open questions for the operator

Recorded in full at
`knowledge-base/project/specs/feat-one-shot-gsc-404-cdn-cgi-email-protection/decision-challenges.md`
(rendered into the PR body and filed as an `action-required` issue by `/ship`):

1. **Option C vs Option B** — should the host-scoped Configuration Rule be adopted up front
   rather than as an escalation?
2. **CTA fallback fix** — should the `[email protected]` rendering defect be folded into
   this PR rather than deferred?

## Open Code-Review Overlap

**None.** All planned paths checked against the 61 open `code-review` issues via
`gh issue list --json` piped through a standalone `jq --arg` contains-filter. Zero matches.

## Sharp Edges

- **`grep -c` undercounts occurrences in minified HTML.** During verification
  `grep -c 'cdn-cgi/l/email-protection'` reported `1` where the page had **2** — `grep -c`
  counts matching *lines*, and served HTML puts both hrefs on one line. Use
  `grep -o … | wc -l`. This is why the census table above is per-occurrence.
- **`&&`-chained verification stops on a zero-match `grep`.** A chain in this session
  silently truncated because `grep -o` found nothing and returned exit 1. Append `|| true`
  or split commands. (Also in
  `2026-06-01-gsc-page-with-redirect-is-historical-memory-verify-against-build.md`.)
- **`ugrep` rejects wide `.{0,N}` context patterns** with `exceeds complexity limits`. The
  host `grep` is `ugrep`; use `python3` slicing for context extraction on large single-line files.
- **Do not put the Cloudflare-Images note in the public `robots.txt`.** A plan draft did,
  and it made an AC self-falsifying: the AC grepped for `cdn-cgi/image` returning zero,
  while the comment it shipped *contained* that string. A detector that fires on its own
  documentation is not a detector. The condition lives in the test file instead.
- **Do not add the `/cdn-cgi/` check to `validate-seo.sh`.** It is a distributed plugin
  skill; a hard FAIL there imposes a Cloudflare-specific requirement on every consumer
  site. It would also have turned the green 21-test `validate-seo.test.ts` suite red, since
  `setupSite()`'s default fixture (line 41) omits the directive and 8 tests assert exit 0.
- **robots.txt conflict resolution is longest-match, not first-match** (RFC 9309).
  `Allow: /` does not override `Disallow: /cdn-cgi/`. Do not "fix" the file by reordering.
- **A directive-presence assertion is only sound while no `User-agent: Googlebot` stanza
  exists.** Googlebot obeys the `*` group only in that case. AC1 pins it.
- **Do not add `X-Robots-Tag` or a `robots.txt` for `api.soleur.ai`.** Both are structurally
  inert on a DNS-only CNAME; a rule exists and is deliberately dormant. This surface has now
  been examined three times (#3297 → #4575 → #3379); **#3379 is the single live tracker** —
  add findings there rather than creating a fourth artifact.
- **The `scripts/followthroughs/` sweeper closes issues on exit 0.** A draft of this plan
  proposed enrolling an `api.soleur.ai` probe against #3379; because the probe's asserted
  condition is *already true today*, the sweeper would have **closed #3379 on its first
  run** — contradicting the plan's own "`Ref`, not `Closes`" criterion. Follow-through
  probes are *trigger detectors* (fire once, close the tracker), not *regression detectors*.
  Do not conflate them.
