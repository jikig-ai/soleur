---
title: Migrate the marketing/docs site off GitHub Pages to Cloudflare Pages — the proxy/certificate conflict is structural, not a bug to fix
status: accepted
date: 2026-08-19
related_adrs: [ADR-125, ADR-130, ADR-136]
related: [6691, 6698, 6657, 7539, 7584, 7620, 7640]
related_runbooks:
  - knowledge-base/engineering/operations/runbooks/gh-pages-cert-renewal.md
brand_survival_threshold: single-user incident
---

# Migrate the marketing/docs site off GitHub Pages to Cloudflare Pages

## Status

**ACCEPTED** — 2026-08-20. Written to support a decision; the operator took it on
the evidence recorded below. The mitigation it supersedes (`ssl = "full"`, PR
#7584) is live and the site is healthy, so the migration proceeds without time
pressure — and `ssl = "full"` stays in place until the migration is verified
live. Implementation is tracked in issue #7640.

## Context

### The conflict

`soleur.ai` / `www.soleur.ai` are served by GitHub Pages behind Cloudflare's
proxy. Two requirements the platform holds simultaneously cannot both be
satisfied:

- **`domains.md` mandates `proxied = true`** for hosts in this zone, to satisfy
  the HSTS preload commitment (submitted 2026-03-20; removal takes months).
- **GitHub Pages refuses to issue or renew a certificate for a proxied host.**

The second is not a bug or an outage. It is a documented, deterministic product
behaviour, reported by GitHub's own diagnostic
(`GET /repos/{owner}/{repo}/pages/health`):

```
is_https_eligible              false     <- the blocker
is_proxied                     true
is_cloudflare_ip               true
is_pointed_to_github_pages_ip  false
caa_error                      null      <- not CAA
reason                         null      <- nothing else misconfigured
```

Because **renewal requires the same eligibility as issuance**, the origin
certificate expires every 90 days by construction and cannot self-heal.

### What it has already cost

- **2026-05-18** — Cloudflare's Always-Use-HTTPS 301'd the ACME challenge path.
  Fixed with a negative-match carve-out in Rule 10 of `seo_page_redirects`.
  `domains.md` then recorded this as *the* fix for renewal. It was necessary but
  not sufficient, and that false confidence is part of why the next failure went
  unescalated.
- **2026-07-19** — Certificate entered `bad_authz`; #6691 filed. It commented
  **every day for 28 days**, counting down to expiry.
- **2026-08-16** — Certificate expired 13:53:34Z. Apex served Cloudflare **526**
  for ~8h15m. Restored with a scoped `ssl = "full"` Configuration Rule (#7584).
- **Three successive wrong diagnoses** were recorded in this repo during
  remediation: (1) DNS propagation too short (#6698); (2) the authorization is
  wedged server-side and needs GitHub Support; (3) GitHub re-evaluates
  eligibility on a slow background schedule. All three were falsified by
  measurement. That is not incidental — it is evidence the failure mode is
  **hard to reason about correctly**, which is itself an operational cost.

### The decisive experiment (2026-08-19)

A full renewal window was run under conditions verified correct in advance —
something no previous attempt did:

| Precondition | Verified |
|---|---|
| apex+www `proxied=false` | 5/5 records |
| Public DNS on GitHub anycast | both 1.1.1.1 and 8.8.8.8, ~20s |
| `is_https_eligible` | **`True` / `True`**, reached in ~1 minute |
| `is_pointed_to_github_pages_ip` | `True` |
| `caa_error` | `null` |
| Zone AAAA records | 0 |
| ACME challenge path | 404 GitHub-shaped, 0 redirects, HTTP and HTTPS |
| Custom-domain toggle | cleared 75s, re-set, **while eligible** |
| Fresh Pages deployment | dispatched inside the window |

**Result after 62 minutes: no change whatsoever.** `https_certificate.state`
stayed flat at `bad_authz`, with **no intermediate state** (`new`,
`authorization_pending`, …) at any point, and the origin continued to serve the
expired `notAfter=Aug 16 13:53:34 2026` certificate. Certificate-transparency
logs (Cert Spotter) show **no Let's Encrypt certificate naming the apex since
mid-June**, so no order has silently succeeded either.

The absence of *any* state transition is the important part. It suggests GitHub
is not placing a new order at all, and there is no API to force one. We hold no
lever.

### Why this keeps recurring

The remediation machinery built for this (`cron-gh-pages-cert-reissue`, ADR-125)
is sound in design and still cannot win: it automates a DNS-only window, but the
window only helps if GitHub then acts, and we have now measured that it does not.
Meanwhile the machinery itself is substantial — ~1,700 lines plus tests, a marker
schema, a detector cron, and a runbook — all of it existing solely to fight a
product behaviour we cannot change.

## Considered Options

### (a) Migrate to Cloudflare Pages — **ACCEPTED**

The site is served *by* Cloudflare, so **there is no origin certificate**. The
entire failure class stops existing rather than being managed.

The build is portable. `deploy-docs.yml` runs Eleventy
(`eleventy.config.js` → `_site`) and then six gates — SEO validation, CSP
validation, canonical-host, build verification, critical-CSS coverage, and a
Playwright screenshot/FOUC gate. **None of that changes.** Only the terminal
steps swap:

```
actions/configure-pages + upload-pages-artifact + deploy-pages
  ->  cloudflare/wrangler-action:  wrangler pages deploy _site
```

Direct-upload mode (not the Git integration) keeps the existing gate chain
authoritative — the site deploys only if every gate passed, exactly as today.

### (b) Keep `ssl = "full"` permanently — rejected, but it is the fallback

Costs nothing and is already live. Rejected as a *destination* because it leaves
the Cloudflare→origin leg unauthenticated forever, keeps ~2,000 lines of dead
remediation machinery, and leaves `domains.md` describing an architecture nobody
can operate correctly (see the three wrong diagnoses).

It remains the correct **fallback** if (a) is not accepted, and the correct
**interim** state regardless.

### (c) Automate a proactive day-60 DNS-only renewal — rejected on evidence

The theory: renew while the current certificate is still valid, so GitHub Pages
serves the valid certificate during the window and the renewal is zero-downtime.
This was the intended follow-up before 2026-08-19.

Rejected because the experiment falsified its premise. It assumes that with
eligibility restored GitHub will renew. We held perfect eligibility for 62
minutes, toggled the domain, and deployed — and GitHub did nothing. Automating a
window that has never once been observed to work would be building on an
unverified assumption, which is precisely the mistake this ADR exists to stop
repeating.

Worth noting it may *still* be true for a **healthy** certificate — our cert is
wedged in `bad_authz`, which may be its own trap. But we have no way to test that
without waiting 90 days for a healthy cert we cannot currently obtain.

### (d) Self-host the static site on the existing Hetzner web host — rejected

`web-1` already runs the app behind Cloudflare with its own certificate handling.
Rejected: it converts a zero-ops static site into a host we must patch, monitor,
and keep alive, and couples marketing availability to the app host. The current
outage was bad; making the docs site share a fate with the app is worse.

### (e) Another static host (Netlify, Vercel, S3+CloudFront) — rejected

All solve the certificate problem, all add a new vendor, a new bill, a new
account to provision, and a new DPA/sub-processor entry. Cloudflare is already a
sub-processor, already holds the zone, already has Terraform-managed narrow
tokens, and costs nothing further.

## Decision

**Accepted:** migrate the marketing/docs site from GitHub Pages to Cloudflare
Pages, retire the certificate-remediation subsystem, and return the zone to
`strict` universally.

### Work required

1. **`cloudflare_pages_project`** (direct-upload) + `cloudflare_pages_domain`
   for apex and www, in `apps/web-platform/infra/`. Provider is pinned
   `cloudflare/cloudflare ~> 4.0` (4.52.7), which supports both.
2. **Swap the deploy step** in `deploy-docs.yml` to `wrangler pages deploy _site`.
   Everything upstream is untouched.
3. **Re-create the `www -> apex` 301** (see Consequences — this is the real work).
4. **DNS rewire**: the four apex A-records and the www CNAME become CNAMEs to the
   Pages project; Cloudflare flattens the apex.
5. **Mint/scope a `Pages:Edit` token** per the ADR-130 decision test (widen an
   existing narrow token vs. mint an alias).
6. **Delete** the remediation subsystem (listed below).

> **Superseded 2026-08-20 (#7640) — item 3's premise. The item stands; the cost it was
> priced at does not.** `## Consequences` below reasons that the `www -> apex` rule must be
> added *inside* `seo_page_redirects` at its 10-rule Free-tier cap, and concludes *"retiring
> the ACME carve-out frees the slot the www rule needs"*. **Retiring the carve-out frees zero
> slots.** The carve-out is not a rule. It is a negative-match clause inside Rule 10's own
> `expression` — `(not ssl) and not (http.host in {"soleur.ai" "www.soleur.ai"} and
> starts_with(http.request.uri.path, "/.well-known/acme-challenge/"))` — inlined there
> precisely because Cloudflare permits one user-defined ruleset per `(zone, phase)` and
> rejects a `skip` action on the `http_request_dynamic_redirect` phase (CF API error 20016,
> PR #3974). Deleting the clause leaves the rule count at 10. The slot it was believed to
> free never existed, and the ~~"migrating pays for itself here"~~ claim is withdrawn.
>
> **The cap does not bind this work at all.** The 301 is rebuilt on a *different product*:
> Cloudflare **Bulk Redirects**, account-level, on the `http_request_redirect` phase, with
> its own quota (15 rules / 5 lists on Free), already wired in this repo at
> `apps/web-platform/infra/seo-bulk-redirects.tf` and already inside the granted token scope
> post-#5092. `seo_page_redirects` is not edited, Rule 10 and its ACME carve-out clause
> survive verbatim, and `always_use_https = "off"` and the `ssl = "full"` Configuration Rule
> are all explicitly out of scope for the migration. Rationale and the rejected options are
> in **Alternatives Considered — the `www -> apex` 301 mechanism** below; the implementing
> decision is `## Design Decision D1` of
> `knowledge-base/project/plans/2026-08-20-chore-migrate-docs-site-to-cloudflare-pages-plan.md`.

### Sequencing

Deliberately **after** the current incident is closed out, not during it. The
`ssl = "full"` mitigation makes the site healthy and removes all urgency, so this
migration should be planned work with a rollback rehearsal — not another change
made under outage pressure. Rollback is a DNS flip: leave the GitHub Pages
configuration in place but DNS-detached.

## Consequences

### The hard part: `www -> apex` is currently free and would be lost

`dns.tf` is explicit that this redirect is **GitHub-Pages-owned**:

> "The live `www.soleur.ai -> 301 -> soleur.ai` redirect is GitHub-Pages-owned —
> it is NOT a Cloudflare Redirect Rule or Page Rule."

GitHub Pages auto-301s every non-primary alias to the primary domain named by
`plugins/soleur/docs/CNAME`. On Cloudflare Pages that behaviour does not exist and
must be built, and it runs into a constraint this repo has already hit:

- Cloudflare allows **one user-defined ruleset per (zone, phase)**.
- `seo_page_redirects` already occupies `http_request_dynamic_redirect`.
- It is at the **10-rule Free-tier cap** — a blog redirect was already dropped to
  fit the ACME carve-out.

So the www rule must be added *inside* the existing ruleset, at the cap.
**Migrating pays for itself here**: retiring the ACME carve-out frees the slot the
www rule needs.

> **Superseded 2026-08-20 (#7640):** both sentences above are false. The carve-out is a
> clause of Rule 10, not a rule, so retiring it frees no slot; and the www rule is not added
> to this ruleset at all — it is a Cloudflare Bulk Redirect on a different phase with its own
> quota. The full correction is the `> **Superseded 2026-08-20 (#7640) — item 3's premise**`
> note in `## Decision` above. What survives here unchanged: the redirect really is
> GitHub-Pages-owned today and really is lost by the migration, and
> `www-apex-canonicalizer.test.sh` really does need rewriting.

`www-apex-canonicalizer.test.sh` asserts three facts together (the records, the
CNAME file, and the 301) and would need rewriting, since its premise becomes
false. Runtime drift is guarded by `sentry_uptime_monitor.soleur_www`, which
keeps working unchanged because the asserted URL does not move.

### What gets deleted

- `cron-gh-pages-cert-reissue.ts` (~1,700 lines) + `cron-gh-pages-cert-reissue.test.ts`
- `cron-gh-pages-cert-state.ts` + the `[cert-poll]` issue machinery
- `cert-reissue-marker.ts` + its tests
- `cf-cert-reissue-token.tf` and the `CF_API_TOKEN_DNS_EDIT` runtime secret
- the `ssl = "full"` Configuration Rule (zone returns to `strict` everywhere)
- the ACME carve-out clause in Rule 10 of `seo_page_redirects`
- `gh-pages-cert-renewal.md`, ADR-125, and issues #6691 / #6698

This is a **net deletion** of a subsystem whose entire purpose is fighting a
product behaviour we do not control.

### Costs and risks

- **Cost: $0.** Pages free tier is unlimited bandwidth, 500 builds/month;
  direct-upload deploys do not consume build minutes. No new sub-processor, no
  DPA change — Cloudflare is already both.
- **CSP/headers parity** must be verified. `validate-csp.sh` runs against `_site`,
  so meta-tag-delivered policy ports unchanged; anything relying on GitHub Pages
  response headers needs a `_headers` file.
- **404 handling**: `404.njk` builds to `404.html`, which Cloudflare Pages honours.
- **A new deploy surface** to learn, and `wrangler` becomes a CI dependency.
- **HSTS preload is unaffected** — Cloudflare still terminates TLS with a valid
  edge certificate, which is what preload actually requires.

### What this does NOT solve

Stated plainly, because the motivating framing was "GitHub has been unreliable":
this removes **one** failure mode. GitHub Actions still builds and deploys the
site, the GitHub App still drives automation, and issues remain the backbone of
the workflow. Platform exposure is essentially unchanged.

The honest case for this migration is not risk reduction. It is **deleting a
subsystem that has produced one public outage, 28 days of ignored alerts, and
three incorrect diagnoses** — and whose core assumption we have now measured to be
false.

## Principle Alignment

- **AP-001 / AP-019** (off-Terraform live-infra mutation): the DNS-only toggle is
  a sanctioned exception governed by ADR-125. Migrating removes the need for the
  exception entirely, which is strictly better than continuing to justify it.
- **`hr-all-infrastructure-provisioning-servers`**: the Pages project and its
  domains are Terraform-declared; no vendor-dashboard click-path is introduced.
- **`hr-observability-as-plan-quality-gate`**: the migration removes an
  observability burden rather than adding one — the `SOLEUR_CERT_REISSUE` marker
  family and its Better Stack queries retire with the subsystem.

## Addendum — 2026-08-20 (#7640): what the implementation plan changed about this ADR's reasoning

The decision is unchanged and the status stays **ACCEPTED**. Implementation planning
(`knowledge-base/project/plans/2026-08-20-chore-migrate-docs-site-to-cloudflare-pages-plan.md`)
falsified one premise and split one deliverable, and both are recorded here rather than
silently absorbed into the plan.

### 1. The free-slot premise (R1)

Corrected in place — see the `> **Superseded 2026-08-20 (#7640) — item 3's premise**` note in
`## Decision`, and the pointer at the false sentence in `## Consequences`. Summary: the ACME
carve-out is a clause of Rule 10, not a rule; retiring it frees zero slots; and the cap it was
measured against does not govern the product the 301 is actually rebuilt on.

### 2. Deletion is deferred, but **disarmament is not** — and they are different decisions

`### What gets deleted` above is a *cleanup once live* list, and every item on it is deferred
out of the migration's scope by the plan (`ssl = "full"` in particular must stay in place for
the whole rollback window, because the GitHub Pages origin certificate is expired by
construction and `strict` would 526 a rollback). **One item cannot be deferred whole**: the
certificate-reissue routine. Deleting it later is fine; leaving it *armed* across the cutover
is not, because the cutover is what creates the hazard:

- `cron-gh-pages-cert-state` runs on a live `0 3 * * *` schedule. Post-cutover the GitHub
  Pages certificate is DNS-detached and can never recover, so the detector's steady-state
  output is a `[cert-poll]` issue **every day, forever**, whose body instructs the reader —
  in practice an autonomous agent — to fire `cron/gh-pages-cert-reissue.manual-trigger`.
- Every precondition in `checkReissuePreconditions` still passes post-cutover, and probe-only
  mode does **not** make the routine read-only: `setRecordsProxied(deps, records, false)` runs
  unconditionally.
- `listToggleRecords()` queries `[apex, "A"]` and `[www, "CNAME"]`. Post-cutover the apex is a
  CNAME, so the apex is untouched and **`www` is what gets `proxied = false`** — dropping HSTS,
  Rule 10's HTTPS upgrade, WAF and bot management on a host `domains.md` mandates be proxied.
- It cannot undo that. `restoreStateInner` refuses to restore a subset when fewer than
  `EXPECTED_TOGGLE_RECORDS = 5` records come back, which post-cutover is always. The routine's
  own fail-loud safety guarantee is exactly what makes the de-proxying **one-way**.

So the migration ships the disarmament with the substrate, not with the deletion: an
apex-topology precondition that refuses to run unless the live apex record type is `A`, and
removal of the `cron` trigger on `cron-gh-pages-cert-state` (its manual-trigger arm is
retained). Nothing is deleted. See `## Design Decision D2` of the plan.

This also voids, until that precondition is live, the justification AP-019 carries in
`knowledge-base/engineering/architecture/principles-register.md` — recorded there under
`## Notes`.

### 3. Pointers

- **Deferred cleanup** — the deletions in `### What gets deleted`, the retirement of the ACME
  carve-out, and the return of the zone to `ssl = "strict"` are tracked on the deferred-cleanup
  issue filed with PR1 of #7640. Its re-evaluation criteria include that `ssl = "full"` must
  remain in place while the rollback window is open, that the docs-site container and the
  public-visitor actor remain deliberately unmodelled in C4, and that
  `sentry_uptime_monitor.soleur_acme_probe` **loses its property** at the cutover (it keeps
  passing, but against Cloudflare Pages' own `404.html` rather than Rule 10's carve-out).
- **Cutover runbook** —
  `knowledge-base/engineering/operations/runbooks/cloudflare-pages-cutover.md` (lands with PR2).
  It records that `workflow_dispatch` structurally cannot perform the rollback — the destroy
  gate reads `github.event.head_commit.message`, which is empty on a dispatch run, so
  `[ack-destroy]` can never match — making the merge of the pre-opened revert PR the only
  rollback path.
- **Retained runbook** — `gh-pages-cert-renewal.md` stays (it is a deferred-deletion artifact),
  but the routine it documents refuses to run post-cutover by design.

## Alternatives Considered — the `www -> apex` 301 mechanism (added 2026-08-20, #7640)

GitHub Pages auto-301s `www.soleur.ai` to the primary domain named by `plugins/soleur/docs/CNAME`
for free. Cloudflare Pages has no equivalent, so the redirect must be rebuilt. Three mechanisms
were considered; the measured reason for each verdict is recorded so the next author does not
re-derive them.

### (i) A rule inside `cloudflare_ruleset.seo_page_redirects` — **rejected**

This is what `## Consequences` above assumed. It fails on measurement, not on taste:

- The ruleset holds exactly 10 rules (9 SEO 301s + Rule 10, the HTTPS catch-all) against a
  documented Free cap of 10 for the `http_request_dynamic_redirect` phase, and Cloudflare
  permits one user-defined ruleset per `(zone, phase)` — so there is no second ruleset to
  put it in.
- Rule 10 upgrades **every proxied host in the zone** to HTTPS, protecting cross-subdomain
  credentials on `app.soleur.ai` and `deploy.soleur.ai` (caught by `user-impact-reviewer` in
  PR #3974). It cannot be evicted to make room.
- Consolidating rules 1–8 into one would need `regex_replace()` / `substring()`, which are
  Business-tier functions.
- And the ACME carve-out frees nothing when retired, because it is a clause and not a rule
  (R1, above).

### (ii) A `_redirects` file in the Eleventy build artifact — **rejected**

Superficially the cheapest option, and it is the one Cloudflare's own documentation rules out:
**domain-level redirects in `_redirects` are documented as unsupported**, and the doc cites this
exact `www` → apex shape as the case it does not handle. Two repo-local reasons compound it: the
canonical-host build gate in `deploy-docs.yml` would reject the file's contents on every build,
and the guard assertion would then have to live in `eleventy.config.js`, which is outside
`infra-validation.yml`'s `paths:` filter — so the chokepoint would be unguarded in CI.

### (iii) Cloudflare Bulk Redirects (account-level) — **CHOSEN**

A different product on a different phase (`http_request_redirect`), account-scoped, with its own
Free quota (15 rules / 5 lists) — so the `http_request_dynamic_redirect` cap does not bind at all.
It is already wired in this repo (`apps/web-platform/infra/seo-bulk-redirects.tf` holds the legal
redirects), the token scope was already granted post-#5092, and it is what Cloudflare's own
www-redirect guide prescribes for a Pages project.

Two implementation choices inside (iii), both deliberate:

- **A separate `cloudflare_list` rather than a 13th item in `legal_redirects`.** Every existing
  item carries `include_subdomains = "enabled"`, so `www.soleur.ai/pages/legal/<slug>.html`
  already matches an apex item today; adding a www catch-all to the same list would make the
  winner depend on undocumented list-entry precedence. Rules **within a ruleset** evaluate in
  declaration order, first-match-wins — a property this repo already relies on and documents —
  so the legal rule is declared first and the www rule second, and precedence becomes explicit
  and testable.
- **`www` stays attached to the Pages project as a second custom domain**, diverging from
  Cloudflare's guide (which parks www at `192.0.2.1`, an RFC 5737 black hole). Cloudflare
  documents that Bulk Redirects run in front of a Pages project, so the redirect still wins.
  The divergence buys a better failure mode: if the redirect ever stops firing, www serves the
  site (duplicate content, already covered by the apex `<link rel="canonical">` and the
  canonical-host build gate) instead of a hard Cloudflare 522 on an HSTS-preloaded host. Both
  are caught by `sentry_uptime_monitor.soleur_www` within one confirmation interval, so
  detection is a wash and the severity is not.

Not reconsidered here, because the migration does not touch them: Rule 10, its ACME carve-out
clause, `always_use_https = "off"`, and the `ssl = "full"` Configuration Rule.
