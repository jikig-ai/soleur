# Runbook — Moved-block CI-apply wedge & multi-host GA cutover (#5887 / #5877)

> **Default to the zero-downtime path.** A serving-host reboot is NOT the baseline —
> the wedge clears with a no-op `state mv`, and the GA host change is blue-green.
> Downtime is acceptable only with explicit justification + a bounded window + operator
> sign-off (learning `2026-07-02-zero-downtime-first-moved-block-statemv-and-blue-green-cutover`).

## ✅ Resolved (2026-07-03) — how the CI wedge was actually cleared

The CI wedge is **cleared**; both `apply-web-platform-infra.yml` and
`apply-deploy-pipeline-fix.yml` are green on `main`. History, so a future reader
does not re-run the wrong path:

- By triage time the four `moved {}` blocks were **already consumed** in state (a
  prior `terraform state mv` — Scope A below). The remaining red was **not** the
  moved error but the `reboot_updates` destroy-guard (#5911) halting on web-1's
  pending `placement_group_id` attach (the reboot).
- It was cleared via a **third, even simpler zero-reboot path** (neither a state
  mv nor the Scope-B cutover): `lifecycle { ignore_changes = [placement_group_id] }`
  on `hcloud_server.web` (**PR #5950**). That drops web-1's pending placement change
  out of **every** plan (verified live: `31 add, 2 change` → `31 add, 1 change,
  0 destroy`), so the guard passes and **both** targeted CI applies self-heal green —
  **zero reboot, normal PR merge, no maintenance window.** A static guard in
  `plugins/soleur/test/terraform-target-parity.test.ts` fails if that entry is dropped.
- Clearing the wedge then **exposed two latent deploy-fix defects** that had never
  run green behind it (see learning `2026-07-03-chain-of-latent-defects-clearing-a-
  wedge-exposes-a-cascade`): the seccomp redeploy sent `tag=latest` → `tag_malformed`
  (fixed by **#5957**, `/health` semver resolution), then `loaded != committed`
  (fixed by **#5963**, live-profile read). Both pipelines green on `b62526b80`.
- **Design captured:** ADR-068 §Amendment (2026-07-03) + ADR-079 §Amendment.

**Everything below is still the reference for the DEFERRED multi-host GA cutover**
(Scope B) — which is what actually takes the web-1 reboot on a drained host and flips
git-data. Its **first diff removes the `ignore_changes = [placement_group_id]` entry**
so the placement reboot is taken deliberately, blue-green. The `terraform state mv`
(Scope A) is retained as historical context; the moves are already consumed, so it is
not re-run.

## When to run this

`apply-web-platform-infra.yml` **and** `apply-deploy-pipeline-fix.yml` are red with:

```
Error: Moved resource instances excluded by targeting
  -target="hcloud_server.web"
  -target="hcloud_volume.workspaces"
  -target="hcloud_volume_attachment.workspaces"
  -target="hcloud_server_network.web"
```

Root cause (ADR-068 §Amendment 2026-07-02): PR #5877 added four `moved {}` blocks to
`apps/web-platform/infra/placement-group.tf` for the singleton→`for_each` multi-host
migration but shipped **without** consuming them. Terraform refuses any `-target=`-scoped
plan while pending `moved` sources aren't in the target set, so every per-PR targeted CI
apply aborts. **The `moved` blocks are pure re-addressing (`0 to destroy`) — they reboot
nothing by themselves.** The reboot hazard is a *separate* pending change: web-1 gaining
`placement_group_id` (Hetzner attaches a placement group only to a **stopped** server).

## Two scopes — pick deliberately

| Scope | Goal | Path | User impact |
|-------|------|------|-------------|
| **A** | Clear only the CI wedge (kill the plan-time error) | `terraform state mv` ×4 | **Zero** — no reboot, no new host, reversible |
| **B** | Pipelines fully green / multi-host GA go-live | Blue-green cluster cutover | **Zero if blue-green**; brief outage if naive apply |

> **Historical note (superseded by what shipped — see §Resolved above).** This table
> predates the fix. In practice the wedge was cleared by a **third path**:
> `ignore_changes = [placement_group_id]` on `hcloud_server.web` (#5950) — which turned
> **both** pipelines green with zero reboot and **without** Scope B's cluster changes,
> because the only remaining red-maker (once the moves were consumed) was the
> `reboot_updates` guard, not an un-applied cluster. Scope A (`state mv`) alone would not
> have cleared the reboot-guard red; the `ignore_changes` entry is what does. Scope B
> below remains the DEFERRED GA go-live (it removes that `ignore_changes` entry as its
> first diff and takes the reboot on a drained host).

## What NOT to do (forbidden / hazardous)

- ❌ **Add the four resources to the per-PR `-target=` allow-list.** `hcloud_server.web`
  carries `placement_group_id` + `for_each`; an unattended apply forces a power-off reboot
  of the running prod host. Forbidden by ADR-068 §Amendment; the
  `terraform-target-parity.test.ts` `MOVED_OPERATOR_CONSUMED` guard (PR #5908) fails
  plan-review if a future migration tries this.
- ❌ **`[ack-destroy]` through the per-PR apply.** `hcloud_server.web` is transitively in
  the saved plan (dependency of `hcloud_firewall_attachment.web`), so ack-ing would
  *execute* the reboot on the unattended path — the exact hazard the `reboot_updates`
  destroy-guard (PR #5911) prevents. `[ack-destroy]` is an emergency override only.
- ❌ **Naive full `terraform apply` during serving hours.** It reboots web-1 while it is
  taking traffic → ~1–2 min outage. Use the blue-green sequence below instead.

---

## Scope A — clear the CI wedge with `terraform state mv` (ZERO downtime)

The wedge is caused *only* by pending `moved` blocks. Consuming them as a state op has
zero infra effect.

1. **Back up state first** (reversibility):
   ```bash
   terraform state pull > /tmp/tfstate.pre-movedmv.$(date +%s).json   # keep off-host
   ```
2. **Re-address the four resources** (state-only; no plan, no apply, no reboot):
   ```bash
   terraform state mv 'hcloud_server.web'             'hcloud_server.web["web-1"]'
   terraform state mv 'hcloud_volume.workspaces'      'hcloud_volume.workspaces["web-1"]'
   terraform state mv 'hcloud_volume_attachment.workspaces' 'hcloud_volume_attachment.workspaces["web-1"]'
   terraform state mv 'hcloud_server_network.web'     'hcloud_server_network.web["web-1"]'
   ```
3. **Confirm the moved error is gone:** `terraform plan` no longer emits
   `Moved resource instances excluded by targeting`.

> **Layer-2 note (verified):** `hcloud_firewall_attachment.web` is in the CI `-target`
> allow-list and its `server_ids = [for h in hcloud_server.web : h.id]` depends on the
> **whole** `for_each` map. After the `state mv`, a *targeted* CI apply therefore cascades
> into web-1's placement-attach (needs the host stopped → `server_not_stopped`) and web-2's
> create. So Scope A removes the plan-time error but the pipelines go green only once
> Scope B's cluster changes actually apply. **Verify the real pipeline — do not assume
> "error cleared = green."**

---

## Scope B — multi-host GA cutover, blue-green (ZERO downtime when sequenced)

`var.web_hosts` defaults to **both** `web-1` (existing) and `web-2` (new). A fresh
`for_each` host is **born into the placement group at creation — no reboot**. Only the
pre-existing web-1 needs a power-off to join. So reboot a **drained, non-serving** host.

### Pre-flight
1. Confirm a maintenance window is booked (safety margin, even for the zero-downtime path).
2. Prerequisite bug is cleared: web-2 fresh-host `user_data` 32 KB cap (**#5921**) — fixed
   by **#5922** (merged 2026-07-03). Re-confirm a fresh `hcloud_server.web["web-2"]` plans
   cleanly.
3. Full (`-target`-free) `terraform plan`; verify **`0 to destroy`** on the moved
   resources and that `hcloud_volume.workspaces["web-1"]` shows **no** destroy/replace
   (data-bearing volume — any replace is a STOP).
4. Apply runs **Inngest-dispatches-GHA off-host** with cloud-admin creds — never
   in-process terraform on the app host (learning `2026-06-02`,
   `hr-fresh-host-provisioning-reachable-from-terraform-apply`).

### Blue-green sequence (reboot hits a non-serving host)
5. **Provision web-2 in-group** — apply the create for `hcloud_server.web["web-2"]` +
   its volume/attachment/network. Born into `web_spread`, no reboot.
6. **Bring web-2 into rotation** — deploy the app to web-2, health-check, add it to the
   ingress (Cloudflare LB / proxied A records per `dns.tf` + `firewall.tf` D1 rewire).
7. **Drain web-1** — drop its router/connector weight so it stops taking new traffic;
   let in-flight requests finish.
8. **Attach web-1 to the placement group *while drained*** — this is the power-off reboot,
   now against a non-serving host. No user impact.
9. **Restore web-1** to rotation once healthy.
10. **(If flipping the git-data store too)** follow the hardened cutover — fresh LUKS
    volume, write-freeze two-pass rsync, set-identity verify (`git for-each-ref` diff +
    `git rev-list --all | sort | sha256sum`), coordinated flag flip — per plan §3.D +
    `git-data-luks-cutover-5274.md`. Not strictly required to clear the wedge; ADR-068
    sequences it with GA — decide before the window.

### Verify (pull data yourself — no dashboard eyeballing)
11. Both pipelines' next `main` run must be **success**.
12. Follow-through probe:
    ```bash
    GH_TOKEN=$(gh auth token) bash scripts/followthroughs/moved-block-wedge-5887.sh
    # PASS (exit 0) = both apply pipelines green on main → wedge cleared
    ```
13. Scheduled sweeper auto-closes **#5887** on first PASS (earliest
    `2026-07-04T20:15:57Z`). No manual close.

### Rollback
- **Scope A:** `terraform state push` the backed-up pre-`mv` state.
- **Scope B:** flag-off + re-drain (plan §3.D-6). Pushed refs also live on GitHub `origin`
  (rehydration), so only post-flip git-data writes are at risk — state this dependency
  before the window. The web-1 `for_each` addressing is the new steady state and is not
  reverted.

## Recurrence prevention (already shipped — no action)
- **#5908** — `MOVED_OPERATOR_CONSUMED` parity guard + ADR-068 amendment + learning.
- **#5911** — destroy-guard `reboot_updates` counter (reboot-forcing in-place
  `hcloud_server.*` update no longer blind on the unattended per-PR path).
- **#5922** — web-2 `user_data` externalized under the 32 KB cap (unblocks blue-green).
- **#5950** — `ignore_changes = [placement_group_id]` on `hcloud_server.web` (the actual
  wedge-clear) + a `terraform-target-parity.test.ts` guard that fails if it is dropped.
- **#5957 / #5963** — the two deploy-fix defects the unwedge exposed (seccomp redeploy
  `tag_malformed`, then `loaded != committed`), now fixed; both pipelines green.
