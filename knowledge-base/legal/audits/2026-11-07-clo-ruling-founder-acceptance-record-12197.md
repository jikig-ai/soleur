---
title: "CLO agent ruling for the founder-acceptance-record text (#12197, PR #12342): final wording, retention period, card deck and sign-off hygiene"
type: legal-ruling
date: 2026-11-07
issue: 12197
related: [12011, 12080, 12344, 12365, 12366]
status: "CLO-AGENT V1 RULING, standing in for counsel on the operator's instruction. NOT a lawyer's opinion. Human-lawyer review owed."
ruled_by: "soleur:legal:clo agent (two rounds, 2026-11-07; review round 1, 2026-11-08)"
text_sha256: "10d283e02d4543d291468750655bbaf4375f807a585cd5138724a362b993a287"
text_version: "2026-11-07"
---

# CLO agent ruling: founder-acceptance-record (#12197)

> **What this is and is not.** The company has no external counsel. On 2026-11-07 the operator ruled that the CLO agent's ruling (`soleur:legal:clo`) stands in for counsel sign-off on this text. That is the only reason an agent ruling closes the "counsel sign-off" item. It is a v1 internal position, not a lawyer's opinion. No human lawyer has read the text, the retention period or the card deck. This file is the persisted record the pull request, the register, the limited-interest assessment and the architecture decision cite; it is evidence about ONE byte state of the text (the sha256 above). After any later edit to the text, the ruling is re-verified, never assumed.

Rulings below are quoted from the sign-off plan (`knowledge-base/project/plans/2026-11-07-feat-founder-acceptance-record-text-draft-signoff-plan.md`) where the CLO agent's words were recorded verbatim. Where the plan quotes a CLO string and a CTO string that disagree, the CLO owns wording and the CTO owns mechanism. Code is cited by function or constant name, never by line number.

## Round 1 and the deepen-plan follow-ups: final wording, retention, deck, hygiene

### Standing

Operator ruling, 2026-11-07 (quoted from the brief): "the company has no external counsel, so the CLO agent's ruling (soleur:legal:clo) stands in for counsel sign-off." Recorded in the PR as `Ruled by CLO agent, 2026-11-07`.

### CLO agent, A: final wording of `founder-acceptance-record.md`

Apply each edit as exact OLD to exact NEW. Each OLD must match exactly once before and each NEW exactly once after.

**A1. Acknowledgement sentence.**

- OLD: `Saying Yes here records that you acknowledge this description.`
- NEW: `Saying Yes here records that you were shown this description and that you acknowledge it. It is not consent and it does not affect your rights: Jikigai keeps the record on the grounds stated under How long it is kept, whatever you answer.`

**A2. Legal basis.**

- OLD: `Jikigai relies on its legitimate interest (Article 6(1)(f) GDPR) in being able to show later what was decided; Article 17(3)(e) GDPR lets it keep data that may be needed for legal claims.`
- NEW: `Jikigai relies on its legitimate interest (Article 6(1)(f) GDPR) in being able to show later what was decided. Jikigai considers that it may need the record to establish, exercise or defend a legal claim, and keeps it after an erasure request on that ground (Article 17(3)(e) GDPR).`

**A3. Account identifier.**

- OLD: `The account identifier is not anonymous: someone who holds other Jikigai records could link it to you, so Jikigai treats it as personal data.`
- NEW: `The account identifier is pseudonymous, not anonymous: someone who holds other Jikigai records could link it to you. It is personal data, and Jikigai handles it as such.`

**A4. Retention.**

- OLD: `How long the record is kept: [period to be confirmed by counsel].`
- NEW: `How long the record is kept: 5 years from the date of the decision, and then Jikigai deletes it. This covers the whole record, including any note and the marker described above. If a legal claim, a complaint or an official inquiry about the record is open when the 5 years end, Jikigai keeps it until that matter is closed. Jikigai has not yet built the step that deletes a record at the end of this period; it will build it before any record reaches that age, and until then records are kept as they are. Copies in database backups may last for a further period that Jikigai has not measured.`
- When #12080 ships, the "has not yet built" sentence comes out in a new `version`.

