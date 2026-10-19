---
title: Per-host absence detector + image digest-pin & signature (#5933 items 1 & 4)
issue: 5933
lane: cross-domain
brand_survival_threshold: single-user incident
governing_adr: ADR-082
status: spec
created: 2026-07-03
---

# Spec: Per-host absence detector + image digest-pin & signature

## Problem Statement

Two of ADR-082's four fresh-host observability controls are unshipped and are prerequisites of the web-2 provisioning cutover (#5274 Phase 3.D):

- **Item 1 — no per-host uptime absence detector.** All web monitors target the apex or `app.soleur.ai` (a CF round-robin with no origin health-check). A dead/never-booted host serves intermittent, unattributed 5xx to a round-robin subset of users; a non-technical operator cannot diagnose it. `uptime-alerts.tf` has only apex/www/acme monitors.
- **Item 4 — the container image runs unpinned & unsigned.** `var.image_name` defaults to `:latest`; the running host serving all users can be given a typo-squatted / registry-compromised image (full RCE, total user-data exposure). The `host_scripts_content_hash` is a coherence control, not a supply-chain control.

Items 2 (A-record drain) and 3 (egress probe) are out of scope: Item 3 shipped (PR #5945); Item 2 rides the deferred #5274 DNS rewire (in-flight runbook PR #5968).

## Goals

- **G1.** Ship a per-host CF-proxied uptime absence detector for the currently-live web-1, `monitored`-gated so web-2 activates at the #5274 cutover. (Item 1)
- **G2.** Pin `var.image_name` from `:latest` to an immutable `@sha256` manifest-list digest emitted by the release pipeline. (Item 4)
- **G3.** Add cosign-keyless (GitHub OIDC) signing to `reusable-release.yml` and verify the signature at **both** consumption points: fresh-host `cloud-init.yml` and running-host `ci-deploy.sh`. (Item 4)
- **G4.** Deliver as two separate PRs, Item 1 first.
- **G5.** Amend ADR-082 (Item 4 dual-path verify; correct the #5887→#5274 blocker citation).

## Non-Goals

- **NG1.** Item 2 (A-record drain / CF LB round-robin health) — rides #5274 cutover.
- **NG2.** Re-examining Item 3 (shipped, #5945).
- **NG3.** web-2 live monitoring — gated `monitored=false` until the #5274 cutover creates web-2.
- **NG4.** A user-facing status page or in-app banner (YAGNI at founder scale; a dead host can't serve one). A host-attributed operator alert is sufficient.
- **NG5.** Changing the routine deploy tag strategy (semver + `ALLOWED_IMAGES` allowlist stays); Item 4 adds a verify gate, not a new tag scheme.

## Functional Requirements

- **FR1.** A CF-proxied per-host probe hostname `web-<n>.app.soleur.ai` resolving to each host's origin IP, preserving the CF-only origin firewall (`firewall.tf`). [→ ADR-082 Item 1]
- **FR2.** A `betteruptime_monitor` `for_each` over a `monitored`-gated subset of `var.web_hosts`; add `monitored = optional(bool, true)` to the object type; `web-2 = { … monitored = false }`.
- **FR3.** Monitor alert wiring reuses the existing `betteruptime_policy` free-tier/paid-tier pattern (`uptime-alerts.tf`); alert text is host-attributed and plain-language.
- **FR4.** `reusable-release.yml` emits the pushed **manifest-list** digest and cosign-keyless signs the image.
- **FR5.** `var.image_digest` (new) threads the digest so `cloud-init.yml` pulls/runs the pinned `@sha256`.
- **FR6.** cosign verify gate before `docker run` in **both** `cloud-init.yml` (fresh-host) and `ci-deploy.sh` (deploy path), pinned to the release workflow's OIDC identity + issuer.

## Technical Requirements

- **TR1.** No raw-origin-IP or unproxied grey-cloud probes (origin firewall gates 443 to CF IPs; unproxied exposes origins). [ADR-082 rejected alternatives]
- **TR2.** Signing must be live and one signed image must exist **before** any verify gate activates (else fresh-host boot / deploy fails closed on unsigned `:latest`). Sequence sign → publish → enable-verify within the Item 4 PR.
- **TR3.** Pin the manifest-list (index) digest, not a platform-specific digest; update tag and digest together. [`2026-03-19-docker-base-image-digest-pinning.md`]
- **TR4.** Account for `ignore_changes=[image]` (`server.tf:153`): the TF digest-pin does not touch running hosts — the `ci-deploy.sh` verify (FR6) is what protects them.
- **TR5.** Observability: every new failure path (monitor-down alert, verify-fail) must be reachable without SSH (BetterStack alert; cosign-verify failure surfaces in the deploy/boot Sentry envelope). [`hr-observability-as-plan-quality-gate`, `hr-no-ssh-fallback-in-runbooks`]
- **TR6.** No detector reads from the surface it protects (no tautology): the external proxied monitor does not depend on the host self-reporting. [`hr-no-dashboard-eyeball-pull-data-yourself`]

## Operator / Compliance Follow-ups

- **OP1.** BetterStack Vendor DPA is pending operator signature (`compliance-posture.md:83`); close before wide per-host monitoring rollout (CLO). Track as its own action, not a code blocker.

## Domain Review (carry-forward)

- **Engineering (CTO):** ADR-locked; dual-path verify refinement is the load-bearing addition; sign-before-verify sequencing is the top risk.
- **Product (CPO):** Item 4 higher-severity, Item 1 higher-likelihood; Item 1 first; host-attributed alert only.
- **Legal (CLO):** no signing compliance weight; BetterStack DPA signature is the one follow-up (OP1).

## References

- Governing: ADR-082; issue #5933; brainstorm `2026-07-03-web2-absence-detector-image-pin-brainstorm.md`.
- Precedent: `2026-03-19-docker-base-image-digest-pinning.md`, `feat-supply-chain-hardening/`, `feat-renovate-docker-digest-816/`.
- Context: #5945 (Item 3 shipped), #5274 Phase 3.D (real cutover), #5968 (Item 2 runbook), fresh-host-bootstrap-recovery runbook.
