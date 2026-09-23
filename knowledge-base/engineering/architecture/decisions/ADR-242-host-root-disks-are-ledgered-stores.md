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
- Inngest's SQLite directory (`/var/lib/inngest`) is on the root disk. It is vestigial in the durable
  Postgres+Redis mode and load-bearing only in the Redis-not-ready fallback; whether it holds
  residual state is not measured.

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
2. **A multi-instance block must say so on its row.** A block with `for_each` or `count`, or
   one instantiated by a module, needs a `multiplicity` declaration on its row. A `for_each`
   written exactly as `var.<map>`, whose default literal resolves in the same Terraform root,
   is compared key for key. Every other shape (`count`, a `for` expression, a module call)
   cannot be verified: the row must declare `instances: []`, because an unchecked list would
   read as coverage it does not have. Its exception's `reevaluate_when` must name one of the
   `var.`/`local.`/`module.` identifiers in the block's own expression, which the check
   derives rather than taking from the row. A singleton must not declare `multiplicity`.
3. **The floor is exact.** Every catalogued non-IaC id must name a row. Every row must be a
   store-class `.tf` address or a catalogued id, and ids may not repeat. A row at a
   store-class address must be a real block. The operands must be disjoint sets: an address
   declared in two Terraform roots, a catalogued id that is also a `.tf` address, and a
   catalogue entry listed twice each fail by name. Given that, `rows == tf_store_count +
   |non_iac_stores|` holds by construction, so there is no slack for a deleted row to hide in.
   A row also conforms to its store class: the class's `kind`, and one of its `mechanisms`.
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

- At merge the sweep reports 26 stores (18 from `*.tf` plus 8 catalogued), with no slack.
- Adding a key to the `var.web_hosts` default fails the gate until the ledger is updated: a new
  host is a new root disk. Flipping a count gate (`enable_grok_dogfood`) does NOT: Layer A reads
  committed code, and the gate is flipped by a dispatch input. What Layer A guarantees for a
  gated block is that its row exists, admits it covers an unknown set, and names the gate that
  reopens it.
- The multiplicity resolver reads the committed `default` literal. The sweep reads only tracked
  files (`git ls-files`), so an untracked `.tf`, a gitignored `*.tfvars` or a `.terraform/` cache
  on one machine cannot change its verdict; `*.tfvars` is gitignored here and the apply reads
  its `TF_VAR_*` inputs from Doppler.
- Host rows keep `expires_on` inside ADR-140's 90-day window as review dates; the rebuild
  window is in `reevaluate_when`.
- The web-1 snapshot images are a catalogued row of kind `provider-image`, not a root disk.
  They are the first store a CI runner could observe directly (`GET /v1/images`), which is
  ADR-141's arming trigger; nothing polls them yet.
- Root-disk posture has no live signal. Every host row's `live_verification` is `unavailable`,
  because a CI runner cannot see guest-side disk state (ADR-141).

## C4 impact

No new element or relationship. `model.c4` gains ledger clauses on existing store elements and the
Inngest server's root-disk posture in its description (ADR-243 owns the clause convention).
