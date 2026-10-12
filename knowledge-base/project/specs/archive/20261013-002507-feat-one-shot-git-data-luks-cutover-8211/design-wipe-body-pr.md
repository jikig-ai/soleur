# Design: the wipe body PR (DL-2, destroy `hcloud_volume.git_data`)

Status: DESIGN ONLY (plan Phase 4.1, 2026-10-12). Nothing here was executed, dispatched or applied; no
production system was read for this document. Every claim below is anchored to a file and a content anchor
read in this worktree, never a line number (`cq-cite-content-anchor-not-line-number`). A figure that came
from an ADR or a runbook (volume ids, dates) is a claim to RE-READ at build time, never to trust.

Rulings applied (decision-challenges.md): CTO F5 (new `mode=wipe` in `git-data-cutover.yml`; one job behind the
reviewer-gated environment; typed volume-id confirm; same-session fresh `boot_complete` + mapper, identity and
emptiness reads; ID-pinned Hetzner delete; 404 read-back as the end event; a terraform plan/apply split cannot
guarantee same-session re-assertion). F3 (fail closed on empty or unknown input) is applied to every read below.

Reading of F5 (plan-default reading, recorded in `decision-challenges.md` as a taste row, not a technical ruling):
the ruling's "single job" is read as "the assertion and the delete share ONE job", not "the existing `cutover`
job"; section 2.2 resolves it into a separate `wipe` job in the same file. `decision-challenges.md` quotes F5
verbatim as "single job" in its ruling row and records the reinterpretation in its own row (class taste: a reading of
the F5 wording, not a technical fork). "Same-session fresh ... emptiness reads" is only partly achievable: sections 3.2 and 3.3 state what
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
  `mode=unfreeze`; it gains the symmetric refusal: `volume_id` is valid ONLY with `mode=wipe` and
  `mode=wipe_finish` (section 5 gives the re-entry mode the same input) and must match `^[0-9]{1,12}$` (a mistaken
  input must not pretend it applied), and either wipe mode with an empty `volume_id` refuses.
- The typed id is the human anchor, not the authority: it must EQUAL the id the Hetzner API returns for the name
  `soleur-git-data-store` (section 3, R2). Two independent sources (the owner's typing and the API) must agree.
- The environment reviewer is the second human gate. A menu answer or a "go ahead" is not authorization
  (`hr-menu-option-ack-not-prod-write-auth`): the owner names the exact command, with the volume id, in the
  session. The destroy is irreversible: the project holds no snapshot or backup of this volume (whether Hetzner
  retains any copy is unmeasured, ADR-239), so there is no restore path to design around.
- **The headless approval form is never valid here.** `design-rollback-rehearsal.md` documents a consent-only,
  UNVERIFIED `gh api -X POST .../pending_deployments ... state=approved` form for a reviewer-gated environment. It is
  never valid for `mode=wipe` or `mode=wipe_finish`: the environment approval is an owner action by a human in the
  owner's own session, and an agent never approves its own wipe dispatch (the environment's only reviewer is the
  owner's own login, `infra-credential-tiers-8209.md` row for the retired `web-host-reboot.yml`, so the approval's
  independence is a rule, not a platform control).
