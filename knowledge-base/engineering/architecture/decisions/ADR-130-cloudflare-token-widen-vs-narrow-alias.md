---
title: "Widen an existing Cloudflare token within its API family; mint a narrow alias for a distinct API surface"
status: accepted
date: 2026-07-20
issue: 6755
supersedes: null
---

# ADR-130: Cloudflare token widen vs. narrow alias

## Context

`apps/web-platform/infra/main.tf` declares five Cloudflare provider aliases,
each bound to its own token: `default`, `zone_settings`, `rulesets`,
`bot_management`, `r2`. The convention has been "one alias per credential
blast-radius", and each alias comment carries a least-privilege rationale —
`zone_settings` says *"rather than expanding its scope, this alias uses a narrow
token"*, and `r2` (#6649) says the same.

But the file also contains the opposite move: #5092 **widened**
`cf_api_token_rulesets` to add account-level `Account Rulesets:Edit` +
`Account Filter Lists:Edit` for Bulk Redirects.

So two contradictory precedents lived in one file with **no stated rule**. That
gap had a concrete cost. While fixing a GSC "Not found (404)" on
`/cdn-cgi/l/email-protection` (#6746), the plan prescribed a Configuration Rule
in the `http_config_settings` phase. Neither the plan, its 6-agent review panel,
nor `/deepen-plan` noticed that `cf_api_token_rulesets` does not carry the
Configuration-Rules permission. It surfaced only at implementation time, from a
live probe:

| Probe | Result |
|---|---|
| `GET /zones/<zone>/rulesets/phases/http_config_settings/entrypoint` | **403** `request is not authorized` |
| `GET /zones/<zone>/rulesets/phases/http_request_dynamic_redirect/entrypoint` | 200 (control) |

Every other Cloudflare token in Doppler `prd_terraform` was probed against the
same endpoint — all 403. No token holds `User API Tokens:Edit` (all 403 on
`GET /user/tokens`) and there is no Global API Key, so any scope change requires
the Cloudflare dashboard.

## Decision

**A new permission in the SAME API family as an existing alias widens that
alias's token. A permission on a DISTINCT API surface mints a new narrow
alias.**

For the case at hand: Configuration Rules is a ruleset *phase*, reached through
`/zones/<id>/rulesets`, via the same `cloudflare.rulesets` provider alias, on
the same zone, declared as the same `cloudflare_ruleset` resource type as its
three siblings. It is inside the family by construction. Widen.

Two axes decide it, and both must be stated — a rule that carries only the
second always argues for widening, because adding a permission to an existing
token *never* creates a root variable:

**1. Least-privilege (the axis the existing narrow aliases were built on).**
Ask what the marginal capability actually is. `cf_api_token_rulesets` already
carries Single Redirect:Edit (a full traffic-hijack primitive — redirect any
path to attacker infrastructure) and Zone WAF:Edit (a `skip` rule disabling
managed-rule enforcement). An attacker holding this token already owns the
zone's request path. Adding `set_config` grants per-request TLS-mode and
Browser-Integrity-Check downgrade — a real delta, but one that does not change
the terminal outcome. Where the marginal capability *would* change the terminal
outcome, or reaches a different resource class entirely (R2 object storage, zone
settings), mint the narrow alias instead.

**2. The Terraform root-var hazard (the asymmetry that breaks ties).** A new
alias needs a new root variable, and `variables.tf` documents the consequence
verbatim: *an unprovisioned no-default var fails the WHOLE merge-triggered
apply*, because Terraform resolves all root vars **before** `-target` pruning.
Widening moves no secret material — a permission edit does not rotate the token
value — so it needs no variable, no Doppler write, and no stale-secret window.

The failure modes are asymmetric:

| | Widen, token not yet re-scoped at merge | New alias, Doppler secret absent at merge |
|---|---|---|
| Blast radius | One resource 403s | **Nothing applies, for every resource, on every merge** |
| Recovery | Re-scope, re-run — idempotent | Operator must mint a token and write Doppler while `main` is stuck |

Axis 2 makes widening the **default within a family**; axis 1 is what can
override it. If the two conflict, least-privilege wins and the operator accepts
the sequencing cost.

### #5092 is a deviation, not clean supporting precedent

Recorded honestly because it is the precedent this rule leans on hardest and it
does **not** satisfy a naive reading: #5092 widened a zone-scoped token to
**account-level** permissions. Account-level is strictly broader than zone, so
"same zone" is not a load-bearing clause of this rule — "same API family" is,
and #5092 stayed inside the rulesets family while escalating scope. Any future
escalation that crosses zone → account must state that escalation explicitly
rather than treating it as routine.

## Consequences

**Mandatory retained-scope probe after ANY re-scope of a shared token.** Widening
mutates a live credential four production concerns already depend on; a
dashboard edit that *replaces* rather than *appends* scopes silently breaks cache
rules, WAF, single redirects, transform rules, and account bulk redirects at
once. After any re-scope, probe all four and require non-403 (a **404 on an
entrypoint is a pass** — the phase exists with no ruleset yet; only 403 is a
failure):

```bash
TOK=$(doppler secrets get CF_API_TOKEN_RULESETS -p soleur -c prd_terraform --plain)
ZONE=$(doppler secrets get CF_ZONE_ID -p soleur -c prd_terraform --plain)
ACCT=$(doppler secrets get CF_ACCOUNT_ID -p soleur -c prd_terraform --plain)
for u in \
  "zones/$ZONE/rulesets/phases/http_config_settings/entrypoint" \
  "zones/$ZONE/rulesets/phases/http_request_dynamic_redirect/entrypoint" \
  "zones/$ZONE/rulesets/phases/http_request_cache_settings/entrypoint" \
  "accounts/$ACCT/rulesets"; do
  printf '%s -> ' "$u"
  curl -sS -o /dev/null -w '%{http_code}\n' -H "Authorization: Bearer $TOK" \
    "https://api.cloudflare.com/client/v4/$u"
done
```

**Probe, never trust the permission label.** The Cloudflare UI names this
permission inconsistently across surfaces. Probe 1 returning non-403 is the
ground truth.

**A `kind = "zone"` ruleset OWNS its phase entrypoint.** Entrypoint management is
whole-list replacement, and `terraform plan` reports "1 to add" purely because
the resource is absent from *state* — it cannot see dashboard-created rules.
Before the first apply of a ruleset in a **new** phase, enumerate that phase's
entrypoint and confirm it is 404 or empty, or the apply silently deletes
dashboard-created rules.

**When the entrypoint is NOT empty, adopt it — both halves.** This probe fired on
its first real run (#6767): `http_config_settings` on soleur.ai already held a
dashboard-created rule (`"Flexible SSL for web platform"`, `app.soleur.ai`,
`set_config { ssl = "flexible" }`). The remedy is:

1. reproduce the live rule verbatim as a `rules` block — including `ref`, which
   is how the v4 provider preserves rule IDs across a whole-list PUT; and
2. adopt the ruleset with an `import` block so Terraform **updates** rather than
   creates.

Neither half suffices alone: (1) without (2) still creates and clobbers; (2)
without (1) still deletes the rule on the next plan. Import ID on provider v4 is
`zone/<zone_id>/<ruleset_id>` — **singular**; the plural `zones/` shown in the
provider's `main`-branch docs is v5 and silently routes to the account path,
reporting `Authentication error (10000)`. `for_each` on an import block requires
Terraform **>= 1.7**. Expected plan shape afterwards is
`N to import, 0 to add, 1 to change, 0 to destroy`; a plan still reporting
"1 to add" means the import block was dropped.

**Detection is not covered by the destroy-guard.** `destroy-guard-filter-web-platform.jq`
counts `before.rules − after.rules` and keeps only positive results. On a create
`before` is null, so the difference is negative and filtered out — no
`[ack-destroy]` prompt fires. A plan-derived guard inherits plan's blind spot,
which is precisely why the pre-apply enumeration above is a *probe* and not a
CI gate. **Making it a gate: DONE — see ADR-136** (#6767 shipped the standing
fail-closed pre-apply entrypoint-enumeration gate + a retrospective drift
audit). This ADR's manual enumeration remains the `/work`-time pre-*write* check
when authoring a new phase; ADR-136 is the pre-*apply* automated control.

**`variables.tf` descriptions are the scope ledger.** The whole gap existed
because the ledger was accurate and nothing read it against the new phase. A new
ruleset phase needs a matching permission in the ledger AND on the live token.
Do not maintain a competing enumeration elsewhere — `main.tf`'s alias comment
had already drifted two phases behind, and now points at the ledger instead.

**Capability gap (not closed by this ADR).** There is no first-party skill for
Cloudflare token scope changes. `soleur:provision-cloudflare` mints *tenant*
tokens via the `cloudflare_api_token` resource, which itself requires
`User API Tokens:Edit` — a permission no Soleur token holds. So every
first-party scope change is an ad-hoc dashboard trip; this is the third on
record (#6657 DNS, #6649 R2, #6755 Config Rules). A Playwright-driven
`soleur:cf-token-scope` skill that performs the widen and runs the probe set
above would turn this class into a two-minute automated step.

## Alternatives considered

**Mint `cf_api_token_config_rules` as a narrow alias.** Rejected: it would create
a second credential and a second provider alias pointed at the *same endpoint
family on the same zone* as an alias that already exists — alias sprawl for a
security delta near zero (see axis 1), while paying the repo's most expensive
documented hazard (axis 2). It also does not save the operator a dashboard trip;
no token can mint via API, so both options require one, and the narrow alias
additionally requires a Doppler write and a `doppler_secret` republish.

**Give the new variable a `default = ""` plus a resource `precondition`,** so an
unprovisioned secret fails one resource instead of the whole apply. This would
genuinely defuse axis 2 and make least-privilege cheaper. Not adopted here
because it collides with hard rule `hr-tf-variable-no-operator-mint-default`.
Worth revisiting as a deliberate change to that rule rather than as a side
effect of a GSC fix — the Terraform limitation is being worked around, not
accepted as a law.

**Disable Email Obfuscation zone-wide** via `cloudflare_zone_settings_override`
(which uses a different alias whose token already has the scope, avoiding the
token question entirely). Rejected on blast radius: it would also strip
obfuscation from `app.`/`deploy.`/`api.`, which serve no marketing copy. Buying
our way out of a credential-scope decision with unnecessary production scope is
the wrong trade.

**Cloudflare's `<!--email_off-->` markup opt-out**, avoiding the edge entirely.
Rejected: 70 email addresses across 8 legal markdown files plus two `.njk`
pages, and every future address silently regresses the bug. A per-occurrence fix
with a permanent regression footgun, maintained by a solo non-technical
operator, is worse than one host-scoped rule.