**A5. Code-request records (name them).** Insert this paragraph immediately after the paragraph beginning `The record also holds fixed technical labels`:
`Each decision also uses a short-lived request record, kept apart from the decision record. It holds your account identifier, the name, version and fingerprint of the text, the identifier of the sign-in session, the number of attempts, and the times of the request. It never holds the code. Jikigai deletes request records older than 30 days when the next request for a decision is made, so one can last longer than 30 days. A request record is not deleted when you delete your account, and it is not covered by the 5 years above.`

> **Superseded 2026-11-08 (CLO ruling L1, review round 1), as to "it is not covered by the 5 years above":** the served text now reads "it is not covered by the 5 years stated under How long it is kept", because the period is stated further down the text, not above this paragraph. The pinned text carries the amended sentence; this paragraph keeps the original wording as the record of what was first ruled.

**A6. Ack marker.**

- OLD: `A separate marker, linked to the record's identifier, may note when the web service reported the decision to Jikigai's monitoring; it can be missing.`
- NEW: `A separate marker, linked to the record's identifier, may note the time the web service reported the decision to Jikigai's monitoring; it can be missing. Because it can be linked to your record, it is personal data too, and it is kept and deleted together with the record.`

> **Superseded 2026-11-08 (CLO ruling L5, review round 1), as to the A6 NEW sentence "may note the time the web service reported the decision to Jikigai's monitoring":** `acked_at` is written when `Sentry.flush` returns true, which does not prove receipt (it is also true with no transport). The text now reads "may note the time the web service finished trying to send the decision to Jikigai's monitoring (it does not show that monitoring received it); it can be missing."

**A7. Note statement.**

- OLD: `If you choose Request changes, the note is saved with your decision and kept even if you later delete your account.`
- NEW: `If you choose Request changes, the note is saved with your decision and kept for as long as the decision record is kept (5 years from the date of the decision, see How long it is kept), even if you later delete your account. It cannot be removed on its own: it is deleted together with the record.`

**A8. Rights.**

- OLD: `You can ask what Jikigai holds, or object, by writing to <legal@jikigai.com> (Articles 15 and 21 GDPR), and you can complain to the CNIL.`
- NEW: `You can ask what Jikigai holds, ask for erasure or restriction, or object, by writing to <legal@jikigai.com> (Articles 15, 17, 18 and 21 GDPR), and you can complain to the CNIL. Jikigai decides each request or objection case by case and tells you its decision; the record is kept where it is needed for a legal claim, and a note cannot be removed from it on its own.`

No change: the first paragraph apart from A1, the stored-fields list, "How a decision is given", "Who can read it", the checksum paragraph.

Ruled by CLO agent, 2026-11-07: Edits A1 to A8 are the final wording of founder-acceptance-record.md. The text may state the 5-year period as a commitment together with the plain statement that the deletion step is not yet built. The Art. 6(1)(f) and Art. 17(3)(e) framing is adopted as Jikigai's v1 position for the operator-first stage only, and it is not a counsel review.

Effects the CLO named: the LIA keeps `status: draft-requires-counsel-review` (record the ruling in an addendum, do not edit the status); the A5 paragraph makes the text describe `legal_reauth_event`, so that table's columns get a pin (CTO 4b).

### CLO agent, B: the concrete retention period (#12080 question)

Ruled by CLO agent, 2026-11-07: The retention period for the decision record and for the Request-changes note is 5 years from the date of the decision, extended only while a legal claim, a complaint or an official inquiry about the record is open. The start event is the decision date, not the life of the text. The card notice and the Request-changes notice carry that period word for word.

Stated basis (the CLO's, to be carried into the audit record): Code civil art. 2224 (5-year general limitation; the repo's own Art. 30 register applies it in the `tc_acceptances` row and the `workspace_member_removals` row; it also covers Art. 82 GDPR claims per that register row). It is the lowest period with a legal anchor, meets Art. 5(1)(e), and a numeric period beats a "criteria" statement under Art. 13(2)(a). The hold covers interruption of limitation by a pending claim. Rejected: 10 years (L123-22, accounting documents; Art. 17(3)(b) is not claimed here), 7 years (the `tc_acceptances` precedent is B2B commercial terms), 20 years (art. 2232 is an outer limit, not a need), anything under 5 (below the limitation period). Fixed-from-decision start was chosen over a variable start because registry texts have no `valid_until`, the database has no text lifecycle, and `created_at` is the row's own column. The note gets the same period because it cannot be separated from the row today (checksum, write-once guard).

Exact strings:

