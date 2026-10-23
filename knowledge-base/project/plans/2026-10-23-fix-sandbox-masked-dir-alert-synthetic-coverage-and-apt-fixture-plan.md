---
title: "sandbox: routed alert for masked-dir-precreate, synthetic mask coverage, and the deploy-script-tests apt fixture"
date: 2026-10-23
slug: sandbox-masked-dir-alert-synthetic-coverage-and-apt-fixture
branch: feat-one-shot-10455-prb-masked-dir-alert-deploy-tests
issue: 10455
type: fix
priority: p2
domain: engineering
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
lane: cross-domain
refs: [10455, 10548, 10781, 8744]
closes: []
pr: 10892
---

# sandbox: routed alert for masked-dir-precreate, synthetic mask coverage, and the deploy-script-tests apt fixture

## Enhancement Summary

**Deepened on:** 2026-10-23. **Agents and rulings used:** CTO (7 forks, 6 follow-up rulings), CPO sign-off, a 5-agent plan-review panel (DHH, Kieran, code-simplicity, architecture-strategist, spec-flow), then security-sentinel, observability-coverage-reviewer, user-impact-reviewer and a best-practices apt researcher; mechanical gates 4.6 to 4.12 run.

### Key improvements

1. **P0 caught by the observability pass and verified in code:** the planned `reportSilentFallback(err, ...)` emit would have been deduplicated behind the pino mirror's `feature=pino-mirror` capture (#8629), so the new Sentry rule could never have fired. The emit now uses the message path (`null` first argument), carries `extra.code`, and has a real-path test.
2. The apt claim was narrowed: the shared cache fixes the multi-container exhaustion signature only; the two first-`update` stall signatures are instrumented, not fixed; `Closes #10781` became `Ref`.
3. The probe's PID-1 reads were hardened (narrow `/proc/1/environ` filter, closed-enum journal fields) and a HOME guard added against a false-green.

### New considerations

- The merge alone mutates production in three ways (Sentry apply, synthetic re-delivery to both web hosts, release restart); see the new section.
- The #10548 soak reads the deploy-time ledger, which this PR does not change.

Spec lane note: no `spec.md` exists for this branch, so `lane:` defaulted to `cross-domain` (fail-closed).

## Overview

