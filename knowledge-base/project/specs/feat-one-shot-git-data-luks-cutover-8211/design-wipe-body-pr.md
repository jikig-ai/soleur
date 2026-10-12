# Design: the wipe body PR (DL-2, destroy `hcloud_volume.git_data`)

Status: DESIGN ONLY (plan Phase 4.1, 2026-10-12). Nothing here was executed, dispatched or applied; no
production system was read for this document. Every claim below is anchored to a file and a content anchor
read in this worktree, never a line number (`cq-cite-content-anchor-not-line-number`). A figure that came
from an ADR or a runbook (volume ids, dates) is a claim to RE-READ at build time, never to trust.

Rulings applied (decision-challenges.md): CTO F5 (new `mode=wipe` in `git-data-cutover.yml`; one job behind the
reviewer-gated environment; typed volume-id confirm; same-session fresh `boot_complete` + mapper, identity and
emptiness reads; ID-pinned Hetzner delete; 404 read-back as the end event; a terraform plan/apply split cannot
guarantee same-session re-assertion). F3 (fail closed on empty or unknown input) is applied to every read below.

Reading of F5 recorded here (technical fork, `hr-technical-fork-is-not-an-operator-question`): the ruling's
"single job" is read as "the assertion and the delete share ONE job", not "the existing `cutover` job"; section 2.2
resolves it into a separate `wipe` job in the same file. `decision-challenges.md` still quotes F5 verbatim as
"single job" and MUST record this reinterpretation (that file is updated by another agent; this document only states
the reading). "Same-session fresh ... emptiness reads" is only partly achievable: sections 3.2 and 3.3 state what
is asserted in the destructive session and what remains inferred from boot time.

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
  on a main-only environment). The Tier-B arm of the loader downloads the WHOLE `soleur-infra-privileged/prd`
  project and exports EVERY key into `$GITHUB_ENV` twice, once under the plain name and once as `TF_VAR_<lower>`
  (so `HCLOUD_TOKEN` AND `TF_VAR_hcloud_token`, `TF_STATE_AWS_*` and their `AWS_*` alias, `DOPPLER_TOKEN_TF`, and
  every other key), i.e. into EVERY later step of the job. It masks every string value per line before exporting,
  and it emits `outputs.source` (`tier_b` or `legacy`). Its legacy arm (empty `DOPPLER_TOKEN_INFRA_PRIVILEGED`)
  exports only `HCLOUD_TOKEN`, read from `prd_terraform` (read-only token first, then the read/write one), a path the
  loader itself says a branch can plant until O11. Those facts drive the job shape and the containment rules below.
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

1. The loader exports `HCLOUD_TOKEN` (root on any host through rescue, rebuild or re-attach, ADR-241 Context) and
   the rest of the privileged project into `$GITHUB_ENV`. In `cutover`, every step after it would see them while
   the git-data root key and the SSH bridge are live, and the arms that do not wipe would carry a write token they
   never use. In a dedicated job the loader is placed after every read, immediately before the first write, and the
   census can pin that job's own step order. **What this does NOT give (corrected claim):** a dedicated job does not
   contain the token inside W9 and W11. The plain name and `TF_VAR_hcloud_token` both stay in `$GITHUB_ENV`, so
   `env -u HCLOUD_TOKEN` alone is NOT containment: it leaves `TF_VAR_hcloud_token`, `TF_STATE_AWS_*`/`AWS_*` (the R2
   state key) and `DOPPLER_TOKEN_TF` (a workplace-scope Doppler token) visible to the child. The root key and the
   write token also COEXIST from W8 through W10 (W10 needs ssh), so "the token and the root key never coexist" holds
   only for the arms that do not wipe, not for this job. Design requirements (build PR, census-pinned): every ssh
   child and every step that runs repo code between W8 and the end of the job runs under an `env -i` allow-list of
   exactly what it needs (the precedent is the retired `web-host-reboot.yml` rows of `infra-credential-tiers-8209.md`,
   whose never-pooled, snapshot, reboot and summary steps each ran under an `env -i` allow-list pinned by a
   workflow test); the loader's per-line masking of every value is relied on and pinned (a census row that the
   loader still masks); `$GITHUB_ENV` blanking and the read-only read-back are in section 2.3 (W11b, W12); no
   third-party `uses:` action runs after W8 (the loader and the SSH bridge are LOCAL actions; the workflow's
   `uses:` pin set moves deliberately, see section 6).
2. `cutover`'s `if: always()` finalizer, its progress markers and `notify-failure`'s `case "$MODE"` list would all
   need wipe carve-outs; a wipe that fails must NOT run an unfreeze/flag unwind (it never froze or wrote a flag).
