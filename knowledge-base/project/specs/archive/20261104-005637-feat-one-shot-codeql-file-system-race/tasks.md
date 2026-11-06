# Tasks — feat-one-shot-codeql-file-system-race

Plan: `knowledge-base/project/plans/2026-11-03-fix-codeql-file-system-race-batch-plan.md`

## 1. Setup

- [x] 1.1 Worktree + draft PR #12035 exist; premise validation done (all five
      alerts open on main; five tracker issues open; PR #10926 same-file
      different-scope noted).

## 2. Core Implementation

- [x] 2.1 `plugins/soleur/scripts/install-opencode-adapter.ts` (alert #301):
      in `walkPayloadFiles`, replace `statSync(full).mode` + `readFileSync(full)`
      with one `openSync(full, O_RDONLY|O_NOFOLLOW|O_NONBLOCK)` → `fstatSync(fd)`
      (mode + `isFile()` guard, non-regular → throw mirroring the symlink refusal)
      → `readFileSync(fd, "utf-8")` → `closeSync` in `finally`. Extend the `fs`
      import with `constants`, `openSync`, `fstatSync`, `closeSync`; drop `statSync`
      if now unused.
- [x] 2.2 `apps/web-platform/test/no-network-fonts.test.ts` (alert #246): in
      `sweep`'s `requiredAssets` loop, replace `existsSync || statSync().size===0`
      then `readFileSync` with `openSync` → `fstatSync(fd)` → `readFileSync(fd)`;
      open failure pushes the existing "missing or empty" problem entry. Update
      imports; drop `statSync` only if unused elsewhere in the file.
- [x] 2.3 `apps/web-platform/test/server/inngest/cron-community-monitor-collector-status.test.ts`
      (alert #252): in the FIFO sidecar test, replace `statSync(fifo)` + the
      HUNG-path `open(fifo, "r+")` with a single `await open(fifo, "r+")` held
      across the `Promise.race`; `fh.stat().isFIFO()` for non-vacuity; `fh.close()`
      in `finally` doubles as the reader unblock.
- [x] 2.4 `apps/web-platform/test/bwrap-shim.test.ts` (alert #258): access
      `argsFile` once via `openSync(argsFile, "w+")` + `writeFileSync(fd)`; mint each
      `spawnSync` stdio fd via `openSync("/proc/self/fd/${argsFd}", "r")`; close
      descriptors; `rmSync` the mkdtemp dir in `finally`.
- [x] 2.5 `apps/web-platform/test/server/teardown-deleteuser-sentinel.test.ts`
      (alert #272): in `deleteUserCarriers`'s `visit`, replace `statSync(full)` +
      `readFileSync(full)` with `openSync`+`fstatSync`; dir branch closes fd then
      recurses; file branch reads via `readFileSync(fd, "utf8")`.

## 3. Testing

- [x] 3.1 Run the four touched vitest files + `plugins/soleur/test/opencode-adapter-install.test.ts`;
      all green.
- [ ] 3.2 `tsc`/lint on edited files clean; no unused imports.
- [x] 3.3 Confirm no path-based check→use pair remains at any flagged site
      (grep the five sites).

## 4. Ship

- [ ] 4.1 PR body: per-alert disposition table + `Closes #10925`, `Closes #9551`,
      `Closes #9646`, `Closes #9802`, `Closes #10118` each on its own line.
- [ ] 4.2 Commit author = repo CLA identity (Jean Deruelle via repo git config);
      Devin only as `Co-Authored-By` trailer.
- [ ] 4.3 `soleur:review` → resolve findings → `soleur:qa` (no Test Scenarios
      beyond the plan's unit rows) → `soleur:compound` → `soleur:ship` → merge.
