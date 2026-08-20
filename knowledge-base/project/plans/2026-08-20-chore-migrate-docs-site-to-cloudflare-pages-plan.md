---
title: "Migrate the marketing/docs site off GitHub Pages to Cloudflare Pages (ADR-194)"
date: 2026-08-20
slug: chore-migrate-docs-site-to-cloudflare-pages
branch: feat-one-shot-7640-cloudflare-pages-migration
issue: 7640
closes: 7640
lane: cross-domain
type: chore
priority: p2-medium
domain: engineering
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# Migrate the marketing/docs site off GitHub Pages to Cloudflare Pages

## Enhancement Summary

**Deepened:** 2026-08-20. Eight review agents (terraform-architect, architecture-strategist,
spec-flow-analyzer, code-simplicity-reviewer, kieran, CTO, a strong-model advisor consult) plus
the deepen-plan halt gates. The plan was **restructured**, not annotated — four findings
falsified load-bearing choices in the first draft.

### What changed and why

1. **The www→apex mechanism was wrong.** The first draft put the 301 in a Pages `_redirects`
   file. Cloudflare documents domain-level redirects as **unsupported**, citing the exact
   shape proposed; the repo's own canonical-host build gate would have rejected the file's
   contents on every build; and the guard's chokepoint assertion would have landed outside
   `infra-validation.yml`'s path filter, so the guard would have passed by never running.
   Three independent failures behind one plausible line. Replaced with account Bulk Redirects
   — the mechanism Cloudflare's own www-redirect guide prescribes and one this repo already
   has wired.
2. **One merge could not produce the plan's own verification order.** `apply-web-platform-infra.yml`
   and `deploy-docs.yml` fire on the same push with no ordering edge, so the apex would point at
   a Pages project with zero deployments, or the deploy would read a secret Terraform had not
   yet created. Restructured into **three sequenced PRs, IaC first**.
3. **A deferred item could not be deferred.** `cron-gh-pages-cert-state` runs `cron: "0 3 * * *"`
   and its issue body instructs firing the reissue routine — which, post-cutover, de-proxies
   **www** and then **cannot restore it** (`restore` fails closed at `1/5` records). Disarmament
   is now an in-scope deliverable (D2); deletion stays deferred.
4. **The cutover is a gap, not a swap.** A removed resource and its replacement are unrelated
   graph nodes, so Terraform dispatches the deletes and the create concurrently — a coin flip
   between a clean apply and error `81053` on the live apex, with a recordless window that
   negative-caches for 1800 s. Gate 4.55 then forced the question the draft never asked: is the
   outage necessary at all? Probably not — **Hypothesis Z** (custom-domain attachment, not the
   record, selects the origin) is now the plan of record, with the two-pass apply demoted to a
   measured fallback.

### Also corrected

- `ci.yml` runs `lint-encryption-posture.py --repo-sweep`, which **fail-closes on unknown
  resource types**; neither Pages type is in the ledger. Adding `cf-pages.tf` would have
  reddened CI deterministically.
- The new apex record's Terraform address was never named — and `-target=cloudflare_record.github_pages`
  must be **retained**, or the destroy is never planned.
- Acceptance criteria that could not pass a correct implementation: `grep -c` exits 1 on zero
  matches; a bare `grep -c 'default'` returns 1 on a correct no-default variable; a bare
  action-name grep returns 2 because of a comment.
- A guard was a costume (no runner, two rows resolving to "a reviewer notices") — cut.
- A `_headers` file would have imposed a 4-hour deploy-staleness window on non-content-hashed
  filenames — cut; the cache-control change is now deliberate.
- Five monitors, not four: `soleur_changelog_deep` is the only deep-path apex monitor and
  guards exactly the Pages directory-index risk. `soleur_acme_probe` goes **vacuous**, not
  merely misdescribed.
- The apex carries live Protonmail `MX` and four `TXT` records that no criterion protected —
  a silent mail break invisible to every uptime monitor. Baseline captured; CUT9 added.
- The origin-provenance probe **failed open**, printing the success verdict for an unreachable
  site (an AP-021 violation). Hardened and verified across all four arms.
- `workflow_dispatch` structurally cannot carry `[ack-destroy]`, so the documented escape hatch
  cannot perform the rollback. The revert PR is now pre-opened.

### Confirmed as sound (probed, no change)

An apex CNAME **does** coexist with apex `MX`/`TXT` at Cloudflare — CNAME flattening is what
makes it legal, and the conflict set never includes `MX`/`TXT`. This was the highest-flagged
structural risk and it is not a risk; CUT9 still asserts it, because the failure would be silent.


## Overview

ADR-194 (accepted 2026-08-20, commit `2635b1c3a`) records that the docs-site hosting
arrangement holds two requirements that cannot both be satisfied: `domains.md` mandates
`proxied = true` for the HSTS preload commitment, and GitHub Pages refuses certificate
issuance or renewal for a proxied host (`is_https_eligible: false`). The origin
certificate therefore expires every ~90 days by construction and cannot self-heal.
Serving the same Eleventy build from Cloudflare Pages removes the origin certificate from
the picture entirely — there is no origin leg to validate — and the failure class stops
existing rather than being managed.

This plan delivers **the migration mechanism and the live DNS cutover**, sequenced as
three PRs on this branch's work item (see `## Delivery Sequencing`). Deletion of the
certificate-reissue subsystem, retirement of the ACME carve-out, and the return of the
zone to `ssl = "strict"` are **out of scope**. `ssl = "full"` in `seo-config-rules.tf`
stays in place throughout — it is what keeps the site up today, and it is also what makes
the rollback viable.

The build pipeline is untouched above the last three steps of `deploy-docs.yml`: Eleventy
and all six gates stay authoritative over what gets published.

**One deferred item is promoted into scope.** The certificate-reissue routine is retained
but must be **disarmed** in this work. Deletion and disarmament have different deadlines:
the hazard is *created* by the cutover, so it cannot be closed by a later PR. See
`## Design Decision D2`.

## Delivery Sequencing

`apply-web-platform-infra.yml` fires on merge to `main` touching
`apps/web-platform/infra/**` and runs **one** targeted apply. `deploy-docs.yml` fires on
the same push for its own path set. They have no ordering edge. A single PR carrying
`cf-pages.tf`, `deploy-docs.yml` and the `dns.tf` cutover therefore cannot produce the
verification order this plan asserts, and produces two guaranteed-bad interleavings:

- the apply finishes first → the apex points at a Pages project with **zero deployments**,
  and Cloudflare serves its own error page at `soleur.ai`;
- `deploy-docs.yml` starts first → it reads a GitHub Actions secret Terraform has not
  created yet, resolves it to empty, and fails on wrangler auth — with DNS already moved.

This is a technical fork, not an operator question, so it is decided here: **three
sequenced PRs, IaC first.** Scope is unchanged — the same work item still delivers the
mechanism and the cutover.

| PR | Contents | Fires | Gate before the next PR |
|---|---|---|---|
| **PR1 — substrate** | `cf-pages.tf` (project, apex domain, two `github_actions_secret`), `main.tf` alias, `variables.tf`, the www Bulk Redirect (`seo-bulk-redirects.tf`), the cert-reissue disarmament, `-target=` allow-list, guard rewrite, ADR/C4/docs. **No `dns.tf`, no `deploy-docs.yml`.** | apply-infra | PF1-PF4 |
| **PR2 — deploy path** | `deploy-docs.yml` only (terminal-step swap, build-identity stamp, post-deploy custom-domain probe, workflow rename, `environment:` removal) | deploy-docs | PF5-PF8 |
| **PR3 — cutover** | the `dns.tf` hunk **alone**, merged with `[ack-destroy]` | apply-infra | CUT0-CUT9 |

PR3 being a single-file, single-hunk commit is what makes the rollback a surgical
`git revert`. If `cf-pages.tf` and `dns.tf` shared a squashed commit, reverting would
destroy the Pages project along with the DNS record, leaving the apex pointed at nothing.

PR1 also touches `apps/web-platform/infra/sentry/cron-monitors.tf`, so its merge fires **two**
apply workflows: `apply-web-platform-infra.yml` and `apply-sentry-infra.yml`. They are separate
Terraform roots sharing no resource, so no ordering edge is required and neither interleaving is
bad. The sentry-root plan is an **update, 0 destroys** — `sentry-destroy-required` passes without
`[ack-destroy]`, and PR1's merge commit message must **not** carry `[skip-sentry-apply]`.

**PR1 must come first, not last.** Shipping the workflow before the substrate would swap
`deploy-docs.yml` away from GitHub Pages while GitHub Pages is still the live origin —
dark-shipping the docs site and reddening `main` on every docs push for the whole interval.

## Research Insights

### Premise Validation (Phase 0.6)

| Cited premise | Probe | Result |
|---|---|---|
| ADR-194 is accepted and merged | frontmatter + body + `git log --oneline -1 2635b1c3a` | **HOLDS** — `status: accepted`, commit on this branch |
| Issue #7640 open, targets this work | `gh issue view 7640 --json state,title,labels` | **HOLDS** — OPEN, `type/chore`, `priority/p2-medium` |
| Provider supports both Pages resources at the pin | `terraform providers schema -json`, `cloudflare/cloudflare 4.52.7` | **HOLDS** — schemas recorded below |
| `seo_page_redirects` is at the Free cap | 10 rules counted in the resource; Cloudflare availability table: Single Redirects Free = **10 rules per zone** | **HOLDS** — 10/10 |
| "Retiring the ACME carve-out frees the rule the www redirect needs" | Rule 10 read verbatim | **FALSE** — R1 |
| The www→apex 301 is GitHub-Pages-owned | `curl -sSI https://www.soleur.ai/` | **HOLDS** — `301`, `location: https://soleur.ai/`, carries `x-github-request-id` / `via: 1.1 varnish` / `x-fastly-request-id` |
| No `cloudflare_pages_*` resource or `wrangler` usage exists | repo sweep | **HOLDS** — greenfield |
| No `Pages:Edit`-scoped token exists | token ledger in `variables.tf` | **HOLDS** — six tokens, none Pages-scoped |
| Pages `_redirects` can express a www→apex redirect | Cloudflare `_redirects` docs | **FALSE** — R7, the decisive finding |
| `cloudflare_pages_domain` "manages no DNS" | provider schema exposes no DNS attributes | **UNSAFE INFERENCE** — R8 |

### Property List (Phase 0.6b)

- **P1** — the docs site serves over HTTPS at `soleur.ai` with no origin certificate that can expire.
- **P2** — `www.soleur.ai` keeps returning a host- and path-preserving `301` to `soleur.ai`.
- **P3** — every existing build gate stays authoritative over what reaches production.
- **P4** — an unmatched path returns HTTP `404` with the site's own 404 page.
- **P5** — response headers the site depends on are preserved, or the regression is measured and deliberate.
- **P6** — the cutover is reversible by a procedure written and rehearsed before it fires.
- **P7** — the existing uptime monitors keep passing without edits, including `sentry_uptime_monitor.soleur_changelog_deep` (`https://soleur.ai/changelog/`), the only deep-path apex monitor and the one that catches "root serves 200 but every other page 404s" — precisely the Pages directory-index risk profile.
- **P8** — the apex keeps resolving mail (MX) and verification (TXT) records unchanged.
- **P9** — no retained subsystem can mutate the post-cutover DNS topology in a way it cannot undo.

### Cut List (Phase 0.6b)

