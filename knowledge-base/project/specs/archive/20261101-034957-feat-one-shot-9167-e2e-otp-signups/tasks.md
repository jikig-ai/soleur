# Tasks — feat-one-shot-9167-e2e-otp-signups

Plan: `knowledge-base/project/plans/2026-10-31-fix-e2e-webserver-exit-marker-plan.md`
Issue: #9167 (closes)

## Phase 1 — Server-exit marker

- [x] 1.1 Create `apps/web-platform/e2e/web-server.sh` per plan MVP: `#!/usr/bin/env bash`, `set -uo pipefail`, `--selftest` arm (`marker_fd=1`, `set -- true`), usage guard (exit 2), `"$@" &` + `wait` + rc capture + `e2e-webserver: exited rc=... port=... distdir=... uptime=...s` on `>&"$marker_fd"`, `exit "$rc"`. `chmod +x`.
- [x] 1.2 Edit `apps/web-platform/playwright.config.ts`: both `webServer` entries → `command: "bash e2e/web-server.sh npm run dev"` + `name: "e2e-public"` / `name: "e2e-auth"`; keep `url:`, `timeout: 180_000`, `reuseExistingServer`, `env:` (incl. `NEXT_DIST_DIR`) unchanged; one comment line noting the marker contract.

## Phase 2 — Marker test coverage

- [x] 2.1 Create `apps/web-platform/test/playwright-web-server-exit-marker.test.ts` (vitest + `spawnSync`): rc pass-through (`true`→0, `bash -c 'exit 42'`→42, `bash -c 'kill -9 $$'`→137), usage guard →2, `--selftest` → stdout marker + rc 0, marker carries `port=`/`distdir=`/`uptime=` fields (assert `port=3101` with `env: { PORT: "3101" }`), and comment-stripped config-text assertions (each webServer `command:` references `e2e/web-server.sh`; each entry declares a unique `name:`).
- [x] 2.2 `cd apps/web-platform && npx vitest run test/playwright-web-server-exit-marker.test.ts test/playwright-dev-server-distdir.test.ts` — both green.

## Phase 3 — Mock log self-labeling

- [x] 3.1 Edit `apps/web-platform/e2e/otp-login.e2e.ts`: `msg`/`message` → `"[e2e-mock] Signups not allowed for otp"`; extend the comment per plan §3 (fabricated string = CI-log noise, not an env failure).

## Phase 4 — Verification & issue close-out

- [x] 4.1 Re-run merge-group `e2e` measurement (`gh run list --workflow ci.yml --event merge_group -L 300` + per-run `gh run view <id> --json jobs` for the `e2e` job) and post the corrected count (0 OTP/font-mechanism recurrences; the `ERR_CONNECTION_REFUSED :3100` reds named by run id as the #11299 residual — NEVER the falsified "60/60 green since 2026-10-06" figure) + falsified-premise summary + run-37435711833 signature + marker design as `gh issue comment 9167`.
- [ ] 4.2 PR body carries `Closes #9167` (via soleur:ship).
- [ ] 4.3 Verify `e2e` CI check green on the PR and its log shows `[e2e-public]` / `[e2e-auth]` prefixes.
