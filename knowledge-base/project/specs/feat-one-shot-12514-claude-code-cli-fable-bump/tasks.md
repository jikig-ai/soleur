# Tasks: bump claude-code / agent-sdk to 2.1.321 / 0.3.321 so `fable` resolves to claude-fable-5-2 (Ref #12514)

Plan: `knowledge-base/project/plans/2026-11-10-chore-bump-claude-code-cli-fable-5-2-plan.md`
Branch: `feat-one-shot-12514-claude-code-cli-fable-bump` | Draft PR #12553 | PR body: `Ref #12514`, `Closes #8643`.
Rulings: `knowledge-base/project/specs/feat-one-shot-12514-claude-code-cli-fable-bump/decision-challenges.md`.

## Phase 0 - Baseline (read-only)

- 0.1 `npm view` time and `dist.integrity` for claude-code 2.1.321, agent-sdk 0.3.321 and both `-linux-x64` packages; stop if pulled.
- 0.2 `git grep -n -E '2\.1\.311|0\.3\.311' -- ':!knowledge-base' ':!**/package-lock.json'` -> the 2.6 sweep set.
- 0.3 Confirm 2.1.311 / 0.3.311 still resolve (rollback pair).
- 0.4 `docker info` and `command -v bwrap` succeed; otherwise stop with the PR draft.

## Phase 1 - Before Gate G1: non-pin work and static checks only (CTO F15: no 2.1.321 / 0.3.321 code runs)

- 1.0 Author and push to the draft PR: `server/agent-model-defaults.ts` + runner default; shared parser `plugins/soleur/test/lib/autofix-pairs.ts` as pure `parseAutofixPairs(src)` + `assertPairFloors` (>= 11 pairs, >= 4 distinct RHS; `model-launch-review.test.ts` imports it); Guards 4 and 5 (`assertIdsKnown`, literal `REVIEWED_ADVISOR_EFFORT = {"claude-fable-5-2": "medium"}` cross-checked against `AUTOFIX_PAIRS`), every mutation row a standing synthetic test, written before the guard bodies; test-selection edge for `audit-models.sh`; prose (AGENTS.md, ADR-053, ADR-083, model-launch-review SKILL.md incl. release-age note); ADR-079 addendum incl. the cross-boundary contract.
- 1.1 Static checks: `npm pack` (download only) the 321 tarballs and the 311 parents outside the repo; diff `install.cjs` and manifests; record `dist.integrity`, tarball sha512 and binary sha256 (`426c33815ca6645a...`) in the PR body. Advisory or unpublish before G1 -> stop, record `Operator-authorizes:` host credential rotation (F15b).

## Gate G1 - release-age floor

- G1 `date -u +%s` >= `date -u -d '2026-11-12T19:04:00Z' +%s`. Earlier: install, run or commit nothing from the new versions; PR stays draft; end with `Paused: release-age floor clears 2026-11-12T19:04Z` and a resume prompt naming the PR and the recorded integrity values.

## Phase 2 - Pins and lock (after G1)

- 2.1 package.json pins; `npx --yes npm@11 install --package-lock-only` in `apps/web-platform`.
- 2.2 Dockerfile global install `2.1.321`.
- 2.3 `scheduled-marketplace-drift.yml` `CLI_VERSION: "2.1.321"`.
- 2.4 pen-cli `overrides` only -> `0.3.321`; regenerate its lock.
- 2.5 Integrity proof against `npm view` and the recorded values (re-`npm pack`).

## Phase R - Re-proof on the installed tree, in a throwaway container (read-only tree, tmpfs HOME, no ~/.doppler ~/.ssh ~/.config/gh, no docker socket)

- 1.1r `npm ci` (postinstall inside the container) + control tree at 2.1.311 / 0.3.311; `npm audit signatures`; `claude --version` = 2.1.321.
- 1.2 Assert sha256 `426c3381...` for every spawned binary; Bun banner >= 1.4.4; Guards 4/5 pass, Guard 4 reds in control.
- 1.3 RED baseline of the unchanged pin suites (incl. `home-census`); classify each red.
- 1.4 Runtime evidence (non-skipped, sha256 asserted): wrapped-command (prod config, AF_UNIX-deny + negative control, egress arm), credential-deny runtime, credential-deny behavioural, bwrap-userns-seccomp real rows, proc-mask runtime, docker masked-/proc (`wrapped` arm = seccomp proof); CI stand-in for the docker arm is `infra-validation` `deploy-script-tests-fixed` on the pin-commit head only.
- 1.5 Cron hook probe (original filename, `*` matcher, known-deny control), 2.1.311 control; key via 0600 file + wrapper, `env -i`, temp HOME deleted; record only `.permission_denials`.
- 1.6 Invalid-key alias probe on both binaries -> `claude-fable-5-2`.
- 1.6b Authenticated alias probe (Doppler `ci` key, same key handling, one turn) -> `.modelUsage|keys` has `claude-fable-5-2`.
- 1.7 Write/Edit allow-path smoke through the real SDK.
- 1.8 Re-measure argv census, helper step strings, bridge anchors, `default_effort` rows.
- 1.9 Stop condition: any non-pin-shape red blocks; comment on #12514; re-ask the CTO.

## Phase 2 (continued) - re-pin, capture, trailer

- 2.6 Re-pin version-literal sites and `PINS` (`measuredVersion`, counts, date); comment rule (history stays, current-pin claims move).
- 2.7 Re-capture `infra/sandbox-canary-argv.json` (Doppler `ci` key, never `prd`, no xtrace); `sdkVersion` 0.3.321.
- 2.12 `bash plugins/soleur/test/c4-count-parity.test.sh`.
- 2.13 Affected vitest set; `--replay` and docker replay arms against the re-captured fixture; `docker build --target cli-tools` + Bun and alias probe.
- 2.14 Pin commit with the `sdk-bump-verified:` trailer (validated / not validated lists); copy it into the PR body.

## Phase 3 - PR and CI

- 3.1 Push (check the real exit code); PR body per plan; `semver:patch`.
- 3.2 Required `test` + `guards-ruleset` green; `npx --yes npm@11.21.1 install --package-lock-only && git diff --exit-code` in both lock dirs; read `sandbox-canary-capture-gate` (in-image `--verify`, no drift) and `infra-validation` runs on the head, record run ids, then mark ready.
- 3.3 After any rebase: `npx --yes npm@11.21.1 install --package-lock-only && git diff --exit-code` in both dirs, fixture byte-diff; never push to a queued PR.

## Phase 4 - Post-merge (image and telemetry, no SSH)

- 4.1 Image sha256 of the three `claude` binaries; invalid-key alias probe in the image.
- 4.2 web-1 / web-2 deploy status: canary ok, `sdk_version` 0.3.321, smoke ok; no classifier unknown-step events.
- 4.3 Next audit cron run and `scheduled-real-sdk-ask-probe` green.
- 4.4 Rollback on any named trigger: revert PR with its own trailer (no faster no-SSH path exists); leave #12514 open.
- 4.5 Comment evidence on #12514 and close it.
