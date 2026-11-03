---
title: "fix: close five js/file-system-race TOCTOU alerts via one-descriptor reads"
type: fix
date: 2026-11-03
slug: fix-codeql-file-system-race-batch
branch: feat-one-shot-codeql-file-system-race
issue: 10925
closes: [10925, 9551, 9646, 9802, 10118]
priority: high
domain: engineering
brand_survival_threshold: none
---

# fix: close five js/file-system-race TOCTOU alerts via one-descriptor reads

## Overview

Five open CodeQL `js/file-system-race` (high, CWE-367) alerts on `refs/heads/main` each
pair a path-based filesystem check with a later path-based use of the same file. The fix
is the repo's established remediation idiom (commits `1b60715d80`, `7a3f264e0e`): open
each path once, then derive kind/mode/bytes from the same descriptor — `fstatSync` /
`fh.stat()` and `readFileSync(fd)` / `fh.readFile()` — so no window exists in which the
object can be swapped between check and use. One production script and four test files;
one PR closes all five tracker issues.

## Research Insights

### Premise Validation (Phase 0.6)

- All five tracker issues verified OPEN, each titled `sec: CodeQL alert #NNN —
  js/file-system-race`: #10925 (alert 301), #9551 (alert 246), #9646 (alert 252),
  #9802 (alert 258), #10118 (alert 272). None have linked or prose-referencing PRs
  (`linked:issue` and `#N in:body` probes, both states, all empty).
- All five alerts verified `state=open` on `refs/heads/main` via the code-scanning API;
  `most_recent_instance` line numbers match the operator's cited lines and the current
  tree (each flagged line is the path-based "use" of a check→use pair).
