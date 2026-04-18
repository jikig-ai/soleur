# Tasks: bot-fixture + bot-signin hardening

Plan: [knowledge-base/project/plans/2026-04-18-fix-bot-fixture-hardening-plan.md](../../plans/2026-04-18-fix-bot-fixture-hardening-plan.md)

Branch: `feat-one-shot-bot-fixture-hardening`

Closes: `#2358`, `#2359`, `#2360`, `#2361`. Ref: `#2362`.

## Phase 0 — Guard top-level execution (prerequisite)

- [ ] **0.1** Wrap `bot-fixture.ts`'s bottom `process.argv[2]` dispatch block in
  `if (import.meta.main) { ... }`. Without this, importing the file from a unit test
  triggers `process.exit(2)` at module load. Canonical Bun pattern (verified against
  `/oven-sh/bun` docs).
- [ ] **0.2** Wrap `bot-signin.ts`'s trailing `await main();` call in
  `if (import.meta.main) { ... }`. Without this, importing `projectRef` /
  `cookieDomain` for unit tests attempts a live Supabase signin at module load.
- [ ] **0.3** Verify: `bun -e 'await import("./plugins/soleur/skills/ux-audit/scripts/bot-fixture.ts")'`
  exits 0 silently. Repeat for `bot-signin.ts`. Both must be silent (no stderr, no
  `process.exit(2)`, no network call) before Phase 2 or 3.2.5 can add `export`s.

## Phase 1 — Setup

- [ ] **1.1** Create migration `apps/web-platform/supabase/migrations/028_conversations_user_id_session_id_unique.sql`.
  - Partial unique index: `(user_id, session_id) WHERE session_id IS NOT NULL`.
  - Use `create unique index concurrently if not exists`.
  - Name: `uniq_conversations_user_id_session_id`.
  - PostgREST `on_conflict=user_id,session_id` resolves against a partial unique
    index with matching column list — verified, no live probe needed.

## Phase 2 — Core Implementation

### 2.1 Upsert conversations (#2358) — `bot-fixture.ts`

- [ ] **2.1.1 RED** Add a failing test in `bot-fixture.test.ts` asserting message
  count remains stable at 7 across two back-to-back seed runs (3 + 4 = 7 for the
  two FIXTURE_CONVERSATIONS). Current code would double to 14 after upsert swap
  without the DELETE-before-insert fix.
- [ ] **2.1.2 GREEN** Replace `findConversationId` + `insertConversation` with a
  single `upsertConversation` that POSTs to `/rest/v1/conversations?on_conflict=user_id,session_id`
  with `Prefer: return=representation,resolution=merge-duplicates`.
- [ ] **2.1.3 GREEN** Before `insertMessages(cid, ...)`, DELETE messages where
  `conversation_id=eq.<cid>` to keep reseed idempotent on message count.
- [ ] **2.1.4 GREEN** Add a runtime guard in `upsertConversation`: throw clearly if
  `sessionId` is empty or null (partial unique index excludes NULLs).
- [ ] **2.1.5** Remove `findConversationId` + `insertConversation` helpers — no
  callers should remain.
- [ ] **2.1.6** Verify: `grep -n 'findConversationId\|insertConversation' plugins/soleur/skills/ux-audit/scripts/bot-fixture.ts` returns zero hits.

### 2.2 bot-signin test gaps (#2359) — `bot-signin.ts` + test

- [ ] **2.2.1 RED** Add `describe("bot-signin pure helpers", ...)` with ~9 unit
  tests for `projectRef` (valid, path-tolerated, non-supabase host error, empty
  error) and `cookieDomain` (hostname, subdomain, localhost, invalid URL error).
- [ ] **2.2.2 GREEN** `export` `projectRef` and `cookieDomain` from `bot-signin.ts`
  (no behavior change).
- [ ] **2.2.3 RED** In the integration describe block, replace the
  `authCookie.value.length > 20` assertion with `JSON.parse(authCookie.value)` +
  `expect(typeof session.access_token).toBe("string")` (and length > 20),
  `typeof session.refresh_token === "string"`, `typeof session.expires_at === "number"`.
- [ ] **2.2.4 GREEN** Confirm tests pass against the current cookie-writer
  (`storageState.cookies[0].value = JSON.stringify(session)`); if a future
  @supabase/ssr bump adds a `base64-` prefix, this test will fail loudly.

### 2.3 reset auth-survival + DELETE guards (#2360) — `bot-fixture.ts` + test

