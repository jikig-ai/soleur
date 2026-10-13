---
title: "fix: dsar-worm-guc-sites races run-migrations-unmerged-gate synthetic fixture in real migrations dir (ENOENT)"
date: 2026-06-05
type: fix
issue: 4957
branch: feat-one-shot-4957-dsar-worm-migrations-fixture-race
lane: single-domain
brand_survival_threshold: none
status: planned
---

# fix: dsar-worm-guc-sites races run-migrations-unmerged-gate fixture in real migrations dir (ENOENT) 🐛

Closes #4957.

## Enhancement Summary

**Deepened on:** 2026-06-05
**Sections enhanced:** Overview, Research Reconciliation, Phase 1, Phase 2, AC3, Risks, Sharp Edges

### Key Improvements (deepen-plan pass)

1. **Env-var name hardened** `MIGRATIONS_DIR` → `RUN_MIGRATIONS_TEST_DIR` — the generic name
   risked silent collision with a same-named Doppler-`prd` secret injected by `doppler run` in
   the prod migrate step. Test-scoped name is collision-proof by construction.
2. **Verify-the-negative pass** confirmed all three load-bearing claims against live code: the
   gate predicate interpolates only `basename` (`run-migrations.sh:157,200`); `zzz_*` is absent
   from origin/main (`git ls-tree` empty); no prod/CI caller passes the override
   (`web-platform-release.yml:57` + `tenant-integration.yml` set only `DOPPLER_TOKEN`).
3. **Precedent-diff gate** confirmed the temp-dir staging is NOT novel — it is the exact
   `mkdtempSync`+`cpSync`+`rmSync` idiom already at `legal-doc-shas-guard.test.ts:32,39,67` and
   already used by the gate test's own psql-stub lifecycle (lines 51,54,113).

### New Considerations Discovered

- Sibling scripts `lint-migration-fk-preconditions.sh` / `preflight-schema-vs-ledger.sh` carry
  their own hardcoded `MIGRATIONS_DIR` and are NOT callers of `run-migrations.sh` — unaffected.
- Two prod invocation sites exist (release + tenant-integration); both verified env-clean.

## Overview

`scripts/test-all.sh webplat` (the local full-suite exit gate) intermittently fails with
`ENOENT: no such file or directory, open '.../supabase/migrations/zzz_unmerged_gate_<hex>.sql'`.

The named file is a **synthetic test fixture** that
`apps/web-platform/test/scripts/run-migrations-unmerged-gate.test.ts` creates inside the
**real** `apps/web-platform/supabase/migrations/` directory and deletes in `afterAll`. Four
sibling suites enumerate that same real directory with `readdirSync(...)` and then
`readFileSync` each entry. When the local `vitest run` (no `--shard`) runs the producer suite
and a reader suite concurrently across forked workers, the reader lists the synthetic `zzz_*`
file, the producer's `afterAll` `unlinkSync`s it, and the reader's `readFileSync` hits ENOENT.

This is a **shared-mutable-directory test-isolation bug**, independent of all product code.
Main CI is green because the webplat job sets `VITEST_SHARD` (`scripts/test-all.sh:157-158`),
splitting the producer and readers across separate shard processes that never co-execute. The
local path (`VITEST_SHARD` unset → plain `vitest run` over all 470+ files) is the only place
the two suites land in the same process tree, so it is the only place the race fires.

**Chosen fix: producer-side elimination (issue Option 2), adapted to the SUT's path coupling.**
The producer is the *single* writer into the real migrations dir; every reader (4 today, N
tomorrow) is a passive victim. Removing the one write surface closes the entire race class at
once, whereas a consumer-side guard (issue Option 1) would have to be applied to all four
readers and re-applied to every future reader. Option 2 is structurally the YAGNI-correct
choice here because the producer count is exactly 1.