| Mechanism proposed | Property | Why it is cut |
|---|---|---|
| A rule for the www 301 **inside `seo_page_redirects`** | P2 | The zone phase is at 10/10 (Cloudflare's own availability table: Free = 10 rules/zone), one user-defined ruleset per `(zone, phase)`, and Rule 10 cannot be evicted. The account Bulk Redirects product already in this repo buys P2 on a separate quota. |
| Retire the ACME carve-out "to free the slot" | a free rule slot | The carve-out is an inline `and not (…)` **clause inside Rule 10's expression**, not a rule. Retiring it frees **zero** slots. |
| `_redirects` in the build artifact | P2 | **Impossible.** Cloudflare Pages documents "Domain-level redirects" as *unsupported*, with the exact shape proposed as the counter-example. It would also fail this repo's own canonical-host build gate (R7). |
| `_headers` for `Access-Control-Allow-Origin` / `X-Content-Type-Options` | P5 | Measured: Cloudflare Pages sets both by default, and the zone's `security_header { nosniff = true }` sets `nosniff` independently. |
| `_headers` for static-asset `Cache-Control` | P5 | Cut on measurement. `_site/css/style.css` is **not content-hashed** (`eleventy.config.js` is a straight directory passthrough), so restoring `max-age=14400` would impose a 4-hour deploy-staleness window on a site that redeploys on every merge. Pages' `must-revalidate` default is the better behaviour. P5 is satisfied by declaring the change deliberate, which it now is. |
| A new mechanism for `404.html` | P4 | Pages honours a root `404.html` natively; the existing `test -f _site/404.html` gate already asserts the artifact. |
| A standing "origin provenance" guard | P6 | It has no runner, no file and no CI job, and two of its four mutation rows resolve to "a human notices in review". The property is a one-shot *transition* property; it is kept as cutover assertion CUT2, and its durable half is already covered structurally by the DNS rows of Guard 1. |
| `platform.docsSite` C4 container + a deploy edge | model accuracy | The docs site was unmodelled before this change and the change does not make that silence false. Silence is not falsehood. Recorded in the C4 enumeration as checked-and-declined, and carried to the deferred issue. |
| A hand-held rollback patch file + a byte-identity rehearsal | P6 | `git revert` derives the same hunk mechanically and cannot drift; a held patch is a second source of truth for `dns.tf`. The byte-identity rehearsal tests `git apply`, not the rollback. Replaced by a rehearsal that tests the load-bearing premise instead (D3). |

### Measured empirical baseline (2026-08-20, `curl -sSI`)

| Header | `https://soleur.ai/` (GH Pages) | `/css/style.css` | Cloudflare Pages default | Verdict |
|---|---|---|---|---|
| `access-control-allow-origin` | `*` | `*` | `*` | preserved |
| `x-content-type-options` | `nosniff` | `nosniff` | `nosniff` | preserved (also zone-set) |
| `strict-transport-security` | `max-age=63072000; includeSubDomains; preload` | — | zone setting, not Pages | preserved — `cloudflare_zone_settings_override` is untouched |
| `referrer-policy` | absent | absent | `strict-origin-when-cross-origin` | added by Pages; improvement |
| `cache-control` (HTML) | `max-age=600` | — | `public, max-age=0, must-revalidate` | **deliberate change** (Cut List) |
| `cache-control` (assets) | — | `max-age=14400` | `public, max-age=0, must-revalidate` | **deliberate change** — faster deploy propagation on non-hashed filenames |
| `x-github-request-id`, `via: 1.1 varnish`, `x-fastly-request-id`, `x-served-by`, `x-proxy-cache` | present | present | absent | the cutover discriminator (CUT2) |

Apex mail/verification baseline, captured for P8 (`dig +short soleur.ai MX` / `TXT`):

```
MX:  10 mail.protonmail.ch.   20 mailsec.protonmail.ch.
TXT: "v=spf1 include:_spf.protonmail.ch ~all"
     "protonmail-verification=669dab6390579ccb6db592dca20dbd199bacce2d"
     "google-site-verification=zbo0JKaBz4mZwUq9sv_gXtmw5RmiN6dw_O8bqK2nq6s"
     "google-site-verification=HiasMKe0J0IzSe3nX2Ers0pYMAJ2vRvj6BxKEjJ1szk"
```

Note: two `google-site-verification` TXT values are live; `dns.tf` declares one. Pre-existing
drift, out of scope, recorded so the P8 comparison is not misread as caused by this change.

### Verified schemas — `cloudflare/cloudflare 4.52.7`

```
cloudflare_pages_project
  account_id         required
  name               required
  production_branch  required          <- required EVEN for direct upload
  subdomain          computed          <- "<name>.pages.dev"
  domains, created_on computed
  optional max-1 blocks: build_config, deployment_configs, source

cloudflare_pages_domain
  account_id, project_name, domain  required
  status                            computed

cloudflare_list -> item { value { redirect { … } } }
  source_url, target_url           required
  status_code, include_subdomains  optional
  subpath_matching                 optional   <- present at this pin
  preserve_path_suffix             optional   <- present at this pin
  preserve_query_string            optional

cloudflare_record
  name, type, zone_id  required
  content / value      optional+computed   (this repo uses `content`)
  proxied, ttl         optional
```

For a direct-upload project, omit the `source` block (it is the git integration) and still
set `production_branch = "main"`.

### Verified quotas (Cloudflare availability table)

- Single Redirects (zone `http_request_dynamic_redirect`): **Free = 10 rules per zone.** Confirms the cap.
- Bulk Redirects (account): **Free = 15 rules, 5 lists, 10,000 URL redirects across lists.**
  The repo uses 1 list (12 items) and 1 rule — ample headroom for a second list and a second rule.

### Verified Bulk Redirect parameter semantics

`subpath_matching` + `preserve_path_suffix` on source `www.soleur.ai/` → a request to
`www.soleur.ai/item` redirects to the target with `/item` appended. Scheme may be omitted,
in which case the redirect applies to both `http` and `https`. `include_subdomains` would
extend the match to hosts *left of* `www.soleur.ai` and is **not** wanted here.
**Matching precedence between two entries that could both match is undocumented** — which
is why D1 uses a separate list plus explicit rule ordering rather than relying on it.

### Verified CLI form — `wrangler pages deploy` (measured 2026-08-20)

```
$ npx --yes wrangler@latest pages deploy --help
wrangler pages deploy [directory]
POSITIONALS  directory
OPTIONS      --project-name --branch --commit-hash --commit-message --commit-dirty
             --skip-caching --no-bundle --upload-source-maps
```

Published version at measurement time: `wrangler 4.124.0`. Auth via `CLOUDFLARE_API_TOKEN`
+ `CLOUDFLARE_ACCOUNT_ID`; permission **Account → Cloudflare Pages → Edit**.

<!-- verified: 2026-08-20 source: npx --yes wrangler@latest pages deploy --help -->

### Applicable institutional learnings and principles

| Source | Takeaway | Why it binds |
|---|---|---|
| ADR-130 | Same API family → widen; distinct API surface → mint narrow. Zone→account escalation must be stated. | The Pages token decision |
| ADR-136 | A `kind = "zone"`/`"root"` ruleset owns its phase entrypoint as a whole-list replacement | No new phase is introduced; the account `http_request_redirect` entrypoint is already Terraform-owned, so the create-from-absent discriminator does not match |
| AP-019 (principles register) | The cert-reissue routine's off-Terraform mutation is sanctioned **because** it is "transient, self-reverting, single-attempt, human-gated" | The self-reverting clause becomes provably false post-cutover — D2 |
| AP-021 (CI-enforced) | A verdict must never collapse "could not check" into a definite answer | The origin-provenance probe must emit a third `UNREACHABLE` verdict |
| AP-023 (CI-enforced) | An anti-vacuity floor reports with `printf >&2` + `exit 1`, and the case counter increments **at the call site**, never inside both verdict helpers | The guard being rewritten has exactly the banned shape today |
| `2026-04-03-cloudflare-dns-at-symbol-causes-terraform-drift.md` | Never `name = "@"` at the apex | The apex CNAME |
| `2026-03-20-cloudflare-terraform-v4-v5-resource-names.md` | v4 block syntax; registry `latest` shows v5 | All new HCL |
| `2026-05-29-target-allowlist-extension-must-sweep-all-guard-suites.md` | A `-target=` allow-list is asserted on by several artifacts | Applied — but see R9: the two suites first assumed cannot see these resource types |
| `domains.md` §HSTS Preload Commitment | New Terraform records must be `proxied = true` | Both new records are proxied |

### CI-verification gate (#2566)

Every prescribed CLI invocation is verified: `wrangler pages deploy` by live `--help`;
the provider schemas by `terraform providers schema -json` at the pin; the header and DNS
baselines by live `curl`/`dig`; the origin-provenance probe by execution across all four
arms (below). No invocation is carried from memory.

## Research Reconciliation — Spec vs. Codebase

| Claim | Reality | Plan response |
|---|---|---|
| **R1.** "Retiring the ACME carve-out frees exactly the rule the www redirect needs." | The carve-out is an inline `and not (…)` clause **inside Rule 10's expression**. Retiring it frees zero rules. Only deleting Rule 10 frees a slot, which requires re-enabling zone `always_use_https` — the deferred cleanup. | D1 rebuilds the 301 outside that ruleset. ADR-194 is amended to correct its own reasoning. |
| **R2.** `dns.tf`: "There is no `cloudflare_page_rule` / `cloudflare_list` / `http_request_redirect` resource anywhere in this repo." | **Stale since 2026-06-09.** `seo-bulk-redirects.tf` declares `cloudflare_list.legal_redirects` (12 items, 10 of them legacy legal paths) and `cloudflare_ruleset.bulk_redirects` (`kind = "root"`, `http_request_redirect`, account-scoped). | The comment is rewritten to enumerate **all three** redirect substrates and which is authoritative for what — a comment naming one substrate rots the same way this one did. |
| **R5.** `sentry_uptime_monitor.soleur_www` keeps working unchanged. | Confirmed — asserts `301` on a URL that does not move. `soleur_acme_probe` also still holds (Pages serves `404.html` at 404), but it becomes **vacuous**, not merely misdescribed: its stated property is "ACME carve-out regression detector" for Rule 10, and today the 404 comes from a passthrough to the GitHub Pages origin. Post-cutover the 404 comes from Cloudflare Pages' own `404.html` regardless of Rule 10's state, so the assertion is a permanent pass with zero coupling to the thing it guards — while Rule 10 and its carve-out are explicitly retained in scope. | Monitors unedited; the `soleur_acme_probe` description is corrected (comment-only), and **the loss of its property is recorded against the deferred-cleanup issue** — a guard losing its property is a different finding from a stale description. |
| **R6.** The DNS change is destructive. | Four apex `A` records collapse to one apex `CNAME`; `name`/`type` are ForceNew → **4 deletes + 1 create**, plus an **in-place update** of www (`content` is not ForceNew). `destroy_count > 0` fails the apply without `[ack-destroy]`. | PF/CUT assertions; PR3 carries the ack. |
| **R7.** "`_redirects` can host the www→apex 301." | **False, three ways.** (a) Cloudflare documents "Domain-level redirects" as *unsupported*, citing the exact shape. (b) The repo's own canonical-host build gate greps `_site/` recursively for `https://www\.soleur\.ai($\|[^a-zA-Z0-9.-])` — the `_redirects` line matches, failing every build. (c) A hostless source would match the apex too and loop. | Option A is removed entirely, not held as a fallback. D1 selects Bulk Redirects. |
| **R8.** "`cloudflare_pages_domain` manages no DNS." | The claim is **true for the Terraform path**, but an earlier draft proved it from the *provider schema* — a schema exposing no DNS attribute shows the resource has no DNS field, not that the API has no side effect. The correct citation is the provider documentation at the pin: *"A DNS record for the domain is not automatically created. You need to create a `cloudflare_record` resource for the domain you want to use."* The **dashboard** flow does auto-create (*"the CNAME record will be added automatically after you confirm your DNS record"*), so the two paths genuinely differ. | Claim retained, citation corrected to the provider docs. PF3 keeps a cheap confirmation probe — had the claim been false, the failure would have arrived as error `81053` from a direction nobody was watching. |
| **R9.** "`terraform-target-parity.test.ts` and `test-destroy-guard-counter-web-platform.sh` are the orphan suites to sweep." | Neither can see a `cloudflare_pages_*` resource. The parity test's predicate is a `terraform_data` resource with **both** an SSH `connection` block and a `provisioner` block, and it self-documents as one-directional. The destroy-guard counter's five nested-block clauses cover other `cloudflare_*` types; Pages resources have no nested-block surface. | AC14 becomes a **direct grep** of the `-target=` lines. Delegating to suites that structurally cannot see the resources would have passed vacuously. |
| **R10.** The canonicalizer guard's CI registration. | Found: `.github/workflows/infra-validation.yml`, step `Run www-apex-canonicalizer drift-guard`, in `deploy-script-tests` (no `needs:`, no `if:`). Its `pull_request: paths` includes `apps/*/infra/**`. | Under D1 every rewritten assertion lives under `apps/web-platform/infra/**`, so the guard's trigger already covers them. Had the `_redirects` design survived, the chokepoint assertion would have sat in `eleventy.config.js`, outside the filter — the guard would have passed by never running. A fourth reason Option A was wrong. |

## Open Code-Review Overlap

Checked 2026-08-20 against 64 open `code-review` issues, matching every path in
`## Files to Edit` / `## Files to Create`. **None.**

## User-Brand Impact

**If this lands broken, the user experiences:** `https://soleur.ai` serving a Cloudflare
error page, a Pages "no deployment" page, a stale build, or NXDOMAIN — the public
marketing and documentation site, the only surface a prospective user meets before signing
up, dark or wrong. The 2026-08-16 precedent (#6691) was an ~8h15m apex outage from the same
host. Because `soleur.ai` is HSTS-preloaded, a broken apex cannot even fall back to HTTP.

**A second, quieter blast radius:** the apex also carries the company's Protonmail `MX` and
four `TXT` records. The A→CNAME transition touches that name. A silent mail break would be
invisible to every uptime monitor. P8/CUT9 exist for this.

**If this leaks, the user's workflow is exposed via:** a Cloudflare API token scoped to
`Account → Cloudflare Pages → Edit` reaching CI. That token is a **site-content replacement
primitive** — whoever holds it can publish arbitrary content at `soleur.ai` under the real
domain and the real certificate. It is minted narrow (Pages only; no DNS, no rulesets, no
zone settings), never echoed, and reaches the workflow auto-masked. `deploy-docs.yml`
triggers on `push: [main]`, `workflow_run` and `workflow_dispatch` — **no `pull_request`**,
so there is no fork exposure. That absence is load-bearing and is recorded in the scope
ledger so a later author does not add one.

**Brand-survival threshold:** `single-user incident`

`requires_cpo_signoff: true`. CPO sign-off is required at plan time before `/work` begins —
carried by the Phase 2.5 assessment. `user-impact-reviewer` is invoked at review time.

## Design Decision D1 — where the www→apex 301 lives

The ARGUMENTS asked whether the www redirect can be added within the Free cap **without**
retiring the ACME carve-out. **It can — but not inside `seo_page_redirects`.**

**Why not there:** the ruleset holds exactly 10 rules (9 SEO 301s + Rule 10, the HTTPS
catch-all) against a documented Free cap of 10 for `http_request_dynamic_redirect`, and
Cloudflare permits one user-defined ruleset per `(zone, phase)`. Rule 10 upgrades **every
proxied host in the zone** to HTTPS, protecting cross-subdomain credentials on
`app.soleur.ai` and `deploy.soleur.ai` (caught by `user-impact-reviewer` in PR #3974); it
cannot be evicted. Consolidating rules 1-8 needs `regex_replace()` / `substring()`, which
are Business-tier. And the carve-out is not a rule, so retiring it frees nothing (R1).

**Chosen: Cloudflare Bulk Redirects**, which is also what Cloudflare's own www-redirect
guide prescribes for a Pages project. It is a separate product on a different phase
(`http_request_redirect`, account-level) with its own quota, already wired in this repo,
with the token scope already granted post-#5092.

**The www DNS shape — a deliberate divergence from Cloudflare's own recipe.** Cloudflare's
guide points www at `192.0.2.1` (RFC 5737 TEST-NET-1, a black hole) and leaves it off the
Pages project, so the Bulk Redirect is the only thing that can answer. This plan instead
**keeps `www.soleur.ai` attached to the Pages project as a second custom domain**, with the
Bulk Redirect in front of it. Cloudflare documents the precedence that makes this work:
*"In case of duplicates, Bulk Redirects will run in front of your Pages project."*

The two designs differ only in their **failure mode**, and that is the whole reason for the
divergence:

| If the redirect ever stops firing | `192.0.2.1` (CF's recipe) | attached to the project (chosen) |
|---|---|---|
| What www serves | Cloudflare 522 — a hard, user-visible edge error | the site itself — duplicate content |
| Detection | `sentry_uptime_monitor.soleur_www` (asserts `301`) | the same monitor, equally |
| Severity | a broken host on an HSTS-preloaded domain | an SEO annoyance for one monitor interval |

Both are caught by the same monitor within one confirmation period, so detection is a wash —
and a 522 is strictly worse for a visitor than a second copy of the page. The
duplicate-content risk is also already covered a second time by the canonical-host build gate
and by the apex `<link rel="canonical">` the site emits.

Consequences of the chosen shape: `www` stays a proxied `CNAME` (so the change is an
**in-place update**, not a replace — this matters for the plan-shape assertion), it satisfies
the `domains.md` HSTS mandate, and Universal SSL's one-label wildcard `*.soleur.ai` covers it.

**Implementation — a separate list and a second, explicitly ordered rule:**

```hcl
resource "cloudflare_list" "www_canonical" {
  provider   = cloudflare.rulesets
  account_id = var.cf_account_id
  name       = "www_canonical"
  kind       = "redirect"
  item {
    value {
      redirect {
        source_url            = "www.soleur.ai/"   # scheme omitted -> matches http AND https
        target_url            = "https://soleur.ai/"
        status_code           = 301
        subpath_matching      = "enabled"
        preserve_path_suffix  = "enabled"
        preserve_query_string = "enabled"
        include_subdomains    = "disabled"  # would match hosts LEFT of www.soleur.ai; not wanted
      }
    }
  }
}
```

plus a **second** `rules { }` block in `cloudflare_ruleset.bulk_redirects`, declared
**after** the existing `legal_redirects` rule.

**Why a separate list rather than a 13th item in `legal_redirects`:** Cloudflare does not
document matching precedence between two list entries that could both match, and every
existing item carries `include_subdomains = "enabled"` — so `www.soleur.ai/pages/legal/
privacy-policy.html` already matches an apex item today. Adding a www catch-all to the same
list would make which entry wins depend on undocumented behaviour. Rules **within a
ruleset** evaluate in declaration order with first-match-wins, which this repo already
relies on and documents (`seo-rulesets.tf`: *"Positioned LAST so specific path rules above
match first and avoid double-redirect chains"*). Ordering the legal rule first and the www
rule second makes precedence explicit and testable. Free-tier headroom is ample (15 rules,
5 lists).

**T-WWW is a blocking pre-cutover check:** the ten legacy `/pages/legal/<slug>.html` paths
requested **on the www host** must still `301` to their `/legal/<slug>/` targets and not
collapse to the bare apex.

**Rejected: `_redirects` in the build artifact.** Cloudflare documents domain-level
redirects as unsupported and cites this exact shape; the repo's canonical-host build gate
would reject the file's contents on every build; and the guard's chokepoint assertion would
have landed in `eleventy.config.js`, outside `infra-validation.yml`'s path filter (R7, R10).

**What is NOT touched:** Rule 10, its ACME carve-out clause, `always_use_https = "off"`,
and `ssl = "full"`.

## Design Decision D2 — disarming the cert-reissue routine (promoted into scope)

Deleting the certificate-reissue subsystem is deferred. **Leaving it armed is not the same
decision**, and the hazard is created by this work, so it must be closed by this work.

**The mechanism, read from the source:**

- `cron-gh-pages-cert-reissue.ts` registers on `[{ event: "cron/gh-pages-cert-reissue.manual-trigger" }]`
  — event-only, reachable through the allowlisted `POST /api/internal/trigger-cron`.
- `cron-gh-pages-cert-state.ts` registers on `{ cron: "0 3 * * *" }` — **a live daily
  schedule**. Post-cutover the GitHub Pages certificate can never recover (it is
  DNS-detached by design), so it stays wedged permanently and this job files a `[cert-poll]`
  issue **every day, forever**, whose body reads *"cert wedged … ACME cannot self-heal this
  state; fire `cron/gh-pages-cert-reissue.manual-trigger`"*. It hands an autonomous agent a
  daily, authoritative instruction to run the routine below. Likelihood is not "low" — it is
  the retained system's designed steady-state output.
- Every precondition passes post-cutover: `assertStuckState` accepts `bad_authz`, and
  `checkReissuePreconditions` requires the ACME apex path to return `404`, which Cloudflare
  Pages does.
- `resolveProbeOnly` defaults to `true`, but **probe-only still performs the DNS flip** —
  `setRecordsProxied(deps, records, false)` runs unconditionally; only the cname toggle is skipped.
- `listToggleRecords()` queries exactly `[apex, "A"]` and `[www, "CNAME"]`. Post-cutover the
  apex is a CNAME, so the `type=A` query returns nothing — **the apex is untouched**, and
  the plan's original fear was misdirected. The **www** record is what gets `proxied = false`,
  dropping HSTS, Rule 10's HTTPS upgrade, WAF and bot management on a host `domains.md`
  mandates be proxied.
- **It cannot undo this.** `restoreStateInner` opens with
  `if (records.length < EXPECTED_TOGGLE_RECORDS)` where `EXPECTED_TOGGLE_RECORDS = 5`
  (4 apex A + 1 www CNAME). Post-cutover the read returns fewer, so it throws *"refusing to
  restore a subset"*, `retries: 1` exhausts, `onFailure` calls the same restore and throws
  again, and it pages `proxy_restore_failed`. The routine's own fail-loud safety guarantee is
  what makes the de-proxying **one-way**.

**In-scope deliverable (additive; no deletion):**

1. Add a **topology precondition** to `checkReissuePreconditions` that reads the live apex
   record type and returns a non-benign terminal outcome unless it is `A`. The routine then
   refuses to run against the post-cutover topology instead of half-running against it.
2. Disable the `cron` trigger on `cron-gh-pages-cert-state`, retaining its manual-trigger
   arm. This closes the self-escalating daily loop.
3. Record in the principles register that **AP-019's justification is void** until (1) lands:
   the "self-reverting to the Terraform-declared steady state" clause is provably false
   post-cutover.

4. Set `enabled = false` on `sentry_cron_monitor.scheduled_gh_pages_cert_state` in
   `apps/web-platform/infra/sentry/cron-monitors.tf`. Disarming the Inngest schedule (item 2)
   RELOCATES the daily-noise loop rather than closing it: that monitor carries
   `checkin_margin_minutes = 240` and `failure_issue_threshold = 1`, so with no check-ins it
   opens a missed-check-in issue every day from PR1's merge. `enabled = false` is an in-place
   update on the pinned provider (`jianyuan/sentry 0.15.4` exposes `enabled`, bool,
   optional+computed) — **0 destroys, so no `[ack-destroy]`, and the resource, its schedule and
   its margins stay in config as the re-arm recipe.** Deleting the block was considered and
   rejected: it spends the cutover PR's destroy gate on the substrate PR, breaks the code->IaC
   parity guard while the handler's manual-trigger arm still heartbeats, and makes re-arming a
   resource re-creation instead of the inverse of one boolean.

This is a phase step with files and acceptance criteria (AC25-AC27, AC27a-AC27e), not a
risk-table note.

## Design Decision D3 — rollback

Rollback is a revert of the **PR3** commit — one hunk, one file — merged with
`[ack-destroy]`. Three things make that real rather than aspirational:

1. **The revert PR is opened, green and mergeable *before* PR3 merges.** Under a
   `single-user incident` threshold the dominant cost is not authoring the revert, it is
   waiting out required CI on the revert PR. Pre-opening moves that wait from during the
   incident to before it, and rollback becomes one merge.
2. **`workflow_dispatch` cannot perform this rollback.** The destroy gate reads
   `HEAD_MSG: ${{ github.event.head_commit.message }}`; on a dispatch run
   `github.event.head_commit` is absent, `HEAD_MSG` is empty, and the
   `[ack-destroy]` regex cannot match. The reverting apply always has `destroy_count > 0`
   (it destroys the apex CNAME), so the documented manual escape hatch structurally cannot
   execute it. The merge path is the **only** path, and the runbook says so.
3. **The rehearsal tests the premise, not the patch.** Asserting that a reverse diff
   reproduces the original file tests `git`. The load-bearing, genuinely unverified claims
   are: (a) GitHub Pages **still serves** `soleur.ai` after being DNS-detached — nothing
   re-asserts the `CNAME` file to GitHub Pages after `deploy-docs.yml` stops deploying
   there, so the self-healing mechanism is gone; (b) a DNS-only revert is **sufficient** —
   `cloudflare_pages_domain.apex` remains attached to `soleur.ai` on the same account, and
   Pages custom-domain attachment establishes edge routing for that hostname, so the revert
   may also require destroying that resource. **(b) is measured in PR2 against a scratch
   custom domain on the same project, before the cutover** — it is the one item that could
   otherwise require re-derivation under pressure.

**Rollback content freezes.** GitHub Pages will serve the last pre-cutover build. A rollback
three weeks later serves three-week-old docs. Acceptable for an availability rollback;
stated so nobody is surprised.

**The rollback window depends on the deferred cleanup staying deferred** — specifically on
`ssl = "full"` remaining in place, because the GitHub Pages origin certificate is expired by
construction. This is added to the deferred issue's re-evaluation criteria.

## Design Decision D4 — ordering the apex swap (the gap, not the swap)

The apex transition is **not** a swap. `cloudflare_record.github_pages[*]` leaves the config
and `cloudflare_record.pages_apex` enters it. Those are unrelated graph nodes: no dependency
edge exists between them, and `depends_on` **cannot** create one, because it cannot reference
a resource that is no longer in the configuration. Terraform therefore dispatches the four
deletes and the one create **concurrently** at default parallelism. Two consequences, both
missing from an earlier draft of this plan:

1. **The create can lose the race and hard-fail the apply.** Cloudflare rejects a CNAME at a
   name that still carries `A` records — `An A, AAAA or CNAME record already exists with that
   host. (Code: 81053)`, HTTP 400. If the create is dispatched before all four deletes land,
   the apply dies mid-flight on the live public apex. A plan-*shape* assertion (PF9) cannot
   catch this: shape is not order.
2. **Between the last delete and the create, the apex carries no address record at all.** This
   is a gap, not a swap. Resolvers querying in that window get NODATA/NXDOMAIN and
   **negative-cache it against the zone SOA minimum (1800 s)** — an order of magnitude longer
   than the 300 s positive TTL a proxied record uses, and a harder user-visible failure than
   stale-but-working. "Both origins serve the same content during propagation" is only true
   for resolvers that never observe the gap.

**Chosen: a two-pass targeted apply inside one workflow run** — a destroy pass
(`-target=cloudflare_record.github_pages`) followed by a create pass
(`-target=cloudflare_record.pages_apex`). This bounds the recordless window to the latency of
two API calls rather than to Terraform's scheduler, and it is IaC-native: the repo already
carries this shape in `apply-web-platform-infra.yml`'s dedicated `apply_target=` dispatch jobs,
with a `confirm` typo-guard and an id-pin (the `workspaces-luks-recut` / `registry-luks-recut`
jobs are the template).

**`-target=cloudflare_record.github_pages` must be RETAINED in the allow-list, not removed.**
The instinct once the block leaves config is to delete the line as dead. Doing so means the
destroy is never planned: the four `A` records stay live and in state, and every subsequent
create attempt hits 81053 forever. Both the old and the new address must be present during
the cutover apply.

**PF-ORDER** is added to the pre-flight set: the cutover job asserts the destroy pass completed
(the four records are gone from state) **before** the create pass is dispatched.

## Downtime & Cutover

**Trigger.** The deploy/router class fires: the apex record swap takes the public serving
surface through a state where it has no address record. An earlier draft treated that window
as something to *bound* (D4's two-pass apply). This gate requires evaluating a **zero-downtime
path first**, and defaulting to it.

**The offline-inducing operation, precisely.** `cloudflare_record.github_pages[*]` (4 × `A`)
must be gone before `cloudflare_record.pages_apex` (`CNAME`) can exist — Cloudflare rejects a
CNAME at a name still carrying `A` records (error `81053`). Between the last delete and the
create, `soleur.ai` has no address record: resolvers get NODATA/NXDOMAIN and negative-cache it
against the zone SOA minimum (**1800 s**), six times the 300 s positive TTL a proxied record
uses. On an HSTS-preloaded domain there is no HTTP fallback. Affected surface: the public
marketing and documentation site, `single-user incident` threshold.

### Zero-downtime path — evaluated, and it is probably available

**Hypothesis Z.** For a hostname attached to a Pages project as a custom domain, Cloudflare's
edge routes by **Host header to the project**, and the DNS record's *content* is not what
selects the origin — the record only has to exist and be **proxied** so the edge terminates the
request. Two documented behaviours point this way: Cloudflare warns that pointing a CNAME at a
Pages site *without* first attaching the custom domain yields a **522** (i.e. attachment is what
establishes routing, and its absence is what breaks it), and Bulk Redirects are documented to
run *"in front of your Pages project"* for an attached hostname.

If Z holds, the cutover is **zero-downtime by construction and the record swap is not the
cutover at all**:

1. PR1 attaches `soleur.ai` as a Pages custom domain while the four `A` records still point at
   GitHub Pages. The record stays proxied throughout; nothing is deleted.
2. The apex begins serving from Pages at the moment of attachment — verified by CUT0
   (`version.txt` equals the deployed SHA) and CUT2 (no GitHub-origin headers).
3. The `A`→`CNAME` change becomes **cosmetic tidy-up** — correcting the record to express what
   is already true — and can be scheduled independently of the cutover, or deferred entirely.
4. Rollback is *detaching the custom domain*, which is faster than a revert PR and does not
   touch DNS at all.

**PF-Z (blocking, measured in PR1, before PR3 is written).** Attach the apex custom domain and,
without changing any DNS record, measure: does `https://soleur.ai/version.txt` return the
deployed SHA, and do the GitHub-origin headers disappear? This is a **reversible** probe — detach
restores the prior state — and it is measured on the real hostname, so it settles Z rather than
arguing it. PF7's detach measurement is the same experiment run backwards and the two share one
result.

### Residual-downtime path (fallback, only if PF-Z falsifies Z)

If attachment alone does **not** move the origin, the record swap is genuinely the cutover and
D4's two-pass targeted apply applies: destroy pass, assert the four records are gone, create
pass. That bounds the recordless window to the latency of two API calls rather than to
Terraform's scheduler.

**This path is accepted only with:** the bounded window stated (target: under 5 s between
passes), the cutover run inside a declared maintenance window at a low-traffic hour, the
pre-opened revert PR ready (PF8), and the CUT0-CUT9 verification set gating "done". It is a
**fallback**, not the plan of record — the plan of record is Z.

**Why this gate earned its place here:** the earlier draft had already chosen the residual-downtime
path and optimised it, without ever asking whether the outage was necessary. It probably is not.

## Token Decision — ADR-130 decision test applied

**Axis 1 — least privilege.** Cloudflare Pages is reached at `/accounts/<id>/pages/projects`,
not `/zones/<id>/rulesets`. Different resource class entirely. ADR-130 names this case:
*"Where the marginal capability … reaches a different resource class entirely (R2 object
storage, zone settings), mint the narrow alias instead."* Folding Pages:Edit into
`cf_api_token_rulesets` would attach a site-content replacement primitive to a token five
`.tf` files and the pre-apply entrypoint gate already consume.

**Axis 2 — the root-var hazard.** A new alias needs a new no-default root variable, and
Terraform resolves all root variables **before** `-target` pruning, so an unprovisioned
`TF_VAR_cf_api_token_pages` fails the *whole* merge-triggered apply. Real, and a sequencing
cost, not a reason to widen.

**Decision: MINT a narrow alias `cf_api_token_pages`** (Account → Cloudflare Pages → Edit,
that permission only). The zone→account escalation is stated explicitly per ADR-130's #5092
note: this token is account-scoped because Pages is an account-level product, and it carries
no zone permission of any kind. The retained-scope probe set does not apply — it is scoped to
`cf_api_token_rulesets`, and a mint mutates no existing token. The new token gets its own
first-use probe instead.

**Publication.** The value must reach `deploy-docs.yml`. Two in-repo patterns exist:
`github_actions_secret` (seven instances) and a Doppler CLI read (`tunnel.tf`). This plan
uses `github_actions_secret` for the token **and** for the account id, because the workflow
runs in the Playwright container and the alternative adds a Doppler install to it. Recorded
honestly: the cited `kb-drift.tf` precedent publishes a *Doppler service token* — a scoped,
independently revocable credential — whereas this publishes the terminal Cloudflare
credential itself. The consequence is that after this change the token exists in **three**
places (Doppler `prd_terraform`, `terraform.tfstate` on R2, GitHub Actions secrets), one
rotation. That fan-out is named in the scope ledger and in `## Encryption Posture`, and a
Doppler-service-token indirection is recorded on the deferred issue as the tighter shape.

**Expiry.** Mint with **no expiry**, and state that in the scope ledger. `event-cf-token-expiry-check`
covers `CF_API_TOKEN` only; a freshly minted token with an expiry and no monitor is a ~90-day
time bomb that reds every docs deploy.

**Naming.** Doppler `CF_API_TOKEN_PAGES` → `TF_VAR_cf_api_token_pages` → Actions
`CLOUDFLARE_API_TOKEN_PAGES` → workflow `env: CLOUDFLARE_API_TOKEN`. Only the last is forced
(by wrangler); the divergence is noted at both sites.

## Implementation Phases

### Phase 0 — Pre-flight (blocking)

1. **Provision the Pages token.** `/work` drives the Cloudflare dashboard through Playwright
   to mint a token named `Pages edit — soleur-docs`, scoped to Account → Cloudflare Pages →
   Edit and nothing else, **with no expiry**, then writes it to Doppler `soleur/prd_terraform`
   as `CF_API_TOKEN_PAGES`.

   ```
   automation-status: UNVERIFIED — /work MUST run a Playwright attempt and record
   `playwright-attempt: navigated <URL>; reached <named human gate>` before any handoff.
   An a-priori "console-gated" assertion is not acceptable evidence; a dashboard action under
   an authenticated session is presumptively automatable until an attempt proves a named human
   gate (CAPTCHA / OTP / TOTP / passkey / push-MFA / payment-card / hardware token).
   Precedent: #5480, where the same a-priori claim was falsified by one attempt.
   ```

2. **First-use scope probe** (this must run *after* step 1 — the existing `CF_API_TOKEN` is
   Tunnel/DNS-scoped and 403s on the Pages API):

   ```bash
   TOK=$(doppler secrets get CF_API_TOKEN_PAGES -p soleur -c prd_terraform --plain)
   ACCT=$(doppler secrets get CF_ACCOUNT_ID     -p soleur -c prd_terraform --plain)
   ZONE=$(doppler secrets get CF_ZONE_ID        -p soleur -c prd_terraform --plain)
   printf 'pages    -> '; curl -sS -o /dev/null -w '%{http_code}\n' --max-time 20 \
     -H "Authorization: Bearer $TOK" "https://api.cloudflare.com/client/v4/accounts/$ACCT/pages/projects"
   printf 'rulesets -> '; curl -sS -o /dev/null -w '%{http_code}\n' --max-time 20 \
     -H "Authorization: Bearer $TOK" "https://api.cloudflare.com/client/v4/zones/$ZONE/rulesets"
   ```

   Expected `pages -> 200`, `rulesets -> 403`. A `200` on the second line means the token is
   over-scoped and must be re-minted narrower.
3. **Assert the project name is free.** Using the token from step 1, `GET /accounts/$ACCT/pages/projects`
   must not list `soleur-docs`.
4. **Confirm the token resolves through Terraform** before PR1 merges: `TF_VAR_cf_api_token_pages`
   must be readable from `prd_terraform`. Until it is, PR1 cannot merge — an unprovisioned
   no-default root variable fails every apply on this root, not just this resource.
5. Baselines are already captured in Research Insights (headers, apex MX/TXT). Re-capture
   immediately before PR3 and record both in the PR body.

### Phase 1 — PR1: substrate

1. **`apps/web-platform/infra/cf-pages.tf`** (new):

   ```hcl
   resource "cloudflare_pages_project" "docs" {
     provider          = cloudflare.pages
     account_id        = var.cf_account_id
     name              = "soleur-docs"
     production_branch = "main"   # required by the v4 schema even for direct upload, and the
                                  # SOLE determinant of whether a deploy reaches the custom
                                  # domain or a preview alias. Must equal deploy-docs.yml's
                                  # --branch. Guard 1 M7 asserts the two agree.
     # No `source` block: `source` is the git integration. Omitting it is what makes this a
     # direct-upload project, which is what keeps the six gates authoritative.
   }

   resource "cloudflare_pages_domain" "apex" {
     provider     = cloudflare.pages
     account_id   = var.cf_account_id
     project_name = cloudflare_pages_project.docs.name
     domain       = "soleur.ai"
   }
   ```

   plus two `github_actions_secret` resources publishing `CLOUDFLARE_API_TOKEN_PAGES` and
   `CLOUDFLARE_ACCOUNT_ID_PAGES`, following the `kb-drift.tf` shape, each carrying a rotation-policy
   header comment.

   plus `cloudflare_pages_domain.www` for `www.soleur.ai`, per D1 — the Bulk Redirect runs in
   front of the project, and attaching www makes the redirect's failure mode duplicate content
   rather than a hard 522.
2. **`main.tf`**: a `cloudflare` provider alias `pages` bound to `var.cf_api_token_pages`,
   following the `r2` / `rulesets` alias shape, with a pointer to the scope ledger rather than
   a second enumeration.
3. **`variables.tf`**: declare `cf_api_token_pages`, `sensitive = true`, **no default**
   (`hr-tf-variable-no-operator-mint-default`). Its description is the scope ledger: the exact
   permission, no-expiry, the Doppler location, the three storage locations, the four names for
   one value, the consuming resources and workflow, the ADR-130 mint rationale, and the fact
   that `deploy-docs.yml` has no `pull_request` trigger.
4. **`seo-bulk-redirects.tf`**: add `cloudflare_list.www_canonical` and a second, explicitly
   ordered `rules { }` block per D1. Landing this **before** the DNS cutover is safe and
   deliberate: the Bulk Redirect matches on the `www.soleur.ai` host at the edge regardless of
   where www's DNS points, so it produces the same `301` the site already serves today. It is
   effectively a no-op until the cutover, and it means P2 is already live and measurable when
   PR3 fires.
5. **Cert-reissue disarmament** per D2: the apex-topology precondition, the `cron-gh-pages-cert-state`
   schedule removal, and the AP-019 status note in the principles register.
6. **`.github/workflows/apply-web-platform-infra.yml`**: extend the `-target=` allow-list with
   **all six** new addresses — `cloudflare_pages_project.docs`, `cloudflare_pages_domain.apex`,
   `cloudflare_pages_domain.www`, the two `github_actions_secret` addresses, and
   `cloudflare_list.www_canonical` — and in PR3, `cloudflare_record.pages_apex`. Every declared
   `github_actions_secret` in this root is individually target-listed today; an untargeted
   resource is silently never applied. **`-target=cloudflare_record.github_pages` stays** (D4):
   removing it once the block leaves config means the destroy is never planned.
7. **Rewrite `www-apex-canonicalizer.test.sh`** per Phase 4.
8. **Docs**: the ADR-194 amendment, the `domains.md` resolution note, the three C4 description
   corrections, the `soleur_acme_probe` description fix, and the deferred-cleanup issue.

**PR1 gates (PF1-PF4):**

| # | Assertion |
|---|---|
| PF1 | `terraform state list` shows `cloudflare_pages_project.docs` and `cloudflare_pages_domain.apex` |
| PF2 | Both `github_actions_secret` resources exist — `gh secret list` shows `CLOUDFLARE_API_TOKEN_PAGES` and `CLOUDFLARE_ACCOUNT_ID_PAGES` |
| PF3 | **R8 probe**: `GET /zones/$ZONE/dns_records?name=soleur.ai` shows **no new record** created by the custom-domain attachment. If Cloudflare auto-created one, the `dns.tf` design becomes an `import` rather than a create, and PR3 changes shape before it is written |
| PF4 | `curl -sSI https://www.soleur.ai/` still returns `301` to the apex — the Bulk Redirect landed without disturbing the live behaviour — **and** T-WWW passes on the ten legacy legal paths |

### Phase 2 — PR2: the deploy path

1. **`deploy-docs.yml`**: replace **only** the three terminal steps (`actions/configure-pages`,
   `actions/upload-pages-artifact`, `actions/deploy-pages`) with:

   ```yaml
   - name: Install wrangler (exact version, no floating tag)
     run: npm install --no-save wrangler@4.124.0
   - name: Deploy to Cloudflare Pages
     env:
       CLOUDFLARE_API_TOKEN: ${{ secrets.CLOUDFLARE_API_TOKEN_PAGES }}
       CLOUDFLARE_ACCOUNT_ID: ${{ secrets.CLOUDFLARE_ACCOUNT_ID_PAGES }}
     run: npx wrangler pages deploy _site --project-name=soleur-docs --branch=main
          --commit-hash="${GITHUB_SHA}" --commit-dirty=false
   ```

   The exact-version, `--no-save` form mirrors the step ~130 lines above it
   (`npm install --no-save playwright@1.60.0 http-server@14`) and its explicit
   "no `^`, no `~`, no floating tag" comment. `npx --yes wrangler@<major>` would re-resolve
   from npm at every deploy, outside the lockfile and invisible to dependency review, while
   holding a token that can replace every byte of `soleur.ai`.
2. **Build-identity stamp**: emit `_site/version.txt` containing `${GITHUB_SHA}` during the
   build, and add `test -f _site/version.txt` to the build-verification gate.
3. **Post-deploy custom-domain probe** (a new step, not one of the six gates): after the
   deploy, `curl https://soleur.ai/version.txt` and fail the job unless it equals
   `${GITHUB_SHA}`. This is the detector for the plan's highest-ranked risk — a deploy that
   lands on a preview alias leaves the custom domain serving the previous build while the
   workflow is green. Before PR3, this step runs in a reporting-only mode against
   `https://soleur-docs.pages.dev/version.txt`, since the apex is still GitHub Pages.
4. **Leftovers**: rename the workflow (it is `Deploy Documentation to GitHub Pages`); remove
   the `environment: { name: github-pages, url: ${{ steps.deployment.outputs.page_url }} }`
   block, whose `url` now resolves from a deleted step id and which gates the job on a
   `github-pages` environment it no longer deploys to; drop `permissions: pages: write` and
   `id-token: write`; keep `contents: read`, the `concurrency` group and the monitor
   pause/resume block.
5. **`_site/CNAME` and `_site/.nojekyll` become publicly served static files** on Pages
   (GitHub Pages consumed them). Harmless; recorded in the runbook so `https://soleur.ai/CNAME`
   is not later mistaken for a leak. `CNAME` stays in the build because it is part of the
   GitHub Pages configuration retained for rollback.
6. **Create the cutover runbook**, `knowledge-base/engineering/operations/runbooks/cloudflare-pages-cutover.md`:
   pre-flight set, cutover verification, the rollback path, the `[ack-destroy]`-on-the-merge-commit
   mechanics, and the fact that `workflow_dispatch` cannot perform the rollback (D3). It also
   carries **content rollback** — how to roll back a bad docs build now that re-running a
   previous green workflow run is no longer the mechanism. Verify the
   `wrangler pages deployment` subcommand shape at the pinned version before writing it; it was
   not in the `--help` capture.

**PR2 gates (PF5-PF8):**

| # | Assertion |
|---|---|
| PF5 | `https://soleur-docs.pages.dev/version.txt` equals the merge SHA — the build is live on the **production** branch of the project |
| PF6 | A nonexistent path on `*.pages.dev` returns `404`; `/` returns `200` |
| PF7 | **D3(b) probe**: attach a scratch custom domain to the project, then detach it, and observe whether edge routing for that hostname persists. This decides whether a DNS-only revert is sufficient or whether the rollback must also destroy `cloudflare_pages_domain.apex`. The runbook is written to match the measured answer |
| PF8 | The revert PR for PR3 is open, green and mergeable, with `[ack-destroy]` positioned to land in the squash message |

### Phase 3 — PR3: the DNS cutover

**Pre-flight: PF1-PF8 all hold, plus:**

| # | Assertion |
|---|---|
| PF9 | `terraform plan` shows exactly: 4 `cloudflare_record.github_pages[*]` deletes, 1 `cloudflare_record.pages_apex` create, 1 **in-place update** of `cloudflare_record.www` (`destroy_count` = 4, not 5) — and **zero** changes to `cloudflare_ruleset.seo_page_redirects`, `cloudflare_ruleset.seo_config_settings`, `cloudflare_zone_settings_override.soleur_ai`, or the apex MX/TXT records |
| PF10 | The merge commit message carries a line containing exactly `[ack-destroy]` |
| PF-ORDER | The cutover runs as **two targeted passes** (D4): the destroy pass completes and the four `cloudflare_record.github_pages[*]` records are gone from state **before** the `cloudflare_record.pages_apex` create pass is dispatched. Asserted on the sequence, not the counts — a shape assertion cannot see order, and an unordered apply can hit Cloudflare error `81053` mid-flight on the live apex |

**The change** — `apps/web-platform/infra/dns.tf`, and nothing else in this PR:

- Remove `cloudflare_record.github_pages` (the `for_each` over four GitHub Pages `A` IPs) and
  add **`cloudflare_record.pages_apex`** — the address is named here deliberately, because an
  unnamed address is one nobody adds to the `-target=` allow-list: `name = "soleur.ai"`
  (**never** `@`), `type = "CNAME"`,
  `content = cloudflare_pages_project.docs.subdomain` (a resource reference, not a literal),
  `proxied = true`, `ttl = 1`.
- Retarget `cloudflare_record.www`'s `content` to `cloudflare_pages_project.docs.subdomain`.
  `name` and `type` are unchanged, and `content` is **not** ForceNew, so this is an **in-place
  update**, not a replace.
- Leave `cloudflare_record.github_pages_challenge` (TXT) in place — part of the GitHub Pages
  configuration retained DNS-detached for rollback.
- Rewrite the contract comment to enumerate all three redirect substrates and name the new
  owner of the 301 (R2).
- **Both the old and new record addresses must be in the `-target=` allow-list during this
  apply**, or a targeted apply could create the CNAME without the four `A` deletes in scope —
  which Cloudflare rejects, since a CNAME cannot coexist with `A` records at the same name.

**Post-cutover verification — the site is not cut over until all hold.** Because the plan's
own propagation estimate is ~5 minutes of mixed resolution (proxied TTL is fixed at 300 s),
a single sample would legitimately fail on a healthy cutover. Each assertion is therefore
**3 consecutive clean samples at 60 s intervals, beginning 5 minutes after the apply**, with
transport failure reported as a distinct `UNREACHABLE` verdict rather than folded into either
answer (AP-021).

| # | Assertion |
|---|---|
| CUT0 | `https://soleur.ai/version.txt` equals the merge SHA — **binds the apex to the current build**. Closes preview-alias, stale-deployment, wrong-project and did-the-deploy-land in one predicate |
| CUT1 | `https://soleur.ai/` returns `200` |
| CUT2 | The response carries **none** of `x-github-request-id`, `x-github-edge-region`, `via: 1.1 varnish`, `x-fastly-request-id`, `x-served-by`, `x-proxy-cache`. `server: cloudflare` is deliberately not used — it is true before *and* after |
| CUT3 | `https://www.soleur.ai/` returns `301` to `https://soleur.ai/`, with no GitHub-origin header |
| CUT4 | `https://www.soleur.ai/agents/` returns `301` to `https://soleur.ai/agents/` — path preservation, not a bare-apex collapse |
| CUT5 | A nonexistent path returns `404` |
| CUT6 | `strict-transport-security: max-age=63072000; includeSubDomains; preload` still present |
| CUT7 | T-WWW: the ten legacy `/pages/legal/<slug>.html` paths on the **www** host still `301` to their `/legal/<slug>/` targets |
| CUT8 | All **five** monitors green through one full check interval: `soleur_apex`, `soleur_www`, `soleur_changelog_deep`, `soleur_acme_probe`, and `betteruptime_monitor.soleur_apex`. `soleur_changelog_deep` is load-bearing here — a trailing-slash directory-index regression on Pages would leave the root at 200 while every other page 404s |
| CUT9 | **`dig soleur.ai MX` and `dig soleur.ai TXT` return byte-identical sets to the Phase 0 baseline** — the apex A→CNAME transition did not disturb mail routing or domain verification |

**Decision point.** If CUT0-CUT9 are not all green by **T+20 minutes** from the apply, merge
the pre-opened revert PR. The decider is the engineer running the cutover; no further approval
is required, and rolling back is the default action on ambiguity. Do not debug forward on a
live public surface.

## Files to Edit

**PR1** — `scripts/encryption-posture-ledger.json`; `apps/web-platform/infra/main.tf`, `variables.tf`, `seo-bulk-redirects.tf`,
`www-apex-canonicalizer.test.sh`, `sentry/uptime-monitors.tf` (comment only);
`apps/web-platform/server/inngest/functions/cron-gh-pages-cert-reissue.ts`,
`cron-gh-pages-cert-state.ts`; `.github/workflows/apply-web-platform-infra.yml`;
`knowledge-base/engineering/architecture/decisions/ADR-194-migrate-marketing-docs-site-off-github-pages-to-cloudflare-pages.md`;
`knowledge-base/engineering/architecture/principles-register.md`;
`knowledge-base/operations/domains.md`;
`knowledge-base/engineering/architecture/diagrams/model.c4`

**PR2** — `.github/workflows/deploy-docs.yml`

**PR3** — `apps/web-platform/infra/dns.tf`

## Files to Create

- `apps/web-platform/infra/cf-pages.tf` (PR1)
- `knowledge-base/engineering/operations/runbooks/cloudflare-pages-cutover.md` (PR2)

**Not edited, deliberately:** `eleventy.config.js` and `views.c4`. Both were in an earlier
draft; the `_headers`/`_redirects` cut and the C4 container cut removed the need. Their absence
also removes two hazards — the `infra-validation.yml` path-filter gap (R10) and the #7332
both-endpoints-must-be-included rule.

**Glob verification:** every Files-to-Edit path was read or listed during research; the two
Files-to-Create paths do not exist.

## Acceptance Criteria

Verification commands are written exit-safe: `grep -c` **exits 1 on zero matches**, so a bare
`grep -c … returns 0` would abort under `set -e` rather than pass. Each count assertion below
uses `$(grep -c … || true)` compared with `[ "$n" = "0" ]`, or `! grep -q`.

### PR1

- **AC1** — `cf-pages.tf` declares `cloudflare_pages_project.docs` with `production_branch = "main"` and no `source` block: `! grep -q 'source {' apps/web-platform/infra/cf-pages.tf`.
- **AC2** — `terraform validate` passes in `apps/web-platform/infra/` (the catch for v4-vs-v5 schema drift and any `ExactlyOneOf` violation).
- **AC3** — two `cloudflare_pages_domain` resources are declared (apex and www): `grep -c 'resource "cloudflare_pages_domain"' apps/web-platform/infra/cf-pages.tf` equals `2`.
- **AC4** — `variables.tf` declares `cf_api_token_pages` with `sensitive = true` and no `default`. Anchor on the **assignment**, not the word: `awk '/variable "cf_api_token_pages"/,/^}/' apps/web-platform/infra/variables.tf | grep -cE '^\s*default\s*=' || true` equals `0`. A bare `grep -c 'default'` returns `1` on a correct implementation, because the repo's convention for this exact variable shape is a description ending *"No default (hr-tf-variable-no-operator-mint-default)"* — verified against the `cf_api_token_dns_edit` precedent.
- **AC5** — the `-target=` allow-list contains all six new addresses **and still contains `cloudflare_record.github_pages`** (D4). Asserted by a **direct grep of `.github/workflows/apply-web-platform-infra.yml`**, one assertion per address — not by delegating to `terraform-target-parity.test.ts` or `test-destroy-guard-counter-web-platform.sh`, neither of which can see a `cloudflare_pages_*` or `github_actions_secret` resource (R9). Both suites are still run, but as regression checks, not as evidence for this property.

  **AC5 addendum — 2026-08-20 (#7640), measured.** Each of the seven assertions MUST be
  LINE-ANCHORED, not a bare substring grep. Measured against the as-written workflow, the
  bare form `grep -c -- '-target=cloudflare_record.github_pages'` returns **2**, because
  `-target=cloudflare_record.github_pages_challenge` contains it as a prefix — so an AC5
  written as `[ "$(grep -c ...)" = 1 ]` FAILS on a correct file, and the natural "fix" is to
  loosen the assertion rather than anchor it. Use the terminated form, which returns 1:
  `grep -cE '^[[:space:]]+-target=cloudflare_record\.github_pages \\$' <workflow>`.
  This is not specific to that one address: `cloudflare_pages_project.docs` and
  `cloudflare_pages_domain.www` are prefix-vulnerable to any future sibling in exactly the
  same way, so all seven use the anchored form (`cq-assert-anchor-not-bare-token`).
- **AC6** — `seo-rulesets.tf` is unchanged: `git diff --stat origin/main -- apps/web-platform/infra/seo-rulesets.tf` is empty. Rule 10 and its ACME carve-out clause survive verbatim.
- **AC7** — `seo-config-rules.tf` still contains exactly one `ssl = "full"` Configuration Rule: `grep -c 'ssl *= *"full"' apps/web-platform/infra/seo-config-rules.tf` equals `1`. **Asserted at the resource level, not as an empty diff.** An empty-diff assertion would forbid correcting the rule's `REMOVAL CONDITION` comment, which instructs deleting the block once `gh api repos/jikig-ai/soleur/pages` reports an issued certificate — a condition the cutover makes permanently unsatisfiable, because DNS is detached and the certificate can never issue. Locking that comment in place is the same doc-rot this plan corrects elsewhere; the comment is updated and the rule is not.
- **AC8** — none of the deferred-deletion artifacts are removed. Per-path existence check, never an aggregate count:
  `apps/web-platform/server/inngest/functions/cron-gh-pages-cert-reissue.ts`,
  `apps/web-platform/server/inngest/functions/cron-gh-pages-cert-state.ts`,
  `apps/web-platform/server/cert-reissue-marker.ts` (note: `server/`, **not** `server/inngest/functions/`),
  `apps/web-platform/infra/cf-cert-reissue-token.tf`,
  `knowledge-base/engineering/operations/runbooks/gh-pages-cert-renewal.md`.
  The `CF_API_TOKEN_DNS_EDIT` secret and `doppler_secret.cf_api_token_dns_edit` are likewise untouched.
- **AC9** — `plugins/soleur/docs/CNAME` still exists and reads exactly `soleur.ai`.
- **AC10** — the rewritten `www-apex-canonicalizer.test.sh` exits `0` on the branch, and **each of Guard 1's mutation rows M1-M7 drives it to a non-zero exit**, and harness row H1 fails while H2 passes. (The row count is stated as the explicit range, not a bare number — an earlier draft said "three" against a six-row matrix, which would have let the guard ship with its chokepoint and vacuity rows unexercised.)
- **AC11** — the guard's anti-vacuity floor conforms to **AP-023**: it reports with `printf >&2` + `exit 1` rather than through the suite's own `fail`, and the case counter increments **at the call site**, not inside both verdict helpers. The current file has the banned shape (`TOTAL=$((TOTAL + 1))` inside both `pass()` and `fail()`), so this is a required change, not a preserved property. `scripts/guard-vacuity-floor.test.sh` passes.
- **AC12** — the Phase 0 token probe records `pages -> 200` and `rulesets -> 403`, and `TF_VAR_cf_api_token_pages` resolves from Doppler `prd_terraform`. Asserted by re-running the probe, not by the presence of text in a PR body.
- **AC13** — `terraform plan` shows zero changes to `seo_page_redirects`, `seo_config_settings`, `zone_settings_override`, and the apex MX/TXT records.
- **AC14** — ADR-194 carries the R1 correction in `## Decision` and names the considered options in `## Alternatives Considered`.
- **AC25** — `cron-gh-pages-cert-reissue.ts` refuses to run when the live apex record type is not `A`, asserted by a unit test that stubs the record read with a `CNAME` and expects the non-benign terminal outcome.
- **AC26** — `cron-gh-pages-cert-state.ts` no longer registers a `cron` trigger: `! grep -q 'cron: "0 3 \* \* \*"' apps/web-platform/server/inngest/functions/cron-gh-pages-cert-state.ts`, with the manual-trigger arm retained.
- **AC27** — the principles register records that AP-019's "self-reverting" justification is void until the topology precondition is live.
- **AC27a** — `sentry_cron_monitor.scheduled_gh_pages_cert_state` carries `enabled = false`, and the PR-time sentry-root plan reports **0 destroys** (`sentry-destroy-required` green with no `[ack-destroy]` on PR1).
- **AC27b** — the monitor's `schedule`, `checkin_margin_minutes`, `max_runtime_minutes` and both thresholds are unchanged from `main` (asserted by diff), so re-arming is a single-attribute flip.
- **AC27c** — `routine-metadata-parity.test.ts` is green: every `ROUTINE_METADATA.description` is <= 160 chars, including the disarmed cert-state entry.
- **AC27d** — `sentry-monitor-iac-parity.test.ts` is green **with no new `DISABLED_CRON_SLUG_EXEMPTIONS` entry** — the structural proof the monitor was disabled, not deleted.
- **AC27e** — `cron-inngest-cron-watchdog.ts`'s cadence comment no longer cites `scheduled-gh-pages-cert-state` as a live constraint, and names `scheduled-community-monitor @ 0 8 * * *` as the surviving AC10 basis.
- **AC28** — `scripts/encryption-posture-ledger.json` classifies both new resource types, and `python3 scripts/lint-encryption-posture.py --repo-sweep` exits `0`. The `cloudflare_pages_project` `stores[]` row carries a `provider-managed:<AttestationName>` mechanism with an `attestation_url` and a `retrieved_on` within 365 days — the validator rejects a bare "provider-managed encryption at rest" string.
- **AC29** — the cutover apply is expressed as two targeted passes with the sequence asserted between them (PF-ORDER), and `-target=cloudflare_record.github_pages` is still present in the allow-list.

### PR2

- **AC15** — `deploy-docs.yml` no longer **uses** the three GitHub Pages actions: `grep -cE '^\s*uses: actions/(configure-pages|upload-pages-artifact|deploy-pages)@' .github/workflows/deploy-docs.yml || true` equals `0`. Anchored on `uses: actions/`, not the bare names: the file also mentions all three in a container-config comment (*"Pages-deploy actions … work inside container jobs"*), so a bare-name grep returns `2` on a correct implementation. That comment is itself stale after the migration and is rewritten in the same step.
- **AC16** — the five build gates other than build-verification are byte-unchanged, and the build-verification step changes only by added `test -f` lines. Asserted mechanically: the diff hunks for `deploy-docs.yml` fall only within the terminal-steps range, the `permissions:` block, the `environment:` block, the workflow `name:`, and additive lines in build-verification. (An earlier draft claimed "the six gates are byte-unchanged" while also changing one of them — self-contradictory.)
- **AC17** — wrangler is pinned exactly: `grep -c 'wrangler@4\.124\.0' .github/workflows/deploy-docs.yml` equals `1`, and `grep -c 'wrangler@latest\|npx --yes wrangler' … || true` equals `0`.
- **AC18** — the `environment:` block is gone: `! grep -q 'github-pages' .github/workflows/deploy-docs.yml`.
- **AC19** — the post-deploy custom-domain probe step exists and fails the job on a SHA mismatch, exercised by a run where the expected SHA is deliberately wrong.
- **AC20** — `https://soleur-docs.pages.dev/version.txt` equals the merge SHA (PF5).
- **AC21** — the cutover runbook exists, states that `workflow_dispatch` cannot perform the rollback, records the PF7 detach measurement, and carries the content-rollback procedure.

### PR3 (cutover)

- **AC22** — CUT0 through CUT9 all hold under the 3-sample rule, recorded with measured output.
- **AC23** — a `workflow_dispatch` run of `deploy-docs.yml` publishes a change and `https://soleur.ai/version.txt` reflects the new SHA. (Asserted by an explicitly dispatched run, not by waiting on an unrelated future commit — `cq-ac-must-not-depend-on-concurrent-sessions`.)
- **AC24** — the deferred-cleanup issue exists and carries its re-evaluation criteria, including that `ssl = "full"` must remain in place while the rollback window is open.

Repo-wide: `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main` exits `0`
(the gate's own invocation, not a hand-enumerated path list), and
`apps/web-platform/test/c4-code-syntax.test.ts` + `c4-render.test.ts` pass.

## Domain Review

**Domains relevant:** Engineering, Marketing, Operations

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Risk concentrates in sequencing, and the three-PR split is what makes the
plan's own verification order physically achievable. The `production_branch` / `--branch`
coupling is the subtlest trap — two independent magic strings in HCL and YAML with no
compiler between them; Guard 1 M7 now covers it. The deferred cert-reissue subsystem was the
one item that becomes *actively dangerous* rather than merely stale at cutover, and it is now
an in-scope deliverable. `npx --yes wrangler@<major>` was the single unpinned vendor surface
in a workflow that publishes the public site, against a workflow that digest-pins its
container; it is now exact-pinned via the repo's own adjacent precedent.

### Marketing (CMO / SEO)

**Status:** reviewed
**Assessment:** Canonical direction stays apex, enforced by three independent mechanisms that
all survive: the Bulk Redirect 301, the canonical-host build gate, and
`sentry_uptime_monitor.soleur_www`. The SEO redirect corpus is untouched, so no indexed URL
changes shape. Path preservation on the www 301 is load-bearing (CUT4) — a bare collapse to
the apex would turn every indexed www deep link into the "Page with redirect" cluster in
Search Console. The static-asset `Cache-Control` change is now a deliberate accepted change
rather than a regression to reverse: because filenames are not content-hashed, Pages'
`must-revalidate` default propagates a docs fix immediately where GitHub Pages' 4-hour window
would not.

### Operations (COO)

**Status:** reviewed
**Assessment:** No new vendor and no new recurring cost. Cloudflare is already both vendor and
sub-processor; Pages Free is `$0` at 500 builds/month (direct-upload consumes none), 100 custom
domains, 20,000 files, 25 MiB per file. No expense-ledger entry required. The operational
surface shrinks by one certificate lifecycle. One new operational obligation is created and
named: the Pages token now exists in three places with a single rotation.

### Product/UX Gate

**Tier:** none
**Rationale:** the mechanical UI-surface override does not fire. No path in Files to
Edit/Create matches the glob superset in `ui-surface-terms.md` — no `.njk`, `.html`, `.tsx`,
`.vue`, `.svelte`, `.astro`, no `components/**`, no `app/**/page.tsx`. `404.njk` is verified,
not edited. The rendered site is byte-identical; only the host serving it changes. No wireframe
required.

### GDPR / Compliance (Phase 2.7)

**Assessment:** skipped with reason. The canonical regulated-data regex does not match — no
`.sql`, no `supabase/migrations/`, no auth flow, no API route. None of the four expansion
triggers fire: no new LLM/external-API processing of session-derived data; the
`single-user incident` threshold here is an availability threshold, not a personal-data one;
no new cron or workflow reads `learnings/` or `specs/`; no new artifact-distribution surface —
the docs site is already public. Recorded for completeness: visitor request logs move from
GitHub's edge to Cloudflare's; both are existing sub-processors under the current DPA set, so
no Article 30 entry and no DPA change is triggered. ADR-194 reaches the same conclusion
independently.

## Infrastructure (IaC)

### Terraform changes

| File | Change | Provider / alias | PR |
|---|---|---|---|
| `cf-pages.tf` (new) | `cloudflare_pages_project.docs`, `cloudflare_pages_domain.apex`, two `github_actions_secret` | `cloudflare.pages` (new), `github` | 1 |
| `main.tf` | `cloudflare` alias `pages` bound to `var.cf_api_token_pages` | — | 1 |
| `variables.tf` | `cf_api_token_pages` — sensitive, no default, description is the scope ledger | — | 1 |
| `seo-bulk-redirects.tf` | `cloudflare_list.www_canonical` + a second ordered rule | `cloudflare.rulesets` | 1 |
| `dns.tf` | apex `A`×4 → apex `CNAME` (`cloudflare_record.pages_apex`); www `content` retargeted to the Pages project, staying a proxied `CNAME` (**in-place update**, not a replace) | default `cloudflare` | 3 |

Provider pin unchanged: `cloudflare/cloudflare ~> 4.0` (4.52.7). All new HCL uses **v4 block
syntax**; registry `latest` documents v5 attribute-set syntax and must not be copied.
Terraform `>= 1.7`.

Sensitive variable `TF_VAR_cf_api_token_pages` from Doppler `soleur/prd_terraform` key
`CF_API_TOKEN_PAGES` via `--name-transformer tf-var`. No default, and Terraform resolves all
root variables before `-target` pruning, so it must be live before PR1 merges.

### Apply path

**Path (b): existing auto-applied root, extended.** `apply-web-platform-infra.yml` fires on
merge touching `apps/web-platform/infra/**` and applies against the `-target=` allow-list. No
new Terraform root, no new backend — R2 already exists in this root (`use_lockfile = false`;
the shared GitHub Actions concurrency group is the sole serializer).

Blast radius is concentrated in PR3: a **4-delete + 1-create + 1-in-place-update** plan on the public
apex. Expected exposure is the proxied-record propagation window (TTL fixed at 300 s), during
which both origins serve identical content because the GitHub Pages configuration is retained
and the Pages project is already live and verified. That overlap is the reason PR1/PR2 precede
PR3 rather than sharing a merge.

`destroy_count > 0` fails the apply without a `[ack-destroy]` line in the merge commit —
expected and correct. PF9 is what makes acking it safe, by pinning the exact plan shape first.

### Distinctness / drift safeguards

- `name = "soleur.ai"`, never `@` — the API normalizes `@` to FQDN and `name` is ForceNew.
- `content = cloudflare_pages_project.docs.subdomain` is a resource reference, so Terraform holds the edge.
- PF3 probes whether the custom-domain attachment auto-created a DNS record (R8); if it did, `dns.tf` becomes an `import`, not a create.
- No new ruleset phase, so ADR-136's pre-apply entrypoint gate is not newly engaged; the account `http_request_redirect` entrypoint is already Terraform-owned, so the create-from-absent discriminator does not match there either.
- The token value lands in `terraform.tfstate` (R2, encrypted at rest, credentials distinct from every Cloudflare API token in this root).
- `seo_page_redirects`, `seo_config_settings`, `zone_settings_override` and the apex MX/TXT records are asserted unchanged (AC6, AC7, AC13, CUT9).

### Encryption-posture ledger (a fail-closed CI gate this plan must satisfy)

`.github/workflows/ci.yml` runs `python3 scripts/lint-encryption-posture.py --repo-sweep`,
which scans `apps/*/infra/**/*.tf` for every `resource "<type>"` and partitions each type into
`store_classes` or `non_store_types` in `scripts/encryption-posture-ledger.json`. An unknown
type is a deterministic failure:

```
FAIL: unknown resource type <type> (at <addr>) -> add <type> to store_classes or non_store_types
```

Neither `cloudflare_pages_project` nor `cloudflare_pages_domain` is in that ledger today
(verified). **Creating `cf-pages.tf` therefore reddens CI on both new types until the ledger
is updated**, and no other gate in this plan would have surfaced it.

Both are classified in `scripts/encryption-posture-ledger.json` in PR1:

- `cloudflare_pages_project` → **`store_classes`**. It is a persistent store of published
  bytes; classifying it as a non-store would be a false statement about what it holds. Its
  `stores[]` row must satisfy the validator's shape, which the `## Encryption Posture` prose
  above does **not** yet meet: a `provider-managed:<AttestationName>` mechanism requires an
  `attestation_url` **and** a `retrieved_on` no older than 365 days. A bare "provider-managed
  encryption at rest" string is a literal reject.
- `cloudflare_pages_domain` → **`non_store_types`**. It is a hostname attachment; it holds no
  bytes.

### Vendor-tier reality check

Cloudflare Pages Free: 500 builds/month (direct-upload consumes none), 1 concurrent build,
20,000 files, 25 MiB max file, 100 custom domains, unlimited bandwidth. Bulk Redirects Free:
15 rules, 5 lists, 10,000 URL redirects. Single Redirects Free: 10 rules per zone (the cap this
plan works around). The site is well inside every limit. No `count = var.*_paid_tier` gate needed.

## Observability

```yaml
liveness_signal:
  what: sentry_uptime_monitor.soleur_apex (GET https://soleur.ai/ asserts 200),
        sentry_uptime_monitor.soleur_www (GET https://www.soleur.ai/ asserts 301),
        sentry_uptime_monitor.soleur_changelog_deep (GET https://soleur.ai/changelog/ asserts
        2xx — the only DEEP-PATH apex monitor, guarding "root serves 200 but every other page
        404s"), sentry_uptime_monitor.soleur_acme_probe (asserts 404), and the independent
        second source betteruptime_monitor.soleur_apex
  cadence: 300 s (Sentry, 300 s confirmation) / 180 s (Better Stack)
  alert_target: Sentry issue alert -> notify_email IssueOwners with ActiveMembers
        fallthrough; Better Stack -> managed recipient email. Two independent vendors
        by design (observability layer: vendor uptime probes, ADR-031).
  configured_in: apps/web-platform/infra/sentry/uptime-monitors.tf,
        apps/web-platform/infra/uptime-alerts.tf

error_reporting:
  destination: deploy-docs.yml fails the job on a non-zero wrangler exit AND on a
        post-deploy custom-domain SHA mismatch; the workflow's Sentry cron monitor
        (apps/web-platform/infra/sentry/cron-monitors.tf) opens an issue on a missed or
        failed check-in.
  fail_loud: true — the monitor pause/resume block runs its resume under `if: always()`,
        so a failed deploy never strands soleur-ai-www paused.

failure_modes:
  - mode: deploy lands on a preview alias because --branch != production_branch, so the
        custom domain keeps serving the previous build while CI is green
    detection: the post-deploy probe reads https://soleur.ai/version.txt (the CUSTOM
        DOMAIN, not *.pages.dev) and compares it to ${GITHUB_SHA}. A content-identity
        predicate, not a header proxy — a header proxy is present on every deployment of
        the project including a stale one, so it cannot discriminate.
    alert_route: deploy-docs.yml job failure.
  - mode: www stops 301-ing
    detection: sentry_uptime_monitor.soleur_www asserts 301, not 2xx. Under D1's chosen
        design www IS attached to the Pages project, so a missing redirect serves a duplicate
        copy of the site at 200 — which is exactly what the 301 assertion catches, within one
        confirmation period. (The rejected 192.0.2.1 variant would hard-fail instead; both are
        caught by this same monitor, which is why the failure-mode severity, not detectability,
        decided D1.) Second and third nets: the canonical-host build gate and the apex
        <link rel="canonical">.
    alert_route: Sentry issue alert -> email.
  - mode: the retained cert-reissue routine fires post-cutover and de-proxies www one-way
    detection: the D2 apex-topology precondition refuses the run and emits a non-benign
        terminal outcome; the existing proxy_restore_failed page remains as backstop.
    alert_route: Sentry issue alert -> email.
  - mode: apex serves from the wrong origin after a partial rollback
    detection: the origin-provenance probe below, which distinguishes three states
        (GitHub / Cloudflare / UNREACHABLE) rather than folding transport failure into a
        definite answer (AP-021).
    alert_route: run on demand; CUT2 is the cutover-time gate.
  - mode: token revoked -> every docs deploy fails
    detection: wrangler exits non-zero; the workflow's Sentry cron monitor opens an issue.
        event-cf-token-expiry-check covers CF_API_TOKEN only, which is why this token is
        minted with NO expiry — recorded in the scope ledger and on the deferred issue.
    alert_route: Sentry cron monitor -> issue -> email.
  - mode: apex mail/verification records disturbed by the A->CNAME transition
    detection: CUT9 compares dig MX/TXT against the recorded Phase 0 baseline.
    alert_route: cutover gate; rollback on mismatch.

logs:
  where: GitHub Actions run logs for the deploy path; Cloudflare Pages deployment history;
        Sentry issues for monitor failures.
  retention: GitHub Actions 90 days; Sentry per org plan; Cloudflare Pages deployment
        history retained by Cloudflare.

discoverability_test:
  command: |
    bash -c 'H=$(curl -sS -D - -o /dev/null --max-time 20 -w "HTTPCODE=%{http_code}\n" https://soleur.ai/ 2>/dev/null) || { echo "UNREACHABLE (transport)"; exit 2; }; case "$H" in *"HTTPCODE=200"*) ;; *) echo "UNREACHABLE (status not 200)"; exit 2;; esac; printf "%s\n" "$H" | grep -qiE "^(x-github-request-id|x-fastly-request-id|via: 1\.1 varnish)" && echo "SERVING-FROM-GITHUB-PAGES" || echo "SERVING-FROM-CLOUDFLARE-PAGES"'
  expected_output: "SERVING-FROM-CLOUDFLARE-PAGES"
```

The probe is unauthenticated, runs from any laptop or runner, reaches no private network, and
its first token is `bash` (on the preflight Check 10 allowlist). `credentials_required` is
deliberately absent — which origin serves the apex is fully observable from a public request.

**Verified across all four arms, 2026-08-20:** GitHub-Pages apex → `SERVING-FROM-GITHUB-PAGES`;
a live Cloudflare Pages host → `SERVING-FROM-CLOUDFLARE-PAGES`; an unreachable host →
`UNREACHABLE (transport)`; a reachable non-200 → `UNREACHABLE (status not 200)`. The naive
one-liner without the status capture printed `SERVING-FROM-CLOUDFLARE-PAGES` for an unreachable
host — a fail-open that collapses "could not check" into the *success* verdict, the worse
direction under AP-021.

## Encryption Posture

```yaml
at_rest:
  - store: Cloudflare Pages asset store (the deployed _site bundle)
    mechanism: provider-managed encryption at rest on Cloudflare object storage
    evidence: Cloudflare SOC 2 Type II / ISO 27001 attestations, already relied on for the
      existing R2 buckets in this root (soleur-terraform-state, soleur-workspaces-luks-header)
    defends_against: physical media compromise and offline disk access at the provider
    does_not_defend: anyone holding CF_API_TOKEN_PAGES, who can read and REPLACE the
      published bundle; and any public reader, since every byte in this store is
      deliberately public content
    disclosed_as: public marketing/documentation content, no personal data
    live_verification: curl -sSI https://soleur.ai/ returns 200 over TLS from Cloudflare's edge
  - store: terraform.tfstate on R2 (now also holds the Pages token value)
    mechanism: R2 provider-managed encryption at rest; bucket credentials distinct from every
      Cloudflare API token in this root
    evidence: backend block in main.tf; ADR-006
    defends_against: media compromise; credential separation bounds blast radius from a leaked
      CF API token
    does_not_defend: anyone holding the R2 S3-compatible access keys
    disclosed_as: infrastructure state containing sensitive variable values
    live_verification: unchanged by this plan
  - store: GitHub Actions secrets (CLOUDFLARE_API_TOKEN_PAGES, CLOUDFLARE_ACCOUNT_ID_PAGES)
    mechanism: GitHub-managed encryption at rest, auto-masked in logs
    evidence: seven existing github_actions_secret resources in this root
    defends_against: casual log exposure; read-back through the API
    does_not_defend: a compromised runner, or a workflow edit adding a pull_request trigger.
      deploy-docs.yml has NO pull_request trigger today and that absence is load-bearing.
    disclosed_as: CI deploy credential
    live_verification: gh secret list shows both names
    NOTE: after this change the token exists in THREE places — Doppler prd_terraform,
      terraform.tfstate on R2, and GitHub Actions secrets — under a single rotation. Named
      here and in the scope ledger; a Doppler-service-token indirection that would collapse
      this to one is recorded on the deferred issue.

in_transit:
  - connection: visitor browser -> Cloudflare edge (soleur.ai / www.soleur.ai)
    tls: TLS 1.3, Cloudflare-managed zone certificate
    cert_verification: "on"
    does_not_defend: an attacker holding CF_API_TOKEN_PAGES serves malicious content over a
      perfectly valid certificate — TLS attests the host, never the content
    disclosed_as: HTTPS everywhere, HSTS preloaded
  - connection: Cloudflare edge -> origin
    tls: n/a — ELIMINATED for the docs hosts by this change. Cloudflare Pages is served by
      Cloudflare, so after cutover there is no external origin leg. This is the posture
      improvement the migration buys: `ssl = "full"` exists precisely because the
      edge->GitHub-Pages leg presents an expired certificate.
    cert_verification: "n/a"
    does_not_defend: n/a
    disclosed_as: n/a
  - connection: GitHub Actions runner -> Cloudflare API (wrangler upload)
    tls: TLS 1.3 to api.cloudflare.com, default certificate verification
    cert_verification: "on"
    does_not_defend: a compromised runner or a leaked token
    disclosed_as: CI deploy path, token auto-masked

exception:
  - subject: the `ssl = "full"` Configuration Rule on soleur.ai + www.soleur.ai
    justification: PRE-EXISTING and explicitly retained by operator decision. It keeps the site
      up while the current origin certificate is expired, and it is what keeps the ROLLBACK
      viable — GitHub Pages' certificate is expired by construction, so a revert lands on an
      origin that only serves because of this rule. Removing it is part of the deferred
      cleanup. That it becomes inert for these hosts post-cutover (no origin leg remains) is a
      claim to MEASURE during that cleanup, not to assert here.
    tracking_issue: the deferred-cleanup issue filed in PR1
    reevaluate_when: the site is verified serving from Cloudflare Pages across a full
      certificate cycle AND the rollback window is formally closed
    expires_on: 2026-11-20
```

## Guard Contract

### Guard 1 — `www-apex-canonicalizer.test.sh` (rewritten)

**Property.** The `www.soleur.ai → 301 → soleur.ai` redirect, and the apex's binding to the
Pages project, cannot be silently lost by any single edit to the substrate that produces them.

**Assembly.** The property quantifies over the **chain** that produces the live behaviour, not
over a snapshot of current facts — the existing guard's defect is precisely that it asserts
five literal GitHub-Pages facts, which this migration falsifies wholesale. The chain has five
links and the guard must assert all five:

1. the redirect declaration — the `www.soleur.ai/` item in `cloudflare_list.www_canonical`, with `subpath_matching` and `preserve_path_suffix` both `"enabled"` and `include_subdomains` `"disabled"`;
2. the **binding chokepoint** — the second `rules { }` block in `cloudflare_ruleset.bulk_redirects` whose `from_list.name` references that list, declared **after** the `legal_redirects` rule. A list nothing binds is inert, and a rule ordered before the legal rule silently changes which redirect wins;
3. the DNS substrate — the apex is a proxied `CNAME` at the Pages project and www is a proxied `A` at the black-hole address;
4. the **cross-file deploy coupling** — `deploy-docs.yml`'s `--branch` equals `cf-pages.tf`'s `production_branch`;
5. the **cross-file project coupling** — `deploy-docs.yml`'s `--project-name` equals `cloudflare_pages_project.docs`'s `name`.

Links 4 and 5 are two independent magic strings in HCL and YAML with no compiler between them,
and link 4 is the highest-ranked risk in this plan: editing `--branch` leaves every other
assertion green while the custom domain silently serves a stale build. Both must be asserted by
**cross-reading the two files**, never by matching two independent literals.

All five assertion targets live under `apps/web-platform/infra/**` or `.github/workflows/`,
both inside `infra-validation.yml`'s `pull_request: paths`, so the guard actually **runs** on a
PR that mutates any of them. This is a live constraint, not a nicety: under the rejected
`_redirects` design, link 2 would have sat in `eleventy.config.js`, outside that filter, and
the chokepoint mutation would have passed by never running.

**Disclosed honestly: the guard runs but does not block.** Its only CI invocation is the
`Run www-apex-canonicalizer drift-guard` step in `infra-validation.yml`'s `deploy-script-tests`
job, and that job is **advisory** — it is not in `ruleset-ci-required.tf`, so it is a
visible-red signal rather than a merge gate. This plan does **not** silently rely on it as a
blocking control. Two things follow: the ten-path www assertion is additionally carried as a
cutover gate (CUT7), which is blocking by procedure; and promoting `deploy-script-tests` to a
required check is recorded on the deferred-cleanup issue as a separate decision with its own
blast radius, not smuggled in here.

**Mutation matrix.** Each row must drive the guard to a non-zero exit.

| # | Mutation | Why it must redden |
|---|---|---|
| M1 | Delete the www item from `cloudflare_list.www_canonical` (leaving the list present) | the declaration is gone; a list-existence check alone would pass |
| M2 | Remove the second `rules { }` block from `cloudflare_ruleset.bulk_redirects` (leaving the list intact) | **the chokepoint row** — the declaration survives but nothing binds it, so the live 301 dies with every other assertion green |
| M3 | Reorder the two rules so the www rule precedes the legal rule | first-match-wins means the ten legacy legal paths on www would collapse to the bare apex |
| M4 | Repoint the apex `cloudflare_record` at any host other than the Pages project | the apex leaves the project |
| M5 | Flip `proxied = false` on either the apex or the www record | breaks the `domains.md` HSTS mandate and the edge path the redirect depends on |
| M6 | **Second-member row** — add a *second* redirect list and bind it with a third rule while leaving M1/M2 intact | a guard that stops at the first matching list or rule cannot see a divergent second declaration |
| M7 | **Cross-file row** — change `--branch` in `deploy-docs.yml` so it no longer equals `production_branch` (and, separately, `--project-name`) | the plan's highest-ranked risk; every in-file assertion stays green while the custom domain serves a stale build |
| M8 | **Own-dispatch row** — replace the guard's assertion list with an empty list | a guard reporting `0 assertions checked` and exiting `0` is vacuous |

**Harness rows.**

| # | Edit to the SUITE (not the guard) | Expected |
|---|---|---|
| H1 | Delete the M2 case from the guard's case list | the anti-vacuity floor must fail — a suite that silently shrinks is exactly what this row detects. Per **AP-023** the floor reports with `printf >&2` + `exit 1`, **not** through the suite's own `fail()`, and the case counter increments **at the call site**, never inside both verdict helpers. The file being rewritten has the banned shape today, so preserving its structure and bolting a floor on top would satisfy M8 on paper and be vacuous in fact |
| H2 | **Must-PASS, non-canonical**: reformat `seo-bulk-redirects.tf` with different internal whitespace, reorder unrelated list items, and reflow the `dns.tf` contract comment | must still exit `0` — the guard asserts content anchors, not byte-equality with a canonical file. A guard that rejects everything is as broken as one that accepts everything |

Carry forward the existing header note: *"A2/A3 grep the `cloudflare_record` resource name. A
future v4→v5 bump renames `cloudflare_record` → `cloudflare_dns_record`."* It applies unchanged
to the rewritten assertions.

## Architecture Decision (ADR/C4)

### ADR

**Amend ADR-194** — do not renumber, do not create a new ADR. This plan *implements* an accepted
decision and corrects two lines of its reasoning:

1. `## Decision` — correct the free-slot premise (R1): the ACME carve-out is an inline clause of Rule 10, not a rule, so retiring it frees zero slots. Record that the 301 is rebuilt on a different product entirely, so the cap does not bind.
2. `## Alternatives Considered` — add the three considered mechanisms (a rule in `seo_page_redirects`; a Pages `_redirects` file; account Bulk Redirects) with the measured reason each was rejected or chosen, including that Cloudflare documents domain-level `_redirects` as unsupported.
3. Record that the ADR's "cleanup once live" list contains one item — the cert-reissue routine — whose *disarmament* could not be deferred with its deletion, and why.
4. Add pointers to the deferred-cleanup issue and the cutover runbook.

No new ADR ordinal is claimed, so there is no ordinal-collision exposure.

### C4 views

All three model files were read: `model.c4` (691 lines), `views.c4` (74), `spec.c4` (54). The
enumeration the completeness mandate requires:

| Category | Element | Modelled? | Action |
|---|---|---|---|
| External system | `github` | yes; in `context` + `containers` | **amend description** — it carries the Pages-cert-admin `PUT /pages` role as a live concern; post-cutover that path is DNS-detached |
| External system | `cloudflare` | yes; in both views | **amend description** — it becomes the docs-site host, a role it does not carry today |
| External system | `letsencrypt` | yes; described as *"ACME CA issuing the GitHub Pages custom-domain TLS cert for soleur.ai/www"* | **amend description** — that becomes false for the live site; scope it to the retained, DNS-detached path |
| External system | `publicResolvers` | yes; described via the cert-reissue DNS-propagation gate | **no edit** — the routine is retained, so the description stays true |
| Container | the Eleventy docs/marketing site | **not modelled** anywhere in `model.c4` | **not added** — it was unmodelled while on GitHub Pages and remains unmodelled after; this change does not make that silence false, and silence is not falsehood. Recorded on the deferred issue |
| External human actor | public site visitor / search crawler | not modelled (`founder`, `emailSender`, `betaContact`, `contributor` only) | **not added** — same disposition; recorded here so the next author sees it was checked, not missed |
| Access relationship | GitHub Actions → Cloudflare Pages content upload | not modelled | **not added** — `github` and `cloudflare` are already in both view include lists and the model already says they talk; a second parallel edge would need disambiguation from the existing read-only rulesets-GET edge, work created entirely by the addition |
| Access relationship | `api -> cloudflare` (cert-reissue proxied flip) | yes | **amend description** — add that the routine is gated on apex topology per D2 |

Only `model.c4` is edited; `views.c4` is untouched, which removes the #7332
both-endpoints-must-be-included hazard entirely. `c4-code-syntax.test.ts` and
`c4-render.test.ts` remain the gates.

### Sequencing

The ADR amendment, the C4 corrections and the principles-register AP-019 note all ship in
**PR1**, ahead of the cutover — the statements they correct become false at the moment PR3
lands, and the disarmament they describe must exist before then.

**Issue closure is PR3's alone.** The frontmatter `closes: 7640` names the work item, not the
merge that resolves it. Only **PR3** carries `Closes #7640` in its body; **PR1 and PR2 cite
`Refs #7640`** and must not use a closing keyword. Closing the issue at PR1 would mark the
migration done while the site is still served by GitHub Pages and the cutover has not
happened — and it would retire the tracking issue that PR2 and PR3 are sequenced against.

## Test Scenarios

| # | Scenario | Expected |
|---|---|---|
| T1 | `terraform validate` after adding `cf-pages.tf` and the new list/rule | exit `0` |
| T2 | `cloudflare_pages_project` declared without `production_branch` | `terraform validate` fails — confirms the schema requirement empirically |
| T3 | Guard 1 mutation rows M1-M8 | each drives a non-zero exit |
| T4 | Guard 1 harness rows H1, H2 | H1 fails via the AP-023 floor; H2 passes |
| T5 | `scripts/guard-vacuity-floor.test.sh` against the rewritten guard | passes |
| T6 | `wrangler pages deploy _site --project-name=soleur-docs --branch=main` | lands on the **production** deployment; `https://soleur-docs.pages.dev/version.txt` equals the SHA |
| T7 | Deploy with `--branch=some-other-branch` | lands on a preview alias and the custom domain keeps serving the previous build — confirms the trap is real before it can bite in production |
| T8 | The post-deploy probe with a deliberately wrong expected SHA | fails the job |
| T9 | `curl -sS -o /dev/null -w '%{http_code}' https://soleur-docs.pages.dev/no-such-path` | `404` |
| T10 | PF3: attach the apex custom domain, then list zone DNS records | no record auto-created, or the create is detected and `dns.tf` becomes an import |
| T11 | PF7: attach and detach a scratch custom domain | edge-routing persistence measured; the runbook's rollback matches the answer |
| T12 | T-WWW / CUT7: the ten legacy legal paths on the **www** host | still `301` to `/legal/<slug>/`, not collapsed to the bare apex |
| T13 | The origin-provenance probe across four arms | GitHub / Cloudflare / UNREACHABLE(transport) / UNREACHABLE(non-200) — already executed, results in Observability |
| T14 | D2: stub the apex record read with a `CNAME` and invoke the reissue preconditions | non-benign terminal outcome; no DNS mutation attempted |
| T14b | `python3 scripts/lint-encryption-posture.py --repo-sweep` after adding `cf-pages.tf` **without** a ledger entry | FAILS with `unknown resource type cloudflare_pages_project` — confirms the gate is real before relying on the ledger fix |
| T14c | The same sweep after the ledger entry lands | exit `0` |
| T14d | The cutover apply rehearsed as a single unordered pass against a scratch zone | reproduces error `81053` or a recordless window — confirms D4's premise rather than assuming it |
| T15 | `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main` | exit `0` |
| T16 | `c4-code-syntax.test.ts` + `c4-render.test.ts` | pass |
| T17 | `dig soleur.ai MX` / `TXT` before and after PR3 | byte-identical sets |
| T18 | CUT0-CUT9 under the 3-sample rule | all hold |

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Deploy lands on a preview alias; custom domain serves stale content while CI is green | medium | high | `production_branch` pinned in HCL, `--branch` pinned in YAML, Guard 1 M7 asserts they agree, and the post-deploy probe reads `version.txt` on the **custom domain**. T7 exercises the failure deliberately |
| Apex CNAME create lands while the four `A` deletes are out of `-target` scope | low | **total outage — NXDOMAIN, and HSTS preload forbids an HTTP fallback** | Both old and new addresses in the allow-list; PF9 pins the exact plan shape before the ack |
| `cloudflare_pages_domain` auto-creates a DNS record that collides with the Terraform-managed one | medium | medium | PF3 probes it in PR1, before PR3 is written. The ordering design no longer rests on the schema inference (R8) |
| A DNS-only revert does not restore GitHub Pages because the Pages custom domain still routes the hostname | medium | **high — rollback does not roll back** | PF7 measures it on a scratch domain before the cutover; the runbook is written to the measured answer |
| `TF_VAR_cf_api_token_pages` absent at merge → every apply on this root fails | medium | high | Phase 0 step 4 makes it a merge precondition for PR1 |
| The retained cert-reissue routine de-proxies live www, one-way | **high — it is the retained system's designed steady-state output** | high | D2: apex-topology precondition, the daily cron disabled, AP-019 status recorded. AC25-AC27 |
| CUT assertions fail during the legitimate ~5-minute mixed-resolution window | high without mitigation | medium — a false rollback | 3 consecutive clean samples at 60 s, starting 5 minutes after the apply; transport failure is a distinct verdict |
| Rollback MTTR dominated by CI on the revert PR | certain without mitigation | high at this threshold | The revert PR is pre-opened, green and mergeable before PR3 merges (PF8) |
| `workflow_dispatch` cannot carry `[ack-destroy]`, so the documented escape hatch cannot roll back | certain | high if discovered mid-incident | Stated in the runbook; the merge path is the only path |
| Apex MX/TXT disturbed by the A→CNAME transition — invisible to every uptime monitor | low | **high — silent mail loss** | Baseline captured in Phase 0; CUT9 compares; PF9 asserts zero planned changes to those records |
| Bulk Redirect precedence between the legal rule and the www rule | low | medium | Separate list plus explicit rule ordering, not intra-list precedence (undocumented); CUT7/T12 assert the ten legal paths on www |
| Pages token exists in three places under one rotation | certain | medium | Named in the scope ledger and Encryption Posture; rotation-policy comment on both `github_actions_secret` resources; Doppler-service-token indirection recorded on the deferred issue |
| Content rollback (a bad docs build) is no longer "re-run a green workflow run" | certain | medium | The runbook carries the Pages deployment-rollback procedure, with the subcommand shape verified at the pinned wrangler version |
| Rollback serves frozen, pre-cutover content | certain | low | Stated in D3; acceptable for an availability rollback |

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or omits the threshold fails `deepen-plan` Phase 4.6. It is filled above.
- **`production_branch` is required even for a direct-upload project**, and it is not cosmetic: it is the sole determinant of whether a deploy reaches the custom domain or a preview alias. It must equal `--branch` in the workflow, and nothing but Guard 1 M7 checks that.
- **The ACME carve-out is a clause, not a rule.** Any future plan that budgets a rule slot by retiring it is budgeting a slot that does not exist.
- **Cloudflare Pages `_redirects` cannot express a domain-level redirect.** The obvious `https://www.example.com/* https://example.com/:splat 301` shape is the documented counter-example. It would also have failed this repo's own canonical-host build gate, and it would have placed the guard's chokepoint assertion outside `infra-validation.yml`'s path filter. Three independent failures behind one plausible-looking line.
- **A provider schema that exposes no DNS attributes does not mean the API creates no DNS record.** `cloudflare_pages_domain` looked inert by schema; Cloudflare documents that it auto-creates the CNAME when the zone is on the same account. Schema inference is not service behaviour — probe it (R8).
- **`grep -c` exits 1 when the count is zero**, so an acceptance criterion of the form "`grep -c … returns 0`" aborts under `set -e` instead of passing. Use `$(… || true)` with an explicit comparison, or `! grep -q`.
- **`server: cloudflare` is present both before and after this cutover**, because Cloudflare already proxies the GitHub origin. Any "are we on Pages yet?" check keyed on it discriminates nothing. The header discriminator is the **absence** of the GitHub/Fastly origin markers — and the durable check is the build-identity probe, not a header at all.
- **A probe that folds transport failure into a definite verdict is worse than one that fails closed.** The naive origin-provenance one-liner prints the *success* answer for an unreachable site. AP-021 forbids collapsing "could not check" into an answer; the shipped form emits a third `UNREACHABLE` verdict, verified across all four arms.
- **An anti-vacuity floor that reports through the suite's own `fail()` is vacuous** (AP-023), because neutering `fail()` silences both the assertion rows and the floor meant to notice. The file being rewritten has exactly that shape today.
- **`workflow_dispatch` cannot satisfy the `[ack-destroy]` gate**, because `github.event.head_commit` is absent on that event. The documented manual escape hatch structurally cannot perform a destructive rollback.
- **A `-target=` allow-list is the apply predicate, not sweep hygiene.** An untargeted resource is declared and never created, and nothing fails until something downstream reads it. Every `github_actions_secret` in this root is individually target-listed.
- **Delegating a `-target=` assertion to `terraform-target-parity.test.ts` passes vacuously** for any non-SSH resource: its predicate is a `terraform_data` resource with both an SSH `connection` block and a `provisioner` block, and it self-documents as one-directional.
- **A removed resource and its replacement are unrelated graph nodes.** `depends_on` cannot reference a resource that has left the configuration, so Terraform dispatches the deletes and the create concurrently. For a record type where the old and new cannot coexist (CNAME over `A`), that is a coin flip between a clean apply and error `81053` mid-flight on a live apex — and the interval between them is a window where the name has *no* address record at all. NXDOMAIN negative-caches against the zone SOA minimum (1800 s), six times the 300 s positive TTL a proxied record uses. Order it explicitly; a plan-shape assertion cannot see order.
- **An apex CNAME coexists with apex `TXT` and `MX` at Cloudflare.** The conflict set is exactly CNAME-over-`A`/`AAAA`/`CNAME` and `A`/`AAAA`-over-`CNAME`; `MX` and `TXT` are never in it, and CNAME flattening is what makes an apex CNAME legal at all. The zone's five apex `TXT`/`MX` records survive untouched. This was the plan's highest-flagged structural risk and it is **not** a risk — but CUT9 still asserts it, because a silent mail break is invisible to every uptime monitor.
- **Do not touch the zone's CNAME-flattening setting.** It runs the default *Flatten CNAME at root*. Someone adding an apex CNAME is exactly the person who might flip it to *Flatten all CNAMEs* — which would flatten the three ProtonMail DKIM CNAMEs and the unproxied `api.soleur.ai` Supabase record, breaking DKIM and Supabase certificate validation. The apex CNAME needs no such change.
- **Pointing DNS at a Pages project before the custom domain is attached is a hard 522, not a soft 404.** Cloudflare: *"Manually adding a custom CNAME record pointing to your Cloudflare Pages site — without first associating the domain … will result in your domain failing to resolve at the CNAME record address, and display a 522 error."* The `depends_on` direction in this plan is the correct one, and the cost of reversing it is an edge error on the apex.
- **`cloudflare_pages_domain.status` reads `pending`/`initializing` for a while after apply.** It is computed, so it produces no diff — but `scheduled-terraform-drift.yml` runs a full plan every 12 h, and a drift reviewer should not chase it.
- **`ssl = "flexible"` on a Pages custom domain is a documented redirect loop.** This zone is not exposed: `seo-config-rules.tf` scopes `flexible` to `(http.host eq "app.soleur.ai")` and `full` to the docs hosts. Recorded as *checked*, because "we didn't touch it" is a weaker guarantee than "we read the expression."
- **`grep -c` counts lines, not tokens, and a repo convention can put the searched word in prose.** `grep -c 'default'` inside a Terraform variable block returns `1` on a *correct* no-default variable here, because the house style ends the description with "No default (hr-…)". Anchor on `^\s*default\s*=`.
- `dns.tf`'s contract comment asserting repo-wide absence of `cloudflare_list` / `http_request_redirect` resources has been stale since 2026-06-09. Comments that assert repo-wide absence rot silently; the rewrite states what the substrate **is**, across all three redirect owners, and the guard asserts it.
