# Tasks: bump claude-code/agent-sdk to a Bun>=1.4.4 pair (Ref #12026)

Plan: `knowledge-base/project/plans/2026-11-04-fix-bump-claude-code-sdk-bun-1-4-4-pair-plan.md`
Branch: `feat-one-shot-12026-bun-claude-code-bump` | Draft PR 12073 | PR body uses `Ref #12026`, never `Closes`.

## Phase 0 - Baseline and scope evidence (read-only)

- 0.1 Re-run the read-only prd count (`public.workspaces`, `web_egress`) at Phase 1 start, before the pin commit, and at merge; compare with the planning baseline (1 of 22 at 2026-11-04T08:59:56Z). A rise above 1 is the issue's pull-forward trigger: escalate it on #12026 in the same session.
- 0.2 Paste the CI-scope finding (no WebFetch/WebSearch in `.github/workflows`; three `claude-code-action` invocations use action defaults, unverified; `scheduled-marketplace-drift.yml` pins 2.1.228) into the PR body.
- 0.3 Confirm `2.1.311` and `0.3.311` resolve under `min-release-age=3`.
- 0.4 Confirm `web-platform-release.yml` `workflow_dispatch` can redeploy a head SHA (rollback path); read only.

## Phase 1 - Scratch install and real-SDK re-proof (no committed pin moves)

- 1.1 `git worktree add --detach` a scratch tree outside the repo from `origin/main`; set the two exact pins; generate `package-lock.json` with `npx npm@11`; keep that lockfile for Phase 2.
- 1.2 Record installed versions and `sha256sum` of both `claude` binaries (expect `86dc1fcc69498159eaf15f446613e847010f9036bfbbdffd4c49350be8489ada`); run the corrected Bun probe on both.
- 1.3 RED baseline, unchanged tests against the scratch tree: `sandbox-vendored-argv-tail`, `sandbox-startup-classifier`, `claude-cli-pin-knows-models`, `broker-mechanism-spike`, `plugins/soleur/test/model-launch-review`. Record failing row names.
- 1.4 Real-SDK proof set against the scratch tree: `sandbox-wrapped-command-runtime` (production-config block, G2 block, AF_UNIX-deny variant block), `sandbox-credential-deny-runtime`, `sandbox-proc-mask-runtime`, `infra/sandbox-masked-proc-docker.test.sh` (not optional; if it cannot run, PR stays draft).
- 1.5 F4 checks: knob true skips the helper; knob false + helper present reproduces `apply-seccomp: unshare(CLONE_NEWUSER): Operation not permitted`; our config sets no managed-policy mode that drops `network.allowAllUnixSockets`.
- 1.6 Watch `--disable-userns` and `--unsetenv <var>` in every run (production bwrap + AppArmor profile).
- 1.7 Measure runtime order of the four new `apply-seccomp:` strings; decide pre-command / post-command / non-step line for each.
- 1.8 Stop condition: any red not explained by a pin-shape change blocks the bump; PR stays draft. Post the failing rows on #12026 the same day; CTO rules on the next candidate pair (2.1.312-2.1.316) or hold by 2026-11-09; if none is green by then the owner decides (extend 2026-11-11, or ask the single `web_egress` workspace owner to switch it off - consent needed; decision-challenges F8).
- 1.9 Docker masked-/proc arm without local sudo: push the pin commit to the draft PR and use CI `infra-validation` on that head as the stand-in; mark ready only after it is green.

## Phase 2 - One atomic pin commit

