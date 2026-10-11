# Runbook — T2 collapse: the LUKS singleton becomes `hcloud_volume.workspaces["web-1"]` (#9357)

**Status:** readiness document, 2026-10-02. **Nothing here has been executed.** The HCL change and the single-use workflow that
performs the move are authored in the live operation's own PR, not in the PR that carries this page.
**Rehearsal:** `apps/web-platform/infra/workspaces-luks-t2-rehearsal.test.sh` replays the exact command sequence below against a
scratch Terraform root built from the built-in `terraform_data` type. It is a **state-address rehearsal**; it is not evidence about
hcloud provider behaviour (no provider is loaded, and no volume, attachment or server exists in it).

## What T2 is, and why it is a state move

Today the live LUKS store is two singleton addresses, `hcloud_volume.workspaces_luks` and
`hcloud_volume_attachment.workspaces_luks`, hardwired to web-1. T2 dissolves them into the keyed family that every other web host
already uses, `hcloud_volume.workspaces["web-1"]` and `hcloud_volume_attachment.workspaces["web-1"]`. The physical volume does not
change; only its Terraform address does. That is a **state-only re-address** (`terraform state mv`): no reboot, no host change, no
provider call.

Why not a `moved` block: a `moved` block on this root makes every `-target`ed plan fail (the ADR-119 2026-09-28 measurement, re-proved by
case (c) of the rehearsal), and every apply of this root is `-target`ed. A `moved` block must never be added here.

**The ordering hazard, which is the reason this page and the rehearsal exist.** The HCL half and the state half cannot merge in either order:

- State moved first, old HCL still merged: the plan destroys the keyed address (the config does not declare it yet).
- HCL merged first, state not moved: the plan destroys the singleton, which holds the **sole copy** of every user workspace.

So the live operation pauses push-apply, moves state, then merges the HCL (precedent: `workspaces-plaintext-forget.yml`).

## Preconditions (all must hold; each is checked by the live workflow, never assumed)

1. **PR #9348 is merged**: `gh pr view 9348 --json state --jq .state` reads `MERGED`. #9348's forget flow removes the retired plaintext web-1
   addresses (`hcloud_volume.workspaces["web-1"]`, `hcloud_volume_attachment.workspaces["web-1"]`) from state. Until it has, those two
   slots are **occupied** and the first move below collides with an existing destination (the rehearsal proves the collision, case
   (e)). The recipe starts from the post-#9348 state.
2. **A web-1 de-pet rebuild issue exists and is scheduled.** T2 removes the by-id pin hazard only for the keyed topology; the rebuild of
   web-1 itself is tracked separately, and #9357 is blocked by it.
3. **Push-apply is paused and idle**: both `apply-web-platform-infra.yml` and `apply-deploy-pipeline-fix.yml` read `disabled_manually`
   with no queued or running run, checked the way `assert_apply_paused_idle` did in the single-use `workspaces-plaintext-forget.yml` (deleted by #9348; read it with `git show 59abf6a76c:.github/workflows/workspaces-plaintext-forget.yml`), or the way `pause_real` does in `scripts/web2-rebirth.sh`.
4. **Physical-id pins**: the state instance at `hcloud_volume.workspaces_luks` carries the pinned LUKS volume id, selected by exact `.type`
   and `.name` (never an address prefix: `workspaces_luks` shares the `hcloud_volume.workspaces` prefix). The pinned constants live in the
   live workflow's own `env`, as in `apply-web-platform-infra.yml`.
5. **The two keyed slots are empty**: `terraform state list` shows neither `hcloud_volume.workspaces["web-1"]` nor
   `hcloud_volume_attachment.workspaces["web-1"]`.
6. **Re-read this page after #9348 merges.** #9348 edits the same surfaces (`workspaces-luks.tf`, the encryption-posture ledger row,
   comments); the `-target` list additions and the commands below must be re-checked against what it landed.

State holds `random_password.workspaces_luks`. **State is never written to a file, printed or uploaded**: `terraform state pull` is only
ever piped straight into one field-selecting `jq` program that emits serial, lineage and ids.

## State-move sequence (forward)

Executed in this order, inside the single-use workflow, with push-apply paused:

```bash
terraform state mv 'hcloud_volume.workspaces_luks' 'hcloud_volume.workspaces["web-1"]'
terraform state mv 'hcloud_volume_attachment.workspaces_luks' 'hcloud_volume_attachment.workspaces["web-1"]'
```

The volume moves first and the attachment second; moving only one of the two leaves the other singleton in state with no declaration
behind it, and the plan destroys it (rehearsal case (d)).

## Post-move expectations

- `terraform state list` holds `hcloud_volume.workspaces["web-1"]` and `hcloud_volume_attachment.workspaces["web-1"]` and neither
  `workspaces_luks` address; every other line is unchanged.
- The state **serial advanced** and the **lineage is unchanged** (a state-address operation never forks lineage). An exact serial delta is
  not asserted: Terraform derives it and counts differently across versions.
- The instance ids of the moved resources equal the pins read before the move.
- With the T2 HCL (singleton dissolved into the keyed family), `terraform plan -detailed-exitcode` exits `0`: no change.
- `random_password.workspaces_luks` and its Doppler secrets show no action (a rotation here strands the at-rest header).

## Rollback (reverse sequence)

Valid only while the HCL half has **not** merged, or after reverting it. The same two moves, reversed, in the reverse order:

```bash
terraform state mv 'hcloud_volume_attachment.workspaces["web-1"]' 'hcloud_volume_attachment.workspaces_luks'
terraform state mv 'hcloud_volume.workspaces["web-1"]' 'hcloud_volume.workspaces_luks'
```

Never write state to a file to take a "backup": it holds the passphrase. Re-enable push-apply only after an untargeted-shape plan against
the restored HCL reads clean.

## What this page does not do

It authors no HCL and no workflow. The T2 HCL and the single-use state-move workflow are written in the live operation's own PR, which is
gated by #9348 merged, a scheduled de-pet rebuild, the push-apply pause, and its own approval. Removing the web-1 refusal in
`tests/scripts/lib/web-host-replace-gate.sh` is a separate change (#9356) that needs rehearsal evidence and this topology.