3. The test census (`git-data-cutover-access.test.sh`) pins `cutover`'s exact step `order = [...]`; a separate job
   gets its own order pin and leaves the existing one untouched.

Workflow-level `concurrency: git-data-state` already serializes the wipe against any replace, rotate or cutover
dispatched through this workflow, the git-data jobs of `apply-web-platform-infra.yml` and `apply-git-data-root-key.yml`
(the same group string; `never between a replace's plan and apply`). It does NOT serialize against a full or
non-git-data apply, which holds no `git-data-state` group (see section 4, wedge). The existing `cutover` job also
holds a job-level `concurrency: web-1-swap`; the `wipe` job would not. The build PR decides this explicitly and the
census pins the choice: the default is that `wipe` takes `web-1-swap` too (it shares the SSH bridge and the
`ssh_config` path with `cutover`), with the dispatch queued behind a web-1 swap rather than interleaved with it.

`cutover` gains `if: inputs.mode != 'wipe'` and `wipe` gains `if: inputs.mode == 'wipe'` (plus the re-entry mode of
section 5, S3). `notify-failure` needs MORE than `needs: [cutover, wipe]` and a mode word. As written it is keyed on
`needs.cutover.*` only, its `if:` is the pinned expression `always() && (needs.cutover.result == 'failure' ||
needs.cutover.result == 'cancelled') && needs.cutover.outputs.started != 'false'`, and its body maps a run with no
finalizer output to "STATE UNKNOWN ... check the flag in prd, the freeze sentinel and both hosts" with an
unfreeze remedy. A wipe that fails after the detach would read as that unfreeze-flavoured message, which is wrong
(the wipe never froze or wrote a flag) and hides the one fact the owner needs (a volume may be detached). Design
requirements:

