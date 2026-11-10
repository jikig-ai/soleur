# Tasks: bump claude-code / agent-sdk to 2.1.321 / 0.3.321 so `fable` resolves to claude-fable-5-2 (Ref #12514)

Plan: `knowledge-base/project/plans/2026-11-10-chore-bump-claude-code-cli-fable-5-2-plan.md`
Branch: `feat-one-shot-12514-claude-code-cli-fable-bump` | Draft PR #12553 | PR body: `Ref #12514`, `Closes #8643`.
Rulings: `knowledge-base/project/specs/feat-one-shot-12514-claude-code-cli-fable-bump/decision-challenges.md`.

## Phase 0 - Baseline (read-only)

- 0.1 `npm view` time and `dist.integrity` for claude-code 2.1.321, agent-sdk 0.3.321 and both `-linux-x64` packages; stop if pulled.
- 0.2 `git grep -n -E '2\.1\.311|0\.3\.311' -- ':!knowledge-base' ':!**/package-lock.json'` -> the 2.6 sweep set.
- 0.3 Confirm 2.1.311 / 0.3.311 still resolve (rollback pair).
- 0.4 `docker info` and `command -v bwrap` succeed; otherwise stop with the PR draft.

## Phase 1 - Non-pin work and rehearsal (before Gate G1)

- 1.0 Author and push to the draft PR: `server/agent-model-defaults.ts` + runner default; shared parser `plugins/soleur/test/lib/autofix-pairs.ts` (pair floor >= 11 and distinct-RHS floor >= 4 moved in; `model-launch-review.test.ts` imports it); Guards 4 and 5 with every mutation row as a standing synthetic test, written before the guard bodies (Guard 5 rows cut from the real 2.1.321 row text); test-selection edge for `audit-models.sh`; prose (AGENTS.md, ADR-053, ADR-083, model-launch-review SKILL.md incl. release-age note); ADR-079 addendum incl. the cross-boundary contract.
- 1.1 Scratch tree from branch HEAD (`npm ci`, then `rm -rf` and replace the four `@anthropic-ai` packages with the 321 tarballs, `npm rebuild @anthropic-ai/claude-code`, manifest diff recorded) and an untouched control tree (311).
- 1.2 Assert sha256 `426c33815ca6645a...` for every spawned binary; Bun banner >= 1.4.4; Guards 4/5 pass in scratch, Guard 4 reds in control; record SHAs, integrity strings and hashes in the PR body.
- 1.3 RED baseline of the unchanged pin suites (incl. `home-census`); classify each red as pin-shape or not.
- 1.4 Runtime evidence (non-skipped, sha256 asserted): wrapped-command (prod config, AF_UNIX-deny + negative control), credential-deny runtime, credential-deny behavioural, bwrap-userns-seccomp real rows, proc-mask runtime, docker masked-/proc, canary `--replay`.
- 1.5 Cron hook probe (original filename, `*` matcher, known-deny control), 2.1.311 control from the control tree.
- 1.6 Invalid-key alias probe on both binaries -> `claude-fable-5-2`.
- 1.6b Authenticated alias probe (Doppler `ci` key, read-only, one turn) -> `modelUsage` has `claude-fable-5-2`.
- 1.7 Write/Edit allow-path smoke through the real SDK.
- 1.8 Re-measure argv census, helper step strings, bridge anchors, `default_effort` rows.
- 1.9 Stop condition: any non-pin-shape red blocks; comment on #12514; re-ask the CTO.

## Gate G1 - release-age floor

- G1 `date -u +%s` >= `date -u -d '2026-11-12T19:04:00Z' +%s`. Earlier: commit nothing pin-bearing, PR stays draft, end with `Paused: release-age floor clears 2026-11-12T19:04Z` and a resume prompt naming the PR, the recorded SHAs and integrity strings.

## Phase 2 - The pin commit (after G1)

- 2.1 package.json pins; `npx --yes npm@11 install --package-lock-only` in `apps/web-platform`.
- 2.2 Dockerfile global install `2.1.321`.
- 2.3 `scheduled-marketplace-drift.yml` `CLI_VERSION: "2.1.321"`.
- 2.4 pen-cli `overrides` only -> `0.3.321`; regenerate its lock.
- 2.5 Integrity proof against `npm view` and the recorded values (re-`npm pack`); scratch `npm ci` yields sha256 `426c3381...`.
- 2.6 Re-pin version-literal sites and `PINS` (`measuredVersion`, counts, date); comment rule (history stays, current-pin claims move).
- 2.7 Re-capture `infra/sandbox-canary-argv.json` (Doppler `ci` key, never `prd`, no xtrace); `sdkVersion` 0.3.321.
- 2.12 `bash plugins/soleur/test/c4-count-parity.test.sh`.
- 2.13 `npm ci` in the branch worktree; re-run 1.2, 1.4, 1.5, 1.6, 1.6b and the affected vitest set; `docker build --target cli-tools` + Bun and alias probe.
- 2.14 Commit with the `sdk-bump-verified:` trailer (validated / not validated lists); copy it into the PR body.

## Phase 3 - PR and CI

- 3.1 Push (check the real exit code); PR body per plan; `semver:patch`.
- 3.2 Required `test` + `guards-ruleset` green; read `sandbox-canary-capture-gate` (in-image `--verify`, no drift) and `infra-validation` runs on the head, record run ids, then mark ready.
- 3.3 After any rebase: `npx --yes npm@11.21.1 install --package-lock-only && git diff --exit-code` in both dirs, fixture byte-diff; never push to a queued PR.

## Phase 4 - Post-merge (image and telemetry, no SSH)

- 4.1 Image sha256 of the three `claude` binaries; invalid-key alias probe in the image.
- 4.2 web-1 / web-2 deploy status: canary ok, `sdk_version` 0.3.321, smoke ok; no classifier unknown-step events.
- 4.3 Next audit cron run and `scheduled-real-sdk-ask-probe` green.
- 4.4 Rollback on any trigger: revert PR with its own trailer; leave #12514 open.
- 4.5 Comment evidence on #12514 and close it.
