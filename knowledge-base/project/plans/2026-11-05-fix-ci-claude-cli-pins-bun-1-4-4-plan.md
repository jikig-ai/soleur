---
title: "fix: CI claude CLI pins below the Bun 1.4.4 fix (marketplace-drift CLI, claude-code-action, pen-cli lock)"
date: 2026-11-05
slug: ci-claude-cli-pins-bun-1-4-4
branch: feat-one-shot-12102-ci-claude-cli-pins
issue: 12102
closes: 12102
type: fix
lane: single-domain
brand_survival_threshold: aggregate pattern
---

## Enhancement Summary

**Deepened on:** 2026-11-05
**Sections enhanced:** Phase 2 (input-drift result pre-measured), Phase 3 (scratch regeneration measured), Sharp Edges, verification pass over every cited SHA, PR/issue number and label.
**Method:** inline gate and verification pass (halt gates 4.6, 4.8, 4.12 and the Quality Checks list) plus one CTO ruling batch at plan time; the wide per-skill/per-agent fan-out was not run because the change is a three-site pin bump with measured evidence and CTO rulings F1-F4.

### Key Improvements
1. The claude-code-action input diff v1.0.236 to v1.0.263 was measured now: identical input lists, so the main risk of the 27-release bump (a renamed or removed `with:` key) is retired at plan time; the work phase only re-confirms.
2. Every cited SHA was resolved live and length-checked (all 40 chars): tag object `3b7e1a45...` is an annotated tag for v1.0.263 peeling to commit `8041f1d1...`; the old pin `20f0b248...` is the v1.0.236 tag object.
3. Labels `meta/machinery`, `domain/engineering`, `type/security`, `deferred-scope-out`, `semver:patch` all exist; PR 12073 is MERGED, #12026 CLOSED, PR 12136 is this branch's draft; PR 10926 is now CLOSED (still out of scope, no action).

### New Considerations Discovered
- The pen-cli regeneration was dry-run in a scratch copy under npm 11.20.0: only the nine SDK entries and the SDK's `engines.node` change; the work phase must still regenerate under npm 11.21.1 (CI's pin) before committing.
- Halt gates: 4.6 pass (section present, threshold `aggregate pattern`), 4.8 pass (no PAT-shaped variables), 4.12 pass (one unfenced `## Scope Check`), 4.7 pass (Observability present; discoverability command `grep ...` is allowlisted, finishes well inside 15 s, expected output is a literal that works once Phase 1.3 lands), 4.9/4.10/4.11/4.13 not triggered (no UI surface, no store/connection, no new guard, no new autonomous task). No AGENTS rule IDs are cited in the plan body.

## Overview

Issue #12102 tracks the claude runtime pins that PR 12073 deliberately left below the Bun 1.4.4 fix (CVE-2026-111497, a Brotli decoder flaw in Bun). Its dependency trigger (#12026) closed on 2026-11-05T00:52:09Z, so `scripts/followthroughs/ci-claude-cli-pins-bun-12073.sh` now reports ACTION REQUIRED (exit 5). This plan moves the remaining pins onto the shipped, already-verified pair (claude-code 2.1.311 / agent-sdk 0.3.311, Bun 1.4.4):

1. `scheduled-marketplace-drift.yml` `CLI_VERSION` 2.1.228 to exactly 2.1.311, with the plugin-delivery canary re-run against the new CLI first.
2. The `anthropics/claude-code-action` pin (four workflows plus the customer-facing constraint-scaffold template) from v1.0.236 to v1.0.263, the first release whose action runtime (Bun) and bundled CLI are both the shipped pair.
3. The pencil-setup engine lockfile's transitive agent-sdk 0.3.310 to 0.3.311 via an exact `overrides` entry, gated on `engine-contract-probe.sh`.

Do not redo the 12026 bump, the deploy checks, or the binary probe. PR body carries `Closes #12102`; label `meta/machinery`.

Premise-validation time check (2026-11-05 09:55 UTC, `date -u` equals the session clock): #12026 CLOSED at 00:52:09Z, #12102 OPEN, no merged PR closes #12102; the only open PR naming it is this branch's own draft PR 12136.

## Research Reconciliation — Spec vs. Codebase

