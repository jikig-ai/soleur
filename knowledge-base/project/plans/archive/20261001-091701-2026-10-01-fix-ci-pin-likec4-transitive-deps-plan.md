---
title: "ci: likec4 global install fails on npm CDN lag for freshly published transitive deps"
type: fix
date: 2026-10-01
slug: fix-ci-pin-likec4-transitive-deps
branch: feat-one-shot-9300-likec4-pin-transitive-deps
issue: 9300
closes: 9300
priority: p2-medium
domain: engineering
brand_survival_threshold: none
---

## Enhancement Summary

**Deepened on:** 2026-10-01
**Method:** deepen-plan halt gates run mechanically, plus the plan-review panel (DHH, Kieran, code-simplicity, CTO devex) and a learnings search. Broad skill and agent fan-out was not run: the change is CI-flag scoped and every load-bearing claim was already measured locally (see Research Insights).

### Gates (all passed)

- 4.6 User-Brand Impact present, threshold `none`, scope-out line present; the touched paths are not in the sensitive-path regex.
- 4.7 Observability: all five fields populated, `discoverability_test.command` is a single `grep` (allowlisted verb, no shell-active characters, finishes well inside 15 s), `expected_output` is the literal `3`.
- 4.8 no PAT-shaped variables. 4.5, 4.9, 4.10 not triggered (no network-outage terms, no UI surface, no store or connection). 4.11 `scripts/lint-guard-contract.py` passes (1 guard, 6-row matrix).
- Citations: both cited rule ids resolve to active rules; ADR-191 and ADR-235 exist; every `knowledge-base/` path resolves; the only issue number cited is #9300.

### Key improvements over the first draft

1. The `npx` render sites are in scope, backed by a measured npm-cache coupling (a `--before` install followed by an unpinned `npx` fetches the incident tarball from the network).
2. The guard scans comment-stripped lines and shares one `checkLikec4Pins` between the real-file test and the self-test; the date gets an offline 3-day age floor.
3. The lockfile route is rejected on measurement (5 of 15 real-bwrap tests fail on the hoisted layout), and the learnings search independently confirms that sandbox bind fragility.

### New considerations from review and learnings

- `ci.yml` prose already quotes `npm install -g likec4@1.50.0`, so an unstripped scan would count four sites; the AC greps are anchored on the full install command.
- A private registry mirror that omits per-version publish times makes `--before` fail with `ETARGET`; documented in the `BUMPING LIKEC4` header and in User-Brand Impact.
- The Dockerfile asymmetry is a recorded Taste decision, not an oversight (`decision-challenges.md`).
- Learnings applied: `2026-09-24-sandboxing-a-render-child-with-bwrap-no-writable-host-bind.md` (layout-sensitive binds), `2026-05-29-canonical-constant-flip-must-grep-consumers-that-assert-old-value.md` (grep asserting consumers: the remaining `likec4@1.50.0` literals outside the edit set are comments, doc recipes asserted by the version-pin test, and `.npmrc` prose), `2026-06-29-c4-source-edit-requires-regenerate-model-json-orphan-suite.md` (freshness suite is only reached by the full battery, so Phase 3 runs it explicitly).

# ci: pin the whole likec4 dependency tree, not just the top-level package (#9300)

## Overview

Every CI step that installs the likec4 CLI runs `npm install -g likec4@1.50.0`. That pins one
package; its ~190-node transitive tree resolves to the newest releases at run time, and npm's CDN can
serve a 404 for a tarball published minutes earlier. On 2026-09-30 two consecutive attempts of CI run
36726970979 died on `source-map-js-1.2.2.tgz` and then `electron-to-chromium-1.5.443.tgz`, each taking
out 12 shards and the required `test` context with them.

The fix is to resolve the tree as of a fixed past date (`--before=<date>`), applied uniformly to
every place that resolves likec4's tree in CI: the four `Install likec4 CLI` steps **and** the two
plugin-owned `npx -y likec4@<v>` call sites that run inside the same test shards. The version pin and
the date are a pair; a parity guard keeps every site on the same pair as the Dockerfile and
`package.json` version.

