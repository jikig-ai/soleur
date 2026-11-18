# Tasks: cron spawn isolation (#12824)

Plan: `knowledge-base/project/plans/2026-11-17-fix-cron-agent-editable-code-spawn-isolation-plan.md`
Decisions: `knowledge-base/project/specs/feat-one-shot-12824-cron-spawn-isolation/decision-challenges.md`

## Phase 0 — Measure (local only, prod-pinned CLI 2.1.321)

- [ ] 0.0 Write `probes/cli-isolation-probe.sh` (scratch dir under the session scratchpad, empty HOME, dummy `GH_TOKEN`, dev `ANTHROPIC_API_KEY` read-only from Doppler dev; disclose ~USD 0.05 of haiku spend).
- [ ] 0.1 Negative control: no `--plugin-dir`, no marker.
- [ ] 0.2 Empty-HOME `--print` with the prod flag shape returns a `result` event; record HOME files created; git commit identity under the pin and `gh` with `GH_TOKEN` work under an empty HOME.
- [ ] 0.3 Path 3: edited plugin `PreToolUse(Bash)` hook runs on the next call; control arm with a read-only plugin dir.
- [ ] 0.4 Path 4: in-run vs cross-run `.bashrc` re-source; apply the pre-written decision rule.
- [ ] 0.5 `${CLAUDE_PLUGIN_ROOT}` substitution form under an absolute `--plugin-dir`; apply the pre-written branch.
- [ ] 0.6 ux-audit `/app/node_modules/.bin/` MCP binary under an empty HOME as uid 1001, in the pinned image if pullable (else label `unverified-in-image`); record browser reachability.
- [ ] 0.7 `bun install` / `npm ci` under an empty HOME with the registry unreachable (cold cache); on failure accept the degraded baseline, never share the `/home/soleur` cache.
- [ ] 0.8 Local `docker run -v <dir>:/p:ro` arm: record the errno `accessSync(W_OK)` returns (uid 1001 and root); accept only EROFS/EACCES.
- [ ] 0.8a `git branch -r` in a `git clone --depth=1` of the repo; anything beyond `origin/main` makes the roadmap-review `git switch` fix an in-PR task.
- [ ] 0.8b Write the decision branches for 0.4, 0.5, 0.7 and 0.8 into `measurements.md` before running any arm.
- [ ] 0.8c worktree-manager `create` from a `chmod -R a-w` plugin copy with CWD in a depth-1 clone (`SOLEUR_WORKTREE_SKIP_INSTALL=1`).
- [ ] 0.8d Nested CLAUDE.md `@`-import canary under `.git/` (plan arm 0.7g); apply the pre-written S3 branch.
- [ ] 0.9 (plan arm 0.7f) Write `measurements.md` (version, command, output excerpt, verdict per arm).

## Phase 1 — Tests first (RED)

- [ ] 1.1 `test/server/inngest/cron-spawn-isolation.test.ts` — Guard 2 (spawn spy: HOME, argv, refusal, `loadPlugin`) and Guard 3 (resolver, `vi.mock` of `_cron-spawn-fs.ts`; Guard 2 on the real fs with only `spawn` mocked).
- [ ] 1.2 `test/server/inngest/cron-write-execute-census.test.ts` — Guard 1 (AST-discovered population over all of `server/`, non-call references fail, Write-confinement probes, PATH entries outside run roots, empty all-writable set and exemption map, executed-path sources, real `decide()` over Write/Edit and the tree-writing probe set, arbitrary-exec line-shape class (set must be empty), anchor citing `docker-run-tuple.test.sh` (no `:ro` re-check), known-writable control row, root = `SOLEUR_PLUGIN_PATH_DEFAULT`, exemption identity map, UNCLASSIFIED bucket).
- [ ] 1.3 Update shape tests to the new contract (derive the list with the `git grep` in Files to Edit).

## Phase 2 — Implementation (GREEN)

