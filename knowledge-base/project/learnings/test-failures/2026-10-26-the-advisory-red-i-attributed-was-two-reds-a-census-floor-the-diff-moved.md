---
title: The suite red I attributed to the designed-advisory guard was two reds — the diff had moved a census floor
date: 2026-10-26
category: test-failures
component: apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh
tags:
  - qa
  - census-floor
  - heredoc-inventory
  - advisory-red
  - suite-cardinality
  - attribution
related:
  - https://github.com/jikig-ai/soleur/pull/11159
  - https://github.com/jikig-ai/soleur/issues/11103
  - knowledge-base/project/learnings/2026-09-09-the-linter-rewrote-the-fixtures-its-own-suites-assert-on.md
  - knowledge-base/project/learnings/2026-09-08-the-guard-was-deleted-the-plan-still-cited-it-and-the-linter-validated-the-citation.md
---

# Learning: the suite red I attributed to the designed-advisory guard was two reds — a census floor the diff moved

## Problem

QA on PR #11159 (the inner-`bash -c` credential-expansion fix, #11103) ran
`cloud-init-inngest-bootstrap.test.sh` and got `rc=1, 267/269`. The plan, tasks.md, and
session-state all said the suite's red was **GuardA designed-advisory** (ADR-232: the baked
carriers drift from the `vinngest-v*` pin until the image tag propagates — expected,
non-required). Attributing the rc=1 to GuardA alone was wrong by one: the log carried a
SECOND failure —

```
FAIL: GuardD dispatch: the heredoc scan found the full inventory (found 11)
```

GuardD pins the heredoc inventory of `inngest-bootstrap.sh` at an exact cardinality
(`(( GD_ALL == 10 ))`) so a scan that inspects nothing cannot certify. This PR added the
quoted `<<'SERVERLAUNCHEOF'` heredoc (the rendered `inngest-server-launch.sh`), so the
inventory legitimately became 11 — and the floor was never bumped. The work phase had run
the suite (tasks.md 4.2 ticked), seen rc=1, and filed it under "GuardA designed-advisory"
without counting the reds.

The introducing commit `235693e411` added GuardD and a heredoc to `inngest-bootstrap.sh`
*in the same commit* — the pin moving with the diff is the established convention, not an
invention.

## Solution

Bumped the census literal `(( GD_ALL == 10 ))` → `(( GD_ALL == 11 ))` in the same PR
(`be11fc8a1e`). Re-ran the suite: `268/269`, and the one remaining red is exactly the
designed-advisory GuardA row — nothing else.

The discriminator that caught it: an "advisory red" is a claim about WHICH asserts fail,
not about the exit code. Grep the FAIL lines and diff the failing-row SET against the
designed-advisory set — `rc=1` + "GuardA is expected" certifies nothing about rows 2..N.

## Key Insight

**A designed-advisory red is a set-membership claim, not an exit-code claim.** When a
suite is *expected* to red, the correct verification is "the failing rows are exactly the
advisory set" — counted by name — never "rc != 0, as predicted." A second failure hides
perfectly behind the first because the exit code, the suite name, and the narrative all
still match. The same shape as the known-pre-existing-failure trap (a matching failure
COUNT is the weakest evidence) one level down: here even the count was wrong, and the
label still absorbed it.

Corollary for the *authoring* side: when a diff changes a counted inventory (heredocs,
units, carriers, routes — anything a `== N` census floor or `MIN_*` constant pins), the
floor bump is part of the diff. Plan/task templates that list suite files to TOUCH
(`doppler-injection-bound.test.sh`, `inngest.test.sh`) but not the suites whose pins the
diff merely perturbs (`cloud-init-inngest-bootstrap.test.sh`) produce exactly this miss.

## Session Errors

- **GuardD floor left stale by the work phase** — Recovery: QA read the FAIL rows by name,
  bumped `GD_ALL == 10` to `11` in the same PR (`be11fc8a1e`), re-ran to 268/269. —
  **Prevention:** for every suite a diff makes red, enumerate the failing assert NAMES and
  diff the set against the declared-advisory set before attributing; task lists should
  grep the touched source for counted inventories (`<<`, `Exec*=`, carrier lists) and name
  each suite whose census floor the diff perturbs.
- **`git show origin/main:inngest-bootstrap.sh` failed — relative path inside
  `apps/web-platform/infra/`** — Recovery: re-ran with the full repo path. — **Prevention:**
  use `origin/main:./<file>` or the repo-root-relative path; `git show` resolves pathspecs
  against the toplevel, not cwd.
- **`vector-admission.test.sh` not found under `apps/web-platform/infra/`** — Recovery:
  `git grep` located it at `apps/web-platform/test/infra/`. — **Prevention:** plan ACs should
  write suite paths repo-root-relative; a bare basename under the wrong dir is a
  file-not-found, not a suite result.
- **Session started in the bare repo, not the worktree** — Recovery: `cd`'d to the
  worktree; all git ops already used `git -C <worktree>`. — **Prevention:** verify `pwd`
  against the mandated worktree before the first file op (the parent brief said to).

## Tags

category: test-failures
module: apps/web-platform/infra
