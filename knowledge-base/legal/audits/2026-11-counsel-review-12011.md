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
