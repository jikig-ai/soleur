# ADR-148: Web-host replacement is a distinct gated dispatch, not a widened birth

- **Status:** accepted
- **Date:** 2026-07-26
- **Issue:** #6969 (`soleur-web-2` is dark and there is no mechanism to replace it). Related: #6416 (the birth-without-NIC incident the `host_creates` HALT exists for), #6393/#6400 (an out-of-stock recreate stranding the fleet), #6966 (the cx→cpx repin forced by stock), #6459 (web-2 as the cattle-host disposability proof).
- **Extends:** ADR-145 (host birth is a guarded capability — this is the *replacement* sibling it explicitly deferred), ADR-143 (host lifecycle), ADR-128 (fresh-boot observability R1–R5).
- **Constrained by:** #6931 (fresh-boot guest-side LUKS unlock — the real reason web-1 is refused; see §web-1 is refused). Related: ADR-119 (the workspaces-LUKS cutover), #6964 (tracker).
- **Plan:** `knowledge-base/project/plans/2026-07-26-feat-web-host-replace-dispatch-target-plan.md`

## Context

`soleur-web-2` booted dark and stayed dark. Nothing could replace it.

`apply_target=web-host-create` (ADR-145) is additive-only by contract: its gate requires
**exactly one create and zero destroys**. A host already in state plans zero creates, so the
birth gate correctly refuses — it names the case in its own message, *"the host already
exists (a no-op the gate must not rubber-stamp)"*. Its header also names the missing sibling:

> *"Scoped host REPLACEMENT is a different operation with a different gate; it does not
> borrow this one."*

Every other automated route to `hcloud_server.web` HALTs on `host_creates > 0`, and that HALT
is **not inherited** by dispatch jobs — it is a separate inline copy in the `apply` job whose
`if:` is mutually exclusive with every dispatch job. So a new dispatch job's own gate is not
defense-in-depth behind an existing check; for that path it is the only check.

## Decision

Ship `apply_target=web-host-replace` as a **sibling** of the birth path, generic over
`var.web_hosts` keys, with its own inverted gate
(`tests/scripts/lib/web-host-replace-gate.sh`). The `host_creates` HALT stays. The birth path
stays additive-only.

The gate PASSES only a plan that is **exactly one `delete+create` of the requested host**,
with seven prohibitions and three requirements:

| Arm | Assertion | Why |
|---|---|---|
| `replaced` | `== 1` | one authorization replaces one host |
| identity | replaced address `== hcloud_server.web["<key>"]` | a count-only check passes a plan that replaces **web-1** — the total-outage case |
| `workspaces_volume_destroyed` | `== 0` | named backstop; the per-host workspace store |
| `luks_volume_destroyed` | `== 0` | named backstop; the LUKS at-rest store |
| `luks_passphrase_touched` | `== 0` | a rotated passphrase opens a new header and strands the at-rest data while the host boots healthy |
| `reboot_updates` | `== 0` | the fleet firewall singleton drags every host into the plan; a `server_type` delta on web-1 would power-cycle the sole live origin |
| `out_of_scope` | `== 0` | exact-equality `IN(...)` membership, never `contains`/`inside` |
| `nic` | `>= 1` | absent ⇒ #6416: no private IP, transiently no firewall, and it looks like a successful apply |
| `vatt` | `>= 1` | absent ⇒ `/mnt/data` writes to the ROOT DISK behind a fail-open mount; every workspace is lost when the real volume mounts over it |
| `fw` | `>= 1` | absent ⇒ the fresh host boots NAKED on its public IPv4/IPv6 |

Authorization is the `web-platform-infra-apply` environment reviewer plus a
`confirm=REPLACE-<key>` typo guard, deliberately distinct from the birth path's
`BIRTH-<key>` so a token typed for one cannot authorize the other. **No `[ack-destroy]`
bypass** (`hr-menu-option-ack-not-prod-write-auth`).

### The stores are preserved by OMISSION, not by a gate arm

The `-target` set is four addresses: the server, its NIC, its workspaces volume attachment,
and the fleet firewall attachment. `hcloud_volume.workspaces[key]`,
`hcloud_volume.workspaces_luks`, the LUKS passphrase pair and `cloudflare_record.app` are all
**absent** from the `-target` set.

