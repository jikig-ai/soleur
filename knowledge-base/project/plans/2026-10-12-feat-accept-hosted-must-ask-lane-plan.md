---
title: "feat: accept the hosted must-ask lane (ADR-284) - finish the C9 limbs, re-time the soak, bound the inert window"
type: feat
date: 2026-10-12
slug: accept-hosted-must-ask-lane
branch: feat-one-shot-accept-must-ask-lane-10054
issue: 10054
closes: none
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# feat: accept the hosted must-ask lane (ADR-284) - finish the C9 limbs, re-time the soak, bound the inert window

Tracker: #10054 (stays open; this PR uses `Ref`, never `Closes`). Epic #9601, feature #9776, soak trackers #9976 (24 h) and #9776
(7 d). Draft PR #10101. ADR-284 stays `adopting` in this PR; see "Sequencing" for why the flip is a later, measured step.

## Overview

Item 1 of the remaining sequence of agent-security epic #9601: take the hosted must-ask lane (ADR-284) from `adopting` towards
`accepted` on measured evidence. The lane was inert in hosted sessions until the fix in #10072 (merge `dfb9e2dba5`, deployed by
release run 38223902738, `deploy` job finished 2026-10-12T08:38:33Z, `release-outcome` 08:39:06Z). Three strands:

- **(a) C9 limbs with no dev account.** Extend the real-SDK probe (`apps/web-platform/scripts/dev-probe-destroy-ask.ts`) to a
  non-owner member session and a prior batch grant that must still be gated (plus the `gh` families, CPO's family-coverage
  condition); capture the lane's pino line and Sentry event in-process; then self-pull Better Stack and Sentry for the lane's own
  telemetry with the channel proven live, allowlisted and in retention before any silence is read as absence.
- **(b) Re-time the soak.** #9976 (24 h) and #9776 (7 d) were timed from the earlier, inert shipment (#9977, deployed 2026-10-11
  10:44Z). Move both `earliest=` values to the fix deploy, record the measured numbers in the ADR-277 addendum (a dated soak-open pointer now,
  the numbers in the flip PR once the windows close), and flip ADR-284 only when the measurements support it.
- **(c) Bound the inert window.** Run the probe against the pre-fix tree under each SDK version the repo actually pinned (0.2.85,
  0.3.197, 0.3.284), then bisect released 0.3.x versions, so the draft user notice carries measured dates.

## Research Insights

**Premise validation (Phase 0.6).** Held: #10054, #9976, #9776, #9601, #9826, #9858, #9543, #9545, #4672, #4671, #9602, #9603,
#9851, #9955 are all OPEN (checked with `gh issue view`); `origin/main` is `67dec0d7c6` and contains `dfb9e2dba5`; the SDK pin is
still `0.3.284` and `git log dfb9e2dba5..origin/main` over `package.json`, `package-lock.json`, `agent-runner-sandbox-config.ts`
and `sandbox-hook.ts` is empty, so the post-fix soak start is the fix deploy and has not moved. Stale or sharpened by checking:
(1) the brief says "arm run 38223902738"; it is a `workflow_run` of Web Platform Release on `dfb9e2dba5`, all jobs green
(`deploy` 08:37:17-08:38:33Z, `live-verify` green). (2) The directive's `earliest=` values live in issue bodies, not the repo, so
no repo test can pin them. (3) The ADR-284 mechanism (a must-ask lane) is not in any ADR's rejected-alternatives table; this
plan does not change the mechanism. (4) An existing CI gate `apps/web-platform/scripts/sdk-bump-sandbox-gate.sh` (ci.yml
`lockfile-sync`) already forces a `sdk-bump-verified:` acknowledgement on any lockfile SDK change; the bisect must therefore never
touch the lockfile.

**Measured baselines taken while planning (self-pulled; counts only).**

- Sentry (org events API, prd, `statsPeriod=14d`): `op:hosted-destroy-ask`, `op:safe-bash-near-miss`,
  `op:destroy-classifier-near-miss` and even `feature:cc-permissions` all return 0 events. Positive control in the same session:
  an unfiltered 2-day query returns current events including release `web-platform@0.338.26+dfb9e2dba5` (the fix build) at
  2026-10-12T09:02Z and `feature:pino-mirror` events, so Sentry is live and the zero is a real zero for hosted Bash that reaches
  `canUseTool` and matches the lane's ops. Hosted ask volume is founder-only and tiny: expect zero natural asks in the soak.
- Better Stack: query role works (`doppler run -p soleur -c prd_terraform -- bash scripts/betterstack-query.sh`); the hot window
  (`remote()`) held only ~3 h of rows at planning time (oldest 2026-10-12 07:59Z), so any soak read must include the archive arm
  (the convenience flags do; raw SQL must write the `UNION ALL s3Cluster(primary, $BS_TABLE_S3)` itself). Source 2457081 reports
  90-day retention (runbook `betterstack-log-query.md`, re-read live in Phase 2). A bare `--grep destroy-ask` over 36 h returned
  rows from the inngest host (journald payloads mentioning the string): a bare grep is contaminated; every read must decode
  `.raw` and field-isolate (`CONTAINER_NAME = soleur-web-platform`, `source_kind = app_container`, `message.decision`).
