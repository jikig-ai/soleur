# Tasks — feat(infra): deep-readiness endpoint `/internal/readyz` (#5966)

lane: single-domain
Plan: `knowledge-base/project/plans/2026-07-03-feat-deep-readiness-endpoint-workspaces-mount-plan.md`
Brand-survival threshold: single-user incident (fail-closed is load-bearing)
Deepened: 2026-07-03 (8-agent panel — st_dev check replaced by write-probe; see plan Review Synthesis)

## Phase 1 — Readiness builder (`server/readiness.ts`, new)

- [ ] 1.1 Create `apps/web-platform/server/readiness.ts` with `ReadinessResponse { ready, checks:{workspaces_writable, workspaces_populated} }` + `buildReadinessResponse()`.
- [ ] 1.2 `isWorkspacesWritable(root)` = `writeFileSync(join(root, ".readyz-probe-<rand>"), "")` in try/catch/finally(unlink); any error → `false` (fail-closed). Do NOT use an st_dev mountpoint check (inert inside the container bind mount).
- [ ] 1.3 Resolve `WORKSPACES_ROOT` ONCE (`process.env.WORKSPACES_ROOT || "/workspaces"`) and pass it into both signals.
- [ ] 1.4 `workspaces_populated = countWorkspaceDirsAt(root) > 0` (new root-parameterized export — see 1.6).
- [ ] 1.5 `ready = workspaces_writable && workspaces_populated`. (No `git_data_consistent` — cut.)
- [ ] 1.6 `session-metrics.ts`: extract `countWorkspaceDirsAt(root: string)` (adds `lost+found` to the `.orphaned-`/`.cron` exclusions, keeps `isDirectory()` + ENOENT→0); re-express `getActiveWorkspaceCount()` as `countWorkspaceDirsAt(WORKSPACES_ROOT)` (no behavior change for existing callers).

## Phase 2 — Route wiring (`server/index.ts`)

- [ ] 2.1 Add `/internal/readyz` route after `/internal/metrics`.
- [ ] 2.2 Gate on `req.socket.remoteAddress` loopback (`127.0.0.1`/`::1`/`::ffff:127.0.0.1`) AND `isLoopbackHost` secondary → 403 otherwise.
- [ ] 2.3 Wrap `buildReadinessResponse()` in try/catch → 503 `{ready:false, checks:{}}` on any throw (never propagate → crash handlers).
- [ ] 2.4 `res.writeHead(readiness.ready ? 200 : 503)`. Leave `/health` and `/internal/metrics` untouched.

## Phase 3 — Boot-time readiness mirror

- [ ] 3.1 Add latched `verifyWorkspacesMountOnce()` to `readiness.ts`: call `buildReadinessResponse()` once; when not-ready → `reportSilentFallback(null, {feature:"workspaces-mount", op:"boot-readiness", message, extra:{checks, workspacesRoot}})`.
- [ ] 3.2 Call it in `index.ts` `app.prepare()` next to `verifyPluginMountOnce()`.

## Phase 4 — Tests (`test/server/readiness.test.ts`, new)

- [ ] 4.1 Mock `fs` (`writeFileSync`/`unlinkSync`) + `./session-metrics` (`countWorkspaceDirsAt`) before SUT import (health.test.ts pattern).
- [ ] 4.2 Case: writable + count 5 → `ready:true`.
- [ ] 4.3 Case: writable + count 0 (bare-host sim) → `ready:false`, `workspaces_populated:false`. (AC-required)
- [ ] 4.4 Case: `writeFileSync` throws EROFS/ENOENT → `ready:false`, `workspaces_writable:false`.
- [ ] 4.5 Case: any internal throw → route returns 503 (fail-closed, no crash).
- [ ] 4.6 Case: `WORKSPACES_ROOT`=real temp dir (NOT mocking `countWorkspaceDirsAt`) → both signals honor that root.
- [ ] 4.7 Case: root with only `lost+found` → `workspaces_populated:false`.
- [ ] 4.8 Case: non-loopback `socket.remoteAddress` → 403.
- [ ] 4.9 Case: `verifyWorkspacesMountOnce` fires one `reportSilentFallback` on not-ready boot, zero on ready.
- [ ] 4.10 Run `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/readiness.test.ts test/server/health.test.ts test/server/session-metrics.test.ts` (all green).
- [ ] 4.11 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` clean.

## Phase 5 — ADR + C4

- [ ] 5.1 Add ADR-068 amendment: readiness contract, writability+populated semantics, container-topology rationale (why not st_dev), RWO single-attach identity backstop, boot mirror, N≥2-consecutive flap-safety.
- [ ] 5.2 Confirm "no C4 impact" enumeration against `model.c4`/`views.c4`/`spec.c4` (no `.c4` edit).

## Phase 6 — Docs / runbook reference

- [ ] 6.1 Update blue-green plan Sharp Edge C1 (`2026-07-03-feat-multi-host-blue-green-ingress-prereqs-plan.md`) → "delivered — `/internal/readyz`".
- [ ] 6.2 `gh issue comment 5946` referencing `/internal/readyz` + the N≥2-consecutive drain precondition (post-merge / ship).
- [ ] 6.3 PR body `Closes #5966` + `Ref #5946`.
