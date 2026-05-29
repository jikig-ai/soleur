<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
<!--
  Phase 2.8 reviewed in the linked plan: this work adds NO infrastructure
  resource. The canonicalizer substrate (www CNAME + apex A-records, both
  proxied) is already Terraform-managed and drift-detected; the 301 is
  GitHub-Pages-owned (docs/CNAME = apex). The deliverables are a static bash
  drift-guard test + comment corrections + a CI-wire of the existing test
  pattern. No SSH, no dashboard config, no operator terraform apply.
-->
---
title: "Tasks — codify the www→apex canonicalizer drift-guard"
issue: "#4584"
plan: "knowledge-base/project/plans/2026-05-29-infra-codify-www-apex-canonicalizer-plan.md"
lane: cross-domain
---

# Tasks — www→apex canonicalizer drift-guard (#4584)

> Reframing: the www→apex 301 is GitHub-Pages-owned (CNAME = apex), NOT unmanaged
> CF config. The DNS substrate is already Terraform-managed + drift-detected. The
> real gap is a config-invariant test, not a new cloudflare_ruleset. See plan.

## Phase 0 — Preconditions (read-only)

- [ ] 0.1 Live-probe www→apex 301 still GitHub-Pages-owned: `curl -sI https://www.soleur.ai/` shows `via: 1.1 varnish` + `x-fastly-request-id` + status 301, host+path-preserving. STOP if mechanism changed.
- [ ] 0.2 Confirm no CF redirect resource appeared: `grep -rlE 'cloudflare_page_rule|cloudflare_list\b|http_request_redirect|cloudflare_bulk' apps/web-platform/infra` → none.
- [ ] 0.3 Read current `www` + apex `cloudflare_record` blocks in `dns.tf` and the stale "out-of-band canonicalizer" comments in `seo-rulesets.tf` (~16-20, ~248, ~371-374).

## Phase 1 — Failing test first (RED)

- [ ] 1.1 Read `apps/web-platform/infra/inngest.test.sh` for the `*.test.sh` assertion + exit-code idiom (plain bash, no framework).
- [ ] 1.2 Scaffold `apps/web-platform/infra/www-apex-canonicalizer.test.sh` (executable) with assertions:
  - A1: `plugins/soleur/docs/CNAME` == `soleur.ai` (apex), trimmed.
  - A2: `dns.tf` `www` record content == `"jikig-ai.github.io"` AND `proxied = true`.
  - A3: `dns.tf` apex record `type = "A"` AND `proxied = true`.
  - A4: `grep -q 'GitHub-Pages-owned'` sentinel in `dns.tf` (doc anti-rot).
- [ ] 1.3 Confirm RED: A4 fails (comment not yet added); A1-A3 already pass against current tracked state.

## Phase 2 — Add contract comment + correct stale comments (GREEN)

- [ ] 2.1 Add GitHub-Pages-owned contract-comment block to `dns.tf` above the `www` CNAME (and apex A-record). Comment only, no resource change.
- [ ] 2.2 Correct stale `seo-rulesets.tf` "out-of-band / dashboard-created canonicalizer" comments → "GitHub-Pages-owned 301 (docs/CNAME = apex); see dns.tf + www-apex-canonicalizer.test.sh".
- [ ] 2.3 Re-run test: all A1-A4 PASS, exit 0.
- [ ] 2.4 `terraform validate` in `apps/web-platform/infra/` → Success; `terraform plan` shows `0 to change` for `cloudflare_record.*` + the two rulesets.

## Phase 3 — Wire test into CI

- [ ] 3.1 Confirm target line (`grep -n 'canary-bundle-claim-check.test.sh' .github/workflows/infra-validation.yml`) — verified 2026-05-29 at the `deploy-script-tests` job, lines ~118-131.
- [ ] 3.2 Add a named step `run: bash apps/web-platform/infra/www-apex-canonicalizer.test.sh` to the `deploy-script-tests` job in `infra-validation.yml`, matching the existing 3 named test steps. Do NOT use the `main.test.sh` per-app hook; do NOT create a new workflow. Record the final step location in the PR body.

## Phase 4 — Close & document

- [ ] 4.1 PR body: front-load falsification evidence (www 301 Fastly/GitHub headers + `grep -rlE … → none`); `Closes #4584`.
- [ ] 4.2 Post-merge: CI green on merge commit; `gh issue close 4584` with reframing summary comment.

## Acceptance gates (see plan ## Acceptance Criteria)

- [ ] Pre-merge: test exists/executable/exits 0; A1 tamper-and-revert proves it catches CNAME inversion; `grep -c 'GitHub-Pages-owned' dns.tf` >= 1; stale-comment grep == 0; `terraform validate` Success; CI-wired; evidence in PR body.
- [ ] Post-merge: CI green; #4584 closed with comment.