- The `#N` tokens in the brief for alert numbers (#301, #246, #252, #258, #272)
  coincidentally resolve to unrelated merged PRs / an unrelated closed issue
  (#258 = "Integrate Vercel MCP"); treated as contextual citations, not work targets.
- Collision precheck: open PR #10926 (`fix/npm-publish-sigpipe`) rewrites
  `install-opencode-adapter.ts` for a different scope (vendor-payload/npm publish); it
  overlaps the #301 file but not the alert semantics — whoever merges second rebases.
  Two sibling sessions run `test-all.sh` in unrelated worktrees
  (`feat-one-shot-12027-commit-author-identity-gate`, `feat-local-test-gate-speed`):
  shared-TMPDIR notice only, no same-file overlap. Tests run affected-only.
- ADR corpus grep for the mechanism (fd-reopen/O_NOFOLLOW/TOCTOU): no ADR rejects or
  constrains it; merged precedent `1b60715d80` already adopted it.

### Repo research

- Established idiom: `1b60715d80` (`snapshotClone opens each path once`): `open(abs,
  O_RDONLY | O_NOFOLLOW | O_NONBLOCK)` → `fh.stat()` → `fh.readFile()`, ELOOP →
  `readlink`, close failures swallowed. `7a3f264e0e`: `readdirSync({withFileTypes:
  true})` Dirent type + try/catch read. O_NOFOLLOW appears in ~15 source/test files.
- Per-site pairings (verified on disk in this worktree):
  - **#301** `plugins/soleur/scripts/install-opencode-adapter.ts:143-144`
    (`walkPayloadFiles`): `statSync(full).mode` then `readFileSync(full)` — REAL race,
    production install path; the file's documented invariant ("Symlinks are refused so
    a stray symlink in the source tree can never be dereferenced", line ~120) is itself
    weakened by the stat→read window. Fix: `openSync(full, O_RDONLY|O_NOFOLLOW|
    O_NONBLOCK)` → `fstatSync(fd)` (mode + `isFile()` guard, non-regular → throw,
    mirroring the symlink-refusal throw) → `readFileSync(fd, "utf-8")` → `closeSync`.
  - **#246** `apps/web-platform/test/no-network-fonts.test.ts:137-139`: `existsSync ||
    statSync().size===0` then `readFileSync` — fix: `openSync`/`fstatSync`/
    `readFileSync(fd)`; open failure → existing "missing or empty" problem entry.
  - **#252** `apps/web-platform/test/server/inngest/cron-community-monitor-collector-
    status.test.ts:213,226`: `statSync(fifo).isFIFO()` then `open(fifo, "r+")` — fix:
    `open(fifo, "r+")` once (O_RDWR never blocks on a FIFO, same guarantee the original
    unblock relied on), `fh.stat()` for the non-vacuity FIFO check, and `fh.close()`
    doubles as the HUNG-path unblock (closing the only writer end EOFs a stuck reader).
    Holds the inode pinned across the whole `Promise.race` window.
  - **#258** `apps/web-platform/test/bwrap-shim.test.ts:1570,1582,1591`:
    `writeFileSync(argsFile)` then `openSync(argsFile,"r")` twice — fix: create via a
    single `openSync(argsFile, "w+")` (the path's only access), `writeFileSync(fd)`,
    then mint each child's read descriptor via `openSync("/proc/self/fd/"+fd, "r")` —
    a fresh file description at offset 0 on the SAME inode (Node has no lseek to rewind
    one descriptor between two `spawnSync` reads; verified locally). Linux-only, which
    this suite already is (`skipIf(!BWRAP_OK)`, `/usr/bin/bwrap`, `mkfifo`).
  - **#272** `apps/web-platform/test/server/teardown-deleteuser-sentinel.test.ts:133,
    149`: `statSync(full)` gates dir-recursion and `readFileSync(full)` — fix:
    `openSync`+`fstatSync`; directory branch closes the fd then recurses by path
    (realpath/readdir are not flagged uses), file branch reads via `readFileSync(fd)`.
- Functional overlap: no shared "atomic stat+read" helper exists in the repo; the
  precedent applies the idiom inline per call site. Five sites × ~6 lines does not
  justify a new shared helper — kept inline (Cut List).

### Learnings

- `2026-04-13-codeql-alert-triage-and-issue-automation.md`: alert↔issue automation and
  dismissal mechanics (`"used in tests"`/`"false positive"`/`"won't fix"`, space-
  separated). Not needed — all five are fixed, nothing dismissed.
- `plans/archive/20261027-181105-...-fix-codeql-fs-race-digest-write-plan.md`: prior
  same-shape fix plan.

### External research

- CodeQL query help (`js-file-system-race`, CWE-367): "Use file descriptors instead of
  file names whenever possible" — `fs.open` then operate on the fd. Matches the chosen
  idiom. Independent projects fix the same rule with the identical open-once +
  fstat/read-via-fd shape (e.g. `O_NOFOLLOW` for the symlink-swap variant).

### Property List (Phase 0.6b)

1. Each flagged check→use pair observes one filesystem object through a single
   descriptor — no window in which it can be swapped between check and use. Observable:
   the five alerts transition to `fixed` on the post-merge CodeQL rescan of main.
2. Fixes use the repo's established idiom and preserve each suite's existing assertions
   and vacuity controls.
3. Per-item disposition is assessed and recorded; any item judged a test-only false
   positive is left open and noted in the PR body (never dismissed without operator
   sign-off).
4. One PR; `Closes #10925`, `Closes #9551`, `Closes #9646`, `Closes #9802`,
   `Closes #10118` each on its own line; commit author is the repo CLA identity.

### Cut List (Phase 0.6b)

- `fs.mkdtemp` / `O_EXCL` (brief's example remediations) → buy create-time atomicity —
  not the flagged class (all five are check→use read races, not exists→create). Covered
  by the open-once idiom.
- A shared `openAndRead` helper → buys reuse — the precedent applies the idiom inline
  and five small sites do not amortize a new abstraction.
- Dismissing the four test-file alerts → buyable only with operator sign-off; the fix
  is cheaper than the sign-off round-trip and precedent fixes test-site races rather
  than dismissing (`7a3f264e0e`).

## User-Brand Impact

- **If this lands broken, the user experiences:** a failing `test` suite in CI
  (vitest row for the touched files) or a broken `opencode` adapter install path —
  surfaced as install errors, not silent corruption.
- **If this leaks, the user's data / workflow / money is exposed via:** no exposure —
  the change narrows read windows; it grants no new access.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** the diff touches a plugin install script and
  test files — no credentials, auth, user data, or payment surface — so no user-facing
  incident is reachable from a defect here.

## Observability

```yaml
liveness_signal:
  what: "CodeQL code-scanning rescan of main: alerts #301, #246, #252, #258, #272 transition open -> fixed"
  cadence: "per-PR analyze + post-merge main analysis"
  alert_target: "GitHub code-scanning alert list (repo security tab)"
  configured_in: ".github/workflows/ (existing CodeQL analyze pipeline; no new surface)"

error_reporting:
  destination: "CI test output on the PR (vitest)"
  fail_loud: "a red vitest row for any touched file fails the PR's required test check"

failure_modes:
  - mode: "adapter payload walk regressed (open/fstat misuse)"
    detection: "plugins/soleur/test/opencode-adapter-install.test.ts fails in CI"
    alert_route: "required `test` check blocks the merge queue"
  - mode: "vendored-font sweep false failure"
    detection: "apps/web-platform/test/no-network-fonts.test.ts red"
    alert_route: "required `test` check blocks the merge queue"
  - mode: "FIFO sidecar probe or census regressed"
    detection: "the touched vitest files go red"
    alert_route: "required `test` check blocks the merge queue"

logs:
  where: "GitHub Actions run logs for the PR's test/CodeQL checks"
  retention: "GitHub default (~90 days)"

discoverability_test:
  command: rg -n 'O_NOFOLLOW|fstatSync' plugins/soleur/scripts/install-opencode-adapter.ts
  expected_output: O_NOFOLLOW
```

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Fix FIVE js/file-system-race (high) CodeQL alerts in one PR" | Phase 2 edits across five files | mapped |
| 2 | "#301 — plugins/soleur/scripts/install-opencode-adapter.ts:144 (tracker issue #10925)" | Task 2.1 | mapped |
| 3 | "#246 — apps/web-platform/test/no-network-fonts.test.ts:139 (tracker #9551)" | Task 2.2 | mapped |
| 4 | "#252 — apps/web-platform/test/server/inngest/cron-community-monitor-collector-status.test.ts:226 (tracker #9646)" | Task 2.3 | mapped |
| 5 | "#258 — apps/web-platform/test/bwrap-shim.test.ts:1591 (tracker #9802)" | Task 2.4 | mapped |
| 6 | "#272 — apps/web-platform/test/server/teardown-deleteuser-sentinel.test.ts:149 (tracker #10118)" | Task 2.5 | mapped |
| 7 | "assess per-item whether it is a real race (fix it) or a warning-level test-file false positive" | Per-alert disposition table (Context) + AC6 | mapped |
| 8 | "PR body MUST include `Closes #10925` ... each on its own line" | Ship-phase PR body requirement (AC7) | mapped |
| 9 | "Commit author: repo's CLA identity, never devin-ai-integration[bot]" | Author = repo git config (Jean Deruelle); Devin appears only as Co-Authored-By trailer per repo convention | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Five file edits | "Fix FIVE js/file-system-race (high) CodeQL alerts in one PR" | asked |
| fd/one-descriptor idiom | "e.g. atomic create/rename, fs.mkdtemp, O_EXCL, lstat-before-use" | inferred — brief names example mechanisms; repo precedent + CodeQL docs pick the fd idiom |
| Plan/tasks/session-state artifacts | (none) | inferred — pipeline convention |
| `## Observability` / `## User-Brand Impact` sections | (none) | inferred — plan Phase 2.9/2.6 gates |

### Split Assessment

- Subsystems touched: 2 — `plugins/soleur/scripts/`, `apps/web-platform/test/`
- Planned files: 5 | Estimated changed lines: ~90
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Open Code-Review Overlap

None — `gh issue list --label code-review --state open` bodies contain none of the five
planned paths.

## Files to Edit

- `plugins/soleur/scripts/install-opencode-adapter.ts` — alert #301
- `apps/web-platform/test/no-network-fonts.test.ts` — alert #246
- `apps/web-platform/test/server/inngest/cron-community-monitor-collector-status.test.ts` — alert #252
- `apps/web-platform/test/bwrap-shim.test.ts` — alert #258
- `apps/web-platform/test/server/teardown-deleteuser-sentinel.test.ts` — alert #272

## Implementation Phases

1. **Edits.** Apply the five one-descriptor fixes per Research Insights; extend each
   file's `node:fs` import list only as needed (`openSync`, `fstatSync`, `closeSync`,
   `constants`; `open`/`fh.stat()` already imported in the cron test).
2. **Targeted tests.** `bun run test` (or vitest) on the four touched test files +
   `plugins/soleur/test/opencode-adapter-install.test.ts` (covers `walkPayloadFiles`
   behavior); TypeScript check on the edited files.
3. **Ship.** `Closes #N` lines for all five trackers; semver patch; PR body carries the
   per-alert disposition table.

## Context

Per-alert disposition (assessed during planning, verified during work):

| Alert | Site | Disposition |
|-------|------|-------------|
| #301 | install-opencode-adapter.ts:144 | real race (production path; weakens the documented symlink-refusal invariant) — fixed |
| #246 | no-network-fonts.test.ts:139 | test-file site but genuine check→use pattern — fixed via same idiom (cheaper than a sign-off-gated dismissal) |
| #252 | cron-community-monitor-collector-status.test.ts:226 | test-file site, genuine pattern — fixed via single held descriptor |
| #258 | bwrap-shim.test.ts:1591 | test-file site, genuine pattern — fixed via one path access + `/proc/self/fd` re-opens |
| #272 | teardown-deleteuser-sentinel.test.ts:149 | test-file site, genuine pattern — fixed via open+fstat |

No alert is dismissed; nothing requires operator sign-off.

## Acceptance Criteria

- [ ] AC1: `plugins/soleur/scripts/install-opencode-adapter.ts` performs mode+read of
      each payload file through a single open descriptor (`fstatSync`/`readFileSync(fd)`);
      no `statSync(`→`readFileSync(` path pair remains at the #301 site.
- [ ] AC2: `no-network-fonts.test.ts` required-asset check uses one open descriptor;
      the `existsSync`/`statSync`→`readFileSync` pair at the #246 site is gone.
- [ ] AC3: the FIFO sidecar test opens `fifo` once and reuses that handle for the
      non-vacuity check and the HUNG-path unblock; `statSync(fifo)` is gone.
- [ ] AC4: `bwrap-shim.test.ts` accesses `argsFile` exactly once (create-open); both
      `spawnSync` reads use descriptors minted via `/proc/self/fd`.
- [ ] AC5: `teardown-deleteuser-sentinel.test.ts` census uses `openSync`+`fstatSync`
      and reads file bytes via the descriptor; `statSync(full)`→`readFileSync(full)`
      pair at the #272 site is gone.
- [ ] AC6: every disposition in the Context table is `fixed` (else the PR body records
      the item as left-open-with-reason — none expected).
- [ ] AC7: PR body contains `Closes #10925`, `Closes #9551`, `Closes #9646`,
      `Closes #9802`, `Closes #10118` each on its own line.
- [ ] AC8: the four touched vitest files and `opencode-adapter-install.test.ts` pass;
      `tsc`/lint on the edited files is clean.

## Test Scenarios

- Given the payload tree, when `walkPayloadFiles` runs, then each file's mode and bytes
  come from one descriptor and the existing adapter-install suite stays green (unit —
  covered by `plugins/soleur/test/opencode-adapter-install.test.ts`).
- Given a vendored-font tree variant, when `sweep` checks `requiredAssets`, then a
  missing/empty asset still pushes `vendored font missing or empty` and a non-WOFF2
  asset still pushes `not a WOFF2 file` (unit — the suite's own mutation rows).
- Given a FIFO sidecar, when the collector-status read is raced, then the suite still
  returns `present-but-failed (sidecar-unsafe)` and the non-vacuity FIFO assertion
  still fires (unit).
- Given the `--args <fd>` payload file, when both shim and control spawn, then each
  reads the payload from offset 0 on the same inode (integration — the suite's existing
  probe+control assertions).
- Given the `test/` census walk, when a file exists, then its bytes are read through
  the opened descriptor and carriers are still found (unit — anti-vacuity floor test).

## References

- CodeQL query help: `js/file-system-race` (CWE-367) — "use file descriptors instead of
  file names whenever possible."
- Repo precedent: `1b60715d80`, `7a3f264e0e`, `87d76ceec2`.
- Tracker issues: #10925, #9551, #9646, #9802, #10118.
- Overlap notice: open PR #10926 edits `install-opencode-adapter.ts` (different scope).

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — security/test hardening on existing code.