- [ ] **2.3.1 GREEN** Extract `sbDelete(path: string): Promise<void>` helper at
  file top near `sbFetch`: throws on `!res.ok` with `status + slice(0, 200)` of body.
- [ ] **2.3.2 GREEN** Replace both raw DELETE calls in `reset()` (messages loop,
  conversations delete) with `await sbDelete(...)`.
- [ ] **2.3.3 RED** In `bot-fixture.test.ts` "reset clears seeded conversations
  but leaves auth user" test, add after `expect(r.status).toBe(0)`:
  `expect(await getBotUserId()).toBe(botId)` — asserts the auth user survived.
- [ ] **2.3.4 GREEN** Test passes against current `reset()` behavior (it never
  touches `/auth/v1/admin/users/:id`); the assertion locks the invariant against
  future regressions.
- [ ] **2.3.5 (scope-in default)** Export `sbDelete` + `sbFetch` from
  `bot-fixture.ts` and add a unit-level test file
  `plugins/soleur/test/ux-audit/bot-fixture-helpers.test.ts` that mocks `fetch`
  to return `{ ok: false, status: 409, text: () => "conflict" }` and expects
  `sbDelete` to throw. Only skip if the export ceremony conflicts with the
  one-file script ethos — default is scope-in.

### 2.4 CI concurrency guard (#2361) — `scheduled-ux-audit.yml`

- [ ] **2.4.1** Add job-level `concurrency: { group: bot-fixture-shared-state,
  cancel-in-progress: false }` on the `ux-audit:` job in
  `.github/workflows/scheduled-ux-audit.yml`.
- [ ] **2.4.2** Add a 4-line inline comment above the workflow-level `concurrency:`
  block documenting the shared-name convention: "Any job that invokes
  `bot-fixture.ts seed` or `reset` must belong to `concurrency.group:
  bot-fixture-shared-state` with `cancel-in-progress: false`."
- [ ] **2.4.3** Do NOT change the workflow-level group (`schedule-ux-audit`); it
  stacks with the job-level group and is correct as-is.

## Phase 3 — Testing

- [ ] **3.1 Local run — integration.** `cd .worktrees/feat-one-shot-bot-fixture-hardening
  && doppler run -p soleur -c prd_scheduled -- bun test
  plugins/soleur/test/ux-audit/bot-fixture.test.ts
  plugins/soleur/test/ux-audit/bot-signin.test.ts`. All integration tests must
  pass. Exercise upsert path by running `bun plugins/soleur/skills/ux-audit/scripts/bot-fixture.ts seed`
  twice in a row under the same doppler context — second run must return the same
  conversation ids and keep message count at 7.
- [ ] **3.2 Local run — unit helpers.** Same command without doppler should still
  run the Phase 2 pure-helper tests (no creds gate on that describe block).
- [ ] **3.3 Plugin suite.** `npm test` at the repo root — verify nothing else
  broke.
- [ ] **3.4 Markdownlint.** `npx markdownlint-cli2 --fix plugins/soleur/skills/ux-audit/scripts/bot-fixture.ts
  plugins/soleur/test/ux-audit/bot-fixture.test.ts
  plugins/soleur/test/ux-audit/bot-signin.test.ts` — no-op for .ts; run against
  any .md docs you touch (none expected for this PR).

## Phase 4 — Ship

- [ ] **4.1** `git add` only the four edited files, the new migration, and the
  new helper test file (if Phase 2.3.5 was scope-in). Avoid repo-wide blast.
- [ ] **4.2** Commit with `skill: soleur:compound` before commit (workflow gate).
- [ ] **4.3** Push and open PR. PR title: `fix(bot-fixture): upsert + DELETE
  guards + cookie-shape tests + CI concurrency (drains #2358 + #2359 + #2360 + #2361)`.
  PR body must start with `Closes #2358`, `Closes #2359`, `Closes #2360`,
  `Closes #2361`, and reference `Ref #2362`.
- [ ] **4.4** Label: `semver:patch` (bug-fix class).
- [ ] **4.5** After merge, apply migration `028_*.sql` to prod Supabase and
  verify the index: `select indexname from pg_indexes where tablename='conversations'
  and indexname='uniq_conversations_user_id_session_id'`. Runbook:
  `knowledge-base/engineering/ops/runbooks/supabase-migrations.md`.
- [ ] **4.6** Trigger a manual `gh workflow run scheduled-ux-audit.yml` dry-run to
  verify the upsert path + concurrency guard in situ.

## Acceptance Criteria (summary)

See the plan's **Acceptance Criteria** section for the detailed pre-merge and
post-merge checklists.
