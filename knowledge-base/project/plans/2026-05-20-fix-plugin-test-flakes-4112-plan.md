---
title: "fix(test): 3 pre-existing plugin-test flakes (marketing-content-drift, jsonld-escaping, github-stats-data)"
type: fix
date: 2026-05-20
issue: 4112
branch: feat-one-shot-plugin-test-flakes-4112
lane: single-domain
---

# fix(test): 3 pre-existing plugin-test flakes

Closes #4112

## Enhancement Summary

**Deepened on:** 2026-05-20
**Sections enhanced:** Overview, Research Reconciliation, Files to
Edit, Acceptance Criteria, Risks, Implementation Phases.
**Verification performed:**

- Live repro of all three failure modes in pairwise and isolated
  invocations (see Research Reconciliation table).
- `bun-types@1.3.14` `test.d.ts` line 308 / 325 inspected to confirm
  `beforeAll(fn, options?: HookOptions)` with
  `HookOptions = number | { timeout?: number }` accepts a numeric
  third arg as the hook timeout in ms.
- PR #4097 precedent verified live: `30_000` third-arg form used in
  `plugins/soleur/test/skill-security-scan.test.ts:196, 204, 219,
  237, 273, 368` for `test.each` per-test timeouts. The same
  HookOptions API applies to `beforeAll` per bun-types.
- `_data/github.js` is exercised by the docs build because
  `plugins/soleur/docs/pages/changelog.njk:18` reads
  `{{ changelog.html | safe }}` and the `changelog` data file is
  `_data/github.js` (Eleventy convention: data file name == template
  key).
- `gh pr view 4097` confirmed `state=MERGED`,
  `mergeCommit.oid=4ecac082...`.

### Key Corrections vs. v1

1. **Root cause is simpler than v1 claimed.** The "dangling timer in
   `githubStats.js`" hypothesis was wrong — verified by running
   `bun test plugins/soleur/test/github-stats-data.test.ts` in
   isolation: 7/7 pass, 262 ms, no "killed N dangling process"
   warning. The dangling-process line in the issue body comes from
   bun killing the `npm run docs:build` / `npx @11ty/eleventy` child
   process when *another* test file's `beforeAll` hits the 5000 ms
   default timeout. The proximate cause for all three observed
   symptoms is one defect: **default 5000 ms hook timeout vs. Eleventy
   subprocess startup of ~3.2–6.5 s**.
2. **github-stats-data is innocent in isolation.** The issue body's
   "dangles ~180s before being killed" is the WHOLE-SUITE behaviour
   when an upstream file's hook timeout leaves npm/`npx` zombies that
   bun reports against the next file in alphabetical order
   (`github-stats-data` < `jsonld-escaping` < `marketing-...`). No
   change to `github-stats-data.test.ts` is required.
3. **`_data/github.js` AbortController fix is preventive, not
   proximate.** The proximate timeout cause is Eleventy's own
   startup latency, not the GitHub Releases fetch. The fetch IS
   unbounded today (`github.js:20`, no `signal` parameter), which is
   a latent flake risk — fixing it is still in scope, but as
   defense-in-depth, not as the load-bearing fix.

## Overview

`bash scripts/test-all.sh` runs `bun test plugins/soleur/` as one
suite (see `scripts/test-all.sh:157`). Inside that suite three test
files intermittently fail with symptoms surfaced during `/ship`
Phase 4 on PR #4097:

- `plugins/soleur/test/marketing-content-drift.test.ts` —
  `beforeAll` runs `Bun.spawn(["npm", "run", "docs:build"])` (the
  full Eleventy site build, ~10 s when cold including `npx`
  resolution and `_data/github.js` releases fetch). Hits the
  default 5000 ms hook timeout. Bun's reporter labels the failure
  `a beforeEach/afterEach hook timed out for this test` (mislabel
  for `beforeAll`).
- `plugins/soleur/test/jsonld-escaping.test.ts` — `beforeAll` runs
  `Bun.spawnSync(["npx", "@11ty/eleventy", ...])` on a self-contained
  fixture. Measured 3.2 s standalone (`time npx @11ty/eleventy
  --config=plugins/soleur/test/fixtures/jsonld-escaping/eleventy
  .config.js --output=/tmp/...`), but inside bun's test harness the
  child runtime sits around 6.4 s. Hits the default 5000 ms hook
  timeout.