**Chosen mechanism: `--before=2026-09-28` (not a committed lockfile).** Measured, not assumed; see
Research Insights. Short version: a lockfile in a tools package hoists likec4's deps into sibling
`node_modules/*` directories, and `server/c4-render.ts` only binds `dirname(dirname(entry))` (the
likec4 package directory) into its bwrap sandbox, so 5 of the 15 `c4-render-tenant-config` tests fail
(real-binary, real-bwrap run, 2026-10-01). A lockfile also cannot be consumed by the `npx` call sites.
`--before` keeps the global install layout the sandbox depends on (15/15 pass) and works for both
`npm install -g` and `npx`.

## Research Insights

### Premise Validation (Phase 0.6)

- #9300 is OPEN, no closing PR (`gh issue view 9300 --json state,closedByPullRequestsReferences`).
- Cited surfaces exist on the branch: the three `npm install -g likec4@1.50.0` steps in
  `.github/workflows/ci.yml` (jobs `test-webplat`, `test-scripts`, `test-scripts-heavy`), the one in
  `.github/workflows/main-health-monitor.yml`, and `apps/web-platform/Dockerfile`.
- **The issue's premise is incomplete in one respect.** It describes only the global-install step.
  `plugins/soleur/scripts/render-c4-model.sh` and `plugins/soleur/scripts/generate-c4-from-components.ts`
  both run `npx -y --ignore-scripts likec4@1.50.0 ...` at test time (c4-model-freshness,
  render-c4-model.test.sh, c4-from-components.test.sh). `ci.yml` itself says the global install is not
  reused by `npx` as an installation. It IS reused as a download cache, and that is measured
  (2026-10-01, `--loglevel http`, clean cache): an unpinned global install followed by an unpinned
  `npx` fetches 0 tarballs from the network (125 of 125 cache hits). A `--before` install followed by
  an unpinned `npx` fetches exactly four from the network: `browserslist-4.29.3`,
  `caniuse-lite-1.0.30001814`, `electron-to-chromium-1.5.443` and `source-map-js-1.2.2` - the very
  tarball that 404'd in the incident, plus its siblings. So pinning only the install step would move
  the exposure onto the `npx` call and leave the flake in place. The `npx` sites are in scope.
- ADR corpus grep (`likec4`, `--before`): ADR-191 records the global exact pin and the root `.npmrc`
  exemption (`min-release-age` applies to exact pins). No ADR rejected `--before`. `before` wins over
  `min-release-age` when both are set in one source (npm config definitions), so a project `.npmrc`
  floor cannot conflict.

### Property List (Phase 0.6b)

1. A freshly published transitive tarball can never be requested by a CI likec4 install or `npx`.
2. The set of transitive versions is the same on every run (deterministic), so the byte-diff in
   `c4-model-freshness` cannot flip on a transitive bump.
3. The CLI layout under CI still matches what the bwrap sandbox binds (global `lib/node_modules/likec4`).
4. The version and date pins cannot drift between sites, or from the Dockerfile/`package.json` version.
5. A version bump that forgets the date fails loudly, not silently.

### Cut List (Phase 0.6b)

- Committed lockfile + `npm ci` in a tools package -> property 2 (already bought by `--before`); breaks
  property 3 (measured 5/15 failures) and cannot cover `npx` sites; needs a fifth entry in
  `lockfile-sync` and the install-site lint. Rejected.
- `npm-shrinkwrap.json` injected into a repacked likec4 tarball -> same property as the lockfile, plus a
  repack procedure to maintain. Rejected.
- Retry loop around the install -> a 404 on a tarball older than the cutoff cannot be lag; nothing to
  retry. Cut.
- `--ignore-scripts` on the global installs -> unrelated to #9300 (the `npx` sites already pass it).
  Measured to work, but it is a separate hardening change. Cut; not bundled.
- Date as a workflow-level `env:` variable -> the monitor's own comment records that the guard regex
  needs literals. Inline literal + parity test instead.
