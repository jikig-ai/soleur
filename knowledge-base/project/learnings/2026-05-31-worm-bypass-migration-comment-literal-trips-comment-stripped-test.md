# Learning: WORM-bypass migration COMMENT string literals trip the comment-stripped guardrail test

## Problem

The migration-shape guardrail tests for the WORM-bypass migrations (087, now 088)
assert the forward migration nowhere references the old privileged GUC:

```ts
const executable = sql.replace(/--[^\n]*/g, ""); // strips LINE comments only
expect(executable).not.toMatch(/session_replication_role/i);
```

The comment-strip removes `-- …` line comments but **not SQL string literals**.
`COMMENT ON FUNCTION … IS '…'` bodies are string literals, not comments, so any
mention of `session_replication_role` inside a `COMMENT ON FUNCTION` string
survives the strip and fails the assertion.

While writing migration 088 (mirroring 087's `session_replication_role →
app.worm_bypass` swap), the first `purge_workspace_member_actions` COMMENT
included the explanatory phrase `(was session_replication_role, superuser-only →
42501…)`. The test failed:

```
FAIL > no privileged GUC anywhere > forward migration never references session_replication_role
```

A raw `grep -c session_replication_role <file>` returned 6 (all the `--` header
lines + the one COMMENT string), which is misleading — only the COMMENT-string
occurrence is load-bearing for the test, because the test strips `--` lines.

## Solution

In the forward migration, never name the retired GUC literally in any
`COMMENT ON FUNCTION` string (or any other SQL string literal). Describe it
generically instead:

```sql
-- BAD  (string literal trips the comment-stripped test):
COMMENT ON FUNCTION … IS 'Privilege-free GUC (was session_replication_role …).';

-- GOOD:
COMMENT ON FUNCTION … IS 'Privilege-free GUC (replaces the prior superuser-only
  replica-role bypass that raised 42501 on managed Supabase).';
```

`-- …` header/inline comments may freely mention the old GUC (they are stripped
before the assertion). The `.down.sql` SHOULD reference it (the down test asserts
`expect(downExecutable).toMatch(/session_replication_role/i)`).

Verification one-liner that matches the test (NOT a raw grep):

```bash
sed 's/--.*//' <forward-migration>.sql | grep -c session_replication_role   # must be 0
```

## Key Insight

When a guardrail test strips comments before a negative `not.toMatch`
assertion, enumerate every SQL surface that is *not* a `--` comment — string
literals (`COMMENT ON …`, `RAISE LOG '…'`, `RAISE EXCEPTION '…'`), dollar-quoted
bodies, and identifiers all survive the strip. The forbidden token must be
absent from all of them, not just from the executable statements you were
focused on. A raw `grep -c` over-counts (includes the stripped `--` lines) and
mis-points; mirror the test's own strip (`sed 's/--.*//'`) when self-checking.

This also hardened the 088 test beyond the 087 pattern: added an
arm-`'on'` < write < re-arm-`'off'` **ordering** assertion (presence alone is
vacuous — a body that re-armed before the write would WORM-reject the write) and
a down-migration `not.toMatch(/app\.worm_bypass/i)` rollback-symmetry assertion.

## Session Errors

1. **`worktree-manager.sh create` blocked on interactive `Proceed? (y/n)`** — the
   Bash tool is non-interactive, so the first create (without `--yes`) hung.
   Recovery: piped `printf 'y\n'`; the one-shot path used `--yes`.
   **Prevention:** always pass `--yes` to `worktree-manager.sh create` in
   non-interactive/agent sessions.
2. **one-shot collision gate false-positive on closed contextual ref `#4696`** —
   the `#N` regex matched a closed predecessor citation and aborted the first
   `/soleur:one-shot` invocation. Recovery: re-invoked with `#4696` rewritten as
   `issue 4696` (no `#`), leaving only the open work-target `#4702` in `#N` form.
   **Prevention:** scrub closed contextual `#N` refs to non-hash phrasing before
   invoking one-shot (already documented in one-shot Step 0a.5 sharp edges +
   learning `2026-05-25-one-shot-closed-issue-gate-fires-on-contextual-refs`).
3. **`gh issue create` blocked: missing `--milestone`** (PreToolUse hook).
   Recovery: added `--milestone "Post-MVP / Later"` for the operational bug.
   **Prevention:** include `--milestone` on every `gh issue create` (already
   hook-enforced; not a workflow gap).
4. **`/tmp/<file>` did not persist between Bash tool calls** — a heredoc-written
   body-file was absent ("no such file or directory") on the next Bash
   invocation. Recovery: write the body-file and consume it (`gh issue create
   --body-file`) in the SAME Bash call. **Prevention:** never assume `/tmp`
   artifacts survive across separate Bash tool calls in this environment; write +
   use in one invocation, or write inside the repo worktree.
5. **Forward-migration COMMENT string literal tripped the comment-stripped test**
   (the subject of this learning). Recovery: reworded the COMMENT to avoid the
   literal `session_replication_role`. **Prevention:** see Solution above; the
   verification one-liner mirrors the test's `--`-strip.

## Tags
category: build-errors
module: apps/web-platform/supabase/migrations
related: 087_worm_bypass_privilege_independence, 088_worm_bypass_non_erasure_rpcs, "#4702", "#4709"
