---
title: "Tasks — fix dsar-worm-guc-sites / run-migrations-unmerged-gate fixture race (#4957)"
date: 2026-06-05
issue: 4957
branch: feat-one-shot-4957-dsar-worm-migrations-fixture-race
lane: single-domain
plan: knowledge-base/project/plans/2026-06-05-fix-dsar-worm-migrations-fixture-race-plan.md
---

# Tasks — #4957 fixture-race fix

Derived from the finalized + deepened plan. Producer-side fix: remove the only writer into the
real `apps/web-platform/supabase/migrations/` dir so all four readdir-based readers stop racing.

## Phase 1 — Script seam (`run-migrations.sh`)

- [x] 1.1 Edit `apps/web-platform/scripts/run-migrations.sh` line 64 to
  `MIGRATIONS_DIR="${RUN_MIGRATIONS_TEST_DIR:-$SCRIPT_DIR/../supabase/migrations}"` with the
  comment block from the plan (explains the test-scoped name + the canonical-path gate anchor).
- [x] 1.2 Do NOT touch the `git ls-tree origin/main -- "apps/web-platform/supabase/migrations/$filename"`
  predicate (line 200) — it stays anchored to the canonical path (basename-only lookup).
- [x] 1.3 Verify the script parses: `bash -n apps/web-platform/scripts/run-migrations.sh`.

## Phase 2 — Gate test stages a temp dir (`run-migrations-unmerged-gate.test.ts`)

- [x] 2.1 In `beforeAll`: `mkdtempSync(join(tmpdir(), "run-migrations-gate-"))`, then
  `cpSync(realMigrationsDir, tempDir, { recursive: true })` (precedent:
  `legal-doc-shas-guard.test.ts:32,39`). Track the temp dir for sweep.
- [x] 2.2 Write the synthetic `zzz_unmerged_gate_<hex>.sql` into the **temp** dir (not the real
  dir). Keep the `zzz_` prefix + randomized suffix.
- [x] 2.3 Pass `RUN_MIGRATIONS_TEST_DIR: <tempDir>` in the `runScript` `env` object alongside the
  existing `PATH` stub.
- [x] 2.4 Point `SYNTHETIC_MIGRATION` at the temp dir; keep the three assertions unchanged (they
  match the basename + `::error::`/`::warning::` contract).
- [x] 2.5 Replace the real-dir `beforeAll` atomic-create precondition (O_CREAT|O_EXCL, lines
  124-140) with the temp-dir staging; change `sweep` to `rmSync(tempDir, { recursive: true, force: true })`
  (precedent: same file's `stubDirs` sweep, line 113). Keep `process.on("exit", sweep)` +
  `afterAll(sweep)`.

## Phase 3 — (Optional, default OFF) consumer-side belt-and-braces

- [ ] 3.1 SKIP by default. Only if review requests defense-in-depth: add
  `&& !f.startsWith("zzz_unmerged_gate_")` to the `readdirSync` filter in ALL FOUR readers
  (`dsar-worm-guc-sites`, `dsar-message-redact-fields-sweep`, `migration-rpc-grants`,
  `dsar-allowlist-completeness`) — never just one (AC6).

## Phase 4 — Verify

- [x] 4.1 `cd apps/web-platform && ./node_modules/.bin/vitest run test/scripts/run-migrations-unmerged-gate.test.ts` → 3/3 pass (AC2).
- [x] 4.2 Co-location run (one process, producer + all 4 readers):
  `./node_modules/.bin/vitest run test/dsar-worm-guc-sites.test.ts test/dsar-message-redact-fields-sweep.test.ts test/migration-rpc-grants.test.ts test/dsar-allowlist-completeness.test.ts test/scripts/run-migrations-unmerged-gate.test.ts`
  → all pass, no ENOENT.
- [x] 4.3 `scripts/test-all.sh webplat` 5× (loop), green each time; capture exit codes for AC5.
- [x] 4.4 `git status --porcelain apps/web-platform/supabase/migrations/` empty (AC4);
  `ls apps/web-platform/supabase/migrations/zzz_* 2>/dev/null` empty.

## Ship

- [ ] 5.1 PR body uses `Closes #4957` (body, not title) (AC7).
- [ ] 5.2 Paste the 5 webplat exit codes (AC5) into the PR body.
- [ ] 5.3 No post-merge operator steps — merge is the only action.
