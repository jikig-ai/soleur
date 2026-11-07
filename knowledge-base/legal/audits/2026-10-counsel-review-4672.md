---
title: "Counsel review audit — #4672 / PR #11289 (approval queue slice 1: Privacy 4.15, DPD 2.3(ah), GDPR 3.17, Art. 30 PA-38, posture row, b-canary record; dark ship)"
type: counsel-review
date: 2026-10-29
issue: 4672
pr: 11289
status: "SIGNED-OFF (CLO-agent-attested, Soleur-as-tenant-zero v1), for the DARK MERGE only"
signed_off_at: 2026-10-29
signed_off_by: "CLO agent (attestation authority for the Soleur-as-tenant-zero v1 posture; the operator retains an optional veto)"
reviewed_head: ec1ba7a5f5
disposition: "DISCHARGED for a merge in which the `approval-queue` flag stays OFF/absent everywhere, subject to two record-only in-PR conditions (C1, C2: no published text, no mirror, no SHA re-pin). Every implementation-detail claim in the published text matches migration 180 and server/approval/*; no unqualified 'no plaintext' claim survives; canonical and mirrors are byte-identical in their added lines and the pins are current; no [DRAFT] marker. This is NOT a flag-ON attestation: every flag-ON condition from the earlier rulings stays open."
conditions:
  - "C1 — compliance-posture.md, row 'Approval queue: public wording and enabling gate': the row does not carry the cohort rule or the pepper condition (both live only in ADR-309's flip checklist items 1 and 2 and in PA-38 (g)(7)). Add the clause given in section 5 after item (i). Until added, the b-canary record's statement that the row names the cohort rule is false against the file."
  - "C2 — 2026-10-29-approval-queue-b-canary-record.md: (v) still says 'I ask the lead to re-run the probe at the final head'. The re-run is recorded in phase-0-measurements.md ('Addendum 2026-10-29 (#4672): probe re-run at the final head e271d9f101', PASS). Replace that sentence and add the cohort/pepper bullet given in section 5."
non_blocking:
  - "N1 — the b-canary record is pinned at e271d9f101; the legal documents, mirrors and pins are byte-unchanged since (checked), and server/approval and migration 180 are untouched since. The later code changes (userIdHash in the cross-kind log, INVISIBLE_RE split) add no emitter that could carry action text and narrow the identifiers logged."
  - "N2 — the register (g)(7) sentence is redundant ('derived by HKDF-SHA256 ... from SENTRY_USERID_PEPPER ... the existing pepper'). Accurate; no edit owed."
  - "N3 — the mirror-drift lint prints that the #7465 remediation target (2026-09-30) has passed with 80 drift lines remaining. Pre-existing, exit 0, not caused by this PR; re-date #7465 is the owner's call."
open_follow_ups: ["Flag-ON conditions below (all open)", "#7465 (canonical/mirror drift freeze, past its target date)", "#11303 (gate-effectiveness limbs; the pre-existing 'single-use' / 'bound to a hash' claims in Privacy 4.14 and DPD 2.3(ab) stay with it, per register item 15(h))"]
re_evaluation_triggers: "Any edit to docs/legal/{privacy-policy,gdpr-policy,data-protection-disclosure}.md or a mirror (void for that document); migration 180 or server/approval/{canonical,service,grants,notify}.ts changed; first non-Jikigai principal in any workspace with the flag on; first non-canary ON (needs full (b), (c)-(h), (i), CPO+CLO sign-off); first arms-length user; EEA-out data subject; regulated-industry user."
---

# Counsel review audit — #4672 (approval queue slice 1, dark ship)

v1 internal counsel-review attestation for PR #11289, a `single-user incident` PR that adds Processing Activity 38 and amends the Privacy Policy, GDPR Policy and Data Protection Disclosure (and mirrors). Authority: CLO agent (Soleur-as-tenant-zero v1); operator veto retained; external counsel reserved for the frontmatter triggers. Output is draft material, not legal advice.

