# git-data LUKS cutover runbook — #5274 Phase 3 / Sub-PR 3.D / ADR-068

Operator runbook for migrating the live per-workspace bare repos onto a fresh
LUKS-at-rest volume and flipping the `GIT_DATA_STORE_ENABLED` GA flag across both
web hosts. This is the additive **rsync-then-flag-flip** cutover (ADR-068 §1), not
an authority flip — `origin`→GitHub is retained throughout as the rehydration
backstop.

**No SSH in this runbook.** All verification is read from the observability layer
(Sentry + Better Stack) per `hr-no-ssh-fallback-in-runbooks`. The cutover
*mechanism* uses SSH transport (over the CF Tunnel bridge, off the app host), but
you never SSH a host to *check* whether it worked — you read Sentry/Better Stack.

## Preconditions

- Sub-PRs 3.A–3.C merged; both web hosts (`web-1`, `web-2`) deployed with the
  Phase-3 container (AC5). Confirm from the **deploy pipeline run**, not by SSH.
- ADR-068 status is `adopting`. `GIT_DATA_STORE_ENABLED` is currently **OFF**
  (unset / not `"true"`) in Doppler `prd`.
- `SENTRY_AUTH_TOKEN` and the git-data cutover secrets (`DOPPLER_TOKEN`,
  `DOPPLER_TOKEN_WRITE`) are configured as GitHub secrets.

## Sequence

1. **Merge** the 3.D PR to `main`.
2. **CI deploys** the container to BOTH hosts (AC5) — verify the deploy workflow
   run is green.
3. **Maintenance-window `terraform apply`** (`apply-web-platform-infra.yml`):
   provisions + **attaches** the fresh **LUKS** git-data block volume. The
   `placement_group` attach on the running host forces a power-off → **this reboots
   `web-1`**, hence the maintenance window. Confirm `0 to destroy` on the plan.
   NOTE: terraform only *attaches* the volume — cloud-init runs **only on first
   boot**, so on the already-running git-data host it does **not** `luksFormat`/
   `luksOpen`/mount the new volume. The cutover script's `prepare_luks_target` step
   does that idempotent unlock+mount at `/mnt/git-data-luks` (key fetched host-side
   via `doppler run`, piped on stdin — never argv). Do **not** expect
   `/mnt/git-data-luks` to exist before the cutover runs.
4. **Dry-run the cutover** — dispatch `git-data-cutover.yml` with
   `confirm=CUTOVER-GIT-DATA`, `dry_run=true`. This runs `prepare_luks_target` +
   preconditions + pass-1 rsync + the **set-identity verify** with NO freeze, NO
   flip, NO re-point, NO wipe. Confirm the set-identity verify reports `OK` for
   every repo.
