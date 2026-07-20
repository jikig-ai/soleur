# Learning: `terraform plan` cannot see what a whole-list-owning resource destroys

## Problem

Sibling to
`2026-07-20-a-plan-can-prescribe-a-resource-its-credential-cannot-create.md`,
one layer deeper and considerably more dangerous. That one: the credential could
not create the resource, so the apply 403'd — loud, safe, nothing lost. This
one: the apply would have **succeeded** and silently deleted live production
config.

Same PR (#6746), same resource. `cloudflare_ruleset.seo_config_settings`, a
`kind = "zone"` ruleset on the `http_config_settings` phase.

Throughout planning, review and implementation, `terraform plan` reported:

```
Plan: 1 to add, 0 to change, 0 to destroy.
```

That plan is **correct and completely misleading**. The resource is absent from
state, so Terraform plans a create. It never calls the API, so it never
discovers that the phase entrypoint it is about to "create" already exists and
already contains a rule:

```
"Flexible SSL for web platform" / (http.host eq "app.soleur.ai")
/ set_config { ssl: "flexible" }        (created in the dashboard, 2026-03-17)
```

A `kind = "zone"` ruleset **owns its phase entrypoint as a whole-list
replacement**. Applying our one-rule resource would have replaced the entrypoint's
rule list with just our rule — deleting the Flexible SSL rule and dropping
`app.soleur.ai` to the zone-level SSL mode. If that mode is Full/Strict and the
origin has no valid cert, the main product host serves TLS errors.

`0 to destroy` was, in the most literal sense, a lie.

## What caught it

Not the plan, not CI, not the 6-agent review panel, and not `/deepen-plan`. A
one-line probe added during `/review` as task 2.9.3b, on the reasoning that a
whole-list-owning resource has a blind spot `plan` structurally cannot cover:

```bash
GET /zones/$ZONE/rulesets/phases/http_config_settings/entrypoint
# expect 404, or 200 with an empty result.rules array
```

It returned **200 with one rule**, on its first real run. The probe existed for
maybe six hours before it earned its entire cost.

Worth noting *why* it nearly didn't run: the probe was written as a task in a
spec file, gated behind an unrelated blocker (a token widen). Had the widen been
done by an operator out-of-band and the PR merged on the strength of its green
plan, nothing would have run it.

## Key insight

**A clean `terraform plan` is fully compatible with a destructive apply, for any
resource that owns a whole list it did not create.**

The general shape: resource types that manage a *collection as a unit* — ruleset
phase entrypoints, DNS record sets, IAM policy documents, ACL lists — express
"here is the complete list" rather than "here is one member". For those, absence
from Terraform state is not evidence of absence in the world, and `plan`'s
create/destroy counts describe only what Terraform *knows about*, never what
exists.

The reflex to build: before the FIRST apply of any whole-list-owning resource,
enumerate the live collection. Not as a nice-to-have — as the precondition. If
it is non-empty, the choice is adopt-and-import or do not apply.

## Resolution

Adoption, and both halves are required:

1. Reproduce the pre-existing rule verbatim as a `rules` block in the resource.
2. An `import` block adopting the existing ruleset into state, so Terraform
   **updates** the entrypoint rather than creating it.

(1) without (2) still creates and clobbers. (2) without (1) still deletes the
rule on the next plan. Verified shape after both:

```
Plan: 1 to import, 0 to add, 1 to change, 0 to destroy.
```

...where the single change is `+1 rule` and the adopted rule shows every
attribute unchanged.

## Trap inside the fix: the import block is version- and provider-sensitive

The import block as first written could not have worked, and neither failure
said what was actually wrong.

**Import ID syntax is v4-vs-v5.** The provider docs on the `main` branch — which
is what a docs lookup returns — say `zones/<zone_id>/<ruleset_id>`. That is v5.
We are pinned to `~> 4.0` (4.52.7), which wants **singular** `zone/<zone_id>/<ruleset_id>`.
v4 does not reject the unknown plural prefix. It falls through to the
account-level path and issues `GET /accounts/<zone_id>/rulesets/<id>` — a zone ID
in an accounts URL — which surfaces as:

```
Error: error reading ruleset ID "a21ac..."
Authentication error (10000)
```

The error names *authentication*, so it reads as a token-scope problem and sends
you back to re-probe a credential that was already correct. Verified empirically
against 4.52.7:

| import ID | result |
|---|---|
| `<zone_id>/<ruleset_id>` | `invalid import identifier` |
| `zones/<zone_id>/<ruleset_id>` (v5 form) | wrong-path `Authentication error (10000)` |
| `zone/<zone_id>/<ruleset_id>` | correct `GET /zones/<zone_id>/rulesets/<id>` |

**`provider` is not inherited by an import block** from the resource it targets.
Without an explicit `provider = cloudflare.rulesets`, the import read runs
through the default `cloudflare` provider, whose token holds none of the ruleset
permissions — producing the same misleading auth error.

Both are the same failure mode as task 2.1's existing instruction ("verify every
attribute name against the pinned provider — do not copy the plan's illustrative
block blindly"), extended to a surface nobody thought to apply it to: the import
ID, and the provider meta-argument.

## Generalisation still open

Every other `kind = "zone"` ruleset this repo applies has the same exposure and
was never enumerated against its live entrypoint — `seo-rulesets.tf`,
`bot-allowlist.tf`, `cache.tf`, `seo-bulk-redirects.tf`. Tracked in **#6767**,
along with the argument for making the enumeration probe a standing pre-apply
gate rather than a per-plan task someone has to remember to write.
