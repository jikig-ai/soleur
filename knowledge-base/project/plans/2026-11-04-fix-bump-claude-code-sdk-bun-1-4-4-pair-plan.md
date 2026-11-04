---
title: "security: bump claude-code/agent-sdk to a Bun>=1.4.4 pair and re-prove sandbox builder properties (CVE-2026-111497)"
type: fix
date: 2026-11-04
slug: bump-claude-code-sdk-bun-1-4-4-pair
branch: feat-one-shot-12026-bun-claude-code-bump
issue: 12026
priority: p1
domain: engineering
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# security: bump claude-code/agent-sdk to a Bun>=1.4.4 pair and re-prove sandbox builder properties (CVE-2026-111497)

PR body uses `Ref #12026`, never `Closes`: the issue closes only after the post-merge evidence in Phase 4 shows Bun >= 1.4.4 in the shipped binaries.

## Enhancement Summary

**Deepened on:** 2026-11-04 (UTC)
**Method (bounded, stated plainly):** the plan was already reviewed by a five-seat eng panel (DHH, Kieran, code-simplicity, architecture-strategist, spec-flow), the CTO (F1-F4 rulings) and the CPO (sign-off approved). Deepen therefore ran the mechanical halt gates and live verification of every cited fact rather than a fresh 40-agent fan-out, which would have re-read the same four files.
**Gates run:** 4.6 User-Brand Impact (present, `single-user incident`) pass; 4.7 Observability (new block: `jq` is on the probe allowlist, no `ssh `, command is sub-second, `expected_output` is the literal `2.1.311`) pass; 4.8 PAT-shaped variables (no hit) pass; 4.9 UI wireframe (no UI surface) skipped; 4.10 Encryption Posture (no new store or connection) skipped; 4.11 Guard Contract (`scripts/lint-guard-contract.py` green, 2 entries; Assembly names chokepoints, not member lists) pass; 4.12 Scope Check (exactly one unfenced section, every row mapped or justified) pass; 4.13 Task Design (no new autonomous-task surface) skipped.
**Verified live:** `semver:patch` label exists; every cited issue/PR state matches (#12026 open, #12009 merged, #10453 closed as implemented, #8643/#9724/#10115/#10455/#10549 open); the two rule ids cited resolve (`cq-cite-content-anchor-not-line-number` active, `wg-architecture-decision-is-a-plan-deliverable` migrated); ADR-075/079/116/272/278 files exist; `ci-deploy.sh` prints "report-only canary; deploy NOT rolled back"; `web-platform-release.yml` has `workflow_dispatch`; `audit-models.sh` has `sdk_carveout_re()` feeding `EXCLUDE_RE`; `model-launch-review/SKILL.md` documents `SDK_PATH_CARVEOUT`; the Dockerfile stage is named `cli-tools`; `sandbox-startup-classifier.test.ts` pins `minStrings: 17` and the `["observe sendmsg failed"]` equality; `origin/main` moved by five commits (#12078, #12029, #12002, #11949, #12063) with no overlap with any planned file and still carries the 0.3.284 / 2.1.293 pins.

### Key Improvements
1. Phase 1 proof is now time-boxed (ruling due 2026-11-09), has an owner for a red result and a stated interim exposure path.
2. A rollback path (revert PR plus `workflow_dispatch` redeploy) replaces the overstated "deploy gate": canary and smoke are report-only.
3. The proof is repeated on the committed tree (2.13) and the global-install tree is probed pre-merge via `docker build --target cli-tools`.
4. The F5 swap, the ADR-075/278 version lines and the classifier test anchors are complete, with deletions enumerated so `grep -rn SDK_PATH_CARVEOUT plugins/` is a checkable AC.

### New Considerations Discovered
- The issue's own acceptance probe prints the bare fragment `Bun v` and can never report a version; the corrected regex is the contract everywhere.
- SDK and CLI collapse to one byte-identical binary at this pair, so one measurement serves both packages, but the Guard still scans both so they can diverge again.
- Three ~294 MB copies ship in the image; no size gate exists, so the delta is reported.

## Overview

Move the pinned `@anthropic-ai/claude-code` (2.1.293) and `@anthropic-ai/claude-agent-sdk` (0.3.284) to the exact pair **2.1.311 / 0.3.311**, whose native `claude` binaries embed Bun 1.4.4, so the Brotli-decoder flaw (CVE-2026-111497) no longer sits in the process that decodes `Content-Encoding: br` responses. The Node-side half shipped in #12009 and is not redone here.

The bump replaces the vendored bwrap argv builder the per-user agent sandbox depends on. Credential-deny, masked `/proc` and AF_UNIX isolation are therefore re-proved through the real SDK path in a scratch install **before any committed pin moves**; the pins, lockfile, Dockerfile, fixture and test shapes then land in one atomic commit.

Decisions of record (CTO-ruled, 2026-11-04) live in `knowledge-base/project/specs/feat-one-shot-12026-bun-claude-code-bump/decision-challenges.md`: F1 exact pin 2.1.311/0.3.311; F2 standing embedded-Bun floor guard; F3 scratch-proof sequencing with three amendments; F4 content-anchored replacement for the settings-mapping needle; F5 forced model-launch-review carve-out swap; F6 PR 10926 note.

## Research Reconciliation — Spec vs. Codebase

| Spec / issue claim | Reality (measured 2026-11-04) | Plan response |
|---|---|---|
| Acceptance probe: `strings <bin> \| grep -m1 '^Bun v'` reports the version | The first hit is the bare string-pool fragment `Bun v` in BOTH the old and new binaries (two such lines); it can never carry a version. The working probe is `grep -m1 -E '^Bun v[0-9]+\.[0-9]+\.[0-9]+'` (old: `Bun v1.4.3 (Linux x64)`, new: `Bun v1.4.4 (Linux x64)`). | Use the corrected probe everywhere (guard, PR body, issue comment). The guard has a positive control that a bare `Bun v` does not count. |
| "9 tests in sandbox-vendored-argv-tail.test.ts fail" | Not listed in the issue. The real-binary describe has per-package rows (tail, census, helper selection, bridge, fixture) plus the lock row; the count is consistent but unrun here. Reproduced as the RED baseline in Phase 1. | Phase 1 runs the file in the scratch install and records the failing row names. |
| "`--proc /proc` second site, `--unshare-pid` 1 to 2" (SDK) | True of the SDK binary only: the SDK binary becomes byte-identical to the claude-code binary (sha256 `86dc1fcc...`, 293.8 MB, both embed `Bun v1.4.4 (0ae49f8b6)`). The claude-code pins already carry 2/1/1/2/2; the SDK pins converge on them. | SDK `PINS` rows are rewritten to the claude-code shape; one measurement serves both packages. |
| "allowAllUnixSockets mapping gone" | The literal `sandbox?.network?.allowAllUnixSockets` is gone (SDK count 2 to 0) but the setting is still read: `uV(e)` returns `allowAllUnixSockets: e?.allowAllUnixSockets` unless a managed-policy mode (`La()`, a new `Za` key list including `network.allowAllUnixSockets` with `qa=["required","egress"]`) drops it. The skip line `Skipping seccomp filter - allowAllUnixSockets is enabled` survives (count 2). | Not a removal: the mapping is reshaped and a new drop-in-managed-mode path exists. The wrapped-command arm is the proof (F4); the static needle is a tripwire only. Phase 1 verifies our config never lands in a dropping mode. |
| "TCP-LISTEN:3128 bridge anchor gone" | The in-sandbox wrapper now builds `TCP6-LISTEN:<port>,ipv6only=0,fork,reuseaddr,backlog=4096 UNIX-CONNECT:<sock> \|\| exec socat TCP4-LISTEN:<port>,...`, started from `C(3128,e)` / `C(1080,n)`, with `_srt_http=$!`, `_srt_socks=$!`, the same EXIT trap, and a new `/proc/net/sockstat` watchdog loop. Host-side `UNIX-LISTEN ... TCP:localhost:` bridge is unchanged. | New content anchors (`TCP6-LISTEN:`, `TCP4-LISTEN:`, `_srt_http=$!`, trap line); BRIDGE_ORDER semantics re-proved by the AF_UNIX-deny variant block. |
| Tail changed | Tail gains `--unsetenv <var>` (opaque arg) and `--disable-userns` after `--bind /proc /proc`; `--disable-userns` is a security property (bwrap blocks nested user namespaces). | `EXPECTED_TAIL_CALLS` gains both calls; fixture regenerated. |
| Not in the issue: classifier census | `apply-seccomp:` helper string pool grows 17 to 21 (new: `prctl(PR_SET_NO_NEW_PRIVS, stub)`, `prctl(PR_SET_SECCOMP, stub)`, `prctl(PR_SET_SECCOMP, namespaces)`, `could not set user.max_user_namespaces (%s); the seccomp filter alone ...`). `sandbox-startup-classifier.test.ts` Guard 2 reds (`HELPER_STEP_NEW`, `minStrings: 17`). | In scope: decide pre/post-command per step with measured evidence; update `server/sandbox-startup-classifier.ts` and `HELPER_NON_STEP_LINES`. |
| Not in the issue: model-launch-review | `plugins/soleur/test/model-launch-review.test.ts` self-expires at SDK >= 0.3.293 and prescribes the swap. | F5: forced consequence, in scope (Haiku 4.5 to 5.5 in four files, delete `SDK_PATH_CARVEOUT`). |
| Not in the issue: blocking gate | `scripts/sdk-bump-sandbox-gate.sh` (CI `lockfile-sync`) blocks any lock bump of either package until a commit carries `sdk-bump-verified:` or the capture arm verifies; `sandbox-canary-capture-gate` is live (`SANDBOX_CANARY_GATE_ENABLED: "1"`). | The trailer is written only after Phase 1 is green and states what was and was not validated. Never used to paper over a stale fixture. |
| Not in the issue: paid probe on merge | `scheduled-real-sdk-ask-probe.yml` runs a paid probe on push to main when either SDK version moved. | Expected, noted in Phase 4. |
| Step 0 "confirm the CI scope statement" | No `WebFetch`/`WebSearch` in `.github/workflows` (zero hits). `fix-constraints-stage-a.yml` sets explicit `--allowedTools Bash,Read,Write,Edit,Glob,Grep`. Three other `claude-code-action` invocations (`claude-code-review.yml`, `scheduled-machinery-drain.yml`, `test-pretooluse-hooks.yml`) set no `allowedTools`, so they follow the action defaults, which were not verified. `scheduled-marketplace-drift.yml` pins `CLI_VERSION: "2.1.228"` (exact, not coupled to this bump). | Recorded in the PR body: no web-tool allow-list found in CI; action defaults unverified; CI remains out of scope. |

## Research Insights

### Premise Validation (Phase 0.6)

- Issue #12026 is open, P1, due 2026-11-11, no closing PR. Draft PR 12073 (this branch) names it; no other open PR names it. The collision pre-check also reported two `test-all.sh` processes owned by another worktree (`feat-one-shot-10479-cf-readonly-wrapper`); unrelated to these files.
- #12009 merged (d1303cb464): `.bun-version` is 1.4.4, `apps/web-platform/.nvmrc` 22.23.4, npm-publish setup-bun reads `bun-version-file`. Verified on `origin/main`.
- All cited files exist on `origin/main`: Dockerfile line `RUN npm install -g @anthropic-ai/claude-code@2.1.293`, package.json pins, the four suites, the fixture, the pin-table tests.
- Mechanism vs ADR corpus: ADR-079 (faithful canary, SDK-bump guard, amendments through 2026-10-23) and ADR-075 addendum 2026-10-16 (`allowAllUnixSockets` posture, CTO-ruled) are the governing records; neither rejects this plan's mechanism (a pinned bump plus re-proof). ADR-079 requires re-capture on a lockfile bump; its addendum list is the home for the 0.3.311 re-proof record.
- Open PR 10926 (`fix/npm-publish-sigpipe`): state OPEN, `mergeStateStatus: DIRTY`, auto-merge armed 2026-10-23, `isInMergeQueue: false`. Its diff creates `.github/workflows/npm-publish.yml` as a NEW file whose `Setup Bun` step has no `bun-version-file`; `origin/main` has since added that file with `bun-version-file: ".bun-version"`, the OIDC-diagnose step, and the SIGPIPE-safe `sed -n '1p'` form. A rebase resolved in the PR's favour would re-float the npm-publish Bun pin that #12009 pinned. It does not touch any file in this plan.
- Baseline (step 0), read-only prd query 2026-11-04T08:59:56Z, `PGOPTIONS="-c default_transaction_read_only=on"` via `doppler run -p soleur -c prd`: **1 of 22 workspaces have `web_egress = true`**. Re-evaluation trigger from the issue: pull forward if the count rises above 1.
- Timing: UTC 08:5x vs local CET 09:5x (UTC+1) at planning time; all dates here are UTC.

### Measured builder drift (helper `test/helpers/vendored-bwrap-tail.ts` run against the real binaries)

| Probe | 2.1.293 (claude-code) | 0.3.284 (SDK) | 2.1.311 = 0.3.311 (one byte-identical binary) |
|---|---|---|---|
| embedded Bun | 1.4.3 (eecfd55de) | 1.4.3 | 1.4.4 (0ae49f8b6) |
| tail calls after `--dev /dev` | `--unshare-pid`, `--unshare-user`+caps, `--proc /proc`, `--bind /proc /proc` | same | same plus `--unsetenv <var>`, `--disable-userns` |
| procSites / hookProcSites / bindProcSites / unsharePid / hookAnchors | 2/1/1/2/2 | 1/0/1/1/0 | 2/1/1/2/2 |
| rootBind, cap-drop, cap-add | 1/1/1 | 1/1/1 | 1/1/1 |
| HELPER_SELECTION skip/apply/missing/mapping | 2/2/2/0 | 2/2/2/2 | 2/2/2/0 (mapping reshaped, see Reconciliation) |
| bridge wrapper anchor hits / `--unshare-net` hits | 1/1 | 1/1 | **0**/1 (re-anchored on `TCP6-LISTEN:`) |
| `apply-seccomp:` strings | 17 | 17 | 21 |

Release facts: dist-tags `stable` 2.1.311, `latest` 2.1.318 / 0.3.318. 2.1.311 and 0.3.311 were published 2026-10-26; 2.1.317/0.3.317 (11-02/11-03) and 2.1.318 (11-03 21:55 UTC) fail the repo's `min-release-age=3`. SDK 0.3.311 declares `claudeCodeVersion: 2.1.311` (0.3.284 declared 2.1.284, a different binary from claude-code 2.1.293); the skew disappears. The platform binary grows from ~243 MB to 293.8 MB: image-size consequence noted in Risks.

### Institutional learnings applied

- Post-mortem 2026-07-01 (concierge bwrap seccomp, SDK 0.2.85 to 0.3.197): a bump split `unshare` and the canary stayed green while every tenant's Bash failed; re-validate against the real invocation, not a synthetic probe.
- Learning 2026-10-18 (allowAllUnixSockets removes the per-command AF_UNIX block; canary replays only the setup argv and stays green during an outage): ask what the skipped wrapper was bounding; the wrapped-command arm is the instrument, the fixture is not.
- Learning 2026-11-03 (base-image CVE bump is a pin census): this issue is its recorded follow-up; run the sandbox suites before committing to a bump.
- Learning 2026-09-29 (detached precommit watchdog and sdk-bump attestation): the `sdk-bump-verified:` trailer is an attestation; write what was not validated; long batteries need `SOLEUR_TEST_ALL_ALLOW_ORPHAN=1 setsid nohup`.
- Learning 2026-10-09 (model launch): `claude-cli-pin-knows-models.test.ts` scans a ~200 MB binary and needs an explicit timeout; a bundle that does not know an id silently halves `max_tokens`.
- Learning 2026-10-29: a push to a queued PR branch is rejected (`GH006`); dequeue deliberately first. This PR is a draft, not queued.
- Learning 2026-11-03 (accept rows): a malformed `scripts/ci-pr-affected-audit.accept.tsv` reason empties the whole exemption map; validate with `audit --accept <file>`.

### Property List (Phase 0.6b)

1. P1: the installed `claude`/`sdk` linux-x64 binaries embed Bun >= 1.4.4 (the CVE fix).
2. P2: a tenant's sandboxed Bash cannot read the Anthropic credentials (credential-deny).
3. P3: a tenant's sandbox keeps a masked `/proc` (no host/sibling pid visibility) — the tail still ends in the mask.
4. P4: a tenant's sandboxed Bash cannot reach a sibling session's AF_UNIX proxy sockets or persisted CLI content, and hosted Bash still starts (no `apply-seccomp: unshare(CLONE_NEWUSER)` EPERM outage).
5. P5: the committed canary fixture equals the real builder's tail for the new SDK; the pin tables, Dockerfile, package.json and lockfile agree on one pair.
6. P6: no pin moves before P2-P4 are proved against the new binary through the real SDK path.

### Cut List (Phase 0.6b)

| Mechanism proposed in the ask | Property | Verdict |
|---|---|---|
| Bump CI `scheduled-marketplace-drift.yml` `CLI_VERSION` 2.1.228 | none in P1-P6 (issue: CI out of scope unless step 0 finds web tools; none found) | Cut. Recorded in step 0 evidence only. |
| A new standalone Bun-version script/workflow | P1 | Cut: the existing `claude-cli-pin-knows-models.test.ts` already scans the installed binaries (F2 adds one test, not a script). |
| Touching PR 10926 | none | Cut from code; flag only (comment). |
| Re-pinning Node/`.bun-version`/`.nvmrc` | none | Already done by #12009; not redone. |
| Server comment refresh of every "0.3.284 / 2.1.284" mention | none | Cut except the measured-pin records in the argv-tail test and helper (those ARE the pin documentation); server comments are historical. |

## User-Brand Impact

- **If this lands broken, the user experiences:** every hosted Concierge/agent Bash call failing with EPERM (the 2026-10-06 / 2026-07-01 outage shape), or a workspace session that cannot start; a founder's agent session silently unable to run commands.
- **If this leaks, the user's data/workflow is exposed via:** a silently changed builder that stops skipping/applying the `apply-seccomp` wrapper or re-exposes `/proc`, letting one tenant's Bash reach a sibling session's proxy sockets, persisted CLI output or credentials; or an unfixed embedded Bun decoding a hostile `br` response on the shared host (the claude process runs outside the Bash sandbox with the session's credentials).
- **Brand-survival threshold:** `single-user incident`
- **Threshold decision (challengeable):** one cross-tenant read of another founder's workspace content is a brand-ending event for a product whose pitch is isolated agent workspaces, so aggregate-pattern is too lax; CPO sign-off is required before `soleur:work` (see Domain Review).

