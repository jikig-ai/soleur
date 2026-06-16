---
title: "fix(sentry-iac): widen claude-eval cron margins + route high-priority issues to ops@jikigai.com"
date: 2026-06-15
type: fix
branch: feat-one-shot-sentry-cron-margin-alert-routing
issue: null
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
adr: ADR-031-sentry-as-iac.md
related:
  - knowledge-base/engineering/architecture/decisions/ADR-031-sentry-as-iac.md
  - knowledge-base/project/learnings/2026-05-17-sentry-issue-alert-create-dedup-on-action-match-not-conditions.md
  - knowledge-base/project/learnings/2026-05-15-terraform-import-only-beta-provider-schema-validation.md
  - knowledge-base/project/learnings/bug-fixes/2026-06-02-sentry-auth-alert-rules-drifted-to-empty-filters-not-a-red-herring.md
  - knowledge-base/project/learnings/best-practices/2026-05-30-routing-through-shared-tag-filtered-alert-primitive-needs-all-filter-tags.md
---

# fix(sentry-iac): widen claude-eval cron margins + route high-priority issues to ops@jikigai.com

🐛 / 📈 Two cohesive Sentry-alerting IaC fixes in `apps/web-platform/infra/sentry/`,
both shipped via `.github/workflows/apply-sentry-infra.yml` on merge to main, both
triggered by a production Sentry page received **2026-06-15 11:30 CEST** for monitor
`scheduled-agent-native-audit` (monitor.id `738e2caf-4807-437b-895f-cea3bb668d3b`,
monitor.incident `5546660`, "A missed check-in was detected", last successful
check-in `2026-06-10T16:59:18+00:00`).

## OUTCOME (2026-06-15, post-implementation)

**CHANGE A shipped as planned** — margin 30→60 on the 12 `max_runtime_minutes=55` cohort monitors
+ substrate/inline comment updates. fmt clean, validate success, parity + destroy-guard tests green.

**CHANGE B did NOT land as IaC — it moved to account-level Email Routing** after Phase-0 live
verification falsified the plan's premises (see
`knowledge-base/project/learnings/2026-06-15-sentry-alert-routing-to-an-email-needs-member-target-not-an-iac-rule.md`):
(1) the `iac-terraform-prd` token lacks `member:read` (all 4 Sentry tokens 403 on the members API),
so a `data.sentry_organization_member` lookup would 403 at plan time on every future apply and break
the pipeline; (2) `ops@jikigai.com` is **not** a Sentry member (the org's only member is
`jean.deruelle@jikigai.com`), so there was no member to resolve/target. Per the operator's choice,
CHANGE B was implemented as: add `ops@jikigai.com` as a verified secondary email on the founder's
account + route the `web-platform` project's notifications to it (Sentry → Account → Email Routing).
No new `sentry_issue_alert`, no member resource, no workflow `-target`, no contract test. The
`member:read` scope was toggled on only to verify membership, then **reverted** to the documented
ADR-031 least-privilege set. **Remaining operator step:** verify `ops@jikigai.com` via the link Sentry
emailed to that inbox (delivery to an unverified secondary email does not occur). The Phases 2-3 below
(CHANGE B IaC) are therefore **superseded** and were not implemented.

## Enhancement Summary

**Deepened on:** 2026-06-15
**Gates passed:** 4.6 User-Brand Impact (threshold present + valid), 4.7 Observability
(5-field schema, no SSH), 4.8 PAT-shaped (clean), 4.9 UI-wireframe (no UI surface — skip).
**Agents:** terraform-architect (CHANGE B rule shape), Explore verify-the-negative (8 premises).

### Key Improvements
1. **`filters_v2` OMITTED, not `= []`** (terraform-architect Item 1, highest-risk). A project-wide
   apply-created rule with no filter is unprecedented in `issue-alerts.tf`; `terraform validate`
   cannot prove the apply-time round-trip. Phase 0.1b added to probe `filters_v2.optional` and
   prefer omission; PR body must flag this as the one shape not provable pre-merge.
2. **`<member.internal_id>` placeholder is invalid HCL** (Item 5) — Phase 2.2 now binds the real
   `data.sentry_organization_member.ops.internal_id`; AC4 + AC11 updated.
3. **Member + `fallthrough_type` pairing** (Item 3) — Phase 0.1c added to settle the pairing via a
   config-time `terraform validate` probe; drop `fallthrough_type` if rejected.
4. **Fail-closed member coupling** (Item 4) — documented: data-source read fails the next apply if
   `ops@jikigai.com` is removed (desired posture; Phase 0.2 probes membership first).

### Verified premises (verify-the-negative pass, 0 contradictions)
- 12 monitors `max_runtime_minutes=55` (NOT 13; `scheduled_strategy_review` is 10) — all 12 at margin 30.
- `frequency = 16` is free. `kb_sync_silent_failure` absent from `-target` (acknowledged out-of-scope).
- scope-guard allows `sentry_issue_alert` already; `sentry_organization_member` would be a new type.
- README "8/6" counts stale (real 42/12); no test pins them. `EXPECTED_RULES` = 4 names. Substrate prose at L28-46.

## Overview

**CHANGE A — kill false-positive "missed check-in" pages on the claude-eval cron cohort.**
The 12 claude-eval-cohort monitors post a **single end-of-run** Sentry heartbeat
(`_cron-claude-eval-substrate.ts` → handler step 4 `sentry-heartbeat`) AFTER a
`claude --print` run whose budget is **50 min** (`MAX_TURN_DURATION_MS = 50 * 60 * 1000`)
plus token-mint + depth-1 clone + workspace teardown overhead (~5-10 min). The monitors
set `checkin_margin_minutes = 30`, so any run finishing >30 min after its scheduled
fire false-pages even on a fully successful run. **Proof it was a false positive:** today's
`scheduled-agent-native-audit` run *succeeded* and filed issue **#5318** ("[Scheduled]
Agent-Native Audit — CRUD Completeness…", `state: OPEN`, `createdAt: 2026-06-15T09:09:20Z`);
only the heartbeat landed late. agent-native-audit is the heaviest (8 Task sub-agents) so it
tripped first, but the entire cohort shares the 30-min-margin / 50-min-budget mismatch.
**Fix:** widen `checkin_margin_minutes` 30 → **60** for all 12 cohort monitors.

