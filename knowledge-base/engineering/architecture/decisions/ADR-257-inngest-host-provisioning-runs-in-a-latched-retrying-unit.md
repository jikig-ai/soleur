---
title: The dedicated inngest host provisions through a latched, retrying systemd unit, not once-per-instance runcmd
status: adopting
date: 2026-09-28
amends: none
supersedes: none
issue: 8562
related: [8539, 8036, 6985, 6780, 7228]
related_adrs: [ADR-100, ADR-096, ADR-115, ADR-142]
brand_survival_threshold: aggregate pattern
---

# ADR-257: The dedicated inngest host provisions through a latched, retrying systemd unit, not once-per-instance `runcmd`

## Status

**Adopting — 2026-09-28 (#8562).** The decision is true of the **template**
(`apps/web-platform/infra/cloud-init-inngest.yml`) at merge, not of the live host. Merging replaces
nothing. `hcloud_server.inngest`'s `user_data` is ForceNew, and the change reaches the host only
through the next operator-approved `apply_target=inngest-host-replace` dispatch, followed by a
human-approved `cutover-inngest.yml -f op=resume` (ADR-100's 2026-08-25 addendum: code delivery to
this host is replace-only). Until then the live host keeps the once-per-instance behavior this ADR
replaces.

The status flips to `accepted` when `scripts/followthroughs/inngest-provision-unit-8562.sh` reads
`verdict=PASS` after the first replace that delivers the change: a `bootstrap-done` row carrying
the same `iid` as the newest `provision-unit-armed` row. The probe is enrolled as a follow-through
on #8562.

## Context

The dedicated inngest host is the fleet's only scheduler (ADR-100). It fetches its bootstrap image
from zot, extracts `inngest-bootstrap.sh` and runs it. Before this change that happened once, in
the last cloud-init `runcmd` item (the item headed
`# --- Extract + run inngest-bootstrap.sh from the baked OCI image`).

`runcmd` runs once per instance. If that one attempt missed, nothing retried it, and a reboot did
not help either. A miss can come from a private NIC that converges after the 150 s wait (#8539), a
zot outage, or a transient docker or Doppler error. Since #8036 item 1d there is no GHCR fallback
behind the zot pull (ADR-096, "Amendment 2026-09-24 (#8036 item 1d)"), so a miss ended the boot:
the host stayed dark until another `inngest-host-replace` plus `op=resume`. The 2026-09-22
incident cost about 59 minutes that way.

ADR-115 rejected a self-reboot for inngest ("Reboot-for-inngest" row) partly because `runcmd`
would not re-run on a reboot anyway. The problem is that the provisioning step has no retry
edge at all, not that the host lacks a reboot.

## Decision

1. **One script, one unit.** The zot login, the boot-credential isolation self-check, and the
   pull → extract → bootstrap → health block move out of `runcmd` into
   `/usr/local/bin/soleur-inngest-provision`. The script runs as `soleur-inngest-provision.service`:
   - `Type=oneshot`, `Restart=on-failure`, `RestartSec=120`, `StartLimitIntervalSec=0` (unlimited,
     rate-bounded retries; no terminal state to strand the host in), and a per-attempt
     `TimeoutStartSec` derived from measured attempt durations;
   - `EnvironmentFile=/etc/default/inngest-doppler` without the `-` tolerance prefix, so the
     script gets the same Doppler environment `runcmd` had, and a missing file fails the attempt
     loudly;
   - `StateDirectory=soleur-inngest-provision`, which holds the attempt counter and the latch on
     the root disk;
   - **no `[Install]` section.** A `WantedBy=multi-user.target` would add an `After=` ordering
     and make boot completion wait on a oneshot that may retry for hours.
2. **A latch.** The script writes an empty file, `/var/lib/soleur-inngest-provision/done`, only
   after `inngest-bootstrap.sh` exits 0, and then ends with an explicit `exit 0`. The unit's
   `ConditionPathExists=!/var/lib/soleur-inngest-provision/done` is the latch's one consumer. It
   only refuses a start; it never resumes or replays anything.
3. **A boot timer.** `soleur-inngest-provision.timer` (`OnBootSec=90s`) starts the unit on every
   later boot until the latch exists.
4. **`runcmd` only arms the unit.** It keeps its first-boot-only work (LUKS stage, NIC wait,
   env-file and user writes). Its last items enable the timer (without `--now`, since an
   already-elapsed `OnBootSec=` would fire at once and become a hidden second trigger), start the
   service with `--no-block`, and phone home `provision-unit-armed iid=…`. The pull moves; it is
   not copied, so there is one code path and one environment.
5. **Paging.** Every missed pull attempt emits `inngest_pull_fatal` on both channels (Sentry via
   `soleur-boot-emit`, Better Stack via the phone-home), now carrying `attempt=N`. The existing
   rule `sentry_alert.zot_mirror_fallback_rate` (`frequency_minutes = 23`, one grouped issue) is
   unchanged. Every failed attempt also emits `provision-attempt-exit-<rc>` (phone-home) and
   `provision_attempt_failed` (Sentry, visibility only; its alert rule is a tracked deferral).
   New stages carry `iid=<cloud-init instance-id>`, and so does `bootstrap-done`, because old and
   new hosts share `host_name` during a replace.
6. **Quiesce the cutover FSMs before every bootstrap run.** Immediately before invoking
   `inngest-bootstrap.sh`, the script stops `inngest-cutover-flip.timer` and
   `inngest-luks-cutover.timer`, then waits (bounded at 300 s) until neither
   `inngest-cutover-flip.service` nor `inngest-luks-cutover.service` is activating. If the bound
   expires it emits `provision-fsm-busy` and exits non-zero, which retries. The bootstrap
   re-enables both timers as it does today. The provision unit deliberately has no `Before=`
   ordering on those services: the bootstrap restarts units synchronously, so that ordering would
   invite a deadlock.

## Consequences

- **Delivery is by replace only.** The template changes at merge; the live host changes at its
  next `inngest-host-replace` plus `op=resume`. This change adds no replace of its own. It rides
  the next replace some other change requires.
- **A missed attempt no longer darkens the scheduler until a second replace.** The unit retries
  the whole block every 120 s on the same host, and the first attempt after the cause clears
  provisions it.
- **A provisioned host's reboot does not re-provision it.** The latch makes the unit a no-op, which
  matches today's once-per-instance behavior for a healthy host. A host that never latched
  re-provisions on every boot, 90 s after boot, until it does.
- **Recovery never uses SSH or a latch delete.** The latch has one writer (the script) and is
  reset only by a replace, which gives a fresh root disk. Re-provisioning a latched host is a
  replace. `hr-no-ssh-fallback-in-runbooks` applies unchanged.
- **Paging repeats while the host stays dark.** Each missed attempt is a new
  `inngest_pull_fatal` event, and the rule's 23-minute throttle caps the email at about 2.6 an
  hour on one grouped issue. Before this change a dark host paged once. The runbook
  (`inngest-server.md` § "Provision unit (#8562)") explains `attempt=N` and says to wait for
  `bootstrap-done` with the same `iid` before deciding to replace.
- **Better Stack row volume rises on a failing host,** up to about 150 rows an hour on a
  fast-failing host. Each attempt makes at most about 6 Doppler reads.
- **Singleton guarantee (ADR-100).** A self-recovered host never starts serving on its own
  authority. `inngest-server-flip-guard.sh` refuses a production start on an inherited `done`,
  one this host carries no `done-owner` marker for (ADR-100 Decision 6, #7228). A replaced host's
  fresh root disk has no marker until its own verified flip, which `op=resume` drives. So a unit that
  succeeds late brings the server up behind the guard, not into the scheduler role. No two
  bootstraps can overlap on this host either: systemd runs one instance of a unit, so `runcmd`'s
  single `start --no-block` and the timer serialize onto one job, and `ci-deploy.sh`'s bootstrap
  path runs only on web hosts (the dedicated host has no deploy webhook).
- **AOF safety under a kill (ADR-142).** A `TimeoutStartSec` kill, a shutdown or a reboot
  mid-attempt keeps the default `KillMode=control-group`. That signals only the provision unit's
  cgroup: the script and its `systemctl` clients. Redis, the server and the flip each run in
  their own unit cgroup, and killing a `systemctl` client does not cancel the job PID 1 is
  running. What a kill can leave behind is a half-written unit file or binary, which the next
  attempt's idempotent bootstrap re-installs. The long children run as `cmd & wait` behind a
  TERM trap, so the attempt reports before SIGKILL.
- **No mount precondition, by design (ADR-142).** The unit orders
  `After=inngest-luks-open.service` but adds no `/mnt/data` mount check. A failed LUKS stage keeps
  today's behavior: `inngest-redis.service`'s mount guard and the mapper-identity check in
  `inngest-redis-bootstrap.sh` refuse Redis, and the server serves SQLite-only
  (`INNGEST_DURABLE_DEGRADED`). A mount check would instead make the host retry forever with the
  scheduler dark, and nothing re-runs the LUKS stage on that boot.
- **The FSM quiesce creates an ordering rule on the sole scheduler (ADR-100).** A retry after a
  late failure re-runs the bootstrap's restarts of `inngest-redis` and `inngest-server`.
  Without the quiesce, a retry coinciding with an `op=resume` run could restart the server
  inside the flip's `verify_serving` window and drive the FSM to `aborted`, which needs a
  `/mnt/data` recut to recover. The runbook rule is also written down: run `op=resume` only
  after the new host's `bootstrap-done`. An `op=resume` gate row that enforces it is a tracked
  deferral.
- **Arming residual (acknowledged, not widened).** The timer is enabled in the last `runcmd`
  items, after the last prerequisite the unit needs (`/etc/default/inngest-server`, the deploy
  user, the probe credential). If an earlier `runcmd` item aborts, for example on a LUKS-stage
  FATAL, the unit is never armed and the host stays dark until a replace, exactly as today. The
  aborting item's own phone-home stage says why, and the follow-through probe reads FAIL when no
  `provision-unit-armed` row, or no `provision-attempt-start` after it, appears. Arming earlier
  would let the unit run on a later reboot without prerequisites only `runcmd` writes, turning a
  loud stage FATAL into an endless retry that can never succeed.
- **The unit's journald rows stay on the host.** Vector is installed by the bootstrap this unit
  runs, and shipping those rows would need a `vector.toml` edit, which mints a bootstrap tag. The
  off-host channels are the phone-home and the Sentry emitter (tracked on #6780).

## Alternatives considered

| Option | Verdict | Why |
| --- | --- | --- |
| **A. Unit only.** `runcmd` enables a boot timer (no `--now`) and starts the unit `--no-block` | **Chosen** | One code path and one environment. Both retry and reboot are covered. |
| **B.** `runcmd` runs the script synchronously for attempt 1, with a unit and timer for later runs | Rejected | Two environments (the shared `runcmd` shell and `EnvironmentFile=`) reproduce the #6985 token-loss class by construction. A concurrent timer tick would also need `flock`. |
| **C.** The git-data shape: a `StartLimitBurst=5` window, an `OnFailure=` reporter and a 15-minute standing timer | Rejected | With a 45-minute attempt timeout, a window at least as long as the slow retry ladder is 3.8 h or more, so a 20-minute zot blip would retry only after the window closes. `RestartSec=120` recovers within about 2 minutes of the cause clearing. |
| **D.** `cloud-init clean` and a re-run on reboot | Rejected | ADR-115's three verified failure modes (its first §Alternatives row). |
| **E.** Reboot for inngest | Rejected | Rejected by ADR-115 (its "Reboot-for-inngest" row), and `runcmd` would not re-run on the reboot anyway. This ADR grants no reboot authority. |
| **F.** Bake the retry into the bootstrap image | Impossible | The image is the thing being fetched. |

## Relationship to other ADRs

- **ADR-100** (singleton control plane): a new actor on the sole scheduler. The replace-only
  delivery path is unchanged; the FSM quiesce and the `op=resume`-after-`bootstrap-done` rule are
  recorded there in a dated addendum.
- **ADR-096** (zot migration): for inngest, the #8036 item 1d "a miss is terminal" statement now
  holds per **attempt**, not per boot, in the template. Recorded there in a dated note.
- **ADR-115** (private-NIC boot convergence): its once-per-instance premise for inngest now applies
  only to a host that has provisioned. Its acceptance stays registry-only and no reboot authority
  is granted. Recorded there in a dated note.
- **ADR-142** (Redis AOF on LUKS): cited for the no-mount-precondition choice and the
  AOF-safety-under-kill argument above. Not amended.

## Diagram

No element, relationship or store is added. The `inngest -> sentry` edge description in
`knowledge-base/engineering/architecture/diagrams/model.c4` said a zot miss "ENDS the boot"; it now
says the miss ends the attempt and the unit retries every 120 s until one succeeds.
