# Verification record — #7652

## Gates

| Gate | Result |
|---|---|
| `TEST_GROUP=scripts bash scripts/test-all.sh` | rc=0 — `342 suites: 340 passed, 0 failed, 0 killed, 2 skipped (declined — not relevant to this diff)` |
| `TEST_GROUP=bun bash scripts/test-all.sh` | rc=0 — `7/7 suites passed` |
| `scripts/lint-diagnosis-claims.sh` | rc=0 — `1 unmeasured causal claim (baseline 1)`, unchanged |
| `scripts/guard-vacuity-floor.test.sh` | 23/0 |
| `scripts/lint-orphan-test-suites.test.sh` | 67/0 |
| `scripts/lint-trap-tempfile-ownership.test.sh` | 20/0 |
| `scripts/test-all-killed-classification.test.sh` | 77/0 |
| `scripts/test-all-infra-coverage-notice.test.sh` | 127/0 |
| `scripts/test-all-capacity-signal.test.sh` | 80/0 |
| `plugins/soleur/test/fanout-suite-scope.test.sh` | 36/0 |
| `plugins/soleur/test/fixture-cd-containment.test.sh` | 8/0 — assertion count unchanged (AC13) |
| `plugins/soleur/test/fixture-dir-operand-assert.test.sh` | 21/0 |
| `scripts/lib/repo-write-boundary.test.sh` | 29/0 |

`webplat` was not run and is not claimed: the diff touches no `apps/web-platform/` path.

## AC11 — the four dimensions, measured from OUTSIDE the runner

Snapshots taken with `REPO_BOUNDARY_SALT=ac11-salt` immediately before and after a full `scripts`
shard run, by a separate process, so the claim is not asserted by the same code it is about:

```
before: 3081 lines   after: identical (diff empty)
```

All four inspected dimensions — HEAD, this worktree's tree and index, local (shared) config, and
local heads and tags — unchanged across the run. No `[FATAL]`, no `[REPORT]`, and no not-measured
NOTE appeared in the run.

## Mutation matrices — what was EXECUTED, and what was not

Stated per axis rather than as a row count, because a row count is the number that flatters.

**Executed as live arms** (each drives the suite RED; the ones marked ✎ were additionally
mutation-proven against a pristine copy with `diff -q` confirming the mutation landed):

- Guard 1 rows 1, 2, 3, 4, 5, 6, 7, 8 — including the guard's own dispatch (empty corpus) and the
  harness row (a neutered `fail()`), both reported directly rather than through the verdict helpers.
- Guard 2 rows 1, 2, 3, 4, 5, 10, 12, 13, 14, 15 as unit arms; rows 6, 7 ✎ and 8 as window/placement
  arms; row 11 as an EXIT-trap presence arm.
- Guard 3 rows 1, 2, 3, 4 — each asserting BOTH a non-zero rc and a byte-identical probe repository
  afterwards, which is the only thing that can catch an assertion placed below the first write.
- The relocator-enumeration arm ✎ (added after a red shard found a third sandbox the plan did not
  name).

**Axes deliberately NOT sampled**, stated so the battery is not read as wider than it is:

- **Guard 2 row 11 is asserted structurally, not by killing a live run.** The arm proves the trap is
  armed and that it is wired to `_repo_boundary_reported`; it does not SIGKILL a real gate run
  mid-suite. A kill-the-run arm would need a full runner invocation per case.
- **Guard 3 row 5** (`v=$(helper "")` — `exit` inside a command substitution does not stop the
  caller) is not a live arm. It is a property of the CALL SITE rather than of the assertion, and the
  scanner covers the call sites.
- **P1b entirely** — relative operands, `rm -rf`, `mv`/`cp -r`, redirections. Tracked in #7708.
- **Suites invoked outside the runner** — lefthook's hook path, and any `bash path/to/x.test.sh`.
  The boundary says so in its own not-inspected list rather than leaving it implied.
- **Any escape reaching a remote.** No local snapshot can observe it; named in the not-inspected list.

## Phase 0 measurement

The plan's pre-committed decision rule selected AGAINST CWD isolation on measured evidence. See the
dated addendum in the plan (`### Phase 0 measurement — Addendum 2026-08-26`).