**CHANGE B — route Sentry high-priority issue notifications to `ops@jikigai.com`, codified in IaC.**
The page came from Sentry's built-in default "Send a notification for high priority issues"
rule (`new_high_priority_issue` + `existing_high_priority_issue`), which notified "recently
active members". The user wants these to land at `ops@jikigai.com`, codified in IaC (not the
UI). Add a project-wide **apply-created** `sentry_issue_alert` (modeled on the apply-created
`byok_art_33_breach` / `byok_cap_exceeded` rules that terraform OWNS) whose `conditions_v2`
are the two high-priority lifecycle conditions and whose `actions_v2 notify_email` targets
`ops@jikigai.com` as a pinned **Member**. Invite the member via IaC
(`sentry_organization_member` resource) so no manual dashboard step is required.

Both changes are in the same Sentry IaC root and ship through the same pipeline → **one PR**.

## Premise Validation (Phase 0.6)

Every premise the brief cites by reference was checked against the live repo / GitHub /
Sentry-provider docs:

- **`#5318` succeeded-but-late thesis** — `gh issue view 5318` → `state: OPEN`,
  `createdAt: 2026-06-15T09:09:20Z`. **HELD.** The run filed an artifact; only the
  end-of-run heartbeat was late. This is the false-positive proof.
- **`#4656` recipient-pinning deferral** — `gh issue view 4656` → `OPEN`
  ("byok Art.33 alert hardening: recurrence firing, **recipient pinning (N>1)**…"). **HELD.**
  CHANGE B's Member-pinning is the same deferred concern; this PR partially advances it
  (see Open Questions OQ2 — whether to also pin the BYOK rules is out of scope).
- **`#4610` provider-GA / `sentry_alert` migration** — `gh issue view 4610` → `CLOSED`.
  Deprecation of `sentry_issue_alert` stays accepted until stable v0.15.0 (ADR-031 amendment
  2026-05-29). CHANGE B's new rule stays a `sentry_issue_alert` (NOT `sentry_alert`). **HELD.**
- **Cohort membership = `max_runtime_minutes = 55`** — authoritative `awk` pairing of
  `^resource "sentry_cron_monitor"` → `max_runtime_minutes = 55` returned **exactly 12**:
  `scheduled_bug_fixer, scheduled_community_monitor, scheduled_roadmap_review,
  scheduled_legal_audit, scheduled_agent_native_audit, scheduled_competitive_analysis,
  scheduled_content_generator, scheduled_ux_audit, scheduled_campaign_calendar,
  scheduled_growth_audit, scheduled_growth_execution, scheduled_seo_aeo_audit`. This matches
  the brief's listed names byte-for-byte. **`scheduled_strategy_review` is NOT in the cohort**
  (`max_runtime_minutes = 10`, pure-TS) — a parallel research agent erroneously included it; the
  `awk` grep is authoritative. **HELD with correction noted.**
- **`sentry_issue_alert` design hinge — do high-priority conditions fire on cron-monitor
  issues?** External research (Sentry docs + jianyuan provider docs, v0.15.0-beta.2):
  - Sentry creates a real **Issue** when a cron monitor reports a missed/failed check-in
    ("Issues are created when a cron monitor job execution is missed or failed.").
  - For **non-error issues like cron monitors, Sentry assigns priority by *actionability*** —
    a cron-monitor failure is high-priority. The default rule that paged uses
    `new_high_priority_issue` + `existing_high_priority_issue`.
  - The jianyuan/sentry provider docs confirm both condition types exist in `conditions_v2`
    (`new_high_priority_issue`, `existing_high_priority_issue`) and that
    `actions_v2.notify_email` supports `target_type = "Member"` +
    `target_identifier = data.sentry_organization_member.member.internal_id`.
  - **Conclusion:** a project-wide rule with the two high-priority conditions and NO tag
    filter captures BOTH error high-priority issues AND cron-monitor missed-check-in issues —
    exactly replicating the default rule's scope, routed to `ops@jikigai.com`. **HELD.**

## Research Reconciliation — Spec vs. Codebase

| Claim (brief) | Reality (verified) | Plan response |
|---|---|---|
| "cohort = 12 named monitors" | `awk` pairing of `max_runtime_minutes=55` returns exactly those 12 | Use the `awk`-derived list verbatim; AC pins the count to 12 |
| README says "8 cron monitors / 6 issue alerts" | File has **42 cron monitors / 12 issue-alert resources** (7 apply-created in `-target`); no test pins either count | Update README prose to current counts; safe (no count guard) |
| "model on byok rules that terraform OWNS" | `byok_art_33_breach`/`byok_cap_exceeded` use real `conditions_v2`/`filters_v2`/`actions_v2`, `lifecycle.ignore_changes = [environment]` only, and are `-target`'d | Model new rule identically (apply-created, not import-only) |
| "notify_email needs a member id; ops@ must be a verified member first" | True: `data.sentry_organization_member` *retrieves* an existing member (fails if absent). The `sentry_organization_member` **resource** *creates/invites* one and exposes `internal_id` | Invite via the IaC **resource** (codifies the invite — no manual step); reference its `internal_id` in `target_identifier` |
| "verify whether issue alert fires on cron-monitor issues" | Confirmed: cron issues are real Sentry Issues; high-priority conditions fire on them | Use high-priority `conditions_v2`, project-wide (no tag filter) |
| `kb_sync_silent_failure` is apply-created | It IS apply-created (real filters, only `environment` ignored) but is **NOT** in the `-target` list — never auto-applied (latent gap) | **Acknowledge** (see Open Code-Review Overlap); out of scope unless trivially foldable — do NOT silently inherit |

## User-Brand Impact