**Critical adaptation surfaced at plan time (see Research Reconciliation):** the issue's
Option 2 prose ("point the SUT at a temp migrations dir") is **not directly achievable** —
`run-migrations.sh` hardcodes both its glob root (`MIGRATIONS_DIR="$SCRIPT_DIR/../supabase/migrations"`,
line 63-64) and its gate predicate path (`git ls-tree origin/main -- "apps/web-platform/supabase/migrations/$filename"`,
line 200), with no dir-override env var. Pointing the SUT at a temp dir therefore requires a
**production-script change** (adding an env override and keeping the `git ls-tree` predicate
anchored to the canonical path) — a larger blast radius than the issue implies. The plan
accounts for this by choosing the **lowest-blast-radius variant of Option 2**: add a single
optional **`RUN_MIGRATIONS_TEST_DIR`** env override to the script (defaulting to current
behavior, zero change for prod/CI callers) and have the gate test stage a temp dir containing
real-`*.sql` copies plus the synthetic file. The real migrations dir is never written to again.
A test-scoped env-var name (not the generic `MIGRATIONS_DIR`) is chosen so the override can
never be tripped by an unrelated same-named secret injected via `doppler run` in the prod
migrate step.

## Research Reconciliation — Spec vs. Codebase

| Claim (issue body) | Reality (verified against branch HEAD) | Plan response |
| --- | --- | --- |
| Race is between `dsar-worm-guc-sites.test.ts` and `run-migrations-unmerged-gate.test.ts` | Confirmed. Producer writes `zzz_*` via `openSync` (`gate.test.ts:127-140`); `dsar-worm-guc` does unguarded `readFileSync` in its top-level collection loop (`dsar-worm-guc-sites.test.ts:131-133`, outside any try/catch). | Fix the producer; this reader (and 3 others) become safe automatically. |
| Only `dsar-worm-guc` reads the dir | **Four** suites `readdirSync` the real dir and `readFileSync` each entry: `dsar-worm-guc-sites`, `dsar-message-redact-fields-sweep`, `migration-rpc-grants`, `dsar-allowlist-completeness`. All let `zzz_*.sql` pass their `.sql` filter. | Confirms producer-side is the correct lever (1 producer fixes 4+ readers). Option 1 on a single reader would leave 3 racing. |
| Option 2: "point the SUT at a temp migrations dir … without losing fidelity" | **Not directly achievable.** `run-migrations.sh` hardcodes the glob root (L63-64) *and* the `git ls-tree origin/main -- apps/web-platform/supabase/migrations/$filename` predicate (L200, where `filename="$(basename "$migration_file")"` at L157 — basename only). No dir override exists. | Add an optional **`RUN_MIGRATIONS_TEST_DIR`** env override to the script (default unchanged). Keep the gate predicate path literal — it interpolates only the basename, which for `zzz_*` is absent from origin/main, so `git ls-tree` returns empty and the gate still fires. See Phase 1. **Deepen note:** a generic `MIGRATIONS_DIR` name was rejected — too collision-prone with a possible Doppler-`prd` secret of the same name that `doppler run` would inject into the `web-platform-release.yml` migrate step's env (verified no such secret exists today, but the test-scoped name is collision-proof by construction). |
| `isolate: true` on the unit project should prevent this | `isolate: true` (`vitest.config.ts`) gives each file a fresh module graph / process, but does **not** isolate a shared on-disk directory. Forked workers share the real filesystem. | Isolation is irrelevant to this bug; the fix must remove the shared write surface, not rely on isolate. |
| CI green / local red | Confirmed. `scripts/test-all.sh:157-158` forwards `VITEST_SHARD` (set in CI matrix, unset locally). Sharding splits producer/readers across processes in CI; local unsharded `vitest run` co-locates them. | No CI workflow change needed; fix is in test/script source only. |
| Pre-existing, not caused by PR #4954 | `gh pr view 4954 --json files` → zero files under `apps/web-platform/test/` or `.../supabase/`. | Treat as pre-existing flake; no regression introduced by the discovering PR. |

## User-Brand Impact

