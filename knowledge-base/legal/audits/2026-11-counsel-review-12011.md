---
title: "Counsel review audit — #12011 PR-B (founder legal-acceptance record, PA-40, migration 184, ADR-319): register entry, standalone LIA, attestation record, DSAR and notice note, gdpr-gate exit, posture row"
type: counsel-review
date: 2026-11-04
issue: 12011
pr: 12069
status: "SIGNED-OFF (CLO-agent-attested, Soleur-as-tenant-zero v1)"
signed_off_at: 2026-11-04
signed_off_by: "CLO agent function run via subagent (attestation authority for the Soleur-as-tenant-zero v1 posture; the operator retains an optional veto)"
disposition: "DISCHARGED for the merge of PR-B (feature dark, no row exists), conditioned on the three follow-ups being tracked (filed as #12080) (see Conditions) and on the first-real-row conditions below. Not external counsel: counsel item 17 (a) to (g) stays open and the sign-off block of the attestation record stays blank. Every implementation-detail claim was checked against migration 184, its down script, the verify script, dsar-export-allowlist.ts and ADR-319; six misstatements were corrected in place."
non_blocking:
  - "N1 — ADR-319 (not edited here) says in Option F that a 'service-role holder can recompute an unkeyed chain'. That is a statement about a hypothetical chain design and is accurate in that context; the register and LIA no longer say a service_role holder can rewrite an existing row, because the migration gives service_role no table privilege."
  - "N2 — statutory-response-catalog.md#dsar routes a Web Platform account holder to the self-serve export or the DSAR worker and has no route for rows held in tables excluded from both (the PA-40 email route). It also has no Art. 21 section (already acknowledged in the LIA). Owed before the first erasure request or objection."
  - "N3 — Art. 20 is cited next to Art. 15 in register (h). The basis is Art. 6(1)(f), so Art. 20 does not apply; harmless, left as drafted."
open_follow_ups: ["deletion path for a retained row at the end of the retention period, including redaction of the free-text note (not built; tracked in #12080)", "external anchor for the row checksum (deferred; ADR-319 says no issue tracks it)", "deletion of legal_reauth_event rows on erasure (not built; the 30-day opportunistic purge is built)", "Register Maintenance item 17 (a) to (g) (external counsel)"]
addenda: ["2026-11-07 pointer addendum (#12197, PR #12342, fires on its merge): the CLO agent ruling that stands in for counsel on the first committed text is in 2026-11-07-clo-ruling-founder-acceptance-record-12197.md; this attestation and its disposition are not changed", "2026-11-05 PR-C addendum (PR #12148, fires on its merge): see the section 'Addendum 2026-11-05 (PR-C)' at the end; it does not change this PR-B disposition", "2026-11-05 PR-D enforcement-read trigger (PR #12187, fires on its merge): recorded as met in the LIA Addendum 2026-11-05; balancing outcome unchanged; no change to the PR-B or PR-C dispositions", "2026-11-06 PR-D ship-time CLO-attestation (PR #12187, fires on its merge): DISCHARGED for the merge of the dark endpoint and the draft-marked disclosures; see the section 'Addendum 2026-11-06 (PR-D, ship-time attestation)' at the end; CLO-agent-attested, draft, pending counsel for #12080", "2026-11-09 round-4 addendum (#12365, PR #12438, fires on its merge): the approval-queue flag is on for every production workspace; the premises 'flag stays off' and 'dark endpoint' of the PR-C and PR-D dispositions and Conditions 1, 2 and 4 are marked at the end; no re-attestation, the discharges for their merges are not withdrawn"]
re_evaluation_triggers: "First arms-length user (any founder other than the Jikigai operator) OR EEA-out data subject OR regulated-industry user OR any component that reads the table to enforce something (PR-D wired into a gate) OR the external anchor built OR the retention period confirmed or changed OR a first erasure request or objection from a founder whose row is kept OR a second free-text field or a change to the note cap."
---

# Counsel review audit — #12011 PR-B (PA-40, migration 184)

v1 internal counsel-review attestation under the ship Phase 5.5 gate, for a PR whose plan declares `brand_survival_threshold: single-user incident`. Authority: CLO agent function (Soleur-as-tenant-zero v1); operator veto retained; external counsel reserved for the frontmatter triggers and for counsel item 17. Output is draft material, not legal advice. The artifacts reviewed carry, and keep, their "drafted, not counsel-reviewed" wording: this audit is not external counsel and clears no marker.

