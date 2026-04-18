# Plan: bot-fixture + bot-signin hardening (drains #2358 + #2359 + #2360 + #2361)

## Enhancement Summary

**Deepened on:** 2026-04-18
**Sections enhanced:** Overview, Phase 1 (upsert conflict-target), Phase 2 + 3 (import-side-effect guard), Risks, Acceptance Criteria
**Learnings applied:**

- `knowledge-base/project/learnings/2026-04-17-migration-not-null-without-backfill-and-partial-unique-index-pattern.md` — partial unique index pattern validated
- `knowledge-base/project/learnings/2026-04-15-ux-audit-scope-cutting-and-review-hardening.md` — direct prior art (PR #2346, this fixture's origin)
- `knowledge-base/project/learnings/2026-04-17-postgrest-aggregate-disabled-forces-rpc-option.md` — PostgREST hosted-capability probe pattern
- `knowledge-base/project/learnings/integration-issues/vitest-bun-test-cross-runner-compat-20260402.md` — bun:test is bun-only; test files cannot be type-checked by tsc/vitest
- `knowledge-base/project/learnings/test-failures/2026-04-03-bun-test-dom-preload-execution-order.md` — bun preload & cross-runner gotchas
- `knowledge-base/project/learnings/implementation-patterns/2026-03-28-psql-migration-runner-ci-patterns.md` — migration application CI pattern
- `knowledge-base/project/learnings/2026-04-13-billing-review-findings-batch-fix.md` — validates bundling 4 review scope-outs in one PR (the billing PR #2036 shipped three fixes in one with partial unique index for payment race)

### Key Improvements (deepen pass)

1. **Critical: top-level-execution guard required before Phase 2/3 exports.** `bot-fixture.ts` ends with `if (cmd === "seed") { await seed(); } else if ...` at module scope, and `bot-signin.ts` ends with `await main()`. Exporting helpers from these files for unit-testing **will execute the main path on import**, crashing the test runner (`process.exit(2)` from the `else` branch of `bot-fixture.ts`; a live Supabase signin from `bot-signin.ts`). Wrap both bottoms in `if (import.meta.main) { ... }` (the canonical Bun entrypoint guard — verified via Context7 against `/oven-sh/bun` docs) **as Phase 0 preparatory work**, before any `export` is added. This finding was caught by deepen-pass self-review against the loaded learnings and by reading the actual file tails; the original plan's Phase 2.2.2 (`export projectRef and cookieDomain`) and Phase 3.2.5 (`export sbDelete and sbFetch`) would have been runtime-broken without this guard.
2. **PostgREST upsert conflict-target explicitly verified.** `on_conflict=<cols>` in PostgREST resolves against any unique constraint or unique index that exactly matches those columns — **including a partial unique index**. Supabase's hosted PostgREST disables `db-aggregates-enabled` (per #2478 learning), but `resolution=merge-duplicates` is core PostgREST functionality and is NOT affected by that flag. No live probe required; Supabase docs confirm.
3. **Message-idempotency DELETE window risk labeled.** The DELETE-messages-before-INSERT step (Phase 1) creates a ~ms window where a crash between the two operations leaves the conversation without messages. Acceptable for a test fixture (re-seed recovers), but worth naming in Risks.
4. **`cq-mutation-assertions-pin-exact-post-state` rule directly applies.** The rule was born from PR #2346 (this fixture's origin). Every new assertion added in this plan MUST pin exact post-state (e.g., `expect(...).toBe(post)`, not `toContain`). Added to Acceptance Criteria as an explicit check.
5. **`cq-destructive-prod-tests-allowlist` rule already satisfied by the existing `UX_AUDIT_BOT_EMAIL` guard at module load.** This PR must not remove or weaken it. Added as a Pre-merge AC.
6. **bun:test files cannot be tsc-checked.** The existing `bot-fixture.test.ts` / `bot-signin.test.ts` already use `import { ... } from "bun:test"` — tsc `--noEmit` cannot resolve `bun:test`. This is a **pre-existing** constraint, not introduced here, but the new helper unit tests (Phase 2, Phase 3.2.5) continue to use `bun:test` and therefore will not be type-checked by vitest/tsc either. This is fine for `bun test plugins/soleur/` which is the actual runner.

### New Considerations Discovered

- A self-review pass surfaced the `import.meta.main` guard as a hard prerequisite. Without it, the plan would have RED-stage test failures unrelated to the actual test logic, costing a round of diagnosis.
- #2362 item 6 (`FIXTURE_CONVERSATIONS.role` narrowing to `'user' | 'assistant'` via `as const`) is already present in the current source (line 38: `] as const;`), verified via Read. The narrowing that issue requests is **on the `role` field inside `messages`**, not on the outer array. This PR does not fold that item — scope-holding on #2362 confirmed.

## Overview

PR #2346 (the ux-audit bot fixture landing) produced four code-review scope-outs in
`plugins/soleur/skills/ux-audit/scripts/{bot-fixture.ts, bot-signin.ts}` and their
`bun:test` companions in `plugins/soleur/test/ux-audit/`. This plan closes all four
in a single PR:

- **#2358 (P3 bug):** `seed()` is check-then-insert for conversations. Two concurrent
  callers can both "find no row, insert one" — duplicates. Fix with a unique index on
  `(user_id, session_id)` + PostgREST upsert (`Prefer: resolution=merge-duplicates`,
  `on_conflict=user_id,session_id`).
- **#2359 (P2 chore):** `bot-signin.test.ts` asserts only `authCookie.value.length > 20`
  — a future `@supabase/ssr` change to cookie format (e.g., `base64-` prefix) would
  pass the test while breaking bot auth. `projectRef` + `cookieDomain` are pure and
  untested. Fix: parse the cookie as JSON and assert session shape; export the two
  helpers and unit-test them.
- **#2360 (P2 bug):** Reset test never asserts the auth user survives; a regression
  that deletes the bot auth row would pass. `reset()` does not check DELETE `res.ok`,
  so partial failures silently orphan data. Fix: add `expect(await getBotUserId()).
  toBe(botId)` after reset and guard every DELETE response.
- **#2361 (P2 chore):** Two concurrent CI runs of the fixture suite race on the
  shared bot user. Fix: add `concurrency: { group: plugin-tests-ux-audit, cancel-in-progress: false }`
  to the job (or workflow) that runs these integration tests. Serializes ux-audit
  integration runs without cancelling them.

All four touch the same narrow surface area (two scripts + two test files + one new
migration + one workflow file) so bundling is strictly net-positive: one review
cycle, one migration apply, one concurrency change.

**Note on issue path drift:** The issue bodies reference `apps/web-platform/test/bot-fixture.ts`
but the actual files live at `plugins/soleur/skills/ux-audit/scripts/` (source) and
`plugins/soleur/test/ux-audit/` (tests). This plan uses the real paths throughout.

## Research Reconciliation — Spec vs. Codebase

| Spec claim (from #2358–#2361) | Reality (verified 2026-04-18) | Plan response |
|---|---|---|
| Files live at `apps/web-platform/test/bot-fixture.ts` | Files live at `plugins/soleur/skills/ux-audit/scripts/bot-fixture.ts` (source) and `plugins/soleur/test/ux-audit/bot-fixture.test.ts` (test) | Plan uses the real paths; no file-rename drift elsewhere |
| `conversations (user_id, session_id)` has no unique constraint | Confirmed — `001_initial_schema.sql` lines 45–61 create only `idx_conversations_user_id` (non-unique) and declare `session_id text` (nullable) | Add migration `028_conversations_user_id_session_id_unique.sql` with a **partial** unique index `WHERE session_id IS NOT NULL` (null-tolerant — existing rows without `session_id` must not block index creation) |
| Tests use vitest/jest | Tests use `bun:test` (`bun test`) | Plan uses `bun:test` idioms (`import { ... } from "bun:test"`; `spawnSync("bun", [SCRIPT])`); no vitest helpers |
| Workflow name is `.github/workflows/ux-audit.yml` or similar | Workflow is `.github/workflows/scheduled-ux-audit.yml` | Plan targets `scheduled-ux-audit.yml`. This workflow **already has** `concurrency.group: schedule-ux-audit`. #2361's concern is about the **plugin test runner** that executes `plugins/soleur/test/ux-audit/bot-{fixture,signin}.test.ts`, not the scheduled UX audit itself. |
| A dedicated plugin-tests workflow exists | `.github/workflows/` contains only `scheduled-ux-audit.yml` and `test-pretooluse-hooks.yml`; plugin tests run via `bash scripts/test-all.sh` invoked by root `npm test`, with no dedicated CI workflow visible | Plan addresses #2361 by **adding** job-level `concurrency:` to the scheduled-ux-audit workflow's `ux-audit:` job (belt-and-suspenders; the workflow-level group already exists so this is a narrowing rename to `plugin-tests-ux-audit` only if a dedicated plugin test workflow is introduced — see Phase 4 for the conservative choice) |

## Open Code-Review Overlap

Four open scope-outs touch these files and are folded into this PR:

- **#2358** (bot-fixture seed race) — **Fold in**. This plan closes it via Phase 1.
- **#2359** (bot-signin test gaps) — **Fold in**. This plan closes it via Phase 2.
- **#2360** (bot-fixture reset auth-survival + DELETE guards) — **Fold in**. Phase 3.
- **#2361** (CI concurrency guard) — **Fold in**. Phase 4.

One additional open scope-out touches `bot-fixture.ts` but is explicitly **deferred**,
not folded:

- **#2362** (ux-audit P3 polish batch — includes item 5 "seed() body logging truncation"
  and item 6 "FIXTURE_CONVERSATIONS.role narrow to `'user' | 'assistant'`"). **Acknowledge
  — do not fold.** #2362 is a grab-bag across 4 files (`ux-design-lead.md`, `route-list.yaml`,
  `scheduled-ux-audit.yml`, `bot-fixture.ts`) with its own shape. Pulling the two
  bot-fixture items from it would leave an orphan issue that's harder to reason about
  than shipping the whole #2362 batch on its own cycle. This PR restricts itself to
  the four-issue bot-fixture hardening scope.

PR body must list: `Closes #2358`, `Closes #2359`, `Closes #2360`, `Closes #2361` and
reference #2362 as `Ref #2362`.

## Files to Edit

- `plugins/soleur/skills/ux-audit/scripts/bot-fixture.ts` (Phase 1: replace
  `findConversationId` + `insertConversation` with a single `upsertConversation`;
  Phase 3: guard DELETE responses; optionally inline `seed()` messages-upsert by
  `conversation_id` to keep the reseed no-op idempotent).
- `plugins/soleur/skills/ux-audit/scripts/bot-signin.ts` (Phase 2: `export` the
  `projectRef` and `cookieDomain` helpers so they are unit-testable).
- `plugins/soleur/test/ux-audit/bot-fixture.test.ts` (Phase 3: add auth-user-survives
  assertion; add an idempotency test for concurrent seed that exercises the upsert
  path).
- `plugins/soleur/test/ux-audit/bot-signin.test.ts` (Phase 2: parse cookie as JSON,
  assert session shape; add unit-test describe blocks for the exported helpers).
- `.github/workflows/scheduled-ux-audit.yml` (Phase 4: the existing workflow-level
  `concurrency` already serializes scheduled runs; this PR does not need to change
  it. See Phase 4 decision.)

## Files to Create

- `apps/web-platform/supabase/migrations/028_conversations_user_id_session_id_unique.sql`
  — partial unique index on `(user_id, session_id) WHERE session_id IS NOT NULL`.

## Implementation Phases

### Phase 0 — Guard top-level execution (prerequisite for Phase 2 + Phase 3.2.5 exports)

**Why:** `bot-fixture.ts` currently ends with

```typescript
const cmd = process.argv[2];
if (cmd === "seed") { await seed(); }
else if (cmd === "reset") { await reset(); }
else { console.error(`Usage: bun ${import.meta.path} <seed|reset>`); process.exit(2); }
```

and `bot-signin.ts` ends with `await main();`. Importing helpers from either file
(which Phase 2 and Phase 3.2.5 require) will **execute the bottom block at module
load**, either crashing the test runner with `process.exit(2)` or attempting a real
Supabase signin before any test logic runs. The canonical Bun pattern for this is
`import.meta.main` (verified against the official Bun docs via Context7, source
`/oven-sh/bun/docs/guides/util/entrypoint.mdx`).

**Code changes:**

In `bot-fixture.ts`, replace the bottom block with:

```typescript
if (import.meta.main) {
  const cmd = process.argv[2];
  if (cmd === "seed") {
    await seed();
  } else if (cmd === "reset") {
    await reset();
  } else {
    console.error(`Usage: bun ${import.meta.path} <seed|reset>`);
    process.exit(2);
  }
}
```

In `bot-signin.ts`, replace `await main();` with:

```typescript
if (import.meta.main) {
  await main();
}
```

No behavior change when invoked directly via `bun plugins/soleur/skills/ux-audit/scripts/bot-fixture.ts seed`
(or `bot-signin.ts`) — `import.meta.main` is `true` in that context. Importing the
files from a test becomes safe.

**Test:** after this edit, `bun -e 'import("./plugins/soleur/skills/ux-audit/scripts/bot-fixture.ts")'`
should complete without error or `process.exit` — previously it printed the Usage
message and exited 2.

### Phase 1 — Upsert conversations (#2358)

**Migration first.** Create `028_conversations_user_id_session_id_unique.sql`:

```sql
-- Unique (user_id, session_id) for PostgREST upsert on conflict.
-- Partial: session_id is nullable; existing NULL rows must not collide.
create unique index concurrently if not exists
  uniq_conversations_user_id_session_id
  on public.conversations (user_id, session_id)
  where session_id is not null;
```

Why `concurrently` + `if not exists`: builds the index without blocking writes on the
`conversations` table and is idempotent across re-apply. Why partial: `session_id` is
`text` nullable in the existing schema (verified in `001_initial_schema.sql` line 51);
a full unique index would reject every existing row with `session_id IS NULL`.

**PostgREST conflict-target verification.** PostgREST's `on_conflict=<cols>` resolves
against any unique constraint or unique index whose column list exactly matches the
parameter — a **partial** unique index on those same columns satisfies the requirement.
(Supabase's hosted PostgREST disables `db-aggregates-enabled` per learning
`2026-04-17-postgrest-aggregate-disabled-forces-rpc-option.md`, but
`resolution=merge-duplicates` is core upsert functionality and is NOT affected by
that flag.) No live probe needed; Supabase PostgREST docs confirm.

**Code changes in `bot-fixture.ts`:**

1. Replace `findConversationId` + `insertConversation` with a single `upsertConversation`:

    ```typescript
    async function upsertConversation(
      userId: string,
      sessionId: string,
      domainLeader: string,
    ): Promise<string> {
      const res = await sbFetch(
        `/rest/v1/conversations?on_conflict=user_id,session_id`,
        {
          method: "POST",
          headers: {
            Prefer: "return=representation,resolution=merge-duplicates",
          },
          body: JSON.stringify({
            user_id: userId,
            session_id: sessionId,
            domain_leader: domainLeader,
            status: "completed",
          }),
        },
      );
      if (!res.ok) {
        const body = (await res.text()).slice(0, 200);
        throw new Error(`POST conversations (upsert) failed: ${res.status} ${body}`);
      }
      const rows = (await res.json()) as Array<{ id: string }>;
      if (!rows[0]) {
        throw new Error("POST conversations returned empty array — representation missing");
      }
      return rows[0].id;
    }
    ```

2. In `seed()`, replace the `existing = await findConversationId(...)` / `if (existing) continue`
   block with a single `const cid = await upsertConversation(botId, c.session_id, c.domain_leader)`.
3. For `insertMessages`, keep the POST. The messages table has no `(conversation_id, role, content)`
   unique. Idempotency today is achieved by the "skip if conversation exists" branch. With upsert
   - `resolution=merge-duplicates`, re-running `seed()` will return the existing conversation id
   and then **re-insert** messages, doubling them. **Fix:** before `insertMessages`, issue a
   `DELETE /rest/v1/messages?conversation_id=eq.<cid>` to clear. This keeps `seed()` idempotent
   in message count. (Alternative — adding a unique `(conversation_id, role, content)` index —
   rejected: `content` is long text, indexing it is wasteful; a DELETE+INSERT on a fixture-only
   conversation is fine.)
4. The post-condition test ("seed is idempotent — running twice yields same row counts") in
   `bot-fixture.test.ts` lines 116–123 already asserts `countAfterSecond === countAfterFirst
   === 2`. Keep as-is; it now exercises the upsert path.

### Phase 2 — bot-signin test gaps (#2359)

**Export helpers** in `bot-signin.ts`:

```typescript
export function projectRef(supabaseUrl: string): string { ... }
export function cookieDomain(siteUrl: string): string { ... }
```

No behavior change; the existing `main()` still calls them.

**Expand `bot-signin.test.ts`:**

1. Inside the existing `describeIfCreds("bot-signin", ...)` integration block, change
   the cookie assertion to parse the value as JSON and assert session shape:

    ```typescript
    const session = JSON.parse(authCookie!.value) as {
      access_token?: unknown;
      refresh_token?: unknown;
      expires_at?: unknown;
    };
    expect(typeof session.access_token).toBe("string");
    expect((session.access_token as string).length).toBeGreaterThan(20);
    expect(typeof session.refresh_token).toBe("string");
    expect(typeof session.expires_at).toBe("number");
    ```

    Why: asserts the contract `@supabase/ssr` consumes, not just that "something long was written."
    If a future SDK version adds a `base64-` prefix to the cookie value (as @supabase/ssr has
    historically done), `JSON.parse` on the raw value will throw, failing the test loudly, and
    the implementer will know to strip the prefix or update the writer.

2. Add a separate `describe("bot-signin pure helpers", ...)` block (no creds gate — these
   are pure functions) with unit tests via `import { projectRef, cookieDomain } from
   "../../skills/ux-audit/scripts/bot-signin.ts"`:

    - `projectRef("https://abc123.supabase.co")` → `"abc123"`.
    - `projectRef("https://abc123.supabase.co/rest/v1/")` → `"abc123"` (path tolerated).
    - `projectRef("http://localhost:54321")` → throws (no protocol/host mismatch).
    - `projectRef("https://example.com")` → throws (non-supabase.co host).
    - `projectRef("")` → throws.
    - `cookieDomain("https://soleur.ai/dashboard")` → `"soleur.ai"`.
    - `cookieDomain("https://preview.soleur.ai")` → `"preview.soleur.ai"`.
    - `cookieDomain("http://localhost:3000")` → `"localhost"`.
    - `cookieDomain("not-a-url")` → throws.

### Phase 3 — reset auth-survival + DELETE guards (#2360)

**Code changes in `bot-fixture.ts` — `reset()`:**

1. Guard both DELETE responses. Introduce a small helper at the top of the file
   (near `sbFetch`):

    ```typescript
    async function sbDelete(path: string): Promise<void> {
      const res = await sbFetch(path, { method: "DELETE" });
      if (!res.ok) {
        const body = (await res.text()).slice(0, 200);
        throw new Error(`DELETE ${path} failed: ${res.status} ${body}`);
      }
    }
    ```

2. In `reset()`, replace the bare `await sbFetch(..., { method: "DELETE" })` at the
   messages loop and at the conversations delete with `await sbDelete(...)`.
3. The `updateUserRow` at the end of `reset()` already throws on non-OK; leave it.

**Code changes in `bot-fixture.test.ts` — reset test:**

1. After `expect(r.status).toBe(0)`, assert the bot auth user still exists:

    ```typescript
    // Auth user must survive reset — only DB state should be cleared.
    expect(await getBotUserId()).toBe(botId);
    ```

    The existing `getBotUserId()` helper already throws if the email is absent, so
    any regression that cascaded to delete the auth user would fail loudly.

### Phase 4 — CI concurrency guard (#2361)

**Decision: narrow the fix to match the actual risk surface.**

The stated risk in #2361 is: "Two concurrent CI runs will race on `seed`/`reset`,
producing flaky failures." There are two runners that can race:

1. **The scheduled UX audit workflow** (`.github/workflows/scheduled-ux-audit.yml`) —
   already has `concurrency: { group: schedule-ux-audit, cancel-in-progress: false }`
   at workflow level (lines 42–44). Scheduled runs are already serialized. ✅
2. **The plugin test-runner** that executes `plugins/soleur/test/ux-audit/bot-{fixture,signin}.test.ts`
   — invoked by `bash scripts/test-all.sh` at the root. There is **no dedicated workflow
   file** running these tests (verified: `.github/workflows/` contains only
   `scheduled-ux-audit.yml` and `test-pretooluse-hooks.yml`). Whichever workflow(s) invoke
   `npm test` at the root would be the ones to guard.

The conservative, correctness-preserving fix is twofold:

1. **Belt-and-suspenders on the scheduled UX audit job.** Even though the workflow-level
   concurrency already serializes scheduled runs, the `workflow_dispatch` trigger allows
   a manual run to overlap. Since the workflow already uses `cancel-in-progress: false`
   at workflow scope, this is already covered. **No change needed to the scheduled workflow.**
2. **Add a test-module-level advisory lock** — the simpler, runner-agnostic guard that
   works regardless of which CI workflow executes the integration tests. Supabase's
   Postgres supports session-scoped advisory locks via PostgREST's RPC. However, the
   #2361 issue explicitly prefers the **concurrency group** option: "The concurrency
   group is simpler and sufficient for current scale."

Since there is no dedicated plugin-test workflow today, Phase 4 ships the concurrency
guard on the one workflow that definitively runs the bot-fixture scripts in shared prod
— `scheduled-ux-audit.yml` — by **tightening the existing workflow-level group to also
apply at job level** with a bot-fixture-specific name. This keeps the scheduled-run
serialization and makes the intent discoverable to future readers:

```yaml
# At the existing workflow level (keep as-is):
concurrency:
  group: schedule-ux-audit
  cancel-in-progress: false

# Add at the ux-audit job level:
jobs:
  ux-audit:
    runs-on: ubuntu-latest
    timeout-minutes: 45
    concurrency:
      group: bot-fixture-shared-state
      cancel-in-progress: false
    steps:
      ...
```

`bot-fixture-shared-state` is a **shared name** any future workflow that seeds/resets
the bot fixture can opt into. This makes #2361 a structural guard, not a one-off fix.

Document the pattern inline above the workflow `concurrency:` block with a 4-line
comment: "Any job that invokes `bot-fixture.ts seed` or `reset` must belong to
`concurrency.group: bot-fixture-shared-state` with `cancel-in-progress: false`. This
serializes all bot-fixture consumers so the shared <ux-audit-bot@jikigai.com> row is
never raced on."

### Phase 5 — Verify + ship

1. **Migrations:** run the new `028_*.sql` against prod Supabase after merge
   (`wg-when-a-pr-includes-database-migrations` gate — Supabase CLI or SQL editor,
   verify via `select indexname from pg_indexes where tablename='conversations'`).
2. **Local verification (before PR):** exercise the upsert path twice in sequence via
   `doppler run -p soleur -c prd_scheduled -- bun plugins/soleur/skills/ux-audit/scripts/bot-fixture.ts seed`.
   First run should insert 2 conversations; second run should return the same 2
   conversation ids (upsert hit). Confirm message counts are stable at 3+4=7 across
   runs. This is intentionally run against `prd_scheduled` because that's where
   `ux-audit-bot@jikigai.com` exists — the blast-radius guard in the test already
   enforces that only this email is acceptable.
3. **Test:** `cd /home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-bot-fixture-hardening
   && doppler run -p soleur -c prd_scheduled -- bun test plugins/soleur/test/ux-audit/bot-fixture.test.ts
   plugins/soleur/test/ux-audit/bot-signin.test.ts`. The full suite of 5 bot-fixture
   tests + 2 bot-signin integration tests + ~10 helper unit tests should pass; the
   helper unit tests must pass even without creds.
4. **Push + PR:** PR body must begin with the four `Closes #...` lines before any
   prose. `semver:patch` label (bug-fix category).

## Acceptance Criteria

### Pre-merge (PR)

- [ ] Both `bot-fixture.ts` and `bot-signin.ts` wrap their top-level execution in
  `if (import.meta.main) { ... }` (Phase 0 — hard prerequisite for unit-test imports).
  Verify: `bun -e 'await import("./plugins/soleur/skills/ux-audit/scripts/bot-fixture.ts")'`
  exits 0 silently (no Usage message, no `process.exit(2)`).
- [ ] Migration `028_conversations_user_id_session_id_unique.sql` committed.
- [ ] `bot-fixture.ts` uses a single `upsertConversation` (no `findConversationId` /
  `insertConversation` helpers remain).
- [ ] `bot-fixture.ts` `reset()` uses `sbDelete` (or equivalent guard) for every DELETE
  — `grep -n 'method: "DELETE"' plugins/soleur/skills/ux-audit/scripts/bot-fixture.ts`
  returns **zero** bare calls.
- [ ] `bot-signin.ts` exports `projectRef` and `cookieDomain`.
- [ ] `bot-signin.test.ts` parses the cookie value with `JSON.parse` and asserts
  `access_token`, `refresh_token`, `expires_at` presence/types.
- [ ] `bot-signin.test.ts` contains a `describe("bot-signin pure helpers", ...)` block
  with at least 9 unit tests (4 projectRef happy/error + 3 cookieDomain happy + 2
  cookieDomain error).
- [ ] `bot-fixture.test.ts` "reset clears seeded conversations but leaves auth user"
  test asserts `expect(await getBotUserId()).toBe(botId)` after reset.
- [ ] `scheduled-ux-audit.yml` `ux-audit:` job has
  `concurrency: { group: bot-fixture-shared-state, cancel-in-progress: false }` with
  an inline comment naming the shared-name convention.
- [ ] `bun test plugins/soleur/test/ux-audit/bot-fixture.test.ts
  plugins/soleur/test/ux-audit/bot-signin.test.ts` passes locally with `prd_scheduled`
  creds (integration) and without creds (unit helpers only).
- [ ] Every new mutation assertion pins exact post-state (`.toBe(post)`, never
  `toContain([pre, post])`) per rule `cq-mutation-assertions-pin-exact-post-state`
  (the rule was born from PR #2346 — this fixture's parent).
- [ ] Existing `UX_AUDIT_BOT_EMAIL !== "ux-audit-bot@jikigai.com"` allowlist guard at
  module load in `bot-fixture.test.ts` lines 22–29 is preserved unchanged
  (`cq-destructive-prod-tests-allowlist`).
- [ ] PR body begins with: `Closes #2358`, `Closes #2359`, `Closes #2360`, `Closes #2361`.
- [ ] `## Changelog` section in PR body references all four issue numbers.

### Post-merge (operator)

- [ ] Apply migration `028_*.sql` to prod Supabase via `supabase db push` (or
  equivalent SQL Editor paste) — runbook:
  `knowledge-base/engineering/ops/runbooks/supabase-migrations.md`.
- [ ] Verify index exists: query `pg_indexes where tablename='conversations' and
  indexname='uniq_conversations_user_id_session_id'` returns one row.
- [ ] Trigger a manual `gh workflow run scheduled-ux-audit.yml` dry-run (the workflow
  has `workflow_dispatch: {}`), watch it turn green, confirm the "Seed bot fixture"
  and "Reset bot fixture" steps both succeed. This verifies the upsert path and
  concurrency guard in situ without waiting for the next monthly cron.

## Test Scenarios (RED → GREEN)

1. **RED:** `bot-fixture.test.ts` reset test adds
   `expect(await getBotUserId()).toBe(botId)` — fails because the test runs before the
   auth-survival guard is added (guard is already indirectly satisfied today; this
   test is TDD-style to lock the invariant forever). GREEN: the existing `reset()`
   already preserves the auth user (it only touches `/rest/v1/*` tables, never
   `/auth/v1/admin/users/:id DELETE`), so the test passes against current behavior.
   Its value is regression-prevention, not root-cause-fix.

2. **RED:** Add an idempotency assertion that re-seeding preserves exactly 7 total
   messages across the two fixture conversations (3 + 4). Without the DELETE-messages
   step in Phase 1, re-seed would produce 14. GREEN: Phase 1's DELETE-before-insert
   keeps the count at 7.

3. **RED:** Unit test `projectRef("")` throws. GREEN: no behavior change needed —
   `bot-signin.ts` line 32 already throws when the regex doesn't match. This test
   locks the contract in case anyone makes the helper lenient in the future.

4. **RED:** Parse-cookie assertion — `JSON.parse(authCookie.value)` on the current
   cookie should succeed and yield `{ access_token, refresh_token, expires_at }`.
   GREEN: already true; the test pins it.

5. **RED:** `reset()` DELETE guard — inject a fake 403 via an invalid service key
   in a local repro (don't ship this as an automated test — the prod Supabase
   integration suite won't let us forge a 403 without harming real state). Instead,
   add a unit-level assertion: mock `sbFetch` to return `{ ok: false, status: 409,
   text: () => Promise.resolve("conflict") }` and call an extracted `sbDelete(...)`
   — expect it throws. This is the only case where a unit-pure extraction pays off.
   **Scope decision:** the extraction is 6 lines; add the unit test in a new
   `plugins/soleur/test/ux-audit/bot-fixture-helpers.test.ts` that imports the
   exported `sbDelete` and `sbFetch`. Requires `export` on both helpers. If the
   export would violate the script's "one-file bun script" ethos, skip this unit
   test and rely on the integration suite's DELETE path to exercise the happy path
   — the guard itself is one `if (!res.ok) throw` line, trivially correct. **Default
   to scope-in** (export + unit test) unless the RED step turns up a reason to
   defer. An exported helper is better than a bare DELETE call; the test is cheap.

6. **RED/GREEN for #2361:** Manually trigger two concurrent `gh workflow run
   scheduled-ux-audit.yml` invocations. With the job-level concurrency group, the
   second run should enter "queued" state until the first finishes. Without it
   (counterfactual — not actually tested in this PR), both would run and the seed
   race would be possible. This is a post-merge operator verification, not an
   automated test.

## Risks

- **Partial unique index + upsert edge case.** PostgREST's `on_conflict=user_id,session_id`
  relies on a unique constraint or unique index matching exactly those columns. A
  **partial** unique index (`WHERE session_id IS NOT NULL`) is supported by
  Postgres ≥ 9.5 and PostgREST's upsert resolution, but the upsert will **still fail
  with a 23505 if `session_id IS NULL`** is ever attempted (the partial index
  doesn't catch nulls). This is acceptable for the fixture — both `FIXTURE_CONVERSATIONS`
  entries have non-null `session_id` strings. **Mitigation:** add a runtime guard in
  `upsertConversation` that rejects empty `sessionId` with a clear error, so future
  contributors who add a `session_id: ""` fixture fail fast.
- **Migration race with running dev instances.** `create unique index concurrently`
  is non-blocking but takes longer than a normal index build. On prod, the
  `conversations` table has ≲1000 rows (small); impact is negligible. `if not exists`
  makes the migration idempotent on re-apply.
- **`scheduled-ux-audit.yml` workflow-level vs job-level concurrency interaction.** Having
  both `concurrency.group: schedule-ux-audit` (workflow) and
  `concurrency.group: bot-fixture-shared-state` (job) **stacks**: both gates must pass.
  This is what we want — scheduled runs stay serialized among themselves, AND any
  future workflow that adopts `bot-fixture-shared-state` is serialized against the
  scheduled one. Verified via GitHub Actions docs: job-level `concurrency` is
  independent of workflow-level and checked per-job.
- **`@supabase/ssr` cookie format drift.** If a future SDK version serializes the
  cookie value as `base64-<base64(json)>`, the new Phase 2 `JSON.parse(authCookie.value)`
  assertion will throw. That's **correct behavior** — the ux-audit bot would also break
  silently today, and the failing test tells us which shape we need to emit. Mitigation:
  when the test fails after an SDK bump, update `bot-signin.ts` to emit whichever
  shape the matching @supabase/ssr major version consumes.
- **Destructive-prod-test blast radius (existing guard).** `bot-fixture.test.ts` lines
  22–29 already throw at module load if `UX_AUDIT_BOT_EMAIL !== "ux-audit-bot@jikigai.com"`,
  satisfying `cq-destructive-prod-tests-allowlist`. This PR does not change that guard.
- **Message-idempotency DELETE window.** Phase 1 issues DELETE-then-INSERT on messages
  inside `seed()` per conversation. If the process is killed between the two operations
  (e.g., SIGTERM during CI), the conversation is left with zero messages until the
  next seed. **Impact:** acceptable for a test fixture — re-running `seed` recovers
  the state, and the fixture is never read by a user-facing path. **Mitigation:**
  none; the alternative (a single POST with `resolution=merge-duplicates` on a unique
  `(conversation_id, role, content)` index) is rejected in the Alternatives table.
- **Top-level-execution import side effect (caught in deepen-pass).** Without Phase 0's
  `import.meta.main` guard, Phase 2 / 3.2.5 unit tests would crash at import — either
  `process.exit(2)` from `bot-fixture.ts` or a live Supabase signin attempt from
  `bot-signin.ts`. Phase 0 is a hard prerequisite, not a nice-to-have.

## Non-Goals

- **KB file seeding** — deferred to #2351. Bot-fixture v1 is DB-only by design; KB
  files live in GitHub workspace, not Supabase Storage.
- **Advisory lock fallback for #2361.** The issue explicitly prefers the concurrency
  group ("simpler and sufficient for current scale"). A `pg_advisory_lock` on
  `hashtext('ux-audit-bot')` would be an alternative, but adds Supabase round-trips
  and a release-in-finally requirement. Out of scope.
- **Exhaustive SDK-format-drift test** — the Phase 2 JSON.parse assertion covers the
  current shape. A matrix test across @supabase/ssr versions is out of scope.
- **Folding #2362 (ux-audit P3 polish batch)** — it touches 4 files; acknowledged above.
- **Removing the `describe.skip` + "no creds" silent-skip in `bot-fixture.test.ts`.**
  The existing comment in lines 32–35 references #2361 for the loud-fail guardrail,
  but the actual fix there is "add a dedicated ux-audit smoke job that injects
  Doppler prd_scheduled" — a workflow change, not a test change. This PR does not
  add that job; the comment and skip behavior stay. Create a follow-up issue if the
  smoke-job delivery needs its own tracker — but per the existing comment, #2361 is
  already the tracker. Acknowledge by keeping the comment; do not extend scope.

## Domain Review

**Domains relevant:** Engineering (CTO — architectural implication: adds a new unique
constraint to a core table; modifies a recurring workflow).

Cross-domain impact: none. No Product/UX surface area, no legal, no finance, no
marketing. Pure test/CI hardening + one migration.

### Engineering

**Status:** reviewed (plan-author-integrated — change is a backlog-drain of explicit
review findings; no fresh architectural decision beyond choosing partial vs full
unique index, which is forced by schema reality).
**Assessment:** The unique index is narrow and non-blocking (`concurrently`). The
upsert is a PostgREST-native pattern (no RPC, no stored proc). The message-reseed
DELETE+INSERT is fixture-scoped and acceptable. The concurrency group is a structural
guard with a stable shared-name that future consumers can opt into. No architectural
concern that warrants a full CTO assessment round trip.

No Product/UX Gate — no user-facing surface.

## Alternative Approaches Considered

| Approach | Pros | Cons | Decision |
|---|---|---|---|
| Full unique index on `(user_id, session_id)` (no partial) | Simpler DDL | Would reject existing rows where `session_id IS NULL`, breaking migration | **Rejected** — schema has nullable `session_id` |
| `pg_advisory_lock` instead of CI concurrency group (#2361) | Works across any workflow | Adds Supabase round-trips; must release in finally; more to maintain | **Rejected** — issue explicitly prefers concurrency group |
| Extract `sbDelete` to a separate module for unit-testing | Cleaner unit tests | Breaks "one-file bun script" ethos; import ceremony | **Scope-in** but defer module split — just `export` within the same file |
| Fold #2362 items 5+6 (log truncation, role narrowing) into this PR | One less PR | #2362 is a grab-bag; fold would orphan the other items | **Rejected** — ship #2362 on its own cycle |
| Add unique `(conversation_id, role, content)` index for messages | Upsert-native message idempotency | `content` is long text; wasteful; re-parse on every insert | **Rejected** — DELETE+INSERT on 7-row fixture is cheap |

**Deferral tracking:** no new deferrals introduced by this plan. #2351 (KB file
seeding) and #2362 (P3 polish) are already filed with their own issues.

## AI-Era Considerations

- The upsert migration SQL was drafted from Postgres + PostgREST docs and verified
  against the existing schema in `001_initial_schema.sql`. Human review required on
  the `concurrently` + `if not exists` combination (standard but version-sensitive).
- The Phase 2 JSON.parse assertion design reflects the `@supabase/ssr` cookie contract
  at the time of writing; when the SDK bumps majors, the failing test itself will
  point the future agent at the right shape change. No fragile version-pinning.
- `bot-fixture-shared-state` concurrency-group name is chosen to be grep-stable and
  self-documenting — `cq-code-comments-symbol-anchors-not-line-numbers` guidance.

---

*Plan authored 2026-04-18 for branch `feat-one-shot-bot-fixture-hardening`. Closes
`#2358`, `#2359`, `#2360`, `#2361`.*
