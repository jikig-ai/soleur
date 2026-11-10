---
title: "chore: bump the claude-code / agent-sdk pair to 2.1.321 / 0.3.321 so `fable` resolves to claude-fable-5-2"
type: chore
date: 2026-11-10
slug: chore-bump-claude-code-cli-fable-5-2
branch: feat-one-shot-12514-claude-code-cli-fable-bump
issue: 12514
closes: [8643]
priority: p3
domain: engineering
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# chore: bump the claude-code / agent-sdk pair to 2.1.321 / 0.3.321 so `fable` resolves to claude-fable-5-2

PR body: `Ref #12514` (it closes only after the post-merge alias and binary evidence in Phase 4) and
`Closes #8643` (its acceptance, an SDK-binary model-id row plus the raw default routed through a named
constant, is fully pre-merge). Spec lacks valid lane: - defaulted to cross-domain (TR2 fail-closed).

## Enhancement Summary

**Deepened on:** 2026-11-10 (plan-review round, then deepen-plan round).
**Gates run:** deepen-plan 4.6 (User-Brand Impact), 4.7 (Observability; `probe-verb-gate.sh` rc 0 on the
discoverability command), 4.8 (no PAT-shaped variable), 4.9 (no UI surface), 4.10 (no store / connection; no
`.tf` in Files to Edit), 4.11 (`lint-guard-contract.py` green, 2 entries), 4.12 (Scope Check present, one live
section, three subsections, `Recommendation:` present), 4.13 (no new autonomous task); 4.5 / 4.55 not
triggered (no network symptom; the deploy mechanism itself is unchanged).
**Agents used:** plan-review panel (dhh-rails-reviewer, kieran-rails-reviewer, code-simplicity-reviewer,
architecture-strategist, spec-flow-analyzer), CPO sign-off, the scoped advisor consult (fable tier), and in the
deepen round security-sentinel, test-design-reviewer and a verify-the-negative pass (10 of 10 claims
confirmed). The deepen round ran this bounded panel, not every available agent.

### Key Improvements

1. No code from 2.1.321 / 0.3.321 runs before the release-age floor clears; the re-proof runs after Gate G1 on
   the installed tree inside a throwaway container, and every real-key run uses a 0600 key file through a
   wrapper (CTO F15, security review).
2. An authenticated alias probe closes the gap the invalid-key probes cannot see (CTO F12).
3. Guards 4 and 5 are specified as pure functions with every mutation row a standing synthetic test, a literal
   `REVIEWED_ADVISOR_EFFORT` key cross-checked against `AUTOFIX_PAIRS`, and parser edge rows (test-design review).
4. Evidence and lockfile proof survive the two-day pause (integrity and sha256 recorded in the PR body), and
   the non-pin commits are pushed to the draft PR instead of staying local (spec-flow, DHH, simplicity).
5. Corrected facts: pen-cli has the SDK only under `overrides`; the CI stand-in for the docker arm is
   `infra-validation`'s `deploy-script-tests-fixed` job, not `sandbox-canary-verify-in-image`; two more real
   sandbox suites (`agent-sandbox-credential-deny-behavioural`, `bwrap-userns-seccomp`) join the evidence set.

### New Considerations Discovered

- The consult's bundled default effort moves "high" -> "medium" with the alias (CTO F9).
- `server/agent-runner-query-options.ts` is a capture input, so the non-pin draft push runs the capture gate.
- No faster no-SSH rollback than a revert PR exists (`web-platform-release.yml` dispatch has no older-tag input).
- The planning session ran the new binaries once on its host for the zero-cost invalid-key probe; disclosed in
  decision-challenges F15, with an operator rotation item (F15b) only if an advisory hits 2.1.321.

## Overview

Both web-platform Claude runtimes are pinned at a release (claude-code 2.1.311, claude-agent-sdk 0.3.311,
one byte-identical native binary) whose bundled model table has no `claude-fable-5-2` row. Measured in this
session: on that binary the version-agnostic `fable` alias resolves to **`claude-fable-5-1`**, so every
hosted plan Step 4.5 / ship Phase 5.5 consult still runs on Fable 5.1. The first release that knows the id
is 2.1.321 / 0.3.321 (again one byte-identical binary, `sha256 426c3381...`), on which `fable` resolves to
`claude-fable-5-2`.

This plan moves the **pair** (CTO F2: the hosted consult runs on the Agent SDK's own bundled binary, so a
CLI-only bump would not reach the place where `fable` is spent), re-proves the sandbox and cron containment
on the real binary (CTO F4, the #12026 evidence set), respects the 3-day release-age floor (CTO F3: the pin
commit lands only after 2026-11-12T19:04Z; before it only static supply-chain checks run, and no new-package code executes - CTO F15),
turns the one-time measurements into standing guards (CTO F6/F6r/F9), folds in #8643, and corrects the four
places that still call the alias target "unverified" (CTO F7). Every ruling is recorded in
`knowledge-base/project/specs/feat-one-shot-12514-claude-code-cli-fable-bump/decision-challenges.md`.

## Research Reconciliation — Spec vs. Codebase

