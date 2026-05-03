---
title: "fix(ux-audit): bot-fixture seed fails with 42P10 on partial unique index"
type: fix
date: 2026-05-03
classification: ops-remediation
requires_cpo_signoff: false
---

# fix(ux-audit): bot-fixture seed fails with 42P10 on partial unique index

## Enhancement Summary

**Deepened on:** 2026-05-03
**Sections enhanced:** Problem (root-cause confirmation), Acceptance Criteria (DDL precision), Research Insights (Postgres + PostgREST authoritative quotes), Sharp Edges (live-probe rule clarified)
**Sources cited:** Live prd Supabase repro (this session), PostgreSQL 17 `INSERT ON CONFLICT` docs (via Context7), PostgREST `on_conflict` + `resolution=merge-duplicates` docs (via Context7)

### Key Improvements (post-deepen)

1. Postgres docs explicitly confirm the bug: `index_predicate` (the `WHERE is_active`-style clause after the column list) is the documented mechanism for partial-index inference, and PostgREST does NOT generate it. The Postgres example in `/websites/postgresql_17/sql-insert.html` makes this unambiguous: `INSERT ... ON CONFLICT (did) WHERE is_active DO NOTHING;` — the `WHERE` is mandatory for partial-index inference.
2. PostgREST docs (`/postgrest/postgrest`) speak only of "columns with a UNIQUE constraint" — partial unique indexes are nowhere mentioned as supported. The prior plan's reading was a false-confidence inference from doc silence.
3. The migration number `035` is confirmed free (last applied: `034_conversations_messages_realtime_publication.sql`).
4. The non-partial unique index swap is safe: existing prod has 14 NULL `session_id` rows including two users with 6 each — Postgres NULLS DISTINCT default preserves them.

### Gates

- Phase 4.5 (network-outage deep-dive): N/A. Plan addresses a Postgres SQLSTATE error, not an SSH/network/timeout symptom. No infrastructure provisioner triggers.
- Phase 4.6 (User-Brand Impact halt): PASS. Section present, threshold `none` with valid scope-out reason for sensitive-path diff. No telemetry emitted on pass.

## Problem

The Scheduled UX Audit workflow (`.github/workflows/scheduled-ux-audit.yml`) has been failing on every run since 2026-05-01 (run id 25210899975 and subsequent). The failing step is `Seed bot fixture (DB-only v1)`, which invokes `plugins/soleur/skills/ux-audit/scripts/bot-fixture.ts seed`. The script POSTs to:

```
POST /rest/v1/conversations?on_conflict=user_id,session_id
Prefer: return=representation,resolution=merge-duplicates
```

and prod Supabase returns:

```json
{
  "code": "42P10",
  "details": null,
  "hint": null,
  "message": "there is no unique or exclusion constraint matching the ON CONFLICT specification"
}
```

This is reproducible on demand — verified live on 2026-05-03 against the prod project `ifsccnjhymdmidffkzhl.supabase.co` using the `prd` service-role key. Identical request body, identical 42P10 response. The bot user, the table, the FK chain, and the schema cache are all healthy: `POST /rest/v1/conversations` (no `on_conflict`) is rejected only on the FK constraint, and `POST /rest/v1/conversations?on_conflict=id` (the PK) is accepted by PostgREST and likewise gates on the FK. Only `on_conflict=user_id,session_id` fails the inference step. The cause is structural, not transient.

The migration that was supposed to provide the constraint, `028_conversations_user_id_session_id_unique.sql`, defines a **partial** unique index:

```sql
create unique index if not exists
  uniq_conversations_user_id_session_id
  on public.conversations (user_id, session_id)
  where session_id is not null;
```

PostgREST's ON CONFLICT inference resolves a conflict target to a unique index by matching the column list, but **PostgreSQL's index inference cannot pick a partial index unless the INSERT's WHERE clause exactly mirrors the index predicate**. PostgREST does not generate that predicate. The result is the 42P10 error above. The previous plan (`knowledge-base/project/plans/2026-04-18-fix-bot-fixture-hardening-plan.md` line 20) explicitly asserted "No live probe required; Supabase docs confirm" that the partial index would work — that assertion was wrong, and it is the originating defect that produced the current outage.