**Method.** Each factual claim in the six artifacts was checked against `apps/web-platform/supabase/migrations/184_legal_acceptance.sql` (columns and checks, RLS and grants, `legal_acceptance_guard`, `issue_legal_reauth`, `claim_legal_reauth_attempt`, `mark_legal_reauth_verified`, `record_legal_acceptance`, `verify_legal_acceptance`, `legal_acceptance_row_hash`), `184_legal_acceptance.down.sql` (refuses while any row exists), `apps/web-platform/supabase/verify/184_legal_acceptance.sql` (catalog sentinel: no foreign key, no write privilege for any api role, `anonymise_approval_request` unaware of the table), `apps/web-platform/server/dsar-export-allowlist.ts` (`DSAR_TABLE_EXCLUSIONS` entries for both tables) and ADR-319. `account-delete.ts` contains no reference to either table (the only user-keyed scrub added in this area is `anonymise_approval_request`, which the verify script pins as unaware of `legal_acceptance`).

## Artifact 1 — article-30-register.md (PA-40 and Register Maintenance item 17)

| Claim | Checked against | Verdict |
|---|---|---|
| Columns listed in (c) match the table, including `requested_edit` at most 1000 characters, trimmed, only for `request_changes`; `session_id` up to 128 characters | `CREATE TABLE`, `record_legal_acceptance` | TRUE |
| No name, email or IP stored; the code is never stored | table definitions; `mark_legal_reauth_verified` takes no code | TRUE |
| `service_role` holds no privilege on either table; founder-only SELECT on `legal_acceptance`, restrictive jti-deny; `legal_reauth_event` no policy, no privilege | `REVOKE`/`GRANT`, policies, verify script | TRUE |
| Founder reads own rows (including the note) via RLS; check function returns status, hash, time, checksum flag, not the note | `legal_acceptance_founder_select`, `verify_legal_acceptance` | TRUE |
| Retention (f): no sweep, guard refuses UPDATE, DELETE, TRUNCATE; intent 30 minutes; challenge rows older than 30 days deleted whenever a challenge is requested; nothing deletes on erasure | guard, `issue_legal_reauth` (purge runs only there), no FK, `account-delete.ts` | TRUE |
| Every decision needs a server-issued intent; a Yes needs the code confirmed in the last 5 minutes; attempts cap 5; 3 intents per user and key per 15 minutes; a resend voids the earlier intent | `issue_legal_reauth`, `claim_legal_reauth_attempt`, `record_legal_acceptance` | TRUE |
| Checksum "detects a changed row ... a holder of database-owner or `service_role` access could rewrite a row and recompute its hash" | `service_role` has `REVOKE ALL` on the table; every write is refused by the guard unless inside `record_legal_acceptance`, which needs a founder web-session token | **OVERSTATED — corrected in place** (database-owner only; the service-key limit stated: it can stamp an intent as confirmed via `mark_legal_reauth_verified`, which trusts its caller, but still needs a founder token to record) |
| Resend carries the code email | plan Phase A0 spike: production Supabase Auth uses Resend SMTP | TRUE (as recorded) |
| Not Art. 17(3)(b); Art. 17(3)(e) with Art. 6(1)(f) | position paper, see Determinations | Accepted as a drafted position |

Item 17(g) carried the same overstatement; corrected. **Verdict: accurate after correction.**

## Artifact 2 — legitimate-interest-assessments/2026-11-founder-legal-acceptance-lia.md

Three limbs present; the retention and erasure rule is correctly separated from PA-38. Corrections made in place:

1. Summary and Residual 4 described the challenge as "5-minute" and said challenge rows "expire by timestamp after 5 minutes". The implementation has a 30-minute intent; 5 minutes is the maximum age of the code confirmation when a Yes is recorded. Corrected in both places.
2. Residual 2 said a `service_role` holder can rewrite a row and its checksum. Corrected as in Artifact 1.
3. Residual 7 and the Art. 17 paragraph said access after erasure is by the database owner role only. `verify_legal_acceptance` (service_role) also reads a row after erasure and returns status, text hash, decision time and a checksum flag, never the note. Both now say so, matching the erasure reply.

The balancing sentence "closed only by telling the founder, before they decide, what is kept" relied on card wording that the DSAR note did not contain (only the note-field notice was drafted). A card-level notice is now drafted as part (c-2) of the DSAR note (proposed, not approved). **Verdict: accurate after correction.**

