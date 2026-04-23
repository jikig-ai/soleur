# Tasks — Fix MU1 Ops Bugs (#2837, #2838, #2839)

Derived from `knowledge-base/project/plans/2026-04-23-fix-mu1-ops-bugs-audit-runbook-plan.md`.

## Phase 0 — Setup

- [ ] 0.1 Confirm branch is `feat-one-shot-fix-mu1-ops-bugs-2837-2838-2839` and the worktree is clean.
- [ ] 0.2 Re-verify the three bugs on current `main`:
  - [ ] 0.2.1 `ssh <prod-host> docker inspect soleur-web-platform --format '{{json .HostConfig.SecurityOpt}}'` — confirm seccomp is inlined JSON.
  - [ ] 0.2.2 `ssh <prod-host> find / -name audit-bwrap-uid.sh 2>/dev/null` — confirm no host-side checkout.
  - [ ] 0.2.3 `doppler run -p soleur -c dev -- node -e 'console.log(process.env.SUPABASE_URL, process.env.NEXT_PUBLIC_SUPABASE_URL)'` — confirm only the `NEXT_PUBLIC_` form is populated.

## Phase 1 — TDD: Write failing tests first

- [ ] 1.0 Create fixture directory + files:
  - [ ] 1.0.1 `mkdir -p apps/web-platform/infra/test-fixtures/audit-bwrap`.
  - [ ] 1.0.2 `valid-seccomp.json` — minimal ~3-line JSON (e.g., `{"defaultAction":"SCMP_ACT_ALLOW","syscalls":[]}`).
  - [ ] 1.0.3 `inspect-pass.txt` — 2 lines: `apparmor=soleur-bwrap` + `seccomp=<valid JSON inlined>`, where the inlined JSON is byte-equal after `jq -cS .` to `valid-seccomp.json`.
  - [ ] 1.0.4 `inspect-drift.txt` — 2 lines: `apparmor=...` + `seccomp=<JSON with added key or changed value>`.
  - [ ] 1.0.5 `inspect-no-seccomp.txt` — 1 line: `apparmor=soleur-bwrap`.
  - [ ] 1.0.6 `inspect-literal-path.txt` — 2 lines: `apparmor=soleur-bwrap` + `seccomp=/etc/docker/seccomp-profiles/soleur-bwrap.json`.
  - [ ] 1.0.7 `inspect-no-apparmor.txt` — 1 line: `seccomp=<valid JSON inlined>`.
- [ ] 1.1 Create `apps/web-platform/infra/audit-bwrap-uid.test.sh`:
  - [ ] 1.1.1 Skeleton matches `orphan-reaper.test.sh` (PASS/FAIL/TOTAL counters, `TEST_PATH_BASE` excluding `~/.local/bin`, per-case `mktemp -d` MOCK_DIR).
  - [ ] 1.1.2 `create_docker_mock` factory following `ci-deploy.test.sh:107` pattern — `MOCK_DOCKER_MODE` + `DOCKER_INSPECT_FIXTURE` + `DOCKER_EXEC_EXIT`.
  - [ ] 1.1.3 Each test exports env inside its subshell: `PATH`, `CONTAINER`, `EXPECTED_SECCOMP_PATH` (= path to `valid-seccomp.json`), `DOCKER_INSPECT_FIXTURE` (= path to the per-case `.txt` fixture), `DOCKER_EXEC_EXIT`.
  - [ ] 1.1.4 Case: PASS — `inspect-pass.txt` + `DOCKER_EXEC_EXIT=0` → audit exit 0, stderr empty, stdout contains `sha256=`.
  - [ ] 1.1.5 Case: FAIL — `inspect-drift.txt` → audit exit 1, stderr contains `seccomp drift`.
  - [ ] 1.1.6 Case: FAIL — `inspect-no-seccomp.txt` → audit exit 1, stderr contains `no seccomp= entry`.
  - [ ] 1.1.7 Case: FAIL — `inspect-literal-path.txt` → audit exit 1, stderr contains `literal path, not inlined JSON`.
  - [ ] 1.1.8 Case: FAIL — `inspect-pass.txt` + `EXPECTED_SECCOMP_PATH=/nonexistent` → audit exit 1, stderr contains `deploy state incoherent`.
  - [ ] 1.1.9 Case: FAIL — `inspect-no-apparmor.txt` → audit exit 1, stderr contains `missing apparmor=soleur-bwrap`.
  - [ ] 1.1.10 Case: FAIL — `DOCKER_EXEC_EXIT=1` (bwrap rejects) → audit exit 1, stderr contains `CLONE_NEWUSER rejected`.
  - [ ] 1.1.11 Final `echo "=== Results: $PASS passed, $FAIL failed, $TOTAL total ==="` + `[[ "$FAIL" -eq 0 ]]` exit gate.
  - [ ] 1.1.12 Run `bash apps/web-platform/infra/audit-bwrap-uid.test.sh` — expect failures (RED on uncreated script behavior).
