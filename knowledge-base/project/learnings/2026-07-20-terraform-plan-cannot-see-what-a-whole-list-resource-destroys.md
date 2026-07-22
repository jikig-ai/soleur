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

### The correction that matters more than the trap

The first version of this learning also claimed **"`provider` is not inherited by
an import block"**, and said an explicit `provider = cloudflare.rulesets` was
required. **That is false**, and how it got written is the more useful lesson.

The sequence was: plan fails → add `provider` → plan fails *identically* → find
the real cause (`zones/` → `zone/`) → fix it → plan succeeds. Two changes were in
flight and only one was load-bearing, and the write-up credited both. The
evidence that `provider` changed nothing was already on screen — the second run
produced the same error, and `TF_LOG` showed the request still going to
`/accounts/...`. Nobody looked back at it.

Measured afterwards, both directions:

| experiment | result |
|---|---|
| remove `provider =`, poison the DEFAULT provider's token | plan still succeeds, `1 to import` |
| point the `rulesets` alias at an invalid host, no `provider =` | import read fails on **that** host |

Both show the import block using the target resource's provider. It inherits.

Keep `provider =` for legibility if you like — it is now pinned by a test — but
do not claim it is required. **When two changes are in flight and the symptom
clears, the one that produced no observable change on its own attempt is not part
of the fix.** A confidently-wrong correction is worse than the original gap,
because it is written down and will be mined by whoever hits this next.

Both ID-format traps are the same failure mode as task 2.1's existing instruction ("verify every
attribute name against the pinned provider — do not copy the plan's illustrative
block blindly"), extended to a surface nobody thought to apply it to: the import
ID, and the provider meta-argument.

## Third trap: `mock_provider` does not mock `import` blocks

The adoption fix passed locally and broke CI's `validate` leg, which had nothing
to do with credentials until this change made it about credentials.

`infra-validation.yml` runs `terraform test` against
`tests/web-hosts-eu-pin.tftest.hcl`, whose entire premise is being
credential-free — it declares `mock_provider` for all seven providers so
`command = plan` never touches a real API. Adding an `import` block broke that:

**Terraform performs import reads against the REAL provider even under
`terraform test` with `mock_provider` declared.** The file failed with
`error reading ruleset ID ... Authentication error (10000)` before a single
`var.web_hosts` assertion ran — a credential error in the one job designed not
to need credentials.

Worth noting what the failure concealed: the file reported
`0 passed, 1 failed, 2 skipped`. The two "skipped" runs were real EU-residency
GDPR assertions that silently stopped executing. An import block added anywhere
in a config can therefore switch off unrelated tests elsewhere in the same root.

Fix: gate the import on a bool variable, default `true`, and have the tftest set
it `false`.

```hcl
variable "adopt_seo_config_entrypoint" {
  type    = bool
  default = true
}

import {
  for_each = var.adopt_seo_config_entrypoint ? toset(["adopt"]) : toset([])
  provider = cloudflare.rulesets
  to       = cloudflare_ruleset.seo_config_settings
  id       = "zone/${var.cf_zone_id}/<ruleset_id>"
}
```

**Pinning the default was not enough, and the gap is instructive.** The first
version added a test asserting `default = true` and a comment in three places
saying the test protected the gate. Three reviewers then mutated the *other* end
of it: `for_each = toset([])`, or an inverted ternary, disables the import
entirely while the default still reads `true` and every assertion passes. The
test pinned the variable's declaration; nothing pinned that the import block
*consumed* it. Existence, not effect — and the prose claiming otherwise was
written by the same person who wrote the incomplete test.

Severity, stated accurately rather than dramatically: because the adopted rule is
reproduced verbatim in config, a create-instead-of-import converges on the same
two-rule end state. So a flipped gate is a **drift-overwrite** hazard — any
dashboard edit diverging from the reproduction is silently overwritten — not the
rule-loss outage the original single-rule version would have caused. The defence
that actually matters is having the adopted rule in config; the gate pin is the
second layer.

Worth knowing: the repo's destroy-guard cannot see this either. Its
`cloudflare_ruleset` clause computes `before.rules − after.rules` and keeps only
positive results; on a create `before` is null, so `0 − 2 = −2` is filtered out
and no `[ack-destroy]` prompt fires. A plan-derived guard inherits plan's blind
spot — which is this learning's thesis one level up.

## Generalisation still open

Corrected scope. The other `kind = "zone"` rulesets — `seo_page_redirects`,
`seo_response_headers`, `allowlist_ai_crawlers`, `cache_shared_binaries`,
`bulk_redirects` — are **already in state** (verified with `terraform state
list`), so `plan` refreshes their entrypoints and would surface a
dashboard-added rule as ordinary drift. The blind spot exists only *before* a
resource's first apply. Their exposure is therefore **retrospective** — anything
added to their entrypoints before their own first apply is already gone, silently
— rather than the prospective hazard this file hit.

An earlier version of this learning claimed they had "the same exposure". They do
not, and the difference changes what to do about it: **#6767** is a drift-audit
plus a pre-apply gate for *future* whole-list resources, not a rescue mission for
existing ones. Tracked there,
gate rather than a per-plan task someone has to remember to write.
