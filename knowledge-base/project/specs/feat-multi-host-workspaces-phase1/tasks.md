---
feature: multi-host-workspaces-phase1
lane: cross-domain
brand_survival_threshold: single-user incident
plan: knowledge-base/project/plans/2026-06-30-feat-multi-host-workspaces-phase-1-host-local-correctness-plan.md
epic: knowledge-base/project/plans/2026-06-29-feat-multi-host-workspaces-layer-plan.md
issue: 5274
status: draft
---

# Tasks: Multi-host `/workspaces` — Phase 1 (host-local correctness, no new infra)

> Epic step 1 of 6. Architecture settled in ADR-068 (merged PR #5710). No new ADR,
> no migration, no Terraform, no Redis, no coordinator, **no `host_id`**. RED→GREEN
> per `cq-write-failing-tests-before`. PR body: **`Ref #5274`** (epic stays open).
>
> **Review-corrected (2026-06-30, 4-agent panel):** the grace guard CLOSES A REAL
> replicas=1 RACE (`sessions.set` :2843 precedes the timer-cancel :2893 by 3 awaited
> DB calls) — it is not belt-and-suspenders. The dev-Supabase live-DB integration
> test is **deferred to Phase 2** (operator decision); #5338 already covers the logic.

## 1.A — `abortSession` found-count (contract change first)
- [x] 1.A.1 Widen `abortSession` (agent-session-registry.ts:190-213) `: void → : number`;
  `leaderId` branch `return session ? 1 : 0`; broadcast accumulates `aborted += 1`
  (semantic mirror of `drainAutonomousDisclosureGates` cc-dispatcher.ts:1344-1364).
- [x] 1.A.2 Docblock (:178-189): "returns count of **registered** sessions matched on
  this host (not necessarily live); Phase-3 coordinator-forward affordance per ADR-068 §4."
- [x] 1.A.3 Touch no call site (6 production sites are statement calls; test spies read
  call-args, not return — confirm with the AC6 sweep).

## 1.B — TR2 host-local owning-host guard
- [x] 1.B.1 Add the user-level local-liveness guard at the top of `runDisconnectGraceAbort`
  (ws-handler.ts:228): `const live = sessions.get(uid); if (live && live.ws.readyState
  === WebSocket.OPEN) { log…; return; }`. Reuses the `forceDisconnectForTierChange`
  predicate (:334-342); no new import. Comment states it closes the :2843↔:2893 race.

## 1.C — Legacy abort audit (confirmation)
- [x] 1.C.1 Grep anchored on `registerSession(` (not line `:944`) confirming the
  agent-runner AbortController rides in `activeSessions` and is reachable by the
  `abortSession` broadcast; record in PR.
- [x] 1.C.2 Present-tense one-line comment at the agent-runner registration noting the
  cc lineage has its own controller (cc-dispatcher.ts:2117). No Phase-3 forward-refs.
- [x] 1.C.3 Present-tense host-local note on the `sessions` Map (session-registry.ts:1-5).

## 1.D — RED→GREEN tests
- [x] 1.D.1 New `test/ws-handler-disconnect-grace-owning-host-guard.test.ts` (node;
  `afterEach` deletes the seeded `sessions` entry): (a) live OPEN session = race-window →
  abort suppressed (AC2); (b) no session → abort fires (AC3); (c) CLOSED socket → abort
  fires (AC3, pins the `readyState===OPEN` check).
- [x] 1.D.2 Extend `test/server/abort-turn.test.ts`: found-count 2/0/1 per branch (AC4);
  a `registerSession`+real-`AbortController` session is aborted & counted (AC5, folds the
  legacy-abort deliverable); a different-`(uid,conv)` decoy is neither counted nor
  aborted (AC4 exclusion).
- [x] 1.D.3 Task 1.2 confirmation (no new test): cite `durable-workspace-binding-resolver.test.ts:43`
  + :118-137 and grep-trace the post-restart consumer through `resolveUserWorkspaceBinding`.

## Gates
- [x] `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` clean (AC1).
- [x] AC6 type-widening sweep `git grep -n "abortSession(" --include=*.ts apps/web-platform`
  recorded in PR; confirm no site reads the return (incl. spies + the :201 re-export).
- [ ] `./node_modules/.bin/vitest run` the new + extended suites green.
- [x] No `.c4` edit → do NOT run `regenerate-c4-model.sh` (nothing changed).
- [ ] `user-impact-reviewer` at PR review (single-user-incident threshold).
- [ ] PR body uses `Ref #5274` (not `Closes`).

## Deferred to Phase 2 (recorded here so it is not lost)
- [ ] Live-DB dev-Supabase restart-survival integration test (real tenant-scoped
  `readWorkspaceIdFromDb`, spy-assert closure-called-once, Map-empty-at-call) — lands
  with migration 114, the first new DB surface + the repo's first `*.integration.test`.
  No setup workspace-create (mig-053 trigger auto-creates); `anonymise_user` teardown.
