# Tasks: migration-immutability guard — fail PRs that mutate on-main supabase/migrations files (#8583)

Source plan: `knowledge-base/project/plans/2026-09-22-feat-migration-immutability-guard-plan.md`

## Phase 1: Guard script + companion suite

- [ ] 1.1 Create `apps/web-platform/scripts/lint-migration-immutability.sh`:
  - Modes: `--from-pr-diff` (CI; base = `origin/${BASE_REF:-main}`, head = HEAD, best-effort
    `git fetch --quiet --no-tags origin main || true`) and `--base <ref> --head <ref>
    [--repo <dir>]` (tests/local; no fetch in explicit mode).
  - `_assert_repo_root`-style check: resolved root must contain
    `apps/web-platform/supabase/migrations` (exit 2 otherwise).
  - `git rev-parse --verify "<base>^{commit}"` else exit 2 (fail closed on cannot-measure).
  - Enumerate `git -C "$REPO_ROOT" diff --no-renames --name-only "<base>...<head>" --
    'apps/web-platform/supabase/migrations/*.sql'`; exclude `*.down.sql` paths.
  - Per path: `git ls-tree <base> -- <path>` empty → skip (not on main → free); non-empty →
    compare mode+blob sha vs `git ls-tree <head> -- <path>`; difference → `::error::` naming the
    basename + remediation ("land the change as a new `NNN_*.sql` — on-main migration files are
    immutable, #8583").
  - Print a per-run checked-count line; pass arms print the literal `migration-immutability: clean`.
  - Exit 0 clean / 1 violations / 2 cannot-measure-or-invocation-error.
- [ ] 1.2 Create `apps/web-platform/scripts/lint-migration-immutability.test.sh`:
  - Synthesized fixture repo under `mktemp -d` (`git init`, commit on-main migrations, branch, apply
    mutations) — never write fixtures into the real migrations tree (`cq-test-fixtures-synthesized-only`).
  - Cases: modify on-main → rc 1 names file; delete on-main → rc 1; `git mv` rename → rc 1
    (regresses the `--no-renames` load-bearing flag); add-collides (`A` status, path exists on base
    with different blob) → rc 1; new file beyond max → rc 0; on-main `*.down.sql` edit → rc 0;
    bogus `--base` → rc 2; no migration changes → rc 0.
  - Wiring assertion: `grep -q 'lint-migration-immutability'
    "$REPO_ROOT/.github/workflows/tenant-integration.yml"` (guard's own dispatch).
  - Vacuity arm: when the fixture diff touches migrations, assert the run reports ≥1 checked file —
    a bare "0 checked, exit 0" must not be reachable.
  - Call-site-incremented case counter + assertion floor per `guard-vacuity-floor.test.sh` shape.

## Phase 2: Workflow wiring

- [ ] 2.1 `.github/workflows/tenant-integration.yml`: add step
  `Assert on-main migration files immutable` to the `detect-changes` job AFTER the `filter` step:
  `env: BASE_REF: ${{ github.base_ref }}` + `run: bash apps/web-platform/scripts/lint-migration-immutability.sh --from-pr-diff`.
  No event gate — on push-to-main the diff is empty (clean no-op); on `merge_group` it re-checks
  against fresh `origin/main`.
- [ ] 2.2 Extend the `detect-changes` anchor alternation (~line 111) with
  `apps/web-platform/scripts/lint-migration-immutability` so guard edits self-trigger the heavy suite.

## Phase 3: Baselines + verification

- [ ] 3.1 `bash apps/web-platform/scripts/lint-migration-immutability.test.sh` → green.
- [ ] 3.2 `bash plugins/soleur/test/fixture-relative-assert.test.sh` and
  `bash plugins/soleur/test/fixture-dir-operand-assert.test.sh` — if either baseline moved, regen
  via that suite's `--write-baseline` in the same commit and inspect the diff for only-expected rows.
- [ ] 3.3 `bash scripts/lint-orphan-test-suites.sh` → green (auto-glob registration confirmed).
- [ ] 3.4 `git diff --name-only origin/main...HEAD` lists only the Files to Edit/Create plus
  `knowledge-base/` artifacts.
- [ ] 3.5 PR body carries `Closes #8583` on its own line; verify the new step appears in this PR's
  `detect-changes` run log printing `migration-immutability: clean`.

## Out of scope

- Dev-ledger self-mutation arm (PR applies its own unmerged migration then edits it) — post-section
  re-probe stays `::warning::`-only on PR surfaces; follow-up issue to be filed at work/ship time.
- Any new required-check registration (deliberately avoided — guard rides `detect-changes` →
  `tenant-integration-required`).
