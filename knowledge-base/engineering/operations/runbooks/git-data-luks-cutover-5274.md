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
   provisions the fresh **LUKS** git-data volume, `luksOpen`s + mounts it at its
   target, and re-points the git-data mount. The `placement_group` attach on the
   running host forces a power-off → **this reboots `web-1`**, hence the
   maintenance window. Confirm `0 to destroy` on the plan.
4. **Dry-run the cutover** — dispatch `git-data-cutover.yml` with
   `confirm=CUTOVER-GIT-DATA`, `dry_run=true`. This runs preconditions + both
   rsync passes' shape + the **set-identity verify** with NO freeze, NO flip, NO
   wipe. Confirm the set-identity verify reports `OK` for every repo.
5. **Real cutover** — dispatch `git-data-cutover.yml` with
   `confirm=CUTOVER-GIT-DATA`, `dry_run=false`, `confirm_wipe=false`. The script:
   - pass-1 bulk rsync (writers live) → pass-2 delta rsync under a **write-freeze**
     (freeze sentinel the pre-receive fence honours; receive-pack fail-closed-rejects
     while held);
   - **set-identity verify** (`git for-each-ref` diff empty **AND**
     `git rev-list --all | sort | sha256sum` equal on old and fresh, per repo) —
     aborts with the freeze left releasable on any mismatch;
   - **coordinated cross-host flip**: drain both hosts together → write
     `GIT_DATA_STORE_ENABLED=true` once → reload both containers → un-drain (no
     turn straddles the non-atomic Doppler propagation);
   - release the freeze.
6. **Verify set-identity + health from observability** (below).
7. **Enroll the soak follow-through** (below) — this gates GA close.
8. **Old-volume wipe (DL-2)** — only AFTER the soak confirms health, re-dispatch
   with `confirm_wipe=true` (or run the wipe step), then detach/destroy the old
   `hcloud_volume` via terraform so the decommissioned disk carries no plaintext.

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

Flag off + re-drain (the cutover script's rollback path, or dispatch a flag-off):
set `GIT_DATA_STORE_ENABLED=false` in Doppler `prd` and reload both containers.

**GitHub-rehydration dependency (state explicitly):** post-flip git-data writes
made *after* the flip are LOST by rollback. This is acceptable ONLY because every
ref the app pushes to git-data is ALSO pushed to GitHub `origin`
(`ensure-workspace-repo.ts` retains `origin`→GitHub, ADR-068 §1). On rollback the
next turn re-clones/re-pushes from origin, so no user work is permanently lost. If
origin retention were ever removed, this rollback would become lossy.

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
