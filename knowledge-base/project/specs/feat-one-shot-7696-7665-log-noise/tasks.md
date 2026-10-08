# Tasks — feat-one-shot-7696-7665-log-noise

Plan: `knowledge-base/project/plans/2026-10-07-chore-log-noise-cutdown-7696-7665-plan.md`

- [x] T1: flip FSM — add `CUTOVER_NOOP_THROTTLE_S` seam to gate list + `NOOP_THROTTLE_S`/`NOOP_EMIT_STAMP` and noop-throttle inside `emit_state` (`apps/web-platform/infra/inngest-cutover-flip.sh`)
- [x] T2: flip suite — new throttle cases + header comment + `MIN_ASSERTIONS` floor bump (`apps/web-platform/infra/inngest-cutover-flip.test.sh`)
- [x] T3: resolve-origin — per-origin once-per-process dedupe with bounded FIFO cap (`apps/web-platform/lib/auth/resolve-origin.ts`)
- [x] T4: new vitest file `apps/web-platform/lib/auth/resolve-origin.test.ts` covering dedupe/suppression/cap/return-value
- [x] T5: comment-only refresh of the `FLIP_LIVENESS_SINCE` WINDOW cadence citation (`scripts/cutover-inngest.sh`)
- [x] T6: run `bash apps/web-platform/infra/inngest-cutover-flip.test.sh` + `npx vitest run lib/auth/`; green
- [x] T7: PR body carries `Closes #7696` / `Closes #7665` on their own lines; ship → merge
- [x] T8 (unplanned, gate-forced): Rule-E drawdown — T5's edit to `scripts/cutover-inngest.sh` made the file subject to `lint-shell-trace-credential-refusal --changed` (baselines bypassed for changed files). Converted all 20 `curl -H` credential-header sites to the new `_sig_curl` wrapper (HMAC + CF-Access trio on `--config -` stdin), removed the file's Rule-E baseline row + census-ceiling row, spliced `_bearer_ok`/`_sig_curl` into the four render drivers in `cutover-inngest-workflow.test.sh`, rewrote the confinement/outer-budget rows for the wrapper shape, floor 1040→1041.
