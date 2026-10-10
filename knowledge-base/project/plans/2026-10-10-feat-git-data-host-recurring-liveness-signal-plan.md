---
title: "git-data host: recurring off-host liveness signal (flip precondition)"
date: 2026-10-10
slug: git-data-host-recurring-liveness-signal
branch: feat-one-shot-9438-git-data-liveness-signal
issue: 9438
type: feat
priority: p2
domain: engineering
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
lane: cross-domain
---

# git-data host: recurring off-host liveness signal (flip precondition)

## Enhancement Summary

**Deepened on:** 2026-10-10
**Sections enhanced:** 4 (Downtime & Cutover added, Network-Outage Deep-Dive added, verification record added, no content removed)
**Agents and passes used:** the plan-phase fan-out already ran 2 research agents (repo, learnings), 3 domain leaders (CTO, COO, CPO)
and a 5-seat eng panel (DHH, Kieran, code-simplicity, architecture-strategist, spec-flow). This pass added the mandatory halts
(user-brand, observability, PAT, encryption posture, guard contract, scope check, downtime) and a citation and consistency sweep rather
than a second blanket fan-out over a plan that had just absorbed ten reviews.

### Key improvements

1. A `## Downtime & Cutover` section: the plan makes a pending `hcloud_server.git_data` replace necessary, so the gate fires; it
   records why no zero-downtime path exists for this single-host store and why the plan adds no downtime of its own.
2. A Network-Outage Deep-Dive for the new egress dependencies (Better Stack heartbeat host, Doppler API) with verified and
   not-verified layers named.
3. A verification record: every cited issue and PR resolved live, every rule id resolved, all section literals checked for drift after
   the review rewrite.

### New considerations discovered

- The deepen sweep found no stale literal (`TimeoutStartSec=55`, `state=ok`, `GIT_DATA_HOST_HEARTBEAT_URL`, `push = false` agree across
  every section) and no fabricated or retired rule id (the one `wg-architecture-decision-is-a-plan-deliverable` is migrated and active).
- The uptime heartbeat host is not yet verified reachable from the git-data host; only the Better Stack ingest host is (a
  `boot_complete` row exists since the 2026-09-25 replace). The first measured beat is the verification, and the soak read shows
  `ping_fail` if it is not.

## Overview

The git-data host emits no recurring signal of its own between boots. Its only recurring signal
today is fed from the web hosts: `web-git-data-probe.timer` makes a bounded TCP connect to
`10.0.1.20:22` and pings `betteruptime_heartbeat.git_data_prd`. That beat proves one thing, that
some web host can open a TCP connection to the port (and under Ubuntu 24.04 socket activation even
that is weaker than it reads: `ssh.socket` accepts the connection whether or not the service
behind it works). A full disk, an exhausted inode table, a closed or unmounted LUKS store, a failed
unit, or a dead web fleet are all invisible to it.

This plan adds a **host-originated** liveness signal and records it as a flip precondition:

1. A timer on the git-data host runs a feeder every 60 s. The feeder checks the host's own
   health and pings a **new, dedicated** Better Stack heartbeat (`soleur-git-data-host-prd`) only
   when every check passes. Absence of the ping is the alert. When a ping is withheld the feeder
   also says why, off-host, through the existing `git-data-emit` channel.
2. The heartbeat URL reaches the host at runtime through the existing scoped read-only Doppler token
   (`prd_git_data`), never through `user_data`. That keeps it out of the rung-2 hash input and makes
   a rehearsal host structurally unable to ping the production monitor.
3. The monitor is born **paused** and is armed only after a measured first beat from the replaced
   host (ADR-117). Merging does not turn the merge-time apply red, and arming is a separate,
   owner-authorized production write that this change neither performs nor schedules.
4. The cutover runbook gains a hard flip precondition that names the signal, how to read it without
   SSH, and what "satisfied" means, re-read at flip time.
5. The payload edit is bundled with the hash-bound comment-only fix still pending on #8093, so one
   rung-2 rehearsal and one host replace cover it. The replace itself stays the owner's decision.

**Closing #9438 (explicit, per the brief).** This PR (the payload PR, #9936) uses `Refs #9438`, never
`Closes`: at its merge the signal exists nowhere, the host carries none of it, and the monitor is
paused. The rung-2 evidence-only PR is restricted to one file by Guard 4, so it does not carry the
close either. `Closes #9438` belongs to the **dependent record PR** that lands after the owner's
replace and the measured first beat: it removes `arming_pending` from the manifest row, ticks the
runbook precondition with the run evidence, and closes the issue. See "PR sequence and who closes
what".

## Research Insights

### Premise Validation (Phase 0.6)

