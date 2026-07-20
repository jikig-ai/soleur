# Learning: a new `for_each = var.<map>` resource can force premature provisioning of a `-target`-excluded sibling

## Problem

Plan v1 for #5933 Item 1 added a per-host probe `cloudflare_record "web_host"` with `for_each = var.web_hosts` (all hosts) and `content = hcloud_server.web[each.key].ipv4_address`. `var.web_hosts` includes `web-2`, but `hcloud_server.web` is **deliberately excluded** from the auto-apply `-target=` allow-list (`apply-web-platform-infra.yml:29`) — web-2 is provisioned only at the operator's #5274 maintenance window.

The trap: the new record IS in the `-target` set (all `cloudflare_record.*` are). Terraform `-target` **auto-pulls dependencies**, so a routine per-PR merge-apply would plan to **CREATE `hcloud_server.web["web-2"]`** — provisioning a fresh prod host outside the maintenance window, without the DNS rewire. A pure create is neither a destroy nor a reboot-update, so the destroy-guard filter does not catch it. Single-user-incident class, invisible in the plan text.

Caught pre-merge by three independent plan-review agents (spec-flow, architecture-strategist) + the plan author's own `-target` allow-list read.

## Solution

When a new resource uses `for_each = var.<map>` (or references `<resource>[each.key]`) AND the map contains entries whose backing resource is **excluded from the auto-apply `-target` allow-list** (deferred/maintenance-window-only provisioning), gate the new resource's `for_each` on the **same existence predicate** the sibling uses:

```hcl
for_each = { for k, v in var.web_hosts : k => v if v.monitored }
```

so it materialises only for entries that actually exist. Verify with `terraform plan` asserting **no create** of the excluded resource. Add the new resource to the `-target` allow-list in the same PR (a `for_each` base address like `-target=cloudflare_record.web_host` targets all its instances).

## Key Insight

`-target` is transitive on dependencies. A new targeted resource that references a `-target`-excluded resource silently drags that excluded resource into the plan — the exclusion is not a firewall, it's a default the new reference overrides. The `-target` allow-list and the resource's own `for_each` filter must agree on which entries exist; a new `for_each` over the full map is the common way they silently diverge.

Corollary (also this session): a cosign keyless verify identity regexp for an image signed by a **reusable** workflow must pin `@(refs/heads/main|refs/tags/v[0-9].+)$` — the loose `refs/(heads|tags)/.+` accepts a signature from ANY intra-repo branch/tag push (attacker-branch RCE that ENFORCE would trust).

## Tags
category: workflow-patterns
module: plan, terraform
related: ADR-082, #5933, #5887, #5274, apply-web-platform-infra.yml, 2026-07-03-brainstorm-re-verify-adr-deferral-triggers-against-live-state.md