- **Defect found by running the plan's own discoverability command once (2026-10-12):**
  `doppler run -p soleur -c prd_terraform -- bash scripts/followthroughs/hosted-destroy-ask-window-9776-24h.sh` exits 3 with
  `CANNOT ESTABLISH: SHAPE_DRIFT - 34 row(s) mention destroy-ask but none decodes as a lane row`. Decoding those 34 rows by
  `CONTAINER_NAME`, `SYSLOG_IDENTIFIER`, `host_name`, `source_kind` gives 34 of 34 = `(none) / doppler / soleur-inngest-prd /
  journald`: they are the Inngest host's journald copies of GitHub webhook event payloads that quote the string (issue and PR
  events on the trackers), not lane rows and not a shape drift. The shipped soak probe counts mentions over the whole result,
  so it will exit 3 on every sweep (and every tracker comment that quotes the marker, including the sweeper's own, adds rows):
  the 24 h and 7 d probes cannot reach a clean read. This is the "bare substring contaminated by another service" class
  (learning 2026-07-18) inside the shipped probe; Guard 2 fixes it by field-isolating the mention count to app-container rows.
- The app-container shipper keeps pino level >= 40 (`apps/web-platform/infra/vector.toml`, `app_container_warn_filter`); the
  lane's `destroy-ask*` lines are `log.warn` (40), so they ship. The `ci` Doppler config has no Sentry DSN and no Better Stack
  token (`doppler secrets -p soleur -c ci --only-names`), so a local probe run can never arrive in the production sinks: it can
  prove emission (in-process capture) and decode-compatibility, and nothing more. Arrival can only be observed from hosted-container
  traffic.

**Institutional learnings applied** (from `soleur:engineering:research:learnings-researcher`):
`2026-03-16-agent-sdk-spike-validation.md` (a pre-approved tool or an allow rule bypasses `canUseTool` silently: the mechanism
class of #10054); `2026-08-04-my-probe-passed-against-the-outage-it-was-built-to-detect.md` (a positive control must be
something only the new code can produce: the bisect controls are "pre-fix tree FAILS on 0.3.284" and "fixed tree PASSES");
`2026-08-20-the-channel-was-silent-on-the-path-it-was-built-for.md` (silence needs retention + allowlist + positive control);
`2026-07-18-betterstack-followthrough-probe-must-field-isolate-syslog-identifier.md` (no bare substring reads);
`2026-07-16-the-fix-for-an-inert-monitor-shipped-a-probe-that-could-never-fire.md` (prove the probe can fire);
`2026-06-05-followthrough-pr-body-prose-closes-keyword-autocloses-tracker.md` (PR body must not contain a closing keyword before
`#10054`, `#9776`, `#9976` or `#9601`); `2026-04-15-sdk-v0.2.80-zoderror-allow-shape.md` (an old SDK needs `updatedInput` echoed on
every allow branch; an option-shape error on an old SDK is non-evidence).

**Domain leaders consulted (Phase 2.5; details under `## Domain Review`).** CPO: zero asks is data about volume, not liveness;
acceptance on probe plus control, and say plainly that the soak did not exercise the lane. CLO: dates and counts add no new
Art. 33/34 consideration but carry a small-number rule and a "window start = production deploy of the first inert build" rule.
CTO: pin-first bisect with a sandbox-engaged preflight and repeat runs; do not CI-gate the live probe; defer a scheduled probe.

**Property List (Phase 0.6b).**

1. P1 - the lane is live against the real SDK for a non-owner member session and cannot be laundered by a prior batch grant.
2. P2 - the telemetry the soak reads is provably emitted, decodable by the soak probe, shipped (allowlist), retained, and an empty
   read is distinguishable from a dark channel.
3. P3 - each soak window measures only post-fix traffic.
4. P4 - the inert window is bounded by measurement, with production-deploy dates.
5. P5 - ADR status follows measured evidence; nothing public ships ahead of it.

**Cut List (Phase 0.6b).** Mechanism -> property -> what already covers it / why cut.

- A new CI job running the live probe -> P1 -> cut: needs an Anthropic key and a model call, is nondeterministic; the
  deterministic half already exists (`apps/web-platform/test/agent-runner-sandbox-config.test.ts` asserts
  `autoAllowBashIfSandboxed` is `false`; `sandbox-hook.test.ts` covers the hook) and `sdk-bump-sandbox-gate.sh` forces an
  acknowledgement on any SDK bump. A scheduled or on-bump probe is a deferral (tracked below), not this PR.
- A committed bisect driver script -> P4 -> cut: one-shot; the exact commands go in the post-mortem and the driver lives in the
  session scratchpad. (Committing it would also put an SDK-install helper next to production code for a question asked once.)
- A synthetic prod canary or a prod synthetic ask via the live-verify principal -> P2 -> cut from this PR: it is a production
  write, and `hr-menu-option-ack-not-prod-write-auth` makes that an explicit operator authorisation. Surfaced as an operator
  decision, with a deferral issue for the scheduled variant.
- A new Better Stack native alert or standing monitor for `destroy-ask` -> P2 -> cut: the two soak probes already are the
  recurrence alarm (ADR-096 pattern); one liveness arm is added to them instead (Guard 2).
- `PROBE_MUTATE` hook, `grant-terraform-destroy`, `member-nonautonomous` and the second live `gh` case -> P1 -> cut at plan review
  (2026-10-12): the grant limb cannot launder by design (the cache refuses destroy-capable heads), the lane-before-cache ordering is
  pinned by an existing vitest row, and each live case costs a model call; the pre-fix-tree control (Guard 1 M1) proves the harness can
  go red. Interim n=0 counts in ADR-277 -> P5 -> cut: they carry no information; final counts are recorded once, in the flip PR.
- Per-version release bisect of all ~140 releases -> P4 -> bounded: the three pinned versions answer the notice's question; the
  release-level bisect is capped (Phase 3) because the operator asked for it, but the notice date never depends on it.

## Research Reconciliation - Spec vs. Codebase

| Brief / ADR claim | Reality (checked) | Plan response |
|---|---|---|
| "Re-time the follow-through directives from the deploy of the fix (arm run 38223902738)" | Directive `earliest=` lives in the issue bodies of #9976 (`2026-10-12T11:00:00Z`) and #9776 (`2026-10-18T11:00:00Z`); nothing in the repo reads or checks it. The 24 h value is already due today, i.e. the sweeper could grade a window that is 2.4 h old | Phase 0 first action, via `gh issue edit`; verify by re-reading the body through the sweeper's own awk parse |
| "Query Better Stack ... verify the channel is allowlisted ... before reading silence as absence" | The shipped soak probe cannot be read at all: it exits 3 SHAPE_DRIFT on contaminated non-lane rows (measured above), i.e. its "channel" is not field-isolated | Guard 2 item (i): isolate the mention count and every liveness count to `CONTAINER_NAME = soleur-web-platform` rows |
| "7d soak numbers recorded in the ADR-277 addendum" | The 7 d wrapper (`hosted-destroy-ask-window-9776-7d.sh`) exits 2 NOT YET when there are zero ask rows, and only reaches "ACTION REQUIRED: record these numbers" when `TOTAL > 0`. With founder-only volume the sweeper would never prompt the recording or the flip | Guard 2: a liveness arm plus "7d elapsed with zero asks" -> exit 5 with the n=0 statement; an empty window with a dark channel -> exit 3 |
| ADR-284 "Post-merge verification ... on dev hosted" | There is no dev account and no deployed dev hosted instance; CLO advisory (2026-10-12) accepts real-SDK probe plus production lane telemetry as the substitute, recorded as a PROPOSED equivalence pending operator ratification | Record it in ADR-284 (one pointer in the counsel-review audit); do not claim "dev-hosted observation" |
| Post-mortem: "bisect the SDK 0.3.x versions" | The repo pinned 0.2.80 (#1182, 2026-03-27), 0.2.85 (#2284, 2026-04-15 to 2026-07-01), 0.3.197 (#5849, 2026-07-01) and 0.3.284 (#9236, 2026-09-29/30), with no intermediate pins after #5849 (`git log -G'claude-agent-sdk"' -- apps/web-platform/package.json`) | Tier 1: test the pins on the pre-fix tree; Tier 2: conditional, capped release-level bisect between adjacent pins that disagree |
| Post-mortem "#5849 shipped" | #5849 was also the bwrap `unshare()` P0 (ADR-079 / `sdk-bump-sandbox-gate.sh` header): the sandbox may not have been engaged for part of the window, which would make `autoAllowBashIfSandboxed` irrelevant for those builds | Sandbox-engaged preflight per run; a run with the sandbox not engaged is non-evidence (exit 3) |
| ADR-284 "The probe covers force-push, terraform destroy and `bash -lc`" | The classifier also has `gh repo delete` and `gh api -X DELETE .../git/refs/heads/<default>`; the probe has no `gh` case, and CPO wants every destroy family exercised | Add two `gh` cases (never run: answered Reject at the gate; `gh` is unauthenticated in the agent env) |

## Problem Statement / Motivation

The lane (ADR-284) is the only thing standing between a hosted autonomous session and a default-branch force-push or
`terraform destroy`. It has been verified once, against the owner path only, with the verdict recorded as a comment on an issue.
The acceptance conditions in ADR-284 (post-merge verification, 24 h and 7 d soak numbers, CPO3-R1) are open, the soak clocks
were started from an inert deploy, the soak probes cannot tell a quiet channel from a dark one, and the inert window's start is
still "between 2026-05-05 and 2026-09-29". A founder-facing notice with an unmeasured start date is not usable, and no public
security claim may ship ahead of its measured control (epic AC).

## Proposed Solution

### Sequencing (what can and cannot happen in this PR)

The fix deployed 2026-10-12T08:39Z, so the 24 h window closes 2026-10-13T08:40Z and the 7 d window 2026-10-19T08:40Z. Neither
can elapse inside this pipeline run. This PR therefore ships everything that does not need the elapsed window (probe extension,
decode compatibility, liveness arm, re-timed directives, a dated soak-open pointer, bounded inert window) and keeps ADR-284 at
`adopting`. The flip is a second, small PR opened when the 7 d tracker prompts (#9776 carries the directive; the Guard 2 change
makes it prompt even at zero asks): record the final counts, set `status: accepted`, sweep the status consumers
(`knowledge-base/INDEX.md`, the ADR-277 addendum, the counsel-review audit, the post-mortem), close #9776 and #9976 by hand. No
new tracking issue: #9776 and #9976 are the enrolled follow-throughs and already carry the directives.

### Acceptance criteria for the flip (CPO + CLO, 2026-10-12; stated now so "supports it" is not decided later)

1. Real-SDK probe `RESULT: PASS` on the deployed SDK/CLI stack covering owner, non-owner member, a stale batch grant present (still
   gated; with a live-grant control honoured in the same wiring) and the destroy families (git force-push, terraform destroy,
   `bash -lc` variant, `gh repo delete`; the second `gh` family and terraform-under-a-grant are covered by the classifier corpus and the
   cache unit row), with the control push reaching `canUseTool` and not asked, the output recorded verbatim with SDK version, bundled
   CLI version, the deployed `build_sha`, the probe's own commit and UTC time. The probe runs on the dev host, not in the hosted
   container; the ADR says so.
2. Emission proven in-process (pino line fields and Sentry event tags/extra, no command text) and the captured real line decodes
   in the soak probe's own jq path (the stored-shape decode was only ever measured on other rows).
3. The 24 h window shows no revert-threshold trip and the 7 d window no tune-threshold trip, recorded as counts with the
   small-number rule (any count under 5 is written as "under 5"), including an explicit "0 natural asks; the soak did not
   exercise the lane" statement when that is the measurement. Natural false-positive and abandon rates are recorded as
   "unmeasured, n=0" and CPO3-R3 stays open.
4. Channel proven live in the same window (allowlisted by the vector filter, in retention, archive arm returns rows, positive
   control rows present) so zero is a measured zero. If zero natural asks persist, the arrival of the destroy-ask line and the
   Sentry event in the production sinks is recorded as NOT OBSERVED, and the operator decides (see Operator decisions) whether
   in-process emission plus channel liveness is accepted as the substitute; the agent does not decide that.
5. No SDK, CLI or sandbox-option change landed between the fix deploy and the flip (else re-run the probe on the new build).

## Technical Considerations

### Phase 0 - Re-time the soak directives (first action; the 24 h value is already due)

Derive T0 from the run, not from memory: `gh run view 38223902738 --json jobs --jq '.jobs[]|select(.name=="release-outcome")|.completedAt'`
(measured 2026-10-12T08:39:06Z; `deploy` finished 08:38:33Z). Use `T0 = 2026-10-12T08:40:00Z` (rounded up to the minute, so the window
starts strictly after the fix serves). New values: 24 h `earliest=2026-10-13T08:40:00Z`, 7 d `earliest=2026-10-19T08:40:00Z`.

Commands (each tracker body is read, edited by exact line, written back, re-read):

```bash
S=/tmp/claude-1000/-data-git-repositories-jikig-ai-soleur/130353b7-db44-45e8-a4b4-ccbf83691bb3/scratchpad
for pair in "9976 2026-10-13T08:40:00Z" "9776 2026-10-19T08:40:00Z"; do
  set -- $pair
  gh issue view "$1" --json body --jq .body | tr -d '\r' > "$S/$1.body"         # CRLF would defeat the $ anchor below
  # Replace only the earliest= line inside the column-0 directive block; any other line is left byte-for-byte.
  sed -E "s/^([[:space:]]*earliest=)[0-9T:Z-]+$/\1$2/" "$S/$1.body" > "$S/$1.body.new"
  [ "$(diff "$S/$1.body" "$S/$1.body.new" | grep -c '^>')" = 1 ] || { echo "STOP: not exactly one changed line in #$1"; break; }
  [ "$(grep -c "^[[:space:]]*earliest=$2\$" "$S/$1.body.new")" = 1 ] || { echo "STOP: parsed value is not $2"; break; }
  gh issue edit "$1" --body-file "$S/$1.body.new"
done
```

The loop refuses to edit unless exactly one line changed and the new body parses to the intended value (a `diff` alone exits 1 on a
change and would not stop it). Verify through the sweeper's own parser (its awk anchors on a column-0 `<!-- soleur:followthrough`, skips fenced blocks, first
`earliest=` wins; `scripts/sweep-followthroughs.sh`): pipe each re-read body through the parse and assert the value. Then comment
on #9976, #9776 and #10054 with T0, the run id, the old and new values and the reason (the earlier clock started from the inert
#9977 deploy). The prose line in each body ("`earliest` was set before the deploy time was known; move it ...") is updated in the
same edit so the body does not contradict the directive. Do not use a closing keyword in any of these comments.

Also confirm no later build supersedes the fix deploy: `git log dfb9e2dba5..origin/main -- apps/web-platform/package.json
apps/web-platform/package-lock.json apps/web-platform/server/agent-runner-sandbox-config.ts apps/web-platform/server/sandbox-hook.ts`
(empty at planning time). If non-empty at work time, T0 moves to that deploy and the probe re-runs on it.

### Phase 1 - Extend the real-SDK probe (a)

Edit `apps/web-platform/scripts/dev-probe-destroy-ask.ts`; keep the harness shape (production `buildAgentQueryOptions` and
`createCanUseTool`, streaming-input prompt held open, every card answered Reject, throwaway workspace with a local bare `origin`).
Reviewed down (plan review 2026-10-12) to the cases that each answer an ask or a measured gap; the rest were cut.

1. **Throwaway `HOME`.** The probe currently hands the real `HOME` to git and the agent env. Set `process.env.HOME` to a directory
   under the throwaway base (outside the workspace) before building options: a build that runs the matrix inert can otherwise reach
   `~/.config/gh`, and the sandbox preflight below writes there.
2. **Case matrix.** The four existing owner cases are unchanged. New, with `variant` and `grant` fields on `Case`:
   - `member-force-push-default`: `deps.isOwner = false`, autonomous and acked as the owner cases. Expect the card with exactly
     `["Approve","Reject"]` and card text that does not name an owner (ADR-284: neutral, a member may approve) (ask 1 (i)).
   - `grant-live-control` (positive control for the grant mechanism): `bashApprovalCache = getBashApprovalCache("probe-user",
     "probe-grant")` with `.grant("npm run probe-noop")`, `bashAutonomous = false`, command `npm run probe-noop`. Preconditions asserted
     before the SDK call: `isBashCommandSafe(cmd) === false` and `cache.allow(cmd) === true`. Expect `canUseTool` reached for Bash and NO
     card (auto-approved via the batch cache). This proves a live grant is honoured in this exact wiring.
   - `grant-force-push-default` (ask 1 (ii)): same cache with `.grant("git push")` installed (a stale or forged grant, as in the
     existing unit row), `bashAutonomous = false`, command `git push --force origin main`. **The cache refuses destroy-capable
     heads by construction since #10072** (`batchGrantablePrefix` is null for `git push`, `terraform`, `gh`; `allow()` returns false),
     so `cache.allow(cmd)` is false here and the anti-vacuity precondition is `grant-live-control` passing in the same run, not a
     cache-would-approve check (that precondition would abort every run: plan review P0). Expect the Approve/Reject lane card. The
     claim is "still gated end to end with a grant present, by two independent layers"; the lane-before-cache ordering in isolation
     stays pinned by the existing vitest row `cache laundering: a prior git push or terraform batch grant does not cover the destroy forms`
     (`apps/web-platform/test/permission-callback-destroy-ask.test.ts`), which the work phase runs, not edits.
   - `gh-repo-delete` (`gh repo delete probe-owner/probe-repo --yes`), owner variant, expectCard true, answered Reject; `gh` has no
     credential in the allowlisted agent env and the throwaway `HOME` has no `gh` config, so a leak fails rather than deletes. The
     second `gh` family (`gh api -X DELETE .../git/refs/heads/<default>`) and `terraform` under a grant are covered by the classifier
     corpus and the cache unit row, not by another live model call (CPO asked for each family exercised "or the probe's equivalent").
3. **In-process Sentry capture (emission, not arrival).** Before importing the server modules, `Sentry.init` with a placeholder DSN
   and a custom `transport` that appends envelopes to an array (nothing leaves the process; no DSN is read from Doppler). Per
   destroy case assert one event with `tags.feature = "cc-permissions"`, `tags.op = "hosted-destroy-ask"`, `extra.ruleId` starting
   `hosted-destroy-ask:`, `extra.family`, `extra.isOwner` equal to the variant (so a mis-wired member variant reds), and an envelope
   containing neither the command text nor a branch name. The pino breadcrumb assertions of the first draft are dropped (the probe's
   ctx carries empty `repoOwner`/`repoName`, so `repo` would be asserted vacuously, and `approverRole` lives on outcome lines only).
4. **Decode-compat as a no-model mode.** `PROBE_DECODE_ONLY=1` skips the SDK entirely (no key needed beyond the existing guard):
   spawn one child `NODE_ENV=production bun -e` that imports the production logger and calls `logDestroyOutcome("rejected", match,
   false)` and `detectDestroyAsk` against a stub context, capture the JSON stdout line, wrap it in the stored shape the soak probe
   decodes (`{"raw":"<json of {message:<pino object>,CONTAINER_NAME:"soleur-web-platform"}>"}`, as measured on live rows), and run the
   soak probe against it through its `DESTROY_ASK_QUERY_SCRIPT` seam with dummy `BETTERSTACK_QUERY_*` values (the probe exits 3 without
   them; the `ci` config has none). Assert the probe's summary line counts it and that the real line has `level` 40. Limitation, stated: the
   wrapper is hand-built, so this proves the decoder reads the real pino object, not that Vector produces this wrapper; the Vector
   shape stays measured on live rows only (Phase 2).
5. **Sandbox-engaged preflight (Tier 1 of Phase 3 only).** `PROBE_PREFLIGHT=1` adds a case `sandbox-engaged-control` that tries a
   write outside the workspace (under the throwaway `HOME`) and removes it if it succeeded; success means the sandbox was not engaged
   and the run reports `CANT-RUN:sandbox-not-engaged` (exit 3). It is not in the default matrix (the control push reaching
   `canUseTool` already covers it there). `PROBE_ONLY` accepts a comma-separated list so a bisect run can name the preflight case and
   one destroy case, and it is mandatory on a pre-fix tree (the matrix executes real commands against the throwaway remote).
6. **Provenance on every line.** Every `PROBE` line and `RESULT` print the SDK version and `claudeCodeVersion` read from the resolved
   SDK `package.json`, so a recorded result names the stack it measured. Header comment updated: new cases, env variables, exit codes,
   and "a local run cannot arrive in the production sinks and runs on the dev host, not in the hosted container".

`PROBE_MUTATE` (a runtime hook that empties the classifier list) is cut: two reviewers asked for it to go, it needs `PROBE_UNSAFE`
because it lets a real force-push run, and the grant limb it was built for cannot launder by design (above). Its RED rows are replaced
by the pre-fix-tree control (M1) and the precondition and dispatch rows in Guard 1.

**Commands that run (live SDK, real model; estimated under USD 2 for the phase; actual spend to be read from result frames and
recorded, not asserted).**

```bash
cd /data/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-accept-must-ask-lane-10054
# 0. confirm the key works with one trivial call before the matrix (a credit error is CANT-RUN, never a result);
# 1. baseline on the deployed SDK, extended matrix, exit 0 = PASS:
NODE_ENV=test doppler run -p soleur -c ci -- bun run apps/web-platform/scripts/dev-probe-destroy-ask.ts
# 2. no-model decode-compat row:
PROBE_DECODE_ONLY=1 NODE_ENV=test bun run apps/web-platform/scripts/dev-probe-destroy-ask.ts
# 3. the deployed build the probe is being compared with (record both, they differ):
curl -s https://app.soleur.ai/health | jq -r .build_sha ; git rev-parse HEAD
```

Results are recorded verbatim (the `PROBE` lines and `RESULT`, plus SDK/CLI version, the DEPLOYED `build_sha` from `/health`, the probe's
own source commit and UTC time) in ADR-284's "C9 result" block, with filesystem paths redacted. A `MODEL-DID-NOT-TRY` verdict is exit 3
and non-evidence: re-run, never average it into a pass; stop after 3 consecutive exit 3 and report why.

### Phase 2 - Self-pull Better Stack and Sentry (a, second half)

All reads are by API with Doppler-injected credentials, run by the agent; no operator dashboard step. Output is recorded as
counts, rule ids and release strings only (CLO: no repo names, user ids, command text; any count under 5 written "under 5").

1. **Allowlist.** Quote the `app_container_warn_filter` condition from `apps/web-platform/infra/vector.toml` (keeps pino level >=
   40; `destroy-ask*` lines are `log.warn`) and show a stored real row passes: a Better Stack query for `CONTAINER_NAME =
   soleur-web-platform`, `source_kind = app_container`, decoded `.message.level >= 40` over the last hour returns > 0 rows (the
   positive control; at planning time the 30-minute count was 292 app-container rows).
2. **Retention.** `GET https://telemetry.betterstack.com/api/v2/sources/2457081` with `BETTERSTACK_API_TOKEN_READONLY` (prd_terraform)
   -> `logs_retention` (90 at last measurement); and an archive-arm read: a raw SQL `UNION ALL s3Cluster(primary, $BS_TABLE_S3)`
   count over a window older than the hot window returns rows. For Sentry: an events query over `statsPeriod=30d` returns events
   older than 7 days (retention covers the soak).
3. **Lane lines, Better Stack.** Decoded, field-isolated count of `message.decision` in
   `{destroy-ask, destroy-ask-approved, destroy-ask-rejected, destroy-ask-expired}` over the explicit window [T0, now] (`--since 2026-10-12T08:40:00Z`),
   recorded with its bounds. The sweeper's trailing windows (cron `0 18 * * *`) start at 18:00Z and skip the first hours after T0, so
   they are alarms, not the measurement; the final numbers come from explicit [T0, T0+24h] and [T0, T0+7d] reads.
4. **Lane events, Sentry.** `op:hosted-destroy-ask`, `op:destroy-classifier-error`, `op:destroy-classifier-near-miss`,
   `op:safe-bash-near-miss` since T0 using `SENTRY_API_TOKEN` (Discover scope; `SENTRY_ISSUE_RO_TOKEN` is issue-scope and 403s on
   the events endpoint) against `https://${SENTRY_API_HOST}/api/0/organizations/${SENTRY_ORG}/events/?dataset=errors`. Positive
   control: an unfiltered query returns events carrying release `web-platform@0.338.26+dfb9e2dba5`.
5. **Interpretation rule (written before the read).** Rows present -> record counts. Zero rows with every control green ->
   "0 natural asks in window W (hosted volume); arrival in the sinks NOT OBSERVED" (never "confirmed" and never "absent"). Zero
   rows with a control red -> channel dark, CANNOT ESTABLISH, escalate in the report.

### Phase 3 - Bound the inert window (c)

**Scratch tree, no repo mutation.** Build outside the feature worktree, in the session scratchpad. A detached scratch worktree of the
pre-fix commit replaces the first draft's `git archive` plus symlink farm (plan review: simpler, and its lockfile is not the feature
worktree's):

```bash
S=/tmp/claude-1000/-data-git-repositories-jikig-ai-soleur/130353b7-db44-45e8-a4b4-ccbf83691bb3/scratchpad/bisect
R=/data/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-accept-must-ask-lane-10054
git -C "$R" worktree add --detach "$S/prefix" dfb9e2dba5^          # PRE-FIX tree (autoAllowBashIfSandboxed true + hook allow)
cp "$R/apps/web-platform/scripts/dev-probe-destroy-ask.ts" "$S/prefix/apps/web-platform/scripts/"   # the extended probe (untracked there)
( cd "$S/prefix/apps/web-platform" && npm ci )                      # its own node_modules, its own lockfile copy
# per SDK version V (inside the scratch tree only; never in $R):
( cd "$S/prefix/apps/web-platform" && npm install --no-save --no-package-lock --ignore-scripts @anthropic-ai/claude-agent-sdk@"$V" )
```

Run each version as `cd "$S/prefix/apps/web-platform" && PROBE_PREFLIGHT=1 PROBE_ONLY=sandbox-engaged-control,force-push-default NODE_ENV=test
doppler run -p soleur -c ci -- bun run scripts/dev-probe-destroy-ask.ts`; parse the `PROBE` lines (a `PROBE_ONLY` run prints
DIAGNOSTIC and exit 4, so the verdict is read from the `verdict=` and `canUseToolCalls=` fields, never from the exit code). The
pre-fix tree runs real commands against the throwaway local remote (a `git push --force` really executes there: contained, which is
also why `PROBE_ONLY` is mandatory on it). Record `claudeCodeVersion` from the installed SDK `package.json` with each result.

**Tree invariants (assert before and after the phase, record the output).** In the FEATURE worktree: `git -C "$R" status --porcelain`
shows nothing new under `apps/web-platform/`; `git -C "$R" diff --quiet origin/main...HEAD -- apps/web-platform/package.json
apps/web-platform/package-lock.json` exits 0 (the `sdk-bump-sandbox-gate.sh` CI gate would otherwise demand an ack); and
`$R/apps/web-platform/node_modules/@anthropic-ai/claude-agent-sdk/package.json` still reads `0.3.284`. Cleanup: `git -C "$R" worktree
remove --force "$S/prefix"` and `git -C "$R" worktree prune`, after the results are copied into the post-mortem.

**Production-pinned versions (corrected by plan review).** `git log -G'claude-agent-sdk"' -- apps/web-platform/package.json`:
0.2.80 (#1182, 2026-03-27 to 2026-04-15), 0.2.85 (#2284, 2026-04-15 to 2026-07-01), 0.3.197 (#5849, 2026-07-01 to 2026-09-29),
0.3.284 (#9236, 2026-09-29 to now), with no intermediate pins after #5849. Production shipped no other version.

**Order and decision rule (each version twice; repeats guard model flakiness).**

1. **Controls first.** Pre-fix tree on SDK 0.3.284 must show `canUseToolCalls=[]` with `bashAttempted=true` (reproduces #10054; a
   signal only the buggy build produces) and the fixed tree on 0.3.284 must PASS (already shown; re-recorded in this harness). If
   either is wrong, stop: the harness is not trustworthy.
2. **Tier 1, the pins:** pre-fix tree on 0.2.85, 0.3.197 and 0.3.284 (0.2.80 only if 0.2.85 is inconclusive). Per version:
   *gate working* = both runs reach `canUseTool` for Bash and show a card for the destroy case; *inert* = both runs attempt Bash with
   zero `canUseTool` calls; *inconclusive* = anything else (option-shape error on an old SDK, sandbox not engaged, model did not try),
   exit 3, never counted either way.
3. **Code-side confound, per pin.** The scratch tree carries the code of 2026-10-11, not of the pin's era (the probe cannot run on the
   era trees: `agent-runner-query-options.ts` did not exist then). For each pin commit read the two causes directly:
   `git show <pin-commit>:apps/web-platform/server/agent-runner-sandbox-config.ts` and `.../sandbox-hook.ts`, and record that both were
   present on that date (`git log -S'autoAllowBashIfSandboxed'` dates the first to 2026-03-20, #871).
4. **Tier 2 (asked for; conditional and capped).** Only if Tier 1 yields a measured boundary between two adjacent pins, bisect the
   released versions between them (`npm view @anthropic-ai/claude-agent-sdk versions --json`; dates from `npm view ... time --json`)
   with at most 6 distinct versions x 2 runs, to name the SDK release for the record; verify both neighbours of the boundary twice. If a
   later version behaves differently from an earlier inert one the behaviour is non-monotonic: stop and report the table. Reviewers
   (DHH, simplicity, CTO, spec-flow) asked to cut Tier 2 because the notice date depends only on the pins; the operator's brief asks for
   the 0.3.x bisect, so it stays but never gates the notice (decision-challenges.md).
5. **If Tier 1 cannot measure the start** (0.2.85 and 0.2.80 inconclusive on today's code and no boundary): the production fact #3252
   (closed 2026-05-05: Command Center Bash prompting on SDK 0.2.85 with both causes already in the code) is the only evidence of a
   working gate; the notice then says "between 2026-05-05 and <deploy of the first measured-inert pin>", never a single start. That
   fallback wording is composed by the CLO agent in Phase 5; it is not this plan's text.
6. **From version to date (CLO).** The notice's start is the PRODUCTION DEPLOY of the first inert build, not a release or merge date: for
   the #5849 pin, the release containing `48b13c1f2e` (tag `web-v0.172.1`, 2026-07-01T13:20:50Z) and that release's `Web Platform
   Release` run `deploy` job `completedAt`; for the #9236 pin, `web-v0.312.7` (2026-09-29T22:02Z) and its deploy run. End: the fix
   deploy (`deploy` job 2026-10-12T08:38:33Z, `/health` build_sha `dfb9e2dba5`). Where a pin merge was rolled back or not deployed, say so.

Estimated cost: 3 pins + 2 controls = 5 versions x 2 runs x about USD 0.05-0.20; Tier 2 at most 12 more runs. Estimate only; actual spend is read from the `result` frames and recorded. Stop after 3 consecutive exit 3 (credit or model failures) and report.

### Phase 4 - Guard 2: soak-probe isolation and liveness (the shipped probe cannot be read; justified in Scope Check)

Edit `scripts/followthroughs/hosted-destroy-ask-window-9776.sh` and its `.test.sh`:

- **(i) Field-isolate the decode and mention counts, not the truncation count.** `MENTIONS`, `DECODABLE` and the `ROWS` lane-row decode
  are computed over the whole result, so the 34 Inngest-host `doppler` journald rows that quote the marker (measured above) trip
  SHAPE_DRIFT, and a canary or Inngest row carrying `decision=destroy-ask*` would count as an ask. Restrict all three to rows whose
  decoded `.raw` has `CONTAINER_NAME == "soleur-web-platform"` (the app container; the canary `soleur-web-platform-canary` does not
  serve users, stated inline in the script). Keep `OUT_LINES >= ROW_LIMIT` on the RAW line count: contaminating rows fill the 5000-row
  limit before isolation, so an isolated count would let truncation evict real lane rows unnoticed (plan review, architecture HIGH).
  One predicate definition, three uses. The sweeper's own comment text (it quotes `hosted destroy-ask window`) and every tracker
  comment also reach the Inngest journal; isolation, not wording, is the fix.
- **(ii) Liveness arm (both windows).** After the main read and before reporting "no asks", one more query over the SAME window and
  both arms (hot + archive): the count of app-container pino rows with level >= 40. The convenience flags cannot express a
  container or level filter, so this is one raw-SQL call through the same query script (`$BS_TABLE` and `$BS_TABLE_S3` tokens, the
  `UNION ALL s3Cluster(primary, ...)` written out; the earlier statement that every soak read uses the convenience flags is corrected
  here). The `DESTROY_ASK_QUERY_SCRIPT` test seam therefore dispatches on its first argument: a stub that answers `--since ... --grep`
  with rows and a `SELECT` with a count. Zero -> `CANNOT ESTABLISH` (exit 3). A positive count proves the CHANNEL, not the lane: after an
  SDK bump that re-inerts the lane, a green liveness arm plus zero asks still reads as quiet; the dev probe is the lane's liveness check
  and the sdk-bump gate forces its re-run (stated in the probe's output).
- **(iii) 7 d zero-ask rule.** With the liveness arm green and `ASKS = 0`, the 7 d window exits 5 with "7 d elapsed; 0 natural asks;
  the soak did not exercise the lane; open the flip PR per ADR-284 'Flip checklist' and record this", instead of 2 NOT YET forever. The
  24 h window keeps exit 2 at zero asks and prints `NOT YET: no 24h revert threshold tripped.` (the string T1 checks).
- The wrappers and the `run_suite` row need no new wiring; `secrets=` is unchanged. Public output stays counts only.

### Phase 5 - Records (knowledge-base; CLO-reviewed wording)

- `knowledge-base/engineering/operations/post-mortems/2026-10-11-hosted-bash-ask-bypassed-by-sdk-auto-allow-postmortem.md`:
  replace "Window (bounds, not measured)" with the measured table, the exact bisect commands in a fenced block (so the next SDK-bump
  re-run is copyable) and dates; frontmatter `recovery_at: 2026-10-12T08:38:33Z` and `incident_window` updated; `status` stays a
  not-yet-resolved value (`fix-deployed-notice-and-register-decisions-pending`) until the operator decides the notice and the
  breach-register row; `art_33_triggered` unchanged. The draft notice gets only the CLO-pre-cleared edit (the bracketed deploy date;
  "began on <measured date>" replacing "no later than 29 Sep 2026 and possibly earlier; we are determining the start"); the
  fallback wording of Phase 3 item 5 and any other change go back to the CLO agent first. The notice stays a DRAFT; publication is the
  operator's. Action-item rows get statuses, none are removed.
- `ADR-284-...md`: "C9 result" extended with the measured limbs and "When that began is not measured" replaced by the measured bound.
  The dev-hosted observation is replaced by the real-SDK probe plus production lane telemetry, written as **"proposed equivalence,
  pending operator ratification"** (the CLO advisory is internal, not external counsel). Add a `## Flip checklist`: the five flip
  criteria, then the flip PR's own work (record final counts; `status: accepted` in frontmatter and `## Status`; sweep
  `knowledge-base/INDEX.md`, ADR-277 addendum, counsel-review audit, post-mortem and `knowledge-base/legal/` for future-tense sentences
  about the lane; retire the soak probe family together as its header says (the `.sh`, `-24h.sh`, `-7d.sh`, `.test.sh`, the `run_suite`
  row, both directives); close #9776 and #9976 and REMOVE their `follow-through` label so the closed-set sweep stops re-running the
  probe). The Status block carries, in the same sentence as the status: "arrival of the lane's lines in production sinks NOT OBSERVED;
  member approval never observed; revisit at the first multi-member workspace or first external founder". Frontmatter and `## Status`
  stay `adopting` in this PR.
- `ADR-277-...md` addendum: no interim counts (a few hours at n=0 carry no information; the final numbers are recorded once, in the
  flip PR). Replace "**Measured numbers: not yet recorded.**" with a dated pointer: "soak open: 24 h window closes 2026-10-13T08:40Z, 7 d
  window 2026-10-19T08:40Z; numbers recorded by the flip PR (ADR-284 Flip checklist)", with conditional wording for anything that only
  becomes true when this PR merges. The Phase 2 readouts live in ADR-284's C9 block and the post-mortem instead. No "verified" wording.
- `knowledge-base/legal/audits/2026-10-counsel-review-9776-ask-gate.md`: one line on the C9 disposition pointing to ADR-284's C9 block
  for the proposed equivalence (composed via the CLO agent); the determination is not repeated in four files.

### Phase 6 - Deferrals

One new GitHub issue (milestone "Phase 4: Validate + Scale", labels `domain/engineering`, `type/chore`, `priority/p2-medium`):
"scheduled real-SDK probe on SDK bump plus a synthetic hosted ask canary", with re-evaluation criteria (any SDK/CLI/sandbox-option
bump; first multi-member workspace; first external founder) and a note that the synthetic canary is a production write needing
explicit authorisation. Referenced from the ADR-284 Status block. (Per CTO and `soleur:schedule` as the mechanism.)

## Known open risks (kept visible; not fixed here)

| Risk | Disposition |
|---|---|
| Legacy domain-leader runner (`agent-runner.ts`) asks on every non-safe Bash, no autonomous toggle, no batch cache | Already row 4 of the post-mortem action table on #10054; wiring those deps is separate work; recorded in ADR-284 "Coverage by conversation type". Revisit trigger: complaint or first member workspace |
| File tools still get a hook `allow`, so their `canUseTool` branch is unreached (ADR-284 residual) | Residual stays named in ADR-284; the file-path deny lives in the hook and `disallowedTools`; not touched |
| Approve card per non-safe Bash in non-autonomous workspaces (approve-fatigue; rebase-and-force-push workflows meet the card on every push; workflows that ran unprompted now stall) | CPO: record as medium open risk; no friction figure is claimed (unmeasured, n=0); revisit at the first multi-member workspace or first external founder |
| Bisect may be non-monotonic or an old SDK may reject current options | Per-run sandbox preflight, exit 3 is non-evidence, no single boundary is stated if behaviour is non-monotonic |
| Arrival in the production sinks may never be observed from natural traffic | Operator decision below; the plan states NOT OBSERVED rather than inferring it |
| The sweeper reads trailing windows from main at 18:00Z; this PR's Guard 2 fix must be merged before the first read or that comment is exit 3 noise | AC1 names the deadline (2026-10-13T18:00Z for the 24 h read); merge needs the operator's go-ahead, so the PR body states it; explicit [T0, T0+N] reads, not sweeper comments, are the measurement |
| The probe runs on the dev host (host bwrap), not in the hosted container where the sandbox has failed before (the `/proc` EPERM incident) | Stated in the probe header and ADR-284; "deployed" means the same SDK, CLI and option builder; recorded identity is the deployed `build_sha` from `/health` plus the probe's commit |
| The flip depends on someone picking up the 7 d tracker comment | The 7 d probe's exit-5 text names the flip checklist; `T2` states an owner and what happens if decision 3 is unanswered; the deferral issue keeps the follow-up visible |

## User-Brand Impact

- **If this lands broken, the user experiences:** a hosted workspace's default branch or infrastructure destroyed with no Approve
  card because a measurement said the lane was live when it was not (a probe that passes against the wrong stack, a soak read from
  an inert-era window, or a dark channel read as a clean week), or a published notice carrying a wrong inert-window start date.
- **If this leaks, the user's workflow is exposed via:** soak and probe output that echoes repo names, command text or approver
  counts small enough to identify a person into a public issue comment or the public knowledge-base (the soak probe prints counts
  and rule ids only; Phase 2 and Phase 5 apply the under-5 rule; no `repo`, `userId` or command is recorded).
- **Brand-survival threshold:** `single-user incident`
- **Threshold decision (challengeable):** inherited from ADR-284 (CPO third pass): one founder losing a default branch's history
  while the product says their work is backed up is brand-ending at current scale; the "aggregate pattern" tier is not chosen
  because a single workspace is enough.

`requires_cpo_signoff: true` is set. CPO advisory (2026-10-12, Phase 2.5, below) is the plan-time input; the acceptance criteria
above carry its conditions. `soleur:engineering:review:user-impact-reviewer` runs at review time.

## Observability

Production code is not edited (the lane and its telemetry already shipped); the deliverable is the measurement apparatus and the
telemetry readout, so the section describes how the lane's own signal is made discoverable without SSH.

```yaml
liveness_signal:
  what: "Hosted destroy-ask soak probes (24h and 7d wrappers) plus the real-SDK dev probe; the dev probe is the lane's liveness check, the soak probes are its recurrence alarm"
  cadence: "sweeper daily after earliest (2026-10-13T08:40Z and 2026-10-19T08:40Z); dev probe on every SDK, CLI or sandbox-option bump"
  alert_target: "tracker issue comments on #9976 and #9776 (exit 5 ACTION REQUIRED, exit 3 CANNOT ESTABLISH); sdk-bump-sandbox-gate.sh blocks the PR on an SDK bump"
  configured_in: "scripts/followthroughs/hosted-destroy-ask-window-9776.sh; .github/workflows/scheduled-followthrough-sweeper.yml; apps/web-platform/scripts/dev-probe-destroy-ask.ts"

error_reporting:
  destination: "Sentry project web-platform (feature cc-permissions; ops hosted-destroy-ask, destroy-classifier-error, destroy-classifier-near-miss); Better Stack source 2457081 for the pino decision lines"
  fail_loud: "exit 3 CANNOT ESTABLISH on a dark channel, truncated result, shape drift or outcome lines without ask lines; Sentry destroy-classifier-error is a revert-or-fix-inside-24h trigger"

failure_modes:
  - mode: "channel dark or allowlist moved (empty read mistaken for a clean window)"
    detection: "Guard 2 liveness arm: zero app-container pino level>=40 rows in the window -> exit 3"
    alert_route: "sweeper comment on #9976 / #9776 (counts only)"
  - mode: "stored-row shape drift (lane rows exist but do not decode)"
    detection: "existing SHAPE_DRIFT check in the soak probe, now also exercised by a real-line decode row"
    alert_route: "sweeper comment, exit 3"
  - mode: "SDK, CLI or sandbox-option bump silently re-inerts the gate"
    detection: "sdk-bump-sandbox-gate.sh requires the sdk-bump-verified token; the dev probe re-run is the measurement; deferral issue tracks a scheduled run"
    alert_route: "required CI check on the bump PR"
  - mode: "soak clock started from the wrong deploy"
    detection: "Phase 0 re-read of the directive through the sweeper parser; AC compares to the run's release-outcome time"
    alert_route: "work-phase gate before the PR is marked ready"

logs:
  where: "Better Stack source soleur-inngest-vector-prd (id 2457081), table via scripts/betterstack-query.sh; Sentry web-platform"
  retention: "Better Stack 90 days (logs_retention, re-read in Phase 2); hot window about 3 hours, the rest in the archive arm; Sentry retention measured by an events query older than 7 days"

discoverability_test:
  command: bash scripts/followthroughs/hosted-destroy-ask-window-9776-24h.sh
  expected_output: "hosted destroy-ask window 24h"
  credentials_required: "Doppler prd_terraform BETTERSTACK_QUERY_HOST/USERNAME/PASSWORD - stored log rows are readable only with the ClickHouse connection credential; no unauthenticated probe reads the same stored rows (run as: doppler run -p soleur -c prd_terraform -- bash scripts/followthroughs/hosted-destroy-ask-window-9776-24h.sh)"
```

Affected-surface note (blind execution surface): the lane runs inside the hosted container, which this plan cannot inspect
directly; the in-process capture (Phase 1 item 2) is the in-surface probe for emission, and its structured fields discriminate
the competing hypotheses in one event (rule id, family, `isOwner`, `approverRole`, no command text). Better Stack and Sentry
queries are self-pulled with Doppler-injected credentials (`hr-no-dashboard-eyeball-pull-data-yourself`); no step asks the
operator to fetch or eyeball anything. Layer citation (`hr-observability-layer-citation`): Better Stack (container log layer) and
Sentry (event layer); not the plugin/self-hosted layer.

## Architecture Decision (ADR/C4)

Not applicable as a new decision: this plan makes no architectural decision. It amends ADR-284 (C9 result, measured window,
status stays `adopting`) and the ADR-277 addendum (a dated soak-open pointer), both listed as in-scope tasks above, not deferred. C4:
no element, relationship or access path changes (the lane, its telemetry and the sandbox are unchanged); a "no C4 impact"
conclusion is valid because the change touches no external actor, no vendor edge and no data store, and no derived cardinality
in `model.c4` moves (re-run `plugins/soleur/test/c4-count-parity.test.sh` in the work phase to confirm).

## Domain Review

**Domains relevant:** Engineering (CTO), Product (CPO), Legal (CLO)

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Plan sound, risk low-medium. Add a per-version sandbox-engaged preflight and record the CLI version (the bundled
CLI is bisected implicitly); run each version twice; test the pins first and bisect only if needed; assert the grant control is
live (`cache.allow`) and that the destroy form is asked while the grant is live. Do not CI-gate the live probe (API-keyed,
nondeterministic); the deterministic subset exists. Defer a scheduled or on-bump probe and a synthetic canary as an issue.
Label in-process capture as such; never claim sink arrival from it. All adopted above.

### Product (CPO)

**Status:** reviewed
**Assessment:** Zero asks measures volume, not liveness. Acceptable `accepted` flip: probe PASS across owner, member and batch
grant; every destroy family exercised on the deployed build (probe equivalent acceptable); soak recorded as measured counts
including "0 natural asks"; natural false-positive and abandon rates "unmeasured, n=0" with CPO3-R3 open. Record approve-fatigue,
silent stall of previously unprompted workflows, and rebase-and-force-push friction as a medium open risk. Do not claim publicly:
exact window dates before bisect, "no destroy command ran unprompted", "fixed/protected for all users" before the member and grant
cases pass, any friction rate, any breach claim. Adopted above (family cases added for the `gh` families).

### Legal (CLO)

**Status:** reviewed (internal advisory; not external counsel)
**Assessment:** Filling the measured deploy date is a plain fact; the start-date clause may change only to "began on <measured
date>" with "we are determining" deleted; any other change returns to the CLO. The date is the production deploy of the first
inert build, not a release or merge date. The public repo already carries the detection date, so recording dates and aggregate
counts adds no Art. 33/34 consideration; the flag flips only on evidence of actual destruction or personal-data exposure. Record
aggregates and rule ids only, with counts under 5 suppressed; never write "no user affected" or "no destroy command ran" (the
post-mortem's telemetry gap forbids it); supersede in place in the post-mortem, ADR-284, the counsel-review audit and the
ADR-277 addendum. The dev-hosted C9 observation is replaced by probe plus production telemetry, recorded as an equivalence
determination; "member approvals observed" only if `approverRole=member` is read on an approved line. Adopted above.

### GDPR gate (Phase 2.7, run via `soleur:gdpr-gate`, 2026-10-12)

**Status:** reviewed (advisory; not legal review). No regulated-data path in Files to Edit/Create; no new vendor, column, table or FK; no
Critical finding. Two suggestions adopted: aggregate-only recording with the under-5 rule (Art. 5(1)(c)); dates and counts add no Art.
33/34 consideration beyond the public post-mortem. Triggered by the declared `single-user incident` threshold, not by the path regex.

### Product/UX Gate

**Tier:** none (no UI-surface file in Files to Edit or Create; the Approve card is unchanged)
**Decision:** not applicable
**Agents invoked:** none
**Skipped specialists:** none
**Pencil available:** N/A (no UI surface)

## Open Code-Review Overlap

None. Checked the open `code-review` issues' bodies against `apps/web-platform/scripts/dev-probe-destroy-ask.ts`,
`scripts/followthroughs/hosted-destroy-ask-window-9776`, ADR-284, ADR-277, the post-mortem and the counsel-review audit: no match.

## Files to Edit

- `apps/web-platform/scripts/dev-probe-destroy-ask.ts` - case matrix (member, live-grant control, grant, one `gh`), throwaway `HOME`,
  in-process capture, `PROBE_DECODE_ONLY`, `PROBE_PREFLIGHT`, comma-list `PROBE_ONLY`, provenance fields, header.
- `scripts/followthroughs/hosted-destroy-ask-window-9776.sh` - Guard 2 isolation, liveness arm and the 7 d zero-ask rule.
- `scripts/followthroughs/hosted-destroy-ask-window-9776.test.sh` - rows for the new arms (RED and must-PASS).
- `knowledge-base/engineering/architecture/decisions/ADR-284-hosted-bash-must-ask-lane-for-destroy-families.md` - C9 limbs, measured
  window, equivalence determination, flip criteria; status stays `adopting`.
- `knowledge-base/engineering/architecture/decisions/ADR-277-plugin-destructive-command-guard.md` - addendum dated soak-open pointer (counts come with the flip PR).
- `knowledge-base/engineering/operations/post-mortems/2026-10-11-hosted-bash-ask-bypassed-by-sdk-auto-allow-postmortem.md` -
  measured window, notice dates (CLO-limited edit), action-item statuses.
- `knowledge-base/legal/audits/2026-10-counsel-review-9776-ask-gate.md` - C9 disposition line (composed via the CLO agent).
- `plugins/soleur/test/preflight-discoverability-test.test.ts` - `BASELINE_DECLARED_PROBES` 62 -> 63 with the
  PLACEMENT/TRUTH/NO SUBSTITUTE comment (this plan's `discoverability_test` declares `credentials_required`; the repo-global G1
  ratchet counts declaring plans; re-read the live value at work time, it moves with sibling PRs).

GitHub-side (not repo files): bodies and one comment each on #9976 and #9776 (directive re-timing), a comment on #10054, one new
deferral issue.

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-accept-must-ask-lane-10054/tasks.md` - task breakdown (derived from this plan).
- (conditional) `knowledge-base/project/specs/feat-one-shot-accept-must-ask-lane-10054/decision-challenges.md` - written by plan
  review when it finds Taste or User-Challenge items.

No new source files. Path checks: every path above exists on `origin/main` (`git ls-files` verified for the five existing
scripts/ADRs/audit; the glob-free list needs no further verification).

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "extend the real-SDK probe ... to cover (i) a non-owner member session and (ii) a prior batch grant still gated" [brief] | Phase 1 item 2, Files to Edit entry 1 | mapped |
| 2 | "then query Better Stack and Sentry to confirm the pino destroy-ask line and the Sentry event actually arrive (verify the channel is allowlisted and retention covers the window before reading silence as absence)" [brief] | Phase 2; Phase 1 items 3-4; Guard 2 | mapped (arrival reported as NOT OBSERVED if no natural traffic; operator decision) |
| 3 | "Re-time their follow-through directives (earliest=) from the deploy of the fix (arm run 38223902738)" [brief] | Phase 0 | mapped |
| 4 | "then record measured numbers in the ADR-277 addendum (currently \"Measured numbers: not yet recorded\")" [brief] | Phase 5 (dated soak-open pointer now; the numbers in the flip PR once the windows close) | mapped (numbers sequenced after the windows) |
| 5 | "flip ADR-284 adopting -> accepted only once the measurements support it" [brief] | Sequencing; flip criteria; flip PR after 2026-10-19T08:40Z | mapped (flip deliberately not in this PR) |
| 6 | "Bisect the @anthropic-ai/claude-agent-sdk 0.3.x versions with the probe to bound when the gate went inert" [brief] | Phase 3 | mapped |
| 7 | "put the dates in the draft user notice" [brief] | Phase 5 post-mortem entry | mapped (draft only; publish is the operator's) |
| 8 | "the plan must say exactly which commands run, how probe results are recorded (measured, not asserted), and how the bisect pins/restores versions without leaving the lockfile changed" [brief] | Phases 0-3 command blocks; Phase 3 invariants | mapped |
| 9 | "Include the observability plan-quality gate (hr-observability-as-plan-quality-gate) and note Better Stack/Sentry queries are self-pulled" [brief] | `## Observability` | mapped |
| 10 | "Known open risks to keep visible, not fix unless trivial" [brief] | `## Known open risks` | mapped |
| 11 | "publish or decline the draft user notice, CLO breach-register row, legal items #9851 and #9955" [brief, out of scope] | Operator decisions (surfaced, not decided) | descoped - justification: the brief says surface at the end, do not decide |
| 12 | "Later items (W3 #9826/#9858 promotion per ADR-281, egress sequencing, #9602/#9603, closing #9601 ...)" [brief, out of scope] | none | descoped - justification: follow after item 1 is accepted per the brief |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Probe extension (member, grant) | asks 1 | asked |
| `gh-repo-delete` case in the probe | - | inferred - justification: CPO (Phase 2.5) requires the destroy families exercised before `accepted`; the probe had no `gh` case (one live case; the rest by corpus) |
| `grant-live-control` case and throwaway `HOME` | asks 1 ("a prior batch grant still gated") | asked for the grant limb; the live control is the anti-vacuity precondition the grant limb needs because the cache refuses destroy-capable heads by construction (plan review P0); `HOME` isolation is inferred - justification: a build that runs inert could reach `~/.config/gh` |
| In-process Sentry capture and `PROBE_DECODE_ONLY` row | asks 2 | asked (the only way to measure "emitted" with no DSN in the `ci` config) |
| Sandbox-engaged preflight (Tier 1 only) | - | inferred - justification: CTO; #5849 was also the bwrap P0, so a run with no sandbox would be silently non-evidence in the bisect |
| Phase 0 directive re-time | asks 3 | asked |
| ADR-277 dated soak-open pointer (counts in the flip PR) | asks 4 | asked, sequenced: counts cannot exist before the windows close; interim n=0 counts were cut by plan review |
| Guard 2 liveness arm and 7 d zero-ask rule | asks 2 ("before reading silence as absence") | asked for the liveness half; the zero-ask prompt is inferred - justification: without it the 7 d probe never reaches the "record these numbers" prompt at founder-only volume, so asks 4 and 5 could not complete through the tracker |
| Bisect Tier 1 (pins) and controls | asks 6 | asked (pins are the production exposure window; controls are the positive control) |
| Bisect Tier 2 (release-level) | asks 6 | asked; conditional and capped (reviewers asked to cut it: decision-challenges.md) |
| `BASELINE_DECLARED_PROBES` bump | - | inferred - justification: the G1 ratchet fails the required suite when a plan declares `credentials_required` without it |
| Guard 2 item (i), field isolation | asks 2 ("verify the channel is allowlisted ... before reading silence as absence") | asked - measured defect: the shipped probe cannot be read (34 contaminating rows) |
| Counsel-review audit C9 pointer | - | inferred - justification: the audit's disposition still reads "C9 post-merge observation pending"; one pointer line, not a repeat of the determination |
| Deferral issue (scheduled probe, canary) | - | inferred - justification: `wg-defer-only-after-inline-triage` / deferral tracking; CTO's deferral must have an issue |

### Split Assessment

- Subsystems touched: 4 - `apps/web-platform`, `scripts`, `knowledge-base`, `plugins/soleur`
- Planned files: 9 | Estimated changed lines: about 450
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR - the fourth root is a one-line ratchet bump (`BASELINE_DECLARED_PROBES`) that the declared probe forces
  into the same PR (a split would leave the required suite red between the two); the only real seam is the ADR flip, which is a
  separate later PR by sequencing, not by size

## Guard Contract

### Guard 1 - Real-SDK probe liveness matrix (apps/web-platform/scripts/dev-probe-destroy-ask.ts)

**Property.** Under the production option set and the real SDK, every destroy-family command in the covered hosted session shapes
(owner, non-owner member, a stale batch grant present) reaches the Approve/Reject gate with exactly those two options and leaves
the remote unchanged, while the control push and a live-grant control reach `canUseTool` without a card; and a run in which the model
never tried Bash, the sandbox was not engaged or a subset was selected can never print PASS.

**Assembly.** The `CASES` array and every variant it expands to; the `runCase` ctx deps builder (`isOwner`, `bashAutonomous`,
`autonomousAckAt`, `bashApprovalCache`); the per-case precondition block for the two grant cases; the single verdict function; the
refs-unchanged check; the exit-code mapping (0 PASS, 1 FAIL, 3 CANT-RUN, 4 DIAGNOSTIC); the SDK itself (version and bundled CLI
recorded on every line). Chokepoint: one verdict function and one exit mapping, so a case added later flows through them. The cache
launder path is a second chokepoint (`bashApprovalCache.allow` before the review gate) that the production code closes by refusing
destroy-capable heads, so the grant cases measure "still gated with a grant present", and `grant-live-control` proves the grant
mechanism is live in the same wiring.

**Mutation matrix:**

| # | Mutation (must drive RED) | Expected |
|---|---------------------------|----------|
| M1 | Pre-fix tree (`dfb9e2dba5^`) on SDK 0.3.284, `PROBE_ONLY=force-push-default` | `verdict=FAIL`, `canUseToolCalls=[]`, `bashAttempted=true`; the force push executes against the throwaway local remote (contained). Reproduces #10054 |
| M2 | `grant-live-control` with the grant prefix edited so `cache.allow(cmd)` is false (e.g. `"npm run other"`) | aborts CANT-RUN (exit 3) before the SDK call: a grant that was never live cannot certify "still gated" |
| M3 | Dispatch: `PROBE_ONLY=nonexistent` | zero `PROBE` lines and exit 3 (not 0, not 4-as-success): a run that checks nothing is vacuous |
| M4 | System prompt edited so the model does not use Bash | exit 3 `MODEL-DID-NOT-TRY` for every case, never 0 |
| M5 | Member variant wired with `isOwner:true` | the `extra.isOwner` assertion reds (`verdict=FAIL`, exit 1) |
| M6 | A second grant-shaped case appended after a compliant first with its card options widened to three (`Approve all`) | `approveReject=false` -> `verdict=FAIL` on the second while the first stays ok: the verdict loop does not stop at the first member |

**Harness rows.** H1 (suite edit, must RED): the M2 edit above is the suite edit; assert it exits 3, not 0. H2 (must-PASS, not the
canonical input): `grant-live-control` with a different grantable command (`bun run probe-noop`, prefix `bun run probe-noop`)
passes with no card, so a harness that rejects every grant cannot go green on the canonical spelling alone. RED rows assert exit 1 and
`verdict=FAIL` (or exit 3 where stated), never "non-zero": exit 4 DIAGNOSTIC is also non-zero.

The LLM is in this guard's assertion path by design (the property is the real SDK plus a real model reaching the callback), which
`plan-sharp-edges` warns reads as model compliance. Three controls bound it: a case where the model does not attempt Bash is exit 3
and never a pass, every bisect version is run twice, and the pre-fix control (M1) must FAIL on the same prompt, so a model that
always refuses cannot produce a green and the harness cannot fail only on the buggy build for an unrelated reason. Dev-host
limitation: the probe runs on the dev host (host bwrap, `NODE_ENV=test`), not in the hosted container; "deployed" means the same SDK,
bundled CLI and option builder, and the recorded identity is the DEPLOYED `build_sha` from `/health` plus the probe's own commit.

**Anchor.** The result is a live measurement, not a stored value; what must move for a weakening to pass is the SDK/CLI stack: the
recorded PASS names SDK version, bundled CLI version, deployed build SHA and UTC time, and `sdk-bump-sandbox-gate.sh` (required CI
check) refuses any lockfile SDK change without a `sdk-bump-verified:` acknowledgement. The probe re-run after a bump is a human step
enforced by that acknowledgement, not mechanically (and an SDK bump after the fix deploy also invalidates the soak start: the
directives are re-timed in that PR); the deferral issue tracks automating it.

### Guard 2 - Soak-probe isolation and liveness (scripts/followthroughs/hosted-destroy-ask-window-9776.sh)

**Property.** Each soak window is read from the app-container rows only (other services' rows that quote the marker neither trip
SHAPE_DRIFT nor count as asks nor hide truncation), neither window can report a clean or quiet result unless the channel is proven
live over the same window (both Better Stack arms), and a 7 d window that elapsed with zero natural asks and a live channel prompts the
flip instead of staying NOT YET.

**Assembly.** The main ask query and the new raw-SQL liveness query (same window, hot plus archive); the isolation predicate shared by
`MENTIONS`, `DECODABLE` and the lane-row `ROWS` decode (one definition, three uses) and deliberately NOT by the raw-line truncation
check; the decode; the three exits (2, 3, 5); both wrappers (`-24h.sh`, `-7d.sh`) which differ only in `--window`; the
`DESTROY_ASK_QUERY_SCRIPT` seam (a stub dispatching on its first argument: convenience flags vs `SELECT`); the `run_suite` row in
`scripts/test-all.sh`. Chokepoint: the single zero-ask branch (`TOTAL == 0`), now guarded by the liveness result for both windows.

**Mutation matrix:**

| # | Mutation (must drive RED) | Expected |
|---|---------------------------|----------|
| M1 | Liveness query returns 0, ask query returns 0 (24 h) | exit 3, not 2 |
| M2 | Same, 7 d | exit 3, not 5 |
| M3 | Liveness > 0, asks = 0, 7 d | exit 5 with the n=0 statement and the flip pointer |
| M4 | Liveness > 0, asks = 0, 24 h | exit 2 with `NOT YET: no 24h revert threshold tripped.` |
| M5 | Delete the liveness call from the script | suite RED (the row asserting exit 3 on a dark channel fails): the guard's own dispatch |
| M6 | Contamination (the measured 2026-10-12 shape): 34 `doppler`/`soleur-inngest-prd` rows quoting the marker, live app-container rows, zero lane rows | NOT exit 3 SHAPE_DRIFT; exit 2 (24 h) / 5 (7 d) |
| M7 | Control for M6: one app-container row quoting the marker that does not decode | exit 3 SHAPE_DRIFT (isolation did not blind the arm it protects) |
| M8 | Truncation: 5000 raw rows, almost all Inngest, a few app rows | exit 3 on the raw-count check (isolation must not hide it) |
| M9 | A canary-container row with `decision=destroy-ask` | not counted as an ask |

**Harness rows.** H0 (the measured shape as a fixture, first row of the suite): the 34-row contamination capture reduced to synthetic
rows with the same field shape (`cq-test-fixtures-synthesized-only`: no real payload text). H1 (suite edit, must RED): make the stub
return the liveness count for the ASK query too; the suite must fail on the ask-count assertion. H2 (must-PASS, not the canonical
fixture): ask rows from a repo name the canonical fixture never uses and container name in a different case than the liveness rows
(`CONTAINER_NAME` matching is exact; the row must still be excluded or included by the stated rule, asserted).

**Anchor.** Thresholds (25 %, 10 %, floor 20) are constants in the probe and ADR-284; the ADR sentence and the script constants are one
commit, and the existing test file pins the constants, so a weakening in one diff is visible as an ADR/script disagreement. No stored
hash. The merge-base diff in this PR's review is the outside check.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `AC1` Phase 0 done and verified: for each of #9976 and #9776 the re-read body's directive, parsed by the sweeper's own awk
  (column-0 `<!-- soleur:followthrough`, first `earliest=` wins), prints `earliest=2026-10-13T08:40:00Z` and `earliest=2026-10-19T08:40:00Z`
  respectively; a comment on each names T0 and run 38223902738 (T0 re-derived from the run's `release-outcome.completedAt`, not copied from
  this plan). **Ordering:** this PR must be merged before 2026-10-13T18:00Z (the sweeper cron is `0 18 * * *`); until it is, the
  24 h sweep runs the old probe, exits 3 SHAPE_DRIFT, and that comment is noise, not evidence (said in the PR body).
- [ ] `AC2` The extended probe, run exactly as `NODE_ENV=test doppler run -p soleur -c ci -- bun run
  apps/web-platform/scripts/dev-probe-destroy-ask.ts`, exits 0, and its output (pasted verbatim into ADR-284 with SDK version, CLI
  version, the DEPLOYED `build_sha` from `/health`, the probe's own commit, UTC time; paths redacted) shows `verdict=ok` for the four
  existing cases, `member-force-push-default`, `grant-live-control`, `grant-force-push-default`, `gh-repo-delete`,
  `remote-refs-unchanged=true` and `RESULT: PASS`; and `PROBE_DECODE_ONLY=1` prints the decode-compat success line.
- [ ] `AC3` Guard 1 rows measured with exact outcomes (not "non-zero"): M1 on the pre-fix tree shows `verdict=FAIL` and
  `canUseToolCalls=[]`; M2 exits 3; M3 prints zero `PROBE` lines and exits 3; M5 exits 1. Raw exit codes and `PROBE` lines recorded.
- [ ] `AC4` In-process capture asserted by the probe and recorded: Sentry event tags `feature=cc-permissions`, `op=hosted-destroy-ask`,
  `extra.ruleId` prefix and `extra.isOwner` per variant, envelope with no command text. The decode-compat row passes through the soak
  probe (its summary counts the line; `level` is 40).
- [ ] `AC5` Guard 2: `bash scripts/followthroughs/hosted-destroy-ask-window-9776.test.sh` exits 0 with the new rows (M1-M9, H0-H2) and
  its anti-vacuity floor prints a literal count; the live run `doppler run -p soleur -c prd_terraform -- bash
  scripts/followthroughs/hosted-destroy-ask-window-9776-24h.sh` no longer exits 3 SHAPE_DRIFT on the 2026-10-12 contamination (first line
  begins `hosted destroy-ask window 24h`, exit 2 or 5); `scripts/test-all.sh`'s row still runs the suite.
- [ ] `AC6` Telemetry reads recorded (counts only, "under 5" rule) per Phase 2, each with its positive control: Better Stack (allowlist
  quote, retention figure, archive-arm control, decoded lane counts) and Sentry (four ops, release control, 30 d retention control);
  the interpretation rule applied literally ("arrival NOT OBSERVED" if zero). The explicit windows [T0, now] are recorded with their
  bounds; the sweeper's trailing windows are not substituted for them.
- [ ] `AC7` Bisect recorded: controls, the pins x 2 runs with `claudeCodeVersion` and per-pin code-side confirmation, any Tier 2
  versions, and the production-deploy dates derived per Phase 3 item 6 (or the Phase 3 item 5 fallback bounds, composed by the CLO
  agent). In the FEATURE worktree: `git status --porcelain` shows no change under `apps/web-platform/` from the phase, `git diff --quiet
  origin/main...HEAD -- apps/web-platform/package.json apps/web-platform/package-lock.json` exits 0, the installed SDK still reads
  `0.3.284`; the scratch worktree is removed and pruned.
- [ ] `AC8` Post-mortem updated per Phase 5 (measured window table, bisect commands, notice dates limited to the CLO-cleared edit,
  statuses); no sentence "no user affected" or "no destroy command ran"; `art_33_triggered` unchanged; `status` not set to resolved.
- [ ] `AC9` ADR-284 still has `status: adopting` (frontmatter and `## Status`), the Status sentence carries "NOT OBSERVED / never
  observed / revisit triggers" next to the status, the `## Flip checklist` exists, the equivalence is worded "proposed ... pending
  operator ratification"; ADR-277 addendum no longer contains `Measured numbers: not yet recorded` and carries the dated soak-open
  pointer with no counts and no "verified"; the counsel-review audit has the one-line C9 pointer.
- [ ] `AC10` Deferral issue created (milestone Phase 4: Validate + Scale; labels `domain/engineering`, `type/chore`,
  `priority/p2-medium`) and linked from ADR-284.
- [ ] `AC11` PR body for #10101 uses `Ref #10054, #9776, #9976, #9601` only: no `Closes`/`Fixes`/`Resolves` before any of them; the PR is
  NOT merged without the operator's explicit "go ahead".
- [ ] `AC12` `bash plugins/soleur/test/c4-count-parity.test.sh` green; `bun test plugins/soleur/test/preflight-discoverability-test.test.ts`
  green with the bumped baseline; `python3 scripts/lint-guard-contract.py <this plan>` and `python3 scripts/lint-infra-no-human-steps.py
  --changed --base origin/main` pass; `npx markdownlint-cli2` clean on this plan and `tasks.md`.
- [ ] `AC13` Diff scope: `git diff --name-only origin/main...HEAD` is a subset of the Files to Edit and Files to Create lists plus the
  files the pipeline itself writes (`knowledge-base/INDEX.md` if regenerated; under
  `knowledge-base/project/specs/feat-one-shot-accept-must-ask-lane-10054/`: `tasks.md`, `session-state.md`, `decision-challenges.md`); no
  file under `apps/web-platform/server/`, `apps/web-platform/package*.json` or `.github/` appears.

### Soak-gated tail (not this PR; enrolled; owner = whoever picks up #9776 under the follow-through convention)

- [ ] `T1` After 2026-10-13T08:40Z: an explicit self-pulled read over [T0, T0+24h] (Better Stack `--since`/`--until` and the Sentry
  ops) shows no revert-threshold trip, and the sweeper comment carries `NOT YET: no 24h revert threshold tripped.` (a missing comment
  is a failed sweep, not a quiet day: check the run, do not infer).
- [ ] `T2` After 2026-10-19T08:40Z: #9776's 7 d probe prompts (exit 5, now also at zero asks); the flip PR runs an explicit read over
  [T0, T0+7d] (the sweeper's trailing windows start at 18:00Z and skip about 9 h after T0), records final counts with the under-5 rule,
  and executes ADR-284's `## Flip checklist`. CPO3-R1 is recorded closed only if the flip criteria hold; otherwise ADR-284 stays
  `adopting` with the shortfall named. Decision 3 below is the operator's before this date; if it is unanswered by 2026-10-19 the flip
  PR is not opened and the tracker comment says why.
- [ ] `T3` Any SDK, bundled-CLI or sandbox-option change deployed before the flip: re-run the probe on that build and re-time both
  directives from that deploy (the bump PR carries the `sdk-bump-verified:` token); the flip waits for the later window.

## Test Scenarios

### Acceptance tests (RED phase targets)

- Soak-probe suite: dark channel (zero liveness) with zero asks -> exit 3 (24 h and 7 d); live channel, zero asks, 7 d -> exit 5 with
  the n=0 wording; live channel, zero asks, 24 h -> exit 2. Written and failing before the script edit (`cq-write-failing-tests-before`).
- Probe-side: the `grant-live-control` precondition aborts CANT-RUN when `cache.allow` is false (Guard 1 M2); the dispatch row (M3)
  and the not-Bash row (M4) exit 3. These are exercised by editing the probe's inputs, not by an in-script self-test mode.

### Regression tests

- Existing `destroy-ask-*` vitest suites, `agent-runner-sandbox-config.test.ts` (autoAllow false), `sandbox-hook.test.ts`, and
  `apps/web-platform/scripts/sdk-bump-sandbox-gate.test.sh` remain green; no production file changes, so they are run, not edited.

### Edge cases

- Hot-window-only read mistaken for a 7 d read (the hot window held about 3 h): the liveness arm and every soak query go through
  the convenience flags' archive arm; raw SQL carries the `UNION ALL s3Cluster` explicitly.
- Sweeper runs later than `earliest` (a 24 h window then covers a later 24 h): documented, counts still post-fix.
- Old SDK rejects a current option or the sandbox is not engaged: exit 3, non-evidence, recorded.
- A pin merge that was never deployed or was rolled back: the date is the deploy record's, with a note.

### Integration verification (for `soleur:qa`)

- **Probe:** `NODE_ENV=test doppler run -p soleur -c ci -- bun run apps/web-platform/scripts/dev-probe-destroy-ask.ts` expects
  `RESULT: PASS`.
- **Soak probe:** `doppler run -p soleur -c prd_terraform -- bash scripts/followthroughs/hosted-destroy-ask-window-9776-24h.sh`
  expects a first line beginning `hosted destroy-ask window 24h` and an exit of 2, 3 or 5 (never 0 or 1).

## Dependencies & Risks

- Live Anthropic API calls (key from Doppler `ci`; the account was reported "credit balance too low" in a Sentry event on
  2026-10-12 08:03Z from a different surface - verify a trivial call works before the phase; a credit failure is CANT-RUN, not a result).
- `npm` registry access for the scratch SDK installs; bubblewrap available on this host (the earlier PASS ran here).
- The operator's decisions below can change what "supports it" means for the flip; they do not block this PR.

## Operator decisions to surface at the end (not decided here)

1. Publish or decline the draft user notice (dates now measured); add the breach-register row (CLO). #10054 stays open for it.
2. Legal items #9851 and #9955.
3. (Needed before 2026-10-19; owner: the operator.) Whether in-process emission plus channel liveness is accepted as the substitute if zero natural asks leave arrival in the
   production sinks NOT OBSERVED, versus authorising a production write: a synthetic ask via the live-verify principal, or a probe
   emission to the production Sentry DSN tagged `environment=probe` (both are production writes needing explicit authorisation).
4. Whether the deferred scheduled probe on SDK bump becomes a required check (CTO's recommendation).

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will
  fail `deepen-plan` Phase 4.6; this one carries all three lines.
- `earliest=` values live only in issue bodies; a PR cannot pin them, so Phase 0's verify step (re-read through the sweeper parser)
  is the guard, and the work phase must do it BEFORE the first sweeper run after 2026-10-12T11:00Z.
- A bare `--grep destroy-ask` returns other services' rows; never count without decoding and field-isolating.
- The `ci` Doppler config has no Sentry DSN or Better Stack token: a local PASS says nothing about sink arrival; do not word it so.
- Do not use `Closes`, `Fixes` or `Resolves` before #10054, #9776, #9976 or #9601 in the PR body or any commit message.
- Counts under 5 are written "under 5" in anything public; no repo names, user ids or command text anywhere.
- The lane's producers are the founders using hosted Concierge (a handful); a zero over seven days is the expected measurement and
  proves nothing about the lane by itself. The absence-of-signal close the 7 d probe implements is only valid because Guard 2
  adds the liveness arm and the dev probe supplies the positive control (`plan-sharp-edges`: absence closes need proof the
  affected party can produce the signal).
- `credentials_required` in the discoverability test bumps a repo-global ratchet; re-read `BASELINE_DECLARED_PROBES` at work time.
- Do not word anything as "the lane is verified in prod". The strongest true sentence is "the real-SDK probe passed on the deployed
  stack; production sink arrival is NOT OBSERVED" (or the counts, if any).
