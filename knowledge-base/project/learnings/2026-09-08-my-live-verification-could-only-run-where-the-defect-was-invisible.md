---
title: "My live verification could only be run in the state where the defect was invisible"
date: 2026-09-08
category: security-issues
module: apps/web-platform/supabase/migrations
tags: [verification, migrations, security-definer, grants, mutation-testing, vacuity]
issue: 1055
pr: 7916
---

# Learning: a live check and a static check cover different STATES, and the one you can run is not always the one that matters

## Problem

Migration 136 re-created `sum_user_mtd_cost` via `CREATE OR REPLACE` (to repin its
`search_path` to `public, pg_temp`) and shipped **zero REVOKE statements** for it.

I verified the grants against live dev and got exactly the expected shape:

```
sum_user_mtd_cost             {postgres=X/postgres,service_role=X/postgres}
sum_user_mtd_cost_by_workflow {postgres=X/postgres,service_role=X/postgres}
```

I also mutation-tested the tenant-JWT denial: granting `EXECUTE` to `authenticated`
reddened the isolation suite, revoking restored it. Both checks were real and both
passed. The defect shipped anyway, and was caught by two review agents.

## Root cause

`CREATE OR REPLACE FUNCTION` preserves the existing ACL **on replace** and
default-grants `EXECUTE` to `PUBLIC` **on first create**. Migration 027 states this
in its own header, verbatim:

> on FIRST create Postgres grants EXECUTE to PUBLIC by default. The REVOKE
> statements below MUST run on every apply — treating them as "cleanup" after the
> CREATE is a real security gap.

So the function is only unprotected on an apply where it does **not already exist**:
a `db reset` against a squashed baseline postdating 027, a fresh project bootstrapped
from `db diff`, or a `DROP FUNCTION` during incident recovery followed by
forward-only replay.

**A `proacl` read cannot be taken in that state.** Reading the live catalog requires
a database where 027 has already applied — which is precisely the state in which
`CREATE OR REPLACE` preserves the ACL and the missing REVOKE is invisible. The
verification was not weak; it was **structurally incapable** of observing the
defect, and it returned the exact string the acceptance criterion predicted.

## Key insight

**A live check and a static assertion cover different states of the system, and
"the state I can reach" is not the same as "the state that matters."**

The generalization: whenever verification requires the system to already be in some
state S, ask what the change does in `not S`. If the defect is only reachable from
`not S`, no amount of live checking will find it — the static assertion is the
load-bearing half, and a green live check is actively misleading because it looks
like the stronger evidence.

This is the inverse of the usual advice. The corpus repeatedly says prefer a live
probe over a static claim (a `terraform plan` over a citation, a `proacl` read over
migration text). That is right when both instruments can reach the same state. It is
wrong here, and the tell is that the live probe *needs a precondition the defect
excludes*.

## What made it worse

My own shape test looped **both** function names for `search_path` and **one** for
grants:

```ts
for (const fn of [NEW_FN, "sum_user_mtd_cost"]) { /* pg_temp */ }   // both
new RegExp(`REVOKE ... public.${NEW_FN} ...`)                        // one
```

The discipline was applied unevenly inside a single file, in the direction where the
second function was the newly-risky one. Fixed by making the grant assertion
`it.each([NEW_FN, "sum_user_mtd_cost"])`.

## Prevention

- **For any `CREATE OR REPLACE` of a function that already exists elsewhere in the
  corpus:** the REVOKE/GRANT block is not redundant with the original migration's.
  Ship it in every file that can create the function. Assert it per-function in the
  shape test, never for "the new one" only.
- **When a verification needs a precondition, write down what it cannot see.** One
  sentence in the evidence file: *"this check is only takeable in state S; in `not S`
  the behaviour is X, covered by <static assertion>."* If that sentence cannot be
  written, the coverage claim is incomplete.
- **When a test loops a set for one property, check whether every other property in
  that file loops the same set.** The uneven case is the defect.

## Related

- The same PR's `H1` finding: a member-count dispatch floor (`BUCKETS.length >= 8`)
  catches an empty LOOP and cannot see an emptied assertion BODY. Two axes; the plan
  asserted one mechanism covered both. Driven, it did not — 53 tests passed with the
  body deleted. Closed with `expect.assertions(n)`.
- `cq-pg-security-definer-search-path-pin-pg-temp` — the rule the repin satisfies.
- `knowledge-base/project/specs/archive/20260908-114856-feat-one-shot-1055-per-workflow-cost-observability/ac-evidence.md`
  — the AC record, including the addendum explaining this gap.

