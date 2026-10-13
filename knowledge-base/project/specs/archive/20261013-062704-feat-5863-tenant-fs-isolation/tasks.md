# Tasks — feat-5863-tenant-fs-isolation

Plan: `knowledge-base/project/plans/2026-10-08-feat-tenant-fs-isolation-plan.md`
Issue: #5863 · Branch: `feat-5863-tenant-fs-isolation` · PR: #9767
Arm: **F — mountns-only outer wrap via file-cap'd bwrap** (spike-verified;
userns wraps are measured-incompatible with the vendored inner sandbox).

## Phase 0 — Spike

- [x] 0.0 `/proc` + nesting gate — **measured**: fresh `--proc` EPERM (masked
  paths unremovable); any outer userns kills inner's `--unshare-pid`/
  `--unshare-net`; arm F (file-cap bwrap, mountns-only, zero `--unshare-*`)
  verified working incl. captured inner argv. #9723 → open residual.
- [x] 0.3 S0.2 — `SpawnOptions.env` = `{...options.env}` + SDK mutations
  (CLAUDE_CODE_ENTRYPOINT=sdk-ts, NODE_OPTIONS deleted): verbatim
  passthrough is correct since we always pass options.env. Round-trip/
  resume/fd-enumeration still pend a stubbed-API test in Phase 1.
- [x] 0.4 S0.3 kill semantics: `detached:true` + `kill(-pgid)`; no orphan
  `claude`; server pgid untouched; ESRCH caught; no double-kill.
- [x] 0.6 S0.5 `tenant-isolation-probe.sh` under preflight Step 10.5 —
  **verified**: the probe is jq+bwrap-only (replays the committed fixture +
  pipes the shared payload), so it runs inside the Step-10.5-shaped
  `--unshare-all` sandbox (bun lives under the tmpfs'd /home and is never
  needed). `isolation_ok` measured locally nested inside Step-10.5's own
  bwrap invocation.
- [x] 0.7 S0.6 config strategy: **narrow-bind landed** — `--dir $HOME` +
  HOME_STATE_FILES (`.credentials.json`, `settings.json`) + `~/.claude.json`
  + HOME_SESSION_DIRS (`.claude/projects/<encoded-cwd>`
  session-transcript bind) per plan; no new state root needed.
- [x] 0.8 S0.7 privilege mechanics — Dockerfile `setcap cap_sys_admin,
  cap_setuid,cap_setgid+ep` + `getcap -r /` audit (bwrap is the ONLY
  file-cap'd binary) + cloud-init `--cap-add SYS_ADMIN` (bounding only — the
  app runs as non-root `soleur`, eff/perm/amb already empty). Session-child
  caps pinned by the real-wrap test (1.7). The inner canary argv is
  path-pinned (`/usr/bin/bwrap` absolute — the shim only interposes PATH).
- [x] 0.9 S0.8 `$HOME` dependents + proxy-socket ownership — the `--dir`
  home + `--tmpfs /tmp` table gives every session a private home/scratch
  (npm/gh/sock dirs write session-locally; the `claude-http-*.sock` dir is
  bound only when explicitly provided). Shared-loopback/delegated-egress
  cross-use is the named ADR-075 residual (#9723-adjacent, tracked).

## Phase 1 — Failing tests

- [x] 1.1 `test/agent-outer-wrap.test.ts`: argv shape (no mount target under
  ws parent except own bind; **zero `--unshare-*`**; `--bind /proc /proc`
  pass-through; no `--clearenv`; no secrets in argv; realpath(command)+pkg
  dir bound; both resolver-root arms) + env-composition drift test + fixture
  pin (`infra/agent-outer-wrap-argv.json`).
- [x] 1.2 Integration — real-wrap row in `agent-outer-wrap.test.ts` runs
  the shared `tenant-isolation-inner-probe.sh` inside the built table:
  sibling absent from parent `ls`/`stat`/`cat`/`/proc/self/mountinfo`
  (`isolation_ok`). #9723 residual documented in-payload (shared procfs
  expected).
- [x] 1.3 Mid-session sibling — probe-time `ws-bbbb` creation asserts a
  post-table-build sibling is never bound (the wrap binds paths, not the
  parent enumeration).
- [x] 1.4 Fail-closed spawn — all three preflight refusals (bwrap/command/
  bind-source) synthesize a failed process whose error carries the SDK's
  missing-binary signature → `missing_binary`/`sandbox_unavailable` + the
  outcome marker preserved for triage.
- [x] 1.5 Options-drift (verified green: flag-off snapshot byte-identical): flag-off `buildAgentQueryOptions` output byte-
  identical to existing snapshot; flag-on second pinned shape.
- [x] 1.6 File-tool vantage — the shared payload's fs-level read
  (`cat`/`stat` → ENOENT) IS the mountns vantage the Read tool sees (same
  kernel boundary, no hook-layer deny). No LLM needed.
- [x] 1.7 Session-child caps — post-exec `/proc/self/status` CapEff/
  CapBnd assertion runs INSIDE the real wrap in the integration row.

