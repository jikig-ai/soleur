---
title: "docs: plan the single bundled Inngest host-replace window (Ref #9927)"
date: 2026-11-06
slug: inngest-host-replace-window
branch: feat-one-shot-9927-host-replace-window-plan
issue: 9927
type: docs
priority: p3-low
domain: engineering
closes: none
refs: [9927, 12230, 11266, 11265, 12158, 12229, 12213, 12221]
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
lane: cross-domain
---

## Enhancement Summary

**Deepened on:** 2026-11-06. **Halts run and passed:** User-Brand Impact (4.6), Scope Check (4.12, one unfenced section, no `BLOCKED` marker), PAT-shaped variable sweep (4.8, no hits). **Skipped with reason:** Observability (4.7) and Task Design (4.13), because the plan edits no code and adds no autonomous surface; Encryption Posture (4.10) and Guard Contract (4.11), because it introduces no store, connection or guard; UI wireframe (4.9); Downtime and Cutover (4.55), because the plan changes nothing and the replace's own downtime is the runbook's.

**Cited facts re-resolved live this pass:** PRs #11535, #12210 and #12186 are MERGED (merge times as stated in the plan); origin/main tip is bd89194eed; the plan cites no AGENTS rule ids; every run id, SHA and job name was also checked by the Kieran seat against `gh`. **Review passes already applied:** the 5-seat plan-review panel, the CPO conditions and CTO rulings T1 to T5 (see `decision-challenges.md`). One wording fix in this pass: row c1 no longer asserts which `.tf` file the dead-man alert lands in.

## Overview


Epic #9927 agreed in session on 2026-11-06 that one bundled window is planned for the next
Inngest host replace (ADR-282 addendum of 2026-11-06, ruling D6). This document is that plan,
written so it can also be used as the runbook for the window. It has four parts: a precondition
ledger for D6 (a) to (g), the D2 post-window ordering with a named rollback per step, a dated
PROPOSAL, and the owner's actions. It is documentation only.

What this PR does not do, stated once and binding on every later step: it dispatches nothing
(`apply_target=inngest-host-replace` stays a per-command in-session go, hold O4), edits no issue
body, closes none of #9927, #12158, #12213 or #11265, does not touch
`apps/web-platform/infra/inngest-arm-write-token.tf`, signs or drafts nothing for the A6 record,
commits no spend, and runs no delegation or render step. The PR body says `Ref #9927`, never
`Closes` or `Fixes`. The CTO agent ruled "No delegable act" for this epic: every operator hold
stands. No question is put to the owner in this run; Part 4 lists actions for the owner at the
time they fall due.

Labels used verbatim, per the CLO ruling L3: "owner decision given in session 2026-11-06 (relayed
by the agent; not a signed record)". Queue and run state is held on a single volume with no
off-project copy; recoverability after a project or account loss is not established.

State below is read-only, dated 2026-11-06 between about 14:10Z and 14:50Z, and is a reading, not clearance: the archived copy of this file carries dated readings that are never current on the day of the window (the go-day step in Part 2 re-runs every command). Every CI claim names
the workflow, the run kind (the GitHub event), the run id, the SHA and the job or leg, because a
green run of the wrong kind or leg is not evidence for the property it is cited for.

## Research Reconciliation - Spec vs. Codebase

| Claim carried into this task | Reality read on 2026-11-06 | Plan response |
|---|---|---|
| "ci.yml merge_group run 42223420689 on d802784259 is green (job coverage of the infra leg unverified)" | `ci.yml` has no infra leg: its test legs call `scripts/test-all.sh` with `webplat`, `bun`, `scripts` and `scripts-heavy` only (`.github/workflows/ci.yml` lines 1493, 1529, 1706, 1819), and the nested infra runner runs only under `TEST_GROUP=all` or `infra` (`want_infra` in `scripts/test-all.sh`). The infra runner runs in `Infra Validation` (`deploy-script-tests (n/4)`; triggers are push and pull_request on infra paths, no merge_group) and in the Main Health Monitor `test-infra` leg. | The ci.yml run is Guard 1 evidence (row a2) and nothing else. It is not evidence for #12213. The "unverified" label is replaced by this reading. |
| #12213 clears on "a Main Health Monitor, merge-queue or dispatch run" | The failing suite `apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh` is in shard leg 4 of `apps/web-platform/infra/suite-shard-legs.tsv`; no merge-queue run runs it. Infra Validation push run 42216139949 on d1f7602ef8 (contains the fix) is green with that suite printed PASS. | CTO ruling T1: the Infra Validation run is supporting evidence only; row a1 waits for a Main Health Monitor `test-infra` leg. |
| #9927 Operator Holds: "follow-through re-look of #10972 (the orphan-sweeps monitor), from 2026-11-09T00:00:00Z" | #10972 was closed 2026-10-29 with a comment recording it as overtaken by events: the monitor was destroyed by PR #11535 (merged 2026-10-29T22:58Z) and the re-look probe retired; `scripts/followthroughs/orphan-sweeps-relook-10972.sh` does not exist on main. | The 2026-11-09 re-look gates nothing. Recorded in the appended #9927 comment (a note, never a body edit). Decision row R-orphan. |
| Ruling D6 text letters the dead-man alert PR as (e), #11265 as (f), the host-token downgrade as (g) | The ADR-282 addendum paragraph "Preconditions for the bundled window" letters them (a) to (g) differently: (c) bundle plus dead-man PR, (d) probe write, (e) per-command go, (f) #11265, (g) host-token downgrade. | This plan uses the addendum paragraph's lettering, as the task brief does, and splits rows where a letter holds two classes. |
| #11266 body: dead-man needs `query_period = 2592000` | The ADR-282 addendum "Count-variable form, defined" and "Above-900 s caveat, corrected" supersede it with a ladder (a 26 h window of about 93600 to 97200 s is the first thing to try; refusal is then an owner decision). The 2026-10-30 comment on #11266 and ADR-218's 2026-10-30 amendment add the heartbeat-feeder pattern, which is on main (PR 11653). | Row d points at the ADR ladder and invents no design. |
| "no Main Health Monitor run exists yet on a main SHA containing 6810a37793" | Holds: newest run is 42171723678 (06:00Z, 7e5c496ceb, failure). The 12:00Z slot has no run listed as of 14:16Z; the cause was not read. | Row a1 is `waiting`, with the 18:00Z slot as the next expected one and the missing slot noted as unexplained. |

