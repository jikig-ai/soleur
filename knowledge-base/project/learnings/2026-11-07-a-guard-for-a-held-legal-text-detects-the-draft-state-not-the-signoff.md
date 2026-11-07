# Learning: a merge guard for a held legal text detects the draft state, not the sign-off

## Problem

PR #12342 adds the first legal-acceptance text (`founder-acceptance-record`) as a DRAFT held for counsel.
Merging deploys it to production, where it becomes acceptable, so the hold had to be mechanical as well as
procedural. The first guard was a CI-only test that failed on a bracketed placeholder in the text body. Review
and a verification seat found it was narrower than its name in four ways.

## Solution

- The guard is a detector of the draft state (any placeholder-shaped token) over EVERY surface that states the
  open fact: the text body, `LEGAL_COPY.cardNotice` and `LEGAL_COPY.requestChangesNotice`. One `heldFindings()`
  feeds the CI-only test, and a non-CI control proves it finds the open items in the real data.
- The guard is documented as not proof of sign-off: an admin or UI merge bypasses it, and a numeric period
  written by anyone passes it. The PR stays DRAFT; the hold is the PR state plus the operator, the test is a net.
- A registry tripwire fails when a second text is committed, so the guard cannot silently stop covering a new key.
- Every extractor over migrations reads SQL through the lexer in `test/helpers/sql-lex.ts` (nested block
  comments, string literals blanked), not a two-pass regex, and scans every migration, not one.
- Pins for a table's stored fields parse a balanced column body, pin both tables and fail on any later column
  ALTER; they are not a type-list regex.

## Key Insight

A user-facing statement of fact lives on several surfaces (the text, the card notice, the request-changes
notice). A guard or a test that covers one surface is a guard about a string, not about the fact. Grep the
fact's SUBJECT across the layers before writing the guard. And a fix commit is the least-audited code in the
diff: here the fixes repeated the class they fixed (narrow type list, one-migration scan, SQL not lexed) and
were caught only by a fresh-eyes seat on the fix range.

## Session Errors

1. **Told the user to make the first acceptance in the app when no legal text was committed** - Recovery:
   found no text under `texts/`, drafted one as a held draft PR - Prevention: before telling an operator how to
   use a feature, read the registry/data it needs (`hr-verify-repo-capability-claim-before-assert` already covers it).
2. **The draft's ack-marker sentence said the marker means the decision was "finished recording"** - Recovery:
   a review seat read the writer (marker is written after the Sentry flush and can be missing); sentence corrected
   in `cb4be7e07c` - Prevention: for each factual sentence in a user-facing text, open the code that writes the
   thing it describes before drafting.
3. **The merge guard missed the card notice carrying the same retention placeholder** - Recovery: widened to all
   surfaces - Prevention: grep the fact's subject across layers before scoping a guard.
4. **Fix commits repeated the defect class (narrow column-type regex, one-migration scan, comment-only stripping)** -
   Recovery: fix round 2 after a verification seat on the fix range - Prevention: run the targeted fix-round
   review on every fix batch and grade it as its own change.
5. **`technical-ruling-gate.sh` rejected invented class names in `decision-challenges.md`** - Recovery: used
   `operator (production-mutating)` and `taste` - Prevention: read the gate's accepted classes first (one-off).
6. **Stop-hook blocks on closing turns that named a future action** - Recovery: ended with a `Paused:` sentence -
   Prevention: none needed (one-off).

## Tags

category: logic-errors
module: web-platform/legal-acceptance
