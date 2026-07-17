# ADR-118 seed — LUKS at rest for the live `/workspaces` volume

> **This is a seed, not the ADR.** Phase 2's first task copies it to
> `knowledge-base/engineering/architecture/decisions/ADR-118-luks-at-rest-for-the-live-workspaces-volume.md`
> with `status: adopting`, re-verifying the ordinal against `origin/main` first
> (ADR-117 is the current max; `/ship`'s ADR-Ordinal Collision Gate is authoritative).
>
> It lives here because the planning phase's write boundary is
> `knowledge-base/project/{plans,specs}/`, and `wg-architecture-decision-is-a-plan-deliverable`
> requires the decision to be **produced now**, not deferred. Seeding it keeps the ADR a
> deliverable in hand rather than a promise.

**Ruled by:** `soleur:engineering:cto`, 2026-07-17, per issue #6588's explicit routing mandate
(*"Do not start with terraform… The design question belongs to `soleur:engineering:cto`"*).

---

## Status

`adopting` → flips to `accepted` on Phase 5 soak-pass (7 days).

## Context

`hcloud_volume.workspaces` (`server.tf:1241`) holds every user's checked-out repository as plain
ext4. Three published legal documents assert it is LUKS-encrypted. The encryption must be made true.

Five facts constrain the design. Each was verified against the repo, not inherited from the issue:

1. **LUKS at Hetzner is guest-side.** `git-data-luks.tf:11-14`: *"encryption-at-rest is GUEST-SIDE
   LUKS, NOT an hcloud_volume attribute. There is no hcloud 'encrypted' flag."* Its own LUKS volume
   keeps `format = "ext4"`. **The issue's "`format` is ForceNew ⇒ apply destroys the volume" hazard
   is a red herring — `format` never changes.**
2. **The real data-loss mechanism is the `isLuks` guard.** `cloud-init-git-data.yml:159`:
   `if ! cryptsetup isLuks "$DEV"; then luksFormat`. On a **populated plaintext** device `isLuks`
   is false ⇒ `luksFormat` ⇒ **wipes live user code**. The guard is safe only because git-data's
   volume is born fresh.
3. **The data is sole-copy.** `refs/checkpoints/<convId>` (`inflight-checkpoint.ts`) is pushed by no
   refspec anywhere; `session-sync.ts` autocommits only `/^knowledge-base\//`; and
   `provisionWorkspace` — the **signup/auth-callback** path (`app/(auth)/callback/route.ts:380`) —
   does `git init` with no `remote add`. ADR-068 §1's *"GitHub remains the durable rehydration
   source"* is walked back by its own §(d): *"a fresh GitHub clone can be strictly behind the user's
   latest tip."*
4. **The host cannot be replaced.** `cx33` is `available=false` in hel1-dc2, fsn1-dc14 and nbg1-dc3
   (live 2026-07-17; corroborated at `tests/scripts/test-stock-preflight-gate.sh:11-13`: *"on
   2026-07-15 cx33 went from 'orderable in hel1' to orderable in ZERO datacenters within ~3h"*).
   `-replace` destroys before it creates ⇒ the destroy succeeds, the create fails
   `resource_unavailable`, and the fleet strands **unrebuildable**.
5. **A cloud-init edit is a no-op on the live hosts.** `server.tf:254-256`
   `ignore_changes = [user_data, ssh_keys, image, placement_group_id]`.

## Decision

**Encrypt the live `/workspaces` volume by attaching a fresh LUKS-formatted volume additively,
freezing writers by stopping the app container, two-pass rsync with filesystem-level verification,
repointing the mapper to `/mnt/data`, and retaining the plaintext volume under `prevent_destroy` as
the sole rollback backstop — never by replacing the host.**

Single-host (web-1 only). Sequenced after PR #6568. Bounded downtime ≤20 min (target ~10; ≤2h hard
abort). Adapt the *shape* of `git-data-cutover.sh`; do **not** build `soleur-drain.service`.

### (a) The freeze is a full container stop, not a drain

`soleur-drain.service` must not be built. A drain exists to shed traffic from one fleet member while
peers absorb it. **There is no LB and no peer** (`server.tf:186-187`); `app.soleur.ai` is a pinned
singleton. For a singleton, drain and stop are the same operation, and **stop is strictly stronger**.

The freeze: stop the app container (the sole writer — `cloud-init.yml:776` binds
`/mnt/data/workspaces:/workspaces`), plus halt `webhook.service` so a CI deploy cannot race the
cutover by restarting the container mid-rsync. Inngest functions execute inside that container, so
they stop with it and retry after; the Inngest host needs no action.

**The straggler-write assert is `fuser -vm /mnt/data` / `lsof +f -- /mnt/data` returning empty** —
not a sentinel file. A stopped container holds no mount; this is **verifiable rather than advisory**,
a better guarantee than git-data's pre-receive sentinel.

### (b) Rollback is the retained plaintext volume, and it is lossless only inside the freeze

No flag-flip analogue exists (`/workspaces` has no `GIT_DATA_STORE_ENABLED` equivalent) and GitHub is
not a backstop (fact 3). The plaintext volume stays attached-but-unmounted, `prevent_destroy = true`,
un-wiped through the soak. Inside the freeze, rollback is: unmount mapper, remount plaintext at
`/mnt/data`, restart container — seconds, byte-identical.

**After traffic resumes, rollback is no longer lossless** — new writes land on LUKS only. **Rollback
authority expires at canary-pass. This is a one-way door and must be stated in the runbook, not
implied.**

**Do not take a pre-cutover Hetzner snapshot as a backstop**: a retained plaintext snapshot
re-creates the exact exposure this ADR closes. (COO concurred independently: *"It was never the cost
that made snapshotting wrong."*) The additive design already yields a two-copy state; the old volume
**is** the backup, and unlike a snapshot it is a live, mountable device the cutover **rehearses**.

### (c) Bounded downtime is justified; budget ≤20 min

The #5887 norm permits downtime with explicit justification + a bounded window + sign-off.
Justification: the zero-downtime path requires a load balancer with no implementation and no ADR
(#6459), **and is impossible anyway** given fact 4 — against a population of one operator and zero
beta users. The bulk rsync runs **live** (no downtime); only delta + verify + repoint + restart +
canary sit inside the freeze, over a quiesced tree well under 20 GB.

### (d) web-2 is out of scope; this work waits for #6568

Sequencing after PR B is not merely collision-avoidance — it is what makes the AC affordable. Once
web-2 leaves `var.web_hosts`, `for_each` shrinks and `hcloud_volume.workspaces["web-2"]` is
destroyed. The AC *"LUKS-encrypt for every `var.web_hosts` member"* then means **web-1 only**.
Encrypting a volume scheduled for destruction is waste. Starting early also collides on `server.tf`
and `variables.tf`.

### (e) The fresh-host path gets LUKS via the baked bootstrap, not inline cloud-init

`WEB_GZIP_BUDGET = 21_900` with ~300 bytes headroom (`server.tf:157`: cloud-init.yml is *"effectively
comment-frozen"*) means an inline block blows the budget. The extraction precedent exists at
`cloud-init.yml:561`, which invokes `soleur-host-bootstrap.sh` from the image seed. LUKS goes there,
per ADR-080. On a fresh host the volume is born empty, so the `isLuks` guard is safe **in its
intended direction**.

### (f) The passphrase is Soleur-generated and its escrow is proven before the cutover

`random_password` → `doppler_secret` → read-only scoped `doppler_service_token`, mirroring
`git-data-luks.tf` exactly. No `TF_VAR`, no human-minted secret
(`hr-tf-variable-no-operator-mint-default`). `--key-file -` via stdin, never argv. Fail loud on an
empty key — **never an unencrypted fallback** (NFR-026).

**Amendment (CPO sign-off, 2026-07-17).** The CPO review surfaced a failure mode this ruling did not
originally address: **passphrase loss makes the volume unreadable forever — a terminal mode strictly
worse than the plaintext exposure being closed.** Escrow is therefore a **blocking pre-cutover gate**:
read the passphrase back from Doppler and prove it unlocks a throwaway volume before any cutover
step. An unproven key is not a key.

## Rationale

The decisive fact is **fact 3 + the absence of any backstop**. When the data has no second copy, the
only acceptable migration is one where **the source is never written to and remains mountable at
every instant**. Option 2 is the only candidate with that property. That same property is what
rejects the in-place path, and what makes ~€1.14/month for a second 20 GB volume the cheapest
insurance in the plan.

The second driver: the near-exact precedent is already written and reviewed, and its #5274 review
already paid for the **data-stranding trap** — an additive mount at a new path while consumers
hardcode the old path means every post-flip write lands on plaintext. `repoint_luks_mount`
(`git-data-cutover.sh:288`) exists because of that. For `/workspaces` the trap is **sharper**:
`cloud-init.yml:776` hardcodes `/mnt/data/workspaces` into the container's bind mount, so the mapper
must land at `/mnt/data` itself, not a sibling path.

## Alternatives Considered

| # | Alternative | Verdict |
|---|---|---|
| 1 | **Blue-green host** (the issue's preferred option) | **Rejected — currently impossible.** Priced honestly it is the most expensive option and the *least* safe. Requires: an LB that does not exist; unwinding `web["web-1"]` pinned 23× across 5 files; an ADR for #6459 never written; and a `-replace` that per `hr-prod-host-config-change-immutable-redeploy` **destroys before it creates with no rollback** — on the exact resource that wedged the fleet on `resource_unavailable` on 2026-07-13, and whose server type is now unorderable in every EU DC. It spends weeks and takes fleet-stranding risk to save one operator ten minutes. The issue's claim that this *"aligns with the zero-downtime precedent in #5887"* **inverts** that precedent: #5887's own norm demands justification for downtime, and here the justification is available while the zero-downtime machinery is not. |
| 2 | **Additive volume + freeze + rsync + repoint** | **ADOPTED.** See Decision. |
| 3 | **Accept + re-scope the claim** | **Rejected as primary; ADOPTED for the three unachievable clauses.** Retraction is correct only when encryption is unaffordable; option 2 is ~4-6 days, so the decision to make the claim true is sound. **But the issue's own out-of-scope list is not optional**: the per-workspace git-data host (cax11 orderable in 0 of 3 EU DCs, #6570), TLS-in-transit between hosts (no cross-host traffic exists; #6538 destroys web-2), and cross-host membership re-verification (no LB) can never be made true by this work and **must be retracted or past-tensed**. Encrypting the volume while leaving those standing simply **relocates** the false claim. *(CLO + CPO subsequently ruled this retraction should also be **decoupled** and shipped ahead of the migration — see the plan's "legal track".)* |
| 4a | **In-place `cryptsetup reencrypt --encrypt --reduce-device-size`** | **Rejected — the strongest alternative, and the one the issue omitted.** Genuinely simpler: same volume, same name, same terraform address, no second volume, no state surgery, no naming divergence, comparable downtime. Rejected on one ground: **it operates on the sole copy.** LUKS2's reencrypt journal (`--resilience checksum`) makes it crash-*resumable*, not crash-*proof*; a `resize2fs` shrink plus header insertion on the only extant copy of un-pushed user code converts every recoverable failure mode into an unrecoverable one. Adding a snapshot to make it recoverable means paying option 2's complexity to buy back what option 2 gives free — while retaining a plaintext snapshot that re-opens the exposure. **Option 2 dominates.** |
| 4b | **fscrypt / ext4 native encryption, or gocryptfs** | **Rejected.** Both encrypt file contents but leak metadata, and neither matches the published wording (*"LUKS"*) — and the published claim is the artifact being made true. Encrypting with a different mechanism than the one named leaves the policy inaccurate in a subtler way. |
| 5 | **Build `soleur-drain.service`** | **Rejected.** See (a). Its absence is not a gap to fill; it is **evidence that the git-data cutover script was written against a fleet shape that does not exist**. |
| 6 | **Pre-cutover Hetzner snapshot as the backstop** | **Rejected.** See (b). CTO and COO converged independently. |

## Consequences

- **`git-data-cutover.sh` cannot run today** and must not be presented as a reusable asset. Its
  `acquire_freeze`/`release_freeze` (`:196`/`:212`) invoke `soleur-drain.service`, and its reload step
  invokes `soleur-web.service`; **neither exists** (`grep -rln` finds each in that file only — the app
  is a bare `docker run -d --name soleur-web-platform`). It is a **shape** to copy into a new
  `workspaces-cutover.sh`, not a script to invoke.
- **`verify_set_identity` must be rewritten, not adapted.** `git-data-cutover.sh:246` verifies
  `git rev-list --all | sort | sha256sum` — sound for **bare** repos, where all state is refs/objects.
  `/workspaces` holds **working trees**: uncommitted edits, untracked files, `refs/checkpoints/*`. A
  rev-list identity would **pass while silently dropping exactly the sole-copy data of fact 3.**
  Verification is filesystem-level: `rsync -aHAX --numeric-ids --checksum --delete --dry-run SRC/ DST/`
  must print zero transfers, plus file-count and total-byte asserts. The flags are load-bearing: `-H`
  (hardlinks, which git objects use), `-A -X` (ACLs/xattrs), `--numeric-ids` with a post-pass re-assert
  of `chown 1001:1001 /mnt/data/workspaces` (`cloud-init.yml:581`, must match the Dockerfile UID).
  **A count-match is not an identity** — the same caveat git-data recorded.
- **`/mnt/data` carries more than workspaces.** `/mnt/data/plugins/soleur` (`:573`, seeded `:661-666`)
  is **re-derivable** — cloud-init deletes and re-seeds it from the image via `docker cp`. Rsync all of
  `/mnt/data` anyway (it is free), but the irreplaceable set is `/mnt/data/workspaces` alone.
- **The device glob must die first.** `cloud-init.yml:568-569` mounts via
  `scsi-0HC_Volume_*` and writes that **glob into `/etc/fstab`**, which does not expand globs — so the
  entry is inert, there is no `nofail`, and `|| true` swallows mount failure. Today `/mnt/data` has
  **no working reboot path**, and a reboot would leave the container writing workspaces to the **root
  disk**. A second attached volume also makes the glob match two devices. Pinning to an explicit volume
  ID is **Phase 0/1 and a hard prerequisite**, independently a latent-bug fix. **Verify this against the
  live host before designing around it** — this asserts the code shape, not the running `/etc/fstab`,
  which may have drifted.
- **Terraform state will diverge unless deliberately converged.** The live host ends on
  `soleur-web-platform-data-luks`; a fresh apply would create `soleur-web-platform-data`. Post-soak:
  release `prevent_destroy`, destroy the old volume, `state rm` its address, `moved` the LUKS resource
  onto `hcloud_volume.workspaces["web-1"]`, and rename (hcloud volume `name` is updatable in place, not
  ForceNew). Until that lands the divergence is real and must be drift-guarded, not assumed away.
- **A dedicated `workflow_dispatch` job is required.** `hcloud_volume.workspaces` /
  `_attachment.workspaces` / `hcloud_server.web` are excluded by `OPERATOR_APPLIED_EXCLUSION`
  (`apply-web-platform-infra.yml:29-35`); only the firewall resources are on the per-PR hcloud path.
  Template: the `git_data_host_replace` job (~`:2158`) with its no-`[ack-destroy]`-bypass
  structured-plan gate. The volume create/attach is a **create, not a destroy**, so it does not trip the
  destroy-guard — but it still has no per-PR apply path. **`stock-preflight-gate.sh` does not fire**: it
  scopes to `.server_types.available` (servers only), and no server is created. *That is precisely why
  this design is executable while every server-creating design is currently, and correctly, blocked.*
- **Observability, not SSH.** `hr-no-ssh-fallback-in-runbooks` does not bar an SSH-orchestrated
  cutover — `git-data-cutover.yml` is the sanctioned precedent (workflow_dispatch, creds off-host). It
  bars the *runbook* from saying "log in and check." The canary and the standing drift assert must
  surface to Sentry/Better Stack — reuse the `disk-monitor.service`/`.timer` pattern
  (`cloud-init.yml:151-185`) for a recurring `isLuks` + `findmnt` probe, so a future plaintext
  regression is observable without a login.
- **No database writes.** This plan adds no hot-path `INSERT`/`UPDATE`/`DELETE`; the WAL / Disk-IO
  budget is unaffected.

## Open risks

1. **The live host's `/etc/fstab` and mount state are unverified.** The glob finding is a code-shape
   finding. If web-1 has been rebooted since first boot and `/mnt/data` is currently unmounted, the
   workspace data's actual location is not where this ADR assumes. **Verify before Phase 1** — the
   single highest-value check in the plan; it invalidates the sequencing if it comes back wrong.
2. **Rollback expiry is a one-way door.** Once traffic resumes, plaintext-volume rollback loses the
   delta. If the LUKS mount degrades hours later there is no clean path back. Mitigation: the soak plus
   the recurring canary; the residual risk is accepted.
3. **The cutover writes to `/etc/fstab` on a host whose fstab is already malformed.** Phase 1 and Phase
   4's repoint both edit it. A botched edit is a boot-time failure on a host with no LB and no peer.
4. **Passphrase availability at boot.** The mapper must open unattended via the Doppler-injected key,
   matching git-data's `/etc/default/git-data-doppler` shape. If Doppler is unreachable at boot,
   `/mnt/data` does not mount. `nofail` makes that a degraded boot rather than a hang — the web host
   must inherit that, and **the failure must page**. *(Synthesised with CPO G6: keep `nofail`, and add a
   fail-closed gate before `docker run` so the app never silently writes to the root disk.)*
5. **Divergence window.** Between Phase 4 and Phase 5's convergence, the live host and a hypothetical
   fresh apply differ in volume identity. `hr-fresh-host-provisioning-reachable-from-terraform-apply` is
   satisfied in *behaviour* (both paths end LUKS-encrypted) but not in *state* until convergence. If
   Phase 5 stalls, that divergence becomes permanent drift.
6. **#6568 may not merge.** The sequencing assumes it does. If it stalls, re-price: a two-host migration
   is not twice the work, it is worse — web-2's volume would need the same cutover for a host being
   deleted.

## References

- Issue #6588 (this work) · #6570 (cax11 unorderable) · #6459 (blue-green, ADR needed) · #6538 / PR
  #6568 (web-2 teardown) · #5274 (git-data epic) · #5887 (moved-block/blue-green precedent) · #6453
  (stock-preflight gate)
- ADR-068 (multi-host workspaces / git-data lease) — §1 and its §(d) amendment
- ADR-080 (bake-and-extract for user_data)
- `apps/web-platform/infra/git-data-luks.tf` · `git-data-cutover.sh` · `git-data-luks.test.sh`
- `knowledge-base/engineering/operations/runbooks/git-data-luks-cutover-5274.md`
- `knowledge-base/engineering/operations/runbooks/moved-block-wedge-cutover-5887.md`
