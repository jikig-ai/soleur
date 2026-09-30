# Tasks: fix: worktree-manager create/feature hangs indefinitely on dependency install when the package registry is unreachable

Plan: `knowledge-base/project/plans/2026-09-30-fix-worktree-install-deps-sandbox-hang-plan.md` (closes #9269)

## Phase 1: Script changes (`plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh`)

- [x] 1.1 Add `SKIP_INSTALL=false` global beside `YES_FLAG`/`UPDATE_LOCAL_MAIN` (~:151); honour `[[ "${SOLEUR_WORKTREE_SKIP_INSTALL:-}" == "1" ]]` (session-state.sh:27 convention).
- [x] 1.2 Add `--no-install` to the global flag-parse loop (file tail) so it sets `SKIP_INSTALL=true` and is consumed (not passed positionally); document it + `SOLEUR_WORKTREE_SKIP_INSTALL` in `show_help` Global Flags.
- [x] 1.3 Add helpers above `install_deps` (:1653):
  - [ ] 1.3.1 `_install_registry_host <dir> <runtime>` — npm → `npm --prefix "$dir" config get registry` fallback `registry.npmjs.org`; bun → `bunfig.toml`/`.npmrc` grep, default `registry.npmjs.org`; yarn → `.yarnrc`, default `registry.yarnpkg.com`; strip scheme/userinfo/port/path; `_sanitize_marker_field` the result.
  - [ ] 1.3.2 `_registry_reachable <host>` — per-host `declare -A` memo; `command -v curl` gate (absent → return 0); `curl --proto '=https' --connect-timeout "${SOLEUR_WORKTREE_REGISTRY_PROBE_SECS:-5}" --max-time "${SOLEUR_WORKTREE_REGISTRY_PROBE_MAX_SECS:-8}" -sS -o /dev/null "https://$host/"`; rc-based (no `-f`).
  - [ ] 1.3.3 `install_to` array at globals: `install_to=(); if command -v timeout …; elif command -v gtimeout …; fi` with `${install_to[@]+"${install_to[@]}"}` expansion (bash-3.2/`set -u` safe — git-commit-secret-scan.sh:151-154 precedent).
  - [ ] 1.3.4 `_run_install <label> <runtime> <dir> <cmd...>` — probe → on failure emit `SOLEUR_WORKTREE_INSTALL_SKIPPED reason=registry-unreachable host=… arm=…` + `headless_or_stderr warn` naming host; else run under `${install_to[@]+…}`; rc 124|137 → `reason=timeout` marker + warn; other nonzero → existing `install failed` warn; rc 0 → existing success line.
- [x] 1.4 `install_deps` head: when `SKIP_INSTALL` → `echo "SOLEUR_WORKTREE_INSTALL_SKIPPED reason=opt-out"` + warn + skip both install blocks (hook-dep enumeration still runs).
- [x] 1.5 Rewire root block (:1694–1703) and apps loop (:1747–1754) through `_run_install`; keep `bun install` `allow-bun` waiver comments colocated; keep `Dependencies installed` / `install failed` strings byte-identical.
- [x] 1.6 `bash -n` syntax check + `shellcheck` the script if available.

## Phase 2: Telemetry registration

- [x] 2.1 Add `SOLEUR_WORKTREE_INSTALL_SKIPPED\b.*` to `MARKER_RE` in `apps/web-platform/server/git-lock-marker-telemetry.ts` (:134) with a MIRRORED-NOT-PAGED comment; do NOT add to `WEDGE_RE` (:309).
- [x] 2.2 Add a vitest row in `apps/web-platform/test/git-lock-marker-telemetry.test.ts` asserting `extractGitLockMarkers("SOLEUR_WORKTREE_INSTALL_SKIPPED reason=registry-unreachable host=registry.npmjs.org arm=root-npm")` → length 1, `wedged: false`.
- [x] 2.3 Verify: `cd apps/web-platform && ./node_modules/.bin/vitest run test/git-lock-marker-telemetry.test.ts`.

## Phase 3: Documentation

- [x] 3.1 `plugins/soleur/skills/git-worktree/SKILL.md` — document `--no-install` / `SOLEUR_WORKTREE_SKIP_INSTALL=1` near :96–118 (create args/`--update-local-main` area) and the `SOLEUR_WORKTREE_INSTALL_SKIPPED` sentinel + reasons.

## Phase 4: Regression suite (`plugins/soleur/test/worktree-manager-install-bounded.test.sh`)

- [x] 4.1 Scaffold on `worktree-manager-hook-deps.test.sh`: `TEST_DIR=$(mktemp -d)`; `export INCIDENTS_REPO_ROOT="$TEST_DIR/incidents"` + `mkdir -p` BEFORE `source test-helpers.sh` (#8659); `git_fixture_env`; `SOLEUR_SESSION_STATE_ROOT`; `TMPDIR=/var/tmp`; separate stdout/stderr capture; PATH stubs.
- [x] 4.2 Arms: (a) env opt-out — stub npm records calls, assert zero + `reason=opt-out` marker + rc 0 + worktree exists; (b) `--no-install` flag — same; (c) curl-stub exit non-zero — assert `reason=registry-unreachable` + `host=registry.npmjs.org` + npm never invoked + rc 0; (d) sleep-stub npm + `SOLEUR_WORKTREE_INSTALL_TIMEOUT_SECS=2` — bounded wall clock + `reason=timeout` + rc 0; (e) `SOLEUR_WORKTREE_SKIP_INSTALL=0` — install still runs (must-PASS); (f) `feature <name>` with opt-out — marker prints; (g) happy path — `Dependencies installed`.
- [x] 4.3 M7a: compose `node_modules/.bin/$HOOK_BIN`, never literal binary/path tokens.
- [x] 4.4 Run: `bash plugins/soleur/test/worktree-manager-install-bounded.test.sh` → 0 failures; `bash plugins/soleur/test/worktree-manager-hook-deps.test.sh` → still green.

## Phase 5: Verification & ship prep

- [x] 5.1 `bash scripts/lint-workflow-install-sites.sh` + `bash scripts/lint-orphan-test-suites.sh` green.
- [x] 5.2 Denied-egress smoke (if a sandbox/deny harness is available, else the curl-stub arm is the evidence): `create` completes in seconds with the named-host diagnostic.
- [x] 5.3 AC checklist pass against plan AC1–AC8.
- [x] 5.4 Commit with `Closes #9269` in the PR body (not title).
