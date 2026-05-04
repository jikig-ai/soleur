---
title: "feat(testing): A2 goldens + secret-scanning safety floor (slice 1 of #3121)"
date: 2026-05-04
branch: behavior-harness-uplift
issue: 3121
draft_pr: 3129
spec: knowledge-base/project/specs/feat-behavior-harness-uplift/spec.md
brainstorm: knowledge-base/project/brainstorms/2026-05-04-behavior-harness-uplift-brainstorm.md
parent_brainstorm: knowledge-base/project/brainstorms/2026-05-04-harness-engineering-review-brainstorm.md
follow_up_issues: [3130, 3131, 3132, 3133, 3136, 3143, 3144]
sibling_issues: [3120, 3122]
user_brand_critical: true
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
detail_level: more
type: feat
review_applied: [dhh, kieran, simplicity]
deepen_applied: [best-practices, framework-docs, architecture-strategist, security-sentinel, test-design-reviewer, learnings-researcher]
gitleaks_version: 8.24.2
---

# A2 Goldens + Secret-Scanning Safety Floor (Slice 1 of #3121)

## Overview

This plan implements the first shippable slice of #3121 (Theme A from the harness engineering audit) as **two sequential PRs against `main`** off the `behavior-harness-uplift` branch.

- **PR1 — Safety floor (~1 day, expanded scope after deepen pass).** gitleaks integration (10+ rule pack), CODEOWNERS for security-critical files, fixture-content linter, `.gitignore` for mutation report dirs, AGENTS.md rule, secret-scanning runbook.
- **PR2 — Golden convention + 2 seed surfaces (~half-day, scope reduced).** `expectMatchesGolden` helper, lefthook commit-msg trailer (UX nicety), CI trailer guard (load-bearing), 2 surfaces (LLM prompts + API response shapes). Markdown + SQL-builder surfaces deferred to #3143/#3144 per test-design-reviewer's Farley-properties scoring (3-5/10 on noise-prone surfaces).

**Merge graph:** Both PRs target `main`. PR1 merges first, then PR2 opens from a fresh branch off main.

Five domain agents (CTO, CPO, CLO + repo-research-analyst + learnings-researcher) converged on the safety-floor-first ordering during brainstorm. Six deepen agents (best-practices, framework-docs, architecture-strategist, security-sentinel, test-design-reviewer, learnings-researcher) re-validated and surfaced critical correctness gaps now folded into this plan. The user-impact framing answer ("all of them" — trust-breach, productivity drag, secret-leak) tagged this brand-survival-threshold = `single-user incident`.

