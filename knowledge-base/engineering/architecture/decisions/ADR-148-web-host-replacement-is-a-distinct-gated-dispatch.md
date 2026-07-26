# ADR-148: Web-host replacement is a distinct gated dispatch, not a widened birth

- **Status:** accepted
- **Date:** 2026-07-26
- **Issue:** #6969 (`soleur-web-2` is dark and there is no mechanism to replace it). Related: #6416 (the birth-without-NIC incident the `host_creates` HALT exists for), #6393/#6400 (an out-of-stock recreate stranding the fleet), #6966 (the cx→cpx repin forced by stock), #6459 (web-2 as the cattle-host disposability proof).
- **Extends:** ADR-145 (host birth is a guarded capability — this is the *replacement* sibling it explicitly deferred), ADR-143 (host lifecycle), ADR-128 (fresh-boot observability R1–R5).
- **Constrained by:** ADR-119 (the workspaces-LUKS cutover, whose in-flight two-volume state is why web-1 is refused).
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
**absent**. An untargeted resource cannot be planned for destroy, so omission is the primary
mechanism; the three named backstops in the gate are intentionally redundant and exist for
the error text an operator reads mid-abort.

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
eight `terraform_data.*` SSH provisioners in `server.tf` (`disk_monitor_install`,
`resource_monitor_install`, `fail2ban_tuning`, `journald_persistent`, …) hardcode
`connection.host = hcloud_server.web["web-1"].ipv4_address`. They are web-1-only, not
per-host, so they are correctly absent from a non-web-1 replace — but a web-1 replace changes
that IP and would leave every one of them pointing at a destroyed host until the next
token-gated SSH apply. `-target` is upstream-only, so nothing pulls them in and no gate arm
would notice.

Those three are all expressible as key-conditional arms. The decisive reason is not:

> *"with a second volume attached, the `scsi-0HC_Volume_*` glob in cloud-init.yml becomes
> AMBIGUOUS. Pinning the mount by volume ID is a hard prerequisite of the cutover."*
> — `workspaces-luks.tf`

web-1 currently carries **two** attached volumes mid-ADR-119 cutover. A fresh web-1 would
boot, mount whichever volume the glob resolved first, serve normally, and strand or overwrite
data. That is a property of **cloud-init**, not of `resource_changes` — no plan-shaped gate
can observe it. Admitting web-1 would mean certifying a safety property the gate cannot
check, which is the failure mode every arm above exists to refuse.

The refusal is keyed on `_WEB_HOST_REPLACE_LUKS_PINNED_KEY` so that when ADR-119
§Sequencing's volume-ID mount pin lands, the reviewer of *that* change is the one who decides
to relax it. The workflow repeats the refusal as a fail-fast input check purely so the
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
