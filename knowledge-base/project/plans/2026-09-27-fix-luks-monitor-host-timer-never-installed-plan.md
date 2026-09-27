---
title: "fix(infra): web-1's luks-monitor.timer was never installed — deliver it through Terraform and prove it runs"
date: 2026-09-27
slug: fix-luks-monitor-host-timer-never-installed
branch: feat-one-shot-8706-luks-monitor-timer-dark
issue: 8706
type: fix
closes: null  # the follow-through closes #8706 after three observed nights; the PR says Ref #8706
priority: p2
domain: engineering
brand_survival_threshold: aggregate pattern
lane: cross-domain
---

# fix(infra): web-1's luks-monitor.timer was never installed

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed).
<!-- Phase 2.8: every systemd action named in this plan runs inside a Terraform-owned
     terraform_data provisioner in the per-merge CI apply; see ## Infrastructure (IaC). -->

## Overview

Issue #8706 reports that web-1's daily LUKS at-rest probe (`luks-monitor.timer`) produces no
off-box output. This plan reads the unit state without SSH, names the cause, moves delivery of
the probe's units onto a Terraform-owned path, adds a positive liveness check keyed on the host
unit's own journald identity, and corrects the runbook paragraph that assumed the timer runs.

## Research Insights

### Root cause (measured, no SSH)

**The timer, its service and `/usr/local/bin/luks-monitor` were never installed on web-1.** It is
not "installed but disabled", not "failing before exec", and not "installed then removed".

1. **Apply log, `apply-web-platform-infra.yml` run `36005279546` (2026-09-24 13:41 UTC).** The
   `terraform_data.luks_monitor_token_install` state-print provisioner (workspaces-luks.tf, the
   `list-timers luks-monitor.timer` remote-exec) printed:
   - `0 timers listed.` for the timer listing;
   - `UnitFileState=` (empty), `ActiveState=inactive`, `LastTriggerUSec=` (empty) for the timer;
   - `Result=success`, `ExecMainStatus=0`, `ExecMainExitTimestamp=` (empty) for the service.

   An installed-but-disabled unit reports `UnitFileState=disabled`. An empty `UnitFileState` with
   default-valued service properties is what systemd reports for a unit that has no unit file.
   Read back with `gh run view 36005279546 --log | grep -E 'timers listed|UnitFileState|ActiveState|LastTrigger|ExecMain'`.
2. **The only installer never ran.** `workspaces-cutover.sh` is the sole delivery site. Its tail,
   after `app_canary` and `disarm_dead_man` (anchor: `# Deliver the standing observability to the
   LIVE host via THIS channel (ADR-119 §(e)).`), installs `luks-monitor.sh` as
   `/usr/local/bin/luks-monitor`, installs the emit helper and both unit files, writes the
   `DOPPLER_TOKEN=` line, and arms the timer. Every `dry_run=false` cutover run died before that
   tail (`gh run list --workflow workspaces-luks-cutover.yml`):

   | run | date (UTC) | outcome |
   |---|---|---|
   | 29782780158 | 2026-07-20 22:07 | host canary PASSED, then `FATAL: app /health=521` in `app_canary` |
   | 29995956562 | 2026-07-23 09:35 | host canary PASSED, then `FATAL: /internal/readyz … reason=readyz_gate_regression code=403` in `app_canary`. **This is the run that left LUKS live.** |
   | 29725194755, 29706401639, 29695998561, 29687729540, 29676994044, 29654062280, 29649845529, 29644526137 | 07-18 … 07-20 | died before the canary (auto-rollback) |

   Every other run of that workflow is `DRY_RUN=1` (`cutover body complete (DRY_RUN=1)`), which never
   reaches the tail. `cleanup()` no-ops once `CANARY_OK=1`, so nothing re-ran it.
3. **The same cause explains two other symptoms, so this is one defect, not three.**
   - The absent `/etc/default/luks-monitor` that #8703's first apply found (`envfile_absent`, fixed
     by #8724): the token write sits in the same unreached tail.
   - The missing `SOLEUR_SENTRY_DSN=` line: cloud-init writes it only at a host's birth
     (`cloud-init.yml`, `printf 'SOLEUR_SENTRY_DSN=%s\n'`), and web-1 predates that line. The file
     #8724 created holds only the token line. `luks-monitor-token-refresh.sh` records this itself:
     "#8706 tracks the missing DSN line".
4. **Why nothing noticed for about nine weeks.**
   - `betteruptime_heartbeat.workspaces_luks` has two pushers by design. `workspaces-luks-verify.yml`
     (daily 04:41 UTC) ships its own copy of `luks-monitor.sh` and pushes the same heartbeat; its own
     comment says this "removes the dependency on a prior cutover having installed
     /usr/local/bin/luks-monitor". One live pusher kept the shared beat `up`. A multi-feeder beat
     alarms only when every feeder stops (learning
     `2026-07-18-shared-delivery-substrate-and-reused-heartbeat-url-masking.md`).
   - `plugins/soleur/lib/heartbeat-manifest.ts` (ADR-117) cites `workspaces-cutover.sh` and the line
     `systemctl enable --now luks-monitor.timer` as the feeder's arming construct. The line exists,
     so the static guard is green over code that never executed (learning
     `2026-07-16-the-fix-for-an-inert-monitor-shipped-a-probe-that-could-never-fire.md`).
   - A failing host run would also have been silent in Sentry. Without the DSN line,
     `workspaces_luks_emit` falls back to `doppler secrets get SENTRY_DSN --config prd` using the
     `prd_workspaces_luks`-scoped token, which cannot read `prd`, and then returns 0 without sending.

### Better Stack re-verification (2026-09-27, `scripts/betterstack-query.sh`)

- `--since 2026-09-24T00:00:00Z --grep luks-monitor` returned 57 rows. The
  `SYSLOG_IDENTIFIER=luks-monitor` rows are the verify job's `SOLEUR_WORKSPACES_READYZ` / `OK:` pairs
  (09-24 09:39 and 13:48, 09-25 09:48, 09-26 09:31, 09-27 10:12) and three
  `SOLEUR_LUKS_HOST_TOKEN_REFRESH` rows. No row falls in any 00:00-00:30 window, and none carries
  `_SYSTEMD_UNIT=luks-monitor.service`. This matches the parent session's reading.
- **`_SYSTEMD_UNIT` is unreliable on `logger` rows (measured).** Raw-SQL tally over three days,
  grouped by identifier, `_TRANSPORT`, and whether `_SYSTEMD_UNIT` is empty:

  | identifier | `_TRANSPORT` | unit present | unit missing |
  |---|---|---|---|
  | ci-deploy | syslog | 527 | 573 |
  | inngest-heartbeat | syslog | 39 | 35 |
  | inngest-heartbeat | stdout | 16480 | 0 |
  | luks-monitor | syslog | 3 | 6 |
  | web-git-data-probe | stdout | 17684 | 0 |
  | webhook | stdout | 18204 | 0 |

  `logger` sends a datagram and exits, and journald often cannot resolve the dead PID's cgroup, so
  it drops `_SYSTEMD_UNIT` about half the time. A unit's stdout stream carries the unit identity
  itself, so every `stdout` row has it. `luks-monitor.sh`'s `log()` writes both
  (`logger -t "$LOG_TAG"` and `echo "[$LOG_TAG] $*"`). Under `luks-monitor.service` the echo is
  journaled as `_TRANSPORT=stdout`, `SYSLOG_IDENTIFIER=luks-monitor` (from the unit's
  `SyslogIdentifier=`), `_SYSTEMD_UNIT=luks-monitor.service`. Over SSH the echo goes to the SSH
  channel and never reaches the journal. **The stdout copy is therefore a host-unit-only row, and its
  `_SYSTEMD_UNIT` is reliable.** `luks-monitor.sh` needs no change to make host runs identifiable.
