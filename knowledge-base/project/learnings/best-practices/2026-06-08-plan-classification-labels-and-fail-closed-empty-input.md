---
title: Plan-specced classification labels must be verified live; a fail-closed filter's modal bug is empty-input bypass
date: 2026-06-08
category: best-practices
tags: [planning, eligibility-filter, fail-closed, gh-labels, brand-critical, multi-agent-review, tdd]
feature: shortform-feature-tweets
issue: 5021
pr: 5017
---

# Plan classification labels must be verified live; fail-closed filters fail open on the empty case

## Problem

`feat-shortform-feature-tweets` (#5021) added `tweet-eligibility.sh` — a **brand-critical,
fail-closed** filter deciding whether a merged PR may become a draft tweet. Two compounding
issues surfaced during `/work`:

1. The 10-agent-reviewed plan specced the eligibility allow-set as labels `user-facing` +
   `type/feature` and a deny-set of `security`/`infra`/`internal`/`dark-launch`. **None of those
   labels exist on this repo's PRs.** `gh label list` + sampling 25 recent merged PRs showed PRs
   carry `semver:*` + `app:web-platform` + a conventional-commit `feat(...)`/`fix(...)` title; the
   `type/*` labels are issue-triage labels, never applied to PRs. Implementing the plan verbatim
   would have made the filter exclude **100% of real PRs** — the feature dead on arrival, "safe"
   but inert.

2. Even after the allow/deny sets were corrected, multi-agent post-implementation review
   (security-sentinel + user-impact-reviewer + pattern-recognition) found **three P1 fail-opens in
   a green-CI fail-closed filter**: (a) an empty `gh pr diff --name-only` result silently disabled
   the entire deny-path layer and reached `eligible` on title+label alone; (b) the deny-path glob
   list omitted real infra/credential/money surfaces (vercel.json, k8s/helm, docker-compose,
   middleware.ts, supabase config, billing/stripe/oauth/api-keys); (c) the draft validator's
   frontmatter extractor failed open on an unterminated `---` block, passing a malformed draft.

## Key Insight

**(A) Plan-quoted classification labels/enums are preconditions to verify against the live system,
never facts — especially on a brand-critical gate.** A plan (even a heavily-reviewed one) can be
authored against a label taxonomy that doesn't match how the repo actually labels PRs. Before
coding a label/enum-gated filter, run `gh label list` AND sample real artifacts (`gh pr list
--state merged --json labels,title`) to confirm both the names exist AND are applied in practice.
The `type/feature` issue-triage label being absent on PRs is invisible until you sample. When the
gate is brand-critical and the correct signal is non-obvious, surface the corrected mapping to the
operator (a wrong allow-set tweets forbidden content; a wrong-but-strict one tweets nothing) —
this is exactly the decision `AskUserQuestion` exists for, even in pipeline mode.

**(B) A fail-closed filter's modal bug is the empty-input bypass — test the empty case for every
enumerated guard layer.** "Fail closed" is asserted per-layer, but an empty collection makes a
`for path in $paths` / `while read` loop iterate **zero times**, silently skipping that whole
layer and falling through to the allow decision. The same filter already fail-closed on empty
*labels* and empty *title* but not empty *paths* — the inconsistency is the tell. Deny-lists must
also enumerate the **full sensitive-surface union** (auth + oauth + api-keys + migrations +
secrets + money/billing/stripe/webhooks + CI + k8s/helm/compose/vercel/supabase/middleware/deploy-
scripts), not just the plan's named examples ("auth, migrations, secrets, CI/infra"). Multi-agent
review with an explicit adversarial prompt ("construct a label/path that SHOULD be excluded but
returns exit 0") reliably produces falsifying inputs that a green test suite — which only tests
the shapes the author already imagined — does not.

## Solution

- Reconciled the eligibility contract to the live signal (operator-approved via `AskUserQuestion`):
  **eligible = title `^feat(` AND label `app:web-platform`; deny = `type/security`,
  `security/leak-suspected`, `infra-drift`, `no-auto-ship` + path globs; gh-error/empty/missing-allow
  => excluded.** Reconciled every secondary citation in plan/spec/tasks (per
  `hr-when-a-plan-specifies-relative-paths` generalized to labels).
- Added an explicit `[[ -n "$paths" ]] || excluded` guard (mirroring the empty-title/empty-metadata
  guards), broadened the deny-path globs to the full sensitive union (anchored at path-segment
  boundaries so benign substrings like `pinstripe` don't trip `stripe`), and added a closing-fence
  check to the draft validator. +16 eligibility test cases, +5 validator cases, all the agents'
  falsifying inputs now excluded; benign UI + a real eligible PR still pass.

## Session Errors

- **Plan eligibility labels do not exist in the repo** (`user-facing`/`type/feature`/`infra`/
  `internal`/`dark-launch`). Recovery: `gh label list` + 25-PR sample, then `AskUserQuestion` to
  pick the live signal. **Prevention:** verify label/enum names against `gh label list` AND real
  PR labeling practice at plan-time and again at /work Phase 0 before coding a classification gate.
- **Three P1 fail-opens in a green-CI fail-closed filter** (empty-diff bypass, incomplete deny
  globs, unterminated-frontmatter bypass). Recovery: fixed inline post-review with regression
  tests. **Prevention:** for any fail-closed filter, add a RED test that feeds an EMPTY input to
  every enumerated guard layer (empty labels/paths/frontmatter), and run an adversarial review
  prompt that asks for a should-be-excluded input that returns success.
- **Vacuous RED**: `validate-tweet-draft.test.sh` reject-tests passed on script-missing (rc=127 +
  non-empty stderr satisfied "non-zero + non-empty"). Recovery: pinned each reject assertion to the
  validator's own `invalid:` reason marker. **Prevention:** negative/reject tests must assert the
  implementation's specific failure marker, never just "non-zero exit + any output" — a missing
  script otherwise passes vacuously.
- **`components.test.ts` backtick-reference regex** (`` `(references|assets|scripts)/[^`]+` ``)
  flagged repo-root `scripts/...` references in the new SKILL.md; took 3 reword cycles. Recovery:
  removed inline backticks around `scripts/...` paths. **Prevention:** in a SKILL.md, never wrap a
  repo-root `scripts/...` path in inline backticks — the convention regex is prefix-based and not
  skill-local-aware; use plain text or wrap only the basename.
- **`ZSH_VERSION: unbound variable`** when sourcing `content-publisher.sh` in an interactive-ish
  shell → spurious "no X/Twitter Thread section" (count 0). Recovery: re-ran in clean `bash -c`
  with `set -euo pipefail`. **Prevention:** source repo bash libraries inside `bash -c`, mirroring
  the test harness, not the interactive snapshot shell. (one-off)
- `mkdir` and an Edit-after-`mv`/linter touch hit the known Bash-CWD-non-persistence and
  read-before-edit harness behaviors. (one-off, already documented)
