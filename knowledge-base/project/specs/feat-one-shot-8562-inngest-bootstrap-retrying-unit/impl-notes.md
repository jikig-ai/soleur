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

Bounded steps, from the steps' own bounds (not healthy history):

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
