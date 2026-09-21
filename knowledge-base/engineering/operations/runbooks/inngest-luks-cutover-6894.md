---
title: Cutting the Inngest Redis AOF store over to the encrypted volume (#6894 / ADR-142)
audience: operator
related: [6894, 7228, 7695, 8017, 8285, 8294, 8295, 8296]
---

# Inngest LUKS cutover (#6894)

**What this does.** Moves the dedicated Inngest host's Redis AOF store from the plaintext volume to
the encrypted (LUKS) one, without losing a byte and without SSH. The host freezes its writers, copies
the whole `/mnt/data` mount to the already-attached encrypted volume, proves the copy byte-identical,
swaps the mount, restarts the writers, and verifies. If the verification fails it rolls itself back —
reverse-copying first, so nothing written after the swap is lost.

**Two dispatches, nothing else.** There is no SSH step in this document and there is no manual
Doppler write. If you find yourself wanting one, the answer is in §6.

| | |
| --- | --- |
| Forward | `gh workflow run cutover-inngest.yml -f op=luks-cutover` |
| Back | `gh workflow run cutover-inngest.yml -f op=luks-rollback` |

Both hold in **Waiting** until a reviewer approves the `inngest-cutover` environment. That approval
is the prod-write ack; the token that can write the flag is injected only for these ops.

---

## 1. Before you dispatch (all four are read-only)

1. **The trio is installed and polling.** Its rows are the host's only voice:

   ```
   doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh \
     --since 30m --grep inngest-luks-cutover --limit 20
   ```

   Expect `noop-unset` rows roughly every 30s. **Zero rows is a finding, not a quiet host** — either
   the host is dark or the cutover trio never installed (`inngest-bootstrap.sh` emits
   `reason=install_missing` on that path). The dispatch refuses on this condition anyway (G3), before
   writing anything.

   Read the liveness from these ROWS, never from `systemctl is-active inngest-luks-cutover.service`:
   a oneshot's healthy steady state is `inactive`, so that reading answers a different question.

2. **The store is where you think it is.**

   ```
   doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh \
     --since 3h --grep SOLEUR_INNGEST_SERVER_PROBE --limit 20
   ```

   On the newest `host_role=dedicated` row: `data_mount_devid` is the PLAINTEXT volume's
   `scsi-0HC_Volume_<id>` alias, `redis_active=active`, and `redis_keys` is a number (not
   `__UNREADABLE__`). An unreadable count is not a zero — the FSM refuses on it (`t1-unreadable`).

3. **Note the key count.** The FSM records it (`k_freeze`) and T3 checks the store after the swap
   against it. You want it in your own notes too, for §5.

4. **Pick a window.** Writers are frozen for the copy. Sizing it from the last measurement: the store
   is small (hundreds of keys), so the freeze is seconds, not minutes — but the unit is bounded at
   `TimeoutStartSec=600` and the post-swap verification window is 120s. Plan for a few minutes, and
   see §4 for what a frozen window costs.

---

## 2. Dispatch, then watch the FSM

```
gh workflow run cutover-inngest.yml -f op=luks-cutover
```

Approve the environment gate when it appears. The job then: refuses or writes
`INNGEST_LUKS_CUTOVER=armed`, and polls Better Stack for a terminal flag for up to 900s. You do not
need to watch anything else — but if you want the host's own view:

```
doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh \
  --since 20m --grep inngest-luks-cutover --limit 50
```

The flag walks `copying → copied → swapped → done`, and the FSM emits a row at each transition
(`reason=phase-frozen`, `phase-copy-start`, `phase-copy-verified`, `phase-swapped`, then
`cutover-complete`). Each row carries `reason`, `phase`, `k_freeze` and `e_freeze`.

**The dispatch is green only on `done`.** `rolled-back` and `aborted` both exit non-zero and both
name the reason field to read.

---

## 3. What each terminal state means

| Flag | What happened | Where the store is | What to do |
| --- | --- | --- | --- |
| `done` | Cutover complete, verified after the swap | **Encrypted volume** | §5 close-out |
| `rolled-back` | The post-swap verification failed; the host reverse-copied and cleared the pointer | **Plaintext volume**, intact | Read `reason=t3-failed-rc*`; fix the cause; re-dispatch |
| `aborted` | A guard refused. Writers were resumed BEFORE the flag landed | Wherever it was before you dispatched | Read `reason=`; see below |
| `copied` (persisting) | The swap LANDED but its bookkeeping (envfile, fstab, durable pointer) did not finish — a SIGTERM, a Doppler failure on the pointer write, or a refusal inside it. NOT terminal: every 30s tick re-drives the bookkeeping (`reason=repair-forward`) | **Encrypted volume**, serving | Nothing, if the next row is `done`. If `copied` persists across ticks, read the refusal `reason=` beside it — that is the bookkeeping step that keeps failing |
| `aborted` with the pointer PRESENT | A ROLLBACK was interrupted (its `reason=` names the step: `rollback-no-backstop`, `t2-*`, `rollback-mapper-still-open`). The FSM does not re-drive a rollback by itself | **Encrypted volume**, serving | Fix the named condition (re-attach the backstop, …) and re-dispatch `op=luks-rollback` — G1 admits `aborted` when G2 finds the pointer present |

Refusal reasons, and what each one is telling you:

| `reason=` | Meaning |
| --- | --- |
| `luks-key-absent` / `redis-password-absent` / `volume-ids-unreadable` | The unit's own inputs did not arrive — a Doppler name is missing, or the first-boot stage did not write `/etc/default/inngest-luks-volumes`. Nothing was stopped. |
| `pointer-already-set` | This host is already past the cutover. Use `op=luks-rollback` if you meant to go back. |
| `canonical-not-plaintext` / `staging-not-mapper` / `staging-wrong-backing` / `canonical-mapper-open` | The pre-cutover topology is not what the FSM requires. The host is not in the state this dispatch acts on; read the probe row before doing anything. |
| `envfile-key-absent` | `/etc/default/inngest-luks` carries no passphrase, so the boot-reopen unit could not open the store on the next boot. Refused before anything stopped. |
| `t1-unreadable` | Redis could not be read before the freeze. Refused rather than treating "could not measure" as an empty store. |
| `mount-not-quiesced` | A process still holds a file under `/mnt/data` after the freeze. Something writes there that the freeze set does not name — that is a finding worth a line in the freeze set's comment. |
| `t2-listing-differs` / `t2-checksums-differ` / `t2-bytes-differ` / `t2-flip-latch-missing` / `t2-aof-structure` / `t2-unit-active` | The copy is not byte-identical, or a writer came back during the copy window. **Hard abort by design.** The plaintext store is untouched and serving. |
| `copy-dst-*` | The copy refused its own destination (not a mount, same as the source, empty or relative). A bug, not an operational condition — file it. |
| `swap-mount-source` / `swap-wrong-backing` | The swap did not produce the mount it intended; the plaintext store was put back and the writers resumed. |
| `unexpected-exit(...)` / `terminated` | The script died or was killed (a `TimeoutStartSec` kill emits `terminated`). Writers were resumed on the way out. |
| `flip-in-flight` | The flip FSM (`inngest-cutover-flip.service`) is mid-run. It owns the one authorized `FLUSHALL` and restarts the server, so the two must not overlap. Wait for its terminal row, then re-dispatch. |
| `unit-exit` with `service_result=timeout` | systemd killed the unit outright — the script never got to report. The store is wherever the last `phase-*` row says; read those before re-dispatching. |
| `not-root` | Emitted, but NOT through the abort path: the flag is left untouched, so the timer keeps polling. Unreachable under systemd (the unit runs as root). |

---

## 4. The freeze window costs scheduled ticks — close it out

**This is mandatory, not optional.** Inngest is stopped for the copy, and ticks due during that
window are **not backfilled** when it comes back. The window is short, but "short" is not "none", and
a cron that did not fire is invisible unless someone enumerates it.

**The two obvious verbs do not answer this on this host, and it is worth knowing why before you
reach for them.** `op=enumerate` posts to `/hooks/inngest-enumerate-reminders`, and that hook's
handler queries `127.0.0.1:8288` on **whichever host serves the webhook** — which is web-1, because
the dedicated host runs no listener (the measurement ADR-225 and `inngest-server.md` both record).
It would read the wrong machine. `op=verify` anchors its window on the **flip** FSM's transition row
and detects double-fires, which is not what a freeze produces.

So take the window from the LUKS FSM's own rows and re-arm directly:

```
doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh \\
  --since 6h --grep inngest-luks-cutover --limit 200
```

The `phase-frozen` row is the freeze start and the `phase-swapped` row is the resume (the `done` row
is up to 120s later, after T3). Anything due inside that window is re-armed the way it was armed —
there is no backfill, and no dispatch that can synthesise one.

---

## 5. Close-out after `done`

1. **Confirm from the host's own telemetry**, not from the dispatch's exit code:

   ```
   doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh \
     --since 2h --grep SOLEUR_INNGEST_SERVER_PROBE --limit 20
   ```

   On the newest `host_role=dedicated` row, `data_mount_devid` must now be the **encrypted** volume's
   alias, `redis_active=active`, and `redis_keys` at least `k_freeze − e_freeze` (volatile keys may have
   expired; nothing else should have gone).

2. **Arm the wrong-volume alert.** It SHIPPED paused, because before the cutover the plaintext alias
   was the correct value and an armed rule would have paged continuously.

   **CORRECTED 2026-09-20 (#8296).** This step used to prescribe a Doppler write
   (`doppler secrets set INNGEST_LUKS_CUTOVER_COMPLETE … true`) followed by
   `gh workflow run apply-web-platform-infra.yml -f apply_target=main`. Both halves were wrong:
   `main` is not a value the workflow's `apply_target` choice accepts (the dispatch is refused), and
   the arming route is now the DECLARED DEFAULT — `var.inngest_luks_cutover_complete` defaults to
   `true` in `apps/web-platform/infra/variables.tf` since #8296, and the merge of that change is the
   apply that arms it (the two alert resources are in the push-triggered plan's `-target=`
   allowlist, and `variables.tf` is under the workflow's `paths:` trigger).

   **The Doppler secret is therefore an OVERRIDE, not the switch.** There is still no tfvars file in
   this root and no `-var-file` in any workflow; every variable reaches terraform through
   `doppler run --name-transformer tf-var`, so a secret named `INNGEST_LUKS_CUTOVER_COMPLETE` in
   `soleur/prd_terraform` silently wins over the declared default. Do not set one to arm. If one is
   set to `false` — for a sanctioned re-pause during a rollback to the plaintext backstop — the
   drift reconciler will report `logs-alert-paused` twice daily BY DESIGN (it resolves the declared
   default and cannot see the override); that report is the only record the override leaves.
   Re-read it before concluding anything from a plan:

   ```
   doppler secrets get INNGEST_LUKS_CUTOVER_COMPLETE -p soleur -c prd_terraform --plain
   ```

   If the merge apply halted on unrelated drift, re-run it as the ordinary manual rerun with a
   `reason` (that input is required):

   ```
   gh workflow run apply-web-platform-infra.yml -f apply_target=manual-rerun -f reason='arm inngest_luks_wrong_volume after #8296'
   ```

   The two alert resources are already in that plan's `-target=` allowlist. From then on, any probe
   row reporting `/mnt/data` on a volume that is not the encrypted one pages — that is the detector
   for "the store quietly went back to plaintext".

3. **Do the §4 close-out** if you have not already.

4. **Close out the trackers.** #8294 (staging observed) and #8295 (cutover measured) close
   themselves through the daily sweeper once their probes pass — check that they did, rather than
   assuming. #8296 (the encryption-posture ledger flip) is a human decision and does not close
   itself. #8285 is the backstop volume's retirement, expiring 2026-10-22.

---

## 6. If something looks stuck

- **The flag is a non-terminal value and nothing is moving.** The unit holds a `flock` and resumes
  from its own state on the next 30s tick. Do not re-dispatch blind: `op=luks-cutover` refuses an
  in-flight flag precisely so a second write cannot race the FSM. Read the rows first.
- **No rows at all.** The host is dark or the trio never installed. Neither is fixed by writing the
  flag — the write would park it in a state the next dispatch refuses. The route is
  `apply_target=inngest-host-replace` (and note #7228: **every** replace strands the scheduler, whose
  one-dispatch recovery is `gh workflow run cutover-inngest.yml -f op=resume`).
- **You want to "just look at the host".** There is no SSH on this host by design
  (`hr-no-ssh-fallback-in-runbooks`). Everything the FSM knows, it emits: flag, phase, reason,
  `k_freeze`, `e_freeze`. If a state you needed is not in a row, that is a gap to fix in the emitter,
  not a reason to open a shell.
- **Rolling back later, on purpose.** `op=luks-rollback` works while the pointer is set and the flag
  is `done`. It reverse-copies first, so writes taken since the cutover come back with it. It refuses
  if the pointer is absent (nothing to roll back) or the flag is anything else.

---

## Related

- ADR-142 (+ its 2026-09-18 amendment) — why additive, why a pointer, why a separate flag.
- ADR-199 — the empty-store world, where the destructive recut is lawful instead.
- `knowledge-base/engineering/operations/runbooks/inngest-server.md` — the host itself.
- `betterstack-log-query.md` — the standing alarms over this source, including the wrong-volume alert.
