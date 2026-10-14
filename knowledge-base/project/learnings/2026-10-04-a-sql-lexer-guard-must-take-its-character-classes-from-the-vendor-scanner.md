# Learning: a hand-written SQL lexer guard must take its character classes from the vendor scanner, not from the instance that prompted it

## Problem

`apps/web-platform/supabase/verify/154_inbox_item_idempotent_rearchive.sql` shipped (#9283) with
`LIKE "%status = 'archived' THEN RETURN%"`. In Postgres a double-quoted token is an identifier, so
the statement parses and fails only at bind time (`column "%status = ..." does not exist`). It went
unnoticed because `verify-migrations` is skipped on the `workflow_run` deploy arm (8 of 8 sampled
runs; mechanism unproven, tracked in #9471); the first `workflow_dispatch` run that executed it
failed on it (run 37186697713, "29 passed, 1 failed").

The fix was one line. The guard added with it (`verify-sql-string-literals.test.ts`, a small lexer
that blanks comments, `'..'` literals and dollar bodies, then rejects any remaining `"`) is where
the review time went: the 10-seat panel and then fix round 1 (5 seats + a verifier) found it
fail OPEN in five more ways, three of them High.

## Solution

Fixed in the guard (commits `a6bceecde4`, `b393a39ac0`, `ebde208779`, `222e9d9e51`):

- Nested block comments are depth-counted like Postgres, and the scan restarts at `i + 2` so
  `/*/` opens one comment. The first version sliced up to the first `*/`, which excludes the `*`
  shared with an inner `/*/`, so `/* /*/ -- */ */ SELECT ... LIKE "y"` hid a live `"y"` behind what
  the lexer read as a `--` comment.
- Any backslash in code position is a psql meta-command (`SELECT 1 \gexec`, `\!`). The first
  version only matched `^\s*\\[A-Za-z]`.
- Any non-ASCII code unit in code is flagged AND counts as an identifier character for the
  `$`-glue rule. The first version denylisted four curly quotes and used an ASCII-only identifier
  class, so a full-width quote or `e-acute$$` slipped through.
- `standard_conforming_strings` anywhere is reported (it changes what a backslash means in `'..'`).
- The directory walk and per-file scan are one shared pair of functions, exercised by the real
  corpus and by a seeded temp directory, so a dead walk goes red. The order-coupled aggregator
  test (shared mutable state across `it`s) was removed.

Mutation proof: `/var/tmp/vsl-mutbat3.py`, 20 rows, control green, 20/20 killed, restore verified
identical. Verifier seat: differential fuzz of 400k random strings against an independent
emulation of Postgres's `scan.l` comment/string rules found zero fail-open.

## Key Insight

The first-version guard took its detection rules from the one instance (a double quote) and the
spellings its author was thinking about (a `\i` on its own line, four curly quotes, a
`*/`-terminated comment). Each is a denylist of what the author imagined; the properties are
defined by the vendor's scanner: *every non-ASCII byte is an identifier character*, *every
unquoted backslash starts a psql meta-command*, *block comments nest and the opener consumes its
`*`*. When a diff adds a lexer-shaped guard, derive each character class from the vendor's own
scanner source or grammar, and ask of every denylist "what does the scanner treat the same way
that this list does not name?". A differential fuzz against an independent emulation of the
vendor's rules finds this class faster than reading.

Second, the guard's loop was the unpinned axis: a clean corpus makes `expect(found).toEqual([])`
green for a walk that reads nothing. Share the walk with a seeded fixture directory.

## Session Errors

1. **verify/154 merged with a double-quoted LIKE and nothing ran it.** Recovery: one-line fix plus
   the guard. Prevention: PR-time guard (this PR); the structural fix (run verify files against an
   ephemeral Postgres in PR CI, and make verify-migrations run on the normal arm) is tracked in
   #9471, including the two traps the architecture seat found (the `rls-authz-fuzz.yml` path filter
   omits `verify/**`; several verify files assert prod state and may fail on a fresh stack).
2. **The guard's first version failed open on five spellings** (line-start-only backslash check,
   `/*/` comment scan, ASCII-only identifier class, four-character quote denylist,
   `standard_conforming_strings`). Recovery: fix round 1. Prevention: take character classes from
   the vendor scanner; run a differential fuzz against an independent emulation before review.
3. **Mutation battery row M10 was an equivalent mutation** (`.` already excludes newline).
   Recovery: redone with `[\s\S]`. Prevention: before crediting a row, confirm the mutated regex
   actually changes behaviour on some input.
4. **A header comment overstated the code** ("stripSqlNoise drops newlines" is true only inside
   multi-line spans; "verify-migrations does not run on the normal arm" was imprecise). Recovery:
   corrected in fix round 1. Prevention: name the command that falsifies each causal sentence a
   diff adds (already in review/SKILL.md; applied late here).
5. **`cd ..` inside a compound command in a worktree moved the shell to `apps/`**, so `git add`
   with a repo-relative path failed. Recovery: re-ran with absolute paths. Prevention: already
   documented in review/SKILL.md ("never `cd ..` inside a compound command in a worktree").
6. **The Stop hook flagged forward-looking closing text twice** (a "next I will ..." sentence at a
   turn boundary). Recovery: acted in the same turn, then used the sanctioned
   `<stop>BLOCKED:</stop>` form while a background seat was still running. Prevention: state the
   wait as `<stop>BLOCKED:</stop>`, never as a promise.
7. **`gh issue create` was blocked by the filing hook** (earlier in the session). Recovery:
   re-ran with `--label meta/machinery`. Prevention: none needed beyond the hook's own message.

Triage: items 1 and 2 are recurring (disposition: fix-now-inline done; structural follow-up
already filed as #9471; latent sibling weaknesses below are appended to it rather than filed as a
new issue, per net-issue-flow). Items 3 to 7 are one-offs or already covered by an existing rule.

## Latent siblings (not fixed here, different subsystem)

Pattern seat, fix round 1: `test/migration-lint/definer-grants.ts` `stripSqlNoise` has no
fail-loud on unterminated regions, `E'..'`, `$`-glue or lone CR (feeds the DEFINER-grant lint);
54 migration tests strip comments with `sql.replace(/--[^\n]*/g, "")`, which a `--` inside a
literal truncates; `test/lib/terraform-hcl-blocks.ts:155` `break`s on unbalanced braces where its
neighbour throws.

## Tags

category: test-failures
module: apps/web-platform/supabase/verify
