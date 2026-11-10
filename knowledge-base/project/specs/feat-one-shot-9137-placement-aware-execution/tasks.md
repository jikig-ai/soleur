# Tasks — feat-one-shot-9137-placement-aware-execution

Plan: `knowledge-base/project/plans/2026-11-10-feat-inngest-placement-aware-execution-plan.md`
Issue: #9137 (closes). Branch: `feat-one-shot-9137-placement-aware-execution`.

## Phase 0 — Decision module (no behavior change)

- [x] 0.1 Create `apps/web-platform/server/inngest/exec-placement.ts`: `EXEC_HOST_PRIVATE_IP`
      constant (`10.0.1.10`), `EXEC_FORWARD_HEADER`, `classifyFnId` (strip `soleur-runtime-`
      prefix + `-failure` suffix → manifest lookup; unknown → pinned-class fail-closed),
      `decidePlacement` (the plan's decision table — pure function over env + request facts),
      structured `placement_decision` log seam.
- [x] 0.2 `SOLEUR_HOST_PRIVATE_IP` reader + `isExecHost(): true|false|unknown`
      (in `server/host-identity.ts` or a `host-private-ip.ts` sibling); `unknown` → refuse path.
- [x] 0.3 Unit tests: every decision-table row + mutation-matrix fixtures (synthesized only).

## Phase 1 — Forwarder + receiver + env injection

- [x] 1.1 `server/inngest/exec-forward-client.ts`: pinned-TLS dial reusing
      `loadProxyTlsClientCa()` + the session-relay dial shape (`ca`, `rejectUnauthorized: true`
      — never false; reuse the relay's identity check, never a new one); verbatim
      method/path/query/header/body forward; streamed response pass-through; bounded timeouts;
      `placement.forward_failed` error → fail-closed (never local fallback).
- [x] 1.2 `app/api/inngest/route.ts`: wrap `handlers.POST` in the forwarder (GET/PUT/`?probe=`
      bypass; http-only exports per `cq-nextjs-route-files-http-only-exports`); module load
      must not throw without env (`IS_BUILD_PHASE` / inert-when-absent pattern).
- [x] 1.3 Receiver (implementer picks, per CTO T3): (i) `request` handler for `/api/inngest`
      on the existing :8443 https server in `session-proxy.ts` — marked calls forwarded
      internally to the app serve path; OR (ii) sibling `https.createServer` on a dedicated
      port, same material + private bind. Wire in `server/index.ts`.
- [x] 1.4 `infra/ci-deploy.sh`: `-e SOLEUR_HOST_PRIVATE_IP="$PROXY_BIND"` on the prod
      `docker run` (~L5798); `-e SOLEUR_HOST_PRIVATE_IP=` on the canary (~L5413).
- [x] 1.5 `infra/lib/docker-run-tuple.py` + `infra/docker-run-tuple.test.sh` +
      `infra/ci-deploy.test.sh`: pin the new env lines.

## Phase 2 — Guards + tests (Guard Contract Guards 1–4)

- [x] 2.1 `test/server/inngest/exec-placement-forward.test.ts`: Guards 1–4 with full
      mutation matrices (own-dispatch + must-PASS rows per contract), all fixtures synthesized.
- [x] 2.2 Extend `test/server/inngest/execution-placement.test.ts` Guard 1: served set resolves
      through the classifier including `-failure` ids.
- [x] 2.3 `apps/web-platform/scripts/exec-placement-probe.sh`: committed discoverability probe
      printing `exec-placement: ok` in <15 s.

## Phase 3 — ADR/C4 + runbook + observability wiring

- [x] 3.1 ADR-033 amendment `## Amendment — 2026-11-10 (#9137)`; ADR-248 reversal-trigger-1
      fired note; ADR-243 §2 addendum; ADR-143 addendum line; ADR-030 update-log line.
- [x] 3.2 `model.c4` `inngest -> api` edge prose update (no numeric counts); run
      `c4-code-syntax.test.ts`, `c4-render.test.ts`, `c4-count-parity.test.sh`.
- [x] 3.3 `knowledge-base/engineering/operations/runbooks/inngest-server.md`:
      `placement.exec_identity_missing` recovery (redeploy, no SSH) + `forward_failed`
      diagnosis (8445 publish state, cert expiry).
- [x] 3.4 `reportSilentFallback` wiring: refuse + forward-failure paths report to Sentry.

## Phase 4 — Optional unpin (gated)

- [x] 4.1 Move `resolveCurrentWorkspaceId` to a filesystem-free module; re-class
      `cfo-on-payment-failed` + `github-on-event` to `portable` in `execution-placement.ts`;
      Guard 2 verifies. Defer to a scope-out if consumers block the move (record, don't skip).

## Phase 5 — Verification (AC mapping)

- [ ] 5.1 `next build` + vitest suite + infra shell-test suite green (AC13).
- [ ] 5.2 Decision-table + TLS + marker + concurrency scenarios pass (AC1–AC7).
- [ ] 5.3 Post-merge live check (AC12): Better Stack rows show `decision=forward` on web-2 /
      `decision=execute` on web-1 for a pinned fn; `execute` on both for a portable fn —
      follow-through script if the verdict needs a soak.