- `wipe` job outputs: `mode`, `started` (as `cutover`'s), and `phase` = `pre_detach | detached | delete_sent |
  deleted`, written by the progress markers of section 2.3 (W9, W11, W12). An ABSENT `phase` on a failed wipe means
  the runner was lost before any marker (see the S-table).
- its own `if:` clause: `(needs.wipe.result == 'failure' || needs.wipe.result == 'cancelled') &&
  needs.wipe.outputs.started != 'false'`, OR-ed with the existing `cutover` clause; a skipped job (the other
  mode's) must not email.
- its own body words, never the unfreeze remedy: `WIPE_PRE_DETACH` (nothing changed), `VOLUME_DETACHED` (the
  plaintext volume is detached and not deleted: state S3, with the exact re-entry command of section 5),
  `DELETE_SENT_UNCONFIRMED` (state S4: read the volume list read-only before anything else), and for an absent
  `phase` a wipe-specific unknown word that names the read-only Hetzner volume read, not the freeze sentinel.
- `case "$MODE"` gains `wipe`. The census rows that pin `notify-failure` move deliberately and are re-pinned to the
  new exact values, never loosened: `N-if` (today `needs == "cutover"` and the whole `if:` string), `N-jobkeys`
  (the job key set stays `{needs, if, runs-on, timeout-minutes, permissions, steps}`) and `N-secrets` (still exactly
  `GITHUB_TOKEN` and `RESEND_API_KEY`, no Doppler token, no Hetzner token).

### 2.3 Step order inside `wipe` (each step fail-closed; later steps `if: success()`, never `always()` except teardown)

| # | Step | Credential bound | What it does |
|---|---|---|---|
| W1 | confirm | none | mode/token/`volume_id` shape (above) |
| W2 | checkout, Doppler CLI | none | as `cutover` |
| W3 | flag/stamp/pin precheck | `DOPPLER_TOKEN_PRD` only. It is the only step of its JOB naming that secret. The existing census row (`AC9: DOPPLER_TOKEN_PRD is named only by the flag precheck step`, scanning every job) is amended deliberately to name exactly two sites, `cutover.flag_precheck` and `wipe.flag_precheck`, with the same pinned env shape; it is not loosened to "any step". | `git-data-flag-precheck.sh` gains `FLAG_MODE=wipe`: flag must read exactly `true`; `GIT_DATA_LUKS_CUTOVER_AT` must be present, parseable and at least 7 days old (the runbook's soak follow-through floor; the lb-weight-gate's 3 days is a different gate); the pin is read and written as today. Anything else: `verdict=wipe_precondition_flag_not_true`, `wipe_precondition_stamp_absent` or `wipe_precondition_soak_not_elapsed`, exit 5. The stamp is only trustworthy once the rollback arm clears it (`design-rollback-rehearsal.md` F-D: today the rollback does not clear `GIT_DATA_LUKS_CUTOVER_AT`, so a rehearsal's stamp can satisfy the 7 days); until that fix has merged, W3 also requires the stamp to be NEWER than the last `mode=rollback` run (a `gh run list` read, fail-closed on an unreadable list). The flag is read AGAIN immediately before W9 (a second, read-only call of the same precheck; a flag that is no longer `true` refuses with `wipe_precondition_flag_not_true`). |
| W4 | Hetzner identity read (read-only) | `DOPPLER_TOKEN` -> `HCLOUD_TOKEN_READONLY` | section 3, R1-R6. Writes a verdict record under `$RUNNER_TEMP` (server id, both volume ids, `created`, a nonce, an epoch). The W4 epoch is the OUTER bound only; the bound that matters is the W7 epoch (section 3.4). Absent token: refuse; NEVER fall back to the read/write token (the inngest runbook's wording: "absent from prd_terraform: stop, never fall back to HCLOUD_TOKEN"). |
| W5 | fresh `boot_complete` read | `DOPPLER_TOKEN` (query creds only) | section 3, R7. Same pinned git-data tables as `git_data_served_empty_read` in `scripts/lib/git-data-boot-signal-poll.sh`. What this step proves and does not prove is section 3.2: it is boot-time evidence, at least the 7-day soak old, not a statement about now. |
| W6 | bridge, key fetch, ssh_config | as `cutover` | existing steps, unchanged |
| W7 | host assertion | none (root key via ssh_config) | ONE ssh session, section 3, H1-H10, new read-only verb in `git-data-cutover.sh`. On success it stamps the W7 epoch that bounds W9 (section 3.4). |
| W8 | load Tier-B Hetzner token | `DOPPLER_TOKEN_INFRA_PRIVILEGED` | `.github/actions/infra-credentials`; the LAST step before any write. The step REFUSES unless the loader's `outputs.source` equals `tier_b` (`wipe_token_source_legacy` or `wipe_token_source_unknown`): the legacy arm exports a `HCLOUD_TOKEN` read from `prd_terraform`, which a branch can plant until O11, and a destroy must never run on it. A census row pins the `source == 'tier_b'` guard and that no step between W8 and W9 can bypass it. No later step but W9 and W11 may name the write token (W10, W10b and W12 name only the read-only one; teardown names none). Everything after W8 runs under the containment rules of section 2.2 (an `env -i` allow-list, not `env -u HCLOUD_TOKEN`; no third-party `uses:` action). |
| W9 | detach | `HCLOUD_TOKEN` | First refuses (`wipe_assertion_stale`) if more than ~120 s have passed since the W7 epoch (W8 installs the Doppler CLI and downloads the whole privileged project, a variable tens of seconds, so the bound is W7 to W9, not W4 to W9) and re-reads the flag (W3). Then `POST /volumes/<id>/actions/detach` and polls the returned action at a 2 s interval for at most 30 attempts (60 s). Any end state other than `success` (`error`, still `running` after the 30th attempt, an unreadable body) refuses with `wipe_detach_not_confirmed`, whose body says the volume may be attached, detaching or detached and routes to S2. The poll counts toward the W7-to-W11 bound of section 3.4 (it is inside the window, not exempt from it). On `success`, writes `wipe_progress=detached` to `$GITHUB_OUTPUT` (the job output `phase=detached`) and a line to `$GITHUB_STEP_SUMMARY` IMMEDIATELY, because W13 runs only on success and a failed run would otherwise carry no marker. |
| W10 | post-detach host read | none | same bridge: the by-id link is gone AND the LUKS store still serves (uncached `dd iflag=direct` block read of `/dev/mapper/git-data` plus a root listing, the `git-data-liveness.sh` checks) AND the one-session `store-verified` facts still hold. Detaching the wrong volume would show here, before the irreversible step. Runs under an `env -i` allow-list that carries no Hetzner token, and under an explicit `timeout`. |
| W10b | Hetzner re-read of the target (read-only) | `HCLOUD_TOKEN_READONLY` | `GET /volumes/<id>`, immediately before the delete: `.name == soleur-git-data-store`, `.server == null`, `.protection.delete == false`, and `GET /volumes?name=soleur-git-data-luks-store` still lists exactly one attached volume. Nothing else re-reads Hetzner state between R1-R6 and the `DELETE`, and the W10 host read proves the mapper still serves, not the identity of the volume about to be deleted. Refuses with `wipe_target_changed` (state S3, detached). |
| W11 | delete | `HCLOUD_TOKEN` | Refuses (`wipe_assertion_stale`) if more than the build's bound (working value ~300 s: the W9 bound plus the detach poll and the W10 host read) has passed since the W7 epoch. `DELETE /volumes/<id>`, expect 204; on 2xx writes `wipe_progress=delete_sent` (job output `phase=delete_sent`) and a summary line immediately. |
| W11b | blank the write token | none | A small step right after W11 appends `HCLOUD_TOKEN=` (empty) to `$GITHUB_ENV`, so the plain name no longer carries the write token in W12 and teardown. It does not blank `TF_VAR_hcloud_token` or the other loader keys, which is why every later step runs under the `env -i` allow-list of section 2.2 and not on this blanking alone. |
| W12 | read-back (the end event) | `HCLOUD_TOKEN_READONLY`, under `env -u HCLOUD_TOKEN` inside the `env -i` allow-list | `GET /volumes/<id>` must be 404 AND `GET /volumes?name=soleur-git-data-store` must list zero volumes; the LUKS volume must still list exactly one and still be attached. On success writes `wipe_progress=deleted` (job output `phase=deleted`). A 404 with the name still listed means the id was wrong (the registry precedent in `apply-web-platform-infra.yml`, "returned 404, but a volume named ... still exists"), which is its own red verdict. |
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
`wipe_boot_unreadable`, `wipe_boot_predates_server`, `wipe_boot_field_<name>`.

**What this read is, stated plainly.** "Latest" means newest, not recent, and `dt >= server created` is not a
freshness bound. The bootstrap FATALs (`luks_residue`) on a non-empty served store (`git-data-bootstrap.sh`, step 3),
so after the flip no newer `boot_complete` can exist for this instance: the only row W5 can read is the pre-flip
one, at least the 7-day soak older than the wipe. It is boot-time evidence about the plaintext volume, and
`served_repos=0` in that row is a pre-flip fact about the served store, not a statement about it now. The emptiness
of the plaintext volume AT THE TIME OF THE WIPE is therefore inferred, not re-asserted, unless section 3.3 (H8, H10)
links the boot-time count to now. H8 and H10 are what turn the inference into an assertion; the design does not
claim the same-session emptiness read of F5 without them.

**Emptiness scope (requirement).** `plaintext_empty=yes` is a `repositories/`-only count (`_repo_count`: a missing
`repositories` directory counts as 0, and entries outside it are not counted). Data under another top-level name
(a legacy layout, repositories under a differently named directory) reads "empty", and the delete is irreversible
with no copy. W5 therefore also requires a layout-independent signal from the same read-only snapshot: either a
top-level name listing (`find -mindepth 1 -maxdepth 1`) restricted to an allowlist `{repositories, lost+found,
.gc-cursor, the lock dotfiles}`, or inodes in use against the formatted baseline. A missing or off-allowlist signal
refuses (`wipe_boot_layout_signal_<absent|offlist>`). Two constraints the build PR resolves explicitly: (a) the
superblock free-inode count is not trustworthy on a device with a dirty journal (the bootstrap's own reason for
counting on a dm snapshot where the journal replays into the COW), so the top-level name listing on a snapshot is the
preferred signal; (b) `git-data-bootstrap.sh` is `file()`-bound into the git-data `user_data`, so adding the signal
there is a change to a hash-bound payload (it triggers the two-PR payload sequence and a ForceNew host change) and
the LIVE host booted with the old bootstrap will never emit it. So the signal for the live volume cannot come from a
`boot_complete` row; it must be taken in the destructive session (the W7 verb running the same pinned snapshot unit
over the kernel-read-only device, with the same origin-counters-unchanged check, which revises the deliberate
absence below) or recorded as a one-off owner read on #6897 before the dispatch. An absent signal refuses either way.

Non-empty (`plaintext_empty` not
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
| H8 | quiescent AND untouched since enumeration: `/sys/dev/block/<maj:min>/stat` sectors-written and sectors-discarded (fields 7 and 14) are ABSOLUTELY `0` and `0` (nothing was ever written or discarded since the device was enumerated), AND identical across two reads two seconds apart; `blockdev --getro` reads `1` (the flag the boot's bootstrap set). Two reads two seconds apart prove only a two-second window, so the absolute zero is the assertion that links the boot-time count to now. The build PR confirms on the rehearsal host that an idle plaintext volume attached by this render reads `0 0` after boot (the bootstrap itself only compares its before and after counters, it does not require zero); if boot-time reads write nothing but a nonzero baseline is measured, the fallback is that the bootstrap emits its `_pt_w1` pair in `boot_complete` and H8 requires equality, and that fallback has the same hash-bound-payload cost as section 3.2(b). `getro` of `0` means the device was re-enumerated or the host rebooted since boot; that is a false-refusal path by design (git-data is outside the reboot primitive, ADR-115, but a crash reboot is possible) and the verdict names it so the owner knows the volume was not necessarily touched. | bootstrap `_pt_wstat` | `wipe_device_active`, `wipe_device_written`, `wipe_ro_flag_lost` |
| H10 | device generation bound: the host boot time (now minus `/proc/uptime`) must be at or before the W5 row's `dt` and the row's `dt` must fall within a bounded window after that boot time (the build fixes it, from the rung-2 rehearsal host's measured boot-to-`boot_complete` time); otherwise the host rebooted after the row (or the row belongs to another generation) and the boot-time count says nothing about this device. | new | `wipe_boot_generation_mismatch` |
| H9 | the host is the instance Hetzner names: `/var/lib/cloud/data/instance-id` equals the R1 server id. NOT yet verified for the Hetzner datasource; the build PR confirms it against the rung-2 rehearsal host and falls back to refusing (not to the metadata endpoint, which `nft_metadata_drop` blocks by design). | new | `wipe_instance_mismatch` |

The deliberate absence, revised: the wipe does NOT mount the plaintext volume and does NOT re-count `repositories/`
through a writable path; counting means mounting or snapshotting a device whose retention is being ended precisely
so it is never written. The boot-time count (W5) is the emptiness evidence for the `repositories/` tree. What the
destructive session adds is the part that can be asserted without touching the device: the kernel read-only flag, the
ABSOLUTE zero write and discard counters since enumeration and the device-generation bind (H8, H10), plus H6 and
H7. The layout-independent signal of section 3.2 is the one place a read-only dm snapshot in the destructive
session may be needed (the same unit the bootstrap uses, never a mount); if the build PR takes that route, this
paragraph's "does NOT re-count" narrows to "does not re-count `repositories/` and does not mount".

### 3.4 Same-session binding and the time bounds

W4 stamps a nonce and an epoch into the verdict record; W7, W9, W10, W10b and W11 each re-read the record and refuse
if the nonce differs from this run's `GITHUB_RUN_ID`-derived value (`wipe_assertion_stale` for a stale epoch). Two
epochs, because the 15-minute bound from W4 is the wrong bound for the destructive pair:

- **W4 epoch, outer bound, 15 minutes:** W5 to W7 (the Better Stack read, the bridge and key fetch, the host
  assertion) must complete within it.
- **W7 epoch, the bound that matters:** stamped when W7's assertion line is accepted. W8 (the Doppler CLI install
  and the whole-project download of the loader, a variable tens of seconds) sits between W7 and W9, so the host look
  is NOT seconds old at the detach. W9 refuses if more than ~120 s have passed since the W7 epoch; W11 refuses if more
  than the longer working bound (~300 s) have; the detach poll (60 s at most, W9) and the W10 host read are inside
  that window and count toward it. Exact values are the build PR's; the property is that the bound runs from the
  LAST host look, not from W4, and that a reviewer pause cannot widen it (the environment approval happens BEFORE
  W1, not between steps).
- **Hetzner state is re-read, not remembered:** W10b re-reads the target volume (name, `.server == null`,
  unprotected) and the LUKS volume's attachment right before the `DELETE`, because between R1-R6 (W4) and the delete
  nothing else reads Hetzner state. W12 reads it again after.
- **The flag is re-read right before W9** (section 2.3, W3 row).

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
| 1 | **PR-W (mechanism)** | the `wipe` job, `FLAG_MODE=wipe`, the new read-only host verb, the `volume_id` input, tests (section 6), runbook "The wipe" section, a rehearsal-root variant that passes `git_data_volume_id = ""`, and a gate condition (below), the `notify-failure` wipe clause and progress markers (section 2.2), the S3 re-entry arm (section 5) and the wedge test (below). Touches NO rung-2 hash-bound file AS DESIGNED, so the two-PR payload sequence is NOT triggered; if the layout-independent emptiness signal is added to `git-data-bootstrap.sh` (section 3.2(b)) that premise is false for this PR and the sequence applies. | normal review; `git-data-cutover.yml` carries the no-admin-merge restriction (the issue says so) |
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
That is fail-closed, but it holds the emergency replace lever. The git-data dispatch is NOT the only path that sees
the missing volume:

- `scheduled-terraform-drift` runs a full-root `terraform plan -detailed-exitcode` (no `-target`), which also plans a
  CREATE of `hcloud_volume.git_data` in the wedge. It only plans, so the effect is a drift report, but it is the
  second reader of the wedge and the runbook names it.
- A non-targeted apply (any apply path that is not the git-data dispatch and does not carry a `-target` set that
  excludes the volume and the server) that refreshes the volume away plans a NEW volume id. That id flows into
  `git_data_volume_id` and therefore into the rendered `user_data` of `hcloud_server.git_data`, which has no
  `ignore_changes = [user_data]`: a ForceNew replace of the git-data host from a path nobody dispatched for that
  purpose.

Requirements for the wipe-build PR (design requirements, not existing code): (1) prove BY TEST that no apply path other
than the git-data dispatch can plan the host replace in the wedge (a fixture of the post-wipe state fed through every
workflow's plan or apply gate, red if any path would plan `hcloud_server.git_data` replace or a create of
`hcloud_volume.git_data` outside the git-data dispatch's own gate); (2) time-box the interval: PR-C is prepared as a
READY PR (green, reviewed, the evidence slot the only open field) BEFORE the dispatch, the owner names a bound for
dispatch-to-PR-C-merge (a working bound of one business day, recorded on #6897 before the dispatch), and the runbook
says the replace lever is held and the drift plan is expected to show the create in that interval.

A second residual, also stated: the LIVE host's `user_data` still names the deleted id
(`GIT_DATA_PLAINTEXT_VOLUME_ID` in the rendered runcmd) until its next replace. `runcmd` is once per instance, so a
reboot does not re-run the bootstrap; a manual bootstrap re-run would FATAL closed
(`plaintext_unverified reason=source`, no marker, erasure refused). The runbook row says so and the next replace
boots the already-rehearsed empty-id render.

A third residual, and a PRECONDITION of PR-C rather than an independent item: after the flip the served store is
populated, and `git-data-bootstrap.sh` FATALs (`luks_residue`, forward-only) when first boot finds a non-empty served
store. PR-C renders `git_data_volume_id = ""`, a ForceNew change of the host, so the first replace after PR-C (the
only remediation lever for a dead host) re-runs first boot against a populated LUKS volume and fails closed:
git-data stays dark with its data intact. Availability and Art. 17 handling are what is at risk, not the data. The
populated-store rotation is #8571 (copy mode). Merging PR-C therefore requires #8571 (or an explicit, recorded owner
acceptance of this window) first; section 7 lists it and section 8 repeats it.

## 5. Failure states of the irreversible pair (defined, not improvised)

| State | Reads as | Recovery (every step owner-authorized, never automatic) |
|---|---|---|
| S1 fails before W9 | nothing changed (`phase` absent or `pre_detach`; notify word `WIPE_PRE_DETACH`) | fix the cause, re-dispatch |
| S2 detach did not reach `success` (`wipe_detach_not_confirmed`) | volume may be attached, detaching or detached | read `GET /volumes/<id>` (read-only token); if attached, nothing changed; if detached, S3 |
| S3 detached, not deleted (`phase=detached`; notify word `VOLUME_DETACHED`) | the volume is detached and intact; W10, W10b or W11 did not complete | W10's refusal names why. If the LUKS store reads unhealthy, the wrong volume may have been detached: stop, the owner decides a re-attach (`POST /volumes/<id>/actions/attach`) and nothing is deleted. Otherwise the continuation is the typed re-entry arm below. A plain re-dispatch of `mode=wipe` REFUSES at R4 (`wipe_not_attached_to_current_host`), by design, and a `resume` input on `mode=wipe` is rejected because it would skip the host assertion. |
| S4 delete returned 2xx but W12 reads the id (`phase=delete_sent`; notify word `DELETE_SENT_UNCONFIRMED`) | the delete did not take, or is not yet visible | re-read read-only; do not re-run detach |
| S5 W12 reads 404 and the name list non-empty | the id was wrong | incident; the typed id and R2 disagreed in a way R2 should have caught: treat as a defect in W4 |

**S3 re-entry arm (design requirement).** A detached volume cannot re-enter `mode=wipe`, and the Tier-B write token is
delivered only inside this workflow, so without a sanctioned path the continuation becomes a hand-run API call outside
the environment gate and the census (the exact thing ADR-241 tiers exist to prevent). Specified instead: a typed
re-entry mode in the same job (working name `mode=wipe_finish`, confirm token `WIPE-FINISH-GIT-DATA`, the same
`volume_id` input; both added to the closed mode choice and the input census of section 6), still behind the
environment and its reviewer, and not a loosening of `mode=wipe`. It requires, each fail-closed with a fixed verdict
word and a bounded read:

1. the volume reads DETACHED (`GET /volumes/<id>`: `.server == null`, a FRESH read in this session), its `.name` is
   `soleur-git-data-store`, `.protection.delete == false`, and the typed id equals the id of the name lookup (R2);
2. R1, R2, R3, R5 and R6 re-read (R4 is replaced by the detached read above and by the LUKS volume still attached to
   the R1 server);
3. the LUKS store healthy: one ssh session over the bridge, the W10 checks (uncached `dd iflag=direct` block read of
   `/dev/mapper/git-data` plus a root listing, the one-session store-verified facts);
4. no emptiness evidence of unbounded age: the arm does NOT consume W5's `boot_complete` row (a volume left detached
   for a week would otherwise ride on a week-old row). It instead requires that a `mode=wipe` run on this repository
   whose recorded `phase` is `detached` for THIS volume id exists within a build-fixed bound (a `gh run list` read;
   working bound 24 hours), and refuses past it: beyond that age the full `mode=wipe` path (a re-attach, a new
   assertion, a new dispatch) is the only route, which is an owner decision recorded on #6897;
5. the flag still reads `true` and the stamp precheck of W3 still passes;
6. it then runs W8 (the `tier_b` source guard), the W7-style epoch (stamped at the head of the arm), W10b, W11, W11b
   and W12 unchanged, with the same progress markers and notify words.

If the build PR defers this arm, S3 is an accepted MANUAL API step, and the document says so rather than leaving it
implicit: after the owner records the decision on #6897 and re-reads R1-R3, R5 and R6 and a fresh `server == null`
with `HCLOUD_TOKEN_READONLY`, the delete is one request whose token is passed through a stdin curl config, never
argv or the environment (ADR-280's stdin-config library): `curl -sS -K - -X DELETE https://api.hetzner.cloud/v1/volumes/<id>`
with the bearer header supplied on stdin, expect 204, then the W12 read-back by hand. The manual form uses a
read/write token outside the workflow's environment gate and census; that is why the typed arm is the default.

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
- **Credential census.** `WF9`'s secret set is unchanged (`DOPPLER_TOKEN_INFRA_PRIVILEGED` is already in it);
  `DOPPLER_TOKEN_PRD` is named by exactly two sites, `cutover.flag_precheck` and `wipe.flag_precheck`, with the same
  pinned env shape (the `AC9` row, which today asserts a single `("step", "flag_precheck")` site across `len(jobs) == 2`,
  is amended deliberately, not loosened); the Tier-B loader appears once, in `wipe`, after W7 and before W9, and a step
  guards `outputs.source == 'tier_b'` between it and W9 (a legacy-arm run is refused, with a mutation row that flips
  the guard and expects RED); `HCLOUD_TOKEN` is referenced only by W9 and W11 (the read-only name by W4, W10b and W12);
  every step after W8 that runs repo code or ssh runs under an `env -i` allow-list that carries NO `TF_VAR_*`, `AWS_*`,
  `TF_STATE_AWS_*` or `DOPPLER_*` name (`env -u HCLOUD_TOKEN` alone fails the row, because the loader exported the
  token under two names and the state key and a Doppler token besides); W11b blanks `HCLOUD_TOKEN` in `$GITHUB_ENV`;
  no third-party (remote) `uses:` appears after W8; the loader still masks every string value per line; the new job
  has no `secrets` reference outside the allowed set; `notify-failure` carries `wipe`.
- **Workflow shape census (these pins move with a third job and a new input; each is re-pinned deliberately).** In
  `git-data-cutover-access.test.sh` (AC9 / G7 and the `WF-` rows): `len(jobs) == 2` (the `DOPPLER_TOKEN_PRD` row and
  the `AC9: DOPPLER_TOKEN_PRD is named only by the flag precheck step` scan use it); `sorted(inputs.keys()) ==
  ["confirm", "lineage", "mode"]` (gains `volume_id`); `WF-inputs-refs` (`only inputs.confirm, inputs.lineage and
  inputs.mode are referenced`, gains `inputs.volume_id`); the closed `mode` choice `proof|flip|rollback|unfreeze|
  redeploy` (gains `wipe`, and `wipe_finish` if section 5's arm is built); the local-action set, today exactly
  `[cf-tunnel-ssh-bridge, notify-ops-email]` (gains `./.github/actions/infra-credentials`); the `cutover` job's exact
  key allowlist (gains `if`) and its pinned step `order`; and the job-level `concurrency` decision of section 2.2
  (`web-1-swap` for `wipe` or an explicit census row that it holds none).
- **Progress markers and notify.** A stub run that fails after W9 leaves `phase=detached` and the notify body carries
  `VOLUME_DETACHED` and NOT the unfreeze remedy or the `STATE UNKNOWN ... freeze sentinel` text; a failure after W11
  carries `DELETE_SENT_UNCONFIRMED`; a failed `mode=wipe` never produces `MODE=unknown`; the markers are written at W9
  and W11 themselves (not at W13, which is `if: success()`).
- **Time bounds and TOCTOU.** A stub clock past the W7-epoch bound refuses at W9 (`wipe_assertion_stale`) with the
  detach NOT sent; a detach poll that never reaches `success` in 30 attempts refuses `wipe_detach_not_confirmed`; a
  W10b read that returns a changed name, an attached server or `protection.delete == true` refuses before the
  `DELETE`; a flag flipped to `false` after W3 refuses at the pre-W9 re-read.
- **Emptiness rows.** Non-zero absolute written or discarded sectors; `getro == 0`; a `boot_complete` row whose
  `dt` predates the host's boot time (H10); a missing or off-allowlist layout-independent signal; a `repositories`
  directory that is absent (counts 0 in `_repo_count`) but with a non-allowlisted top-level entry: each refuses.
- **The wedge (section 4).** The wedge test of section 4: a post-wipe state fixture fed to every workflow's plan or
  apply gate proves that only the git-data dispatch's own gate can plan the host replace.
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
   flag. The 7 days anchor on `GIT_DATA_LUKS_CUTOVER_AT`, which the rollback does not clear today
   (`design-rollback-rehearsal.md` F-D): a rehearsal's stamp, or a stamp from a flip that was later rolled back, would
   satisfy the soak. So a precondition is that the rollback-clears-the-stamp fix (that document's R8 / section 6) has
   MERGED; failing that, W3 requires the stamp to be newer than the last rollback run (section 2.3), and the flag is
   re-read right before W9.
2. The chain it rides: #10137 fix merged and a successful rotate (`d6_replace_stale` already requires it for the
   flip), #8209, #8609 (so the Tier-B seam exists: `precondition_8209_open`), #8573 (flag write seam).
3. #8571 copy mode: the WIPE itself does not depend on it, but PR-C does (section 4, third residual): after the flip
   the served store is populated, so the first replace after PR-C re-runs first boot against a populated LUKS volume
   and FATALs `luks_residue` (forward-only). #8571, or an explicit recorded owner acceptance of that window, is a
   PRECONDITION of PR-C's merge, not an independent item; the wipe's completion does not clear it.
4. The empty-id rehearsal evidence is on `main` (step 2 of section 4).
5. CLO: the retention date 2026-11-12 is the outer bound; a second slip returns to the CLO (ADR-239 Amendment
   2026-10-12). Moving `expires_on` past it requires a CLO re-ruling linked on #6897 first.
6. `soleur:legal:clo` has seen the wording of the record PR; brand-survival threshold for the BUILD PR is
   `single-user incident` and carries CPO sign-off (plan, User-Brand Impact).

Owner-gated (named, never inferred): (a) the empty-id rehearsal dispatch (paid host); (b) the `mode=wipe` command with
the volume id; (c) the environment approval; (d) any S3 recovery (the `mode=wipe_finish` dispatch, or the manual form if the build PR defers that arm); (e) PR-C's merge timing, including the recorded bound of section 4 and the #8571 precondition; (f) the CLO's wording
sign-off. An agent never dispatches any of them on a menu answer.

## 8. What this does not prove or claim

- Nothing about Hetzner-side snapshot or backup retention of the volume (Art. 30 PA-36 (f) stays unmeasured), the
  `.gc-cursor` residue on either volume, or the served store's lock residue (the freeze-window purge, which has not
  run). The end event is "the device was destroyed at <time> by run <url>".
- Nothing about a copy of the volume held by anyone with prior access.
- Not a claim that the volume is empty at the time of the wipe beyond what H8 and H10 assert: the `repositories/`
  count and the layout-independent signal are boot-time (or one-time owner-read) evidence, and a missing signal
  refuses (section 3.2).
- Not a claim that token containment is by `env -u`: containment is the `env -i` allow-list plus the `tier_b` source
  guard plus the blanking of W11b, and the root key and the write token coexist from W8 through W10 (section 2.2).
- Not a recovery plan for a populated-store host replace: that is #8571 and a PR-C precondition (section 4).
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
row for `wipe`, verdict-map rows for every `wipe_*` word, "The wipe", the wedge note and the S3 re-entry command); `.github/actions/infra-credentials` is read, not edited; `knowledge-base/legal/` NOT edited here (CLO). Also expected: the notify composite wiring in `git-data-cutover.yml`, `design-rollback-rehearsal.md`'s stamp fix (a separate PR, a precondition), and a wedge-proof test across the apply workflows' plan gates.

PR-C (merges only after the #8571 precondition of section 7 and inside the recorded bound of section 4): `apps/web-platform/infra/git-data.tf`, `git-data-luks.tf` (comment cross-refs), `tests/scripts/lib/git-data-host-replace-gate.sh`
and its suite, the replace job's post-apply call from this plan's Phase 2 (`git_data_post_apply_gate` and rows
PA1/PA8/PA10), `plugins/soleur/test/terraform-target-parity.test.ts`, `scripts/encryption-posture-ledger.json`,
ADR-239 amendment, the runbook, Art. 30 hand-off to the CLO.

ADR: this design applies ADR-239 as written. PR-C amends ADR-239 (retention end reached; the empty-id branch is
rehearsed) per the plan's note; no new ADR is needed unless the build changes the destroy sequencing described here.
