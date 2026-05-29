<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
---
title: "refactor: Migrate sentry_issue_alert → sentry_alert (jianyuan/sentry v0.15.0-beta2)"
issue: 4610
type: refactor
classification: infrastructure-iac
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
date: 2026-05-29
branch: feat-one-shot-4610-sentry-alert-migration
spec: none (no spec.md authored for this branch — plan is source of truth)
---

# refactor: Migrate `sentry_issue_alert` → `sentry_alert` (#4610)

## Enhancement Summary

**Deepened on:** 2026-05-29
**Method:** Inline (Task subagent fan-out unavailable in this environment). Core
evidence is a direct `terraform providers schema -json` dump of the installed
`terraform-provider-sentry_v0.15.0-beta2` binary — stronger than Context7/registry
docs, which return latest (potentially GA) schema, not the pinned beta.

### Key findings (deepen-pass, re-verified against the binary)
1. `sentry_alert.monitor_ids.required == true`, `sentry_alert.trigger_conditions.required == true`, `sentry_alert` has **no `project` attribute**, `sentry_issue_alert.block.deprecated == true`. All four re-confirmed via the schema JSON.
2. The migration #4610 describes is **not faithfully expressible** in beta2 — `sentry_alert` is a monitor-bound alert; the auth rules are project-wide frequency alerts. This is the load-bearing finding; the rest of the plan follows from it.
3. Claim (3) "update the audit script" is a verified **no-op** (0 resource-type strings in either audit file).
4. Mechanical deepen gates pass: 4.6 User-Brand Impact (single-user incident), 4.7 Observability (5 fields, no SSH in discoverability test), 4.8 no PAT-shaped variables. 4.4 scheduled-work N/A (no cron introduced). 4.5 network-outage N/A (no SSH/provisioner surface).

