# Tasks — feat-one-shot-7696-7665-log-noise

Plan: `knowledge-base/project/plans/2026-10-07-chore-log-noise-cutdown-7696-7665-plan.md`

- [ ] T1: flip FSM — add `CUTOVER_NOOP_THROTTLE_S` seam to gate list + `NOOP_THROTTLE_S`/`NOOP_EMIT_STAMP` and noop-throttle inside `emit_state` (`apps/web-platform/infra/inngest-cutover-flip.sh`)
- [ ] T2: flip suite — new throttle cases + header comment + `MIN_ASSERTIONS` floor bump (`apps/web-platform/infra/inngest-cutover-flip.test.sh`)
- [ ] T3: resolve-origin — per-origin once-per-process dedupe with bounded FIFO cap (`apps/web-platform/lib/auth/resolve-origin.ts`)
- [ ] T4: new vitest file `apps/web-platform/lib/auth/resolve-origin.test.ts` covering dedupe/suppression/cap/return-value
- [ ] T5: comment-only refresh of the `FLIP_LIVENESS_SINCE` WINDOW cadence citation (`scripts/cutover-inngest.sh`)
- [ ] T6: run `bash apps/web-platform/infra/inngest-cutover-flip.test.sh` + `npx vitest run lib/auth/`; green
- [ ] T7: PR body carries `Closes #7696` / `Closes #7665` on their own lines; ship → merge
