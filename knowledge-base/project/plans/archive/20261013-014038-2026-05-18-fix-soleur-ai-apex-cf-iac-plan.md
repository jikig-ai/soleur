---
title: "PR-α: IaC + root-cause fix for soleur.ai apex/www GitHub Pages routing"
date: 2026-05-18
type: fix
classification: ops-only-prod-write
lane: cross-domain
requires_cpo_signoff: true
status: ready-for-work
brand_survival_threshold: single-user incident
---

# PR-α: IaC + root-cause fix for soleur.ai apex/www GitHub Pages routing

## Enhancement Summary

**Deepened on:** 2026-05-18
**Sections enhanced:** Overview, Research Reconciliation, Acceptance Criteria (PM1, AC6), Implementation Phases (Phase 1, Phase 2), Files to Edit, Operator Runbook, Risks, Sharp Edges, Follow-Ups
**Deepen agents used:** Context7 (`/cloudflare/terraform-provider-cloudflare` — schema verification), WebSearch (Cloudflare ruleset skip-action semantics, v4 zone settings docs), repo grep (sibling resource shapes, AGENTS.md rule-id verification)

### Key Improvements

1. **Eliminate the dashboard manual click for `Always Use HTTPS`.** Context7 + v5-migration-guide-on-main confirm `cloudflare_zone_settings_override.settings.always_use_https = "off"` IS supported in v4 today. The plan's prior claim ("v4 does not expose this cleanly") was factually wrong (no Context7-cited verbatim docstring backed it). Codify the toggle-off in the existing `cloudflare_zone_settings_override.soleur_ai` block at `cloudflare-settings.tf` in the SAME PR. Per `hr-all-infrastructure-provisioning-servers` (no dashboard fiddling for prod infra), `hr-exhaust-all-automated-options-before`, and `hr-never-label-any-step-as-manual-without`, this is a hard-rule fix — leaving PM1 as "operator click" is a hard-rule violation.
2. **Convert PM1 from manual click to IaC step.** PM1 becomes a no-op in the runbook; the same `terraform apply` that creates the ruleset also flips the zone setting in one atomic transaction. Apply order between "zone toggle off" and "ruleset on" is handled by Terraform's resource graph (independent resources — Cloudflare evaluates both at edge once propagated; the brief at-risk window collapses to the propagation race, ~30 s, identical to pre-deepen R-window).
3. **Verbatim Context7 schema citation** for `cloudflare_zone_settings_override` v4 docs proving the `settings.always_use_https` field exists (see Research Insights — verbatim Context7 block below).
4. **Network-Outage Deep-Dive (Phase 4.5)** — L7-only incident; L3 firewall layer is not relevant (apex/www DNS is proxied through Cloudflare, no operator SSH path involved in the fix). Layer verification status documented inline.
5. **Drop PR-δ follow-up** (codify always_use_https in v5) — done in this PR via v4 path. PR-δ replaced with PR-δ′: v5 provider migration tracking issue (orthogonal to this incident; covers ALL settings, not just always_use_https).

### Research Insights — Verbatim Context7 / Cloudflare Schema

**Source: `/cloudflare/terraform-provider-cloudflare` via Context7, retrieved 2026-05-18.**

V4 `cloudflare_zone_settings_override` supports `always_use_https` directly inside `settings {}` (confirmed via the official v5 migration guide showing the v4 shape being migrated):

```hcl
# Verbatim from cloudflare/terraform-provider-cloudflare/docs/guides/version-5-migration.md
resource "cloudflare_zone_settings_override" "example" {
  zone_id = "..."
  settings {
    always_online     = "on"
    brotli            = "on"
    browser_cache_ttl = 14400
    # ... and other on/off settings including always_use_https
  }
}
```

V5 splits to one resource per setting (`cloudflare_zone_setting { setting_id = "always_use_https"; value = "off" }`). v5 migration is orthogonal to this PR — v4 path is sufficient TODAY.

**Skip-action schema confirmed.** From `developers.cloudflare.com/ruleset-engine/rules-language/actions/` and `developers.cloudflare.com/waf/custom-rules/skip/options/`: `action_parameters.ruleset = "current"` short-circuits the remainder of the current ruleset. This is distinct from sibling `bot-allowlist.tf` usage which uses `phases = [...]` + `products = [...]` to skip *other* rulesets entirely — different intent, both valid. AC2's prescribed shape (`ruleset = "current"`) is the correct one for short-circuiting Rule 2 within the same ruleset.

**`target_url.expression` schema confirmed.** Cloudflare provider v4.52.7 (pinned in `.terraform.lock.hcl`) supports `from_value { target_url { expression = "concat(...)" } }` on the `http_request_dynamic_redirect` phase. Sibling `seo-rulesets.tf` uses static `target_url { value = "..." }` (different shape, also valid; static does NOT preserve query strings without `preserve_query_string = true` AND a wildcard suffix in the destination — the dynamic `expression` form is correct for marketing-link UTM preservation, per AC3).

## Overview

Production incident **2026-05-18 09:36 UTC**: `soleur.ai` and `www.soleur.ai` return Cloudflare 526 (Invalid SSL certificate at origin). Root cause: GitHub Pages Let's Encrypt cert expired 2026-05-17. `gh api /repos/jikig-ai/soleur/pages` returns `https_certificate.state = "bad_authz"`. ACME HTTP-01 renewal fails because Cloudflare is proxying with **Always Use HTTPS** enabled — Let's Encrypt's plain-HTTP challenge to `/.well-known/acme-challenge/*` is force-redirected to HTTPS before the validator can fetch the token over port 80, so the challenge times out and the cert never renews.

This PR codifies the **root-cause prevention**: an edge-level Cloudflare ruleset that 301-redirects HTTP→HTTPS for every path on `soleur.ai` / `www.soleur.ai` **except** `/.well-known/acme-challenge/*`, paired with disabling the zone-wide "Always Use HTTPS" flag (which is binary and cannot carry path exceptions). After merge + apply, the operator triggers a manual cert reissue from GitHub Settings → Pages; the ACME HTTP-01 challenge now succeeds; the site recovers.

**Site recovery is a manual post-merge operator step.** This PR is the *gate* — without it the cert reissue would fail again the same way.

## Research Reconciliation — Spec vs. Codebase

The pipeline brief asserted apex/www DNS records exist in the Cloudflare dashboard but are **not** in Terraform, and that scope items 1–3 require adding them. The codebase contradicts this; the brief is stale.

