---
title: "Per-host absence detector + image signing/verify (#5933 items 1 & 4)"
issue: 5933
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
governing_adr: ADR-082
type: feat
created: 2026-07-03
plan_review: applied (spec-flow + architecture-strategist + code-simplicity + security-sentinel, 2026-07-03)
---

# ✨ Per-host absence detector + image signing/verify (#5933 items 1 & 4)

## Overview

Ship the **independently-actionable, currently-testable** halves of ADR-082 items 1 & 4 as **two PRs, Item 1 first**. A multi-agent plan-review (spec-flow, architecture, simplicity, security) reshaped the scope: the fresh-host (cloud-init) verify + digest-pin **only protect web-2, which does not exist until the #5274 cutover** — so they are deferred to that cutover PR (like Item 2), and this cycle ships only what protects the host serving users *today*.

- **PR 1 — Item 1: per-host uptime absence detector (web-1).** A CF-proxied `web-1.app.soleur.ai` probe hostname + a `monitored`-gated `betteruptime_monitor for_each`. **Record AND monitor gate on the same `if v.monitored` filter** (web-1 only now); web-2's record+monitor both ride #5274.
- **PR 2 — Item 4: image signing + running-host verify.** cosign-keyless **sign** the release image (`reusable-release.yml`) with an **attached bundle** (offline-verifiable), and cosign-**verify on the deploy path** (`ci-deploy.sh`) — the running-host RCE surface the operator asked to close. Verify lands **WARN**, flips **ENFORCE** via a trivial fast-follow after one signed release deploys clean.

**Deferred to the #5274 Phase 3.D cutover (documented, not dropped):** fresh-host `cloud-init.yml` verify + `var.image_digest` pin + the web-2 monitor/record flip (`monitored=true`). They land where web-2 actually boots and can be end-to-end tested.

The design is decided in **ADR-082**; this plan certifies a cleared deferral trigger, resolves scope, and produces the ADR-082 amendment + C4 edits as deliverables. **NEVER re-derives the ADR design.**

## Research Reconciliation — Spec vs. Codebase

| Spec / issue claim | Codebase reality (verified) | Plan response |
|---|---|---|
| "blocks #5887 operator cutover" | **#5887 CLOSED** — a `moved`-block CI fix, not a cutover. Real cutover = **#5274 Phase 3.D** (`dns.tf:4`, OPEN). | Correct in ADR-082 amendment + PR bodies. |
| Item 1 "blocked on #5887 (apply RED)" | `apply-web-platform-infra.yml` last two `main` runs **green**. Trigger cleared. | Item 1 web-1 ships now. |
| Item 3 (egress probe) a gap | **Shipped** — PR #5945. | Out of scope. |
| web-2 exists / is monitorable now | **web-2 NOT in state** — `hcloud_server.web` excluded from the auto-apply `-target` set (`apply-web-platform-infra.yml:29`); provisioned only at #5274 (`dns.tf:4-12`, `server.tf:87-95`). | **Record + monitor both gate on `if v.monitored`** (web-1 only). Fresh-host verify + digest-pin defer to #5274. |
| CF provider uses `value =` (research agent) | Existing `cloudflare_record.app` uses **`content =`** (`dns.tf:16`). | Mirror `cloudflare_record.app` exactly. |
| Live-Rekor cosign verify is fine | #5945 egress allowlist (`cron-egress-allowlist.txt`) excludes sigstore/rekor/fulcio → live verify firewall-blocked; cosign absent on host. | Sign with attached bundle → `cosign verify --offline`; install/containerize cosign. |

**Premise Validation:** #5921 CLOSED, #5887 CLOSED (mis-cited), #5274 OPEN (real cutover), #5945 MERGED (item 3), ADR-082 governing (this plan *extends* it with operator sign-off). Apply pipeline green (`gh run list`). No stale premise remains.

## User-Brand Impact

**If this lands broken, the user experiences:** a dead/never-booted web host serving intermittent, unattributed 5xx to the CF round-robin subset it routes to (Item 1 gap); or a tampered/typo-squatted image running with full RCE on the host serving every user (Item 4 gap).