- 2.1 `apps/web-platform/package.json`, `package-lock.json` (from scratch; `npx npm@11 install --package-lock-only` is a no-op).
- 2.2 `apps/web-platform/Dockerfile`: `@anthropic-ai/claude-code@2.1.311`; delete the two-line CVE caveat comment.
- 2.3 Pin tables: `adhoc-npm-install-pin-table.test.ts`, `broker-mechanism-spike.test.ts`; re-derive `REVIEWED_DEFAULT_EFFORT` in `claude-cli-pin-knows-models.test.ts`.
- 2.4 `sandbox-vendored-argv-tail.test.ts` + `helpers/vendored-bwrap-tail.ts`: new `EXPECTED_TAIL_CALLS` (`--unsetenv`, `--disable-userns`), SDK `PINS` to the measured shape with new `measuredVersion`s, content-anchored settings needle, `TCP6-LISTEN:`/`TCP4-LISTEN:`/`_srt_http=$!` bridge anchors, `synth()` mirrors the new shape; no line numbers anywhere.
- 2.5 `server/sandbox-startup-classifier.ts` + test (`minStrings` floor, `HELPER_NON_STEP_LINES` equality assertion) + `HELPER_NON_STEP_LINES` in the helper, per 1.7.
- 2.6 Guard 1: embedded-Bun floor test in `claude-cli-pin-knows-models.test.ts` (bounded scan, semver compare, bare `Bun v` positive control, floor of 2 binaries checked, minimum over all occurrences).
- 2.7 F5 (own commit just before the pin commit): Haiku 4.5 to 5.5 in `sandbox-credential-deny-runtime.test.ts`, `broker-mechanism-spike.test.ts`, `scripts/sandbox-canary.mjs` (`CAPTURE_MODEL`), `scripts/plugin-root-sandbox-propagation-probe.mjs`; delete `SDK_PATH_CARVEOUT`, `sdk_carveout_re()` and the `EXCLUDE_RE` term in `audit-models.sh`; delete every test referencing `SDK_CARVEOUT_PATHS`/`sdkKnowsHaiku55`/`pkgSdkPin` in `model-launch-review.test.ts`; update `model-launch-review/SKILL.md`; `grep -rn SDK_PATH_CARVEOUT plugins/` must return nothing.
- 2.8 `agent-auth-cli-contract.test.ts` runs in the 1.3 baseline; edit only if red.
- 2.9 Regenerate `infra/sandbox-canary-argv.json` via `SANDBOX_CANARY_MODE=capture bash apps/web-platform/scripts/sandbox-canary-verify-in-image.sh` (Doppler config `ci` key only, never `prd`, no xtrace; CTO F13; never hand-edit).
- 2.10 Commit with a `sdk-bump-verified:` trailer stating validated and not-validated items, written only after Phase 1 is green, capture succeeded and 2.13 passed; keep it on the lockfile-bearing commit and verify the squash message keeps it.
- 2.11 Short ADR-079 addendum dated 2026-11-04, ADR-075 pointer (reshaped settings mapping), ADR-278 "Measured against" version to 0.3.311; run `plugins/soleur/test/c4-count-parity.test.sh`.
- 2.13 Re-run the 1.4 runtime suites + docker arm on the branch head; `docker build --target cli-tools` and run the corrected Bun probe on its global `claude`; then finalize the trailer. Guard 1 test: timeout >= 60 s, `shouldSkipRealBinaryRows` gate, absent binary reds `BINARY_MISSING`.
- 2.12 Registry rows (accept/durations/shard-legs) only if the audit replay demands; sorted position, validate with `audit --accept`.

## Phase 3 - PR, CI gate, PR 10926 note

- 3.1 Push; check the real exit code (no `| tail`). Mark PR ready only after Phase 1 evidence + Phase 2 complete. PR body: `Ref #12026`, baseline, CI scope, corrected probe old/new, sha256, evidence table, `## Changelog`; `semver:patch`.
- 3.2 Gate = CI required `test` check plus `lockfile-sync`/`sdk-bump-sandbox-gate`. `sandbox-canary-capture-gate` and `infra-validation` (the AppArmor half of the masked-/proc proof) are NOT required checks: read both runs on the pushed head, record the run ids, and mark ready/arm auto-merge only when both ran and passed (the capture gate must have run the in-image `--verify` and reported no drift, not the `sdk-bump-verified:` ack fallback). Never push to a queued PR; dequeue via the GraphQL `dequeuePullRequest` mutation first.
- 3.2b CI-red loop: fixture mismatch in the capture gate means re-capture in the CI image path, never a hand edit; after any rebase re-run `npx npm@11 install --package-lock-only` and the fixture byte-diff before re-queuing.
- 3.3 One flag comment on PR 10926 (stale `Setup Bun` without `bun-version-file`; keep main's `npm-publish.yml` on rebase). No branch change.

## Phase 4 - Post-merge evidence and issue close (telemetry/image only)

- 4.1 Confirm release, deploy on web-1 and web-2 per host, canary `sdkVersion` 0.3.311 and SDK Bash smoke via `/hooks/deploy-status` and Better Stack, within a stated timeout. Canary and smoke are report-only (no auto-rollback) and web-2 is forwarded after web-1's swap, so this poll is the detection step.
- 4.1b Rollback if canary/smoke is not ok or hosted Bash fails: revert the atomic pin commit via a new PR (lockfile, Dockerfile, fixture together to 2.1.293 / 0.3.284), redeploy through `web-platform-release.yml` `workflow_dispatch`; never SSH; leave #12026 open and comment the verdict.
- 4.2 Extract the three shipped `claude` binaries from the released image and run the corrected probe: all three must report `Bun v1.4.4` or newer or #12026 stays open.
- 4.3 Check the paid `scheduled-real-sdk-ask-probe` run after merge.
- 4.4 Comment evidence on #12026, then close it.
