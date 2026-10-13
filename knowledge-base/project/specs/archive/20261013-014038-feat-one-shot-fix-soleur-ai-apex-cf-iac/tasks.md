---
title: "Tasks — PR-α: IaC + root-cause fix for soleur.ai apex/www GitHub Pages routing"
date: 2026-05-18
plan: knowledge-base/project/plans/2026-05-18-fix-soleur-ai-apex-cf-iac-plan.md
lane: cross-domain
status: ready
---

# Tasks

## Phase 0 — Preflight

- [ ] 0.1 Confirm worktree + branch (`git status`, `git branch --show-current`).
- [ ] 0.2 Re-confirm DNS records already in `dns.tf` (grep github_pages / www / github_pages_challenge → 4+ hits).
- [ ] 0.3 Confirm `cf_api_token_rulesets` scope includes `http_request_dynamic_redirect` (grep variables.tf:69).
- [ ] 0.4 Confirm cloudflare provider version `~> 4.0` (grep main.tf).

## Phase 1 — Author the ruleset

- [ ] 1.1 Create `apps/web-platform/infra/acme-challenge-ruleset.tf` with header comment + `cloudflare_ruleset.acme_aware_https_upgrade` (2 rules: skip ACME, redirect rest).
- [ ] 1.2 Run `terraform fmt apps/web-platform/infra/`.
- [ ] 1.3 Run `terraform init -input=false -backend=false && terraform validate` from `apps/web-platform/infra/`. Fallback to host-pair form if `target_url.expression` rejects.

## Phase 2 — Update operations docs

- [ ] 2.1 Edit `knowledge-base/operations/domains.md`: bump `last_updated`, prepend source-of-truth pointer to `dns.tf`, append new "Always Use HTTPS exception" subsection naming the new ruleset file.

## Phase 3 — Commit, push, open PR

- [ ] 3.1 Stage + commit with the message specified in plan Phase 3.1.
- [ ] 3.2 `git push -u origin feat-one-shot-fix-soleur-ai-apex-cf-iac`.
- [ ] 3.3 Open PR. PR body = Operator Runbook from plan + Test Plan + `Ref #<incident-issue-number>`.
- [ ] 3.4 Wait for `infra-validation.yml` to post plan; verify `Plan: 1 to add, 0 to change, 0 to destroy` with `cloudflare_ruleset.acme_aware_https_upgrade` as the only new resource.
- [ ] 3.5 `gh pr ready <N> && gh pr merge <N> --squash --auto`.

## Phase 4 — Post-merge operator runbook (operator-driven, NOT automated in this PR)

- [ ] PM1 Toggle dashboard "Always Use HTTPS" → Off.
- [ ] PM2 Run canonical Doppler-Terraform triplet with `-target=cloudflare_ruleset.acme_aware_https_upgrade`. Expect `Plan: 1 to add, 0 to change, 0 to destroy`.
- [ ] PM3 `curl http://soleur.ai/.well-known/acme-challenge/probe` → 404 (not 301).
- [ ] PM4 `curl http://soleur.ai/changelog/` → 301 https://soleur.ai/changelog/.
- [ ] PM5 Trigger GitHub Pages cert reissue; watch `gh api /repos/jikig-ai/soleur/pages | jq '.https_certificate.state'` cycle `bad_authz` → `authorized` → `issued`.
- [ ] PM6 `curl -I https://soleur.ai/` → `HTTP/2 200`. Same for www.
- [ ] PM7 `gh issue close <incident-issue-number>`; run `/soleur:incident` to scaffold PIR.
