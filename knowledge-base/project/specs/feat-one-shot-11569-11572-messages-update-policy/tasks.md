# Tasks: messages owner draft UPDATE policy and #11572 hygiene

Plan: `knowledge-base/project/plans/2026-10-30-fix-messages-update-policy-and-harness-hygiene-plan.md`
Branch: feat-one-shot-11569-11572-messages-update-policy. Draft PR: #11622. Closes #11569, Closes #11572 (separate lines in the PR body).

## Phase 0: Baseline (read-only)

- 0.1 Re-run dev and prd `pg_policies` + `has_column_privilege` reads for `public.messages`; add the `status = 'draft'` count by `source` (paste into the PR body).
- 0.2 Capture the pristine ledger-label lists of the 11211 and 11265 suites and the argv-bearer-sweep row count (`EXPECTED_TESTS=824`).
- 0.3 Confirm the next free migration ordinal against `origin/main` and open PRs (181 provisional; #11593 holds 179).

## Phase 1: Tests first for #11569 (RED)

- 1.1 `apps/web-platform/test/server/messages-owner-draft-update.tenant-isolation.test.ts` (dev DB, rolled back, message-level error assertions, positive controls, service-role re-reads).
- 1.2 `apps/web-platform/test/supabase-migrations/181-messages-owner-draft-update.test.ts` (thin: REVOKE before GRANT, no bare `auth.uid()`, exact two-column GRANT, down file, verify contract, anti-vacuity).
- 1.3 `apps/web-platform/test/api/dashboard/today/discard-route.test.ts` (200, zero rows 403, DB error 500, 401).
- 1.4 rls-fuzz: `targets.ts` `messages` target (updateCol `draft_preview`, draft-card seed), `rls-row-hijack.integration.test.ts` `HIJACK_TARGETS` entry (+ optional `hijackCol`/`hijackValue`), `table-grants.ts` OVERRIDES entry.

## Phase 2: Migration, verify, dev rehearsal

- 2.1 Re-check ordinals immediately before the first dev apply (final from then on); resolve 179 sequencing.
- 2.2 Extended writer census (`ON CONFLICT`, non-DEFINER functions, `.upsert(`, tenant clients); paste empty output in the PR body.
- 2.3 `181_messages_owner_draft_update.sql` and `.down.sql`.
- 2.4 `supabase/verify/181_messages_owner_draft_update.sql` (policy rows, column privileges from `pg_attribute`, `attacl` sweep, PUBLIC `aclexplode`) and the `verify/174` edit (remove UPDATE for `anon`/`authenticated` on `messages`).
- 2.5 Rolled-back dry-run on dev, then `run-migrations.sh` on dev, then `psql -f` both verify files; run test 1.1 RED -> GREEN.
- 2.6 ADR-303 Consequences bullet.

## Phase 3: Copy and client (#11572 items 7, 12)

- 3.1 Tests first in `today-card.click.test.tsx`: Edit-409 restored string, three DENY strings, one 403 row each for Discard, Edit and Dismiss; dashboard fetcher `cache: "no-store"` row.
- 3.2 Edit `today-card.tsx` (strings, delete the "Discard is not offered" comment, 403 branches) and `lib/messages/trust-tier-copy.ts`; edit `app/(dashboard)/dashboard/page.tsx` fetcher.
- 3.3 AC6 diff invariant (no structural change) and `tsc --noEmit`.

## Phase 4: Header-only edits (items 3, 5, 10)

- 4.1 11265 probe header: 60-day read measurement and trigger.
- 4.2 11211 probe header: Sentry environment split and triggers.
- 4.3 `docker-run-tuple.test.sh` header: why it does not use the shared lib; pointer to #11628.
- 4.4 AC9 comment-only diff check.

## Phase 5: Harness hygiene (items 8, 9, 11, 13)

- 5.1 Controls first in both probe suites (`mh_frag_unique` tokens, exact-mode `mh_caught`, `mh_selftest_caught`, `mh_floor` and `assert_fixture_dir` refusal rows).
- 5.2 Implement in `scripts/lib/mutation-harness.sh`; wire `mutate_run` and `mutate_helper`; disambiguate any pre-existing ambiguous fragment.
- 5.3 Raise `MIN_BATTERY` by the exact ledger-label diff in each suite.
- 5.4 `tests/scripts/test-argv-bearer-sweep.sh`: `exec < /dev/null`, one pinning row, before/after row diff with stdin closed, `EXPECTED_TESTS` to the measured count, AC10 open-stdin run.
- 5.5 Pre-push ratchets (plan Phase 5 step 5).

## Phase 6: Ship and prod verification

- 6.1 PR body: `Closes #11569` / `Closes #11572`, catalog reads, rollback SQL plus reverse registry edit, links #11628 #11629 #11630, author-only note, what the fix unblocks by source.
- 6.2 After merge: `migrate` and `verify-migrations` green; read-only prd catalog check (PM2); Sentry read (PM3).

## Phase 7: Tracking

- 7.1 Comment on #11572 with the disposition of each item and the closing PR (#11628, #11629, #11630 already filed).