PR-B of the post-incident bundle in #10455 (`Ref #10455`, never `Closes`: the persisted-CLI-output
measurement, the legacy-runner observer and several test-hardening items stay open there), plus two CI items
found on the same day. Four deliverables, one PR (draft PR #10892):

1. **Routed alert for `op=masked-dir-precreate`.** Today the pre-create failure is a Sentry error event with
   no rule behind it. Add one Sentry email rule, a low-cardinality `dir_kind` tag so the event says which
   channel is unmasked, and a contract test that ties emit site to rule.
2. **The `masks_missing=3` finding.** Diagnosed (below): it is the cold-container state, not a pre-create
   defect. Under alpha traffic it is the permanent state, so the runtime synthetic never exercises the
   masked-dir mounts and can never claim the full production tuple. A fourth production dir (`/tmp/.cs`) is
   additionally invisible to the probe. Fix: the runtime probe creates the missing dirs exactly as production
   does, behind a PID-1-uid guard.
3. **The `deploy-script-tests` apt fixture red** (tracker #10781; `Ref`, not `Closes`: the failure is
   intermittent, so one green leg is not proof). Two distinct signatures, stated separately:
   (a) the multi-container suite (`git-data-runcmd-rehearsal`: 12 containers in series, 420 s budget) re-runs a
   full `apt-get update` + `install` per container and was calibrated with ~34 s of headroom over a measured
   slow-box cost, so a slow-mirror day exhausts the shared budget; the shared lists/archives cache fixes this.
   (b) the single-container suites (`git-data-ownership`, `htpasswd-stdin`) stalled twice on the very FIRST
   `apt-get update`; a cache cannot help the first container, so this PR only bounds the stall cost
   (the cache cuts the stall exposure from ~12 cycles to 1-2) and makes the stalled phase visible (surfacing the apt
   tail), so the next occurrence is diagnosable. It does not claim to fix (b); a first-cycle mirror stall remains
   and fails closed. No `Acquire::http::Timeout` is added (never shipped in this repo, see Corrections; the 90 s attempt cap sits below apt's default 120 s HTTP timeout). No budget or assertion is loosened and no
   arm becomes skip-eligible.
4. **Inngest GuardA re-check.** Verified green on main (see Research Insights). No change.

Out of scope and operator-only: #10548 (create and enable flag `agent-sandbox-unix-deny`, ADR-236). The PR
body carries the exact typed commands under an operator hand-off line (Phase 5). The flag is not touched.

## Premise Validation (Phase 0.6)

Checked with `gh` / `git` / data pulls on 2026-10-23: #10455 OPEN (milestone `Post-MVP / Later`); #10548 OPEN
(follow-through tracker, `earliest=2026-10-26`); PR #10892 OPEN draft; PRs #10546 and #10697 merged;
op `masked-dir-precreate` exists on main (`agent-runner-sandbox-config.ts`, loop over the three dir lists);
`masks_missing` is emitted by `infra/lib/sdk-bash-probe.mjs` and journaled by `infra/web-bash-synthetic.sh`;
GuardA row is in `cloud-init-inngest-bootstrap.test.sh`. Two claims in the brief needed correction:

- The brief says the apt failure is in "the apt-get fixture". It is a family: `git-data-runcmd-rehearsal`
  (budget exhausted), `git-data-ownership` and `htpasswd-stdin` (first `apt-get update` stalled twice at the
  90 s attempt cap), each with a distinct signature. #10781 already tracks it (opened by a prior session); its
  "shard partition shift" hypothesis was retracted in its own comment and this plan does not rely on it.
- The ADR corpus check (Phase 0.6 step 4): ADR-188 amendment 2026-10-01 (#9379) is the apt-bounding design and
  ADR-079 addendum 2026-10-22 states "the probe creates nothing outside its own scratch dirs in runtime mode".
  The second is reversed by this plan on evidence, so it is amended, not silently contradicted (see ADR/C4).

## Research Reconciliation: spec/issue vs. codebase

| Claim | Reality (measured 2026-10-23) | Plan response |
|---|---|---|
| #10455 comment: "`masks_missing=3` is the PR-B `masked-dir-precreate` territory" | 85 of 85 passing synthetic runs on both web hosts in the last 24 h read `masks_missing=3`; Sentry has **zero** `op:masked-dir-precreate` events in 14 d; Supabase `prd` has 0 assistant messages in 36 h and 8 in 7 d. The production `mkdirSync` has not failed. The dirs are created by the first real dispatch only. | The finding is a probe-coverage defect, not a pre-create defect. Fix the probe (Phase 2), keep the alert as the detector for the real pre-create failure (Phase 1). |
| Probe masks = "the production masked set" | `maskedDirs()` has 3 entries; production pre-creates 4 (`AGENT_SESSION_TMP_ROOT` = `/tmp/.cs` too) and `smokeSandboxConfig.denyRead` carries `/tmp/.cs` as a literal outside `masked`. Neither the deploy smoke nor the runtime synthetic ever creates or counts it. | Add it through a separate constant (order of `denyRead` is pinned by `sdk-bash-probe-parity.test.ts`). |
| "apt-get fixture times out" | Healthy runs spend 3 s of apt; failing runs spend 420 s across 7 to 11 attempts (rehearsal) or 2 x 90 s on the first `update` (ownership, htpasswd). `apt-bounded.sh` said apt's own timeouts were set although the helper only ever set `Acquire::Retries` (see Corrections: `Acquire::http::Timeout` was never shipped). | Phase 3 (shared cache + visible tail; no timeout option, unproven); stale comment fixed. |
| "GuardA red pending the pin bump" | Red on every main/PR run from 21:45Z to 00:10Z on 10-22/23 (`pin v1.1.57` vs latest tag `vinngest-v1.1.58`). `f6ebfa6c68` (#10878) bumped the pin; `Infra Validation` on main is green since 01:01Z (run 39881599619, all `deploy-script-tests` legs including 4/4). HEAD contains the bump. | No change; recorded in the PR body. |
| Brief: "persisted-CLI-output measurement" is PR-B | The #10697 comment lists it for PR-B, but the operator's brief for this PR scopes only the alert and the `masks_missing` finding. | Not in this PR (Scope Check); it stays an open item on #10455. |

## Research Insights

**Property list (Phase 0.6b).**
P1. A masked-dir pre-create failure in the app reaches a human without anyone reading a dashboard.
P2. The runtime synthetic's coverage claim is true: when it says `sdk_wrapper_shim_prodtuple` the masked-dir
mounts were part of what it ran.
P3. The `deploy-script-tests` git-data/htpasswd fixtures stop depending on N repeated mirror round-trips, with
every budget and assertion unchanged.
P4. The GuardA state on main is recorded, not assumed.

**Cut list.** Each mechanism the brief or the issue implies, the property it buys, and what already covers it:

- Better Stack Logs alert on the same op: P1, but the event is a Sentry event plus a pino line; the Sentry rule
  is the existing convention for `reportSilentFallback` ops (`seccomp_remediation_failed`). Cut.
- Distinct-user threshold / `event_unique_user_frequency_count`: P1, no `userId` on the event, and that trigger
  type is frozen in this provider version. Cut (CTO ruling, Decision Classes).
- Per-dir Sentry fingerprint: would turn one persistent fault into one issue per dir and page storms. Cut.
- Firing a synthetic event into production Sentry: P1 proof, but a production write that emails ops@. Cut from
  this PR (CTO ruling); proof is the three-link chain in Guard 1.
- Create the masked dirs at app boot / entrypoint (option C): P2, but it changes production boot for a
  monitoring need and hides the builder's own mkdir path (the one that has the alert). Cut.
- Pre-baked fixture image per suite (apt option B): P3, but moves apt into an unbounded `docker build`. Cut.
- Raising any apt budget: forbidden by the brief. Cut.
- `Acquire::ForceIPv4`: no evidence in the repo or the logs. Cut.
- Mirror fail-over for a genuine first-container mirror outage: not provable from the artifacts; residual
  recorded on #10781 instead of building it.
- Persisted-CLI-output measurement: not asked in this brief. Not built; stays on #10455.

**Diagnosis 1: `masks_missing=3`** (data pulled with `scripts/betterstack-query.sh`, `SENTRY_ISSUE_RO_TOKEN`
and the Supabase REST count). Journal lines: `verdict=pass reason=ok selector=base coverage=prodtuple_partial
masks_missing=3` x 85 (web-1 `soleur-web-platform` 42, web-2 43) across the 11 h since the last deploy. The
probe's `maskedDirs(uid, home)` is `/tmp/cc-socks`, `/tmp/cc-socks-<uid>`, `<HOME>/.claude/projects`; runtime
mode only counts which exist (`isDir` = `statSync().isDirectory()`), and production creates them in
`buildAgentSandboxConfig` at the first dispatch. With 8 assistant messages in 7 days no dispatch has run in
either container since the deploy, so all three are absent. **Status: the strongest hypothesis, not CONFIRMED.**
The deciding datum (does `/tmp/cc-socks` exist in the running container) cannot be read without `docker exec`
on the host, and the Supabase count measures assistant messages, not dispatches. What it rules out, with
controls: not a mkdir defect (the Sentry query `op:masked-dir-precreate` is empty over 14 d, and the control
query `feature:agent-sandbox` on the same endpoint returned the `sandbox-canary-outer-wrap` events with their
`op` field, so the filter works); not a HOME or uid mismatch (the first two paths are HOME-independent). The
fix is itself the probe that confirms it: the first post-merge run on a cold container reports
`masks_created=4` (hypothesis true) or `masks_missing>0` with `masks_note` naming why (hypothesis
false, and the alert path is then the next suspect). Container facts: `--tmpfs /tmp:rw,nosuid,nodev,size=256m`
(wiped on each container start), `USER soleur` (Dockerfile), `docker exec` without `-u`.

**Diagnosis 2: apt.** Three red signatures on 2026-10-22 (runs 39801931672 and 39806578595 at 15:16 and 15:46Z,
39859809156 at 21:54Z), all on the pull-request/main legs, none since 01:01Z 10-23:
(a) `git-data-runcmd-rehearsal`: `GD_APT: spent=420s of budget=420s across 7/10/11 apt attempt(s)`, last
container `stage=none attempt=1 attempt_secs=0 spent_before=420s` (budget gone before it started), then the S1
skipped-assertion ceiling (#10781); (b) `git-data-ownership` and `htpasswd-stdin`: `stage=update attempt=2
attempt_secs=90 spent_before=0s budget=180s` (two 90 s cap kills on the very first `update`). Facts from the
code and commit `3e5c5e0a38` (#9383): one `apt-get update` + `install` per container, ~12 containers in the
rehearsal, measured healthy cost ~32 s per container (386 s of 420 s on a slow box), apt's default HTTP
timeout is 120 s (longer than the 90 s attempt cap, so apt's `Retries` can never act inside a cap), and the
18-20 line scrubbed apt tail the helper prints is not in the CI output, so the stalled phase is invisible.
**Measured here** (value proposition, Phase 0.6c; command: `docker run` of the digest-pinned `ubuntu:24.04`
with `-o Dir::State::lists=/work/apt/lists -o Dir::Cache::archives=/work/apt/archives`, `curl python3`):
80 to 102 s cold, 17 to 19 s warm on the same bind mount on a dev box (one-off measurements, -81 % at best; a healthy CI apt cycle is 2 to 5 s), 38 `.deb` files retained (`docker-clean` does not touch
a custom archives dir). On a healthy day the saving is small (3 s of apt); it matters on exactly the days the
mirror is slow, which is when the suite reds. A genuine mirror outage during the **first** container remains
fail-closed by design (#8744); the plan records it as a residual, not a fix.

**Diagnosis 3: GuardA.** `cloud-init-inngest-bootstrap.test.sh` "pin matches latest `vinngest-v*` tag merged
into HEAD" and "GuardA: every baked carrier byte-identical" failed on 10-22 (21:45Z to 00:10Z, runs 39859809156,
39864948621, 39875013638 and ~11 PR runs) with `pin v1.1.57` vs latest `v1.1.58` (drift: `vector.toml`). PR
#10878 (`f6ebfa6c68`) set `ghcr.io/jikig-ai/soleur-inngest-bootstrap:v1.1.58@sha256:14a46f56...` in
`cloud-init-inngest.yml` (lines 1266, 1316) and `cloud-init.yml` (719, 723). `infra-validation.yml` on main:
success at 23:56Z (f6ebfa6c6) and 01:01Z (29e153037, run 39881599619, `deploy-script-tests (4/4)` success).
**Verdict: green; no change.** Re-verify with a fresh read before opening the PR for review.

**Institutional learnings applied** (`knowledge-base/project/learnings/`): `2026-10-02-a-shared-apt-budget-must-be-charged-in-apt-seconds-and-a-count-census-is-not-a-binding.md`
(an attempt cap does not bound elapsed time; charge apt-seconds); `2026-10-01-an-alert-guard-pinned-the-declaration-and-the-command-text-not-the-consumer.md`
(pin the consumer and the alert attributes, not the spelling); `2026-09-07-my-instruments-reported-green-while-measuring-nothing.md`
(run `c4-count-parity.test.sh` and T25 directly after any alert change); `2026-05-17-sentry-issue-alert-create-dedup-on-action-match-not-conditions.md`
(use an unused `frequency_minutes`); `2026-07-15-sentry-event-frequency-threshold-unreachable-and-data-source-scope-403.md`
(check the grouped count can reach the threshold: value 0 here); `2026-10-15-a-new-nonpaging-marker-moved-a-pin-in-a-suite-the-affected-gate-never-selects.md`
(adding a journal field can move a count pin in a suite `test-all.sh --affected` never selects).

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "implement the PR-B scope: the masked-dir-precreate alert" | Phase 1 (rule, tag, contract test, alert-reference, README) | mapped |
| 2 | "and the masks_missing=3 finding" | Diagnosis 1; Phase 2 (probe creates the masked set under guards, `masks_created`, `/tmp/.cs`) | mapped |
| 3 | "Keep #10455 open after merge (do NOT use Closes; use Ref)" | Phase 5 PR body: `Ref #10455`, `Ref #10548`, `Ref #10781` | mapped |
| 4 | "fix the deploy-script-tests CI failure ... find the root cause (fixture/stub/timeouts) and fix it, do not skip or loosen the test" | Diagnosis 2; Phase 3 | mapped |
| 5 | "re-check the Inngest GuardA check ... if green, note it and make no change" | Diagnosis 3; AC12 | mapped |
| 6 | "#10548 ... do not enable it ... just list the exact typed command for the operator in the PR body under a hand-off line" | Phase 5 hand-off line | mapped |
| 7 | "Self-pull diagnostics from Better Stack/Sentry/CI logs; do not ask the operator to fetch anything" | Research Insights (all data pulled) | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `dir_kind` tag on the emit | "the masked-dir-precreate alert" | asked (the alert is not triageable without it; CTO ruling) |
| Contract test for the rule | "the masked-dir-precreate alert" | asked (repo convention for every routed op) |
| Probe creates masked dirs, `/tmp/.cs`, `masks_created`, `masks_note` | "the masks_missing=3 finding" | asked (the fix for the finding) |
| Builder-vs-reality row, probe/builder set-equality parity | "the masks_missing=3 finding" | asked (guards the fix against hiding an app regression, CPO condition 1 / CTO Fork 5) |
| Shared apt lists + archives, visible apt tail | "find the root cause (fixture/stub/timeouts) and fix it" | asked |
| `scripts/masked-dir-alert-discoverability.sh` | "silent fallbacks must mirror to Sentry; observability-as-plan-quality-gate applies" (brief) | asked (hr-observability-as-plan-quality-gate needs a runnable no-ssh probe) |
| ADR-079 / ADR-188 addenda | "(ADR-236)" / "find the root cause" | inferred: the probe reverses a recorded decision and the apt helper changes a recorded design; `wg-architecture-decision-is-a-plan-deliverable` requires the record in this PR |
| Issue for the Slack wake path (ADR-260) | "the masked-dir-precreate alert" | inferred: CPO plan-time condition; the alert is email-only until that integration is verified, and no dedicated issue exists (only a checkbox in #10455) |

### Split Assessment

- Subsystems touched: 4 roots (`apps/web-platform/server` + `test`, `apps/web-platform/infra` incl. `infra/sentry` and `infra/lib`, `scripts`, `knowledge-base`) — below the 4-root + 25 file + 800 line thresholds jointly; planned files ~19, estimated changed lines ~700.
- Recommendation: single PR. The three code items share one review surface (sandbox observability) except the apt work, which shares no files with the rest. It stays in because the brief asks for one PR and #10781 is a tracked red; if review finds the apt change large, it splits cleanly along `apps/web-platform/infra/lib/apt-bounded.sh` + `apt-bounded.test.sh`.

## User-Brand Impact

- **If this lands broken, the user experiences:** a tenant's Claude Bash session in the shared container keeps a cross-tenant read channel (another tenant's peer-messaging sockets, session transcripts, CLI temp base with proxy credentials) unmasked with nobody paged; or, if the probe change misbehaves, root-owned or wrong-owner dirs under `/tmp` or `~/.claude` in the production container make the app's own session setup fail so the tenant sees Bash fail to start.
- **If this leaks, the user's workflow data is exposed via:** the `/tmp/cc-socks*` peer sockets, `~/.claude/projects` transcripts and `/tmp/.cs/<id>/claude-<uid>` persisted Bash output reachable from a sibling tenant's Bash, which is exactly the mask whose pre-create failure this PR starts alerting on (the alert and the probe do not add an exposure vector of their own).
- **Brand-survival threshold:** `single-user incident`
- **Threshold decision (challengeable):** the monitored failure is the tenant-isolation promise failing open for every later session in a container, and the probe change writes into the production container, so `aggregate pattern` understates it (CTO confirmed 2026-10-23, CPO accepted at plan time).

Per-artifact pairs for `soleur:engineering:review:user-impact-reviewer` (CPO condition 4: run it at review time):

1. Missing alert -> a failed `cc-socks` / `cc-socks-<uid>` mask lets a sibling Bash connect to another session's bridge socket.
2. Missing alert -> a failed `~/.claude/projects` mask lets a sibling read a transcript holding a proxy credential.
3. Missing alert -> a failed `/tmp/.cs` mask lets a sibling read persisted CLI output.
4. Probe `mkdir` as the wrong uid -> a root-owned dir the app cannot use; mitigated by the PID-1 uid guard (Guard 3).
5. Probe-created dirs hide an app-side regression that stops pre-creating -> mitigated by the builder-vs-reality row and set-equality parity (Guard 2); accepted residual below.

Accepted residuals (deepen-plan user-impact pass, recorded rather than silently scoped out):

- A post-creation swap of a masked dir for a symlink or file is seen only by the probe's `lstat` (journal-only, 15-minute cadence, CTO ruling D), because the app's recursive `mkdir` succeeds on an existing symlink-to-directory. The tenant's Bash cannot write `/tmp` or `~/.claude` (`allowWrite` is the workspace), so this needs a same-uid actor outside the sandbox; no alert route is added in this PR.
- One tenant's writable session tmp dir lives inside the shared 256 MB `/tmp` tmpfs; filling it makes later pre-creates fail with ENOSPC for every session in the container. The new alert then fires (desired, `extra.code` says ENOSPC) while the masks stay fail-open, the existing posture. Bounding per-session usage is the open #10455 item on per-session flooding and `--pids-limit`, not this PR.
- A persistent fault re-emails every `frequency_minutes` to the same inbox as the other rules; the runbook names the ack/resolve step. A group acknowledged for one kind does not silence the other two (three Sentry issues, one per kind).

CPO sign-off (plan time, 2026-10-23): ACCEPT, with conditions folded in: probe creation is journaled apart from production's (`masks_created`, verdict docs say the synthetic proves the namespace can mount over the dirs, not that the app created them); the alert acceptance is restated as the proven chain (Guard 1); a follow-up issue verifies the Slack wake path (Phase 5); `user-impact-reviewer` runs at review; the PR text must not claim "paged" (email-only until ADR-260's Slack path is verified) and must not imply the isolation gap closes (#10548 is untouched).

## Open Code-Review Overlap

None. 95 open `code-review` issues were searched for each of the 14 planned file paths; no body names any of them.

## Implementation Phases

Order is RED first (`cq-write-failing-tests-before`). Every new test below is written and seen red before its change.

### Phase 0 — RED tests and re-verification

0.1 Re-read GuardA state on `origin/main` and record the run id (AC12).
0.2 Write failing tests for Phases 1-3 (named per phase). Run each and confirm RED for the right reason.
0.3 Pick an unused `frequency_minutes` for the rule: `grep -h frequency_minutes apps/web-platform/infra/sentry/*.tf | sort -n`; at plan time 5 to 37 are taken in the files (38 is free; Sentry's POST-time dedup keys on action shape + `action_match` + `filter_match` + frequency, not conditions).

### Phase 1 — routed alert (P1)

1.1 `apps/web-platform/server/agent-runner-sandbox-config.ts`: the existing pre-create loop iterates three named
lists; iterate them with a local kind label instead of one flat array:
`[["peer-socket", peerSocketDirs], ["transcript", transcriptDirs], ["session-tmp", [AGENT_SESSION_TMP_ROOT]]]`.
**Emit on the MESSAGE path (deepen-plan P0, #8629 class).** `reportSilentFallback(err, ...)` with an `Error` first
runs `logger.error({ err })`, whose pino mirror (`server/logger.ts` `mirrorToSentry`, lines ~73-79) calls
`Sentry.captureException(err, { tags: { feature: "pino-mirror" } })`; Sentry then drops the second capture that
carries `feature`/`op`, so a tag-filtered rule could never match. Therefore the emit's first argument is the
LITERAL `null`: `reportSilentFallback(null, { feature: "agent-sandbox", op: "masked-dir-precreate", tags: { dir_kind: kind },
extra: { dir, code, syscall }, message })`, with the `mkdirSync` error's `code` and `syscall` read from the caught
error (the errno discriminator: EACCES, EEXIST for a file in the way, ENOSPC for a full tmpfs, EROFS, ENOTDIR) and
never passed as `err`. The `message` is a constant per kind that names the kind and no path, e.g.
`agent-sandbox: <kind> masked dir could not be created; its read-deny may not apply`, which gives three Sentry
issues, so an acknowledged benign `peer-socket` issue cannot silence a later `transcript` failure. Same pattern
already documented at `server/account-delete.ts` (~lines 273 and 314) and used by
`reportAnthropicCreditExhausted`. No new exported chokepoint (CTO ruling, plan review): the parity test calls
`peerMessagingSocketDirs()`, `sessionTranscriptDirs()` and `AGENT_SESSION_TMP_ROOT` directly. The `denyRead`
assembly is untouched (order pinned). Replace the stale comment "no dedicated alert routes it yet, #10455". Tag
values are a closed three-value set; never the raw path (env-derived, unbounded).
1.2 `apps/web-platform/infra/sentry/issue-alerts.tf`: new `resource "sentry_alert" "masked_dir_precreate_failed"`
(name `masked-dir-precreate-failed`), copied from `seccomp_remediation_failed` (the two-`tagged_event` shape
(`feature` + `op`) is in `sandbox_startup_failure`), carrying `monitor_ids = [data.sentry_project_issue_stream_monitor.web_platform.id]`: `trigger_conditions =
[{ event_frequency_count = { interval = "1h", value = 0 } }]`; one `action_filters` block, `logic_type = "all"`,
two `tagged_event` conditions (`feature eq agent-sandbox`, `op eq masked-dir-precreate`), email action
`issue_owners` + `fallthrough_type = "ActiveMembers"`; `lifecycle { ignore_changes = [environment] }`;
a header comment naming the grouping (`mkdirSync` throws, so `captureException` groups by stack + type; one
issue for all dirs, re-notified every `frequency_minutes` while it keeps firing; no per-dir fingerprint).
1.3 Derive `apps/web-platform/infra/sentry/alert-reference.json` LOCALLY in the work phase (a PR-required
generated artifact: deferring it to the `plan_pr` red round-trip is a merge blocker, not a follow-up). Route:
README "Adding or editing a rule" (`terraform init` with the R2 backend creds from `prd_terraform`, `terraform
plan -out`, `terraform show -json`, `jq -S --arg side tf -f tests/scripts/lib/sentry-alert-projection.jq`); if
CI is the proof (`sentry-alert-reference-gate.sh`), never the producer. The local `terraform show -json` route is
mandatory, not optional (a hand-written entry would fail only in CI). Update the `README.md`
counts (T25 pins the README strings ``**46 `sentry_alert` rules**`` and `(46 alert rules total)`; also 44 fully Terraform-owned, 43 in
`issue-alerts.tf`, and add the issue to the history list).
1.4 Create `apps/web-platform/test/sentry-masked-dir-precreate-alert-op-contract.test.ts`
(mirror of `sentry-no-text-block-alert-op-contract.test.ts`; Guard 1).
1.5 Extend `apps/web-platform/test/agent-sandbox-precreate-failure.test.ts` (keeps its mock of
`reportSilentFallback`): assert `feature === "agent-sandbox"`, `tags.dir_kind`, `extra.code` and that the first
argument is `null`, for each of the three kinds (force each to fail with a file as base), and the dir stays in
`denyRead`. Create `apps/web-platform/test/agent-sandbox-precreate-sentry-path.test.ts`: the same forced failure
over the REAL logger and the REAL `reportSilentFallback`, mocking only the Sentry SDK (spy on `captureMessage` and
`captureException`); assert `captureMessage` is called exactly once with tags `feature=agent-sandbox`,
`op=masked-dir-precreate` and the `dir_kind`, and that `captureException` is NOT called with
`feature=pino-mirror`. The mocked test cannot see the dedup defect; this one can.
1.6 Create `scripts/masked-dir-alert-discoverability.sh`: pure bash with grep/awk (about 20 lines; a vitest run
cannot be guaranteed inside Check 10's 15 s cap with `PATH=/usr/local/bin:/usr/bin:/bin` and no `node_modules`),
no credentials, and no logic the contract test has beyond three checks: (1) the literal op in a non-test file
under `apps/web-platform/server/`, (2) a live (uncommented) rule in `apps/web-platform/infra/sentry/*.tf`
carrying `feature` eq `agent-sandbox`, that op and an email action, (3) prints `MASKED_DIR_ALERT_PATH_OK`.

### Phase 2 — probe creates the masked set (P2)

2.1 `apps/web-platform/infra/lib/sdk-bash-probe.mjs` (plain ESM; the image has no TypeScript):

- `export const SESSION_TMP_ROOT = "/tmp/.cs"` and `export function precreateDirs(uid, home) { return [...maskedDirs(uid, home), SESSION_TMP_ROOT]; }`.
  `maskedDirs()` and the literal in `smokeSandboxConfig` stay (the `denyRead` order is pinned by
  `sdk-bash-probe-parity.test.ts`); the parity test additionally pins `SESSION_TMP_ROOT === AGENT_SESSION_TMP_ROOT`.
- `ensureMaskedDirs` is the ONLY producer of `masks_missing` and `masks_created` in runtime mode (CTO ruling).
  Remove `runtimeMaskedDirs` and the runtime branch's reliance on the injected `exists`; `planSmoke` stays pure
  (it returns the intended dir set and the mode, no I/O). Deploy mode keeps its own `mkdir` of `maskedDirs`.
  The sandbox config receives ALL `denyRead` entries in the builder's order whatever `ensureMaskedDirs` found,
  like production (which keeps an entry even when its pre-create failed), `/tmp/.cs` literal included. If a
  file or symlink at a deny landing makes bwrap error, the synthetic reports that error through the existing
  verdict mapping; production would hit it on every session, so a loud result is true to production. bwrap's
  behaviour for a tmpfs over a non-directory is unmeasured, so its test asserts only `masks_missing>0` and a
  verdict from the existing mapping.
- `ensureMaskedDirs({ dirs, uid, pid1, lstat, mkdir })` (pure, I/O injected; `lstat` everywhere, never `stat`).
  Guards, in this precedence: `uid_mismatch` (probe uid differs from PID 1's real uid, read from
  `/proc/1/status` `Uid:` first field, not `stat`) > `pid1_unreadable` > `pid1_env_unreadable` > `home_mismatch`
  > `env_divergence`. The first two stop ALL creation. `home_mismatch` / `pid1_env_unreadable`: PID 1's `HOME`
  (from `/proc/1/environ`, NUL-separated; readability in this image is unverified, so the unreadable fallback is
  mandatory) must equal the probe's `HOME` by exact string, both absolute. Hardening (CTO ruling E2: `/proc/1/environ`
  holds every app secret, so it is read narrowly): cap the read at 256 KiB and treat a hit cap as
  `pid1_env_unreadable` without parsing a partial entry; split on NUL and keep ONLY the exact names `HOME`,
  `CLAUDE_CONFIG_DIR`, `XDG_RUNTIME_DIR`, `CLAUDE_CODE_TMPDIR`, `TMPDIR`; keep `HOME`'s value only for the
  comparison and only a set-to-an-absolute-path boolean for the other four; discard every other entry at once;
  never log, return or interpolate any value (nothing from environ reaches the result JSON, `detail=` or stderr;
  a test seeds a sentinel secret in a fake PID-1 environ and asserts it never appears on stdout, stderr or in the
  JSON). `/etc/passwd` was considered and rejected: it answers the default HOME, not the HOME the app has. On mismatch refuse ONLY the HOME-derived
  dir (`${home}/.claude/projects`), count it missing, and still create the other three. `env_divergence` is
  informational and NOT counted missing: PID 1 has an absolute `CLAUDE_CONFIG_DIR`, `XDG_RUNTIME_DIR`,
  `CLAUDE_CODE_TMPDIR` or `TMPDIR`, bases the probe does not model (surfaces the accepted residual).
  Per dir: `lstat` first; absent -> `mkdir(dir, { recursive: true, mode: 0o700 })` (the production call; no
  chmod, no chown, never replace an existing non-directory); a `mkdir` error counts that dir as failed and does
  NOT stop the loop. A dir is **failed** iff, after the pass, it is not a real directory (symlink, file, other),
  or `st.uid !== uid`, or still absent. Mode is not asserted (a tmpfs mount masks whatever the bits; the CLI
  creates `~/.claude/projects` with its own umask). Returns `{ created, failed, note }`.
- `runSmoke` calls it before the existing scratch / SDK run; the result JSON gains `masks_created` and
  `masks_note` (runtime mode only; `masks_modes` was cut in plan review, CTO ruling).
- The `runSmoke` `masked_dir_precreate_failed` infra exit stays for deploy mode only; in runtime mode a failed
  create is data (`masks_missing`), not an infra error.

2.2 `apps/web-platform/infra/web-bash-synthetic.sh`: parse `masks_created` (`^[0-4]$`) and `masks_note` (whole-string
`case` match against the closed enum `uid_mismatch`, `pid1_unreadable`, `pid1_env_unreadable`, `home_mismatch`,
`env_divergence`, else `-`; never derived from errno text or a path, never fed to `detail=`; a test row with an
EMBEDDED newline such as `uid_mismatch` newline `forged=1` yields `-`, because command substitution strips only a
trailing newline), with the same guards as `masks_missing`; journal them after
`masks_missing=`. Keep the `prodtuple_partial` downgrade for `masks_missing > 0` only and the ping unchanged: a
run that says it created 3 of 4 dirs makes a claim, so the heartbeat is NOT withheld (CTO ruling D; withholding
would also be misread as a dead host). An old probe (apply lands before the release) emits no `masks_created`:
it must parse to `-` (test row). Update `web-bash-synthetic.test.sh` (mock results gain the fields).

2.3 Tests (names the existing rows that change): `apps/web-platform/test/sdk-bash-probe-runtime.test.ts` (the
`masksMissing: 3` rows near lines 120-124 and the source pins near lines 146-150 that require exactly one
`mkdirSync(` and the literal `for (const d of plan.mkdir)` line break and are rewritten to pin
`ensureMaskedDirs` as the single creation site); `sdk-bash-probe-parity.test.ts` (Guard 2: set equality built
from `peerMessagingSocketDirs()`, `sessionTranscriptDirs()` and `AGENT_SESSION_TMP_ROOT` under the controlled
env); `agent-sandbox-precreate-failure.test.ts` (builder-versus-reality row, Guard 2); the cases in Test
Scenarios.

2.4 Docs: `knowledge-base/engineering/operations/runbooks/canary-probe-set.md`: (a) the `masks_missing` /
`prodtuple_partial` paragraph near "consecutive_no_ping=<n>" and a decode row for `masks_created` and
`masks_note` (values `uid_mismatch`, `pid1_unreadable`, `pid1_env_unreadable`, `home_mismatch`, `env_divergence`;
check `masks_note` first); the reader is the person running the Better Stack Logs query
(`scripts/betterstack-query.sh --grep SOLEUR_WEB_BASH_SYNTHETIC`), because no rule matches the line; a
persistent `masks_missing>0` means expect a `masked-dir-precreate-failed` Sentry email on the next dispatch ONLY when the path is absent or a regular file (a symlink-to-directory or foreign-owned dir makes the app's recursive mkdir succeed, so only the journal line shows it); (b) an
alert-response section for the Sentry rule `masked-dir-precreate-failed`: decode by `dir_kind`
(`peer-socket` -> a sibling can reach another session's bridge socket; `transcript` -> a sibling can read a
transcript; `session-tmp` -> a sibling can read persisted CLI output), the existing fail-open posture stated
as such (the builder keeps the entry in `denyRead` and carries on), containment (redeploy through the existing `deploy` webhook, which starts a fresh container: a plain
restart keeps the writable layer, so `~/.claude/projects` survives it and only the tmpfs `/tmp` dirs reset; a
fault that persists after a redeploy needs a code fix), decode of `extra.code` (EACCES permissions, EEXIST a file in
the way, ENOSPC the 256 MB `/tmp` tmpfs is full, EROFS, ENOTDIR), and the sentence that the first probe run after a
container start hides the cold-start state, so an email proves the app's own pre-create failed, the ack/resolve step, and that a persistent fault re-notifies every
`frequency_minutes`; (c) the proof limits: the synthetic proves the namespace can mount over the dirs, not that
the app created them; the app's env subset is not modelled; after the first probe run the synthetic can no
longer observe a cold-start mkdir failure (the Sentry rule is the detector); probe-created dirs persist after a
revert and are harmless; the #10548 soak reads the DEPLOY-time ledger (`.sdk_bash_smoke.coverage`, read by
`scripts/followthroughs/sdk-bash-smoke-verdict-10548.sh`), whose semantics this PR does not change, so the soak
clock does not restart.

### Phase 3 — apt fixture root cause (P3)

3.1 `apps/web-platform/infra/lib/apt-bounded.sh`:

- `gd_apt_state_arm` also creates `lists/partial` and `archives/partial` under the state dir (before the
  existing `chmod -R a+rwX`), so apt's sandboxed download user can write them in a bind mount. The state dir
  is per suite (`$TMP/aptstate`), not shared across suites; containers of one suite run serially (verify in the
  work phase for every consumer; `git-data-cutover-access` is the one to check).
- Root-owned cache files: container root creates `lists/` and `archives/` content the host user cannot delete,
  and `gd_apt_state_arm` returns early when already armed; apt also chowns `lists/partial` and `archives/partial`
  to `_apt` with mode 0700 inside the container, so a non-root host user can fail to clean the state dir. The
  helper runs a container-side `chmod -R a+rwX "$dir"` on EVERY exit path of `gd_apt_install_bounded` (success and
  failure; GNU `chmod -R` does not follow symlinks met during traversal, so no `find ! -type l` is needed), with a
  unit check that the host can remove the state dir after a run. Check how each suite tears the state dir down
  today before relying on it (unverified at plan time).
- `gd_apt_install_bounded` passes the same `-o Dir::State::lists=/work/apt/lists -o Dir::Cache::archives=/work/apt/archives`
  on BOTH `update` and `install` (derived from `GD_APT_STATE_DIR`, not a second literal). `update` still runs in
  every container (a conditional GET; it proves the mirror is reachable). No budget, cap, backoff or rc contract
  changes, and no `Acquire::http::Timeout` is added (CTO ruling, plan review: unproven; never shipped here, see Corrections). The A1 regex `^install .*Acquire::Retries=5.* curl python3$` keeps matching if the new `-o` options are
  placed before `Acquire::Retries`; `--no-install-recommends` call sites (`sandbox-masked-proc-docker`,
  `cloud-init-inngest-provision-unit`) keep their argument order (test row).
- Fix the stale header sentence about apt's own timeouts to say what ships (none set; apt's 120 s default exceeds
  the 90 s attempt cap).
3.2 Surface the scrubbed apt tail: the 20-line credential-scrubbed tail the helper writes to stderr is not in the
CI output today (the failures show only the cause line), so a stalled phase is invisible. Make the consumer
suites' FIXTURE-FAIL / FAIL lines include it (scrubbed text only). Measure first which consumers drop it
(`git-data-ownership.test.sh`, `git-data-runcmd-rehearsal.test.sh`, `htpasswd-stdin.test.sh` print the cause
line from the container's stderr tail); touch only the consumers that drop it.
3.3 `apps/web-platform/infra/apt-bounded.test.sh`: rows in Guard 4; the stub `apt-get` simulates the cache from the
`Dir::State::lists` / `Dir::Cache::archives` paths in `-o` (network work only when the lists are empty and the
package is not in the archives dir), so the warm-run row can turn red. Run EVERY consumer suite (the helper is
also used by `sandbox-masked-proc-docker`, `cloud-init-inngest-provision-unit`, `git-data-cutover-access`,
`htpasswd-stdin`, `git-data-ownership`, `git-data-runcmd-rehearsal`), not only the three that went red; re-run the
A10 raw-apt census and S1 skipped-assertion ceilings unchanged. The measured cold run (102 s) exceeds the 90 s
attempt cap on a slow box, so one row covers a capped-then-resumed attempt (apt resumes from `partial/`).
Apt researcher result (deepen-plan, real docker runs on the digest-pinned image): (1) a missing `lists/partial` is
fatal for `update` (`E: List directory ... partial is missing`, exit 100) and a missing `archives/partial` is
fatal for `install`, so the arm-time creation of both is load-bearing; as root apt chowns `partial/` to its download
user with mode 700, which is the host-side cleanup hazard (so the container-side `chmod -R a+rwX` on every exit path
and the host-removal check stay); an untraversable ancestor only warns (`Download is performed unsandboxed`) and
exits 0. (2) `lists/lock` is root-owned 640 and four sequential runs across containers never conflicted
(concurrent containers untested, so the serial-containers precondition stays). (3) `Dir::State::status` is not
overridden, so dpkg state stays per container while the downloaded `.deb` files persist in the shared archives
dir. Still owed in the work phase: (4) what a `timeout -k` kill mid-download or mid-update leaves for the next
attempt (unmeasured); record the observed behavior in the PR body.
3.4 Record on #10781 (comment): root cause, the measured cold/warm pair, and the residual (a mirror outage during
the first container still fails closed; no mirror fail-over built; the two first-`update` stall signatures are
instrumented, not fixed). The PR body uses `Ref #10781`, never `Closes`: GitHub closes on merge unconditionally
and one green leg proves nothing for an intermittent failure. Close #10781 afterwards, by a comment citing three
consecutive green runs of the leg (`gh run list`), or leave it open with the new apt-tail evidence.

### Phase 4 — records

4.1 ADR-079: edit the 2026-10-22 addendum sentence "creates nothing outside its own scratch dirs in runtime mode"
in place to say it is superseded by a new `Addendum — 2026-10-23 (#10455 PR-B)` (and update its residual 1),
the new addendum at most about 10 lines: the runtime probe now creates the closed set `precreateDirs`, the
guards (PID-1 uid and HOME, create-only-when-absent, lstat/owner failure rule), `/tmp/.cs`, `masks_created` and
`masks_note`, and that the probe is now a production-affecting writer whose timer, if stopped, changes nothing the
app depends on (the app's own mkdir is idempotent).
4.2 ADR-188: a short `Amendment — 2026-10-23 (#10781)` (at most about 10 lines) under the 2026-10-01 amendment:
shared lists/archives, no timeout option added, no arm became skip-eligible, and that the shared apt state is
cross-container but only inside one suite run.
4.3 C4: before concluding "no change", grep the Sentry and Better Stack element descriptions (`model.c4` near
lines 473 and 913) for enumerations of sandbox alerts and add one clause if the new rule makes them stale; run
`plugins/soleur/test/c4-count-parity.test.sh` and the C4 vitest pair either way.

### Phase 5 — PR body and hand-off (not a deliverable of code)

The PR body (written at ship time) carries: `Ref #10455`, `Ref #10548`, `Ref #10781`, the
GuardA note ("green on main since run 39881599619; no change"), the diagnosis summary, the accepted residuals,
and this line:

> **Operator hand-off (#10548, not done in this PR; operator-typed per ADR-236):** after the soak reaches
> 2026-10-26 and the enable request in `knowledge-base/engineering/operations/runbooks/canary-probe-set.md`
> ("Enable request must contain") is complete, type `/soleur:flag-create agent-sandbox-unix-deny --flagsmith-only`
> (the agent first runs it with `--dry-run`), then `/soleur:flag-set-role agent-sandbox-unix-deny prd on`
> (dry-run first). Rollback owner types `/soleur:flag-set-role agent-sandbox-unix-deny prd off`.

Also at work time: file the Slack-wake-path verification issue (ADR-260, milestone `Post-MVP / Later`, re-evaluation
criterion: verified integration or a decision to drop email-only), referencing #10455 and #10548.

## Merge-time production effects (does merging THIS alone mutate production?)

Yes, three ways, all automatic on merge; the PR body's FIRST line states this (AC11):

1. `apply-sentry-infra.yml` (path `apps/web-platform/infra/sentry/**`) creates the new Sentry alert rule in the
   production org. Effect: a new email route to issue owners / ActiveMembers; no existing rule changes.
2. `apply-web-platform-infra.yml` (path `apps/web-platform/infra/**`; its `-target` list includes
   `terraform_data.web_bash_synthetic_install` and the `_web2` twin, whose `triggers_replace` hashes
   `web-bash-synthetic.sh`) re-delivers the synthetic script to the RUNNING web-1 and web-2 through the
   existing Terraform provisioners and re-enables the timer. Those resources `depends_on` the journald
   resources, which re-run only if their own triggers change. The previous merge's apply failed once on
   `journald_persistent` (a transient vector restart, recovered by an authorized `manual-rerun` dispatch); the
   same remedy applies. `host_scripts_content_hash` also changes; the image built from the same commit carries
   the matching hash, so the freshness check is consistent once the release deploys.
3. `web-platform-release.yml` (path `apps/web-platform/**`) builds and deploys the new image: the probe
   (`infra/lib/sdk-bash-probe.mjs`) and the builder change reach the production containers, which restarts them.
   A restart wipes `/tmp` (tmpfs), so the first synthetic run after it is the cold-container case this PR fixes.
   Three further consequences of this step: (i) the changed probe also runs in the release's deploy-mode canary
   gate, so a regression in it blocks the production deploy; (ii) the release restart ends live tenant sessions on
   both web hosts; (iii) the first write into a PRODUCTION container (the probe creating masked dirs) happens at the
   first synthetic tick after the new image is live, not at merge.

No new infrastructure is introduced (Phase 2.8 does not fire): the only Terraform addition is one `sentry_alert`
resource in the existing Sentry root; the host delivery path already exists. The apt change (`apt-bounded.sh`
and its tests) is CI-only and touches no host.

Rollback: revert the PR. The revert destroys the Sentry rule (check whether the destroy guard demands an
`[ack-destroy]` line in a commit body for an alert, as it does for monitors) and re-delivers the previous
synthetic script. The recipe is simulated in the work phase (a scratch worktree, `git revert --no-commit`, then
the gates the revert PR must pass) and written into the runbook, not trusted from this paragraph.

## Files to Edit

- `apps/web-platform/server/agent-runner-sandbox-config.ts`
- `apps/web-platform/infra/sentry/issue-alerts.tf`
- `apps/web-platform/infra/sentry/alert-reference.json`
- `apps/web-platform/infra/sentry/README.md`
- `apps/web-platform/infra/lib/sdk-bash-probe.mjs`
- `apps/web-platform/infra/web-bash-synthetic.sh`
- `apps/web-platform/infra/web-bash-synthetic.test.sh`
- `apps/web-platform/infra/lib/apt-bounded.sh`
- `apps/web-platform/infra/apt-bounded.test.sh`
- `apps/web-platform/test/agent-sandbox-precreate-failure.test.ts`
- `apps/web-platform/test/sdk-bash-probe-runtime.test.ts`
- `apps/web-platform/test/sdk-bash-probe-parity.test.ts`
- `knowledge-base/engineering/operations/runbooks/canary-probe-set.md`
- `knowledge-base/engineering/architecture/decisions/ADR-079-faithful-sandbox-canary-and-profile-redeploy-verification.md`
- `knowledge-base/engineering/architecture/decisions/ADR-188-a-transient-environment-decline-is-reachable-under-ci.md`
- conditional, only the ones that drop the apt tail (Phase 3.2): `apps/web-platform/infra/git-data-ownership.test.sh`, `apps/web-platform/infra/git-data-runcmd-rehearsal.test.sh`, `apps/web-platform/infra/htpasswd-stdin.test.sh`

## Files to Create

- `apps/web-platform/test/sentry-masked-dir-precreate-alert-op-contract.test.ts`
- `apps/web-platform/test/agent-sandbox-precreate-sentry-path.test.ts`
- `scripts/masked-dir-alert-discoverability.sh`

Glob/path check (`hr-when-a-plan-specifies-relative-paths-e-g`): every path above was verified present on
`origin/main` (edit list) or is under an existing directory (create list) with `git ls-files`/`ls` on 2026-10-23.

## Architecture Decision (ADR/C4)

### ADR

Amend ADR-079 (addendum 2026-10-23): reversal of the 2026-10-22 decision that the runtime probe creates
nothing outside its scratch dirs. Decision: it creates the closed set `precreateDirs(uid, home)` (4 dirs),
only in runtime mode, only when its uid equals PID 1's, only when absent, with production's own `mkdir` call.
Alternatives: B never-create (permanently partial coverage under alpha traffic), C create at boot (changes
production for a monitoring need and hides the builder's mkdir path). Amend ADR-188 (apt shared cache).
Both are tasks 4.1 and 4.2, not follow-ups.

### C4 views

No change. Checked against all three model files (`model.c4`, `views.c4`, `spec.c4`): (a) external human
actors: none added (operator and tenants already modeled); (b) external systems: Sentry (edges `webapp -> sentry`
at `model.c4:910` and `sentry -> founder` at `:913`, email via issue owners) and Better Stack (`:473`, the
synthetic's heartbeat) already modeled, no new vendor; the web-host synthetic delivery is modeled at `:708-709`;
(c) containers/data stores: none added; (d) actor-surface access relationships: unchanged (the probe and the
alert are internal to modeled containers). No element description is falsified: none mentions
`masks_missing` or the pre-create set. Work phase still runs `plugins/soleur/test/c4-count-parity.test.sh`
and the C4 tests (a new rule moves the T25 README count, not a modeled cardinality).

### Sequencing

Single PR; no soak-gated step.

## Observability

```yaml
liveness_signal:
  what: Sentry issue-alert rule masked-dir-precreate-failed (event-driven, healthy = no events) plus the per-host Better Stack heartbeat web_bash_synthetic whose journal line now carries masks_missing, masks_created and masks_note
  cadence: per event for the rule; every 15 minutes per web host for the synthetic
  alert_target: email to Sentry issue owners with ActiveMembers fallthrough (ops mailbox); Better Stack heartbeat email (email-only until the ADR-260 Slack path is verified)
  configured_in: apps/web-platform/infra/sentry/issue-alerts.tf; apps/web-platform/infra/web-bash-synthetic.service and web-bash-synthetic.timer; apps/web-platform/infra/web-probe.tf

error_reporting:
  destination: Sentry project web-platform via SENTRY_DSN (reportSilentFallback(null, ...) message path, tags feature=agent-sandbox op=masked-dir-precreate dir_kind=peer-socket|transcript|session-tmp, extra code and syscall and dir), mirrored to container stdout by pino
  fail_loud: the Sentry email on the first occurrence in an hour; the pino line "agent-sandbox: <kind> masked dir could not be created; its read-deny may not apply" in the container log

failure_modes:
  - mode: a masked dir cannot be pre-created in the app (one cross-tenant channel fails open)
    detection: in-surface emit from the dispatcher (reportSilentFallback(null, ...) in buildAgentSandboxConfig; layer 2 is the pino breadcrumb mirror and the tagged captureMessage goes direct, because passing an Error would be deduplicated behind the feature=pino-mirror capture); dir_kind discriminates which channel and extra.code (errno) which cause in one event
    alert_route: Sentry rule masked-dir-precreate-failed, email to issue owners (one Sentry issue per kind)
  - mode: the app stops pre-creating a dir (regression in the loop) while the probe has created it
    detection: builder-versus-reality unit row and probe/builder set-equality parity in CI, not a runtime signal (accepted residual: the probe hides it at runtime)
    alert_route: CI red on the PR (layer 6, workflow-run log)
  - mode: the synthetic cannot create or validate a masked dir (non-directory, foreign owner, uid mismatch, mkdir error)
    detection: journal line SOLEUR_WEB_BASH_SYNTHETIC with masks_missing greater than 0 and masks_note, shipped by Vector (layer 3 journald to Better Stack, SYSLOG_IDENTIFIER web-bash-synthetic is in the vector.toml allowlist), coverage=prodtuple_partial
    alert_route: informational only, no human is paged (CTO ruling D); the reader runs the runbook Better Stack Logs query; the app-side failure emails through the Sentry rule on the next dispatch (email only until ADR-260's Slack path is verified; nobody is paged)
  - mode: the apt fixture stalls or the shared budget is spent
    detection: GD_APT spent line, FIXTURE_APT_CAUSE line and the surfaced scrubbed apt tail in the suite output
    alert_route: red deploy-script-tests job (layer 6, workflow-run log and the infra-suite-logs artifact)

logs:
  where: Sentry event (rule and issue); Better Stack Logs source for the web hosts (journald, SYSLOG_IDENTIFIER=web-bash-synthetic) via scripts/betterstack-query.sh; CI artifact infra-suite-logs-N for the apt suites
  retention: Sentry org retention (unchanged by this PR); Better Stack hot window plus the S3 archive arm of betterstack-query.sh; CI artifact 14 days

discoverability_test:
  command: bash scripts/masked-dir-alert-discoverability.sh
  expected_output: MASKED_DIR_ALERT_PATH_OK
```

Layer note (`hr-observability-layer-citation`): the layer list is `observability-coverage-reviewer.md` "The
seven observability layers"; this block cites layers 2, 3 and 6. Affected-surface rule (§2.9.2): the agent
sandbox is a blind surface; the emit comes FROM the dispatcher, and one event's `dir_kind` plus the retained
`extra.dir` plus `extra.code` discriminate the competing causes (which channel, and EACCES vs EEXIST vs ENOSPC vs EROFS).
The offline discoverability command proves the committed emit-to-rule chain only; the live proof is the post-merge
`workflows/` read in Acceptance Criteria.

## Guard Contract

### Guard 1 — masked-dir-precreate alert chain

**Property.** Every code site that emits op `masked-dir-precreate` is routed by a live (uncommented) Sentry rule that filters `feature=agent-sandbox` AND that op and has an email action, and the emitted `dir_kind` is one of the three-value closed set.

**Assembly.** Emit sites are derived by walking `apps/web-platform/server/**` (non-test `.ts/.tsx/.mts`, any quote style, parser-based comment stripping) for a literal `op: "masked-dir-precreate"` inside its enclosing object; the rule is parsed from every `apps/web-platform/infra/sentry/*.tf` with HCL comments stripped; the kinds are the three literals in the loop and the single `reportSilentFallback` call in `buildAgentSandboxConfig`. The live half is the existing post-apply `scripts/sentry-alert-live-fidelity.sh` read and `scripts/sentry-alert-reference-gate.sh` against `alert-reference.json`. Three links proven, none by firing a production event: forced failure -> `reportSilentFallback` with the tags -> live rule -> email action. Not proven (accepted residual): Sentry's email delivery after the rule matches.

**Mutation matrix.**

| # | Mutation | Expected |
|---|---|---|
| 1 | Comment out the `sentry_alert "masked_dir_precreate_failed"` block | RED |
| 2 | Rename the op at the emit site (`"masked-dir-precreate"` -> `"masked-dir-precreate-x"`) so the derivation finds 0 sites (guard's own dispatch: a floor of >= 1 emit site) | RED |
| 3 | Add a second emit site in another `server/` file with the same op and `feature: "other"` after the compliant first | RED |
| 4 | Drop the `op` `tagged_event` (or the `feature` one) from the rule | RED |
| 5 | Remove the email action | RED |
| 6 | Emit `dir_kind` with a fourth value or the raw path | RED |
| 6b | Pass the caught `Error` as the first argument of `reportSilentFallback` instead of `null` (the pino-mirror dedup defect) | RED (contract test asserts the literal `null`; the real-path test sees `pino-mirror`) |
| 7 | Harness: disable the comment-strip step in the test helper; a fixture where the rule is commented out must then be seen as live, so the harness self-test row goes RED | RED |
| 8 | Must-PASS non-canonical: the same rule with conditions in the opposite order and a different `frequency_minutes` | GREEN |

**Anchor.** The test compares an emit-site-derived set against the `.tf`; both are editable in one diff, so it proves consistency. What outside the commit must move for a weakening to pass: `alert-reference.json` must match the plan (`sentry-alert-reference-gate.sh`, merge-base strict up-to-date) and the apply workflow's live-fidelity read compares the live rule to the plan.

### Guard 2 — probe/builder set parity and builder-versus-reality

**Property.** The set of directories the runtime probe creates equals, as a set, the set the production builder pre-creates under the default container env, and the builder really creates every member of its set on disk.

**Assembly.** Builder side: the loop's three named lists = `peerMessagingSocketDirs()` + `sessionTranscriptDirs()` + `AGENT_SESSION_TMP_ROOT`, called directly by the test (no exported chokepoint). Probe side: `precreateDirs(uid, home)` = `maskedDirs` + `SESSION_TMP_ROOT`, and `smokeSandboxConfig.denyRead` (order pinned). Controlled env for the comparison: `HOME` fixed, `XDG_RUNTIME_DIR`, `CLAUDE_CODE_TMPDIR`, `TMPDIR`, `CLAUDE_CONFIG_DIR` unset, fixed uid. Equality, not `arrayContaining` (today `sdk-bash-probe-parity.test.ts` uses `arrayContaining`). Reality side: `buildAgentSandboxConfig` run against a temp root with stubbed env creates every default-env dir.

**Mutation matrix.**

| # | Mutation | Expected |
|---|---|---|
| 1 | Drop `/tmp/.cs` from `precreateDirs` | RED |
| 2 | Drop `sessionTranscriptDirs` from the builder's set | RED |
| 3 | Add a fourth list (a new kind) to the builder after the compliant three, no probe edit | RED |
| 4 | Remove one list from the builder's mkdir loop (the dir is not on disk) | RED (builder-versus-reality row) |
| 5 | Guard's own dispatch: the controlled-env derivation returns an empty set (floor: exactly 4 members) | RED |
| 6 | Change `SESSION_TMP_ROOT` to another literal | RED (pinned to `AGENT_SESSION_TMP_ROOT`) |
| 7 | Harness: compare with `arrayContaining` instead of set equality | the superset fixture (probe creates one extra dir) goes GREEN, harness self-test RED |
| 8 | Must-PASS non-canonical: a different uid and HOME produce the same shape | GREEN |

### Guard 3 — probe mask-creation safety

**Property.** In runtime mode the probe creates a masked dir only when its uid equals PID 1's, only when the path is absent, with `mkdir` mode 0700 recursive, never chmod/chown/replace of an existing path, and never as root.

**Assembly.** `ensureMaskedDirs` is the only runtime-mode creation site (`plan.mkdir` seam in `runSmoke`); deploy mode keeps its own `mkdir` of `maskedDirs`. Failure rule: not a real directory (`lstat`), foreign `st.uid`, or still absent after the attempt.

**Mutation matrix.**

| # | Mutation | Expected |
|---|---|---|
| 1 | Remove the PID-1 uid comparison (create when uid differs) | RED |
| 2 | Add a `chmod` after `mkdir` | RED |
| 3 | `lstat` replaced by `stat` (a symlink counts as a directory) | RED |
| 4 | Stop the loop at the first failed dir (second dir not attempted) | RED |
| 4c | Read `/proc/1/environ` without the narrow filter (a sentinel secret in a fake PID-1 environ reaches stdout, stderr or the JSON) | RED |
| 4b | Drop the HOME comparison (create `~/.claude/projects` although PID 1's HOME differs, or `/proc/1/environ` is unreadable) | RED |
| 5 | Dispatch: `pid1Uid` reader returns `undefined` and creation still happens | RED |
| 6 | Add a fifth path to `precreateDirs` without a test row | RED (set-equality, Guard 2) |
| 7 | Must-PASS: a 0755 dir owned by the probe uid -> `masks_missing=0`; a foreign-owner dir and a symlink each -> `masks_missing>0` | GREEN / GREEN / RED as stated |

### Guard 4 — shared apt cache in the bounded helper

**Property.** Every apt cycle the helper runs uses the same shared lists and archives dirs on both `update` and `install`, so only the first container per package set pays package downloads, and no budget, cap or rc contract changed.

**Assembly.** `gd_apt_install_bounded` is the only apt call site (one `bash -c` pair); `gd_apt_state_arm` creates the dirs; ~8 consumer call sites across 6 suites go through the helper (raw-apt census A10 in `git-data-runcmd-rehearsal.test.sh`).

**Mutation matrix.**

| # | Mutation | Expected |
|---|---|---|
| 1 | Drop the `Dir::*` options from the `update` call | RED |
| 2 | Drop them from the `install` call | RED |
| 3 | Point `update` at a different lists dir than `install` | RED |
| 4 | Use per-container private dirs (warm run makes network calls again) | RED (warm/cold row: the stub counts fetches; second call must make zero) |
| 5 | `gd_apt_state_arm` stops creating `partial/` dirs | RED |
| 6 | Dispatch: the stub apt never runs (helper returns 0 without calling apt) | RED (call-count floor) |
| 7 | The shared state dir is not made world-writable after a call (root-owned cache files), so the host-side cleanup fails | RED (host-side cleanup row) |
| 8 | Stall injection: first fetch stalls, cap fires, retry succeeds, `spent` within budget — with shared dirs removed this row stays GREEN, so rows 1-4 carry the proof | GREEN |
| 9 | Must-PASS non-canonical: a state dir with a pre-existing `lists/` and a different budget | GREEN |

## Domain Review

**Domains relevant:** Engineering (CTO), Product (CPO, plan-time brand sign-off only; no UI surface)

### Engineering

**Status:** reviewed
**Assessment:** CTO (2026-10-23) ruled on six forks (Decision Classes) and confirmed `single-user incident`. Risks recorded: the probe mutates production state (bounded to 4 dirs, same uid and mode as production; the PID-1 uid guard is mandatory); after the first probe run the synthetic can no longer observe a cold-start mkdir failure, so the Sentry rule is the only detector and its contract test is a hard gate; alert noise is low and desired for a cross-tenant channel; a shared apt cache can carry a stale index or an interrupted attempt into later containers (bounded by `partial/`, atomic renames, the retry loop and a fresh `update` per container); no hot-path DB writes, no schema change.

### Product

**Status:** reviewed
**Assessment:** CPO sign-off: ACCEPT with four conditions, all folded in (User-Brand Impact). Product/UX Gate: tier NONE (no UI surface; no `components/**`, `app/**` file in the Files lists), so no wireframes or copy review.

## Acceptance Criteria

### Functional Requirements

- [ ] AC1. A forced `mkdirSync` failure for each of the three kinds reaches `reportSilentFallback` with `feature=agent-sandbox`, `op=masked-dir-precreate` and the right `dir_kind`, and the dir stays in `denyRead` (`agent-sandbox-precreate-failure.test.ts`).
- [ ] AC2. `sentry_alert.masked_dir_precreate_failed` exists with the two `tagged_event` filters, the `event_frequency_count` value 0 / 1h trigger, the email action and an unused `frequency_minutes`; `alert-reference.json` and the README counts (T25: 46 / 44 / 43) match the plan; `sentry-alert-reference-gate.sh` and the post-apply live-fidelity read are green on the PR's `plan_pr`/apply.
- [ ] AC3. `sentry-masked-dir-precreate-alert-op-contract.test.ts` passes and every Guard 1 mutation row turns it RED.
- [ ] AC4. In runtime mode the probe creates the missing members of `precreateDirs` (4 dirs, including `/tmp/.cs`) under the PID-1 uid guard; `masks_missing` counts only dirs that are not real directories, foreign-owned or still absent after the attempt; `masks_created` and `masks_note` are journaled with bounded charsets; the `prodtuple_partial` downgrade fires only for `masks_missing > 0`; deploy mode behavior is unchanged.
- [ ] AC5. Set-equality parity and the builder-versus-reality row exist and every Guard 2 / Guard 3 mutation row turns them RED.
- [ ] AC6. `apt-bounded.test.sh` proves shared `Dir::*` options on both calls, a warm second call with zero network fetches, `partial/` dirs after arm, a capped-then-resumed attempt, and host-side cleanup of root-owned cache files; every Guard 4 mutation row turns it RED.
- [ ] AC7. The three failing suites show the scrubbed apt tail in their failure output (measured for which consumers need the edit); every consumer suite of the helper (6) still passes; no budget value, attempt cap, skipped-assertion ceiling or fail-closed arm changed (diff shows none). Accepted wording: redundant apt cycles removed; a first-cycle mirror stall remains and fails closed.
- [ ] AC8. The cold-versus-warm pair (cold 102 s, warm 19 s on this box, healthy network) is recorded in the PR body as a cost measurement of the redundant cycles, not as evidence that the red is fixed.
- [ ] AC9. This PR's own `Infra Validation` `deploy-script-tests` legs are green, and the PR body uses `Ref #10781` (never `Closes`); #10781 gets a comment stating signature (a) addressed and signature (b) instrumented only.
- [ ] AC10. ADR-079 and ADR-188 addenda are in the diff; the runbook decodes the new journal fields and states the proof limits.
- [ ] AC11. PR body: its first line answers "does merging this alone mutate production" (Merge-time production effects); `Ref #10455`, `Ref #10548`, no `Closes #10455`/`#10548`; the hand-off line with the two typed commands; no sentence claims anyone was "paged"; the flag is not created or enabled. Verified with `gh pr view 10892 --json body`, not from memory.
- [ ] AC12. GuardA re-verified on a fresh read of `origin/main` and recorded in the PR body (run id, pin `v1.1.58`); no file changed for it.
- [ ] AC13. The Slack-wake-path verification issue exists (milestone `Post-MVP / Later`, references #10455 and #10548).

### Non-Functional Requirements

- [ ] The probe never runs `chmod`/`chown`, never creates as a uid other than PID 1's, and never follows a symlink (Guard 3).
- [ ] NFR register assessment (`soleur:architecture assess` against `knowledge-base/engineering/architecture/nfr-register.md`).

### Quality Gates

- [ ] `plugins/soleur/test/c4-count-parity.test.sh`, `apps/web-platform/scripts/sentry-monitors-audit.test.sh` (T25), the C4 vitest pair, `web-bash-synthetic.test.sh`, `apt-bounded.test.sh`, `sdk-bash-probe-*.test.ts`, `agent-sandbox-precreate-failure.test.ts` run directly (not only via `--affected`).
- [ ] `soleur:engineering:review:user-impact-reviewer` and `observability-coverage-reviewer` run at review.
- [ ] Preflight Check 10 on `bash scripts/masked-dir-alert-discoverability.sh` prints `MASKED_DIR_ALERT_PATH_OK` inside 15 s (the script is created in this PR, so the command exists in this PR's tree; run it once before the PR is marked ready).

### Post-merge (automated, run by the ship/postmerge skills; no operator step)

- [ ] The release deploy and both infra applies are green (`gh run list`); if `web_bash_synthetic_install` failed on a transient vector restart, re-dispatch with the documented `manual-rerun`.
- [ ] `doppler run -p soleur -c prd -- bash -c 'curl -s -H "Authorization: Bearer ${SENTRY_ISSUE_RO_TOKEN}" "https://jikigai-eu.sentry.io/api/0/organizations/jikigai-eu/workflows/?per_page=100"'` lists a workflow named `masked-dir-precreate-failed` with both `tagged_event` filters (the endpoint was read once at plan time: 47 workflows, `seccomp-remediation-failed` present).
- [ ] On each web host the post-deploy synthetic lines read `masks_missing=0` and `coverage=sdk_wrapper_shim_prodtuple` (query in Test Scenarios); `masks_created` is diagnostic only (it reads `4` on a fresh container, `3` after a plain restart because `~/.claude/projects` survives in the writable layer while the tmpfs `/tmp` dirs reset, then `0`; a real dispatch before the first tick lowers it). If it reads `masks_missing>0`, the diagnosis hypothesis is false: reopen with `masks_note`.

## Test Scenarios

- Given a cold container where none of the four dirs exist, when the runtime probe runs as PID 1's uid, then it creates all four (`masks_created=4`), `masks_missing=0`, `coverage=sdk_wrapper_shim_prodtuple` (unit; `sdk-bash-probe-runtime.test.ts` + `web-bash-synthetic.test.sh` seam).
- Given a 0755 dir owned by the probe uid, then `masks_missing=0` and the field reads `755` (unit).
- Given a foreign-owned dir, a symlink in place of a dir, or an unwritable parent, then `masks_missing>0` and `coverage=prodtuple_partial` (unit).
- Given the probe uid differs from PID 1's, then nothing is created and `masks_note=uid_mismatch` (unit).
- Given two runs in a row, then the second creates nothing (`masks_created=0`) and does not touch the existing dirs (idempotent, unit).
- Given the default env, then the builder's pre-create set equals the probe's create set and every member exists on disk after `buildAgentSandboxConfig` (unit, temp root).
- Given the rule is commented out, a filter is dropped, the email action is removed, or a second emit site appears, then the contract test is RED (unit).
- Given a warm apt state dir, then a second `gd_apt_install_bounded` for the same packages performs zero fetches; given a stalled first fetch, then the cap fires and the retry succeeds within budget (unit with a stub `apt-get`).
- Integration (`soleur:qa`): after merge, `doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh --since 1h --grep SOLEUR_WEB_BASH_SYNTHETIC --limit 20 | jq -r '.raw|fromjson|.message'` shows `masks_created=4` on a fresh container (`3` after a plain restart) and then `masks_created=0`, `masks_missing=0`, `coverage=prodtuple_partial` gone, and Sentry shows the live rule (`organizations/jikigai-eu/workflows/`).

## Encryption Posture

Skipped per plan Phase 2.11: this plan introduces no persistent data store and no new cross-component or network
connection. The only `.tf` addition is one `sentry_alert` rule inside the existing Sentry root (a notification
route, not a store); the probe writes empty directories on the container's own tmpfs and writable layer; the apt
cache lives in a per-suite CI temp dir that is destroyed with the runner. The Sentry and Better Stack edges already
exist and are unchanged.

## Precedent-diff (deepen-plan 4.4)

- Alert rule: precedent `seccomp_remediation_failed` (`issue-alerts.tf`, trigger `event_frequency_count` value 0 over 1h, email `issue_owners` + `ActiveMembers`, `ignore_changes = [environment]`) and the two-filter `feature` + `op` shape of `sandbox_startup_failure`. Differences: this rule carries both filters and omits the frozen `legacy_trigger_conditions`.
- Message-path emit: precedent `reportAnthropicCreditExhausted` (`server/anthropic-credit.ts`) and `server/account-delete.ts`; difference: the kind is in the message to get one Sentry issue per kind.
- Probe creation: precedent is the production `mkdirSync(dir, { recursive: true, mode: 0o700 })` in `buildAgentSandboxConfig`, reused verbatim; guards (PID-1 uid and HOME) are new and have no precedent in the repo.
- Shared apt state: precedent is the existing `GD_APT_STATE` host-owned dir mounted at `/work/apt`; the lock pattern is apt's own `lock` files in `archives/` and `lists/`, with containers of one suite run serially.

## Risks and Sharp Edges

- `deepen-plan` Phase 4.6 halts on an empty or unfilled `## User-Brand Impact` section or a missing threshold; this plan carries concrete artifacts and `single-user incident`.
- **Probe-created dirs hide an app-side regression at runtime** (accepted residual, CTO Fork 5): "create only when the app has not" is unobservable (race), so the rows in Guard 2 are the control. State it in the runbook.
- After the first probe run the synthetic cannot observe a cold-start mkdir failure; the Sentry rule is the only detector (CTO).
- The synthetic exec runs as the container's own user (ADR-079 residual 1); the guard compares to PID 1, so a future `-u root` creates nothing.
- The probe models only the default-env subset (`XDG_RUNTIME_DIR`, `CLAUDE_CODE_TMPDIR`, `TMPDIR` bases are not modelled); a green synthetic is no proof for those.
- Email delivery after a rule match is unproven by design (no production fire); the alert is email-only on the free tier until ADR-260's Slack path is verified.
- apt: a genuine mirror outage during the **first** container still fails closed (#8744 owns that); the shared cache is cumulative across package sets and root-owned on the bind mount (a local re-run needs the state dir removed by the same uid that created it; hosted runners are destroyed).
- Adding journal fields can move a count pin in a suite `test-all.sh --affected` never selects: run `web-bash-synthetic.test.sh` and `ci-deploy.test.sh` directly.
- `ignore_changes = [environment]` only: do not copy the `ignore_changes = all` of the frozen `sandbox_startup_failure` block.
- An ADR renumber is not involved (both are addenda to existing ADRs).

## Corrections (2026-10-23, review fixes; outcome unchanged, premises corrected)

- **`Acquire::http::Timeout` was never shipped.** `git log --all -S"Acquire::http::Timeout" -- apps scripts` returns nothing, so the plan's
  statements that "#9379 saw stalls with it set" and that it "was removed between #8744 and the shipped helper" were wrong. The #9379 issue says its
  stalls happened with NO `Acquire::*::Timeout` set. The decision stands (no apt timeout option is added) for a different reason: the bound is the 90 s
  per-attempt cap, which sits below apt's default 120 s HTTP timeout (unverified here; apt's config is absent on the dev box), and `Acquire::Retries`
  only helps fast failures. The Fork 3 ruling's "plus `Acquire::http::Timeout=20`" and Plan review A's "stalls were seen with it set" carry the same
  premise error (see `decision-challenges.md`).
- **`masks_created` by container state.** `4` on a fresh container (redeploy), `3` after a plain restart (`~/.claude/projects` survives in the writable
  layer; only the tmpfs `/tmp` dirs are recreated), `0` afterwards. Earlier wording that every restart produces a `4` line was wrong.
- **App-side alert wording.** The Sentry rule emails; it pages no one (Phase 3 observability row).
