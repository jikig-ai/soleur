# CLO agent wording rulings for the published trio and the card deck (verbatim, 2026-11-08)

Ruled by CLO agent, 2026-11-08: this is a v1 internal ruling standing in for counsel on the operator's instruction of 2026-11-07. A human lawyer's review is still owed. All OLD strings were quoted by the CLO verbatim from `docs/legal/`; the work phase must still prove each OLD matches exactly once before editing and each NEW exactly once after (the CLO transcribed them; a mismatch is a stop-and-ask, not a paraphrase). Do not change `founder-acceptance-record.md`.

## (1) Retention wording

**Canonical block R** (PP 4.17 Retention, GDPR 3.19 Retention, DPD 2.3(aj) Retention).

OLD, from `no retention period is confirmed.` to `a period we have not measured.`:

`no retention period is confirmed. Our proposal, unconfirmed and subject to counsel review, is the life of the legal text plus 5 years and in any case no more than 10 years. No automatic deletion is built yet and the application cannot delete the record. The marker in the third table is kept with the decision record it names and has no separate deletion today. Records of code requests older than 30 days are deleted whenever the next request is made; they are not deleted when you delete your account, so they can outlast it until then. Supabase backups may hold copies for a period we have not measured.`

NEW:

`5 years from the date of the decision, and then we delete the record. This covers the whole record, including any note and the marker in the third table, which is kept and deleted with the decision record it names. If a legal claim, a complaint or an official inquiry about the record is open when the 5 years end, we keep it until that matter is closed. We have not yet built the step that deletes a record at the end of this period (the application cannot delete the record today); we will build it before any record reaches that age, and until then records are kept as they are. Copies in database backups may last for a further period we have not measured. Records of code requests are not covered by the 5 years: those older than 30 days are deleted whenever the next request is made, so one can last longer than 30 days, and they are not deleted when you delete your account. The copies of a decision held by our monitoring are not part of the record and are not covered by the 5 years: our Privacy Policy states 90 days for the copies held by Sentry and Better Stack, and the copy in the logs on our own servers is limited by disk space, not by time, and we have not measured how long it lasts.`

**Other edits**

- PP Kept-after-deletion bullet: no change.
- PP line ~583 (Section 7):
  - OLD: `No retention period is confirmed (proposal: the life of the legal text plus 5 years, at most 10 years, subject to counsel review) and no automatic deletion is built.`
  - NEW: `Kept for 5 years from the date of the decision (longer only while a legal claim, a complaint or an official inquiry about it is open); the step that deletes a record at the end of that period is not yet built (Section 4.17).`
- PP 4.17 The note bullet:
  - OLD: `it is saved with your decision and kept even if you later delete your account.`
  - NEW: `it is saved with your decision and kept for as long as the decision record is kept (5 years from the date of the decision, see Retention above), even if you later delete your account. It cannot be removed on its own: it is deleted together with the record.`
- GDPR 3.19 The note: same edit, with `see Retention above` replaced by `see Retention`.
- GDPR 8.4 retention schedule: no founder-record line exists; add one pointer paragraph: `Founder legal-acceptance records (Section 3.19): not deleted on account deletion; kept for 5 years from the date of the decision, longer only while a legal claim, a complaint or an official inquiry about the record is open. The deletion step is not yet built.`
- DPD 5.3(a):
  - OLD: `(Section 2.3(aj)), once the write path is deployed.`
  - NEW: `(Section 2.3(aj)), which now exists for the Jikigai operator's account.`
- DPD 10.3(l):
  - OLD: `with Article 6(1)(f), once the write path is deployed (Section 2.3(aj)). Records of code requests older than 30 days are deleted when the next request is made and are not deleted on account deletion.`
  - NEW: `with Article 6(1)(f) (Section 2.3(aj)), for 5 years from the date of the decision and longer only while a legal claim, a complaint or an official inquiry about it is open; the step that deletes a record at the end of that period is not yet built. Records of code requests older than 30 days are deleted when the next request is made, are not covered by the 5 years, and are not deleted on account deletion.`
- L2 inconsistency, in all three "Who can see it" passages: the published monitoring sentence says the event carries `text fingerprint`; the committed text says it does not, and `reportLegalOp("accepted")` carries only key, choice, version and the hashed id. Delete `, text fingerprint,` from the list for the decision event. Add: `and one line is written to our logs, which are copied to our log provider (Better Stack)`. Before keeping the "failed check" or "no marker" events in the sentence, grep the `reportLegalOp` call sites for the fields they carry.

## (2) The "written ahead" preface and the status-check sentence

Both are now false. Replace the italic preface in PP 4.17, GDPR 3.19 and DPD 2.3(aj). Keep its `[DRAFT ...]` marker.

- OLD: from `(This is written ahead of the processing it describes.` through `Nothing here states that a record about any particular account exists.`
- NEW: `(Status as of November 8, 2026: since the approval queue was switched on for the Jikigai operator in November 2026, the screens and the write path that record a decision are on for the operator's account only, and a record about that account exists. The record will not apply to any other founder until the Privacy Policy, the Data Protection Disclosure and the GDPR Policy have been updated for that.`

Status-check sentence, in the "Who can see it" passages:

