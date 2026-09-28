# git-data LUKS cutover runbook — #5274 Phase 3 / Sub-PR 3.D / ADR-068

Runbook for the git-data LUKS cutover route. **Today the route is a reviewer-gated, read-only proof.**
`git-data-cutover.yml` authenticates to root on the git-data host through the ADR-220 web-1 jump, reads
the state of the store (served by the LUKS mapper, marker bound, not frozen, empty) and the shape of
its pre-receive fence, and exits. It moves no data, repoints no mount, flips no flag and wipes no
volume. The real cutover (copy, repoint, flag flip, rollback, old-volume decommission) was removed from
`git-data-cutover.sh` because it called host mechanisms that do not exist; its rebuild is **#8211**.
Rationale and residuals: ADR-220 › "Amendment log" › "2026-09-15 (#8189)".

**No SSH in this runbook.** Every read below is a workflow annotation, a Better Stack API read or a
Sentry query. The dispatch itself uses SSH transport off the app host; you never SSH a host to check
whether it worked (`hr-no-ssh-fallback-in-runbooks`).

## Preconditions for the real cutover (all open — do not book a window)

The real cutover does not exist yet. It is blocked on all of:

- **#8211** — rebuild the real modes on real mechanisms (freeze model, same-version redeploy, rollback
  split, `web-1-swap` membership, the endpoint guard for the copy). **Split in two.** PR1 (PR #8564,
  ADR-239) moved the store onto the LUKS mapper at boot and shipped the store assertion. PR2's proof
  half (ADR-239 amendment 2026-09-27) rebuilt the dry run's store probes for that layout: the
  read-only dispatch below **is** the `proof`. Still open on #8211: the `flip`, the flag-off-only
  `rollback`, the same-version redeploy, and the ADR-220 D6 fresh replace with its
  `GIT_DATA_LUKS_KEY` and volume rotation. See
  [The LUKS-serving render](#the-luks-serving-render-pr1-of-8211).
- **#8209** — evict the repo-secret-reachable credentials from `prd_terraform` (its own ADR).
- **#7226 / #5914** — pin the SSH host keys of web-1 and git-data (ADR-237). Staged; the open items
  are the [host-key pinning post-merge sequence](#host-key-pinning-post-merge-sequence-7226-5914)
  below:
  - [x] #7226 — closed 2026-09-22 by PR #8511; ADR-237 is `accepted` (PR #9036, host-key step 4).
  - [x] Mechanism: PR #8511 (pending merge at the time of writing). The CI bridge, the Terraform
    `connection` blocks and this workflow's two hops are strict; git-data's key is Terraform-minted
    and rotated on every replace; the app's transport pins when a pin is published (since
    PR #9096 it always pins, and an absent pin refuses).
  - [ ] Step 1 — every merge-triggered apply is `success` (the `web_1_host_key_probe` ran).
  - [x] Step 2 — rung-2 re-rehearsal, then the evidence-only PR. Done: rehearsal run
    [35914294265](https://github.com/jikig-ai/soleur/actions/runs/35914294265) (2026-09-23, `main`,
    `success`), evidence PR #8655 merged 2026-09-23 (#5914 issuecomment-5803357950).
  - [x] Step 3 — `git-data-host-replace` publishes `GIT_DATA_SSH_HOST_KEY`, and the
    `git-data-pin-redeploy.yml` run it triggers loads it (startup line `git_data_pin=present`).
    Done: replace run [36118115758](https://github.com/jikig-ai/soleur/actions/runs/36118115758)
    (2026-09-25); startup line `git_data_pin=present fp=SHA256:4eErmLfOuKM17zzNd+2so+26zojG0tsv9NMVNCuXpCs`
    at 2026-09-25T09:39:39Z (#5914 issuecomment-5830287903); re-read on the serving deploy under
    gate G2 before the step-6 merge (recorded in the PR #9096 body).
  - [x] Step 4 — the strict dry run reads `role=git-data-auth verdict=ok`; then tick this item and flip
    ADR-237 to `accepted` in a docs PR. Done: `git-data-cutover.yml` run
    [36119817656](https://github.com/jikig-ai/soleur/actions/runs/36119817656) (from `main`,
    2026-09-25) read `role=git-data-auth verdict=ok` with both hops pinned. The run exited 5 on
    `verdict=already_cut_over` — git-data serves the LUKS mapper from boot since replace run
    36118115758 — a store probe and not a host key. ADR-237 is `accepted` (addendum 2026-09-27).
    That verdict was retired by #8211 PR2's proof half: the probes now require the mapper.
  - [x] Step 5 — every erasure left pending by the pin window is discharged. Done: #5914
    issuecomment-5865758722 (window 2026-09-22T12:07:01Z to 2026-09-28T07:51:53Z: 0 events, 0 ids;
    proof run 36339208990 reused under the 5.2 rule).
  - [x] Step 6 — the #5914 follow-up PR deletes the app's unpinned fallback arm and closes #5914.
    Done: PR #9096.
  - **Flag-flip precondition (hard):** `GIT_DATA_STORE_ENABLED` is never set until the pin is present
    in `prd`, #5914 is closed, **and** #8211 pages on `git_data_replication_push` pin faults (with the
    store on, a stale pin fails every replication push, and today that failure does not page). The
    flag precheck's `TOFU_ARM present|absent|unknown` line is a reminder read from the dispatched
    source tree, not a control: it says whether that ref still carries the fallback arm, not what the
    running app does. The enforcing control is the app's pin resolver, which throws on an absent pin
    while the store flag is on. Only `TOFU_ARM absent` satisfies the reminder.
    **Since PR #9096 (#5914, host-key step 6):** the resolver throws on an absent pin whatever the
    flag says, and a dispatch from `main` reads `TOFU_ARM absent`, which satisfies the reminder. The
    other conditions stand: the pin present in `prd`, #8572 paging, and #8211's per-id re-erasure
    path (the flip must not happen before it exists; see host-key step 5, "Requests after the
    window").
    **Since #8572:** the paging condition is met once its PR has merged **and** both of its runs
    are green: `apply-sentry-infra.yml` (it creates the `git-data-host-key-pin-fault` rule and adds
    per-event re-paging to `art17-erasure-incomplete`) and `web-platform-release.yml` (it deploys the
    emitter). Check the live rule, not only its name: the rule's `in` set is
    `host_key_mismatch,pin_absent,pin_invalid,ssh_client_absent`, it is enabled, and it emails
    `ActiveMembers`. Before the flip only its boot arm can fire, so "no `pin_fault` event" never
    counts as healthy: a network attacker can hold every dial before the host-key check, which
    stays unclassified, so the flip check needs positive replication evidence. #8211's per-id
    re-erasure path stays a **hard** precondition beside it.
  - [ ] **An ssh client in the web-platform image** (PR #9096): the startup line reads
    `git_data_ssh_client=present` on the deployed build
    (`doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh --since 30m --grep git_data_ssh_client=`).
    Until PR #9096, `node:22-slim` plus `--no-install-recommends` shipped no `ssh` (git only
    Recommends openssh-client), so every app-side git-data dial failed ENOENT: every Art. 17
    erasure read `unreachable`, and no replication call could run. Required before
    `GIT_DATA_STORE_ENABLED` flips.
- A fresh `git-data-host-replace` plus a `GIT_DATA_LUKS_KEY` rotation immediately before the real
  cutover, so nothing planted during the read-only period survives into it (ADR-220 D6).
- **#8101** — remaining: the hooks copy, the post-copy fence readback and the wrappers' mapper
  assertion, carried in #8211 ("Carried from #8101"). The wrapper edit is hash-bound, so it follows
  the [two-PR sequence](git-data-rung2-rehearsal.md#changing-the-payload-the-two-pr-sequence). The
  dry run's fence probe is in place.
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
   It then prints the informational `TOFU_ARM present|absent|unknown` line (whether the app still
   carries the unpinned fallback arm, #5914) and reads git-data's host-key pin, `GIT_DATA_SSH_HOST_KEY`,
   with the same token. An absent or malformed pin, or a failed read, refuses
   `verdict=git_data_host_key_unavailable reason=<absent|invalid>` (exit 5), or `reason=<word> rc=<n>` when the read itself fails. A valid pin is
   written to `$RUNNER_TEMP/git-data.pin` and only its `SHA256:` fingerprint is printed.
3. **Secrets present.** An empty `DOPPLER_TOKEN_GIT_DATA_ROOT` refuses `verdict=git_data_root_token_absent`.
4. CF tunnel bridge to web-1.
5. **Key fetch** from the separate Doppler project `soleur-git-data-root`. A failure refuses
   `verdict=git_data_root_key_fetch_failed reason=<rc_nonzero|empty|not_openssh_key>`.
6. `ssh_config` writer (literal jump target, `IdentitiesOnly`, no forwarding). It writes one
   known_hosts file through the bridge's validated `write-known-hosts.sh`: `web-1` from the committed
   `apps/web-platform/infra/web-1-ssh-host-key.pub`, `git-data` from the precheck's pin. Both Host
   blocks are strict, each under its own `HostKeyAlias` and algorithm (ECDSA-P256 for web-1, ED25519
   for git-data); the `ProxyCommand` resolves to the web-1 block, so the jump hop is pinned too.
7. **Script.** First a configuration check (`probe=config`, exit 5, nothing dialed or printed): every
   configurable path is a safe literal. Then the access gate (`role=web`, `role=git-data-jump`,
   `role=git-data-auth`; exit 3 on any non-ok, including
   `verdict=host_key_mismatch reason=<changed|unknown|alg>`), then the fail-closed store probes
   (exit 5), in order:
   - `probe=store-mounted`: the store root is mounted on a device (`old_store_unmounted`);
   - `probe=store-on-mapper`: that device is the LUKS mapper `/dev/mapper/git-data`
     (`store_not_on_mapper`; ADR-239 D1 says the render never serves anything else);
   - then ONE ssh session reports two probes, so every fact is read at one instant.
     `probe=store-verified`: the store is still served by that device, the freeze sentinel
     `/mnt/git-data/.cutover-freeze` is absent (read first, so a frozen store reads frozen), the
     mounted filesystem has a UUID, and the bootstrap's marker `/etc/git-data/store-verified` (the
     one every store wrapper requires, ADR-239 D3) holds that UUID on its first line
     (`store_unverified reason=<no_fs_uuid|marker_absent|marker_mismatch>`, or `cutover_frozen`).
     `probe=store-empty`: `repositories/`'s containing mount is the store root, and it holds no
     entry except `.*.init.lock` dotfiles and `lost+found`, the bootstrap's own `_repo_count` rule
     (`store_not_empty`). A `store_unverified` means every wrapper refuses on the host right now;
     `cutover_frozen` means provision, remove, the transport wrapper and pre-receive do. The probes
     read as root while the wrappers run as git, so a permission fault can make the wrappers refuse
     where the proof passes: the proof is never **stricter** than the wrappers, and the git-user
     path is attested by `boot_complete erasure_probe=yes` and the fence probe's `runuser` checks.

   A probe that could not be answered is `probe_failed rc=<n>`; a dangling symlink, a missing
   repositories directory or a second mount over it is `probe_failed`, never a zero count.
   Then the **fence probe** (#8101, exit 5). It checks what a push actually depends on:
   - a real `root:git 750` hooks directory, under a root-owned parent nobody else can write;
   - a real `root:root 755` `pre-receive` that the `git` user can read and execute;
   - the installed transport wrapper pins pushes to that directory on git's command line, and the
     system `core.hooksPath` (includes resolved) names it too;
   - both sit on the store device the first probe accepted.

   It reads `probe=fence-shape verdict=ok`, `verdict=fence_not_intact reason=<word>`, or
   `probe_failed rc=<n>|reason=arg_<name>`. It checks the fence's shape, not which hook is installed.
8. Teardown, always.

Exit 0 means: root authenticated end to end; the store is served by the LUKS mapper, with the
bootstrap's store marker bound to its filesystem; it is not frozen; its repositories directory holds
no entry (lock dotfiles and `lost+found` excepted); and a push would run a root-owned `pre-receive` of the planted shape from that store. It does **not**
determine when encryption at rest became active for the Art. 30 register: that determination is
#8634's, and this dry run leaves it alone. Before PR #8511 a compromised web-1 could forge
that answer (ADR-220 D4). With both hops pinned (ADR-237), web-1 can no longer stand in for
git-data. A pinned key authenticates the host, not the truth of its answer: a compromised git-data
can still answer falsely, which is why the probes stay bounded and fail-closed.

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
   `role=git-data-auth verdict=ok`, clear the store probes and the fence probe, and exit 0.
   **Done:** first met by run [35119099336](https://github.com/jikig-ai/soleur/actions/runs/35119099336) (2026-09-16, before the fence probe and host-key pinning); met as now worded by run [36339208990](https://github.com/jikig-ai/soleur/actions/runs/36339208990) (2026-09-27, `verdict=clear`, #5914 issuecomment-5859802570).

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

## Host-key pinning post-merge sequence (#7226, #5914)

PR #8511 (ADR-237) pins web-1's host key on every CI path and git-data's on the cutover workflow
and in the app. It publishes no git-data pin by itself: the pin is created by the next
`git-data-host-replace`. Each prod step below needs its own explicit authorization
(`hr-menu-option-ack-not-prod-write-auth`).

1. **Merge.** From this merge on, any merge-triggered `apply-web-platform-infra.yml` run runs
   `terraform_data.web_1_host_key_probe` (a read-only `true` over the strict Terraform path) and must
   end `success`. Read the latest ones; every `conclusion` must be `success`:

   ```bash
   gh run list --workflow apply-web-platform-infra.yml --event push -L 5 --json conclusion,databaseId,createdAt
   ```

   The bash path was proven before merge (AC15): `workspaces-luks-verify.yml` run
   [35636913078](https://github.com/jikig-ai/soleur/actions/runs/35636913078), on branch commit
   `d916e62f1`, concluded `success` over the pinned strict path. Its log shows
   `pinned web-1 ecdsa-sha2-nistp256 SHA256:ARBTzhY4hCGXKwWZ2j9aOc4zZefBYgAxJncoVglvuok` and
   `workspaces-luks re-assert PASSED`.
2. **Rung-2 re-rehearsal, then the evidence-only PR.** Dispatch `git-data-rung2-rehearsal.yml`
   (`REHEARSE-GIT-DATA`, `dry_run=false`, `--ref main`), then land its evidence in an
   evidence-only PR ([two-PR sequence](git-data-rung2-rehearsal.md#changing-the-payload-the-two-pr-sequence);
   PR #8511 is the payload PR and deleted the old evidence file). Until that PR merges, **birth and
   replace refuse, including an emergency replace** — see "The rung-2 emergency-replace gap" below.
   - **HELD until PR #8564 merges** (the operator ruling on DC-2, posted on #5914). PR #8564 changes
     the same hash-bound payload, so a rehearsal dispatched for #8511 alone is voided by that merge.
     One rehearsal after PR #8564 covers both payloads. It must read the values in
     [The LUKS-serving render](#the-luks-serving-render-pr1-of-8211). This lengthens the gap in "The
     rung-2 emergency-replace gap"; that is the accepted price of not paying for two rehearsals.
3. **`git-data-host-replace`.**
   - The replace rotates the host key (`-replace` of `tls_private_key.git_data_host_ssh`),
     `git_data_boot_verify` passes (it includes the cloud-init boot proof that sshd serves exactly the
     Terraform key), and `GIT_DATA_SSH_HOST_KEY` publishes to `prd`.
   - The completed apply run (replace or birth) triggers `git-data-pin-redeploy.yml` (`workflow_run`),
     whose `redeploy` job dispatches `web-platform-release.yml` and waits until a newer release's
     deploy succeeds; a failure emails ops. Find the run:

     ```bash
     gh run list --workflow git-data-pin-redeploy.yml -L 5 --json databaseId,conclusion,event,createdAt
     ```

     It must end `success`, and Better Stack must then show `git_data_pin=present` with the
     fingerprint the source apply run printed (go/no-go below). A green follower does not by itself
     mean a redeploy happened: since #8710 its gate proceeds only when the job **and** its apply step
     both succeeded, and otherwise does not redeploy (green with a notice or warning, red when it
     cannot decide). The follower has two jobs: `gate` grades the source run, and `redeploy`
     dispatches the release only when the gate proceeds; when it does not, `redeploy` is `skipped`.
     Check that its `redeploy` job is `success`, not `skipped`:

     ```bash
     gh run view <pin-redeploy-run-id> --json jobs --jq '.jobs[] | select(.name == "redeploy") | .conclusion'
     ```

     If `redeploy` is `skipped` and its gate printed `verdict=carried_over` (source-run-gate: the
     git-data job was carried over from an earlier attempt of the same apply run), the previous
     follower owns the redeploy. Find the followers whose gate names the same `in run <id>`:

     ```bash
     for id in $(gh run list --workflow git-data-pin-redeploy.yml -L 20 --json databaseId --jq '.[].databaseId'); do gh run view "$id" --log | grep -qF "in run <apply-run-id>" && echo "$id"; done
     ```

     Check the previous one's `redeploy` job with the command above: it must be `success`. If it is
     not, run `gh workflow run git-data-pin-redeploy.yml --ref main` (no `source_run_id`, so it
     redeploys unconditionally). If `redeploy` is `cancelled`, a newer follower's pending redeploy
     replaced it in the lock: check that newer follower's `redeploy` job instead.

   - **If the replace failed after the secret published:** re-dispatch the replace. The replace gate
     accepts that plan.
   - **If the replace failed before the new server was created:** state holds the new key, no server,
     and the old host's pin. The replace gate needs a server to delete, so re-dispatch
     `git-data-host-create` instead (see `git-data-birth.md`). The birth gate accepts a pin `update`
     only while the same plan creates `hcloud_server.git_data`.
   - **If only the redeploy failed:** never replace again for it. Re-run its failed job, or dispatch it
     against the source apply run:

     ```bash
     gh run rerun <pin-redeploy-run-id> --failed
     gh workflow run git-data-pin-redeploy.yml --ref main -f source_run_id=<apply-run-id>
     ```

     If the gate exited 1 with `verdict=unidentified`, or printed `verdict=pin_published` or `verdict=pin_maybe_published`, the same `source_run_id` refuses again.
     When the source apply step published a pin, dispatch with **no** `source_run_id` (it redeploys
     unconditionally):

     ```bash
     gh workflow run git-data-pin-redeploy.yml --ref main
     ```

4. **Strict dry run.** Dispatch `git-data-cutover.yml` from `main`. It must read
   `role=git-data-auth verdict=ok` with both hops pinned. Then tick the #7226 item under Preconditions
   and flip ADR-237 to `accepted` in a docs PR.
   **Done:** run [36119817656](https://github.com/jikig-ai/soleur/actions/runs/36119817656) (2026-09-25) read `role=git-data-auth verdict=ok` with both hops pinned (it exited 5 on `probe=store-not-cut-over verdict=already_cut_over`, a store probe since retired); re-met clean by run [36339208990](https://github.com/jikig-ai/soleur/actions/runs/36339208990) (2026-09-27, `verdict=clear`). ADR-237 `accepted` 2026-09-27 (PR #9036); see Preconditions.
5. **Discharge the erasures left pending.** After the pin is fixed (step 3 GO) and before step 6 or any
   flag flip:
   1. Collect the repository ids from Sentry: every `op:git-data-bare-repo-erasure` event since the
      PR #8511 merge (2026-09-22T12:07:01Z), using the sweep query under "Store not empty" (step 3
      there) with its period widened to cover the merge. Do not filter on `erasure_outcome`: the
      `removeGitDataRepo threw` arm carries no such tag. Read every page: the list call returns a
      `Link: <…>; rel="next"; results="true|false"` header, so capture headers (`curl -D <file>`)
      and follow the cursor until `results="false"`. Run the sweep again just before you write
      the #5914 record; the window ends at that second read. **The ids stay in Sentry.** They go on
      no issue, PR, commit, workflow input or log, and neither does a hash of an id or of the list.
      This repository and its Actions logs are public, and `workspace_id` is `auth.users.id`. The
      record carries counts and Sentry issue ids only. **The agent transcript and the terminal are
      logs too:** never run the "Store not empty" step-3 block as written (its final `jq … @tsv`
      prints one id per line). Write the sweep as an uncommitted script that prints only counts
      and Sentry issue ids, run it as `doppler run -p soleur -c prd -- bash <script>` with
      `set +x`, send `jq`'s stderr to `/dev/null` (a `jq` error echoes the value it failed on),
      read each exit status, and feed ids only into an aggregating `awk` or `sort -u | wc -l`.
      Read the issue list AND each issue's `events/?full=true` with `curl -D` and follow
      `rel="next"`, keeping only events inside the window.

      **Also sweep by message text** (added 2026-09-28 by the first step-5 record, #5914
      issuecomment-5865758722). An Error-path report reaches Sentry as `feature=pino-mirror`
      without its `feature`/`op` tags (#8629), so the tag query alone reads 0 for it whatever
      happened. Until PR #9096 the erasure report used that path, and the `removeGitDataRepo threw`
      arm still does. So over the same window also run the free-text queries `"git-data erasure"`,
      `"refusing unsafe workspace_id"` and `"GIT_DATA_SSH_HOST is unset"` against the organization
      issues endpoint:
      `curl -G -D <hdr> --data-urlencode 'query="git-data erasure"' --data-urlencode start=<window start> --data-urlencode end=<window end> …/organizations/jikigai-eu/issues/`,
      with the same pagination, printing only each issue's `.id` and `.count` (never `.title`: the
      `refusing unsafe workspace_id` title embeds the raw id). De-duplicate hits against the tag
      sweep by issue id. Pair every zero with three positive controls: the token and host list any
      organization issue; the tag syntax (`feature:pino-mirror`) returns issues; free text on a bare
      phrase from an existing issue title returns it. A pre-#9096 Error-path erasure event carries
      its repository id and `detail` in its `category: "pino"` breadcrumb
      (`.entries[] | select(.type=="breadcrumbs") | .data.values[] | select(.category=="pino") | .data.gitDataRepoId`),
      not in `extra`; classify it by its message (`git-data erasure <status>`). Only the
      `removeGitDataRepo threw` arm carries no id; its known throws are pre-dial (see (d)).

      **Sentry is not a complete per-erasure record.** Sentry's default Dedupe integration drops an
      event identical to the previous one from the same process (same message, no stack), so two
      refusals with nothing between them reach Sentry once. The pino line (`log.error`, shipped to
      Better Stack) is written for every refusal and carries `gitDataRepoId` and `detail`. Count
      those lines over the window (`scripts/betterstack-query.sh … --grep git-data-bare-repo-erasure`,
      counts only) and compare with the Sentry event count; a mismatch means ids are missing from
      Sentry and must be read from Better Stack the same counts-only way.
   2. Dispatch `git-data-cutover.yml` from `main`, after the #8211 PR2 proof-half merge and its
      release deploy have concluded (`bash plugins/soleur/scripts/deploy-arm.sh find --wait
      <merge-sha>` prints `DEPLOY=success`, and `deploy-arm.sh served <merge-sha>` prints `CONTAINS`;
      waiting keeps the dry run off a host mid-redeploy).
      An existing `verdict=clear` run from `main` may be reused instead of a new dispatch when its
      head descends from the proof-half merge, that merge's deploy arm ended `DEPLOY=success`
      (`deploy-arm.sh find <full merge sha>`, then the arm run's `updatedAt`) before the run's
      `cutover` **job** started (`gh run view <id> --json jobs`), and no `web-platform-release.yml`
      deploy arm overlapped the job
      (`gh run list --workflow web-platform-release.yml --event workflow_run -L 40 --json databaseId,createdAt,updatedAt,status`
      against the job's `startedAt`/`completedAt`; a queued or in-progress deploy arm counts as
      overlapping). Only the deploy arm (`workflow_run`) redeploys the host; the push arm only
      builds, so it cannot move the host under the job. The wait is about when the job ran, not when it was dispatched (CTO ruling
      2026-09-28; first used by #5914 issuecomment-5865758722). The reuse holds only while
      `GIT_DATA_STORE_ENABLED` has never been on, which (c) re-reads. No per-id erasure
      trigger exists today, and none is needed before the first flag flip: the store cannot hold a
      repository while the flag has never been on.

      The job waits on the `web-platform-infra-apply` environment approval, which hands it
      `DOPPLER_TOKEN_PRD` and the git-data root key. The operator's approval is the single human input.
      An agent may approve only with the operator's explicit consent in the session for this run,
      and only after checking the run is the one it dispatched:
      `gh run view <id> --json path,event,headBranch,headSha,actor` must read
      `.github/workflows/git-data-cutover.yml`, `workflow_dispatch`, `main`, the merge SHA and the
      session's own actor; then read the environment id with
      `gh api repos/jikig-ai/soleur/actions/runs/<id>/pending_deployments` and approve with
      `gh api -X POST repos/jikig-ai/soleur/actions/runs/<id>/pending_deployments -F 'environment_ids[]=<env-id>' -f state=approved -f comment=<why>`.
      A run still unapproved at the end of the session is cancelled (`gh run cancel <id>`), because
      it holds the `git-data-state` group.

      **Only a run ending `verdict=clear` discharges the collected ids**, and only with all four of
      these recorded:
      - **(a) The served LUKS store.** The run's `clear`, from a run on `main`: `gh run view <id>
        --json headBranch,headSha,event,conclusion` reads `main`, `workflow_dispatch`, `success`, and
        `git merge-base --is-ancestor <headSha> origin/main` succeeds. The annotations
        (`gh api repos/jikig-ai/soleur/check-runs/<job-id>/annotations --jq '.[] | select(.annotation_level=="notice") | .message'`)
        read the nine notice lines; the flag precheck's `TOFU_ARM present` warning is expected
        until step 6, and the `flag=` precheck line appears only in `gh run view <id> --log`.
        (Since PR #9096 a dispatch from `main` reads `TOFU_ARM absent`; a `present` warning there
        is a finding.)
        `probe=store-empty verdict=ok` means no entry under `repositories/` on the served store when
        the run was made, except `.*.init.lock` dotfiles and `lost+found`.
      - **(b) The retained plaintext volume.** Read the **current** instance's `boot_complete` line
        from Better Stack. It must read all three of `plaintext_volume=present`,
        `plaintext_empty=yes` and `served_repos=0`. `plaintext_empty=yes` alone is not this
        evidence: the bootstrap also emits it with `plaintext_volume=absent` when no plaintext
        volume id was rendered, and then it read nothing. `present` means the bootstrap was given
        the id Terraform renders from `hcloud_volume.git_data` and counted that volume through a
        read-only snapshot. Both counts skip `.*.init.lock` and `lost+found`, so (b) says nothing
        about lock files; (d) covers those. git-data ships to its own Better Stack source, so the
        read names that table; the anchor is the replace run's own `boot-trail anchor` line:

        ```bash
        A=$(gh run view <replace-run-id> --log | sed -nE 's/.*boot-trail anchor: ([0-9]+) .*/\1/p' | head -1)
        doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh \
          --table t520508_soleur_git_data_prd_logs --table-s3 t520508_soleur_git_data_prd_s3 \
          "SELECT dt, raw FROM (SELECT dt, raw FROM remote(\$BS_TABLE) UNION ALL SELECT dt, raw FROM s3Cluster(primary, \$BS_TABLE_S3) WHERE _row_type = 1) WHERE dt > fromUnixTimestamp($A) AND JSONExtractString(raw,'stage') = 'boot_complete' AND JSONExtractString(raw,'host_name') = 'soleur-git-data' ORDER BY dt DESC LIMIT 1 FORMAT JSONEachRow" \
          | jq -r '.raw | fromjson | "plaintext_volume=\(.plaintext_volume) plaintext_empty=\(.plaintext_empty) served_repos=\(.served_repos)"'
        ```

        Record it with the replace run that produced the instance (36118115758 unless a later one
        ran), and show that no host was created since: the server's `created` time
        (`doppler run -p soleur -c prd_terraform -- sh -c 'curl --disable --noproxy "*" -sS -H "Authorization: Bearer $HCLOUD_TOKEN" https://api.hetzner.cloud/v1/servers?name=soleur-git-data' | jq -r '.servers[0].created'`)
        falls inside that replace run, and no later `apply-web-platform-infra.yml` dispatch ran a
        `git_data_host_replace` or `git_data_host_create` job to `success`
        (`gh run list --workflow apply-web-platform-infra.yml --event workflow_dispatch --created '>=<replace start>' --json databaseId`,
        then per run `gh run view <id> --json jobs --jq '.jobs[] | select(.name | test("git_data_host_(replace|create)")) | "\(.name) \(.conclusion)"'`).
        The replace run's own poll step already failed the run unless `plaintext_empty=yes`, so a
        `success` there is a second, weaker source. The marker alone is not this evidence: a
        same-instance bootstrap re-run that FATALs before it removes the marker can leave an older
        one in place. The volume has not been mounted by the render since (ADR-239 D2).
      - **(c) The flag was never on, since before either volume existed.** Record the run's flag
        precheck line, then extend "Two reads to record", read 2: page `doppler configs logs` for
        `GIT_DATA_STORE_ENABLED` back past the `created` time of the **older** of
        `hcloud_volume.git_data` and `hcloud_volume.git_data_luks` (read both with the token above:
        `…/v1/volumes?name=soleur-git-data-store` and `…/v1/volumes?name=soleur-git-data-luks-store`,
        `.volumes[0].created`, GET only). The web containers load `--project soleur --config prd`
        only (`ci-deploy.sh`), so `prd` is the config to page; record that. Read the logs after the
        proof run completes. This read is required: the counts see entries, not freed blocks, so a
        repository written and then deleted would be invisible to them, and only the flag's history
        since the volumes were created excludes one.
      - **(d) No lock file for the collected ids.** Once its guards pass, `git-data-remove.sh`
        opens `REPO_ROOT/.<workspace_id>.init.lock` and never removes it. Neither the proof nor the
        bootstrap count sees it, because both skip `.*.init.lock`. The file is 0 bytes, but its name
        is the user's id, so it is personal data on the store. Classify every
        `op:git-data-bare-repo-erasure` event in the window, per id, by its `erasure_outcome` tag
        and `detail`:
        - **host not reached:** `unreachable`, `unauthorized`, `host_key_mismatch`, `unconfigured`
          (including `ssh_client_absent:` since PR #9096), `threw` (since PR #9096 the
          `removeGitDataRepo threw` arm is tagged; its known throws are pre-dial), and events with
          no `erasure_outcome` tag (that arm before PR #9096) — **except** an `unreachable` whose
          `detail` shows the ssh was killed by its 30-second timeout, which may have connected and
          belongs in "lock may exist";
        - **refused before the lock:** `refused`, with a `detail` naming a guard the wrapper runs
          before it opens the lock: missing or unsafe `workspace_id` (empty, dot path, slash, unsafe
          characters), `mountpoint`/`findmnt` unavailable, store not mounted, not served by the
          mapper, store not verified, frozen, repo root not present, repo root not on the store,
          path escapes the repo root, lock path is a symlink;
        - **lock may exist:** any other `refused` detail (for example `could not acquire init lock`
          or `rm -rf failed`), and any detail you do not recognise.

        An id is discharged only if **every** one of its events is in the first two classes. Any
        id with a "lock may exist" event is not discharged here; it follows "If an item cannot be
        read" below. Lock files left by erasures that completed are not this step's to discharge;
        they are tracked in #9066.

      **If an item cannot be read, or an id is in (d)'s "lock may exist" class.** Nothing is
      discharged for the ids it affects; they stay pending. The same day:
      1. Post the record on #5914 using the template, with `outcome:` reading
         `NOT DISCHARGED — <item>: <what was read, and the error or the oldest date reached>`.
         Counts only, no ids.
      2. Open an issue labelled `clo-attestation`, titled
         `git-data Art. 17 discharge blocked (#5914): <item> — earliest Art. 12(3) deadline <date>`.
         Link the record and route it through `soleur:go`. The CLO rules on it and writes the ruling
         to `knowledge-base/legal/audits/`; the operator does not sign it off.
      3. Retry by reads only: (a) by the 5.3 rule; (b), (c) and (d) by re-reading the same source.
         Nothing in this step replaces a read with a write. A host replace to produce a new
         `boot_complete` needs its own authorization and is the CTO's decision.
      4. The CLO rules no later than 7 days before the earliest Art. 12(3) deadline among the
         affected ids. The ruling either discharges on the evidence that was read, with the gap
         stated in a new #5914 record, or extends the deadline under Art. 12(3) by two further
         months. An extension requires telling each affected data subject, with reasons, before
         the first month ends. Their accounts are deleted, so the ruling must name the channel
         that will be used.

      Record on #5914, using this template:

      ```text
      git-data store Art. 17 discharge (#5914, host-key step 5)
      proof run: <run id>  dispatched: <UTC>  head SHA: <sha>  (headBranch main, event workflow_dispatch)
        [reuse: <why an existing run qualifies under the 5.2 reuse rule>]
      notices (9): <the notice-level annotations, each cited by the ##[group]Run step that printed it>
      (a) counted: every entry under repositories/ except .*.init.lock and lost+found
      (b) instance: replace run <id>  boot_complete: <line, showing plaintext_volume=present plaintext_empty=yes served_repos=0>
          server created <UTC>; no replace or create run between that replace and the proof: <gh run list reference>
      (c) flag precheck line: <line>   oldest Doppler log entry reached: <date> (configs: prd)
          volumes created: git_data <UTC>, git_data_luks <UTC>
      Sentry sweep: 2026-09-22T12:07:01Z (the PR #8511 merge) to <time of this record>,
        op:git-data-bare-repo-erasure, not filtered on erasure_outcome, pagination read to the end:
        <n> distinct repository ids in <e> events, Sentry issues <issue ids>
        (the ids are kept only in Sentry extra.gitDataRepoId and are not reproduced here)
        also swept by message text: <the queries>: <n> issues each
        controls: <token/host>, <tag syntax>, <free text>; Better Stack erasure lines: <n> (vs <e> Sentry events)
      (d) per id: <h> host not reached, <r> refused before the lock, <m> lock may exist
      outcome: git-data store (op=git-data-bare-repo-erasure): no repository held for the <n-m> discharged ids
        (no entry under repositories/ on the served store at the proof or on either volume at boot, with
        lock dotfiles and lost+found not counted); nothing to erase
      not discharged: <m> ids, routed to <clo-attestation issue #> | none
      not covered: .<id>.init.lock files left on the served store and on the retained plaintext volume by
        erasures that passed the wrapper's guards, including completed ones (#9066); the user's
        copy in web-1 /workspaces (a separate operation)
      earliest request: <date>  Art. 12(3) deadline: <date>
      ```

      Write "no repository held; nothing to erase", never "erased" and never "no data held". The
      user's copy in web-1's `/workspaces` is erased by a separate operation, and this record must
      not read as covering it. It does not cover lock files left by completed erasures (#9066)
      and says nothing about encryption at rest (#8634).

      **Requests after the window.** The window ends when the #5914 record is written. This record
      discharges nothing after that. The proof does not answer a later request: it reads the store
      as root at one moment and does not see how `git-data-remove.sh` runs for the git user. Each
      later request is answered by its own outcome. Only `erased` closes it; account deletion
      reports `erased` by emitting no `op:git-data-bare-repo-erasure` event, and the lock file it
      leaves falls under #9066. Every event after the record is a pending erasure: any
      `erasure_outcome` (`refused`, `unreachable`, `unauthorized`, `unconfigured`,
      `host_key_mismatch`) and the `removeGitDataRepo threw` arm. Follow its verdict-map row. Then,
      while `GIT_DATA_STORE_ENABLED` has never been on, discharge it by running 5.2 again: a fresh
      proof, fresh reads of (b) to (d), and a new record. After the first flip, emptiness is no
      longer evidence, so the flip must not happen until a per-id re-erasure path exists (#8211).
   3. Any verdict other than `clear` follows its verdict-map row; only `clear` discharges. After
      the row's remedy, re-dispatch **once**. A repeat of the same verdict opens an incident
      instead of a loop, and step 5 resumes with one re-dispatch after the incident closes. If the
      Art. 12(3) deadline is at risk, escalate to the CLO. A `store_not_empty` read stops here and
      follows "Store not empty": erasing those repositories is the incident's decision.
6. **The #5914 follow-up PR.** It deletes the app's unpinned fallback arm (`TOFU_FALLBACK_OPTS` and the
   `null`-pin path), removes `git-auth.ts` from the no-TOFU guard's allow-list
   (`tests/scripts/test-no-tofu-ssh.sh`), and closes #5914. Gate it on the positive step-3 startup line
   (`git_data_pin=present` on the current deploy), not on the absence of Sentry events. It must merge
   before any `GIT_DATA_STORE_ENABLED` flip.
   **Done:** PR #9096. After it, an absent or malformed pin refuses every git-data dial whatever the
   flag says (an erasure returns `unconfigured` `pin_absent:`), and an armed container booting
   without a pin emits `op=pin_absent_at_startup` (ADR-237, Addendum PR #9096). A step-5 record
   whose `outcome:` reads `NOT DISCHARGED` for some ids does not block this step, provided its
   `clo-attestation` issue is open with the earliest Art. 12(3) deadline in its title and nothing
   claims step 5 discharged everything (CLO ruling 2026-09-28): deleting the arm destroys no
   evidence and leaves the reads-only retry untouched. **Never revert PR #9096** to recover from a
   pin fault: a revert restores the unpinned arm AND its Guard 1 allow-list entry, so CI stays
   green. Republish the pin instead (see the pin-fault row).

Step 3 is **not** ADR-220 D6's fresh replace immediately before the real cutover. That replace is still
required; it now also rotates the host key and redeploys the app automatically.

### Deploy-day go/no-go (step 3)

- **GO** requires both:
  - Better Stack shows `git_data_pin=present fp=SHA256:X`, where X is the fingerprint the **source**
    apply run (the replace or birth) printed. The redeploy never reads Terraform state, so it cannot
    print X itself. Read X from that run's log (the same line is in its job summary):

    ```bash
    gh run view <apply-run-id> --log | grep 'git-data host key fingerprint'
    ```

    Then read the startup line. It is logged at warn level because only lines at warn or above reach
    Better Stack. The redeploy can wait up to 75 minutes for its release, so a fixed `30m` window can
    miss the line: start the window at the apply run's start (UTC), and read the newest line after
    the redeploy run's deploy finished:

    ```bash
    doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh \
      --since 'YYYY-MM-DD HH:MM:SS' --grep git_data_pin=
    ```

  - Zero Sentry events tagged `erasure_outcome` between the replace dispatch and that line. The query
    must print nothing; read any issue it lists in full with `scripts/sentry-issue.sh`:

    ```bash
    SENTRY_ISSUE_RO_TOKEN=$(doppler secrets get SENTRY_ISSUE_RO_TOKEN -p soleur -c prd --plain)
    curl -fsS -H "Authorization: Bearer ${SENTRY_ISSUE_RO_TOKEN}" \
      'https://jikigai-eu.sentry.io/api/0/organizations/jikigai-eu/issues/?query=feature%3Aaccount-delete%20op%3Agit-data-bare-repo-erasure%20has%3Aerasure_outcome&start=<dispatch ISO>&end=<now ISO>' \
      | jq -r '.[] | [.id, .count, .title] | @tsv'
    doppler run -p soleur -c prd -- scripts/sentry-issue.sh --latest-event <issue-id>
    ```

    If there are any, collect the repository ids with the sweep query under "Store not empty" (step
    3) and discharge them in post-merge step 5.
- `git_data_pin=absent` or `git_data_pin=invalid` on the new deploy is **NO-GO**: the release did not
  load the pin. Re-run the redeploy (`gh run rerun <pin-redeploy-run-id> --failed`, or
  `gh workflow run git-data-pin-redeploy.yml --ref main -f source_run_id=<apply-run-id>`), then read
  again. If the gate exited 1 with `verdict=unidentified`, or printed `verdict=pin_published` or `verdict=pin_maybe_published`, dispatch
  `gh workflow run git-data-pin-redeploy.yml --ref main` with no `source_run_id` instead.
- **The first rotation cannot produce `host_key_mismatch`.** Until the redeploy, the app has no pin
  and stays on its fallback arm against the new host. Pin lag matters only from the second rotation
  on, and once the store flag is on it stalls replication pushes and fetches as well as erasures.
  **Since PR #9096 (#5914):** there is no fallback arm. A container without a pin refuses
  (`unconfigured` `pin_absent:`) and emits `op=pin_absent_at_startup`; a rotation's stale-pin window
  is unchanged (`host_key_mismatch` until the pin-redeploy follower loads the new pin).
- **A full revert of PR #8511 is never the rollback.** It would restore trust-on-first-use on every
  path. Every fix goes forward.

### Between merge and step 3

- **A dry run refuses at the precheck** with `verdict=git_data_host_key_unavailable reason=absent`
  (exit 5): no pin is published yet. That is expected. Run step 3; do not work around it.
- **Expected drift.** `scheduled-terraform-drift` shows a pending **replace of `hcloud_server.git_data`**
  (its `user_data` now carries the host key) plus creates of `tls_private_key.git_data_host_ssh` and
  `doppler_secret.git_data_ssh_host_key`, until step 3 applies them. Neither address is on any per-PR
  `-target` list, so no routine apply publishes a pin the live host does not carry.
- **Drift is red for this whole window, including the rung-2 gap.** While these three addresses are
  pending, a red drift verdict says nothing about anything else. Read other drift from the plan diff:
  any address other than these three is real drift. Step 3 is the deadline for this blind spot, so
  do not let the window run on.
- **The app logs `git_data_pin=absent`** at every start, and Sentry receives one
  `feature=git_data_host_key_pin op=pin_absent_store_disabled` event per process. Expected until step 3.
  Historical since step 3 (2026-09-25): PR #9096 deleted that event; an armed container without a pin
  now emits `op=pin_absent_at_startup` instead, and every erasure refuses.

### Operator-local applies enforce `host_key`

Every Terraform `connection` block that dials web-1 now sets `host_key = local.web_1_ssh_host_key`, so
an operator-local apply verifies web-1 exactly as CI does. A local apply must also export
`TF_VAR_terraform_version` equal to the workflows' `TERRAFORM_VERSION` (currently `1.10.5`), or it
re-triggers `terraform_data.web_1_host_key_probe`. If an operator-local apply fails at a
provisioner with a host-key error, the committed pin is wrong or web-1 was re-keyed: follow the H4
triage below. Do not edit the pin file to whatever the laptop sees; a re-capture follows the web-1
re-capture section.

### The rung-2 emergency-replace gap

PR #8511 changed the hash-bound git-data payload, so the rung-2 interlock refuses **every** git-data
birth and replace — an emergency one included — from its merge until the step-2 evidence PR lands.
ADR-237 records this as an accepted gap. Keep the window short: schedule the rehearsal right after
merge.

- **The break-glass path inside the gap** is the operator-local apply under the
  `OPERATOR_APPLIED_EXCLUSIONS` contract (ADR-096), with its own explicit authorization. Give it the
  same `-replace` and `-target` set as the gated replace job, so the host key rotates and the secret
  publishes with the host, and export `TF_VAR_terraform_version` as above. It triggers no
  `git-data-pin-redeploy.yml` run (that listens only for the apply workflow): dispatch
  `gh workflow run git-data-pin-redeploy.yml --ref main` (no `source_run_id`, so it redeploys
  unconditionally) afterwards. Read X from the published pin
  (`doppler secrets get GIT_DATA_SSH_HOST_KEY -p soleur -c prd --plain | ssh-keygen -lf -`), then read
  the startup line as in the go/no-go.
- **The known-good-tag route** under "Break-glass for the rung-2 interlock" is not a substitute. Inside
  the gap the only candidate tag predates PR #8511 (PR #8511 deleted the evidence file, so find it
  with `git log -1 --diff-filter=AM --format=%H -- apps/web-platform/infra/git-data-rung2-boot-evidence.env`;
  a plain `git log -1` returns the deletion): it boots a host with sshd's self-generated keys and
  publishes no pin, so it restores the pre-#8511 state (the app on its fallback arm, dry runs refusing
  `reason=absent`). Once a pin is published, a replace from such a tag leaves the pin not matching the
  host, and every pinned consumer fails `host_key_mismatch reason=changed`. Never use a pre-#8511 tag
  after step 3.

## The LUKS-serving render (PR1 of #8211)

PR #8564 makes the git-data render serve `/mnt/git-data` from the LUKS mapper `/dev/mapper/git-data`
at boot. There is no plaintext/LUKS toggle, no runtime repoint, and no separate cutover run that
moves the device. Why, what it costs, and which gaps are accepted: **ADR-239**. This section is only
what to do.

**The serving change is the ADR-237 step-3 replace.** It is the same `git-data-host-replace` that
publishes the host-key pin — PR #8564 adds no second replace. It runs while `GIT_DATA_STORE_ENABLED`
is off and the store holds no repository, and the fresh host comes up on the mapper.

**The #8511 rung-2 re-rehearsal is held until PR #8564 merges.** PR #8564 changes the hash-bound
payload, so it voids any evidence rehearsed for #8511 alone. Rehearsing #8511 first would buy a
rehearsal that PR #8564's merge immediately invalidates. The hold is posted on #5914; it replaces
"dispatch the rehearsal right after merge" in host-key post-merge step 2. One rehearsal on `main`,
after PR #8564 merges, covers both payloads and serves both ADR-237 post-merge step 2 and PR
#8564's own gate.

The rehearsal must read, in `boot_complete`:

```text
luks_mounted=yes fence_on_mapper=yes erasure_probe=yes plaintext_empty=yes
```

and its reboot arm must read `luks_reopen_ok action=reopened target=/mnt/git-data`. Any other
`target`, or any terminal boolean reading `no`, is a FAIL: see
[the rehearsal runbook](git-data-rung2-rehearsal.md#the-pr-8564-payload-what-the-rehearsal-must-read).

### Two reads to record before dispatching step 3

Both are linked from the replace run's summary. Neither touches a host.

1. **The flag is not `true`.** Dispatch `git-data-cutover.yml` from `main`. Before the replace it
   refuses at the precheck with:

   ```text
   verdict=git_data_host_key_unavailable reason=absent
   ```

   That line is the proof. `git-data-flag-precheck.sh` reads `GIT_DATA_STORE_ENABLED` and refuses
   `flag_already_true` **before** it reads the pin, so reaching the pin refusal means the flag was
   not `true`.

2. **The flag has never been `true`, for the CLO record.** Page back through the config log until
   the oldest entry predates the host's birth (2026-09-14):

   ```bash
   doppler configs logs -p soleur -c prd --page 1 --number 100
   doppler configs logs get <log-id> -p soleur -c prd
   ```

   Open any entry naming `GIT_DATA_STORE_ENABLED`. Record the oldest date the paging reached, so
   the record says how far back the evidence goes rather than implying it is unbounded.

### Boot order on the replace: what is already published when the poll reds

Measured against `apply-web-platform-infra.yml`, `git-data.tf` and
`.github/actions/dispatch-web-redeploy/source-run-gate.sh`, not asserted from the plan:

- In job `git_data_host_replace`, the step `Terraform apply (git-data-host -replace)` (id `apply`)
  runs **before** the step `Poll for the git-data boot-completion signal (replace)` (id `poll`).
  `doppler_secret.git_data_ssh_host_key` carries `depends_on = [hcloud_server.git_data]` and is
  written by that apply. **So a red boot poll leaves the new pin already published to `prd`.**
- `git-data-pin-redeploy.yml` triggers on the apply workflow's `workflow_run` `completed`, whatever
  the conclusion, so the follower run does start. Its gate then reads the source run's jobs and
  their apply steps (#8710), and proceeds **only** when `git_data_host_replace` concluded `success`
  **and** its step `Terraform apply (git-data-host -replace) — both-volumes-preserved assert`
  concluded `success`. A boot-poll red fails that job after the apply succeeded, so
  `source-run-gate.sh` emits a `::warning::` carrying `verdict=pin_published`, sets the gate output
  `pin_published=true` and emails ops ("git-data pin published but the app was not redeployed"):
  **the redeploy does not fire by itself.**
- Recovery for that skip is a dispatch with **no** `source_run_id`, because passing the same id
  re-reads the same non-success and skips again:

  ```bash
  gh workflow run git-data-pin-redeploy.yml --ref main
  ```

### If the fresh host fails a boot check after step 3

Applies to `plaintext_unverified`, `plaintext_residue`, `luks_residue`, `fence_on_mapper=no` and
`erasure_probe=no`.

**Start with a read, never with another replace.** A second replace re-runs the same render against
the same volumes and reproduces the same FATAL, while destroying the host whose boot events are the
evidence.

1. Read the host's boot events. Better Stack carries `stage:bootstrap` with the FATAL reason;
   Sentry carries the same event through the `git_data_boot_fatal` rule:

   ```bash
   doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh \
     --since '<replace dispatch, UTC>' --grep 'FATAL'
   ```

2. Count the Art. 17 refusals opened by the window. No marker was written, so every Delete Account
   since the replace was **refused** — the deletion itself completed and nothing was left behind,
   because the store is empty, but each refusal is an Art. 17 event. Sweep the repository ids with
   the query under [Store not empty](#store-not-empty-store_not_empty) (step 3), widening its period
   to the replace dispatch, reading `extra.gitDataRepoId`, counts only, plus host-key step 5.1's
   message-text sweep for any part of the window before PR #9096.
3. **The fix is forward: PR, then rehearsal, then the evidence PR, then the replace.** That is hours
   to days. There is no shortcut, and the decision to hold or proceed is the operator's.
4. **There is no revert to a pre-PR1 tag.** Any tag without PR #8564 must also postdate PR #8511
   (see "The rung-2 emergency-replace gap"), and no rung-2 evidence exists for #8511's template
   alone — so such a tag cannot be birthed or replaced either. A pre-#8511 tag is worse still: it
   publishes no pin, and after step 3 every pinned consumer then fails `host_key_mismatch
   reason=changed`.
5. After the forward fix lands and a green replace reports `boot_complete` with every terminal
   boolean `yes`, **re-drive each swept id** and record each one on the Art. 17 record, so the
   register shows a discharge and not only a refusal.

`plaintext_residue` is the one branch that is not forward-only: the plaintext volume holds something,
it is retained and was only ever mounted read-only, so nothing has been lost. Stop, escalate to the
CLO, bump **#8571** (copy mode), and block the wipe until that decision is taken. Do not wipe either
volume — the contents are the evidence.

### 2026-09-24: the step-3 replace FATALed on a dirty journal (#5274)

Recorded, not edited into the steps above. Run 35979304442 applied cleanly and published the new pin
(`SHA256:WRk5AW6j9IHNpE9KJ3FpVZbDp4I9HerMD84LGP0uB48`); the fresh host FATALed at 09:09:30Z with
`reason=journal … has needs_recovery set` — ADR-239's accepted dirty-journal gap, because the
predecessor was destroyed while the plaintext volume was mounted read-write. Nothing was written.
The Art. 17 sweep over 09:07Z-09:32Z found no `erasure_outcome` issue. The forward fix reads the
volume through a dm snapshot and makes the rung-2 rehearsal reproduce a dirty journal (ADR-239
amendment 2026-09-24).

**The sequence, each dispatch stopping for the operator's explicit per-command go-ahead**
(`hr-menu-option-ack-not-prod-write-auth` — a menu acknowledgement is not write authority):

| # | Dispatch | Precondition | Clean means |
|---|---|---|---|
| G1 | `git-data-rung2-rehearsal.yml` `dry_run=false` (paid) | the fix PR merged | the run concludes `success`, and its evidence lands through an evidence-only PR |
| G2 | `apply-web-platform-infra.yml` `apply_target=git-data-host-replace plan_only=true` | the evidence PR merged **and** `gh issue view 8710 --json state,closedByPullRequestsReferences` shows #8710 closed by a merged PR (otherwise this rehearsal fires a production redeploy again) | the job's destroy-guard (`git_data_host_replace_gate`, `tests/scripts/lib/git-data-host-replace-gate.sh` — the single source for which addresses a replace may touch; neither volume is among them) admits the plan and the run concludes `success`, and the pin-redeploy run it triggered did not redeploy: find it with `for id in $(gh run list --workflow git-data-pin-redeploy.yml --created ">=<G2 start>" --json databaseId --jq '.[].databaseId'); do gh run view "$id" --log \| grep -F "in run <G2 run id>" \| grep -q 'verdict=no_apply' && echo "$id"; done`, then `gh run view <that id> --json jobs --jq '.jobs[] \| select(.name == "redeploy") \| .conclusion'` prints `skipped` (the gate did not proceed, so its `redeploy` job never ran). For reference, run 35979304442 planned `6 to add, 1 to change, 4 to destroy` because `tls_private_key.git_data_host_ssh` and `doppler_secret.git_data_ssh_host_key` were not yet in state; with both in state the counts differ, so compare against the gate, never against that line. (Check amended 2026-09-24 by #8710: the pin-redeploy run always starts, so read its verdict rather than its absence.) |
| G3 | the same, real (one attempt) | G2 read clean | GO, below |
| G4 | `git-data-cutover.yml` strict dry run | G3's `boot_complete` | `role=git-data-auth verdict=ok` |

Between G1 and the evidence PR, hold every merge that touches a file the evidence hash binds: each
voids the hash and costs another paid G1 (cap: 2 per payload hash). The set is derived, not listed
— `git_data_rung2_bound_files` in `tests/scripts/lib/git-data-birth-readiness-gate.sh` prints it
(17 files on 2026-09-24: `cloud-init-git-data.yml`, the three `modules/git-data-userdata/*.tf`, and
the 13 `file()`-bound payloads, among them `git-data-bootstrap.sh`, the `git-data-gc*`,
`git-data-luks-reopen*` units and scripts, and `git-data-{provision,remove,transport-wrapper,pre-receive-placeholder}.sh`).

**Downtime.** G3 destroys the serving host: git-data serves nothing from the destroy until the new
host's `boot_complete`, and the pin redeploy that follows redeploys the web platform to load the new
fingerprint. Dispatch G3 in a low-traffic window.

**GO for G3 means all three:** Better Stack shows `git_data_pin=present fp=<G3's fingerprint>` from
a pin redeploy caused by **that** replace run (not 35979135707, which the `plan_only` rehearsal
triggered — #8710 — and not 35980551109); zero Sentry `erasure_outcome` events in the window; and G4
reads `role=git-data-auth verdict=ok`. The replace boot must also emit `boot_complete` with
`plaintext_journal=dirty plaintext_empty=yes fence_on_mapper=yes erasure_probe=yes`. A production
`plaintext_journal=clean` is **NO-GO and an incident**: the volume was measured dirty on 2026-09-24,
so a clean journal means something replayed it — a write to the retained volume.

**G3 is capped at one attempt.** A failed G3 leaves the Doppler pin naming a host that serves nothing
(harmless: nothing can use git-data until a boot writes the marker, and the next replace re-pins).
Recovery is a read first, never a second replace.

**Art. 12(3).** Sweep the refused erasures from Sentry over the window **from the start of run
35979304442** (refusals began when the predecessor was destroyed, not at the 09:09:30Z FATAL) to the
G3 marker, querying `op:git-data-bare-repo-erasure` (pre-FATAL refusals may have surfaced through the
`removeGitDataRepo threw` path rather than `erasure_outcome`), and re-drive each id by
**2026-10-24**. Record the count and the Sentry issue ids on #5914, never the ids themselves (host-key step 5.1). If G3 has not reached GO well before then,
escalate to the CLO rather than rushing G3.

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
| Between the PR #8511 merge and post-merge step 3 | `verdict=git_data_host_key_unavailable reason=absent` (exit 5, precheck) | Expected: no pin is published yet. Run host-key step 3. |
| After step 3, `GIT_DATA_SSH_HOST_KEY` missing from `prd` | `verdict=git_data_host_key_unavailable reason=absent` (exit 5) | The TF-owned secret was deleted outside Terraform. Read `doppler configs logs --project soleur --config prd` for who removed it, then re-dispatch `git-data-host-replace`, which rotates and republishes. An unexplained removal is a Breach-triage trigger. |
| The published pin is not one ED25519 key line | `verdict=git_data_host_key_unavailable reason=invalid` (exit 5) | Terraform only writes a valid key, so the value was edited outside it. Same as the row above: read the config log, re-dispatch the replace, and treat an unexplained edit as a Breach-triage trigger. |
| A replace failed before the new server was created | the replace gate refuses the retry (no server to delete); state holds the new key and the old host's pin | Re-dispatch `git-data-host-create` (`git-data-birth.md`). The birth gate accepts the pin `update` only while the same plan creates `hcloud_server.git_data`. |
| The app, an Art. 17 erasure, pin fault | Sentry `erasure_outcome=unconfigured` with `detail` starting `pin_invalid:` or `pin_absent:` (match with the colon: `pin_absent` prefixes the pre-#9096 word `pin_absent_store_enabled:`, which older events carry); at boot, `op=pin_absent_at_startup` or `op=pin_invalid_at_startup` | The app's pin resolver refused before dialing: the published pin is malformed, or absent (since PR #9096, whatever the store flag says; before it, only while the flag was on). Nothing was erased. Fix the pin (re-dispatch `git-data-host-replace`, or re-run `git-data-pin-redeploy.yml` if the secret is present but not loaded; for a pre-#9096 `pin_absent_store_enabled` also check the flag, see "Flag already on"), then discharge the ids as in host-key step 5: that sweep is what keeps the login page's "will be completed" promise. Once the sweep is recorded, **resolve** the Sentry issue (never archive or ignore it, since a muted group fires no trigger). Since #8572 `art17-erasure-incomplete` also re-pages per event, at most one email per issue per 5 minutes (not one per refusal), so an issue left open no longer swallows the next fault; resolving still marks the sweep done. Since PR #9096 each `unconfigured` reason has its own issue (`git-data erasure unconfigured (<reason>): …`, tag `erasure_reason`), so query `feature:account-delete op:git-data-bare-repo-erasure erasure_reason:pin_absent` for the first event (earliest date and a count only). A destroy/recreate of the `GIT_DATA_SSH_HOST_KEY` secret triggers no redeploy follower: dispatch `git-data-pin-redeploy.yml` by hand. Boot-time signals: `feature:git_data_host_key_pin op:pin_absent_at_startup` / `op:pin_invalid_at_startup`, `feature:git_data_ssh_client op:ssh_client_absent_at_startup` (since #8572 these page through `git-data-host-key-pin-fault`, keyed on the `pin_fault` tag; after resolving one, run the Sentry query `pin_fault:*` over the last 4 h, because a fault that recurs within the rule's 4-hour interval after a resolve does not page again), and the Better Stack lines `git_data_pin=` and `git_data_ssh_client=`. An `unconfigured` with `ssh_client_absent:` means the image has no `ssh`: ship `openssh-client` in the runner stage (PR #9096), then sweep. Count the Art. 12(3) one-month deadline from the first `pin_absent:` event and route such events to a `clo-attestation` issue with that deadline in its title, as step 5 does for `NOT DISCHARGED`. Limit: "discharge as in step 5" works only while `GIT_DATA_STORE_ENABLED` has never been on; after the first flip it depends on #8211's per-id re-erasure path. An `unconfigured` whose `detail` starts `remove_key_absent:` is a different fault: the remove key is missing while git-data is otherwise armed (a partial birth or a half-applied rotation), and the pin is not involved. |
| The app, a replication push, pin fault (#8572) | The `git-data-host-key-pin-fault` email; Sentry `feature:worktree_lease op:git_data_replication_push pin_fault:<reason>`, message `git-data replication push pin fault (<reason>): …` (one issue per reason) | The session-end push was refused or failed on the pinned host key. `pin_absent` / `pin_invalid`: republish the pin (re-dispatch `git-data-host-replace`), or re-run `git-data-pin-redeploy.yml` if the secret is present but not loaded. `ssh_client_absent`: the image has no `ssh`; ship `openssh-client` in the runner stage. `host_key_mismatch`: `extra.via` says which dial failed (`ssh` = the provision dial, `git` = the push); the `git-data-cutover.yml` dry-run precheck splits `alg` / `unknown` / `changed` in `_access_reason` without SSH. The match also fires on an absent or unwritable known_hosts file under `StrictHostKeyChecking=yes`, and the tag is advisory: ssh passes the remote's stderr through, so a host that already holds the pinned key can print host-key text. **Never re-pin to the key a host presents** (see "Host-key mismatch (H4)"). Verify without SSH: `doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh --since 30m --grep 'git_data_pin=present fp='` shows the redeployed pin loaded with the expected fingerprint (a `warn` line, so Vector ships it; the `git-data replication push complete` line is `info` and never reaches Better Stack), then `scripts/sentry-issue.sh` shows no new `pin_fault:*` event after the next session end. Catch-up: the replica self-heals at each workspace's next session end, which force-pushes every head and tag; commits made in the window exist only on the host until then. The rule re-pages at most every 4 h per issue; after resolving, run the `pin_fault:*` query over the last 4 h. |
| The pin read failed | `verdict=git_data_host_key_unavailable reason=<word> rc=<n>` (exit 5; the same reason words as `flag_read_failed`, e.g. `auth_invalid`, `forbidden`, `network`) | The same token and read as the flag; handle it like `flag_read_failed`. Re-dispatch once; a repeat means the `DOPPLER_TOKEN_PRD` token needs replacing. |
| The committed web-1 pin file is malformed | `verdict=web_1_host_key_invalid` (ssh_config step) | A defect in `apps/web-platform/infra/web-1-ssh-host-key.pub` on the dispatched ref. Fix it in a reviewed PR (see "Re-capturing web-1's host key"). |
| **L7 host identity** — a hop presented a key other than its pin | `role=<web\|git-data-jump\|git-data-auth> verdict=host_key_mismatch reason=changed` | Rule out L3 and L7 auth first, then follow "Host-key mismatch (H4)" below. The app's own `pin_fault=host_key_mismatch` (#8572) is read from ssh stderr, which is the same text an absent or unwritable known_hosts file produces under `StrictHostKeyChecking=yes`, so confirm with this precheck before treating it as a changed key. |
| **L7 host identity** — no pin for the alias | `verdict=host_key_mismatch reason=unknown` | A configuration bug (a typo'd `HostKeyAlias` or an empty known_hosts file), not an attack signal. Fix the workflow in a reviewed PR. |
| **L7 host identity** — the host offers no key of the pinned algorithm | `verdict=host_key_mismatch reason=alg` | web-1 must offer ECDSA-P256 and git-data ED25519. For git-data, the boot proof should have failed the replace first: read its `stage:sshd_config` events. Then follow "Host-key mismatch (H4)". |
| The `prd` read token is empty | `verdict=flag_token_absent` (exit 5) | The `DOPPLER_TOKEN_PRD` repo secret is unset or not passed to this run. Restore it, then re-dispatch. |
| The flag read failed | `verdict=flag_read_failed reason=<word>` (exit 5) | `network`: re-dispatch. `auth_invalid`, `forbidden`, `config_not_found`, `scope_mismatch`: the token behind `DOPPLER_TOKEN_PRD` is revoked, lacks `prd` read, or resolves another config; replace it, then re-dispatch. `unknown`: re-dispatch once, then open an issue. |
| The flag is already on | `verdict=flag_already_true` (exit 5) | **Incident.** See "Flag already on" below. |
| The store root is not mounted on a device | `probe=store-mounted verdict=old_store_unmounted` (exit 5) | Read the host's git-data boot events in Sentry before anything else; both volumes are retained. **Before** the step-3 replace this means the plaintext volume did not mount, and the remedy is to re-dispatch the replace. **After** it, the mapper did not mount, which is a boot FATAL: follow "If the fresh host fails a boot check after step 3" and do not re-dispatch a replace first. |
| **Configuration fault** — an unsafe configured path | `probe=config verdict=probe_failed reason=arg_root\|arg_subdir\|arg_marker\|arg_mapper\|arg_wrapper` (exit 5) | Nothing was dialed and the value was not printed. `OLD_ROOT`, `REPO_SUBDIR`, `STORE_VERIFIED`, `LUKS_MAPPER` or `TRANSPORT_WRAPPER` reached the script with an unsafe value: the workflow sets none of them, so something (a workflow `env:` or a `$GITHUB_ENV` write in an earlier step) injected it. Do not re-dispatch; find and remove the injection in a reviewed PR. |
| **Incident, served device wrong** — the store root is served by something other than the LUKS mapper | `probe=store-on-mapper verdict=store_not_on_mapper` (exit 5) | The ADR-239 render cannot produce this. The wrappers refuse on the same device check, so every erasure is refused: sweep Sentry for the Art. 17 refusals with the query under "Store not empty" (step 3), and escalate to the CLO if an Art. 12(3) deadline is at risk. Read the current instance's boot_complete line and its `stage:bootstrap` events first, then follow "If the fresh host fails a boot check after step 3". Never re-dispatch a replace before that read. |
| **Wrappers refusing now** — the bootstrap's store marker is missing, or the filesystem has no UUID | `probe=store-verified verdict=store_unverified reason=no_fs_uuid\|marker_absent` (exit 5) | Every provision, erasure and push is refusing on the host. Sweep Sentry for the Art. 17 refusals it opened, with the query under "Store not empty" (step 3), then follow "If the fresh host fails a boot check after step 3". `no_fs_uuid`: the mounted filesystem reports no UUID. `marker_absent`: the marker is missing, empty or not a file; a boot FATAL removes it, so read the boot events. |
| **Tampering signal** — the marker names another filesystem | `probe=store-verified verdict=store_unverified reason=marker_mismatch` (exit 5) | Every wrapper refuses. With a matching boot FATAL (a mapper reopened on another volume, a writer defect), route as "Wrappers refusing now". With **no** boot FATAL it is a Breach-triage trigger: open an incident first, and do **not** replace the host until the incident releases it: a replace destroys the host and rewrites the marker, which is the evidence. Host-key step 5 resumes only after the incident closes, by its step-5.3 rule. |
| **Frozen** — the freeze sentinel exists | `probe=store-verified verdict=cutover_frozen` (exit 5) | Provision, remove, the transport wrapper (pushes and fetches) and pre-receive all refuse now (gc does not read the sentinel). Nothing writes the sentinel today and nothing removes it, it sits on the retained LUKS volume, and SSH is barred. Open an incident (Breach-triage trigger) and escalate to the CLO, because the Art. 12(3) clock runs. The only removal path is a bootstrap step that deletes the sentinel, which is hash-bound: it ships through the [two-PR sequence](git-data-rung2-rehearsal.md#changing-the-payload-the-two-pr-sequence) (payload PR, rung-2 rehearsal, evidence PR) and then a `git-data-host-replace` — days, not hours. It is not gated on #5914 or the rest of #8211. Host-key step 5 resumes by its step-5.3 rule. |
| **Store session could not be answered** — the store-verified stage | `probe=store-verified verdict=probe_failed rc=5\|6\|16` (exit 5) | `rc=5`: `findmnt` could not read the store's source or its filesystem UUID; re-dispatch once, a repeat is an incident. `rc=6`: the store source is not the one the first probe read — it changed or something is mounted over it. That is not transient: open an incident, and discharge nothing until it explains the change. `rc=16`: `head` could not read the marker; re-dispatch once, a repeat is an incident. Other `rc` values read as in the last row below. |
| **Store session could not be answered** — the store-empty stage | `probe=store-empty verdict=probe_failed rc=3\|4\|7\|8\|9\|96` (exit 5) | Every store-verified fact held, then the count could not be taken. `rc=3`: `repositories` is a dangling symlink or not a directory. `rc=7`: it is missing (the bootstrap always creates it). `rc=8`: its containing mount is not the store root, so a second mount is hiding what lies under it. `rc=9`: `readlink`/`stat` could not resolve it. `rc=4`: `find` failed. `rc=96`: the count answer was malformed. None of these is transient and an empty store produces none of them: open an incident, and discharge nothing. |
| The store holds repositories | `probe=store-empty verdict=store_not_empty` (exit 5) | **Incident.** See "Store not empty" below. Since #8211 PR2 this counts every entry under `repositories/` (the bootstrap's `_repo_count` rule), not only `*.git`. |
| A probe could not be answered | `probe=store-mounted verdict=probe_failed rc=<n>`, or any probe's `rc=124\|255\|141` (exit 5) | `rc=124`: the 30 s bound expired; re-dispatch. `rc=255`: ssh transport failed; read the heartbeat, then re-dispatch. `rc=141`: the answer was larger than the cap. `rc=96` from store-mounted: the answer did not match the expected pattern; re-dispatch once, then open an incident. No `rc` from store-on-mapper or store-verified: the first probe left nothing to compare; re-dispatch once. |
| The pre-receive fence is not intact | `probe=fence-shape verdict=fence_not_intact reason=hooks_dir_absent\|hooks_dir_owner\|hook_absent\|hook_owner\|hooks_parent_writable\|hook_not_runnable_by_git\|hooks_path_mismatch\|transport_pin_mismatch\|hooks_wrong_source` (exit 5) | **Incident first.** A root-owned path or mount changed on git-data (before post-merge host-key step 3, on a host whose SSH key was not yet pinned, #7226). Capture the run's annotations and its `probe-stderr:` lines (`gh run view <run-id> --log`), then open an incident (Breach-triage trigger). Then dispatch `apply-web-platform-infra.yml` with `apply_target=git-data-host-replace`, which re-runs the bootstrap; the pre-cutover replace plus `GIT_DATA_LUKS_KEY` rotation (ADR-220 D6) is still required afterwards. The bootstrap FATALs at boot on the ownership, executable and `core.hooksPath` facts; it does not check the device, the parent directory, the wrapper pin or the `git` user's access. The words:<br>`hooks_dir_absent` — the hooks directory is missing or is a symlink. A symlink survives a replace (the volume is retained), so remove it in the incident first.<br>`hooks_dir_owner` — the hooks directory is not `root:git 750`.<br>`hook_absent` — `pre-receive` is missing, a symlink, not a regular file, or not executable.<br>`hook_owner` — `pre-receive` is not `root:root 755`.<br>`hooks_parent_writable` — the hooks directory's parent is not root-owned, or is group/other-writable.<br>`hook_not_runnable_by_git` — the `git` user cannot read and execute `pre-receive` (group membership, an ACL, a denied traversal). Git would skip the hook and accept the push.<br>`hooks_path_mismatch` — the effective system `core.hooksPath` is unset or names another path.<br>`transport_pin_mismatch` — the installed transport wrapper no longer pins pushes to the serving hooks directory.<br>`hooks_wrong_source` — the hooks directory or `pre-receive` is on a different device from the store. |
| The fence probe could not be answered | `probe=fence-shape verdict=probe_failed rc=5\|16` or `reason=arg_root\|arg_source\|arg_serving\|arg_wrapper` (exit 5) | `rc=5`: `findmnt` could not resolve a fence path's device. `rc=16`: an instrument on the host failed; the `probe-stderr:` lines in `gh run view <run-id> --log` name which (`stat`, or `git config` exiting above 1). Re-dispatch once; if it repeats, dispatch `git-data-host-replace`, since an instrument failing on a bootstrapped host is itself drift. `reason=arg_root\|arg_source\|arg_serving\|arg_wrapper`: the probe was called with an empty or unsafe argument. That is a code or configuration fault: do not re-dispatch, fix the caller. Other `rc` values read as in the row above. |
| A stale invocation asking for a real mode | `verdict=real_cutover_unreconciled` (exit 5) | Nothing to do. The dry run is the `proof`; the flip and the flag-off-only rollback remain on #8211. |
| The fresh host could not verify the retained plaintext volume | Better Stack / Sentry `stage:bootstrap` `FATAL: plaintext_unverified reason=<mount\|source\|journal\|umount\|snapshot>` | Since 2026-09-24 (#5274) the volume is set kernel read-only and read through a throwaway dm snapshot, never mounted itself. `source` = the device is not the plaintext volume (not a block device, LUKS, has holders or no sysfs entry, its device number changed, the snapshot's origin is another device) or the mount is not the snapshot, or `repositories` on the snapshot is not a real directory; `snapshot` = the read-only flag or the snapshot apparatus failed (journal geometry, loop, `dmsetup create`, an invalidated COW, a previous run's snapshot still present, unreadable sector counters); `mount` = the snapshot did not mount or its tree is unreadable; `journal` = the journal did not replay cleanly into the snapshot (still needs recovery, `with errors`, `errors_count` after replay differs from the volume's historical error count, or it moved during the count); `umount` = a transient device could not be torn down. **One `snapshot` FATAL is an incident, not a refusal:** `… was written or discarded (sectors a b -> c d)` means the retained volume's written- or discarded-sector counters moved during the read — open an incident (Breach-triage trigger) and route to the CLO; every other FATAL here wrote nothing. The FATAL detail carries `kernel=<overflow\|jbd2\|ext4-error\|none> cow=<used/total>`. No store marker exists, so every erasure refuses. A repeated journal-class FATAL on the production volume routes to the #8571 wipe decision and the CLO, never to another replace. Follow "If the fresh host fails a boot check after step 3". |
| The retained plaintext volume holds repository entries | `FATAL: plaintext_residue count=<n>` | **Stop.** The data is read-only on a retained volume. Escalate to the CLO, bump #8571 (copy mode) and block the wipe. Do not wipe or replace. See the residue paragraph in "If the fresh host fails a boot check after step 3". |
| The LUKS volume itself holds repository entries | `FATAL: luks_residue count=<n>` | An adopted volume carries content this register has not recorded. No marker is written and the host serves nothing. Treat it as "Store not empty": open an incident and route it to the CLO before any erasure or wipe. |
| The pre-receive fence did not land on the mapper | `FATAL: fence_on_mapper=no`, and `boot_complete` `fence_on_mapper=no` | The hooks landed under the mountpoint instead of on the serving device, so a push would run an unfenced hook. No marker is written. Forward fix; follow "If the fresh host fails a boot check after step 3". |
| The boot erasure self-probe failed | `FATAL: erasure_probe=no`, and `boot_complete` `erasure_probe=no` | The bootstrap removed the marker before the FATAL, so the Art. 17 path is fail-closed rather than silently broken. Forward fix, and sweep and re-drive the refused ids; follow "If the fresh host fails a boot check after step 3". |

L3 and L7 are different faults: L3 is reachability (NIC, sshd, host), L7 is authorization (the key).
Read the private-NIC heartbeat before treating an L7 verdict as a key problem.

### Host-key mismatch (H4)

A host-key failure is its own verdict, `host_key_mismatch`, and never a timeout. Triage it only after
the lower layers, in this order:

1. **H1, L3 admission.** The bridge reports `ci_ssh_access_denied` or `ci_ssh_liveness_*`: Cloudflare
   Access or the tunnel, not the pin.
2. **H2, L3 private network.** The git-data hop times out: read the private-NIC heartbeat. A key
   mismatch never produces a timeout.
3. **H3, L7 auth.** `reason=auth_refused` means the wrong CI or root key; the pins do not touch it.
4. **H4, L7 host identity.** Likely causes, in order:
   - **(a) web-1's committed pin was captured wrong** (`role=web`, or a bad web-1 line surfacing under
     `role=git-data-auth`, below). Remedy: a re-capture PR (see "Re-capturing web-1's host key").
   - **(b) git-data was re-keyed outside the gated replace job,** so the published pin is not the key
     the host serves. Remedy: dispatch `git-data-host-replace`, which rotates the key, republishes the
     pin and redeploys the app.
   - **(c) a real impersonation.**

**Role attribution caveat.** The jump hop's `ProxyCommand` ssh shares stderr with the outer ssh, so a
bad web-1 key can surface as `role=git-data-auth`. The `role=web` probe runs first, and both
known_hosts lines come from one writer, so read the first failing role. The `workspaces-luks-*`
workflows name no verdict: their log shows ssh's raw error output and the run fails.

**Escalation.**

- **Never re-enable trust-on-first-use** on any path, and never edit the pin to whatever the host
  currently presents without the re-capture procedure.
- If neither (a) nor (b) explains the mismatch, treat it as (c): open an incident (`/soleur:incident`)
  and follow [breach-notice triage](../../../legal/recommended-tools.md#breach-notice-triage). The
  72-hour clock starts there.
- If (a) is still unfixed **21 days** after it was found, escalate to the CLO: the daily at-rest
  encryption verdict behind a published Article 32 claim has been failing closed for that long, and
  the claim-decay window is 30 days.

In the app, the same mismatch surfaces as the Art. 17 erasure outcome `erasure_outcome=host_key_mismatch`
(paging through the existing `art17_erasure_incomplete` rule). Its first remedy is (b)'s redeploy half:
the app holds a stale or wrong pin. Re-run the redeploy (`gh run rerun <pin-redeploy-run-id> --failed`),
or dispatch `gh workflow run git-data-pin-redeploy.yml --ref main -f source_run_id=<apply-run-id>`.
If that run's gate exited 1 with `verdict=unidentified`, or printed `verdict=pin_published` or `verdict=pin_maybe_published`, dispatch
`gh workflow run git-data-pin-redeploy.yml --ref main` with no `source_run_id`.

### Store not empty (`store_not_empty`)

The store was assumed empty by construction (ADR-220 D4, #6976): the flag has never been on, so no
repository should exist. A non-empty store breaks that assumption. Since ADR-239 the dry run measures
the served LUKS store, so the entries are there; a deleted user's repository may remain on it. The
retained plaintext volume is covered by the boot's `plaintext_empty` count, not by this verdict.

1. Open an incident (`/soleur:incident`) and route it to the CLO for an Art. 33 assessment.
2. **Do not replace the host and do not wipe either volume.** The store's contents are the evidence,
   and the Art. 17 question is about them.
3. Pull the repository ids whose erasure may not have completed from Sentry: every event tagged
   `feature:account-delete op:git-data-bare-repo-erasure` carries the id in `extra.gitDataRepoId`.
   Read that field, not `userId`: `extra.userId` is pseudonymized by policy (ADR-029), so it returns
   `no-user-id` or a hash, never the repository name. For any window reaching back before PR #9096,
   the tag query cannot see Error-path reports (#8629): also run host-key step 5.1's message-text
   sweep. The issue's event listing returns each event in
   full, `extra` included (token and host as in `scripts/sentry-issue.sh`):

   ```bash
   SENTRY_ISSUE_RO_TOKEN=$(doppler secrets get SENTRY_ISSUE_RO_TOKEN -p soleur -c prd --plain)
   curl -fsS -H "Authorization: Bearer ${SENTRY_ISSUE_RO_TOKEN}" \
     'https://jikigai-eu.sentry.io/api/0/organizations/jikigai-eu/issues/?query=feature%3Aaccount-delete%20op%3Agit-data-bare-repo-erasure&statsPeriod=90d' \
     | jq -r '.[].id'
   # for each issue id:
   curl -fsS -H "Authorization: Bearer ${SENTRY_ISSUE_RO_TOKEN}" \
     "https://jikigai-eu.sentry.io/api/0/organizations/jikigai-eu/issues/<issue-id>/events/?full=true" \
     | jq -r '.[] | [.dateCreated, (.tags[]? | select(.key == "erasure_outcome") | .value) // "-", (.context.gitDataRepoId // .extra.gitDataRepoId // "no-repo-id")] | @tsv'
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

**git-data's SSH host key rotates on every replace (ADR-237).** The gated replace job re-mints
`tls_private_key.git_data_host_ssh` with the host and republishes `GIT_DATA_SSH_HOST_KEY`; the birth
job mints and publishes it the same way. When that apply run completes with the job and its apply
step both green, and the job was not carried over from an earlier attempt of the run (#8760; that
attempt's follower owns the redeploy), `git-data-pin-redeploy.yml` forces a web release, so the app
loads the new pin within about one release cycle. No step outside Terraform copies the pin, and no separate rotation
input exists. If the redeploy fails (it emails ops), re-run it with
`gh run rerun <pin-redeploy-run-id> --failed`; if its gate exited 1 with `verdict=unidentified`, or printed `verdict=pin_published` or `verdict=pin_maybe_published` (a red job whose apply published the pin, also emailed), dispatch
`gh workflow run git-data-pin-redeploy.yml --ref main` with no `source_run_id`. Until it succeeds, erasures page
with `erasure_outcome=host_key_mismatch` from the second rotation on, and with the store on,
replication pushes and fetches fail too.

web-1's host key does not rotate: it is a committed pin, changed only by the re-capture procedure below.

## Re-capturing web-1's host key

web-1 cannot be replaced (the replace gate refuses it until #6931) and ignores cloud-init changes, so
its host key is a committed pin: `apps/web-platform/infra/web-1-ssh-host-key.pub`, `#` header lines
(capture method, UTC date, `SHA256:` fingerprint) and exactly one `ecdsa-sha2-nistp256` key line.
ECDSA-P256 is required because Terraform's SSH client negotiates it (ADR-237). Re-capture only when
web-1's key has legitimately changed (a web-1 rebuild once #6931 lands) or the committed capture was
wrong (H4 cause (a)).

1. From a machine whose egress IP is in `ADMIN_IPS` (if it is not, type `/soleur:admin-ip-refresh` in Claude Code first),
   run `scripts/capture-web-1-host-key.sh <web-1 public IPv4>`. It scans web-1's public port 22
   directly, outside Cloudflare, prints the fingerprint, cross-checks it against your own known_hosts
   entry for that IP if one exists, and writes the pin file with its header. It refuses to run in CI,
   and it refuses when your known_hosts entry differs from the scanned key: investigate that (H4)
   before pinning anything.
2. Open a PR with the new file. The PR body names the capture vantage (the egress IP class, not a
   secret), the UTC date, the fingerprint in the file header, and the cross-check result. The file has
   a CODEOWNERS row, which is advisory only (ADR-237: code-owner review is not enforced on `main`), so
   the reviewer compares the fingerprint independently.
3. Before merge, dispatch `workspaces-luks-verify.yml --ref <branch>`: a strict pass through Cloudflare
   is the second, independent observation of the new key. It must end `success`.
4. After merge, the merge-triggered apply re-runs `terraform_data.web_1_host_key_probe` (its trigger
   hashes the pin) and must end `success`.

Never source a pin from `ssh-keyscan` in a CI path, and never loosen host-key checking to get a run
through.

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
   `git log -1 --diff-filter=AM --format=%H -- apps/web-platform/infra/git-data-rung2-boot-evidence.env`
   (`--diff-filter=AM` skips a commit that deleted the file, as PR #8511 did), or any
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
- a dry run refusing `verdict=store_not_on_mapper`, `verdict=cutover_frozen`, or
  `verdict=store_unverified reason=marker_mismatch` with no matching boot FATAL;
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
  `feature:git-data-authz cross_tenant:true` = 0 (a `level:warning` tag). Since #8572,
  `feature:worktree_lease level:error` also counts push **pin faults** (`pin_fault:*`), which were
  invisible to it before: the Error-path push report reached Sentry as `feature=pino-mirror`. The `soleur-git-data-prd`
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
- ADR-237 (SSH host keys are pinned); web-1 pin: `apps/web-platform/infra/web-1-ssh-host-key.pub`; capture: `scripts/capture-web-1-host-key.sh`; known_hosts writer: `.github/actions/cf-tunnel-ssh-bridge/write-known-hosts.sh`; redeploy: `.github/workflows/git-data-pin-redeploy.yml` (runs `.github/actions/dispatch-web-redeploy/track.sh`)
- Soak script: `scripts/followthroughs/phase3-ga-soak-5274.sh`
- Convention: `knowledge-base/engineering/operations/runbooks/followthrough-convention.md`
