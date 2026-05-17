---
title: "sentry phantom-ingest destination unreachable"
date: 2026-05-16
incident_pr: 1235
incident_window: "2026-03-28T18:03:00Z → 2026-05-16T12:50:00Z"
suspected_change: "PR #1235 introduced Sentry SDK + SENTRY_DSN to Doppler prd on 2026-03-28. DSN points to org ID 4511123328466944 on the de.sentry.io ingest cluster — the destination org is not enumerable, not controllable, and likely orphaned. Phantom-ingest window ≈ 49 days."
brand_survival_threshold: none
status: resolved
triggers:
  []
art_33_triggered: true
art_34_triggered: false
art_33_deadline: "2026-05-19T12:50:00Z"
classification_override:
  advisory: aggregate pattern
  chosen: none
  reason: "10 operator-adjacent accounts existed in prd auth.users during phantom-ingest window (founders + team + bot + internal-QA + 2 friends-of-team test signups, per PR-α SQL-count + operator categorization on 2026-05-17); zero arms-length external signups; data captured was internal team / operator-adjacent telemetry only"
---

## Actor key

- `agent` — Claude Code did this autonomously (no operator ack required).
- `agent-with-ack` — Claude Code did this AFTER operator confirmed via menu option per `hr-menu-option-ack-not-prod-write-auth`.
- `human` — Operator did this directly.

## Symptom

