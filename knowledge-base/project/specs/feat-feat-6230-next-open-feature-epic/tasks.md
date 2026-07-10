---
title: "Tasks — lb-weight-gate-doppler.sh + on-host runtime gate (next slice of #6027)"
date: 2026-07-11
lane: cross-domain
brand_survival_threshold: single-user incident
plan: knowledge-base/project/plans/2026-07-11-feat-lb-weight-gate-doppler-and-on-host-runtime-gate-plan.md
---

# Tasks — lb-weight-gate-doppler.sh + on-host runtime gate

**Plan:** `knowledge-base/project/plans/2026-07-11-feat-lb-weight-gate-doppler-and-on-host-runtime-gate-plan.md`

**Spec:** `knowledge-base/project/specs/feat-feat-6230-next-open-feature-epic/spec.md`

**Branch:** feat-feat-6230-next-open-feature-epic (PR #6327)

## Phase 0 — Setup & Verification (no code change)
- [ ] Verify current state (pure gate, test, server.tf, readiness, workflows, runbooks) on origin/main vs worktree.
- [ ] `git grep -n "requires_runtime_bind_probe=true"` across infra, workflows, runbooks, ADR.
- [ ] Confirm LUKS soak marker absent in Doppler prd (re-confirm deferral).
- [ ] Read ADR-068 + July 2026 learnings + 2026-07-04 gate plan (Phase 5).
- [ ] Baseline: `bun test apps/web-platform/infra/lb-weight-gate.test.sh`
- [ ] Emit observability block skeleton.

## Phase 1 — Doppler sourcing wrapper
- [ ] Create `apps/web-platform/infra/lb-weight-gate-doppler.sh` (thin sourcing shim, guarded doppler gets, exact vars, exec pure gate, structured output, logger -t, GHA friendly).
- [ ] Add/update test (env -i, stub, assert sub_condition + rc + banner).
- [ ] Comment referencing pure gate contract.

## Phase 2 — On-host runtime gate
- [ ] Create `apps/web-platform/infra/runtime-bind-gate.sh` (or deliver via existing pattern): docker exec readyz (writable + populated), N≥2 consecutive, disk attach check, structured output, separate from shape.
- [ ] Tests: real FS, N-consec transients, attach failure.

## Phase 3 — Verifiable evidence seam for #6230
- [ ] Add machine-readable evidence marker / JSON / reason for web-2-recreate/quiesce (via existing dispatch).
- [ ] Update `inngest-server.md` step 1a + SEAM to assert evidence (no-SSH).
- [ ] Update cutover-inngest.yml comments + DI-C3 notes.
- [ ] Discoverability test (no SSH) for the marker.

## Phase 4 — Observability (5-field)
- [ ] Implement the 5-field block (liveness, error, failure_modes, logs, discoverability_test no-SSH).
- [ ] Allowlist any new `logger -t` tags in vector.toml + tests (same change).
- [ ] Verify discoverability_test.

## Phase 5 — Integration, tests, runbooks, comments
- [ ] Wire wrapper (standalone doppler run or verify job; later orchestrator).
- [ ] Fact-only refresh of server.tf HARD GATE comment if needed.
- [ ] Runbook + SEAM updates for evidence.
- [ ] Unit + dispatch + N-consec + attach tests green.
- [ ] Parity / destroy-guard / followthrough updates if touched.
- [ ] `<!-- lint-infra-ignore -->` carve-outs only for deferred orchestrator prose.

## Phase 6 — Cross-cutting gates & verification
- [ ] Run gdpr-gate (plan Phase 2.7); fold findings.
- [ ] IaC routing check (script on existing paths; no new manual provisioning or ssh).
- [ ] Confirm User-Brand Impact + single-user threshold + CPO sign-off note.
- [ ] All AGENTS hard rules (no-ssh, observability pull, bounded, etc.).
- [ ] Post-merge verification of invariants (gate comments, ADR text).

## Acceptance Criteria (from plan)
- [ ] Doppler wrapper exists, thin, sources exact vars, propagates output, invocable via doppler run.
- [ ] On-host runtime gate (N≥2 + attach) exists, callable, structured, distinct from shape.
- [ ] Tests green (unit + dispatch, no weight changes).
- [ ] Web-2 quiesce evidence machine-readable and asserted in runbook/SEAM (no SSH/eyeball).
- [ ] Observability 5-field + discoverability (no SSH) + tag allowlist.
- [ ] Shape-only contract preserved.
- [ ] gdpr-gate run + folded.
- [ ] No new operator checklists; all posture respected.
- [ ] Draft PR updates #6027/#6230; plan + tasks committed.

## Notes for /work
- Follow research patterns exactly for Doppler (guarded, scoped, no argv leakage, fallbacks).
- Preserve "SHAPE-ONLY — NOT weight-flip authorization" contract at every step.
- Web-2 (weight-0, self-arming, #6230 manual) is a precondition; do not assume verified.
- All verification no-SSH + pull-your-own-data.
- New logger tags = same-change Vector + test update.

**Resume after /clear:**
`/soleur:work knowledge-base/project/plans/2026-07-11-feat-lb-weight-gate-doppler-and-on-host-runtime-gate-plan.md`
