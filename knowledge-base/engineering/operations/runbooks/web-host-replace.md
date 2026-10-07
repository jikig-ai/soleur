# Runbook — replacing a web host

**Status:** current as of 2026-10-01 (#6969, ADR-148; rotated-credential re-seed #8705; fresh-boot LUKS reading, ADR-263).
**Applies to:** any `hcloud_server.web[<key>]` that is **already in state** — except `web-1`,
which this path refuses (see below).

**This is the destructive sibling of [birthing a web host](./web-host-birth.md).** A birth is
additive: it creates a declared-but-absent host and its gate permits zero destroys. A replace
**destroys the existing host and creates a new one in its place**. Pick by whether the host
exists:

| The host is… | Use | Gate contract |
|---|---|---|
| declared in `var.web_hosts` but absent from the provider | `web-host-create` | exactly 1 create, 0 destroys |
| present, but broken / dark / on a bad image | `web-host-replace` | exactly 1 delete+create of that key |
| present, but holding a baked create-time credential that has since been rotated (`hcloud_server.web` ignores `user_data` changes, so only a new host picks up the new value) | `web-host-replace` | exactly 1 delete+create of that key |

**Re-seeding a rotated credential — ordering.** Dispatch the replace only after the rotation's merge
apply is green (the #8705 `web_probes` rotation is the first such use). While the rotation is still
pending, the gate refuses the dispatch (the credential's replace is out of its scope), so a refusal
there is expected. A dispatch made *before* the rotation merges is NOT refused and bakes the old
credential into the new host. web-1 is excluded from this path; its copy is re-delivered by the
SSH-stage installers of the rotation's own apply.

**The fresh-host Doppler token is the exception to "rotate, then replace".** The read token a
fresh host uses to unlock its `/workspaces` volume (`doppler_service_token.workspaces_luks_fresh_boot`,
ADR-263 D4) is never co-rotated with web-1's `WORKSPACES_LUKS_BOOT_TOKEN`, and it is baked into the
host's `user_data`, which only a new host picks up. Its rotation **is** a host replacement: rotating it
without replacing the host leaves that host unable to re-open its volume on its next reboot. (Not
for web-2 before the volume rebirth, #9372: see "A `discriminate` fatal" below.)

Dispatching the wrong one is safe by construction — each gate refuses the other's plan shape,
and the `confirm` tokens are deliberately different — but it wastes a run.

## `web-1` is refused

This path aborts on `web_host_key=web-1`, at input validation and again in the gate. web-1 is
not merely higher-stakes; it is topologically different:

- `hcloud_volume_attachment.workspaces_luks.server_id` is hardcoded to it and is ForceNew, so
  replacing it requires recreating an attachment no other key has. Omit that and the LUKS
  at-rest store boots **unattached** while the host reports healthy.
- `cloudflare_record.app.content` is web-1's `ipv4_address`. Replace it without re-pointing
  the record and `app.soleur.ai` resolves to a destroyed host.
- The **web-1** `terraform_data.*` SSH provisioners in `server.tf` (the bulk of the
  fleet) pin `connection.host` to web-1 — including the seccomp and AppArmor sandbox
  controls. `-target` is upstream-only, so none is pulled into the plan and they would
  be left un-run against a dead IP.
- Decisively: `/mnt/data` pins **by-id** to `hcloud_volume.workspaces[key]`, which on web-1 is
  the **plaintext** volume the 2026-07-23 LUKS cutover **superseded**. The guest-side fresh-boot
  LUKS path of **#6931** (ADR-263) does not change web-1's by-id pin to that volume: a rebuilt
  web-1 now reads `ext4` there, fails closed at the provisioner's `discriminate` arm and powers
  itself off, instead of (as before the path) booting healthy and serving every user worktree
  **rolled back to 2026-07-23**. Either way the live LUKS volume sits attached and unopened.

The last one is a property of cloud-init, not of the terraform plan, so no gate arm can
observe it. **There is no automated route to replace web-1 today**, and there was none before
this path either.

<!-- lint-infra-ignore start: the blockquote below states the PRECONDITIONS a future change
     must satisfy before the web-1 refusal can be lifted (add gate arms, rehearse
     off-prod; the #6931 code path is merged). It prescribes no step for today's operator — the operative instruction in this
     runbook is a single `gh workflow run` dispatch. Naming a rehearsal as a prerequisite for
     someone else's future PR is not a human-run infra step in this one. -->
> **Corrected 2026-07-27.** This section previously named an *"ambiguous `scsi-0HC_Volume_*`
> mount glob"* as decisive and gave *"ADR-119 §Sequencing's volume-ID mount pin"* as the
> prerequisite. Both were false — #6604 pinned the mount by-id before this path existed, and
> ADR-119 has no §Sequencing — which made the refusal read as already relaxable. If you are
> here to lift the refusal: **the #6931 code path is merged** (the fresh-boot guest-side LUKS path,
> ADR-263; the live web-2 conversion is #9372). **The key-conditional gate arms for
> `hcloud_volume_attachment.workspaces_luks` and `cloudflare_record.app` now exist (#9356) and are
> arms-only:** inert while the refusal holds, and blind to the by-id mount pin, the web-1-pinned SSH
> provisioners and `-target` being upstream-only. The remaining blockers are a rehearsal on
> a non-production host (the section below covers what a web-2 rehearsal does and does not prove), and **#6964**; see ADR-148 §Alternatives item 4.
<!-- lint-infra-ignore end -->

## The procedure

### Step 0 — check the escrow config before you start; diagnose an abort (#9377)

A host born (or replaced) after #9377 reads its LUKS key and header-escrow pair from the separate
`prd_workspaces_luks_web` config. The provisioner **formats even when escrow is missing, by design**, so the
dispatch itself refuses to start without it: the `Escrow readiness preflight` step of `web-host-create` and
`web-host-replace` runs `scripts/web-host-escrow-preflight.sh` before any Terraform command, and **any
non-zero result aborts the run with nothing changed** (1 contract violated, 2 no token, 3 the config could not be
read; an unreadable config is never treated as a missing one).

**Ask first, with no human step.** Dispatch the read-only diagnostic `web-host-escrow-diagnose.yml` from `main`, find the
run you started, watch it, and read the verdict from the run log. The commands, the rule for finding your own run, and the full
outcome table (what each verdict means and what to do) are in Step 0 of [web-host-birth.md](./web-host-birth.md); it is the
single copy. Take the verdict only from the log line that starts with `Verdict:`, never from a bare `live-ok` or `PASS`
substring (the log echoes the step's script, which contains both).

When a replace aborts at this step, the cause is in its annotations and its own log: the checker prints one
`escrow-split-contract:CAUSE` line per family of missing name (a Terraform-managed name not created yet, none was missing on 2026-10-04 and the escrow-create workflow is retired, so only the `apply-web-platform-infra.yml` push-apply can create them now; or the R2 pair, the live
mint, the only gap on that date). **If `prd_workspaces_luks_web` does not exist at all**, the checker exits 3 and prints a `NOTE` instead of a
`CAUSE` line: `escrow-split-contract:NOTE prd_workspaces_luks_web was not found; this is usually consistent with the web-platform push-apply (apply-web-platform-infra.yml) not having created it yet (unmeasured: the read failed, absence of the config is not proven)`.
That says what the failed read is consistent with; it is not a diagnosis. (Read the push-apply's current state before relying on it. The single-use escrow-create workflow is retired (its only run was plan-only), and the apply HALT now refuses a create of the web-class passphrase (`random_password.workspaces_luks_web`); the push-apply can still create the config, the bucket and the name secrets.)

**A green run is necessary, not sufficient, and valid only when it ran.** The check reads secret *names*, so it cannot tell a
bucket-scoped R2 pair from web-1's pair pasted under the same names (the mint step on #9377 requires a signed `HEAD` of
web-1's bucket with the new pair to return 403). Cite a green run only if it was created by your dispatch in this replace session (the id rule in Step 0 of
web-host-birth.md) and its commit (the log's `Run-context:` line prints it, with the UTC time) equals the current `main` head;
otherwise dispatch again. The replace job
re-runs the same preflight itself and still aborts on any non-zero result with nothing changed. A red run blocks nothing
automated: repair the named cause and dispatch again.

**Before any host dispatch.** Four facts carry over from the retired escrow-create step (the full text is in Step 0 of
[web-host-birth.md](./web-host-birth.md), "Before any host dispatch"):

1. The preflight must print `escrow-split-contract:live-ok` before the replace is dispatched; the check is names only and
   proves neither the R2 pair's scope nor its values.
2. The R2 credential pair is not Terraform. Its mint and the signed isolation proof stay tracked on #9377, which was still
   open on 2026-10-06. Until the pair exists the preflight fails with the missing-R2-pair `CAUSE` line.
3. `web_host_replace` is a job of `apply-web-platform-infra.yml`. When that workflow is disabled at the time, the push-apply
   enable window applies: enable it for the dispatch, dispatch, then disable it again, and note that a merge to main inside
   the enabled window triggers its push-apply.
4. Losing the web-class passphrase entry has no documented or verified recovery: the apply HALT refuses a `create` of
   `random_password.workspaces_luks_web` and importing the existing value is not a supported route; do not apply, merge with the
   push-apply kill-switch line and escalate to the owner (see the same item in `web-host-birth.md`).

**If `escrow=missing` pages anyway** (alert `web-host-luks-boot-fatal`, stage `workspaces_luks_provision_escrow`;
the boot continued, the volume is formatted, the header has no off-host copy): escrow is attempted **once, at
birth**, so the only way to re-attempt it is a host replace (`web-host-replace`, with the config repaired first).
While the web-class host holds no user data that costs one replace. Once a web-class host holds data, the
remediation of this page is owned by the #9372 follow-up; no re-escrow step is defined here.

**During an outage, when the preflight cannot pass.** The preflight has **no in-workflow bypass**, by design. The only
operator-local route is the break-glass procedure in `web-host-birth.md` (written for a birth, with the preflight as its
step 0, run by hand because the dispatch does not run for it). A **web-1** replace is refused (above) and a web-1 rebirth
is not a supported recovery until the de-pet rebuild (#9421).

The paged stage's `reason=` values are decoded in "web-2 boot failed — how to read it" below (the `escrow` row and the table after it). That page is throttled fleet-wide for 35 minutes across boots, so read the stage directly after every birth or replace (the same section has the command).

```bash
gh workflow run apply-web-platform-infra.yml \
  -f apply_target=web-host-replace \
  -f web_host_key=web-2 \
  -f confirm=REPLACE-web-2 \
  -f reason='replace web-2 — <why>'
```

Add `-f image_tag=vX.Y.Z` to pin the image explicitly. Without it the pin is read from web-1's
live `/health` — the tag the fleet is actually serving, which is the right default. That read
is **not** circular on this path the way it is for a birth, because web-1 is never the host
being replaced here; supply `image_tag` when the fleet is down or when you need a specific
version.

The run pauses on the `web-platform-infra-apply` environment for reviewer approval before its
first step. Approve it in the Actions UI. **That approval is the only human input** — dispatch
queues the destructive step behind the reviewer gate, it does not bypass it.

`confirm` must be exactly `REPLACE-<key>`. It is a typo-guard, not the authorization, and it
is deliberately not the birth path's `BIRTH-<key>`: a token typed for a birth must not be able
to authorize a destroy.

### What the job does, and why each step is not optional

| Step | Guards against |
|---|---|
| Input validation, in this order: key shape regex → `confirm=REPLACE-<key>` → `var.web_hosts` membership → web-1 refusal → `image_tag` shape | An unknown key, a mis-selected `apply_target`, and the web-1 hazard above — all before anything reads a secret |
| `SENTRY_DSN` non-empty (ADR-128 R1) | The replacement is a *fresh* host: its pre-extraction boot stages emit through the baked DSN and nothing else. An empty DSN means it boots dark **with the original already destroyed** |
| amd64 runner assertion | A non-amd64 runner resolves the multi-arch index to a different manifest, voiding the coherence preflight's comparison |
| Digest pin (`tag → @sha256`) | TOCTOU: a tag that moves between preflight and apply defeats the preflight entirely |
| Coherence preflight | An image whose baked host-scripts do not match the applied hash aborts cloud-init at `stage=verify`; `runcmd` is once-per-instance, so nothing repairs it. On a replace the previous host is already gone, so this is an outage rather than a no-op |
| `web_host_replace_gate` | Any plan that is not exactly one replace of the requested key with both stores preserved and the NIC / volume attachment / firewall re-attached |
| Stock preflight | **The one that matters most here.** A replace destroys before it creates. The destroy frees the account slot but cannot conjure DC stock, so an out-of-stock create leaves the host gone and unrecreatable (#6393/#6400). On 2026-07-26 the entire cx and cax lines were orderable in 0 of 3 EU DCs (#6966) |
| Boot-trail read (ADR-128 R2–R5) | A green `terraform apply` that produced a dark host — which is #6969's originating incident exactly |

### What is preserved, and by what mechanism

The `-target` set is four addresses: the server, its NIC, its workspaces volume attachment,
and the fleet firewall attachment. Everything else is **absent from the target set**, and that
absence is what keeps them out of the destroy set. The obvious formulation — *"an untargeted
resource cannot be planned for destroy"* — is **false**: `-target` prunes **dependents**, not
**dependencies**. So the mechanism differs per address:

- `hcloud_volume.workspaces[<key>]` — the host's workspace store. It IS in the plan graph (the
  targeted attachment references it) and appears as a no-op. What preserves it is
  `prevent_destroy = true`, which errors at **plan** time, plus the gate's `out_of_scope` and
  `workspaces_volume_destroyed` arms. It survives the replace and re-attaches to the new host.
- `hcloud_volume.workspaces_luks` and the LUKS passphrase pair — untouched, so the at-rest
  data stays readable behind its existing header. A rotated passphrase would open a *new*
  header and strand the data while the host booted healthy.
- `cloudflare_record.app` — must not move on a standby replace. Any positive action on it is
  an out-of-scope abort.

The gate carries named backstops for the two volumes and the passphrase. They are
intentionally redundant with the out-of-scope arm; they exist so the abort message names the
catastrophe rather than saying "an address you did not authorize changed".

## What the replace does NOT restore

The `-target` set is upstream-only, so nothing downstream of the server rides along. Two
consequences worth knowing before you dispatch:

- **The web-1 `terraform_data.*` SSH provisioners** (disk monitor, resource monitor, fail2ban
  tuning, persistent journald, seccomp/AppArmor profiles, cron egress firewall, orphan reaper,
  …) hardcode
  `connection.host` to **web-1**. They never applied to any other host, so a non-web-1
  replace neither loses nor needs them. The ONE exception is
  `terraform_data.deploy_pipeline_fix_web2` (#9151): it dials web-2 and its
  `hcloud_server.web["web-2"].id` trigger re-fires delivery post-replace — but a replace
  also rotates web-2's sshd host key, so the next `apply-deploy-pipeline-fix.yml` run
  fails closed at the end-to-end probe until `scripts/capture-web-2-host-key.sh <ip>`
  re-captures `web-2-ssh-host-key.pub` (runbook: `git-data-luks-cutover-5274.md` §
  "Re-capturing web-2's host key"; ADR-237 consequence note).
- **Better Stack heartbeats** for the host already exist and are not targeted. If they are
  still `paused`, they are armed by the measure-then-arm step in the `apply` job at the next
  merge-to-main infra apply — the same as after a birth.

Neither is a regression introduced by this path; both match the birth path's behaviour. They
are listed because "the host is back" and "the host is fully configured" are different
claims, and the dispatch summary only supports the first.

## Verify the result

The job verifies itself and fails if the host booted dark — there is nothing to eyeball. The
boot-trail step polls Sentry for the host's own stage breadcrumbs and:

- exits clean when the trail reaches `cloud_init_complete` (and raises a `::warning::` if the
  host booted clean but *retried* a stage — a real fault that a green run would otherwise
  bury);
- fails the run with an `::error::` naming the **stage and the cause** on a fatal;
- fails the run if no terminal event lands inside the poll's 960 s deadline (the host's own
  declared boot window is 900 s; the reader allows slack), because
  absence past the boot window is the documented dark signal, not a slow boot.

If it reports a dark boot: `runcmd` is once-per-instance, so the host **cannot be repaired by
a reboot**. Do not put it into service — replace it again once the cause is fixed (except a web-2
`discriminate` fatal, which a replace cannot clear; see below).

### web-2 boot failed — how to read it

On a host born with the guest-side LUKS path (ADR-263) a fatal provisioner step, or `/mnt/data` not
being the mapper after it, emits a Sentry stage and then **powers the host off** (`poweroff -f`). A
failed boot therefore has **no** `SOLEUR_FRESH_BOOT_READY` row: that row is emitted once per
instance, at the end of a boot that got through. Read the signals in this order, without a login:

1. **Boot trail.** The job's boot-trail step names the stage and the cause in its `::error::` and
   step summary ("booted DARK at stage ... detail ..."). Start there. The server's own state
   confirms the gate fired: `curl -sS -H "Authorization: Bearer $HCLOUD_TOKEN"
   "https://api.hetzner.cloud/v1/servers?name=soleur-web-2" | jq -r '.servers[0].status'` reads `off`.
2. **Sentry stage.** `doppler run -p soleur -c prd -- bash scripts/sentry-issue.sh --host-events
   soleur-web-2 --stage <stage>` returns the event and its detail. Fourteen stages page (Sentry alert
   `web-host-luks-boot-fatal`): the eight provisioner arms below, `workspaces_luks_not_mounted`, the four
   `fresh_boot_not_ready_{token,vector,volume,luks}` and `escrow`, which pages although the boot continues
   (#9377: a header with no off-host copy is a single-point loss). Three stages are read, not paged
   (`web-host-luks-boot-warning`, NoOne): `wire_warn`, `result` and `fresh_boot_ready_bs_egress`.
   The provisioner's rows ride the journald tag `workspaces-luks-reopen`, which Vector ships to Better Stack
   once it is running; Vector is installed after the provisioner, so for a host that powered off on a fatal
   the Sentry stage is the record.

   | Stage (`workspaces_luks_provision_<arm>`) | Exit | Meaning and what clears it |
   |---|---|---|
   | `config` | 10 | A boot env file was missing or malformed. Fix the cause, then replace the host. |
   | `device` | 11 | The volume's by-id link never answered within 300 s (attachment missing or lagging). Check the attachment, then replace. |
   | `discriminate` | 12 | The device carries a filesystem, a signature or non-zero content (a volume that was not born raw, or the wrong device). **Nothing was written.** See "A `discriminate` fatal" below: replacing the host does not clear it. |
   | `key` | 13 | The Doppler key fetch failed past its retry ladder (Doppler outage, a revoked or wrong fresh-host token). This is where a key-fetch failure lands, not `format` or `open`. Fix the token or wait out the outage, then replace. |
   | `format` | 14 | `cryptsetup luksFormat`, `luksOpen`, `mkfs` or the final relabel failed on a raw volume. `luksFormat` stamps the container with the LUKS2 label `soleur-formatting`, replaced by `soleur-workspaces` only after `mkfs`; the label rides the volume, so the replacement host recognises an interrupted format and finishes it. A replace is the recovery. |
   | `open` | 15 | `luksOpen` of an existing container failed, or the container has no filesystem and neither a local intent file bound to the volume's `luksUUID` nor the `soleur-formatting` label ("damaged store"). |
   | `wire` | 16 | crypttab, fstab, the docker drop-in, the immutable covered inode, the mount, or enabling the reopen service and timer failed (the last would leave the first reboot without an unlock). |
   | `wire_warn` (non-fatal) | none | The daily probe timer did not arm; the boot continues and no probe row will arrive until it is fixed. |
   | `result` (non-fatal) | none | The arm file that carries `luks_arm` and `escrow` to the readiness row was unwritable. |
   | `mount` | 17 | `/mnt/data` is not mounted from the mapper after wiring. |
   | `escrow` (non-fatal, **pages**) | none | The header backup did not reach the off-host bucket, or the object read back did not match the header's size and md5. The event detail is `arm=escrow reason=<x>`: decode `<x>` in the `reason=` decode table below this one. The page is throttled **fleet-wide for 35 minutes across boots** (all boot events share one Sentry issue group), so also read the stage directly after every birth or replace. The boot continues. It is attempted **once, at birth**, so `escrow=missing` persists for the host's life and withholds the soak marker; a host replace is the only way to re-attempt it. |
   | `workspaces_luks_not_mounted` (cloud-init gate) | none | The provisioner exited cleanly but `/mnt/data` is not the mapper; the host powered itself off before anything wrote under it. |
   | `fresh_boot_not_ready_<reason>` (fatal) | none | The boot finished but the readiness gate named an unmet field (`reason=luks` is the volume step). |
   | `fresh_boot_ready_bs_egress` (warning) | none | The readiness row was skipped or failed to send to Better Stack (`reason=` `no_token`, `no_url`, `unpinned_url`, `bad_token_shape` — the Better Stack token has a character outside the token charset, re-set it in Doppler — or `post_failed`); the Sentry event's detail carries it with the row's `luks_arm`, `escrow` and `boot_id`. Without that row the marker cannot be earned. |

   **`reason=` decode for the `escrow` stage.** Read it with the command in item 2 above, `--stage workspaces_luks_provision_escrow`
   (`<host>` is `soleur-<web_host_key>`; web-1 is `soleur-web-platform`). The event detail is `arm=escrow reason=<x>`. The page is throttled by
   the alert's frequency (**35 minutes, per rule per issue group**) and every boot event from every host lands in one perpetually-active
   Sentry issue group, so the throttle is **fleet-wide and spans boots**: an escrow page within 35 minutes of any other
   `web-host-luks-boot-fatal` page (any stage, any host, including an earlier failed attempt of the same birth) can be folded into silence,
   and an escrow page can equally swallow a fatal one that follows it. Do not rely on the email alone: read the stage after every
   web-class birth or replace.

   | `reason=` | Meaning | Remediation (the boot continued and the volume is formatted; escrow is attempted once, so every one ends in a host replace) |
   |---|---|---|
   | `creds` | At least one of the four names (bucket, key id, secret, endpoint) read back empty from `prd_workspaces_luks_web`. | Repair the config (the preflight reads names only, so an empty value passes it), then replace the host. |
   | `shape` | The **bucket or the endpoint** failed its pattern (a lowercase DNS-style bucket name; exactly `https://<32 hex>.r2.cloudflarestorage.com`). | Fix the value in `prd_workspaces_luks_web`, then replace the host. |
   | `creds_shape` | The **R2 key id or secret** failed its pattern (key id: 16 to 128 alphanumerics; secret: 16 to 256 of `A-Za-z0-9/+=_-`), for example a stray quote, space or newline from a paste. No value is ever echoed. | Re-mint or re-paste the pair cleanly in `prd_workspaces_luks_web`, then replace the host. |
   | `uuid` | `cryptsetup luksUUID` did not return a UUID for the opened container. | Local to the host (not a config problem); replace the host. |
   | `tmp` | The tmpfs directory for the header copy could not be created. | Local to the host; replace the host. |
   | `backup` | `cryptsetup luksHeaderBackup` failed or wrote an empty file. | Local to the host; replace the host. |
   | `put` | R2 refused the upload (a non-2xx answer): the pair is not write-scoped to the bucket, the bucket or endpoint is wrong, or R2 was unavailable. | Repair the config, then replace the host. No automated check of the pair's R2 scope or of R2 availability exists yet; the mint procedure and its probe are owned by the #9377 mint comment. |
   | `readback` | The object read back after the upload did not match the header's size and md5 (an ETag mismatch). | Replace the host. No automated check of R2 availability exists yet; a persistent mismatch is owned by the #9377 mint comment. |

3. **Readiness row** (only for a host that booted: it is emitted once per instance and carries the
   birth boot's `luks`, `luks_arm` and `escrow`). The row has no host dimension among Better Stack's
   indexed columns; its only host marker is the `host=` token inside the message, so filter on that.
   `scripts/betterstack-query.sh` accepts a SELECT/WITH/SHOW statement or its own flags, and needs the
   query credentials from Doppler:

   ```bash
   doppler run -p soleur -c prd_terraform -- bash scripts/betterstack-query.sh "$(cat <<'SQL'
   SELECT dt, JSONExtractString(raw, 'message') AS message
   FROM (SELECT dt, raw FROM remote($BS_TABLE)
         UNION ALL
         SELECT dt, raw FROM s3Cluster(primary, $BS_TABLE_S3) WHERE _row_type = 1)
   WHERE dt > now() - INTERVAL 7 DAY
     AND JSONExtractString(raw, 'message') LIKE 'SOLEUR_FRESH_BOOT_READY %'
     AND JSONExtractString(raw, 'message') LIKE '% host=soleur-web-2 %'
   ORDER BY dt DESC LIMIT 5 FORMAT TSVWithNames
   SQL
   )"
   ```

   Read `luks` (`1` only when the `/mnt/data` source is the `/dev/mapper/workspaces` mapper; `ready=0
   reason=luks` means the volume step failed), `luks_arm` (`formatted` on a born-raw volume, `opened`
   when the volume already held a container, `noop` when it was already mounted; written once by the
   provisioner and never rewritten on a later reboot, because its source file is tmpfs) and `escrow`
   (`ok`, `missing` or `none`). Later boots are evidenced by the **daily probe row** instead
   (`SYSLOG_IDENTIFIER = luks-monitor`, `host_name = soleur-web-2`: `device_type=crypto_LUKS`,
   `mount_source=/dev/mapper/workspaces`, a `boot_id` that changes on every reboot, which is evidence for the reader and is never joined). The same two
   reads, with their verdict tokens, are `w2l_fetch_ready` / `w2l_ready_verdict` and `w2l_fetch_probe` /
   `w2l_probe_verdict` in `scripts/lib/web2-luks-rows.sh`.

#### A `discriminate` fatal, and replacing web-2 before the live conversion

The workspaces volume is never in a replace's destroy set (`prevent_destroy`), so a replace re-attaches
the **same** volume. For a volume that is not raw, "fix the cause and replace the host again" is
therefore circular: the new host meets the same `ext4` and takes the same fatal. The live web-2 volume
is still the Hetzner-formatted `ext4` one until the volume rebirth (**#9372**). **Replacing web-2 before
#9372 powers the new host off by design** (fail closed, serving weight 0, no user impact); do not
dispatch it. Only the rebirth, which deletes and re-creates the empty volume, clears a `discriminate`
fatal on a non-raw volume. For every other stage, fix the named cause and then replace the host; the
volume re-attaches to the new host.

#### The daily web-2 verify leg (`web2_marker`) — reason to action

The `web2_marker` job of `workspaces-luks-verify.yml` (default branch only: a schedule event, or a dispatch from `main`)
prints one reason token in its `::error title=web-2 LUKS evidence is RED::` line, or in its
`::notice title=web-2 not live yet::` line while the marker is absent and web-2 has no evidence that certifies this
instance (`no_probe_row`, `no_ready_row` or `probe_predates_ready`). Until #9372 has run, that notice is the expected state.

The join is instance-level (ADR-263 D5; `boot_id` is printed for diagnosis and never compared). The marker is
**earned** only when the newest probe row is green and fresh AND the newest readiness row is green and not newer
than that probe row. It is **kept** by the newest probe row alone, unless a readiness row is newer than the probe
row (a rebirth), which is RED `probe_predates_ready`. A RED run on a held marker deletes it (the gate fails closed);
a fault of the judge itself or of the query leaves the marker exactly as it is. A scheduled run that is RED or
could not judge files a `[ci/luks-verify-web2]` GitHub issue, one per class, deduped by title and commented only
when the reason changes: `web-2 LUKS evidence is RED` (labels `luks/class-web2-red`, `priority/p1-high`) or
`could not judge web-2 - nothing proven` (`luks/class-web2-unavailable`, `priority/p2-medium`). The job's last
step posts a Sentry Crons check-in to `workspaces-luks-verify-web2` (schedule events only) to catch a run that
never happened; that monitor is unrouted by design (`cron_monitor_alert_unrouted`) until its first measured
check-in (#9372), so the GitHub issue is the channel to watch.

| Reason | Cause | Next action |
|---|---|---|
| `no_probe_row` | No `luks-monitor` verdict row for `soleur-web-2` in the 48 h lookback: not converted yet, host down, or the probe timer never armed. | Marker absent: expected until #9372, a notice. After the conversion, or with a held marker (RED, marker deleted): read the boot trail, the host's Sentry stages and the `wire_warn` stage. |
| `no_ready_row` | No readiness row in the 90-day lookback (never converted, the host never finished a boot, or the row could not be sent). Only judged while the marker is absent. | Read the boot trail and the `fresh_boot_ready_bs_egress` stage. A notice. |
| `probe_predates_ready` | The newest probe row is older than the newest readiness row: the instance was just born or replaced and its probe has not run yet. | Wait for the next daily probe (at most 26 h). Marker absent: a notice. Marker held: RED, the marker is deleted and the soak restarts. |
| `probe_stale` | The newest probe row is older than 26 h (host down, timer stopped). | Check the server status and the boot trail; the probe timer is enabled by the provisioner. |
| `probe_fail_row`, `probe_malformed` | The newest probe verdict is a `FAIL (...)` line, or a row that does not parse. | Read the row and the Sentry `op=workspaces-luks-drift` event; the drift table in the 6604 cutover runbook lists each class. |
| `probe_not_luks`, `probe_mount_source` | The backing device is not `crypto_LUKS`, or `/mnt/data` is not mounted from `/dev/mapper/workspaces`. | The volume is not LUKS-backed. Do not flip; read the provisioner stages above. |
| `probe_escrow` | The probe's passphrase re-test is not `ok`: the Doppler passphrase no longer opens the container header. | Check the fresh-host token and `WORKSPACES_LUKS_KEY`. |
| `ready_escrow` | `escrow` is not `ok` in the readiness row: the header copy failed at birth. | Attempted once; replace the host to re-attempt. The marker stays withheld. |
| `ready_not_ready`, `ready_stage`, `ready_unit`, `ready_not_luks`, `ready_luks_arm` | The readiness row reports the boot did not finish clean (read its `reason=`), a unit was down, or `luks` / `luks_arm` is wrong. Only judged while the marker is absent. | Read the row (query above) and the `fresh_boot_not_ready_<reason>` Sentry stage. |
| `ready_host`, `ready_malformed` | The newest readiness row names another host or does not parse. Only judged while the marker is absent. | Re-run the query above; a row for another host means the host-name splice is wrong. |
| `probe_body_unparseable`, `ready_body_unparseable` | Better Stack answered with a body that is not JSON rows (an error page, a truncated line): zero counted rows, so RED. | Re-run the workflow; see [Better Stack log query](./betterstack-log-query.md) if it persists. A held marker is deleted. |

Faults that are not verdicts fail the run, file the `could not judge` issue and leave the marker exactly as it is:
a missing `BETTERSTACK_QUERY_*` secret or marker write token (`BETTERSTACK_QUERY_HOST_missing` and its siblings, `DOPPLER_TOKEN_missing`) or a malformed
marker token (`token_shape`), an unanswered Better Stack query (`query`), a Doppler fault reading, writing or
reading back the marker (`marker_read`, `marker_write`, `marker_readback`), and a fault of the judge itself on this
runner (`judge_error`, from `probe_judge_error` / `ready_judge_error`). A held marker that cannot be deleted on RED
(`red_delete_failed`, filed as RED) usually means a value in shared `prd` is showing through the branch config:
remove it there.

## Populated-volume rehearsal on web-2, after #9372

**What this proves, and what it does not.** web-2 carries its own LUKS volume once #9372 has converted it. A replace of web-2
meets a volume that already holds a LUKS container with an ext4 filesystem and content, which is the situation the provisioner's
`opened` arm exists for (the arm opens the container and never formats, relabels or runs `mkfs`). A rehearsal therefore proves the
**populated-volume-preserve path** and the **dispatch mechanics** (confirm token, digest pin, gate, boot-trail poll). It does **not**
exercise the web-1 keyed arms of the gate (they apply to the `web-1` key alone and the refusal still stands), and it does not touch
any of the web-1-only blockers above: those are proven only offline (the gate fixtures and mutation battery in
`tests/scripts/test-web-host-replace-gate.sh`) and, for the superseded by-id pin, by the T2 topology (#9357). A green web-2 rehearsal
is not evidence that web-1 is safe to replace.

**Before the replace (sentinel).** The volume must carry something a wrongful format would destroy. Write a uniquely named sentinel file
under web-2's `/mnt/data` through an authenticated, non-SSH channel, and record its name and content hash in the dispatch's tracking
issue. No such write channel for a standby host's volume exists in the repository today, so it is authored together with the live run
(a scripted verifier is written then, only if it proves useful). Without a sentinel the row query below still proves the arm taken
(`opened`, never `formatted`) and the escrow state, which is the part the provisioner records on its own.

**Dispatch.** The standard replace dispatch for `web-2`, exactly as in "The procedure" above. Nothing in this section dispatches anything.

**Post-replace acceptance (no SSH).** One inline query through the existing rows library reads the newest readiness row for `soleur-web-2`
(the row is emitted once per instance, at the replaced host's birth). It must report a GREEN verdict, `luks_arm=opened` and `escrow=ok`:

```bash
doppler run -p soleur -c prd_terraform -- bash -c '
  set -euo pipefail
  source scripts/lib/web2-luks-rows.sh
  out="$(mktemp)"; trap "rm -f \"\$out\" \"\$out.err\"" EXIT
  w2l_fetch_ready "$out" 1 5                      # lookback: 1 day, newest 5 rows
  verdict="$(w2l_ready_verdict "$out")"; echo "$verdict"
  msg="$(jq -rs "sort_by(.age_s | tonumber) | .[0].message" "$out")"; echo "$msg"
  case "$verdict" in GREEN*) ;; *) echo "FAIL: readiness verdict is not GREEN" >&2; exit 1 ;; esac
  case " $msg " in *" luks_arm=opened "*) ;; *) echo "FAIL: luks_arm is not opened (formatted means the populated volume was re-created)" >&2; exit 1 ;; esac
  case " $msg " in *" escrow=ok "*) ;; *) echo "FAIL: escrow is not ok" >&2; exit 1 ;; esac
  echo "ACCEPT: populated volume opened, never formatted; escrow ok"
'
```

`luks_arm=formatted` on this rehearsal is a **stop-the-line** result, not a warning: it means the provisioner saw a raw volume, so the
populated store was not the one attached. The verdict function accepts `formatted`, `opened` and `noop` for the daily marker, which is why
this query adds the stricter `opened` requirement. The sentinel read-back, once a channel exists, is the second half of the acceptance;
the row query alone cannot show that file content survived.

## If the apply fails partway

A replace destroys before it creates, so check the apply output for whether the destroy
landed:

- **Destroy did not run** — nothing changed. Re-dispatch after fixing the cause.
- **Destroy landed, create failed** (out-of-stock is the documented cause) — **two states are
  reachable and their recoveries are opposite.** Determine which one you are in first, from
  the apply log or a Hetzner API existence probe:

  ```bash
  curl -sS -H "Authorization: Bearer $HCLOUD_TOKEN" \
    "https://api.hetzner.cloud/v1/servers?name=soleur-<key>" | jq '.servers | length'
  ```

  - **Absent from state** (the create never returned an id) — re-dispatching *this* target
    plans zero replaces and the gate correctly refuses. Recovery is
    [`web-host-create`](./web-host-birth.md): additive, graded against the birth contract.
  - **In state but TAINTED** (the create returned an id and a later step failed) — a tainted
    resource plans `delete+create`, which *this* gate PASSES. Re-dispatch
    `web-host-replace`. Do **not** use `web-host-create` here: the birth gate aborts on the
    destroy arm.

  Either way the workspaces volume was never in the destroy set and re-attaches to the new host.
  If stock is the cause, repin `var.web_hosts[<key>].server_type` to an orderable type and
  **merge that change first** — this job replaces a host as declared, it does not redeclare
  one.

## References

- ADR-148 — web-host replacement is a distinct gated dispatch, not a widened birth
- ADR-145 — host birth is a guarded capability (the additive sibling)
- ADR-128 — fresh-boot observability (R1–R5)
- ADR-119 — the workspaces-LUKS cutover (why web-1 is refused)
- `tests/scripts/lib/web-host-replace-gate.sh` — the gate, with its full arm-by-arm rationale
- `tests/scripts/test-web-host-replace-gate.sh` — the mutation battery proving no arm is vacuous, including the key-conditional web-1 arms (#9356, arms-only)
- [Runbook — birthing a web host](./web-host-birth.md)
- [Runbook — the web-2 LUKS rebirth (#9372, single-use)](./web2-luks-rebirth-9372.md) — converts web-2's empty plaintext volume; until it runs a plain replace of web-2 re-attaches the ext4 volume