The plan defers other Theme A sub-scopes (A1 #3130, A3 #3131, A4-lite #3132, A4-p95 #3133), agent-runner.ts extraction (#3136), markdown-behavioral surface (#3143), and SQL-builders shape surface (#3144) to follow-up issues.

## User-Brand Impact

**Artifact:** golden snapshots and (future) mutation-test reports committed to the public repo at `github.com/jikig-ai/soleur` (Apache-2.0).

**If this lands broken, the user experiences:** developer-facing CI false-greens (a secret-laden snapshot lands without rejection), eventually escalating to a credential leak in `git log` history. Downstream user impact: a single leaked BYOK API key fragment exposes that user's third-party model spend; a leaked Supabase service-role JWT exposes every user's data; a leaked email is a GDPR/privacy-policy disclosure event.

**If this leaks, the user's data / credentials / workflow is exposed via:** an inadvertent commit of a snapshot file containing real credential material, captured during a routine `vitest --update` or `GOLDEN_REGEN=1` run that ran against an environment with real `.env` / Doppler / Supabase keys loaded.

**Brand-survival threshold:** `single-user incident`.

**Sign-off:** CPO sign-off required at plan time before `/work` (per `hr-weigh-every-decision-against-target-user-impact`). Brainstorm Phase 0.1 captured CPO + CLO + CTO assessments; this plan inherits those framings. The `user-impact-reviewer` agent will be invoked at PR1 review time per the conditional-agent block in `plugins/soleur/skills/review/SKILL.md`.

## Acceptance Criteria

### Pre-merge (PR1 — Safety Floor)

- [ ] AC-1: `.gitleaks.toml` exists at repo root, gitleaks v8.24.2-correct syntax (`[extend] useDefault = true` + per-rule `[[rules.allowlists]]` — NOT top-level `[[allowlists]] + targetRules` which is v8.25+ only). Custom `[[rules]]` for ALL of: `soleur-byok-key`, `doppler-token` (covers `dp.pt./dp.st./dp.sa./dp.ct.`), `supabase-service-role-jwt` (HS256 + iss/role claim), `supabase-anon-jwt`, `supabase-access-token` (`sbp_`), `stripe-webhook-secret` (`whsec_`), `anthropic-api-key` (`sk-ant-`), `resend-api-key` (`re_`), `cf-scoped-token` (40-char alphanum), `sentry-auth-token` (`sntrys_`/`sntryu_`), `discord-webhook-url`, `database-url-with-password` (`postgres(ql)?://[^:]+:[^@]+@`), `vapid-private-key`. Each rule includes per-rule `[[rules.allowlists]]` paths block. Allowlist paths use **narrow, anchored globs**: `__goldens__/.*`, `(__snapshots__|__goldens__)/.*\.snap$` (anchored to test dirs, NOT `.*\.snap$` repo-wide), `apps/web-platform/test/__synthesized__/.*` (NEW dir for fixtures that may contain semi-sensitive shapes; replaces broad `apps/web-platform/test/fixtures/.*` allowlist), `reports/mutation/.*`. The existing `apps/web-platform/test/fixtures/qa-auth.ts` is NOT allowlisted (real auth-test fixture; if it ever needs a synthesized token, move under `__synthesized__/`).
- [ ] AC-2: `.github/CODEOWNERS` exists, requires second-reviewer approval for `.gitleaks.toml`, `.github/workflows/secret-scan.yml`, `.github/workflows/pr-quality-guards.yml`, `lefthook.yml`, `apps/web-platform/scripts/lint-fixture-content.mjs`, and `AGENTS.md`. Branch-protection enablement on `main` requiring `secret-scan` status check + CODEOWNERS approval is **filed as follow-up issue** (requires repo-admin scope; cannot be done in-PR). Without CODEOWNERS, CI is self-disabling — a single PR could modify the gates and add a leaked secret in the same diff.
- [ ] AC-3: `lefthook.yml` `pre-commit` block contains a new `gitleaks-staged` command running `gitleaks git --pre-commit --staged --redact --no-banner --exit-code 1`, slot priority 4-5 (lint cluster). No `glob:` filter (gitleaks scans the index itself). Plus a separate `lint-fixture-content` command with a path-array `glob:` (NOT `**/*` — gobwas semantics silently no-op without explicit subdirs; per learning `2026-03-21-lefthook-gobwas-glob-double-star.md`).
- [ ] AC-4: `.github/workflows/secret-scan.yml` exists with three triggers: `pull_request` (PR-diff scan via `--log-opts="--no-merges <base>..HEAD"`), `push: branches: [main]` (post-merge full-tree scan), `schedule: [cron: '0 6 * * 1']` (weekly retroactive scan with current rule pack — catches retroactive coverage when the rule pack adds new patterns; cheap; replaces the daily cron the plan-review pass cut). `permissions: contents: read` ONLY (drop `pull-requests: read` per least-privilege; workflow does not need PR metadata access). Triggered on `pull_request` (NOT `pull_request_target`) so fork PRs run without secrets exposure. Inlines the gitleaks v8.24.2 install with **hardcoded SHA256 literal in the workflow YAML** (NOT fetched from GitHub at runtime — same-origin attacker could swap both binary and checksum). Uses `--redact` to suppress raw secret content in logs. **Does NOT upload `--report-path` JSON as artifact** (gitleaks v8.18+ redacts the JSON `Secret` field but on a public repo the safer default is to print redacted summary to logs only and require local re-run with the offending commit SHA for forensics; documented in secret-scanning.md).
- [ ] AC-5: `apps/web-platform/scripts/lint-fixture-content.mjs` exists (the parent `apps/web-platform/scripts/` directory is brand-new — first file in the dir). Scans staged file contents (passed via `{staged_files}` from lefthook) for: real-email regex with `@(example\.com|example\.org|.+\.test|fixtures\.local)` allowlist, Supabase prod-shape UUIDs against an allowlist of known synthesized values, and Supabase project-ref pattern (`[a-z0-9]{20}\.supabase\.co`). Honors `# gitleaks:allow` AND `// gitleaks:allow` line-level waivers (single waiver vocabulary). Each waiver MUST include `issue:#NNN <reason>` trailer; lint script rejects waivers with empty reason. Exits 1 with `file:line:reason` on first match. ~50 lines. Bash-safe per learning `2026-03-18-shared-test-helpers-extraction.md`: ESM Node script, no shell substring matching with `grep -qF`.
- [ ] AC-6: `.gitignore` extended with `reports/mutation/`, `.stryker-tmp/`, `mutants/`.
- [ ] AC-7: `knowledge-base/engineering/operations/secret-scanning.md` exists with these required sections:
  - **Decision tree** (history-rewrite vs accept-and-rotate): public-repo + post-merge → "rotate immediately, don't `filter-repo`; assume secret is exfiltrated to GitHub CDN/index/forks the moment `push:main` fires the alert."
  - **Per-token rotation playbook** for: `BYOK_ENCRYPTION_KEY` (worst-case — dual-key migration path; cannot rotate without re-encrypting stored ciphertexts), `SUPABASE_SERVICE_ROLE_KEY` (dashboard reset; coordinate with deploy), `SUPABASE_ACCESS_TOKEN` (revoke + regenerate; update `prd_terraform`), `ANTHROPIC_API_KEY`, `STRIPE_SECRET_KEY` + `STRIPE_WEBHOOK_SECRET` (webhook rotation needs endpoint redeploy), `GITHUB_APP_PRIVATE_KEY` (all installations re-auth), `RESEND_API_KEY`, `CF_API_TOKEN_PURGE`, `SENTRY_*`, `GOOGLE_CLIENT_SECRET`, `GITHUB_CLIENT_SECRET`, `BUTTONDOWN_API_KEY`, `VAPID_PRIVATE_KEY`, `DISCORD_OPS_WEBHOOK_URL`, `DATABASE_URL` password.
  - **Notification:** post to `#security-incidents` Discord via `DISCORD_OPS_WEBHOOK_URL`; GDPR/security-disclosure obligation if customer data is touched.
  - **Forensics:** preserve commit SHA + workflow logs in private incident tracker before rotation.
  - **Rule-pack maintenance:** how to add a new rule when a token shape is missed; weekly cron coverage.
  - **Waiver discipline:** every `# gitleaks:allow` requires `issue:#NNN <reason>`; CI grep enforces.
- [ ] AC-8: `AGENTS.md` `## Code Quality` section appended with `cq-test-fixtures-synthesized-only` rule (458 bytes, verified by `printf '%s' '<rule>' | wc -c`; under 600-byte cap per `cq-agents-md-why-single-line`) tagged `[hook-enforced: .github/workflows/secret-scan.yml]` (single load-bearing enforcer per architecture-strategist pattern-consistency finding; lefthook commands documented as fast-feedback in secret-scanning.md, not in the tag). **Phase ordering:** AGENTS.md edit is the LAST step of PR1, after the workflow exists in the branch and AC-9 smoke tests pass.
- [ ] AC-9: Smoke tests run as a job in `secret-scan.yml` (5 cases — note rename case added per security-sentinel finding §3):
  - **Allowlist positive:** stage a synthesized `__goldens__/fake.snap` with JWT-shaped content → `gitleaks git --staged` exits 0.
  - **Allowlist negative:** stage same content at `apps/web-platform/server/leaked.ts` → exits 1.
  - **Linter positive:** stage `__goldens__/contains-real-email.txt` with `user@gmail.com` (no waiver) → `lint-fixture-content.mjs` exits 1.
  - **Linter waiver:** stage same content with `# gitleaks:allow # issue:#TEST documentation example` → exits 0.
  - **Rename laundering:** `git mv apps/web-platform/server/with-secret.ts apps/web-platform/test/__synthesized__/now-allowed.ts` → assert behavior (deepen-plan recommends fail-closed; verify what gitleaks v8.24.2 actually does and document in secret-scanning.md).
- [ ] AC-10: PR1 includes user-impact-reviewer sign-off in its review thread (per `Brand-survival threshold: single-user incident`).

### Pre-merge (PR2 — Golden Convention + 2 Surfaces)

- [ ] AC-11: `apps/web-platform/test/helpers/golden.ts` exports `expectMatchesGolden(actual: string, goldenPath: string): Promise<void>` — read-only by default; writes via `mkdirSync` + `writeFileSync` when `process.env.GOLDEN_REGEN === '1'`; throws actionable error message when golden missing in non-regen mode (point at trailer rule + exact regen command). Single export. Caller passes already-resolved absolute path (use `import.meta.url` + `dirname` in test file). See §Code Skeletons for full implementation.
- [ ] AC-12: `lefthook.yml` extended with NEW `commit-msg` block (no precedent — only `pre-commit` exists today). Per context7 verification (lefthook v1.4+), `{1}` placeholder is the correct syntax. Hook script: `git diff --cached --name-only | grep -qE '__goldens__/' || exit 0; grep -qE '^Golden-Updated-By: .+' {1} || (echo '...' && exit 1)`. **Documented as UX-nicety only** (architecture-strategist §1) — load-bearing gate is AC-13 CI guard. Hook does NOT fire on `git rebase -i` reword/squash AND can be bypassed with `git commit --no-verify`. Kept because faster-feedback for the common case (vanilla commit) is still useful.
- [ ] AC-13: `.github/scripts/check-goldens-trailer.sh` exists, mirrors the existing `check-pr-body-vs-diff.sh` pattern; `pr-quality-guards.yml` adds a `goldens-trailer-guard` job with path filter on `__goldens__/**`. Script logic: scan `git log <base>..HEAD --format=%B` for `^Golden-Updated-By: .+` in any commit OR scan PR body via `gh api` for the same trailer. Either source satisfies. **Load-bearing gate** — only path that survives `git rebase` and `--no-verify`. Script sanitizes any echoed values per learning `2026-03-05-github-output-newline-injection-sanitization.md` (do NOT echo raw scanner content to `$GITHUB_OUTPUT`/`$GITHUB_STEP_SUMMARY`).
- [ ] AC-14: Two seed golden surfaces under `apps/web-platform/test/__goldens__/` (down from 4; markdown + sql-builders deferred to #3143/#3144 per test-design-reviewer recommendation):
  - **llm-prompts/** — `soleur-go-baseline.test.ts` snapshots `buildSoleurGoSystemPrompt({})` AND `buildSoleurGoSystemPrompt({ artifactPath: '/synth/example.md', activeWorkflow: 'plan' })`. Goldens at `*.golden.txt`. (`replay-prompt` test dropped per test-design recommendation — drop replay; keep just the SoleurGo baseline + artifact variant; full agent-runner system-prompt extraction deferred to #3136.)
  - **api-responses/** — `flags-route.no-auth.test.ts` (the `.no-auth.` infix is documentation convention) **hardened per test-design-reviewer**: `vi.stubEnv` BEFORE dynamic `await import('@/app/api/flags/route')` (prevents module-load env capture); `afterEach(() => vi.unstubAllEnvs())`; consider `vi.resetModules()` if any env capture moves to module-load. Snapshots JSON via inline 5-line shape assertion (`Object.keys(json).sort()` + `Object.fromEntries(Object.entries(json).map(([k,v]) => [k, typeof v]))`) to `*.golden.json`. Verifies `getFeatureFlags()` reads env per-request (not module-load) — confirmed at `apps/web-platform/lib/feature-flags/server.ts`.
- [ ] AC-15: `.github/PULL_REQUEST_TEMPLATE.md` extended with a `Golden-Updated-By:` trailer field (R3 mitigation — squash-merge can drop intermediate commit trailers; PR-body trailer is the durable source).
- [ ] AC-16: `knowledge-base/engineering/operations/golden-tests.md` documents the regen workflow (`GOLDEN_REGEN=1 bun test <path>`), the `Golden-Updated-By:` trailer template, the directory-naming rationale (`__goldens__/` not `__snapshots__/`), and links to `secret-scanning.md` for the bypass discussion. Minimal scope; structure left to author.

### Post-merge (operator)

PR1 + PR2 are pure-PR slices (no terraform apply, no migrations). Issue closure: PR2 body contains `Closes #3121`; PR1 body contains `Ref #3121`.

**Operator follow-up (not part of this plan, but tracked):** enable branch protection on `main` requiring `secret-scan` status check + CODEOWNERS approval. Requires repo-admin scope; file as separate issue at PR1 merge time.

## Files to Edit

- `AGENTS.md` — append `cq-test-fixtures-synthesized-only` rule at end of `## Code Quality` (PR1, last step).
- `lefthook.yml` — add `gitleaks-staged` + `lint-fixture-content` to `pre-commit` (PR1); add new `commit-msg` block (PR2).
- `.gitignore` — append `reports/mutation/`, `.stryker-tmp/`, `mutants/` (PR1).
- `.github/workflows/pr-quality-guards.yml` — add `goldens-trailer-guard` job (PR2).
- `.github/PULL_REQUEST_TEMPLATE.md` — add `Golden-Updated-By:` trailer field section (PR2).

All paths anchored at worktree root `/home/jean/git-repositories/jikig-ai/soleur/.worktrees/behavior-harness-uplift/`.

## Files to Create

PR1:

- `.gitleaks.toml` (root)
- `.github/CODEOWNERS`
- `.github/workflows/secret-scan.yml`
- `apps/web-platform/scripts/lint-fixture-content.mjs` (parent dir `apps/web-platform/scripts/` is brand-new — first file)
- `apps/web-platform/test/__synthesized__/.gitkeep` (NEW dir for synthesized fixtures; replaces broad allowlist of `apps/web-platform/test/fixtures/`)
- `knowledge-base/engineering/operations/secret-scanning.md`

PR2:

- `apps/web-platform/test/helpers/golden.ts`
- `.github/scripts/check-goldens-trailer.sh`
- `apps/web-platform/test/__goldens__/llm-prompts/soleur-go-baseline.test.ts` + `soleur-go-baseline.golden.txt` + `soleur-go-with-artifact.golden.txt`
- `apps/web-platform/test/__goldens__/api-responses/flags-route.no-auth.test.ts` + `flags-route.no-auth.golden.json`
- `knowledge-base/engineering/operations/golden-tests.md`

## Implementation Phases

### Phase 1 — PR1 safety floor (~1 day, expanded after deepen)

**Important:** AGENTS.md edit (step 12) is LAST. The `[hook-enforced]` tag must reference an enforcer that already exists in the branch.

1. Author `.gitleaks.toml` with full rule pack (13+ custom rules per AC-1) using v8.24.2-correct per-rule `[[rules.allowlists]]` syntax.
2. Lookup gitleaks v8.24.2 SHA256 from release page; embed as literal in the workflow YAML.
3. Author `.github/CODEOWNERS` requiring 2nd-reviewer for security-critical files (per AC-2).
4. Author `.github/workflows/secret-scan.yml` with three triggers (`pull_request`, `push:main`, weekly cron); `permissions: contents: read` only; hardcoded SHA256; NO artifact upload.
5. Extend `lefthook.yml` `pre-commit` with `gitleaks-staged` + `lint-fixture-content` commands. No `glob:` on gitleaks (it scans index); array glob on linter (avoid gobwas `**/*` no-op trap).
6. Mkdir `apps/web-platform/scripts/`; mkdir `apps/web-platform/test/__synthesized__/` with `.gitkeep`.
7. Author `apps/web-platform/scripts/lint-fixture-content.mjs` (see §Code Skeletons).
8. Append `.gitignore` with mutation report dirs.
9. Write `knowledge-base/engineering/operations/secret-scanning.md` with all required sections (per AC-7).
10. Add 5 smoke-test jobs to `secret-scan.yml` (allowlist+/−, linter+/waiver, rename laundering).
11. Push branch; verify all 5 smoke tests fire correctly in CI on the draft PR.
12. **Last step:** append `AGENTS.md` `## Code Quality` with the `cq-test-fixtures-synthesized-only` rule (text in §AGENTS.md Rule Draft below; recount via `printf '%s' '<rule>' | wc -c` — expect 458). Run `python3 scripts/lint-rule-ids.py` to confirm rule passes lint.
13. File branch-protection-enablement follow-up issue (operator action).
14. Mark PR ready, secure user-impact-reviewer sign-off + 2nd CODEOWNERS reviewer, merge.

### Phase 2 — PR2 golden convention + 2 surfaces (~half-day, scope-reduced)

PR2 opens after PR1 merges to main (so PR2's branch can be rebased on main and inherit the floor).

1. Write `apps/web-platform/test/helpers/golden.ts` (single export; see §Code Skeletons).
2. Extend `lefthook.yml` with NEW `commit-msg` block (Golden-Updated-By trailer enforcement; UX-nicety only).
3. Author `.github/scripts/check-goldens-trailer.sh` mirroring `check-pr-body-vs-diff.sh`; sanitize output per learning `2026-03-05-github-output-newline-injection-sanitization.md`.
4. Add `goldens-trailer-guard` job to `pr-quality-guards.yml` (path filter on `__goldens__/**`).
5. Edit `.github/PULL_REQUEST_TEMPLATE.md` adding the `Golden-Updated-By:` trailer field.
6. Write 2 seed surfaces (per AC-14):
   - llm-prompts: 1 test file, 2 golden files (no replay-prompt).
   - api-responses: 1 test file, 1 golden file, hardened with `vi.stubEnv` + dynamic `await import` + `afterEach(() => vi.unstubAllEnvs())`.
7. Generate goldens with `GOLDEN_REGEN=1 bun test apps/web-platform/test/__goldens__`.
8. Write `knowledge-base/engineering/operations/golden-tests.md` (regen recipe, trailer template, directory-naming rationale, link to secret-scanning.md).
9. Run trailer-guard smoke: commit a golden change with no trailer → CI rejects; with trailer → passes; with trailer in PR body only → passes.
10. Push PR2, mark ready, merge to main.

## Test Strategy

- **PR1 tests** = CI smoke tests against the gates themselves (AC-9; 5 cases). Wired as a job in `secret-scan.yml` co-located with the gate.
- **PR2 tests** = the golden tests of AC-14 (which test the convention by using it). No new test framework — vitest already in place.

**Per `cq-write-failing-tests-before` (work skill Phase 2 TDD Gate):** PR2's golden tests are first-commit-failing by definition. PR1 is mostly infrastructure and qualifies for the infrastructure-only exemption — write the failing smoke fixtures first, then add the gates.

## Risks

- **R1: gitleaks version drift.** Pinned to v8.24.2 with hardcoded SHA256. v9 (if released) could shift `[extend]` semantics or `[[rules.allowlists]]` schema. **Mitigation:** version pin in `secret-scan.yml`; document upgrade procedure in `secret-scanning.md`; weekly cron triggers regression detection on rule-pack changes.
- **R2: lefthook commit-msg + `--no-verify` are bypassable.** **Mitigation:** CI `goldens-trailer-guard` (AC-13) is the load-bearing gate, surviving rebase/--no-verify.
- **R3: GitHub squash-merge drops trailers from intermediate commits.** **Mitigation:** PR template field for trailer (AC-15); CI guard checks PR body OR commit messages.
- **R4: gitleaks v8.24.2 per-rule `[[rules.allowlists]]` does NOT inherit to default rules.** Each project rule explicitly declares its own allowlist; default-pack rules are scanned without project allowlists. **Mitigation:** acceptable — default rules SHOULD fire on fixtures (e.g., AWS keys never belong even in synthesized fixtures); the per-rule allowlist exists only for the synthesized-by-shape custom rules where false positives are expected. Document explicitly in `secret-scanning.md`.
- **R5: `/api/flags` snapshot is env-dependent.** **Mitigation per test-design-reviewer:** `vi.stubEnv` + dynamic `await import` (defeats module-load capture if any future flag migrates to constant); inline 5-line shape assertion (key presence + types) instead of value comparison; `afterEach(() => vi.unstubAllEnvs())`.
- **R6: agent-runner.ts not refactored.** Only soleur-go-runner is golden-tested. **Mitigation:** filed as #3136.
- **R7: `apps/web-platform/scripts/` is brand-new dir.** **Mitigation:** `.mjs` precedent at `plugins/soleur/docs/scripts/screenshot-gate.mjs`; flagged in PR1 file additions.
- **R8: CODEOWNERS exists but no branch protection on main.** Branch protection requires repo-admin scope. **Mitigation:** AC-2 requires CODEOWNERS file; branch-protection enablement is filed as operator follow-up issue at PR1 merge time. Until enabled, CODEOWNERS is convention rather than enforcement.
- **R9: `git mv` rename may launder secrets through path allowlist.** AC-9 case 5 documents actual gitleaks v8.24.2 behavior. **Mitigation:** if rename launders (gate fails-open), add a CI step using `git diff --cached --diff-filter=R --name-only` to flag rename targets landing in fixture dirs for human review. Resolved during PR1 implementation based on observed behavior.
- **R10: Default gitleaks rules might miss tokens that appear in `prd` Doppler.** Plan adds 13 custom rules but the inventory is best-effort. **Mitigation:** weekly cron with current rule pack catches retroactive coverage; `secret-scanning.md` documents the rule-pack-update workflow.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. This plan's section is filled and threshold is `single-user incident`.
- The `[hook-enforced: .github/workflows/secret-scan.yml]` tag on the new AGENTS.md rule MUST point at an existing workflow after PR1 merges. Phase 1 step 12 (AGENTS.md append) is explicitly LAST for this reason.
- The lefthook `commit-msg` block introduces a NEW stage. `{1}` placeholder is correct (verified via context7). Test on `git commit --amend` specifically.
- gitleaks `--staged` mode reports the worktree path; per-rule `[[rules.allowlists]] paths` regex is anchored against that path. AC-9 smoke tests verify actual behavior.
- The 2 surface tests must NOT modify any existing test file — net-new tests under `apps/web-platform/test/__goldens__/`.
- Lefthook gobwas glob: `**/*` requires explicit subdirs to match (silently skips otherwise). Per learning `2026-03-21-lefthook-gobwas-glob-double-star.md`, use array `glob:` with explicit paths or set `glob_matcher: doublestar`.
- `# gitleaks:allow` waivers MUST include `issue:#NNN <reason>` trailer. CI grep enforces (extend the existing `lint-rule-ids.py` or add a new check).
- Sensitive-path canonical regex is in `plugins/soleur/skills/preflight/SKILL.md` Check 6 Step 6.1 — single source of truth. If this slice references it, copy verbatim and add a drift-detection test.
- When extending `cq-test-fixtures-synthesized-only`'s `[hook-enforced]` tag in future work, recount the rule body bytes against the 600-byte cap.

## Domain Review

**Domains relevant:** Engineering, Legal (carry-forward from brainstorm Phase 0.5).

### Engineering

**Status:** reviewed (carried forward from brainstorm + 6-agent deepen pass)
**Assessment:** CTO recommended A4-lite as first slice for lowest risk; concurred with the safety-floor-first pivot when the operator confirmed user-brand-critical framing. Architecture-strategist (deepen) flagged the load-bearing CODEOWNERS gap (CI is self-disabling without it); folded into AC-2. Test-design-reviewer (deepen) scored the 4-surface plan at D-grade and recommended dropping markdown + sql-builders to follow-ups; folded into AC-14 with #3143/#3144 filed.

### Legal

**Status:** reviewed (carried forward from brainstorm + security-sentinel deepen pass)
**Assessment:** CLO identified the critical gap — repo has zero secret-scanning today (CodeQL is SAST for code paths, not fixture content). Proposed `gitleaks` (MIT, no contagion) as `pre-commit` + CI; AGENTS.md rule; `.gitignore` for mutation report dirs. Confirmed all proposed tooling licenses are clean. Security-sentinel (deepen) found rule pack incomplete (10+ token shapes missing for `prd` Doppler tokens), allowlist scope too broad, artifact upload would leak secrets — all folded into AC-1, AC-3, AC-7. Pre-empted Theme D2 (trajectory dataset) GDPR Article 5(1)(b) issue.

### Product/UX Gate

**Tier:** none
**Decision:** N/A — no `components/**/*.tsx`, `app/**/page.tsx`, or `app/**/layout.tsx` files created.

**CPO sign-off (per `requires_cpo_signoff: true`):** required at plan time before `/work`. Brainstorm Phase 0.1 captured CPO assessment; this plan inherits the framing. Per plan SKILL.md Phase 2.6 tiered model, CPO does NOT re-sign at plan time; `user-impact-reviewer` runs at PR1 review.

## Open Code-Review Overlap

6 open code-review issues touch files this plan references. Disposition: **acknowledge all** — none conflict with this slice's scope. (Detail unchanged from initial plan; see brainstorm doc.)

## Research Insights

### gitleaks v8.24.2 — verified config syntax (best-practices-researcher)

- `[[allowlists]] + targetRules` is **v8.25+ only**. For v8.24.2, use **per-rule `[[rules.allowlists]]`** (nested under each rule).
- `[extend] useDefault = true` inherits all default-pack rules (AWS, GitHub PAT, Stripe, OpenAI, Slack, Discord, SSH-key, etc.).
- `--report-path` JSON includes the `Secret` field; verified redacted with `--redact` only as of v8.18+. Drop artifact upload for safety.
- Hardcode SHA256 in workflow YAML literal (`echo "<sha256>  gitleaks.tgz" | sha256sum -c -`); fetch from release page once at pin time, NOT at runtime.

### lefthook (context7-verified)

- `{1}` is the correct placeholder for the commit-msg file path. Verified against `/evilmartians/lefthook` docs.
- `commit-msg` re-fires on `git commit --amend`; does NOT fire on `git rebase -i` reword/squash.
- gobwas glob: `**` requires 1+ subdirs (silent skip if not nested). Use array glob or `glob_matcher: doublestar`.

### Vitest snapshot conventions (framework-docs-researcher)

- `toMatchFileSnapshot` is gated by `vitest --update`, not env var. Hand-rolled `writeFileSync` helper with `process.env.GOLDEN_REGEN === '1'` is more maintainable.
- `vi.stubEnv` BEFORE dynamic `await import('@/app/api/flags/route')` defeats Vitest's module cache + ESM hoisting. Add `vi.unstubAllEnvs()` in `afterEach`. Add `vi.resetModules()` in `beforeEach` if any future flag captures at module load.
- `@testing-library/react` `container.innerHTML` is the canonical snapshot serialization (over `prettyDOM` which has whitespace inconsistencies across minor versions).

### Existing CI script patterns

- `.github/scripts/check-pr-body-vs-diff.sh` is the precedent for parsing PR body via `gh api`. New `check-goldens-trailer.sh` mirrors that pattern.

### AGENTS.md Rule Draft (458 bytes — verified)

```text
- Test fixtures and golden files (`__goldens__/**`, `**/*.snap`, `apps/web-platform/test/fixtures/**`) MUST contain only synthesized data — no real emails (use `@example.com`/`@test.local`), no Supabase prod-shape UUIDs, no live JWTs/Doppler/BYOK tokens [id: cq-test-fixtures-synthesized-only] [hook-enforced: .github/workflows/secret-scan.yml]. Waive a line with `# gitleaks:allow # issue:#NNN <reason>`. **Why:** #3121 — fixtures bypass prod redaction.
```

Single-enforcer tag (per architecture-strategist pattern-consistency finding — existing `[hook-enforced]` rules tag exactly one enforcer).

### Test-design scoring summary (test-design-reviewer)

Original 4-surface plan: weighted **5.9/10 (D)**. Per-surface: llm-prompts 6.3, markdown 5.6 (defer; react-markdown attr churn = noise), sql-builders 6.0 (defer; raw call-sequence punishes refactors), api-responses 6.6 (keep; harden env-stubbing). Revised 2-surface plan estimated B-grade.

### Code Skeletons

Worked code from best-practices-researcher and framework-docs-researcher. Implementer should use as starting point and adapt to actual codebase structure verified at implementation time.

#### `.gitleaks.toml` (excerpt — 3 of 13 rules)

```toml
title = "Soleur secret-scan floor"
[extend]
useDefault = true

[[rules]]
id = "soleur-byok-key"
description = "Soleur BYOK provider key"
regex = '''sk-soleur-[A-Za-z0-9]{32,}'''
keywords = ["sk-soleur-"]
tags = ["key", "soleur"]
  [[rules.allowlists]]
  description = "Synthesized fixture paths"
  paths = ['''__goldens__/.*''', '''(__snapshots__|__goldens__)/.*\.snap$''', '''apps/web-platform/test/__synthesized__/.*''', '''reports/mutation/.*''']

[[rules]]
id = "doppler-token"
regex = '''dp\.(pt|st|sa|ct)\.[A-Za-z0-9]{40,}'''
keywords = ["dp.pt.", "dp.st.", "dp.sa.", "dp.ct."]
  [[rules.allowlists]]
  paths = ['''__goldens__/.*''', '''(__snapshots__|__goldens__)/.*\.snap$''', '''apps/web-platform/test/__synthesized__/.*''', '''reports/mutation/.*''']

[[rules]]
id = "supabase-service-role-jwt"
description = "Supabase service-role JWT (HS256)"
regex = '''eyJhbGciOiJIUzI1NiI[A-Za-z0-9_\-]{10,}\.eyJ[A-Za-z0-9_\-]{60,}\.[A-Za-z0-9_\-]{20,}'''
keywords = ["eyJhbGciOiJIUzI1NiI"]
entropy = 4.5
tags = ["jwt", "supabase"]
  [[rules.allowlists]]
  paths = ['''__goldens__/.*''', '''(__snapshots__|__goldens__)/.*\.snap$''', '''apps/web-platform/test/__synthesized__/.*''', '''reports/mutation/.*''']
# ... 10 more rules: supabase-anon-jwt, supabase-access-token (sbp_), stripe-webhook-secret (whsec_),
# anthropic-api-key (sk-ant-), resend-api-key (re_), cf-scoped-token, sentry-auth-token (sntrys_/sntryu_),
# discord-webhook-url, database-url-with-password, vapid-private-key
```

#### `lefthook.yml` `pre-commit` additions (PR1)

```yaml
    gitleaks-staged:
      priority: 4
      run: gitleaks git --pre-commit --staged --redact --no-banner --exit-code 1
    lint-fixture-content:
      priority: 4
      glob:
        - "apps/web-platform/test/fixtures/**"
        - "**/__goldens__/**"
        - "**/*.snap"
      run: node apps/web-platform/scripts/lint-fixture-content.mjs {staged_files}
```

#### `lefthook.yml` `commit-msg` block (PR2)

```yaml
commit-msg:
  parallel: false
  commands:
    golden-updated-by-trailer:
      run: |
        git diff --cached --name-only | grep -qE '__goldens__/' || exit 0
        grep -qE '^Golden-Updated-By: .+' {1} || {
          echo "ERROR: Commit touches __goldens__/ but lacks 'Golden-Updated-By:' trailer." >&2
          echo "Append: 'Golden-Updated-By: <name> (<reason>)'. Reword via git commit --amend." >&2
          exit 1
        }
```

#### `apps/web-platform/test/helpers/golden.ts` (full)

```ts
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname } from "node:path";
import { expect } from "vitest";

export async function expectMatchesGolden(
  actual: string,
  goldenPath: string,
): Promise<void> {
  if (process.env.GOLDEN_REGEN === "1") {
    mkdirSync(dirname(goldenPath), { recursive: true });
    writeFileSync(goldenPath, actual, "utf8");
    return;
  }
  if (!existsSync(goldenPath)) {
    throw new Error(
      `Golden file missing: ${goldenPath}\n` +
        `Regenerate with: GOLDEN_REGEN=1 bun test ${goldenPath}\n` +
        `Then commit with trailer: 'Golden-Updated-By: <name> (<reason>)'.`,
    );
  }
  const expected = readFileSync(goldenPath, "utf8");
  expect(actual).toBe(expected);
}
```

#### `apps/web-platform/test/__goldens__/api-responses/flags-route.no-auth.test.ts` (hardened pattern)

```ts
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { expectMatchesGolden } from "../../helpers/golden";

const here = dirname(fileURLToPath(import.meta.url));
const goldenPath = join(here, "flags-route.no-auth.golden.json");

describe("GET /api/flags golden (no-auth, env-stubbed)", () => {
  beforeEach(() => {
    vi.stubEnv("FLAG_KB_CHAT_SIDEBAR", "0");
    vi.stubEnv("FLAG_CC_SOLEUR_GO", "0");
  });
  afterEach(() => {
    vi.unstubAllEnvs();
  });

  it("returns the locked flag shape", async () => {
    const { GET } = await import("@/app/api/flags/route");
    const res = await GET(new Request("http://localhost/api/flags"));
    const body = await res.json();
    // Inline 5-line shape assertion (key presence + types, not values).
    const shape = {
      keys: Object.keys(body).sort(),
      types: Object.fromEntries(
        Object.entries(body).map(([k, v]) => [k, typeof v]),
      ),
    };
    await expectMatchesGolden(JSON.stringify(shape, null, 2) + "\n", goldenPath);
  });
});
```

## Open Questions / Deferrals

- Should the `Golden-Updated-By:` trailer be a closed enum or free-text? **Plan decision: free-text** in slice 1; track follow-up if it boilerplates within 2 months.
- Branch-protection enablement on main: filed as operator follow-up (requires repo-admin scope; cannot be done in-PR).

## Plan Review Application Log

This plan was reviewed by DHH, Kieran, code-simplicity-reviewer (initial pass) and best-practices-researcher, framework-docs-researcher, architecture-strategist, security-sentinel, test-design-reviewer, learnings-researcher (deepen pass). Major changes:

**Initial review (applied previously):**

- Drop `expectStableShape`; inline gitleaks install; cut daily cron; collapse R2+R3; drop `// fixture-allow:` (use `# gitleaks:allow`); fix path bugs; reorder PR1; recount AGENTS.md bytes; add PR template; tighten AC-3; verify `{1}` syntax via context7; clarify merge graph.

**Deepen pass (applied here):**

- **gitleaks v8.24.2 schema fix:** original plan used `[[allowlists]] + targetRules` (v8.25+ syntax); rewrote to per-rule `[[rules.allowlists]]` (v8.24.2-correct). Pinned version explicitly in frontmatter.
- **CODEOWNERS** (architecture-strategist §2): added AC-2; without it CI is self-disabling.
- **Rule pack expansion** (security-sentinel §1): from 3 custom rules to 13, covering token shapes actually present in `prd` Doppler.
- **Allowlist tightening** (security-sentinel §2): replaced `apps/web-platform/test/fixtures/.*` with new `apps/web-platform/test/__synthesized__/` dir; `(__snapshots__|__goldens__)/.*\.snap$` instead of repo-wide `.*\.snap$`. `qa-auth.ts` no longer allowlisted.
- **Rename laundering smoke test** (security-sentinel §3): added 5th smoke case to AC-9.
- **Drop `pull-requests: read` permission** (security-sentinel §4): least-privilege.
- **Drop artifact upload** (security-sentinel §4): would leak unredacted secrets on public-repo runs.
- **Re-add weekly cron for retroactive scans** (security-sentinel §5): catches rule-pack updates that need to re-scan history.
- **Hardcode SHA256 in workflow YAML literal** (security-sentinel §6): not fetched from same origin as binary.
- **AC-7 runbook content enumerated** (security-sentinel §7): per-token rotation, decision tree, notification, forensics, waiver discipline.
- **AGENTS.md rule recount + single-enforcer tag** (architecture-strategist §5): 458 bytes; `[hook-enforced: .github/workflows/secret-scan.yml]` (single load-bearing enforcer per pattern-consistency).
- **Drop markdown + sql-builders surfaces** (test-design-reviewer): defer to #3143 + #3144; ship PR2 with 2 surfaces (llm-prompts scoped + api-responses hardened) for B-grade test quality. Drop replay-prompt sub-test from llm-prompts.
- **Harden api-responses golden** (test-design-reviewer): `vi.stubEnv` + dynamic `await import` + `vi.unstubAllEnvs()` afterEach; defeats module-load env capture if any future flag changes.
- **AC-12 (lefthook commit-msg) kept but documented as UX-nicety only** (architecture-strategist §1): load-bearing gate is AC-13 CI guard.
- **`# gitleaks:allow` waivers require `issue:#NNN <reason>`** (learnings-researcher §5): single waiver vocabulary with mandatory justification.
- **Lefthook gobwas glob warning** (learnings-researcher §1): array glob, not `**/*`.
- **`$GITHUB_OUTPUT` redaction** (learnings-researcher §2): no raw scanner content to outputs.
- **Helper bash safety** (learnings-researcher §6): ESM Node, no `grep -qF`.
- **Code skeletons added** (best-practices + framework-docs): `.gitleaks.toml` excerpt, lefthook YAML, golden.ts full impl, hardened api-responses test.

Rejected (operator-chosen via brainstorm; not re-litigated):

- Two-PR split (review-blast-radius reasons; different reviewer skill sets).
- Trailer apparatus retention (structural author-prompt; load-bearing CI gate).
- `__goldens__/` directory naming (brainstorm decision #4).
- Separate secret-scanning.md + golden-tests.md docs (different audiences).

## Follow-up Issues Filed

| # | Title | Why deferred |
|---|---|---|
| #3130 | A1 mutation testing pilot | Blocked by this slice + #3120 (eval-suite calibration target) |
| #3131 | A3 ATDD trigger hardening | CPO-recommended slice; deferred to ship after this safety floor |
| #3132 | A4-lite fitness functions | Split into 3 sub-tasks; independent of this slice |
| #3133 | A4-p95 latency gate | Needs own brainstorm |
| #3136 | Extract `buildAgentRunnerSystemPrompt` for golden testing | Refactor risk too high to bundle with PR2 |
| #3143 | Markdown golden surface — behavioral assertions | Raw-HTML snapshots = noise (test-design 3-5/10) |
| #3144 | SQL-builders golden surface — query-shape normalizer | Raw call-sequence punishes refactors (test-design 3/10) |

Plus operator follow-up (file at PR1 merge time): branch-protection enablement on `main` requiring `secret-scan` status check + CODEOWNERS approval.
