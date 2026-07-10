---
title: "lb-weight-gate-doppler.sh + on-host runtime gate (next slice of #6027 multi-host GA cutover orchestrator)"
date: 2026-07-11
type: feat
lane: cross-domain
brand_survival_threshold: single-user incident
status: spec
refs: ["6230", "6027", "6218", "6178"]
closes: []
---

# Spec — lb-weight-gate-doppler.sh + on-host runtime gate

**Brainstorm:** `knowledge-base/project/brainstorms/2026-07-11-6230-cutover-next-feature-brainstorm.md`

**Epic context:** #6027 (deferred live multi-host GA cutover orchestrator). Entered via #6230 (accepted permanent manual web-2 quiesce for one-time Inngest cutover).

## Problem Statement

The pure shape-only `lb-weight-gate.sh` (ADR-068 §(c)) and warm-standby/web-2-recreate dispatch paths have shipped. The deferred #6027 orchestrator requires a Doppler-sourced callable entrypoint for the gate and a *distinct* on-host runtime-bind probe (N≥2 consecutive readyz + disk attach proof) before any LB weight shift or drained-host reboot can be authorized.

#6230 surfaced the related residual: weight-0 web-2 is not auto-verified for Inngest capture/quiesce (LB limitation). The manual quiesce is now permanent; it must produce verifiable evidence rather than remaining a prose checklist item.

Without the doppler wrapper + runtime gate:
- No GHA/orchestrator-callable surface exists for the already-written gate.
- The "requires_runtime_bind_probe=true" contract cannot be satisfied.
- Operator evidence for web-2 quiesce (and future weight decisions) remains manual/eyeball-only.

## Goals

- Ship `apps/web-platform/infra/lb-weight-gate-doppler.sh` — thin, fail-closed, Doppler-prd sourcing wrapper around the pure gate. GHA-friendly, pattern-matched to existing bootstrap/ci-deploy.
- Ship on-host runtime gate (delivered script or equivalent): docker exec loopback readyz requiring `workspaces_writable && populated` for N≥2 consecutive + disk attach check (`/dev/disk/by-id/scsi-0HC_Volume_*` or equivalent).
- Emit structured output compatible with future orchestrator (sub_condition lines + requires_* markers).
- Add verifiable evidence/audit seam for the #6230 web-2 quiesce step (timestamped, non-SSH, observable via GHA/deploy-status/BetterStack).
- Preserve strict separation: shape gate alone never authorizes weight flip.
- All changes respect no-SSH, immutable-redeploy, observability-as-gate, and user-brand-critical (single-user incident) posture.
- Tests first (unit + dispatch exercise).
- Update SEAM/runbook references + cutover-inngest.yml comments for the new evidence surface (no new long docs).

## Non-Goals

