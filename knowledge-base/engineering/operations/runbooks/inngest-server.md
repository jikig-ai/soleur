# Runbook: Inngest server (self-hosted on Hetzner)

Operator-facing runbook for the self-hosted Inngest server provisioned by `apps/web-platform/infra/inngest.tf` and `inngest-bootstrap.sh` (PR-F follow-up, #3960).

Per ADR-030 the Inngest server runs as a single-host durable trigger layer serving `:8288` (event ingestion) and `:8289` (admin API). **This intro previously said "SQLite-backed" and "bound to `127.0.0.1`" and both were stale — see ADR-030's 2026-06-17 and 2026-09-03 amendments.** CORRECTED 2026-09-03 (#7695, CLO determination): the socket-bind claim was true at authoring and ceased to be true on 2026-05-19 (#4017) — the bridge-networked `soleur-web-platform` container cannot register its SDK against a loopback-bound server, so `inngest-bootstrap.sh`'s ExecStart binds `--host 0.0.0.0` unconditionally. The conclusion survives on three different controls: a zero-rule deny-all `hcloud_firewall.inngest` on the public interface, a host-local nftables chain scoping `:8288`/`:8289` to the web hosts' private addresses, and — the one that actually restricts the personal-data-bearing surface — Inngest's own software gating of `/v1/*` to loopback-origin requests, measured 2026-05-31 (#4708) and independent of the bind. The rest of this file already described the current posture; only this opening sentence did not. On the same Hetzner host that runs the Web Platform. The CFO autonomous-draft pipeline (#3940) emits events to this server via `apps/web-platform/server/inngest/client.ts`.

> **Correction 2026-09-25 (#8754):** Of the three controls named above, the first (the zero-rule deny-all `hcloud_firewall.inngest`) was not attached to the host in service when that paragraph was written. It was also unattached for most of the period since the first scoped host replacement on 2026-07-09: from 2026-07-09 to 2026-07-31, from 2026-08-12 to 2026-09-09, and from 2026-09-09 to at least the 2026-09-25 measurement. Once the change tracked in #8754 merges, the binding lives on `hcloud_server.inngest.firewall_ids`, and the host in service gains it at its next `inngest-host-replace`. Until the post-replace check passes, treat these as the controls in force: the host-local nftables chain (`:8288`/`:8289` only) and Inngest's `/v1/*` loopback gating. Treat TCP 22 as reachable from the internet. **Post-replace check (Hetzner API, no SSH):** the new server's `public_net.firewalls` lists 11269127 with status `applied`, and firewall 11269127's `applied_to` lists that server's id. After that check passes, append a dated "restored" marker here and at the records listed in `knowledge-base/legal/audits/2026-09-25-8754-inngest-cloud-firewall-determination.md` (§Post-replace verification).

> **Restored 2026-09-27 (#8754):** The post-replace check passed. `inngest-host-replace` run 36327637204 created server 167651172 at 2026-09-27T14:56:48Z with the firewall applied at creation, and deleted server 167310350. Measured through the Hetzner API at about 15:02Z: server 167651172's `public_net.firewalls` lists 11269127 with status `applied`, and firewall 11269127's `applied_to` lists 167651172. TCP connects to the new public address on 22, 8288 and 6379 time out (dropped, not refused). The cloud-firewall control named in the intro is measured in force again, so stop treating TCP 22 as reachable from the internet. The host-local nftables chain and the `/v1/*` loopback gating are installed by design on every host; their load on server 167651172 was not separately measured. The record is the 2026-09-27 addendum of `knowledge-base/legal/audits/2026-09-25-8754-inngest-cloud-firewall-determination.md`.

## Quick reference

| Concern | Procedure |
|---|---|
| First-time bootstrap | [§ Fresh-host bootstrap](#fresh-host-bootstrap) |
| Heartbeat-miss alert | [§ Heartbeat triage](#heartbeat-miss-triage) |
| Key rotation (signing or event) | [§ Key rotation](#key-rotation) |
| Inngest CLI version bump | [§ Version bump](#cli-version-bump) |
| FR5 flag flip | [§ FR5 flip](#fr5-flag-flip) |
| Unpause heartbeat after first ping | [§ Unpause heartbeat](#unpause-heartbeat) |
| Cron bug-fixer manual trigger | [§ Cron bug-fixer](#cron-bug-fixer) |
| Fire any cron on demand | [§ On-demand cron trigger (HTTP)](#on-demand-cron-trigger-http--primary) |
| Dedicated-host cutover (#6178) | [§ Dedicated-host cutover](#dedicated-host-cutover-phase-2-opexecute-gated-sequence--ref-6178) |
| Read ANY host/unit state | [§ Reading host state without SSH](#reading-host-state-without-ssh) |
| Scheduler dead after a host replace | [§ Inherited `done`](#inherited-done-after-a-host-replace-7228) |
| Link TLS: flag, flip, rollback, post-merge acts A0 to A7, replace duration, reading `tls-health`, certificate expiry (#10136) | [§ Link TLS (#10136)](#link-tls-10136) |
| Private-NIC boot event after a host replace (#8539) | [§ Reading the private-NIC boot event](#reading-the-private-nic-boot-event-8539) |
| `inngest_pull_fatal attempt=N` / provision-unit stages after a host replace (#8562) | [§ Provision unit (#8562)](#provision-unit-8562) |
| Flush latch stands on a `done` host / `op=arm` refused at G3.7 | expected — [§ Dedicated-host cutover](#dedicated-host-cutover-phase-2-opexecute-gated-sequence--ref-6178), G3.7 post-cutover status |
| Deliberate SECOND FLUSHALL on the same host (#7777) | `gh workflow run cutover-inngest.yml -f op=reflush` — [§ Authorizing a second FLUSHALL](#authorizing-a-second-flushall-opreflush-7777) |
| First boot or reboot fails with `stage=unpointed_raw_refused`, `reopen_not_luks` or `inngest-luks-FAILED` (after the #9786 host replace) | read the stage and its `detail=` in Better Stack ([log query](betterstack-log-query.md)); meaning of each refusal: [cutover runbook, "After the host replace that carries #9786"](inngest-luks-cutover-6894.md) |
| Choosing rollback on a `done` host | one-way on this volume — [§ Rollback sequence](#rollback-sequence-p1-13--mirrors-the-forward-gate-stop-the-dedicated-host-first), then the G3.7 post-cutover status |

## Inherited `done` after a host replace (#7228)

**Symptom.** An `apply_target=inngest-host-replace` succeeds, the server is `running`, the AOF
volume is preserved — and `inngest-server` never starts. The probe reads
`server_active=activating http_code=000` indefinitely, and the host journal carries:

```
BLOCK: cutover flag='done' but this host carries no done-owner marker at
/var/lib/inngest-cutover/done-owner — refusing a prod start on an INHERITED done (#7228)
```

**This is not a malfunction.** `INNGEST_CUTOVER_FLIP` lives in Doppler and **outlives the host**;
the matching `done-owner` marker lives on the **root disk**, which a replace destroys. The new
machine therefore inherits a `done` it never earned, and the flip guard refuses rather than risk
running a **second** prod scheduler. It follows that **every** host replace strands the scheduler
while the flag is `done` — it is deterministic, not a flake, so retrying the replace cannot fix
it. **Retrying is the trap**: "same image, same cloud-init, same volume, so it must be transient"
is the reasoning that produced a second stranded host on 2026-09-17.

`apply-web-platform-infra.yml`'s `inngest_host_replace` job reads the flag before applying and,
on `done`, emits a `::warning::` and writes the recovery below into the job summary. It does not
block — the replace is often exactly what you want and the recovery is one dispatch — and it
degrades open on an unreadable flag.

**Recovery — one dispatch, then an approval, no data loss:**

```
gh workflow run cutover-inngest.yml -f op=resume
```

> **The run then HOLDS in `Waiting` until a human approves it.** `op=resume` writes a flag that
> authorizes a prod scheduler start, so its job declares `environment: inngest-cutover`
> (`cutover-inngest.yml:78`) and that environment carries a required reviewer — verified
> 2026-09-17, the reviewer set is non-empty. **No step executes before the approval**, so a
> dispatch that appears to produce nothing has not failed; it is waiting for you. Ask the
> operator to approve it in the Actions UI, and confirm the state with:
>
> ```
> gh run list -w cutover-inngest.yml -L 1
> ```
>
> Recorded because the previous wording — "one dispatch, no data loss" — is what an engineer
> reads mid-outage, and an unexplained `Waiting` invites a second remediation on top of a
> recovery that is already in flight.

`op=resume` exists for exactly this state. Its G1 requires the flag to be `done` (only that
evidences a completed flip), G3 requires the host to be audible, G4 (#9177) requires the current
host generation's `bootstrap-done` — the same check the probe reports as `verdict=PASS` — and it
then writes `INNGEST_CUTOVER_FLIP=flushed`. The on-host 30s timer takes the post-flush arm: start → verify it
SERVES → re-record the marker → complete to `done`, **with no re-FLUSHALL**, so the queue
survives. Confirm by the FSM row `reason="flushed-resume-no-reflush"` followed by a return to
`noop-done` — read it with:

```
doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh \
  --since 30m --grep inngest-cutover-flip --raw-only --limit 20
```

**G3 is a live precondition, not a formality.** It requires the host to be audible on Better
Stack **from the current server**: only rows stamped AND ingested after that server's Hetzner
`created` time count, so a destroyed predecessor with the same name never satisfies it (the
2026-09-24 replace: the old server's rows made G3 pass before the new one shipped anything —
ADR-225 §4 amendment). A *freshly replaced* host is therefore not audible until its own Vector is up
and shipping. If `op=resume` refuses on G3, read the run log's generation notice before acting:

```
::notice::inngest-cutover-flip liveness scoped to server soleur-inngest created <iso> (<age>s ago): rows=<R> counted=<C> host_pair=<N> pre_floor=<P> malformed=<M> skew_suspect=<K>
```

(The LUKS gate prints the same line labelled `inngest-luks-cutover liveness`.)

- `rows` — decoded rows the query returned, from any host. The read keeps the newest 50 in the
  15-minute window, so `rows=50` means the window was truncated and the older counters are lower
  bounds.
- `counted` — rows from the current server. G3 passes when this is above 0.
- `host_pair` — rows matching both `host` and `host_name`, from any server generation.
- `pre_floor` — well-formed host-pair rows that fail either clock. It **includes** `skew_suspect`,
  so `pre_floor − skew_suspect` are the predecessor's rows.
- `skew_suspect` above 0 — rows ingested after `created` but stamped before it: the current
  server IS shipping and its clock is behind. It self-heals once the clock passes `created`;
  re-dispatch then.
- `malformed` above 0 — host-pair rows without a parseable event time or `dt`: a Vector or
  warehouse schema change. File an issue with the run URL.

When `counted=0`, the log carries at most one `::warning::` saying why, and each says **do NOT
replace it**: `skew_suspect > 0` (check the host's NTP sync), `malformed > 0` (schema change), or a
server under 600s old (`WAIT and re-dispatch`). **Believe it**: a replace resets `created` and the
wait starts over. Wait for the host to start shipping (read it with `scripts/inngest-host-state.sh`)
and re-dispatch. Only a server more than 600s old with `counted=0`, `skew_suspect=0` and
`malformed=0` is a candidate for an `inngest-host-replace`.

When G3 refuses `unreadable`, the `::warning::` above it names the read that failed: Better Stack
(`BETTERSTACK_QUERY_*` in `prd_terraform`), the **Hetzner generation anchor**, or the local row
filter (a jq fault — file an issue). The anchor's classes:

- **re-dispatch later is enough:** rate-limited (429), Hetzner outage (5xx), transport fault, or no
  server named `soleur-inngest` in the token's project (a replace in flight — re-dispatch once it
  exists);
- **re-dispatching does nothing until the cause is fixed:** the Doppler token read returned nothing,
  the token was rejected (HTTP 401/403 — the warning names `HCLOUD_TOKEN_READONLY`), or `created` is
  out of bounds.

When G4 refuses, the `::error::` names which outcome the provisioning probe reported
(`bootstrap-done-DEGRADED` is never a pass; `not-delivered` on a host life that predates the
provision unit means replace, not resume) and the probe's per-stage detail lines sit on the same
run's stderr.

Nothing was written in any of these cases. The anchor reads `HCLOUD_TOKEN_READONLY` alone: since
#10664 (2026-10-23) there is no fallback to the read/write `HCLOUD_TOKEN`, which no longer exists in
`prd_terraform` (names-only listing, 2026-10-20). A missing or unusable read-only token is
`unreadable`. A transient Doppler auth or network failure clears on re-dispatch; a secret that is truly absent
is restored by the owner (`infra-credential-tiers-8209.md` step O5) before a re-dispatch can pass. The same generation scope applies to op=arm G3.7's
liveness signal and to op=luks-cutover / op=luks-rollback G3, so **all four ops now also refuse
while the Hetzner API or the HCLOUD token is unavailable** — including op=luks-rollback (retired by #8285 PR B,
so three ops today; the sentence is kept as written).

**Do NOT re-arm.** The monotonic flush latch on `/mnt/data` survives the replace and will refuse
it. If the intent is a deliberate SECOND flush on the same host — not a recovery — the verb is
`op=reflush` (see [§ Authorizing a second FLUSHALL](#authorizing-a-second-flushall-opreflush-7777)).
For diagnosis only, `INNGEST_DIAGNOSTIC_BOOT=1` starts SQLite-only and serves nothing.

**Measured 2026-09-17:** two replaces and 76 minutes with no live scheduler, because the cause
was invisible until the host journal was read — see
[§ Reading host state without SSH](#reading-host-state-without-ssh) for the read that finds it.

### Authorizing a second FLUSHALL (`op=reflush`, #7777)

The `/mnt/data` latch is an **append-only ledger**, never a flag file: each record is one line,
`flushed_at=… host=… dbsize=…` when a FLUSHALL ran, and `cleared_at=… run=… by=… boot_id=…` when a
deliberate second flush was authorized. **The newest record decides** whether the FSM may flush —
a `cleared_at` supersedes the `flushed_at` it follows, and a later `flushed_at` re-latches the
host. Records are only ever appended; nothing deletes or truncates the ledger, so the flush
evidence and the authorization evidence coexist permanently.

A second flush is needed when a deliberate recut emptied the queue once and a later operation —
typically the `inngest-volume-recut` refusal telling you the store holds N keys (that dispatch is gone since #8285 PR A, see the Update callout under § Post-cutover status below) — requires it
empty again. The verb:

```
gh workflow run cutover-inngest.yml -f op=reflush
```

Like `op=resume`, the run **holds in `Waiting` for the required-reviewer approval** on the
`inngest-cutover` environment before any step executes — that approval IS the authorization the
ledger records. The op writes `INNGEST_CUTOVER_FLIP=reflush,run=<gha-run-id>,by=<actor>` — the
evidence rides the flag value because `soleur-inngest/prd`'s boot-isolation self-check is an
exact-set match on the config and no new secret name can exist. The on-host FSM's `reflush` arm
then appends the `cleared_at` record (stamping `cleared_at` and the host's own `boot_id` at the
host, so a clear can never be attributed to a boot that did not record it) and re-enters the
normal `stop → FLUSHALL → assert → flushed → start → done` path, which appends a fresh
`flushed_at` and re-engages the latch.

Gates, all refusing **before** the write:

- **G1** the flag must be terminal (`done`/`aborted`/`rolled-back`) — a reflush over an
  in-flight flip races the running FSM;
- **G2** the latch must **exist** off-host (the inverse of op=arm's G3.7) — a reflush with no
  recorded flush is a first flush, and its verb is `op=arm`;
- **G3** the host must be audible — `reflush` is consumed only by the on-host 30s timer;
- **G4** the evidence must be well-formed — a bare or malformed `reflush` carries no
  authorization, and the FSM refuses it the same way (`reflush-evidence-invalid`).

Confirm the ledger afterwards with `tail` on the latch record surfaced by
`cat-inngest-cutover-state.sh`, or the Better Stack rows `reason="latch-cleared"` followed by
`reason="flip-complete"`. **There is still no delete and no SSH anywhere in this path.**

### Reading the private-NIC boot event (#8539)

**From the next `inngest-host-replace` onward** — merging changes nothing; `runcmd` is
once-per-instance, so the helper runs on a host CREATE and not on a reboot — every fresh inngest
boot emits **exactly one** private-NIC event just before the zot login. Later boots of the same
host are converged by the `.network` file alone and emit nothing, so an absence on a reboot is
expected, not a fault. It goes to Better Stack as a `SOLEUR_INNGEST_BOOT_STAGE` marker and to
Sentry as the same stage (`host_name soleur-inngest`), carrying a byte-identical detail string.
The stage is one of `private_nic_ok`, `private_nic_timeout` or `private_nic_probe_fault`. It
reports whether the private NIC, which Hetzner hot-attaches after boot, held its address in
time. The static networkd fallback `/etc/systemd/network/99-soleur-private-fallback.network`
is what configures a late NIC. The design is recorded in the ADR-115 amendment of 2026-09-22.

Read it with this query. It needs the Better Stack ClickHouse read connection
(`BETTERSTACK_QUERY_HOST/USERNAME/PASSWORD` in Doppler `soleur/prd_terraform`), so run it under
`doppler run -p soleur -c prd_terraform --`:

```
doppler run -p soleur -c prd_terraform -- bash scripts/betterstack-query.sh \
  --since 30d --grep SOLEUR_INNGEST_BOOT_STAGE --limit 2000 \
  | jq -R -r 'fromjson? | .raw? | fromjson?
      | select(.marker == "SOLEUR_INNGEST_BOOT_STAGE")
      | select(.stage | startswith("private_nic_"))
      | "\(.dt) \(.stage) \(.detail)"'
```

`--grep` compiles to an unanchored ClickHouse `raw LIKE '%…%'` over a source every host
multiplexes into, and `_` is a single-character wildcard there — so grepping `private_nic_`
directly returns thousands of unrelated web-1 rows and none of these. The marker is the coarse
prefilter; the `jq` decode is what actually selects. `fromjson?` at both levels is load-bearing:
without it one malformed line aborts the whole read and the result reads as "never emitted".

The detail string is `boot=<8>.waited_s=<n>.by=<b>.egress=<dev>` on `ok`,
`boot=<8>.waited_s=150.links=<entries>` on `timeout`, and `boot=<8>.waited_s=<n>.reason=<r>` on
`probe_fault`. `boot=` is the first 8 characters of the boot id. `waited_s` is the loop counter times two, so
it is a FLOOR on the elapsed wait, not a measurement of it — each iteration also forks `ip` and
`grep`. Read the fields as follows.

**`by=` (on `private_nic_ok`): which networkd file configured the interface holding the address.**

| Value | Meaning | Next step |
| --- | --- | --- |
| `10-netplan-<if>` | Ordinary boot: cloud-init rendered the NIC itself, and the fallback stayed inert. | None. |
| `99-soleur-private-fallback` | The race happened and the fallback healed it. Sentry level is warning, at any `waited_s` (usually `0`, because the early `networkctl reload` heals the link first). | None for this boot. Count these: they are the evidence that the race recurs. |
| `none` | networkd reports no file for the link, so something other than networkd configured it (for example an image udev hook). | Record it on #8539; the fallback is not what is working. |
| `nonetworkctl` | `networkctl` is missing on the image, so the fallback cannot have been working. | Record it on #8539. |
| anything else | A networkd file we do not ship took the link — a vendor file under `/usr/lib/systemd/network/`, or a drop-in. | Read it on the host's next replace and record it on #8539; the fallback is not what is working. |

**`egress=` (on `private_nic_ok`): the device of the default route.** It should be `eth0`. Any
other device means the private DHCP took the default route, and the event is warning level.
Public egress (apt, Sentry, Better Stack) then runs over the private net, which has no NAT
gateway. Record it on #8539 with the boot's full detail string.

**`links=` (on `private_nic_timeout`): every non-loopback link except `eth0`, `docker*`,
`veth*` and `br-*`, as `<if>:<networkd setup>:<driver>:<v4|nov4>`, joined by `--`.**

| Value | Meaning |
| --- | --- |
| `none` | No such link exists: the attach never reached the guest within 150 s. |
| `<if>:unmanaged:virtio_net:...` | The link arrived but the fallback did not take it (networkd did not match or did not act). |
| `<if>:<setup>:<driver>:...` with a driver other than `virtio_net` | The fallback's `Driver=virtio_net` assumption is wrong for this image. |
| `<if>:configured:...:v4` | The link is configured with a different address than expected: drift between the template's IP and the attach. |
| `nonetworkctl` | `networkctl` is missing, so no link state could be read. |
| an entry ending `--cut` | The detail string hit its 120-char cap and trailing entries were dropped. |

**A `timeout` or a `probe_fault` PAGES.** `sentry_alert.web_private_nic_boot_gate`
(`apps/web-platform/infra/sentry/issue-alerts.tf`) filters on the `stage` tag with **no host
condition**, and every host bakes the same `var.sentry_dsn` — so these two stages from the
inngest host match a rule whose name still says `web-host-…`. Judge severity by the event's
`host_name` tag, not by the rule name: on web-1 the condition self-heals, on inngest it means
the zot pull is about to fail and the sole scheduler will not come up. It is the earliest
automated warning you get. The pull failure itself pages next: since #8036 item 1d a zot miss
has no GHCR fallback behind it, so it ends the boot and emits `inngest_pull_fatal` at level
`fatal`. `sentry_alert.zot_mirror_fallback_rate` (`zot-mirror-fallback-rate`) pages on that
stage, even though the rule name still says "fallback". The same stage goes to Better Stack
through the phone-home, with the redacted pull tail. Query it with
`scripts/betterstack-query.sh --grep inngest_pull_fatal`. The detail is `rc=<n>` (`rc=124` is
the 180 s pull timeout), or `rc=noendpoint` when no zot endpoint was baked. If zot does not
serve the pinned digest, the fix is a `build-inngest-bootstrap-image.yml -f mirror_only=true`
backfill and then a new replace, not a revert. The old `oci-pull-ALL-LEGS-FAILED`,
`pre-oci-pull` and `oci-pull-rc-*` markers no longer exist. `private_nic_ok`
matches no filter and is query-only by design — a healthy replace must not page. A `private_nic_probe_fault` means no measurement was possible (`reason=`
is `noarg`, `noip`, `nogrep` or `iprc`); the pull outcome markers that follow still say whether
the boot worked.

> **Addendum 2026-09-28 (#8562): "it ends the boot" is now the live host's behavior only.** The
> template retries: since ADR-257 the pull runs in `soleur-inngest-provision.service`, so a zot
> miss ends one **attempt**, emits `inngest_pull_fatal` with `attempt=N`, and the unit tries again
> (120 s later at first, backing off to 15 minutes). The live host keeps the old behavior until its next replace. Read a page from a
> host born from the new template per [§ Provision unit (#8562)](#provision-unit-8562), and wait
> for `bootstrap-done` before deciding on another replace.

**Absence is detected by query only, and nothing pages on it.** If a boot has a `pre-zot-pull`
marker and no `private_nic_*` marker within ±15 minutes of it on the same host, the helper
crashed or never ran. Read the `pre-zot-pull` rows with the same query, `--grep pre-zot-pull`,
and compare timestamps. `zot-login-*` is not a valid reference: the empty-credentials path emits
`zot-creds-EMPTY` instead.

### Post-replace: the boot-trace allowlist (#7596)

**Run after every `inngest-host-replace`.** The two #7457 Source-4 allowlist
entries — `inngest-boot-phone-home` and `inngest-bs-token-restage` — reach the
inngest host **only** inside the baked bootstrap image: this host's
`vector.toml` is never redelivered (`terraform_data.journald_persistent`
connects to `hcloud_server.web["web-1"]` and nothing else). A replace is the
delivery, so the replace is where delivery is measured — and the close
condition for #7596 is a **measured read**, never "the entries are on main"
(that is the trap the issue was filed about) and never a web-1 row (the
entries are live-but-inert there by design).

The positive control is the restage unit, not the phone-home emitter.
`inngest-bs-token-restage.service` runs once per boot and, on SUCCESS, logs
`SOLEUR_INNGEST_BS_TOKEN_RESTAGED ok=1` under
`SYSLOG_IDENTIFIER=inngest-bs-token-restage` (the write_files pair in
`cloud-init-inngest.yml`). `inngest-boot-phone-home` is deliberately
silent-on-success — every `logger` call sits in a failure arm
(`journald-config.test.sh` CF-4c) — so a healthy replaced host emits **zero**
phone-home rows, and an absence check there proves nothing. Use the restage
row:

```
doppler run -p soleur -c prd_terraform -- bash scripts/betterstack-query.sh \
  --since <window covering the replace> --grep inngest-bs-token-restage --limit 500 \
  | jq -R -r 'fromjson? | .raw? | fromjson?
      | select(.SYSLOG_IDENTIFIER == "inngest-bs-token-restage" and .host == "soleur-inngest")
      | "\(.dt) \(.message)"'
```

The double `fromjson?` is load-bearing: Better Stack stores `raw`
double-encoded (quotes escaped), so a literal `"host":"…"` grep on the outer
row matches nothing, ever — decode first, field-isolate second. `host` (the
OS hostname) is required, not just `host_name` — the shared renderer makes a
stale `host_name` possible on a web-1 row (#6616).

- **One or more `SOLEUR_INNGEST_BS_TOKEN_RESTAGED ok=1` rows** from
  `host=soleur-inngest` — the allowlist is live on the host; #7596's close
  condition is met.
- **Zero rows** — do NOT read that as "the allowlist is missing" yet. A quiet
  window and a dead channel read identically (the issue's own methodology
  note: liveness probe before the identifier probe, and check vendor billing
  state when a whole channel is dark — that, not a host fault, was the
  2026-08-14→16 darkness, #7569). Widen `--since` past the replace, confirm the
  host ships *something* (`--grep inngest- --limit 20`), then re-read.
- The same read exists as a sweeper probe:
  `scripts/followthroughs/inngest-bs-token-restage-7596.sh` asserts the
  positive row and reports TRANSIENT until it arrives — enrolled on #7596 via
  a `soleur:followthrough` directive (operator step; see the issue).

## Provision unit (#8562)

[ADR-257](../../architecture/decisions/ADR-257-inngest-host-provisioning-runs-in-a-latched-retrying-unit.md).
The zot login, the isolation self-check and the pull → bootstrap block no longer run once in
cloud-init `runcmd`. They run in `/usr/local/bin/soleur-inngest-provision`, under
`soleur-inngest-provision.service`, which retries without limit until one attempt succeeds. The
delay between attempts starts at 120 s and backs off to 15 minutes (`RestartSteps=4`,
`RestartMaxDelaySec=15min`): about 8 attempts in the first hour, about 4 an hour once backed
off (corrected 2026-09-30 from "about 26 fast failures", #9299). A full success writes a latch, and the latch switches the unit off for the rest of the host's
life. `runcmd` only arms the unit; a boot timer starts it again 90 s after any later boot of a host
that has not latched yet.

Two design rules change what a reading means:

- **A degraded success does not latch.** If the bootstrap exits 0 but `inngest-redis` is
  inactive or the installed server unit lacks the durable ExecStart (the server serves
  SQLite-only; a requested diagnostic boot is exempt), the attempt emits `bootstrap-done-DEGRADED`
  with `why=` naming which, and exits 0 without the latch. The unit does not retry on that boot; the timer retries at the next boot.
  The host serves degraded until then, as before #8562.
- **The cutover timers are always put back.** Before each bootstrap run the unit stops the flip
  and LUKS-cutover timers and waits (bounded at 300 s) for any running flip or LUKS-cutover step,
  a non-empty `/var/lib/inngest-luks-cutover/frozen-active`, or a flip between steps (the flip
  FSM's host state slot reads `"flag":"flipping"`). On success the bootstrap re-enables the
  timers; on a failed attempt the unit's exit handler restarts every timer that was active when
  it stopped them.

Each attempt also re-runs the bounded private-NIC wait and, before the bootstrap, a bounded
`dpkg --configure -a`.

**When this applies.** Only to a host born from the #8562 template. The change reaches the host
at its next `inngest-host-replace` (`apply-web-platform-infra.yml`, `apply_target=inngest-host-replace`)
plus the human-approved `cutover-inngest.yml -f op=resume`. A host born before it keeps the old
behavior until then: a zot miss ends that boot. Tell the two apart by the rows: a host running the
unit emits `provision-unit-armed` once per host life.

**Key every reading on `iid`.** Every stage row the unit emits carries
`iid=<cloud-init instance-id>`. Old and new hosts share the hostname `soleur-inngest` during a
replace, so a late row from the destroyed host looks like the new host's unless the `iid`
matches the newest `provision-unit-armed` row's. An `iid` of `unknown` or `soleur-inngest` is the
fallback every host life shares when the instance-id was unreadable; it cannot tell host lives
apart, and the probe refuses it.

**`scripts/inngest-host-state.sh` does not read these stages.** It reads the served FSM and unit
state through journald → Vector → Better Stack, and Vector is installed by the bootstrap this unit
runs. The readers for provision stages are the follow-through probe and the queries below.

**On-demand rehearsal (#9175, ADR-279).** This whole path is rehearsed end-to-end by the
dispatch-only `inngest-provision-rehearsal.yml` workflow: it births a throwaway host without its
private NIC (Phase A — the NIC-absent failure is observed, not assumed), attaches the NIC in a
second apply (Phase B — recovery to `bootstrap-done`), then reboots and asserts no provision
markers re-emit (the latch holds). It renders the SAME `cloud-init-inngest.yml` with only
identity-class divergences: the scratch `rehearsal_<runid>` Doppler environment (a non-inheriting
root config), a read-scoped token, `INNGEST_DIAGNOSTIC_BOOT=true`, loopback `sdk_url`, and
`10.0.1.60` on the real private subnet. See
[runbook inngest-provision-rehearsal.md](inngest-provision-rehearsal.md).

### Stages

| Stage (channel) | Meaning |
| --- | --- |
| `provision-unit-armed iid=…` (Better Stack) | `runcmd` enabled the timer and started the unit. Once per host life. |
| `provision-attempt-start attempt=N` (Better Stack) | Attempt N began. N counts every attempt since the host was born (the counter is on the root disk). |
| `provision-env-MISSING keys=…` (Better Stack) | The env file exists but lacks a required key. The attempt ends before any Doppler call. |
| `provision-nic-ABSENT ip=…` (Better Stack) | The private NIC was still absent after the NIC wait; the attempt ended and retries. |
| `isolation-check-FAILED` (Better Stack) | The Doppler boot credential failed the isolation self-check; the attempt ended before any pull. |
| `zot-creds-EMPTY` / `zot-login-FAILED` (Better Stack) | No baked zot credential, or the zot login was refused. The pull that follows misses. |
| `inngest_pull_fatal` with `attempt=N` (Sentry, fatal, paged; Better Stack) | This attempt's zot pull missed. One missed attempt, not a dead host. |
| `provision-fsm-busy` (Better Stack) | A flip or LUKS-cutover step was still running after the 300 s quiesce bound; the attempt ended and retries. |
| `bootstrap-exit-<rc>` (Better Stack) | The bootstrap exited `rc`; its detail carries the output tail. `rc != 0` is followed by `bootstrap-failure-journal` and ends the attempt. |
| `bootstrap-failure-journal` (Better Stack) | Written after a failed bootstrap: the failed units and the `inngest-server` journal for that attempt. |
| `provision-attempt-exit-<rc>` (Better Stack) | Attempt ended with `rc` (`143` = killed at `TimeoutStartSec` or at shutdown). |
| `provision_attempt_failed` (Sentry, warning, **paged** by `inngest-provision-failure`, #9176) | Same failure, on the channel that does not depend on Doppler. Its detail carries `rc=`, `attempt=`, `iid=` and `why=<last stage>`. `why=inngest_pull_fatal` is excluded from that rule: the pull miss already paged through `zot-mirror-fallback-rate`. |
| `sentry-emit-FAILED stage=… rc=…` (Better Stack) | The Sentry POST for that stage failed; read the stage from Better Stack instead. |
| `SOLEUR_INNGEST_BOOT_TRACE_LOST` (journald tag `inngest-boot-phone-home`) | The Better Stack channel was dead for that stage (token file missing or empty, or the POST failed). It leaves the host only once Vector runs, i.e. after a bootstrap; until then the Sentry rows are the trace. |
| `bootstrap-done-DEGRADED why=… iid=…` (Better Stack); `bootstrap_done_degraded` (Sentry, warning, **paged** by `inngest-provision-degraded`, #9299; see [§ Reading an `inngest-provision-degraded` page](#reading-an-inngest-provision-degraded-page-9299)) | The bootstrap exited 0 but the host serves SQLite-only (`why=` is `.redis-inactive` and/or `.no-durable-execstart`). **No latch**; the next boot retries. Not a PASS. |
| `bootstrap-done iid=…` (Better Stack) | Full success; the latch is written. This is the recovery signal. |

Signatures that have no stage of their own:

- **SIGKILL or power loss mid-attempt:** `provision-attempt-start attempt=N+1` with no
  `provision-attempt-exit-*` and no `bootstrap-done*` for attempt N. The kill left nothing to
  emit with; the next attempt's start is the durable trace.
- **xtrace refusal or a missing env file:** `provision-unit-armed`, then no
  `provision-attempt-start` ever. Both stop the attempt before its first emit: the script refuses
  under xtrace (exit 78), and systemd will not start the unit without
  `/etc/default/inngest-doppler`. The probe reads this as `FAIL reason=never-started`.

### Reading a page

- **A page carrying `attempt=N` is one missed attempt.** The unit retries (120 s at first, backing
  off to 15 minutes), and `zot-mirror-fallback-rate` emails at most every 23 minutes while the
  host stays dark (one grouped Sentry issue). A second email means the host is still dark, not
  that a second host failed.
- **After `inngest_pull_fatal`, wait for `bootstrap-done` with the same `iid` before deciding to
  replace.** The host may recover on its own as soon as the cause clears (a late NIC, a zot blip).
- **Run `op=resume` only after `bootstrap-done` for the new `iid`.** `bootstrap-done-DEGRADED` is
  not enough. The unit's quiesce keeps a retry from restarting the server inside the flip's verify
  window, and since #9177 the ordering rule is also enforced gate-side: op=resume's G4 runs the
  provisioning probe and refuses anything but `verdict=PASS` for the current iid.

**Find the host life (`iid`).** The armed row is written once per host life, so the window must
cover the whole life (30 days, as the probe uses); `raw` is double-encoded and must be decoded:

```sh
doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh --since 30d \
  --grep provision-unit-armed --limit 200 \
  | jq -R -r 'fromjson? | .raw? | fromjson?
      | select(.marker == "SOLEUR_INNGEST_BOOT_STAGE" and .host == "soleur-inngest"
               and .stage == "provision-unit-armed")
      | "\(.dt) \(.detail)"' | sort | tail -n 1
```

**Read that life's stages.** Set `IID` from the `iid=` in the row above:

```sh
IID=<iid>
doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh --since 30d \
  --grep SOLEUR_INNGEST_BOOT_STAGE --limit 5000 \
  | jq -R -r --arg iid "$IID" 'fromjson? | .raw? | fromjson?
      | select(.marker == "SOLEUR_INNGEST_BOOT_STAGE" and .host == "soleur-inngest")
      | select((.detail // "") | test("(^|\\s)iid=" + $iid + "(\\s|$)"))
      | "\(.dt) \(.stage)"' | sort > life.txt
cut -d' ' -f2 life.txt | sort | uniq -c                                   # per-stage counts
awk '$2 == "provision-attempt-start" {buf = ""} {buf = buf $0 "\n"} END {printf "%s", buf}' life.txt
                                                                          # the latest attempt only
```

- **"`isolation-check-FAILED` on every attempt"** reads as: its count equals the
  `provision-attempt-start` count, over at least 3 attempts.
- **"Repeating `provision-fsm-busy`"** reads as: it ends 3 or more consecutive attempts (the last
  lines of `life.txt` alternate `provision-attempt-start` / `provision-fsm-busy`). That is a flip
  or LUKS-cutover step wedged for well over 15 minutes. Read the FSM state with the read-only
  `scripts/inngest-host-state.sh` (locally, or via the `inngest-host-state.yml` one-tap wrapper,
  #8449 UC2; see [§ Reading host state without SSH](#reading-host-state-without-ssh)). Do not
  replace blindly: the flip FSM's flag lives in Doppler and outlives the host (ADR-100
  Decision 6), so read it first.

**Read the Sentry side without a dashboard.** `provision_attempt_failed`,
`bootstrap_done_degraded` and `inngest_pull_fatal` are Discover-readable per host and stage, with
the read-only token:

```sh
doppler run -p soleur -c prd -- scripts/sentry-issue.sh --host-events soleur-inngest \
  --stage provision_attempt_failed --stats-period 7d
doppler run -p soleur -c prd -- scripts/sentry-issue.sh --host-events soleur-inngest \
  --stage bootstrap_done_degraded --stats-period 7d
```

Each event's detail carries `iid=` and `why=`; filter on the `iid` above.

**Print a stage's detail.** The `life.txt` recipe prints only the stage. For one stage's detail
(for example the failed units in `bootstrap-failure-journal`), reuse the same query with a stage
filter and print `.detail`:

```sh
doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh --since 30d \
  --grep bootstrap-failure-journal --limit 200 \
  | jq -R -r --arg iid "$IID" 'fromjson? | .raw? | fromjson?
      | select(.marker == "SOLEUR_INNGEST_BOOT_STAGE" and .host == "soleur-inngest"
               and .stage == "bootstrap-failure-journal")
      | select((.detail // "") | test("(^|\\s)iid=" + $iid + "(\\s|$)"))
      | "\(.dt) \(.detail)"' | sort
```

**The delivery probe is the same reading, automated.**
`doppler run -p soleur -c prd_terraform -- scripts/followthroughs/inngest-provision-unit-8562.sh`
prints one `verdict=` line on stdout:

| Verdict | Exit | Meaning |
| --- | --- | --- |
| `PASS` | 0 | A `bootstrap-done` carries the newest armed row's `iid`. |
| `FAIL reason=degraded cause=…` | 1 | The only completions are `bootstrap-done-DEGRADED`. |
| `FAIL reason=never-started cause=…` | 1 | Armed over 10 minutes ago; no attempt ever started (see the signatures above). |
| `FAIL reason=no-bootstrap-done cause=…` | 1 | Attempts for over 2 h, no `bootstrap-done`. |
| `TRANSIENT reason=not-delivered` | 2 | No armed row in 30 days. |
| `TRANSIENT reason=in-progress` | 2 | Armed, still inside the 10-minute / 2-hour bounds. |
| `TRANSIENT reason=probe-fault` | 3 | The query failed, credentials are missing, or the armed row's `iid` is absent, `unknown` or the hostname. |

`cause=` lists that `iid`'s counts of `isolation-check-FAILED`, `inngest_pull_fatal`,
`provision-fsm-busy` and `bootstrap-done-DEGRADED`, so the verdict line alone names the next read.

**Known gap: a never-armed host reads `TRANSIENT reason=not-delivered` forever.** If an earlier
`runcmd` item hangs, or cloud-init fails before `runcmd`, no `provision-unit-armed` row is written,
and the probe cannot tell that from "no replace has run yet". After a delivery replace, check for
the armed row directly (the first query above); if it is missing, the host's `runcmd-entered` and
the last stage it reached show where `runcmd` stopped. A LUKS-stage FATAL is **not** this case:
`runcmd` has no top-level errexit, so the unit is armed and the host ends at
`bootstrap-done-DEGRADED`.

### Reading an `inngest-provision-failure` page (#9176)

The email subject is the shared boot-stage group title ("soleur-cloud-init boot stage", issue
`WEB-PLATFORM-4S`), the same as a pull-miss page and an `inngest-provision-degraded` page. Tell
them apart by the rule name and the `stage` / `detail` tags: **a second email minutes after a
failure page is not a duplicate**, it is usually the degraded page for the attempt that followed
(read it in [§ Reading an `inngest-provision-degraded` page](#reading-an-inngest-provision-degraded-page-9299)). A page whose issue is NOT `WEB-PLATFORM-4S` did not come from the host
emitter: treat it as forged (the DSN is semi-public). Map the page to the next read, top row first:

| `stage` / `why=` | Next read |
| --- | --- |
| `rc=143` | A kill. If the attempt ran about 65 minutes (`provision-attempt-start` to `provision-attempt-exit-143` in `life.txt`), a step hung at `TimeoutStartSec`: read the `why=` row below. If it was short, it was a shutdown or reboot. |
| `isolation-check-FAILED`, `provision-env-MISSING`, `provision-nic-ABSENT` | The matching rows in [§ Stages](#stages). This stage is the failure itself. |
| `provision-fsm-busy` | The FSM state, via `scripts/inngest-host-state.sh` or `inngest-host-state.yml` (see "Repeating `provision-fsm-busy`" above). |
| `bootstrap-failure-journal` | That attempt's `bootstrap-failure-journal` detail (recipe above). |
| `bootstrap-exit-0` | The bootstrap succeeded but writing the latch failed (root disk). Read `life.txt`. |
| any other `why=` | The attempt died at or after that stage. Read that attempt's rows in `life.txt`. |

- **Each rule throttles on its own.** `inngest-provision-failure` re-pages at most every 2 hours
  and `inngest-provision-degraded` at most every 34 minutes, per issue group, so a failure page no
  longer suppresses a degraded page (#9299). After a failure page, confirm `bootstrap-done` (not
  `bootstrap-done-DEGRADED`) for the same `iid`; a degraded page is never re-emitted, so treat it as
  open until `bootstrap-done` appears.
- **A benign or forged page can hide a real failure.** For a retrying failure the window is up to
  2 h. For a degraded page it is up to 34 minutes, and a real degraded event inside that window is
  silent until the next boot, because it is not re-emitted. Corroborate with the Better Stack
  `provision-attempt-exit-<rc>` and `bootstrap-done-DEGRADED` rows, which need a Doppler-held token
  to write.
- **Not paged by any rule:** a unit that never armed or never started (see the signatures above),
  a SIGKILL or power loss, a Sentry POST that failed (`sentry-emit-FAILED` in Better Stack; for
  `sentry-emit-FAILED stage=bootstrap_done_degraded` the degraded state has no second paging path), and a
  bootstrap that exits 0 while broken in ways the degraded check does not test (a refused server
  start, a missing Vector, missing flip or LUKS-cutover assets). Read these from `life.txt`.
- **To quiet either, change the rule in Terraform** (`sentry_alert.inngest_provision_failure` or
  `sentry_alert.inngest_provision_degraded`): raise
  `frequency_minutes`, or set `enabled = false`, and regenerate `alert-reference.json` in the same
  PR (the `sentry-alert-reference-expected-<run>` artifact, see the Sentry root
  [README § Drift detection](../../../../apps/web-platform/infra/sentry/README.md#drift-detection)).
  Do not disable it in the Sentry UI (the daily drift job reports a live `DISABLED` as a fault),
  and never mute `WEB-PLATFORM-4S`: that group carries every web and inngest host boot stage.

### Reading an `inngest-provision-degraded` page (#9299)

The bootstrap exited 0 but the host is not running on its durable store, so a restart can drop
scheduled work. The `why=` names the missing piece: `.redis-inactive` (the `inngest-redis` unit is
not active) and/or `.no-durable-execstart` (the installed `inngest-server` unit lacks
`--postgres-max-open-conns`, the durable-ExecStart sentinel, or could not be read). The event is
emitted **once per boot and not re-emitted before the next one**, and there is no latch, so
nothing retries until the next boot: treat the page as open until `bootstrap-done` appears for the
host's current `iid` (recipes in [§ Reading a page](#reading-a-page)). The #8562 delivery probe
reads the same state as `FAIL reason=degraded` while that follow-through is open.

- **Same subject as a failure page.** Both rules page `WEB-PLATFORM-4S`; read the rule name or the
  `stage` tag. A degraded page minutes after a failure page is the next attempt ending degraded,
  not a duplicate.
- **A forged degraded event can hide a real one.** The DSN is semi-public, and a page whose issue
  is NOT `WEB-PLATFORM-4S` is forged. Each forged event opens a 34-minute window, and a real
  degraded event that arrives inside it is suppressed and, since it is not re-emitted, stays silent
  until the next boot; a forger repeating every 34 minutes keeps that window open. A forged page
  also carries a forged `iid`, so do not corroborate on the page's own `iid`: read the host's
  current `iid` from its newest `provision-unit-armed` row (recipe in
  [§ Reading a page](#reading-a-page)) and check that life for `bootstrap-done` or
  `bootstrap-done-DEGRADED`.
- **A lost POST is not paged.** If the Sentry POST failed, Better Stack carries
  `sentry-emit-FAILED stage=bootstrap_done_degraded` and nothing pages on it. That row's detail has
  no `iid=`, so the `iid`-filtered recipes miss it; read it by stage and match its time against the
  attempt times in `life.txt`:

  ```sh
  doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh --since 30d \
    --grep sentry-emit-FAILED --limit 200 \
    | jq -R -r 'fromjson? | .raw? | fromjson?
        | select(.marker == "SOLEUR_INNGEST_BOOT_STAGE" and .host == "soleur-inngest"
                 and .stage == "sentry-emit-FAILED")
        | select((.detail // "") | test("(^|\\s)stage=bootstrap_done_degraded(\\s|$)"))
        | "\(.dt) \(.detail)"' | sort
  ```

- **To quiet it**, see the Terraform note at the end of the section above.

### Replace triggers

A replace (the same `inngest-host-replace` dispatch plus `op=resume`) is the answer only when a
retry cannot fix the cause:

- `isolation-check-FAILED` on **every** attempt (as read above). The boot credential's scope is
  wrong, and retries cannot change it. Fix the Doppler scope first, then replace.
- No `bootstrap-done` for the new `iid` more than **2 h** after its first
  `provision-attempt-start`. Read the latest attempt's stages (above) for the cause before
  replacing.
- No `provision-unit-armed` for the new host (the known gap above), or armed with no
  `provision-attempt-start` within 10 minutes.

### What does not happen, by design

- **A provisioned host's reboot does not re-provision it.** The latch makes the unit a no-op, as
  `runcmd`'s once-per-instance rule did before. A degraded host has no latch and does retry at
  its next boot.
- **There is no SSH, latch-delete or `systemctl` step anywhere in this recovery.** The latch has
  one writer and is reset only by a fresh root disk. Re-provisioning a host is a replace.
- **Rollback of #8562 itself** is a revert, then the same replace plus `op=resume`, at the same
  bounded downtime as any inngest replace.

## Reading host state without SSH

Every unit state, journal tail and file-identity fact this runbook needs comes from **one
authenticated GET**. This section is the single recipe; the rest of the runbook references it
rather than repeating a host login.

**Prerequisite — the `doppler` CLI, and a missing one is not a missing capability.** Every
command below reads its credentials through `doppler`. On a machine without the binary the
shell answers `doppler: command not found`, which reads to an agent as "this session cannot
see the host" and sends it to an hourly probe or to SSH (`hr-no-ssh-fallback-in-runbooks`).
Measured 2026-09-17 during an inngest host replace: a 20-minute blind spot on a production
scheduler, for a one-command install. Bootstrap it first — checksum-verified, no sudo:

```
scripts/ensure-doppler.sh              # installs to ~/.local/bin, prints the path
scripts/ensure-doppler.sh --state      # missing | unauthenticated | ready | unknown
```

The four states have different fixes and must not be collapsed: `missing` → run the script;
`unauthenticated` → the operator runs `doppler login` (interactive, so an agent asks rather
than attempts it) or exports `DOPPLER_TOKEN`; `unknown` → a non-token failure such as a
network fault, where a login flow would fix nothing; `ready` → wrap the call in `doppler run`.

```
WS=$(doppler secrets get WEBHOOK_DEPLOY_SECRET -p soleur -c prd_terraform --plain)
CID=$(doppler secrets get CF_ACCESS_CLIENT_ID -p soleur -c prd_terraform --plain)
CSEC=$(doppler secrets get CF_ACCESS_CLIENT_SECRET -p soleur -c prd_terraform --plain)
HMAC=$(printf '' | HMAC_KEY="$WS" python3 -I -c 'import hashlib,hmac,os,sys;k=os.environb.get(b"HMAC_KEY");k or sys.exit(1);sys.stdout.write(hmac.new(k,sys.stdin.buffer.read(),hashlib.sha256).hexdigest())')
curl -fsS -H "X-Signature-256: sha256=${HMAC}" \
  -H "CF-Access-Client-Id: ${CID}" -H "CF-Access-Client-Secret: ${CSEC}" \
  "https://deploy.soleur.ai/hooks/deploy-status" > /tmp/ds.json
jq -e '.host_id == "hetzner-123931471"' /tmp/ds.json   # ASSERT FIRST — see below
jq '.services' /tmp/ds.json
```

**Assert `.host_id` BEFORE believing any field — this is not optional.** `deploy.soleur.ai` is
a Cloudflare Tunnel hostname and Cloudflare picks a connector per edge colo, so a read can be
answered by a *different* host than you meant. A redis-healthy answer from a peer is otherwise
indistinguishable from a fixed host; #6425 cost 16 hours of false alarms to exactly this.

> **This recipe CANNOT read the dedicated inngest host — use `scripts/inngest-host-state.sh`.**
> MEASURED 2026-09-17, 12 consecutive pinned attempts: every one was answered by
> `hetzner-123931471` (web-1); none reached the inngest host. This is not an unlucky
> coin-flip to retry past — the `/hooks` channel **terminates on web-1**, and the dedicated
> inngest host runs no listener and has no inbound rule (deny-all public firewall; the tunnel
> ingress is web-1's). So a `deploy-status` read "about the inngest host" is structurally a
> reading of a different machine, and `restart-inngest-server.yml` — same endpoint — cannot
> reach it either, which is why its verify step fails against a host it never contacted.
>
> The channel that *does* reach it is journald → vector → Better Stack, which is continuous
> rather than hourly and carries host identity **in the row**, so pinning is a filter rather
> than a routing hope:
>
> **One tap, no laptop (#8449):** dispatch the read-only wrapper from the Actions UI (the GitHub
> mobile app works) or from any shell:
>
> ```
> gh workflow run inngest-host-state.yml                      # since=90m, error scan off
> gh workflow run inngest-host-state.yml -f since=3h
> gh run list -w inngest-host-state.yml -L 1                  # then: gh run view <id>
> ```
>
> The run is **green only on rc 0**. Every other rc fails the run with
> `::error::inngest-host-state rc=<n> — <meaning>`, and that includes rc 4 (the host is not
> shipping), so a red run is the signal. The job summary shows the rc, its meaning, the
> `VERDICT … SERVING=yes|no` line, and the full rc table. **It does not show the rest of the
> output, and the error scan is off by default.** The repository is public, and the script's
> output includes unscrubbed journald text, so the full read stays with the laptop route:
>
> ```
> doppler run -p soleur -c prd_terraform -- scripts/inngest-host-state.sh
> ```
>
> Both routes run the same script and give the same exit codes. The laptop route is the only one
> that prints the probe-row fields, the STALE block and the recent-refusals scan.
>
> It prints the newest dedicated-host probe row **with its age**, a SERVING/NOT SERVING
> verdict, and a scan of recent unit refusals. Note the pin is the conjunction
> `host=soleur-inngest` **AND** `host_role=dedicated`: web-1 also emits
> `SOLEUR_INNGEST_SERVER_PROBE` with `host_name=soleur-inngest-prd`, so filtering on the
> marker or on `host_name` selects the wrong machine while looking right. The script also
> selects by emitter (`SYSLOG_IDENTIFIER=inngest-server-probe`, through
> `scripts/lib/inngest-probe-row.sh`): the inngest event log on the same host
> (`SYSLOG_IDENTIFIER=doppler`) quotes probe lines from GitHub issues about this work (#8846).
>
> **Exit codes are the contract — branch on them, and do NOT treat `rc != 0` as "host down".**
> The distinction between *the host is bad* and *I could not measure the host* is the entire
> point of this tool, and it is carried in the exit code, not the prose:
>
> | rc | Meaning | What to do |
> |---|---|---|
> | `0` | A dedicated-host row was found and summarised. Read `SERVING=yes\|no`. | Act on the verdict — but check the age first; see STALE below. |
> | `2` | Usage error (e.g. `--since` without a unit). Nothing was queried. | Fix the invocation. Says nothing about the host. |
> | `3` | Credentials not injected. Nothing was queried. | Wrap in `doppler run -p soleur -c prd_terraform --`. You are not missing access. |
> | `4` | The query **ran** and the window held no dedicated-host row. | A real finding: the host is not shipping (vector down, host down, or never booted). |
> | `5` | The newest anchored row carried no identity/verdict fields. **No verdict emitted.** | Not evidence of ill health *or* of good. Widen `--since` and re-read. |
> | `6` | **The read failed. Nothing was measured.** | Fix the read path (rotated credential, ClickHouse fault, DNS, missing binary). **Never report this as a host outage.** |
> | `78` | Refused to run under `set -x` with a live credential in the environment (#7797). | Nothing was queried. Re-run without shell tracing. |
>
> `4` and `6` are the pair that matters. Until 2026-09-17 every instrument fault — a 503, an
> absent binary, an error page, a python traceback — exited `4` and printed "the host is not
> shipping", which is a confident diagnosis of a healthy machine produced by a broken reader.
> If you see `6`, the tool is telling you it does not know.
>
> **Two things the verdict does not say.** `SERVING=yes` requires `registry_fns > 0` as well as
> `server_active=active` and `http_code=200` — a diagnostic boot (`INNGEST_DIAGNOSTIC_BOOT=1`)
> satisfies the first two and owns no work (#8015). And the probe timer is hourly, so a row can
> be up to 60m old; the verdict is a statement about **then**. The output labels this itself
> (`[Nm old]`, a `STALE` block, or `[AGE UNKNOWN]` when the timestamp will not parse) — read
> that line before acting on the verdict.
>
> **`INNGEST_DIAGNOSTIC_BOOT=1` is not an env var you can just export.** The unit carries a
> durable sentinel, so setting the variable alone produces a *second* BLOCK; it is a Doppler
> write to `soleur-inngest/prd` and needs `inngest-bootstrap.sh` re-run with it set.

Fields this runbook uses (all under `.services`):

| Field | Answers |
|---|---|
| `inngest_server`, `inngest_redis` | unit states (see the caveat below) |
| `inngest_server_version` | the **installed** `/usr/local/bin/inngest` self-reported version (`1.45.1-<sha>`; `#7308` — empty = no resolvable binary; the doppler wrap + yama ptrace scope make a running-process read dead, so this is installed≈running under the immutable-redeploy rule) |
| `inngest_journal_tail`, `inngest_redis_journal_tail`, `inngest_heartbeat_journal_tail` | the unit's own stderr, scrubbed |
| `inngest_redis_result` | `Result`/`ExecMainStatus`/**`NRestarts`**/`ActiveEnterTimestamp`/`LoadState`/`ActiveState`/**`SyslogIdentifier`** |
| `inngest_redis_dropin` | the drop-ins systemd has actually **loaded** (basenames; empty = none merged) |
| `inngest_redis_credfile` | credential presence + mtime + length (never the value); `absent` when missing |
| `inngest_redis_datadir` | `present <owner:group> <mode> use=<pct>` / `absent` / `refused-symlink` / `probe-timeout` |
| `inngest_redis_binary` | redis version + `distro_unit=`; `absent` when the binary is missing |
| `inngest_redis_tail_status` | `ok` / `empty` / `no-journalctl` / `unit-unknown` |
| `vector_config_identity` | **`redis_allowlisted=yes\|no`** + on-host sha256/mtime |

**Two fields answer the "is redis actually silent?" question as a PAIR, and both halves are
needed.** Vector's Source 4 matches `SYSLOG_IDENTIFIER` by exact value, so the unit's tag and
the shipper's allowlist only work together: `inngest_redis_result`'s `SyslogIdentifier=` is the
EMITTER half, `vector_config_identity`'s `redis_allowlisted=` is the ALLOWLIST half. If either
reads wrong, zero Better Stack rows for `inngest-redis` says nothing about redis — the rows are
going somewhere else (a unit with no `SyslogIdentifier=` is tagged from its ExecStart basename,
i.e. `doppler`, which matches no source).

Do **not** compare `vector_config_identity`'s sha256 against the repo file. The on-host
`vector.toml` is a render — it carries `@@HOST_NAME@@` sentinels substituted differently by
three renderers — so the hashes never match on any host. The sha is a change-detector between
two reads of the SAME host; `redis_allowlisted=` is the field that answers the question.
| `inngest_heartbeat_timer` | the durable heartbeat liveness signal |

**A single unit-state sample is a coin flip on a crash-looping unit.** `RestartSec=5` against
systemd's default `StartLimitBurst` means a failing unit never latches `failed` — it cycles
`activating`/`active` forever. During #7286 three probes 8 seconds apart reported
`degraded, degraded, durable` on a unit that was down for 16 hours.

**Decide from ONE read.** `inngest_redis_result` carries `ActiveEnterTimestamp`, `NRestarts` and
`ActiveState`, and the crash-loop signature is visible in a single payload: `NRestarts > 0` AND
`ActiveEnterTimestamp` within the last ~60s AND `ActiveState != failed` means it is still
looping. Prefer this to a two-read `NRestarts` delta — nothing on the host persists the prior
value between watchdog ticks, so a delta is only available to a human holding both payloads.

A second read ≥60s apart is still the cleanest CONFIRMATION once you believe it is fixed:
`NRestarts` unchanged across the two is the healthy signal, `is-active` is not.

If the endpoint itself returns non-2xx it now returns its stderr in the body (every read hook
carries `include-command-output-in-response-on-error`), so an error is diagnosable rather than
an empty response.

## On-demand cron trigger (HTTP — PRIMARY)

To fire any allowlisted `cron/<name>.manual-trigger` event on demand, POST to the
internal trigger route — **no SSH to the Hetzner box required** (#4734, #4742):

```bash
TOKEN=$(doppler secrets get INNGEST_MANUAL_TRIGGER_SECRET -p soleur -c prd --plain)
curl -sS -X POST https://app.soleur.ai/api/internal/trigger-cron \
  -H "Authorization: Bearer $TOKEN" \
  -H 'content-type: application/json' \
  -d '{"event":"cron/workspace-sync-health.manual-trigger"}' \
  -w '\n%{http_code}\n'
unset TOKEN
# → 202 {"dispatched":"cron/workspace-sync-health.manual-trigger","trigger":"manual-api"}
```

**Optional per-cron `data`** — crons that read `event.data` (e.g. `cron-bug-fixer`
reads `event.data.issue_number`) accept a `data` object. Route-controlled keys
(`trigger`, `at`) are stamped server-side and CANNOT be overridden by `data`:

```bash
  -d '{"event":"cron/bug-fixer.manual-trigger","data":{"issue_number":4383}}'
```

**Throttle and per-run cap (#8611, ADR-243).** The 18 Claude-spawning functions carry
`throttle {limit 2, period 1h}` (`apps/web-platform/server/inngest/cron-budgets.ts`). A `202` does
not mean the run started: a third fire within the hour is **queued**, not rejected, and runs (and
bills) later. Check `routine_runs_list` for up to an hour before re-firing. Each fire is a new run
with its own `--max-budget-usd` cap (`CLAUDE_BUDGET_USD`); a cap hit shows as a FAILED run with
reason `budget-capped` and `subtype=error_max_budget_usd` on the cost marker
(`betterstack-log-query.md`).

The allowlist is derived from `EXPECTED_CRON_FUNCTIONS`
(`apps/web-platform/server/inngest/cron-manifest.ts`) — a non-allowlisted event
returns 400. Non-plain-object `data` returns 400; the per-cron field validation
(e.g. `issue_number` positive-integer) lives in each cron, not the route.

**Agent/operator wrapper:** the `/soleur:trigger-cron` skill wraps this POST
(reads the secret read-only, lists allowlisted events, supports `--dry-run`):

```bash
plugins/soleur/skills/trigger-cron/scripts/trigger.sh --list
plugins/soleur/skills/trigger-cron/scripts/trigger.sh \
  --event cron/bug-fixer.manual-trigger --data '{"issue_number":4383}' --dry-run
```

## Fresh-host bootstrap

After `terraform apply` against a fresh `hcloud_server.web`, the inngest-server is NOT yet running on the host. The bootstrap is decoupled from cloud-init by design (the OCI image is the sole delivery path). Steps:

1. Verify the GHA workflow `.github/workflows/build-inngest-bootstrap-image.yml` has published an OCI image:

   ```
   gh api repos/jikig-ai/soleur/actions/workflows/build-inngest-bootstrap-image.yml/runs --jq '.workflow_runs[0]'
   ```

   If no run exists, release a bootstrap image — see [§ Bootstrap-image release](#bootstrap-image-release-tag--build--deploy--verify) below for the canonical 4-step tag→build→deploy→verify flow.
2. Deploy the published image (NO SSH — `deploy-inngest-image.yml` is
   `workflow_dispatch`-only; it POSTs the deploy webhook → on-host `ci-deploy.sh`
   `case "inngest")` runs the bootstrap):

   ```
   gh workflow run deploy-inngest-image.yml -f tag=<TAG>   # e.g. tag=v1.1.16
   ```

3. Verify via the deploy-status webhook (NO SSH) — see [§ Bootstrap-image release](#bootstrap-image-release-tag--build--deploy--verify) step 4. Expect `{component:"inngest", tag:"<TAG>", reason:"success"}`.
4. [§ Unpause heartbeat](#unpause-heartbeat) once you've confirmed the heartbeat timer is firing.

## `inactive` because a standing `rollback` flag stopped it — #7674

**The discriminator is one row.** `SOLEUR_INNGEST_SERVER_PROBE` carries `server_active=` **and**
`cutover_flag=` in the SAME line, hourly. Read that line before opening any other query:

```bash
doppler run -p soleur -c prd_terraform -- bash scripts/betterstack-query.sh \
  --since 24h --grep 'SOLEUR_INNGEST_SERVER_PROBE' --limit 500 \
  | jq -R -r 'fromjson? | .raw? | fromjson? | select(type == "object")
      | select(.host=="soleur-inngest" and .host_name=="soleur-inngest-prd")
      | select(.SYSLOG_IDENTIFIER=="inngest-server-probe")
      | .message | select(type == "string" and startswith("SOLEUR_INNGEST_SERVER_PROBE "))'
```

Select by emitter as well as host. The inngest event log on this host (`SYSLOG_IDENTIFIER=doppler`)
quotes probe lines from GitHub issue webhooks, so a host-only filter can return a quoted line as the
newest row (#8846; it filed false P1s #8833/#8834).

`server_active=inactive` together with `cutover_flag=rollback` or `cutover_flag=rolled-back` means
the host was **told to stop and obeyed**: `inngest-cutover-flip.sh`'s `rollback` arm calls
`stop_server`, writes the terminal `rolled-back`, and then emits `noop-rolled-back` — on every
30s tick pre-#7696, throttled to once per 300s since. The host is not broken and there is nothing
to repair on it.

**`inactive` is not `failed`.** That distinction is the whole diagnosis. A crash or a restart loop
leaves the unit `failed` and the `boot_id` churning; a deliberate stop leaves it `inactive` on an
unchanged `boot_id`. Measured 2026-08-25: 5.4 days of `server_active=inactive http_code=000
bind=[] priv8288=000` on one unchanged `boot_id`, with the flip guard's ALLOW arm logged twice at
boot — the unit started, and the FSM subsequently stopped it.

**Do not** read `bind=[]` / `priv8288=000` as a bind or firewall fault in this state; they are
consequences of the stop. **Do not** dispatch a restart: `restart-inngest-server.yml` is LB-routed
to the *web* host and cannot reach 10.0.1.40. **Do not** dispatch a host replace to "clear" it —
the flag lives in Doppler and survives, so the replaced host reads it at boot and stops again,
while the standing diagnostic evidence is destroyed.

**The only thing that releases the brake is a cutover window** (`op=arm` and its gate sequence).

**But "the brake is on" is NOT "nothing is broken" — correct an earlier reading here.** This entry
originally said "while the brake stands there is no outage". That is HALF true and the false half
matters:

| Path | State | Evidence |
|---|---|---|
| Scheduled crons | **healthy** | web-1's co-located scheduler; ~14 `inngest/scheduled.timer` rows/hour |
| App-originated `inngest.send()` | **FAILING CONTINUOUSLY** | ~621 `ECONNREFUSED 10.0.1.40:8288` rows/hour (~14,900/day), measured 2026-08-25 |

`INNGEST_BASE_URL=http://10.0.1.40:8288` is baked unconditionally into the web-platform container
(`ci-deploy.sh`, `cloud-init.yml`) and `server/inngest/client.ts` passes it through as `baseUrl`
with **no fallback**. So every app-originated event send is addressed to the stopped host.
`server/inngest/send-with-retry.ts` retries transient failures — against a host that is
deliberately stopped, every retry also fails, and the event is dropped once retries exhaust.

So the accurate statement is: **crons fire, events do not.** A reader who takes "no outage" at face
value will under-prioritise this, which is exactly what happened for 5.4 days — the cron half stayed
green and nothing read the half that was not.

The `*/15` dedicated-host arm on `scheduled-inngest-health.yml` now surfaces the host state
(`[ci/inngest-dedicated-host]`, verdict `stopped-by-brake`, no restart dispatched). It reports the
HOST, not the dispatch failure; the dispatch failure is tracked separately.

## Heartbeat-miss triage

BetterStack emails `ops@jikigai.com` when the heartbeat is silent past the 30-second grace period. Triage:

1. **Confirm the alert is real** — `curl https://uptime.betterstack.com/api/v2/heartbeats/460830 -H "Authorization: Bearer $(doppler secrets get BETTERSTACK_API_TOKEN -p soleur -c prd_terraform --plain)" | jq '.data.attributes.status'` should return `"paused"` (planned) or `"down"` (alert state).
2. **Check the service** — [§ Reading host state without SSH](#reading-host-state-without-ssh), then read
   `.services.inngest_server` and `.services.inngest_heartbeat_timer`.
   - Both inactive → the bootstrap never completed. Re-fire the deploy webhook.
   - `inngest-server` active, `inngest-heartbeat.timer` inactive → **dispatch
     `deploy-inngest-image.yml`** (i.e. a `deploy inngest`, NOT a web-platform release).
     `inngest-bootstrap.sh:889` runs `systemctl enable --now inngest-heartbeat.timer`, and that
     bootstrap runs only from ci-deploy.sh's `inngest)` arm — the `web-platform)` arm returns
     before reaching it, so a web release does not re-assert the timer. There is deliberately no
     dedicated timer-restart verb: `ci-deploy.sh` accepts `deploy|restart|quiesce|enable`, and
     `restart` is scoped to component `inngest` (which restarts inngest-server, not the timer).
     Adding a timer verb would widen the root-run allowlisted surface for a case a deploy
     already covers.
   - Both active → read `.services.inngest_heartbeat_journal_tail` from the *same* payload
     (#6536 gave the unit `SyslogIdentifier=inngest-heartbeat` precisely so this tail exists).
     Typical failure: missing `INNGEST_HEARTBEAT_URL` in Doppler prd, or Doppler CLI auth on the
     host expired — both visible in that tail. A present-but-malformed URL is refused by the shape
     guard and the unit exits 0 (it does NOT show as failed): look for an hourly-limited
     `SOLEUR_CREDENTIAL_REFUSED script=inngest-heartbeat reason=…` row over at least 70 minutes
     (ADR-280, PR C follow-ups), and fix the Doppler value rather than reverting the guard.
3. **Confirm the URL is fresh:**

   ```
   terraform -chdir=apps/web-platform/infra output -raw inngest_heartbeat_url
   ```

   should match what `doppler secrets get INNGEST_HEARTBEAT_URL -p soleur -c prd --plain` returns.

## Session-pool pressure / exhaustion (`[ci/inngest-pool]`) — #5562

The external watchdog (`.github/workflows/scheduled-inngest-health.yml`) runs a
pool-utilization probe every 15 min: it reads `pg_stat_activity` on the dedicated
inngest Supabase project (ref `pigsfuxruiopinouvjwy`) via the Management API and
files a `[ci/inngest-pool]` issue + Sentry `error` when **inngest-attributable**
client connections cross ~80% of inngest's worst-case TOTAL footprint
(`INNGEST_CLIENT_CAP` = P × per-pool cap 5 ≤ 20; #6258, ADR-105)
— `pool_pressure`, the leading indicator — or `EMAXCONNSESSION` fires (`pool_exhausted`,
the cliff). It counts ONLY inngest's own connections (role `postgres`, minus the
pooler's Supavisor warm connections + the probe), NOT total `pg_stat_activity` (which
is dominated by Supabase infra baseline and false-fires — #5563). These modes are
**excluded from the auto-restart gate** — a restart re-opens all of inngest's
pooler connections at once and DEEPENS exhaustion (#5558). **Do NOT restart
inngest-server for a `[ci/inngest-pool]` alert.** Triage (no-SSH first):

1. **Read the alert** (no SSH) — `gh issue view "$(gh issue list --state open --search 'in:title \"[ci/inngest-pool]\"' --json number --jq '.[0].number')" --comments`. The body carries the inngest-attributable connection count vs the client cap; the full per-backend breakdown is in the run log (`Inngest client backends: …`).
2. **Re-read the live pool** (no SSH, read-only) — confirm via the same filtered query the probe uses (per-backend breakdown; inngest = role `postgres` minus Supavisor + the probe):

   ```
   SUPA=$(doppler secrets get SUPABASE_ACCESS_TOKEN -p soleur -c prd --plain)
   curl -s --max-time 15 -X POST \
     https://api.supabase.com/v1/projects/pigsfuxruiopinouvjwy/database/query \
     -H "Authorization: Bearer $SUPA" -H 'Content-Type: application/json' \
     -d '{"query":"select coalesce(application_name,'\''(none)'\'') as app, usename, state, count(*)::int as n from pg_stat_activity where backend_type = '\''client backend'\'' and query not ilike '\''%pg_stat_activity%'\'' group by 1,2,3 order by 4 desc"}' | jq .
   ```

3. **Clear stale sessions** (no SSH, read-only client cap is the real fix) — if `idle` / `idle in transaction` sessions are climbing, terminate them via the same `/database/query` path (still no host login):

   ```
   curl -s --max-time 15 -X POST \
     https://api.supabase.com/v1/projects/pigsfuxruiopinouvjwy/database/query \
     -H "Authorization: Bearer $SUPA" -H 'Content-Type: application/json' \
     -d '{"query":"select pg_terminate_backend(pid) from pg_stat_activity where state = '\''idle'\'' and state_change < now() - interval '\''10 minutes'\''"}'
   ```

   The durable fix (#6258, ADR-105): inngest-server runs `--postgres-max-open-conns 5 --postgres-max-idle-conns 2 --postgres-conn-max-idle-time 1` (idle-time in MINUTES). `--postgres-max-open-conns` is PER-POOL, not total — inngest opens ~P separate Postgres pools (queue/state/history/api), so worst-case total = P × 5 ≤ 20; the idle-conns cap + 1-min idle drain release pinned Supavisor sessions so cutover-probe scans cannot ratchet the pool. The probe's leading indicator tracks this worst-case total (`INNGEST_CLIENT_CAP=20` in the workflow), not the pooler `default_pool_size` — so a `pool_pressure` alert means inngest's OWN connections approach the total ceiling (a stuck/looping function holding pooled connections, or more pools than expected). `default_pool_size` stays 30 — the #5562 30→15 revert is SUPERSEDED (its premise was falsified by the per-pool model; a 15-slot upstream would worsen exhaustion; see `apps/web-platform/infra/inngest.tf` + `decision-challenges.md`).
4. **`pool_probe_unavailable`** (401/403/non-JSON) is a *soft* mode — the probe itself is degraded, not the pool. Check the printed response body in the run log; a Supabase Management-API 401 is often a validation/scope signal, not pure auth (verify the PAT in Doppler `prd` and the `SUPABASE_ACCESS_TOKEN` GH secret).

### Cutover pre-flight-hang triage (`op=inventory` / `op=verify` `HTTP 000`) — #6258, ADR-106

An `op=inventory` / `op=verify` hook that returns **`HTTP 000` (empty body)** is a pre-flight scan
that ran past its budget — a distinct failure from the `[ci/inngest-pool]` `EMAXCONNSESSION` (500)
two-writer topology above. Since ADR-106 the scans are bounded (wall-clock deadline + page ceiling)
and **abandon-safe** (on timeout they emit a LOUD marker and `exit 1`, releasing the pool instead of
orphaning the scan). Triage off-box (no SSH):

1. **Query the in-surface marker** (the pre-flight path is now observable):

   ```
   scripts/betterstack-query.sh --grep 'SOLEUR_INNGEST_PREFLIGHT' --since 1h
   ```

   Read the discriminator fields on the `START` / `TIMEOUT` line for the run:
   - **No `SOLEUR_INNGEST_PREFLIGHT_START` for the run** → transport/host-down (the hook never
     executed) — check the Cloudflare tunnel + `webhook.service`, not the scan.
   - `TIMEOUT reason=deadline` with a progressing `pages=N`, `last_curl_exit=0` → the scan could
     not exhaust its window. **The deadline is NOT the lever (#6178).** The SUM bound
     `DEADLINE + PAGE_MIN ≤ outer_curl` caps `PREFLIGHT_DEADLINE_S` at 112 s, buying ~14 pages —
     against a 200-day window that needs ~1,456. Eleven op=verify dispatches emitted exactly this
     marker and none produced a verdict. Narrow the **window** (`CUTOVER_ANCHOR_FROM`) or scope the
     **population** (`CUTOVER_DOUBLEFIRE_FUNCTION_IDS`); see § Scan window + trust anchor below.
     *(This bullet previously advised enlarging the in-script deadline and explicitly forbade
     narrowing — the inverse of the correct action. Measurement retired it: ~728 runs/day.)*
   - `TIMEOUT reason=window_too_wide` → the page-1 feasibility gate refused the scan in ~2 s
     because the server's own `totalCount` exceeds what the budget can read. The message carries a
     **computed** latest-viable anchor; set `CUTOVER_ANCHOR_FROM` to it and re-dispatch. Narrowing
     yields a **window-limited** verdict, so prefer scoping the population when the full
     coexistence window must be covered.
   - `TIMEOUT` with `last_curl_exit=28` / `pages_timed_out>0` → a **pool-pressure STALL** (the
     `HTTP 000` shape), NOT a slow scan — triage as `[ci/inngest-pool]` above (the durable fix is
     #6178, gated by #6230). `reason=gql_error` with `last_curl_exit=28` is the same stall surfacing
     via the `.data` guard.
2. **A fast LOUD error ≠ a hang.** Since ADR-106 the correct behaviour on an over-budget scan is a
   quick `exit 1` → webhook **non-200** with a `SOLEUR_*_TIMEOUT` cause in the run log's `::error::`.
   That is the fix working (it releases the pool), not a regression — re-run; the bounded transport
   retry (2 attempts) absorbs a transient two-writer 500.
3. **`op=verify` verdict ≠ transport-200.** A green op=verify sub-probe **transport** (no 000/500 on
   registry-probe / doublefire) is the ADR-106 success signal. The op=verify **JOB** still
   legitimately halts at its `registry_empty` precondition on the dark pre-cutover host
   (the `registry_empty` precondition check in the `verify)` arm of `cutover-inngest.yml`) — that is a verdict, not a transport hang, and a green op=verify
   job is a post-#6178 concern. Do NOT read a `registry_empty` halt as a pre-flight hang.
   Two more readings that look like verdicts and are not (#8079): a standalone `op=registry-probe`
   run that exits **0 without a `registry_empty=` line** printed a HOST-STATE VERDICT — the host was
   dark and graded from its own rows; the registry was never read, and the run's own `::warning::`
   says so. And a red `restart-inngest-server` run is a statement about the **restart workflow**,
   not about this host — it shows `cancelled` when displaced from the shared `deploy-inngest-restart`
   group's queue, and red on its own gate or on the web unit, none of which the dedicated host's rows
   would show.

### Inspecting inngest-server's connection log

Only after the three steps above fail to resolve the pressure, inspect inngest-server's own
connection count — via [§ Reading host state without SSH](#reading-host-state-without-ssh):

```
jq -r '.services.inngest_journal_tail' /tmp/ds.json | tr '|' '\n' | grep -iE 'conn|pool|EMAXCONN'
```

The tail is `|`-folded in the payload, hence the `tr`. A host-level restart is the WRONG lever
here (it worsens `EMAXCONNSESSION`); this step is log inspection only, not remediation.

## How the external watchdogs are triggered (#8495, ADR-248)

`scheduled-inngest-health.yml` (every 15 min), `scheduled-zot-restart-loop.yml` (hourly) and
`scheduled-inngest-probe-heartbeat.yml` (every 15 min, #9703; see
[§ Arming the probe heartbeat](#arming-the-probe-heartbeat-9703)) are started by `workflow_dispatch` from the **watchdog dispatch clock** inside the web-platform
server (`apps/web-platform/server/watchdog-dispatch-clock.ts`), on every deployed web host. Their
`schedule:` crons are only the fallback: GitHub delivered them once every 2–7 h. The clock is
not an Inngest function because it watches Inngest. The run is created within seconds of the
dispatch, but its job then waits in the org runner queue (median ~30 s, p90 ~20 min), so the
Sentry monitors (`scheduled-inngest-health` margin 50, `scheduled-zot-restart-loop` margin 60,
`scheduled-inngest-probe-heartbeat` margin 60) are sized for that queue. A real outage still pages as soon as a run executes.

1. **Is it running?** Each web host logs one `armed` row at boot and about five tick rows an
   hour. Vector adds the host name (`soleur-web-platform` = web-1, `soleur-web-2`) outside the
   marker; the marker itself carries the Hetzner `host_id`:

   ```bash
   doppler run -p soleur -c prd_terraform -- \
     bash scripts/betterstack-query.sh --since 2h --grep SOLEUR_WATCHDOG_DISPATCH \
     | jq -R -r 'fromjson? | .raw | fromjson? | .host_name as $h | .message
         | select(type == "object" and .SOLEUR_WATCHDOG_DISPATCH == true)
         | [$h, .host_id, .workflow, .slot, .outcome, (.op // ""), (.reason // "")] | @tsv'
   ```

   Expect rows from both host names. The run cadence itself is public (`-a` also lists a
   disabled workflow):

   ```bash
   gh run list -a --workflow scheduled-inngest-health.yml --limit 20 --json createdAt,event \
     | jq -r '.[] | "\(.createdAt) \(.event)"'
   ```

   Healthy is one `workflow_dispatch` run per 15-min slot, occasionally two (a host collision
   or a late `schedule` fallback run). A `disarmed` row, or a Sentry event with
   `feature=watchdog-dispatch-clock op=arm`, means `SOLEUR_HOST_ID` was empty at boot.
2. **How do I run it now?** `gh workflow run scheduled-inngest-health.yml` (or the zot file);
   neither takes inputs. A manual run created inside the current slot makes the clock skip
   that slot (its skip row shows `run_event=workflow_dispatch`, like a run from the other
   host). To tell who started a run:
   `gh api repos/jikig-ai/soleur/actions/runs/<run_id> --jq .triggering_actor.login` (the
   clock's runs show the GitHub App's bot login).
3. **How do I stop it?** `gh workflow disable scheduled-inngest-health.yml` (or the zot file)
   stops both the clock's dispatches and the fallback cron. There is no way to pause only the
   clock while keeping the fallback (a kill-switch flag was considered and declined in the
   #8495 plan); reverting the PR removes the clock. While a workflow is disabled, expect one
   Sentry event per host per slot (`feature=watchdog-dispatch-clock op=dispatch`, tags
   `workflow`, `status=422`; about 8 an hour for inngest-health), grouped into one issue. If
   you revert the PR, also restore the pre-#8495 monitor margins (inngest 15, zot 120), or both
   page as missed on GitHub's slower cadence.
4. **How do I add or remove a table row?** Edit `WATCHDOG_DISPATCH_TABLE`
   (`apps/web-platform/server/watchdog-dispatch-table.ts`) with a non-empty `eligibility`
   argument (ADR-248: the job must watch the scheduling substrate or what it depends on;
   anything else belongs on the Inngest dispatch pattern). The workflow needs
   `workflow_dispatch:` + its fallback `schedule:` and no other trigger, a `concurrency`
   group with `cancel-in-progress: false`, and must tolerate a repeat run in one slot. Budget
   the monitor margin in `apps/web-platform/infra/sentry/cron-monitors.tf` as clock delay
   (the worst-case retry path: jitter + each attempt's poll and tick deadline + the backoffs
   between attempts, `CLOCK_DELAY_MINUTES`) + queue allowance
   (`QUEUE_ALLOWANCE_MINUTES`) + max runtime, at most `MAX_MARGIN_MINUTES` — the constants and
   the check live in `sentry-monitor-iac-parity.test.ts`. Update the expected slug set there
   and the `api -> github` watchdog edge and the `github -> sentry` workflow list in
   `model.c4`. After the deploy, each host logs a new `armed` row and a tick row for the new
   workflow within one interval.
5. **Which host sent a run?** Match the run's `created_at` to a `dispatched` row's `slot` and
   `host_name` (query in step 1); a skipped tick names the run that already covered the slot
   (`run_id`, `run_event`). A dispatched run with no matching marker came from the canary
   container, whose logs are not shipped.

`ci-deploy.sh`'s note that "the canary fires no crons" is no longer strictly true: the canary
carries a clock for its few minutes of life, and the slot-scoped read keeps it from
double-dispatching.

## External watchdog: functions-query degraded + restart `lock_contention` — #6407

Two soft/benign states the external inngest health watchdog handles WITHOUT paging or
churning a restart. Both are no-SSH — read Better Stack + the GitHub issue, never the host.

### `[ci/inngest-functions-degraded]` — `/v0/gql functions` transiently degraded (SOFT, NO restart)

**What it means.** The watchdog's cheap `/v0/gql functions` liveness read transiently failed
(a curl transport blip → the `__FETCH_FAILED__` envelope), but the on-host probe corroborated
the SAME loopback server's `/health` and got **HTTP 200** — inngest-server is UP and processing
events; only the functions read blipped. The classifier maps this to the soft mode
`functions_query_degraded`: **NO restart is dispatched, NO `[ci/inngest-down]` P1 is filed, and
the Sentry heartbeat stays `ok`** (no page). This is the #6407 false-positive class (the FATAL
sentinel used to fire `inngest_down` → restart even though inngest was healthy).

**Expected resolution.** Self-heals on the next `*/15` tick (the issue auto-closes on recovery).

**Persistence-escalation ceiling.** If the degraded state PERSISTS for ≥ ~45 min (3 `*/15`
cycles — the `/health`-ok-but-functions-permanently-wedged residual), the watchdog reclassifies
the verdict to `inngest_down`: it dispatches a restart AND flips the heartbeat to `error` (page).
First occurrence is soft; a sustained one is never masked forever.

**How to see it (no-SSH).** Query Better Stack for the verdict marker (tag `inngest-inventory`):

```
doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh --since 2h --grep SOLEUR_INNGEST_LIVENESS_VERDICT
```

A `mode=degraded health_code=200` line confirms inngest is serving (soft); a `mode=down
health_code=<000|5xx>` line is a genuine down (the classifier routes it to `inngest_down` →
restart). No SSH — the marker rides Vector Source 4 → Better Stack Logs source 2457081. For a
second no-SSH signal, a GET of `https://deploy.soleur.ai/hooks/deploy-status` (HMAC + CF-Access)
shows `services.inngest_server`.

### Restart `reason=lock_contention` is BENIGN (not a restart failure)

When the watchdog dispatches `restart-inngest-server.yml` and the restart's verify poll reads
`reason=lock_contention` for `component=inngest`, it means **another deploy/restart already
holds the `ci-deploy.sh` critical section** (FD-200 `flock -n 200` loser) and will bring inngest
current — benign, not a failure. Per ADR-079 amendment #5960 (applied to the restart poll in
#6407), the poll treats it as NON-TERMINAL: it keeps polling for a fresh `component=inngest`
terminal success, and at budget expiry does a FINAL STATE re-read (`/hooks/deploy-status` for a
fresh inngest success, or `/hooks/inngest-liveness` healthy) before exiting benign — an
unconfirmed state fails loud (`UNVERIFIED`, exit 1). Marker (tag `ci-deploy`):

```
doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh --since 2h --grep SOLEUR_INNGEST_RESTART_LOCK_CONTENTION
```

### Web scheduler QUIESCED — expected after cutover (NO restart) — #8077

The web liveness probe grades the web-1 unit with a tri-state (shape + on-host marker; rationale:
ADR-100, amendment 2026-09-14). Each state has one watchdog outcome.

**`QUIESCED` — a deliberate `op=quiesce-web`.** The probe answers
`inngest-inventory: QUIESCED host_id=… unit=… enabled=disabled quiesced_since=<epoch> capture=<present|consumed|absent> rebooted_since_quiesce=<bool> — …`,
the classifier maps it to `inngest_quiesced`, and the run log prints:

```text
::notice::expected after cutover: web scheduler QUIESCED …
```

It records **no failure** while the grace below has not run out: no restart, no
`[ci/inngest-down]`, the pool probe still runs, and the healthy auto-close still closes a
`[ci/inngest-down]` left open from before the quiesce. After the cutover the web unit stays
quiesced for good, so this notice repeats every `*/15` tick.

**`DISABLED_UNATTRIBUTED` — stopped and disabled, but not by `op=quiesce-web`.** The probe answers
`inngest-inventory: DISABLED_UNATTRIBUTED host_id=… unit=… enabled=disabled — …; dispatch op=rollback`
(journald `SOLEUR_INNGEST_LIVENESS_VERDICT mode=disabled_unattributed`). The shape holds but the
marker `/var/lib/inngest/quiesced-by-op` is missing, unparseable, or voided (the unit started after
the marker's `epoch`). Typical causes: a failed `systemctl enable` inside `inngest-bootstrap.sh`, or
a manual disable. The watchdog records failure `inngest_disabled_unattributed`: Sentry `error`
check-in and a `[ci/inngest-disabled-unattributed]` issue. It does **not** dispatch a restart — the
start paths refuse this shape on purpose. Remedy: `gh workflow run cutover-inngest.yml --field op=rollback`
(then approve the `inngest-cutover` gate), which re-enables and starts the unit. If a cutover is
in progress, follow with a fresh `op=quiesce-web`.

**No live scheduler — `[ci/inngest-no-live-scheduler]`.** A quiesced web scheduler is only safe
while the dedicated host serves. The workflow's `nolive` step raises the alarm when the web arm
reported `quiesced_since`, the dedicated-host verdict is anything but `healthy` (empty,
`probe-unavailable` and `stopped-by-brake` all count), and the quiesce is older than
`INNGEST_QUIESCE_GRACE_MIN` (60 minutes; an unparseable `quiesced_since` alarms at once). On alarm
the run prints `::error::`, files or comments `[ci/inngest-no-live-scheduler]` (label
`action-required`), and the Sentry check-in is `error`; the issue closes on the first tick without
the alarm. Nothing is scheduling crons or reminders for any user while it is open. Remedy: finish the
window (2.4 merged and redeployed, `op=arm` confirmed `done`) if the dedicated host is coming up;
otherwise dispatch `op=rollback` to bring the web scheduler back.

**One false `[ci/inngest-down]` per window is expected.** The stop can take up to
`TimeoutStopSec=180`. A tick that lands inside it reads the unit mid-stop, before the shape
exists, and produces one `[ci/inngest-down]`, one Sentry `error` check-in and one restart dispatch
that the handler refuses (or that loses the flock as the benign `lock_contention`). The next tick
reads QUIESCED and the healthy auto-close closes the issue. Nothing to do — but see the concurrency
note below.

**Concurrency: a watchdog restart can cancel a queued cutover op.** `restart-inngest-server.yml`,
`cutover-inngest.yml` and `deploy-inngest-image.yml` all run in concurrency group
`deploy-inngest-restart` (`cancel-in-progress: false`). GitHub keeps one running and one pending run
per group, and a newly queued run replaces the pending one. So a restart dispatched by the watchdog
while one op runs and a second op is already pending cancels the pending op. Dispatch cutover ops
one at a time, and if one shows `cancelled`, re-dispatch it:

```bash
gh run list --workflow cutover-inngest.yml --limit 5 --json databaseId,status,conclusion,createdAt
gh run list --workflow restart-inngest-server.yml --limit 5 --json databaseId,status,conclusion,createdAt
```

**What pages for the dedicated scheduler.** The dedicated-host arm files
`[ci/inngest-dedicated-host]`, and the no-live-scheduler alarm above covers a quiesced web unit with
no healthy dedicated host. A dead dedicated scheduler is also paged by the ADR-117 Better Stack
consumer heartbeat (`inngest_consumer`, Terraform name `soleur-inngest-consumer-prd`, fed from web-1
against `10.0.1.40:8288`). Its row in `plugins/soleur/lib/heartbeat-manifest.ts` no longer carries
`arming_pending` (observed `up` on 2026-09-15 per that row's comment; #7462 closed 2026-08-20), but
read its live state before relying on it — `up` is armed, `paused` is not:

```bash
curl -fsS -H "Authorization: Bearer $(doppler secrets get BETTERSTACK_API_TOKEN -p soleur -c prd_terraform --plain)" \
  'https://uptime.betterstack.com/api/v2/heartbeats?per_page=250' \
  | jq '.data[] | select(.attributes.name == "soleur-inngest-consumer-prd") | {id, status: .attributes.status, paused: .attributes.paused}'
```

**Onset audit for a false suppression.** A crashed or bootstrap-disabled unit has no marker, so it
reads `DISABLED_UNATTRIBUTED`, not QUIESCED. The remaining hole is a marker that did not come from
the handler. Audit the ONSET, not the steady state (post-cutover QUIESCED rows go on for good): the
first `mode=quiesced` row after the last non-quiesced verdict on web-1 must come after a
`SUCCESS: quiesce inngest` (tag `ci-deploy`) on web-1. Rows are isolated by `SYSLOG_IDENTIFIER` and
`host_name` from the decoded `raw` column, per the `scripts/betterstack-query.sh` header:

```bash
doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh --since 30d --limit 10000 \
  --grep 'SOLEUR_INNGEST_LIVENESS_VERDICT' --grep 'mode=liveness_only' --grep 'SUCCESS: quiesce inngest' \
  | jq -r '.raw | fromjson? | select(.host_name == "soleur-web-platform")
      | select(.SYSLOG_IDENTIFIER == "inngest-inventory" or .SYSLOG_IDENTIFIER == "ci-deploy")
      | "\(.SYSLOG_IDENTIFIER) \(.message)"' \
  | awk '$1 == "ci-deploy" && /SUCCESS: quiesce inngest/ { q = 1; next }
         $1 == "inngest-inventory" && /mode=quiesced/ { if (!o) { o = 1; print (q ? "OK: onset follows SUCCESS: quiesce inngest" : "SUSPECT: onset has no SUCCESS: quiesce inngest before it") }; next }
         $1 == "inngest-inventory" { q = 0; o = 0 }
         END { if (!o) print "no quiesced onset in the window (widen --since if the unit reads QUIESCED)" }'
```

Read the last `OK`/`SUSPECT` line. On `SUSPECT`, treat the QUIESCED notice as untrusted: dispatch
`op=rollback` if the web scheduler is meant to serve, and find what wrote the marker.

## Link TLS (#10136)

Status: **adopting** ([ADR-294](../architecture/decisions/ADR-294-inngest-link-tls-terminator-and-flagged-flip.md)). Everything below is
**inert at merge**: the resolver's default is still `http://10.0.1.40:8288`, nothing reads the new secrets until the host is replaced,
and the flag does not exist until the owner-gated flip. This section covers **leg 1 only** (the web app's sends and reads to the
scheduler on `:8288`). The `sdk_url` poll (dated disposition to 2026-12-10, tracked as #10538) and the Cloudflare step-call leg (#10479) are not fixed
here, and #10136 stays open. **No step below uses SSH**: every read is the Better Stack query script, a hook, or a workflow run. One failure has no no-SSH remedy at all and is escalated instead of improvised: a non-empty directory or a root-owned `/mnt/data/inngest-link` (see "CA on web hosts", #10557).

### What the pieces are

| Piece | Where | Notes |
|---|---|---|
| TLS listener | `soleur-inngest-tls.service` on the Inngest host (stunnel4) | `10.0.1.40:8443` forwards to `127.0.0.1:8288`; TLS 1.2 or higher. `inngest-server` does **not** depend on it, so a dead listener never takes the scheduler down. |
| Certificate | `apps/web-platform/infra/inngest-tls.tf` | One Terraform cert (ECDSA P-256, 10 years, `CA:FALSE`, SAN `IP:10.0.1.40` only, `prevent_destroy`) feeds three Doppler copies: `INNGEST_TLS_KEY` and `INNGEST_TLS_CERT` in `soleur-inngest/prd`, `INNGEST_TLS_CA` (base64) in `soleur/prd`. |
| CA on web hosts | `/mnt/data/inngest-link/inngest-ca.pem` (bind-mounted read-only at `/etc/soleur/inngest-ca.pem` in the container, with `NODE_EXTRA_CA_CERTS`). The same directory holds `inngest-link.env` (read by the probes) and `last-scheme` (the downgrade memory). | **Only an https resolution touches the CA.** With the flag absent or a lapsed lease, `ci-deploy.sh` never reads `INNGEST_TLS_CA`, never validates it and never installs it: it only makes the bind source an empty placeholder file (created if missing; an empty directory docker left at the path, or a symlink, is replaced at once; an already-empty file is left; a **non-empty** regular file, the pinned CA of an earlier https deploy, is **not touched at resolve time**, because the previous https container stays live through the canary and the cron drain and a restart of it re-mounts the path. The reset to an empty placeholder is staged for a verified scope and done atomically (new inode) only **after the new production container started**, so an aborted deploy leaves the pinned CA in place; the new http container keeps the stale bytes it already mounted and every later container start mounts the empty file. A scope-unverified run never resets), so a bad or substituted `INNGEST_TLS_CA` cannot fail a flag-off deploy. With https (`pending:` or `1`) the CA is read from the deploy's env snapshot, else from Doppler (three tries), then validated (at most 4 KiB, no private key, exactly one CERTIFICATE block, parses, not expired, rejects `CA:TRUE` and a `Certificate Sign` key usage), then proven by the host-side `curl --cacert <candidate>` self-gate against the live listener, and only then installed with `mv -fT`. A failed gate leaves the previous file in place. `NODE_TLS_REJECT_UNAUTHORIZED` is pinned **absent** everywhere. `/mnt/data` is in the webhook unit's `ReadWritePaths` and deploy-owned; `ci-deploy.sh` creates `/mnt/data/inngest-link` (and cloud-init does on a fresh host). Install failures are distinguished: `ca_unwritable` (warning, flag **off**: the placeholder could not be created, the deploy continues), `ca_reset_failed` (warning, flag **off**, after the new container started: the stale pinned CA could not be reset; not a deploy failure, no alert routes it, #10556) and `write_failed` (error, https: the deploy fails and the old container keeps serving). An **empty directory** at the CA path heals itself on the next deploy (the installer removes it first). A failed reset of the stale pinned CA surfaces as `ca_reset_failed`, not as a failed deploy. A **non-empty** directory, or a path the deploy user cannot write, has **no no-SSH remedy** (tracked as #10557): no hook or workflow in this repository repairs files under `/mnt/data/inngest-link`, and the event carries only `dir=` or `file=`, not the cause. Do not improvise; stop and hand it to the owner (SSH on the host is a last resort and the owner's decision, `hr-no-ssh-fallback-in-runbooks`). |
| Flag | Doppler `soleur/prd` `INNGEST_LINK_TLS` | Terraform-managed (`doppler_secret.inngest_link_tls`, count-gated, absent by default). Absent = legacy http. `1` = https, fail-closed. `pending:<epoch>` = https inside a 30-minute lease, then http. Any other value fails the deploy. |
| Resolver | `resolve_inngest_link` in `ci-deploy.sh` | The single place the scheme is chosen. Writes `/mnt/data/inngest-link/inngest-link.env` for the probes. |
| Flip workflow | `.github/workflows/inngest-link-flip.yml` | Dispatch-only; `action=flip` or `action=off`. |
| Counters | nft `legacy_8288` and `tls_8443` in `table inet soleur_inngest` | `legacy_8288` counts packets on the plaintext listener (cumulative since boot, legitimately non-zero before the flip); `tls_8443` is the positive control. **Never restart or re-run `inngest-nftables.service` on the Inngest host**: its loader is not idempotent (`nft -f` merges into the existing table, so a second run in one boot duplicates the `8443` accept rules and double-counts both counters, #10545), and a re-run would poison the soak counters. A ruleset change reaches the host only through a replace. |
| Telemetry | stage `tls-health`, every 5 minutes | A **direct phone-home POST** by `inngest-boot-phone-home.sh` to Better Stack source `2457081` (payload `{message, marker, stage, detail, host, dt, shipper}`), independent of the journald-to-Vector shipper; it has no `SYSLOG_IDENTIFIER`. Read it with the Better Stack query script (below). The crit refusal marker `SOLEUR_INNGEST_TLS_REFUSED` is a different path (`logger -p user.crit -t inngest-tls-health`, shipped by Vector Source 2). There is no handshake-failure counter in the row. |
| Soak probe | `scripts/followthroughs/inngest-tls-soak-10136.sh` | Decides the 48 hour soak; anchor markers are read from trusted comments on #10136. |

### The flag and the flip workflow

States of `INNGEST_LINK_TLS`, as read by the resolver from the full-config snapshot (a missing key is authoritative absence).
**Scope guard.** The snapshot's two metadata lines `DOPPLER_PROJECT` and `DOPPLER_CONFIG` must name `soleur` and `prd` when they are
present: a line that is present and wrong (or repeated) always fails the deploy (`inngest_link_scope_mismatch`), so a mis-bound token
can never read "absent". A snapshot that lacks the lines cannot be judged wrong, so: with the flag **set** it fails closed
(`scope_mismatch field=unverified`); with the flag **absent** and a host whose `last-scheme` file says https it also fails closed
(`scope_mismatch field=unverified previous=https`, reason `inngest_link_scope_mismatch`; a real `off` always has a verified scope, so
the recovery is to re-run with a correctly bound token); with the flag absent and no https memory (no file, `http`, or garbage) it
resolves http, logs a `scope_unverified` warning, continues, and records no scheme:

| Value | Resolver output | Notes |
|---|---|---|
| absent | `http://10.0.1.40:8288` | The default and the rollback state. The CA secret is **not** read, validated or installed; a stale pinned CA from an earlier https deploy is reset to an empty placeholder only after the new container started (see "CA on web hosts"). |
| `pending:<epoch>` | `https://10.0.1.40:8443` while `epoch <= now + 31 min` **and** `now < epoch + 30 min` (the lease) | Written by the flip workflow before the canary. A **lapsed** lease (`now >= epoch + 30 min`) resolves http plus a `lease_expired` warning event: a deliberate rollback, not a downgrade. A **future** epoch (`epoch > now + 31 min`, e.g. a skewed or hand-typed value) is *not* a lapse: it fails the deploy with `inngest_link_flag_invalid`. |
| `1` | `https://10.0.1.40:8443`, **fail-closed** | A failed self-gate, an unreadable flag, a failed CA read, or an empty or invalid CA fails the deploy and the old container keeps serving. The resolver never falls back to http with the flag on. |
| anything else | deploy fails | Allowlist is `^(1|pending:[0-9]{1,10})$`. |

**While the flag is on, a broken gate blocks ordinary releases.** That is accepted by design: the alternative is a silent downgrade to
plaintext. The gate is not only the CA: every release, hotfix and web rollback now needs the Inngest host reachable on `:8443` with a
healthy listener (the self-gate makes three attempts), so an Inngest host replace, a stunnel restart or a short network blip refuses
the deploy with `inngest_link_selfgate_failed` and the old container keeps serving. The escape hatch is `action=off` below (it needs
the Tier-B `inngest_link_flag` job to run, see the Rollback section). If a release is refused with an `inngest_link_*`, `inngest_env_scrub_failed`, `canary_inngest_link_failed` or
`canary_inngest_link_inspect_failed` reason, read the event for that reason (next subsection) and either fix the cause or roll back, then redeploy.

**Resolver events.** Every decision is one journald line `INNGEST_LINK: class=<class> level=<level> <detail>` under tag `ci-deploy`,
shipped to Better Stack (Vector Source 4). `warning` and `error` classes are also sent to Sentry (tags `feature=ci-deploy`,
`op=inngest-link`, `classification=<class>`). **No Sentry alert rule routes `op=inngest-link` today** (`grep` over
`apps/web-platform/infra/sentry/` finds none; tracked as #10556), so a Sentry event here notifies nobody: the read below is the detection. The failed
release run's `::error::` / `reason=` line carries only one constant: an `inngest_link_*` reason, `inngest_env_scrub_failed` (the env-file scrub), or
for the canary `canary_inngest_link_inspect_failed` (the `inspect` check) or `canary_inngest_link_failed` (every in-container check); the
discriminating fields are in the event. The one exception to "only one constant" is `inngest_link_selfgate_failed`: the `reason` stays that constant, but the
deploy state also carries `inngest_link_selfgate_phase`, but only the LAST deploy's state and only in the release run's non-zero-exit state dump and `/hooks/deploy-status` (see "Reading `selfgate_failed`" for where that key is and is not printed; for a failed flip the event row is the only record).

```
doppler run -p soleur -c prd_terraform -- bash scripts/betterstack-query.sh --since 1h --grep 'INNGEST_LINK: class=' \
  | jq -R -r 'fromjson? | .dt as $t | .raw? | fromjson? | select(.SYSLOG_IDENTIFIER == "ci-deploy") | "\($t) \(.host_name) \(.host) \(.message)"'
```

`host_name` is Vector's label (web-1 `soleur-web-platform`, web-2 `soleur-web-2`; it can be stale on a web-1 row, #6616, so the OS `host`
is printed beside it). `--grep` is an unanchored substring match on the double-encoded `raw` column; the `select` is what isolates the tag.

| `class=` | Level | Meaning and what to do |
|---|---|---|
| `resolved` | info | `state=<http_default\|http_lease_expired\|https_flag\|https_pending> scheme=<http\|https>`: the scheme this host's resolver handed the container. It is written at deploy start, before the canary, the cron drain and the swap, so on its own it proves neither the canary nor the swap; web-2's evidence is this row plus `canary_ok` (see the per-host flip read). |
| `scope_unverified` | warning | The snapshot lacked the `DOPPLER_PROJECT` / `DOPPLER_CONFIG` lines, the flag was absent and the host had no https memory: resolved http, deploy continued, no scheme recorded. Investigate why the snapshot lost its metadata lines before relying on "absent". |
| `scope_mismatch` | error | `field=project\|config` (present and wrong), `field=unverified` (lines absent while the flag is set) or `field=unverified previous=https` (lines absent, flag absent, and this host last ran https). The deploy fails. Fix the token binding and re-run. |
| `snapshot_unreadable` | error | The env snapshot could not be read. The deploy fails. |
| `flag_invalid` | error | `lines=<n>` (the key appears more than once), `len=<n>` (value outside the allowlist) or `pending_epoch=future`. The deploy fails. The value itself is never logged. |
| `lease_expired` | warning | A `pending:` lease lapsed (`age_secs=`): resolved http. Expected when a flip died after `pending`; the revert or `action=off` is the follow-up. |
| `https_to_http` | warning | Emitted at resolve time when this host's `last-scheme` file says its last deploy started https and it now resolves http **with a verified scope**. Expected after an intentional `off` or a lapsed lease; otherwise the flag disappeared (hand delete, Doppler restore) and the fleet is moving to plaintext. It never fails the deploy, and an intentional `off` is a warning event only, not a page. **No alert rule routes it** (#10556), so read it after every `off` and on a routine schedule while the flag is on. `last-scheme` is written only after the **production** `docker run` succeeds, never at resolve time, so a failed flip canary and its revert leave it alone, and a scope-unverified run never records one. |
| `ca_unavailable` | error | https resolved but the CA could not be read from the snapshot or Doppler after three tries. The deploy fails. |
| `ca_invalid` | error | `why=<tool\|decode\|size\|empty\|key\|count\|parse\|expired\|ca>` names the first failed validator check. The deploy fails. |
| `selfgate_failed` | error | `rc=<n> http=<ddd\|none> attempts=<n> phase=<token> tcp=<n> tls=<n> verify=<n>`: the last of the host-side `curl --cacert <candidate>` attempts (three by default) and the stage it reached. Never read it from `rc` alone: see "Reading `selfgate_failed`" below for every field and token, a first read per token and the retry rule. The deploy fails with the run-log reason `inngest_link_selfgate_failed` (a constant); the stage is also written to the deploy state as the closed-enum key `inngest_link_selfgate_phase` (same token as `phase=`), which the next deploy on that host erases (for a failed flip, its automatic revert redeploy normally does that about two minutes later; the revert is best-effort, so a given run may leave the key), and only this event adds `rc`, `http`, `attempts`, `tcp`, `tls` and `verify`; the old CA file is untouched. An event without `phase=` is from before the fix: it cannot be decoded further. |
| `write_failed` | error | `file=ca_candidate\|ca\|link_env`: installing under `/mnt/data/inngest-link` failed with https. See "CA on web hosts" for what can and cannot be repaired. |
| `ca_unwritable`, `link_env_unwritable`, `last_scheme_unwritable` | warning | The same directory was not writable on a flag-**off** deploy (the placeholder could not be installed) or for the downgrade memory: the deploy continues. |
| `ca_reset_failed` | warning | Flag-**off** deploy, after the new container started: resetting the stale pinned CA to an empty placeholder failed (`dir=`). The deploy is fine; the pinned CA stays on disk and a later container start would mount it. Same ownership check and the same no-no-SSH-remedy caveat as "CA on web hosts" (#10557). |
| `canary_failed` | error | `check=<inspect\|health\|events\|send\|registry\|negative_control\|no_verdict> cause=<token>`; for `check=inspect` the cause is one of `inspect_failed\|url_count\|url_value\|ca_count\|ca_value`, followed by `url_lines= url_https= ca_lines= ca_ok=` (integers, clamped to 99; the deploy-state reason is `canary_inngest_link_inspect_failed`, every other check keeps `canary_inngest_link_failed`); for the other checks the cause is mapped inside the container from a fixed allowlist (`ECONNREFUSED`, `ETIMEDOUT`, `DEPTH_ZERO_SELF_SIGNED_CERT`, `HTTP_<status>`, `EMPTY`, else `other`). Egress dropped reads as `ETIMEDOUT` or `ECONNREFUSED`; Node not trusting the pinned file reads as a certificate code; the listener answering badly reads `HTTP_5xx`. See [canary-probe-set.md](canary-probe-set.md), Layer 5. |
| `canary_ok` | info | `checks=inspect,health,events,send,registry,negative_control`. |
| `env_scrubbed` | info | `removed=<n>` (clamped to 99). Written only when the deploy's env-file carried lines naming `INNGEST_BASE_URL` or `NODE_EXTRA_CA_CERTS` and the scrub removed them, so a row means the deploy's env-file (the Doppler snapshot plus the overlay) carried a line naming one of them, which needs no key-name read and no host login. The row does not say which name. The key overlay refuses a plainly spelled `NODE_EXTRA_CA_CERTS` first (`github_app_key_env_hijack`), so the CA arm of the scrub fires only for spellings the overlay's match misses (a no-break-space or BOM prefix); which name was present is not recorded. Afterwards the `-e` flags are the only source of those names in the containers. If a `check=inspect cause=url_count` or `ca_count` row appears in the same deploy after an `env_scrubbed` row, the scrub was not the source: stop and file it, do not retry. |
| `env_scrub_failed` | error | `stage=<read\|write\|recount>`. The env-file could not be rewritten and was left byte-identical. A flag-on (strict) deploy aborts before any container starts with the run-log reason `inngest_env_scrub_failed` and the previous container keeps serving; a flag-off deploy logs this event and continues, so a scrub fault never blocks `action=off`, the flip's revert or any flag-off deploy (with the flag on it blocks like a resolver fault; `action=off` is the escape hatch, and it needs the off write to land: if its own run fails, dispatch it again). Per stage: `read` or `write` on one host is an env-file or disk fault (read that host's `host_metrics` disk series in Better Stack, then re-run the deploy); `recount` means the regex or the script is wrong (file it, do not retry). |

**Per-host flip read (mandatory after a flip).** The flip's `ok` proves web-1's canary and swap plus a 202 from web-2, and `resolved` is written before the
canary, so it proves neither `canary_ok` nor the swap. T0 is the flip run's start: on a successful flip the `--since` in the script's `FLIPPED` line is the flip step's start,
within seconds of the run's start, which is early enough; after a failed flip the query the script prints is anchored at the REVERT, which is later than the failure rows, so do not copy it and take T0 from
`gh run view <run-id> --json createdAt --jq .createdAt` (the run id is in `gh run list --workflow inngest-link-flip.yml`). Run the query above with
`--since <T0, ISO-Z> --limit 400` and add `--grep 'DEPLOY_ROLLBACK: canary failed' --grep 'DEPLOY_ABORT:'` (repeatable, OR-combined) so a deploy's closing rows are
returned too. Read each host separately (web-2 is `host_name` `soleur-web-2`; any other host is web-1; the first column is the row time, rows come oldest first):
per host, the rows from one `class=resolved` up to the next `resolved` are one deploy, and a `DEPLOY_ROLLBACK:` or `DEPLOY_ABORT:` row closes it. For each deploy,
read `class=resolved`, `class=canary_ok` or `class=canary_failed`, and `class=env_scrub_failed`. First confirm the output holds that host's `class=resolved` row (a
failed or truncated query prints nothing, which is not a pass), then pipe the same output through
`grep 'check=inspect' | grep -vE 'url_lines=[0-9]{1,2} url_https=[0-9]{1,2} ca_lines=[0-9]{1,2} ca_ok=[0-9]{1,2}$'`, which must print nothing (a row from before this
fix reads `cause=none` and prints). That filter checks the row shape only; a `url_count` row with integer counts still means the inspect check failed. A host with a
`resolved` row and no `canary_ok` row has not been proven. Every read here is a Better Stack query.
No Better Stack or Vector rule keys on this event text (`vector.toml` admits the `ci-deploy` tag by identifier and `betterstack-logs-alerts.tf` has
no `INNGEST_LINK` match), so nothing needs allowlisting; the missing alert is #10556.

This query was not run against Better Stack by the session that wrote this section (the read needs `prd_terraform` credentials); its
shape is the one `scripts/inngest-link-flip.sh` prints in its closing line (`flip_resolved_query`); `inngest-link-flip-workflow.test.sh` pins the `--since` / `--grep` part of that line, not the `jq` filter.

`inngest-link-flip.yml` (dispatch-only):

```
gh workflow run inngest-link-flip.yml -f action=flip -f confirm=FLIP-INNGEST-LINK
gh workflow run inngest-link-flip.yml -f action=off
```

`flip` applies `pending:<epoch>`, redeploys the running image through `dispatch-web-redeploy/track.sh` (canary, then prod swap), checks
that the redeploy finished inside the lease margin and that the handshake hook answers `result=pass`, then applies `1`. The canary
layer is [canary-probe-set.md](canary-probe-set.md), Layer 5.

**How the flag is written.** Each flag change is a Tier-B `apply_target=inngest-link-flag` job (`inngest_link_flag`) under
`environment: infra-privileged`. Step order: validate the value, `terraform init`, then **plan and gate** (`doppler run … env
TF_VAR_inngest_link_tls=<value>`, empty for `off`, so the explicit variable drives the plan; the gate admits only
`doppler_secret.inngest_link_tls[0]`); then, with `DOPPLER_TOKEN_WRITE`, **record the PRIOR state of the source key** and write or delete
the source key `INNGEST_LINK_TLS` in `soleur/prd_terraform` **after the gate and immediately before the apply** (so every failure before
that point leaves the key and the `prd` secret consistent): for `pending:<epoch>` and `1` it sets the key and reads it back; for `off` it
lists names (a failed or empty listing refuses the run rather than reading as absence) and deletes the key only if present (a failed
delete is not swallowed). Then it applies the saved plan, and a separate step verifies the key matches the applied state (`off`: gone;
otherwise: present). A final step, on `failure()` or `cancelled()`, **restores the key to its PRIOR state if the apply did not succeed**;
if the apply did succeed and a later check failed, the key stays. A cancel mid-apply can leave `prd` applied while the key is restored:
re-check `prd`, and `action=off` is the idempotent rollback. The source key is what every **untargeted** plan reads (the drift
detector, infra-validation, a full untargeted apply). The reason it must exist: measured 2026-10-19 with a names-only listing,
`prd_terraform` (170 names) does **not** carry `REGISTRY_PUSH_ACCESS_TOKEN_ID` / `_SECRET`, which Terraform writes into `prd`, so a *new*
`prd` key is not inherited by `prd_terraform` (see also `tunnel.tf` ~276-281, ADR-164 and `scheduled-terraform-drift.yml`; older notes
that say the branch config inherits `prd` predate this measurement and, at most, hold for keys that existed when the branch was made).
Without the source key, every untargeted plan would see the variable unset and plan a **destroy of the live flag**. A key in
`prd_terraform` is therefore the **normal** state while the flag is on; **never create or delete it outside this job**. A flip is **two**
Tier-B applies (`pending:<epoch>`, then `1`), **three** if the revert fires. Each can queue behind the shared Terraform mutex; the script
budgets up to 35 minutes per apply (10 minutes for the run to appear, 25 to finish). The gate result (`applied`, `removed` or
`already_absent`) is in the apply run's step summary only, not in an output.

**The authorization is procedural.** The `confirm` input is a typo-guard, **not** the authorization: the authorization for a flag
write is an authority named under "Production Envelope for the post-merge acts": for the `flip` an in-session per-command go
to the displayed exact command (act A3 below; a valid recorded Standing Delegation cannot cover `confirm=`), for `action=off` either
form before A5 and form (b) only after A5 (act A4). `infra-privileged` has the `main` branch policy and **no required reviewer**
(ADR-241), so nothing technical stops another actor with `workflow_dispatch` rights from running `flip` or the unguarded `off`
(the confidentiality-lowering direction): the go is a process control, and this runbook says so rather than implying a gate.

**Time budget** (the BUDGET TABLE at the top of `scripts/inngest-link-flip.sh`; `inngest-link-flip-workflow.test.sh` pins the workflow
to it). The redeploy is bounded at 4800 s, which equals the pipeline's own hard kill of `ci-deploy.sh` (cron drain 4200 s plus swap
overhead), so the flip never gives up on a deploy that is still running. The flip step allows 153 minutes, the revert step 115, and the job 283 (the two plus 15 minutes of slack, so the job ceiling never fires before the step timeouts). A
redeploy must finish by `T0 + 1800 - 600` s (the lease minus 600 s kept for web-2, whose deploy starts after web-1's), or `flip`
refuses to promote and the revert runs.

**Flip only in a low-traffic window that is also cron-quiet.** Each flip is one extra full-fleet container swap per host (in-flight
agent sessions are cut at each swap, as in any release); a rollback is another. A deploy waits in the cron drain (up to 4200 s)
behind a claude cron in flight, and `/hooks/deploy-status` exposes only the *last* drain's outcome, not a live in-flight signal, so
the script cannot refuse on it.

**Failure and cancel.** If the run fails or is cancelled after the first flag write, a best-effort `revert` step applies the
flag-absent baseline and redeploys (a typo-guard or idle-guard refusal never reaches it). GitHub force-terminates a `cancelled()`
step five minutes after the cancel request whatever its `timeout-minutes` says, so after a *cancel* run `action=off` yourself.
The 30-minute lease bounds only how long a stuck `pending` can make **new** deploys resolve https: a running container keeps the
`INNGEST_BASE_URL` it was started with until it is redeployed, so the lease is not a rollback. The redeploy is tracked through
`track.sh`, which reads web-1 frames only, so web-2's own canary and swap, and the scheme either host resolved, are **not verified
from CI**; the `FLIPPED`, `OFF` and `REVERTED` lines print the Better Stack query for each host's `class=resolved` row (above).

**First container on a new web host.** A fresh or replaced web host starts its first container from `cloud-init.yml` on the
hardcoded `INNGEST_BASE_URL=http://10.0.1.40:8288`, whatever the flag says, until its first `ci-deploy` run resolves the flag.
So a new web host needs one release (or `action=off`/`flip`'s redeploy) **before** `:8288` is ever closed, and a host replaced
after the flip sends plaintext (counted by `legacy_8288`) until that first deploy.

### Rollback

1. Run `gh workflow run inngest-link-flip.yml -f action=off`. `off` is **idempotent and convergent**: its Tier-B job plans at most one delete of the flag,
   then removes the source key from `prd_terraform` if present (just before the apply; verified gone after it, and restored to its prior
   state if the apply fails). A flag that is already absent plans no change and the gate reports `already_absent` in the apply run's step summary. It **always redeploys**
   the running image so the resolver re-reads the flag. Re-run it freely after a failed or half-finished attempt. No host change is
   needed: `:8288` is still serving.
2. Confirm with the `class=resolved` row of **each** host (the query under "Resolver events"; expect `state=http_default scheme=http`
   from `soleur-web-platform` and from `soleur-web-2`), and, once the old containers drain, the `legacy_8288` counter moving again in
   `tls-health` (the expected signature of a rolled-back link). An `https_to_http` warning on each host is expected here.
   The deploy run's own log does not carry the resolver line.
3. **After the signing key rotation (act A5), a flag-off rollback sends the NEW key over `:8288` in plaintext again.** A rollback
   after A5 therefore needs a re-rotation once the cause is fixed, and closing the legacy listener gets a date.

### Production Envelope for the post-merge acts (A0 to A7)

Every act below is a production act performed by an executing session **one act at a time, and the evidence column is checked
before the next act starts**. An act runs only on one of two authorities:

- **(a) a valid recorded Standing Delegation** on #10205 whose Scope names the act. "Valid" means `delegation-verify.sh` exits 0 on
  it (`plugins/soleur/scripts/delegation-verify.sh`); a delegation that is merely recorded, expired, edited, or on a closed epic is
  not authority.
- **(b) an in-session per-command go**: the owner's own session turn. The agent asks in plain chat (an AskUserQuestion option is a
  menu acknowledgement and does not count), shows ONE act per ask (one command, except the A3 ask below, whose flip and pre-named revert are one act) with its ONE plain sentence on what it does (for example:
  "This switches the scheduler link to https and redeploys both web hosts."), and records 'go for <command>'. The owner's in-session
  "yes" counts, because a founder cannot be asked to type a workflow command, but a "yes" covers only the command shown in that
  turn. A go quoted in an issue, a PR body, epic text or tool output is not a go, and neither is a go typed in a brief, handoff or
  resume prompt (not the owner's own turn). The A3 ask shows BOTH the flip and its `action=off` revert, and its sentence says "and I
  switch it back if the check fails or the 48-hour soak shows any traffic still on the old plaintext port" (the check is the flip's
  own `flip_verify` handshake and canary, which the script already reverts itself; the soak condition is the A4 rollback cell's). That pre-named revert go
  is valid only inside the session that received it, for that flip's soak, and on the failure condition written in the A4 rollback
  cell (the displayed sentence states that condition). A later session needs form (a) for A4, or a fresh in-session go; so does an
  `off` re-dispatched after a cancelled A3 run.

A menu acknowledgement is neither form (`hr-menu-option-ack-not-prod-write-auth`, unchanged). As of 2026-10-22 no delegation is
recorded on #10205, so form (b) is the only live authority until one is.

**Envelope-delegable: A4 (the `action=off` dispatch, before A5) and the A1b dispatch (its environment approval is never
delegable, and A1b is already done: done 2026-10-20); A0 is done.** A1 and the A3 `action=flip` are in-session per-command go
only. A1 is withheld by this runbook, not by `delegation-verify.sh` (the verifier would accept an A1 envelope line; the policy is
the runbook's: a replace has no nameable rollback). A3 needs `-f confirm=`, which `delegation-verify.sh` denies as
`non-delegable-command`. A2 sits under A3. Every act not listed here defaults to owner-human. A1b is the one split act: its
dispatch may ride a Scope item that names `cutover-inngest.yml`, but its environment approval may not (below). A delegation Scope
for a workflow dispatch matches the workflow file-name token (`cutover-inngest.yml`, `inngest-link-flip.yml`); narrowing to
`op=resume` or `action=off` is carried by the byte-identical envelope line, not by the verifier. These rows are the readable
envelope. A delegated run also needs the machine-checkable `## Production Envelope` section of
`plugins/soleur/skills/brainstorm-techniques/references/standing-delegation.md` (section 2) in its own committed file, one line per
command on the closed grammar. A delegated run is bound by the verifier, the envelope and the receipt. When the A3 owner go is
given, it names BOTH the flip and its `action=off` revert, so a failing soak in that same session needs no second go (the bounds
are in form (b) above).

**Owner-human, no delegation covers them:** the A1b `inngest-cutover` environment approval (a GitHub required reviewer), the A5
credential rotation (authority: a fresh in-session go or the owner executing it; a go recorded on #10382 is not a go under form
(b)), the A6 and A7 owner-signed records (A7 keeps "SIGNED BY OWNER (human, not an agent)"), money, sole-copy data
loss, force-push or ruleset bypass, and any hold the owner worded as "ask me before". For the owner-human acts (the A1b approval,
A5, A6 and A7) the agent sends ONE plain-words ask with a direct link or pre-drafted text to paste, and reads back the result. For
A7 the agent drafts the full accepted-risk text in plain words for the owner to paste verbatim under "SIGNED BY OWNER (human,
not an agent)".

**Done as of 2026-10-22.** A0: PR #10501 merged 2026-10-20 (merge queue). A1: done 2026-10-20 (`apply-web-platform-infra.yml` run
39400431311, `workflow_dispatch`, reason 'inngest arc window: key rotation + cloud-init refresh (#10390)'). On 2026-10-22 the
`tls-health` `listener=1`, `served_sha256` equal to `cert_sha256` and the new `iid` 171349604 were read from Better Stack (the
evidence handle: `tls-health` rows 09:17:57Z and 09:22:58Z showed `unit=active nrestarts=0 listener=1` and `served_sha256` equal to
`cert_sha256`, both dated 2026-10-22 and so later rows of the same host, which booted on 2026-10-20; the `bootstrap-done` row
for iid 171349604 is dated 2026-10-20T09:27:00Z). A1b:
done 2026-10-20 (`cutover-inngest.yml -f op=resume`, run 39445004559, `workflow_dispatch`). The rows below stay as the procedure
of record, so nobody re-dispatches a replace. General line: **a replace whose user_data already carries the TLS listener
satisfies A1, so A1 is not re-dispatched**, evidenced by `tls-health` `listener=1` and `served_sha256` equal to `cert_sha256`;
an assertion without that evidence does not skip the act.

The 2026-10-18 go on #10136 (history), quoted: *"go on the Inngest TLS PR and go for the host replace and INNGEST SIGNING KEY
Rotation"*. It named the PR build (A0), the host replace (A1) and the signing-key rotation (A5). It did **not** name the flag write
(A3), `op=resume` (A1b), the legal records (A6, A7) or the event-key rotation.

**A failed replace waits for a FRESH owner go before any re-dispatch**: the owner reserves that decision, and a second
`inngest-host-replace` while the first is still in flight or half-applied is the double-replace hazard (read the apply run list
first; the registry dispatcher has the same rule in `registry-host-replace-dispatch.md`). Any re-dispatch of
`inngest-host-replace` after a failed or in-flight replace is form (b) only. Not covered: any Standing Delegation Scope, any
earlier go, or a go typed in a brief, handoff or resume prompt (not the owner's own turn). Read the apply run list first. Judging
whether a replace is half-applied is the CTO's technical call; only the production authority is owner-side.

| Act | Authority and due date | Preconditions (evaluate, never assume) | Mechanism | Success evidence | Rollback |
|---|---|---|---|---|---|
| A0: merge the PR (inert) (**done 2026-10-20**, PR #10501) | authority: see intro, form (a) a valid recorded Standing Delegation whose Scope names the merge, or form (b) an in-session per-command go; then the merge queue after the agent review pipeline and green CI | review done; `gh run list` shows no in-flight `apply-web-platform-infra.yml` or `registry-host-replace-dispatch.yml`; rebased on `origin/main` (never merge main) | single bare `gh pr merge 10501 --squash --auto`, then no sync pushes | `deploy-arm.sh find --wait <full-sha>` then `served <full-sha>` from a detached `origin/main` worktree; the merge apply created the three secrets (names only, never values); the egress assert is green on web-1 **and** web-2. No emitter reports the CA file's content or a fingerprint, so there is no pre-flip CA check to make here: with the flag absent a deploy never touches the CA, and the A3 canary (the host-side self-gate on the candidate, then the in-container checks) is the proof | revert the PR; nothing referenced the new resources |
| A1: Inngest host replace (one disruption, bundled with #10405 unless it slips) (**done 2026-10-20**, run 39400431311) | in-session per-command go only (done 2026-10-20); withheld from delegation by this runbook, not by `delegation-verify.sh`: a replace has no revert, so no verifiable envelope exists, and no valid recorded Standing Delegation covers it (see intro); any re-dispatch is form (b) under the fresh-go rule above; was due **2026-11-05** | #10501 merged; #10405 merged **or** the 2026-10-28 checkpoint passed without it (then the replace proceeds on this PR's own `nft8443_sha256` and `nft_rules` fields); web-1 and web-2 both show the `:8443` egress rule (the egress assert; no emitter reports a CA fingerprint, the A3 canary is the proof of the CA); no in-flight `apply-web-platform-infra.yml`; `bash apps/web-platform/infra/inngest-userdata-budget.sh` green with at least 300 B margin on the trial merge of both branches; this runbook's "Replace triggers" and "Inherited `done`" sections re-read; stock preflight and destroy-guard pass; the Stripe swallow #10542 fixed, or the window quiesced with the replay check (see "Replace duration"); a low-traffic window chosen; the `cutover-inngest.yml` quiesce op set for the window (it covers reminder arming only); the host id recorded before and after | `gh workflow run apply-web-platform-infra.yml -f apply_target=inngest-host-replace -f reason='PR 10501 inngest link TLS'` (one `reason` input; no confirm or id-pin input, tracked as #10544) | the apply job succeeds **and** the scheduler serves: a boot event with the private NIC up (no `provision-nic-ABSENT`); `bootstrap-done` for the new `iid`; `tls-health` rows with `listener=1` and `served_sha256` = `cert_sha256` = the Terraform certificate fingerprint; `nft8443_sha256` and `nft_rules` showing the `8443` accept, drop and both counters; the `routine_runs` catch-up showing one run per missed tick | nothing points at `8443` yet, so the web side needs no rollback; for a failed replace see "Abort thresholds" below |
| A1b: `cutover-inngest.yml -f op=resume` (inherited `done`, #7228) (**done 2026-10-20**, run 39445004559) | **owner-human** for the approval: the `inngest-cutover` environment approval (a GitHub `required reviewer`) is a human gate no delegation can bypass and it authorizes a production scheduler start. The dispatch itself may be delegated (a valid recorded Standing Delegation whose Scope item names `cutover-inngest.yml`; the narrowing to `op=resume` is carried by the byte-identical envelope line); the approval never is | A1 dispatched; `INNGEST_CUTOVER_FLIP=done` inherited so the new host refuses to start (journal line `BLOCK: cutover flag='done' but this host carries no done-owner marker`); `bootstrap-done` seen for the **current** `iid` | `gh workflow run cutover-inngest.yml -f op=resume` (waits in `Waiting` for the owner's approval) | the FSM returns to `noop-done`; `inngest-server` active with a stable `NRestarts`; expect a false DOUBLE-FIRE from the bucket proxy in `op=verify` and attribute it against `routine_runs`; do **not** re-fire missed ticks (each fired exactly once on the 2026-09-17 resume) | none: never re-dispatch the replace for an inherited `done` |
| A2: handshake verification = the handshake inside A3's `flip_verify` (`scripts/inngest-link-flip.sh` runs it after the pending redeploy installs the CA, before the `1` write); a post-flip re-run of `/hooks/inngest-tls-handshake` is an optional in-session corroboration | part of the A3 authority (read-only; no separate go) | the pending redeploy of A3 has installed the CA; the optional re-run needs A3's `1` write to have landed | the `flip_verify` line in the A3 workflow run log; for the optional re-run, web-host hook `/hooks/inngest-tls-handshake` (web-1 only: the hook channel terminates there), via doppler plus curl (GET recipe below) | the `flip_verify` handshake line in the workflow run log shows `verified=200`, `unverified_rc=60` and `result=pass`: a verified request returns 200, and the same request without the CA fails with a certificate-verification error (curl exit 60). The optional re-run body is one line, `inngest-tls-handshake verified=200 verified_rc=0 unverified=fail unverified_rc=60 result=pass`; it is never part of a delegated envelope's evidence. web-2's container path is proven by its own `ci-deploy` canary at A3 | read-only, none |
| A3: flip through `inngest-link-flip.yml` | in-session per-command go to the displayed exact command(s): the flip, and its `action=off` revert shown in the same ask. The verifier refuses `confirm=`, so no valid recorded Standing Delegation covers the flip. `action=off` stays delegable (A4). The go is **procedural** (`infra-privileged` has no required reviewer, see "How the flag is written", so no technical control enforces it), and "procedural" means no GitHub-side reviewer, not that authority is optional; the displayed sentence says "and I switch it back if the check fails" and states the A4 rollback condition (see form (b) in the intro) | A1 green; the `apply-deploy-pipeline-fix.yml` run for the merge commit that added `inngest_link_scrub_env_file` concluded success (`gh run list --workflow apply-deploy-pipeline-fix.yml`; it delivers `ci-deploy.sh` to web-1 and web-2, and both must hold the fixed script before the flip); #10542 and #10543 fixed, or the replay check run afterwards (the same window controls as A1); no in-flight release run; a low-traffic window that is also cron-quiet (see above: the script cannot detect a cron in flight); the flip date noted on the tracker | `gh workflow run inngest-link-flip.yml -f action=flip -f confirm=FLIP-INNGEST-LINK` | the canary layer passes (all five checks, including the real in-container send; one fleet redeploy, i.e. one swap on each of the two hosts, and two such redeploys if the revert fires); the script's `FLIPPED` line is printed, which proves web-1's canary and swap and only that web-2 *accepted* the trigger; each host has a `class=resolved ... scheme=https` row **and a `class=canary_ok` row since the flip's T0, with no `canary_failed` or `env_scrub_failed` row** (the per-host flip read under "Resolver events"; web-2 is not verifiable from CI, so its rows are its only evidence, and the `resolved` row alone does not prove its canary or swap); **T = the later of the two hosts' `CRON_DRAIN: waited` rows of that deploy (logged just before the host's prod stop; the `resolved` row is written at deploy start, before the canary, the cron drain and the swap, so it is a lower bound, not the swap time) plus 5 minutes**, with the baseline row read as `--since T --until T+400s` (below); post the two anchor lines on #10136; the `flip_verify` handshake line in the workflow run log (`verified=200`, `unverified_rc=60`, `result=pass`) plus the script's `FLIPPED` line is the success evidence; the post-flip re-run of the A2 handshake hook (doppler plus curl, GET recipe below) is optional in-session corroboration only | `gh workflow run inngest-link-flip.yml -f action=off` (idempotent; the workflow's own failure step is best-effort and after a cancelled run, `off` must be dispatched again; the 30-minute lease only bounds new deploys) |
| A4: 48 hour soak | envelope-delegable before A5 (authority: see intro, form (a) a valid recorded Standing Delegation whose Scope names `inngest-link-flip.yml`, with the narrowing to `action=off` carried by the byte-identical envelope line, or form (b) an in-session per-command go); the soak itself needs none and the `action=off` dispatch is the only command. After A5 the new `INNGEST_SIGNING_KEY` would travel over plaintext `:8288` if the link is turned off, so `action=off` after A5 is form (b) only (a fresh in-session go). The A3 go that pre-names this revert is valid only inside the session that received it | A3 timestamp T and the baseline row | the follow-through sweeper runs `inngest-tls-soak-10136.sh` | gap-free `tls-health` series since T, one `boot_id`, `legacy_8288` delta exactly 0, `tls_8443` delta at least 90% of the expected probe cadence, for 48 hours. A reboot restarts the clock: re-anchor with a new pair of comments | any non-zero legacy delta: run `action=off` and find which caller still dials `8288` |
| A5: `INNGEST_SIGNING_KEY` rotation (#10382 row 1), together with `INNGEST_EVENT_KEY` only if the owner extends the go | **owner-human** (credential rotation; no delegation covers it): a fresh in-session go or the owner executing it; a go recorded on #10382 is not a go under form (b) | A4 passed (the new key must never ride plaintext); the rotation follow-up with a minimal `apply_target` has landed; the "Key rotation" section re-read; both copies identified (host: `random_id.inngest_signing_key_dedicated` in `soleur-inngest/prd`; app: `soleur/prd` `INNGEST_SIGNING_KEY`, copied out of band per `inngest.tf`); the Stripe-webhook (#10542) and dashboard-send (#10543) loss defects fixed first, or the rotation runs inside a quiesced window with the replay check | set both values, then restart `inngest-server` (`restart-inngest-server.yml`) and redeploy web (`web-platform-release.yml`) **back to back**. No host replace is forced (keys are read from Doppler at start). During the mismatch window step calls fail signature verification (Inngest retries them) and `inngest.send` fails with 401 if the event key rotates too | old-key rejection (status code only; keep the old value until it passes), new key accepted, `.services.inngest_server` active with a stable `NRestarts` | the "Key rotation" rollback; see the post-A5 rollback note above |
| A6: "no known access" record | **owner-human**: CLO condition; owner-signed (no delegation covers it) | A5 complete; a measured re-read from the deployed #10405 emit; the Hetzner member list enumerated read-only | a record under `knowledge-base/legal/audits/`, linked from #10382 and #10136, written by the owner and attested separately by the CLO agent | the record exists and is linked | n/a (this PR does not write it) |
| A7: leg-2 accepted-risk record (the `sdk_url` poll) | **owner-human**: owner item, class `operator (legal-risk)` (no delegation covers it) | the CLO conditions on the leg-2 row | an owner-typed record on #10136 beginning "SIGNED BY OWNER (human, not an agent)"; an agent-posted record does not satisfy it | the record exists before the poll row is relied on | n/a |

**Abort thresholds for A1** (from "Replace triggers" and the provision unit): **10 minutes** after the apply with `provision-unit-armed`
but no `provision-attempt-start`, or **2 hours** with no `bootstrap-done` for the new `iid`, or `tls-health` absent 30 minutes after the
apply, means the replace failed. Read the apply run's recovery-read block and the latest attempt's stages
([Provision unit](#provision-unit-8562)), then **stop and wait for a fresh owner go**. Do not re-dispatch on your own, and an inherited
`done` is recovered by A1b, never by a second replace.

**What the executing session posts for the soak (A3, after the old containers drain).** Two plain, unfenced lines in one comment on
#10136, authored by the owner's identity (the probe ignores any author without write permission, and anything inside a code fence):

```
S1-SOAK-T: <UTC ISO time, last prod swap plus drain>
S1-SOAK-BASELINE: dt=<UTC ISO> boot_id=<8 chars> legacy_8288_packets=<n> tls_8443_packets=<n>
```

The baseline is the first `tls-health` row at or after T, read with an explicit window so a late post cannot return the wrong rows (the query keeps the *newest* rows): `doppler run -p soleur -c prd_terraform -- bash scripts/betterstack-query.sh --since <T> --until <T+400s> --grep stage=tls-health --limit 3` (ISO-8601 UTC). The soak refuses a baseline more than 400 s after T as a malformed anchor, and `--since <T> --until <T+400s>` is the documented form. The latest pair wins, which is how a reboot is handled.

**Calling the handshake hook (A2)** reads from web-1 only. It is a signed GET with an empty body against the `inngest-tls-handshake`
hook (HMAC-SHA256 of the empty body in `X-Signature-256`, plus the Cloudflare Access pair). The repository's credential-safe form is
`scripts/lib/bearer-curl.sh` (ADR-280: the credentials ride curl's stdin config, never an argument list), the same call
`scripts/inngest-link-flip.sh` makes. Run from the repository root; `-sS` without `-f` prints the body on a failing status too (the
hook returns its line on error as well):

```
export WEBHOOK_DEPLOY_SECRET=$(doppler secrets get WEBHOOK_DEPLOY_SECRET -p soleur -c prd_terraform --plain)
export CF_ACCESS_CLIENT_ID=$(doppler secrets get CF_ACCESS_CLIENT_ID -p soleur -c prd_terraform --plain)
export CF_ACCESS_CLIENT_SECRET=$(doppler secrets get CF_ACCESS_CLIENT_SECRET -p soleur -c prd_terraform --plain)
source scripts/lib/bearer-curl.sh
SIG="$(printf '' | bc_hmac_sha256_hex WEBHOOK_DEPLOY_SECRET)" || SIG=""
bc_curl handshake 'X-Signature-256:sha256=:SIG' 'CF-Access-Client-Id::CF_ACCESS_CLIENT_ID' \
  'CF-Access-Client-Secret::CF_ACCESS_CLIENT_SECRET' -- -sS --max-time 30 \
  "https://deploy.soleur.ai/hooks/inngest-tls-handshake"
```

Expected: `inngest-tls-handshake verified=200 verified_rc=0 unverified=fail unverified_rc=60 result=pass`. Read a failure from the same line:
`verified_rc=60` = the pinned CA was rejected; `28` or `7` = the listener is unreachable; `unverified=ACCEPTED` = the listener accepted a
client that did not trust the CA (the MITM-relevant case: stop). The line holds fixed tokens and numeric exit codes only. The call
shape was exercised against a local stub server that checks the three headers (it printed the expected line); the real hook was not
called, because it answers meaningfully only after the CA is installed: `apps/web-platform/infra/cloud-init.yml:794` (the
`[ -f /mnt/data/inngest-link/inngest-ca.pem ] || install ... /dev/null` line) creates an EMPTY placeholder file, and `ci-deploy.sh`
installs the real CA only in the https arm, after the host-side self-gate passes. A `verified_rc=77` before the flip is expected
(curl exit 77 is a CA file that cannot be read as a certificate; the empty placeholder is the cause on the repository facts, the host's
curl version was not read).

### Replace duration, and what happens to events during it

Measured from the repository's own records on 2026-10-18 (no estimate is used where a measurement exists):

- **Clean path, 2026-09-27** (`apply-web-platform-infra.yml` run 36327637204, `inngest-host-replace`): apply started 14:55:00Z and
  finished 14:57:37Z (about 2.5 minutes); the server was created at 14:56:48Z; Better Stack shows `runcmd-entered` 14:57:36Z and
  `bootstrap-done` 14:58:07Z, so **79 seconds from server creation to `bootstrap-done`**. The host then refused to start the
  scheduler on the inherited `done` (`inngest-server-start-REFUSED` at 14:57:59Z). `cutover-inngest.yml` `op=resume` run 36327875467
  was dispatched at 14:59:05Z, waited for the environment approval, started at 15:29:31Z and finished at 15:29:49Z. Apply start to
  resume done: **34 minutes 49 seconds, of which about 30 were approval latency**. A green apply does not mean the scheduler is
  serving.
- **Incidents:** about 59 minutes on 2026-09-22 (private-NIC race, a second replace, then `op=resume`) and about 76 minutes on
  2026-09-17 (inherited `done`, two replaces). Plan for **15 to 60 minutes plus owner approval latency**; the window can outlast that
  if the owner is away when a failed replace needs a fresh go.
- **Queue state survives.** The Redis AOF volume is retained by omission and the destroy-guard asserts zero deletes. After the
  2026-09-17 76-minute gap each missed cron tick fired **exactly once** on resume (ADR-100, addendum of 2026-09-19): do not re-fire
  missed ticks by hand.
- **Event sends during the window.** `sendInngestWithRetry` makes three attempts with 0.5 s then 1 s backoff, then throws
  (`apps/web-platform/server/inngest/send-with-retry.ts`). What each caller does with the throw (code read 2026-10-18):
  GitHub-push and Resend-inbound webhooks release their dedup row and return 500 so the sender redelivers; `schedule-reminder` returns
  the retryable 503 only for connection refusal today (this PR extends it to timeouts and TLS causes), and otherwise 502, so the
  caller must re-arm; the dashboard send path archives the draft with `degraded=enqueue_failed` and does **not** retry (the approved
  action is lost until re-sent); the Stripe `invoice.payment_failed` route swallows the failure and returns 200, so that finance
  event can be lost permanently. The last two are pre-existing and tracked: the Stripe swallow as #10542 (P1, it **blocks the A1 go**: fix it or run the replace in a quiesced window with the replay check) and the dashboard send as #10543.
- **Window controls:** a low-traffic dispatch; the `cutover-inngest.yml` quiesce op; and a replay check afterwards (rows in
  `action_sends` without a spawn, Stripe dedup rows without a CFO draft). Whether the quiesce flag reaches the container without a
  redeploy is unverified, so use the existing op and do not assume a mechanism.
- **Not measured:** how a step HTTP call in flight when the scheduler goes away is re-driven (presumed at-least-once). Check
  non-idempotent steps before A1.

### Reading `tls-health` without SSH

The Inngest host emits one `tls-health` row every 5 minutes. Read the newest rows (needs the `prd_terraform` read credentials; a bare
shell exits 3, which means nothing was queried):

```
doppler run -p soleur -c prd_terraform -- bash scripts/betterstack-query.sh --since 15m --grep stage=tls-health --limit 3 \
  | jq -R -r 'fromjson? | .raw | fromjson? | select(.stage == "tls-health") | .detail'
```

The expected healthy shape contains `listener=1`. The `raw` column is double-encoded JSON, so decode before matching, and select on the
decoded `stage` field: `--grep` is an unanchored substring match that also returns any row *quoting* the string. For anything longer
than a few hours pass `--limit 1000` or more; the default of 100 silently keeps only the newest ~8 hours at this cadence.

| Field | Meaning and what to do |
|---|---|
| `unit`, `nrestarts` | state and restart count of `soleur-inngest-tls.service`; rising `nrestarts` means the listener is flapping |
| `fetch_rc` | exit code of the key and certificate fetch from Doppler: `0` ok, `91` runtime directory setup, `92` temp directory, `93` key fetch from Doppler, `94` certificate fetch, `95` key does not match the certificate, `96` install failed |
| `bind`, `listener` | `listener=0` means nothing is bound on `:8443`; this also emits the crit marker `SOLEUR_INNGEST_TLS_REFUSED` (reasons `listener_down`, `cert_expiring`), which the existing `monitor_send_failed` alert pages on |
| `served_sha256`, `cert_sha256` | the fingerprint the live handshake returns and the one on disk; they must be equal, and equal to the Terraform certificate (A1 compares them) |
| `notafter_days` | days to expiry; about 3650 after the host replace; under 90 pages |
| `legacy_8288_packets`, `tls_8443_packets` | cumulative nft packet counters **since boot**. Only the **delta from the baseline row** means anything; a non-zero legacy value before the flip is normal |
| `nft8443_sha256`, `nft_rules` | fingerprint of the `8443` lines and a rule count, used as the measured nftables re-read |
| `boot_id` | first 8 characters of the kernel boot id; a change means a reboot, the counters reset and the soak clock restarts |

Dead-emitter detection is the soak probe's gap check (a stretch over 400 seconds without a row) and the monthly certificate
days-left follow-through. Nothing pages on a missing row by ruling.

Two reads the crit marker does not cover: a listener that is bound but not serving shows only in the periodic row (`listener=1` with an
empty `served_sha256`, or `served_sha256` different from `cert_sha256`); and a **missing `cert.pem`** reads as `notafter_days=0` and
`reason=cert_expiring` (the day count is computed from an empty date), so a page with `notafter_days=0` and `fetch_rc` other than `0`
is a certificate that was never installed, not an expiry. The refusal-marker page route (`monitor_send_failed` reading Vector
Source 2 on the Inngest host) is asserted by source-text guards only; no PRIORITY-2 row from that host has been read back, so treat
the first one as the proof and read it after A1 (`JSONExtractString(raw,'PRIORITY') = '2'` for the Inngest host's `host`).

### Reading `selfgate_failed`

One failed host-side gate is one line. Read it with the `INNGEST_LINK: class=` query above, `--grep` narrowed to the class and `--since` wide enough to
cover the failed deploy (the default `--since 1h` silently misses an older deploy; `--since` takes `Nh`, `Nm`, `Nd` or an ISO-Z time):

```
doppler run -p soleur -c prd_terraform -- bash scripts/betterstack-query.sh --since 24h --grep 'class=selfgate_failed' \
  | jq -R -r 'fromjson? | .dt as $t | .raw? | fromjson? | select(.SYSLOG_IDENTIFIER == "ci-deploy") | "\($t) \(.host_name) \(.host) \(.message)"'
```

```
INNGEST_LINK: class=selfgate_failed level=error rc=<n> http=<ddd|none> attempts=<n> phase=<token> tcp=<n> tls=<n> verify=<n>
```

The `dt` and host this prints are the failing row's own: use that `dt` as T for every read below, and read the host before reading that host's other rows.
**An empty result is not a pass and not a reason to re-flip.** The shipper may have lagged or the window may be wrong: widen `--since` once. For a failed **flip** an
empty read means STOP and ask the owner for the shipper check: do not fall back to "read the state key instead", because for a flip the revert normally erases it (next paragraph).
Do not re-flip on the run-log reason alone.

**Where the stage is printed.** `phase` is carried in three places, and only the first has the other fields. (1) This Better Stack event: `rc`, `http`, `attempts`,
`phase`, `tcp`, `tls`, `verify`. (2) The deploy state key `inngest_link_selfgate_phase` (one of the seven tokens below, written by `write_state` through a closed-enum
check, so an out-of-enum value reads `invalid`; the key is ABSENT unless the https self-gate failed). The key is the LAST deploy's state and is visible in two places only:
(a) the release run's log, where `web-platform-release.yml` prints the whole state body (`jq .`) when ci-deploy.sh exits non-zero, and (b) `/hooks/deploy-status` while no other
deploy has run on that host. Any later deploy rewrites the state (`write_state ... running` at its start) and erases the key. Read (b) with the HMAC call in
`plugins/soleur/skills/postmerge/references/deploy-status-debugging.md`, section "Call Pattern" (no SSH). **web-2:** web-1 answers that hook, and when web-1's last deploy fanned out
its whole status, including this key, sits under `.peers["<web-2 private ip>"]` of web-1's body (`peers_json()` in `cat-deploy-state.sh`); the release run prints a failing peer's
body too. The key appears there only once web-2 itself runs the new `ci-deploy.sh`. (3) NOT the flip run log: `inngest-link-flip.yml` polls through
`.github/actions/dispatch-web-redeploy/track.sh`, which prints only `reason=` and `exit_code=`, so a failed flip run shows the constant reason without the stage.
**For a failed flip the Better Stack event row is therefore the ONLY record.** The workflow's `Revert to http (best effort)` step redeploys the fleet and every host rewrites its
state: on 2026-10-23 the failure row was at 15:24:42Z and the revert rows at 15:26:10Z (web-1) and 15:26:44Z (web-2), so about two minutes later both hosts had begun a new deploy, which erases the key (the revert is best-effort and can end `REVERT-INCOMPLETE` or be cancelled, so a given run may leave the key: read Better Stack first), and in that run
nothing had printed it (evidence file, "Better Stack rows read on 2026-10-23").

Every field is a fixed token or an integer; the event never carries a URL, an address, certificate text or curl's own error message. The gate makes
`attempts` tries of one curl each (three by default) and passes only on curl exit code 0 with HTTP 200 against the pinned file; nothing here changes that.

| Field | Meaning | Reading rule |
|---|---|---|
| `rc` | curl's exit code on the LAST attempt | The same wire event can print a different `rc` on a different curl build (52 on curl 8.5.0, 56 on 7.81 and 8.23), so decide the stage from `phase`, not from `rc`. `rc` is needed only to tell 7 (refused) from 28 (a drop) when `tcp=0`, and for the `unknown` decode below. |
| `http` | the HTTP code of the LAST attempt, only when it was a three-digit number, else `none` | `000` means curl got no HTTP status. `http=200` with `phase=request` is a 200 header whose body was cut short: not healthy. It is not rc 18 only: rc 18 was measured on curl 8.5.0, rc 56 (a close without `close_notify`) and rc 28 (the body stalled until `--max-time`) on curl 8.23.0, and all three print the same line. |
| `attempts` | how many attempts ran | The denominator for `tcp` and `tls`. |
| `phase` | the stage the LAST attempt reached, one of seven tokens below | Describes the last attempt only. |
| `tcp` | how many of ALL attempts connected TCP, 0 to 99 | Compare it with `attempts`; an attempt whose timer field could not be read adds nothing. |
| `tls` | how many of ALL attempts printed a non-zero TLS handshake time, 0 to 99 | Compare it with `attempts` and `tcp`. Every measured rc 60 and rc 77 row printed `time_appconnect` 0.000000 (the curl 8.5.0 table in the evidence file, and the rc 60 rows measured on 8.23), so `verify` and `ca_file` lines read `tls=0` as well: `phase` and `rc` separate them from `handshake`. |
| `verify` | 0 unless `phase=verify`; then curl's certificate verification result of the last attempt, clamped to 99 | See the `verify` reading rule below. |

| `phase` | The last attempt | Typical `rc` | First read with no SSH (below) | Retry |
|---|---|---|---|---|
| `connect` | no TCP connection: the listener refused, a firewall dropped the packets, or nothing answers | 7 (refused), 28 (a drop; `tcp=0`) | the Inngest host's `tls-health` rows for the window: `listener`, `nrestarts`, `bind` | Transient only if `nrestarts` rose in the window; read `tls-health` first. A deterministic cause fails the same way on a re-flip, and a re-flip needs the owner's per-command go (A3). |
| `handshake` | TCP connected and no TLS handshake time was printed (a terminator crash loop, plaintext on the TLS port, a stalled handshake; the rcs measured are 35 and 28). The classifier also files rc 58, 83 and 51 with a non-zero connect time here, not under `ca_file`: those were not measured, so `handshake` with an rc outside 35 and 28 is not evidence of a terminator fault | 35, 28 | the same rows: `unit`, `nrestarts`, `listener` | As `connect`. |
| `verify` | TLS was rejected at certificate verification: the served certificate does not verify against the candidate CA file (curl printed no handshake time, so `tls=0`, measured on every rc 60 row) | 60 | the `verify=` value, then the `verify` reading rule below: the `tls-health` fingerprints are both Inngest-host values and cannot show the pinned side | Deterministic until the served certificate or the CA value Doppler holds changes; a re-flip repeats it. STOP: do not re-mint, re-publish or re-flip on this line alone. |
| `ca_file` | curl could not use the candidate CA file it was handed | 77 | nothing earlier in the same deploy: `class=ca_invalid` and `class=write_failed file=ca_candidate` return before the gate runs, so a `ca_file` event means they did not fire and the validator already accepted the bytes (`write_failed file=ca` and `file=link_env` come AFTER the gate and say nothing about it). The CA value in Doppler `soleur/prd` is an owner read, not a no-SSH read; this is not a listener problem | Deterministic until the CA file is right; do not re-flip before the cause is read. |
| `request` | TLS completed and verified, no HTTP response came back | 56, 52, 28, 1, 18 | the same `tls-health` rows (`unit`, `nrestarts`, `listener`), which describe the terminator only: no field shows its upstream on `127.0.0.1:8288`. The read-only `/hooks/inngest-tls-handshake` call (see "Calling the handshake hook (A2)" above) repeats the gate's own request against the INSTALLED CA file, so it adds nothing while the gate is failing, and after a failed gate it returns `verified_rc=77` only while the installed CA file is still the empty placeholder (a host that has never completed an https deploy; a host holding an older valid CA answers against that file): that is not a verdict on this event | Do not re-flip on `phase=request` alone: unchanged `tls-health` is not a reason to expect a different result, and no cause is readable. Every flip attempt needs the owner's in-session per-command go (A3). A failed gate aborts that host's deploy before any container swap; the workflow's revert step then flag-absent applies and redeploys the fleet (the A3 row counts that as one swap per host). |
| `status` | TLS verified and an HTTP status other than 200 came back | 0, 18 | the `http=` value | Depends on what answers behind the terminator; read the status first. |
| `unknown` | the attempt's output could not be read (see the `unknown` decode) | 124, 2, 0 | none: the line carries no stage | Read the `unknown` decode before retrying. |

**`phase=request` means: TLS verified, no HTTP response: check the terminator and its upstream, not the certificate. No cause is readable today:
the terminator's own journald is not shipped to Better Stack.** `soleur-inngest-tls.service` runs stunnel in the foreground with `syslog = no` and sets no priority, so its
output takes systemd's default priority 6, and `vector.toml` Source 1 admits only `inngest-server.service` or priority 3-4 from other units (no `vector.toml` entry names the
terminator). No issue tracks shipping it: #10880 is a different `vector.toml` item, a carrier-drift CI guard. The event does not say whether the terminator, its upstream on `127.0.0.1:8288` or the app failed.
**Exit from the stop rule (the owner's decision, not made here).** Shipping the terminator's journald is a small `vector.toml` change by reading: add the unit to Source 1 `include_units`
and to Source 2 `exclude_units` (excludes win, so the two lists move together), and update `apps/web-platform/test/infra/vector-admission.test.sh`, which pins both lists (rows S1 and S2). A `vector.toml`
change reaches the Inngest host only through the bootstrap image (`IREF` digest in `cloud-init-inngest.yml`, which feeds `user_data`), and `hcloud_server.inngest` has no `ignore_changes` on
`user_data` (`inngest-host.tf`), so the digest bump forces a host replace; it also touches the `vector.toml` carrier pin that #10880 guards. No issue tracks it. The owner chooses between shipping it before a
third flip and a one-off SSH read of the terminator's journal under `hr-ssh-diagnosis-verify-firewall`.
A real stunnel whose upstream refused printed exactly `rc=56 http=000` with TLS completed (curl 8.5.0, one measurement): a match for the shape of the
2026-10-23 event, not a cause for it.

**First read with no SSH.** The Inngest host phones its `tls-health` row home every 5 minutes, independent of the journald shipper
(see "Reading `tls-health` without SSH" above for the fields). T is the `dt` the `selfgate_failed` query above printed for the failing row (not the time the run
was dispatched or read). Widen it by 15 minutes each way and read; the line prints each row's `dt` and host so the rows can be placed against the gate's second:

```
doppler run -p soleur -c prd_terraform -- bash scripts/betterstack-query.sh --since <T-15m, ISO-Z> --until <T+15m, ISO-Z> --grep stage=tls-health --limit 10 \
  | jq -R -r 'fromjson? | .dt as $t | .raw | fromjson? | select(.stage == "tls-health") | "\($t) \(.host) \(.detail)"'
```

`listener=1` with `nrestarts` unchanged across the window says the terminator was up and stable at the 5-minute samples; it does not say it was up at the
gate's second, and it says nothing about its upstream. An empty result is not a pass: confirm the query returned rows for the Inngest host first.

**The `verify` reading rule.** `verify=` is meaningful only with `phase=verify`, because curl prints 1 for several unrelated failures; the line suppresses it elsewhere.
`18`: the served certificate is a different self-signed certificate than the pinned file (the pinned file is a self-signed leaf by design, so a re-mint without a re-publish reads 18). `10`: the served certificate
expired. `1`: a name mismatch (no matching IP in the served certificate); on curl 8.23 a different certificate WITHOUT the matching IP also reads 1, because the
name check is reported first (measured), so 1 does not exclude a re-mint. `19`, `20`, `21` and any other value are unexpected: the served chain is not the designed single self-signed
certificate (a leaf issued by a CA that is not pinned read 20 on curl 8.23, measured); do not guess.

**What the `tls-health` rows can and cannot show for `verify`.** `served_sha256` (the live handshake) and `cert_sha256` (the file on disk) are both measured on the
Inngest host, from the certificate in `soleur-inngest/prd`. The gate's candidate CA is the `INNGEST_TLS_CA` value in `soleur/prd` that this deploy read (from the
deploy snapshot, else from Doppler) and decoded; the Terraform `doppler_secret.inngest_tls_ca` writes it as the base64 of the same certificate. Equal `served_sha256`
and `cert_sha256` therefore say only that the Inngest host is self-consistent, and they stay equal after a re-mint whose new certificate was never re-published to the
Doppler value the web hosts read: that is exactly the `verify=18` case. No event carries the fingerprint of the candidate or of the pinned file the web hosts have
installed (the A1 row says the same: no emitter reports a CA fingerprint). Only an owner read of the Doppler `INNGEST_TLS_CA` fingerprint against the Terraform
certificate's reads the pinned side, and this section's no-SSH reads do not include it. **STOP rule: `phase=verify` alone licenses neither a re-mint, nor a
re-publish, nor a re-flip.** Read the pinned side first; a re-flip needs the A3 per-command go.

**The flapping rule.** `phase` is the last attempt; `tcp` and `tls` cover all of them. When `tcp` or `tls` is neither 0 nor `attempts`, or when `phase` contradicts the counts
(for example `phase=connect` with `tcp` at least 1, or `phase=handshake` with `tls` at least 1), the attempts did not all behave alike: read the line as an unstable listener, not as the last token alone.
A count below `attempts` is not proof of a restart: an attempt that hung (`rc=124`) or printed nothing adds to neither counter, so it lowers both without any listener change. Confirm a restart from the Inngest host's `nrestarts` in `tls-health`, never from the counts alone.

Three worked lines (each is the line the suite's flapping fixture prints, row S4; the attempt sequence in brackets is that fixture's):

- `rc=56 http=000 attempts=3 phase=request tcp=2 tls=2 verify=0` (reset after the request, refused, reset after the request): the first and the last attempts completed TLS and got no HTTP response, the middle one was refused.
- `rc=7 http=000 attempts=3 phase=connect tcp=1 tls=1 verify=0` (reset after the request, refused, refused): the last attempt was refused, as was the one before it; only the first connected, and it completed TLS but got no HTTP response, so it was not a good attempt.
- `rc=35 http=000 attempts=3 phase=handshake tcp=2 tls=1 verify=0` (refused, reset after the request, closed during the handshake): the first was refused, the second completed TLS and got no HTTP response, and the last connected TCP and was closed before the TLS handshake finished.

A steady line has `tcp` and `tls` both equal to `attempts` (`request`, `status`), `tcp=attempts tls=0` (`handshake`, and also `verify` and `ca_file`, which print no handshake time: `phase` and `rc` tell them apart) or both 0 (`connect`).

**The `unknown` decode.** `unknown` is never a stage and `tcp=0 tls=0` beside it does NOT mean connect failed: an attempt whose output was unreadable counts nothing.
`rc=124`: the `timeout 20` wrapper killed curl, so curl printed nothing (a hang; this wins over any good timers). `rc=2`: curl 8.23 with a MISSING CA file prints a usage
error and no output (measured; curl 7.81 and 8.5.0 print `rc=77` for a missing file, read as `ca_file`, and an EMPTY or garbage file prints 77 on every build measured, so rc 2 does not point at an empty placeholder). `rc=0` with `phase=unknown`: the write-out line was not in the expected four-field shape,
which means the curl output format changed; file it, do not retry.

**Proof limits.** The profiles were measured against local servers on curl 7.81, 8.5.0 and 8.23, but not every row on every build (evidence: `knowledge-base/project/specs/archive/20261024-023954-feat-one-shot-inngest-selfgate-phase/curl-w-measurements.md`,
whose last column says which): the real stunnel rows, the truncated body (rc 18) and the firewall drop are 8.5.0 or unrun elsewhere; the host's own curl was not read. The suite compares the double with real curl for six cases (closed port, accept and close, a pinned-certificate mismatch,
TLS then a clean close, 200, 502); the resolver suite's real-curl rows ran 6 of 6 against curl 8.5.0 (the Ubuntu 24.04 userland) in a container on 2026-10-23, including the pinned-certificate mismatch and the check that the phase the real function emits equals the stub's, at commits `4500ff682c` (274 passed) and `c2ac316a14` (281 passed); an earlier 252-passed run predates the fix commits and is not proof of the shipped code; the same rows also ran on the dev host's 8.23. The hang phases (5 s and 10 s timers), a TCP reset, an empty CA file and a truncated body are stub-only in the suite (measured once in the evidence file, not compared against real curl) and rc 58, 83 and 51 were never measured.

### Certificate expiry and rotation

The certificate is valid for 10 years with no rotation cron; the warning is `notafter_days < 90`. **Re-minting forces two things**:
the web hosts must pick up the new CA (the CA file comes from `INNGEST_TLS_CA` at deploy time, and `NODE_EXTRA_CA_CERTS` is read once
at process start, so a CA change needs a new container, not a reload), and the Inngest host must be replaced (the key and
certificate are fetched at the unit's start from a template that is replace-only). The CA file holds **exactly one certificate**
(the validator refuses a bundle, because every certificate in `NODE_EXTRA_CA_CERTS` is trusted for all outbound TLS), so there is
**no overlap window**: an https fleet fails closed between the host replace and the web side picking up the new CA. The order that
never lets the fleet dial a mismatched pair:

1. `inngest-link-flip.yml -f action=off` (the fleet is back on `http://10.0.1.40:8288`, which stays open through the whole sequence).
2. Publish the new certificate (the three Doppler copies change together, because they come from one Terraform resource). Both
   resources carry `prevent_destroy`, so a re-mint is a reviewed code change that lifts the guard for one apply, not a dispatch; no
   apply route exists for it (#10540 covers the signing and event keys only).
3. Replace the Inngest host (act A1, under its own authority: an in-session per-command go, never a valid recorded Standing Delegation; already done 2026-10-20). It now serves the new certificate.
4. `inngest-link-flip.yml -f action=flip`. A separate "redeploy web" step is not needed and would not help: a deploy with the flag
   **off** never reads or installs the CA, so only the flip's own `pending` redeploy installs the new one, and it does so only after the
   host-side self-gate has proven the new bytes against the new listener (a mismatch fails the deploy and leaves the old file).

Do not use `early_renewal_hours`: it would plan a replace that `prevent_destroy` blocks and fail every later merge apply once inside the
window.

### Key rotation order (A5)

1. Do not start until the soak (A4) has passed: the new key must never travel over `:8288` in plaintext.
2. Rotate the host copy (`soleur-inngest/prd`) and the app copy (`soleur/prd` `INNGEST_SIGNING_KEY`) to the same new value in one
   window; the event key rotates in the same window only if the owner extended the go.
3. Restart `inngest-server` (`restart-inngest-server.yml`) and redeploy web (`web-platform-release.yml`) back to back. During the
   mismatch window step calls fail signature verification and Inngest retries them; `inngest.send` fails with 401 if the event key
   changed on one side only.
4. Check the old key is rejected (status code only), the new key is accepted, and `.services.inngest_server` is active with a stable
   `NRestarts` ([Reading host state without SSH](#reading-host-state-without-ssh)).
5. Then the A6 record. The rotation apply route is a separate follow-up (#10540) and A5 waits for it; until it lands the existing
   [Key rotation](#key-rotation) procedure applies. No command for the "old key is rejected" check exists yet either, so A5 is not
   dispatchable by an agent today; keep it blocked in its follow-through issue until #10540 lands.

### Tracked follow-ups (filed 2026-10-19)

| Issue | What it tracks |
|---|---|
| #10538 | the `sdk_url` poll (leg 2): a web-side listener or poll removal, merge by 2026-11-12, accepted-risk row lapses 2026-12-10 |
| #10539 | bind `:8288` to loopback and drop the legacy accept at the next unrelated replace (also restricts the Connect ports) |
| #10540 | the signing-key and event-key rotation apply route (blocks A5) |
| #10541 | keep `INNGEST_TLS_KEY` out of the `inngest-server` process environment (`--only-secrets` or a split config) |
| #10542 | Stripe `invoice.payment_failed` swallows an Inngest send failure (P1, blocks the A1 go) |
| #10543 | the dashboard send archives the draft on a failed enqueue |
| #10544 | `inngest-host-replace` has no confirm or id-pin input |
| #10545 | the Inngest host's nft loader is not idempotent |
| #10556 | a Sentry alert rule for `op=inngest-link` events (`https_to_http`, `scope_unverified`, `canary_failed`, `selfgate_failed`) |
| #10557 | no no-SSH repair path for a non-empty or root-owned `/mnt/data/inngest-link` on a web host |

The `https_to_http`, `lease_expired` and `canary_failed` events notify nobody today (#10556), and a wedged `/mnt/data/inngest-link` has no
no-SSH repair (#10557).

## Key rotation

Both `INNGEST_SIGNING_KEY` and `INNGEST_EVENT_KEY` are TF-generated via `random_id` resources.

> **Secret delivery (#5560).** inngest-server reads `INNGEST_POSTGRES_URI`, `INNGEST_REDIS_URI`, `INNGEST_SIGNING_KEY`, and `INNGEST_EVENT_KEY` from the doppler-run **environment** (owner-only `/proc/<pid>/environ`), never the `inngest start` argv (world-readable `/proc/<pid>/cmdline`). A rotated value loads on the next inngest-server restart/redeploy **without** being re-exposed on argv. **Ordering matters:** when rotating because a value leaked, deploy the env-delivery build FIRST (verify `ps -eo args | grep inngest` shows no secret), THEN rotate — rotating while an old argv-form image is still running would re-leak the new value immediately. After rotation, NEVER roll back to a pre-#5560 (argv-form) image.

<!-- lint-infra-ignore start -->

**⚠ The ONLY supported rotation path is the `terraform taint` flow below.** Do NOT rotate via the Doppler UI — every `doppler_secret` carries `lifecycle.ignore_changes = [value]`, so out-of-band Doppler-side changes are INVISIBLE to subsequent `terraform plan` runs. The provider skips the value read-back when `ignore_changes` is set; you'd get silent dashboard ↔ tfstate divergence. If you've accidentally rotated via the UI, run `terraform apply -replace=doppler_secret.<key>` to force TF to re-converge.

> **#8209 / ADR-241 — the single-loader form in this runbook is the PRE-cutover one.** After the
> Tier-B cutover the same command is wrapped by an outer `soleur-infra-privileged` loader, and the
> inner `prd_terraform` loader carries `--preserve-env` so the outer values win. Canonical form and
> rationale: [`infra-credential-tiers-8209.md`](./infra-credential-tiers-8209.md) §Local Terraform
> invocation. This note covers every occurrence in this file.

1. Identify which key to rotate. Replace `<KEY>` with `inngest_signing_key_prd` (or `_dev`, or `inngest_event_key_{prd,dev}`).
2. Taint the random_id so the next apply regenerates it:

   ```
   doppler run -p soleur -c prd_terraform --name-transformer tf-var -- terraform -chdir=apps/web-platform/infra taint random_id.<KEY>
   ```

3. Apply:

   ```
   doppler run -p soleur -c prd_terraform --name-transformer tf-var -- terraform -chdir=apps/web-platform/infra apply
   ```

   The companion `doppler_secret.<KEY>` ignores `value` changes via lifecycle; force a refresh:

   ```
   doppler run -p soleur -c prd_terraform --name-transformer tf-var -- terraform -chdir=apps/web-platform/infra apply -replace=doppler_secret.<KEY>
   ```

4. Restart the application + inngest-server so they pick up the new value — **two existing
   no-SSH verbs, no host login:**
   - web-platform: re-run `web-platform-release.yml`. The container is swapped, which IS the
     restart (`ci-deploy.sh` rejects `restart web-platform` by design — "web-platform restart is
     docker-level").
   - inngest-server: dispatch `restart-inngest-server.yml`, which sends the `restart inngest`
     verb (`ci-deploy.sh:2354`).

   Confirm with [§ Reading host state without SSH](#reading-host-state-without-ssh): `.reason`
   should read `success`, and `.services.inngest_server` should be `active` with
   `.services.inngest_redis_result` showing a **stable** `NRestarts` across two reads.

<!-- lint-infra-ignore end -->

## CLI version bump

Inngest CLI version is pinned in `apps/web-platform/infra/inngest.tf` `locals` block. Bump procedure:

1. Find the new version + SHA256 at `https://github.com/inngest/inngest/releases`. The linux_amd64 SHA256 lives in the release's `checksums.txt` file.
2. Edit `inngest.tf`:

   ```
   inngest_cli_version = "vX.Y.Z"
   inngest_cli_sha256  = "<64-hex>"
   ```

3. Release the new bootstrap-image semver (N.N.N — separate from the embedded
   inngest-cli version) via the canonical flow below
   ([§ Bootstrap-image release](#bootstrap-image-release-tag--build--deploy--verify)):
   annotated tag → build → cloud-init pin bump → `workflow_dispatch` deploy →
   verify. The dedicated host's live flip is `inngest-host-replace` (destroy +
   recreate); `inngest-bootstrap.sh`'s in-place upgrade block never runs there —
   see `apps/web-platform/infra/inngest-cli.provenance.md` § Bump procedure, step 7. Only
   an in-place redeploy of an already-running server enters that block: it waits a
   `DRAIN_SLEEP_SEC` settle delay, replaces the binary and restarts the unit.
   Nothing pauses, drains or resumes (no such CLI verb exists, #9219); in-flight
   step dispatches are interrupted at the restart. The success-path `upgrade …`
   log lines stay on the host, so confirm an upgrade through the release verify
   step, not by searching Better Stack.

## Bootstrap-image release (tag → build → deploy → verify)

Releasing a new `soleur-inngest-bootstrap` image (changed `inngest-bootstrap.sh`,
`inngest-redis.*`, or bumped `inngest_cli_version`) is a **4-step coordinated
flow — the image build does NOT auto-deploy**. None of these steps use SSH
(`hr-no-ssh-fallback-in-runbooks`). Full context + gotchas:
`knowledge-base/project/learnings/workflow-patterns/2026-06-18-inngest-bootstrap-release-tag-then-dispatch-deploy.md`.

> **Refresh-channel cross-ref (#6780, ADR-135).** For the five dedicated-host
> carriers in `apps/web-platform/infra/inngest-config-refresh-set.txt`
> (`inngest-redis-bootstrap.sh`, `inngest-cutover-flip.sh`,
> `inngest-server-flip-guard.sh`, `cat-inngest-cutover-state.sh`,
> `inngest-luks-cutover.sh`), an image bake + host replace is no longer the only
> delivery path: once the signed config-refresh channel is live (host rebuilt
> with this cloud-init + a promoted `INNGEST_CONFIG_DIGEST`), bundle promotion
> delivers them in place — see
> [inngest-config-refresh.md](inngest-config-refresh.md). Anything ELSE that
> rides the image (bootstrap.sh, vector.toml, the cli pin) still needs this
> 4-step flow.

1. **The tag is minted automatically (#4326, ADR-232 §8).** When a push to `main` changes an
   image input (a `cp`-staged carrier, one of the four baked pins in `inngest.tf` /
   `vector.tf`, or the Dockerfile heredoc), `mint-inngest-bootstrap-tag.yml` cuts the next
   `vinngest-vX.Y.Z` on **`main`'s tip at the moment the run starts** (which carries that
   change and may carry later ones; it is not necessarily the commit that made the change) as
   `github-actions[bot]` (one patch above EVERY existing `vinngest-v*` tag) and dispatches
   `build-inngest-bootstrap-image.yml` from `main`. That run
   builds, SHA-verifies and pushes the image. It does NOT deploy. There is nothing to do in
   this step unless the mint run failed: read its stage-named `::error::` and
   `result=`/`reason=` lines and use the recovery table below. To see what the mint would
   decide, run `git fetch --tags origin && bash .github/scripts/mint-inngest-bootstrap-tag.sh --dry-run`.

   **Manual fallback, in this order.** First re-run the decision. It is idempotent: it mints
   only when the inputs still differ from the newest merged tag, and it builds once:

   ```
   gh workflow run mint-inngest-bootstrap-tag.yml --ref main
   ```

   Hand-tag only after `reason=workflows-permission` (residual R1), and only when no
   `vinngest-v*` tag already carries the change. The mint tags `main`'s tip, so a tag on the
   change's merge commit OR on any later `main` commit already carries it, and a second tag
   means a second build. Check that this prints nothing:

   ```
   git fetch --tags origin main
   git tag --contains <merge-sha> --list 'vinngest-v*'
   ```

   **Hand-tag:** push an ANNOTATED `vinngest-vX.Y.Z` tag, one patch above every existing
   `vinngest-v*` tag, on `origin/main`'s current tip, after the PR that changes the
   carrier has merged (the repo forces annotated tags — a
   bare `git tag <name> <sha>` fails `fatal: no tag message?`):

   ```
   git fetch origin main
   git tag -a vinngest-v1.1.16 origin/main -m "inngest-bootstrap v1.1.16: <what>"
   git push origin vinngest-v1.1.16
   ```

   A hand-pushed tag starts nothing: `build-inngest-bootstrap-image.yml` has no `push: tags`
   trigger (removed by #9262, ADR-232 A5), so every build is dispatched from `main`. Confirm no
   build run exists for the tag (below), then dispatch it once:
   `gh workflow run build-inngest-bootstrap-image.yml --ref main -f ref=<tag>` (ADR-232 §8, R1).
   That run builds, SHA-verifies and pushes the image. It does NOT deploy.

   **Confirming no build run exists for a tag** (required before ANY manual dispatch — a
   second build of one tag moves its digest). Build runs are titled
   `Build inngest-bootstrap <tag>`:

   ```
   gh run list --workflow build-inngest-bootstrap-image.yml --limit 100 \
     --json displayTitle,status,conclusion,url \
     --jq '.[] | select(.displayTitle == "Build inngest-bootstrap <tag>")'
   ```

   Empty output means no run. Any row (queued, running or finished) means do NOT dispatch.

   **A tag on a PR-branch commit is refused (#8747, ADR-232 §7).** The build job refuses
   before building (`::error::ancestry: vinngest-vX.Y.Z is on commit <sha>, which is not an
   ancestor of main`) and posts to Slack. A branch forked before the fix carries no
   build-side check; its bump then dies at stage `args` (no `--signed-commit`). Every other
   bump run ignores the off-main tag: only tags merged into `main` are candidates
   (#8782). Recover by deleting
   the tag, waiting for the PR to merge, and tagging its squash-merge commit as a **new**
   version — never re-use the name, because GHCR may still hold the off-main image under it:

   ```
   git push origin :refs/tags/vinngest-v1.1.16
   git tag -d vinngest-v1.1.16
   git fetch origin main
   git tag -a vinngest-v1.1.17 <squash-merge-sha> -m "inngest-bootstrap v1.1.17: <what>"
   git push origin vinngest-v1.1.17
   ```

   That push starts nothing (no `push: tags` trigger since #9262). Confirm no build run exists
   for the new tag (above), then dispatch the build once from `main`:
   `gh workflow run build-inngest-bootstrap-image.yml --ref main -f ref=vinngest-v1.1.17`. Do not
   re-run the failed run. The deletion is
   **required**, not hygiene: AC6 of `cloud-init-inngest-bootstrap.test.sh` and the bump
   take the semver-max over tags merged into `main` (ADR-232 §7), so while the tag is off
   `main` it reds only the PR carrying its commit (and branches built on it) — but the
   moment that commit reaches `main` through a merge-commit or rebase merge, the tag
   becomes the merged max with no image behind it: AC6 reds `main`, and every bump for an
   older tag defers (`result=skipped`) without ever self-healing. Recover from that state
   the same way — delete the tag and cut a new, higher version on `main`.

   **Exception: never delete the tag `main` pins today** — e.g. `v1.1.39`, off `main`, right
   after #8747 merged. Deleting it breaks the live pin. Cut a new, higher version on `main`
   instead. While `main` pins a tag that sits above every tag merged into `main` (off `main`
   or deleted), the bump refuses at stage `resolve` with "Refusing to author a downgrade …
   Do NOT delete or re-cut the pinned tag"; that refusal is the signal.

   A `mirror_only` backfill of a legacy off-main tag still mirrors (the build-side check is
   skipped on that path); its bump reconciles the pin to the merged max and ends
   `result=noop` when all of these hold: the merged max is the pinned tag, GHCR resolves it
   to the pinned digest, and its image's revision label names that tag's commit. A registry
   failure on that path ends `result=error` (the bump defers only for a NEWER target whose
   own publish may still be running).

   **Carrier-changing PR flow.** Merge the PR that changes a baked carrier first. Its
   `deploy-script-tests` GuardA row is red on the PR, which is expected and advisory (the
   PR-side exemption is #9081). The merge itself mints the tag and dispatches the build
   (above); tag by hand only per the fallback. The publish passes the ancestry check, and the
   automated bump PR (step 2) auto-merges when the zot mirror is healthy. `main`'s GuardA is
   red from the merge until that bump lands, which is now one mint + build + bump cycle.
   A candidate image can no longer be built from an unmerged PR (#8781).

   **Auto-mint recovery table** (`mint-inngest-bootstrap-tag.yml`; every row is a
   `gh` command or a code fix, never SSH):

   | Signal | Action |
   |---|---|
   | `::error::args:` (`usage`, `credential-isolation`, `missing-credential`, `missing-tool`, `bad-repo-dir`, `bad-repo`, `xtrace`) | Nothing was published. The workflow step drifted from the script's contract (a token bound to the wrong step, a missing env, a traced run). Fix `.github/workflows/mint-inngest-bootstrap-tag.yml` against the script header's CREDENTIALS/MODES block, then re-run the mint. |
   | `::error::ancestry:` | The mint's checkout lost history (shallow, or an unreadable object). Re-run the mint; the workflow checks out `fetch-depth: 0`. |
   | `::error::resolve:` (`no-head`, `base-unresolvable`) | Nothing was published. The checkout could not resolve `HEAD` or the newest merged tag to a commit (tags not fetched, or a tag ref naming a missing object). Re-run the mint (`fetch-tags: true`); if it repeats, inspect the tag with `git ls-remote --tags origin 'refs/tags/vinngest-v*'`. |
   | `::error::decide:` (`no-carriers`, `copy-count-unreadable`, `copy-unparsed`, `cardinality-count`, `cardinality-names`, `recipe-blocks`, `pin-empty`, `comparator-selftest`) | The mint's extractor drifted from the build workflow (a refactor of the `cp`/`COPY` lines, the heredoc or the pin files); the error prints the staged and baked name sets. Fix `.github/scripts/mint-inngest-bootstrap-tag.sh` so it reads the new shape; its parity rows name the authority to follow. Then re-run the mint. |
   | `::error::allocate:` `reason=ls-remote-failed` | The origin was unreachable. Nothing was published. Re-run the mint. |
   | `::error::allocate:` `reason=oversized-version` or `reason=leading-zero-version` | A remote tag carries a malformed version (a component longer than 6 digits, or zero-padded). Delete THAT tag per ADR-232 §7 (never the tag `main` pins), then re-run the mint. |
   | `::error::allocate:` `reason=no-remote-tags`, `next-exists`, `not-last` or `bad-next` | Do NOT delete anything. `no-remote-tags` means the listing came back empty: check `git ls-remote --tags origin 'refs/tags/vinngest-v*'` and re-run. The others mean a concurrent tag landed or the allocator is wrong: re-run once; if it repeats, fix the script. |
   | `::error::tag:` with NO `tag_state=unknown` (`workflows-permission`, `bad-response`, an `http-*` from the tag-object POST, `ls-remote-failed` at the re-read) | The failure came before the ref POST: nothing was published (a tag object alone is orphaned and harmless). For `workflows-permission` (R1), hand-tag per the fallback above. Otherwise re-run the mint; it re-decides from a fresh read of the remote tags. |
   | `::error::tag:` WITH `tag_state=unknown` (`verify-failed`, `ls-remote-failed` at verify, an `http-*` from the ref POST), or a ref POST / verify hang killed at the step timeout (no `::error::` line; the name was recorded before the POST); Slack says the tag MAY exist | The ref POST was attempted, so the tag may exist even though the step failed. Check `git ls-remote --tags origin refs/tags/<tag> 'refs/tags/<tag>^{}'`. **Absent:** re-run the mint. **Present and peeling to the commit the run logged:** confirm no build run exists for it (above), then dispatch exactly once: `gh workflow run build-inngest-bootstrap-image.yml --ref main -f ref=<tag>`. **Present but peeling elsewhere:** do not dispatch; delete it per ADR-232 §7 only when no build run exists for it, then re-run the mint. Never reuse the name. |
   | `::error::dispatch:` | The tag exists and is the merged max. Confirm no build run exists for it (above), then run the line the step printed, exactly once: `gh workflow run build-inngest-bootstrap-image.yml --ref main -f ref=<tag>`. Never delete or reuse the tag. `reason=ls-remote-failed` means the origin was unreachable, not that the tag is missing. |
   | `::error::mint-infra-app-token: …` (the App-token step of the mint job or of a build's `bump-cloud-init-pin` job), or `::error::DOPPLER_TOKEN_INFRA_APP is not available` | Nothing was tagged or pushed: both jobs mint before the tag and before the push. A permission refusal (`GitHub said: …`) or a grant mismatch (`differ from the requested`, `not limited to the requested repositories`) means the live `soleur-infra` App lacks the committed manifest's scopes: do step O4c of `knowledge-base/engineering/operations/runbooks/infra-credential-tiers-8209.md`. `DOPPLER_TOKEN_INFRA_APP is not available`, or a Doppler read failure (`not readable from Doppler soleur-infra-app/prd`), means the narrow read token or its copied App values are missing or stale: the cause-to-stage table in §Release-job App source of the same runbook names the bootstrap stage to re-run. A transport failure (`did not complete (curl rc=…)`) needs no fix. Then, for the mint: `gh workflow run mint-inngest-bootstrap-tag.yml --ref main`. For a bump job: `gh run rerun <run-id> --failed` (reruns only the failed bump job: no rebuild, the digest does not move). |
   | The build or the bump failed after a successful dispatch | If the bump job failed and the build job succeeded: `gh run rerun <run-id> --failed` (reruns only the bump job; no rebuild, the digest does not move). If the build job itself failed, re-run that build run (it posts its own Slack). |
   | R12: a bump PR held with signed ≠ target after two auto-mints in flight | `gh workflow run build-inngest-bootstrap-image.yml --ref main -f ref=<max-tag> -f mirror_only=true` (digest-preserving). Since #9262 a `mirror_only` run never arms auto-merge, and disarms one an earlier run armed. On the existing PR it refreshes the branch, disables auto-merge if it was armed (`gh pr merge <n> --disable-auto`; the run dies at stage `pr` if that fails), and posts a hold comment; the PR body keeps its original text. Review the held PR, then merge it: `gh pr merge <n> --squash`. |
   | A later run ends `result=noop` with `::notice::base=<tag>`, but that tag has no build run | An earlier dispatch was lost. Confirm no build run exists for it (above), then run `gh workflow run build-inngest-bootstrap-image.yml --ref main -f ref=<tag>` once. |
   | R8: `base=` names a tag that reached `main` through a merge commit and has no image | Delete that tag per ADR-232 §7 (it is off-main content), then re-run the mint. |

   **Digest movement is sanctioned but never silent (#4699).** A non-`mirror_only`
   `workflow_dispatch` of an EXISTING tag re-runs `docker build` and re-pushes it, so the
   tag's GHCR digest **moves** — that is the designed CVE-base-image-rebuild escape hatch
   (the workflow's own header says so), and `mirror_only` is the only dispatch that cannot
   move a digest because it never builds. The detector is the weekly
   `scheduled-vinngest-digest-freshness.yml` run
   (`.github/scripts/vinngest-digest-freshness.sh`): for every `vinngest-v*` tag merged into
   `main` it compares the live `crane digest` against the digest the pin history recorded.
   Reading a verdict: `moved` or `unresolvable` on a NON-pinned tag is a warning-class
   finding — record it, confirm it was a sanctioned re-publish, and move on; the same
   verdicts on the PINNED tag are error-class, because the pin's `@sha256` is now orphaned
   (GHCR keeps the manifest untagged; zot's 5-tag retention can evict it — a bounded fuse).
   **The machinery response to a `moved` verdict on the pinned tag is a NEW tag** — mint a
   higher version on `main` and let the bump pin it — never a re-pin to the moved digest and
   never a blind `mirror_only` of the moved content into zot: the whole point of the check
   is that moved bytes are looked at, not propagated. `never-recorded` means a merged tag
   was superseded before its bump PR merged — reported, not alarmed. `unmeasurable` means
   the instrument (crane/auth/history) failed; it is never a content verdict.

   **Rolling back** to an older image — including the legacy off-main versions (`v1.1.14`,
   `v1.1.24`, `v1.1.26`–`v1.1.39`) — is a **revert commit on `main`**: merge a PR that restores
   the old carrier, pin or recipe content. The mint then publishes it as a NEW, higher version
   and the bump pins it, which is the only pin AC6 accepts. **Never tag an older commit** to
   roll back: a higher version on older content becomes the merged max, and the very next mint
   compares `main`'s tip against it and publishes the newer content again. A manual pin PR to
   an existing older image is an emergency stopgap only:
   AC6 reds `main` while it stands (main-health-monitor files `ci/main-broken`), and the
   next publish's bump moves the pin back up. A *rebuild* of an off-main tag is refused.
2. **The pin bump is authored automatically** by the publish workflow's
   `bump-cloud-init-pin` job (ADR-232): a `soleur-infra[bot]` PR (`soleur-ai[bot]` before #9262) on `soleur/inngest-pin-vX.Y.Z`
   with auto-merge armed when this run's zot mirror reports `ok` and the image carries an
   `org.opencontainers.image.revision` label naming the tag's commit (unlabelled legacy images
   are opened held, and since #9262 so is every `mirror_only` run's PR, which also disarms auto-merge on a reused PR). The detail below is the **manual fallback**, for when that job fails (it
   posts to Slack) or holds the PR. **Never use it after a refusal at stage `args`,
   `ancestry`, or `resolve`** — a hand-written pin fixes none of them:
   - `args`: a workflow copy from before #8747 (the tag is likely off `main`).
   - `ancestry`: a shallow checkout, an unreadable history (`git tag --merged` wrote to
     stderr), a tag re-pointed after the build, or an image whose config cannot be read or
     whose revision label is missing-malformed-or-mismatched.
   - `resolve` "no vinngest-v* tag is merged into HEAD": a checkout without tags.
   - `resolve` "Refusing to author a downgrade": `main` pins a tag above every tag merged
     into `main` (off `main` or deleted).

   Follow step 1's recovery instead.
   **Bump the cloud-init pin in lockstep** — there are **FOUR** pin sites across **TWO** files,
   not three in one: `IREF` and `ZIREF` in `apps/web-platform/infra/cloud-init-inngest.yml`
   (the dedicated host) and `IREF` and `ZIREF` in `apps/web-platform/infra/cloud-init.yml`
   (the web host). CORRECTED 2026-09-10 (#8017) — the old count named one file and missed the
   other entirely, which is exactly how a partial bump happens.
   **Do NOT sweep with a directory-wide `sed`:**
   `cloud-init-inngest-zot-pull-mutation.test.sh` carries a fifth ref pinned at `v1.1.24` as a
   deliberately stale NEGATIVE CONTROL, and the only thing keeping it out of the drift guard's
   population is that a `.test.sh` cannot match the `cloud-init*.yml` glob. Rewriting it turns a
   guard red. AC6 of
   `cloud-init-inngest-bootstrap.test.sh` asserts pin == the semver-max `vinngest-v*` tag
   merged into `main`, so the tag in step 1 MUST exist first (else the bump PR's CI
   fails AC6); pushing the tag without bumping turns `main` red until this PR merges —
   and red **repo-wide**, on every concurrently open pull request that runs the suite, not just
   on the bump branch. A failed bump posts to Slack and an ancestry-refused build posts to
   Slack, but an ordinary build failure notifies nobody, so the window can stay open silently.
   Keep it to the length of one build run: do not push the tag until the digest commit is
   ready to land.

   **A stale-schema row is not a sick host.** `scheduled-inngest-health.yml` grades liveness and
   will keep reporting the host HEALTHY on a row the execute gate refuses as `stale_schema` — the
   two ask different questions, and that divergence is by design, not a monitoring gap. A host
   running an older image is serving fine and simply cannot answer the execute gate's question.
3. **Dispatch the deploy** (workflow_dispatch-only; the build never chains into it):

   ```
   gh workflow run deploy-inngest-image.yml -f tag=v1.1.16
   ```

4. **Verify via the deploy-status webhook (NO SSH)** — single authenticated GET:

   ```
   WS=$(doppler secrets get WEBHOOK_DEPLOY_SECRET -p soleur -c prd_terraform --plain)
   CID=$(doppler secrets get CF_ACCESS_CLIENT_ID -p soleur -c prd_terraform --plain)
   CSEC=$(doppler secrets get CF_ACCESS_CLIENT_SECRET -p soleur -c prd_terraform --plain)
   HMAC=$(printf '' | HMAC_KEY="$WS" python3 -I -c 'import hashlib,hmac,os,sys;k=os.environb.get(b"HMAC_KEY");k or sys.exit(1);sys.stdout.write(hmac.new(k,sys.stdin.buffer.read(),hashlib.sha256).hexdigest())')
   curl -fsS -H "X-Signature-256: sha256=${HMAC}" \
     -H "CF-Access-Client-Id: ${CID}" -H "CF-Access-Client-Secret: ${CSEC}" \
     "https://deploy.soleur.ai/hooks/deploy-status" | jq '{component, tag, reason, exit_code}'
   ```

   Expect `{component:"inngest", tag:"v1.1.16", reason:"success"}` (durable backend
   live). `reason:"success_degraded_durability"` = the SQLite fail-safe fired
   (Redis not ready, #5547). Use the literal host `deploy.soleur.ai` — do NOT
   interpolate `$(doppler secrets get APP_DOMAIN_BASE …)` (reads empty / races).

## FR5 flag flip

`SOLEUR_FR5_ENABLED` gates PR-G (#3947) cohort exposure of the autonomous-draft trigger surface. NOT Terraform-managed (one-time human decision, not a credential). Flip procedure:

1. Confirm current state:

   ```
   doppler secrets get SOLEUR_FR5_ENABLED -p soleur -c prd --plain
   ```

2. Decide explicitly: this flips a production user-facing feature from gated to open. Confirm with `${USER}`.
3. Flip:

   ```
   echo 'true' | doppler secrets set SOLEUR_FR5_ENABLED -p soleur -c prd --no-interactive
   ```

4. Restart the web platform so it re-reads — re-run `web-platform-release.yml`. The container
   swap IS the restart; `ci-deploy.sh` deliberately rejects `restart web-platform` because a
   web-platform restart is docker-level, not systemd-level. No host login is involved.

## Arming the probe heartbeat (#9703)

`betteruptime_heartbeat.inngest_server_probe` (`soleur-inngest-server-probe-prd`, period 3600, grace
1800) is the dead-man's-switch for `logtail_exploration_alert.inngest_luks_wrong_volume`, which reads a
silent probe pipeline as healthy. It ships born paused. Its feeder is
`.github/workflows/scheduled-inngest-probe-heartbeat.yml`, started every 15 minutes by the watchdog
dispatch clock (ADR-248; the `schedule:` fallback alone delivers one run every 2-7 h and cannot hold the
5400 s budget), which runs `scripts/inngest-probe-heartbeat-feeder.sh`: it queries the Logs
warehouse for the newest `host_role=dedicated` `SOLEUR_INNGEST_SERVER_PROBE` row and beats the heartbeat
only when that row is at most 4500 s old and the heartbeat is **unpaused**. While the heartbeat is
paused the verifier reports `verdict=fresh_heartbeat_paused` and sends nothing, so a paused heartbeat is
**fed but not armed**. It was armed on 2026-10-12 through the command below: read-back
`status=up paused=false`, and feeder runs 38264380002 (forced), 38265381453 and 38267189184
(clock-dispatched) each reported `verdict=beat http=200`. That is a dated record: read the live state from
Better Stack, not from this paragraph.

Since #10390 the beat also certifies the **serving verdict**, not just row freshness: the feeder grades
the same freshest row's `server_active`/`http_code`/`cutover_flag` through the shared
`classify_dedicated_host` def and beats `<url>/fail` on `not-serving` (verdict `fail_beat` — an intended
immediate incident), beats normally on `healthy` and `stopped-by-brake`, and withholds
(`verdict=serving_unavailable`, exit 3) when the fields do not grade to a verdict.

**Reading the feeder (no SSH).** Each run prints one `inngest-probe-feeder: verdict=<v> ...` line. Once
the warehouse has answered it carries `rows_total rows_probe rows_host rows_dedicated newest_dt lines
dt_rejected` (and `age_s`), so an empty warehouse, a host or role filter dropping rows, rows that arrived
in an unreadable shape (`lines` above `rows_total`) and a stale-but-present row are told apart from that
one line. `dt_rejected` counts dedicated rows excluded because their timestamp is not in the warehouse's own
shape (for example it carries a zone offset); `newest_dt` ignores them, so `producer_silent` or
`row_unusable` with `dt_rejected` above 0 is a timestamp-format fault to check first, not a dark pipeline.
`query_failed`, `clock_malformed`, `usage`, `trap_remapped`, `xtrace_refused` and the empty-window
`no_rows` form carry no complete funnel. `heartbeat_not_unique` carries `paged=1` when the API reports a
further page (the feeder then refuses to trust a page-1 answer). A run that died before printing any marker
(the script missing, a parse error) prints `verdict=no_marker rc=<n>`.
Exit 0 means exactly `beat`, `fail_beat` or `fresh_heartbeat_paused` (`--selftest` is the one other zero and is never
run by the workflow). Verdicts: `no_rows` / `producer_silent` (no fresh dedicated probe row; the probe
pipeline is dark, which is what this heartbeat exists to report), `row_unusable` (no readable timestamp
among the dedicated rows, or the newest is future-dated; a data fault, not proof the pipeline is dark),
`query_failed` (warehouse unreadable; says nothing about the store), `beat_failed` (a fresh row existed
but the heartbeat could not be resolved or delivered), `serving_unavailable` (a fresh row existed but its
serving fields did not grade to a verdict — withheld, never a false beat either way). The Sentry monitor
`scheduled-inngest-probe-heartbeat` checks in `ok` only for the three exit-0 verdicts (including `fail_beat`,
whose 2xx /fail POST IS the delivered incident); `error` means
"withheld or failed", not "feeder broken". `bash scripts/inngest-probe-heartbeat-feeder.sh --selftest`
prints `selftest=ok` with no network or credentials. A local run sends nothing ONLY while the heartbeat
is paused; once armed, the same command beats the heartbeat, which is a production write. It needs the
four secrets `BETTERSTACK_QUERY_HOST`, `BETTERSTACK_QUERY_USERNAME`, `BETTERSTACK_QUERY_PASSWORD` and
`BETTERSTACK_API_TOKEN_READONLY` (all in Doppler `prd_terraform`):
`doppler run -p soleur -c prd_terraform -- env -u INNGEST_FEEDER_NOW -u INNGEST_PROBE_ROW_LIB -u INNGEST_CLASSIFY_LIB bash scripts/inngest-probe-heartbeat-feeder.sh`
(the three `env -u` seals keep a stale exported test seam from deciding the verdict). Exit codes are 0 beat
or paused, 3 withheld, 4 beat could not be delivered, 64 usage, 78 tracing refused.

**Arming is a production write to Better Stack.** Run the command below only after the operator has
authorized THIS command as a unit; a menu answer or an earlier approval does not authorize it. It is
one compound command so that the unpause and its rollback live in one shell under a `trap`: a catchable
interruption (INT, TERM, HUP, a shell exit) rolls back, while SIGKILL or a lost machine cannot, and the
Better Stack page at 5400 s is then the only backstop (see "Re-pause" below). It needs a `doppler` login
that can read `prd_terraform` and a `gh` login with `actions: write`. No dashboard step and no SSH step. The write token is read
inside `doppler run` and sent through `curl --config -`; nothing below prints it or the heartbeat URL.
Run it through the Monitor tool, never as a foreground call: it can run for up to 75 minutes.
Expect the forced dispatch to cost one slot of beat-budget tolerance, so read back a second
`verdict=beat` before treating the heartbeat as armed.

<!-- lint-infra-ignore start -->

Preconditions (read-only; the snippet exits non-zero and prints `PREFLIGHT: FAIL <reason>` on any miss):

```bash
# P0  tokens: reads use the READ-ONLY token; only the arm block below reads the write token.
#     (The soak behind this procedure measured the first-sighting lag of a new hourly probe row at under
#     2 minutes; the 4500 s bound assumes lag well under 14 minutes. Re-check it from the run logs'
#     `newest_dt` / `age_s` before arming if the pipeline has been changed since.)
hbr() { doppler run -p soleur -c prd_terraform --silent -- bash -c '
  [[ "$BETTERSTACK_API_TOKEN_READONLY" =~ ^[A-Za-z0-9._~+/=-]{20,}$ ]] || { echo "token shape refused" >&2; exit 78; }
  printf "header = \"Authorization: Bearer %s\"\n" "$BETTERSTACK_API_TOKEN_READONLY" | curl --disable --noproxy "*" -fsS --max-time 20 --config - "$@"' _ "$@"; }

# P1+P2  the feeder is on main, the clock has dispatched the workflow, the latest four completed runs all
# report freshness with the heartbeat still paused, and Sentry received every check-in
preflight() {
  local fail="" n=0 first="" last="" rid ev created log v sent
  git fetch -q origin main && git log origin/main --oneline -1 -- scripts/inngest-probe-heartbeat-feeder.sh | grep -q . \
    || { echo "PREFLIGHT: FAIL feeder not on main"; return 1; }
  while IFS=$'\t' read -r rid ev created; do
    [ -n "$rid" ] || continue
    log="$(mktemp)"; gh run view "$rid" --log > "$log"
    v="$(grep -o 'inngest-probe-feeder: verdict=[a-z_]*' "$log" | tail -1 | sed 's/.*verdict=//')"
    sent="$(grep -o 'sentry-heartbeat: http_code=[0-9]*' "$log" | tail -1)"
    rm -f "$log"
    echo "$rid $ev $created verdict=${v:-none} ${sent:-sentry-heartbeat=none}"
    n=$((n + 1)); [ -n "$first" ] || first="$created"; last="$created"
    [ "$ev" = workflow_dispatch ] || fail="$fail run $rid event=$ev;"
    [ "$v" = fresh_heartbeat_paused ] || fail="$fail run $rid verdict=${v:-none};"
    case "$sent" in *http_code=2[0-9][0-9]) : ;; *) fail="$fail run $rid sentry check-in not 2xx;" ;; esac
  done < <(gh run list --workflow=scheduled-inngest-probe-heartbeat.yml --status completed --limit 4 --json databaseId,event,createdAt --jq '.[] | [.databaseId, .event, .createdAt] | @tsv')
  [ "$n" = 4 ] || fail="$fail saw $n runs, expected 4;"
  [ "$(( $(date -u -d "$first" +%s) - $(date -u -d "$last" +%s) ))" -ge 2400 ] 2>/dev/null \
    && : || fail="$fail the four runs span less than 40 minutes;"   # newest first, so first - last is the span; 3 slots = 45 min nominal, minus per-slot clock jitter
  # P3  live heartbeat state (the URL attribute is deliberately not selected)
  local live
  live="$(hbr "https://uptime.betterstack.com/api/v2/heartbeats?per_page=250" \
    | jq -r '.data[] | select(.attributes.name=="soleur-inngest-server-probe-prd") | [.id, .attributes.status, (.attributes.paused|tostring), (.attributes.period|tostring), (.attributes.grace|tostring)] | join(" ")')"
  echo "heartbeat: $live"
  [ "$live" = "504655 paused true 3600 1800" ] || fail="$fail heartbeat state is '$live';"
  [ -z "$fail" ] && echo "PREFLIGHT: PASS" || { echo "PREFLIGHT: FAIL$fail"; return 1; }
}
preflight
# A manual dispatch inside a slot makes the clock skip it and consumes the budget's one slot of tolerance,
# so do not stack manual runs (the check above cannot tell a clock dispatch from a manual one).
```

Arm (WRITE; poll deadline 4500 s of wall clock, leaving a 15-minute rollback margin inside
`period + grace`):

```bash
set -uo pipefail
EXPECT_ID=504655; NAME=soleur-inngest-server-probe-prd; BASE=https://uptime.betterstack.com/api/v2/heartbeats
hb() { doppler run -p soleur -c prd_terraform --silent -- bash -c '
  [[ "$BETTERSTACK_API_TOKEN" =~ ^[A-Za-z0-9._~+/=-]{20,}$ ]] || { echo "token shape refused" >&2; exit 78; }
  printf "header = \"Authorization: Bearer %s\"\n" "$BETTERSTACK_API_TOKEN" | curl --disable --noproxy "*" -fsS --max-time 20 --config - "$@"' _ "$@"; }
patch() { hb -X PATCH -H 'Content-Type: application/json' --data-binary "{\"paused\":$1}" "$BASE/$HB" | jq -e ".data.attributes.paused == $1" >/dev/null; }
rollback() {  # runs on EXIT, INT, TERM, HUP; three attempts, each confirmed by read-back
  trap - EXIT INT TERM HUP
  for t in 1 2 3; do patch true && { echo "ROLLED BACK (paused=true read back)"; exit 1; }; sleep 5; done
  echo "ROLLBACK FAILED - pause heartbeat $HB now; Better Stack pages within 5400 s of the unpause"; exit 2
}
HB=$(hb "$BASE?per_page=250" | jq -r --arg n "$NAME" '[.data[] | select(.attributes.name==$n)] | if length==1 then .[0].id else empty end')
[ "$HB" = "$EXPECT_ID" ] || { echo "heartbeat id '$HB' is not the expected $EXPECT_ID (or not unique): refusing"; exit 3; }
[ "$(hb "$BASE/$HB" | jq -r '.data.attributes.status')" = "paused" ] || { echo "heartbeat is not paused: refusing a second arm"; exit 3; }
trap rollback EXIT INT TERM HUP
patch false || { echo "unpause not confirmed by read-back"; exit 1; }     # exit fires the rollback trap
echo "ARM_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)"                              # anchor for the read-back
gh workflow run scheduled-inngest-probe-heartbeat.yml --ref main \
  || echo "FORCED DISPATCH FAILED; waiting for the watchdog clock instead"  # force one real beat now
SECONDS=0; last=""
while [ "$SECONDS" -lt 4500 ]; do
  s=$(hb "$BASE/$HB" | jq -r '.data.attributes.status')
  [ "$s" != "$last" ] || [ $((SECONDS % 300)) -lt 30 ] && echo "$(date -u +%H:%M:%S) elapsed=${SECONDS}s status=$s"; last="$s"
  if [ "$s" = "up" ]; then trap - EXIT INT TERM HUP; echo "ARMED: status=up after ${SECONDS}s"; exit 0; fi
  sleep 30
done
echo "arm failed: status never reached up in ${SECONDS}s"; exit 1       # exit fires the rollback trap
```

<!-- lint-infra-ignore end -->

Exit codes of the arm command: 0 armed (`status=up`), 1 rolled back or never reached `up`, 2 ROLLBACK
FAILED, 3 refused before any write (wrong id, not unique, or not paused).

Re-pause (WRITE; use it when the arm command printed `ROLLBACK FAILED`, or when its shell died after the
unpause, because Better Stack pages within 5400 s of an unfed unpause):

```bash
hb() { doppler run -p soleur -c prd_terraform --silent -- bash -c '
  [[ "$BETTERSTACK_API_TOKEN" =~ ^[A-Za-z0-9._~+/=-]{20,}$ ]] || { echo "token shape refused" >&2; exit 78; }
  printf "header = \"Authorization: Bearer %s\"\n" "$BETTERSTACK_API_TOKEN" | curl --disable --noproxy "*" -fsS --max-time 20 --config - "$@"' _ "$@"; }
hb -X PATCH -H 'Content-Type: application/json' --data-binary '{"paused":true}' \
  https://uptime.betterstack.com/api/v2/heartbeats/504655 | jq -e '.data.attributes.paused == true' && echo PAUSED
```

Read-back (READ), after `ARMED`: with `ARM_AT` as the instant the arm command printed, list the runs created
since (`gh run list --workflow=scheduled-inngest-probe-heartbeat.yml --created ">=$ARM_AT" --json databaseId,createdAt`)
and read each run's `verdict=` line as in P2. Expect `verdict=beat http=2xx` on the forced run, then a second
`verdict=beat` on a LATER run (one slot later), and the P3 state `504655 up false 3600 1800`. Only then drop
`arming_pending` from the manifest row in a record PR. The Stage 3a record PR (#10134, 2026-10-12) does this;
from its merge it re-arms the nightly reconcile's `fed-but-paused`
class (`SOLEUR_HEARTBEAT_RECONCILE_*`), which is the net if anything re-pauses the heartbeat (a paused heartbeat
makes the feeder report `fresh_heartbeat_paused` with exit 0, so the feeder itself would not alert), and the
reconcile is only meaningful after that record PR. If the command rolled back, read the newest completed run's
`verdict=` line: `fresh_heartbeat_paused` after the unpause means that run predates it, `beat_failed` means
the feeder cannot deliver, and any withheld verdict means the probe pipeline itself is dark (the finding this
heartbeat exists for). To retry after a rollback, re-run the command (the heartbeat is paused again).

## Unpause heartbeat

The BetterStack heartbeat is created with `paused = true` to avoid false alerts during the post-apply / pre-bootstrap gap. After [§ Fresh-host bootstrap](#fresh-host-bootstrap) succeeds and the first heartbeat ping is received, choose one of:

**Option A — UI (one-off):** Visit `https://uptime.betterstack.com/team/520508/heartbeats` → find `soleur-inngest-server-prd` → toggle pause off.

**Option B — API (agent-driveable):**

```
TOKEN=$(doppler secrets get BETTERSTACK_API_TOKEN -p soleur -c prd_terraform --plain)
curl -X PATCH https://uptime.betterstack.com/api/v2/heartbeats/460830 \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"paused": false}'
unset TOKEN
```

<!-- lint-infra-ignore start -->

The `lifecycle { ignore_changes = [paused] }` on `betteruptime_heartbeat.inngest_prd` ensures future `terraform apply` runs do NOT revert the unpause regardless of which option you used.

Confirm pings are flowing:

```
TOKEN=$(doppler secrets get BETTERSTACK_API_TOKEN -p soleur -c prd_terraform --plain)
curl -s https://uptime.betterstack.com/api/v2/heartbeats/460830 \
  -H "Authorization: Bearer $TOKEN" \
  | jq '.data.attributes | {status, last_ping_at}'
unset TOKEN
```

<!-- lint-infra-ignore end -->

## SQLite event-store retention

The Inngest SQLite store at `/var/lib/inngest/main.db` grows over time with retained events. There is no built-in rotation. At alpha-internal volume (~1k events/day × ~2KB avg), the store grows ~60MB/month — benign for ~1 year, then unbounded.

**This procedure is SUPERSEDED on any host running the durable backend, which is every
production host today.** Measured on web-1 (`hetzner-123931471`) while writing this:
inngest-server logs `initialized database db=postgres` and `using external redis` on every
start, so events live in Supabase Postgres and the queue/run-state lives in Redis —
`/var/lib/inngest/main.db` is not the event store. `--sqlite-dir /var/lib/inngest` remains in
argv in BOTH forms (`inngest-bootstrap.sh:799`), so the directory's continued existence is not
evidence that it holds events. Deleting rows from it would reclaim nothing and stop nothing.

**Monitoring, no SSH:** root-disk headroom is already reported by
[§ Reading host state without SSH](#reading-host-state-without-ssh) as
`.journald_storage.root_avail` and `.journald_storage.inngest_store_bytes`, and `disk-monitor.sh`
pages independently on volume pressure. Read those rather than logging in to run `du`.

**If a host is ever run on the SQLite form** (the #5547 fail-safe, i.e. `.reason` reads
`success_degraded_durability`), the retention question returns and there is **no no-SSH verb for
it today**: `ci-deploy.sh` accepts `deploy|restart|quiesce|enable` only, and adding a
stop-VACUUM-start verb would widen the root-run allowlisted surface for a case that is currently
hypothetical. That gap is tracked rather than papered over with a host login — see the
follow-up issue linked from the #7286 PR. The correct response to a degraded-durability host is
to fix the durability regression, not to prune its fallback store.

## Durable backend (Supabase Postgres + self-hosted Redis) — #5450

> Migrating Inngest off bundled SQLite + in-memory Redis (ephemeral root disk) onto
> **Supabase Postgres** (`--postgres-uri`, dedicated EU project, session pooler :5432) +
> **self-hosted Redis** (`--redis-uri`, AOF on `/mnt/data`). Closes the silent-loss gap where a
> host re-provision drops every HTTP-armed `event-scheduled-reminder`. Executes the Postgres
> migration ADR-030 deferred. Plan: `knowledge-base/project/plans/archive/20261013-032858-2026-06-17-feat-inngest-durable-backend-supabase-postgres-plan.md`.

### Host-rebuild durability matrix (per mechanism)

"Dies with session?" (process restart) is distinct from "Survives host re-provision?" (fresh root disk).
The bug is the **host-rebuild** column, not the session column.

| Mechanism | Re-arms on web redeploy? | Survives process restart? | Survives host re-provision (pre-migration) | Survives host re-provision (post-migration) |
|---|---|---|---|---|
| `cron-*` (recurring) | Yes (registered every deploy) | Yes | Yes (re-armed on next deploy) | Yes |
| `oneshot-*` (first-arm) | n/a | Yes | Yes (boot-arm re-arms, ADR-046 I4) | Yes |
| `oneshot-*` (conditional re-arm, diverged ts) | n/a | Yes | **No — silent loss** | Yes (durable queue) |
| `event-scheduled-reminder` (HTTP-armed future `ts`) | No | Yes (queue in Redis) | **No — silent loss** | **Yes (durable Redis AOF)** |

### Phase 0 spike verdicts (2026-06-17, inngest v1.19.4, local docker harness — the Phase 1 gate)

CLI semantics (`inngest start --help`): `--postgres-uri` = "configuration and history persistence
(defaults to SQLite)"; `--redis-uri` = "external **queue and run state** (defaults to self-contained
**in-memory Redis** with periodic snapshot backups)". The armed-event **queue lives in Redis**, not Postgres.

- **0.2 FR1 durability boundary — durable Redis is MANDATORY.** Wiped-volume restart (recreate the
  inngest container = fresh root disk; Postgres + external-Redis volumes persist):
  - Postgres-only (default in-memory Redis): armed future-`ts` event **LOST** (did not fire).
  - Postgres + external durable Redis (AOF, `appendfsync everysec`): armed event **SURVIVED**, fired at its `ts`.
  - → Configure **both** Postgres and durable Redis (since #5560 both are delivered via the doppler-run **environment** — `INNGEST_POSTGRES_URI` + a constructed `INNGEST_REDIS_URI` — NOT on argv; see § Secret delivery). Postgres alone does NOT persist the queue.
- **0.3 Fail-closed vs silent fallback — Inngest FAILS CLOSED.** With a reachable-but-refused backend
  it exits non-zero (`failed to connect … connection refused`); `/health` never returns 200; **no**
  silent degrade to a healthy SQLite state. → The existing `/health` 200 gate already catches an
  *unreachable* backend. The residual silent-non-durable risk is **sentinel-absent** (ExecStart drops the
  durable config → defaults to SQLite **while** `/health`=200). The hard gate therefore asserts: (a) the
  running inngest cmdline contains the non-secret `--postgres-max-open-conns` durable sentinel (**#5560**:
  the postgres/redis URIs + signing/event keys are delivered via the doppler-run **environment**, never
  argv — `/proc/<pid>/cmdline` is world-readable, so detection keys on the sentinel, not `--postgres-uri`),
  (b) `inngest-redis` unit active + Redis ping, (c) Postgres reachable — NOT a "fail-open post-start assertion".
- **0.4 Cutover-recovery — enumeration is FEASIBLE; no app-side ledger required.** The server's GraphQL
  (`/v0/gql` `eventsV2(filter:{from!,until,eventNames,query,includeInternalEvents})`) returns received
  events by time window, including future-dated `reminder.scheduled`. Cutover recovery = quiesce arming →
  enumerate the OLD server's future-dated, not-yet-fired `reminder.scheduled` events → re-arm on the new
  Postgres+Redis server (cross-ref `runs` to exclude already-fired → avoid double-posting a comment).
  Dual-run-drain (run old SQLite server until armed reminders fire) is the simpler fallback. **No
  `scheduled_reminders` Supabase migration / boot reconciler is needed** (removes that conditional Phase-1 scope).
- **0.5 Pooler mode — session :5432 only (LIVE-confirmed).** Inngest uses sqlc prepared statements;
  Supabase **transaction pooler :6543 breaks them** (PgBouncer transaction mode). Use **Supavisor
  session pooler :5432**. **Live-verified 2026-06-17**: inngest v1.19.4 connected to the dedicated EU
  project (`soleur-inngest-prd`, ref `pigsfuxruiopinouvjwy`, `aws-0-eu-west-1.pooler.supabase.com:5432`,
  user `postgres.<ref>`) and **ran its migrations** cleanly (`ran database migrations db=postgres`).
  The dedicated project IS the isolation boundary, so the connection uses the project's `postgres` role
  via the pooler (verified) rather than a custom role (custom-role-via-Supavisor routing is the
  unverified part; a dedicated role inside an already-isolated project adds pooler-auth risk for
  marginal benefit — so the planned `inngest-supabase-bootstrap.sql` role bootstrap is intentionally
  dropped). `INNGEST_POSTGRES_URI` is set out-of-band in Doppler prd (see inngest.tf).

### Availability coupling (permanent, post-migration)

Post-cutover Inngest **cannot start** without Supabase + Redis reachable (the in-memory fallback is
gone — proven fail-closed in 0.3). Pre-migration it survived a Supabase outage on local SQLite; it no
longer will. Knowingly traded for durability + PITR + ADR-030 closure. The dedicated Inngest Supabase
project + co-located Redis keep the blast radius off the main app's project.

### Cutover procedure (Phase 2 — low-traffic window, rollback-ready)

**Before any cutover, consult:** [Destructive datastore migration safety pattern](../../../project/learnings/best-practices/2026-06-18-destructive-datastore-migration-backup-inventory-after-diff.md) — every destructive datastore migration takes (a) a recovery backup, (b) a full inventory BEFORE, (c) an after-inventory + diff. Steps 0.5 and 5 below are this runbook's instance of that pattern.

The KEYSTONE risk (plan §Sharp Edges): armed `reminder.scheduled` events live ONLY in Inngest state —
there is no app-side reminder store. A fresh-Postgres cutover loses them unless they are enumerated and
re-armed. Run these steps in order, **starting with Step 0** (the secret-provisioning precondition —
`INNGEST_REDIS_PASSWORD` is not created at merge time); the connection string is set out-of-band in
Doppler prd (`INNGEST_POSTGRES_URI`, see inngest.tf) and must be **URL-safe** (the provisioned value is
hex — no percent-encoding needed; if rotated to a password with reserved chars, URL-encode before
setting).

0. **Provision the Redis secret** (one-time precondition — `INNGEST_REDIS_PASSWORD` is NOT created at
   merge time; the `apply-web-platform-infra.yml` allow-list now reconciles it on the next infra merge,
   but for an immediate cutover run, apply it explicitly here). `INNGEST_POSTGRES_URI` is already present
   (set out-of-band, see inngest.tf). From the repo root:

   ```bash
   # Backend creds — post-O5b the prd_terraform AWS_* pair is read-only; a state
   # write (apply) needs the Tier-B pair exported ambiently (the tf-var
   # transformer renames injected secrets, so no loader sets bare AWS_*):
   export AWS_ACCESS_KEY_ID=$(doppler secrets get TF_STATE_AWS_ACCESS_KEY_ID -p soleur-infra-privileged -c prd --plain)
   export AWS_SECRET_ACCESS_KEY=$(doppler secrets get TF_STATE_AWS_SECRET_ACCESS_KEY -p soleur-infra-privileged -c prd --plain)
   terraform -chdir=apps/web-platform/infra init -input=false
   doppler run -p soleur-infra-privileged -c prd --name-transformer tf-var -- \
     doppler run -p soleur -c prd_terraform --name-transformer tf-var --preserve-env -- \
     terraform -chdir=apps/web-platform/infra apply \
       -target=random_password.inngest_redis_password_prd \
       -target=doppler_secret.inngest_redis_password_prd
   # Confirm the secret now exists (read-only, no SSH):
   doppler secrets get INNGEST_REDIS_PASSWORD -p soleur -c prd --plain   # → 48-char URL-safe value
   ```

   If the value is already present (a prior auto-apply or manual run minted it), this is a clean no-op —
   proceed to step 0.5.
0.5. **Pre-cutover safety gates (MANDATORY — #5509).** Before quiescing, capture a recovery point and a
   full-state baseline so this destructive cutover is reversible and verifiable (no SSH):

   ```bash
   gh workflow run cutover-inngest.yml --field op=backup      # Hetzner server snapshot (full root disk incl. /var/lib/inngest); logs the image id
   gh workflow run cutover-inngest.yml --field op=inventory   # BEFORE baseline: {functions, event_names, armed_reminder_ids}
   ```

   Record the backup **image id** (the run logs `DELETE /v1/images/<id>` to free it after the cutover is
   confirmed) and save the BEFORE inventory block from the run log — both feed step 5's correctness check.
   Do NOT proceed to quiesce until the `op=backup` snapshot action reports `success`.
1. **Quiesce arming** (no reminder armed into the doomed old SQLite mid-cutover):

   ```bash
   doppler secrets set INNGEST_CUTOVER_QUIESCE=1 -p soleur -c prd --no-interactive
   # POST /api/internal/schedule-reminder now returns 503 + Retry-After: 120.
   ```

2. **Reminder survival — DEFAULT: dual-run-drain; FALLBACK: no-SSH enumerate + re-arm.** Armed
   `reminder.scheduled` events live ONLY in Inngest state (verdict 0.4 — no app-side ledger). A
   fresh-Postgres cutover drops any still-armed reminder unless it is allowed to fire first OR is
   enumerated and re-armed. There is **no operator shell step** here — both paths are no-SSH.
   - **DEFAULT — dual-run-drain (simplest, no re-arm risk):** with arming quiesced (step 1), let the
     OLD SQLite server keep running until its already-armed reminders fire on their own. When the
     soonest pending fire-time has passed, proceed to deploy (step 4). No enumeration, no re-arm, no
     double-fire window. Best when only a few near-term reminders are armed.
   - **FALLBACK — capture + re-arm (when draining is not viable):** when too many reminders are armed
     or they fire too far out to wait, **persist the still-armed set ON-HOST BEFORE the deploy** — a
     post-deploy `op=rearm` self-enumerate would query the NEW (empty) Postgres+Redis backend and
     silently lose every reminder (#5542):

     ```bash
     gh workflow run cutover-inngest.yml --field op=enumerate   # OPTIONAL visibility: logs count + reminder_ids
     gh workflow run cutover-inngest.yml --field op=capture     # MANDATORY: persists records on-host pre-deploy
     ```

     `op=capture` drives `/hooks/inngest-rearm-reminders` with `mode=capture`: the host script queries
     the OLD server's `eventsV2`, reconstructs the FULL re-armable payload from each event's `raw`
     envelope (the legacy `id name receivedAt` query was payload-incomplete), drops already-fired events
     via the `runs` cross-ref, paginates to exhaustion, and writes the records to
     `/var/lib/inngest/cutover-capture.json` — under the `--sqlite-dir` volume, which survives the
     cutover's systemd restart (a config change, not a host re-provision). Records stay on-host
     (P2-sec-a) — only counts + `reminder_id`s surface in the run log. Then re-arm AFTER the deploy +
     quiesce-clear in step 6 (`op=rearm`), which **consumes the capture file** (NOT a post-deploy
     self-enumerate) and deletes it on full success. The re-arm routes back through `schedule-reminder`,
     which recomputes the Inngest dedup `id`/`ts` so an event that ALSO survived in state dedups instead
     of double-firing.
3. **Drain in-flight runs** — confirm zero `Running` status for ~60s (or accept-and-document that
   in-flight runs are abandoned; the reminder `post-comment`/`run-check` steps are not idempotent on
   replay, so a re-arm of an already-fired reminder would double-post).
4. **Deploy** via the release pipeline (no SSH): `deploy inngest ghcr.io/jikig-ai/soleur-inngest-bootstrap v1.1.14`.
   The deploy arg is the OCI **image tag** `v1.1.14` (space-separated, matching the CLI-version-bump
   step) — NOT `vinngest-v1.1.14`: the build workflow strips the `vinngest-` GIT-tag prefix and publishes
   the image as `v1.1.14` (GHCR has `v1.1.14`; `vinngest-v1.1.14` does not exist and would fail to pull).
   The `verify_inngest_health` HARD gate fails the deploy if `--postgres-uri` is set but `--redis-uri`
   is absent OR `inngest-redis.service` is inactive.
5. **Verify durability.**
   - **DEFAULT (non-destructive):** the deploy's own `verify_inngest_health` HARD gate (step 4) already
     asserts `--postgres-uri` ⇒ `--redis-uri` present + `inngest-redis` active + `/health` 200 +
     `/v1/functions` ≥1 cron. Combined with the spike-0.2 evidence (a wiped-volume restart survived on
     durable Redis), this is sufficient proof for a normal cutover — no extra step needed.
   - **OPT-IN (destructive, end-to-end proof):** to exercise the real wiped-volume invariant in prod
     shape with no remote shell:

     ```bash
     gh workflow run cutover-inngest.yml --field op=verify-wiped-volume   # async; polls verify-status
     ```

     This drives `/hooks/inngest-wiped-volume-verify`, which **aborts loudly unless the armed set is
     empty** (the real safety gate — it will NOT wipe with a real reminder pending), arms an
     unregistered-`named-check` throwaway that fires a run but posts **zero** comments, wipes
     `/var/lib/inngest`, restarts, and asserts `/health` + `/v1/functions` + the throwaway fired. Only
     run it once the armed set is drained/re-armed.
   - **Correctness diff (MANDATORY — #5509):** re-run `op=inventory` (the AFTER baseline) and diff it
     against the BEFORE block from step 0.5:

     ```bash
     gh workflow run cutover-inngest.yml --field op=inventory   # AFTER baseline
     ```

     Expected: `functions` identical (re-registered every deploy by construction) and `event_names`
     identical. `armed_reminder_ids` MUST be re-present after re-arm (FALLBACK path, step 6) OR
     empty-by-design (DEFAULT dual-run-drain, where the armed set fired on the old server pre-cutover).
     Any unexplained drop in `functions`/`event_names`, or a missing `armed_reminder_id` after re-arm,
     is a cutover defect — restore from the step 0.5 backup image before clearing quiesce.
6. **Re-open arming + re-arm recovered work** (no remote shell):

   ```bash
   doppler secrets set INNGEST_CUTOVER_QUIESCE= -p soleur -c prd --no-interactive  # clears the flag
   # FALLBACK path only: re-arm from the on-host capture persisted in step 2 (op=capture).
   gh workflow run cutover-inngest.yml --field op=rearm
   ```

   Run `op=rearm` ONLY after the quiesce flag is cleared — the host script aborts loud (does not
   silently drop) if it gets a 503 because quiesce is still set. `op=rearm` (mode `rearm-from-capture`)
   consumes `/var/lib/inngest/cutover-capture.json` from step 2 and deletes it on FULL success; a
   missing/corrupt capture is FATAL (non-200), never a silent self-enumerate of the empty new backend.
   - **Retry window (re-arm is replay-on-full-set).** On a partial failure the capture is RETAINED and a
     re-run re-POSTs the entire set; `schedule-reminder` recomputes the dedup `id`/`ts` so a
     still-pending reminder dedups instead of double-arming — but a reminder that *fires* between attempts
     is non-idempotent (it double-posts its comment, same hazard as step 3). So retry `op=rearm` promptly
     and only while quiesce is cleared; do not let hours pass between a partial re-arm and its retry.
   - **Aborted cutover leaves a landmine.** If you run `op=capture` then ABORT before `op=rearm`, the
     capture file persists on-host. A steady-state `op=rearm` (mode `rearm`, the default) deliberately
     IGNORES it (self-enumerates the live backend), so it will not hijack a routine re-arm — but it is
     stale clutter. After an aborted cutover, re-run the cutover from `op=capture` (which overwrites it),
     or let the next successful cutover `op=rearm` consume it.
7. **Rollback tripwire** — reverting ExecStart to `--sqlite-dir` is data-safe ONLY before any *real*
   (non-throwaway) reminder is armed against Postgres. After that the stale SQLite is missing those
   reminders AND could double-fire ones Postgres recorded → **forward-fix only**. On a committed
   cutover, wipe the old `/var/lib/inngest` SQLite so an accidental SQLite boot cannot replay dead
   reminders.

## Dedicated-host cutover (Phase 2, `op=execute` gated sequence) — Ref #6178

> **This is the ADR-100 dedicated-host extraction cutover** (move Inngest off the
> co-located web host onto the singleton `hcloud_server.inngest` at `10.0.1.40`),
> distinct from the same-host durable-backend cutover above. It flips the dedicated
> host to **prod Postgres**, gated behind a
> Redis `FLUSHALL` + `DBSIZE==0` assertion (ADR-100 Decision 6/6a). **Every operator
> action here is a Doppler write, a `workflow_dispatch`, or a Better Stack read — there is
> NO `ssh`/host-shell step** (`hr-no-ssh-fallback-in-runbooks`; the dedicated host is
> deny-all-public). Only counts + `reminder_id`s / `function_id`s ever surface in a run
> log — never reminder bodies, actors, or connection strings.

**Precondition (do this DURING the dark window, well before the maintenance window):** the
flip oneshot (`inngest-cutover-flip.sh` + `.service`/`.timer` + `inngest-server-flip-guard.sh`)
must already be baked into the OCI image and installed on the dark host. Installing it is a
cloud-init/OCI change that **force-replaces the singleton** — zero prod-downtime by
construction (the host serves zero prod crons — note this is NOT because its backend is
non-prod: since 2026-07-23 `soleur-inngest/prd` holds the PROD DSN, and what keeps the host dark
is `inngest-server-flip-guard.sh` refusing a prod-URI start while the flag sits outside
`{armed,flipping,flushed,done}`. See ADR-100's 2026-08-20 addendum; the AOF
Redis volume survives the replace). Never run that force-replace inside the maintenance
window. The poll timer ships **enabled and stays enabled for the host's whole life** — the
FSM flag (`INNGEST_CUTOVER_FLIP`) is the sole gate, so arming is pure Doppler writes with no
`systemctl` step.

### Op order (the gated sequence)

`op=execute` → **`op=arm` (no-SSH flip arm)** → **operator app-repoint (2.4)** → `op=rearm` →
`op=verify`. `op=execute` automates the web-host-expressible spine (2.0 → 2.2) and then
**withholds a SEAM**. As of #6369 the flip arm (2.2b/2.3) is **no longer an operator Doppler
write** — it is the no-SSH **`op=arm`** dispatch (a prod-write behind explicit dispatch + the
`inngest-cutover` GitHub Environment required-reviewer gate, which satisfies
`hr-menu-option-ack-not-prod-write-auth`: the dispatch + approval IS the ack). The remaining true
operator seam is **2.4** (app-repoint, a code merge), printed in the SEAM as an out-of-band
hand-off. There is no 2.2a web-2 freeze/recreate seam any more — see §1a.

The first `op=execute` stops at 2.2 `STILL RUNNING` by design (the web scheduler is still up), so
the loop as driven from CI is **`op=execute` → window procedure → `op=quiesce-web` → `op=execute` →
`op=arm`** (#6921). The second `op=execute` resumes its 2.1 capture from the file the quiesce
persisted, and the watchdog leaves the quiesced unit alone (#8077). Design and rejected alternatives:
ADR-100, amendment 2026-09-14.

> **Window procedure — do all four BEFORE `op=quiesce-web`.** `op=quiesce-web` stops production
> scheduling for every user (crons and reminders) until the dedicated host serves and 2.4 has
> redeployed. Nothing is persisted for a reminder that is refused in the window: the caller must
> retry, and `op=rearm` re-arms only what the quiesce captured.
>
> 1. **(a) Confirm the dedicated host is ready.** Two readings, cheapest first.
>
>    **Before dispatching either, know the queue you are joining.** `cutover-inngest.yml` shares the
>    `deploy-inngest-restart` concurrency group (job-level, `cancel-in-progress: false`) with
>    `restart-inngest-server.yml`, `deploy-inngest-image.yml` and the `apply-web-platform-infra.yml`
>    apply jobs — including the `inngest-host-replace` remedy several verdicts below point at.
>    GitHub keeps one running and ONE pending run per group, and a newly queued run REPLACES the
>    pending one — so during the incident this reading diagnoses, a watchdog-dispatched restart can
>    silently CANCEL your queued diagnostic, not merely delay it. A `cancelled` op is that, not a
>    verdict: re-dispatch it. The mechanism and the re-dispatch recipe are under **"Concurrency: a
>    watchdog restart can cancel a queued cutover op"** in § Web scheduler QUIESCED. Read the group's
>    own workflows first — the watchdog (`scheduled-inngest-health.yml`) runs in its own group and only
>    DISPATCHES into this one, so its run list does not show what is queued here:
>
>    ```bash
>    gh run list --workflow cutover-inngest.yml --limit 3 --json databaseId,status,conclusion,createdAt
>    gh run list --workflow restart-inngest-server.yml --limit 3 --json databaseId,status,conclusion,createdAt
>    ```
>
>    The cheaper reading is the standalone diagnostic (#8079): `gh workflow run cutover-inngest.yml
>    -f op=registry-probe`. It is read-only and dispatchable outside any window. Read its run:
>
>    ```bash
>    # The runner RENDERS workflow commands: a `::notice::` in the script is `##[notice]` in the log,
>    # so a grep on the `::` spelling matches nothing on a real run (measured on run 34948634783).
>    # Anchor on the body prefix; it catches the notice, the error, the `::warning::` caveat and
>    # the plain `registry-probe: 1./2./3.` next-step lines a refusal prints after its headline.
>    gh run view <op=registry-probe run id> --log | grep -F 'registry-probe'
>    ```
>
>    A `registry_empty=` line is the **live measurement** (the host answered). A `HOST-STATE VERDICT:
>    dark` notice at exit 0 is **not** — it says the host was not serving as of its newest row and
>    that nothing has registered SINCE that row (after a rollback the server served earlier on the
>    same boot, and those registrations persist), and its warning says what was not measured. Any `REFUSED (…)` line names its own remedy; none of
>    them tells you to SSH or to dispatch a mutating op. The op cannot open the window and cannot
>    stand in for 2.0's gate — it answers a weaker question.
>
>    The gating reading is 2.0 itself. The first `op=execute` must have passed it (the
>    dedicated-host registry pre-flight). Read it from that run:
>
>    ```bash
>    gh run view <first op=execute run id> --log | grep -E '(::|##\[)(notice|error)(::|\])2\.0'
>    ```
>
>    A `2.0 … REFUSED` line means do not open the window; follow its remedy first.
> 2. **(b) Pre-stage the 2.4 PR green** (the `INNGEST_BASE_URL` repoint, checks passed, ready to
>    merge) so the window lasts one merge and one redeploy, not an authoring session.
> 3. **(c) Refuse new reminders for the whole window.** Set `INNGEST_CUTOVER_QUIESCE=1` in Doppler
>    `soleur/prd`, then redeploy web-platform. Doppler values are baked into the container at start
>    (learning `knowledge-base/project/learnings/2026-05-19-doppler-env-hot-reload-limitation.md`),
>    so a flip without the redeploy changes nothing:
>
>    ```bash
>    doppler secrets set INNGEST_CUTOVER_QUIESCE=1 -p soleur -c prd --no-interactive > /dev/null
>    gh run rerun "$(gh run list --workflow=web-platform-release.yml --event workflow_run -L1 --json databaseId -q '.[0].databaseId')"
>    ```
>
>    When that run is green, confirm the flag is live. `POST /api/internal/schedule-reminder` checks
>    the flag right after the Bearer check and before it reads the body, so an empty body is a safe
>    probe: `503` with `X-Soleur-Unavailable: cutover-quiesce` means live; `400` means the container
>    still runs without the flag.
>
>    ```bash
>    TOKEN=$(doppler secrets get INNGEST_MANUAL_TRIGGER_SECRET -p soleur -c prd --plain)
>    curl -sS -o /dev/null -D - -X POST https://app.soleur.ai/api/internal/schedule-reminder \
>      -H "Authorization: Bearer $TOKEN" -H 'content-type: application/json' -d '{}' \
>      | grep -iE '^HTTP/|^x-soleur-unavailable:'
>    unset TOKEN
>    ```
>
>    This is what closes the loss window. Capture-before-stop only narrows it: a reminder armed
>    after the capture and before the stop would land in the web scheduler, miss the capture, and be
>    lost at the stop. With the flag live, every arming attempt in the window gets `503` +
>    `Retry-After: 120` instead. The flag is cleared by the 2.4 redeploy, BEFORE `op=rearm` (step 4
>    below) — `op=rearm` POSTs to the same route.
> 4. **(d) Announce the window** to users before it opens.

> **`op=quiesce-web` (#6178) — the no-SSH ACT behind the 2.2 CHECK.** The `op=execute` 2.2 gate
> only certifies (see §1); `op=quiesce-web` stops and disables inngest across the host-set over the
> private net (HMAC + CF-Access, **no SSH**), then polls `/hooks/deploy-status` for each host's
> synchronous verdict — it does NOT immediate-probe (`TimeoutStopSec=180` means the async stop can
> lag the 202). `lock_contention` from the poll is non-terminal: it keeps polling.
>
> ```bash
> gh workflow run cutover-inngest.yml --field op=quiesce-web   # after the window procedure above
> ```
>
> **Preflight (before any stop).** The run compares `/hooks/infra-config-status` sha256 of
> `/usr/local/bin/{ci-deploy.sh,inngest-inventory.sh,inngest-rearm-reminders.sh,inngest-enumerate-reminders.sh}`
> with the checkout. A mismatch prints `::error::` "config push not landed" and exits 1 without
> dispatching. Remedy: wait for the `apply-deploy-pipeline-fix.yml` run for the merge SHA to go
> green, then re-dispatch.
>
> **What the handler does, by the unit's state.**
>
> - `active` → capture the still-armed reminders to `/var/lib/inngest/cutover-capture.json`
>   (bounded: 120 s, `timeout --kill-after=5`) → write the marker `/var/lib/inngest/quiesced-by-op`
>   (`epoch`, `boot_id`, `host_id`, `run_id`, `capture_sha256`, `capture_count`) → disable → stop →
>   verify → peer fan-out. End state: the quiesced shape (`is-active` ∈ {`inactive`, `failed`} AND
>   `is-enabled` = `disabled`) plus a marker, which the probe reports as `QUIESCED`.
> - already quiesced (a re-dispatch) → no capture, marker untouched (its `epoch` does not move) →
>   idempotent disable/stop → verify → fan-out.
> - unit absent (web-2) → no capture, no marker → verify → fan-out.
> - anything else (`failed`, `activating`, `deactivating`, stopped but still enabled, or
>   `DISABLED_UNATTRIBUTED`) → `quiesce_capture_unavailable`: nothing is disabled or stopped.
>
> Every start path except `op=rollback`'s `enable` refuses the shape: `restart`
> (`inngest_quiesced_restart_refused` / `inngest_disabled_unattributed_restart_refused`),
> `deploy inngest <tag>` (`inngest_quiesced_deploy_refused` / `inngest_disabled_unattributed_deploy_refused`),
> the wiped-volume verify (`quiesced_refused`) and the luks-cutover starts (skipped on `disabled`).
>
> **Failure verdicts and remedies** (full reason → remedy table:
> [deploy-status-debugging.md](../../../../plugins/soleur/skills/postmerge/references/deploy-status-debugging.md#reason-taxonomy)).
> Read the journald line for any of them with
> `doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh --since 2h --grep INNGEST_QUIESCE --limit 50`.
>
> - `quiesce_capture_failed` — the capture failed or timed out; **nothing was stopped**. Read
>   `INNGEST_QUIESCE_CAPTURE_FAILED rc= stderr_tail=` (tag `ci-deploy`; the tail is credential- and
>   URI-scrubbed). If the unit is active but its GQL is dead the capture can never succeed; the unit
>   is still enabled, so dispatch `restart-inngest-server.yml`, then re-dispatch `op=quiesce-web`.
>   There is no override flag.
> - `quiesce_capture_unavailable` — the unit was not `active`, not already quiesced, and not
>   absent, so there was nothing trustworthy to capture; nothing was stopped. Read
>   `INNGEST_QUIESCE_CAPTURE_UNAVAILABLE unit= enabled= state=`. `state=disabled_unattributed` →
>   `op=rollback`, then `op=quiesce-web`. `enabled=enabled` with `unit=failed`, `activating` or
>   `inactive` → the unit is not quiesced, so a restart is allowed: dispatch
>   `restart-inngest-server.yml`, and re-dispatch `op=quiesce-web` once that restart reports the
>   unit serving. `unit=deactivating` → a stop is in flight; re-dispatch after 180 s.
> - `quiesce_marker_write_failed` — the capture succeeded but the marker could not be written;
>   nothing was stopped. Re-dispatch `op=quiesce-web` (it captures again). If it repeats, the
>   `/var/lib/inngest` write path on the host is broken — read the `ci-deploy` rows around the
>   failure and file an issue with the run URL.
> - `quiesced_shape_unrecognized` — the stop and disable verified, but the tri-state did not read
>   `quiesced` (typically the marker is missing or voided). The unit is stopped and disabled, so no
>   scheduler runs; 2.2 will not pass. Dispatch `op=rollback`, then a fresh `op=quiesce-web`.
> - `inngest_still_serving` / `inngest_still_enabled` — persistent means the unit is being
>   RESURRECTED: pull `reason=` from `/hooks/deploy-status` + Better Stack (tag `ci-deploy`) and find
>   what restarts or re-enables it. Do **not** SSH.
> - `quiesced_peer_fanout_unaccepted` — a peer did not return 202. Grep Better Stack for
>   `FANOUT: webhook secret unavailable` and `FANOUT: could not compute the request signature` first:
>   either line means the originating host cannot read its own `deploy-peer` secret or its signer fails
>   (python3 missing), and a re-dispatch will not converge (R9). Otherwise check the peer host
>   and the web→web:9000 firewall, then re-dispatch — stop and disable are idempotent.
> - UNKNOWN/000 — the webhook was unreachable: check CF-Access/HMAC, then re-dispatch.
>
> A watchdog tick that lands inside the stop files one false `[ci/inngest-down]` (R8); see
> [§ Web scheduler QUIESCED](#web-scheduler-quiesced--expected-after-cutover-no-restart--8077).
>
> NB the two "quiesce" meanings are now used together: `INNGEST_CUTOVER_QUIESCE` (Doppler,
> refuses new reminders at the app route — window step (c)) and `op=quiesce-web` (stops and
> disables the scheduler **process**).

> **Pre-flight scans are bounded + observable (#6258, ADR-106).** The `op=inventory` /
> `op=verify` sub-probe scans (`inngest-inventory`, `inngest-registry-probe`,
> `inngest-doublefire-probe`) now enforce a wall-clock deadline + page ceiling and are
> abandon-safe (on timeout they emit `SOLEUR_INNGEST_PREFLIGHT_TIMEOUT` and `exit 1` →
> webhook non-200, releasing the pool). If a pre-flight op returns `HTTP 000`/`500`, use the
> **[Cutover pre-flight-hang triage](#cutover-pre-flight-hang-triage-opinventory--opverify-http-000--6258-adr-106)**
> above — a fast LOUD `SOLEUR_*_TIMEOUT` error is the fix working, NOT a hang, and an
> `op=verify` halt at its `registry_empty` precondition is a legitimate verdict on the dark
> pre-cutover host, NOT a transport failure.

1. **`op=execute`** (pre-flip orchestrator — no prod-write):

   ```bash
   gh workflow run cutover-inngest.yml --field op=execute
   ```

   It runs: **2.0** empty-registry pre-flight (aborts if the dark registry is non-empty — see
   remediation below); **2.1** capture of still-armed reminders (records persist on-host;
   `Σcaptured` + `reminder_id`s only in the log); **2.2** quiesce followed by a **QUIESCE HARD
   GATE** that re-inventories web-1 (the host the `deploy.` ingress targets) and **fails loud +
   withholds the SEAM** unless the scheduler there reports `QUIESCED`. If the gate fails
   (`STILL RUNNING`), run the window procedure and **`op=quiesce-web`** (see the op-order note
   above) and re-run `op=execute`; the gate is a CHECK, `op=quiesce-web` is the ACT. When the gate
   passes it prints the SEAM with the exact operator steps below, then exits 0.

   **2.1 `source` (#6921).** The capture notice reads
   `2.1 capture: Σcaptured=N source=<live|persisted> [captured_at=<ISO>]`:
   - `source=live` — the unit is not quiesced; the script enumerated the running scheduler (the
     first `op=execute`). A failed live enumeration still fails; it never falls back to a file.
   - `source=persisted captured_at=…` — the unit is `QUIESCED` and the persisted capture belongs to
     that quiesce: the capture file is a JSON array, its sha256 equals the marker's
     `capture_sha256`, and the marker has no `capture_consumed_at`. `captured_at` is the marker's
     `epoch` (the quiesce instant); the response also carries `quiesced_since` and
     `rebooted_since_quiesce`. Read `captured_at` before `op=arm`.

   2.1 refuses (exit 1, one `ERROR: capture:` line) when the persisted capture cannot be trusted.
   All three are fixed the same way: reopen scheduling, then take a fresh capture.

   | Refusal | Cause | Remedy |
   |---|---|---|
   | `already re-armed (capture consumed at <ISO>)` | `op=rearm` already fully re-armed this capture | Nothing to resume. If scheduling must reopen, `op=rollback` |
   | `stale_capture — … (<reason>)` | capture file missing, not a JSON array, or its sha256 differs from the marker | `op=rollback`, then the window procedure + `op=quiesce-web` |
   | `capture_unattributed` | the unit is `DISABLED_UNATTRIBUTED` (no valid marker) | `op=rollback`, then the window procedure + `op=quiesce-web` |

   **2.2 verdicts.** Every probe of `/hooks/inngest-inventory` is read, and only the anchored
   fixed-vocabulary start of each body line counts:

   | Verdict | Condition | Remedy |
   |---|---|---|
   | **PASSED** | no probe answered 200, at least one non-200 body carries `inngest-inventory: QUIESCED`, AND every answered non-200 body carries it | — |
   | **STILL RUNNING** | any probe answered 200 | window procedure, then `op=quiesce-web` |
   | **UNKNOWN** — `DISABLED_UNATTRIBUTED` | a body carries `inngest-inventory: DISABLED_UNATTRIBUTED` | `op=rollback`, then the window procedure + `op=quiesce-web` |
   | **UNKNOWN** — non-200 without the sentinel | an answered non-200 body (any of them) lacks the QUIESCED line | branches on 2.1 `source`, below |
   | **UNKNOWN** — `000` only | no probe got an HTTP answer | check CF-Access/HMAC and the run log, then re-dispatch `op=execute` |

   For the non-200-without-sentinel case the run prints the first 120 characters of the last body:
   - `source=persisted` → the on-host `inngest-inventory.sh` predates the QUIESCED verdict (the
     rearm script, delivered by the same push, already saw the quiesced state). Confirm the
     `apply-deploy-pipeline-fix.yml` run for the merge landed, then re-dispatch `op=execute`. Do
     **not** re-run `op=quiesce-web`.
   - `source=live` → the unit is not quiesced. Run the window procedure, then `op=quiesce-web`.

   UNKNOWN and STILL RUNNING both withhold the SEAM.

   Read the SEAM from the run log:

   ```bash
   gh run view <op=execute run id> --log | grep -E '(::|##\[)(notice|error|warning)(::|\])'
   ```

1a. **web-2 needs no cutover step (corrected 2026-09-14, #6921).** web-2 (`10.0.1.11`, hel1
   cattle, running since 2026-07-27 — #6969, ADR-143) was born with `web_colocate_inngest=false`: it
   has no `inngest-server.service`, runs no scheduler and holds no local reminders. `var.web_hosts`
   carries both keys and `CUTOVER_HOSTS` lists both IPs, so the `op=quiesce-web` and `op=rollback`
   fan-out reaches web-2. The quiesce fan-out is a no-op there (absent unit: no capture, no marker).
   The rollback fan-out is not: `enable` fails on the absent unit and writes `inngest_enable_failed`
   to web-2's own deploy-status slot, which the rollback tolerates (it measures only the peer's 202;
   see §Rollback step 3). There is **no web-2
   freeze/recreate step**: nothing on web-2 for 2.1 to capture, for 2.2 to certify, or for
   `op=verify` to catch double-firing. This replaces the former DI-C3 limitation and the former
   mandatory "quiesce web-2" step, both written for a different machine — the fsn1 weight-0 warm
   standby that self-armed oneshots into its own Redis (#6227). That host was destroyed on
   2026-07-17 (#6538), and #6230 was closed as obviated by its retirement. The "single-host web
   set" note that followed was true only until the cattle web-2 was born.

2. **Arm the flip (2.2b/2.3) — dispatch the no-SSH `op=arm` verb (#6369).** This REPLACES the
   former three manual Doppler writes. `op=arm` performs all three writes on
   **`soleur-inngest/prd`** itself and confirms the on-host FSM reached `done` via Better Stack,
   with **no secret value ever echoed** (AC-NOBODY):

   ```bash
   gh workflow run cutover-inngest.yml --field op=arm
   ```

   Then **approve the `inngest-cutover` GitHub Environment required-reviewer gate** on the run —
   that approval IS the prod-write ack (`hr-menu-option-ack-not-prod-write-auth`; the dispatch +
   approval replace the old Doppler-console write). What `op=arm` does, in order:
   - **G1 pre-write FSM-state guard (DI-C2):** refuses to arm over a non-safe
     `INNGEST_CUTOVER_FLIP` state (armed/flipping/flushed/done) — a second arm would re-`FLUSHALL`
     the now-PROD Redis and wipe the live cron queue.
   - **G2 read-through sources (ADR-100 6b):** reads `INNGEST_POSTGRES_URI` +
     `INNGEST_HEARTBEAT_URL` **from `prd_terraform`** via the existing read-only `DOPPLER_TOKEN`
     (the canonical prod values already live there — **no operator seed**), masking each value.
   - **G3 positive prod-URI assertion (DI-C3):** asserts the value targets the prod project's
     session pooler. It does NOT require the value to differ from the current `soleur-inngest/prd`
     URI — that requirement was removed in #7462, because after the first successful arm it is
     permanently true (`op=rollback` has no inverse for the write) and it refused every re-arm.
     Equality is now informational. Superseded wording follows for reference: differs from the dark
     `soleur-inngest/prd` URI, uses the `:5432` session pooler (never `:6543`), and targets the
     prod host — all value-silent.
   - **G3.5 channel-key parity HARD GATE (#6178 durability):** sha256-compares the app
     (`soleur/prd`, read-through) vs host (`soleur-inngest/prd`, arm token) `INNGEST_EVENT_KEY`
     **and** `INNGEST_SIGNING_KEY` — value-silent (AC-NOBODY; only MATCH/MISMATCH reaches the log)
     — and **refuses to arm** if either diverges. These keys are a **SHARED app↔host channel
     token** (ADR-100 §4 Amendment), so a mismatch is the exact #6178 cutover-502 (post-repoint
     every app `inngest.send()` to the host is rejected → `op=rearm` HTTP 502). On MISMATCH,
     reconcile the app to the host's key + redeploy **before** re-running `op=arm` — see §2.4
     key-reconcile below.
   - **G3.6 diagnostic-boot HARD GATE (#7462):** refuses to arm while `INNGEST_DIAGNOSTIC_BOOT` is
     set on `soleur-inngest/prd`, and fails closed if that value cannot be read. `inngest-bootstrap.sh`
     has stated this precondition in prose since the diagnostic path existed ("This is NOT a cutover
     state: clear INNGEST_DIAGNOSTIC_BOOT before arming") and nothing enforced it. With the flag set
     the host renders an SQLite-only ExecStart with `--sdk-url` on a closed loopback port, so it adopts
     **no** function registry: arming would run the FSM to `done`, quiesce the web scheduler and
     complete the cutover onto a host that serves nothing — reporting success while production crons
     stop. **Remediation:** clear `INNGEST_DIAGNOSTIC_BOOT` on `soleur-inngest/prd`, **then replace the
     host** (`apply_target=inngest-host-replace`) so it re-renders its ExecStart, then re-run
     `op=arm`. No SSH.

     > **Corrected 2026-08-25 (#7674).** This step previously read "clear the flag, let the host
     > re-render its ExecStart". That is not performable: `inngest-bootstrap.sh` consumes
     > `INNGEST_DIAGNOSTIC_BOOT` in `runcmd`, at **first boot only**, so clearing the Doppler value
     > changes nothing on a host that is already running — it re-renders on its next boot and not
     > before. An operator following the old wording would clear the flag, wait for a re-render
     > that cannot happen, and re-run `op=arm` into the same refusal. The gate's own `::error::`
     > string carried the same false instruction and was corrected in the same change.
   - **G3.7 pre-flush-latch gate (#7462):** refuses to arm — **before any prod write** — when the
     dedicated host's Better Stack log source carries a `"reason":"flip-complete"` or
     `"reason":"refuse-rearm-after-done"` row inside `FLUSH_LATCH_SINCE` (default `365d`), i.e. when a
     `FLUSHALL` has already been performed for this host. Such an arm was always doomed: the monotonic
     latch on `/mnt/data` refuses it on-host and drives the flag to terminal `aborted`. What the gate
     removes is the damage done on the way there — G4 wrote both prod secrets and G5 parked
     `INNGEST_CUTOVER_FLIP` at `armed`, a value **inside** the flip guard's prod-start allowlist, so a
     reboot in that ~30-60s window would start a SECOND prod scheduler. Fails closed if Better Stack
     cannot be read (G6 confirms over the same path, so an unconfirmable arm is refused rather than
     dispatched), and — since the 2026-09-24 generation scope — if the Hetzner API cannot name the
     current `soleur-inngest` server, because its liveness signal counts only that server's rows
     (the latch count stays unscoped: a predecessor's `flip-complete` is still valid evidence). It is a **pre-filter, not the authority** — the on-host latch is what actually
     prevents a second `FLUSHALL`, and this gate can only ever ADD a refusal.
     **Remediation:** the only path is the authorized flush `op=reflush` (#7777); `op=resume` is not it
     (its G1 accepts `done` only). `op=reflush` appends a `cleared_at` record to the latch ledger — never by SSH, and **not** by an `inngest-host-replace`.
     (The recut route this line used to name, `apply_target=inngest-volume-recut`, was retired by #8285;
     see the ADR-199 addendum of 2026-10-14.)

     > **Corrected 2026-08-25 (#7674).** This previously said the recut happens "via the
     > `inngest-host-replace` maintenance window". It does not. A replace destroys and recreates the
     > SERVER and **re-attaches the same `hcloud_volume`**; `/mnt/data` and the latch file on it
     > survive intact. Measured: volume `106261946` was created 2026-07-07 and is attached to a host
     > created 2026-08-20 — six weeks later, across a replace, latch preserved. Nor does
     > `op=verify-wiped-volume` help: it wipes `/var/lib/inngest`, not `/mnt/data`.
     >
     > ~~There is **no `apply_target` that recuts `/mnt/data` today.**~~ *(superseded 2026-09-18 —
     > see the Post-cutover status callout below)* The design for one
     > (`inngest-volume-recut`, five guard layers, required-reviewer environment, typed confirm) is
     > recorded in the #7674 plan and tracked for the PR that opens the cutover window. Until it is
     > built, a standing latch has no in-repo remediation, and pretending otherwise is what left
     > this gate's operator-facing message pointing at a window that could not clear it. If that recut has ALREADY happened but
     > the old rows have not aged out, set the repo variable `FLUSH_LATCH_SINCE` to a window starting
     > after it (e.g. `1h`) and re-dispatch; that narrows this pre-filter only.

     > **Post-cutover status (2026-09-18, #7695).** The recut target now exists:
     > `apply_target=inngest-volume-recut` merged 2026-09-04 (PR #7778), dispatch-only, behind the
     > `inngest-cutover` required-reviewer environment. It is NOT a route from this host. On
     > `INNGEST_CUTOVER_FLIP=done` (Doppler `soleur-inngest/prd`, the authority G19 reads; the row's
     > `cutover_flag` mirrors it) its Guard 2 is unreachable on G19 alone (the flag set is
     > `{rolled-back, aborted}`), and G8/G9/G13 refuse independently on the live row —
     > `server_active=active`, `http_code=200`, `redis_keys=1261` (ADR-199: a populated store on a
     > serving host is never recut; G8's `== inactive` form is #8078). As of 2026-09-18 the same
     > volume `106261946` is attached to host `166317708` (created 2026-09-17; the ninth dedicated
     > host since 2026-09-04, re-attached across eight replaces — measured from the probe rows'
     > `instance_id`; Hetzner API `GET /v1/volumes/106261946` → `.volume.server`) with the latch
     > intact. The durable latch STANDS since `op=arm` run 34948112813 (`gh run view 34948112813`,
     > 2026-09-15, on host `165451537`) and survived both 2026-09-17 replaces (onto `166305436`,
     > then `166317708`): `flush_latched=true` with `cutover_flag=done` is the steady state of a
     > healthy `done` host, not a fault to clear. (The 2026-08-25 callout's "latch preserved"
     > describes the file's LOCATION surviving a replace; the row of 2026-09-09, boot `906c015b`,
     > read `flush_latched=false`, so the standing record dates from this arm.) A second `op=arm` is
     > refused by design.
     > Re-measure every row value above with
     > `doppler run -p soleur -c prd_terraform -- scripts/inngest-host-state.sh` (the Better Stack
     > probe row; § Reading host state without SSH).
     > The routes from here are `op=resume` for a stalled or inherited `done` (§ Inherited `done`;
     > it is still not a latch remediation) and the P1-13 rollback (§ Rollback sequence; behind the
     > `inngest-cutover` environment; only when the dedicated scheduler must be stopped) — and on
     > this volume a rollback is one-way: after `rolled-back`, `op=arm` G1 admits the flag, G3.7
     > refuses BEFORE any write (the flag stays `rolled-back`), and if that pre-filter is narrowed
     > the on-host latch refuses into terminal `aborted` (#7777). The `FLUSH_LATCH_SINCE` narrowing
     > above has no application here — no recut has happened and the latch rows are genuine. The
     > latch's real precondition is a measured-empty store, which this volume cannot reach without
     > #7777; the plaintext posture is #6894's (ADR-142, additive), and the target's fate — dormant
     > on this volume, retire-or-keep undecided — is decided on #8316.
     >
     > **Update (2026-10-08, #8285, PR A).** Appended; nothing above is changed. The
     > `apply_target=inngest-volume-recut` dispatch no longer exists once PR A of #8285 has merged: its job
     > is converted into `inngest_backstop_retire` (`apply_target=inngest-backstop-retire`), which retires
     > the plaintext backstop volume `106261946` and does not recut a store. So the "recut" remediation
     > named above has no dispatch to run, and a standing flush latch has no in-repo remediation dispatch
     > (the dark-gate library `tests/scripts/lib/inngest-host-dark-gate.sh` is kept, because
     > `scripts/cutover-inngest.sh` still uses it). The procedure is in
     > `inngest-luks-cutover-6894.md` §5b. The convergence PR of #8285 deletes the retire job itself.
     >
     > **Update (2026-10-09, #8285, PR B).** Appended; nothing above is changed. The retire job and its
     > dispatch inputs are deleted: the backstop volume `106261946` was destroyed on 2026-10-09 (Hetzner
     > `GET /v1/volumes/106261946 -> 404` at 16:21:26Z), so there is no dispatch left that touches it. The
     > dark-gate library stays for `scripts/cutover-inngest.sh`. See `inngest-luks-cutover-6894.md` §5b for the
     > record of the retirement.
     >
     > **Update (2026-10-14, #8316).** Appended; nothing above is changed. The dark-gate entry point
     > `inngest_host_dark_gate` (the recut dispatch's "Guard 2") is retired: it and its one private helper were
     > deleted from `tests/scripts/lib/inngest-host-dark-gate.sh`, which stays for `scripts/cutover-inngest.sh`
     > (`inngest_execute_registry_gate` only). So the "recut" remediation named in the latch-refusal text above
     > has neither a dispatch nor a gate; the latch yields only to the authorized flush `op=reflush` (#7777). The
     > retired code is recoverable at `b6d745fe78`, and the decision is recorded in the ADR-199 addendum of
     > 2026-10-14. #8316 stays open for the operator to close.

   - **G4/G5 writes:** `INNGEST_POSTGRES_URI` → `INNGEST_HEARTBEAT_URL` → `INNGEST_CUTOVER_FLIP`
     set to `armed` (last), each via **stdin** (never argv), exit-gated. The enabled 30s poll
     timer then drives the forward FSM **stop → `FLUSHALL` → assert `DBSIZE==0` → start → `done`**.
   - **G6 confirm:** polls Better Stack for the `logger -t inngest-cutover-flip` line, time-bounded
     to the arm moment (so a stale prior terminal line cannot false-succeed), requiring `"flag":"done"`
     / `"exit_code":0` (the FSM state lives in the `flag` field; `reason` is a cause string like
     `flip-complete`); it FAILS LOUD on `aborted`/`rolled-back`/timeout (**do NOT proceed to 2.4**
     in that case — see aborted-state recovery below).

   > **No operator secret-seed (#6369 / ADR-100 Decision 6b).** The prod `INNGEST_POSTGRES_URI`
   > already lives in `prd_terraform` (canonical, `:5432`). It is NOT distinct from the value in
   > `soleur-inngest/prd` — measured 2026-08-20 they are byte-identical (sha256 `7968f3d658c2`),
   > which is the documented post-first-arm steady state, not drift. So op=arm
   > reads it **read-through** — there is **no `INNGEST_POSTGRES_URI_PROD` seed and no pre-window
   > human write**. The only new credential is the TF-provisioned read/write token
   > (`doppler_service_token.inngest_arm_write`) published as the `inngest-cutover` **environment**
   > secret `DOPPLER_TOKEN_INNGEST_ARM` (required-reviewer gated).

3. **Independent confirm / troubleshooting (optional — op=arm already gates on this).** op=arm
   only exits 0 after Better Stack shows the FSM `done`. To re-read the line yourself
   (`hr-no-dashboard-eyeball-pull-data-yourself`), or if op=arm failed loud at G6:

   ```bash
   doppler run -p soleur -c prd_terraform -- \
     scripts/betterstack-query.sh --since 30m --grep inngest-cutover-flip --raw-only --limit 20
   ```

   A clean flip surfaces a `"flag":"done"` line (with `"reason":"flip-complete"`) within a single 30s poll of arming. A
   `"reason":"dbsize-nonzero"` line means the DBSIZE gate tripped; a `"reason":"unexpected-exit(...)"`
   line means a flag-write/systemctl failure drove the flag to terminal `aborted` (the ERR-trap
   loud-fail) → either way see **aborted-state recovery** below. Do **NOT** `ssh`/`cat` the
   deny-all-public host to read state — `cat-inngest-cutover-state.sh` exists on-host as a **debug
   aid only**, never the operator gate. (These tags are on the `vector.toml` Source 4 allowlist —
   see the `vector-pii-scrub.test.sh` drift-guard — so they are guaranteed to ship off-box.)

3b. **Post-cutover: revoke the arm-write token (#6369, security F4/D6 — after AC17).** Once
   `op=verify` confirms exactly-once on the dedicated host, `DOPPLER_TOKEN_INNGEST_ARM` is a
   **standing read+write handle to the now-armed prod `INNGEST_POSTGRES_URI`** on
   `soleur-inngest/prd`. Rotate + revoke it (no-SSH); there is **no seed to delete** (reads are
   read-through):

   ```bash
   # (a) mint a fresh key + orphan the old one (propagates to the env secret in the same apply):
   doppler run -p soleur -c prd_terraform --name-transformer tf-var -- \
     terraform -chdir=apps/web-platform/infra apply -replace=doppler_service_token.inngest_arm_write
   # (b) confirm the orphaned key is revoked so no standing prod-DSN read handle survives:
   doppler configs tokens revoke --project soleur-inngest --config prd --slug <slug>
   ```

   `-replace` in (a) destroys the old `doppler_service_token`, which already revokes its slug, so
   (b) is a confirmation, not the revocation itself. Its own flags on CLI v3.75.3 are `--project`,
   `--config` and `--slug`; an earlier version of this step also passed `--yes`, which the CLI
   rejected (#6921).

   The next per-merge apply keeps a fresh `inngest-cutover` env secret available for a future
   cutover; the required-reviewer gate means it cannot be used without an approved dispatch.

4. **App-repoint (2.4).** Merge the `INNGEST_BASE_URL` → `http://10.0.1.40:8288` change — all four
   places: `ci-deploy.sh` canary + prod sites, `cloud-init.yml`, and the watchdog's
   `INNGEST_HOST_FALLBACK` (parity-pinned; #8191) — and redeploy the web app so the functions re-sync
   (register) onto the dedicated host. `op=rearm`/`op=verify` precondition-check that this
   landed (registry-non-empty).

   **Clear the window flag in the same redeploy.** Immediately before merging, clear
   `INNGEST_CUTOVER_QUIESCE` so the 2.4 redeploy starts the container without it (a clear with no
   redeploy changes nothing). Confirm with the window-step (c) probe — `400`, not `503` — before
   `op=rearm`:

   ```bash
   doppler secrets set INNGEST_CUTOVER_QUIESCE= -p soleur -c prd --no-interactive > /dev/null
   ```

   > **Channel-key reconcile (#6178 durability — do this as part of 2.4, NOT deferred).** The
   > app and the dedicated host must share the SAME `INNGEST_EVENT_KEY` + `INNGEST_SIGNING_KEY`
   > (they are a shared app↔host **channel** auth token, ADR-100 §4 Amendment — the isolation
   > that stays separate is `INNGEST_POSTGRES_URI` + `SUPABASE_SERVICE_ROLE`, never these). The
   > #6178 cutover repointed the app to the host but never reconciled the keys, so every
   > app→host `inngest.send()` was rejected → **HTTP 502** (`op=rearm` failed). `op=arm`'s **G3.5
   > parity HARD GATE** now blocks the flip if they diverge — so reconcile happens BEFORE `op=arm`
   > passes, but the invariant belongs to this app-repoint step: the app must adopt the host's key.
   >
   > **Because `soleur/prd`'s `INNGEST_EVENT_KEY`/`INNGEST_SIGNING_KEY` carry
   > `lifecycle.ignore_changes = [value]` (inngest.tf), a naive `terraform apply` does NOT
   > propagate a host-key change** — reconcile is the Doppler copy the `ignore_changes` lifecycle
   > explicitly supports (or a `-replace` of the host `random_id` + copy), then a **web redeploy**
   > (ci-deploy regenerates the env each deploy, so the app only bakes the new key on the next
   > deploy). No secret value is echoed — read on the arm token, pipe on stdin:
>
   > ```bash
   > # Copy each host channel key INTO soleur/prd (value on STDIN, never argv/log):
   > for K in INNGEST_EVENT_KEY INNGEST_SIGNING_KEY; do
   >   DOPPLER_TOKEN="$DOPPLER_TOKEN_INNGEST_ARM" doppler secrets get "$K" -p soleur-inngest -c prd --plain \
   >     | doppler secrets set "$K" -p soleur -c prd --silent --no-interactive   # DOPPLER_TOKEN_WRITE cannot reach prd root; use a prd-root write token / Doppler console
   > done
   > # then redeploy web-platform so the app adopts the shared keys, and re-run op=arm (G3.5 now MATCHes).
   > ```
>
   > (`DOPPLER_TOKEN_WRITE` is scoped to `soleur/prd_terraform` and cannot write the `prd` root
   > config the app reads; the copy is a `prd`-root write — Doppler console or a prd-root r/w token.
   > A future full automation would mint a narrow prd-root write token; the G3.5 gate is the
   > recurrence-prevention that makes the divergence impossible to ship silently.)

5. **`op=rearm`** (re-arm the captured reminders after the flip):

   ```bash
   gh workflow run cutover-inngest.yml --field op=rearm
   ```

   It precondition-checks 2.4 (registry non-empty), consumes the on-host capture, and
   reconciles `Σcaptured`; a delta **fails loud** with the missing `reminder_id`s and offers a retry
   (in-window ticks are not auto-backfilled).

   **Before dispatching:** the 2.4 redeploy must have cleared `INNGEST_CUTOVER_QUIESCE` (window step
   (c)). `op=rearm` POSTs every record to the same `schedule-reminder` route, which answers `503`
   while the flag is live. Re-run the window-step (c) probe: it must answer `400`, not `503`.

   **Marker checks.** When a quiesce marker exists, the re-arm first requires the capture's sha256 to
   equal the marker's `capture_sha256` (else `stale_capture`, capture kept) and refuses a replay
   once the marker carries `capture_consumed_at` (`already re-armed`). Remedy for both, as in 2.1:
   `op=rollback` if scheduling must reopen.

   **Held back.** A record whose `fire_at` is at or before the cutoff came due while the web
   scheduler was still running, so it already fired there. The cutoff is the marker's `epoch`, or the
   unit's `InactiveEnterTimestamp` when that is later and the host has not rebooted since the marker
   was written (same `boot_id`). After a reboot the timestamp is gone and the cutoff falls back to
   the marker's `epoch`. So when a run ends with `F > 0` and the host reboots before the retry,
   reminders due in the few seconds between the marker write and the stop can be re-armed and fire
   twice. Retry before rebooting. It is NOT re-sent; it is counted as
   `held_back` and its ids are printed on stderr
   (`inngest-rearm-reminders: held back <n> reminder(s) due before the quiesce: <ids>`). The
   canonical final line is:

   ```text
   inngest-rearm-reminders: re-armed=N failed=F held_back=H total=K
   ```

   `N + F + H == K`, and `K` must equal `Σcaptured`. An empty capture prints
   `re-armed=0 failed=0 held_back=0 total=0`. On full success (`F == 0`) the capture file is deleted
   and the marker is rewritten with `capture_consumed_at`, so a second `op=rearm` refuses instead of
   re-sending.

   **Two different `503`s.** The route tags each with `X-Soleur-Unavailable`, and the re-arm aborts
   on the first one with the capture retained:

   | Header | Meaning | Remedy |
   |---|---|---|
   | `backend-refused` | the app's Inngest backend is not accepting connections — the 2.4 `INNGEST_BASE_URL` repoint has not deployed, or the dedicated host is restarting | wait for the 2.4 redeploy (or the host) to serve, then re-run `op=rearm` |
   | `cutover-quiesce` (or no header) | `INNGEST_CUTOVER_QUIESCE` is still live in the running container | clear it in Doppler `soleur/prd`, redeploy web-platform, confirm the probe answers `400`, re-run `op=rearm` |

   **A retry re-sends every record that was not held back**, including ones the failed run already
   re-armed. Inngest dedups on the event `id` (the `reminder_id`) per function for 24 h, so a retry
   within 24 h of the first run against the same backend is absorbed. A retry more than 24 h later is
   NOT deduped and can arm those reminders twice. No op reads the dedicated host's pending reminders
   today (`op=enumerate` reads web-1's loopback), so past 24 h do not retry blind: file an issue with
   both run URLs and the `failed` ids from the first run's log.

   **A reminder whose `fire_at` fell inside the window FIRES LATE — it runs immediately on
   re-arm — and is never dropped.** The re-arm sends the event with its original, now-past `ts`.
   Inngest schedules at `max(now, ts)` (`inngest/inngest@v1.19.4`,
   `pkg/execution/executor/executor.go`: `if evtTs.After(at) { at = evtTs }`), and the only `ts`
   rejection is outside 1980–2100 (`pkg/event/event.go` `Validate`); both retrieved 2026-09-14.
   Residual: a record due after the marker's `epoch` but before the stop completed (≤ 180 s) may
   have fired on web-1 AND is re-sent, and the dedicated host holds no dedup key from web-1, so it
   can fire twice (ADR-100, amendment 2026-09-14).

6. **`op=verify`** (exactly-once):

   ```bash
   gh workflow run cutover-inngest.yml --field op=verify --field cron_period_seconds=1200
   ```

   > **`cron_period_seconds=1200` was required while `cron-ghcr-token-minter` ran `*/20 * * * *`**
   > (the 3600 default collapsed three legitimate runs into one bucket and reported a phantom
   > double-fire). That minter was deleted by #8714 (ADR-096 task 5.4); before relying on the 3600
   > default again, confirm no `cron-manifest.ts` entry is scheduled more often than hourly.
   It reaches the dedicated GQL over the private net via `/hooks/inngest-doublefire-probe`
   (P1-12 — the runner cannot curl `10.0.1.40` directly), buckets every run by
   `(functionID, floor(startedAt / cron_period))`, and fails if any bucket has >1 run
   (double-fire). By default it then prints one `missed-tick candidates NOT EMITTED` notice
   pointing to [§ Bounded-outage note](#bounded-outage-note), which is the only recovery path for
   a tick skipped in the quiesce→register gap (P2-16, #6939). Dispatching with
   `missed_tick_candidates=true` adds UNVERIFIED `candidate function_id=… empty_bucket_start=…`
   lines. They are **not** a re-fire list: a line can be an event-driven function or a bucket a
   slower cron was never due in, and re-firing one double-fires that cron.
   To get them: `gh workflow run cutover-inngest.yml -f op=verify -f cron_period_seconds=1200 -f missed_tick_candidates=true`.

   > **`op=verify` caveats — read before trusting the verdict:**
   > - **Reads only the dedicated host (P2-a).** The doublefire-probe reads **only the dedicated
   >   host's** (`10.0.1.40`) run history, so a scheduler on a web host would be invisible to it.
   >   The web-1 scheduler is covered by the 2.2 gate (quiesced shape); web-2 runs no scheduler
   >   (step 1a). The earlier "mandatory web-2 quiesce" control named here belonged to the fsn1
   >   web-2 destroyed in #6538.
   > - **Single global `CRON_PERIOD` (P2-c).** One `CUTOVER_CRON_PERIOD_SECONDS` (default 3600)
   >   buckets **every** function. The exactly-once verdict is sound **only if every registered
   >   cron period ≥ `CRON_PERIOD` and hour-aligned**; a cron firing faster than the period yields
   >   >1 run/bucket (false-positive, blocks verify — safe) or a boundary-straddling double-fire
   >   reads clean (false-negative — unsafe). If any cron is sub-hourly, re-run with
   >   `CUTOVER_CRON_PERIOD_SECONDS` set to the **shortest** registered cron period.
   > - **Non-empty registry ≠ fully synced (P3-c).** The precondition only proves the re-sync
   >   **started**. Set `CUTOVER_REGISTRY_BASELINE` to the pre-cutover `op=inventory` `functions`
   >   count so `op=rearm`/`op=verify` enforce `function_count ≥ baseline` (a half-sync otherwise
   >   passes); without it, confirm the count matches the pre-cutover inventory manually.

   #### Scan window + trust anchor (#6178, ADR-146)

   There are **two** windows, and they are deliberately different:

   | Arm | Window | `anchor_source` |
   |---|---|---|
   | `op=verify` (2.6) | `min( bucket_floor(anchor) − 2×cron_period , now − 1d )`, open-topped | `fsm` \| `var` \| `floor` |
   | `op=doublefire-probe` (pre-cutover dark-host detector) | `now − 200d`, open-topped | `wide` |

   The anchor is resolved in order: the **on-host flip-FSM transition row** (`fsm` — read from
   Better Stack, stamped on `10.0.1.40`'s journald, the *same clock* that stamps `startedAt`),
   then the `CUTOVER_WINDOW_FROM` repo variable (`var`), then **fail closed**. There is no wide
   fallback: at ~728 runs/day a 7-day window is ~5,100 runs ≈ 214 s and cannot be exhausted, and
   the probe emits nothing on a non-exhausted scan — so scanning it would only *look* safer.

   **Reading a verdict — check `anchor_source` before believing it.** Every dispatch logs
   `anchor_source=` alongside `from=`, and the probe's markers carry `total_count=`. A clean
   verdict is only meaningful over a window that actually covered the coexistence region:

   - `anchor_source=fsm` — strongest. Anchor and run timestamps share a clock.
   - `anchor_source=floor(fsm)` — an fsm anchor WAS derivable, and the 1-day floor was the earlier
     (wider) bound, so it won the `min()`. This is the normal shape within ~24 h of the cutover.
     Confirm the floor covers the quiesce instant before trusting a clean result.
   - `anchor_source=var` / `floor(var)` — no transition row was derivable; the window rests on an
     operator-typed value on a *different* clock. Confirm it covers the quiesce instant.
   - `anchor_source=override` / `floor(override)` — you set `CUTOVER_ANCHOR_FROM`, so the window was
     deliberately NARROWED and may not cover the whole coexistence region. `op=verify` reports
     `exactly-once VERIFIED (QUALIFIED)` here; it is **not** a full exactly-once proof.
   - `anchor_source=wide` — the pre-cutover `op=doublefire-probe` arm only. Never `op=verify`.
   - `total_count=0` with a clean verdict — **vacuous**, and since #6178 `op=verify` HARD-FAILS on
     it rather than reporting a verdict. If you see one, the gate was bypassed; do not close #6178.

   **If the run aborts with `reason=window_too_wide`**, the message names a *computed* latest-viable
   anchor. Set `CUTOVER_ANCHOR_FROM` — **not** `CUTOVER_WINDOW_FROM`, which is consulted only when
   no anchor is derivable and is therefore inert whenever the flip-FSM row resolves — and
   re-dispatch. Narrowing produces a **window-limited** verdict, which `op=verify` labels
   `exactly-once VERIFIED (QUALIFIED)`; to keep the full window instead, scope the population via
   `CUTOVER_DOUBLEFIRE_FUNCTION_IDS` (but confirm the scope still contains the destructive crons —
   `cron-workspace-gc`, `cron-rule-prune`, `cron-action-required-sla`):

   ```bash
   gh variable set CUTOVER_ANCHOR_FROM --body '<the ISO instant from the abort message>'
   gh workflow run cutover-inngest.yml --field op=verify --field cron_period_seconds=1200
   ```

   Do **not** reach for `PREFLIGHT_DEADLINE_S` — the SUM bound `DEADLINE + PAGE_MIN ≤ outer_curl`
   caps it at 112 s (~14 pages), which is why that remediation was removed. The live lever is the
   window.

   **Query the markers off-box** (no SSH):

   ```bash
   doppler run -p soleur -c prd_terraform -- bash scripts/betterstack-query.sh \
     --since 1h --grep SOLEUR_INNGEST_PREFLIGHT --limit 20
   ```

   `total_count` + `anchor_source` are the discriminating fields: they separate "window too wide"
   (large measured `total_count`, or `reason=window_too_wide`) from "budget too small" (small
   `total_count` that still hit `reason=deadline`) from "anchored on the wrong instant"
   (`anchor_source` weaker than `fsm`). `total_count=unknown` means page 1 never parsed — the scan
   never learned its own scale.

   **Anchor retention bound.** `_flip_transition_dt` queries the last **30 days**
   (`FSM_ANCHOR_SINCE` in `cutover-inngest.yml`). That literal — not vendor retention — is the hard
   limit on how long after a cutover an `fsm` anchor can be derived at all. Past it, `op=verify`
   degrades to `var` and then fails closed. It is deliberately a named variable so the bound is
   greppable rather than implicit.

### 2.0 registry-non-empty remediation (P1-6)

If `op=execute` aborts at 2.0 with `::error::2.0 ABORT — dark registry is NON-empty` — or, **while
the cutover flag is still pre-arm** (`INNGEST_CUTOVER_FLIP` not `done`), a standalone
`op=registry-probe` prints `registry_empty=false` with the `REGISTERED function(s)` warning (#8079;
same hook, same reading, no window needed) — the dark host has functions registered against it —
flipping now would carry stray state onto prod Postgres. **This section is pre-arm only.** After
step 2.4 the dedicated host owns production scheduling and `registry_empty=false` with ~70 functions
is the HEALTHY reading (ADR-100 addendum 2026-09-15); following the steps below then would replace
the production scheduler host. To empty a pre-arm dark registry and re-run (all no-SSH):

1. Read `INNGEST_POSTGRES_URI` on `soleur-inngest/prd` and record which backend it targets.
   **Do NOT assert it should still be non-prod** — that instruction was correct only before the
   first successful arm. `op=arm` writes the prod DSN and `op=rollback` has no inverse for that
   write, so since 2026-07-23 the slot holds the prod value as its documented steady state
   (ADR-100, addendum 2026-08-20). Following the superseded wording literally would lead to
   hand-writing the soleur-dev DSN back into a guarded secret, which is explicitly not the fix.
2. Stop whatever dev/test backend is re-syncing functions into the dark server (typically a
   stray `--sdk-url` pointing at the dark host), so nothing re-registers after you clear it.
3. Clear the dark registry (re-provision the dark host via the
   `apply_target=inngest-host-replace` dispatch, which force-replaces onto the empty dark
   backend), then re-dispatch `op=execute`. The 2.0 probe must report `registry_empty:true`
   before the SEAM is reachable.

### 2.1 capture `HTTP 500: INNGEST_MANUAL_TRIGGER_SECRET unavailable` triage

The web host's `inngest-rearm-reminders.sh` reads the Bearer secret from Doppler, re-reading the
re-delivered credential in `/etc/default/soleur-doppler-token` first (#7095 class; the unit's own
`DOPPLER_TOKEN` was revoked 2026-07-30). On a failed read it emits ONE classified line to journald
and to the hook's response body — the `::error::2.1 capture returned HTTP 500: …` text in the run log
already carries it — so no SSH is needed:

```bash
doppler run -p soleur -c prd_terraform -- bash scripts/betterstack-query.sh --since 1h --grep SOLEUR_DEPLOY_CRED_FAIL
```

Decode `class=` / `token_file=` from that line (layer: Better Stack via Vector's journald source,
tags `inngest-rearm-reminders` / `inngest-wiped-volume-verify`; the same event reaches Sentry as
`op=doppler-read-failed` when the file's three DSN components were read):

| line | meaning | fix (no SSH) |
|---|---|---|
| `token_file=absent` | `terraform apply` never delivered `/etc/default/soleur-doppler-token` | dispatch `apply-web-platform-infra.yml`; confirm via `/hooks/deploy-status` (`cat-deploy-state.sh` reports the cred-file state) |
| `token_file=unreadable` | mode/group drift from `install -m 640 -o root -g deploy` | re-deliver via the same apply (the installer rewrites mode+owner) |
| `token_file=present class=invalid_auth` | the FILE's token is itself revoked — delivery is stale | mint a new `TF_VAR_doppler_token` and apply; the file is re-rendered |
| `token_file=present token_applied=0` | the file was read but its `DOPPLER_TOKEN` line is not shape-valid (quoted value, an `export`-prefixed line, empty) — the unit's revoked export was used | re-render the file via the same apply; a hand-edited file must carry a bare `DOPPLER_TOKEN=dp.<family>.<body>` line |
| `class=secret_not_found` | `INNGEST_MANUAL_TRIGGER_SECRET` missing in `soleur/prd` | provision the secret (inngest.tf owns it) |
| `class=transport` | the web host cannot reach `api.doppler.com` | egress/DNS on the web host — see the cron-egress runbook |
| `class=empty_value` | the secret exists but is empty | set a value in Doppler |
| `class=binary_absent` | `doppler` is not on the webhook unit's PATH | host-image defect; re-provision |

### nftables web-host allowlist parity (#6608)

`inngest-host.tf` `local.web_host_private_ips` is rendered into the dedicated host's nftables
`ip saddr { … }` allowlist for the `:8288`/`:8289` control API (SEC-H2). It must equal the live
web-host roster (`var.web_hosts` `private_ip` set). web-2 (`.11`) was retired 2026-07-17 (#6538),
so the roster is web-1 (`10.0.1.10`) only; the literal was corrected to match (#6608) and is now
**drift-guarded** by `inngest-host.test.sh` §6b (the allowlist IP set must byte-equal the
`var.web_hosts` private_ip set — the edge to `var.web_hosts` the roster previously lacked, so a
future roster change red-lines CI until the allowlist follows).
*(Superseding note, 2026-09-14: the roster has two keys again — a cattle web-2 was born at `.11`
on 2026-07-27, #6969 — and the literal in `inngest-host.tf` is `10.0.1.10,10.0.1.11`. The §6b
guard is what keeps the two equal.)*

**Apply path — the literal is baked into `user_data`, so the edit force-replaces the host.**
`hcloud_server.inngest` deliberately carries **no** `lifecycle.ignore_changes=[user_data]`
(ADR-100), and its resources are **excluded from the per-PR CI `-target`**, so the corrected
literal is **inert at merge** — nothing applies. Deliver it by folding into the HELD Phase-2
cutover re-provision (the same `apply_target=inngest-host-replace` dispatch above that delivers the
#6197 arm64-Vector wiring), which is scoped, AOF-volume-preserving, and menu-ack authorized. Do
**not** fire a separate gratuitous replace: during Phase-1 the host is dark/inert (zero prod crons),
so there is no urgency unless a read-only check shows `10.0.1.11` reallocated to a live host before
Phase-2.

**Post-apply verification (no-SSH).** Confirm the rendered nftables set no longer contains `.11`
and the `:8288`/`:8289` control API still accepts from web-1 (`10.0.1.10`) via the Vector
journald→Better Stack boot marker / registry-probe class check — never `ssh` (the host is
deny-all-public; `hr-no-ssh-fallback-in-runbooks`). Then `gh issue close 6608`.

### Rollback sequence (P1-13) — mirrors the forward gate, stop the dedicated host FIRST

> **One-way on volume `106261946` (2026-09-18, #7695):** a re-arm after `rolled-back` is refused while the
> durable flush latch stands — read the G3.7 "Post-cutover status" callout under § Dedicated-host cutover
> before dispatching.

1. **Dispatch `op=rollback` (no-SSH — it now does BOTH halves, #6369).** As of #6369 `op=rollback`
   first writes `INNGEST_CUTOVER_FLIP=rollback` on `soleur-inngest/prd` itself (the still-enabled
   timer then stops `inngest-server` on its next poll), confirms `"flag":"rolled-back"` /
   `"exit_code":0` via Better Stack (time-bounded), and THEN runs the web re-enable fan-out
   (step 3 below) **only after that confirm** — so the dedicated scheduler is proven stopped before
   the web schedulers come back (no two-live-scheduler double-fire; on an unconfirmed rolled-back it
   fails loud and withholds the web re-enable). Half (A) writes `rollback` when the forward flip is
   armed or progressing (`armed`/`flipping`/`flushed`/`done`), behind the same `inngest-cutover`
   environment required-reviewer gate; it writes ONLY the flip value (never re-writes
   POSTGRES_URI/HEARTBEAT). For a non-forward state (`aborted`/`unset`) there is nothing to reverse
   and it proceeds straight to the web re-enable (the documented aborted-state / P0-3 recovery):

   ```bash
   gh workflow run cutover-inngest.yml --field op=rollback   # then APPROVE the inngest-cutover environment gate
   ```

   There is **no separate operator Doppler write** — the dedicated-host stop is now folded into
   this single dispatch.
2. **Repoint the app back to the co-located scheduler** — `git revert` the 2.4 app-repoint PR
   (#8191) and redeploy. The repoint spans FOUR places, so never hand-edit one: `ci-deploy.sh`
   (canary + prod `docker run`), `cloud-init.yml` (a freshly born web host's first run) and the
   watchdog's `INNGEST_HOST_FALLBACK` (+ its parity test, which reds on a partial revert). The
   target is the Docker host-gateway `http://host.docker.internal:8288`, not a loopback address.
   **Pre-stage the revert PR green BEFORE dispatching step 1**: `op=rollback` stops the dedicated
   host and re-enables web-1 in one dispatch, and until the revert deploys every app
   `inngest.send()` is refused (`X-Soleur-Unavailable: backend-refused`).

<!-- lint-infra-ignore start -->

3. **Re-enable web inngest — Half (B) of the SAME `op=rollback` dispatch from step 1** (it runs
   automatically after the `rolled-back` confirm; no second dispatch needed). `op=rollback` issues
   a SINGLE no-SSH `enable inngest _ _` fan-out (enable + start + verify-serving-and-enabled in ONE
   flock-held ci-deploy.sh handler, #6178) across the `$CUTOVER_HOSTS` set, then POLLS
   `/hooks/deploy-status` for the terminal `reason=enabled` verdict. The `enable` verb restores
   the `[Install]` symlink the 2.2 disable removed (a `restart` never touches it) so the web
   scheduler survives a reboot — **no operator `systemctl` step is needed** (this is the no-SSH
   reverse of `op=quiesce-web`; there is deliberately no two-POST enable+restart, which would
   race the `flock -n` and could leave the unit enabled-but-stopped reported as success).
   Before it enables or starts anything, the handler retires the cutover capture to
   `/var/lib/inngest/cutover-capture.json.retired-<epoch>` and removes the quiesce marker
   `/var/lib/inngest/quiesced-by-op`, logging
   `INNGEST_ENABLE: retired capture=<path|none> marker_removed=<true|false>` (tag `ci-deploy`). A later
   `op=quiesce-web` therefore always takes a fresh capture, and 2.1 can never resume a capture from
   before the rollback. The fan-out to web-2 is acceptance-only (DI-C3) and is NOT a no-op: web-2
   has no `inngest-server.service` (step 1a), so its `enable` fails and writes
   `inngest_enable_failed` to web-2's own deploy-status slot. That is expected and tolerated — the
   rollback reads web-1's verdict and the peer's 202. On web-1's `inngest_enable_failed` / `inngest_start_failed` /
   `inngest_reenable_unverified` / `enabled_peer_fanout_unaccepted`, pull `reason=` from
   `/hooks/deploy-status` + Better Stack (`logger -t ci-deploy`) — do **not** SSH the host.

<!-- lint-infra-ignore end -->

The capture is retired (renamed, not deleted), so its reminder ids stay on-host for an
investigation but can never be resumed. Rollback is data-safe only before any
**real** (non-throwaway) reminder is armed against prod Postgres — after that, forward-fix only.

> **Do NOT target a web host with `restart-inngest-server.yml` after the cutover completes
> (arch P2-4).** Post-cutover the web hosts' inngest is intentionally stopped+disabled
> (10.0.1.40 is the sole scheduler). A routine `restart-inngest-server.yml` restart is
> LB-routed to a web host and would START its disabled unit → a TRANSIENT second scheduler on
> prod Postgres (double-fire), independent of any enable-folding — the `inngest-server`
> `ExecStartPre` flip-guard blocks only the DEDICATED host, not web hosts. The only web verb to
> touch post-cutover is `op=quiesce-web` (forward) / `op=rollback` (reverse), never `restart`.
>
> **Superseding note (2026-09-14, #8077).** The hazard above is now closed in code: `restart`
> refuses a stopped+disabled unit whether or not a quiesce marker attributes it
> (`inngest_quiesced_restart_refused` / `inngest_disabled_unattributed_restart_refused`), and so
> does every other start path except `enable` (see §op=quiesce-web). The instruction stands — never
> use `restart` on a web host post-cutover — but a stray dispatch no longer starts a second
> scheduler. Also, `restart-inngest-server.yml` is not load-balanced: the `deploy.` tunnel ingress
> targets web-1's private IP, so it only ever reaches web-1 (ADR-100, amendment 2026-09-14).

<!-- lint-infra-ignore start -->

> **Editor guard — a "no-SSH cutover" claim must be verified verb-by-verb (#6178).** Any host
> mutation this runbook performs (quiesce/stop/disable, enable/start, a future drain/pause) needs
> its OWN no-SSH webhook verb + pinned sudoers grant — an existing verb for a *different* mutation
> (e.g. `restart`) does NOT make the cutover no-SSH; that asymmetry is exactly what left 2.2
> quiesce on operator SSH. Re-arm uses `enable` (restores the `[Install]` symlink `disable`
> removed), never `restart` (which leaves the unit enabled-at-runtime but dropped on reboot). Before
> claiming no-SSH, list every mutation and confirm each has a verb.

<!-- lint-infra-ignore end -->

### `aborted`-state recovery (P0-3)

If the flip's DBSIZE gate tripped (`"exit_code":1`, `"reason":"dbsize-nonzero"`), the oneshot
refused to start and transitioned the flag to the terminal `aborted` (the 30s poll halts — no
re-attempt storm, and `aborted` never reads as success). The web schedulers are already
quiesced/disabled from `op=execute` 2.2, so **recover via the same rollback path**: run
`gh workflow run cutover-inngest.yml --field op=rollback` to bring the web schedulers back,
fix the Redis state (the non-zero `DBSIZE` means stale dark queue state — investigate why the
dark Redis was not empty), then re-arm from `op=execute`.

> **On volume `106261946` (2026-09-18, #7695):** a re-arm after `rolled-back` is refused — see the G3.7
> "Post-cutover status" callout under § Dedicated-host cutover before choosing this path.

### Heartbeat suppression window (P2-14)

Both pushers (the co-located web scheduler and the dedicated host) are silent across the
window — the web pusher is quiesced at 2.2 and the dedicated host only begins pinging
`INNGEST_HEARTBEAT_URL` **after** the flip. So set a **Better Stack maintenance / suppression
window** on the `soleur-inngest-server-prd` heartbeat spanning the cutover (or rely on the
monitor's grace period) so the pusher-quiesce → post-flip gap does not page. Lift the
suppression once step 3 confirms `done` and the dedicated host is pinging.

### Bounded-outage note

The window between 2.2 (quiesce) and functions registering after 2.4 (app-repoint) is the
parent plan's **accepted bounded residual** (ADR-100: a fully zero-downtime switchover is
impossible under the single-writer constraint — two schedulers on prod Postgres would
double-fire every cron, strictly worse than a brief gap). The flip oneshot restarts inngest
**in place** (pre-installed during dark, so the window is bounded by the restart + app-redeploy,
target < 5 min — NOT a cold OCI pull). **Do not assume a missed tick stays missed:** ADR-100's
2026-09-19 addendum measured the scheduler firing each missed tick exactly once when it resumed
after a 76-minute gap, so a tick skipped in the window may already have been drained on restart.

**Recovering a skipped tick (#6939).** `op=verify` does not print a re-fire list. A per-bucket
list cannot tell a tick that was due from one that was never due, and re-firing a tick that was
never due, or one the scheduler already drained, double-fires that cron. Every step below is
fail-safe: if you cannot complete one, stop at step 1.

1. **Default: do nothing.** A tick skipped in the gap is the accepted residual above, and the
   cron's next scheduled tick runs normally. For a low-frequency cron that next tick can be far
   off (`cron-rule-prune` is quarterly). Monitored crons page on their own: each Sentry monitor in
   `apps/web-platform/infra/sentry/cron-monitors.tf` opens an issue once its
   `failure_issue_threshold` of missed check-ins is reached (1 for most), so a miss that matters
   usually surfaces without this procedure.
2. Re-fire only when a skipped tick matters **and** all four checks hold:
   - (a) **You know the gap window.** It runs from the op=execute 2.2 quiesce to the moment the
     dedicated host's functions registered after 2.4, both timestamped in that op=execute run's
     log (`gh run view <run-id> --log`). `op=verify` echoes `CUTOVER_WINDOW_FROM`/`UNTIL` when they
     are set and ISO-shaped, and `<unset>`/`<invalid>` otherwise; if you cannot state both ends, stop.
   - (b) **The cron was due inside it.** Start from cron names, not the UUIDs `op=verify` can list
     (nothing in the repo maps a UUID to a name): for each entry in `EXPECTED_CRON_FUNCTIONS`
     (`apps/web-platform/server/inngest/cron-manifest.ts`), read the `{ cron: }` trigger in
     `apps/web-platform/server/inngest/functions/cron-<name>.ts` and keep only the crons whose
     schedule put a tick strictly inside the window. A function with no `{ cron: }` trigger is
     event-only and is never missed.
   - (c) **No run has been recorded for that tick since.** Wait until the dedicated host has
     resumed (so any drain has happened), then read the run log, which is the record every cron in
     `EXPECTED_CRON_FUNCTIONS` writes (`routine_id` is the fnId):
     `doppler run -p soleur -c prd -- sh -c 'psql "$DATABASE_URL_POOLER" -Atc "$0"' "select started_at, status, trigger_source from public.routine_runs where routine_id = 'cron-<name>' and started_at >= '<tick>' order by started_at"`
     (the `sh -c` is load-bearing: without it your own shell expands the variable before Doppler
     sets it).
     Any row means the tick ran (or was drained): do not re-fire.
   - (d) **Its Sentry monitor agrees.** The slug is usually `scheduled-<name>` (the
     `SENTRY_MONITOR_SLUG` constant in `cron-<name>.ts`); if that file has no constant, look the
     monitor up by name in `cron-monitors.tf` before concluding there is none. Read the check-ins
     after the tick plus that monitor's `checkin_margin_minutes`, through the API with the
     IaC read token (verified live 2026-09-27; this repo reads Sentry with `SENTRY_IAC_AUTH_TOKEN`):
     `doppler run -p soleur -c prd -- bash -c 'curl -sS --fail-with-body -H "Authorization: Bearer $SENTRY_IAC_AUTH_TOKEN" "https://de.sentry.io/api/0/organizations/jikigai-eu/monitors/<slug>/checkins/?per_page=100"' | jq -r 'if type == "array" then .[] | select(.environment == "production") | "\(.expectedTime) \(.status)" else error("sentry read failed") end'`.
     Require a `missed` row whose `expectedTime` is the tick, and no `ok`, `in_progress` or `error`
     row after it (a finished run whose heartbeat was lost also reads `missed`, which is why step
     (c) comes first). An API
     error, or no monitor at all, means the tick cannot be confirmed as missed: do not re-fire.
3. Only then fire it, the way `soleur:trigger-cron` recommends: confirm the event is allowlisted
   with `--list`, run `--event cron/<name>.manual-trigger --dry-run`, then run it without
   `--dry-run`. Take particular care with the destructive or user-facing crons:
   `cron-workspace-gc`, `cron-rule-prune` and `cron-action-required-sla` (a duplicate SLA
   notification reaches a user).

The opt-in `missed_tick_candidates=true` lines are keyed by function UUID and are an input to step
2(b) at most, never a list to fire. Naming them and filtering them to due ticks is the proper fix,
tracked on #6940. Before dispatching `op=verify` against a newly cut-over dedicated host, check
whether #6940 has landed (ADR-146 § Deferred item 5).

## Concurrency conventions

- **One `terraform apply` at a time.** The R2 backend has `use_lockfile = false` (R2 does not support S3 conditional writes). Concurrent applies race silently. R7 in the plan documents this.
- **`inngest-bootstrap.sh` is idempotent** — second invocation against the same version is a ~50ms no-op via `systemctl is-active` + version-file match. Safe to re-run.

## Cron bug-fixer

The cron-bug-fixer Inngest function (`apps/web-platform/server/inngest/functions/cron-bug-fixer.ts`) runs daily at `0 6 * * *` UTC, selecting a qualifying `type/bug` issue and spawning `claude-code` to fix it. It also accepts a manual-trigger event for operator-initiated runs.

### Event name and payload

- **Event:** `cron/bug-fixer.manual-trigger`
- **Payload:** `{ "issue_number": <positive integer> }` (optional)
- **Validation:** If `issue_number` is present, it must be a positive integer. Invalid values are rejected with a Sentry fallback report and the function returns `ok: false` without selecting any issue.

When `issue_number` is omitted, the function falls through to the priority cascade (see Override semantics).

### Override semantics

- **Without override:** The handler runs the priority cascade, selecting the first qualifying issue in order: `priority/p3-low` → `priority/p2-medium` → `priority/p1-high`. Issues matching the title skip-regex (`/^(\[Content Publisher\]|flaky|flake|test-flake|test)[: [(]/i`) or carrying skip-labels (`bot-fix/attempted`, `ux-audit`, `synthetic-test`) are excluded.
- **With override:** The `issue_number` bypasses the cascade entirely. The operator owns ensuring the target issue is fix-issue-compatible (has `type/bug` label, is open, is not in the skip-list). The handler does not re-validate these constraints on override.

### Concurrency

- **fn-scoped limit 1:** Only one `cron-bug-fixer` invocation runs at a time.
- **account-scoped `cron-platform` limit 1:** Shared across all `cron-*` functions using the `cron-platform` key. A manual trigger queues behind any in-flight cron run (daily-triage, follow-through-monitor, etc.).
- **Retries:** 1 (Inngest retries once on non-terminal failure).

Manual triggers do NOT preempt scheduled runs — they queue behind them.

### How to fire

**HTTP (PRIMARY — no SSH):** POST to the internal trigger route (see
[§ On-demand cron trigger (HTTP)](#on-demand-cron-trigger-http--primary) for the
full Bearer + `data` contract):

```bash
TOKEN=$(doppler secrets get INNGEST_MANUAL_TRIGGER_SECRET -p soleur -c prd --plain)
curl -sS -X POST https://app.soleur.ai/api/internal/trigger-cron \
  -H "Authorization: Bearer $TOKEN" -H 'content-type: application/json' \
  -d '{"event":"cron/bug-fixer.manual-trigger","data":{"issue_number":4383}}'
unset TOKEN
```

Without `issue_number` (runs the default cascade) — omit `data` (or send `{}`):

```bash
  -d '{"event":"cron/bug-fixer.manual-trigger"}'
```

Or via the skill: `plugins/soleur/skills/trigger-cron/scripts/trigger.sh
--event cron/bug-fixer.manual-trigger --data '{"issue_number":4383}'`.

**Last-resort diagnosis (on-host, only if the HTTP route is itself down):** the
Inngest CLI talks to the loopback event endpoint and requires being on the
Hetzner host. Use ONLY when the public route is unreachable:

```bash
# on the Hetzner host (last-resort)
inngest send '{"name":"cron/bug-fixer.manual-trigger","data":{"issue_number":4383}}'
```

**Inngest dashboard:** Navigate to the Events tab → Send Event → paste the JSON body above.

### How to observe results

1. **Sentry cron monitor:** `scheduled-bug-fixer` — shows `ok` / `error` heartbeat status per run.
2. **GitHub PRs:** Filter by `bot-fix/*` branch prefix — `gh pr list --state all -L 200 --search "head:bot-fix/"`.
3. **Inngest dashboard:** Run history for `cron-bug-fixer` shows step-by-step execution (mint-installation-token → precreate-labels → select-issue → setup-workspace → claude-eval → detect-pr → auto-merge-gate → notify-ops-email → sentry-heartbeat).

### Common failure modes

| Mode | Symptom | Resolution |
|------|---------|------------|
| Invalid override | Sentry fallback: "Manual-trigger issue_number must be a positive integer" | Re-send with a valid positive integer |
| Empty cascade | Function returns `ok: true`, `selectedIssue: null` — no qualifying issue at any priority level | Expected when no open `type/bug` issues exist; no action needed |
| claude-eval timeout | Sentry fallback: "claude-eval aborted by timeout (3000000ms budget exceeded)" | The 50-minute AbortController fired; check Anthropic usage for the aborted run |
| Workspace setup failure | Sentry fallback: "Failed to scaffold ephemeral cron workspace" | Check GitHub App installation token minting, repo clone permissions |
| No PR detected | Warning log: "No bot-fix PR detected after claude-eval" | The agent did not produce a PR — review the claude-eval step output in Inngest dashboard |
| Auto-merge gate: non-bot author | Gate returns "author is not a recognized bot" | PR was opened by a human or unrecognized bot account |
| Auto-merge gate: no eligibility label, carries `bot-fix/review-required` | Gate returns "missing bot-fix/auto-merge-eligible label" | Expected, not a defect: fix-issue Phase 5.5 chose review. `triage-prs.sh` puts the PR in the `needs-review` tier (agent review via `soleur:drain-prs`, which runs only when invoked) |
| Auto-merge gate: missing label, carries neither label | Gate returns "missing bot-fix/auto-merge-eligible label" | An agent defect: fix it in fix-issue Phase 5.5, where exactly one of the two labels is applied (not Phase 6, the failure handler). The gate does not add the review label and `triage-prs.sh` has no label branch for this PR, so a PR that is `MERGEABLE` with zero failing checks lands in `ready-green`, **not** `needs-review`; an otherwise-eligible non-green PR falls through to `needs-review`. There is no detector for the missing label, so check the labels when the PR appears |
| Auto-merge gate: multi-file diff | Gate strips eligibility label, adds `bot-fix/review-required` | PR touches >1 file; agent review via the drain-prs `needs-review` tier (runs when `soleur:drain-prs` runs; nothing schedules it) |
| Auto-merge gate: non-p3-low source | Gate strips eligibility label, adds `bot-fix/review-required` | Source issue priority is not `priority/p3-low`; agent review via the drain-prs `needs-review` tier (runs when `soleur:drain-prs` runs; nothing schedules it) |

## Plan deviations from `2026-05-18-feat-pr-f-inngest-iac-plan.md`

See the `## Plan Deviations (Phase 1)` section of the plan for full context. Summary:

1. 4 Inngest secrets are `random_id`-generated, not operator-minted.
2. Single workplace-scope Doppler personal token (was: two per-config service tokens).
3. `[ack]` operator-mint count: 6 → 2.
4. OCI image tag is plain `vX.Y.Z` (not `vinngest-vX.Y.Z`).
5. cloud-init.yml embedding + `server.tf triggers_replace` for `inngest-bootstrap.sh` skipped — OCI image is the sole delivery path.

## PR-G post-merge: Flipping `SOLEUR_FR5_ENABLED` to `true`

Per ADR-033 (per-tenant scope grants), the env flag `SOLEUR_FR5_ENABLED` is no longer a tenant-level gate — it is a global kill-switch. The per-grant deny-by-default predicate at `apps/web-platform/app/api/webhooks/stripe/route.ts:437` is the actual tenant-level authorization gate. **Even with the flag at `true`, no Inngest event fires for a tenant who has not granted the action class via `/dashboard/settings/scope-grants`.** This decoupling is what makes the flip operator-routable in PR-G (#3947).

### Prerequisites (all must be true before flip)

1. **PR-G merged to `main`**; Vercel auto-deploy green; Hetzner web-platform unit has restarted with the new image (or per the deploy substrate's restart policy).
2. **Migrations 048 + 049 applied to prd Supabase.** Verify via `psql` (or Supabase MCP):

   ```bash
   doppler run -p soleur -c prd -- sh -c 'psql "$DATABASE_URL_POOLER" -c "$0"' '\d+ public.scope_grants'
   doppler run -p soleur -c prd -- sh -c 'psql "$DATABASE_URL_POOLER" -c "$0"' '\d public.users' | grep runtime_explainer_dismissed_at
   ```

   Expected shape: 7 columns on `scope_grants`, RLS enabled, 2 WORM triggers (`scope_grants_no_update`, `scope_grants_no_delete`), 1 partial index (`scope_grants_active_idx`), 3 RPCs (`grant_action_class`, `revoke_action_class`, `anonymise_scope_grants`) with explicit `REVOKE EXECUTE FROM PUBLIC, anon` and the correct `GRANT EXECUTE TO` for each role.
3. **T&C version 2.0.0 deployed.** Middleware redirect to `/accept-terms` on next request will fire for the operator + first dogfood founder. Coordinate dogfood timing accordingly.
4. **BetterStack on-call live** (per PR-F flip-prerequisite list at the top of this runbook).
5. **Synthetic Stripe smoke against prd webhook passed** (see § "Synthetic smoke" below) — the smoke runs against a **preview env** with the flag temporarily on, NOT against prd before the prd flip.
6. **CPO sign-off captured** in `knowledge-base/legal/compliance-posture.md` Active Items (PR-G brand-survival threshold: single-user incident).
7. **First dogfood founder selected** and onboarding-ready. Their `scope_grants` row will be granted by them via `/dashboard/settings/scope-grants` after PR merges (no backfill per brainstorm K16).

### Flip command

```bash
doppler secrets set SOLEUR_FR5_ENABLED=true -p soleur -c prd
```

Verify:

```bash
doppler secrets get SOLEUR_FR5_ENABLED -p soleur -c prd --plain
# → true
```

### Roll-back command (if first invocation surfaces a regression)

```bash
doppler secrets set SOLEUR_FR5_ENABLED=false -p soleur -c prd
```

The web container reads this value from the env snapshot taken at container start, so the flip takes effect only after the web containers restart (a redeploy).

Stripe redelivery (up to 3 days) preserves at-least-once if the flip+rollback cycle drops events in flight.

### Synthetic smoke procedure (one-off, no separate script)

Run from a Vercel preview env (NOT prd) before the prd flip. Replace `<founder-uuid>` with a seeded grant's `founder_id`:

```bash
# 1. Seed the grant in the preview env's Supabase (one-time, founder-id-bound).
#    Sign in to /dashboard/settings/scope-grants as the operator's preview account;
#    select finance.payment_failed at draft_one_click; submit. The row lands in
#    public.scope_grants.

# 2. Compose a synthetic Stripe payload.
STRIPE_PAYLOAD=$(jq -nc --arg fid "<founder-uuid>" '{
  type: "invoice.payment_failed",
  data: { object: { customer: "cus_smoke_test", id: "in_smoke_test",
                    customer_email: "smoke@soleur.test",
                    amount_due: 4200, currency: "usd",
                    last_finalization_error: { code: "card_declined" } } }
}')

# 3. Sign with the preview env's webhook secret.
TS=$(date +%s)
PAYLOAD_TO_SIGN="${TS}.${STRIPE_PAYLOAD}"
SIG_HEX=$(printf '%s' "$PAYLOAD_TO_SIGN" \
  | HMAC_KEY="$STRIPE_WEBHOOK_SECRET" python3 -I -c 'import hashlib,hmac,os,sys;k=os.environb.get(b"HMAC_KEY");k or sys.exit(1);sys.stdout.write(hmac.new(k,sys.stdin.buffer.read(),hashlib.sha256).hexdigest())')
SIG_HEADER="t=${TS},v1=${SIG_HEX}"

# 4. POST to the preview webhook endpoint.
curl -sS -X POST "https://<preview-domain>/api/webhooks/stripe" \
  -H "Stripe-Signature: $SIG_HEADER" \
  -H "Content-Type: application/json" \
  -d "$STRIPE_PAYLOAD"
# Expected: HTTP 200; webhook returns {"received": true}.

# 5. Wait ~5s, then query Inngest via the loopback API.
doppler run -p soleur -c <preview-config> -- bash -c '
  curl -sS -H "Authorization: Bearer $INNGEST_SIGNING_KEY" \
    "$INNGEST_BASE_URL/v1/events?name=finance.payment_failed&cel=event.data.founderId=='\''<founder-uuid>'\''&limit=1"
'
# Expected: { "data": [ { id: "...", data: { founderId: "<founder-uuid>", tier: "draft_one_click", ... } } ], ... }

# 6. Confirm the founder's /dashboard/audit page renders the new run with the
#    redacted summary, action class, tier-at-time, and the Request-human-review
#    affordance. Confirm the CFO function wrote a messages row with
#    trust_tier='draft_one_click', status='draft' (DB CHECK enforces).

# 7. Revert the preview-env flag and clean up the synthetic grant.
```

After the preview smoke passes, flip prd per the command above; within 1h fire a single prd synthetic smoke against the operator's own seeded grant; assert Inngest dashboard shows the run AND `/dashboard/audit` renders it; close #3947 with `gh issue close 3947 --reason completed`; run `/soleur:postmerge`.

## Related

- ADR-030 (Inngest as durable trigger layer)
- ADR-033 (per-tenant scope grants substrate)
- PR-F (#3940) — Inngest trigger layer + CFO autonomous-draft
- PR-G (#3947, PR #3984) — cohort-exposure surface + per-grant deny-by-default
- PR-A (#3960 close) — IaC for inngest-server
- `apps/web-platform/server/inngest/client.ts` — fail-closed startup guards (ADR-030 I4)
- `apps/web-platform/server/scope-grants/is-granted.ts` — webhook predicate's grant probe (ADR-033)

## Fresh-host provisioning (#4118)

A new Hetzner VM (intentional `terraform destroy && terraform apply`, full
`-replace`, or a brand-new Soleur user running `terraform apply` against an
empty Hetzner project) installs Inngest automatically via the cloud-init
`runcmd:` block at `apps/web-platform/infra/cloud-init.yml`. The block pulls
`ghcr.io/jikig-ai/soleur-inngest-bootstrap:v1.0.0`, extracts the embedded
`inngest-bootstrap.sh`, sources `INNGEST_CLI_VERSION` + `INNGEST_CLI_SHA256`
from the image's `Config.Env`, and runs the script — same install path as the
operator-triggered deploy webhook, just fired at first boot.

The currently-running prod VM is unaffected by this addition. `hcloud_server.web`
has `lifecycle.ignore_changes = [user_data]` (`apps/web-platform/infra/server.tf`),
so cloud-init.yml edits never re-render the existing host.

### Verification (no SSH required)

```bash
# Run from the operator's workstation. 200 or 401 = Inngest is alive.
curl -fsS -o /dev/null -w "%{http_code}\n" --max-time 10 \
  https://app.soleur.ai/api/inngest
```

Anything other than `200` / `401` means Inngest is absent or unreachable.
Investigate `/var/log/cloud-init-output.log` on the host (via Hetzner console
if SSH is also broken).

### Upgrade path (existing operator workflow, unchanged)

1. Push `vinngest-vX.Y.Z` tag.
2. The `build-inngest-bootstrap-image.yml` GHA workflow builds the OCI image.
3. The operator triggers the deploy webhook
   `deploy inngest ghcr.io/jikig-ai/soleur-inngest-bootstrap vX.Y.Z`.

Cloud-init installs only on FRESH hosts; live upgrades still go through the
webhook. Pinning is documented inline in `cloud-init.yml`'s drift-sentinel
comment ("Pinned image tag tracks
`apps/web-platform/infra/inngest.tf:locals.inngest_cli_version`").

### Tier 2 follow-up

A weekly disaster-recovery test that exercises the full fresh-`terraform apply`
path against a clean Hetzner test-workspace is tracked in #4126 (deferred).
Until that lands, the post-merge verification above is the operator-driven
canary on the prod VM.