**If this lands broken, the user experiences:** nothing user-facing — this is a developer-only
test-isolation flake in the local full-suite gate. A broken fix would, at worst, leave the
local `test-all.sh webplat` shard intermittently red (the status quo) or, in the bad case,
write a stray `zzz_*.sql` into the real migrations dir that a developer accidentally commits.
The plan's AC explicitly guards the no-stray-file invariant.

**If this leaks, the user's data/workflow/money is exposed via:** N/A — no user data, secret,
or runtime surface is touched. The change is confined to a test file and a dev/CI migration
script's directory-resolution logic (which already runs only against dev/CI databases behind
the `ALLOW_UNMERGED_DEV_APPLY` + `git ls-tree` gates).

**Brand-survival threshold:** none — developer-tooling reliability fix, no production code path,
no regulated-data surface. (Sensitive-path scope-out: `threshold: none, reason: change is
limited to test files plus a dev/CI migration script's MIGRATIONS_DIR resolution; no schema
DDL, auth flow, API route, or user-data surface is modified.`)

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1 — Race eliminated at the source.** `run-migrations-unmerged-gate.test.ts` no longer
  writes any `*.sql` file into `apps/web-platform/supabase/migrations/`. Verify:
  `grep -nE "join\(MIGRATIONS_DIR|supabase/migrations" apps/web-platform/test/scripts/run-migrations-unmerged-gate.test.ts`
  returns **no** line where a synthetic file is `openSync`/`writeFileSync`/`writeSync`-created
  under the real dir. (The const `MIGRATIONS_DIR` may remain referenced only for copying real
  `*.sql` *out* of the real dir into the temp staging dir.)
- [ ] **AC2 — Gate test still asserts the same three contracts.** The three `test(...)` cases
  (gate-blocks-exit-1, ack-warns-exit-0, positive-control) still exist and pass against the
  temp-dir staging. Verify: `./node_modules/.bin/vitest run test/scripts/run-migrations-unmerged-gate.test.ts`
  from `apps/web-platform/` → all tests pass; output contains the three case titles unchanged
  in intent.
- [ ] **AC3 — Production/CI callers unchanged.** `run-migrations.sh` with no
  `RUN_MIGRATIONS_TEST_DIR` env set resolves to `"$SCRIPT_DIR/../supabase/migrations"` exactly
  as before. Verify: `grep -nE 'MIGRATIONS_DIR=' apps/web-platform/scripts/run-migrations.sh`
  shows the override form is
  `MIGRATIONS_DIR="${RUN_MIGRATIONS_TEST_DIR:-$SCRIPT_DIR/../supabase/migrations}"` (default
  preserves current behavior). Verify no caller passes it:
  `grep -rn 'RUN_MIGRATIONS_TEST_DIR' .github/ apps/web-platform/ | grep -v 'test/'` →
  only the script's own default assignment.
- [ ] **AC4 — No stray fixture in the real dir after a full run.** After running the gate suite
  (and a full `vitest run`), `git status --porcelain apps/web-platform/supabase/migrations/`
  is empty and `ls apps/web-platform/supabase/migrations/zzz_* 2>/dev/null` returns nothing.
- [ ] **AC5 — Local full-suite shard is green and stable.** `scripts/test-all.sh webplat`
  (no `VITEST_SHARD`) passes across **≥5 consecutive runs** with zero ENOENT on a
  `supabase/migrations/zzz_*` path. Capture the 5 exit codes in the PR body.
- [ ] **AC6 — Reader suites unmodified (or, if any consumer-side belt-and-braces guard is
  added, scoped to all four readers).** Default plan modifies only the producer + script;
  if a defensive readdir-filter is added (see Phase 3, optional), it MUST be applied to all
  four readers (`dsar-worm-guc-sites`, `dsar-message-redact-fields-sweep`, `migration-rpc-grants`,
  `dsar-allowlist-completeness`), not just the one in the issue title. Default: no reader
  changes.
- [ ] **AC7 — PR body uses `Closes #4957`** (in body, not title).

### Post-merge (operator)

- [ ] None. Pure test/dev-script change; merge to main is the only required action. CI
  re-runs the webplat shards on the PR.