- [ ] 1.2 Create `apps/web-platform/infra/mu1-runbook-cleanup.test.sh`:
  - [ ] 1.2.1 Skeleton: same PASS/FAIL/TOTAL convention.
  - [ ] 1.2.2 Each case uses `node --input-type=module -e "import { assertDevCleanupEnv } from '$SCRIPT_DIR/mu1-cleanup-guard.mjs'; try { assertDevCleanupEnv({ DOPPLER_CONFIG: '…', NEXT_PUBLIC_SUPABASE_URL: '…' }); console.log('no-throw'); } catch (e) { console.log('threw: ' + e.message); }"`.
  - [ ] 1.2.3 Case: `{ DOPPLER_CONFIG: 'dev', NEXT_PUBLIC_SUPABASE_URL: 'https://ifsccnjhymdmidffkzhl.supabase.co' }` → stdout `no-throw`.
  - [ ] 1.2.4 Case: `{ DOPPLER_CONFIG: 'prd', NEXT_PUBLIC_SUPABASE_URL: '…' }` → stdout matches `DOPPLER_CONFIG is not 'dev'`.
  - [ ] 1.2.5 Case: `{ DOPPLER_CONFIG: 'dev', NEXT_PUBLIC_SUPABASE_URL: 'https://otherref.supabase.co' }` → stdout matches `project ref 'otherref'`.
  - [ ] 1.2.6 Case: `{ DOPPLER_CONFIG: 'dev', NEXT_PUBLIC_SUPABASE_URL: '' }` → stdout matches `project ref ''`.
  - [ ] 1.2.7 Case: `{ DOPPLER_CONFIG: undefined, NEXT_PUBLIC_SUPABASE_URL: 'https://ifsccnjhymdmidffkzhl.supabase.co' }` → stdout matches `<unset>`.
  - [ ] 1.2.8 Run `bash apps/web-platform/infra/mu1-runbook-cleanup.test.sh` — expect failures (RED, guard file doesn't exist yet).

## Phase 2 — Implement #2837: audit script check 2 rewrite

- [ ] 2.1 Edit `apps/web-platform/infra/audit-bwrap-uid.sh`:
  - [ ] 2.1.1 Replace `EXPECTED_SECCOMP` with `EXPECTED_SECCOMP_PATH="${EXPECTED_SECCOMP_PATH:-/etc/docker/seccomp-profiles/soleur-bwrap.json}"`.
  - [ ] 2.1.2 Replace literal-match block with the four-branch seccomp check (no entry / literal path / file missing / hash mismatch → FAIL; match → PASS with hash prefix).
  - [ ] 2.1.3 Keep apparmor check unchanged.
  - [ ] 2.1.4 Update inline comment on check 2 to describe the new hash-compare semantics.
- [ ] 2.2 Run the Phase 1.1 tests — all cases GREEN.
- [ ] 2.3 `shellcheck apps/web-platform/infra/audit-bwrap-uid.sh` clean.

## Phase 3 — Implement #2839: cleanup guard helper

- [ ] 3.1 Create `apps/web-platform/infra/mu1-cleanup-guard.mjs`:
  - [ ] 3.1.1 Export `assertDevCleanupEnv()` — throws on `DOPPLER_CONFIG !== "dev"` or project-ref mismatch.
  - [ ] 3.1.2 Export `sweep()` — reads `NEXT_PUBLIC_SUPABASE_URL` + `SUPABASE_SERVICE_ROLE_KEY`, runs the synthetic-user listing + deletion (body identical to current runbook snippet less the guard).
  - [ ] 3.1.3 Document the `DEV_PROJECT_REF` constant with a comment pointing to the test's SYNTH allowlist coupling.
- [ ] 3.2 `node --check apps/web-platform/infra/mu1-cleanup-guard.mjs` passes.
- [ ] 3.3 Run the Phase 1.2 tests — all cases GREEN.

## Phase 4 — Implement #2838 + #2839: runbook updates

- [ ] 4.1 Edit `knowledge-base/engineering/ops/runbooks/mu1-signup-workspace-verification.md`:
  - [ ] 4.1.1 Step 2 cleanup snippet: replace inline guard + sweep with `assertDevCleanupEnv()` + `sweep()` import from the vendored helper.
  - [ ] 4.1.2 Step 2 prose (line ~94): rewrite to match new guard semantics (DOPPLER_CONFIG + project-ref).
  - [ ] 4.1.3 Step 3 SSH command: replace `ssh <host> "cd soleur && bash …"` with `ssh <host> "bash -s" < apps/web-platform/infra/audit-bwrap-uid.sh`.
  - [ ] 4.1.4 Step 3 add sub-bullet for CONTAINER-override form under the stdin-piped invocation.
  - [ ] 4.1.5 Step 3 add note referencing #2606 for the CI-wiring follow-up.
- [ ] 4.2 `npx markdownlint-cli2 --fix knowledge-base/engineering/ops/runbooks/mu1-signup-workspace-verification.md` clean.
- [ ] 4.3 `grep -n 'cd soleur\|SUPABASE_URL' knowledge-base/engineering/ops/runbooks/mu1-signup-workspace-verification.md` — only `NEXT_PUBLIC_SUPABASE_URL` should remain.

## Phase 5 — Integration verification (manual, pre-merge)

- [ ] 5.1 Run full MU1 runbook verbatim against prod:
  - [ ] 5.1.1 Step 1 offline tests: `cd apps/web-platform && ./node_modules/.bin/vitest run test/mu1-integration.test.ts` — 4 passed / 2 skipped.
  - [ ] 5.1.2 Step 2 cleanup dry-run under `doppler run -p soleur -c dev --` — completes (0 or N synth users deleted).
  - [ ] 5.1.3 Step 2 guard trip check: set `DOPPLER_CONFIG=prd` manually, confirm throw before any delete.
  - [ ] 5.1.4 Step 3 audit: `ssh <prod-host> "bash -s" < apps/web-platform/infra/audit-bwrap-uid.sh` — exit 0, three `PASS:` lines including the new seccomp hash line.
- [ ] 5.2 Capture output of 5.1.4 for attachment to PR body.

## Phase 6 — Compound + ship

- [ ] 6.1 Run compound skill to capture any learnings from the fix.
- [ ] 6.2 `/ship` to open PR with `Closes #2837`, `Closes #2838`, `Closes #2839` on separate lines in body.
- [ ] 6.3 Paste Phase 5.1.4 output into PR description as post-merge verification evidence.

## Follow-ups (out of scope, file separately if new)

- `#2606` already tracks CI wiring of the audit script — no new issue needed.
- If the cleanup-guard vendoring is rejected by plan review, replace Phase 3 + Phase 1.2 with an inline runbook edit and a `set -e` bash harness that pipes the guard to `node -e` under four env combinations.
