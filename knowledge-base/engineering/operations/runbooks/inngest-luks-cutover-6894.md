---
title: Cutting the Inngest Redis AOF store over to the encrypted volume (#6894 / ADR-142)
audience: operator
related: [6894, 7228, 7695, 8017, 8285, 8294, 8295, 8296, 9703, 9786, 9879]
---

# Inngest LUKS cutover (#6894)

**What this does.** Moves the dedicated Inngest host's Redis AOF store from the plaintext volume to
the encrypted (LUKS) one, without losing a byte and without SSH. The host freezes its writers, copies
the whole `/mnt/data` mount to the already-attached encrypted volume, proves the copy byte-identical,
swaps the mount, restarts the writers, and verifies. (Before 2026-10-09 a failed verification rolled
itself back by reverse-copying to the plaintext volume; that volume was destroyed, so on this host a failed
post-swap verification is an incident with no automatic rollback — see §5a.)

**One dispatch, nothing else.** There is no SSH step in this document and there is no manual
Doppler write. If you find yourself wanting one, the answer is in §6.

| | |
| --- | --- |
| Forward | `gh workflow run cutover-inngest.yml -f op=luks-cutover` |
| Back | none. `op=luks-rollback` was retired by #8285 PR B (§5a): the plaintext volume it copied back to was destroyed on 2026-10-09. |

The forward dispatch holds in **Waiting** until a reviewer approves the `inngest-cutover` environment. That approval
is the prod-write ack; the token that can write the flag is injected only for the ops that need it.

> **The cutover this document describes has run (2026-09-20) and its rollback route is gone (2026-10-09).** Sections 1-4
> are kept because the forward verb still exists; §5a says what replaced the rollback and §5b is the record of how the
> plaintext backstop was retired. Where an older sentence below says "roll back", read §5a first.

---

## 1. Before you dispatch (all four are read-only)

1. **The trio is installed and polling.** Its rows are the host's only voice:

   ```
   doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh \
     --since 30m --grep inngest-luks-cutover --limit 20
   ```

   Expect `noop-unset` rows roughly every 300s (the LUKS FSM's `emit_noop` throttles the terminal
   heartbeat; an older copy said 30s, from before that throttle landed). **Zero rows is a finding, not a quiet host** — either
   the host is dark or the cutover trio never installed (`inngest-bootstrap.sh` emits
   `reason=install_missing` on that path). The dispatch refuses on this condition anyway (G3), before
   writing anything. G3 counts only rows from the **current** `soleur-inngest` server (stamped and
   ingested after its Hetzner `created` time), so it also refuses while the Hetzner API or the HCLOUD
   token is unavailable — see `inngest-server.md` §op=resume "G3 is a live precondition" for the
   notice fields and the warning classes.

   Read the liveness from these ROWS, never from `systemctl is-active inngest-luks-cutover.service`:
   a oneshot's healthy steady state is `inactive`, so that reading answers a different question.

2. **The store is where you think it is.**

   ```
   doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh \
     --since 3h --grep SOLEUR_INNGEST_SERVER_PROBE --limit 200 \
     | jq -R -r 'fromjson? | .raw? | fromjson? | select(type == "object")
         | select(.host == "soleur-inngest" and .SYSLOG_IDENTIFIER == "inngest-server-probe")
         | .message | select(type == "string" and startswith("SOLEUR_INNGEST_SERVER_PROBE "))'
   ```

   Read only rows the probe itself emitted (`SYSLOG_IDENTIFIER=inngest-server-probe`). The inngest
   event log on the same host (`SYSLOG_IDENTIFIER=doppler`) quotes probe lines from GitHub issues about
   this work, and a quoted line can be the newest row the `--grep` returns (#8846).

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
| `rolled-back` | HISTORICAL (pre-2026-10-09 layout): the post-swap verification failed; the host reverse-copied and cleared the pointer. The plaintext volume no longer exists, so a fresh `rolled-back` row on this host is an incident (the on-host rollback refuses with `rollback-no-backstop`) | Not on a plaintext volume | Follow §5a; read `reason=` first |
| `aborted` | A guard refused. Before the swap, writers were resumed BEFORE the flag landed. With the pointer PRESENT it is a post-swap failure whose rollback refused (`rollback-no-backstop`): the swap stayed landed | Before the swap: wherever it was before you dispatched. With the pointer present: the **encrypted volume** | Read `reason=`; with the pointer present follow §5a, otherwise see below |
| `copied` (persisting) | The swap LANDED but its bookkeeping (envfile, fstab, durable pointer) did not finish — a SIGTERM, a Doppler failure on the pointer write, or a refusal inside it. NOT terminal: every 30s tick re-drives the bookkeeping (`reason=repair-forward`) | **Encrypted volume**, serving | Nothing, if the next row is `done`. If `copied` persists across ticks, read the refusal `reason=` beside it — that is the bookkeeping step that keeps failing |
| `aborted` with the pointer PRESENT | HISTORICAL: a ROLLBACK was interrupted (its `reason=` named the step: `rollback-no-backstop`, `t2-*`, `rollback-mapper-still-open`). The verb is retired (§5a), so a fresh row of this shape is an incident, not a rollback | **Encrypted volume**, serving | Do not look for a rollback dispatch: there is none. Read §5a, then §6 |

Refusal reasons, and what each one is telling you:

| `reason=` | Meaning |
| --- | --- |
| `luks-key-absent` / `redis-password-absent` / `volume-ids-unreadable` | The unit's own inputs did not arrive — a Doppler name is missing, or the first-boot stage did not write `/etc/default/inngest-luks-volumes`. Nothing was stopped. |
| `pointer-already-set` | This host is already past the cutover. There is no verb to go back (§5a); nothing to do. |
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

*[2026-09-27, #6939:]* before re-firing a **cron** tick from that window, follow
`inngest-server.md` § Bounded-outage note. "No backfill" is not safe to assume for crons: ADR-100's
2026-09-19 addendum measured the scheduler firing each missed tick once on resume, and re-firing a
drained tick double-fires the cron. That procedure's `routine_runs` check tells the two apart.

---

## 5. Close-out after `done`

1. **Confirm from the host's own telemetry**, not from the dispatch's exit code:

   ```
   doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh \
     --since 2h --grep SOLEUR_INNGEST_SERVER_PROBE --limit 200 \
     | jq -R -r 'fromjson? | .raw? | fromjson? | select(type == "object")
         | select(.host == "soleur-inngest" and .SYSLOG_IDENTIFIER == "inngest-server-probe")
         | .message | select(type == "string" and startswith("SOLEUR_INNGEST_SERVER_PROBE "))'
   ```

   Read only rows the probe itself emitted (`SYSLOG_IDENTIFIER=inngest-server-probe`). The inngest
   event log on the same host (`SYSLOG_IDENTIFIER=doppler`) quotes probe lines from GitHub issues about
   this work, and a quoted line can be the newest row the `--grep` returns (#8846).

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
   `soleur/prd_terraform` silently wins over the declared default. (**#8209 / ADR-241:** that path
   is the PRE-cutover one. After the Tier-B cutover the loader is nested — an outer
   `soleur-infra-privileged` pass and an inner `prd_terraform` pass carrying `--preserve-env`, so
   the outer values win and a `prd_terraform` override no longer reaches a privileged run. Canonical
   form: [`infra-credential-tiers-8209.md`](./infra-credential-tiers-8209.md) §Local Terraform
   invocation.) Do not set one to arm. If one is
   set to `false` — for a sanctioned re-pause during a rollback to the plaintext backstop (retired, §5a) — the
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

   **Superseded 2026-09-21 (#8296), appended rather than edited:** the ledger flip has landed, and
   the sentence above about #8294/#8295 is historical. Neither closed through the sweeper: both were
   closed explicitly, and both follow-through directives were retired on 2026-09-21 (#8294's probe is
   deleted as obsolete; #8295's would have falsely reopened it once its 48h window passed the
   cutover). #8296 is closed explicitly (`gh issue close 8296`) once PR-2 has merged and its
   post-merge steps are read back, never by a sweeper. The one open step is now #8285: destroy
   `hcloud_volume.inngest_redis` by 2026-10-22.
   - #8285 is enrolled, as a post-merge step of #8296 PR-2, with the `follow-through` label and the
     directive for `scripts/followthroughs/inngest-luks-property-8296.sh`. The probe is NOTIFY-ONLY:
     it never exits 0 or 1, so the sweeper never closes that tracker. It comments on #8285 every
     day. The heading reads "NOT YET" when the ledger claim and the device agree (the body says
     "healthy: nothing to do"), and "ACTION REQUIRED" when they do not. **Do not close #8285 before
     the backstop is destroyed**: on a closed issue the sweeper does nothing with 2, 3 or 5, so
     closing it turns the probe off.
   - **Retiring the probe** happens only AFTER the destroy apply has run and the Hetzner API shows
     the volume gone, never in the PR that merely removes it from Terraform. That PR's body carries
     no closing keyword next to #8285; #8285 is closed explicitly after the check. The probe
     header's RETIREMENT line lists what to delete.
   - A silent probe pipeline reads as healthy to the wrong-volume alert (`treat_as_zero`). The
     property probe reports that as "CANNOT ESTABLISH". The dead-probe heartbeat resource landed in
     cde96fb5e2 (#8516, closed), but its feeder is not wired or armed (#9703, open), so a silent probe
     still reads as healthy to the alert today. Do not retire the property probe before #9703 is armed
     (§5b, "Records the convergence PR must carry").
   - **After a sanctioned `op=luks-rollback`**, see §5a.
   - **Superseded 2026-10-09 (#8285 PR B), appended rather than edited:** the backstop was destroyed (§5b), so the
     bullets above about #8285 describe the state before that. The probe stays until the dead-probe feeder (#9703)
     is armed; its daily comment moves to #9703 when #8285 is closed, and `op=luks-rollback` no longer exists.

---

## 5a. `op=luks-rollback` is retired: what to do instead

`op=luks-rollback` (a Doppler write of `INNGEST_LUKS_CUTOVER=rollback`, then an on-host reverse copy onto the plaintext
volume) was removed from `cutover-inngest.yml` and `cutover-inngest.sh` by #8285 PR B. The plaintext volume
`hcloud_volume.inngest_redis` (Hetzner id 106261946) was wiped and destroyed on 2026-10-09 (§5b), so a reverse
copy has nowhere to land. The dated history of the verb stays in ADR-142.

**The live LUKS volume `hcloud_volume.inngest_redis_luks` (id 106903269) is now the only copy of the Inngest queue and run
state, and `INNGEST_REDIS_LUKS_KEY` in Doppler `soleur-inngest/prd` is its sole opener.** Losing either is data loss
with no second copy to restore from. Protection for that (delete protection, edge pins, key-loss posture) is tracked
in #9879; do not assume it exists.

**Signals that used to mean "the store went back to plaintext" are now incidents, not rollbacks.** The wrong-volume
alert (`logtail_exploration_alert.inngest_luks_wrong_volume`), a probe row whose `data_mount_src` is not
`/dev/mapper/inngest-redis`, and the property probe's `rollback_inversion` verdict all mean the store is on a device
the ledger does not claim. Nothing here can put it back on a plaintext volume. Treat each as a production incident
(`soleur:incident`): read the newest `host_role=dedicated` `SOLEUR_INNGEST_SERVER_PROBE` row first (§5 step 1's query).

**Signal -> route.** Read the newest `host_role=dedicated` probe row first, then pick the route; the host-replace route is a
production write and needs the operator's per-command go-ahead:

| Signal | What it means now | Route |
| --- | --- | --- |
| Host dark / probe silent, volume intact (first read `GET /v1/servers/<id>` with the read-only token, §5b read-backs: the LUKS volume must still be attached, else stop and escalate) | Host or shipper failure, store not implicated | `gh workflow run apply-web-platform-infra.yml -f apply_target=inngest-host-replace -f reason="<why>"` (keeps the LUKS volume by omission), then `gh workflow run cutover-inngest.yml -f op=resume` (#7228) |
| `data_mount_src` is not `/dev/mapper/inngest-redis`, or the wrong-volume alert fires | The store is on a device the ledger does not claim | Incident (`soleur:incident`); do NOT replace the host until the probe row says which device is mounted |
| `rollback_inversion` verdict from the property probe | The ledger claims LUKS but the measured store is not on `/dev/mapper/inngest-redis` | Incident; the verdict text names this section |
| `op=luks-cutover` dispatched again | Refused on this host: the durable pointer is set and the flag is `done` (G1/G2) | Nothing to do |

The probe's other verdicts are about the ledger or the probe pipeline, not about where the store is: `under_claim` is a
ledger-only edit, `backstop_expired` cannot fire once the backstop row is gone, and `no_rows` / `producer_silent` /
`row_unusable` / `ledger_unreadable` (exit 3) mean the probe pipeline went silent or unreadable (see the #9703 note under
"Rules that stay in force"): that reads as "cannot establish", never as healthy.

**Recovery routes that exist:** the host-replace route is the first row of the table above (note #7228: **every**
replace strands the scheduler, whose one-dispatch recovery is `gh workflow run cutover-inngest.yml -f op=resume`).

- A volume that will not open: the key is in Doppler `soleur-inngest/prd` (`INNGEST_REDIS_LUKS_KEY`). There is no SSH
  route and no second copy; stop and escalate rather than improvise.

**What 5a used to do and why it is gone.** It reverted the ledger row `hcloud_volume.inngest_redis_luks` to
`plaintext-exception`, answered the three `[2026-09-21 AMENDMENT (#8296)` cells of the Article 30 register, re-paused the
wrong-volume alert and amended the C4 model and ADR-142. All of that assumed a plaintext volume to revert to. With the
volume destroyed there is no plaintext exception to record, so none of those steps applies. This heading is kept
(`op=luks-rollback` in the title) because the property probe's `ACTION REQUIRED` text still points readers at 5a.

---

## 5b. Retiring the backstop (#8285): record of what was done

**Status: complete on 2026-10-09.** The plaintext backstop `hcloud_volume.inngest_redis` (Hetzner id **106261946**, ext4,
hel1, 10 GiB) was detached, zeroed and read back, and deleted. Hetzner answered `GET /v1/volumes/106261946 -> 404` at
2026-10-09T16:21:26Z. The dispatch that did it (`apply_target=inngest-backstop-retire`, a four-phase job, dispatched three times, each phase reviewer-gated) and
its gate library were deleted by #8285 PR B; the code is in git history at d7dee46bb0 (PR #9784). Ref #8285, Ref #6894.
The live store on `hcloud_volume.inngest_redis_luks` (id **106903269**) was never touched.

| Phase | Run | Result |
| --- | --- | --- |
| `detach` | <https://github.com/jikig-ai/soleur/actions/runs/37950928039> | success; volume 106261946 `server: null` |
| `wipe` | <https://github.com/jikig-ai/soleur/actions/runs/37955244979> | success; evidence row `result=wiped readback=zero sig_after=none`, then the throwaway server and attachment torn down in the same dispatch |
| `destroy` | <https://github.com/jikig-ai/soleur/actions/runs/37958051426> | success; `Apply complete! 0 added, 0 changed, 1 destroyed`; `server volumes == [106903269]` |

The evidence, how it was graded, its limits and the attestation are in `knowledge-base/legal/audits/inngest-aof-backstop-destruction-record.md`.
**The erasure is logical, guest-side and self-attested**: Hetzner records that a non-live server held the volume between an
attach and a detach, and the host reported the zero and read-back; nothing independent corroborates that the overwrite
happened, and no claim of physical or secure erasure is made.

### Read-backs after `destroy` (read-only; re-runnable)

```
doppler run -p soleur -c prd_terraform -- sh -c ': "${HCLOUD_TOKEN_READONLY:?absent from prd_terraform: stop, never fall back to HCLOUD_TOKEN}"; curl -sS -o /dev/null -w "%{http_code}\n" -H "Authorization: Bearer $HCLOUD_TOKEN_READONLY" https://api.hetzner.cloud/v1/volumes/106261946'
```

Expect `404`. The same token form reads `GET /v1/servers/169426216` (`.server.volumes` is `[106903269]`). The next
`host_role=dedicated` probe row still reports `scsi-0HC_Volume_106903269` with `redis_active=active`.

### Rules that stay in force

- After retirement the live LUKS volume is the only copy of the store and `INNGEST_REDIS_LUKS_KEY` in Doppler
  `soleur-inngest/prd` is its sole opener (ADR-142 addendum 2026-10-08; protection tracked in #9879).
- **Do not delete `scripts/followthroughs/inngest-luks-property-8296.sh` until the dead-probe heartbeat feeder (#9703) is
  armed.** That script is the only reporter that says "CANNOT ESTABLISH" for a silent probe pipeline; the wrong-volume
  alert reads a silent probe as healthy until the feeder is wired. Its deletion sites are the probe, its test, the
  `run_suite` line in `scripts/test-all.sh`, two `*.tsv` rows, the `test-affected-kb-consumers.baseline.txt` rows and the
  5a pointer; the list is posted on #9703 when #8285 is closed.
- The dead on-host `rollback)` arm in `inngest-luks-cutover.sh`, its FSM comments and fixtures, and the dead
  plaintext-resolver arm in `cloud-init-inngest.yml` leave at the next planned Inngest host replace (#9786).

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
- **Rolling back later, on purpose.** There is no rollback: `op=luks-rollback` was retired by #8285 PR B and the
  plaintext volume it would have copied back to was destroyed on 2026-10-09 (§5a, §5b).

---

## Related

- ADR-142 (+ its 2026-09-18 amendment) — why additive, why a pointer, why a separate flag.
- ADR-199 — the empty-store world, where the destructive recut is lawful instead.
- `knowledge-base/engineering/operations/runbooks/inngest-server.md` — the host itself.
- `betterstack-log-query.md` — the standing alarms over this source, including the wrong-volume alert.
