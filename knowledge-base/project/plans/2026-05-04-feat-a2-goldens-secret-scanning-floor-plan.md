---
title: "feat(testing): A2 goldens + secret-scanning safety floor (slice 1 of #3121)"
date: 2026-05-04
branch: behavior-harness-uplift
issue: 3121
draft_pr: 3129
spec: knowledge-base/project/specs/feat-behavior-harness-uplift/spec.md
brainstorm: knowledge-base/project/brainstorms/2026-05-04-behavior-harness-uplift-brainstorm.md
parent_brainstorm: knowledge-base/project/brainstorms/2026-05-04-harness-engineering-review-brainstorm.md
follow_up_issues: [3130, 3131, 3132, 3133, 3136]
sibling_issues: [3120, 3122]
user_brand_critical: true
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
detail_level: more
type: feat
review_applied: [dhh, kieran, simplicity]
---

# A2 Goldens + Secret-Scanning Safety Floor (Slice 1 of #3121)

## Overview

This plan implements the first shippable slice of #3121 (Theme A from the harness engineering audit) as **two sequential PRs against `main`** off the `behavior-harness-uplift` branch. PR1 lands an irreversible secret-scanning floor; PR2 (opened after PR1 merges to main) layers the golden-test convention with four documented seed surfaces.

**Merge graph:** Both PRs target `main`. PR1 merges first, then PR2 is opened from the same branch (or a fresh branch off main if `behavior-harness-uplift` carries unrelated commits). The branch carries both PRs only as a workspace; merges are direct to main, not stacked.

Five domain agents (CTO, CPO, CLO + repo-research-analyst + learnings-researcher) converged on the safety-floor-first ordering: snapshot frameworks serialize whatever the test produced; the repo today has zero secret-scanning infrastructure; once a snapshot file containing real credential material is in `main` of a public repo, `git filter-repo` is the only remediation and breaks every fork and clone. The user-impact framing answer ("all of them" — trust-breach, productivity drag, secret-leak) tagged this brand-survival-threshold = `single-user incident`.

