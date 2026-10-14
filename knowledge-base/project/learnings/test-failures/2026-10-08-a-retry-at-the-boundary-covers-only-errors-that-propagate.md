---
title: A retry at the call boundary covers only the errors that PROPAGATE — a catch arm between the statement and the retry turns a transient into a verdict
date: 2026-10-08
category: test-failures
tags: [retry, postgresql, deadlock, 40P01, test-harness, flake, catch-arm, verdict-classification]
issue: '#9779'
pr: '#9793'
---

# Learning: a retry at the call boundary covers only errors that propagate

**Date:** 2026-10-08
**Session:** `feat-one-shot-9779-rls-fuzz-deadlock` (PR #9793, issue #9779)

## What happened

The fix for the rls-fuzz teardown deadlock (#9779: `40P01 deadlock_detected`
when one vitest worker's `drop trigger` raced a sibling's `SELECT` on a shared
disposable Postgres) added `withTransientRetry` around every bare `sql`-handle
unit of work — `rolledBackRaw`, the seed transactions, and every catalog/spec
call site. Both AC6 census greps went to zero; every propagating surface was
wrapped.

Two independent review seats (architecture-strategist,
pattern-recognition-specialist) then found the same residual path: **13+ catch
arms inside the retried `fn` bodies classify the caught error into a verdict
(`{kind: "test-error", sqlstate}`) before the error can reach the retry.** A
deadlock victim on a probe statement returned a `test-error` verdict → loud red
→ the identical flake signature the PR existed to eliminate, just relocated.
The retry boundary covered seeds, DDL, and catalog reads — everything whose
errors *propagate* — but not the probe statements, which are the most frequent
lock-waiters.

## The rule

When you add a retry (or any error-reactive wrapper) around a call boundary,
the wrapper sees only what is thrown to it. Enumerate every `catch` between the
statement and the wrapper and ask of each: *can the transient error reach the
retry from here?* A catch that converts an error into a return value is a
second boundary — the transient error dies there.

The fix shape that closes the class, not the site: a shared
`rethrowIfTransient(err)` called at the top of every *classifier* (the
chokepoint the catch arms funnel through), not N copies at N catch sites. In
this diff it lives in `verdict.ts › rethrowIfTransient()` beside
`TRANSIENT_SQLSTATES`; `classify{Write,Mutation,Rpc}Outcome` call it before
reading `err.code`. Any catch arm that stores the error for later (`caught = e`)
calls it explicitly first.

A related asymmetry, also caught in review: errors that reach a catch arm
*sitting outside* the retried unit (e.g., `driveDenied`'s outer catch) are
already post-exhaustion — classifying them as `test-error` vs. letting them
rethrow produces the same loud red either way. What matters is which side of
the retried boundary the catch arm sits on.

## Second-order lessons

- **A plan-time census is not a guard.** The plan pinned the wrap coverage with
  two `git grep` census commands verified at author time — and nothing stopped
  the next bare `await sql` from reintroducing the flake silently (every spec
  is `describe.skipIf(!RLS_FUZZ_LOCAL)`, so no local run would redden it). The
  review's P2 was closed by codifying the greps as `rls-fuzz-census.test.ts`
  (comment-stripped scan + seeded-offender self-tests + totality pin). If a
  plan asserts a census, write the census as a test in the same diff.

- **A guard's own prose can trip the guard.** The header comment documenting
  "an unwrapped `await sql` is an unretried deadlock victim" contained the
  literal `await sql` and tripped census A — and the mechanical
  `` `) `` → `` `); `` style sweep appended a semicolon inside a docblock.
  Comment-strip before scanning; reword prose that must discuss a pattern
  without matching it.

- **The exemption list is part of the property.** The first census-guard draft
  exempted `await sql\.(begin|end|savepoint)` — silently whitelisting the exact
  shape the guard exists to catch (a bare `await sql.begin` is an unretried
  multi-statement unit). Only `sql.end` (teardown, never a statement) was a
  legitimate exemption. When a guard exempts a token, ask whether the exemption
  is load-bearing or load-*bearing-away*.

## What worked

- The class-level fix (wrap at the `Sql`-handle boundary, never a `Txn` handle)
  held — every review finding was about residual surfaces, not the approach.
- Two seats converging on the same P2 from different lenses confirmed it was
  load-bearing before a single line was reverted or re-verified.
- Seeded-offender self-tests inside the census guard make its redness provable
  without mutating the tree.

## Session Errors

1. `timeout 900` wrapped a `test-all.sh --affected` invocation that was
   legitimately queued on the repo-global lock (position 3, ~11 min of
   heartbeats) and killed it mid-queue. **Prevention:** when a runner's own
   heartbeat protocol already bounds the wait (7200s ticket queue), don't wrap
   a second shorter timeout around it — poll the log instead, or run
   `nohup … &` and check later.
2. `fix-round-seats.sh --finding-seats` rejected a multi-argument list; the
   flag takes one quoted string. **Prevention:** read `--help`/usage for flags
   that take "a list" — the singular token is a hint.
3. New `harness-fixture.ts` header comment containing the literal `await sql`
   tripped the AC6 census grep. **Prevention:** before committing prose that
   discusses a code pattern, grep the prose for the pattern's own regex.
4. A `` `) `` → `` `); `` replacement sweep appended a `;` inside a docblock
   (`catalog.ts` COALESCE prose). **Prevention:** mechanical punctuation sweeps
   over mixed code+comment files need a comment-stripped check or per-line
   review; the review seat caught it because it re-read the hunk.
5. The first `rls-fuzz-census.test.ts` draft exempted `await sql.begin` —
   whitelisting the highest-exposure unretried shape. **Prevention:** seeded-
   offender self-tests that include the exemption's own edge cases
   (`await sql.begin` MUST be an offender) — now in the guard.
6. A `cd ..` between chained commands landed in `test/` instead of
   `apps/web-platform`, so a vitest run and a plan-file edit silently skipped
   while the commit proceeded. **Prevention:** use absolute paths per command;
   when a command produces no output, check `pwd` before assuming it ran.
7. `git config core.hooksPath` resolved to `/dev/null` on this clone — the
   lefthook battery silently never ran at commit time. **Prevention:** check
   `core.hooksPath` (or hook output presence) after the first commit on a
   fresh clone; the owed linters (markdown-lint, gitleaks, tsc, affected gate)
   must be run explicitly when hooks are disabled.

## Prevention

- `verdict.ts › rethrowIfTransient()` + the classifier-level calls now close
  the verdict-swallow path permanently for this suite.
- `rls-fuzz-census.test.ts` turns the wrap census into a deterministic local
  red — including the `await sql.begin`/`return sql.begin` unretried-unit
  shapes.
- For future retry-boundary work in other suites: first enumerate the catch
  arms inside the retried unit; only then count the call sites.