- **`SYSLOG_IDENTIFIER=systemd` is not shipped.** `vector.toml`'s `host_scripts_journald` allowlist
  has no `systemd` entry (its own comment: a live row "carries SYSLOG_IDENTIFIER=systemd, which NO
  source here admits"), and Source 2's PRIORITY 0-2 cut drops `Failed to start` (PRIORITY 3). The
  silence on that channel is not evidence; the apply log is.
- July 2026 is outside retention (a `luks-monitor` query for 2026-07-23..24 returned 0 rows), so
  what the un-disarmed dead-man timer of run 29995956562 did cannot be read back. The present state
  is measured daily instead: every verify `OK:` row reads `mount_source=/dev/mapper/workspaces`.

### Relevant files

- `apps/web-platform/infra/workspaces-luks.tf`: `terraform_data.luks_monitor_token_install`, the
  sibling installer on the same host with the same `connection {}` shape.
- `apps/web-platform/infra/server.tf`: `terraform_data.git_data_probe_install` (file provisioners,
  enable, list-timers), `terraform_data.journald_persistent` (Vector reload), `local.sentry_dsn_shape_ok`.
- `apps/web-platform/infra/luks-monitor.{sh,service,timer}`, `workspaces-luks-emit.sh` (DSN first,
  Doppler last), `luks-monitor-token-refresh.sh` (token-line owner; keeps other lines byte for byte).
- `apps/web-platform/infra/betterstack-logs-alerts.tf`: ADR-218 native logs alerts.
  `claude_cost_capture_dark` is the exact precedent for an absence alert (`operator = "lower_than"`,
  `value = 1`, `query_period = 86400`, `on_missing_data = "treat_as_zero"`).
- `.github/workflows/apply-web-platform-infra.yml`: the per-merge SSH apply `-target` list (the step
  containing `terraform_data.web_1_host_key_probe`) and the MAIN plan allowlist
  (`-target=logtail_exploration*` lines).
- Guards that enumerate these:
  - `apps/web-platform/infra/web-host-provisioner-parity.test.sh`: G2 `FLOOR_BLOCKS = 20` counts SSH
    `connection` blocks across all `.tf` files and pins `host_key = local.web_1_ssh_host_key`. Its §1
    (`FLOOR_RESOURCES = 18`) and §2 (`FLOOR_DESTS = 59`, "every SSH-written destination has a
    fresh-boot writer") scan `server.tf` only.
  - `plugins/soleur/test/terraform-target-parity.test.ts`: every SSH-provisioned `terraform_data`
    must be targeted by the SSH apply; `MIN_SSH_PROVISIONED = 17` is a floor.
  - `apps/web-platform/test/infra/inngest-step-524-alert.test.sh`: pins the three explorations inside
    its `# ── #8611 / ADR-243:` section only (`names.count(...) == 1`, floor 3), so a new alert under
    its own section header does not touch it (Kieran review).
  - `plugins/soleur/lib/heartbeat-manifest.ts` and its reprovision-parity test.
  - `apps/web-platform/infra/suite-shard-legs.tsv`: registers infra `*.test.sh` suites
    (`luks-monitor.test.sh`, `workspaces-luks-host-token-refresh.test.sh` are listed).
- `knowledge-base/engineering/operations/runbooks/workspaces-luks-cutover-6604.md`: the
  "Margin, because it is thinner than it looks. Two independent pushers …" paragraph, and the
  rotation section ("Avoid merging between 04:30 and 05:00 UTC"; "The host timer then fails with
  `doppler_unreachable`").
- `knowledge-base/engineering/architecture/decisions/ADR-119-luks-at-rest-for-the-live-workspaces-volume.md`:
  §(e) ("the live delivery path for web-1 is the cutover job's SSH channel") and the 2026-09-24
  addenda (token-line owner; "the SOLEUR_SENTRY_DSN line stays cloud-init's").
- `scripts/followthroughs/workspaces-luks-soak-6604.sh`: counts `OK:` rows under the tag without
  telling the two pushers apart (see Open Code-Review Overlap / acknowledged below).

### Institutional learnings applied

- `2026-07-18-shared-delivery-substrate-and-reused-heartbeat-url-masking.md`: OR-semantics masking
  on a multi-feeder heartbeat. The new liveness signal must single out the host feeder.
- `2026-07-16-the-fix-for-an-inert-monitor-shipped-a-probe-that-could-never-fire.md`: a green
  static arming guard is not a measured beat. Closure requires an observed row.
- `2026-07-08-inngest-cutover-authoring-review-and-observability-allowlist.md`: "rides the shipper"
  must be verified. Verified above: `luks-monitor` is allowlisted, `systemd` is not.
- `2026-08-13-making-a-red-gate-green-arms-everything-it-was-silently-gating.md`: enumerate what the
  unreached tail was also gating. Done in points 2-3: units, emit helper, token line, DSN line, and
  `disarm_dead_man`.
- `2026-04-03-terraform-data-remote-exec-drift-encrypted-ssh-key.md`: an SSH-provisioned
  `terraform_data` must ride the CI SSH apply, not sit as local-only drift.

### Premise Validation

- #8706 is OPEN. Cited #8632 CLOSED, #6808 CLOSED, #6814 OPEN (whether the daily unit should assert
  readyz; its premise assumed the unit runs; acknowledged, not folded), PR #8703 MERGED, PR #8724
  MERGED. No open PR or worktree exists for #8706.
- The issue's "Evidence source that will land with #8703" already landed: run 36005279546.
- The parent evidence "the EnvironmentFile absence was at most one cause" holds in a stronger form:
  it and the dark timer are the same cause (point 3).
- ADR corpus: a Terraform SSH installer is not in any ADR's rejected alternatives. ADR-119 §(e)
  chose the cutover channel because the bake cannot reach web-1 and did not consider a Terraform
  installer. ADR-218 prescribes Terraform-managed logs alerts.

### Property List (Phase 0.6b)

- P1: web-1 runs the at-rest probe daily from its own systemd timer.
- P2: the host unit's delivery is owned by a path that re-applies without a cutover (ADR-119
  2026-09-24 addendum: Terraform-owned).
- P3: a host-timer run can be told apart off-box from a verify-job run.
- P4: the host timer going dark pages with nobody looking (a positive signal, not the absence of a
  drift event).
- P5: a failing host run reaches Sentry with its discriminating fields.
- P6: #8706 closes on observed evidence (3 consecutive nights), not on merge.
- P7: the runbook's pusher and margin reasoning matches reality.

### Cut List

- **An `invoker=host-timer` marker in `luks-monitor.sh`** → P3 → already bought by
  `_SYSTEMD_UNIT=luks-monitor.service`, which the unit's stdout copy of every line carries (measured
  100% on stdout rows above). Cut. `luks-monitor.sh` stays untouched; it also carries regex-derived
  parity gates an edit would have to satisfy.
- **A `_TRANSPORT = 'stdout'` conjunct in the alert predicate** (first draft) → P3 → the unit
  conjunct alone already excludes SSH runs (their rows carry `session-N.scope` or no unit), and
  requiring one specific copy would make the alert depend on one of the two rows each line produces.
  Cut (terraform-architect review): either copy counts, and `lower_than 1` does not care about
  double counting.
- **`INVOCATION_ID`-gated stdout logging in `log()`** (a CTO suggestion based on reading `log()` as
  logger-only) → P3 → `log()` already echoes to stdout unconditionally. Cut.
- **A second Better Stack heartbeat for the host unit** → P4 → the ADR-218 logs alert buys it with no
  new heartbeat object, Doppler secret or unit environment variable. Kept as the rejected
  alternative.
- **A host-timer assertion inside `workspaces-luks-verify.yml`** → P4 → the same logs alert; the
  verify classifier and its (M)/(N) parity gates would need a new class for no extra property.
- **Removing the cutover's install tail** → buys no property; it is a harmless second installer of
  the same repo files.

## Research Reconciliation — Spec vs. Codebase

