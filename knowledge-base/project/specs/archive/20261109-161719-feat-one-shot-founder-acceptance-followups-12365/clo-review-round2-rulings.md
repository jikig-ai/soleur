# CLO agent round-2 rulings on the panel's legal-wording findings (verbatim, 2026-11-09)

Ruled by CLO agent, 2026-11-09: a v1 internal ruling standing in for counsel on the operator's instruction of 2026-11-07; a human lawyer's review is separate and still owed (#12365 stays open for it). PR #12438, branch `feat-one-shot-founder-acceptance-followups-12365`. Every OLD string below was transcribed from `docs/legal/` at the HEAD of this branch and every NEW string is the exact text the work phase applies; the edits are applied from the same source, so OLD matches exactly once per file before and NEW exactly once after (a mismatch is a stop, not a paraphrase). `apps/web-platform/server/legal-acceptance/texts/founder-acceptance-record.md` is NOT changed (sha256 `10d283e02d4543d291468750655bbaf4375f807a585cd5138724a362b993a287`).

Sources: panel files `/var/tmp/review-12438-{data-integrity,deployment-verification,structural-enumeration,user-impact}.md`; flag listing `/var/tmp/fa12365/flags.json` (the `approval-queue` feature: Doppler prd `1`, segment `role-prd` enabled in prd; every server read passes `role: "prd"`, see `server/approval/flag.ts`, so the segment matches every production identity).

## Decision summary

- The published sentence "The approval queue is not switched on for any workspace that Jikigai does not own" is FALSE. It is replaced everywhere by a dated statement of the fact (`As of November 9, 2026 the approval queue is switched on in production for every workspace, including workspaces that Jikigai does not own.`). The operator was not asked to change the flag and nobody is told to. If the flag is changed before merge the wording must be re-ruled (R2-1d-1 note).
- The founder decision record stays limited to the operator's account: `isLegalSurfaceEnabled` compares the signed-in id to the configured founder id first and returns false when none is configured. What was wrong was saying the QUEUE was on for the operator only.
- Every existing `[DRAFT ...]` marker stays byte-identical. The new November 9 Amended entry carries one. The Superseded annotations and the replaced notices carry none of their own (their notices keep the `Draft, pending counsel review.` tail they already had).
- No issue or PR number in any new public annotation.
- Dated records are append-only: Superseded markers, not rewrites. The three `**Last Updated:**` dates are not changed.

## R2-1a. Status paragraph (PP 4.17, GDPR 3.19, DPD 2.3(aj))

Finding and reason: The paragraph says the queue was switched on 'for the Jikigai operator'. The queue is on for every production workspace; what is limited to the operator is the founder decision record (one configured account), not the queue. The existing '[DRAFT ...]' marker that follows stays byte-identical.

### Privacy Policy (docs/legal/privacy-policy.md and the mirror)

OLD:

```text
(Status as of November 8, 2026: since the approval queue was switched on for the Jikigai operator in November 2026, the screens and the write path that record a decision are on for the operator's account only, and a record about that account exists. The record will not apply to any other founder until the Privacy Policy, the Data Protection Disclosure and the GDPR Policy have been updated for that.
```

NEW:

```text
(Status as of November 8, 2026: the approval queue has been switched on in production since November 2026 (see the status notice at the head of Section 4.15), and the screens and the write path that record a decision are on for the Jikigai operator's account only, because they answer only for one configured account; a record about that account exists. The record will not apply to any other founder until the Privacy Policy, the Data Protection Disclosure and the GDPR Policy have been updated for that.
```

### GDPR Policy (docs/legal/gdpr-policy.md and the mirror)

OLD:

```text
(Status as of November 8, 2026: since the approval queue was switched on for the Jikigai operator in November 2026, the screens and the write path that record a decision are on for the operator's account only, and a record about that account exists. The record will not apply to any other founder until the Privacy Policy, the Data Protection Disclosure and the GDPR Policy have been updated for that.
```

NEW:

```text
(Status as of November 8, 2026: the approval queue has been switched on in production since November 2026 (see the status notice at the head of Section 3.17), and the screens and the write path that record a decision are on for the Jikigai operator's account only, because they answer only for one configured account; a record about that account exists. The record will not apply to any other founder until the Privacy Policy, the Data Protection Disclosure and the GDPR Policy have been updated for that.
```

### Data Protection Disclosure (docs/legal/data-protection-disclosure.md and the mirror)

OLD:

```text
(Status as of November 8, 2026: since the approval queue was switched on for the Jikigai operator in November 2026, the screens and the write path that record a decision are on for the operator's account only, and a record about that account exists. The record will not apply to any other founder until the Privacy Policy, the Data Protection Disclosure and the GDPR Policy have been updated for that.
```

NEW:

```text
(Status as of November 8, 2026: the approval queue has been switched on in production since November 2026 (see the status notice at the head of item 2.3(ah)), and the screens and the write path that record a decision are on for the Jikigai operator's account only, because they answer only for one configured account; a record about that account exists. The record will not apply to any other founder until the Privacy Policy, the Data Protection Disclosure and the GDPR Policy have been updated for that.
```

## R2-1b. Status-check sentence in 'Who can see it' (PP 4.17, GDPR 3.19, DPD 2.3(aj))

Finding and reason: 'since the approval queue was switched on for the operator' ties the configuration of the status check to the queue and repeats the false premise that the queue was switched on for the operator alone. The status check is configured by a protected setting naming one account; it has nothing to do with when the queue was switched on. The date is anchored to the last time it was read (plan record of November 8, 2026).

Applies identically to the Privacy Policy, the GDPR Policy and the Data Protection Disclosure (canonical and mirror).

OLD:

```text
It has been configured for the Jikigai operator's account since the approval queue was switched on for the operator in November 2026.
```

NEW:

```text
It is configured for the Jikigai operator's account, as last checked on November 8, 2026.
```

## R2-1c. Counts reader (PP 4.17, GDPR 3.19, DPD 2.3(aj), 'Who can see it')

Finding and reason: The new credential-free counts check is a second reader of the table that the 'Who can see it' passage does not name (panel finding F5; ADR-319 and CTO ruling T5 assign the wording to the CLO). Ruling: disclose it as an aggregate reader. Do NOT write 'no personal data': with one data subject a count of one is information about that one record; say so, and say the same reader already learns it from the status check. Fields checked against the route and RPC: key, registry_hash, total, by_hash, ok_to_flag; no founder id, choice, time or note.

Applies identically to the Privacy Policy, the GDPR Policy and the Data Protection Disclosure (canonical and mirror).

OLD:

```text
whether that session falls within a recorded processing activity is a question for counsel. The database administrator credential is held by the operator
```

NEW:

```text
whether that session falls within a recorded processing activity is a question for counsel. A second protected internal address, read with the same protected credential, counts the decision records for one named legal text: it returns the total number of records, for each text fingerprint how many records carry it, and whether every record carries the current text's fingerprint, and nothing else. It returns no account identifier, no choice, no note and no time, and it is not limited to one account; while the Jikigai operator is the only founder with a record, a count of one is information about that one record, which the status check already gives to the same reader. The operator reads it before a change to a legal text is published, and its output can appear in the operator's working session in the same way as the status check's. The database administrator credential is held by the operator
```

## R2-1d-1. Notice at the head of PP 4.15, GDPR 3.17, DPD 2.3(ah): the false sentence and its two companions

Finding and reason: FALSE as of the Flagsmith listing of 2026-11-09: every production identity is evaluated with role 'prd' and the 'role-prd' segment is enabled for the feature, FLAG_APPROVAL_QUEUE=1 in Doppler prd. 'Not switched on for any workspace that Jikigai does not own', 'may be switched on ... for testing' and 'everything ... is conditional on Jikigai switching it on for a workspace' are all untrue as statements of the present. The honest wording states the fact with an 'as of' date, says it is earlier than the document promised, says the preconditions the documents named (DPIA screening, standalone LIA) are not done (both are stated as not done in GDPR 3.17 and 9 and DPD 2.3(ah) today), states no number, and keeps the 'nothing here states that a request ... has been stored' sentence, which is still true. The trailing 'Draft, pending counsel review.' stays byte-identical in PP and GDPR (the DPD item never carried one).

Note: Operator-open: if the flag is turned off before merge, this wording is wrong in the other direction and must be re-ruled (it cannot be pre-written: the date it was switched off is not known).

### Privacy Policy (docs/legal/privacy-policy.md and the mirror)

OLD:

```text
(The approval queue is not switched on for any workspace that Jikigai does not own. It may be switched on for workspaces that Jikigai itself owns, for testing. Everything in this Section is conditional on Jikigai switching it on for a workspace, and nothing here states that a request about any particular workspace has been stored. Draft, pending counsel review.)
```

NEW:

```text
(Status as of November 9, 2026: the approval queue is switched on in production for every workspace, including workspaces that Jikigai does not own. This is earlier than this Section said it would be, and the steps it named as coming first (a data protection impact screening and a standalone legitimate-interest assessment) have not been completed. What this Section says below about what happens where the approval queue is switched on now applies to every workspace. We state no number of approval requests, and nothing here states that a request about any particular workspace has been stored. Draft, pending counsel review.)
```

### GDPR Policy (docs/legal/gdpr-policy.md and the mirror)

OLD:

```text
(The approval queue is not switched on for any workspace that Jikigai does not own. It may be switched on for workspaces that Jikigai itself owns, for testing. Everything in this section is conditional on Jikigai switching it on for a workspace; nothing here states that a request about any particular workspace has been stored. Draft, pending counsel review.)
```

NEW:

```text
(Status as of November 9, 2026: the approval queue is switched on in production for every workspace, including workspaces that Jikigai does not own. This is earlier than this section said it would be, and the steps it named as coming first (a data protection impact screening and a standalone legitimate-interest assessment) have not been completed. What this section says below about what happens where the approval queue is switched on now applies to every workspace. We state no number of approval requests, and nothing here states that a request about any particular workspace has been stored. Draft, pending counsel review.)
```

### Data Protection Disclosure (docs/legal/data-protection-disclosure.md and the mirror)

OLD:

```text
(The approval queue is not switched on for any workspace that Jikigai does not own. It may be switched on for workspaces that Jikigai itself owns, for testing. Everything in this item is conditional on Jikigai switching it on for a workspace; nothing here states that a request about any particular workspace has been stored.)
```

NEW:

```text
(Status as of November 9, 2026: the approval queue is switched on in production for every workspace, including workspaces that Jikigai does not own. This is earlier than this item said it would be, and the steps it named as coming first (a data protection impact screening and a standalone legitimate-interest assessment) have not been completed. What this item says below about what happens where the approval queue is switched on now applies to every workspace. We state no number of approval requests, and nothing here states that a request about any particular workspace has been stored.)
```

## R2-1d-2. PP 4.15 opening paragraph

Finding and reason: 'only for a workspace for which Jikigai has switched it on' repeats the per-workspace premise.

### Privacy Policy (docs/legal/privacy-policy.md and the mirror)

OLD:

```text
and only for a workspace for which Jikigai has switched it on, the Web Platform can hold
```

NEW:

```text
and, as of November 9, 2026, for every production workspace (see the status notice above), the Web Platform can hold
```

## R2-1d-3. PP Section 6 parenthesis

Finding and reason: 'is not switched on ... and this is stated ahead of any processing' is false on both limbs.

### Privacy Policy (docs/legal/privacy-policy.md and the mirror)

OLD:

```text
(the approval queue is not switched on for any workspace that Jikigai does not own, and this is stated ahead of any processing)
```

NEW:

```text
(the approval queue is switched on in production for every workspace as of November 9, 2026, including workspaces that Jikigai does not own; see Section 4.15)
```

## R2-1d-4. Rights / retention / export pointers: PP 7, GDPR 5.3, GDPR 8.4, DPD 5.3(a)

Finding and reason: Same false sentence followed by 'Where it is switched on,'. Replace the sentence and let the next sentence stand alone ('Where it is switched on, X' becomes 'X is', 'these records are' becomes 'These records are').

### Privacy Policy (docs/legal/privacy-policy.md and the mirror)

OLD:

```text
The approval queue is not switched on for any workspace that Jikigai does not own. Where it is switched on, the action text is removed
```

NEW:

```text
As of November 9, 2026 the approval queue is switched on in production for every workspace, including workspaces that Jikigai does not own. The action text is removed
```

### GDPR Policy (docs/legal/gdpr-policy.md and the mirror)

OLD:

```text
The approval queue is not switched on for any workspace that Jikigai does not own. Where it is switched on, these records are
```

NEW:

```text
As of November 9, 2026 the approval queue is switched on in production for every workspace, including workspaces that Jikigai does not own. These records are
```

OLD:

```text
The approval queue is not switched on for any workspace that Jikigai does not own. Where it is switched on, the action text is removed
```

NEW:

```text
As of November 9, 2026 the approval queue is switched on in production for every workspace, including workspaces that Jikigai does not own. The action text is removed
```

### Data Protection Disclosure (docs/legal/data-protection-disclosure.md and the mirror)

OLD:

```text
The approval queue is not switched on for any workspace that Jikigai does not own. Where it is switched on, these records are
```

NEW:

```text
As of November 9, 2026 the approval queue is switched on in production for every workspace, including workspaces that Jikigai does not own. These records are
```

## R2-1d-5. GDPR 9 (DPIA) approval-requests bullet

Finding and reason: States both the false sentence and an owed-before condition that has been overtaken.

### GDPR Policy (docs/legal/gdpr-policy.md and the mirror)

OLD:

```text
No DPIA screening has been completed. The approval queue is not switched on for any workspace that Jikigai does not own. A screening is owed before it is switched on for any workspace Jikigai does not own, and no conclusion is stated here.
```

NEW:

```text
No DPIA screening has been completed. As of November 9, 2026 the approval queue is switched on in production for every workspace, including workspaces that Jikigai does not own. A screening was owed before that and is still owed; no conclusion is stated here.
```

## R2-1d-6. GDPR 10, item 13 (register entry for PA-38)

Finding and reason: Same false sentence at the end of the register-summary item.

### GDPR Policy (docs/legal/gdpr-policy.md and the mirror)

OLD:

```text
as it relates to the requesting user. The approval queue is not switched on for any workspace that Jikigai does not own. Supabase Inc,
```

NEW:

```text
as it relates to the requesting user. As of November 9, 2026 the approval queue is switched on in production for every workspace, including workspaces that Jikigai does not own. Supabase Inc,
```

## R2-1d-7. DPD 10.3(j)

Finding and reason: Same false sentence closing the erasure item.

### Data Protection Disclosure (docs/legal/data-protection-disclosure.md and the mirror)

OLD:

```text
a workspace that still has other members keeps its record under the workspace identifier. The approval queue is not switched on for any workspace that Jikigai does not own.
```

NEW:

```text
a workspace that still has other members keeps its record under the workspace identifier. As of November 9, 2026 the approval queue is switched on in production for every workspace, including workspaces that Jikigai does not own.
```

## R2-1d-8. GDPR 3.17 'Roles', 'Lawful basis' balancing parenthesis, 'DPIA status'; DPD 2.3(ah) 'DPIA'

Finding and reason: Four promises phrased as 'before the feature is switched on for any workspace Jikigai does not own'. Each reads as if the step had not happened. Each is restated as owed and overdue, without self-description beyond the fact.

### GDPR Policy (docs/legal/gdpr-policy.md and the mirror)

OLD:

```text
This is a working position still being confirmed, and this Policy will be updated first, before the feature is switched on for any workspace Jikigai does not own.
```

NEW:

```text
This is a working position still being confirmed. This Policy said it would be updated before the feature was switched on for any workspace Jikigai does not own; the feature has been switched on (see the status notice at the head of this section) and this update came after it.
```

OLD:

```text
a standalone legitimate-interest assessment is owed before the feature is switched on for any workspace Jikigai does not own)
```

NEW:

```text
a standalone legitimate-interest assessment was owed before the feature was switched on for workspaces that Jikigai does not own, which has happened, and is still owed)
```

OLD:

```text
It is owed before the feature is switched on for any workspace Jikigai does not own, and no conclusion is stated here. See Section 9.
```

NEW:

```text
It was owed before the feature was switched on for workspaces that Jikigai does not own, which has happened, and it is still owed; no conclusion is stated here. See Section 9.
```

### Data Protection Disclosure (docs/legal/data-protection-disclosure.md and the mirror)

OLD:

```text
**DPIA:** no screening completed; owed before the feature is switched on outside a Jikigai-owned workspace.
```

NEW:

```text
**DPIA:** no screening completed; it was owed before the feature was switched on outside a Jikigai-owned workspace, which has happened, and it is still owed.
```

## R2-1e. Monitoring-event field list (PP 4.17, GDPR 3.19, DPD 2.3(aj), 'Who can see it')

Finding and reason: Panel F4 (data-integrity): the published sentence presents a union of fields as if every event carried all of them. Measured against the reportLegalOp call sites: accepted = key, choice, version, hashed id (no age); decide_rejected = reason, key, choice, hashed id (no version; the route-level catch only the reason and the hashed id); reauth_failed = stage, error class, hashed id; page_read_failed = read label, step, key, hashed id; kind_undeclared = key, hashed id; record_invalid = key, text hash; row_without_event = key, text hash, age in seconds, status; store_failed = stage, step, key, variable names (config), error code/function/class, hashed id for stage ack only. describeError keeps only code, fn, errName: never a message. The old sentence under-listed the event kinds and over-attributed fields; the new one names every kind and says 'depending on the event'. The hashed id is added to Sentry's user scope as well as extra; that is still the pseudonym. This supersedes the verbatim L2 wording of the round-1 ruling.

Applies identically to the Privacy Policy, the GDPR Policy and the Data Protection Disclosure (canonical and mirror).

OLD:

```text
receives an event when a decision is recorded or refused, when a check fails, or when a decision record has no marker; the event carries the text name, version, choice, record age and an account identifier pseudonymised before it is sent (the events for a failed check and for a record with no marker also carry the text fingerprint, which is not secret), never the note, the code, your email address or the text; and one line is written to our logs, which are copied to our log provider (Better Stack).
```

NEW:

```text
receives an event when a decision is recorded or refused, when a check or the email-code step fails, when a page cannot read the decisions or the text or finds a registered text with no card, or when a decision record has no marker; each event carries the name of the text and, depending on the event, some of these: the version, the choice, a reason or the name of the step that failed, an error class, a database error code or the name of the database function that failed (never an error message), the age and status of the record, and an account identifier pseudonymised before it is sent (only events raised from a signed-in session carry it; the events raised by the status check and the counts check carry none); only the event for a record that fails its checksum and the event for a record with no marker carry the text fingerprint, which is not secret; no event carries the note, the code, your email address or the text; and one line is written to our logs, which are copied to our log provider (Better Stack), for each event.
```

## R2-1f. PP 4.17 Retention, last sentence: self-reference

Finding and reason: The Privacy Policy says 'our Privacy Policy states 90 days'. In the GDPR Policy and the DPD that is a cross-reference; in the PP it is a document pointing at itself with no section. PP-only fix, with the two sections that carry the figures (5.10 Sentry, 5.14 Better Stack). GDPR and DPD keep the phrase unchanged.

### Privacy Policy (docs/legal/privacy-policy.md and the mirror)

OLD:

```text
our Privacy Policy states 90 days for the copies held by Sentry and Better Stack
```

NEW:

```text
Sections 5.10 and 5.14 of this Privacy Policy state 90 days for the copies held by Sentry and Better Stack
```

## R2-1g. `**Last Updated:**` line: inline Superseded marker under the PR-B founder-record note

Finding and reason: The note still says the record is 'described ahead of the processing: nothing writes to it until the write path ships ... no retention period is confirmed'. The round-1 ruling said not to touch the line; the instruction was about the date and the frozen chain, and the line already carries inline markers of this form ('[Superseded November 4, 2026 (#9066): ...]'). The text is NOT edited; a marker is inserted after the bold sentence. The Last Updated DATE is unchanged. No issue number (new public annotation). published-retention.test.ts excludes lines that start with `**Last Updated:**`, so the quoted phrases do not trip it.

### Privacy Policy (docs/legal/privacy-policy.md and the mirror)

OLD:

```text
no retention period is confirmed. It adds a data category and a purpose but no sub-processor, no recipient and no international transfer.** Marked draft pending counsel review. Ref #12011.)*
```

NEW:

```text
no retention period is confirmed. It adds a data category and a purpose but no sub-processor, no recipient and no international transfer.** [Superseded November 9, 2026, as to "nothing writes to it until the write path ships" and "no retention period is confirmed": the write path that records a decision is deployed and a record exists for the Jikigai operator's account, and the retention period is 5 years from the date of the decision; see the November 8, 2026 and November 9, 2026 entries below.] Marked draft pending counsel review. Ref #12011.)*
```

### GDPR Policy (docs/legal/gdpr-policy.md and the mirror)

OLD:

```text
no retention period is confirmed. It adds no sub-processor, no recipient and no international transfer.** Marked draft pending counsel review. Ref #12011.)*
```

NEW:

```text
no retention period is confirmed. It adds no sub-processor, no recipient and no international transfer.** [Superseded November 9, 2026, as to "nothing writes to it until the write path ships" and "no retention period is confirmed": the write path that records a decision is deployed and a record exists for the Jikigai operator's account, and the retention period is 5 years from the date of the decision; see the November 8, 2026 and November 9, 2026 entries below.] Marked draft pending counsel review. Ref #12011.)*
```

### Data Protection Disclosure (docs/legal/data-protection-disclosure.md and the mirror)

OLD:

```text
no retention period is confirmed. It adds no sub-processor, no recipient and no international transfer.** Marked draft pending counsel review. Ref #12011.)*
```

NEW:

```text
no retention period is confirmed. It adds no sub-processor, no recipient and no international transfer.** [Superseded November 9, 2026, as to "nothing writes to it until the write path ships" and "no retention period is confirmed": the write path that records a decision is deployed and a record exists for the Jikigai operator's account, and the retention period is 5 years from the date of the decision; see the November 8, 2026 and November 9, 2026 entries below.] Marked draft pending counsel review. Ref #12011.)*
```

## R2-1i. New `**Amended:**` entry of November 9, 2026, after the November 8, 2026 entry and its Superseded marker (PP, GDPR, DPD) plus three markers

Finding and reason: Change-log completeness. The November 8 entry listed 4.17 only (PP, GDPR) and 2.3(aj)/5.3(a)/10.3(l) (DPD), but the November 8 edits also touched PP Section 7 (retention pointer and the PP 'Why' bullet), GDPR 8.4 (pointer paragraph) and Purposes (iv), the note paragraphs, and the monitoring-event list. The new entry names every section touched by round 2 and lists, in addition, the unlisted November 8 changes. It carries the DRAFT marker; the markers under the dated entries do not (they are annotations of superseded sentences, not new claims). No issue or PR number appears in any new public annotation (the marker text and the entry), except the pre-existing '[DRAFT ... per #12011]' marker form, which is kept byte-identical.

### Privacy Policy (docs/legal/privacy-policy.md and the mirror)

Insert as a new paragraph directly after the November 8, 2026 Amended entry and its Superseded marker (blank line before and after):

```text
**Amended:** November 9, 2026 — corrects the statement, given in this policy since October 29, 2026, that the approval queue is not switched on for any workspace that Jikigai does not own. As of November 9, 2026 the approval queue is switched on in production for every workspace, including workspaces that Jikigai does not own. That is earlier than this policy said it would be, and the data protection impact screening and the standalone legitimate-interest assessment that the GDPR Policy names as coming first have not been completed. We state no number of approval requests. What Section 4.15 says is stored, who can read it and how long it is kept is unchanged and now applies to every workspace. Sections 4.15, 6 and 7 are corrected in the same way. Section 4.17 is also changed: the status notice no longer says the approval queue was switched on for the Jikigai operator alone (the founder decision record itself stays limited to one configured account); the sentence on the status check no longer ties the check to the approval queue; a sentence describes a second protected internal address that returns only counts for one legal text and no account identifier, choice, note or time; the sentence on what our monitoring events carry is made exact (it says what each kind of event carries and when the text fingerprint is included); and the reference to the 90-day figures now points to Sections 5.10 and 5.14 of this policy. This entry also records changes made on November 8, 2026 that the November 8, 2026 entry did not list: the matching sentence in Section 7, the "Why" bullet and the note paragraph of Section 4.17, and the removal of the text fingerprint from the list of what the monitoring event for a recorded decision carries (the log line copied to Better Stack is now named). It adds no sub-processor, no recipient and no international transfer. Marked draft pending counsel review. [DRAFT — pending CLO/counsel review per #12011]
```

### GDPR Policy (docs/legal/gdpr-policy.md and the mirror)

Insert as a new paragraph directly after the November 8, 2026 Amended entry and its Superseded marker (blank line before and after):

```text
**Amended:** November 9, 2026 — corrects the statement, given in this policy since October 29, 2026, that the approval queue is not switched on for any workspace that Jikigai does not own. As of November 9, 2026 the approval queue is switched on in production for every workspace, including workspaces that Jikigai does not own. That is earlier than this policy said it would be, and the data protection impact screening and the standalone legitimate-interest assessment that this policy names as coming first have not been completed. We state no number of approval requests. What Section 3.17 says is stored, who can read it and how long it is kept is unchanged and now applies to every workspace. Sections 3.17, 5.3, 8.4, 9 and 10 are corrected in the same way. Section 3.19 is also changed: the status notice no longer says the approval queue was switched on for the Jikigai operator alone (the founder decision record itself stays limited to one configured account); the sentence on the status check no longer ties the check to the approval queue; a sentence describes a second protected internal address that returns only counts for one legal text and no account identifier, choice, note or time; and the sentence on what our monitoring events carry is made exact (it says what each kind of event carries and when the text fingerprint is included). This entry also records changes made on November 8, 2026 that the November 8, 2026 entry did not list: the pointer paragraph in Section 8.4, the sentence on purpose (iv) and the note paragraph of Section 3.19, and the removal of the text fingerprint from the list of what the monitoring event for a recorded decision carries (the log line copied to Better Stack is now named). It adds no sub-processor, no recipient and no international transfer. Marked draft pending counsel review. [DRAFT — pending CLO/counsel review per #12011]
```

### Data Protection Disclosure (docs/legal/data-protection-disclosure.md and the mirror)

Insert as a new paragraph directly after the November 8, 2026 Amended entry and its Superseded marker (blank line before and after):

```text
**Amended:** November 9, 2026 — corrects the statement, given in this disclosure since October 29, 2026, that the approval queue is not switched on for any workspace that Jikigai does not own. As of November 9, 2026 the approval queue is switched on in production for every workspace, including workspaces that Jikigai does not own. That is earlier than this disclosure said it would be, and the data protection impact screening and the standalone legitimate-interest assessment that the GDPR Policy names as coming first have not been completed. We state no number of approval requests. What Section 2.3(ah) says is stored, who can read it and how long it is kept is unchanged and now applies to every workspace. Sections 2.3(ah), 5.3(a) and 10.3(j) are corrected in the same way. Section 2.3(aj) is also changed: the status notice no longer says the approval queue was switched on for the Jikigai operator alone (the founder decision record itself stays limited to one configured account); the sentence on the status check no longer ties the check to the approval queue; a sentence describes a second protected internal address that returns only counts for one legal text and no account identifier, choice, note or time; and the sentence on what our monitoring events carry is made exact (it says what each kind of event carries and when the text fingerprint is included). This entry also records a change made on November 8, 2026 that the November 8, 2026 entry did not list: the removal of the text fingerprint from the list of what the monitoring event for a recorded decision carries (the log line copied to Better Stack is now named). It adds no sub-processor, no recipient and no international transfer. Marked draft pending counsel review. [DRAFT — pending CLO/counsel review per #12011]
```

## R2-1h. Superseded markers under the dated entries (PP, GDPR, DPD)

Finding and reason: Append-only: the dated entries are not rewritten. Marker 1 goes in its own blockquote paragraph directly under the October 29, 2026 Amended entry; marker 2 directly under the November 8, 2026 Amended entry (before the November 9 entry); marker 3 is a second blockquote paragraph directly under the existing 'Superseded November 8, 2026' marker below the November 6, 2026 entry (the existing marker stays byte-identical; it is extended by a sibling, not edited). The quoted phrases were grep-verified to exist in each document's entry (the November 6 phrases 'This is described ahead of the processing' and 'the retention period, is still owed' exist in all three; the October 29 phrase 'conditional on Jikigai switching the feature on for a workspace' exists in GDPR and DPD and, in PP, as 'is conditional on Jikigai switching the feature on for a workspace', which contains it).

Applies identically to the Privacy Policy, the GDPR Policy and the Data Protection Disclosure (canonical and mirror).

OLD:

```text
<<marker-oct29>>
```

NEW:

```text
> **Superseded November 9, 2026, as to "The approval queue is not switched on for any workspace that Jikigai does not own." and "conditional on Jikigai switching the feature on for a workspace":** both were true on October 29, 2026 and are not true on November 9, 2026: the approval queue is switched on in production for every workspace, including workspaces that Jikigai does not own; see the November 9, 2026 entry.
```

OLD:

```text
<<marker-nov8>>
```

NEW:

```text
> **Superseded November 9, 2026, as to "since the approval queue was switched on for the Jikigai operator in November 2026":** the approval queue was not switched on for the operator alone; it is switched on in production for every workspace (see the November 9, 2026 entry). The screens and the write path that record a founder's decision remain limited to the operator's account.
```

OLD:

```text
<<marker-nov6b>>
```

NEW:

```text
> **Superseded November 9, 2026, further, as to "This is described ahead of the processing" and "the retention period, is still owed":** the whole bold sentence that begins "This is described ahead of the processing" is superseded, not only the two phrases quoted above (the table is written to, a record exists for the Jikigai operator's account and the status check is configured for it), and the retention period is no longer owed: it is stated in the November 8, 2026 entry. "It applies at first only to the Jikigai operator" still holds for the founder decision record.
```

## R2-2. DRAFT markers

Existing `[DRAFT ...]` markers and `Draft, pending counsel review.` tails stay byte-identical (the PP/GDPR 4.15 and 4.16-style tail inside a replaced notice is re-emitted unchanged). The new November 9 Amended entry carries `[DRAFT — pending CLO/counsel review per #12011]`. No marker on the new status sentences, the counts-reader sentence, the monitoring sentence or the Superseded annotations.

## R2-3. Retention paragraph (not changed) and the strings the tests should pin

The Retention bullet/paragraph written in round 1 is NOT changed (the committed text says the same). Pin these exact strings, per document, canonical AND mirror, and assert them inside the Retention bullet/paragraph or the `(aj)` Retention run, not anywhere on the page (panel structural-enumeration finding on `published-retention.test.ts`):

- Hold clause: `If a legal claim, a complaint or an official inquiry about the record is open when the 5 years end, we keep it until that matter is closed.` (once per document)
- Not-built clause: `We have not yet built the step that deletes a record at the end of this period (the application cannot delete the record today); we will build it before any record reaches that age, and until then records are kept as they are.` (once per document)
- Period lead: `5 years from the date of the decision, and then we delete the record.` (once per document)
- Status paragraph, the start (once per document): `(Status as of November 8, 2026: the approval queue has been switched on in production since November 2026 (see the status notice at the head of`, then a space and `Section 4.15` / `Section 3.17` / `item 2.3(ah)`.
- Replaced notice, the head (once per document): `(Status as of November 9, 2026: the approval queue is switched on in production for every workspace, including workspaces that Jikigai does not own.`
- Short form (PP 7; GDPR 5.3 and 8.4 and 9 and 10; DPD 5.3(a) and 10.3(j); PP 4.15 intro uses the other form): `As of November 9, 2026 the approval queue is switched on in production for every workspace, including workspaces that Jikigai does not own.` Sites and counts: PP 1 (Section 7); GDPR 4 (5.3, 8.4, 9, 10); DPD 2 (5.3(a), 10.3(j)); each document also repeats the sentence once in its November 9, 2026 Amended entry, so a page-wide count is sites plus 1 (PP 2, GDPR 5, DPD 3, as applied). The PP Section 6 parenthesis uses its own form, pin `the approval queue is switched on in production for every workspace as of November 9, 2026, including workspaces that Jikigai does not own; see Section 4.15` once; the PP 4.15 opening paragraph uses `and, as of November 9, 2026, for every production workspace (see the status notice above), the Web Platform can hold` once. Pin presence per section, not a page-wide count.
- ABSENCE of the false sentence `The approval queue is not switched on for any workspace that Jikigai does not own` on every line that does NOT start with `**Amended:**` or `> **Superseded` (the October 29 Amended entries and the Superseded markers quote it by design). Also absent on those lines: `may be switched on for workspaces that Jikigai itself owns, for testing`, `is conditional on Jikigai switching it on for a workspace`, `and this is stated ahead of any processing`, `before it is switched on for any workspace Jikigai does not own`, `before the feature is switched on for any workspace`, `written ahead`, `once the write path is deployed`, `not switched on at the date of this amendment`.
- Counts reader sentence start (once per document): `A second protected internal address, read with the same protected credential, counts the decision records for one named legal text:`
- Monitoring sentence: absent `choice, text fingerprint, record age` and absent `the event carries the text name, version, choice, record age`; present `each event carries the name of the text and, depending on the event, some of these:` and `only the event for a record that fails its checksum and the event for a record with no marker carry the text fingerprint`.
- PP only: absent `our Privacy Policy states 90 days`; present `Sections 5.10 and 5.14 of this Privacy Policy state 90 days`.
- The Last Updated line: present `[Superseded November 9, 2026, as to "nothing writes to it until the write path ships"`.

## R2-4. Open question for the operator

- Is the `approval-queue` flag meant to stay on for every production workspace? Nothing in the repository records a decision to widen it beyond the Jikigai canary, and the enabling-gate row requires conditions (a) to (k) for that. The published wording above states the present fact; it does not endorse it. If the operator turns the flag off before merge, tell the CLO: the wording has to be re-ruled, and the record that the queue was on for every production workspace on and before November 9, 2026 stays (it is a fact about the past, and it matters for any request that was recorded in that period).
- The number of `approval_request` rows for workspaces that Jikigai does not own is unmeasured. The published text says so by stating no number. Measuring it needs a production read the CLO was told not to run.
