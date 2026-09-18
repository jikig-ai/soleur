---
title: "Local green baseline for test-all (precondition for #8231)"
issue: 8231
bundles: [8238, 8250, 8261, 8263, 8266]
branch: feat-8231-parallel-test-all-next
lane: cross-domain
brand_survival_threshold: none
brainstorm: knowledge-base/project/brainstorms/2026-09-18-parallel-test-all-green-baseline-brainstorm.md
---

# Spec: local green baseline for `scripts/test-all.sh`

## Problem Statement

The #8231 parallel scheduler plan
(`knowledge-base/project/plans/2026-09-17-feat-parallel-local-test-all-suites-plan.md`) is blocked
because its Phase 1 and Phase 4 methods need a serial baseline where RED means something. On a
developer host, 9 registered suites are red today, even though `ci.yml` on `main` is green. Each one
is a host-vs-CI divergence already tracked by an open issue.

## Goals

- G1. A full serial `TEST_GROUP=all bash scripts/test-all.sh` on a developer host (Arch/Omarchy,
  16 cores, Node 26, mise shims) finishes with zero FAIL rows. Each suite either passes or
  shows a declared, named SKIP.
- G2. No suite reports a verdict about its subject when the actual cause is an unrunnable tool
  (the #8266 class).
- G3. The #8231 plan can resume at Phase 0.5 without changing its method.

## Non-Goals

- Building the parallel scheduler (plan Phases 1–5 stay under #8231).
- #8112 (main-branch health monitor). That is a different signal, and CI is green.
- #8045 (pre-commit hook glob scoping) and decision-challenge UC-1. Both stay open as recorded.

## Functional Requirements

- FR1 (#8266). Every site that runs gitleaks, `/usr/bin/time`, or `bc` tells apart "tool
  unrunnable" and "subject verdict". `.claude/hooks/git-commit-secret-scan.sh` must not fail open
  when gitleaks cannot run.
- FR2 (#8250). `notice-frontmatter` TS-cron-5 no longer hard-depends on GNU `/usr/bin/time`.
- FR3 (#8261). `apps/web-platform` component suites pass on every Node major that `engines` admits,
  or `engines` stops admitting the ones they fail on.
- FR4 (#8263). `guardrails.test.sh` kb-index sentinel arm and `scratch-root.test.sh` containment /
  HOME-fallback arms pass. Root cause first: find out whether it is an env leak or a resolver defect.
- FR5 (#8238). `lint-legal-scope-block-placement` arm (a) passes, and its positive controls are
  non-vacuous.

## Technical Requirements

- TR1. Evidence for G1 is one full serial battery run, recorded with its timing log, in
  `knowledge-base/project/specs/feat-one-shot-8231-parallel-test-all/acceptance-evidence.md`
  (new section).
- TR2. Every FR fix is shown RED-before / GREEN-after on the developer host AND stays green in CI.
- TR3. The PR uses `Ref #8231` and `Closes` for each of #8238, #8250, #8261, #8263, #8266 in the
  body only.
- TR4. The plan decides the gitleaks toolchain question (repo `mise.toml` pin versus declared skip)
  and records whether a declared SKIP satisfies the Phase 1 precondition.
