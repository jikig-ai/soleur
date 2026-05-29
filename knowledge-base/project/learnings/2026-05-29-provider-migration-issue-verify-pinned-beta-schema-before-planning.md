# Learning: A deprecated→new resource migration issue must be schema-verified against the PINNED (beta) provider before planning the migration

## Problem

Issue #4610 asked to migrate 4 deprecated `sentry_issue_alert.*` Terraform
resources to the unified `sentry_alert` resource (jianyuan/sentry, pinned at
`v0.15.0-beta2`). The issue read as a routine deprecation-cleanup chore: the
provider emits "This resource is deprecated. Please migrate to `sentry_alert`"
on every `validate`/`plan`, and the issue prescribed a clean 4-step plan
(migrate blocks → `terraform state mv` → update audit script → `plan` shows 0
changes + 0 warnings).

Taking the issue at face value would have produced a broken migration: a forced
recreate that **drops the live auth paging rules**.

## Root Cause

The provider's deprecation message is **forward-looking to the GA schema**, not
a claim that the *current beta* supports the migration. A `terraform providers
schema -json` dump of the installed `v0.15.0-beta2` binary proved the target
resource is incompatible in this version:

- `sentry_alert` (beta2) is **monitor-bound**: `monitor_ids` (set) and
  `trigger_conditions` (`first_seen|regression|reappeared|issue_resolved`) are
  BOTH required, and it has **no `project` attribute**.
- The 4 auth rules are **project-wide frequency alerts**
  (`EventFrequencyCondition` + `TaggedEventFilter`) bound to no monitor — there
  is no faithful value for the required fields.
- `terraform state mv` across the two types is impossible: the schemas share
  only `name`/`organization`/`id`, so the move leaves every routing attribute
  unconfigured and the required `monitor_ids` unsatisfiable.

The issue's claim (4) was also internally contradictory under the pin: killing
the deprecation warning requires *removing* the deprecated type, which requires
a recreate (≠ 0 changes). "0 changes AND 0 warnings" is mutually exclusive
until provider GA. ADR-031 had **already deferred this exact migration "until
provider GA"** — #4610 overrode that defer without new schema information.

## Solution

The honest, only-safe-under-the-pin resolution was **document the accepted
posture**, not migrate:

1. Add a header comment block to `issue-alerts.tf` explaining the deprecation
   warning is accepted until provider GA, with the schema rationale.
2. Add a dated amendment to ADR-031 re-confirming the defer at beta2.
3. `terraform validate` continues to exit 0 with the (now-documented) warning.

No state mutation, no recreate, no dropped paging rules. The user was given the
fork (ship docs-only / defer-no-PR / verify schema first) via `AskUserQuestion`
before the pipeline committed to an outcome — the autonomous pipeline correctly
*paused* on a "the requested work is impossible as written" finding rather than
barreling ahead to ship a forced migration.

## Key Insight

**When an issue requests migrating a deprecated dependency/provider resource to
its replacement, verify the replacement's schema in the PINNED version before
planning the migration — especially when the pin is a beta/pre-release.** The
upstream "migrate to X" deprecation pointer presumes the GA schema; a beta X
can be stricter or structurally disjoint, making the migration impossible
without data loss.

- Canonical evidence is `terraform providers schema -json` against the
  *installed binary* (via `dev_overrides` if backend init is offline) — NOT
  registry docs or Context7, which return the latest/GA schema, not the pin.
- A pre-existing ADR that already deferred the same work is a strong signal:
  re-confirm the defer with fresh evidence rather than silently overriding it.
- "Deprecation warning present" ≠ "migration available now." Accepting and
  documenting a forward-deprecation warning is a legitimate terminal state when
  the replacement schema isn't ready.

This generalizes beyond Terraform: any "upgrade to the non-deprecated API"
chore (npm major bumps, deprecated SDK methods, beta GraphQL fields) should
verify the replacement against the *pinned* version's actual surface before
committing to a migration plan.

## Session Errors

1. **Planning-environment Task fan-out unavailable** — plan-review + domain-leader subagents could not be spawned in the planning subagent's context. Recovery: schema evidence gathered inline via the binary schema dump (arguably stronger than agent summaries for a schema-fact question); the one-shot review phase ran the reviewers normally. Prevention: already mitigated — one-shot's review step runs the reviewers regardless of the planning environment.
2. **PreToolUse IaC-routing-gate false-positive** on plan prose describing "operator runs" (what NOT to do). Recovery: documented `iac-routing-ack` opt-out after confirming zero new infrastructure. Prevention: already covered by the documented opt-out mechanism.
3. **Benign `ZSH_VERSION: unbound variable`** shell-snapshot warning on one Bash call. Recovery: none needed (output unaffected). Prevention: environment noise, not actionable.

## Tags
category: integration-issues
module: apps/web-platform/infra/sentry
related: ADR-031-sentry-as-iac, "#4610", 2026-05-15-terraform-import-only-beta-provider-schema-validation