- `NPM_CONFIG_BEFORE` as a job-level env var -> would silently cap every other npm resolution in the
  shard (fixtures, other pins). Rejected in favour of explicit flags.
- Removing the install steps from `test-scripts`/`test-scripts-heavy` (no suite there was found
  resolving `likec4` from PATH; the renderer uses `npx`) -> plausible, but it also removes the cache
  warm-up measured above, and `scripts-shard-runtime-coverage.test.sh` asserts the install step exists
  wherever a suite mentions `likec4`; changing that contract is out of scope. Noted for the deferral
  issue.

### Measured (2026-10-01, local, npm 11.19.1 and npm 10.9.2)

| Check | Result |
|---|---|
| likec4@1.50.0 publish time | `2026-02-21T16:54:35Z` |
| Tree resolved today vs `--before=2026-09-28` | 190 nodes; 5 differ: `electron-to-chromium` 1.5.443 -> 1.5.439, `source-map-js` 1.2.2 -> 1.2.1, `browserslist` 4.29.3 -> 4.29.1, `caniuse-lite` 1.0.30001814 -> 1.0.30001812. Exactly the two tarballs that 404'd are excluded. |
| `npm install -g --before=2026-09-28 likec4@1.50.0` under npm 10.9.2 (CI's bundled npm) | installs, `likec4 --version` = 1.50.0 |
| `npx -y --ignore-scripts --before=2026-09-28 likec4@1.50.0` | honours the flag (`electron-to-chromium` 1.5.439 in the `_npx` tree) |
| `c4-render-tenant-config.test.ts`, real binary + real bwrap, `LIKEC4_REQUIRED=1 C4_BWRAP_REQUIRED=1` | global layout (today's tree): 15/15; global layout (`--before` tree): 15/15; **hoisted lockfile layout: 5 failed / 10 passed** |
| `render-c4-model.sh` with `NPM_CONFIG_BEFORE=2026-09-28` vs committed `model.likec4.json` | byte-identical (83 elements, 177 relations, 85 views) |
| Cache coupling, clean cache each: unpinned `npm i -g` then unpinned `npx` | 125 cache hits, 0 network tarball fetches |
| `--before` `npm i -g` then unpinned `npx` | 125 hits + 4 network fetches (browserslist 4.29.3, caniuse-lite 1.0.30001814, electron-to-chromium 1.5.443, source-map-js 1.2.2) |
| `--before` `npm i -g` then `npx --before` (same date), `--offline` | succeeds, prints `1.50.0` |
| Lockfile route, for the record | `npm ci` of a tools package: 81 hoisted dirs, entry at `node_modules/likec4/bin/likec4.mjs`; `installPrefixBinds` binds only `node_modules/likec4` |

### Institutional context

- ADR-191: `min-release-age=3` is deliberately not applied at the repo root because it applies to
  exact pins; the cutoff date here is chosen >= 3 days old for the same supply-chain stance.
- `c4-likec4-version-pin.test.ts` (existing guard) reads version literals out of the Dockerfile,
  `package.json`, `render-c4-model.sh`, `ci.yml` (matchAll), `main-health-monitor.yml`; its regex
  `npm install -g likec4@([0-9][^\s"'`]*)` stops at whitespace, so appending ` --before=...` does not
  disturb it.
- `scripts-shard-runtime-coverage.test.sh` greps the job block for the substring
  `npm install -g likec4@`; keep that substring intact.
- `ci.yml` is a required-check workflow edited on the untrusted-CI path: not admin-merge eligible.
- Other consumers of `render-c4-model.sh` inherit the pin with no edit of their own: the
  regenerable-conflict resolver, `sync-pr-behind.sh` and the pre-commit regeneration hook all call the
  one renderer (ADR-235).

## Open Code-Review Overlap

None. At plan time, 87 open `code-review` issues were checked (two-stage `gh --json` then `jq --arg`
against every path in Files to Edit); zero reference any of them. Re-run at work time.

## Research Reconciliation — Spec vs. Codebase

| Claim (issue #9300) | Reality | Plan response |
|---|---|---|
| Fix is a `ci.yml` edit; "both options are `.github/workflows/ci.yml` edits" | Four workflow sites (3 in `ci.yml`, 1 in `main-health-monitor.yml`) plus two plugin `npx` sites resolve the same unpinned tree | Edit all six; guard all six |
| "keep it matching the Dockerfile/package.json pin" | Version parity is already guarded; there is no date to match | Extend the guard to the (version, date) pair; Dockerfile keeps the version-only pin (see Non-Goals) |
| "commit a lockfile + `npm ci` in a small tools package" is viable | Breaks the bwrap sandbox binds (5/15 fail) and cannot reach `npx` | `--before`; rationale recorded in the ci.yml comment |

## Implementation Phases

### Phase 1 — Failing guard first (RED)

Extend `apps/web-platform/test/c4-likec4-version-pin.test.ts` before touching any site
(`cq-write-failing-tests-before`). Keep it proportionate: one pure function, a handful of assertions.

1. Add a pure `checkLikec4Pins(files, now)` returning a list of violation strings (empty when clean).
   The real-file test asserts it returns `[]`; the self-test cases below assert a mutated input returns a
   non-empty list. Both go through the same function, so weakening it turns the self-test red.
2. Extraction, **comment-stripped first** (drop whole-line `#`, `//`, `*` comments, as
   `plugins/soleur/test/c4-canonical.test.ts` does). `ci.yml` already carries explanatory comments that
   mention `npm install -g likec4@1.50.0` (the `test-scripts` job header), so an unstripped scan reads
   four sites, not three, and would demand the flag inside prose.
   - Workflows (`ci.yml`, `main-health-monitor.yml`): every `npm install -g likec4@<digit...>` command
     line (derived by `matchAll`, not a fixed count) must carry `--before=<D>`.
   - `render-c4-model.sh` and `generate-c4-from-components.ts` write `likec4@${LIKEC4_VERSION}`, which
     the digit-anchored regex cannot see. Extract the single non-comment line containing
     `export json` (`"export", "json"` in TS) and assert it carries the flag. The three
     `npx -y likec4@${LIKEC4_VERSION} validate ...` hint lines in `render-c4-model.sh` are
     human-copy-paste text and are excluded by that extraction.
   - Do not wrap the `npx` argv across lines: `c4-canonical.test.ts` checks `--no-use-dot` on the same
     line as `export json`, so the new flag must stay on that line.
