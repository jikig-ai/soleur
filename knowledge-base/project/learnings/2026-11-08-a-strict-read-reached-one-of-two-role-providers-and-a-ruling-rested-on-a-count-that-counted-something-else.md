# Learning: a strict role read reached one of two providers, and a ruling rested on a count that counted something else

## Problem

PR #12336 (Ref #9601, ADR-309 flip item 1) shows the Owner who approves an action who asked for it, and withholds the
action text from members who are neither an Owner nor the requester. Two rounds of review found defects that were not in
the feature but in how the fixes were applied and in what a ruling was built on.

1. **A fix applied to the instance, not the class.** The first round made the reattach path throw on a non-boolean
   `is_workspace_owner` result, so a malformed answer no longer turned into "member" silently. The first-send provider
   in `gate.ts` computes the same role with the same `data === true ? "owner" : "member"` expression and stayed silent.
   Four seats named it in the second round; the first round's fix agent had been told about the pattern and still left
   it.
2. **A ruling that rested on an unmeasured claim.** The earlier CTO ruling suppressed the requester label when
   `request_count >= 2`, to avoid naming one member on a card another member re-asked. `request_count` counts rows of
   every status for the same conversation and action hash, and `requested_by_user_id` is immutable per row, so the count
   cannot show a re-ask by someone else. It only removed the label after a denied or expired earlier row, which is when
   an Owner most needs to know who is asking. Reading migration 180 refuted the premise in a few lines.
3. **A test instrument with the defect it replaced.** The hand-written lexer behind the render-sink census was rebuilt on
   the TypeScript parser, but `stripComments` (six other consumers) was only moved to the parser's trivia API and kept a
   fail-open: a one-line `/** @type {string} // note */` made the trivia scan read `// note */ code();` as a line
   comment and blank real code.

## Solution

- Role read: the same null-tenant, error and non-boolean throws now sit in both providers, each caught by its caller and
  reported through the existing `viewerRoleFailed` op, with mutation row G1-GD7's anchor line left in place.
- Suppression: dropped on reattach and on the Owner landing page by a CTO ruling made after reading migration 180; the
  landing page now reads the label and the count in parallel. The ADR limitation was rewritten to say what the count
  measures.
- `stripComments`: do not descend into JSDoc nodes (the comment is already found as the next token's leading trivia);
  a RED then GREEN control was added.
- Verification: one fresh-eyes verification seat after the second round returned no P1 or P2.

## Key Insight

When a review fix hardens one reader of a value, the unit of work is the value's readers, not the reader the finding
named: list every code path that computes the same fact (here, the viewer's role) before calling the fix done. And a
ruling is only as good as the weakest sentence it quotes about a column or a function: the count's definition was one
`sed -n` away. The comment-handling lexer replacement and its sibling are the same lesson one level down: move every
consumer of the old behaviour, then fuzz the new one with the input class that broke the old one.

## Session Errors

1. **Eslint ratchet moved** (`no-control-regex` 20 > 19) from a new control-character regex. Recovery: `/[\s\p{Cc}]/u`, baseline untouched. **Prevention:** run `test/eslint-config.test.ts` after any regex literal that names control characters.
2. **Gate-side label lookup outlived its approval** (one labeler per deps object). Recovery: CTO ruling deleted the first-send lookup. **Prevention:** a memo or trip must have the lifetime of the unit it protects; read where the object is constructed before adding state to it.
3. **Hand-rolled lexer desync** on a JSX apostrophe and a quoted regex. Recovery: AST census. **Prevention:** fuzz any source scanner with a JSX apostrophe, a regex containing a quote, a regex containing `//` and a one-line JSDoc containing `//`.
4. **Strict read applied to one of two providers.** Recovery: both throw. **Prevention:** after any "make X strict" fix, `git grep` the expression that computes X across the app and fix every hit in the same commit.
5. **A ruling quoted what a column counts without reading it.** Recovery: CTO re-ruled after reading migration 180. **Prevention:** put the definition of any count a ruling depends on (the migration line) in the ruling request.
6. **`pipeline-tally.sh incr` run from the bare repo root** after a `cd` there (cwd drift) added one count to the `main` ledger; the script has no decrement. Recovery: re-ran `incr` from the worktree so the branch ledger is right; the stray count stays. **Prevention:** begin every Bash call with `cd <worktree>`, never `cd` to a plugin path from the bare root, and read `git branch --show-current` before any tally write.
7. **A mangled test title from my own Edit** (a stray word inside an unrelated test name), caught on the next read. **Prevention:** after an Edit that adds a neighbouring block, re-read the first lines of the old block.
8. **Disk quota (EDQUOT -122)** during the Playwright browser install; `/home` at 96%. Recovery: nav-states gate recorded as INFRA-BLOCKED, CI e2e is authoritative; told the user. **Prevention:** `df -h /home` before a multi-hundred-MB install.
9. **First-panel seat reports were not on disk**, so the test-design seat could not map its own survivor ids. **Prevention:** write each panel seat's report to `/var/tmp/review-<pr>-<seat>.md` when it returns (already a rule in the review reference).
10. **A fix agent could not touch the Guard-1 script**, so a test title had to keep a row's kill substring. Recovery: kept the substring. **Prevention:** grep `approval-guard1-mutation.test.sh` for a test title before renaming it.

## Tags

category: logic-errors
module: apps/web-platform/server/approval