| Claim (issue / runbook / ADR / parent brief) | Reality (measured) | Plan response |
|---|---|---|
| #8706: "possible causes: timer not enabled or active, unit fails before exec, binary missing" | None of those: the unit files and binary were never delivered (`UnitFileState=` empty, `0 timers listed`, run 36005279546) | Deliver all four artifacts through a Terraform installer (Phase 1) |
| #8706: "evidence source that will land with #8703" | Already landed on 2026-09-24 13:41 UTC | Cite it; the new installer prints a richer state line every fire |
| Parent brief: "the EnvironmentFile absence was at most one cause" | Same cause as the dark timer: one unreached cutover tail | One installer fixes units, emit helper and the DSN line together |
| Runbook: "Two independent pushers feed this heartbeat" | One pusher (the verify job) since the 2026-07-23 cutover | Rewrite the paragraph (Phase 4) |
| ADR-119 §(e): "the live delivery path for web-1 is the cutover job's SSH channel" | That channel never reached its install tail on any real run | ADR-119 addendum 2026-09-27: Terraform owns delivery of the monitor units and the DSN line (Phase 4) |
| ADR-119 2026-09-24 addendum: "the SOLEUR_SENTRY_DSN line stays cloud-init's" | Cloud-init never wrote it on web-1 | The new installer owns the DSN line on web-1; cloud-init keeps it for fresh hosts |
| `heartbeat-manifest.ts`: feeder armed by `workspaces-cutover.sh` | That arming line never executed | Evidence moves to `workspaces-luks.tf`; the runtime proof is the new logs alert |
| `luks-monitor-token-refresh.sh`: "#8706 tracks the missing DSN line" | Confirmed, still missing | Folded in (Phase 1) |
| Issue closure: "an `OK:` row whose `_SYSTEMD_UNIT` is `luks-monitor.service`" | `_SYSTEMD_UNIT` is dropped on ~50% of `logger` rows, never on stdout rows | Predicate keys on `_SYSTEMD_UNIT = 'luks-monitor.service'`; the unit's stdout copy guarantees every host run yields at least one such row |
| Repo-research agent: add 4 to `FLOOR_DESTS` in web-host-provisioner-parity | §1/§2 scan `server.tf` only; the installer lives in `workspaces-luks.tf` | Only G2's `FLOOR_BLOCKS` moves (20 → 21) |

## Problem Statement

ADR-119 promises a daily host-side escrow and header re-test of the LUKS volume that holds every
user's workspace. That re-test has never run on web-1. The at-rest claim is still supported, by the
04:41 UTC `workspaces-luks-verify.yml` job, but:

- the probe the runbook and ADR describe as the steady-state check does not exist on the host;
- the shared heartbeat and the static arming guard both read green over its absence;
- a failing host run would have been silent in Sentry (no DSN line on web-1);
- any check of the form "no drift event after the next host timer run" passes trivially.

## Proposed Solution

Four phases, one PR. Phases 1-3 are code; Phase 4 is the knowledge-base record.

### Phase 1: Terraform-owned delivery (`terraform_data.luks_monitor_install`)

New resource in `apps/web-platform/infra/workspaces-luks.tf`, directly after
`terraform_data.luks_monitor_token_install`. It lives in this file, not `server.tf`, for the same
reason its sibling does: the units are web-1-only by design (ADR-119 §(d)). The `server.tf`-scoped
fresh-boot parity sweep (§1/§2 of `web-host-provisioner-parity.test.sh`) asserts every SSH-written
destination has a fresh-boot writer, and a fresh web host must NOT get these units. The ADR-119
addendum records this so the placement is a decision, not an evasion.

Shape (copied from `git_data_probe_install` and the sibling token installer). **[Updated 2026-09-27
after plan review: freeze guard, staging directory and the DSN helper script cut; see Plan Review
Revisions.]**

1. `triggers_replace = sha256(join(",", [file(luks-monitor.sh), file(workspaces-luks-emit.sh),
   file(luks-monitor.service), file(luks-monitor.timer), nonsensitive(sha256(var.sentry_dsn))]))`.
   The trigger's file operands equal the file-provisioner source set exactly, plus the DSN hash.
   Unlike the sibling token installer ("No file() hash"), file hashes ARE the trigger here,
   deliberately: a probe edit must re-deliver the probe. The resource comment states the cost: any
   edit to the shared `workspaces-luks-emit.sh` re-installs on web-1 and starts one probe run.
2. `depends_on = [terraform_data.luks_monitor_token_install, terraform_data.journald_persistent]`.
   Serializes the two writers of `/etc/default/luks-monitor`, and reloads Vector before the first
   run (the `git_data_probe_install` "probe-first ordering" note). `depends_on` orders; only
   `triggers_replace` or a taint replaces a `terraform_data`, so it never cascades a re-fire.
3. `lifecycle { precondition }`:
   `nonsensitive(var.sentry_dsn != "" && can(regex("^https://[A-Za-z0-9]+@[A-Za-z0-9.-]+/[0-9]+$", var.sentry_dsn)))`,
   the exact character-class regex `inngest-host.tf` already applies to the same variable.
   `local.sentry_dsn_shape_ok` (`server.tf`) is NOT enough: it passes an empty value, and its
   `[^@/]+` classes admit `$(…)`, backticks, spaces and `'` (Kieran review). The strict class
   matters twice: the value is interpolated into a single-quoted shell `printf`, and
   `workspaces-luks-emit.sh` SOURCES `/etc/default/luks-monitor` as root. This is the only DSN shape
   check; nothing on the host repeats it.
4. `connection {}`: identical to the sibling (web-1 address, root, `var.ci_ssh_private_key`,
   `host_key = local.web_1_ssh_host_key`).
5. Provisioners, in this order (the arm-before-kick order is part of the Guard 2 contract):
   1. **File provisioners, straight into place** (as `git_data_probe_install` does):
      `luks-monitor.sh` → `/usr/local/bin/luks-monitor`, `workspaces-luks-emit.sh` →
      `/usr/local/bin/workspaces-luks-emit.sh`, `luks-monitor.service` and `luks-monitor.timer` →
      `/etc/systemd/system/`. A failure part-way taints the resource and the next apply re-delivers
      all four from the top.
   2. **DSN line** (remote-exec, inline, output suppressed because `var.sentry_dsn` is `sensitive`):

      ```sh
      set -e; umask 077; f=/etc/default/luks-monitor
      [ ! -L "$f" ]
      { grep -v '^SOLEUR_SENTRY_DSN=' "$f" 2>/dev/null || true; printf 'SOLEUR_SENTRY_DSN=%s\n' '<dsn>'; } > "$f.tmp"
      chown root:root "$f.tmp"; mv "$f.tmp" "$f"
      [ "$(grep -c '^SOLEUR_SENTRY_DSN=' "$f")" = 1 ]
      ```

      This is the cutover's own form for the token line. `grep -v` keeps every other line, in
      order, by construction, so the `DOPPLER_TOKEN=` line the token installer owns survives; the
      token helper returns the favour (`[ "$before" = "$after" ] || restore envfile_other_lines_changed`).
      The file is created 0600 root if absent (`umask 077`). A failure reddens the apply with no
      reason in the log, because Terraform suppresses the whole provisioner's output; the failure
      modes are a symlinked file or a full disk, both visible from the state print that follows on
      the next attempt.
   3. **Arm** (remote-exec, `set -e`): `chmod 0755` both binaries; `daemon-reload`; enable the
      timer with `--now`; assert `is-enabled` and `is-active` (a delivery fault reddens the apply;
      probe health never can); then one `start --no-block luks-monitor.service`. The kick gives a
      same-day host-unit row instead of waiting for midnight, and `--no-block` means the apply never
      waits on or fails with the probe (the ADR-119 2026-09-24 rule: probe faults must not redden a
      merge).
   4. **State print** (remote-exec, no secret references so output is not suppressed):
      `list-timers luks-monitor.timer`; `show -p LoadState,UnitFileState,ActiveState,NextElapseUSecRealtime,LastTriggerUSec luks-monitor.timer`;
      `show -p ActiveState,Result workspaces-luks-deadman.timer workspaces-luks-deadman.service`.
      `NextElapseUSecRealtime` prints in host-local time with its zone, which is the measurement that
      the 00:00-00:30 window is UTC. Never `show -p Environment` (it would print the DSN unsuppressed).
6. `.github/workflows/apply-web-platform-infra.yml`: add
   `-target=terraform_data.luks_monitor_install` to the per-merge SSH apply step (the one that
   targets `terraform_data.web_1_host_key_probe`), after the token installer's line.
   `terraform-target-parity.test.ts` Guard 1 requires the SSH stage, not the MAIN plan.

No cutover-freeze guard: the cutover is complete, and a future re-cut already has to avoid merging
infra changes during its freeze window (the dead-man units stay visible in the state print).

`workspaces-cutover.sh`'s install tail stays as it is: it installs the same repo files, so it is a
harmless second installer for a future re-cut.

### Phase 2: positive liveness check (Better Stack logs alert, ADR-218)

In `apps/web-platform/infra/betterstack-logs-alerts.tf`, following the file's own "TO ADD ANOTHER
LOGS ALERT (five steps)" recipe and the `claude_cost_capture_dark` precedent:

