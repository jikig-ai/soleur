# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-09-30-fix-concierge-stop-gate-sentinel-leak-plan.md
- Status: complete
- Plan artifact: complete (selector=branch)

### Errors
None blocking. Follow-up issue filed as #9281 after hooks refused the first body form.

### Decisions
- Root cause: plugin Stop hook `unkept-promise-hook.sh` (operator-CLI guard) loads in the web runtime via the local plugin; it forces the model to emit `<stop>OPERATOR-GATE…</stop>`, which replaces the question list (text is replaced per block).
- Fix: env opt-out `SOLEUR_DISABLE_UNKEPT_PROMISE_HOOK` (Phase 1), `stripStopGateMarkup` in `soleur-go-runner.ts` (Phase 2), cc turn end on client `stream_end` (Phase 3, gated by a failing wire-sequence test), Stop-hook parity guard (Phase 4).
- Rejected: widening hook regexes, rewording CRM_LEAD_DIRECTIVE, `session_ended` per cc turn, accumulating text, SDK `disableAllHooks`.

### Components Invoked
soleur:plan, soleur:plan-review, soleur:deepen-plan; repo-research-analyst, learnings-researcher, dhh/kieran/code-simplicity reviewers, cto.
