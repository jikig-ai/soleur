# Tasks: SQL twin re-trim + stored-row re-normalization (#10633)

Plan: `knowledge-base/project/plans/2026-10-22-fix-normalize-repo-url-sql-retrim-backfill-plan.md`
Branch: `feat-one-shot-10633-normalize-repo-url-sql-retrim` | Draft PR: #10876

## Phase 0: Preconditions

- 0.1 Re-run `git fetch origin main`; confirm ordinal `163` is free on `origin/main` and across pushed branches.
- 0.2 Capture baseline counts for dev and prd (counts only; wrap `psql` as `doppler run -p soleur -c <cfg> -- sh -c 'psql "$DATABASE_URL_POOLER" ...'`): per table `total`, `with_url`, `to_rewrite`, `skipped_but_changed`, plus the collision-group count. Do this BEFORE the first push containing the migration, and re-run on prd within the hour before merge. STOP if `to_rewrite`, `skipped_but_changed` or collisions is above 0.

## Phase 1: Parity oracle and tests (`apps/web-platform/test/repo-url-sql-parity.test.ts`)

- 1.1 Make `sqlNormalize031` faithful: space-only trim; `rest` pattern `/^[^/]*\/\/[^/]+(\/[\s\S]*)$/`.
- 1.2 Add `sqlChain163` (ASCII-class trim, lowercase scheme+host, one tail strip `(/|\.git|[ \t\n\r\f\v])+$` case-insensitive, null without scheme+host) and `sqlBackfill163` (chain plus eligibility guard: no internal whitespace in the trimmed input AND clean http(s) shape); write the sync-sites registry header.
- 1.3 Add `SHIELDED_WS_FIXTURES` (space shields host-position only; length floor >= 8), the 031-differs sub-list for D1/D2/D3, `BACKFILL_FIXTURES` (031-shaped stored rows rewritten, ineligible rows untouched; floor >= 8), and `OUT_OF_PARITY` pinning both sides.
- 1.4 Add property tests inside the same file: P1 chain parity on `urlCleanArb` (letter-initial hosts), P2 backfill safety (`backfill(x) !== x` implies `backfill(x) === normalizeRepoUrl(x)`) over the adversarial generator, backfill idempotence, and a negative-control `it`.
- 1.5 Create `apps/web-platform/test/fixtures/sql/normalize-repo-url-163-golden.sql` (SELECT over `VALUES`, emitting the 031 chain, the 163 chain and the backfill outcome for every fixture raw) and the `PG_GOLDEN_163` assertions: ports equal golden columns, every fixture raw present, row count equals the script's VALUES count. Golden values are filled in Phase 2 (these assertions and the shape test are the only RED ones until then).

## Phase 2: Migration 163

- 2.1 Write `163_renormalize_repo_url.sql`: header (031 defects D1-D3 fixed; D4-D6 and ineligible rows left alone; 2026-10-22 prod observation; immutability; forward-fix = 164; strict permanent verify; no new grants), `canon-expr` block (three LATERALs), `SET LOCAL lock_timeout = '5s'`, `LOCK TABLE`, precondition `DO` block (explicit NULL, `context_path` and `archived_at` filters; count-only `RAISE`; no `USING DETAIL`/`HINT`), two guarded `UPDATE`s.
- 2.2 Write `163_renormalize_repo_url.down.sql` (no-op with comment).
- 2.3 Rehearse the body on dev inside `BEGIN; ... ROLLBACK;`: eligible shielded rows rewritten, ineligible rows (`https://github.com/o .git`, port, userinfo) untouched, second run `UPDATE 0`, seeded collision pair raises and modifies nothing, NULL pair does not raise.
- 2.4 Generate `PG_GOLDEN_163` from the committed expressions on dev (SELECT only); paste; Phase 1 tests GREEN.

## Phase 3: Verify sentinel and shape test

- 3.1 Write `supabase/verify/163_renormalize_repo_url.sql` (three rows: `conversations_noncanonical`, `workspaces_noncanonical`, `canon_expr_selftest`; no `"`, no backslash in code position, no non-ASCII, no `E''`).
- 3.2 Write `test/supabase-migrations/163-renormalize-repo-url.test.ts`: lock_timeout, lock and DO-block offsets, precondition-BODY-scoped filters, count-only `RAISE`, no `USING DETAIL`/`HINT`, expression-identity set size 1 across migration, verify and golden script (markers extracted before comment stripping), `check_name` set, no-op down, no `public.users`.
- 3.3 Run `verify-sql-string-literals.test.ts` and the new shape test.

## Phase 4: Flake pins and closure

- 4.1 Add the regression `describe` to `test/lib/repo-url.property.test.ts`: `"http://a.aa/."`, `"http://a.aa/..git"`, `"a://A"`, `" a://A .git"`, `"a://A /"`, `" a://A/..git"` (run-id labels, no seed params; annotate `"http://a.aa/."` and `"a://A"` as non-discriminating).
- 4.2 Run the pins once against `git show 91594324ef:apps/web-platform/lib/repo-url.ts` (scratch copy); note which fail (expected: `"http://a.aa/..git"`, `" a://A .git"`, `"a://A /"`, `" a://A/..git"`).
- 4.3 Post evidence comments on #10732 and #10713.

## Phase 5: Docs and pointers

- 5.1 `lib/repo-url.ts` docstring only: point to the sync-sites registry in the parity test.
- 5.2 ADR-293 First yield paragraph; learning follow-up line resolved.

## Phase 6: Verification and ship prerequisites

- 6.1 Scratch fuzz (not committed): P1 and P2 at 100,000 runs over at least 3 seeds.
- 6.2 `lint-migration-immutability.sh`, `lint-guard-contract.py`, `technical-ruling-gate.sh --branch ...`, markdownlint on plan and tasks.
- 6.3 One RED proof per Guard Contract guard (Guard 1 row 1, Guard 2 row 4), reverted.
- 6.4 PR body: `Closes #10633`, `Closes #10732`, `Closes #10713`, baselines, rehearsal notes, #10692 untouched.
- 6.5 Post-merge: confirm the `verify-migrations` conclusion is `success` (not `skipped`) with all three `verify/163` rows at `bad = 0`.