## Artifact 3 — audits/2026-11-founder-legal-acceptance-attestation.md

Nine design properties match the migration (checked one by one). Section 2 correctly disclaims production behaviour, anchor, evidential weight, retention and Art. 17(3)(e). Corrected in place: the checksum/`service_role` sentence (section 2 and residual 1), residual 7 (check function), condition list (card-level notice added), and a pointer line under the blank sign-off block to this audit, stating it does not fill that block. Status, disposition "OPEN" and the blank block are unchanged. **Verdict: accurate after correction; remains a drafted record awaiting external counsel.**

## Artifact 4 — audits/2026-11-founder-legal-acceptance-dsar-and-notice-note.md

| Claim | Verdict |
|---|---|
| Both tables in `DSAR_TABLE_EXCLUSIONS`, not the allowlist; reasons match the code's stated reasons (no account to key on after erasure; worker reads with `service_role`, which has no privilege) | TRUE |
| Founder can read own `legal_acceptance` rows once PR-C is live; cannot read `legal_reauth_event` | TRUE (RLS, no policy) |
| Erasure reply "What is kept" list | **INCOMPLETE — corrected**: omitted the session identifier, the code-confirmation time and the checksum, all stored in the row |
| "Who can see it" names the check service | **Corrected**: it is PR-D and not live; now "once it is switched on" |
| "with one exception" in the reply | **Flagged** in the notes for the person answering: reconcile with other data kept for the account |
| Content of the Art. 15 copy | **Corrected**: now includes any `legal_reauth_event` rows still held (they hold the uuid and session id) |
| Notice for the Request changes field | Matches the 1000-character cap and trim |

Added (c-2), a proposed card-level Art. 13 notice (operator first; Art. 13(4) fallback does not carry to any other founder). Part (d) originally recommended no `docs/legal/**` change in PR-B; that was superseded the same day by the lockstep addendum below. The final-form update and the retention-paragraph conflict it names must be resolved before any other founder. **Verdict: accurate after correction.**

## Artifact 5 — audits/2026-11-04-gdpr-gate-work-exit-12011-pr-b.md

Statements check out (LAWFUL_BASIS and RETENTION annotations present in the migration; no FK; no `anonymise_*` for this table; DSAR exclusion present). It is a heuristic gate output and says so. **Verdict: accurate; no edit.**

## Artifact 6 — compliance-posture.md (new row and comment)

Row conditions the gate on the first real row and on any non-Jikigai founder, not on the merge; open limbs (a) to (h) are the right list. One sentence corrected (checksum/`service_role`). Dated comment is conditioned on the merge of the carrying PR. **Verdict: accurate after correction.**

## Addendum 2026-11-04 — published disclosure added in this PR

The CI DSAR lockstep gate (`pr-quality-guards.yml`) requires the three public documents and the posture file to change whenever `dsar-export-allowlist.ts` changes, so the three documents were updated in this PR rather than at the non-Jikigai-founder gate: Privacy Policy 4.17 and a Section 7 bullet, GDPR Policy 3.19, Data Protection Disclosure 2.3(aj), 5.3(a) and 10.3(l), each mirrored in `plugins/soleur/docs/pages/legal/` and the three SHA pins regenerated, no TC_VERSION bump. The text is short, written ahead of the processing exactly as the PR #11889 precedent does (tables exist from migration apply, nothing writes to them, applies from the date the write path ships, operator only first), covers only what migration 184 and PA-40 state, and states the retention proposal as unconfirmed. It is marked `[DRAFT — pending CLO/counsel review per #12011]`; **those markers remain until external counsel clears counsel item 17.** This audit does not clear them: it is the in-repo v1 attestation, and publishing draft-marked text keeps the public record honest about its status. Wording verified against the migration (no foreign key, write-once guard, 30-day purge of code-request rows only when the next request is made, `service_role` without table privilege, note readable by the founder and the database owner but not returned by the status check). Final-form wording for all three documents is still owed before any founder other than the operator is admitted. The Privacy Policy retention statements elsewhere that data is deleted on account deletion are qualified by an explicit exception in 4.17 and Section 7.

## Determinations