- OLD: `until it is configured it answers "not available", and it is not switched on at the date of this amendment (November 6, 2026). Once it is on, Jikigai's release tooling reads its answer to decide`
- NEW: `where it is not configured it answers "not available". It has been configured for the Jikigai operator's account since the approval queue was switched on for the operator in November 2026. Jikigai's release tooling can read its answer to decide`

Follow-on edits for the same falsehood:

- PP "Why" bullet:
  - OLD: `until the status check described below is switched on, nothing in the product enforces anything from it. Once it is switched on, one use is added:`
  - NEW: `since the status check described below was configured, one use applies:`
- GDPR Purposes: `One further purpose is added once the status check is switched on (it is not switched on at the date of this amendment): (iv)` becomes `One further purpose applies since the status check was configured for the operator's account in November 2026: (iv)`.

No day is given. If the operator has the switch-on date it can replace "in November 2026".

## (3) DRAFT markers

They stay, byte-identical, on all existing sentences. No markers on the new retention sentences. The new Amended entry carries one, like the November 6 entry.

## (4) The L7 concern

Its premises are gone, but the residual risk is small. The published "proposal, up to 10 years" overstates the 5 years the live text commits to, which is worse than silence (Art. 13(2)(a)). The honest phrasing is in block R. The earliest record (2026-11) reaches 5 years in 2031-11, so #12080 must ship before 2031-11-07; when it ships, drop the "not yet built" sentences in the trio and the text in a new version and a new Amended entry.

## (5) TC_VERSION, SHA pins, Amended entries

- No TC_VERSION bump, no re-acceptance (applies only to `docs/legal/terms-and-conditions.md`; `check-tc-document-sha.sh` treats the other documents as drift-only).
- Required: re-pin the three entries in `legal-doc-shas.ts`; edit the three mirrors in lockstep; do not touch the `Last Updated:` line; make no heading changes.
- New `Amended:` entry, placed after the November 6 entry (GDPR: "Section 3.19"; DPD: "Section 2.3(aj)" plus 5.3(a) and 10.3(l)):

`**Amended:** November 8, 2026 — Section 4.17 now states the retention period of the founder decision record: 5 years from the date of the decision, longer only while a legal claim, a complaint or an official inquiry about the record is open. The step that deletes a record at the end of that period is not yet built and will be built before any record reaches that age. This replaces the earlier unconfirmed proposal (the life of the legal text plus 5 years, at most 10 years). It also corrects the notice that this section was written ahead of the processing: since the approval queue was switched on for the Jikigai operator in November 2026, the screens and the write path that record a decision are on for the operator's account only, a record about that account exists, and the status check is configured for that account. It applies to no other founder. It adds no sub-processor, no recipient and no international transfer. Marked draft pending counsel review. Ref #12011, #12365. [DRAFT — pending CLO/counsel review per #12011]`

- Marker under the November 6 entry so its bold sentence is not silently contradicted:

`> **Superseded November 8, 2026 (#12365), as to "they are switched off at the date of this amendment" and "which has not happened at the date of this amendment":** both were true on November 6, 2026 and are no longer; see the November 8, 2026 entry.`

(The work phase checks the two quoted phrases exist in each document's November 6 entry before using the marker; adjust the quoted phrase to the document's actual wording.)

## (6) Code validity (#12366 item 2)

Live setting `mailer_otp_exp: 600` in `configure-auth.sh`; the template says "This code expires in 10 minutes." Change the card, not the template (shared with sign-in; a production auth-config PATCH). Do not edit the template line "Enter this code to sign in to your Soleur account"; neutralise it on the card.

- `dialog.codeBody`: OLD `The code works for a few minutes. Nothing is recorded until your code is checked.` NEW `The code works for about 10 minutes. The email may say the code is for signing in: use it here. Nothing is recorded until your code is checked.`
- `verifyError.wrong_code`: OLD `Codes only work for a few minutes.` NEW `Codes only work for about 10 minutes.`
- `sendError.locked` ("wait a few minutes") is a lockout, stays. `codeHint` "6 to 8 digits" out of scope.
- Tests: update the byte pin at `legal-copy.test.ts`; add one test reading `magic-link.html` for `expires in 10 minutes` and `configure-auth.sh` for `"mailer_otp_exp": 600`.

## (7) First-ever terms text (#12366 item 1)

One neutral wording true for a first-ever text and for an update, by dropping "updated":

- `pendingTitle`: `Accept the ${label}?`
- `acceptedTitle`: `You accepted the ${label}`
- `declinedTitle`: `You said No to the ${label}`
- `answerDetail`: `Accept the ${label}, version ${version}. Nothing is recorded until your code is checked.`
- Unchanged: `yesBody` ("starting today", "ask for a new version"), `acceptedBody`, `changesBody`, `changesRequestedBody`, `expiredBody`.
- Same defect class, change too ("The current terms stay in place" is false when no terms exist yet): `noBody` = `Nothing changes. Nothing is accepted. Final once recorded.`; `declinedBody` = `Nothing changed. Nothing was accepted. This answer is final: to change it, your team sends a new version of the text.`
- Tests: update the full-deck byte pin in `legal-copy.test.ts` with the source; the `answerDetail` regex ending stays valid; `TERMS_PRESUMING` is unaffected.
