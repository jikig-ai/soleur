---
title: "fix: sandbox post-incident follow-ups (deploy-time SDK Bash smoke, runtime hardening, outer-wrap canary decision)"
date: 2026-10-19
slug: fix-sandbox-incident-followups
branch: feat-one-shot-10455-10453-10454-sandbox-followups
issue: 10453
closes: [10453, 10454]
refs: [10455]
type: fix
priority: p2
domain: engineering
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
lane: cross-domain
---

## Enhancement Summary

**Deepened on:** 2026-10-19
**Passes applied:** six CTO rulings (outer-wrap, probe config/synthetic/message/classifier/Slack/alert, AF_UNIX design, review forks), CPO and CLO advisories, a six-seat plan review (DHH, Kieran, simplicity, architecture, spec-flow, CTO devex), the deepen halts 4.6 to 4.12, and live verification of vendor and repo facts.

### Key improvements
1. The AF_UNIX item was reshaped by a measured fact: the SDK's in-sandbox `socat ... UNIX-CONNECT` bridges start before the user command in every session, so a blanket bwrap-level deny is infeasible. The plan ships a second artifact, applied to no-egress sessions only, behind a default-OFF runtime flag.
2. The user-facing notice no longer claims "this command did not run" (a tenant can forge the helper line after a command that ran); it is single-line, error-flagged and pre-fork-step only, and the directive keys on the raw line the model actually sees.
3. The deploy smoke closes the signature-dependence trap: Bash dispatched with no nonce, or a hang, is `sdk_bash_smoke_failed`; `smoke_infra_error` is reserved for "Bash never dispatched" and has a stale-warning escalation so a dead probe cannot stay silent.
4. The runtime synthetic gained deploy-swap guards (deploy lock, container state, first run at timer start), a 900 s / 900 s heartbeat (a 300 s grace would false-page on every deploy straddling a skipped tick), and an objective cut line.

### New considerations discovered
- `GET .../heartbeat/<token>/fail` is documented by Better Stack (verified live below), so a failed synthetic can alert immediately instead of waiting for a missed beat.
- The plan's discoverability probe is credential-declared, which moves the repo-global `BASELINE_DECLARED_PROBES` ratchet (70 to 71).
- Phase 5 touches about 25 parity registrations that a host-resident heartbeat drags in (cloud-init user_data size cap, birth gate, vacuity floor, templates validator).

## Overview