**If this leaks, the user's data/workflow is exposed via:** an **unsigned** container image (GHCR compromise / supply-chain substitution) executing arbitrary code with full access to all user data on the shared host. *(Note: signature-verify provides authenticity; digest-pin — deferred to #5274 — provides only immutability, NOT authenticity. This plan's authenticity control is the cosign verify.)*

**Brand-survival threshold:** single-user incident → `requires_cpo_signoff: true` (carried from brainstorm). `user-impact-reviewer` runs at review time.

## Implementation Phases

### PR 1 — Item 1: Per-host uptime absence detector (web-1)

**Phase 1.1 — `var.web_hosts` gating field.** Add `monitored = optional(bool, true)` to the `web_hosts` object type (`variables.tf:69-88`); set `web-2 = { … monitored = false }`. Preserve the EU-location + private_ip validations.

**Phase 1.2 — Per-host proxied probe hostname (web-1 only).** Add `cloudflare_record "web_host"` `for_each = { for k, v in var.web_hosts : k => v if v.monitored }` in `dns.tf`, **mirroring `cloudflare_record.app`** (`zone_id`, `name = "${each.key}.app"`, `type = "A"`, `content = hcloud_server.web[each.key].ipv4_address`, `proxied = true`, `ttl = 1`). **The `if v.monitored` filter is load-bearing** — an ungated `for_each` references `hcloud_server.web["web-2"]` (excluded from the auto-apply `-target` set) and forces premature web-2 provisioning on a routine merge-apply (P0, #5887 redux).

**Phase 1.3 — Per-host monitor (same filter).** Add `betteruptime_monitor "web_host"` `for_each = { for k, v in var.web_hosts : k => v if v.monitored }` in `uptime-alerts.tf`, mirroring `soleur_apex` (`:53-77`): `monitor_type="status"`, `url = "https://${each.key}.app.soleur.ai/health"`, `pronounceable_name = "soleur uptime ${each.key}"` (**unique per host — hard provider constraint**), `check_frequency=180`, `verify_ssl=true`, `policy_id = var.betterstack_paid_tier ? betteruptime_policy.uptime[0].id : null` (mirror the free/paid gate). No `follow_redirects`.

**Phase 1.4 — `-target` allow-list.** Add `-target=cloudflare_record.web_host` + `-target=betteruptime_monitor.web_host` to BOTH the plan and apply `-target` sets in `apply-web-platform-infra.yml` (~`:264-330`). Destroy-guard filter (`tests/scripts/lib/destroy-guard-filter-web-platform.jq`) **checked — no change needed**: `cloudflare_record`/`betteruptime_monitor` add no counted nested-block surface (`.rules`/`.config`/`.settings`/`.include`/`.email_integration`/hcloud-reboot).

**Phase 1.5 — C4 + ADR-082 amendment.** Add `betterstack` external system + probe edge to `model.c4`/`views.c4`; amend ADR-082 Item 1 (trigger-cleared certification; web-1 now / web-2 at #5274) + Relates-to line (#5887→#5274).

### PR 2 — Item 4: Image signing + running-host verify

**Phase 2.1 — Sign in the release pipeline (with attached bundle).** In `reusable-release.yml` after build-push (`:579-611`): add `permissions: id-token: write`, `sigstore/cosign-installer` (pinned SHA), and `cosign sign --yes ghcr.io/jikig-ai/soleur-web-platform@${{ steps.docker_build.outputs.digest }}` (**sign the digest**). Ensure the signature+bundle is retrievable for **offline** verification (attached bundle / OCI referrer) so the host needs no live Rekor round-trip.

**Phase 2.2 — Deploy-path verify (`ci-deploy.sh`, running host).** After `docker pull "$IMAGE:$TAG"` (`:805`):
1. Resolve the pulled digest: `docker inspect --format '{{index .RepoDigests 0}}'`. **Handle empty/multi-entry** RepoDigests → emit Sentry `verify_result=inspect_failed`; do NOT silently pass.
2. Ensure cosign is available on the host — **not installed today**. Choose (deepen-plan/work): install the pinned cosign binary via cloud-init host-setup, OR verify via a pinned `ghcr.io/sigstore/cosign` container (no host binary). Absent-cosign → Sentry `verify_result=cosign_absent`, never silent-pass.
3. `cosign verify --offline <digest>` with `--certificate-identity-regexp='^https://github\.com/jikig-ai/soleur/\.github/workflows/reusable-release\.yml@(refs/heads/main|refs/tags/v[0-9].+)$'` `--certificate-oidc-issuer=https://token.actions.githubusercontent.com` (**pinned to main+release-tags — NOT `refs/(heads|tags)/.+`**, which accepts any intra-repo branch/tag signature).
4. On pass → **`docker run` the verified DIGEST**, not `:$TAG` (TOCTOU: the tag can move between verify and run).
5. On fail (WARN): `logger` + Sentry `verify_result ∈ {unsigned, wrong_identity, tampered, inspect_failed, cosign_absent}`, do NOT `final_write_state 1`. (ENFORCE later: `final_write_state 1 "cosign_verify_failed:<result>"` + keep the old container live — `ci-deploy.sh:855` — so fail-closed is downtime-safe.)

**Phase 2.3 — C4 + ADR-082 amendment.** Add `sigstore` external system + sign/verify edges to `model.c4`/`views.c4`. Amend ADR-082 Item 4: record signing, the **deploy-path verify** + the **explicit rationale** (the `ignore_changes=[user_data]` gap leaves running hosts unprotected by the fresh-boot pin — why verify was extended to `ci-deploy.sh` as an amendment, not a new ADR); note the fresh-host verify + digest-pin ride #5274; add the verify-by-tag→verify-by-digest rejection to Alternatives.

**Phase 2.4 — ENFORCE fast-follow (signal-gated, no soak harness).** After PR2 merges → the next release signs → a deploy verifies WARN. Once **AC16** confirms one signed release deployed clean, a **trivial fast-follow** flips WARN→ENFORCE (a one-line branch change), and declares the `rekor_unreachable` branch = warn-and-proceed (moot under offline verify; unsigned/tampered/wrong_identity → fail-closed). No `cosign-verify-enforce-*.sh` soak script, no sweeper wiring — the flip is gated on the signal (a signed release exists), not a time-soak.

## Files to Edit

- `apps/web-platform/infra/variables.tf` — `monitored` field on `web_hosts` (PR1).
- `apps/web-platform/infra/dns.tf` — `if v.monitored`-gated probe `cloudflare_record for_each` (PR1).
- `apps/web-platform/infra/uptime-alerts.tf` — `if v.monitored`-gated `betteruptime_monitor for_each` (PR1).
- `.github/workflows/apply-web-platform-infra.yml` — `-target=` entries for the two new resources (PR1).
- `.github/workflows/reusable-release.yml` — cosign-installer + `cosign sign` (PR2).
- `apps/web-platform/infra/ci-deploy.sh` — deploy-path cosign verify after `:805` (PR2).
- `knowledge-base/engineering/architecture/decisions/ADR-082-fresh-web2-boot-observability.md` — amend Items 1 & 4 + Relates-to (both PRs).
- `knowledge-base/engineering/architecture/diagrams/model.c4` + `views.c4` — betterstack (PR1) + sigstore (PR2).

## Files to Create

None. (`cosign-verify-enforce-*.sh` removed — no soak harness. `image-digest.auto.tfvars` removed — digest-pin defers to #5274 and will use Doppler `TF_VAR_image_digest`, not a committed tfvars, to avoid a commit-loop/apply-race — architecture P1.)

## Open Code-Review Overlap

None. All 61 open `code-review` issues queried; zero reference the edited files.

## Infrastructure (IaC)

### Terraform changes
- **Files:** `variables.tf`, `dns.tf`, `uptime-alerts.tf` (PR1). No new TF root. PR2 touches CI (`reusable-release.yml`) + host script (`ci-deploy.sh`), not `.tf`.
- **Providers (existing pins):** `BetterStackHQ/better-uptime ~> 0.20`, `cloudflare/cloudflare ~> 4.0` (4.52.7).
- **Sensitive vars:** none new. cosign keyless needs no stored key.

### Apply path
- **PR1:** the auto-apply `apply-web-platform-infra.yml` (green post-#5887), with the new `-target=` entries. Additive records/monitors → no downtime. `if v.monitored` keeps web-2 out of state until #5274.
- **PR2:** CI + host-script only; effect on the next deploy. No TF apply.

### Distinctness / drift safeguards
- `monitored=false` on web-2 keeps its record+monitor out of the plan (no premature web-2 provisioning; no NXDOMAIN/522 false page).
- Destroy-guard filter unaffected (checked).

### Vendor-tier reality check
- **BetterStack free tier rejects `betteruptime_policy`** — mirror `policy_id = var.betterstack_paid_tier ? … : null`. Monitors are free-tier OK.
- CF bot-fight *may* challenge the probe → verify `curl https://web-1.app.soleur.ai/health` at /work; add a `cloudflare_ruleset` skip rule (repo's existing pattern) only if challenged. YAGNI otherwise.

## Observability

```yaml
liveness_signal:
  what: per-host betteruptime_monitor (origin 200 on web-1.app.soleur.ai/health) + deploy-path cosign verify pass/fail
  cadence: monitor check_frequency 180s; verify runs per deploy
  alert_target: betteruptime_policy escalation (paid) / email (free); Sentry issue alert for verify failures
  configured_in: apps/web-platform/infra/uptime-alerts.tf; apps/web-platform/infra/ci-deploy.sh
error_reporting:
  destination: Sentry (ci-deploy.sh final_write_state + logger + Sentry); BetterStack incident on monitor down
  fail_loud: true (WARN logs+Sentry; ENFORCE additionally fail-closed, keeps old container)
failure_modes:
  - mode: host dead/never-booted
    detection: per-host monitor non-200 (522) after confirmation_period — in-CF-edge probe, no host self-report
    alert_route: betteruptime_policy / email
  - mode: cosign verify fail (unsigned/tampered/wrong-identity)
    detection: verify exit != 0 -> Sentry {stage, image_ref, verify_result in {unsigned,wrong_identity,tampered,inspect_failed,cosign_absent,rekor_unreachable}}
    alert_route: Sentry issue alert
  - mode: probe hostname misconfigured (522 on a healthy host = false page)
    detection: betteruptime confirmation_period + operator monitor-status read
    alert_route: email
logs:
  where: BetterStack incident log; host journald (ci-deploy cosign output); Sentry
  retention: vendor defaults
discoverability_test:
  command: cosign verify --offline --certificate-identity-regexp='^https://github\.com/jikig-ai/soleur/\.github/workflows/reusable-release\.yml@(refs/heads/main|refs/tags/v[0-9].+)$' --certificate-oidc-issuer=https://token.actions.githubusercontent.com ghcr.io/jikig-ai/soleur-web-platform:latest ; curl -sf https://web-1.app.soleur.ai/health
  expected_output: cosign exit 0 (post-sign) ; curl HTTP 200
```

**Soak (2.9.1):** the WARN→ENFORCE flip is **signal-gated** (a signed release exists + one clean WARN deploy — AC16), not time-soak-gated, so no follow-through soak script is enrolled. The flip is a tracked fast-follow (Phase 2.4).

## Architecture Decision (ADR/C4)

### ADR
**Amend ADR-082** (implements ADR-082's own items — not a new ADR) via `/soleur:architecture`:
- **Item 1 §:** replace "DEFERRED, blocked on #5887" with the trigger-cleared certification (apply green → web-1 now; web-2 record+monitor ride #5274).
- **Item 4 §:** record signing + the **deploy-path** verify, and — as an **explicit sub-decision** (architecture P2) — *why* verify extends to `ci-deploy.sh` (the `ignore_changes=[user_data]` gap leaves running hosts unprotected by the fresh-boot pin) and why that is an amendment, not a new ADR. Note fresh-host verify + digest-pin (Doppler `TF_VAR_image_digest`, not committed tfvars) ride #5274.
- **Relates-to:** #5887 (closed CI fix) → #5274 Phase 3.D.
- **Alternatives:** add "verify-by-tag (rejected: mutable, TOCTOU) → verify-by-digest"; "committed tfvars digest threading (rejected: commit-loop/apply-race) → Doppler."

### C4 views
Read all three `.c4` files. Existing external systems: anthropic, github, cloudflare, doppler, discord, stripe, plausible, resend, ghcr; `hetzner` compute + `hetzner -> ghcr` pull edge (`model.c4:164,238,301`). **Better Stack and Sigstore are NOT modeled** → both items add external systems:
- **PR1:** `betterstack = system "Better Stack" #external` + `betterstack -> hetzner "Per-host origin uptime probe (web-1.app.soleur.ai, CF-proxied)"` + `views.c4` include.
- **PR2:** `sigstore = system "Sigstore" #external` + `github -> sigstore "Keyless-signs release image (cosign)"` + `hetzner -> sigstore "Verifies image signature at deploy"` + `views.c4` includes.
- Run `apps/web-platform/test/c4-code-syntax.test.ts` + `c4-render.test.ts` after each edit. No new human actors; no access-relationship change.

## Domain Review

**Domains relevant:** Engineering, Product, Legal (carry-forward from brainstorm).

### Engineering (CTO)
**Status:** reviewed (carry-forward + plan-review round). **Assessment:** ADR-082-locked. Plan-review reshaped scope (fresh-host pieces → #5274) and hardened the cosign design (offline bundle vs #5945 egress firewall; identity regexp pinned to main+tags; run-verified-digest; cosign-absent handling).

### Product (CPO)
**Status:** reviewed (carry-forward). **Assessment:** Item 4 higher-severity (RCE), Item 1 higher-likelihood. Item 1 first. Host-attributed alert only (YAGNI). `requires_cpo_signoff: true`.

### Legal (CLO)
**Status:** reviewed (carry-forward). **Assessment:** no signing compliance weight (Rekor no PII). **OP1:** BetterStack Vendor DPA pending operator signature (`compliance-posture.md:83`) — close before wide per-host rollout.

### Product/UX Gate
**Tier:** none. Pure infra — no UI-surface file.

## Acceptance Criteria

### PR 1 — Item 1

**Pre-merge:**
- [ ] AC1: `web_hosts` gains `monitored = optional(bool, true)`; web-2 `monitored=false`; validations preserved; `terraform validate` passes.
- [ ] AC2: `cloudflare_record.web_host` uses `for_each = { … if v.monitored }` (**web-1 only**), mirrors `cloudflare_record.app` (`content =`, `proxied = true`, `name = "${each.key}.app"`). `terraform plan` shows **no `hcloud_server.web["web-2"]` create**.
- [ ] AC3: `betteruptime_monitor.web_host` uses the SAME `if v.monitored` filter; `pronounceable_name` interpolates `each.key`; `policy_id` mirrors the paid-tier gate.
- [ ] AC4: `apply-web-platform-infra.yml` plan+apply `-target` sets both include `cloudflare_record.web_host` and `betteruptime_monitor.web_host`.
- [ ] AC5: `model.c4`+`views.c4` add `betterstack` + probe edge; `c4-code-syntax.test.ts`+`c4-render.test.ts` pass.
- [ ] AC6: ADR-082 Item 1 § amended + Relates-to → #5274. PR body `Ref #5933`.

**Post-merge (pipeline, automatable via Bash — no operator step):**
- [ ] AC7: after apply, `curl -sf https://web-1.app.soleur.ai/health` → 200; BetterStack shows web-1 monitor green.

### PR 2 — Item 4

**Pre-merge:**
- [ ] AC8: `reusable-release.yml` has `id-token: write` + pinned `sigstore/cosign-installer` + `cosign sign --yes …@${{ steps.docker_build.outputs.digest }}` with an offline-verifiable bundle. `actionlint` passes.
- [ ] AC9: `ci-deploy.sh` after `:805`: resolves the pulled digest (empty/multi → Sentry `inspect_failed`), ensures cosign present (absent → Sentry `cosign_absent`), `cosign verify --offline <digest>` with the **main+tags-pinned** identity regexp, then `docker run` the **verified digest** (not `:$TAG`). WARN mode does not `final_write_state 1`.
- [ ] AC10: identity regexp is `@(refs/heads/main|refs/tags/v[0-9].+)$` — NOT `refs/(heads|tags)/.+` (verify by grep of `ci-deploy.sh`).
- [ ] AC11: `model.c4`+`views.c4` add `sigstore` + sign/verify edges; c4 tests pass.
- [ ] AC12: ADR-082 Item 4 § amended with the deploy-path rationale sub-decision + Alternatives (verify-by-tag, tfvars-threading rejections). PR body `Closes #5933` (if Item 1 merged) else `Ref #5933`.

**Post-merge (pipeline):**
- [ ] AC13: after the next release, `cosign verify --offline …:latest` (discoverability cmd) exits 0 — a signed image exists and is offline-verifiable.
- [ ] AC14: ENFORCE flip is a tracked fast-follow, landed only after AC13 holds + one clean WARN deploy.

## Risks & Mitigations / Sharp Edges

- **web-2 premature provisioning (P0, fixed).** The `if v.monitored` filter on BOTH record and monitor is load-bearing — an ungated `for_each` pulls `hcloud_server.web["web-2"]` into a `-target` apply and provisions web-2 outside the maintenance window. AC2 asserts no web-2 create in `terraform plan`.
- **cosign identity under-anchoring (P0, fixed).** `refs/(heads|tags)/.+` accepts any intra-repo branch/tag signature → ENFORCE would accept attacker-branch RCE. Pinned to `main`+release-tags (AC10).
- **Egress firewall vs live Rekor (P1, fixed).** #5945's `cron-egress-allowlist.txt` excludes sigstore/rekor/fulcio → a live-Rekor verify is firewall-blocked. Use attached-bundle **offline** verify. (If offline proves infeasible at /work, the alternative is adding `rekor.sigstore.dev`/`fulcio.sigstore.dev`/TUF to the allowlist — but offline is preferred: no new egress surface.)
- **cosign absent on host + RepoDigests edge cases (P1, fixed).** cosign is not installed today. Install (cloud-init) or verify via a pinned cosign container. Empty/multi RepoDigests + absent-cosign → explicit Sentry `verify_result`, never silent-pass (AC9).
- **TOCTOU on run-by-tag (P2, fixed).** `docker run` the verified digest, not `:$TAG` (AC9).
- **Rollback to a pre-signing image.** ENFORCE fails closed on an unsigned rollback target; fail-closed keeps the old container (downtime-safe). Operator override via an explicit deploy skip flag — flag for deepen-plan.
- **Item 2 / CF-LB future overlap.** When Item 2's CF Load Balancer origin health-checks land at #5274, they may duplicate this per-host monitor — note in ADR-082 so one is retired (simplicity reviewer).
- A plan whose `## User-Brand Impact` is empty/`TBD` fails deepen-plan Phase 4.6. (Filled above.)

## Operator Follow-ups

- **OP1:** BetterStack Vendor DPA pending operator signature (`compliance-posture.md:83`). Close before wide per-host monitoring rollout. Automation: not feasible (a vendor DPA counter-signature is a legal act) — genuine operator action.

## Deferred to #5274 Phase 3.D cutover (tracked, not dropped)

- Fresh-host `cloud-init.yml` cosign verify (offline) before the `:381`/`:466` pulls, emitting the #5921 `emit_fail` envelope with the `verify_result` discriminator (blind-surface in-boot signal).
- `var.image_digest` pin (`default = ""` + tag-fallback; threaded via Doppler `TF_VAR_image_digest`) for fresh boots.
- web-2 `monitored=true` flip (activates its probe record + monitor).
- (Item 2 A-record drain already rides #5274.)