## Research Insights

**Premise validation (Phase 0.6).** All cited issues were read: #9927, #11265, #11266, #12158,
#12213, #12221, #12229 and #12230 are OPEN; #10972 is CLOSED (see above); #11631 is CLOSED;
#8528, #7671, #9377, #8620 and #12190 are OPEN; #9786 is CLOSED. Fix commit 6810a37793 (PR 12210,
a bootstrap pin bump) is on `origin/main` and is not an ancestor of 7e5c496ceb. The collision
pre-check found one open change naming #9927 (this PR, #12245) and two `test-all.sh` processes
owned by an unrelated worktree (`feat-one-shot-10390-residual-chores`), which do not touch this
epic. Mechanism check against the ADR corpus: the window shape (replace, then resume, then the
new write path, then flip-read, then revoke) is ruling D2 as recorded; nothing here proposes an
alternative that ADR-282 rejected.

**Property list (Phase 0.6b).** P1 each D6 precondition has a class, a read-only command that
clears it, and a dated state. P2 every CI claim names workflow, run kind, run id, SHA and leg.
P3 the D2 order is stated with a named rollback per step. P4 dates are a proposal, with the gating
dates and the dependency chain. P5 the owner list is actions only. P6 nothing is dispatched,
edited, closed or committed as spend. P7 stale holds and mismatched lettering are surfaced.

**Cut list.** (1) A separate runbook file: cut, this plan is the one document, so the ledger has
one copy and cannot drift. (2) A new ADR-282 addendum: cut, no architectural decision is made
here; the rulings are rows in `decision-challenges.md`. (3) A script that evaluates the ledger:
cut, it would be a new autonomous surface for a document read a few times; the commands are
copy-run. (4) A follow-through tracker for window readiness: cut, #11266 (2026-11-09) and #12229
(2027-01-08) already carry dates. (5) Any UI or wireframe: not applicable.

**Institutional learnings applied.** Name the workflow step that runs a suite before citing it as
a gate (`knowledge-base/project/learnings/2026-06-16-infra-test-orphan-suites-and-node-options-env-file-clobber.md`);
a green from a path that never ran is not evidence
(`2026-07-15-a-guard-that-never-ran-has-more-than-one-reason-and-indexof-block-scoping-swallows-siblings.md`);
a go names one command (`2026-04-19-menu-option-ack-not-authorization-for-prod-writes.md`).

<!-- lint-infra-ignore start: a runbook for a held, owner-gated window; it records existing CI dispatches and the owner's gates and prescribes no new human infrastructure step -->

## Part 1 - Precondition ledger for ruling D6 (a) to (g)

Classes: `operator(<category>)` is the owner's alone; `technical` is the CTO's to rule or an agent
to read; `waiting` carries a UTC time. A class is a routing label: it grants nothing and clears
nothing. Every reading below is as of 2026-11-06 and is not clearance; a "met" or "provisional"
cell names its SHA and run id. A row with a read-only command clears only when that command prints
the stated result on the dispatch SHA, within the invalidation rule below. Rows d and e are
in-session acts with no command; they clear by the owner's act, recorded on the tracker.

**Invalidation rule (CTO ruling T3).** This is a re-check rule, not an eight-day freeze. Any merge
that changes a file under `apps/web-platform/infra/` invalidates row b, so row b is always re-run in
full mode on the then-current main tip immediately before the go. A merge to
`.github/workflows/apply-web-platform-infra.yml` or `tests/scripts/lib/inngest-host-replace-gate.sh`,
to `scripts/test-all.sh` or the sole-copy pin files, or to the config bundle or digest of row c2,
invalidates every row: all of them are re-cleared and the window slips if one cannot be. A docs-only
merge invalidates nothing. Rows c1 and c2 are the planned exception to ruling D2's "only documents
land before the window": D6 names them as blocking prerequisites, c1 is a Better Stack alert change that will land under `apps/web-platform/infra/` (the sibling alerts are in `betterstack-logs-alerts.tf`; its exact file is not yet chosen), so it voids any earlier a2 and b reading, and they land before the
window on their own gates, not inside the window session.