**If this lands broken, the user experiences:** (A) continued 3am false pages on every
slow-but-successful claude-eval cron run, training the solo founder to mute the cron channel —
so a *genuinely* dead cron (e.g. a secret-touching workflow that stopped firing) goes
unnoticed; (B) a high-priority production error or a real missed-check-in that never reaches
`ops@jikigai.com` because the new routing rule was mis-shaped (empty-filter catch-all that
Sentry dedups away, wrong member id, or a dropped `-target`), leaving the founder blind to a
real incident.
**If this leaks, the user's data is exposed via:** the `notify_email` recipient — a Sentry
issue-alert payload carries error messages, stack traces, and pseudonymized `userIdHash`
(scrubbed by `sentry-scrub.ts`). Routing to `ops@jikigai.com` (internal staff, the founder's
own ops inbox) does not widen disclosure beyond the current `ActiveMembers` fallthrough at N=1;
at N>1 active members, pinning to a single Member *narrows* disclosure (an improvement over the
current fallthrough). No new external recipient.
**Brand-survival threshold:** `single-user incident` — an un-paged real incident or a muted
cron channel is a single-user-incident-class observability regression (the exact #4116-class
dark-monitor failure mode). `requires_cpo_signoff: true` (CHANGE B is a paging-path change).

## Implementation Phases

> **Phase order is load-bearing:** Phase 0 (provider-schema + token-scope verification) MUST
> complete before any `.tf` edit — CHANGE B's whole shape depends on the provider supporting
> `new_high_priority_issue` + `notify_email target_type="Member"` + the `sentry_organization_member`
> resource, and on the IaC token carrying member-invite scope.

### Phase 0 — Provider-schema + token-scope verification (NO file edits)

0.1. **Confirm provider schema** for the pinned `jianyuan/sentry v0.15.0-beta2` against the
  *installed* provider (not just docs):
  ```bash
  cd apps/web-platform/infra/sentry && terraform init -backend=false -lockfile=readonly
  terraform providers schema -json 2>/dev/null \
    | jq '.provider_schemas[].resource_schemas["sentry_issue_alert"].block.attributes.conditions_v2' \
    | grep -iE 'new_high_priority_issue|existing_high_priority_issue' || echo "MISSING — re-scope"
  terraform providers schema -json 2>/dev/null \
    | jq '.provider_schemas[].resource_schemas["sentry_organization_member"]' \
    | head -5   # confirms the invite-resource exists in beta2
  ```
  Docs (v0.15.0-beta.2) confirm: `conditions_v2` includes `new_high_priority_issue`,
  `existing_high_priority_issue`; `actions_v2.notify_email.target_type ∈ {IssueOwners, Team,
  Member}`, `fallthrough_type ∈ {AllMembers, ActiveMembers, NoOne}`, `target_identifier` =
  Member/Team internal id; `sentry_organization_member` resource takes `{organization, email,
  role}` and exposes `internal_id`. **If the installed schema disagrees, halt and re-scope**
  (the beta tag is mutable — `2026-05-15-terraform-import-only-beta-provider-schema-validation.md`).
0.1b. **[deepen-plan: terraform-architect Item 1 — HIGHEST RISK] Probe `filters_v2`
  optionality and prefer OMITTING the attribute over `= []`.** Every apply-created rule in
  `issue-alerts.tf` carries a **non-empty** `filters_v2`; the only `filters_v2 = []` uses are the
  4 import-only auth rules, and those freeze it under `lifecycle.ignore_changes = [filters_v2]`.
  CHANGE B's project-wide rule is the FIRST apply-created, **non-ignored** rule with no filter —
  unprecedented in this file. `terraform validate` (AC10) will likely pass (the auth rules prove
  `[]` is config-legal) but **validate does NOT exercise the apply-time POST round-trip**: the
  provider may reject an empty filter array at create, OR Sentry may return a computed non-empty
  default → a *perpetual* `filters_v2` diff (since it is NOT ignored). Probe the schema:
  ```bash
  terraform providers schema -json 2>/dev/null \
    | jq '.provider_schemas[].resource_schemas["sentry_issue_alert"].block.attributes.filters_v2
          | {nesting: .nesting, optional: .optional, required: .required}'
  ```
  - **If `filters_v2` is `optional` (not `required`): OMIT the attribute entirely** in the new
    rule (do NOT write `filters_v2 = []`). An omitted optional attribute is the more conservative
    "no filter" expression and avoids a provider normalizing `[] ↔ null` on read (a classic
    perpetual-diff source on a non-ignored attribute). This is the **default** shape for the rule.
  - **`ignore_changes` on `filters_v2` is FORBIDDEN** (it re-enters the 2026-06-02 empty-filter
    catch-all class). So the empty-filter round-trip is the **one shape not provable pre-merge**;
    state this explicitly in the PR body. Rollback if the post-merge apply shows a perpetual
    `filters_v2` diff: the project-wide design must be reconsidered (e.g. scope to a broad-but-
    real `monitor.slug`-present filter), NOT silenced via `ignore_changes`.
0.1c. **[deepen-plan: terraform-architect Item 3] Validate the `notify_email` Member +
  `fallthrough_type` pairing at config-time.** Enum membership is confirmed, but the *pairing*
  (does the provider accept `fallthrough_type` alongside `target_type = "Member"`, where there is
  no "nobody" to fall through from?) is unverified. Add a throwaway block with the exact
  `notify_email { target_type="Member"; target_identifier="1"; fallthrough_type="ActiveMembers" }`
  shape and run `terraform validate` (folds into AC10). **If validate rejects the pairing, DROP
  `fallthrough_type`** (a pinned Member with an explicit id needs no fallthrough). Do not block on
  this — it is config-time-catchable.
