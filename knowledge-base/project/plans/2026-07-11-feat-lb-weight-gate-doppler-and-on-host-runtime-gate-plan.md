---
title: "feat: lb-weight-gate-doppler.sh + on-host runtime gate (next slice of #6027 multi-host GA cutover orchestrator)"
date: 2026-07-11
type: feat
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
refs: ["6027", "6230", "6218", "6178", "5274"]
---

# Plan — lb-weight-gate-doppler.sh + on-host runtime gate (next from #6027 / #6230 context)

**Brainstorm:** `knowledge-base/project/brainstorms/2026-07-11-6230-cutover-next-feature-brainstorm.md`

**Spec:** `knowledge-base/project/specs/feat-feat-6230-next-open-feature-epic/spec.md`

**Epic context:** #6027 (deferred live multi-host GA cutover orchestrator, p3-low). Entered via #6230 (p1-high action-required manual web-2 quiesce for one-time Inngest cutover; now accepted permanent per re-eval).

## Overview

The pure shape-only `lb-weight-gate.sh` (ADR-068 §(c)) and the warm-standby + web-2-recreate dispatch paths have shipped. The deferred orchestrator in #6027 requires:
- A Doppler-`prd` sourcing entrypoint (`lb-weight-gate-doppler.sh`) that injects the exact env the pure gate expects and execs it.
- A *distinct* on-host runtime-bind gate (N≥2 consecutive `docker exec ... /internal/readyz` (writable+populated) + disk attach check) before any LB weight shift or drained-host reboot.

#6230 surfaced the residual: weight-0 warm-standby web-2 self-arms into its local Redis and is not auto-captured/quiesce-verified by LB-routed hooks (DI-C3). The manual web-2 freeze/recreate quiesce (via existing `apply_target=web-2-recreate`) is the accepted permanent seam. It must produce verifiable, non-SSH evidence (timestamped marker / deploy-status reason / GHA artifact) rather than remaining prose in a checklist.

**Why now:** Warm-standby + shape gate + recreate dispatch are in place. The next unshipped items explicitly listed in #6027 are the doppler wrapper and runtime gate. This is low-risk (read-mostly probes, dark-launchable, no weight/drain/rollback yet) but high-value for de-risking GA multi-host and making the #6230 manual step auditable.

**Brand-survival threshold:** single-user incident (misrouted/incompletely-attached web-2 or unquiesced scheduler state can lose scheduled reminders or route live git-data workspaces to a host without the LUKS volume).

## User-Brand Impact

- **If this lands broken, the user experiences:** live git-data workspaces routed to a web-2 without attached LUKS volume (or scheduled reminders silently dropped/double-fired) during a future weight shift or Inngest cutover.
- **If this leaks, the user's [data / workflow / money] is exposed via:** silent loss of scheduled actions or git-data misroute on a drained/live origin (single-user or small-cohort integrity/availability incident).
- **Brand-survival threshold:** single-user incident

## Research Reconciliation — Spec vs. Codebase + Learnings

**From spec (verified on origin/main + worktree):**
- Pure gate + test + server.tf HARD GATE comments + readiness.ts exist and match the "SHAPE-ONLY + requires_runtime_bind_probe=true + separate runtime" contract.
- No `lb-weight-gate-doppler.sh` and no dedicated on-host runtime gate script (docker exec + N≥2 + attach).
- Doppler sourcing patterns exist (ci-deploy, git-data-cutover, bootstrap, inngest-*); pure gate intentionally takes injected env only.
- Workflows (apply-web-platform-infra.yml, cutover-inngest.yml) + runbooks (inngest-server.md, moved-block-wedge-cutover-5887.md) + ADR-068/105/106 already document the separation and #6230 manual seam.
- Attach proof today = terraform apply created-resources output (not probes). Off-host verify via web-1 deploy-status reason.

**From repo research (consolidated):**
- Doppler must be *outside* the pure gate (sourcing shim + `doppler run ... -- exec pure-gate` or equivalent; guarded `--plain`, scoped project/config, timeouts, `|| true` + fallbacks, `logger -t`, no argv leakage).
- Runtime gate must be on-host only (loopback + Host header 403), use write+unlink probe for writable, count dirs for populated, N≥2 consecutive, device attach check.
- Shared patterns: `cat-*.sh` atomic state, deploy-status-fanout-verify, webhook delivery for host scripts, `::notice::` baselines, Vector journald allowlist + PII scrub (new `logger -t` tags must be allowlisted in same change).
- No per-host targeting yet (DI-C3); weight-0 web-2 self-arms independently.

