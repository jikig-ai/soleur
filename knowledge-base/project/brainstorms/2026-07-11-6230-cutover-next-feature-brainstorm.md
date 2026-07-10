---
date: 2026-07-11
topic: lb-weight-gate-doppler and on-host runtime gate (next from #6027 epic, #6230 context)
issue: 6230
refs: ["6027", "6218", "6178"]
branch: feat-feat-6230-next-open-feature-epic
pr: 6327
lane: cross-domain
brand_survival_threshold: single-user incident
status: brainstorm-complete
---

# Brainstorm — Next open feature from Inngest cutover epic (#6230 entry, #6027)

## What We're Building

Identify and scope the next open actionable buildable feature from the Inngest cutover / multi-host epic area, entered via #6230.

**#6230 (OPEN, action-required, p1-high, decision-challenge, type/chore)** is the operator checklist item: "web-2 must be manually quiesced before the Inngest cutover (PR #6218 / #6178)". 

Context (verified):
- Phase-2 `op=execute` cutover (merged #6218) only reaches the LB-routed host (127.0.0.1:8288). Weight-0 warm-standby web-2 self-arms reminders into its *local* Redis.
- No auto capture/quiesce for web-2 (DI-C3). `op=verify` cannot backstop.
- Risks: silent reminder data loss or undetected double-fires against prod Postgres.
- Operator action (pre-cutover window, no-SSH): quiesce web-2 via the **web-2 freeze/recreate lifecycle** (runbook `inngest-server.md` step 1a + plan §Downtime).
- Re-eval (2026-07-08 comment): #6227/#6228 closed won't-build. Manual web-2 recreate is now the **accepted permanent answer** for the one-time cutover. Stays open as cutover-day checklist.

**The broader epic (#6027 OPEN, p3-low, type/feature)**: "feat(infra): live multi-host GA cutover orchestrator (Inngest-dispatched GHA maintenance-window)".

Deferred per `wg-when-deferring-a-capability-create-a`. Explicit next items after warm-standby + shape gate landed:
- lb-weight-gate + runtime-bind probe (separate)
- `lb-weight-gate-doppler.sh` (Doppler prd-sourcing entrypoint)
- On-host runtime gate (in-container `docker exec … curl 127.0.0.1:3000/internal/readyz` requiring `workspaces_writable && populated` with **N≥2 consecutive** + device-identity attach `/dev/disk/by-id/scsi-0HC_Volume_*`)
- Then: shift web-2 LB weight 0→1 → drain web-1 → remove `ignore_changes=[placement_group_id]` → placement-group reboot on drained host → restore, with automatic rollback.

Re-eval criteria (ALL): warm-standby apply clean, gate tests green, LUKS cutover marker + soak elapsed.

**Consensus from domain leaders (CPO + CLO + CTO, brand-critical triad):** The next open actionable buildable feature is **implement `lb-weight-gate-doppler.sh` (Doppler wrapper) + on-host runtime gate** as the immediate next slice of #6027. The full weight/drain/rollback orchestrator remains gated. For #6230 specifically, add verifiable evidence/audit capture for the (now-permanent) manual web-2 quiesce step so it is not a prose checklist.

This is infra/engineering (no new user-facing UI).

## User-Brand Impact

**Artifact:** the lb-weight-gate-doppler.sh + on-host runtime-bind probe (and evidence seam for web-2 quiesce) for the multi-host/Inngest cutover path.

**Vector:** A misrouted or incompletely attached web-2 (or unquiesced web-2 during Inngest cutover) can cause silent loss of scheduled reminders/actions or double-fires against prod data, or route live git-data workspaces to a host without the LUKS volume mounted — single-user (or small cohort) data integrity / availability incident.

**Threshold:** single-user incident.

Tagged as **user-brand-critical** (auto, per #5175). CPO + CLO + CTO were spawned in parallel at Phase 0.5.

## Why This Approach

- Warm-standby + pure shape gate (`lb-weight-gate.sh`) + web-2 recreate dispatch already shipped (see #6218, apply workflow, 2026-07-04 plan).
- The pure gate is intentionally injected-env only and emits `requires_runtime_bind_probe=true` + "SHAPE-ONLY — NOT weight-flip authorization".
- Doppler wrapper is the missing callable surface (GHA / future orchestrator / operator verification today).
- On-host runtime gate (N-consec readyz + disk attach) is the *distinct required condition* called out in the gate, server.tf HARD GATE comment, and epic body.
- Directly addresses the #6230 residual by making the quiesce step produce observable evidence (tying into the same probe/gate patterns) without reviving the closed #6227 scope.
- Low-risk entry: read-mostly, testable in isolation/dark, re-uses existing no-SSH dispatch + Doppler patterns, no TF/LB changes yet, no live-origin reboot.
- High value: completes the documented de-manualization arc (ADR-068), prevents "workspace-gone" and scheduled-data-loss classes, enables safe GA cutover later.

## Domain Assessments

**Assessed:** Marketing (N/A for pure infra), Engineering, Operations, Product, Legal, Sales (N/A), Finance (N/A), Support (N/A)

### Engineering (CTO)

See full subagent output. Key:
- Verified all gh states + Doppler (LUKS marker absent → #6027 still deferred).
- Shipped: lb-weight-gate.sh (pure/fail-closed/SHAPE-ONLY + parity tests), warm-standby dispatch, readiness.ts, server.tf comments, runbooks.
- Missing: lb-weight-gate-doppler.sh, dedicated runtime gate script.
- Risks: LB not yet in TF, host-targeting fundamental gap (shared with DI-C3), separate runtime vs shape contract must be preserved, timing across Inngest + multi-host cutovers.
- Recommendation: Start with doppler wrapper (thin, GHA-friendly, pattern-matched to ci-deploy/bootstrap). Then runtime gate. Full orchestrator later. Observability block + no-SSH discoverability test mandatory.

### Product (CPO)

See full subagent output. Key:
- Operator (founder/CEO) is the user for cutover tooling.
- High value: de-manualizes multi-host GA, prevents workspace-gone / data-loss incidents (single-user threshold).
- Low risk for this slice (probes first): no prod writes, dark-launchable, re-uses dispatch paths, matches existing patterns (fail-closed, structured output).
- UX: preserve strict separation of gates, structured output, N-consec, recovery, BetterStack markers, explicit messaging.
- Validation gaps: no doppler wrapper, runtime not wired, readyz alone insufficient for attach proof (apply output is current attach evidence).
- Questions: exact contracts, LB weight implementation later, interaction with #6230 recreate, soak sequencing.
- Scoped next: lb-weight-gate-doppler.sh + on-host runtime gate.

### Legal (CLO)

See full subagent output. Key:
- Verified states (gh + bounded).
- Data loss: reminder.scheduled events (Inngest local Redis on web-2) can be silently dropped or double-fired. Payloads touch workspace actions indirectly.
- GDPR: Art. 5(1)(f) integrity/availability, Art. 32 security/TOMs, Art. 5(2) accountability, potential Art. 33/34 if high-risk breach. Cutover is a migration control (TOM or PA amendment).
- Auditability: the manual web-2 quiesce must produce timestamped, non-repudiable evidence (webhook/GHA artifact/Doppler audit) — not prose checklist (aligns hr-ship-message-no-operator-checklist).
- **hr-gdpr-gate-on-regulated-data-surfaces directly applicable** (reminder paths + infra touching scheduling). Must invoke in plan/work.
- Recommendations: scope narrowly to evidence capture + gate tie-in; run gdpr-gate; update Article 30 + posture + policies/Last-Updated in lockstep if any new surfaces; no new subproc; observability as gate.
- Questions: whether dropped scheduled event = breach trigger; exact evidence mechanism for quiesce; retention/DSAR for capture artifacts.

**Lane:** cross-domain (forced by USER_BRAND_CRITICAL + infra/auth/data scheduling surface triggers).

## Key Decisions

| # | Decision | Rationale |
|---|----------|-----------|
| 1 | Next feature = `lb-weight-gate-doppler.sh` + on-host runtime gate (readyz N≥2 + disk attach) as first slice of #6027 | Consensus across CPO/CLO/CTO; first unshipped items explicitly listed in epic after shape gate + warm-standby shipped. Directly enables later weight/drain while keeping contract (shape ≠ runtime). |
| 2 | Tie verifiable evidence/audit seam for #6230 web-2 quiesce into the gate work | Manual step is permanent/accepted; must not be a prose operator checklist. Use existing dispatch + structured output patterns for observability/accountability. |
| 3 | Pure probes first (dark / standalone / GHA exercisable); full orchestrator (weight shift + drain + rollback + LB) deferred | Matches epic re-eval criteria + LUKS soak still pending. Low blast radius. |
| 4 | No new TF / LB authoring / live reboot yet | LB resources absent; host targeting gap remains fundamental; full path gated on soak + shape+runtime green. |
| 5 | Observability block + no-SSH discoverability test + gdpr-gate mandatory | Per hr-*-observability, hr-gdpr-gate, hr-no-dashboard-eyeball-pull-data-yourself, cq-write-failing-tests-before. |
| 6 | User-brand-critical (single-user incident) | Misrouted/partial-attach web-2 or unquiesced scheduler state can lose scheduled user actions or git-data workspaces. |

## Open Questions

- Exact runtime gate contract details (N consecutive reads? docker exec + Host:localhost curl on readyz? separate disk ls or extend readyz? attach proof via apply output or new signal?).
- Delivery of on-host runtime gate (infra-config webhook push like inngest-*.sh, or GHA exec via existing mechanisms)?
- Doppler wrapper output format + error propagation (same sub_condition lines as pure gate?).
- How/when to wire LB weight change + verify + drain semantics (new CF API wrapper? when do we author the TF load-balancer resources)?
- Rollback design for weight/placement (symmetric, auto on gate failure post-flip)?
- Interaction/ordering with Inngest cutover #6230 (web-2 recreate affects local Redis; unified pre-GA quiesce helper?) — can the manual checklist retire after probes land?
- LUKS soak timing vs this work (re-eval criteria still require the marker + days).
- Testing: unit for wrapper + dispatch exercises + injected failure for N-consec transients; fixture for volume attach.
- UX for operator: single entrypoint dispatch? GHA summary steps + BetterStack markers? explicit "shape ok, runtime pending" states?
- Any lower-risk first PR (just doppler wrapper + runbook/SEAM updates referencing #6230)?

## Research Notes (synthesized from leaders + local)

- Prior Inngest brainstorms exist (2026-07-07 dedicated host, multiple TR9 migration, 2026-06-17 durability, etc.). This is the post-extraction GA multi-host slice.
- Shape gate + tests + server.tf HARD GATE comments + runbook §1a + cutover-inngest.yml DI-C3 notes all confirm the separation and the manual seam.
- No lb-weight-gate-doppler.sh or runtime gate script on disk.
- Doppler sourcing patterns exist in ci-deploy, soleur-host-bootstrap, git-data-cutover.sh.
- Readiness is intentionally loopback + host-root fallback (does not prove attach).

## Capability Gaps (from leaders)

- Doppler prd entrypoint for the gate (pure gate exists but not callable from GHA without manual env).
- On-host runtime gate implementation + delivery mechanism.
- Evidence/audit surface for the #6230 quiesce step (currently prose + GHA logs).

All gaps cited with evidence from gh verification + file reads/greps in the subagent transcripts.

## Next

Spec generated from this brainstorm. Ready for `/soleur:plan #6027` (or #6230 context) or one-shot on the scoped doppler + runtime gate slice.

Resume prompt (copy-paste after /clear):
/soleur:plan #6027 — lb-weight-gate-doppler and on-host runtime gate (next from cutover epic). Brainstorm: knowledge-base/project/brainstorms/2026-07-11-6230-cutover-next-feature-brainstorm.md. Spec: knowledge-base/project/specs/feat-feat-6230-next-open-feature-epic/spec.md. Branch: feat-feat-6230-next-open-feature-epic. Worktree: .worktrees/feat-feat-6230-next-open-feature-epic/. PR: #6327. Brainstorm complete with 6 key decisions. Ready for planning. Context from #6230 (manual web-2 quiesce) + #6027 (deferred orchestrator).

---

**Session notes:** Entered via /go 6230 "implement next open feature from the epic". Classified per go.md (non-attestation issue + feature intent → brainstorm). Worktree created early + draft PR per skill Phase 0 safety. Triad + deep verification performed. All AGENTS.md hard rules observed (gh state before assert, bounded output, no unbounded, observability citations, etc.).