| Brief / issue claim | Reality (measured 2026-11-05) | Plan response |
|---|---|---|
| "Bump CLI_VERSION and its pin-table test row" | `apps/web-platform/test/adhoc-npm-install-pin-table.test.ts` row for `scheduled-marketplace-drift.yml` is `{kind:"env", envVar:"CLI_VERSION"}`: value-agnostic, it carries no version number. The `literal` row for the Dockerfile already reads 2.1.311. | No numeric row to bump. The existing test must stay green with the new value (it asserts the env value is an exact semver). AC records "no test edit needed" so the work phase does not invent one. |
| "Bump via the `claude_code_version` input" | That input does not exist in claude-code-action v1.0.236 or v1.0.263 (inputs verified from `action.yml`; only `path_to_claude_code_executable` and `path_to_bun_executable` exist). v1.0.236 hardcodes `CLAUDE_CODE_VERSION="2.1.284"` in `base-action/action.yml` and installs Bun 1.3.14 via `oven-sh/setup-bun`. | The bump lever is the action SHA. CTO F2: bump to v1.0.263 (CLI 2.1.311, Bun 1.4.4). |
| "Four claude-code-action uses" | Five files carry the pin `20f0b248...`: the four workflows plus `plugins/soleur/skills/constraint-scaffold/references/fix-constraints-stage-a.template` (the customer-facing source of the `fix-constraints-stage-a.yml` dogfood copy). | Template is bumped in the same commit so the dogfood copy and its source stay in parity. |
| "Bump the pen-cli lockfile (agent-sdk 0.3.310 to 0.3.311 pair) if it ships to customers" | It ships: `check_deps.sh` copies `pen-cli/{package.json,package-lock.json}` to `~/.local/share/pen-cli` and runs `npm ci`. agent-sdk is a transitive dep of `@pen.dev/cli@0.3.13` (range `^0.3.293`); this lock holds no claude-code, so there is no "pair" to move, only the SDK and its eight platform optionals. | Exact `overrides` entry (precedent: undici, sharp, minimatch already there), lock regenerated under npm@11 (CTO F3). Scratch run confirmed the lock diff is only the nine SDK entries plus the SDK's own `engines.node` (`>=18.0.0` to `>=18.14.0`). |
| "Check each use for a bundled-Bun version; or record 'does not decode network Brotli'" | Bundled Bun is 1.3.14 (below the fix). Whether the jobs decode network Brotli stays unverified, but they hold secrets/OIDC and run the CLI with agent tools. | Bump (stricter option) instead of recording. The PR body states the Brotli question is unverified and moot after the bump. |
| `collision-precheck.sh 12102` (exit 10) | Hits: PR 12136 (this branch's own draft) and two `test-all.sh` processes owned by the `feat-one-shot-10390-ci-hygiene-batch` worktree. | Not a duplicate of this work. Noted; no action. |

## Research Insights

### Premise Validation
Checked: #12102 (open, labels incl. `follow-through`, `meta/machinery`), #12026 (closed 00:52:09Z), the probe script's exit semantics, the pin-table row shape, the action's input list at v1.0.236 and v1.0.263, release/tag history (first Bun-1.4.4 action release is v1.0.262, first with CLI 2.1.311 is v1.0.263, latest v1.0.268), the pen-cli lock/ranges, and the ADR corpus for the mechanism (ADR-182 and the runbook measured the delivery canary on CLI 2.1.228; ADR-191 owns lockfile/pin conventions). Held: the trigger fired, all three pin sites exist on `origin/main`. Stale: the `claude_code_version` input and the "pin-table test row" wording (see Reconciliation).

### Property List
- P1: no CI job installs or runs a claude CLI whose embedded Bun is below 1.4.4.
- P2: the delivery canary keeps proving what it proves (plugin content delivered intact) on the newer CLI.
- P3: the customer-installed pencil engine resolves agent-sdk 0.3.311 deterministically from the committed lock.
- P4: the follow-through tracker closes by itself (probe PASS) rather than by memory.

### Cut List
- A new numeric pin-table row for the env pin -> buys no property (the row is value-agnostic by design, ADR-191 pin-table guard) -> `adhoc-npm-install-pin-table.test.ts` already covers P1's "exact semver" half.
- A new Bun-floor guard for the CI sites -> P1 is already enforced for the shipped binaries by the standing test in `claude-cli-pin-knows-models.test.ts` (CTO F2 of #12026), and the CI sites are covered by the probe script plus the pin table; a second guard would duplicate it.
- `path_to_claude_code_executable` / `path_to_bun_executable` wiring (option B) -> more machinery for the same property the SHA bump buys.

### Institutional learnings applied
- `learnings/security-issues/2026-11-04-a-native-binary-carries-its-own-runtime-and-the-issues-probe-could-not-read-it.md`: use `strings <bin> | grep -m1 -E '^Bun v[0-9]+\.[0-9]+\.[0-9]+'`; a package version does not prove the embedded runtime.
- `learnings/2026-11-03-base-image-cve-bump-is-a-pin-census-not-a-digest-edit.md`: census every pin site; the template copy is the one the brief missed.
- `learnings/2026-04-18-action-pin-sync-with-model-bump.md`: action SHA pins and `--model` must stay compatible; all four uses pass `--model claude-sonnet-5-5` and v1.0.263 post-dates that model.
- `learnings/2026-05-22-npm-version-pin-required-for-lockfile-sync-gate.md` and `workflow-patterns/2026-06-30-update-branch-drifts-lockfiles-and-npm11-pin.md`: regenerate the lock under the CI-pinned npm 11.21.1 (the local npm is 11.20.0), not the operator's npm.
- `claude-code-action-auth.test.sh` header: the OIDC `id-token: write` / `github_token:` requirement is unchanged across versions; the census suite must stay green.

## Open Code-Review Overlap

None. (Queried open `code-review` issues against every planned file path; no body names any of them.)

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "should report ACTION REQUIRED until `.github/workflows/scheduled-marketplace-drift.yml` CLI_VERSION (currently 2.1.228) is >= 2.1.311. Bump CLI_VERSION and its pin-table test row." [brief] | Phase 1 | mapped (test row is value-agnostic; no edit, see Reconciliation) |
| 2 | "Check the four anthropics/claude-code-action v1.0.236 uses ... for a bundled-Bun version; either bump via the `claude_code_version` input or record 'does not decode network Brotli'" [brief] | Phase 2 | mapped (bump via action SHA; input does not exist) |
| 3 | "Bump `plugins/soleur/skills/pencil-setup/scripts/pen-cli/package-lock.json` (agent-sdk 0.3.310 -> 0.3.311 pair) if it ships to customers." [brief] | Phase 3 | mapped |
| 4 | "PR body must contain `Closes #12102`. Label meta/machinery." [brief] | Phase 5 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Canary re-run against 2.1.311 before merge | — | inferred — justification: CTO F1; the canary parses CLI output records and was measured on 2.1.228 only, so a version jump of 83 releases can silently change its input |
| constraint-scaffold template bump | "Check the four anthropics/claude-code-action v1.0.236 uses" | inferred — justification: the template is the source of the `fix-constraints-stage-a.yml` dogfood copy and ships to customers on the same vulnerable pin; leaving it creates dogfood/template drift |
| engine-contract-probe gate on the lock bump | "if it ships to customers" | inferred — justification: CTO F3; the probe's header requires it before an engine lockfile bump |
| Follow-up issue for `operator-digest.workflow.yml` (v1.0.101) | — | inferred — justification: CTO F4; same class, customer-facing, larger jump, so it is tracked instead of silently dropped |

### Split Assessment

- Subsystems touched: 2 (`.github/workflows`, `plugins/soleur`)
- Planned files: 8 edits (plus spec artifacts) | Estimated changed lines: about 70 excluding the lockfile (nine SDK blocks, about 40 lines)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## User-Brand Impact

- **If this lands broken, the user experiences:** a customer running the pencil-setup `--auto` install gets a failed or wrong `npm ci` of the headless Pencil engine (design tooling unavailable until fixed), or the maintainers' own PR review and drain automation stops running; no hosted-product surface changes. Only NEW `soleur:constraint-scaffold` installs receive the v1.0.263 template: the script refuses to overwrite an existing artifact, so repositories scaffolded earlier keep v1.0.236 until someone re-emits it (tracked in the follow-up issue).
- **If this leaks, the user's data is exposed via:** no new exposure vector; nothing here reads or writes user data. The pins reduce an existing risk (a Bun Brotli decoder flaw in runtimes that handle network responses).
- **Brand-survival threshold:** aggregate pattern
- **Threshold decision (challengeable):** a bad lockfile would affect every customer installing the engine (a pattern, not one user's data incident), and no tenant data or credential path is touched, so it does not reach single-user incident.

## Implementation Phases

Technical rulings are recorded in `knowledge-base/project/specs/feat-one-shot-12102-ci-claude-cli-pins/decision-challenges.md` (F1-F4, Ruled by CTO agent, 2026-11-05). Per the brief, CI's required `test` check is the gate; the local runs below are evidence for the rulings' flip conditions, not a substitute gate.

### Phase 0 - Baseline (read-only)

- 0.1 `date -u`; re-read #12026 state and `bash scripts/followthroughs/ci-claude-cli-pins-bun-12073.sh` with the ambient `gh` token (expected exit 5, ACTION REQUIRED).
- 0.2 Confirm `2.1.311` and `0.3.311` resolve under the repo's `min-release-age=3` (root has no `.npmrc` by design, ADR-191; `pen-cli` install is lockfile-bound).

### Phase 1 - marketplace-drift CLI pin (CTO F1)

- 1.1 Scratch install, outside the repo: `npm install -g --prefix "$SCRATCH/cli" "@anthropic-ai/claude-code@2.1.311"`; record `sha256sum` of the native binary (the 12026 evidence expects the shipped-pair hash `86dc1fcc...`) and run the corrected probe `strings <bin> | grep -m1 -E '^Bun v[0-9]+\.[0-9]+\.[0-9]+'` (expect `Bun v1.4.4`).
- 1.2 Run the canary against it with the repo's own seam: `CANARY_CLI="$SCRATCH/cli/bin/claude" bash scripts/plugin-delivery-canary.sh` (needs network; same environment variables the workflow step sets). Pass condition: `canary-counts` with `compared` > 0, no `installpath_unresolved`, exit 0. A failure blocks the merge; do not revert to 2.1.228 silently, stop and update the runbook/ADR-182 measurement text (CTO flip condition).
- 1.3 Edit `.github/workflows/scheduled-marketplace-drift.yml` line with `CLI_VERSION: "2.1.228"` to `"2.1.311"`. Keep the "Pinned, never latest" comment; add no version-specific prose.
- 1.4 No edit to `adhoc-npm-install-pin-table.test.ts`: run it once to prove the env row still satisfies (EXACT_RE on the new value).
- 1.5 Doc touch only if 1.2 shows behavior differences: ADR-182 and `plugin-delivery-recovery.md` cite "CLI 2.1.228" as the instrumented version; those are dated historical measurements and stay untouched when the canary is green.

### Phase 2 - claude-code-action v1.0.263 (CTO F2)

- 2.1 Re-resolve the target: `gh api repos/anthropics/claude-code-action/git/ref/tags/v1.0.263` must still return tag object `3b7e1a45ca6f231c62605aabcf79e6a41b08c7da`, and `base-action/action.yml` at that ref must still show `CLAUDE_CODE_VERSION="2.1.311"` and `bun-version: 1.4.4` (also in root `action.yml`). Keep the repo's tag-object SHA convention with comment `# v1.0.263`.
- 2.2 Input-drift check (CTO condition): diff `action.yml` inputs/outputs between v1.0.236 and v1.0.263 and confirm every `with:` key used in the five files (measured at plan time: `anthropic_api_key`, `claude_args`, `prompt` in all; `plugins` and `plugin_marketplaces` in claude-code-review and test-pretooluse-hooks; `github_token` in fix-constraints-stage-a) still exists. Deepen-plan pre-ran this diff: the root `action.yml` input list is byte-identical between v1.0.236 and v1.0.263 (0 added, 0 removed), so the condition is expected to hold; re-run it at work time against the then-current tag. A removed or renamed input means pin to the last release that has it and say so.
- 2.3 Replace the SHA in `claude-code-review.yml`, `test-pretooluse-hooks.yml`, `scheduled-machinery-drain.yml`, `fix-constraints-stage-a.yml` and `constraint-scaffold/references/fix-constraints-stage-a.template` (one `sed` over exact literal `20f0b248c5003db4b9ca43c45e17949bcdc36d2d # v1.0.236`; census: `git grep -c` must show zero remaining before and five replacements after). Leave the historical "measured at v1.0.236" comments in `scheduled-machinery-drain.yml` and `claude-code-action-auth.test.sh` as they are (dated measurements).
- 2.4 Check `knowledge-base/legal/article-30-register.md` (it mentions `scheduled-machinery-drain.yml`): if it cites the pinned version as a current fact, update the number; if it cites it as a dated snapshot, leave it.
- 2.5 Run `bash plugins/soleur/test/claude-code-action-auth.test.sh`, `bash plugins/soleur/skills/constraint-scaffold/test/parity.test.sh` and the model-launch-review pin-freshness audit (`plugins/soleur/skills/model-launch-review/scripts/audit-models.sh`, section 2 is flag-only) to confirm nothing else reads the old SHA.
- 2.6 Expected on this PR, non-required: `claude-code-review.yml` cannot validate against the default-branch copy while the PR edits that very file, so the review job is expected to skip/fail workflow validation; record that in the PR body so it is not mistaken for a regression. A branch dispatch of `test-pretooluse-hooks.yml` is NOT verification: it edits that same file, so the action prints "Skipping action due to workflow validation" and exits 0 without installing the CLI or running any guard test, and the `continue-on-error` step still reports `success` (measured on run 42008804290: only the deterministic F2 telemetry steps ran). It proves at most that the pinned SHA downloads. The real verification is a dispatch on `main` after merge (see the Post-merge criteria).

### Phase 3 - pen-cli lock (CTO F3)

- 3.1 `plugins/soleur/skills/pencil-setup/scripts/pen-cli/package.json`: add `"@anthropic-ai/claude-agent-sdk": "0.3.311"` to `overrides` (exact, alongside undici/sharp/minimatch).
- 3.2 Regenerate under the CI-pinned npm: `cd plugins/soleur/skills/pencil-setup/scripts/pen-cli && npx --yes npm@11.21.1 install --package-lock-only --ignore-scripts --no-audit --no-fund`. Expected diff: nine entries (`claude-agent-sdk` plus eight `-darwin/-linux/-win32` platform packages) move 0.3.310 to 0.3.311 with new `resolved`/`integrity`, and the SDK's own `engines.node` `>=18.14.0`; anything else in the diff (a different transitive moving) is a stop-and-inspect.
- 3.3 Run `engine-contract-probe.sh` against the regenerated lock: `doppler run -p soleur -c dev -- bash plugins/soleur/skills/pencil-setup/scripts/engine-contract-probe.sh` (read-only; credential via Doppler, never printed, no xtrace). If it cannot run, label the lock bump `unverified`, drop Phase 3 from this PR, and say why in the PR body (do not ship an unprobed customer lockfile); the PR still closes #12102 only if the remaining AC items are met, otherwise the issue keeps its open item via `Ref`, never silent.
- 3.4 Run `bash plugins/soleur/test/check-deps-adapter-drift.test.sh`, `bash scripts/lint-dual-lockfile.test.sh`, and the `pencil-adapter-sentinels` test. Note for the PR body: the lock-stamp sha changes, so each customer install does one `--auto` reinstall (about 1 GB) on next `check_deps`.

### Phase 4 - Follow-through closure check

- 4.1 After Phase 1, re-run the probe's extraction against the worktree (the probe reads `main`, so use its same `sed` against the local file) to show `2.1.311` satisfies `sort -V` against the `2.1.311` floor; the live PASS happens post-merge (see ACs).
- 4.2 The tracker's directive is unchanged; the PR's `Closes #12102` closes it at merge, and the sweeper's PASS is the independent confirmation.

### Phase 5 - Ship wiring

- 5.1 PR body (not the title) contains `Closes #12102`, the bundled-Bun statement ("v1.0.236 shipped Bun 1.3.14 and CLI 2.1.284; v1.0.263 ships Bun 1.4.4 and CLI 2.1.311; whether the jobs decode a network Brotli response stays unverified and is moot after the bump"), the canary scratch-run result, the engine-contract-probe result, the `test-pretooluse-hooks` dispatch result, the expected-non-required `claude-code-review` note, and the customer reinstall note. Label `meta/machinery`; semver label per ship (patch).
- 5.2 Do not push to a PR that is in the merge queue (dequeue via GraphQL `dequeuePullRequest` first). Check each push's real exit code (no `| tail`). `cd` into the worktree before git writes. Do not touch PR 10926 or any other open tracker.
- 5.3 File one follow-up issue for the `operator-digest.workflow.yml` pin (`claude-code-action@ab8b1e6471c519c585ba17e8ecaccc9d83043541 # v1.0.101`, customer-facing asset, 162-release jump needing its own input-drift review and `operator-digest-workflow.test.sh` run), milestone from `knowledge-base/product/roadmap.md`, labels `domain/engineering`, `type/security`, `deferred-scope-out`. No existing open issue covers it (searched). Net-issue-flow: the PR closes one issue and files one, so if the gate asks for it use the override marker with justification "deferred scope-out of #12102, customer-facing template, separate risk profile" and a `Filed:` line.
- 5.4 Registry files (`scripts/ci-pr-affected-audit.accept.tsv`, `suite-durations.tsv`, `suite-shard-legs.tsv`): no new suite or workflow is added, so no rows are expected; if a registry check reds, insert the row in sorted position, never appended.
- 5.5 Read the non-required `infra-validation` and `sandbox-canary-capture-gate` runs on the pushed head by hand; required checks are `test`, `lockfile-sync`, `markdown-lint`, `tenant-integration-required`.

## Files to Edit

- `.github/workflows/scheduled-marketplace-drift.yml` (CLI_VERSION)
- `.github/workflows/claude-code-review.yml` (action SHA)
- `.github/workflows/test-pretooluse-hooks.yml` (action SHA)
- `.github/workflows/scheduled-machinery-drain.yml` (action SHA)
- `.github/workflows/fix-constraints-stage-a.yml` (action SHA)
- `plugins/soleur/skills/constraint-scaffold/references/fix-constraints-stage-a.template` (action SHA)
- `plugins/soleur/skills/pencil-setup/scripts/pen-cli/package.json` (override)
- `plugins/soleur/skills/pencil-setup/scripts/pen-cli/package-lock.json` (regenerated)
- `knowledge-base/legal/article-30-register.md` (only if it states the pinned version as current; see 2.4)

## Files to Create

None (spec artifacts `decision-challenges.md` and `tasks.md` live under `knowledge-base/project/specs/feat-one-shot-12102-ci-claude-cli-pins/`).

## Acceptance Criteria

### Pre-merge (PR)

- [x] `grep -c 'CLI_VERSION: "2.1.311"' .github/workflows/scheduled-marketplace-drift.yml` returns 1 and the file contains no `2.1.228`.
- [x] The scratch canary run against CLI 2.1.311 exits 0 with `compared` > 0 and no `installpath_unresolved` (result recorded in commit a766f83147 and copied into the PR body at ship); the scratch binary reports `Bun v1.4.4` via the corrected probe.
- [x] `git grep -c '20f0b248c5003db4b9ca43c45e17949bcdc36d2d'` outside `knowledge-base/` returns nothing; the five files carry `anthropics/claude-code-action@3b7e1a45ca6f231c62605aabcf79e6a41b08c7da # v1.0.263`.
- [x] The v1.0.236-to-v1.0.263 input diff (plan-time result: identical input lists) shows every `with:` key used in the five files still exists (recorded in commit a766f83147; summarised in the PR body at ship); `claude-code-action-auth.test.sh` and the constraint-scaffold parity test pass.
- [ ] `pen-cli/package.json` `overrides` has the exact `@anthropic-ai/claude-agent-sdk: 0.3.311` entry; the lock shows `node_modules/@anthropic-ai/claude-agent-sdk` and its eight platform packages at 0.3.311, regenerated under npm 11.21.1; `lockfile-sync` is green.
- [x] `engine-contract-probe.sh` passes against the regenerated lock (145 PASS, 0 FAIL on 2026-11-05; the refreshed transcript is deliberately not committed, the result goes in the PR body).
- [x] `adhoc-npm-install-pin-table.test.ts` passes unchanged (no edit to it is part of the diff).
- [ ] CI required checks green: `test`, `lockfile-sync`, `markdown-lint`, `tenant-integration-required`; non-required `infra-validation` and `sandbox-canary-capture-gate` read by hand.
- [ ] PR body contains `Closes #12102`, the Brotli statement, and the customer-reinstall note; label `meta/machinery` applied; follow-up issue for `operator-digest.workflow.yml` filed and referenced.

### Post-merge (operator-free, agent-run)

- [ ] `bash scripts/followthroughs/ci-claude-cli-pins-bun-12073.sh` with the ambient `gh` token exits 0 (PASS) against `main`.
- [ ] `gh workflow run scheduled-marketplace-drift.yml` dispatch (CTO F1 production check) completes green on `main`; arm a Monitor on the run id (do not poll in a background shell) and read the canary job's verdict output.
- [ ] `gh workflow run test-pretooluse-hooks.yml --ref main` completes and its log shows NO "Skipping action due to workflow validation" line and the Test 1-5 guard rows reported PASS by the agent (the only run that exercises v1.0.263; arm a Monitor on the run id, and read the log, not the step `conclusion`, which `continue-on-error` pins to `success`).
- [ ] #12102 is closed by the merge.

## Domain Review

**Domains relevant:** engineering

### Engineering

**Status:** reviewed
**Assessment:** CTO ruled F1-F4 on 2026-11-05 (see decision-challenges.md). Pin-only change on CI and a customer lockfile; no product, marketing, legal, finance or sales implications. No new user-facing surface (Product/UX gate: NONE). No regulated-data surface (GDPR gate not triggered; no data flow added).

## Observability

```yaml
liveness_signal:
  what: the daily follow-through sweeper runs scripts/followthroughs/ci-claude-cli-pins-bun-12073.sh and the marketplace-drift canary heartbeat keeps checking in
  cadence: daily (sweeper) and the existing scheduled-marketplace-drift schedule
  alert_target: existing Sentry cron monitor for scheduled-marketplace-drift plus the sweeper's action-required issue
  configured_in: .github/workflows/scheduled-marketplace-drift.yml, .github/workflows/scheduled-followthrough-sweeper.yml
error_reporting:
  destination: canary verdict output (MISMATCH with installpath_unresolved / cli_unavailable findings) and the Sentry heartbeat
  fail_loud: true
failure_modes:
  - mode: 2.1.311 cannot be installed on the runner
    detection: canary step reports cli_unavailable (MISMATCH), not a silent green
    alert_route: drift-check job files the drift issue / Sentry check-in fails
  - mode: CLI record shape drift makes the canary compare nothing
    detection: compared=0 with exit 0 is converted to installpath_unresolved MISMATCH by the workflow
    alert_route: same as above
logs:
  where: GitHub Actions run logs for scheduled-marketplace-drift.yml; Sentry cron monitor
  retention: GitHub default run-log retention
discoverability_test:
  command: grep -m1 'CLI_VERSION: "2.1.311"' .github/workflows/scheduled-marketplace-drift.yml
  expected_output: CLI_VERSION: "2.1.311"
```

## Test Scenarios

- Probe extraction against the edited workflow: `2.1.311` sorts at/above the `2.1.311` floor (PASS branch); against the original `2.1.228` it falls to the ACTION REQUIRED branch (confirms the probe still discriminates).
- Canary on the old pin (2.1.228) versus new (2.1.311) produce the same verdict and a comparable `compared` count; a differing count is investigated before merge.
- `npm ci` in a scratch copy of `pen-cli` (lifecycle scripts ignored, as `check_deps.sh` does) installs and `node_modules/@anthropic-ai/claude-agent-sdk/package.json` reports 0.3.311.

## Sharp Edges

- The "pin-table test row" is value-agnostic. Do not add a literal row or a version to the env row to satisfy the brief's wording; that would make every future CLI bump a two-file edit for no added guarantee.
- `claude_code_version` does not exist as an action input. A plan, PR body, or comment that claims to have "set" it is wrong; the lever is the action SHA.
- For `claude-code-action` specifically the pin convention is the annotated tag object, not the peeled commit (`8041f1d17e0e7d2f2cfe35002962e9f26237c0bb` for v1.0.263); the repo's other action pins use peeled commit SHAs, so this is not a repo-wide rule. Mixing forms across the five files would leave `audit-models.sh` (which reads only the first pin it finds) reporting on one form while others differ; use the tag object everywhere and re-resolve it at work time.
- Local npm is 11.20.0 and CI pins 11.21.1; a lockfile regenerated locally can still fail `lockfile-sync`. Regenerate with `npx --yes npm@11.21.1`.
- `scheduled-marketplace-drift.yml` steps declare no `shell:` key (errexit-on by default); the edit is a one-token change and must not touch the `set +e` bracket.
- The follow-through probe reads `main`, so its PASS is only observable after merge; do not claim it passed from the branch.
- A `## User-Brand Impact` section that is empty or lacks the threshold fails `deepen-plan` Phase 4.6; this plan fills it.