- Text body phrase: `5 years from the date of the decision`.
- Card notice: replace `[period to be confirmed by counsel]` with `5 years from the date of the decision (longer only while a legal claim, a complaint or an official inquiry about it is open)`. The sentence then reads: "Jikigai keeps this record to be able to show later what was decided, even if you delete your account, for 5 years from the date of the decision (longer only while a legal claim, a complaint or an official inquiry about it is open)."
- FINAL `cardNotice` and note (c-2) (deepen-plan CLO ruling 3, one bold line, supersedes the bullet above where they differ): "Your decision is saved with your account identifier, the text's version and fingerprint, the time, and (for Yes) the time you confirmed the emailed code. Jikigai keeps this record to be able to show later what was decided, even if you delete your account, for 5 years from the date of the decision (longer only while a legal claim, a complaint or an official inquiry about it is open). You can ask what we hold, ask for erasure or restriction, or object by writing to <legal@jikigai.com>, and you can complain to the CNIL."
- Request-changes notice: ending `...up to 1000 characters, and is kept even if you later delete your account.` becomes `...up to 1000 characters, and is kept for 5 years from the date of the decision, even if you later delete your account.`
  > **Superseded 2026-11-08 (CLO ruling L4, review round 1), as to this bullet:** the notice carries the hold clause too. It now ends `...up to 1000 characters, and is kept for 5 years from the date of the decision (longer only while a legal claim, a complaint or an official inquiry about it is open), even if you later delete your account.` A flat "5 years" next to the field where a person may type third-party data understates the retention when a hold applies (Art. 13). `LEGAL_COPY.requestChangesNotice`, the DSAR note (c) bold line and the pinned literal in `legal-copy.test.ts` moved together.

Trigger restated for #12080: build the deletion path before the first non-Jikigai founder, or before any row is 4 years old (12 months before the 5-year date); note redaction is no longer separate because the note is deleted with the row; the request-record purge on erasure and the ack-row deletion stay in scope.

Consequential records (edit in place with `> **Superseded 2026-11-07 (#12197; fires on the merge of the pull request that carries it): ...**` markers, append-only): PA-40 (f) and register item 17(a); LIA "Retention proposal" and its counsel item 1; attestation section 2 ("retention lawful"); DSAR note (b) ("For how long" and the code-request bracket) and sections (c), (c-2); ADR-319 retention paragraphs (as a dated amendment); the compliance-posture row. Do not edit migration 184/185 comments. Source check on citations: art. 2224, L123-22 and the 7-year precedent were verified in the repo's own records; art. 2232, L110-4 and CNIL archiving guidance are from the CLO's memory and flagged unverified.

### CLO agent, C: card deck wording (#12344)

Two deck-owned wordings selected by a declared kind. A single neutral wording for all texts is not acceptable (CLO). Heading for both kinds: `exactTextHeading` becomes `The exact text your answer covers` (the old heading overstates: only the sha256 is stored, never the text; ADR-319 property 4).

> **Superseded 2026-11-08 (CLO follow-up 6, same ruling):** ADR-319 has Properties 1 to 3 only; the heading is grounded on property 4 of the ATTESTATION RECORD (verbatim text not stored, only its sha256), not on an ADR-319 property 4. The citation in this line is superseded by follow-up item 6 below.