- `plugins/soleur/test/github-stats-data.test.ts` — `7/7 pass,
  ~262 ms` in isolation. The "dangling process / ~180 s hang" in the
  issue body is bun killing the *upstream* file's `npm`/`npx` child
  process when its hook timed out; the warning is reported against
  the next file in the discovery order.

### Verified pairwise repro (this worktree, 2026-05-20)

```bash
$ bun test plugins/soleur/test/github-stats-data.test.ts
 7 pass, 0 fail, 262.00ms  # innocent in isolation

$ bun test plugins/soleur/test/marketing-content-drift.test.ts
 0 pass, 1 fail, beforeEach/afterEach hook timed out [5005.94ms]
 killed 1 dangling process  # the npm subprocess

$ bun test plugins/soleur/test/jsonld-escaping.test.ts
 0 pass, 1 fail, beforeEach/afterEach hook timed out [6386.93ms]
 killed 1 dangling process  # the npx subprocess

$ bun test plugins/soleur/test/github-stats-data.test.ts \
           plugins/soleur/test/marketing-content-drift.test.ts \
           plugins/soleur/test/jsonld-escaping.test.ts
 7 pass + 1 fail (marketing) + 0 pass (jsonld blocked); two
 "killed 1 dangling process" warnings ascribed to the file that
 BEGINS the new spawn (not the file that left the zombie).
```

### Fix

1. **Primary (load-bearing):** raise the per-hook timeout to
   `30_000` ms on `beforeAll` in both Eleventy-spawning tests:
   - `plugins/soleur/test/marketing-content-drift.test.ts` line 62.
   - `plugins/soleur/test/jsonld-escaping.test.ts` line 20.

2. **Defense-in-depth (preventive):** add `AbortController` +
   `FETCH_TIMEOUT_MS = 5000` to `plugins/soleur/docs/_data/github.js`
   so a slow GitHub Releases endpoint cannot push the docs:build past
   the new 30 s ceiling. Mirror of the pattern already in
   `githubStats.js:30-67` and `communityStats.js:24-46`.

3. **No change to `github-stats-data.test.ts`.** The file passes in
   isolation and the v1 plan's "rewrite throw to Promise.reject"
   change had no measurable effect on the dangling-process warning
   in repro (warning comes from the npm/npx subprocess of the
   neighboring file, not from the AbortController timer).

## User-Brand Impact

**If this lands broken, the user experiences:** intermittent red
checks on `bun test plugins/soleur/` in CI — non-user-facing test
infrastructure. The plugin marketplace install path is unaffected;
the Eleventy docs site builds use the same `github.js` codepath but
operator-side build failures degrade to "version: null" via the
existing fallback (`github.js:31-33`).
**If this leaks, the user's [data / workflow / money] is exposed
via:** N/A — no regulated data on the test path; `github.js` reads a
public Releases endpoint with optional `GITHUB_TOKEN`.
**Brand-survival threshold:** none — internal CI hygiene only.

## Research Reconciliation — Spec vs. Codebase

| Spec claim                                | Reality                                                          | Plan response                              |
|-------------------------------------------|------------------------------------------------------------------|--------------------------------------------|
| `beforeEach`/`afterEach` hook timeout     | Both files use `beforeAll`; bun mislabels the error.             | Raise `beforeAll` timeout; document quirk. |
| github-stats hangs ~180 s                 | github-stats passes in 262 ms in isolation; hang is cross-file.  | No change to github-stats; fix upstream.   |
| Three different root causes               | One root cause: default 5 s hook timeout vs. ~3–10 s build.      | One numeric edit per Eleventy-spawn site.  |
| Dangling fetch / AbortController in test  | `githubStats.js` already clears its timer in `finally`.          | Drop the v1 "Promise.reject" AC.           |
| `github.js` unbounded fetch is the cause  | `github.js` IS unbounded, but the Eleventy startup is ~3 s pure. | Keep the fix as defense-in-depth.          |

## Files to Edit

- `plugins/soleur/test/marketing-content-drift.test.ts:62-77` —
  change `beforeAll(async () => { ... });` to
  `beforeAll(async () => { ... }, 30_000);` per `bun-types@1.3.14`
  `test.d.ts:308 + 325`. Add an inline comment citing PR #4097's
  `30_000` precedent and the Eleventy build timing rationale.

- `plugins/soleur/test/jsonld-escaping.test.ts:20-33` — same:
  third-arg `30_000` on `beforeAll`. Same comment.

