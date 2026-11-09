# CLO agent fix-round rulings on the 10-seat review's legal doubts (verbatim, 2026-11-09)

Ruled by CLO agent, 2026-11-09: a v1 internal ruling standing in for counsel on the operator's instruction of 2026-11-07; a human lawyer's review is separate and still owed (#12365 stays open for it). PR #12438, branch `feat-one-shot-founder-acceptance-followups-12365`, HEAD 977017b2c4. Sources: `/var/tmp/review-12438-fr-legal.md` (twelve doubts) and the legal parts of `-user-impact`, `-data-integrity`, `-observability` and `-security` (F3). Every OLD string was transcribed from `docs/legal/` at HEAD; every NEW string is the exact text applied; the same strings apply to the canonical file and its Eleventy mirror (link FORM unchanged). `apps/web-platform/server/legal-acceptance/texts/founder-acceptance-record.md` is NOT changed (sha256 `10d283e02d4543d291468750655bbaf4375f807a585cd5138724a362b993a287`).

Round numbering (doubt 11), ruled: the signed audit trail counts rounds as `knowledge-base/legal/audits/2026-11-07-clo-ruling-founder-acceptance-record-12197.md` does: round 1 = the 2026-11-08 rulings L1 to L7 on PR #12342; round 2 = `clo-wording-rulings.md` (2026-11-08); round 3 = `clo-review-round2-rulings.md` (2026-11-09; the file name counts the second review round of this PR, not the audit's round); round 4 = THIS file (2026-11-09). The audit's numbering governs every register, posture and audit marker. Existing file names are cited by path in many records and are not renamed.

## Decision summary

- ONE append-only rule (doubts 6, 7, 10). Append-only attaches to text that has been on the PUBLISHED surface, which is `origin/main` (`git show origin/main:<path>`), not to text that exists only on this branch. Text on `origin/main` (the October 29 and November 6 Amended entries, the pre-existing `[DRAFT ... per #12011]` markers, the `**Last Updated:**` note) is never rewritten: it gets a dated `Superseded` marker. Text that exists only on this branch (the November 8 Amended entry, the November 8 status paragraph, the November 9 Amended entry, and every marker written in this PR) is the first publication's draft and is corrected in place, with NO marker, because no reader has seen the text that a marker would mark as false. A body sentence that changed is logged in an Amended entry; it is not a dated record. Knowledge-base records (audits, register, posture, ledger, LIA) stay append-only whatever their publication state, because their history is the repository.
- Consequence: the November 9 `Superseded` marker under the November 8 Amended entry is REMOVED in all six files (the clause it marked is corrected in the entry itself).
- Issue numbers (doubt 10), ruled: the `[DRAFT — pending CLO/counsel review per #12011]` marker is NOT exempt from "no issue or PR number in a new public annotation". It is exempt only as the pre-existing marker (4 in the Privacy Policy and GDPR Policy, 5 in the Data Protection Disclosure on `origin/main`), which stays byte-identical because editing it rewrites published text. The marker at the end of the November 8 Amended entry and of the November 9 Amended entry (both new) is `[DRAFT — pending CLO/counsel review]` with no number, in all six files. This is also what round-2 ruling R5 said ("the Amended entry and the marker omit them"); the November 8 entry was applied against it.
- Dates (doubt 5), ruled: the repository records no date on which the queue was switched on, so no sentence says "since November 2026" for the queue. The only measurement of the flag is `/var/tmp/fa12365/flags.json`, written 2026-11-08 23:51 +01:00 (22:51 UTC); the earlier rulings called it "the listing of 2026-11-09", which is corrected in the knowledge-base records. "As of November 9, 2026" in the published notices is the controller's statement on the date of the amendment; it rests on that listing and was not re-measured by the CLO. The facts about the operator's record and the status check were read on 2026-11-08 and are dated so. SHIP CONDITION: re-read the flag read-only at ship; if it changed, stop and return the notices to the CLO (they would be wrong in the other direction).
- The `approval-queue` flag is not changed and nobody is told to change it (hard constraint). The R2-4 operator question stays open.

## F-A. Monitoring-event sentence (doubts 1 and 2; PP 4.17, GDPR 3.19, DPD 2.3(aj), 'Who can see it')

Finding and reason: "each event carries the name of the text" is false for the events that carry no text key (`reauth_failed`; the `decide_rejected` route-level catch; `store_failed` stage `config`; `page_read_failed` for the page reads and for the Inbox steps other than `registry`). "a database error code" is imprecise: for `store_failed` stage `registry` the code is a text-registry code. The record-failed-integrity event (`record_invalid`, "a stored decision failed its integrity check") was absent from the introductory list although the fingerprint clause relies on it. The names of missing or malformed protected settings (stage `config`) were carried but not listed. The Art. 13 sentence is stated per event ("which of the following an event carries depends on the event, and no event carries all of them") instead of as a union; the full per-event matrix is in the Art. 30 register. This supersedes the NEW string of R2-1e of `clo-review-round2-rulings.md`.

Applies identically to the Privacy Policy, the GDPR Policy and the Data Protection Disclosure (canonical and mirror).

OLD:

```text
receives an event when a decision is recorded or refused, when a check or the email-code step fails, when a page cannot read the decisions or the text or finds a registered text with no card, or when a decision record has no marker; each event carries the name of the text and, depending on the event, some of these: the version, the choice, a reason or the name of the step that failed, an error class, a database error code or the name of the database function that failed (never an error message), the age and status of the record, and an account identifier pseudonymised before it is sent (only events raised from a signed-in session carry it; the events raised by the status check and the counts check carry none); only the event for a record that fails its checksum and the event for a record with no marker carry the text fingerprint, which is not secret; no event carries the note, the code, your email address or the text; and one line is written to our logs, which are copied to our log provider (Better Stack), for each event.
```

NEW:

```text
receives an event when a decision is recorded or refused, when a stored decision record fails its checksum, when a check or the email-code step fails, when a page cannot read the decisions or the text or finds a registered text with no card, or when a decision record has no marker; which of the following an event carries depends on the event, and no event carries all of them: the name of the text, the version, the choice, a reason or the name of the step that failed, an error class, an error code (a database error code, or a code saying what is wrong with a legal text file) or the name of the function that failed (never an error message), the name of a protected setting that is missing or malformed (never its value), the age and status of the record, and an account identifier pseudonymised before it is sent (only events raised from a signed-in session carry it; the events raised by the status check and the counts check carry none); only the event for a stored decision record that fails its checksum and the event for a record with no marker carry the text fingerprint, which is not secret; no event carries the note, the code, your email address or the text; and one line is written to our logs, which are copied to our log provider (Better Stack), for each event.
```

## F-B. Notices at the head of PP 4.15 and DPD 2.3(ah) (doubt 3)

Finding and reason: each notice may say only what its own document promised. On `origin/main`: PP 4.15 named neither the data protection impact screening nor the standalone legitimate-interest assessment and gave no timing; DPD 2.3(ah) named the DPIA screening only ("**DPIA:** no screening completed; owed before the feature is switched on outside a Jikigai-owned workspace"); GDPR 3.17 named both. The GDPR notice is accurate and stays byte-identical. The PP notice states the fact, says it differs from what the Section said, and attributes the two steps to the GDPR Policy. The DPD notice attributes the DPIA to itself and the legitimate-interest assessment to the GDPR Policy.

### Privacy Policy (docs/legal/privacy-policy.md and the mirror)

OLD:

```text
This is earlier than this Section said it would be, and the steps it named as coming first (a data protection impact screening and a standalone legitimate-interest assessment) have not been completed.
```

NEW:

```text
This differs from what this Section said before this notice. The GDPR Policy names a data protection impact screening and a standalone legitimate-interest assessment as steps to come first; neither has been completed.
```

### Data Protection Disclosure (docs/legal/data-protection-disclosure.md and the mirror)

OLD:

```text
This is earlier than this item said it would be, and the steps it named as coming first (a data protection impact screening and a standalone legitimate-interest assessment) have not been completed.
```

NEW:

```text
This is earlier than this item said it would be, and the step it named as coming first (a data protection impact screening) has not been completed. The GDPR Policy also names a standalone legitimate-interest assessment as coming first; it has not been completed either.
```

GDPR Policy 3.17: no change.

## F-C. Counts-reader sentence (doubt 4; PP 4.17, GDPR 3.19, DPD 2.3(aj))

Finding and reason: "and nothing else" and "which the status check already gives to the same reader" overstate. The route answers `{key, registry_hash, total, by_hash, ok_to_flag}`; the status check answers only about the one configured account and only for the exact fingerprint the caller supplies, whereas the counts reader reveals which fingerprints the records carry, across all accounts. Say so; keep "a count of one is information about that one record".

Applies identically to the three documents (canonical and mirror). The start of the sentence (`A second protected internal address, read with the same protected credential, counts the decision records for one named legal text:`) is unchanged.

OLD:

```text
counts the decision records for one named legal text: it returns the total number of records, for each text fingerprint how many records carry it, and whether every record carries the current text's fingerprint, and nothing else. It returns no account identifier, no choice, no note and no time, and it is not limited to one account; while the Jikigai operator is the only founder with a record, a count of one is information about that one record, which the status check already gives to the same reader.
```

NEW:

```text
counts the decision records for one named legal text: it returns the name of the text, the current text's fingerprint, the total number of records, for each text fingerprint how many records carry it, and whether every record carries the current text's fingerprint. It returns no account identifier, no choice, no note and no time. Unlike the status check, which answers only about the one configured account and only for a text fingerprint that the caller supplies, it is not limited to one account and it shows which text fingerprints the records carry; while the Jikigai operator is the only founder with a record, a count of one is information about that one record.
```

## F-D. Status paragraph of November 8 and undated present-tense facts (doubt 5; PP 4.17, GDPR 3.19, DPD 2.3(aj))

Finding and reason: "has been switched on in production since November 2026" has no evidence of a switch-on date; the paragraph is dated November 8 and carried a fact that rests on a later reading. The paragraph now states only the two facts read on November 8 (the screens and write path answer for the one configured account; a record about that account exists) and points to the status notice for the queue. The sentence "It is configured for the Jikigai operator's account, as last checked on November 8, 2026." in 'Who can see it' is already dated and stays.

The OLD is the start of the italic paragraph; the section reference is `Section 4.15` (PP), `Section 3.17` (GDPR), `item 2.3(ah)` (DPD). The rest of the paragraph (from "The record will not apply to any other founder") and its pre-existing `[DRAFT ...]` marker are unchanged.

OLD (PP shown; GDPR and DPD differ only in the reference):

```text
(Status as of November 8, 2026: the approval queue has been switched on in production since November 2026 (see the status notice at the head of Section 4.15), and the screens and the write path that record a decision are on for the Jikigai operator's account only, because they answer only for one configured account; a record about that account exists.
```

NEW (PP shown):

```text
(Status as of November 8, 2026: the screens and the write path that record a decision are on for the Jikigai operator's account only, because they answer only for one configured account, and a record about that account exists. For the approval queue itself, see the status notice at the head of Section 4.15.
```

### `**Last Updated:**` line: inline Superseded marker, dating (doubt 5; all three documents, canonical and mirror)

OLD:

```text
the write path that records a decision is deployed and a record exists for the Jikigai operator's account, and the retention period is 5 years from the date of the decision; see the November 8, 2026 and November 9, 2026 entries below.]
```

NEW:

```text
the write path that records a decision was deployed and a record existed for the Jikigai operator's account when last read on November 8, 2026, and the retention period is 5 years from the date of the decision; see the November 8, 2026 and November 9, 2026 entries below.]
```

## F-E. The November 8 Amended entry and the marker under it (doubt 6; all three documents)

Rule: see the decision summary. The November 8 entry is corrected in place and the November 9 `Superseded` marker under it is deleted.

OLD (inside the November 8 entry):

```text
since the approval queue was switched on for the Jikigai operator in November 2026, the screens and the write path that record a decision are on for the operator's account only, a record about that account exists, and the status check is configured for that account.
```

NEW:

```text
as read on November 8, 2026, the screens and the write path that record a decision are on for the operator's account only, a record about that account exists, and the status check is configured for that account.
```

DELETE the whole blockquote paragraph (and one adjacent blank line) that begins `> **Superseded November 9, 2026, as to "since the approval queue was switched on for the Jikigai operator in November 2026":**`.

Marker at the end of the November 8 entry (all three documents, canonical and mirror):

OLD: `Marked draft pending counsel review. [DRAFT — pending CLO/counsel review per #12011]`

NEW: `Marked draft pending counsel review. [DRAFT — pending CLO/counsel review]`

## F-F. The "further" Superseded marker under the November 6 entry (doubt 7; all three documents)

Finding and reason: the bold run of the November 6 entry has two sentences; only the first is superseded. "the retention period is no longer owed" overstated: the period is now stated but is a drafted position, and the rest of the sentence (final wording for any founder other than the operator) stays owed. The existing November 8 marker stays byte-identical.

OLD:

```text
> **Superseded November 9, 2026, further, as to "This is described ahead of the processing" and "the retention period, is still owed":** the whole bold sentence that begins "This is described ahead of the processing" is superseded, not only the two phrases quoted above (the table is written to, a record exists for the Jikigai operator's account and the status check is configured for it), and the retention period is no longer owed: it is stated in the November 8, 2026 entry. "It applies at first only to the Jikigai operator" still holds for the founder decision record.
```

NEW:

```text
> **Superseded November 9, 2026, further, as to the first sentence of the bold passage, "This is described ahead of the processing" through "which has not happened at the date of this amendment", and as to "the retention period, is still owed":** the first sentence is superseded in full, not only the two phrases that the November 8, 2026 marker quotes (the table is written to, a record existed for the Jikigai operator's account when last read on November 8, 2026, and the status check was configured for that account when last checked on November 8, 2026). The second sentence of the bold passage ("It adds no sub-processor, no recipient and no international transfer.") is not superseded and is restated in the November 9, 2026 entry. Of the following sentence only "the retention period" is superseded: the period is now stated in the November 8, 2026 entry, as a drafted position pending counsel review; the rest of that sentence, that the final wording for these documents "is still owed before the record applies to any founder other than the Jikigai operator", still holds.
```

## F-G. The November 9 Amended entry (doubts 3, 4, 9, 10; all three documents)

Corrected in place (rule above). Apply, within the paragraph that begins `**Amended:** November 9, 2026`:

1. Privacy Policy only. OLD `That is earlier than this policy said it would be, and the data protection impact screening` NEW `That differs from what this policy said, and the data protection impact screening`.
2. Data Protection Disclosure only. OLD `and the data protection impact screening and the standalone legitimate-interest assessment that the GDPR Policy names as coming first have not been completed` NEW `and the data protection impact screening that this disclosure names as coming first and the standalone legitimate-interest assessment that the GDPR Policy names as coming first have not been completed`.
3. The sections list and the Section 4.17 / 3.19 / 2.3(aj) clause. OLD (PP) from `Sections 4.15, 6 and 7 are corrected in the same way.` through `(it says what each kind of event carries and when the text fingerprint is included)`; NEW:

```text
Sections 4.15, 6 and 7 are corrected in the same way, and Sections 4.14 and 5.9 gain a pointer to the status notice at the head of Section 4.15. Section 4.17 is also changed: its status paragraph says that the screens and the write path that record a decision answer only for the Jikigai operator's account (the founder decision record itself stays limited to one configured account) and points to Section 4.15 for the approval queue itself; the sentence on the status check is dated and does not tie the check to the approval queue; a sentence describes a second protected internal address that returns counts and text fingerprints for one legal text and no account identifier, choice, note or time; and the sentence on what our monitoring events carry says that what an event carries depends on the event
```

   (Privacy Policy only: the clause list continues with `; and the reference to the 90-day figures ...`, so the NEW has `; the sentence on what our monitoring events carry says ...` with no "and" before "the sentence" and "a sentence describes ... time;" before it.) GDPR: `Sections 3.17, 5.3, 8.4, 9 and 10 are corrected in the same way, and Section 3.11 gains a pointer to the status notice at the head of Section 3.17. Section 3.19 is also changed: ...` with the same clause list (its 'Section 4.15' reference becomes 'Section 3.17'). DPD: `Sections 2.3(ah), 5.3(a) and 10.3(j) are corrected in the same way, and Section 4.2 gains a pointer to Section 2.3(ah). Section 2.3(aj) is also changed: ...` (reference `item 2.3(ah)`). The PP clause `and the reference to the 90-day figures now points to Sections 5.10 and 5.14 of this policy` that follows is kept.
4. Marker at the end of the entry. OLD `Marked draft pending counsel review. [DRAFT — pending CLO/counsel review per #12011]` NEW `Marked draft pending counsel review. [DRAFT — pending CLO/counsel review]`.

## F-H. Conditional sentences: pointer to the status notice (doubt 9)

The six conditional sentences are true and stay conditional; each gains a pointer. Canonical and mirror.

PP 4.14:

OLD: `*(If the approval queue (Section 4.15) is switched on for a workspace, the recipient address, subject and body`
NEW: `*(If the approval queue (Section 4.15) is switched on for a workspace (for the present state see the status notice at the head of Section 4.15), the recipient address, subject and body`

PP 5.9:

OLD: `Where the approval queue is switched on for a workspace, the recipient address, subject and body of an email an agent proposes to send are also held`
NEW: `Where the approval queue is switched on for a workspace (for the present state see the status notice at the head of Section 4.15), the recipient address, subject and body of an email an agent proposes to send are also held`

GDPR 3.11:

OLD: `where the approval queue (Section 3.17) is switched on for the workspace, in the approval request`
NEW: `where the approval queue (Section 3.17; for the present state see its status notice) is switched on for the workspace, in the approval request`

GDPR 3.17 'What it is':

OLD: `**What it is.** Where the feature is switched on for a workspace, an action proposed`
NEW: `**What it is.** Where the feature is switched on for a workspace (for the present state see the status notice above), an action proposed`

DPD 2.3(ah):

OLD: `)* Where it is switched on, an action proposed by an AI agent`
NEW: `)* Where it is switched on (for the present state see the status notice above), an action proposed by an AI agent`

DPD 4.2:

OLD: `where the approval queue is switched on for a workspace, a proposed email's recipient`
NEW: `where the approval queue is switched on for a workspace (for the present state see Section 2.3(ah)), a proposed email's recipient`

Other "while the feature is on" phrases (GDPR 3.17 and DPD 2.3(ah) amend-2.3(ab) sentences, GDPR PA-28 cross-reference) describe a condition, not a status, and are left.

## F-I. Knowledge-base records (append-only; doubts 8, 11, 12)

Applied as markers or addenda, never as rewrites of the marked text (only the register's status cell of the ledger is corrected in-cell, with a marker):

- `knowledge-base/legal/audits/2026-11-counsel-review-12011.md`: addendum "2026-11-09 (review round 4)" marking Conditions 1, 2 and 4 and the "flag stays off" premises of the PR-C and PR-D dispositions (lines 163, 176, 224 and 228 at HEAD); no re-attestation; the discharges were for their merges and are not withdrawn.
- `knowledge-base/legal/public-security-claim-ledger.md` row A1: status `dark` corrected in-cell to `advisory` (sub-case `unmeasured`) with a Superseded marker in the evidence cell: by the ledger's own definition a control on for any external organisation is not `dark`.
- `knowledge-base/legal/article-30-register.md`: marker after the Addendum 2026-11-09 (counts reader wording; complete field list; the merge-versus-apply window; the date of the flag listing); inline marker on open item 15; a cross-reference under PA-28's Amended 2026-10-29 note.
- The posture row, the attestation record, the DSAR and notice note, the LIA: short round-4 markers (counts-reader wording; listing date).
- `apps/web-platform/server/legal-acceptance/README.md`: the sentence "Turning the flag on is the operator's act" corrected (living document, edited in place).
- Window ruling (doubt 12): the merge is not the effect. The documents site and the release pipeline deploy independently. Between the publication of the documents and the release pipeline applying migration 186 and the route, the published counts-reader paragraph describes a reader that does not answer yet (route absent, or 503 with `store_failed` stage `counts`); nothing is read through it in that window, so the notice runs ahead of the processing. That is the safe direction and is ACCEPTED. The converse (the reader live before the documents show it) is closed by an internal rule: `scripts/legal-acceptance-counts.sh` is not run until the published Privacy Policy shows the counts paragraph.

## F-J. Strings `published-retention.test.ts` should pin (per page, canonical AND mirror; assert inside the section named, not page-wide)

See the final message of this round for the per-page counts. Pins, new or changed:

- Monitoring (PP 4.17, GDPR 3.19, DPD 2.3(aj)) present: `which of the following an event carries depends on the event, and no event carries all of them: the name of the text, the version,`; `when a stored decision record fails its checksum, when a check or the email-code step fails`; `an error code (a database error code, or a code saying what is wrong with a legal text file) or the name of the function that failed (never an error message)`; `the name of a protected setting that is missing or malformed (never its value)`; `only the event for a stored decision record that fails its checksum and the event for a record with no marker carry the text fingerprint, which is not secret`. Absent: `each event carries the name of the text`, `a database error code or the name of the database function that failed`, `choice, text fingerprint, record age`.
- Counts reader present: the unchanged start, then `it returns the name of the text, the current text's fingerprint, the total number of records, for each text fingerprint how many records carry it, and whether every record carries the current text's fingerprint.` and `Unlike the status check, which answers only about the one configured account and only for a text fingerprint that the caller supplies, it is not limited to one account and it shows which text fingerprints the records carry`. Absent: `and nothing else`, `which the status check already gives to the same reader`.
- Status paragraph start (once per document): `(Status as of November 8, 2026: the screens and the write path that record a decision are on for the Jikigai operator's account only, because they answer only for one configured account, and a record about that account exists. For the approval queue itself, see the status notice at the head of`, then a space and the reference `Section 4.15` (PP) / `Section 3.17` (GDPR) / `item 2.3(ah)` (DPD). Absent: `switched on in production since November 2026`.
- Notice head, once per document, unchanged: `(Status as of November 9, 2026: the approval queue is switched on in production for every workspace, including workspaces that Jikigai does not own.`. PP also `This differs from what this Section said before this notice. The GDPR Policy names a data protection impact screening and a standalone legitimate-interest assessment as steps to come first; neither has been completed.`; DPD also `the step it named as coming first (a data protection impact screening) has not been completed. The GDPR Policy also names a standalone legitimate-interest assessment as coming first; it has not been completed either.`; GDPR unchanged (`the steps it named as coming first (a data protection impact screening and a standalone legitimate-interest assessment) have not been completed`). Absent in PP: `This is earlier than this Section said it would be`; absent in DPD: `the steps it named as coming first`.
- Markers: `Superseded November 9, 2026` occurs THREE times per page: two blockquotes (under the October 29 entry; the "further" marker under the November 6 entry) and one inline in the `**Last Updated:**` line; the marker under the November 8 entry is gone. The old claim `The approval queue is not switched on for any workspace that Jikigai does not own` sits on exactly THREE lines per page, all history: the October 29 Amended entry, its Superseded blockquote, and the November 9 Amended entry (which quotes it); every other line is absent of it. The "further" marker present: `as to the first sentence of the bold passage` and `is not superseded and is restated in the November 9, 2026 entry`; absent `the whole bold sentence`, `the retention period is no longer owed`. `[DRAFT — pending CLO/counsel review per #12011]` occurs exactly as often as on `origin/main` (4 PP, 4 GDPR, 5 DPD); the two new entries end `[DRAFT — pending CLO/counsel review]`.
- Last Updated line present: `a record existed for the Jikigai operator's account when last read on November 8, 2026`.

## F-K. Wording for ADR-309 and ADR-319 (the ADR files are owned by another agent; not edited here)

Given in the final message of this round.