- **Lawful basis.** Art. 6(1)(f) with the standalone LIA is supportable for an operator-first data subject: concrete evidential interest, minimal data (no name, email or IP), pseudonymous uuid, low impact. The balancing outcome for a customer founder is correctly not reached.
- **Art. 17(3)(e).** Keeping the row after erasure is a defensible position for evidence of a decision on a legal text where claims are foreseeable, and is weaker as a blanket rule. Art. 17(3)(b) is rightly not claimed. Stays a counsel item (17(b)), including for customer founders.
- **Retention.** Life of the instrument plus 5 years, cap 10, is a reasonable proposal (the 5-year figure tracks ordinary commercial limitation); it stays unconfirmed. The cap cannot be honoured today because no deletion path exists. Acceptable while dark and operator only, not acceptable as a standing state.
- **Art. 13/14.** Data is collected from the subject (Art. 13). Before this audit only the note-field notice existed; the card-level notice is now drafted (c-2). Art. 14 is not engaged except for third parties named in the note (disproportionate-effort position, disclosed).
- **DSAR.** Email route for Art. 15, served by the database owner role; adequate for one data subject. After deletion, matching a requester to a bare uuid is the open Art. 11 / 12(6) question (item 17(d)).

## Conditions

Before ship (conditions of this discharge): discharged — the three follow-ups are tracked in one issue, #12080.

1. Filed: #12080 covers the end-of-retention deletion path including note redaction, the external anchor, and deletion of `legal_reauth_event` rows on erasure.

Before the table receives its first real row (enabling gate, not the merge):
2. Card-level notice (c-2) and the Request changes notice (c) are on the screen word for word, with the retention period filled or the line carrying "to be confirmed" removed from the display text.
3. The attestation record's sign-off block is completed by counsel, or the operator records an express deferral of each open item in item 17.
4. Statutory response catalog gets a route for excluded-table access requests (N2).

Before any founder other than the Jikigai operator: Privacy Policy, Data Protection Disclosure and GDPR Policy updated together with mirrors and SHA pins, retention paragraph qualified; LIA re-run.

## Overall

| Artifact | Verdict |
|---|---|
| article-30-register.md PA-40 + item 17 | Accurate after correction |
| LIA | Accurate after correction |
| Attestation record | Accurate after correction; still awaiting external counsel |
| DSAR and notice note | Accurate after correction |
| gdpr-gate exit | Accurate |
| compliance-posture.md row | Accurate after correction |

**Disposition: DISCHARGED**, conditioned on Condition 1. No code, SQL or ADR was changed. Problems in those files: none found that make a legal artifact false; N1 notes one ADR sentence read in context.

*Draft material for internal attestation; not legal advice. External counsel re-review follows the frontmatter triggers and counsel item 17.*

## Addendum 2026-11-05 (PR-C)

v1 internal counsel-review attestation under the ship Phase 5.5 gate for PR #12148 (PR-C of #12011: the web card and the in-place email-code check behind the `approval-queue` flag). The plan declares `brand_survival_threshold: single-user incident`. Authority and limits are as stated above: CLO agent function, operator veto retained, external counsel reserved for the frontmatter triggers and counsel item 17. This addendum is conditioned on the merge of PR #12148; the text above is unchanged. Draft material, not legal advice. It clears no PROVISIONAL, DRAFT or counsel-placeholder marker.

**Method.** The prose in the five legal artifacts was read against `apps/web-platform/server/legal-acceptance/reauth.ts` (`resolveIdentity`, `AttemptCeiling`, `SendFailureMemory`, `sendReauthCode`, `verifyReauthCode`), `service.ts` (`decideLegal`, `normaliseNote`), the two routes under `apps/web-platform/app/api/legal-acceptance/[key]/`, the two pages under `apps/web-platform/app/(dashboard)/dashboard/approvals/legal/`, `server/approval/flag.ts` and `LEGAL_OPS` in `server/approval/ops.ts`, `lib/legal-acceptance-copy.ts`, `server/legal-acceptance/texts/` and the ADR-319 PR-C amendment. The two notice strings in `LEGAL_COPY` were compared character by character with parts (c) and (c-2) of `2026-11-founder-legal-acceptance-dsar-and-notice-note.md`: identical (the retention placeholder `[period to be confirmed by counsel]` is present). No migration, SQL or DSAR allowlist change is in the diff, so migration 184 claims from the PR-B review stand and the `docs/legal/**` lockstep gates are not engaged.

### Facts checked

