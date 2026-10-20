---
title: "Tasks — feat: property-based testing adoption (issue #10398)"
date: 2026-10-19
branch: feat-one-shot-10398-property-based-testing
plan: knowledge-base/project/plans/2026-10-19-feat-property-based-testing-adoption-plan.md
---

# Tasks

Derived from `2026-10-19-feat-property-based-testing-adoption-plan.md` (post-review). AC numbers reference the plan's `## Acceptance Criteria`.

## Phase 1: Dependency + shell harness foundation

- [x] 1.1 `cd apps/web-platform && npm install --ignore-scripts --save-dev fast-check@^4.10.2` (AC1)
- [x] 1.2 Regenerate lockfile: `cd apps/web-platform && npx --yes npm@11 install --package-lock-only` (AC2)
- [x] 1.3 Write `scripts/lib/property-harness.sh` — `prop_init`/`prop_rand`/`prop_pick`/`prop_fail`/`prop_pass`, `PROP_SEED` + `PROP_RUNS` env, direct-execution + double-source guards (mirror `legal-normalise.sh:28-38`), `LC_ALL=C`, bash-3.2-safe, `set -u` only (sourced lib) (AC7, AC8)
- [x] 1.4 Write `scripts/lib/property-harness.md` — seeded loop, generator-over-token-alphabet (alphabet must enumerate every LHS transform of the SUT), shell property shapes, `PROP_SEED` replay, fixture convention, placement rules per suite home (AC8)

## Phase 2: Vitest property suites (RED → GREEN)

- [x] 2.1 `apps/web-platform/test/server/codex-app-server-jsonl.property.test.ts` — round-trip: `decodeCodexJsonlLine(encodeCodexJsonl(m)) ≡ m` over `fc.jsonObject()` (size-bounded); stream reassembly under arbitrary string-offset chunk splits; rejection taxonomy (`codex_rpc_frame_invalid`/`codex_rpc_frame_too_large`); >1 MiB example `it`; negative-control `it`; fixture-convention header (AC3–AC6, AC12)
- [x] 2.2 `apps/web-platform/test/lib/plan-limits.property.test.ts` — invariant: `effectiveCap` ∈ {base, override} ∧ ≥ base ∧ monotone in override; `nextTier` strict ladder + `null` at top; non-enterprise `PLAN_LIMITS` ≤ `PLATFORM_HARD_CAP`; negative control; header (AC3–AC6)
- [x] 2.3 `apps/web-platform/test/lib/repo-url.property.test.ts` — idempotency: `normalizeRepoUrl² ≡ normalizeRepoUrl` over `fc.string()` + `fc.webUrl()`-with-suffix arbs; output contract (self-trim, no trailing `/` or `(\.git)+$`); scheme/host lowercase + path-case preservation for URL inputs; negative control; header (AC3–AC6)
- [x] 2.4 `apps/web-platform/test/lib/log-sanitize.property.test.ts` — idempotency: `sanitizeForLog² ≡ sanitizeForLog`; `length ≤ n`; no `[\x00-\x1f\x7f\u2028\u2029]` in output; negative control; header (AC3–AC6)
- [x] 2.5 Trigger one deliberate local failure to confirm shrink/replay output (seed+path), then revert (AC13)
- [x] 2.6 `apps/web-platform/test/README.md` — add "Property-based tests" section: `*.property.test.ts` placement + regression-fixture convention (AC10)

## Phase 3: Shell reference suite + pointers

- [x] 3.1 `scripts/lib/legal-normalise-property.test.sh` — sources `legal-normalise.sh` + `property-harness.sh`; generated docs over the full `collapse` LHS alphabet; asserts `collapse² ≡ collapse` + residue-free (no LHS pattern in output); `PROP_RUNS=100` default (AC7)
- [x] 3.2 `.claude/hooks/README.md` — "Property tests" pointer paragraph naming `scripts/lib/property-harness.md` + the reference suite (AC8)

## Phase 4: Selection verification (no CI edits)

- [x] 4.1 `WEBPLAT_RELATED=$'server/codex-app-server-jsonl.ts' bash apps/web-platform/scripts/vitest-related.sh unit` → `outcome=related` + property file runs (AC9a)
- [x] 4.2 `bash scripts/test-all.sh --print-affected-set` → `scripts/lib/legal-normalise-property.test.sh` present with `edge:` class (AC9b)
- [x] 4.3 Fabricated diff touching `scripts/lib/legal-normalise.sh` selects the suite (`--print-selection` or `--affected` fixture conventions, per `test-all-affected.test.sh`) (AC9c)
- [x] 4.4 `bash scripts/lint-orphan-test-suites.sh` exits 0 (AC9d)
- [x] 4.5 AC15 probes: `--affected` on new-files-only diff selects `apps/web-platform [unit]` + the shell suite (AC15)

## Phase 5: Decision record

- [x] 5.1 Author `knowledge-base/engineering/architecture/decisions/ADR-293-property-based-testing-adoption.md` (provisional — renumber on collision and sweep `grep -rn 'ADR-293' knowledge-base/project/{plans,specs}/feat-one-shot-10398-property-based-testing/`) (AC11)

## Phase 6: Verify + ship

- [x] 6.1 Full AC sweep AC1–AC15; `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` (AC4)
- [x] 6.2 Confirm diff scope: `git diff origin/main...HEAD --name-only | grep -vE '(apps/web-platform/(package(-lock)?\.json|test/|lib/repo-url\.ts)|scripts/lib/|\.claude/hooks/README\.md|knowledge-base/)'` empty (AC14; `lib/repo-url.ts` is the sanctioned SUT fix — review round corrected the allowlist, which had omitted it)
