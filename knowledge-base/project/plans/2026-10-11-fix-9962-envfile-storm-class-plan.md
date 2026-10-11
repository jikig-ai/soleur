# Plan: absent-EnvironmentFile storm class on non-LUKS units (#9962)

Issue #9962, filed from the #9939 review panel. #9944 conditioned the three
`inngest-luks-*` units (`ConditionPathExists=` skip + fail-closed unprefixed
`EnvironmentFile=`) and #9965 armed the `Failed to start inngest-luks` capture
needle. This slice applies the same calibration to the units the panel
enumerated plus the same-class siblings a fresh census surfaces.

Risk tier: single-user incident (production host unit semantics; dark-vs-loud
calibration).

## Census of unprefixed `EnvironmentFile=` on runcmd-written files

| Unit | File | Activation | Storm shape | Disposition |
|---|---|---|---|---|
| inngest-cutover-flip.service | `/etc/default/inngest-server` | timer 30s, `Persistent` | `Failed to start` every 30s | CONDITION (service + timer) |
| soleur-inngest-provision.service | `/etc/default/inngest-doppler` | boot re-entry timer + `start --no-block` | `Restart=on-failure` ×4 @120s | CONDITION (service; timer stays — its own condition already arms) |
| inngest-heartbeat.service (bootstrap.sh) | `/etc/default/inngest-server` | timer 60s | same + `OnFailure` ERR rows | CONDITION (service + timer) |
| vector.service (bootstrap.sh) | `/etc/default/inngest-server` | `WantedBy` boot + `RestartSec=10` | crash-loop | CONDITION (service) |
| inngest-server.service (bootstrap.sh) | `/etc/default/inngest-server` | `WantedBy` boot + `RestartSec=5` | crash-loop (worst) | CONDITION (service) |
| inngest-redis.service | `/etc/default/inngest-server` | `WantedBy` boot | same | LEAVE LOUD — designated; `RequiresMountsFor` is already its designed-loud signal; comment |
| `git-data-gc`, `cron-egress-*`, `container-restart-monitor`, `web*` | various | various | `-` prefixed already (tolerant, different mechanism) | out of scope |
| inngest-luks-* (×3) | LUKS files | timers | done | #9944 |

The compensating-detector argument (skipped ≠ invisible): an absent env file
post-provision is a real anomaly — but every conditioned unit's absence is
detected by a designed dark channel (Better Stack missing-heartbeat marker,
the flip FSM's phone-home, the probe's dark-arm, vector's shipping silence),
identical to the #9939 precedent's "dispatch-side liveness refusal +
no-terminal-flag confirm timeout". For inngest-server specifically the FSM +
control-plane probes are the channel.

## Needle widening

`Failed to start inngest-luks` → `Failed to start inngest` (shared prefix —
sees flip/heartbeat/vector/server/redis rows). The systemd-row scope arm
`UNIT.{0,12}inngest-luks` → `UNIT.{0,12}inngest` would match the FP control
row's `"_SYSTEMD_UNIT":"inngest-server.service"` — anchor it `[="]UNIT` so the
`_SYSTEMD_UNIT` field name can't launder a doppler row into the count.

## Files

- `apps/web-platform/infra/inngest-cutover-flip.service` — [Unit] condition + SKIP-VS-FAIL comment
- `apps/web-platform/infra/inngest-cutover-flip.timer` — same condition (evaluated at activation)
- `apps/web-platform/infra/inngest-bootstrap.sh` — conditions in the heartbeat service + timer, server, vector heredoc units
- `apps/web-platform/infra/cloud-init-inngest.yml` — condition in soleur-inngest-provision.service [Unit]
- `apps/web-platform/infra/inngest-redis.service` — deliberately-loud comment only
- `scripts/followthroughs/inngest-provision-rehearsal-capture.sh` — needle + function rename + `[="]UNIT` scope arm
- `scripts/followthroughs/inngest-provision-rehearsal-capture.test.sh` — flip + server forbidden-row fixtures
- `apps/web-platform/infra/inngest.test.sh` — per-unit assert rows mirroring the _luks_sec helpers

## Acceptance criteria

- AC-1: every conditioned unit carries `ConditionPathExists=<env-file>` in `[Unit]` exactly once; its `[Service]` `EnvironmentFile=` stays unprefixed; the path-set equality assertion shape (conditions ≡ envfiles) holds per unit, including the flip + heartbeat timers.
- AC-2: `inngest-redis.service` carries no condition + a comment naming the deliberately-loud disposition.
- AC-3: the capture's forbidden-row check counts a `Failed to start inngest*` row for any inngest unit and still rejects the doppler-tagged FP control row; function names say `inngest`, not `luks`.
- AC-4: `bash inngest.test.sh`, `inngest-provision-rehearsal-capture.test.sh`, `cloud-init-inngest-provision-unit.test.sh`, `inngest-redis-luks.test.sh`, `inngest-server-flip-guard.test.sh` green; provision-unit G4's "EnvironmentFile exactly once, no `-`" assertion still holds.
- AC-5: mutation — drop the condition from any one conditioned unit → the corresponding assert row goes RED.
