---
title: Behavior Harness Uplift — A2 Goldens + Secret-Scanning Floor (Slice 1 of #3121)
date: 2026-05-04
branch: behavior-harness-uplift
issue: 3121
pr: 3129
parent_brainstorm: knowledge-base/project/brainstorms/2026-05-04-harness-engineering-review-brainstorm.md
sibling_issues:
  - "#3120 (Theme D — harness eval suite)"
  - "#3122 (Theme C — scheduled audits + skill freshness)"
follow_up_issues_filed:
  - A1 mutation testing pilot
  - A3 ATDD trigger hardening
  - A4-lite fitness functions (dep-cruiser + bundle + complexity)
  - A4-p95 latency gate
user_brand_critical: true
---

# Behavior Harness Uplift — A2 Goldens + Secret-Scanning Floor

This brainstorm scopes the **first shippable slice of #3121** (Theme A from the harness engineering audit, PR #3119). The original issue bundled four sub-scopes (A1 mutation testing, A2 goldens, A3 ATDD hardening, A4 fitness functions). After domain-leader assessment (CTO + CPO + CLO), the operator chose to ship A2 first, gated by a secret-scanning floor that lands before any snapshot file can exist in the repository.

## What We're Building

**Two PRs against #3121, in sequence.**

### PR1 — Safety floor (~half-day)

Lands the irreversible guardrails before any snapshot or fixture file exists in the repo.

- `gitleaks` integrated into:
  - `lefthook.yml` `pre-commit` stage (blocks local commits)
  - A new `.github/workflows/secret-scan.yml` workflow on `pull_request` (blocks merge)
  - Custom rule pack scoped to `__goldens__/**`, `**/*.snap`, `tests/fixtures/**`, `reports/mutation/**` matching at minimum: `sk_live_`, `sk_test_`, `sbp_`, `eyJ` (JWT prefix), `doppler_`, `xoxb-`, `ghp_`, `Bearer\s+[A-Za-z0-9._-]{20,}`, plus an email regex (`[a-zA-Z0-9._%+-]+@(?!example\.com|test\.local)`)
- New AGENTS.md Code Quality rule `cq-test-fixtures-synthesized-only`: "Test fixtures and snapshots MUST contain only synthesized data — no production database dumps, no replayed user requests, no real email addresses (use `@example.com`/`@test.local`), no real org IDs." With `[hook-enforced: secret-scan.yml + lefthook gitleaks]` tag.
- `.gitignore` entries for `reports/mutation/`, `.stryker-tmp/`, `mutants/` (defensive — pre-empts the A1 follow-up's mutation-report leakage).
- Fixture-content linter (small node script invoked by lefthook) sweeping `__goldens__/**` + `**/*.snap` + `tests/fixtures/**` for real-email patterns and prod-shaped UUIDs (the format Supabase issues for org IDs).
- Documentation: `knowledge-base/engineering/operations/secret-scanning.md` capturing the rule pack, the `// gitleaks:allow` waiver process (must include `Why:` line + reviewer sign-off), and the test-data invariant.

### PR2 — Golden-test convention + 4 seed surfaces (~1-2 days)

With the floor in place, lands the convention itself plus four documented surfaces proving the regen workflow.

- New convention: `__goldens__/` directory (deliberately NOT `__snapshots__/` — breaks Jest/Vitest `-u` muscle memory), one helper at `apps/web-platform/test/helpers/golden.ts` that reads/writes goldens.
- Regeneration gate: helper requires `GOLDEN_REGEN=1` environment variable to write (env var instead of CLI flag defeats `vitest --update` scripted bypass).
- Pre-commit hook (`lefthook.yml`): any `git diff --cached --name-only` match on `__goldens__/**` requires the commit body to contain a `Golden-Updated-By:` trailer with a non-empty reason. Hook rejects otherwise.
- Four seed surfaces (one `__goldens__/` dir + ≥1 golden file + ≥1 consuming test each):
  1. **LLM prompt outputs** — snapshot the assembled prompt strings produced by `apps/web-platform/server/soleur-go-runner.ts` and `apps/web-platform/server/agent-runner.ts` for synthesized inputs.
  2. **Markdown→HTML rendering** — two surfaces under one convention: docs site (Eleventy chain in `plugins/soleur/docs/`) and chat message rendering (`apps/web-platform/components/chat/message-bubble.tsx`'s markdown pipeline).
  3. **SQL builders** — snapshot the literal SQL produced by query construction in `apps/web-platform/server/` for representative synthesized inputs. Catches RLS-bypass regressions and accidental N+1.
  4. **API response shapes** — snapshot JSON shape (not values) of Next.js route handler responses for representative synthesized request fixtures. Highest-risk surface — the consuming test must be tagged `@goldens-no-auth` and the helper enforces no real auth context can reach the snapshot serializer.
- Documentation: `knowledge-base/engineering/operations/golden-tests.md` covering the convention, the regen workflow, the trailer enforcement, and the four seed surfaces as worked examples.

## User-Brand Impact

**Artifact:** golden snapshots and (future) mutation-test reports committed to the public repo at `github.com/jikig-ai/soleur` (Apache-2.0).

**Vector:** an inadvertent commit of a snapshot containing real credential material (BYOK API key fragment, Supabase service-role JWT, Bearer token in a response header, real user email) places that material in `git log` permanently — `git filter-repo` is the only remediation and it breaks every fork and clone.

**Threshold:** `single-user incident` — one leaked BYOK key exposes that user's third-party model spend; one leaked service-role JWT exposes every user's data; one leaked email is a GDPR/privacy-policy disclosure event.

**Mitigations landing in PR1 (irreversible floor):**
- `gitleaks` blocks both commit-time and merge-time
- AGENTS.md rule `cq-test-fixtures-synthesized-only` makes the invariant explicit and discoverable
- Fixture-content linter catches real-email + prod-UUID patterns even when they don't match a secret regex
- `.gitignore` for mutation report directories pre-empts the A1 follow-up's leak surface

**Why this slice goes first:** every other Theme A sub-scope (A1 mutation, A2 goldens themselves, future A4 work that ever serializes data into reports) flows through these guardrails. Landing them after any single snapshot file exists is structurally too late — the snapshot would already be in `main` history.

## Why This Approach

Five agents (CTO, CPO, CLO + repo-research-analyst + learnings-researcher) converged on three findings:

1. **A4-p95 latency must be split out** of #3121 — needs sustained traffic baseline, Sentry plumbing, separate brainstorm.
2. **A1 mutation testing has a load-bearing secret-leak vector** that the issue body undersold — Stryker re-runs the test suite N times with mutated source; if any test loads real credentials, every mutant log/snapshot becomes an exfiltration surface.
3. **Repo has zero infra for any sub-scope today** (no Stryker, no `__snapshots__`, no ESLint config, no bundle analyzer, no dep-cruiser, no coverage tooling, no gitleaks/trufflehog/detect-secrets). Every sub-scope starts greenfield.

CTO and CPO disagreed on whether A4-lite or A3 should ship first. The operator answered the user-impact framing with "all of them" (trust-breach + productivity drag + secret-leak + internal). That answer pushed the safety floor — proposed by CLO — to the front: it is the only slice that closes the irreversible failure mode (secret in `git log` of a public repo), and it is a prerequisite for any future A1/A2 work regardless.

## Key Decisions

| # | Decision | Rationale |
| --- | --- | --- |
| 1 | Ship A2 + secret-scanning floor as the first slice of #3121 | Safety-first; prevents the irreversible failure mode (secret in public-repo git history) before any snapshot exists |
| 2 | Two PRs (floor first, goldens second) | Lower per-PR blast radius; the floor is structurally first — it's in `main` before any golden file can ever be added |
| 3 | All 4 surfaces (LLM prompts, MD→HTML, SQL builders, API responses) seeded in PR2 | Operator chose to exceed the issue's "≥3 surfaces" criterion; sets a stronger floor for the convention |
| 4 | `__goldens__/` directory, NOT `__snapshots__/` | Breaks Jest/Vitest `-u` muscle memory; forces explicit `GOLDEN_REGEN=1` env var to regenerate |
| 5 | `Golden-Updated-By:` trailer enforcement via lefthook | Every snapshot diff requires a stated reason; defeats blind approval-fatigue acceptance |
| 6 | API response surface requires `@goldens-no-auth` tag | Highest-risk surface; helper enforces no real auth context reaches the serializer |
| 7 | New AGENTS.md rule `cq-test-fixtures-synthesized-only` | Makes the synthesized-only invariant explicit + tagged `[hook-enforced: secret-scan.yml + lefthook gitleaks]` |
| 8 | Repurpose #3121 as the umbrella + first-PR issue | Original issue bundled 4 scopes; repurposed to scope only A2+floor with clear pointers to follow-up issues |
| 9 | File 4 follow-up issues during this brainstorm action | Per `wg-when-deferring-a-capability-create-a` — A1, A3, A4-lite, A4-p95 each get a tracked issue |
| 10 | Independent of #3120 sequencing | A2 + floor needs no eval-suite calibration; can ship in parallel with #3120 |

## Open Questions

- Should the `Golden-Updated-By:` trailer be a **closed enum** (`schema-change`, `prompt-tuning`, `intentional-output-shift`, `flake-fix`) or free-text? CPO recommended closed-enum patterns for skip rationales (boilerplates within 2 weeks if free text). Defer to PR2 implementation; flag for `/plan` to decide.
- Should the secret-scanning floor scope `tests/fixtures/**` from day 1, or wait until a real fixture exists? The repo has only one fixture file today (`apps/web-platform/test/fixtures/qa-auth.ts`); scoping it now is cheap and pre-empts future drift.
- Whether `gitleaks` should run on the entire repo (slower, broader coverage) or only on diff (faster, lower CI cost). Recommend diff-only for `pre-commit` + `pull_request`, full sweep nightly via a `scheduled-secret-scan.yml` workflow. Defer to `/plan`.

## Tracked Follow-ups

Filed during this brainstorm action (see `gh issue list --milestone "Post-MVP / Later"` for current state):

- **A1 — Mutation testing pilot** — Stryker on `apps/web-platform/server/`, blocked by this PR + #3120 (eval-suite calibration target). Per-file mutation score on curated mutator subset (exclude `StringLiteral`/`ArrayLiteral`); `env -i` runner sandbox.
- **A3 — ATDD trigger hardening** — tighten `cq-write-failing-tests-before` to fire on `apps/*/app/**/page.tsx`, `apps/*/components/**/*.tsx`, `apps/*/app/**/route.ts` globs. `## TDD Skip Rationale` requires closed-enum category (`styling-only|config|migration|emergency-rollback`).
- **A4-lite — Fitness functions** — split into 3 sub-tasks: dep-cruiser layer boundaries (`server/` vs `app/` vs `components/`), `@next/bundle-analyzer` + per-route budget, `eslint complexity` rule with project-tuned threshold. Bump-approval pattern: `bundle-bump` PR label only `simplicity-reviewer`/admin can apply.
- **A4-p95 — Latency gate** — separate brainstorm needed; requires Sentry perf-data plumbing or metrics-export wiring before a CI gate can read p95.

Themes B (symbol-level grounding), C (drift detection — partially #3122), D (trajectory dataset — #3120), E (build-to-delete cadence), F (topology bundles): not in this slice; see source brainstorm for context.

## Domain Assessments

**Assessed:** Engineering (CTO), Product (CPO), Legal (CLO).

### Engineering

**Summary:** Recommended A4-lite as first slice (3 config files, lowest risk, computational fitness functions). Flagged A1's per-file mutation-score gameability via trivial-mutant inflation; A3's "skip rationale boilerplate" failure mode within 2 weeks; A4 budget-bump loophole. Identified the secret-leak vector for A1 as the load-bearing risk and proposed `env -i` sandbox + tagged-test-subset enforcement. Concurred with the safety-floor-first pivot when the operator confirmed user-brand-critical framing.

### Product

**Summary:** Recommended A3-only as first slice (highest user-protective leverage, direct prevention of #2887-class trust-breach via untested UI-route ships). Flagged A1 as having no calibration target without #3120 landing first. Concurred with the safety-floor-first pivot once the operator chose the CLO-driven approach. Confirmed #3121 should be repurposed as the umbrella for A2 + safety-floor and that A1/A3/A4 each spin out to tracked issues.

### Legal

**Summary:** Identified critical gap — repo has zero secret-scanning today (CodeQL is SAST for code paths, not fixture content). Snapshot frameworks serialize whatever the test produced; once committed to a public repo, `git filter-repo` is the only remediation and it breaks every fork. Recommended `gitleaks` (MIT, no contagion) as `pre-commit` + CI with snapshot-scoped rule pack, plus `cq-test-fixtures-synthesized-only` AGENTS.md rule, plus `.gitignore` for mutation report dirs. Confirmed all proposed tooling licenses are clean (Apache-2.0/MIT/BSD); flagged Stryker dashboard as a data-egress consideration (disable in CI). Pre-empted Theme D2 (trajectory dataset) by noting fixture pollution would propagate to any future dataset and create a GDPR Article 5(1)(b) purpose-limitation issue.

## Capability Gaps

None. All proposed tooling (gitleaks, lefthook, GitHub Actions, vitest helpers) and patterns (snapshot tests, hook-enforced rules, AGENTS.md cq- rules) already have primitives in the repo. No new agents/skills required.