3. Assertions: one `<D>` across every site (set size 1); `render-c4-model.sh` declares
   `LIKEC4_BEFORE="<D>"` and `c4-from-components.ts` exports the same value; `<D>` is a valid
   `YYYY-MM-DD` and at least 3 days older than the injected `now` (UTC; the check is monotone, so it
   can only get easier to satisfy and cannot flake); site count > 0.
4. The failure message for a version or date mismatch prints the bump procedure and the one command
   (`npm view likec4@<version> time --json`), because bumpers enter through the Dockerfile or
   `package.json`, neither of which mentions the date.
5. Fix the stale comment in this test that says ci.yml carries "THREE" install lines.
6. Mirror the date parity in `plugins/soleur/test/c4-from-components.test.ts`, beside the existing
   `LIKEC4_VERSION` assertion.
7. Run the suite against the unmodified sites: it must go RED. Record the RED output in the PR body.

### Phase 2 — Pin the sites (GREEN)

Choose `D = 2026-09-28` (>= 3 days before today, after the likec4@1.50.0 publish, excludes both
incident tarballs, differs from today's resolved tree by only the 5 nodes above).

- `.github/workflows/ci.yml`, three steps named `Install likec4 CLI (pinned — matches Dockerfile/package.json)`
  (jobs `test-webplat`, `test-scripts`, `test-scripts-heavy`): `npm install -g likec4@1.50.0 --before=2026-09-28`.
  Add a short comment above each step (or one shared comment at the first, referencing it from the
  others) stating: why `--before`, that the version and date are a pair, how to bump (below), and that a
  lockfile was measured and rejected. Update the stale comments inside the `test-scripts` job header
  (the "NOTE ... `npx -y <pkg>@<version>` does NOT reuse the `npm install -g likec4@1.50.0` step" and
  the "`likec4@1.50.0:` bullet") so they mention the date and that the `npx` sites are pinned too.
- `.github/workflows/main-health-monitor.yml`: same flag on the literal install line; extend the
  TOOLCHAIN PINS comment ("LIKEC4_VERSION -> 6 sites ...") to the new count and name the date.
- `plugins/soleur/scripts/render-c4-model.sh`: add `LIKEC4_BEFORE="2026-09-28"` beside
  `LIKEC4_VERSION`, and `--before="${LIKEC4_BEFORE}"` to the `npx -y --ignore-scripts` invocation;
  document the pair in the header's "Pinned to likec4@..." paragraph. Do not change the three
  diagnostic hint lines that print interactive `npx -y likec4@${LIKEC4_VERSION} validate ...`
  commands (human copy-paste, not CI).
- `plugins/soleur/lib/c4-from-components.ts`: `export const LIKEC4_BEFORE = "2026-09-28";` beside
  `LIKEC4_VERSION`, with the "MUST stay equal to ... render-c4-model.sh" note.
- `plugins/soleur/scripts/generate-c4-from-components.ts`: add `` `--before=${LIKEC4_BEFORE}` `` to the
  `npx` argv array and import the constant; extend the existing `--ignore-scripts` comment with one
  sentence on the date.
- Bump procedure, written once under a greppable `BUMPING LIKEC4` heading in the `render-c4-model.sh`
  header; the other sites carry a one-line pointer to it (the ci.yml header NOTE and bullet SHRINK to a
  pointer, they do not grow). Content: when bumping `LIKEC4_VERSION`, set `LIKEC4_BEFORE` to a date >=
  the new version's publish time and >= 3 days old (`npm view likec4 time --json`), then update all
  sites in one commit. Policy: the date moves with a likec4 bump, or sooner if a transitive advisory
  affects the CLI; the tree is otherwise frozen on purpose. A forgotten date is caught by an `ETARGET`
  install failure (the registry knows publish times; the offline guard does not), and the guard's own
  contribution is parity plus the age floor. Also state the one customer-visible failure mode: a private
  registry mirror that serves metadata without per-version publish times makes `--before` fail
  resolution with `ETARGET`.
- `main-health-monitor.yml`: the date stays a literal on the install line (no `LIKEC4_BEFORE` env
  entry), because the guard reads literals; say so in its TOOLCHAIN PINS comment and update the stale
  site count there.

### Phase 3 — Verify

- Local, before push: `cd apps/web-platform && ./node_modules/.bin/vitest run test/c4-likec4-version-pin.test.ts`,
  `bash plugins/soleur/test/render-c4-model.test.sh`, the `c4-from-components` suites, and
  `bash plugins/soleur/test/scripts-shard-runtime-coverage.test.sh` (all GREEN).
- Local functional re-check of the real path: `NPM_CONFIG_CACHE=<scratch> bash plugins/soleur/scripts/render-c4-model.sh --out <scratch>/m.json`
  then `cmp` against the committed `model.likec4.json` (byte-identical, as measured).
- Confirm `generate-c4-from-components.ts` surfaces npm's stderr when resolution fails (the
  `render-c4-model.sh` path already prints its render log), and record one cold-cache wall-time
  before/after for the `npx` render in the PR body (the producer's 600 s budget was sized against a
  measured 151 s cold install).
