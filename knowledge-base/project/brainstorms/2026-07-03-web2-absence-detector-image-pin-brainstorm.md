# Brainstorm: Per-host absence detector + image digest-pin & signature (#5933 items 1 & 4)

- **Date:** 2026-07-03
- **Issue:** #5933 (chore(infra): fresh web-2 boot observability prerequisites)
- **Scope:** Items 1 (per-host uptime absence detector) and 4 (image digest pin + signature verification) only
- **Governing ADR:** ADR-082 (Fresh web-2 boot observability + supply-chain hardening contract)
- **Nature:** Certification + scoping refinement — the design is ADR-locked, not open. This brainstorm certifies a cleared deferral trigger and resolves one open scope decision, then hands to `soleur:plan`.

## What We're Building

Two of the four controls in ADR-082's fresh-host observability contract, delivered as **two separate PRs, Item 1 first**:

1. **Per-host uptime absence detector (Item 1).** A CF-**proxied** per-host probe hostname (`web-<n>.app.soleur.ai` → the specific origin IP, preserving the CF-only origin firewall in `firewall.tf`) + a `betteruptime_monitor` `for_each` over a `monitored`-gated subset of `var.web_hosts`. web-1 monitored now; web-2 gated (`monitored=false`) until the #5274 cutover creates it.
2. **Image digest pin + signature verification (Item 4).** Pin `var.image_name` from `:latest` to `@sha256:<digest>` (emitted by `reusable-release.yml` build → new `var.image_digest`), add cosign-keyless (GitHub OIDC) signing to the release pipeline, and verify the signature **at both consumption points**: fresh-host `cloud-init.yml` (before `docker pull`/`run`) **and** the running-host deploy path `ci-deploy.sh` (before `docker run`).

## Why This Approach