| Claim (issue #12514 / brief) | Reality (measured 2026-11-10) | Plan response |
|---|---|---|
| Bump the CLI pin (package.json + Dockerfile) | The hosted consumer of `fable` is the Agent SDK's bundled binary (`agent-runner-query-options.ts` sets no `pathToClaudeCodeExecutable`); the CLI copy only serves the crons, which never send `fable` | Move the SDK in lockstep, pen-cli with it (CTO F2) |
| "2.1.321 measured to contain it" (10 hits) | 25 occurrences by `grep -a -o`; 10 was a line count. 2.1.317-2.1.319 have 0; 2.1.320 was never published | Pin 2.1.321 / 0.3.321, the minimum pair (CTO F1) |
| "confirm that the `fable` alias resolves to 5.2 on the chosen version" | init-event probe: 5.1 on 2.1.311 / 0.3.311, 5.2 on 2.1.321 / 0.3.321 (bundled path; a server-side override for authenticated sessions is not ruled out) | One-time probe in PR body + trailer, image re-probe post-merge (CTO F6, F8) |
| Needs a lockfile regeneration | `min-release-age=3` blocks fresh resolution of both packages until 2026-11-12T19:03:36Z | Wait, no waiver (CTO F3); before the floor only static checks run, no new-package code (CTO F15) |
| The `sdk-bump-verified:` ack | Required for a version change of EITHER package; a CLI-only ack must name the cron hook control | Full #12026 evidence set plus the cron hook probe (CTO F4) |
| Prose: "whether `fable` resolves to 5.2 on the pinned CLI 2.1.311 is unverified" | It is measured: 5.1 | Correct the four sites (CTO F7) |
| (not in the issue) | The consult's bundled default effort moves "high" (5.1) -> "medium" (5.2) | Accept and record; standing effort row (CTO F9) |

## Research Insights

### Premise Validation (Phase 0.6)

- #12514 is OPEN (`gh issue view 12514`), no closing PR. The only open change naming it is this branch's own
  draft PR #12553 (`collision-precheck.sh 12514` exit 10, prs=12553, foreign=none) - not a collision.
- #8643 is OPEN, no open PR names it (`collision-precheck.sh 8643` exit 0).
- Cited pin sites exist on this branch (cut from `origin/main` at e5ad65a67b): `apps/web-platform/package.json`
  pins `@anthropic-ai/claude-agent-sdk` 0.3.311 and `@anthropic-ai/claude-code` 2.1.311; the Dockerfile
  `cli-tools` stage runs `npm install -g @anthropic-ai/claude-code@2.1.311` under a `KEEP IN SYNC` comment.
- The issue's measurement holds and was extended (below). Its count "10 hits" was a `grep -c` line count; the
  `grep -a -o | wc -l` occurrence count is 25. Both say the same thing: present.
- The premise "nothing sends a fable id as an argv value" still holds: `git grep -n -i fable` over
  `apps/web-platform/server`, `lib`, the Dockerfile, package.json and `.github/workflows` returns only
  substrings of "spoofable"; `plugins/soleur/lib/harness-model-map.ts` maps `advisor: "fable"`.
- The issue framed the goal as the CLI pin only. The hosted agent runner is a second, larger consumer
  of the `fable` alias (below), which the issue does not name.

### Measured evidence (2026-11-10, `npm pack` of the linux-x64 platform packages, unpacked in the session scratchpad, outside the repo)

| package@version | `claude-fable-5-2` occurrences | sha256 of `claude` | Bun banner | `--model fable` resolves to (init event) |
|---|---|---|---|---|
| claude-code-linux-x64@2.1.311 | 0 | 86dc1fcc69498159eaf15f446613e847010f9036bfbbdffd4c49350be8489ada | Bun v1.4.4 | `claude-fable-5-1` |
| claude-code-linux-x64@2.1.317 | 0 | eb224419e344575f... | - | - |
| claude-code-linux-x64@2.1.318 | 0 | 708c77b204db3008... | - | - |
| claude-code-linux-x64@2.1.319 | 0 | dabafec82ca1319f... | - | - |
| claude-code-linux-x64@2.1.321 | 25 | 426c33815ca6645a772f722fbff10dbf2cbdb124a8aeab733c1365dbf8bbf61f | Bun v1.4.4 | `claude-fable-5-2` |
| claude-agent-sdk-linux-x64@0.3.311 | 0 | 86dc1fcc... (same as CLI 2.1.311) | Bun v1.4.4 | `claude-fable-5-1` |
| claude-agent-sdk-linux-x64@0.3.321 | 25 | 426c3381... (same as CLI 2.1.321) | Bun v1.4.4 | `claude-fable-5-2` |

- 2.1.320 / 0.3.320 were never published; 2.1.321 / 0.3.321 is the first release carrying the id.
- Alias probe (zero cost, no credential): `env -i PATH=/usr/bin:/bin HOME=<tmp> ANTHROPIC_API_KEY=sk-ant-invalid-probe
  <binary> -p hi --model fable --output-format stream-json --verbose --max-turns 1`; the `system/init` event
  carries `"model":"<resolved id>"` and `claude_code_version`, then the turn fails 401. It measures the
  bundled resolution path. The 2.1.321 bundle carries both `fable:{default:"claude-fable-5-2",...}` and a
  `provider_alias_targets:{fable:{default:"claude-fable-5-1",...}}` table; the init event resolves 5-2, but
  an authenticated session could in principle receive a remote override, so a real-key `modelUsage` read is
  the authenticated confirmation.
- Both versions honour `ANTHROPIC_DEFAULT_FABLE_MODEL` (14 and 16 occurrences).
- Package manifests (`npm view`): `@anthropic-ai/claude-code@2.1.321` has `scripts.postinstall: node install.cjs`
  and no `dependencies`; `@anthropic-ai/claude-agent-sdk` `peerDependencies` are identical at 0.3.311 and 0.3.321
  (`zod ^4.0.0`, `@anthropic-ai/sdk >=0.93.0`, `@modelcontextprotocol/sdk ^1.29.0`).
- Bundled `default_effort` rows: `claude-fable-5-1` "high" (2.1.311 and 2.1.321), `claude-fable-5-2` "medium"
  (2.1.321), `claude-opus-5-5` and `claude-sonnet-5-5` "medium" on both, so `REVIEWED_DEFAULT_EFFORT` holds.
- Coarse sandbox-vocabulary diff 2.1.311 -> 2.1.321: the 19 `apply-seccomp: <step>` strings are identical and
  the quoted bwrap-flag vocabulary counts are identical. A hint, not a proof: the byte-level census in
  `sandbox-vendored-argv-tail.test.ts` and the runtime suites are the proof.
- Publish times (npm `time`): claude-code 2.1.321 2026-11-09T19:02:47Z, 2.1.322 2026-11-10T01:58:41Z;
  agent-sdk 0.3.321 2026-11-09T19:03:36Z, 0.3.322 2026-11-10T01:57:38Z. dist-tags: claude-code
  `stable`=2.1.311, `latest`=`next`=2.1.322; agent-sdk `latest`=0.3.322.
  `apps/web-platform/.npmrc` `min-release-age=3` means 2.1.321 and 0.3.321 cannot be freshly resolved before
  2026-11-12T19:03:36Z (the later of the two).
- Price direction: Fable 5.2 lists below Fable 5.1 on every row (ADR-053 2026-11-09 addendum: input 8 vs 10,
  output 40 vs 50, cache read 0.20 vs 0.25 $/MTok), so moving the alias from 5.1 to 5.2 lowers the consult
  gates' per-token cost. No spend increase to authorize.

### Where the `fable` alias is resolved (the two consumers)

1. **Hosted agent runtime** - `apps/web-platform/server/agent-runner-query-options.ts` passes
   `plugins: [{ type: "local", path: trustedPluginPath }]` (the soleur plugin) and no
   `pathToClaudeCodeExecutable`, so hosted sessions run the Agent SDK's own bundled binary
   (`@anthropic-ai/claude-agent-sdk-linux-x64`). The plan Step 4.5 and ship Phase 5.5 consult gates run
   there for hosted users and resolve `fable` through THIS binary. Pinned 0.3.311 resolves it to 5.1.
2. **Cron CLI** - `/app/node_modules/.bin/claude` (`_cron-claude-eval-substrate.ts`) from the
   `@anthropic-ai/claude-code` dependency; the Dockerfile global install is its fallback. Pinned 2.1.311
   resolves it to 5.1.

### Gates and pin sites that a bump moves

- `apps/web-platform/scripts/sdk-bump-sandbox-gate.sh` (ci.yml `lockfile-sync` member of the required
  `guards-ruleset`): a lockfile version change of EITHER `@anthropic-ai/claude-agent-sdk` or
  `@anthropic-ai/claude-code` requires a `sdk-bump-verified:` token in a branch commit message.
- `apps/web-platform/test/claude-pin-lockstep.test.ts` (#12102): `CLI_VERSION` in
  `.github/workflows/scheduled-marketplace-drift.yml`, the Dockerfile install and package.json must be equal;
  the pen-cli override and every `@anthropic-ai/claude-agent-sdk*` entry in
  `plugins/soleur/skills/pencil-setup/scripts/pen-cli/package-lock.json` must equal the app's SDK pin. No test
  forces the CLI and SDK versions to equal each other.
- `apps/web-platform/test/sandbox-vendored-argv-tail.test.ts` `PINS` carry a `measuredVersion` per package
  (0.3.311, 2.1.311) and reds when an installed platform package differs from it; a CLI-only bump still has
  to re-measure and re-pin the `claude-code` row.
- Version-literal pins: `test/adhoc-npm-install-pin-table.test.ts` (Dockerfile literal),
  `test/broker-mechanism-spike.test.ts` (SDK declared and installed), `infra/sandbox-canary-argv.json`
  (`sdkVersion`, a capture fixture, never hand-edited), `server/sandbox-startup-classifier.ts` + test (step
  list measured on 0.3.311), `test/helpers/vendored-bwrap-tail.ts` (measured comments, Bun floor helpers).
- `apps/web-platform/test/server/inngest/claude-cli-pin-knows-models.test.ts` (#8603): tier ids in the
  claude-code binary, `REVIEWED_DEFAULT_EFFORT`, `AUDIT_EFFORT` acceptance, Bun >= 1.4.4 in both binaries.
  Nothing tests what the `fable` alias resolves to, and the SDK binary's model table is out of scope (#8643).
- CI `lockfile-sync` regenerates with `npm@11.21.1` (`npm install --package-lock-only`) in
  `apps/web-platform`, the repo root, `pencil-setup/scripts`, `spike` and `pen-cli`. `pen-cli` has no
  `.npmrc` (no release-age floor). `spike/` pins its own `^0.2.76` SDK and is out of scope.
- Stale prose stating "unverified (#12514)": `plugins/soleur/AGENTS.md` (Model Selection Policy, pricing
  paragraph), ADR-053 2026-11-09 addendum, ADR-083 2026-11-09 addendum,
  `plugins/soleur/skills/model-launch-review/SKILL.md` step 2 Fable note. Measured fact: on 2.1.311 / 0.3.311
  the alias resolves to Fable 5.1.

### Precedent

- #12026 / PR 12073 (2026-11-04): pair bump 2.1.293/0.3.284 -> 2.1.311/0.3.311 with a full real-SDK
  re-proof. Plan: `knowledge-base/project/plans/archive/20261104-203103-2026-11-04-fix-bump-claude-code-sdk-bun-1-4-4-pair-plan.md`;
  rulings: `knowledge-base/project/specs/archive/20261104-203103-feat-one-shot-12026-bun-claude-code-bump/decision-challenges.md`;
  ADR-079 addendum 2026-11-04.
- #8601 (2026-09-23): CLI-only bump 2.1.219 -> 2.1.280; the trailer had to name the cron allowlist-hook
  control, not the SDK canary replay.

### Institutional learnings applied

- `learnings/2026-09-23-the-deferral-rested-on-a-sentence-nobody-had-measured.md` - the release-age floor gates
  new resolution only; a CLI-only trailer must name the cron allowlist-hook control, not the SDK canary.
- `learnings/workflow-patterns/2026-09-29-detached-precommit-watchdog-and-sdk-bump-attestation.md` - trailer
  recipe; background long batteries with `SOLEUR_TEST_ALL_ALLOW_ORPHAN=1 setsid nohup`.
- `learnings/workflow-patterns/2026-10-01-squash-merge-drops-branch-commit-trailers.md` - the trailer is read
  pre-merge only; anything a post-merge reader needs goes in the PR body too.
- `learnings/workflow-patterns/2026-06-30-update-branch-drifts-lockfiles-and-npm11-pin.md` - regenerate under
  npm@11; re-run `--package-lock-only` after any merge from main.
- `learnings/2026-10-09-a-rollback-recipe-nobody-had-run-and-a-baselined-file-touched-without-its-changed-lint.md` -
  the rollback is a `git revert` of the squash commit, run through the gates; not a prose recipe.
- `learnings/2026-07-03-faithful-canary-capture-must-run-in-the-deploy-base-image.md` and
  `learnings/security-issues/bwrap-args-payload-outer-resume-proc-mask-20261009.md` - capture in the deploy base
  image through `normalizeCapturedArgv`; the `infra/bwrap-shim` splice is coupled to the builder tail.
- `learnings/2026-11-03-base-image-cve-bump-is-a-pin-census-not-a-digest-edit.md` - the
  native binaries carry their own Bun; census both.
- `learnings/2026-04-15-sdk-v0.2.80-zoderror-allow-shape.md` - smoke the Write/Edit allow
  path end to end after an SDK bump.
- `learnings/workflow-issues/2026-11-09-an-alias-only-model-launch-is-a-table-retarget-and-the-prose-is-where-it-goes-wrong.md` -
  run the command before writing any tier, multiple or id into prose; strip comments in any pair-table parser.

### Property List (Phase 0.6b)

- P1. A hosted session's `fable` consult resolves to `claude-fable-5-2`: the Agent SDK's bundled binary knows the
  id and its alias table points at it.
- P2. The cron CLI binary (package.json copy and the Dockerfile global fallback) knows `claude-fable-5-2` and
  resolves `fable` to it.
- P3. No containment property regresses: the hosted bwrap/seccomp sandbox (credential deny, masked `/proc`,
  AF_UNIX isolation, canary fixture equality) and the cron PreToolUse allowlist hook, proven on the real binary.
- P4. The lockfiles resolve exactly the measured tarballs, and the 3-day release-age floor is respected.
- P5. A later pin move that loses a current model id (including the alias target) reds CI on both binaries.
- P6. Repository prose no longer says the alias target is unverified; it states the measured fact.
- P7. The bundled `default_effort` of each CLI-reaching tier and of the `fable` alias target is a reviewed
  value in both binaries, so a bump that moves it is visible (CTO F9).

### Cut List (Phase 0.6b)

- `ANTHROPIC_DEFAULT_FABLE_MODEL=claude-fable-5-2` on 2.1.311 -> P1/P2 -> defeated, not covered: 2.1.311 has no
  5-2 row, so the id would be halved (#6934). Cut (CTO F2b).
- A CLI-only bump -> P2 only -> leaves P1 unmet; the hosted runtime is where `fable` is actually spent. Cut (CTO F2).
- A new CLI-equals-SDK version equality test -> P5 -> already covered: the two `measuredVersion` rows in
  `sandbox-vendored-argv-tail.test.ts`, `claude-pin-lockstep.test.ts` and the new both-binaries id row.
- A live-API `--model fable` spawn test in CI -> P1 -> network-dependent; replaced by the one-time init-event
  probe (PR body + trailer) plus the binary id row (CTO F6).
- A new canary / observability surface -> P3 -> already covered by the deploy canary, SDK Bash smoke, runtime
  Bash synthetic and the startup classifier (ADR-079 addenda).
- A new ADR -> no new decision; ADR-079 / ADR-053 / ADR-083 addenda record the move.

## User-Brand Impact

- **If this lands as intended, the user experiences:** hosted plan Step 4.5 / ship Phase 5.5 consults run on
  Fable 5.2 instead of 5.1, at the 5.2 row's bundled default effort ("medium", against 5.1's "high") and at a
  lower list price (input 8 vs 10, output 40 vs 50 $/MTok). Whether a `model: fable` Task inherits the parent
  session's effort instead is not measured. Nothing else changes for the user.
- **If this lands broken, the user experiences:** every hosted Concierge / agent Bash call failing at sandbox
  spawn (the 2026-07-01 and 2026-10-06 EPERM shapes), a workspace session that cannot start, or Write/Edit
  approvals surfacing a schema error (the SDK 0.2.80 allow-shape class); on the cron side, an audit cron whose
  Bash allowlist hook no longer fires.
- **If this leaks, the user's data / workflow is exposed via:** a silently changed bwrap builder that stops
  masking `/proc`, stops denying the credential paths or re-opens AF_UNIX reach, letting one tenant's Bash read
  a sibling session's sockets, persisted CLI output or credentials; or a cron CLI whose PreToolUse
  allowlist hook stops dispatching, letting a prompt-injected cron run arbitrary commands with its token.
- **Brand-survival threshold:** `single-user incident`
- **Threshold decision (challengeable):** the change is a model-alias retarget on paper, but it moves the
  native binary that builds every hosted sandbox. One cross-tenant read is brand-ending for a product whose
  pitch is isolated agent workspaces, so `aggregate pattern` is too lax. CPO sign-off is required before
  `soleur:work` (Domain Review below); `soleur:engineering:review:user-impact-reviewer` runs at review time.

## Proposed Solution

1. **Before the floor, run none of the new code (CTO F15).** Author and push the non-pin changes; do static
   supply-chain checks only (manifest and `install.cjs` diff, integrity, sha256).
2. **Gate G1 (time).** Nothing from 2.1.321 / 0.3.321 is installed, run or committed as a pin before
   2026-11-12T19:04:00Z. After it: regenerate the lock, then run the CTO F4 evidence set on the installed tree
   inside a throwaway container (Phase R). Red rows that trace to a pin shape are re-measured; any other red
   stops the bump.
3. **Two commit groups.** Before G1, the non-pin commits (guards, parser, constant, test-selection edge, prose,
   ADR addenda) are pushed to the draft PR; their Guard 4 red against the old pins is the expected draft state.
   After G1, ONE pin commit moves everything that is version-bearing: both pins, Dockerfile, drift-workflow
   `CLI_VERSION`, pen-cli override, both lockfiles regenerated normally under npm@11, the re-measured pins and
   fixture, and the `sdk-bump-verified:` trailer, written only after every F4 arm passes against the installed
   lockfile tree. The PR squash-merges, so main sees one commit either way.
4. **Post-merge** image and telemetry evidence (CTO F8), then close #12514.

## Alternative Approaches Considered

| Approach | Verdict | Why |
|---|---|---|
| CLI-only bump (the issue's literal scope) | Rejected (CTO F2) | Leaves hosted `fable` on 5.1; still needs the trailer and the argv-tail re-pin |
| `ANTHROPIC_DEFAULT_FABLE_MODEL=claude-fable-5-2` on 2.1.311 | Rejected (CTO F2b) | 2.1.311 has no 5-2 row; the id would get half `max_tokens` (#6934) |
| Pin 2.1.322 / 0.3.322 (`latest`) | Rejected (CTO F1) | Unmeasured, clears the floor later, buys nothing |
| One-off `--min-release-age=0` | Not taken (CTO F3) | Operator-only waiver; p3 issue; waiting costs two days (decision-challenges F3b) |
| Hosted effort env var to keep the consult at "high" | Rejected (CTO F9) | Changes effort for every hosted session on every model: an operator spend decision, out of scope |
| Live-API alias test in CI | Rejected (CTO F6) | Network-dependent and flaky; the init probe is recorded once and re-run post-merge |

No deferral is created by this table: every rejected item is rejected, not postponed.

## Implementation Phases

### Phase 0 — Baseline (read-only)

- 0.1 Re-run `npm view @anthropic-ai/claude-code@2.1.321 time dist.integrity` and the same for
  `@anthropic-ai/claude-agent-sdk@0.3.321` and both `-linux-x64` platform packages; record the integrity
  strings. If either version is deprecated or unpublished, stop and re-ask the CTO (F1 re-target clause).
- 0.2 `git grep -n -E '2\.1\.311|0\.3\.311' -- ':!knowledge-base' ':!**/package-lock.json'` and keep the list:
  it is the sweep set for Phase 2 (CTO amendment 1). At planning time it names the files in `## Files to Edit`.
- 0.3 Confirm the rollback pair 2.1.311 / 0.3.311 still resolves (`npm view ... version`), read only.
- 0.4 Tooling: `docker info` and `command -v bwrap` both succeed (both did on the planning host,
  2026-11-10). The fixture capture (2.7) runs only locally - CI's capture gate runs `--verify`, never capture -
  so without docker the PR stays draft and the work phase stops with the reason.

### Phase 1 — Before Gate G1: non-pin work and static supply-chain checks (CTO F15)

No code from 2.1.321 / 0.3.321 runs before Gate G1: the release-age floor exists so a bad release is caught
before it runs on a host that holds credentials. Only acts that execute none of the new packages' code happen
here.

- 1.0 Author the non-pin changes first, on the branch, and push them to the draft PR (Guard 4 reds against the
  old pins by design; the PR is draft). Note that the runner edit touches a capture input
  (`server/agent-runner-query-options.ts` is in the `sandbox-canary-capture-gate` trigger list), so the draft
  push runs the capture gate's `--verify` against the unchanged 0.3.311 fixture: `server/agent-model-defaults.ts` and the runner
  edit (2.8), the shared parser (confirm first that web-platform vitest resolves
  `plugins/soleur/test/lib/autofix-pairs.ts` the way it already resolves `plugins/soleur/test/lib/git-fixture-env.ts`;
  keep it a pure string-in, ids-out module with no runner import, each suite reading `audit-models.sh`
  itself), Guards 4 and 5 with their mutation matrices written as standing synthetic tests before the guard bodies (2.9), the
  test-selection edge (2.10), and the prose and ADR edits (2.11, 2.12). None of this depends on Gate G1.
  Build the Guard 5 synthetic rows from the real 2.1.321 row text (measured, not modelled).
- 1.1 Static checks only: `npm pack` the four 321 tarballs and the two 311 parent tarballs into a fresh empty
  directory outside every repo tree (download and unpack; run nothing from it); diff `install.cjs`,
  `package.json` (`dependencies`, `optionalDependencies`, `peerDependencies`, `scripts`) of claude-code and
  agent-sdk 311 vs 321 and record the diff in the draft PR body - any change beyond the platform-package
  versions is a finding to bring to the CTO before G1; record each tarball's `dist.integrity` (from `npm view`
  and from `openssl dgst -sha512 -binary <tgz> | base64`) and each `claude` binary's sha256 (expect
  `426c33815ca6645a772f722fbff10dbf2cbdb124a8aeab733c1365dbf8bbf61f`) in the PR body, since the session
  scratchpad does not survive the pause. If an advisory or an unpublish hits 2.1.321 before G1, stop and
  record `Operator-authorizes:` rotation of this host's credentials (decision-challenges F15b).

### Gate G1 — release-age floor (time)

`[[ $(date -u +%s) -ge $(date -u -d '2026-11-12T19:04:00Z' +%s) ]]` must be true before Phase 2. If the work
phase reaches this gate earlier, it commits nothing that moves a pin, leaves the PR draft with the Phase 1
evidence in its body, and ends with `Paused: release-age floor clears 2026-11-12T19:04Z` and the resume
prompt. This is a scheduled wait, not an operator step (CTO F3). Only the operator can shorten it
(decision-challenges F3b).

### CTO F16 added checks (2026-11-10, from the Phase 1.1 installer diff)

Phase 1.1 found claude-code 2.1.321's `install.cjs` and `cli-wrapper.cjs` changed beyond the platform-package
versions: a new `resolvePlatformPackageDir()` that only reads files and refuses (install exit 1) on two installed
copies of the platform package or an unreadable manifest. Ruled by CTO agent, 2026-11-10 (decision-challenges
F16): proceed to G1, with these checks. Each is mirrored in `tasks.md` under the same id.

- **2.5a** (static, both locks): no claude-code / agent-sdk package under two paths, none nested.
- **R-1.1r-a** (container): `npm ci` with scripts exits 0; a fresh copy passes `npm ci --omit=dev` as root; one
  copy of each linux-x64 platform package; `bin/claude.exe` sha256 `426c3381...`; `cli-wrapper.cjs --version` =
  2.1.321 (the path `--ignore-scripts` CI trees take).
- **R-1.9a**: an `EDUPLICATEPKG` / `EUNREADABLEPKG` error blocks like 1.9; never worked around.
- **2.13a**: `docker build --target deps` exits 0; in cli-tools the global `bin/claude.exe` sha256 and one platform copy.
- **2.14a**: one trailer and PR-body row for the installer refusal checks; the runner-stage build is validated only
  by the release build (4.1).

### Phase 2 — The pin commit (after G1)

- 2.1 `apps/web-platform/package.json`: `@anthropic-ai/claude-agent-sdk` `0.3.321`, `@anthropic-ai/claude-code`
  `2.1.321`. `cd apps/web-platform && npx --yes npm@11 install --package-lock-only` (no override flag).
- 2.2 `apps/web-platform/Dockerfile`: `RUN npm install -g @anthropic-ai/claude-code@2.1.321` (comment block
  unchanged except a version mention, if any).
- 2.3 `.github/workflows/scheduled-marketplace-drift.yml`: `CLI_VERSION: "2.1.321"`.
- 2.4 `plugins/soleur/skills/pencil-setup/scripts/pen-cli/package.json` `overrides` SDK `0.3.321` (overrides only:
  its `dependencies` carries only `@pen.dev/cli`, and adding the SDK there would create a new direct dependency
  in a user-facing install prefix); `cd plugins/soleur/skills/pencil-setup/scripts/pen-cli && npx --yes npm@11 install --package-lock-only`.
- 2.5 Lockfile proof (CTO F5): for `node_modules/@anthropic-ai/claude-agent-sdk-linux-x64` and
  `node_modules/@anthropic-ai/claude-code-linux-x64`, lock `integrity` == `npm view <pkg>@<v> dist.integrity`
  == the integrity recorded in the PR body in 1.1 (re-run `npm pack` after G1 and assert
  `sha512-` + `openssl dgst -sha512 -binary <tgz> | base64` equals it; the Phase 1 tarballs may be gone); a scratch `npm ci` installs
  binaries with sha256 `426c3381...`. Every platform entry of both packages (all eight) is at the new version.
### Phase R — Re-proof (after Gate G1 and steps 2.1-2.5), in a throwaway container (CTO F4, F15)

- 1.1r `npm ci` from the regenerated lock (the step 2.5 tree) and a control tree at 2.1.311 / 0.3.311
  (`git worktree add --detach <control> origin/main`, `npm ci`). The claude-code postinstall (`node install.cjs`)
  and every non-docker spawn below run inside a throwaway container: repository tree read-only, tmpfs `HOME`, no
  `~/.doppler`, `~/.ssh`, `~/.config/gh`, no docker socket. `npm audit signatures` on the installed tree.
  Confirm `node_modules/.bin/claude --version` prints `2.1.321`.
- 1.2 `sha256sum` both installed `claude` binaries and every binary a suite spawns (including
  `node_modules/.bin/claude`'s resolved target): each must EQUAL
  `426c33815ca6645a772f722fbff10dbf2cbdb124a8aeab733c1365dbf8bbf61f`, asserted, not just recorded - a
  recorded-but-wrong hash is how this re-proof would pass vacuously. Run Guards 4 and 5 from this tree
  here: both pass, and Guard 4 reds in the control tree. Record both HEAD SHAs in the PR body. Bun probe
  `grep -a -m1 -o -E 'Bun v[0-9]+\.[0-9]+\.[0-9]+ \(' <bin>` on both: `Bun v1.4.4 (` or newer.
- 1.3 RED baseline, unchanged tests against the installed tree: `sandbox-vendored-argv-tail`,
  `sandbox-startup-classifier`, `claude-cli-pin-knows-models`, `broker-mechanism-spike`,
  `adhoc-npm-install-pin-table`, `claude-pin-lockstep`, `sandbox-canary`, `sandbox-credential-deny-argv`,
  `test/server/home-census.test.ts` (it describes the 2.1.311 plugin-store layout under HOME).
  Record which rows red and why (expected: `measuredVersion`, version literals, lockstep; anything else is a
  finding).
- 1.4 CTO F4 runtime evidence against the installed tree, each asserting the sha256 of the spawned binary and a
  NON-skipped run (a skipped credential-deny suite reads like a pass): `agent-sandbox-credential-deny-behavioural`
  (real SDK, GH_TOKEN visibility, #12469; gated on `SANDBOX_OK`), the real-bwrap rows of
  `bwrap-userns-seccomp` (production BPF and unix-deny filters; gated on `BWRAP_OK`),
  `sandbox-wrapped-command-runtime` (production-config block, the AF_UNIX-deny variant and its negative
  control), `sandbox-credential-deny-runtime`, `sandbox-proc-mask-runtime`,
  `apps/web-platform/infra/sandbox-masked-proc-docker.test.sh` (not optional; without local docker/sudo the PR
  stays draft; the only CI stand-in is `infra-validation`'s `deploy-script-tests-fixed` job, which runs
  `sudo bash apps/web-platform/infra/sandbox-masked-proc-docker.test.sh`, and it counts only on a head that
  carries the pin commit - `sandbox-canary-verify-in-image` is a plain `docker run` without the seccomp /
  AppArmor / uid posture and is NOT a stand-in), and `node apps/web-platform/scripts/sandbox-canary.mjs --replay`
  (verdict `pass`, not `canary_infra_error`). Seccomp proof: `seccomp-bwrap.json` against 0.3.321 is proven by
  the docker suite's `wrapped` arm (control and treatment run the real SDK under the profile) and the egress arm
  of `sandbox-wrapped-command-runtime.test.ts`; `--replay` and the docker replay arm replay the committed
  fixture, so they count only from the 2.13 run after the 2.7 re-capture. The trailer names them that way.
- 1.5 Cron containment (model-launch-review step 2b), using the `<control>` tree's 2.1.311 as the control: settings = `DEFAULT_CLAUDE_SETTINGS` plus
  `apps/web-platform/server/inngest/cron-bash-allowlist-hook.mjs` copied under its ORIGINAL filename under a
  `*` matcher; spawn the 2.1.321 CLI `-p --output-format json --model claude-sonnet-5-5` asking for a
  non-allowlisted `echo`; require it in `.permission_denials[]`; repeat on 2.1.311 as the control; include a
  known-deny control so a vacuous probe cannot pass.
- 1.6 Alias probe (zero cost) on both installed binaries:
  `env -i PATH=/usr/bin:/bin HOME=<tmp> ANTHROPIC_API_KEY=sk-ant-invalid-probe <bin> -p hi --model fable --output-format stream-json --verbose --max-turns 1`
  must show `"model":"claude-fable-5-2"` and `"claude_code_version":"2.1.321"` in the `system/init` event.
- 1.6b Credential handling for every real-key run (security review): the key is written to a 0600 file in a
  fresh temp dir and exported by a `bash -c` wrapper that reads it (never `ANTHROPIC_API_KEY=<value>` on a command
  line, which shows in `/proc/<pid>/cmdline`); `env -i`, temp `HOME`, `PATH=/usr/bin:/bin`; only
  `jq '.modelUsage|keys'` (or `.permission_denials`) is recorded; the temp `HOME` and key file are `rm -rf`'d
  after the run. Authenticated alias probe (CTO F12): one `-p hi --model fable --max-turns 1 --output-format json` turn on
  the installed 2.1.321 binary (sha256 asserted), `env -i HOME=<tmp>`, the Doppler config `ci`
  `ANTHROPIC_API_KEY` read-only (exported for this one run, never printed, no xtrace, never `prd`). Pass only
  if the `modelUsage` keys contain `claude-fable-5-2`. It proves the ci key's account at that time; production
  and tenant accounts stay "not validated" in the trailer.
- 1.7 Write/Edit allow-path smoke through the real SDK (`canUseTool` allow shape, learning 2026-04-15): an
  existing suite that drives an approved Write end to end, or the `scheduled-real-sdk-ask-probe` recipe run
  locally; record which.
- 1.8 Re-measure from the installed binaries: the argv-tail census (`MEASURED_SHAPE`), the helper step strings
  (classifier census), the bridge anchors, and the `default_effort` rows for every id the new effort guard
  reads. Expected from the planning measurement: 19 `apply-seccomp:` strings unchanged, bwrap vocabulary
  unchanged, opus-5-5 / sonnet-5-5 "medium", fable-5-2 "medium".
- 1.9 Stop condition: any red not explained by a pin shape blocks the bump; post the failing rows on #12514
  the same day and re-ask the CTO. The PR stays draft.


### Phase 2 (continued) — re-pin, capture, guards, trailer

- 2.6 Version-literal pin sites (sweep set from 0.2, plus `test/server/home-census.test.ts` if 1.3 reds it): `test/adhoc-npm-install-pin-table.test.ts`,
  `test/broker-mechanism-spike.test.ts`, `test/sandbox-vendored-argv-tail.test.ts` `PINS` (both
  `measuredVersion` rows, re-measured counts, new measured date), `test/helpers/vendored-bwrap-tail.ts`
  (measured comments), `server/sandbox-startup-classifier.ts` + its test (only if 1.8 shows a change), and the
  version mentions in comments (`scripts/sandbox-canary.mjs`, `server/untrusted-content.ts`,
  `test/sandbox-canary.test.ts`, `test/sandbox-credential-deny-argv.test.ts`,
  `test/sandbox-credential-deny-runtime.test.ts`, `test/sandbox-wrapped-command-runtime.test.ts`). The
  `infra/betterstack-logs-alerts.tf` comment ("19 step strings ... at SDK 0.3.311") is a historical
  measurement and is not edited, so no Terraform file is in this diff. A comment that records a historical measurement stays as
  history and gains the new measurement next to it; a comment that asserts the CURRENT pin moves.
- 2.7 Regenerate `infra/sandbox-canary-argv.json` with
  `SANDBOX_CANARY_MODE=capture bash apps/web-platform/scripts/sandbox-canary-verify-in-image.sh` (Doppler config
  `ci` `ANTHROPIC_API_KEY`, read-only, exported for the one run, never printed, no xtrace, never `prd`; CTO
  #12026 F13). `sdkVersion` must read `0.3.321`. Never hand-edit.
- 2.8 (authored in 1.0) SDK default constant (CTO F6r condition 2): create `apps/web-platform/server/agent-model-defaults.ts`
  exporting `AGENT_DEFAULT_MODEL = "claude-sonnet-5-5"`; `server/agent-runner-query-options.ts` uses
  `args.model ?? AGENT_DEFAULT_MODEL` and its `model?:` doc comment names the constant instead of the literal.
- 2.9 (authored in 1.0) Guards 4 and 5 (`## Guard Contract`) in
  `test/server/inngest/claude-cli-pin-knows-models.test.ts`, with the shared parser
  `plugins/soleur/test/lib/autofix-pairs.ts` (extracted from `parseAutofixPairs` in
  `plugins/soleur/test/model-launch-review.test.ts`, which then imports it). Write the mutation matrices first,
  then the guards. Update the file's header comment: the SDK binary is now in scope (remove the
  "out of scope — tracked in #8643" sentence), and the "CI twin" sentence about `audit-models.sh` `[2b]` says the
  test is now WIDER than `[2b]` (both binaries, `AUTOFIX_PAIRS` targets, SDK default) while `[2b]` stays the
  hand-run claude-code CANDIDATE check.
- 2.10 (authored in 1.0) Test selection (CTO F6r condition 4): check whether the local affected gate derives an edge from
  `claude-cli-pin-knows-models.test.ts` to `plugins/soleur/skills/model-launch-review/scripts/audit-models.sh`
  and to `plugins/soleur/test/lib/autofix-pairs.ts` (`scripts/test-all.sh` derivation; the web-platform leg
  selects through `apps/web-platform/scripts/vitest-related.sh`, an import graph, which reaches the parser
  module but never a file read with `readFileSync`, so `audit-models.sh` is expected to need the declared
  edge); if not, declare it in
  `scripts/lib/test-affected-paths.sh` as `AFFECTED_<LABEL>_PATHS` for that registration, and run
  `scripts/lint-orphan-test-suites.sh`. CI: `scripts/ci-oracle-lane.sh` only skips legs when every path is in
  the oracle surface, and `audit-models.sh` is not, so the full battery runs; record that reading.
- 2.11 Prose (CTO F7, F9, F6r): `plugins/soleur/AGENTS.md` Model Selection Policy pricing paragraph;
  ADR-053 2026-11-09 addendum ("These are list prices..." sentence); ADR-083 2026-11-09 addendum (the effort
  row and the closing "version-agnostic" sentence); `plugins/soleur/skills/model-launch-review/SKILL.md` step 2
  Fable note (repoint at the new guard, keep the "do not merge a Fable `--fix`" instruction) and its
  release-age passage (a same-week retarget PR stays red until the pins clear the floor, by design). State the
  measured fact only: on 2.1.311 / 0.3.311 the bundled resolution is `claude-fable-5-1`; on 2.1.321 / 0.3.321
  it is `claude-fable-5-2`; hosted sessions resolve through the SDK binary; local consult gates resolve through
  the operator's own unpinned CLI; a server-side override is not ruled out; the bundled row default effort is
  "medium" (never "the consult runs at medium"). Leave the 2026-11-09 learning untouched.
- 2.12 ADR-079 short addendum dated on the commit day (`## Architecture Decision (ADR/C4)`), then
  `bash plugins/soleur/test/c4-count-parity.test.sh`.
- 2.13 After 2.6-2.12, on the branch head's installed tree (inside the same throwaway container): the full
  affected vitest set; the `--replay` and docker replay arms again, now against the 2.7 re-captured fixture
  (they count only from this run); `docker build --target cli-tools -f apps/web-platform/Dockerfile
  apps/web-platform` and the Bun banner + invalid-key alias probe on that stage's global `claude`.
- 2.14 Commit with a `sdk-bump-verified:` trailer (CTO amendment 3) listing, each with the binary sha256 it
  ran: the runtime arms (including the two 1.4 additions), `--replay`, capture, the census re-measure, the cron
  hook probe and its control, the invalid-key and authenticated alias probes; and as NOT validated: a server-side alias override for production or tenant accounts, the non-x64
  platform binaries (covered by lock version equality only), whether a `model: fable` Task inherits the
  parent session's effort, and how a hosted session in flight at the image swap behaves (the deploy replaces
  the container as every release does; resume across the binary change is not separately tested). Copy the trailer text into the PR body too (squash-merge drops branch trailers).

### Phase 3 — PR and CI

- 3.1 Push; check the real exit code. PR body: `Ref #12514`, `Closes #8643`, the measurement table, the alias
  probe output (old and new), sha256s, the Phase 1/2.13 evidence table, the trailer text, `## Changelog`,
  label `semver:patch`.
- 3.2 Gates: required `test` and `guards-ruleset` (`lockfile-sync` with `sdk-bump-sandbox-gate.sh`). Also read
  the non-required `sandbox-canary-capture-gate` (must have run the in-image `--verify` with no drift, not the
  ack fallback) and `infra-validation` runs on the pushed head, record their run ids, and mark ready only when
  both passed.
- 3.3 After any rebase on main: `npx --yes npm@11 install --package-lock-only` in both directories and the
  fixture byte-diff before re-queuing. Never push to a queued PR.

### Phase 4 — Post-merge evidence (image and telemetry only, no SSH)

- 4.1 From the published release image: sha256 of
  `/app/node_modules/@anthropic-ai/claude-agent-sdk-linux-x64/claude`,
  `/app/node_modules/@anthropic-ai/claude-code-linux-x64/claude` and the global `claude` all equal
  `426c3381...`; the invalid-key `--model fable` probe inside the image reports `claude-fable-5-2`.
- 4.2 Per-host deploy status for web-1 and web-2 (`/hooks/deploy-status`, web-2 read from
  `.peers["10.0.1.11"]`) shows the release, canary verdict ok with `sdk_version` `0.3.321`, SDK Bash smoke ok;
  Sentry shows no startup-classifier `helper_step_new` / unknown-step events from the release; a
  `canary_infra_error` or empty `sdk_version` counts as a failure.
- 4.3 The next audit cron run shows the hook denial path intact (Sentry / Better Stack, no new
  allowlist-bypass event); the next `scheduled-real-sdk-ask-probe` run is green.
- 4.4 Rollback. Triggers (any one): the image sha256 or invalid-key alias probe in 4.1 is wrong; a canary verdict
  other than ok, or an empty `sdk_version`, on web-1 or web-2; any startup-classifier `helper_*` /
  `bwrap_eperm` / `proc_mount_eperm` event from the release in Sentry; a hosted Bash failure report; the cron
  hook denial missing in 4.3. Method: a revert PR of the squash commit (lockfile, Dockerfile, fixture, pins and
  guards together back to 2.1.311 / 0.3.311; never the pin alone) with its own `sdk-bump-verified:` trailer,
  reusing the #12026 evidence for the `86dc1fcc...` binary that is in production today; the release-age floor
  does not block it (those versions are 15 days old and already locked). Redeploy happens through the normal
  `web-platform-release.yml` push trigger. No faster no-SSH containment was found: its `workflow_dispatch`
  inputs (`bump_type`, `skip_deploy`, the mirror escape hatch) build a new release and none redeploys an older
  tag (read 2026-11-10). Target: the revert PR is opened in the session the trigger is read; restore time is
  CI plus the release build plus the sequential web-1 / web-2 deploy (hours, as #12026 measured). Leave #12514
  open and comment the verdict.
- 4.5 Comment the evidence on #12514, then close it.

## Files to Edit

- `apps/web-platform/package.json` — both pins.
- `apps/web-platform/package-lock.json` — regenerated (npm@11).
- `apps/web-platform/Dockerfile` — global CLI install line.
- `.github/workflows/scheduled-marketplace-drift.yml` — `CLI_VERSION`.
- `plugins/soleur/skills/pencil-setup/scripts/pen-cli/package.json` — SDK override only.
- `plugins/soleur/skills/pencil-setup/scripts/pen-cli/package-lock.json` — regenerated (npm@11).
- `apps/web-platform/infra/sandbox-canary-argv.json` — re-captured, never hand-edited.
- `apps/web-platform/server/agent-runner-query-options.ts` — default model through `AGENT_DEFAULT_MODEL`.
- `apps/web-platform/test/server/inngest/claude-cli-pin-knows-models.test.ts` — Guards 4 and 5, header.
- `apps/web-platform/test/sandbox-vendored-argv-tail.test.ts` — `PINS` re-measured.
- `apps/web-platform/test/helpers/vendored-bwrap-tail.ts` — measured comments.
- `apps/web-platform/test/adhoc-npm-install-pin-table.test.ts` — Dockerfile literal.
- `apps/web-platform/test/broker-mechanism-spike.test.ts` — SDK declared / installed version.
- `apps/web-platform/server/sandbox-startup-classifier.ts` and `apps/web-platform/test/sandbox-startup-classifier.test.ts` — only if 1.8 shows a census change; otherwise the measured-version comment.
- Version-mention comments: `apps/web-platform/scripts/sandbox-canary.mjs`, `apps/web-platform/server/untrusted-content.ts`, `apps/web-platform/test/sandbox-canary.test.ts`, `apps/web-platform/test/sandbox-credential-deny-argv.test.ts`, `apps/web-platform/test/sandbox-credential-deny-runtime.test.ts`, `apps/web-platform/test/sandbox-wrapped-command-runtime.test.ts`.
- `plugins/soleur/test/model-launch-review.test.ts` — import the shared parser.
- `plugins/soleur/AGENTS.md` — Model Selection Policy pricing paragraph.
- `plugins/soleur/skills/model-launch-review/SKILL.md` — step 2 Fable note, release-age passage.
- `knowledge-base/engineering/architecture/decisions/ADR-053-per-call-model-tiering-for-workflow-subagent-spawns.md` — 2026-11-09 addendum sentence.
- `knowledge-base/engineering/architecture/decisions/ADR-083-scoped-strong-model-consult-at-decision-gates.md` — 2026-11-09 addendum effort row and alias sentence.
- `knowledge-base/engineering/architecture/decisions/ADR-079-faithful-sandbox-canary-and-profile-redeploy-verification.md` — short addendum.
- `scripts/lib/test-affected-paths.sh` — only if 2.10 finds no derived edge.

Not edited: `spike/` (its own `^0.2.76` SDK), `.bun-version`, `scripts/followthroughs/ci-claude-cli-pins-bun-12073.sh` (its floor 2.1.311 is a `>=` check that 2.1.321 satisfies), and the 2026-11-09 learning.

## Files to Create

- `apps/web-platform/server/agent-model-defaults.ts` — `AGENT_DEFAULT_MODEL`, added to the id harvest.
- `plugins/soleur/test/lib/autofix-pairs.ts` — the one `AUTOFIX_PAIRS` parser both tests import.

## GDPR / Compliance Gate (plan Phase 2.7)

**This is not legal review. Findings are heuristic. Consult `soleur:legal:clo` + `soleur:legal:legal-compliance-auditor` before merging.**

Invoked because the threshold is `single-user incident` (trigger b). Path scan: 0 of the planned files match
the canonical regulated-data regex (no migration, `lib/auth/`, `server/*auth*`, `app/api/` or `.sql` path).
The five v1 checks: `GDPR-Art-6`, `GDPR-Art-5e`, `GDPR-Art-17`, `GDPR-Art-17-caller` and `GDPR-Art-9` have
nothing to match (no schema change); `GDPR-Chapter-V` - no new vendor, SDK or env var: the processor stays
Anthropic under its existing DPA row, and the change selects a newer model of the same processor. No
findings; no `compliance/critical` action.

## Open Code-Review Overlap

None. Queried open `code-review` issues (200) for every path above, including `package-lock.json`,
`Dockerfile`, `claude-cli-pin-knows-models`, `sandbox-vendored-argv-tail`, `sandbox-canary-argv.json`,
`sandbox-startup-classifier`, `pen-cli`, `claude-pin-lockstep`, `model-launch-review/SKILL.md`, ADR-053,
ADR-083 and `sdk-bump-sandbox-gate`: no match.

## Observability

```yaml
liveness_signal:
  what: "Deploy-time faithful canary and SDK Bash smoke verdicts (verdict, sdk_version) in /hooks/deploy-status, the runtime Bash synthetic (ADR-079 addenda #10453, #10455 b), and the Sentry sandbox-startup classifier events (helper_userns_eperm, helper_step_eperm, helper_step_new, bwrap_eperm, proc_mount_eperm)"
  cadence: "per deploy (canary, smoke) and per hosted Bash call (classifier); per audit cron run (allowlist hook)"
  alert_target: "Sentry web-platform for the classifier and a faithful-replay sandbox_broken; Better Stack soleur-faithful-canary-sandbox-broken-prd for sdk_bash_smoke_failed (email); canary and smoke are report-only (no automatic rollback), so the Phase 4.2 deploy-status read is the detection step; canary_infra_error pages nobody and is read as a failure there"
  configured_in: "apps/web-platform/infra/ci-deploy.sh (canary and smoke verdicts), apps/web-platform/scripts/sandbox-canary.mjs, apps/web-platform/server/sandbox-startup-classifier.ts, apps/web-platform/infra/betterstack-logs-alerts.tf"
error_reporting:
  destination: "Sentry web-platform via SENTRY_DSN (classifier events carry errorCode, matchedLine, sdkVersion, helperStep)"
  fail_loud: "a lockfile version change without the sdk-bump-verified token reds the required guards-ruleset; a lost model id or a moved default_effort in either binary reds the required test check (Guards 4 and 5); sandbox-canary-capture-gate and infra-validation are not required and are read on the pushed head"
failure_modes:
  - mode: "the 0.3.321 builder changes the per-command bwrap tail or mount set, so hosted Bash fails at spawn or /proc is re-exposed"
    detection: "in-surface: the classifier reads the failing tool_result inside the hosted session (errorCode bwrap_eperm / proc_mount_eperm / helper_step_eperm with sdkVersion 0.3.321 and helperStep), which discriminates builder-tail drift from a seccomp-helper step failure in one event; pre-merge: TAIL_LITERALS / PROC_SITE_COUNT in sandbox-vendored-argv-tail.test.ts and the capture-gate byte-diff; host-side: the deploy-time SDK Bash smoke"
    alert_route: "Sentry issue; Better Stack sandbox-broken alert; required CI test"
  - mode: "a new apply-seccomp step string the classifier does not know"
    detection: "HELPER_STEP_NEW in sandbox-startup-classifier.test.ts (census against the installed binary); in-surface helper_step_new events if one escapes"
    alert_route: "required CI test; Sentry"
  - mode: "the cron CLI's PreToolUse allowlist hook stops dispatching under 2.1.321"
    detection: "pre-merge: the Phase 1.5 permission_denials[] probe with 2.1.311 control and a known-deny control; in-surface at runtime: the hook's own Sentry mirror inside the cron worker"
    alert_route: "PR evidence blocks the trailer; Sentry"
  - mode: "a later pin move drops a current model id (alias target, tier id, SDK default) from either binary, or a launch retarget lands before the pins carry the id"
    detection: "Guard 4 in claude-cli-pin-knows-models.test.ts against both installed binaries"
    alert_route: "required CI test check"
  - mode: "a later bump silently moves the bundled default_effort of a tier or of the fable alias target"
    detection: "Guard 5 (REVIEWED_DEFAULT_EFFORT and the reviewed fable row) in both binaries"
    alert_route: "required CI test check"
  - mode: "the shipped image carries the wrong binary, or its bundled alias resolution is not claude-fable-5-2"
    detection: "Phase 4.1 image sha256 and invalid-key init probe inside the published image (bundled resolution only; a server-side override is covered pre-merge, for the ci account only, by the 1.6b authenticated probe)"
    alert_route: "post-merge evidence step; rollback 4.4"
logs:
  where: "Sentry events and the Better Stack logs warehouse (source 2457081); canary and smoke verdict lines in the deploy-status payload"
  retention: "existing Sentry and Better Stack plans; no new sink"
discoverability_test:
  command: "jq -r '.packages[\"node_modules/@anthropic-ai/claude-agent-sdk\"].version' apps/web-platform/package-lock.json"
  expected_output: "0.3.321"
```

The probe reads the deploy-authoritative SDK pin from the committed lockfile in under a second. The binary
properties (ids, effort rows, Bun floor, argv tail) are asserted by the CI suites against the installed
binaries, which do not fit preflight's 15-second sandbox cap, and the shipped binaries are read in Phase 4.1.

## Guard Contract

### Guard 4 — Current model ids are known by both pinned binaries (CTO F6, F6r; closes #8643)

**Property.** Every model id the repository declares current (the RHS of `AUTOFIX_PAIRS`), every tier id the
cron CLI can receive, and the hosted SDK default model is present as a whole token in BOTH installed
platform binaries, `claude-code-linux-x64` and `claude-agent-sdk-linux-x64`.

**Assembly.** The id set is the union of three authorities, each read from its source file, never retyped:
(a) RHS of `AUTOFIX_PAIRS` in `plugins/soleur/skills/model-launch-review/scripts/audit-models.sh`, parsed by
the single shared helper `plugins/soleur/test/lib/autofix-pairs.ts` (block to the first `)`, comment lines
stripped, de-duplicated, `^claude-` only); (b) the existing `harvestIds()` over `server/inngest/model-tiers.ts`
and `server/inngest/leader-prompts/constants.ts`; (c) `server/agent-model-defaults.ts`, added to the same
harvest list. The chokepoint is the existing two-package loop: `BUN_FLOOR_PACKAGES` resolved through
`resolveVendoredBinary()` (`test/helpers/vendored-bwrap-tail.ts`, which throws `BINARY_MISSING` on ENOENT), the
same loop the Bun floor rows use; for each binary it calls the existing `absentIds()` over the whole union and
collects every absent `(package, id)` pair before failing. One shared assertion that both packages were
examined serves Guards 4 and 5. Skip rule: `shouldSkipRealBinaryRows(process.platform, process.arch,
process.env.CI)` (skips only off linux-x64 with CI unset; under CI an absent binary fails). The pair-count floor
(>= 11, today in `model-launch-review.test.ts`) moves into the shared parser beside a distinct-RHS floor (>= 4).
Not reached: the musl / arm64 / darwin / win32 variants (lock version equality only) and the Dockerfile global
install (pin agreement row; read in 4.1). These names avoid the file's existing `Guards 2/3 (#8603)` and
`Guard 1 (#12026)`.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Retarget one `AUTOFIX_PAIRS` pair to an id absent from the binaries (synthetic: `claude-fable-9-9`) | RED naming both packages and the id |
| 2 | Dispatch (shared with Guard 5): the package list resolves zero binaries, or only the claude-code one | RED (`checked` binary count must equal 2; "0 checked" cannot pass) |
| 3 | Second member after a compliant first: the SDK binary path pointed at a synthetic buffer that lacks `claude-sonnet-5-5` while the CLI binary is real | RED naming only `claude-agent-sdk` |
| 4 | Parser: the `AUTOFIX_PAIRS` block emptied, or every pair commented out | RED on the distinct-RHS floor (>= 4 today) and the raw pair floor, never "0 ids checked" |
| 5 | `agent-runner-query-options.ts` keeps or regains a raw `"claude-sonnet-5-5"` literal, even beside an `AGENT_DEFAULT_MODEL` import | RED (the tier harvest regex over the comment-stripped runner source must return `[]`) |

**Harness rows.** (a) Edit the suite, not the guard: make the shared parser return an empty list and require
row 4's floor to fire; make `absentIds` receive an empty id list and require a `checked ids >= floor`
assertion to red. (b) Must-PASS non-canonical inputs: a synthesized `AUTOFIX_PAIRS` block with an extra
commented-out pair (not counted) and an inline trailing comment after a live pair (still counted), and a
dated id (`claude-x-1-20260101`) in a buffer that must NOT vouch for its undated prefix (the existing
boundary semantics).

**Anchor.** The id set is derived from repository files a model-launch PR edits, so one diff can drop an id
from `AUTOFIX_PAIRS` and from the pins together; the guard proves consistency, not that the table is right.
Outside the commit: the `sdk-bump-sandbox-gate.sh` merge-base lockfile diff (trailer required on any pin
move) and model-launch-review's single-hop / deletion guards on `AUTOFIX_PAIRS`. The floors are paired with
set identity: row 3 targets a named member, not a count.

### Guard 5 — Reviewed default_effort rows in both binaries (CTO F9)

**Property.** For each CLI-reaching tier id and for the `fable` alias target (the `AUTOFIX_PAIRS` RHS of the
fable family), the bundled model-table row's `default_effort` in BOTH installed binaries equals the reviewed
value: `AUDIT_MODEL` medium, `EXECUTION_MODEL` medium, `claude-fable-5-2` medium; and the audit model's row
still advertises the `effort` capability.

**Assembly.** `REVIEWED_DEFAULT_EFFORT` (existing) plus a sibling `REVIEWED_ADVISOR_EFFORT` keyed by the
fable-family RHS id (so `tierRows`' audit-capability logic is not fed a non-tier key), both read through the
existing `modelRow()` helper (one row per id, 3000-byte window, throws on a missing or over-long row), called
once per binary from the same two-package loop as Guard 4 (whose row 2 covers this guard's dispatch).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Synthetic buffer whose `claude-fable-5-2` row reads `default_effort:"high"` | RED naming the id, the package and both values |
| 3 | Second member after a compliant first: the CLI row compliant, the SDK row moved to "low" | RED naming only `claude-agent-sdk` |
| 4 | Row absent for the fable target (id present elsewhere, no `{id:"...",family:` row) | RED "no model-table row", never read as a missing default |

**Harness rows.** (a) Suite edit: change the reviewed map to "high" for fable and require the real-binary row
to red (proves the comparison reads the real row). (b) Must-PASS non-canonical input: a synthetic row with
extra capabilities and a different field order that still carries `default_effort:"medium"`.

**Anchor.** The reviewed values are constants in the test, so one diff can move a default and the map
together; the guard forces the move to be visible in review and to name the ADR-083 / ADR-053 decision.
Outside the commit: the trailer requirement on any pin move.

### Implementation shape for Guards 4 and 5 (deepen-plan, test-design review)

- **Pure functions, so every mutation row is a standing synthetic test** (the file's existing
  `embedded Bun floor — synthetic mutation rows` pattern): `parseAutofixPairs(src: string)` (no disk read; the
  callers read `audit-models.sh`), a separate `assertPairFloors(pairs)` (>= 11 pairs, >= 4 distinct RHS), and
  `assertIdsKnown(rows, ids, required = BUN_FLOOR_PACKAGES)` modelled on `assertEmbeddedBunFloor`, fed
  `bufferSource` blobs in the synthetic rows and the two resolved binaries in the real row. Synthetic parser
  inputs of two or three pairs then exercise the parser without tripping the floors.
- **Coverage lives inside the shared per-binary function**, so both Guard 4 and Guard 5 call it and each has its
  own row-2 test (a Guard 5 loop over `[]` must red on its own, not only through Guard 4).
- **Harness row (a) of Guard 4 is a standing test:** `assertIdsKnown(rows, [])` throws on the checked-ids floor.
- **Parser edge rows:** a trailing `# was "a=b"` comment after a live pair is NOT a pair; a `)` inside a comment
  does not end the block (end the block at a line that is only `)`); one must-RED row for each. A literal
  `)` rule change must keep `model-launch-review.test.ts`'s existing rows green.
- **Guard 5 keys:** `REVIEWED_ADVISOR_EFFORT` is a LITERAL `{ "claude-fable-5-2": "medium" }`, never keyed at
  runtime from the derived value (that would carry "medium" to an unreviewed `claude-fable-5-3`); a separate
  assertion requires the set of distinct `^claude-fable-` RHS values in `AUTOFIX_PAIRS` to EQUAL that key set
  (reds on zero, two, or a moved value).
- **Guard 5 must-PASS row** reorders only fields AFTER `family:` (e.g. `default_effort` before `capabilities`),
  because `modelRow()` anchors on `{id:"<id>",family:`; add a must-RED row with `family` before `id` so the
  anchor is stated behaviour. Measured: the `claude-fable-5-2` row in 2.1.321 is ~1015 bytes, inside the
  3000-byte window.
- **Guard 4 row 5** is a function over a source string: with comments stripped, the tier harvest regex run over
  `agent-runner-query-options.ts` returns `[]` (an import of `AGENT_DEFAULT_MODEL` beside a surviving
  `args.model ?? "claude-sonnet-5-5"` still reds); fed the reverted synthetic source in the synthetic row.
- **Cost:** one `grep -aoE` per binary carrying every id pattern (not one 290 MB scan per id), or the 180 s
  timeout the Bun row uses; skip rule `shouldSkipRealBinaryRows`.

### Existing guards re-pinned, not redesigned

`sandbox-vendored-argv-tail.test.ts` (`PINS`, census, fixture equality), `sandbox-startup-classifier.test.ts`
(step census), the Bun floor rows in `claude-cli-pin-knows-models.test.ts`, `claude-pin-lockstep.test.ts`,
`adhoc-npm-install-pin-table.test.ts` and `broker-mechanism-spike.test.ts` keep their contracts (recorded in
the #12026 plan's Guard Contract); this PR only re-measures their pinned values against 2.1.321 / 0.3.321
and re-dates the measurement.

## Architecture Decision (ADR/C4)

Not a new decision; the bump follows ADR-079's SDK-bump discipline and ADR-083's consult gates. Three ADRs
would mislead after the change, so they are updated in this PR:

### ADR

- ADR-079: a short addendum (the pair 2.1.321 / 0.3.321, still one byte-identical binary; the evidence set
  and where the measured shape lives; Guard 4 now covers the SDK binary's model table, closing #8643; and the new cross-boundary contract: a
  plugin-side `AUTOFIX_PAIRS` retarget, which edits files that run on self-hosted users' own unpinned CLI, now
  also waits on the hosted app's pins, the F4 re-proof and the 3-day floor - intended per CTO F6r; the only
  scheduled consumer, `rule-audit.yml`, runs `audit-models.sh --detect` and opens no PR). No new
  ordinal is claimed, so there is no ordinal-collision risk.
- ADR-083: rewrite the 2026-11-09 addendum's effort row and closing sentence to the measured fact (CTO F7, F9).
- ADR-053: rewrite the 2026-11-09 addendum's "list prices, not spend in effect" sentence to the measured fact.

### C4 views

No C4 impact. Enumerated against `model.c4`, `views.c4` and `spec.c4`: external human actors (hosted founder,
plugin users, contributors) unchanged; external systems: `anthropic = system "Anthropic API"` and its edges
(`engine -> anthropic`, `claude -> anthropic`, `github -> anthropic`) are unversioned and unchanged;
containers: the Agent Runtime container's technology is the unversioned string "Claude Code"; no element
names a claude-code / agent-sdk version or a Fable id (`grep -E '2\.1\.[0-9]{3}|0\.3\.[0-9]{3}|fable'` over the
three files finds no version and no Fable element); access relationships unchanged. The work phase re-reads
the three files in full before concluding and runs `bash plugins/soleur/test/c4-count-parity.test.sh`.

### Sequencing

None; the addenda land in the pin commit.

## Domain Review

**Domains relevant:** engineering (CTO), product (CPO sign-off for the single-user-incident threshold)

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Rulings F1-F9 and F6r (decision-challenges.md). Net: exact pair 2.1.321 / 0.3.321; SDK moves in
lockstep with pen-cli; wait for the release-age floor; the #12026 real-SDK evidence set plus the cron hook
probe before any trailer; lockfile proved against the measured tarballs; standing both-binary id and effort
guards derived from `AUTOFIX_PAIRS`; prose corrected; image and telemetry evidence post-merge with a revert
path.

### Product (CPO sign-off)

**Status:** reviewed — CPO sign-off: approved with conditions (2026-11-10). Framing and the `single-user incident`
threshold confirmed. Conditions: (1) an intended-outcome line in User-Brand Impact - applied; (2) a post-merge
consult quality signal - recorded as decision-challenges F11 (spot read in Phase 4.5, no new monitor);
(3) rollback triggers and a time target, and confirmation the floor never blocks the revert - applied in 4.4;
(4) in-flight sessions at the image swap - listed as not validated in the trailer (2.14).

### Product/UX Gate

**Tier:** none (no UI surface: no `components/**/*.tsx`, `app/**/page.tsx` or layout file in Files to Edit/Create).
**Decision:** not applicable
**Agents invoked:** none
**Skipped specialists:** none
**Pencil available:** N/A (no UI surface)

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "bump the pinned @anthropic-ai/claude-code CLI (apps/web-platform/package.json and Dockerfile, currently 2.1.311) to a release whose bundle knows claude-fable-5-2" [brief] | Phase 2.1-2.3; F1 | mapped |
| 2 | "Needs a CTO ruling on the supply-chain bump" [brief] | decision-challenges F1, F3 | mapped |
| 3 | "the sdk-bump-verified ack" [brief] | Phase 1.4-1.6, 2.14; F4 | mapped |
| 4 | "lockfile regeneration" [brief] | Phase 2.1, 2.4, 2.5; F5 | mapped |
| 5 | "confirmation that the `fable` alias resolves to 5.2 on the chosen version" [brief] | Phase 1.6, 2.13, 4.1; F6 | mapped |
| 6 | "the plan must decide (via CTO) whether the SDK moves in lockstep" [brief] | F2; Phase 2.1, 2.4 | mapped |
| 7 | "must locate the existing sdk-bump-verified ack mechanism and any CI gate pinning CLI/SDK sync" [brief] | Research Insights (gates and pin sites) | mapped |
| 8 | "Bump first, in the same PR, if any web-platform tier, cron or `MODEL_PRICING` row gains a fable ID literal. Otherwise revisit at the next scheduled CLI bump and confirm the `fable` alias resolves to 5.2 on the chosen version." [issue #12514] | Premise validation (no fable literal); Phase 1.6, 4.1 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Pin edits, lockfiles, Dockerfile | asks 1, 4 | asked |
| SDK + pen-cli move | ask 6 | asked |
| Drift workflow `CLI_VERSION` | — | inferred — justification: `claude-pin-lockstep.test.ts` reds the required `test` check unless it equals the package.json pin |
| Phase 1 static checks and the Phase R runtime evidence set | ask 3 | asked |
| Gate G1 (time) | ask 2 | asked |
| Guard 4 (both-binary ids, `AUTOFIX_PAIRS`-derived), shared parser, `agent-model-defaults.ts` | ask 5 | asked; #8643 fold-in inferred — justification: CTO F6, its re-evaluation trigger ("the next claude-agent-sdk bump") fires on this PR |
| Guard 5 (effort rows) | — | inferred — justification: CTO F9; the bump moves the consult's bundled default from high to medium, and without a row a later flip is invisible |
| Test-selection edge | — | inferred — justification: CTO F6r condition 4; Guard 4 reads a file in the plugin tree |
| Prose corrections (AGENTS.md, ADR-053, ADR-083, SKILL.md) | ask 5 | asked |
| ADR-079 addendum | — | inferred — justification: `wg-architecture-decision-is-a-plan-deliverable`; ADR-079's last addendum describes 0.3.311 as current |
| Re-pinned existing guards and comment sweep | — | inferred — justification: each reds the required `test` check on a version move |
| Phase 4 rollback | — | inferred — justification: canary and smoke are report-only, and the threshold is single-user incident |

### Split Assessment

- Subsystems touched: 4 roots — `apps/web-platform`, `plugins/soleur`, `.github`, `knowledge-base` (plus `scripts/` only if 2.10 needs the edge)
- Planned files: 30 (lockfiles counted) | Estimated changed lines: ~350 excluding lockfile churn
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR — the threshold trips on roots and file count, but every edit is forced by the
  same atomic version move: `claude-pin-lockstep` and `sdk-bump-sandbox-gate` require the pins, drift workflow,
  pen-cli and trailer in one change, and the prose/ADR edits describe the state this commit creates. A split
  would ship a window in which the docs or the guards describe the wrong binary.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `jq -r '.dependencies["@anthropic-ai/claude-agent-sdk"], .dependencies["@anthropic-ai/claude-code"]' apps/web-platform/package.json` prints `0.3.321` and `2.1.321`.
- [ ] Every `node_modules/@anthropic-ai/claude-agent-sdk*` and `node_modules/@anthropic-ai/claude-code*` entry in `apps/web-platform/package-lock.json` has version 0.3.321 / 2.1.321 (16 platform entries plus the two packages); both `-linux-x64` integrity strings equal `npm view` and the integrity recorded in the PR body; `npx --yes npm@11.21.1 install --package-lock-only && git diff --exit-code -- package-lock.json` exits 0 in both `apps/web-platform` and `plugins/soleur/skills/pencil-setup/scripts/pen-cli`.
- [ ] `grep -c 'npm install -g @anthropic-ai/claude-code@2.1.321' apps/web-platform/Dockerfile` prints 1; `CLI_VERSION: "2.1.321"` in `scheduled-marketplace-drift.yml`; the pen-cli override is `0.3.321`.
- [ ] The pin commit's `git log -1 --format=%ct <pin-sha>` is >= `date -u -d '2026-11-12T19:04:00Z' +%s`, and CI `lockfile-sync` (which regenerates with the floor in force) is green on the head.
- [ ] The pin commit body and the PR body carry the `sdk-bump-verified:` text naming each arm with the binary sha256 it ran (`426c3381...`), the two added 1.4 suites as non-skipped, the cron hook probe with its 2.1.311 control, the invalid-key and authenticated alias probes, and the not-validated list.
- [ ] `infra/sandbox-canary-argv.json` was regenerated by the capture script and its `sdkVersion` is `0.3.321`.
- [ ] Guards 4 and 5 exist in `claude-cli-pin-knows-models.test.ts`, pass on both installed binaries, and every mutation-matrix row is a standing synthetic test in the same file (like the existing `embedded Bun floor — synthetic mutation rows`); only harness row (a) of each guard is a one-time manual check, recorded in the PR body. The file header no longer says the SDK binary is out of scope.
- [ ] `plugins/soleur/test/model-launch-review.test.ts` and `claude-cli-pin-knows-models.test.ts` import the one parser from `plugins/soleur/test/lib/autofix-pairs.ts`; `grep -c 'function parseAutofixPairs' plugins/soleur/test/model-launch-review.test.ts` prints 0.
- [ ] `grep -n 'claude-sonnet-5-5' apps/web-platform/server/agent-runner-query-options.ts` returns no code line (comments stripped), and the default reads `AGENT_DEFAULT_MODEL`.
- [ ] `git grep -c 'resolves to 5.2 on the pinned CLI 2.1.311' -- plugins/soleur/AGENTS.md knowledge-base/engineering/architecture/decisions/ADR-053-per-call-model-tiering-for-workflow-subagent-spawns.md knowledge-base/engineering/architecture/decisions/ADR-083-scoped-strong-model-consult-at-decision-gates.md` returns nothing (baseline 2026-11-10: one hit in each of the three files), and each of those three sites names `claude-fable-5-1` and `claude-fable-5-2`; the `model-launch-review/SKILL.md` Fable note points at Guard 4.
- [ ] Comment rule applied: no comment outside `knowledge-base/` asserts 2.1.311 / 0.3.311 as the CURRENT pin (historical measurement comments stay and gain the new measurement beside them).
- [ ] Required `test` and `guards-ruleset` green on the head; `sandbox-canary-capture-gate` ran in-image `--verify` with no drift and `infra-validation` passed on the same head (run ids in the PR body).
- [ ] ADR-079 addendum, ADR-083 and ADR-053 edits committed; `bash plugins/soleur/test/c4-count-parity.test.sh` green.

### Post-merge (agent-executed, image and telemetry only, no SSH)

- [ ] The three shipped `claude` binaries in the published image have sha256 `426c33815ca6645a772f722fbff10dbf2cbdb124a8aeab733c1365dbf8bbf61f`, and the invalid-key init probe inside the image prints `"model":"claude-fable-5-2"`.
- [ ] web-1 and web-2 deploy status show the release with canary verdict ok, `sdk_version` `0.3.321`, smoke ok; no unknown-step classifier events from the release.
- [ ] The next audit cron run and the next `scheduled-real-sdk-ask-probe` run are green.
- [ ] Evidence commented on #12514, then the issue closed; #8643 closed by the merge.

## Test Scenarios

### Acceptance Tests (RED phase targets)

- Given the control tree on 2.1.311 / 0.3.311 binaries, when Guard 4 runs, then it reds naming
  `claude-fable-5-2` in both packages (the property the bump fixes).
- Given the regenerated lock installed (2.1.321 / 0.3.321), when Guards 4 and 5 run, then both pass.
- Given a synthetic `AUTOFIX_PAIRS` retarget to an unknown id, when Guard 4 runs, then it reds.

### Regression Tests

- Production-config hosted Bash through the real SDK returns stdout; AF_UNIX-deny variant starts and cannot reach
  a sibling socket; the credential-deny decoy is unreadable; the sandbox `/proc` lists no outside pid.
- The canary fixture replays through the shim in the docker suite.
- The cron allowlist hook denies a non-allowlisted command on 2.1.321 as on 2.1.311.
- Write/Edit approval allow path completes end to end on 0.3.321.

### Edge Cases

- `--disable-userns` stays absent under the production config (`enableWeakerNestedSandbox: true`).
- The 2.1.321 bundle's second table (`provider_alias_targets.fable.default = claude-fable-5-1`): the init
  probe is what decides; the Guard 4 presence check alone is not proof of the alias target (stated in the
  trailer).
- A dated id in the bundle never vouches for its undated prefix (existing boundary semantics).
- All eight platform entries per package at the new version (musl, arm64, darwin, win32).
- Compare UTC to local time before reasoning about Gate G1.

### Integration Verification (for `soleur:qa`)

- **Pre-merge:** `cd apps/web-platform && npx vitest run test/server/inngest/claude-cli-pin-knows-models.test.ts test/sandbox-vendored-argv-tail.test.ts test/sandbox-startup-classifier.test.ts test/claude-pin-lockstep.test.ts`; `bun test plugins/soleur/test/model-launch-review.test.ts`.
- **Post-merge:** the Phase 4.1 image read and the 4.2 deploy-status read.

## Dependencies & Risks

- **Release-age floor:** Gate G1; the pipeline pauses rather than waives (F3, F3b).
- **Newer releases keep arriving** (2.1.322 already exists): F1 re-targets only on a pull or an advisory.
- **Fixture capture can refuse new tokens** (`normalizeCapturedArgv` fails loud on unknown options): fix the
  projection with measured evidence; if capture cannot run the PR stays draft; the trailer never substitutes.
- **Docker / sudo unavailable locally:** PR stays draft; `infra-validation`'s `deploy-script-tests-fixed` job on
  the pin-commit head stands in for the docker arm only (security review: `sandbox-canary-verify-in-image` is not
  a stand-in).
- **Server-side alias override:** an authenticated session could resolve `fable` differently from the bundled
  path; stated as not validated; Phase 4.1 re-probes the shipped image (still unauthenticated).
- **Consult quality:** the hosted consult moves from 5.1 at bundled-default high to 5.2 at bundled-default
  medium; accepted (F9); if quality is later seen to regress, that is an operator spend decision.
- **Coupling introduced by Guard 4:** a same-week model-launch retarget PR stays red until the pins clear the
  floor, by design (F6r), documented in model-launch-review's release-age passage.
- **Concurrent worktrees:** long batteries use `SOLEUR_TEST_ALL_ALLOW_ORPHAN=1 setsid nohup`.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only filler text, or omits the threshold
  will fail `deepen-plan` Phase 4.6; this one is filled and declares `single-user incident`.
- Probe the PLATFORM package (`*-linux-x64`), never the `@anthropic-ai` scope dir and never the ~23 kB launcher
  tarball; grep the native binary with `grep -a` (text-mode grep reports zero for every id).
- `npm pack` extracts to `./package/`; unpack outside every repo tree so the auto-fix surface never sees a
  binary full of model ids.
- The `sdk-bump-verified:` trailer is read pre-merge only (squash-merge drops branch trailers); the PR body
  carries the same text. The rollback revert PR needs its own trailer.
- Do not cite line numbers for changed anchors; use content strings.
- A historical measurement comment ("measured on 0.3.311") stays as history beside the new measurement; a
  comment asserting the current pin moves.
- Never claim "the consult runs at medium effort": only the bundled row default is measured.
- Check the real exit code of `git push` (no `| tail`).

## References

- Issues: #12514, #8643, #12026 (PR 12073), #12102, #8601, #6934, #12513.
- ADR-079 (canary, SDK-bump gate, 2026-11-04 addendum), ADR-083 (consult gates, 2026-11-09 addendum), ADR-053
  (tiering, 2026-11-09 addendum), ADR-191 (one lockfile per directory).
- `apps/web-platform/scripts/sdk-bump-sandbox-gate.sh`, `apps/web-platform/test/claude-pin-lockstep.test.ts`,
  `apps/web-platform/test/server/inngest/claude-cli-pin-knows-models.test.ts`,
  `apps/web-platform/scripts/sandbox-canary-verify-in-image.sh`,
  `apps/web-platform/infra/sandbox-masked-proc-docker.test.sh`,
  `plugins/soleur/skills/model-launch-review/SKILL.md` step 2b.
- Precedent plan: `knowledge-base/project/plans/archive/20261104-203103-2026-11-04-fix-bump-claude-code-sdk-bun-1-4-4-pair-plan.md`.
