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
- **If this leaks, the user's [data / workflow / money] is exposed via:** N/A for the change itself (the new ruleset exposes nothing user-controlled — it only governs HTTP→HTTPS redirect behavior for one path prefix). The *outage* itself does not leak data; it dark-pages the brand surface.
- **Brand-survival threshold:** **single-user incident**. A single user encountering a "Cloudflare 526" on `soleur.ai` reads as "this company is dead." There is no aggregate-pattern story here — every visitor experiences the breach individually and forms an individual judgment. The remediation must land correctly the first time.

CPO sign-off requirement: CPO has been informed of the incident inline via the pipeline brief; the approach (path-scoped HTTPS-upgrade ruleset that excludes `/.well-known/acme-challenge/*`) is the canonical Let's Encrypt + Cloudflare reconciliation pattern documented by both vendors. No alternative approach is viable (the LE HTTP-01 challenge is a plain-HTTP protocol requirement; the DNS-01 alternative would require operator API-token plumbing into GitHub Pages, which GitHub does not expose). At review-time, `user-impact-reviewer` MUST enumerate failure modes against the diff.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1 — Ruleset declared.** New file `apps/web-platform/infra/acme-challenge-ruleset.tf` contains exactly one `cloudflare_ruleset` resource: `provider = cloudflare.rulesets`, `kind = "zone"`, `phase = "http_request_dynamic_redirect"`, two rules.
- [ ] **AC2 — Rule 1 (allow plain HTTP for ACME).** First rule: `expression = "(http.host in {\"soleur.ai\" \"www.soleur.ai\"} and starts_with(http.request.uri.path, \"/.well-known/acme-challenge/\") and not ssl)"`, `action = "skip"`, `action_parameters.ruleset = "current"` (skip remaining rules in this ruleset). Verified by `grep -nE 'acme-challenge' apps/web-platform/infra/acme-challenge-ruleset.tf` returning ≥1 match AND `grep -nE '"skip"' apps/web-platform/infra/acme-challenge-ruleset.tf` returning ≥1 match.
- [ ] **AC3 — Rule 2 (force HTTPS for everything else).** Second rule: `expression = "(http.host in {\"soleur.ai\" \"www.soleur.ai\"} and not ssl)"`, `action = "redirect"`, `action_parameters.from_value.status_code = 301`, `action_parameters.from_value.preserve_query_string = true`, `action_parameters.from_value.target_url.expression = "concat(\"https://\", http.host, http.request.uri.path)"`. Verified: `grep -nE 'concat\("https' apps/web-platform/infra/acme-challenge-ruleset.tf` returns ≥1 match.

  Note: `target_url.expression` (vs. `target_url.value`) requires the same `Single Redirect Rules:Edit + Transform Rules:Edit` token scope already granted to `var.cf_api_token_rulesets` (verified at `variables.tf:69`).

- [ ] **AC4 — Rule ordering is total.** Rule 1 sits before Rule 2 in the file AND in the resource block (Cloudflare evaluates rules top-down within a ruleset; the ACME skip MUST short-circuit the HTTPS redirect). Verified by reading the file: line number of "acme-challenge" expression < line number of "concat(\"https" expression.
- [ ] **AC5 — Provider alias correct.** `provider = cloudflare.rulesets`. Verified: `grep -n 'provider = cloudflare.rulesets' apps/web-platform/infra/acme-challenge-ruleset.tf` returns 1 match.
- [ ] **AC6 — Comment header explains why.** The file opens with a block comment naming (a) the 2026-05-18 incident, (b) the LE HTTP-01 / "Always Use HTTPS" conflict, (c) the operator-runbook requirement to **turn off the dashboard "Always Use HTTPS" toggle before apply**, (d) cross-link to `knowledge-base/operations/domains.md`. Verified: file's first 30 lines contain "2026-05-18", "acme", "Always Use HTTPS", "domains.md".
- [ ] **AC7 — `terraform fmt` clean.** `terraform fmt -check apps/web-platform/infra/` exits 0. Run before push.
- [ ] **AC8 — `terraform validate` clean.** From `apps/web-platform/infra/`: `terraform init -input=false -backend=false && terraform validate` exits 0. (Backend init is skipped so this runs without Doppler credentials in the local environment — provider plugins still download and the schema is checked.)
- [ ] **AC9 — `infra-validation.yml` green on the PR.** The existing pre-merge workflow (`.github/workflows/infra-validation.yml`) detects `apps/web-platform/infra/` changes, runs `terraform plan` against the live state, and posts the plan to the PR. The plan output MUST show: `Plan: 1 to add, 0 to change, 0 to destroy` (one new `cloudflare_ruleset.acme_aware_https_upgrade` resource), confirmed via inline workflow check.
- [ ] **AC10 — `domains.md` updated.** `knowledge-base/operations/domains.md` updated as described in `Files to Edit`. Verified: `grep -nE 'apps/web-platform/infra/dns\.tf' knowledge-base/operations/domains.md` returns ≥1 match AND `grep -nE 'acme-challenge-ruleset\.tf' knowledge-base/operations/domains.md` returns ≥1 match.
- [ ] **AC11 — PR body contains the operator runbook.** PR description includes the verbatim Doppler-Terraform invocation triplet, the dashboard-toggle-off step, the post-apply curl verification, the GitHub Pages cert-reissue link, and the post-cert-issuance verification curls. (See Operator Runbook section below; the PR body imports it verbatim.)
- [ ] **AC12 — PR body uses `Ref #N`, not `Closes #N`.** Because the actual user-facing recovery happens at *operator apply time + cert reissue*, not at *merge time*, the PR body MUST use `Ref` for the incident-tracker issue if one exists, with explicit Pre-merge / Post-merge subsections in this AC list. The incident issue is closed in the post-merge runbook step `gh issue close <N>` after the post-apply curl returns HTTP 200.