**Scope.** The merge only. Rulings R1 (`CLO-RULINGS.md`) and R2 (`CLO-RULINGS-R2.md`, which corrected R1 on canary gate versus attestation) are the standard; R2 governs where they differ. Nothing here switches anything on, and nothing here waives a flag-ON condition. The `approval-queue` flag is absent/OFF by default and per workspace; with it OFF no row is written, shown or sent, so the merge itself creates no personal-data-breach event and no breach-notification duty (this is not a breach determination; the breach register's determination rows concern other matters).

**Method.** Each added sentence in the three canonical documents was read at HEAD `ec1ba7a5f5` and checked against: `apps/web-platform/supabase/migrations/180_approval_request.sql` (table, CHECK constraints, `sweep_approvals`, `anonymise_approval_request`, guard GUC `app.approval_erase`), `server/approval/canonical.ts` (`deriveApprovalHashKey`), `notify.ts`, `reattach.ts`, `cron-approval-expiry.ts`, `server/notifications.ts` (`approvalExpiresAt`, first name, workspace name) and ADR-309. Mirrors were compared by sorted added lines (md5 equal for all three documents). Gates were run, not assumed.

## Gate results (run at HEAD)

| Gate | Result |
|---|---|
| `npx vitest run test/legal-doc-shas-guard.test.ts test/legal-doc-consistency.test.ts` (apps/web-platform) | 2 files, 43 tests passed |
| `apps/web-platform/scripts/check-tc-document-sha.sh` | exit 0 |
| `sha256sum` of the three canonical files versus `lib/legal/legal-doc-shas.ts` | privacy `a5a0f4e2…99aa0`, gdpr `bed31edf…8adc7`, dpd `7d5ec492…e6bb4`: all equal their pins |
| `scripts/lint-legal-mirror-drift-baseline.sh --base origin/main` | exit 0 (drift not grown; #7465 warning pre-existing) |
| `scripts/lint-legal-scope-block-placement.sh --base origin/main` | exit 0 |
| Added lines canonical versus mirror | identical for all three (sorted-line md5 equal) |
| `[DRAFT` marker in added lines of docs, mirrors, register, posture | 0 (the pre-existing house phrases 'Draft, pending counsel review' / 'requires professional legal review' / 'Output marked draft-requiring-professional-review' appear, as they already do three times per document on `origin/main`) |
| `terms-and-conditions.md` in the diff | no, so no `TC_VERSION` bump; no document or heading added, so `EXPECTED_COUNT` and heading parity unchanged |

## Artifact verdicts

| # | Artifact | Verdict | Basis |
|---|---|---|---|
| 1 | Privacy Policy 4.15 + Amended note + lawful-basis list + Section 7 retention bullet (and mirror) | TRUE | See table A |
| 2 | Privacy Policy 4.14 note and 5.9 Resend bullet (and mirror) | TRUE | Both scope the 'no plaintext' claim to the outbound-email records and state the approval-request location and 30-day retention |
| 3 | DPD 2.3(ah), 4.2 Resend row, 5.3(a), 10.3(j), Amended note (and mirror) | TRUE | See table A; 4.2 carries the qualifier |
| 4 | GDPR Policy 3.11 Necessity, 3.17, 5.3, 8.4, 9, 10 item 13 (and mirror) | TRUE | 3.11 carries the qualifier; 3.17 matches 4.15 and 2.3(ah); Section 9 wording is the R1 6f form |
| 5 | Art. 30 register PA-38 (a)-(h), PA-28 amendment note, item 15 | TRUE | PA-28 note is conditioned on the merge ('fires on the merge of PR #11289, draft at the date of writing'), not past tense; (g)(7) HKDF-then-HMAC matches `deriveApprovalHashKey` |
| 6 | compliance-posture.md row 'Approval queue: public wording and enabling gate' | TRUE as far as it goes; INCOMPLETE | Gates enabling, not the merge; has (a)-(i), (b-canary), card-string note; lacks cohort rule and pepper (C1) |
| 7 | b-canary record `2026-10-29-approval-queue-b-canary-record.md` | TRUE except two stale/over-reaching statements (C1, C2) | Verification step re-performed below (3 of 3 phrases qualified in 8 of 8 occurrences); `status: conditional` is correct |

### Table A — published statements against the implementation

| Statement | Checked against | Verdict |
|---|---|---|
| Three user links (requester, decider, revoker); all cleared on that user's erasure | migration 180 columns `requested_by_user_id`, `decided_by`, `revoked_by`, all `ON DELETE SET NULL`; `anonymise_approval_request` nulls all three | TRUE |
| Statuses pending/approved/rejected/expired/used; a withdrawn approval is stored `rejected` with the withdrawal time and `decided_*` kept; 'used' is not 'succeeded' | CHECK `status IN (...)`, `approval_request_revoked_pairing`, `consumed_at` pairing | TRUE |
| Flagged as unanswered after 15 minutes | `sweep_approvals`: `status='pending' AND unanswered_flagged_at IS NULL AND created_at < now() - interval '15 minutes'` | TRUE |
| Keyed fingerprint, HMAC-SHA-256, secret outside the database, pseudonymous while the secret exists | `canonical.ts`: HKDF-SHA256 over `SENTRY_USERID_PEPPER` (info `soleur:approval-request:action-sha256:v1`) then HMAC-SHA-256; unset/empty fails closed (`key_unavailable`) | TRUE (published text describes the keyed form only, not the derivation; both constructions satisfy it) |
| Action text removed 30 days after final state (rejected/expired/used; withdrawn counts as rejected from withdrawal) | `sweep_approvals` scrub: `status IN ('rejected','expired','consumed')` and `COALESCE(consumed_at, expired_at, revoked_at, decided_at) < now() - interval '30 days'` | TRUE |
| Action text removed immediately, for requests the user raised, on erasure | `anonymise_approval_request` sets `canonical_action = NULL` where `requested_by_user_id = p_user_id` | TRUE |
| Personal workspace with no member left: every request and its inbox entry deleted; other members keep the record under the workspace id | `anonymise_approval_request`: `IF NOT EXISTS (workspace_members WHERE workspace_id = p_user_id)` then GUC `app.approval_erase` DELETE and `inbox_item ... source = 'approval_required'` DELETE; otherwise rows kept | TRUE (R1 item 1 contract met) |
| Rest of the record kept for the workspace's life; no shorter limit fixed | no other deletion path in 180; open counsel question 15(a) | TRUE, correctly disclosed as unconfirmed |
| Notification: fixed wording, no action/recipient/repository/branch/document/subject; email may carry first name, workspace name and the decision deadline | `notify.ts` (never the row title; `expires_at` taken from the create-RPC result), `notifications.ts` (`firstName`, `workspaceName`, `expiresAt`) | TRUE (R1 6b condition met in code) |
| Expiry pair (push + email) only for an unanswered request; approved-but-unused expiry is inbox only | `cron-approval-expiry.ts`: `if (e.reason !== "unanswered") continue;` | TRUE |
| Copy says the request 'ran nothing' | R2 item 8 narrowing; sweep for 'nothing was run' returns nothing | TRUE |
| Inbox entry retention (archived or demoted-to-info entries deleted by the daily sweep once more than 90 days from entry creation) | migration 122 sweep as verified in R2 item 4; `approval_request_inbox_settle` modes | TRUE |
| Logs/error reports carry ids, kind, workspace/conversation/user ids, not action text; on-host copy has no fixed limit | `ops.ts` emitters (static messages, id tags, scalar extras); no `canonical_action` in any log/Sentry call (grep, 0 lines); Privacy Section 7 | TRUE (design statement; static grep, not a measurement of what Sentry/Better Stack received) |
| No AI provider receives the action text from this feature | `render`/`notify`/`gate-flow` build cards and fixed copy from the stored action; no prompt path reads `canonical_action` | TRUE as to this feature (the conversation is processed per Privacy 5.1, as the text says) |
| Owner reads in product; requester sees it in their own conversation; other members cannot | Owner-only RLS `SELECT` via `is_workspace_owner`; `reattach.ts` sends the card only to the attaching (requesting) user | TRUE for the cohort that the flag-ON rule allows (single-member); multi-member is cohort-gated below |
| No promise that approval is enforced, single-use, time-limited or action-bound | text contains only the 'What this Section does not say' disclaimer | TRUE (no unmeasured design intent is asserted) |

## (b-canary) verification step re-performed

1. The three 'no plaintext' phrases, canonical and mirrors: `persist no plaintext` (Privacy 5.9 and DPD 4.2 Resend row, plus Privacy 4.14), `never store the plaintext` (Privacy 4.14), `remain only in the drafting` (GDPR 3.11). Each carries an approval-queue qualifier in reach (Privacy 5.9, DPD 4.2 and GDPR 3.11 read the R1 wording; Privacy 4.14 carries it in the trailing italic note of the same bullet). The register's equivalents (PA-28 (c), (g) item 9) are covered by the PA-28 amendment note, which names (c); widening 'as to the statements in (c)' to '(c) and (g)' is optional and not owed.
2. No present-tense categorical 'no plaintext recipient or body persisted' statement survives where the code stores more. The remaining unqualified occurrences are the dated history in the `Last Updated` notes and sentences scoped to named outbound tables ('these tables never persist ...'), which stay true because `approval_request` is a different table.
3. `canonical_action` in logs/Sentry: 0 emitter lines (grep over `server`, `lib`, `app`, `infra`, `.github`); no new emitter since the b-canary record's pinned head.

## 4. Flag-ON conditions: recorded, not waived

None of the following is satisfied or waived by this merge. The posture row says it 'gates ENABLING, not the merge', and nothing in the diff says the flag may be turned on by merge or by this attestation.

| Condition | Where recorded at HEAD | Status |
|---|---|---|
| (a) real-SDK probe | posture row (a); `phase-0-measurements.md` addenda; final-head re-run PASS recorded | recorded; legacy-runner path only, approval flow with the flag on and hosted ask lane (#9776, #10111) NOT measured |
| (i) erasure and fingerprint real-DB conformance | posture row (i); b-canary record (v); `approval-request.tenant-isolation.test.ts` (tenant-integration workflow only) | OPEN: not observed by me; must be recorded in `knowledge-base/legal/audits/` before any ON |
| (b-canary) | the b-canary record | present, `conditional` on the tenant-integration suite being green; void on any later change to the three documents |
| Canary workspace Jikigai-owned and every member a Jikigai principal | posture row | recorded; runtime fact, operator check at flip time |
| Non-canary: full (b), (c)-(h), CPO+CLO sign-off of `AUTONOMOUS_CARD_COPY_PROVISIONAL` | posture row (b), (c)-(h) | recorded; open |
| Cohort rule for multi-member workspaces | ADR-309 flip checklist item 1; flag-create-handover.md; NOT in the posture row | recorded in engineering docs only: C1 |
| `SENTRY_USERID_PEPPER` non-empty in the running container and never rotated while approvals are live | ADR-309 flip checklist item 2; register PA-38 (g)(7) rotation consequence; NOT in the posture row | recorded in engineering docs and the register only: C1 |
| Qualifier sentences removed by a docs PR with re-pin | posture row (c) | open (non-canary) |

## 5. Conditions of discharge (record-only; apply in this PR; no re-pin)

**C1 — `knowledge-base/legal/compliance-posture.md`**, row 'Approval queue: public wording and enabling gate'. After the sentence ending `both recorded in \`knowledge-base/legal/audits/\`.` that closes item (i) and before `**Owed and not done in this PR:**`, insert:

> **Further flip conditions carried from the ADR-309 flip checklist, not waived by the merge (CLO, 2026-10-29):** (j) **cohort rule**: no workspace with more than one member gets the flag, canary or not, until the Owner card names the requester and `reattach` stops sending full action text to non-Owners; until then single-member workspaces only, with the `workspace_members` count checked before any per-workspace override and re-checked on every member invite (a legal condition stated independently of the engineering rule); (k) **`SENTRY_USERID_PEPPER`** is non-empty in the running container and is not rotated while any approval is live (a rotation fails every live approval closed and also changes the ADR-029 pseudonyms; see PA-38 (g)(7)).

Falsifier: `grep -c "Further flip conditions carried from the ADR-309" knowledge-base/legal/compliance-posture.md` returns 1.

**C2 — `knowledge-base/legal/audits/2026-10-29-approval-queue-b-canary-record.md`**, section (v), bullet '(a) Real-SDK probe recorded'. Replace the sentence beginning `The recorded run therefore pre-dates the committed head and I have not seen a re-run at \`e271d9f101\`; I ask the lead to re-run the probe at the final head and append one line to the addendum before a canary ON.` with:

> A re-run at the final head `e271d9f101` is recorded in the same file ("Addendum 2026-10-29 (#4672): probe re-run at the final head e271d9f101", PASS, cases-run=10); a later code change to the gate, the grants or the runner re-opens it.

and add, at the end of the 'Before ANY ON, canary included' list:

> - **Cohort and pepper (posture row (j), (k); ADR-309 flip checklist items 1 and 2).** Single-member workspaces only until the cohort rule is met; `SENTRY_USERID_PEPPER` non-empty in the container and not rotated while approvals are live. Not verifiable from the repo; operator checks at flip time.

Falsifier: `grep -c "Cohort and pepper" knowledge-base/legal/audits/2026-10-29-approval-queue-b-canary-record.md` returns 1.

If C1 or C2 does not land, the sentence in the b-canary record's section (ii) that the posture row 'names the engineering counterpart in ADR-309 (cohort rule ...)' remains false against the file, and this disposition reverts to BLOCKED for that record.

## Disposition

Disposition: DISCHARGED

Dark merge only, subject to C1 and C2. The `approval-queue` flag must remain absent/OFF everywhere after merge; any ON, canary included, requires the conditions in section 4 and a fresh record. Re-evaluation triggers are in the frontmatter.
