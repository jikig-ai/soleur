# Tasks: SQL twin re-trim + stored-row re-normalization (#10633)

Plan: `knowledge-base/project/plans/2026-10-22-fix-normalize-repo-url-sql-retrim-backfill-plan.md`
Branch: `feat-one-shot-10633-normalize-repo-url-sql-retrim` | Draft PR: #10876

## Phase 0: Preconditions

- 0.1 Re-run `git fetch origin main` and confirm ordinal `163` is free on `origin/main` and across pushed branches.
- 0.2 Capture baseline counts for dev and prd (counts only; wrap `psql` as `doppler run -p soleur -c <cfg> -- sh -c 'psql "$DATABASE_URL_POOLER" ...'`) and keep them for the PR body. Do this BEFORE the first push containing the migration.

## Phase 1: Parity oracle and RED tests (`apps/web-platform/test/repo-url-sql-parity.test.ts`)

- 1.1 Make `sqlNormalize031` faithful: space-only trim; `rest` pattern `/^[^/]*\/\/[^/]+(\/[\s\S]*)$/`.
- 1.2 Add `sqlNormalize163` (ASCII-class trim, lowercase scheme+host, one tail strip `(/|\.git|[ \t\n\r\f\v])+$` case-insensitive, host guard) and the sync-sites registry header.
- 1.3 Add `SHIELDED_WS_FIXTURES` (space shields host-position only), the `sqlNormalize031` differs-on-D1/D2/D3 sub-list, and the `OUT_OF_PARITY` table pinning both sides (`https://x/y .git`, the path-space shield `http://a.aa/` + space + newline + `.git/`, dot-segment, default port, `http://.git`).
- 1.4 Add property tests P1 (`TS === sql163`) and P3 (`sql163(TS(x)) === TS(x)`) with the letter-initial host generator, plus a negative-control `it`.
- 1.5 Create `apps/web-platform/test/fixtures/sql/normalize-repo-url-163-golden.sql` and the `PG_GOLDEN_163` assertion (table filled in Phase 2).

## Phase 2: Migration 163

- 2.1 Write `163_renormalize_repo_url.sql`: header, `canon-expr` block, precondition `DO` block (explicit `repo_url IS NOT NULL`, count-only `RAISE`), two guarded `UPDATE`s.
- 2.2 Write `163_renormalize_repo_url.down.sql` (no-op with comment).
- 2.3 Rehearse the body on dev inside `BEGIN; ... ROLLBACK;`: seeded shielded rows change, second run `UPDATE 0`, seeded collision pair raises and modifies nothing, NULL-pair does not raise.
- 2.4 Generate `PG_GOLDEN_163` from the committed expression on dev (SELECT only); paste; Phase 1 tests GREEN.

## Phase 3: Verify sentinel and shape test

- 3.1 Write `supabase/verify/163_renormalize_repo_url.sql` (three rows; no `"`, no backslash in code position, no non-ASCII, no `E''`).
- 3.2 Write `test/supabase-migrations/163-renormalize-repo-url.test.ts` (offset ordering, NULL filter, count-only `RAISE`, expression-identity set size 1, `check_name` set, no-op down, no `public.users`).
- 3.3 Run `verify-sql-string-literals.test.ts` and the new shape test.

## Phase 4: Flake pins and closure

- 4.1 Add the regression `describe` to `test/lib/repo-url.property.test.ts` (six pins, labelled with run ids, no seed params).
- 4.2 Run the pins once against `git show 91594324ef:apps/web-platform/lib/repo-url.ts` (scratch copy) and note which fail.
- 4.3 Post evidence comments on #10732 and #10713.

## Phase 5: Docs and pointers

- 5.1 `lib/repo-url.ts` docstring only: point to the sync-sites registry.
- 5.2 ADR-293 First yield paragraph; learning follow-up line resolved.

## Phase 6: Verification and ship prerequisites

- 6.1 Scratch fuzz of P1 and P3: 100,000 runs over at least 3 seeds.
- 6.2 `lint-migration-immutability.sh`, `lint-guard-contract.py`, `technical-ruling-gate.sh --branch ...`, markdownlint on plan and tasks.
- 6.3 One RED proof per Guard Contract guard, reverted.
- 6.4 PR body: `Closes #10633`, `Closes #10732`, `Closes #10713`, baselines, rehearsal notes, #10692 untouched.