- [ ] 2.1 `resolveCronPluginRoot()` + `CronPluginRootError` + op `cron-plugin-root-untrusted`; once per run in setup, NonRetriableError; root and `hooks/` W_OK probe; one `.seed-complete` retry; seed-tag compare at exit (`plugin-reseeded-mid-run`); fs calls in `_cron-spawn-fs.ts`.
- [ ] 2.2 `buildClaudeArgv()`, `--plugin-dir` refusal (both forms), required `loadPlugin`.
- [ ] 2.3 Per-spawn HOME `mkdtemp(join(ephemeralRoot,"home-"))` (sibling of `repo/`), `TMPDIR=<HOME>/tmp`, env order, mkdtemp inside try (op `cron-spawn-home-create`), removal after SIGKILL settles (op `cron-spawn-home-teardown`).
- [ ] 2.4 `<plugin-root>` substitution in `buildAllowlistLines(…, pluginRoot)`; `runHookSelfTest` gets the substituted lines; bug-fixer and community-router lines; community-monitor prompt from the substituted lines.
- [ ] 2.5 18 callers: drop the flag pair / pass `loadPlugin`; rewrite stale comments (substrate #5091 block, cron headers).
- [ ] 2.6 ux-audit MCP `command` -> `/app/node_modules/.bin/` binary, unconditionally.
- [ ] 2.6a Shared seeded plugin-root test fixture; update every spawn-ending handler test (`git grep -l 'spawnClaudeEval\|setupEphemeralWorkspace' apps/web-platform/test`); CLI-pin staleness test.
- [ ] 2.7 Vendored-file coverage census row; per-miss dispositions (default degrade; clone path only for a no-write, no-exec cron with exemption).

- [ ] 2.9 Containment hook Write/Edit/MultiEdit allow-by-root (clone + `home-*` HOME, realpath of nearest existing ancestor, deny reason `write outside run roots`); enumerate every cron write site; move ux-audit `/tmp/ux-audit` and profile under TMPDIR/HOME.
- [ ] 2.10 Bug-fixer: drop `./node_modules/.bin/vitest run`, set `SOLEUR_WORKTREE_SKIP_INSTALL=1`, prompt test step -> no-baseline path; empty exemption map.
- [ ] 2.11 `GIT_CONFIG_COUNT=3` (hooksPath=/dev/null, fsmonitor=false, safe.bareRepository=explicit) at the pin spread point; update #12757 census maps; test nothing else sets COUNT.

## Phase 3 — Census battery

- [ ] 3.1 Run the Guard 1-3 mutation matrices and harness rows once against the finished suites; record per-row results for the PR body.
- [ ] 3.2 `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest` and `./node_modules/.bin/tsc --noEmit`.
- [ ] 3.3 Run the Observability `discoverability_test.command`; expect `deny` (reason `cron-containment: not allowlisted`).

## Phase 4 — Records and follow-ups

<!-- lint-infra-ignore start: follow-up issue specs to file, not steps a person runs -->
- [x] 4.1a (#12856 #12857 #12860) File F3 (atomic versioned seed), F4 (mount canary readiness gate), F5 if 0.6 shows the browser unreachable; no priority labels.
- [x] 4.1 (#12854 #12855 #12858) File F1 (token out of agent env; p1, `single-user incident`, active milestone; re-evaluation: no cron regains a test runner/install until tokenless; mention `npm_config_ignore_scripts` and moving the hook `.mjs` to the `:ro` root) and F2 (Dockerfile chowns only `.next/cache`; ISR measurement first; CPO recommendation recorded; no priority label — operator sets it). F6: CI runs agent-committed code with secrets.
<!-- lint-infra-ignore end -->
- [ ] 4.2 Put F1/F2 numbers in the census exemption map and the ADR.
- [ ] 4.3 Amend ADR-033 (cron spawn) with the 2026-11-17 amendment; update the #12757 residual bullet.
- [ ] 4.4 Read all three `.c4` files in full; record actors/systems/stores/relationships checked; run `bash plugins/soleur/test/c4-count-parity.test.sh`.
- [ ] 4.5 Verify AC15 monitor routing for the 13 resolver-dependent crons in `infra/sentry/cron-monitor-alerts.tf`.
- [ ] 4.6 PR body: plain "still open" first paragraph (AC16: token still in env -> F1; bug-fixer has no local baseline; founder-workspace/server-build writes closed here; CLO read requested), Phase 0 tables, mutation battery results, `Closes #12824`, `Ref #9601`.
