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

---

## 5a. After a sanctioned `op=luks-rollback`: revert the record

> **Rollback ends at the `detach` phase of the backstop retirement (#8285, see §5b), or at the first
> Inngest host replace after PR A merges, whichever comes first.** Once
> `apply_target=inngest-backstop-retire phase=detach` has run, the plaintext volume
> `hcloud_volume.inngest_redis` (id 106261946) is no longer attached to the Inngest host, and
> `op=luks-rollback` has nothing to copy back from: its on-host path refuses with
> `reason=rollback-no-backstop` (the plaintext device is absent; the refusal is pinned by a fixture in
> `apps/web-platform/infra/inngest-luks-cutover.test.sh`). The same holds after a host replace even
> before `detach`: PR A removes the attachment declaration, so a replaced host boots without the
> backstop attached. From that point there is no rollback and the live LUKS volume is the only copy of
> the store. Everything below applies only while the backstop is still attached. The operator verb
> itself stays listed until the convergence PR (PR B of #8285) retires it.

The store is back on `hcloud_volume.inngest_redis`, which is now the **LIVE store: do NOT destroy
it**, and do not act on #8285's expiry until the store is re-cut. A rollback makes no commit, so the
record it falsifies is reverted in one PR. An agent can do every step; none needs a console.

1. **Confirm the store moved.** The newest `host_role=dedicated` `SOLEUR_INNGEST_SERVER_PROBE` row
   emitted by `inngest-server-probe`
   reads `data_mount_src` other than `/dev/mapper/inngest-redis` (§5 step 1's query). The property
   probe reports this as `rollback_inversion` on #8285, and the wrong-volume alert pages on it.
2. **Re-pause the wrong-volume alert** with the Doppler override described in §5 step 2
   (`INNGEST_LUKS_CUTOVER_COMPLETE=false` in `soleur/prd_terraform`, then the manual-rerun apply).
   This is a production write: it needs the operator's per-command go-ahead.
3. **Revert the ledger row.** Take `hcloud_volume.inngest_redis_luks` back to its pre-flip shape,
   which is recoverable verbatim from the parent of the #8296 PR-2 merge commit:

   ```
   git show <pr2-merge-sha>^:scripts/encryption-posture-ledger.json \
     | jq '.stores[] | select(.store == "hcloud_volume.inngest_redis_luks")'
   ```

   Restore `mechanism: plaintext-exception` with that `exception` block (update `reassessed_on` and
   append the rollback to `justification`), then run
   `python3 scripts/lint-encryption-posture.py --repo-sweep` (must print `0 failing checks -> PASS`).
4. **Answer the three `[2026-09-21 AMENDMENT (#8296)` cells** in
   `knowledge-base/legal/article-30-register.md` (PA-21 §(f), PA-22 §(f), PA-13 §(e)) with a new
   dated bracket appended to each, never by deleting text:
   `**[<date> AMENDMENT (#<issue>): a sanctioned op=luks-rollback on <date> returned the store to
   the plaintext volume hcloud_volume.inngest_redis; the #8296 amendment recorded above in this
   cell no longer holds.]**`
5. **Update the two other records:** `platform.infra.inngestRedis` in
   `knowledge-base/engineering/architecture/diagrams/model.c4` (then
   `bash scripts/regenerate-c4-model.sh`), and an appended amendment to ADR-142.

---

## 5b. Retiring the backstop (#8285)

**Status of this section: the dispatches below exist once PR A of #8285 has merged. Until each phase
has run and its read-back is recorded in
`knowledge-base/legal/audits/inngest-aof-backstop-destruction-record.md`, the backstop volume still
exists.** Ref #8285, Ref #6894.

**What this does.** Retires the plaintext backstop `hcloud_volume.inngest_redis` (Hetzner id
**106261946**, ext4) before its ledger exception expires on **2026-10-22** (pinned, not extendable).
The live store on `hcloud_volume.inngest_redis_luks` (id **106903269**) is never touched. Four phases of
one reviewer-gated dispatch, no SSH, no manual Doppler write, no `[ack-destroy]` (that route cannot
reach these addresses). Design: ADR-142 addendum 2026-10-08, refined by its 2026-10-09 addendum.

| Phase | What it does | Terraform change |
| --- | --- | --- |
| `detach` | Detaches 106261946 from the Inngest host. **Rollback ends here.** | one delete: `hcloud_volume_attachment.inngest_redis` |
| `wipe` | Creates a throwaway server, attaches the volume to it, zeroes it, reads it back, posts an evidence row, then tears the server down | step A: two creates (wipe server and attachment); step B (runs even if A failed): any subset of the two matching deletes |
| `teardown` | Step B of `wipe` alone, for a leaked wipe server | any subset of those two deletes |
| `destroy` | Deletes the volume; state converges in the same apply | one delete: `hcloud_volume.inngest_redis` |

**Every phase is a production write.** Show the exact command to the operator, wait for a go-ahead
that names it, then dispatch. The dispatch then holds in **Waiting** until a reviewer approves the
`inngest-cutover` environment (the sole human authorization; `confirm` is a typo guard only). Each phase
is idempotent: it reads Hetzner first and exits green without planning if its post-condition already
holds, so a retry after a partial apply is safe. After every phase (pass or fail) a step comments on
#8285 with the run URL, the read-back and the days remaining to 2026-10-22 (past it, how many days
overdue). A dispatch waiting for approval produces no comment, and nothing else posts a days-to-expiry
line in that interval (the property probe's daily comment has none), so the reminder is the operator's
to keep while it waits.

### Target dates

PR A merged by 2026-10-12; `detach` by 2026-10-13; `wipe` by 2026-10-15; **decision point 2026-10-17**
(below); `destroy` by 2026-10-17 (or the D4 path by 2026-10-19); PR B merged by **2026-10-21**. The real
deadline is PR B merged, not the destroy: the encryption-posture lint fails an expired exception on
2026-10-22 whether or not the volume is gone, and PR B may not merge before the 404 read-back.

### Operator prerequisites before the first dispatch (known gaps, accepted)

1. **No wipe rehearsal exists.** The first `wipe` dispatch is the first run of the wipe host script
   against real hardware. Rehearsing it would need a dry-run input threaded through cloud-init,
   Terraform, `variables.tf`, the workflow and their tests, which was weighed and not built (see
   `decision-challenges.md`, 2026-10-09). The script's identity guards (listed under "When the wipe does not go green") refuse before
   any write, so a refusal by one of them costs one approval cycle, not data. Three guards fire only
   after the write has begun, and those can leave the device partly zeroed. Record "none: no rehearsal path exists" in the
   destruction record.
2. **No key or header continuity proof exists.** Nothing here proves, before the backstop goes, that
   the LUKS header and the Doppler key `INNGEST_REDIS_LUKS_KEY` still open the live volume at rest.
   The only evidence is that the running host serves from it (the probe row on `scsi-0HC_Volume_106903269`
   and `/dev/mapper/inngest-redis`). There is no SSH-free channel to open the header, and the gap is
   older than this work (ADR-142). The operator accepts it knowingly before `detach`, because after
   `detach` there is no rollback.
3. **First measurements (UNMEASURED until the first real `wipe` run).** The 10 GiB size, the by-id
   device naming (`scsi-0HC_Volume_<id>`), the 300 s wait for the device link and the on-host duration
   have never run against a real Hetzner volume. The expectation is a few minutes on the host (an
   estimate of 4 to 10 minutes, not a measurement), inside a 20-minute wall-clock poll. A fifth
   assumption is just as unmeasured: **the guest hostname equals the server name
   `soleur-inngest-backstop-wipe`**. The evidence funnel pins the row's `host` to that name and its
   `shipper` to `inngest-backstop-wipe`. If the hostname differs, the wipe itself completes but every
   row reads `emitter_mismatch`: the poll then prints the observed `host` and `shipper` and fails, and
   the later `destroy` would refuse the same way. The remedy is a reviewed change to the pin, not a
   bypass; the D4 path (below) is the fallback if the date is near. Copy what the first run shows into
   the destruction record.
4. **Terraform version.** The orphan-address `-target` plans were checked on Terraform **1.9.8** (a
   local-backend experiment: plan `-target` on the attachment shows only the attachment delete; on the
   volume only the volume delete). CI pins **1.10.5** (`TERRAFORM_VERSION`). **Re-run that experiment on
   1.10.5 on a local backend before the first dispatch** and record the result in the destruction
   record. If the chain behaves differently the plan-shape gate aborts with no mutation, so the cost of
   being wrong is a wasted approval, not a wrong delete.

### Precondition for every phase: the live store is healthy (read-only)

For `detach`, `wipe` and `destroy` the workflow proves the first three items before it plans anything;
read them yourself first, from the host's own telemetry (§5 step 1 for the probe query). **`teardown`
skips both the live-store gate and the untargeted plan** (item 4): a leaked wipe server must always be
cleanable, even when the store looks unhealthy, and teardown can only delete the two wipe addresses (its
targeted plan is still graded exactly, including the wipe server's pinned name and physical id).

1. Doppler `soleur-inngest/prd`: `INNGEST_LUKS_CUTOVER` reads `done` (never `rollback`, `rolled-back`,
   `armed` or `copying`) and `INNGEST_LUKS_ACTIVE_VOLUME_ID` reads `106903269`.
2. The newest `host_role=dedicated` `SOLEUR_INNGEST_SERVER_PROBE` row (emitted by
   `inngest-server-probe`) is under 3 hours old with `data_mount_devid=scsi-0HC_Volume_106903269` and
   `redis_active=active`. This probe row is the proof that the live volume is mounted and serving.
3. No other apply runs alongside. This is **not** a gate check: the workflow-level concurrency group
   `terraform-apply-web-platform-host` (`cancel-in-progress: false`, shared with
   `apply-deploy-pipeline-fix.yml`) queues a second run behind the first. An earlier draft also polled
   the Actions API for in-flight runs; that check was unpinned and fail-open and was removed, along with
   a duplicate Hetzner attachment cross-check (`decision-challenges.md`, 2026-10-09, round 2).
4. An untargeted read-only plan of the whole root is the proof that the host is untouched. It requires
   that `hcloud_server.inngest` and the two LUKS resources each appear as exactly one **no-op** entry
   (absence proves nothing); that no entry with a create, update, delete or forget carries the live
   volume id 106903269; that the **web-1 set** (server, volume, attachment) and the **LUKS key pair**
   (`random_password.inngest_redis_luks`, `doppler_secret.inngest_redis_luks_key`) show no action; and
   that any entry for the retired or wipe addresses is within the phase's authorized set. Entries for
   other unrelated resources are ignored in this untargeted plan, so unrelated drift does not block a
   phase; the targeted plan that follows stays exact.

If any of these fails, stop and read the cause; do not dispatch around it.

### Phase 1: `detach`

```
gh workflow run apply-web-platform-infra.yml --ref main -f apply_target=inngest-backstop-retire -f phase=detach -f expected_inngest_volume_id=106261946 -f confirm=RETIRE-INNGEST-BACKSTOP -f reason='#8285 detach plaintext backstop'
```

Gate: the targeted plan has exactly one non-no-op change, a delete of
`hcloud_volume_attachment.inngest_redis` whose `before.volume_id` is 106261946, and the server shows no
action (this is the first proof, on live state, that the cloud-init template pin leaves the host
alone). The phase reads Hetzner before it plans: if the volume already shows `server: null` (or is
gone), it skips the plan and apply, which covers an attachment left stale by a routine host replace;
a stale attachment entry still in state is then dropped by a gated state-only reconcile (below).
**Read back:** Hetzner `GET /v1/volumes/106261946` shows `server: null`.

**State-only reconcile.** Where Hetzner says the object is gone but state still lists its address, the
phase runs a single-address refresh-only apply and then compares `terraform state list` before and
after: the difference must be exactly that address (for `detach` with the volume already gone from
Hetzner, exactly the attachment and the volume), or the phase fails with no further action. **That
comparison is detective, not preventive.** The refresh-only apply has already written state when the
comparison runs, and a dependency the provider reads as gone can be dropped before the check fires. If
the check fails, do not edit state by hand: read the state list, re-plan (re-dispatch the phase, whose
convergence read starts from the state as it now is) and compare against Hetzner. A preventive,
plan-gated reconcile was weighed and not built (`decision-challenges.md`, 2026-10-09, round 2).

### Phase 2: `wipe`

```
gh workflow run apply-web-platform-infra.yml --ref main -f apply_target=inngest-backstop-retire -f phase=wipe -f expected_inngest_volume_id=106261946 -f confirm=RETIRE-INNGEST-BACKSTOP -f reason='#8285 wipe plaintext backstop'
```

Step A creates the throwaway server and attaches only volume 106261946 (the gate pins
`after.volume_id` to 106261946, never 106903269). The job passes its own run id as the nonce and polls
Better Stack, up to a 20-minute wall-clock deadline, for a row with that nonce, `result=wiped`,
`volume_id=106261946` and the expected size, posted by the wipe host's pinned emitter. The deadline is
20 minutes, capped so that teardown and the read-back still fit inside the job's timeout. A `refused`
row for the nonce ends the poll at once and names its guard; so does any other genuine rejection of the
rows that exist for the nonce (wrong emitter, volume or time), which is printed with its reason (for a
wrong emitter, the observed `host` and `shipper`); an absent row fails the job rather than passing it.
Everything the poll prints from Better Stack is stripped to printable characters first, so a row cannot
inject log commands. Step B then removes the throwaway server whether or not the poll passed.
**Read back:**

```
doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh \
  --since 3h --grep SOLEUR_INNGEST_BACKSTOP_WIPE --limit 50
```

Expect `result=wiped readback=zero sig_after=none`, the run's nonce, `volume_id=106261946` and the
volume's exact `size_bytes`. A `result=refused` row names the guard that stopped it. **A refusal does
not always mean the volume is untouched**: see the two guard classes in the triage section below. What
the `wiped` row does and does not prove is stated once, in the destruction record ("What the evidence
does and does not show", as amended 2026-10-09 and again in round 2); repeat it from there, not from
memory. Then confirm the wipe server is gone and the volume is detached again (commands under
"Verification" below).

**If a wipe server is left behind** (the job died between steps), dispatch the same command with
`-f phase=teardown`. **"Wiped but never destroyed" is a defined state:** the volume is zeroed, detached
and rollback is gone; the next move is `destroy`, not a retry of `wipe`.

#### When the wipe does not go green: triage

Every read below is self-pullable (Better Stack query as above, or a read-only Hetzner `GET`); none needs
a shell on any host. Before any re-dispatch of `wipe`, query Better Stack once more for the nonce: a
slow host can post a `wiped` row after the poll has already given up.

**Two classes of `refused` row.** The row's `reason=` names the guard, and the guard decides what you
may assume about the volume:

- **Pre-write guards** refuse before the script has touched the device, so the volume is as it was:
  `config_invalid`, `config_id_mismatch`, `device_absent`, `device_unresolved`,
  `other_volume_attached`, `not_whole_disk`, `size_mismatch`, `mounted`, `has_children`,
  `sysfs_absent`, `has_holders`, `luks_signature`, `type_not_ext4`. (The script runs its identity
  guards twice, once before the `started` row and once again before the write; a refusal by the second
  run is still pre-write.)
- **Post-write guards** fire after the zeroing has begun: `zero_failed` (the discard command failed;
  it may have written part of the device), `readback_nonzero` (the read-back found non-zero bytes) and
  `sig_survived` (a filesystem signature is still readable after the zero). After one of these the
  device **may be partially zeroed, the rollback is gone, and the volume is not intact**. Re-dispatch
  `wipe`: the script re-enters, and a device that now reads as blank or ext4 goes through the zero and
  read-back again. If it refuses `type_not_ext4` on such a device, stop and ask the operator; do not
  improvise.

| What you see | What it means | Read | Next move |
| --- | --- | --- | --- |
| A `result=refused` row for the nonce | A pre-write guard stopped the script and the volume is untouched; a post-write guard (`zero_failed`, `readback_nonzero`, `sig_survived`) fired after the write began and the device may be partially zeroed | the row's `reason=` (guard name; classes above) | Pre-write: fix the named cause; the teardown step already ran; re-dispatch `wipe`. Post-write: the rollback is gone; fix the cause and re-dispatch `wipe` (it re-enters) |
| Only a `result=started` row, no `wiped` or `refused` | The host proved it can post evidence, then ended or was still working at the deadline; a partial zero is possible (the job's error says the device may be partially zeroed) | Better Stack for a late `wiped` row; Hetzner server listing for a surviving wipe host | Wait out a live host, then query again; if none arrives, `teardown` then re-dispatch `wipe` (zeroing twice is harmless; an already-blank device takes the `prior=blank` path). Never `destroy` on a `started` row |
| No row at all | The host never booted, cloud-init failed before the script, egress or the ingest token failed, or the script could not deliver its `started` row (it then writes nothing and exits, so the volume is untouched) | Hetzner server listing and status for the labelled server; Better Stack for any row from that host | `teardown`, then re-dispatch `wipe`. A kernel or cloud-init failure before the script runs leaves no row by construction; repeated empty runs are a reason to raise the D4 decision before 2026-10-17 |
| Rows exist but every one reads `emitter_mismatch` | The pin did not match what the wipe host sent: the guest hostname differs from `soleur-inngest-backstop-wipe` or the shipper differs (an unmeasured first-run assumption). The poll output shows the observed `host` and `shipper` | the poll's printed values; the Better Stack rows | The wipe may well have completed (check the row's `result=`); the remedy is a reviewed change to the pin; the D4 path is the fallback if the date is near |
| Job red, evidence fine | A step after the poll failed (teardown or read-back) | the failed step's log; Hetzner for a surviving wipe host | `phase=teardown` converges; do not re-run the zero |
| Job red and `teardown` also refuses or finds nothing, yet a labelled server exists in Hetzner | The wipe host is absent from Terraform state, so no gated phase can remove it | `GET /v1/servers?label_selector=role%3Dinngest-backstop-wipe` | Delete that server by id through the Hetzner API with the privileged token held by the operator tooling (a production write: show the exact call and wait for a named go-ahead). Hetzner detaches the volume with the server. Then dispatch `phase=teardown` to clear any stale state entry, and re-dispatch `wipe`. The workflow does not do this itself |

A leaked wipe server costs roughly EUR 0.03 per hour (an estimate), so a leak is a nuisance, not an
emergency, but it blocks every later phase until it is gone.

### Phase 3: `destroy`

```
gh workflow run apply-web-platform-infra.yml --ref main -f apply_target=inngest-backstop-retire -f phase=destroy -f expected_inngest_volume_id=106261946 -f confirm=RETIRE-INNGEST-BACKSTOP -f wipe_run_id=<run id of the wipe dispatch> -f reason='#8285 destroy plaintext backstop'
```

Preconditions beyond the live-store check, proved in the run log before any plan: a `wiped` evidence
row exists whose nonce equals `wipe_run_id`, posted by the pinned emitter, with matching volume id and
size, and Hetzner's own action history for the volume corroborates it. The corroboration is
specific. The time floor is the later of the wipe run's start and the finish of the latest successful
`attach_volume` of 106261946 to the live Inngest host (169426216), if any. A successful `attach_volume`
to a server that is neither the live host nor absent must have finished after that floor; no attach to
the live host may have finished after it; the `wiped` row's Better Stack ingest time must fall between
that attach's finish and the first later successful `detach_volume`'s finish, with 300 s of slack either
side; and no live attachment of 106261946 exists. **What this proves and does not:** Hetzner records an
attach and a later detach of the volume by a non-live server. That corroborates that a host held the
volume; it does not corroborate that the overwrite happened. The erasure remains self-attested, and a
holder of the shared ingest token can still forge a row that sits inside a real attach-to-detach
window. Gate: exactly one delete, `hcloud_volume.inngest_redis`, `before.id` equal to 106261946;
everything else no-op. Terraform deletes the Hetzner volume and drops the state entry. If Hetzner
already answers 404 and state still lists the address, the phase runs the gated state-only reconcile
for that one address (see Phase 1). A query that fails prints its exit code and the first part of its
stderr (printable characters only) instead of reading as "no rows".

If `destroy` aborts because a stale orphan attachment for 106261946 is still in state, or a wipe host
exists in Hetzner but not in state, re-dispatch `detach`, or delete the labelled server by id (triage
table above), then retry; the abort message names which.

### Decision point: 2026-10-17 (D4)

If the `wipe` phase has not succeeded by **2026-10-17**, stop and ask the operator for a decision; do not
choose silently. A provider delete without zeroing is defensible only as a CLO-attested downgrade
("provider delete only, no overwrite, logical erasure not evidenced by read-back"), and it beats an
expired non-extendable Art. 32 exception. The attestation is a **two-person** record on #8285: the
comment has to be written by someone other than the person who dispatches the destroy. Before the
destroy dispatch, the CLO (or another repository owner or member) posts a comment on issue #8285 with
all of these properties:

1. **First line exactly** `CLO-ATTESTATION erasure=provider-only volume=106261946` (nothing before or
   after it on that line, except one trailing carriage return, which the GitHub web editor stores),
   followed by the attestation text, which names volume 106261946. A comment that lacks the volume id
   is refused (`clo_body_missing_volume`) before the marker is checked.
2. **Unedited.** The comment's `created_at` equals its `updated_at`. An edited comment is refused; to
   change the text, post a new comment and use its id.
3. **A human user.** The comment's author has type `User` (a bot or GitHub App comment is refused) and
   an `author_association` of `OWNER` or `MEMBER` (`COLLABORATOR` is not enough).
4. **A different login from the dispatcher.** The workflow compares the comment author's login with
   the login of the actor who dispatched the run; equal logins are refused. If the organization has no
   second owner or member, this path is unavailable and the operator must say so at the decision point.
5. **On issue #8285**, with the exact URL shape below.

The destroy dispatch then replaces `wipe_run_id` with:

```
gh workflow run apply-web-platform-infra.yml --ref main -f apply_target=inngest-backstop-retire -f phase=destroy -f expected_inngest_volume_id=106261946 -f confirm=RETIRE-INNGEST-BACKSTOP -f erasure=provider-only -f clo_attestation_ref=https://github.com/jikig-ai/soleur/issues/8285#issuecomment-<comment id> -f reason='#8285 destroy plaintext backstop, provider delete only'
```

The gate accepts only that exact URL shape, fetches the comment through the GitHub API, and checks every
property above; any other reference, on any host, is refused. There is no third way past the
precondition. The destruction record uses its "provider delete only" wording.

### Verification after `destroy` (read-only, a hard exit criterion)

```
doppler run -p soleur -c prd_terraform -- sh -c ': "${HCLOUD_TOKEN_READONLY:?absent from prd_terraform: stop, never fall back to HCLOUD_TOKEN}"; curl -sS -o /dev/null -w "%{http_code}\n" -H "Authorization: Bearer $HCLOUD_TOKEN_READONLY" https://api.hetzner.cloud/v1/volumes/106261946'
```

Expect `404` (it is `200` before `destroy`). The same token form reads
`GET /v1/servers/169426216` (`.server.volumes` must be `[106903269]`) and
`GET /v1/servers?label_selector=role%3Dinngest-backstop-wipe` (no server). Also: a read-only untargeted
plan lists neither retired address; the next `host_role=dedicated` probe row still reports
`/dev/mapper/inngest-redis` on 106903269 with `redis_active`; the wrong-volume alert is quiet **and** a
fresh probe row is present (an absent alert alone proves nothing, because a silent probe reads as
healthy); Hetzner snapshots and backups for the volume are still 0. Record the `destroy` apply
completion time and the time of the first 404 in the destruction record. The workflow's read-back step
runs even when an earlier step failed, so its output exists for a red run too. It also runs on the
shortcut where Hetzner already answers 404 (so a record exists), and when the precondition refused and
no destroy was attempted it says "destroy not applied" instead of reporting a failed destroy.

### The window between PR A's merge and `destroy`

- The two removed Terraform addresses are state-only orphans, so the scheduled drift plan (twice daily,
  06:00 and 18:00 UTC) reports two deletes and comments on the infra-drift issue. That is expected and
  clears when the phases finish. Do not apply it.
- **Never run an untargeted `terraform apply` of the root until the `destroy` phase has completed**: it
  would delete both orphans unwiped. No CI path does so, and any HALT or error text that suggests an
  operator-run untargeted apply does not apply in this window; do not follow it. Do not add a path by
  hand. (The orphans are plain state entries with no declaration, so a Terraform-level guard would
  need a new resource; none is added, and this paragraph is the control.) The two places that print an
  operator-apply prescription, the per-merge apply's `luks_key_touched` text and the scheduled drift
  plan's next-steps text, carry the same qualifier: never untargeted while the retired volume or its
  attachment is still in state; add `-target` for each planned address.
- Do not dispatch `inngest-host`, `inngest-host-replace` or any host rebirth in the window. A host
  replace after PR A also ends the rollback (§5a banner).
- Do **not** close either tracker (#8285, #6894) before the 404 read-back, and do not retire the property probe before
  it either (§5 step 4). The convergence PR carries `Ref #8285` only; the trackers are closed
  explicitly afterwards with the PR link, the run URLs and the 404 read-back.
- After retirement the live LUKS volume is the only copy of the store and `INNGEST_REDIS_LUKS_KEY` in
  Doppler `soleur-inngest/prd` is its sole opener (ADR-142 addendum 2026-10-08).

### Records the convergence PR must carry

The checklist is owned by the destruction record
(`knowledge-base/legal/audits/inngest-aof-backstop-destruction-record.md`, "Addendum 2026-10-09",
"Completion checklist for PR B, extended") and mirrored as tasks in the feature spec. Two operational
points live here because they gate a deletion:

- **Do not delete `scripts/followthroughs/inngest-luks-property-8296.sh` until the dead-probe heartbeat
  feeder (#9703) is armed.** That script is the only reporter that says "CANNOT ESTABLISH" for a silent
  probe pipeline; the wrong-volume alert reads a silent probe as healthy until the feeder is wired.
- **Days-to-expiry note (pre-deletion).** The property probe's daily comment has no days-to-expiry
  line, so while a dispatch waits for approval nothing unprompted tells the operator how long is left.
  PR A does not edit the probe, so this is not a PR A deliverable: the operator keeps the reminder
  until PR B deletes the probe, and PR B's pre-deletion checklist records that no such line was ever
  added.
- **PR B merges only after the 404 read-back is recorded**, and its squash message carries no closing
  keyword next to #8285 or #6894 (the property probe is notify-only for exactly this reason, see commit
  7f7d9c3d9b; §5 step 4 explains why the tracker stays open until the destroy).

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
  if the pointer is absent (nothing to roll back) or the flag is anything else. It also needs the
  plaintext volume attached, so it is no longer available once the `detach` phase of §5b has run.

---

## Related

- ADR-142 (+ its 2026-09-18 amendment) — why additive, why a pointer, why a separate flag.
- ADR-199 — the empty-store world, where the destructive recut is lawful instead.
- `knowledge-base/engineering/operations/runbooks/inngest-server.md` — the host itself.
- `betterstack-log-query.md` — the standing alarms over this source, including the wrong-volume alert.
