# Feature: Behavior Harness Uplift — A2 Goldens + Secret-Scanning Floor

> **Slice 1 of #3121** (Theme A from the harness engineering audit, PR #3119). A1, A3, A4-lite, A4-p95 are tracked in separate follow-up issues.
> Brand-survival threshold: `single-user incident` (inherited from brainstorm User-Brand Impact section).

## Problem Statement

Soleur has zero behavior-harness infrastructure today: no mutation testing, no golden/snapshot convention, no fitness functions in CI. The Fowler harness engineering audit (#3119) explicitly called the behavior layer "not good enough yet" — the weakest of his three regulation categories. Worse, the repo has zero secret-scanning infrastructure (CodeQL is SAST for code paths, not fixture content). Adding any snapshot or mutation tooling without a secret-scanning floor in place creates an irreversible failure mode: a snapshot inadvertently containing real credential material (BYOK API key fragment, Supabase service-role JWT, Bearer token, real user email) lands permanently in the public repo's `git log`, where `git filter-repo` is the only remediation and it breaks every fork and clone.

The first slice of #3121 must therefore land the safety floor before the convention itself — once any snapshot file exists in `main`, retrofitting the floor is structurally too late.

## Goals

- Land an irreversible secret-scanning + synthesized-fixtures-only floor in `main` BEFORE any snapshot or mutation report file can ever be created in the repo.
- Establish a golden-test convention (`__goldens__/` directory, `GOLDEN_REGEN=1` regen, `Golden-Updated-By:` trailer enforcement) that is structurally resistant to approval-fatigue acceptance and `-u` muscle-memory bypass.
- Seed the convention with four documented surfaces (LLM prompts, MD→HTML, SQL builders, API responses) proving the regen workflow end-to-end.
- File tracked GitHub issues for every deferred Theme A sub-scope (A1, A3, A4-lite, A4-p95) so the deferrals are not invisible.

## Non-Goals

- Mutation testing (A1) — separate follow-up issue; blocked by both this slice landing AND #3120 (eval-suite calibration target).
- ATDD trigger hardening (A3) — separate follow-up issue.
- Architectural fitness functions (A4-lite: dep-cruiser layer boundaries, bundle-size budget, complexity cap) — separate follow-up issue, split into 3 sub-tasks.
- p95 latency gate (A4-p95) — separate follow-up issue requiring its own brainstorm; needs Sentry perf-data plumbing or metrics-export wiring before a CI gate can read p95.
- Themes B, C (beyond #3122), D (beyond #3120), E, F from the source audit.
- Modifying any existing test files in this slice — the four seed surfaces are net-new tests demonstrating the convention.

## Functional Requirements

### FR1: Secret-scanning floor (PR1)

Pre-commit and pre-merge gates that block any commit or PR introducing credential material in fixture/snapshot/mutation-report files.

- `gitleaks` integrated into `lefthook.yml` `pre-commit` stage (blocks local commits) and a new `.github/workflows/secret-scan.yml` workflow on `pull_request` (blocks merge).
- Custom rule pack scoped to `__goldens__/**`, `**/*.snap`, `tests/fixtures/**`, `reports/mutation/**` matching at minimum: `sk_live_`, `sk_test_`, `sbp_`, `eyJ` (JWT prefix), `doppler_`, `xoxb-`, `ghp_`, `Bearer\s+[A-Za-z0-9._-]{20,}`, plus an email regex excluding `@example.com`/`@test.local`.
- Waiver mechanism: explicit `// gitleaks:allow` comment with mandatory adjacent `// Why: <reason>` line; reviewer sign-off required for any waiver to merge.

### FR2: Synthesized-fixtures-only invariant (PR1)

A new AGENTS.md Code Quality rule `cq-test-fixtures-synthesized-only` and an enforcing linter.

- Rule body: "Test fixtures and snapshots MUST contain only synthesized data — no production database dumps, no replayed user requests, no real email addresses (use `@example.com`/`@test.local`), no real org IDs."
- `[hook-enforced: secret-scan.yml + lefthook gitleaks + lefthook fixture-content-lint]` tag pointing at the actual enforcers.
- Small node script (`scripts/lint-fixture-content.mjs`) invoked by lefthook sweeping `__goldens__/**` + `**/*.snap` + `tests/fixtures/**` for real-email patterns and prod-shaped UUIDs (Supabase org-id format `^[0-9a-f]{8}-[0-9a-f]{4}-...$` matched against an allowlist of synthesized values).

### FR3: Pre-empt mutation-report leak surface (PR1)

`.gitignore` entries for `reports/mutation/`, `.stryker-tmp/`, `mutants/` so the future A1 follow-up cannot accidentally commit raw mutant logs.

### FR4: Golden-test convention (PR2)

A directory + helper + regen workflow that breaks Jest/Vitest `-u` muscle memory and forces explicit reasoning for every snapshot diff.

- Convention directory: `__goldens__/` (deliberately NOT `__snapshots__/`).
- Helper: `apps/web-platform/test/helpers/golden.ts` reads goldens by default, writes only when `GOLDEN_REGEN=1` env var is set (env var instead of CLI flag defeats `vitest --update` scripted bypass).
- Pre-commit hook (`lefthook.yml`): any `git diff --cached --name-only` match on `__goldens__/**` requires the commit body to contain a `Golden-Updated-By:` trailer with a non-empty reason. Hook rejects otherwise.

### FR5: Four seed golden surfaces (PR2)

Each surface = one `__goldens__/` directory + ≥1 golden file + ≥1 consuming test.

- **LLM prompt outputs** — assembled prompts produced by `apps/web-platform/server/soleur-go-runner.ts` and `apps/web-platform/server/agent-runner.ts` for synthesized inputs.
- **Markdown→HTML rendering** — Eleventy chain (`plugins/soleur/docs/`) and chat message rendering (`apps/web-platform/components/chat/message-bubble.tsx`).
- **SQL builders** — literal SQL produced by query construction in `apps/web-platform/server/` for representative synthesized inputs.
- **API response shapes** — JSON shape (not values) of Next.js route handler responses for representative synthesized request fixtures. Highest-risk surface: consuming test must be tagged `@goldens-no-auth` and the helper enforces no real auth context can reach the snapshot serializer.

### FR6: Documentation (PR1 + PR2)

- `knowledge-base/engineering/operations/secret-scanning.md` (PR1) — rule pack, waiver process, test-data invariant.
- `knowledge-base/engineering/operations/golden-tests.md` (PR2) — convention, regen workflow, trailer enforcement, four seed surfaces as worked examples.

### FR7: Deferred-scope tracking (this brainstorm action)

Four GitHub issues filed in the same action as the brainstorm capture:

- A1 mutation testing pilot (blocked by this PR + #3120).
- A3 ATDD trigger hardening.
- A4-lite fitness functions (split into 3 sub-tasks: dep-cruiser, bundle, complexity).
- A4-p95 latency gate (requires its own brainstorm).

## Technical Requirements

### TR1: Two-PR sequencing

PR1 (safety floor) and PR2 (goldens) ship as separate PRs against this branch. PR1 MUST merge first; PR2 MUST not be marked ready until PR1 is in `main`. Lower per-PR blast radius; the floor is structurally first — it is in `main` before any golden file can ever be added.

### TR2: License compatibility

All proposed tooling must be permissively licensed (MIT/BSD/Apache-2.0). Confirmed clean for first-PR scope: `gitleaks` (MIT). No GPL/AGPL contagion.

### TR3: CI cost

`gitleaks` runs diff-only on `pre-commit` and `pull_request` triggers (fast). Full-repo sweep moves to a follow-up `scheduled-secret-scan.yml` (not in this slice) to keep PR latency low.

### TR4: AGENTS.md byte budget

Adding `cq-test-fixtures-synthesized-only` increases AGENTS.md byte size. Per `cq-agents-md-why-single-line`, the rule body is ≤600 bytes with a one-line `**Why:**` pointing at this brainstorm and the source audit (PR #3119). The longer rationale lives in this spec and `knowledge-base/engineering/operations/secret-scanning.md`, not in AGENTS.md.

### TR5: Hook tag verification

Per `cq-agents-md-tier-gate`, the `[hook-enforced: ...]` tag on the new rule must point at actually-existing hooks/workflows. PR1 includes a one-line verification script in CI confirming the tagged hooks exist (anti-rot for the tag itself).

### TR6: User-brand-impact carry-forward

Per `hr-weigh-every-decision-against-target-user-impact`, this spec inherits the `Brand-survival threshold: single-user incident` from the brainstorm. The plan derived from this spec MUST carry forward the User-Brand Impact section verbatim, and the `user-impact-reviewer` agent MUST sign off on PR1 before merge.

### TR7: Worktree-scoped commits

Per the auto-commit-density guard (`pr-quality-guards.yml`), commits in this branch must be scoped via path-allowlist (`knowledge-base/`, `apps/web-platform/test/`, `lefthook.yml`, `.github/workflows/`, `.gitignore`, `AGENTS.md`, `scripts/`) — no `git add -A` / `git add .`.

### TR8: API response surface — no real auth

The seed test for the API response shape surface (FR5) MUST run with synthesized auth contexts only. The `golden.ts` helper enforces this by rejecting any context object whose token field matches a real-key regex. The test is tagged `@goldens-no-auth` so future suites can include/exclude as needed.

### TR9: No modification to existing tests

This slice adds net-new tests under `__goldens__/` directories adjacent to the four target surfaces. Existing tests are untouched to keep the PR scope and review surface bounded.
