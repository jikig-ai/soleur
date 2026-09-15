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
5. **Key fetch** from the isolated Doppler project `soleur-git-data-root`. A failure refuses
   `verdict=git_data_root_key_fetch_failed reason=<rc_nonzero|empty|not_openssh_key>`.
6. `ssh_config` writer (literal jump target, `IdentitiesOnly`, no forwarding).
7. **Script.** The access gate (`role=web`, `role=git-data-jump`, `role=git-data-auth`; exit 3 on any
   non-ok), then three fail-closed store probes (exit 5): `old_store_unmounted`, `already_cut_over`,
   `store_not_empty`, or `probe_failed rc=<n>` when a probe could not be answered. The store-empty probe
   re-checks, in the same remote command, that the store root is still the device the first probe read;
   a dangling symlink or a missing repositories directory is `probe_failed`, never a zero count.
8. Teardown, always.

Exit 0 means: root authenticated end to end, the plaintext store is mounted from a device that is not
the LUKS mapper, and it holds zero repositories. While #7226 is open a compromised web-1 could forge
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
   `role=git-data-auth verdict=ok`, clear all three store probes, and exit 0.

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

## Sharp edges

- **A pending approval holds `git-data-state`.** A cutover or root-key apply run waiting for its
  environment approval holds the group. A replace dispatched meanwhile waits while holding
  `terraform-apply-web-platform-host`, which stalls web-platform applies. Approve, reject or cancel the
  pending run before you dispatch a replace.
- **A newer queued run cancels an older pending one (#8167).** GitHub keeps one pending run per
  concurrency group. A run that ends `cancelled` without executing a step was displaced, not refused.
  Re-dispatch it once the group's current holder has finished.
- **A re-run asks for approval again.** The environment sits on the job that reads the key.

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