1. `locals { luks_monitor_host_timer_sql = <<-SQL … SQL }`:

   ```sql
   SELECT toDateTime({{end_time}}) AS time, count(*) AS value
   FROM {{source}}
   WHERE dt BETWEEN {{start_time}} AND {{end_time}}
     AND JSONExtractString(raw, 'SYSLOG_IDENTIFIER') = 'luks-monitor'
     AND JSONExtractString(raw, '_SYSTEMD_UNIT') = 'luks-monitor.service'
     AND JSONExtractString(raw, 'message') LIKE '%OK: /mnt/data is LUKS-backed%'
   ```

   Every conjunct is load-bearing: the unit conjunct excludes the verify job's rows (the masking
   defect), the message needle excludes `FAIL (…)` and helper rows, the identifier scopes the scan.
   Each host run yields two rows per line (the `logger` copy, unit-attributed about half the time,
   and the stdout copy, always attributed); `lower_than 1` counts either.
2. `logtail_exploration.luks_monitor_host_timer_dark` (name `soleur-luks-monitor-host-timer-dark-prd`),
   `variable "source"` = `local.vector_prd_source_id`, single-line `sql_query` like the siblings.
3. `logtail_exploration_alert.luks_monitor_host_timer_dark`: `alert_type = "threshold"`,
   `operator = "lower_than"`, `value = 1`, `check_period = 3600`, `query_period = 97200`,
   `confirmation_period = 0`, `recovery_period = 3600`, `on_missing_data = "treat_as_zero"`,
   `paused = false`, email only, the sibling `escalation_target` ternary, `incident_cause` with the
   runbook URL. Why a 27 h window: `OnCalendar=daily` with `RandomizedDelaySec=1800` can space two
   runs up to 24h30m (88200 s) apart, so a strict 24 h window would legitimately read empty for up to
   30 minutes a day. The margin comes from the window (a mechanism this file already uses) rather
   than from `confirmation_period`, which no resource in the repo has ever set non-zero, so its
   server-side behaviour is unmeasured. The pinned provider (`logtail` 11.2.0, lock file) documents
   `query_period` as "The query evaluation window in seconds." with no enum (terraform-architect
   read the cached provider). Whether the Better Stack API accepts 97200 is verified before merge
   (Sharp Edges); the fallback if it does not is `query_period = 86400` with
   `confirmation_period = 7200`. Pages about 27 h after the last good host run.
4. The three blocks go under their own `# ── #8706:` section header in the file (the #8611 section's
   test pins its own names only). Two `-target` lines in the MAIN plan allowlist of
   `apply-web-platform-infra.yml`, beside the
   `claude_cost_capture_dark` pair.
5. A "Standing alarms over this source" row in `runbooks/betterstack-log-query.md` and a decode
   entry in the cutover runbook (Phase 4).

The twice-daily `reconcile-live-heartbeats.ts` `logs_alert` arm discovers every
`logtail_exploration_alert` from the root, so a vendor-side pause or deletion of this alert is
already detected with no new code.

**Pre-merge live probe (required by the recipe; SQL is not validated by `terraform validate`).**
Run the predicate through `scripts/betterstack-query.sh` in raw-SQL mode over the last 7 days with
`{{source}}` expanded to the hot+archive union:

- as written: `0` (no host-unit row exists yet; this is the dark state the alert must page on);
- positive control A, `'luks-monitor'`/`'luks-monitor.service'` swapped for
  `'inngest-heartbeat'`/`'inngest-heartbeat.service'` and the needle dropped: non-zero (the
  identifier+unit shape matches real rows from a unit that, like this one, writes through both
  `logger` and stdout);
- positive control B, the unit conjunct dropped: non-zero (the verify job's `OK:` rows exist, which
  proves the unit conjunct is what excludes them);
- after merge, the same query as written returns non-zero within minutes of the SSH apply (the
  Phase 1 kick), which is the first measured host-unit row.

**Measured at plan time (2026-09-27, 7-day window, `count()` over the hot+archive union):** as
written `{"n":0}`; control A (`_SYSTEMD_UNIT='inngest-heartbeat.service'`, the literal value, so
the unit name is measured, not assumed) `{"n":39228}`; control B `{"n":9}`. The work phase re-runs all three
and records them in the PR body.

### Phase 3: closure follow-through (`scripts/followthroughs/luks-monitor-host-timer-8706.sh`)

Closes #8706 on evidence, per the issue's re-evaluation trigger. Read-only; runs under the sweeper's
`env -i` with `secrets=BETTERSTACK_QUERY_HOST,BETTERSTACK_QUERY_USERNAME,BETTERSTACK_QUERY_PASSWORD`
(already wired in `scheduled-followthrough-sweeper.yml`).

- Queries the Phase 2 predicate plus `toHour(dt, 'UTC') = 0` over the last 5 days (hot + archive union),
  groups by UTC date, prints one `HOST_TIMER_OK day=<YYYY-MM-DD> unit=luks-monitor.service` line per
  qualifying day. The `00` hour excludes the Phase 1 kick row, so only timer-fired runs count; a
  `Persistent=true` catch-up run after a reboot also falls outside it and does not count.
- Positive control first: at least one `SYSLOG_IDENTIFIER=luks-monitor` row of any kind in the
  window (the verify job writes one daily). Zero means the channel is dark, reported as TRANSIENT
  (exit 2), never as a FAIL of the timer and never as a PASS.
- `PASS` (exit 0) when 3 consecutive UTC dates qualify; `FAIL` (exit 1) otherwise; exit 2 on any
  query or auth failure. Refuses to run under xtrace, like its siblings.
- Tracker enrollment on #8706 at ship time: the `<!-- soleur:followthrough script=… earliest=<merge+3d> secrets=… -->`
  directive plus the `follow-through` label. The PR body says `Ref #8706`, never `Closes`.

### Phase 4: record the decision and correct the docs

- **ADR-119 addendum (2026-09-27): the monitor units and the DSN line have a Terraform owner.**
  States the root cause (no real cutover reached its install tail), supersedes §(e)'s delivery
  claim for the monitor units, `workspaces-luks-emit.sh`, and the `SOLEUR_SENTRY_DSN=` line on web-1
  (the 2026-09-24 addendum's "DSN line stays cloud-init's" holds for fresh hosts only), records why
  the installer sits in `workspaces-luks.tf`, and records that the emit helper's Doppler fallback
  (`--config prd`) is unreachable with the scoped token, which is why the baked line is the only DSN
  path on web-1. Notes that the static arming guard was satisfied by never-executed code and names
  the logs alert as the runtime proof.
- **`plugins/soleur/lib/heartbeat-manifest.ts`**: `workspaces_luks.feeder.evidence` becomes
  `{ file: "apps/web-platform/infra/workspaces-luks.tf", pattern: "<the exact arming string in the new resource>" }`;
  rewrite the entry's comment and `exempt_reason` (delivered by `terraform_data.luks_monitor_install`,
  not the cutover channel; second pusher is the verify job; runtime proof is
  `logtail_exploration_alert.luks_monitor_host_timer_dark`).
- **Runbook `workspaces-luks-cutover-6604.md`**:
  - Rewrite the "Margin, because it is thinner than it looks. Two independent pushers …" paragraph
    in a few sentences, linking the ADR-119 2026-09-27 addendum for the evidence instead of
    repeating run IDs: until this change the heartbeat had ONE pusher (the verify job) because the
    host unit was never installed; now there are two; the shared heartbeat cannot tell them apart,
    so the only host-specific signal is the new logs alert; the 24h30m margin arithmetic stays.
  - Rotation step 2: also avoid merging between 00:00 and 00:35 UTC (a host run reading the token
    file while the old token is being revoked now emits `doppler_unreachable`).
  - Failure signals: add the logs alert (what it means, how to read it back without a dashboard via
    `betterstack-query.sh`, and that a Vector outage also trips it).
  - Replace the "#8706 tracks …"-style future tense on the DSN line with the delivered state.
- **`runbooks/betterstack-log-query.md`**: "Standing alarms over this source" row for the new alert.
- **`luks-monitor-token-refresh.sh`**: comment only, the "#8706 tracks the missing DSN line" pointer
  becomes "delivered by `terraform_data.luks_monitor_install`". Its installer's only trigger is the
  token hash, so this edit does not re-fire it.

## Files to Edit

- `apps/web-platform/infra/workspaces-luks.tf`: new `terraform_data.luks_monitor_install`.
- `apps/web-platform/infra/betterstack-logs-alerts.tf`: SQL local, exploration, alert.
- `.github/workflows/apply-web-platform-infra.yml`: one SSH-apply target, two MAIN-plan targets.
- `apps/web-platform/infra/web-host-provisioner-parity.test.sh`: G2 `FLOOR_BLOCKS` 20 → 21 with a
  `#8706` comment (measure the new sweep count; do not assume).