- Full live cutover orchestrator (weight 0→1, web-1 drain, placement_group reboot on drained host, automatic rollback, Inngest dispatch of the window). Still deferred behind LUKS soak + re-eval criteria in #6027.
- Authoring Cloudflare LB resources / pools / monitors in TF (still absent; count-gated in plans).
- Per-host web→web:8288 fan-out or host-targeting for Inngest (explicitly won't-build for the one-time cutover).
- Changes to readyz surface itself (loopback + Host gate stays; attach proof remains apply output for now).
- New TF variables or operator-mint defaults.
- Any UI, user-facing flows, or new scheduled functions.

## Functional Requirements

FR1: Doppler wrapper script exists at `apps/web-platform/infra/lb-weight-gate-doppler.sh` that:
- Sources the required vars from Doppler `soleur/prd` (SOLEUR_PROXY_BIND, SOLEUR_PROXY_PEER_ALLOWLIST, SOLEUR_HOST_ROSTER, GIT_DATA_STORE_ENABLED, GIT_DATA_LUKS_CUTOVER_AT, GIT_DATA_LUKS_SOAK_DAYS).
- Exports them and invokes the pure gate.
- Propagates exit code and structured stderr/stdout.
- Is executable via `doppler run --project soleur --config prd -- ./lb-weight-gate-doppler.sh` and from GHA (DOPPLER_TOKEN).

FR2: On-host runtime gate (script or inline in existing hook delivery) performs N≥2 consecutive successful `docker exec ... curl -H 'Host: localhost' http://127.0.0.1:3000/internal/readyz` checks (workspaces_writable && populated) plus a device attach check. Emits structured success/fail. Separate from shape gate.

FR3: The two gates remain contractually distinct (shape prints `requires_runtime_bind_probe=true`; runtime is the additional required condition). server.tf HARD GATE comments and cutover docs updated only with facts.

FR4: Verifiable evidence for #6230 web-2 quiesce (via existing web-2-recreate dispatch path or new marker): timestamped, machine-readable status (e.g. deploy-status reason, GHA artifact, or lightweight capture) that can be asserted in SEAM without SSH or eyeball.

FR5: Unit tests + at least one dispatch exercise (GHA or local) that exercises the wrapper without performing weight changes.

FR6: Observability: 5-field block declared for any new writer/reader; discoverability_test.command is runnable with no SSH (per hr-observability-as-plan-quality-gate).

FR7: No new operator checklist prose; any manual step is backed by observable evidence.

## Technical Requirements

TR1: Pure gate contract preserved exactly (injected-env only for the core; wrapper only adds sourcing).

TR2: Fail-closed + structured output (gate_fail sub_condition=... or equivalent JSON) for easy future orchestrator parsing.

TR3: Follows existing patterns: timeout/retry Doppler, R2/GHA dispatch, private-net delivery where needed, Vector/BetterStack tagging.

TR4: No new sub-processors, no new PII surfaces requiring extra DPA (run gdpr-gate in plan phase).

TR5: Re-uses web-2-recreate / warm-standby apply_target paths for evidence where possible.

TR6: Lane: cross-domain (infra + scheduling + data-integrity surfaces).

## Acceptance Criteria

- `lb-weight-gate-doppler.sh` + test(s) land on main; can be invoked standalone and from apply workflow context.
- On-host runtime gate lands and can be exercised (N-consec + attach) via dispatch or hook.
- #6230 runbook/SEAM updated with evidence assertion (e.g. "confirm post-recreate deploy-status reason or capture marker").
- `server.tf` and cutover-inngest.yml comments reflect reality (no over-claims).
- All new/changed surfaces have observability block + test.
- gdpr-gate invoked and findings addressed (or explicitly N/A).
- Draft PR for this slice references #6027 and #6230.
- Re-eval criteria for #6027 still listed as not-yet-met (LUKS soak etc.).

## Risks & Mitigations

- LB resources / weight API not present → scope explicitly excludes weight flip.
- LUKS marker absent → this work is pre-soak verification only.
- Host targeting limitation (shared DI-C3) → document; do not claim per-host for Inngest.
- Single-user incident threshold → CPO sign-off + user-impact-reviewer at review time.

## Observability

(Declared here per rule; will be expanded in plan.)

- Writers: GHA steps for gate execution, any new capture markers.
- Readers: future orchestrator + existing verify jobs.
- discoverability_test: `doppler run ... lb-weight-gate-doppler.sh` + GHA log grep for sub_condition + deploy-status reason check (no SSH).
- Events: gate_fail, requires_runtime_*, web2_quiesce_evidence.

## References

- Brainstorm (this session)
- #6027, #6230, #6218, #6178
- `apps/web-platform/infra/lb-weight-gate.sh` + `.test.sh`
- `apps/web-platform/infra/server.tf` (HARD GATE comments)
- `.github/workflows/apply-web-platform-infra.yml` (warm_standby + web_2_recreate)
- `knowledge-base/engineering/operations/runbooks/inngest-server.md`
- ADR-068, 2026-07-04 multi-host plan
- `apps/web-platform/server/readiness.ts`

**Lane:** cross-domain (per brainstorm Phase 0.4 + USER_BRAND_CRITICAL).