- CI is the test gate. This PR edits the install steps themselves, so the PR's own CI exercises the
  new flag on every job that installs likec4 (`test-webplat` x2, `test-scripts` x7, `test-scripts-heavy`
  x3, `test`). Stop at green CI with the PR ready.
- **No admin merge.** The PR edits `.github/workflows/ci.yml`; do not run `gh pr merge --admin`. Leave
  the PR open and report to the operator when CI is green.

### Phase 4 — Deferral tracking

File one GitHub issue (milestone from `knowledge-base/product/roadmap.md`, label per repo convention)
for the residual same-class sites this PR deliberately leaves: the Dockerfile
`npm install -g likec4@1.50.0` and `@anthropic-ai/claude-code@...` installs, which resolve floating
transitives in the release image build; and the vestigial likec4 install in `test-scripts` /
`test-scripts-heavy` (removing it would drop two exposure sites, but it also removes the cache warm-up
the pinned `npx` benefits from and needs the `scripts-shard-runtime-coverage` contract changed).
Re-evaluation trigger: next release-build E404 or the next likec4 version bump. Reference the new issue
from the PR body. The agent-facing `npx -y likec4@1.50.0 validate` doc recipes are interactive and
asserted by the version-pin test; they are a Non-Goal and get no issue.

## Files to Edit

