# Learning: refusing to run is not blocking the release, and "identical output" needs an oracle

## Problem

PR #10446 added an I-cannot-spend gate to the live-verify harness: before the browser launches,
every `api_keys` row of the synthetic prod principal must equal the seed's decrypt-poisoned
sentinel and no un-revoked delegation may exist. The plan said "fail closed" and the first
implementation made every failure of the check `BLOCK=1` in the release workflow. Four review
seats independently found the conflation: the THROW before the launch delivers the safety
property, but a read error, a null body or an unseeded principal is "could not check", not
"holds spend authority". Marking it `BLOCK=1` reddened every trigger-path release on a
PostgREST blip, after the image was already live and with no rollback.

Two further defects came from my own fixes, each found only because a later, independent
seat read the fix rather than the feature:

- To close a quadratic email regex (100k characters with no `@` took ~23 s) I added a
  lookbehind and wrote "the redacted output is identical" in the comment and "same output" in
  the test title. It was not: after one match ends, a back-to-back address whose local part
  begins with a local-part character (`a@example.com+c@example.org`) can no longer start a match, so the
  second address stayed in a public Actions log. No test had two addresses in one string.
- The tests ran the emit step only up to a cut before the Sentry payload, and compared a
  hand-copied `redact(err.message)` instead of the conversion `main()`'s catch performs. The
  `reason` tag could be deleted, renamed or re-prefixed with the suite green.

## Solution

- Two tokens: `cannot-spend-violated` (a breach: `BLOCK=1`, `::error`) and
  `cannot-spend-unverified` (could not check: `BLOCK=0`, `::error`, a distinct Sentry `reason`
  tag). A violation outranks "could not check": both tables are read unless a violating key
  row is already certain, so an empty `api_keys` cannot mask a visible delegation. CTO-ruled.
- The email rule is a linear scan with the original regex's exact matching, and
  `redact.test.ts` keeps the ORIGINAL regex as the oracle in a 20k-string seeded differential
  fuzz plus the verifier's counterexamples, and asserts the 100k timing separately.
- `failureResult(err)` is exported and used by `main()`'s catch and the tests; the full emit
  body is executed behind an argv-strict `curl` shim and asserts `tags.reason`.

## Key Insight

1. **A guard that refuses to run and a gate that blocks the release are two different effects.**
   When a plan says "fail closed", write down which effect each failure class gets. The
   refusal is the safety property; the red run is an alarm, and an alarm on "could not check"
   is a false positive that teaches operators to ignore it (AP-021).
2. **"Same output" is a claim about every input, and the only oracle is the original.** A
   performance rewrite of a matcher keeps the old implementation in the test as the reference
   and fuzzes against it on inputs that put several matches next to each other. A single
   happy-path assertion and a 13-character random fuzz of short strings both stayed green over
   the counterexample.
3. **A test that stops before the wire pins the wire's two ends and neither.** When the
   artifact under test ends in an external call, run the whole body with a shim that accepts
   exactly the modelled argv; and when a function's result crosses a conversion, export the
   conversion and use it in the test instead of re-typing it.

## Session Errors

1. **Plan prescribed BLOCK=1 for every "cannot verify" outcome** — Recovery: CTO ruling, split
   token, ordering fix. **Prevention:** in a plan's Guard Contract, state per failure class
   whether it refuses the action, blocks the pipeline, or both.
2. **Claimed "output identical" for the email lookbehind with no differential oracle** —
   Recovery: linear scan plus fuzz against the original regex. **Prevention:** the `work`
   skill's Common Pitfalls now carries the oracle rule (routed bullet).
3. **Tests cut the emit step before the Sentry payload and re-typed `main()`'s conversion** —
   Recovery: `curl` shim, shared `failureResult`. **Prevention:** already covered by the
   `review` skill's "both endpoints pinned, the wire is not" class; no new rule.
4. **Wrote `--findings 62` into the review trailer subject without a tally** — Recovery:
   amended the unpushed commit to a measured statement and force-pushed with a lease.
   **Prevention:** an optional count flag is omitted rather than estimated.
5. **The fresh-eyes verifier seat returned nothing (no text, no file)** — Recovery: one
   `SendMessage` resume asking for the report. **Prevention:** already in the `review` skill
   (mandate file delivery in the spawn prompt, resume once); it worked.
6. **A `cd ..` in a compound command put the shell in `apps/`; a `grep -o` over a very long
   line hung for 120 s; `pkill -f` was blocked by the self-match hook; `git commit --amend`
   refused an empty commit; two TS cast errors; an over-broad PATCH assertion against the seed
   script** — Recovery: each fixed on the next call. **Prevention:** none beyond existing
   hooks; one-offs.
7. **A round-2 skill edit named `scripts/betterstack-query.sh` in backticks, which
   `plugins/soleur/test/components.test.ts` forbids in skills; my scoped suites never
   selected that repo-global ratchet** — Recovery: caught when compound re-ran it, replaced
   with a markdown link. **Prevention:** after any edit under `plugins/soleur/skills/`, run
   `components.test.ts` with the other touched-file suites; the affected gate at ship also
   selects it.
8. **A whole-directory vitest run was killed (143) at load average 17 from sibling worktrees**
   — Recovery: reran under `timeout -k` and got 10/10 files. **Prevention:** none; contention.

## Tags
category: workflow-issues
module: live-verify
