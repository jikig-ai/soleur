---
title: "ci: pin likec4/claude-code transitives in the release image build and retire the vestigial test-shard likec4 installs"
date: 2026-10-04
slug: ci-pin-release-image-transitives
branch: feat-one-shot-9343-pin-release-image-transitives
issue: 9343
closes: 9343
type: chore
priority: p3
domain: engineering
brand_survival_threshold: none
lane: cross-domain
---

# ci: pin the release-image CLI trees and retire the vestigial test-shard likec4 installs

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed). No spec.md exists for this branch (one-shot pipeline, no brainstorm).

## Overview

Issue 9343 is the follow-up to PR 9338 (merged 2026-10-01, closed issue 9300), which pinned the likec4 transitive tree with `--before=2026-09-28` at every CI resolution site. Two same-class sites were left out on purpose, and each needs a decision rather than a one-line edit:

1. **The release image build** (`apps/web-platform/Dockerfile`, runner stage): `RUN npm install -g @anthropic-ai/claude-code@2.1.284` and `RUN npm install -g likec4@1.50.0` resolve at release-build time. CI tests a pinned likec4 tree while the shipped image resolves whatever the registry serves at the last layer-cache bust, so the 15 `c4-render-tenant-config` tests do not cover the exact shipped tree, and a CDN-lag 404 can fail a release build the way it failed CI.
2. **The likec4 installs in the `test-scripts` and `test-scripts-heavy` CI shards** (`.github/workflows/ci.yml`): the issue calls them vestigial. `plugins/soleur/test/scripts-shard-runtime-coverage.test.sh` asserts the install wherever a suite mentions likec4, so the contract has to change with any removal.

The CTO agent ruled on both (verbatim rulings and the measurements behind them are recorded under "CTO Assessment" below). Summary of the outcome:

- likec4 in the image: append the same literal `--before=2026-09-28` to the Dockerfile install (flag, not a lock) and make the Dockerfile a sixth parity site in `c4-likec4-version-pin.test.ts`.
- claude-code in the image: **no `--before`**. Its tree is two exact-pinned packages with zero floating transitives (measured); a date would ETARGET at the current pin and add bump friction for no benefit. A small lockfile assertion added to the existing `claude-cli-pin-knows-models.test.ts` replaces it.
- PR-time check: split the two installs into a `cli-tools` Dockerfile stage that `runner` is built `FROM`, and add a ~60 s `--target cli-tools` no-cache build step to the existing `web-platform-build` job. A full `--target runner` PR build was measured and rejected (+~4 min and three external network dependencies inside a required aggregate).
- Shards: **remove** the install from `test-scripts-heavy` (no heavy suite touches likec4); **keep** it in `test-scripts` (three suites render through `npx` and the install is their download-cache warm-up). The shard-coverage contract's `likec4` row is scoped to the light job only; every consumer falls back to `npx`, so the heavy install was never a correctness requirement and the contract has no business demanding it there.

## Enhancement Summary

**Deepened on:** 2026-10-04. **Agents:** architecture-strategist, security-sentinel, test-design-reviewer, plus mechanical gates (4.6 user-brand, 4.7 observability, 4.8 PAT, 4.11 guard-contract lint, 4.12 scope check) and live verification of every cited PR/issue, rule id and the SHA-pin length.

### Key improvements applied

1. Guard 3 and Guard 1 mechanics made drivable: the shard-coverage suite's `check_runtime` must become fixture-fed and return a status, and the marker grep must ignore comment lines; the image-structure check becomes a pure function over parsed fixtures (a `cli-tools` slice that holds the likec4 install is a test-pinned fact, not an inference from cardinality).
2. Guard 2 becomes a fixture-fed helper that also binds the lock entry's version to the package.json pin and checks platform keys against the optionalDependencies keys.
3. Supply-chain records: the install-sites lint boundary comment and the ADR-191 amendment name the `builder` stage only; `cli-tools` is a second discarded-container install site on `pull_request`. Both get a one-clause edit, and the step is pinned secret-free by the structural test. `--before` is recorded as a recency floor, not an integrity control.
4. Tracked deferral for the real gap the review found: nothing detects an advisory against the frozen likec4 tree (issue 9498, in addition to issue 9497).

### New considerations discovered

- A claude-code bump PR pulls a version published minutes earlier into a required check (no `--before` on that line): accepted residual, a rerun clears CDN lag.
- `cli-tools` must be `FROM` the node digest, never `FROM builder` (the builder declares `SENTRY_AUTH_TOKEN` ARGs).

### Merge policy for this PR (explicit)

**This change edits `.github/workflows/ci.yml` (the `web-platform-build` job, the `test-scripts-heavy` job, and the likec4 comments). It therefore edits `.github/workflows/**`. It does NOT edit `.github/actions/**`. This PR must NOT be admin-merged.** Merge it through the normal path: mark ready, `gh pr merge --squash --auto`, and let the required `test` aggregate and the other required checks gate it. No split was chosen (see Alternatives): ci.yml has to change regardless, because its comments assert the Dockerfile is "version-only on purpose (#9343)", which this PR makes false.

## Research Reconciliation — Spec vs. Codebase