- `.github/workflows/ci.yml`
- `.github/workflows/main-health-monitor.yml`
- `plugins/soleur/scripts/render-c4-model.sh`
- `plugins/soleur/scripts/generate-c4-from-components.ts`
- `plugins/soleur/lib/c4-from-components.ts`
- `apps/web-platform/test/c4-likec4-version-pin.test.ts`
- `plugins/soleur/test/c4-from-components.test.ts`

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-9300-likec4-pin-transitive-deps/tasks.md` (plan artifact)

Glob/path verification (`hr-when-a-plan-specifies-relative-paths-e-g`): every path above exists on the
branch (`git ls-files` confirmed for all seven edits).

## Acceptance Criteria

### Pre-merge (PR)

- [ ] All four workflow `npm install -g likec4@1.50.0` lines carry `--before=2026-09-28`;
      `grep -c -e 'npm install -g likec4@1.50.0 --before=2026-09-28' .github/workflows/ci.yml` prints
      `3` and the same grep on `main-health-monitor.yml` prints `1` (anchored on the install command, so
      explanatory comments cannot change the count; keep the full command string out of comments).
- [ ] `render-c4-model.sh` declares `LIKEC4_BEFORE` and its `npx` call passes it;
      `generate-c4-from-components.ts` passes `--before=${LIKEC4_BEFORE}`; `c4-from-components.ts`
      exports the same value.
- [ ] The guard (extended `c4-likec4-version-pin.test.ts`) was observed RED against the unmodified
      sites and is GREEN after Phase 2 (RED output captured in the PR body).
- [ ] The Guard Contract mutation rows each reddened `checkLikec4Pins` once (string-fed self-test cases)
      and the must-PASS row stayed green.
- [ ] `render-c4-model.test.sh`, `c4-from-components.test.{sh,ts}`, `c4-model-freshness.test.sh`,
      `scripts-shard-runtime-coverage.test.sh` pass.
- [ ] This PR does not touch the Dockerfile or `package.json`:
      `git diff --quiet origin/main...HEAD -- apps/web-platform/Dockerfile apps/web-platform/package.json`
      exits 0 (three-dot, merge-base form); the version parity guard is still green.
- [ ] PR CI is fully green, including the required `test` context.
- [ ] PR body contains `Closes #9300` and links the Phase 4 deferral issue.
- [ ] PR is left open, NOT admin-merged; operator is told CI is green and the PR is ready.

### Post-merge

None required beyond the operator's merge. Soak signal (informational, no follow-through enrollment
needed): no `E404` on a likec4 tarball in subsequent `main` CI runs.

## Test Scenarios

(Property-shaped, derived from the Guard Contract; see below.)

- Given a workflow with three install lines where the second lacks `--before`, `checkLikec4Pins`
  reports it (a first-match read would stay green).
- Given the monitor's date differs from `ci.yml`'s by one day, it reports a set-size violation.
- Given the renderer's `export json` line lacks the flag while the header comment quotes it, it
  reports a violation (comment-stripped extraction).
- Given every site is moved together to a different valid date at least 3 days old (e.g. `2026-09-29`
  with an injected `now` of `2026-10-05`), it reports nothing, so the guard is not pinned to the
  literal `2026-09-28`.
- Given a date younger than 3 days or not a date, it reports a violation.
- Given `LIKEC4_VERSION` is bumped in all sites but the date is not moved, the install fails with
  `ETARGET` (registry-side); the offline guard cannot see that and does not claim to.