## Proposed Solution

Prove first, move pins once.

1. Baseline and evidence plumbing (Phase 0).
2. In a scratch worktree outside the repo, install the exact target pair from the registry with the repo's npm 11 so the lockfile it produces is the one that will be committed; run the real-SDK suites and the red baseline there (Phase 1).
3. Only if all of P2-P4 are green: one atomic commit carrying pins, lockfile, Dockerfile (caveat deleted), pin tables, regenerated fixture, rewritten pin tests, classifier update, F2 guard, F5 swap, and the `sdk-bump-verified:` trailer (Phase 2).
4. PR with `Ref #12026`, CI as the gate (Phase 3), then production evidence from telemetry and the shipped image (Phase 4).

## Implementation Phases

### Phase 0 — Baseline and scope evidence (read-only)

- 0.1 Re-run the prd count immediately before opening the PR for review and compare with 1: `doppler run -p soleur -c prd -- bash -c 'export PGOPTIONS="-c default_transaction_read_only=on"; psql "${DATABASE_URL_POOLER/:6543\//:5432/}" -X -At -c "select count(*) filter (where web_egress), count(*) from public.workspaces"'` (pattern from `apps/web-platform/scripts/email-route-status.sh`; connection string never printed; run from a shell, not a `!` prefix). Record both numbers and UTC timestamps in the PR body; stdout must be only the two integers (a connection string must never reach the PR body on an error path). Run it at Phase 1 start, before the pin commit, and at merge. If the count rose above 1 this is the issue's pull-forward trigger: say so in the PR body and on #12026 in the same session so the owner can act on the exposure.
- 0.2 Paste the CI-scope finding from the Reconciliation table into the PR body.
- 0.3 Re-confirm `npm view @anthropic-ai/claude-code@2.1.311` and `@anthropic-ai/claude-agent-sdk@0.3.311` resolve under `min-release-age=3` (published 2026-10-26; passes).
- 0.4 Confirm the redeploy path used for a rollback exists: `web-platform-release.yml` accepts `workflow_dispatch` and deploys the head SHA (read the workflow; no run is triggered).

