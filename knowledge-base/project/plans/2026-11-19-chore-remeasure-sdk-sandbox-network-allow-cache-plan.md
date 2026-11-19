---
title: "chore: re-measure the SDK's per-host SandboxNetworkAccess allow cache on Agent SDK 0.3.328 (one-command re-run script)"
type: chore
date: 2026-11-19
slug: chore-remeasure-sdk-sandbox-network-allow-cache
branch: feat-one-shot-12906-sdk-allow-cache-remeasure
issue: 12906
closes: none
priority: p2
domain: engineering
brand_survival_threshold: none
lane: cross-domain
---

# chore: re-measure the SDK's per-host SandboxNetworkAccess allow cache on Agent SDK 0.3.328

PR-1b of the #11637 order (CTO ruling on #11637, 2026-11-19). `Ref #12906`. This PR does not close #12906.

## Enhancement Summary

**Deepened on:** 2026-11-19 (after a plan review the same day)
**Sections enhanced:** Proposed Solution (script steps 5, 8, 9b, 10, 10a; pointers; redaction), Verdict rules, Technical Considerations, Attack Surface, Phases 1 to 5, Guard Contract, Acceptance Criteria, User-Brand Impact
**Agents used:** plan review: dhh-rails-reviewer, kieran-rails-reviewer, code-simplicity-reviewer, soleur:engineering:cto (devex), a sharp-edges verification pass. Deepen: security-sentinel, test-design-reviewer, a verify-the-negative and stale-symbol sweep. CTO rulings: items 16 to 20.

### Key Improvements
1. **The baseline is a scratch install of `MEASURED_BASELINE`.** That one exported object is shared with the runtime suite and carries pinned integrity, so a bump branch can no longer measure the candidate twice (CTO items B and E).
2. **The run is contained.** `$HOME` and `$XDG_RUNTIME_DIR` are masked, and the worktree and git common dir are read-only, proven by a write probe that fails closed. npm runs with no access to the operator's npmrc token or cache (CTO item D).
3. **The classifier cannot read a blind sensor as a finding.** A fixed precedence table, count-based F2 rules, a `post-teardown-ran` precondition and the per-arm observed CLI version guard against it. MIXED is conclusive in its coherent direction (CTO item A).
4. **The operator can use it at the next bump without this plan.** It prints one `REMEASURE verdict= exit= reason= next=` line. A verdict-to-action table is in the script header and the ADR. `--markdown` writes the drafts.
5. **The offline tests can go red.** The stubs refuse any argv they do not model, the real classifier is wired in, and the clock, disk and timeout are stubbed.

### New Considerations Discovered
- `npm view <pkg> time --json` returns the whole time map. The floor must read `time[exact]`.
- `DETECTED bump` in `sdk-bump-sandbox-gate.sh` prints once per bumped package and is skipped without a base lockfile. The pointer `echo` goes after the loop.
- The git common dir (with `.git/hooks`) lies outside the worktree. Remounting the worktree alone would leave the hooks writable.
- `npm audit signatures` is not provenance. 0.3.328 has none.
- The harness `.mts` is outside the tsconfig include, so the runtime suite is its only typecheck.
- The discoverability probe returns rc=2 on this branch until #12897 merges and Phase 2 adds the command to the runtime suite. It is expected to pass after the Build stage.

## Overview

Evidence-only follow-up to #12585 (PR #12897). On Agent SDK 0.3.321, PR #12897 measured that the SDK remembers a `SandboxNetworkAccess` allow per host for the rest of the CLI session. The permission callback is then never asked again for that host, so a later deny for it can never be given. That finding is why the arm ships deny-all (`gateway-unverified`) and why #12906, a real allow arm, is blocked.

This plan re-runs the same network-namespace measurement against 0.3.328, the current npm release, installed in a throwaway directory. The production pin stays at 0.3.321. The run is committed as one command, so the next SDK bump can repeat it. The result goes into a dated ADR-278 addendum and a comment on #12906.

The work splits into two stages with different start conditions (CTO items 1 and 10):

| Stage | What | Starts when |
|---|---|---|
| Build | The harness override, the classifier, the re-run script, their unit suites, the pointer edits | #12897 has merged and this branch is rebased onto main |
| Measure (interim, this PR) | One real run on the newest SDK already past the floor (0.3.326 at or after 2026-11-19T18:44:37Z, else 0.3.325), the ADR-278 addendum, the #12906 comment | #12897 merged and this branch rebased (CTO item 21) |
| Measure (0.3.328, follow-up issue) | The 0.3.328 run and its records | Not before 2026-11-21T23:14Z, when 0.3.328 clears the 3-day release-age floor (CTO items 10 and 21) |

CTO item 21 replaced the earlier "stay draft and end with a resume prompt" rule: this PR merges with an interim measurement, labelled as such, and the 0.3.328 run is tracked in a follow-up issue filed before merge. No UNVERIFIED token is recorded for the floor, because the harness can run here.

## Research Insights

**Premise Validation (Phase 0.6).**
- #12906 is OPEN. Its body names the trigger: "An SDK release that re-asks per connection (the F/F2 runtime assertions go red when caching stops: that is the trigger)".
- PR #12897 is OPEN, auto-merge armed, head `cbe7f21beb`. It is not merged. Everything this plan builds on is on that branch only: `apps/web-platform/test/helpers/netns-egress-harness.mts`, `apps/web-platform/test/sandbox-network-access-runtime.test.ts`, `apps/web-platform/server/sandbox-network-access.ts`, and the ADR-278 2026-11-18 addendum. `git show origin/main:apps/web-platform/test/helpers/netns-egress-harness.mts` fails today. The plan therefore depends on the merge (CTO item 1).
- The CTO ruling on #11637 (2026-11-19) names this PR: "PR-1b (`Ref #12906`): re-measure the Phase 1a per-host allow cache at SDK 0.3.328 (main pins 0.3.321). Runs alongside PR-1."
- `npm view @anthropic-ai/claude-agent-sdk version` returns `0.3.328`. It was published 2026-11-18T23:13:27.778Z. Its `claudeCodeVersion` field is `2.1.328`. Its linux-x64 native binary package is 373 MB unpacked. Both packages are registry-signed, carry no provenance attestation, and have no install scripts.
- `apps/web-platform/.npmrc` sets `min-release-age=3` (ADR-191, #1174). npm reads that file only from the install cwd, so a scratch-dir install must pass the floor on the command line (CTO item 10). `npm install --help` on npm 11.20.0 lists `--min-release-age <days>`, and `npm audit` lists the `signatures` subcommand.
- `unshare -rnm true` succeeds on this host. Tool versions: node v26.12.0, npm 11.20.0, bubblewrap 0.13.1, kernel 7.2.15. Whether nested bwrap works inside the namespace is measured by the harness's own step 0, not assumed.
- Collision pre-check (`collision-precheck.sh 12906`) found PR #12966 (this branch's own draft) and PR #12897 (the PR that filed #12906, not a duplicate). It also found one foreign `test-all.sh` process in an unrelated worktree.

**Property List (Phase 0.6b).**
- P1 One command measures, for a given SDK version, whether a host the SDK already allowed is asked again after the forwarder is torn down, both within one command (arm F) and across commands of one session (arm F2).
- P2 The measured SDK is the requested version, installed outside the app. The app's `package.json`, `package-lock.json` and installed SDK are byte-unchanged afterwards.
- P3 A run that cannot see is never reported as a finding. A blind sensor, a failed precondition, a version mismatch or a failed same-host baseline yields INCONCLUSIVE. A host that cannot run the harness yields UNVERIFIED. A connection that escaped the forwarder yields LEAK.
- P4 The 0.3.328 result, with the exact command, versions and per-arm outcome, is in ADR-278 and on #12906.
- P5 The next SDK bump finds the command from the places a bump already lands: the runtime suite's `MEASURED_ON_SDK` failure, ADR-278's re-measure trigger, and `sdk-bump-sandbox-gate.sh`'s bump message.

**Cut List (Phase 0.6b).**
- Self-contained harness copy: cut. P1 is already bought by #12897's harness. A copy would be a second sensor with no agreement check (CTO item 1).
- Reading pass/fail of the existing vitest suite as the verdict: cut as the verdict source. A red run cannot tell "stopped caching" from "blind sensor" from "leak" (CTO item 3). The suite stays the pinned-version regression lane.
- A new CI lane on SDK-bump PRs: cut. P5 is bought by the existing red `MEASURED_ON_SDK` assertion and the ADR-079 ack gate (CTO item 7).
- New harness arms (allow-then-deny, PRODUCTION tap): cut. They are #12906's design work, and adoption re-runs the PRODUCTION arms anyway (CTO item 4).
- A `--allow-fresh-release` override: cut. Adoption cannot pin a version under the floor anyway (CTO item 10).
- Plan review cuts:
  - the classifier's `releaseAgeVerdict`: `--min-release-age=3` plus shell date arithmetic already cover it;
  - the `--baseline-expect` flag: a fixed rule, replaced by the single `MEASURED_BASELINE` object;
  - the `REMEASURE_*` env seams: replaced by stubs on `PATH` and a copied fixture tree;
  - the script's pre-checks for `ip`, `curl`, `socat` and `bwrap`: the harness's own step 0 covers them.
- Plan review declines:
  - one TS orchestrator in place of bash plus TS (CTO item C);
  - exact-version-only input: CTO item 6 ruled dist-tags resolved and both recorded;
  - folding MIXED into INCONCLUSIVE (CTO item A).

**Value-proposition measurement (Phase 0.6c).** Not a cost or performance claim. The cost of one run is two harness runs, each bounded by the script's 600 s timeout (the suite's own ceiling is 420 s), plus a roughly 380 MB install. There is no model API spend, because the harness drives a local scripted Anthropic stub (`test/helpers/anthropic-stub.ts`).

