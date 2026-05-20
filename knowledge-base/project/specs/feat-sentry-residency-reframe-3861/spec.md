---
title: "Sentry residency reframe — falsified-premise correction"
date: 2026-05-19
parent_issue: 3861
bundled_issues: [3861, 3962, 3849]
draft_pr: 4044
brand_survival_threshold: single-user incident
lane: cross-domain
triad: [CPO, CLO, CTO]
brainstorm: knowledge-base/project/brainstorms/2026-05-19-sentry-residency-reframe-3861-brainstorm.md
---

## Problem Statement

On 2026-05-17, Soleur shipped a 3-PR series (PR-α #3904, PR-β #3945, PR-γ #3946) under issue #3861 that framed an internal Sentry residency-cleanup incident as a 49-day "phantom-ingest to an unowned third-party Sentry organization" event. That framing committed affirmative public-facing legal disclosure to `knowledge-base/legal/article-30-register.md` PA8 §(d), a PIR flagged `art_33_triggered: true` with a deadline anchored on a notional sub-processor breach, and supporting corpus across ADR-031, learnings, audit scripts, and a SQL-count audit of the prd `auth.users` table.

On 2026-05-19, two Sentry support replies materially falsified the core premise:

1. **Billing reply:** "Both orgs `jikigai` and `jikigai-eu` are both using the EU databases."
2. **Forensics reply (Rodolfo):** "I checked the information from the Jikigai organisation (ID: 4511123328466944) and confirmed that your user `jean.deruelle@jikigai.com` is currently the owner of this organisation. ... This organisation is also owned by you. I checked the audit logs for both organisations and all actions were performed by your user. I do not see any indication that either organisation was owned by other entities other than you."

Per PIR Phase 8 Gate 3b prescription (already committed at the PIR line 100): "HALT closure; reopen PIR (`status: open`); investigate why region-router + token-membership probes returned 401 against a self-owned org. This branch is a workflow-defect signal, not a residual."

The committed Article 30 §(5)(2) recipient-drift disclosure currently reads as an affirmative public-record claim of a sub-processor incident that did not occur. A regulator or DPA reading it today would conclude Soleur had a third-party recipient-drift event and ask why no Art-33 notification was issued — a question we cannot answer truthfully because the event did not happen.

The probable root cause of the original 401 / discovery failure is **token-scope mismatch** (runtime `SENTRY_AUTH_TOKEN` was scoped only for the `jikigai-eu` slug, not `jikigai`), compounded by misreading Sentry's URL routing topology (`jikigai.sentry.io` is the URL front door for an EU-database org Jean already owned; it is NOT the same surface as `eu.sentry.io/jikigai`). This is the inference the corpus correction rests on; it must be empirically verified before any doc correction lands.

## Goals

- **G1.** Empirically verify the token-scope theory via a 3-step probe (CTO-authored sequence) and commit the probe report as first-party §5(2) accountability evidence.
- **G2.** Reopen the PIR per Gate 3b prescription, strike the Art-33 deadline + triggered flags (anchored on a non-event), and append a dated Gate-3b correction section.
- **G3.** Retract-in-place the PA8 §(d) recipient-drift disclosure in the Article 30 register with a dated `[2026-05-19 UPDATE: ...]` block pointing forward to the corrected PIR. Preserve original via git history.
- **G4.** Sweep supporting corpus (auth.users audit, ADR-031, host glossary, learnings) with revise-in-place corrections; keep all factually-still-true claims, drop recipient-drift causal narrative.
- **G5.** Settle the Sentry billing thread by replying with "transfer credit to jikigai-eu" path; operator transmits card-last-4 + expiry directly.
- **G6.** Land the corrections in two PRs (PR-1 urgent: probe + PIR reopen; PR-2 deliberate: full corpus sweep) with PR-2 explicitly blocked-by PR-1.

## Non-Goals

- **N1.** Reverting the operational cutover to `jikigai-eu`. CTO confirmed: cleaner state regardless of original framing; reverting costs another 7-secret-surface atomic swap with the same risk profile for zero gain.
- **N2.** Deleting the 4-gate destination-controllability audit script (`apps/web-platform/scripts/sentry-monitors-audit.sh`). Stays as defense-in-depth even when its motivating story was wrong; only header comment reframes.
- **N3.** Deleting the original PIR / Article 30 entries. Git history is the audit trail for the evolution. Disclosure surfaces get dated `[UPDATE]` annotations; supporting docs rely on git log.
- **N4.** Investigating Sentry's URL routing topology beyond what's needed to write a correct three-dimensional host-glossary entry (URL slug ≠ database cluster ≠ token scope).
- **N5.** Touching unrelated Sentry IaC AC13-AC16 work (#3849) beyond noting partial unblock once probe lands.

## Functional Requirements

- **FR1.** Probe Step 1: `curl` `SENTRY_AUTH_TOKEN_PRD` against `/api/0/organizations/jikigai/`, capture HTTP status code. Expected 401.
- **FR2.** Probe Step 2: same token against `/api/0/organizations/jikigai-eu/` as control. Expected 200.
- **FR3.** Probe Step 3: Playwright-driven mint of a short-lived org:read token in Sentry UI scoped only to `jikigai`, run Step 1 again, revoke token in same session. Expected 200 post-mint. Operator-ack required at token-mint step per `hr-menu-option-ack-not-prod-write-auth`.
- **FR4.** Probe report committed at `knowledge-base/legal/audits/2026-05-19-sentry-token-scope-probe-report.md` including: HTTP status codes from all three steps, screenshots of token mint + revocation, Sentry audit-log timestamps for both events, the verbatim Sentry support replies (billing + forensics), and a one-sentence verification verdict.
- **FR5.** PIR frontmatter: `status: resolved` → `open`; strike `art_33_triggered: true` and `art_33_deadline`; strike `classification_override.chosen: none` (replace with reference to Gate-3b correction). Add `## Phase 9 — Gate 3b Correction (2026-05-19)` section quoting Sentry replies verbatim + probe outcome.
- **FR6.** Article 30 PA8 §(d) edit: retract the "Recipient-drift after-the-fact disclosure" paragraph; replace with `[2026-05-19 UPDATE: Prior entry of 2026-05-17 (recipient-drift to org 4511... 2026-03-28–2026-05-16) is SUPERSEDED. Sentry support confirmed 2026-05-19 that org 4511... is operator-owned; both jikigai and jikigai-eu orgs use EU databases. No third-party recipient occurred. Root cause re-scoped to internal token-scope/region-router defect. See PIR §Phase 9 Gate-3b correction.]`
- **FR7.** Article 30 Vendor DPAs row (line 258): keep DE residency + SCCs claim (still factually true per billing reply); verify post-cutover monitor count on `jikigai-eu` still matches the committed "8".
- **FR8.** `knowledge-base/legal/audits/2026-05-17-sentry-phantom-ingest-window-auth-users-audit.md`: rename to drop "phantom-ingest" framing; prepend dated correcting note; preserve SQL count and per-row categorization as still-factually-true.
- **FR9.** ADR-031: revise §DE region support to drop recipient-drift causal narrative; keep DE-region IaC support claims.
- **FR10.** `apps/web-platform/scripts/sentry-monitors-audit.sh`: header comment reframe from "detects phantom-ingest" → "detects destination-controllability drift".
- **FR11.** Learnings sweep:
  - `2026-05-15-sentry-dsn-cluster-substring-authoritative-residency.md` — keep, append three-dimensional reframe (URL slug ≠ DB cluster ≠ token scope).
  - `2026-05-16-brainstorm-premise-cascade-and-playwright-handoff-discipline.md` — append "premise cascade extended by Sentry replies 2026-05-19" pointer.
  - NEW `2026-05-19-sentry-401-is-not-unowned-verify-token-scope-first.md` — full learning with the 3-step probe pattern.
- **FR12.** Operator action (no PR): reply to Sentry billing thread with "transfer credit to jikigai-eu" + card-last-4/expiry. Capture acknowledgment screenshot for PR-1 evidence.
- **FR13.** Close #3962 in PR-1 (Gate-3b resolved 12 days early).
- **FR14.** Update parent issue #3861 with bundle-scoping note + link to PR-1 and PR-2 (do NOT close; scope still requires PR-2 corpus sweep).
- **FR15.** Bundle-scoping note also appended to #3849 (Sentry IaC blocked) noting partial-unblock conditional on probe outcome.

## Technical Requirements

- **TR1.** Probe Step 3 token lifetime ≤ 10 minutes. Single read call (Step 1 re-run). Revoke in same Playwright session before probe report write.
- **TR2.** No broad-scope token mint. Probe Step 3 token's only scope: `org:read` on `jikigai`. Operator-ack at mint screen.
- **TR3.** Probe report stored under `knowledge-base/legal/audits/` (same namespace as the existing SQL audit) — §5(2) evidence corpus.
- **TR4.** Disclosure surface edits (PA8 §(d), PIR Phase 8/9) use dated `[2026-05-19 UPDATE: ...]` or `[2026-05-19 CORRECTION: ...]` annotation pattern. Supporting docs (ADR-031, learnings, audit script header) edit-in-place; git log carries the audit trail.
- **TR5.** PR-2 explicitly `Blocked-by: PR-1` in the PR body. PR-2 cannot merge until PR-1 lands.
- **TR6.** User-impact-reviewer required on BOTH PRs at PR review (per `brand_survival_threshold: single-user incident`).
- **TR7.** GDPR-gate (`/soleur:gdpr-gate`) MUST run against both PR diffs before merge — even though the net effect is risk-reducing, the surfaces touched are regulated.
- **TR8.** Conditional halt: if probe Step 1 returns anything OTHER than 401, OR Step 3 returns 401 even with scope-matched token, the reframe narrative is dead. Halt corpus sweep. Re-spawn triad with new framing. Re-evaluation criterion: probe Step 1 = 401 AND Step 3 = 200.
- **TR9.** Token-scope probe artifacts (screenshots, audit-log timestamps) MUST be redacted of card numbers, full email addresses other than the operator's, and any Sentry internal IDs other than the two known org IDs (`4511123328466944` for jikigai, `4511404939345920` for jikigai-eu) which are already committed to main.

## Acceptance Criteria

- **AC1.** PR-1 merged: probe report committed, PIR reopened, Gate-3b correction section appended, `art_33_*` flags struck, audit script header reframed, #3962 closed.
- **AC2.** PR-2 merged: PA8 §(d) retracted with dated pointer, auth.users audit reframed, ADR-031 revised, host-glossary three-dimensional rewrite, learnings sweep complete.
- **AC3.** Sentry billing thread closed: credit transferred to jikigai-eu, acknowledgment screenshot in PR-1.
- **AC4.** #3861 updated with bundle-scoping note + scope-rewrite summary; not closed (closure waits for full PR-2 verification cycle).
- **AC5.** `/soleur:gdpr-gate` ran clean on both PR diffs.
- **AC6.** User-impact-reviewer signed off on both PRs.
- **AC7.** Probe Step 1 returned 401 AND Step 3 returned 200 (token-scope theory confirmed). If not — escalate via TR8 conditional halt path.

## User-Brand Impact

**Artifact at risk:** `knowledge-base/legal/article-30-register.md` PA8 §(d) "Recipient-drift after-the-fact disclosure" block (~10 lines of affirmative public-facing legal text); PIR `art_33_triggered: true` + `art_33_deadline: 2026-05-19T12:50:00Z` (deadline anchored on a non-event).

**Vector of harm:** DPA / regulator / counsel reading the live Article 30 register today concludes Soleur self-reported a sub-processor recipient-drift event with a named third-party org. Follow-up question ("Art 33 notification?") cannot be answered truthfully. Brand-credibility damage of higher class than absence of disclosure.

**Threshold:** `single-user incident`. Correcting work is risk-reducing in aggregate but touches public-facing legal disclosure surfaces and must be evidentially grounded.

**Channel:** institutional (regulators, counsel, DPAs reading the register), not end-user directly.

**Per AGENTS.md `hr-weigh-every-decision-against-target-user-impact`:** every step of this plan was weighed against what one regulator's misreading of PA8 §(d) costs the brand. The CLO-recommended retract-in-place (not append) was chosen because a live disclosure register must not read as an affirmative claim that no longer holds.

## Bundle-scoping notes (to be appended to each issue)

### #3861

> **Bundled scoping note 2026-05-19.** Sentry support replies received 2026-05-19 falsify the core "phantom-ingest to unowned third-party org" framing committed under PR-α #3904 / PR-γ #3946. PIR Phase 8 Gate 3b ("this org is yours") is now load-bearing. Corrective two-PR series scoped under brainstorm `knowledge-base/project/brainstorms/2026-05-19-sentry-residency-reframe-3861-brainstorm.md` + spec `knowledge-base/project/specs/feat-sentry-residency-reframe-3861/spec.md` + branch `feat-sentry-residency-reframe-3861` + draft PR #4044. This issue stays open until PR-2 corpus sweep merges + verification cycle completes.

### #3962

> **Bundled scoping note 2026-05-19.** Sentry support replies received 2026-05-19 resolve Gate 3 as **3b** ("this org is yours" STOP signal) 12 days before T+14d expiry. Resolution work scoped under brainstorm `knowledge-base/project/brainstorms/2026-05-19-sentry-residency-reframe-3861-brainstorm.md`. PR-1 of the corrective two-PR series closes this issue.

### #3849

> **Bundled scoping note 2026-05-19.** Sentry support replies received 2026-05-19 + the corrective token-scope probe (scoped under brainstorm `knowledge-base/project/brainstorms/2026-05-19-sentry-residency-reframe-3861-brainstorm.md` PR-1) MAY partial-unblock this issue. Re-evaluate after PR-1 lands; the SENTRY_AUTH_TOKEN scope question is adjacent (this issue is about scope of token for AC13-AC16 IaC work; the probe scope is for org:read jikigai verification).
