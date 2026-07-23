---
feature: feat-one-shot-readyz-loopback-peer-gate-container-403
lane: cross-domain
plan: knowledge-base/project/plans/2026-07-23-fix-readyz-loopback-peer-gate-container-403-plan.md
brand_survival_threshold: single-user incident
---

# Tasks — Fix /internal/readyz loopback peer-gate 403 (container-networking)

> Note: spec.md absent for this branch → `lane:` defaulted to `cross-domain` (TR2 fail-closed).
> Trust boundary in `readiness.ts` / `loopback.ts` is comment-only — do NOT change gate logic.

## Phase 1 — Centralize container-scoped transport (RED-first where testable)
- [ ] 1.1 Write/adjust the failing tests FIRST (see Phase 3) so GREEN proves the fix.
- [ ] 1.2 `workspaces-luks-emit.sh`: add `: "${WL_READYZ_CONTAINER:=soleur-web-platform}"` near the top (default-var idiom).
- [ ] 1.3 `workspaces-luks-emit.sh` `wl_probe_readyz` (line ~151): change the readyz curl to `docker exec "$WL_READYZ_CONTAINER" curl -sS -w "\n%{http_code}" --max-time 5 "$url"`, keeping the `|| printf '\n000'` fail-closed tail.
- [ ] 1.4 Update the `wl_probe_readyz` header comment to record the docker-exec transport + bridge-topology reason.
- [ ] 1.5 `luks-monitor.sh:43-45`: correct the stale "reachable from the host" comment to the measured reality (host curl → 403; docker exec → genuine loopback).
- [ ] 1.6 Precondition (verified, no new work): all three paths run as root, so `docker exec` host-access holds (cutover sudo; daily timer root; verify remote root ops). Keep the `docker exec … curl` wrapper unconditional (no URL-shape branch).

## Phase 2 — Gate rationale comments (no logic change)
- [ ] 2.1 `readiness.ts:92-100`: clarify "on-host consumers run on loopback" = inside the container (docker exec); add the "do NOT widen the peer gate to the bridge gateway (userland-proxy)" note at the gate.
- [ ] 2.2 `loopback.ts:8-19`: refine the comment to distinguish metrics (Host-only, host-curl-reachable) vs readyz (peer+Host, in-container-only). Function bodies unchanged.

## Phase 3 — Tests
- [ ] 3.1 `test/server/readiness.test.ts`: add `remoteAddress="172.17.0.1"` + Host `127.0.0.1:3000` → 403; add `::ffff:172.17.0.1` → 403. Keep existing loopback → 200/503 cases.
- [ ] 3.2 `workspaces-luks-harness.sh` (first harness, `run_case`): `docker()` stub delegates `exec <c> curl` → `curl()` (`$1=exec` && `$3=curl` → `shift 2; "$@"`). NO apostrophes in the added lines (single-quoted `bash -c` body).
- [ ] 3.3 `workspaces-luks-harness.sh` (`mon_prepare` PATH stubs): add `$d/bin/docker` that records + for `exec <c> curl` does `shift 2; exec "$@"`.
- [ ] 3.4 `workspaces-luks-freeze.test.sh`: assert `$CALLS` contains `docker exec soleur-web-platform curl` on the app_canary readyz path (revert-to-bare-curl guard).
- [ ] 3.5 `luks-monitor.test.sh`: assert the same transport on the monitor readyz path.

## Phase 4 — Verify (no ssh)
- [ ] 4.1 `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/readiness.test.ts` → pass.
- [ ] 4.2 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` → clean.
- [ ] 4.3 Run the infra shell suite (`test-all.sh` / repo shell-test entrypoint): freeze + monitor suites green, incl. T22/T22b/T22c preserved.
- [ ] 4.4 Confirm `git diff` shows comment-only edits in `readiness.ts` / `loopback.ts` (AC5).

## Phase 5 — Ship
- [ ] 5.1 PR body: justify Approach A vs B (userland-proxy argument); note web-1 `/mnt/data` is a live LUKS mapper this fix unblocks; `Ref #6812` — NO `Closes`.
- [ ] 5.2 Post-merge: `gh workflow run workspaces-luks-verify.yml`; read the emitted reason marker (not run status) — readyz arm no longer `readyz_gate_regression`.
