---
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
related_prs: ["#4290", "#4508"]
related_issues: ["#4364", "#4232"]
---

# Sentry BYOK Alert Rules — Implementation Plan

**Date:** 2026-05-30
**Status:** Deepened
**Author:** soleur:plan + soleur:deepen-plan (one-shot)
**Issue:** #4364 (de-deferred; original deferral premise invalid)

## Problem Statement

PR-A (#4290, MERGED) shipped `byok-delegations` observability events to Sentry.
The emitter is **`emitDelegationEvent(...)` in `apps/web-platform/server/cost-writer.ts`**
(lines 131-160 — verified this session; NOT `src/lib/observability/...` — this
repo has no `src/` tree, and the issue body + one-shot brief both cite a wrong
path). It emits a Sentry event on every cross-tenant / cap-exceeded path,
carrying these **tags** (set via `scope.setTag(...)`):

- `feature = "byok-delegations"` (cost-writer.ts:136, every event)
- `op = cross-tenant-violation | hourly-cap-exceeded | daily-cap-exceeded | …`
  (cost-writer.ts:137)
- `art_33_breach = "true"` (string, set ONLY on `op === "cross-tenant-violation"`,
  cost-writer.ts:140-141)

Levels (`scope.setLevel`, cost-writer.ts:142-146): cross-tenant-violation →
`fatal`; hourly-cap-exceeded / daily-cap-exceeded → `warning`; else → `info`.
The function docstring (cost-writer.ts:123-130) explicitly says it is tagged
"so the Sentry alert rules from issue #4364 can route on them" — confirming this
plan is the intended consumer.

There are **no alert rules** routing those events to a human. A cross-tenant
violation starts the GDPR Art. 33 72-hour breach-notification clock, yet today
it lands silently in the unrouted Sentry issue stream. This is both an
observability gap (`hr-observability-as-plan-quality-gate`) and a compliance gap
(`hr-gdpr-gate-on-regulated-data-surfaces`).

The issue's original deferral (Sentry alert actions are "UI-only" / "no Sentry
MCP server") was **invalidated** by the maintainer comment 2026-05-30: Sentry
issue-alerts are fully API-settable (conditions + filters + actions), which the
existing terraform root already proves (the 4 auth `sentry_issue_alert`
resources). The re-eval trigger (PR-B #4508 merged) is satisfied.

## Research Reconciliation — Brief vs. Codebase

The one-shot brief and the issue body carry several stale premises. **The brief
explicitly instructed: "CHECK and prefer extending the existing
`apps/web-platform/infra/sentry/` terraform over a new bespoke script."** That
check changes the plan's central decision — the brief's own fallback preference
(a TS script) is wrong because the terraform root already exists.

| Brief / issue claim | Codebase reality (verified 2026-05-30) | Plan response |
|---|---|---|
| Emitter at `web-platform/src/lib/observability/byok-delegation-events.ts` | Emitter at `apps/web-platform/lib/byok/delegation-events.ts`; no `src/` tree | Cite the real path; tag values read from it directly |
| Org slug `jikigai` | Org slug is **`jikigai-eu`** (EU cluster); `variables.tf` desc + `.env.example` `SENTRY_ORG=jikigai-eu`; provider `base_url = https://de.sentry.io/api/` (`main.tf`) | Use `var.sentry_org` / `var.sentry_project` — never a hardcoded slug |
| API host `sentry.io` | EU host `de.sentry.io` (`main.tf` provider `base_url`) | Inherited automatically via the existing provider block; no change |
| "prefer extending existing terraform **if present**" | `apps/web-platform/infra/sentry/` **IS present**: `main.tf`, `issue-alerts.tf` (4 `sentry_issue_alert` resources), `cron-monitors.tf`, `uptime-monitors.tf`, `variables.tf`, `versions.tf`, `.terraform.lock.hcl`, R2 backend, ADR-031, README, auto-apply workflow | **Extend the terraform root.** Add 2 `sentry_issue_alert` resources to `issue-alerts.tf`. Do NOT write a TS script. |
| `SENTRY_AUTH_TOKEN` in **Doppler** (`alerts:write`+`project:read`) | Token lives in **GitHub repo secrets** for the sentry root (README §Authentication: "Sentry secrets live in GitHub repository secrets", NOT Doppler `prd_terraform`). Only the R2 backend creds come from Doppler. | Correct the auth model: no Doppler `SENTRY_AUTH_TOKEN` needed; the existing `apply-sentry-infra.yml` already wires `secrets.SENTRY_AUTH_TOKEN`. Operator prerequisite is "the GitHub repo secret already exists" (it does — the 4 auth rules + cron monitors apply with it). |
| Idempotency = re-runnable POST that dedups | Idempotency = terraform state (declarative). Sentry POST `/rules/` dedup quirk (learning `2026-05-17`) still applies at **create** time → must give the 2 new rules **distinct `frequency`** from each other AND from the 4 existing auth rules (60/61/62/30 are taken) | Use `frequency = 5` (Rule 1) and `frequency = 15` (Rule 2) — distinct from the taken set and from each other; record rationale inline |

## User-Brand Impact

**If this lands broken, the user experiences:** a cross-tenant BYOK key leak
(one operator's Anthropic key used to serve another tenant) goes unnoticed
because no alert fires — the founder discovers it only when a customer reports it,
blowing the GDPR Art. 33 72-hour clock and the brand's "your key never touches
another tenant" promise.
**If this leaks, the user's data / workflow / money is exposed via:** the
`cross-tenant-violation` event sits in the unrouted Sentry stream; the BYOK API
key (the user's money — they pay Anthropic directly) and the cross-tenant
inference it enabled are the exposure surface. The alert rule is the detection
control, not the prevention control (prevention is `cross-tenant-guard.ts` from
PR-A); this plan closes the detection gap.
**Brand-survival threshold:** single-user incident.

Per `2026.05` plan Phase 2.6: threshold = `single-user incident` →
`requires_cpo_signoff: true` (frontmatter). CPO sign-off required at plan time
before `/work`; `user-impact-reviewer` invoked at review-time (review/SKILL.md
conditional-agent block). Note: this PR ships only the **routing rule** for an
already-emitted event; the brand-survival blast radius is bounded by PR-A's
emitter correctness, which is out of scope here.

## Goals

1. **Rule 1 (Art. 33 breach):** a `sentry_issue_alert` matching
   `feature = byok-delegations AND art_33_breach = true` → high-urgency action
   shape, distinct from the 4 existing auth rules and from Rule 2.
2. **Rule 2 (cap-exceeded):** a `sentry_issue_alert` matching
   `feature = byok-delegations AND op IN {hourly-cap-exceeded, daily-cap-exceeded}`
   → lower-severity action shape, distinct from Rule 1.
3. Both as **committed terraform** in the existing IaC root, applied via the
   existing `apply-sentry-infra.yml` auto-apply-on-push workflow — reproducible
   and drift-guarded, no bespoke imperative script.

## Non-Goals

- A TS provisioning script (the brief's fallback) — terraform root supersedes it.
- Rules for `revoke-past-grace` / `expired` — not in #4364 acceptance criteria.
- Migrating the existing 4 `sentry_issue_alert` resources to `sentry_alert`
  (deferred until provider GA #4610 per ADR-031 — see issue-alerts.tf docblock).
- Provisioning/rotating the `SENTRY_AUTH_TOKEN` GitHub repo secret (already
  exists; the 4 auth rules + cron/uptime monitors apply with it).
- Changing the prevention control (`cross-tenant-guard.ts`).

## Proposed Solution

Add **two `sentry_issue_alert` resources** to
`apps/web-platform/infra/sentry/issue-alerts.tf`, following the exact shape of
the 4 existing auth rules but — critically — these are **NOT import-only**.
The 4 auth rules are import-only (created by the legacy script, then imported,
with `conditions_v2 = [] / filters_v2 = []` placeholders under
`lifecycle.ignore_changes`). The 2 new BYOK rules have **no pre-existing Sentry
rule to import** — terraform must CREATE them from real `conditions_v2` +
`filters_v2` + `actions_v2`. This is the apply-creates-fresh path that learning
`2026-05-17` warns about: give each a unique `frequency` so Sentry's POST-time
"exact duplicate" dedup does not conflate them.

### Why terraform, not a script (precedent-diff)

`git grep -l sentry_issue_alert apps/web-platform/infra/sentry/` →
`issue-alerts.tf` (4 resources). ADR-031 codifies "Sentry alert and cron monitor
configuration as IaC." The auto-apply workflow already exists. A bespoke TS
script would be a parallel, un-drift-guarded source of truth for the same
resource class — a net regression against the established pattern. **No novel
pattern: the canonical form is `sentry_issue_alert` in this file.**

## Technical Design

### Verified facts (this session)

| Fact | Source | Verified |
|---|---|---|
| Terraform sentry root exists; `sentry_issue_alert` is the resource type | `apps/web-platform/infra/sentry/issue-alerts.tf` | yes |
| Provider `jianyuan/sentry` pinned `0.15.0-beta2` | `versions.tf` + `.terraform.lock.hcl` | yes |
| Org/project via `var.sentry_org` / `data.sentry_project.web_platform.slug`; EU host | `main.tf`, `variables.tf` | yes |
| Tag keys/values `feature`/`op`/`art_33_breach` and exact literals | `server/cost-writer.ts:136-141` | yes |
| Tags emitted via `scope.setTag` (→ matchable by TaggedEventFilter) | `server/cost-writer.ts:136,137,141` | yes |
| Create-time POST dedup keys on action-shape+frequency+match, not conditions | learning `2026-05-17-sentry-issue-alert-create-dedup-on-action-match-not-conditions.md` | yes |
| Existing rule frequencies 60/61/62/30 (must avoid for dedup) | `issue-alerts.tf` | yes |
| Auth token = GitHub repo secret, NOT Doppler | `infra/sentry/README.md` §Authentication | yes |
| Auto-apply workflow exists; issue-alerts currently `-target`-excluded | `.github/workflows/apply-sentry-infra.yml` | yes |
| Provider deprecation warning on `sentry_issue_alert` is EXPECTED/accepted to GA | `issue-alerts.tf` docblock + ADR-031 | yes |

### Sentry issue-alert registry id strings (v0.15.0-beta2 `conditions_v2`/`filters_v2`/`actions_v2`)

The new resources use the v2 attribute set (objects, not the legacy JSON `id`
strings). **DEEPEN-PLAN OPEN ITEM (must resolve at /work Phase 0 via
`terraform providers schema -json` against the pinned beta2 — do NOT trust
memory of the v2 nested-attribute names):** confirm the beta2 attribute names for

- the "every event" / "first seen" **condition** under `conditions_v2`,
- the **tagged-event filter** under `filters_v2` (key/match/value; and whether
  `match = "is_in"` is supported for the comma/newline list, else fall back to
  two `eq` filters with `filter_match = "any"`),
- the **notify action** under `actions_v2` (the existing rules use
  `notify_email { target_type / fallthrough_type }`; confirm whether a
  Slack/PagerDuty integration action object is available on the org — if not,
  `notify_email` is the always-available distinct fallback).

Schema-verify-before-write is mandatory here per learning
`2026-05-15-terraform-import-only-beta-provider-schema-validation.md`:
`ignore_changes` runs at plan-phase but the provider's per-attribute schema
validation runs at config-phase and will reject a malformed `conditions_v2` /
`filters_v2` element regardless. Write the **minimum body that passes
`terraform validate`** for the create path.

### Distinctness (satisfies both acceptance criteria)

The two rules are distinct on THREE axes, so neither Sentry's create-time dedup
nor a reviewer can confuse them:

1. **Filters differ:** Rule 1 filters `art_33_breach = true`; Rule 2 filters
   `op IN {hourly-cap-exceeded, daily-cap-exceeded}`.
2. **Frequency differs:** Rule 1 `frequency = 5` (tight — every Art. 33 event
   matters); Rule 2 `frequency = 15` (throttle noisy cap events). Both distinct
   from the existing 60/61/62/30.
3. **Action shape differs (severity):** Rule 1 high-urgency target; Rule 2
   lower-urgency target. Minimum-viable distinct fallback if no integration
   exists on the org: both `notify_email`, still distinct via filters+frequency
   (no default route filters on these tags, so both are distinct from default
   routes too — the AC wording).

### Files to Edit

- `apps/web-platform/infra/sentry/issue-alerts.tf` — **add 2 resources**
  (`byok_art_33_breach`, `byok_cap_exceeded`). These are CREATE resources with
  real `conditions_v2`/`filters_v2`/`actions_v2` (NOT import-only); no
  `ignore_changes` on conditions/filters (we own them as IaC truth) — but DO
  keep `ignore_changes = [environment]` if the provider recomputes it.
- `.github/workflows/apply-sentry-infra.yml` — **add two `-target=` flags** to
  the apply step: `-target=sentry_issue_alert.byok_art_33_breach` and
  `-target=sentry_issue_alert.byok_cap_exceeded`. The existing apply is
  `-target`-scoped to cron + uptime monitors precisely because the 4 auth rules
  are import-only and an untargeted apply would 412 on them. The 2 BYOK rules
  ARE apply-creatable, so they must be added to the target set or the workflow
  will never create them. **Sharp edge:** leaving them out of the target set is
  a silent no-op (the resources exist in config but apply never reaches them).
- `apps/web-platform/infra/sentry/README.md` — document the 2 new rules in the
  resource inventory ("4 issue alerts" → "6 issue alerts; 4 import-only auth +
  2 apply-created BYOK") and note they are NOT import-only.

### Files to Create

None (extends existing files).

## Implementation Steps

1. **Phase 0 (schema verify — mandatory):** `cd apps/web-platform/infra/sentry &&
   terraform init -input=false` then `terraform providers schema -json |
   jq '.provider_schemas[].resource_schemas.sentry_issue_alert'` to read the
   exact beta2 `conditions_v2`/`filters_v2`/`actions_v2` nested-attribute names
   and the `match` enum (confirm `is_in` support). Pin the output in the work log.
2. Add the 2 resources to `issue-alerts.tf` with verified v2 attribute shapes,
   distinct frequencies (5, 15), and the tag filters from the verified contract.
3. Add the 2 `-target=` flags to `apply-sentry-infra.yml`.
4. Update `README.md` inventory.
5. `terraform fmt` + `terraform validate` (expect the accepted deprecation
   warning; no errors). Capture `terraform plan` output (will show 2 to add) —
   run with the GitHub-secret token locally OR rely on CI plan if no token.
6. Merge → `apply-sentry-infra.yml` fires on push (path-filtered to
   `infra/sentry/**`), creates the 2 rules. Verify post-merge via the workflow
   run log (the apply prints "2 added").

## Testing Strategy

- **`terraform validate`** in `infra/sentry/` — config-phase schema check passes
  (the load-bearing gate for beta2; catches malformed v2 attributes).
- **`terraform plan`** shows exactly `2 to add, 0 to change, 0 to destroy`
  (re-run idempotency: a second plan after apply shows `0 to add` — declarative
  idempotency, the terraform analogue of the script's GET-diff).
- **No vitest** — this is IaC, not app code; the existing repo has no terraform
  unit-test harness for the sentry root (the 4 auth rules ship without one).
  The drift guard is `terraform plan` in CI, consistent with the established
  pattern.
- **Post-apply functional check (read-only, no synthetic prod data):** the
  discoverability test below — GET the rules via the Sentry API and assert both
  exist with the expected filters. Does NOT emit a synthetic `art_33_breach`
  event (would create a fake GDPR breach record — `hr-dev-prd-distinct...`).

## Observability

```yaml
liveness_signal:
  what: "apply-sentry-infra.yml workflow run on push to main touching infra/sentry/**"
  cadence: "on every merge that changes infra/sentry/ (path-filtered push trigger)"
  alert_target: "GitHub Actions run status; failure surfaces in the Actions tab + the existing apply-sentry-infra concurrency group"
  configured_in: ".github/workflows/apply-sentry-infra.yml"
error_reporting:
  destination: "GitHub Actions job log (terraform apply non-zero exit fails the job loudly)"
  fail_loud: "terraform apply -auto-approve exits non-zero on create failure → workflow run marked failed; no silent swallow"
failure_modes:
  - mode: "v2 attribute schema rejected by beta2 provider at config-phase"
    detection: "terraform validate / plan errors in CI before apply"
    alert_route: "apply-sentry-infra.yml job failure"
  - mode: "create-time POST dedup 412 (frequency collision with existing rule)"
    detection: "terraform apply error 'exact duplicate of <rule>'"
    alert_route: "apply-sentry-infra.yml job failure; mitigated by distinct frequency 5/15"
  - mode: "resource added to config but omitted from -target set (silent no-op)"
    detection: "terraform plan in CI shows the resource as still-to-create after a merge that should have created it"
    alert_route: "post-merge plan drift; covered by adding both -target flags (Files to Edit)"
  - mode: "rule created but routes nowhere (action target wrong/empty)"
    detection: "discoverability_test below GETs the rule and asserts actions array non-empty"
    alert_route: "manual post-apply check (read-only API GET)"
logs:
  where: "GitHub Actions run logs for apply-sentry-infra.yml"
  retention: "GitHub default (90 days for Actions logs)"
discoverability_test:
  command: "curl -s -H \"Authorization: Bearer $SENTRY_AUTH_TOKEN\" \"https://de.sentry.io/api/0/projects/$SENTRY_ORG/$SENTRY_PROJECT/rules/\" | jq '[.[] | select(.name | test(\"BYOK\"))] | length'"
  expected_output: "2 (both BYOK issue-alert rules present after apply); NO ssh required"
```

## Risks and Mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| beta2 v2 attribute names differ from memory | config-phase validate error | Phase 0 `terraform providers schema -json` before writing — mandatory; do not guess |
| `match = "is_in"` unsupported in beta2 filter | Rule 2 rejected | Fallback: `filter_match = "any"` + two `eq` filters (one per cap op) — documented in design |
| frequency collision with existing 60/61/62/30 | create-time 412 dedup | Use 5 and 15 (distinct from taken set AND each other) per learning 2026-05-17 |
| resource added to config but not to `-target` set | silent no-op; rule never created | Add both `-target` flags to apply-sentry-infra.yml (Files to Edit) + plan-drift detection (Observability) |
| accidental untargeted `terraform apply` | would try to create the 4 import-only auth rules (412) | The workflow stays `-target`-scoped; never run untargeted apply on this root (README warns) |
| action target lands on `notify_email` only (no integration) | both rules route to issue-owners mail, not a high-urgency channel | Acceptable minimum: still distinct + still distinct-from-default-route (AC met). Upgrade to integration action if one exists on the org (Phase 0 schema also lists available action objects) |
| SENTRY_AUTH_TOKEN repo secret scope insufficient (needs project:write for create) | apply 403 | README states the token has project:write for apply; the cron/uptime monitors already create with it → scope is sufficient. Genuine prerequisite, already satisfied. |

## Domain Review

**Domains relevant:** Engineering, Legal/Compliance, Product

### Engineering (CTO)
**Status:** reviewed (carry-forward from brief + this session)
**Assessment:** Extend existing IaC root; no new toolchain. The only non-obvious
correctness items are (a) NOT import-only (must supply real v2 conditions/filters
for the create path), (b) `-target` set must include the 2 new rules, (c) beta2
schema-verify-before-write. All captured in Files to Edit + Risks.

### Legal/Compliance (CLO)
**Status:** reviewed (carry-forward)
**Assessment:** This is the detection control for a GDPR Art. 33 breach class.
`/soleur:gdpr-gate` (Phase 2.7) applies because the plan touches a regulated-data
observability surface (cross-tenant key exposure). Advisory: the alert is
necessary-but-not-sufficient for the 72h clock — the runbook that consumes the
alert (operator notification within 72h) is a separate artifact; this PR only
guarantees the signal reaches a human. No new processing activity (the event is
already emitted by PR-A); no Art. 30 register change.

### Product/UX Gate
**Tier:** none
**Decision:** N/A — no user-facing surface (infra-only change; the "user" of the
alert is the operator/founder via Sentry, not an app UI).

## Open Questions

- **Action target severity:** does the `jikigai-eu` org have a Slack/PagerDuty
  integration whose action object beta2 exposes? Resolve at Phase 0 via
  `terraform providers schema` (action object list) + a one-time read of org
  integrations. If none, `notify_email` is the agreed distinct fallback.
- **`is_in` filter support in beta2** vs the two-`eq`-with-`filter_match=any`
  fallback for Rule 2's cap-op set — resolve at Phase 0.
- Should the 2 new rules also get a `lifecycle.ignore_changes = [environment]`?
  The 4 auth rules ignore it because import recomputes it; for the create path it
  may not drift. Decide at Phase 0 from the plan output (if `environment` shows
  perpetual drift, add it).