| Issue / brief claim | Reality (verified this session) | Plan response |
|---|---|---|
| `@anthropic-ai/claude-code@...` "resolve floating transitives" and should get `--before` | `npm view @anthropic-ai/claude-code@2.1.284` shows `dependencies: {}` and 8 optionalDependencies, all `@anthropic-ai/claude-code-<platform>@2.1.284` exact-pinned; the linux-x64 platform package has no dependencies. In the pinned `node:22-slim` image (npm 10.9.4) the install prints `added 2 packages`. `apps/web-platform/package-lock.json` agrees. There is nothing floating to pin. | No `--before` on claude-code. Offline lockfile tripwire (Guard 2) makes "still zero floating transitives" a CI fact at the next bump. |
| Dockerfile installs should resolve with `--before=<the repo's likec4 date>` (applied to both) | `--before=2026-09-28` is midnight-exclusive. In the pinned image `npm install -g @anthropic-ai/claude-code@2.1.284 --before=2026-09-28` fails `ETARGET ... with a date before 9/28/2026, 12:00:00 AM` (2.1.284 was published 2026-09-28T17:11Z); `--before=2026-09-29` succeeds. claude-code publishes about daily. | The shared likec4 date cannot apply to claude-code, and a separate date would need to move on every claude-code bump while its 3-day floor blocked fresh releases. Rejected (see Cut List). |
| "or an equivalent lock" | `npm install -g` ignores lockfiles. A hoisted `npm ci` layout was measured in PR 9338's plan to fail 5 of 15 `c4-render-tenant-config` tests (global layout: 15/15), because `server/c4-render.ts` binds the global install prefixes into bubblewrap. ADR-050 already chose a global install over a package.json dependency to keep prod `npm ci` lockfile parity. | Flag, not lock. The ADR-050 addendum records this so the next reader does not take the "or a lock" detour. |
| "no PR-time test builds the runner stage" | True. `web-platform-build` (ci.yml) builds `target: builder` only (about 1m52s cold, unconditional, a member of the required `test` aggregator's `needs`). | Add a `cli-tools` build step there. A local cold `--target runner` build was 391 s wall (runner-only layers about 255 s: claude-code 41.8 s, likec4 17.2 s, apt 28.4 s + 18.3 s, `playwright install --with-deps chromium` 105.8 s, `npm ci --omit=dev` 43.2 s) with dependencies on deb.debian.org, the rolling cli.github.com apt repo and cdn.playwright.dev. |
| "no suite there resolves `likec4` from PATH (the renderer uses `npx`)" | Verified. The three rendering suites are all in `test-scripts` (light) legs per `scripts/suite-shard-legs.tsv`: `render-c4-model.test.sh` leg 1, `c4-from-components.test.sh` leg 5, `c4-model-freshness.test.sh` leg 7. `test-scripts-heavy` runs exactly three registrations (`tests/scripts/test-registry-gate-mutation-battery.sh`, `scripts/battery-tag-authorship-mutations.test.sh`, `.github/scripts/test/run-all.sh`); none mention likec4 or render-c4. | Heavy install is genuinely dead: remove. Light install is a warm-up for real consumers: keep. |
| "removing the step ... also removes the download-cache warm-up" | Measured in the pinned image: cold `npx -y --before=2026-09-28 likec4@1.50.0 --version` 26.6 s; global install 18.1 s; `npx` right after the global install 1.9 s. `generate-c4-from-components.ts` records 151 s cold on a slow machine (its timeout is 600 s). The install is not a second registry exposure (the tarballs are fetched once either way), it just moves the fetch out of a suite into a named step. | Keep in light, record why in the ci.yml comment. Net saving from removing it would be about 0 s, and it would force a contract change for no gain. |
| "`scripts-shard-runtime-coverage.test.sh` asserts the install exists wherever a suite mentions `likec4`" | Its `check_runtime` takes every `plugins/soleur/test/*.test.sh` whose comment-stripped text matches `likec4[[:space:]]` as a "user" of BOTH jobs (it does not model which job runs which suite), and the match currently fires on prose and echo text such as `SKIP: likec4 CLI unreachable`, not only on invocations (baseline run on this branch: users are `c4-from-components.test.sh` and `render-c4-model.test.sh`, 14 passed, 0 failed). | Scope the `likec4` row to the light job only (Guard 3, one call-site edit plus a comment). No heavy-suite derivation: every consumer falls back to `npx`, so the install is a warm-up and no job's correctness depends on it. |

## Research Insights

**Premise Validation.** Checked: issue 9343 is OPEN with no closing PR; PR 9338 is MERGED and closed issue 9300 (not this one); PR 7390 is an OPEN stale draft; PR 9496 is the OPEN draft for this work. Cited paths exist on this branch: `apps/web-platform/Dockerfile` (runner-stage installs at the `Install Claude Code CLI` and `LikeC4 CLI for runtime diagram re-render` comments), `.github/workflows/ci.yml`, `plugins/soleur/scripts/render-c4-model.sh` (carries `BUMPING LIKEC4` and the "version-only ... tracked in #9343" sentence), `plugins/soleur/test/scripts-shard-runtime-coverage.test.sh`. ADR corpus grep for the mechanism (`likec4`, `--before`, `npm install -g`): ADR-050 (global install over a package.json dependency, which is why a lock is not "an unconsidered idea") and ADR-191 (npm single lockfile of record; the boundary note in `scripts/lint-workflow-install-sites.sh` already names `web-platform-build` as a Dockerfile-install site that lint cannot see). Nothing stale; one premise partially false (claude-code "transitives", see Reconciliation).

**Property List** (what must be observably true):

- P1. The release image resolves the likec4 tree as of the repo's likec4 date, the same pair CI tests.
- P2. A Dockerfile pin that cannot resolve (version/date mismatch, registry error) is caught at PR time, not at the first release build.
- P3. The claude-code install cannot silently grow a floating transitive tree.
- P4. Every likec4 install left in CI has a consumer in the job that carries it, and the shard-coverage contract no longer demands one where no consumer exists.
- P5. The decisions are recorded where the next bumper looks (`BUMPING LIKEC4`, the ci.yml comments, ADR-050).

**Cut List** (mechanism, property it would buy, what already covers it):

- `--before` on the claude-code install: buys P3, but P3 already holds (two exact-pinned packages); a date would ETARGET now and add bump friction. The lock tripwire covers drift.
- Lockfile / `npm ci` install of likec4: buys P1, but breaks the global layout the sandbox binds (5/15 failures, ADR-050).
- Full `docker build --target runner` on every PR: buys P2, which `--target cli-tools` buys at roughly a quarter of the cost without apt/CDN dependencies.
- A Dockerfile `ARG` for the date: P1 only; adds a build-arg surface and breaks the `npm install -g likec4@<digit>` scanner regexes.
- Removing the `test-scripts` install: buys nothing measurable (net about 0 s) and costs a contract rewrite.
- A new `claude-code-install-tree-pin.test.ts` file (plan-review cut): the same assertion fits in the existing `claude-cli-pin-knows-models.test.ts`, which already ties package.json, the Dockerfile and the lock to one version.
- A heavy-suite derivation engine in the shard-coverage contract (plan-review cut): the heavy install is a warm-up, not a requirement, so the contract simply stops demanding it there; the pin test's `ci.yml` cardinality of 2 catches a silent re-add.
- Structural assertion that `cli-tools` holds both installs (plan-review cut): implied by the likec4 cardinality-1 check plus the unchanged claude-code `RUN` line.
- A new required status context or a path gate for the new check: P2 is satisfied inside the existing unconditional `web-platform-build`; a path-skipped required context stalls the merge queue.
- Splitting the PR into a workflow and a non-workflow half: ci.yml must change anyway (stale comments), so a split only adds a window in which the comments lie.

**Value-proposition measurement (0.6c).** The only saving claimed is removing the heavy-shard install: about 18 s per heavy leg (command: `docker run ... npm install -g likec4@1.50.0 --before=2026-09-28`, measured 18.1 s in the pinned image), times 3 legs in parallel. That is a side benefit; the justification is removing a dead exposure site, not the seconds. The cost of the new check is measured: the two installs took 41.8 s + 17.2 s in the local cold runner build.

**Institutional learnings applied** (`knowledge-base/project/learnings/`):

- `integration-issues/2026-10-01-npm-before-pins-the-tree-but-is-silent-when-the-registry-has-no-publish-times.md`: version and date are a pair; `--before` is silently inert on a mirror without per-version publish times (documented residual); `npx` and global installs share the download cache, which is the basis for keeping the light-shard warm-up.
- `2026-06-08-ci-gate-fail-open-traps-skip-token-grep-and-buildkit-cache-mode.md`: `cache-to` is `mode=min` in the release; the new step must not export cache and must not add a builder-secret layer (the `cli-tools` stage has no ARGs or secrets).
- `2026-06-29-required-check-anchors-must-cover-verified-surface-not-inherited-paths.md` and the ci.yml header comment: every required context must run on `merge_group`; hence no path gate on the new step.
- `best-practices/2026-06-29-admin-merge-skips-deploy-via-await-ci-gate.md`: reinforces the operator's no-admin-merge rule for infra/build-file PRs.
- The Dockerfile's own CACHE-ORDERING INVARIANT (#5055) and `GH_VERSION` comment: heavy layers stay above `ENV BUILD_*`; a rolling-repo dependency in a PR check is exactly the flake class to keep out.

## CTO Assessment

Spawned `soleur:engineering:cto` (instructed not to use AskUserQuestion) with the measured facts above. Rulings, recorded as binding for this plan:

**Ruling a1 — pinning.**

- likec4: use the flag, not a lock. `RUN npm install -g likec4@1.50.0 --before=2026-09-28`, literal date on the same line (no ARG). Source of truth stays `LIKEC4_BEFORE` in `render-c4-model.sh` and `plugins/soleur/lib/c4-from-components.ts`; the Dockerfile becomes one more parity site in `checkLikec4Pins` (exactly one install line, flag present, same date).
- claude-code: no `--before` (zero floating transitives, midnight-exclusive ETARGET, bump friction). Replace with an offline lockfile tripwire: the `node_modules/@anthropic-ai/claude-code` lock entry has no `dependencies`, every optionalDependency equals the entry's own version exactly, and any `claude-code-*` platform entries also have no `dependencies`. The lock is valid evidence because the Dockerfile pin equals the package.json pin (already enforced by `claude-cli-pin-knows-models.test.ts`). Leave the claude-code `RUN` line text unchanged so its layer stays cached.
- `BUMPING LIKEC4`: add `apps/web-platform/Dockerfile` to step 2 as a literal-date site; delete the "Deliberately version-only ... #9343" sentence; keep package.json and the interactive validate recipes as version-only; add that a claude-code bump needs no date but the tripwire must stay green.

**Ruling a2 — PR-time check.** Option (ii): a `cli-tools` stage (same pinned `node:22-slim` digest, only the two global installs) with `runner` as `FROM cli-tools AS runner`; layer order and cache keys are identical (precedent: `FROM deps AS builder`). A step in the existing `web-platform-build` job: `docker/build-push-action`, `target: cli-tools`, `push: false`, `load: false`, `no-cache: true` (a cache hit would pass without exercising registry resolution), step `timeout-minutes: 5`, about 60 s, npm registry only. No new required context, no path gate (it already runs on `merge_group`). A structural test makes "cli-tools builds" equal "the runner's install layers build" (runner is `FROM cli-tools`, `cli-tools` holds both installs, the ci.yml step targets `cli-tools`). The PR states that "builds the runner stage" is met by its ancestor stage, which contains every install the issue is about. Rejected: (i) extra `target: runner` step (too slow and flaky), (iii) offline parity alone (fails the acceptance; stays as the cheap first tier), (iv) docker inside a vitest suite (brittle). A `.github/workflows` edit IS needed.

**Ruling b — shards.** `test-scripts`: KEEP (warm-up for three `npx` consumers; not a second exposure). `test-scripts-heavy`: REMOVE. Rewrite the contract rather than delete the assertion: `check_runtime` takes an optional explicit user-file list; the heavy list is derived from the `^if want_scripts_heavy; then$` .. `^fi$` region of `scripts/test-all.sh` plus the files under `.github/scripts/test/`; heavy keeps `bun` and `gitleaks` on the current all-suites behavior and only `likec4` is scoped; add a non-vacuity self-check (a synthetic suite containing `likec4`+space against a block without the install must FAIL); assert the light users list is non-empty and includes `render-c4-model.test.sh`. Pin-test cardinality for ci.yml becomes 2 (test-webplat, test-scripts).

**Ruling c — records.** A short dated ADR-050 addendum (global-not-lock invariant with the 5/15 measurement, `--before` pairing now covering the image, deliberate no-`--before` for claude-code). No new ADR. No C4 impact.

**Constraints and risks the CTO attached.** One PR (9496), no split, merge on green CI normally with no admin merge. The likec4 `RUN` edit busts that layer and everything after it once (apt, gh, playwright about 106 s, `npm ci`): the first release after merge takes about 5 to 6 minutes; state it in the PR. Never move `ENV BUILD_*` or any per-commit-volatile line above the installs. Keep builder-stage lines untouched (PR 7390). Run `playwright-mcp-version-pin`, `claude-cli-pin-knows-models`, `sentry-monitor-iac-parity` and `dockerfile-runner-ssh-client` explicitly. The new image gets the frozen 2026-09-28 tree (the tree test-webplat passes 15/15 on) instead of whatever was newest at the last cache bust. A mirror without per-version publish times makes `--before` inert (documented residual).

### Plan-review amendments (implementation of the rulings, not reversals)

The eng panel (DHH, Kieran, code-simplicity) accepted the stage split, the CI step and the Dockerfile as a pin-test site, and pushed back on the weight of the rest. Applied as mechanical simplifications of HOW the CTO rulings are implemented: the claude-code lock assertion moves into the existing `claude-cli-pin-knows-models.test.ts` (no new file, no Dockerfile-equals-lock row, which that test already enforces); the shard-coverage change shrinks to scoping the `likec4` row to the light job (no heavy-suite derivation, no new parser); the structural test keeps two assertions; the ADR addendum shrinks to the invariant and the measurement; comments carry one line each (the numbers live in this plan and the PR body). Recorded dissent (taste, not applied): DHH and code-simplicity preferred keeping BOTH shard installs and recording the decision; the CTO ruling and the fact that the heavy install has no consumer at all stand, and the dissent is appended to `knowledge-base/project/specs/feat-one-shot-9343-pin-release-image-transitives/decision-challenges.md` for ship to surface.

## Alternatives Considered

| Alternative | Verdict |
|---|---|
| Lockfile (`npm ci` in a side directory) for likec4 | Rejected: hoisted layout fails 5/15 sandbox tests; conflicts with ADR-050 |
| `--before=2026-09-28` on both installs | Rejected: ETARGET on claude-code 2.1.284 (measured) |
| Separate `CLAUDE_CODE_BEFORE` date | Rejected: moves every bump; 3-day floor blocks fresh releases; nothing to pin |
| `--target runner` PR build | Rejected: +~4 min, apt/cli.github.com/cdn.playwright.dev flake in a required aggregate |
| Offline parity only | Rejected as sole check (acceptance asks for a build); kept as tier one |
| Remove both shard installs | Rejected: light install warms three real consumers; removal buys about 0 s and costs a contract rewrite |
| Keep both shard installs, record only | Rejected: heavy install has no consumer at all |
| Split into admin-mergeable and workflow PRs | Rejected by CTO: ci.yml changes regardless |

## Implementation Phases

Tests first (`cq-write-failing-tests-before`): Phase 1 lands the guards and their mutation rows red before Phases 2 and 3 make them green.

### Phase 1 — Guards and tests (RED)

- `apps/web-platform/test/c4-likec4-version-pin.test.ts`:
  - Add `dockerfile: string` to `Likec4PinFiles` and `readPinFiles()` (`read("Dockerfile")`). In `checkLikec4Pins`, treat the Dockerfile like the workflows: `extractInstallLines(files.dockerfile)` must be exactly 1, carry `--before=<date>`, join the `dates` set, count in `sites`, and pass the census.
  - Update every existing self-test fixture and loop that enumerates the files: `good()` gets a `dockerfile` entry and its `ci` fixture drops to TWO install lines; the `empty` fixture in row 5 gets `dockerfile: ""`; the `["ci","monitor","renderSh","lib"]` loops in rows 6 and in the age-floor / must-PASS tests gain `"dockerfile"` (otherwise "moved together to another date" reads "dates differ" on a correct tree and the exact-3-day case goes red).
  - ci.yml cardinality test: 3 becomes 2; add Dockerfile cardinality 1.
  - Correct `BUMP_HINT` / the age wording: a date-only `--before` is midnight-exclusive, so the date must be the day AFTER the version's publish day.
  - Structural test as a pure, fixture-fed `checkImageStructure(dockerfile, ci)` (so the mutation rows can be driven from strings, not live files): a `FROM`-stage slicer must examine 4 stages (`deps`, `builder`, `cli-tools`, `runner`); `cli-tools` is `FROM node:22-slim@sha256:...` (never `FROM builder`, whose `SENTRY_AUTH_TOKEN` ARGs would inherit) and its slice holds exactly one likec4 install plus the claude-code install; the `runner` slice holds zero `npm install -g`; `runner` is `FROM cli-tools` and the LAST `FROM` (the release builds the default target). The ci.yml side parses the file with the `yaml` package (already an app dependency) and finds the `web-platform-build` step as ONE object: `uses` is `docker/build-push-action`, `with.target` is `cli-tools`, `with.no-cache` is true, and the step has no `if`, no `continue-on-error`, no `with.secrets`, `secret-files`, `build-args` or `cache-to`/`cache-from` (secret-free by construction; this also kills a commented-out or split step).
  - Add a `moveDate(files, from, to)` helper that maps over every key of `good()` and use it in rows 6, the age-floor and the must-PASS tests, so a future site cannot be skipped; rename "three" in the row-1 test name and the cardinality comment to match the new counts; add a Dockerfile census row (`RUN npm i -g likec4@...` is flagged as unrecognised) and a note that the install must be single-line (a `\\` continuation with `--before` on the next line is a false RED; require the single-line form in `BUMPING LIKEC4`). Initialise `dockerfile` to `""` in the harness row so the failure is the cardinality assertion, not a TypeError.
  - Do not quote the literal `npm install -g likec4@<digit>` command in any new comment in the Dockerfile, ci.yml or the BUMPING text: the version-parity tests use a first-match regex over the raw file (comments included) and the ci.yml parity test uses `matchAll` over raw text.
- `apps/web-platform/test/server/inngest/claude-cli-pin-knows-models.test.ts` (existing file, keep it app-local: read only under the app root, so `repo-wide-containment.test.ts` stays green): add a fixture-fed helper `checkClaudeCodeLock(lock, pin)` plus a real-file test, in the describe block that runs on every host (not the `skipIf` one). It asserts: the `node_modules/@anthropic-ai/claude-code` entry's `version` equals the package.json pin (otherwise a pin bump with a stale lock keeps it green on stale evidence); the entry has no `dependencies` and no `peerDependencies`; every `optionalDependencies` value equals the entry's own `version` exactly; the platform entry keys equal the `optionalDependencies` keys, each with the `@anthropic-ai/claude-code-` prefix, and each has no `dependencies`. State inline the assumption that makes the lock valid evidence for a global install (the Dockerfile pin equals the package.json pin, asserted by this file's existing test) and the documented residual that the entry carries `hasInstallScript: true`, which the assertion does not cover.
- `plugins/soleur/test/scripts-shard-runtime-coverage.test.sh`: run the `likec4` row for the light job only (a change in the job loop plus a comment saying why: no heavy registration invokes likec4, every consumer falls back to `npx`, and the pin test's ci.yml install count of 2 catches a silent re-add). Make the mutation rows drivable: `check_runtime` takes the users directory and a `required` flag as arguments (`likec4` is `required=1`, so an empty users list is a failure; `bun` and `gitleaks` keep SKIP), returns a status instead of bumping the global `FAIL`, and the self-check calls it in a subshell against fixtures; strip comment lines from the block before the install-marker grep (today a keep-decision comment containing the marker would satisfy it after the real step is deleted, which is a surviving mutation). Assert the real light users list is non-empty and includes `render-c4-model.test.sh`. Scope note for the suite header: the user scan is one level deep (a suite that sources a helper which invokes likec4 is invisible), as for the other rows. Leave the `bun` and `gitleaks` rows untouched (tracked in issue 9497).

### Phase 2 — Dockerfile

- `apps/web-platform/Dockerfile`: insert the `cli-tools` stage between `builder` and `runner` (`FROM node:22-slim@sha256:4f77a690... AS cli-tools`, the claude-code `RUN` unchanged byte for byte, then `RUN npm install -g likec4@1.50.0 --before=2026-09-28`), and change the runner's first line to `FROM cli-tools AS runner`. Move the two install comment blocks with their `RUN` lines (the `FROM … AS runner` line and the CACHE-ORDERING INVARIANT comment stay at the top of runner; renumber the "Stage 3" comment). Update the CACHE-ORDERING comment to say the heavy installs now live in the `cli-tools` ancestor and still sit above every `ENV BUILD_*`. One-line comment on the likec4 line: the date must equal `LIKEC4_BEFORE` (render-c4-model.sh) and the stage is built per PR by `web-platform-build`. One-line comment on the claude-code line: no `--before` because the tree is two exact-pinned packages (asserted in `claude-cli-pin-knows-models.test.ts`). Do not touch builder-stage lines. Neither the Dockerfile nor `reusable-release.yml` sets a custom npm registry (checked), so `--before` is not inert in the release build.
- `scripts/lint-workflow-install-sites.sh` (header BOUNDARY comment only) and `knowledge-base/engineering/architecture/decisions/ADR-191-npm-single-lockfile-of-record.md` (one sentence appended to the 2026-09-13 amendment): the `web-platform-build` job now also builds the Dockerfile `cli-tools` stage, which runs `npm install -g` with lifecycle scripts enabled in the same discarded, secret-free buildkit container, a second install site this lint's `run:`-only scan cannot see. Re-run `scripts/lint-workflow-install-sites.test.sh` afterwards (its H3 asserts the boundary text).
- `plugins/soleur/scripts/render-c4-model.sh`: `BUMPING LIKEC4` only: add the Dockerfile to step 2's site list, delete the "Deliberately version-only ... #9343" clause (package.json and the validate recipes remain version-only), state in step 1 that a date-only `--before` is midnight-exclusive so the date must be the day AFTER the version's publish day (illustrate with the claude-code example as an example, not a likec4 fact), and add one line that a claude-code bump needs no date but `claude-cli-pin-knows-models.test.ts` must stay green. No literal install command in the added prose.

### Phase 3 — Workflow

- `.github/workflows/ci.yml`:
  - `web-platform-build`: add a step after the builder build, `Build the Dockerfile cli-tools stage (registry resolution, no cache)`, `timeout-minutes: 5`, `docker/build-push-action` at the SHA already pinned in that job, `context: apps/web-platform`, `target: cli-tools`, `push: false`, `load: false` (explicit, matching the sibling step), `no-cache: true`. Update the job's header comment: the extra step (about 60 s) and why the runner stage is not built per PR (one line); refresh the "1m52s ... >=5x headroom" wording against the 10-minute timeout.
  - `test-scripts-heavy`: delete the `Install likec4 CLI (pinned ...)` step; one comment line saying no heavy registration invokes likec4.
  - `test-webplat`: replace the "Dockerfile install is version-only on purpose for now (#9343)" sentence with one saying the Dockerfile `cli-tools` stage carries the same pair.
  - `test-scripts`: one comment line recording the keep decision (three `npx` consumers; the install is their download-cache warm-up).
- No other workflow file changes (`main-health-monitor.yml` keeps its install: it asserts `command -v likec4`).

### Phase 4 — Records

- `knowledge-base/engineering/architecture/decisions/ADR-050-likec4-runtime-rerender-via-out-of-process-cli.md`: a short dated addendum, three or four sentences (see Architecture Decision).
- `knowledge-base/engineering/operations/runbooks/ci-test-scripts-sharding.md`: the line "toolchain parity asserted on both jobs (bun, likec4, gitleaks)" becomes "(bun, gitleaks on both jobs; likec4 on test-scripts only)".

### Phase 5 — Verification (local, before pushing)

- `cd apps/web-platform && ./node_modules/.bin/vitest run test/c4-likec4-version-pin.test.ts test/server/inngest/claude-cli-pin-knows-models.test.ts test/playwright-mcp-version-pin.test.ts test/dockerfile-runner-ssh-client.test.ts test/server/inngest/sentry-monitor-iac-parity.test.ts test/repo-wide-containment.test.ts` (runner is vitest per `package.json` `test:ci`; the baseline form of this command was run on this branch before any edit: 5 files, 60 passed, 1 skipped). Then `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`.
- `bash plugins/soleur/test/scripts-shard-runtime-coverage.test.sh` (baseline on this branch: 14 passed, 0 failed); `bash plugins/soleur/test/c4-count-parity.test.sh`; `bash scripts/lint-workflow-install-sites.sh` (and its `.test.sh`); `bash apps/web-platform/scripts/lib/in-image-copy-src.test.sh` (digest parity across the now-two pinned `FROM` lines).
- `docker build --no-cache --target cli-tools apps/web-platform` locally (about 35-60 s), then one full `--target runner` build on a vendored copy of the context to confirm `FROM cli-tools AS runner` yields the same layer list, with the claude-code layer `CACHED` on a second run.
- Post-merge (read-only): `gh run list --workflow web-platform-release.yml --limit 3` and confirm the first release after merge is green.

## Files to Edit

- `apps/web-platform/Dockerfile` (new `cli-tools` stage; `--before` on the likec4 line; `runner` is `FROM cli-tools`; comments)
- `.github/workflows/ci.yml` (**workflow edit — no admin merge**: new step in `web-platform-build`; remove heavy install; comments)
- `apps/web-platform/test/c4-likec4-version-pin.test.ts` (Dockerfile as a site; fixtures and loops; cardinalities; structural test)
- `apps/web-platform/test/server/inngest/claude-cli-pin-knows-models.test.ts` (lock assertion)
- `plugins/soleur/test/scripts-shard-runtime-coverage.test.sh` (`likec4` row light-only; light users non-empty)
- `plugins/soleur/scripts/render-c4-model.sh` (`BUMPING LIKEC4` comment only; no behavior change)
- `knowledge-base/engineering/architecture/decisions/ADR-050-likec4-runtime-rerender-via-out-of-process-cli.md` (addendum)
- `knowledge-base/engineering/operations/runbooks/ci-test-scripts-sharding.md` (one line)
- `scripts/lint-workflow-install-sites.sh` (BOUNDARY comment only) and `knowledge-base/engineering/architecture/decisions/ADR-191-npm-single-lockfile-of-record.md` (one sentence)

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-9343-pin-release-image-transitives/tasks.md`
- `knowledge-base/project/specs/feat-one-shot-9343-pin-release-image-transitives/decision-challenges.md` (plan-review dissent record, for ship to surface)

Glob/path check: every path above was verified with `git ls-files` or `ls` in this worktree except the two Files-to-Create entries. `.github/actions/**` is not touched.

## Open Code-Review Overlap

None. Queried open `code-review` issues (limit 200) against every file in the two lists above (`apps/web-platform/Dockerfile`, `.github/workflows/ci.yml`, `c4-likec4-version-pin.test.ts`, `scripts-shard-runtime-coverage.test.sh`, `render-c4-model.sh`, ADR-050, `claude-cli-pin-knows-models.test.ts`); no issue body names any of them.

## Open draft PR 7390 — merge-conflict surface

PR 7390 (draft, stale since 2026-09-21, branch `feat-one-shot-7389-provenance-buildarg-secret`) edits `apps/web-platform/Dockerfile` for an unrelated build-arg provenance concern, in the builder stage (about lines 21-50: the `SENTRY_AUTH_TOKEN` ARG block and a secret-mount on `RUN npm run build`). This plan edits the stage boundary right after the builder (the new `cli-tools` stage and the `runner` `FROM` line, about lines 41-79). Expect an adjacent-hunk textual conflict if both land; resolution is mechanical (keep both hunks). This PR does not touch, rebase or comment on 7390, and touches no builder-stage line. The CTO's advice: this PR should merge first.

## Architecture Decision (ADR/C4)

### ADR

Amend ADR-050 with a short dated addendum (three or four sentences), as an in-scope task of this plan (Phase 4, plan Phase 2.10 rule `wg-architecture-decision-is-a-plan-deliverable`), not a follow-up: the install-layout invariant (global install rather than a lock, 5 of 15 `c4-render-tenant-config` tests fail on a hoisted layout), the `--before` pairing now covering the image via the Dockerfile `cli-tools` stage, claude-code deliberately having no `--before` (two exact-pinned packages, asserted in `claude-cli-pin-knows-models.test.ts`), and that `--before` bounds recency, not integrity (a global install has no lock hashes, so the registry is trusted at install time). No new ADR: this extends an existing decision and reverses none.

### C4 views

No C4 impact, checked against all three model files (`knowledge-base/engineering/architecture/diagrams/{model,views,spec}.c4`): (a) external human actors: none are involved in a build-time install; (b) external systems/vendors: `github` (CI/CD and releases) and `ghcr` (the private image registry the release publishes to) are already modeled and the publish edge is unchanged; the public npm registry is not modeled, and the existing `npm ci` / `npm run build` registry fetches in the same Dockerfile are equally unmodeled, so pinning adds no new edge; (c) containers/data stores: the image's contents change by tree version only, no new container; (d) actor-to-surface access relationships: none change. `plugins/soleur/test/c4-count-parity.test.sh` stays in the Phase 5 run to back the conclusion for derived cardinalities.

### Sequencing

None. The ADR addendum describes current state and ships in this PR.

## Domain Review

**Domains relevant:** Engineering

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Real CTO-agent assessment run; rulings recorded in "CTO Assessment" (flag not lock; no `--before` on claude-code with a lock tripwire; `cli-tools` stage plus a no-cache build step in `web-platform-build`; keep the light-shard install, remove the heavy one with a scoped contract; ADR-050 addendum; one non-admin-merged PR). No Product/UX surface (no UI files), no legal, finance, marketing, sales, support or operations implication.

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing directly. The failure mode is a failed release build (the deploy step is skipped and production keeps serving the last good image, as the Dockerfile's `GH_VERSION` comment records for a prior rolling-repo expiry), or a CI check going red on a PR. No user-facing artifact changes.
- **If this leaks, the user's data is exposed via:** no exposure vector. No secret, credential, or user data is read or written; the new `cli-tools` stage has no ARGs or secrets and the step pushes and loads nothing.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** `none` rather than `aggregate pattern`: the change is build-time supply-chain hygiene whose blast radius is a delayed deploy, and the diff touches no preflight sensitive path (`apps/web-platform/Dockerfile`, `ci.yml` and the test files do not match the canonical regex).

`threshold: none, reason: build-time dependency pinning and CI-shard hygiene; no runtime, auth, data or user-facing path is touched, and the only failure mode is a delayed deploy that leaves production on the last good image.`

## Observability

```yaml
liveness_signal:
  what: "web-platform-build cli-tools step (a no-cache build of the two global installs against the live npm registry) plus the two pin-parity vitest files"
  cadence: "every pull_request and every merge_group run"
  alert_target: "red web-platform-build rolls up into the required test aggregator check on the PR"
  configured_in: ".github/workflows/ci.yml (job web-platform-build) and apps/web-platform/test/c4-likec4-version-pin.test.ts"
error_reporting:
  destination: "GitHub Actions check annotations and step logs (build-time only; no Sentry surface exists for a Docker build step)"
  fail_loud: "npm error code ETARGET or E404 line in the cli-tools step log, a red web-platform-build job, and a red test aggregator"
failure_modes:
  - mode: "likec4 version and --before date drift apart so the pair cannot resolve (ETARGET)"
    detection: "cli-tools build step fails on the PR that moves one without the other; checkLikec4Pins also fails on any date mismatch"
    alert_route: "PR author via the red required check"
  - mode: "a CDN-lag 404 on a transitive tarball"
    detection: "effectively removed for the frozen date (tarballs at least a week old); if it recurs the same cli-tools step fails"
    alert_route: "PR author via the red required check; release run web-platform-release.yml fails at the image build if it first appears there"
  - mode: "registry mirror serves no per-version publish times so --before is silently inert"
    detection: "no automatic detection (documented residual in BUMPING LIKEC4); the build uses registry.npmjs.org by default"
    alert_route: "none automatic; recorded in ADR-050 addendum"
  - mode: "a claude-code bump introduces a floating dependency"
    detection: "the lock assertion in claude-cli-pin-knows-models.test.ts fails on the bump PR"
    alert_route: "PR author via the red test-webplat check"
  - mode: "claude-code bump PR pulls a version published minutes earlier into the required cli-tools step (CDN lag, no --before on that line)"
    detection: "cli-tools step red with E404 or ETARGET on the bump PR"
    alert_route: "PR author via the red required check; a rerun clears CDN lag (accepted residual)"
logs:
  where: "GitHub Actions run logs for CI and web-platform-release.yml"
  retention: "GitHub default workflow-log retention (90 days)"
discoverability_test:
  command: grep -cE "^RUN npm install -g likec4@1\.50\.0 --before=[0-9]{4}-[0-9]{2}-[0-9]{2}" apps/web-platform/Dockerfile
  expected_output: 1
```

The probe prints `0` on this branch until Phase 2 lands and `1` afterwards (run during planning: `0`); `probe-verb-gate.sh` accepted the command (rc 0) during deepen.

## Guard Contract

Three guards are in the deliverable: the extended likec4 pin scanner, the claude-code lock assertion, and the narrowed shard-coverage contract. The matrices were written from the design before any of the three changed.

### Guard 1 — likec4 pin scanner covers the Dockerfile

**Property.** Every place a likec4 tree is resolved (the Dockerfile `cli-tools` install, the two remaining ci.yml installs, the monitor install, the renderer script and the TS producer) carries the same `--before` date, at least 3 days old, as a pair with the pinned version.

**Assembly.** Chokepoint: `checkLikec4Pins` in `apps/web-platform/test/c4-likec4-version-pin.test.ts` over `readPinFiles()`; sites are derived by `extractInstallLines` over the Dockerfile, ci.yml and the monitor, plus the `export json` lines of the renderer and the producer, never a fixed count. More than one chokepoint exists on purpose: the scanner (dates and flag), the cardinality tests (ci.yml count 2, Dockerfile count 1, so a deleted or added site cannot pass silently), and the live `cli-tools` build step (the only oracle that resolves the pair against the real registry). A new site spelled another way is caught by the census in the scanner. `.github/workflows/main-health-monitor.yml` keeps its install and stays in the assembly.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Remove `--before=...` from the Dockerfile likec4 line (flag only in a trailing comment) | RED: Dockerfile install line has no --before |
| 2 | Dockerfile date differs from the other sites by one day | RED: dates differ across sites |
| 3 | Add a second COMPLIANT `npm install -g likec4@1.50.0 --before=<same date>` line after the first, in the Dockerfile | RED: expected exactly one Dockerfile install line (assert this message specifically, so deleting the cardinality check cannot hide behind the missing-flag message) |
| 4 | Feed an empty Dockerfile string while the other four files are canonical (the scanner's own dispatch) | RED: no non-comment install line found |
| 5 | Image structure, driven through `checkImageStructure` fixtures: move the likec4 `RUN` into `runner`; make `runner` not the last `FROM`; make `cli-tools` `FROM builder`; drop `no-cache: true`, comment the step out, add `if: false`, `continue-on-error: true`, `build-args` or `cache-to` to it | RED for each |

**Harness rows.** Suite edit that MUST turn it RED: remove `dockerfile` from `readPinFiles()` (the real-file Dockerfile cardinality assertion then fails). Must-PASS input that is not the canonical: every site, Dockerfile included, moved together to another valid old date (for example `2026-09-29`).

**Anchor.** The stored value (the date) is compared across sites by the scanner, which proves consistency not resolvability. The independent oracle outside the commit is the registry: the PR-time `cli-tools` no-cache build re-resolves the pair against `registry.npmjs.org` on every PR and ETARGETs if the date predates the version's publish time. A same-commit edit of every date to a wrong value therefore cannot pass.

### Guard 2 — claude-code install tree stays two exact-pinned packages

**Property.** The `@anthropic-ai/claude-code` lock entry has no `dependencies`, every optionalDependency equals the entry's own version exactly, and every `claude-code-*` platform entry has no `dependencies`.

**Assembly.** Chokepoint: one test in `claude-cli-pin-knows-models.test.ts` over `apps/web-platform/package-lock.json` `packages`, selecting entries by key pattern `node_modules/@anthropic-ai/claude-code` and `node_modules/@anthropic-ai/claude-code-*` (derived, so a ninth platform package is covered). One lock location exists (ADR-191). The Dockerfile-equals-lock binding is already enforced by this file's existing pin test and is not repeated.

**Mutation matrix** (applied to a parsed copy of the lock inside the test's own fixture-fed helper):

| # | Mutation | Expected |
|---|---|---|
| 1 | Add `dependencies: {"left-pad": "^1.0.0"}` to the claude-code entry | RED |
| 2 | Change one optionalDependency to `^2.1.284` | RED |
| 3 | Add a new platform entry with a `dependencies` key after the compliant ones | RED |
| 4 | Lock with zero claude-code entries (the scanner's own dispatch) | RED: examined 0 entries |
| 5 | Lock entry version differs from the package.json pin (stale lock after a pin bump), or a platform entry key is missing from `optionalDependencies` / foreign to it | RED |

**Harness rows.** Suite edit that MUST turn it RED: change the key pattern to match nothing (the zero-entry assertion fires). Must-PASS input that is not the canonical: a lock with a ninth compliant platform package, and a lock plus pin both moved to another version together.

**Anchor.** The lock is a stored claim about the registry. The independent check is the bump itself: any new floating dependency enters the lock in the same PR that bumps the version, where this assertion reds before merge. Documented residual: `hasInstallScript: true` on the entry is not covered.

### Guard 3 — shard-coverage contract demands the likec4 install only where a suite needs the warm-up

**Property.** `test-scripts` (whose users include `render-c4-model.test.sh`) must carry the likec4 install; `test-scripts-heavy` is not asked for one because no heavy registration invokes likec4 and every consumer falls back to `npx`.

**Assembly.** Chokepoints: the light user set (`plugins/soleur/test/*.test.sh`, the existing glob), the `test-scripts` job block extraction in ci.yml, and the pin test's ci.yml install count of 2 (the cross-check that a silent re-add or a deleted light install is noticed). The heavy job is intentionally outside the `likec4` row; that choice is stated in the suite.

**Mutation matrix** (fixture-fed calls of `check_runtime` in a subshell, with a users-dir argument and a `required` flag, so no live file is mutated and the suite's own counters are untouched; the existing setup-bun self-check only proves `grep -v` removes a line and is not the model):

| # | Mutation | Expected |
|---|---|---|
| 1 | Remove the install step from a fixture light block | RED (`likec4` row fails) |
| 2 | Keep only a COMMENT containing the install marker in the block (step deleted) | RED (comment lines are stripped before the marker grep) |
| 3 | Empty users directory with `required=1` (the scanner's own dispatch) | RED: empty users list is a failure, not a SKIP |

**Harness rows.** Suite edit that MUST turn it RED: invert the non-empty assertion on the real light users list. Must-PASS inputs that are not the canonical: a light block carrying the install under a different step name; `required=0` with an empty users directory (bun and gitleaks behavior preserved: SKIP).

**Anchor.** The contract compares a ci.yml block to a suite glob that the same diff can edit; the independent cross-check is `c4-likec4-version-pin.test.ts` asserting exactly 2 install lines in ci.yml, which fails on a deleted light install or a re-added heavy one without a deliberate number change.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Dockerfile installs resolve with --before=<the repo's likec4 date> (or an equivalent lock)" [issue #9343] | Phase 2 Dockerfile edit; Guard 1; claude-code ruling in CTO Assessment | mapped |
| 2 | "with a PR-time check that builds the runner stage" [issue #9343] | Phase 2 `cli-tools` stage + Phase 3 `web-platform-build` step; Guard 1 rows 6-7 | mapped |
| 3 | "Either the vestigial installs are removed and the shard-coverage contract updated, or the decision to keep them is recorded" [issue #9343] | Phase 3 (remove heavy, record keep for light) + Guard 3 | mapped |
| 4 | "decide each with the CTO agent and record the decision" [brief] | CTO Assessment section | mapped |
| 5 | "state in the plan whether the change edits `.github/workflows/**` or `.github/actions/**`" [brief] | Overview, Merge policy | mapped |
| 6 | "note the likely merge-conflict surface" for PR 7390 [brief] | Open draft PR 7390 section | mapped |
| 7 | "read first, including the `BUMPING LIKEC4` procedure" [brief] | Phase 2 `render-c4-model.sh` edit | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `apps/web-platform/Dockerfile` edits | "Dockerfile installs resolve with --before=<the repo's likec4 date>" | asked |
| `.github/workflows/ci.yml` new step and heavy-install removal | "PR-time check that builds the runner stage" / "the vestigial installs are removed" | asked |
| `c4-likec4-version-pin.test.ts` edits | — | inferred — justification: the pin parity test is the only thing that keeps a new Dockerfile date from drifting from `LIKEC4_BEFORE`; without it the pin rots on the next bump (the predecessor PR's own contract) |
| lock assertion in `claude-cli-pin-knows-models.test.ts` | — | inferred — justification: the CTO ruled out `--before` for claude-code, and the "still zero floating transitives" fact must be a CI assertion or the issue's concern returns unobserved |
| `scripts-shard-runtime-coverage.test.sh` edits | "the shard-coverage contract updated" | asked |
| `lint-workflow-install-sites.sh` boundary comment and ADR-191 sentence | — | inferred — justification: both record that `build-push-action` Dockerfile installs are an accepted, secret-free exposure and name only the `builder` stage; the new `cli-tools` step makes that record stale (security review) |
| `ci-test-scripts-sharding.md` one-line edit | — | inferred — justification: the runbook states the contract's old behavior ("bun, likec4, gitleaks" on both jobs), which this PR makes false |
| `render-c4-model.sh` comment edit | "the `BUMPING LIKEC4` procedure" | asked |
| ADR-050 addendum | — | inferred — justification: AGENTS `wg-architecture-decision-is-a-plan-deliverable`; a pin-policy extension that a future reader would otherwise reverse with the rejected lock |
| `tasks.md` | — | inferred — justification: the plan skill's Save Tasks contract |

### Split Assessment

- Subsystems touched: 5 — `apps/web-platform` (Dockerfile + tests), `.github/workflows`, `plugins/soleur` (test + script comment), `scripts` (lint comment), `knowledge-base/engineering` (ADRs + runbook)
- Planned files: 12 (10 edited, 2 created: tasks.md and decision-challenges.md) | Estimated changed lines: about 260 (mostly tests and comments)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR — the subsystem-root count meets the threshold on the nose but every piece is one coupled change (the pin trio, its guard, its PR-time build, its contract and its record); a split would leave stale "version-only (#9343)" comments live in either half.

## Acceptance Criteria

### Functional

- [ ] `grep -cE "^RUN npm install -g likec4@1\.50\.0 --before=2026-09-28" apps/web-platform/Dockerfile` prints `1`, and the Dockerfile has `FROM cli-tools AS runner` as its last `FROM`, with both `npm install -g` lines inside the `cli-tools` stage and above any `ENV BUILD_`.
- [ ] The claude-code `RUN` line text is byte-identical to before (`RUN npm install -g @anthropic-ai/claude-code@2.1.284`), carries no `--before`, and a one-line comment records why.
- [ ] `web-platform-build` in ci.yml has a `docker/build-push-action` step with `target: cli-tools`, `no-cache: true`, `push: false`, `load: false`, `timeout-minutes: 5`; no new job and no path gate were added; the job's existing builder step is unchanged.
- [ ] The `test-scripts-heavy` job has no likec4 install step; `test-scripts` still has exactly one; the pin test's `extractInstallLines(ci)` cardinality assertion is `2` (test-webplat, test-scripts). New comments in the Dockerfile, ci.yml and `BUMPING LIKEC4` do not quote the literal install command.
- [ ] `c4-likec4-version-pin.test.ts` treats the Dockerfile as a site (cardinality 1, same date, flag required); its fixtures and date-replacement loops include the Dockerfile; its structural test asserts `runner` is the last `FROM` and is `FROM cli-tools`, and that the `web-platform-build` job has the `cli-tools` step with `no-cache: true`.
- [ ] `claude-cli-pin-knows-models.test.ts` carries the lock assertion (no `dependencies` on the claude-code entry and its platform entries; every optionalDependency equals the entry's version) and `repo-wide-containment.test.ts` stays green.
- [ ] `plugins/soleur/test/scripts-shard-runtime-coverage.test.sh` passes, runs the `likec4` row for `test-scripts` only, fails (not SKIPs) when the light users list is empty, and each Guard 3 mutation/harness row is demonstrably RED when applied (record each as a run in the PR body). The `bun` and `gitleaks` rows are unchanged.
- [ ] `BUMPING LIKEC4` no longer says the Dockerfile is version-only; it lists the Dockerfile as a literal-date site and states the midnight-exclusive date rule. `git grep -n '#9343' -- .github plugins apps scripts` returns nothing (today it has exactly two hits: `.github/workflows/ci.yml` and `plugins/soleur/scripts/render-c4-model.sh`; the search excludes `knowledge-base/` so the plan and ADR may cite the issue).
- [ ] ADR-050 has a dated addendum covering the three points under Architecture Decision, and the `ci-test-scripts-sharding.md` line no longer claims likec4 parity on both jobs.
- [ ] The keep decision for the `test-scripts` install is recorded as a one-line ci.yml comment; the removal rationale for the heavy job is a one-line comment in that job. The measured numbers live in this plan and the PR body.

### Non-functional / process (pre-merge)

- [ ] This PR is merged through the normal path (not `--admin`) because it edits `.github/workflows/ci.yml`; PR body says so and says `Closes #9343`.
- [ ] PR body states: the first release after merge rebuilds from the likec4 layer onward (about 5-6 min, one-time), that "builds the runner stage" is met by its ancestor `cli-tools` stage with the measured rationale (the acceptance wording differs: say so on the issue), and the recorded DHH/code-simplicity dissent on removing the heavy install.
- [ ] No builder-stage Dockerfile line changed (PR 7390 conflict surface): `git diff origin/main...HEAD -- apps/web-platform/Dockerfile` has no hunk that touches a line before the old `# Stage 3` comment.
- [ ] Phase 5 verification commands all exit 0.

### Post-merge (automated read-only check, no operator step)

- [ ] The first `web-platform-release.yml` run after merge is green. Automation: `soleur:ship` / `soleur:postmerge` read-only `gh run list --workflow web-platform-release.yml --limit 3 --json conclusion,createdAt,displayTitle` (run once against live data while planning: returns the last runs with `conclusion` populated). Expect one cold rebuild of about 5-6 min; a failure here is a release-build regression, not a deploy of a bad image (the deploy step is skipped and production keeps the last good image).

## Test Scenarios

- Given the Dockerfile likec4 line loses its `--before`, when `c4-likec4-version-pin.test.ts` runs, then it fails naming the Dockerfile.
- Given a bump of `LIKEC4_BEFORE` in the scripts but not in the Dockerfile, when the pin test runs, then "dates differ across sites" fails; and when only the Dockerfile date is moved to a pre-publish date, then the `cli-tools` build step fails with ETARGET.
- Given `--before=2026-09-28` is applied to claude-code 2.1.284 in the pinned image, then npm exits ETARGET (recorded measurement; the reason there is no flag on that line).
- Given the light job's likec4 install step is removed, when the shard-coverage contract runs, then it fails; given the light users list is empty, then it fails instead of skipping.
- Given a claude-code bump adds a `dependencies` key to its lock entry, when `claude-cli-pin-knows-models.test.ts` runs, then it fails on the bump PR.
- Given the PR runs on `merge_group`, then `web-platform-build` (and the new step) runs and reports into `test`; the context set is unchanged.

## Dependencies & Risks

- **First-release cost.** The likec4 `RUN` edit invalidates that layer and every later one once: playwright (about 106 s), apt, `npm ci --omit=dev`. First release after merge about 5-6 min; later releases hit the gha cache again because the heavy layers stay above `ENV BUILD_*`.
- **Stage split must preserve cache keys.** `cli-tools` shares the base image and the two `RUN` command strings, so BuildKit cache keys for the claude-code layer are unchanged; verify with a second local `docker build` showing `CACHED` for it. The release builds the default target, so `runner` must stay the last stage (asserted by the structural test).
- **Frozen tree.** The image now ships the 2026-09-28 likec4 tree rather than "newest at last cache bust". Policy (from `BUMPING LIKEC4`): the date moves with a likec4 bump, or sooner if a transitive advisory affects the CLI; the owner is whoever bumps likec4 or triages a CLI advisory, and nothing alerts automatically (stated, not hidden). The CLI renders tenant input inside bubblewrap (ADR-050 and the #8623 addendum), which bounds the exposure.
- **Mirror caveat.** `--before` is inert against a registry that serves no per-version publish times. Checked: neither the Dockerfile, `.npmrc` nor `reusable-release.yml` sets a custom registry, so the release build uses `registry.npmjs.org`.
- **Fresh claude-code on a bump PR.** The `cli-tools` step pulls a claude-code version that may have been published minutes earlier (`model-launch-review` repins to fresh releases; `.npmrc` `min-release-age=3` only protects lock regeneration), so the #9300 CDN-lag failure can recur in a required check on exactly those PRs. Accepted: a rerun clears it, and `--before` on that line would ETARGET.
- **Lifecycle scripts on `pull_request`.** The `cli-tools` step runs `npm install -g` with scripts enabled (claude-code has `hasInstallScript: true`) on fork PRs, in a discarded, secret-free buildkit container with `permissions: contents: read`; the structural test pins that the step carries no secrets, build-args or cache export.
- **claude-code `hasInstallScript`.** The lock entry carries `hasInstallScript: true`; the lock assertion does not cover it (documented residual).
- **`dockerfile-runner-ssh-client.test.ts` slicing.** It slices from `FROM … AS runner` to the next `FROM`; the apt packages stay in the runner slice, so it should stay green; it is in the Phase 5 run list.
- **Digest parity.** `apps/web-platform/scripts/lib/in-image-copy-src.test.sh` requires at least one pinned `FROM node:22-slim@sha256` line and one distinct digest across the Dockerfile and two helpers; `deps` and `cli-tools` carry the same digest and `runner` inherits. In the Phase 5 run list.
- **First-match parity regexes.** The existing version-parity tests regex the raw Dockerfile and ci.yml text, comments included; a new comment quoting a different version would break them (hence the no-literal-command rule in Phase 1).

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold fails `deepen-plan` Phase 4.6; this plan fills it with a `none` threshold and a stated reason.
- The `--before` value is a calendar date meaning 00:00 UTC. A version published at 17:11Z on day D needs a date of D+1 or later; this is the reason claude-code 2.1.284 cannot share the likec4 date and the reason the BUMPING procedure gets a one-sentence rule.
- Do not "simplify" `cli-tools` away by building `--target runner` in CI without first re-measuring: the +4 min and three external dependencies are the recorded reason it was rejected.
- Do not move any `ENV BUILD_*` or other per-commit-volatile line above the `cli-tools` installs.

## Non-Goals and Tracked Deferrals

- The `bun` and `gitleaks` rows of `scripts-shard-runtime-coverage.test.sh` have the same all-suites over-approximation for `test-scripts-heavy` (the baseline run printed `'gitleaks' is invoked by 1 suite(s) (gitleaks-merge-commit.test.sh) and installed in test-scripts-heavy`). Only the `likec4` row is in scope here. Tracked as issue 9497 (priority/p3-low, `meta/machinery`, milestone Post-MVP / Later), to reuse the per-job user-list mechanism built in Guard 3.
- `.github/workflows/main-health-monitor.yml` keeps its likec4 install (it asserts `command -v likec4` on PATH; a real PATH consumer).
- No change to the claude-code `RUN` line, to `package.json`, or to the C4 model.
- Advisory coverage for the frozen likec4 tree (no manifest, invisible to Dependabot, no `npm audit` or OSV job): tracked as issue 9498 (priority/p3-low, `meta/machinery`, milestone Post-MVP / Later). Until then the owner is whoever bumps likec4 or triages a CLI advisory.
- Not edited on purpose, recorded as accepted-stale: the `mode=min` wording in `reusable-release.yml` and `ci.yml` ("runner-stage layers"; the heavy layers now sit in the `cli-tools` ancestor but are still in the final image, so export behavior is unchanged; editing `reusable-release.yml` would also make this a release-workflow change), the install hints in `apps/web-platform/server/c4-render.ts` and `apps/web-platform/test/c4-render-tenant-config.test.ts` (they print the install without `--before`, which still works; `apps/web-platform/server/**` is a sensitive path this chore should not touch), and the "lives in three places" comment in `scripts/lib/test-relevance-paths.sh`.

## References & Research

- Issue 9343; PR 9338 (predecessor, merged), issue 9300; PR 7390 (stale draft); PR 9496 (this pipeline's draft PR).
- `plugins/soleur/scripts/render-c4-model.sh` (`BUMPING LIKEC4`), `apps/web-platform/test/c4-likec4-version-pin.test.ts`, `plugins/soleur/test/scripts-shard-runtime-coverage.test.sh`, `scripts/suite-shard-legs.tsv`, `scripts/test-all.sh` (`want_scripts_heavy` region), `.github/workflows/ci.yml`, `.github/workflows/reusable-release.yml`.
- ADR-050, ADR-191.
- Measurements reproduced locally with `docker build` / `docker run` against `node:22-slim@sha256:4f77a690...` (npm 10.9.4), 2026-10-04.
