# Tasks: A2 Goldens + Secret-Scanning Safety Floor (Slice 1 of #3121)

> Plan: `knowledge-base/project/plans/2026-05-04-feat-a2-goldens-secret-scanning-floor-plan.md`
> Spec: `knowledge-base/project/specs/feat-behavior-harness-uplift/spec.md`
> Brainstorm: `knowledge-base/project/brainstorms/2026-05-04-behavior-harness-uplift-brainstorm.md`
> Branch: `behavior-harness-uplift` | Draft PR: #3129 | Issue: #3121
> User-brand-critical: `single-user incident` threshold; CPO sign-off required before /work.

## PR1 — Safety Floor

### Phase 1.1: Setup

- 1.1.1 Confirm CPO sign-off captured (brainstorm Phase 0.1 inheritance is sufficient per plan SKILL.md Phase 2.6 tiered model)
- 1.1.2 Verify worktree state: `git status` clean, branch `behavior-harness-uplift`, draft PR #3129 open

### Phase 1.2: Author config + scripts

- 1.2.1 Create `.gitleaks.toml` at repo root: `[extend] useDefault = true`, project rules (`soleur-byok-key`, `doppler-token`, `supabase-jwt-issuer`), top-level `[[allowlists]]` with `targetRules = []` and the four scoped paths (`__goldens__/.*`, `.*\.snap$`, `apps/web-platform/test/fixtures/.*`, `reports/mutation/.*`)
- 1.2.2 Create `.github/workflows/secret-scan.yml`: triggers `pull_request` + `push: branches: [main]`; explicit `permissions: { contents: read, pull-requests: read }`; inline gitleaks v8.24.2 install (curl + sha256sum -c + tar); artifact upload on detection
- 1.2.3 Mkdir `apps/web-platform/scripts/`; create `apps/web-platform/scripts/lint-fixture-content.mjs` with regex sweep for real-emails + Supabase prod-shape UUIDs; honors `# gitleaks:allow` line-level waiver

### Phase 1.3: Wire hooks + .gitignore

- 1.3.1 Edit `lefthook.yml` `pre-commit` block: add `gitleaks` command (`gitleaks git --pre-commit --staged --redact --no-banner`, tags: security)
- 1.3.2 Edit `lefthook.yml` `pre-commit` block: add `lint-fixture-content` command (separate from gitleaks per plan)
- 1.3.3 Append `.gitignore` with `reports/mutation/`, `.stryker-tmp/`, `mutants/`

### Phase 1.4: Documentation

- 1.4.1 Create `knowledge-base/engineering/operations/secret-scanning.md` documenting: rule pack, top-level vs per-rule allowlist semantics, `# gitleaks:allow` waiver, `--no-verify` bypass + CI backstop, post-merge rotation runbook

### Phase 1.5: Smoke tests + verification

- 1.5.1 Add 4 smoke-test fixtures to `secret-scan.yml`: allowlist-positive (golden path with JWT), allowlist-negative (server path with same JWT), linter-positive (golden with real email), linter-waiver (golden with real email + `# gitleaks:allow`)
- 1.5.2 Push branch; verify all four smoke tests fire correctly in CI
- 1.5.3 Verify `[hook-enforced]` candidate text resolves to existing files (`ls lefthook.yml .github/workflows/secret-scan.yml apps/web-platform/scripts/lint-fixture-content.mjs`)

### Phase 1.6: AGENTS.md edit (LAST step before PR1 ready)

- 1.6.1 Append `cq-test-fixtures-synthesized-only` to `AGENTS.md` `## Code Quality` section (text in plan §AGENTS.md Rule Draft; recount via `printf '%s' '<rule>' | wc -c` — expect 488)
- 1.6.2 Run `python3 scripts/lint-rule-ids.py` to verify rule passes lint
- 1.6.3 Mark PR1 ready via `/ship`; secure user-impact-reviewer sign-off
- 1.6.4 Auto-merge PR1 (`gh pr merge --squash --auto`)

## PR2 — Golden Convention + 4 Surfaces

### Phase 2.1: Setup (after PR1 merges)

- 2.1.1 Rebase branch on main (or open from a fresh branch off main)
- 2.1.2 Open PR2 as draft

### Phase 2.2: Helper + hooks

- 2.2.1 Create `apps/web-platform/test/helpers/golden.ts` with single export `expectMatchesGolden(actual, goldenPath): Promise<void>` (read-only; writes when `GOLDEN_REGEN=1`; throws actionable message on missing golden)
- 2.2.2 Edit `lefthook.yml`: add NEW `commit-msg` block with Golden-Updated-By trailer enforcement; uses `grep -qE ... || exit 0` for safe no-op; `{1}` placeholder per context7-verified syntax
- 2.2.3 Create `.github/scripts/check-goldens-trailer.sh` mirroring `check-pr-body-vs-diff.sh` pattern: scans `git log <base>..HEAD --format=%B` OR PR body for `^Golden-Updated-By: .+`
- 2.2.4 Edit `.github/workflows/pr-quality-guards.yml`: add `goldens-trailer-guard` job with path filter on `__goldens__/**`
- 2.2.5 Edit `.github/PULL_REQUEST_TEMPLATE.md`: add `Golden-Updated-By:` trailer field section

### Phase 2.3: Seed golden surfaces

- 2.3.1 LLM-prompts surface: write `apps/web-platform/test/__goldens__/llm-prompts/soleur-go-baseline.test.ts` (snapshots `buildSoleurGoSystemPrompt` output for 2 arg permutations)
- 2.3.2 LLM-prompts surface: write `apps/web-platform/test/__goldens__/llm-prompts/replay-prompt.test.ts` (snapshots `buildReplayPrompt` for synthesized history)
- 2.3.3 Markdown surface: write `apps/web-platform/test/__goldens__/markdown/chat-message-bubble.test.tsx` (component test, 4 fixtures: plain/gfm-table/fenced-code/link-with-rel)
- 2.3.4 Markdown surface: write `apps/web-platform/test/__goldens__/markdown/eleventy-baseline.test.ts` (direct `markdown-it` import with default options, same 4 fixtures)
- 2.3.5 SQL-builders surface: write `apps/web-platform/test/__goldens__/sql-builders/lookup-conversation-supabase-chain.test.ts` (mocks `supabase().from()`, records call sequence as JSON)
- 2.3.6 API-responses surface: write `apps/web-platform/test/__goldens__/api-responses/flags-route.no-auth.test.ts` (stubs env via `vi.stubEnv`, invokes `/api/flags` in-process, inline 5-line shape assertion)

### Phase 2.4: Generate goldens

- 2.4.1 Run `GOLDEN_REGEN=1 bun test apps/web-platform/test/__goldens__` to generate all `*.golden.*` files
- 2.4.2 Verify generated goldens contain only synthesized data (manual review)
- 2.4.3 Run `bun test apps/web-platform/test/__goldens__` (without GOLDEN_REGEN) to confirm green

### Phase 2.5: Documentation

- 2.5.1 Create `knowledge-base/engineering/operations/golden-tests.md`: regen recipe, trailer template, `__goldens__/` rationale, link to secret-scanning.md

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

- 3.1 Verify all 5 follow-up issues (#3130, #3131, #3132, #3133, #3136) are accurately scoped against the shipped slice
- 3.2 Update `knowledge-base/product/roadmap.md` if Theme A is referenced in any phase row (per `wg-when-moving-issues-between-milestones`)
- 3.3 Run `cleanup-merged` to remove the worktree
