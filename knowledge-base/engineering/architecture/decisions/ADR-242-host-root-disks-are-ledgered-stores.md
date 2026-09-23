---
title: "ADR-242: Host root disks are ledgered stores"
status: accepted
date: 2026-09-23
issue: 8532
supersedes: []
amends:
  - ADR-140
tags: [encryption-posture, ledger, hetzner, root-disk, gdpr, art-32]
---

# ADR-242: Host root disks are ledgered stores

## Status

`accepted`, implemented by the #8532 ledger PR (PR-2 of its plan). The ordinal is provisional
and gets re-checked against `origin/main` at merge, because open PRs have claimed 238 to 241.

## Context

The encryption-posture ledger (ADR-140) divides every Terraform resource type into
`store_classes`, which must have a ledger row with a verified at-rest posture, and
`non_store_types`, which have neither. `hcloud_server` sat in `non_store_types`. That seed
was mechanical: every resource type that was not obviously a volume or a bucket was listed,
with no per-type reason.

The root disk of every Hetzner host is unencrypted, and several hold material that the
ledger's own rows depended on without saying so:

- The inngest root disk caches the passphrase of `hcloud_volume.inngest_redis_luks`
  (`/etc/default/inngest-luks`). The LUKS open unit runs before the network and cannot fetch
  it. Against a seized host, that volume's LUKS defends nothing.
- The web-1, git-data and registry root disks each hold a Doppler token that can fetch the
  passphrase of the LUKS volume beside them.
- The web hosts' persistent journal holds the app container's stdout and stderr. #8617 found
  outbound recipient addresses in that class of data.
- The Inngest SQLite state (`/var/lib/inngest`) lives on the root disk.

The ledger stated none of this, so no gate could reach it.

Separately, a ledger row is keyed on `<type>.<name>`, while `hcloud_server.web` and
`hcloud_volume.workspaces` are both `for_each = var.web_hosts`. One row therefore stood for
two devices. For `workspaces`, their posture differs: web-1's copy is a superseded rollback
backstop, while web-2's copy is web-2's live `/mnt/data` with no LUKS sibling.

## Decision

1. **`hcloud_server` is a store class**, with the new kind `host-root-disk`. Each of the six
   hosts gets a row, and every row is a `plaintext-exception`. The exception's
   `reevaluate_when` names the host's **rebuild window**, because a root disk can be encrypted
   only when its host is rebuilt. The `expires_on` dates are staggered review dates, not
   remediation deadlines. For a host that cannot be rebuilt as such (`rehearsal`, born each
   run; `grok_dogfood`, not yet born), the window is its birth. All six are tracked in #8620.
2. **A row covers every instance of its block, or the sweep fails.** A block with `for_each`
   or `count`, or one instantiated by a module, needs a `multiplicity` declaration on its row.
   A `for_each` over `var.<map>` whose default literal resolves in the same Terraform root is
   compared key for key. Every other shape fails closed unless the row names its `gated_by`
   (a variable, local or module call). That gate must appear in the block's expression and in
   the exception's `reevaluate_when`. A singleton must not declare `multiplicity`.
3. **The floor is exact.** Every catalogued non-IaC id must name a row. Every row must be a
   store-class `.tf` address or a catalogued id, and ids may not repeat. A row at a
   store-class address must be a real block. Together these make
   `rows == tf_store_count + |non_iac_stores|` hold by construction, so there is no slack for a
   deleted row to hide in.
4. **Each LUKS row's `does_not_defend` names where its passphrase lives**, including the
   root-disk copy or the token that fetches it.

`git_data.baked_credentials_on_host` stays a separate row. It records a different threat: the
metadata endpoint serving `user_data` to root. It is not the disk.

## Alternatives Considered

| Alternative | Why not |
|---|---|
| Keep `hcloud_server` a non-store type and record the credential files on the rows they unlock | The passphrase cache and the SQLite state belong to no volume row. A host would still be born unledgered |
| A "holds nothing" mechanism for hosts without data | This self-certifies and nothing can falsify it. `rehearsal` and `grok_dogfood` take an exception row on the `hcloud_volume.rehearsal` precedent instead |
| A `reason` field on each remaining `non_store_types` entry | It satisfies no property, and it crashes `check_resource_partition`, which builds a `set()` over that list (plan review R5). The seed stays mechanical for the other types; this ADR moves the one type whose classification was wrong |
| Instance-keyed rows (`hcloud_server.web["web-1"]`) | Nothing in the ledger's address space or its consumers supports indexed addresses. `multiplicity` gets the same guarantee without re-keying the ledger |

## Consequences

- The sweep reports 25 stores (18 from `*.tf` plus 7 catalogued), with no slack.
- Adding a key to `var.web_hosts`, or setting `enable_grok_dogfood`, fails the gate until
  the ledger is updated. That is the intent: a new host is a new root disk.
- The multiplicity resolver reads only a variable's `default` literal. A `*.tfvars` file in the
  same root makes the literal unauthoritative, and the check then fails closed.
- Root-disk posture has no live signal. Every host row's `live_verification` is `unavailable`,
  because a CI runner cannot see guest-side disk state (ADR-141).

## C4 impact

None. This changes how existing hosts are recorded, not the containers or their relationships.