- `plugins/soleur/test/terraform-target-parity.test.ts`: raise `MIN_SSH_PROVISIONED` 17 → 18 with a
  `#8706` comment (floor; measure first).
- `plugins/soleur/lib/heartbeat-manifest.ts`: `workspaces_luks` evidence, comment, `exempt_reason`.
- `apps/web-platform/infra/luks-monitor-token-refresh.sh`: one comment line.
- `apps/web-platform/infra/suite-shard-legs.tsv`: register the new suite.
- `plugins/soleur/test/preflight-discoverability-test.test.ts`: `BASELINE_DECLARED_PROBES` 31 → 32
  with the PLACEMENT/TRUTH/NO-SUBSTITUTE comment its failure text asks for (this plan's
  `discoverability_test` declares `credentials_required`, which moves the repo-global count the
  moment the plan is committed).
- `knowledge-base/engineering/operations/runbooks/workspaces-luks-cutover-6604.md`.
- `knowledge-base/engineering/operations/runbooks/betterstack-log-query.md`.
- `knowledge-base/engineering/architecture/decisions/ADR-119-luks-at-rest-for-the-live-workspaces-volume.md`.

## Files to Create

- `apps/web-platform/infra/luks-monitor-install.test.sh`: Guard 1's static half (alert predicate),
  Guard 2 (installer) and Guard 3 (the inline DSN writer), each with its mutation rows and an
  anti-vacuity floor; registered in `suite-shard-legs.tsv`. About 18 rows in total.
- `scripts/followthroughs/luks-monitor-host-timer-8706.sh`: Phase 3.

No changes to `luks-monitor.sh`, `luks-monitor.service`, `luks-monitor.timer`,
`workspaces-luks-emit.sh`, `workspaces-cutover.sh`, `vector.toml` or `cloud-init.yml`.

## Open Code-Review Overlap

None. 87 open `code-review` issues checked against every path above; no body references them.

Acknowledged, not folded:

- #6814 (should the DAILY unit assert readyz + inventory): its premise assumed the unit runs. After
  this change the premise holds for the first time; the decision itself is out of scope.
- `scripts/followthroughs/workspaces-luks-soak-6604.sh` counts `OK:` rows from either pusher. Both
  run the same five at-rest asserts, so as a wipe-authorization gate it is sound; its FAIL wording
  ("the daily probe is DEAD, never armed") was true of the host unit all along and is left as is.

## Infrastructure (IaC)

Phase 2.8 detection fired (systemd unit delivery). Everything routes through Terraform; no step in
this plan is performed by hand. `soleur:engineering:infra:terraform-architect` reviewed the design
(see Domain Review).

### Terraform changes

- Root: `apps/web-platform/infra/` (existing, R2 backend). Files: `workspaces-luks.tf`
  (`terraform_data.luks_monitor_install`), `betterstack-logs-alerts.tf`
  (`logtail_exploration.luks_monitor_host_timer_dark`, `logtail_exploration_alert.luks_monitor_host_timer_dark`).
- Providers: no new provider. `terraform_data` is built in; `logtail` is already pinned in the root.
- Sensitive inputs: `TF_VAR_sentry_dsn` (Doppler `prd_terraform` `SENTRY_DSN`, already injected by
  `doppler run --name-transformer tf-var` in both apply steps); `var.ci_ssh_private_key` (existing).

### Apply path

(b) Idempotent in-place delivery to the already-running host through a `terraform_data` SSH
provisioner in the per-merge CI apply (no reprovision; web-1 cannot be rebuilt). Blast radius: one
`daemon-reload` on web-1, one timer enable, one read-only probe run. No downtime; the probe holds
`/mnt/data` open briefly (`RequiresMountsFor`), which only matters during a cutover freeze (none is
planned; the cutover is complete). The logs alert rides the MAIN plan apply (Better Stack API only),
which runs a few minutes BEFORE the SSH step in the same job (see Sharp Edges on the first
evaluation).

### Distinctness / drift safeguards

- `dev != prd`: no dev counterpart exists; the host and the Logs source are prd-only.
- No `lifecycle.ignore_changes` on the installer (a guard asserts its absence, same as the
  `web-probes-token-rotation` G1 rule for installers).
- State: the DSN hash, not the DSN, is in `triggers_replace`; the DSN appears only in the
  suppressed provisioner command, and Terraform state stores provisioner commands for neither.
- Taint semantics: any failed provisioner (freeze refusal, SSH drop, failed enable assert) taints
  the resource, and the next per-merge apply re-fires it from the top; every step is idempotent.

### Vendor-tier reality check

Better Stack free tier: logs alerts exist on it today (six in `betterstack-logs-alerts.tf`), email
only; paid tier escalates via `betteruptime_policy.uptime[0]` through the sibling ternary. No new
heartbeat object is created, so the heartbeat/monitor object pool is unchanged.

## Architecture Decision (ADR/C4)

### ADR

