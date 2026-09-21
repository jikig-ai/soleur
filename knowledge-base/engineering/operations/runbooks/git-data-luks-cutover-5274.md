# git-data LUKS cutover runbook — #5274 Phase 3 / Sub-PR 3.D / ADR-068

Runbook for the git-data LUKS cutover route. **Today the route is a reviewer-gated, read-only proof.**
`git-data-cutover.yml` authenticates to root on the git-data host through the ADR-220 web-1 jump, reads
three facts about the store, and exits. It moves no data, repoints no mount, flips no flag and wipes no
volume. The real cutover (copy, repoint, flag flip, rollback, old-volume decommission) was removed from
`git-data-cutover.sh` because it called host mechanisms that do not exist; its rebuild is **#8211**.
Rationale and residuals: ADR-220 › "Amendment log" › "2026-09-15 (#8189)".

**No SSH in this runbook.** Every read below is a workflow annotation, a Better Stack API read or a
Sentry query. The dispatch itself uses SSH transport off the app host; you never SSH a host to check
whether it worked (`hr-no-ssh-fallback-in-runbooks`).

## Preconditions for the real cutover (all open — do not book a window)

The real cutover does not exist yet. It is blocked on all of:

- **#8211** — rebuild the real modes on real mechanisms (freeze model, same-version redeploy, rollback
  split, `web-1-swap` membership, the endpoint guard for the copy).
- **#8209** — evict the repo-secret-reachable credentials from `prd_terraform` (its own ADR).
- **#7226** — pin git-data's SSH host key. Until then every store-probe answer is unauthenticated.
- A fresh `git-data-host-replace` plus a `GIT_DATA_LUKS_KEY` rotation immediately before the real
  cutover, so nothing planted during the read-only period survives into it (ADR-220 D6).
- **#8101** — fence readback landed; the hooks copy, post-copy readback and wrapper mapper assertion are carried in #8211 (see its "Carried from #8101" section; the wrapper edit is hash-bound, so it follows the [two-PR sequence](git-data-rung2-rehearsal.md#changing-the-payload-the-two-pr-sequence)).
- The legal-activation dependencies on the roadmap row for #5274 (Article 30 PA-36, #8101, #8094).

A dispatch that asks for a real mode refuses with `verdict=real_cutover_unreconciled` (exit 5) before
any remote call.

## What the read-only dispatch does

`git-data-cutover.yml` (`workflow_dispatch`, input `confirm=CUTOVER-GIT-DATA`, from `main`). One job,
`cutover`, behind the `web-platform-infra-apply` environment approval. The whole run holds the
`git-data-state` concurrency group, so it never overlaps a git-data replace, birth or rehearsal.

1. Confirm token.
2. **Flag precheck** (`git-data-flag-precheck.sh`, the only step holding the `prd` read token). An empty
   token refuses `verdict=flag_token_absent`. A failed read refuses
   `verdict=flag_read_failed reason=<auth_invalid|config_not_found|forbidden|network|scope_mismatch|unknown>`;
   the reason is a fixed word mapped from the CLI's error, which is never printed. `scope_mismatch` means
   the token resolves a config other than `prd`, where a missing flag would read as unset.
   `GIT_DATA_STORE_ENABLED=true` refuses `verdict=flag_already_true`. All exit 5.
3. **Secrets present.** An empty `DOPPLER_TOKEN_GIT_DATA_ROOT` refuses `verdict=git_data_root_token_absent`.
4. CF tunnel bridge to web-1.
5. **Key fetch** from the separate Doppler project `soleur-git-data-root`. A failure refuses
   `verdict=git_data_root_key_fetch_failed reason=<rc_nonzero|empty|not_openssh_key>`.
