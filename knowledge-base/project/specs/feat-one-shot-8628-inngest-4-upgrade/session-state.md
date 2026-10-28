# Session State

## Plan Phase
- Plan file: /data/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-8628-inngest-4-upgrade/knowledge-base/project/plans/2026-10-28-chore-inngest-v4-upgrade-stream-detach-plan.md
- Status: complete

### Errors
- Bare git calls denied by main-branch guard; resolved with `git -C <abs-path>` (commits fa1c5128ef, a492b57d5a).
- No nested agent-spawn tool in the subagent harness; prescribed fan-outs ran as inline passes (disclosed in plan's Enhancement Summary; NOT claimed as independent review).
- webfetch denied in background mode; v4 facts verified via web_search + direct npm tarball inspection.
- Premise corrections: no bun.lock in this repo (package-lock.json only, npm@11); stream-detach test at apps/web-platform/test/server/inngest/stream-detach.test.ts; self-hosted server pinned at v1.45.1 not v1.19.4.

### Decisions
- 7-phase plan: dep pin → mechanical codemod (71 files) → middleware rewrite to Middleware.BaseMiddleware → wrapper/test/route deletion → S1–S8+S9 spike re-run → residuals (followthrough retirement + 4 fd-pinning P3s) → ADR-243 amendment.
- Brand-survival threshold: single-user incident with requires_cpo_signoff (serve handler shared with founder BYOK leader loop).
- Checkpointing promoted to R1 — v4 enables it by default; evidence-gated by new spike row S9 with documented `checkpointing: false` fallback.
- S7 wrapper-less stream cut is the deletion kill-proof.
- onRunError.isFinalAttempt (4.26.1) replaces run-log's manual attempt gate — recorded as option.
- ADR-243 amendment in-plan; C4 impact none.

### Components Invoked
- soleur:plan (full), soleur:deepen-plan (fan-outs inlined); cloud-detect.sh, collision-precheck.sh; commits fa1c5128ef + a492b57d5a.

## Technical-Ruling Gate (pre-work)
- cto_spawns=1 (one batched spawn, 6 items — max 2 for the pipeline)
- Outcome: Item A OVERTURNED planner default → ship `checkpointing: false`, S9 measurement-only. Items B–F confirmed/refined (no telemetry replacement; exported-for-test seam; single error-prefix family + op token; `streaming: true`; `^4.<latest>`; no bun.lock).
- Row 18 recategorized: `operator (challengeable)` → `operator (brand)` (closed category list).

## Pipeline Progress (one-shot #8628)
- Draft PR: #11381 (branch feat-one-shot-8628-inngest-4-upgrade, worktree .worktrees/feat-one-shot-8628-inngest-4-upgrade)
- Done: collision checks, worktree+draft-PR, plan+deepen (subagent), scope verify, CTO ruling batch (spawn 1), plan/tasks amended for checkpointing:false, ruling gate PASS.
- Next: soleur:work <plan file> → review → resolve → qa → compound → ship → postmerge.
- Session bookkeeping: #8316 + #9705 closed with evidence comments; #10290 stays deferred (no probe_schema bump); #11372 owned by sibling session (PR #11374 live); apply-web-platform-infra has unrelated red runs (422 alert resource — being fixed by that session; a gated host-update and a dark web-2 boot are operator-side).

## Work Phase

- **Phase 0–3 (dep, codemod, middleware, route/client, stream-detach deletion):** DONE, one atomic commit `HEAD~1` — inngest `^4.26.0` (4.26.1 inside min-release-age=3 floor until 2026-10-30 — new ruling appended to decision-challenges.md); 73/73 createFunction sites migrated via TS-AST codemod; 3 middlewares → `Middleware.BaseMiddleware`; `streaming: true`, `serveOrigin`, `signingKey`→client, `checkpointing: false` (binding ruling); `send()` `v:` kept via widened payload where consumers read `event.v` (new ruling appended); stream-detach.ts + test + route wrapper deleted.
- **Gates:** `./node_modules/.bin/tsc --noEmit` green; vitest green on the 8 touched suites (run-log-middleware, bound-logger-middleware, sentry-correlation-middleware, signature-verify, signature-verify-dev-mode, client-startup, cron-email-ingress-probe, cron-community-publication — 186+113 pass). `test-all.sh --affected` NOT run here (long suite; left for the review/ship gate rather than fabricate).
- **Phase 5a:** probe retired — script+test+run_suite+2 TSV rows+baseline row deleted; `git grep inngest-verify-clean-10390` → 0 in code paths.
- **Phase 5b:** all four P3 items — ContainedFdSeam optional override (beforeOpen-precedent), procfs-absent loud-ENOENT probe, fh.close() track-and-rethrow, `writeDigestFileContained: op=<token>` family; 7 new tests green.
- **Phase 4 spike:** NOT RUN — binaries fetched (inngest 1.45.1-9059f14a7, cloudflared) but the build+tunnel harness could not complete in-session; `streaming-spike-v4.md` records every S-row as not executed. S7 kill-proof still owed — do NOT merge treating it as evidence.
- **Phase 6:** ADR-243 amended in place; 2 new decision-challenges rulings appended.
- **Files:** ~98 changed (71 function codemods, middleware×3, client, route, 3 webhook routes, 6 inngest test files, 5 registry/baseline files, ADR-243, spec artifacts).
- **Commits:** `2f6baea` migration unit · `HEAD` residuals — see git log.

## Spike + Gates Phase

- **Harness stood up (2026-10-28):** `next build` from this branch (placeholders for `NEXT_PUBLIC_SUPABASE_*`); minimal `http.createServer → next().getRequestHandler()` server with the production two-handler crash semantics + supervisor restart loop; `inngest start` v1.45.1 (`--sqlite-dir`, bare-hex signing/event keys); cloudflared quick tunnel → TCP cut-proxy (:3100, SIGUSR1 destroys all live sockets) → app (:3000). Fixture serve mounts `/api/spike-inngest` (`spike-v4` client, `checkpointing: false` = shipped config) + `/api/spike-inngest-ck` (`spike-v4-ck`, v4 default on); everything else incl. the real `/api/inngest` route (74 `soleur-runtime` fns) served by the actual build. `env -i`, `INNGEST_DEV=0`, `NODE_ENV` unset (so the `serveOrigin` prod pin doesn't fire — tunnel URL registers, same as 2026-09-23). Harness under `/tmp/spike-v4/`, logs beside it.
- **S-rows (all executed, per-row detail in streaming-spike-v4.md):**
  - S1 3/3 · S2 3/3 (3-min streamed >100 s, zero 524) · S3 run-2 COMPLETED full 70 min in one attempt (run-1 deliberately cut twice → retries exhausted, recorded) · S4 3/3 (attempt-1 retry succeeded) · S5 3/3 (NonRetriableError, no retry) · S6 3/3 (step-a + step-b once) · S8 3/3 (cap-check+claude once, tool-0 re-ran) · throttle 2 ran / 2 queued→released.
  - **S7 kill-proof: PASS** — one cut destroyed 3 live streams (s7c, s7e, s3) at once; app stayed up; **zero** `Invalid state`/`Controller is already closed` occurrences in the whole log; server logged `error parsing SDK response stream` per run; retries re-invoked (+17 s/+29 s/+34 s). s7e completed on retry; s7a/s7b SIGKILL rows completed after restart; s7d 5 aborts → app up. s7c's run FAILED on retry-exhaustion after a *second* deliberate drop (the s7a/b kill) — mechanism verified, recorded honestly.
  - S9 measurement: shipped `checkpointing: false` arm passes (S2); **default-on arm also COMPLETED** a 3-min step in one attempt on v1.45.1 — the "expected degrade" hypothesis not observed for this shape; checkpoint-transport negotiation not visible in server logs at info level.
  - Unsigned POST: 201 + `x-inngest-sdk: inngest-js:v4.26.0` + streamed `{"status":401}` envelope, no function ran. Registration PUT on the real route: `modified:true`, `soleur-runtime` 74 fns / **55 cron triggers planned**; armed crons then fired against the tunnel every ~5 min (expected env-missing failures on the throwaway server).
- **Gates:** `tsc --noEmit` green (work phase + after spike fixes); eslint on the 104-file diff → **0 errors, 4 pre-existing warnings** (tokens absent from diff lines); `scripts/lint-dual-lockfile.sh` → OK; `scripts/test-all.sh --affected` → **UNRESOLVED (exit 3), crossed TC_RUNTIME_CEILING_S at 14670s/14400s** — `691 suites: 365 passed, 7 failed, 0 killed, 2 skipped, 317 declined (runtime ceiling — coverage not obtained), 46 REPORT observations`. The run is not green and not a failure; the 317-suite coverage gap stands for CI/the ship gate.
  - **4 diff-caused failures found and FIXED** (verified green on re-run): `execution-placement.test.ts` Guard 4 (`serveHost`→`serveOrigin` in the guard + fixture), `function-registry-count.test.ts` (same rename), `resend-inbound-route.test.ts` (top-level `v:` dropped — v4 SendEventPayload omits it), `inngest-step-harness.test.ts` (v4 StepError preserves the thrown error's `name`; harness doc updated).
  - **Environmental/pre-existing failures documented:** `roster-entry-gate.test.ts` + `ccla-add.test.sh` (CLA-ledger epochs derived from git history — worktree is a **207-commit shallow clone**, `git log` returns no history); `plugins/soleur` redirect-tombstone census (`git log --diff-filter=RD` → 0 events under shallow clone); `scripts/orphan-process-reaper` + `-mutations` (host-state suite — live walk found foreign processes on the shared box; fails standalone too, unrelated to diff files); `c4-render-argv-fixture` timeout + `today-card.click` — load flakes, green on quiet re-run.
- **Artifacts:** `streaming-spike-v4.md` rewritten from NOT-RUN to per-row verdicts; harness scripts/logs in `/tmp/spike-v4/` (server.mjs, proxy.mjs, fns.mjs, send.mjs, app/inngest/cloudflared/proxy logs).
- **Deviations:** fixture fns on spike-only mounts (same `inngest@4.26.0` under test; real route exercised by unsigned-POST + PUT rows); S3 ran twice not thrice; crash handlers are the JS-equivalent two handlers (no Sentry DSN under env -i); `next.config.mjs` precompiled via the Dockerfile's esbuild line (deleted after the run — untracked artifact).
- **SHAs:** `2e722ca97b` (this phase: spike record + session-state + 4 test fixes) on top of `5923033cf1`/`d93c56f768`/`4e5fd912d8` (work phase).