## Guard Contract

### Guard 1 — likec4 pin-pair parity

**Property.** Every place CI resolves likec4's dependency tree uses the same (version, `--before` date)
pair, the date is old enough to be CDN-safe, and the pair's version equals the Dockerfile and
`package.json` pin.

**Assembly.** The population is every likec4 resolution in: `.github/workflows/ci.yml` (all
non-comment `npm install -g likec4@` lines, derived by `matchAll`, not a fixed three),
`.github/workflows/main-health-monitor.yml`, `plugins/soleur/scripts/render-c4-model.sh` (the
`export json` line AND the `LIKEC4_BEFORE` declaration), `plugins/soleur/scripts/generate-c4-from-components.ts`
(the `export json` argv line), and `plugins/soleur/lib/c4-from-components.ts` (the exported constant).
There is more than one chokepoint (YAML, bash, TS), so each file's extraction is stated explicitly
rather than assuming one regex covers all three. The Dockerfile is deliberately out of this guard's
date population (version-only; tracked in the Phase 4 issue) and is not asserted either way.

**Mutation matrix.**

| # | Mutation (edit that MUST drive `checkLikec4Pins` RED) | Targets |
|---|---|---|
| 1 | Remove `--before=...` from the SECOND of three install lines | second-member check; a first-match read stays green |
| 2 | Change the date in the monitor only | cross-file set-size-1 check |
| 3 | Remove the flag from the renderer's `export json` line while a header comment still quotes it | comment-stripped extraction, declaration without use |
| 4 | Remove the flag from the TS `export json` argv line | TS chokepoint |
| 5 | Feed a file set containing zero likec4 sites | the guard's own dispatch: it must fail when it examined 0 sites |
| 6 | Set the date younger than 3 days, then to a non-date string | age floor and validity |

**Harness rows.** (a) Weaken the scanner to a first-match read: row 1 must turn RED, which proves the
self-test exercises the scanner and not the file-level assertion. (b) Must-PASS input that is not the
canonical: move every site together to another valid date at least 3 days old (injected `now`).

**Anchor.** The date literal and the install flag sit in the same commit, so one diff can move both and
the guard proves consistency plus the age floor, not integrity. Nothing outside the commit must also
move for a weakening to pass. Accepted and stated: the date is a reproducibility pin, not a security
control; tarball tamper-evidence is npm's own integrity check, and a merge-base diff gate would be
gold-plating for a CI flake fix.

## Observability

