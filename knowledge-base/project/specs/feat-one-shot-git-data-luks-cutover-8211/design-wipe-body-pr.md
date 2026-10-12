# Design: the wipe body PR (DL-2, destroy `hcloud_volume.git_data`)

Status: DESIGN ONLY (plan Phase 4.1, 2026-10-12). Nothing here was executed, dispatched or applied; no
production system was read for this document. Every claim below is anchored to a file and a content anchor
read in this worktree, never a line number (`cq-cite-content-anchor-not-line-number`). A figure that came
from an ADR or a runbook (volume ids, dates) is a claim to RE-READ at build time, never to trust.

Rulings applied (decision-challenges.md): CTO F5 (new `mode=wipe` in `git-data-cutover.yml`; one job behind the
reviewer-gated environment; typed volume-id confirm; same-session fresh `boot_complete` + mapper, identity and
emptiness reads; ID-pinned Hetzner delete; 404 read-back as the end event; a terraform plan/apply split cannot
guarantee same-session re-assertion). F3 (fail closed on empty or unknown input) is applied to every read below.

Governing text: ADR-239, "Consequences" bullet "The wipe branch needs a rehearsal of its own" and
"Amendment 2026-10-09" (retention end: the wipe PR must destroy the volume itself, the Hetzner delete recorded in
that PR's evidence is the end event, the volume is NEVER mounted to purge in place) and "Amendment 2026-10-12"
(blocker chain; second slip past 2026-11-12 returns to the CLO); #10138 decision 1; #6897.

## 1. What exists today (read, not assumed)

- **There is no wipe body to restore, and there never was a destroying one.** `git show 7fb9c5b399^:apps/web-platform/infra/git-data-cutover.sh`
  (the parent of the #8189 deletion) holds `canary_luks_device` and `old_volume_wipe`. `old_volume_wipe` only logs
  `NEXT (operator/terraform, NOT this script): secure-wipe + detach + destroy the old hcloud_volume`. So the PR
  restores one IDEA (a canary that proves the serving path is the LUKS mapper before anything is destroyed) and
  builds the destroy itself. The retired `CONFIRM_WIPE` variable must stay retired: `refuse_legacy_modes` in
  `git-data-cutover.sh` refuses it with `verdict=real_cutover_unreconciled`, and the wipe uses a workflow mode, not
  that variable.
- **The plaintext volume is not mounted after boot, ever.** `git-data-bootstrap.sh`, unit "plaintext-count": it
  resolves `/dev/disk/by-id/scsi-0HC_Volume_<id>`, pins the device number, refuses a LUKS device, refuses holders,
  sets it kernel read-only (`blockdev --setro`, read back), stacks a throwaway dm snapshot named
  `git-data-pt-snap` on it, counts `repositories/` entries on the snapshot, tears the snapshot down and requires the
  origin's sysfs sector counters unchanged. The count excludes `.*.init.lock`, `.init.lock` and `lost+found`
  (`_repo_count`). `boot_complete` then carries `plaintext_volume=present plaintext_journal=<dirty|clean|absent>
  plaintext_empty=yes served_repos=0`. Consequence for this design: **`plaintext_empty=yes` means "no repository
  entry at boot", not "no residue"**. The id-bearing `.<id>.init.lock` files, the `.gc-cursor` residue and any
  snapshot copy are exactly what the count does not see (ADR-239 Amendment 2026-10-09). So emptiness here is a
  SAFETY gate (do not destroy user repositories), never a residue claim.
- **The Terraform side.** `git-data.tf`: `hcloud_volume.git_data` (name `soleur-git-data-store`, no
  `delete_protection`) and `hcloud_volume_attachment.git_data` (`automount = false`); `git-data-luks.tf`:
  `hcloud_volume.git_data_luks` (name `soleur-git-data-luks-store`). `module "git_data_userdata"` receives
  `git_data_volume_id = hcloud_volume.git_data.id`. The module variable `git_data_volume_id` has NO default and no
  validation, and `cloud-init-git-data.yml` already tolerates an empty value (`[ -z "${git_data_volume_id}" ] || ...`
  in the LUKS stage; `GIT_DATA_PLAINTEXT_VOLUME_ID='${git_data_volume_id}'` into the bootstrap, whose
  `if [ -n "$_pt_id" ]` arm is skipped). `hcloud_server.git_data` has NO `ignore_changes = [user_data]` (only
  `ssh_keys`), so changing the rendered id is a ForceNew replace of the host at the next git-data dispatch.
- **The workflow side.** `git-data-cutover.yml` runs five modes on one job `cutover` behind environment
  `web-platform-infra-apply`, workflow concurrency `git-data-state`, 56.8 KB (cap 490,000, ADR-231). Credentials are
  census-pinned: `WF9` in `git-data-cutover-access.test.sh` asserts the exact referenced-secret set
  (`DOPPLER_TOKEN`, `..._GIT_DATA_FLAG`, `..._GIT_DATA_ROOT`, `..._INFRA_PRIVILEGED`, `..._PRD`, `GITHUB_TOKEN`,
  `RESEND_API_KEY`, `SENTRY_ACTIONS_RO_TOKEN`, `SENTRY_API_HOST`). `DOPPLER_TOKEN_INFRA_PRIVILEGED` is already
  referenced (the `precondition_8209_open` check in step `flip_preconditions`) but is not yet used to load a
  Hetzner write token.
- **Hetzner credentials are tiered (ADR-241).** `HCLOUD_TOKEN_READONLY` (Tier A, readable from `prd_terraform` by
  `secrets.DOPPLER_TOKEN`; precedent: the volume-id lookup in `workspaces-luks-cutover.yml`) and `HCLOUD_TOKEN`
  (read/write, Tier B, delivered only by `.github/actions/infra-credentials` from `DOPPLER_TOKEN_INFRA_PRIVILEGED`
  on a main-only environment). The loader exports the plain name into `$GITHUB_ENV`, i.e. into EVERY later step of
  the job. That one fact drives the job shape below.
- **Host reads the proof already knows how to make.** `gd_capture` (30 s, 4096 bytes, anchored pattern, value never
  printed), the one-session store probe (`refuse_if_store_unverified_or_not_empty`), and the uncached mapper read
  `dd if="$STORE_MAPPER" of=/dev/null bs=4096 count=1 iflag=direct` in `git-data-liveness.sh`.

State as the ADRs last measured it (2026-10-12, Hetzner API read-only and Better Stack; RE-READ before use):
plaintext volume 106867358 and LUKS volume 107102614 both attached to server 169724272. These are inputs the
build re-reads from the Hetzner API; they are never constants in code.

## 2. Mechanism

### 2.1 Dispatch contract

```bash
gh workflow run git-data-cutover.yml --ref main -f mode=wipe -f confirm=WIPE-GIT-DATA -f volume_id=<digits>
```

- `mode` gains `wipe` in the choice list. The `confirm` token follows the existing pattern
  (`<VERB>-GIT-DATA`); step `confirm` already rejects a mismatch and already refuses `lineage` outside
  `mode=unfreeze`; it gains the symmetric refusal: `volume_id` is valid ONLY with `mode=wipe` and must match
  `^[0-9]{1,12}$` (a mistaken input must not pretend it applied), and `mode=wipe` with an empty `volume_id` refuses.
- The typed id is the human anchor, not the authority: it must EQUAL the id the Hetzner API returns for the name
  `soleur-git-data-store` (section 3, R2). Two independent sources (the owner's typing and the API) must agree.
- The environment reviewer is the second human gate. A menu answer or a "go ahead" is not authorization
  (`hr-menu-option-ack-not-prod-write-auth`): the owner names the exact command, with the volume id, in the
  session. The destroy is irreversible: the project holds no snapshot or backup of this volume (whether Hetzner
  retains any copy is unmeasured, ADR-239), so there is no restore path to design around.

### 2.2 Job shape: a separate `wipe` job in the same file, not a sixth arm of `cutover`

Resolved fork (technical, `hr-technical-fork-is-not-an-operator-question`). CTO F5 says "single job"; that is about
the assertion and the delete living in ONE job so they share one session. It does not require the existing
`cutover` job. Reasons for a second job inside `git-data-cutover.yml`:

1. The loader exports `HCLOUD_TOKEN` (root on any host through rescue, rebuild or re-attach, ADR-241 Context) into
   `$GITHUB_ENV`. In `cutover`, every step after it would see the token while the git-data root key and the SSH
   bridge are live, and the arms that do not wipe would carry a write token they never use. In a dedicated job the
   loader is placed after every read, immediately before the first write, and the census can pin that job's own
   step order.
2. `cutover`'s `if: always()` finalizer, its progress markers and `notify-failure`'s `case "$MODE"` list would all
   need wipe carve-outs; a wipe that fails must NOT run an unfreeze/flag unwind (it never froze or wrote a flag).
3. The test census (`git-data-cutover-access.test.sh`) pins `cutover`'s exact step `order = [...]`; a separate job
   gets its own order pin and leaves the existing one untouched.

Workflow-level `concurrency: git-data-state` already serializes the wipe against any replace, rotate or cutover
(`never between a replace's plan and apply`). `cutover` gains `if: inputs.mode != 'wipe'`, `wipe` gains
`if: inputs.mode == 'wipe'`, and `notify-failure` gains `needs: [cutover, wipe]` plus `wipe` in its mode word list
(otherwise a failed wipe maps to `MODE=unknown` and reads as STATE UNKNOWN, which would misdirect the owner).

### 2.3 Step order inside `wipe` (each step fail-closed; later steps `if: success()`, never `always()` except teardown)

| # | Step | Credential bound | What it does |
|---|---|---|---|
| W1 | confirm | none | mode/token/`volume_id` shape (above) |
| W2 | checkout, Doppler CLI | none | as `cutover` |
| W3 | flag/stamp/pin precheck | `DOPPLER_TOKEN_PRD` only. It is the only step of its JOB naming that secret. The existing census row (`AC9: DOPPLER_TOKEN_PRD is named only by the flag precheck step`, scanning every job) is amended deliberately to name exactly two sites, `cutover.flag_precheck` and `wipe.flag_precheck`, with the same pinned env shape; it is not loosened to "any step". | `git-data-flag-precheck.sh` gains `FLAG_MODE=wipe`: flag must read exactly `true`; `GIT_DATA_LUKS_CUTOVER_AT` must be present, parseable and at least 7 days old (the runbook's soak follow-through floor; the lb-weight-gate's 3 days is a different gate); the pin is read and written as today. Anything else: `verdict=wipe_precondition_<flag_not_true|stamp_absent|soak_not_elapsed>`, exit 5. |
| W4 | Hetzner identity read (read-only) | `DOPPLER_TOKEN` -> `HCLOUD_TOKEN_READONLY` | section 3, R1-R6. Writes a verdict record under `$RUNNER_TEMP` (server id, both volume ids, `created`, a nonce, an epoch). Absent token: refuse; NEVER fall back to the read/write token (the inngest runbook's wording: "absent from prd_terraform: stop, never fall back to HCLOUD_TOKEN"). |
| W5 | fresh `boot_complete` read | `DOPPLER_TOKEN` (query creds only) | section 3, R7. Same pinned git-data tables as `git_data_served_empty_read` in `scripts/lib/git-data-boot-signal-poll.sh`. |
| W6 | bridge, key fetch, ssh_config | as `cutover` | existing steps, unchanged |
| W7 | host assertion | none (root key via ssh_config) | ONE ssh session, section 3, H1-H9, new read-only verb in `git-data-cutover.sh` |
| W8 | load Tier-B Hetzner token | `DOPPLER_TOKEN_INFRA_PRIVILEGED` | `.github/actions/infra-credentials`; the LAST step before any write. No later step but W9-W12 and teardown may name the token; every ssh child later runs under `env -u HCLOUD_TOKEN`. |
| W9 | detach | `HCLOUD_TOKEN` | `POST /volumes/<id>/actions/detach`, poll the action to `success`; refuse on any other end state |
| W10 | post-detach host read | none | same bridge: the by-id link is gone AND the LUKS store still serves (uncached `dd iflag=direct` block read of `/dev/mapper/git-data` plus a root listing, the `git-data-liveness.sh` checks) AND the one-session `store-verified` facts still hold. Detaching the wrong volume would show here, before the irreversible step. |
| W11 | delete | `HCLOUD_TOKEN` | `DELETE /volumes/<id>`, expect 204 |
| W12 | read-back (the end event) | `HCLOUD_TOKEN_READONLY` | `GET /volumes/<id>` must be 404 AND `GET /volumes?name=soleur-git-data-store` must list zero volumes; the LUKS volume must still list exactly one and still be attached. A 404 with the name still listed means the id was wrong (the registry precedent in `apply-web-platform-infra.yml`, "returned 404, but a volume named ... still exists"), which is its own red verdict. |
| W13 | summary, teardown | none | evidence lines to `$GITHUB_STEP_SUMMARY`; shred root key, ssh_config, known_hosts, pin (as the `cutover` teardown step) |

The two API calls are separate, recorded steps because Hetzner refuses `DELETE` on an attached volume; they are
also why a failure BETWEEN them is a defined state (section 5, S3), not an undefined one.

## 3. The fail-closed read set

Every read is bounded (timeout), its output shape-validated by an anchored regex before use, its failure, empty
answer, multi-line answer, duplicate match or off-shape value a REFUSAL with a fixed verdict word (`exit 5`, the
house convention of `_store_refuse`), and none is retried into a pass. No `|| true`, no `// ""` default, no
"absent means fine". Values are never printed except digits and fixed words.

### 3.1 Hetzner reads (W4, Tier A)

| # | Read | Refusal |
|---|---|---|
| R1 | `GET /servers?name=soleur-git-data`: exactly ONE server; its id and `created` | `wipe_server_count`, `wipe_server_unreadable` |
| R2 | `GET /volumes?name=soleur-git-data-store`: exactly ONE; `.id` equals the typed `volume_id` | `wipe_volume_count`, `wipe_volume_id_mismatch` |
| R3 | `GET /volumes?name=soleur-git-data-luks-store`: exactly ONE; its id is DIFFERENT from the typed id | `wipe_luks_count`, `wipe_target_is_luks` |
| R4 | the plaintext volume's `.server` equals the R1 server id; the LUKS volume's `.server` equals the same id | `wipe_not_attached_to_current_host` |
| R5 | `.protection.delete` of the plaintext volume is exactly `false`. The run never lifts protection (lifting is a Terraform change of its own). | `wipe_delete_protected`, `wipe_protection_unreadable` |
| R6 | `.labels.app == "soleur-web-platform"` and `.location` equal to the LUKS volume's | `wipe_label_mismatch` |

Hetzner reads are authoritative about WHICH id is which volume; the host reads below are authoritative about what
the host currently does with it. Neither is trusted alone: a compromised web-1 or git-data can still answer
"unmounted, empty" (the `gd_capture` header says so), which is why the Hetzner side pins the identity and the
`boot_complete` side supplies independent evidence.

### 3.2 `boot_complete` read (W5)

The latest `stage=boot_complete` row for `host_name=soleur-git-data` from the PINNED git-data tables
(`BS_GIT_DATA_TABLE` hot UNION `BS_GIT_DATA_TABLE_S3` archive, `ORDER BY dt DESC LIMIT 1`, as
`git_data_served_empty_sql`), via `--only-secrets BETTERSTACK_QUERY_*` with `env -u DOPPLER_TOKEN`. The shared
default table answers zero rows for this host (runbook, "The D6 rotate"), so a read that does not pin the table is
a refusal by construction. Required: the row exists; its `dt` is at or after the R1 server's `created` (it belongs
to the CURRENT instance: a destroyed predecessor's row predates it); `luks_mounted=yes`, `fence_on_mapper=yes`,
`erasure_probe=yes`, `plaintext_empty=yes`, `served_repos=0`; `plaintext_volume=present`. Any other value,
including `plaintext_volume=absent` (the volume was never attached to this instance), refuses. Verdicts:
`wipe_boot_unreadable`, `wipe_boot_predates_server`, `wipe_boot_field_<name>`. Non-empty (`plaintext_empty` not
`yes`, or `served_repos` not `0`) is not a wipe condition at all: it means STOP and route to the CLO; the wipe
never decides what happens to repositories (runbook "Store not empty": "erasing those repositories is the
incident's decision").

### 3.3 Host reads (W7), ONE ssh session so no fact can change between two reads

A new read-only verb (working name `MODE=wipe_assert`) in `git-data-cutover.sh`, written with the same idioms as
`refuse_if_store_unverified_or_not_empty` (a `facts=( ... )` array joined into one `gd_capture` command, each stage
with its own exit code mapped to a fixed verdict word). It prints one fixed-shape line that the caller matches in
full; any other answer is `probe_failed rc=<n>`, never a verdict about the host. The checks, in order:

| # | Check | Idiom reused | Refusal |
|---|---|---|---|
| H1 | the store root is served by the mapper: `findmnt -n -o SOURCE --mountpoint /mnt/git-data` equals `/dev/mapper/git-data` (`probe=store-on-mapper` is the existing word), and the marker is bound to the filesystem UUID | `refuse_if_unmounted`, `refuse_if_not_on_mapper`, store-verified facts | existing words |
| H2 | the freeze sentinel is absent | store-verified `fz` | `cutover_frozen` |
| H3 | `/dev/disk/by-id/scsi-0HC_Volume_<typed id>` resolves (`realpath -e`) to a block special file; its major:minor (`stat -L -c '%t:%T'`) is recorded | bootstrap `_pt_link`/`_pt_mm` | `wipe_device_absent`, `wipe_device_not_block` |
| H4 | that device is NOT the mapper's backing device: the dev number behind `cryptsetup status git-data` differs from H3's, and equals the dev number behind `scsi-0HC_Volume_<LUKS id>` (identity checked in both directions; the LUKS id comes from R3 and is passed in, quoted with `%q`) | `git-data-luks-reopen.sh` ("cryptsetup status reports no backing device") | `wipe_device_is_luks_backing` |
| H5 | `cryptsetup isLuks` on it exits 1 (not LUKS); any other code is "unknown", never "plaintext" (the reopen script's own rule: `rc is not a blankness verdict`, #7240) | bootstrap, reopen | `wipe_device_luks_or_unknown` |
| H6 | not mounted: no `/proc/self/mountinfo` line carries its major:minor, `findmnt -S` returns nothing; `/sys/dev/block/<maj:min>/holders` exists and is EMPTY; `dmsetup info git-data-pt-snap` fails (no leftover snapshot) | bootstrap holders and snapshot refusals | `wipe_device_mounted`, `wipe_device_has_holders`, `wipe_snapshot_present` |
| H7 | no open handle: no `/proc/[0-9]*/fd/*` symlink resolves (`readlink -f`) to the device node. A timeout counts as "unknown" and refuses. | new, no extra packages needed | `wipe_device_open` |
| H8 | quiescent: `/sys/dev/block/<maj:min>/stat` sectors-written and sectors-discarded (fields 7 and 14) are identical across two reads two seconds apart; `blockdev --getro` reads `1` (the flag the boot's bootstrap set). `0` means the device was re-enumerated or the host rebooted since boot; that is a false-refusal path by design (git-data is outside the reboot primitive, ADR-115, but a crash reboot is possible) and the verdict names it so the owner knows the volume was not necessarily touched. | bootstrap `_pt_wstat` | `wipe_device_active`, `wipe_ro_flag_lost` |
| H9 | the host is the instance Hetzner names: `/var/lib/cloud/data/instance-id` equals the R1 server id. NOT yet verified for the Hetzner datasource; the build PR confirms it against the rung-2 rehearsal host and falls back to refusing (not to the metadata endpoint, which `nft_metadata_drop` blocks by design). | new | `wipe_instance_mismatch` |

The deliberate absence: the wipe does NOT re-count `repositories/` on the plaintext volume. Counting means
mounting or snapshotting a device whose retention is being ended precisely so it is never written; the boot-time
count (W5) is the emptiness evidence and the kernel read-only flag plus H6-H8 are the evidence it has not moved
since. The dm-snapshot count stays a boot-time instrument.

### 3.4 Same-session binding

W4 stamps a nonce and an epoch into the verdict record; W7, W9, W10 and W11 each re-read the record, refuse if the
nonce differs from this run's `GITHUB_RUN_ID`-derived value, and refuse if more than 15 minutes elapsed since W4
(`wipe_assertion_stale`). The window between W7 (the last look at the host) and W9 (the detach) is seconds, and
there is nothing a reviewer pause can widen: the environment approval happens BEFORE W1, not between steps.

## 4. Sequencing across PRs, state and gates (the part the plan's sentence 4.1(e) leaves open)

Plan 4.1(e) says the same PR removes `hcloud_volume.git_data`, its attachment and the plaintext branch from
Terraform. Read against the code, that sentence cannot all land in the PR that ADDS the mode, for three reasons,
each grounded:

1. **The encryption-posture ledger.** `scripts/encryption-posture-ledger.json` carries a row `hcloud_volume.git_data`
   (plaintext exception, `expires_on` 2026-11-12) whose `device_binding` must resolve to real code in the blocking
   CI leg `encryption-posture` (`scripts/lint-encryption-posture.py --repo-sweep`). Removing the HCL while the
   volume still exists in Hetzner forces deleting the disclosure row while the plaintext store is still there.
2. **A removed resource with no `removed { lifecycle { destroy = false } }` block is a destroy waiting for the
   next apply** (the comment at the top of `anthropic-ci-key.tf`). With the block it is a forget; Guard 4 of
   `test-infra-privileged-tier-census.sh` pins that shape and requires the forget to be reached by a `-target`.
3. **Gate counters.** `tests/scripts/lib/git-data-host-replace-gate.sh` requires `plaintext_attachment_recreated>=1`
   and scores `git_data_volume_destroyed`; the birth job's plan step lists `-target='hcloud_volume.git_data'`;
   `plugins/soleur/test/terraform-target-parity.test.ts` pins both jobs' target sets; and THIS plan's Phase 2 adds
   `git_data_post_apply_gate`, which asserts `hcloud_volume_attachment.git_data` has a `create` and
   `hcloud_volume.git_data` has no `delete|forget` in both modes. All of these change when the volume leaves
   Terraform.

Resolved sequence (technical fork, no ruling needed): three merges and two owner-named dispatches.

| Order | Step | Contents | Gate |
|---|---|---|---|
| 1 | **PR-W (mechanism)** | the `wipe` job, `FLAG_MODE=wipe`, the new read-only host verb, the `volume_id` input, tests (section 6), runbook "The wipe" section, a rehearsal-root variant that passes `git_data_volume_id = ""`, and a gate condition (below). Touches NO rung-2 hash-bound file, so the two-PR payload sequence is NOT triggered. | normal review; `git-data-cutover.yml` carries the no-admin-merge restriction (the issue says so) |
| 2 | rung-2 rehearsal of the empty-id render (owner-gated: it boots a paid host), dispatched from `main` with the empty-id variant, then an evidence-only PR | `RUNG2_VAR_DIVERGENCE` names `git_data_volume_id` (it is on the closed allowlist `GIT_DATA_RUNG2_DIVERGENCE_ALLOWLIST` in `git-data-birth-readiness-gate.sh`); the capture's PASS predicate for this arm is `plaintext_volume=absent plaintext_journal=absent plaintext_empty=yes served_repos=0` (the existing predicate requires `present`/`dirty`) | owner names the dispatch |
| 3 | **the wipe**, `mode=wipe` | sections 2-3 | owner names the command and the id; environment reviewer approves |
| 4 | **PR-C (record and removal)** | the Hetzner delete evidence (run URL, W12 lines); HCL removal of the two resources with `removed { lifecycle { destroy = false } }` blocks and the matching `-target` lines; `git-data.tf` passes `git_data_volume_id = ""`; ledger row `hcloud_volume.git_data` deleted; the plan-time gate, `git_data_post_apply_gate` and their suites amended (below); ADR-239 amendment; Art. 30 note staged for the CLO (PA-36); runbook; closes #6897 on its merge | the CLO date 2026-11-12 is the outer bound |

Why the rehearsal can come BEFORE the wipe: the evidence hash binds 13 files (the template, the render module's own
`.tf` files and the nine `file()`-bound payloads) and NOT the render arguments, so passing `""` from `git-data.tf`
and from the rehearsal root changes no hashed byte. Nothing in the machinery therefore FORCES the empty-id
rehearsal (that is the ADR-239 sentence about it, enforced by memory only). PR-W adds the enforcing condition: when
`git-data.tf` renders an empty plaintext id, `git_data_rung2_rehearsal_gate` also requires an evidence key
(working name `RUNG2_PLAINTEXT_VOLUME=absent`) and HOLDs otherwise. The mechanism is the build PR's; the PROPERTY is
fixed here: no replace or birth may render the empty-id branch unless a main-dispatched rehearsal booted it.

The wedge this ordering accepts, stated plainly: between step 3 (volume gone from Hetzner) and PR-C's merge,
`hcloud_volume.git_data` still sits in HCL and state. A git-data dispatch in that interval refreshes the volume
away and plans a CREATE of a new empty `soleur-git-data-store`, which the plan-time gate refuses as `out_of_scope`.
That is fail-closed, but it holds the emergency replace lever. Mitigation: PR-C is prepared as a ready PR before the
dispatch and merges immediately after the evidence is read; the runbook says the lever is held in that interval.

A second residual, also stated: the LIVE host's `user_data` still names the deleted id
(`GIT_DATA_PLAINTEXT_VOLUME_ID` in the rendered runcmd) until its next replace. `runcmd` is once per instance, so a
reboot does not re-run the bootstrap; a manual bootstrap re-run would FATAL closed
(`plaintext_unverified reason=source`, no marker, erasure refused). The runbook row says so and the next replace
boots the already-rehearsed empty-id render.

## 5. Failure states of the irreversible pair (defined, not improvised)

| State | Reads as | Recovery (every step owner-authorized, never automatic) |
|---|---|---|
| S1 fails before W9 | nothing changed | fix the cause, re-dispatch; `notify-failure` reports FAILED |
| S2 detach did not reach `success` | volume may be attached or detaching | read `GET /volumes/<id>`; if attached, nothing changed; if detached, S3 |
| S3 detached, W10 or W11 not completed | the volume is detached and intact | W10's refusal names why. If the LUKS store reads unhealthy, the wrong volume may have been detached: stop, the owner decides a re-attach (`POST /volumes/<id>/actions/attach`). Otherwise a plain re-dispatch REFUSES at R4 (`wipe_not_attached_to_current_host`), by design: a `resume` input is rejected because it would skip the host assertion. The continuation is an owner decision recorded on #6897 to delete a detached, host-unattached volume by id using the R1-R3, R5 and R6 reads only; W5's `boot_complete` evidence for the instance that last held the volume still stands, and the host assertion is moot because nothing is attached. |
| S4 delete returned 2xx but W12 reads the id | the delete did not take | re-read; do not re-run detach |
| S5 W12 reads 404 and the name list non-empty | the id was wrong | incident; the typed id and R2 disagreed in a way R2 should have caught: treat as a defect in W4 |

## 6. Tests and interlocks (the build PR's RED-first rows)

Stub-driven (a fake `curl` for Hetzner, a fake `ssh` answering the one-session line, a fake Better Stack reader), in
the house shape of `git-data-cutover-access.test.sh` and `workspaces-luks-cutover-gate`.

- **Order.** One stub log records every call with a sequence number; the happy path must read exactly
  R1-R6 < W5 < W7 < loader < detach < post-detach read < delete < read-back. Mutation rows swap each adjacent pair
  and require RED. The decisive one, named by the plan: the host-identity read moved before the `boot_complete` read
  or after the detach. The ssh stub is a state machine that flips from "attached, unmounted" to "device absent" at
  the detach call, so a reordered implementation reads the post-detach world and the row must go RED rather than
  pass on a stale fixture (the test OBSERVES inside the window).
- **Every unknown refuses.** One row per verdict word in sections 3.1 to 3.4, each driven by the stub returning
  empty, multi-line, off-shape, duplicate or error output; plus "token absent", "`HCLOUD_TOKEN_READONLY` absent
  never falls back to `HCLOUD_TOKEN`".
- **Identity.** typed id equals the LUKS id; typed id equals a volume attached to another server; id equals a
  volume whose by-id device is the mapper's backing device; two volumes returned for the name.
- **Credential census.** `WF9`'s secret set is unchanged; `DOPPLER_TOKEN_PRD` still named by the flag precheck
  step only; the Tier-B loader appears once, in `wipe`, after W7 and before W9; `HCLOUD_TOKEN` is referenced only by
  W9, W11 and (read-only name) W12; every ssh child runs under `env -u HCLOUD_TOKEN`; the new job has no
  `secrets` reference outside the allowed set; `notify-failure` carries `wipe`.
- **`git-data-cutover.sh` census.** The `G2` mutating-verb census and the "exactly five gd_capture call sites"
  census in `git-data-cutover-access.test.sh` move deliberately (the new verb is read-only; the site count is
  re-pinned to the new number, not loosened to "at least").
- **Gate amendments (PR-C).** Mutation: restore the old `hcloud_volume_attachment.git_data` create requirement and
  show the post-wipe canonical plan fixture goes RED, proving `git_data_post_apply_gate` and
  `git_data_host_replace_gate` were actually updated; the plan-time gate still refuses a CREATE of
  `hcloud_volume.git_data` (the wedge above is the intended refusal, not a regression).
- **Evidence honesty.** The record PR's lint refuses wording that claims snapshots or copies are gone: the end
  event claims the DEVICE only (ADR-239 Amendment 2026-10-09).

## 7. Preconditions and owner-gated steps

Preconditions (all must hold; the machine enforces what it can):

1. Flip done and soaked: `GIT_DATA_STORE_ENABLED=true` and the stamp at least 7 days old (W3). This is the ADR-239
   Amendment 2026-10-09 gate ("gated by the flip chain"); lifting it needs an ADR amendment and a CLO ruling, not a
   flag.
2. The chain it rides: #10137 fix merged and a successful rotate (`d6_replace_stale` already requires it for the
   flip), #8209, #8609 (so the Tier-B seam exists: `precondition_8209_open`), #8573 (flag write seam).
3. #8571 copy mode: the wipe does not depend on it, but a populated-store rotation does; recorded so nobody reads
   the wipe's completion as clearing that dependency.
4. The empty-id rehearsal evidence is on `main` (step 2 of section 4).
5. CLO: the retention date 2026-11-12 is the outer bound; a second slip returns to the CLO (ADR-239 Amendment
   2026-10-12). Moving `expires_on` past it requires a CLO re-ruling linked on #6897 first.
6. `soleur:legal:clo` has seen the wording of the record PR; brand-survival threshold for the BUILD PR is
   `single-user incident` and carries CPO sign-off (plan, User-Brand Impact).

Owner-gated (named, never inferred): (a) the empty-id rehearsal dispatch (paid host); (b) the `mode=wipe` command with
the volume id; (c) the environment approval; (d) any S3 recovery; (e) PR-C's merge timing; (f) the CLO's wording
sign-off. An agent never dispatches any of them on a menu answer.

## 8. What this does not prove or claim

- Nothing about Hetzner-side snapshot or backup retention of the volume (Art. 30 PA-36 (f) stays unmeasured), the
  `.gc-cursor` residue on either volume, or the served store's lock residue (the freeze-window purge, which has not
  run). The end event is "the device was destroyed at <time> by run <url>".
- Nothing about a copy of the volume held by anyone with prior access.
- `plaintext_empty=yes` at boot is not "the volume holds no personal data" (section 1).
- H9 and the exact Hetzner response shapes (`.server`, `.protection.delete`, the action poll, 204 on delete) are
  stated from the repo's existing reads (`postmerge` skill's `.volume.protection.delete`, the registry preflight's
  404 handling, the workspaces cutover's `?name=` lookup) and Hetzner's public API; the build PR pins them in its
  stub contract and re-verifies against a real read-only call before relying on them.

## 9. Build PR checklist (files expected to change)

PR-W: `.github/workflows/git-data-cutover.yml`; `apps/web-platform/infra/git-data-cutover.sh`;
`apps/web-platform/infra/git-data-flag-precheck.sh` (+ `.test.sh`); `apps/web-platform/infra/git-data-cutover-access.test.sh`;
a new `git-data-wipe` helper and its test (Hetzner calls through the stdin-config bearer library of ADR-280, never
argv); `tests/scripts/test-git-data-root-token-census.sh` if its row set moves; `rung2-rehearsal/rehearsal.tf` and
`.github/workflows/git-data-rung2-rehearsal.yml` (empty-id variant); `tests/scripts/lib/git-data-birth-readiness-gate.sh`
(the evidence-key condition) and its suite; the runbook (`git-data-luks-cutover-5274.md`: modes table, blast-radius
row for `wipe`, verdict-map rows for every `wipe_*` word, "The wipe"); `knowledge-base/legal/` NOT edited here (CLO).

PR-C: `apps/web-platform/infra/git-data.tf`, `git-data-luks.tf` (comment cross-refs), `tests/scripts/lib/git-data-host-replace-gate.sh`
and its suite, the replace job's post-apply call from this plan's Phase 2 (`git_data_post_apply_gate` and rows
PA1/PA8/PA10), `plugins/soleur/test/terraform-target-parity.test.ts`, `scripts/encryption-posture-ledger.json`,
ADR-239 amendment, the runbook, Art. 30 hand-off to the CLO.

ADR: this design applies ADR-239 as written. PR-C amends ADR-239 (retention end reached; the empty-id branch is
rehearsed) per the plan's note; no new ADR is needed unless the build changes the destroy sequencing described here.