## Phase 2 — Implementation

- [x] 2.1 `server/agent-outer-wrap.ts`: `buildOuterWrapArgv({workspacePath,
  sessionId, cwd, home, pluginPath, appRoot})` (the `command` the plan
  pinned arrives per-spawn in `SpawnOptions`, not at wrap build — the
  vendored CLI rides the `appRoot/node_modules` ro-bind, covered by the
  `--smoke-outer` dep-bump gate) + `makeSandboxedSpawn()` — detached pgid
  kill (ESRCH caught), stderr ring buffer (continuous drain), spawn
  preflight (accessSync; synthetic 127 fail, never hang), single
  `realpathSync` feeding bind src/dest/`--chdir`/hook, dev+ino parity warn
  on workspace reprovision between build and spawn.
- [x] 2.2 Mount table per plan T2.2 (system image ro-bind + derived state
  roots; `/etc` files bound via `--ro-bind-try` — bind works for both file
  and dir and try-variants keep argv host-stable for the Guard-2 pin;
  `--tmpfs /tmp`+TMPDIR; narrow `~/.claude` binds; bpf artifact rides
  `/app/infra`; bound `/proc`; **no `--unshare-*`**). The plan's gitfile
  target mounts were DROPPED in review — `.git` indirection is
  tenant-controlled and any outside-workspace bind is an arbitrary-host-path
  primitive (see the module comment; platform readiness heals stranding
  pointers, #5733).
- [x] 2.3 `AgentQueryOptionsArgs` + `workspaceId`/`sessionId`;
  `spawnClaudeCodeProcess` wired in `buildAgentQueryOptions` behind env flag
  (dispatch-time read, default off, workspace-allowlist arm); BOTH callers
  (`cc-dispatcher.ts`, `agent-runner.ts` `startAgentSession`).
- [x] 2.4 `agent-runner-sandbox-config.ts`: deny stays unconditional
  (comment records load-bearing-off / vestigial-on); flag+deny deletion
  issue filed in-PR.
- [x] 2.5 Persona parity — support-arm argv test asserts zero binds under
  the workspaces root AND absence of `knowledge-base` (both arms).
- [x] 2.6 Dockerfile: `setcap` on `/usr/bin/bwrap` + `getcap -r /` audit
  as the runner-stage's LAST root layer (fail-closed, asserts bwrap's own
  cap set + {bwrap}-only); the app runs as `USER soleur` so SYS_ADMIN is
  bounding-only (no entrypoint needed — exec clears eff/perm/amb).
- [x] 2.7 `infra/cloud-init.yml` + `infra/ci-deploy.sh` (canary + prod
  docker run): `--cap-add SYS_ADMIN` on all three sites — cloud-init only
  covers first boot; deploys re-create the container here.

## Phase 3 — Canary + observability

- [x] 3.1 `--replay-outer` (committed `outer-bwrap-v1` fixture replay +
  shared payload, three-way verdict) + `run_outer_wrap_canary` in
  ci-deploy.sh (report-only, own soak ledger) + `outer_wrap_canary` on
  /hooks/deploy-status + Dockerfile COPYs.
- [x] 3.2 Shared `tenant-isolation-inner-probe.sh` (fs surfaces incl.
  file-tool-equivalent reads); founder probe + canary + tests all delegate.
  Opt-in boot self-probe `verifyOuterWrapRealizedIsolation`
  (`AGENT_OUTER_WRAP_BOOT_PROBE=1`, feature:agent-sandbox + Sentry fork).
- [x] 3.3 `op:"tenant-outer-wrap"` structured log per spawn incl. full argv.
- [x] 3.4 `probeOuterWrapInterpose` + `verifyOuterWrapInterpose` — flag-on
  must yield a real `spawnClaudeCodeProcess` on buildAgentQueryOptions
  output (cohort-aware); wired beside the hardening probe in index.ts with
  the same emit fork.
- [x] 3.5 `apps/web-platform/scripts/agent-outer-wrap-debug.sh` operator repro entry.
- [x] 3.6 `--smoke-outer` in sandbox-canary-verify-in-image.sh (native
  CLI inside the real table; smoke_fail short-circuits as last verdict),
  `server/agent-outer-wrap.ts`+outer fixture added to both trigger sets
  (ci.yml + sdk-bump-sandbox-gate.sh), `smoke_fail` blocking.
- [x] 3.7 `scripts/followthroughs/tenant-outer-wrap-soak-5863.sh` (reads
  `.outer_wrap_canary`; ≥5 greens/≥3d → PASS, sandbox_broken → FAIL,
  else TRANSIENT) + tracker **#9797** filed; flag+deny deletion issue **#9798**.

## Phase 4 — Records

- [x] 4.1 Amend ADR-075 (arm F: mountns-only via file-cap bwrap; #9723
  residual + why; residuals incl. egress-bypass loopback grade).
- [x] 4.2 Art. 30 register row — `adopting`, honest tense, residuals named.
- [ ] 4.3 Issue #5863 close-out citing the claim ceiling; #9723 cross-refs
  #9773.