0.2. **Confirm IaC-token member-invite scope.** ADR-031 lists the `iac-terraform-prd` integration
  scopes as `[alerts:read, alerts:write, event:read, org:read, project:admin, project:read,
  project:write]`. The `sentry_organization_member` resource (member invite) typically needs
  **`member:admin`** (or `member:write`), which is NOT in that set. Probe read-only via the
  members API before committing to the IaC-resource approach:
  ```bash
  curl -fsS -H "Authorization: Bearer $SENTRY_AUTH_TOKEN" \
    "https://${SENTRY_ORG}.sentry.io/api/0/organizations/${SENTRY_ORG}/members/" | jq 'length' || echo "scope gap"
  curl -fsS -H "Authorization: Bearer $SENTRY_AUTH_TOKEN" \
    "https://${SENTRY_ORG}.sentry.io/api/0/organizations/${SENTRY_ORG}/members/" \
    | jq -r '.[].email' | grep -i 'ops@jikigai.com' || echo "ops@ NOT yet a member"
  ```
  - **If `ops@jikigai.com` is ALREADY a verified org member** (likely — it is the operator's own
    ops address): **drop the `sentry_organization_member` resource entirely** and use the
    `data.sentry_organization_member` *data source* (needs only `member:read`/`org:read`,
    already in scope) to resolve `internal_id`. **This is the default path.**
  - **If the member is absent AND the token lacks member-invite scope:** widen the
    `iac-terraform-prd` integration permission set to **Member & Billing: Admin** — record this
    as a one-time integration-permission change in `### Infrastructure (IaC)` (it is the
    integration's scope, not a per-apply dashboard click) — then use the
    `sentry_organization_member` resource to invite. Record the chosen path in the PR body.

### Phase 1 — CHANGE A: widen `checkin_margin_minutes` 30 → 60 on the 12-monitor cohort

1.1. In `apps/web-platform/infra/sentry/cron-monitors.tf`, set `checkin_margin_minutes = 60`
  on exactly these 12 resources (the `max_runtime_minutes = 55` cohort, `awk`-derived):
  `scheduled_bug_fixer, scheduled_community_monitor, scheduled_roadmap_review,
  scheduled_legal_audit, scheduled_agent_native_audit, scheduled_competitive_analysis,
  scheduled_content_generator, scheduled_ux_audit, scheduled_campaign_calendar,
  scheduled_growth_audit, scheduled_growth_execution, scheduled_seo_aeo_audit`.
  Do NOT touch any monitor with `max_runtime_minutes ≠ 55` (e.g. `scheduled_strategy_review` =
  10 stays at 30; the small-cron cohort stays at 30; `scheduled_realtime_probe` stays at 1440).
1.2. **Update the per-substrate prose comment block** (the `checkin_margin_minutes is sized
  per-substrate` block, currently ~lines 28-46). Add a paragraph documenting the **claude-eval
  cohort 60-min margin and WHY**: these crons post a *single end-of-run heartbeat* after a
  50-min `MAX_TURN_DURATION_MS` budget + ~5-10 min mint/clone/teardown, so a fully successful
  run lands its check-in up to ~60 min after the scheduled fire; a 30-min margin false-pages on
  success. 60 = 50-min budget + setup/teardown slack; it stays far under each cohort monitor's
  inter-fire gap (the tightest cohort cadences are weekly / twice-weekly / monthly — all ≥ 1
  day, vs the hourly drift-guards which are NOT in this cohort), so a maximally-late run is never
  misread as a missed *next* run, and a genuinely dead cron still pages within ~1h.
  `cron-inngest-cron-watchdog` (the `scheduled_inngest_cron_watchdog` liveness beacon + the
  parity-guarded `EXPECTED_CRON_FUNCTIONS` manifest) remains the not-firing backstop.
  Per-resource: where a resource already carries an inline margin-rationale comment
  (`scheduled_roadmap_review` lines 322-327, the `community_monitor`/`legal_audit`/`ux_audit`
  cohort comments that say "30-min margin per the Inngest-fired precedent"), update each such
  line so it now reads 60 — `grep -n '30-min margin' cron-monitors.tf` after the edit and
  reconcile each cohort hit.

### Phase 2 — CHANGE B: high-priority alert routing to ops@jikigai.com

2.1. **(Conditional, per Phase 0.2 verdict)** Default path — member already exists — use the
  data source:
  ```hcl
  data "sentry_organization_member" "ops" {
    organization = var.sentry_org
    email        = "ops@jikigai.com"
  }
  ```
  Fallback path — member absent + token scoped — use the invite resource:
  ```hcl
  resource "sentry_organization_member" "ops" {
    organization = var.sentry_org
    email        = "ops@jikigai.com"
    role         = "member"
  }
  ```
  Co-locate in `issue-alerts.tf` next to the rule that consumes it.
2.2. **Add the apply-created high-priority routing rule** to `issue-alerts.tf`, modeled on
  `byok_art_33_breach` (apply-created posture: real conditions/filters/actions, NOT
  `lifecycle.ignore_changes` on them — only `environment`):
  ```hcl
  resource "sentry_issue_alert" "high_priority_to_ops" {
    organization = var.sentry_org
    project      = data.sentry_project.web_platform.slug
    name         = "high-priority-to-ops"
    # "any": the two high-priority conditions are distinct lifecycle states (a
    # NEW high-priority issue vs an EXISTING issue ESCALATED to high-priority);
    # "all" would require both on one event — never satisfiable. Same rationale
    # as byok_art_33_breach's "any" over its three lifecycle conditions.
    action_match = "any"
    filter_match = "all"
    frequency    = 16  # free slot (taken: 5,10,11,12,13,14,15,30,60,61,62) —
                       # Sentry POST-time dedup keys on action+filter+frequency
                       # +actions-shape, NOT conditions (2026-05-17 learning).

    # Project-wide high-priority capture: NO tagged_event filter. Sentry assigns
    # priority by log-level (errors) AND actionability (non-error issues like
    # cron-monitor missed/failed check-ins), so these two conditions fire on BOTH
    # error high-priority issues AND cron-monitor missed-check-in issues — exactly
    # replicating the default "high priority issues" rule that paged.
    conditions_v2 = [
      { new_high_priority_issue      = {} },
      { existing_high_priority_issue = {} },
    ]
    # filters_v2 DELIBERATELY OMITTED (NOT `= []`) per Phase 0.1b: project-wide
    # scope IS the design (route ALL high-priority, mirroring the default rule).
    # Omission avoids the [] <-> null normalize-on-read perpetual-diff trap on a
    # non-ignored attr. ignore_changes on filters_v2 is FORBIDDEN (2026-06-02
    # empty-filter catch-all class). If Phase 0.1b shows filters_v2 is `required`,
    # re-scope to a broad real filter rather than [] — do NOT silence with ignore.
    actions_v2 = [
      {
        notify_email = {
          target_type       = "Member"
          target_identifier = data.sentry_organization_member.ops.internal_id  # data-source path (default)
          fallthrough_type  = "ActiveMembers"  # founder still paged if the id resolves empty
                                               # (drop if Phase 0.1c validate rejects Member+fallthrough)
        }
      },
    ]

    lifecycle {
      ignore_changes = [environment]
    }
  }
  ```
  **`target_identifier` MUST be a real HCL reference, NOT a `<placeholder>`** (invalid HCL → `fmt`/`validate`
  hard-fail). Use `data.sentry_organization_member.ops.internal_id` (data-source path, default) or
  `sentry_organization_member.ops.internal_id` (resource path, fallback) per the Phase 0.2 verdict.
  **Standing coupling (document in PR body):** because the rule's `target_identifier` reads from
  the member data source, if `ops@jikigai.com` is ever removed as an org member the data-source
  read errors and the NEXT apply fails — even an apply touching only cron margins. This is the
  desired fail-closed posture for a paging-path resource (better than creating a rule against a
  dead member id), but it is a real coupling the operator should know.
2.3. **Add the new rule (and, if the resource path is taken, the member resource) to the
  apply workflow `-target` set** in `.github/workflows/apply-sentry-infra.yml` (the
  `terraform plan -target=…` block):
  - `-target=sentry_issue_alert.high_priority_to_ops`
  - if Phase 2.1 uses the **resource**: `-target=sentry_organization_member.ops` (a data
    source needs no target). Place targets on their own continuation lines; a comment INSIDE
    the backslash-continued command terminates it (the file's own L195 warning, PR #5108).
2.4. **Update the README** (`apps/web-platform/infra/sentry/README.md`): correct the stale
  "6 issue alerts" / "8 cron monitors" counts to current reality (now `13 issue alerts` after
  this PR / `42 cron monitors`), describe the new `high-priority-to-ops` rule (project-wide,
  routes high-priority error AND cron-monitor missed-check-in issues to `ops@jikigai.com`),
  and reference ADR-031. Note the rule's apply-created posture and `-target` inclusion.

### Phase 3 — Liveness assertion + contract test for the new rule

3.1. **Extend `apps/web-platform/scripts/assert-byok-rules-exist.sh`** `EXPECTED_RULES` array
  with `"high-priority-to-ops"` so the post-apply read-only liveness check asserts the new
  paging rule still exists by name after every apply (mirrors the chat/workspace-sync additions
  per ADR-031 amendment 2026-06-03). Update the error-message prose to name the new rule's
  failure mode (high-priority/cron-failure notifications un-routed). Also update the fixture
  test `apps/web-platform/scripts/assert-byok-rules-exist.test.sh` fixtures to include the new
  rule so the test stays green.
3.2. **Add a contract test** modeled on the simplest op-contract test
  (`test/sentry-workspace-sync-health-alert-op-contract.test.ts`, feature-only shape — but here
  there is NO feature tag, so it pins the *structural invariants* instead). New file
  `apps/web-platform/test/sentry-high-priority-alert-contract.test.ts` asserting against
  `infra/sentry/issue-alerts.tf` (use block-scoped slicing, resource-marker to next-resource-marker,
  per the `kb-sync`/`kb-db` test pattern, so assertions cannot pass vacuously):
  - the `high_priority_to_ops` resource block exists;
  - it declares BOTH `new_high_priority_issue` AND `existing_high_priority_issue` in
    `conditions_v2` (a regression that drops one is a silent coverage loss);
  - `action_match = "any"` (so the two mutually-exclusive lifecycle conditions are satisfiable);
  - `notify_email` `target_type = "Member"` (the routing-to-ops invariant — a drift back to
    `IssueOwners` would silently revert to the over-disclosing fallthrough);
  - `frequency = 16` is unique in the file (dedup invariant);
  - the rule name `"high-priority-to-ops"` matches the `EXPECTED_RULES` entry in
    `assert-byok-rules-exist.sh` (cross-artifact pin so a rename breaks CI in both places — read
    both files in the test).

## Acceptance Criteria

### Pre-merge (PR)
- [ ] **AC1 (A):** `awk '/^resource "sentry_cron_monitor"/{r=$3} /max_runtime_minutes *= *55/{print r}' cron-monitors.tf` returns exactly 12 resources, and every one of those 12 has `checkin_margin_minutes = 60` after the edit (`grep -A8 <resource> | grep 'checkin_margin_minutes  *= *60'` for each).
- [ ] **AC2 (A):** No monitor with `max_runtime_minutes ≠ 55` had its margin changed — diff shows exactly 12 `checkin_margin_minutes` lines changed, all 30 → 60.
- [ ] **AC3 (A):** The per-substrate prose comment block documents the claude-eval-cohort 60-min margin AND the WHY (single end-of-run heartbeat after a 50-min budget). `grep -c 'single end-of-run\|end-of-run heartbeat' cron-monitors.tf` ≥ 1 in the substrate block; no stale "30-min margin per the Inngest-fired precedent" line remains on any of the 12 cohort resources.
- [ ] **AC4 (B):** `issue-alerts.tf` declares `resource "sentry_issue_alert" "high_priority_to_ops"` with `conditions_v2` containing BOTH `new_high_priority_issue` and `existing_high_priority_issue`, **`filters_v2` OMITTED** (project-wide; per Phase 0.1b — NOT `= []`, and NOT under `ignore_changes`), `action_match = "any"`, `frequency = 16`, and `actions_v2 notify_email target_type = "Member"` with `target_identifier` bound to a real `data.`/resource reference (no `<placeholder>`).
- [ ] **AC5 (B):** The member id is resolved via either `sentry_organization_member.ops.internal_id` (resource) or `data.sentry_organization_member.ops.internal_id` (data source) per the Phase 0.2 verdict — NOT a hardcoded id.
- [ ] **AC6 (B):** `frequency = 16` is unique in `issue-alerts.tf` (`grep -c 'frequency *= *16' = 1`).
- [ ] **AC7 (B):** `apply-sentry-infra.yml` `-target` set includes `sentry_issue_alert.high_priority_to_ops` (and `sentry_organization_member.ops` iff the resource path was chosen). Run `tests/scripts/test-destroy-guard-sentry-scope-guard.sh` and confirm pass: `sentry_issue_alert` is already an allowed type; `sentry_organization_member` is a NEW type IF the resource path is used → **then the scope-guard allow-list AND `destroy-guard-filter-sentry.jq` MUST be extended** (see Sharp Edges).
- [ ] **AC8 (B):** `assert-byok-rules-exist.sh` `EXPECTED_RULES` includes `high-priority-to-ops`; `bash apps/web-platform/scripts/assert-byok-rules-exist.test.sh` passes with the new expected entry.
- [ ] **AC9 (B):** `apps/web-platform/test/sentry-high-priority-alert-contract.test.ts` exists and passes (`cd apps/web-platform && ./node_modules/.bin/vitest run test/sentry-high-priority-alert-contract.test.ts`).
- [ ] **AC10 (both):** `cd apps/web-platform/infra/sentry && terraform init -backend=false -lockfile=readonly && terraform validate` passes (config-time schema validation — catches a `conditions_v2`/`notify_email` shape error per the beta-provider learning). `terraform plan` against live Sentry needs the IaC token and is the Phase 4 post-merge apply concern, not a pre-merge gate.
- [ ] **AC11 (both):** `terraform fmt -check` clean on the sentry root.
- [ ] **AC12 (B):** README updated — counts corrected to current reality, new rule described, ADR-031 referenced. `sentry-monitor-iac-parity.test.ts` still passes (margin/alert changes do not touch slug↔name parity).
- [ ] **AC13:** Full relevant suite green: `sentry-monitor-iac-parity.test.ts`, all `sentry-*-alert-op-contract.test.ts`, `test-destroy-guard-counter-sentry.sh`, `test-destroy-guard-sentry-scope-guard.sh`.
- [ ] **AC14:** PR body uses `Ref` (not `Closes`) for any tracked issue — the page-routing isn't live until `apply-sentry-infra.yml` runs post-merge.

### Post-merge (operator/automated)
- [ ] **AC15:** `apply-sentry-infra.yml` fires on merge (path filter matches `cron-monitors.tf` + `issue-alerts.tf`), the destroy-guard shows 0 destructive changes (margin widening + rule add are non-destructive), and `terraform apply` succeeds. Verify via the workflow run summary — NO SSH, NO dashboard eyeball.
- [ ] **AC16:** The post-apply `assert-byok-rules-exist.sh` step confirms `high-priority-to-ops` exists in Sentry (read-only API GET, fail-closed). This IS the automated verification that the rule landed.
- [ ] **AC17:** API-GET confirms the 12 cohort monitors now report a 60-min margin (per `hr-no-dashboard-eyeball-pull-data-yourself`): `curl -fsS -H "Authorization: Bearer $TOKEN" "https://${ORG}.sentry.io/api/0/organizations/${ORG}/monitors/" | jq '[.[] | select(.config.checkin_margin == 60)] | length'` ≥ 12.

## Domain Review

**Domains relevant:** Engineering (infra/observability), Legal (GDPR recipient-routing — advisory). Product/UX: NONE.

### Engineering
**Status:** reviewed (plan-author + research agents)
**Assessment:** Pure IaC change against an already-provisioned Sentry root + an existing
auto-apply pipeline. No new server runtime, no new persistent process. The observability blast
radius is the paging path itself, which is exactly why the threshold is single-user-incident and
the liveness-assertion + contract-test gates (Phase 3) are mandatory. CTO probe — *does the new
rule mirror a predicate that already exists in another layer?* The default UI rule it replaces is
being *superseded* by an IaC-owned rule (the user's explicit choice); the UI rule should be
disabled/deleted to avoid double-paging (see Open Questions OQ1).

### Legal (GDPR — advisory)
**Status:** reviewed (advisory)
**Assessment:** CHANGE B changes the `notify_email` *recipient* of an existing processing
activity already in the Article 30 register (Sentry issue-alert notifications & cron monitors).
The new recipient `ops@jikigai.com` is **internal staff** (the operator's own ops inbox), not a
third-party — Art. 28 DPA terms inherit from the existing Sentry processor entry; no new
sub-processor. Pinning to a single Member *narrows* disclosure vs the current `ActiveMembers`
fallthrough at N>1 (a privacy improvement, advancing the #4656 recipient-pinning concern). The
issue-alert payload carries pseudonymized `userIdHash` (scrubbed by `sentry-scrub.ts`), not raw
PII. **Action:** update the Sentry processing-activity entry in
`knowledge-base/legal/article-30-register.md` §(d) Recipients to name `ops@jikigai.com` as the
pinned high-priority routing recipient. Advisory-only; no new processing activity, no Art. 9
special-category data, no lawful-basis change — full `/soleur:gdpr-gate` not triggered
(recipient-routing on an existing internal-staff PA, no schema/migration/auth/API surface).

### Product/UX Gate
**Tier:** NONE — no `## Files to Create`/`## Files to Edit` path matches a UI-surface term
(all edits are `.tf`, `.sh`, `.test.ts`, `.yml`, `.md`). No `.pen` required.

## Infrastructure (IaC)

### Terraform changes
- `apps/web-platform/infra/sentry/cron-monitors.tf` — 12 `checkin_margin_minutes` field
  edits + prose comment update (no new resource).
- `apps/web-platform/infra/sentry/issue-alerts.tf` — 1 new `sentry_issue_alert` resource
  (`high_priority_to_ops`); + (conditional) 1 `sentry_organization_member` data source (default)
  OR resource (fallback).
- Provider: `jianyuan/sentry v0.15.0-beta2` (pinned, `.terraform.lock.hcl` readonly).
- Sensitive vars: none new. Member email `ops@jikigai.com` is non-secret. `SENTRY_AUTH_TOKEN`
  from GitHub repo secret `SENTRY_IAC_AUTH_TOKEN`; R2 backend creds from Doppler `prd_terraform`
  (unchanged).

### Apply path
- (a) cloud-init-only — N/A.
- **(b) auto-apply via `apply-sentry-infra.yml`** on merge to main (path filter already covers
  `cron-monitors.tf` + `issue-alerts.tf`). The saved-plan shape (`plan -target=… -out=tfplan` →
  destroy-guard → `apply tfplan`) means plan-targets == apply-targets; the new rule (+ member
  resource if the fallback path is used) must be added to the `-target` list. **Expected blast
  radius:** non-destructive (12 in-place margin updates + 1 resource create, + 1 more if the
  member-invite resource path is used). Destroy count = 0 → no `[ack-destroy]` needed.
- (c) taint/replace — N/A.

### Distinctness / drift safeguards
- `dev != prd`: Sentry IaC root manages the single prod project (`web-platform` on `jikigai-eu`);
  no dev/prd split for Sentry alerting. The auth-token store divergence (GitHub secret, not
  Doppler) is per ADR-031 §secret-store-divergence.
- `lifecycle.ignore_changes = [environment]` on the new rule (apply-created posture — terraform
  owns conditions/filters/actions; only `environment` recomputes on read). Do NOT add
  conditions/filters/actions to `ignore_changes` (that would recreate the 2026-06-02
  empty-filter catch-all class — the whole point is that terraform is the source of truth).
- State note: `web-platform/sentry/terraform.tfstate` on R2; member internal_id lands in state
  (non-secret).

### Vendor-tier reality check
- `sentry_issue_alert` and `sentry_cron_monitor` are usable in the pinned provider for our
  attribute set (the deprecation warning on `sentry_issue_alert` is accepted until GA per
  ADR-031); `sentry_organization_member` is used only if the invite path is needed.
- **Member-invite scope gate (Phase 0.2):** the `iac-terraform-prd` integration may lack
  `member:admin`. If the data-source path is chosen (member already exists), only
  `member:read`/`org:read` are needed — already in scope. The resource path requires a
  one-time integration permission widen to **Member & Billing: Admin** — recorded here as an
  integration-scope change, NOT a per-apply dashboard click.

## Observability

```yaml
liveness_signal:
  what: "post-apply read-only API GET asserts high-priority-to-ops + the 4 existing
         EXPECTED_RULES exist by name in Sentry; the 12 widened cron monitors continue to
         report check-ins (now within a 60-min margin)"
  cadence: "every apply-sentry-infra.yml run (on every merge touching the sentry root)"
  alert_target: "GitHub Actions workflow failure (fail-closed: assert-byok-rules-exist.sh
                 non-zero exit halts the workflow)"
  configured_in: ".github/workflows/apply-sentry-infra.yml (BYOK liveness step) +
                  apps/web-platform/scripts/assert-byok-rules-exist.sh EXPECTED_RULES"
error_reporting:
  destination: "the new rule IS the error-reporting destination — it routes high-priority
                Sentry issues (errors + cron missed-check-ins) to ops@jikigai.com"
  fail_loud: "yes — un-routed high-priority issues are caught by the liveness assertion;
              a mis-shaped rule (empty conditions, wrong member) surfaces as a terraform
              validate failure pre-merge or a liveness-assertion failure post-apply"
failure_modes:
  - mode: "claude-eval cron runs slow-but-successful (>30, <60 min past schedule)"
    detection: "previously false-paged; AFTER fix, no page (within 60-min margin)"
    alert_route: "n/a — this is the false-positive being eliminated"
  - mode: "claude-eval cron genuinely dead (no heartbeat at all)"
    detection: "missed check-in after 60-min margin"
    alert_route: "Sentry cron-monitor issue -> high-priority-to-ops -> ops@jikigai.com;
                  backstop: scheduled_inngest_cron_watchdog"
  - mode: "new routing rule mis-wired (dropped -target / deleted / name drift)"
    detection: "assert-byok-rules-exist.sh post-apply read-only GET"
    alert_route: "GitHub Actions workflow failure (fail-closed)"
  - mode: "high-priority production error issue"
    detection: "new_high_priority_issue condition fires"
    alert_route: "high-priority-to-ops -> ops@jikigai.com"
logs:
  where: "GitHub Actions run logs for apply-sentry-infra.yml; Sentry issue + alert-rule
          activity log"
  retention: "GitHub Actions default (90d); Sentry per-plan retention"
discoverability_test:
  command: "gh run list --workflow=apply-sentry-infra.yml --limit 1 --json conclusion
            && curl -fsS -H \"Authorization: Bearer $SENTRY_AUTH_TOKEN\"
            \"https://${SENTRY_ORG}.sentry.io/api/0/projects/${SENTRY_ORG}/${SENTRY_PROJECT}/rules/\"
            | jq '[.[] | select(.name==\"high-priority-to-ops\")] | length'"
  expected_output: "workflow conclusion=success; rule-count = 1 (NO ssh)"
```

## Open Code-Review Overlap

`gh issue list --label code-review --state open` was not the discriminator here; the overlap
surfaced from reading the artifacts directly:

- **`kb_sync_silent_failure` is apply-created but NOT in the `-target` list** of
  `apply-sentry-infra.yml` (verified: it's the 12th issue-alert resource, real filters, only
  `environment` ignored, yet absent from every `-target=sentry_issue_alert.*` line). The
  workflow comment at L186-192 documents a *different* orphan (`kb_tenant_mint_silent_fallback`
  deliberately absent pending destroy). `kb_sync_silent_failure`'s absence appears to be an
  unintended gap (its sibling rules ARE targeted). **Disposition: Acknowledge** — out of scope
  for this PR (different concern; adding it to `-target` is a separate apply-correctness fix
  that should be reasoned about on its own, including whether it was deliberately left out).
  Record a 1-line note in the PR body so the reviewer sees it was observed, not missed. Do NOT
  silently fold it in.

## Test Scenarios

1. **Margin widening, cohort-only:** edit 12 resources; `terraform fmt -check` + `validate`
   pass; diff shows exactly 12 margin lines 30→60, zero other margin changes.
2. **New rule schema:** `terraform validate` accepts the `new_high_priority_issue` +
   `existing_high_priority_issue` + `notify_email target_type="Member"` shape (config-time gate).
3. **Contract test:** the new `sentry-high-priority-alert-contract.test.ts` fails if any
   structural invariant drifts (one high-priority condition dropped, `Member`→`IssueOwners`,
   non-unique frequency, name mismatch with the assert script).
4. **Liveness:** `assert-byok-rules-exist.test.sh` passes with `high-priority-to-ops` in
   EXPECTED_RULES against a fixture that includes it; fails when the fixture omits it.
5. **Destroy-guard:** scope-guard + counter tests pass (no new array-of-blocks type unless the
   member *resource* path is chosen — then jq filter + scope-guard extended).

## Open Questions

- **OQ1 — disable the default UI rule.** The user wants high-priority issues routed to
  `ops@jikigai.com` *instead of* "recently active members". The IaC rule ADDS a routing path; it
  does not remove the default UI rule that paged. To avoid double-notification (and to actually
  *replace* the default behavior), the default "Send a notification for high priority issues"
  rule should be disabled/deleted. **Is that in scope?** Options: (a) delete it manually
  (out-of-IaC, a one-time dashboard action — discouraged per the IaC rule); (b) import it into
  terraform state and manage/disable it via IaC; (c) leave both and accept the founder gets two
  notifications for high-priority issues (one to ops@, one to active-members). Recommend (b) or
  surface to the operator. Resolve before /work freezes Phase 2.
- **OQ2 — should the BYOK rules also pin Member?** #4656 defers Member-pinning for
  `byok_art_33_breach` until N>1 seats. This PR introduces the Member-targeting pattern; folding
  the BYOK rules in is tempting but expands scope and touches the GDPR-sensitive Art.33 path.
  Recommend: keep out of scope; note that the pattern is now available for #4656.
- **OQ3 — frequency for a project-wide high-priority rule.** `frequency` on a lifecycle-condition
  rule governs re-notification cadence, not match logic (the dedup learning). 16 is a free slot;
  confirm it does not collide after any concurrent sentry PR merges before this one.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only TBD/TODO/placeholder text,
  or omits the threshold will fail `deepen-plan` Phase 4.6. (Filled above: threshold =
  single-user incident.)
- **The destroy-guard scope-guard keys on resource TYPE, not resource name.** Adding another
  `sentry_issue_alert` to the `-target` list does NOT trip `test-destroy-guard-sentry-scope-guard.sh`
  (the type is already allow-listed). BUT if Phase 2.1 uses the `sentry_organization_member`
  **resource** path, that is a NEW resource type in the `-target` set → the scope-guard's
  `grep -vxE 'sentry_cron_monitor|sentry_uptime_monitor|sentry_issue_alert'` will FAIL it, AND
  `tests/scripts/lib/destroy-guard-filter-sentry.jq` must be extended with a nested-clause for
  the new type (and a fixture added to `test-destroy-guard-counter-sentry.sh`). **Prefer the data-source
  path** precisely to avoid this — a data source is not a `-target` and adds no type.
- **`filters_v2` is OMITTED, not `= []`, and this is the single shape not provable pre-merge**
  (deepen-plan terraform-architect Item 1). Every apply-created rule in the file has a NON-EMPTY
  filter; a project-wide filterless rule is unprecedented here. `terraform validate` blesses the
  config but cannot exercise the apply-time POST round-trip — Sentry may reject an empty filter or
  return a computed default → a *perpetual* `filters_v2` diff on a non-ignored attr. Mitigations:
  (a) Phase 0.1b probes `filters_v2.optional` and prefers omitting the attribute (avoids the
  `[] ↔ null` normalize-on-read trap); (b) the project-wide scope IS the design, NOT the
  2026-06-02 catch-all bug (that was unintended drift frozen under `ignore_changes`); (c)
  `ignore_changes` on `filters_v2` is FORBIDDEN — if a perpetual diff appears post-apply, re-scope
  to a broad real filter, do NOT silence it. State this as the one unprovable-pre-merge shape in
  the PR body.
- **The notify_email member binding is fail-closed-coupled to the member's existence**
  (deepen-plan Item 4): the data-source read errors if `ops@jikigai.com` is ever removed, failing
  the NEXT apply (even a cron-only one). This is the desired posture (better than a rule pointed at
  a dead id) but a real standing coupling — document it. Phase 0.2 probes membership BEFORE
  committing to the data-source path so the first apply never blindly assumes membership.
- **`target_identifier = <placeholder>` is invalid HCL** (deepen-plan Item 5) — `fmt`/`validate`
  hard-fail. Substitute the real `data.sentry_organization_member.ops.internal_id` (or resource
  ref) at write time. Run `terraform fmt` (write mode) before `fmt -check` (AC11).
- **Cohort is `max_runtime_minutes=55`, authoritatively 12 — NOT 13.** A research agent included
  `scheduled_strategy_review`; it has `max_runtime_minutes=10`. Trust the `awk` pairing, not a
  name list.
- **Comment-inside-continuation in the `-target` block is fatal** (the workflow's own L195 note,
  PR #5108): a mid-continuation `#` comment terminates the command and the next `-target=` line
  runs as a bare command (exit 127). Add new targets as plain continuation lines, no inline
  comments.
- **Member-invite scope is NOT obviously in the IaC token** (ADR-031 scope set lacks
  `member:admin`). The data-source path needs only `org:read`/`member:read` (in scope); only the
  resource path needs a scope widen. Resolve in Phase 0.2.
- **`terraform validate` is the pre-merge schema gate; `terraform plan` against live Sentry is
  post-merge.** A `notify_email`/`conditions_v2` shape error is caught by `validate` (config-time)
  per the beta-provider learning — do NOT rely on plan (which needs the IaC token + live API).

## Files to Edit
- `apps/web-platform/infra/sentry/cron-monitors.tf` — 12 margin fields 30→60 + prose comment
- `apps/web-platform/infra/sentry/issue-alerts.tf` — new `high_priority_to_ops` rule (+ member resource/data source)
- `.github/workflows/apply-sentry-infra.yml` — add `-target` for the new rule (+ member resource iff resource path)
- `apps/web-platform/infra/sentry/README.md` — corrected counts + new-rule description + ADR-031 ref
- `apps/web-platform/scripts/assert-byok-rules-exist.sh` — add `high-priority-to-ops` to EXPECTED_RULES + prose
- `apps/web-platform/scripts/assert-byok-rules-exist.test.sh` — fixture includes new rule (keep green)
- `knowledge-base/legal/article-30-register.md` — Sentry PA §(d) Recipients: name ops@jikigai.com (advisory)
- `tests/scripts/lib/destroy-guard-filter-sentry.jq` — ONLY if the member *resource* path is chosen
- `tests/scripts/test-destroy-guard-sentry-scope-guard.sh` — ONLY if the member *resource* path is chosen

## Files to Create
- `apps/web-platform/test/sentry-high-priority-alert-contract.test.ts` — structural-invariant contract test for the new rule