### Phase 1 — Scratch install and real-SDK re-proof (no committed pin moves)

- 1.1 `git worktree add --detach <scratch>/proof-12026 origin/main` outside the repo tree; in its `apps/web-platform`, edit `package.json` to the two exact pins and run `npx npm@11 install --ignore-scripts`, then `npx npm@11 ci --ignore-scripts` to prove the lock is installable (the repo's lockfile-sync job pins npm 11; a different npm major disagrees on `"dev": true` for optional packages). The scratch base commit must equal the branch's merge-base so the lockfile applies cleanly; before copying it back, diff it against the base lockfile and confirm only `@anthropic-ai/claude-code*` and `@anthropic-ai/claude-agent-sdk*` entries changed. Keep that `package-lock.json`: it is the file Phase 2 copies back, so tarballs and integrity hashes are identical by construction (F3 amendment 1).
- 1.2 Evidence of what was loaded: `sha256sum` of `node_modules/@anthropic-ai/claude-agent-sdk-linux-x64/claude` and `claude-code-linux-x64/claude` (expect `86dc1fcc69498159eaf15f446613e847010f9036bfbbdffd4c49350be8489ada` for both); installed `package.json` versions 0.3.311 / 2.1.311; corrected Bun probe on both (expect `Bun v1.4.4 (Linux x64)`). Because the scratch tree contains only the new binary, a suite cannot silently exercise the old pin.
- 1.3 RED baseline: run `sandbox-vendored-argv-tail.test.ts`, `sandbox-startup-classifier.test.ts`, `claude-cli-pin-knows-models.test.ts`, `broker-mechanism-spike.test.ts`, `plugins/soleur/test/model-launch-review.test.ts` against the scratch tree **unchanged**; record failing row names (the 9 in the issue plus the classifier census and the model-launch expiry).
- 1.4 Real-SDK proof set, run unchanged against the scratch tree (F3 minimum evidence; static or fixture-only evidence never stands in):
  - `test/sandbox-wrapped-command-runtime.test.ts` — the production-config hosted-Bash block, the G2 sibling-socket/transcript block, and the **AF_UNIX-deny variant** block (P4), including that the knob still yields `Skipping seccomp filter - allowAllUnixSockets is enabled`;
  - `test/sandbox-credential-deny-runtime.test.ts` (P2);
  - `test/sandbox-proc-mask-runtime.test.ts` (P3, live-spawn tail comparison);
  - `infra/sandbox-masked-proc-docker.test.sh` (docker 29.9 and bwrap 0.13.1 are present locally; needs sudo and AppArmor; `wrapped`, `census`, `isolation`, `recorder` arms). Not optional. If it cannot run locally (no sudo), the pin commit may be pushed to the draft PR and the CI `infra-validation` run of this suite on that head is the stand-in; this weakens F3's "before any pin" ordering for this one arm and is recorded as such in the PR body. The PR is marked ready only after that run is green.
- 1.4b The runtime suites run unchanged here, so they use the Haiku 4.5 ids; the model id is irrelevant to the sandbox-path proof, and the two swapped suites are re-run once after 2.7 (see 2.13).
- 1.5 F4 verification: with `allowAllUnixSockets: true` (as `buildAgentSandboxConfig` sets it) the helper is skipped; with the knob false and the helper present the `apply-seccomp: unshare(CLONE_NEWUSER): Operation not permitted` reproduction still occurs (negative control). Verify our config sets none of the managed-policy modes (`required`/`egress`) that drop `network.allowAllUnixSockets`; if that cannot be shown, fail the PR (F4).
- 1.6 Watch the two new tail flags in every run: `--disable-userns` (needs bwrap >= 0.8.0, not setuid; the production image's Debian bubblewrap and the `soleur-bwrap` AppArmor profile must tolerate it) and `--unsetenv <var>` (compare with the fixture's existing `--unsetenv ANTHROPIC_API_KEY`/`CLAUDE_CODE_OAUTH_TOKEN`). A hosted-Bash start failure here is a stop condition.
- 1.7 Classifier decision: measure the runtime order of the four new helper strings (read the helper's source form in the binary, plus the LD_PRELOAD interposer recipe recorded 2026-10-19 in `canary-probe-set.md` if the order is not evident). Decide each as `HELPER_STEPS_PRE_COMMAND`, `HELPER_STEPS_POST_COMMAND`, or `HELPER_NON_STEP_LINES` (a warning with a `%s` and no errno suffix is a non-step line). Record the evidence.
- **Stop condition:** any red in 1.4-1.6 that is not explained by a pin-shape change is a real isolation regression. Do not bump; keep PR 12073 draft. Post the failing rows on #12026 the same day and ask the CTO to rule on the next candidate pair (2.1.312-2.1.316, each repeating Phase 1) or on holding. Time-box: that ruling is due by 2026-11-09; if no pair is green by then, the owner is told the interim exposure (owner-only `web_egress`, 1 of 22 workspaces at baseline) and decides whether to extend the 2026-11-11 due date or to ask the single affected workspace owner to switch the toggle off (needs that owner's consent; decision-challenges F8).

### Phase 2 — One atomic pin commit (branch `feat-one-shot-12026-bun-claude-code-bump`)

Order inside the commit (tests encode the Phase 1 measurements, so they are written from evidence, not from the new code):

- 2.1 `apps/web-platform/package.json` + `package-lock.json` (copied from the scratch tree; verify `npx npm@11 install --package-lock-only` is a no-op).
- 2.2 `apps/web-platform/Dockerfile`: line `RUN npm install -g @anthropic-ai/claude-code@2.1.293` becomes `@2.1.311`; delete the two-line `# CVE-2026-111497: this CLI's native binary embeds Bun 1.4.3 ...` caveat above it (keep the `KEEP IN SYNC` and `No --before` comments).
- 2.3 Pin tables: `adhoc-npm-install-pin-table.test.ts` (the `@anthropic-ai/claude-code` Dockerfile literal, `expect: "2.1.311"`), `broker-mechanism-spike.test.ts` (declared and installed SDK version `toBe("0.3.311")`, the test name, and the `claude-haiku-5-5` swap below). `claude-cli-pin-knows-models.test.ts` reads package.json/Dockerfile dynamically; re-derive `REVIEWED_DEFAULT_EFFORT` against the new bundle (its comment says "Re-checked 2026-10-08 against claude-code 2.1.293").
- 2.4 `test/sandbox-vendored-argv-tail.test.ts` + `test/helpers/vendored-bwrap-tail.ts` (see Guard Contract, Guard 2):
  - `EXPECTED_TAIL_CALLS` gains `{ args: ["--unsetenv"], opaque: true }` and `{ args: ["--disable-userns"], opaque: false }`; `synth()` in the test mirrors the new minified shape; the TAIL failure message keeps its "a re-pin is a security decision" wording.
  - `PINS["claude-agent-sdk"]` rewritten to the measured 2/1/1/2/1/1/1/1/1/2 shape with `measuredVersion: "0.3.311"`; `PINS["claude-code"].measuredVersion: "2.1.311"`. Header comments updated with the new measurement date and versions.
  - `HELPER_SELECTION_NEEDLES.settingsMapping` replaced by content-anchored needles (property name `allowAllUnixSockets` with minifier-stable neighbours such as `allowAllUnixSockets:` and the `network` key, count >= 1, never identifiers/offsets/optional-chain), with the SDK/CLI distinction ("0 for the CLI package") removed because the two binaries are now one.
  - Bridge: `BRIDGE_WRAPPER_ANCHOR` becomes the `TCP6-LISTEN:` / `TCP4-LISTEN:` / `_srt_http=$!` anchors with counts measured in Phase 1; `scanBridgeStructure`/`assertBridgeStructure` and the synthetic bridge rows follow.
  - The lock row (`package-lock.json pins every linux variant ... to the measured version`) follows the new versions.
  - Line numbers are never cited; every anchor is a content string (ADR-116, `cq-cite-content-anchor-not-line-number`).
- 2.5 `server/sandbox-startup-classifier.ts` (`HELPER_STEPS_PRE/POST_COMMAND`, header comment version record) and `test/sandbox-startup-classifier.test.ts` per 1.7: the `minStrings: 17` floor in the census, and the equality assertion that pins `HELPER_NON_STEP_LINES` to `["observe sendmsg failed"]` (found by content, not line number). `HELPER_NON_STEP_LINES` itself lives in `test/helpers/vendored-bwrap-tail.ts`.
- 2.6 F2 guard: one test in `test/server/inngest/claude-cli-pin-knows-models.test.ts` (see Guard 1), with a per-test timeout of at least 60 s (the scan reads ~290 MB) and the `shouldSkipRealBinaryRows` gate: an absent binary reds with `BINARY_MISSING` in CI, never a skip.
- 2.7 F5 forced swap: `claude-haiku-4-5-20251001` to `claude-haiku-5-5` in `sandbox-credential-deny-runtime.test.ts` and `broker-mechanism-spike.test.ts` (`model:` lines); `claude-haiku-4-5` to `claude-haiku-5-5` in `scripts/sandbox-canary.mjs` (`CAPTURE_MODEL`) and `scripts/plugin-root-sandbox-propagation-probe.mjs`; delete `SDK_PATH_CARVEOUT`, `sdk_carveout_re()` and its `EXCLUDE_RE` term in `plugins/soleur/skills/model-launch-review/scripts/audit-models.sh`; delete every test in `plugins/soleur/test/model-launch-review.test.ts` that references `SDK_CARVEOUT_PATHS`, `sdkKnowsHaiku55`, `pkgSdkPin` or the carved-file assertions, as that test's own message prescribes; update the `SDK_PATH_CARVEOUT` documentation in `plugins/soleur/skills/model-launch-review/SKILL.md`. This swap is its own commit placed just before the pin commit, so the `sdk-bump-verified:` commit is about the pin only (the PR is squash-merged, so a rollback reverts the whole squash commit, see 4.1b); the capture model change is part of the fixture-capture evidence.
- 2.8 `agent-auth-cli-contract.test.ts` runs in the Phase 1.3 baseline (its header says "re-derive on every SDK bump"); edit it only if that run is red because the not-logged-in wording moved.
- 2.9 Fixture: `SANDBOX_CANARY_MODE=capture bash apps/web-platform/scripts/sandbox-canary-verify-in-image.sh` from the repo root with docker and `ANTHROPIC_API_KEY` read from Doppler config `ci` only, never `prd` (dev has no key; CTO F13), exported for one run with xtrace off (read-only; one paid Haiku call). Check the verdict is not `canary_infra_error` and that `infra/sandbox-canary-argv.json` actually changed (`sdkVersion` 0.3.311, the new `--unsetenv` present in the tail and `--disable-userns` ABSENT: production never emits it, see ADR-079 Review additions). Never hand-edit; never re-pin to turn it green. If `normalizeCapturedArgv` in `sandbox-canary.mjs` refuses a new token, fix the projection only with the measured evidence in the commit message; if the capture cannot run, the PR stays draft.
- 2.10 Commit message ends with the attribution line and a `sdk-bump-verified:` trailer stating exactly what was validated (Phase 1 suites with their results, fixture re-capture, binary sha256) and what was not (arm64/musl variants, the paid real-API arms that need a CI key). The trailer is written only after Phase 1 is green, the capture succeeded and 2.13 passed; keep it on the lockfile-bearing commit and check the squash-merge message preserves it.
- 2.11 ADR records (see Architecture Decision section): a short ADR-079 addendum dated 2026-11-04, a short ADR-075 pointer for the reshaped settings mapping, and the "Measured against" line in ADR-278 moved to 0.3.311.
- 2.13 Re-proof on the committed tree: after 2.1-2.9, re-run the 1.4 runtime suites and the docker arm on the branch head (the Phase 1 results came from a scratch tree; 2.7 and 2.9 changed the capture model, classifier and fixture since), and build only the image stage that carries the global install (`docker build --target cli-tools`, registry-only, about a minute) and run the corrected Bun probe on its `claude-code-linux-x64/claude`; record results, then finalize the trailer.
- 2.12 Registry files: this PR edits existing tests only, so no row in `scripts/ci-pr-affected-audit.accept.tsv`, `scripts/suite-durations.tsv` or `scripts/suite-shard-legs.tsv` is expected. If the audit replay says otherwise, insert rows in sorted position, never at end of file, and validate the accept file with `audit --accept <file>`.

### Phase 3 — PR, CI gate, PR 10926 note

- 3.1 `git push` (check the real exit code, never `| tail`); PR 12073 stays draft until Phase 1 evidence and Phase 2 are complete, then mark ready. PR body: `Ref #12026`, baseline numbers, CI-scope finding, corrected Bun probe with old/new outputs, sha256, Phase 1 results table, the `## Changelog` section, and a `semver:patch` label.
- 3.2 The gate is CI's required `test` check plus `lockfile-sync`/`sdk-bump-sandbox-gate`. `sandbox-canary-capture-gate` and `infra-validation` (the AppArmor half of the masked-/proc proof) are NOT required checks: read both runs on the pushed head, record the run ids, and arm auto-merge only when both ran and passed. Local runs are evidence, not the gate. Never push to a PR that is in the merge queue: dequeue deliberately with the GraphQL `dequeuePullRequest` mutation first.
- 3.2b CI-red loop: a fixture mismatch in `sandbox-canary-capture-gate` means re-capture in the CI image path, never a hand edit. After any rebase or main movement (including a queued PR whose base moved), re-run `npx npm@11 install --package-lock-only` and the fixture byte-diff before re-queuing.
- 3.3 PR 10926: post one comment on it flagging that its `Setup Bun` step omits `bun-version-file: ".bun-version"` and that the file already exists on `main` with the pin, the OIDC diagnose step and the `sed -n '1p'` SIGPIPE-safe form, so a rebase must keep main's version of `npm-publish.yml`. No code change here. Closing it as superseded is an owner decision (decision-challenges F7).

### Phase 4 — Post-merge evidence (telemetry only, no SSH) and issue close

- 4.1 `web-platform-release` builds the image; confirm the release tag containing the merge commit and the deploy on web-1 and web-2 via `/hooks/deploy-status` and Better Stack telemetry (the deployed version and the canary verdict; its `sdkVersion` 0.3.311 is read from the committed fixture, so it proves the image carries this commit, not that the binary embeds Bun 1.4.4 - Phase 4.2 is the binary evidence; the SDK Bash smoke verdict), per host, with a stated timeout after which a stale or mixed-host status is treated as a failed deploy. The faithful canary and the SDK Bash smoke are report-only in `ci-deploy.sh` ("deploy NOT rolled back") and the peer host is forwarded after the first host's swap, so CI is the only pre-deploy gate and this poll is the detection step.
- 4.1b Rollback: if the canary or smoke is not ok, or hosted Bash fails, revert the squash-merge commit of PR 12073 through a new PR (`git revert`; lockfile, Dockerfile, fixture, pin tests and the Haiku 5.5 ids revert together to 2.1.293 / 0.3.284) and redeploy through the release workflow (`web-platform-release.yml` `workflow_dispatch` deploys the head SHA; confirm in Phase 0 that this path is available), never SSH. Leave #12026 open and comment the verdict. Two costs the review surfaced: (1) the revert PR changes the SDK/CLI lock versions, so the required `lockfile-sync` / `sdk-bump-sandbox-gate` demands an `sdk-bump-verified:` trailer that a default `git revert` body does not carry: write it into the revert commit up front; (2) there is no faster path than a full CI cycle, a release build and sequential web-1 then web-2 deploys (up to 4800 s each), so time-to-restore is hours; and a rollback re-opens the CVE exposure. The unit is the whole squash commit, never the pin commit alone: main has no separate pin commit, and a pin-only revert would leave the Haiku 5.5 ids on a bundle that does not know them.
- 4.2 Read the shipped binaries without touching production: pull the released image digest from the registry, `docker create` it, `docker cp` out `/app/node_modules/@anthropic-ai/claude-agent-sdk-linux-x64/claude`, `/app/node_modules/@anthropic-ai/claude-code-linux-x64/claude` and the global `claude-code-linux-x64/claude`, and run the corrected probe on each. The global copy is the one Guard 1 does not reach; the other two confirm the `npm ci` tree. All three must report `Bun v1.4.4` or newer, otherwise #12026 stays open. If the image cannot be pulled locally, cite the CI guard run against the identical `npm ci` tree, the 2.13 `cli-tools` probe and the Dockerfile pin test as the evidence and say so.
- 4.3 Expect a paid `scheduled-real-sdk-ask-probe` run on the merge; check it is green.
- 4.4 Comment the evidence on #12026 (including the corrected probe) and close the issue only then. `Closes` is never used in the PR.

## Files to Edit

- `apps/web-platform/package.json`
- `apps/web-platform/package-lock.json`
- `apps/web-platform/Dockerfile`
- `apps/web-platform/infra/sandbox-canary-argv.json` (regenerated, never hand-edited)
- `apps/web-platform/test/sandbox-vendored-argv-tail.test.ts`
- `apps/web-platform/test/helpers/vendored-bwrap-tail.ts`
- `apps/web-platform/test/sandbox-startup-classifier.test.ts`
- `apps/web-platform/server/sandbox-startup-classifier.ts`
- `apps/web-platform/test/server/inngest/claude-cli-pin-knows-models.test.ts`
- `apps/web-platform/test/adhoc-npm-install-pin-table.test.ts`
- `apps/web-platform/test/broker-mechanism-spike.test.ts`
- `apps/web-platform/test/sandbox-credential-deny-runtime.test.ts` (model id only)
- `apps/web-platform/scripts/sandbox-canary.mjs` (`CAPTURE_MODEL`; projection only if the capture refuses a token, with evidence)
- `apps/web-platform/scripts/plugin-root-sandbox-propagation-probe.mjs` (model id)
- `apps/web-platform/test/agent-auth-cli-contract.test.ts` (only if its baseline run is red)
- `plugins/soleur/skills/model-launch-review/scripts/audit-models.sh`
- `plugins/soleur/test/model-launch-review.test.ts`
- `plugins/soleur/skills/model-launch-review/SKILL.md` (carve-out documentation)
- `knowledge-base/engineering/architecture/decisions/ADR-079-faithful-sandbox-canary-and-profile-redeploy-verification.md` (short addendum)
- `knowledge-base/engineering/architecture/decisions/ADR-075-agent-sandbox-tenant-read-isolation.md` (short pointer)
- `knowledge-base/engineering/architecture/decisions/ADR-278-opt-in-open-web-egress-via-dedicated-connect-gateway.md` ("Measured against" version)

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-12026-bun-claude-code-bump/tasks.md`
- `knowledge-base/project/specs/feat-one-shot-12026-bun-claude-code-bump/decision-challenges.md` (exists)

Path-glob verification: every path above was confirmed with `git ls-files` on this branch, except the two created under `knowledge-base/project/specs/`.

## Open Code-Review Overlap

None. Queried 96 open `code-review` issues against all planned paths above (two-stage `gh ... --json` then `jq --arg`); zero bodies name any of them.

## Observability

```yaml
liveness_signal:
  what: "Deploy-time faithful canary and SDK Bash smoke verdicts (sdkVersion, verdict) surfaced through /hooks/deploy-status, plus the runtime Bash synthetic (ADR-079 addenda #10453, #10455 b) and the Sentry sandbox-startup classifier events (helper_userns_eperm, helper_step_eperm, bwrap_eperm, proc_mount_eperm)"
  cadence: "per deploy (canary and smoke) and per hosted Bash call (classifier)"
  alert_target: "Sentry web-platform issues for the classifier; canary and smoke verdicts are report-only in ci-deploy.sh (no automatic rollback), so detection is the Phase 4.1 deploy-status poll (read web-2 from `.peers["10.0.1.11"]`, and treat `canary_infra_error` or an empty `sdk_version` as a failure). Alerts that exist today: the runtime classifier also pages through Better Stack (`agent_sandbox_bash_denial`, see `betterstack-log-query.md`); for deploy-time verdicts Better Stack matches only the journald line `SANDBOX_CANARY_FAIL: verdict=sandbox_broken reason=sdk_bash_smoke_failed` (email-only, auto-resolves after 10 quiet minutes); a faithful-replay `sandbox_broken` goes to Sentry; `canary_infra_error` and `smoke_infra_error` page nobody"
  configured_in: "apps/web-platform/infra/ci-deploy.sh (canary read of sdkVersion), apps/web-platform/scripts/sandbox-canary.mjs, apps/web-platform/server/sandbox-startup-classifier.ts"
error_reporting:
  destination: "Sentry web-platform via SENTRY_DSN (classifier mirrors with errorCode, matchedLine, sdkVersion, helperStep)"
  fail_loud: "classifier emits an exact-step helper_* code with the SDK version; a CI red on lockfile-sync/sdk-bump-sandbox-gate blocks merge; sandbox-canary-capture-gate and infra-validation are not required checks and are read by hand on the pushed head"
failure_modes:
  - mode: "new builder flag (--disable-userns / --unsetenv) makes every hosted Bash call fail at spawn"
    detection: "in-surface: the classifier reads the failing tool_result inside the session (errorCode bwrap_eperm / helper_step_eperm with sdkVersion 0.3.311); host-side: the deploy-time SDK Bash smoke verdict in /hooks/deploy-status"
    alert_route: "Sentry issue plus Better Stack deploy-status incident"
  - mode: "allowAllUnixSockets not honored, so the apply-seccomp wrapper re-engages and unshare(CLONE_NEWUSER) is denied by the shim"
    detection: "classifier helper_userns_eperm (exact step allowlist, structured fields discriminate pre- versus post-command), and the wrapped-command arm in CI before merge"
    alert_route: "Sentry issue; CI red blocks the bump"
  - mode: "embedded Bun regresses below 1.4.4 on a later bump"
    detection: "the Guard 1 test in claude-cli-pin-knows-models.test.ts fails in CI against the installed binaries"
    alert_route: "required CI test check (blocks merge)"
  - mode: "fixture drift: committed canary argv no longer equals the real builder tail"
    detection: "TAIL_DRIFT in sandbox-vendored-argv-tail.test.ts and the capture gate byte-diff"
    alert_route: "required CI checks"
logs:
  where: "Sentry events and the Better Stack logs warehouse; canary and smoke verdict lines in the deploy-status payload"
  retention: "per the existing Sentry and Better Stack plans (no new log sink)"
discoverability_test:
  command: jq -r '.packages["node_modules/@anthropic-ai/claude-code"].version' apps/web-platform/package-lock.json
  expected_output: "2.1.311"
```

The probe above reads the pin from the committed lockfile in under a second. The embedded-Bun property itself is asserted by the Guard 1 test against the installed binaries (a 290 MB scan does not fit preflight's 15-second sandbox cap), and the production-image binaries are read in Phase 4.2.

## Guard Contract

### Guard 1 — Embedded Bun floor (F2)

**Property.** Every installed `claude` linux-x64 binary of `@anthropic-ai/claude-agent-sdk` and `@anthropic-ai/claude-code` embeds a Bun runtime whose version is at least 1.4.4.

**Assembly.** The chokepoint is one helper in `test/helpers/vendored-bwrap-tail.ts` (or a sibling function in the same file) that reads the embedded version from a `ByteSource` and is called once per binary resolved by `resolveVendoredBinary` for both packages, so the two binaries are examined by the same code path and can diverge again. Members: `claude-agent-sdk-linux-x64` and `claude-code-linux-x64` under `apps/web-platform/node_modules`. Not reached by a byte scan: the x64-musl/arm64/arm64-musl/darwin/win32 variants, which are covered only by the existing lock-version equality row (the scanned x64 binary stands for them, as `sandbox-vendored-argv-tail.test.ts` already states), and the Dockerfile global install tree, covered by the existing offline pin-agreement rows and read directly in Phase 4.2. The scan uses a bounded `fileSource` read (no whole-file buffer), matches `Bun v<major>.<minor>.<patch>` followed by a space and `(` so the bare `Bun v` string-pool fragments never count, and takes the minimum across ALL occurrences (the binary carries the version in two places). Comparison is numeric semver, not string order.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Synthetic buffer whose only version is `Bun v1.4.3 (Linux x64)` | RED naming the package and both versions |
| 2 | Synthetic buffer holding only bare `Bun v` fragments (the issue's original probe shape) | RED ("no version found"), never a pass or a skip |
| 3 | Dispatch: the package list resolves zero binaries, or only one of the two | RED (floor of 2 binaries checked; "0 checked" cannot pass) |
| 4 | Second member after a compliant first: buffer with `Bun v1.4.4 (...)` first and `Bun v1.4.3 (...)` later | RED (minimum over all occurrences, not the first) |
| 5 | Real binaries: SDK compliant, CLI swapped to a 1.4.3 fixture buffer | RED naming the CLI binary only |

**Harness rows.** (a) Delete the helper call from the real-binary row: a suite-level `expect(checked).toBe(2)` count assertion reds. (b) Must-PASS inputs that differ from the canonical `1.4.4`: `Bun v1.4.10 (...)` (numeric, not lexicographic, compare) and `Bun v1.5.0 (...)`.

**Anchor.** The floor `1.4.4` is a constant in the test file, so one diff can lower the floor and move the pins together: the guard proves consistency with the stated floor, not integrity of the floor. What outside the commit must also move for a weakening to pass: the `sdk-bump-verified:` trailer on any lockfile change (`sdk-bump-sandbox-gate.sh`), and the CVE reference in the test header that a reviewer will see in the diff. Accepted residual, stated rather than hidden. The musl and arm64 variants are covered only by lock equality; the production base `node:22-slim` is glibc x64, so that is acceptable.

### Guard 2 — Vendored builder pins (F4) and fixture equality

**Property.** The vendored bwrap builder's per-command argv still ends with the masked-`/proc` tail (`--unsetenv`; `--disable-userns` is conditional and absent under our config), keeps exactly the audited `/proc`, `--unshare-pid`, root-bind and capability sites, still selects the `apply-seccomp` helper by the `allowAllUnixSockets` knob, still starts the proxy bridges before the user command under `--unshare-net`, and equals the committed canary fixture.

**Assembly.** Chokepoint: `resolveVendoredBinary` for both packages, then the helper's extractors: `extractBuilderTailFrom` (tail window), `scanLiterals` (site census), `scanHelperSelection` (skip/apply/missing lines plus the content-anchored settings needle), `scanBridgeStructure` (TCP6/TCP4 wrapper anchors, `--unshare-net` window), `readFixtureTail`/`assertTailMatchesFixture` against `infra/sandbox-canary-argv.json`, and the classifier census (`scanHelperStepStrings` against `HELPER_STEPS` in `server/sandbox-startup-classifier.ts`). Three injection sites for mounts exist (`BWRAP_ARGS`-style builder, hook-site function under `/run/claude-hook`, and the bind/proc branches); the census is per-package over all of them, not scoped to the first.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Append `.push("--tmpfs","/proc")` after the bind push in a synthetic builder (retained row, re-pinned to the new shape) | RED TAIL_LITERALS |
| 2 | Remove `--disable-userns` (or reorder it before `--bind /proc /proc`) in a synthetic builder | RED TAIL_LITERALS (a pinned security flag cannot silently vanish) |
| 3 | Dispatch: scan an empty or anchor-less buffer (retained row, re-pinned to the new shape) | RED `TAIL_ANCHOR found 0`, never "0 checked" |
| 4 | Third `"--proc","/proc"` site after the compliant two, and a third `--unshare-pid` (retained row, re-pinned to the new shape) | RED PROC_SITE_COUNT / SITE_COUNT |
| 5 | Settings needle absent (knob unread) while the three log lines remain | RED HELPER_SELECTION settingsMapping |
| 6 | Bridge wrapper anchor absent, or `TCP4-LISTEN:` present twice | RED bridge anchor count |
| 7 | Fixture tail edited to add `--tmpfs /proc` after the bind (retained row, re-pinned to the new shape) | RED TAIL_DRIFT naming the only regenerator |
| 8 | A fifth new `apply-seccomp:` string not in `HELPER_STEPS`/`HELPER_NON_STEP_LINES` | RED HELPER_STEP_NEW |

Reorder row for the ORDER property (bridges before the user command, `/proc` mask last in the tail): the synthetic bridge builder with the user command moved ahead of the bridge array, and the tail with `--disable-userns` moved ahead of the proc branch, each RED; plus one case that observes inside the window (the fixture replay in the docker `recorder` arm).

**Harness rows.** (a) Edit the suite, not the guard: change a synthetic `synth()` option so the builder no longer matches the real shape and require the must-PASS control row to go RED (proves `synth()` still tracks the real builder). (b) Must-PASS non-canonical inputs: a synthetic builder with an extra unrelated `.push("--setenv", ...)` before `--dev /dev`, and a hook site whose proc literal sits at a different offset.

**Anchor.** The pins are re-derived from the binary and the fixture is regenerated by the capture script inside the deploy base image; an independent anchor outside the commit is `sdk-bump-sandbox-gate.sh` (merge-base diff of the lockfile versions, trailer required) and the CI capture-gate byte-diff. A `>= N` floor never stands alone: counts are paired with set identity (the offsets and neighbouring content anchors are asserted by the synthetic rows).

## Architecture Decision (ADR/C4)

Not a new decision: the CTO rulings (F1-F4) are recorded in `decision-challenges.md`. A reader of ADR-079/ADR-075 would however be misled about the mechanism (the addenda describe the 0.3.284 builder and the old bridge shape), so the record is updated in this PR.

### ADR
Add a short addendum to ADR-079 dated 2026-11-04 (via `soleur:architecture`): the pair, the one-binary-for-both-packages fact, a pointer to the PR evidence (the measured shape changes live in the pin-test headers, not here), and the F4 rule that the runtime arm, not the static needle, is the proof. Add a short pointer in ADR-075 (the 2026-10-16 `allowAllUnixSockets` posture now rests on a reshaped settings mapping with a managed-policy drop path) and move ADR-278's "Measured against" version to 0.3.311. No new ADR ordinal is claimed, so no ordinal-collision risk.

### C4 views
No C4 impact. Checked against all three model files (`model.c4`, `views.c4`, `spec.c4`): external human actors (hosted founder, support end user, untrusted contributor, plugin users) unchanged; external systems (Anthropic API, GitHub, Better Stack, Sentry, the open-web-egress gateway, MCP servers) unchanged and unversioned in the model; containers/data stores touched: none (the `Agent Runtime` container's technology is the unversioned string "Claude Code"); actor-to-surface access relationships unchanged. No element names the claude-code or agent-sdk pin or a Bun version. `plugins/soleur/test/c4-count-parity.test.sh` is run as the backing check.

### Sequencing
None; the addendum lands with the bump.

## Domain Review

**Domains relevant:** engineering (CTO), product (CPO sign-off for the single-user-incident threshold)

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Rulings F1-F4 above are the CTO's, with the evidence table as input. Net: exact pin 2.1.311/0.3.311; standing Bun floor guard; scratch-proof sequencing with three amendments; runtime arm is load-bearing and the static needle is a tripwire; docker masked-/proc arm is not optional.

### Product (CPO sign-off)

**Status:** reviewed — CPO sign-off: approved (2026-11-04). The User-Brand Impact framing and the `single-user incident` threshold are right; the interim exposure (1 of 22 workspaces, owner-only toggle, hostile `br` response required) is acceptable while the proof runs. Conditions folded in above: re-check the `web_egress` count at Phase 1 start, before the pin commit and at merge and treat a rise as the pull-forward trigger (Phase 0.1); a dated ruling by 2026-11-09 if the stop condition fires, with the owner told the interim exposure (Phase 1 stop condition); a stated rollback path (Phase 4.1b).

### Product/UX Gate

**Tier:** none (no UI surface: no `components/**/*.tsx`, `app/**/page.tsx` or layout files in Files to Edit/Create).
**Decision:** not applicable
**Agents invoked:** none
**Skipped specialists:** none
**Pencil available:** N/A (no UI surface)

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Record the baseline count of workspaces with web_egress=true (read-only prd query), per step 0 of the issue." [brief] | Phase 0.1 (1 of 22 recorded) | mapped |
| 2 | "Re-prove credential-deny, masked /proc and AF_UNIX isolation through the real SDK path BEFORE moving any pin." [brief] | Phase 1.1-1.6 | mapped |
| 3 | "Regenerate infra/sandbox-canary-argv.json." [brief] | Phase 2.9 | mapped |
| 4 | "Bump package.json, package-lock.json, the Dockerfile `npm install -g @anthropic-ai/claude-code@...` line and the pin-table tests together; remove the CVE caveat comment above that Dockerfile line." [brief] | Phase 2.1-2.3 | mapped |
| 5 | "Update sandbox-vendored-argv-tail.test.ts to the new builder shape, keeping the assertions meaningful (anchor on content, not line numbers)." [brief] | Phase 2.4, Guard 2 | mapped |
| 6 | "Use `Ref #12026` in the PR body, NOT `Closes`" [brief] | Phase 3.1, 4.4 | mapped |
| 7 | "Also cross-check open PR 10926 (npm-publish SIGPIPE fix): on rebase it would re-float the npm-publish bun pin ... flag or fix that conflict if it touches this work." [brief] | Phase 3.3, decision F6/F7 | mapped |
| 8 | "Keep the `claude-cli-pin-knows-models.test.ts` pin parity green." [issue #12026] | Phase 2.3, Guard 1 (same file) | mapped |
| 9 | "rely on CI's required `test` check as the gate, not the local affected-test gate" [brief] | Phase 3.2 | mapped |
| 10 | "Registry files ... get new rows in sorted position, never appended at end of file." [brief] | Phase 2.12 | mapped |
| 11 | "Production host state comes from telemetry (Better Stack, /hooks/deploy-status), never SSH." [brief] | Phase 4.1-4.2 | mapped |
| 12 | "`strings <bin> | grep -m1 '^Bun v'` on the installed binaries reports Bun >= 1.4.4" [brief] | Phase 4.2 (with the corrected regex), Guard 1 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Phase 1 scratch install | "Re-prove ... BEFORE moving any pin" | asked |
| Guard 1 embedded-Bun floor (F2) | — | inferred — justification: CTO ruling F2; pin tests prove the package version, not the runtime embedded in the binary where the CVE lives, and the issue's own probe cannot report a version |
| Classifier update (`server/sandbox-startup-classifier.ts`, test) | — | inferred — justification: the pin bump reds its Guard 2 census (`HELPER_STEP_NEW`, `minStrings: 17`), so the PR cannot merge without it |
| F5 model-launch-review swap | — | inferred — justification: `model-launch-review.test.ts` self-expires at SDK >= 0.3.293 and fails the required `test` check |
| `agent-auth-cli-contract.test.ts` re-derivation | — | inferred — justification: its header makes re-derivation on every SDK bump the tripwire |
| ADR-079 addendum, ADR-075 pointer, ADR-278 version line | — | inferred — justification: `wg-architecture-decision-is-a-plan-deliverable`; all three cite 0.3.284 as the measured builder and would mislead |
| Phase 4.1b rollback and the 2.13 branch-head re-proof | — | inferred — justification: the canary and smoke are report-only (no auto-rollback) and the Phase 1 evidence came from a scratch tree, so the single-user-incident threshold needs a stated revert path and a re-proof on the committed tree |
| Time-boxed stop condition (2026-11-09) | — | inferred — justification: the P1 due date is 2026-11-11 and CPO sign-off required a dated decision path |
| `sdk-bump-verified:` trailer | — | inferred — justification: `sdk-bump-sandbox-gate.sh` blocks merge without it or a passing capture |
| Phase 4.2 image read | "reports Bun >= 1.4.4" | asked |
| PR 10926 comment | "flag or fix that conflict" | asked |

### Split Assessment

- Subsystems touched: 3 — apps/web-platform, plugins/soleur, knowledge-base
- Planned files: 24 | Estimated changed lines: ~700 (plus lockfile churn)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

### Pre-merge (PR)

- [ ] PR body uses `Ref #12026` and contains no `Closes`/`Fixes` for it; carries `## Changelog`, the baseline (1 of 22 `web_egress` workspaces, UTC timestamps), the CI-scope finding, the corrected Bun probe with old and new outputs, and the binary sha256.
- [ ] Phase 1 evidence table (suite, result, binary sha256 loaded) is in the PR body and shows green for: wrapped-command runtime (incl. AF_UNIX-deny variant), credential-deny runtime, proc-mask runtime, and the docker masked-/proc suite (locally before the pin commit or, if sudo is unavailable, the CI `infra-validation` run on the draft head, with the PR marked ready only after it is green); the 2.13 re-run on the branch head is recorded too.
- [ ] `apps/web-platform/package.json` pins `@anthropic-ai/claude-agent-sdk` `0.3.311` and `@anthropic-ai/claude-code` `2.1.311` exactly; `package-lock.json` resolves both and all eight platform entries of each to those versions and is a no-op under `npx npm@11 install --package-lock-only`.
- [ ] Dockerfile line is `RUN npm install -g @anthropic-ai/claude-code@2.1.311` and the `CVE-2026-111497: this CLI's native binary embeds Bun 1.4.3` caveat comment is gone (`grep -c "embeds Bun 1.4.3" apps/web-platform/Dockerfile` prints 0).
- [ ] `infra/sandbox-canary-argv.json` is regenerated by the capture script (`sdkVersion` `0.3.311`, tail carries `--unsetenv` and no `--disable-userns`), never hand-edited; verdict is not `canary_infra_error`.
- [ ] `sandbox-vendored-argv-tail.test.ts` passes with the rewritten pins; every anchor is a content string; no assertion cites a line number; synthetic rows still fail on each Guard 2 mutation.
- [ ] Guard 1 test exists in `claude-cli-pin-knows-models.test.ts`, passes on both installed binaries, and fails on each Guard 1 mutation row (positive control: bare `Bun v` does not count).
- [ ] `sandbox-startup-classifier.test.ts` census green with an evidenced pre/post/non-step decision for each of the four new strings.
- [ ] `model-launch-review.test.ts`, `claude-cli-pin-knows-models.test.ts`, `adhoc-npm-install-pin-table.test.ts`, `broker-mechanism-spike.test.ts` green; `grep -rn SDK_PATH_CARVEOUT plugins/` returns no hit; the four carve-out files on `claude-haiku-5-5`.
- [ ] The commit introducing the lockfile change carries a `sdk-bump-verified:` trailer that lists what was and was not validated.
- [ ] CI required `test` check and the SDK-bump gates are green on the PR head; any new registry row sits in sorted position and `audit --accept` validates.
- [ ] A comment is posted on PR 10926; no change to its branch.
- [ ] ADR-079 addendum, ADR-075 pointer and ADR-278 version line committed; `plugins/soleur/test/c4-count-parity.test.sh` green.

### Post-merge (agent-executed, telemetry/image only, no SSH)

- [ ] Release deployed on web-1 and web-2 per `/hooks/deploy-status` and Better Stack; canary verdict ok with `sdkVersion` 0.3.311 (fixture-sourced commit identity, not binary evidence; 4.2 is the binary evidence); SDK Bash smoke ok.
- [ ] Corrected probe on the three shipped binaries extracted from the released image (or the documented CI-based fallback) reports `Bun v1.4.4` or newer; if any one does not, #12026 stays open.
- [ ] Per-host deploy status shows the new version and an ok canary and smoke verdict within the stated timeout; otherwise the Phase 4.1b rollback runs.
- [ ] `scheduled-real-sdk-ask-probe` run after merge is green.
- [ ] Evidence commented on #12026, then the issue is closed.

## Test Scenarios

### Acceptance Tests (RED phase targets)

- Given the scratch tree at 0.3.311, when `sandbox-vendored-argv-tail.test.ts` runs unchanged, then the real-binary rows fail (tail, census, helper selection, bridge, fixture) — the RED baseline.
- Given the rewritten pins, when the same file runs against the installed pair, then all rows pass.
- Given the installed binaries, when Guard 1 runs, then both report >= 1.4.4; given a synthetic 1.4.3 buffer, then it fails naming the package.

### Regression Tests

- Production-config hosted Bash through the real SDK returns its stdout (no `apply-seccomp: unshare(CLONE_NEWUSER)` EPERM).
- AF_UNIX-deny variant: a no-egress session's Bash starts; a sibling session's proxy socket and persisted CLI content are not reachable; the credential-deny decoy key is not readable from inside the sandbox; the sandbox `/proc` lists no outside pid.
- Fixture replay in the docker suite passes through the shim with the new tail.

### Edge Cases

- `--disable-userns` under the production AppArmor profile and docker default masks.
- The sockstat watchdog loop does not terminate the bridge early on a session with one idle connection.
- Lock row: x64-musl, arm64 and arm64-musl entries all at the new versions.
- Guard 1: a binary with no `Bun v<semver> (` match at all (format change) reds; the 290 MB scan stays under its explicit timeout.
- The global install tree and the project `npm ci` tree report the same claude-code version (Dockerfile pin agreement) and both Bun floors hold.
- Image-size growth (three ~294 MB copies) is measured in the PR body; no size gate was found, so it is reported, not assumed within limits.
- Classifier: the pre-command versus post-command decision for each new helper string is backed by a measured order, not inferred from the name.

### Integration Verification (for `soleur:qa`)

- **Pre-merge:** `bash apps/web-platform/infra/sandbox-masked-proc-docker.test.sh` (sudo, docker); `cd apps/web-platform && npx vitest run test/sandbox-vendored-argv-tail.test.ts test/sandbox-startup-classifier.test.ts test/server/inngest/claude-cli-pin-knows-models.test.ts`.
- **Post-merge:** read `/hooks/deploy-status` for the release containing the merge; extract and probe the image binaries as in Phase 4.2.

## Dependencies & Risks

- **Image size:** the platform binary grows ~243 MB to ~293.8 MB, and three copies ship (SDK, project claude-code, global claude-code). Check the web-platform image build and registry push still fit existing limits and note the delta in the PR; no size gate was found in the research, so this is measured, not assumed.
- **Fixture capture can refuse new tokens** (`normalizeCapturedArgv` fails loud on unknown bwrap options). Mitigation: fix the projection with measured evidence; if capture cannot run, the PR stays draft; the ack trailer never substitutes for a stale fixture.
- **Newer releases keep arriving** (2.1.318 is the current `latest`). Mitigation: F1; revisit only if an advisory names a version above .311.
- **Min-release-age:** .311 is eight days old, passes the 3-day floor; any switch to .317+ would fail ETARGET until 2026-11-06.
- **Shared worktrees:** another worktree is running `test-all.sh`; long batteries use `SOLEUR_TEST_ALL_ALLOW_ORPHAN=1 setsid nohup` and are not killed by the parent-death watchdog.
- **Privileged suite locally:** the docker suite needs sudo; if the work environment cannot provide it, the PR stays draft and CI evidence is the only stand-in (F3).
- **PR 10926 can still be force-resolved wrongly** by a future rebase; mitigation is the comment plus the existing `bun-version-file` convention across 20 workflows; the owner decides on closing it.
- **Interim exposure until merge:** unchanged from the issue (owner-only `web_egress` toggle, 1 of 22 workspaces now). Due date 2026-11-11.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or carries filler text fails `deepen-plan` Phase 4.6; this one is filled and declares `single-user incident`.
- Never cite line numbers for the changed anchors; the pins and comments use content strings (the Dockerfile caveat is identified by its first words, the tail by its literal calls).
- The measured-version records in `sandbox-vendored-argv-tail.test.ts` and the helper must name the new versions and date; a pin that says "measured on 0.3.284" after the bump is the stale-evidence defect.
- Do not use `bun test` or the local affected-test gate as the merge gate; CI's required `test` check is.
- A `| tail` after `git push` hides its exit code; check the real status.
- Compare UTC to local time (CET is UTC+1 today) before reasoning about elapsed time or the 3-day release-age window.
- Do not touch `.bun-version`, `.nvmrc` or the npm-publish `setup-bun`; they were done in #12009.
- The issue's acceptance command is vacuous as written; replace it everywhere with the version-capturing regex.

## References

- Issue #12026; PR 12073 (draft); #12009 (Node half); PR 10926 (stale npm-publish PR); #8643, #10549, #10115, #9724 (related sandbox work).
- ADR-079 (faithful canary, SDK-bump guard, addenda to 2026-10-23); ADR-075 addendum 2026-10-16 (`allowAllUnixSockets`); ADR-272 (credential deny); ADR-278 (open-web egress); ADR-116 (content-anchored citations).
- `apps/web-platform/scripts/sdk-bump-sandbox-gate.sh`, `apps/web-platform/scripts/sandbox-canary-verify-in-image.sh`, `apps/web-platform/infra/sandbox-masked-proc-docker.test.sh`.
- Learnings: 2026-11-03-base-image-cve-bump-is-a-pin-census-not-a-digest-edit; 2026-10-18 allowAllUnixSockets canary-green-over-outage; 2026-09-29 sdk-bump attestation; 2026-10-09 model-launch pin; post-mortem 2026-07-01 concierge bwrap seccomp.