- `plugins/soleur/docs/_data/github.js` — wrap the existing `fetch
  (RELEASES_URL, { headers })` in an `AbortController + setTimeout +
  clearTimeout-in-finally` pattern. Verbatim port of
  `githubStats.js:30-67`. Constant `FETCH_TIMEOUT_MS = 5000`.

## Files NOT to Edit (vs. v1 plan)

- `plugins/soleur/test/github-stats-data.test.ts` — passes in
  isolation; the v1 plan's `Promise.reject(...)` rewrite was based
  on a misattribution of the dangling-process warning. Verified by
  pairwise repro 2026-05-20.

## Open Code-Review Overlap

Ran 2026-05-20:

```bash
gh issue list --label code-review --state open --json number,title,body \
  --limit 200 > /tmp/open-review-issues.json
for p in plugins/soleur/docs/_data/github.js \
         plugins/soleur/test/marketing-content-drift.test.ts \
         plugins/soleur/test/jsonld-escaping.test.ts; do
  jq -r --arg path "$p" '.[] | select(.body // "" | contains($path))
    | "#\(.number): \(.title)"' /tmp/open-review-issues.json
done
```

Result: **None**. No open code-review scope-outs touch these files.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1: Eleventy-spawning hooks have 30 s timeout.** Both files
  pass:
  - `grep -nE ', 30_000\)' plugins/soleur/test/marketing-content-
    drift.test.ts` returns exactly 1 line and that line is the
    closing of the file's only `beforeAll`.
  - Same for `plugins/soleur/test/jsonld-escaping.test.ts`.
- [ ] **AC2: `github.js` has bounded fetch.**
  `grep -nE 'AbortController|FETCH_TIMEOUT_MS|signal:'
  plugins/soleur/docs/_data/github.js` returns ≥3 matches (controller
  construction, timeout constant, signal pass-through). The constant
  value is `5000` to match `githubStats.js:6` and `communityStats.js:15`.
- [ ] **AC3: Repro command exits 0.** Run

  ```bash
  bun test plugins/soleur/test/github-stats-data.test.ts \
           plugins/soleur/test/jsonld-escaping.test.ts \
           plugins/soleur/test/marketing-content-drift.test.ts
  ```

  Exit code MUST be 0; stderr MUST NOT contain `beforeEach/afterEach
  hook timed out`. (The `killed N dangling process` line may still
  appear under future bun versions if a test forgets to await a
  spawn — but it MUST NOT co-occur with a hook timeout, which is the
  user-visible failure.)
- [ ] **AC4: Each file passes in isolation.** Three separate `bun
  test <file>` invocations each exit 0.
- [ ] **AC5: Full plugin suite passes.** `bun test plugins/soleur/`
  exits 0 in ≤120 s. Capture timing in PR body.
- [ ] **AC6: CI bun-shard passes.** `TEST_GROUP=bun bash
  scripts/test-all.sh` exits 0 (the exact CI form — see
  `scripts/test-all.sh:128-159`).
- [ ] **AC7: No new dependencies.** `git diff --stat package.json
  bun.lockb` returns empty.
- [ ] **AC8: PR body uses `Closes #4112`** (per
  `wg-use-closes-n-in-pr-body-not-title-to`).

### Post-merge (operator)

None. The fix is pure code; the next `bun test` run on `main` will
exercise it.

## Test Strategy

No new test files. The drift-guard is the AC3 repro itself: if the
third-arg `30_000` is removed from either edited file, the same
`bun test ...` invocation regresses to the 5 s timeout failure.
If the `github.js` AbortController is removed but the test guards
stay, AC3 still passes locally (Eleventy build ≪ 30 s on healthy
network); CI catches the regression because the existing
`if (process.env.CI) throw` branch in `github.js:28-30` will fire
on the next slow-fetch event. That branch is unchanged.

**Why not lower-bound the timeout to 15 s instead of 30 s?** Two
reasons:

1. 30 s is the project convention from PR #4097 for
   subprocess-spawning bun tests (verified at
   `plugins/soleur/test/skill-security-scan.test.ts:196` and 5
   other sites).
2. The marketing-content-drift `beforeAll` runs the FULL docs:build
   including all `_data` files (github.js, githubStats.js,
   communityStats.js, blogRedirects.js, skills.js, agents.js, etc.).
   Real GitHub API + Discord API round-trips combined can push the
   build to 8–12 s on cold cache; 15 s would leave thin margin.
   30 s leaves CI-runner headroom without masking a true regression
   (`scripts/test-all.sh` is itself wall-clocked by the GitHub
   Actions job-level `timeout-minutes`).

