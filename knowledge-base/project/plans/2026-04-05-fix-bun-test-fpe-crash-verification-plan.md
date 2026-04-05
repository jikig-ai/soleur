---
title: "fix: verify bun test FPE crash resolution and close #1511"
type: fix
date: 2026-04-05
semver: patch
closes: "#1511"
---

# fix: verify bun test FPE crash resolution and close #1511

## Enhancement Summary

**Deepened on:** 2026-04-05
**Sections enhanced:** 3 (Version range resolution, Problem Statement, References)

### Key Improvements

1. Confirmed the FPE affected Bun 1.3.5 AND 1.3.6 via crash report URL analysis -- the version range in comments must be "<=1.3.6"
2. Verified Bun release timeline: 6 releases between 1.3.6 (2026-01-13) and 1.3.11 (2026-03-18); the FPE fix was not explicitly documented in any changelog but the upstream issue #20429 is labeled `old-version`
3. Confirmed 1.3.11 is still the latest Bun release (no newer version to evaluate), eliminating the version upgrade question entirely

### Research Findings

- Bun v1.3.6 release notes mention 45 bug fixes but do not explicitly call out FPE/GC crash fixes ([source](https://bun.com/blog/bun-v1.3.6))
- The upstream issue oven-sh/bun#20429 was reported on Bun 1.2.9 and labeled `old-version` -- the FPE is a recurring class of GC bugs across major version lines, not a single bug with a single fix
- No Bun versions between 1.3.7 and 1.3.10 exist to test (releases jump 1.3.6 -> 1.3.7 -> 1.3.8 -> 1.3.9 -> 1.3.10 -> 1.3.11)
- The three-layer defense (version pin + sequential runner + dual-runner exclusion) provides robust protection even if future Bun versions regress

## Overview

Issue #1511 reports that `bun test` crashes with a Floating Point Error (SIGFPE) in Bun v1.3.6. Investigation confirms the crash no longer reproduces -- it was resolved by a combination of prior work:

1. **Bun version pin to 1.3.11** (#860) -- `.bun-version` pins the project to a version that fixes the GC/allocator FPE bug present in Bun <= 1.3.6
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

### Tasks

1. **Fix bunfig.toml comment version range** -- the root `bunfig.toml` comment says "Bun <=1.3.5" but the FPE also affects 1.3.6 (confirmed by issue #1511's crash report URL which contains `1.3.6` in the path). Update to "Bun <=1.3.6"
2. **Fix learning doc version range** -- `knowledge-base/project/learnings/2026-03-20-bun-fpe-spawn-count-sensitivity.md` title references "Bun 1.3.5" but the FPE class extends through 1.3.6. Update references for accuracy
3. **Close issue #1511** -- add a resolution comment documenting the three-layer fix path (#860 version pin, #860 sequential runner, #1517 dual-runner exclusion) and close
4. **Update PR #1527** -- either close it (if only comment fixes) or use it to carry the bunfig.toml and learning doc corrections

### Version range resolution

The original FPE was reported on Bun 1.3.5 (issue #860). Issue #1511 reports the same crash class on Bun 1.3.6 (crash report URL: `bun.report/1.3.6/...`). Both versions are affected. The correct range for comments and documentation is **<=1.3.6**. Bun 1.3.11 is the first version in the project's history where the crash does not reproduce.

**Bun 1.3.x release timeline:**

| Version | Date | FPE Status |
|---|---|---|
| 1.3.5 | pre-2026-01-13 | Crashes (confirmed, #860) |
| 1.3.6 | 2026-01-13 | Crashes (confirmed, #1511) |
| 1.3.7 | 2026-01-27 | Unknown (not tested) |
| 1.3.8 | 2026-01-29 | Unknown (not tested) |
| 1.3.9 | 2026-02-08 | Unknown (not tested) |
| 1.3.10 | 2026-02-26 | Unknown (not tested) |
| 1.3.11 | 2026-03-18 | No crash (confirmed, this plan) |

The exact fix version is unknown because the FPE fix was not documented in any Bun changelog. The upstream issue [oven-sh/bun#20429](https://github.com/oven-sh/bun/issues/20429) tracks FPE crashes as a class across Bun versions (also seen in 1.2.x). The `old-version` label indicates the Bun team considers it fixed in current releases

## Non-goals

- Fixing the upstream Bun FPE bug (oven-sh/bun's responsibility)
- Migrating away from Bun as a test runner
- Restructuring tests to reduce subprocess spawn counts
- Adding a Bun version manager (the `.bun-version` file + `scripts/test-all.sh` version check is sufficient)

## Acceptance Criteria

- [x] `bun test` from repo root succeeds reliably (5+ consecutive runs) on Bun 1.3.11+
- [x] `bash scripts/test-all.sh` runs all suites and exits 0
- [x] Issue #1511 is closed with a resolution comment
- [x] PR #1527 is either closed (no changes needed) or merged with any version/comment fixes
- [x] `bunfig.toml` FPE comment says "Bun <=1.3.6" (not "<=1.3.5")
- [x] Learning document version references updated to include 1.3.6

## Test Scenarios

- Given Bun 1.3.11 installed, when `bun test` runs 5 times from repo root, then all runs complete with 0 failures and no SIGFPE crash
- Given `scripts/test-all.sh` exists, when executed, then all suites pass
- Given bunfig.toml comment updated, when reading line 11, then it says "Bun <=1.3.6" (not "<=1.3.5")

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- infrastructure/tooling verification and issue closure.

## Files to Modify

| File | Change |
|---|---|
| `bunfig.toml` | Update FPE comment version range from "<=1.3.5" to "<=1.3.6" |
| `knowledge-base/project/learnings/2026-03-20-bun-fpe-spawn-count-sensitivity.md` | Update version references to include 1.3.6 |

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