## Implementation Phases

### Phase 1 — Add an optional `RUN_MIGRATIONS_TEST_DIR` override to `run-migrations.sh`

**File to edit:** `apps/web-platform/scripts/run-migrations.sh`

- Change line 64 from:
  ```bash
  MIGRATIONS_DIR="$SCRIPT_DIR/../supabase/migrations"
  ```
  to:
  ```bash
  # Default to the real dir; tests may override via RUN_MIGRATIONS_TEST_DIR to
  # a temp staging dir so they never write transient *.sql into the real
  # migrations tree (#4957). The git ls-tree gate (below) intentionally stays
  # anchored to the canonical repo path — a temp-dir filename absent from
  # origin/main still trips the gate, which is exactly what the gate test
  # exercises. A test-scoped var name (not MIGRATIONS_DIR) avoids any collision
  # with a same-named secret a future Doppler config might inject via
  # `doppler run` in the prod migrate step.
  MIGRATIONS_DIR="${RUN_MIGRATIONS_TEST_DIR:-$SCRIPT_DIR/../supabase/migrations}"
  ```
- **Do NOT** change the gate predicate at line 200
  (`git ls-tree origin/main -- "apps/web-platform/supabase/migrations/$filename"`). It uses
  only the *basename* (`filename="$(basename "$migration_file")"` at line 157), and a synthetic
  `zzz_*` basename is absent from origin/main regardless of where the glob rooted — so the gate
  still fires. This preserves the test's existing assertions verbatim. (Verified: `git ls-tree
  origin/main -- apps/web-platform/supabase/migrations/ | grep zzz_unmerged` → empty.)
- Verify the script still parses: `bash -n apps/web-platform/scripts/run-migrations.sh`.

**Why a script change is unavoidable:** the SUT has no dir-injection seam today (confirmed:
`grep -n 'MIGRATIONS_DIR' run-migrations.sh` shows only the hardcoded assignment at L64). The
override is the minimal seam; defaulting via `${VAR:-...}` makes it a strict no-op for every
existing caller. **Callers verified (deepen pass):** `web-platform-release.yml:57`
(`doppler run -c prd -- bash …run-migrations.sh`, env = `DOPPLER_TOKEN` only) and
`tenant-integration.yml` — neither sets `RUN_MIGRATIONS_TEST_DIR`; default behavior preserved.
The sibling scripts `lint-migration-fk-preconditions.sh` and `preflight-schema-vs-ledger.sh`
each carry their *own* hardcoded `MIGRATIONS_DIR` (they are not callers of `run-migrations.sh`)
and are unaffected.

### Phase 2 — Rewrite the gate test to stage a temp migrations dir

**File to edit:** `apps/web-platform/test/scripts/run-migrations-unmerged-gate.test.ts`

- In `beforeAll`: `mkdtempSync(join(tmpdir(), "run-migrations-gate-"))`, then copy every real
  `*.sql` from the real `MIGRATIONS_DIR` into the temp dir (`copyFileSync` per file, or
  `cpSync(realDir, tempDir, { recursive: true })`). Track the temp dir for `afterAll` sweep
  (reuse the existing `stubDirs`-style tracking array, or a new `tempMigrationsDir` var).
- Write the synthetic `zzz_unmerged_gate_<hex>.sql` into the **temp** dir (not the real dir).
  Keep the randomized suffix and the `zzz_` prefix (so it still sorts last under the glob).
- In `runScript`, pass `RUN_MIGRATIONS_TEST_DIR: <tempDir>` in the `env` object handed to
  `spawnSync`, alongside the existing `PATH` stub. The script's Phase-1 override then roots its
  `*.sql` glob at the temp dir, sees the synthetic file there, and the `git ls-tree` gate (still
  anchored to the canonical repo path) returns empty for `zzz_*` → gate fires, exactly as today.
- Update `SYNTHETIC_MIGRATION` to point at the temp dir; the three assertions remain unchanged
  (they match on the basename `SYNTHETIC_FILE` and the `::error::`/`::warning::` contract, not
  on the absolute path).
- Keep the `process.on("exit", sweep)` + `afterAll(sweep)` belt-and-braces, but the sweep now
  `rmSync(tempDir, { recursive: true, force: true })` instead of `unlinkSync`ing a file in the
  real dir. The `beforeAll` precondition (atomic `O_CREAT|O_EXCL` against the real dir, lines
  124-140) becomes unnecessary — there is no longer a real-dir file to collide with; replace it
  with the temp-dir staging. (A leftover temp dir under `os.tmpdir()` from a crashed run is
  harmless and `mkdtempSync` is collision-free by construction.)
- **Fidelity check:** the positive-control test references `KNOWN_MERGED_FILE =
  "053_template_authorizations.sql"`. Because we copy *all* real `*.sql` into the temp dir, the
  merged file is present in the glob and its `git ls-tree` lookup (canonical path) still returns
  non-empty → control still passes. No fidelity loss.

**Pseudocode shape (illustrative, not load-bearing):**
```ts
// beforeAll
tempMigrationsDir = mkdtempSync(join(tmpdir(), "run-migrations-gate-"));
cpSync(REAL_MIGRATIONS_DIR, tempMigrationsDir, { recursive: true }); // real *.sql copied in
writeFileSync(join(tempMigrationsDir, SYNTHETIC_FILE),
  "-- synthetic test migration; never on origin/main.\nSELECT 1;\n");

