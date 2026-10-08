# Tasks — feat-5863-tenant-fs-isolation

Plan: `knowledge-base/project/plans/2026-10-08-feat-tenant-fs-isolation-plan.md`
Issue: #5863 · Branch: `feat-5863-tenant-fs-isolation` · PR: #9767

## Phase 0 — Spike gates (evidence before implementation)

- [ ] 0.1 S0.0 `/proc` gate: `bwrap --unshare-user --unshare-pid --proc /proc -- true` in a prod-posture container; if EPERM, verify whether any honest arm remains (`--tmpfs /proc` starves the inner shim's `/proc/self/fd` sweep; `--bind /proc` never scopes). If unviable → surface that #9723 stays open (re-scope in the open).
- [ ] 0.2 S0.1 real-session spawn: full minimal table wraps vendored `claude`; nested inner bwrap still works; enumerate `$HOME` dependents + socat/proxy socket ownership (+ per-session socket feasibility).
- [ ] 0.3 S0.2 `spawnClaudeCodeProcess` round-trip vs stubbed API (hermetic-cli-env): resume uses same path; signal arrives post-grace; measure `SpawnOptions.env` contents (passthrough vs intersect with `buildAgentEnv` keyset); enumerate inherited fds ≥3.
- [ ] 0.4 S0.3 kill semantics: `detached:true` + `kill(-pgid)`; no orphan `claude`; server pgid untouched; ESRCH caught; no double-kill via `options.signal`.
- [ ] 0.5 S0.4 prod bwrap version + masked-proc re-measure; prefer one argv valid on the deployed floor.
- [ ] 0.6 S0.5 `tenant-isolation-probe.sh` executes under preflight Step 10.5 (bwrap-in-bwrap) — else reshape before relying on the founder-check pin.
- [ ] 0.7 S0.6 config strategy: narrow-bind `~/.claude/projects/<encoded-cwd>` + enumerated CLI config files onto `--dir $HOME` (default) vs new per-tenant root (contingency only).

## Phase 1 — Failing tests

- [ ] 1.1 `test/agent-outer-wrap.test.ts`: argv shape (no mount target under ws parent except own bind; `--unshare-pid`; proc per S0.0; no `--clearenv`; no secrets in argv; binds realpath(command)+package dir; both resolver-root arms) + env-composition drift test + committed fixture pin (`infra/agent-outer-wrap-argv.json`).
- [ ] 1.2 Integration via `test/helpers/sandbox-isolation-fixtures.ts`: sibling absent from ls/stat/mountinfo; no non-session pids; sibling environ unreachable.
- [ ] 1.3 Mid-session sibling creation stays invisible (TOCTOU shape).
- [ ] 1.4 Fail-closed spawn: missing bwrap/command/bind-source → synthetic failed process, classified via `classifySandboxStartupError`.
- [ ] 1.5 Options-drift: flag-off `buildAgentQueryOptions` output byte-identical to existing snapshot; flag-on second pinned shape.
- [ ] 1.6 File-tool vantage test: Read on sibling path → ENOENT inside a wrapped session.

## Phase 2 — Implementation

- [ ] 2.1 `server/agent-outer-wrap.ts`: `buildOuterWrapArgv({workspacePath, sessionId, cwd, command})` (signature pinned to the probe's call) + `makeSandboxedSpawn()` — detached pgid kill, stderr ring buffer (continuous drain), spawn preflight (accessSync; synthetic 127 fail, never hang), `realpathSync` once feeding bind src/dest/`--chdir`/hook, reprovision-serialized bind + dev+ino parity log.
- [ ] 2.2 Mount table per plan T2.2 (system image ro-bind + derived state roots; no `--unshare-net`/`-uts`; `/etc` files `--file`, dirs `--ro-bind`; `--tmpfs /tmp`+TMPDIR; narrow `~/.claude` binds; bpf artifact; socket dir; gitfile targets).
- [ ] 2.3 `AgentQueryOptionsArgs` gains `workspaceId`/`sessionId`; `spawnClaudeCodeProcess` wired in `buildAgentQueryOptions` behind env flag (dispatch-time read, default off, workspace-allowlist arm); BOTH callers (`cc-dispatcher.ts`, `agent-runner.ts` `startAgentSession`).
- [ ] 2.4 `agent-runner-sandbox-config.ts`: comments only — deny stays unconditional while flag exists; file the flag+vestigial-deny deletion issue in this PR.
- [ ] 2.5 Persona parity test: support arm binds nothing under ws root (cwd=pluginPath); `allowRead` arm unaffected.

## Phase 3 — Canary + observability

- [ ] 3.1 `sandbox-canary.mjs` outer-wrap arm (capture fixture + deploy replay; report-only at first deploy).
- [ ] 3.2 Dual-vantage realized probe (Bash-side mounts/proc + file-tool Read → ENOENT); `tenant-isolation-probe.sh` delegates to the same assertions.
- [ ] 3.3 `op:"tenant-outer-wrap"` structured log per spawn incl. full emitted argv (secrets-free by construction).
- [ ] 3.4 Interpose-installed assertion in `verifyAgentSandboxHardening` output checks.
- [ ] 3.5 `scripts/agent-outer-wrap-debug.sh` operator repro entry.
- [ ] 3.6 Dep-bump smoke wired into `sandbox-canary-capture-gate` trigger set.
- [ ] 3.7 `scripts/followthroughs/tenant-outer-wrap-soak-5863.sh` + tracker issue with `soleur:followthrough` directive + label.

## Phase 4 — Records

- [ ] 4.1 Amend ADR-075 (Option B adopted in outer-wrap form; residuals incl. egress-bypass loopback grade; naming survives).
- [ ] 4.2 Art. 30 register row — `adopting` status, honest tense, residuals named with tracking links.
- [ ] 4.3 Issue #5863 close-out comment citing the claim ceiling; residuals cross-referenced to #9773.