The plan defers other Theme A sub-scopes (A1 #3130, A3 #3131, A4-lite #3132, A4-p95 #3133) and the agent-runner.ts system-prompt extraction (#3136) to follow-up issues, all filed during the brainstorm + plan actions.

## User-Brand Impact

**Artifact:** golden snapshots and (future) mutation-test reports committed to the public repo at `github.com/jikig-ai/soleur` (Apache-2.0).

**If this lands broken, the user experiences:** developer-facing CI false-greens (a secret-laden snapshot lands without rejection), eventually escalating to a credential leak in `git log` history. Downstream user impact: a single leaked BYOK API key fragment exposes that user's third-party model spend; a leaked Supabase service-role JWT exposes every user's data; a leaked email is a GDPR/privacy-policy disclosure event.

**If this leaks, the user's data / credentials / workflow is exposed via:** an inadvertent commit of a snapshot file containing real credential material, captured during a routine `vitest --update` or `GOLDEN_REGEN=1` run that ran against an environment with real `.env` / Doppler / Supabase keys loaded.

**Brand-survival threshold:** `single-user incident`.

**Sign-off:** CPO sign-off required at plan time before `/work` (per `hr-weigh-every-decision-against-target-user-impact`). The brainstorm Phase 0.1 captured CPO + CLO + CTO assessments; this plan inherits those framings via the brainstorm document. The `user-impact-reviewer` agent will be invoked at PR1 review time per the conditional-agent block in `plugins/soleur/skills/review/SKILL.md`.

## Acceptance Criteria

### Pre-merge (PR1)

- [ ] AC-1: `.gitleaks.toml` exists at repo root with `[extend] useDefault = true`, project-specific `[[rules]]` for `soleur-byok-key`, `doppler-token`, `supabase-jwt-issuer`, AND a top-level `[[allowlists]]` block (NOT per-rule) with `targetRules = []` + `paths = ['''__goldens__/.*''', '''.*\.snap$''', '''apps/web-platform/test/fixtures/.*''', '''reports/mutation/.*''']` so the path waiver applies to inherited default rules too.
- [ ] AC-2: `lefthook.yml` `pre-commit` block contains a new `gitleaks` command running `gitleaks git --pre-commit --staged --redact --no-banner` with `tags: security` annotation; slot priority appropriate for the existing lint cluster (~ priority 4-5).
- [ ] AC-3: `.github/workflows/secret-scan.yml` exists, triggers on `pull_request` (PR-diff scan via `--log-opts="--no-merges <base>..HEAD"`) AND `push: branches: [main]` (full-tree scan post-merge as backstop). Explicit `permissions:` block: `contents: read`, `pull-requests: read`. On non-zero exit: uploads gitleaks JSON report as workflow artifact for forensics. Runs only on `pull_request` (NOT `pull_request_target`) to avoid scanning untrusted fork code with elevated permissions. Inlines the gitleaks v8.24.2 install (curl + sha256sum -c + tar) — no extracted script (one caller).
- [ ] AC-4: `apps/web-platform/scripts/lint-fixture-content.mjs` exists (the parent `apps/web-platform/scripts/` directory is brand-new — note this in PR1 file additions). Scans `__goldens__/**`, `**/*.snap`, `apps/web-platform/test/fixtures/**` for: (a) real-email regex `[a-zA-Z0-9._%+-]+@(?!example\.com|test\.local)[a-zA-Z0-9.-]+`, (b) Supabase prod-shape UUIDs against an allowlist of known synthesized values. Honors `# gitleaks:allow` line-level waivers (single waiver vocabulary; same comment that gitleaks recognizes — no parallel `// fixture-allow:` to learn). Wired into `lefthook.yml` `pre-commit` as a separate command from `gitleaks` (different binaries, different scopes; combining hides which one tripped).
- [ ] AC-5: `.gitignore` extended with `reports/mutation/`, `.stryker-tmp/`, `mutants/`.
- [ ] AC-6: `AGENTS.md` `## Code Quality` section appended with `cq-test-fixtures-synthesized-only` rule (488 bytes, verified by `printf '%s' '<rule>' | wc -c`; under 600-byte cap per `cq-agents-md-why-single-line`) tagged `[hook-enforced: lefthook gitleaks + lefthook fixture-content-lint + .github/workflows/secret-scan.yml]`. **Phase ordering:** this AGENTS.md edit is the LAST step of PR1, after all three enforcers exist in the branch and AC-9 smoke tests pass — the `[hook-enforced]` tag must reference workflows/hooks that actually exist (per `cq-agents-md-tier-gate`).
- [ ] AC-7: `knowledge-base/engineering/operations/secret-scanning.md` exists, documenting: gitleaks rule pack, top-level vs per-rule allowlist semantics, `# gitleaks:allow` waiver mechanism (recognized by both gitleaks and `lint-fixture-content.mjs`), the `--no-verify` bypass + CI backstop, the rotation runbook if a leaked secret is detected post-merge.
- [ ] AC-8: PR1 includes user-impact-reviewer sign-off in its review thread (per `Brand-survival threshold: single-user incident`).
- [ ] AC-9: Smoke tests run as a job in `secret-scan.yml` (co-located with the gate they test):
  - **Allowlist positive:** stage a synthesized `__goldens__/fake.snap` containing a JWT-shaped string `eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.fake.fake` → `gitleaks git --staged` exits 0 (allowlist applies).
  - **Allowlist negative:** stage same content at `apps/web-platform/server/leaked.ts` → `gitleaks git --staged` exits 1 (allowlist does NOT apply outside fixture paths).
  - **Linter positive:** stage `__goldens__/contains-real-email.txt` with `user@gmail.com` (no waiver) → `lint-fixture-content.mjs` exits 1.
  - **Linter waiver:** stage same content with `# gitleaks:allow` → `lint-fixture-content.mjs` exits 0.

### Pre-merge (PR2)

- [ ] AC-10: `apps/web-platform/test/helpers/golden.ts` exports `expectMatchesGolden(actual: string, goldenPath: string): Promise<void>` — read-only by default; writes via `mkdirSync` + `writeFileSync` when `process.env.GOLDEN_REGEN === "1"`; throws explicit message ("Run with `GOLDEN_REGEN=1 bun test <path>`, then commit with `Golden-Updated-By: <name>` trailer") when golden missing in non-regen mode. Single export — JSON-shape assertion for env-sensitive surfaces is inlined per-test where needed (no premature helper extraction).
- [ ] AC-11: `lefthook.yml` extended with NEW `commit-msg` block (no precedent — only `pre-commit` exists today). Per context7 verification (lefthook v1.4+), `{1}` placeholder is the correct syntax for the commit message file path. Hook script: `git diff --cached --name-only | grep -qE '__goldens__/' || exit 0; grep -qE '^Golden-Updated-By: .+' {1} || (echo "Goldens changed; commit must include 'Golden-Updated-By: <name>' trailer." && exit 1)`. The leading `|| exit 0` handles "no goldens staged" without false-positive failure.
- [ ] AC-12: `.github/scripts/check-goldens-trailer.sh` exists, mirroring the existing `check-pr-body-vs-diff.sh` pattern; `pr-quality-guards.yml` adds a new job `goldens-trailer-guard` that runs on `pull_request` whenever `__goldens__/**` paths appear in the PR diff (path filter at job level). Script logic: scan `git log <base>..HEAD --format=%B` for `^Golden-Updated-By: .+` in any commit OR scan PR body via `gh api` for the same trailer. Either source satisfies the guard. **This is the load-bearing gate** — lefthook commit-msg does NOT fire on `git rebase -i` reword/squash AND can be bypassed with `git commit --no-verify`. CI is the only path that survives both.
- [ ] AC-13: Four seed golden surfaces under `apps/web-platform/test/__goldens__/` (the directory name is a deliberate non-default to defeat `vitest --update` muscle memory; documented rationale in golden-tests.md):
  - **llm-prompts/** — `soleur-go-baseline.test.ts` snapshots `buildSoleurGoSystemPrompt({})` and `buildSoleurGoSystemPrompt({ artifactPath: '/synth/example.md', activeWorkflow: 'plan' })`; `replay-prompt.test.ts` snapshots `buildReplayPrompt(<synthesized history>, '<synthesized message>')`. Goldens at `*.golden.txt`. Full agent-runner system-prompt extraction deferred to #3136.
  - **markdown/** — `chat-message-bubble.test.tsx` (component test, picks up `test/setup-dom.ts`) renders `<MarkdownRenderer content={fixture}/>` via `@testing-library/react`, snapshots HTML to `*.golden.html` for: plain markdown, GFM tables, fenced code blocks, links with custom rel; `eleventy-baseline.test.ts` imports `markdown-it` directly with default options (Eleventy uses default config — verified at `eleventy.config.js`) and snapshots HTML for the same fixture set. Documented limitation: Eleventy's full pipeline applies Nunjucks post-processing (`htmlTemplateEngine: "njk"`); this golden snapshots only the markdown→HTML stage, not the full Eleventy output.
  - **sql-builders/** — `lookup-conversation-supabase-chain.test.ts` mocks `supabase().from()` to record the chained method-call sequence as JSON (`.from(arg).select(arg).eq(arg, arg)...`), invokes a representative server function (e.g., `lookupConversationForPath` from `apps/web-platform/server/lookup-conversation-for-path.ts`), and snapshots the captured call sequence to `*.golden.json`.
  - **api-responses/** — `flags-route.no-auth.test.ts` (the `.no-auth.` infix is a documentation convention) stubs `process.env.FLAG_KB_CHAT_SIDEBAR=0` and `process.env.FLAG_CC_SOLEUR_GO=0` via `vi.stubEnv` BEFORE invoking `/api/flags` route handler in-process, then asserts shape via inline `Object.keys(json).sort()` + `Object.fromEntries(Object.entries(json).map(([k,v]) => [k, typeof v]))` (5 lines, not a helper) and snapshots to `*.golden.json`.
- [ ] AC-14: `.github/PULL_REQUEST_TEMPLATE.md` extended with a `Golden-Updated-By:` trailer field (R3 mitigation — squash-merge can drop intermediate commit trailers; PR-body trailer is the durable source).
- [ ] AC-15: `knowledge-base/engineering/operations/golden-tests.md` documents the regen workflow (`GOLDEN_REGEN=1 bun test <path>`), the `Golden-Updated-By:` trailer template, the directory-naming rationale (`__goldens__/` not `__snapshots__/`), and links to `secret-scanning.md` for the bypass discussion. Minimal scope; structure left to author.

### Post-merge (operator)

This slice has no post-merge ops actions (no terraform apply, no migrations). PR1 + PR2 are pure-PR slices. Issue closure: PR2 body contains `Closes #3121`; PR1 body contains `Ref #3121` (PR1 alone does not close the umbrella).

## Files to Edit

- `AGENTS.md` — append `cq-test-fixtures-synthesized-only` rule at end of `## Code Quality` (PR1, last step).
- `lefthook.yml` — add `gitleaks` + `lint-fixture-content` to `pre-commit` (PR1); add new `commit-msg` block (PR2).
- `.gitignore` — append `reports/mutation/`, `.stryker-tmp/`, `mutants/` (PR1).
- `.github/workflows/pr-quality-guards.yml` — add `goldens-trailer-guard` job (PR2).
- `.github/PULL_REQUEST_TEMPLATE.md` — add `Golden-Updated-By:` trailer field section (PR2).

All paths anchored at worktree root `/home/jean/git-repositories/jikig-ai/soleur/.worktrees/behavior-harness-uplift/`.

## Files to Create

PR1:

- `.gitleaks.toml` (root)
- `.github/workflows/secret-scan.yml`
- `apps/web-platform/scripts/lint-fixture-content.mjs` (**parent dir `apps/web-platform/scripts/` is brand-new** — first file in the directory)
- `knowledge-base/engineering/operations/secret-scanning.md`

PR2:

- `apps/web-platform/test/helpers/golden.ts`
- `.github/scripts/check-goldens-trailer.sh`
- `apps/web-platform/test/__goldens__/llm-prompts/soleur-go-baseline.test.ts` + `soleur-go-baseline.golden.txt` + `soleur-go-with-artifact.golden.txt`
- `apps/web-platform/test/__goldens__/llm-prompts/replay-prompt.test.ts` + `replay-prompt.golden.txt`
- `apps/web-platform/test/__goldens__/markdown/chat-message-bubble.test.tsx` + four `.golden.html` files (plain, gfm-table, fenced-code, link-with-rel)
- `apps/web-platform/test/__goldens__/markdown/eleventy-baseline.test.ts` + four `.golden.html` files
- `apps/web-platform/test/__goldens__/sql-builders/lookup-conversation-supabase-chain.test.ts` + `.golden.json`
- `apps/web-platform/test/__goldens__/api-responses/flags-route.no-auth.test.ts` + `.golden.json`
- `knowledge-base/engineering/operations/golden-tests.md`

## Implementation Phases

### Phase 1 — PR1 safety floor (~half-day)

**Important:** AGENTS.md edit (step 11) MUST be the LAST step. The `[hook-enforced]` tag must reference enforcers that already exist in the branch.

1. Author `.gitleaks.toml` at repo root with `[extend] useDefault = true`, project-specific `[[rules]]` for BYOK/Doppler/Supabase JWT prefixes, top-level `[[allowlists]]` (`targetRules = []`) for path waivers. Verify against gitleaks v8.24.2 schema.
2. Author `.github/workflows/secret-scan.yml` with two triggers (`pull_request`, `push: branches: [main]`). Inline gitleaks install (curl + sha256sum -c + tar; pin v8.24.2 + checksum). Explicit `permissions:` block. Artifact upload on detection.
3. Extend `lefthook.yml` `pre-commit` with `gitleaks` command (`gitleaks git --pre-commit --staged --redact --no-banner`).
4. Mkdir `apps/web-platform/scripts/`; author `apps/web-platform/scripts/lint-fixture-content.mjs` with regex sweep + `# gitleaks:allow` line-level waiver scanner (same vocabulary gitleaks uses).
5. Extend `lefthook.yml` `pre-commit` with `lint-fixture-content` command.
6. Append `.gitignore` with mutation report dirs.
7. Write `knowledge-base/engineering/operations/secret-scanning.md`.
8. Add AC-9 smoke tests as a job in `secret-scan.yml` (positive + negative + linter-positive + linter-waiver).
9. Push branch; verify all four smoke tests fire correctly in CI on the draft PR.
10. Verify `[hook-enforced: ...]` candidate text resolves to actually-existing files in the branch (`ls lefthook.yml .github/workflows/secret-scan.yml apps/web-platform/scripts/lint-fixture-content.mjs`).
11. **Last step:** append `AGENTS.md` `## Code Quality` with the `cq-test-fixtures-synthesized-only` rule (text in §AGENTS.md Rule Draft below; recount bytes before commit).
12. Mark PR ready, secure user-impact-reviewer sign-off, merge to main.

### Phase 2 — PR2 golden convention + 4 surfaces (~1-2 days)

PR2 opens after PR1 merges to main (so PR2's branch can be rebased on main and inherit the floor).

1. Write `apps/web-platform/test/helpers/golden.ts` exporting `expectMatchesGolden` (single export).
2. Extend `lefthook.yml` with NEW `commit-msg` block (Golden-Updated-By trailer enforcement; uses `grep -qE ... || exit 0` for safe no-op; `{1}` placeholder per context7-verified lefthook syntax).
3. Author `.github/scripts/check-goldens-trailer.sh` mirroring the `check-pr-body-vs-diff.sh` pattern.
4. Add `goldens-trailer-guard` job to `pr-quality-guards.yml` (path filter on `__goldens__/**`; script invocation; load-bearing gate).
5. Extend `.github/PULL_REQUEST_TEMPLATE.md` with the `Golden-Updated-By:` trailer field.
6. Write 4 seed surfaces (per AC-13) — each as one test file + one or more `*.golden.*` fixture files.
   - llm-prompts: 2 sub-tests using already-extracted helpers; no source refactor needed.
   - markdown: 2 sub-tests; chat surface uses `@testing-library/react`, eleventy surface imports `markdown-it` directly with default options.
   - sql-builders: 1 test mocking the Supabase client method chain.
   - api-responses: 1 test stubbing env vars + invoking `/api/flags` handler in-process; inline 5-line shape assertion.
7. Generate goldens with `GOLDEN_REGEN=1 bun test apps/web-platform/test/__goldens__`.
8. Write `knowledge-base/engineering/operations/golden-tests.md` (regen recipe, trailer template, directory-naming rationale, link to secret-scanning.md).
9. Run smoke tests for the trailer guard: commit a golden change with no trailer → CI guard rejects; commit with trailer → passes.
10. Push PR2, mark ready, merge to main.

## Test Strategy

- **PR1 tests** = CI smoke tests against the gates themselves (AC-9). Wired as a job in `secret-scan.yml` so a future edit to gitleaks config triggers the smoke job via path filter.
- **PR2 tests** = the golden tests of AC-13 (which test the convention by using it). No new test framework — vitest already in place.

**Per `cq-write-failing-tests-before` (work skill Phase 2 TDD Gate):** PR2's golden tests are first-commit-failing by definition (the goldens don't exist yet); the gate is naturally satisfied. PR1 is mostly infrastructure (CI configs, hooks, AGENTS.md text) and qualifies for the infrastructure-only exemption — the smoke-test job (AC-9) is the closest analog to TDD for that PR; write the failing smoke fixtures first, then add the gates.

## Risks

- **R1: gitleaks version drift.** Pinned to v8.24.2 with SHA256. If gitleaks releases a v9 with breaking config changes, `[extend] useDefault = true` semantics could shift. **Mitigation:** version pin in `secret-scan.yml`; document upgrade procedure in `secret-scanning.md`. Renovate/Dependabot will surface upgrades; they're operator-reviewed before merging.
- **R2: lefthook commit-msg is bypassable** (does NOT fire on `git rebase -i` reword/squash; bypassed by `git commit --no-verify`). **Mitigation:** the load-bearing gate is the CI `goldens-trailer-guard` job (AC-12), not the lefthook hook. The hook is a fast-fail UX nicety; CI is enforcement that survives both bypasses.
- **R3: GitHub squash-merge drops trailers from intermediate commits.** **Mitigation:** PR template field for trailer (AC-14); CI guard (AC-12) checks PR body OR commit messages, accepting either source.
- **R4: gitleaks per-rule `[[rules.allowlists]]` does NOT apply to inherited default rules.** **Mitigation:** use top-level `[[allowlists]]` with `targetRules = []` (per AC-1).
- **R5: `/api/flags` snapshot is env-dependent (not user-dependent).** **Mitigation:** `vi.stubEnv` both flags before invocation; inline 5-line shape assertion (key presence + types) instead of value comparison.
- **R6: agent-runner.ts not refactored in this slice.** Only soleur-go-runner + buildReplayPrompt are golden-tested for the LLM-prompts surface. **Mitigation:** filed as #3136. Convention itself is proven without it.
- **R7: `apps/web-platform/scripts/` is a brand-new directory.** **Mitigation:** noted explicitly in PR1 file additions; `.mjs` precedent already exists at `plugins/soleur/docs/scripts/screenshot-gate.mjs`.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. This plan's section is filled and threshold is `single-user incident`.
- The `[hook-enforced: ...]` tag on the new AGENTS.md rule MUST point at workflows/hooks that actually exist after PR1 merges — not the planned future state. Phase 1 step 11 (AGENTS.md append) is explicitly the LAST step for this reason.
- The lefthook `commit-msg` block introduces a NEW stage (no precedent — only `pre-commit` exists). `{1}` placeholder is the correct syntax (verified via context7 against `/evilmartians/lefthook` docs). Test on `git commit --amend` specifically.
- gitleaks `--staged` mode reports the worktree path; `[[allowlists]] paths` regex is anchored against that path. `'''__goldens__/.*'''` matches anywhere in the path; verified against actual staged-file behavior in the AC-9 smoke tests.
- The four surface tests must NOT modify any existing test file — they are net-new tests under `apps/web-platform/test/__goldens__/`. Per spec TR9, existing tests are untouched to keep the PR scope and review surface bounded.
- When extending the `cq-test-fixtures-synthesized-only` rule's `[hook-enforced]` tag in future work (e.g., adding new enforcers), recount the rule body bytes against the 600-byte cap.

## Domain Review

**Domains relevant:** Engineering, Legal (carry-forward from brainstorm Phase 0.5).

### Engineering

**Status:** reviewed (carried forward from brainstorm)
**Assessment:** CTO recommended A4-lite as first slice for lowest risk; concurred with the safety-floor-first pivot when the operator confirmed user-brand-critical framing. Flagged A1's per-file mutation-score gameability and proposed `env -i` sandbox + tagged-test-subset enforcement (deferred to #3130). Identified the secret-leak vector for A1 as the load-bearing risk that this slice's PR1 closes structurally.

### Legal

**Status:** reviewed (carried forward from brainstorm)
**Assessment:** CLO identified the critical gap — repo has zero secret-scanning today (CodeQL is SAST for code paths, not fixture content). Proposed `gitleaks` (MIT, no contagion) as `pre-commit` + CI with snapshot-scoped rule pack; `cq-test-fixtures-synthesized-only` AGENTS.md rule; `.gitignore` for mutation report dirs. Confirmed all proposed tooling licenses are clean (Apache-2.0/MIT/BSD); flagged Stryker dashboard as a data-egress consideration (relevant to deferred #3130). Pre-empted Theme D2 (trajectory dataset) by noting fixture pollution would propagate to any future dataset and create a GDPR Article 5(1)(b) purpose-limitation issue.

### Product/UX Gate

**Tier:** none
**Decision:** N/A — no `components/**/*.tsx`, `app/**/page.tsx`, or `app/**/layout.tsx` files created. All new files are CI configs (`*.yml`, `*.toml`), scripts (`*.mjs`, `*.sh`), tests under `test/__goldens__/`, AGENTS.md rule text, docs, and a new `apps/web-platform/test/helpers/golden.ts` test helper.

**CPO sign-off (per `requires_cpo_signoff: true`):** required at plan time before `/work` per `hr-weigh-every-decision-against-target-user-impact`. Brainstorm Phase 0.1 already captured CPO assessment; this plan inherits the framing. CPO does NOT need to re-sign at plan time per the tiered sign-off model documented in plan SKILL.md Phase 2.6 — the `user-impact-reviewer` will run at PR1 review per the conditional-agent block.

## Open Code-Review Overlap

6 open code-review issues touch files this plan references. Disposition: **acknowledge all** — none conflict with this slice's scope.

| Issue | File pattern | Concern | Disposition |
|---|---|---|---|
| #3002 | AGENTS.md | service-worker error handler for cache.put quota | Acknowledge — different concern (this plan adds a Code Quality rule; #3002 adds a separate rule about service-worker errors) |
| #2963 | apps/web-platform/test/ | Supabase typegen for ConversationPatch | Acknowledge — about codegen, orthogonal to test infrastructure |
| #2221 | apps/web-platform/test/ | Replace TestBubble proxy with real MessageBubble in memo test | Acknowledge — could later inform our markdown golden test if MessageBubble integration improves; doesn't block |
| #2193 | apps/web-platform/test/ | Unify past_due/unpaid banners + extract useDismissiblePersistent | Acknowledge — billing component refactor, not test infra |
| #2962 | apps/web-platform/server/agent-runner.ts | Extract memoized getServiceClient() singleton | Acknowledge — this slice does NOT modify agent-runner.ts (deferred to #3136) |
| #2955 | apps/web-platform/server/{agent-runner,soleur-go-runner}.ts | Process-local state ADR + startup guard | Acknowledge — read-only references in this slice; doesn't modify either file |

## Research Insights

### gitleaks (v8.24.2, 2026)

- `detect`/`protect` deprecated since v8.19.0 (still functional but hidden from `--help`). Canonical commands: `gitleaks git --pre-commit --staged` (git-aware) or `gitleaks stdin` (pipe).
- For OSS public repos, install binary directly (NOT `gitleaks/gitleaks-action@v2` — requires `GITLEAKS_LICENSE` for orgs above 1 repo). Pattern: `curl -sSfL -o gitleaks.tgz <url> && echo "<sha256>  gitleaks.tgz" | sha256sum -c - && tar xzf gitleaks.tgz`.
- `[[rules.allowlists]]` is rule-scoped (only applies to the rule it's nested under). For path waivers that should apply to ALL rules including extended defaults, use top-level `[[allowlists]]` with `targetRules = []`.
- Path-allowlist regex matches anywhere in the path (not anchored). `'''__goldens__/.*'''` correctly catches files under any nested location.
- `# gitleaks:allow` is a line-level inline waiver. Reused by `lint-fixture-content.mjs` as the same vocabulary (single waiver convention).

### Vitest snapshot conventions

- `expect.toMatchFileSnapshot('./path.ext')` is gated by `vitest --update`, not an env var. Hand-rolled `writeFileSync` helper with `process.env.GOLDEN_REGEN === "1"` gate is more maintainable: env-var gate (not CLI flag), custom error pointing at trailer rule, no surprise from `vitest -u`.
- `__goldens__/` is a deliberate non-default; no public OSS precedent. Defensible because `vitest -u` mechanically does not touch files outside `__snapshots__/`. Document rationale in `golden-tests.md`.

### Lefthook conventions

- Existing `lefthook.yml` has only `pre-commit` stage. Adding `commit-msg` is a new convention.
- **`{1}` placeholder verified via context7** against `/evilmartians/lefthook` — correct syntax for the commit message file path passed to `commit-msg` hook commands. Same as `$1` in shell scripts.
- `commit-msg` re-fires on `git commit --amend`. Does NOT fire on `git rebase -i` reword/squash. CI guard (AC-12) is required for trailer enforcement to be load-bearing.

### Existing CI script patterns

- `.github/scripts/check-pr-body-vs-diff.sh` is the precedent for parsing PR body via `gh api`. New `check-goldens-trailer.sh` mirrors that pattern.

### AGENTS.md Rule Draft (488 bytes — verified by `printf '%s' '<rule>' | wc -c`)

```text
- Test fixtures and golden files (`__goldens__/**`, `**/*.snap`, `apps/web-platform/test/fixtures/**`) MUST contain only synthesized data — no real emails (use `@example.com`/`@test.local`), no Supabase prod-shape UUIDs, no live JWTs/Doppler/BYOK tokens [id: cq-test-fixtures-synthesized-only] [hook-enforced: lefthook gitleaks + lefthook fixture-content-lint + .github/workflows/secret-scan.yml]. Waive a line with `# gitleaks:allow`. **Why:** #3121 — fixtures bypass prod redaction.
```

If the `[hook-enforced]` tag list ever changes (e.g., adding a 4th enforcer), recount byte length before committing.

## Open Questions / Deferrals

- Should the `Golden-Updated-By:` trailer be a closed enum (`schema-change|prompt-tuning|intentional-output-shift|flake-fix`) or free-text? CPO recommended closed-enum patterns for skip rationales. **Plan decision: free-text in slice 1**, with a follow-up issue tracked if the field becomes boilerplate within 2 months (mirror the A3 closed-enum lesson once we have data).
- Daily scheduled gitleaks scan: **deferred** — `pull_request` + `push: branches: [main]` covers governance; cron only catches scenarios that require admin web-UI edits (vanishingly rare). Re-evaluate if a real bypass is observed.

## Plan Review Application Log

This plan was reviewed by DHH, Kieran, and code-simplicity-reviewer. Applied:

- **Drop `expectStableShape`** (DHH + Simplicity) — inlined 5-line shape assertion in flags-route test (AC-13).
- **Inline `scripts/install-gitleaks.sh`** (Simplicity) — one caller in PR1; AC-3 inlines the install steps.
- **Cut daily scheduled scan** (DHH) — `pull_request` + `push: branches: [main]` covers governance.
- **Collapse R2+R3** (Simplicity) — single risk for lefthook bypass paths with CI as load-bearing mitigation.
- **Drop `// fixture-allow:` waiver** (Simplicity) — `lint-fixture-content.mjs` honors `# gitleaks:allow` instead (single waiver vocabulary).
- **Fix path bugs** (Kieran) — AC-1 fixture path corrected to `apps/web-platform/test/fixtures/.*`; `apps/web-platform/scripts/` flagged as brand-new dir.
- **Reorder PR1 phase** (Kieran) — AGENTS.md edit is now LAST step (#11), after enforcers exist.
- **Recount AGENTS.md bytes** (Kieran) — actual 488 bytes, verified via `printf | wc -c`.
- **Add `.github/PULL_REQUEST_TEMPLATE.md`** (Kieran) — to Files to Edit (R3 mitigation).
- **Tighten AC-3** (Kieran) — explicit `permissions:`, artifact upload, `pull_request` (NOT `pull_request_target`).
- **Tighten AC-12** (Kieran) — name `check-goldens-trailer.sh`, mirror existing `check-pr-body-vs-diff.sh` pattern.
- **Pick wiring for AC-9** (Kieran) — co-locate smoke tests in `secret-scan.yml`.
- **Verify `{1}` placeholder via context7** (Kieran) — confirmed correct lefthook syntax.
- **Clarify merge graph** (Kieran) — both PRs target `main`; branch is workspace, not stack.

Rejected (operator-chosen via brainstorm; not re-litigated):

- Two-PR split (review-blast-radius reasons; different reviewer skill sets)
- Trailer apparatus retention (structural author-prompt, not just review-time question)
- 4 seed surfaces (brainstorm decision #3)
- `__goldens__/` directory naming (brainstorm decision #4)
- Separate secret-scanning.md + golden-tests.md docs (different audiences)

## Follow-up Issues Filed

| # | Title | Why deferred |
|---|---|---|
| #3130 | A1 mutation testing pilot | Blocked by this slice + #3120 (eval-suite calibration target) |
| #3131 | A3 ATDD trigger hardening | CPO-recommended slice; deferred to ship after this safety floor |
| #3132 | A4-lite fitness functions | Split into 3 sub-tasks (dep-cruiser, bundle, complexity); independent of this slice |
| #3133 | A4-p95 latency gate | Needs own brainstorm (Sentry plumbing / baseline strategy) |
| #3136 | Extract `buildAgentRunnerSystemPrompt` for golden testing | Refactor risk too high to bundle with PR2; agent-runner ~200 lines of conditional appends |