| Row | Precondition | Class | State 2026-11-06 |
|---|---|---|---|
| a1 | A Main Health Monitor `test-infra` leg is green on a SHA containing 6810a37793 | waiting (2026-11-06T18:00:00Z; becomes technical if the 2026-11-07T00:00:00Z slot also has no run) | unmet: no monitor run on such a SHA |
| a2 | Guard 1 evidence on the dispatch SHA (ci.yml merge_group or dispatch run, leg `test-scripts (3/8)`) | technical | met at d802784259 (run 42223420689); unmet on tip bd89194eed (`server.tf`, `terraform-target-parity.test.ts` changed since) |
| a3 | The owner closes #12213 | operator(scope) | unmet: #12213 is OPEN |
| b | `inngest-userdata-budget.sh` in full mode on the dispatch SHA | technical | provisional: 424 B headroom at d802784259 and at tip bd89194eed; re-run on the dispatch SHA |
| c1 | The dead-man alert PR (first item of #12230) is merged with its apply read back | technical | unmet: no such PR exists |
| c2 | Probe-carrying config bundle built and digest promoted (#11266), after c1 | operator(production-mutating) | unmet: blocked by c1 and d |
| d | Better Stack dead-man probe production write | operator(production-mutating) | not run; authorised for the window by an "owner decision given in session 2026-11-06 (relayed by the agent; not a signed record)" (O5); that is not a go and is re-asked in session |
| e | A per-command in-session go naming the exact command line | operator(production-mutating) | not given |
| f1 | #11265 (standalone keeper): feasibility default | technical | default OUT, pending f2 (CTO ruling T4) |
| f2 | #11265 recorded in or out of this window | operator(scope) | not recorded |
| g | Item-4 host-token downgrade, a post-replace check (not a pre-go gate) | technical | declared in config; live state not read |

### a1 - Main Health Monitor evidence for #12213 (waiting)

```
git fetch origin main
gh run list --workflow main-health-monitor.yml --limit 6 --json databaseId,headSha,status,conclusion,event,createdAt
git merge-base --is-ancestor 6810a37793 <headSha> && echo contains-fix
gh run view <run-id> --json jobs --jq '.jobs[]|select(.name=="test-infra")|[.name,.conclusion]|@tsv'
```

Clears when a run whose `headSha` prints `contains-fix` shows `test-infra	success`.

State: #12213 is OPEN. Its failing run is Main Health Monitor run 42171723678, event
`workflow_dispatch` (dispatched by the Inngest cron every six hours), 2026-11-06T06:00Z, on
7e5c496ceb, job `test-infra` failure, suite `cloud-init-inngest-bootstrap.test.sh`. 7e5c496ceb
predates the fix commit 6810a37793 (PR 12210, merged 2026-11-06T06:02:18Z; the run was created at 06:00:20Z, before the merge), which is not its ancestor. No
monitor run exists on a SHA containing the fix: the newest listed is that 06:00Z run, and the
12:00Z slot has no run listed as of 14:16Z (cause not read). The monitor closes #12213 itself on a green run, so do not dispatch it. The monitor is dispatched by the Inngest cron (`main-health-monitor.yml` header), the scheduler this window replaces, so a silent slot may be a scheduler fault and not a wait: also read `gh run list --workflow scheduled-inngest-health.yml --limit 3 --json databaseId,headSha,conclusion,event,createdAt` (on 2026-11-06 its newest runs, event `workflow_dispatch` on d802784259 at 14:01Z and 14:16Z, were success). If the 2026-11-07T00:00:00Z slot also has no run, a1 is reclassified `technical` and routed to the CTO.

Supporting evidence, not clearing (CTO ruling T1): `Infra Validation` run 42216139949, event
`push`, SHA d1f7602ef8 (contains 6810a37793), job `deploy-script-tests (4/4)` success, log line
`PASS apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh` and
`registered infra suites: 44 passed, 0 failed, 0 unaccounted (of 44)`. A local run of `cloud-init-inngest-bootstrap.test.sh` on d802784259 passed 296 of 296; it is not Guard 1 evidence and not a CI run. If the next monitor run is red for a different
suite, a1 stays unmet and the new failure is routed to the CTO, never to the owner.

### a2 - Guard 1 evidence on the dispatch SHA (technical)

```
gh run list --workflow ci.yml --event merge_group --limit 10 --json databaseId,headSha,conclusion
gh run view <run-id> --json jobs --jq '.jobs[]|select(.name=="test-scripts (3/8)")|[.databaseId,.conclusion]|@tsv'
gh run view <run-id> --job <job-id> --log | grep -m2 'inngest-luks-sole-copy:'
git diff --name-only <evidence-sha>..origin/main -- 'apps/web-platform/infra/*.tf' apps/web-platform/infra/inngest-luks-sole-copy.test.sh scripts/test-all.sh scripts/suite-shard-legs.tsv plugins/soleur/test/terraform-target-parity.test.ts infra/github/ruleset-ci-required.tf
```

Clears when the log line reads `inngest-luks-sole-copy: 89 passed, 0 failed (89 cases)` for a
`merge_group` or `workflow_dispatch` run, on the dispatch SHA or on an ancestor for which the last
command prints nothing. The path list is the CTO's and is unverified against the suite's own input
list; if it cannot be derived, the stricter default is an exact SHA match.

State: met at d802784259. ci.yml run 42223420689, event `merge_group`, SHA d802784259, job
`test-scripts (3/8)` success, log `inngest-luks-sole-copy: 89 passed, 0 failed (89 cases)`. Not
evidence: ci.yml run 42229510432, event `push`, same SHA, where `test-scripts` and
`test-scripts-heavy` are `skipped`.

Refreshed 2026-11-06T14:50Z: the last command above, run against tip bd89194eed, prints
`apps/web-platform/infra/server.tf` and `plugins/soleur/test/terraform-target-parity.test.ts`, so the
d802784259 run no longer qualifies on the current tip. Row c1's alert change will add a `.tf` file under `apps/web-platform/infra/`, which that path list also covers. A new `merge_group` or `workflow_dispatch` run of ci.yml on the final tip is needed.

### a3 - The owner closes #12213 (operator(scope))

```
gh issue view 12213 --json state,closedAt,stateReason
```

Clears when `state` is `CLOSED`. The agent never closes it; the monitor closes it on a green run,
and the owner may close it earlier or later by their own call.

### b - User-data budget on the dispatch SHA (technical)

```
git fetch origin main
git diff --name-only d802784259..origin/main -- apps/web-platform/infra .github/workflows/apply-web-platform-infra.yml tests/scripts/lib/inngest-host-replace-gate.sh scripts/test-all.sh
bash apps/web-platform/infra/inngest-userdata-budget.sh --cap-only
bash apps/web-platform/infra/inngest-userdata-budget.sh
```

The last two commands run in a clean checkout of the dispatch SHA (the first is information about
what has moved, never a reason to skip them). They render offline and need no credentials. Clears
when, on the then-current tip immediately before the go, the full-mode run exits 0 with headroom at
or above the 384 B policy floor.

State: at d802784259 and again at tip bd89194eed (a detached checkout, read 2026-11-06 about 14:50Z)
`--cap-only` prints stored 32344 B against cap 32768 B, headroom 424 B, and the full-mode run exits
0. Provisional: the first command prints nine paths on bd89194eed (including `cloud-init.yml` and
`server.tf`), the workflow itself runs only `--cap-only` before the destroy, the stubs are length
upper bounds, and the real Doppler token width is unverified, so a pass at 424 B is evidence, not
proof. A user-data payload over the cap is rejected at the CREATE after the destroy has run (the
2026-09-08 stranded host, recorded in the script header). If the full-mode run fails the floor
after c1 and c2 have landed, any fix is an infra merge that voids c2; that is the slip case, not a
reason to dispatch.

### c1 - Dead-man alert PR (technical build, gated by d)

```
gh pr list --state open --search "12230" --json number,title
gh issue view 12230 --json body --jq .body
git grep -n 'inngest_luks_key_probe' origin/main -- apps/web-platform/infra/betterstack-logs-alerts.tf
```

Clears when a merged PR adds the dead-man alert and its apply is read back (ADR-282 addendum:
the dead-man prerequisite stands). State: unmet. The open-PR search prints `[]` for #12230, the first checkbox of #12230 is open, and the config holds the paging alert
`inngest_luks_key_probe_fail` and no dead-man (its file comment says the dead-man is not in this
file, ruling D12). The design ladder and the "count-variable form" are defined in the ADR-282
addendum and are not restated here.

### c2 - Bundle build and digest promotion (operator(production-mutating))

```
gh run list --workflow build-inngest-config-bundle.yml --limit 5 --json databaseId,headSha,conclusion,event,createdAt
git log -1 --format='%H %cI' -- apps/web-platform/infra/inngest-cutover-flip.sh
doppler run -p soleur -c prd_terraform -- bash scripts/betterstack-query.sh --since 3d --grep SOLEUR_INNGEST_LUKS_KEY_PROBE --limit 5
```

Credentials: the third command reads Better Stack through the existing read-only query wrapper
under the `soleur/prd_terraform` Doppler config, as in #11266's close condition. Clears when the
promotion is made (owner go, #11266 steps 2 and 3, with a higher-versioned revert bundle built
first, step 5) and the third command shows a `token=ok rc=0` row from both channels (journald with
`SYSLOG_IDENTIFIER` `inngest-cutover-flip`, and phone-home). An `indeterminate` row means not yet
proven. A replaced host applies the currently promoted bundle over the image-baked script (#11266
step 4), so this row must clear before the replace.

State: unmet. The newest successful bundle build is `build-inngest-config-bundle.yml` run
40332015744, event `workflow_dispatch`, SHA 408c669631, 2026-10-26T13:36Z; the probe was added to
`inngest-cutover-flip.sh` by 4fb4f6acd7 on 2026-10-27T16:33Z, after it, so no probe-carrying bundle
has been built. The Better Stack query (`--since 3d`, run at about 14:30Z) printed no rows and
exited 0; a zero from a log surface is not evidence of absence (ADR-197), and it is consistent
with the probe not being delivered. The live dedicated host runs whichever bundle `INNGEST_CONFIG_DIGEST` points at (#11266), so the promotion delivers the probe to the running host and the first-row check precedes the replace; it is not circular. #11266's own re-evaluate-by date is 2026-11-09.

### d - Better Stack dead-man probe write (operator(production-mutating))

No read-only command clears it; the write is the owner-present create-then-delete of one throwaway
alert described in #11266 and the ADR-282 addendum "Count-variable form, defined". Its result is
recorded on #12230. State: not run. Owner-authorised for the window (hold O5) and re-asked in
session at dispatch; that authorisation is not the per-command go of row e, and it does not cover
#12221 decision 1 (CTO ruling T5).

### e - Per-command in-session go (operator(production-mutating))

Displayed so the owner can name the exact line; displaying it is not the go (display only, not a
go):

```
gh workflow run apply-web-platform-infra.yml -f apply_target=inngest-host-replace -f reason='<one sentence>'
gh workflow run cutover-inngest.yml -f op=resume
```

Before the go, read-only: for each status in `queued`, `waiting`, `in_progress`, `gh run list --workflow apply-web-platform-infra.yml --status <status> --json databaseId` must print `[]` (no replace in flight or parked on an approval; the double-replace hazard). The `op=resume` run then
waits for the `inngest-cutover` environment approval, which is the owner's. State: not given. The
rest of the runbook's A1 prerequisite list (low-traffic window, quiesce op, replay check, stock
preflight and destroy-guard) is unchanged and is re-read on the day:
`knowledge-base/engineering/operations/runbooks/inngest-server.md`, "Production Envelope for the
post-merge acts", rows A1 and A1b, and "Replace duration, and what happens to events during it".

### f - #11265 in or out of the window

```
git ls-files apps/web-platform/infra | grep -i keeper
gh issue view 11265 --json state
```

f1 (technical, CTO ruling T4): default OUT. The first command prints nothing and `STAGED` in
`cloud-init-inngest.yml` names no keeper asset. For IN, all of these must be on main before row b
is run: the image-content PR; the image mint and pin bump (owner); the STAGED and cloud-init PR
after a headroom measurement, under its own freeze; and a bundle that meets the 384 B floor.
Otherwise the keeper rides a later replace. f2 (operator(scope)) is the owner recording the choice;
this PR records none. #11265 stays open either way.

### g - Item-4 host-token downgrade (technical, checked after the replace)

```
git show origin/main:apps/web-platform/infra/inngest-host.tf | grep -n 'access  *='
doppler configs tokens -p soleur-inngest -c prd --json | jq -r '.[]|"\(.name)\t\(.access)"'
```

The second command lists token metadata only and needs a Doppler credential; it proves existence
and access class, not that a token works. State: at d802784259 the config declares
`doppler_service_token.inngest` (`inngest-boot`) with `access = "read"` and
`doppler_service_token.inngest_flip` (`inngest-flip`) with `access = "read/write"`; the live host
still carries its pre-split credential until the replace, and live Doppler state was not read in
this run. The replace gate pins `.change.after.access` for tokens a plan creates (a wrong value
aborts with `reason=doppler_token_access`). The post-replace checks are the runbook's "Flip-token
split", "First replace, in order", steps 2 to 7, not restated here.

## Part 2 - The window and the D2 post-window ordering

**Before the window, each on its own gate.** Row d (the throwaway-alert write), the c1 merge, and
the c2 bundle build, digest promotion and first-row check are separate acts, each with its own
go, and land before the window session. The window session holds only: the go-day re-run (below),
row b in full mode, the owner's go on the replace (row e), the host checks on the new instance, and
`op=resume`. Commands and thresholds for those are the runbook's and are not copied here:
`knowledge-base/engineering/operations/runbooks/inngest-server.md`, "Production Envelope for the
post-merge acts" rows A1 and A1b, "Flip-token split" ("First replace, in order", steps 2 to 7), and
"Replace duration, and what happens to events during it" (expect 15 to 60 minutes plus approval
latency, quiesce op and replay check as window controls, a dashboard approval older than 23 hours
is archived).

**Go-day step.** On the day, before the go, re-run every Part 1 command on the then-current tip and
record the output in the session. A row that was cleared earlier is re-read, not carried: if
#12213 has re-opened or a new suite is red, a1 and a3 are unmet; if any whole-ledger class of merge
landed (Part 1 invalidation rule), every row is re-cleared. A row that cannot be re-cleared moves
the window; it is never overridden.

**Noise to expect in the dark window.** A "Drift Detected" issue naming the pending replace (runbook
"Flip-token split"); the paused alert `inngest_cutover_flip_silent` stays quiet while paused; any
armed dead-man from c1 may fire while the host is dark if its window overlaps (check at the c1
design, not assumed). Tell the owner before the go.

**If the replace aborts or part-completes.** Stop and wait for a fresh owner go; the owner must be
present. Read the apply run's recovery block and take the route the runbook's "State to dispatch
matrix" names. Rows b and e are spent and are re-cleared (a fresh full-mode run and a fresh
per-command go) before any re-dispatch; an invalidating merge in between voids more. The arm token
must be intact: `op=resume` and `op=rollback` consume it, so step 4 (the revoke) is never run
before the window or between an aborted attempt and its recovery. An inherited `done` is recovered
by `op=resume`, never by a second replace.

**Post-window sequence (ruling D2).** Steps 2 to 4 land after the window because the window's
inherited-done preflight reads with the flip-read token and `op=resume` consumes the arm token; a
change to either moves the dispatch SHA and invalidates row b. If no window has happened by about
2026-12-08, steps 2 and 3 may move earlier with the dispatch SHA re-checked; the owner decides
that on that date (Part 4 item 3).

| Step | What | Rollback (named) |
|---|---|---|
| 1 | Host replace plus `op=resume` (delivers items 2 and 4; row g's checks follow it) | None for the replace itself: a replace has no revert (runbook A1 row). Recovery routes: the abort paragraph above; the "State to dispatch matrix"; a pre-built higher-versioned revert bundle for a bad probe bundle (#11266 step 5); `op=rollback`, the only web-scheduler re-enable, which needs the arm token intact. |
| 1a | Re-arm the paused alert `inngest_cutover_flip_silent` (#12221 decision 2) after the first post-replace `noop-*` row (CTO ruling T5); a merge-apply, technical | Revert the PR so the alert is `paused = true` again, then the ordinary merge apply. |
| 2 | Build and prove the new write path (D1, D1b, D1c; neither verb retired). The apply that creates the new Doppler token is an owner go | Revert the build PR: the arm token stays the live path until step 4. To remove the new token later, follow design doc "Rollback" for the new token (resource, `-target` line, credential step, census name, then an owner-gated destroy or revoke, then delete the environment secret) and record on #12158. |
| 3 | Move flip-read delivery to Tier B (`soleur-infra-privileged/prd`) | Revert the PR so the preflight reads the repo secret again. This works only while step 4 has not removed that secret; as the design is written it names no removal at this step. |
| 4 | The revoke change, then an owner-gated destroy. Precondition (soak): the new write path was exercised by a real gated `op=resume` or `op=rollback` run, or the design's authenticated Doppler check, on a tip that contains steps 2 and 3 | Re-mint with `-replace=doppler_service_token.inngest_arm_write` (documented in the file), then re-run the relay script; record date and evidence on #12158. After step 4, steps 2 and 3 are no longer revertible by a PR alone. `inngest-arm-write-token.tf` is never deleted whole (it defines the `inngest_cutover` environment). |

Design detail, test pins and the `write_token_stale` refusal are in
`knowledge-base/project/specs/archive/20261106-103523-feat-one-shot-9927-record-owner-decisions-a6-refresh/arm-token-replacement-design-12158.md`.
Condition 1 of the epic close conditions (R6: the replace delivered items 2 and 4) is evidenced by
row c2's first-row check, the flip-unit rows, and row g's checks; conditions 2 to 7 are not moved by
the window and stay the owner's.

## Part 3 - Date PROPOSAL (not a commitment)

No date is set (hold O3). The owner sets, moves or rejects every date below (Part 4 item 3). The
dependency chain fixes the order; the dates are only a proposal.

| Date (UTC) | Kind | What it is |
|---|---|---|
| Fri 2026-11-06 18:00 | waiting | Next Main Health Monitor slot (00, 06, 12, 18 UTC); first chance for row a1 |
| Sat 2026-11-07 00:00 | waiting | Expiry of a1 as a pure wait (see row a1) |
| Mon 2026-11-09 | waiting | #11266 re-evaluate-by date. The orphan-sweeps re-look that the #9927 Operator Holds list for this date is superseded (#10972 closed 2026-10-29, monitor destroyed by PR #11535) and gates nothing |
| Tue 2026-12-08 | outer bound | D2: if no window has happened by about this date, steps 2 and 3 may move earlier with the dispatch SHA re-checked |
| Fri 2027-01-08 | outer bound | Arm-token revisit date (#12229); with no replace by then, the revisit decision is recorded on #12158 anyway |

Dependency chain (an arrow means "must clear first"):

```
a1 (monitor green) --> a3 (owner closes #12213) -----------------------------+
d (owner-present throwaway write) --> c1 (dead-man PR merged, apply read back) --> c2 (bundle + digest + first-row check) --> go-day re-run --> b (full mode, tip) --> e (go) --> replace --> resume --> g checks --> D2 steps 1a, 2, 3, 4
a2 (Guard 1 on the final tip, after c1) -------------------------------------+
f2 (#11265 in/out) ---------------------------------------------------------+
```

Proposal: week of Mon 2026-11-09, write the dead-man alert PR (agent) and hold the owner-present
write d, then merge and read the apply back; week of Mon 2026-11-16, build and promote the bundle
and read the first probe row on both channels (the probe emits daily while healthy; the delay from
promotion to first row was not measured, so allow a full cadence plus pull latency); a new ci.yml
`merge_group` run on the final tip for a2; window **not before Mon 2026-11-23**, proposed **Tue
2026-11-24** with **Tue 2026-12-01** as the fallback, both ahead of the 2026-12-08 bound. The
not-before date is the end of the chain above plus about a week of slack for the unmeasured
first-row delay. Between promotion and the window, ordinary infra merges only force a row b re-run;
a whole-ledger merge slips the window. The hour is the owner's to pick for low traffic. This
proposal does not set the date.

## Part 4 - Owner actions

Worded as actions, each with its class. None is asked in this run; each falls due at the time
shown. No item is a technical fork: evidence bars, the invalidation rule and the keeper default are
CTO rulings recorded in `decision-challenges.md`.

1. Close #12213 once row a1 is cleared (operator(scope)). The monitor may close it first.
2. Decide the #11266 re-evaluation on or before 2026-11-09 (operator(schedule)): keep the date, set
   a new one, or tie it to the window date.
3. Set the window date and a low-traffic hour, or reject the Part 3 proposal; and on 2026-12-08, if
   no window has happened, decide whether steps 2 and 3 move earlier or the window is re-proposed
   (operator(schedule)).
4. Be present for the throwaway-alert write (row d) and give the go in session naming the exact
   command (operator(production-mutating)).
5. Give the go for the bundle build dispatch and, separately, for the digest promotion (c2), each
   naming the exact command line (operator(production-mutating)).
6. Record #11265 as IN or OUT for this window; OUT is the CTO's feasibility default (f2,
   operator(scope)).
7. On the day, give the per-command go for the replace and, separately, approve the
   `inngest-cutover` environment gate for `op=resume` (row e, operator(production-mutating)).
8. After the replace, record the arm-token revisit decision on #12158 (the "next host replace" half
   of the trigger fires), then close tracker #12229 and remove its label: keep with a new date at
   most 90 days out and a freshly enrolled tracker (operator(scope)), or revoke, which is its own
   go, as are the step 2 apply that creates the new Doppler token and the step 4 destroy
   (operator(production-mutating)).
9. Only if the Better Stack incident 1047829421 does not clear on its own: give a per-command go for
   any hand-write on it (#12221 decision 1, operator(production-mutating)); it is outside the window
   and separate from row d.
10. Close #9927 only when the R6 conditions hold (operator(scope)); the A6 record, the off-project
    copy decision and the other R6 conditions remain the owner's and are not touched here.

<!-- lint-infra-ignore end -->

## User-Brand Impact

- **If this lands broken, the user experiences:** a ledger that reads a precondition as cleared
  when it is not, so an owner dispatches a replace of the sole scheduler host and every scheduled
  agent run, reminder and webhook-driven job stops until `op=resume` completes; a failed Stripe
  `invoice.payment_failed` delivery in that window can be lost permanently.
- **If this leaks, the user's data is exposed via:** nothing in this document carries a secret, a
  token value or customer data; it names Doppler config paths and secret names only.
- **Brand-survival threshold:** `single-user incident`
- **Threshold decision (challengeable):** chosen over `aggregate pattern` because the act the
  document prepares touches a sole scheduler and a sole-copy volume, and the fail-safe default
  applies when user data is at stake; the PR itself adds no code and no production write.

CPO sign-off is required at plan time (`requires_cpo_signoff: true`); see Domain Review.
`soleur:engineering:review:user-impact-reviewer` runs at review time.

## Domain Review

**Domains relevant:** engineering, product (sign-off only)

### Engineering

**Status:** reviewed
**Assessment:** One batched CTO spawn (spawn 1 of the 2-spawn cap) ruled T1 to T5, persisted as
rows in `decision-challenges.md`: the evidence bar for a1 (stricter option), Guard 1 evidence as a
precondition (a2), the freeze rule, the #11265 default (OUT), and the re-arm placement (after the
window). Other domains: no vendor, expense or provisioning change (operations, finance: none);
CLO rulings L1 to L4 and C1 to C11 are carried by pointer and no new legal posture is authored
(the L3 vocabulary limits are met by Acceptance Criterion 7).

### Product

**Status:** reviewed (plan-time CPO sign-off, scoped to plan fitness; it clears no ledger row)
**Assessment:** CPO verdict `yes with conditions`, 2026-11-06. The nine conditions were applied in
the revision that followed plan review: reading-not-clearance banner and SHA or run id on every
"met" cell (Part 1 intro, rows a2 and b); rows a2 and b void once c1 merges; row b's "reading
stands" shortcut removed; row g marked a post-replace check; Part 2 limited to the window session
with c1, c2 and d on their own gates; row e's in-flight check over `queued`, `waiting` and
`in_progress`; an expiry for a1 (2026-11-07T00:00:00Z slot); a go-day re-run step and an archived-copy
banner; the L3 label and "not a go" on row d; and "default, pending f2" on row f1.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Plan the single bundled Inngest host-replace window for epic #9927 (docs only)." [brief] | This document; Phases 1 to 3 | mapped |
| 2 | "A precondition ledger for ruling D6 (a)-(g). Each row has a class (operator(<category>) / technical / waiting), the exact read-only command that discharges it, and its state as of 2026-11-06." [brief] | Part 1 | mapped |
| 3 | "State the CI run kind and leg with every CI claim." [brief] | Part 1 rows a1, a2; Overview | mapped |
| 4 | "The D2 ordering (host replace + op=resume, then the new write path, then flip-read to Tier B, then the revoke change) as the post-window sequence, with a named rollback per step." [brief] | Part 2 | mapped |
| 5 | "A date PROPOSAL (not a commitment) with the gating dates 2026-11-09 (#11266 re-evaluation, and the orphan-sweeps monitor re-look) and the dependency chain." [brief] | Part 3 (the orphan-sweeps date is reconciled as superseded) | mapped |
| 6 | "The owner-question list worded as ACTIONS (never technical forks)." [brief] | Part 4 | mapped |
| 7 | "Then append a comment (not a body edit) to #9927 linking the doc." [brief] | Phase 3, ship-time task | mapped |
| 8 | "The PR body says \"Ref #9927\", never Closes/Fixes." [brief] | Phase 3 | mapped |
| 9 | "Do NOT dispatch anything, edit any issue body, close #9927/#12158/#12213/#11265, touch inngest-arm-write-token.tf, sign or draft anything for A6, or commit spend." [brief] | Overview; Acceptance Criterion 8 | mapped |
| 10 | "Persist every decision as a row of the `\| Item \| Class \| Ruling \|` table in knowledge-base/project/specs/<branch>/decision-challenges.md" [brief] | `decision-challenges.md` | mapped |
| 11 | "Ship via the normal pipeline with auto-merge once checks pass." [brief] | Phase 3 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Part 1 ledger | "A precondition ledger for ruling D6 (a)-(g)." | asked |
| Part 2 | "The D2 ordering" | asked |
| Part 3 | "A date PROPOSAL (not a commitment)" | asked |
| Part 4 | "The owner-question list worded as ACTIONS" | asked |
| Research Reconciliation table | "State the CI run kind and leg with every CI claim." | asked (asks 3 and 5 need the stale-hold and lettering facts surfaced) |
| `decision-challenges.md` | "Persist every decision as a row" | asked |
| Invalidation rule paragraph in Part 1 | "(b) inngest-userdata-budget.sh --cap-only on d802784259 gives 32344/32768 B (424 B headroom) and must be re-run on the real dispatch SHA." | asked |
| Part 2 "Before the window", go-day and abort paragraphs | "Plan the single bundled Inngest host-replace window" | inferred - justification: the post-window sequence and the ledger are only meaningful relative to what the window contains and what happens when it aborts (plan-review spec-flow and CPO findings); the paragraphs point at runbook rows and add no new owner step beyond Part 4 |
| Row a2 (Guard 1) | "state the CI run kind and leg with every CI claim" | inferred - justification: CTO ruling T2 makes Guard 1 evidence on the dispatch SHA a precondition (R3 names it) |

### Split Assessment

- Subsystems touched: 1 - knowledge-base
- Planned files: 3 | Estimated changed lines: about 420
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Open Code-Review Overlap

None. The open `code-review` issues were searched for the two paths this plan creates and for
ADR-282; the one hit on `knowledge-base/project/plans` (#3151, a generic CI persistence design) is
unrelated and is acknowledged, not folded in.

## Implementation Phases

### Phase 1 - Refresh the ledger on the ship day

Re-run every command in Part 1 (including the go-day step's list) and compare with the stated state. Where a state moved, append a
dated `Refreshed <UTC time>:` line under the row; never rewrite the earlier reading. Do not
dispatch the Main Health Monitor, do not close any issue, do not run any production write.

### Phase 2 - Lint and checks

Run the checks in Acceptance Criteria 2 to 9. The repo's markdown lint and the
`scripts/lint-infra-no-human-steps.py` run must pass on the file.

### Phase 3 - Ship

Normal pipeline, auto-merge once checks pass. The PR body carries `Ref #9927` and no closing
keyword. After the merge, append (do not edit the body of) one comment to #9927 that links this
document at its merge-commit path, states that the 2026-11-09 orphan-sweeps re-look hold is
superseded (#10972 closed 2026-10-29, monitor destroyed by PR #11535, probe retired), and repeats
a line stating that nothing was dispatched, applied, revoked or closed and nothing was drafted for the A6 record. Ship archives this file, so
resolve the path from the merge commit with `git ls-tree -r --name-only <merge-sha> | grep inngest-host-replace-window`.
Do not post to GitHub during planning.

## Files to Create

- `knowledge-base/project/plans/2026-11-06-docs-inngest-host-replace-window-plan.md` (this file)
- `knowledge-base/project/specs/feat-one-shot-9927-host-replace-window-plan/decision-challenges.md`
- `knowledge-base/project/specs/feat-one-shot-9927-host-replace-window-plan/tasks.md`

## Files to Edit

None.

## Acceptance Criteria

- [x] 1. The file has exactly four unfenced headings starting `## Part ` (`grep -c '^## Part ' <file>` prints 4) and ten ledger row headings (`grep -c '^### [a-g]' <file>` prints 10).
- [x] 2. Every paragraph that cites a CI run id also names its run kind: `awk -v RS= '/(42171723678|42216139949|42223420689|42229510432|40332015744)/ && !/(workflow_dispatch|[`]push[`]|merge_group)/' <file>` prints nothing.
- [x] 3. Part 2's step table has rows 1, 1a, 2, 3 and 4, each with a non-empty last cell (`awk '/^## Part 2/,/^## Part 3/' <file> | grep '^| [0-9]' | awk -F'|' '$4 ~ /^ *$/' | wc -l` prints 0).
- [x] 4. Part 3 contains the word PROPOSAL and the dates 2026-11-09 and 2026-12-08, and says the orphan-sweeps re-look is superseded.
- [x] 5. Part 4 contains no question mark (`awk '/^## Part 4/,/^<!-- lint-infra-ignore end -->/' <file> | grep -c '?'` prints 0).
- [x] 6. The L3 vocabulary limits hold (patterns are bracket-split so this line does not match itself): `grep -nEi 'backed[ ]up|recoverabl[e]|complian[t]|DPA[ ]in[ ]place|approved[ ]by[ ]the[ ]CLO|owner-signe[d]|ready[ ]to[ ]attes[t]|pending[ ]attestatio[n]' <file>` prints nothing, and `grep -nE '\b(signe[d]|attest[e]d)\b' <file> | grep -v 'not a signed record'` prints nothing.
- [x] 7. Nothing is dispatched or edited: `grep -n 'gh workflow ru[n]' <file>` hits only the two lines inside the fenced block marked "display only, not a go"; `git diff origin/main...HEAD --name-only` lists only paths under `knowledge-base/` (the three files, ship's archive move, and the pipeline-written `knowledge-base/INDEX.md` and `specs/<branch>/session-state.md` if present); `git diff --quiet origin/main...HEAD -- apps .github scripts plugins` exits 0.
- [x] 8. `python3 scripts/lint-infra-no-human-steps.py knowledge-base/project/plans/2026-11-06-docs-inngest-host-replace-window-plan.md` exits 0; the PR body matches `Ref #9927` and does not match `(Closes|Fixes|Resolves) #9927`.
- [x] 9. `decision-challenges.md` carries the rows T1 to T5, T4-o, T5-o, O-date, O-go, R-orphan, R-panel, P-thr and P-doc, each with Class in {technical, taste, operator (...)}.
- [x] 10. The Domain Review records the CPO sign-off and the PR carries no other sign-off claim.

## Test Scenarios

- Given the file as shipped, when the commands of rows a1, a2, a3, b and f are re-run read-only, then each prints what the row's State paragraph says, or a later `Refreshed` line explains the difference.
- Given a mutation that removes the event word (`push`) from the paragraph of run 42229510432, when Acceptance Criterion 2 is applied, then it prints that paragraph.
- Given a mutation that empties the rollback cell of step 3, when Acceptance Criterion 3 is applied, then it prints 1.
- Given a mutation that adds one of the L3-banned words anywhere in the file, when Acceptance Criterion 6 is applied, then it prints that line.
- Given a mutation that adds a closing keyword for #9927 to the PR body, when Acceptance Criterion 8 is applied, then it fails.

## Sharp Edges

- A green run of the wrong kind or leg is not evidence: `ci.yml` has no infra leg, `Infra Validation`
  has no `merge_group` trigger, and a `push` run of ci.yml skips the sharded legs (Part 1, rows a1, a2).
- Ship archives this file. Link it by the merge-commit path, not the plans path.
- The ledger is time-sensitive. A stale `State` line is a defect; refresh with a dated line.
- Do not dispatch the Main Health Monitor to clear #12213; it clears itself.
- Avoid the L3 words in any follow-up edit; grep before committing.
- Output from `gh run view --log` is large: always pipe to `grep -m` as shown.
- The collision pre-check reports `test-all.sh` processes from another worktree; they are unrelated
  to this epic and are noted, not acted on.
