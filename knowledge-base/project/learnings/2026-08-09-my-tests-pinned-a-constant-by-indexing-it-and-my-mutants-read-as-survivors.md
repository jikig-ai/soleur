---
date: 2026-08-09
issue: "#7332"
pr: 7336
category: test-failures
tags: [tests, mutation-testing, self-referential-assertions, verification, gates]
---

# My tests pinned a constant by indexing it, and my mutants read as survivors

Two verification failures from #7332's review. They look unrelated and are the same
mistake: **the instrument took its reading from the thing under test.**

## 1. A test that indexes the constant it pins cannot see a wrong value

`EXPECTED_KB_PATHS` listed `overview/constitution.md`. `sync.md`'s Definition Sync reads
and writes `project/constitution.md` — where the file actually lives. Soleur's own
knowledge base would have reported a permanent *"no constitution present"* line against a
file one directory away, **in every customer repo, committed**.

Nothing caught it, and the reason is structural, from the review commit:

> Nothing caught it because every test indexed the constant it was pinning (`[0]`, `[1]`,
> `.length`), which is self-referential: it verifies internal consistency and cannot see a
> wrong value.

`expect(EXPECTED_KB_PATHS[0]).toBe(EXPECTED_KB_PATHS[0])` is the limit case, and
`.length`-based assertions are the same thing wearing arithmetic. Such a test survives
**any** edit to the value; it only fails if the array's *shape* changes.

**The fix is an external referent.** A parity test that extracts the documented path from
`sync.md` and asserts the list contains it — plus sorted-ness and no-duplicates. The
assertion now fails when the constant is wrong, which is the only interesting case.

Auditing the other eight entries afterwards found them legitimate (`product/prd` is
written by the `code-to-prd` skill and is simply absent here). One wrong entry out of
nine, invisible to a full green suite.

## 2. A mutation battery is only as trustworthy as the harness running it

Two separate corruptions of the mutation signal in the same PR:

**The suite aborted before it could report.** From the review commit that added a
call-site guard:

> Writing that guard reproduced the `x=$(cmd)` set -e trap for the third time this
> session — grep exits 1 on no matches, so the suite aborted before printing FAIL and
> **the mutation read as surviving**.

The mutant was killed. The harness died first, printed nothing, and the absence of a FAIL
line was scored as survival. A mutation result is a claim about a *test run*, and a run
that aborts produces no evidence in either direction — but "no FAIL printed" looks exactly
like "passed" to anyone reading output rather than exit codes.

**Redundant fixes disguise live mutants.** The write-row defect was closed on two
independent levels (clear `insec` at the next `^##` heading, *and* a post-write check that
the row landed inside `Auto-inferred`). Either alone catches it:

> that redundancy is why my first mutation runs looked like survivors until I isolated
> them.

Mutating one level leaves the other standing, so the suite stays green and the mutant is
scored as surviving — when in fact the *defect* is covered twice over. Redundant defences
require **isolated** mutation, one level disabled at a time, or the score is noise.

## Key insight

A green verification is a claim about the **instrument**, not only about the code. Before
believing one, ask what it reads from:

- **A test that reads its expected value from the code under test** verifies internal
  consistency and nothing else. Pin against an **independent referent** — the doc, the
  sibling implementation, the external contract.
- **A mutation score is evidence about the mutations you chose and the harness that ran
  them.** If the harness can die silently, or the defence is layered, the score measures
  the harness rather than the suite.

Both failures share one tell: **nothing outside the system was consulted.** That is the
question to ask of any gate — *what does this compare against, and could that thing be
wrong in the same direction?*

## Related

- [[2026-08-09-the-shell-capture-trap-recurred-three-times-and-finally-earned-a-lint]] —
  the trap that corrupted the mutation reading
- [[2026-08-06-my-gate-would-have-fired-on-every-input-and-no-unit-test-could-see-it]] —
  same PR: a gate whose parse used the wrong key, so it fired on every corpus
- [[2026-08-01-my-mutation-battery-inferred-the-verdict-from-the-input-under-test]]
