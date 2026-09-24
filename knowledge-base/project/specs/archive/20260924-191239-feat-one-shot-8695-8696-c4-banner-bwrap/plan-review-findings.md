# Plan-review findings (not yet integrated into the plan)

Reviews ran against the plan at fff6121b09, after the planning subagent was terminated by a rate limit. Fold these in during deepen-plan. Overlaps with `spec-flow-findings.md` are noted.

## Architecture review (architecture-strategist)
1. **P0 — server follows what the child leaves in `/c4-out`** (same as spec-flow #1). Also `/dev/zero` symlink → OOM, FIFO → hang holding the render slot. Fix: open `O_RDONLY|O_NOFOLLOW|O_NONBLOCK`, `fstat` regular file + size cap (~20 MiB), read from that fd. Guard rows: symlink, pipe, oversize; real-bwrap row where a `node -e` payload plants the symlink. Cite AP-020 in the ADR-050 amendment.
2. **P1 — Guard 1 pins destinations, not sources.** `--ro-bind /workspaces /c4-sources` passes. Fix: `/usr`,`/etc/*`, extra ro binds source==dest; `/c4-sources` source under `c4RenderStagingRoot()`; `/c4-out` source == `<same mkdtemp>/out`; mutation row each.
3. **P1 — `extraRoBinds` can widen the sandbox in prod** (stray `LIKEC4_BIN` walk-up to `/app/package.json`). Fix: in `NODE_ENV=production`, node+likec4 realpaths must be under `/usr` and `extraRoBinds` empty, else `sandbox_error`.
4. **P1 — boot self-probe before `listen`**; a sync throw from realpath rejects `app.prepare().then` → server never starts. Fix: run after `listen` via `void Promise.resolve().then(verifyC4RenderSandboxOnce).catch(report)`; unit row where resolution throws and boot continues.
5. **P2 — probe too weak** (same as spec-flow #5): 2-element real export on the same argv.
6. **P2 — `c4-render.ts` bundled twice** (esbuild custom server + next build): probe-captured `bwrap=<version>` never reaches the route copy; `POOL_SIZE=2` per bundle → up to 4 concurrent layouts (2 concurrent measured 12.5 s at 2 CPUs; 4 nears the 25 s timeout). Fix: lazy `bwrap --version` in render path; state 4-render ceiling; include `STAGE_SETTLE_GRACE_MS` and `rm` in the 45 s budget.
7. **P2 — isolation tests vacuous on CI** (same as spec-flow #6) + loop `fs.fstatSync(3..255)` for inherited fds.
8. **P2 — kernel surface.** Add `--unshare-ipc`; measure `--disable-userns` (may fail on RO `/proc/sys`); replace Guard 4 "subset of SDK flags" with explicit allowed set {user,pid,net,ipc,uts}; tmpfs `--size` if bwrap 0.8.0 supports it, else `RLIMIT_FSIZE`.
Confirmed sound: mounts already exercised by SDK canary argv; AppArmor allows mount/pivot_root; `NODE_ENV=production` in Dockerfile; C4 model unchanged is correct; ADR-050 amendment is the right vehicle.

## Kieran review
1. **P1 — builder fixes the command tail**, but boot probe and real-bwrap row need other commands. Fix: `command: string[]` param; Guard 1 pins the render site's command exactly.
2. **P1 — spawn count wrong**: `bwrap --version` is a third spawn with no `--`, RED under Guard 1 row 10; dev opt-out's direct spawn bypasses the builder. Fix: enumerate every spawn; exempt `["--version"]` by exact match or drop it; say whether opt-out shares the render spawn call.
3. **P1 — `fs/promises` mock breaks** on `realpath`/`access`/`stat` additions; `realpathSync` unmocked hits real fs. Fix: use `fs/promises` versions, add to `fsMock`, update boundary test list in the same commit; reset memo with `vi.resetModules`.
4. **P1 — two existing `c4-render.test.ts` fixtures go RED** under the views check ("replaces the random stage path…", "maps a canonicalize failure to io_error" both use `views: {}`). Fix: give both an `index` view; add to Files to Edit.
5. **P1 — real-bwrap row can't live in `c4-render-sandbox.test.ts`** (hoisted `vi.mock('node:child_process')`). Move to `c4-render-tenant-config.test.ts` or its own file.
6. **P2 — Guard 1 contract**: say how the expected set is built given `realpath(process.execPath)` varies; reword "only writable destination is `/c4-out`" → "only writable bind from the host".
7. **P2 — resolution-failure phase**: "likec4 not resolvable" `sandbox_error` must carry `phase:"spawn"` to get `INTERNAL_DIAGNOSTIC` (AC5).
8. **P2 — CI step**: `sudo -n apt-get update` first; tenant-config skip check must actually run `bwrap --unshare-user … /bin/true`; note ubuntu-latest bwrap ≈0.9 vs prod 0.8.0 in the ADR note.
9. **P2 — `queueWaitMs`**: make optional or list mocks to update (`c4-writer-concurrency.test.ts`).
10. **P2 — boot probe fires in local dev** (no bwrap) → skip when opt-out active.
Confirmed accurate: `onSaved` threading (one-arg call when no diagnostic), parents hold only `stale: boolean`, `setTab("diagram")` after save, new reasons fall through to `INTERNAL_DIAGNOSTIC`, `RATE_LIMITED_DIAGNOSTIC` text, CI job shape, `verifyWorkspacesMountOnce` precedent. `SpawnResult` reason list still needs `"sandbox_error"`.