- **The design is already decided (ADR-082, Adopting, 2026-07-03).** ADR-082 settled the mechanism for all four items and shipped Item 3 (egress-enforcement probe, PR #5945). Re-deriving the design would be theatre; the honest task is to certify triggers and refine scope. Per the "read the governing ADR before extending its decision" learning, we build ON ADR-082, not around it.
- **Item 1's deferral trigger has cleared.** ADR-082 deferred Item 1 solely because `apply-web-platform-infra.yml` was RED (#5887 `moved`-block breakage) — a new `cloudflare_record` couldn't auto-apply, and a monitor pointed at a not-yet-created hostname pages immediately. #5887 is now **fixed & merged**; the pipeline's last two `main` runs (2026-07-03 12:27, 16:09) are **green**. web-1 exists, so its `monitored`-gated per-host coverage is shippable now with zero dependency on the deferred #5274 DNS rewire.
- **Item 4 extended to both verify paths (operator decision).** ADR-082 as written specifies a cosign verify only at fresh-host `cloud-init.yml`. But `var.image_name` is consumed **only** by fresh-host cloud-init; routine deploys pull `$IMAGE:$TAG` via `ci-deploy.sh` (webhook payload, `ALLOWED_IMAGES` allowlist), and `ignore_changes=[image]` (`server.tf:153`) means the TF digest-pin never touches a *running* host. The running web-1 — which serves users today — is the higher-severity RCE surface (CPO: all-users, unrecoverable). Verifying at **both** paths closes it. **This extends ADR-082 → an ADR-082 amendment is a plan deliverable.**

## Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Item 1 detector mechanism | CF-proxied per-host probe hostname + `betteruptime_monitor for_each` (ADR-082) | Reaches origin via CF edge (firewall-allowed), preserves WAF/CF-only gate, needs no host self-report; catches origin-down/never-booted as 522. Rejected: raw-origin-IP (firewall gates 443 to CF IPs), unproxied grey-cloud (exposes origins; no stable vendor probe ranges). |
| Item 1 web-2 gating | `monitored = optional(bool, true)`; `web-2 = { … monitored = false }` until #5274 cutover | A monitor at a not-yet-created hostname pages immediately (522/NXDOMAIN). web-1 ships now. |
| Item 1 unblock certification | Ship now (deferral trigger cleared) | `apply-web-platform-infra.yml` green post-#5887. |
| Item 4 digest resolution | Pipeline-resolved digest → `TF_VAR_image_digest` at apply (ADR-082) | Deterministic; keeps bake-extract + run coherent. Rejected: TF data-source resolve-at-plan (nondeterministic plans, drift noise). |
| Item 4 signing | cosign keyless (GitHub OIDC identity) in `reusable-release.yml` | No key storage/rotation burden; Rekor public log carries no PII (CLO). Must land **before** any verify gate or fresh-host boot fails closed on unsigned `:latest`. |
| **Item 4 verify scope** | **Both paths — `cloud-init.yml` AND `ci-deploy.sh`** | Closes the running-web-1 RCE surface that the fresh-host-only pin misses. Extends ADR-082. |
| Delivery | **Two PRs, Item 1 first** | Item 1 = small TF-only, unblocked now; Item 4 = cross-cutting release-pipeline + cosign, security-reviewed. ADR-082 keeps Item 4 its own PR. |
| Visual design | N/A — pure infra, no UI surface | Phase 3.55 skip is legitimate (no page/component/banner). |

## Open Questions

1. **Item 4 signing→verify sequencing within its PR.** Signing must be live in `reusable-release.yml` and a signed image must exist before the verify gate activates, or the next fresh-host boot / deploy fails closed on an unsigned image. Plan must sequence: sign → publish one signed release → then enable verify (possibly behind a soft-fail warn window). Decide the cutover mechanic at plan time.
2. **cosign verify identity/policy pinning.** Exact `--certificate-identity` (workflow ref) + `--certificate-oidc-issuer` values, and where they live (baked constant vs var). Plan-time.
3. **Manifest-list vs platform digest.** Per `2026-03-19-docker-base-image-digest-pinning.md`, pin the **manifest-list** digest, not a platform-specific one. Confirm the release build emits the index digest.

## User-Brand Impact

- **Artifact:** the per-host web-uptime absence detector + the digest-pinned/signature-verified container-image supply chain for `app.soleur.ai`.
- **Vector:** a fresh/existing web host boots into silent failure no per-host monitor catches (users get intermittent, unattributed 5xx from the round-robin subset), **or** an unpinned/unsigned `:latest` image (typo-squat / GHCR compromise) runs with full RCE on the host serving every user.
- **Threshold:** `single-user incident`.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Engineering (CTO)

**Summary:** Design is ADR-082-locked and sound. Key refinement: `var.image_name` hardens only the fresh-host path (`ignore_changes=[image]`; deploys use `ci-deploy.sh` webhook payload) — the running-host deploy path needs a separate cosign verify. Signing must precede any verify gate. Item 1 meaningfully covers only web-1 pre-cutover.

### Product (CPO)

**Summary:** Item 4 = higher-severity (RCE, all users, unrecoverable); Item 1 = higher-likelihood (fires the instant web-2 boots; today unattributed 5xx are effectively undiagnosable for a non-technical operator). Recommends Item 1 first, Item 4 immediately after. Only justified user surface: a host-attributed plain-language alert, optionally one operator-digest line. No status page/banner at founder scale (YAGNI).

### Legal (CLO)

**Summary:** No compliance weight in signing itself — no SLSA/"signed image" claim exists to contradict; keyless cosign's Rekor log carries no PII; BetterStack/Sentry already recorded sub-processors with opaque-ping payloads. One real follow-up: the **BetterStack Vendor DPA is pending operator signature** (`compliance-posture.md:83`); Item 1 broadens BetterStack to per-host probes, so close that signature before wide rollout.

## Capability Gaps

None. All execution is covered by existing agents (terraform-architect, infra-security, observability-coverage-reviewer, security-sentinel) and existing infra primitives. Evidence:
- Monitoring substrate exists: `uptime-alerts.tf:53` (`betteruptime_monitor.soleur_apex`), `sentry/uptime-monitors.tf:53-194`, `var.web_hosts` (`variables.tf:69`).
- Release pipeline exists: `.github/workflows/reusable-release.yml:579-615` (docker build-push). cosign is a net-new step in an existing workflow, not a new capability.
- CF Load Balancer confirmed absent (grep of all `*.tf`) — but ADR-082's proxied-hostname approach does not require one.

## Session Errors

1. **Issue #5933 body cites a stale/wrong blocker.** It says the work "blocks #5887" and calls #5887 "the operator cutover." #5887 is a **CLOSED** Terraform `moved`-block CI fix, not a provisioning cutover. The real web-2 provisioning cutover is **#5274 Phase 3.D** (OPEN), per `dns.tf:4`. ADR-082 inherited the same mis-citation. **Fix:** the issue body was corrected during this brainstorm; the ADR-082 "Relates to" line should be corrected at plan/ship time.
2. **Issue #5933 item 3 already shipped.** Item 3 (post-container egress-enforcement probe) merged via **PR #5945** ("Ref #5933", not "Closes"). The issue body still lists it as open. Corrected in the issue body during this brainstorm.
3. **Issue #5933 claims `uptime-alerts.tf` has no per-host monitor "in the root."** The file exists and the claim (no *per-host* monitor) is accurate, but the phrasing implied the file was absent. Verified: only apex/www/acme monitors exist; no `for_each`-over-`var.web_hosts` monitor.

## Handoff

Design is ADR-082-locked + certified unblocked. Next: `soleur:plan` to produce the two-PR task breakdown (Item 1 first). Plan deliverables include an **ADR-082 amendment** (Item 4 dual-path verify; corrected #5887→#5274 blocker) per `wg-architecture-decision-is-a-plan-deliverable`.
