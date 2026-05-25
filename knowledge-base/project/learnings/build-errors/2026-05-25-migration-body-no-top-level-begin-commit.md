---
date: 2026-05-25
category: build-errors
status: applied
session_pr: "#4417"
related_pr: "#3853"
related_migs: "068, 067, 066, 065"
---

# Migration body must NOT contain top-level `BEGIN;`/`COMMIT;` — the runner already wraps

## Problem

Migration `068_attachments_workspace_shared.sql` was authored with an explicit `BEGIN;` at line 40 and `COMMIT;` at the end, on the assumption that wrapping the body in a transaction was good hygiene. The mig-shape lint was even authored to **assert** the wrapper was present.

This collides with the canonical migration runner (`apps/web-platform/scripts/run-migrations.sh:328-335`), which pipes the body PLUS a trailing `INSERT INTO public._schema_migrations (filename, content_sha) VALUES (...)` to `psql --single-transaction --set ON_ERROR_STOP=1`. The `--single-transaction` flag implicitly wraps the whole stream in `BEGIN ... COMMIT`.

When the migration body issues its own explicit `BEGIN;`, psql emits a warning. When it issues its own explicit `COMMIT;`, psql's wrapping transaction ends prematurely — and the trailing `INSERT INTO _schema_migrations` runs in autocommit, **outside any transaction**.

**The dangerous failure mode:** if the trailing ledger INSERT fails (PK collision on retry, content_sha length mismatch, etc.), the migration's DDL is already committed but the ledger row never lands. Next deploy invocation sees an empty ledger row for this filename → re-applies the migration → `CREATE POLICY` fails with duplicate name → migrate job dies → operator-recovery required.

For an auto-applied prd migration on a single-user-incident-threshold feature, this is brand-survival.

## Solution

**Strip all top-level `BEGIN;`/`COMMIT;` from migration bodies.** The runner already provides atomic apply + ledger-insert via `--single-transaction`. Mig 067 (the precedent established by PR-1 #4307) ships with no explicit transaction control and works correctly through the same runner.

The only legitimate `BEGIN` / `END` inside a migration body are **plpgsql block delimiters inside dollar-quoted function bodies** (e.g., `LANGUAGE plpgsql AS $$ DECLARE ... BEGIN ... END; $$`). These are syntactic and do not interact with the wrapping transaction.

**Migration-shape lint:** assert ABSENCE, not presence. Use a dollar-quote-stripping pre-pass before the line-anchored regex so plpgsql `BEGIN`/`END` keywords inside function bodies don't false-match:

```typescript
function topLevelBeginCommits(src: string): number {
  // Strip dollar-quoted function bodies before counting top-level
  // BEGIN;/COMMIT; statements.
  const stripped = src.replace(/\$\$[\s\S]*?\$\$/g, "");
  const beginMatches = stripped.match(/^\s*BEGIN\s*;/gim) ?? [];
  const commitMatches = stripped.match(/^\s*COMMIT\s*;/gim) ?? [];
  return beginMatches.length + commitMatches.length;
}
expect(topLevelBeginCommits(sql)).toBe(0);
```

**Down migrations:** same rule. The down body runs through the same runner path on rollback.

## Key Insight

**A migration body is one half of a contract with its runner.** The runner imposes a transaction boundary; the body must not duplicate it. Duplicating produces silently-broken atomicity that only manifests on retry — the worst kind of bug because the first apply looks healthy.

The general pattern: when a calling context already provides a primitive (transaction, lock, retry envelope, signal handler, exit-code propagation), the callee must NOT redundantly provide the same primitive. Redundancy often means subtle misbehavior, not graceful degradation.

This is symmetric to the bench-pattern lesson where `set -e` doesn't propagate through `cmd | tail` pipelines (`hr-when-a-command-exits-non-zero-or-prints` family), and to the Bash tool's lack of `pipefail` (`knowledge-base/project/learnings/2026-05-18-test-all-tail-masking-and-monitor-exit-condition-tightness.md`).

## Prevention

1. **Mig-shape lint inverted** in PR #4417: assert `topLevelBeginCommits(sql) === 0` for both up and down.
2. **Migration template** (if one is added) must omit BEGIN/COMMIT.
3. **`/soleur:plan` migration prescription** should explicitly state "no top-level BEGIN/COMMIT" when generating migration scaffolding.
4. **Cross-migration scan** (one-off): grep historical migrations for top-level `^BEGIN;` / `^COMMIT;` patterns. Mig 068's pre-fix state was the only case; mig 067, 066, 065, 064 are all clean. If any are found, file an issue to strip them (idempotency on re-apply is the load-bearing concern; current state is "first-apply works, retry breaks").

## Session Errors

(See conversation for full list; this learning resolves item 10.)

- **Nested top-level BEGIN/COMMIT in mig 068** — Recovery: removed from both .sql and .down.sql, inverted mig-shape lint. Prevention: above.
- **Mig-shape lint asserted the wrong direction** — Recovery: replaced positive-presence assertion with absence-assertion + dollar-quote stripper. Prevention: when authoring a lint for a migration invariant, walk the runner's actual code path before asserting body shape.

## Related

- `apps/web-platform/scripts/run-migrations.sh:328-335` (runner pipe + ledger INSERT)
- `apps/web-platform/supabase/migrations/067_workspace_member_revocation_lookup.sql` (precedent — no explicit txn control)
- `apps/web-platform/supabase/migrations/068_attachments_workspace_shared.sql` (post-fix; up + down)
- `apps/web-platform/test/supabase-migrations/068-attachments-workspace-shared.test.ts` (inverted lint)
- PR #4417 (#4318) — the session this surfaced in
- PR-1 #4307 / mig 067 — established the no-explicit-txn precedent