## Session Errors

- **`cmd | tail` masked a non-zero exit three times.** A `git commit … | tail -2` hid
  a markdown-lint rejection and the commit never landed while reporting success; a
  `git push -q … | tail -2; echo rc=$?` reported `tail`'s status on a *rejected*
  non-fast-forward push. **Recovery:** re-derived state with `git log` /
  `git cat-file -e` and re-ran. **Prevention:** already an `hr`-documented class —
  redirect to a file and read `$?`. The failure was applying it, not knowing it. A
  `PROMPT_COMMAND`-style habit does not exist here; the durable fix is never piping
  a command whose exit code is the result.

- **Leaked part of the dev DB pooler credential into the session transcript.** Piped
  `doppler secrets get DATABASE_URL_POOLER --plain` to `head -c 60` with a redacting
  `sed` *after* the truncation, so the `sed` never matched and a partial password was
  printed. **Recovery:** switched every subsequent call to `doppler run --`, so the
  value never materialises in output; flagged for rotation. **Prevention:** never
  pipe a secret to a truncating filter — the filter runs before the redactor. Prefer
  `doppler run -- <cmd>` over `doppler secrets get`; when a value must be inspected,
  test a property of it (`| wc -c`, `| grep -c '^postgresql://'`) rather than
  printing a prefix.

- **A mutation that never landed reported the BASELINE, which is indistinguishable
  from a pass.** `/tmp` was swept between turns, the helper script vanished, the
  `GRANT` never executed, and the tenant-denial suite re-measured the unmutated
  baseline — reporting `SURVIVED`, i.e. "this security test is vacuous." **Recovery:**
  noticed the `No such file or directory` in the same output, recreated the probe, and
  re-ran with a landing assertion. **Prevention:** assert the mutation landed *before*
  reading any verdict — here, read `proacl` back and require `authenticated=X` to be
  present, aborting otherwise. Treat baseline-identical as UN-RUN, never as evidence.

- **Two of my own verification instruments were broken, in opposite directions.** A
  link-checker using `tr -d '](./)'` stripped the dot from `.md` and reported three
  broken ADR links that were fine (false positive). A divergence probe used capturing
  groups, so `re.findall` returned the group (`'sh'`) instead of the full match,
  undercounting lost `file:line` citations **20×** (118 vs 2,367) — a false negative
  on the more consequential number. **Recovery:** re-ran both with corrected
  expressions before either propagated. **Prevention:** run every measuring instrument
  against a known-positive AND a known-negative before trusting its output. For
  `re.findall`, use non-capturing groups `(?:…)` whenever the whole match is wanted.

- **Measured a third-party tool with suppressing defaults and reported 0.00%.** A
  compression pilot returned "0/40 payloads modified" because the library defaults
  `compress_user_messages=False` and `protect_recent=4`, so a single-message fixture
  is protected by construction. **Recovery:** inspected the config object before
  believing the result; rebuilt the fixture as a realistic multi-turn conversation.
  **Prevention:** when a tool reports "no effect", read its effective configuration
  before reporting the number — a no-op default is far likelier than a no-op tool.

- **`content_sha` drift after editing an already-applied migration.** The review fix
  changed 136 *after* it had been applied to dev, leaving the tracked sha stale — the
  drift guard's exact target. **Recovery:** re-applied (the migration is idempotent)
  and reconciled `_schema_migrations.content_sha` in the **same transaction**.
  **Prevention:** any edit to a migration already applied to a shared environment must
  be followed by a re-apply + sha reconcile in one transaction, before the branch is
  considered green.

- **Relative `cd ..` drift silently dropped a commit.** `cd ..` from
  `apps/web-platform` left the shell in `apps/`, so `git add apps/web-platform`
  matched nothing and the commit did not land — while the following `git push`
  reported `0`. **Recovery:** re-ran from an absolute worktree path. **Prevention:**
  already documented; use absolute paths for any `git add`/`commit` in a multi-package
  worktree.

- **Asserted two guard properties instead of driving them.** I reported that the
  structural-UI QA gate did not fire, and accepted a review agent's "dispatch is
  sound" for the H1 scenario. Driven afterwards, the first held and **the second did
  not** — deleting an assertion body left the suite green at 53 passed. **Recovery:**
  drove both; added `expect.assertions(n)`. **Prevention:** this is the session's own
  headline lesson applied to process — a guard's property is established by running
  the mutation, never by an agent's summary of it or by reading the code. The plan's
  own `H1` row had *specified* the expected behaviour, and it was still wrong.