### Precedent-Diff (Phase 4.4)
Sibling precedent for "beta-provider import-only resource shape" is
`knowledge-base/project/learnings/2026-05-15-terraform-import-only-beta-provider-schema-validation.md`
(PR #3811) — it established that `lifecycle.ignore_changes` does NOT mask
config-time validation, and that auto-apply workflows must be `-target=`-scoped
to create-not-import resources. This plan's Option A is fully consistent: it adds
no resource, mutates no state, and touches no `-target=` allow-list. **No novel
pattern is introduced** — the recommended path is the strict status-quo-plus-docs.

### New consideration discovered during deepen
- The two halves of #4610 claim (4) ("0 changes AND 0 deprecation warnings") are **mutually exclusive** under the beta pin: 0 deprecation warnings requires removing the deprecated resource type, which requires a recreate (non-zero changes + drops live paging). This is the single most important thing for the user/CPO to weigh before `/work`.

## ⚠️ Decision Headline (read first)

The migration as literally framed in #4610 is **NOT mechanically possible** against
the pinned provider `jianyuan/sentry` v0.15.0-beta2. The schema dump (canonical,
extracted from the installed binary — see Research Reconciliation) proves the
target resource `sentry_alert` is a **monitor-bound** alert in this beta, not a
drop-in replacement for project-wide issue-alert rules:

- `sentry_alert.monitor_ids` is **required** (`set(string)`, "The IDs of the
  monitors to create alerts for"). The 4 `auth-*` rules are project-wide
  frequency alerts bound to **no monitor** — there is no value to put here.
- `sentry_alert.trigger_conditions` is **required** and exposes only
  `first_seen_event | issue_resolved_trigger | reappeared_event |
  regression_event`. The auth rules' triggers are
  `EventFrequencyCondition` / `EventUniqueUserFrequencyCondition` — these live
  under `action_filters[].conditions.event_frequency_count` /
  `event_unique_user_frequency_count` in `sentry_alert`, NOT under
  `trigger_conditions`. A `sentry_alert` with an empty/synthetic
  `trigger_conditions` would fire on a *different event class* than the auth
  rules do today.
- `sentry_alert` has **no `project` attribute**; `sentry_issue_alert` requires
  `project`. The two state shapes are disjoint.

`terraform state mv sentry_issue_alert.X sentry_alert.X` is therefore impossible:
`state mv` across resource types requires schema-compatible state, and these two
schemas share **zero** addressable attributes beyond `name`/`organization`/`id`.
Terraform would reject the moved state at the next plan (every attribute would
read as "unconfigured / unknown"), and even if forced, the required
`monitor_ids` could never be satisfied.

**This plan's recommended path is Option A (document-the-blocker + suppress the
warning at source) — it ships the only 0-changes / 0-net-new-risk outcome
available under the beta pin.** Options B and C are recorded for the GA
re-evaluation. The final choice is gated on CPO sign-off (single-user-incident
threshold — these are the auth paging rules).

## Overview

`apps/web-platform/infra/sentry/issue-alerts.tf` declares 4 import-only
`sentry_issue_alert` resources (`auth_exchange_code_burst`,
`auth_callback_no_code_burst`, `auth_per_user_loop`, `auth_signout_burst`) that
mirror the auth-observability paging rules created by
`apps/web-platform/scripts/configure-sentry-alerts.sh`. As of v0.15.0-beta2 the
provider marks `sentry_issue_alert` **deprecated** and emits a warning on every
`terraform validate` / `plan` (reproduced below). ADR-031 explicitly **deferred**
this migration "until provider GA". #4610 asks to do it now.

The investigation (schema dump + deprecation-message read + source-rule mapping)
shows the beta `sentry_alert` cannot represent these rules. The deprecation
pointer in the provider (`Please migrate to sentry_alert`) is **forward-looking**
— it presumes the GA `sentry_alert` schema, which may differ from beta2's
monitor-bound shape (the resource itself is flagged "currently in beta and may
be subject to change").

### Reproduction (current state — captured 2026-05-29)

```text
$ cd apps/web-platform/infra/sentry && terraform validate
Warning: Deprecated
  with sentry_issue_alert.auth_exchange_code_burst,
  on issue-alerts.tf line 16 ...
  This resource is deprecated. Please migrate to `sentry_alert` resource instead.
(and 3 more similar warnings elsewhere)
Success! The configuration is valid, but there were some validation warnings.
$ echo $?   # 0
```

## Research Reconciliation — Spec vs. Codebase

| #4610 claim | Codebase / provider-schema reality | Plan response |
|---|---|---|
| "(1) migrate each `sentry_issue_alert.<name>` to `sentry_alert`, mapping conditions/filters/actions/frequency to the new schema" | `sentry_alert` (beta2) is **monitor-bound**: requires `monitor_ids` (set, required) + `trigger_conditions` (required, only first_seen/regression/reappeared/issue_resolved). Auth rules are project-wide `EventFrequencyCondition`/`EventUniqueUserFrequencyCondition` with `TaggedEventFilter` — these map to `action_filters[].conditions.event_frequency_count`/`event_unique_user_frequency_count` + `tagged_event`, but the **required** `monitor_ids` and `trigger_conditions` have no faithful value. | **Blocker.** Migration is not faithfully expressible in beta2. Recommend Option A (suppress/document warning at source, keep `sentry_issue_alert` until GA). Re-attempt at GA when `sentry_alert` schema stabilizes. |
| "(2) re-state via `terraform state mv` … NEVER recreate" | `state mv` across resource types requires schema-compatible state. `sentry_issue_alert` and `sentry_alert` share only `name`/`organization`/`id`; all routing attributes are disjoint (`project`+`conditions_v2`+`actions_v2`+`frequency` vs `monitor_ids`+`trigger_conditions`+`action_filters`+`frequency_minutes`). | `state mv` is mechanically impossible here. The "never recreate" constraint is correct and is exactly why Option A is the safe path — any beta migration WOULD force recreate (drop+readd the paging rules). |
| "(3) update `apps/web-platform/scripts/sentry-monitors-audit.*` and any test fixtures asserting the `sentry_issue_alert` resource type" | `grep -c 'sentry_issue_alert\|sentry_alert'` on both `sentry-monitors-audit.sh` and `.test.sh` → **0**. The audit tooling queries the Sentry REST API (`/projects/.../rules/`), not Terraform resource types. No fixture asserts the TF resource type. | **No-op.** The audit script needs no change for a resource-type rename. (It WOULD change only if Option B/C altered which REST endpoint holds the rules — see Sharp Edges.) |
| "(4) run full terraform plan expecting 0 changes + 0 deprecation warnings" | The 0-deprecation-warnings half is achievable ONLY by removing/replacing the deprecated resource type. Under Option A the warning is suppressed via a documented provider mechanism if one exists, else the warning persists by design (and the AC must be relaxed to "validate exits 0; warning is expected + documented"). | AC split: Option A → "validate exits 0, deprecation warning documented as accepted-until-GA". Options B/C → genuinely 0 warnings but NON-zero changes (recreate), which violates constraint (2). The two halves of claim (4) are **mutually exclusive** in beta2. |
| ADR-031: "Defer migration … until provider GA" | The repo's own ADR already deferred this exact migration with a documented rationale. #4610 predates / overrides that defer without new information. | Plan surfaces the ADR conflict. If Option A is chosen, ADR-031 stays authoritative (no change). If the user insists on B/C, ADR-031 must be amended and CPO must sign off on the recreate blast radius. |

### Canonical schema evidence

Extracted via `terraform providers schema -json` against the installed
`terraform-provider-sentry_v0.15.0-beta2` binary (dev_overrides, offline) — see
the Phase 0 command to reproduce:

```
sentry_issue_alert (deprecated:true): action_match*, filter_match, frequency*,
  conditions/filters/actions (deprecated JSON-string), conditions_v2/filters_v2/
  actions_v2 (list-of-object), environment, name*, organization*, project*, owner
  (* = required)

sentry_alert (deprecated:false, "in beta, may be subject to change"):
  organization*, name*, monitor_ids* (set(string), REQUIRED),
  trigger_conditions* (REQUIRED; first_seen_event|issue_resolved_trigger|
  reappeared_event|regression_event), action_filters* (REQUIRED; each carries
  conditions[] + actions[] + logic_type), frequency_minutes*, environment,
  enabled, id
  — NO `project` attribute.
```

`sentry_alert` block description (verbatim): *"Create an Alert for a **Monitor**
in an Organization. Monitors must be created separately using the
`sentry_cron_monitor`, `sentry_metric_monitor`, or `sentry_uptime_monitor`
resources."*

Source-rule mapping (from `configure-sentry-alerts.sh`): all 4 rules use
`EventFrequencyCondition`/`EventUniqueUserFrequencyCondition` + `TaggedEventFilter`
(`feature=auth`, `op=<flow>`) + `NotifyEmailAction` (IssueOwners/Team,
ActiveMembers fallthrough). None use first_seen/regression triggers — confirming
they cannot populate `sentry_alert.trigger_conditions` faithfully.

## User-Brand Impact

**If this lands broken, the user experiences:** the 4 auth paging rules
(`auth-exchange-code-burst`, `auth-callback-no-code-burst`, `auth-per-user-loop`,
`auth-signout-burst`) stop firing — an auth-abuse burst (credential-stuffing
exchange-code loop, signout storm) goes unpaged. The operator is blind to an
in-progress auth incident affecting a real founder's account.

**If this leaks, the user's data / workflow is exposed via:** N/A for the alert
*config* itself (no PII in rule definitions). The exposure vector is the
**absence** of alerting, not a leak — a recreate that drops the rules silently
removes the only paging path for auth-event floods.

**Brand-survival threshold:** single-user incident. A single founder whose
account is targeted while the paging rule is dropped (the exact failure mode of
the forbidden recreate path) is a brand-survival event — the operator promised
"we watch your auth surface" and silently stopped.

> CPO sign-off required at plan time before `/work` begins (these are the
> production auth paging rules; any recreate path drops live paging).
> `user-impact-reviewer` will be invoked at review-time.

## Alternative Approaches Considered

| Option | What | 0-changes? | 0-warnings? | Recreate risk | Verdict |
|---|---|---|---|---|---|
| **A (recommended)** | Keep `sentry_issue_alert`; suppress the deprecation warning at source if a provider/Terraform mechanism exists, else document the warning as accepted-until-GA in `issue-alerts.tf` header + ADR-031. No state change. | yes | warning persists unless suppressible; documented as accepted | none | **Ship.** Only path honoring "never recreate" under the beta pin. |
| B | Rewrite the 4 rules as `sentry_alert` bound to a synthetic monitor + synthetic `trigger_conditions`, carrying the frequency logic under `action_filters[].conditions`. | recreate | yes | **HIGH — drops+readds live paging rules** | **Reject.** Violates constraint (2); changes the fired-event semantics (trigger_conditions != frequency-only); requires a monitor that doesn't exist. |
| C | Defer to GA (status quo + tracking issue), per ADR-031's existing defer. | yes | warning persists | none | **Fallback** if Option A's warning cannot be suppressed AND the user declines to accept the documented warning. Equivalent to "close #4610 as deferred". |

**Deferral tracking:** if Option C is chosen, #4610 is updated with the GA
re-evaluation criterion ("re-attempt when `jianyuan/sentry` ships stable v0.15.0
and `sentry_alert` no longer requires `monitor_ids` for project issue alerts")
rather than closed.

## Implementation Phases (Option A — recommended)

### Phase 0 — Preconditions (verify before any edit)
- [ ] Confirm provider still pinned `0.15.0-beta2` in `versions.tf` + `.terraform.lock.hcl` (re-run schema dump if the lock advanced; this whole plan is schema-version-bound).
- [ ] Re-run `cd apps/web-platform/infra/sentry && terraform init -backend=false && terraform validate` — confirm the 4 deprecation warnings + exit 0 still reproduce.
- [ ] Reproduce the schema dump: `terraform providers schema -json` (via dev_overrides to the installed binary if backend init is unavailable offline) and confirm `sentry_alert.monitor_ids.required == true` and `sentry_alert.trigger_conditions.required == true`.
- [ ] **Warning-suppression feasibility probe (load-bearing):** determine whether the deprecation warning is suppressible without removing the resource. Check: (a) `-compact-warnings` only collapses output, does NOT suppress; (b) provider has no opt-out attribute for the deprecation (schema dump shows none); (c) `validate`/`plan` warnings cannot be allow-listed in Terraform core as of 1.10.5. **Expected result: the warning is NOT suppressible while the resource type is `sentry_issue_alert`.** If confirmed, Option A degrades to "document the warning as accepted-until-GA" (= Option C content, but keeps the resources in code, which is the status quo). Surface this to the user before proceeding — it likely means #4610's claim (4) "0 deprecation warnings" is unachievable under the pin, and the honest outcome is Option C.

### Phase 1 — Document the accepted-warning posture (if no suppression mechanism)
- [ ] Edit `apps/web-platform/infra/sentry/issue-alerts.tf` header comment: add a block explaining the deprecation warning is expected and accepted until `jianyuan/sentry` GA, citing the schema-incompatibility (monitor_ids/trigger_conditions required), and pointing to ADR-031's existing defer + this plan + the GA re-evaluation issue.
- [ ] Confirm ADR-031 "Defer migration from `sentry_issue_alert` … until provider GA" line still stands — no edit needed (it already says this); optionally add a 1-line `Amendment (2026-05-29, #4610): re-confirmed at beta2 — sentry_alert requires monitor_ids/trigger_conditions; see plan` for traceability.
- [ ] Update `apps/web-platform/infra/sentry/README.md` only if its prose claims a migration is pending in a way that now needs the beta-blocker note (currently it does not reference `sentry_alert`; verify with grep before editing).

### Phase 2 — Verification (read-only; no prod write)
- [ ] `terraform validate` → exits 0 (warning present + documented as accepted).
- [ ] `terraform fmt -check` clean on any edited `.tf`.
- [ ] `grep -c 'sentry_issue_alert\|sentry_alert' apps/web-platform/scripts/sentry-monitors-audit.{sh,test.sh}` → still 0 (no audit-script change required — claim 3 is a no-op).
- [ ] `bash tests/scripts/test-destroy-guard-sentry-scope-guard.sh` → still passes (the `-target=` allow-list is unchanged; `sentry_issue_alert` was never auto-applied and is not being added to the allow-list).
- [ ] No prod-state mutation of any kind. State is untouched.

### Out of scope / explicitly NOT done
- No rewrite to `sentry_alert` (blocked by required `monitor_ids`/`trigger_conditions`).
- No cross-type state rename (impossible across disjoint schemas).
- No change to `apply-sentry-infra.yml` `-target=` allow-list (issue-alerts stay import-only; never auto-applied).
- No change to `tests/scripts/lib/destroy-guard-filter-sentry.jq` (no `sentry_alert` with array-of-blocks is being auto-applied).

## Acceptance Criteria

### Pre-merge (PR)
- [ ] AC1: `terraform validate` in `apps/web-platform/infra/sentry/` exits 0.
- [ ] AC2 (Option A documented-warning): the deprecation warning is either (a) suppressed via a verified provider/core mechanism, OR (b) explicitly documented in `issue-alerts.tf` header as accepted-until-GA with a pointer to the GA re-evaluation issue. The plan's Phase 0 probe determines which. **Note: claim (4)'s "0 deprecation warnings" is achievable ONLY via recreate (forbidden); the realistic AC is "validate exits 0; warning documented".**
- [ ] AC3: `git grep -c sentry_alert apps/web-platform/scripts/sentry-monitors-audit.sh apps/web-platform/scripts/sentry-monitors-audit.test.sh` → 0 (audit tooling unchanged — claim 3 verified no-op).
- [ ] AC4: `bash tests/scripts/test-destroy-guard-sentry-scope-guard.sh` → `[ok]` (allow-list unchanged).
- [ ] AC5: `terraform fmt -check` clean on every edited `.tf`.
- [ ] AC6: `git diff --stat` shows NO change to `*.tfstate`, no new prod-state-mutation token in any committed runbook or workflow.
- [ ] AC7: PR body uses `Ref #4610` (NOT `Closes`) until the user confirms Option A vs C — if Option C (defer), the issue stays open with a GA re-evaluation note; if Option A documented-warning is accepted as the resolution, `Closes #4610`.

### Post-merge (operator)
- [ ] None. This plan makes no prod write. Automation: not feasible because there is no prod-state mutation to perform — the recommended outcome is documentation + status-quo state.

## Domain Review

**Domains relevant:** Engineering (CTO), Product (CPO — single-user-incident threshold)

> NOTE: Task-based domain-leader subagents are UNAVAILABLE in this planning
> environment (no Task tool). Domain assessment below is the planner's inline
> pass; CPO sign-off (required by the single-user-incident threshold) must be
> obtained before `/work` — flag to the user.

### Engineering (CTO) — inline
**Status:** reviewed (inline)
**Assessment:** This is an IaC-only change against an already-provisioned Sentry
surface. The hard finding is schema incompatibility in the beta provider; the
safe path makes no state mutation. No new infrastructure, no new secret, no new
vendor. The only architectural risk is the forbidden recreate path (Option B),
which the plan explicitly rejects.

### Product/UX Gate
**Tier:** none (no user-facing UI surface)
**Decision:** N/A — infrastructure/tooling change. The user-brand impact is
captured in `## User-Brand Impact` (auth paging continuity), which drives the
single-user-incident threshold + CPO sign-off requirement, not a UX-gate.

## Infrastructure (IaC)

### Terraform changes
- Files (Option A): `apps/web-platform/infra/sentry/issue-alerts.tf` (header
  comment only), optionally `knowledge-base/engineering/architecture/decisions/ADR-031-sentry-as-iac.md`
  (1-line amendment), optionally `apps/web-platform/infra/sentry/README.md`.
- Provider: `jianyuan/sentry 0.15.0-beta2` (unchanged, pinned). Required version `>= 1.6`.
- Sensitive variables: none added. `SENTRY_AUTH_TOKEN` (GitHub repo secret
  `SENTRY_IAC_AUTH_TOKEN`) + R2 backend creds (Doppler `prd_terraform`) —
  unchanged.

### Apply path
- **No apply.** Option A is documentation/comment only; state is untouched.
  `issue-alerts.tf` resources remain import-only and are NOT in the
  `apply-sentry-infra.yml` `-target=` allow-list (which is cron + uptime only).

### Distinctness / drift safeguards
- `dev != prd`: N/A (single Sentry org `jikigai`/`jikigai-eu`; no dev/prd split
  for Sentry IaC per ADR-031).
- `lifecycle.ignore_changes` on the 4 resources stays as-is
  (`conditions_v2, filters_v2, actions_v2, environment, frequency`) — required
  because the post-import state is authoritative.
- State storage: R2 backend, `use_lockfile = false`. No new secret lands in
  state (no resource created).

### Vendor-tier reality check
- N/A — no resource creation. `sentry_alert` is itself beta ("may not be
  viewable in the UI today") which is an additional reason not to adopt it now.

## Observability

```yaml
liveness_signal:
  what: "4 auth paging rules continue firing in Sentry (auth-exchange-code-burst, auth-callback-no-code-burst, auth-per-user-loop, auth-signout-burst)"
  cadence: "per-event, project web-platform"
  alert_target: "IssueOwners / ops team email (NotifyEmailAction, ActiveMembers fallthrough)"
  configured_in: "Sentry rules (source: configure-sentry-alerts.sh); imported into TF state as sentry_issue_alert.*"
error_reporting:
  destination: "Sentry (the alerting surface itself)"
  fail_loud: "this plan makes no code change that can fail; terraform validate exit code is the gate"
failure_modes:
  - mode: "rules silently dropped (the recreate path this plan forbids)"
    detection: "apps/web-platform/scripts/sentry-monitors-audit.sh Class C (empty actions[]) + Class A (orphan) detection on next release audit"
    alert_route: "audit report written to knowledge-base/legal/audits/ + CI release asset"
  - mode: "provider lock advances past beta2 and schema changes"
    detection: "terraform init -upgrade in CI surfaces new version; re-run schema dump"
    alert_route: "scheduled-terraform-drift.yml (Sentry root extension is a tracked follow-up)"
logs:
  where: "terraform validate output (CI + local); Sentry dashboard for rule fires"
  retention: "Sentry default; CI logs per GitHub Actions retention"
discoverability_test:
  command: "cd apps/web-platform/infra/sentry && terraform init -backend=false && terraform validate; echo exit=$?"
  expected_output: "Success! ... validation warnings (4 deprecation) ... exit=0"
```

## Test Scenarios
- `terraform validate` exits 0 with the 4 documented deprecation warnings (Option A) — the discoverability test above.
- `tests/scripts/test-destroy-guard-sentry-scope-guard.sh` passes (allow-list unchanged).
- Audit-script grep returns 0 `sentry_alert` matches (claim 3 no-op confirmed).
- Negative: NO `*.tfstate` diff, NO new prod-state-mutation token in any committed file.

## Sharp Edges
- A plan whose `## User-Brand Impact` section is empty, contains only TBD/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. (This plan's section is filled — auth paging continuity, single-user-incident.)
- Cross-resource-type state rename is NOT a rename — it requires schema-compatible state. `sentry_issue_alert` → `sentry_alert` shares zero routing attributes; attempting it leaves every attribute "unconfigured" at next plan and the required `monitor_ids` can never be satisfied. Do not attempt it.
- The provider's deprecation message ("migrate to `sentry_alert`") is forward-looking to GA. Reading it as "beta2 supports the migration" is the trap this plan exists to prevent. `sentry_alert` in beta2 is monitor-bound; the auth rules are not monitor-bound.
- If a future PR ever DOES migrate to `sentry_alert` (at GA), the destroy-guard chain changes: `sentry_alert.action_filters[]` carries array-of-blocks (`conditions[]`, `actions[]`), so `tests/scripts/lib/destroy-guard-filter-sentry.jq` MUST gain a path-specific nested-clause BEFORE `sentry_alert` is added to the `apply-sentry-infra.yml` `-target=` allow-list, and `tests/scripts/test-destroy-guard-sentry-scope-guard.sh` must be extended to allow `sentry_alert`. (Not in scope here — Option A adds nothing to the allow-list.)
- The audit-script change in #4610 claim (3) is a no-op (0 resource-type strings). Do not invent an edit to satisfy a claim the codebase falsifies.
- This entire plan is schema-version-bound to `0.15.0-beta2`. If `.terraform.lock.hcl` has advanced, re-run the schema dump (Phase 0) before trusting any attribute claim here.

## Open Code-Review Overlap

Task tool unavailable in this environment to query `gh issue list --label
code-review`. **Manual follow-up before /work:** run
`gh issue list --label code-review --state open --json number,title,body
--limit 200` and grep for `issue-alerts.tf`, `sentry`, `ADR-031`. Disposition:
expected None (this is a freshly-filed migration issue), but verify rather than
assume.

## Notes on workflow-environment gaps (planning session)
- **Task tool unavailable:** the plan skill's parallel research agents
  (repo-research-analyst, learnings-researcher), domain leaders, SpecFlow, and
  plan-review (DHH/Kieran/Simplicity) could not be spawned. Research was done
  inline via direct schema dump + file reads, which for an IaC schema-fact
  question is arguably stronger evidence than agent summaries. CPO sign-off
  (required by threshold) and the 3-reviewer plan-review must be obtained
  out-of-band before `/work`.
