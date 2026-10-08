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
- [ ] 0.6 S0.5 `tenant-isolation-probe.sh` under preflight Step 10.5 (arm F
  needs file-cap'd bwrap — bounding-set question on the dev host; else the
  check reshapes to `judgement`).
- [ ] 0.7 S0.6 config strategy: narrow-bind `~/.claude/projects/<encoded-cwd>`
  + enumerated CLI config files (default) vs new state root (contingency).
- [ ] 0.8 S0.7 arm-F privilege mechanics in prod-posture container: setcap
  needs bounding-set `SYS_ADMIN` (`--cap-add` at docker run); app drops
  effective/permitted/ambient (NOT bounding); `getcap -r /` audit — no other
  file-cap'd binary; session-child cap sets carry no sys_admin; inner canary
  argv unchanged under file-cap'd bwrap.
- [ ] 0.9 S0.8 `$HOME` dependents + socat/proxy socket ownership under the
  arm-F table.

## Phase 1 — Failing tests

- [x] 1.1 `test/agent-outer-wrap.test.ts`: argv shape (no mount target under
  ws parent except own bind; **zero `--unshare-*`**; `--bind /proc /proc`
  pass-through; no `--clearenv`; no secrets in argv; realpath(command)+pkg
  dir bound; both resolver-root arms) + env-composition drift test + fixture
  pin (`infra/agent-outer-wrap-argv.json`).
- [ ] 1.2 Integration (sandbox-isolation-fixtures.ts): sibling absent from
  `ls`/`stat`/`mountinfo` inside the wrap; suite documents #9723 residual
  (no /proc assertions).
- [ ] 1.3 Mid-session sibling creation stays invisible (TOCTOU shape).
- [ ] 1.4 Fail-closed spawn: missing bwrap/command/bind-source → synthetic
  failed process, classified via `classifySandboxStartupError`.
- [x] 1.5 Options-drift (verified green: flag-off snapshot byte-identical): flag-off `buildAgentQueryOptions` output byte-
  identical to existing snapshot; flag-on second pinned shape.
- [ ] 1.6 File-tool vantage: Read on sibling path → ENOENT inside a wrapped
  session.
- [ ] 1.7 Session-child caps: post-exec `CapEff`/`CapBnd` carry no
  `sys_admin` (privilege-hygiene pin).

## Phase 2 — Implementation

- [x] 2.1 `server/agent-outer-wrap.ts`: `buildOuterWrapArgv({workspacePath,
  sessionId, cwd, command})` (signature pinned to probe) +
  `makeSandboxedSpawn()` — detached pgid kill (ESRCH caught), stderr ring
  buffer (continuous drain), spawn preflight (accessSync; synthetic 127
  fail, never hang), single `realpathSync` feeding bind src/dest/`--chdir`/
  hook, reprovision-serialized bind + dev+ino parity log.
- [x] 2.2 Mount table per plan T2.2 (system image ro-bind + derived state
  roots; `/etc` files `--file`, dirs `--ro-bind`; `--tmpfs /tmp`+TMPDIR;
  narrow `~/.claude` binds; bpf artifact; socket dir; gitfile targets; bound
  `/proc`; **no `--unshare-*`**).
- [x] 2.3 `AgentQueryOptionsArgs` + `workspaceId`/`sessionId`;
  `spawnClaudeCodeProcess` wired in `buildAgentQueryOptions` behind env flag
  (dispatch-time read, default off, workspace-allowlist arm); BOTH callers
  (`cc-dispatcher.ts`, `agent-runner.ts` `startAgentSession`).
- [ ] 2.4 `agent-runner-sandbox-config.ts`: comments only — deny stays
  unconditional while flag exists; file flag+deny deletion issue in-PR.
- [ ] 2.5 Persona parity test: support arm binds nothing under ws root.
- [x] 2.6 Dockerfile: `setcap` on `/usr/bin/bwrap` + `getcap -r /` audit
  line; entrypoint drops SYS_ADMIN (eff/perm/amb, keep bounding).
- [x] 2.7 `infra/cloud-init.yml`: `docker run` gains `--cap-add SYS_ADMIN`.

## Phase 3 — Canary + observability

- [ ] 3.1 `sandbox-canary.mjs` outer-wrap arm (capture fixture + deploy
  replay; report-only at first deploy).
- [ ] 3.2 Dual-vantage realized probe (fs surfaces + file-tool Read →
  ENOENT); `tenant-isolation-probe.sh` delegates to the same assertions.
- [x] 3.3 `op:"tenant-outer-wrap"` structured log per spawn incl. full argv.
- [ ] 3.4 Interpose-installed assertion in `verifyAgentSandboxHardening`.
- [x] 3.5 `apps/web-platform/scripts/agent-outer-wrap-debug.sh` operator repro entry.
- [ ] 3.6 Dep-bump smoke wired into `sandbox-canary-capture-gate`.
- [ ] 3.7 `scripts/followthroughs/tenant-outer-wrap-soak-5863.sh` + tracker.

## Phase 4 — Records

- [x] 4.1 Amend ADR-075 (arm F: mountns-only via file-cap bwrap; #9723
  residual + why; residuals incl. egress-bypass loopback grade).
- [x] 4.2 Art. 30 register row — `adopting`, honest tense, residuals named.
- [ ] 4.3 Issue #5863 close-out citing the claim ceiling; #9723 cross-refs
  #9773.
