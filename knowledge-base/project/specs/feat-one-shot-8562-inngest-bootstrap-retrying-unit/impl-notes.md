# #8562 implementation notes (Phase 1 inventory, measurements, run evidence)

Scratch notes from the implementation pass. The plan is
`knowledge-base/project/plans/2026-09-28-fix-inngest-bootstrap-pull-retrying-unit-plan.md`.
Anchors are content, not line numbers (`cq-cite-content-anchor-not-line-number`).

## 1.1 runcmd classification (pre-change template, 28 items)

| # | Item (first code line) | Verdict |
|---|---|---|
| 1 | `runcmd-entered` bs-token stage + phone-home | stays |
| 2 | `networkctl reload` (#8539) | stays |
| 3-4 | `systemctl restart sshd` + phone-home | stays |
| 5 | `mkdir -p /mnt/data` | stays |
| 6 | Doppler CLI install | stays |
| 7-8 | `/etc/default/inngest-doppler` printf + chmod | stays (now also the unit's `EnvironmentFile=`) |
| 9 | LUKS stage (`doppler run … <<'LUKSEOF'`) | stays |
| 10 | `enable --now inngest-luks-open.service` | stays |
| 11 | bs-token fetch (`doppler-token-fetched`) | stays |
| 12 | `enable inngest-bs-token-restage.service` | stays |
| 13 | zot `daemon.json` allowlist | stays |
| 14 | `enable --now docker` | stays |
| 15 | `systemctl restart docker` | stays |
| 16 | `enable --now inngest-nftables.service` | stays |
| 17 | `/etc/default/soleur-zot-read` bake | stays |
| 18 | NIC wait (`soleur-inngest-nic-wait`) | **stays** (once, before anything can start the unit) |
| 19 | zot login | **moves** into the script |
| 20 | isolation self-check (+ `/run/soleur-inngest-doppler.ok` write) | **moves**; the sentinel is retired |
| 21-24 | deploy group/user + phone-home | stays |
| 25-26 | `/etc/default/inngest-server` + chown | stays |
| 27 | probe credential | stays |
| 28 | pull → extract → bootstrap → health | **moves** into the script |
| new | `daemon-reload`, `enable …timer` (no `--now`), `start --no-block …service`, `provision-unit-armed` | arming, appended last |

Post-change runcmd: 29 items (28 − 3 moved + 4 arming). Rendered and parsed by the suite.

## 1.2 Cross-item state census (P8)

What the moved text read, where it came from inside the shared runcmd `/bin/sh`, and where it
comes from now.

| Read by the moved text | Old source (shared runcmd shell) | New source | Guard |
|---|---|---|---|
| `DOPPLER_TOKEN` (isolation `doppler run`, `DIAG_BOOT`, redact) | isolation item's `set -a; . /etc/default/inngest-doppler` — leaked to the pull item by the shared shell (the #6985 class) | unit `EnvironmentFile=/etc/default/inngest-doppler` (no `-`); the script checks it is non-empty (`provision-env-MISSING`) | G4, G7 (Tier A env built only from the executed write + unit `Environment=`), T6 (Tier B, real parsing) |
| `HOME` | same `set -a` (file carries `HOME=/root`) | unit `Environment=HOME=/root` + the same file | G4 row "HOME=/root reaches the unit environment", env check |
| `DOPPLER_CONFIG_DIR`, `DOPPLER_ENABLE_VERSION_CHECK` | same `set -a` | `EnvironmentFile=` | env check (G7 r4 is RED through it) |
| `ZOT_REGISTRY_ENDPOINT`/`ZOT_PULL_USER`/`ZOT_PULL_TOKEN`, `ZOT_EP` | each item `.`-sourced `/etc/default/soleur-zot-read` itself | the script initialises all three to `""`, then loads the file once (`if [ -r … ]; then . …; fi`) and derives `ZOT_EP` once | G7 (r1: a read before derivation aborts under `-u`) |
| `/run/soleur-inngest-doppler.ok` | written by the isolation item, `test -f` by the pull item | **retired**; the check's own `if` is the status, re-run every attempt | G8 (static: the path appears nowhere in the render; T3 after a prior pass) |
| `/run/inngest-bs-logs-token` | runcmd item 1 + restage unit | same, plus a per-attempt re-stage when empty | T17 |
| `PATH` (bare `soleur-boot-emit`, `doppler`, `docker`) | cloud-init's PATH | unit `Environment=PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin` | Tier A/B run with exactly that PATH (Tier A prefixes the stub dir) |
| `umask` | runcmd default 0022 | `UMask=0022` | G6 |
| errexit state | leaked between items (`set -e` in the pull item, `set +e` at the end of the isolation item) | explicit per region inside one script; the miss arm runs under `set +e` on purpose | G2 r2, G2 r8 |
| cwd | cloud-init's | systemd default `/`; the script uses no relative path | — |
| template vars (`inngest_cli_arch`, `inngest_cli_sha256`, `vector_sha256`, `sdk_url`, `inngest_private_ip`, IREF/ZIREF pins) | render-time | render-time (unchanged; carried verbatim) | render gate + bump-bot 2-ref invariant |
| `/etc/default/inngest-doppler`, `/etc/default/soleur-zot-read` lifetime | read once | read on EVERY attempt, possibly for hours | checked: nothing in runcmd or `inngest-bootstrap.sh` deletes/rewrites either (`inngest-bootstrap.sh` only names `inngest-doppler` as another unit's `EnvironmentFile=-`) |

Guard 7 is enforced by execution, not by a free-variable parser: every Tier A scenario runs the
rendered script under `dash -u` with `env -i` + the executed-write fixture + the unit's
`Environment=` lines, and Tier B runs it through a `/bin/sh -u` ExecStart drop-in.

## 1.3 Consumers of the moved side effects and stage names (meaning under retry)

- `/etc/default/soleur-inngest-image`: read by `inngest-bootstrap.sh` (`image_ref`),
  `tests/scripts/lib/inngest-host-dark-gate.sh` and `inngest-cutover-flip-rollout-7761.sh`. A retry
  rewrites it with the same digest-pinned bytes: meaning unchanged.
- `/var/log/inngest-zot-pull.log`, `/var/log/inngest-bootstrap.log`: host-local, rewritten per
  try/attempt; the shipped tail is the last one. Unchanged.
- `scripts/followthroughs/zot-soak-6122.sh`: counts `stage:"inngest_pull_fatal"` as `[freshboot]`
  failures with a zero tolerance. A dark host now emits one per missed ATTEMPT instead of one per
  boot, so the count can be larger; the PASS/FAIL verdict (any ≥ 1 fails) is unchanged.
- `scripts/followthroughs/inngest-host-not-serving-7674.sh`: substring-reads `inngest_zot` and
  `bootstrap-done`. `bootstrap-done` now carries `attempt=N iid=…` as detail; substring match
  unaffected. #7674 is closed.
- `tests/scripts/test-sentry-alert-live-fidelity.sh`,
  `apps/web-platform/test/sentry-zot-mirror-fallback-alert-op-contract.test.ts`: the literal
  `soleur-boot-emit inngest_pull_fatal fatal "rc=$zot_rc"` / `"rc=noendpoint"` sites are kept
  byte-identical (vitest file: 32/32 green).
- `scripts/cutover-inngest.sh`: gates on flip liveness rows, not boot stages. Unaffected.
- `apps/web-platform/infra/scripts/fresh-host-boot-trail.sh`: web-host births only (its
  "runcmd is once-per-instance" guidance is about the web host). Unaffected.
- "Is the host done?" readers: none keys on cloud-init completion for the inngest host; the
  follow-through probe keys on `provision-unit-armed` → `bootstrap-done` with the same `iid`.

## 1.4 `TimeoutStartSec` derivation

**Superseded by the review batch (PR #9159): 45 min did NOT hold; the unit now sets
`TimeoutStartSec=65min`.** The first derivation below omitted the bootstrap's synchronous
`systemctl` waits and the two steps the review added (the reboot-path NIC wait and the dpkg
recovery). The corrected sum follows the original table.

Bounded steps, from the steps' own bounds (not healthy history) — original derivation:

| Step | Bound |
|---|---|
| bs-token re-stage (`timeout 20` doppler) + its phone-home | 20 s + 8 s |
| docker readiness | 30 × 2 s = 60 s |
| zot login | `timeout 60` = 60 s |
| pulls | 3 × 180 s + 2 × 5 s = 550 s |
| `DIAG_BOOT` | `timeout 20` = 20 s |
| cutover-FSM quiesce | 300 s (one shared budget for both units) |
| Vector download inside the bootstrap | 4 × 180 s + (5 + 10 + 15) s = 750 s |
| bootstrap's own sleeps | `DRAIN_SLEEP_SEC` 2 s + `sleep 2` = 4 s |
| post-boot `sleep 8` + two `curl --max-time 5` | 18 s |
| ~15 phone-home / Sentry emits at ≤ 8 s each | ~120 s |
| **bounded sum** | **~1,910 s ≈ 31.8 min** |

Unbounded: the inngest binary `curl` (`inngest-bootstrap.sh`), the apt path in
`inngest-redis-bootstrap.sh`, the isolation `doppler run`, and the `doppler secrets download`
inside each `inngest-redact.sh` call. Margin ≥ 10 min → **`TimeoutStartSec=45min`**
(1,910 s + 790 s = 2,700 s). Better Stack history cross-check: NOT performed (no read-only
`BETTERSTACK_QUERY_*` credentials in this session's environment). The arithmetic is also in the
unit's comment in `cloud-init-inngest.yml`.

### 1.4b Corrected derivation (review batch)

| Added or previously missing step | Bound |
|---|---|
| reboot-path NIC wait (`soleur-inngest-nic-wait`, only when the address is absent) | 150 s |
| `timeout 300 dpkg --configure -a` before the bootstrap | 300 s |
| `inngest-server` restart inside the bootstrap (`TimeoutStopSec=180` + default start 90 s) | 270 s |
| `inngest-redis` restart (`inngest-redis-bootstrap.sh`: stop 30 s + start 90 s) | 120 s |
| `vector` restart (stop 30 s + start 90 s) | 120 s |
| `systemd-journald` restart (default start 90 s) | 90 s |
| heartbeat oneshot (curl `--max-time 10`) + server-probe oneshot (`TimeoutStartSec=120`) | ~130 s |
| `docker create` + 13 `docker cp` (local) | ~30 s |
| ~5 more emits than the first count (the new stages) | ~40 s |
| **added** | **~1,250 s** |

The `enable --now` of the heartbeat, probe, flip and LUKS-cutover timers are near-instant; the
bootstrap's own `DRAIN_SLEEP_SEC` + `sleep 2` were already counted.

Bounded sum: ~1,910 s + ~1,250 s − the double-counted ~40 s of emits ≈ **3,220 s (~54 min)**.
Unbounded steps are unchanged (inngest binary curl, the redis apt path, the isolation
`doppler run`, the redaction downloads). Margin ≈ 11 min → **`TimeoutStartSec=65min`**
(3,900 s). The unit comment carries the same arithmetic. The static guard allows 20 min–2 h.

### Retry rate with the back-off (review item 9)

`RestartSec=120`, `RestartSteps=4`, `RestartMaxDelaySec=15min` (systemd ≥ 254; the host runs
255). systemd interpolates the delay geometrically over the four steps:
120 s → ~198 s → ~329 s → ~545 s → 900 s, then it stays at 900 s.

| Failure shape | Attempt length | First hour | Backed off |
|---|---|---|---|
| fast fail (refused connection, isolation FATAL, env missing) | seconds | the first 4 retries take ~20 min; ~8 attempts in hour one | 3600 / 900 ≈ **4/h** |
| zot unreachable (60 s login + one 180 s pull timeout, not retried, + readiness and emits) | ~330 s | ~5 in hour one (starts at 0, 450, 979, 1638, 2512 s) | 3600 / (330 + 900) ≈ **3/h** |

The review said "~330 s ≈ 11/h" for the zot case; 11/h is the attempt length alone
(3600 / 330). With the restart delay it is 3600 / 450 = 8/h at a flat `RestartSec=120`, ~5 in
the first hour with the back-off, and ~3/h once backed off.
Paging stays capped by the Sentry rule's 23-minute throttle on one grouped issue either way.
Tier B disables the back-off with a `RestartSteps=0` drop-in (every retry is 2 s); the
production ladder is pinned statically (G6 "the restart delay backs off", row G6-r16).

## Payload (Phase 0.2 / 3.5)

`bash apps/web-platform/infra/inngest-userdata-budget.sh`:

| | raw | stripped | stored (b64gzip) | headroom |
|---|---|---|---|---|
| before (merge-base template) | 125,834 B | 47,964 B | 16,400 B | 16,368 B |
| after | 144,743 B | 53,334 B | 18,396 B | 14,372 B |

Render starts `#cloud-config`; `cloud-init schema -c` (cloud-init 26.1, ubuntu:24.04 container)
reports `Valid schema` on the stripped render. Exactly 2 pinned refs remain (bump-bot invariant).

`plugins/soleur/test/cloud-init-user-data-size.test.ts` carries a SOFT early-warning bracket
`INNGEST_GZIP_BUDGET = 18_000`; its node-zlib model measured 18,072 B after the change, so the
bracket was raised to 20,000 with a dated rationale (the hard 32,768 B cap and the terraform-exact
CI gate are untouched). This file was outside the implementation agent's listed scope — flagged.

## Mint dry-run (Phase 3.6)

`bash .github/scripts/mint-inngest-bootstrap-tag.sh --dry-run`:

```
::notice::base=vinngest-v1.1.40 — HEAD builds the same image inputs; nothing to mint. ...
base=v1.1.40
changed=
tags=local
reason=unchanged
result=noop
```

## Design decisions taken during implementation (and alternatives)

1. **Sentry detail of `inngest_pull_fatal` kept as `rc=$zot_rc` / `rc=noendpoint`** (plan said
   `rc=… attempt=N`). `sentry-zot-mirror-fallback-alert-op-contract.test.ts` pins those literals
   and is outside this scope; `soleur-boot-emit` also strips spaces from detail. The attempt number
   reaches Sentry through the EXIT trap's `provision_attempt_failed` (`rc=N.attempt=N.iid=…`) and
   Better Stack through the `inngest_pull_fatal` phone-home detail. Alternative: change the literal
   and re-point the vitest file.
2. **`provision_attempt_failed` is emitted at `warning`**, not `error`: `soleur-boot-emit` accepts
   only `info|warning|fatal` and maps anything else to `info`. A retrying failure is a warning;
   the page stays on `inngest_pull_fatal` (fatal).
3. **`AccuracySec=1s` added to the timer.** Tier B measured a 2 s `OnBootSec` firing 23 s late
   under the default 1 min coalescing window; on the host that is 90-150 s. Not in the plan's
   sketch; small and deterministic.
4. **The miss arm runs under `set +e`** (restored after the arms). This makes plan Guard 2 row 2
   (`( exit "$zot_rc" )`) observable: under `set -e` that mutant was equivalent. The old
   zot-pull battery row `g4-row7a` (a must-PASS asserting that equivalence) became a must-RED row.
5. **Environment precondition** (`provision-env-MISSING`, exit 1) added at attempt start: a unit
   whose `EnvironmentFile=` did not deliver `HOME`/`DOPPLER_TOKEN`/`DOPPLER_CONFIG_DIR` fails
   loudly before any Doppler call. Gives Guard 4 row 4 and Guard 7 row 4 a runtime detector.
6. **`/etc/default/soleur-zot-read` loaded with `if [ -r … ]`**: in dash `. missing || true` kills
   the shell (rc 2, measured); a missing file now reads as an empty endpoint and takes the fatal arm.
7. **Tier A rewrite is one simultaneous pass** (a sequential replace rewrote `/tmp/` inside the
   already-substituted `/var/tmp/<fx>` path). Same fix applied to the re-pointed Guard 4 slice.
8. **`/root/` pair omitted from the Tier A rewrite table**: the script names no `/root/` path, so
   by the plan's own rule (every pair must match) it would be a guaranteed instrument fault.
9. **Tier B boots without the `-v /sys/fs/cgroup:/sys/fs/cgroup:rw` bind** from the plan's command:
   `--privileged --cgroupns=private` alone boots systemd 255 cleanly, and a host cgroup bind into
   a privileged systemd container risks the host's own hierarchy on a developer machine.
10. **Residual (documented, not fixed):** a SIGTERM that lands after the latch but during the
    ~8-20 s post-boot diagnostics (a shutdown in that window) reports
    `provision-attempt-exit-143` although the host is provisioned; the latch still condition-skips
    the next boot. Forcing rc 0 in the trap once latched was rejected: it would make the explicit
    final `exit 0` (Guard 3 row 5) an equivalent mutant.

## Re-pointed suites (before → after, all green on the final tree)

| Suite | Before | After | Change |
|---|---|---|---|
| `cloud-init-inngest-bootstrap.test.sh` | 230/230 (153 unconditional) | 230/230 (153 unconditional) | re-pointed: block + Guard 4 slice from the write_files script, Guard 4 doppler stub/env/rewrite pairs, sentinel fixture dropped, Phase 4 vs the unit start, NIC-G1 resolves `systemctl start` → ExecStart script (row 1 "precedes") |
| `cloud-init-inngest-zot-pull-mutation.test.sh` | 61/61 killed | 61/61 killed | anchors re-indented; ng1-row1 moves the call after the unit start; g4-row7a must-PASS → must-RED; g4-phfail injects `\|\| exit 3` |
| `inngest-host.test.sh` | 82 | 83 | §9-§9c read the provision script; flip-asset cp source `"$cid:/…"` + a new row binding `cid` to the pinned create |
| `inngest-redis-luks.test.sh` | 57 | 57 | none needed |
| `inngest-boot-emitter.test.sh` | 93 | 93 | none needed |
| `inngest-nic-wait.test.sh` | 400 | 400 | none needed |
| `inngest-bootstrap-mirror-only.test.sh` | 62 | 62 | none needed |
| `journald-config.test.sh` | 88/88 | 88/88 | none needed |
| `inngest-redis-luks-loopback.test.sh` | not runnable locally (needs root/passwordless sudo: `LOOPBACK_UNAVAILABLE`) | same | none; it slices the untouched `LUKSEOF` stage |
| `plugins/soleur/test/cloud-init-user-data-size.test.ts` | 70/70 | 70/70 | soft bracket 18_000 → 20_000 (see Payload) |
| `apps/web-platform/test/sentry-zot-mirror-fallback-alert-op-contract.test.ts` (vitest) | — | 32/32 | none needed |

Also re-run green with no change: soleur-host-bootstrap-observability (117), doppler-download-error-channel
(112), inngest-cutover-flip (150), cloud-init-web-zot-seed (101), cutover-inngest-workflow (1000),
inngest (414), doppler-injection-bound (33), credential-persist-home-guard (40),
templatefile-bare-dollar-guard (17), cloud-init-ghcr-seed-login (45), inngest-server-flip-guard (46),
test-bump-inngest-bootstrap-pin (487), zot-soak-6122.test, inngest-cutover-flip-rollout-7761.test
(366), test-inngest-volume-recut-gate (60).

## New suite: `cloud-init-inngest-provision-unit.test.sh`

- RED first (commit a75d5bf549): against the pre-change template the control row C0 failed 37
  assertions, including "dispatch: the unit exists", "G1: no runcmd item pulls an image" (found 1)
  and "G1: no runcmd item runs docker login" (found 1).
- GREEN on the final tree, locally and under `CI=1`: C0 94/94, `systemd-analyze verify` clean
  (systemd 261, `--root` with the host's unit tree), rows executed 59/59 (51 RED KILLED, 8 must-PASS
  HELD, 0 survived/misrouted/unresolved), Tier B ran with all six scenarios PASS. ~2.6 min wall.
- Tier A scenarios (never skip): X (xtrace → 78, zero calls), the `-u` probe, T1, T2, T3 (after a
  passing T3a in the same fixture), T4, T5, T7, T8, T14, T16, T17, and T6-A (doppler env). C0 is the
  control run of all of them.

### Tier B run log excerpt (systemd 255.4-1ubuntu8.17 as PID 1, CI=1 run)

```
PASS: T12 exactly one provision-attempt-start attempt=1 after arming; timer enabled, NOT active
PASS: T6  every doppler call received DOPPLER_TOKEN and HOME=/root via real EnvironmentFile=
PASS: T9  exit-143 lands 5.07 s after bootstrap start (5 s timeout); attempt=2 follows
PASS: T15 bootstrap starts only after the activating flip step ends; bounded wait -> fsm-busy, exit 1
PASS: T11 no latch: timer starts the unit 1.35 s after multi-user.target; target active while retrying
PASS: T10 NRestarts=2, active (exited), exactly 3 attempts despite an injected timer start
PASS: T11 latch present (written by T10): ConditionResult=no, zero attempts after reboot

1790614656.357 PHASE T12
1790614656.526 phone provision-attempt-start attempt=1 iid=i-tierb
1790614656.532 phone provision-unit-armed timer=enabled unit=activating iid=i-tierb
1790614656.710 phone bootstrap-done attempt=1 iid=i-tierb
1790614667.286 PHASE T9
1790614667.604 bootstrap start
1790614672.671 phone provision-attempt-exit-143 attempt=1 iid=i-tierb
1790614674.933 phone provision-attempt-start attempt=2 iid=i-tierb
1790614675.654 PHASE T15
1790614675.799 flip-start
1790614695.801 flip-end
1790614695.915 bootstrap start
1790614704.476 PHASE T15b
1790614708.557 phone provision-fsm-busy units=[.inngest-cutover-flip.service] waited_s=300 (fast-sleep stub)
1790614708.564 phone provision-attempt-exit-1 attempt=1 iid=i-tierb
1790614709.418 PHASE T11a   (docker restart; no latch)
1790614722.183 phone provision-attempt-start attempt=1 iid=i-tierb
1790614732.813 PHASE T10
1790614742.957 phone provision-attempt-exit-1 attempt=1
1790614755.230 phone provision-attempt-exit-1 attempt=2
1790614757.624 phone bootstrap-done attempt=3 iid=i-tierb
1790614766.298 PHASE T11b   (docker restart; latch present) -> no further rows
```

(The second exit-143 in T9 and the one after T15's bootstrap-done in earlier drafts are the
harness stopping the unit between phases; the final harness waits for `SubState=exited` first.)

## Mutation check on the key guards (source template, sandbox copy)

Each mutation was applied to a copy of `cloud-init-inngest.yml` in a scratch directory, the new
suite was run against that copy, and the worktree template's sha256 was compared before and after.

| Mutation | Result | First failing assertions |
|---|---|---|
| delete the latch write | RED | G3 condition/write-site rows, TA T2 latch |
| move the pull back into runcmd | RED | G1 runcmd pull (found 1), G1 script pulls=0, TA T1 exits 1 |
| drop the xtrace refusal | RED | G6 xtrace row, TA X (rc=0, 48 calls) |
| add `[Install] WantedBy=multi-user.target` to the service | RED | G6 no-[Install] row |
| place the FSM quiesce after the bootstrap call | RED | TA T4 quiesce order (stop=32 > boot=31) |

Worktree template sha256 `96389d43…0b7f3b` before and after: IDENTICAL.

## Review batch (PR #9159, 11-agent panel on 760504c6e1)

### Template and script changes

1. **Degraded success does not latch.** After `inngest-bootstrap.sh` exits 0 the script requires
   `systemctl is-active --quiet inngest-redis.service` and the `--postgres-max-open-conns`
   sentinel in `/etc/systemd/system/inngest-server.service` (the bootstrap's own durable-ExecStart
   detection sentinel, present only in its `REDIS_READY=1` arm). A requested diagnostic boot
   (`INNGEST_DIAGNOSTIC_BOOT` in `1|true|TRUE|yes|YES`, the bootstrap's own accepted set, after
   whitespace stripping) is exempt. Degraded: phone-home `bootstrap-done-DEGRADED`
   (`why=… attempt=N iid=…`) and Sentry `bootstrap_done_degraded` at `warning`, the diagnostics
   still run, exit 0, no latch.
2. **The quiesce records which FSM timers were active** and `on_exit` (rc ≠ 0) starts exactly
   those again.
3. **Busy is wider:** either oneshot `activating`, a non-empty
   `/var/lib/inngest-luks-cutover/frozen-active`, or `"flag":"flipping"` in the flip FSM's host
   state slot `/var/lock/inngest-cutover-flip.state` (written by `inngest-cutover-flip.sh`
   `emit_state`, `jq -nc`, so compact JSON). Residual: a frozen-active record that is NEVER
   cleared would hold every attempt at `provision-fsm-busy`; on a replaced host `/var/lib` is a
   fresh root disk, so that needs an un-latched host that rebooted mid-LUKS-cutover.
4. `on_exit` reports first, then cleans up; the container removal is `timeout 15 docker rm -f`.
5. `last_stage` is set before every phone-home; `provision_attempt_failed` carries
   `rc=N.attempt=N.why=<stage>.iid=…` (soleur-boot-emit's charset, iid last so a cut drops it).
6. `iid=` on isolation-check-passed/-FAILED, `inngest_pull_fatal` (Better Stack detail, both arms),
   pre-bootstrap-run, bootstrap-exit-N and bootstrap-failure-journal.
7. **Reboot-path NIC check.** `soleur-inngest-nic-wait` was read: it only reads `ip`/`networkctl`
   state, loops at most 75 × 2 s = 150 s, emits one `private_nic_*` event and always exits 0 —
   idempotent and bounded, but it never fails. So the script checks for the address first (no
   call, no emit when present: a healthy attempt does not re-page `web_private_nic_boot_gate`),
   runs the helper only when absent, re-checks, and on a still-absent address emits
   `provision-nic-ABSENT` and exits 1.
8. `timeout 300 dpkg --configure -a` (non-fatal) before the bootstrap.
9. `RestartSteps=4`, `RestartMaxDelaySec=15min`; rates above. `TimeoutStartSec=65min` (1.4b).
10. One `STAGED` list drives both the per-attempt `rm -f` loop and the `docker cp` loop.
11. `inngest-boot-phone-home.sh` passes `Authorization` via `curl -q -K -` on stdin.
12. Write-time charset guards before the `/etc/default/inngest-doppler` and
    `/etc/default/soleur-zot-read` writes: each value is read through a QUOTED heredoc (a quote in
    the value cannot break the check) and refused unless it matches `[A-Za-z0-9._:/-]`; refusal
    phones home (`inngest-doppler-write-REFUSED` / `zot-read-write-REFUSED`) and `exit 1`s the
    runcmd shell. The zot pull password is `random_password { special = false }`, so real values
    pass. The item's previous "failure convention" was none (a bare printf); the stage-then-exit
    shape follows the surrounding items. Probed: `dp.st.prd.ab'c;$(id)` → REFUSED, rc 1.
13. Comments corrected: the vector.toml copy (the web host copies by container name, this host by
    the create ID); the environment check (HOME always comes from `Environment=`); the xtrace
    refusal (it runs before the trap; its signature is armed-with-no-attempt-start, not a page);
    the arming residual (a failed item, a LUKS FATAL included, does NOT stop runcmd; the residual
    is a hang, cloud-init failing before runcmd, or the two new charset guards).

### Suite changes (`cloud-init-inngest-provision-unit.test.sh`)

- Static layer rewritten and widened: write_files paths normalized and aliases refused;
  drop-ins/shadow copies/`systemctl edit|set-property` of the unit or timer refused (write_files,
  runcmd, bootcmd); forbidden service directives (`TimeoutSec`, `StartLimitInterval`,
  `StartLimitBurst`, `RestartPreventExitStatus`, `SuccessExitStatus`, `UnsetEnvironment`,
  `KillSignal`, `KillMode`, `OnFailure`, `OnSuccess`, `RestartForceExitStatus`, `TimeoutStopSec`,
  `FinalKillSignal`); the back-off pinned; the timer's `Unit=` and `AccuracySec` pinned; xtrace
  refused anywhere in the script including heredoc bodies; pull/login matching folds `/usr/bin/docker`,
  `"docker"` and backslash continuations and counts `docker run|create "$ZIREF"` as a pull; the
  `timeout 180` literal pinned; exactly one `inngest-bootstrap.sh` invocation, in the script;
  `bootcmd:` scanned; unit starts counted without the suffix and via `add-wants`; the latch census
  covers `tee`, `N>`, `2>`, `exec N>`, `mkdir`, `dd of=` and `"$STATE"/done`; heredoc detection
  ignores `<<` in comments and `$(( ))`; the three iid derivations must be byte-identical; both
  charset guards present.
- Tier A: the latch invariant after every scenario; new scenarios TN (NIC absent), TD1/TD2
  (degraded), TD3 (diagnostic exempt), Q1–Q4 (each busy signal: fsm-busy, exit 1, no bootstrap,
  the flip timer restarted), Q5 (the not-busy shapes), and T4 now proves the LUKS timer restart;
  T7 proves the report precedes the bounded cleanup. Control row: 94 → **160** assertions.
- Rows: 59 → **83** (74 RED + 9 must-PASS). New IDs: G1-r9..r13, G2-r12..r16, G3-r9..r13,
  G5-r7, G5-r8, G6-r11..r16, G8-r6 (must-PASS: `<<` in a comment and in arithmetic).
- Tier B: `ip`/NIC-wait stubs, an enabled `inngest-redis.service` stand-in, the fake bootstrap
  writes a durable-shaped server unit, and a `RestartSteps=0` drop-in. An unbootable container is
  now a FAIL under CI (still a named skip locally); the ADR-188 apt `arm_skip` is unchanged.
- Code quality: every verdict-bearing `producer | grep -q` / `| awk … exit` became
  capture-then-match or a herestring; `SRC`, `nfail` (nothing counted into it — the fault
  counter is `nfault`) and the unused loop variables were removed; the dead
  `static_out | grep -q … && return 1; return 1` pair was removed.

### Mutation re-check (source template, sandbox copies; green control first)

| Mutation | Result | Row(s) that also pin it |
|---|---|---|
| control (unmutated) | GREEN (C0 160/160) | — |
| (a) `[ "$rc" -eq 124 ] && : \| tee "$LATCH"` in `on_exit` | RED: G3 latch write-site count; TA T8 latch-iff | G3-r9 |
| (b) latch written on a degraded success | RED: G3 write-site count; TA TD1/TD2 latch-iff | G3-r10 |
| (c) `= activating` → `= activatingX` | RED: TA Q1 (exit, busy, restart) | G2-r12 |
| (d) the provision-fsm-busy `exit 1` removed | RED: TA Q1–Q4 | G2-r13 |
| (e) luks-cutover dropped from the quiesce loop | RED: TA Q2 | G2-r14 |
| (f) a runcmd `/usr/bin/docker pull` | RED: G1 runcmd pull (found 1) | G1-r9 |
| (g) a drop-in under `soleur-inngest-provision.service.d/` | RED: G6 no drop-in | G6-r11 |
| (h) `set -x` after the refusal | RED: G6 no xtrace anywhere | G6-r12 (G6-r15: in the heredoc) |
| (i) `TimeoutSec=infinity` | RED: G6 forbidden directives | G6-r13 |
| (j) `timeout 180` → `timeout 1800` | RED: G1 `timeout 180` pin | G1-r10 |
| (k) `on_exit` restart of stopped timers removed | RED: TA T4, Q1, Q2 restart rows | G2-r15 |

Worktree template sha256 `7a39177f…734655153` before and after: IDENTICAL.

### Numbers after the review batch

- Payload: stored 19,568 B, headroom 13,200 B (was 18,396 / 14,372). The soft bracket in
  `cloud-init-user-data-size.test.ts` (20,000) still holds; no raise.
- Mint dry-run: `result=noop` (`reason=unchanged`, base `vinngest-v1.1.40`).
- Re-pointed suites: bootstrap 230/230; zot-pull battery 61/61; `inngest-host.test.sh` 83 → 85
  (STAGED list assigned once + the one copy loop); `inngest-boot-emitter.test.sh` 93 → 95 (the
  curl stub reads `-K -` stdin; two new rows: the token is not on argv, and it is on stdin).
