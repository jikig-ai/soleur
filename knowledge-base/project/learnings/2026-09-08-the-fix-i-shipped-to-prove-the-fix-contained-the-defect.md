# The code I added to prove the fix worked contained the defect the fix removed

**Date:** 2026-09-08 · **Issue:** #7829 · **PR:** #7914

## Problem

`check_and_record_byok_delegation_use` refused a delegated BYOK turn on five
branches. The issue was filed against the two cap branches, which SELECT the
spend window and then `RAISE` without inserting — while the three sibling
branches visibly `INSERT INTO audit_byok_use` before raising and therefore
looked correct.

They were not correct, and the difference matters more than the count.

## Key Insight 1 — an unhandled RAISE discards the INSERT made in its own transaction

An unhandled plpgsql `RAISE EXCEPTION` aborts the transaction, and the `INSERT`
executed earlier in that same transaction is rolled back with it. The function
declared no `EXCEPTION` handler (verified against the live catalogue: `RETURNS
void`, zero `WHEN` clauses). So **no** refusal branch had ever persisted a row.

The defect was five branches, not two — and the obvious repair, "add the two
missing INSERTs", would have shipped green while still writing nothing. The
three branches that looked right were the evidence that the diagnosis was
wrong: if inserting-then-raising worked, they would have left rows, and
production had **zero** delegated audit rows.

**Generalisable:** when an issue names a subset of a set and the rest of the set
"looks fine", check whether the mechanism that makes the subset broken also
applies to the rest. A sibling that looks correct under a wrong model is
evidence about the model, not about the sibling.

## Key Insight 2 — a fix's verification inherits the defect's framing

The single worst finding of the review was in code added to PROVE the fix
worked:

```ts
tags: { ledger_row_written: await ledgerRowWrittenTag(invocationId) },
```

The `await` evaluates BEFORE `reportSilentFallback` runs, so the mandatory
signal (a cap breach) was sequenced behind an optional diagnostic (did the row
land) issuing an untimed database round-trip. The failure modes are
**correlated**: a database that just failed to write the ledger row is exactly
the one that will not answer the read-back. On a degraded database the breach
was never reported at all.

That is the silent failure this whole PR existed to remove, relocated from the
migration into the reporting path, by the instrument built to observe it.

**Generalisable:** on a fix PR, review the new ASSERTIONS and new INSTRUMENTS
before the new code. They are written while holding the defect in mind and they
reliably pin the shape of that defect rather than the property. Ask of every
diagnostic: *if this diagnostic fails, does the thing it annotates still get
reported?*

## Key Insight 3 — a mutation battery measures the axes you mutate, and no others

I reported "6 mutations across 6 axes, all RED". Every axis was a variant of
*is this string present*. A review agent built its own harness and found twelve
survivors:

- deleting every `RETURN` from all five branches — which makes execution fall
  through to the pass branch, so a revoked or consent-withdrawn delegation is
  **admitted**. My test was NAMED "every INSERT is followed by a RETURN" and its
  entire body was `expect(inserts.length).toBe(6)`.
- deleting the `FOR UPDATE` row lock and leaving a block comment mentioning it —
  my harness stripped `--` only, while its header claimed a bare token a comment
  could also carry could not satisfy it.
- excluding refusal rows via `founder_id = grantor` instead of naming
  `attribution_shift_reason` — same semantic defect, different column.
- a sixth refusal branch that RAISEs, reintroducing the defect class.
- replacing the whole down migration with a no-op body.

**Generalisable:** count AXES, not rows, and state which axes the battery did
NOT edit. A test whose DESCRIPTION names a property while its ASSERTION is a
bare count pins neither.

## Key Insight 4 — a sweep indexed by literals misses the claim

Renumbering 136 to 137, I anchored on the two spellings I thought of and left
**38** references behind, in forms I had not enumerated (`by 136`, uppercase,
hyphenated, `pre-`/`post-` prefixed, and the `.down.sql` filename). One sat
INSIDE the function body, which Postgres stores in `prosrc` and returns to
anyone reading the live definition. Another left an Article 30 register cell
citing two different migration numbers for one change.

The residual count over the NEW spelling reported clean throughout.

**Generalisable:** index a sweep by the CLAIM ("this work is migration 136"),
not by the phrasings you remember. A bare-token regex minus the legitimate
homographs finds what an enumeration cannot.

## Key Insight 5 — the collision window includes the shared dev database

