---
title: "feat: chat write-absence liveness alert (Sentry op:persist-user-message)"
date: 2026-06-03
issue: 4849
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
brainstorm: knowledge-base/project/brainstorms/2026-06-03-chat-write-absence-alert-brainstorm.md
spec: knowledge-base/project/specs/feat-chat-write-absence-alert/spec.md
follow_up: 4854
---

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
<!-- All infrastructure is Terraform-routed: one apply-created sentry_issue_alert
     in apps/web-platform/infra/sentry/issue-alerts.tf, applied via the existing
     apply-sentry-infra.yml on merge to main. No manual/operator provisioning. -->

# ✨ feat: Chat Write-Absence Liveness Alert

## Overview

Catch a silent chat write-path outage by **instrumentation**, not by a user
report. `dispatchSoleurGo` (`apps/web-platform/server/cc-dispatcher.ts`) has **three**
fail-and-throw sites that each block an interactive message from persisting,
all tagged `feature = "cc-dispatcher"` via `reportSilentFallback`:
`op = "tenant-mint.persistUserMessage"` (:1455-1460, tenant client mint fails),
`op = "persistUserMessage.workspaceRead"` (:1475-1482, parent conversation
`workspace_id` read fails), and `op = "persist-user-message"`
(`CC_OP_SLUGS.persistUserMessage`, :1500-1505, the INSERT itself fails). All
three **throw** → the user's message is not saved. The 3-week outage hit the
INSERT site (PIR quotes `"new row violates row-level security policy for table
messages"` = the :1502 WITH-CHECK reject; `workspace_id` RLS, PR #4831; later
`template_id` NOT-NULL `23502`, PR #4848). The signal existed the whole time but
**no alert rule watched it** (PIR contributing factor 2).

The MVP adds **one apply-created `sentry_issue_alert`** that fires on **any of
the three insert-blocking ops** (`op IS_IN` the three slugs + `feature EQUAL
cc-dispatcher`), modeled byte-for-byte on the `byok_art_33_breach` precedent
(`issue-alerts.tf:203-282`). Scoping to only the INSERT slug would leave the two
sibling failure paths (identical user outage) unpaged — a `single-user incident`
window the brand-survival threshold forbids deferring. It pages the founder on
the **first** failed save and re-pages on recurrence. No prod DB read, no new
credential, no new data egress — the alert fires on events Sentry already captures.

Inverted framing (unanimous across CPO/CTO/CLO in brainstorm): alert on
**attempted-but-failed writes**, global, not a per-workspace silence timer. The
scheduled prod write-absence probe (issue's "Option A") is **deferred to #4854**.

## Research Reconciliation — Spec vs. Codebase

| Spec/issue claim | Codebase reality | Plan response |
|---|---|---|
| Alert on op `Failed to save user message` | That string is only the thrown `Error.message` (`cc-dispatcher.ts:1505`); the queryable tags are 3 op slugs (`tenant-mint.persistUserMessage` :1457, `persistUserMessage.workspaceRead` :1477, `persist-user-message`/`CC_OP_SLUGS.persistUserMessage` :292/:1502), all `feature = cc-dispatcher`, all throw | Filter on `feature EQUAL cc-dispatcher` + `op IS_IN` the 3 slugs (SpecFlow P2: covers the whole insert-blocking class, not just the INSERT) |
| `EventFrequencyCondition` window/count threshold (issue body) | Repo precedent (`byok_art_33_breach`) uses issue-lifecycle conditions: `first_seen_event` + `reappeared_event` + `regression_event`, `action_match = "any"` | Adopt issue-lifecycle model — pages on first failure (best at 0–1 users); **dissolves the threshold-tuning open question** |
| "Reuse issue-alerts.tf" (brainstorm) | Adding a `sentry_issue_alert` also requires a `-target=` entry in `apply-sentry-infra.yml:186-215`, else it never applies | Add `-target=sentry_issue_alert.chat_message_save_failure` (Files to Edit #2) |
| Guard-suite sweep for the `-target` allowlist (Sharp Edge `2026-05-29-...`) | `sentry_issue_alert` is **already** allow-listed in `test-destroy-guard-sentry-scope-guard.sh` and has a nested-clause in `destroy-guard-filter-sentry.jq` (both #4364). Same type → no edit | No jq/scope-guard/counter edit; documented in Phase 0 |

## User-Brand Impact

**If this lands broken, the user experiences:** a future chat write-path
regression (a third un-swept required column, a new RLS policy, a dispatch
throw) silently drops every interactive message save and the operator is not
paged — users lose chat for an extended window, exactly as in the source PIR.

**If this leaks, the user's data is exposed via:** the alert notification email.
`workspace_id == owner_user_id` for solo workspaces (ADR-038 N2), so it is
personal data. The existing emit already sends `extra: { userId, conversationId }`
to Sentry (this PR adds no new field); the alert email must not surface raw
identifiers or message content.

**Brand-survival threshold:** single-user incident.

CPO sign-off: carried forward from brainstorm Phase 0.1 (CPO assessed the idea;
`USER_BRAND_CRITICAL=true` triad ran). `user-impact-reviewer` runs at PR review.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1** — `issue-alerts.tf` gains exactly one `sentry_issue_alert`
  ("chat_message_save_failure") with `action_match = "any"`, `filter_match = "all"`,
  a free `frequency` (NOT in {5,15,30,60,61,62}), `conditions_v2` =
  [first_seen_event, reappeared_event, regression_event], `filters_v2` =
  [`tagged_event` feature EQUAL cc-dispatcher, `tagged_event` op IS_IN
  "tenant-mint.persistUserMessage,persistUserMessage.workspaceRead,persist-user-message"],
  `actions_v2` = notify_email IssueOwners→ActiveMembers,
  `lifecycle.ignore_changes = [environment]`. (`IS_IN` valid in beta2 per
  `byok_cap_exceeded:310`.)
- [ ] **AC2** — The `terraform plan` step in `apply-sentry-infra.yml` includes
  `-target=sentry_issue_alert.chat_message_save_failure`. Verify the target is in
  the plan block specifically (SpecFlow P2): `awk` the `Terraform plan` step
  region and assert the `-target` line is present there (not merely anywhere in
  the file / a comment).
- [ ] **AC3** — Contract test pins both filter dimensions against drift (SpecFlow
  P1 + Kieran P2): asserts the literal `"cc-dispatcher"` and all three op-slug
  literals (`tenant-mint.persistUserMessage`, `persistUserMessage.workspaceRead`,
  `persist-user-message`) appear in BOTH `issue-alerts.tf` AND `cc-dispatcher.ts`
  via plain whole-file substring match. NOTE (Kieran P2): `persist-user-message`
  lives at the `CC_OP_SLUGS` const definition (`cc-dispatcher.ts:292`), NOT at the
  emit site (`:1502`, which references the constant) — a whole-file match finds
  it; the two siblings are inline literals at `:1457`/`:1477`. No TS const/AST
  resolution needed (code-simplicity). (Discovery-glob verified per Phase 0.)
- [ ] **AC4** — `assert-byok-rules-exist.sh` `EXPECTED_RULES` (array at `:49`)
  gains `chat-message-save-failure`, and the header is retitled from "BYOK Art. 33"
  to issue-alert detector liveness. Kieran P1: the helper test
  `assert-byok-rules-exist.test.sh` is an **array-membership loop, NOT a count** —
  its T1 positive fixture (`:40-46`) MUST gain the new slug or T1 regresses red.
  (A dedicated new-rule absence case is optional, not MVP-required — avoid
  testing-the-test per code-simplicity.)
- [ ] **AC5** — `sentry-monitors-audit.sh` passes; Phase 0 step 3 determines if
  the new rule needs an audit-allowlist entry (add only if required — real work,
  conditional). (Verification-only, NOT a deliverable per DHH: the
  `test-destroy-guard-sentry-scope-guard.sh` + `destroy-guard-filter-sentry.jq`
  need NO edit — same `sentry_issue_alert` type, already allowlisted; verified at
  `test-destroy-guard-sentry-scope-guard.sh:52`.)
- [ ] **AC7** — No raw `workspace_id` / message content / email added to any
  alert payload by this PR (FR4); recipient-pinning N=1 accepted-risk note
  mirrors `byok_art_33_breach:259-269`.
- [ ] **AC8** — PR body uses `Closes #4849` (code-class fix, applies on merge via
  `apply-sentry-infra.yml`; the alert is apply-created so merge IS the apply).

### Post-merge (operator)

- [ ] **AC9** — On merge, `apply-sentry-infra.yml` fires (path filter already
  includes `issue-alerts.tf:48`), the destroy-guard passes (0 destroys), apply
  creates the rule, and the post-apply `assert-byok-rules-exist.sh` step confirms
  `chat-message-save-failure` exists. Verify via the workflow run log + a
  read-only Sentry `/rules/` GET (no SSH).

## Implementation Phases

### Phase 0 — Preconditions (verify before editing)

1. `terraform providers schema -json` (or read existing rules) confirm
   `first_seen_event`/`reappeared_event`/`regression_event` + `tagged_event`
   `EQUAL` are valid under `jianyuan/sentry` 0.15.0-beta2 (already proven by
   `byok_art_33_breach`).
2. Pick the free `frequency` integer (taken: 5,15,30,60,61,62 → use e.g. `10`).
3. Read `sentry-monitors-audit.sh` — determine if a new apply-created issue
   alert needs an allowlist entry in the 4-gate destination-controllability
   check. Record the answer (edit only if required).
4. Confirm the contract-test path matches the web-platform vitest `include:`
   glob (`apps/web-platform/vitest.config.ts` → `test/**/*.test.ts`) — place the
   test under `apps/web-platform/test/`, NOT co-located.

### Phase 1 — The alert resource (RED→GREEN)

1. Write the cross-artifact contract test first (`apps/web-platform/test/
   sentry-chat-alert-op-contract.test.ts`): read both files and assert (a) the
   `feature` filter value == `"cc-dispatcher"` (present in `.tf` and at the 3
   emit sites), and (b) the `op` IS_IN value set == the 3 emitted slugs
   (`tenant-mint.persistUserMessage`, `persistUserMessage.workspaceRead`,
   `CC_OP_SLUGS.persistUserMessage`). Pins BOTH filter dimensions (SpecFlow P1).
   RED (resource doesn't exist yet) → GREEN after step 2.
2. Add `resource "sentry_issue_alert" "chat_message_save_failure"` to
   `issue-alerts.tf` per AC1, with a SHORT header comment — port ONLY the
   `action_match=any` recurrence rationale + the N=1 recipient-pinning note
   (`issue-alerts.tf:259-269`). Do NOT import byok's Art. 33 / `mirrorP0Deduped`-TTL
   rationale — this path has neither (3-reviewer agreement: comment-bloat caution).

### Phase 2 — Wire the apply + liveness

1. Add `-target=sentry_issue_alert.chat_message_save_failure` to the plan step
   in `apply-sentry-infra.yml` (alongside the two byok targets, ~:213-214).
2. Add `chat-message-save-failure` to `assert-byok-rules-exist.sh` `EXPECTED_RULES`
   (`:49`); retitle the header to "issue-alert detector liveness". Add the slug to
   the T1 positive fixture (`:40-46`) in `assert-byok-rules-exist.test.sh` —
   array-membership, NO count bump (Kieran P1).

### Phase 3 — Docs + guard-sweep evidence

1. Update `ADR-031-sentry-as-iac.md` resource inventory to list the new
   apply-created issue alert.
2. Record in the PR body that the `-target` guard-suite sweep ran and found no
   jq/scope-guard/counter edit needed (same `sentry_issue_alert` type).

## Files to Edit

- `apps/web-platform/infra/sentry/issue-alerts.tf` — add the alert resource.
- `.github/workflows/apply-sentry-infra.yml` — add the `-target=` entry.
- `apps/web-platform/scripts/assert-byok-rules-exist.sh` — extend `EXPECTED_RULES`.
- `apps/web-platform/scripts/assert-byok-rules-exist.test.sh` — update fixture/expectation.
- `knowledge-base/engineering/architecture/decisions/ADR-031-sentry-as-iac.md` — inventory.
- (conditional) `apps/web-platform/scripts/sentry-monitors-audit.sh` — allowlist, if Phase 0 step 3 requires.

## Files to Create

- `apps/web-platform/test/sentry-chat-alert-op-contract.test.ts` — slug↔filter-value contract test.

## Infrastructure (IaC)

### Terraform changes
- File: `apps/web-platform/infra/sentry/issue-alerts.tf` (existing root). One new
  `sentry_issue_alert.chat_message_save_failure`. Provider `jianyuan/sentry`
  0.15.0-beta2 (pinned, lockfile readonly). No new variables (reuses
  `var.sentry_org`, `data.sentry_project.web_platform`).

### Apply path
- (a) apply-on-merge: `apply-sentry-infra.yml` already triggers on
  `issue-alerts.tf` changes (`:48`) and `-target`s the apply-created issue
  alerts. The merge IS the apply. Blast radius: one CREATE, zero destroys
  (destroy-guard enforces). No downtime (additive paging rule).

### Distinctness / drift safeguards
- `lifecycle.ignore_changes = [environment]` (provider recomputes env on read
  for project-wide rules). `conditions_v2/filters_v2/actions_v2` are
  Terraform-owned (the point of the rule). Distinct `frequency` avoids Sentry
  POST-time exact-duplicate dedup. Post-apply `assert-byok-rules-exist.sh`
  proves liveness. State lands in the Sentry IaC R2 backend (no secret values
  in this resource).

### Vendor-tier reality check
- N/A — Sentry issue alerts are not tier-gated (the auth + byok rules already
  exist on the same project/plan).

## Observability

```yaml
liveness_signal:
  what: "post-apply read-only Sentry /rules/ GET asserts chat-message-save-failure exists by name"
  cadence: "every apply that touches issue-alerts.tf (assert-byok-rules-exist.sh post-apply step)"
  alert_target: "GitHub Actions job failure (fail-closed, non-zero exit halts the workflow)"
  configured_in: "apps/web-platform/scripts/assert-byok-rules-exist.sh + apply-sentry-infra.yml post-apply step"
error_reporting:
  destination: "the alert IS the error-reporting surface — it pages on op:persist-user-message Sentry events (reportSilentFallback → captureException, observability.ts)"
  fail_loud: "yes — notify_email IssueOwners→ActiveMembers pages the founder on first_seen/reappeared/regression"
failure_modes:
  - mode: "op slug renamed in cc-dispatcher.ts without updating the alert filter"
    detection: "cross-artifact contract test (AC3) fails in CI"
    alert_route: "CI red on PR"
  - mode: "rule dropped from -target / deleted / muted in Sentry"
    detection: "post-apply assert-byok-rules-exist.sh existence check"
    alert_route: "GitHub Actions job failure"
  - mode: "Sentry-UI mute/tag-drift between applies (residual window)"
    detection: "self-heals on next apply (filters Terraform-owned); deferred recurring-liveness cron is #4854-adjacent"
    alert_route: "next apply re-asserts"
  - mode: "rule exists but its single notify_email action removed via the Sentry UI (SpecFlow P2)"
    detection: "name-only existence check (AC4) passes; self-heals next apply (actions_v2 Terraform-owned)"
    alert_route: "next apply re-asserts — acknowledged MVP residual"
logs:
  where: "GitHub Actions run logs for apply-sentry-infra.yml; Sentry issue stream for op:persist-user-message"
  retention: "GitHub Actions default; Sentry project retention"
discoverability_test:
  command: "curl -fsS -H \"Authorization: Bearer $SENTRY_AUTH_TOKEN\" \"https://$SENTRY_API_HOST/api/0/projects/$SENTRY_ORG/$SENTRY_PROJECT/rules/\" | jq -e '[.[]|select(.name==\"chat-message-save-failure\")]|length==1'"
  expected_output: "exit 0 (rule present); no ssh"
```

## Open Code-Review Overlap

None — no open `code-review` issues reference `issue-alerts.tf`,
`apply-sentry-infra.yml`, `assert-byok-rules-exist.sh`, or `ADR-031`.

## SpecFlow Analysis

spec-flow-analyzer (Phase 3) — proxy-vs-invariant SOUND (event captured ⟹ a save
threw; single-shot insert, no retry-then-succeed), CI-wiring SOUND, recurrence
re-paging SOUND (no `mirrorP0Deduped` TTL on this path → strictly better re-paging
than byok). Findings folded in:

| Sev | Gap | Disposition |
|---|---|---|
| P1 | Contract test pinned `op` but not `feature`; `filter_match=all` ⇒ `feature` drift silently zeroes matches | **Folded** → AC3 pins both |
| P2 | Sibling insert-blocking ops (`tenant-mint.*` :1457, `*.workspaceRead` :1477) = same outage, were excluded | **Folded** → `op IS_IN` 3 slugs (AC1); verified both throw + carry `feature=cc-dispatcher` |
| P2 | Confirm cited PIR outage hit :1502 not :1477 | **Verified** → PIR quotes "new row violates RLS policy for table messages" = :1502 INSERT; widening covers both regardless |
| P2 | AC2 grep not scoped to the plan block | **Folded** → AC2 asserts target in the `terraform plan` step region |
| P2 | AC4 name-only check passes if `notify_email` action removed via Sentry UI | **Acknowledged** → self-heals next apply (added to observability `failure_modes`) |

## Domain Review

**Domains relevant:** Product, Engineering, Legal (carried forward from brainstorm `## Domain Assessments`)

### Engineering (CTO)

**Status:** reviewed (carry-forward)
**Assessment:** Option B (Sentry alert on the failure op) is signal-viable — the
insert throws → `op:persist-user-message` + `pg_code`. Recommended as MVP; the
scheduled probe needs an out-of-band attempt signal (`user_concurrency_slots`,
not `conversations.last_active`) and prd-read infra → deferred. Biggest risk for
the deferred probe is a detection tautology; not applicable to the MVP (no DB read).

### Legal (CLO)

**Status:** reviewed (carry-forward)
**Assessment:** Founder-grade; no specialist threshold tripped. Load-bearing
guardrail: alert payloads carry no raw `workspace_id` (== user UUID for solo
workspaces), content, or email. This PR adds no new processing — it fires on
already-captured events. For the deferred probe: aggregates-only SECURITY DEFINER
RPC + one-line Article 30 PA-2 TOM note.

### Product/UX Gate

**Tier:** none
**Decision:** N/A — no UI surface. Files are `.tf`, `.yml`, `.sh`, a `.ts` test,
and `.md`. Mechanical UI-surface override did not fire (no `components/**/*.tsx`,
`app/**/page.tsx`, or layout files). Global-aggregate, founder-paged per CPO.
**Pencil available:** N/A (no UI surface)

## Risks & Mitigations

- **Op-slug drift silently blinds the alert** → AC3 contract test pins it.
- **Rule never applied (missing `-target`)** → AC2 + the scope-guard pattern;
  post-apply existence check (AC4/AC9) catches a dropped target.
- **Recipient over-disclosure at N>1 Sentry seats** → N=1 accepted-risk note
  mirroring `byok_art_33_breach`; revisit recipient pinning before the second seat.
- **Provider deprecation warning** (`sentry_issue_alert` → `sentry_alert`) is
  EXPECTED and accepted until provider GA (#4610) — do not migrate (see
  `issue-alerts.tf:16-39`).

## Non-Goals

- Scheduled prod write-absence probe (deferred → #4854).
- Per-workspace alerting / silence-timer model.
- (Note: filtering only the INSERT op was considered and **rejected** — the two
  sibling insert-blocking ops are folded in via `IS_IN` per the single-user-incident
  anti-pattern Sharp Edge. Not a Non-Goal.)