Amend ADR-119 with "Addendum (2026-09-27): the monitor units and the DSN line have a Terraform owner
(#8706)" (content in Phase 4). An amendment, not a new ADR: it corrects §(e)'s delivery claim and the
2026-09-24 addendum's DSN-line ownership, both inside ADR-119's decision. ADR-119 stays `adopting`.

### C4 views

No C4 change. All three files (`model.c4`, `views.c4`, `spec.c4`) were read for the elements this
change touches:

- External actors: the founder/operator receiving Better Stack email, already modeled
  (`betterstack -> founder`).
- External systems: Better Stack (`betterstack`, Logs source 2457081 described) and Sentry, both
  modeled; no new vendor.
- Containers and stores: the web host (`hetzner`) and `workspacesVolume` (described as LUKS2 via
  `/dev/mapper/workspaces`), both modeled.
- Relationships: `hetzner -> betterstack` (journald via Vector) and `betterstack -> founder` exist;
  the CI-to-web-1 SSH path exists via the `tunnel -> hetzner` edge (`ssh. → ssh://10.0.1.10:22`),
  already used by every web-1 installer.
- No edge prose enumerates logs alerts or host timers, so no count moves;
  `plugins/soleur/test/c4-count-parity.test.sh` counts Sentry heartbeat workflows only. The work
  phase runs it plus `apps/web-platform/test/c4-code-syntax.test.ts` and `c4-render.test.ts` to
  confirm green.

### Sequencing

None; the addendum describes the state this PR delivers.

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing on the request path. No user-facing code,
  route or container changes. The realistic broken states are operator-facing: a host probe that
  stays dark (the logs alert emails the operator within ~27 h), a false `workspaces-luks-drift`
  email if the token line is damaged (`doppler_unreachable`), a red per-merge SSH apply step if
  delivery fails, or one alert email at merge before the first host row lands. None of them touches `/mnt/data`'s mount, the container,
  or a user's workspace; the probe is read-only.
- **If this leaks, the user's data is exposed via:** no new vector. The probe already reads
  `WORKSPACES_LUKS_KEY` through the pinned scoped-config form and refuses xtrace; this change adds
  the semi-public Sentry DSN to a 0600 root file and a count-only query over `luks-monitor` rows,
  whose `OK:` line carries a device path and no user identifier. What the change protects is the
  detection of an at-rest regression across every user's workspace at once.
- **Brand-survival threshold:** `aggregate pattern`. A dark at-rest re-test degrades detection for
  all users' encrypted workspaces collectively; it is not a single-user breach vector.

## Observability

```yaml
liveness_signal:
  what: >-
    Better Stack logs alert soleur-luks-monitor-host-timer-dark-prd: fires when the trailing 27 h
    holds zero luks-monitor "OK: /mnt/data is LUKS-backed" rows attributed to
    _SYSTEMD_UNIT=luks-monitor.service (the host unit's own runs; the verify job's rows can never
    match). Positive: a healthy night produces the row; silence pages.
  cadence: daily host run at 00:00-00:30 UTC; alert evaluated hourly (check_period 3600)
  alert_target: >-
    operator email (free tier, team "Your team"); betteruptime_policy.uptime on the paid tier via
    the sibling escalation_target ternary
  configured_in: >-
    apps/web-platform/infra/betterstack-logs-alerts.tf
    (logtail_exploration_alert.luks_monitor_host_timer_dark); delivery in
    apps/web-platform/infra/workspaces-luks.tf (terraform_data.luks_monitor_install)
error_reporting:
  destination: >-
    Sentry via workspaces-luks-emit.sh's direct envelope (feature=workspaces-luks,
    op=workspaces-luks-drift, nine discriminating fields), DSN from the SOLEUR_SENTRY_DSN line this
    change delivers to /etc/default/luks-monitor
  fail_loud: >-
    host: luks-monitor "FAIL (<reason>)" row in Better Stack + Sentry drift event; delivery: red
    per-merge SSH apply step (the arm step's is-enabled / is-active assert, or the precondition)
failure_modes:
  - mode: units never delivered or disarmed (the #8706 state)
    detection: >-
      logs alert (layer 3 data, Better Stack native alerting); installer state print in the
      apply run log (layer 6)
    alert_route: operator email ~27 h after the last host OK row
  - mode: installer failed or SSH step skipped (ssh_apply_skip)
    detection: red SSH apply step (layer 6); the #7539 skip notification; the logs alert as backstop
    alert_route: workflow failure email; operator email from the alert
  - mode: host run fails an at-rest assert (mount, mapper, escrow, header, doppler)
    detection: luks-monitor FAIL row (layer 3) + Sentry workspaces-luks-drift event (direct envelope)
    alert_route: sentry_issue_alert on op=workspaces-luks-drift; logs alert if it persists 27 h
  - mode: DSN line absent or malformed, so a host failure cannot reach Sentry
    detection: >-
      plan-time lifecycle precondition on an empty or malformed var.sentry_dsn (layer 6); the
      DSN provisioner's count assert reddens the SSH step (layer 6)
    alert_route: red apply (precondition); the logs alert still pages on the missing OK row
  - mode: Vector or the Logs source is down
    detection: logs alert fires (no rows at all); heartbeat-live-reconcile and existing Vector monitors
    alert_route: operator email; runbook decode row says "check the pipeline before the host"
  - mode: the alert itself paused or deleted vendor-side
    detection: reconcile-live-heartbeats.ts logs_alert arm (twice daily, discovers the new resource)
    alert_route: SOLEUR_HEARTBEAT_RECONCILE_MISMATCH issue
logs:
  where: >-
    journald on web-1 (SyslogIdentifier=luks-monitor, both logger and stdout copies) shipped by
    Vector host_scripts_journald to Better Stack Logs source 2457081; apply run logs in GitHub Actions
  retention: >-
    Better Stack hot window plus s3 archive per the source's plan (July 2026 rows already aged out
    by 2026-09-27); GitHub Actions run logs 90 days
discoverability_test:
  command: bash scripts/followthroughs/luks-monitor-host-timer-8706.sh
  expected_output: "HOST_TIMER_OK"
  credentials_required: >-
    BETTERSTACK_QUERY_HOST/USERNAME/PASSWORD (Doppler prd_terraform, read-only ClickHouse
    connection) — journald rows are readable only through that connection; no unauthenticated
    endpoint exposes whether a host-unit OK row landed
```

## Encryption Posture

```yaml
# Detection fired on the .tf edits. This change adds NO persistent store and NO new
# cross-component connection: it delivers a probe of an existing store over existing channels.
at_rest:
  - store: hcloud_volume.workspaces_luks
    mechanism: luks
    evidence: >-
      unchanged; resolved by the ledger row's device_binding in scripts/encryption-posture-ledger.json
      (workspaces-cutover.sh luksFormat/luksOpen, random_password.workspaces_luks,
      doppler_secret.workspaces_luks_key)
    defends_against: a seized or RMA'd disk, a raw Hetzner volume snapshot
    does_not_defend: >-
      an unlocked running host, a root compromise of web-1, a leaked prd_workspaces_luks token
      paired with device access, or application-layer access to /workspaces
    disclosed_as: docs/legal/privacy-policy.md (the "Workspace storage encryption" bullet)
    live_verification: >-
      available — this change restores the HOST half (daily luks-monitor.service); the verify job
      half was already live
in_transit:
  - connection: GitHub Actions runner -> web-1 (terraform_data SSH provisioner)
    enforced_at: >-
      apps/web-platform/infra/workspaces-luks.tf connection { host_key = local.web_1_ssh_host_key },
      carried over the existing Cloudflare Tunnel ssh bridge
    tls: SSH transport inside the Cloudflare Tunnel (TLS 1.3 to the edge)
    cert_verification: "on"
    does_not_defend: a compromised CI runner or a stolen ci_ssh private key
    disclosed_as: not-publicly-claimed
  - connection: web-1 journald (Vector) -> Better Stack Logs source 2457081
    enforced_at: apps/web-platform/infra/vector.toml (existing https sink; unchanged)
    tls: HTTPS, TLS 1.2+
    cert_verification: "on"
    does_not_defend: Better Stack-side access to the shipped rows
    disclosed_as: not-publicly-claimed
```

## Guard Contract

### Guard 1 — host-timer liveness alert (`logtail_exploration_alert.luks_monitor_host_timer_dark`)

**Property.** The alert is quiet if and only if at least one `luks-monitor` `OK:` row produced by
`luks-monitor.service` itself reached Better Stack within the trailing 27 h.

**Assembly.** Emitter to detector, one chain with one chokepoint per hop: `luks-monitor.sh`'s single
`OK:` log call → `log()` (both `logger` and stdout) → the unit's `SyslogIdentifier=luks-monitor` →
`vector.toml` `host_scripts_journald` allowlist entry `"luks-monitor"` → source 2457081 →
`local.luks_monitor_host_timer_sql` (the only predicate) → `logtail_exploration` (source variable)
→ `logtail_exploration_alert` (operator, value, window, `on_missing_data`) → the two MAIN-plan
`-target` lines. The static half is asserted in `luks-monitor-install.test.sh`; the live half by the
pre-merge probe and the post-merge first row. Every `logtail_exploration` whose SQL names
`luks-monitor` is in the assembly, not only the first.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Drop the `_SYSTEMD_UNIT = 'luks-monitor.service'` conjunct (verify rows now satisfy it: the original masking) | RED |
| 2 | `on_missing_data` changed from `treat_as_zero` (silence can no longer fire) | RED |
| 4 | `query_period` below 88200 with `confirmation_period` 0 (a normal 24h30m gap would page); the fallback shape needs `confirmation_period` of at least 3600 | RED |
| 5 | The needle no longer a substring of `luks-monitor.sh`'s `OK:` log string (reword either side) | RED |
| 7 | A second `logtail_exploration` naming `luks-monitor` added after a compliant first, lacking the unit conjunct | RED |
| H1 | Harness: the SQL extractor returns an empty body (suite checks 0 predicates) | RED via the anti-vacuity floor |
| H2 | Must-PASS: conjuncts reordered and whitespace reflowed, same predicate | PASS |

**Anchor.** No stored value is compared; the needle is cross-checked against the emitter file in the
same tree, so a single diff that rewords both stays consistent and correct, and the post-merge
first-row check is the outside-the-commit proof. Rows cut at plan review because another suite
already reds on them: the `vector.toml` allowlist entry (`vector-pii-scrub.test.sh` derives the tag
set from `LOG_TAG`), the MAIN-plan targets (`terraform-target-parity.test.ts`), and literal re-reads
of `operator`/`value`.

### Guard 2 — installer (`terraform_data.luks_monitor_install`)

**Property.** Every file the installer delivers is in its trigger, the resource is targeted by the
per-merge SSH apply, and the probe is kicked only after arming has been asserted.

**Assembly.** The resource block in `workspaces-luks.tf` (trigger operand set, `file` provisioner
source set, provisioner order, `connection`, precondition, absence of `lifecycle.ignore_changes`);
the SSH-apply step's `-target` set in `apply-web-platform-infra.yml` (the step containing
`terraform_data.web_1_host_key_probe`); the heartbeat manifest's evidence pattern, which must match
this resource's arming line. Chokepoint: set equality between `file()` operands in
`triggers_replace` and `source` values of `file` provisioners.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Remove `file(luks-monitor.timer)` from `triggers_replace` | RED |
| 2 | Add a fifth `file` provisioner after the compliant four without hashing it | RED |
| 4 | REORDER: move the `start --no-block` kick above the enable/assert lines | RED |
| 7 | Move the arming line into a comment (comment-stripped view) | RED |
| 8 | A `file` destination that differs from the cutover tail's `install` destination for the same source (e.g. `/usr/local/bin/luks-monitor.sh`), so the two installers drift | RED |
| H1 | Harness: the HCL block extractor finds no `luks_monitor_install` block | RED ("0 checked" fails the floor) |
| H2 | Must-PASS: trigger operands reordered; an extra harmless `echo` line in the state print | PASS |

