---
title: "fix: verify/154 uses a double-quoted LIKE pattern, failing the release verify-migrations job"
type: fix
date: 2026-10-04
slug: verify-154-double-quoted-like-literal
branch: feat-one-shot-verify-154-double-quoted-like
issue: 8609
closes: none
lane: single-domain
---

# fix: verify/154 uses a double-quoted LIKE pattern, failing the release verify-migrations job

Refs #8609 (unblocks R-step 4's release; does NOT close #8609). Draft PR: #9467. Never `Closes #8211`.

## Overview

`apps/web-platform/supabase/verify/154_inbox_item_idempotent_rearchive.sql` check (1) writes its
`LIKE` pattern with double quotes. In Postgres a double-quoted token is an identifier, so the
statement fails at parse/bind with
`ERROR: column "%status = 'archived' THEN RETURN%" does not exist`. `run-verify.sh` runs each file
under `ON_ERROR_STOP=1`, so the file is counted as failed ("Verify summary: 29 passed, 1 failed",
workflow_dispatch run 37186697713, job `verify-migrations`), the job goes red, and the release
cannot proceed to deploy. The defect was introduced by PR #9283 (migrations 145 + 154, merged
2026-09-30).

Scope is deliberately small and is its own PR: (1) fix the one literal, (2) confirm no other file
under `apps/web-platform/supabase/verify/` has the same defect, (3) add a cheap vitest guard so the
class cannot recur, (4) record why the defect hid for four days and whether the intended semantic
still holds. No workflow file is touched, so the "no `--admin` merge" restriction is not triggered.
Sibling draft PR #9456 (adds `verify/155_email_inbox_routes.sql`) is not touched.

## Research Insights

### Premise Validation (Phase 0.6)

