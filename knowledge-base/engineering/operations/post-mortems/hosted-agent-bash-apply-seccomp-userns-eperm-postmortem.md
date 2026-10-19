---
title: "Hosted agent Bash failed on every call with apply-seccomp unshare(CLONE_NEWUSER) EPERM for an inferred twelve days, and nothing alerted: our own seccomp filter killed the SDK's command-side helper while the canary replayed only the setup argv"
date: 2026-10-16
incident_pr: 10445
incident_window: "2026-10-06T13:19:38Z (inferred onset: first production deploy of web-v0.324.3, web-1; no pre-2026-10-16 failure was observed directly) → 2026-10-18T16:41:40Z (fix PR #10451, merge commit 940578c435, deploy job success)"
recovery_at: "2026-10-18T16:41:40Z"
suspected_change: "#9595 (shared bwrap seccomp filter plus fd hygiene, first shipped in tag web-v0.324.3, 2026-10-06)"
# incident class (every hosted session); the fix PR's plan declares `single-user incident` for the cross-tenant surface it widens
brand_survival_threshold: aggregate pattern
status: resolved
triggers:
  - availability (hosted agent Bash tool fails at sandbox start; production /health stays ok)
  - silent detection gap (sandbox_canary green over a hard-down Bash; the tool_result classifier returns null for the helper line)
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "n/a"
# Classification rationale: an availability event on the agent Bash tool with no personal-data dimension. The sandbox
# failed CLOSED (the command never ran, no isolation was weakened). Every hosted session that uses Bash is affected, so the
# advisory is aggregate pattern rather than single-user. No personal data was exposed, accessed, altered or lost, so
# Art. 33 and Art. 34 do not apply; no Art. 33(5) register row is warranted for a false screening output.
---

## Actor key

- `agent` — Claude Code did this autonomously (no operator ack required).
- `agent-with-ack` — Claude Code did this AFTER operator confirmed via menu option per `hr-menu-option-ack-not-prod-write-auth`.
- `human` — Operator did this directly.

# Incident Overview