Be precise about *why* that preserves them, because the obvious formulation is wrong.
"An untargeted resource cannot be planned for destroy" is **false**: `-target` prunes
**dependents**, not **dependencies**, so `hcloud_volume.workspaces[key]` IS in this plan's
graph (the targeted attachment references it, and the server's `user_data` takes its id) and
appears as a no-op. What actually preserves each address is different per address:

- `hcloud_volume.workspaces[key]` — in-graph. Preserved by `prevent_destroy = true`, which
  errors at **plan** time, plus the `out_of_scope` and `workspaces_volume_destroyed` arms.
- `hcloud_volume.workspaces_luks`, the LUKS passphrase pair, `cloudflare_record.app` — genuinely
  outside the graph, because no targeted address references them. Note the LUKS volume has
  **no** `prevent_destroy`, so `out_of_scope` and `luks_volume_destroyed` are its only guards;
  if a future reference path is added (the shape `workspaces_volume_id` already establishes),
  it becomes in-graph and those two arms are all that remain.

The named backstops are intentionally redundant with `out_of_scope` and exist for the error
text an operator reads mid-abort.

### The stock preflight is mandatory here, not advisory

A replace **destroys before it creates**. The destroy frees the account slot but cannot
conjure DC stock, so an out-of-stock create leaves the host gone and unrecreatable — #6393 /
#6400 verbatim. On 2026-07-26 the entire Hetzner cx line (including web-1's `cx33`) and the
entire cax line were orderable in **0 of 3** EU DCs (#6966).

### web-1 is refused by name

This is the decision that departs from the plan, which asked for a gate handling web-1 and
non-web-1 keys alike. Phase 0 measurement falsified the premise it rested on.

The plan assumed a web host owns two symmetric per-host volume families, mirroring git-data.
It does not:

- `hcloud_volume.workspaces` **is** `for_each = var.web_hosts` — per host.
- `hcloud_volume.workspaces_luks` is a **singleton**, and
  `hcloud_volume_attachment.workspaces_luks.server_id` is hardcoded to
  `hcloud_server.web["web-1"].id`. **web-2 has no LUKS volume at all.**

So replacing web-1 entails two members no other key has — the LUKS attachment (ForceNew on
`server_id`; omit it and the at-rest store boots unattached) and `cloudflare_record.app`
(pinned to web-1's `ipv4_address`; omit it and `app.soleur.ai` resolves to a destroyed host).

There is a third asymmetry, found while checking whether the `-target` set was complete: the
**15** `terraform_data.*` SSH provisioners in `server.tf` — every one except
`deploy_pipeline_fix`, and including the `docker_seccomp_config`, `apparmor_bwrap_profile`
and `cron_egress_firewall` sandbox controls — hardcode
`connection.host = hcloud_server.web["web-1"].ipv4_address`. They are web-1-only, not
per-host, so they are correctly absent from a non-web-1 replace — but a web-1 replace changes
that IP and would leave every one of them pointing at a destroyed host until the next
token-gated SSH apply. `-target` is upstream-only, so nothing pulls them in and no gate arm
would notice.

Those three are all expressible as key-conditional arms. The decisive reason is not — and
**this paragraph replaces a false one**, recorded rather than quietly rewritten because the
false version was load-bearing and shipped to five places:

> **RETRACTED.** An earlier revision named an *"AMBIGUOUS `scsi-0HC_Volume_*` glob"* as
> decisive, quoting `workspaces-luks.tf`. That glob does not exist: **#6604** pinned the mount
> by-id (`cloud-init.yml`: `/dev/disk/by-id/scsi-0HC_Volume_${workspaces_volume_id}`), and
> `soleur-host-bootstrap-observability.test.sh` AC6b REDs if the bare glob returns. The
> quoted comment had been stale on `main` for nine days. It was **quoted, not measured** — in
> a plan whose Research Reconciliation table opens *"Every row measured this session against
> the worktree, not recalled."*

The real decisive reason is the **opposite of ambiguity — it is determinism pointed at the
wrong volume**, and it is worse:

`/mnt/data` on a fresh host pins by-id to `hcloud_volume.workspaces[key]`, which on web-1 is
the **plaintext** volume that the 2026-07-23 cutover **superseded** — the encryption-posture
ledger records live data on `hcloud_volume.workspaces_luks` and the plaintext volume as
*"retained as the pre-cutover rollback backstop"*. Nothing on a fresh boot opens the mapper:
`soleur-host-bootstrap.sh` writes crypttab with keyfile `none` + `nofail`, and the guest-side
unlock path is **deferred to #6931**. So a rebuilt web-1 boots healthy, mounts the superseded
backstop, and serves every user worktree **rolled back to 2026-07-23**, while the live LUKS
volume sits attached and unopened. That is a property of **cloud-init**, not of
`resource_changes` — no plan-shaped gate can observe it.

**The unblock condition is #6931**, not the ADR-119 mount pin. The retracted wording named
*"ADR-119 §Sequencing's volume-ID mount pin"* — a section that does not exist in ADR-119, for
a pin that already shipped — so the refusal read as **relaxable today**, and a reviewer
following it would have deleted the refusal and inherited reasons 1–3 with no gate arms at
all. Relaxing requires: #6931, plus key-conditional requirement arms for
`hcloud_volume_attachment.workspaces_luks` and `cloudflare_record.app`, plus a rehearsal on a
non-production host. Tracker: **#6964**.

The refusal is keyed on `_WEB_HOST_REPLACE_LUKS_PINNED_KEY`. The workflow repeats the refusal as a fail-fast input check purely so the
operator reads the reason before a digest resolve and a terraform plan; the gate remains the
load-bearing control, and `terraform-target-parity.test.ts` binds the two literals.

## Alternatives considered

1. **Widen the birth gate to accept `["delete","create"]`.** Rejected. It dissolves the
   birth/replace distinction that gives the birth gate's destroy arm its meaning: a replace
   reads as one create to a naive counter while destroying a live host. The birth gate's own
   header forbids exactly this.
2. **Destroy then create as two dispatches.** Rejected. It opens a window in which the host
   is absent from state with no plan to restore it, and doubles the approval surface for one
   logical operation.
3. **Operator-local `terraform apply -replace`.** Rejected per
   `hr-all-infrastructure-provisioning-servers` and
   `hr-fresh-host-provisioning-reachable-from-terraform-apply`.
4. **Support web-1 via key-conditional requirement arms** (require the LUKS attachment
   recreate and the `cloudflare_record.app` update when the key is web-1). Rejected *for now*
   — the arms are writable and would be strengthening rather than weakening, but they cannot
   reach the ambiguous-mount hazard above, which is the one that loses data silently. Revisit
   as a follow-up once ADR-119's volume-ID mount pin lands; that work also needs a rehearsal
   on a non-production host, since no web-1 replace has ever been performed.

## C4 impact — none, and here is what was enumerated

A bare "no C4 impact" is not checkable, so the enumeration is recorded. Checked against all
three files in `knowledge-base/engineering/architecture/diagrams/` (`model.c4`, `views.c4`,
`spec.c4`):

- **External actors** — `founder` ("Founder / Operator") already models the person who fires a
  gated `workflow_dispatch` and clicks the environment approval. No new actor; `emailSender`,
  `betaContact` and `contributor` are untouched.
- **External systems** — `github` (Actions as the apply substrate), `hetzner` (Compute),
  `sentry` (boot-stage ingest) and Doppler are all already modeled, and this change adds no
  new vendor edge.
- **Containers / data stores** — no new store. `hetzner.workspacesVolume` and the LUKS volume
  already appear with their at-rest posture; this change *preserves* both by omission and
  alters neither their declaration nor their encryption posture.
- **Relationships** — the existing `github -> hetzner` apply relationship already covers a
  terraform-driven host lifecycle operation. A second `apply_target` on an existing workflow
  is a new *authorization route inside* that relationship, not a new edge between elements.

The one description that could be argued stale is `hetzner`'s, which says the fleet "remains
single-host until web-2 is provisioned by the gated web-host-create dispatch" — still true;
this change adds a replacement route and does not provision anything. It is updated when the
rebirth actually lands, not on the mechanism merging.

## Consequences

- The fleet gains a real replacement mechanism, and #6969's dark web-2 becomes recoverable
  without touching the birth path's contract.
- `web-1` remains non-replaceable by automation until ADR-119 completes. This is a *narrowing*
  of the plan's intended scope and is recorded as such rather than as a completed capability.
  The birth path is likewise unable to replace it, so this changes nothing about web-1's
  current posture — it declines to claim an improvement that was not delivered.
- The fresh-host boot-trail reader (ADR-128 R2–R5) is extracted from the birth job into
  `apps/web-platform/infra/scripts/fresh-host-boot-trail.sh` and shared by both provisioning
  jobs, so a replaced host surfaces the same last-reached-stage telemetry that #6969 needed
  and did not have. `soleur-host-bootstrap-observability.test.sh` AC8d asserts every
  provisioning job wires it — without that, every assertion about the reader's body would
  pass whether or not any job still called it.
