---
title: "Tasks — lb-weight-gate-doppler.sh + on-host runtime gate (next slice of #6027)"
date: 2026-07-11
lane: cross-domain
brand_survival_threshold: single-user incident
plan: knowledge-base/project/plans/2026-07-11-feat-lb-weight-gate-doppler-and-on-host-runtime-gate-plan.md
---

# Tasks — on-host runtime gate (thin probes slice of #6027 / #6230 context)

**Note (DHH mechanical review applied):** Dedicated Doppler shim removed (use direct `doppler run`). Heavy #6230 evidence seam deferred. Phases collapsed. Focus: thin runtime gate + concrete delivery.

**Plan:** `knowledge-base/project/plans/2026-07-11-feat-lb-weight-gate-doppler-and-on-host-runtime-gate-plan.md`

**Spec:** `knowledge-base/project/specs/feat-feat-6230-next-open-feature-epic/spec.md`

**Branch:** feat-feat-6230-next-open-feature-epic (PR #6327)

## Phase 0 — Setup & Contract Verification
- [ ] Verify pure gate + test + server.tf HARD GATE + readiness + workflows.
- [ ] Confirm shape-only contract (`requires_runtime_bind_probe=true` + banner) and that pure gate reads *only* injected env.
- [ ] Confirm LUKS soak marker absent (full orchestrator deferred).
- [ ] Read ADR-068 + key July 2026 learnings (DI-C3, no-SSH, preflight bounding).
- [ ] Baseline tests green.

## Phase 1 — Direct Doppler + document separation (no new scripts)
- [ ] Document direct `doppler run -p soleur -c prd -- ./lb-weight-gate.sh` + the 6 vars in comments in `lb-weight-gate.sh`.
- [ ] Extend `lb-weight-gate.test.sh` with doppler-stub cases.
- [ ] Minimal fact-refresh comments in runbooks / cutover-inngest.yml (web-2 recreate artifacts only).
- [ ] If any new logger tag: add to vector.toml + test.
- [ ] Short observability description.

**Note:** Per DHH + YAGNI mechanical reviews: no dedicated doppler shim, no new runtime-bind-gate.sh, no disk attach check, no heavy evidence seam, no gdpr in scope for this thin slice. Use existing readiness.ts for runtime separation.

## Acceptance Criteria (updated per reviews)
- [ ] Direct `doppler run -p soleur -c prd -- ./lb-weight-gate.sh` documented and exercisable (no new shim).
- [ ] Existing readiness + pure gate marker satisfy documented shape vs runtime separation (no new script; disk attach removed).
- [ ] Test extension for doppler stub passes; contract preserved.
- [ ] Minimal fact-refresh comments only.
- [ ] Observability description present.
- [ ] Draft PR updates #6027/#6230; plan + tasks committed.

## Notes for /work
- Thin runtime gate + reuse existing readyz logic.
- Direct doppler run (no new shim).
- Heavy #6230 evidence work deferred.
- All verification no-SSH + pull-your-own-data.
- DHH mechanical review incorporated.

**Resume after /clear:**
`/soleur:work knowledge-base/project/plans/2026-07-11-feat-lb-weight-gate-doppler-and-on-host-runtime-gate-plan.md`