## Risks & Sharp Edges

- **Risk: 30 s timeout masks a slower regression.** Mitigation: the
  CI runner has its own job-level `timeout-minutes`; a regression
  cannot hide indefinitely. Per `wg-when-tests-fail-and-are-
  confirmed-pre`, the threshold matches PR #4097's precedent — 30 s
  is the project convention, not a one-off.

- **Risk: `github.js` abort masks a real CI flake.** A real abort
  would replicate the existing CI fail-fast contract on
  `githubStats.js:52-53` (`if (process.env.CI) throw ...`). Dev mode
  (CI unset) keeps the existing `console.warn` + `{ version: null,
  changelog: { html: "" } }` fallback. No behaviour change for
  successful fetches.

- **Sharp Edge: bun-test mislabels `beforeAll` timeout as
  `beforeEach/afterEach`.** Documented inline in both edited test
  files. Future debuggers searching for the error string will land
  on the code comment first.

- **Sharp Edge: "killed N dangling process" warnings.** These are
  bun's reporter line for any child process that outlives the test
  file. Today they only appear when `Bun.spawn(npm run docs:build)`
  or `Bun.spawnSync(npx @11ty/eleventy)` is killed by a hook
  timeout. After this fix they should not appear because the hook
  has 30 s to await the subprocess cleanly. If a future bun version
  emits the warning under healthy conditions, that's a bun-runtime
  bug, not a test bug — file upstream rather than chasing it in
  these files.

- **Sharp Edge per AGENTS.md:** the plan's `## User-Brand Impact`
  section threshold is `none`. `deepen-plan` Phase 4.6 verified the
  section exists and the threshold is in the allowed enum.

- **Sharp Edge: AC count drift.** v1 plan said "3 throw stubs to
  rewrite"; live grep showed only 2 throw sites
  (`github-stats-data.test.ts:101, 116`). The 401 case at line 127
  returns a `Response`, not a throw. The deepen pass dropped that
  AC entirely (file is innocent); no count to track.

## Domain Review

**Domains relevant:** Engineering only. Single-domain test-
infrastructure fix. CTO/engineering scope.

- **CTO assessment (inline):** Source fix in `github.js` mirrors
  three existing siblings (`githubStats.js`, `communityStats.js`,
  Discord fetch in `communityStats.js`) — pattern is well-
  established. Test fixes use the bun-types-documented `HookOptions`
  third arg, with PR #4097's `30_000` literal as project precedent.

No GDPR-gate trigger. No IaC trigger. No Product/UX trigger.

## Implementation Phases

### Phase 0 — Preconditions

- [ ] Verify worktree is `feat-one-shot-plugin-test-flakes-4112`.
- [ ] `bun --version` ≥ 1.3.11.
- [ ] Repro AC3 command. Capture the before-state output.
- [ ] Read `plugins/soleur/docs/_data/githubStats.js:1-67` and
  `plugins/soleur/docs/_data/communityStats.js:1-50` to internalise
  the mirror pattern.
- [ ] Re-confirm bun-types `HookOptions` signature at
  `~/.bun/install/cache/bun-types@<version>/test.d.ts` (the version
  Bun resolves on this host). Project does not pin `bun-types`
  explicitly; the runtime API is what we depend on.

### Phase 1 — Source fix (`github.js`)

- [ ] Edit `plugins/soleur/docs/_data/github.js`:
  - Add `const FETCH_TIMEOUT_MS = 5000;` near the top, with the
    comment block copied from `githubStats.js:4-5`.
  - Inside the function, before the existing `try { const res =
    await fetch(...) }`:
    - `const controller = new AbortController();`
    - `const timer = setTimeout(() => controller.abort(),
      FETCH_TIMEOUT_MS);`
  - Pass `{ headers, signal: controller.signal }` to `fetch`.
  - Wrap the existing `try { ... } catch { ... }` with `finally
    { clearTimeout(timer); }`.
- [ ] Run `npm run docs:build` — must exit 0.

### Phase 2 — Test hardening (`marketing-content-drift.test.ts`)

- [ ] Change `beforeAll(async () => { ... });` (line 62) to
  `beforeAll(async () => { ... }, 30_000);` with an inline comment.
- [ ] Run `bun test plugins/soleur/test/marketing-content-drift.test.ts`
  — must exit 0.

### Phase 3 — Test hardening (`jsonld-escaping.test.ts`)