6. `ssh_config` writer (literal jump target, `IdentitiesOnly`, no forwarding).
7. **Script.** The access gate (`role=web`, `role=git-data-jump`, `role=git-data-auth`; exit 3 on any
   non-ok), then three fail-closed store probes (exit 5): `old_store_unmounted`, `already_cut_over`,
   `store_not_empty`, or `probe_failed rc=<n>` when a probe could not be answered. The store-empty probe
   re-checks, in the same remote command, that the store root is still the device the first probe read;
   a dangling symlink or a missing repositories directory is `probe_failed`, never a zero count.
   Then the **fence probe** (#8101, exit 5): the pre-receive fence the bootstrap plants is a real
   `root:git 750` hooks directory holding a real, executable `root:root 755` `pre-receive`, the system
   `core.hooksPath` names it, and it sits on the store device the first probe accepted. It reads
   `probe=fence-shape verdict=ok`, `verdict=fence_not_intact reason=<word>`, or `probe_failed rc=<n>`.
   It checks the fence's shape, not which hook is installed.
8. Teardown, always.

Exit 0 means: root authenticated end to end, the plaintext store is mounted from a device that is not
the LUKS mapper, and it holds zero repositories, and the pre-receive fence is installed and wired on the
store it will copy from. While #7226 is open a compromised web-1 could forge
that answer (ADR-220 D4).

Read the annotations without a dashboard:
`gh api repos/jikig-ai/soleur/check-runs/<job-id>/annotations --jq '.[].message'`, with the job id from
`gh run view <run-id> --json jobs --jq '.jobs[0].databaseId'`.

## Post-merge order (#8189)

Each prod step needs explicit authorization for that step. A menu acknowledgement does not count
(`hr-menu-option-ack-not-prod-write-auth`).

1. **Root-key apply.** Dispatch `apply-git-data-root-key.yml` from `main` with its typed confirm token,
   then approve the environment. The root is additive-only, with no exception: it refuses any plan other
   than a create of exactly its seven addresses or a no-op (`verdict=git_data_root_key_non_additive`,
   which also covers an import or a moved address). Once the fingerprint file is committed, it refuses a
   create of the key itself (`verdict=git_data_root_key_remint_refused`). It prints the key's `SHA256:`
   fingerprint read from Terraform state, and only after that value equals the fingerprint of the
   Hetzner key object's public key (`verdict=git_data_root_key_fingerprint_mismatch` otherwise). Any
   non-success except a run-level cancel emails ops through `notify-root-key-apply`.
2. **Fingerprint PR.** A PR commits the printed value to
   `apps/web-platform/infra/git-data-root-key.fingerprint` and merges.
3. **Replace.** Dispatch `apply-web-platform-infra.yml` from `main` with
   `apply_target=git-data-host-replace`. The replace gate's `git_data_root_key_arm` must pass. This is
   the only way the key reaches the host.
4. **Private-NIC readiness read** (below). It must read `up`.
5. **Dry run.** Dispatch `git-data-cutover.yml` from `main` and approve. It must read
   `role=git-data-auth verdict=ok`, clear all three store probes and the fence probe, and exit 0.

### Private-NIC readiness read (step 4)

`web-git-data-probe.sh` runs on web-1 every 60 s. On a successful bounded TCP connect to `10.0.1.20:22`
over the private network, it pings the `soleur-git-data-prd` heartbeat (`betteruptime_heartbeat.git_data_prd`
in `git-data.tf`, period 60 s, grace 180 s). A green read proves the fresh host's private NIC is up and
its sshd port answers. It does **not** prove that git transport serves or that the root key was
delivered; the dry run proves that.

Read it no earlier than 4 minutes (period plus grace) after the replace run completed
(`gh run view <run-id> --json conclusion,updatedAt`), so a beat from before the replace cannot account
for `up`:

```bash
curl -fsS -H "Authorization: Bearer $(doppler secrets get BETTERSTACK_API_TOKEN_READONLY --plain -p soleur -c prd_terraform)" \
  'https://uptime.betterstack.com/api/v2/heartbeats?per_page=250' \
  | jq '.data[] | select(.attributes.name == "soleur-git-data-prd") | {id, status: .attributes.status, paused: .attributes.paused}'
```

- `up` — proceed to the dry run.
- `down` — the fresh host's private NIC or sshd is not up. A fresh Hetzner host can boot with its
  private NIC down (learning `2026-07-07-immutable-redeploy.md`). Re-dispatch the replace; both volumes
  are retained.
- `paused` — the heartbeat is not armed, so this read proves nothing. Arming is
  `arm-heartbeats.sh --arm` inside `apply-web-platform-infra.yml`, and it skips an address absent from
  state. Rely on the dry run's `role=git-data-jump` verdict for L3 instead.
- `pending` — Better Stack has not received a first beat since the heartbeat was created or unpaused.
  Treat it like `paused`: it proves nothing either way. Rely on the dry run's `role=git-data-jump`
  verdict.
- **No output** (the command prints nothing and exits 0) — no heartbeat named `soleur-git-data-prd` is
  in the listing. Treat it like `paused`, and rely on the dry run's `role=git-data-jump` verdict. A
  non-zero exit is a failed read, not an answer; read again.

## Verdict map

| Where you are | What the run reads | What to do |
|---|---|---|
| Before the root-key apply | `verdict=git_data_root_token_absent` | Run post-merge step 1. |
| Root-key apply, a plan that is not a create of its seven addresses or a no-op | `verdict=git_data_root_key_non_additive` | Nothing is applied. A rotation or any other change is a reviewed PR that adds a typed allowlist arm for exactly its addresses (see "Rotation"). |
| Root-key apply after the fingerprint is committed, planning a create of the key | `verdict=git_data_root_key_remint_refused` | Do not re-anchor. The key's state was lost or the key deleted: open an incident (Breach-triage trigger). |
| Root-key apply, the Hetzner key object's public key is not the key in state | `verdict=git_data_root_key_fingerprint_mismatch` | Commit neither value. Open an incident (Breach-triage trigger). |
| Root-key apply, a capture step failed | `verdict=git_data_root_key_fingerprint_unreadable reason=<word>` | Nothing to commit. Re-dispatch once; a repeat is a defect in the step. |
| Root-key apply, the workflow could not read its own checkout | `verdict=git_data_root_key_anchor_unreadable` | Nothing was applied. Re-dispatch from `main`; a repeat is a defect in the workflow. |
| Before the fingerprint PR merged, or the Hetzner key object deleted | the replace or birth gate refuses `verdict=git_data_root_key_not_in_create reason=fingerprint_file_missing` or `reason=data_source_absent` | Dispatch `apply-git-data-root-key.yml` from `main`, commit its printed fingerprint, re-dispatch the replace or birth. |
| The Hetzner key object swapped, duplicated or renamed | the gate refuses `reason=fingerprint`, `reason=key_count` or `reason=name` | **Do not re-anchor.** A key object changed outside Terraform: open an incident (Breach-triage trigger). |
| A created server that does not carry exactly the default and root keys | the gate refuses `reason=server_keys` | A plan-shape defect, not a key problem. Fix the plan in a reviewed PR. |
| Token revoked, or the Doppler secret missing or malformed | `verdict=git_data_root_key_fetch_failed reason=<rc_nonzero\|empty\|not_openssh_key>` | Re-run the root-key apply if the secret is gone; a revoked token is replaced by a reviewed rotation PR. |
| **L3** — the host is down, or its private NIC or sshd is not up | `role=git-data-jump verdict=failed reason=timeout\|no_route\|connect_refused` | Read the private-NIC heartbeat; re-dispatch the replace if `down`. |
| web-1's sshd stopped permitting `direct-tcpip` | `role=git-data-jump verdict=failed reason=forward_refused` | ADR-220 D1a: the fallback needs its own amendment. |
| **L7** — the key has not been delivered yet (replace not run) | `role=git-data-auth verdict=failed reason=auth_refused` | Run post-merge step 3. |
| **L7** — after a key rotation, until the next replace | `role=git-data-auth verdict=failed reason=auth_refused` | Dispatch the replace. |
| The `prd` read token is empty | `verdict=flag_token_absent` (exit 5) | The `DOPPLER_TOKEN_PRD` repo secret is unset or not passed to this run. Restore it, then re-dispatch. |
| The flag read failed | `verdict=flag_read_failed reason=<word>` (exit 5) | `network`: re-dispatch. `auth_invalid`, `forbidden`, `config_not_found`, `scope_mismatch`: the token behind `DOPPLER_TOKEN_PRD` is revoked, lacks `prd` read, or resolves another config; replace it, then re-dispatch. `unknown`: re-dispatch once, then open an issue. |
| The flag is already on | `verdict=flag_already_true` (exit 5) | **Incident.** See "Flag already on" below. |
| The store root is not mounted on a device | `verdict=old_store_unmounted` (exit 5) | The plaintext volume is not mounted. Read the host's git-data boot events in Sentry before anything else, then re-dispatch the replace; both volumes are retained. |
| The store root is already the LUKS mapper | `verdict=already_cut_over` (exit 5) | Something repointed the mount outside the cutover. Open an incident. |
| The store holds repositories | `verdict=store_not_empty` (exit 5) | **Incident.** See "Store not empty" below. |
| A probe could not be answered | `verdict=probe_failed rc=<n>` (exit 5) | `rc=124`: the 30 s bound expired; re-dispatch. `rc=255`: ssh transport failed; read the heartbeat, then re-dispatch. `rc=141`: the answer was larger than the cap. `rc=96`: the answer did not match the expected pattern. Any `probe_failed` from the store-empty probe can also mean the store root changed device between probes, is a dangling symlink, or has no repositories directory. None of these is transient, and an empty store on its expected device produces none of them: do not re-dispatch in a loop; open an incident. No `rc`: the first probe left nothing for the second to compare; re-dispatch once. |
| The pre-receive fence is not intact | `verdict=fence_not_intact reason=<word>` (exit 5) | **Post-boot drift on a root-owned path**: `git-data-bootstrap.sh` FATALs at boot on each of these facts, so a host that booted cannot have come up this way. Dispatch `git-data-host-replace`, which re-runs the bootstrap. The words:<br>`hooks_dir_absent` — the hooks directory is missing or is a symlink.<br>`hooks_dir_owner` — the hooks directory is not `root:git 750`.<br>`hook_absent` — `pre-receive` is missing, a symlink, not a regular file, or not executable.<br>`hook_owner` — `pre-receive` is not `root:root 755`.<br>`hooks_path_mismatch` — the system `core.hooksPath` is unset or names another path.<br>`hooks_wrong_source` — the hooks directory is on a different device from the store. |
| The fence probe could not be answered | `probe=fence-shape verdict=probe_failed rc=5\|16` (exit 5) | `rc=5`: `findmnt` could not resolve the hooks directory's device. `rc=16`: an instrument on the host failed (`stat`, or `git config` exiting above 1). Re-dispatch once; if it repeats, dispatch `git-data-host-replace`. An instrument failing on a bootstrapped host is itself drift. Other `rc` values read as in the row above. |
| A stale invocation asking for a real mode | `verdict=real_cutover_unreconciled` (exit 5) | Nothing to do; the real cutover is #8211. |

L3 and L7 are different faults: L3 is reachability (NIC, sshd, host), L7 is authorization (the key).
Read the private-NIC heartbeat before treating an L7 verdict as a key problem.

### Store not empty (`store_not_empty`)

The store was assumed empty by construction (ADR-220 D4, #6976): the flag has never been on, so no
repository should exist. A non-empty store breaks that assumption, and a deleted user's repository may
remain on the plaintext volume.

1. Open an incident (`/soleur:incident`) and route it to the CLO for an Art. 33 assessment.
2. **Do not replace the host and do not wipe either volume.** The store's contents are the evidence,
   and the Art. 17 question is about them.
3. Pull the user ids whose erasure may not have completed from Sentry: every event tagged
   `feature:account-delete op:git-data-bare-repo-erasure` carries the id in its `extra.userId`. The
   issue's event listing returns each event in full, `extra` included:

   ```bash
   SENTRY_AUTH_TOKEN=$(doppler secrets get SENTRY_AUTH_TOKEN -p soleur -c prd --plain)
   curl -fsS -H "Authorization: Bearer ${SENTRY_AUTH_TOKEN}" \
     'https://sentry.io/api/0/organizations/jikigai-eu/issues/?query=feature%3Aaccount-delete%20op%3Agit-data-bare-repo-erasure&statsPeriod=90d' \
     | jq -r '.[].id'
   # for each issue id:
   curl -fsS -H "Authorization: Bearer ${SENTRY_AUTH_TOKEN}" \
     "https://sentry.io/api/0/organizations/jikigai-eu/issues/<issue-id>/events/?full=true" \
     | jq -r '.[] | [.dateCreated, (.context.userId // .extra.userId // "no-user-id")] | @tsv'
   ```

4. Attach the list to the incident. Whether and how each repository is erased is the incident's
   decision, taken with the CLO.

### Flag already on (`flag_already_true`)

`GIT_DATA_STORE_ENABLED=true` in `prd` while the store is still on the plaintext volume means user
repositories may now be written there unencrypted (Article 30 PA-2 (g)(17)).

1. Set the flag off in Doppler `prd`, verify it with a separate read, then redeploy the web container.
   Doppler values are baked into the container at start, so the flag stays on until the redeploy
   (learning `2026-05-19-doppler-env-hot-reload-limitation.md`):

   ```bash
   doppler secrets set GIT_DATA_STORE_ENABLED=false -p soleur -c prd --no-interactive > /dev/null
   doppler secrets get GIT_DATA_STORE_ENABLED -p soleur -c prd --plain   # must print: false
   gh workflow run web-platform-release.yml -f bump_type=patch            # redeploys current main
   ```

2. Open an incident (`/soleur:incident`) and route it to the CLO: find who or what set the flag, and
   treat any repository written while it was on as the "Store not empty" case above.
3. Re-dispatch the dry run only after the release run's deploy has finished; it must clear the flag
   precheck.

## The boot reopen failed: `stage:luks_reopen` (#8210)

A `stage:luks_reopen level:fatal` event means the git-data host booted and
`git-data-luks-reopen.service` could not reopen `/dev/mapper/git-data`. The store is absent
until this is resolved: the fstab line is `nofail`, so the host itself is up and answering on
:22 with nothing mounted. The event carries the phase that failed as `action=`, plus
`result=` / `rc=` / `code=` / `restarts=` read from the unit itself, and the script's stderr as
`detail` (capped at 180 chars by the emitter, after its redaction passes).

**Key on `action=` first.** The table below has one row per value the script and its reporter can
emit. Every check is off-host — a Doppler CLI read, a Hetzner API read or a Sentry query — because
this host ships no journal and has no SSH fallback.

| `action=` | Probable cause | Off-host check | Lever |
|---|---|---|---|
| `config` | `GIT_DATA_LUKS_DEV` or `GIT_DATA_DOPPLER_CONFIG` absent or malformed in `/etc/default/git-data-doppler` | The rendered payload: `bash apps/web-platform/infra/git-data-userdata-budget.sh /tmp/r.yml >/dev/null && grep -A8 'path: /etc/default/git-data-doppler' /tmp/r.yml` | A payload/tfvars defect — both values are template-rendered. Fix the payload, then `git-data-host-replace`. |
| `key` | `GIT_DATA_LUKS_KEY` was not injected: renamed, deleted, or the token lost the config | `doppler secrets --project soleur --config prd_git_data --only-names` | Re-create the secret under its NAME with the SAME value: `doppler configs logs rollback <log_id> --project soleur --config prd_git_data`, with the id from the `configs logs` read (Doppler logs every rename and delete, so the entry is there). No workflow re-converges it: `doppler_secret.git_data_luks_key` is in the CREATE job's `-target` set only, and `manual-rerun` does not carry it. Never a replace — a replace re-runs first boot, which needs the same key. |
| `device` | The LUKS volume is not attached, or did not appear within 30 s | `doppler run -p soleur -c prd_terraform -- sh -c 'curl --disable --noproxy "*" -sS -H "Authorization: Bearer $HCLOUD_TOKEN" https://api.hetzner.cloud/v1/servers?name=soleur-git-data' \| jq '.servers[0].volumes'` against `git_data_luks_volume_id` in the git-data tfvars | `POST /v1/volumes/{volume_id}/actions/attach` with `{"server": <server_id>}` under the same token (Hetzner re-attaches in place; no Terraform address re-creates `hcloud_volume_attachment.git_data_luks` short of a replace), then the timer's next ladder re-runs the reopen — or replace. |
| `header` | The pinned device is not a LUKS header — wrong volume, or a damaged one | The same volume-id read as `device` | **DO NOT REPLACE.** The birth heredoc formats a blank device, so a replace against a damaged or wrong volume destroys the only copy. This is the ADR-115 second-blocker class; the lever is what ADR-068 names as the durable rehydration source — GitHub (every bare repo is a mirror of a user remote, `ensure-workspace-repo.ts`) — re-provisioned onto a recreated volume. **No automated route for that exists yet**; it is a #8211 deliverable, and until it lands the honest state is "store unavailable, data intact upstream, do not replace". |
| `open` | `luksOpen` refused the passphrase — a mis-rotation | `doppler configs logs --project soleur --config prd_git_data` (the config audit log: when a secret last changed; `doppler activity` takes no `--project`) for when the secret last changed | **DO NOT REPLACE.** `doppler configs logs rollback <log_id> --project soleur --config prd_git_data` with the id from the logs read — and only if the change was out-of-band: `doppler_secret.git_data_luks_key` is Terraform-managed (`git-data-luks.tf`), so a `-replace=random_password.git_data_luks` rotation re-converges to the NEW value on the next create-path apply. A replace with the wrong passphrase dies at the birth heredoc's `luks_open` and leaves the host dark. |
| `identity` | The mapper is open but backed by a device other than the pin — a stale pin after a volume swap | `GET /v1/servers/{id}` attached volume ids vs the pin | Correct the pin in the payload, then replace. A host-config change is delivered by replace, never in place. |
| `target` | `/etc/fstab` names the mapper zero times or more than once — a bad #8211 cutover | The rendered payload's fstab line, as for `config` | A payload defect. Fix, then replace. |
| `mount` | The mount unit failed. `detail` carries the mount unit's journal tail | Read `detail` | `wrong fs type … bad superblock` is **filesystem damage**: the lever is the GitHub rehydration route named in the `header` row, NOT a replace. If `detail` reads `result=timeout` with the mount journal EMPTY, read the `luks_reopen_ok` rows first: a forced full e2fsck (`pass=2`) on a large error-flagged volume can exceed `TimeoutStartSec=300` while PID 1's mount completes, and the next attempt then reads `noop` — silently, so the fatal is never contradicted. A unit/payload defect is a payload fix plus a replace. |
| `identity-mount` | The target is mounted from something that is not the mapper | Read `detail` — it names the actual source | Same split as `mount`: damage → the GitHub rehydration route (not yet automated); payload defect → fix and replace. |
| `emit` | The store is OPEN AND MOUNTED — this row is not a store fault. The success emitter returned a STRUCTURAL rc (2, or 126/127 = absent/not executable) after a real reopen; a transient rc=1 is tolerated and never reaches here. **This row is DARK by construction**: the reporter ships through the same emitter, so no `action=emit` event can arrive. The unit exits 3 and `RestartPreventExitStatus=3` keeps it `failed` (a retry would take the silent noop branch and erase the fault). | What an agent sees: at birth, `luks_reopen_unit=no` in `boot_complete` (the boolean requires `ActiveState=active`); after a reboot, the ABSENCE of a `luks_reopen_ok` row where one is due, with no `luks_reopen` fatal either | A payload defect in the emitter, and an urgent one: every LATER failure on this host would be silent too. Fix the payload, then replace. Do NOT touch the volume — the data path is healthy. |
| `unit` | The script never ran: `doppler run` failed, exec failed, or the unit hit its start timeout. Key on `result=` (`exit-code` / `timeout` / `signal` / `start-limit-hit`) and `rc=`; `detail` carries the doppler CLI's own error line | `doppler configs --project soleur` (the config exists) and `doppler configs logs --project soleur --config prd_git_data` (the config audit log: when a secret last changed; `doppler activity` takes no `--project`) (when the token was last used) — both read-only CLI reads needing no host access | A token/config fault is corrected in Doppler; no replace. A `timeout` against a healthy Doppler is a slow boot, which the bounded restarts cover — `restarts=` on the next success row records that it recovered. **An ABSENT `/etc/default/git-data-doppler` lands here, not on `config`:** the unit's `EnvironmentFile=-` makes a missing file a no-op rather than an error, so `DOPPLER_TOKEN` is unset and `doppler run` dies before the script reaches a phase. The off-host check is the same rendered-payload read as the `config` row — a `write_files` entry that failed to render leaves no file at all. |
| `reopened` | Not a failure. The mapper was closed and is now open and mounted — the ordinary post-reboot success | — | None. Emitted at `info` on `luks_reopen_ok`; `restarts=` says whether a transient blip was absorbed |
| `mounted` | Not a failure. The mapper was already open and the target was not mounted — a retry after a failed mount job | — | None, unless it repeats: a mapper open with the target unmounted at every boot means the mount unit is failing for another reason |
| `noop` | Not a failure. Open and mounted already — the birth case, where the runcmd heredoc has just done both | — | None; this path emits nothing at all. In a REHEARSAL after a reset it is a FAIL (see below) |

**Success and no-op rows.** `action=reopened` (the mapper was closed and is now open and mounted)
and `action=mounted` (it was open, the target was not mounted) are emitted at `info` on stage
`luks_reopen_ok`, which is deliberately routed by NO Sentry rule — the fatal router has no
`level` condition, so routing it would page on every healthy reboot. `action=noop` (open and
mounted already, the birth case) emits nothing at all. Read the success rows with:

```bash
doppler run -p soleur -c prd -- bash scripts/sentry-issue.sh --host-events soleur-git-data --stage luks_reopen_ok \
  --start 2026-09-18T00:00:00 --end 2026-09-19T00:00:00
```

**In the rehearsal, `noop` and `mounted` after a reset are a FAIL, not a pass.** A mapper cannot
survive a hard power cycle, so the rung-2 reboot arm treats either as the probe or the host
lying. Only `reopened` releases the evidence.

**Event counts, so a repeat does not read as a new fault.** One exhausted restart ladder produces
exactly ONE `luks_reopen` fatal — and that is because `git-data-luks-reopen.service` carries
`RestartMode=direct`, not a default. Measured on systemd 261 at review: under the default
`RestartMode=normal` the unit transits `failed` before EVERY auto-restart and `OnFailure=` fires
on each attempt plus the terminal `start-limit-hit` — six events per ladder, and a transient
Doppler blip that recovered on attempt 2 still paged a fatal on a healthy host. With `direct` the
reporter runs once, at convergence, with `Result=start-limit-hit` and `NRestarts=<n>`.

**A host that stays broken repeats ONCE AN HOUR, not four times, and that is deliberate.** A
`git-data-luks-reopen.timer` tick inside the still-open `StartLimitIntervalSec=1h` window is
refused on an already-`failed` unit and fires NOTHING (`failed → failed` is not a transition;
measured). The first tick at or after the window closes re-runs a full ladder: one fatal, ~6
Doppler calls, then quiet until the next window. So expect roughly 20–24 events a day while the
store stays closed, collapsed by Sentry into one issue (the reporter's message is constant and
the emitter sets no fingerprint, so tags do not split it — which also means different `action=`
values share the issue: read the FIRST event's `action=`). Recovery from a vendor outage is
therefore bounded by that hour, not by the 15-minute tick: a 20-minute outage self-heals at the
first tick after 60 minutes from the ladder's first attempt. An earlier revision of this
paragraph claimed ~96 evenly spaced fatals a day; the timer file records the correction too.

The inherited gc-failure shape can double-emit only when `doppler run` succeeds and the emitter
itself then exits non-zero (its rc 1, a failed POST): the reporter's `|| "$@"` arm re-runs the
emitter once without the Doppler-injected Better Stack token. That is a bounded retry on the
failure path, not a second fault. A reopen that stays broken produces THREE events per weekly gc
tick, one root cause: the reopen's own fatal, gc's unit failure, and gc's mountpoint fatal.

## Sharp edges

- **A pending approval holds `git-data-state`.** A cutover or root-key apply run waiting for its
  environment approval holds the group. A replace dispatched meanwhile waits while holding
  `terraform-apply-web-platform-host`, which stalls web-platform applies. Approve, reject or cancel the
  pending run before you dispatch a replace.
- **A newer queued run cancels an older pending one (#8167).** GitHub keeps one pending run per
  concurrency group. A run that ends `cancelled` without executing a step was displaced, not refused.
  Re-dispatch it once the group's current holder has finished.
- **A re-run asks for approval again.** The environment sits on the job that reads the key.
- **The reporter's own failure is dark, and that is inherent to a host with no journal off-box.**
  If both of `git-data-luks-reopen-failure.service`'s arms fail (Sentry and Better Stack both
  unreachable from the host), that ladder's fatal is lost; the next hourly ladder re-emits, and a
  later success lands `luks_reopen_ok restarts=<n>`. A host with the store closed AND both sinks
  unreachable is dark until one recovers — as is every other git-data signal (gc's mountpoint fatal
  uses the same emitter; the web-side probe checks TCP :22 only).

## Rotation

The root-key root is additive-only, with no exception and no rotation input. **Any rotation, of the read
token or of the key, is a reviewed PR** that adds a typed allowlist arm naming exactly the addresses it
replaces. A key rotation's PR also lifts `prevent_destroy` on those addresses and accounts for the
re-mint refusal, which blocks a create of the key while the fingerprint file is committed. Then:

1. dispatch `apply-git-data-root-key.yml` from `main`;
2. for the key, a new fingerprint PR commits the printed value;
3. for the key, dispatch `git-data-host-replace`. Until then, dry runs read `reason=auth_refused`.

## What users see

### During a replace

- **Web requests: nothing.** With `GIT_DATA_STORE_ENABLED` off, provision, replicate and fetch return
  before touching git-data (`apps/web-platform/server/git-data-replication.ts`).
- **Settings → Delete Account completes**, but each deletion during the window can wait up to the
  30 s `execFile` timeout in `removeGitDataRepo` and logs an Art. 17 erasure-failure Sentry event
  (`feature:account-delete`, `op:git-data-bare-repo-erasure`). No repository exists yet, so nothing is
  left behind. These events are expected for the window, and only for the window: one outside a replace
  window is a real finding.
- The `soleur-git-data-prd` heartbeat reads `down` for the window.

### The blocked-recovery window (from the #8189 merge until the fingerprint PR lands)

Both host-creating gates now call the root-key arm, and the arm refuses without the committed
fingerprint. So from the merge of #8189 until the fingerprint PR merges, **every git-data replace and
birth refuses** with `reason=fingerprint_file_missing` or `reason=data_source_absent`. If the git-data
host fails inside that window, it stays down until post-merge steps 1 and 2 are done.

- Web requests still see nothing, for the reason above.
- **Delete Account completes**, but each deletion waits up to the 30 s `execFile` timeout and logs an
  Art. 17 erasure-failure event (`op:git-data-bare-repo-erasure`). **Those events are expected in this
  window** while the host is down. No repository exists, so nothing is left behind.
- Keep the window short: run post-merge steps 1 and 2 back to back.

**Break-glass for the rung-2 interlock (#8210).** `git_data_host_replace` calls
`git_data_rung2_rehearsal_gate`, which binds the landed evidence to a hash of the cloud-init
template, the render module and every payload it binds — **at the dispatched ref** — and reads
the evidence's commit provenance (so the job checks out with `fetch-depth: 0`; a shallow clone
HOLDs). An emergency replace is therefore refused whenever `main` has drifted since the last
rehearsal, including when the host is already down. The route:

1. Find the candidate: **the last commit that touched the evidence file**,
   `git log -1 --format=%H -- apps/web-platform/infra/git-data-rung2-boot-evidence.env`, or any
   descendant of it up to the next change of a bound file. (Not the template's own log: those
   commits are where the template CHANGED, and by Guard 4 the evidence for a template always lands
   in a LATER, evidence-only commit — at every SHA that log prints the in-tree evidence is the
   previous one and the gate refuses with STALE EVIDENCE.)
2. `gh workflow run --ref` takes a **branch or tag name**, not a SHA: push a tag at that commit
   (`git tag rung2-known-good-<date> <sha> && git push origin rung2-known-good-<date>`), then
   dispatch `git-data-host-replace` with `--ref rung2-known-good-<date>`.
3. The ref must itself CARRY the interlock and the full-history checkout (i.e. be at or after the
   #8210 merge); a pre-#8210 ref has no interlock in its workflow, so dispatching one would be a
   bypass, which this paragraph does not license.

That ref is not a weaker payload — it is precisely the payload a rehearsal booted and reset. No
PR, no SSH, no gate edit; one tag push. Re-rehearse and land evidence for the newer payload
afterwards; do not carry the tag forward as a standing dispatch source.

**Escape hatch.** If the root-key apply cannot succeed (for example a provider or Doppler failure the
dispatch cannot get past) and a recovery replace is needed, the route is **a reviewed PR** that reverts
the `git_data_root_key_arm` call in both gates (`git-data-host-replace-gate.sh` and
`git-data-host-birth-gate.sh`), together with the suites that pin those calls. A replace after that
merge creates the host without the root key: git transport works, and dry runs read
`reason=auth_refused` until a PR restores the arm and the post-merge order runs. Do not bypass the gate
any other way.

## Breach-triage trigger

Open an incident (`/soleur:incident`) and route it to the CLO for an Art. 33 assessment when any of
these is seen:

- a run log or artifact showing root-key material;
- any workflow run, on any branch, that received `DOPPLER_TOKEN_GIT_DATA_ROOT` outside the `cutover`
  job of `git-data-cutover.yml`, including a callee that received it through `secrets: inherit`
  (`reusable-release.yml` receives every repo secret from `web-platform-release.yml` and
  `version-bump-and-release.yml`) and then referenced it;
- an unexplained change to the Hetzner key labelled `soleur-role=git-data-root`, or a create gate
  refusing `reason=fingerprint`, `reason=key_count` or `reason=name`;
- a root-key apply refusing `verdict=git_data_root_key_fingerprint_mismatch` or
  `verdict=git_data_root_key_remint_refused`;
- a dry run refusing `verdict=store_not_empty` or `verdict=flag_already_true` (remedies under the
  verdict map);
- a `git-data-root-key` state object or `soleur-git-data-root` Doppler access that no dispatch explains.

Before any repository exists, a leaked root key already reaches the host's own Doppler token
(`prd_git_data`, #6167). Once repositories exist, a leak is likely an Art. 33 event (ADR-220 D4).

## Multi-host DNS rewire

Not part of the read-only proof. `cloudflare_record.app` (`dns.tf`) stays single-host until the
ADR-068 Phase-3 GA flip, which also brings the out-of-band second web host into rotation (ADR-143 D2).
That rewire is sequenced by #8211 together with the real cutover; the design constraint stays recorded
in the `dns.tf` header.

## After the real cutover (owned by #8211)

These stay recorded for the rebuild; none applies to the read-only proof.

- **Verification (observability only).** Sentry `feature:control_plane_route level:error` = 0 (after
  confirming healthy placement events exist), `feature:worktree_lease level:error` = 0,
  `feature:git-data-authz cross_tenant:true` = 0 (a `level:warning` tag). The `soleur-git-data-prd`
  heartbeat reads `up` through the API read above.
- **Backstop: `origin` is a strict subset of git-data.** `replicateToGitData` force-pushes all refs,
  while `syncPush` commits only `knowledge-base/**` and reroutes protected pushes. After any rollback, do
  not decommission the LUKS volume until git-data-only writes are reconciled.
- **Soak follow-through (gates GA close).** ≥7 days with zero fence false-rejects, zero cross-tenant
  denials and zero `control_plane_route` failures, via
  `scripts/followthroughs/phase3-ga-soak-5274.sh` and a `follow-through` tracker
  (`followthrough-convention.md`), whose directive carries `secrets=SENTRY_AUTH_TOKEN`. When it closes,
  ADR-068 moves `adopting` → `accepted`.

## References

- Dispatch workflows: `.github/workflows/git-data-cutover.yml`, `.github/workflows/apply-git-data-root-key.yml`
- Script: `apps/web-platform/infra/git-data-cutover.sh`; flag precheck: `apps/web-platform/infra/git-data-flag-precheck.sh`
- Root-key Terraform root: `apps/web-platform/infra/git-data-root-key/`
- Create-gate arm: `tests/scripts/lib/git-data-root-key-arm-gate.sh`
- ADR-220 (access and credential), ADR-068 (cutover design), ADR-149 (birth route)
- Soak script: `scripts/followthroughs/phase3-ga-soak-5274.sh`
- Convention: `knowledge-base/engineering/operations/runbooks/followthrough-convention.md`