| Fact | Finding |
|---|---|
| Per-host verify ceiling carries its caveat everywhere | `AttemptCeiling` is an in-process map (10 per 15 minutes per user); the code says so. Caveat was missing in two places and is now present: the LIA web-screen paragraph and the gdpr-gate exit body. Present already in the register amendment, LIA safeguards, attestation property 12, ADR-319. The database bounds (5 per challenge, 3 challenges per 15 minutes) are the hard limit. Read in context: PA-8 records web-2 as an out-of-band standby at serving weight 0, so multiplication across hosts may be theoretical today; a restart or deploy resets the counter, so the "soft brake" wording stays right. |
| Address for the code comes from the session only | TRUE. `resolveIdentity` takes the email from `getUser()` on the user-context client; the reauth route reads only `step`, `resend`, `code` from the body. The 422 `otp_disabled` branch returns `sent`, as stated. |
| Note not delivered to the team until PR-D | TRUE (no delivery code exists), and the card says "saved with your decision". Stated in the posture row and ADR-319 already; **added** to the register amendment, the LIA and the attestation (not-attested list). |
| Flag effectively global | TRUE. Both routes and both pages call `isApprovalQueueEnabled({ userId, workspaceId: null })`. The posture row and ADR-319 said so; the register amendment, LIA and attestation property 10 did not, and "operator first" read as if the flag enforced it. **Corrected**; the gdpr-gate exit's earlier "flag read per user" now carries a pointer to its own addendum. |
| Notice wording is the counsel-pinned text | TRUE (string comparison above; `legal-copy.test.ts` pins it). Not edited. |
| No real legal text committed | TRUE. `texts/` holds only `README.md` and `.gitattributes`; every key answers not-found. |
| Card copy PROVISIONAL behind the flag | TRUE (`LEGAL_COPY.PROVISIONAL` is true, both sign-offs null). |
| Event count | **Corrected.** The register and LIA listed `row_without_event` among events "the screen reports". The screen emits `accepted`, `decide_rejected`, `reauth_failed` and `page_read_failed`; `row_without_event` is defined but nothing emits it until the PR-D check endpoint. Events carry ids and tags, not the text, code, address or note; user ids are pseudonymised at the Sentry boundary under PA-8. |
| Resend not named in the gdpr-gate exit | Added (mail relay for the Supabase code email, already a listed processor; no new recipient). |

### Per-artifact verdicts

| Artifact | Verdict |
|---|---|
| article-30-register.md (PA-40 scope note and Status) | Accurate after correction (event count, flag scope, note delivery). |
| compliance-posture.md row | Accurate; no edit. |
| LIA | Accurate after correction (ceiling caveat, flag scope, note delivery, event count, address-from-session, a trigger clarified). |
| Attestation record | Accurate after correction (property 10, not-attested list). Still a drafted record; sign-off block blank and untouched. |
| gdpr-gate exit | Accurate after correction (ceiling caveat, flag line, Resend). Heuristic gate output, says so. |
| DSAR and notice note (not in the diff) | Unchanged; the card carries it word for word. |

### Determinations

