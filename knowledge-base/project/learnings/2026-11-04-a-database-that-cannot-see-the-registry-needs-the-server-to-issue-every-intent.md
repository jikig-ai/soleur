# Learning: a database that cannot see the text registry needs the server to issue an intent for every decision

## Problem

PR-B of #12011 (PR #12069) added a write-once record of a founder's decision on a legal text (migration 184). The first design
followed the plan: only a Yes needed a server-side step (an email-code challenge); Decline and Request changes were a plain
authenticated RPC call. Review (13 seats) converged on the hole from four directions: the legal texts are committed files, so the
database cannot tell a real `(key, text_hash)` pair from an invented one. Any signed-up user could call the RPC directly with
invented keys and leave undeletable rows (Request changes carries up to 1000 characters of free text), and a stolen session could
pre-empt the founder by declining the current, publicly computable hash, after which the unique key blocked their Yes forever.

The fix round then introduced its own defect: an idempotent "reuse the live intent" path ignored the freshness of the confirmed code,
so a founder whose code had gone stale reopened the card, got the same stale intent back and burned attempts until locked.

## Solution

- CTO ruling (option B): `issue_legal_reauth` (service role, the only party that knows the registry) is the only source of valid pairs;
  `record_legal_acceptance` needs a live intent for EVERY choice, consumed in the same transaction; a Yes also needs a code confirmed in
  the last five minutes. Intent lives 30 minutes, version is bound at issue, reopening a card reuses the intent for free, a resend
  inserts a new one (3 per 15 minutes).
- The trigger also requires a consumed intent matching user, key, text hash, version, session and event, so the write-door setting is not
  the only gate; triggers are `ENABLE ALWAYS`; verify fails closed (`invalid`) on a checksum mismatch.
- The reuse predicate now carries the consumer's freshness condition (`verified_at >= now() - 5 minutes`) and the version; `claim` reports
  `code_stale` and burns no attempt.
- Reads and writes both whitelist the web audience (`aud = 'authenticated'`) instead of blocklisting the runtime audience.

## Key Insight

When a table's valid keys are defined outside the database (a committed registry, a config file), the database cannot validate them, and
any caller allowed to write is a caller allowed to invent keys. Make the one party that knows the registry the only source of a
write capability (an intent row), and make the write consume it. Corollary for every idempotent "reuse" path: the reuse predicate must
include every freshness condition the downstream consumer checks, or reopening becomes a trap.

## Session Errors

1. **A real sign-in email was sent to the operator before checking whether the dev project could deliver a code.** The dev project has a link-only
   magic-link template (no `{{ .Token }}`), the default mailer, and 8-digit OTPs; the code never arrived. Recovery: proved the verify half with
   admin `generate_link` and recorded prod parity. **Prevention:** read the auth config through the Management API (`config/auth`: template contains
   `{{ .Token }}`, SMTP host, OTP length) before asking the operator to read an inbox.
2. **Told the operator no dev user existed for their address when one did.** The admin user listing was capped and unfiltered. Recovery: the send returned
   200 and `recovery_sent_at` moved. **Prevention:** look a user up with a filtered admin query or SQL on `auth.users`, never a paginated scan of an
   unordered listing.
3. **Dev helper scripts under the session scratchpad were lost when the session restarted.** Recovery: rewrote `/var/tmp/la184-dev.cjs`.
   **Prevention:** keep re-usable helper scripts for a long task under `/var/tmp` or in the worktree, not the scratchpad.
4. **`test-all.sh --print-selection` printed several kilobytes of suite names into the transcript.** Violates `hr-never-run-commands-with-unbounded-output`.
   **Prevention:** redirect to a file and print `AFFECTED_SUMMARY` plus a count.
5. **A new RLS-on, zero-policy table was not classified in `scripts/check-tom4-rls-posture.sh`, and the PA-40 row used the unscoped phrase "every table privilege".**
   Both made the repo-wide posture gate fail (3 of 22 assertions); only the pattern-recognition seat ran the script. **Prevention:** when a migration adds a
   table, run `check-tom4-rls-posture.sh` and add the table to `SHAPE_IV` or `NOT_CUSTOMER_DATA`; word legal prose with scoped nouns ("both tables", not "every table").
   (Routed to the SQL scaffold header.)
6. **The ADR ordinal was verified against `origin/main` only.** Open PR #12002 had already claimed ADR-318. **Prevention:** scan open PR heads
   (`gh pr view N --json files`) for `decisions/ADR-NNN` before picking an ordinal, and re-check right before merge.
7. **Mutation spot-check M3 did not land (wrong indentation in the anchor) and reported the baseline green.** **Prevention:** copy a pristine file first and
   `cmp -s` after the edit; treat a baseline-identical result as un-run.
8. **The fix round introduced a trap: the idempotent intent reuse ignored the stale confirmed code.** Found by the verification seat. **Prevention:** for
   every "return the existing one" path, list the consumer's acceptance conditions and put each in the reuse predicate; fixture the stale case.
9. **The initial design left Decline/Request changes unbound to a server step (followed the plan literally).** Reversed after review by a CTO ruling.
   **Prevention:** at plan time ask "what does the database know, and what can only the server know?" for every table whose keys come from outside it.
10. **`Write` refused twice after files were edited by scripts ("modified since read").** **Prevention:** `Read` (any range) before overwriting a file edited by a script.

## Tags
category: security-issues
module: apps/web-platform legal-acceptance (migration 184, ADR-319)
