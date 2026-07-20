---
title: "fix: GSC 'Not found (404)' — disable Cloudflare email obfuscation on marketing hosts"
date: 2026-07-20
type: bug-fix
lane: cross-domain
brand_survival_threshold: none
requires_cpo_signoff: false
branch: feat-one-shot-gsc-404-cdn-cgi-email-protection
related_issues: ["#3379"]
---

# fix: GSC "Not found (404)" — Cloudflare email-obfuscation `/cdn-cgi/` crawl leak

> **Lane note:** no `spec.md` exists for this branch; `lane:` defaulted to `cross-domain`
> (TR2 fail-closed).
>
> **[Updated 2026-07-20 — decision REVERSED at deepen-plan.]** v1 chose
> `Disallow: /cdn-cgi/` in robots.txt. Deepen-plan research found Google **explicitly
> advises against that remedy for this exact case**, corroborated by a repo learning v1
> had not applied. The plan now adopts a **host-scoped Cloudflare Configuration Rule**.
> Full reversal record in [Decision](#decision). Earlier review also cut a Phase 4
> api.soleur.ai probe (would have auto-closed #3379).

## Overview

GSC's `soleur.ai-Coverage-Validation-2026-07-20` export reports a **failed** validation
for "Not found (404)" across 4 URLs. This plan fixes the one URL with a live repo-side
defect and documents why the other three are deliberately untouched.

The defect: **Cloudflare Email Obfuscation (Scrape Shield) is on for the `soleur.ai`
zone and rewrites `mailto:` hrefs and plaintext addresses in served marketing HTML into
`/cdn-cgi/l/email-protection` links** (30 of them site-wide). Googlebot follows them and
gets a 404.

**Remedy: disable Email Obfuscation for `soleur.ai` + `www.soleur.ai` only**, via a
host-scoped `cloudflare_ruleset` in the `http_config_settings` phase. This **removes the
hrefs from the HTML at the source**, so there is nothing left for Googlebot to crawl.

This is option (a) exactly as the brief framed it — *"disabling Cloudflare Email
Obfuscation for the zone/**marketing pages** via Terraform"* — scoped to the marketing
pages rather than the whole zone.

## Root Cause — verified live

Verified 2026-07-20 by fetching served HTML as Googlebot UA.

**Site-wide census** (counted `grep -o … | wc -l`, not `grep -c`):

| Page | Occurrences |
|---|---|
| `/legal/privacy-policy/` | **20** |
| `/legal/terms-and-conditions/` | 7 |
| `/getting-started/` | 2 |
| `/pricing/` | 1 |
| `/`, `/changelog/` | 0 |
| **Total** | **30** |

Two rewrite forms. On `/getting-started/`:

**Form 1 — fragment form** (rewrite of the `mailto:` href in
`plugins/soleur/docs/pages/getting-started.njk`, source href beginning
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
Cloudflare also injects `/cdn-cgi/scripts/…/email-decode.min.js`.

**Edge-injected, not committed:** `grep -rn 'cdn-cgi' plugins/soleur/docs/` returns
**zero** (independently re-verified). Source ships plain `mailto:`; Cloudflare rewrites at
the edge. Plaintext `ops@jikigai.com` appears **0 times** in served HTML.

**Consequence for gate design:** the built artifact *never* contains `/cdn-cgi/`, so a
build-time gate asserting "built HTML is free of `/cdn-cgi/l/email-protection`" is
**structurally incapable of failing**. The gate must assert the Terraform rule in source
plus a post-deploy live probe.

## Per-URL disposition

| URL | GSC | Verified live | Disposition |
|---|---|---|---|
| `soleur.ai/cdn-cgi/l/email-protection` | **Failed** | 404 | **FIXED** — hrefs removed at the edge |
| `www.soleur.ai/cdn-cgi/l/email-protection` | Pending | 404 | **FIXED by the same rule** (`www.soleur.ai` is in the rule's host set) |
| `api.soleur.ai/` | Pending | 404, no `x-robots-tag` | **NO CHANGE.** DNS-only CNAME → `ifsccnjhymdmidffkzhl.supabase.co` (verified via `dig`), so Cloudflare Rules on our zone never see it, and we don't control the Supabase gateway to serve a `robots.txt`. An `X-Robots-Tag` rule already exists in `apps/web-platform/infra/seo-rulesets.tf` and is deliberately dormant. Owned by **#3379** (OPEN, `p3-low`), criteria unchanged. Non-indexability is **already asserted** by 3 existing tests in `apps/web-platform/test/seo-rulesets-noindex.test.ts`. No new work. |
| `soleur.ai/pages/legal/terms-of-service.html` | Pending | `301` → canonical, final `200` | **NO CHANGE — deliberately.** Already correct; clears on next crawl. Per `knowledge-base/project/learnings/2026-06-01-gsc-page-with-redirect-is-historical-memory-verify-against-build.md` this row shape is Google's historical memory, not a live defect. Adding a redirect, canonical, or sitemap entry would create a chain or soft-404 and make it worse. |

## Decision

### Option B (REJECTED — was v1's choice) — `Disallow: /cdn-cgi/` in robots.txt

Cloudflare does recommend this as generic hygiene, verbatim: *"As a best practice, update
your `robots.txt` file to include `Disallow: /cdn-cgi/`"*
([developers.cloudflare.com](https://developers.cloudflare.com/fundamentals/reference/cdn-cgi-endpoint/)).
v1 adopted it on that basis. **Deepen-plan research reversed it.** Three independent lines
of evidence:

1. **Google explicitly advises against it for this exact situation.** From Google's own
   404 documentation, verbatim: *"Don't create fake content, redirect to your homepage, or
   **use robots.txt to block 404s** — all of these things make it harder for us to
   recognize your site's structure."*
   ([support.google.com/webmasters/answer/2445990](https://support.google.com/webmasters/answer/2445990))
   Cloudflare's advice is generic hygiene for sites with no GSC 404 report on that path;
   Google's is specific to the case we actually have, and it governs.

2. **robots.txt cannot de-index, and we supply the precondition for indexing.** Google:
   *"A page that's disallowed in robots.txt can still be indexed if linked to from other
   sites … the URL address … can still appear in Google Search results"*; and *"it is not
   a mechanism for keeping a web page out of Google"*
   ([Google robots.txt intro](https://developers.google.com/search/docs/crawling-indexing/robots/intro)).
   We have **30 internal links from indexed pages** to the target. Blocking the crawl
   removes the 404 signal that would otherwise have retired the URL, while leaving the
   links that keep it discoverable — the textbook recipe for **"Indexed, though blocked by
   robots.txt"**, which is strictly worse than the 404 we started with.

3. **The repo already learned this the hard way, and v1 missed the learning.**
   `knowledge-base/project/learnings/2026-06-14-gsc-indexed-though-blocked-by-robots-is-a-real-misconfig-not-benign.md`
   — title and Key Insight are unambiguous: *"robots.txt is never an indexing control and
   never a security control — it only asks compliant bots not to crawl."* That learning
   documents `app.soleur.ai/` becoming indexed **because** a robots.txt `Disallow`
   prevented Googlebot from ever reading the `noindex`. Same trap, same zone, six weeks ago.

Also note Google states **404s do not harm indexing or ranking**, and *"if it is a bad URL
that never existed on your site, you probably don't need to worry about it."* So a remedy
that risks converting a harmless self-clearing 404 into a persistent indexed-but-blocked
row is **negative value**.

### Option A (rejected) — disable Email Obfuscation zone-wide

`cloudflare_zone_settings_override.soleur_ai` + `email_obfuscation = "off"`.

Correct mechanism, wrong scope. The setting is per-zone, so it would also change
`app.soleur.ai` and every other host. `cloudflare_zone_settings_override.soleur_ai` is
inside the `-target=` auto-apply allow-list
(`.github/workflows/apply-web-platform-infra.yml:322`), so it applies to production on
merge. Option C achieves the same outcome with the blast radius bounded to two hostnames.

### Option C (CHOSEN) — host-scoped Configuration Rule

A new `cloudflare_ruleset` in the `http_config_settings` phase, action `set_config`,
`email_obfuscation = false`, scoped by
`(http.host eq "soleur.ai" or http.host eq "www.soleur.ai")`.

1. **It eliminates the surface instead of annotating it.** With obfuscation off for the
   marketing hosts, Cloudflare stops rewriting — the 30 `/cdn-cgi/l/email-protection`
   hrefs simply cease to exist. Google recrawls the pages, finds no links, and the URLs
   retire naturally. This is the disposition
   `knowledge-base/project/learnings/2026-05-05-gsc-indexing-triage-patterns.md` prescribes:
   *"eliminate the surface entirely rather than annotating it."*
2. **Blast radius is two hostnames.** `app.soleur.ai`, `deploy.soleur.ai`, and everything
   else keep obfuscation. This is the objection that sank Option A, and Option C answers it.
3. **It is committed IaC**, as the brief required — not a dashboard click.
4. **It fixes a real user-facing defect as a side effect** — see [below](#side-effect-fix).
5. **Feasible on the pinned provider — verified, not assumed.** `apps/web-platform/infra/.terraform.lock.hcl`
   pins `cloudflare/cloudflare 4.52.7`. The v4 provider docs confirm all three required
   pieces exist: `email_obfuscation` *(Boolean) "Turn on or off the Cloudflare Email
   Obfuscation feature"*, `http_config_settings` as a valid `phase`, and `set_config` as a
   valid `action`.

**Accepted cost — stated plainly.** The marketing pages' addresses (`ops@jikigai.com`,
`hello@soleur.ai`, `legal@jikigai.com`) become plaintext in HTML and therefore
harvestable. Weighing it honestly:

- What is lost is **cheap friction, not a security control.** Cloudflare's `data-cfemail`
  is a single-byte XOR whose key is the first hex byte — publicly documented and decoded
  by off-the-shelf scrapers for over a decade.
- Plaintext contact addresses on a privacy policy / legal page are near-universal practice.
- `legal@jikigai.com` is the GDPR/DSAR channel and `ops@jikigai.com` is the founder inbox,
  so spam load is a genuine (if modest) cost. If it becomes material, the escalation is a
  contact form or an alias — **not** re-enabling obfuscation, which would reintroduce this
  exact bug.

**No robots.txt change is made.** Per the brief's *"do not do both blindly"*: once the
hrefs are gone, a `/cdn-cgi/` disallow is unnecessary for the reported issue, and Google
advises against robots-blocking 404s. Generic `/cdn-cgi/` hygiene for the *other*
endpoints (`challenge-platform/`, `rum`, `trace`) is a separate, non-urgent decision.

### Side-effect fix

Disabling obfuscation on the marketing hosts also repairs a user-facing defect that two
reviewers flagged independently. `plugins/soleur/docs/pages/getting-started.njk:22` ships
a deliberate graceful-degradation fallback:

```html
<span class="hero-meta-fallback">(or email <code>ops@jikigai.com</code>)</span>
```

which currently renders as literal **`[email protected]`** — the one element whose job is
to show a copyable address instead shows a string that is not an address, on the page
selling engineering competence to technical builders. The founding-cohort CTA href is
likewise currently a 404 for any visitor without JS. Both revert to correct behavior with
no `.njk` edit. (Severity was bounded: the hero's primary CTA `Join the waitlist` and
secondary `Run the self-hosted version today` were never affected.)

## Implementation Phases

### Phase 1 — RED: source guard for the new rule

1. Create `apps/web-platform/test/seo-config-rules.test.ts` (runner: **vitest**;
   `apps/web-platform/vitest.config.ts` `unit` project includes `test/**/*.test.ts`).
   Mirror the text-parsing approach of the sibling `test/seo-rulesets-noindex.test.ts`
   (`readFileSync` + brace-counting extraction — **not** an HCL parser). Assert that
   `apps/web-platform/infra/seo-config-rules.tf`:
   - declares a `cloudflare_ruleset` with `phase = "http_config_settings"` and `kind = "zone"`;
   - has a rule with `action = "set_config"` and `email_obfuscation = false`;
   - scopes the expression to **both** `soleur.ai` and `www.soleur.ai`, and to **neither**
     `app.soleur.ai` nor `deploy.soleur.ai` nor `api.soleur.ai` (the blast-radius bound is
     the load-bearing property — assert it explicitly, both positively and negatively);
   - is `enabled = true`.
2. Assert the `-target=` allow-list in `.github/workflows/apply-web-platform-infra.yml`
   contains the new resource address (otherwise the rule is committed but never applied —
   a silent no-op of exactly the class `#3379` already documents).
3. Confirm RED:
   `cd apps/web-platform && ./node_modules/.bin/vitest run test/seo-config-rules.test.ts`

### Phase 2 — GREEN: the Terraform rule

4. Create `apps/web-platform/infra/seo-config-rules.tf`. Shape (verify attribute names
   against the pinned v4.52.7 provider before writing — do not copy this block blindly):

   ```hcl
   resource "cloudflare_ruleset" "seo_config_settings" {
     provider = cloudflare.rulesets
     zone_id  = var.cf_zone_id
     name     = "Marketing-host config overrides"
     kind     = "zone"
     phase    = "http_config_settings"

     rules {
       action      = "set_config"
       description = "Disable Email Obfuscation on marketing hosts (GSC 404 on /cdn-cgi/l/email-protection)"
       enabled     = true
       expression  = "(http.host eq \"soleur.ai\" or http.host eq \"www.soleur.ai\")"
       action_parameters {
         email_obfuscation = false
       }
     }
   }
   ```

   Carry a comment block explaining *why* (the GSC 404, the 30 hrefs, why not robots.txt,
   why host-scoped not zone-wide), following the precedent density of `seo-rulesets.tf`.
   Reuse the existing `cloudflare.rulesets` provider alias — confirm its name in `main.tf`.

5. Add the resource to the `-target=` allow-list in
   `.github/workflows/apply-web-platform-infra.yml`.
   **Sweep the guard suites**: a `-target=` allow-list is typically asserted on by more
   than one artifact. Run `git grep -ln 'cloudflare_ruleset\|\-target=' scripts/ apps/web-platform/infra/*.test.sh`
   and update **every** hit — the scope-guard suites are orphan suites that only the
   full-suite run exercises, and are the ones plans reliably miss.
6. Confirm GREEN: `cd apps/web-platform && ./node_modules/.bin/vitest run test/seo-config-rules.test.ts`
7. Confirm no regression: `cd apps/web-platform && npm run test:ci`
8. `terraform fmt -check` and `terraform validate` in `apps/web-platform/infra/`
   (use the canonical Doppler invocation triplet — see
   `knowledge-base/project/learnings/2026-05-09-drift-runbook-canonical-tf-invocation-and-fresh-plan.md`;
   `--name-transformer tf-var` is required or ~13 variables fail to resolve).

### Phase 3 — plan review of the apply

9. Run `terraform plan` and confirm it shows **exactly one resource to add** and
   **zero to change or destroy**. A `-target`-scoped apply is transitive on dependencies;
   confirm no `hcloud_server`/volume or other excluded resource is dragged in.

## Files to Edit

- `.github/workflows/apply-web-platform-infra.yml` — add the new resource to `-target=`.
- Any guard suite asserting on the `-target=` list (enumerate via the Phase 2 step 5 grep).

## Files to Create

- `apps/web-platform/infra/seo-config-rules.tf` — the Configuration Rule.
- `apps/web-platform/test/seo-config-rules.test.ts` — the source guard.

**Explicitly NOT edited:**

- `plugins/soleur/docs/robots.txt` — no `Disallow: /cdn-cgi/`. See
  [Option B rejection](#option-b-rejected--was-v1s-choice).
- `plugins/soleur/skills/seo-aeo/scripts/validate-seo.sh` — a **distributed plugin skill**
  shipped to Soleur users and referenced by `.openhands/skills/seo-aeo-analyst/SKILL.md`
  and two Inngest cron prompts (all three references verified). A Cloudflare-specific
  hard FAIL there would break consumer sites not behind Cloudflare.
- `plugins/soleur/docs/pages/*.njk` — the `mailto:` sources are correct as written; the
  rendering defect is fixed by removing the edge rewrite, not by editing source.
- `apps/web-platform/infra/cloudflare-settings.tf` — zone-wide change rejected (Option A).

## Acceptance Criteria

### Pre-merge (PR)

1. `apps/web-platform/test/seo-config-rules.test.ts` passes and asserts: the
   `http_config_settings` phase, `set_config` + `email_obfuscation = false`, **both**
   marketing hosts present, and `app.`/`deploy.`/`api.` **absent** from the expression.
2. The gate is **capable of failing**: flipping `email_obfuscation` to `true`, or adding
   `app.soleur.ai` to the expression, makes the test fail. (Guards against a
   structurally-unfailable gate — cf. commit `7f84318dc`.)
3. `cd apps/web-platform && npm run test:ci` passes in full — in particular the 3 existing
   `api.soleur.ai` tests in `test/seo-rulesets-noindex.test.ts` are untouched and green.
4. `terraform validate` passes and `terraform plan` reports **1 to add, 0 to change,
   0 to destroy**, with no excluded resource (`hcloud_server.web`, volumes, SSH keys)
   appearing in the plan.
5. The new resource address appears in the `-target=` allow-list in
   `apply-web-platform-infra.yml`, and every guard suite asserting on that list was
   updated (`git grep -ln 'cloudflare_ruleset\|\-target=' scripts/ apps/web-platform/infra/*.test.sh`
   returns no un-updated hit).
6. `git diff --name-only origin/main...HEAD` contains **no** `plugins/soleur/docs/robots.txt`
   — confirming the rejected Option B did not leak back in.
7. PR body uses `Ref #3379`, **not** `Closes`.

### Post-merge (operator)

8. `apply-web-platform-infra.yml` succeeded for the merge SHA:
   `gh run list --workflow=apply-web-platform-infra.yml --branch=main --limit=1 --json conclusion,headSha`
9. **The rule is live — the load-bearing check.** The whole plan rests on Cloudflare
   actually honouring a `set_config` rule for this feature, which cannot be proven from
   source. Assert the hrefs are gone from served HTML:

   ```bash
   UA="Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)"
   for p in "" "getting-started/" "pricing/" "legal/privacy-policy/" "legal/terms-and-conditions/"; do
     n=$(curl -sS -H 'Cache-Control: no-cache' -A "$UA" "https://soleur.ai/$p" \
          | grep -o 'cdn-cgi/l/email-protection' | wc -l | tr -d ' ')
     echo "/$p -> $n"
   done
   ```

   **Every count must be 0** (baseline before the change: 0, 2, 1, 20, 7). Use `grep -o …
   | wc -l`, never `grep -c` — see [Sharp Edges](#sharp-edges). Allow for Cloudflare
   propagation; retry for a few minutes before concluding failure.

10. **The addresses render correctly again** (the side-effect fix):
    `curl -sS https://soleur.ai/getting-started/ | grep -c 'ops@jikigai.com'` returns ≥1,
    and `grep -c '\[email&#160;protected\]'` returns 0.

11. **GSC re-validation.** *Precondition:* step 9 shows 0 across all pages.

    *Action:* GSC → **Page indexing → "Not found (404)" → Validate Fix.**

    *Post-condition:* validation state reads "Validation passed", or the two `/cdn-cgi/`
    rows leave the report. Google's validation runs take **up to 28 days**.

    Because the hrefs no longer exist, Google recrawls the linking pages, finds no
    references, and retires the URLs — the mechanism Google's own 404 guidance describes
    for URLs that should simply cease to be discovered. This is a materially stronger
    position than v1's robots.txt approach, which would have left 30 live links pointing
    at an uncrawlable URL.

    *`Automation: not feasible because` Google Search Console exposes no public API for
    triggering a coverage-issue validation run or reading its state — the Search Console
    API covers Search Analytics, sitemaps, and URL Inspection only. Genuine human-only
    step; do not re-litigate automating it.*

12. **Feedback loop.** `/work` files a follow-up issue due 28 days post-merge to re-check
    the "Not found (404)" report and confirm all four rows cleared. (A
    `scripts/followthroughs/` probe cannot serve here — it would need to read GSC, which
    has no API. But note the *step 9* census **is** automatable and would make a fine
    followthrough probe if recurrence is a concern.)

## Rollback

**Trigger:** unexpected breakage on the marketing hosts after apply — most plausibly an
unrelated Configuration Rule side effect, since `http_config_settings` is a phase this zone
has not used before.

**Mechanism:** `git revert` the commit; `apply-web-platform-infra.yml` re-applies on merge
to `main` and removes the ruleset. Effect is near-immediate at the edge (unlike a
robots.txt change, which Google would take ~24h+ to re-read — a further advantage of this
remedy over Option B).

**Residual after revert:** obfuscation returns, the `/cdn-cgi/` hrefs return, and the GSC
404 rows return. No data loss; the only cost is being back at the starting state.

## Risks & Mitigations

| Risk | Likelihood | Mitigation |
|---|---|---|
| **`http_config_settings` is a new phase for this zone** — Cloudflare allows only one user-defined ruleset per (zone, phase), and this zone has 5 rulesets across 5 *other* phases. An unexpected API rejection is possible. | Low | `terraform validate` + `terraform plan` in Phase 2/3 catch schema errors pre-merge; AC4 requires a clean 1-add plan. Provider support for all three attributes was verified against the pinned 4.52.7 docs, not assumed. |
| **The rule applies but Cloudflare does not actually stop rewriting** (config-derived expectation vs. real edge behavior). | Low | AC9 measures the outcome on 5 real pages rather than inferring it from config. This is the load-bearing check and is explicitly called out as such. |
| **Marketing-page email addresses become harvestable**, increasing spam on the DSAR channel (`legal@`) and the founder inbox (`ops@`). | Medium | Accepted, with rationale in [Decision](#option-c-chosen--host-scoped-configuration-rule). What is lost is XOR-trivial friction, not a control. Escalation if material: contact form or alias — **not** re-enabling obfuscation. |
| **`-target=` allow-list edit misses a guard suite**, leaving a suite red post-merge. | Medium | Phase 2 step 5 mandates the `git grep` sweep; AC5 asserts it. This class has bitten before (`2026-05-29-target-allowlist-extension-must-sweep-all-guard-suites.md`). |
| **`-target` is transitive on dependencies** and could drag an excluded resource (e.g. `hcloud_server.web`) into the apply. | Low | AC4 requires `terraform plan` to show exactly 1 add / 0 change / 0 destroy. The new ruleset depends only on `var.cf_zone_id`. |

## Observability

```yaml
liveness_signal:
  what: "Served marketing HTML contains zero occurrences of cdn-cgi/l/email-protection across the 5 known pages"
  cadence: "post-merge operator check (AC9); CI asserts the Terraform source on every PR"
  alert_target: "GitHub Actions job failure annotation; apply-web-platform-infra.yml run status"
  configured_in: "apps/web-platform/test/seo-config-rules.test.ts (source) + .github/workflows/apply-web-platform-infra.yml (apply)"

error_reporting:
  destination: "GitHub Actions job failure; terraform apply errors surface in the workflow run log"
  fail_loud: true

failure_modes:
  - mode: "Terraform rule present in source but never applied (omitted from the -target allow-list)"
    detection: "seo-config-rules.test.ts asserts the resource address appears in apply-web-platform-infra.yml"
    alert_route: "CI fails on the PR -> merge blocked"
  - mode: "Rule applied but Cloudflare still rewrites (edge behavior differs from config)"
    detection: "AC9 per-page occurrence census as Googlebot UA"
    alert_route: "operator observes non-zero counts; revert path in Rollback"
  - mode: "Rule scope widened to app./deploy./api. hosts, disabling obfuscation where it is still wanted"
    detection: "seo-config-rules.test.ts negative assertions on the expression"
    alert_route: "CI fails on the PR"

logs:
  where: "GitHub Actions run logs (vitest output; terraform plan/apply output)"
  retention: "90 days"

discoverability_test:
  command: "curl -sS -A 'Googlebot' https://soleur.ai/legal/privacy-policy/ | grep -o 'cdn-cgi/l/email-protection' | wc -l"
  expected_output: "0"
```

No SSH in any verification path.

## Infrastructure (IaC)

### Terraform changes

- **New:** `apps/web-platform/infra/seo-config-rules.tf` — one `cloudflare_ruleset`
  (`http_config_settings` phase, `set_config` action, `email_obfuscation = false`),
  host-scoped to `soleur.ai` + `www.soleur.ai`.
- **Provider:** `cloudflare/cloudflare` pinned at **4.52.7**
  (`apps/web-platform/infra/.terraform.lock.hcl`, constraint `~> 4.0`). All three required
  schema elements verified present in the v4 docs. Reuses the existing
  `cloudflare.rulesets` provider alias and `var.cf_zone_id`.
- **No new variables**, so no Doppler provisioning and no operator mint is required — the
  `hr-tf-variable-no-operator-mint-default` sequencing hazard does not apply here.

### Apply path

Merge-triggered auto-apply via `.github/workflows/apply-web-platform-infra.yml` (fires on
push to `main` touching `apps/web-platform/infra/**`), scoped by the `-target=` allow-list
which this PR extends. **Expected downtime: none** — adding a Configuration Rule is a
metadata change at the edge; no origin, DNS, or serving resource is touched.

### Distinctness / drift safeguards

Zone-scoped to the production `soleur.ai` zone via `var.cf_zone_id`; there is no dev
counterpart zone, so no `dev != prd` precondition applies. The rule is fully declarative
with no `lifecycle.ignore_changes` and no secret values, so nothing sensitive lands in
`terraform.tfstate`.

### Vendor-tier reality check

Configuration Rules are available on all Cloudflare plans including Free (rule-count
quotas differ by plan). This zone currently uses 5 rulesets across other phases and adds
its first `http_config_settings` ruleset with a single rule — comfortably inside any tier
quota. No paid-tier gate needed.

## Architecture Decision (ADR/C4)

**No ADR.** Disabling a vendor content-rewriting feature for two hostnames changes no
ownership/tenancy boundary, substrate, integration pattern, or trust boundary, and reverses
no existing ADR. It extends the established `cloudflare_ruleset`-in-Terraform pattern
already set by `seo-rulesets.tf` rather than introducing a new one.

**C4:** the external actors (Googlebot, Cloudflare, GitHub Pages) and their relationships
are unchanged — this removes an edge *transformation*, adding no element, container, data
store, or access relationship. No `.c4` edit in scope.

*Recorded dissent:* architecture-strategist argued for an ADR on the grounds that the PR
sets a precedent about edge-injected artifacts leaking into the crawl graph. With the
decision now reversed to "eliminate the surface", the precedent it sets is simply the
existing one from `2026-05-05-gsc-indexing-triage-patterns.md`, so an ADR is redundant.

## Domain Review

**Domains relevant:** Marketing (SEO), Engineering

- **Marketing (SEO):** correctly scoped as hygiene, **not** ranking recovery — Google
  states 404s do not harm ranking. The reversal to Option C additionally repairs a
  user-visible CTA/fallback rendering defect on the highest-intent page. Accepted cost is
  plaintext addresses; escalation if spam becomes material is a contact form, not
  re-enabling obfuscation.
- **Engineering:** blast radius bounded to two hostnames and one new declarative edge rule;
  no origin, DNS, or serving resource touched; no new variables or secrets. The main
  execution risk is the `-target=` allow-list guard-suite sweep, which has its own AC.

**Product/UX Gate:** not applicable — no UI-surface paths in Files to Edit/Create. The
`.njk` rendering defect is repaired without a source edit.

## GDPR / Compliance Gate

**Skipped** — no regulated-data surface: no schema, migration, auth flow, API route, or
`.sql` file; no new processing activity. Threshold `none`.

Noted: `legal@jikigai.com` (the DSAR intake channel) becomes plaintext on the legal pages.
This is a spam-volume consideration, not a compliance defect — the address is *intended* to
be publicly reachable, and Article 13/14 transparency obligations favour a contact point
being plainly readable. Obfuscation was arguably in mild tension with that.

## User-Brand Impact

**If this lands broken, the user experiences:** a misapplied Configuration Rule affecting
the marketing site's edge behavior. Because `http_config_settings` is a new phase for this
zone, the realistic failure is the rule not taking effect (no user-visible change,
`/cdn-cgi/` hrefs persist) rather than a serving outage. A mis-scoped expression would
disable obfuscation on hosts where it is still wanted — surfaced by AC1's negative
assertions before merge.

**If this leaks, the user's data / workflow / money is exposed via:** no user data is
touched. The deliberate, accepted exposure is that three *company* contact addresses
(`ops@`, `hello@`, `legal@jikigai.com`) become plaintext on public marketing pages,
increasing spam volume. No customer data, credential, or authenticated surface is involved.

**Brand-survival threshold:** `none`

*Justification:* files touched are `apps/[^/]+/infra/` — which **does** match the canonical
sensitive-path regex, so a scope-out is required: `threshold: none, reason:` the change adds
a single declarative Cloudflare edge rule affecting only public marketing-page HTML
rendering, touching no user data, credentials, auth flow, or serving infrastructure.

## Open questions for the operator

Recorded at
`knowledge-base/project/specs/feat-one-shot-gsc-404-cdn-cgi-email-protection/decision-challenges.md`
(rendered into the PR body and filed as an `action-required` issue by `/ship`).

## Open Code-Review Overlap

**None.** Planned paths checked against the 61 open `code-review` issues via
`gh issue list --json` piped through a standalone `jq --arg` contains-filter. Zero matches
for `apps/web-platform/infra/seo-rulesets.tf` and the new file paths.

## Sharp Edges

- **`grep -c` undercounts occurrences in minified HTML.** During verification
  `grep -c 'cdn-cgi/l/email-protection'` reported `1` where the page had **2** — `grep -c`
  counts matching *lines*, and served HTML puts both hrefs on one line. AC9's census uses
  `grep -o … | wc -l` for this reason.
- **`&&`-chained verification stops on a zero-match `grep`.** A chain in this session
  silently truncated when `grep -o` found nothing (exit 1). Append `|| true` or split
  commands. Especially relevant to AC9, whose *success* condition is a zero match.
- **`ugrep` rejects wide `.{0,N}` context patterns** with `exceeds complexity limits`. The
  host `grep` is `ugrep`; use `python3` slicing for context extraction on large
  single-line files.
- **Do not "fix" this with `Disallow: /cdn-cgi/`.** It is Cloudflare's generic advice and
  it is wrong here: Google explicitly says *"don't use robots.txt to block 404s"*, robots
  cannot de-index, and 30 internal links supply the precondition for
  "Indexed, though blocked by robots.txt" — the exact trap
  `2026-06-14-gsc-indexed-though-blocked-by-robots-is-a-real-misconfig-not-benign.md`
  documents on this same zone. **Vendor hygiene advice does not override the more specific
  vendor guidance for the situation you actually have.**
- **Do not disable Email Obfuscation zone-wide.** `cloudflare_zone_settings_override` is
  per-zone and is inside the auto-apply `-target=` list; scope with a Configuration Rule.
- **Do not add the check to `validate-seo.sh`.** It is a distributed plugin skill; a
  Cloudflare-specific hard FAIL there breaks consumer sites. It would also have turned the
  green 21-test `validate-seo.test.ts` suite red, since `setupSite()`'s default fixture
  (line 41) omits any `Disallow` and 8 tests assert exit 0 against it.
- **Extending a `-target=` allow-list requires sweeping every guard suite**, not just the
  workflow. Scope-guard suites are orphan suites exercised only by the full run.
- **`-target` is transitive on dependencies** — a new targeted resource referencing an
  excluded sibling can drag it into the apply. AC4 pins 1-add / 0-change / 0-destroy.
- **Do not add `X-Robots-Tag` or a `robots.txt` for `api.soleur.ai`.** Both are
  structurally inert on a DNS-only CNAME; a rule exists and is deliberately dormant. This
  surface has been examined three times (#3297 → #4575 → #3379); **#3379 is the single
  live tracker** — add findings there rather than creating a fourth artifact.
- **The `scripts/followthroughs/` sweeper closes issues on exit 0.** A draft of this plan
  proposed enrolling an `api.soleur.ai` probe against #3379; because the probe's asserted
  condition is *already true today*, the sweeper would have **closed #3379 on its first
  run**. Follow-through probes are *trigger detectors* (fire once, close the tracker), not
  *regression detectors*.