// runScript env
env: { ...process.env, ...env, RUN_MIGRATIONS_TEST_DIR: tempMigrationsDir, PATH: `${stubDir}:...` }

// sweep / afterAll
rmSync(tempMigrationsDir, { recursive: true, force: true });
```

**Precedent (deepen-plan Phase 4.4 — pattern is NOT novel).** This is the canonical temp-dir
staging idiom already in this test directory:
- `apps/web-platform/test/legal-doc-shas-guard.test.ts:32,39,67` — exact
  `mkdtempSync(join(tmpdir(), "..."))` → `cpSync(real, tmp, { recursive: true })` →
  `rmSync(tmp, { recursive: true, force: true })` sequence the plan adopts verbatim.
- The gate test **itself already** uses `mkdtempSync(join(tmpdir(), "psql-stub-"))` for the
  psql stub (line 54), tracks dirs in `stubDirs[]` (line 51), and sweeps via
  `rmSync(dir, { recursive: true, force: true })` (line 113). The new temp migrations dir
  reuses the file's own established lifecycle — no new pattern introduced.

### Phase 3 — (Optional, default OFF) defensive readdir filter on all four readers

Default: **skip.** Phase 1+2 fully closes the race by removing the only writer. A consumer-side
filter is pure belt-and-braces and adds churn to four files. Only add if review explicitly
requests defense-in-depth. **If added, it MUST cover all four readers** (`dsar-worm-guc-sites`,
`dsar-message-redact-fields-sweep`, `migration-rpc-grants`, `dsar-allowlist-completeness`) with
the same one-line filter `&& !f.startsWith("zzz_unmerged_gate_")` on their `readdirSync(...)`
result, per AC6 — never just the one named in the issue title. (See Sharp Edges: applying it to
a single reader recreates the partial-coverage failure mode.)

### Phase 4 — Verify

- From `apps/web-platform/`: `./node_modules/.bin/vitest run test/scripts/run-migrations-unmerged-gate.test.ts`
  → 3/3 pass.
- From `apps/web-platform/`: `./node_modules/.bin/vitest run test/dsar-worm-guc-sites.test.ts test/dsar-message-redact-fields-sweep.test.ts test/migration-rpc-grants.test.ts test/dsar-allowlist-completeness.test.ts test/scripts/run-migrations-unmerged-gate.test.ts`
  in one process → all pass, no ENOENT (forces co-location of producer + all readers).
- From repo root: run `scripts/test-all.sh webplat` **5×** (loop), confirm green each time and
  capture exit codes for AC5.
- `git status --porcelain apps/web-platform/supabase/migrations/` empty (AC4).

## Files to Edit

- `apps/web-platform/scripts/run-migrations.sh` — change L64 to
  `MIGRATIONS_DIR="${RUN_MIGRATIONS_TEST_DIR:-$SCRIPT_DIR/../supabase/migrations}"` (Phase 1).
- `apps/web-platform/test/scripts/run-migrations-unmerged-gate.test.ts` — stage temp dir, write
  synthetic file there, pass `MIGRATIONS_DIR` env to the SUT, sweep temp dir (Phase 2).

## Files to Create

- None.

## Test Strategy

Runner: **vitest** (per `apps/web-platform/package.json` `test:ci = "vitest run"` and
`apps/web-platform/vitest.config.ts`; the `unit` project collects `test/**/*.test.ts` and
`isolate: true`). No new framework. The gate test stays under `test/scripts/` (matches the
`unit` project's `test/**/*.test.ts` glob). The verification step intentionally runs the
producer + all four readers in **one** `vitest run` invocation to reproduce the co-location that
the sharded CI path hides — a green run there is the canonical proof the race is gone.

### Research Insights

**Verification artifacts captured this pass (all against branch HEAD / origin/main):**

- Gate predicate is basename-scoped:
  ```
  run-migrations.sh:157  filename="$(basename "$migration_file")"
  run-migrations.sh:200  if [[ -z "$(git ls-tree origin/main -- "apps/web-platform/supabase/migrations/$filename" 2>/dev/null)" ]]; then
  ```
- Synthetic file absent from main: `git ls-tree origin/main -- apps/web-platform/supabase/migrations/ | grep zzz_unmerged` → (empty).
- Four readdir-based readers race the same dir (only consumer-side blast radius):
  `dsar-worm-guc-sites`, `dsar-message-redact-fields-sweep`, `migration-rpc-grants`,
  `dsar-allowlist-completeness`. One producer: `run-migrations-unmerged-gate.test.ts`.
- `isolate: true` (both `unit` and `component` projects, `vitest.config.ts`) gives per-file
  module-graph/process isolation but does NOT isolate the shared on-disk migrations dir — which
  is precisely why a producer-side fix (remove the write), not an isolation knob, is required.

**Pattern precedent (canonical, in-repo):** `legal-doc-shas-guard.test.ts` copies real source
into a `mkdtempSync` dir via `cpSync(..., { recursive: true })` and sweeps with
`rmSync(..., { recursive: true, force: true })` — the plan adopts this verbatim.

## Risks & Mitigations

- **`cpSync` of the whole migrations dir per run is I/O.** ~100 small `*.sql` files; negligible
  (< a few ms) and one-time in `beforeAll`. Mitigation: copy only `*.sql` (skip `.down.sql` is
  unnecessary — they're inert for the gate, but copying them keeps fidelity; either is fine).
- **`git ls-tree` path stays canonical while the glob roots elsewhere.** This is intentional and
  is the load-bearing fidelity property: the gate's job is to compare a *basename* against
  origin/main's canonical migrations path, independent of where the runner physically reads
  files. Verified against `run-migrations.sh:200` — the predicate interpolates only `$filename`
  (basename). Mitigation: AC2 asserts the three contracts still pass; the positive-control test
  proves a merged basename does not trip the gate.
- **A future env var could collide with the override.** Mitigated by choosing the test-scoped
  name `RUN_MIGRATIONS_TEST_DIR` (deepen-plan finding) rather than the generic `MIGRATIONS_DIR`.
  A generic name risked being silently honored if a Doppler `prd` secret of the same name were
  ever injected by `doppler run` in the `web-platform-release.yml` migrate step. Verified no such
  secret exists today; the test-scoped name makes the class impossible regardless. The override
  is opt-in and no prod/CI path sets it (confirmed via grep over `.github/` + `apps/web-platform/`).

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — developer test-isolation / tooling change. No user-facing
surface (Product NONE; no file under `components/**`, `app/**/page.tsx`, or `app/**/layout.tsx`).
No legal/compliance surface (no regulated-data write; the touched script already runs only
against dev/CI DBs behind existing gates). No infrastructure surface (no new server, secret,
vendor, cron, or persistent process — the migration script's *directory resolution* changes,
not any provisioned resource).

## Infrastructure (IaC)

N/A — no new infrastructure. The change edits a test file and adds an env-var default to an
existing dev/CI shell script. No Terraform, no new secret, no new vendor or runtime process.

## Observability

N/A — no new code-class file under `apps/*/server/`, `apps/*/src/`, `apps/*/infra/`, or
`plugins/*/scripts/`, and no new infrastructure surface. The change is a test file plus a
directory-resolution default in an existing dev/CI script. The race's *detection* signal is
already the local `scripts/test-all.sh webplat` shard turning red on ENOENT; AC5 makes "5×
green" the regression-proof. (Plan Phase 2.9 skip condition met: no observable runtime surface
is introduced.)

## Open Code-Review Overlap

None. (Checked open `code-review`-labeled issues against `Files to Edit`:
`apps/web-platform/scripts/run-migrations.sh` and
`apps/web-platform/test/scripts/run-migrations-unmerged-gate.test.ts` — no open scope-out
touches either path.)

## Sharp Edges

- **Do not "fix" only `dsar-worm-guc-sites`.** Three other suites
  (`dsar-message-redact-fields-sweep`, `migration-rpc-grants`, `dsar-allowlist-completeness`)
  read the same real dir and race the same fixture. A consumer-side guard on the single named
  reader leaves the race live for the other three — the exact partial-coverage trap the
  producer-side fix avoids. If review insists on belt-and-braces consumer guards (Phase 3),
  apply the filter to **all four** readers (AC6).
- **Do not change the `git ls-tree` predicate path.** It must stay anchored to the canonical
  `apps/web-platform/supabase/migrations/` path even when the glob roots at a temp dir — that
  decoupling is what lets the synthetic file trip the gate while the runner reads the temp dir.
  Repointing it to the temp dir would break the gate's semantics (a temp-dir path is never on
  origin/main *as a path*, but the gate compares basenames).
- **The override default must be `MIGRATIONS_DIR="${RUN_MIGRATIONS_TEST_DIR:-$SCRIPT_DIR/../supabase/migrations}"`,
  not a bare reassignment.** A bare `MIGRATIONS_DIR=$SCRIPT_DIR/...` would ignore the test's
  injected value; omitting the `:-` default would break prod (unset → empty dir). The `:-`
  default form with the test-scoped var name is the only correct shape (AC3 asserts it).
- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder
  text, or omits the threshold will fail `deepen-plan` Phase 4.6. (This plan's section is
  filled with threshold `none` + sensitive-path scope-out reason.)

## Alternative Approaches Considered

| Approach | Verdict | Rationale |
| --- | --- | --- |
| **Option 1 — consumer-side guard on `dsar-worm-guc-sites` only** | Rejected | Leaves 3 other readers racing; recreates the bug under any new reader. |
| **Option 1b — consumer-side guard on all 4 readers** | Fallback (Phase 3, default off) | Works, but 4-file churn + must be re-applied to every future reader; treats the symptom, not the shared-write surface. Kept as belt-and-braces only if review requests it. |
| **Option 2 — producer stages a temp dir (chosen)** | **Chosen** | Removes the single write surface; fixes all readers (current + future) at once. Requires a minimal `MIGRATIONS_DIR` override in the SUT (the issue's prose understated this; see Research Reconciliation). |
| Exclude the gate test from the `unit` project / mark it serial | Rejected | Hides the race rather than removing it; loses coverage or couples the fix to vitest scheduling internals. `isolate: true` already doesn't help (shared FS), and a serial/exclude hack is brittle across vitest versions. |
| Move all migration-reading suites to read a git-tracked snapshot instead of the live dir | Rejected (YAGNI) | Large refactor across 4+ suites for a problem the 2-file producer fix already closes. No deferral issue needed — superseded by the chosen fix. |