The pre-apply migration-number check consulted `origin/main`, where 136 was
free. A sibling branch owned 136 and had **already applied it to dev**. The
authoritative set is the union of `origin/main`, every worktree's migrations
directory, and dev's `_schema_migrations` — the last of which is the one a
`git`-only check structurally cannot see.

## What else the panel caught

- The **084 rollback chain was dead**: its down migration opens with
  `CREATE OR REPLACE ... RETURNS void`, and a return type cannot be changed that
  way — SQLSTATE `42P13`, verified live — so while 137 is applied it aborts on
  its first statement and every later step is skipped.
- A hand-written **mirror of the reply classifier** in the live suite had
  drifted fail-OPEN under a docstring saying "keep the two in sync", and it is
  the only artifact that observes the real PostgREST wire shape.
- The PR shipped user-facing copy reading **"Your $X daily cap is still
  enforced"** while the same commit's Terraform comment documented that the cap
  enforces nothing. One PR, two artifacts, and the user-facing one was false, on
  a billing surface.
- A **known-wrong expression scoped out to another issue** would not have been
  fixed by that issue: its scope covered migrations 061/121, not this
  migration's own third copy of the expression. Not-propagating is not the same
  as fixing, and "land the other issue first" was a dominated option.

## Session Errors

- **Collision check consulted `origin/main` only.** A sibling had already
  applied 136 to the shared dev database. — Recovery: renumbered to 137 and
  re-swept. — **Prevention:** query dev's `_schema_migrations` in the pre-apply
  check; routed to `work/SKILL.md`.
- **Renumber sweep anchored on remembered literals**, leaving 38 references
  including one in `prosrc` and a self-contradicting statutory register cell. —
  Recovery: re-swept indexed by claim. — **Prevention:** covered by the
  index-by-claim rule; reinforced here with the `prosrc` consequence.
- **Mutation battery measured one axis while claiming six.** — Recovery: the
  review's own harness found 12 survivors; all now RED. — **Prevention:**
  enumerate axes explicitly and state the ones not edited.
- **Gated the mandatory report behind its own optional diagnostic.** — Recovery:
  emit first, annotate second, bounded read-back. — **Prevention:** the
  diagnostic question in Key Insight 2.
- **Shipped a false user-facing safety claim** contradicting the same commit. —
  Recovery: corrected to "still applies". — **Prevention:** when a PR documents
  that a control does not do X, grep the diff for user-facing copy asserting X.
- **A tripwire header asserted comment-proof anchoring** that was false for
  block comments. — Recovery: strip both comment forms at extraction. —
  **Prevention:** a claim about a harness is a claim to mutate, not to write.
- **A fan-out agent was instructed to commit while the lead was committing** in
  the same worktree. Two lefthook runs deadlocked on one `index.lock` for ~20
  minutes, and killing the wrapper left three orphaned full-suite runs consuming
  the machine. — Recovery: stopped the agent, reaped the trees after verifying
  ownership via each process's working directory, committed as sole writer. —
  **Prevention:** fan-out agents in a shared worktree are write-only; the lead
  commits. Routed to `one-shot/SKILL.md`.
- **Leaked part of a dev database password into the transcript.** A redaction
  filter could not match a string that a byte-count truncation had already cut
  before the `@` delimiter it anchored on. — Recovery: stopped echoing the
  value, passed it only via the environment. — **Prevention:** never pipe a
  credential-bearing string through a truncating filter before redacting;
  redact at the source or do not print.
  **Operator action: rotate `DATABASE_URL_POOLER` for `soleur/dev`.**
- **A mutation that did not reproduce its attack reported GREEN**, which proves
  nothing. — Recovery: caught by the battery's own landing assertion; redone as
  the real attack. — **Prevention:** assert the mutation reproduces the attack,
  not merely that bytes changed.
- **The `084.down.sql` repair fell through the gap between three parallel
  workstreams** — each brief excluded it as another's territory. — Recovery: the
  migration-safety agent found it. — **Prevention:** when fanning out by file
  ownership, diff the union of the briefs against the plan's file table.
- **The plan cited a probe script that never existed.** — Recovery: repointed at
  the verify sentinel, which the release pipeline already runs. — Prevention:
  covered by the waiver-abuse rule.
- Wrong agent namespace (`spec-flow-analyzer` is under `soleur:product:`, not
  `soleur:engineering:review:`), a `markdown-lint` MD038 rejection, a Python
  quoting slip, and a process-matching guardrail denial — all one-off,
  self-corrected, no recurrence vector.

## Tags

category: database-issues
module: byok-delegations
