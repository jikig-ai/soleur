---
title: "web-1 private-net probe systemd units delivered-but-inert (failed to start; root doppler auth gap)"
date: 2026-07-18
brand_survival_threshold: single-user incident
severity: contained (no user impact; monitors safely paused by fail-loud arm gate)
gdpr_art_33_notifiable: false
gdpr_art_33_rationale: "n/a — availability/observability delivery defect; no personal-data breach, no exfiltration, no unauthorized access. The only credential involved is a read-scoped prd Doppler token delivered to a 600 on-host env file."
gdpr_art_34_notifiable: false
gdpr_art_34_rationale: "n/a — no personal data affected; no data subjects to notify."
issues: [6438, 6548, 6459]
---

# PIR: web-1 private-net probe units delivered-but-inert

## Summary

The three web-1 private-net probe systemd units (`web-zot-consumer-probe`, `web-git-data-probe`,
`web-private-nic-guard`), delivered by commit 14075d1b, **failed to start at runtime**. Their root
`ExecStart` runs `doppler run --config prd …` with no `$HOME` and no `DOPPLER_TOKEN` source, so
doppler died `$HOME is not defined` before exec'ing the probe. No heartbeat pinged.

## Impact

**Contained — no user impact.** The `apply-web-platform-infra.yml` fail-loud arm gate (ADR-117,
measure-then-arm) observed that no beat landed within the deadline and **rolled the three heartbeat
monitors back to PAUSED** — so no false coverage was ever presented to the operator, no false alarm
fired, and web-1 served production traffic normally throughout. The residual exposure was that the
operator's private-net degradation detection stayed **dark** (the #6400 shape — a silent NIC-path
degradation would not have been caught), but the monitors never went live, so this was a *latent
gap in new coverage*, not a regression of existing coverage.

## Detection

Immediate and automated, by design: the fail-loud arm gate caught it on the first apply
(`apply-web-platform-infra.yml` runs 29638706057 push + 29638910260 dispatch), and self-pulled
Better Stack telemetry confirmed 59 systemd supervisor lines with ZERO probe-tagged lines in the
failing window. This is the fail-loud arm gate working exactly as designed.

## Root cause

Two coupled delivery/runtime gaps (no design fault in ADR-123):

1. **No root doppler auth.** A root systemd service gets no `$HOME`, so the doppler CLI's
   `os.UserHomeDir()` init dies before exec'ing the probe. Compounding it, web-1 has no
   `/etc/default/inngest-server` (`web_colocate_inngest` defaults false), so there was no *suitable*
   root-doppler token source on the host (the deploy-owned `webhook-deploy` token imports
   `/tmp/.doppler`, the #6536 clash surface, so it must not be sourced).
2. **Observability file-only, never live.** web-1 installs vector only at cloud-init boot and never
   re-runs cloud-init, so `vector.toml` Source 4's probe `SyslogIdentifier`s were never live on the
   running host — the probes' own FATAL stderr never reached Better Stack, which is why the failure
   was delivered-but-invisible until the arm gate fail-loud'd.

## Resolution

This PR (Ref #6438 #6548): add `Environment=HOME=/root` to the 3 units + a dedicated read-scoped
`doppler_service_token.web_probes` folded into each per-probe env file; fold `vector.toml`
re-delivery + agent reload into the live-prod SSH provisioner so Source 4 goes live on web-1; add a
positive-control canary so a future vector-delivery regression is detectable. Full mechanism +
lessons: `knowledge-base/project/learnings/2026-07-18-web-1-root-doppler-unit-needs-home-and-dedicated-token-and-vector-toml-has-no-running-host-delivery.md`.

## Lessons

- **"Delivered" ≠ "running."** A successful `terraform apply` proves the unit FILE landed, not that
  the unit STARTS. The fail-loud arm gate (measure-then-arm) is what converted a silent
  delivered-but-inert state into a loud, contained rollback — this is the primary control that
  prevented user impact and should be preserved as the pattern for all future boot-armed heartbeats.
- **A new consumer of a fleet pattern inherits none of its proof.** These were the first root-doppler
  units on web-1; the fleet's "root doppler works" did not transfer because web-1's own host had no
  such precedent. Diff the units against the host's working ones before assuming the pattern holds.
- **Ship the component's own error channel first.** The observability delivery gap is what made the
  failure invisible off-box; fixing it is a co-equal deliverable, not an afterthought.

## Action Items & Follow-ups

| Issue | Item | Status |
|-------|------|--------|
| #6459 | Fresh-host cloud-init bake must ALSO write the read-scoped `DOPPLER_TOKEN` into each `/etc/default/web-<probe>`, or a baked host boots units that require the token with nothing writing it (recorded in the ADR-123 amendment as an explicit blocker). | Open — tracked by the existing future-host issue #6459; out of scope for this PR. |
