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

## AC-6 — gate evidence, and why it is a substitute set rather than a shard

`TEST_GROUP=scripts bash scripts/test-all.sh` exited **4 — REFUSED, nothing ran.** Not a pass and
not a red: the runner MEASURED two sibling full-gate runs in flight (`feat-one-shot-8361-...` and
`feat-one-shot-auto-inngest-pin-bump`, 1815 s and 1467 s at the time) and refused rather than let
concurrent runs inflate each other's timings and push suites past their own timeouts. The log also
carried `SIBLING_RUN_DETECTED` and `CAPACITY_CONTENDED reason=sibling_runs`.

Its own preamble named the second gap before anything ran: *"your diff touches
apps/web-platform/infra/, but TEST_GROUP=scripts does NOT include the infra runner. Nothing below
is evidence for that directory."* Both gaps are covered below.

**Substitute set derived from CONSUMERS, not memory** — for every changed file,
`git grep -l -- "$f" -- '*.test.sh' '*.test.ts' tests/scripts`. The raw derivation returned 144
suites and that is an artefact, not coverage: `scripts/test-all.sh` is in the diff and nearly every
suite references it. The set below is the subset that actually gates the substantive changes.

23 suites, 23 rc=0, 0 failed:

```
scripts/lib/trusted-verdict.test.sh                     scripts/lint-orphan-test-suites.test.sh
scripts/followthroughs/concierge-strand-...-5733.test.sh scripts/lint-shell-trace-credential-refusal.test.sh
scripts/followthroughs/cpx22-invoice-reconcile-7431.test.sh scripts/lint-guard-contract.test.sh
scripts/lint-followthrough-varq-ban.test.sh              scripts/suite-exit-class-parity.test.sh
scripts/followthrough-predicate-parity.test.sh           plugins/soleur/test/scripts-shard-totality.test.sh
scripts/followthrough-exec-bit.test.sh                   plugins/soleur/test/infra-validation-detect.test.sh
scripts/follow-through-closure-guard.test.sh             plugins/soleur/test/fixture-relative-assert.test.sh
plugins/soleur/test/fixture-dir-operand-assert.test.sh   plugins/soleur/test/ship-followthrough-directive.test.sh
plugins/soleur/test/c4-count-parity.test.sh              apps/web-platform/infra/inngest-rls/inngest-rls.test.sh
apps/web-platform/infra/inngest-rls/apply-inngest-rls-workflow.test.sh
apps/web-platform/infra/run-registered-suites.test.sh    apps/web-platform/infra/supabase-advisor/scan-workflow.test.sh
.github/scripts/test/test-infra-suite-registration.sh    tests/scripts/test-lint-supabase-deprecated-endpoints.sh
```

**New-vocabulary sweep** (a drift guard keyed on a token this diff introduces would name no file it
touched): the diff adds `trusted_verdict_bodies` and `_TRUSTED_VERDICT_PERM` and no `SOLEUR_*`
marker. `git grep -l` over `*.test.sh`/`*.test.ts` returns only suites already in the set above.

**Environment sweep.** A suite can be green locally and red on merge, so each new or materially
changed suite was re-run under `CI=1` and `SOLEUR_SUBAGENT=1`, comparing PASS COUNTS and not just
exit codes:

| Suite | local | `CI=1` | `SOLEUR_SUBAGENT=1` |
|---|---|---|---|
| `trusted-verdict.test.sh` | rc 0 | rc 0 | rc 0 |
| `concierge-strand-754ee124-5733.test.sh` | rc 0, 13 passed | rc 0, 13 passed | rc 0 |
| `cpx22-invoice-reconcile-7431.test.sh` | rc 0, 16 passed | rc 0, 16 passed | rc 0 |
| `lint-followthrough-varq-ban.test.sh` | rc 0, 80 passed | rc 0, 80 passed | rc 0 |
| `inngest-rls.test.sh` | rc 0 | rc 0 | rc 0 |
| `apply-inngest-rls-workflow.test.sh` | rc 0 | rc 0 | rc 0 |

No rc delta and no count delta in any row.

**Census, in the mode CI runs it in:** `bash scripts/lint-supabase-deprecated-endpoints.sh
--check-highwater` → `OK — census 22 (baseline 22)`. The plain invocation computes the ratchet but
only RETURNS it under that flag, so a plain-mode check is green locally and red in CI.

**What this set does NOT cover, stated plainly:** the full `bun`/`webplat` shards. The diff's only
`apps/web-platform/**` paths are under `infra/`, which the shard map defers to the ship Phase 4
full battery and which the infra runner above covers directly; no `docs/legal/**` path is touched,
so the legal mirror gate is not implicated. CI's required `test` context runs the shards on the PR
head regardless — that, not any local run, is the merge gate.