**Relevant code (content anchors; all on the #12897 branch until it merges).**
- `test/helpers/netns-egress-harness.mts`: `const { query } = await import("@anthropic-ai/claude-agent-sdk");` inside `runArm` is the only runtime SDK import. Spec shape `{ appRoot, scratch, tap, arms }`. Output lines `NETNS_STEP0 <json>` and `NETNS_ARM <json>`. `setupNamespace()` computes `step0.ok`. Arms `control`, `B`, `D`, `E`, `F` (`duringTurn` tears down after `.f-step1` and writes `.f-barrier`), `F2` (`followUps`).
- `test/sandbox-network-access-runtime.test.ts`: `MEASURED_ON_SDK = "0.3.321"` and its failure text "The SDK changed: re-run this suite's MEASUREMENT arms (B, D, E, F, F2) ...". `runHarness()` passes `env: { PATH, HOME: scratch, LANG, NODE_ENV }`. `assertNoLeak`, `assertAsked`, `DEAD_FORWARDER`. The F and F2 `it` blocks hold the exact 0.3.321 host sequences: F `["198.51.100.1"]`, F2 `["198.51.100.1", "example.test"]`.
- `server/permission-callback.ts` imports the SDK type-only (`import type { CanUseTool, PermissionResult }`). Whether the harness's `@/server/*` import closure loads the app's SDK copy at runtime is unverified (CTO item 2). That is why the loaded versions are observed in STEP0, not assumed.
- The SDK resolves its native CLI with `createRequire(import.meta.url)` relative to its own package. It tries `@anthropic-ai/claude-agent-sdk-linux-x64/claude` first on glibc. So importing the scratch install's `sdk.mjs` loads that install's binary.
- `scripts/real-sdk-ask-probe.sh` is the precedent for an outcome classifier with a distinct "blind" outcome and an offline `.test.sh`. `scripts/sdk-bump-sandbox-gate.sh` is the ADR-079 ack-token gate on SDK lockfile bumps.
- `test/probe-budget.test.ts` imports `../scripts/lib/probe-budget`, which is the precedent for a vitest suite over a `scripts/lib/*.ts` module. `scripts/lib/no-cross-context-import.test.sh` excludes `test/` from its check.
- `scripts/test-all.sh` `SUITE_GLOBS` includes `apps/web-platform/scripts/*.test.sh`, so a new `.test.sh` is auto-registered. `scripts/lint-orphan-test-suites.sh` requires that. No CI lint requires a `.sh` to have a test.
- `scripts/lint-shell-trace-credential-refusal.py` requires the xtrace refusal only where a live credential is bound. The new script binds none, and the harness env carries only the stub's decoy key.

**Institutional learnings applied.**
- `knowledge-base/project/learnings/2026-03-20-canusertool-caching-verification.md`: an earlier "canUseTool does not cache" verdict. Harness isolation needs `settingSources: []` and no pre-approval of the tool under test, which the harness already sets.
- `knowledge-base/engineering/operations/post-mortems/2026-10-11-hosted-bash-ask-bypassed-by-sdk-auto-allow-postmortem.md`: `autoAllowBashIfSandboxed` or an allow hook pre-empts canUseTool. `buildAgentSandboxConfig` sets `autoAllowBashIfSandboxed: false`. The floor of at least one recorded `SandboxNetworkAccess` call per arm guards the rest.
- `knowledge-base/project/learnings/2026-06-04-cron-silence-was-bwrap-userns-drift-not-turn-budget.md`: a probe on a different path than production misleads either way. The harness's step 0 already runs nested bwrap with `--proc /proc` through the production shim.
- `knowledge-base/project/learnings/2026-05-04-vacuous-red-via-shared-fixture-and-toolchain-pinning.md` and `2026-05-05-load-bearing-predicate-test-gap.md`: each verdict must prove its sensor fired, and the classifier tests must include inputs where two candidate verdicts differ.
- `knowledge-base/project/learnings/2026-04-19-claude-agent-sdk-subprocess-exit-tag-via-stderr-substring.md`: on a harness crash the script must surface stderr, not only the exit status.
- PR #12897's `2026-11-18-a-revocation-fix-closed-the-window-i-named-...md` noted that a hook blocks Bash calls carrying a literal stash token. Keep such tokens out of the script and its output.

**External research.** Skipped. The authority is the measured behavior of the installed package. npm flags were verified locally with `npm install --help` and `npm audit --help`.

**Functional overlap.** `soleur:engineering:discovery:functional-discovery` found no community artifact that installs a chosen SDK version or measures canUseTool caching. Nothing was installed.

**Rulings.** Every fork is recorded in `knowledge-base/project/specs/feat-one-shot-12906-sdk-allow-cache-remeasure/decision-challenges.md` (CTO items 1 to 10, 14, 15 and A to C; CLO items 11 to 13).

## Research Reconciliation — Spec vs. Codebase

| Brief claim | Reality | Plan response |
|---|---|---|
| "see apps/web-platform/test/helpers/netns-egress-harness.mts" | Absent on main; exists only on the open #12897 branch | Build stage waits for #12897 to merge, then rebases (CTO item 1) |
| "the plan knowledge-base/project/plans/archive/*fix-sandbox-network-access-canusetool-arm-plan.md" | Archived on the #12897 branch as `20261118-150540-2026-11-18-fix-...-plan.md`; absent on main | Cited from the #12897 worktree; it lands on main with the merge |
| Run against 0.3.328 "installed in an isolated harness directory" | The harness imports the SDK by bare specifier from the app's `node_modules` | One env override, `NETNS_SDK_ENTRY`, plus observed-version fields in STEP0 (CTO item 2) |
| Measure now | 0.3.328 is under the repo's 3-day release-age floor until 2026-11-21T23:13:27Z | The Measure stage waits for the floor; the script refuses fresher versions (CTO item 10) |
| "If the harness cannot run in this environment (no user namespaces)" | `unshare -rnm true` succeeds here; nested bwrap is unmeasured until step 0 runs | The script maps a failed step 0 to exit 3 and prints the `UNVERIFIED:` token; the issue path stays in the plan |

## Problem Statement

#12906's allow arm is blocked on one measured SDK behavior. The record of that behavior is pinned to 0.3.321, and the only way to re-check it today is to bump the production pin and watch the runtime suite go red. A red suite cannot say why it went red. The repo needs to read the behavior of a candidate SDK before adopting it, with a result that cannot be produced by a blind sensor.

## Proposed Solution

1. **Harness override (one edit to #12897's harness).** If `NETNS_SDK_ENTRY` is set, the harness imports `query` from `pathToFileURL(realpath(NETNS_SDK_ENTRY))`. Otherwise it keeps today's bare import, so the runtime suite is unaffected. Two kinds of observation are added (CTO item 2; plan-review sharp-edge pass):
   - `NETNS_STEP0` gains:
     - `sdkEntry`: the realpath of the module `query` came from. For the default path, resolve it with `fileURLToPath(import.meta.resolve("@anthropic-ai/claude-agent-sdk"))`, because `import.meta.resolve` returns a `file://` URL string. The SDK's `exports` map has `"."` with a `default` condition and no `./package.json` export.
     - `sdkVersion`: the `version` read from the `package.json` found by walking up from `sdkEntry` to the directory whose `package.json` `name` is `@anthropic-ai/claude-agent-sdk`.
     - `cliPath`: `createRequire(sdkEntry).resolve("@anthropic-ai/claude-agent-sdk-linux-x64/claude")`, the same lookup the SDK makes on glibc. The linux-x64 package has no `exports` field, so the subpath resolves.
     - `cliVersion`: the first whitespace-delimited token of that binary's `--version` output, compared for equality, never as a substring (plan review: Kieran 7).
   - Each `NETNS_ARM` record gains `initClaudeCodeVersion`: the `claude_code_version` of the SDK's `system`/`init` message seen in that arm's `query()` stream (`SDKSystemMessage`, `sdk.d.ts`). The message loop already iterates every message and today skips non-`user` ones. This is the observation of which binary actually ran, where `cliPath` only repeats the SDK's lookup.

   A probe failure records the field as `null` with an `...Error` string. It does not change `step0.ok`. The runtime suite's MEASUREMENT step-0 test also asserts `step0.sdkVersion === MEASURED_ON_SDK`. That checks the module actually loaded, which the existing `package.json` check does not.

2. **Classifier (`apps/web-platform/scripts/lib/sandbox-network-cache-verdict.ts`).** A pure module, plus a small CLI entry guarded so that importing it has no side effects.
   - **Inputs:** the baseline and candidate harness stdout files, and the expected SDK and CLI versions for each run.
   - **Processing:** it parses the `NETNS_STEP0` and `NETNS_ARM` lines and applies the rules in the next section.
   - **Outputs:**
     - a per-arm table;
     - one machine-read line, `REMEASURE verdict=<word> exit=<n> reason=<token> next=<action>`;
     - the verdict JSON (`--out`);
     - with `--markdown <dir>`, two data-only drafts, `addendum.md` and `issue-comment.md` (plan-review, CTO devex finding 3). Each holds the exact command, a versions table for both runs, the per-arm tables, the verdict and the exit code. Each also holds a marked placeholder where the dated policy sentences from ADR-278 go. The script never writes those sentences itself, because they carry dates and conditions that would go stale.
   - **Exit code:** the process exit code is the classifier's (CTO items 3 and 5).
   - **Single source of the pinned answer:** it exports `MEASURED_BASELINE = { version: "0.3.321", reading: "CACHES", fHosts: ["198.51.100.1"], f2Hosts: ["198.51.100.1", "example.test"], integrity: { sdk: "<dist.integrity of 0.3.321>", linuxX64: "<dist.integrity of its linux-x64 package>" } }`. The runtime suite imports `MEASURED_ON_SDK` from `MEASURED_BASELINE.version`, and its F and F2 blocks import the two host lists. A pin move then edits one object, and the suite and the classifier cannot drift apart (plan review: CTO devex 1, DHH 6, simplicity 1, sharp-edge 9). The two integrity values are copied from `npm view <pkg>@<v> dist.integrity` at build time (CTO item E).

3. **Re-run script (`apps/web-platform/scripts/remeasure-sdk-sandbox-network-cache.sh <version|dist-tag> [--out <path>] [--markdown <dir>] [--keep-scratch]`).** It honors `TMPDIR`. Each stage prints a progress line to stderr, such as `[10/11] candidate harness run (up to 10 min)`, numbered by script step. Every exit path ends with the `REMEASURE verdict=... exit=... reason=... next=...` line. On paths the script decides before the classifier runs, the verdict word is `UNVERIFIED`, `REFUSED` or `ERROR`.

   Steps:
   1. **Setup preflight.** The host must be Linux x64 with glibc, because the CLI lookup mirrors the SDK's glibc linux-x64 path. Any other host gets exit 3, reason `unsupported-arch` (plan review: Kieran 6). The setup also requires `node`, `npm`, `unshare` and the app's `node_modules/.bin/tsx`. If any is missing: exit 1, reason `setup-missing`, next `run npm ci in apps/web-platform`. This path prints no `UNVERIFIED` token, because a setup mistake is not a host limitation (CTO devex 5). The harness's own step 0 covers `ip`, `curl`, `socat` and `bwrap` (simplicity 8).
   2. **Namespace check.** If `unshare -rnm true` fails: exit 3, reason `no-userns`.
   3. **EXIT trap.** Set `scratch=""` and arm the trap before anything is written, so `set -u` holds on an early exit. It removes the scratch dir if one was created (unless `--keep-scratch` is set). It also re-hashes the app files. A changed hash forces exit 1 `app-mutated`, which overrides whatever exit the run was heading for.
   4. **App hash.** Hash the app's `package.json`, its `package-lock.json`, and every file under `node_modules/@anthropic-ai/claude-agent-sdk*`, using `find ... -type f -print0 | sort -z | xargs -0 sha256sum`. The hash covers the installed binaries, not only `package.json`, because the candidate CLI is itself a process that can write (sharp-edge 10).
   5. **Resolve the version.** Before any npm call, the argument must match `^([0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?|[a-z][a-z0-9-]{0,30})$`, which refuses `npm:` aliases, `file:` paths, git and tarball URLs (exit 1 `bad-version-arg`; deepen: security 4). The resolved exact version must match the semver half. Resolve the argument to an exact version with `npm view @anthropic-ai/claude-agent-sdk@<arg> version`. Record both the argument and the exact version (CTO item 6). Read the linux-x64 package version from the SDK's `optionalDependencies`.
   6. **Release-age floor.** Read `npm view <pkg> time --json` for the SDK and for `@anthropic-ai/claude-agent-sdk-linux-x64`. Select the `time["<exact>"]` key, never `created` or `modified`; the command returns the whole time map (sharp-edge 5, verified 2026-11-19). The check is plain shell date arithmetic (`date -u -d`). If either package is under 3 days old: exit 3, reason `release-age-floor`, next `re-run after <clear time>`, verdict word `REFUSED`, and no `UNVERIFIED` token (CTO item 10; plan review: DHH 1, simplicity 2).
   7. **Scratch dirs and disk.** Under one `mktemp -d` in `TMPDIR`, create two install prefixes, `baseline/` and `candidate/`. Each harness run gets its own fresh `spec.scratch` and HOME dir, as `runHarness` makes a fresh `mkdtemp` per run. That makes four directories in all, never shared between an install and a run (plan review: Kieran 8). Check that at least 2 GB is free there. Two installs of about 380 MB each fit with headroom, and `/tmp` is RAM-backed on some hosts (CTO devex 4).
   8. **Install.** Every npm call in steps 5 to 8 runs as `env -i PATH="$PATH" HOME="$root/npm-home" npm_config_userconfig=/dev/null npm_config_globalconfig=/dev/null npm_config_cache="$root/npm-cache" npm_config_registry=https://registry.npmjs.org/ npm ...`. The real `~/.npmrc` carries a registry auth token, and the shared `~/.npm` cache and any registry override must not reach the run (deepen: security 1). For each prefix, from inside it, run `npm install --prefix "$dir" --ignore-scripts --no-audit --no-fund --save-exact --min-release-age=3 @anthropic-ai/claude-agent-sdk@<v>`, then `npm audit signatures`. The baseline installs `MEASURED_BASELINE.version`; the candidate installs the exact requested version. If signatures fail: exit 3, reason `signature-verification-failed`, verdict word `REFUSED`, next `file a security issue; do not record a finding`, no `UNVERIFIED` token.
   9. **Version asserts.** In each prefix, assert that the installed SDK `package.json` version equals the requested one and that the linux-x64 binary exists. The expected CLI version comes from that install's `claudeCodeVersion` field, never a constant (CTO item 6).
   9b. **Integrity.** `npm audit signatures` is a registry signature and integrity check, not provenance: the packages carry no provenance attestation, so a stolen publish token would still yield a validly signed package. For the baseline prefix, the scratch lockfile's `integrity` for the SDK and linux-x64 tarballs must equal `MEASURED_BASELINE.integrity`. A mismatch is exit 3, reason `baseline-integrity-mismatch`, verdict `REFUSED`, and the candidate never runs, because published npm bytes never change. The candidate's two integrity values go into the verdict JSON and the addendum (CTO item E).
   10. **Harness runs.** Run the harness twice under `unshare -rnm` with a constructed environment: `env -i`, the keys `runHarness` passes (`PATH`, `HOME` set to a scratch dir, `LANG`, `NODE_ENV=test`), plus `NETNS_SDK_ENTRY` set to that prefix's `sdk.mjs`. Both runs set the entry, so the app's own `node_modules` SDK is never the measured one. That is what makes the baseline valid on a bump branch, where the app already pins the new version (plan review: CTO devex 1, amending CTO item 9's "default entry"). Each run uses spec `{ appRoot, scratch, tap: "allow-all", arms: ["control","B","D","E","F","F2"] }` (CTO item 4), with `cwd` the app root and `tsx --tsconfig <app>/tsconfig.json`, as `runHarness` does. It is launched as `timeout -k 10 600 unshare -rnm --fork --pid --mount-proc --kill-child ...`, so the CLI, forwarder and socat children die with the run and cannot outlive the trap (deepen: security 3). A timeout or a non-zero harness exit is exit 1 `harness-crash`, which prints the harness stderr tail with the sentinel redaction below applied.
   10a. **Containment (CTO item D).** Inside each run's mount namespace, before `tsx` starts, the script:
       - mounts a tmpfs over the real `$HOME` and over `$XDG_RUNTIME_DIR`;
       - bind-remounts read-only every worktree path listed by `git worktree list --porcelain` (this includes the main checkout, so every sibling under `.worktrees/` is covered) and the git common dir (`git rev-parse --git-common-dir`). The common dir lies outside a worktree and holds `.git/hooks`, so remounting only the app root would leave the hooks writable (CTO item 21 widened this from the current worktree alone);
       - asserts the scratch root lies outside `$HOME`, every listed worktree and the git common dir, else exit 3 `scratch-inside-protected-path`;
       - runs a write probe: creating a file must fail in `$HOME`, in every listed worktree and in the git common dir, and succeed in scratch. Any wrong result, or any failed mount, is exit 3 `containment-unavailable`. It never falls back to running uncontained;
       - sets `PATH` explicitly under `env -i`, with no shim directory under the masked `$HOME` (node resolves to `/usr/bin/node` on this host, and `tsx` is read from the app's `node_modules`).

       Remaining exposure, named in the verdict JSON and the addendum: `/tmp` outside scratch and the rest of the user-writable host filesystem. #12969 still owns masking for the shared harness and the vitest suite.
   11. **Classify.** Pass both outputs and the expected versions to the classifier, and propagate its exit code.

4. **Pointers (CTO item 7).** The exact one-line command is named in three places:
   - **The runtime suite's `MEASURED_ON_SDK` failure message.** It is reworded to give both versions and to say the script measures them side by side, for example "installed `<x>`, measured `<y>`: run `bash apps/web-platform/scripts/remeasure-sdk-sandbox-network-cache.sh <x>` (it installs both into scratch dirs), record the result in ADR-278, then update `MEASURED_BASELINE`" (CTO devex 6).
   - **The "Re-measure trigger" paragraph of ADR-278's 2026-11-18 addendum.** It names the command and gets the verdict-to-action table below (CTO devex 2).
   - **`scripts/sdk-bump-sandbox-gate.sh`.** One `echo`, printed once right after the per-package loop that prints the `DETECTED bump` lines, when any SDK package bumped. It does not depend on the ack trailer, unlike the missing-ack error (CTO devex 6). The `DETECTED bump` echo prints once per bumped package and is skipped when the base lockfile cannot be read (deepen: verify-the-negative).

   The script's header and `--help` also carry the verdict-to-action table, so whoever runs it at the next bump needs nothing from this archived plan (CTO devex 2):

   | Verdict | Action |
   |---|---|
   | CACHES | #12906 stays blocked; record the run in ADR-278 and on #12906 |
   | RE-ASKS-AFTER-TEARDOWN | Record the run; it triggers #12906's build and its live-forwarder deny-flip arm; it is not proof that an allow is revocable |
   | MIXED | Record the run; most consistent with a per-command cache; a trigger for #12906 like RE-ASKS-AFTER-TEARDOWN |
   | INCONCLUSIVE | Re-run once; then record the run and file an issue naming the reason |
   | ERROR | Fix the cause (`setup-missing`, `harness-crash`, parse) and re-run; `app-mutated` also files a bug against the script |
   | LEAK | Separate ADR-278 addendum plus a bug issue against adopting that SDK |
   | UNVERIFIED | Record `UNVERIFIED:sdk-<v>-sandbox-network-allow-cache` and file an issue |
   | REFUSED | No finding; wait for the floor (release-age), or file a security issue (signatures, baseline integrity) |

5. **Records (Measure stage).**
   - A new section in ADR-278: `## Addendum — <run date> (#12906): per-host allow cache re-measured on Agent SDK 0.3.328`.
   - A comment on #12906.
   - If the verdict is LEAK: a separate bug issue as well (CTO item 8).

### Verdict rules (CTO items 3, 5, 9 and 11; plan review)

The rules apply per run, then combine. The precedence is fixed (sharp-edge 4, simplicity 7):

| Rank | Condition | Verdict | Exit |
|---|---|---|---|
| 1 | Unparseable output, a missing `NETNS_STEP0` line, a `__harness__` crash record, or a malformed `NETNS_ARM` JSON line | ERROR | 1 |
| 2 | In either run, an arm other than `control` has a decoy hit or a gateway line with `authOk: false`. The `control` arm is excluded: it has no forwarder, so a gateway line there fails the `control` precondition instead. A baseline LEAK is reported as `LEAK (baseline)`, a finding against the production pin (plan review: Kieran 4 and 10) | LEAK | 4 |
| 3 | `step0.ok === false` in either run | UNVERIFIED (`step0:<failed fields>`) | 3 |
| 4 | A baseline precondition fails, or the baseline reading is not `MEASURED_BASELINE.reading` | INCONCLUSIVE (`baseline:<name>`) | 2 |
| 5 | A candidate precondition fails | INCONCLUSIVE (`candidate:<name>`) | 2 |
| 6 | The candidate reads INCONCLUSIVE (including `incoherent-f-f2`) | INCONCLUSIVE | 2 |
| 7 | The candidate reads CACHES, RE-ASKS-AFTER-TEARDOWN or MIXED | that word | 0 |

**Per-run preconditions.** Each one is an entry in one list that the combine step iterates:
- **`versions`:** the observed `sdkVersion` equals the version expected for that run, and `cliVersion` and every arm's `initClaudeCodeVersion` equal the expected CLI version.
- **`arms-present`:** every arm in `control,B,D,E,F,F2` emitted a record, and every `thrown` is the empty string (the harness defaults it to `""`).
- **`control`:** the control arm hit every decoy the silence checks rely on: `198.51.100.1:443`, `:80` and `:22`, `127.0.0.2:p` and `169.254.169.254:80`. Its gateway list is empty.
- **`teardown`:** `F` and `F2` each have `fStep1`, `fTornDown` and `fPortClosed` set to true. F's `f-barrier` and F2's `f2-barrier` results are both `seen=yes`. Each arm's whole gateway list equals exactly `["CONNECT 198.51.100.1:443 HTTP/1.1"]`, with `authOk` true. Gateway records carry no timestamp, so the check is on the whole list.
- **`post-teardown-ran`:** F's `f-3` result and F2's `f2-2` result match `DEAD_FORWARDER`, the regex the runtime suite uses, exported from the classifier so there is one copy. Without this check, a run in which the post-teardown curls never executed would read CACHES, a false finding from a blind sensor (plan review: Kieran 1).
- **`asked`:** every arm other than `control` and `D` recorded at least one `SandboxNetworkAccess` call, and every such call has a string `host`. Extra input keys do not fail the run. They are recorded as `inputShapeChanged` with the observed key set, and printed as a warning line. A new key matters to #12585's arm, which denies an unexpected key set as `malformed-host`, but it does not make this measurement blind (plan review: DHH 3).

**Per-run cache reading,** from the `SandboxNetworkAccess` host sequences. The harness records calls in order, but with no command index, so the F2 rule is written over counts (sharp-edge 3):

| F hosts | F2 hosts | Reading |
|---|---|---|
| exactly `MEASURED_BASELINE.fHosts` (`["198.51.100.1"]`) | exactly `MEASURED_BASELINE.f2Hosts` (`["198.51.100.1","example.test"]`) | CACHES |
| `198.51.100.1` two or more times, no other host | `198.51.100.1` two or more times, `example.test` at least once, no other host | RE-ASKS-AFTER-TEARDOWN |
| exactly `MEASURED_BASELINE.fHosts` (F caches within one command) | the F2 RE-ASKS pattern (the allowed host is re-asked on the second command) | MIXED: conclusive, and most consistent with explanation (iii), a cache per command (CTO item A) |
| the F RE-ASKS pattern | exactly `MEASURED_BASELINE.f2Hosts` | INCONCLUSIVE (`incoherent-f-f2`): no cache model fits it, so it is treated as a sensor fault and gets the one re-run (CTO item A) |
| any other sequence, for example F2 `["example.test"]` alone | | INCONCLUSIVE |

**Verdict JSON.** It holds:
- the requested argument, the exact versions and the expected CLI versions;
- for both runs, the observed `sdkEntry`, `sdkVersion`, `cliPath`, `cliVersion` and per-arm `initClaudeCodeVersion`;
- for each arm of both runs: the asked hosts, any `inputShapeChanged`, the gateway lines, the decoy hits and the precondition results;
- the environment: node, npm, kernel, bwrap and the host OS;
- the exact command line, and the UTC start and end times.

**Path and identity redaction (deepen: security 6).** Before any output is written, the classifier rewrites absolute paths to relative forms (`<scratch>/candidate/...`, `<app>/...`). It refuses to emit output containing the stub sentinel, the operator's `$HOME`, `$USER`, the hostname, or the forwarder's egress-token format. The same check runs on the `--markdown` drafts before Phase 5 posts them with `gh issue comment`. `--keep-scratch` prints a warning that the kept directory holds unredacted transcripts.

**Sentinel redaction.** The JSON never carries the harness's `stubRequests`, `toolResult` or `calls[].message` fields wholesale. The classifier copies only the fields listed above. As a backstop, it refuses to emit any output containing the stub's key sentinel (`decoy-api-key-sentinel`). The same check applies to the stderr tail the script prints on a crash (sharp-edge 12).

## Technical Considerations

- **Security of the measured binary.** The CLI runs outside bwrap, inside `unshare -rnm`, so there is no network during the run. The script's own run contains it (CTO item D): `$HOME` and `$XDG_RUNTIME_DIR` are masked with tmpfs, and the worktree and git common dir are read-only, proven by a write probe before `tsx` starts. What remains writable is scratch, `/tmp` outside scratch, and other user-writable host paths. The release-age floor lowers the odds of a bad release, and pinned baseline integrity plus the registry signature check verify the bytes. None of them is provenance (CTO item E). Masking for the shared harness and the vitest suite stays in #12969.
- **No production change.** Nothing under `apps/web-platform/server/`, `app/`, `infra/` or `lib/` changes. `package.json` and `package-lock.json` are asserted unchanged. The harness edit keeps the default path byte-for-byte equivalent for the existing runtime suite.
- **Required lane impact.** The runtime suite runs in ci.yml's `test-webplat` lane with `C4_BWRAP_REQUIRED: "1"`. The harness edit and the new step-0 assertion must stay green there. The new vitest classifier suite and the new `.test.sh` run in the existing shards (`test/**/*.test.ts` and the `apps/web-platform/scripts/*.test.sh` glob).
- **Known flake (#12914).** The PRODUCTION-phase arms flaked once in 12 runs with a forwarder that looked not-live. The MEASUREMENT arms use the allow-all tap and never consult `isLive`, but a forwarder that died early would drop F's pre-teardown CONNECT. The precondition "exactly one pre-teardown CONNECT" turns that into INCONCLUSIVE, not a false RE-ASKS-AFTER-TEARDOWN.
- **Harness ceilings (#12915 item 1).** There is still one 200 s abort per arm. The script's 600 s per-run timeout sits above the suite's 420 s ceiling, so a hang is reported as exit 1 with the harness stderr tail, not as a verdict.
- **NFR register.** No production NFR moves. The change touches only test infrastructure and records.
- **Determinism.** The arms are driven by the scripted Anthropic stub: fixed tool calls, no model. So one run per SDK is the measurement, and a single re-run is the response to INCONCLUSIVE. Repeating the run N times would only re-sample host noise, which the same-host baseline already controls.
- **Sandbox runtime location.** The app's `node_modules/@anthropic-ai/` holds `claude-agent-sdk`, its `-linux-x64` binary package, `claude-code`, `claude-code-linux-x64` and `sdk`. It has no separately resolved sandbox-runtime package, so the sandbox proxy that asks `SandboxNetworkAccess` ships inside the native CLI binary. That binary's version is what `cliVersion` records. If a later SDK splits the runtime into its own package, STEP0 must record that package's resolved path and version too, or the classifier cannot tell which copy ran.

### Attack Surface Enumeration

This PR adds no path from sandboxed code to the network. It measures one. The surfaces the run itself opens:

| Surface | Disposition |
|---|---|
| npm install of a candidate SDK (network) | Validated exact version or dist-tag, `--min-release-age=3`, `--ignore-scripts`, `npm audit signatures` (registry signature and integrity, not provenance), pinned baseline `dist.integrity`, `env -i` with scratch HOME, cache and `/dev/null` user and global npmrc, explicit registry, scratch cwd and prefix, app tree hash-checked |
| Candidate CLI binary executing on the host | No network (`unshare -rnm`); tmpfs over `$HOME` and `$XDG_RUNTIME_DIR`; worktree and git common dir read-only, with a write probe that fails closed (`containment-unavailable`); `--fork --pid --kill-child` so no child outlives the run. Remaining: `/tmp` outside scratch and other user-writable paths |
| Harness env | Constructed with `env -i` from the same keys the vitest `runHarness` passes; no ambient credential reaches the child |
| Verdict JSON and the #12906 comment | Hosts are the synthetic decoys (`198.51.100.1`, `example.test`, `metadata.test`); no workspace, user or credential value |

## Implementation Phases

Write the failing tests first in each phase (`cq-write-failing-tests-before`).

**Phase 0 — Gate.** Confirm `gh pr view 12897 --json state,mergedAt` reports merged. Then `git fetch origin && git rebase origin/main` on this branch. Never stash; commit WIP first if needed. Confirm `apps/web-platform/test/helpers/netns-egress-harness.mts` exists. If #12897 is not merged, stop: the PR stays a draft, and the session ends with a resume prompt.

**Phase 1 — Classifier (tests first).**
1. Create `apps/web-platform/test/sandbox-network-cache-verdict.test.ts`. Its fixture records are synthesized by a small in-test factory that builds fresh objects on every call, and are never copied from a real run (`cq-test-fixtures-synthesized-only`). Cases:
   - **Verdicts:**
     - CACHES: both runs read the `MEASURED_BASELINE` sequences.
     - RE-ASKS-AFTER-TEARDOWN: F re-asks the decoy IP, and F2 re-asks it while also asking `example.test`.
     - MIXED: F caches and F2 re-asks. It is exit 0.
     - INCONCLUSIVE `incoherent-f-f2`: F re-asks and F2 caches. It is exit 2.
   - **INCONCLUSIVE, one case per precondition.** Each case is a one-field change from the canonical fixture. Each asserts the exact `reason=candidate:<name>` (or `baseline:<name>`), not only exit 2. One test asserts that the canonical fixture passes every precondition (deepen: test-design 5).
     - control missed one decoy (each of the five, iterated);
     - `fPortClosed` false;
     - `f-barrier` or `f2-barrier` `seen=no`;
     - `f-3` or `f2-2` does not match `DEAD_FORWARDER`;
     - the gateway list is not exactly the one CONNECT;
     - zero `SandboxNetworkAccess` calls in arm B;
     - a missing arm record;
     - a `thrown` value;
     - the candidate's observed `sdkVersion` is 0.3.321;
     - `cliVersion` `2.1.321` against an expected `2.1.32` (exact-token check);
     - one arm's `initClaudeCodeVersion` differs.
   - **Extra input keys:** keys `["host","port"]` still read CACHES, with `inputShapeChanged` recorded.
   - **Baseline:** INCONCLUSIVE `baseline` when the baseline reads RE-ASKS-AFTER-TEARDOWN.
   - **LEAK:**
     - a decoy hit in the candidate's arm B;
     - a decoy hit in the baseline (`LEAK (baseline)`);
     - `authOk: false` in arm E;
     - precedence, one fixture per colliding pair: LEAK with a failed precondition, LEAK with `step0.ok` false in the other run, and a `control` gateway line, which is a precondition failure and not a LEAK.
   - **UNVERIFIED (exit 3):** `step0.ok` false in either run.
   - **F2 counts:** `["198.51.100.1","198.51.100.1","example.test","example.test"]` reads RE-ASKS-AFTER-TEARDOWN, and `["example.test"]` alone is INCONCLUSIVE.
   - **Parser:** noise lines between records are ignored. A malformed `NETNS_ARM` JSON line, empty stdout, or a missing `NETNS_STEP0` line is ERROR (exit 1), never a silent drop.
   - **Sentinel:** a fixture with `decoy-api-key-sentinel` in `stubRequests` and in `toolResult` never shows it in stdout, the `REMEASURE` line, the `--out` JSON or the `--markdown` drafts.
   - **Markdown:** `--markdown` writes both drafts, with the command, versions, per-arm tables and the policy placeholder.
2. Create `apps/web-platform/scripts/lib/sandbox-network-cache-verdict.ts` until the suite is green. It exports `MEASURED_BASELINE` and `DEAD_FORWARDER`, and its header carries the verdict-to-action table.

**Phase 2 — Harness override.**
1. Edit `test/sandbox-network-access-runtime.test.ts`:
   - Assert `step0.sdkVersion`, `step0.cliVersion` and each `initClaudeCodeVersion` are semver strings before comparing them, so two failed probes cannot pass as `null === null` (deepen: test-design 5).
   - Import `MEASURED_BASELINE` and `DEAD_FORWARDER` from the classifier module, and drop the local literals: `MEASURED_ON_SDK = MEASURED_BASELINE.version`, and the F and F2 blocks' host lists.
   - In the MEASUREMENT step-0 test, add `expect(run.step0.sdkVersion).toBe(MEASURED_ON_SDK)`. Also assert that every arm's `initClaudeCodeVersion` equals `step0.cliVersion`.
   - These assertions stay red until the harness records the fields.
2. In `test/helpers/netns-egress-harness.mts`:
   - read `NETNS_SDK_ENTRY`;
   - load `query` through a single `loadSdk()` that `runArm` uses;
   - record the four STEP0 fields without changing `step0.ok`;
   - capture `initClaudeCodeVersion` from the `system`/`init` message in the existing message loop, before its `msg.type !== "user"` skip.
3. Reword the `MEASURED_ON_SDK` failure message as in Proposed Solution 4. Per CTO item B, it says `MEASURED_BASELINE` moves only with a CACHES verdict and an ADR-278 addendum in the same PR.
4. Run the runtime suite locally under `unshare` (it skips without userns). It must stay green on 0.3.321 with zero skipped tests. This suite is the harness's only typecheck: `tsconfig.json` includes `**/*.ts`, not `.mts`.

**Phase 3 — Re-run script (tests first).**
1. Create `apps/web-platform/scripts/remeasure-sdk-sandbox-network-cache.test.sh`. It is an offline suite in the `real-sdk-ask-probe.test.sh` style (CTO item C).
   - **How it isolates the run:** stub `npm`, `unshare`, `uname`, `df`, `timeout` and glibc-probe executables come first on `PATH`.
     - Each stub accepts only the exact argv it models: `unshare` only `-rnm --fork --pid --mount-proc --kill-child`, `npm` only the exact `view`, `install` (all flags, including `--min-release-age=3`, `--ignore-scripts` and the exact `@<v>`) and `audit signatures` forms, and the hardened npm environment. Any other argv exits 64 and is logged to a refusal file that every row asserts empty. So dropping `-n`, `env -i`, the floor flag or `--ignore-scripts` turns a row red (deepen: test-design 1 and 2).
     - The stub `unshare` then runs the rest of its argv. A fixture harness prints synthesized `NETNS_*` lines and dumps its environment. A row asserts the env keys are exactly `{PATH,HOME,LANG,NODE_ENV,NETNS_SDK_ENTRY}`.
     - The fixture tree links the real `tsx` and copies the real classifier module, so the script-to-classifier wiring (argv, expected versions, exit pass-through) is what runs (deepen: test-design 3).
     - Fixture timestamps are offsets from now, at least one day from the 3-day line, except the exact-boundary row (deepen: test-design 4). Each row copies the script into a fixture app tree under the test's own `mktemp -d`, with a fake `node_modules/@anthropic-ai/claude-agent-sdk*`, and the script derives the app root from its own location. So there are no env seams, and nothing a real run could set to change its behavior (plan review: sharp-edge 1, DHH 2).
   - **Rows:**
     - an SDK whose `time["<exact>"]` is under the floor, while `created` and `modified` in the same map are old, gives exit 3 `release-age-floor`, verdict `REFUSED`, no `UNVERIFIED` token, and no `install` argv;
     - the same for a fresh linux-x64 package with an old SDK;
     - a failing `npm audit signatures` gives exit 3 `signature-verification-failed`, verdict `REFUSED`, no `UNVERIFIED` token, and no harness run;
     - a failing `unshare -rnm true` gives exit 3 `no-userns` and prints `UNVERIFIED:sdk-<v>-sandbox-network-allow-cache`;
     - a stub `uname -m` of `aarch64` gives exit 3 `unsupported-arch`;
     - a missing fixture `tsx` gives exit 1 `setup-missing` with no `UNVERIFIED` token;
     - a dist-tag argument is resolved, and both values reach the verdict JSON;
     - a stub that touches the fixture's `package-lock.json`, or any file under the fixture's installed SDK, gives exit 1 `app-mutated`;
     - the scratch dir is gone after every exit row, including a harness that exits non-zero, and is kept with `--keep-scratch`;
     - both harness runs receive `NETNS_SDK_ENTRY`, each pointing into its own prefix;
     - every row's last line matches `^REMEASURE verdict=\S+ exit=[0-9] reason=\S+ next=`;
     - classifier wiring: fixture harness outputs that classify as exit 0, 2 and 4 make the script exit the same code with the same `reason=`;
     - a package exactly 3 days old is allowed, and one a minute under is refused;
     - a stub `df` under 2 GB gives exit 1 `low-disk` with no install;
     - a stub `timeout` returning 124 gives exit 1 `harness-crash`, and its stderr tail contains no `decoy-api-key-sentinel`;
     - a fixture tree whose `claude-agent-sdk*` glob matches nothing gives exit 1 `setup-missing`, so the app hash can never pass over zero files;
     - a `npm:`-alias, `file:` or URL argument gives exit 1 `bad-version-arg` with no npm call.
     - a stub containment probe that can write into the fixture `$HOME` (or the fixture git common dir) gives exit 3 `containment-unavailable` and starts no harness;
     - a scratch root under the fixture `$HOME` gives exit 3 `scratch-inside-protected-path`;
     - a baseline lockfile integrity that differs from the fixture `MEASURED_BASELINE.integrity` gives exit 3 `baseline-integrity-mismatch` and no candidate install.
2. Create `apps/web-platform/scripts/remeasure-sdk-sandbox-network-cache.sh`. Use `set -uo pipefail`, and a header in the `sdk-bump-sandbox-gate.sh` style: purpose, issue and ADR refs, the exit table, the verdict-to-action table, and the "evidence only, never moves the pin" scope line. `--help` prints the header.
3. `git add` the new suite, then run it and `bash scripts/lint-orphan-test-suites.sh`. The lint walks `git ls-files`, so it cannot see an untracked suite.

**Phase 4 — Pointers.**
- `scripts/sdk-bump-sandbox-gate.sh`: one `echo` naming the command, once, after the loop that prints the `DETECTED bump` lines. Run `scripts/sdk-bump-sandbox-gate.test.sh`, and update its pinned output if a row pins it.
- ADR-278's 2026-11-18 addendum, "Re-measure trigger" paragraph: name the command, and add the verdict-to-action table.

**Phase 5 — Measure (CTO item 21).**

5a (this PR, after #12897 merges and the branch is rebased): run the script once against the newest version past the floor, 0.3.326 if the run starts at or after 2026-11-19T18:44:37Z, otherwise 0.3.325. The script's own floor check decides; there is no override. The addendum and #12906 comment label it "interim version, not 0.3.328" and say: "0.3.328 measurement pending the ADR-191 release-age floor, not before 2026-11-21T23:14Z, tracked in #<follow-up>". An interim RE-ASKS-AFTER-TEARDOWN or MIXED verdict is already a #12906 trigger; an interim LEAK takes the LEAK path. In the steps below read `0.3.328` as the interim version for 5a.

5b (follow-up issue, filed before merge with `Ref #12906`): the 0.3.328 run, not before 2026-11-21T23:14Z, with the exact command, the 0.3.328 AC8 and the record steps below.

1. Run `bash apps/web-platform/scripts/remeasure-sdk-sandbox-network-cache.sh <version> --out <scratchpad>/verdict-<version>.json`. Use Monitor with an until-loop, or a run_in_background launch with its notification. Never poll with sleep (`hr-monitor-not-run-in-background-for-polling`).
2. Branch on the `verdict=` word of the final `REMEASURE` line. The exit code only cross-checks it, because exit 0 covers three findings. Write the drafts with `--markdown <scratchpad>/records`, then paste the ADR-278 policy sentences into their placeholders:
   - **0 CACHES:** write the addendum. #12906 stays blocked, and the next run happens on the next SDK bump.
   - **0 RE-ASKS-AFTER-TEARDOWN** (the brief's "no longer caches" case; renamed by CTO item 14 so it cannot be over-read): write the addendum stating:
     - this run cannot tell three explanations apart: (i) the cache is gone; (ii) the SDK re-asks only because the connection to the dead forwarder failed, and would still reuse the allow while the forwarder is live; (iii) the cache became per-command or time-limited;
     - so the result is a trigger to build #12906's allow arm (not built here) and to run that issue's required live-forwarder deny-flip arm. It is not evidence that an allow can be revoked;
     - adopting 0.3.328 fires the results note's SDK-version and CLI-version re-measure triggers, which re-arms CLO gate B-2;
     - the adoption PR must re-run the full runtime suite, PRODUCTION arms included;
     - building the allow arm re-fires the CLO DPIA t4 re-screen before merge.
   - **0 MIXED** (CTO item A): write the addendum stating that F cached within one command while F2 re-asked across commands, which is most consistent with explanation (iii), a cache per command. Like RE-ASKS-AFTER-TEARDOWN, it is a trigger for #12906 and its deny-flip arm, not evidence that an allow can be revoked. The B-2, full-suite and DPIA t4 statements apply as in that branch.
   - **2 INCONCLUSIVE:** re-run once. A conclusive re-run is the finding, recorded next to the first run, which it never replaces. Otherwise record INCONCLUSIVE with its reason, and file an issue naming it (plan review: DHH 8).
   - **3 `UNVERIFIED`** (`no-userns`, `unsupported-arch`, `containment-unavailable`, `scratch-inside-protected-path` or `step0`): record `UNVERIFIED:sdk-0.3.328-sandbox-network-allow-cache` in the addendum, and file an issue with the step-0 fields and host versions.
   - **3 `REFUSED`** (`release-age-floor`, `signature-verification-failed` or `baseline-integrity-mismatch`): do not record a finding. A baseline integrity mismatch also files a security issue: published npm bytes never change. For release-age, wait. For signature, file a security issue and stop.
   - **4 LEAK:** write a separate short addendum and comment on #12906. A candidate LEAK files a bug issue against adopting that SDK. A `LEAK (baseline)` files a P1 issue against the production pin, and the addendum says the pinned SDK leaked.
   - **1 `ERROR`** (`setup-missing`, `harness-crash`, parse, `app-mutated`): fix the cause and re-run. Record nothing, except that `app-mutated` also files a bug issue against the script.
3. Every addendum, whatever the verdict, also carries:
   - the exact command;
   - the requested and exact versions, and the observed SDK, CLI, node, npm, kernel and bwrap versions of both runs;
   - a per-arm table (asked hosts, gateway lines, decoy hits) for baseline and candidate;
   - the verdict and the exit code;
   - one sentence on the limits: off-production (developer host, scripted model stub, pin unchanged), and it neither satisfies nor re-arms gate B-2 (wording per the CLO ruling).
4. Post the #12906 comment with `gh issue comment 12906 --body-file <file>`. It has the same content in short form, plus a link to the ADR section on the PR branch.

**Record wording (CLO rulings, 2026-11-19; use verbatim).**
- Limits and B-2, every verdict: "This measurement is off-production (developer host, scripted model stub, production pin unchanged at 0.3.321). It neither satisfies nor re-arms gate B-2 of the 2026-11-18 DPIA re-screen (PR #12900, open when this was written). B-2 is already unsatisfied, because the 0.3.321 pin fired the SDK-version trigger. Adopting any new Agent SDK or CLI version, 0.3.328 included, would fire the results note's SDK-version trigger, and the CLI-version trigger whenever the bundled CLI changes, and so would re-arm B-2 against the adopted versions." If PR #12900 has merged by the run date, drop the parenthetical "open when this was written" and cite the merged memo path.
- DPIA t4, RE-ASKS-AFTER-TEARDOWN only (addendum and #12906 comment): "Building the allow arm in #12906 re-fires the DPIA t4 re-screen (CLO ruling 2026-11-18). That re-screen must be recorded before the arm's PR merges, and B-2 must then pass on the versions adopted."

**Phase 6 — Verification.**
- vitest: `test/sandbox-network-cache-verdict.test.ts` and `test/sandbox-network-access-runtime.test.ts`.
- `bash apps/web-platform/scripts/remeasure-sdk-sandbox-network-cache.test.sh` and `bash apps/web-platform/scripts/sdk-bump-sandbox-gate.test.sh`.
- Record each Guard 1 and Guard 2 mutation's failing test name in the PR body (plan review: Kieran 9).
- `tsc --noEmit` for apps/web-platform.
- `git diff --quiet origin/main...HEAD -- apps/web-platform/package.json apps/web-platform/package-lock.json` exits 0.
- `python3 scripts/lint-guard-contract.py knowledge-base/project/plans/2026-11-19-chore-remeasure-sdk-sandbox-network-allow-cache-plan.md`.

## Files to Create

- `apps/web-platform/scripts/remeasure-sdk-sandbox-network-cache.sh`
- `apps/web-platform/scripts/remeasure-sdk-sandbox-network-cache.test.sh`
- `apps/web-platform/scripts/lib/sandbox-network-cache-verdict.ts`
- `apps/web-platform/test/sandbox-network-cache-verdict.test.ts`

## Files to Edit

- `apps/web-platform/test/helpers/netns-egress-harness.mts` (from #12897: the `NETNS_SDK_ENTRY` override, four observed STEP0 fields, and the per-arm `initClaudeCodeVersion`)
- `apps/web-platform/test/sandbox-network-access-runtime.test.ts` (from #12897: imports `MEASURED_BASELINE` and `DEAD_FORWARDER`; step-0 `sdkVersion` and `initClaudeCodeVersion` assertions; the `MEASURED_ON_SDK` failure message names the command)
- `apps/web-platform/scripts/sdk-bump-sandbox-gate.sh` (one `echo` after `DETECTED bump` names the command), and `apps/web-platform/scripts/sdk-bump-sandbox-gate.test.sh` only if a row pins that text
- `knowledge-base/engineering/architecture/decisions/ADR-278-opt-in-open-web-egress-via-dedicated-connect-gateway.md` (the 2026-11-18 addendum's re-measure trigger names the command; a new dated addendum with the 0.3.328 result)

Not edited: `apps/web-platform/package.json` and `package-lock.json` (asserted unchanged); the archived spike results note (CTO item 8).

## Open Code-Review Overlap

None. No open `code-review`-labeled issue names any planned file (`netns-egress-harness.mts`, `sandbox-network-access-runtime.test.ts`, `ADR-278`, the new script and module paths were each searched). Adjacent open follow-ups from #12897's review, not `code-review`-labeled:
- #12915 (harness ceilings, PRODUCTION decoy control, `buildAgentQueryOptions` parity): **Acknowledge.** Its items change the harness's arms and topology. This PR adds only an import override and observed fields. Folding them in would change the sensor between the baseline and the candidate reading.
- #12914 (PRODUCTION-phase flake): **Acknowledge.** The MEASUREMENT arms do not consult `isLive`. The F/F2 pre-teardown precondition turns the analogous failure into INCONCLUSIVE.

## Alternative Approaches Considered

| Alternative | Why rejected |
|---|---|
| Self-contained harness copy in this PR | Two sensors for one property, no agreement check; #12897's harness is still changing in review (CTO item 1) |
| `--import` resolve hook redirecting the bare specifier | Stacks on tsx's loader and redirects every SDK import, harder to audit (CTO item 2) |
| App's 0.3.321 JS layer with the 0.3.328 CLI (`pathToClaudeCodeExecutable`) | A combination nobody ships; says nothing about adopting 0.3.328 (CTO item 2) |
| Read pass/fail of the existing vitest suite | Red conflates stopped caching, a blind sensor and a leak (CTO item 3) |
| control, F, F2 only | A verdict without the routing evidence (B, D, E) #12906 needs (CTO item 4) |
| New allow-then-deny or PRODUCTION-tap arms | #12906's design work; adoption re-runs the PRODUCTION arms (CTO item 4) |
| Trust the committed 0.3.321 result as the baseline | Different day and host; only a same-host known answer separates SDK change from host drift (CTO item 9) |
| A CI lane on SDK-bump PRs | New supply-chain and flake surface in an evidence-only PR; the red suite and the ADR-079 ack gate already force the re-run (CTO item 7). Revisit after the script has run cleanly more than once |
| Run now, without the release-age floor or with an override | Overrides the ADR-191 floor while the CLI can read the operator's HOME; adoption cannot use a fresher version anyway (CTO item 10) |
| Bump the production pin to 0.3.328 here | Out of scope by the brief; adoption re-arms B-2 and needs the PRODUCTION arms |

Deferred: masking the real HOME from the CLI in the harness, tracked in #12969 (CTO item 10 dissent). Conditional issues: an UNVERIFIED, a persistent INCONCLUSIVE, a signature failure or a LEAK result each file an issue in Phase 5.

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing directly. No production code, pin or config changes. The indirect failure is a wrong verdict. A false RE-ASKS-AFTER-TEARDOWN could start #12906 on a false premise. That PR has its own runtime suite, PRODUCTION arms and CLO re-screen. A false CACHES keeps sandboxed web egress unavailable longer for owners who turned Agent web access on (today's state).
- **If this leaks, the user's data is exposed via:** no user data path. The run uses synthetic decoys, a local model stub and no workspace or credential. The operator's own host is exposed to a compromised candidate SDK binary during the run, which the script contains: `$HOME` and `$XDG_RUNTIME_DIR` are masked, the repo and git common dir are read-only, and there is no network. `/tmp` and other user-writable paths remain exposed. The release-age floor lowers the odds, and pinned integrity verifies the baseline bytes (CTO items D and E; #12969 tracks the shared harness).
- **Brand-survival threshold:** `none`
- `threshold: none, reason: evidence-only test tooling and records; no file under the sensitive-path regex changes, no production behavior or pin moves, and the verdict gates nothing automatically.`
- **Threshold decision (challengeable):** the one way this reaches a user is through #12906, which carries its own `single-user incident` gates. This PR's output is evidence for that PR, not a decision.

## Observability

The script is an operator- and agent-run measurement, not a production surface. Its signal is its exit code and verdict line.

```yaml
liveness_signal:
  what: the final REMEASURE line and exit code of apps/web-platform/scripts/remeasure-sdk-sandbox-network-cache.sh, recorded in the dated ADR-278 addendum and on #12906
  cadence: on demand, at every Agent SDK bump (pointed to by the MEASURED_ON_SDK failure, ADR-278's re-measure trigger and sdk-bump-sandbox-gate.sh)
  alert_target: the runtime suite's MEASURED_ON_SDK assertion in the required test-webplat lane goes red on any pin move
  configured_in: apps/web-platform/test/sandbox-network-access-runtime.test.ts (MEASURED_ON_SDK) and apps/web-platform/scripts/sdk-bump-sandbox-gate.sh
error_reporting:
  destination: the final `REMEASURE verdict= exit= reason= next=` line on stdout, progress on stderr; exit 1 error, 2 inconclusive, 3 unverified or refused, 4 leak; the verdict JSON at --out
  fail_loud: exit 4 LEAK and exit 3 are never 0; app-mutated is exit 1 regardless of verdict
failure_modes:
  - mode: blind sensor (positive control missed a decoy, no SandboxNetworkAccess call, F/F2 precondition false)
    detection: classifier preconditions over the in-namespace NETNS_ARM records
    alert_route: exit 2 INCONCLUSIVE with the failing precondition name
  - mode: the wrong SDK or CLI was loaded
    detection: observed sdkEntry, sdkVersion, cliPath and cliVersion in NETNS_STEP0, plus each arm's initClaudeCodeVersion from the SDK init message
    alert_route: exit 2 INCONCLUSIVE (candidate:versions)
  - mode: host drift (kernel, bwrap, userns sysctl)
    detection: same-host baseline on a scratch install of MEASURED_BASELINE.version must read CACHES; step0.ok false maps to exit 3
    alert_route: exit 2 INCONCLUSIVE (baseline) or exit 3 UNVERIFIED with the UNVERIFIED token printed
  - mode: a connection escaped the forwarder
    detection: decoy hit or gateway line without the session credential in any non-control arm
    alert_route: exit 4 LEAK; Phase 5 files a bug issue
logs:
  where: script stdout and stderr; the verdict JSON file at --out; the dated ADR-278 addendum
  retention: the ADR addendum and the #12906 comment are permanent; local output is per run
discoverability_test:
  command: grep -o -m1 "bash apps/web-platform/scripts/remeasure-sdk-sandbox-network-cache.sh" apps/web-platform/test/sandbox-network-access-runtime.test.ts
  expected_output: "bash apps/web-platform/scripts/remeasure-sdk-sandbox-network-cache.sh"
```

## Guard Contract

### Guard 1 — the verdict classifier cannot report a finding from a blind or wrong sensor

**Property.** The classifier reports CACHES, RE-ASKS-AFTER-TEARDOWN or MIXED with exit 0 only when both runs passed every precondition, the baseline read the pinned answer, the observed SDK and CLI (including each arm's init message) were the requested ones, the post-teardown requests ran, and no arm leaked. Any leak in either run reports LEAK with exit 4, whatever else holds.

**Assembly.** The single chokepoint is the classifier's combine step in `apps/web-platform/scripts/lib/sandbox-network-cache-verdict.ts`, which every exit-0 path flows through. Its inputs are the two parsed harness outputs, each from `test/helpers/netns-egress-harness.mts`: one `NETNS_STEP0` and six `NETNS_ARM` records. The script passes the classifier's exit code through unchanged, and holds no verdict logic of its own. The precedence table in Verdict rules is the order the combine step evaluates. The precondition set is enumerated once, as a list the combine step iterates, so adding a precondition means adding a list member.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Drop the positive-control check (control decoys) from the precondition list | RED: the "control missed decoy X" fixtures expect INCONCLUSIVE and get a verdict |
| 2 | Own dispatch: the parser returns zero arm records for a stdout with no `NETNS_ARM` lines, and the combine step treats the empty set as passing | RED: the "missing arm record" fixture and an empty-stdout fixture expect exit 2/1, never 0 |
| 3 | Second member: the control check stops after the first decoy that was hit (`.some` instead of every decoy) | RED: the iterated fixture with only `198.51.100.1:443` hit expects INCONCLUSIVE for each of the other four |
| 4 | Order: evaluate LEAK after the preconditions, so a run with a failed precondition and a decoy hit reports INCONCLUSIVE | RED: the LEAK-precedence fixture expects exit 4 |
| 5 | Skip the baseline: classify the candidate alone | RED: the "baseline reads RE-ASKS-AFTER-TEARDOWN" fixture expects INCONCLUSIVE (baseline) |
| 6 | Version check compares the requested version against itself instead of the observed `sdkVersion` | RED: the candidate-observed-0.3.321 fixture expects INCONCLUSIVE |
| 7 | F2 rule accepts `["example.test"]` (allowed host never asked at all) as RE-ASKS-AFTER-TEARDOWN | RED: that fixture expects INCONCLUSIVE |
| 8 | Drop the `post-teardown-ran` precondition (`f-3`/`f2-2` vs `DEAD_FORWARDER`) | RED: the "f-3 not dead-forwarder" fixture expects INCONCLUSIVE, not CACHES |

**Harness rows:**
- Suite edit that must go RED: the fixture factory returns the same object for baseline and candidate, so a mutation of one leaks into the other. The baseline-RE-ASKS-AFTER-TEARDOWN fixture then also changes the candidate, and its expected `baseline` reason fails.
- Must-PASS input that is not the canonical fixture: a candidate whose F re-asks the decoy IP twice (three asks in all), and whose arm B lists the hosts in a different order than the canonical fixture. It must still read RE-ASKS-AFTER-TEARDOWN with exit 0.

**Anchor.** The expected baseline answer is a stored value, `MEASURED_BASELINE`. The runtime suite imports the same object for `MEASURED_ON_SDK` and its F/F2 host lists, and it runs against the live pinned SDK in the required lane. That suite is the outside anchor: a pin move turns it red until `MEASURED_BASELINE` is re-measured (CTO item B).

### Guard 2 — the measurement never moves the app's SDK

**Property.** After any run, whatever its exit, `apps/web-platform/package.json`, `apps/web-platform/package-lock.json` and every file under the installed `apps/web-platform/node_modules/@anthropic-ai/claude-agent-sdk*` are byte-identical to their state before the run, and the scratch directory no longer exists.

**Assembly.** The writers that could touch the app tree are the npm calls, the harness runs and the candidate CLI they start. The installs run with cwd and `--prefix` set to the scratch prefixes, and the CLI runs with `$HOME` masked and the worktree and git common dir read-only (CTO item D), so it cannot write the app tree at all; the hash is the after-the-fact check on top. The pre-run hash is taken before the first npm call. The post-run comparison and the scratch removal both run in the EXIT trap. The trap is armed, with `scratch=""`, before the hash and before any write, so every exit after step 2 passes through it, and `app-mutated` overrides any other exit. Steps 1 and 2 exit before any write. Exit sites by position: tool and userns refusals, and the release-age refusal, happen before any write, with no scratch dir yet. The install, signature, version, harness and classifier exits all happen after the scratch dir exists and before the trap returns.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1a | Drop `--prefix` from the install | RED: the stub `npm` refuses the argv (exit 64, refusal log non-empty) |
| 1b | Run the install with cwd the app dir instead of the scratch prefix | RED: the stub `npm` writes into its cwd, and the row expects exit 1 `app-mutated` |
| 2 | Own dispatch: the post-run hash compares the pre-run value with itself | RED: the "stub touches package-lock" row expects exit 1 |
| 3 | Second member: hash only `package-lock.json`, not the installed SDK tree | RED: a stub that rewrites only a file under the fixture's installed `claude-agent-sdk-linux-x64` expects exit 1 |
| 4 | Reorder: arm the trap after `mktemp -d`, with an exit between them | RED: the row whose harness stub exits non-zero asserts the scratch dir is gone |
| 5 | The release-age check runs after the install | RED: the under-floor row asserts the stub npm saw no `install` argv |
| 6 | Drop the read-only remount of the git common dir (keep the worktree remount) | RED: the containment-probe row whose fixture common dir is writable expects exit 3 `containment-unavailable` |

**Harness rows:**
- Suite edit that must go RED: a row runs the script in place, from the real `apps/web-platform`, instead of the copy in the fixture tree. A guard row asserts that every script path the suite executes is under its own `mktemp -d`.
- Must-PASS input: a run whose classifier exits 2, with the app files untouched. It must exit 2, not 1.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "re-measure, on @anthropic-ai/claude-agent-sdk 0.3.328 ... whether the SDK still caches a per-host SandboxNetworkAccess allow for the whole session, so that a later deny for the same host is never asked" [brief] | Phase 5 run; arms F and F2; verdict rules | mapped |
| 2 | "Use the same network-namespace harness Phase 1a used ... (the child harness under `unshare -rnm`, with routable decoys and a positive control ...)" [brief] | Phase 2 harness override; control arm precondition | mapped |
| 3 | "do NOT bump the production SDK pin in this PR, and run the measurement against 0.3.328 installed in an isolated harness directory" [brief] | Script steps 3, 4, 7, 8 and 10; Guard 2 | mapped |
| 4 | "Record the result in a dated addendum to ADR-278 and as a comment on #12906, with the exact command, versions and per-case outcome" [brief] | Phase 5 steps 3 and 4 | mapped |
| 5 | "If 0.3.328 no longer caches, state that this is the trigger to build #12906's real allow arm (do not build it here) and note that any SDK bump re-arms CLO gate B-2" [brief] | Phase 5 step 2, RE-ASKS-AFTER-TEARDOWN branch | mapped |
| 6 | "If the harness cannot run in this environment (no user namespaces), record `UNVERIFIED:sdk-0.3.328-sandbox-network-allow-cache` and file an issue" [brief] | Script step 2 (`no-userns`), the classifier's rank-3 `step0` row; Phase 5 step 2, `UNVERIFIED` branch | mapped |
| 7 | "Commit the harness invocation as a reusable script so the next SDK bump can re-run it in one command" [brief] | Files to Create (script, classifier, tests); Phase 4 pointers; `MEASURED_BASELINE`; `--markdown` drafts; the verdict-to-action table in the script header and ADR | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `remeasure-sdk-sandbox-network-cache.sh` | asks 3, 6, 7 | asked |
| `sandbox-network-cache-verdict.ts` | — | inferred — justification: the "per-case outcome" of ask 4 needs a classifier that separates stopped caching from a blind sensor and a leak (CTO item 3) |
| `sandbox-network-cache-verdict.test.ts` | — | inferred — justification: `cq-write-failing-tests-before`; the classifier decides whether #12906 starts, so its rules must be pinned |
| `remeasure-sdk-sandbox-network-cache.test.sh` | — | inferred — justification: Guard 2 (pin never moves, ask 3) and the release-age refusal must be driven red offline; the measurement itself is too slow and host-dependent to be the test |
| `netns-egress-harness.mts` override and STEP0 fields | asks 2, 3 | asked |
| `sandbox-network-access-runtime.test.ts` edits | ask 7 ("the next SDK bump can re-run it") | asked |
| `sdk-bump-sandbox-gate.sh` message | ask 7 | asked |
| ADR-278 re-measure-trigger edit and new addendum | asks 4, 5, 7 | asked |
| Same-host baseline run, from a scratch install of `MEASURED_BASELINE.version` | — | inferred — justification: without a known answer on the same host, host drift reads as an SDK change (CTO item 9); the scratch install keeps it valid on a bump branch (CTO item B) |
| `--markdown` drafts, progress lines, `--keep-scratch` | ask 7 ("re-run it in one command") | asked — justification: the operator at the next bump turns the run into records without this plan (plan review: CTO devex) |
| Release-age floor and `npm audit signatures` | — | inferred — justification: ADR-191's supply-chain floor and the CLI's host-filesystem exposure (CTO item 10) |
| LEAK verdict and its issue | — | inferred — justification: a decoy hit is a finding against adoption, or against the pin if it is in the baseline, and must never read as green or as a re-run (CTO items 3, 5, 8) |

### Split Assessment

- Subsystems touched: 2 — `apps/web-platform`, `knowledge-base`
- Planned files: 9 | Estimated changed lines: about 780 (classifier about 260 with the markdown drafts, its suite about 240, script about 150, `.test.sh` about 110, harness about 35, other edits about 25; the ADR addendum about 40)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

Build stage:

- **AC1** `gh pr view 12897 --json mergedAt` is non-null, and this branch's merge-base with `origin/main` contains `apps/web-platform/test/helpers/netns-egress-harness.mts`.
- **AC2** `apps/web-platform/test/sandbox-network-cache-verdict.test.ts` passes. Every Guard 1 mutation-matrix row names a fixture that fails under it. The PR body records each mutation's failing test name.
- **AC3** `bash apps/web-platform/scripts/remeasure-sdk-sandbox-network-cache.test.sh` passes. Every Guard 2 row names a case that fails under it, and the PR body records it.
- **AC4** `apps/web-platform/test/sandbox-network-access-runtime.test.ts` passes on the 0.3.321 pin in the required `test-webplat` lane, including the new step-0 `sdkVersion` and `initClaudeCodeVersion` assertions. It now imports `MEASURED_BASELINE`.
- **AC5** The pointers are anchored, never bare tokens (`cq-assert-anchor-not-bare-token`):
  - `grep -c 'bash apps/web-platform/scripts/remeasure-sdk-sandbox-network-cache.sh' apps/web-platform/test/sandbox-network-access-runtime.test.ts` is at least 1;
  - `grep -c 'bash apps/web-platform/scripts/remeasure-sdk-sandbox-network-cache.sh' apps/web-platform/scripts/sdk-bump-sandbox-gate.sh` is at least 1, and a `sdk-bump-sandbox-gate.test.sh` row bumping one SDK package asserts that line is printed exactly once;
  - for ADR-278, `awk '/^\*\*Re-measure trigger\.\*\*/{f=1} f&&/^$/{exit} f' <ADR> | grep -c remeasure-sdk-sandbox-network-cache.sh` is at least 1.
- **AC6** `git diff --quiet origin/main...HEAD -- apps/web-platform/package.json apps/web-platform/package-lock.json` exits 0.
- **AC7** With the new `.test.sh` tracked (`git ls-files` lists it), `bash scripts/lint-orphan-test-suites.sh` passes. `tsc --noEmit` also passes in apps/web-platform. The harness `.mts` is not in the tsconfig include, so AC4 is its gate.

Measure stage:

- **AC8** (CTO item 21) The script ran for real against the interim version (0.3.326 or 0.3.325, past the floor). The addendum quotes the exact command, the exit code and the final `REMEASURE` line, labelled "interim version, not 0.3.328". The follow-up issue for the 0.3.328 run exists, carries `Ref #12906`, the exact command and the not-before time 2026-11-21T23:14Z, and holds the 0.3.328 form of this criterion.
- **AC8b** (CTO item 21) The offline `.test.sh` has a row with a two-worktree fixture whose sibling worktree stays writable; it exits 3 `containment-unavailable`.
- **AC9** The ADR-278 addendum `## Addendum — <run date> (#12906): ...` records:
  - the requested and exact versions;
  - the observed SDK, CLI, node, npm, kernel and bwrap versions of both runs;
  - a per-arm table for baseline and candidate;
  - the off-production limits sentence and the B-2 sentence (wording per the CLO ruling).
- **AC10** If the verdict is RE-ASKS-AFTER-TEARDOWN or MIXED, the addendum and the #12906 comment name explanations (i) to (iii) and say the run cannot separate them. Both also state:
  - it is the trigger to build #12906's allow arm, which is not built here;
  - allow-then-deny is a required arm there;
  - adopting any SDK bump (0.3.328 included) re-arms CLO gate B-2;
  - the adoption PR re-runs the full runtime suite;
  - building the allow arm re-fires the DPIA t4 re-screen.

  If the verdict is CACHES, both state that #12906 stays blocked until the next bump's run.
- **AC11** A comment on #12906 carries the command, versions, per-arm outcome and verdict. Check it with `gh issue view 12906 --json comments --jq '[.comments[].body|select(contains("remeasure-sdk-sandbox-network-cache.sh 0.3.328") and contains("REMEASURE verdict="))]|length'`, which returns at least 1.
- **AC12** For an `UNVERIFIED` exit 3, the addendum carries `UNVERIFIED:sdk-0.3.328-sandbox-network-allow-cache`, and an issue is filed. For exit 4, a separate bug issue is filed, or a P1 against the pin for `LEAK (baseline)`. For a persistent exit 2, an issue names the failing precondition.
- **AC13** The production pin is still `"@anthropic-ai/claude-agent-sdk": "0.3.321"` in `apps/web-platform/package.json`, and `MEASURED_BASELINE.version` is still `"0.3.321"`.

## Domain Review

**Domains relevant:** Engineering, Legal

### Engineering

**Status:** reviewed
**Assessment:** The CTO ruled twelve design items plus three plan-review forks, A to C (decision-challenges.md). In short:
- wait for #12897 and rebase;
- one `NETNS_SDK_ENTRY` override, with observed versions;
- a standalone classifier with a distinct LEAK verdict;
- the full MEASUREMENT arm set;
- exit codes 0/1/2/3/4;
- install hygiene, with the release-age floor enforced explicitly;
- no CI lane;
- the addendum wording;
- a same-host baseline, installed into scratch from `MEASURED_BASELINE` (item B);
- MIXED is conclusive in its coherent direction (item A);
- bash wrapper plus TS classifier, not one TS orchestrator (item C).

### Legal

**Status:** reviewed
**Assessment:** The CLO ruled three items (decision-challenges.md):
- the B-2 sentence is approved with three changes. B-2 exists only once PR #12900 merges, it is already unsatisfied on the 0.3.321 pin, and the CLI trigger fires only when the bundled CLI changes. The verbatim text is under Phase 5's "Record wording".
- this PR needs no legal artifact and no DPIA action, because it adds no processing and touches no personal data or production system.
- a RE-ASKS-AFTER-TEARDOWN result must restate the future-conditioned DPIA t4 re-screen duty for #12906.

### Product/UX Gate

Not applicable. No UI-surface file is in Files to Create or Files to Edit, and there is no user-facing change.

## Test Scenarios

- Classifier: the fixtures listed in Phase 1, one per verdict word and per precondition, plus the Guard 1 harness rows.
- Script wrapper: the rows listed in Phase 3, plus the Guard 2 harness rows.
- Runtime suite on the pin: green, including step-0 `sdkVersion === "0.3.321"`.
- The real measurement (Phase 5) is the end-to-end scenario. It runs once in this PR, against 0.3.328.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6.
- `MEASURED_BASELINE` is the single stored answer. It moves only when a run reads CACHES on the new version, with an ADR-278 addendum in the same PR (CTO item B). A pin move to a non-caching SDK needs a new baseline design, not an edit to `reading`.
- `npm view <pkg> time --json` returns the whole time map, including `created` and `modified`. Select `time["<exact>"]` (verified 2026-11-19: 0.3.321 maps to 2026-11-09T19:03:36.409Z and 0.3.328 to 2026-11-18T23:13:27.778Z).
- Two scratch installs need about 760 MB. `/tmp` is RAM-backed on some hosts, so the script honors `TMPDIR` and checks free space.
- npm does not read `apps/web-platform/.npmrc` from a scratch cwd. `--min-release-age=3` on the command line is the floor. Removing it turns the floor off silently (CTO item 10 correction).
- The 2026-11-18 addendum's "re-measure trigger" text is edited, not replaced. The new addendum must not restate the 0.3.321 numbers as if they were re-measured.
- Do not print the stub's API key sentinel or the unmasked proxy variables into the verdict JSON, the markdown drafts, the crash stderr tail or the #12906 comment. The classifier copies only listed fields, and refuses output containing the sentinel.

## References

- #12906, #11637 (CTO ruling 2026-11-19), #12585, PR #12897, PR #12900 (DPIA re-screen memo, gate B-2), #12902, #12903, #12904, #12914, #12915, #12969
- `knowledge-base/project/plans/archive/20261118-150540-2026-11-18-fix-sandbox-network-access-canusetool-arm-plan.md` (on the #12897 branch)
- ADR-278, ADR-079, ADR-191