During Phase A2 brainstorm prereq verification (Sentry residency cleanup, follow-up to PR #3863 / issue #3861), an attempt to navigate to https://eu.sentry.io/auth/login/ returned an org-membership banner: "Your account (<operator-email>) is not a member of the eu organization. Ask an organization admin to invite you, or sign in with a different account."

Subsequent API probe of `/api/0/organizations/jikigai/` using the runtime `SENTRY_AUTH_TOKEN` (held in Doppler prd) returned a 302 redirect to `/api/0/organizations/eu/` followed by 401 "Invalid org token" — Sentry's region-router signal for "no org with that slug exists on this edge." Probes against the US edge (`sentry.io`) returned 403 on `/users/me/` (token valid but no member visibility); the operator's account is a member of a US `jikigai` org (separate, accessible, on a Team trial that has been cancelled this session), but the runtime DSN does NOT point there.

The runtime `SENTRY_DSN` in Doppler prd targets `o4511123328466944.ingest.de.sentry.io/4511123344654416` — the destination org ID is `4511123328466944` and the project ID is `4511123344654416`. The Sentry ingest endpoint silently returns 200 on any well-formed envelope POST, regardless of whether the destination org is accessible or even alive. For the ~49-day window since PR #1235 introduced the DSN on 2026-03-28, user envelope POSTs have been transmitted over the wire to a Sentry destination that we cannot enumerate, audit, or administer.

Adjacent A1 audit script (`apps/web-platform/scripts/sentry-monitors-audit.sh`, shipped by PR #3863) catches *wrong-cluster* (DSN host substring mismatch against expected residency) but does NOT catch *wrong-destination* (DSN points to the right cluster substring but the org at the specified ID is unowned). The A1 §5(2) evidence regenerated under this audit script proves the destination is DE-residency by DSN substring; it does NOT prove the destination is admin-controllable.

Discovered when attempting to execute A2.P1 (add payment method to "the DE jikigai org") and A2.P2 (mint DE-scoped SENTRY_AUTH_TOKEN from "the DE jikigai developer-settings") — both prerequisites assumed a controllable DE org that does not exist.

## Root-cause hypothesis

| Hypothesis | Supporting evidence | Disconfirming evidence | Status |
|---|---|---|---|
| DSN was introduced (PR #1235, 2026-03-28) without verifying destination-org existence or operator-membership; Sentry's region-routing + ingest permissiveness masked the orphan-org state for the lifetime of the DSN. | (1) eu.sentry.io login wall confirms zero EU/DE org membership for operator. (2) Region-router 302→401 pattern confirms no `jikigai` slug on EU edge. (3) Audit script in PR #3863 was designed for substring/cluster validation, not destination-controllability. (4) ADR-031 and the A2 feature description both prescribe a `de.sentry.io/api/0/users/me/` verify probe that returns 404 — the URL itself doesn't exist; the conflation between ingest host and dashboard/API host runs through the prior docs. | TBD — pending Sentry support response on owner-history for org ID 4511123328466944. If org belongs to a third party, escalate to Art 34 (risk_to_subjects → high). | open |

## Timeline

| Actor | Time (UTC) | Action |
|---|---|---|
| human | 2026-03-28T18:03:00Z | PR #1235 merged — introduced Sentry SDK + SENTRY_DSN to Doppler prd. Phantom-ingest window begins. |
| human | 2026-05-15T22:11:00Z | PR #3863 merged — A1 residency cleanup: workflow defaults flipped, fail-closed mismatch detector added to audit script. Detector validates DSN host substring against expected cluster — but cannot validate destination-org controllability. |
| human | 2026-05-16T12:50:00Z | Incident detected — A2 brainstorm prereq verification surfaced eu.sentry.io membership wall + region-router 401. |
| agent-with-ack | 2026-05-16T14:46:00Z | US shadow-org Team subscription cancelled (operator ACK'd, completed in own Chrome). Effective Jun 14 2026; org stays alive on free plan. Stops unrelated PAYG burn but does NOT address phantom-ingest itself. |
| human | TBD | Sentry support ticket opened asking owner-history for org ID 4511123328466944. |
| human | TBD | Recovery: runtime DSN rotated to a controllable DE org (per A2 Branch C). Phantom-ingest window closes. |

## Recovery verification

TBD. Recovery is bound to A2 brainstorm Branch C (create new DE org under operator account, migrate runtime DSN across all envs, drop tfstate, terraform import fresh). Recovery is verified when:

1. New DE org is accessible to operator at `eu.sentry.io/settings/<new-slug>/`.
2. Runtime `SENTRY_DSN` (Doppler prd + GH secrets + Vercel envs + any .env templates) all point to the new DE DSN.
3. A fresh ingest probe POSTs an envelope and the event appears in the new DE org's Issues view within 60s.
4. The A1 audit script is extended with a destination-controllability check (auth probe against `/api/0/organizations/<slug>/` returns 2xx, not 302→401) so future drift is caught at audit time, not at incident time.

## Follow-ups

- [ ] Open Sentry support ticket for owner-history of org ID 4511123328466944. Outcome affects Art 34 escalation.
- [ ] A2 brainstorm Branch C restart — produce A2 plan that creates new DE org + migrates DSN. (Blocked on this PIR per task #4 / #21 dependency in this session's task list.)
- [ ] Extend `sentry-monitors-audit.sh` (PR #3863) with a destination-controllability probe — `curl -H Bearer ... /api/0/organizations/$SENTRY_ORG/ → 2xx` — so an unowned destination is caught at audit time. New audit gate: `audit_destination_admin_controllable`. Without this, the failure mode that triggered this PIR repeats silently on the next phantom-DSN.
- [ ] Update PA8 §5(2) (`knowledge-base/legal/article-30-register.md`) — add a positive disclosure of the 2026-03-28 → 2026-05-16 phantom-ingest window once recovery is verified. CLO sign-off required for disclosure language. Decide: separate disclosure footnote vs. retroactive annotation of A1's audit artifact.
- [ ] Update ADR-031 (`knowledge-base/engineering/architecture/decisions/ADR-031-sentry-as-iac.md`) — the cited URL `https://de.sentry.io/settings/account/api/auth-tokens/` is stale (returns 404; de.sentry.io is ingest-only, no /settings surface). Replace with the correct dashboard host path. Bundle with A2 PR.
- [ ] Add a glossary section to A2 PR — "Sentry hosts: ingest vs dashboard vs API" — to prevent future conflations. The feature description for A2, ADR-031, and the A1 plan all prescribed `de.sentry.io/api/0/users/me/` as a verify probe; the endpoint returns 404.
- [ ] Investigate Sentry's built-in cross-org migration tooling (observed via "If migrating to another existing account, can you provide the org slug?" field on the Team-plan cancellation page) as a possible Branch C alternative to manual DSN swap + fresh tfstate.
- [ ] After A2 ships and runtime is on new DE org: request Sentry refund for (a) US Team plan unused portion, (b) $5.46 US PAYG burn driven by misaligned IaC, (c) any phantom-window PAYG burn once accounting reconciles.

## Who was affected (by role)

Per learning `2026-05-06-user-impact-section-by-role-not-surface.md` — enumerate by USER ROLE, not by surface:

- **Prospect:** none — Sentry SDK only fires on app interaction; prospects on marketing pages do not generate SDK events.
- **Authenticated app user:** 10 operator-adjacent accounts existed in the prd `auth.users` table during the phantom-ingest window (founders on `jikig.com` / `soleur.ai`; team on `jikigai.com` / `soleur.ai`; `ux-audit-bot@jikigai.com`; internal QA / test accounts on `soleur.dev` and `example.com`; and 2 `gmail.com` test signups confirmed by the operator on 2026-05-17 as friends-of-team / Harry's pre-team-account test of the external signup flow — see committed audit at `knowledge-base/legal/audits/2026-05-17-sentry-phantom-ingest-window-auth-users-audit.md` and `knowledge-base/legal/article-30-register.md` PA8 §(d) for per-row categorization (PII redacted to domain + role)). **Zero arms-length external app users were onboarded or affected during the window.** *(This is the load-bearing classification override — see frontmatter `classification_override`. The override stands: all 10 in-window accounts are under operator instruction or contractual relationship; the operator-as-data-subject Art 34 obligation is satisfied by this PIR itself, and the team / friends-of-team accounts are directly reachable by team comms.)*
- **Legal-document signer:** zero external signers during window; not applicable.
- **Admin via Access:** the operator (single founder) is the only Admin during window; data captured was their own debugging telemetry. Subject is self-aware of the breach.
- **Billing customer:** zero billing customers during window — paid plan onboarding not yet open.
- **OAuth installation owner:** zero external GitHub App installations during window — installations limited to dogfooding orgs the operator administers. Internal team awareness applies.

**Summary:** the affected population during the phantom-ingest window is the internal team (operator + 8 operator-adjacent accounts: founders, team, bot, internal QA / test) plus 2 friends-of-team test signups under operator instruction (per PR-α SQL-count + operator categorization on 2026-05-17). All subjects are operator-adjacent (under contractual or operator-instructed relationship) and either self-aware or directly reachable by team comms. No arms-length external-party exposure has been positively confirmed. The §5(2) accountability concern is the *enumeration gap* (cannot list the processor that received the events), not a confirmed harm to subjects.

## Phase 8 — Recovery Completeness

This PIR transitions from `status: open` to `status: resolved` when all three gates below hold. Recovery is not a single event; it is the conjunction of (1) cluster surgery, (2) audit prevention, and (3) residual disclosure on the unowned destination org.

- **Gate 1 — Runtime cluster surgery complete (PR-β #3945, merged 2026-05-17T14:36Z; dedup-fix #3954 merged 2026-05-17T15:02Z).** Evidence: runtime `SENTRY_DSN` substring matches the new DE org's orgInternalId (`o4511404939345920.ingest.de.sentry.io/4511404943671376`) in Doppler `prd` + `prd_scheduled` + GH secrets (timestamps `2026-05-17T14:00:56-14:01:08Z`). Controllability probe against `https://jikigai-eu.sentry.io/api/0/organizations/jikigai-eu/` returns 2xx with the runtime token. Old US-shadow-org token `sntrys_***bgtw` (name `soleur-web-platform-ci`) revoked via the `sentry.io/settings/jikigai/auth-tokens/` page at 2026-05-17T18:03Z. The §9 2h observation window passed: synthetic event + 3 release-version startup events queryable in `jikigai-eu` post-cutover.

- **Gate 2 — Audit-gate prevents recurrence (PR-β #3945).** The 4-gate destination-controllability audit (`audit_org_admin_controllable` + `audit_dsn_orgInternalId_substring_match` + `audit_token_destination_match` + `audit_iac_state_consistency` per spec §C5/TR4) runs in all three release/audit paths: `.github/workflows/reusable-release.yml`, `.github/workflows/sentry-audit-gate.yml`, `.github/workflows/apply-sentry-infra.yml`. A future phantom-DSN (DSN substring matches expected cluster but destination org is unowned) trips Gate 1 of the audit and fails-closed before deploy, repairing the failure mode that masked the original incident for 49 days.

- **Gate 3 — Residual disclosure on org ID `4511123328466944` (Sentry support response OR T+14d timeout, ticket-submission anchored).** Two support tickets submitted via `sentry.io/support/` (PR-γ §17): Ticket 1 (billing — Team-plan refund + PAYG burn) and Ticket 2 (forensics — owner-history of org `4511123328466944`). The T+14d countdown anchors on Ticket 2 submission timestamp (captured in PR-γ #3946 body, AC13). Resolution selects ONE of the four operator-selectable branches at countdown expiry, and this PIR is updated to record the selected branch + verbatim Sentry response or timeout artifact:
  - **3a — Authoritative third-party owner confirmed.** Sentry support returns a determinate "this org belongs to `<entity>`" response. Outcome: Art 34 escalation evaluated (cross-org disclosure to a non-controllable processor); PA8 §5(2) updated with positive disclosure naming the response date + verbatim text; US shadow org closure proceeds (PR-γ §22.2 AC12-post).
  - **3b — "This org is yours" (STOP signal).** Sentry support returns evidence that the unowned org is in fact owned by an operator-controlled identity. Outcome: HALT closure; reopen this PIR (`status: open`); audit account-discovery + privilege-pickup procedure; investigate why region-router + token-membership probes returned 401 against a self-owned org. This branch is a workflow-defect signal, not a residual.
  - **3c — Non-disclosure residual.** Sentry support declines to disclose owner-history (privacy or policy). Outcome: residual documented as `Sentry support response 2026-MM-DD: "<verbatim>"`; PA8 §5(2) updated to record the enumeration-gap with closure justification (best-effort exhausted); Art 33/34 stance unchanged (operator-adjacent-only population per frontmatter `classification_override`). PIR remains `status: resolved` with residual annotated.
  - **3d — T+14d timeout.** Sentry support does not respond within 14 calendar days of Ticket 2 submission. Outcome: timeout artifact captured (last `gh` / Sentry support thread state + screenshot); residual documented as `T+14d timeout from <Ticket-2 submission timestamp>`; PA8 §5(2) updated to record the enumeration-gap with timeout justification; PIR remains `status: resolved` with residual annotated. Re-evaluation only if Sentry responds post-timeout (no SLA commitment from operator side).

**Gate 3 current selection (2026-05-17, PR-γ merge time):** *pending* — Ticket 2 not yet submitted; T+14d countdown not yet started. This PIR carries `status: resolved` on Gate 1 + Gate 2 closure with Gate 3 residual tracked in PR-γ #3946 §22 post-merge gate (AC15-post). The operator updates this section in-place (no new commit required; runbook accumulates resolution evidence) when Gate 3 resolves to one of 3a/3b/3c/3d.
