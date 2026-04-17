---
module: "KB share links"
date: 2026-04-17
problem_type: security_issue
component: supabase_migration
symptoms:
  - "Share link token resurrection after file delete/rename/overwrite"
  - "Concurrent POST /api/kb/share can create duplicate active rows for the same (user_id, document_path)"
  - "Migration alter column set not null fails when prior UPDATE did not populate the new column"
root_cause: missing_backfill_and_missing_unique_constraint
severity: high
tags:
  - migration
  - supabase
  - sha256
  - content-integrity
  - partial-unique-index
  - concurrency
  - code-review
synced_to: [data-integrity-guardian]
---

# Migration NOT NULL trap + partial unique index pattern for revoke-and-reissue flows

## Problem

Three related defects in one PR (#2463, closing #2326):

1. **Token resurrection.** `kb_share_links` rows persisted `revoked = false` after the underlying KB file was deleted, renamed, or overwritten. A new file materialising at the same `document_path` would be served through the old token.

2. **Migration NOT NULL trap.** First draft of the migration added `content_sha256 text NOT NULL` after an `UPDATE ... SET revoked = true` that did **not** populate the new column. Any pre-existing row would fail the NOT NULL transition at `alter column ... set not null`. Locally the migration ran against an empty table, so vitest (mocked Supabase) and `tsc --noEmit` never exercised the failure path. Would have failed on first apply if prod had any rows.

3. **Concurrent-POST race.** Two concurrent POSTs for the same `(user_id, document_path)` with a modified file could both pass the existing-share lookup (SELECT-then-INSERT) and both insert new rows. Result: multiple active shares per (user, path), one of them invisible to the UI — exactly the dangling-row class the migration is meant to prevent.

## Investigation / How It Surfaced

Written tests + typecheck all green. The failure modes were caught by parallel review agents:

- **data-integrity-guardian** read the migration SQL symbolically against the insert path and noticed the `UPDATE ... SET revoked = true` leaves `content_sha256 IS NULL`, so the subsequent `set not null` fails on any existing row. Reinforces `2026-04-15-multi-agent-review-catches-bugs-tests-miss.md`.
- **security-sentinel + data-integrity-guardian** both flagged the SELECT-then-INSERT race. The missing partial unique index is the exact mechanism by which the bug the migration tries to close can still occur under concurrent load.
- **performance-oracle** separately flagged a Range-request performance regression (scope-out #2466).

## Solution

### 1. Migration: scope the CHECK to active rows instead of NOT NULL

Instead of requiring `content_sha256 IS NOT NULL` for all rows (which forces backfill or revoke of legacy rows — awkward for audit), keep the column nullable and enforce the invariant only on rows that can be viewed:

```sql
alter table public.kb_share_links
  add column content_sha256 text;

update public.kb_share_links
   set revoked = true
 where content_sha256 is null
   and revoked = false;

alter table public.kb_share_links
  add constraint kb_share_links_content_sha256_format
    check (revoked = true or content_sha256 ~ '^[a-f0-9]{64}$');
```

The CHECK reads: "either this row is revoked, or it carries a valid lowercase-hex SHA-256." Revoked legacy rows retain audit metadata (token, user_id, document_path); active rows are invariant-enforced at the DB layer.

### 2. Partial unique index for "one active X per Y"

The resurrection class needs a DB-level guarantee that no two rows can be active for the same natural key:

```sql
create unique index kb_share_links_one_active_per_doc
  on public.kb_share_links(user_id, document_path)
  where revoked = false;
```

The partial `where revoked = false` is critical: a user can have many historical revoked shares for the same path, but only one active one. The unique constraint only applies to the active subset.

### 3. Handle the resulting 23505 conflict in the POST handler

```ts
const { error: insertError } = await serviceClient
  .from("kb_share_links")
  .insert({ user_id, token, document_path, content_sha256 });

if (insertError) {
  if ((insertError as { code?: string }).code === "23505") {
    // Concurrent POST won the race. Read the winner's row; return its
    // token if hashes match, else 409.
    const { data: winner } = await serviceClient
      .from("kb_share_links")
      .select("token, content_sha256")
      .eq("user_id", user.id)
      .eq("document_path", body.documentPath)
      .eq("revoked", false)
      .maybeSingle();
    if (winner && winner.content_sha256 === contentHash) {
      return NextResponse.json({ token: winner.token, url: `/shared/${winner.token}` });
    }
    return NextResponse.json({ error: "Concurrent share creation — retry" }, { status: 409 });
  }
  // ...
}
```

### 4. Hash raw bytes, not parsed content

For integrity binding to catch frontmatter-only edits, hash the **raw file bytes** (pre-frontmatter-parse). `gray-matter` returns `content` with frontmatter stripped; hashing that lets `title:` / `tags:` edits silently pass verification. Added `readContentRaw` to `server/kb-reader.ts` returning `{ buffer, raw, path }`, and refactored `readContent` as a thin wrapper around it.

## Key Insights

- **Migration "set not null" trap:** Any `alter column X set not null` that runs after an `UPDATE` which does not populate X will fail at apply time if prior rows exist. Vitest with mocked Supabase will pass; `tsc --noEmit` sees no type involvement. Only a prod apply (or integration test against a real DB) catches it. **Prefer scoped CHECK constraints (`revoked = true or X ~ ...`) over blanket NOT NULL** when pre-existing rows can stay in a "tombstone" state.
- **Partial unique indexes are the mechanical guarantee for "one active X per Y":** SELECT-then-INSERT is a race. A partial unique `where revoked = false` cannot race — the DB rejects the second insert. Handle 23505 in app code by re-reading the winner.
- **Hash raw bytes for integrity binding:** `gray-matter`, `parse5`, any content-transforming reader strips metadata. Hash the buffer *before* the parser touches it. Ship a `readContentRaw` sibling to the parsing helper and have the parser call it.

## Session Errors

**Error 1 — Lost CWD between Bash calls.** First `./node_modules/.bin/vitest` attempt after an Edit failed with "No such file or directory" because shell state does not persist between Bash tool invocations. Recovered by prefixing `cd <abs-path> &&`. **Prevention:** Already covered by rule `cq-for-local-verification-of-apps-doppler` in AGENTS.md.

**Error 2 — Migration NOT NULL trap not caught by tests.** Initial migration had `alter column content_sha256 set not null` after an UPDATE that only populated `revoked`. Would have failed on first prod apply. Tests didn't catch it because Supabase was mocked; typecheck didn't see it because there's no type involvement; the failure only surfaces at DB apply time. **Prevention:** When writing a migration that adds NOT NULL on a new column, verify the backfill path explicitly. If pre-existing rows cannot be backfilled with a valid value, use a scoped CHECK (`revoked = true or X ~ ...`) instead of NOT NULL and keep the column nullable. Also: run the migration against a real prod-shaped Supabase instance (or at minimum a local `supabase start`) in any migration PR.

## Prevention

- In migration review checklists, explicitly ask: "Does this migration add NOT NULL to a new column? If yes, does the backfill populate it for all existing rows?"
- When modelling a "one active X per Y" invariant, reach for `CREATE UNIQUE INDEX ... WHERE <active-predicate>` instead of application-level SELECT-then-INSERT.
- When binding a token/signature to file content, hash the raw bytes from the fs read — never hash the output of a content-transforming reader.

## Related

- `2026-04-15-multi-agent-review-catches-bugs-tests-miss.md` — Same pattern: review agents catch defects that unit tests + typecheck miss.
- `plugins/soleur/agents/engineering/review/data-integrity-guardian.md` — This agent reads migration SQL symbolically against app insert code and flags backfill gaps.
- PR #2463 / issue #2326 — Scope.
- Deferred scope-outs filed: #2466 (Range-request hash cache), #2467 (POST handler extraction), #2468 (shared mock fixture), #2469 (ETag emission).
