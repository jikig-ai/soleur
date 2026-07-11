---
title: "Tasks — fix(infra): harden shared deploy tunnel against registry-origin dial storms (#6357)"
plan: knowledge-base/project/plans/2026-07-12-fix-harden-deploy-tunnel-registry-ingress-blast-radius-plan.md
issue: 6357
lane: cross-domain   # spec.md absent — defaulted to cross-domain (fail-closed, TR2)
status: ready-for-work
---

# Tasks — #6357 deploy-tunnel registry-ingress blast-radius hardening

> Re-scoped from the issue's literal "remove the stale rule" ask — the rule is **live** (ADR-096/#6122)
> and the origin IP is **unchanged** post-#6288. See the plan's Research Reconciliation.
> Root cause (registry instability) → #6288; architectural decoupling + monitor + metrics → #6178.

## Phase 1 — Correct the false "stale rule" premise (highest leverage)

- [ ] 1.1 In `apps/web-platform/infra/tunnel.tf` (comment above the `registry.${var.app_domain_base}`
  ingress rule, ~lines 44-56), rewrite the comment to state: this is the **live** ADR-096 / #6122
  registry-**push** ingress; the `10.0.1.30:5000` origin is the **current** zot registry (#6288 moved
  the registry *region* nbg1→hel1 but the **private IP is unchanged** — 10.0.1.0/24 spans hel1);
  **do NOT remove or repoint** (removal breaks CI push; repointing is a no-op); a `dial … canceled`
  here means the origin is transiently **down** (registry stability = #6288), not a config error.

## Phase 2 — Fail-fast `origin_request` on the registry ingress rule

- [ ] 2.1 In the same `ingress_rule` block (`tunnel.tf:57-60`), add a **minimal** nested block:
  ```hcl
  origin_request {
    connect_timeout   = 5      # INTEGER seconds (NOT "5s"); bounds the TCP dial only
    no_happy_eyeballs = true
  }
  ```
  with a short comment (fail-fast so a DOWN origin doesn't pile up ~30s-held dials that degrade the
  sibling deploy route — #6357; mitigation not cure — root cause #6288, decoupling #6178).
- [ ] 2.2 Do **NOT** add `keep_alive_*` / `tcp_keep_alive` / `proxy_type` / `http_host_header`
  (HTTP/pool semantics — no-op or schema friction for a raw `tcp://` bridge).
- [ ] 2.3 Do **NOT** lower `connect_timeout` below `5` (host accept-queue backpressure could false-fail
  a valid cold-zot push).

## Phase 3 — Pre-apply validation (the arbiter for the connect_timeout type)

- [ ] 3.1 `cd apps/web-platform/infra && terraform fmt -check` passes.
- [ ] 3.2 `terraform validate` passes against the v4-pinned root. **If it rejects `connect_timeout = 5`
  (integer), fall back to the duration string `"5s"`** — validate is the arbiter (Kieran vs
  framework-docs disagreed; integer is the verified form). Keep all edits in v4 `ingress_rule {}`
  form; do NOT `-upgrade` the provider.
- [ ] 3.3 Capture `terraform plan` in the PR body: exactly ONE **in-place update** to
  `cloudflare_zero_trust_tunnel_cloudflared_config.web`, **0 to destroy**, no net-new resource, no
  `-target=` workflow edit needed (the resource is already targeted at
  `apply-web-platform-infra.yml:313`).

## Phase 4 — PR + verification

- [ ] 4.1 Acceptance-criteria greps (from the plan) pass:
  - `awk '/hostname = "registry/,/^    }/' apps/web-platform/infra/tunnel.tf | grep -c connect_timeout` ≥ 1
  - `awk '/hostname = "registry/,/^    }/' apps/web-platform/infra/tunnel.tf | grep -c keep_alive` = 0
  - `grep -c 'tcp://\${local.registry_endpoint}' apps/web-platform/infra/tunnel.tf` ≥ 1 (removal-guard)
- [ ] 4.2 PR body uses **`Ref #6357`** (NOT `Closes` — ops-remediation; real close is post-apply), plus
  `Ref #6288` (root cause) and `Ref #6178` (deferred monitor + decoupling + metrics).
- [ ] 4.3 Post-merge: confirm the `apply-web-platform-infra.yml` auto-apply run is green (no operator
  SSH; it pushes the remote tunnel config).
- [ ] 4.4 Post-merge no-SSH health probe: `GET deploy.soleur.ai/hooks/deploy-status` (HMAC via
  `X-Signature-256`) returns last deploy state; a bad-sig `POST deploy.soleur.ai/hooks/deploy` returns
  **403/500 (not 502)** — proving the tunnel→webhook path is healthy.
- [ ] 4.5 Close #6357 via `gh issue close 6357` **only after** the apply is green and the probe passes.

## Out of scope (deferred, trackers exist)

- Registry OOM/restart-loop stability, un-pause registry heartbeat → **#6288**.
- Independent deploy-tunnel monitor (CF-Access synthetic), cloudflared `--metrics` export,
  architectural deploy-webhook decoupling → **#6178**.
- No new ADR / no C4 change (parameter hardening within ADR-008 + ADR-096).
