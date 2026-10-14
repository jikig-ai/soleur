Follow-up of #8285 (retire the plaintext Redis AOF backstop volume). Deferred from PR B (plan: `knowledge-base/project/plans/2026-10-09-chore-pr-b-retire-inngest-backstop-wipe-apparatus-plan.md`).

## What was deferred

With the plaintext backstop destroyed (2026-10-09, Hetzner 404 at 16:21:26Z), `hcloud_volume.inngest_redis_luks` (id 106903269) is the **only copy** of the Inngest Redis AOF (in-flight job payloads and armed reminders), and `INNGEST_REDIS_LUKS_KEY` in Doppler `soleur-inngest/prd` is its sole opener (ADR-142 addendum 2026-10-08; counsel review 2026-09, O4).

Nothing in Terraform or at Hetzner currently refuses a delete of that volume or of its attachment. The web-1 workspaces precedent (#9348, `hcloud_volume.workspaces_luks`) added `prevent_destroy = true` and `delete_protection = true`, and pinned every edge that makes the data unreachable (destroy, detach, replace of the attachment, state-forget, any still-dispatchable retired job).

## Why it is not in PR B

- PR B is docs, ledger, tests and tooling; it makes no hand-written production change. `delete_protection = true` is an in-place update of a live volume applied by the per-merge apply, i.e. a production write that deserves its own review and per-command authorization.
- The design differs from web-1: `apply_target=inngest-host-replace` legitimately replaces `hcloud_volume_attachment.inngest_redis_luks` (its `server_id` is ForceNew), so the web-1 pin set cannot be copied verbatim. The plan must decide which edges are pinned and which dispatch is the sanctioned route.

## Scope when picked up

1. Enumerate every operation that makes the store unreachable: volume destroy/replace, attachment destroy/detach (and which are legitimate under host replace), state-forget, key loss (Doppler secret delete/rotate), and any dispatchable job that can reach them.
2. Decide `prevent_destroy` / `delete_protection` placement, with the guard scanning effective text (not a serialization).
3. Record key-loss recovery posture (the volume is unrecoverable without the Doppler key).

## Re-evaluation criteria

Before the next `apply_target=inngest-host-replace`, or when #8620 (root-disk encryption at the inngest rebuild window) reaches its window, whichever comes first.

Ref #8285
Ref #8620

Mandated-By: wg-when-deferring-a-capability-create-a