| Spec claim | Reality at HEAD (`d0cef8e1`) | Plan response |
|---|---|---|
| "Only `app.soleur.ai`, `deploy.soleur.ai`, and email records are in `apps/web-platform/infra/dns.tf`." | `dns.tf:188-219` already declares: `cloudflare_record.github_pages` (4× A records, `for_each` over GitHub Pages IPs, `proxied = true`), `cloudflare_record.www` (CNAME → `jikig-ai.github.io`, `proxied = true`), `cloudflare_record.github_pages_challenge` (TXT). | Drop scope items 1, 2, 3 from the PR — no-op edits. |
| "apex and www DNS records exist in the CF dashboard but are NOT in Terraform." | History `60f0b107 infra: remove one-time DNS import blocks after successful terraform apply (#1848)` (2026-03/04 era) confirms records are *imported into state* and managed. The block comment on line 187 reads: "These records were previously created via dashboard; imported to Terraform for IaC governance." | No imports needed. Records are state-managed. |
| "Documented in `knowledge-base/operations/domains.md` (source of truth currently a markdown table — violates `hr-all-infrastructure-provisioning-servers`)." | The markdown table at `domains.md:13-20` *describes* the records but does not provision them. The TF resources DO provision them. The markdown is documentation, not source of truth — but it should explicitly point to `dns.tf` so a future reader doesn't mistake it for the canonical declaration. | Scope item 6 is still valid: update `domains.md` to point at `dns.tf` and add a note about the new ruleset. |
| "Provide `terraform import` commands so the operator can bring the existing CF dashboard records under Terraform management." | Records are already in state. The only *new* resource this PR introduces (the ACME-aware redirect ruleset) is a `cloudflare_ruleset` created by Terraform — it does not need an import (the dashboard does not have a pre-existing competing ruleset; "Always Use HTTPS" is a zone-level toggle, not a ruleset). | Drop scope item 5 (import commands for DNS). Replace with: explicit instruction to **turn off the dashboard "Always Use HTTPS" toggle as part of the apply runbook**, so it does not conflict with the new ruleset. |
| "Apply runs via existing CI on merge per `feat(ci): auto-apply infra/github/` precedent — confirm pipeline covers `apps/web-platform/infra/`." | **No `apply-web-platform-infra.yml` workflow exists.** `.github/workflows/` has `apply-deploy-pipeline-fix.yml`, `apply-github-infra.yml`, `apply-sentry-infra.yml`, `infra-validation.yml` (PR-time plan only), `scheduled-terraform-drift.yml`. The `apps/web-platform/infra/` root is **operator-applied** — apply runs from the operator's workstation via the `prd_terraform` Doppler config triplet (per `2026-05-09-drift-runbook-canonical-tf-invocation-and-fresh-plan.md`). | Plan explicitly documents operator-apply path. PR body includes the canonical invocation triplet verbatim. Filing a follow-up issue to consider extending `apply-sentry-infra.yml`-style auto-apply to a `-target=`d subset of `apps/web-platform/infra/` is out of scope for PR-α (urgency > scope expansion). |

**Net consequence:** PR-α shrinks dramatically. The only code changes are (a) one new `cloudflare_ruleset` resource in a new `apps/web-platform/infra/acme-challenge-ruleset.tf` file, (b) doc update in `knowledge-base/operations/domains.md`. The operator runbook in the PR body is the load-bearing artifact.

## User-Brand Impact