5. **Real cutover** — dispatch `git-data-cutover.yml` with
   `confirm=CUTOVER-GIT-DATA`, `dry_run=false`, `confirm_wipe=false`. The script:
   - `prepare_luks_target`: idempotent `luksOpen` + mount at `/mnt/git-data-luks`;
   - pass-1 bulk rsync (writers live);
   - **write-freeze**: drain **both** web hosts (the authoritative freeze — the
     writers are the web hosts' per-turn `replicateToGitData`) + drop the freeze
     sentinel (`git-data-pre-receive.sh` now denies receive-pack while it exists,
     so a straggler push is rejected loud, not lost);
   - pass-2 **delta rsync under the drain** (a genuinely quiesced source) →
     **set-identity verify** (`git for-each-ref` diff empty **AND** `git rev-list
     --all | sort | sha256sum` equal, per repo) — the ONLY verify that gates the
     flip, and it runs post-drain so it never races a live writer;
   - **`repoint_luks_mount`**: umount the LUKS staging + old plaintext mounts, mount
     `/dev/mapper/git-data` **at `/mnt/git-data`** and rewrite `/etc/fstab`, so every
     hardcoded wrapper/symlink/`hooksPath` becomes LUKS-backed with zero path
     changes (the GA flag alone does NOT change host mount topology);
   - **coordinated flip**: write `GIT_DATA_STORE_ENABLED=true` once → reload both
     (drained) containers → release the freeze / un-drain;
   - **canary**: assert a fresh write under `/mnt/git-data` is backed by
     `/dev/mapper/git-data` — this gates the DL-2 wipe.
   On any mid-flip failure the script auto-rolls-back (flag off) and always releases
   the freeze (un-drains). A stale-mount abort leaves the wipe gated.
6. **Verify set-identity + health from observability** (below).
7. **Enroll the soak follow-through** (below) — this gates GA close.
8. **Old-volume decommission (DL-2)** — only AFTER the soak confirms health AND the
   canary passed, re-dispatch with `confirm_wipe=true`. The old plaintext volume is
   already unmounted by the re-point; secure-wipe + detach/destroy the old
   `hcloud_volume` via terraform so the decommissioned disk carries no plaintext.
   Do **not** wipe the **FRESH** volume — it is now live. After a *rollback*, do not
   wipe **either** volume until git-data-only post-flip writes are reconciled (see
   Rollback).

## Verification (observability layer — NO SSH)

Read the verdict from:

- **Sentry** (these classes are the `feature` tag — NOT `op`, which is the sub-op):
  - `feature:control_plane_route level:error` failures — expect **0** after the flip.
    Zero events on a changed routing path can ALSO mean the wrong layer shipped
    (learning 2026-06-30) — confirm you see healthy `feature:control_plane_route`
    placement events first, then zero *failures*.
  - `feature:worktree_lease level:error` reject events — expect **0** (no fence
    false-rejects).
  - `feature:git-data-authz cross_tenant:true` — expect **0** (no cross-tenant
    denials). NB: this is emitted at `level:warning` (not error) and `member:false`
    lives in non-searchable `extra` — query the `cross_tenant:true` tag, not `member`.
- **Better Stack**: the `soleur-git-data-prd` heartbeat (GIT_DATA_HEARTBEAT_URL)
  is GREEN — the git-data host is reachable over the private net post-cutover.

If any is unhealthy, run **Rollback**.

## Rollback

Dispatch `git-data-cutover.yml` with `confirm=CUTOVER-GIT-DATA`, `rollback=true`
(or, if the run is still in progress, the script's EXIT trap auto-rolls-back a
mid-flip failure). Rollback sets `GIT_DATA_STORE_ENABLED=false` in Doppler `prd`,
reloads both containers, and releases any held freeze (un-drains both hosts).

**Backstop — do NOT assume GitHub `origin` holds everything (it does not).**
`replicateToGitData` force-pushes **all** refs to git-data, whereas the app's
`syncPush` only auto-commits `knowledge-base/**` and reroutes protected pushes to a
PR branch — so **`origin` is a strict SUBSET of git-data**. On rollback the flag is
OFF, so `replicateToGitData` no-ops and the app reverts to its local-clone +
origin baseline. The real backstops for any **git-data-only** post-flip writes are
(a) each web host's **local worktree clone** and (b) the **FRESH LUKS volume**,
which physically retains every post-flip write.

**WARNING:** after a rollback, do **not** run the DL-2 wipe of the FRESH LUKS
volume until those git-data-only post-flip writes are reconciled — `origin` does
not hold them, so wiping FRESH would permanently lose them.

## Soak follow-through (gates GA close)

After cutover, file a `follow-through` tracker issue that gates GA close:
**≥7 days, zero fence false-rejects, zero cross-tenant denials, zero
control_plane_route failures → ADR-068 `accepted` / #5274 Phase-3 milestone
closes.**

1. Pin `START=` in `scripts/followthroughs/phase3-ga-soak-5274.sh` to the UTC
   timestamp **just after** the flip (replace the `<POST_CUTOVER_UTC>`
   placeholder), commit it.
2. File the tracker issue with the `follow-through` label and this directive in
   the body (set `earliest=` to cutover-UTC + 7 days):

   ```html
   <!-- soleur:followthrough
     script=scripts/followthroughs/phase3-ga-soak-5274.sh
     earliest=<CUTOVER_UTC_PLUS_7D>
     secrets=SENTRY_AUTH_TOKEN
   -->
   ```

   `SENTRY_AUTH_TOKEN` is already wired in
   `.github/workflows/scheduled-followthrough-sweeper.yml`. The sweeper closes the
   issue the day the soak passes (exit 0); until then it comments and leaves it
   open. When it closes, flip ADR-068 `adopting`→`accepted` and close the Phase-3
   milestone.

## References

- Cutover body: `apps/web-platform/infra/git-data-cutover.sh`
- Dispatch workflow: `.github/workflows/git-data-cutover.yml`
- Soak script: `scripts/followthroughs/phase3-ga-soak-5274.sh`
- Convention: `knowledge-base/engineering/operations/runbooks/followthrough-convention.md`
- ADR-068: `knowledge-base/engineering/architecture/decisions/ADR-068-multi-host-workspaces-shared-git-data-lease-coordinator.md`