**Anchor.** `FLOOR_BLOCKS` in `web-host-provisioner-parity.test.sh` is a count; this suite asserts
the resource by NAME, so a swap that keeps the count still reds.

### Guard 3 — DSN line writer (inline provisioner in `luks_monitor_install`)

**Property.** Every write to `/etc/default/luks-monitor` from Terraform changes only its own key's
line: the DSN writer filters exactly `^SOLEUR_SENTRY_DSN=`, runs under `umask 077`, and asserts one
DSN line afterwards.

**Assembly.** Every remote-exec line in the Terraform root that names `/etc/default/luks-monitor`
(today: the token installer's helper call and this DSN writer). The census runs over all `.tf`
files, so a third writer is seen.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | The `grep -v` pattern widened (e.g. `'^SOLEUR_'` or `'^DOPPLER_TOKEN='`) so it drops the token line | RED |
| 2 | `grep -v` removed, so the DSN line is appended a second time | RED |
| 3 | `umask 077` removed from the writer | RED |
| 4 | A second remote-exec that writes `/etc/default/luks-monitor` added after the compliant one, without a key filter | RED |
| 5 | The precondition's regex widened to `[^@/]+` classes, so a DSN carrying `$(id)` or `'` would reach the sourced file | RED |
| H1 | Harness: the writer extractor finds zero lines naming the env file | RED via floor |
| H2 | Must-PASS: the same writer with its statements split across more `inline` entries | PASS |

## Plan Review Revisions

Panel (headless): `soleur:engineering:review:dhh-rails-reviewer`,
`soleur:engineering:review:kieran-rails-reviewer`, `soleur:engineering:review:code-simplicity-reviewer`,
and `soleur:engineering:cto` (devex lens). Threshold `aggregate pattern`, so the three-seat eng
panel plus the one relevant named seat.

Applied (mechanical):

- **Cut the cutover-freeze guard** (DHH, simplicity; Kieran P0 showed it could refuse forever: an
  elapsed transient timer keeps `ActiveState=active`, `SubState=elapsed` until reboot, so an old
  July dead-man would have blocked every install).
- **Cut the staging directory**; files go straight into place like `git_data_probe_install`.
- **Replaced the DSN helper script with a five-line inline writer**, and replaced the helper's
  behavioural guard with a static census of env-file writers (Guard 3).
- **Tightened the DSN precondition** to the character-class regex `inngest-host.tf` already uses;
  the value lands in a single-quoted `printf` and in a file root sources (Kieran P1).
- **Trimmed the guard matrices** from 29 rows to about 18, dropping rows another suite already reds
  on and literal re-reads (DHH, CTO).
- **Dropped `inngest-step-524-alert.test.sh` from Files to Edit**; the alert gets its own section
  header (Kieran P1).
- `toHour(dt, 'UTC')`; the merge-time alert email is documented with a resolve check; the
  follow-through AC names its positive-control line; Guard 2 pins install destinations to the
  cutover tail's (Kieran P2).
- Plain-language `incident_cause` and per-branch no-SSH runbook actions; the new no-merge window is
  scoped to token-rotating merges (CTO devex).
- Runbook rewrite links the ADR addendum instead of repeating run IDs (DHH).

Rejected, with reasons in Alternatives: the systemd drop-in for the DSN (fixes the unit only, not
the verify job's SSH path), closing on the first row instead of three nights (the issue's own
criterion; logged as a user-challenge in `decision-challenges.md`), and the split heartbeat.

## Alternative Approaches Considered

| Approach | Why not |
|---|---|
| Re-run the cutover to reach its install tail | A data-moving freeze to install four files; the channel failed on every real run |
| Bake into cloud-init / `soleur-host-bootstrap.sh` | Dead on web-1 (`ignore_changes = [user_data]`, cx33 unrebuildable); ADR-119 §(e) already ruled this out |
| Separate Better Stack heartbeat pushed only by the host unit (CTO's preferred alternative) | New heartbeat object (pool is small on the free tier), new Doppler secret, a unit env var and an edit to `luks-monitor.sh`; the logs alert buys the same property with none of those. Its one advantage, independence from Vector, is covered: a Vector outage makes the alert fire, which is loud, not silent |
| Host-timer assertion in `workspaces-luks-verify.yml` | Couples the at-rest verdict to a liveness question; needs a new classifier class across the (M)/(N) parity gates |
| `confirmation_period = 7200` with a 24 h window | Unmeasured server-side semantics in this repo; kept as the fallback if the API rejects 97200 |
| One resource owning the whole `/etc/default/luks-monitor`, or re-firing the DSN installer on the token hash (advisor consult) | Premise does not hold: the DSN line is missing because web-1 predates cloud-init's DSN write and #8724 created the file token-only, not because the token helper clobbered it. `luks-monitor-token-refresh.sh` already refuses to change any non-token line (`[ "$before" = "$after" ] \|\| restore envfile_other_lines_changed`), so a rotation keeps the DSN line; the DSN writer's `grep -v '^SOLEUR_SENTRY_DSN='` keeps the token line. Line ownership stays split, as ADR-119's 2026-09-24 addendum set it |
| A cutover-freeze guard, in the provisioner or the workflow (CTO at plan time; advisor consult) | Cut at plan review (DHH + simplicity): the cutover is complete, so it guards a state that no longer occurs, and a stale dead-man timer reading `active` would have turned every merge's SSH step red. The dead-man units stay in the state print |
| A shipped DSN helper script mirroring `luks-monitor-token-refresh.sh` (terraform-architect) | Cut at plan review (DHH + simplicity): the precondition already validates the shape, `grep -v` preserves other lines by construction, and a second 100-line helper would drift from the first. The cost accepted: a DSN-write failure reddens the apply without a reason in the log |
| A systemd drop-in carrying `Environment=SOLEUR_SENTRY_DSN=` instead of the env-file line (DHH) | Fixes the host unit only. `workspaces-luks-verify.yml` runs the probe over SSH, where `workspaces_luks_emit` reads the DSN from `/etc/default/luks-monitor` and nowhere else (its Doppler fallback cannot read `prd` with the scoped token), so today the verify job's drift events are Sentry-dark on web-1 too. The env-file line fixes both paths |
| A staging directory with `install -m` into place (terraform-architect) | Cut at plan review: `git_data_probe_install` uploads straight into place; a part-way failure taints and the next apply re-delivers all four files |
| Close #8706 on the first timer-fired row instead of three nights (DHH) | The three-night criterion is the issue's own re-evaluation trigger; kept |

## Sharp Edges

- **Better Stack's acceptance of `query_period = 97200` is unverified.** The provider accepts any
  integer; the API may not. The work phase checks Better Stack's alert API docs, and the MAIN apply
  of the merge is the first live write. If the API rejects it, switch to 86400 + `confirmation_period
  = 7200` (the Alternatives row) before merge rather than after a red apply.
- **The alert exists a few minutes before the first host row.** The MAIN apply (step "Terraform
  apply") creates it; the SSH step ("Terraform apply (SSH-provisioned resources, over the bridge)")
  runs later in the same job and kicks the first run. If Better Stack evaluates a new alert at
  creation, one email can fire before the kick row lands and resolve an hour later. The work phase
  checks the vendor's first-evaluation behaviour; if it evaluates at creation, the incident text and
  the PR body say so, so the email is expected rather than alarming.
- **`incident_cause` must be readable by a non-technical operator** (CTO devex review): what
  happened ("web-1's nightly encryption self-check has not reported in about 27 hours"), why it is
  not yet a data exposure (the volume is still encrypted; the 04:41 UTC verify job still checks it
  daily), and the first step (check whether any `luks-monitor` rows arrived at all, because total
  silence means the log pipeline, not the host), plus the runbook URL. The runbook decode names one
  no-SSH action per branch: re-run the apply workflow, or run `betterstack-query.sh`.
- **The cutover's post-canary abort leaves the dead-man armed.** `cleanup()` does not disarm once
  `CANARY_OK=1`, and both runs that passed the canary died before `disarm_dead_man`. What it did in
  July cannot be read back (retention). Out of scope here, but the ADR-119 addendum names it so a
  future re-cut does not inherit it silently; the installer's state print shows the dead-man units'
  current state on every fire.
- **Two writers of `/etc/default/luks-monitor`** (the token helper and the inline DSN writer) are
  serialized by `depends_on` within an apply; each keeps the other's line. The cutover tail is a
  third writer only during a re-cut. No `flock` is added: a lock only one writer takes protects
  nothing, and adding it to the token helper would not deploy until the next rotation.
- **File a tracking issue for the dead-man gap** at work time (`wg-when-an-audit-identifies-pre-existing`):
  `workspaces-cutover.sh`'s `cleanup()` does not disarm the dead-man after a post-canary abort.
  Planning did not file it (plan-only constraint).
- **The kick run is real.** It reads the passphrase via the scoped token and pushes the shared
  heartbeat. It fires only when a delivered file or the DSN changes.
- **The new suite must be registered** in `suite-shard-legs.tsv` or CI never runs it
  (`scripts/guard-vacuity-floor.test.sh` checks registration of the sibling suite the same way).
- **Merging this PR alone mutates production.** `apply-web-platform-infra.yml` fires on the
  `workspaces-luks.tf` / `betterstack-logs-alerts.tf` edits (push to `main`); its SSH step creates the
  installer on web-1 and its MAIN plan creates the alert. No other push workflow reaches these
  resources: `workspaces-luks-verify.yml` is schedule/dispatch only, and `apply-deploy-pipeline-fix.yml`'s
  `paths:` list names none of the edited files. The PR body's first line must say so.
- **Guard 2's static suite must lex HCL, not scan lines.** Reuse an existing extractor that handles
  strings, comments and heredocs (`web-host-provisioner-parity.test.sh`'s `strip_comments` +
  `hcl_blocks`, or the `block()`/`strip()` pair in `workspaces-luks-host-token-refresh.test.sh`)
  rather than a column-0 line scanner; a heredoc or `/* */` must not hide a provisioner.
- **Journald fields sit at the top level of `raw`.** The measurement above used
  `JSONExtractString(raw, '_SYSTEMD_UNIT')` and `JSONExtractString(raw, '_TRANSPORT')` directly and got
  populated values; the pino-under-`raw.message` nesting applies to container rows, not these.
- **Test fixtures are synthesized** (`cq-test-fixtures-synthesized-only`): any DSN or token in the
  suite is made up (`https://<hex>@o0.ingest.example/0` shape), never a real value.
- **The 00:00-00:35 UTC no-merge window applies to token-rotating merges only** (CTO devex review),
  like the existing 04:30-05:00 window; the runbook says so in the rotation section, not globally.
- **Run `npx markdownlint-cli2` on this plan and `tasks.md`** before committing.
- A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits the
  threshold fails `deepen-plan` Phase 4.6.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `terraform_data.luks_monitor_install` exists in `workspaces-luks.tf` with the trigger, order,
      precondition and connection described in Phase 1; `terraform validate` passes.
- [ ] `apply-web-platform-infra.yml` targets it in the SSH apply step, and targets both new
      `logtail_*` resources in the MAIN plan; `bun test plugins/soleur/test/terraform-target-parity.test.ts` passes.
- [ ] `bash apps/web-platform/infra/luks-monitor-install.test.sh` passes, including every mutation
      row of Guards 1-3 driving it red and every must-PASS row passing, and is listed in
      `suite-shard-legs.tsv`.
- [ ] `bash apps/web-platform/infra/web-host-provisioner-parity.test.sh`,
      `bash apps/web-platform/infra/workspaces-luks-host-token-refresh.test.sh`,
      `bash apps/web-platform/infra/luks-monitor.test.sh`,
      `bash apps/web-platform/test/infra/inngest-step-524-alert.test.sh` (unchanged, still green),
      `bash apps/web-platform/test/infra/vector-pii-scrub.test.sh` and
      `bun test plugins/soleur/test/heartbeat-reprovision-parity.test.ts plugins/soleur/test/heartbeat-live-reconcile.test.ts` pass.
- [ ] `python3 scripts/lint-encryption-posture.py` and `bash plugins/soleur/test/c4-count-parity.test.sh` pass.
- [ ] The pre-merge live probe (Phase 2) is recorded in the PR body: as written `0`, control A
      non-zero, control B non-zero, each with the command that produced it.
- [ ] `bash scripts/followthroughs/luks-monitor-host-timer-8706.sh` run locally with Doppler
      credentials exits 1, prints its positive-control line (verify-job rows present) and a `FAIL`
      line (no host-unit rows yet); an exit 2 means the channel is dark and is not this criterion.
- [ ] ADR-119 carries the 2026-09-27 addendum; the runbook paragraph, rotation window and failure
      signals are corrected; `betterstack-log-query.md` lists the alert; the heartbeat manifest
      evidence points at `workspaces-luks.tf`.
- [ ] PR body's first line states that merging installs the probe on web-1 and creates the Better
      Stack alert; the body says `Ref #8706` (not `Closes`), and #8706 carries the follow-through
      directive and label.
- [ ] `bun test plugins/soleur/test/preflight-discoverability-test.test.ts` passes with
      `BASELINE_DECLARED_PROBES` bumped; the PR body lists every floor or baseline this PR moves
      (`FLOOR_BLOCKS`, `MIN_SSH_PROVISIONED`, `BASELINE_DECLARED_PROBES`) so none reads as unrelated.

### Post-merge (automated; read without SSH)

- [ ] The merge's `apply-web-platform-infra.yml` run is green, and its SSH step's log shows
      `luks_monitor_install` created with `LoadState=loaded`, `UnitFileState=enabled`,
      `ActiveState=active` and a `NextElapseUSecRealtime` between 00:00 and 00:30 UTC
      (`gh run view <id> --log | grep -E 'UnitFileState|NextElapse'`).
- [ ] Within 15 minutes of that apply, the Phase 2 predicate returns at least 1 row
      (`betterstack-query.sh`, raw SQL).
- [ ] If the alert fired between the MAIN apply and the kick row (Sharp Edges), its incident is
      resolved within `recovery_period` of the first host-unit row (Better Stack alert API read).
- [ ] The next night, a host-unit `OK:` row lands in 00:00-01:00 UTC; the alert stays quiet.
- [ ] The follow-through closes #8706 after three consecutive qualifying nights.

## Test Scenarios

- Given the installer block, when any delivered file changes, then `triggers_replace` changes
  (static: every `file` provisioner source appears as a `file()` trigger operand).
- Given the installer block, when the kick line is moved above the enable/assert lines, then the
  suite reds (Guard 2 row 4).
- Given the DSN writer's inline commands extracted from the `.tf` and run against a temp file
  holding only `DOPPLER_TOKEN=x` (synthesized), then the file holds that token line unchanged plus
  exactly one DSN line, mode 0600; run again with an old DSN line present, only that line changes;
  run with the file absent, it is created 0600 with only the DSN line.
- Given the alert SQL, when the unit conjunct is removed, then the static suite reds (Guard 1 row 1)
  and the live control B shows verify rows would satisfy it.
- Given no host-unit row for 27 h, when the alert evaluates, then it fires (`lower_than 1`,
  `treat_as_zero`).
- Regression for #8706: the next apply log after merge no longer prints `0 timers listed.`

## Domain Review

**Domains relevant:** Engineering

### Engineering

**Status:** reviewed
**Assessment:** `soleur:engineering:cto` — go. Terraform SSH delivery is the right channel (the
cutover channel failed twice; cloud-init cannot reach web-1). Required and adopted: target in the
SSH-apply stage (Guard 1 of `terraform-target-parity`), keep the cutover tail, serialize the two
env-file writers, record the dead-man gap, ADR-119 addendum covering the DSN and the emit fallback.
The CTO's freeze-refusal was later cut at plan review (see Plan Review Revisions). One CTO blocker was based on reading `log()` as
logger-only; `log()` also echoes to stdout, and the measured stdout attribution is 100%, so the
`INVOCATION_ID` change is cut (Cut List). The CTO's split-heartbeat alternative is recorded and
rejected in Alternatives. `soleur:engineering:infra:terraform-architect` (Phase 2.8) — design sound;
adopted: non-empty DSN precondition, drop the `_TRANSPORT` conjunct, 27 h window instead of an
unmeasured `confirmation_period`, and the trigger-trade-off comments. Its stage-then-install and
stdin DSN helper were adopted, then cut at plan review. Declined: a shared `flock` (Sharp Edges).

Legal: not relevant. The public at-rest claim (`docs/legal/privacy-policy.md`) asserts LUKS
encryption, not a daily host re-test, and stays supported by the verify job throughout.
Product: no user-facing surface.