| Field (current `LEGAL_COPY` path) | terms kind | acknowledgement kind |
|---|---|---|
| `pending.title(label)` | `Accept the updated ${label}?` | `Acknowledge "${label}"?` |
| `yesRow.body` | `Soleur treats these terms as accepted by you, starting today. Clicking again does not undo it. To change it later you would ask for a new version.` | `Your Yes is recorded as your acknowledgement that you were shown this text. That is all it means: it is not consent and it agrees to nothing. Clicking again does not undo it. To change it later you would ask for a new version.` |
| `noRow.body` | `Nothing changes. The current terms stay in place. Final once recorded.` | `Your No is recorded as your answer. The text stays as it is and nothing is acknowledged. Final once recorded.` |
| `changesRow.body` | `Your note is saved with your decision. Nothing is accepted by asking for changes. Final once recorded.` | `Your note is saved with your decision. Nothing is acknowledged by asking for changes. Final once recorded.` |
| `changes.footer` | `Nothing is accepted by saving this. Your note is saved with your decision.` | `Nothing is acknowledged by saving this. Your note is saved with your decision.` |
| `pending.nothingAccepted` | `Nothing has been accepted.` | `Nothing has been acknowledged.` |
| `pending.notAvailable` | `Answering is not available yet. Nothing has been accepted.` | `Answering is not available yet. Nothing has been acknowledged.` |
| `accepted.badge` | `Accepted` | `Acknowledged` |
| `accepted.title(label)` | `You accepted the updated ${label}` | `You acknowledged "${label}"` |
| `accepted.body` | `Soleur now treats this version as accepted by you. To change this later, ask for a new version.` | `Your Yes is recorded as your acknowledgement that you were shown this version. That is all it means: it is not consent and it agrees to nothing. To change this later, ask for a new version.` |
| `declined.title(label)` | `You said No to the updated ${label}` | `You said No to "${label}"` |
| `declined.body` | `Nothing changed. The current terms stay in place. This answer is final: to change it, your team sends a new version of the text.` | `Nothing changed. Your No is recorded and the text stays as it is. This answer is final: to change it, your team sends a new version of the text.` |
| `changesRequested.body` | `Nothing is accepted. Your note is saved with your decision. This answer is final: to change it, your team sends a new version of the text.` | `Nothing is acknowledged. Your note is saved with your decision. This answer is final: to change it, your team sends a new version of the text.` |
| `expired.body` | `Nothing was accepted. Ask your team to send it again if you still want it.` | `Nothing was acknowledged. Ask your team to send it again if you still want it.` |
| `dialog.answerDetail(label, version)` | `` `Accept the updated ${label}, version ${version}. Nothing is recorded until your code is checked.` `` | `` `Acknowledge "${label}", version ${version}. Nothing is recorded until your code is checked.` `` |
| `index.state.accepted` | `You accepted it` | `You acknowledged it` |

Shared change, both kinds (follow-up ruling): `dialog.codeBody` becomes `The code works for a few minutes. Nothing is recorded until your code is checked.` ("accepted" about a code is ambiguous next to accepted terms; "verified" is on the forbidden list; an exact-string allowlist is NOT permitted.) The terms-kind `answerDetail` tail changes from "accepted" to "checked", the one deliberate deviation from "today's wording byte for byte".

Neutral, no change: `choices.*`, `decline.*`, `replaced.*`, `finalNote`, `page.*`.

Quotes: straight ASCII double quotes around the full first-line title are fine. Test requirement: the first line of an acknowledgement text contains no double quote and no newline.

Ruled by CLO agent, 2026-11-07: The deck takes two deck-owned wordings, terms and acknowledgement, selected by a declared type with no default. The heading `The exact text your answer covers` replaces `The exact text that will be recorded` for both types. A single neutral wording for all texts is not acceptable. #12344 is closable by the PR that carries every row of the table, the selection and the pinned tests.

Ruled by CLO agent, 2026-11-07: `dialog.codeBody` is "The code works for a few minutes. Nothing is recorded until your code is checked." The code sentence in `dialog.answerDetail` ends "Nothing is recorded until your code is checked." in both kinds. No exact-string allowlist is permitted, and quoted full-title labels in the acknowledgement titles are acceptable.

Left open by the CLO (tracked, not fixed here): the terms variant still says "the updated" for a first-ever terms text (fix before the first terms-type text is published); the CPO's deck sign-off is outstanding; `PROVISIONAL` stays true.

### CLO agent, D: sign-off hygiene

- `LEGAL_COPY.signOff.clo` becomes exactly `Ruled by CLO agent, 2026-11-07: v1 internal sign-off, not external counsel` in the same commit as the wording. `signOff.cpo` stays `null`. `PROVISIONAL` stays `true` (no human lawyer; CPO sign-off outstanding; the flag is global; first-real-row and non-Jikigai-founder conditions open). `legal-copy.test.ts` pins `signOff` to `{ cpo: null, clo: "<that string>" }` and `PROVISIONAL` to `true`. The string must pass `FORBIDDEN_CLAIMS` (the deck walker collects it).
- Deck header comment: no longer says the retention placeholder stays until counsel confirms; says the period is the CLO-agent v1 ruling of 2026-11-07 and cites the persisted ruling file.
- Attestation record section 6 (counsel sign-off block): every cell stays blank. The block is for counsel; filling it with an agent would contradict `status: DRAFTED, NOT COUNSEL-REVIEWED`. Add a dated append-only addendum below it, conditioned on the carrying PR's merge, that records the operator's no-external-counsel ruling, the register items the ruling closes as v1 positions (17(a), 17(b) operator-first, 17(c) note, 17(f) 30-day value), and that 17(d), 17(e), 17(g) and the final-form trio stay expressly deferred (that deferral is the operator's act under Condition 3 of the 2026-11-04 audit, not the CLO's). Add a frontmatter pointer key; the re-evaluation trigger "retention period confirmed or changed" has fired and is recorded there.
- Persist the ruling as `knowledge-base/legal/audits/2026-11-07-clo-ruling-founder-acceptance-record-12197.md`; add a pointer addendum to `2026-11-counsel-review-12011.md`; LIA and PA-40 addenda with in-cell superseded markers. Cite code by function or constant name, never by line number.