One pull request that closes the follow-ups the hosted-agent Bash outage (#10445) left open: a deploy-time end-to-end
SDK Bash smoke in the canary container with its own paging alert (#10453), a bundle of runtime hardening items from
the consolidated chore issue (#10455), and a recorded fix-or-demote ruling on the standing-red outer-wrap canary
(#10454).

Spec lacks valid lane: - defaulted to cross-domain (TR2 fail-closed).

## Research Insights

### Premise Validation (Phase 0.6)

Checked on 2026-10-19: #10455, #10453, #10454 are all OPEN with no linked closing PR; `git grep` on `origin/main`
finds no `sdk_bash_smoke` verdict map or `faithful_canary_sandbox_broken` alert (only ADR-079 / runbook prose that
calls them planned). The cited artifacts exist on `main`: `apps/web-platform/infra/lib/sdk-bash-probe.mjs`,
`run_faithful_sandbox_canary` and `run_outer_wrap_canary` in `apps/web-platform/infra/ci-deploy.sh`,
`classifyBashSandboxFailure` in `apps/web-platform/server/sandbox-startup-classifier.ts`, the Better Stack alert
`agent_sandbox_bash_denial` in `apps/web-platform/infra/betterstack-logs-alerts.tf`. Two premises were refined:
(1) the issue text implies the single bwrap-level filter can simply gain a `socket(AF_UNIX)` deny; measured
2026-10-19 (logging the bwrap argv the real SDK emits, `allowedDomains: []`): every wrapped command still starts
in-sandbox `socat TCP-LISTEN:3128 ... UNIX-CONNECT:/tmp/claude-http-<id>.sock` bridges BEFORE the user command, so a
blanket filter breaks them for every session (the proxy denies everything for empty `allowedDomains`, so the visible
effect there is "connection refused" instead of a proxy 403, but for egress sessions it is a real egress break);
(2) the ADR-075 2026-10-09 addendum (operator-ratified) dropped the privileged elevation the outer-wrap canary
requires, so `wrong_elevation_userns` is the designed state of production, not a regression. Tracker #10456 (PIR flip)
is already CLOSED, which makes `scripts/followthroughs/sandbox-readback-10445.sh` due for the retirement its own
header prescribes.

### Property List (Phase 0.6b)

1. A deploy whose image cannot run a real wrapped Bash command is reported on a no-SSH surface on that deploy (#10453).
2. A mechanism-level failure of a hosted Bash call between deploys, or a dead log path, pages without depending on
   tenant text or Vector (#10455 b).
3. A tenant never sees raw `apply-seccomp:` text and gets a plain sentence plus a bounded retry (#10455 c).
4. A helper failure at any step, not only `unshare(CLONE_NEWUSER)`, is classified and pages (#10455 e).
5. The weakened AF_UNIX posture is tightened wherever the SDK's own constraint allows (#10455 a).
6. The wake path of every Better Stack Logs alert is known from data, not assumed (#10455 d).
7. No permanently red report-only signal remains; the decision and its reason are on record (#10454).

### Cut List (Phase 0.6b)

- Extending `sandbox-readback-10445.sh` with an `sdk_bash_smoke` line (task 3.3 of the incident plan): cut. Its
  tracker #10456 is closed; the soak-gated promotion gets its own stateless verdict script (workspace-isolation
  precedent) and the old readback is retired.
- A server-side automatic replay of a failed tenant command (retry path): cut. Replaying tenant commands is not
  idempotent; the retry is the model's single retry plus the user's next message (CTO F3).
- A second Docker image artifact / second esbuild bundle for the deploy probe: cut. A literal config pinned by a
  parity test already exists as a pattern for the deny list (CTO F1).
- A new "Try again" UI component and WS error code: cut (CTO F3); it would also trip the mechanical UI-surface gate.
- A fix of the outer-wrap elevation expectation: cut (CTO #10454): it would turn the canary green on the mechanism the
  code itself calls wrong.

### Repo and ADR corpus findings

- ADR-075 addendum 2026-10-16 documents the AF_UNIX posture and names the single-filter follow-up; ADR-079 addendum
  2026-10-16 defines the `sdk_bash_smoke` contract (coverage field, 5 greens over 3 days, `smoke_infra_error` never
  rolls back); ADR-218 records the Logs-alert pattern (seven-step "TO ADD ANOTHER LOGS ALERT" header in
  `betterstack-logs-alerts.tf`); ADR-260 records the Slack integration as dashboard OAuth with no Terraform resource;
  `GET /api/v2/slack-integrations` returned `{"data":[]}` before #9168 (`app-database-readiness-alarm.md`).
- Dark-launch template: `run_workspace_isolation_probe` in `ci-deploy.sh` (own state file, `env -i` exec, host
  `timeout`, rc classification, `canary_state_json` reader in `cat-deploy-state.sh`, stateless soak script
  `scripts/followthroughs/workspace-isolation-verdict-2640.sh`). Journald format is emitted by
  `sandbox_canary_sentry_event` (`SANDBOX_CANARY_FAIL: verdict=... reason=... sdk=... (op=...; report-only canary,
  never gated)`); the alert template is `bwrap_probe_rollback` (`SYSLOG_IDENTIFIER = 'ci-deploy'`, no host_name).
- Host-resident heartbeat template: `web-private-nic-guard.{sh,service,timer,test.sh}` plus `web-probe.tf` heartbeat
  and Doppler URL secrets, `server.tf` install provisioner, `cloud-init.yml`, `soleur-host-bootstrap.sh`,
  `heartbeat-manifest.ts`, `arm-heartbeats.sh`, `fresh-boot-parity.test.sh`, `terraform-target-parity.test.ts`.
- Helper step lines (vendored binary strings): `unshare(CLONE_NEWUSER)`, `write /proc/self/uid_map`, `write
  /proc/self/gid_map`, `unshare(CLONE_NEWPID|CLONE_NEWNS) after userns`, `prctl(PR_SET_NO_NEW_PRIVS)`,
  `prctl(PR_SET_SECCOMP)`, `prctl(PR_CAP_AMBIENT_CLEAR_ALL)`, `prctl(PR_SET_DUMPABLE)`, `mount(/proc)`,
  `mount(MS_PRIVATE)`, `fork(worker)`, `waitpid`, `execvp`, `seccomp(unix-block)`. While `allowAllUnixSockets` is set the
  helper is skipped, so these lines only appear if that knob regresses.
- Institutional learnings: `2026-10-18-a-fix-that-removes-a-block-must-re-derive-...` (green canary over an outage is
  a claim; notify-only readbacks; shared deploy frame); `2026-07-18-betterstack-followthrough-probe-must-field-isolate-
  syslog-identifier` (isolate the journald field, fixtures in the real `raw` shape); `2026-07-03-dark-launch-pr-must-
  exclude-operator-prerequisite-infra`.

### Deepen-pass verification (2026-10-19)

- **Vendor contract (CLI-verification gate).** Heartbeat failure reporting: appending `/fail` to the heartbeat URL, with an optional exit code and POST body, is documented. <!-- verified: 2026-10-19 source: https://betterstack.com/docs/uptime/cron-and-heartbeat-monitor/ -->
  The page lists no minimum period or grace values, so the free-tier floor stays a Phase 0.2 live read. Note the documented host is `incidents.betterstack.com`; the Terraform `betteruptime_heartbeat.url` output is the source of the real URL, to which `/fail` is appended.
- **Precedent diff (4.4).** Atomic ledger write: `write_sandbox_canary_state` (`mktemp "${state_file}.XXXXXX"` in the same directory, then `mv`), which the smoke ledger reuses rather than copying. Deploy lock: `LOCK_FILE="${CI_DEPLOY_LOCK:-/var/lock/ci-deploy.lock}"` (`ci-deploy.sh` L3798), FD-200 advisory flock; the synthetic uses `flock -n` on the same path. Host timer: `web-zot-consumer-probe.{service,timer}` (`OnBootSec=90s`, `Persistent=true`, retagged `SyslogIdentifier`). Alert: `bwrap_probe_rollback` (SYSLOG_IDENTIFIER + startsWith marker, no host_name). Dark-launch probe: `run_workspace_isolation_probe`. No novel pattern is introduced.
- **Rule and reference existence.** Cited rule ids `wg-dark-launch-deploy-gates`, `hr-menu-option-ack-not-prod-write-auth`, `hr-prod-host-config-change-immutable-redeploy`, `hr-observability-as-plan-quality-gate`, `cq-write-failing-tests-before` exist as active ids. Issues #9773, #9797, #10445, #10548, #10549 and PR #9874 resolve live; #8752 is the closed seccomp-filter issue; #10456 is closed.
- **Downtime and cutover (4.55).** Not triggered: the host timer and the Better Stack resources are additive, `ci-deploy.sh` edits add a non-blocking call after the canary, and no hcloud resource is replaced.
- **Halts 4.6 to 4.12.** User-Brand Impact valid (`single-user incident`); Observability fields present, probe verb allowlisted, literal expected output, credential-declared; no PAT-shaped variable; no UI-surface file (so no `.pen` is required); Encryption Posture present with an exception block carrying `tracking_issue` and `expires_on`; Guard Contract lint green (5 guards); Scope Check has exactly one live section and no BLOCKED marker.
- **Propagation.** `tasks.md` carries the 900/900 heartbeat, the flag, the cut trigger and the `/fail` resolution.

### Work-phase measurements: Phase 0.5 and 0.6 (2026-10-19)

- **Observer error flag.** The dispatcher's `onToolResult` block was `{ toolUseId, command, output }`: `extractBashToolResults`
  in `soleur-go-runner.ts` dropped the SDK's `tool_result.is_error`. The real SDK does set it for the helper failure
  (`sandbox-wrapped-command-runtime.test.ts` CONTROL row asserts `isError === true` on the real tool_result). Resolution: the
  runner now forwards `isError` (additive, optional field; `false` when absent) and the notice predicate requires it, so the
  "limit to the single-line match" fallback was NOT needed and a non-error result is never rewritten.
- **Helper step census (corrects "14 steps").** The vendored `claude` binary (claude-agent-sdk 0.3.284; identical in claude-code
  2.1.293) carries 17 `apply-seccomp: ...` strings: 16 `<step>` literals that take `: <strerror>`, plus the errno-less
  `observe sendmsg failed`. The plan's list wrongly included `seccomp(unix-block)` (an SDK log label, not a helper line) and
  missed `fork`, `unshare(CLONE_NEWPID|CLONE_NEWNS)` and `write /proc/self/setgroups (nested userns is capability-restricted; caller
  must provide CAP_SYS_ADMIN)`. Format confirmed by forcing each step to fail with EPERM under an `LD_PRELOAD` interposer:
  `apply-seccomp: <step>: Operation not permitted`.
- **Runtime order (interposer log, not source recall).** helper: `unshare(NEWPID|NEWNS)` attempt, `unshare(NEWUSER)`, writes
  (setgroups, uid_map, gid_map), `unshare(NEWPID|NEWNS)` after userns, `fork`; PID-ns init: `prctl(PR_SET_DUMPABLE)`,
  `mount(MS_PRIVATE)`, `mount(/proc)`, `prctl(PR_CAP_AMBIENT_CLEAR_ALL)`, `fork(worker)`; worker: `prctl(PR_SET_NO_NEW_PRIVS)`,
  `prctl(PR_SET_SECCOMP)`, `execvp`; both waiters print `waitpid` after the command ran. Pre-fork subset = the 11 steps before
  `fork(worker)`; the other 5 (`fork(worker)`, NO_NEW_PRIVS, SET_SECCOMP, `execvp`, `waitpid`) are classified (they page) but never
  rewritten. Guard 2 floors therefore use 16/17, not 14/15.
- **Callers (corrects "five callers").** Direct call sites of `buildAgentSandboxConfig`/`buildAgentEnv` in `server/`: only
  `agent-runner-query-options.ts` (`buildAgentEnv` L302, `buildAgentSandboxConfig` L366), reached through
  `buildAgentQueryOptions` from `agent-runner.ts` (L2115) and `cc-dispatcher.ts` (L3093), plus the dev script
  `scripts/dev-probe-destroy-ask.ts`. Direct builder callers outside `server/`: `scripts/sandbox-canary.mjs` (config, L1614) and
  `scripts/plugin-root-sandbox-propagation-probe.mjs` (both). `soleur-go-runner.ts` and `agent-outer-wrap.ts` only mention them in
  comments or types. Phase 4's call-site census should assert these, not the plan's five names.
- **Baseline.** `bash plugins/soleur/test/c4-count-parity.test.sh` passes (`Failed: 0`).

### Work-phase measurements: Phase 0.2 item 2 (Logs-alert count, free-tier cap, Sentry rule), 2026-10-19

- **Logs-alert count (live, read-only Telemetry API, names and counts only).** `GET telemetry.betterstack.com/api/v2/alerts` with
  `BETTERSTACK_API_TOKEN_READONLY` returned 17 alerts: the 16 Terraform-managed `logtail_exploration_alert` resources (every
  `soleur-*-prd` alert in `betterstack-logs-alerts.tf`, `agent_sandbox_bash_denial` included, so its apply already landed) plus the
  hand-made "Output utilization high". The new alert makes 18 live and the 17th Terraform-managed one (ADR-218 amendment).
- **Free-tier cap.** Still not documented by the vendor (the pricing page and docs list no per-team Logs-alert cap), and 17 alerts apply
  without a count refusal, so the cap is at least 17. A refusal at 18 is the measurement and would fail the whole push apply; the
  pre-decided fallback (fold the smoke row into `agent_sandbox_bash_denial`'s incident text and rely on Sentry for the deploy signal)
  stays armed but is NOT triggered by evidence: the cap would be exceeded only if the apply is refused. Recorded in ADR-218.
- **Sentry rule on `op=sandbox-canary`.** None in IaC: `apps/web-platform/infra/sentry/*.tf` carries no `sandbox-canary` value (the
  only agent-sandbox rule, `sandbox_startup_failure`, filters `feature=agent-sandbox` AND `op=sdk-startup`). The live project rules
  could not be listed with the available read-only tokens (`SENTRY_ISSUE_RO_TOKEN`, `SENTRY_API_TOKEN`, `SENTRY_AUTH_TOKEN` all
  answer 404 on the `rules/` and `combined-rules/` endpoints, an issue-scoped token), so "no live hand-made rule" is not proven.
  Consequence: the deploy smoke's Sentry event (`op=sandbox-canary`, level error) is currently an unrouted issue, and the page for the
  smoke is the Better Stack alert alone; routing the Sentry event is not in this PR's scope.
- **Live positive control for the new predicate (counts only).** 167 `ci-deploy` rows in 14 days start `SANDBOX_CANARY_FAIL:
  verdict=sandbox_broken` with `(op=sandbox-canary-outer-wrap;`; 45 in 30 days carry `(op=sandbox-canary;`; the full predicate matches
  0 of them.

### Work-phase measurements: Phase 0.2 item 1 (io_uring_setup go/no-go for the AF_UNIX variant), 2026-10-19

- **Result: GO, no ENOSYS rule needed in the variant.** The container seccomp profile the production run tuple loads
  (`apps/web-platform/infra/seccomp-bwrap.json`, `--security-opt seccomp=/etc/docker/seccomp-profiles/soleur-bwrap.json`, pinned by
  `infra/lib/docker-run-tuple.py` `SECCOMP`) is a default-deny allowlist (`defaultAction SCMP_ACT_ERRNO`, errno 1) and names no
  `io_uring_*` syscall in any rule (`grep -c io_uring` is 0; 427 allowlisted names), so `io_uring_setup`, `io_uring_enter` and
  `io_uring_register` return EPERM in the container. A seccomp filter is inherited by every descendant and cannot be removed, so the bwrap
  child and the SDK's helpers sit under it; `IORING_OP_SOCKET` needs a ring, and a ring needs `io_uring_setup`.
- **Live measurement (docker 29.9.1, kernel 7.2.8, `perl -e syscall(425, 4, <120 zero bytes>)`, image `ubuntu:24.04`):**
  `--security-opt seccomp=unconfined` (positive control) rc=3 (a ring fd: the kernel supports io_uring);
  `--security-opt seccomp=<the committed seccomp-bwrap.json>` rc=-1 errno=1 EPERM; docker's built-in default profile rc=-1 errno=1 EPERM.
  The AppArmor leg of the run tuple (`soleur-bwrap`) needs sudo and was not exercised; it is not part of this question.
- **Consequence.** The bypass is closed by the profile, so the variant stays a pure `socket(AF_UNIX)` deny. A JSON-level pin in
  `test/bwrap-userns-seccomp.test.ts` fails if the profile ever allowlists an `io_uring_*` name (that is the moment the variant would
  need its own ENOSYS rule). The host-side AppArmor and the `docker run` tuple stay the production authority; this measurement is the
  workstation reproduction of the profile's behavior, not a production read.

## Research Reconciliation — Spec vs. Codebase

| Brief claim | Reality (checked 2026-10-19) | Plan response |
|---|---|---|
| "add our own `socket(AF_UNIX)` deny to the single bwrap-level seccomp filter" | The filter also applies to the SDK's in-sandbox `socat ... UNIX-CONNECT` bridges, which start before the user command in every session (measured from the real SDK's bwrap argv). A blanket deny breaks egress sessions. | CTO ruling (design A): a second generated artifact, selected per session for no-egress sessions only; egress sessions stay at "auth + masks"; coverage of egress sessions filed as #10549. |
| "wired next to `run_faithful_sandbox_canary` in `ci-deploy.sh`" | Wiring point is `ci-deploy.sh` near the `run_faithful_sandbox_canary || true` call in the `CANARY_HEALTHY` block; the template is `run_workspace_isolation_probe`, not `run_canary_replay` (different exec contract). | New `run_sdk_bash_smoke` function with its own ledger, next to the existing calls. |
| "the outer-wrap canary ... misdirected diagnosis" | The runbook's first move for `wrong_elevation_userns` says "check getcap / `--cap-add SYS_ADMIN`", which contradicts ADR-075 2026-10-09 (the elevation was dropped on purpose). | DEMOTE (CTO); the stale first move is replaced by a retirement note. |
| "classify the OTHER helper-step errors" | The helper is skipped while `allowAllUnixSockets` is set, so these lines can only appear if that knob regresses; they matter as a regression net. | Exact-step allowlist code `helper_step_eperm`, pinned to the vendored binary's strings. |
| "verify the Slack wake path (ADR-260) for the new email-only alerts" | ADR-260's Slack integration is dashboard OAuth with no Terraform resource; the Uptime API lists it, but no API ties a Logs-source alert to it. | Read-only check script that reports what the API can prove and never claims "Slack wakes"; operator-only residue named. |

## Problem Statement / Motivation

The 2026-10-06 to 2026-10-16 outage (#10445) left seven detection and posture gaps that the incident PR deliberately deferred.
The faithful canary stayed green over a total Bash outage because its replay ends in `-- true`; the only runtime signal
is a single email-only alert keyed to one exact helper line; users saw the raw `apply-seccomp:` text; the red outer-wrap
canary taught the team to ignore a report-only red signal; and `allowAllUnixSockets` removed the only AF_UNIX block. This
PR closes the detection gaps first (smoke, alert, synthetic, classifier), then tightens the posture where the SDK's own
structure allows, and retires the signal that trains people to ignore alerts.

## Proposed Solution

Seven work items in one PR, ordered by blast radius (lowest first) so each phase is independently revertable:

1. **Demote the outer-wrap canary** (CTO ruling DEMOTE): remove the deploy call, ledger, deploy-status field, soak script
   and their tests; keep `--replay-outer`, its fixture and classifier; ADR-079 addendum and runbook.
2. **Classifier and message**: `helper_step_eperm` (exact-step allowlist), alert filter widened to an IN list, a
   whole-output pre-exec predicate, the fixed platform notice on the streamed output, and a prompt directive (server-only,
   no `components/**` edit).
3. **Deploy-time SDK Bash smoke** (non-blocking): baked probe, `run_sdk_bash_smoke` in `ci-deploy.sh`, its own ledger and
   `sdk_bash_smoke` deploy-status field, `faithful_canary_sandbox_broken` Better Stack alert, promotion tracker #10548 with a
   stateless verdict script.
4. **AF_UNIX deny variant** for no-egress sessions (second artifact, per-session selector from one pure function).
5. **Runtime synthetic**: a 15-minute host timer per web host running the same probe against the RUNNING container, with a
   per-host dead-man heartbeat. This is the phase with a documented cut line (see Risks).
6. **Slack wake check**: read-only script plus the dated result in the runbook.
7. **Records**: ADR-079/075/218 addenda, C4 edge prose, runbooks, #10455 comment listing what remains.

## Technical Considerations

- **Dark launch.** The smoke is a deploy-time check that could, once promoted, roll back a release. It ships NON-BLOCKING:
  `run_sdk_bash_smoke || true`, verdicts recorded to a ledger, paging through the journald alert only, `smoke_infra_error`
  never pages and never rolls back. Promotion is the separate tracker #10548 (5 greens over at least 3 days with the
  coverage field). This PR does not validate the gate with the deploy it gates.
- **Script/image ordering.** `ci-deploy.sh` is delivered to hosts separately from the image. New script with an old image:
  the probe file is absent, `docker exec ... test -f` fails and the verdict is `smoke_infra_error reason=probe_absent`
  (never `sdk_bash_smoke_failed`, never a rollback). Old script with a new image: no field is written and
  `cat-deploy-state.sh` serves the `unknown` sentinel. Both orderings get `ci-deploy.test.sh` rows.
- **Exec envelope.** The canary container's `Config.Env` is the full prd env and the probe copies `process.env` into the
  SDK child, so the exec is `/usr/bin/env -i` with an explicit allowlist, the decoy `ANTHROPIC_API_KEY`, no `-u`, a host
  `timeout`, and the container's real `HOME` (the transcript mask derives from it). Canary and prod run tuples are already
  held equal by `infra/lib/docker-run-tuple.py` (POSTURE_DIVERGENCE), so the smoke certifies the prod tuple.
- **Targeting and ledger atomicity (flow review).** `run_sdk_bash_smoke` execs ONLY the canary container
  (`soleur-web-platform-canary`), never the live prod container (a test row covers "prod present, canary absent"). The ledger
  write is ONE atomic write: `write_sandbox_canary_state` gains an optional extra-JSON argument (`coverage`,
  `consecutive_infra_error`) merged by its existing jq, with no second patch; a failed write yields `smoke_infra_error`,
  never a coverage-less pass.
- **Probe contract.** The probe computes its own verdict in JavaScript (unit-testable with node): `pass` only when the real
  tool_result contains a fresh per-run random nonce echoed by the wrapped Bash command AND the coverage is the shim-and-wrapper
  tuple; `sdk_bash_smoke_failed` when Bash WAS dispatched (the stub delivered the tool_use turn) and either the tool_result or a
  thrown SDK error carries a sandbox signature (`apply-seccomp`, `bwrap`, `unshare`, `seccomp`, `sandbox required but
  unavailable`, EPERM), or no nonce came back, or the call hung (signature-independent, so a new error wording cannot go
  silent: the #10445 shape); `smoke_infra_error` only when Bash was never dispatched (module missing, stub server failure,
  docker rc 125/126/127, ledger write failure) and for a `pass`-shaped result whose coverage is `replay_only` (a HOLD: it
  must not increment `consecutive_pass`; a `ci-deploy.test.sh` row pins it). The host `timeout` is 150 s
  (`SDK_BASH_SMOKE_TIMEOUT`), above the probe's 120 s internal cap. It prints one `SDK_BASH_RESULT` JSON line carrying
  `verdict`, `reason`, `coverage` (`sdk_wrapper_shim_prodtuple`, or `replay_only`). Persistent blindness guard: the ledger
  also holds `consecutive_infra_error`; at 3 in a row a `SDK_BASH_SMOKE_STALE` journald row and a Sentry warning (not a page,
  not an email) are emitted, so a dead probe (for example `probe_absent` after a Dockerfile regression) cannot stay silent.
- **Literal config parity (CTO F1).** The prod image has no TypeScript sources; the probe keeps a literal sandbox config
  and a vitest parity test deep-equals it with `buildAgentSandboxConfig` output for the no-egress shape, so a builder edit
  reds the test (the deny list is pinned the same way).
- **Filter variant (CTO).** `gen-bwrap-userns-seccomp.mjs --variant unixdeny` emits `bwrap-userns-clone3-unixdeny.bpf`:
  the existing rules plus `socket` (nr 41, and 41|X32) with the low 32 bits of arg0 equal to 1 returning EPERM;
  `socketpair` untouched; arch gate kept; `--check` verifies both; the base artifact stays byte-identical so the C4 render
  path is provably unchanged. One pure function `seccompArtifactFor(allowGithubEgress)` feeds both
  `buildAgentSandboxConfig` and `buildAgentEnv`, and `buildAgentEnv` sets `SOLEUR_BWRAP_SECCOMP_BPF` to the
  variant path only for no-egress sessions while the runtime flag below is ON, and otherwise passes the ambient value through
  unchanged (this preserves the ADR-075 #8752 incident-time override for egress sessions; the CTO's "always set" is amended by
  the architecture review, because the flag defaults OFF). An absent selector falls back to the base artifact
  (today's posture); that silent-weak direction is made loud by `probeAgentSandboxHardening` and the canary verifying both
  artifacts and a dispatcher test that env and config agree for both egress values. `IORING_OP_SOCKET` (kernel 5.19+)
  bypasses a `socket()` filter: the run-tuple suite measures whether the container profile already blocks
  `io_uring_setup`; if not, ENOSYS for it is added to the variant. Flip to descoping if the real-SDK run shows the variant
  breaks no-egress Bash, or the bypass cannot be closed cheaply (the `io_uring_setup` measurement is a Phase 0.2 go/no-go
  made BEFORE the artifact is generated).
- **Runtime kill-switch for the variant (architecture review P1).** The variant reaches every no-egress tenant at merge, and
  its only runtime detector is a non-blocking smoke, which is the #10445 shape; under squash-merge a revert is the whole PR.
  `seccompArtifactFor` therefore reads a runtime flag `agent-sandbox-unix-deny` (created with `soleur:flag-create`, default
  OFF = the base artifact, i.e. today's posture). The deploy smoke sets the selector explicitly, so it exercises the variant
  on the canary BEFORE the flag is on. Enabling the flag is a production write: it happens only after the smoke has been
  observed green on a real deploy, and only with the operator's explicit authorization at that time
  (`hr-menu-option-ack-not-prod-write-auth`); it is tracked in #10548 and recorded as an `operator (production-write)` row in
  `decision-challenges.md`. All five callers of `buildAgentSandboxConfig`/`buildAgentEnv` (`agent-runner`, `soleur-go-runner`,
  `cc-dispatcher`, `agent-outer-wrap`, `agent-runner-query-options`) are swept; a spawn-time assertion makes env and config
  agree, and `allowGithubEgress` must be shown constant for the lifetime of a query.
- **Message rewrite (CTO F3, amended by the CPO, CLO and architecture reviews 2026-10-19).** The rewrite applies only when the
  trimmed tool output is exactly ONE non-blank line, that line is a classified pre-exec platform denial, and the observer's
  block reports an error result (confirm in Phase 0.2 that `block` carries the SDK `is_error`/exit information; if it does
  not, the rewrite is limited to the single-line match and the forged-line residual is recorded). Anything else, including
  mixed or multi-line output, falls through unchanged. A tenant (or a prompt-injected file) can still print the exact line
  after a command that ran (`rm -rf x && echo "<line>"`), so the notice must not claim a command did not run: "Platform
  notice: command execution is temporarily unavailable on our side. This is a platform issue, not a problem with your
  project." The server-side mirror event is emitted first and keeps carrying only the scrubbed matched line. The prompt
  directive tells the model not to echo raw sandbox text, to retry the same command ONCE only after that notice and only if
  the command is read-only or idempotent (otherwise to ask the user), and after a second failure to stop and tell the user
  to try again later; it carves out the `GH_403_PROMPT_DIRECTIVE` "report LITERAL output verbatim" rule. A forged-line
  negative test and a test that a non-error result is never rewritten are required.
- **Runtime synthetic (CTO F2).** A host timer (`web-bash-synthetic`) runs every 15 minutes under `flock` and `timeout 60`:
  `docker exec soleur-web-platform /usr/bin/env -i ... node /app/infra/lib/sdk-bash-probe.mjs` in synthetic mode (scratch
  `CLAUDE_CONFIG_DIR`, removed after the run, so no synthetic transcript lands in the shared HOME). It pings the host's own
  Better Stack heartbeat only on a verified `pass`; `sdk_bash_smoke_failed` pings the heartbeat `/fail` path when the vendor
  supports it (CONFIRMED by the vendor docs retrieved 2026-10-19: the failed-run branch appends `/fail` to the host's own heartbeat URL; a test
  asserts a failed run never pings the success URL) and otherwise stays silent; `smoke_infra_error` pings nothing. The
  heartbeat payload carries no user or workspace identifiers (CLO). Period 900 s, grace 900 s (CTO 2026-10-19: a 300 s grace would false-page on every deploy that straddles one skipped tick; detection within about 30 minutes of the last good beat, plus an email read; the tier floor is measured in Phase 0.2 and `arm_one` is set explicitly per host).
  Delivered like `web-private-nic-guard`: an SSH `terraform_data` provisioner for running hosts, cloud-init for fresh ones.
  Guards against the deploy swap (flow review P0): the script takes a non-blocking `flock -n` on `/var/lock/ci-deploy.lock`
  (the deploy's FD-200 lock) and skips silently when it is held, skips silently when the container is not `Running` or
  started less than 60 s ago, and a test row races `docker exec` against `docker stop`. The first run happens at timer start
  (`OnBootSec=90s`, like the zot probe) so the ADR-117 arm-and-watch window is not the full period plus grace; the provisioner carries the
  arming construct ADR-117 requires. The CLI spawn lands inside the tenant container's cgroup (`--memory` cap), so Phase 0.2
  measures headroom as a go/no-go before the timer is enabled.

## User-Brand Impact

- **If this lands broken, the user experiences:** every hosted Bash call failing again (the 10-day outage shape), or a
  no-egress session whose Bash starts but a legitimate unix-socket workload (a local Postgres/Redis socket, Python
  multiprocessing Manager) failing with "Operation not permitted", or a chat that shows a "platform issue" notice for a
  command that did run.
- **If this leaks, the user's workflow is exposed via:** a regression in the AF_UNIX selector that leaves a no-egress
  tenant on the permissive artifact (silent-weak: today's posture, not a new exposure), or a wrongly-scoped selector that
  gives an egress tenant the deny and breaks its proxy bridge (availability, not a leak). No new credential, secret or
  tenant data path is introduced; the synthetic carries no tenant data.
- **Brand-survival threshold:** `single-user incident`
- **Threshold decision (challengeable):** one tenant losing Bash (or a false "did not run" claim) is a visible, attributable
  failure of the product's core capability, and the filter and selector sit on the cross-tenant isolation boundary, so
  `aggregate pattern` understates it.

`requires_cpo_signoff: true` is set. CPO advisory 2026-10-19: conditional yes to begin `soleur:work`; conditions are folded in
below (pre-exec whole-output scoping with a negative test; "did not run" wording; the AF_UNIX design resolved by the CTO
ruling so egress sessions are not broken; the smoke stays non-blocking with its own pager and an alert-flap check in the
soak criteria; `soleur:engineering:review:user-impact-reviewer` runs at review; item (d) stays read-only; item (a)'s
retirement of the red canary is recorded in the ADR). CLO advisory 2026-10-19: legal risk low; limits recorded above.

## Observability

> **Scope banner (review round, 2026-10-19).** The runtime synthetic, heartbeat and vector-retag rows below (liveness_signal 2,
> failure_mode 2, the `web-bash-synthetic` unit journal in `logs.where`, and any in_transit rows for them) land in the stacked PR
> (#10455 b) and are NOT in this PR, so failure mode 2 is uncovered here. Layer cites for failure modes 3, 5, 6 and 7 follow below.

```yaml
liveness_signal:
  what: >-
    Three signals. (1) Deploy time: deploy-status field sdk_bash_smoke (verdict, reason, coverage, consecutive_pass,
    first_pass_at) written by run_sdk_bash_smoke on every canary. (2) Runtime: one Better Stack heartbeat per web host,
    pinged only after a verified real wrapped Bash call with a fresh nonce. (3) Tenant signal: the existing
    agent_sandbox_bash_denial alert, widened to both helper codes.
  cadence: "per deploy for (1); every 15 minutes per host for (2); per matching tenant tool_result for (3)"
  alert_target: "Better Stack team email (free tier; Slack wake unverified until item (d) records its result), Sentry op=sandbox-canary for the deploy smoke"
  configured_in: "apps/web-platform/infra/betterstack-logs-alerts.tf (faithful_canary_sandbox_broken, agent_sandbox_bash_denial), apps/web-platform/infra/web-probe.tf (web_bash_synthetic heartbeat), apps/web-platform/infra/ci-deploy.sh (run_sdk_bash_smoke)"

error_reporting:
  destination: "Sentry web-platform (SENTRY_DSN) op=sandbox-canary from ci-deploy.sh; Sentry feature=agent-sandbox op=bash-tool-result from cc-dispatcher; Better Stack Logs via journald (ci-deploy tag) and the app container's pino mirror"
  fail_loud: "journald line 'SANDBOX_CANARY_FAIL: verdict=sandbox_broken reason=sdk_bash_smoke_failed ... (op=sandbox-canary;' pages faithful_canary_sandbox_broken; a missed heartbeat pages web_bash_synthetic; deploy-status .sdk_bash_smoke.verdict is readable over the signed webhook"

failure_modes:
  - mode: "A build whose wrapped Bash command cannot run under the shim filter (the #10445 shape) reaches the canary"
    detection: "run_sdk_bash_smoke executes a real SDK Bash call inside the canary container (in-surface probe: the nonce must come back in the tool_result); verdict sdk_bash_smoke_failed with the sandbox stderr line in reason and a structured coverage field"
    alert_route: "Better Stack faithful_canary_sandbox_broken email (observability layer 3, Vector journald shipper) plus Sentry op=sandbox-canary (layer 2 is not used; the event is posted directly from ci-deploy.sh)"
  - mode: "Wrapped Bash breaks between deploys (a kernel, profile or docker change) or the Vector/journald path is dead"
    detection: "host timer runs the same probe against the running container every 15 minutes (first run at timer start) and pings a heartbeat only on a verified nonce; silence is the signal, so a dead log path cannot hide it; skipped silently while the deploy lock is held or the container is not Running"
    alert_route: "Better Stack heartbeat web_bash_synthetic (per host) email on a missed beat (layer 3 vendor heartbeat; independent of Vector)"
  - mode: "The smoke never dispatched Bash (probe absent in an old image, docker exec rc 125/126/127, stub server failure, ledger write failure, replay-only coverage)"
    detection: "verdict smoke_infra_error with the first docker stderr line in reason; holds the soak, never pages, never rolls back; three in a row (consecutive_infra_error) emit a SDK_BASH_SMOKE_STALE journald row and a Sentry warning so a dead probe cannot stay silent"
    alert_route: "deploy-status field and journald row (observability layer 3, the Vector journald shipper carries the SDK_BASH_SMOKE and SDK_BASH_SMOKE_STALE rows to Better Stack); the stale warning also goes to Sentry (op=sandbox-canary, level warning, posted directly from ci-deploy.sh), deliberately not an email page; flagged on the #10548 tracker by the follow-through at 3 consecutive infra errors"
  - mode: "A helper step other than unshare(CLONE_NEWUSER) fails with EPERM in a live tenant session"
    detection: "classifyBashSandboxFailure returns helper_step_eperm for a whole-line exact-step match; the dispatcher mirror emits one pino row per user per debounce window with sandboxErrorCode"
    alert_route: "agent_sandbox_bash_denial (IN list of both codes), email"
  - mode: "The AF_UNIX selector and the sandbox config disagree (an egress session on the deny artifact, or a no-egress session on the base artifact)"
    detection: "dispatcher unit test asserts env and config agree for both egress values; probeAgentSandboxHardening and the canary verify both artifacts are present and sock_filter-shaped; the deploy smoke runs the no-egress tuple with the selector set, so a variant that breaks Bash start is a sdk_bash_smoke_failed row"
    alert_route: "faithful_canary_sandbox_broken for a broken variant. The spawn-time disagreement is fail-safe since CTO ruling F1 (2026-10-19): checkSeccompAgreement returns the text, buildAgentQueryOptions mirrors it as a Sentry warning through the pino mirror (observability layer 2; feature=agent-sandbox op=seccomp-agreement, debounced) and corrects toward the base artifact. No alert rule keys on it, so it is visible only (Sentry, and the pino row shipped by vector to Better Stack), never a page; CI covers the construction-time agreement"
  - mode: "The user-facing notice is shown for output that is not a pre-exec denial (a false 'did not run')"
    detection: "whole-output predicate unit tests including mixed-output negatives; the mirror event still carries the scrubbed matched line, so the rewrite never removes the page"
    alert_route: "CI; the mirror event is a pino row shipped by vector to Better Stack (observability layers 2 and 3), so agent_sandbox_bash_denial still pages on the underlying code (cc-soleur-go sessions only)"
  - mode: "A tenant forges the exact helper line"
    detection: "accepted limitation (recorded in the runbook): whole-line exact match, per-user per-code debounce; the deploy smoke and the runtime synthetic are the authoritative signals, not tenant text"
    alert_route: "the pino mirror row shipped by vector to Better Stack (observability layers 2 and 3) feeds agent_sandbox_bash_denial, whose email only prompts the check"

logs:
  where: "journald ci-deploy tag on web hosts (SANDBOX_CANARY_FAIL, SDK_BASH_SMOKE rows) shipped by Vector to Better Stack source 2457081; unit journal web-bash-synthetic (SyslogIdentifier retag, shipped by vector.toml Source 4); app container pino rows for the tenant mirror"
  retention: "Better Stack Logs retention per plan (90 days per GDPR Policy telemetry rows); deploy-status ledger holds the latest verdict durably on /mnt/data"

discoverability_test:
  command: bash scripts/followthroughs/sdk-bash-smoke-verdict-10548.sh
  expected_output: sdk_bash_smoke
  credentials_required: "Doppler soleur/prd_terraform WEBHOOK_DEPLOY_SECRET + CF_ACCESS_CLIENT_ID/CF_ACCESS_CLIENT_SECRET - the live /hooks/deploy-status frame is signed and Cloudflare-Access gated, so no unauthenticated probe reads the same property"
```

## Encryption Posture

```yaml
at_rest:
  - store: "hcloud_volume.workspaces_luks (mounted at /mnt/data; holds /mnt/data/ci-deploy-sdk-bash-smoke.json beside the existing ci-deploy-*.json ledgers)"
    mechanism: luks
    evidence: "apps/web-platform/infra/workspaces-luks.tf (hcloud_volume.workspaces_luks, ADR-119/ADR-263); the new file adds no store"
    defends_against: "a seized or RMA'd disk and a raw volume snapshot reading the ledger"
    does_not_defend: "root on the running host (the volume is unlocked while mounted), a leaked deploy-webhook credential reading the signed deploy-status frame, and the ledger's own content (verdict text and a one-line reason, no secret)"
    disclosed_as: not-publicly-claimed
    live_verification: "unavailable:the ledger carries only verdict text; LUKS state is covered by the workspaces_luks_deadman_fired alert, not by this plan"
in_transit:
  - connection: "web host timer -> Better Stack heartbeat (HTTPS ping, web_bash_synthetic URL from Doppler)"
    enforced_at: "apps/web-platform/infra/web-bash-synthetic.sh (curl, default TLS verification, URL resolved from the per-host Doppler key)"
    tls: "TLS 1.2+ (curl defaults), certificate verification on"
    cert_verification: on
    does_not_defend: "a compromised host sending a false beat; the beat proves a probe ran, and the per-host heartbeat keeps a healthy sibling from masking a broken one"
    disclosed_as: not-publicly-claimed
  - connection: "web host timer -> running app container (docker exec over the local docker unix socket, no network hop)"
    enforced_at: "apps/web-platform/infra/web-bash-synthetic.sh"
    tls: "none: local unix-domain docker socket, root-only"
    cert_verification: off
    does_not_defend: "any process with access to the docker socket (root on the host)"
    disclosed_as: not-publicly-claimed
  - connection: "probe -> stub Messages-API server (HTTP on 127.0.0.1 inside the container, ephemeral port, carries only the synthetic prompt and nonce)"
    enforced_at: "apps/web-platform/infra/lib/sdk-bash-probe.mjs"
    tls: "none: loopback within one container, no tenant data"
    cert_verification: off
    does_not_defend: "another process in the same container reading loopback traffic (it carries no secret; the decoy key is a constant)"
    disclosed_as: not-publicly-claimed
exception:
  justification: "Both non-TLS legs are same-host local transports (a root-only unix socket and container loopback) carrying synthetic, non-secret content; TLS would add no property."
  tracking_issue: "#10548"
  reevaluate_when: "the probe starts carrying real tenant data or a credential, or the stub is moved off loopback"
  expires_on: 2027-01-17
```

## Infrastructure (IaC)

### Terraform changes

- `apps/web-platform/infra/betterstack-logs-alerts.tf`: `logtail_exploration.faithful_canary_sandbox_broken` and
  `logtail_exploration_alert.faithful_canary_sandbox_broken` (bwrap_probe_rollback shape, no host_name conjunct); the
  `agent_sandbox_bash_denial` predicate widens to an IN list. Provider: the already-pinned logtail provider; no new variable.
- `apps/web-platform/infra/web-probe.tf`: `betteruptime_heartbeat.web_bash_synthetic` (`for_each = var.web_hosts`, period
  900, grace 900, `paused = true` with `ignore_changes = [paused]` and the ADR-117 arm gate unpausing after a real beat)
  and `doppler_secret.web_bash_synthetic_url` (`WEB_BASH_SYNTHETIC_URL_<HOST>`, masked), mirroring `web_nic_guard`.
- `apps/web-platform/infra/server.tf`: `terraform_data.bash_synthetic_install` (web-1) and a `_web2` twin, the host-scripts
  set, and the env-file write that reuses the web probes Doppler read token; sensitive input: the existing
  `doppler_service_token.web_probes` (no new credential).
- `.github/workflows/apply-web-platform-infra.yml`: `-target=` lines for the two alert resources, the heartbeat, the Doppler
  secret and both provisioners (main plan allowlist; the logtail resources are enforced only by their own drift guard).

### Apply path

(c) cloud-init plus an idempotent delivery path, because a host replace is not viable: web-1 is the cx33-unrebuildable host
(`web-probe.tf` header: the SSH `terraform_data` provisioner is "the sole path that reaches" it), which is the documented
precedent exception to `hr-prod-host-config-change-immutable-redeploy`. The timer, service and script reach web-1 and web-2
through their SSH `terraform_data` provisioners (the same hot-delivery path as `private_nic_guard_install`, applied by the
push workflow, never by a hand edit), and reach fresh hosts through cloud-init and `soleur-host-bootstrap.sh`. The unit is
a side-car that does not touch the app container's image or config. The Better Stack resources apply through the push-triggered main plan.
Expected downtime: none; blast radius: one SDK CLI spawn per host every 15 minutes (a few hundred MB, no network).

### Host fan-out

| Artifact | web-1 | web-2 | Class |
|---|---|---|---|
| `bash_synthetic_install` provisioner (script, service, timer, env file) | `bash_synthetic_install` | `bash_synthetic_install_web2` | `twin` (no credential material beyond the shared read token the other probe twins already receive) |
| per-host heartbeat and Doppler URL key | `web_bash_synthetic["web-1"]` | `web_bash_synthetic["web-2"]` | `for_each = var.web_hosts` (anti-masking by construction) |

`web-host-provisioner-parity.test.sh` enforces the twin; `heartbeat-reprovision-parity.test.ts` and
`arm-heartbeats.test.sh` enforce the heartbeat rows.

### Distinctness / drift safeguards

The heartbeat is created `paused = true` and unpaused only by the executable arm gate after a measured real beat (ADR-117),
so a half-delivered host cannot page. `lifecycle.ignore_changes = [paused]` keeps the unpause from being reverted. State is
the existing encrypted R2 backend; the heartbeat URL lands in `terraform.tfstate` (masked in Doppler).

### Vendor-tier reality check

Free-tier heartbeats are unconditionally creatable (only policies and monitors are `count`-gated); the escalation target
uses the same `var.betterstack_paid_tier` ternary as the siblings. The heartbeat period floor on the free tier is unverified:
read it live at work time before freezing 900 s / 900 s (fallback to the 1800 s grace if the tier floor forbids 900 s). The Logs-alert count (ADR-218: ten applied, free-tier cap unmeasured) rises
by one; ADR-218 gets an amendment recording the count.

## Architecture Decision (ADR/C4)

### ADR

Amend, no new ADR (CTO R3 precedent: addenda unless the filter architecture changes; it does not, it gains a variant):

- **ADR-079** addendum 2026-10-19: (1) the outer-wrap canary is RETIRED because its pass condition (privileged elevation) is
  unreachable by design (ADR-075 2026-10-09), with the re-introduction path under #9773; "Ruled by CTO agent, 2026-10-19:
  DEMOTE"; (2) the `sdk_bash_smoke` contract is now implemented (status line of the 2026-10-16 addendum updated).
- **ADR-075** addendum 2026-10-19: the AF_UNIX posture after the variant artifact: no-egress sessions block `socket(AF_UNIX)`;
  egress sessions stay at "per-session proxy auth + masks"; names the per-command wrapper (#10549) as the only route to cover
  them.
- **ADR-218** amendment: Logs alert count and the `faithful_canary_sandbox_broken` entry.

### C4 views

Read all three of `knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}` at work time. Enumerated
against the change: (a) external human actor: none new; (b) external system: Slack is already modeled (`betterstack -> slack`,
ADR-260) and is not changed by the read-only check; no new vendor; (c) container/data-store: the new `ci-deploy-sdk-bash-smoke.json`
file joins the existing deploy-state files on the already-modeled LUKS volume; the retired `outer_wrap_canary` field is not
named in `model.c4` (grep of the file); (d) actor-surface relationship: the new host-timer -> running-app-container
`docker exec` plus heartbeat ping extends the existing `hetzner -> betterstack` heartbeat edge prose (which names the
nic-guard) and the Better Stack element description (Logs alerts). Planned edits: amend the `hetzner -> betterstack` edge
prose to name the runtime Bash synthetic heartbeat, and the `betterstack` element description to name the deploy-smoke alert.
`plugins/soleur/test/c4-count-parity.test.sh` must stay green (its counts are Sentry cron monitors and workflow check-ins,
none touched); run it and `apps/web-platform/test/c4-code-syntax.test.ts` + `c4-render.test.ts` after the edit.

### Sequencing

All records ship in this PR; none is deferred. ADR-079's promotion status stays `adopting` until #10548 closes.

## Guard Contract

### Guard 1 — faithful_canary_sandbox_broken alert drift guard

**Property.** The alert pages on exactly the journald rows `ci-deploy.sh` emits for an `sdk_bash_smoke_failed` verdict and on no outer-wrap or other sandbox_broken row.

**Assembly.** The chokepoint is the emitter format in `sandbox_canary_sentry_event` (`SANDBOX_CANARY_FAIL: verdict=... reason=... sdk=... (op=...;`), which every canary arm (inner, outer-wrap, workspace-isolation, smoke) shares: the guard reads the marker, the reason needle and the op needle FROM `ci-deploy.sh`, evaluates the SQL predicate against fixture rows in the real `raw` shape (inner `sdk_bash_smoke_failed` positive, `op=sandbox-canary-outer-wrap` negative, inner `bwrap_*` reason negative, a doppler-identifier row quoting the marker negative), and censuses every `logtail_exploration*` resource in the `.tf` for its `-target=` lines in the main plan. Four consumers must agree: the `.tf`, the emitter, the workflow allowlist and the runbook anchor.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Reword the reason needle in the `.tf` (drop `reason=sdk_bash_smoke_failed`) so outer-wrap rows match | RED |
| 2 | Make the guard's fixture loop empty (zero rows evaluated) while leaving the rest intact | RED (floor on evaluated rows) |
| 3 | Add a second alert resource to the `.tf` without its `-target=` lines after a compliant first | RED (census) |
| 4 | Drop the `;` terminator from the op needle so `op=sandbox-canary-outer-wrap` matches | RED |
| 5 | Edit the emitter's op string in `ci-deploy.sh` (the needle is read from it) | RED |
| 6 | Must-PASS (harness row): a fixture row differing from the canonical in a permitted way (longer `sdk=` token, extra reason detail after `sdk_bash_smoke_failed:`) | GREEN |
| 7 | Harness row: replace the suite's predicate evaluator with a constant true | RED |

### Guard 2 — helper-step classifier allowlist

**Property.** Every helper step line the vendored `apply-seccomp` binary can print is either classified (whole-line exact match) or deliberately excluded, no line with a tenant-chosen tail is classified, and only steps that run strictly before the helper forks its worker can ever trigger the user-facing notice.

**Assembly.** Chokepoint: the `BASH_APPLY_SECCOMP_*` matchers and the pre-fork subset in `sandbox-startup-classifier.ts`, used by `classifyBashSandboxFailure` and the notice predicate; consumers: the mirror emitter in `cc-dispatcher.ts` and the alert IN list in the `.tf`. The test reads the step strings from the vendored binary (guarded by the same `shouldSkipRealBinaryRows` helper the argv-tail suite uses, with a non-skipped-row floor so a skip cannot pass vacuously) and asserts the allowlist is a subset of them.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Rename one step in the allowlist so it is absent from the binary | RED (allowlist subset of binary strings) |
| 2 | Add a trailing tenant-chosen tail to a fixture helper line | RED if classified (it must stay unclassified) |
| 3 | Make the vendored-binary scan return zero strings, or let the real-binary rows skip | RED (floor: at least one non-skipped row and at least 14 strings) |
| 4 | Add a fifteenth allowlisted step that is not in the binary after a compliant first fourteen | RED |
| 5 | Add `waitpid` (a post-fork step) to the pre-fork subset | RED (a `waitpid` EPERM fixture must not trigger the notice) |
| 6 | Mixed output (one helper line plus one ordinary line) passed to the notice predicate | RED if it returns true |
| 7 | Harness: must-PASS fixture with CRLF endings and leading whitespace the contract permits | GREEN |

### Guard 3 — AF_UNIX variant artifact, selector and kill-switch

**Property.** A no-egress session with the runtime flag ON is spawned with the artifact that returns EPERM for `socket(AF_UNIX)` and allows `socketpair`; every other session gets the base artifact; the base artifact is byte-identical to today's.

**Assembly.** Chokepoints: `seccompArtifactFor` (the one function, which reads the runtime flag), `buildAgentSandboxConfig` (`allowedDomains`), `buildAgentEnv` (`SOLEUR_BWRAP_SECCOMP_BPF`), the five caller modules (`agent-runner`, `soleur-go-runner`, `cc-dispatcher`, `agent-outer-wrap`, `agent-runner-query-options`), the shim's artifact load, `gen-bwrap-userns-seccomp.mjs --check` (both artifacts; `emit()` stays exported), `probeAgentSandboxHardening`, and the C4 render path (reads the env from process env, never from `agentEnv`).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Make `buildAgentEnv` ignore `seccompArtifactFor` (always the base path) with the flag ON | RED (dispatcher agreement test) |
| 2 | Regenerate the base artifact with the unixdeny rule included | RED (golden-bytes test on the base artifact) |
| 3 | Make the interpreter-level test table empty | RED (floor on rows) |
| 4 | Flip the arg0 compare from low word to full 64 bits | RED (junk-upper-bits case must still EPERM) |
| 5 | Add `socketpair` (nr 53) to the deny set after the compliant `socket` rule | RED (`socketpair(AF_UNIX)` allowed row) |
| 6 | Remove the x32 variant of the `socket` rule | RED (x32 row) |
| 7 | Point the unreadable-alternate shim test at a readable file | RED (the shim must exit 65 on an unreadable alternate) |
| 8 | Default the runtime flag ON | RED (flag-default test: the flag is OFF unless set) |
| 9 | One of the five caller modules builds its own env without `seccompArtifactFor` | RED (call-site census test) |

### Guard 4 — deploy probe config parity

**Property.** The probe's literal sandbox config and selector path equal what `buildAgentSandboxConfig` and `buildAgentEnv` produce for the no-egress shape with the flag ON, and the probe's verdict logic classifies each known outcome correctly (including the dispatched-but-no-nonce case).

**Assembly.** Chokepoints: `buildAgentSandboxConfig`, `buildAgentEnv`, the literal in `sdk-bash-probe.mjs`, the `MASKED_DIRS` derivation (`peerMessagingSocketDirs`, `sessionTranscriptDirs`), and the verdict function; the parity test deep-equals the config and the selector path, prints the diff and the exact fix on failure, and the verdict table runs under node. The egress shape is exercised pre-merge by the real-SDK egress arm, not by the deploy smoke (recorded as out of scope).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Drop `allowAllUnixSockets` from the probe literal | RED (parity) |
| 2 | Verdict table with zero rows | RED (floor) |
| 3 | Add a new `denyRead` entry to the builder after the compliant ones | RED (parity) |
| 4 | Probe returns `pass` when the nonce is absent but exit is clean | RED (nonce row) |
| 5 | Probe returns `smoke_infra_error` when Bash was dispatched and hung | RED (hang row) |
| 6 | Change the probe's selector path literal | RED (selector pin) |
| 7 | Harness: must-PASS config differing from canonical only by key order | GREEN |

### Guard 5 — outer-wrap retirement leaves no live reader

**Property.** After the demotion no host script, deploy-status field, workflow, skill reference or follow-through reads or writes the outer-wrap ledger, while `--replay-outer` and its fixture still work.

**Assembly.** Chokepoints: `ci-deploy.sh` (call, function, state-file variables, alias block), `cat-deploy-state.sh` (reader and merge), `scripts/test-all.sh`, both shard TSV pairs, the bearer-sweep table, the masked-proc docker suite (still runs `--replay-outer`), and a repo-wide `git grep` for `outer_wrap_canary`, `OUTER_WRAP_CANARY` and `run_outer_wrap_canary` outside the historical record (the PIR, archives, the ADR addendum and the retirement note).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Re-add the `run_outer_wrap_canary || true` call | RED (absence assertion in `ci-deploy.test.sh`) |
| 2 | Re-add `outer_wrap_canary` to the deploy-status merge | RED (`cat-deploy-state.test.sh` absence row) |
| 3 | Delete the soak script but leave its `test-all.sh` line | RED (suite references a missing file) |
| 4 | Delete `--replay-outer` from `sandbox-canary.mjs` | RED (kept tests and the docker suite) |
| 5 | Add an `.outer_wrap_canary` reader to a workflow or skill reference | RED (repo-wide grep absence row) |

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "add our own `socket(AF_UNIX)` deny to the single bwrap-level seccomp filter, replacing the per-command Unix-socket block that was lost (`socketpair` stays allowed)" [brief #10455 a] | Phase 4 (variant artifact, selector) | mapped |
| 2 | "runtime synthetic that runs the wrapped Bash command, with a dead-man arm" [brief #10455 b] | Phase 5 (host timer + heartbeat) | mapped |
| 3 | "plain-language user-facing message instead of the raw `apply-seccomp: ...` error, with a retry path" [brief #10455 c] | Phase 2 (notice + directive) | mapped |
| 4 | "verify the Slack wake path (ADR-260) for the new email-only Better Stack alerts" [brief #10455 d] | Phase 6 (one-off read-only check, dated result in the runbook, no committed script) | mapped |
| 5 | "classify the OTHER helper-step errors (`apply-seccomp: prctl(...)`/`seccomp(...)` EPERM) beyond the one exact `unshare(CLONE_NEWUSER)` line now matched" [brief #10455 e] | Phase 2 (helper_step_eperm) | mapped |
| 6 | "leave them open and keep the issue open via a comment listing what remains (use `Ref #10455` rather than `Closes` if any item stays undone)" [brief] | Phase 7 (comment; PR body uses `Ref #10455`) | mapped |
| 7 | "deploy-time SDK Bash smoke in the canary container, non-blocking first (`wg-dark-launch-deploy-gates`), wired next to `run_faithful_sandbox_canary` in `ci-deploy.sh`, verdicts pass / sdk_bash_smoke_failed / smoke_infra_error (infra errors never roll back), `sdk_bash_smoke` field in deploy-status" [brief #10453] | Phase 3 | mapped |
| 8 | "second Better Stack alert `faithful_canary_sandbox_broken` with its tests" [brief #10453] | Phase 3 (alert + drift guard) | mapped |
| 9 | "Decide fix-vs-demote. This is a TECHNICAL fork: spawn the CTO agent to rule (record `Ruled by CTO agent`), do NOT ask the operator; record the outcome in ADR-079 and the canary-probe-set runbook." [brief #10454] | Phase 1 + decision-challenges row | mapped |
| 10 | "Plan must satisfy observability gates (hr-observability-as-plan-quality-gate, no-SSH runbooks)" [brief] | `## Observability`, Phase 7 runbooks | mapped |
| 11 | "Fix these three open issues in ONE PR (Closes #10455, Closes #10453, Closes #10454 in the PR body, not the title)" [brief] | whole plan; PR body `Closes #10453`, `Closes #10454`, `Ref #10455` (asks 1-6 leave #10455 items open, per ask 6) | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Phase 1 demotion (ci-deploy, cat-deploy-state, soak script, tests, docs) | "Decide fix-vs-demote." | asked |
| Phase 2 classifier, notice, directive, alert IN list | "classify the OTHER helper-step errors" and "plain-language user-facing message" | asked |
| Phase 3 smoke, ledger, field, alert, guard | "deploy-time SDK Bash smoke in the canary container, non-blocking first" | asked |
| Phase 3 promotion tracker #10548 and `sdk-bash-smoke-verdict-10548.sh` | "5 green `sdk_bash_smoke` verdicts" is the issue's promotion step; brief: "non-blocking first (`wg-dark-launch-deploy-gates`)" | asked |
| Phase 4 variant artifact + `seccompArtifactFor` | "add our own `socket(AF_UNIX)` deny to the single bwrap-level seccomp filter" | asked |
| Phase 5 host timer, heartbeat, provisioners, parity registrations | "runtime synthetic that runs the wrapped Bash command, with a dead-man arm" | asked |
| Phase 5 parity registrations (`heartbeat-manifest.ts`, `arm-heartbeats.sh`, `terraform-target-parity`, `fresh-boot-parity`, bootstrap, `cloud-init-user-data-size`, `validate-infra-templates`, `web-host-birth-gate`, `guard-vacuity-floor`, envwrite/read-token) | — | inferred — justification: each is an enforcement contract that reds CI when a new host-resident heartbeat is added without it |
| Phase 4 runtime flag `agent-sandbox-unix-deny` and its flag wiring | "add our own `socket(AF_UNIX)` deny to the single bwrap-level seccomp filter" | inferred — justification: the architecture review found the variant would otherwise reach every no-egress tenant behind a non-blocking canary (the #10445 shape), and under squash-merge a revert is the whole PR |
| Phase 6 one-off Slack wake read | "verify the Slack wake path (ADR-260)" | asked |
| Phase 7 ADR addenda, C4 edge prose, runbooks | "record the outcome in ADR-079 and the canary-probe-set runbook" | asked |
| Retire `sandbox-readback-10445.sh` and its test | — | inferred — justification: its own header prescribes deletion when tracker #10456 closes (it is closed), and leaving it would rot; marked taste in decision-challenges |
| Issue #10549 (egress-session AF_UNIX follow-up) | "leave them open" (remaining and deferred capabilities need a tracking issue) | inferred — justification: the CTO design leaves egress sessions uncovered and a deferral without an issue is invisible |

### Split Assessment

- Subsystems touched: 6 — apps/web-platform, plugins/soleur, scripts, tests, .github, knowledge-base
- Planned files: 88 | Estimated changed lines: 3300
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: split — PR-A: Phases 1-3 + 6 (demotion, classifier/message, deploy smoke + alert, Slack check); PR-B: Phases 4-5 (AF_UNIX variant, runtime synthetic and its host fan-out). The operator's brief directs ONE PR ("Fix these three open issues in ONE PR"), so the plan keeps one PR, orders commits by blast radius (Phase 1 first, Phase 5 last) and defines the cut line in Risks: if Phase 5 overruns, it moves to its own PR without touching Phases 1-4, and #10455 stays open either way (`Ref`).

## Implementation Phases

### Phase 0 — Setup and go/no-go measurements (before editing)

- 0.1 Re-read the CTO rulings in `knowledge-base/project/specs/feat-one-shot-10455-10453-10454-sandbox-followups/decision-challenges.md`.
- 0.2 Measure, with the result written into the plan's Research Insights or the runbook (each is a go/no-go for the phase it
  names):
  1. Phase 4: does the container seccomp profile already block `io_uring_setup` (docker run-tuple measurement)? If not, can ENOSYS for
     it be added to the variant cheaply? If neither, Phase 4 is descoped to the flag-gated artifact being NOT enabled and the ADR-075
     addendum records why (CTO flip condition).
  2. Phase 3: the current Logs-alert count and the free-tier cap (read live via the Telemetry API and the ADR-218 amendments),
     and whether a Sentry alert rule already pages on `op=sandbox-canary`; if the cap would be exceeded, the pre-decided fallback is to
     fold the smoke row into the existing `agent_sandbox_bash_denial` alert's incident text and rely on Sentry for the deploy signal.
  3. Phase 5: Better Stack heartbeat period floor (live read; `/fail` is already confirmed by the vendor docs); the prod container's memory headroom
     for one SDK CLI spawn; `cloud-init.yml` user_data size headroom against the 32 KB cap (`cloud-init-user-data-size.test.ts`).
  4. Phase 2: does the tool_result observer's `block` carry an error flag / exit information; the helper's step order (which of the 14
     steps run strictly before the worker fork), read from the vendored binary and the incident reproduction.
  5. Baseline: `bash plugins/soleur/test/c4-count-parity.test.sh` green; the five caller modules of `buildAgentSandboxConfig` /
     `buildAgentEnv` listed with `git grep`.
- 0.3 Write the RED tests of each phase before the code (`cq-write-failing-tests-before`).

### Phase 1 — Demote the outer-wrap canary (#10454)

1. `apps/web-platform/infra/ci-deploy.sh`: delete `run_outer_wrap_canary`, its call in the `CANARY_HEALTHY` block, the
   `SANDBOX_OUTER_WRAP_CANARY_STATE_FILE` / `OUTER_LEDGER_ALIAS` blocks; leave a short comment at the former call site:
   "no outer-wrap verdict: retired, see ADR-079 addendum 2026-10-19". Keep `run_canary_replay` and the emitter format
   untouched.
2. `cat-deploy-state.sh`: delete `outer_wrap_canary_json` and the `outer_wrap_canary` merge key; `cat-deploy-state.test.sh`
   (rows near "Outer-wrap canary verdict") become absence assertions; `sandbox-canary-soak.test.sh` loses the OWRITER/OREADER
   assertions and the `sandbox-canary-outer-wrap` greps; `ci-deploy.test.sh` loses the `MOCK_CANARY_REPLAY_OUTER_OUT` mock arm
   and the D6d case and gains an absence row (no `--replay-outer` exec, no `outer_wrap_canary` key).
3. Delete `scripts/followthroughs/tenant-outer-wrap-soak-5863.sh` and `.test.sh`; remove their entries from
   `scripts/test-all.sh`, `tests/scripts/test-argv-bearer-sweep.sh`, `scripts/suite-shard-legs.tsv(.n)` and
   `scripts/suite-durations.tsv(.n)` in the same commit (a dangling entry reds the suite); confirm no scheduled follow-through workflow
   references either deleted script.
4. Defense-removal analysis (the outer-wrap canary bounded one property): it asserted the privileged-elevation outer mount table. That
   elevation was dropped on purpose (ADR-075 2026-10-09), `AGENT_OUTER_WRAP` is flag-off in prod, and the mount-table and
   sibling-isolation properties are still measured by the shared `tenant-isolation-inner-probe.sh` payload, `run_workspace_isolation_probe`
   and the faithful inner canary; the `--smoke-outer` CLI-launch gate keeps guarding the fixture. No side-effect role is lost.
5. KEEP, each with a named live consumer: `--replay-outer` and `classifyOuterWrapReplayVerdict` (the masked-proc docker suite and
   `test/sandbox-canary.test.ts`), `infra/agent-outer-wrap-argv.json` and the Dockerfile/.dockerignore bakes (those tests and the
   re-introduction path under #9773), `agent-outer-wrap.ts`, `--smoke-outer` (the CI capture-gate job), and the CI trigger lists. The
   retirement note carries a dated re-evaluate-or-delete trigger (2026-12-19, or when #9773 Stage 1 ships) and a comment on #9773.
6. Docs: `canary-probe-set.md` outer-wrap section replaced by a retirement note (reasons, what stays, how to bring the arm
   back under #9773); `workspace-isolation-canary-probe.md` reference updated; ADR-079 addendum (see ADR section). The PIR keeps its
   historical sentence untouched.
7. External actions (agent-executed at ship time, recorded in the PR body): close #9797 as won't-fix citing the addendum;
   resolve Sentry issue 152662657 with the addendum link via the Sentry API; neither is operator-only.

### Phase 2 — Classifier, notice, directive (#10455 c, e)

1. `sandbox-startup-classifier.ts`: `HELPER_STEPS` exact-match allowlist of the 14 steps; `BashSandboxFailure.errorCode` gains
   `helper_step_eperm` (13 steps) while `helper_userns_eperm` (the userns step) is matched first; export
   `isPreExecSandboxDenialOutput(output, isError)` (true only when the trimmed output is exactly one non-blank line, that line is a
   classified helper line from the pre-fork subset or a bwrap-token EPERM line, and the block reports an error result).
2. `cc-dispatcher.ts`: in the Bash tool_result observer the mirror event is emitted first and unchanged; the streamed `command_stream`
   text becomes the fixed platform notice when the predicate holds. The rewrite sits behind the existing autonomous-posture gate
   (`if (!bashAutonomousPosture) return;`, the `command_stream` path), so it covers autonomous sessions only; non-autonomous sessions
   rely on the directive. The SDK-visible tool_result is NOT rewritten (no hook exists), so the model sees the raw line: the
   directive keys on the raw `apply-seccomp:` / bwrap sandbox error line, not on the notice text. Add
   `BASH_UNAVAILABLE_PROMPT_DIRECTIVE` next to `GH_403_PROMPT_DIRECTIVE`, appended at the same site, with the explicit carve-out of the
   403 directive's verbatim rule and the once-then-stop, idempotent-only retry semantics.
3. `betterstack-logs-alerts.tf`: `agent_sandbox_bash_denial_sql` code conjunct becomes
   `JSONExtractString(raw, 'message', 'sandboxErrorCode') IN ('helper_userns_eperm', 'helper_step_eperm')`; `incident_cause`
   text names both; `sandbox-alerts.test.sh` reads BOTH code needles from the classifier (conjunct count stays exactly four) and
   its mutation rows follow; `betterstack-log-query.md` Standing-alarms row updated.
4. Tests: `sandbox-startup-classifier.test.ts` (each step, EACCES/EINVAL stay unclassified, tail-bearing line unclassified, mixed
   and multi-line output not pre-exec, `waitpid` never triggers the notice, allowlist subset of the vendored binary's strings),
   `cc-dispatcher-bash-sandbox-mirror.test.ts` (notice on a single-line error denial, raw passthrough on mixed output, a forged line
   with a non-error result passes through, mirror event unchanged and emitted first), a prompt-directive sentinel test.

### Phase 3 — Deploy-time SDK Bash smoke (#10453)

1. `infra/lib/sdk-bash-probe.mjs`: add smoke/synthetic mode (`NONCE` env, scratch `CLAUDE_CONFIG_DIR` under a per-run `mktemp -d`,
   `SOLEUR_BWRAP_SECCOMP_BPF` honoured, verdict + reason + coverage computed in JS per the probe contract, one `SDK_BASH_RESULT` line,
   scratch removed); keep the docker-suite control/treatment behaviour unchanged by default.
2. Image: `Dockerfile` COPY of the probe into `/app/infra/lib/`, `.dockerignore` exact-path bang; a Dockerfile/`.dockerignore` parity
   test row.
3. `ci-deploy.sh`: `SDK_BASH_SMOKE_STATE_FILE` (`/mnt/data/ci-deploy-sdk-bash-smoke.json`) with the alias-refusal pattern;
   `run_sdk_bash_smoke` (canary container only; `docker exec ... test -f` presence check; `env -i` exec; host `timeout 150`; rc
   classification; ONE atomic ledger write through `write_sandbox_canary_state` with the extra-JSON argument; reset set
   `sdk_bash_smoke_failed`; ledger stamp `sdk-bash-smoke`; journald line through
   `sandbox_canary_sentry_event sandbox_broken "sdk_bash_smoke_failed: <detail>" ... sandbox-canary` (op stays `sandbox-canary`, the
   issue's contract; the `reason=sdk_bash_smoke_failed` needle discriminates it from other inner-canary rows);
   `SDK_BASH_SMOKE: verdict=... reason=...` row on every run; the `consecutive_infra_error` stale warning; bounded DIAG bundle after
   the page); call `run_sdk_bash_smoke || true` directly after `run_faithful_sandbox_canary || true`.
4. `cat-deploy-state.sh`: `sdk_bash_smoke_json` (sentinel `unknown`) merged as `sdk_bash_smoke`; `cat-deploy-state.test.sh` rows
   (absent, present, malformed, foreign-ledger refusal).
5. `ci-deploy.test.sh`: rows for pass, `sdk_bash_smoke_failed` (journald line shape, ledger reset), a dispatched-but-hung run, a
   `replay_only` pass that holds the counter, `smoke_infra_error` for docker rc 125/126/127, a ledger write failure, probe absent (new
   script + old image), "old script + new image" (field absent), "prod container present, canary absent", and the stale-warning at 3;
   proof that no verdict changes the deploy exit code or rolls back.
6. Alert: `faithful_canary_sandbox_broken` (see Guard 1) plus two `-target=` lines, the new drift guard
   `test/infra/faithful-canary-sandbox-alert.test.sh` (one guard per alert is the sibling convention), an `infra-validation.yml` step and
   path filters, the exact exploration-count bump in `betterstack-send-failed-alert-mutation.test.sh`, the runbook entry in
   `betterstack-log-query.md`, ADR-218 amendment (including the stale "five-step" body count versus the seven-step `.tf` header).
7. Promotion enrollment (rot-prevention for a soak-gated close; kept despite two reviewers asking to defer it, see
   `decision-challenges.md`): `scripts/followthroughs/sdk-bash-smoke-verdict-10548.sh` (+ `.test.sh`), modeled on
   `workspace-isolation-verdict-2640.sh`: exit 0 only at `consecutive_pass >= 5`, span >= 3 days, coverage
   `sdk_wrapper_shim_prodtuple`; exit 1 on a recorded `sdk_bash_smoke_failed`; everything else TRANSIENT; prints a line starting
   `sdk_bash_smoke` on every path; register in `scripts/test-all.sh`, shard TSVs, the bearer-sweep table; bump
   `BASELINE_DECLARED_PROBES`. Tracker #10548 already carries the directive and the `follow-through` label.
8. Runbook: `canary-probe-set.md` SDK-smoke section converted from PLANNED to implemented (decode table, first moves, no-SSH reads,
   the stale warning). A post-merge positive control proves the live alert path: a Better Stack query for the standing historical
   `SANDBOX_CANARY_FAIL` rows (op `sandbox-canary-outer-wrap`, since 2026-10-09) confirms the row shape and the `ci-deploy` identifier
   match the predicate's non-reason conjuncts. No deliberate failing deploy is run against production.

### Phase 4 — AF_UNIX variant behind a runtime flag (#10455 a)

1. `gen-bwrap-userns-seccomp.mjs`: restructure the module-level instruction list into builder functions so `--variant unixdeny` can
   emit the second program (`emit()` stays exported for the tests); the committed `bwrap-userns-clone3-unixdeny.bpf`; `--check`
   covers both; golden-bytes test for the base artifact; interpreter-level cases in `test/bwrap-userns-seccomp.test.ts` (AF_UNIX EPERM
   incl. junk upper bits and x32; AF_INET/AF_INET6/AF_NETLINK and `socketpair(AF_UNIX)` allowed).
2. `agent-runner-sandbox-config.ts`: `seccompArtifactFor`, used by `buildAgentSandboxConfig` and exported for `agent-env.ts`;
   `probeAgentSandboxHardening` verifies both artifacts; `agent-env.ts`: the conditional selector (variant path only for no-egress
   sessions with the flag ON; otherwise ambient pass-through); the five caller modules swept and a spawn-time assertion that env and
   config agree; the runtime flag `agent-sandbox-unix-deny` created with `soleur:flag-create` (default OFF; wiring in the files that
   skill names, e.g. `server.ts` and `.env.example`).
3. Image bake: Dockerfile + `.dockerignore` for the new artifact; the canary hardening probe in `sandbox-canary.mjs` checks it.
4. Real-SDK tests in `sandbox-wrapped-command-runtime.test.ts` (no-egress with the flag ON: Bash works, `socket(AF_UNIX)` EPERM,
   `socketpair` works, curl fails fast; egress: AF_UNIX works and the bridge reaches the proxy; flag OFF: base artifact; the existing
   credential-auth test runs under the egress config); the suite asserts a non-skipped row count (`describe.skipIf(!SANDBOX_OK)` must not
   let it pass vacuously) and `infra-validation.yml`'s docker-suite step is named as the enforcing gate; `sandbox-masked-proc-docker.test.sh`
   run-tuple for the variant; vendored-argv-tail pins (bridge prefix precedes the user command; `--unshare-net`; bridge bind; "Skipping
   seccomp filter" under the knob).
5. ADR-075 addendum that explicitly SUPERSEDES the 2026-10-16 addendum's statements that the replacement is "a single
   `socket(AF_UNIX)` deny in the one filter" and that proxy auth is the only remaining AF_UNIX control. The deploy smoke runs the
   no-egress tuple with the selector set, so a variant that breaks Bash start is reported on the deploy that carries it BEFORE the flag
   is ever turned on.
6. Enablement (post-merge, tracked in #10548 and `decision-challenges.md`): turn the flag on only after the smoke is green on a real
   deploy and with the operator's explicit authorization at that time.

### Phase 5 — Runtime synthetic (#10455 b) — objective cut line

Cut trigger (decided before starting, not after): if, after Phases 1-4, 6 and 7 are complete, adding Phase 5 would push the diff past
100 planned files, or more than three of its parity suites are still red after the first full CI cycle, Phase 5 moves to a stacked
second PR from the same branch and #10455 stays open (`Ref`). Commit order keeps Phase 5 last.

1. `web-bash-synthetic.{sh,service,timer}` and `.test.sh` (mirror `web-private-nic-guard`: `SyslogIdentifier` retag shipped by
   `vector.toml` Source 4, non-blocking `flock -n` on the deploy lock, `timeout 60`, per-run random nonce, heartbeat only on a verified
   pass, `OnBootSec=90s`, no identifiers in the ping); `web-probe.tf` heartbeat + Doppler secret; `server.tf` provisioner pair and
   host-scripts set; `cloud-init.yml` and `soleur-host-bootstrap.sh` first-boot entries; `web-probe-envwrite.sh` and
   `web-probe-read-token.tf` for the env file.
2. `-target` forms mirror `web_nic_guard`: the main-plan lines (unkeyed) and the per-host keyed dispatch lines
   (`-target="betteruptime_heartbeat.web_bash_synthetic[\"${WEB_HOST_KEY}\"]"` and the Doppler secret), because the web-2 host is
   excluded from the main plan's server targets and a for_each target must not drag it in. Registrations that red CI when missing:
   `plugins/soleur/lib/heartbeat-manifest.ts` row, `arm-heartbeats.sh` and its test (explicit `arm_one` values for both hosts from the
   Phase 0.2 measurement), `terraform-target-parity.test.ts`, `heartbeat-live-reconcile.test.ts` fixtures,
   `heartbeat-reprovision-parity.test.ts`, `fresh-boot-parity.test.sh`, `web-host-provisioner-parity.test.sh` (explicit exact-bump rows:
   `FLOOR_BLOCKS` and the census), `cloud-init-user-data-size.test.ts`, `.github/scripts/validate-infra-templates.sh`,
   `tests/scripts/lib/web-host-birth-gate.sh` and its test, `scripts/guard-vacuity-floor.test.sh`, `apps/web-platform/infra/suite-shard-legs.tsv`
   and `suite-durations.tsv`, the Dockerfile `.dockerignore` host-scripts bake set.
3. Tests: exec racing `docker stop`, deploy lock held, container not Running, a failed run never pings the success URL, nonce mismatch.
4. Runbook: `canary-probe-set.md` runtime-synthetic section (decode table; missed-beat first moves with no-SSH reads; worst-case wake
   time stated: about 30 minutes to the alert plus an email read).

### Phase 6 — Slack wake check (#10455 d)

No committed script (two reviewers and the CTO devex review all asked to cut it). During work, one read-only call
`GET https://uptime.betterstack.com/api/v2/slack-integrations` with the read-only token from Doppler plus a read of the Terraform-managed
Logs alerts' escalation targets (Telemetry API path confirmed at work time); the exact commands and the dated result go in the
wake-path paragraph of `canary-probe-set.md` and `betterstack-log-query.md` and in a comment on #10455. The result can only be one of
"no Slack integration connected (alerts are email-only)", "an integration exists at account level (delivery for Logs alerts not
provable from the API)" or "cannot establish"; the ask is mapped as met when the fact is recorded, not when Slack wakes. Operator-only
residue named in the runbook and on #10455: the OAuth consent that connects Slack (`automation-status: UNVERIFIED` - `soleur:work`
attempts a Playwright run up to the consent gate before naming it operator-only), and any paid-tier spend.

### Phase 7 — Records and issue hygiene

ADR-079/075/218 text (ADR-079's status line "time-boxed per the CTO" is updated to the implemented state); `model.c4` edge prose; PIR
pointer to the follow-ups only if a reference is broken; `betterstack-log-query.md`; comment on #10455 listing the unchecked items that
remain (page on >= 2 distinct users; SOCKS proxy-auth probe; peer-messaging protocol auth; legacy runner tool_result observer;
`--pids-limit`; PIR affected-user count; other persisted CLI output; deny set from `agentEnv`; test hardening; masked-dir-precreate
alert) plus the new residuals (EACCES/EINVAL helper failures unalerted; egress sessions uncovered, #10549; the operator OAuth step for
Slack; the retry directive is model-compliance based); PR body `Closes #10453`, `Closes #10454`, `Ref #10455`. The retirement of
`sandbox-readback-10445.sh` (+ test + `test-all.sh` line) is the LAST commit so it can be dropped alone.

## Files to Edit

(asks in brackets; "inferred" entries are justified in the Scope Check)

- `apps/web-platform/infra/ci-deploy.sh` [asks 7, 9]
- `apps/web-platform/infra/ci-deploy.test.sh` [asks 7, 9]
- `apps/web-platform/infra/cat-deploy-state.sh` [asks 7, 9]
- `apps/web-platform/infra/cat-deploy-state.test.sh` [asks 7, 9]
- `apps/web-platform/infra/sandbox-canary-soak.test.sh` [ask 9]
- `apps/web-platform/infra/lib/sdk-bash-probe.mjs` [asks 2, 7]
- `apps/web-platform/infra/sandbox-masked-proc-docker.test.sh` [asks 1, 7]
- `apps/web-platform/infra/betterstack-logs-alerts.tf` [asks 5, 8]
- `apps/web-platform/infra/web-probe.tf`, `server.tf`, `cloud-init.yml`, `soleur-host-bootstrap.sh`, `web-probe-envwrite.sh`, `web-probe-read-token.tf`, `vector.toml` [ask 2]
- `apps/web-platform/infra/arm-heartbeats.sh`, `arm-heartbeats.test.sh`, `fresh-boot-parity.test.sh`, `web-host-provisioner-parity.test.sh`, `suite-shard-legs.tsv`, `suite-durations.tsv` [ask 2; inferred parity]
- `apps/web-platform/scripts/gen-bwrap-userns-seccomp.mjs` [ask 1]
- `apps/web-platform/scripts/sandbox-canary.mjs` (hardening probe checks the second artifact; `--replay-outer` KEPT) [asks 1, 9]
- `apps/web-platform/server/agent-runner-sandbox-config.ts`, `agent-env.ts` [ask 1]
- `apps/web-platform/server/agent-runner.ts`, `soleur-go-runner.ts`, `agent-outer-wrap.ts`, `agent-runner-query-options.ts` (call-site sweep and spawn-time assertion; edit only where a call site does not go through `seccompArtifactFor`) [ask 1; inferred]
- `apps/web-platform/server.ts` and `apps/web-platform/.env.example` (the files `soleur:flag-create` names for the `agent-sandbox-unix-deny` flag) [ask 1; inferred]
- `apps/web-platform/server/sandbox-startup-classifier.ts`, `cc-dispatcher.ts` [asks 3, 5]
- `apps/web-platform/test/bwrap-userns-seccomp.test.ts`, `sandbox-wrapped-command-runtime.test.ts`, `sandbox-vendored-argv-tail.test.ts` [ask 1]
- `apps/web-platform/test/sandbox-startup-classifier.test.ts`, `test/server/cc-dispatcher-bash-sandbox-mirror.test.ts` [asks 3, 5]
- `apps/web-platform/test/infra/sandbox-alerts.test.sh` [asks 5, 8]
- `apps/web-platform/test/infra/betterstack-send-failed-alert-mutation.test.sh` [ask 8]
- `apps/web-platform/Dockerfile` and `apps/web-platform/.dockerignore` [asks 1, 7]
- `.github/workflows/apply-web-platform-infra.yml`, `.github/workflows/infra-validation.yml`, `.github/scripts/validate-infra-templates.sh` [asks 2, 8]
- `plugins/soleur/lib/heartbeat-manifest.ts`, `plugins/soleur/test/heartbeat-live-reconcile.test.ts`, `plugins/soleur/test/heartbeat-reprovision-parity.test.ts`, `plugins/soleur/test/terraform-target-parity.test.ts`, `plugins/soleur/test/cloud-init-user-data-size.test.ts` [ask 2; inferred parity]
- `plugins/soleur/test/preflight-discoverability-test.test.ts` (bump `BASELINE_DECLARED_PROBES` from 70 to 71 with a PLACEMENT/TRUTH/NO-SUBSTITUTE entry for this plan's credential-declared probe) [ask 10; inferred ratchet]
- `scripts/test-all.sh`, `scripts/suite-shard-legs.tsv`, `scripts/suite-shard-legs.tsv.n`, `scripts/suite-durations.tsv`, `scripts/suite-durations.tsv.n`, `scripts/guard-vacuity-floor.test.sh`, `tests/scripts/test-argv-bearer-sweep.sh`, `tests/scripts/lib/web-host-birth-gate.sh`, `tests/scripts/test-web-host-birth-gate.sh` [asks 2, 7, 9]
- DELETE `scripts/followthroughs/tenant-outer-wrap-soak-5863.sh` and `.test.sh` [ask 9]
- DELETE `scripts/followthroughs/sandbox-readback-10445.sh` and `.test.sh` (last commit) [inferred, taste]
- `knowledge-base/engineering/operations/runbooks/canary-probe-set.md`, `betterstack-log-query.md`, `workspace-isolation-canary-probe.md` [asks 4, 9, 10]
- `knowledge-base/engineering/architecture/decisions/ADR-079-faithful-sandbox-canary-and-profile-redeploy-verification.md`, `ADR-075-agent-sandbox-tenant-read-isolation.md`, `ADR-218-native-better-stack-logs-alerts-are-terraform-managed-via-the-logtail-provider.md` [asks 1, 8, 9]
- `knowledge-base/engineering/architecture/diagrams/model.c4` [ask 2]

## Files to Create

- `apps/web-platform/infra/bwrap-userns-clone3-unixdeny.bpf` [ask 1]
- `apps/web-platform/infra/web-bash-synthetic.sh`, `.service`, `.timer`, `web-bash-synthetic.test.sh` [ask 2]
- `apps/web-platform/test/infra/faithful-canary-sandbox-alert.test.sh` [ask 8]
- `apps/web-platform/test/sdk-bash-probe-parity.test.ts` [ask 7]
- `scripts/followthroughs/sdk-bash-smoke-verdict-10548.sh` and `.test.sh` [ask 7; promotion]
- `knowledge-base/project/specs/feat-one-shot-10455-10453-10454-sandbox-followups/tasks.md`

## Open Code-Review Overlap

Checked 2026-10-19 (two-stage `gh issue list --label code-review --state open` then `jq --arg path` over the main Files
lists). Three open code-review issues name files this plan edits:

- #3243 (decompose `cc-dispatcher.ts` into focused modules) and #3242 (`tool_use` WS event lacks a raw name field), both on
  `apps/web-platform/server/cc-dispatcher.ts`: **Acknowledge.** Different concerns (module decomposition; a WS event field);
  this plan adds a bounded block next to existing sibling blocks and a constant beside `GH_403_PROMPT_DIRECTIVE`, and does not
  restructure the file. Both stay open.
- #2197 (billing `SubscriptionStatus` type and throttle doc), on `apps/web-platform/infra/server.tf`: **Acknowledge.** Unrelated
  concern; this plan only adds provisioner resources. Stays open.

## Domain Review

**Domains relevant:** engineering, product, legal

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Six forks and two design questions ruled 2026-10-19 (see `decision-challenges.md`): DEMOTE the outer-wrap canary; literal pinned probe config with `env -i` exec; host timer with per-host heartbeat; server-only message; exact-step allowlist; read-only Slack check; alert shape; AF_UNIX variant for no-egress sessions only.

### Product (CPO)

**Status:** reviewed (advisory, sign-off conditional)
**Assessment:** Conditional yes to begin work on `single-user incident`; conditions folded into User-Brand Impact and Phases 2 and 4. Product/UX gate: no file under `components/**`, `app/**` or other UI-surface globs is edited (the message path is server-only, by CTO F3), so the mechanical UI-surface override does not fire. **Tier:** none. **Decision:** auto-accepted (pipeline). **Pencil available:** not required (no UI surface).

### Legal (CLO)

**Status:** reviewed
**Assessment:** Legal risk low. Rewrite only whole-output pre-exec denials; keep it a platform notice; store what the user saw; the synthetic processes no personal data (no identifiers in the heartbeat); no register entry needed. GDPR gate: the `single-user incident` trigger fired the cross-controller check; the mirror event stays at the scrubbed matched line and nothing new leaves the existing processors.

## Acceptance Criteria

<!-- founder-stated check: see plan-founder-check.md -->

### Functional Requirements

- [ ] On a canary, `run_sdk_bash_smoke` (canary container only) records `sdk_bash_smoke` in `/hooks/deploy-status` with verdict in {pass, sdk_bash_smoke_failed, smoke_infra_error}, reason, `coverage: sdk_wrapper_shim_prodtuple` on a pass, and `consecutive_pass`/`first_pass_at` accumulation that holds on infra errors and on a `replay_only` pass; the ledger and its coverage are one atomic write (`apps/web-platform/infra/ci-deploy.sh` `run_sdk_bash_smoke`, `cat-deploy-state.sh` `sdk_bash_smoke_json`).
- [ ] No smoke verdict changes the deploy exit code, rolls back, or aborts under `set -e` (`ci-deploy.test.sh` rows; call site `run_sdk_bash_smoke || true`); three consecutive `smoke_infra_error` emit `SDK_BASH_SMOKE_STALE` and a Sentry warning, never an email page.
- [ ] An old image without the probe yields `smoke_infra_error reason=probe_absent`; an old script with a new image yields the `unknown` sentinel; a present prod container with an absent canary is never exec'd (`ci-deploy.test.sh`, `cat-deploy-state.test.sh`).
- [ ] The probe verdict is `pass` only when the per-run nonce comes back in the real tool_result; Bash dispatched with no nonce, or hung, is `sdk_bash_smoke_failed` (`sdk-bash-probe.mjs` verdict function; node-level table test).
- [ ] The deploy smoke reproduces the incident: with the knob mutated back (off) the docker suite shows `sdk_bash_smoke_failed` with the `apply-seccomp` line (`sandbox-masked-proc-docker.test.sh`); `infra-validation.yml`'s docker-suite step is the named enforcing gate.
- [ ] `faithful_canary_sandbox_broken` matches the inner smoke failure row and NOT an `op=sandbox-canary-outer-wrap` row or an inner `bwrap_*` row; both `-target=` lines exist (`test/infra/faithful-canary-sandbox-alert.test.sh`).
- [ ] `classifyBashSandboxFailure` returns `helper_userns_eperm` for the userns step and `helper_step_eperm` for each of the other 13 allowlisted steps (whole line, EPERM only); tail-bearing and EACCES/EINVAL lines stay unclassified; the allowlist is a subset of the vendored binary's step strings with a non-skipped-row floor (`test/sandbox-startup-classifier.test.ts`).
- [ ] `agent_sandbox_bash_denial` filters on both codes with exactly four ANDed conjuncts (`sandbox-alerts.test.sh`).
- [ ] A single-line error denial from a pre-fork step streams the fixed platform notice in autonomous sessions; mixed, multi-line, non-error and post-fork (`waitpid`) outputs stream unchanged; the mirror event is emitted first with only the scrubbed matched line (`test/server/cc-dispatcher-bash-sandbox-mirror.test.ts`); `BASH_UNAVAILABLE_PROMPT_DIRECTIVE` keys on the raw sandbox error line, is appended, and carves out the 403 verbatim rule (sentinel test).
- [ ] The unixdeny artifact returns EPERM for `socket(AF_UNIX)` (incl. junk upper bits, x32) and allows `socketpair`, AF_INET, AF_INET6, AF_NETLINK; the base artifact is byte-identical; `--check` verifies both (`test/bwrap-userns-seccomp.test.ts`).
- [ ] `seccompArtifactFor` is the single source for config and env across all five caller modules; the runtime flag `agent-sandbox-unix-deny` defaults OFF (base artifact); a dispatcher test proves env and config agree for both egress values and both flag states; an unreadable alternate artifact makes the shim exit 65.
- [ ] Real-SDK run: no-egress session with the flag ON has Bash working, AF_UNIX denied, curl failing fast; egress session AF_UNIX works and the bridge reaches the proxy (`test/sandbox-wrapped-command-runtime.test.ts`, with a non-skipped-row floor); the run-tuple suite passes on the production tuple; the `io_uring_setup` result is either "profile blocks it" or "ENOSYS added to the variant" (not merely recorded).
- [ ] The web-bash-synthetic timer exists for web-1 and web-2 (provisioner twins) and fresh hosts (cloud-init); it skips while the deploy lock is held or the container is not Running; its heartbeat is per host, paused at creation, pinged only on a verified nonce, silent on infra error, first run at timer start; all parity suites listed in Phase 5 are green with explicit exact-bump rows.
- [ ] The Slack wake read is performed and its dated result (one of the three allowed statements) is recorded in the runbook and on #10455; no claim of delivery is made.
- [ ] The outer-wrap deploy call, ledger, `outer_wrap_canary` field, soak script and their registrations are gone and a repo-wide `git grep` finds no live reader outside the historical record; `--replay-outer`, the fixture, the classifier and the docker-suite arm still work; ADR-079 records `Ruled by CTO agent, 2026-10-19: DEMOTE` with the dated re-evaluate trigger; the runbook outer-wrap section is a retirement note; #9797 is closed and Sentry issue 152662657 is resolved with the addendum link (recorded in the PR body).
- [ ] Records: ADR-079, ADR-075 (explicitly superseding the 2026-10-16 "single filter" and "proxy auth is load-bearing" statements), ADR-218 (stale step-count fixed) amendments; `model.c4` edge prose; `c4-count-parity`, `c4-code-syntax` and `c4-render` tests green; a comment on #10455 lists exactly the items that remain open; the PR body uses `Closes #10453`, `Closes #10454`, `Ref #10455`.

### Non-Functional Requirements

- [ ] Security: no credential reaches the probe (`env -i`, decoy key), no tenant data in the synthetic or heartbeat, the rewrite never exposes or removes data beyond the displayed line.
- [ ] Performance: the synthetic is bounded by `timeout 60` and `flock`, one spawn per host per 15 minutes; the deploy smoke is bounded by a host `timeout` and cannot extend the canary window beyond it.
- [ ] NFR register assessment run against `knowledge-base/engineering/architecture/nfr-register.md` (availability, observability, security rows).

### Quality Gates

- [ ] Every suite named above is green locally and registered in `scripts/test-all.sh`/infra-validation; mutation rows of Guards 1-5 are encoded as test rows and each reddens its guard.
- [ ] `soleur:engineering:review:user-impact-reviewer` runs at review (threshold `single-user incident`); preflight Check 10 runs the discoverability command (credential-declared, skipped explicitly).
- [ ] `BASELINE_DECLARED_PROBES` in `plugins/soleur/test/preflight-discoverability-test.test.ts` is bumped 70 to 71 with its PLACEMENT/TRUTH/NO-SUBSTITUTE entry, and the discoverability command names a script that exists in THIS PR's tree.

### Post-merge (agent-executed)

- [ ] Read `/hooks/deploy-status` (call pattern in `plugins/soleur/skills/postmerge/references/deploy-status-debugging.md`) and confirm `.sdk_bash_smoke.verdict` on the first real deploy (the gate is observed on at least one real deploy before any promotion); automation: `gh`/signed webhook read, no operator step.
- [ ] Confirm the first runtime-synthetic heartbeat beat lands per host before the arm gate unpauses it (`arm-heartbeats.sh` executable arm).
- [ ] Close #9797 (won't-fix, ADR-079 addendum link) and resolve Sentry issue 152662657 via the Sentry API; run the Slack wake check and record its dated result on #10455.

## Test Scenarios

### Acceptance Tests (RED phase targets)

- (unit) Given a single-line error output that is exactly a pre-fork helper step line (for example `apply-seccomp: prctl(PR_SET_NO_NEW_PRIVS): Operation not permitted`, order confirmed in Phase 0.2), when classified, then the code is `helper_step_eperm` and the streamed text is the platform notice; given the same text with a non-error result, or a `waitpid` line, then the output streams unchanged.
- (unit) Given an output with the helper line plus `hello`, or a forged helper line after a command that ran, when the notice predicate runs, then it is false and the output streams unchanged.
- (integration) Given a canary container with the probe baked, when `run_sdk_bash_smoke` runs, then deploy-status carries `sdk_bash_smoke.verdict = pass` and `coverage = sdk_wrapper_shim_prodtuple`.
- (integration) Given the knob mutated off, when the smoke runs, then the verdict is `sdk_bash_smoke_failed` and a `SANDBOX_CANARY_FAIL: verdict=sandbox_broken reason=sdk_bash_smoke_failed` journald row is written.
- (integration) Given a no-egress session with the unixdeny artifact, when the command calls `socket(AF_UNIX, SOCK_STREAM, 0)`, then it fails with EPERM, and `socketpair(AF_UNIX)` succeeds.
- (integration) Given an egress session, when the bridge connects, then the proxy answers and the base artifact is in force.

### Regression Tests

- (integration) Given the old image (no probe), when the new `ci-deploy.sh` runs, then `smoke_infra_error` is recorded and the deploy proceeds.
- (unit) Given the retirement, when `cat-deploy-state.sh` runs, then the payload has no `outer_wrap_canary` key and every other key is unchanged.
- (unit) Given the standing outer-wrap journald row shape, when the new alert predicate evaluates it, then it does not match.

### Edge Cases

- (unit) Given CRLF line endings and trailing whitespace around a helper line, when classified, then it matches (permitted variation); given a 5000-character slash-heavy line, then the scan stays linear and bounded.
- (integration) Given two consecutive `smoke_infra_error` runs after three passes, then `consecutive_pass` holds at 3.
- (integration) Given a missed heartbeat on one host while the sibling beats, then only that host's heartbeat alerts.

### Integration Verification (for `soleur:qa`)

- **API verify:** `bash scripts/followthroughs/sdk-bash-smoke-verdict-10548.sh` prints a line starting `sdk_bash_smoke` (credential-declared; reads the signed deploy-status frame).
- **Offline guard:** `bash apps/web-platform/test/infra/faithful-canary-sandbox-alert.test.sh` and `bash apps/web-platform/test/infra/sandbox-alerts.test.sh` exit 0.

## Success Metrics

The next deploy that carries a Bash-breaking build is reported `sdk_bash_smoke_failed` on that deploy (no 10-day blind window); five green smoke verdicts over three days with correct coverage promote it (#10548); the runtime heartbeat alerts about 30 minutes after a between-deploy break (plus an email read); no page text contains `apply-seccomp:` for tenants; no standing red report-only signal remains in `/hooks/deploy-status`.

## Dependencies & Prerequisites

CTO rulings (done); Better Stack read token and Doppler `soleur/prd_terraform` webhook credentials for the read-only checks (exist); the web probes Doppler read token (exists); a measured heartbeat tier floor (Phase 0.2).

## Risk Analysis & Mitigation

- **Largest-diff risk (Phase 5).** The host-resident heartbeat drags in about 25 parity registrations. Objective cut line (Phase 5
  header): over 100 planned files or more than three parity suites still red after the first full CI cycle moves Phase 5 to a stacked
  second PR; Phases 1-4, 6, 7 are independent of it and #10455 stays open (`Ref`) either way. Under squash-merge a revert is the whole PR,
  so independent reversibility comes from the runtime flag (Phase 4), not from commit order.
- **Variant breaks no-egress Bash (tenant boundary).** The flag defaults OFF; the deploy smoke exercises the variant on the canary before
  it is enabled; enabling needs a green smoke on a real deploy and the operator's authorization; the CTO flip-to-descope conditions
  (breakage, uncloseable `io_uring` bypass, different bridge ordering) apply. Per-tenant impact when ON: AF_UNIX listeners/clients in
  no-egress sessions (Python multiprocessing Manager/Listener, local Postgres/Redis socket paths, D-Bus); Node IPC and libuv `socketpair`
  are unaffected; release-notes and a support-runbook line are part of Phase 7.
- **False or over-claiming user notice.** Single-line, error-flagged, pre-fork-step match only; the notice claims "platform issue, not a
  problem with your project", not "nothing ran"; a forged-line negative test; the retry is idempotent-only and model-compliance based
  (a residual recorded on #10455; the SDK turn cap bounds a non-compliant loop).
- **Synthetic runs inside the tenant container's cgroup.** One SDK CLI spawn per host per 15 minutes under `--memory`; Phase 0.2 measures
  headroom as a go/no-go; the timer skips during a deploy swap and while the container is not Running.
- **Alert flap / noise / cap.** One alert row per failed deploy; recovery period 600; the soak review checks rows against real failed
  verdicts (#10548); the Logs-alert cap is measured in Phase 0.2 with a pre-decided fallback.
- **Email-only wake.** Until the operator connects Slack, both alerts email only; this PR records the fact, it cannot change it. Worst-case
  detection for the runtime synthetic is about 30 minutes to the alert plus an email read.
- **Literal config parity trap.** Any `buildAgentSandboxConfig` edit reds `sdk-bash-probe-parity.test.ts`; the failure prints the diff and
  the exact line to change in the probe so the test is a prompt, not a puzzle.

## Resource Requirements

One engineer-agent session per phase group; no new vendor, no new credential; Better Stack free tier.

## Future Considerations

#10549 (per-command wrapper for egress sessions); promotion of the smoke (#10548); bringing the outer-wrap arm back under the executor topology (#9773) with a pass criterion defined by that topology; the remaining #10455 items.

## Documentation Plan

Runbooks (`canary-probe-set.md`, `betterstack-log-query.md`, `workspace-isolation-canary-probe.md`), three ADR amendments, `model.c4`, PIR follow-up pointers, release notes line for the tenant-visible AF_UNIX change in no-egress sessions (CPO).

## References & Research

- Issues: #10453, #10454, #10455, #10445, #10548 (promotion tracker), #10549 (egress AF_UNIX), #9797, #9773.
- Incident record: `knowledge-base/engineering/operations/post-mortems/hosted-agent-bash-apply-seccomp-userns-eperm-postmortem.md`; archived incident plan and decision-challenges under `knowledge-base/project/specs/archive/20261018-020948-feat-one-shot-10445-sandbox-seccomp-eperm/`.
- ADRs: 075, 079, 117, 218, 260; learning `2026-10-18-a-fix-that-removes-a-block-must-re-derive-...`.

## Sharp Edges

- A `## User-Brand Impact` section that is empty, filler-only or without a threshold fails deepen-plan Phase 4.6; this plan's is filled.
- A `faithful_canary_sandbox_broken` needle without the `reason=` conjunct matches the outer-wrap rows while they still exist; the `;` terminator alone is not enough.
- The deploy-status frame is shared by every component's deploy; the smoke reads its own durable ledger, never the frame, for soak accounting.
- Deleting a followthrough script without its `scripts/test-all.sh`, shard-TSV and bearer-sweep entries in the same commit reds the suite.
- The probe's `HOME` must be the container's real `HOME`; `/tmp` silently changes the transcript-mask derivation and the parity test.
- `seccompArtifactFor` must stay the only place that decides the artifact; a second inline decision reintroduces the config/env drift the CTO ruling closes.