- **Run discriminator (design requirement).** Workflow-dispatch inputs and job outputs are NOT returned by
  `gh run list --json ...`; the cutover workflow already says so for the d6 reader ("displayTitle is the workflow
  name on dispatch runs, the target is only visible in the job/step list", comment in step `flip_preconditions`).
  Every design item below that reads an earlier run (W3's rollback-recency read, section 5's `wipe_finish`
  freshness read) therefore needs a discriminator the API does expose. Specified: a workflow-level `run-name:` built
  from `inputs.mode` (a closed choice) and, for the wipe modes only, `inputs.volume_id`, read with
  `gh run list --workflow git-data-cutover.yml --limit <N> --json databaseId,displayTitle,createdAt,conclusion,headBranch,event`
  and matched in full against closed patterns, one per title family (anything else, including a title carrying a
  free-text `volume_id` that is not digits, matches none and is never interpreted as a new-format title):
  - wipe modes: `^git-data (wipe|wipe_finish) [0-9]{1,12}$`;
  - every other mode, rollback included (W3 uses this discriminator to find the last `mode=rollback` run, so it needs
    its own title): `^git-data (proof|flip|rollback|unfreeze|redeploy)$`. The `run-name` expression emits no trailing
    space and no id for these modes (W1's `volume_id` refusal means a rollback dispatch cannot carry one), and the
    exact-string census row pins the expression;
  - **legacy titles are classified, not refused.** `run-name:` does not exist today: every run created before PR-W
    lands carries the workflow name `git-data cutover (#5274 / ADR-220 / ADR-239)` (read:
    `gh run list --workflow git-data-cutover.yml --limit 20 --json displayTitle` returns that single title for all
    20 rows, and `grep -n "run-name" .github/workflows/git-data-cutover.yml` finds nothing). A title that matches
    exactly `^git-data cutover \(#5274 / ADR-220 / ADR-239\)$` is a LEGACY row and its mode is read from step
    conclusions (`gh run view <id> --json jobs`: job `cutover`, which mode-specific steps concluded and which were
    skipped; the build PR names the exact step names after reading the job's step list), the surface the d6 reader
    already uses. Until PR-W lands, and for every run that predates it afterwards, the interim stamp guard of W3
    therefore reads legacy titles through step conclusions; refusing them would make W3 refuse forever, and skipping
    them would blind the guard to the rehearsal rollbacks it exists to catch. A legacy row whose step conclusions
    cannot be read or do not identify a mode is a refusal (never a skip). A title that is neither a pattern above
    nor the legacy title is a refusal.

  The same read requires `headBranch == main` and `event == workflow_dispatch`, and carries an explicit `--limit`
  (working value 100, the build PR fixes it); a list that does not reach back past the stamp's own time (the oldest
  returned row is newer than the stamp and the list is full) is a refusal, so a rollback run newer than the stamp can
  never fall outside the window and read as "none". What a prior run DID is read from step
  conclusions (`gh run view <id> --json jobs`: job `wipe`, the named steps of W9 and W11), which is the surface the
  d6 reader already uses, never from a "recorded phase". Adding `run-name:` moves the `WF-inputs-refs` pin once more
  (it gains the `inputs.mode` and `inputs.volume_id` references in `run-name`) and needs its own exact-string census
  row.
- **No re-run of a wipe mode.** `GITHUB_RUN_ID` is public and unchanged across `gh run rerun`, and a re-run starts
  from a changed world (a volume may be detached). W1 refuses `GITHUB_RUN_ATTEMPT != 1` for both `mode=wipe` and
  `mode=wipe_finish` (the precedent is the retired `web-host-reboot.yml` rows of `infra-credential-tiers-8209.md`:
  "`github.run_attempt` must be 1"); the continuation of an interrupted wipe is a NEW typed dispatch, section 5.

### 2.2 Job shape: a separate `wipe` job in the same file, not a sixth arm of `cutover`

Resolved by the plan-default reading recorded in `decision-challenges.md` (taste row; both readings keep the
assertion and the delete in one session). CTO F5 says "single job"; that is about
the assertion and the delete living in ONE job so they share one session. It does not require the existing
`cutover` job. Reasons for a second job inside `git-data-cutover.yml`:

1. The loader exports `HCLOUD_TOKEN` (root on any host through rescue, rebuild or re-attach, ADR-241 Context) and
   the rest of the privileged project into `$GITHUB_ENV`. In `cutover`, every step after it would see them while
   the git-data root key and the SSH bridge are live, and the arms that do not wipe would carry a write token they
   never use. In a dedicated job the loader is placed after the identity reads and the host assertion (W4 to W7) and
   immediately before the first write, and the census can pin that job's own step order. Three reads still run AFTER
   the loader (W10, W10b, W12); they are the reason the containment rules below exist, not an exception to them.
   **What this does NOT give (corrected claim):** a dedicated job does not
   contain the token inside W9 and W11. The plain name and `TF_VAR_hcloud_token` both stay in `$GITHUB_ENV`, so
   `env -u HCLOUD_TOKEN` alone is NOT containment: it leaves `TF_VAR_hcloud_token`, `TF_STATE_AWS_*`/`AWS_*` (the R2
   state key) and `DOPPLER_TOKEN_TF` (a workplace-scope Doppler token) visible to the child. The root key and the
   write token also COEXIST from W8 through W10 (W10 needs ssh), so "the token and the root key never coexist" holds
   only for the arms that do not wipe, not for this job. Design requirements (build PR, census-pinned): every ssh
   child and every step that runs repo code between W8 and the end of the job runs under an `env -i` allow-list of
   exactly what it needs (the precedent is the retired `web-host-reboot.yml` rows of `infra-credential-tiers-8209.md`,
   whose never-pooled, snapshot, reboot and summary steps each ran under an `env -i` allow-list pinned by a
   workflow test); `$GITHUB_ENV` blanking and the read-only read-back are in section 2.3 (W11b, W12); no
   third-party `uses:` action runs after W8 (the loader and the SSH bridge are LOCAL actions; the workflow's
   `uses:` pin set moves deliberately, see section 6; W2's remote Doppler CLI action runs before W8).
   - **Scope of the allow-list rule (corrected).** The loader's `$GITHUB_ENV` export is visible to EVERY later step of
     the job that is not itself wrapped, not only to the steps that run repo code or ssh. `TF_VAR_hcloud_token`,
     `TF_STATE_AWS_*`, `AWS_*` and `DOPPLER_TOKEN_TF` stay exported for the rest of the job, and W11b blanks only the
     plain `HCLOUD_TOKEN` name. So the rule's scope is every step after W8 that executes anything, explicitly
     including the always-run teardown (W13) and the guard and blanking steps; a local composite action's `post:`
     hook would also be in scope. Verified in this tree: neither `cf-tunnel-ssh-bridge` nor `infra-credentials` can
     declare a post-job hook (both are `using: composite`, and the bridge's header says a composite action cannot
     register one), so the requirement is that no later change adds one, pinned by a census row on the two actions'
     `runs.using`.
   - **Scrub rule, one per context (stated here for the wipe; `design-9943-liveness-precheck.md` section 4 states the
     other context and the two cross-reference each other).**
     (1) **After the bridge or the loader: the `env -i` allow-list**, the rule of the bullet above for W9 to W13 and of
     `design-9943-liveness-precheck.md` for its three reads, which all run after the bridge. A deny-list cannot work
     there: the bridge (W6) appends `TUNNEL_SERVICE_TOKEN_ID`, `TUNNEL_SERVICE_TOKEN_SECRET`, `SERVER_IP`,
     `CLOUDFLARED_PID`, `CI_SSH_KEYFILE` and `WEB_HOST_SSH` to `$GITHUB_ENV`, and the loader (W8) exports an
     open-ended key set.
     (2) **Before the bridge: a deny-list, the wipe's own rule and not a citation of 9943.** W4 (Hetzner identity read)
     and W5 (Better Stack read) are the only Doppler-sourced reads that run BEFORE W6 and W8, so no bridge or loader
     name is in their environment yet. They therefore run their child under the six-flag deny-list
     `env -u DOPPLER_TOKEN -u AWS_ACCESS_KEY_ID -u AWS_SECRET_ACCESS_KEY -u SHELLOPTS -u BASH_ENV -u BASHOPTS`,
     never the narrower `env -u DOPPLER_TOKEN` alone, and ONLY while that ordering holds: a census row pins that no
     step before W5 appends to `$GITHUB_ENV` (the same writer census as the 9943 design) and that W4 and W5 precede
     W6; if either stops being true the two reads move to the `env -i` allow-list of context (1). The live poll
     library (`scripts/lib/git-data-boot-signal-poll.sh`) strips only the first three of the six, so W5 does not
     reuse its `env -u` form unmodified.
     `flip-preconditions-report.md` section 1.1 uses a six-flag deny-list as a deliberate owner-terminal form (an
     owner's shell has no bridge or loader environment); it is a different context, not a third copy of this rule, and
     is not edited by this design.
   - **Masking is defence in depth, not containment.** The loader masks each literal value per line; that does not
     cover derived forms (base64, URL-encoded, JSON-escaped, one line of a multi-line value split off). It is relied on
     and pinned (a census row that the loader still masks), and a second census row pins that no step prints the
     environment (`env`, `printenv`, `set`, `export -p`, `declare -x`, `doppler secrets` without `--plain` and a
     named secret, or any command whose output is the environment); a step that must show a value prints a digit
     count or a fixed word.
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

Job gating for both wipe modes (`wipe` and the re-entry mode `wipe_finish` of section 5, S3): `cutover` gains
`if: inputs.mode != 'wipe' && inputs.mode != 'wipe_finish'` and `wipe` gains
`if: inputs.mode == 'wipe' || inputs.mode == 'wipe_finish'`. A job skipped by its own `if:` asks for no environment
approval and starts no runner, so `wipe_finish` never starts `cutover` (whose confirm step would reject the unknown
mode after an approval and email as a cutover failure). Both `if:` strings are pinned in full, and the closed `mode`
choice gains both words. `notify-failure` needs MORE than `needs: [cutover, wipe]` and a mode word. As written it is
keyed on `needs.cutover.*` only, its `if:` is the pinned expression `always() && (needs.cutover.result == 'failure' ||
needs.cutover.result == 'cancelled') && needs.cutover.outputs.started != 'false'`, and its body maps a run with no
finalizer output to "STATE UNKNOWN ... check the flag in prd, the freeze sentinel and both hosts" with an
unfreeze remedy. A wipe that fails after the detach would read as that unfreeze-flavoured message, which is wrong
(the wipe never froze or wrote a flag) and hides the one fact the owner needs (a volume may be detached). Design
requirements:

- `wipe` job outputs: `mode`, `started` (as `cutover`'s), and `phase`, a closed vocabulary
  `detach_attempted | detached | delete_attempted | delete_sent | deleted`, written by the progress markers of
  section 2.3 (W9a, W9, W11a, W11, W12). **A marker is written BEFORE the irreversible call it names**
  (`detach_attempted` before W9's detach POST, `delete_attempted` before W11's DELETE) and the after-success markers
  (`detached`, `delete_sent`, `deleted`) are kept. The repo's own precedent is this order: the cutover's
  `freeze_held` and `flag_write_attempted` markers are touched before the mutating call and mean "may have run, not
  succeeded". The before-call marker is its own tiny preceding step, so it is committed before the call starts and is
  not lost if the call's own step is killed (the build PR verifies that behaviour on the stub run). **An ABSENT
  `phase`, or the value `pre_detach` if any step ever writes it as a default, means UNKNOWN, never "nothing
  changed"**: the runner may have been lost, or the detach POST accepted with its poll timed out, before any
  after-success marker. UNKNOWN is resolved only by a read of the volume (`GET /volumes/<id>`, read-only token). This
  applies everywhere the phase is read: the notify words, the S-table (S1 included) and the runbook.
- its own `if:` clause: `(needs.wipe.result == 'failure' || needs.wipe.result == 'cancelled') &&
  needs.wipe.outputs.started != 'false'`, OR-ed with the existing `cutover` clause; a skipped job (the other
  mode's) must not email.
- its own body words, never the unfreeze remedy: `WIPE_STATE_UNKNOWN` (absent phase: names the read-only Hetzner
  volume read and says NOTHING is known to be unchanged, not the freeze sentinel), `DETACH_ATTEMPTED_UNCONFIRMED`
  (state S2: the volume may be attached, detaching or detached), `VOLUME_DETACHED` (the plaintext volume is detached
  and not deleted: state S3, with the exact re-entry command of section 5), `DELETE_ATTEMPTED_UNCONFIRMED` and
  `DELETE_SENT_UNCONFIRMED` (state S4: read the volume list read-only before anything else) and
  `VOLUME_DELETED_TEARDOWN_FAILED` (phase `deleted` with a later failure: the end event is already true, only
  teardown or the summary failed).
- `case "$MODE"` lists BOTH wipe words (`proof|flip|rollback|unfreeze|redeploy|wipe|wipe_finish`); omitting
  `wipe_finish` would map a failed re-entry run to `MODE=unknown`. The test row "a failed `mode=wipe` never produces
  `MODE=unknown`" has a twin for `wipe_finish`.
- The census rows that pin `notify-failure` move deliberately and are re-pinned to the new exact values, never
  loosened: `N-if` (today `needs == "cutover"` and the whole `if:` string), `N-jobkeys` (the job key set stays
  `{needs, if, runs-on, timeout-minutes, permissions, steps}`) and `N-secrets` (still exactly `GITHUB_TOKEN` and
  `RESEND_API_KEY`, no Doppler token, no Hetzner token). The notify `EXPR_OK` list of `git-data-cutover-access.test.sh`
  (today `needs\.cutover\.result` and `needs\.cutover\.outputs\.(mode|finalizer_ran|freeze_held|recovery_failed|
  probe_failed|gc_timer_stopped|started)`) gains the `needs\.wipe\.result` and `needs\.wipe\.outputs\.(mode|started|phase)`
  forms and nothing wider.

### 2.3 Step order inside `wipe` (each step fail-closed; later steps `if: success()`, never `always()` except the token blanking W11b and teardown)

| # | Step | Credential bound | What it does |
|---|---|---|---|
| W1 | confirm | none | mode/token/`volume_id` shape (above); refuses `GITHUB_RUN_ATTEMPT != 1` (section 2.1) |
| W2 | checkout, Doppler CLI | none | as `cutover` |
| W3 | flag/stamp/pin precheck | `DOPPLER_TOKEN_PRD` only. It is the only step of its JOB naming that secret. The existing census row (`AC9: DOPPLER_TOKEN_PRD is named only by the flag precheck step`, scanning every job) is amended deliberately to name exactly two sites, `cutover.flag_precheck` and `wipe.flag_precheck`, with the same pinned env shape; it is not loosened to "any step". | `git-data-flag-precheck.sh` gains `FLAG_MODE=wipe`: flag must read exactly `true`; `GIT_DATA_LUKS_CUTOVER_AT` must be present, parseable and at least 7 days old (the runbook's soak follow-through floor; the lb-weight-gate's 3 days is a different gate); the pin is read and written as today. Anything else: `verdict=wipe_precondition_flag_not_true`, `wipe_precondition_stamp_absent` or `wipe_precondition_soak_not_elapsed`, exit 5. The stamp is only trustworthy once the rollback arm clears it (`design-rollback-rehearsal.md` F-D: today the rollback does not clear `GIT_DATA_LUKS_CUTOVER_AT`, so a rehearsal's stamp can satisfy the 7 days); until that fix has merged, W3 also requires the stamp to be NEWER than the last `mode=rollback` run. That read uses the run discriminator of section 2.1 (the closed `rollback` title pattern, with LEGACY `git-data cutover (#5274 / ADR-220 / ADR-239)` titles classified by step conclusions, `createdAt` for recency, `headBranch == main`, an explicit `--limit` that must reach back past the stamp), NOT dispatch inputs or job outputs, which `gh run list` does not expose; the rollback run counts whatever its conclusion (a failed rollback may still have changed the flag), and an unreadable list, an unclassifiable legacy row, an unparseable title or an off-pattern row is a refusal, never a skip. Until PR-W adds `run-name`, every existing run is a legacy row, so this interim guard rests on step conclusions alone. The flag is read AGAIN immediately before W9 (a second, read-only call of the same precheck; a flag that is no longer `true` refuses with `wipe_precondition_flag_not_true`). |
| W4 | Hetzner identity read (read-only) | `DOPPLER_TOKEN` -> `HCLOUD_TOKEN_READONLY` | section 3, R1-R6, under the pre-bridge scrub rule of section 2.2. The token is read from `prd_terraform` into a masked shell variable and consumed inside this same step; it is NEVER written to `$RUNNER_TEMP`, `$GITHUB_ENV`, `$GITHUB_OUTPUT` or the verdict record. Writes a verdict record under `$RUNNER_TEMP` (server id, both volume ids, `created`, an epoch, and the run binding of section 3.4: `GITHUB_RUN_ID`, `GITHUB_RUN_ATTEMPT` and a per-run random value generated in this step). The W4 epoch is the OUTER bound only; the bound that matters is the W7 epoch (section 3.4). Absent token: refuse; NEVER fall back to the read/write token (the inngest runbook's wording: "absent from prd_terraform: stop, never fall back to HCLOUD_TOKEN"). |
| W5 | fresh `boot_complete` read | `DOPPLER_TOKEN` (query creds only), the pre-bridge scrub rule of section 2.2 (not `env -u DOPPLER_TOKEN` alone) | section 3.2. Same pinned git-data tables as `git_data_served_empty_read` in `scripts/lib/git-data-boot-signal-poll.sh`. What this step proves and does not prove is section 3.2: it is boot-time evidence, at least the 7-day soak old, not a statement about now. |
| W6 | bridge, key fetch, ssh_config | as `cutover` | existing steps, unchanged |
| W7 | host assertion | none (root key via ssh_config) | ONE ssh session, section 3, H1-H10, new read-only verb in `git-data-cutover.sh`. On success it stamps the W7 epoch that bounds W9 (section 3.4). |
| W8 | load Tier-B Hetzner token, then guard | `DOPPLER_TOKEN_INFRA_PRIVILEGED` | W8 is the loader (`.github/actions/infra-credentials`), the LAST step before any write, and W8b is the guard, which MUST be the first step immediately after it (no other step, including the SSH bridge or a summary, sits between them). W8b REFUSES unless the loader's `outputs.source` equals `tier_b` (`wipe_token_source_legacy` or `wipe_token_source_unknown`): the legacy arm exports a `HCLOUD_TOKEN` read from `prd_terraform`, which a branch can plant until O11, and a destroy must never run on it. The refusal path has ALREADY lost the race against the loader's export, so before it exits non-zero W8b appends `HCLOUD_TOKEN=` (empty) to `$GITHUB_ENV`; every later `if: always()` step (W11b, W13) then carries no write token under the plain name, and runs under the allow-list rule of section 2.2 for the rest. A census row pins the `source == 'tier_b'` guard, that W8b is the first step after the loader, that the refusal path blanks the token, and that no step between W8b and W9 can bypass it (a mutation row removes the blanking and expects RED). No later step but W9 and W11 may name the write token (W10, W10b and W12 name only the read-only one; teardown names none). Everything after W8 runs under the containment rules of section 2.2 (an `env -i` allow-list, not `env -u HCLOUD_TOKEN`; no third-party `uses:` action). |
| W9a, W9 | detach | `HCLOUD_TOKEN` | W9a is a tiny step that writes the marker `wipe_progress=detach_attempted` (job output `phase=detach_attempted`) and a `$GITHUB_STEP_SUMMARY` line BEFORE W9 starts, so a runner lost mid-detach does not read as "nothing happened". W9 first refuses (`wipe_assertion_stale`) if more than ~120 s have passed since the W7 epoch (W8 installs the Doppler CLI and downloads the whole privileged project, a variable tens of seconds, so the bound is W7 to W9, not W4 to W9) and re-reads the flag (W3). Then `POST /volumes/<id>/actions/detach` and polls the returned action at a 2 s interval for at most 30 attempts (60 s). Any end state other than `success` (`error`, still `running` after the 30th attempt, an unreadable body) refuses with `wipe_detach_not_confirmed`, whose body says the volume may be attached, detaching or detached and routes to S2. The poll counts toward the W7-to-W11 bound of section 3.4 (it is inside the window, not exempt from it). On `success`, writes `wipe_progress=detached` to `$GITHUB_OUTPUT` (the job output `phase=detached`) and a line to `$GITHUB_STEP_SUMMARY` IMMEDIATELY, because W13 runs only on success and a failed run would otherwise carry no marker. |
| W10 | post-detach host read | none | same bridge: the by-id link is gone AND the LUKS store still serves (uncached `dd iflag=direct` block read of `/dev/mapper/git-data` plus a root listing, the `git-data-liveness.sh` checks) AND the one-session `store-verified` facts still hold. Detaching the wrong volume would show here, before the irreversible step. Runs under an `env -i` allow-list that carries no Hetzner token, and under an explicit `timeout`. |
| W10b | Hetzner re-read of the target (read-only) | `HCLOUD_TOKEN_READONLY`, re-fetched in this step | `GET /volumes/<id>`, immediately before the delete: `.name == soleur-git-data-store`, `.server == null`, `.protection.delete == false`, and `GET /volumes?name=soleur-git-data-luks-store` still lists exactly one attached volume. Nothing else re-reads Hetzner state between R1-R6 and the `DELETE`, and the W10 host read proves the mapper still serves, not the identity of the volume about to be deleted. Refuses with `wipe_target_changed` (state S3, detached). **Where the read-only token comes from after the loader (one route, census-pinned):** the step itself holds `DOPPLER_TOKEN: secrets.DOPPLER_TOKEN` (the loader deliberately does not export it) and fetches `HCLOUD_TOKEN_READONLY` from `prd_terraform` into a masked shell variable consumed inside the same step, then runs the curl child under the `env -i` allow-list carrying that one name and no `DOPPLER_*` name; it is never stashed in `$RUNNER_TEMP` or `$GITHUB_ENV`. **The single exemption:** the fetch itself (`doppler secrets get HCLOUD_TOKEN_READONLY ...`) is an executing child that needs `DOPPLER_TOKEN`, and it runs after the loader, so it too runs under `env -i`, with an allow-list carrying only that one credential name (`DOPPLER_TOKEN`) plus the non-secret `PATH` (and a `HOME` or config directory if the CLI needs one; the build PR names and pins them). It is the ONLY child in `wipe` whose allow-list carries a `DOPPLER_*` name, and the census row pins that exact shape (a mutation that adds any other name, or a `DOPPLER_*` name to any other child, goes RED); every other CHILD carries no `DOPPLER_*`, `TF_VAR_*`, `AWS_*` or `TF_STATE_AWS_*` name. The `secrets.DOPPLER_TOKEN` site count is section 6's row (five sites in `wipe`: W4, W5, W6's bridge input, W10b, W12). |
| W11a, W11 | delete | `HCLOUD_TOKEN` | W11a writes the marker `wipe_progress=delete_attempted` (job output `phase=delete_attempted`) and a summary line BEFORE W11 starts. W11 refuses (`wipe_assertion_stale`) if more than the build's bound (working value ~300 s: the W9 bound plus the detach poll and the W10 host read) has passed since the W7 epoch. `DELETE /volumes/<id>`, expect 204; on 2xx writes `wipe_progress=delete_sent` (job output `phase=delete_sent`) and a summary line immediately. |
| W11b | blank the write token | none | `if: always()`, ordered immediately after W11 so it runs whether W11 succeeded, failed, timed out or was skipped. It appends `HCLOUD_TOKEN=` (empty) to `$GITHUB_ENV`, so the plain name no longer carries the write token in W12 and teardown. It does NOT blank `TF_VAR_hcloud_token`, `TF_STATE_AWS_*`/`AWS_*`, `DOPPLER_TOKEN_TF` or the other loader keys, which stay visible to any step outside the allow-list: that is why every later step, including the always-run teardown W13, runs under the `env -i` allow-list of section 2.2 and not on this blanking alone. |
| W12 | read-back (the end event) | `HCLOUD_TOKEN_READONLY`, re-fetched in this step by the route of W10b, child under the `env -i` allow-list | `GET /volumes/<id>` must be 404 AND `GET /volumes?name=soleur-git-data-store` must list zero volumes; the LUKS volume must still list exactly one and still be attached. On success writes `wipe_progress=deleted` (job output `phase=deleted`). A 404 with the name still listed means the id was wrong (the registry precedent in `apply-web-platform-infra.yml`, "returned 404, but a volume named ... still exists"), which is its own red verdict. |
| W13 | summary, teardown | none | evidence lines to `$GITHUB_STEP_SUMMARY`; shred root key, ssh_config, known_hosts, pin (as the `cutover` teardown step). `if: always()` for the teardown part, therefore under the `env -i` allow-list of section 2.2 (it names no secret and runs no Hetzner call). |

The two API calls are separate, recorded steps because Hetzner refuses `DELETE` on an attached volume; they are
also why a failure BETWEEN them is a defined state (section 5, S3), not an undefined one.

**Job budget (`timeout-minutes` for `wipe`, derived, not copied from `cutover`'s 120).** `cutover`'s 120 is sized on a
fan-out swap of up to ~80 minutes; the wipe has none, and a bound that large would let a stuck step hold the root key,
the bridge and the write token for two hours. The derivation, from the bounds already fixed above: setup before W4
(checkout, Doppler CLI, W1 to W3) at most 5 min; W4 to W7 inside the W4-epoch outer bound of 15 min (section 3.4);
W7 to W11 inside the W7-epoch bound of ~300 s, i.e. 5 min (W8's loader, the 60 s detach poll, W10 and W10b are inside
it); W11b, W12 and W13 at most 5 min. Sum 30 min, so the job pins `timeout-minutes: 30`, every step also carries its
own `timeout-minutes` or `timeout` no larger than its share, and a census row (a `wipe`-specific twin of `WF-timeout`,
which today asserts `cutover`'s `>= 120`) pins the exact value and that it is at least the sum of the stated bounds.
The queue wait behind `web-1-swap` and the environment-approval wait are not job run time; the build PR confirms that
on the stub run and, if either counts, re-derives. `wipe_finish` (section 5) has no W4-W7 reads of that size and the
same job value is a ceiling, not a target. A timeout reaches the notify job as `failure` or `cancelled` (both are in its `if:`)
with the last progress marker; a lost runner reaches it with none, which reads UNKNOWN.

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
`git_data_served_empty_sql`), via `--only-secrets BETTERSTACK_QUERY_*` under the pre-bridge scrub rule of section 2.2 (not `env -u DOPPLER_TOKEN` alone). The shared
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
absence below) or recorded as a one-off owner read on #6897 before the dispatch. An absent signal refuses either way. Two rules on that
signal (design requirements): (i) **no names leave the host.** Top-level names on the plaintext volume can be tenant
identifiers, and #6897 is a PUBLIC repository, so the owner read and any log or summary line carry COUNTS and one
digest (a hash over the sorted listing) only, never a name; the verdict words stay fixed. (ii) **The allowlist is
path-typed, not name-only.** An entry named `repositories` that is a symlink or any non-directory is OFF the
allowlist (`wipe_boot_layout_signal_offlist`), as is an allowlisted dotfile that is a directory or symlink; the listing
uses `find -mindepth 1 -maxdepth 1 -printf '%y %f\n'`-style type-aware output (no `-L`, no following), and a
symlink is never dereferenced, so a link cannot make a populated tree read as the empty `repositories`.

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
| H9 | the host is the instance Hetzner names: `/var/lib/cloud/data/instance-id` equals the R1 server id. NOT yet verified for the Hetzner datasource; the build PR confirms it against the rung-2 rehearsal host and falls back to refusing (not to the metadata endpoint, which `nft_metadata_drop` blocks by design). | new | `wipe_instance_mismatch` |
| H10 | device generation bound: the host boot time (now minus `/proc/uptime`) must be at or before the W5 row's `dt` and the row's `dt` must fall within a bounded window after that boot time (the build fixes it, from the rung-2 rehearsal host's measured boot-to-`boot_complete` time); otherwise the host rebooted after the row (or the row belongs to another generation) and the boot-time count says nothing about this device. | new | `wipe_boot_generation_mismatch` |

The deliberate absence, revised: the wipe does NOT mount the plaintext volume and does NOT re-count `repositories/`
through a writable path; counting means mounting or snapshotting a device whose retention is being ended precisely
so it is never written. The boot-time count (W5) is the emptiness evidence for the `repositories/` tree. What the
destructive session adds is the part that can be asserted without touching the device: the kernel read-only flag, the
ABSOLUTE zero write and discard counters since enumeration and the device-generation bind (H8, H10), plus H6 and
H7. The layout-independent signal of section 3.2 is the one place a read-only dm snapshot in the destructive
session may be needed (the same unit the bootstrap uses, never a mount); if the build PR takes that route, this
paragraph's "does NOT re-count" narrows to "does not re-count `repositories/` and does not mount".

### 3.4 Same-session binding and the time bounds

W4 stamps a run binding and an epoch into the verdict record; W7, W9, W10, W10b and W11 each re-read the record and
refuse if the binding differs from this run's own (`wipe_assertion_stale` for a stale epoch). The binding is NOT
`GITHUB_RUN_ID` alone: that value is public and is unchanged across `gh run rerun`, so it labels a run but is not a
nonce, and a stale or copied record from an earlier attempt would satisfy it. The binding is the triple
`GITHUB_RUN_ID`, `GITHUB_RUN_ATTEMPT` and a random value generated in W4 for this run (not derived from any public
value); the record lives only under `$RUNNER_TEMP` of this runner, holds no token, and a mismatch on any of the three
refuses. Together with the W1 refusal of `GITHUB_RUN_ATTEMPT != 1`, a re-run cannot reuse a record. Two
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
   `plugins/soleur/test/terraform-target-parity.test.ts` pins both jobs' target sets; and the post-apply backstop
   `git_data_host_post_apply_assert` (in `tests/scripts/lib/git-data-host-replace-gate.sh`, delivered by the sibling
   PR #10155, which this branch's reverted Phase 2 duplicated), which asserts that the saved plan shows
   `hcloud_volume_attachment.git_data` (and the LUKS one) with a `create` and `hcloud_volume.git_data` with no
   `delete|forget` (both volumes in `replace` mode, the plaintext volume in `rotate` mode). All of these change when
   the volume leaves Terraform. State as read: #10155 is MERGED (2026-10-12) and the function is present on
   `origin/main` AND on this branch (merge commit `d7878f4e93` is an ancestor of this branch's HEAD; read in
   `tests/scripts/lib/git-data-host-replace-gate.sh`); its suite header names
   rows PA1-PA8 (the review brief said PA1-PA7; PA8 is the output-discipline row), so the row set is RE-READ at
   build time and none of the retired names (`git_data_post_apply_gate`, the old PA1/PA8/PA10) is used.

Resolved sequence (technical fork, no ruling needed): three merges and two owner-named dispatches.

| Order | Step | Contents | Gate |
|---|---|---|---|
| 1 | **PR-W (mechanism)** | the `wipe` job, `FLAG_MODE=wipe`, the new read-only host verb, the `volume_id` input, tests (section 6), runbook "The wipe" section, a rehearsal-root variant that passes `git_data_volume_id = ""`, and a gate condition (below), the `notify-failure` wipe clause, progress markers and the `run-name` discriminator (sections 2.1 and 2.2), the S3 re-entry arm (section 5) and the wedge test (below). Touches NO rung-2 hash-bound file AS DESIGNED, so the two-PR payload sequence is NOT triggered; if the layout-independent emptiness signal is added to `git-data-bootstrap.sh` (section 3.2(b)) that premise is false for this PR and the sequence applies. | normal review; `git-data-cutover.yml` carries the no-admin-merge restriction (the issue says so) |
| 2 | rung-2 rehearsal of the empty-id render (owner-gated: it boots a paid host), dispatched from `main` with the empty-id variant, then an evidence-only PR | `RUNG2_VAR_DIVERGENCE` names `git_data_volume_id` (it is on the closed allowlist `GIT_DATA_RUNG2_DIVERGENCE_ALLOWLIST` in `git-data-birth-readiness-gate.sh`); the capture's PASS predicate for this arm is `plaintext_volume=absent plaintext_journal=absent plaintext_empty=yes served_repos=0` (the existing predicate requires `present`/`dirty`) | owner names the dispatch |
| 3 | **the wipe**, `mode=wipe` | sections 2-3 | owner names the command and the id; environment reviewer approves |
| 4 | **PR-C (record and removal)** | the Hetzner delete evidence (run URL, W12 lines); HCL removal of the two resources with `removed { lifecycle { destroy = false } }` blocks and the matching `-target` lines; `git-data.tf` passes `git_data_volume_id = ""`; ledger row `hcloud_volume.git_data` deleted; the plan-time gate, the post-apply backstop `git_data_host_post_apply_assert` and their suites amended (below); ADR-239 amendment; Art. 30 note staged for the CLO (PA-36); runbook; closes #6897 on its merge | **depends on #10155 having merged first** (it has, as read; the dependency is a build-time re-read, not an assumption), plus the #8571 precondition of section 7; the CLO date 2026-11-12 is the outer bound |

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
says the replace lever is held and the drift plan is expected to show the create in that interval. **The bound is a
recorded commitment, not a machine-enforced limit** (nothing in a workflow measures dispatch-to-merge time). A breach
returns to the owner, who decides and records on #6897 whether to extend it, and once the date 2026-11-12 has passed
it returns to the CLO per ADR-239 Amendment 2026-10-12 (a second slip returns to the CLO); no agent extends it.

A second residual, also stated: the LIVE host's `user_data` still names the deleted id
(`GIT_DATA_PLAINTEXT_VOLUME_ID` in the rendered runcmd) until its next replace. `runcmd` is once per instance, so a
reboot does not re-run the bootstrap; a manual bootstrap re-run would FATAL closed
(`plaintext_unverified reason=source`, no marker, erasure refused). The runbook row says so and the next replace
boots the already-rehearsed empty-id render.

A third residual, and a PRECONDITION of PR-C rather than an independent item: after the flip the served store is
populated, and `git-data-bootstrap.sh` FATALs (`luks_residue`, forward-only) when first boot finds a non-empty served
store. **This is not a PR-C effect: it applies to ANY ForceNew replace of the git-data host after the first flip,
including today's rendering that still passes the plaintext volume id.** The "emergency replace lever" is therefore
not healthy between the flip and #8571 (copy mode), with or without the wedge: the runbook text for the replace lever,
here and in the wedge paragraph above, says a replace after the flip re-runs first boot against a populated LUKS
volume and fails closed (git-data dark, data intact), and promises users nothing stronger. PR-C renders `git_data_volume_id = ""`, a ForceNew change of the host, so the first replace after PR-C (the
only remediation lever for a dead host) re-runs first boot against a populated LUKS volume and fails closed:
git-data stays dark with its data intact. Availability and Art. 17 handling are what is at risk, not the data. The
populated-store rotation is #8571 (copy mode). Merging PR-C therefore requires #8571 (or an explicit, recorded owner
acceptance of this window) first; section 7 lists it and section 8 repeats it.

## 5. Failure states of the irreversible pair (defined, not improvised)

| State | Reads as | Recovery (every step owner-authorized, never automatic) |
|---|---|---|
| S1 phase absent (or `pre_detach`), any failure before or without a marker (notify word `WIPE_STATE_UNKNOWN`) | UNKNOWN, never "nothing changed": the runner may have been lost after a detach or delete was accepted but before any after-success marker, and a step that failed before W9a is indistinguishable from that by `phase` alone | read `GET /volumes/<id>` and `GET /volumes?name=soleur-git-data-store` with the read-only token. Attached to the R1 server: nothing changed, fix the cause and re-dispatch. Detached: S3. Absent (404): S4 or S5. |
| S2 `phase=detach_attempted` (or `wipe_detach_not_confirmed`; notify word `DETACH_ATTEMPTED_UNCONFIRMED`) | the detach POST may have been accepted; the volume may be attached, detaching or detached | read `GET /volumes/<id>` (read-only token); if attached, nothing changed; if detached, S3 |
| S3 detached, not deleted (`phase=detached`; notify word `VOLUME_DETACHED`) | the volume is detached and intact; W10, W10b or W11 did not complete | W10's refusal names why. If the LUKS store reads unhealthy, the wrong volume may have been detached: stop, the owner decides a re-attach (`POST /volumes/<id>/actions/attach`) and nothing is deleted. Otherwise the continuation is the typed re-entry arm below. A plain re-dispatch of `mode=wipe` REFUSES at R4 (`wipe_not_attached_to_current_host`), by design, and a `resume` input on `mode=wipe` is rejected because it would skip the host assertion. |
| S4 `phase=delete_attempted` or `phase=delete_sent` (notify words `DELETE_ATTEMPTED_UNCONFIRMED`, `DELETE_SENT_UNCONFIRMED`) | the DELETE may have been sent (`delete_attempted`) or returned 2xx (`delete_sent`) and W12 did not confirm: the volume is gone, going, or the delete did not take | re-read read-only (`GET /volumes/<id>`, then the name list); do not re-run detach; a still-listed detached volume is S3 |
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
   the R1 server). **The arm must create its own verdict record:** these re-reads are the `wipe_finish` counterpart
   of W4 and write the verdict record of section 3.4 under this run's `$RUNNER_TEMP` (server id, both volume ids,
   `created`, an epoch and the run binding triple `GITHUB_RUN_ID`, `GITHUB_RUN_ATTEMPT` and a per-run random value),
   because W10b and W11 re-read that record and refuse on a missing or mismatched binding; an arm that only re-read
   Hetzner state without writing the record would refuse at W10b every time. A record is never carried over from the
   earlier `mode=wipe` run;
3. the LUKS store healthy: one ssh session over the bridge, the W10 checks (uncached `dd iflag=direct` block read of
   `/dev/mapper/git-data` plus a root listing, the one-session store-verified facts);
4. no emptiness evidence of unbounded age: the arm does NOT consume W5's `boot_complete` row (a volume left detached
   for a week would otherwise ride on a week-old row). It instead requires that a `mode=wipe` run on this repository
   exists for THIS volume id that detached it within a build-fixed bound (working bound 24 hours), and refuses past it:
   beyond that age the full `mode=wipe` path (a re-attach, a new assertion, a new dispatch) is the only route, which
   is an owner decision recorded on #6897. **How that run is read (job outputs are not exposed by `gh run list`):**
   the control surface is the run discriminator of section 2.1 plus step conclusions, never a job output. `gh run list
   --workflow git-data-cutover.yml --json databaseId,displayTitle,createdAt,conclusion,headBranch,event` selects runs
   whose `displayTitle` matches `^git-data wipe [0-9]{1,12}$` in full, with the digits EQUAL to the typed `volume_id`,
   `headBranch == main`, `event == workflow_dispatch` and `createdAt` inside the bound; then `gh run view <id> --json
   jobs` must show, in job `wipe`, the W9 detach step with conclusion `success` and the W11 delete step with a
   conclusion other than `success` (and, for the newest such run, no later `deleted` run for the id). The text of a step
   summary or annotation is human-facing and is NOT a control input; if the build wants to read a marker as text, it
   is same-repository but unauthenticated data and must be parsed against the closed vocabulary of section 2.2
   (`phase` values and a `volume=<digits>` token, anything else is a no-match). Anything unreadable, unparseable or
   multiple-matching refuses. **The 24 h bound is a policy limit, not evidence that nothing wrote**: the read is
   `server == null` at a point in time, so a re-attach and re-detach by another actor inside the window would not be
   seen; the arm's other reads (item 1 fresh, item 3 store healthy) are the evidence, the bound only limits how old
   the premise can be;
5. the flag still reads `true` and the stamp precheck of W3 still passes;
6. it then runs W8 (the `tier_b` source guard), the W7-style epoch (stamped at the head of the arm), W10b, W11, W11b
   and W12 unchanged, with the same progress markers and notify words.

If the build PR defers this arm, S3 is an accepted MANUAL API step, and the document says so rather than leaving it
implicit: after the owner records the decision on #6897 and re-reads R1-R3, R5 and R6 and a fresh `server == null`
with `HCLOUD_TOKEN_READONLY`, the delete is one request whose token is passed through a stdin curl config, never
argv or the environment (ADR-280's stdin-config library): `curl -sS -K - -X DELETE https://api.hetzner.cloud/v1/volumes/<id>`
with the bearer header supplied on stdin, expect 204, then the W12 read-back by hand. The manual form uses a
read/write token outside the workflow's environment gate and census; that is why the typed arm is the default.
Conditions on the manual form (design requirements, and the reason it is a deviation, not a procedure):

- **How the token is obtained.** The Tier-B write token is delivered ONLY by the workflow's loader (section 1); this
  design defines no sanctioned hand route to it. A manual delete therefore means the owner reading the privileged
  Doppler project outside the census, which is exactly the tier bypass ADR-241 exists to prevent, so it is an
  owner-only act and an agent never performs or prepares it.
- **Handling.** The token is never written to shell history or to any file, never passed as an argument, never
  `echo`ed or `cat`ed; it is held in a shell variable filled by a builtin (`read -rs`) and reaches curl on its stdin
  config through a builtin (`printf`), then the variable is unset. A pasted-in-chat or `!`-prefixed form is refused
  (`hr-never-paste-secrets-via-bang-prefix`).
- **Record.** Each manual delete is recorded on #6897 as an owner-accepted deviation (who, when, why the typed arm
  was not available, the volume id, the status code and the read-back result), with ids, counts and status codes
  only, never a token or a volume's content, and the next owner-gated step is a W12-style read-back by hand.

**Recovery for the assertion that can never pass again (H8/H10 reboot dead-end), accepted residual.** After ANY
reboot of the git-data host the boot-time evidence is permanently stale: cloud-init `runcmd` is once per instance,
so no new `boot_complete` row follows, the bootstrap's kernel read-only flag (`blockdev --getro`) reads `0` (H8
`wipe_ro_flag_lost`) and the host boot time is after the row (H10 `wipe_boot_generation_mismatch`). The first-boot
logic also refuses forever on a populated store (`luks_residue`), so a host replace cannot refresh the evidence
either (section 4, third residual); a re-attach and re-assertion cannot help because the mismatch is about the host,
not the volume. This design does NOT define a machine path out and does not widen the assertion to make one: the
destroy would then rest on evidence that no longer describes the device. It is an ACCEPTED RESIDUAL with a defined
route: the refusal verdicts name the cause, the owner records the situation on #6897, and the owner brings an
owner-supplied, recorded emptiness read (counts and one digest only, section 3.2 rule (i), taken from a read-only
snapshot of the detached or attached device by a procedure the CLO has seen) to the CLO for a ruling on whether the
retention can end without the automated assertion; no agent decides it, and no flag or input on `mode=wipe` accepts
such a read in this design. The retention date 2026-11-12 stays the outer bound and a second slip returns to the CLO
(ADR-239 Amendment 2026-10-12), so a reboot late in the window is a CLO matter, not an engineering retry.

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
  pinned env shape (the `AC9` row, which today asserts a single `("step", "flag_precheck")` site and `len(jobs) == 2`,
  is amended deliberately, not loosened); the Tier-B loader appears once, in `wipe`, after W7 and before W9;
  **W8b, the `outputs.source == 'tier_b'` guard, is the FIRST step after the loader** (a mutation row inserts a step
  between them, or moves the guard, and expects RED), its refusal path blanks `HCLOUD_TOKEN` in `$GITHUB_ENV` before
  it exits (a mutation row removes the blanking and expects RED, because the legacy arm has already exported its token
  by the time the guard refuses and every later `if: always()` step would carry it), and no step between it and W9
  can bypass it; `HCLOUD_TOKEN` is referenced as a VALUE SOURCE (a request's bearer) only by W9 and W11; the only other
  occurrences of the literal are the two BLANKING writes `HCLOUD_TOKEN=` (empty) to `$GITHUB_ENV` in W8b's refusal
  path and in W11b, and the row distinguishes the two (a value-source reference anywhere else, or a blanking write
  that assigns a non-empty value, goes RED; without the distinction the row is RED by construction).
  `HCLOUD_TOKEN_READONLY` is referenced only by W4, W10b and W12,
  each of which re-fetches it by the one route of W10b (`secrets.DOPPLER_TOKEN` in the step's own env, consumed in the
  same step, never written to `$RUNNER_TEMP`, `$GITHUB_ENV` or `$GITHUB_OUTPUT`; the fetch child is the single
  `DOPPLER_TOKEN`-carrying `env -i` exemption of W10b). **`secrets.DOPPLER_TOKEN` site census (recounted from
  `git-data-cutover.yml`):** the `cutover` job has FIVE sites today (step `secrets_check`'s
  `DOPPLER_TOKEN_PRESENT: ${{ secrets.DOPPLER_TOKEN != '' }}`, the `CF Tunnel SSH bridge` step's
  `doppler-token: ${{ secrets.DOPPLER_TOKEN }}`, and the step envs of the web-fleet redeploy, the per-host
  `git_data_store=` assertion and the `finalizer`; the header comment line naming the secret is not a site). `wipe`
  adds FIVE more, so the workflow total moves from 5 to 10: W4, W5, W6 (the bridge step, which W6 repeats as in
  `cutover`, so W6 passes `doppler-token: ${{ secrets.DOPPLER_TOKEN }}`), W10b and W12. The census row pins the per-job
  count and the per-step list (a count alone would hide a moved site), and the `WF9` referenced-secret SET is
  unchanged. The `liveness_precheck` step of `design-9943-liveness-precheck.md` adds one more `cutover` site if it lands
  first, so the numbers are re-read at build time, never copied. If W8 also passed the loader's `doppler-token-legacy: ${{ secrets.DOPPLER_TOKEN }}` input the `wipe`
  count would be six and the total eleven (see the open item on omitting that input); every step after W8 that executes anything (repo code, ssh, curl, and the
  always-run W11b and W13 included) runs under an `env -i` allow-list that carries NO `TF_VAR_*`, `AWS_*`,
  `TF_STATE_AWS_*` or `DOPPLER_*` name (`env -u HCLOUD_TOKEN` alone fails the row, because the loader exported the
  token under two names and the state key and a Doppler token besides, and there is no redundant `env -u HCLOUD_TOKEN`
  inside the allow-list: `env -i` already drops it); W11b is `if: always()` and blanks `HCLOUD_TOKEN` in
  `$GITHUB_ENV`; no third-party (remote) `uses:` appears after W8, and neither local action used after W8 declares a
  `post:` hook (`runs.using` is `composite` for both); the loader still masks every string value per line; **no step in
  `wipe` prints the environment** (`env`, `printenv`, `set` with no argument, `export -p`, `declare -x`, `compgen -e`;
  a mutation row adds one and expects RED), since masking covers literal lines and not derived forms; the new job has
  no `secrets` reference outside the allowed set; `notify-failure` carries `wipe`.
- **Workflow shape census (these pins move with a third job and a new input; each is re-pinned deliberately).** In
  `git-data-cutover-access.test.sh` (AC9 / G7 and the `WF-` rows): the literal `WF-jobs` row, today
  `sorted(jobs.keys()) == ["cutover", "notify-failure"]`, becomes the three-job list; the `AC9: DOPPLER_TOKEN_PRD ...`
  scan's `len(jobs) == 2` moves with it; `sorted(inputs.keys()) == ["confirm", "lineage", "mode"]` (gains
  `volume_id`); `WF-inputs-refs` (`only inputs.confirm, inputs.lineage and inputs.mode are referenced`, gains
  `inputs.volume_id`, and the `run-name` references of section 2.1); an exact-string row for `run-name`; the closed
  `mode` choice `proof|flip|rollback|unfreeze|redeploy` (gains `wipe` and `wipe_finish` if section 5's arm is built);
  the pinned `if:` of `cutover` (`inputs.mode != 'wipe' && inputs.mode != 'wipe_finish'`) and of `wipe`; the local-action
  set, today exactly `[cf-tunnel-ssh-bridge, notify-ops-email]` (gains `./.github/actions/infra-credentials`); the
  `cutover` job's exact key allowlist (gains `if`) and its pinned step `order`, and a `wipe`-specific `order` pin and
  `wipe` job-timeout row (section 2.3, job budget); the notify `EXPR_OK` list (gains the `needs.wipe.*` forms of
  section 2.2); and the job-level `concurrency` decision of section 2.2 (`web-1-swap` for `wipe` or an explicit census
  row that it holds none). **The tier inventory moves too:** `infra-credential-tiers-8209.md` lists
  `git-data-cutover.yml::cutover` and no `wipe` job (that row says no edit to the file was needed, which stops being
  true); PR-W adds a `git-data-cutover.yml::wipe` row there (workflow_dispatch; environment
  `web-platform-infra-apply`; `DOPPLER_TOKEN`, `DOPPLER_TOKEN_PRD` and `DOPPLER_TOKEN_INFRA_PRIVILEGED` through
  `.github/actions/infra-credentials`; **write**, one detach and one delete of the allow-listed plaintext volume;
  **B**, a new consumer of the Tier-B Hetzner write token, with the same note on the owner-only reviewer). No test
  pins that document's rows (read: the only references are path lists), so the row is a reviewed deliverable; but
  `tests/scripts/test-infra-privileged-tier-census.sh` does scan workflow files for the loader (`LOADER_USES`), so the
  new consumer is read by it and the build PR re-reads that census rather than assuming the job is invisible to it.
- **Progress markers and notify.** A stub run that is killed after W9a and before W9's detach returns leaves
  `phase=detach_attempted`; one that fails after W9 leaves `phase=detached` and the notify body carries
  `VOLUME_DETACHED` and NOT the unfreeze remedy or the `STATE UNKNOWN ... freeze sentinel` text; one killed after W11a
  carries `DELETE_ATTEMPTED_UNCONFIRMED`; a failure after W11 carries `DELETE_SENT_UNCONFIRMED`; a run with NO marker
  carries `WIPE_STATE_UNKNOWN` and never "nothing changed"; a failed `mode=wipe` or `mode=wipe_finish` never produces
  `MODE=unknown`; the before-call markers are their own steps ahead of W9 and W11 and the after-success markers are
  written at W9, W11 and W12 themselves (not at W13, which is `if: success()`); a mutation row that moves a before-call
  marker after its call goes RED.
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
  show the post-wipe canonical plan fixture goes RED, proving `git_data_host_post_apply_assert` (from #10155) and
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
2. The chain it rides: the #10137 fix merged (PR #10155, merged 2026-10-12, read on `origin/main`), #8209, #8609 (so
   the Tier-B seam exists: `precondition_8209_open`) and #8573 (flag write seam), and a REAL key rotate that preceded
   the flip, evidenced per `design-rollback-rehearsal.md` R0 (its independent rotate check). **`d6_replace_stale` is
   NOT a control for that rotate and this design does not lean on it.** It is a hard `fail` in the cutover's
   `flip_preconditions` step, but it matches only the unconditional "rotate confirm token" step of a successful
   `git_data_host_replace` job, so a plain replace satisfies it and a newer failed or `plan_only=true` rotate is skipped
   by its `continue`; the open decision is #10166 (OPEN), which this precondition requires settled, not assumed.
   **d6's own failure message pushes the owner toward the rotate hazard.** After a rehearsal or after the flip, the
   `fail d6_replace_stale` text ("... dispatch apply_target=git-data-host-rotate (confirm=ROTATE-GIT-DATA) from main
   first.") steers the owner to dispatch exactly the rotate that #10175 says can destroy the only populated copy; the
   reader also scans only the 40 newest `apply-web-platform-infra.yml` dispatches with no time window, so the message
   can appear after enough unrelated dispatches. The build PR and the runbook MUST override that message in any state
   after the flip or after a rehearsal that populated the store (the runbook's D6 rotate section carries "never
   rotate after the flip", and the d6 failure text is amended or the runbook line takes precedence by name), and the
   interaction is recorded on #10166 and #10175; nothing in this design pushes the owner to rotate.
   **Rotate hazard (never rotate after the flip).** The rotate precondition reads only the latest `boot_complete` row
   (`served_repos=0` stays true until a reboot), and the plan-time gate accepts the exact delete+create of the LUKS
   volume, so a rotate dispatched after the flip (or after a rehearsal that populated the store) destroys the only
   populated copy while the plaintext volume is empty by construction; nothing in code stops it today. Until a guard
   exists the rule is "never rotate after the flip", it is a standing precondition of the wipe and of every step after
   it, and it is tracked in #10175 (the build PR cites it, and the runbook's D6 rotate section carries the same rule).
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
the volume id; (c) the environment approval (by a human in the owner's own session; the headless `pending_deployments`
form is never valid, section 2.1); (d) any S3 recovery (the `mode=wipe_finish` dispatch, or the manual form if the build PR defers that arm); (e) PR-C's merge timing, including the recorded bound of section 4 and the #8571 precondition; (f) the CLO's wording
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
  Masking is defence in depth, not containment, and `TF_VAR_hcloud_token`, `TF_STATE_AWS_*`/`AWS_*` and
  `DOPPLER_TOKEN_TF` remain exported to any step outside the allow-list.
- Not a machine-enforced time bound on the wedge (dispatch to PR-C merge): a breach returns to the owner and, past
  2026-11-12, to the CLO (section 4).
- Not a path out of the reboot dead-end of H8/H10: it is an accepted residual routed to the CLO (section 5).
- Not a statement that the 24 h bound of `wipe_finish` proves no write happened to the detached volume (section 5).
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
row for `wipe`, verdict-map rows for every `wipe_*` word, "The wipe", the wedge note and the S3 re-entry command); `.github/actions/infra-credentials` is read, not edited; `knowledge-base/engineering/operations/runbooks/infra-credential-tiers-8209.md` (a `git-data-cutover.yml::wipe` row, section 6) and the run-name change of section 2.1; `knowledge-base/legal/` NOT edited here (CLO). Also expected: the notify composite wiring in `git-data-cutover.yml`, `design-rollback-rehearsal.md`'s stamp fix (a separate PR, a precondition), and a wedge-proof test across the apply workflows' plan gates.

PR-C (merges only after #10155 has merged (it has; re-read), the #8571 precondition of section 7 and inside the recorded bound of section 4): `apps/web-platform/infra/git-data.tf`, `git-data-luks.tf` (comment cross-refs), `tests/scripts/lib/git-data-host-replace-gate.sh`
and its suite, the replace job's post-apply call delivered by #10155 (`git_data_host_post_apply_assert` and
its suite rows, PA1-PA8 as read on `origin/main`, to be re-read; this branch's Phase 2 was reverted and its names are not used), `plugins/soleur/test/terraform-target-parity.test.ts`, `scripts/encryption-posture-ledger.json`,
ADR-239 amendment, the runbook, Art. 30 hand-off to the CLO.

ADR: this design applies ADR-239 as written. PR-C amends ADR-239 (retention end reached; the empty-id branch is
rehearsed) per the plan's note; no new ADR is needed unless the build changes the destroy sequencing described here.

## 10. Open items for the build PR

Findings of the second verification pass that are NOT redesigned here. Each is a requirement or a decision the build
PR (PR-W) takes explicitly; none changes a ruling of this document.

- **V-4 (W13 is one step with two conditions).** W13 is written as "summary, teardown" with `if: always()` for the
  teardown part, while W9's text says "W13 runs only on success" for the summary. A step has one `if:`. Split it into
  a success-only summary step (the success evidence) and an `if: always()` teardown step under the `env -i`
  allow-list; the census `order` pin and the "markers are written at W9, W11, W12, never at W13" rule follow.
- **V-8 (a clean refusal reads as "may have detached").** W9a writes `detach_attempted` and W9 then performs the
  `wipe_assertion_stale` and flag re-read refusals, so the most probable failure (a slow loader past ~120 s) emails
  `DETACH_ATTEMPTED_UNCONFIRMED` although nothing was sent; a W1 typo refusal emails `WIPE_STATE_UNKNOWN`
  ("NOTHING is known to be unchanged"). Conservative, not wrong, but noisy. Either do the stale-epoch and flag
  re-read checks in W9a BEFORE the marker is written, or add a distinct notify word for "refused before the call".
- **V-9 (phase vocabulary leftovers and gaps).** (a) `pre_detach` survives in the S1 heading and in "if any step ever
  writes it" although nothing writes it: drop it or name the writer. (b) `VOLUME_DELETED_TEARDOWN_FAILED` (phase
  `deleted` with a later failure) has no S-table row and no test row in section 6. (c) Section 5 item 4 says
  "multiple-matching refuses" and also "for the newest such run": pick one rule.
- **V-13 and N-19 (archive retention horizon, one measurement).** W5 reads a `boot_complete` row at least 7 days old
  from the hot-plus-archive union (`BS_GIT_DATA_TABLE_S3`). If the archive retains less than the soak plus the
  wipe's own lead time, `wipe_boot_unreadable` is guaranteed. Measure the Better Stack archive retention horizon
  (read-only, no code) and record it on #6897 BEFORE PR-W is built; if it is shorter than the soak, the wipe's
  evidence source needs a decision first.
- **V-14 (simplification: omit the loader's legacy input).** The loader's legacy arm exists only when
  `doppler-token-legacy` is passed; with both token inputs empty it refuses with `no_credential_source` before
  exporting anything. If `wipe` passes only the Tier-B token and omits `doppler-token-legacy` (unlike
  `apply-git-data-root-key.yml`), the legacy arm cannot run, and W8b's "the refusal path has ALREADY lost the race"
  window, its blanking row and the sixth `secrets.DOPPLER_TOKEN` site (section 6 counts five without it) go away. Keep W8b as defence in depth either way.
- **ADR-241 amendment note (when PR-W lands).** A second Tier-B loader consumer inside a mixed-tier workflow, with an
  `env -i` allow-list convention for every step after the loader, merits an ADR-241 amendment note (create it with
  `soleur:architecture`); no new ADR is needed, and this does not change section 9's statement for ADR-239.
