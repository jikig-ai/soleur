---
title: bun-test "killed N dangling process" misattributes the source file alphabetically
category: test-failures
module: plugins/soleur/test
date: 2026-05-20
issue: 4112
pr: 4120
tags: [bun-test, cross-file-flakes, subprocess-zombies, hook-timeout, eleventy]
---

# bun-test "killed N dangling process" misattributes the source file alphabetically

## Problem

Three plugin tests appeared as 3 distinct flakes in issue #4112:

- `marketing-content-drift.test.ts` — `beforeEach/afterEach hook timed out [5005ms]`
- `jsonld-escaping.test.ts` — `beforeEach/afterEach hook timed out [8682ms]`
- `github-stats-data.test.ts` — emits `[githubStats.js] GitHub API failed,
  using fallback: network down` then dangles ~180s before being killed

Three different files, three different stack traces, three different "root
causes" in the v1 plan (`Promise.reject` rewrite, AbortController in
`github.js`, etc.).

## Pairwise Repro (the corrective measurement)

```bash
# In isolation
$ bun test plugins/soleur/test/github-stats-data.test.ts
 7 pass, 0 fail, 262ms  # ← INNOCENT

$ bun test plugins/soleur/test/marketing-content-drift.test.ts
 0 pass, 1 fail [5005ms]
 killed 1 dangling process  # the npm subprocess

$ bun test plugins/soleur/test/jsonld-escaping.test.ts
 0 pass, 1 fail [6386ms]
 killed 1 dangling process  # the npx subprocess

# Combined (discovery order = alphabetical: g, j, m)
$ bun test github-stats-data.test.ts jsonld-escaping.test.ts marketing-content-drift.test.ts
 7 pass + 1 fail (marketing) + 0 pass (jsonld blocked); two
 "killed 1 dangling process" warnings ascribed to the file that
 BEGINS the new spawn (not the file that left the zombie).
```

## Root Cause

bun runs every `*.test.ts` file in a SINGLE OS process
(`2026-04-18-bun-test-env-var-leak-across-files-single-process.md`). When
a `beforeAll` hook in file N timeouts and bun kills file N's child
subprocess (e.g., `npm run docs:build`, `npx @11ty/eleventy`), the kill
event isn't always reported under file N — bun's reporter often
attributes the `killed N dangling process` line to the NEXT file (file
N+1) that begins to spawn its own subprocesses.

Combined with the default 5000ms hook timeout vs. Eleventy subprocess
startup of 3.2-6.5s, this produces a misleading symptom chain:

1. `marketing-content-drift.test.ts` `beforeAll` hits 5s timeout on
   `npm run docs:build` (full Eleventy + `_data/github.js` fetch)
2. bun kills the npm child, but reports the kill against the NEXT file
3. CI users see "github-stats-data dangles 180s" when github-stats-data
   never actually misbehaved

## Solution

Three plausible fixes were reduced to ONE root-cause fix:

1. **Primary (load-bearing):** raise the `beforeAll` timeout to `30_000`
   ms on both Eleventy-spawning tests via bun-types' documented
   `HookOptions = number | { timeout?: number }` API. Precedent: PR
   #4097 used `30_000` six times in
   `plugins/soleur/test/skill-security-scan.test.ts:196,204,219,237,273,368`.

2. **Defense-in-depth:** add `AbortController` + `FETCH_TIMEOUT_MS = 5000`
   to `plugins/soleur/docs/_data/github.js` so a slow GitHub Releases
   endpoint cannot push the docs:build past the new 30s ceiling.
   Verbatim mirror of `githubStats.js:30-67`.

3. **No change to `github-stats-data.test.ts`** — innocent in isolation.

## Key Insight

When bun-test reports a `killed N dangling process` warning, the file
the warning is attributed to is NOT necessarily the file whose hook
left the zombie. Pairwise / standalone repro is the diagnostic — never
trust the per-file attribution in the combined-suite output.

The same single-process model that makes `bun test` fast also makes
its subprocess-cleanup attribution unreliable across file boundaries.

## Prevention

- **Diagnostic gate:** When a bun-test suite shows `killed N dangling
  process` warnings, run each accused test file in isolation
  (`bun test <file>`) before believing the attribution. An isolated
  PASS in 262ms exonerates the file.

- **Plan-time gate:** For multi-test-flake issues that look like 3
  distinct root causes, run pairwise repro in the deepen-plan phase
  before committing to 3 different fixes. The 2026-04-18 single-process
  learning is the upstream prior; this learning extends it to
  subprocess-cleanup attribution.

- **Bun-test mislabel:** When a `beforeAll` hits its timeout, bun
  reports `beforeEach/afterEach hook timed out for this test`. Search
  for BOTH strings when debugging. The mislabel is documented inline
  on both fixed files via 3-line comments.

## Session Errors

1. **Plan subagent: `Task` delegation tool unavailable** — The
   deepen-plan subagent was instructed to spawn parallel review
   agents via `Task` but the tool was not loadable in the subagent
   context (only `TaskCreate` was available). Recovery: fell back to
   single ultrathink pass with live grep/repro verification — the
   plan's CLI-verification section captured the empirical evidence
   that would have been distributed across multiple agents.
   Prevention: pipeline planners should not assume `Task` tool
   availability in subagents; design fan-out instructions with an
   explicit single-agent ultrathink fallback path.

2. **Plan AC referenced `bun.lockb` but project uses `bun.lock`** —
   AC7 said `git diff --stat package.json bun.lockb`; first run
   produced `fatal: bun.lockb: no such path in the working tree`.
   Recovery: re-ran with `bun.lock`; no deps changed either way so
   the AC was satisfied. Prevention: ACs that hard-code lockfile
   names should grep `git ls-files | grep -E '(bun|package|yarn|pnpm).*lock'`
   in the deepen phase to pick the actual lockfile name.

3. **Full `bash scripts/test-all.sh` surfaced 9 pre-existing
   `apps/web-platform/` failures outside #4112 scope** — Plan's
   exit gate was `TEST_GROUP=bun` (the bun shard only); work
   skill's Phase 2 exit gate runs the full `test-all.sh`. The
   broader gate caught failures the plan didn't enumerate.
   Recovery: filed #4128 with structural-impossibility evidence
   (`git diff origin/main...HEAD -- apps/web-platform | wc -l` → 0).
   Prevention: plans whose AC exit gate is a CI shard should note
   that the work skill's exit gate is broader, and pre-classify
   any not-in-shard failures as `pre-existing-unrelated` when the
   diff structurally cannot have caused them.

## Related Learnings

- `2026-04-18-bun-test-env-var-leak-across-files-single-process.md` —
  upstream prior: bun runs all `*.test.ts` files in one OS process,
  causing env-var stubs in one file to leak into siblings. This
  learning extends the single-process model to subprocess-cleanup
  attribution.
- `2026-04-22-vitest-cross-file-leaks-and-module-scope-stubs.md` —
  vitest's analogous cross-file-leak class (different runner, same
  root-cause family: shared module-scope state).
- PR #4097 — precedent for `30_000` numeric third-arg on bun
  `HookOptions` for subprocess-spawning hooks.
