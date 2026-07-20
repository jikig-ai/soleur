---
title: "verify/*.sql content tests must pin CASE polarity + bind check_name, not just probe existence"
date: 2026-07-11
category: test-failures
module: apps/web-platform/test/supabase-migrations
tags: [supabase, verify-sentinel, migration-content-test, vacuous-green, has_function_privilege, grant-hygiene]
issue: 6306
pr: 6318
---

# verify/*.sql content tests must pin CASE polarity, not just probe existence

## Problem

A migration-content test (`readFileSync` the `verify/NNN_*.sql` sentinel + regex-assert,
036-style) for a grant-revoke migration (#6306, migration 128) asserted only that each
`has_function_privilege('<role>', '<sig>', 'EXECUTE')` **probe exists** in the verify file.
It did NOT assert the surrounding `CASE WHEN … THEN 1 ELSE 0` (deny) vs `THEN 0 ELSE 1`
(present) polarity that carries the actual semantics.

`test-design-reviewer` flagged the vacuous-green mutation: inverting a deny check to
`THEN 0 ELSE 1` (which makes the sentinel assert that `anon` *should* have EXECUTE — a
self-defeating guard) leaves the probe substring unchanged, so every content-test assertion
still passes. The suite claimed to guard "the deny state" but guarded only probe presence.
The verify sentinel is the load-bearing runtime guard (`run-verify.sh` at deploy time); a
silently-inverted sentinel would ship green and never catch a real grant re-opening.

## Solution

Bind three things in ONE regex per check — the `check_name` literal → the probe → the CASE
polarity:

```js
// deny check MUST be THEN 1 ELSE 0 (bad=1 when the role still has EXECUTE)
const re = new RegExp(
  `'${fn}_${role}_revoked'[^\\n]*,\\s*CASE\\s+WHEN\\s+has_function_privilege\\(` +
  `\\s*'${role}'\\s*,\\s*'${sig}'\\s*,\\s*'EXECUTE'\\s*\\)\\s+THEN\\s+1\\s+ELSE\\s+0`,
  "i",
);
// service_role-present check MUST be THEN 0 ELSE 1 (bad=1 when service_role LACKS EXECUTE)
```

Binding the `check_name` literal also catches a mislabeled row (a check_name typo that would
otherwise pass because the probe alone matched).

**Prove non-vacuity by mutation:** flip one deny check's polarity in the verify file
(`THEN 1 ELSE 0` → `THEN 0 ELSE 1`), run the suite (must go RED on exactly that check), then
restore and confirm GREEN + a clean `git diff --stat` on the verify file. Do the restore with
a targeted inverse edit, not `git checkout --` (the file may carry sibling uncommitted edits).

## Key Insight

This is the SQL-sentinel instance of a known defect class: **a source-grep test that asserts
the dangerous half of an expression EXISTS but not the branch/polarity/direction that makes
it correct is vacuous.** For any `verify/*.sql` (check_name, bad) sentinel, the load-bearing
part is the `CASE … THEN <bad-value>` direction, not the `has_function_privilege(...)` call —
pin the direction. Same reflex as the `red-verification-must-distinguish-gated-from-ungated`
family: mentally mutate the artifact and confirm the test flips RED for each mutation.

## Tags
category: test-failures
module: apps/web-platform/test/supabase-migrations