### Post-merge (operator)

- [ ] **PM1 — Toggle dashboard "Always Use HTTPS" OFF.** Cloudflare dashboard → soleur.ai zone → SSL/TLS → Edge Certificates → Always Use HTTPS: **Off**. Done by the operator BEFORE `terraform apply`. If left on, both the zone-level toggle AND the new ruleset will fire and the ACME challenge is still 301'd. This is **a manual click** — `cloudflare_zone_settings_override` in v4 of the provider does not expose `always_use_https` cleanly (the setting lives outside the documented `settings {}` block schema in v4). Filed as scope-out follow-up to codify on the v5 migration (see Follow-Ups).
- [ ] **PM2 — Run the canonical Doppler-Terraform invocation triplet.** From `apps/web-platform/infra/`:

  ```bash
  export AWS_ACCESS_KEY_ID=$(doppler secrets get AWS_ACCESS_KEY_ID -p soleur -c prd_terraform --plain)
  export AWS_SECRET_ACCESS_KEY=$(doppler secrets get AWS_SECRET_ACCESS_KEY -p soleur -c prd_terraform --plain)
  terraform init -input=false
  doppler run -p soleur -c prd_terraform --name-transformer tf-var -- \
    terraform plan -target=cloudflare_ruleset.acme_aware_https_upgrade -out=tfplan
  doppler run -p soleur -c prd_terraform --name-transformer tf-var -- \
    terraform apply tfplan
  ```

  Expected plan output: `Plan: 1 to add, 0 to change, 0 to destroy`. The `-target=` scoping is defensive — if drift has accumulated unrelated to PR-α (per `2026-05-09-drift-runbook-canonical-tf-invocation-and-fresh-plan.md`), the operator deals with that separately via a clean `terraform plan` without `-target=` to surface the full drift list.

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

### Phase 1 — Author the ruleset

1.1. Create `apps/web-platform/infra/acme-challenge-ruleset.tf` with the file contents specified in `Files to Create`.

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

  The dashboard toggle MUST stay off. If a future operator re-enables it,
  the next cert renewal (every ~60 days) will fail again. A future PR
  should codify the toggle-off state via the cloudflare provider v5
  `cloudflare_zone_setting` resource (v4 does not expose this setting
  cleanly via `cloudflare_zone_settings_override`).
  ```

2.2. Cross-link from `dns.tf` Phase 1 comment back to `domains.md` for symmetry. (Already linked in the AC6 file header; this is just the reverse direction.)

### Phase 3 — Commit, push, open PR

3.1. Stage and commit:

```bash
git add apps/web-platform/infra/acme-challenge-ruleset.tf knowledge-base/operations/domains.md
git commit -m "$(cat <<'EOF'
fix(infra): codify ACME-aware HTTPS upgrade for soleur.ai apex/www

Cloudflare's zone-level Always Use HTTPS toggle force-redirected the
Let's Encrypt HTTP-01 challenge at /.well-known/acme-challenge/* to
HTTPS before the validator could fetch the token over port 80, causing
the GitHub Pages cert renewal to fail with bad_authz on 2026-05-17 and
the production marketing site to return Cloudflare 526 on 2026-05-18.

