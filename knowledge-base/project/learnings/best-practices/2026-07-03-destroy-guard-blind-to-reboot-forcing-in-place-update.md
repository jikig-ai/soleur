---
title: A delete-only destroy-guard is blind to reboot-forcing in-place updates
category: best-practices
module: infra/ci-destroy-guard
issue: 5911
pr: 5930
date: 2026-07-03
tags: [terraform, destroy-guard, hcloud, ci, invariant-not-proxy]
---

# Learning: A destructive-change guard that counts only `delete` is blind to reboot-forcing in-place `update`

## Problem

The web-platform terraform destroy-guard
(`tests/scripts/lib/destroy-guard-filter-web-platform.jq`, consumed inline by
`apply-web-platform-infra.yml`) counted only `delete` actions
(`resource_deletes`) + nested-block removals on 5 Cloudflare types
(`nested_deletes`). It was **structurally blind** to a reboot-forcing in-place
`update` on `hcloud_server.*`: changing `placement_group_id` or `server_type`
powers-off / reboots the running prod host with **0 destroys**, so the guard's
`destroy_count` stayed 0 and the unattended per-PR apply proceeded without any
`[ack-destroy]`. The single production web host reachable in the targeted plan
(as a dependency of `hcloud_firewall_attachment.web`) could be power-cycled
mid-merge with a green check.

## Solution

Add a third counter, `reboot_updates`, to the same filter and fold it into the
same `destroy_count`/`[ack-destroy]` gate:

```jq
reboot_updates: (
  [ .resource_changes[]?
    | select(.type == "hcloud_server")
    | select(.change.actions == ["update"])
    | select(.change.before.placement_group_id != .change.after.placement_group_id
          or .change.before.server_type       != .change.after.server_type) ]
  | length
)
```

Mirror the read + `^[0-9]+$` parse-guard + sum in the workflow bash, and add a
reboot-specific `::error::` that steers the resolution to the **operator
maintenance-window apply** — NOT `[ack-destroy]` (because the host update is
transitively in the saved plan, an ack-through would *execute* the reboot on
the unattended apply, re-introducing the exact hazard).

## Key Insight

**"Destructive" is not synonymous with the `delete` action.** An in-place
`update` can be as disruptive as a destroy (a reboot drops in-flight sessions).
A guard keyed on the `delete` *action* is a proxy for "disruptive change"; the
invariant is the *effect*. Three discipline points that generalize:

1. **Select the exact lifecycle shape.** `actions == ["update"]` (exact
   array-equality, stable across jq 1.6/1.7/1.8) — never `index("update")`.
   A REPLACE serializes as `["delete","create"]` and is already counted by the
   delete counter; exact-`["update"]` guarantees no double-count and no
   false-fire on CREATE (a 2nd-host add) or a `moved` re-address (no-op).
2. **Compare the reboot-forcing *attributes*, not the mere presence of an
   update.** A `labels`-only update is `["update"]` but not a reboot — the
   proxy-vs-invariant trap. Detect the attribute diff.
3. **Err safe on unknowns.** When `placement_group_id` is a resource reference,
   its value is unknown at plan time (`after.<attr>` absent → jq yields `null`);
   `before(0) != null` still trips. An unknown `after` must never yield a
   *missed* reboot — availability friction is the safe failure direction.

The residual allowlist of attributes (`placement_group_id`, `server_type`) is
itself a second-order proxy — it silently narrows as `server.tf`'s attribute
surface grows (a new `rescue`/`iso` or a provider ForceNew→in-place flip returns
`rupd=0`). Mitigation is CODEOWNERS coupling + a documented KNOWN-UNCOVERED note
in the filter header, not a heavyweight attribute-parity test.

## Session Errors

1. **`Edit` "File has been modified since read"** on the counter test — a
   hook/linter re-touched the file between Read and Edit. Recovery: re-read,
   retried; content was identical. Prevention: none warranted — transient
   tool-state race, one-off, no recurrence vector.
2. **Bash "Shell cwd was reset"** after a `/tmp` jq probe — expected/benign;
   every Bash call already `cd`s into the worktree. Prevention: already handled.

## Tags
category: best-practices
module: infra/ci-destroy-guard
