# Learning: a two-pass regex comment stripper in a text-lint test is itself the bypass

## Problem

PR #11238 (egress audit window selector, migration 183) pins a SQL migration with offline text tests: body parity with
migration 177, statement order, a closed list of top-level statements, a reader-set check and a denial-prefix check.
Every one of them read the file through `stripComments`, first written as two regex passes (`/* */` then `--`).

Review round 1 fixed several blind spots in those guards, and the fix commit itself replaced the stripper with a
"stricter" two-pass version. Fix-round seats then found the replacement opened two new holes:

- `/*` inside two string literals made the first pass swallow live SQL between them.
- `-- /*` made a line comment open a block comment.
- A trailing `.replace(/ {2,}/g, " ")` ran after the literal-preserving join, so the comment claiming literals are
  kept "byte-for-byte" was false (`'a  b'` equalled `'a b'`).
- Splitting statements on `;` plus newline missed a same-line `GRANT ...; DELETE ...`.
- `\b` after the last word of one element never matches against `textContent`, which glues neighbouring elements
  together, so the "past month" ban in the render sweep was dead for text in adjacent elements.

## Solution

One left-to-right lexer, `apps/web-platform/test/helpers/sql-lex.ts`: it knows at every character whether it is in a
literal, a quoted identifier, a line comment or a nested block comment. `stripSqlComments`, `collapseSql` and
`splitSqlStatements` are built on it, and the three consumers (183 shape test, denial-prefix test, helpers test) import it.
Verify rows are matched head to tail, the reader-set check matches any grantee list and `ON ALL FUNCTIONS`, and the
render sweep scans whitespace-joined text plus every visible attribute. Five mutants (same-line DELETE, same-line DO,
a literal-hidden grant, a `-- /*` hidden grant, a spaced literal) were run against the committed tree and all went red.

## Key Insight

Two regex passes cannot see nesting, so any text-lint that strips comments with them reads a different file than the
database does. The durable unit is a shared lexer that every test imports, not a better regex per test. Measured here
the class already exists in about twenty sibling migration tests that strip `--` with a regex; they were left alone (other
subsystem, no live exploit, net issue flow 0) and are recorded as carry-forward, not filed.

Second insight: a fix commit is the least-audited surface in the diff. The stripper was "fixed" in the very commit that
reported closing the class, and only a report-only fix-round panel caught it. Run the mutants against the committed tree
before claiming a class is closed.

## Session Errors

1. **technical-ruling-gate failed on a free-text `Class` cell** — Recovery: used the closed-list category `operator (legal-risk)`. Prevention: read the gate's closed list before writing a decision-challenges row.
2. **First `--affected` run ended rc 6 (budget-deferred) plus a real `lint-window-closure-assertion` failure** — Recovery: added `// window-assembly:` declarations, re-ran green. Prevention: when a diff adds a window/parse test, run `python3 scripts/lint-window-closure-assertion.py --allowlist ...` before the first gate.
3. **A plan-edit script aborted on a count mismatch (2 vs 3)** — Recovery: re-ran with all three strings; the tree was untouched. Prevention: scripts that assert counts before editing are the right shape; keep them.
4. **"must-pass reflow" test failed after `collapse` became literal-aware** — Recovery: reflow only outside literals. Prevention: change a chokepoint and its must-pass row in the same edit.
5. **Closed issue #11929 in the args would trip one-shot's closed-issue abort** — Recovery: scrubbed it from child args, kept it for the postmerge report. Prevention: none needed beyond that scrub.
6. **Stop hook flagged an unkept promise** — Recovery: ended the turn with an explicit `Paused:` sentence. Prevention: do not end a turn on a promise to wait.
7. **My round-1 comment-stripper fix opened new bypasses (above)** — Recovery: shared lexer plus mutants run against the committed tree. Prevention: grade a fix commit as its own change; mutate the committed tree before saying the class is closed.
8. **My new `last|past ... 30` regex tripped legitimate 30-day copy, and the first reader-set rewrite caught migration 174's table grants** — Recovery: dropped the digit alternative; restricted the grant pattern to `GRANT EXECUTE`. Prevention: run a new guard against the unmutated tree before mutating it.
9. **`rm -rf` of a scratch dir under `/tmp` was blocked by the protected-path hook** — Recovery: `rm -f` the file then `rmdir`. Prevention: use the skill's `rm -f` + `rmdir` form for scratch dirs.
10. **Local Playwright chromium download timed out; the nav-states gate failed at launch for all 35 tests** — Recovery: recorded as INFRA-BLOCKED, CI's containerized e2e job is authoritative. Prevention: none; host limitation.
11. **A `cd ..` in a compound command moved the cwd and made relative greps miss** — Recovery: re-ran from the worktree root. Prevention: use absolute or root-relative paths in multi-file greps.

## Tags

category: test-failures
module: apps/web-platform/test/helpers/sql-lex
