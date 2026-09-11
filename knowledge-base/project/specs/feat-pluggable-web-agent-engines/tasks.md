---
title: "Pluggable web agent engines work ledger"
date: 2026-09-11
branch: feat-pluggable-web-agent-engines
lane: cross-domain
status: in-progress
---

# Work ledger

Canonical scope: [implementation plan](../../plans/2026-09-11-feat-pluggable-web-agent-engines-plan.md).
Both Codex authentication modes and workspace routines are included. Each new
routine run binds the current default once; retries retain that binding.

## Preflight

- [x] Restore feature checkout after cleanup unexpectedly checked out main; confirm no authored changes lost.
- [x] Reconcile prior brief and plan with the four approved decisions.
- [x] UX specialist updates wireframe and produces implementation brief for both auth modes and routine scope.
- [x] Complete consumer/write-boundary inventory and identify extraction seams.

## Phase 0 — Neutral contract

- [x] RED-01a: registry eligibility, qualified capabilities, auth-mode binding, no alternate-engine selection, and retry binding tests for the registry surface (19 tests green).
- [x] GREEN-01a (blockedBy RED-01a): neutral engine contract and reviewed registry surface (`f5b92f5bd`/`25600a6ed`).
- [ ] RED-01b: persisted conversation/routine binding, dispatch authorization, and no alternate-engine invocation at the execution boundary.
- [ ] RED-02: event sequencing, terminal-state monotonicity, uncertain cancellation, and usage provenance tests.
- [ ] GREEN-02 (blockedBy RED-02): normalized lifecycle and deterministic remote adapter.

## Phase 1 — Persistence and Claude extraction

- [ ] RED-03: atomic workspace-default/conversation/routine binding, owner setting writes, immutable bindings, tenant/RLS and event idempotency tests.
- [ ] GREEN-03 (blockedBy RED-03): migration, durable run/event records, scoped RPCs and repositories.
- [ ] RED-04: current Claude behavior and denied platform tools through neutral adapter.
- [ ] GREEN-04 (blockedBy RED-04): extract Claude adapter and wire all inventoried dispatch paths.
- [ ] Write ADR and update/regenerate C4 for implemented boundaries.

## Phase 3 — Codex and settings

- [ ] RED-05: API-key and managed ChatGPT login isolation, refresh, logout, revoked credentials, approvals, recovery, usage, and cancellation.
- [ ] GREEN-05 (blockedBy RED-05): Codex transport, auth lifecycle, credential isolation, shared policy and normalized events.
- [ ] RED-06: settings default, both auth modes, routines, missing credentials, availability, and owner authorization.
- [ ] GREEN-06 (blockedBy RED-06): settings UI and server endpoints following the updated wireframe.

## Qualification and delivery

- [ ] RED-07: DSAR/export/delete, provider error sanitization, egress, replay/stale-event protection, and observability.
- [ ] GREEN-07 (blockedBy RED-07): implement protections and wire production paths.
- [ ] Refresh GDPR evidence, run prescribed GDPR gate, and obtain vendor/CLO disposition for both auth modes.
- [ ] Synthetic-only qualification, feature flag, bounded live probes, QA and screenshots; customer content remains disabled without evidence.
- [ ] Run appropriate suites/lint/typecheck/build after all GREEN tasks.
- [ ] Review, QA, compound, ship and required postmerge checks.

## Verification evidence

Evidence so far: the RED-01a import failure was observed before implementation;
the registry suite now passes 19/19. The repository full gate was attempted by
the pre-commit hook and completed 397/404 suites with two failures while sibling
gates were active; those failures are not yet isolated. Do not mark an entire
phase complete from an isolated helper suite.