```yaml
liveness_signal:
  what: required CI `test` context plus the 6-hourly main-health-monitor run, both of which execute the likec4 install and the render suites
  cadence: every PR push and every 6 hours
  alert_target: GitHub required-check failure on the PR; main-health-monitor files a priority issue on a red main
  configured_in: .github/workflows/ci.yml and .github/workflows/main-health-monitor.yml
error_reporting:
  destination: GitHub Actions step status (no application DSN involved; CI-only change)
  fail_loud: the install step exits non-zero with `npm error code E404` or `ETARGET ... with a date before`, failing the shard
failure_modes:
  - mode: version bumped without moving the date
    detection: install step fails with ETARGET naming the date (registry-side; the offline guard cannot know publish times)
    alert_route: PR check failure on the bumping PR
  - mode: date literal drifts between sites, or is younger than 3 days
    detection: c4-likec4-version-pin.test.ts parity and age assertions
    alert_route: required `test` context
  - mode: a likec4 tarball inside the cutoff is unpublished from the registry
    detection: install step E404 on a tarball older than the cutoff
    alert_route: PR check failure or main-health-monitor issue
logs:
  where: GitHub Actions job logs for the Install likec4 CLI step
  retention: 90 days (GitHub default)
discoverability_test:
  command: grep -c -e 'npm install -g likec4@1.50.0 --before=2026-09-28' .github/workflows/ci.yml
  expected_output: 3
```

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure/tooling change. No user-facing surface (no
`components/`, `app/**/page.tsx`), so the Product/UX gate does not fire; no new infrastructure, store,
or connection (IaC and encryption-posture gates skip); no regulated-data surface (GDPR gate skips);
no architectural decision (a dependency-pin mechanism; ADR-191's exemption text is unaffected), so no
ADR/C4 deliverable.

## User-Brand Impact

- **If this lands broken, the user experiences:** a red required `test` check on unrelated PRs (the
  failure being fixed), or, if the plugin pin is wrong, `render-c4-model.sh` / the C4 sync step failing
  loudly with an `ETARGET` message in a self-hosted install; the same shows for a customer behind a
  registry mirror that omits per-version publish times (`render-c4-model.sh` hard-fails with npm's log,
  the producer degrades to `likec4-unavailable`).
- **If this leaks, the user's data is exposed via:** no vector; no secrets, tokens, or user data are
  read or written, and no production system is touched.
- **Brand-survival threshold:** none

`threshold: none, reason: the diff touches CI workflow files and a plugin render script that handle no user data, credentials, or auth, and a wrong pin fails loudly at install time rather than degrading silently.`

## Non-Goals / Alternatives Considered

| Alternative | Verdict |
|---|---|
| Committed lockfile + `npm ci` (tools package) | Rejected: hoisted layout fails 5/15 sandbox tests; cannot cover `npx`; adds a fifth `lockfile-sync` directory |
| Shrinkwrap injected into a repacked tarball | Rejected: maintenance burden, same layout caveats |
| `--min-release-age=3` (rolling) | Rejected: not deterministic across runs; byte-diff freshness could flip |
| Pin the Dockerfile too | Deferred (Phase 4 issue). Release-image contents would change with no PR-time test of the runner stage. Stated consequence: CI now tests a pinned tree while the shipped image still resolves a floating one, so the 15 `c4-render-tenant-config` tests no longer cover the exact shipped tree until the issue lands. Surfaced as a Taste decision in `decision-challenges.md` (DHH review recommended doing it here). |
| Pin agent-facing doc recipes | Non-Goal: interactive, and the version-pin test asserts their literals |
| A `scripts/bump-likec4-pin.sh` and a date-staleness warning (CTO advisory) | Cut: the guard's failure message carries the procedure; a stale-date warning is a recurring-signal mechanism with no requirement behind it in this fix. Re-evaluate if the date is ever forgotten twice. |
| `actions/cache` keyed on version+date | Not needed now; would cut registry exposure to one install across the matrix |

## Sharp Edges

- The date is half of a pair. `ETARGET` on a version bump is the intended loud failure.
- `--before=2026-09-28` is interpreted as UTC midnight (measured).
- `before` wins over `min-release-age`; do not "fix" that by adding a root `.npmrc` (ADR-191).
- A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits the
  threshold fails `deepen-plan` Phase 4.6; this one is filled.
- Keep the substring `npm install -g likec4@` in the job blocks (`scripts-shard-runtime-coverage`).
- The guard regex requires a digit after `likec4@`; keep literals, not `${LIKEC4_VERSION}`, in the
  monitor.

## Plan Review Disposition (2026-10-01)

Panel: DHH, Kieran, code-simplicity, plus the CTO devex lens (threshold `none`, so no 5-agent
escalation). Applied as Mechanical: comment-stripped extraction and an install-line-anchored AC
(Kieran P1.1, P1.3); a single `checkLikec4Pins` shared by the real-file test and the self-test, with
harness row (a) restated (Kieran P1.2, simplicity); the Dockerfile no-`--before` assertion cut (three
reviewers); an offline 3-day age floor with an injected `now` replacing "not in the future"
(simplicity, CTO); matrix trimmed from 8 rows to 6; the bump procedure written once under `BUMPING
LIKEC4` with the policy sentence and the failure message carrying the command; the monitor date stays
a literal; the Observability claim corrected (a forgotten date is caught by `ETARGET`, not the offline
guard); customer-mirror failure mode and stderr/timing checks added; deferral issue trimmed.
Surfaced as Taste (persisted to `decision-challenges.md`): pin the Dockerfile in this PR (DHH), a bump
script, and a stale-date warning (CTO).
