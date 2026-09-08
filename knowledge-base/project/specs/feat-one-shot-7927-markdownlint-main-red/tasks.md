# Tasks — markdownlint: clear the red tree and give the linter a second home in CI

Plan: `knowledge-base/project/plans/2026-09-08-fix-markdownlint-main-red-and-ci-blind-spot-plan.md`
Issue: #7927 (also closes #7837, #7832, #2685; refs #7817 Part 2)

Phase order is load-bearing. 1 before 4, or the sweep corrupts prose. 2 before 3, or the guard
has nothing to run.

## Phase 1 — Root cause

- [ ] 1.1 Locate the two escaped-backtick spans in `plugins/soleur/skills/work/SKILL.md` by
      content anchor: `against an UNTYPED client`, and the one containing the literal-backtick
      grep in the commit-message trap bullet. Both anchors verified unique.
- [ ] 1.2 Replace each with an outer double-backtick run, padding spaces, and real inner
      backticks. No backslashes.
- [ ] 1.3 Decide the four deliberate-space MD038 sites individually — anchors
      `optional`/`prefix` in the drift-guard bullet, `never single-space`, and two on the
      `Legal-doc edits have TWO independent mirror gates` line. Inline disable-line comment or
      the outer-delimiter idiom; never delete the illustrated space.
- [ ] 1.4 Confirm the file is clean by the gate's own invocation.

## Phase 2 — The single invoker

- [ ] 2.1 Add `markdownlint-cli` to root `package.json` `devDependencies`, pinned exactly (no
      caret). Regenerate `package-lock.json`.
- [ ] 2.2 Create `scripts/markdown-lint.sh`: assert the working directory is the repository
      root and both config files exist; assert the binary version equals the manifest pin and
      fail loudly if the binary is absent (no network fallback).
- [ ] 2.3 Implement `--repo-sweep`: derive tracked `*.md` minus
      `git ls-files -c -i --exclude-from=.markdownlintignore -- '*.md'`, under `LC_ALL=C`.
- [ ] 2.4 Implement explicit-paths mode for the hook: filter given paths through the same
      exclusion; exit 0 with a printed reason when none remain.
- [ ] 2.5 Add the anti-vacuity pair, sweep mode only: `MIN_SWEPT_FILES` with a
      `<n> against <m>, measured <date>` comment, and an expected-top-level-roots set
      assertion. Copy three details from `scripts/lint-orphan-test-suites.sh` rather than
      re-deriving them: the roots assertion is a SUPERSET not an equality; the derivation
      carries its own non-vacuity check; and the expected set is measured from the producer's
      own output, never written from memory. Size the floor's slack deliberately — slack is
      narrowing budget, not safety margin.
- [ ] 2.6 Add the static remediation block emitted on non-zero exit.

## Phase 3 — The guard's suite

- [ ] 3.1 Create `scripts/markdown-lint.test.sh` covering M1-M7 and H1-H3 from the plan's
      Guard Contract, emitting one result line per row.
- [ ] 3.2 Implement the call-site check as a NEGATIVE grep for a markdownlint binary token
      across `lefthook.yml`, `.github/**` and `scripts/**`, excluding the script itself. Not a
      count.
- [ ] 3.3 Register with exactly one explicit `run_suite` line in `scripts/test-all.sh`. Do not
      add a workflow step as well.
- [ ] 3.4 Confirm `bash scripts/lint-orphan-test-suites.sh` reports zero orphans and no
      double coverage.

## Phase 4 — Content-safe sweep

- [ ] 4.1 Disable MD025 and MD001 in `.markdownlint.json`, with a comment naming the count and
      the MD041 coherence argument. No other rule change.
- [ ] 4.2 Add `knowledge-base/project/` to `.markdownlintignore`, with a comment naming the
      blocking linter and the measured file and error counts.
- [ ] 4.3 Run `--fix` with MD037, MD038, MD049 and MD050 withheld, three passes, over the
      in-scope set. Commit alone.
- [ ] 4.4 Before touching anything under `.grok/`, `.openhands/` or `.gemini/`, determine
      whether it is generated (start at `plugins/soleur/scripts/sync-grok-agent-compat.ts`).
      Fix the source and regenerate rather than the copy.
- [ ] 4.5 Resolve the four withheld rules by hand, per site.
- [ ] 4.6 Resolve the remaining residual by hand. MD052 are broken reference links — fix, never
      suppress.
- [ ] 4.7 Fold in `knowledge-base/product/roadmap.md` (#7832),
      `knowledge-base/legal/article-30-register.md` (#7817 Part 2),
      `plugins/soleur/skills/dhh-rails-style/SKILL.md` (#2685),
      `apps/web-platform/infra/sentry/README.md`.

## Phase 5 — Legal corpus, by hand

- [ ] 5.1 Convert the 12 bare addresses to autolinks across the 5 canonical documents and the
      5 mirrors, identically. Includes two section headings — `privacy-policy.md` §4.13 and
      `gdpr-policy.md` §3.10.
- [ ] 5.2 For the four sites on `**Last Updated:**` lines, change the bracketing only. No
      wording, date, amendment note, version bump or re-consent.
- [ ] 5.3 MD032 on the two CLA documents, canonical only — the mirrors already carry the
      blockquote blank line.
- [ ] 5.4 Re-pin 7 entries in `apps/web-platform/lib/legal/legal-doc-shas.ts`.
      `TC_DOCUMENT_SHA` stays untouched.
- [ ] 5.5 Run `scripts/lint-legal-mirror-drift-baseline.sh`. Four sites sit on already-drifting
      lines; use the script's documented `SOLEUR_LEGAL_DRIFT_ACCEPT` escape with a reason naming
      #7927, the byte-identical rendered text, and the pending resync.
- [ ] 5.6 Run `scripts/lint-legal-scope-block-placement.sh` and
      `apps/web-platform/scripts/check-tc-document-sha.sh`.

## Phase 6 — CI wiring

- [ ] 6.1 Add the job to `.github/workflows/pr-quality-guards.yml`, shaped like
      `guard-script-fixture-tests`: no `if:`, no opt-out label, action refs pinned to
      40-character SHAs with version comments.
- [ ] 6.2 Register the context in `infra/github/ruleset-ci-required.tf`.
- [ ] 6.3 Register it in `scripts/ci-required-ruleset-canonical-required-status-checks.json`.
- [ ] 6.4 Register it in `scripts/required-checks.txt` with the empty-intersection derivation
      spelled out (both `ALLOWED_PATHS` members, and why each is outside the swept set).
- [ ] 6.5 Bump the deliberate literal `22` to `23` in
      `tests/scripts/test-audit-ruleset-bypass.sh`.
- [ ] 6.6 Confirm `tests/scripts/test-audit-ruleset-bypass.sh` and
      `plugins/soleur/test/required-checks-canonical-parity.test.sh` both exit 0.

## Phase 7 — Prove it can fail

- [ ] 7.1 Execute M1-M7 and H1-H3 against the built gate; record observed result per row.
- [ ] 7.2 Confirm every acceptance criterion in the plan, by the command it names.
- [ ] 7.3 File the two deferral issues named in the plan, with their measured figures.