- #8609: open (security: soleur-ai runtime App key). Cited only as `Refs`. Holds.
- PR #9283: MERGED 2026-09-30T19:54:24Z, title "feat(inbox): bulk archive ... (migs 145+154)".
  `git log` shows `e0b0a9cc79` (#9283) is the only commit touching both the 154 migration and its
  verify file. Holds.
- Failing run 37186697713: `workflow_dispatch`, head `907b0a50`, `release / release` success,
  `migrate` success, `verify-migrations` **failure**, `deploy` skipped. Holds.
- The defect line exists on `origin/main` (worktree is at main + draft-PR scaffold only). Holds.
- Mechanism vs ADR corpus: the "mechanism" here is a one-character-class quoting fix plus a lint;
  no ADR decides otherwise. Nothing rejected.

### Property List and Cut List (Phase 0.6b)

Properties (observable outcomes):

1. `verify/154` check (1) parses and returns `bad = 0` when the live function body contains the
   idempotent early return, and `bad = 1` when it does not.
2. No file under `verify/*.sql` carries a double-quoted token where a string is meant.
3. A future `verify/*.sql` with that defect is rejected before merge, on the PR, without needing a
   release run (see CTO review: only a real Postgres run catches bind-time errors in general; a
   lexical no-`"` rule is the cheap layer that catches this class).

Mechanisms considered and cut:

- Rewrite `run-verify.sh` to pre-parse files (e.g. `psql --single-transaction -c 'EXPLAIN'`)
  -> buys property 3 only at release time, which is the very gate that is slow and (see below)
  rarely runs; the PR-time vitest is cheaper and earlier. CUT.
- Add pgTAP / a Postgres service container to PR CI to execute every verify file -> buys 1-3 but
  is a CI-infra addition far beyond "keep scope small"; the repo has no PR-time Postgres for
  `verify/` today (confirmed: only `plugins/soleur/test/preflight-discoverability-test.test.ts`
  and per-migration vitest string-shape tests reference `supabase/verify`). CUT; named as the
  structural option in the Phase 4 follow-up. A local scratch Postgres is used once (Phase 3).
- A SQL-parser-based lint (e.g. libpg-query) -> `LIKE "x"` is syntactically valid; the failure is a
  bind-time error, so a parser would not catch it. CUT.
- A previous-token operator allow-list tokenizer (first design) -> replaced after Plan Review by
  the simpler, stronger "no `"` in code" rule (Phase 2).
- Fix `web-platform-release.yml` so `verify-migrations` runs on the `workflow_run` arm -> a real
  gap (see "Why it only failed now") but a workflow change, a different subsystem, and it would
  flip the no-admin-merge rule. CUT from this PR; tracked as a follow-up (Phase 4).

### Why migration 154's verify only failed now (evidence-backed)

`run-verify.sh` (invoked by the `verify-migrations` job at
`.github/workflows/web-platform-release.yml` "Run verify files" step) runs EVERY `verify/*.sql`
file on every invocation, against prd via `doppler run -c prd`. The job's `if:` is
`needs.migrate.result == 'success'` with `needs: [resolve-target, migrate]`.

Measured with `gh run view <id> --json jobs` over the 40 most recent `web-platform-release.yml`
runs plus a scan of runs back to 2026-09-28:

| run | event | migrate | verify-migrations |
|---|---|---|---|
| 37186697713 | workflow_dispatch | success | **failure** (first and only time it executed since #9283) |
| 37153711841, 37131511540, 37117633839, 37112455527, 37111216271, 37109604424, 37106657885, 36970234398 | workflow_run | success | **skipped** |
| all other workflow_run / push runs since 2026-09-28 | workflow_run / push | skipped | skipped |

Conclusion: `verify-migrations` has not executed on any normal deploy since #9283 merged. On the
`workflow_run` arm (the normal deploy path since #5806) the `release` job is skipped
(`if: github.event_name != 'workflow_run'`), `migrate` survives it because its `if:` leads with
`always() &&`, but `verify-migrations` has a bare `if:` (implicit `success()`), and a skipped
ancestor (`release`) skips it even though `migrate` succeeded. Only a `workflow_dispatch` run (where
`release` actually runs) exercises it, which is why the first real execution of 154's verify was the
operator's dispatch on 2026-10-04. The inline comment at the `deploy` job ("verify-migrations ...
only runs on migrate.result==success; when migrate is itself skipped, verify is skipped too")
documents the intent but not this observed behavior. The implicit-`success()`-over-skipped-ancestor
explanation is the best fit for the 8/8 observations and is stated as likely, to be confirmed in the
follow-up issue; it is NOT fixed here.

Consequence for this plan: the new PR-time vitest guard is the only pre-merge defence for the
literal class, which strengthens the case for adding it despite the "cheap" constraint.

### Does the intended semantic still hold? (read, not assumed)

- `public.set_inbox_item_state(uuid,text)` is defined by exactly two migrations:
  `122_inbox_item.sql` (original) and `154_inbox_item_idempotent_rearchive.sql`
  (`CREATE OR REPLACE`, the later one). `git grep` on `origin/main` shows no other
  `CREATE ... set_inbox_item_state`.
- 154's body contains `IF v_row.status = 'archived' THEN RETURN; END IF;` inside the
  `p_action = 'archived'` branch. `pg_get_functiondef` returns plpgsql source verbatim, so the
  pattern `%status = 'archived' THEN RETURN%` matches the 154 body.
- The pattern discriminates: 122's body has `status = 'archived'` only in `SET status = 'archived',
  archived_at = now()` and `CASE WHEN status = 'archived' THEN status ELSE`; neither is followed
  by `THEN RETURN`, so the 122 body returns `bad = 1`. Check (1) is therefore not vacuous.
- 154 was applied: `migrate` concluded success in run 37186697713 at head `907b0a50`, which
  contains 154.
- Check (2) of the same file (`cannot archive an un-acted action_required item`) is present in
  154's body, and run-verify aborts the file on check (1)'s error before reaching it (so (2) has
  also never run in prd); Phase 3 runs both.
- Local proof (no prod contact) is specified in Phase 3: scratch `postgres:16-alpine` (image
  already present locally) with `check_function_bodies = off` and the 154 function statement, then
  the 122 statement for the discrimination check. The live proof arrives on the next
  operator-dispatched release (AC8); the agent runs no prd probe.

### Sweep of other verify files

A sweep of every `"` outside `--` comment lines across all 30 verify files returns exactly one
hit (154 line 14), and an operator-anchored sweep (`LIKE|ILIKE|=|~|IN|IS|<>|!=` followed by `"`)
agrees. So the fix set is one line in one file. (Phase 1 re-runs the broader sweep as AC1.)

### Institutional learnings applied

- `2026-07-08-verify-sentinel-hardcoded-count-breaks-on-new-counted-object` and
  `2026-07-18-rls-initplan-wrap-breaks-verify-sentinels...`: verify sentinels drift from the live
  function/policy text they pin; keep sentinels anchored on a distinctive construct (here the
  `THEN RETURN` tail), not a bare token (`cq-assert-anchor-not-bare-token`).
- Existing pattern to mirror: `apps/web-platform/test/supabase-migrations/144-*.test.ts` and
  `128-*.test.ts` (file-parse vitest, `stripSqlComments`, `readFileSync` of the SQL).

## User-Brand Impact

- **If this lands broken, the user experiences:** no end-user surface; the failure mode is a
  release that stays red (no deploy of the inbox bulk-archive and the R-step 4 work), i.e. delayed
  shipping, not a broken product.
- **If this leaks, the user's data is exposed via:** no vector; the change edits one read-only
  catalog `SELECT` (`pg_get_functiondef ... LIKE`) and adds a test that reads local files.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** none, because nothing here reads or writes user data and
  the worst failure is a still-red release gate, not a user-visible incident.

threshold: none, reason: the touched `.sql` is a read-only function-definition probe under `verify/`, not a schema, migration, or auth/data path; it processes no user data.

## Scope Check

- Ask 1 (fix 154 line ~15 as a single-quoted literal with doubled inner quotes) -> Phase 1.
- Ask 2 (check every other verify file for the same defect and fix any) -> Phase 1 sweep (AC1/AC2); one hit total.
- Ask 3 (cheap guard if the harness makes it natural) -> Phase 2 vitest in the existing
  `test/supabase-migrations/` pattern (the rule is a superset of the asked "after LIKE/=" rule). The harness (`run-verify.sh`) itself has no PR-time test
  seam; the vitest suite does, so the guard lives there.
- Ask 4 (state why 154's verify only failed now) -> "Why migration 154's verify only failed now".
- Ask 5 (confirm the intended semantic still holds) -> "Does the intended semantic still hold" +
  Phase 3 scratch-DB proof.
- Every item maps to an ask; the only item beyond them is the Phase 4 follow-up issue for the
  workflow skip, a deferral tracker required by the deferral-tracking rule, not scope.
- Split assessment: single PR; one subsystem (Supabase verify sentinels).

## Files to Edit

- `apps/web-platform/supabase/verify/154_inbox_item_idempotent_rearchive.sql` — line 14:
  `LIKE "%status = 'archived' THEN RETURN%"` becomes `LIKE '%status = ''archived'' THEN RETURN%'`.
  (Header comment of the same file stays; no other line changes.)

## Files to Create

- `apps/web-platform/test/supabase-migrations/verify-sql-string-literals.test.ts` — the guard
  (literal/comment stripper + inline fixtures + a real-population scan of `supabase/verify/*.sql`).
- `knowledge-base/project/specs/feat-one-shot-verify-154-double-quoted-like/tasks.md` — task list.

Not touched: `verify/155_email_inbox_routes.sql` (#9456's), `run-verify.sh`,
`.github/workflows/**`, any migration file (154's header says "146" while the file is 154 — a
cosmetic pre-existing slip, out of scope).

## Open Code-Review Overlap

None. (Queried open `code-review` issues for each path above; no body references
`verify/154_inbox_item_idempotent_rearchive.sql`, `test/supabase-migrations/`, or the new test.)

## Implementation Phases

### Phase 1 — Fix the literal and sweep

1.1 Edit line 14 of verify/154 to `LIKE '%status = ''archived'' THEN RETURN%'`.
1.2 One sweep (AC1): any `"` outside `--` comment lines in `verify/*.sql` must return nothing.
1.3 No other verify file changes (the sweep found none).

### Phase 2 — Guard (TDD: write the test first, watch it fail on the unfixed file)

Plan Review (DHH, code-simplicity, CTO, Kieran) cut the first design (a previous-token operator
tokenizer, 13 fixtures, a `>= 30` floor) down to the rule below. The simpler rule is also STRONGER:
it has no operator list to drift (`IN ("a")`, `THEN "x"`, `COALESCE(x, "")` are caught too).

New test `apps/web-platform/test/supabase-migrations/verify-sql-string-literals.test.ts`:

- Local helper `codeWithoutLiteralsAndComments(sql)`: strip, in this order, `--` line comments,
  `/* ... */` block comments (non-nested), `'...'` literals with `''` escapes, and
  `$$ ... $$` dollar-quoted bodies (tag must be empty or identifier-shaped, not `$1`).
- Rule: no `"` may remain in the stripped text of any `verify/*.sql` file. Rationale in the failure
  message: "a double-quoted token is a Postgres IDENTIFIER, not a string; use a single-quoted
  literal and double any inner `'` (see verify/154 history, #9283)". Findings report `file:line`.
- Verify directory is resolved as `join(__dirname, "../../supabase/verify")` (two hops from
  `test/supabase-migrations/`, exactly as `128-*.test.ts` does); a three-or-more-hop spelling would
  trip `test/repo-wide-containment.test.ts`.
- Assertions: (a) `readdirSync(...).filter(.sql).length > 0` (guard cannot pass over zero files);
  (b) each file's stripped text has no `"`; (c) inline fixtures through the same helper:
  RED: the original defect line (`LIKE "%status = 'archived' THEN RETURN%"`), and a file whose
  FIRST statement is compliant and SECOND is `ILIKE "..."`; must-PASS (differ from the canonical
  fix): `LIKE '%"x"%'` (double quote inside a single-quoted literal), `-- = "x"` and `/* LIKE "x" */`
  comments, a `$$ ... "x" ... $$` body, and `'it''s'`.
- Documented limits (stated in a test comment, not modelled): `E'..\'..'` backslash strings and
  nested `/* /* */ */` comments. If a future verify file uses one, early termination can surface as a
  FALSE POSITIVE (loud, fail-closed), never a silent pass of a real defect. No verify file uses
  either today. A legitimate quoted identifier is also flagged; none exists, and the remedy is to
  use an unquoted lowercase name (no allow-list, YAGNI).
- Run only this file: `cd apps/web-platform && npx vitest run test/supabase-migrations/verify-sql-string-literals.test.ts`
  (targeted; no full battery). The existing `include: ["test/**/*.test.ts", ...]` unit project
  picks it up; no wiring.
- TDD order (`cq-write-failing-tests-before`): write the test, run it against the UNFIXED 154 and
  see (b) go RED naming `154_inbox_item_idempotent_rearchive.sql:14`, then apply Phase 1.1 -> GREEN.

### Phase 3 — Prove the fixed file executes (one scratch run, no production contact)

Check (2) of the same file has never executed (check (1) aborted the file under `ON_ERROR_STOP=1`),
so a second latent error would redden the next dispatched release. One run covers both checks:

1. `docker run --rm -d -e POSTGRES_PASSWORD=x -p <free port>:5432 postgres:16-alpine`
   (image already present locally); remove the container afterwards.
2. In that DB: `SET check_function_bodies = off;` (so the `public.inbox_item%ROWTYPE` and
   `auth.uid()` references need no stubs; the function is never executed, only its definition is
   read), then run the single `CREATE OR REPLACE FUNCTION public.set_inbox_item_state ...` statement
   from `154_inbox_item_idempotent_rearchive.sql`.
3. `psql ... -tAF $'\t' -f apps/web-platform/supabase/verify/154_inbox_item_idempotent_rearchive.sql`
   expect `idempotent_rearchive	0` and `archive_guard_intact	0`.
4. Discrimination, one line: re-run step 2 with the `CREATE OR REPLACE` from `122_inbox_item.sql`
   and confirm `idempotent_rearchive	1` (the sentinel is not vacuous).

Paste the recipe and outputs into the PR body so the next sentinel author can reuse it. No prd
probe is run by the agent; live confirmation arrives on the next operator-dispatched release (AC8).

### Phase 4 — Follow-up issue (filed from this PR, not in its diff)

File one GitHub issue (milestone from `knowledge-base/product/roadmap.md`, priority label) titled
roughly "ci: verify-migrations is skipped on the workflow_run deploy arm, so supabase/verify never
runs on normal deploys". Body: the evidence table above; the skipped-ancestor hypothesis flagged as
UNPROVEN with a cheap experiment (a one-line `always() &&` guard on a throwaway branch plus a dry
run, since GitHub does not report skip reasons); the intent evidence that the release budget math
(`job_ceiling "$REL" verify-migrations` in `web-platform-release.yml`) already counts the job in the
deploy path; a warning that enabling it makes `deploy` (which lists it in `needs:`) block on all
30 verify files on every normal deploy, including any latent red, so roll out behind a dry run; and
the structural option (ephemeral Postgres + migrations + verify in PR CI, which is the only layer
that catches bind-time errors like this one — a SQL parser accepts `LIKE "x"` as valid syntax).
That workflow change needs its own PR and the no-`--admin` rule. Link it in the PR body; the PR
uses `Refs #8609` only.

## Guard Contract

### Guard 1 — verify-sql no-double-quote lint

**Property.** No executable text (outside comments, single-quoted literals and dollar-quoted
bodies) in any `apps/web-platform/supabase/verify/*.sql` file contains a double-quoted token, so a
string can never be written where Postgres would parse an identifier.

**Assembly.** Population = every `*.sql` returned by `readdirSync` on the verify directory at test
time (not a hard-coded list), so a new file is covered automatically. Chokepoint = the single
`codeWithoutLiteralsAndComments` helper every file and every inline fixture flows through; there is
one dispatch (the directory loop) and one stripper, so there is no second path to drift. Out of
scope by design: `migrations/*.sql` (applied by `run-migrations.sh`, which fails at apply time — a
different surface) and the documented lexer limits (`E''` strings, nested block comments).

**Mutation matrix.**

| # | Edit | Must go RED because |
|---|---|---|
| 1 | Restore the original `LIKE "%status = 'archived' THEN RETURN%"` in verify/154 | directory case reports `154_inbox_item_idempotent_rearchive.sql:14` |
| 2 | Point the directory at an empty/non-matching path | `length > 0` assertion fails (cannot report "0 checked, pass") |
| 3 | Add a second, defective `ILIKE "..."` statement after a compliant first one in a file | stripper keeps scanning; the second member is reported (not just the first) |
| 4 | Harness: make the stripper/check return "no findings" unconditionally | the inline RED fixtures (original defect, second-member file) fail, so a vacuous check cannot pass the suite |

Must-PASS rows that are not the canonical fixed 154 line: `LIKE '%"x"%'`, `-- = "x"`,
`/* LIKE "x" */`, a `$$ ... "x" ... $$` body, `'it''s'`. A check that rejects everything fails
these; a check that only accepts the canonical line fails them too.

**Anchor.** The guard compares no stored value (no hash/manifest); the only constant is
`length > 0`, which cannot be weakened by an add-one-delete-one edit. N/A beyond that.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1: `grep -n '"' apps/web-platform/supabase/verify/*.sql | grep -v ':[0-9]*:[[:space:]]*--'`
  returns no lines (expected output: empty).
- [ ] AC2: `sed -n 14p apps/web-platform/supabase/verify/154_inbox_item_idempotent_rearchive.sql`
  prints a line containing `LIKE '%status = ''archived'' THEN RETURN%'`.
- [ ] AC3: `cd apps/web-platform && npx vitest run test/supabase-migrations/verify-sql-string-literals.test.ts`
  passes; it was first run against the UNFIXED 154 and failed naming `...154_...sql:14`.
- [ ] AC4: Phase 3 scratch-DB output recorded in the PR body: fixed file with the 154 body ->
  `0` and `0`; with the 122 body -> `idempotent_rearchive 1`.
- [ ] AC5: Diff contains only the 154 verify edit, the new test, and plan/spec artifacts. No change
  to `.github/workflows/**`, `run-verify.sh`, any migration, or `verify/155_*`.
- [ ] AC6: PR body uses `Refs #8609`; contains no `Closes #8211` and no `Closes #8609`.
- [ ] AC7: The follow-up issue from Phase 4 exists (number cited in the PR body) with a milestone
  and priority label.

### Post-merge (no workflow dispatched by the agent)

- [ ] AC8: The next release run that executes `verify-migrations` (a `workflow_dispatch` run, since
  the `workflow_run` arm skips it) prints
  `ok 154_inbox_item_idempotent_rearchive.sql/idempotent_rearchive (bad=0)` and `0 failed`. The
  agent does not dispatch `web-platform-release.yml` or any production workflow.

## Test Scenarios

- Given verify/154 as shipped in #9283, when the guard test runs, then it fails naming line 14.
- Given the fixed file, when the guard test runs, then all files are scanned and none reports a `"`.
- Given a file with a compliant first LIKE and a double-quoted second `ILIKE`, then it is reported.
- Given a `"` inside a single-quoted literal, a comment or a `$$` body, then nothing is reported.
- Given the 122-era function body, when verify/154 runs in the scratch DB, then
  `idempotent_rearchive` is 1.

## Risks and Sharp Edges

- The stripper is a lexical approximation, not a Postgres parser (a parser would not help anyway:
  `LIKE "x"` is syntactically valid and fails at bind time). Limits are documented in Phase 2 and
  fail loud, not silent.
- `verify-migrations` being skipped on normal deploys means this PR-time guard is the only
  automatic defence for the class until the follow-up lands.
- Do not run any workflow; do not dispatch `web-platform-release.yml` (operator boundary).
- A plan whose `## User-Brand Impact` section is empty or placeholder fails deepen-plan Phase 4.6;
  this one carries the threshold and a scope-out line.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — CI/test-hygiene fix confined to a Supabase verify
sentinel and one vitest file. No UI surface (no Product/UX gate), no new infrastructure (Phase 2.8
skipped), no architectural decision (Phase 2.10 skipped: a bug fix on an existing surface), no
persistent store or connection (Phase 2.11 skipped), and no code-class path under
`apps/*/server|src|infra` or `plugins/*/scripts` (Phase 2.9 Observability skipped). GDPR gate: the
only `.sql` touched is a read-only `pg_get_functiondef` probe that processes no personal data; the
regulated-surface regex match on `.sql` is nominal, so no gdpr-gate invocation is warranted.