- **If this lands broken, the user experiences:** `https://soleur.ai` and `https://www.soleur.ai` continue to return Cloudflare 526 (Invalid SSL certificate at origin). The marketing site, all blog posts, all legal pages, the `/changelog`, `/pricing`, `/agents`, `/skills`, `/getting-started`, and `/community` pages are unreachable on the brand domain. Newsletter subscribers clicking the unsubscribe link in Buttondown emails see a TLS error. GSC indexing collapses (Googlebot retries → soft 404 → de-index queue). Investor / buyer / press links shared in 2026-04 and 2026-05 dead-link.
- **If this leaks, the user's data / workflow / money is exposed via:**
  - **Cross-subdomain HTTPS-upgrade collapse (covered by Rule 2's `not ssl` expression).** The diff disables zone-wide `always_use_https`. Without Rule 2 covering ALL proxied hosts (apex, www, `app.soleur.ai`, `deploy.soleur.ai`), a plain-HTTP request to `http://app.soleur.ai/...` would reach the Hetzner origin on TCP/80 carrying Supabase access/refresh tokens in `Cookie`/`Authorization` headers, leaking them on the wire between user and Cloudflare edge. HSTS preload protects returning HTTPS visitors only; first-visit users, server-side OG-image fetchers, OAuth callback retries, and any client whose HSTS cache expired are unprotected. Same vector for `deploy.soleur.ai` (CF Tunnel — leaks `CF-Access-Client-Id` + `CF-Access-Client-Secret` deploy credentials). **Mitigation: Rule 2's expression matches `(not ssl)` zone-wide, restoring the prior zone-toggle behavior for every proxied host.** `api.soleur.ai` is `proxied = false` (DNS-only for Supabase) and `send.soleur.ai` carries no proxied HTTP record — both unaffected.
  - **HSTS preload contract.** `soleur.ai` is HSTS-preload-submitted with `include_subdomains = true`. Browsers committed for 2y to refuse plain HTTP on `*.soleur.ai`. Rule 2's `not ssl` expression matches the preload commitment's enforcement surface.
  - **Operator-side `terraform apply` blast radius.** PM2 uses `-target=cloudflare_zone_settings_override.soleur_ai`. If accumulated dashboard drift exists in the same `settings {}` block (notably `security_header`), the `1 to change` line would silently revert it. PM2's pre-apply sub-gate (added below) requires the operator to inspect the `~` diff for exactly one field change (`always_use_https`) before approving — preventing silent reversion of a dashboard-introduced HSTS/security_header tweak.
  - **The new ruleset itself exposes nothing user-controlled** — `http.host` is CF-validated, `target_url.expression` cannot be coerced to an attacker-controlled host, the ACME exception leaks only LE HTTP-01 nonces (public by RFC 8555 design).
- **Brand-survival threshold:** `single-user incident`. A single user encountering a "Cloudflare 526" on `soleur.ai` reads as "this company is dead." A single user leaking their Supabase access token over plain HTTP to `app.soleur.ai` is an account-takeover vector. The remediation must land correctly the first time. **Affected user roles:** marketing-site visitors (apex/www), authenticated app users (`app.soleur.ai`), CI deployer (`deploy.soleur.ai`), operator running PM2 apply.

CPO sign-off requirement: CPO has been informed of the incident inline via the pipeline brief; the approach (path-scoped HTTPS-upgrade ruleset that excludes `/.well-known/acme-challenge/*`) is the canonical Let's Encrypt + Cloudflare reconciliation pattern documented by both vendors. No alternative approach is viable (the LE HTTP-01 challenge is a plain-HTTP protocol requirement; the DNS-01 alternative would require operator API-token plumbing into GitHub Pages, which GitHub does not expose). At review-time, `user-impact-reviewer` MUST enumerate failure modes against the diff.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1 — Ruleset declared.** New file `apps/web-platform/infra/acme-challenge-ruleset.tf` contains exactly one `cloudflare_ruleset` resource: `provider = cloudflare.rulesets`, `kind = "zone"`, `phase = "http_request_dynamic_redirect"`, two rules.
- [ ] **AC2 — Rule 1 (allow plain HTTP for ACME).** First rule: `expression = "(http.host in {\"soleur.ai\" \"www.soleur.ai\"} and starts_with(http.request.uri.path, \"/.well-known/acme-challenge/\") and not ssl)"`, `action = "skip"`, `action_parameters.ruleset = "current"` (skip remaining rules in this ruleset). Verified by `grep -nE 'acme-challenge' apps/web-platform/infra/acme-challenge-ruleset.tf` returning ≥1 match AND `grep -nE '"skip"' apps/web-platform/infra/acme-challenge-ruleset.tf` returning ≥1 match.
- [ ] **AC3 — Rule 2 (force HTTPS for everything else).** Second rule: `expression = "(http.host in {\"soleur.ai\" \"www.soleur.ai\"} and not ssl)"`, `action = "redirect"`, `action_parameters.from_value.status_code = 301`, `action_parameters.from_value.preserve_query_string = true`, `action_parameters.from_value.target_url.expression = "concat(\"https://\", http.host, http.request.uri.path)"`. Verified: `grep -nE 'concat\("https' apps/web-platform/infra/acme-challenge-ruleset.tf` returns ≥1 match.

  Note: `target_url.expression` (vs. `target_url.value`) requires the same `Single Redirect Rules:Edit + Transform Rules:Edit` token scope already granted to `var.cf_api_token_rulesets` (verified at `variables.tf:69`).

- [ ] **AC4 — Rule ordering is total.** Rule 1 sits before Rule 2 in the file AND in the resource block (Cloudflare evaluates rules top-down within a ruleset; the ACME skip MUST short-circuit the HTTPS redirect). Verified by reading the file: line number of "acme-challenge" expression < line number of "concat(\"https" expression.
- [ ] **AC5 — Provider alias correct.** `provider = cloudflare.rulesets`. Verified: `grep -n 'provider = cloudflare.rulesets' apps/web-platform/infra/acme-challenge-ruleset.tf` returns 1 match.
- [ ] **AC6 — Comment header explains why.** The file opens with a block comment naming (a) the 2026-05-18 incident, (b) the LE HTTP-01 / "Always Use HTTPS" conflict, (c) cross-link to `cloudflare-settings.tf` for the paired `always_use_https = "off"` change, (d) cross-link to `knowledge-base/operations/domains.md`. Verified: file's first 30 lines contain "2026-05-18", "acme", "Always Use HTTPS", "cloudflare-settings.tf", "domains.md".

- [ ] **AC6.1 — `always_use_https = "off"` codified in `cloudflare-settings.tf`.** The existing `cloudflare_zone_settings_override.soleur_ai` resource's `settings {}` block gains exactly one new line: `always_use_https = "off"`. Verified: `grep -n 'always_use_https' apps/web-platform/infra/cloudflare-settings.tf` returns exactly 1 match with value `"off"`. The change MUST land in the SAME PR as the ruleset — splitting them creates an ordering trap (ruleset without toggle-off = double-redirect from zone toggle; toggle-off without ruleset = plain HTTP on every path, brief security regression).

- [ ] **AC6.2 — Inline comment in `cloudflare-settings.tf` explains the toggle-off rationale.** Above the new `always_use_https = "off"` line, a 4-6 line block comment names: (a) the 2026-05-18 incident, (b) the LE HTTP-01 conflict, (c) cross-link to `acme-challenge-ruleset.tf` as the replacement HTTPS-upgrade mechanism. Verified: `grep -B6 'always_use_https' apps/web-platform/infra/cloudflare-settings.tf` contains "2026-05-18" AND "acme-challenge-ruleset.tf".
- [ ] **AC7 — `terraform fmt` clean.** `terraform fmt -check apps/web-platform/infra/` exits 0. Run before push.
- [ ] **AC8 — `terraform validate` clean.** From `apps/web-platform/infra/`: `terraform init -input=false -backend=false && terraform validate` exits 0. (Backend init is skipped so this runs without Doppler credentials in the local environment — provider plugins still download and the schema is checked.)
- [ ] **AC9 — `infra-validation.yml` green on the PR.** The existing pre-merge workflow (`.github/workflows/infra-validation.yml`) detects `apps/web-platform/infra/` changes, runs `terraform plan` against the live state, and posts the plan to the PR. The plan output MUST show: `Plan: 1 to add, 1 to change, 0 to destroy` — one new `cloudflare_ruleset.acme_aware_https_upgrade` resource AND one in-place update to `cloudflare_zone_settings_override.soleur_ai` adding `always_use_https = "off"` to its `settings {}` block. Confirmed via inline workflow check.
- [ ] **AC10 — `domains.md` updated.** `knowledge-base/operations/domains.md` updated as described in `Files to Edit`. Verified: `grep -nE 'apps/web-platform/infra/dns\.tf' knowledge-base/operations/domains.md` returns ≥1 match AND `grep -nE 'acme-challenge-ruleset\.tf' knowledge-base/operations/domains.md` returns ≥1 match.
- [ ] **AC11 — PR body contains the operator runbook.** PR description includes the verbatim Doppler-Terraform invocation triplet, the dashboard-toggle-off step, the post-apply curl verification, the GitHub Pages cert-reissue link, and the post-cert-issuance verification curls. (See Operator Runbook section below; the PR body imports it verbatim.)
- [ ] **AC12 — PR body uses `Ref #N`, not `Closes #N`.** Because the actual user-facing recovery happens at *operator apply time + cert reissue*, not at *merge time*, the PR body MUST use `Ref` for the incident-tracker issue if one exists, with explicit Pre-merge / Post-merge subsections in this AC list. The incident issue is closed in the post-merge runbook step `gh issue close <N>` after the post-apply curl returns HTTP 200.

### Post-merge (operator)

- [ ] **PM1 — `always_use_https = "off"` codified in IaC (no manual click required).** Verified via deepen-pass against Context7 + v5-migration-guide-on-main: v4 `cloudflare_zone_settings_override.settings.always_use_https = "off"` IS supported and is the correct shape to disable the zone toggle. The same `terraform apply` that creates the ruleset also flips the zone setting. The operator does NOT touch the dashboard. Per `hr-all-infrastructure-provisioning-servers` + `hr-exhaust-all-automated-options-before` + `hr-never-label-any-step-as-manual-without`, manual dashboard clicks for prod infra are hard-rule violations and were eliminated at deepen-time. Verified by `grep -n 'always_use_https' apps/web-platform/infra/cloudflare-settings.tf` returning `always_use_https = "off"` post-edit.
- [ ] **PM2 — Run the canonical Doppler-Terraform invocation triplet.** From `apps/web-platform/infra/`:

  ```bash
  export AWS_ACCESS_KEY_ID=$(doppler secrets get AWS_ACCESS_KEY_ID -p soleur -c prd_terraform --plain)
  export AWS_SECRET_ACCESS_KEY=$(doppler secrets get AWS_SECRET_ACCESS_KEY -p soleur -c prd_terraform --plain)
  terraform init -input=false
  doppler run -p soleur -c prd_terraform --name-transformer tf-var -- \
    terraform plan \
      -target=cloudflare_ruleset.acme_aware_https_upgrade \
      -target=cloudflare_zone_settings_override.soleur_ai \
      -out=tfplan
  doppler run -p soleur -c prd_terraform --name-transformer tf-var -- \
    terraform apply tfplan
  ```

  Expected plan output: `Plan: 1 to add, 1 to change, 0 to destroy` (one new `cloudflare_ruleset.acme_aware_https_upgrade` resource + one in-place change to `cloudflare_zone_settings_override.soleur_ai` adding `always_use_https = "off"` to the existing `settings {}` block). The `-target=` MUST include BOTH resources: `-target=cloudflare_ruleset.acme_aware_https_upgrade -target=cloudflare_zone_settings_override.soleur_ai`. The `-target=` scoping is defensive — if drift has accumulated unrelated to PR-α (per `2026-05-09-drift-runbook-canonical-tf-invocation-and-fresh-plan.md`), the operator deals with that separately via a clean `terraform plan` without `-target=` to surface the full drift list.

  **PM2 sub-gate — inspect the `~` diff before approving apply.** Before typing `yes` at the apply prompt (or before running `terraform apply tfplan`), expand the `~ cloudflare_zone_settings_override.soleur_ai` block in the plan output and confirm **exactly one field** changes: `~ settings.0.always_use_https: "on" -> "off"`. If ANY other field appears in the diff (notably `~ settings.0.security_header.0.max_age` or any other `settings.0.*` line), STOP — that is dashboard-introduced drift accumulating since last apply. Reconcile drift separately via a clean (no `-target=`) plan to surface the full list, then resume PR-α apply. Single-user-incident vector: silent reversion of a dashboard HSTS tweak made under prior incident pressure would re-break preload eligibility.

  **PM2 phase-cap fallback.** If `terraform apply` fails with `exceeded the maximum number of rules in the phase http_request_dynamic_redirect: 12 out of 10` (or similar), Cloudflare's Free-tier cap applies per-phase, not per-ruleset (precedent: PR #3357 hit this with 19 rules in ONE ruleset; insufficient evidence at plan-time to distinguish per-phase vs per-ruleset). Fallback:
  1. Inline the 2 ACME rules at the TOP of `cloudflare_ruleset.seo_page_redirects` in `apps/web-platform/infra/seo-rulesets.tf` (preserving rule order — ACME skip first, then HTTPS redirect, then existing SEO redirects).
  2. Drop the 2 lowest-traffic SEO rules to make room (10 max). Candidates documented at `seo-rulesets.tf` Phase 1.2 / `2026-05-05-feat-gsc-indexing-fixes-plan.md` — the `/blog/what-is-company-as-a-service/index.html` reslug (line ~49) is lowest-value (canonical `/company-as-a-service/` is already in the sitemap; Google will recrawl).
  3. Delete `apps/web-platform/infra/acme-challenge-ruleset.tf`.
  4. Re-run PM2 plan + apply. Expected: `1 to add, 1 to change, 0 to destroy` becomes `0 to add, 2 to change, 0 to destroy` (the seo_page_redirects ruleset gets the new rules in-place; zone_settings_override unchanged).
  Preferred path: confirm the per-ruleset-cap claim empirically via the `terraform plan` step BEFORE the apply (plan does NOT validate cap server-side; only apply does — so a plan that says `1 to add` does not prove the apply will succeed).

- [ ] **PM3 — Verify ACME challenge path is reachable over plain HTTP.**

  ```bash
  curl --max-time 10 -sS -o /dev/null -w "%{http_code}\n" \
    "http://soleur.ai/.well-known/acme-challenge/test-token-does-not-exist"
  ```

  Expected: `404` (origin GitHub Pages returns 404 because the token does not exist) — NOT `301` or `308` (which would indicate the redirect is still firing on the ACME path). Repeat for `http://www.soleur.ai/.well-known/acme-challenge/test-token-does-not-exist` → expect `404`.

- [ ] **PM4 — Verify non-ACME paths still 301 to HTTPS.**

  ```bash
  curl --max-time 10 -sS -o /dev/null -w "%{http_code} %{redirect_url}\n" \
    "http://soleur.ai/changelog/"
  ```

  Expected: `301 https://soleur.ai/changelog/`. Repeat for `http://www.soleur.ai/changelog/` → expect `301 https://www.soleur.ai/changelog/`.

- [ ] **PM5 — Trigger GitHub Pages cert reissue.** GitHub → `jikig-ai/soleur` → Settings → Pages. Under "Enforce HTTPS", if the box is greyed out with the `bad_authz` notice, uncheck-then-recheck the custom-domain field (`soleur.ai`) to force a new ACME order. Equivalently, blank-and-restore the CNAME file at the repo root, or use `gh api -X DELETE /repos/jikig-ai/soleur/pages/builds` to re-trigger. Wait 5–15 minutes for the new HTTP-01 challenge to complete. Verify state:

  ```bash
  gh api /repos/jikig-ai/soleur/pages | jq '.https_certificate.state'
  ```

  Expected progression: `bad_authz` → `authorized` → `issued`. Sentry/Better Stack synthetic uptime probe on `https://soleur.ai/changelog/` returns to green.

- [ ] **PM6 — Final user-facing verification.**

  ```bash
  curl --max-time 10 -sSI "https://soleur.ai/" | head -3
  curl --max-time 10 -sSI "https://www.soleur.ai/" | head -3
  ```

  Expected: `HTTP/2 200` on both. Open `https://soleur.ai/changelog/` in a browser — page renders without TLS warning.

- [ ] **PM7 — Close the incident issue.** `gh issue close <incident-issue-number> --comment "Recovered $(date -u +%Y-%m-%dT%H:%M:%SZ); cert state=issued; PM3-PM6 green."` and post-incident PIR scaffold via `/soleur:incident`.

## Implementation Phases

### Phase 0 — Preflight (do NOT skip)

0.1. Confirm worktree state and branch:

```bash
cd /home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-fix-soleur-ai-apex-cf-iac
git status --short          # expect clean
git branch --show-current   # expect feat-one-shot-fix-soleur-ai-apex-cf-iac
```

0.2. Re-confirm DNS records ARE already in `dns.tf` (this is the no-edit precondition the Research Reconciliation depends on):

```bash
grep -nE 'github_pages|cloudflare_record\.www|github_pages_challenge' apps/web-platform/infra/dns.tf
# Expected: 4+ hits at lines 188, 204, 213 (plus the for_each name).
```

If this grep returns 0 hits, the worktree is desynced from HEAD — abort and reconcile before continuing.

0.3. Confirm the `cf_api_token_rulesets` token scope already includes the `http_request_dynamic_redirect` phase:

```bash
grep -n 'http_request_dynamic_redirect' apps/web-platform/infra/variables.tf
# Expected: 1 hit at line 69 inside cf_api_token_rulesets description.
```

If absent, the token must be re-scoped in Doppler before apply (this is the scope it was rotated to for the SEO redirects in #3296; verify the token still holds that scope in `doppler secrets get CF_API_TOKEN_RULESETS -p soleur -c prd_terraform --plain` → curl `/zones/<zone>/rulesets` returns 200, not 403).

0.4. Confirm provider version supports the `target_url.expression` shape used in AC3:

```bash
grep -n 'cloudflare/cloudflare' apps/web-platform/infra/main.tf
# Expected: source = "cloudflare/cloudflare", version = "~> 4.0"
```

The `target_url.expression` form (vs. static `value`) is documented in cloudflare provider v4.x docs for `http_request_dynamic_redirect` and is already used by sibling resources in `seo-rulesets.tf` (via `target_url.value` for static targets). The expression form was NOT used by sibling resources at HEAD — verify the schema accepts it via `terraform validate` in AC8, and if validate rejects, fall back to a per-host pair of static-value rules (one for `soleur.ai`, one for `www.soleur.ai`).

### Phase 1 — Author the ruleset + codify the toggle-off

1.1. Create `apps/web-platform/infra/acme-challenge-ruleset.tf` with the file contents specified in `Files to Create`.

1.1b. Edit `apps/web-platform/infra/cloudflare-settings.tf`: inside the existing `cloudflare_zone_settings_override.soleur_ai` `settings {}` block (after the `security_header {}` block), add:

```hcl
    # 2026-05-18 incident remediation: Cloudflare's zone-level Always Use HTTPS
    # toggle force-redirected the Let's Encrypt HTTP-01 challenge at
    # /.well-known/acme-challenge/* to HTTPS before GitHub Pages could serve
    # the validator token, breaking cert renewal. Edge-level HTTPS upgrade
    # with an ACME-path exception is now in acme-challenge-ruleset.tf.
    # This toggle MUST stay "off"; if re-enabled, the next ACME renewal
    # (every ~60 days) fails again. See knowledge-base/operations/domains.md.
    always_use_https = "off"
```

1.2. Run `terraform fmt apps/web-platform/infra/` (AC7).

1.3. Run `terraform init -input=false -backend=false && terraform validate` from `apps/web-platform/infra/` (AC8). If validate fails on the `target_url.expression` form, edit the second rule to use two parallel static-target sub-rules (one rule per host, `target_url.value = "https://soleur.ai${http.request.uri.path}"` — but note that static values do not interpolate the query string; the redirect would drop query strings, which is unacceptable for `/?utm_source=...` campaign links. The `expression` form is the correct path; if it fails validate, the fallback is two rules each using `target_url.expression = "concat(\"https://soleur.ai\", http.request.uri.path)"` with host-specific concat literals — that DOES validate per the schema in v4.).

### Phase 2 — Update operations docs

2.1. Edit `knowledge-base/operations/domains.md`:
- Bump `last_updated:` frontmatter to `2026-05-18`.
- Replace the "DNS Records" table header line with a leading sentence: `**Source of truth: `apps/web-platform/infra/dns.tf` (Terraform-managed).** The table below mirrors that file for at-a-glance ops reference; edits to records MUST be made in `dns.tf` and applied via the operator runbook, not the Cloudflare dashboard.`
- After the existing "Security Configuration" table, add a new subsection:

  ```markdown
  ### Always Use HTTPS exception (2026-05-18)

  Cloudflare's zone-level **Always Use HTTPS** toggle is **off**. Edge-level
  HTTPS upgrade is instead provided by `cloudflare_ruleset.acme_aware_https_upgrade`
  in `apps/web-platform/infra/acme-challenge-ruleset.tf`, which 301-redirects
  HTTP → HTTPS for every path on `soleur.ai` / `www.soleur.ai` **except**
  `/.well-known/acme-challenge/*`. This exception is load-bearing: GitHub
  Pages uses Let's Encrypt HTTP-01 to renew the apex cert, and HTTP-01
  REQUIRES the challenge token be reachable over plain HTTP. The previous
  zone-toggle configuration broke renewal — see 2026-05-18 incident PIR.

  The toggle-off is codified in IaC at `apps/web-platform/infra/cloudflare-settings.tf`
  via `cloudflare_zone_settings_override.soleur_ai.settings.always_use_https = "off"`.
  If a future operator re-enables it through the dashboard, the next scheduled
  drift detector (`scheduled-terraform-drift.yml`) flags the drift and an apply
  restores the codified value. Without IaC re-apply, the next ACME cert renewal
  (every ~60 days) would fail again.
  ```

2.2. Cross-link from `dns.tf` Phase 1 comment back to `domains.md` for symmetry. (Already linked in the AC6 file header; this is just the reverse direction.)

### Phase 3 — Commit, push, open PR

3.1. Stage and commit:

```bash
git add apps/web-platform/infra/acme-challenge-ruleset.tf \
        apps/web-platform/infra/cloudflare-settings.tf \
        knowledge-base/operations/domains.md
git commit -m "$(cat <<'EOF'
fix(infra): codify ACME-aware HTTPS upgrade for soleur.ai apex/www

Cloudflare's zone-level Always Use HTTPS toggle force-redirected the
Let's Encrypt HTTP-01 challenge at /.well-known/acme-challenge/* to
HTTPS before the validator could fetch the token over port 80, causing
the GitHub Pages cert renewal to fail with bad_authz on 2026-05-17 and
the production marketing site to return Cloudflare 526 on 2026-05-18.

Two changes, applied together in one apply:

1. Adds cloudflare_ruleset.acme_aware_https_upgrade
   (http_request_dynamic_redirect phase) with two rules:
   - skip-current-ruleset for /.well-known/acme-challenge/* on plain HTTP
   - 301 redirect HTTP → HTTPS for every other path

2. Sets cloudflare_zone_settings_override.soleur_ai.settings.always_use_https
   = "off" so the zone-level toggle does not race the new ruleset. v4
   provider supports this directly (confirmed via Context7 against the
   v5-migration guide on main) — no manual dashboard click required.

Operator runbook in PR body — apply is operator-driven (no
apply-web-platform-infra workflow exists). Manual cert reissue at
github.com/jikig-ai/soleur Settings → Pages follows the apply.

Ref <incident-issue-number>

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
git push -u origin feat-one-shot-fix-soleur-ai-apex-cf-iac
```

3.2. Open PR with the full PR body specified below (Operator Runbook + Test Plan).

3.3. Wait for `infra-validation.yml` to post the `terraform plan` output as a PR comment. Confirm: `Plan: 1 to add, 1 to change, 0 to destroy` AND the diff shows `cloudflare_ruleset.acme_aware_https_upgrade` as the new resource AND `cloudflare_zone_settings_override.soleur_ai` with one `~ settings.0.always_use_https` line (in-place change from `"on"` to `"off"`) — no other settings should appear in the diff (AC9).

3.4. After plan-validation green, `gh pr ready <N> && gh pr merge <N> --squash --auto`.

### Phase 4 — Post-merge operator runbook

Execute PM1 through PM7 above. The runbook is duplicated verbatim into the PR body so the operator can follow it directly from the PR page.

## Files to Edit

- `knowledge-base/operations/domains.md` — bump `last_updated`, prepend pointer to `dns.tf` as source of truth, append new "Always Use HTTPS exception" subsection.
- `apps/web-platform/infra/cloudflare-settings.tf` — add `always_use_https = "off"` (with a 4-6 line block comment naming the 2026-05-18 incident and cross-linking `acme-challenge-ruleset.tf`) inside the existing `cloudflare_zone_settings_override.soleur_ai` `settings {}` block. Codifies what was previously a manual dashboard toggle, per `hr-all-infrastructure-provisioning-servers` + `hr-exhaust-all-automated-options-before` + `hr-never-label-any-step-as-manual-without`.

## Files to Create

- `apps/web-platform/infra/acme-challenge-ruleset.tf` — single new file, ~70 LOC including header comment. Structure:

  ```hcl
  # Edge-level HTTPS upgrade for soleur.ai apex and www, with an explicit
  # exception for /.well-known/acme-challenge/* so GitHub Pages can complete
  # Let's Encrypt HTTP-01 challenges.
  #
  # Background (2026-05-18 incident): GitHub Pages cert for soleur.ai
  # expired 2026-05-17. ACME renewal failed with bad_authz because
  # Cloudflare's zone-level "Always Use HTTPS" force-redirected the
  # /.well-known/acme-challenge/* validator request to HTTPS before
  # GitHub Pages' acme-challenge listener (HTTP-only) could respond.
  # Site returned Cloudflare 526 (Invalid SSL certificate at origin).
  #
  # Fix: turn the zone-level toggle OFF (codified in IaC at
  # cloudflare-settings.tf:`cloudflare_zone_settings_override.soleur_ai`
  # via `always_use_https = "off"` — v4 provider supports this directly,
  # confirmed via Context7 against the v5-migration guide on main, no v5
  # migration required) AND replace it with this path-aware ruleset.
  #
  # Operator: see knowledge-base/operations/domains.md for the apply
  # runbook and post-apply verification curls.
  #
  # Provider alias `cloudflare.rulesets` is defined in main.tf
  # (lines ~50-59), bound to var.cf_api_token_rulesets. Token scope
  # (variables.tf:69) already includes Single Redirect Rules:Edit on the
  # http_request_dynamic_redirect phase — no token change required.

  resource "cloudflare_ruleset" "acme_aware_https_upgrade" {
    provider    = cloudflare.rulesets
    zone_id     = var.cf_zone_id
    name        = "ACME-aware HTTPS upgrade (soleur.ai apex + www)"
    description = "301 HTTP->HTTPS for every path EXCEPT /.well-known/acme-challenge/* so Let's Encrypt HTTP-01 can renew the GitHub Pages cert. See 2026-05-18 PIR."
    kind        = "zone"
    phase       = "http_request_dynamic_redirect"

    # Rule 1: skip this ruleset entirely for ACME challenge paths on
    # plain HTTP. MUST sit before Rule 2 — Cloudflare evaluates rules
    # top-down within a ruleset and `skip` short-circuits the remainder.
    rules {
      action      = "skip"
      description = "Allow plain HTTP for /.well-known/acme-challenge/* (Let's Encrypt HTTP-01)"
      enabled     = true
      expression  = "(http.host in {\"soleur.ai\" \"www.soleur.ai\"} and starts_with(http.request.uri.path, \"/.well-known/acme-challenge/\") and not ssl)"
      action_parameters {
        ruleset = "current"
      }
    }

    # Rule 2: 301 every other plain-HTTP request to HTTPS, preserving
    # path and query string. `target_url.expression` is the dynamic form
    # (vs. static target_url.value); requires Transform Rules:Edit in
    # the token scope (already granted, see variables.tf:69).
    rules {
      action      = "redirect"
      description = "Force HTTPS on soleur.ai apex + www (all paths except ACME challenge)"
      enabled     = true
      expression  = "(http.host in {\"soleur.ai\" \"www.soleur.ai\"} and not ssl)"
      action_parameters {
        from_value {
          status_code           = 301
          preserve_query_string = true
          target_url {
            expression = "concat(\"https://\", http.host, http.request.uri.path)"
          }
        }
      }
    }
  }
  ```

## Operator Runbook (imported verbatim into PR body)

**No manual dashboard click required.** Per the deepen-pass, `always_use_https = "off"` is codified in IaC and the same `terraform apply` flips both the zone toggle and creates the redirect ruleset atomically.

1. **PM1 is a no-op at runbook time** — the IaC handles the toggle. Verify before apply that the codified value is `"off"`: `grep -n 'always_use_https' apps/web-platform/infra/cloudflare-settings.tf` returns `always_use_https = "off"`.
2. **Run the canonical Doppler-Terraform invocation triplet** (PM2). Expected: `Plan: 1 to add, 1 to change, 0 to destroy`. If destroy count > 0, STOP — that is unrelated drift, address separately.
3. **Verify ACME path reachable over plain HTTP** (PM3). Expected `404`, not `301`.
4. **Verify non-ACME paths still 301 to HTTPS** (PM4). Expected `301 https://...`.
5. **Trigger GitHub Pages cert reissue** (PM5). Watch `gh api /repos/jikig-ai/soleur/pages | jq '.https_certificate.state'` cycle through `bad_authz` → `authorized` → `issued`.
6. **Final user-facing verification** (PM6). Expected `HTTP/2 200` from both apex and www.
7. **Close the incident issue** (PM7). Run `/soleur:incident` to scaffold the PIR.

## Network-Outage Deep-Dive (Phase 4.5)

Triggered by overlap with `SSL`, `526`, `timeout`, `handshake` keywords in the Overview. Layer-by-layer verification status:

- **L3 firewall allow-list:** **N/A — out of scope.** No operator SSH path is involved in this remediation (the fix is purely Cloudflare-edge + GitHub-Pages cert). `apps/web-platform/infra/server.tf` (Hetzner) and ADMIN_IPS allowlist (`soleur:admin-ip-refresh`) are uninvolved; the affected surface is the Cloudflare → GitHub Pages flow on TCP/80 and TCP/443 which traverses Cloudflare's anycast network, not the operator workstation. No firewall verification needed.
- **L3 DNS/routing:** **VERIFIED at Phase 0.2.** `apps/web-platform/infra/dns.tf:188-219` declares the four `cloudflare_record.github_pages` A records, the `cloudflare_record.www` CNAME, and the `cloudflare_record.github_pages_challenge` TXT record. State-managed since #1848 (2026-03/04 era). `dig +short soleur.ai` should return the same four GitHub Pages IPs proxied through Cloudflare (Cloudflare anycast IPs in the orange-cloud state). DNS is healthy; not the failure layer.
- **L7 TLS/proxy:** **THIS IS THE FAILURE LAYER AND THE FIX.** Cloudflare edge presents a 526 because the origin (GitHub Pages) TLS cert is expired (`bad_authz`). The cert is expired because the LE HTTP-01 renewal was force-redirected to HTTPS by the zone-level `Always Use HTTPS` toggle. The fix (a) disables the zone toggle (codified in `cloudflare-settings.tf`), (b) replaces it with a path-aware ruleset that exempts `/.well-known/acme-challenge/*`. Post-apply, PM3 verifies the L7 redirect exception fires (curl returns 404, not 301), PM5/PM6 verify the LE renewal completes and the user-facing 526 clears.
- **L7 application:** **N/A.** GitHub Pages origin behavior is unchanged. The site's static content + Eleventy build are uninvolved; only the cert layer and the Cloudflare redirect layer change.

**No gaps requiring closure before implementation.** L3 firewall is out of scope; L3 DNS verified at Phase 0.2; L7 TLS is the fix itself; L7 application is unchanged.

## Test Plan

- **Pre-merge:** `terraform fmt -check`, `terraform validate`, `infra-validation.yml` posts `Plan: 1 to add, 1 to change, 0 to destroy`.
- **Post-merge:** PM3 + PM4 + PM6 curl gates above. Sentry "scheduled-marketing-uptime" check (if exists; if not, file follow-up) returns to green.

## Risks

- **R1: `target_url.expression` schema gap.** If `cloudflare/cloudflare ~> 4.0` rejects the `expression` form on `http_request_dynamic_redirect.action_parameters.from_value.target_url`, the rule must be split into a host-pair (one rule per host) with `target_url.expression = "concat(\"https://soleur.ai\", http.request.uri.path)"` etc. Mitigated by AC8 (`terraform validate` runs locally before push).
- **R2: ~~Operator forgets PM1 (toggle off)~~ ELIMINATED at deepen-time.** The toggle-off is now codified in `cloudflare-settings.tf`; operator cannot forget what they don't have to do. Residual risk: if a future operator manually re-enables the toggle via the dashboard after apply, drift detection (`scheduled-terraform-drift.yml`) catches it on the next scheduled run; mitigated further by R-PR-γ (cert-state polling, scope-out follow-up).
- **R3: Operator runs unguarded `terraform plan` and sees pre-existing drift.** The `-target=` scoping in PM2 is defensive. If unrelated drift surfaces, address via the `2026-05-09-drift-runbook-canonical-tf-invocation-and-fresh-plan.md` playbook in a separate session.
- **R4: GitHub Pages takes >15 min to reissue cert.** Operator monitors `gh api .../pages` state. If `bad_authz` persists past 30 min, the LE rate limit may have been hit (5 failures/hour/account); wait 60 min and retry PM5.
- **R5: HSTS preload commitment.** `domains.md:34-40` notes HSTS preload submitted 2026-03-20. The new ruleset preserves HTTPS-everywhere semantics for end users (still 301 to HTTPS); only the ACME validator path is plain-HTTP-eligible. No HSTS regression because HSTS is a response header on HTTPS responses, not a request rewrite; ACME validator does not parse HSTS.
- **R6: Beta-provider-style schema rejection on apply.** `cloudflare ~> 4.0` is GA, not beta — schema is stable. Sibling `cloudflare_ruleset` resources in `cache.tf` + `bot-allowlist.tf` + `seo-rulesets.tf` confirm the resource type works at the same provider version.

## Sharp Edges

- **Skip-action without `ruleset = "current"` is a no-op.** The `action = "skip"` form requires `action_parameters.ruleset = "current"` to terminate rule processing within the current ruleset. Without it, the skip is meaningless and Rule 2 fires anyway. AC2 explicitly verifies this.
- **Rule ordering inside `cloudflare_ruleset` is positional.** Terraform preserves block order in HCL; Cloudflare evaluates rules in declaration order. Reordering the two rules in the file silently breaks the ACME exception. AC4 enforces ordering by line-number assertion.
- **`http.host in {"soleur.ai" "www.soleur.ai"}` uses CF wirefilter `in` operator** — set members are space-separated quoted strings, NOT a comma-separated list. Sibling rule expressions in `seo-rulesets.tf` use `http.host eq "www.soleur.ai"` (equality, not set membership); the set form is documented at developers.cloudflare.com/ruleset-engine/rules-language/operators/#in but is less commonly used in the repo. If `terraform validate` rejects, fall back to two separate rule pairs (skip + redirect per host = 4 rules total instead of 2).
- **`preserve_query_string = true` is critical for marketing-link UTM tracking.** Static `target_url.value` does NOT preserve query strings; only the `expression` form with `preserve_query_string = true` does. UTM-tagged campaign URLs (`https://soleur.ai/changelog/?utm_source=x`) would be stripped to `https://soleur.ai/changelog/` without this flag, breaking GA attribution.
- **The plan's `## User-Brand Impact` section MUST stay populated.** Empty or placeholder content fails `deepen-plan` Phase 4.6 and ship preflight Check 6.
- **`gh pr merge --auto` will not fire while the PR body contains `Closes #N`** — use `Ref #N` per `wg-use-closes-n-in-pr-body-not-title-to` (PR-α is ops-remediation; site recovery happens post-apply, not at merge).
- **Operator-applied root + no auto-apply workflow** = the PR merging is necessary but not sufficient for site recovery. The runbook in the PR body is load-bearing; absence of operator action after merge = site stays down. Sentry uptime monitor (if one is wired) is the lagging-indicator backstop.

## Domain Review

**Domains relevant:** infrastructure (CTO), product (CPO).

### Infrastructure (CTO)

**Status:** reviewed (inline, by pipeline framing).
**Assessment:** Path-scoped HTTPS upgrade via `cloudflare_ruleset` on the `http_request_dynamic_redirect` phase is the canonical pattern. Sibling resources prove provider + token scope already support this shape. Provider alias `cloudflare.rulesets` is the right binding. The only IaC gap left after this PR is codifying `always_use_https = false` on the zone — deferred to v5 provider migration follow-up (the v4 `cloudflare_zone_settings_override` does not cleanly expose this setting; the v5 `cloudflare_zone_setting` resource does).

### Product/UX Gate

**Tier:** none (no UI changes; marketing site recovery is the *product outcome* but the change itself is infrastructure).
**Decision:** auto-accepted (pipeline). CPO sign-off requirement on the `single-user incident` threshold is recorded in the YAML frontmatter (`requires_cpo_signoff: true`) and the framing reviewed inline at brainstorm-time via the pipeline context. At PR review, `user-impact-reviewer` runs against the diff.

## Infrastructure (IaC)

### Terraform changes

- New file: `apps/web-platform/infra/acme-challenge-ruleset.tf` — one new `cloudflare_ruleset` resource on existing provider alias `cloudflare.rulesets`.
- No new providers, no new variables, no new tokens. `cf_api_token_rulesets` scope already covers `http_request_dynamic_redirect` (variables.tf:69).
- No new TF root. Reuses `apps/web-platform/infra/` per `hr-every-new-terraform-root-must-include-an` — existing root has drift detection (`scheduled-terraform-drift.yml`) and PR-time validation (`infra-validation.yml`).
- State file: R2-backed `s3` backend at `soleur-terraform-state/web-platform/terraform.tfstate` (main.tf:2-14). The new resource lands in this state.

### Apply path

**Operator-driven** (no `apply-web-platform-infra.yml` exists). The canonical Doppler-Terraform invocation triplet is the apply path (PM2 above). `-target=cloudflare_ruleset.acme_aware_https_upgrade` scopes the apply to this one resource — defensive against accumulated drift.

Expected downtime / blast-radius: **near-zero** for the redirect-rule add (the ruleset starts firing the moment Cloudflare's edge propagates the rule, typically <30 s). PM1 is now a no-op (the IaC change codifies it), so there is no "PM1 → PM2" gap to manage; both the zone-toggle flip and the ruleset add propagate within the same `terraform apply` invocation. Brief at-risk window during edge propagation (<30 s): plain-HTTP requests to non-ACME paths on apex/www are served by GitHub Pages WITHOUT a 301 upgrade while the GH Pages cert is in `bad_authz` (it serves content rather than the redirect it would emit on a healthy custom-domain cert). HSTS-preloaded browsers refuse to render plain-HTTP responses and surface a TLS-style hard error; first-visit clients receive content over plain HTTP. Recommendation: run the apply at low-traffic time (off-peak EU hours) to minimize the propagation-window exposure surface, and confirm cert recovery (PM5) before announcing recovery to the broader team.

### Distinctness / drift safeguards

- `dev != prd`: this resource targets `var.cf_zone_id` (soleur.ai prod zone). There is no dev Cloudflare zone for soleur.ai (the dev environment runs on `localhost` and Hetzner staging behind `app-dev.soleur.ai` which uses a separate CF DNS path).
- `lifecycle.ignore_changes`: none needed. The resource is fully managed by Terraform from creation; no dashboard drift expected (dashboard cannot create a ruleset that conflicts with this one — Cloudflare's ruleset model is name-keyed at the API level).
- Sensitive values: none in this resource. `cf_api_token_rulesets` is already declared `sensitive = true` in variables.tf and lands in tfstate as a secret per existing convention.

### Vendor-tier reality check

- Free-tier cap on `http_request_dynamic_redirect` rules: **10 per phase**. `seo-rulesets.tf` already uses 10 rules in `cloudflare_ruleset.seo_page_redirects` on the same phase. The new ruleset is a **separate** `cloudflare_ruleset` resource (different `name` + different `description`), not additional rules in the existing one. Cloudflare's documented limit is per-ruleset, not per-phase — confirmed because `cache.tf` + `bot-allowlist.tf` each declare their own rulesets on adjacent phases without hitting the cap. Verify at apply-time: if Cloudflare returns "phase rule limit exceeded," fall back to inlining the two new rules into `cloudflare_ruleset.seo_page_redirects` (would push that ruleset from 10 to 12 rules, exceeding the Free cap — would require Pro tier upgrade, ~$25/mo; tracked as scope-out fallback). **Default path is the separate-ruleset shape; fallback is documented but unlikely.**

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open --json number,title,body | jq -r '.[] | select(.body // "" | contains("acme-challenge")) | "#\(.number): \(.title)"'` returns empty; same for `dns.tf` and `domains.md` substring searches. Run at /work time to confirm.

## Follow-Ups (NOT in scope for PR-α)

- **PR-β (alerting / monitoring):** Sentry uptime check on `https://soleur.ai/`, `https://www.soleur.ai/`, and `https://soleur.ai/.well-known/acme-challenge/probe` (the probe path returns 404 but PROVES the redirect exception fires). Per the pipeline brief, out of scope.
- **PR-γ (daily cert-state polling):** scheduled workflow that runs `gh api /repos/jikig-ai/soleur/pages | jq '.https_certificate.state'` and pages on `bad_authz` or `expired_at < now() + interval '14 days'`. Per pipeline brief, out of scope.
- **~~PR-δ (codify Always Use HTTPS = off in TF)~~ DONE in this PR.** Deepen-pass confirmed v4 `cloudflare_zone_settings_override.settings.always_use_https = "off"` is fully supported. No v5 dependency.
- **PR-δ′ (cloudflare provider v4→v5 migration):** orthogonal to this incident; tracking issue for the broader migration (covers `cloudflare_zone_settings_override` split, `cloudflare_record` schema changes, etc.). File as `infrastructure` + `chore`.
- **PR-ε (consider extending `apply-sentry-infra.yml` pattern to `apps/web-platform/infra/`):** auto-apply on push-to-main for a `-target=`-restricted subset of safe resources (DNS records, rulesets — not the Hetzner server which carries data risk). File as `infrastructure` + `chore` tracking issue with explicit destroy-protection design.

## Resume prompt (copy-paste after /clear)

```
/soleur:work knowledge-base/project/plans/2026-05-18-fix-soleur-ai-apex-cf-iac-plan.md. Branch: feat-one-shot-fix-soleur-ai-apex-cf-iac. Worktree: .worktrees/feat-one-shot-fix-soleur-ai-apex-cf-iac/. Plan reviewed; implementation is one new TF file + one doc edit; operator-applied post-merge per runbook in plan + PR body.
```