Residual risk of an agent standing in for counsel (the CLO's 8 points, carried into the PR body):

1. Whether Art. 17(3)(e) covers keeping a record for a foreseeable but not pending claim is contestable; a human or the CNIL might prefer anonymising the founder id on erasure while keeping hash, choice and time.
2. The limitation reasoning rests on the repo register plus recall of art. 2232 and L110-4; not checked against Legifrance; suspension and interruption not reviewed.
3. Evidential weight in a French court (Code civil art. 1366 and 1367, eIDAS) is unassessed; a click plus an email code is not a qualified signature. Needs a human before any terms-type text.
4. Art. 13 sufficiency and the Art. 21(4) separate presentation were tested with no reader other than the drafter; the operator is the only data subject, so Art. 13(4) is the fallback and it fails for any other founder.
5. Matching a bare uuid to a requester after account deletion (Art. 11, 12(6)) is unresolved.
6. The 5 years is a commitment, not a control. If #12080 is not built, Art. 5(1)(e) and the notice are both breached. Backup retention is unmeasured. The note may carry third-party personal data (Art. 14 disproportionate-effort position).
7. The published Privacy Policy, GDPR Policy and Data Protection Disclosure still carry the old proposal and draft markers until the trio is updated; a human must review the final-form trio before any non-Jikigai founder.
8. The operator is both a controller principal and the only data subject. Nothing here is reached for a customer founder.

Ruled by CLO agent, 2026-11-07: Set `LEGAL_COPY.signOff.clo` to exactly "Ruled by CLO agent, 2026-11-07: v1 internal sign-off, not external counsel" in the same commit as the final wording. Leave `signOff.cpo` null and `PROVISIONAL` true. Leave the attestation sign-off block blank, and record the ruling in dated addenda. Founder acceptance, the approval-queue flag and production changes remain operator-reserved, and I do not rule on them.

## Round 2 (verbatim rulings)

### CLO agent, second round (verbatim rulings)

1. Yes and accepted wording, positive first, no "terms" anywhere in the acknowledgement variant, so the ack ban is exact with NO exception pins. Final strings: `yesBody` = "Your Yes is recorded as your acknowledgement that you were shown this text. That is all it means: it is not consent and it agrees to nothing. Clicking again does not undo it. To change it later you would ask for a new version." and `acceptedBody` = "Your Yes is recorded as your acknowledgement that you were shown this version. That is all it means: it is not consent and it agrees to nothing. To change this later, ask for a new version." Ruled by CLO agent, 2026-11-07: the two strings above are final; the ack-variant ban is exact with no allowlist.
2. Finality on every row. Ruled by CLO agent, 2026-11-07: finality is stated on all three rows in both kinds, with the clause " Final once recorded." appended to `noBody` and `changesBody` (strings in the table above); `finalNote` stays on the pending card; `changes.footer` and the decline dialog unchanged.
3. Card rights sentence. Ruled by CLO agent, 2026-11-07: the sentence "You can ask what we hold, ask for erasure or restriction, or object by writing to <legal@jikigai.com>, and you can complain to the CNIL." replaces the old rights sentence in `cardNotice` and DSAR note (c-2) (full final string under CLO B).
4. Temporal qualifier. Ruled by CLO agent, 2026-11-07: no build-state clause in the notices (they state the commitment; a build-state clause would go stale the day #12080 ships and force a pinned-deck change). Required instead: (a) a dated test in `founder-acceptance-record.test.ts` that fails from 2030-11-07 while the text body still contains "has not yet built", failure message naming #12080; (b) #12080 acceptance criteria: the end-of-retention step deletes in ONE transaction the `legal_acceptance` row (so the note goes with it), its `legal_acceptance_ack` row and the founder's `legal_reauth_event` rows, with a test that ages a fixture decision with a note plus its ack row past 5 years, runs the step, asserts all three are gone together and that no other founder's rows are touched; (c) #12080 defines how a hold (claim, complaint, inquiry) is recorded, because "longer only while open" is unimplementable without one, and the step skips held rows.
5. Stored `accept`. Ruled by CLO agent, 2026-11-07: this sentence is required in the persisted ruling file and in `texts/README.md`: "For a text of kind acknowledgement, the stored choice value accept means only that the founder answered Yes to an acknowledgement of that exact text version; it records no acceptance of terms and no consent. Anything that reads a decision row or a check result must read the kind pinned for that text key in the registry before it interprets accept."
6. Heading citation. Ruled by CLO agent, 2026-11-07: `exactTextHeading` = "The exact text your answer covers" stands on property 4 of the ATTESTATION RECORD (verbatim text not stored, only its sha256), the ADR-319 Residual-risk bullet ("only its hash is stored in the row, and the text lives in the repository") and the `text_hash` column set of migration 184. ADR-319 Properties are 1 to 3: do not cite "ADR-319 property 4".
    > **Note 2026-11-08:** the deck-row line earlier in this file that cites "ADR-319 property 4" for the heading is superseded by this follow-up 6: ADR-319 Properties are 1 to 3; property 4 is the ATTESTATION RECORD's.
7. Residual risks 9 to 12 are added to the eight above: (9) the wording was authored and ruled on by the same agent role, no independent read exists; (10) the `approval-queue` flag is read with `workspaceId: null` and cannot target one user (mitigated in this PR by the founder gate below, but the flag itself is still global); (11) a pre-flag `count(*)` under the founder's own login sees only that founder's rows (replaced, see CTO B); (12) AP-009 "Never delete user data" (advisory) is in tension with deleting after 5 years: record a bounded, documented deviation in the ADR-319 amendment (only expired `legal_acceptance` rows, one controlled database-owner action, hold-aware), as ADR-119 documents its AP-009 carve-out.
8. Roadmap CP2 ceiling. Ruled by CLO agent, 2026-11-07: this PR does not edit the roadmap (it says "Not started" today). When edited later by the operator the ceiling is: "Started, operator only: a record of the founder's own decision on a legal text exists behind a feature flag, not enabled in production, on a v1 internal legal position with no external counsel. The batched approval queue for write and send actions is not started." It may not say approvals work for other users, that the record is counsel-cleared, or that it is enforceable.
9. Shared `dialog.codeBody` and the `answerDetail` code sentence: "Nothing is recorded until your code is checked." in both kinds (first-round follow-up, already in the table above). The CTO notes the emailed code expires in 10 minutes (shared sign-in template) while the card says "a few minutes"; reconciling is a wording call left as a known leftover (S6), not changed here.
10. A5 (request records): the migration's 30-day DELETE runs only inside `issue_legal_reauth`, when someone asks for a code. A5 already says "so one can last longer than 30 days"; the text must never promise a hard 30-day upper bound.
    > **Superseded 2026-11-08 (CLO ruling L6, review round 1), as to "runs only inside `issue_legal_reauth`, when someone asks for a code":** verified against migration 184: `issue_legal_reauth` runs `DELETE FROM public.legal_reauth_event WHERE created_at < now() - interval '30 days'` after its input validation and before the advisory lock and every outcome branch, and `decideLegal` calls `issueIntent` for Decline and Request changes as well as the code request for a Yes, so the purge runs on EVERY intent issuance, for all founders and keys; rejected attempts (`hash_mismatch`, `text_expired`) return before `issueIntent` and trigger nothing. The text's own sentence ("when the next request for a decision is made") is correct and stands. The 30-day comment in migration 184 ("whenever any challenge is requested") is not edited, because applied migrations are not edited; this note is the correction.

## Records this ruling closes as v1 positions, and what stays open

Closed as v1 positions only (a human lawyer's review is still owed for each): Art. 30 register item 17(a) retention; 17(b) the operator-first reading of Art. 13(4); 17(c) the note period; 17(f) the 30-day figure for request records. Stay expressly open and deferred (the operator's act under Condition 3 of the 2026-11-04 audit, not the CLO's): 17(d), 17(e), 17(g), the DPIA screening, and the final-form published trio.

## Stored `accept` on an acknowledgement text

For a text of kind acknowledgement, the stored choice value accept means only that the founder answered Yes to an acknowledgement of that exact text version; it records no acceptance of terms and no consent. Anything that reads a decision row or a check result must read the kind pinned for that text key in the registry before it interprets accept.

## Scope-out: the emailed code template

The emailed code uses the shared sign-in template, which says 'sign in to your Soleur account' and '10 minutes'. The card says what the code is for. Not changed here (tracked with the other wording follow-ups in #12366).

## Residual: a text that loses its declared kind vanishes from the card pages

A registered text with no declared card kind renders no card, is a 404 on the card page and the routes, and is left out of the index (CTO ruling, no default kind). Its rows stay in the database for a data-subject access export. The three-way key-set equality test and the published pin make losing a declaration impossible without deleting the text; a deleted text's key is already `unknown_key`. Residual recorded once, here.

## Pre-flag read (non-vacuous; CTO ruling B2)

The founder-login `select count(*) from public.legal_acceptance` only sees the founder's own rows (row-level security `legal_acceptance_founder_select`; the service role has no privilege on the table), so it is not the pre-flag check. Two reads replace it: (a) structural: before this text is merged no committed text exists on `main` and `guardLegalRequest` answers 404 for every unknown key, so no row can have been recorded through the app for any user; (b) observable: the decide route emits one Sentry `accepted` event per recorded row (feature `legal-acceptance`, op `accepted`); the count is expected to be 0 before and exactly 1 after the founder's own first acceptance. Admin SQL is the one blind spot. The Sentry count was NOT read in the work phase of this change: unverified.

## Tracking

- #12080: deletion path, external anchor, reauth-event erasure. Trigger restated (before the first non-Jikigai founder, or before any row is 4 years old). Acceptance criteria 4(b) and 4(c) of the CLO ruling are recorded on that issue.
- #12365: the published Privacy Policy, GDPR Policy and Data Protection Disclosure still carry the old retention proposal; a precondition for turning the flag on for anyone but the operator.
- #12366: terms wording "the updated", code-lifetime wording and the base-SHA pin guard.
- #12344: card copy "terms" for an acknowledgement text; closed by the pull request that carries every row of the deck table.

## Review round 1 (2026-11-08): the CLO agent's rulings on the panel's findings

Ruled by CLO agent, 2026-11-08: the thirteen-seat review of PR #12342 at `a22578f5ad` found no P1 in the text. The rulings below change the text bytes (new sha256 in the front matter: `10d283e02d4543d291468750655bbaf4375f807a585cd5138724a362b993a287`, 6496 bytes; the earlier byte state was `43eef1162d0c8148b7fe5d62adaa116d0102249794163302592453ce9ce983f1`). Edits A1 to A8 stand; L1, L2 and L5 were applied after the panel review. The version stays `2026-11-07` because the text was never on `main`. This is still a v1 internal position standing in for counsel on the operator's instruction; a human lawyer's review is owed.

| Item | Ruling | Applied |
|---|---|---|
| L1 | A5 pointed at "the 5 years above" but the period is stated below. NEW: `and it is not covered by the 5 years stated under How long it is kept.` | text, pinned in `founder-acceptance-record.test.ts` |
| L2 | Add disclosure of the MONITORING COPIES. Confirmed against the code: `decideLegal` calls `reportLegalOp("accepted")` for every recorded row; `warnSilentFallback` writes one pino line and one Sentry message with `feature`, `op`, `userIdHash` (HMAC-SHA256 with a pepper), `key`, `choice`, `version` and the time; a refused decision (`decide_rejected`) carries the reason instead of the version; no note, code, fingerprint or email. Retention as documented in the repo: Sentry 90 days (PA-8(f), a plan default, not measured for this organisation); Better Stack 90 days for WARN and above (Privacy Policy, GDPR Policy); on-host journald capacity-bound (`SystemMaxUse=1G`, shared), no time bound, unmeasured. The text states the copies under "Who can read it" and says in "How long it is kept" that they are outside the 5 years, quoting 90 days only as what the Privacy Policy states. The card notice is a summary and is unchanged. The two ruled strings, verbatim as they are in the text: (Edit 1, a new bullet under "Who can read it") `Jikigai's monitoring: each time you give a decision, the web service sends one event to Jikigai's error-tracking provider (Sentry) and writes one line to its logs, which are copied to its log provider (Better Stack). They hold a keyed hash of your account identifier (Jikigai can still link it to you), the name of the text, your choice, the time and, for a decision that is recorded, the version (for one that is not recorded, the reason instead). They do not hold your note, the code or the fingerprint. The people who run Jikigai's monitoring, and those two providers, can read them.` and (Edit 2, added to "How long it is kept") `The monitoring copies described under Who can read it are not part of the record and are not covered by the 5 years. Jikigai's Privacy Policy states 90 days for the copies held by Sentry and Better Stack; the copy in the logs on Jikigai's own servers is limited by disk space, not by time, and Jikigai has not measured how long it lasts.` | text (two edits); the 90-day duration is the one deliberate new token in `founder-acceptance-record.test.ts` |
| L3 | The scope sentence ("This record applies to whoever signs in and gives an answer here") says what the record applies to, not who is shown it; it is true while the gate admits only the operator and stays true when it widens. No change. | none |
| L4 | `requestChangesNotice` and DSAR note (c) gain the hold clause (see the marker under the Request-changes bullet). | `legal-acceptance-copy.ts`, DSAR note (c), `legal-copy.test.ts` |
| L5 | The ack marker wording (see the marker under A6). | text |
| L6 | The 30-day purge runs on every intent issuance (see the marker under item 10 of the follow-ups). Records marked: this file, the LIA, the attestation. The data protection disclosure is a published document (`docs/legal/`) and is not touched (L7). The migration 184 comment is not edited. Register items 17(b), 17(c) and 17(f) are changed in the cell to "closed as a v1 position (CLO agent, 2026-11-07; human review owed)" with the old wording quoted in a marker; the DSAR note's "Notes for the person answering" line is marked stale; the ADR-319 AP-009 bullet now names the ack and reauth rows; the ADR "no text is committed" line is conditioned on the merge. | records |
| L7 | Leave the published Privacy Policy, GDPR Policy and Data Protection Disclosure unchanged and disclose in the PR body (#12365). Reasons: they only understate the retention ("no period confirmed; proposal"), they do not mislead; the flag is off and the only data subject is the operator; dated markers on the published surface would publish "5 years" to every visitor before #12080 builds the deletion step (a public commitment with no control behind it) and would turn the legal-document consistency and SHA gates red or force a re-pin; a partial edit of three documents and their mirrors is the drift class the gates measure agreement on, not truth. #12365 stays the precondition for admitting any non-operator founder. | PR body |
| L8 | No text change. Residual 13 and the pre-flag check below. | this file |

**Residual risk 13 (same-label hash drift), drafted by the CLO agent.** The uniqueness key is `(founder_id, key, text_hash)`, so a row recorded in dev or preview against an earlier draft hash under version `2026-11-07` would sit beside the final hash. "Final for this text" is therefore enforced per hash, not per label. From the merge of PR #12342 (this rule fires on that merge) the label `2026-11-07` is spent: any later byte change to the text takes a new version. Production exposure found: none (no committed text existed on `main`, `guardLegalRequest` answers 404 for an unknown key, and dev and preview use a distinct Supabase project). The Sentry `accepted` count remains unmeasured.

**Pre-flag check, addition (L8).** Before the flag is turned on in production, the database owner runs `select text_hash, count(*) from public.legal_acceptance where key = 'founder-acceptance-record' group by text_hash`. The only acceptable results are no rows, or one hash equal to the registry hash (the pin in `registry-pins.test.ts`). Any other hash means the version is bumped first. This is in addition to the two reads in the section "Pre-flag read" above, and it is the one read that needs the database owner, not the founder's login.

## Review round 1 (2026-11-08): the CTO agent's rulings recorded here for the legal reader

Ruled by CTO agent, 2026-11-08: T1 the pull request ends as a DRAFT carrying the `parked` label (draft is the only hold that works in every checkout; the barrier exists only on this branch); T2 the hook barrier is hardened and described honestly as a best-effort guardrail; T3 `hold-gate-eval.sh` refuses `web-acceptance` gates on acknowledgement keys (`WA_NON_TERMS_KEYS`); T4 the founder gate reports a missing or malformed founder id once and the decide route re-checks the gate per request; T5 the smaller items. The full table is in the sign-off plan, section "Review round 1 rulings".
