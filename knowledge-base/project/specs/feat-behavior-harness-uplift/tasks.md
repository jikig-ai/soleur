# Tasks: A2 Goldens + Secret-Scanning Safety Floor (Slice 1 of #3121)

> Plan: `knowledge-base/project/plans/2026-05-04-feat-a2-goldens-secret-scanning-floor-plan.md` (deepen-applied: best-practices, framework-docs, architecture-strategist, security-sentinel, test-design-reviewer, learnings-researcher)
> Spec: `knowledge-base/project/specs/feat-behavior-harness-uplift/spec.md`
> Brainstorm: `knowledge-base/project/brainstorms/2026-05-04-behavior-harness-uplift-brainstorm.md`
> Branch: `behavior-harness-uplift` | Draft PR: #3129 | Issue: #3121
> User-brand-critical: `single-user incident` threshold; CPO sign-off required before /work.
> Follow-ups filed: #3130 (A1 mutation), #3131 (A3 ATDD), #3132 (A4-lite fitness), #3133 (A4 p95), #3136 (agent-runner), #3143 (markdown-behavioral surface), #3144 (sql-builders-shape surface).

## PR1 — Safety Floor (~1 day, deepen-expanded scope)

### Phase 1.1: Setup

- 1.1.1 Confirm CPO sign-off captured (brainstorm Phase 0.1 inheritance is sufficient per plan SKILL.md Phase 2.6 tiered model)
- 1.1.2 Verify worktree state: `git status` clean, branch `behavior-harness-uplift`, draft PR #3129 open

### Phase 1.2: Author config + scripts

- 1.2.1 Create `.gitleaks.toml` at repo root using **v8.24.2-correct** syntax: `[extend] useDefault = true` + project rules with **per-rule `[[rules.allowlists]]`** (NOT top-level `[[allowlists]] + targetRules` which is v8.25+). Custom `[[rules]]` for ALL of: `soleur-byok-key`, `doppler-token` (`dp.pt./dp.st./dp.sa./dp.ct.`), `supabase-service-role-jwt` (HS256 + iss/role claim), `supabase-anon-jwt`, `supabase-access-token` (`sbp_`), `stripe-webhook-secret` (`whsec_`), `anthropic-api-key` (`sk-ant-`), `resend-api-key` (`re_`), `cf-scoped-token` (40-char alphanum), `sentry-auth-token` (`sntrys_`/`sntryu_`), `discord-webhook-url`, `database-url-with-password` (`postgres(ql)?://[^:]+:[^@]+@`), `vapid-private-key`. Allowlist paths: `__goldens__/.*`, `(__snapshots__|__goldens__)/.*\.snap$` (anchored to test dirs — NOT repo-wide), `apps/web-platform/test/__synthesized__/.*`, `reports/mutation/.*`. Per AC-1.
- 1.2.2 Create `.github/CODEOWNERS` requiring 2nd-reviewer for `.gitleaks.toml`, `.github/workflows/secret-scan.yml`, `.github/workflows/pr-quality-guards.yml`, `lefthook.yml`, `apps/web-platform/scripts/lint-fixture-content.mjs`, and `AGENTS.md`. Per AC-2. (Branch-protection enablement is operator follow-up.)
- 1.2.3 Create `.github/workflows/secret-scan.yml`: triggers `pull_request` (PR-diff via `--log-opts="--no-merges <base>..HEAD"`) + `push: branches: [main]` + `schedule: [cron: '0 6 * * 1']` (weekly). `permissions: contents: read` ONLY (drop `pull-requests: read`). Inline gitleaks v8.24.2 install with **hardcoded SHA256 literal in YAML** (curl + `sha256sum -c -` + tar). Use `--redact`. **Do NOT upload `--report-path` JSON as artifact.** Per AC-4.
- 1.2.4 Mkdir `apps/web-platform/scripts/` (brand-new dir); create `apps/web-platform/scripts/lint-fixture-content.mjs` (~50 lines, ESM Node). Scans staged file contents (`{staged_files}` from lefthook) for: real-email regex with `@(example\.com|example\.org|.+\.test|fixtures\.local)` allowlist; Supabase prod-shape UUIDs against synthesized allowlist; Supabase project-ref pattern (`[a-z0-9]{20}\.supabase\.co`). Honors `# gitleaks:allow` AND `// gitleaks:allow` line-level waivers; rejects waivers with empty `issue:#NNN <reason>` trailer. Per AC-5.
- 1.2.5 Mkdir `apps/web-platform/test/__synthesized__/` and add `.gitkeep` (NEW dir for fixtures that may contain semi-sensitive shapes; replaces broad `apps/web-platform/test/fixtures/.*` allowlist).

