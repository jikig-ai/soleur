---
title: Shared RLS schema DDL needs file serialization
date: 2026-10-08
category: test-failures
tags: [rls, postgres, deadlock, vitest, ci-only]
issue: '#9779'
---

# Shared RLS schema DDL needs file serialization

At head `d445c1159cd843de7588ed7ef92800b053cd055f`, RLS run 37844980733
applied migrations successfully but failed one of 131 tests with PostgreSQL
40P01. The binding-repair test's trigger drop requested AccessExclusiveLock
on relation 17068 while another backend held it and waited for AccessShareLock
on relation 18611. The backend identities and relation mapping were not
available in the captured test log; do not invent their precise statements.

Source inspection established that the RLS files run in parallel against one
disposable schema, each with its own single-connection pool. The repair test
drops/recreates a conversations trigger inside a rolled-back transaction;
the authz positive control also changes table-level RLS. Unique fixture rows
and per-file connection limits cannot isolate schema locks between files.
The same source is on main, and OPEN issue #9779 already tracks earlier
occurrences. Its description calls this teardown, but this occurrence failed
inside the repair test body before its migration assertion completed.

The CI-only workaround appends `--no-file-parallelism` to the workflow's
standalone RLS invocation. It retains every test and transaction helper,
loopback guard, migration application, positive control, parity condition and
deadline. Ordinary unit/component runs and the package script are unchanged.
The issue has a separate active draft fix; this change does not assert that
all invocation paths are repaired or close that issue.

[Vitest v4's fileParallelism documentation](https://v4.vitest.dev/config/fileparallelism)
confirms that the flag serializes files without changing tests within a file.
Static workflow validation precedes the push; fresh exact-head CI must prove
the actual harness runs successfully. No local suite or database action was
performed because qualification holds persist.

During inspection, an un-escalated PR-diff request failed to reach GitHub.
The escalated retry returned an empty diff, consistent with the live draft's
empty file list. A draft's title is not evidence that it contains a fix.