Every hosted Concierge Bash call failed at sandbox start with `apply-seccomp: unshare(CLONE_NEWUSER): Operation not
permitted` from the first production deploy of `web-v0.324.3` on 2026-10-06 (inferred from deploy time and mechanism; no
failure before 2026-10-16 was observed directly) until the fix deployed on 2026-10-18 (see Status). Production `/health` stayed `ok`
throughout and no alert fired. The cause was a collision between two controls we ship:
the bwrap PATH shim's seccomp filter (introduced by #9595) denies `unshare(CLONE_NEWUSER)`, and the Agent SDK wraps every
sandboxed Bash command in an embedded `apply-seccomp` helper whose first syscall, when it holds no capability, is
exactly that `unshare`. The recorded premise that this helper was "inert today" (the #8752 plan) was false.

## Status

resolved for the shared Bash path — the fix (`network.allowAllUnixSockets: true`, so the SDK does not engage the helper)
shipped in PR #10451 (merge commit `940578c435`) and its deploy job succeeded at 2026-10-18T16:41:40Z. Resolution gate
met on 2026-10-19 on the operator's statement that a real hosted Bash call works (recorded on #10445,
issue-comment 6262884460). The call's clock time and the session's entitlement were not captured and no artifact
records the call. `recovery_at` is the fix deploy, assumed effective; the call only shows Bash worked at some point
after that deploy and before this report was edited on 2026-10-19. Not verified: an entitled web-egress session, which
the Customer Impact section lists as still affected until #10457 lands; the accepted gap on per-command Unix-socket
blocking (Resolution, #10455 item 1) is unchanged by this flip.

Visibility: the repository is public, so this report is not internal. It is redaction-gated, holds no tenant data, and
the mechanism detail already lives in public ADRs.

## Symptom

A user-visible Bash tool failure whose text is the single line `apply-seccomp: unshare(CLONE_NEWUSER): Operation not
permitted`. The line names the SDK helper, not bwrap, which is why the existing classifier did not recognise it.

## Incident Timeline

- **Start time (detected):** 2026-10-16T14:44:25Z (issue #10445 filed from a user report)
- **Onset (impact start):** 2026-10-06T13:19:38Z, inferred: first production deploy of `web-v0.324.3` (web-1; web-2 accepted the same tag at 13:20:41Z). No pre-2026-10-16 failure was observed directly; the onset follows from the deploy time and the mechanism (mechanism confirmed in Root-cause hypothesis and 5-Whys).
- **End time (recovered):** 2026-10-18T16:41:40Z (fix deploy job success; operator confirmed a working hosted Bash call on 2026-10-19)
- **Duration (MTTR):** 2d 1h 57m 15s from detection (2026-10-16T14:44:25Z); impact window 12d 3h 22m 2s from the inferred onset

Order of events (load-bearing: the redaction sentinel scans this table; the Actor key feeds the Actor column). Counts and
timestamps only; sources are Better Stack `ci-deploy` rows, `/hooks/deploy-status` and the git history.

| Actor | Time (UTC) | Action |
|---|---|---|
| agent | 2026-10-06T11:48:18Z | Tag `web-v0.324.2` commit made; it does not contain #9595. It was deployed to web-1 at 13:03:12Z: the last deployed image without the shim filter. |
| human | 2026-10-06T12:53:43Z | #9595 merged (GitHub `mergedAt`); tag `web-v0.324.3` points at its merge commit `eb92243fe8`, whose commit timestamp is 12:17:23Z. |
| agent | 2026-10-06T13:19:38Z | web-1 accepts `deploy web-platform ... v0.324.3`; image pull OK at 13:20:20Z, `SANDBOX_PROBE_OK` (the blocking bwrap probe, which ends in a trivial command) at 13:20:35Z, deploy exit_code 0 at 13:20:41Z. This is the incident onset. |
| agent | 2026-10-06T13:20:41Z | web-2 accepts the same tag; image pull OK 13:21:48Z. Both fleet hosts now run the shim filter. |
| agent | 2026-10-06 to 2026-10-16 | 216 further web-1 deploy acceptances after the onset deploy (2 to 35 per day); the faithful canary and the blocking bwrap probe did not fail on this cause in any of them, because every deploy-time probe ends in a command that never runs the wrapper. |
| agent | 2026-10-09 to 2026-10-11 | A separate outage (`--proc` mount EPERM under docker's masked /proc, #9860) makes the faithful canary red; it is fixed by #10039 (merged 2026-10-11T18:29Z). This masks the helper failure: any Bash complaint in the window reads as the known `--proc` incident. |
| agent | 2026-10-11T18:44:14Z | `sandbox_canary` records its first pass after #10039 (`first_pass_at`); it then stays green. |
| agent | 2026-10-10T13:15Z to 2026-10-11T16:12Z | 30 `SOLEUR_CANARY_SANDBOX_DIAG ... section=kernel_ns` rows, all identical: `restrict=0 clone=1 max=30852`. Unprivileged user namespaces are permitted by the kernel, so the host setting is refuted as the cause. |
| human | 2026-10-16T14:44:25Z | Issue #10445 filed from a user report: hosted Bash is down. Discovery. |
| agent | 2026-10-16T15:28Z | Self-pulled `/hooks/deploy-status` (tag `v0.342.17`, deploy 09:19:32Z to 09:20:42Z, reason `ok`): `seccomp_profile_host_present=true`, `seccomp_profile_loaded_matches_host=true`, `sandbox_canary` verdict `pass` with `consecutive_pass=108`, `workspace_isolation` verdict `pass`, `outer_wrap_canary` verdict `sandbox_broken` reason `wrong_elevation_userns` (report-only, already red). The delivered profile is the enforcing one; the canary is green over a down Bash. |
| agent | 2026-10-16 | Root cause reproduced locally with the committed filter artifact and the SDK's embedded helper (exact production line, rc 1). Fix committed in `21a7319bf7` (squashed into `940578c435`). |
| human | 2026-10-18T16:28:00Z | Fix PR #10451 merged (GitHub `mergedAt`; merge commit `940578c435`, commit timestamp 15:44:52Z). |
| agent | 2026-10-18T16:41:40Z | Release deploy job succeeds for the merge commit; `live-verify` succeeds at 16:41:59Z. Fix deployed; recovery time of record (assumed effective until the operator call). |
| human | 2026-10-19, time not captured | Operator makes a real hosted Bash call and reports it works (comment on #10445, issue-comment 6262884460). Resolution gate met on the operator's statement; no artifact records the call. |

## Participants and Systems Involved

Operator (single founder); Claude Code agents (diagnosis, fix, record). Systems: bwrap PATH shim and its generated
nested-userns seccomp filter (`apps/web-platform/infra/bwrap-shim/bwrap`, `gen-bwrap-userns-seccomp.mjs`), the Agent SDK
`@anthropic-ai/claude-agent-sdk` 0.3.284 and its embedded `claude` binary (the `apply-seccomp` helper), the faithful
sandbox canary (`sandbox-canary.mjs`, ADR-079), the Bash tool_result classifier (`sandbox-startup-classifier.ts`),
Better Stack Logs, Sentry.

## Detection (+ MTTD)

- **How detected:** external — a user reported it; no monitoring system flagged it.
- **MTTD (mean time to detect):** approximately 10 days (10d 1h 24m, taking the inferred onset; from the first production deploy of `web-v0.324.3` at 2026-10-06T13:19:38Z to the issue at 2026-10-16T14:44:25Z).

## Triggered by

system — our own change (#9595) interacting with an SDK default we did not enumerate.

## Root-cause hypothesis (triage)

Triage-time competing hypotheses; the post-resolution final root cause lives in the 5-Whys section below.

| Hypothesis | Supporting evidence | Disconfirming evidence | Status |
|---|---|---|---|
| Our seccomp filter denies `unshare(CLONE_NEWUSER)`, which the SDK's `apply-seccomp` helper needs | Exact production line reproduced locally with the committed filter and the embedded helper; EPERM text names the helper, not bwrap; onset matches the first deploy containing #9595 | none | confirmed (see Causal evidence below) |
| The delivered seccomp profile is not the one enforcing | n/a | `seccomp_profile_host_present=true`, `seccomp_profile_loaded_matches_host=true` | refuted |
| A kernel or AppArmor setting disabled unprivileged user namespaces | n/a | 30 `kernel_ns` DIAG rows all `restrict=0 clone=1 max=30852`; the canary replay creates user namespaces on the same hosts every deploy | refuted |
| Only a subset of hosts or sessions is affected | n/a | The SDK wraps every command it sandboxes, so every session on every host running the image with the shim is affected | refuted |
| #10349 caused it | The issue's 36-hour window | The cause predates the window by 10 days | refuted (incomplete premise) |

### Causal evidence

Measured 2026-10-16 in a production-like container (node:22-slim digest base, Debian bubblewrap 0.8.0, uid 1001, docker
default masks, the committed seccomp profile; AppArmor unconfined): with no shim filter the wrapped Bash call succeeds;
with the shim filter and the knob unset it fails with the helper EPERM. The filter is therefore the cause.

This reconciles with the #10032 measurement (`knowledge-base/project/specs/archive/20261013-062704-feat-one-shot-10032-sandbox-shim-procfs/measurements.md`,
section 0.3), which showed the helper rc=1 "with and without our bpf": that run was on a host that denies unprivileged
`NEWUSER` inside the container, which is a different kernel posture from production (`kernel_ns` rows: `restrict=0
clone=1`). Its section 0.1 also left open whether the wrapper is present in production's real command.

## Resolution

Set `network.allowAllUnixSockets: true` in `apps/web-platform/server/agent-runner-sandbox-config.ts` so the SDK does not
wrap commands in the helper. The seccomp filter is left intact, so the nested-userns and `clone3` denial that #8752 and
#9595 exist for is unchanged. With the helper gone there is no per-command AF_UNIX block, which is weaker than the
pre-incident baseline in that one dimension. It is bounded by (1) per-session proxy-credential auth on the sibling
bridge sockets, (2) masks over the CLI peer-messaging socket directories (the union of `cc-socks` under
`XDG_RUNTIME_DIR`, `CLAUDE_CODE_TMPDIR`, `TMPDIR` and `/tmp`, plus `/tmp/cc-socks-<uid>`), where a failed pre-create now
is reported to Sentry through `reportSilentFallback` as an error event (the mask is then OFF for that directory, so this fails open and no dedicated alert routes the event yet, #10455), (3) a mask over the session-transcript directory
(`$HOME/.claude/projects`, and `$CLAUDE_CONFIG_DIR/projects` when set), because a sibling's proxy credential printed by
`env` and persisted in a shared-HOME transcript would otherwise be usable, (4) per-command `--unshare-net`, and (5) a per-tenant CLI temp base so no sibling can read a persisted Bash output carrying a proxy credential (found in the fix-round review; CTO-ruled). See the
ADR-075 addendum. The fallback if the two-session test fails (it did not fail; the fix merged with it green) is a single `socket(AF_UNIX)` deny folded into the one bwrap
filter, never `socketpair`.

Detection added: the Bash tool_result classifier now maps exactly the line
`apply-seccomp: unshare(CLONE_NEWUSER): Operation not permitted` (line-anchored, nothing trailing) to
`helper_userns_eperm`; a pino mirror feeds a Better Stack alert (`agent_sandbox_bash_denial`, email) shipped with PR #10451 and went live on its post-merge Terraform apply (read back live after the merge: `soleur-agent-sandbox-bash-denial-prd` exists, unpaused, email-only). Other helper-step
EPERMs are not classified (residual, #10455), and the legacy agent-runner loop has no tool_result observer.

## Recovery verification

Pre-merge: the fix is proved through the real SDK in two places. `test/sandbox-wrapped-command-runtime.test.ts` drives the
production config and our shim (control with the knob off reproduces the helper EPERM; treatment returns the command's
stdout), and the docker suite repeats both arms under the production run tuple (docker masks, seccomp profile, uid 1001,
Debian bubblewrap 0.8) plus a pathname-socket census. Post-merge: `scripts/followthroughs/sandbox-readback-10445.sh`
is a NOTIFY-ONLY probe (it never exits 0, so the sweeper cannot close #10456 on its own): it reports NOT YET until the PR's merge commit is an ancestor of the deployed tag, the last deploy succeeded for web-platform and the canary ran since it started, then reports ACTION REQUIRED. After the merge it reported ACTION REQUIRED (`fix_deployed=yes`, `sandbox_canary=pass`).
That means "fix deployed and canary green", not that hosted Bash works: the canary was green throughout the outage, so
it is not evidence of recovery. The first real hosted Bash call was made by the operator on 2026-10-19 and reported as
working (see Status); no existing agent-run check exercises a hosted Bash call, so none could make it. The deploy-time SDK Bash smoke that would make the canary see this class is #10453.

---

# Incident Post-Mortem Analysis

## Root Cause(s) — 5-Whys

1. **Why did every hosted Bash call fail?** The SDK wraps each sandboxed command as `ARGV0=apply-seccomp
   /proc/self/fd/<N> <shell> -c <cmd>`. The helper's first syscall, when it holds no capability (the inner sandbox runs
   `--cap-drop ALL`), is `unshare(CLONE_NEWUSER)`, and our shim filter returns EPERM for it.
2. **Why did we ship a filter that kills the helper?** The #8752 plan recorded the helper as "inert today (our config sets
   no `allowUnixSockets`)". That premise was false: `allowAllUnixSockets` is unset, so the SDK emits the wrapper by
   default. The 2026-10-09 learning `knowledge-base/project/learnings/security-issues/bwrap-args-payload-outer-resume-proc-mask-20261009.md`
   already records that the vendored inner command execs `apply-seccomp /proc/self/fd/N` (its Solution and Key Insight
   sections); the #10032 measurement left open whether the wrapper is present in production's real command. The false
   premise was never re-checked against the vendor binary before #9595 enabled the filter.
3. **Why did the contradicting evidence not stop the change?** #10032 logged "if prod's real command does wrap
   apply-seccomp, its NEWUSER dies under our bpf" as a non-gating open risk with no new issue of its own. The adjacent
   gap (run the nested-unshare probe inside the production canary container) already had an owner, #5941, which is still
   open (its probe is the layer-B `unshare` pair, not the SDK's wrapped command; #10453 is the successor for that class).
4. **Why did the deploy-time canary stay green?** It replays only the captured bwrap SETUP argv, ending in `-- true`
   (`parseShimSetupArgv` documents the command tail as model-chosen and never replayed), so the command-side wrapper is
   never executed. Its `nested_userns_deny` probe even requires the denial that breaks the helper. `sandbox_canary` read
   `consecutive_pass=108` over a hard-down Bash.
5. **Why did the runtime path not catch it?** The Bash tool_result classifier required a `bwrap|bubblewrap` token plus
   `Operation not permitted` on one line; the helper's line has neither a bwrap token nor any other match, so it returned
   `null`. Even a matching event would have paged nobody: the Sentry rule is deferred in #10052 (blocked on #7985), no
   alert read `SANDBOX_CANARY_FAIL` rows, and the standing report-only outer-wrap canary has been red for a week without
   paging. The separate `--proc` outage (#9860) on 2026-10-09 to 2026-10-11 also taught the team that a Bash complaint
   was a known issue.

Contributing factors: (a) the detection gap is the same class as the 2026-10-11 PIR (a report-only canary and a Bash
denial reaching Sentry as nothing); its action items closed the `--proc` case, not the class. (b) Production `/health`
does not exercise the Bash tool. (c) The bwrap probe at deploy time ends in a trivial command and is green by
construction for this failure mode.

## Versions of Components

- **Version(s) that triggered the outage:** `web-v0.324.3` (first tag containing #9595), first production deploy 2026-10-06T13:19:38Z. Production ran `v0.342.17` when the incident was diagnosed (2026-10-16), before the fix.
- **Version(s) that restored the service:** the release built from merge commit `940578c435` (PR #10451), deployed 2026-10-18T16:41:40Z.

## Impact details

### Services Impacted

The hosted agent Bash tool on every production host (web-1 and web-2). No other tool was reported affected.

### Customer Impact (by role)

Per learning `2026-05-06-user-impact-section-by-role-not-surface.md` — enumerate by USER ROLE, not by surface.

The affected-user count is unmeasurable. Phase 0 census-source discovery found no queryable store of Bash tool_result
text: the server forwards `command_stream` output render-only and ephemeral, no `op=bash-tool-result` row has ever
reached Better Stack from the app container (0 rows in 99,049 app-container rows from 2026-10-05 to 2026-10-16), and the
only other copy of that text is the SDK session transcript on each tenant's own workspace volume, which would be a
per-tenant read of tenant content and was not done. The number to use is a session-count proxy (hosted sessions that
could have invoked Bash since 2026-10-06), obtained as an aggregate count with no tenant content, if and when the CLO
gate clears it; a user-note decision stays with the operator.

- Prospect: not affected (no authenticated session).
- Authenticated app user: any session whose agent used Bash saw the failure; other tools unaffected. Count unmeasurable.
- Legal-document signer: not affected.
- Admin via Access: not affected.
- Entitled web-egress user: still affected after this fix until #10457 lands (`spawnEgressForwarder` cannot create its token directory, so the forwarder gets no gateway credential); an entitled-session call was not verified (see Status).
- Billing customer: not affected beyond the above; no billing path involved.
- OAuth installation owner: not affected beyond the above.

### Revenue Impact

Unknown / N/A — no measurement and no number fabricated.

### Team Impact

One founder-operator; one P1 diagnosed and fixed in a single session, plus the follow-up detection work.

## Lessons Learned

### Where we got lucky

The failure was closed: the command never ran, so no isolation was weakened and no tenant data was exposed. The outage
overlapped the `--proc` incident, which both hid this one and kept the sandbox canary under attention.

### What went well

The RCA was self-pulled from Better Stack, Sentry and `/hooks/deploy-status` with no SSH, and reproduced locally with the
committed artifact before any fix. The challenged fork (carve an exception versus keep the filter and stop the SDK
engaging the helper) was settled on evidence rather than by loosening the filter.

### What went wrong

A recorded risk (#10032) was not linked to its existing owner (#5941, nested-unshare probe in the production canary); a false "inert" premise survived two plans; the canary and the classifier were both blind
to the command-side wrapper; no alert covered user-visible Bash failure; a known-red canary paged nobody.

## Action Items & Follow-ups

Every action item and follow-up so this incident cannot recur. #10455 is one tracker holding several distinct actions,
listed below as items of that tracker.

| Issue | Action | Status |
|---|---|---|
| #10445 | Fix: `allowAllUnixSockets: true`, behaviour proof with a control arm, runtime two-session socket test, docker-suite wrapper arm | done 2026-10-18 (#10451 deployed); issue closes with the flip |
| #10455 | (item 1) Own AF_UNIX `socket()` deny folded into the single bwrap filter (option b); re-evaluate on an SDK bump that changes the helper, or a decision to enforce unix-socket blocking; becomes in-scope immediately if the two-session test fails | open |
| #10455 | (item 2) Runtime synthetic of the wrapped Bash command with a dead-man arm (P2) | open |
| #10455 | (item 3) Plain-language message when Bash fails (raw apply-seccomp text is the user-visible failure today) | open |
| #10455 | (item 4) Verify the Slack wake path (ADR-260) across all Better Stack alerts; the new alerts are email-only until then | open |
| #10455 | (further items) Classify other helper-step EPERMs; page on at least 2 distinct users or verify server-side (forged-row suppression); SOCKS proxy-auth test | open |
| #10454 | Standing red outer-wrap canary (`wrong_elevation_userns`, Sentry 152662657): fix the elevation or demote explicitly, with a decision deadline; related to #9797 | open |
| #10453 | Deploy-time SDK Bash smoke in the canary container (non-blocking first); successor to #5941 for the wrapped-command class | open |
| #5941 | Pre-existing owner of the nested-unshare probe inside the production canary container | open |
| #10457 | Adjacent: `spawnEgressForwarder` mkdir EACCES on `/var/lib/soleur/egress-tokens` (entitled web-egress sessions) | open |
| #10456 | PIR `status: ongoing` → `resolved` docs PR, notified by the notify-only `sandbox-readback-10445.sh` follow-through (ACTION REQUIRED); closed by hand after the flip; its directive gains `secrets=GH_TOKEN` | flipped in #10520; close by hand after merge |
| #10477 | Affected-user outreach: a targeted note to users whose sessions used Bash since 2026-10-06, and a check for lost half-finished runs. An operator brand decision, not assumed; pending | pending |
