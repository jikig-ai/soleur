---
lane: cross-domain
issue: 5933
plan: knowledge-base/project/plans/2026-07-03-feat-web2-absence-detector-image-pin-plan.md
brand_survival_threshold: single-user incident
---

# Tasks: Per-host absence detector + image signing/verify (#5933 items 1 & 4)

Two PRs, Item 1 first. Fresh-host verify + digest-pin are **deferred to #5274** (see plan §Deferred).

## PR 1 — Item 1: Per-host uptime absence detector (web-1)

### 1. Setup
- [ ] 1.1 Confirm `apply-web-platform-infra.yml` is green on main before starting (trigger cleared).

### 2. Core Implementation
- [ ] 2.1 `variables.tf`: add `monitored = optional(bool, true)` to the `web_hosts` object type; set `web-2 = { … monitored = false }`. Keep EU-location + private_ip validations.
- [ ] 2.2 `dns.tf`: add `cloudflare_record "web_host"` `for_each = { for k, v in var.web_hosts : k => v if v.monitored }`, mirroring `cloudflare_record.app` (`content = hcloud_server.web[each.key].ipv4_address`, `name = "${each.key}.app"`, `proxied = true`, `ttl = 1`).
- [ ] 2.3 `uptime-alerts.tf`: add `betteruptime_monitor "web_host"` with the SAME `if v.monitored` filter, mirroring `soleur_apex`; `url = "https://${each.key}.app.soleur.ai/health"`; `pronounceable_name = "soleur uptime ${each.key}"`; paid-tier `policy_id` gate.
- [ ] 2.4 `apply-web-platform-infra.yml`: add `-target=cloudflare_record.web_host` + `-target=betteruptime_monitor.web_host` to BOTH the plan and apply steps.

### 3. Architecture
- [ ] 3.1 `model.c4`+`views.c4`: add `betterstack` external system + `betterstack -> hetzner` probe edge + views include. Run `c4-code-syntax.test.ts` + `c4-render.test.ts`.
- [ ] 3.2 ADR-082: amend Item 1 (trigger-cleared certification) + correct Relates-to (#5887→#5274) via `/soleur:architecture`.

### 4. Verify
- [ ] 4.1 `terraform validate` + `terraform plan` — assert NO `hcloud_server.web["web-2"]` create (AC2).
- [ ] 4.2 Post-merge: `curl -sf https://web-1.app.soleur.ai/health` → 200; BetterStack web-1 monitor green. If CF bot-fight challenges, add a `cloudflare_ruleset` skip rule.
- [ ] 4.3 PR body uses `Ref #5933`.

## PR 2 — Item 4: Image signing + running-host verify

### 5. Sign (release pipeline)
- [ ] 5.1 `reusable-release.yml`: add `permissions: id-token: write`, pinned `sigstore/cosign-installer`, `cosign sign --yes …@${{ steps.docker_build.outputs.digest }}` with an offline-verifiable bundle.

### 6. Verify (deploy path)
- [ ] 6.1 Decide cosign availability on host: install via cloud-init OR verify via a pinned `ghcr.io/sigstore/cosign` container (no host binary).
- [ ] 6.2 `ci-deploy.sh` after `:805`: resolve pulled digest (`docker inspect RepoDigests`; empty/multi → Sentry `inspect_failed`); absent-cosign → Sentry `cosign_absent`.
- [ ] 6.3 `cosign verify --offline <digest>` with identity regexp `@(refs/heads/main|refs/tags/v[0-9].+)$` + `token.actions.githubusercontent.com` issuer.
- [ ] 6.4 On pass: `docker run` the **verified digest**, not `:$TAG`. On fail (WARN): logger + Sentry `verify_result`; do NOT `final_write_state 1`.

### 7. Architecture
- [ ] 7.1 `model.c4`+`views.c4`: add `sigstore` external system + `github -> sigstore` (sign) + `hetzner -> sigstore` (verify) edges. Run c4 tests.
- [ ] 7.2 ADR-082: amend Item 4 (signing + deploy-path verify + `ignore_changes` rationale sub-decision; fresh-host + digest-pin ride #5274); Alternatives: verify-by-tag + tfvars-threading rejections.

### 8. Verify + rollout
- [ ] 8.1 `actionlint` on `reusable-release.yml`; grep `ci-deploy.sh` asserts the main+tags-pinned identity regexp (AC10).
- [ ] 8.2 Post-merge: after next release, `cosign verify --offline …:latest` exits 0 (AC13).
- [ ] 8.3 Fast-follow: flip WARN→ENFORCE (one-line) after AC13 holds + one clean WARN deploy. Declare `rekor_unreachable` = warn-and-proceed.
- [ ] 8.4 PR body `Closes #5933` (if Item 1 merged) else `Ref #5933`.

## Operator follow-up
- [ ] OP1: BetterStack Vendor DPA counter-signature (`compliance-posture.md:83`) before wide per-host rollout.
