# Guard observations (AC-8) — applied, expectation observed

Guard 2's rows are re-runnable by anyone (`bash scripts/lib/trusted-verdict.test.sh`, 11/0).
Guard 1's and the drop-arm rows are attested here because both subjects are transient: the drop
workflow is deleted in commit B, so a committed harness for it would be orphaned the day it
landed — which is why the plan cut a static shape guard for that file.

## Guard 1 — anti-vacuity floor on the RLS workflow shape guard

Sandbox copy, pristine backup, every mutation asserted to have LANDED before scoring, restored
from the pristine copy (never `git checkout`, which restores to HEAD). Control run first:
`passed=17 failed=0`, rc 0.

| # | Mutation | Expected | Observed |
|---|---|---|---|
| 1 | delete an `assert` line and its `checks` key together | RED | rc 1 — `FLOOR: executed 16 assertions, declared EXPECTED_TOTAL=17` |
| 2 | delete every key from the `checks` dict | RED | rc 1 — `passed=2 failed=15` (KeyError per probe), floor also breached |
| 3 | `assert()` never increments `FAIL` | RED | rc 1 — `passed=0 failed=0`, `FLOOR: executed 0 assertions` |
| 4 | `PRD_WF` points at a nonexistent path | RED | rc 1 — `passed=0 failed=17` |
| 5 | must-PASS: prd workflow YAML round-tripped through pyyaml + a new comment | PASS | rc 0 — `passed=17 failed=0` |

**Row 3 as drafted was unobservable, and that is worth recording.** With the guard otherwise
intact NO assertion fails, so "make `assert()` never increment `FAIL`" changes nothing and the
first run of it reported PASS. The matrix's own text says the row needs a known-bad fixture
("if it does not, the harness is lying"); re-run paired with a nonexistent `PRD_WF`, the floor
sees `PASS + FAIL == 0` against `EXPECTED_TOTAL=17` and reds. A mutation row that cannot be
observed is not a passing row — it is a void one.

## Guard 2 — trusted-verdict filter

Rows 1-4, 4b, 4c and 7 are committed fixtures in `scripts/lib/trusted-verdict.test.sh`
(11 passed, 0 failed). Rows 5 and 6 are mutations of the mechanism:

| # | Mutation | Expected | Observed |
|---|---|---|---|
| 5 | delete the permission lookup; pipe `.comments[].body` straight to the grep | RED | rc 1 — row 1 flips to `verdict='RESULT: PASS'` from an untrusted login, row 4 flips from TRANSIENT to rc 0 |
| 6a | re-inline `select(.authorAssociation == "OWNER")` in a probe | RED | lint rc 1, 1 × `rule 4:` citation at the true line |
| 6b | must-PASS: the same shape inside a COMMENT | PASS | lint rc 0 — the anchor is the filter, so the rationale comment stays writable |
| 6c | DISPATCH: delete the `# rule4-grep` line, re-run 6a | PASS | lint rc 0 — that grep IS the mechanism |

Rows 6a/6b/6c plus rule 4's own floor breach are also committed, as R4-M1..M4 in
`scripts/lint-followthrough-varq-ban.test.sh` (80 passed, 0 failed, floor 80).

**Two defects this found that reading the code did not.** (a) The lib's permission memo was
written inside a command substitution, so the subshell discarded it and EVERY author resolved as
untrusted — rows 2, 3 and 7 reported "no verdict" while row 1 (the untrusted fixture) still
passed, which is indistinguishable from the filter working. (b) A bot commenter answers
`"github-actions is not a user" (HTTP 404)`, which the first build treated as TRANSIENT; since
`github-actions` comments on nearly every tracker, that makes every such thread permanently
unresolvable — the same permanent-red outcome the lib exists to remove, reached from the other
side. Both now have fixtures in both directions (4b/4c).

## Drop arm — refusal paths (not a plan guard; added because the write is irreversible)

The `run:` body extracted with PyYAML and executed under a `curl` stub that records every POSTed
statement and exits 64 on argv it did not expect. `drops=` counts `DROP TABLE` statements that
actually reached the wire, so a row scores whether the WRITE was blocked, not merely whether the
exit code was non-zero.

| # | Fixture | Expected | Observed |
|---|---|---|---|
| A | `mode=drop`, present=14, posture=14 | rc 0, exactly 1 DROP | rc 0, drops=1 |
| B | `mode=drop`, present=14, **posture=13** | rc 1, **0 DROPs** | rc 1, drops=0, `precondition_posture` |
| C | `mode=drop`, **present=13** | rc 1, **0 DROPs** | rc 1, drops=0, `precondition_tables` |
| D | `mode=dry-run`, present=14, posture=14 | rc 0, **0 DROPs** | rc 0, drops=0 |
| E | drop POST succeeds, post-verify still sees 3 | rc 1 | rc 1, `post_verify` |

Zero stub misses across all five rows. The statement emitted in A and E, verbatim:

```sql
SET lock_timeout TO '10s'; DROP TABLE public.apps, public.event_batches, public.events, public.function_finishes, public.function_runs, public.functions, public.goose_db_version, public.history, public.migrations, public.queue_snapshot_chunks, public.spans, public.trace_runs, public.traces, public.worker_connections;
```

All 14, schema-qualified, no `CASCADE`, no `IF EXISTS`, `lock_timeout` set first.