- **Lawful basis.** Art. 6(1)(f) with the standalone LIA remains supportable for the operator. The card improves the expectation-gap limb because both notices now precede the choice, but the limb is closed only in part: the retention period shown is a placeholder, and the notice has not been tested with a reader other than the drafter. A Yes on the card is acceptance of a legal text, not GDPR consent: no processing here rests on Art. 6(1)(a), so no Art. 7(3) withdrawal mechanics are owed, and "final once recorded" is not an Art. 7 defect. Whether an email-code Yes forms an enforceable acceptance is a contract question outside this review.
- **Notice (Art. 13).** The card-level notice (c-2) names the account identifier, text version and fingerprint, time, and the code-confirmation time for a Yes. The row also holds the sign-in session identifier and the checksum; the erasure reply lists them, the card notice does not. It also states no legal basis and does not link the privacy documents. Acceptable for the operator under the Art. 13(4) fallback; for any other founder the wording must be completed by counsel. Wording is pinned and was not edited. Recorded as non-blocking N4.
- **Retention.** Unchanged and not decided: life of the instrument plus 5 years, cap 10, unconfirmed (item 17(a)). No deletion path exists (#12080). The notice that the record is kept after account deletion is accurate against the code (no erasure step touches the tables).
- **Erasure.** Unchanged: Art. 17(3)(e) with Art. 6(1)(f) stays a counsel item (17(b)); PA-40 item 17 and #12080 remain open.

### Disposition

**DISCHARGED for the merge of PR #12148**, as the PR-B discharge was: the card is dark by default (flag off, no real text committed), the copy is PROVISIONAL, and every counsel-owned decision stays open. Not external counsel; the attestation sign-off block stays blank.

Conditions (enabling gates, not the merge):

1. The retention period and the erasure path for a retained row (PA-40 item 17, #12080) remain counsel decisions. No real row before the period is filled in the card-level notice or the "to be confirmed" line is removed from the display text, or the operator records an express deferral (PR-B condition 2 stands).
2. Because the flag is effectively global, the card must stay dark for any founder other than the operator. Do not switch `approval-queue` on in production, and do not commit a real text to `server/legal-acceptance/texts/`, until either the flag is confirmed confined to the operator or the non-operator gates are met (final-form Privacy Policy, Data Protection Disclosure and GDPR Policy with mirrors and SHA pins; LIA re-run; notice wording completed per N4).
3. The Request changes note must either have a delivery path (PR-D) or the card copy must stop implying the team will read it, before the first real Request changes.
4. The ADR-319 enabling conditions stand, including confirming the Supabase single-session-per-user setting is off.
5. Open items from the PR-B audit (N2, #12080, item 17 (a) to (g)) are unchanged.

*Draft material for internal attestation; not legal advice. External counsel re-review follows the frontmatter triggers and counsel item 17.*

---

## Addendum 2026-11-06 (PR-D, ship-time attestation)

Status: CLO-agent-attested, draft, pending counsel for #12080 (PA-40 item 17). v1 internal counsel-review attestation under the ship Phase 5.5 gate for PR #12187 (PR-D of #12011: migration 185, the read-only check endpoint, the hold gate). The plan declares `brand_survival_threshold: single-user incident`. Authority and limits as stated above: CLO agent function, **not external counsel**, operator veto retained, external counsel reserved for the frontmatter triggers and item 17. This addendum is conditioned on the merge of PR #12187; the text above is unchanged. It strips no `[DRAFT` marker, edits no `Last Updated` line and leaves the sign-off block of the attestation record blank. Draft material, not legal advice.

**Scope of the disposition.** It is about publishing the draft-marked disclosures and records with the endpoint shipped dark (route answers 503 until the token and the founder uuid are configured; the `approval-queue` flag stays off). It is not about enabling processing.

**Method.** The prose of the published documents (Privacy Policy 4.17 and Amended paragraph, GDPR Policy 3.19 and Amended paragraph, Data Protection Disclosure 2.3(aj) and Amended paragraph, canonical and mirror), the register PA-40 cells and Addendum, the LIA addendum, the attestation supersession markers, the DSAR and notice note addendum, the statutory-response catalog and the `DSAR_TABLE_EXCLUSIONS` entry were read against migration 185 (`legal_acceptance_ack`, `ack_legal_acceptance`, `legal_acceptance_ack_state`), the route under `app/api/internal/legal-acceptance/[key]/`, `verifyAcceptance`, `ackState`, `ackWhenFlushed` and `ackAcceptance` in `server/legal-acceptance/service.ts`, and `LEGAL_OPS` and `reportLegalOp` in `server/approval/ops.ts`, with the user-id pseudonymisation in `server/observability.ts`.

### Facts checked

| Fact | Finding |
|---|---|
| Third table holds an acceptance id and a time only | TRUE. `acceptance_id` (primary key, no foreign key) and `acked_at`; no founder id, choice or note. Pseudonymous personal data through the join to `legal_acceptance`, as the documents now say. |
| RPC-only, excluded from the self-serve export for the privilege reason | TRUE. RLS on, every privilege revoked including `service_role`; both functions refuse a caller with a user identity. The allowlist reason matches. |
| Status check returns status, text fingerprint, time, checksum result; never the note | TRUE. The route rebuilds the body from `{status, text_hash, decided_at, row_ok}`. |
| Takes no account identifier from the caller; answers about one configured account; "not available" until configured | TRUE. The founder id comes only from `LEGAL_ACCEPTANCE_FOUNDER_ID`; unset or malformed token or id answers 503 `Not available`, before any lookup. |
| Monitoring events and their content | TRUE as a union across event types. Payloads are key, version, choice, text hash, status, age and a user id that `reportSilentFallback` renames to `userIdHash` (HMAC) at the emit boundary; never the note, the code, the address or the text. The verify route emits `row_without_event`, `record_invalid` and `store_failed` without a user id. |
| Marker written only after the event flush is confirmed; kept with the row; no separate deletion | TRUE. `ackWhenFlushed` writes the marker only when the flush returns true; no sweep or scrub touches the table; L5 (delete ack rows with the decision rows by `acceptance_id`, no cascade) is recorded as part of the #12080 path. |
| Nothing writes the third table until the decision screens run | TRUE. Only `ackWhenFlushed` calls `ack_legal_acceptance`, from the decide route behind the flag, which stays off. |
| Database-owner credential holders | As ruled P2-a: the operator and the production migration pipeline; "no AI-assistant session is meant to use either" is a rule, not a control, and every sentence says so. |

**Correction made in this attestation (one-line prose, six surfaces).** The italic "written ahead of the processing" parenthetical in Privacy Policy 4.17, GDPR Policy 3.19 and Data Protection Disclosure 2.3(aj) (canonical and mirror) said the screens and the write path "ship separately and are not deployed" and that "the two tables" exist. Since PR-C (#12148) merged the screens and the write path are in the codebase behind the flag, and since migration 185 there are three tables. The sentence now reads "the tables that hold the record exist ... the screens and the write path that record a decision are built but switched off ... The record applies from the date those screens are switched on." The `[DRAFT` marker inside the parenthetical is untouched. SHA pins in `legal-doc-shas.ts` regenerated for the three documents; `check-tc-document-sha.sh`, the mirror-drift baseline lint and the scope-block lint exit 0, and `legal-doc-consistency.test.ts` passes.

### Per-artifact verdicts

| Artifact | Verdict |
|---|---|
| Privacy Policy 4.17 and Amended paragraph (canonical, mirror) | Accurate after the correction above. Draft-marked; `Last Updated` untouched. |
| GDPR Policy 3.19 and Amended paragraph (canonical, mirror) | Accurate after the correction above. Draft-marked; `Last Updated` untouched. |
| Data Protection Disclosure 2.3(aj) and Amended paragraph (canonical, mirror) | Accurate after the correction above. Draft-marked; `Last Updated` untouched. |
| `legal-doc-shas.ts` pins | Match the canonical raw bytes. |
| Art. 30 register PA-40 (Scope note, cells, Addendum) | Accurate against migration 185 and the code as ruled L2, X1, L3, L5, P2-a, P2-c; superseded markers sit under the superseded sentences. |
| LIA Addendum 2026-11-05 (PR-D) | Accurate; trigger recorded as met; balancing outcome unchanged for the operator-first stage. |
| Attestation record (supersession markers) | Accurate; sign-off block stays blank. |
| DSAR and notice note (Addendum 2026-11-06) | Accurate; the join query matches the table definitions; produces the ack rows on request for a live and a deleted account. |
| Statutory-response catalog | Accurate; names the record as a requester class. |
| `DSAR_TABLE_EXCLUSIONS` entry | Accurate; one stated reason (privilege), pseudonymous-personal-data position stated. |
| Compliance-posture row | Accurate; the "check endpoint is PR-D" sentence is marked superseded in-cell. |

### Non-blocking observations

- **N5.** The monitoring sentence in the three documents lists "a decision is recorded or refused, a check fails, a decision record has no marker". The email-code step failure (`reauth_failed`), the page read failure and the integrity failure (`record_invalid`) are covered only by "a check fails" read broadly. The recipient (Sentry) and the data are the same as already described; wording to be tightened in the final-form rewrite owed before any non-operator founder.
- **N6.** The sentence that the final-form documents are owed before any founder other than the operator, and that the operator's AI-assistant working session is a counsel question (item 17(h)), stand as written.

### Determinations

- **Lawful basis and balancing.** Unchanged for the operator-first stage (LIA Addendum). The third table adds no recipient, processor or transfer.
- **Retention and erasure.** Unchanged and undecided (item 17(a), (b); #12080). Not decided here.
- **Published drafts.** Publishing these draft-marked paragraphs ahead of the processing is supportable because they state, in the present tense and with dates, what is not yet switched on, and mark themselves pending counsel.

### Disposition

**DISCHARGED for the merge of PR #12187** (dark endpoint, flag off, draft-marked publications). Not external counsel.

Conditions (enabling gates, not the merge):

1. The PR-B and PR-C conditions stand, in particular: no real row, and no `approval-queue` flag on in production, before the retention period is decided by counsel (#12080) or the operator records an express deferral.
2. The final-form Privacy Policy, GDPR Policy and Data Protection Disclosure (with N5 tightened) are owed before any founder other than the operator.
3. Before the verify token and founder uuid are applied in production, the Terraform change (#12196) and the operator's Doppler entry are the operator's act; this attestation authorises no production action.
4. Per D7: before the flag is on in the production project, `select count(*) from legal_acceptance` there must be 0, else the matching ack rows are inserted per the runbook.

*Draft material for internal attestation; not legal advice. External counsel re-review follows the frontmatter triggers and counsel item 17.*

## Addendum 2026-11-07 (#12197, PR #12342): pointer

> Drafted, not counsel-reviewed. Fires on the merge of PR #12342. Nothing above is edited and the disposition above is unchanged.

The retention question that Condition 1 above held open now has a v1 position: on 2026-11-07 the CLO agent ruled, standing in for counsel on the operator's instruction (a human lawyer's review is still owed), that the period is 5 years from the date of the decision, extended only while a legal claim, a complaint or an official inquiry about the record is open. See `knowledge-base/legal/audits/2026-11-07-clo-ruling-founder-acceptance-record-12197.md`. The deletion step is not built (#12080).

## Addendum 2026-11-09, review round 4 (#12365, PR #12438; fires on the merge of the pull request that carries it)

> Drafted by the CLO agent as a v1 internal position standing in for counsel; human review owed. Nothing above is edited. The dispositions above are not re-attested and not withdrawn: each was given for the merge it names. This addendum marks the statements that rested on the `approval-queue` flag being off.

The only listing of the flag is `/var/tmp/fa12365/flags.json`, written 2026-11-08 23:51 +01:00 (22:51 UTC): Doppler prd `FLAG_APPROVAL_QUEUE=1`, Flagsmith segment `role-prd` enabled for the feature, and every server read evaluates with role `prd` (`isApprovalQueueEnabled`), so the flag is ON for every production identity. The CLO did not re-read it.

- **[Superseded 2026-11-09, as to Condition 2 of the PR-B/PR-C conditions ("Because the flag is effectively global, the card must stay dark for any founder other than the operator. Do not switch `approval-queue` on in production ... until either the flag is confirmed confined to the operator or the non-operator gates are met"):]** the flag was switched on in production for every workspace; it is not confined to the operator. What confines the founder card, the decide and reauth routes and the Inbox row to the operator is the configured founder id (`isLegalSurfaceEnabled` compares it before it reads the flag); the purpose of the condition, that no founder other than the operator can record a decision, holds through that gate. The non-operator gates (final-form Privacy Policy, Data Protection Disclosure and GDPR Policy with mirrors; the LIA re-run; the notice wording per N4) are not met.
- **[Superseded 2026-11-09, as to "the `approval-queue` flag stays off" (Scope of the disposition) and "DISCHARGED for the merge of PR #12187 (dark endpoint, flag off, draft-marked publications)":]** the discharge was given on those premises and for that merge. It is not withdrawn and not re-attested; what it says about the flag is no longer true. The endpoint is no longer dark: it answers for the operator's account (a record read back on 2026-11-08).
- **[Superseded 2026-11-09, as to Condition 1 ("no `approval-queue` flag on in production before the retention period is decided by counsel (#12080) or the operator records an express deferral"):]** the flag is on. The retention period has a v1 CLO-agent position (2026-11-07), not a decision by counsel, and the CLO agent found no express deferral by the operator in the repository. The condition was not met as written. The deletion step (#12080) is still not built.
- **[Condition 4 (the count of `legal_acceptance` rows in the production project is 0 before the flag is on) is not recorded as measured in this audit:]** a record for the operator's account was read back on 2026-11-08, so the count was not 0 by then; whether its acknowledgement marker exists is not recorded here. The credential-free counts check (`scripts/legal-acceptance-counts.sh`) and the check endpoint now answer the first part, and the `row_without_event` event the second.

Whether the flag stays on for every production workspace is the operator's decision (R2-4 of `knowledge-base/project/specs/feat-one-shot-founder-acceptance-followups-12365/clo-review-round2-rulings.md`), and it is still open.