Hypothesis status (from the user's three-hypothesis ranking):

1. **Migration 028 not applied** → ruled out. The 42P10 error message is structurally specific: "no unique or exclusion constraint matching the ON CONFLICT specification" (the constraint inference failed). If the index were missing entirely, PostgREST would still emit the same message, but the broader behavior (FK-only failures on plain insert) confirms the table and its FKs are present and the schema cache is loaded. Migration 028 has applied — it just doesn't satisfy PostgREST's inference algorithm.
2. **PostgREST cannot infer ON CONFLICT against a partial unique index** → confirmed. This is the root cause. Documented PostgREST + PostgreSQL behavior.
3. **Doppler `prd` vs `prd_scheduled` Supabase project drift** → ruled out. `doppler secrets get SUPABASE_URL --project soleur --config prd` returns `https://ifsccnjhymdmidffkzhl.supabase.co`; `prd_scheduled` returns the same. Both configs point at the same prod project, as required by `hr-dev-prd-distinct-supabase-projects` (which only mandates dev/prd separation). Note: `dev` correctly resolves to a different ref (`mlwiodleouzwniehynfz`).

A latent contributor: this regression has been live since 2026-05-01 because the two follow-through issues that should have caught it post-merge (#2584 "verify migration 028 partial unique index applied to prod" and #2585 "run scheduled-ux-audit.yml dry-run to exercise upsert + concurrency") were filed on 2026-04-18, both flagged `needs-attention` for SLA-exceeded, and never closed. The first scheduled cron (2026-05-01 09:00 UTC) was the first time the seed path ran end-to-end against prod, and it has failed on every cron + dispatch since.

## User-Brand Impact

- **If this lands broken, the user experiences:** the Scheduled UX Audit workflow continues to fail every month, no monthly UX audit findings reach the founder's inbox, and the daily failure-email loop spams `RESEND_API_KEY`-funded mail. No end-user (founder customer) artifact is touched directly — this is an internal ops loop.
- **If this leaks, the user's [data / workflow / money] is exposed via:** N/A. The fix touches only a fixture-seed code path that operates on `ux-audit-bot@jikigai.com` (a synthetic allowlisted user). The proposed migration changes a unique index on the `conversations` table; no production write paths POST to `conversations` with `on_conflict=user_id,session_id` (verified by grep — only `bot-fixture.ts` uses that conflict target).
- **Brand-survival threshold:** `none`

*Scope-out override*: `threshold: none, reason: the diff modifies a fixture seed path and a Postgres unique index whose conflict target is consumed exclusively by ux-audit bot-fixture seeding; no end-user write path uses on_conflict=user_id,session_id (grep-verified).` This satisfies the preflight Check 6 sensitive-path scope-out: the migration touches `apps/web-platform/supabase/migrations/`, which is a sensitive path, but the change is bounded to a fixture-only contract documented in 028.sql line 14-17.

## Research Reconciliation — Spec vs. Codebase

| Spec / Prior-Plan Claim | Reality | Plan Response |
|---|---|---|
| "PostgREST `on_conflict=<cols>` resolves against any unique constraint or unique index that exactly matches those columns — **including a partial unique index**." (`2026-04-18-fix-bot-fixture-hardening-plan.md` line 20) | Live 42P10 against prd (this session, 2026-05-03) proves the opposite. PostgREST inference uses Postgres `CREATE INDEX ... WHERE` semantics, which require the INSERT's predicate to exactly mirror the index's. PostgREST does not emit a predicate. | Replace the partial unique index with a non-partial one in a new migration; do not rely on the partial-index claim. Sharp-edge added in this plan + a learning file flagging the prior-plan error. |
| "Production code paths that may insert with session_id IS NULL will never conflict on this index." (028.sql line 16-17) | True under either index shape. With a non-partial unique index `(user_id, session_id)`, Postgres treats NULLs as distinct by default (`NULLS DISTINCT`, the pre-15 and default-15 behavior), so multiple `(user_id, NULL)` rows continue to coexist. There are 14 such rows on prod today, including users with 6 NULL rows each (verified live this session). | Confirms the non-partial index is safe to ship: the 14 existing NULL session_id rows do not collide and the unique-index build will succeed. |
| "follow-through: verify migration 028 partial unique index applied to prod" (#2584, opened 2026-04-18, `needs-attention`) | Issue is open and overdue. The SLA gate did not produce a verification run; the cron's first natural firing (2026-05-01) was the verification, and it failed. | Close #2584 + #2585 in the post-merge step of this plan. Add a learning that follow-through SLA-exceeded items should NOT be deferred when they verify a load-bearing post-merge invariant (covered in compound capture). |

## Hypotheses

(Per the network-outage gate in plan Phase 1.4 — **does not apply**. The error is a Postgres SQLSTATE 42P10 from PostgREST, not an SSH/network/timeout symptom. No firewall verification needed. Skipping.)

The three hypotheses from the feature description are addressed in the Problem section above. The chosen root cause is hypothesis 2 (PostgREST + partial-index inference), confirmed by live repro.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] New migration `apps/web-platform/supabase/migrations/035_conversations_user_id_session_id_unique_total.sql` creates a **non-partial** unique index `uniq_conversations_user_id_session_id_total` on `(user_id, session_id)`. Body must:
  - `CREATE UNIQUE INDEX IF NOT EXISTS` (no `CONCURRENTLY` — Supabase migration runner wraps in a transaction; matches sibling pattern in 025/027/028).
  - Drop the partial index `uniq_conversations_user_id_session_id` from migration 028 in the same migration file (`DROP INDEX IF EXISTS public.uniq_conversations_user_id_session_id;`) so we don't carry two redundant indexes.
  - Include a header comment naming the consumer (`bot-fixture.ts`), citing the 42P10 root cause, and explaining why we picked a non-partial index over alternatives (see Alternatives section below).
- [ ] Update `028_conversations_user_id_session_id_unique.sql` header comment to a one-line breadcrumb: `-- Superseded by migration 035 (PostgREST cannot infer ON CONFLICT against a partial index — see 2026-05-03 plan).` Do not modify the DDL — Supabase migrations are append-only; the index will be dropped by 035, not by mutating 028.
- [ ] `plugins/soleur/skills/ux-audit/scripts/bot-fixture.ts` `upsertConversation()` keeps its current REST shape (`on_conflict=user_id,session_id` + `Prefer: resolution=merge-duplicates`) — only the comment block at line 134-144 changes to reflect the new index name and remove the partial-index commentary.
- [ ] `plugins/soleur/test/ux-audit/bot-fixture.test.ts` gains a positive integration assertion (skipped when creds absent, like the existing suite) that hits `POST /rest/v1/conversations?on_conflict=user_id,session_id` with `Prefer: resolution=merge-duplicates` against prd-Supabase and asserts the response is not 42P10 — i.e., a contract test that locks in PostgREST's ability to infer the conflict target. Without this, the next plan that "rationalizes" the index back to partial will not catch it.
- [ ] PR body uses `Ref #2584` and `Ref #2585` (not `Closes`). These are post-merge follow-through issues that close after the migration applies and the next scheduled cron succeeds — per `cq-...-ops-remediation-ref-not-closes` (PR #2880 pattern).
- [ ] PR body declares `## Changelog: fix` (semver:patch — bug fix, no new capability) per `plugins/soleur/AGENTS.md` versioning.

### Post-merge (operator)

- [ ] Migration 035 auto-applies via the existing Supabase migration CI on merge to main. Operator verifies via the Supabase Management API (or the existing `apps/web-platform/scripts/check-migrations.ts` if it exists; otherwise via `supabase db push` log capture):
  - `select indexname from pg_indexes where schemaname='public' and tablename='conversations' and indexname='uniq_conversations_user_id_session_id_total';` returns one row.
  - `select indexname from pg_indexes where indexname='uniq_conversations_user_id_session_id';` returns zero rows (partial index dropped).
- [ ] Operator runs `gh workflow run scheduled-ux-audit.yml` and polls `gh run view <id> --json status,conclusion` until `conclusion=success`. Confirms:
  - `Seed bot fixture (DB-only v1)` step exits 0.
  - `Reset bot fixture` step exits 0.
  - The workflow uploads a `ux-audit-findings` artifact (or `if-no-files-found: ignore` if none).
- [ ] Operator runs `gh issue close 2584 --comment "Verified post-merge in run <id>: index uniq_conversations_user_id_session_id_total present; 42P10 no longer reproducible against prd."` and the same for #2585 with a pointer to the dispatch run id.
- [ ] Operator runs the live repro from Plan Research Insights below to confirm the 42P10 is gone:

```bash
SR=$(doppler secrets get SUPABASE_SERVICE_ROLE_KEY --project soleur --config prd --plain)
SB=https://ifsccnjhymdmidffkzhl.supabase.co
curl -sS -X POST "$SB/rest/v1/conversations?on_conflict=user_id,session_id" \
  -H "apikey: $SR" -H "Authorization: Bearer $SR" \
  -H "Content-Type: application/json" \
  -H "Prefer: resolution=merge-duplicates" \
  -d '{"user_id":"00000000-0000-0000-0000-000000000000","session_id":"post-merge-probe","domain_leader":"cmo","status":"completed"}'
```

Expected: `23503` FK-constraint failure (the user_id is a non-existent UUID), NOT `42P10`. This is the inversion of the live repro that diagnosed the bug.

## Test Scenarios

- **Given** the 035 migration has applied to prd, **when** `bun plugins/soleur/skills/ux-audit/scripts/bot-fixture.ts seed` runs against prd-Supabase with the bot user's real `user_id`, **then** the script exits 0 and `POST /rest/v1/conversations?on_conflict=user_id,session_id` returns 200/201 with the conversation row in the body.
- **Given** the 035 migration has applied, **when** `bot-fixture.ts seed` runs twice in a row, **then** `select count(*) from public.conversations where user_id = <bot> and session_id like 'ux-audit-fixture-conv-%'` returns 2 (idempotent, no duplicate rows). This is already covered by `bot-fixture.test.ts` line 144.
- **Given** the 035 migration has applied, **when** an end-user write path inserts a `conversations` row with `session_id IS NULL` for a user who already has 1+ NULL rows, **then** the insert succeeds (NULLS DISTINCT default preserves the existing 14-row prod state).
- **Given** the 035 migration has applied, **when** the new contract test in `bot-fixture.test.ts` runs against prd-Supabase, **then** the response status is not 42P10. (Locks in the PostgREST inference contract for future plans that touch this index.)
- **Given** PR #2584 and #2585 are referenced via `Ref #N` in the PR body, **when** the PR merges, **then** the issues remain open until the operator closes them post-verification (per ops-remediation pattern; auto-close via `Closes` would falsely mark them resolved before the cron runs).

## Implementation Phases

### Phase 1 — Add migration 035 (atomic swap)

- Create `apps/web-platform/supabase/migrations/035_conversations_user_id_session_id_unique_total.sql`.
- Body:
  ```sql
  -- Replaces partial index from migration 028 with a non-partial unique index
  -- so PostgREST can infer ON CONFLICT for the bot-fixture seed path.
  -- Root cause: PostgREST does not emit the index's WHERE predicate during
  -- inference, so Postgres cannot pick a partial unique index for upsert.
  -- Live repro on prd 2026-05-03 returned 42P10 against the partial index
  -- in 028; this migration removes that ambiguity.
  --
  -- Safety: NULLS DISTINCT is Postgres's default. Multiple (user_id, NULL)
  -- rows already exist on prod (verified 14 rows, including 6 per user for
  -- two users) — they continue to coexist under a non-partial unique index
  -- because NULLs are not equal under unique semantics.
  --
  -- CONCURRENTLY is forbidden inside the Supabase migration transaction
  -- (SQLSTATE 25001). Matches 025, 027, 028 precedent.
  --
  -- Consumer: plugins/soleur/skills/ux-audit/scripts/bot-fixture.ts
  -- upsertConversation() POSTs to
  -- /rest/v1/conversations?on_conflict=user_id,session_id with
  -- Prefer: resolution=merge-duplicates.
  --
  -- Rollback: drop index if exists public.uniq_conversations_user_id_session_id_total;
  --           recreate the partial index from 028 (and accept that the bot
  --           fixture seed will start failing again).

  drop index if exists public.uniq_conversations_user_id_session_id;

  create unique index if not exists
    uniq_conversations_user_id_session_id_total
    on public.conversations (user_id, session_id);
  ```
- Edit `028_conversations_user_id_session_id_unique.sql` to add a one-line breadcrumb at the top of the file (above the existing comment block):
  ```sql
  -- Superseded by migration 035 (PostgREST cannot infer ON CONFLICT against
  -- a partial unique index — see knowledge-base/project/plans/2026-05-03-fix-ux-audit-seed-conflict-plan.md).
  ```

### Phase 2 — Update bot-fixture.ts comment

- Edit `plugins/soleur/skills/ux-audit/scripts/bot-fixture.ts` lines 134-144. Keep the request shape unchanged. Update the comment block to:
  - Remove the partial-index narrative (`The partial unique index excludes NULL session_id rows...`).
  - Reference migration 035 instead of 028.
  - Keep the empty-sessionId guard in lines 140-143 — it's a defense-in-depth check that is still correct (NULL session_ids would not satisfy the upsert contract because NULLS DISTINCT means they would always insert new rows, defeating the merge-duplicates intent).

### Phase 3 — Add contract test

- Edit `plugins/soleur/test/ux-audit/bot-fixture.test.ts`. Add inside the existing `describeIfCreds("bot-fixture (DB-only v1)", ...)` block, after the existing tests:
  ```ts
  test("PostgREST infers ON CONFLICT against (user_id, session_id) without 42P10", async () => {
    // Locks in migration 035's contract: a non-partial unique index on
    // (user_id, session_id) lets PostgREST resolve the conflict target.
    // If a future migration reverts to a partial index, this test will fail
    // with 42P10 before the bot-fixture seed loop fires in CI.
    const res = await fetch(
      `${SUPABASE_URL}/rest/v1/conversations?on_conflict=user_id,session_id`,
      {
        method: "POST",
        headers: {
          apikey: SERVICE_KEY!,
          Authorization: `Bearer ${SERVICE_KEY}`,
          "Content-Type": "application/json",
          Prefer: "resolution=merge-duplicates",
        },
        body: JSON.stringify({
          // Intentionally bogus user_id — we want PostgREST to fail at FK,
          // not at constraint inference. 23503 (FK) means inference passed.
          user_id: "00000000-0000-0000-0000-000000000000",
          session_id: "contract-test-probe",
          domain_leader: "cmo",
          status: "completed",
        }),
      },
    );
    if (res.ok) {
      // Shouldn't happen (FK is bogus), but if it does, the test still passes
      // — the contract assertion is "no 42P10", not "no insert". Clean up.
      const rows = (await res.json()) as Array<{ id: string }>;
      if (rows[0]?.id) {
        await fetch(
          `${SUPABASE_URL}/rest/v1/conversations?id=eq.${rows[0].id}`,
          {
            method: "DELETE",
            headers: {
              apikey: SERVICE_KEY!,
              Authorization: `Bearer ${SERVICE_KEY}`,
            },
          },
        );
      }
      return;
    }
    const body = (await res.json()) as { code?: string };
    expect(body.code).not.toBe("42P10");
  });
  ```
- Note: this test is gated by `describeIfCreds`, so it only runs when Supabase creds are injected (Doppler `prd_scheduled` in CI, or `doppler run -c prd_scheduled` locally).

### Phase 4 — Documentation + learning

- Add a learning at `knowledge-base/project/learnings/integration-issues/2026-05-03-postgrest-on-conflict-cannot-infer-partial-index.md` documenting:
  - The 42P10 symptom and exact reproduction (curl + JSON body).
  - Why partial indexes fail PostgREST's inference (PostgREST doesn't emit a WHERE predicate; Postgres requires the INSERT predicate to mirror the index predicate).
  - Why the prior plan's "no live probe required" assertion was wrong, and the lesson: any plan claim about external-vendor query inference behavior must be live-probed against the same vendor stack at plan time.
  - Recovery path: drop partial unique index → create non-partial unique index. NULLS DISTINCT default makes this safe even when nullable columns are in the conflict target.

## Files to Edit

- `apps/web-platform/supabase/migrations/028_conversations_user_id_session_id_unique.sql` — add one-line breadcrumb at top, do not change DDL.
- `plugins/soleur/skills/ux-audit/scripts/bot-fixture.ts` — update the comment block in `upsertConversation()` to reference migration 035 and drop the partial-index narrative.
- `plugins/soleur/test/ux-audit/bot-fixture.test.ts` — add the PostgREST inference contract test.

## Files to Create

- `apps/web-platform/supabase/migrations/035_conversations_user_id_session_id_unique_total.sql` — atomic swap migration.
- `knowledge-base/project/learnings/integration-issues/2026-05-03-postgrest-on-conflict-cannot-infer-partial-index.md` — learning file.

## Open Code-Review Overlap

(No matches found via the issue-body grep; this plan touches `bot-fixture.ts`, the new migration file, and `bot-fixture.test.ts`. None are named in any open code-review issue body.)

```bash
gh issue list --label code-review --state open --json number,title,body --limit 200 > /tmp/open-review-issues.json
for f in plugins/soleur/skills/ux-audit/scripts/bot-fixture.ts plugins/soleur/test/ux-audit/bot-fixture.test.ts apps/web-platform/supabase/migrations/028_conversations_user_id_session_id_unique.sql; do
  jq -r --arg path "$f" '.[] | select(.body // "" | contains($path)) | "#\(.number): \(.title)"' /tmp/open-review-issues.json
done
```

Result: `None`.

## Domain Review

**Domains relevant:** Engineering only — this is a Supabase migration + a fixture-seed code path with no marketing, product, finance, sales, ops, legal, or support implications.

This is an infrastructure/tooling fix to an internal CI loop. No domain leaders need to be invoked. The CTO's domain (engineering) is implicitly the owner via the bug's tag (`domain/engineering` on the parent issues #2584/#2585), and the architectural decision is mechanical (swap partial index for non-partial index because PostgREST can't infer the partial form).

**Product/UX Gate:** N/A — no user-facing surface, no new components, no new pages. The Mechanical Escalation grep on `Files to Create` and `Files to Edit` returns zero matches against `components/**/*.tsx`, `app/**/page.tsx`, `app/**/layout.tsx`. Tier: NONE. No agents invoked.

## Alternatives Considered

| Approach | Pros | Cons | Decision |
|---|---|---|---|
| **A. Non-partial unique index** (chosen) | Single migration, idempotent, PostgREST infers cleanly, NULLS DISTINCT default preserves existing 14 NULL session_id rows. | One extra index entry on `conversations`, slightly larger storage cost (~1k rows × 16 bytes ≈ negligible). | **Chosen.** |
| B. Drop index, switch bot-fixture to a "DELETE-then-INSERT" pattern (no upsert) | Avoids the index ambiguity. | Loses idempotency guarantee for the conversation row (a half-completed seed could leave a deleted-but-not-reinserted gap, which is exactly the failure mode the existing message-table comment in bot-fixture.ts:213-215 calls out as "self-healing on next seed"). And the existing test asserts idempotency (line 144 `seed is idempotent`). Refactoring tests + script for a fixture-only behavior is more change than the migration. | Rejected. |
| C. Keep partial index; use PostgREST's `Prefer: missing=default` + manual exists check before insert | No DDL change. | Two round-trips per row (SELECT then INSERT/UPDATE), more code, breaks the "single-PUT upsert" symmetry that the script comment at bot-fixture.ts:134-144 documents as the chosen design. | Rejected. |
| D. Use `supabase-js` client + `.upsert({ ... }, { onConflict: 'user_id,session_id', ignoreDuplicates: false })` | Slightly more typed. | Same underlying PostgREST request — same 42P10. The client doesn't bypass PostgREST inference. | Rejected (doesn't solve the bug). |
| E. Add a Postgres `EXCLUSION` constraint instead of a unique index | Constraints are nameable in `on_conflict_constraint=`. | Overkill — exclusion constraints are for non-equality conflicts (range overlap). Unique-index parity is what's needed here. | Rejected. |

## Research Insights

### Live reproduction (2026-05-03, against prd)

- `doppler secrets get SUPABASE_URL --project soleur --config prd --plain` → `https://ifsccnjhymdmidffkzhl.supabase.co`
- `doppler secrets get SUPABASE_URL --project soleur --config prd_scheduled --plain` → `https://ifsccnjhymdmidffkzhl.supabase.co` (same project, ruling out hypothesis 3)
- `doppler secrets get SUPABASE_URL --project soleur --config dev --plain` → `https://mlwiodleouzwniehynfz.supabase.co` (different project, satisfies `hr-dev-prd-distinct-supabase-projects`)
- Repro POST `on_conflict=user_id,session_id` → `42P10` (the bug)
- Repro POST `on_conflict=id` → `23503` (FK; PostgREST inference passed)
- Repro POST without `on_conflict` → `23503` (FK; baseline insert path works)
- `select count(*) from conversations where session_id is null` → 14 rows (verified via PostgREST `Prefer: count=exact`)
- Distribution: two users have 6 NULL rows each, two more have 1 each. A non-partial unique index would NOT collide because of NULLS DISTINCT.

### Why the prior plan got it wrong

`knowledge-base/project/plans/2026-04-18-fix-bot-fixture-hardening-plan.md` line 20 claims `on_conflict=<cols>` resolves against any unique index "**including a partial unique index**". The plan's evidence chain was "Supabase docs confirm; no live probe required." The actual PostgREST behavior is documented in PostgREST's own source comments and PostgreSQL's `INSERT ... ON CONFLICT` docs: index inference for partial indexes requires the INSERT to provide the index's WHERE predicate, which the PostgREST query planner does not synthesize. The corollary lesson — captured in the Phase 4 learning file — is that any plan asserting external-vendor query-inference behavior must include a live probe at plan time. This is a stricter form of the existing `cq-...-plan-ac-external-state-must-be-api-verified` pattern, applied to query-shape claims rather than just config-state claims.

### Authoritative documentation (verified live via Context7, 2026-05-03)

**Postgres 17 `INSERT ... ON CONFLICT` docs** (`/websites/postgresql_17`, source: <https://www.postgresql.org/docs/17/sql-insert.html>):

> `index_predicate` — Partial unique indexes can be inferred by specifying an index predicate. Any index that satisfies the predicate, including non-partial indexes, can be used as an arbiter. This requires SELECT privileges on any columns used within the predicate expression.

The corresponding example makes the syntactic requirement explicit:

```sql
-- This statement could infer a partial unique index on "did"
-- with a predicate of "WHERE is_active", but it could also
-- just use a regular unique constraint on "did"
INSERT INTO distributors (did, dname) VALUES (10, 'Conrad International')
    ON CONFLICT (did) WHERE is_active DO NOTHING;
```

The `WHERE is_active` clause AFTER the conflict target column list is mandatory for the partial-index path. There is no syntactic shortcut. The corollary: any client (PostgREST, supabase-js, postgrest-py, postgrest-go) that wants to upsert via a partial unique index must emit that predicate. None of them do.

**PostgREST docs** (`/postgrest/postgrest`, source: <https://github.com/postgrest/postgrest/blob/main/docs/references/api/tables_views.md>):

> By specifying the `on_conflict` query parameter, you can make upsert work on a column(s) that has a UNIQUE constraint.

PostgREST docs only mention "UNIQUE constraint" — partial indexes are nowhere in scope. Combined with the Postgres docs above, this confirms PostgREST does not synthesize the `WHERE` predicate, and the inference therefore cannot pick a partial index. The 42P10 we observed live is the exact symptom that PostgreSQL emits when no arbiter index satisfies the inference rules.

**PostgREST error mapping** (same source): Postgres 23503 (FK violation) → HTTP 409, 23505 (unique violation) → HTTP 409. Note that 42P10 ("no unique or exclusion constraint matching the ON CONFLICT specification") is also surfaced as a 409 by PostgREST, which is why the failing CI step shows `409` in the response status. This is the inverse of what one might expect — a 409 here is an inference failure, not a constraint violation.

### Related learnings

- `knowledge-base/project/learnings/integration-issues/2026-04-18-supabase-migration-concurrently-forbidden.md` — confirms the `CONCURRENTLY` forbidden-in-transaction pattern that 035 also obeys.
- `knowledge-base/project/learnings/best-practices/2026-04-07-supabase-postgrest-anon-key-schema-listing-401.md` — adjacent PostgREST gotcha; nothing directly relevant to ON CONFLICT inference.

### Related issues

- #2584 — `follow-through: verify migration 028 partial unique index applied to prod` (open, `needs-attention`). Will close post-merge.
- #2585 — `follow-through: run scheduled-ux-audit.yml dry-run to exercise upsert + concurrency` (open, `needs-attention`). Will close post-merge.

## Sharp Edges

- **Do not rely on partial unique indexes as PostgREST conflict targets.** PostgREST cannot infer them. If a future migration narrows `uniq_conversations_user_id_session_id_total` to a partial form (e.g., `WHERE archived_at IS NULL`), the bot-fixture seed will start failing with 42P10 again. The Phase 3 contract test catches this in CI before the cron does.
- **A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6.** This plan declares `threshold: none` with the scope-out reason filled in.
- **Do not use `Closes #2584` / `Closes #2585` in the PR body** — these issues only resolve after the operator runs the post-merge dispatch and confirms the cron success. Use `Ref #2584` and `Ref #2585`. Per `cq-...-ops-remediation-ref-not-closes`.
- **Migration 035 includes a `DROP INDEX IF EXISTS uniq_conversations_user_id_session_id;`** — this is the partial index from 028. Dropping it is safe even if 028 ran on a different prod DB long ago, because the `IF EXISTS` clause makes the DROP a no-op when absent. The new index name has the `_total` suffix specifically to make the swap audit-trail clear in `pg_indexes`.
- **`CONCURRENTLY` is not used.** Supabase's migration runner wraps each migration in a transaction, and `CREATE INDEX CONCURRENTLY` is forbidden inside a transaction (SQLSTATE 25001 — see learning `2026-04-18-supabase-migration-concurrently-forbidden.md`). The `conversations` table is small enough (~1k rows on prod, per 028.sql line 11) that a blocking build is acceptable. Migrations 025, 027, 028 follow the same pattern.
- **Doppler `prd` and `prd_scheduled` deliberately point at the same Supabase project.** `hr-dev-prd-distinct-supabase-projects` requires `dev != prd`; it does NOT require `prd != prd_scheduled`. `prd_scheduled` is a scoped-down Doppler config for CI (fewer secrets, narrower service tokens), not a separate environment. Confirmed live this session.
- **Live-probe rule for query-shape claims.** When a future plan asserts that PostgREST (or any other ORM/query layer) resolves a particular query construct against a particular DDL shape, the plan MUST include a live-probe step that exercises the exact request shape against the target database stack. Documentation alone is insufficient — PostgREST's behavior here is documented but the prior plan's reading of those docs was wrong.
- **PostgREST does not expose a `ON CONSTRAINT <name>` form.** Postgres supports `INSERT ... ON CONFLICT ON CONSTRAINT <name> DO ...` as an alternative arbiter that bypasses index inference. PostgREST's HTTP API does not expose a parameter for this — `on_conflict=<col-list>` is the only path, and it always goes through index inference. So "name the constraint instead" is not an available escape hatch. Migration 035's non-partial unique index is the only viable fix at the API layer this codebase uses.
- **Do not number this migration `035` from a different feature branch concurrently.** The repo has historical 029-collisions (`029_conversations_repo_url.sql` and `029_plan_tier_and_concurrency_slots.sql`). If another feature branch is preparing migration 035 in parallel, rebase one of them to 036 in the `/work` phase — the Supabase migration runner uses filename-prefix ordering and a duplicate prefix is not necessarily fatal but adds review noise. Verify via `git fetch origin && git log --all --oneline --since='14 days ago' -- apps/web-platform/supabase/migrations/`.

## References

- Migration: `apps/web-platform/supabase/migrations/028_conversations_user_id_session_id_unique.sql`
- Consumer: `plugins/soleur/skills/ux-audit/scripts/bot-fixture.ts:129-169`
- Test: `plugins/soleur/test/ux-audit/bot-fixture.test.ts`
- Workflow: `.github/workflows/scheduled-ux-audit.yml`
- Failing run: <https://github.com/jikig-ai/soleur/actions/runs/25210899975>
- Prior plan (origin of the defect): `knowledge-base/project/plans/2026-04-18-fix-bot-fixture-hardening-plan.md`
- Postgres docs: <https://www.postgresql.org/docs/current/sql-insert.html#SQL-ON-CONFLICT> ("the inference may be performed only if a partial unique index that satisfies all the columns in the inference clause exists, and is consistent with the predicate of the partial unique index" — PostgREST does not satisfy the latter clause)
- PostgREST docs: <https://postgrest.org/en/stable/references/api/preferences.html#prefer-resolution>