**From learnings (July 2026 cutover focus + ADR-068 lineage):**
- Shape-only vs runtime is load-bearing (never fold; exit 0 alone never authorizes weight).
- N≥2 + flap-safety for any live-origin drain decision.
- #6230 manual web-2 quiesce/recreate is permanent for the one-time cutover; make it produce observable evidence (journald markers + Better Stack pull, not eyeball or SSH).
- Preflight bounding, abandon-safety, in-surface markers (START/DONE/TIMEOUT) for any new scans.
- Observability: `hr-observability-as-plan-quality-gate` + `hr-no-dashboard-eyeball-pull-data-yourself`; pull via `scripts/betterstack-query.sh` under doppler; no SSH in runbooks.
- Recent preflight/pool work (ADR-105/106, #6258) interacts with the same topology; do not assume clean web-2.
- Attach proof = TF apply output; readyz is separate.
- Stale-branch invariant reversion risk (post-merge verification of gate comments/ADR text).
- No new operator checklists; exhaust automation; immutable re-provision.

**Research Reconciliation table (key spec claims vs reality):**
- Spec claim: "Doppler wrapper is the missing callable surface" — Reality: matches (no doppler wrapper exists; pure gate contract explicit). Plan response: implement thin sourcing shim following ci-deploy/git-data patterns.
- Spec claim: "on-host runtime gate (N≥2 readyz + disk attach)" — Reality: readiness.ts exists (on-host only, write probe + populated); no dedicated N≥2 + attach script yet; attach proof is TF state today. Plan response: deliver the distinct gate script + integrate attach check.
- Spec claim: "verifiable evidence seam for #6230 web-2 quiesce" — Reality: prose + GHA logs today; recreate dispatch exists. Plan response: add structured markers + update runbook/SEAM + cutover-inngest comments.
- No C4/ADR change required (re-use ADR-068 §(c) contract).

**Premise validation (0.6):** Cited issues re-verified (6027 OPEN, 6230 OPEN, 6218 MERGED, 6178 OPEN). No "does not yet exist" / deferred-from / blocked-by stale framing in the input that would invalidate the premise. LUKS soak marker still absent (Doppler prd) → #6027 remains correctly deferred. All gate comments, pure gate, and workflows present on origin/main.

## Domain Review

**Domains relevant:** Engineering, Operations, Legal (from brainstorm carry-forward + cross-domain triggers: infra, scheduling state, single-user data integrity, auditability) | Product (advisory only for operator tooling UX)

### Engineering (CTO — carried from brainstorm + reinforced)
Technical implications: Doppler sourcing must stay outside pure gate; runtime gate must be separate (N≥2 + attach); host targeting gap (DI-C3) remains; LB resources not yet in TF. Risks: concurrent-merge invariant reversion, preflight unboundedness (recent July fixes), observability tag allowlisting. Reuse existing patterns (ci-deploy doppler, deploy-status fanout, webhook delivery). Low complexity for wrapper; medium for full gate integration + tests.

### Operations (COO)
Operational: no-SSH dispatch via existing apply_target + webhook paths; verifiable evidence (not prose checklist) for #6230 manual step; pull-your-own-data verification (betterstack-query under doppler, not dashboard). Cost of bad cutover is high (data loss + double-fire). Reuse recreate lifecycle for quiesce evidence.

### Legal (CLO — carried + reinforced)
#6230 manual step now requires auditable evidence for Art. 5(2) accountability (scheduled processing migration). GDPR surface (scheduling reminders, Art. 32 TOMs for cutover integrity). Invoke gdpr-gate. Update Article 30 / posture if new PA/TOM. No new sub-processor. Runbook + SEAM updates must be lockstep with code.

### Product/UX Gate
**Tier:** advisory (operator tooling / infra; no new user-facing pages or flows per spec Non-Goals).

**Decision:** carried from brainstorm (CPO assessed high value for de-risking GA + preventing workspace-gone / scheduled-data-loss; low risk for probes-first slice). No new wireframes required. Operator UX must match reliability bar (single dispatch, clear GHA summaries, structured reasons, no SSH).

**Agents invoked:** none additional (brainstorm CPO carry-forward sufficient for advisory).

## Architecture Decision (ADR/C4)
No new architectural decision. Re-uses ADR-068 §(c) contract exactly (shape-only + distinct runtime probe). No C4 change (infra script + comments + workflow updates inside existing containers).

## Implementation Phases (collapsed per DHH mechanical review — thin probes slice)

This is a **minimal probes-first slice** (no weight shift, no drain, no LUKS soak, dark-launchable). Phases collapsed to three.

### Phase 0 — Setup & Contract Verification
- [ ] Verify pure gate + test + server.tf HARD GATE + readiness.ts + workflows on origin/main.
- [ ] Confirm the shape-only contract (`requires_runtime_bind_probe=true` + banner) and that the pure gate reads *only* injected env.
- [ ] Confirm LUKS soak marker absent (full orchestrator correctly deferred).
- [ ] Read ADR-068 + key July 2026 cutover learnings (DI-C3, no-SSH, preflight bounding).
- [ ] Baseline tests green.

### Phase 1 — On-host runtime gate (thin, concrete delivery)
- [ ] Add a thin on-host runtime gate (target < ~60 LOC, reuse existing readyz logic).
  - `docker exec soleur-web-platform curl -fsS -H 'Host: localhost' http://127.0.0.1:3000/internal/readyz`
  - Require `workspaces_writable && populated`.
  - N≥2 consecutive (fail-closed).
  - Disk attach check (`ls /dev/disk/by-id/scsi-0HC_Volume_*` or equivalent).
  - Emit structured `runtime_gate_ok` / `runtime_gate_fail sub_condition=...`.
- **Concrete delivery (choose one minimal path):**
  - (Preferred) Add to existing infra-config delivery (like `inngest-*.sh`) via `infra-config-apply.sh` FILE_MAP + webhook, or
  - Start with a CI exerciser in a recreate job parity test (no full on-host delivery yet).
- [ ] Tests: real FS, N-consec, attach failure, using existing patterns.

**Files:**
- Create (thin): `apps/web-platform/infra/runtime-bind-gate.sh` (or extend an existing delivered host script).
- Update: relevant tests, parity, and (if chosen) `infra-config-apply.sh` / FILE_MAP.

### Phase 2 — Integration, tests, comments, gates, observability
- [ ] Use direct `doppler run -p soleur -c prd -- ./lb-weight-gate.sh` pattern (document the 6 vars in comments). No new doppler shim file.
- [ ] Minimal fact-refresh comments only in runbooks / `cutover-inngest.yml` (note current TF + deploy-status artifacts for web-2 recreate). Heavy #6230 evidence seam deferred.
- [ ] Add any new `logger -t` tags (if introduced by runtime gate) to `vector.toml` + tests in same change.
- [ ] Short observability citation (reference existing pattern + "add tag if new").
- [ ] Run gdpr-gate (Phase 2.7 of plan skill); fold minimal findings.
- [ ] IaC / no-SSH / user-brand checks (light — script on existing dispatch paths).
- [ ] Update tests (unit + dispatch exercise for runtime gate).
- [ ] `<!-- lint-infra-ignore -->` only where needed for deferred orchestrator prose.

**Deliverables:** Thin runtime gate + tests + contract-preserving comments + gates passed.

## Acceptance Criteria (updated per DHH mechanical review)

- [ ] Direct `doppler run -p soleur -c prd -- ./lb-weight-gate.sh` pattern documented and exercisable (no dedicated `lb-weight-gate-doppler.sh` shim created in this slice).
- [ ] Thin on-host runtime gate (< ~60 LOC preferred) exists: docker exec readyz (writable + populated), N≥2 consecutive, disk attach check; emits structured output distinct from shape gate.
- [ ] Runtime gate is delivered via a concrete minimal path (infra-config/webhook or CI exerciser in recreate parity test).
- [ ] Tests green for runtime gate (real FS, N-consec, attach failure); pure gate contract preserved (`requires_runtime_bind_probe=true` banner + shape-only semantics).
- [ ] Minimal fact-refresh comments only for #6230 web-2 recreate (heavy evidence seam deferred).
- [ ] Any new logger tags (if any) added to vector.toml + tests in same change.
- [ ] gdpr-gate + IaC/no-SSH/user-brand checks passed (lightweight).
- [ ] All AGENTS hard rules respected (no-SSH, pull-your-own-data, etc.).
- [ ] Draft PR updates #6027/#6230; plan + tasks committed.

## Test Scenarios

- Given doppler token + prd config, when wrapper runs, then pure gate receives injected env, exits with correct sub_condition or success banner, and no Doppler call inside pure gate.
- Given transient readyz failure, when runtime gate runs, then N-consec logic fails closed (does not green on single success).
- Given web-2 recreate dispatch, then evidence marker is present in journald / GHA and discoverable via no-SSH query.
- Given shape gate success + runtime gate failure, orchestrator (future) must not shift weight (contract preserved).
- `doppler run ... lb-weight-gate-doppler.sh` + GHA step summary shows structured output.
- `scripts/betterstack-query.sh` (doppler prd_terraform) surfaces the quiesce / gate markers.

## Risks & Mitigations (from research + leaders)

- LB resources / weight API not present yet → scope excludes any weight flip (probes only).
- LUKS soak marker absent → this slice is pre-soak verification; full orchestrator stays deferred.
- Host targeting gap (shared with DI-C3 / #6230) → document; do not claim per-host for Inngest or weight decisions.
- New logger tags must be allowlisted in same change (Vector) → explicit task + test.
- Concurrent merge can revert gate comments/ADR text → post-merge verification step + lint carve-outs.
- Preflight unboundedness lessons (July 2026) → any new scan in future orchestrator must bound + abandon-safe.
- Single-user incident → CPO sign-off + user-impact-reviewer at review.

## Sharp Edges (must be in implementer context)

- Pure gate must remain injected-env only; Doppler never inside it.
- Runtime gate must be on-host + N≥2; readyz alone is insufficient for attach.
- #6230 manual step is permanent; evidence seam makes it auditable, does not automate it away.
- Shape exit 0 is never sufficient for weight or pool decisions.
- All verification no-SSH / pull-your-own-data.
- Follow existing doppler sourcing + logger + atomic state patterns exactly (see research).

## Observability

(See Phase 4 block above — implement the 5 fields + allowlist + discoverability test.)

## Files to Create
- `apps/web-platform/infra/runtime-bind-gate.sh` (thin; or extend existing delivered host script — see Phase 1)
- `knowledge-base/project/plans/2026-07-11-feat-lb-weight-gate-doppler-and-on-host-runtime-gate-plan.md` (this file)
- `knowledge-base/project/specs/feat-feat-6230-next-open-feature-epic/tasks.md` (post-review)

## Files to Edit (minimal)
- `apps/web-platform/infra/lb-weight-gate.sh` (comments only — document the 6 env vars)
- Relevant tests + parity for runtime gate
- (If delivery chosen) `apps/web-platform/infra/infra-config-apply.sh` or FILE_MAP
- Minimal comment refreshes in runbooks / cutover-inngest.yml (fact only)
- `apps/web-platform/infra/vector.toml` (only if new logger tag introduced by runtime gate)
- `knowledge-base/engineering/operations/runbooks/*.md` (fact refresh only)

## References
- Spec + Brainstorm (this session)
- ADR-068, ADR-105, ADR-106
- 2026-07-04 autonomous multi-host gate plan (Phase 5 deferral)
- lb-weight-gate.sh + test, readiness.ts, server.tf, apply + cutover workflows, runbooks
- July 2026 cutover learnings (preflight, DI-C3, observability, no-ssh)

**Resume prompt (MANDATORY):**
All artifacts on disk. Run `/clear` then:
`/soleur:work knowledge-base/project/plans/2026-07-11-feat-lb-weight-gate-doppler-and-on-host-runtime-gate-plan.md`

Context: worktree .worktrees/feat-feat-6230-next-open-feature-epic, branch feat-feat-6230-next-open-feature-epic, PR #6327, refs #6027/#6230. Plan reviewed + tasks next.

## Post-Generation
After review, generate tasks.md and commit plan + tasks together.

(End of plan body. Domain Review, Observability, and User-Brand sections intentionally placed per template + gates.)
