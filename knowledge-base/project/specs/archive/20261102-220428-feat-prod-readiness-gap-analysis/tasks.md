# Tasks: customer-repo launch-check

Plan: knowledge-base/project/plans/2026-11-02-feat-customer-repo-readiness-gap-analysis-plan.md
Spec: knowledge-base/project/specs/feat-prod-readiness-gap-analysis/spec.md
PR split: PR-A = phases 0-4, PR-B = phase 5, then phase 6.

## Phase 0 - Tests and fixtures first (RED)

- 0.1 Create `plugins/soleur/skills/launch-check/test/` suites: scan, baseline, render, redact-gate, safe-walk-parity, identity, wording (all failing)
- 0.2 Build fixture repos at test time (minimal, nextjs-healthy, python, planted-secret assembled from fragments, symlink-escape, renamed-file, multi-hit) under a scratch dir with a cleaned git env
- 0.3 Commit `test/fixtures/report-sample.md` (valid state block)
- 0.4 Add the per-row fixture-coverage test over `checks.tsv`
- 0.5 Pin finding identity (`path` and `repo` keys) in `identity.test.sh`

## Phase 1 - Skeleton, walker, scanner

- 1.1 `SKILL.md` (disable-model-invocation, scripts-only-write rule, ask-before-create rule, headless preview-only)
- 1.2 `scripts/launch-check.sh` subcommands scan/render/issues/verify-report, flags --target --dry-run --show-secrets, plugin-root identity resolution with fail-closed reasons
- 1.3 `lib/safe-walk.sh` (walker, `safe_path`, stack detection) + parity test green
- 1.4 `references/checks.tsv` (17 deterministic rows, 4 judged rows), `retired-checks.tsv`, `severity-rubric.md`
- 1.5 `lib/checks.sh` data-driven presence engine + named detectors
- 1.6 Closed judged-finding schema and validator

## Phase 2 - Baseline, render, state, diff

- 2.1 `lib/baseline.sh` derived from `guards.tsv` by header name; empty-manifest hard failure
- 2.2 `lib/redact-gate.sh` `emit_checked` (temp file, sentinel + gitleaks, rc capture, trap cleanup, rename)
- 2.3 `lib/render.sh` report, banner/footer, state block, closed/new/accepted/retired sections, catalog-changed notice
- 2.4 `references/banner.txt`, `footer.txt`, `banned-words.txt`; wording test green
- 2.5 `verify-report` parse-only subcommand

## Phase 3 - Self-test and triage

- 3.1 Dry-run scan + render on this repo
- 3.2 Dry-run scan + render on one public non-Soleur Node/TS repo (scratch clone)
- 3.3 Record every gap with a disposition in `self-test.md`; fix detector false positives

## Phase 4 - Registration, ADR, C4

- 4.1 Harness mirror `plugins/soleur/cursor/skills/soleur-launch-check/SKILL.md`; diff touch list against `git show 93583f8d27 --stat`
- 4.2 README counts, `docs/_data/skills.js`, test registries, `components.test.ts` if a derived count moves
- 4.3 ADR-314 via `soleur:architecture` (provisional ordinal)
- 4.4 C4: launchCheck component, `plugin -> github` edge, view include, skill count 105 -> 106, regenerate `model.likec4.json`; run c4 syntax, render and count-parity tests
- 4.5 Re-run `gdpr-gate` on the diff

## Phase 5 - Issue epic (PR-B)

- 5.1 `lib/issues.sh`: preflight, preview with visibility warning and exclusions, 30-issue cap
- 5.2 `gh_write` chokepoint, saved-plan-only create, headless refusal, backoff
- 5.3 Labels (`lc:` prefix, create-if-absent), epic marked section, sub-issue API with task-list fallback
- 5.4 Marker-based idempotency; closed marked issue = accepted; never close issues
- 5.5 Stub-`gh` suite `issues.test.sh`
- 5.6 End-to-end run against a throwaway repo; record result in PR body

## Phase 6 - Roadmap and tracking issue

- 6.1 Roadmap Phase 4 row 4.14 (P2, depends on 4.12)
- 6.2 File the tracking issue under the Phase 4 milestone with `Mandated-By: wg-every-feature-listed-in-a-roadmap-phase`; rewrite plan `issue:` frontmatter
- 6.3 Run `roadmap-reconcile.sh validate`