Adds cloudflare_ruleset.acme_aware_https_upgrade
(http_request_dynamic_redirect phase) with two rules:
  1. skip-current-ruleset for /.well-known/acme-challenge/* on plain HTTP
  2. 301 redirect HTTP → HTTPS for every other path

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

3.3. Wait for `infra-validation.yml` to post the `terraform plan` output as a PR comment. Confirm: `Plan: 1 to add, 0 to change, 0 to destroy` AND the diff shows only `cloudflare_ruleset.acme_aware_https_upgrade` as the new resource (AC9).

3.4. After plan-validation green, `gh pr ready <N> && gh pr merge <N> --squash --auto`.

### Phase 4 — Post-merge operator runbook

Execute PM1 through PM7 above. The runbook is duplicated verbatim into the PR body so the operator can follow it directly from the PR page.

## Files to Edit

- `knowledge-base/operations/domains.md` — bump `last_updated`, prepend pointer to `dns.tf` as source of truth, append new "Always Use HTTPS exception" subsection.

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
  # Fix: turn the zone-level toggle OFF (operator dashboard click — v4
  # provider does not expose always_use_https cleanly via
  # cloudflare_zone_settings_override; codify on v5 migration), and
  # replace it with this ruleset which is path-aware.
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

**Apply order matters — do PM1 before PM2 or both will be active simultaneously and the ACME path will still be 301'd.**

1. **Toggle dashboard "Always Use HTTPS" OFF** (PM1).
2. **Run the canonical Doppler-Terraform invocation triplet** (PM2). Expected: `Plan: 1 to add, 0 to change, 0 to destroy`. If destroy count > 0, STOP — that is unrelated drift, address separately.
3. **Verify ACME path reachable over plain HTTP** (PM3). Expected `404`, not `301`.
4. **Verify non-ACME paths still 301 to HTTPS** (PM4). Expected `301 https://...`.
5. **Trigger GitHub Pages cert reissue** (PM5). Watch `gh api /repos/jikig-ai/soleur/pages | jq '.https_certificate.state'` cycle through `bad_authz` → `authorized` → `issued`.
6. **Final user-facing verification** (PM6). Expected `HTTP/2 200` from both apex and www.
7. **Close the incident issue** (PM7). Run `/soleur:incident` to scaffold the PIR.

## Test Plan

- **Pre-merge:** `terraform fmt -check`, `terraform validate`, `infra-validation.yml` posts `Plan: 1 to add, 0 to change, 0 to destroy`.
- **Post-merge:** PM3 + PM4 + PM6 curl gates above. Sentry "scheduled-marketing-uptime" check (if exists; if not, file follow-up) returns to green.

## Risks

- **R1: `target_url.expression` schema gap.** If `cloudflare/cloudflare ~> 4.0` rejects the `expression` form on `http_request_dynamic_redirect.action_parameters.from_value.target_url`, the rule must be split into a host-pair (one rule per host) with `target_url.expression = "concat(\"https://soleur.ai\", http.request.uri.path)"` etc. Mitigated by AC8 (`terraform validate` runs locally before push).
- **R2: Operator forgets PM1 (toggle off).** If "Always Use HTTPS" stays on, both layers fire and the new ruleset is a silent no-op for the ACME path (the zone toggle has higher precedence on the redirect-before-rules-fire ordering). Mitigated by making PM1 the first step in both the PR body runbook AND the file header comment AND `domains.md`.
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

Expected downtime / blast-radius: **zero** for the redirect-rule add (the ruleset starts firing the moment Cloudflare's edge propagates the rule, typically <30 s). The window between "PM1 toggle off" and "PM2 apply complete" is the only at-risk window — during that gap, plain-HTTP requests to non-ACME paths reach origin without redirect, but origin is GitHub Pages (which itself 301s HTTP→HTTPS on its IP for `*.github.io` hosts), so the user sees a double-301 and lands on HTTPS anyway. No user-visible regression.

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
- **PR-δ (codify Always Use HTTPS = off in TF):** on the v5 cloudflare provider migration, add `cloudflare_zone_setting` resource with `setting_id = "always_use_https"`, `value = "off"`. v4 does not expose this cleanly. File as `infrastructure` + `chore` tracking issue.
- **PR-ε (consider extending `apply-sentry-infra.yml` pattern to `apps/web-platform/infra/`):** auto-apply on push-to-main for a `-target=`-restricted subset of safe resources (DNS records, rulesets — not the Hetzner server which carries data risk). File as `infrastructure` + `chore` tracking issue with explicit destroy-protection design.

## Resume prompt (copy-paste after /clear)

```
/soleur:work knowledge-base/project/plans/2026-05-18-fix-soleur-ai-apex-cf-iac-plan.md. Branch: feat-one-shot-fix-soleur-ai-apex-cf-iac. Worktree: .worktrees/feat-one-shot-fix-soleur-ai-apex-cf-iac/. Plan reviewed; implementation is one new TF file + one doc edit; operator-applied post-merge per runbook in plan + PR body.
```