- [ ] Same edit at line 20. Same comment.
- [ ] Run `bun test plugins/soleur/test/jsonld-escaping.test.ts` —
  must exit 0.

### Phase 4 — Integration

- [ ] Run AC3 over the three files in discovery order — exit 0, no
  hook-timeout strings.
- [ ] Run AC4: three separate isolated invocations.
- [ ] Run AC5: `bun test plugins/soleur/` — full plugin suite.
- [ ] Run AC6: `TEST_GROUP=bun bash scripts/test-all.sh`.

### Phase 5 — Commit + push + PR

- [ ] One commit:
  `fix(test): raise eleventy beforeAll timeout + bound github.js
  fetch (Closes #4112)`.
- [ ] PR body: AC checklist + before/after repro output + the
  Enhancement Summary's Key Corrections paragraph (root-cause
  diagnosis).

## CLI-verification

- `bun test` per-hook `HookOptions` numeric third arg: verified at
  `~/.bun/install/cache/bun-types@1.3.14@@@1/test.d.ts:308` (`type
  HookOptions = number | { timeout?: number }`) and `:325`
  (`export function beforeAll(fn, options?: HookOptions): void`).
- PR #4097 precedent for `30_000` literal: verified at
  `plugins/soleur/test/skill-security-scan.test.ts:196` (`test.each`
  per-test timeout) — same `HookOptions` API.
- `AbortController` + `setTimeout` + `clearTimeout` pattern:
  verified verbatim against
  `plugins/soleur/docs/_data/githubStats.js:30-67` and
  `plugins/soleur/docs/_data/communityStats.js:24-46`. No novel
  API; the edit is a port.
- `Promise.reject(new Error(...))` was considered but dropped (see
  Key Corrections #2-3); no remaining citations require
  verification.

## Research Insights

- **PR #4097** (`state=MERGED`, `mergeCommit.oid=4ecac082...`)
  established the project convention for hook/test timeouts on
  subprocess-spawning bun tests. The same `30_000` literal is used
  6 times in `skill-security-scan.test.ts` (lines 196, 204, 219,
  237, 273, 368).
- **`bun-types@1.3.14` test.d.ts:308 + :325** is the canonical
  source for the `HookOptions` API used by this fix.
- **`knowledge-base/project/learnings/test-failures/2026-04-18-bun-
  test-env-var-leak-across-files-single-process.md`** documents that
  bun runs all `*.test.ts` files in a single OS process — relevant
  context for understanding why `github-stats-data` was misattributed
  as broken in the issue body (single-process means subprocess
  zombies from one file are killed in the next file's window).
- **`knowledge-base/project/learnings/2026-03-20-bun-fpe-spawn-
  count-sensitivity.md`** explains why `scripts/test-all.sh` runs
  `bun test plugins/soleur/` as one shard.
- **Constitution `cq-abort-signal-timeout-vs-fake-timers`** is the
  canonical reference for the manual `AbortController + setTimeout`
  pattern.

## Quality Checks (deepen-plan SKILL.md checklist)

- [x] Every cited PR is live-verified: `gh pr view 4097` → MERGED,
  oid `4ecac082...`.
- [x] Every claim about SDK semantics cites the verbatim type-def
  file (`bun-types@1.3.14/test.d.ts:308,325`).
- [x] All rule-ID citations verified active: `wg-use-closes-n-in-pr-
  body-not-title-to`, `wg-when-tests-fail-and-are-confirmed-pre`,
  `hr-weigh-every-decision-against-target-user-impact`, `cq-abort-
  signal-timeout-vs-fake-timers`. All present in
  `AGENTS.md` index.
- [x] No GitHub label prescribed in ACs.
- [x] No AGENTS.md rule promotion/demotion in this plan.
- [x] No pathspec→regex translation in ACs.
- [x] No vendor base-image migration.
- [x] No multi-clause SQL predicate in ACs.
- [x] No `set -m` / process-group / signal-trap semantics in ACs.
- [x] No SHA pin proposed.
- [x] No new git-log AND-vs-OR semantics in ACs (single repro
  command, not a co-change invariant).
- [x] Source-grep counts cross-checked: 2 `throw new Error` sites in
  `github-stats-data.test.ts` (was claimed 3 in v1; corrected to 0
  since the file is now out of scope).
- [x] AC verification greps tested against the post-fix expected
  output: AC1 `, 30_000\)` matches the new line, AC2 matches the
  ported AbortController block.