### Phase 1.3: Wire hooks + .gitignore

- 1.3.1 Edit `lefthook.yml` `pre-commit` block: add `gitleaks-staged` command (`gitleaks git --pre-commit --staged --redact --no-banner --exit-code 1`, slot priority 4-5, no `glob:` filter — gitleaks scans the index itself). Per AC-3.
- 1.3.2 Edit `lefthook.yml` `pre-commit` block: add `lint-fixture-content` command with **path-array `glob:`** (NOT `**/*` — gobwas semantics silently no-op without explicit subdirs; per learning `2026-03-21-lefthook-gobwas-glob-double-star.md`). Separate from gitleaks per plan.
- 1.3.3 Append `.gitignore` with `reports/mutation/`, `.stryker-tmp/`, `mutants/`. Per AC-6.

### Phase 1.4: Documentation

- 1.4.1 Create `knowledge-base/engineering/operations/secret-scanning.md` with required sections (per AC-7): rule pack inventory; per-rule vs default-rule allowlist semantics; `# gitleaks:allow` waiver discipline (mandatory `issue:#NNN <reason>`); `--no-verify` bypass + CI backstop; **post-merge per-token rotation runbook + decision tree + notification flow**; **forensics workflow** (local re-run with offending commit SHA — explains why no artifact upload); rule-pack-update workflow (weekly cron rationale).

### Phase 1.5: Smoke tests + verification

- 1.5.1 Add **5 smoke-test fixtures** to `secret-scan.yml` (per AC-9, includes rename case from security-sentinel §3):
  1. allowlist-positive (golden path with JWT — expect pass)
  2. allowlist-negative (server path with same JWT — expect fail)
  3. linter-positive (golden with real email — expect fail)
  4. linter-waiver (golden with real email + `# gitleaks:allow # issue:#3121 fixture`)
  5. **rename-laundering** (`git mv` of a previously-non-allowlisted file containing a fake JWT INTO `__goldens__/` — documents v8.24.2 actual behavior; if rename launders, R9 mitigation kicks in)
- 1.5.2 Push branch; verify all 5 smoke tests fire correctly in CI
- 1.5.3 Verify `[hook-enforced]` candidate text resolves to existing files (`ls lefthook.yml .github/workflows/secret-scan.yml apps/web-platform/scripts/lint-fixture-content.mjs .github/CODEOWNERS`)

### Phase 1.6: AGENTS.md edit (LAST step before PR1 ready)

- 1.6.1 Append `cq-test-fixtures-synthesized-only` to `AGENTS.md` `## Code Quality` section. Single-enforcer tag: `[hook-enforced: .github/workflows/secret-scan.yml]` (NOT lefthook — load-bearing enforcer per architecture-strategist pattern-consistency). Recount via `printf '%s' '<rule>' | wc -c` — expect 458 bytes (under 600-byte cap per `cq-agents-md-why-single-line`).
- 1.6.2 Run `python3 scripts/lint-rule-ids.py` to verify rule passes lint
- 1.6.3 Mark PR1 ready via `/ship`; secure user-impact-reviewer sign-off (per AC-10)
- 1.6.4 Auto-merge PR1 (`gh pr merge --squash --auto`)

## PR2 — Golden Convention + 2 Seed Surfaces (~half-day, scope-reduced from 4)

### Phase 2.1: Setup (after PR1 merges)

- 2.1.1 Rebase branch on main (or open from a fresh branch off main)
- 2.1.2 Open PR2 as draft

### Phase 2.2: Helper + hooks

