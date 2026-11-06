# gdpr-gate output: #12011 PR-C (web card and email-code check), work-phase exit, 2026-11-05

**This is not legal review. Findings are heuristic. Consult `soleur:legal:clo` + `soleur:legal:legal-compliance-auditor` before merging.**

Scope: the cumulative diff of branch `feat-founder-approval-cards-pr-c` against `origin/main`. Regulated-data paths matched by the canonical regex: the two route files under `apps/web-platform/app/api/legal-acceptance/[key]/` and `apps/web-platform/server/legal-acceptance/reauth.ts`. No migration, no SQL file and no change to the DSAR export allowlist is in this diff: the record itself (tables, retention, lawful basis, erasure position) was gated in PR-B (`knowledge-base/legal/audits/2026-11-04-gdpr-gate-work-exit-12011-pr-b.md`, activity PA-40, the legitimate-interest assessment and the notice note).

Scan completion: 3 path matches examined, 0 findings of severity Critical.

## Mandatory checks

| Check | Result |
|---|---|
| `GDPR-Art-6` lawful basis | Not triggered: no new schema column. The basis for the record stays Art. 6(1)(f) in PA-40 and the LIA. |
| `GDPR-Art-5e` retention | Not triggered: no new table. Retention of the record is unchanged and still awaits counsel (PA-40 item 17); the card-level notice carries the placeholder `[period to be confirmed by counsel]`. |
| `GDPR-Art-17` erasure | Not triggered: no new foreign key to `users`. The deletion and redaction path for a retained row is still not built and is tracked in #12080. |
| `GDPR-Art-17-caller` | Not triggered: no new `ON DELETE RESTRICT` key and no new anonymisation function. |
| `GDPR-Chapter-V` cross-border | Not triggered: no new vendor package and no new vendor credential. The email code goes through the existing auth service (Supabase, already listed as a processor) and its mail relay (Resend, already listed). Sentry receives event tags only. |
| `GDPR-Art-9` special category | Not triggered: no new column. The free-text note is not special-category by design, but a founder can type anything into it; see finding F-1. |

## Layer checks run against the diff

### `A-` auth and sessions: no findings

- The founder id and email come from the auth service's `getUser()` on the user-context client only. They are never read from the request body or from an unverified token.
- The web session id is read from the verified token exactly as the database reads it (`session_id`, else `ses_id`, empty meaning absent). A token whose audience is not `authenticated` is refused before any intent is issued.
- The code is checked on a throwaway client with no cookies and no persistence, and that session is discarded, so the founder's own session id does not change.
- Attempts are counted before the auth service is asked (5 per challenge in the database) and a per-user ceiling (10 per 15 minutes) sits in front of it; that ceiling is in-process, per host and resets on restart, so it is a soft brake and the database bounds are the hard limit.

### `AP-` API layer: no findings

- Both routes are cookie-session routes: origin check that fails closed on an absent Origin, JSON content type required, per-user rate limit, key validated against the registry pattern, unknown and malformed keys answer the same 404, the `approval-queue` flag read per user (corrected: the flag is read with `workspaceId: null` and is effectively global, see the review round addendum).
- The auth service answers 422 for an unknown address and 200 for a known one. The route returns the same body for both, so the route is not an account-enumeration oracle.

### `T-` data in transit and `DT-EU-CB`: no findings

- Personal data in transit is the founder's email address (to the auth service only, to send the code) and the decision fields (to the database through the user-context client). TLS applies on both legs (see the Encryption Posture block of the plan).

### `DL-` data lifecycle: no new findings

- The decision record is unchanged from PR-B. The challenge row (user id, session id, key, text hash) is purged after 30 days when the next challenge is requested, as before.

### `F-` frontend: no findings

- The card and dialog keep nothing in the browser: no local or session storage, no cookie, no persistence of the check across a reload (a reload returns to the start with nothing recorded).
- Both notices (the Request changes note and the card-level notice) are shown before the founder answers, word for word from the notice note. The copy is marked provisional under the legal sign-off gate and the card sits behind the `approval-queue` flag.

### `LC-` legal and consent: one open item

- The card-level notice contains the placeholder for the retention period, and the notice note says it is not approved for display until counsel decides the period. The control is that the card is dark behind the flag and the copy is `PROVISIONAL`. This is recorded as an enabling condition in the attestation record, not fixed here.

## Findings

### `F-1` free text may hold personal data

**Severity:** Suggestion
**Article:** Art. 5(1)(c) data minimisation
**Location:** the Request changes text box in `components/approvals/legal-acceptance-card.tsx` and the note column written by `record_legal_acceptance`
**Pattern matched:** a free-text field stored with the record
**Why this matters:** the note is kept even if the founder later deletes the account, so a founder who writes names or private details there creates data that is hard to remove.
**What to do:** nothing new in this PR. The 1000-character cap, the notice above the box (shown without scrolling) and the deletion and redaction path (#12080, counsel item 17) are the controls; the note never reaches the agent, which sees only the status.

### `F-2` Sentry events carry a pseudonymous user id

**Severity:** Suggestion
**Article:** Art. 32 and Art. 5(1)(f)
**Location:** `reportLegalOp` in `server/approval/ops.ts`
**Pattern matched:** a user id in an error-tracking event
**Why this matters:** the id is a pseudonymous identifier, the same practice as the existing approval events. The route code never passes the address, the code, the note or the text, and provider errors contribute a class only.
**What to do:** no action; tests in `test/legal-acceptance` assert that the address, the code and the note never appear in a reported event.

## Result

No Critical finding, no Important finding. Two Suggestions, both already covered by existing controls. Open conditions before the first real row are unchanged and are listed in the counsel review audit and the attestation record: counsel's decision on the retention period and on item 17, and the matching update of the three published privacy documents before any founder other than the operator is admitted.

## Review round addendum (2026-11-05)

Appended after the review round; the body above is unchanged. The cumulative diff was re-read against the same checks.

- The two legal pages now report a failed page read under the feature tag `legal-acceptance` (op `page_read_failed`, not paged) instead of the approval landing tag. Event content is unchanged: the user id as a pseudonymous tag, no address, code, note or text.
- F-1 (free-text note) stays a Suggestion. The note now also rejects NUL characters and lone surrogates at validation (the P3 note validation), which is input hygiene and does not change the F-1 reasoning.
- The `approval-queue` flag is read with `workspaceId: null`, which keys on role only, so it is effectively global, not per user. This corrects the `AP-` line above ("flag read per user"). Enabling the card means enabling the flag for every workspace; the ADR-319 amendment lists the enabling conditions.
- The per-user attempt ceiling is in-process, per host, and resets on restart; the database bounds are the hard limit. The send step takes the address from the session only, so there is no enumeration surface to test.

No new Critical finding and no new Important finding.
