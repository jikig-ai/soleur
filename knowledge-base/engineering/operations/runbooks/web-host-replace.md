# Runbook — replacing a web host

**Status:** current as of 2026-07-26 (#6969, ADR-148).
**Applies to:** any `hcloud_server.web[<key>]` that is **already in state** — except `web-1`,
which this path refuses (see below).

**This is the destructive sibling of [birthing a web host](./web-host-birth.md).** A birth is
additive: it creates a declared-but-absent host and its gate permits zero destroys. A replace
**destroys the existing host and creates a new one in its place**. Pick by whether the host
exists:

| The host is… | Use | Gate contract |
|---|---|---|
| declared in `var.web_hosts` but absent from the provider | `web-host-create` | exactly 1 create, 0 destroys |
| present, but broken / dark / on a bad image | `web-host-replace` | exactly 1 delete+create of that key |

Dispatching the wrong one is safe by construction — each gate refuses the other's plan shape,
and the `confirm` tokens are deliberately different — but it wastes a run.

## `web-1` is refused

This path aborts on `web_host_key=web-1`, at input validation and again in the gate. web-1 is
not merely higher-stakes; it is topologically different:

- `hcloud_volume_attachment.workspaces_luks.server_id` is hardcoded to it and is ForceNew, so
  replacing it requires recreating an attachment no other key has. Omit that and the LUKS
  at-rest store boots **unattached** while the host reports healthy.
- `cloudflare_record.app.content` is web-1's `ipv4_address`. Replace it without re-pointing
  the record and `app.soleur.ai` resolves to a destroyed host.
- All **15** `terraform_data.*` SSH provisioners in `server.tf` pin `connection.host` to
  web-1 — including the seccomp and AppArmor sandbox controls. `-target` is upstream-only, so
  none is pulled into the plan and all 15 would be left un-run against a dead IP.
- Decisively: `/mnt/data` pins **by-id** to `hcloud_volume.workspaces[key]`, which on web-1 is
  the **plaintext** volume the 2026-07-23 LUKS cutover **superseded**. Nothing on a fresh boot
  opens the LUKS mapper (crypttab keyfile is `none`; the guest-side unlock path is deferred to
  **#6931**). A rebuilt web-1 would boot healthy and serve every user worktree **rolled back
  to 2026-07-23**, while the live LUKS volume sat attached and unopened.

The last one is a property of cloud-init, not of the terraform plan, so no gate arm can
observe it. **There is no automated route to replace web-1 today**, and there was none before
this path either.

> **Corrected 2026-07-27.** This section previously named an *"ambiguous `scsi-0HC_Volume_*`
> mount glob"* as decisive and gave *"ADR-119 §Sequencing's volume-ID mount pin"* as the
> prerequisite. Both were false — #6604 pinned the mount by-id before this path existed, and
> ADR-119 has no §Sequencing — which made the refusal read as already relaxable. If you are
> here to lift the refusal: the prerequisite is **#6931**, plus key-conditional gate arms for
> `hcloud_volume_attachment.workspaces_luks` and `cloudflare_record.app`, plus a rehearsal on
> a non-production host. Tracker **#6964**; see ADR-148 §Alternatives item 4.

## The procedure

```bash
gh workflow run apply-web-platform-infra.yml \
  -f apply_target=web-host-replace \
  -f web_host_key=web-2 \
  -f confirm=REPLACE-web-2 \
  -f reason='replace web-2 — <why>'
```

Add `-f image_tag=vX.Y.Z` to pin the image explicitly. Without it the pin is read from web-1's
live `/health` — the tag the fleet is actually serving, which is the right default. That read
is **not** circular on this path the way it is for a birth, because web-1 is never the host
being replaced here; supply `image_tag` when the fleet is down or when you need a specific
version.

The run pauses on the `web-platform-infra-apply` environment for reviewer approval before its
first step. Approve it in the Actions UI. **That approval is the only human input** — dispatch
queues the destructive step behind the reviewer gate, it does not bypass it.

`confirm` must be exactly `REPLACE-<key>`. It is a typo-guard, not the authorization, and it
is deliberately not the birth path's `BIRTH-<key>`: a token typed for a birth must not be able
to authorize a destroy.

### What the job does, and why each step is not optional

| Step | Guards against |
|---|---|
| Input validation (shape regex → `var.web_hosts` membership → `REPLACE-<key>` → web-1 refusal) | An unknown key, a mis-selected `apply_target`, and the web-1 hazard above — all before anything reads a secret |
| `SENTRY_DSN` non-empty (ADR-128 R1) | The replacement is a *fresh* host: its pre-extraction boot stages emit through the baked DSN and nothing else. An empty DSN means it boots dark **with the original already destroyed** |
| amd64 runner assertion | A non-amd64 runner resolves the multi-arch index to a different manifest, voiding the coherence preflight's comparison |
| Digest pin (`tag → @sha256`) | TOCTOU: a tag that moves between preflight and apply defeats the preflight entirely |
| Coherence preflight | An image whose baked host-scripts do not match the applied hash aborts cloud-init at `stage=verify`; `runcmd` is once-per-instance, so nothing repairs it. On a replace the previous host is already gone, so this is an outage rather than a no-op |
| `web_host_replace_gate` | Any plan that is not exactly one replace of the requested key with both stores preserved and the NIC / volume attachment / firewall re-attached |
| Stock preflight | **The one that matters most here.** A replace destroys before it creates. The destroy frees the account slot but cannot conjure DC stock, so an out-of-stock create leaves the host gone and unrecreatable (#6393/#6400). On 2026-07-26 the entire cx and cax lines were orderable in 0 of 3 EU DCs (#6966) |
| Boot-trail read (ADR-128 R2–R5) | A green `terraform apply` that produced a dark host — which is #6969's originating incident exactly |

### What is preserved, and by what mechanism

The `-target` set is four addresses: the server, its NIC, its workspaces volume attachment,
and the fleet firewall attachment. Everything else is **absent from the target set**, and that
absence is what keeps them out of the destroy set. The obvious formulation — *"an untargeted
resource cannot be planned for destroy"* — is **false**: `-target` prunes **dependents**, not
**dependencies**. So the mechanism differs per address:

- `hcloud_volume.workspaces[<key>]` — the host's workspace store. It IS in the plan graph (the
  targeted attachment references it) and appears as a no-op. What preserves it is
  `prevent_destroy = true`, which errors at **plan** time, plus the gate's `out_of_scope` and
  `workspaces_volume_destroyed` arms. It survives the replace and re-attaches to the new host.
- `hcloud_volume.workspaces_luks` and the LUKS passphrase pair — untouched, so the at-rest
  data stays readable behind its existing header. A rotated passphrase would open a *new*
  header and strand the data while the host booted healthy.
- `cloudflare_record.app` — must not move on a standby replace. Any positive action on it is
  an out-of-scope abort.

The gate carries named backstops for the two volumes and the passphrase. They are
intentionally redundant with the out-of-scope arm; they exist so the abort message names the
catastrophe rather than saying "an address you did not authorize changed".

## What the replace does NOT restore

The `-target` set is upstream-only, so nothing downstream of the server rides along. Two
consequences worth knowing before you dispatch:

- **All 15 `terraform_data.*` SSH provisioners** (disk monitor, resource monitor, fail2ban
  tuning, persistent journald, seccomp/AppArmor profiles, cron egress firewall, orphan reaper,
  …) hardcode
  `connection.host` to **web-1**. They never applied to any other host, so a non-web-1
  replace neither loses nor needs them.
- **Better Stack heartbeats** for the host already exist and are not targeted. If they are
  still `paused`, they are armed by the measure-then-arm step in the `apply` job at the next
  merge-to-main infra apply — the same as after a birth.

Neither is a regression introduced by this path; both match the birth path's behaviour. They
are listed because "the host is back" and "the host is fully configured" are different
claims, and the dispatch summary only supports the first.

## Verify the result

The job verifies itself and fails if the host booted dark — there is nothing to eyeball. The
boot-trail step polls Sentry for the host's own stage breadcrumbs and:

- exits clean when the trail reaches `cloud_init_complete` (and raises a `::warning::` if the
  host booted clean but *retried* a stage — a real fault that a green run would otherwise
  bury);
- fails the run with an `::error::` naming the **stage and the cause** on a fatal;
- fails the run if no terminal event lands inside the host's own 900 s boot window, because
  absence past the boot window is the documented dark signal, not a slow boot.

If it reports a dark boot: `runcmd` is once-per-instance, so the host **cannot be repaired by
a reboot**. Do not put it into service — replace it again once the cause is fixed.

## If the apply fails partway

A replace destroys before it creates, so check the apply output for whether the destroy
landed:

- **Destroy did not run** — nothing changed. Re-dispatch after fixing the cause.
- **Destroy landed, create failed** (out-of-stock is the documented cause) — **two states are
  reachable and their recoveries are opposite.** Determine which one you are in first, from
  the apply log or a Hetzner API existence probe:

  ```bash
  curl -sS -H "Authorization: Bearer $HCLOUD_TOKEN" \
    "https://api.hetzner.cloud/v1/servers?name=soleur-<key>" | jq '.servers | length'
  ```

  - **Absent from state** (the create never returned an id) — re-dispatching *this* target
    plans zero replaces and the gate correctly refuses. Recovery is
    [`web-host-create`](./web-host-birth.md): additive, graded against the birth contract.
  - **In state but TAINTED** (the create returned an id and a later step failed) — a tainted
    resource plans `delete+create`, which *this* gate PASSES. Re-dispatch
    `web-host-replace`. Do **not** use `web-host-create` here: the birth gate aborts on the
    destroy arm.

  Either way the workspaces volume was never in the destroy set and re-attaches to the new host.
  If stock is the cause, repin `var.web_hosts[<key>].server_type` to an orderable type and
  **merge that change first** — this job replaces a host as declared, it does not redeclare
  one.

## References

- ADR-148 — web-host replacement is a distinct gated dispatch, not a widened birth
- ADR-145 — host birth is a guarded capability (the additive sibling)
- ADR-128 — fresh-boot observability (R1–R5)
- ADR-119 — the workspaces-LUKS cutover (why web-1 is refused)
- `tests/scripts/lib/web-host-replace-gate.sh` — the gate, with its full arm-by-arm rationale
- `tests/scripts/test-web-host-replace-gate.sh` — the mutation battery proving no arm is vacuous
- [Runbook — birthing a web host](./web-host-birth.md)
