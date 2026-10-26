---
title: Cutting the Inngest Redis AOF store over to the encrypted volume (#6894 / ADR-142)
audience: operator
related: [6894, 7228, 7695, 8017, 8285, 8294, 8295, 8296, 9703, 9786, 9879, 9927]
---

# Inngest LUKS cutover (#6894)

> **Cutover dispatch retired 2026-10-25 (#10112).** The on-host cutover trio (`inngest-luks-cutover.{sh,service,timer}`) is no longer baked into
> the image, shipped in the signed config-refresh bundle, or pushed to the web hosts, and the dispatcher refuses `op=luks-cutover` (G1/G2/G3).
> Sections 1-5b are the record of how the cutover ran (2026-09-20); do not follow their dispatch steps. **Section 5c (sole-copy
> protection, key loss, total loss, deliberate unprotect, break-glass and revert) stays in force** and is still the operator procedure those alerts point at. Section 6 below is FSM-dispatch troubleshooting; read it as history. A host provisioned before this
> change still has the trio installed and its timer enabled until the next host replace; the dispatcher stays inert only while the flag is `done`
> and the pointer is set. The dispatcher's `op=luks-cutover` arm and refusal text are retired in a tracked follow-up.

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
| `luks-key-absent` / `redis-password-absent` / `volume-ids-unreadable` | The unit's own inputs did not arrive — a Doppler name is missing, or the first-boot stage did not write `/etc/default/inngest-luks-volumes` (as of #11080 the stage never writes that file on a host born from the current template, so on such a host this is the expected answer). Nothing was stopped. **After the host replace that carries #9786 this is the EXPECTED answer to any flagged run** (flag `armed`/`copying`/`copied`/`swapped`/`rollback`): the stage no longer writes the plaintext id the image-baked script reads, the cutover is complete, and at flag `done` the unit is a no-op. Such a refusal writes the terminal flag `aborted`, so do not dispatch a flagged run on a host in that state. |
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
   - **Retired 2026-10-12 (#9703 Stage 3b); the backstop was destroyed 2026-10-09 (#8285 PR B, §5b) and `op=luks-rollback` no longer exists:** the #8285 follow-through probe for
     the ledger-vs-device claim (the `inngest-luks-property-8296` script, its test and every registration) is
     deleted, and its directive was removed from #9703 (and the closed #8285) that day. A silent probe pipeline reads
     as healthy to the wrong-volume alert (`treat_as_zero`); `betteruptime_heartbeat.inngest_server_probe` (armed
     2026-10-12, #9703, arm record in `inngest-server.md` section "Arming the probe heartbeat (#9703)") now carries that
     case, with the twice-daily (06:00 and 18:00 UTC) `heartbeat-live-reconcile` `fed-but-paused` check as the net.
     **What was lost:** the probe's daily cross-read of the ledger claim against the probe row's `data_mount_src`
     (the `/dev/mapper/inngest-redis` mapper path). The wrong-volume alert keys on `data_mount_devid` only, so a
     right volume remounted without the dm-crypt mapper is no longer reported by anything automated. It never
     verified the LUKS cipher either (the ledger's `live_verification` stays `unavailable:`).
   - **After a sanctioned `op=luks-rollback`**, see §5a.

---

## 5a. `op=luks-rollback` is retired: what to do instead

`op=luks-rollback` (a Doppler write of `INNGEST_LUKS_CUTOVER=rollback`, then an on-host reverse copy onto the plaintext
volume) was removed from `cutover-inngest.yml` and `cutover-inngest.sh` by #8285 PR B. The plaintext volume
`hcloud_volume.inngest_redis` (Hetzner id 106261946) was wiped and destroyed on 2026-10-09 (§5b), so a reverse
copy has nowhere to land. The dated history of the verb stays in ADR-142.

**The live LUKS volume `hcloud_volume.inngest_redis_luks` (id 106903269) is now the only copy of the Inngest queue and run
state, and `INNGEST_REDIS_LUKS_KEY` in Doppler `soleur-inngest/prd` is the only opener the host reads; an independent
copy of the passphrase exists in Terraform state.** Losing the volume, or both copies of the passphrase, is data loss with
nothing to restore from. Protection for that (delete protection, edge pins, key-loss posture) was built by
#9879 (PR #9925, ADR-282, accepted 2026-10-15) and is described in §5c. It is a point-in-time flag that a holder of the
read/write Hetzner token can lift: re-read it per §5c before relying on it.

**Signals that used to mean "the store went back to plaintext" are now incidents, not rollbacks.** The wrong-volume
alert (`logtail_exploration_alert.inngest_luks_wrong_volume`), a probe row whose `data_mount_src` is not
`/dev/mapper/inngest-redis` all mean the store is on a device the ledger does not claim. Nothing here can put it back on a plaintext volume. Treat each as a production incident
(`soleur:incident`): read the newest `host_role=dedicated` `SOLEUR_INNGEST_SERVER_PROBE` row first (§5 step 1's query).

**Signal -> route.** Read the newest `host_role=dedicated` probe row first, then pick the route; the host-replace route is a
production write and needs the operator's per-command go-ahead:

| Signal | What it means now | Route |
| --- | --- | --- |
| Host dark / probe silent, volume intact (first read `GET /v1/servers/<id>` with the read-only token, §5b read-backs: the LUKS volume must still be attached, else stop and escalate) | Host or shipper failure, store not implicated | `gh workflow run apply-web-platform-infra.yml -f apply_target=inngest-host-replace -f reason="<why>"` (keeps the LUKS volume by omission), then `gh workflow run cutover-inngest.yml -f op=resume` (#7228) |
| `data_mount_src` is not `/dev/mapper/inngest-redis`, or the wrong-volume alert fires | The store is on a device the ledger does not claim | Incident (`soleur:incident`); do NOT replace the host until the probe row says which device is mounted |
| `op=luks-cutover` dispatched again | Refused on this host: the durable pointer is set and the flag is `done` (G1/G2) | Nothing to do |

**Recovery routes that exist:** the host-replace route is the first row of the table above (note #7228: **every**
replace strands the scheduler, whose one-dispatch recovery is `gh workflow run cutover-inngest.yml -f op=resume`).

- A volume that will not open: the key is in Doppler `soleur-inngest/prd` (`INNGEST_REDIS_LUKS_KEY`). There is no SSH
  route; an independent passphrase copy exists in Terraform state (§5c, Route B), otherwise stop and escalate rather than improvise.

**What 5a used to do and why it is gone.** It reverted the ledger row `hcloud_volume.inngest_redis_luks` to
`plaintext-exception`, answered the three `[2026-09-21 AMENDMENT (#8296)` cells of the Article 30 register, re-paused the
wrong-volume alert and amended the C4 model and ADR-142. All of that assumed a plaintext volume to revert to. With the
volume destroyed there is no plaintext exception to record, so none of those steps applies. This heading is kept
(`op=luks-rollback` in the title) so existing links to 5a still resolve.

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
  `soleur-inngest/prd` is the only opener the host reads; an independent copy of the passphrase exists in Terraform state
  (ADR-142 addendum 2026-10-08; protection is described in §5c and ADR-282 (accepted 2026-10-15)).
- The dead on-host `rollback)` arm in `inngest-luks-cutover.sh`, its FSM comments and fixtures, and the dead
  plaintext-resolver arm in `cloud-init-inngest.yml` leave at the next planned Inngest host replace (#9786).

---

## 5c. Sole-copy protection and key loss

**Status: accepted 2026-10-15 (#10018, ADR-282).** The read-back below returned protected on 2026-10-15 (evidence: ADR-282,
Addendum 2026-10-15). It is a point-in-time check of the delete-protection flag; re-run it after any merge that touches
`apps/web-platform/infra/inngest-redis-luks.tf` (`soleur:postmerge` Phase 5.7 does) and after a sanctioned lift (each step below
says what it expects).

**What is pinned, and what is not.** The volume, the passphrase pair and the two Doppler cascade parents carry
`prevent_destroy`; the volume also carries Hetzner delete protection. The attachment is deliberately NOT pinned, because
the sanctioned host replace replaces it. The pin set, the reasoning, the accepted residuals and the **canonical loss-mode
table (detection and recovery stance per mode)** are in
[ADR-282](../../architecture/decisions/ADR-282-sole-copy-luks-volume-protection-set.md); this section does not restate
them. Protection defends against mistaken deletes (a console click, a wrong id, a pasted recipe); it does not defend
against a holder of the read/write Hetzner token, which can lift it (until the next infra-path merge or `manual-rerun` re-protects).

### Read-back (read-only; run by `soleur:postmerge` Phase 5.7, re-runnable)

Order matters. The merge's own apply delivers the protection, so the read-back is only meaningful after that run ends.

1. **Derive the expected word from the merged HCL; never assume it.** `git fetch origin main`, then read the volume's
   `delete_protection` at the merge commit: `git show <merge-sha>:apps/web-platform/infra/inngest-redis-luks.tf` (the line
   inside `resource "hcloud_volume" "inngest_redis_luks"`). `true` expects `protected`; `false` expects `not-protected`. The
   sanctioned lift PR (break-glass step 1, deliberate unprotect step 1) expects `not-protected` and is NOT a failure. Compare
   and report a mismatch; nothing else follows from it.
2. **Find the merge run and wait for it.**
   `gh run list --workflow apply-web-platform-infra.yml --commit <merge-sha> --json databaseId,status,conclusion`.
   An empty list right after the merge is retried (every 30 seconds, up to 10 minutes), not read as "no run". Watch the run
   id under Monitor (`gh run watch <id>`; never background polling), bounded to about 65 minutes (the apply job takes up to
   53 minutes, plus queueing behind the shared concurrency group; keep the bound above that ceiling). Conclusion `success` is read back. Any other
   conclusion (`cancelled`, `timed_out`, `startup_failure`, `skipped`, `failure`) and "no run within the bound" mean **not
   delivered or superseded**: read back anyway. A merge-SHA run can be `cancelled` by the shared concurrency group when a
   later merge supersedes it and still have delivered the update; the read-back is the arbiter, not the conclusion.
3. **Run the read-back** (read-only; the token goes to curl as a config on stdin; the output is one word):

```
doppler run -p soleur -c prd_terraform --only-secrets HCLOUD_TOKEN_READONLY --no-exit-on-missing-only-secrets -- sh -c '[ -n "$HCLOUD_TOKEN_READONLY" ] || { echo missing-token; exit 3; }; r=$(printf "header = \"Authorization: Bearer %s\"\n" "$HCLOUD_TOKEN_READONLY" | curl -sS --config - -w "\n%{http_code}" https://api.hetzner.cloud/v1/volumes/106903269) || { echo read-failed; exit 2; }; case "$(printf %s "$r" | tail -n 1)" in 200) w=$(printf %s "$r" | sed "\$d" | jq -r "if .volume.protection.delete == true then \"protected\" elif .volume.protection.delete == false then \"not-protected\" else \"read-failed\" end" 2>/dev/null);; 404) w=volume-gone;; *) w=read-failed;; esac; case "$w" in protected) echo protected;; not-protected) echo not-protected; exit 1;; volume-gone) echo volume-gone; exit 4;; *) echo read-failed; exit 2;; esac'
```

4. **Route on the word** (compare with the expected word from step 1):

| Word (exit) | Meaning | Action |
| --- | --- | --- |
| `protected` (0) | delete protection is on | The pass when `protected` was expected; a mismatch when `not-protected` was expected (the lift did not land): report it. |
| `not-protected` (1) | delete protection is off | The pass for a sanctioned lift. Otherwise a red status: recommend the `manual-rerun` dispatch in "Delivery route" (owner go-ahead), never run it unprompted. |
| `volume-gone` (4) | HTTP 404 on the volume | NOT a read problem: the volume no longer exists. Incident (`soleur:incident`); follow "After a total loss". |
| `read-failed` (2) | an HTTP error other than 404 (a 401, say), a network error, a non-JSON body, or a body without the field | The read did not happen; it is not a lifted protection. Fix the read; never dispatch on its account. |
| `missing-token` (3) | `HCLOUD_TOKEN_READONLY` is absent from `prd_terraform` | Minting it is operator step **O5** in `infra-credential-tiers-8209.md` (console-minted, no API). The agent reports `missing-token` and files an issue; it does not fall back to `HCLOUD_TOKEN`. |
| no word printed | the read did not happen (`doppler` missing or unauthenticated, an error before the command ran) | Report it; never dispatch on its account. |

Any word other than the expected one is a red post-merge status.

The wrapper is single-quoted so the variable expands after Doppler sets it, not in the caller's shell. `--only-secrets`
injects only the read-only token, so the read/write `HCLOUD_TOKEN` in the same config never enters the process, and the
command stops rather than falling back to it. `--no-exit-on-missing-only-secrets` makes Doppler run the command when the
token is absent, so `missing-token` is reachable; without it Doppler exits before the command and no word is printed. This
asserts presence of the read-only token; its scope is not verified here. The token never reaches argv (a stdin curl config);
there is no `-v` and no `set -x`. A JSON string `"true"` reads as `read-failed`, not as `protected`. This read is a proxy
for "Hetzner refuses a delete"; the refusal itself is not exercised. The command was exercised against a stubbed `doppler`
and `curl` (fake token, no network) for protected, not-protected, HTTP 401, HTTP 404, network failure, non-JSON, a missing
field, a missing token, an empty token and a failing `doppler` (no word). It was then run once against the real API, on
2026-10-15, and printed `protected` (exit 0; ADR-282, Addendum 2026-10-15).

**No drift check by log search.** The scheduled drift workflow does not print its plan to the job log (the plan goes to a
file and, when drift is found, to the body or a comment of the open `infra-drift` issue, titled `infra: drift detected in
<stack>`), so a log search would pass vacuously. Drift plans surface as comments on that issue; the read-back is the arbiter. The drift workflow's `sole-copy-protection-check` job (#9927 item 9) is the recurring distinct signal: it compares the live protection flag with the Terraform declaration and files its own issue titled `infra: Inngest store volume delete protection differs from Terraform (...)` when they differ (a sanctioned lift is quiet by design; see ADR-282, Addendum 2026-10-16).

### Delivery route and ordering

- **Merge-apply first, replace second.** The per-merge apply delivers the update. Until it lands, an `inngest-host`
  or `inngest-host-replace` dispatch aborts with `reason=luks_volume_touched`: that is the intended fail-closed behaviour,
  not a defect, and it is not widened. Do not replace the host in that window; land the apply, read back, then replace.
- **If the apply was skipped, failed, cancelled or never ran**, the only delivery route is a `manual-rerun` dispatch of the
  same per-merge job. It is the ungated per-merge apply (no reviewer gate) and it applies the **whole per-merge plan**, not
  only the protection. The agent therefore reports and names the exact command, and waits for the owner's explicit
  per-command go-ahead naming it; a menu answer is not one (`hr-menu-option-ack-not-prod-write-auth`):
  `gh workflow run apply-web-platform-infra.yml --ref main -f apply_target=manual-rerun -f reason='deliver sole-copy protection'`
  (`reason` is a required input). The `inngest-host` dispatch is not a delivery route (its shape gate refuses an update on
  the volume).
- **After any dispatch**, note the newest run id before dispatching, then get the new one with
  `gh run list --workflow apply-web-platform-infra.yml --event workflow_dispatch --limit 1 --json databaseId,status`
  (an empty or unchanged id is stale: retry). Watch it under Monitor (`gh run watch <id>`), bounded to about 65 minutes (above the apply job's 53-minute ceiling),
  then run the read-back. Outcomes: `success` is read back; `cancelled`, `timed_out`, `startup_failure`, `skipped` or no
  run within the bound is **not delivered or superseded**: read back anyway, and if the read says `not-protected`,
  recommend the dispatch again (owner go-ahead).
- **If the per-merge job is wedged by another halt** (`destroy_count`, `host_creates`, the rotation HALT, an apply error),
  both host-replace gates abort and `manual-rerun` runs the same wedged job, so it does not help. The reviewed two-step
  route in "Break-glass" works only if the lift PR also removes the cause of the halt in the same change and does not
  carry `[skip-web-platform-apply]` (a skipped merge applies nothing, so step 1 would never land). If the lift PR cannot
  remove the cause, there is **no route**: the owner resolves the halt first.
- **Never an untargeted apply.** The live host's `user_data` is stale until #9786, so a full-root plan shows a pending
  server replace, and an untargeted apply would replace the server and its attachment with no gate running. Every plan and
  apply for this store is targeted and goes through CI.
- **This overrides the drift issue's generic text.** The scheduled drift filer tells a reader that intentional drift
  means applying locally to update state. For the sole-copy addresses that is wrong: never apply locally, never untargeted,
  and there is no SSH step anywhere on this path (`hr-no-ssh-fallback-in-runbooks`). A drift reason at a sole-copy address
  is read from the plan text for that address and resolved through a reviewed change or the `manual-rerun` route.
- The drift workflow's issue bodies print no `DELETE` recipe (removed by #9927 item 8c). Any reclaim of a rehearsal
  survivor is a separately authorized call and must never be pointed at this volume or its Doppler secret.

### Per-loss-mode owner and procedure

The detection and recovery stance of each mode is in the ADR table. The owner of every mode below is the repository owner
(the founder, who is also the sole CODEOWNER); there is no second on-call. The passphrase has TWO independent copies (the
Doppler secret and the Terraform state value `random_password.inngest_redis_luks.result`); its writers are the arm token,
`DOPPLER_TOKEN_TF` and the host boot token `inngest-boot`.

| Mode (ADR table row) | Procedure |
| --- | --- |
| Doppler secret deleted | Stop. Deliver a `manual-rerun` of the per-merge apply, with the owner's per-command go-ahead naming it (it applies the whole per-merge plan; "Delivery route") (the create of the Doppler copy alone is legal there and restores the value held in state). Confirm the next drift run shows no pending change at `doppler_secret.inngest_redis_luks_key`. |
| Doppler secret overwritten | Stop; do not dispatch any apply (a repair is a secret update with `random_password` a no-op, and the per-merge HALT blocks an update of the pair unattended, correctly). Route A: restore the previous value from Doppler version history (plan tier and rollback scope not measured, #9927; never print values or diffs). **Superseded 2026-10-20 (#9927), as to "plan tier and rollback scope not measured":** Route A is **unverified; treat it as unavailable and plan on Route B**. Recorded 2026-10-20: the plan tier is not measurable from the CLI (no plan field); the `soleur-inngest/prd` config log holds 68 entries back to 2026-07-23 (89 days old), which a 3-day activity-log window (documented for the free Developer plan) could not hold; a rollback restores one log entry (a secret add, update or delete), not a whole config (documented, never run); an owner who still chooses Route A reads the entry's age first (it must be inside the 7-day repair horizon stated in the ADR-282 2026-10-22 addendum) and never prints the diff. Route B, when history is unavailable: the Terraform state value is the second, independent copy, so this is NOT total loss; the owner writes it back (below). Total loss only if both copies are gone. **While the Doppler value stays overwritten, every infra-path merge's per-merge apply plans an update of the Doppler copy and halts on the rotation HALT: merge infra PRs with `[skip-web-platform-apply]` until the key is repaired.** |
| Terraform state entry lost | Stop; do not apply. The per-merge HALT blocks a create of `random_password.inngest_redis_luks` (alone or with the Doppler copy); a create of the Doppler copy alone stays legal. **This halt wedges every merge's per-merge apply, so all infra delivery stops, not only the inngest store, until the owner repairs state** (an `import {}` block is not a route that plans as a no-op: it plans the same replacement); until then merging needs `[skip-web-platform-apply]` and applies nothing. Rehearsed offline by `inngest-redis-luks-import-rehearsal.test.sh`: verified on local state with a synthetic value; not run against R2-backed state. Follow "State-loss recovery: owner procedure" directly below the table; result and limits: the ADR-282 addendum of 2026-10-19. The repository owner decides the repair; no agent applies it. |
| Both copies lost | Total loss of the store. Follow "After a total loss" below. |
| LUKS header corrupted | No recovery; the host fails to open the volume. Incident (`soleur:incident`); follow "After a total loss" if the data is unreadable. Detection lagged to the first Redis failure until 2026-10-26; once the owner has delivered the probe-carrying bundle, the daily key-continuity probe pages on a header or keyslot that no longer opens with the held key (see "Key-continuity probe (#9927 item 2)" below; ADR-282 Addendum 2026-10-26 for the limits). |
| Volume deleted despite protection, or project loss | No recovery. Incident; follow "After a total loss". |

**State-loss recovery: owner procedure (owner-run; added 2026-10-19, #9927 item 5; verified on local state with a synthetic value, terraform 1.9.8 and 1.10.5; not run against R2-backed state, and the credential wrapper in step 1 was not exercised).**
The value is a 40-character alphanumeric string. `terraform import` echoes it, a plan can print it, and every state file holds it, so every step is owner-local: in the owner's terminal, never through an agent, a `!` prefix, CI or a recorded session. Run from the repository root. Run steps 1 to 7 in one subshell (`( ... )`) or restore your `umask` in step 7, because `umask 077` otherwise stays in your shell.

1. Prepare.
   - Pause infra merges (`[skip-web-platform-apply]`), because R2 has no lock. Wait until no run is queued or in progress for any workflow that shares the state, because a merge pause does not stop a run already started: `for w in apply-web-platform-infra.yml apply-deploy-pipeline-fix.yml registry-host-replace-dispatch.yml inngest-provision-rehearsal.yml scheduled-terraform-drift.yml; do for s in queued in_progress; do gh run list --workflow "$w" --status "$s"; done; done` must print nothing. (The first four share the `terraform-apply-web-platform-host` concurrency group; the drift run reads the same state.)
   - Match the CI terraform: `terraform version` must print the version CI pins (`TERRAFORM_VERSION` in `.github/workflows/apply-web-platform-infra.yml`, 1.10.5 as read on 2026-10-19). A state written by a newer terraform is refused by an older one, and the rehearsal suite passed on 1.9.8 (local) and on 1.10.5 (CI, 2026-10-19).
   - Credentials: define the per-merge job's wrapper, `tf() { doppler run --preserve-env -p soleur -c prd_terraform --name-transformer tf-var -- terraform -chdir=apps/web-platform/infra "$@"; }`, and pass the same `-var` flags its `terraform plan` step passes (`ssh_key_path` and the others it names). Every `terraform` command below goes through `tf`. Then `tf init -input=false -lockfile=readonly`. **The wrapper feeds the S3 backend from ambient `AWS_*` only** — the tf-var transformer renames the injected `prd_terraform` pair to `TF_VAR_aws_*`, so the backend reads whatever `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` the shell already holds. That ambient pair must be the Tier-B read/write pair (`export AWS_*` from `TF_STATE_AWS_*` in `soleur-infra-privileged/prd`, per `infra-credential-tiers-8209.md` §Local Terraform invocation) **before step 5's `tf state push` — a write that 403s on the read-only `prd_terraform` pair.** The Route-B `state pull` below is a read and correctly uses the `prd_terraform` pair via `--only-secrets` (no transformer, names pass untransformed).
   - Work in a private directory on tmpfs, so no copy of the value reaches disk (`shred` means nothing on SSD or copy-on-write storage, and tmpfs is not swapped unless swap is enabled; check `swapon --show` is empty): `umask 077; SD=$(mktemp -d "${XDG_RUNTIME_DIR:-/dev/shm}/inngest-state.XXXXXXXX")`, and confirm `findmnt -no FSTYPE -T "$SD"` prints `tmpfs`.
   - Back up the current state, which does not yet hold the passphrase entry but holds every other secret: `tf state pull > "$SD/backup.json"`. It is for inspection; do not push it back.
2. Read the value without echo into an UNEXPORTED variable from the surviving Doppler copy: `v=$(doppler secrets get INNGEST_REDIS_LUKS_KEY -p soleur-inngest -c prd --plain)`, and stop unless `[[ "$v" =~ ^[A-Za-z0-9]{40}$ ]]`. If the Doppler copy is also lost, this is "Both copies lost", not this procedure. The later digest comparison is circular (the value came from that copy): it checks import integrity only, so no step here checks that the value opens the LUKS header.
3. Import, with a single-command prefix assignment and the flags INSIDE the variable: `unset TF_LOG TF_LOG_CORE TF_LOG_PROVIDER TF_LOG_PATH; TF_CLI_ARGS_import="-input=false random_password.inngest_redis_luks $v" tf import > "$SD/import.out" 2>&1; echo "import rc=$?"`. Never `export v`, and avoid `env VAR=value terraform` (the value sits on a command line until exec replaces it). The capture file contains the value: never read it, and use only the printed status. If the status is not `0`, stop: nothing was written, and the entry is still lost.
4. The state is now imported but not edited, a LIVE RED state once it is in R2: every per-merge apply and drift run is expected to fail on `prevent_destroy` until step 5 is pushed (inferred from the rehearsal; the real workflows were not run). Do steps 4 to 6 in one sitting. Compare digests without printing either value: `tf state pull | jq -j '.resources[] | select(.type == "random_password" and .name == "inngest_redis_luks" and .module == null) | .instances[0].attributes.result' | sha256sum` must equal `printf %s "$v" | sha256sum`. On a mismatch, run `tf state rm random_password.inngest_redis_luks` and stop (back to the lost-entry state; the per-merge halt stays in force). A wrong-length value would also show as a `length` change in a plan (the provider sets `length` from the id).
5. Repair: pull a fresh copy, set `special = false` on exactly one instance with serial plus one, push. Never `-force`:

   ```
   tf state pull > "$SD/cur.json" \
     && [ "$(jq '[.resources[] | select(.type == "random_password" and .name == "inngest_redis_luks" and .module == null)] | length' "$SD/cur.json")" = 1 ] \
     && jq '.serial += 1 | (.resources[] | select(.type == "random_password" and .name == "inngest_redis_luks" and .module == null) | .instances[0].attributes.special) = false' "$SD/cur.json" > "$SD/fixed.json" \
     && tf state push "$SD/fixed.json"
   ```

   If the push is refused, another writer moved the state: discard `fixed.json`, pull again and redo from the pull. Never hand-edit a serial onto a stale document (the push only compares serials, so a stale document with a higher serial would silently overwrite a concurrent writer). If the chain stops for any other reason, run `tf state rm random_password.inngest_redis_luks` and stop.
6. Verify with a targeted plan whose output goes to a file, and read only the exit status: `tf plan -input=false -detailed-exitcode -target=random_password.inngest_redis_luks -target=doppler_secret.inngest_redis_luks_key > "$SD/plan.out" 2>&1; echo "plan rc=$?"`.
   - `0` is "No changes" for those two addresses (a full-root plan can legitimately show other changes, including the backlog of merges made with `[skip-web-platform-apply]`).
   - `1` is an error (credentials, variables, init), not a diff: fix the environment and re-run the plan; do not undo the repair.
   - `2` is a diff: do not apply. Run `tf state rm random_password.inngest_redis_luks` and stop.
   - Do not print `plan.out`: a diff at the Doppler copy would carry plaintext.
7. Clean up: remove `$SD` (it holds the backup, the pulled and edited state, the import output and the plan output), `unset v`, and the local files terraform may have left in `apps/web-platform/infra/` and the repository root: `rm -f apps/web-platform/infra/terraform.tfstate* apps/web-platform/infra/crash.log terraform.tfstate* crash.log` (timestamped `.backup` files are not git-ignored and hold plaintext). Resume merging only after reading the first post-repair per-merge plan, which carries the backlog of `[skip-web-platform-apply]` merges.

Not covered by this recipe: whole-state loss (a lost state object plans creates for everything); loss of BOTH pair members (the Doppler copy would then plan as a create, and whether to import it or accept a same-value create is unverified); R2-backed state (the `tf state` commands against the remote backend, and `state rm` there, were not run).

**Route B: write the state value back to the Doppler secret (owner-run; per-command go-ahead; NOT executed or rehearsed).**
Get the owner's explicit go-ahead for each command (a menu answer is not one). The value travels only through a pipe and a
shell variable inside a subshell: never printed, never on argv, never in a file, and the write only runs when the state
read produced exactly one 40-character alphanumeric value (the passphrase is `length = 40, special = false`).

Preconditions, before the write:

- **Which side is right is not known from drift.** An "update planned" at the Doppler copy says only that Doppler differs
  from state. An owner-run `luksChangeKey` with Doppler updated and state stale would make the STATE value the wrong one.
  If anything suggests a deliberate re-key, stop.
- Read the Doppler audit metadata for who and when, without values: `doppler configs logs -p soleur-inngest -c prd -n 10`
  (never `doppler configs logs get`, which carries plaintext).
- Record a non-secret fingerprint of the current value in the incident notes:
  `printf %s "$(doppler secrets get INNGEST_REDIS_LUKS_KEY -p soleur-inngest -c prd --plain)" | sha256sum | cut -c1-8`.
- **The write is irreversible without Doppler history.** Do not stash the old value under a second secret name in
  `soleur-inngest/prd`: the host's boot isolation self-check there is an exact set, so an extra name boot-bricks the next
  re-provision.

Credentials. The state read takes the R2 backend credentials from `prd_terraform` through `--only-secrets
AWS_ACCESS_KEY_ID,AWS_SECRET_ACCESS_KEY`, so the read/write Hetzner token and the other secrets in that config are not
injected. The write needs a Doppler token scoped to `soleur-inngest/prd` (the owner's own login, or the arm token
`DOPPLER_TOKEN_INNGEST_ARM`); if a token is used, supply it only as `DOPPLER_TOKEN` on the two `soleur-inngest` commands
(an exported token for the wrong project would break the first `doppler run`), and never print it. Run from the repository
root:

```
( set -o pipefail
  v=$(doppler run -p soleur -c prd_terraform --only-secrets AWS_ACCESS_KEY_ID,AWS_SECRET_ACCESS_KEY -- sh -c 'terraform -chdir=apps/web-platform/infra init -input=false -lockfile=readonly >/dev/null && terraform -chdir=apps/web-platform/infra state pull' | jq -er '[.resources[] | select(.mode == "managed" and .type == "random_password" and .name == "inngest_redis_luks" and .module == null) | .instances[0].attributes.result] | if length == 1 and (.[0] | type == "string" and test("^[A-Za-z0-9]{40}$")) then .[0] else error("no unique 40-char value") end') \
  && printf %s "$v" | doppler secrets set INNGEST_REDIS_LUKS_KEY -p soleur-inngest -c prd --silent \
  && [ "$(printf %s "$(doppler secrets get INNGEST_REDIS_LUKS_KEY -p soleur-inngest -c prd --plain)" | sha256sum)" = "$(printf %s "$v" | sha256sum)" ] \
  && echo written-and-verified || echo NOT-VERIFIED
  unset v )
```

`written-and-verified` means the value read back from Doppler has the same sha256 as the state value (compared without
printing either). `NOT-VERIFIED` means nothing was written or the compare failed; the old value is untouched unless the
write itself ran. The filter and the pipeline were run offline against synthetic state and stub `doppler` and `terraform`
(a good value is written and verified; a null or absent `result`, empty or non-JSON state, a wrong length, a non-alphanumeric
value, a duplicate resource, a module-only resource, an empty instance list, a failing `terraform init` or `state pull`, and
a failing write all end `NOT-VERIFIED` with the store unchanged). It was not run against the real backend or the real
Doppler CLI, and it cannot prove the value opens the header: only a host boot does. Then dispatch nothing: the next drift
plan should show no change at `doppler_secret.inngest_redis_luks_key`.

### After a total loss: who tells affected users

The repository owner is the incident owner and sends the user notice as a product notice, using `soleur:incident` to
scaffold the report. **No per-user list is kept app-side**: `schedule-reminder` persists nothing app-side (ADR-282, "What
losing the store costs"). Whether any surviving record identifies whose reminders or runs were in the store is **NOT
established** (partial, see the C1 paragraph below); do not tell anyone "no record survives" or "nothing identifies them". The
default is to treat **all active users** as potentially affected, and that default is a floor, not a ceiling: the event-class table
below lists who it does not cover. Do not state a narrower set.
**Superseded 2026-10-22 (#9927 C1), as to "Whether a surviving source exists ... is open and tracked in #9927":** measured,
evidence class **partial**. A candidate source exists: the Inngest Postgres half is a dedicated Supabase project with 14
tables and estimated ~937k `history`, ~182k `events` and ~1.6M `spans` rows (estimates: they support present, never
absent), and a column capable of holding a user reference (`events.event_user`, by name). That column is Inngest's top-level user field and
this repo's own senders do not set it (they put the founder id inside the event `data`), so neither a non-null count nor an empty
result there can define or bound the affected set. The number of non-null rows was NOT measured and the oldest row was NOT
measured. The default stays in force: treat all active users as potentially
affected, and do not state a narrower set. Narrowing would need an incident-time row-level reconstruction, which was not
tested and is separate processing needing its own owner decision. The ciphertext backup (1b) stays parked, and no second
copy of identifying payloads may be created before an Art. 17 retention and erasure design exists (#10848). No row,
identifier, email, payload, event body or per-user count was selected, printed, logged or stored. Whether any surviving
record identifies WHICH users had armed reminders or in-flight jobs was NOT established. Measured on 2026-10-22 by
three catalog-metadata queries (identity, columns, estimates) through the dedicated read-only Management API endpoint against project
`pigsfuxruiopinouvjwy`; the probe script was removed from the PR once the finding was recorded, so the method lives in the record
(`knowledge-base/project/specs/archive/20261022-221258-feat-one-shot-9927-inngest-luks-items-6-8b-c1/measurements.md`) and in git history, and a "round 2"
would re-add it in its own PR with its own suite (owner-gated).
**Superseded 2026-10-20 (#9927), as to "the default is all active users":** the default stays, but it is not complete. The
code read below shows two groups it does not cover: **users who are not currently active** (a founder with a connected GitHub
installation or an unpaid invoice may be past due or churned yet still have a lost draft card), and **people who are not users
at all** (the sender of an inbound email whose triage event was in flight). The loss horizon is the whole life of the store,
because no copy exists off the volume; in practice the harm is work that was queued or in flight at the moment of loss.
Before sending, assess with counsel whether the loss of availability of personal data held in the store is a
personal-data breach (Art. 4(12), 33 and 34; total loss of availability is not necessarily one, so the step is to assess).
If any limb is a personal-data breach, the 72-hour clock of Art. 33 runs from awareness. The breach register is
`knowledge-base/legal/breach-register.md`. The claim that armed reminders can be re-armed from Postgres is **unconfirmed**
(the enumeration script reads the live store, and the route that arms a reminder persists nothing app-side). With an
empty store, the app's behaviour is that functions re-register and new reminders arm normally; do not tell users their
reminders will be restored. **Restoring an empty store has no automated route:** the recut dispatch is retired (#8285), the
per-merge create HALT refuses a new passphrase, and the inngest-host shape gate refuses the volume and passphrase pair, so
the owner designs the restoration in a reviewed change (#9927).

#### Which Inngest events carry a user reference (code read, 2026-10-20, #9927 item C1)

Read from the repository only (no production access): the senders, the handlers and the payload FIELD NAMES, never values.
This table is the code-side half of the C1 finding; the measured half is the C1 paragraph above (the Superseded 2026-10-22 block). A `bot-fix/*` name is a GitHub
label, not an Inngest event, and no `vendor/*` event exists (the only vendor-related event is
`cron/content-vendor-drift.manual-trigger`).

| Event family | User reference in the payload | User-visible harm if an armed or in-flight instance is lost | Covered by "all active users"? |
| --- | --- | --- | --- |
| `reminder.scheduled` (`app/api/internal/schedule-reminder`, handler `eventScheduledReminder`) | none (`reminder_id`, `fire_at`, a platform actor, `action`); the `action` can hold operator or agent free text | a scheduled operator comment or registered check never fires | not applicable (operator work) |
| GitHub action-class events: `engineering.pr_review_pending`, `engineering.ci_failed`, `triage.p0p1_issue`, `security.cve_alert` (`app/api/webhooks/github`, handler `githubOnEvent`) | `founderId`, `installationId`, `deliveryId`; a redacted copy of the webhook body (titles, author logins) | the founder's draft card for that PR, CI failure, P0/P1 issue or CVE alert is never created; the webhook dedup row is already claimed, so GitHub does not redeliver | yes if the founder is active; no if inactive |
| `platform/workspace.reconcile.requested` | `installationId`, `deliveryId`, repository slug (no user id since schema v3) | a workspace is not synced to its default branch until the next push | partly (identified by installation and repository, not user) |
| `finance.payment_failed` (`app/api/webhooks/stripe`, handler `cfoOnPaymentFailed`) | `founderId`, `customerEmailHash`, `invoiceId` | the founder's payment-failure draft card is never created | yes if active; a past-due founder may not be |
| `agent.spawn.requested` (`app/api/dashboard/today/[id]/send`, handler `agentOnSpawnRequested`) | `founderId`, `messageId`, `actionSendId`, `actionClass`, `sourceRef` | an event lost AFTER Inngest accepted it is never redelivered, so an approved action is never executed and no acknowledgement is posted; an enqueue that was never accepted is replayed by the founder's re-click for 23 hours (#10543) | yes if active |
| `agent.spawn.orphaned` (internal) | the whole original envelope, so `founderId` and `actionSendId` | the failed spawn is never settled and its `action_sends` row stays unfinished | yes if active |
| `email/inbound.received` (`app/api/webhooks/resend-inbound`, handler `email-on-received`) | the sender address, the recipient inbox addresses, provider message ids, a subject | an inbound email is never triaged, including a possible statutory request (a data-subject request); its clock still runs | **no**: the person harmed is an external correspondent, not a user |
| `cron/<name>.manual-trigger` (57 names; `server/routines/run-routine.ts`, `app/api/internal/trigger-cron`) | `actor_id`, `delegating_principal`, `actor_class`, run ids | an operator-requested one-off run is lost; the scheduled run still happens | yes (an operator or user requested it) |
| `oneshot/*.fire`, `cron/action-required-sla.process-issue`, `ship-merge.manual-trigger`, `cf-token-expiry-check.manual-trigger` | none | an operator check or a daily nudge for one issue is skipped | not applicable |

Only `reminder.scheduled` has a re-arm path (`apps/web-platform/infra/inngest-rearm-reminders.sh`). The event store keeps payloads with no automatic
deletion, per a source comment in the GitHub webhook route (not independently verified): the redacted GitHub body and the inbound
email addresses sit in the Postgres history. That is why this section never asks anyone to copy the store, and why the ciphertext
backup (item 1b of #9927) stays parked until an Art. 17 retention and erasure design exists.

**The one group the "all active users" default never reaches, and a step for it.** An inbound email that was in flight when the store
was lost (`email/inbound.received`) harms its external sender, and a statutory request among them keeps its clock running. After a
loss the owner lists the inbound mail received since the last known-good triage from the mail provider's side (counts only; no address
goes into a committed file), triages it by hand, and records the clock in the incident report. Nothing in the user notice covers this group.

### Key-continuity probe (#9927 item 2)

A daily, read-only probe on the dedicated Inngest host asks cryptsetup whether the key the host holds still opens the LUKS2 header of the volume behind `/mnt/data`. It is a bounded function (`luks_key_probe_tick`) inside `apps/web-platform/infra/inngest-cutover-flip.sh`, so it ships through the signed config bundle ([ADR-135](../../architecture/decisions/ADR-135-pull-based-signed-config-refresh-for-dedicated-inngest-host.md), [`inngest-config-refresh.md`](./inngest-config-refresh.md)) with no `user_data` change and no host replace. The decision, isolation rules and accepted residuals are in the ADR-282 addendum of 2026-10-26; this section does not restate them. A page means the key no longer opens the volume; header backup is the open, legal-gated item (#9927 item 1), and no recovery exists if the header is lost. Every read below needs no host login (`hr-no-ssh-fallback-in-runbooks`).

**The row.** One plain-text line, `SOLEUR_INNGEST_LUKS_KEY_PROBE token=<tok> rc=<n> at=<literal>`, emitted twice: under SYSLOG_IDENTIFIER `inngest-cutover-flip` (shipped by Vector) and through the curl-direct phone-home (whose message starts with the marker, then `stage=luks-key-probe`, then the detail). It never carries the key, a UUID, a device id, a hash or stderr. Cadence: the first 30-second tick after delivery (no stamp), then every 24 hours after an `ok`, every hour after any other token.

| Token | Meaning | Pages |
| --- | --- | --- |
| `ok` (`rc=0`) | The key held at `/etc/default/inngest-luks` unlocked a keyslot of the header at probe time. | no |
| `fail_passphrase` (`rc=2`, from the `kdf` step) | cryptsetup read the header and no keyslot accepts the held key. | yes |
| `fail_header` (from the `uuid` step) | The device is not readable as LUKS: `luksUUID` and `isLuks` both exited 1 (two independent reads must agree). | yes |
| `fail_key_absent` (`at=key`) | The key file is missing, unreadable, or its value is empty: the next reboot cannot reopen the store. | yes |
| `indeterminate` | The probe could not measure. The `at=` literal names the step: `key` (the key-file check timed out or could not run), `mount` (not on a `/dev/mapper/` source), `status` (`cryptsetup status` unusable), `uuid` (a non-1 exit, a timeout or a missing tool), `mem` (not enough free memory for the keyslot's KDF), `shield` (the OOM shield write was refused), `kdf` (a timeout or an exit other than 0 or 2). It is never a verdict about the key. | never on its own |

**What the probe can and cannot claim.** Can: at probe time, the key held on this host at `/etc/default/inngest-luks` unlocks a keyslot of the LUKS2 header on the device behind the `/mnt/data` mapper; this covers the reboot path (`inngest-luks-open.service`) for that device. Cannot: that the Doppler copy equals the host file (the 12-hour drift plan covers that, and a host replace reads Doppler); that a header backup exists; that the header survives a future device fault; that the device behind the mapper is the by-id volume the boot unit opens (they coincide by construction while mounted; the probe does not derive the boot unit's device); or that a failed header is recoverable (ADR-282 "No recovery" stands until the legal-gated backup ships). LUKS2 keeps a redundant secondary header, so damage to the primary header alone may not fail the probe.

**Key-charset assumption.** The key value is `random_password` with `special = false` (ADR-006 addendum), that is `[A-Za-z0-9]`, so the probe's `sed` extraction and systemd's `EnvironmentFile` parsing (the reboot path) read the same bytes. A value outside that set (an `=`, a trailing space) is outside the assumption; the probe suite pins the observed behaviour. A trailing newline would make the right key fail, which is why the probe strips it.

**Sandbox status.** `sandbox: unverified`. The real `findmnt` shape under the unit's `ProtectSystem=strict` and bind-mounted `ReadWritePaths`, `--disable-locks` and the `oom_score_adj` write were measured only on a file-backed container at plan time. Until a rehearsal result is recorded here, the first-row verification below accepts only `token=ok`, and an `indeterminate` row with `at=mount`, `at=status` or `at=kdf` is read as "not yet proven", never as delivery.

**Decision table for a page** (no destructive step; every action that writes belongs to the repository owner):

| Page | What it means | Action |
| --- | --- | --- |
| `fail_key_absent` or `fail_passphrase` | The next reboot cannot reopen the store (key absent), or the header or keyslot no longer matches the host key. | STOP. Dispatch no host replace until the cause is established: a replace re-reads Doppler and may not open the volume. Read the 12-hour drift plan for the Doppler copy. The owner follows the existing "Per-loss-mode owner and procedure" table above (Doppler secret overwritten, state lost, header corrupted). |
| `fail_header` | The device no longer reads as a LUKS volume. | ADR-282 "No recovery". Follow "After a total loss" if the data is unreadable, and open an incident with `soleur:incident`. |
| `indeterminate` (no page of its own) | The probe could not measure. | Read the `at=` literal from the rows (query below). A dead-man page without a fail page means the probe cannot measure (`mount`, `status`, `mem`, `shield`, `kdf`): fix the measurement; it is not health. |

A fail page re-runs hourly while the verdict stays non-`ok`, and the alert clears within about three hours of the first `ok`.

**The dead-man.** A second alert fires when the probe has been seen at least once (the oldest marker row is more than 26 hours old) and then produces no `ok` or `fail_*` row for 26 hours. It counts only measured verdicts, so an `indeterminate`-only stream fires it after 26 hours and a failing probe leaves it quiet (the paging alert owns that). It is quiet before delivery. Its accepted residuals, stated and not hidden:

- a bundle revert, or promotion of an older bundle, fires it about 26 hours later (correct: the probe is gone);
- a log-pipeline outage longer than 26 hours fires it;
- it self-disarms after 30 days with no marker rows at all (its query window is 30 days); if the probe is ever dark that long, the dead-man must be converted to a count-variable form (recorded on the keeper follow-up under #9927);
- a bundle that is never promoted keeps it quiet forever; the owner-hold tracker for delivery, not the alert, covers that.

**Check the pipeline before the host.** A dead-man page far more often means the pipeline or the bundle than the volume. Diagnose with no host login, in this order (both commands are read-only; read each result by meaning, since a webhook payload that quotes the marker is not a probe row):

```
doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh --since 72h --grep SOLEUR_INNGEST_LUKS_KEY_PROBE --limit 20
doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh --since 72h --grep SOLEUR_INFRA_PULL_APPLIED --limit 1
```

1. Do other rows from the host arrive (the `SOLEUR_INFRA_PULL_` rows, the cutover heartbeat)? If not, the Logs pipeline or the host is the problem, not the key.
2. Compare the newest `SOLEUR_INFRA_PULL_APPLIED version=` with the version of the bundle that first carried the probe. A version below the probe-carrying one means a bundle revert or an older bundle: the probe is gone, and a probe-carrying bundle must be promoted again.
3. Only then read the `at=` literals of the last probe rows as the table above says.

<!-- lint-infra-ignore start: describes held production acts and their verification; the PR performs none of them -->
**Delivery: what the merge does by itself, and what the owner holds.**

What the merge does by itself (automation, no operator step):

- `apply-web-platform-infra.yml` creates the alert resources.
- `apply-deploy-pipeline-fix.yml` fires: `inngest-cutover-flip.sh` is a `triggers_replace` hash input of `terraform_data.deploy_pipeline_fix` and is in that workflow's `paths:`. It pushes the web-host payload (webhook plus the tunnelled SSH bridge) to the web hosts, where the script is an inert file (no flip timer on web). Expect `files_written == files_total` in the run; the ship skill's `DEPLOY_PIPELINE_FIX_TRIGGERS` gate applies; no `[skip-deploy-fix-apply]` marker is used (the web copy must stay in lockstep with the trigger lists).
- `mint-inngest-bootstrap-tag.yml` mints a `vinngest` tag because `inngest-cutover-flip.sh` is a `cp`-staged carrier, and the bot opens a pin-bump PR that edits `cloud-init-inngest.yml`. That bump is routine: merge-apply `-target` lists exclude `hcloud_server.*`, so it shows only as standing drift (#10835, #10768) and replaces nothing. It is a separate PR from the probe's.

What reaches the dedicated host only after the owner acts (held; production-mutating). These are owner-reserved production writes; this section describes them and no agent performs them. A menu answer is not authorization for any of them (`hr-menu-option-ack-not-prod-write-auth`):

1. Pre-promotion checks (read-only, recorded on the tracker): `bash -n` and a `--fixture-seams` smoke run of the script as packed into the built bundle; the sandbox rehearsal result; a review of the member diff since the last promoted bundle (the bundle is built from the default branch, so any other member edit merged since then ships too); a pre-built, unpromoted revert bundle at the next higher version (the channel is monotonic, so a rollback is a roll-forward).
2. Dispatch `build-inngest-config-bundle.yml` from the default branch at a version above the applied one (read it from the newest `SOLEUR_INFRA_PULL_APPLIED version=` row; if that row is absent or past retention, read the drift comparator summary), approved in the `inngest-config-signing` environment. The exact steps are in [`inngest-config-refresh.md`](./inngest-config-refresh.md) "Ship a host-script change".
3. Promote the digest (`INNGEST_CONFIG_DIGEST` in `soleur/prd_terraform`, then the targeted apply per `inngest-config-refresh.md` step 3; #9060 automation is still open).
4. Before ANY future host replace, promote a probe-carrying bundle: a replaced host applies the currently promoted bundle over the image-baked script, so a promoted bundle that predates the probe silently drops it.

**First-row verification** (read-only, no host login; also the close condition of the owner-hold tracker):

```
doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh --since 2h --grep SOLEUR_INNGEST_LUKS_KEY_PROBE --limit 5
```

Read by meaning: a row from the SYSLOG_IDENTIFIER `inngest-cutover-flip` channel AND a phone-home row, both `token=ok rc=0`, within about two minutes of the next applied bundle (the 60-second refresh timer, then the first 30-second tick with no stamp). A webhook payload that quotes the marker, or an `indeterminate` row, does not satisfy it. A `token=fail_*` row pages. The first `ok` row is also the delivery proof (`GUARD_REV` is deliberately not bumped).

**Rollback (independent of the probe path):** a revert PR restoring the previous script, a new bundle at a higher version (pre-built per step 1), and the same promotion. The refresh engine and units are not members, so the rollback path does not run through the probe. Expected side effect: the dead-man fires about 26 hours after the measured rows stop. A script that breaks every tick would kill the only no-SSH rollback channel on the dedicated host, which is why step 1 exists.

**Residuals stated, not hidden:** if the bundle is never promoted, the dead-man stays quiet forever (the owner-hold tracker carries a due date); the dead-man self-disarms after 30 days with no rows at all; the bot pin-bump PR is merged or closed per the existing image-release runbook and its standing drift is harmless.
<!-- lint-infra-ignore end -->

### Deliberate unprotect (two reviewed changes; no sanctioned erase path)

Lifting protection is two reviewed PRs, in this order, never one:

1. Lift Hetzner delete protection on the volume in its own PR and let the per-merge apply land it. Read back
   `not-protected` (the wrapped command above, expecting the opposite result).
2. Only then remove `prevent_destroy` in a second PR.

Removing `prevent_destroy` alone is the trap: a destroy apply detaches the mounted volume before Hetzner refuses the
delete. Each PR edits the guards it trips (the Guard 1 rows in `inngest-luks-sole-copy.test.sh`, the census rows if any
(G4h and `G4_PROTECTED`), the G2 expected set and the G2e effective-text pin in `terraform-target-parity.test.ts`), so the
weakening is visible in review. **No key-rotation route exists today.** The per-merge rotation HALT cannot be
acknowledged and its text names no automated route, so lifting `prevent_destroy` on the pair is not a rotation procedure; a
leaked-key response is an escalation to the owner, carried by #9927. **No sanctioned erase path exists for this volume
since PR B of #8285** (the wipe and destroy dispatch was deleted), so a whole-volume Art. 17 erasure needs a new,
separately designed and reviewed path; none is built.

### Break-glass: a sanctioned host replace is blocked by the protection (the reviewed two-step route)

That Hetzner allows detach of a delete-protected volume is documented only indirectly; the first sanctioned replace is the
live proof. If a replace is refused for that reason, the data-safe route is the reviewed two-step route, and **it takes
several merge cycles; there is no faster data-safe route**:

1. A PR sets the volume's delete-protection attribute to false in `inngest-redis-luks.tf` and edits what it trips (the
   Guard 1 rows, the G2e parity-test pin, the census rows, if any). It must also remove the cause of any current halt
   in the same change and must not carry `[skip-web-platform-apply]`, or the per-merge apply never lands it. Before this
   PR merges it opens a dated re-protect follow-through issue (step 3, with its date), because once step 1 lands the
   HCL, the live state and the drift plan all agree on `false` and nothing alerts. The per-merge apply lands it, so live
   state equals the HCL. Read back `not-protected` (the expected word for this PR; not a failure).
2. Dispatch `inngest-host-replace` (the volume now plans as a no-op, which both gates accept), then `op=resume` per #7228.
3. A re-protect PR restores the attribute and the guards; the per-merge apply lands it; read back `protected`. **The
   unprotected window is a stated cost of this route**: from step 1's apply until step 3's apply the sole copy is deletable
   by a console click, a wrong id or a pasted recipe, and the dated issue from step 1 is the only forcing function.

**Why a one-call out-of-band lift is not a route.** A single Hetzner `change_protection` call makes the next dispatch plan
show the attribute going from false back to true on the volume, an in-place update; both host-replace gates abort
`luks_volume_touched` on any volume action other than no-op or create, so step 2 is refused by construction. The next
infra-path merge or `manual-rerun` runs the per-merge apply and re-protects. Any out-of-band lift is reverted by that
apply. Do not use one to try to complete a replace.

### Volume recreated: the id-pin bump checklist (added 2026-10-24, Ref #10952)

A recreated volume has a new Hetzner id, and until the pin is bumped the sole-copy probe and BOTH orphan sweeps report the old id as
missing (the sweeps end red with `orphan_sweep_project_identity_unproven` and list nothing; ADR-282 addendum 2026-10-24). The bump PR
merges in the same cycle as the `.tf` change that recreates the volume; the founder, as incident owner, owns it. Regenerate the list
below with `git grep -n 106903269` (do not trust a remembered count); on 2026-10-24 it names these places:

- **Pins enforced by `plugins/soleur/test/sole-copy-drift-check.test.sh` (rows N1 and N1b; a stale one reds the suite):** every
  `readonly VOLUME_ID_PIN=` line in `.github/workflows/scheduled-terraform-drift.yml` (exactly three: the sole-copy probe and the
  two orphan sweeps); the "Hetzner id" text in ADR-282; the postmerge skill's section-5c one-liner
  (`plugins/soleur/skills/postmerge/SKILL.md`); the section-5c one-liner in this runbook; and the `VOL_ID` constant in the suite itself.
- **Pins enforced by `plugins/soleur/test/token-drift-workflow-causes.test.sh` (rows R9; a stale one reds the suite):** the id in the `curl` shim
  and in the grep patterns of the project-identity cases. Change every occurrence in that file in the same edit.
- **Record-only places, updated by hand (nothing compares them):** `scripts/encryption-posture-ledger.json`,
  `knowledge-base/legal/compliance-posture.md`, `inngest-provision-rehearsal.md`, ADR-142, and the dated audit records under
  `knowledge-base/legal/audits/` (historical records keep the id they were written with; add a dated line, do not rewrite them).

### Revert recipe

Two recipes. The full revert was executed once in a scratch detached worktree (the record is below); the partial recipe is a
procedure and was not rehearsed.

- **Partial (preferred):** keep the protections and revert only a misbehaving guard row or record edit. Never rebase after
  a record names a commit id.
- **Full revert:** in a scratch detached worktree, `git revert --no-commit` the feature commits, then run the suites the
  revert PR must pass. The revert plans the inverse in-place update (protection true to false) through the same per-merge
  path, and it must remove the new suite together with its registrations (the `PROMOTED_FILES` entry in
  `scripts/guard-vacuity-floor.test.sh`, plus the rows in `apps/web-platform/infra/suite-shard-legs.tsv` and
  `apps/web-platform/infra/suite-durations.tsv`) in the same commit, or the orphan census and the vacuity-floor test go red. Lifting protection deliberately is never a revert of only `prevent_destroy`.

Recorded scratch-run output (executed 2026-10-10 in a scratch detached worktree at `40b2aff031`, the branch head at that
time, before the review commits; the three feature commits were reverted with `git revert --no-commit`, 21 files, and the
suites below were run in that tree). The numbers are dated to that head: the census is 342 at the final head, and the other
counts may differ there:

```
git revert --no-commit <records, guards, evidence commits>   rc=0   (21 files, the .tf pins and the new suite and library gone)
guard-vacuity-floor           rc=0  23 passed, 0 failed
lint-orphan-test-suites       rc=0
workspaces-luks               rc=0  61 passed, 0 failed (same count as before the lexer extraction)
infra-privileged-tier-census  rc=0  314 passed, 0 failed (336 with the pins)
inngest-host-replace-gate     rc=0  41 passed, 0 failed
inngest-host-shape-gate       rc=0  76 passed, 0 failed
inngest-redis-luks            rc=0  57 passed, 0 failed
inngest-host                  rc=0  101 passed, 0 failed
lint-encryption-posture       rc=0
Not run in the scratch tree: the bun parity test (no node_modules there); CI covers it.
```

*Note, 2026-10-10 (#9879 review):* the list of registrations to remove in the revert recipe above was corrected after this
scratch run was recorded; the run's output block is unchanged. The registrations this PR actually created are the
`PROMOTED_FILES` entry in `scripts/guard-vacuity-floor.test.sh` and the rows in the two `*.tsv` files. No `test-all.sh` line
and no `BASELINE_DECLARED_PROBES` bump were created.

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
- **After the host replace that carries #9786 (parked; not yet in force).** The template resolves the one LUKS volume.
  An unpointed boot-reopen of a non-LUKS volume now FAILS `reopen_not_luks` (it used to skip with exit 0), and the
  first-boot stage row for the no-pointer world reads `mode=unpointed` (was `plaintext_canonical`). A blank volume is
  formatted only on a `rehearsal_*` config; on any other config the stage fails with `stage=unpointed_raw_refused`
  (`inngest-luks-FAILED` phone-home carries the same stage), and there is no automated bring-up for a brand-new blank
  `prd` volume, so that case needs a disaster-recovery procedure written when it is ever needed (ADR-142, addendum
  2026-10-12). A lost pointer over an INTACT LUKS volume boots (opened and mounted) and is visible only as
  `pointer=absent` on the `stage=resolve` row.

---

## Related

- ADR-142 (+ its 2026-09-18 amendment) — why additive, why a pointer, why a separate flag.
- ADR-199 — the empty-store world, where the destructive recut is lawful instead.
- `knowledge-base/engineering/operations/runbooks/inngest-server.md` — the host itself.
- `betterstack-log-query.md` — the standing alarms over this source, including the wrong-volume alert.

## 2026-10-13 — `reopen_mount`: what a heal row means (#10217)

Since this change, a boot where the LUKS stage lost the volume-attach race is no longer fatal-by-construction. The boot-reopen unit now completes the mount for the arm it verified: a `SOLEUR_INNGEST_LUKS_STAGE`/`inngest-luks-stage` journald row `reopen_mount` after `reopen_ok` (or after the already-open `reopen_noop`, or after `reopen_skip_plaintext` on the ext4 arm) means the reopen wrote the `/mnt/data` (or `/mnt/data-luks`) fstab line and mounted it. Note two `reopen_mount` shapes share one stage name: the progress row (rc=0, fires BEFORE the umount on a wrong-source convergence — the detail string says what it is doing) and the completion row; and `reopen_device_wait` now emits rc=0 PROGRESS rows ("waiting up to 300s", "appeared after Ns") under the same stage name as the old rc=1 FATAL — rc is the discriminator, not the name.

Failure surface: `reopen_fstab` (fstab write/install), `reopen_mount` (umount/mkdir/mount, and the new stacked-mountpoint refusal), `reopen_backing` (an already-open mapper not backed by the arm's verified device — the noop path now refuses this rather than entrenching it), and `reopen_pointer_lost` (empty pointer plus post-cutover evidence — the ext4-skip arm refuses rather than mounting the plaintext backstop). All leave the unit `failed`. **Phone-home scope:** `inngest-luks-reopen-ARM-FAILED` fires only from the first-boot runcmd arm — on boot ≥2 there is no `OnFailure=` reporter, so the detection path is the journald row itself → the hourly probe (`data_mount_devid=__UNREADABLE__` / `redis_active=inactive`) → the wrong-volume alarm. Conversely, the emit signature differs by boot number: on the FIRST boot (`enable --now` arm) a healthy run emits `reopen_noop` and NO `reopen_mount` (the stage already mounted). On boot ≥2 the mapper starts closed and this unit runs `Before=local-fs.target`, so a healthy boot shows `reopen_ok` then a `reopen_mount` completion row — it performs the mount itself (the fstab-generated unit cannot precede it: the mapper device does not exist until this unit's cryptsetup). A boot ≥2 with `reopen_ok` and NO `reopen_mount` is fine iff `/mnt/data` was already mounted from the mapper — the silent fast path.

Incident that motivated it: iid 170091264 (first replace of the day) — `pointer_device_wait` FATAL at the 30 s bound while the attachment took ~80 s; reopen opened the mapper but could not mount; Redis refused (`not a mountpoint`); `bootstrap-done-DEGRADED`; `op=resume` G4 refused; healed only by a second replace (iid 170097260). Both readers now carry a counted 300 s bound (timeout-wrapped probe, one post-loop `udevadm settle`, post-settle re-probe) and the reopen self-heals the mount, so a lost race converges on the same boot — and any later boot heals the 170091264 shape outright.