- 2.2.1 Create `apps/web-platform/test/helpers/golden.ts` with single export `expectMatchesGolden(actual: string, goldenPath: string): Promise<void>`. Read-only by default; writes via `mkdirSync` + `writeFileSync` when `process.env.GOLDEN_REGEN === '1'`; throws actionable error message when golden missing in non-regen mode (point at trailer rule + exact regen command). Caller passes already-resolved absolute path (use `import.meta.url` + `dirname`). See plan §Code Skeletons. Per AC-11.
- 2.2.2 Edit `lefthook.yml`: add NEW `commit-msg` block (no precedent — only `pre-commit` exists today). `{1}` placeholder per context7-verified syntax. Hook script: `git diff --cached --name-only | grep -qE '__goldens__/' || exit 0; grep -qE '^Golden-Updated-By: .+' {1} || (echo '...' && exit 1)`. **Documented as UX-nicety only** (load-bearing gate is AC-13 CI guard). Per AC-12.
- 2.2.3 Create `.github/scripts/check-goldens-trailer.sh` mirroring `check-pr-body-vs-diff.sh` pattern: scans `git log <base>..HEAD --format=%B` for `^Golden-Updated-By: .+` in any commit OR scans PR body via `gh api`. Either source satisfies. Sanitize echoed values per learning `2026-03-05-github-output-newline-injection-sanitization.md`. Per AC-13. **Load-bearing gate.**
- 2.2.4 Edit `.github/workflows/pr-quality-guards.yml`: add `goldens-trailer-guard` job with path filter on `__goldens__/**`. Per AC-13.
- 2.2.5 Edit `.github/PULL_REQUEST_TEMPLATE.md`: add `Golden-Updated-By:` trailer field section (R3 mitigation — squash-merge can drop intermediate commit trailers). Per AC-15.

### Phase 2.3: Seed golden surfaces (2 surfaces; markdown + sql-builders deferred to #3143/#3144)

- 2.3.1 LLM-prompts surface: write `apps/web-platform/test/__goldens__/llm-prompts/soleur-go-baseline.test.ts` (snapshots `buildSoleurGoSystemPrompt` output for 2 arg permutations: baseline + with-artifact). **Drop replay-prompt sub-test** per test-design-reviewer (filed under follow-up scope; not in this surface). Per AC-14.
- 2.3.2 API-responses surface: write `apps/web-platform/test/__goldens__/api-responses/flags-route.no-auth.test.ts`. **Hardened per test-design-reviewer R5:** `vi.stubEnv` BEFORE dynamic `await import('@/app/api/flags/route')`; `vi.resetModules()` in `beforeEach`; `vi.unstubAllEnvs()` in `afterEach`. Inline 5-line shape assertion (key presence + types) instead of value comparison. Per AC-14.

### Phase 2.4: Generate goldens

- 2.4.1 Run `GOLDEN_REGEN=1 bun test apps/web-platform/test/__goldens__` to generate `*.golden.txt` / `*.golden.json` files for the 2 surfaces.
- 2.4.2 Verify generated goldens contain only synthesized data (manual review)
- 2.4.3 Run `bun test apps/web-platform/test/__goldens__` (without GOLDEN_REGEN) to confirm green

### Phase 2.5: Documentation

- 2.5.1 Create `knowledge-base/engineering/operations/golden-tests.md` documenting: regen recipe (`GOLDEN_REGEN=1 bun test <path>`); `Golden-Updated-By:` trailer template; `__goldens__/` directory-naming rationale (deliberate non-default to defeat `vitest --update` muscle memory); link to `secret-scanning.md` for bypass discussion. Per AC-16.

### Phase 2.6: Trailer-guard verification

- 2.6.1 Test commit-msg hook on `git commit --amend` (verify it re-fires)
- 2.6.2 Push commit with `__goldens__/` change but NO trailer; verify CI `goldens-trailer-guard` rejects
- 2.6.3 Push commit with trailer; verify guard accepts
- 2.6.4 Push commit with trailer in PR body only (no commit trailer); verify guard accepts

### Phase 2.7: Ship PR2

- 2.7.1 Mark PR2 ready via `/ship`
- 2.7.2 PR body contains `Closes #3121` (the umbrella)
- 2.7.3 Auto-merge PR2

## Cleanup (post-PR2 merge)

- 3.1 Verify all 7 follow-up issues (#3130, #3131, #3132, #3133, #3136, #3143, #3144) are accurately scoped against the shipped slice and milestoned correctly.
- 3.2 File branch-protection-on-main follow-up issue (operator action; AC-2 prerequisite for CODEOWNERS to be enforcement rather than convention).
- 3.3 Update `knowledge-base/product/roadmap.md` if Theme A is referenced in any phase row (per `wg-when-moving-issues-between-milestones`).
- 3.4 Run `cleanup-merged` to remove the worktree.
