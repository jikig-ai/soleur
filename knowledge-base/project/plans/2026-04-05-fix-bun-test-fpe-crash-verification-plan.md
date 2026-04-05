---
title: "fix: verify bun test FPE crash resolution and close #1511"
type: fix
date: 2026-04-05
semver: patch
closes: "#1511"
---

# fix: verify bun test FPE crash resolution and close #1511

## Overview

Issue #1511 reports that `bun test` crashes with a Floating Point Error (SIGFPE) in Bun v1.3.6. Investigation confirms the crash no longer reproduces -- it was resolved by a combination of prior work:

1. **Bun version pin to 1.3.11** (#860) -- `.bun-version` pins the project to a version that fixes the GC/allocator FPE bug present in Bun <= 1.3.5
2. **Sequential test runner** (#860) -- `scripts/test-all.sh` isolates test suites to avoid the high-subprocess-count crash pattern
3. **Dual-runner exclusion** (#1517) -- web-platform tests are excluded from `bun test` discovery via `bunfig.toml` `pathIgnorePatterns`, preventing happy-dom corruption of native APIs

The remaining work is verification, issue hygiene (updating the issue title and closing it), and optionally upgrading the Bun version pin if a newer stable version is available.

## Problem Statement

### Original Issue

```text
panic: Floating point error at address 0x41C2C7E
oh no: Bun has crashed. This indicates a bug in Bun, not your code.
```

The crash occurs during Bun's internal process accounting when the GC fires during spawn-heavy test runs. It is a known class of Bun bugs (upstream: [oven-sh/bun#20429](https://github.com/oven-sh/bun/issues/20429), labeled `old-version`).

### Current State (Already Fixed)

| Check | Result |
|---|---|
| `.bun-version` | 1.3.11 (pinned, CI reads via `bun-version-file`) |
| Local `bun --version` | 1.3.11 |
| `bun test` (3 runs) | 1199 pass, 0 fail, no crash |
| `bash scripts/test-all.sh` | 10/10 suites pass |
| Root `bunfig.toml` `pathIgnorePatterns` | `[".worktrees/**", "apps/web-platform/**"]` |
| Web-platform `bunfig.toml` `pathIgnorePatterns` | `["**"]` (defense-in-depth) |
| Upstream Bun issue #20429 | Open, labeled `old-version` |
| Latest Bun release | v1.3.11 (2026-03-18) |

## Proposed Solution

### Phase 1: Verification and documentation

1. **Confirm no FPE crash on current setup** -- run `bun test` 5+ times from repo root, run `scripts/test-all.sh`, verify 0 crashes (DONE during planning -- see Current State table above)
2. **Update issue #1511** -- add a comment documenting the resolution path and close the issue
3. **Update PR #1527** -- either close it (if no code changes needed) or use it to carry any remaining fixes

### Phase 2: Version evaluation (conditional)

Check whether a Bun version newer than 1.3.11 is available. If so, evaluate whether upgrading provides value:

- If newer version exists and has no regressions: update `.bun-version`, run full test suite, commit
- If 1.3.11 is still latest: no change needed, document in the issue comment

### Phase 3: Cleanup

1. **Verify the FPE learning doc is accurate** -- `knowledge-base/project/learnings/2026-03-20-bun-fpe-spawn-count-sensitivity.md` references Bun 1.3.5 but the issue title says 1.3.6. Confirm whether 1.3.6 was also affected and update if needed
2. **Verify bunfig.toml comment accuracy** -- the root `bunfig.toml` comment says "Bun <=1.3.5" but issue #1511 references 1.3.6. Update the comment if the FPE affected versions through 1.3.6

## Non-goals

- Fixing the upstream Bun FPE bug (oven-sh/bun's responsibility)
- Migrating away from Bun as a test runner
- Restructuring tests to reduce subprocess spawn counts
- Adding a Bun version manager (the `.bun-version` file + `scripts/test-all.sh` version check is sufficient)

## Acceptance Criteria

- [ ] `bun test` from repo root succeeds reliably (5+ consecutive runs) on Bun 1.3.11+
- [ ] `bash scripts/test-all.sh` runs all suites and exits 0
- [ ] Issue #1511 is closed with a resolution comment
- [ ] PR #1527 is either closed (no changes needed) or merged with any version/comment fixes
- [ ] `bunfig.toml` FPE comment accurately reflects the affected version range
- [ ] Learning document version references are consistent with issue #1511

## Test Scenarios

- Given Bun 1.3.11 installed, when `bun test` runs 5 times from repo root, then all runs complete with 0 failures and no SIGFPE crash
- Given `scripts/test-all.sh` exists, when executed, then all suites pass
- Given `.bun-version` contains 1.3.11, when CI runs, then `oven-sh/setup-bun` installs the correct version
- Given bunfig.toml comment says "Bun <=1.3.X", when reading, then the version range matches the actual affected versions (1.3.5 and 1.3.6)

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- infrastructure/tooling verification and issue closure.

## Files to Modify

| File | Change |
|---|---|
| `bunfig.toml` | Update FPE comment version range from "<=1.3.5" to "<=1.3.6" if confirmed |
| `.bun-version` | Update to newer version if one exists and is stable |

## References

- GitHub issue: [#1511](https://github.com/jikig-ai/soleur/issues/1511)
- Draft PR: [#1527](https://github.com/jikig-ai/soleur/pull/1527)
- Prior fix: [#860](https://github.com/jikig-ai/soleur/issues/860) (version pin + sequential runner)
- Prior fix: [#1517](https://github.com/jikig-ai/soleur/pull/1517) (dual-runner exclusion)
- Prior plan: `knowledge-base/project/plans/2026-03-20-fix-bun-test-fpe-root-directory-plan.md`
- Learning: `knowledge-base/project/learnings/2026-03-20-bun-fpe-spawn-count-sensitivity.md`
- Learning: `knowledge-base/project/learnings/test-failures/2026-04-05-bun-test-dom-failures-dual-runner-exclusion.md`
- Upstream: [oven-sh/bun#20429](https://github.com/oven-sh/bun/issues/20429) (FPE during GC, labeled `old-version`)
- Bun crash report: [bun.report](https://bun.report/1.3.6/lt1d530ed9CgkggC+ypRs4/2iF41n3iF+tlmiF8+vyiFm40yiF+impvEmqlnB2muqCA5A8n2wjE)