| Cited premise | Check | Result |
|---|---|---|
| #9438 open, targets this work | `gh issue view 9438` | OPEN, labels p2/chore/engineering, no closing PR |
| #8211 umbrella, #8093 follow-up tracker | `gh issue view` | both OPEN |
| PR #9440 only cites #9438 | `gh pr view 9440` | MERGED; cites #9438 as a follow-up gap, no collision |
| Draft PR #9936 for this branch | `gh issue view 9936` | OPEN draft, `WIP: feat-one-shot-9438-git-data-liveness-signal` |
| "#8209 ADR then #8573 follow" | `gh issue view` | both OPEN; out of scope for this PR (any Doppler use there is the owner's call) |
| "The host has emitted no recurring off-host signal since `boot_complete` on 2026-09-25" | ADR-239 addendum; `git-data.tf` | TRUE for host-originated signals. STALE as stated: a web-fed recurring beat exists (`git_data_prd`, ADR-117, #6548/#8754). It reads TCP-22 reachability only |
| "Bundle with the next git-data template change; #8093 already needs one" | `gh issue view 8093 --json comments`; `git grep` | TRUE and still unfixed on `origin/main`: the stale "operator root path the cutover uses" prose survives in `git-data-pre-receive.sh` and `git-data-pre-receive-placeholder.sh` (content anchor: that exact phrase). Only `git-data-pre-receive.sh` is bound by `modules/git-data-userdata/main.tf`; the placeholder file is bound nowhere, so editing it is inert for the hash. No open PR or branch carries the #8093 payload batch, so this PR is the carrier |
| "The host payload is hash-bound; use the two-PR sequence" | `git-data-rung2-rehearsal.md` §Changing the payload | TRUE. Evidence file `git-data-rung2-boot-evidence.env` exists on `origin/main` and must be deleted in the payload PR |
| ADR corpus: is a host-originated heartbeat for git-data an explicitly rejected mechanism? | grep of `decisions/` | NO. ADR-103 records git-data as class (b) "still an unshipped follow-up (#6548)" only because the web probe came first. ADR-198 rejects a log shipper for git-data (quota), which is why the issue says "no Vector". Neither rejects a host timer |

### Property List (Phase 0.6b)

- **P1.** A dead, wedged, full, or store-less git-data host raises an alert within about six minutes
  (period 60 s + grace 300 s), with no web host in the path.
- **P2.** The signal originates on the host and, when withheld, records why, readable without SSH.
- **P3.** A rehearsal or scratch host cannot ping the production monitor.
- **P4.** The alert reaches the owner (email plus the account-level Slack integration, ADR-260).
- **P5.** The flip is not booked until the signal is live and measured; the precondition is recorded
  and has a read-only verification.
- **P6.** The host is replaced once for every hash-bound change that is ready, and no agent performs
  or dispatches the replace.
- **P7.** No false green and no red merge: the monitor is born paused and armed only after a
  measured beat.

### Cut List (Phase 0.6b, extended by plan review)

| Mechanism | Property it would buy | Why cut / what already covers it |
|---|---|---|
| Logs-based dead-man alert (`logtail_exploration_alert`, the `luks_monitor_host_timer_dark` shape) | P1 | Needs a periodic emit (still a payload edit), is born armed (false alert before the host carries it), depends on ingestion lag (#7855 addendum) and on log quota (#4296, #7577). The native heartbeat is absence-alerting by construction |
| Vector or any log shipper on git-data | P2 | ADR-198 / C4 edge: structurally cannot reopen the quota breach; the issue itself says "no Vector" |
| `OnFailure=` reporter unit for the feeder | P2 | A crashed or unarmed feeder produces no ping, and the missing ping IS the alert; a reporter adds a unit, a routed stage and a Sentry rule |
| Routing the diagnostic event as a `warning` stage | P2 | Needs a new stage in `issue-alerts.tf` plus set-equality edits in `sentry-git-data-warning-stages-op-contract.test.ts`. The page is the heartbeat; the event only explains, so it is `info` and deliberately unrouted |
| Machine enforcement of the precondition inside `git-data-cutover.yml` / `git-data-flag-precheck.sh` | P5 (stronger) | Workflow edit plus a new credential in the dispatch; the issue asks for the runbook record. Deferred to #9943 |
| A scratch heartbeat in the rung-2 rehearsal root | P3 | Rung 2's job is boot, not liveness; the scratch Doppler config lacks the URL by construction, which already gives P3 |
| Cumulative counters (`ok_cum`, `miss_cum`, `ping_fail_cum`, `late_ok_cum`) | P2 | Nothing reads them: `state` and `code` on each event, with `ping_fail` as its own state, already separate the three flapping hypotheses the registry post-mortem could not; grace 300 s dwarfs timer jitter (72.6 s measured against 90 s in the registry learning) |
| Hourly URL refresh with fail-static cache | P3 | Rotation is by replace (ADR-220); the cache is fetched once per boot, retried each tick while empty, and dropped on a ping failure |
| A one-shot `first=1` event per boot | P5 | Replaced by the 10-minute `state=ok` summary, which also proves the feeder is still ticking (a one-shot cannot) |
| `push` flip to `true` in the record PR (COO) | P4 | Email plus the account Slack integration already satisfy P4; recorded as DC-3 |
| ADR-103 and ADR-198 "addenda" | P5 | One new ADR carries the decision; each older ADR gets a one-line pointer, not a section |
| Edits to `git_data_host_replace_gate` or the replace job's `-target` set | P6 | The URL is not in the host's graph (Doppler route), so the scoped recreate set is unchanged and the gate stays exact |
| `arm_one` line for the new monitor in the per-merge arm step | P7 | Would unpause, wait out the deadline, roll back and return rc=1 on every merge until the owner replaces the host |
| Arming modes inside THIS PR | P7 | Nothing in the payload needs them to merge; moved to a small second PR (1b) that lands before the replace |
| Bundling the `AuthorizedKeysFile` move (#8093 item 2) | P6 | Moves a literal five birth-gate arms key on; its own note calls it "its own hash-bound change" (DC-2) |
| Deciding the `gc_timer` paging policy (#8093 item 4) | P6 | A policy decision the owner owns; the feeder leaves `git-data-gc.service` out of its failed-unit set so it neither makes nor hides it |

### Local findings (cited)

- **Existing web-fed beat.** `apps/web-platform/infra/web-git-data-probe.sh` does `nc -z -w 5 10.0.1.20 22` and pings
  `GIT_DATA_HEARTBEAT_URL` on success; heartbeat `git_data_prd` (`git-data.tf`, period 60 / grace 180) rides the per-merge
  `-target` list since #8754 (`apply-web-platform-infra.yml`, `-target=betteruptime_heartbeat.git_data_prd`).
- **Registry precedent for a host-originated feeder.** `zot-liveness-heartbeat.{sh,timer}` in `cloud-init-registry.yml`, manifest row
  `registry_prd` (`arming: "dedicated-host-boot"`, `paused: true`, `replace_target: registry-host-replace`). Its post-mortem
  (`2026-08-03-registry-liveness-heartbeat-flapped-and-recorded-no-cause-postmortem.md`) is the design input for P2: "a feeder that
  only gates cannot explain its own silence".
- **Manifest and parity gate.** `plugins/soleur/lib/heartbeat-manifest.ts` (one row per heartbeat, `feeder` evidence is a file plus an
  arming construct matched on a comment-stripped view, `arming_pending` suppresses only the nightly `fed-but-paused` alarm, not
  `absent-live`); `plugins/soleur/test/heartbeat-reprovision-parity.test.ts` requires a `replace_target` for every
  `dedicated-host-boot` row, and `git-data-host-replace` already exists (`apply-web-platform-infra.yml`, `-replace='hcloud_server.git_data'`).
- **Arm gate.** `arm-heartbeats.sh` arms from a hardcoded `arm_one` list, resolves ids from TFSTATE (never a name regex), requires a
  real `up` transition (a paused monitor exposes no ping timestamp), and rolls back to paused otherwise. `arm_one` returns 0 with a
  notice when the address is absent from state. `registry-heartbeat-poll.sh` documents why a level read of `up` is not evidence of a
  new beat (residual `up` for period plus grace after the old host dies).
- **Doppler path.** `/etc/default/git-data-doppler` (0600) carries the scoped read-only token and `GIT_DATA_DOPPLER_CONFIG`; the
  established read shape is `doppler run --project soleur --config "$GIT_DATA_DOPPLER_CONFIG" --only-secrets <NAME> --no-fallback --`
  (`git-data-luks-reopen.service`, `git-data-luks-reopen-failure.service`), and a root unit needs `Environment=HOME=/root` or the CLI
  dies. `prd_git_data` is provisioned by `doppler_config.git_data_prd` and currently holds two secrets (`GIT_DATA_LUKS_KEY`,
  `BETTERSTACK_LOGS_TOKEN`). `git-data-luks.test.sh` `p_doppler_config_scope` lists its sibling files explicitly.
- **Budget.** `bash apps/web-platform/infra/git-data-userdata-budget.sh --json` measured `stored=25980 cap=32768 headroom=6788`
  on this branch. Three new payloads are expected to cost roughly 1 to 1.5 KB stored.
- **Rehearsal root.** `rung2-rehearsal/rehearsal.tf` writes its own scratch Doppler config (`prd_git_data_rehearsal_<id>`) holding only
  the secrets that file declares; a secret it does not write is absent there by construction.
- **Vendor.** Better Stack is on a paid plan since 2026-08-16 (`knowledge-base/operations/expenses.md`); the free-tier object cap
  ("10 monitors and heartbeats") may no longer bind, but the live count was not measured (it needs the Better Stack API token, which is
  a Doppler read the owner must authorize). A create refused at the cap fails the merge-time apply loudly, not silently.
- **Emit cost.** `git-data-emit` can take roughly 40 to 50 s in a degraded-egress case (Sentry `--retry 2 -m 10`, plus two Better Stack
  POSTs at `-m 10`), so it cannot sit unbounded inside a 60 s tick.

### Institutional learnings applied

- `2026-07-18-shared-delivery-substrate-and-reused-heartbeat-url-masking.md`: a reused heartbeat URL masks the break the new probe is
  for. The new monitor is its own heartbeat; `git_data_prd` stays as it is.
- `best-practices/2026-07-09-terraform-source-guard-must-key-on-arming-class-not-ignore-changes-value.md`: classify by arming class,
  not by source `paused`.
- `test-failures/2026-10-06-which-files-feed-user-data-with-no-ignore-changes-decides-whether-a-mechanical-edit-is-a-host-replace.md`:
  every byte of these payloads, comments included, is a ForceNew replace and a voided attestation.
- `2026-07-15-self-healing-guard-on-a-blind-host-must-fail-safe-on-its-own-instrument.md`: set an explicit `PATH` in the unit (cron's
  default omits `/usr/sbin`); an unreadable measurement must be reported as unmeasured.
- `2026-09-19-every-systemd-claim-i-reasoned-was-inverted-by-a-thirty-second-measurement.md`: `Persistent=` is inert without
  `OnCalendar=`; verify timer behaviour on the real host, not from the man page.
- `2026-10-06-an-argv-bearer-sweep-needed-a-ratchet-a-token-shape-guard-and-a-process-substitution-not-a-pipe.md` and ADR-280: the
  heartbeat URL goes to curl on its stdin config through a process substitution, with a token-shape guard, never on argv.
- `2026-07-16-the-fix-for-an-inert-monitor-shipped-a-probe-that-could-never-fire.md`: test the feeder against a real non-200 responder;
  keep the timer interval well inside the grace.

### Conventions that bind this plan

`hr-all-infrastructure-provisioning-servers` and `hr-prod-host-config-change-immutable-redeploy` (the change reaches the host by
replace, never by editing a running host), `hr-no-ssh-fallback-in-runbooks`, `hr-tf-variable-no-operator-mint-default` (no new
variable), `hr-observability-as-plan-quality-gate`, `hr-menu-option-ack-not-prod-write-auth` (arming and replace need explicit
per-step authorization), `wg-block-pr-ready-on-undeferred-operator-steps`, `cq-write-failing-tests-before`.

## Research Reconciliation: Spec vs. Codebase

| Claim in the brief / issue | Reality | Plan response |
|---|---|---|
| "The git-data host emits no recurring off-host signal" | A web-fed recurring beat exists (`git_data_prd`), proving only TCP-22 reachability from some web host | Keep it. Add a host-originated beat on a separate monitor; state in the runbook exactly what each one proves |
| "Better Stack heartbeat or equivalent that fires from the host, not a web host probing it" | No host-side pinger exists; the manifest has no git-data `dedicated-host-boot` row | New feeder, new heartbeat, new manifest row with `replace_target` `git-data-host-replace` |
| "Bundle with the pending git-data host template change for #8093" | No such change is staged anywhere; #8093 is a backlog tracker | This PR carries the ready hash-bound item (the stale pre-receive comment) and records the held-out items with reasons |
| "Fix-Size: 150 lines / 5 files" (issue) | Three payloads, a feeder suite, two TF resources, manifest, parity tests, two workflow edits, runbook, ADR, C4 | Scope Check below sizes it honestly (about 29 files, about 650 lines) |
| "The runbook flip-precondition list" | `git-data-luks-cutover-5274.md` §Preconditions for the flip has no heartbeat or liveness item (the only heartbeat text is the NIC-readiness read) | Add one hard precondition item with a read-only verification and a flip-time re-read |
| "Better Stack heartbeat created in the same apply as the host" | The host's graph must stay exact for `git_data_host_replace_gate`; the birth route refuses monitors it cannot arm (`GIT_DATA_BIRTH_REFUSED`) | The monitor and its Doppler secret ride the per-merge `-target` list (the #8754 precedent); the host reads the URL at runtime, so the replace set does not change |
| "`git-data-pre-receive-placeholder.sh` is hash-bound" (#8093 comment) | `main.tf` binds `git-data-pre-receive.sh` under the name `git_data_pre_receive_placeholder`; the placeholder file itself is bound nowhere | Edit both comments; only the first moves the hash |

## Open Code-Review Overlap

None. Queried `gh issue list --label code-review --state open` (88 issues) against every path in Files to Edit and Files to Create; no
open scope-out names any of them.

## Problem Statement / Motivation

`mode=flip` in `.github/workflows/git-data-cutover.yml` freezes writes on this host, and the finalizer can only report what it can
reach. The account-deletion route `/api/account/delete`, which erases repositories on this host (GDPR Art. 17), fails silently when the
host is down or frozen. Between boots the host is observable only as "port 22 accepts a TCP connection from a web host". The registry
host went nine days with an inert monitor (#6537) and a week of unexplained flapping (2026-08) for exactly the reasons this design
guards against: a monitor nothing fed, and a feeder that gated without recording why.

## Proposed Solution

### The feeder contract (`git-data-liveness.sh`, hash-bound payload)

Runs as root from a `Type=oneshot` service, fired by a timer (`OnBootSec=3min`, `OnUnitActiveSec=60s`, `AccuracySec=5s`; `Persistent=` is
inert here and is not set). Refuses to run under xtrace. Sets an explicit `PATH` that includes `/usr/sbin`.

| Check | Miss code | Notes |
|---|---|---|
| the loopback SSH listener returns an `SSH-` identification string within 5 s | `ssh_no_banner` | Ubuntu 24.04 is socket-activated, so `ssh.service` can be inactive on a healthy idle host and a unit-state check would false-fail; reading the banner proves sshd answers under either arrangement (ADR-149 #8043 F11) |
| `/mnt/git-data` is a mountpoint | `store_unmounted` | closes the "host up, mapper closed later" residual `git-data-luks-reopen.timer` names and scope-outs |
| the mount source is `/dev/mapper/git-data` | `store_not_mapper` | ADR-239: the store always serves the mapper, never a plaintext device |
| bytes used on the store below 90 % | `disk_full` | a fresh store reads about 1 %; the threshold is a `readonly` constant |
| inodes used on the store below 90 % | `inodes_full` | inodes exhaust at about 55 to 60 % of bytes (`git-data-bootstrap.sh` §6c), so this is the binding one |
| `git-data-luks-reopen.service` and `git-data-nftables.service` not failed | `unit_failed:<name>` | `git-data-gc.service` is deliberately excluded (#8093 item 4 is the owner's policy call). The reopen unit is a `RemainAfterExit` oneshot re-run by a 15-minute timer, so a recovered failure can keep withholding for up to about 17 minutes |
| any gating measurement unreadable | `unmeasured:<check>` | an unreadable instrument withholds the beat; it never reads as healthy |

`/` usage is measured and carried on every event as `root_pct`, but it does NOT gate the ping in this version: its threshold is a guess
nothing has measured on a fresh host, and a false fail would have to be fixed by another payload PR, rehearsal and replace. Promoting it
to a gate is a later, measured change.

Thresholds are `readonly` constants at the top of the script, each with its rationale beside it, exercised at the boundary (one below,
at, one above) by the suite.

**Writers of every on-host identity the checks read** (a guard that reads an identity nothing writes asserts a premise, not a fact):
`/mnt/git-data` is `GIT_DATA_ROOT` in `git-data-bootstrap.sh`, and `git-data-luks-reopen.sh` refuses any fstab target other than it;
`/dev/mapper/git-data` is `STORE_DEVICE` in the bootstrap and `MAPPER_NAME` in the reopen script's `luksOpen`;
`git-data-nftables.service` is a `write_files` entry in `cloud-init-git-data.yml`; `git-data-luks-reopen.service` is the module payload of
the same name; the SSH listener is the distribution's own `ssh.socket`. The falsifier for the premise that all of these read healthy on a
real fresh host is a read-only look at the real replaced host: the feeder's own `info` events during the pre-arm window (PR sequence
step 5), plus the rung-2 rehearsal host's first ticks if it lives past `OnBootSec`. Neither needs a login to the host.

**Ping chokepoint.** One function, `_ping`, is the only place curl is invoked. It validates the URL shape
(`https://uptime.betterstack.com/api/v1/heartbeat/<alphanumerics>`; a newline or quote would inject a curl config directive), then runs
`curl --disable --noproxy '*' -fsS -m 10 -o /dev/null --config -` fed by a process substitution (never a pipe: SIGPIPE under
`pipefail`), so the URL is never in any argument list. Two explicit attempts inside the tick absorb a vendor blip; no curl `--retry`
flag is used (a retry flag can turn a throttled response into exit 0, and its worst case is not the one written down).

**URL source.** `/run/git-data-liveness/url` (dir `0700`, file `0600`, tmpfs, never on the block device; the script creates it, because
`RuntimeDirectory=` would wipe it on every oneshot exit) is fetched once per boot by re-executing the script under
`doppler run --project soleur --config "$GIT_DATA_DOPPLER_CONFIG" --only-secrets GIT_DATA_HOST_HEARTBEAT_URL --no-fallback`, bounded by
`timeout 10`. While the cache is empty every tick retries, with no throttle, so a host replaced before its secret existed heals on the
next tick without a second replace. A ping failure drops the cache so the next tick re-reads (this is the whole rotation story). The
behaviour when the secret is absent depends on `GIT_DATA_DOPPLER_CONFIG` compared by EXACT equality with the production config name
(the rehearsal's is `prd_git_data_rehearsal_<id>`, so a prefix match would misclassify it; the name is not written as a prose literal in
unit comments): in the production config it is `url_unavailable` (reported, no ping, so the monitor pages once armed); in any other
config it is `disarmed` (checks still run and report, no ping). A `doppler` that exits 0 with empty output is an absent secret.

**Why it withheld, and proof it is still ticking.** State lives in `/run/git-data-liveness/state` (one line, validated as plain strings
and non-negative integers on read, reset on a corrupt field): `last_emitted_state`, `last_code`, `last_emit_ts`. The feeder emits
through `git-data-emit` at level `info`, stage `liveness`, message prefix `SOLEUR_GIT_DATA_LIVENESS <state>`, on every state change and
as a `state=ok` summary every 10 minutes while healthy, carrying `state`, `code`, `root_pct`, `config`. The states are `ok`, `miss`,
`ping_fail`, `url_unavailable`, `disarmed`. The 10-minute summary is what makes the soak readable: silence cannot distinguish a healthy
feeder from a dead timer, a dropped log line or a failed emit, but a missing summary can. `info` is queryable (Better Stack source
2734275 and Sentry) and unrouted by design; the heartbeat absence is the page.

**Order inside a tick, and its budget.** checks, then ping (the primary signal), then persist state, then emit. The state is written
before the emit so a killed emit cannot repeat a transition forever; `last_emitted_state` is advanced only after the emit returns 0, so
a failed emit is retried on the next tick. The emit is bounded by `timeout 20` (`git-data-emit` alone can take 40 to 50 s degraded).
Worst case: a 10 s cache fetch, two 10 s pings and a 1 s sleep, a 20 s emit, which is 51 s inside `TimeoutStartSec=55`, inside the 60 s
tick. An emit that fails never changes the ping decision or the exit code.

**Service shape.** `Environment=HOME=/root` (a root unit's Doppler CLI dies without it), `PrivateTmp=yes`, `LimitCORE=0`,
`TMPDIR=/dev/shm`, `EnvironmentFile=-/etc/default/git-data-doppler`, `UMask=0077`, `TimeoutStartSec=55`. Ordering only:
`After=network-online.target` and nothing in the `Requires=`, `RequiresMountsFor=` or `BindsTo=` family, because the feeder must
OBSERVE an unmounted store and a Requires-strength directive would mount it. Exit 0 on every path except xtrace refusal; a feeder that
cannot run produces no beat. The xtrace refusal is spelled `[[ $- == *x* ]]`; the literal text `set -x` appears nowhere in the script
or its unit comments, because `git-data-luks.test.sh` A28a greps raw payload source for it. The feeder never sets
`GIT_DATA_REPO_ROOT` (it would join the device-census population in `git-data-store-device-census.test.sh`) and keeps all state under
`/run`. Its `doppler run` call uses the exact `--config "$GIT_DATA_DOPPLER_CONFIG"` form and the feeder is added to
`p_doppler_config_scope`'s file list in `git-data-luks.test.sh`.

**Where it is armed.** The timer-arming item in `cloud-init-git-data.yml` goes AFTER the `gc_timer` arming item, which is itself after
the bootstrap stage and `boot_complete`, so no tick overlaps the store mount at birth. After a later reboot the timer fires at
`OnBootSec`, and a store that is still closed then is reported as exactly that.

### Terraform

- `betteruptime_heartbeat.git_data_host_prd` in `git-data.tf` beside `git_data_prd`: `name = "soleur-git-data-host-prd"`, `period = 60`,
  `grace = 300`, `email = true`, `call/sms/push = false`, `policy_id` gated on `var.betterstack_paid_tier` exactly like `git_data_prd`,
  `paused = true`, `lifecycle { ignore_changes = [paused] }`. `push` stays `false` (DC-3).
- `doppler_secret.git_data_host_heartbeat_url_prd`: `project = "soleur"` and `config = "prd_git_data"` as LITERALS (the same shape
  `git_data_heartbeat_url_prd` uses with `"prd"`), `name = "GIT_DATA_HOST_HEARTBEAT_URL"`, `value =
  betteruptime_heartbeat.git_data_host_prd.url`, `visibility = "masked"`. The literals are deliberate: a reference to
  `doppler_config.git_data_prd` would put that excluded resource into the per-merge `-target` closure, and if it were ever absent from
  state the plan would try to create it and Doppler would answer 400 "Name is already in use" on every merge. With literals, an absent
  config makes the secret write fail loudly instead. No module variable, no operator-minted default.
- Both ride the per-merge `-target` list (`apply-web-platform-infra.yml`, beside `git_data_prd`), are absent from the host-create
  job's set (`GIT_DATA_BIRTH_REFUSED`), and `doppler_config.git_data_prd` stays an exclusion with no `-target` line of its own.

### Arming tooling (PR 1b, separable, lands before the owner's replace)

`arm-heartbeats.sh` gains two narrow modes that reuse `arm_one`, `bs_api` and the state-file sweep: `--status <tf-address>` (read-only,
prints `status=<paused|up|down|pending>`) and `--arm-one <tf-address> <label> <deadline>`. `--arm` and `--sweep` stay byte-identical.
Four obligations the review named: `--arm-one` must REFUSE (non-zero) on an address absent from state, where `arm_one` itself returns 0
with a notice; its deadline is `period + grace - 40 = 320`, asserted by its own test row because `terraform-target-parity.test.ts`
pins that formula only for single-quoted `arm_one` lines in the `--arm` list; the runbook gives the local command that produces the
`TFSTATE_JSON` snapshot (`terraform show -json` with the backend credentials, an owner-authorized read); and a cancelled local run
must be followed by the existing sweep to re-pause an unpaused-and-unfed monitor. Everything here needs the Better Stack token, a
Doppler read the owner must authorize. If the owner prefers, 1b folds back into this PR; the cost is a larger diff, nothing else.

## Alternative Approaches Considered

| Option | Verdict |
|---|---|
| A. Bake the heartbeat URL into `user_data` (the registry's `liveness_heartbeat_url` route) | Rejected. The rehearsal root renders the same module, so it would carry the production URL and ping the production monitor, or need a closed-allowlist divergence entry the rung-2 gate refuses for WHAT-class values. Also fixes rotation to a replace |
| **B. Runtime read from `prd_git_data` under the baked scoped token (chosen)** | No new variable, rehearsal-safe by construction, same boundary as the LUKS reopen |
| C. Logs-based dead-man alert | Rejected (Cut List) |
| D. Extend the web probe to check store health over SSH | Rejected. Not host-originated, needs a fourth forced-command key (the authorization-map gate pins exactly three), and dies with the web fleet |
| E. Reuse the existing `git_data_prd` URL from the host | Rejected. Masking: any one beat from either source hides the other's silence (learning 2026-07-18) |
| F. Arm in the per-merge arm step | Rejected (Cut List): every merge red until the owner replaces the host |
| G. Pause and unpause the monitor around replaces | Rejected. A production write per replace, and each re-arm needs a new measured beat. The runbook records that an armed monitor pages about six minutes into a planned replace, which is expected |

## Technical Approach

### PR sequence and who closes what

The order is fixed by two repo facts: the runbook requires a FRESH replace plus key rotation immediately before the real cutover (ADR-220
D6), and the host that gets frozen must be the host whose beat was measured. So the replace comes first, the soak and the arm follow it,
and the flip comes last.

| Step | Who | What | Closes |
|---|---|---|---|
| 1. **Payload PR** (this PR, #9936) | agent, normal ship flow | Feeder payloads, cloud-init wiring, module `file()` bindings, budget-script mirror, TF pair, manifest row, per-merge `-target` pair, unit-lint list, registrations, parity rows, runbook precondition, ADR-283 with pointers in ADR-103 and ADR-198, C4 edge text, the pre-receive comment fix, **deletion of `git-data-rung2-boot-evidence.env`** | `Refs #9438`, `Refs #8211`, `Refs #8093` |
| 1a. Merge-time apply | CI | Creates the paused heartbeat and the `prd_git_data` secret. These are two production writes by the ordinary pipeline; the PR body says so | |
| 1b. **Arming tooling PR** | agent | `--status` and `--arm-one` with their tests and the runbook arm section (see Arming tooling). Touches no hash-bound input | `Refs #9438` |
| 2. Rehearsal dispatch on `main` (`--ref main`, `dry_run=false`) | **owner-authorized** workflow dispatch; this plan never dispatches it | Produces the evidence artifact. From step 1a until step 3 merges, `main` carries no valid evidence and every git-data birth and replace refuses, an emergency replace included. The plan recommends the owner dispatch within two working days of the merge; the runbook's "Break-glass for the rung-2 interlock" is the only way through the gap | |
| 3. **Evidence-only PR** | agent, after step 2 | Lands the evidence file alone (Guard 4 refuses any other file in the commit) | `Refs #9438` |
| 3b. Pre-replace read (read-only, owner-authorized token) | agent | `--status` reads `paused` and the `prd_git_data` secret exists. Otherwise the new host boots into `url_unavailable` (it self-heals on the next tick once the secret exists, without a second replace) | |
| 4. Host replace with key rotation (ADR-220 D6) | **owner's decision**; never performed or dispatched by an agent. This is the replace the runbook already requires before the cutover, so this change adds no second replace. The monitor is paused, so this replace pages nothing | | |
| 5. Pre-arm read | **owner-authorized** agent step | `scripts/betterstack-query.sh --grep SOLEUR_GIT_DATA_LIVENESS`, filtered to the production config and to events after the new host's `boot_complete`: require at least four consecutive `state=ok` events spanning at least 30 minutes and no other state after the first `ok`. The 30-minute floor is the owner's to lengthen; a longer soak widens the replace-to-flip interval that ADR-220 D6 wants short (DC-6) | |
| 5b. If the soak fails | owner decides | A `miss` code on a healthy fresh host is a payload defect: fix forward through the two-PR sequence (the thresholds are hash-bound). Only the owner can accept a known-benign miss, by a recorded waiver comment on #9438; an agent never waives. A failed `--arm-one` rolls the monitor back to paused and the flip stays blocked | |
| 6. Arm | **owner-authorized** agent step | `--arm-one` on `betteruptime_heartbeat.git_data_host_prd`: unpause, require a real `up` transition, roll back if none | |
| 7. **Dependent record PR** | agent | Removes `arming_pending` from the manifest row, ticks the runbook precondition with the run ids and times, refreshes the Better Stack ledger row (its `verify_by` estimate is overdue and its "never born" note is stale), and cites one Better Stack incident delivered to the Slack channel since ADR-260 as read-only proof that the account route delivers (DC-4). Touches no hash-bound input, so the evidence from step 3 stays valid | **`Closes #9438`** |
| 8. Flip-time re-read | agent, at the flip dispatch | The precondition is RE-READ, not remembered: `--status` is `up` AND the latest `state=ok` event is under 15 minutes old and later than the CURRENT host's `boot_complete`. A box ticked once goes stale at the next replace; this re-read is the only control until #9943 | |

Closing at step 1 or 3 would assert an acceptance nobody observed: the registry heartbeat shipped, was never armed, and sat inert for
nine days (#6537). The precondition's safety does not depend on the issue's state; the runbook item and its flip-time re-read are the
gate. If the owner prefers closing earlier, step 3's PR body is the only other defensible carrier (DC-1). Hand-offs between steps 4,
5, 6 and 7 are prompts to the owner, not scheduled jobs; #9438 stays open as the visible tracker and #9943 tracks the machine check.

### Implementation Phases

**Phase 0 - measure before writing (read-only).**

- Re-run `bash apps/web-platform/infra/git-data-userdata-budget.sh --json`; record headroom (6788 B at plan time).
- Run `bash plugins/soleur/test/c4-count-parity.test.sh` and `python3 -I scripts/lint-encryption-posture.py` for a baseline (both
  green at plan time), and read `terraform-target-parity.test.ts` rows near the git-data pair to pin the exact classification the new
  pair needs.
- Sweep every `prd_git_data` consumer (`git grep -l prd_git_data`) for a "two secrets" cardinality assumption (comments in
  `git-data-luks.tf`, `rehearsal.tf`, `git-data-luks.test.sh`, `doppler-config-inventory.txt`).
- Bump `BASELINE_DECLARED_PROBES` (53 to 54) in `preflight-discoverability-test.test.ts`: the plan declares `credentials_required`, and
  that ratchet counts every declaring plan the moment the plan is committed.

**Phase 1 - tests first (`cq-write-failing-tests-before`).**

- `apps/web-platform/infra/git-data-liveness.test.sh`: behavioural suite with fakes on `PATH` for the service manager, `mountpoint`,
  `findmnt`, `df`, the loopback banner read, `curl`, `doppler` and an emit spy. Rows: every check passes and fails; each threshold at the
  boundary; two simultaneous misses; URL shape guard (newline, quote, wrong host); the URL absent from every recorded argv and from the
  emit spy's args; xtrace refusal; the production config versus the rehearsal config name (exact equality) on an absent secret;
  cache empty then filled, retried each tick; cache dropped on a ping failure; a `doppler` fake that exits 0 empty; transition emit and
  the 10-minute `ok` summary; an emit spy that fails and a feeder that still exits 0 with the same ping decision; a hung `doppler`
  and a hung emit keeping the whole tick under 55 s; `unmeasured` on an empty `df`; `HOME=/root` present in the unit.
- The Guard Contract mutation matrix below, written before the script.
- Manifest row and parity rows (RED until the TF pair and the cloud-init arming line exist).
- Registration (a glob claim is a claim to measure): regenerate the infra shard manifest, then run
  `bash scripts/lint-orphan-test-suites.sh` after the suite file is tracked and record its verdict.

**Phase 2 - payload.**

- Create `git-data-liveness.sh`, `.service`, `.timer`. Bind each in `modules/git-data-userdata/main.tf` with the exact
  `file("${path.module}/../../...")` spelling and `local.git_data_rationale_strip`, one physical line per entry. Mirror all three in
  `git-data-userdata-budget.sh`. `git-data-luks.test.sh`'s `boot_path_files()` and the birth gate's hash input derive their rosters
  from these bindings, so both pick the files up with no list edit; confirm the floor assertion still holds.
- `cloud-init-git-data.yml`: three `write_files` entries (indent pattern of the `git-data-gc` entries) and one runcmd item, after the
  `gc_timer` item, that arms the timer with the `_rc` capture-and-`if` shape and emits at `info` on failure. The arming line is spelled
  exactly like the registry row's manifest pattern. Do not add a `warning` or `fatal` stage.
- Comment-only edits to `git-data-pre-receive.sh` and `git-data-pre-receive-placeholder.sh` so they stop describing a root path and
  freeze mechanism that no longer exist.
- Add the three payloads to `EXPECTED_PATHS` in `git-data-runcmd-rehearsal.test.sh` (a payload missing from that map exits 1) and verify
  rung 1 passes against the pinned image. Add the new service and timer to `infra-validation.yml`'s unit-lint list and alternation.
  Add the feeder to `p_doppler_config_scope`'s file list.

**Phase 3 - Terraform, manifest, workflow target list.**

- `git-data.tf`: the heartbeat and the secret; update the "Liveness (PUSH heartbeat)" comment block (it says a web-host cron is the
  only feeder) and the "deliberately OUT of this job's -target set" line in the birth job text.
- `git-data-luks.tf`: update the CARDINALITY comment (two secrets becomes three) and its blast-radius sentence.
- `heartbeat-manifest.ts`: row `git_data_host_prd`, `arming: "dedicated-host-boot"`, `paused: true`, feeder `timer` with evidence file
  `cloud-init-git-data.yml` and the registry row's arming-line spelling, `replace_target {git-data-host-replace,
  hcloud_server.git_data}`, `arming_pending: { tracking_issue: 9438 }`.
- `apply-web-platform-infra.yml` (two `-target` lines, per-merge list only) and `infra-validation.yml` (unit-lint list and
  alternation). These are workflow edits: validate with `terraform-target-parity.test.ts`, `heartbeat-reprovision-parity.test.ts` and
  `actionlint`, never by dispatching, and never `--admin` merge.
- `terraform-target-parity.test.ts`: extend the pair row (per-merge targeted, not an exclusion, refused by the birth), add the new
  addresses to `GIT_DATA_BIRTH_REFUSED`, and pin the new secret's direct references to exactly the heartbeat (the project and config
  are literals), so the upstream closure reaches neither `doppler_config.git_data_prd` nor `hcloud_server.git_data`.

**Phase 4 - runbook, ADR, C4.**

- Runbook `git-data-luks-cutover-5274.md`: one hard precondition item; a "Liveness heartbeat" section covering what the web beat proves
  versus the host beat, the read-only status command, the pre-arm soak read, the failure branch (5b), the expected page before and
  during a planned replace, the "between merge and replace" drift note, and a decision table covering EVERY emitted state and code
  (`ok`, `miss` codes, `ping_fail`, `url_unavailable`, `disarmed`, `unmeasured`, and the up-to-17-minute `unit_failed` latch). No SSH
  step anywhere.
- ADR-283 and the one-line pointers; C4 edge text and the count-parity run, as below.

**Phase 5 - verification (targeted only).** The suites named in Acceptance Criteria; no full-battery run.

### Files to Edit

- `apps/web-platform/infra/cloud-init-git-data.yml`
- `apps/web-platform/infra/modules/git-data-userdata/main.tf`
- `apps/web-platform/infra/git-data-userdata-budget.sh`
- `apps/web-platform/infra/git-data.tf`
- `apps/web-platform/infra/git-data-luks.tf` (comment only)
- `apps/web-platform/infra/git-data-pre-receive.sh` (comment only; the one hash-bound #8093 item)
- `apps/web-platform/infra/git-data-pre-receive-placeholder.sh` (comment only; inert for the hash)
- `apps/web-platform/infra/git-data-luks.test.sh` (`p_doppler_config_scope` file list)
- `apps/web-platform/infra/git-data-runcmd-rehearsal.test.sh` (three entries in the hand-maintained `EXPECTED_PATHS`; `MIN_PAYLOADS` rises with them)
- `apps/web-platform/infra/suite-shard-legs.tsv` and `apps/web-platform/infra/suite-durations.tsv` (the new suite; regenerate with `python3 scripts/regenerate-shard-manifest.py --group infra --incremental --write`, then run `bash scripts/lint-orphan-test-suites.sh` once the file is tracked)
- `plugins/soleur/lib/heartbeat-manifest.ts`
- `plugins/soleur/test/terraform-target-parity.test.ts`
- `plugins/soleur/test/heartbeat-reprovision-parity.test.ts` (only if the discovery assertions need the new row named)
- `plugins/soleur/test/preflight-discoverability-test.test.ts` (`BASELINE_DECLARED_PROBES` 53 to 54, with the PLACEMENT / TRUTH / NO-SUBSTITUTE comment its failure text asks for)
- `.github/workflows/apply-web-platform-infra.yml` (two `-target` lines)
- `.github/workflows/infra-validation.yml` (add the new service and timer to the `systemd-analyze verify` list AND to the `git-data-(gc|luks-reopen)[^:]*` alternation, otherwise lint errors on them are silently filtered out)
- `knowledge-base/engineering/operations/runbooks/git-data-luks-cutover-5274.md`
- `knowledge-base/engineering/architecture/decisions/ADR-103-dedicated-host-boot-heartbeats-require-guarded-reprovision-path.md` (one-line pointer to ADR-283)
- `knowledge-base/engineering/architecture/decisions/ADR-198-baking-the-better-stack-ingest-token-into-git-data-user-data.md` (one-line pointer to ADR-283)
- `knowledge-base/engineering/architecture/diagrams/model.c4` (the `gitDataStore -> betterstack` and `gitDataStore -> doppler` edge text and the container sentence; derived counts per `c4-count-parity`)
- `scripts/encryption-posture-ledger.json` only if `python3 -I scripts/lint-encryption-posture.py` fails after the change (it passes at plan time, and the existing "hosts -> Better Stack" row already covers the connection)

### Files to Create

- `apps/web-platform/infra/git-data-liveness.sh`
- `apps/web-platform/infra/git-data-liveness.service`
- `apps/web-platform/infra/git-data-liveness.timer`
- `apps/web-platform/infra/git-data-liveness.test.sh`
- `knowledge-base/engineering/architecture/decisions/ADR-283-git-data-host-originated-liveness-heartbeat.md` (ordinal provisional; ADR-282 is claimed by open PR #9925, and no other ref carries 283 at plan time; re-verify across every `origin/*` ref at ship)
- `knowledge-base/project/specs/feat-one-shot-9438-git-data-liveness-signal/tasks.md`
- `knowledge-base/project/specs/feat-one-shot-9438-git-data-liveness-signal/decision-challenges.md`

### Files to Delete

- `apps/web-platform/infra/git-data-rung2-boot-evidence.env` (a voided attestation is deleted, never rewritten; the gate HOLDs on an absent file)

### Belongs to PR 1b, not this PR

- `apps/web-platform/infra/arm-heartbeats.sh` and `apps/web-platform/infra/arm-heartbeats.test.sh`, plus the runbook arm section.

Do not touch `git-data-gc.sh`, `.gc-cursor`, PR #9466's worktree, or the main checkout's `.mcp.json`.

## User-Brand Impact

- **If this lands broken, the user experiences:** a degraded git-data host (down, store closed, disk or inodes full, a security unit
  failed) that nobody is told about, on the host that holds their source code and serves their Art. 17 erasure (`/api/account/delete`);
  or, in the opposite failure, a false page storm that trains the owner to ignore the one alert that matters during the cutover window.
  The signal detects host and store health. It does NOT detect that a particular git operation or erasure call fails on a healthy
  host; the erasure path keeps its own `unreachable` and `erasure_outcome` reporting (ADR-149, #5914).
- **If this leaks, the user's workflow is exposed via:** the heartbeat URL, which lets a holder forge "alive" pings and so mask a dead
  host for that one monitor. It cannot read or write any repository, the LUKS passphrase, or any user data. The host already holds a
  write-only Better Stack ingest token and a Sentry DSN of the same class (ADR-198); this credential's ceiling is lower than the ingest
  token's. It lives only in `prd_git_data` and on tmpfs at `0600`, and never in `user_data`, `/proc/*/cmdline`, or any emitted line.
- **Brand-survival threshold:** `single-user incident`
- **Threshold decision (challengeable):** the host holds every connected user's source code and erases it on request; one undetected
  dark or frozen-write window is a single-user incident (ADR-103 uses the same threshold for the same host class), so
  `aggregate pattern` understates it.

## Observability

```yaml
liveness_signal:
  what: Better Stack heartbeat soleur-git-data-host-prd, pinged every 60 s by git-data-liveness.timer on the host only when the loopback ssh listener answers, the store is mounted from the LUKS mapper, byte and inode usage are under threshold, and no security unit has failed
  cadence: 60 s tick, period 60 s, grace 300 s (page about 6 minutes after the last good beat)
  alert_target: Better Stack incident to email, plus the account-level native Slack integration (ADR-260); no per-monitor push
  configured_in: apps/web-platform/infra/git-data.tf (resource), apps/web-platform/infra/git-data-liveness.sh and .timer (feeder), apps/web-platform/infra/cloud-init-git-data.yml (arming), plugins/soleur/lib/heartbeat-manifest.ts (row)

error_reporting:
  destination: git-data-emit at info, stage liveness, message prefix SOLEUR_GIT_DATA_LIVENESS, to Sentry (baked DSN) and Better Stack source 2734275 (baked ingest token)
  fail_loud: the heartbeat's absence is the page; the info event carries state, code, root_pct and config, and a 10-minute ok summary proves the feeder is still ticking

failure_modes:
  - mode: host dead, wedged, or off the private net
    detection: no beat within period plus grace
    alert_route: Better Stack incident to email and Slack
  - mode: store unmounted, not on the mapper, or closed after a healthy boot
    detection: feeder withholds with store_unmounted or store_not_mapper
    alert_route: heartbeat absence pages; info event names the code
  - mode: bytes or inodes at or over threshold
    detection: feeder withholds with disk_full or inodes_full
    alert_route: heartbeat absence pages
  - mode: sshd not answering, or the LUKS reopen or nftables service failed
    detection: feeder withholds with ssh_no_banner or unit_failed
    alert_route: heartbeat absence pages
  - mode: a gating measurement cannot be read
    detection: feeder withholds with unmeasured
    alert_route: heartbeat absence pages
  - mode: Better Stack ping rejected (vendor or egress fault)
    detection: state ping_fail while the checks pass
    alert_route: heartbeat absence pages; the state separates a vendor fault from a host fault
  - mode: heartbeat URL absent in prd_git_data
    detection: info event state url_unavailable
    alert_route: heartbeat absence pages once armed; the pre-replace read and the arm gate fail first
  - mode: feeder or timer never armed on a fresh host
    detection: no state=ok summary after boot, and the measured-beat arm step never sees up
    alert_route: the arm step rolls back to paused and returns non-zero, which blocks the flip precondition
  - mode: the alert route itself does not deliver
    detection: the dependent record PR cites one Better Stack incident delivered to the Slack channel since ADR-260, read from the Uptime API
    alert_route: no record PR until it is cited

logs:
  where: Better Stack Logs source 2734275 (table soleur_git_data_prd) and Sentry; query with scripts/betterstack-query.sh --grep SOLEUR_GIT_DATA_LIVENESS
  retention: 90 days (Better Stack source setting recorded in expenses.md)

discoverability_test:
  command: bun plugins/soleur/scripts/reconcile-live-heartbeats.ts
  expected_output: SOLEUR_HEARTBEAT_RECONCILE_OK
  credentials_required: BETTERSTACK_API_TOKEN (Better Stack uptime API read) - the live monitor's existence has no unauthenticated substitute; the offline wiring is covered by heartbeat-reprovision-parity and terraform-target-parity
```

## Infrastructure (IaC)

### Terraform changes

- `apps/web-platform/infra/git-data.tf`: `betteruptime_heartbeat.git_data_host_prd`, `doppler_secret.git_data_host_heartbeat_url_prd`
  with literal `project = "soleur"` and `config = "prd_git_data"` so the excluded `doppler_config.git_data_prd` stays out of the
  per-merge closure (existing providers `BetterStackHQ/better-uptime` and `dopplerhq/doppler`, already pinned; no new provider, no new
  version pin).
- Sensitive inputs: none new. The value flows from `betteruptime_heartbeat.git_data_host_prd.url` (masked in Doppler) into
  `prd_git_data`. No `TF_VAR_*` is added, so `hr-tf-variable-no-operator-mint-default` is not engaged.
- `apps/web-platform/infra/modules/git-data-userdata/main.tf`: three more `file()` bindings. No new module variable (a new variable
  would be refused by the rung-2 divergence allowlist).

### Apply path

Two paths, both existing. (1) The heartbeat and secret: the per-merge apply (`-target` pair, born paused, no arming line). (2) The
feeder reaches the host only through `git_data_host_replace` (a scoped `-replace` of `hcloud_server.git_data`, volumes preserved by
omission, destroy-guarded, environment-gated). A running host is never edited in place. Expected downtime is the existing replace
window; the change adds none. The replace is the owner's decision and is not performed or dispatched here.

### Distinctness / drift safeguards

- `dev != prd`: the URL exists only in `prd_git_data`; a scratch rehearsal config lacks it, so a rehearsal host cannot beat the
  production monitor.
- `lifecycle { ignore_changes = [paused] }` on the heartbeat, matching `git_data_prd`; the arm gate's live unpause is not reverted.
- Terraform state carries the heartbeat URL (it is a provider attribute); the R2 backend is encrypted and the existing
  `git_data_prd` URL has the same exposure.
- Expected drift between merge and replace: a pending replace of `hcloud_server.git_data` (already expected since the PR2 payload).

### Vendor-tier reality check

Better Stack is on a paid plan since 2026-08-16; the "10 monitors and heartbeats" free-tier cap may not bind, but the live object count
is unmeasured. The repo already declares more than ten `betteruptime_heartbeat` blocks across its files, which is itself evidence the
cap is not enforced as on free. A refused create fails the merge-time apply loudly. `policy_id` stays gated on
`var.betterstack_paid_tier` (unset), so no escalation policy is created.

## Encryption Posture

```yaml
at_rest:
  - store: /run/git-data-liveness/url and /run/git-data-liveness/state on the git-data host (tmpfs, not persistent)
    mechanism: plaintext-exception
    evidence: tmpfs is RAM-backed; the feeder never writes either file to the block device (suite row asserts the paths)
    defends_against: a seized or snapshotted disk or volume never contains the URL (it exists only in RAM and in Doppler)
    does_not_defend: root-level code execution or a memory read on the live host; anyone holding the Doppler token for prd_git_data reads the secret directly
    disclosed_as: not-publicly-claimed
    live_verification: unavailable:no live reader for a tmpfs path without host access, which the no-SSH rule forbids; the suite proves the path and mode, the first measured beat proves the read
  - store: doppler_secret.git_data_host_heartbeat_url_prd in Doppler project soleur config prd_git_data
    mechanism: provider-managed:Doppler secrets at rest (vendor-encrypted; read-scoped by a config-scoped service token)
    evidence: ADR-198 (same config, same token class); the secret is created masked
    defends_against: exposure through the repository, the plan output, or a broader Doppler config; only the git-data scoped token and the Terraform provider token can read it
    does_not_defend: a compromised git-data host reads it (as it already reads GIT_DATA_LUKS_KEY and BETTERSTACK_LOGS_TOKEN); ceiling is forging alive pings for one monitor
    disclosed_as: not-publicly-claimed
    live_verification: unavailable:needs a Doppler read, which the owner must authorize
in_transit:
  - connection: git-data host -> Better Stack heartbeat endpoint (uptime.betterstack.com)
    enforced_at: apps/web-platform/infra/git-data-liveness.sh (_ping: https only, URL shape guard, curl default certificate verification, no -k)
    tls: https, TLS 1.2 or newer
    cert_verification: on
    does_not_defend: a leaked heartbeat URL; the URL itself is the credential
    disclosed_as: not-publicly-claimed
  - connection: git-data host -> Doppler API (read of the scoped secret)
    enforced_at: apps/web-platform/infra/git-data-liveness.sh (doppler run with --no-fallback, the same shape as git-data-luks-reopen.service)
    tls: https, TLS 1.2 or newer
    cert_verification: on
    does_not_defend: a leaked scoped service token reads prd_git_data
    disclosed_as: not-publicly-claimed
exception:
  justification: the cached URL sits in tmpfs without disk encryption because tmpfs is never persisted, and writing it to the LUKS store or root disk would be strictly worse
  tracking_issue: "#9438"
  reevaluate_when: the feeder ever persists the URL or its state outside /run, or the host gains swap
  expires_on: 2027-01-08
```

## Architecture Decision (ADR/C4)

### ADR

- **Create ADR-283** (provisional ordinal) via `soleur:architecture`: "git-data host-originated liveness heartbeat: gate the beat on
  local checks, read the URL at runtime, arm only after a measured beat". Status `adopting` until the first measured beat is recorded
  by the dependent record PR (the same sequencing note ADR-280 uses). Decision, Alternatives (the table above), and the credential rule
  applied to the new URL (ceiling, publicly-claimed controls, single-purpose) with the result: it passes all three, and it is read
  through the already-baked scoped token rather than baked. ADR-103 and ADR-198 each get a one-line pointer, not a new section.

### C4 views

Read all three of `diagrams/{model.c4,views.c4,spec.c4}` before writing the task. Checked at plan time against the model text:
the external actor is the owner receiving a Better Stack alert (already modeled through `betterstack` and `slack`, ADR-260); the
external systems are Better Stack and Doppler, both already modeled; the edges `gitDataStore -> betterstack` ("posted by direct curl,
NOT a Vector agent") and `gitDataStore -> doppler` exist, and `hetzner -> gitDataStore` carries the web-fed probe. The change adds a
**kind of traffic** to two existing edges (a recurring heartbeat push; a runtime read of one more secret), and the container sentence
"reports its own boot correctness" would mislead a reader into thinking the host emits nothing recurring. The in-scope task is to edit
those edge and container sentences minimally, add no new element, then run `apps/web-platform/test/c4-code-syntax.test.ts`,
`c4-render.test.ts` and `plugins/soleur/test/c4-count-parity.test.sh` (baseline green at plan time; a heartbeat or secret count
embedded in an edge's prose moves with this change).

### Sequencing

The decision is only true after the replace and the measured beat, so the ADR is written now describing the target state with status
`adopting`; it is not deferred to a follow-up issue.

## Guard Contract

### Guard 1 - git-data liveness feeder gate

**Property.** The feeder sends a heartbeat ping if and only if every gating local health check passes and a validated URL is
available, and whenever it withholds it records which check failed.

**Assembly.** The gating checks (loopback ssh banner, store mountpoint, mount source, store bytes, store inodes, the two named services,
and the unmeasured fallback for each), the single `_ping` chokepoint (the only `curl` call site in the script), the URL source (cache,
fetch, config gate), the persist-then-emit tail, and the three delivery points that must stay equal: the script, the service and timer
that run it, and the timer-arming line in `cloud-init-git-data.yml` (the manifest's executable evidence).
Members drift; the chokepoint is structural: every miss code funnels into one `withhold` function and every ping into `_ping`.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Delete one gating check (for example the inode comparison) so a full inode table still pings | RED |
| 2 | Make `_ping` unconditional (ping before the checks are evaluated, or ignore the aggregate result) | RED |
| 3 | Add a SECOND failing condition after a compliant first (store mounted but off the mapper; banner fine but the LUKS reopen service failed) and keep only the first check | RED |
| 4 | Flip a comparison at a boundary (`-ge` to `-gt` at the threshold) | RED |
| 5 | Dispatch: the feeder exits 0 having run zero checks (empty check list, or `main` never invoked) | RED |
| 6 | Put the URL on curl's argument list | RED |
| 7 | Drop the URL shape guard (a URL containing a newline reaches curl's config) | RED |
| 8 | Treat an unreadable `df` as healthy | RED |
| 9 | In a config other than the production one (exact equality), ping anyway; or match the rehearsal name by prefix | RED |
| 10 | Remove the timer-arming line from the template | RED (manifest evidence in `heartbeat-reprovision-parity.test.ts`) |
| 11 | Rename the service in the script but not in the timer | RED |
| 12 | Remove the `timeout` bound on the Doppler fetch or on the emit (a hang overruns the tick) | RED |
| 13 | Add `RequiresMountsFor=` or `Requires=` to the service (it would mount the store it is meant to observe) | RED |
| 14 | Drop `Environment=HOME=/root` from the service (every host would sit at `url_unavailable`) | RED |
| 15 | Replace the banner read with a unit-state check on `ssh.service` (false-fails on a healthy socket-activated host) | RED |
| 16 | Let `root_pct` gate the ping (it is report-only in this version) | RED |
| 17 | Advance `last_emitted_state` before the emit returns (a failed transition emit is then never retried) | RED |
| 18 | Remove the feeder from `p_doppler_config_scope`'s file list, or change its `--config` argument to a literal | RED |

**Harness rows.**

| # | Edit | Expected |
|---|---|---|
| H1 | Suite edit: replace the fake `curl` with one that always succeeds without recording argv | RED (the argv-absence row must notice it recorded nothing) |
| H2 | Suite edit: drop the fake `df` so every measurement is unreadable | RED (healthy rows must fail instead of vacuously passing) |
| H3 | Must-PASS, non-canonical: a healthy host with the store mounted via a different but equivalent `findmnt` output order, and thresholds one below the boundary | PASS |
| H4 | Must-PASS, non-canonical: a corrupt state file and an empty cache with a reachable Doppler fake | PASS (state resets, URL fetched, ping sent) |
| H5 | Must-PASS, non-canonical: the emit spy exits non-zero on every call | PASS (ping still sent, exit 0, transition retried next tick) |

**Anchor.** The suite asserts behaviour at boundary inputs rather than comparing a stored digest, so there is no stored value that one
diff could edit together with the thing it protects. The two stored facts that do exist are covered from outside the commit: the
manifest row is cross-checked against the cloud-init arming line by the existing parity test on every run, and the threshold constants
are pinned by boundary rows, so a one-line threshold relaxation fails a row it did not edit.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "need a host-originated recurring liveness signal (Better Stack heartbeat or equivalent) with an alert route" [brief] | Feeder contract; Terraform; Observability | mapped |
| 2 | "record it as a flip precondition in knowledge-base/engineering/operations/runbooks/git-data-luks-cutover-5274.md" [brief, issue #9438] | Phase 4 runbook edit | mapped |
| 3 | "The host payload is hash-bound, so use the rung-2 two-PR sequence (payload/template change first, then the dependent PR)" [brief] | PR sequence table; Files to Delete | mapped |
| 4 | "bundle with the pending git-data host template change for #8093 so the host is not replaced twice" [brief] | Phase 2 comment-only fix; Cut List rows for held-out #8093 items | mapped (partial bundle, reasons recorded) |
| 5 | "Any host replace is the owner's decision — never perform or dispatch one." [brief] | PR sequence step 4; Apply path | mapped |
| 6 | "the plan should say whether #9438 is closed by the dependent PR ... and which PR of the two-PR sequence carries it" [brief] | Overview; PR sequence and who closes what | mapped |
| 7 | "Plan ONLY #9438 now; the later items are out of scope for this PR." [brief] | Non-Goals below | mapped |
| 8 | "never dispatch a workflow to validate a workflow edit; no agent --admin merge on a PR that edits .github/workflows" [brief] | Phase 3 (validation by parity tests only); Risks | mapped |
| 9 | "targeted test suites only" [brief] | Phase 5 | mapped |
| 10 | "Ship order: run ship step 5.5 (archive-kb.sh) BEFORE arming auto-merge." [brief] | Quality Gates | mapped |
| 11 | "do not touch git-data-gc.sh or .gc-cursor" [brief] | Files section footer; diff-scope AC | mapped |
| 12 | "Better Stack heartbeat or an equivalent that fires from the host ... with an alert route" [issue #9438] | Terraform (`email = true`, ADR-260 Slack) | mapped |
| 13 | "a dead sshd, a full disk or a failed unit is only discovered when" [issue #9438] | the check table (`ssh_no_banner`, `disk_full`, `inodes_full`, `unit_failed`) | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `git-data-liveness.sh/.service/.timer` | "host-originated recurring liveness signal" | asked |
| `betteruptime_heartbeat.git_data_host_prd` | "Better Stack heartbeat or equivalent" | asked |
| the four gating check families | "a dead sshd, a full disk or a failed unit" | asked |
| `store_unmounted`, `store_not_mapper` | — | inferred — justification: the "host up, mapper closed later" residual is named and scope-outed in `git-data-luks-reopen.timer`, and ADR-239 makes "never serve a plaintext device" the store's invariant |
| `doppler_secret.git_data_host_heartbeat_url_prd` | — | inferred — justification: the host needs the URL at runtime and baking it would put the production URL into the rehearsal render (Alternative A) |
| per-merge `-target` pair in `apply-web-platform-infra.yml` | — | inferred — justification: without it the heartbeat is never created before the replace, and `-target=hcloud_server.git_data` would then plan a create the exact-set gate refuses |
| manifest row with `arming_pending` | — | inferred — justification: `heartbeat-reprovision-parity` fails any heartbeat without a row, and a paused-yet-fed monitor would raise the nightly `fed-but-paused` alarm |
| runbook precondition | "record it as a flip precondition in knowledge-base/engineering/operations/runbooks/git-data-luks-cutover-5274.md" | asked |
| flip-time re-read and the 10-minute `ok` summary | "record it as a flip precondition" | inferred — justification: the runbook requires a fresh replace immediately before the cutover, so a one-time tick goes stale, and silence cannot distinguish a healthy feeder from a dead one |
| deletion of `git-data-rung2-boot-evidence.env` | "use the rung-2 two-PR sequence (payload/template change first" | asked |
| the pre-receive comment fix | "bundle with the pending git-data host template change for #8093" | asked |
| PR 1b arming tooling | — | inferred — justification: ADR-117 requires arming to be executable and measured, and the precondition needs a read-only verification that `hr-no-dashboard-eyeball-pull-data-yourself` allows; kept out of this PR because nothing here needs it to merge |
| ADR-283 and the two pointers | — | inferred — justification: `wg-architecture-decision-is-a-plan-deliverable` (a new credential read path and a new feeder class) |
| C4 edge and container text | — | inferred — justification: the container description would otherwise say the host reports boot correctness only |
| `decision-challenges.md` | — | inferred — justification: headless run must persist Taste decisions for ship to render |
| registration and gate-surface edits (`EXPECTED_PATHS`, the infra shard manifest, `infra-validation.yml` unit lint, `p_doppler_config_scope`, the discoverability ratchet) | — | inferred — justification: each is a registration surface a new payload or suite must appear in or CI reddens or, for the unit lint, silently filters the new unit's errors |

### Split Assessment

- Subsystems touched: 4 roots (`apps/web-platform`, `plugins/soleur`, `knowledge-base`, `.github`) plus `scripts`
- Planned files: 29 in this PR (21 edits, 7 creates, 1 delete; the manifest pair counted once), plus 3 in PR 1b
- Estimated changed lines: about 650 (payloads about 130, suite about 280, TF 50, manifest and parity 70, docs 100, registrations 20)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: split already applied once (the arming modes moved to PR 1b); the remainder stays one PR, over two thresholds on purpose. Four roots and 29 files are driven by registration and gate surfaces (the suite registry, `EXPECTED_PATHS`, the unit-lint list, `p_doppler_config_scope`, the discoverability ratchet, the manifest row and its parity tests) that must move with the payload or CI reddens, and by docs and an ADR that would otherwise claim something not yet true. The line estimate is under the line threshold.

## Acceptance Criteria

### Functional Requirements

- [ ] `git-data-liveness.sh` exists, is bound in `modules/git-data-userdata/main.tf` with the `file("${path.module}/../../...")` spelling and
  `local.git_data_rationale_strip`, mirrored in `git-data-userdata-budget.sh`, and written by `cloud-init-git-data.yml` with its service
  and timer.
- [ ] The feeder pings only when every gating check passes, withholds otherwise, and emits a `liveness` `info` event with the miss code
  on a state change and a `state=ok` summary every 10 minutes while healthy (suite rows, Guard Contract rows 1 to 18, H1 to H5).
- [ ] The URL is never on any argument list and never in an emitted line (suite rows; ADR-280 shape).
- [ ] In a config other than the production one (exact equality) an absent secret yields `disarmed` and no ping; in the production
  config it yields `url_unavailable`. An empty cache is retried every tick; a ping failure drops the cache.
- [ ] `betteruptime_heartbeat.git_data_host_prd` (paused, `ignore_changes=[paused]`, `push = false`) and
  `doppler_secret.git_data_host_heartbeat_url_prd` exist in `git-data.tf`; no new variable; the secret's `project` and `config` are literals.
- [ ] The manifest row exists with `arming: "dedicated-host-boot"`, `replace_target` `git-data-host-replace`, executable evidence pointing at
  the timer-arming line, and `arming_pending: { tracking_issue: 9438 }`; the new address is in no `arm_one` line.
- [ ] The pair rides the per-merge `-target` list and is in `GIT_DATA_BIRTH_REFUSED`; the new secret's direct references are pinned.
- [ ] `git-data-rung2-boot-evidence.env` is deleted in this PR and no other change in the PR re-creates it.
- [ ] The runbook carries a hard flip precondition naming the signal, the read-only status command, the pre-arm soak read (at least
  four consecutive `state=ok` events spanning at least 30 minutes after the current host's `boot_complete`, no other state after the
  first), the failure branch, what "satisfied" means (monitor armed after a measured `up` transition, `arming_pending` removed, and the
  whole check RE-READ at flip time: `up` and a `state=ok` event under 15 minutes old and later than the current `boot_complete`), the
  expected page before and during a planned replace (announce it; page then auto-resolve is the normal shape; an incident still open
  after boot plus two ticks is a failed replace), the pre-replace read-only check, the rung-2 window with its owner and recommended
  two-working-day cap, and a decision table for every emitted state and code. No SSH step.
- [ ] The stale pre-receive comments are corrected (comment-only; only the `git-data-pre-receive.sh` edit touches a hash-bound file).

### Non-Functional Requirements

- [ ] Stored `user_data` stays under the cap with headroom recorded in the PR body (`git-data-userdata-budget.sh --json`); the sub-cap
  model in `cloud-init-user-data-size.test.ts` is updated only if its own assertion requires it, with the measured number.
- [ ] Merge-time apply adds no arm line and no feeder dependency, so the new monitor cannot redden it while paused; a refused create
  (vendor object cap) or an absent `prd_git_data` config fails that apply loudly by design (R5), not silently.
- [ ] No production write, host replace, key rotation, ruleset change, or workflow dispatch is performed or scheduled by this PR.
- [ ] No Doppler read or write is made by the agent in this PR's work phase; any Better Stack or Doppler read the owner wants is a
  separate, explicitly authorized step.
- [ ] Diff scope, measured against the merge base: `git diff --name-only origin/main...HEAD` lists no `git-data-gc.sh`, no `.gc-cursor`
  path, nothing under `.worktrees/feat-one-shot-9361-marketplace-ruleset-bypass-swap`, no `.mcp.json`, and neither `arm-heartbeats.sh`
  nor its test (PR 1b); it may list the pipeline's own writes (`knowledge-base/INDEX.md`, `specs/<branch>/session-state.md`).
- [ ] The feeder script and its unit contain the xtrace refusal as `[[ $- == *x* ]]` and the literal text `set -x` appears in neither
  (`git-data-luks.test.sh` A28a); `GIT_DATA_REPO_ROOT` appears in neither; the unit has `Environment=HOME=/root`, no `Requires=`,
  `RequiresMountsFor=` or `BindsTo=`, and `TimeoutStartSec=55`; no `RuntimeDirectory=`.

### Quality Gates (targeted suites only)

- [ ] `bash apps/web-platform/infra/git-data-liveness.test.sh`
- [ ] `bash apps/web-platform/infra/git-data-luks.test.sh` and `bash apps/web-platform/infra/git-data-render-strip-parity.test.sh`
- [ ] `bash apps/web-platform/infra/git-data-runcmd-rehearsal.test.sh` (rung 1 against the pinned image)
- [ ] `bash apps/web-platform/infra/git-data-userdata-budget.sh` (exit 0) and `bun test plugins/soleur/test/cloud-init-user-data-size.test.ts`
- [ ] `bun test plugins/soleur/test/heartbeat-reprovision-parity.test.ts plugins/soleur/test/terraform-target-parity.test.ts`
- [ ] `bun test plugins/soleur/test/preflight-discoverability-test.test.ts` (the ratchet bump) and `actionlint` on the two edited workflows
- [ ] `bash scripts/lint-orphan-test-suites.sh` reports no orphan after the new suite is tracked
- [ ] `bash plugins/soleur/test/c4-count-parity.test.sh` and the C4 syntax and render tests
- [ ] `python3 -I scripts/lint-guard-contract.py` on this plan; `python3 -I scripts/lint-encryption-posture.py` on the change
- [ ] ADR ordinal re-verified against every `origin/*` ref and open PR at ship; `soleur:archive-kb` (ship step 5.5, `archive-kb.sh`)
  runs BEFORE auto-merge is armed
- [ ] The PR body says: `Refs #9438`, `Refs #8211`, `Refs #8093` (never `Closes`); lists the two merge-time production writes; states the
  rung-2 window; and carries no checklist for the owner
- [ ] PR is not armed in the merge queue and is never synced, updated, or pushed afterwards; one re-enqueue on an unrelated `merge_group`
  flake, then report; no `--admin` merge (the PR edits `.github/workflows`)

### Owner-gated steps this PR does not perform

Each is automatable by an agent; the gate is authorization (a menu answer is not authorization), not feasibility. Rehearsal dispatch on
`main`; the evidence-only PR; the host replace; the pre-replace and pre-arm reads; the arm; the dependent record PR that closes #9438.
Each is recorded in the runbook and tracked on #9438, which stays open.

## Plan Review Revisions

Five-agent eng panel (DHH, Kieran, code-simplicity, architecture-strategist, spec-flow) after the CTO, COO and CPO domain passes.
Applied as Mechanical: counters and hourly refresh cut; `first=1` replaced by a 10-minute `ok` summary (spec-flow: silence is not proof);
arming modes moved to PR 1b; ADR and C4 trimmed to one ADR plus pointers and edge text; ledger edit made conditional; `ssh` check moved
to a loopback banner read (socket activation); `root_full` made report-only; `HOME=/root`; feeder added to `p_doppler_config_scope`; no
throttle while the cache is empty; emit bounded and persisted-before-emit with the timeout arithmetic written down; exact equality for the
config name; placeholder-file finding; soak failure branch and flip-time recency read; arm placed after `gc_timer`. Persisted as
decisions the owner may overturn (`decision-challenges.md`): DC-1 to DC-6. The named CEO/design/devex panel is covered by the
Phase 2.5 CPO and CTO passes of the same agents; no UI surface exists, so no design lens applies.

## Domain Review

**Domains relevant:** engineering, operations, product (single-user-incident sign-off only; no UI surface)

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Approve with changes, all applied. The runtime Doppler read is right (a baked URL would put the production URL into the
rehearsal render; the divergence allowlist is identity-only). Per-merge targeting is safe on the graph; the residual risk was pulling
the excluded `doppler_config` into the closure, so project and config are now literals. The manifest and `arming_pending` design avoids
a red merge apply and a false green. Held out `AuthorizedKeysFile` correctly. Required and applied: the precondition is re-read at flip
time; `EXPECTED_PATHS` in the runcmd rehearsal; `infra-validation.yml` unit lint list and alternation; xtrace spelling for A28a; no
`GIT_DATA_REPO_ROOT` and state only under `/run`; a bounded tick.

### Operations (COO)

**Status:** reviewed
**Assessment:** Approve with changes, applied except one. No new ledger line (paid plan, same account); the Better Stack row has an
overdue `verify_by` estimate and a stale "never born" note to refresh in the record PR; the live object count is unmeasured
(owner-authorized read). Replace window: the page is certain; the runbook says to announce it and defines page-then-resolve as normal.
Ordering fixed to replace, soak, arm, record, flip, with a 30-minute floor and the trade-off against ADR-220 D6 recorded. Pre-replace
read-only check added. Not applied: flipping `push` to `true` (the eng panel judged it unrelated to the ask); recorded as DC-3.

### Product (CPO sign-off)

**Status:** reviewed
**Assessment:** Conditional yes at plan time, conditions applied. The failure artifact is reworded to what the signal detects (host and
store health, not erasure outcomes). The soak has a floor; the precondition is a flip-time re-read; the alert-route delivery proof is a
cited, read-only incident; the rung-2 window has a recommended cap and a named owner (the owner). Residual, accepted and tracked: the
gate is a runbook item until #9943 lands, and `arming_pending` suppresses only the nightly `fed-but-paused` alarm, not `absent-live`.
For `user-impact-reviewer` at review: check each miss code against a healthy fresh host and the post-rotation state; that `unit_failed`
does not latch beyond the documented window; that the URL never appears in a log line, an emitted event or Terraform output; that a
rehearsal host cannot reach the production monitor; that nothing in the PR performs or schedules an arm or a replace.

No Product/UX Gate: the Files lists contain no UI-surface path (`components/**`, `app/**/page.tsx`, `app/**/layout.tsx`).

## Downtime & Cutover

**Offline-inducing operation.** Every edit to `cloud-init-git-data.yml` or a `file()`-bound payload is ForceNew on
`hcloud_server.git_data` (it has no `ignore_changes = [user_data]`), so this change makes the already-pending replace carry the
feeder. The replace is the operation; this plan adds no new one and does not perform it.

**Surface affected.** The git-data host only: the shared bare-repo store (empty and flag-off until the cutover flip, ADR-239) and the
Art. 17 erasure path, which reports `unreachable` rather than succeeding while the host is down. The web app keeps serving; git-data is
a fail-soft overlay (`ensure-workspace-repo.ts`).

**Zero-downtime path, evaluated.** Blue-green is not available: the host is a singleton whose private NIC address (`10.0.1.20`), its two
volumes and its pinned SSH host key are bound to one instance, and ADR-237 rotates the key on every replace by design. The volumes
survive by omission from the scoped recreate, so no data moves. A rolling or expand-contract shape does not apply to a one-host store
with an empty dataset. Residual downtime is therefore accepted as the bounded window of one scoped replace, already described in the
runbook ("What users see, During a replace"), already required before the real cutover (ADR-220 D6), and gated on the owner's explicit
per-step authorization. The feeder adds no extra reboot: it is armed by first-boot cloud-init and the monitor is paused, so the window
pages nothing until arming.

**Per-stage verification and rollback.** Verification is the pre-arm read (PR sequence step 5) and the flip-time re-read (step 8);
rollback of the payload is forward-only through the two-PR sequence (a reverted payload voids the evidence again), and rollback of the
monitor is the arm gate's own re-pause on a missing beat.

### Network-Outage Deep-Dive

The trigger words appear because the plan discusses SSH banners and unreachable erasures, not because it diagnoses an outage; the
deep-dive is applied to the NEW egress dependencies the feeder introduces.

| Layer | Status | Artifact |
|---|---|---|
| L3 firewall allow-list | verified by construction | `hcloud_firewall.git_data` declares zero rules (inbound deny, egress open) per ADR-198; the only host-local drop is the metadata endpoint for non-root UIDs, and the feeder runs as root |
| L3 DNS / routing to `uptime.betterstack.com` and the Doppler API | not verified from this host | The host's emitter already reaches Better Stack ingest and Doppler (a `boot_complete` row exists since the 2026-09-25 replace; the LUKS reopen reads Doppler every boot). The heartbeat host is a different name; the first measured beat verifies it, and `ping_fail` names the failure |
| L7 TLS | verified by construction | curl default verification, https only, no `-k` (Encryption Posture) |
| L7 application | designed | the beat is a GET that must return success; `-f` makes a non-2xx a `ping_fail`, with the cache dropped so a rotated URL is re-read |

Service-layer hypotheses (feeder bug, vendor outage) are only entertained after those layers, in that order.

## Verification record (deepen pass)

- Every `#N` in this plan resolved live with `gh issue view` or `gh pr view`; states match the narrative (#9438, #8211, #8093, #9943,
  #9936, #9925 and #9466 open; #9440 and #8128 merged; #5914, #6537, #6548, #7855, #8043 closed).
- Every rule id resolved against `AGENTS.md` or `scripts/migrated-rule-ids.txt`; none missing, none retired.
- Labels used on #9943 (`domain/engineering`, `type/chore`, `priority/p3-low`, `deferred-automation`) exist.
- ADR ordinal 283: `ls decisions` on a freshly fetched tree and a sweep of all 117 `origin/*` refs show 282 claimed by
  `feat-one-shot-9879-luks-sole-copy-protection` and nothing at 283.
- Section literals (`TimeoutStartSec=55`, `state=ok`, `SOLEUR_GIT_DATA_LIVENESS`, `GIT_DATA_HOST_HEARTBEAT_URL`,
  `soleur-git-data-host-prd`, `push = false`) are identical across Proposed Solution, Observability, Guard Contract, Acceptance Criteria
  and tasks.md.
- Lints green at this commit: `lint-guard-contract.py`, `lint-infra-no-human-steps.py`, `lint-encryption-posture.py`,
  `c4-count-parity.test.sh`, `lint-orphan-test-suites.sh`, markdownlint on the plan, tasks and decision-challenges.

## Test Scenarios

- Healthy host, all gating checks pass, URL cached: one ping per tick, a `state=ok` event on the transition and every 10 minutes after.
- Healthy to degraded (inodes at 90 %): ping withheld, one `liveness` info event `state=miss code=inodes_full`, `root_pct` carried.
- Persistent miss: emits at the transition and then at most every 30 minutes.
- Degraded to healthy: ping resumes, one recovery `ok` event.
- Two simultaneous misses: the event names both codes.
- Socket-activated host with `ssh.service` inactive but the listener answering: healthy, no miss.
- Doppler unreachable at first boot, production config: `url_unavailable`, no ping, retried every tick; the next tick after the secret
  exists pings with no replace.
- Doppler unreachable after the cache is filled: cached URL used, no page, no emit storm.
- Rehearsal scratch config, secret absent: `disarmed`, checks still run, no ping, rung-2 PASS rule unaffected (no `fatal`).
- Better Stack rejects the ping: `state=ping_fail`, cache dropped, distinguishable from a host miss.
- URL with an embedded newline or a non-Better-Stack host: refused before any request.
- `set -x`: refuses to run (exit 78).
- A `doppler` fake that exits 0 with empty output: treated as an absent secret, never as a valid URL.
- A hung `doppler` fetch and a hung emit: the tick still finishes inside 55 s and the ping decision is unchanged.
- An emit that fails: exit 0, ping sent, the transition retried next tick.
- `unit_failed`: the LUKS reopen service fails and then recovers; pinging resumes after the unit's next successful run.
- Fresh host after key rotation: every check reads healthy and the first tick emits `state=ok`.
- Manifest: row present, evidence line present, `replace_target` resolves; removing the cloud-init arming line reds the parity test.

## Risks and Sharp Edges

- **R1, per-merge closure.** The exclusion comments in `terraform-target-parity.test.ts` warn that a per-merge target on a git-data
  Doppler write can drag `hcloud_server.git_data` into the plan and trip `host_creates > 0`. Those comments concern secrets that
  reference the server's NIC; the new secret references only the heartbeat, and its project and config are literals so even the
  excluded `doppler_config` stays out of the closure. A row pins both. Treat the row, not this paragraph, as the control; if the closure
  ever reaches the server, move the pair to the birth route and give up per-merge creation.
- **R2, the rung-2 window.** From the payload PR's merge until the evidence PR lands, every git-data birth and replace refuses. This is
  intended, but it must be scheduled; do not shorten it by combining the evidence with the payload (Guard 4) or re-dating evidence.
- **R3, false pages.** A threshold that false-fails on a healthy fresh host would page and train the owner to ignore the alert, the
  brand risk ADR-103 names. Mitigation: boundary rows, `info` events readable while the monitor is still paused, `root_pct` report-only,
  and arming only after the soak read. A false fail found after the replace is a payload defect fixed forward through the two-PR
  sequence (step 5b); there is no agent waiver.
- **R4, expected page during replace.** An armed monitor pages about six minutes into any planned replace. Recorded in the runbook; no
  pause step is prescribed.
- **R5, vendor object cap and absent config.** Unmeasured cap; a refused create, or an absent `prd_git_data` config, fails the
  merge-time apply loudly.
- **R6, comment-only edits void the attestation.** The hash binds source, not the render (ADR-149 #8043 finding), so the pre-receive
  fix costs nothing extra only because the evidence is already being voided.
- **R7, workflow edits.** Two `-target` lines in `apply-web-platform-infra.yml` and the unit-lint list in `infra-validation.yml`.
  Validation is static; no dispatch, no `--admin` merge.
- **R8, the precondition goes stale.** The runbook requires a fresh replace immediately before the cutover, so a beat measured on an
  earlier host proves nothing about the host that is frozen, and `d6_replace_stale` has no recency or liveness bound of its own. The
  precondition is re-read at flip time (PR sequence step 8), and that re-read is the only control until #9943.
- **R9, the soak lengthens the replace-to-flip gap** that ADR-220 D6 wants short (nothing planted during the read-only period should
  survive into the cutover). 30 minutes is the floor; the owner chooses any longer value knowing that cost.
- **Sharp edge.** The SSH listener is socket-activated on Ubuntu 24.04: `ssh.service` may be inactive on a healthy idle host, and the
  service unit is `ssh`, not `sshd`. Read the banner; do not read unit state.
- **Sharp edge.** `OnUnitActiveSec` with the default `AccuracySec=1min` can stretch a 60 s tick; the timer sets `AccuracySec=5s`.
- **Sharp edge.** A plan whose `## User-Brand Impact` section is empty or omits the threshold fails `deepen-plan` Phase 4.6; this one
  declares `single-user incident`, so `requires_cpo_signoff: true` is set and `user-impact-reviewer` runs at review.

## Non-Goals / Deferrals

- The #8209 credential-custody ADR and #8573: out of scope for this PR (any Doppler use there is the owner's call).
- Machine enforcement of this precondition in `git-data-cutover.yml` / the flag precheck: deferred to #9943 (milestone "Post-MVP /
  Later" like #8211; re-evaluate when the cutover workflow is next edited for any other reason, since a workflow edit carries the
  admin-merge restriction). Until it lands the gate is the runbook item plus its flip-time re-read.
- The arming modes (`--status`, `--arm-one`): PR 1b, tracked on #9438.
- `AuthorizedKeysFile` move, `gc_timer` paging policy, root-login detection (its premise names a Vector allowlist git-data does not
  have), the Delete Account `ConnectTimeout`, and the `sshd` unit-name noise in other hosts' templates: remain on #8093, with a
  re-evaluation comment recording what this PR did and did not bundle.

## References

- Issue #9438; umbrella #8211; follow-up tracker #8093; deferral #9943; PR #9440 (cites #9438 as a follow-up); draft PR #9936.
- `knowledge-base/engineering/operations/runbooks/git-data-rung2-rehearsal.md` §Changing the payload.
- ADR-103, ADR-117, ADR-149 (#8043 and #8128 dispositions), ADR-198, ADR-239, ADR-260, ADR-280.
- `knowledge-base/engineering/operations/post-mortems/2026-08-03-registry-liveness-heartbeat-flapped-and-recorded-no-cause-postmortem.md`.
