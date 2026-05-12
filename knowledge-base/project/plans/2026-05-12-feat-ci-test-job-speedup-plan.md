---
title: "CI test-job speedup — 3-way matrix split with synthetic aggregator (replan)"
date: 2026-05-12
issue: 3680
pr: 3672
branch: feat-ci-test-job-speedup
worktree: .worktrees/feat-ci-test-job-speedup
spec: knowledge-base/project/specs/feat-ci-test-job-speedup/spec.md
brainstorm: knowledge-base/project/brainstorms/2026-05-12-ci-test-job-speedup-brainstorm.md
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
status: Draft
supersedes: knowledge-base/project/plans/2026-05-12-feat-ci-test-job-speedup-plan.md (v1, replaced in place)
---

# Plan: CI test-job speedup — 3-way matrix split with synthetic aggregator (replan)

**Issue:** #3680
**Branch:** `feat-ci-test-job-speedup`
**Draft PR:** #3672
**Brainstorm:** [`knowledge-base/project/brainstorms/2026-05-12-ci-test-job-speedup-brainstorm.md`](../brainstorms/2026-05-12-ci-test-job-speedup-brainstorm.md)
**Spec:** [`knowledge-base/project/specs/feat-ci-test-job-speedup/spec.md`](../specs/feat-ci-test-job-speedup/spec.md)

## Overview

Cut the `test` job in `.github/workflows/ci.yml` from ~199s → <130s (stretch <100s) by:

1. Refactoring `scripts/test-all.sh` to accept a `TEST_GROUP` selector (positional arg `$1` OR env-var, default `all`) with a **4-value enum** (`all` | `webplat` | `bun` | `scripts`) so the workflow can request any one group without inlining the suite list in CI.
2. Splitting the `test` CI job into **three** parallel jobs (`test-webplat`, `test-bun`, `test-scripts`) plus a synthetic aggregator job named `test` that satisfies the existing branch-protection ruleset 14145388 required-context contract.
3. Adding `actions/cache@v4.3.0` (SHA-pinned, new pattern in this repo) keyed on `bun.lock` (and `apps/web-platform/bun.lock` for the webplat shard) to skip redundant `bun install` work on shard re-runs.

The Phase 0 measurement step instruments `test-all.sh` with per-suite `EPOCHREALTIME` boundaries so the per-suite timing table appears in PR #3672's body before any workflow restructure ships, and the **3-way ↔ 2-way collapse decision** is made based on measured wall-clock — not pre-committed in the plan.

Branch-protection ruleset 14145388 is NOT edited. The synthetic-aggregator strategy makes any ruleset change unnecessary — the load-bearing reason is that ruleset edits require admin scope and out-of-band coordination, not the weaker "drift risk" framing.

**E2E sharding deferred.** The brainstorm originally bundled `e2e --shard=2`, but plan review flagged it as scope creep with an independent blast radius. It remains in Deferred Items (Item 3) — separate follow-up PR.

## Research Reconciliation — Spec vs. Codebase

This plan is a **replan** of v1 (`2026-05-12-feat-ci-test-job-speedup-plan.md` as committed in `c8d77adf`). v1 was halted at /work Phase 1 because five precondition-drift findings invalidated its Phase 0 gate, Phase 1b YAML, and TEST_GROUP split semantics. The findings, ground truth (verified against `c8d77adf` HEAD), and plan response:

| # | v1 claim / brainstorm assertion | Codebase reality (verified) | Plan response |
|---|---|---|---|
| 1 | "29 suites (7 bun + 22 bash)" | **38 suites total: 17 named + 21 `*.test.sh` glob.** Named breakdown: 11 pre-suite bash/python (lines 52-62 of `scripts/test-all.sh`), 3 bun-named (`test/content-publisher`, `test/x-community`, `test/pre-merge-rebase`), 1 vitest (`apps/web-platform` via `bash -c "cd apps/web-platform && npm run test:ci"`), 1 bun recursive (`plugins/soleur` — 25 `.test.ts` files), 1 bash (`blog-link-validation`). | Replan uses 38 throughout. 3-way grouping (webplat/bun/scripts), enumerated below. |
| 2 | "`apps/telegram-bridge` exists; `run_suite "apps/telegram-bridge" bun test apps/telegram-bridge/`; Phase 1b YAML has `Enforce telegram-bridge coverage` step" | **`apps/telegram-bridge` does NOT exist.** `ls apps/` returns only `web-platform`. `find . -maxdepth 3 -type d -name "*telegram*"` returns nothing. Neither `test-all.sh` nor any other repo file references it. | All telegram-bridge references dropped: no `run_suite` line, no coverage step in workflow YAML. Brainstorm Phase 1.1's `apps/telegram-bridge/test/health.test.ts:23` citation is fabricated. |
| 3 | "`bun test apps/web-platform/`; spawn-count probe targets web-platform's clone(2) syscalls; >130 spawns triggers pre-Phase-1b BLOCKER" | **`apps/web-platform` runs Vitest, not Bun.** `apps/web-platform/package.json` has `"test:ci": "vitest run"`, `"vitest": "^3.1.0"`, `vitest.config.ts` present. 274 `.test.ts` files under apps/web-platform/. The FPE-class spawn-count constraint (`knowledge-base/project/learnings/2026-03-20-bun-fpe-spawn-count-sensitivity.md`) is Bun-specific; Vitest uses tinypool/threads with different concurrency semantics. | Phase 0 spawn-count probe **retargeted** to `bun test plugins/soleur/` (the actual largest bun-test invocation — 25 .test.ts files in one bun process). Probe is **informational, not a BLOCKER** under matrix sharding — each shard runs in its own runner with fresh Bun GC accounting. v1's pre-Phase-1b HALT gate is dropped (Goal G5 reframed accordingly). |
| 4 | Cache key `hashFiles('bun.lockb', 'apps/web-platform/bun.lockb')` | **Lockfiles are `bun.lock` (text), not `bun.lockb` (binary).** `ls bun.lock* apps/web-platform/bun.lock*` returns only the text form (256 KB and 256 KB respectively). `hashFiles('bun.lockb')` would hash zero bytes silently — wrong cache key, no cache invalidation when deps change. | Cache key updated to `hashFiles('bun.lock')` (root) and `hashFiles('apps/web-platform/bun.lock')` (webplat shard). Per-shard cache scopes documented in Phase 1b. |
| 5 | "TEST_GROUP split: `bun` covers 7 named bun suites; `bash` covers 22 `plugins/soleur/test/*.test.sh` files. All 29 covered." | **The 11 pre-suite bash/python tests live at `tests/hooks/`, `tests/scripts/`, `tests/commands/`, `.claude/hooks/`, `scripts/lint-rule-ids-live` — NEITHER inside the bun-named block NOR matching `plugins/soleur/test/*.test.sh`.** Under v1's split, no-args invocation would silently drop those 11 suites, violating G2 (orphan-suite invariant) and AC2 (byte-identical no-args behavior). | Replan introduces a **third group** `scripts` covering all 11 pre-suite tests + the 21 `*.test.sh` glob. `TEST_GROUP=all` runs all three groups in original-order; `TEST_GROUP=webplat\|bun\|scripts` selects one group. The 4-value enum is documented in Phase 1a with explicit invalid-value rejection. |

**Other v1 claims verified intact (no change):** orphan-suite invariant (PR #3512/#3533), the `_site/` builder identity (`plugins/soleur/test/seo-aeo-drift-guard.test.ts` builds; `scripts/validate-blog-links.sh` reads/builds), ruleset 14145388 contexts (`test`, `e2e`, `dependency-review`, `CodeQL`, `skill-security-scan PR gate`), the `if: always() && needs.<job>.result == 'failure'` aggregator idiom (`.github/workflows/scheduled-compound-promote.yml:291`), Approach D rejection (FPE re-trigger), Approach B rejection (workspace.test.ts env-leak — confirmed at `apps/web-platform/test/workspace.test.ts` though specific lines not re-verified since the suite stays inside the webplat shard).

**`_site/` race reframing (correction, not drift):** v1 framed `_site/` builder co-location as a hard correctness invariant. Under **matrix sharding** (separate runners), each runner has its own `_site/` — no race exists. Co-location is a **perf optimization** (build once, reuse) only when builders run in the same shard. `plugins/soleur` builds `_site/` (via `seo-aeo-drift-guard.test.ts`) and `blog-link-validation` reads `_site/`; both stay in the `bun` shard for perf reuse. `scripts/validate-blog-links.sh` is otherwise self-sufficient (its own `npx eleventy` build at lines 25-29 if `_site/` is absent). The co-location invariant comment still ships in `validate-blog-links.sh` (AC8) as defense against any future xargs-P attempt that would re-introduce the race.

## Problem Statement

The `test` job is one of five required status checks on branch-protection ruleset 14145388. Its 199s median wall-clock directly gates merge time for every PR — including PRs touching regulated surfaces (GDPR transcript persistence #3603, payment retry, auth boundaries). `scripts/test-all.sh` runs ~38 test suites strictly sequentially, by design, to defend against a Bun SIGFPE crash whose probability scales with cumulative subprocess spawn count (`knowledge-base/project/learnings/2026-03-20-bun-fpe-spawn-count-sensitivity.md`). `.bun-version` is now 1.3.11 (six patches past the FPE-1.3.5 baseline) but the sequential runner is documented as defense-in-depth and is the project's load-bearing mitigation. Direct in-process parallelism (Approach D, `bun test --max-pool-size`) re-creates the exact spawn-pressure pattern the sequential runner exists to prevent. Per-process matrix sharding sidesteps this — each shard runs in its own GitHub-hosted runner with its own Bun GC accounting.

The 38 suites cleave naturally on three runtime axes:

1. **Vitest** in `apps/web-platform/` (274 `.test.ts` files; dominant single cost).
2. **Bun** (the 3 named `test/*.test.ts` files + `plugins/soleur/` recursive over 25 `.test.ts` files + `blog-link-validation` which co-locates with the `_site/` builder).
3. **Bash + Python** (11 named pre-suite tests + 21 `*.test.sh` glob; CPU-light, no test-runtime install).

These three runtimes have independent install requirements and independent failure surfaces, which makes a 3-way split mechanically simpler than a 2-way split that combines two of them. Phase 0 measurement validates this hypothesis before the workflow restructure ships.

The secondary `e2e` job (111s) runs in a Playwright container (`mcr.microsoft.com/playwright:v1.58.2-jammy`). Playwright supports `--shard=K/N` natively, so a 2-way split is mechanically simple — but is **deferred to Item 3** per plan review.

## Goals

- **G1:** Reduce median `test` job wall-clock to <130s on ≥6 of 10 validation runs (60% threshold). Stretch: <100s.
- **G2:** Preserve the `test-all.sh` orphan-suite invariant. Local invocation `bash scripts/test-all.sh` with no args runs all 38 suites in the same order, with identical exit semantics. (Distinct from v1's "29 suites" claim — corrected count.)
- **G3:** Keep branch-protection ruleset 14145388 untouched. The required context `test` survives via a synthetic aggregator job. `e2e` required context remains satisfied by the existing single-job `e2e` definition; e2e sharding is deferred.
- **G4:** Introduce no new flake class. 10/10 green validation runs + 11th green run post-merge on main (the bump from 5 to 10 follows architecture review P2-2 — at the brand-survival `single-user incident` threshold, 5/5 green admits ~59% false-pass probability for a 1-in-10 flake; 10/10 green tightens to ~35%).
- **G5:** Phase 0 spawn-count probe over `bun test plugins/soleur/` (the actual largest bun-test invocation — 25 `.test.ts` files in one bun process) records `clone(2)` aggregate count for the project's spawn-count tracking. **Probe is informational, NOT a BLOCKER.** Matrix sharding gives each invocation its own runner; FPE risk is bounded by cross-suite isolation regardless of probe value. The probe lands in the PR body for future planning, paired with the per-suite timing table.

## Non-Goals

- **N1:** Bun version bump. `.bun-version` stays at 1.3.11.
- **N2:** Suite-internal split of `apps/web-platform/test/` into sub-directories. Deferred (see Deferred Items Item 2). May fire as a post-merge follow-up if Phase 2 wall-clock validation shows `test-webplat` shard dominates >100s consistently.
- **N3:** In-script `xargs -P` parallelization (Approach B in brainstorm). Rejected.
- **N4:** `bun test --max-pool-size` (Approach D). Rejected.
- **N5:** Touched-file-aware test selection. Violates orphan-suite invariant.
- **N6:** `web-platform-build` job optimization (different bottleneck class — `next build` route validation).
- **N7:** Ruleset 14145388 edit.
- **N8:** New test framework dependencies.
- **N9:** **E2E `--shard=2` sharding.** Deferred to Item 3 follow-up PR per plan review (blast-radius isolation).
- **N10:** Renaming the `test:ci` script in `apps/web-platform/package.json`. The plan invokes the existing script via `bash -c "cd apps/web-platform && npm run test:ci"` (the current `test-all.sh:66` invocation form). No `package.json` churn.
- **N11:** Migrating `apps/web-platform` from Vitest to Bun. Different test runtime, different parallelism model; out of scope.

## User-Brand Impact

(Carried forward verbatim from `knowledge-base/project/specs/feat-ci-test-job-speedup/spec.md` and brainstorm Phase 0.1. Per `requires_cpo_signoff: true` frontmatter, CPO sign-off on the chosen approach is satisfied by the Phase 0.5 brainstorm domain assessment — re-spawning is not required since the replan's scope correction does not change the approach class (synthetic aggregator + matrix split).)

**If this lands broken, the user experiences:**

- Engineers/agents see intermittent red `test` runs caused by a new flake class (shard-bundling exposes a previously isolated `process.env` leak, a `_site/` race, or a port collision). Trust in the red signal erodes; a real regression eventually merges.
- If the merged regression lands in production agent surfaces (`apps/web-platform`, `apps/cc-soleur-go`) during a compliance-sensitive window — GDPR transcript persistence #3603, payment retry, auth boundary — the failure crosses from dev-velocity into brand-survival.
- Team-wide unmergeable state if the synthetic aggregator's job name drifts from ruleset 14145388's required context `test`.

**If this leaks, the user's [data / workflow / money] is exposed via:**

- The merge gate itself is the exposure vector. A flaky-but-not-failing `test` check lets a regression in transcript persistence, payment retry, or auth-boundary handling reach production users undetected. Transcript regression → potential GDPR Art. 32 incident. Payment regression → user-facing money-flow error. Auth regression → cross-tenant read.

**Brand-survival threshold:** `single-user incident`.

**Mitigations specific to this PR:**

- Synthetic aggregator preserves the required-check contract without ruleset edit (TR1) — orphan-check failure mode bounded.
- `_site/` builders co-located in the same shard (`bun`) — perf-optimal AND race-free even if a future change moves them under shared-process parallelism.
- Aggregator MUST fail-closed (FR3, no `||` fallback per `knowledge-base/project/learnings/2026-03-19-ci-squash-fallback-bypasses-merge-gates.md`) — silent partial-success blocked.
- 10-run validation + 11th post-merge run (SC3, SC6) — flake class would surface before merge or in the first post-merge sanity check.
- `user-impact-reviewer` agent runs at PR-review time (handled by `plugins/soleur/skills/review/SKILL.md` conditional-agent block).

## Domain Review

**Domains relevant:** Engineering, Product, Legal (carried forward from brainstorm Phase 0.5).

### Engineering (CTO)

**Status:** reviewed (brainstorm carry-forward; replan does not change approach class)
**Assessment:** Recommended Approach A with synthetic aggregator. Confirmed Bun 1.3.11 still treats sequential isolation as defense-in-depth. Ruled out Approach D (FPE re-trigger) and Approach B (three confirmed sharp edges). Flagged that stretch <100s requires suite-internal split of `apps/web-platform/test/`. The replan **adds** a finer-grained 3-way split (webplat/bun/scripts) that the original brainstorm's 2-way framing missed; this is a sharpening of the same approach class, not a different approach.

### Product (CPO)

**Status:** reviewed (brainstorm carry-forward)
**Assessment:** No direct product angle; defers to CTO. Treats the single-user incident threshold as a hard non-regression constraint, not a product gate. CPO sign-off on the brainstorm approach satisfies plan-time `requires_cpo_signoff: true`. The replan does not change the approach class or the threshold — re-spawning CPO is not required.

### Legal (CLO)

**Status:** reviewed (brainstorm carry-forward)
**Assessment:** No legal hooks fire. Test execution touches synthesized fixtures only (`cq-test-fixtures-synthesized-only`); no DPA / Privacy Policy / SOC 2 control names a specific CI job; ruleset 14145388 is an internal engineering guardrail, not a binding compliance control. Aggregator-rename strategy is legally invisible.

### Product/UX Gate

**Tier:** none — internal CI infrastructure change. No new user-facing pages, no UI components, no flow changes. Mechanical escalation check: zero `components/**/*.tsx`, `app/**/page.tsx`, or `app/**/layout.tsx` files in `Files to Edit` or `Files to Create`. Gate does not fire.

**Brainstorm-recommended specialists:** none.

## GDPR / Compliance Gate

The plan does not touch regulated-data surfaces (no schemas, migrations, auth flows, API routes, or `.sql` files). However, expansion trigger (b) fires — the plan's `brand_survival_threshold: single-user incident` declaration. Per `plugins/soleur/skills/plan/SKILL.md` Phase 2.7, the gate is invoked.

**Inline assessment (CLO carry-forward sufficient):**

- The change scope is GitHub Actions workflow YAML + a bash test runner. Neither surface processes operator-session data, persistent user data, or external API calls touching PII.
- No new processing activity (a). No new cron/workflow reading `learnings/` or `specs/` (c). No new artifact distribution surface (d).
- The trigger fires solely on threshold, not on actual regulated-data movement. CLO already reviewed and cleared.

**No Critical findings.** No `compliance-posture.md` Active Items update needed. No `compliance/critical`-labeled issue filed.

## Open Code-Review Overlap

**None.** Queried `gh issue list --label code-review --state open --json number,title,body --limit 200` and filtered for `scripts/test-all.sh` or `.github/workflows/ci.yml` substrings — zero matches. Replan can proceed without folding in or acknowledging existing scope-outs on the planned files. (v1 ran this check; replan inherits the result since the same files are touched and no new code-review issues have been filed against them in the intervening hours.)

## Implementation Phases

### Phase 0 — Measurement (commit 1, BEFORE workflow restructure)

Instrument `scripts/test-all.sh` with per-suite **`EPOCHREALTIME`** boundaries (bash 5.0+ builtin, microsecond precision, portable across Linux and macOS bash 5 — no `coreutils` dependency, no `date +%N` macOS gap), AND probe the subprocess spawn count for `bun test plugins/soleur/` so the FPE-class baseline number lands in the PR body before any workflow restructure.

**Edits to `scripts/test-all.sh`:**

```bash
# Inside run_suite() — wrap the invocation with monotonic timing.
# EPOCHREALTIME is "seconds.microseconds" since epoch (bash 5.0+).
run_suite() {
  local label="$1"; shift
  suites=$((suites + 1))
  local start="$EPOCHREALTIME"
  echo "--- $label ---"
  local status="ok"
  if ! "$@"; then
    status="FAIL"
    failed=$((failed + 1))
  fi
  # Compute elapsed ms via integer math on the dot-separated EPOCHREALTIME.
  # "1700000000.123456" → start_us=1700000000123456; end_us similar; diff/1000 = ms.
  local end="$EPOCHREALTIME"
  local start_us=$(( ${start%.*} * 1000000 + 10#${start#*.} ))
  local end_us=$(( ${end%.*} * 1000000 + 10#${end#*.} ))
  local elapsed_ms=$(( (end_us - start_us) / 1000 ))
  if [[ "$status" == "ok" ]]; then
    echo "[ok] $label (${elapsed_ms}ms)"
    printf '%s\t%d\n' "$label" "$elapsed_ms" >> "${TEST_TIMING_LOG:-/dev/null}"
  else
    echo "[FAIL] $label (${elapsed_ms}ms)" >&2
    printf '%s\t%d\tFAIL\n' "$label" "$elapsed_ms" >> "${TEST_TIMING_LOG:-/dev/null}"
  fi
}
```

**Spawn-count probe (one-shot, not committed to test-all.sh):**

```bash
# Probe the LARGEST bun-test invocation in this codebase.
# bun test plugins/soleur/ recurses over 25 .test.ts files in one bun process.
# (Note: apps/web-platform is Vitest, NOT Bun — FPE constraint does not apply.)
# Informational only — under matrix sharding each invocation gets its own runner.
strace -fe trace=clone -c bun test plugins/soleur/ 2>/tmp/strace-summary.txt 1>/dev/null || true
grep "clone" /tmp/strace-summary.txt || echo "no clone syscalls captured"
```

Run locally on Linux (CI is ubuntu-latest so `strace` is available there too):

```bash
TEST_TIMING_LOG=/tmp/test-timing.tsv bash scripts/test-all.sh
sort -t$'\t' -k2 -n -r /tmp/test-timing.tsv | head -10
```

**Acceptance:** PR #3672 body MUST contain:

1. A markdown table of all 38 suite wall-clock timings, with top 5 highlighted in bold and three per-group aggregates computed (`webplat`, `bun`, `scripts`).
2. A single-line **grouping decision**: report `max/min` ratio across the three group totals. If `max/min < 2.0`, commit to 3-way matrix. If `max/min ≥ 2.0` AND one of `{bun, scripts}` is the small side, collapse that small side INTO the next-smallest group (likely produces a 2-way `webplat` + `bun+scripts` split). Decision rule is mechanical, not subjective.
3. The `bun test plugins/soleur/` `clone(2)` spawn count from the strace probe. Informational only — recorded for the project's spawn-count tracking. No HALT gate based on this number.

**Commit message:** `feat(ci): instrument test-all.sh with per-suite timing — #3680`

### Phase 1 — Test job split + cache (commits 2 and 3)

#### Phase 1a — TEST_GROUP selector in test-all.sh (commit 2)

Refactor `scripts/test-all.sh` so the suite invocations are gated by `TEST_GROUP`. Per pattern review MEDIUM-2, support BOTH a positional argument (idiomatic for `scripts/*.sh` per `scripts/validate-blog-links.sh:10` and `scripts/provision-plausible-goals.sh:59`) AND an env-var (composes with GitHub Actions `env:` blocks and `gh workflow run`):

```bash
# Selector: positional $1 OR TEST_GROUP env (env wins for explicit CI use).
TEST_GROUP="${TEST_GROUP:-${1:-all}}"

case "$TEST_GROUP" in
  all|webplat|bun|scripts) ;;
  *)
    echo "ERROR: TEST_GROUP must be one of: all, webplat, bun, scripts (got: $TEST_GROUP)" >&2
    echo "Usage: bash scripts/test-all.sh [all|webplat|bun|scripts]" >&2
    echo "   or: TEST_GROUP=<value> bash scripts/test-all.sh" >&2
    exit 2
    ;;
esac

want_scripts() { [[ "$TEST_GROUP" == "all" || "$TEST_GROUP" == "scripts" ]]; }
want_bun()     { [[ "$TEST_GROUP" == "all" || "$TEST_GROUP" == "bun"     ]]; }
want_webplat() { [[ "$TEST_GROUP" == "all" || "$TEST_GROUP" == "webplat" ]]; }

# Order matches the original test-all.sh sequence for byte-identical no-args behavior.

# Pre-suite scripts (original lines 52-62) — scripts shard
if want_scripts; then
  run_suite "tests/hooks/incidents" bash tests/hooks/test_incidents.sh
  run_suite "tests/hooks/emissions" bash tests/hooks/test_hook_emissions.sh
  run_suite "tests/scripts/lint-rule-ids" python3 -m unittest tests.scripts.test_lint_rule_ids
  run_suite "scripts/lint-rule-ids-live" python3 scripts/lint-rule-ids.py --retired-file scripts/retired-rule-ids.txt --index-file AGENTS.md AGENTS.md AGENTS.core.md AGENTS.docs.md AGENTS.rest.md
  run_suite ".claude/hooks/session-rules-loader" bash .claude/hooks/session-rules-loader.test.sh
  run_suite "tests/scripts/classifier-regex-parity" bash tests/scripts/test_classifier_regex_parity.sh
  run_suite "tests/scripts/rule-id-regex-parity" python3 -m unittest tests.scripts.test_rule_id_regex_parity
  run_suite "tests/scripts/rule-metrics-aggregate" bash tests/scripts/test-rule-metrics-aggregate.sh
  run_suite "tests/scripts/audit-ruleset-bypass" bash tests/scripts/test-audit-ruleset-bypass.sh
  run_suite "tests/scripts/audit-bot-codeql-coverage" bash tests/scripts/test-audit-bot-codeql-coverage.sh
  run_suite "tests/commands/sync-rule-prune" bash tests/commands/test-sync-rule-prune.sh
fi

# Bun named tests (original lines 63-65) — bun shard
if want_bun; then
  run_suite "test/content-publisher" bun test test/content-publisher.test.ts
  run_suite "test/x-community" bun test test/x-community.test.ts
  run_suite "test/pre-merge-rebase" bun test test/pre-merge-rebase.test.ts
fi

# Vitest in apps/web-platform (original line 66) — webplat shard
if want_webplat; then
  run_suite "apps/web-platform" bash -c "cd apps/web-platform && npm run test:ci 2>&1"
fi

# Bun plugins/soleur (original line 67) + blog-link-validation (original line 68) — bun shard
# blog-link-validation is co-located with seo-aeo-drift-guard.test.ts (inside plugins/soleur)
# because both interact with _site/. Co-location is a perf optimization under matrix sharding
# (separate runners can't race), but stays load-bearing as defense against any future xargs-P attempt.
if want_bun; then
  run_suite "plugins/soleur" bun test plugins/soleur/
  run_suite "blog-link-validation" bash scripts/validate-blog-links.sh
fi

# Bash *.test.sh glob (original lines 71-74) — scripts shard
if want_scripts; then
  for f in plugins/soleur/test/*.test.sh; do
    [[ -f "$f" ]] || continue
    run_suite "$f" bash "$f"
  done
fi
```

**Also add a header comment to `scripts/validate-blog-links.sh`** (architecture P2-3 — invariant must live in the consumed file, not only in the workflow):

```bash
# CO-LOCATION INVARIANT: this script reads _site/ which is built by
# plugins/soleur/test/seo-aeo-drift-guard.test.ts (running inside `bun test
# plugins/soleur/`). Both run in the "bun" TEST_GROUP in scripts/test-all.sh
# and in the test-bun job in .github/workflows/ci.yml. Under matrix sharding
# (separate runners), there is no _site/ race because each runner builds its
# own _site/; co-location is a perf optimization (build once, reuse).
# However, moving validate-blog-links.sh to a different TEST_GROUP than the
# bun-side builders would re-introduce the race if any future plan adopts
# in-runner parallelism (xargs -P, --max-pool-size). DO NOT move groups.
```

**Backward compatibility:** With `TEST_GROUP` unset and no positional arg, behavior is byte-identical to today's `scripts/test-all.sh` — same 38 suites, same order. Local invocations and the existing one-job CI path don't change.

**Acceptance:** `bash scripts/test-all.sh webplat` runs only the `apps/web-platform` vitest suite. `bash scripts/test-all.sh bun` runs the 5 bun-side entries (3 named + plugins/soleur + blog-link-validation). `bash scripts/test-all.sh scripts` runs the 11 pre-suite + 21 `*.test.sh` glob entries (32 suites). All three groups exist disjoint under `all` and reunite in original order. `bash scripts/test-all.sh invalid` exits 2 with stderr usage. `TEST_GROUP` env wins over positional if both are set (`${TEST_GROUP:-${1:-all}}` evaluates positional only when env unset).

**Commit message:** `feat(ci): add TEST_GROUP selector to test-all.sh — #3680`

#### Phase 1b — CI workflow refactor (commit 3)

Replace the single `test` job in `.github/workflows/ci.yml` with four jobs (three shards + one synthetic aggregator named `test`):

```yaml
test-webplat:
  runs-on: ubuntu-latest
  steps:
    - uses: actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5 # v4.3.1
    - uses: oven-sh/setup-bun@3d267786b128fe76c2f16a390aa2448b815359f3 # v2.1.2
      with:
        bun-version-file: ".bun-version"
    - uses: actions/setup-node@49933ea5288caeca8642d1e84afbd3f7d6820020 # v4.4.0
      with:
        node-version: 22
    - name: Cache bun install (apps/web-platform)
      uses: actions/cache@0057852bfaa89a56745cba8c7296529d2fc39830 # v4.3.0
      with:
        path: |
          ~/.bun/install/cache
          apps/web-platform/node_modules
        key: bun-webplat-${{ runner.os }}-${{ hashFiles('apps/web-platform/bun.lock') }}
        restore-keys: |
          bun-webplat-${{ runner.os }}-
    - name: Install web-platform dependencies
      run: bun install --frozen-lockfile
      working-directory: apps/web-platform
    - name: Type-check web-platform
      run: npx tsc --noEmit
      working-directory: apps/web-platform
    - name: Run webplat tests (vitest)
      run: bash scripts/test-all.sh webplat
      env:
        GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}

test-bun:
  runs-on: ubuntu-latest
  steps:
    - uses: actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5 # v4.3.1
    - uses: oven-sh/setup-bun@3d267786b128fe76c2f16a390aa2448b815359f3 # v2.1.2
      with:
        bun-version-file: ".bun-version"
    - uses: actions/setup-node@49933ea5288caeca8642d1e84afbd3f7d6820020 # v4.4.0
      with:
        node-version: 22
    - name: Cache bun install (root)
      uses: actions/cache@0057852bfaa89a56745cba8c7296529d2fc39830 # v4.3.0
      with:
        path: |
          ~/.bun/install/cache
          node_modules
        key: bun-root-${{ runner.os }}-${{ hashFiles('bun.lock') }}
        restore-keys: |
          bun-root-${{ runner.os }}-
    - name: Install root dependencies
      run: bun install --frozen-lockfile
    - name: Run bun-side tests
      run: bash scripts/test-all.sh bun
      env:
        GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}

test-scripts:
  runs-on: ubuntu-latest
  # No bun, no node, no install — bash + python3 ship on ubuntu-latest by default.
  # Verified: no .test.sh file invokes `bun ` (grep returned 0 matches at plan time).
  # If a future .test.sh needs bun, add setup-bun here without install.
  steps:
    - uses: actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5 # v4.3.1
    - name: Run scripts-side tests (bash + python3)
      run: bash scripts/test-all.sh scripts
      env:
        GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}

test:
  # Synthetic aggregator.
  #
  # LOAD-BEARING SUB-VALUE (per 2026-05-06-defense-in-depth-recovery-mirroring-
  # sql-predicate-document-load-bearing-value.md): the aggregator is NOT
  # redundant with branch-protection ruleset 14145388's `test` required check.
  # It carries three distinct values: (a) cross-layer truing — converts three
  # shard `conclusion`s into one required-context conclusion the ruleset
  # already expects by name; (b) drift-resilience — survives a future
  # ruleset edit that changes the required-context list, as long as the
  # `test` name still gates merge; (c) observability — single PR-status row
  # to inspect, not three. Removing this job orphans ruleset 14145388's
  # `test` required check and breaks every PR merge.
  #
  # The name `test` MUST match the required-context name on ruleset 14145388
  # exactly. Drift = merge gate orphaned for the whole team.
  #
  # `if: always()` + per-shard result inspection is the documented fail-closed
  # pattern. Precedent: scheduled-compound-promote.yml:291 uses
  # `if: always() && (needs.preflight.result == 'failure' || ...)`. Without
  # `if: always()`, default semantics produce a `skipped` aggregator when any
  # shard fails — and some branch-protection configs treat `skipped` as
  # success (fail-open).
  needs: [test-webplat, test-bun, test-scripts]
  if: always()
  runs-on: ubuntu-latest
  steps:
    - name: Aggregate shard results
      run: |
        fail=0
        for shard in test-webplat test-bun test-scripts; do
          case "$shard" in
            test-webplat) result="${{ needs.test-webplat.result }}" ;;
            test-bun)     result="${{ needs.test-bun.result }}" ;;
            test-scripts) result="${{ needs.test-scripts.result }}" ;;
          esac
          if [[ "$result" != "success" ]]; then
            echo "$shard: $result" >&2
            fail=1
          fi
        done
        if [[ $fail -ne 0 ]]; then
          exit 1
        fi
        echo "All three shards green."
```

**Critical design notes:**

- **`if: always()` + per-shard explicit checks** is the canonical GitHub Actions fail-closed aggregator pattern. Precedent: `.github/workflows/scheduled-compound-promote.yml:291`. Without `if: always()`, the default `needs:` semantics produce a `skipped` aggregator if a shard fails (or is itself skipped via `paths-ignore` / conditional `if:`) — and `skipped` is treated as success by some branch-protection configs. The `if: always()` + manual result inspection forces explicit pass/fail.
- **No `|| true`, no `continue-on-error: true`** anywhere in the aggregator. Per `knowledge-base/project/learnings/2026-03-19-ci-squash-fallback-bypasses-merge-gates.md`.
- **`actions/cache@v4.3.0` SHA-pinned inline.** SHA `0057852bfaa89a56745cba8c7296529d2fc39830` resolved at plan time per pattern review HIGH-1 and re-verified on 2026-05-12 (`gh api repos/actions/cache/git/refs/tags/v4 --jq .object.sha` returned the same SHA, type `commit`). Matches the SHA-pin discipline every other action in this workflow follows. If the v4 tag is moved before implementation, re-resolve and update.
- **Per-shard cache scope.** `test-webplat` caches `~/.bun/install/cache` + `apps/web-platform/node_modules`, keyed on `apps/web-platform/bun.lock`. `test-bun` caches `~/.bun/install/cache` + root `node_modules`, keyed on root `bun.lock`. `test-scripts` has no cache step — no test-runtime install. Cache keys are **`bun.lock` (text)**, NOT `bun.lockb` (binary, doesn't exist in this repo) — fixing v1 drift finding #4.
- **Type-check step lives in `test-webplat`.** The 18s `npx tsc --noEmit` depends on `apps/web-platform/node_modules` which only the webplat shard installs. Moving it would force webplat-deps install into another shard.
- **`test-scripts` has no setup-bun.** Verified at plan time: `grep -l "^bun " plugins/soleur/test/*.test.sh` returns zero — no `.test.sh` file invokes bun. Pre-suite python scripts use the ubuntu-latest default `python3`. If a future `.test.sh` adds a bun invocation, the work-skill task should re-grep and add `setup-bun` (no install needed) to `test-scripts`. This is documented in the YAML comment so the constraint travels with the job definition.
- **Plain positional-arg invocation** — `bash scripts/test-all.sh webplat`, `bash scripts/test-all.sh bun`, `bash scripts/test-all.sh scripts` — more grep-able than the env-var form. Per pattern review MEDIUM-2 the script supports both; workflow uses positional for greppability.
- **2-way collapse path (Phase 0 contingency).** If Phase 0 measurement triggers a collapse decision (`max/min ≥ 2.0`), the most likely collapse is `bun+scripts` → one combined `test-rest` job alongside `test-webplat`. The TEST_GROUP enum still supports all 4 values; the collapse is a workflow-only change (one job replaces two; aggregator `needs:` updated accordingly). Plan documents the option but commits to 3-way unless measurement forces it.

**Acceptance:** The aggregator job named exactly `test` appears in `gh run view <run-id> --json jobs` with `status: completed, conclusion: success` when all three shards pass; `conclusion: failure` when any fails. Ruleset 14145388 unchanged.

**Commit message:** `feat(ci): split test job into webplat + bun + scripts shards with synthetic aggregator — #3680`

### Phase 2 — Validation (no commit beyond mutation test; PR-level — 10 runs + T14)

Per architecture review P2-2, the `single-user incident` brand-survival threshold makes a 5-run validation statistically thin (a 1-in-10 flake passes 5/5 ~59% of the time). 10 runs:

```bash
for i in 1 2 3 4 5 6 7 8 9 10; do
  git commit --allow-empty -m "ci: validation run $i — #3680"
  git push
done
```

`gh workflow run` is not available (the `ci.yml` triggers are `push` + `pull_request` + `workflow_dispatch`; `workflow_dispatch` would dispatch off the default-branch copy of the workflow per the GitHub constraint documented in `knowledge-base/project/learnings/integration-issues/2026-04-21-workflow-dispatch-requires-default-branch.md` — Empty-commit-push cycles are the path for new workflow-job-shape validation).

Collect timings:

```bash
gh run list --branch feat-ci-test-job-speedup --workflow ci.yml --limit 15 --json databaseId,status,conclusion,createdAt,jobs > /tmp/runs.json
jq -r '.[] | select(.status=="completed") | "\(.createdAt)\t\(.conclusion)\t\(.databaseId)"' /tmp/runs.json
```

For each run, extract the `test` aggregator duration:

```bash
gh run view <run-id> --json jobs | jq -r '.jobs[] | select(.name == "test") | "\(.startedAt)\t\(.completedAt)\t\(.conclusion)"'
```

**SKIPPED-shard mutation test (T14, per architecture review P1-1).** Before the 10 regular runs, push a single mutation: edit `.github/workflows/ci.yml` to add `if: false` to **each** of the three shards in turn (three separate mutation commits, reverted between). Confirm for each:

1. The mutated shard reaches `conclusion: skipped`.
2. The synthetic `test` aggregator reaches `conclusion: failure` (NOT `skipped`).
3. Attempting `gh pr merge` reports the `test` required check failing — branch protection blocks the merge.

Revert each mutation before testing the next. This proves the aggregator does not silently fail open on a future `paths-ignore` or conditional-`if:` edit on ANY shard. (Three sub-mutations replace v1's single `test-bun` mutation since this plan has three shards.)

**Acceptance:** `test` aggregator wall-clock <130s on ≥6 of 10 runs; 10/10 green. T14 SKIPPED-shard test confirmed branch-protection blocks merge for each shard. If <6/10 within target, pivot to Deferred-Items Item 2 (`apps/web-platform/` internal split) in a follow-up commit on this same PR.

### Phase 3 — Post-merge sanity (no commit; gh-only)

After merge to main, verify:

1. `gh api repos/jikig-ai/soleur/rulesets/14145388 --jq '.rules[] | select(.type=="required_status_checks") | .parameters.required_status_checks[].context'` returns the identical 5-context list as pre-merge (`test`, `e2e`, `dependency-review`, `CodeQL`, `skill-security-scan PR gate`).
2. The next PR opened against main shows the `test` check running as expected, and merge is gated by it.
3. The main-branch CI run on the merge commit shows the `test` aggregator green with wall-clock within Phase 2 target (post-merge sanity = 11th green run).

If any check fails, revert PR via `git revert <merge-sha>` and re-open. The aggregator-rename failure mode is bounded: revert restores the single-job `test` definition immediately.

## Files to Edit

- `scripts/test-all.sh` — Phase 0 timing instrumentation (commit 1) + Phase 1a `TEST_GROUP` selector with 4-value enum (commit 2).
- `scripts/validate-blog-links.sh` — header co-location invariant comment (commit 2, alongside test-all.sh selector — co-located change because the invariant binds the two scripts).
- `.github/workflows/ci.yml` — Phase 1b 3-shard matrix + synthetic aggregator (commit 3).

## Files to Create

- *(none)* — all changes land in three existing files. The `actions/cache@v4.3.0` reference is a new step inside an existing workflow file, not a new file.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1:** PR #3672 body contains (a) a markdown table of all 38 suite wall-clock timings from Phase 0 measurement with top-5 highlighted and per-group aggregates (`webplat`, `bun`, `scripts`), (b) the `bun test plugins/soleur/` strace clone-syscall count (informational only — NO HALT verdict, replacing v1's deprecated BLOCKER gate), (c) the Phase 1b grouping decision (3-way vs collapsed 2-way) with the `max/min` ratio that drove it.
- [ ] **AC2:** `bash scripts/test-all.sh` (no args, no env) runs all 38 suites in the original order and exits 0 on success, 1 on any failure — byte-identical exit semantics to today.
- [ ] **AC3:** `bash scripts/test-all.sh webplat` and `TEST_GROUP=webplat bash scripts/test-all.sh` both run only the `apps/web-platform` vitest suite.
- [ ] **AC4:** `bash scripts/test-all.sh bun` and `TEST_GROUP=bun bash scripts/test-all.sh` both run only the 5 bun-side entries (3 named bun tests + `plugins/soleur` + `blog-link-validation`).
- [ ] **AC5:** `bash scripts/test-all.sh scripts` and `TEST_GROUP=scripts bash scripts/test-all.sh` both run only the 32 scripts-side entries (11 pre-suite named + 21 `plugins/soleur/test/*.test.sh` glob).
- [ ] **AC6:** `bash scripts/test-all.sh invalid` exits with code 2 and prints both error and usage lines to stderr.
- [ ] **AC7:** `.github/workflows/ci.yml` contains four jobs: `test-webplat`, `test-bun`, `test-scripts`, and `test` (the synthetic aggregator). The aggregator's `needs:` lists all three shards and uses `if: always()` + per-shard `result` checks to fail closed. The aggregator job body contains a comment naming the load-bearing sub-value (per architecture P2-1).
- [ ] **AC8:** `actions/cache@v4.3.0` is added to `test-webplat` (keyed on `apps/web-platform/bun.lock`) and `test-bun` (keyed on root `bun.lock`) with the literal SHA `0057852bfaa89a56745cba8c7296529d2fc39830` pinned (no `@v4` floating tag, no `@<SHA>` placeholder). `test-scripts` has NO cache step.
- [ ] **AC9:** `scripts/validate-blog-links.sh` header contains a comment naming the `_site/` co-location invariant with `seo-aeo-drift-guard.test.ts` and pointing to `test-all.sh` (`bun` TEST_GROUP) + `ci.yml` `test-bun` job. The comment also notes the perf-vs-correctness framing (race-free under matrix sharding; co-location is a perf optimization + defense against future in-runner parallelism).
- [ ] **AC10:** `git grep -nE "(\|\| true|continue-on-error: true)" .github/workflows/ci.yml` returns ZERO matches inside the `test`, `test-webplat`, `test-bun`, or `test-scripts` job bodies. Fail-closed invariant.
- [ ] **AC11:** SKIPPED-shard mutation test (T14, architecture P1-1): a temporary `if: false` on EACH of `test-webplat`, `test-bun`, `test-scripts` (three sub-mutations, reverted between) produces aggregator `conclusion: failure` AND `gh pr merge` reports the `test` required check failing. All mutations reverted before AC12.
- [ ] **AC12:** Phase 2 validation: 10 independent runs of the workflow on this PR branch; ≥6 show `test` aggregator wall-clock <130s; 10/10 green (all 38 suites pass on every run).
- [ ] **AC13:** `gh api repos/jikig-ai/soleur/rulesets/14145388` returns the same `required_status_checks` context list pre- and post-merge.
- [ ] **AC14:** PR body uses `Closes #3680` (in body, not in title; per `wg-use-closes-n-in-pr-body-not-title-to`).
- [ ] **AC15:** Three GitHub follow-up issues created and linked from the PR body (see Deferred Items: Bun version probe, `apps/web-platform/` internal split, e2e --shard=2).
- [ ] **AC16:** `apps/telegram-bridge` appears ZERO times in the merged diff (`git diff main...HEAD | grep -c telegram-bridge` returns 0). Drift safeguard against v1's fabricated reference re-emerging.
- [ ] **AC17:** `bun.lockb` appears ZERO times in the merged diff (`git diff main...HEAD | grep -c bun.lockb` returns 0). Drift safeguard against v1's wrong cache-key shape re-emerging.

### Post-merge (operator)

- [ ] **AC18:** Within 24h of merge, the main-branch CI run on the merge commit shows `test` aggregator <130s — 11th green run confirms no flake class introduced.
- [ ] **AC19:** Within 24h, the first new PR opened against main shows the `test` required check present, running, and merge-gating. If the check is missing from the merge-gate view, immediately revert the merge commit.

## Test Scenarios

### Local

- **T1:** Run `bash scripts/test-all.sh` in the worktree → all 38 suites run sequentially in the order documented in the script. Compare timing log against Phase 0 baseline ± 5%.
- **T2:** Run `TEST_GROUP=webplat bash scripts/test-all.sh` → 1 suite (`apps/web-platform`, vitest).
- **T3:** Run `TEST_GROUP=bun bash scripts/test-all.sh` → 5 suites. Confirm `validate-blog-links.sh` runs after `plugins/soleur` (so the latter's `_site/` build is reusable).
- **T4:** Run `TEST_GROUP=scripts bash scripts/test-all.sh` → 32 suites (11 named pre-suite + 21 `*.test.sh` glob). Confirm none of the bun-side or vitest suites run.
- **T5:** Run `TEST_GROUP=invalid bash scripts/test-all.sh` → exits 2 with stderr message naming all four valid values.
- **T6:** With `_site/` deleted, run `TEST_GROUP=bun bash scripts/test-all.sh` → `seo-aeo-drift-guard.test.ts` (inside `plugins/soleur`) rebuilds `_site/`, then `validate-blog-links.sh` reads from it successfully. Same shard, no race.
- **T7:** Backward-compat regression — invoke `bash scripts/test-all.sh` with no args from the repo root and from any subdirectory; confirm identical 38-suite execution.

### CI (PR #3672)

- **T8:** Push the Phase 0 instrumentation commit alone; verify CI passes (instrumentation must be backward-compatible — existing single `test` job still runs and times out cleanly on `failed=0`).
- **T9:** Push the Phase 1a `TEST_GROUP` selector commit; verify the existing single `test` job still passes (script invoked with no args defaults to `all`).
- **T10:** Push the Phase 1b workflow restructure commit; verify the new `test-webplat`, `test-bun`, `test-scripts`, and synthetic `test` jobs all appear and run; verify the existing `e2e` job is unchanged.
- **T11:** Phase 2 — 10 empty-commit-push cycles; collect timings via `gh run view`; record into PR body table.

### Negative

- **T12:** Mutation test — temporarily fail one bun suite locally; confirm `bash scripts/test-all.sh bun` exits 1. In CI, confirm `test-bun` reaches `conclusion: failure` and the synthetic `test` aggregator also fails.
- **T13:** Mutation test — temporarily fail one bash suite; confirm `test-scripts` fails and aggregator fails.
- **T14:** SKIPPED-shard mutation (architecture P1-1) — for each of `test-webplat`, `test-bun`, `test-scripts`, push a separate mutation commit adding `if: false` to that shard; confirm aggregator `conclusion: failure` (NOT `skipped`) and merge gate red for each. Revert between mutations.
- **T15:** Mutation test — temporarily fail the vitest suite (e.g., `expect(true).toBe(false)` in one of the 274 webplat test files); confirm `test-webplat` fails and aggregator fails. Confirms vitest-side failure surface propagates correctly.

## Sharp Edges

(Carried forward from brainstorm + plan v1 + supplemented by replan-time verification findings.)

- **Bun 1.3.11 FPE constraint is defense-in-depth, not eliminated.** Sequential per-suite process isolation still applies. Approaches D (`--max-pool-size`) and B (`xargs -P` within one runner) are rejected outright. Matrix sharding is safe at the **cross-suite** level because separate runners = separate Bun process accounting. **Intra-suite spawn pressure** inside a single bun-test invocation (notably `bun test plugins/soleur/` running 25 `.test.ts` files in one bun process) is bounded by Phase 0 informational probe; under the 1.3.11 patches the FPE has not re-fired in CI but the sequential runner remains load-bearing.
- **Vitest runtime in `apps/web-platform` is separate from Bun's FPE class.** Vitest uses tinypool (threads by default, optionally forks) — its parallelism semantics are independent of Bun's spawn-count-sensitive FPE. The webplat shard does NOT need spawn-count gating. Documented here so future planners do not re-derive the wrong gate. *(Replan finding.)*
- **`apps/telegram-bridge` does not exist.** v1 plan and brainstorm Phase 1.1 referenced `apps/telegram-bridge/test/health.test.ts:23` as a port-binding sharp edge for Approach B. That file is fabricated; the brainstorm's `find` walk missed that `ls apps/` returns only `web-platform`. Approach B's rejection still holds on the other two sharp edges (env-leak, `_site/` race). Documented here so future planners do not re-derive the wrong file list. *(Replan finding.)*
- **Repo lockfiles are `bun.lock` (text), not `bun.lockb` (binary).** Bun supports both formats; this repo uses the text form. `hashFiles('bun.lockb')` would hash zero bytes silently (no cache invalidation), producing a stale-cache class. Cache keys MUST use `bun.lock`. *(Replan finding.)*
- **`_site/` race vector is real ONLY under in-runner parallelism.** Under matrix sharding (this plan), each runner has its own filesystem; no race exists across shards. Co-location of `seo-aeo-drift-guard.test.ts` (builder) and `validate-blog-links.sh` (consumer) inside the same `bun` shard is a perf optimization (build once, reuse). FR4-style invariant comment ships in `validate-blog-links.sh` (AC9) as defense against any future xargs-P attempt that would re-introduce the race. *(Reframed from v1's stronger correctness framing.)*
- **Aggregator `if: always()` is load-bearing.** Without it, the default `needs:` semantics produce a `skipped` aggregator when a shard fails OR is itself skipped (e.g., via `paths-ignore` or conditional `if:` clause added later). Some branch-protection configurations treat `skipped` as success — fail-open. Precedent: `.github/workflows/scheduled-compound-promote.yml:291`. T14 (SKIPPED-shard mutation test, three sub-runs) proves the design fails closed on each shard before the 10-run validation.
- **`actions/cache@v4.3.0` is a NEW PATTERN in this repo.** `grep -rn 'actions/cache@' .github/workflows/` returns zero matches. SHA resolved at plan time and re-verified on 2026-05-12: `0057852bfaa89a56745cba8c7296529d2fc39830`. If the v4 tag is moved before implementation, re-resolve.
- **Branch-protection rename trap.** The synthetic aggregator job MUST be named exactly `test`. Any drift orphans the required check on ruleset 14145388. CI lint check (`lint-bot-statuses` job) does NOT catch this; the only mechanical check is `gh api repos/.../rulesets/14145388` post-merge (AC13).
- **`apps/web-platform` is currently a single `run_suite` invocation that runs 274 `.test.ts` files in one vitest process.** This plan does NOT split it. If Phase 0 wall-clock reveals `apps/web-platform` alone >100s consistently, the stretch <100s target requires the Deferred-Items Item 2 pivot (suite-internal directory split). If Phase 2 validation shows the webplat shard dominating wall-clock unmanageably, Item 2 fires as a fix-on-same-PR follow-up commit.
- **`EPOCHREALTIME` is bash 5.0+.** The script's existing shebang is `#!/usr/bin/env bash`. CI runs ubuntu-latest (bash 5.x). Local macOS users on the default `/bin/bash` (3.2.x) will see `EPOCHREALTIME` as empty string and the elapsed-ms math will compute `0`. Documented in script header.
- **A plan whose `## User-Brand Impact` section is empty, contains placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6.** This plan's section is fully populated and carried verbatim from spec; threshold is `single-user incident`.

## Deferred Items (follow-up issues to be filed)

The following are explicitly out of scope and MUST have a tracking issue filed BEFORE this PR merges. Each issue links back to #3680.

1. **Bun version probe** — separate exploratory PR that bumps `.bun-version` to the latest 1.3.x patch and runs `bun test test/ plugins/soleur/` (the actual bun-runtime test surfaces — `apps/web-platform` is Vitest, excluded) to see if the FPE class still fires in 2026. If gone, Approach D (in-process `--max-pool-size`) unlocks for future use. **Tracking issue:** to be created at plan-implementation start, milestone `Post-MVP / Later`, labels: `chore`, `domain/engineering`, `priority/p3-low` (labels verified to exist via `gh label list`). Re-evaluation criteria: trigger a fresh probe after every minor-version Bun bump.

2. **Pivot: `apps/web-platform/` suite-internal split** — splits `apps/web-platform/test/` into sub-directories (`auth/`, `kb/`, `sandbox/`, ...) and updates `test-all.sh` to call each as its own `run_suite` line. This expands the webplat-side to N sub-suites and lets future matrix sharding bin-pack more aggressively. **Trigger condition:** Phase 2 validation shows `test-webplat` wall-clock dominates >100s consistently AND no other shard can absorb the imbalance. Fires as a fix-on-same-PR follow-up commit if measured pre-merge; otherwise as a post-merge follow-up issue. **Tracking issue:** to be created at plan-implementation start, milestone `Post-MVP / Later`, labels: `chore`, `domain/engineering`, `priority/p3-low`. (v1's pre-Phase-1b BLOCKER trigger on spawn-count is dropped — webplat is Vitest, not Bun, so the FPE-class spawn-count gate doesn't apply.)

3. **E2E job sharding (`--shard=2`)** — separate PR that adds a 2-way Playwright `--shard` matrix to the `e2e` job + synthetic `e2e` aggregator, mirroring the test-job pattern from this PR. The brainstorm originally bundled it; plan review (code-simplicity) flagged independent blast radius. Expected savings: 111s → ~65s slow-side. **Tracking issue:** to be created at plan-implementation start, milestone `Post-MVP / Later`, labels: `chore`, `domain/engineering`, `priority/p3-low`. Re-evaluation criteria: ship after the test-job pattern proves stable in production (≥1 week post-merge with no regressions).

All three deferral issues are created with `gh issue create` during Phase 1b implementation (commit 3) and linked from PR #3672's "Out of scope" section. Each title prefix `ci:` per conventional-commit style.

## Alternatives Considered

| Approach | Decision | Rejection rationale |
|---|---|---|
| **Two-way bun-vs-bash split (v1's choice)** | Rejected for replan | Drops the 11 pre-suite bash/python tests under `TEST_GROUP=bash` semantics (those tests don't match the `plugins/soleur/test/*.test.sh` glob and aren't in the named-bun block). Violates G2 (orphan-suite invariant) and AC2 (byte-identical no-args). |
| **A indexed N-way matrix sharding** | Rejected for v1 (same as v1) | More setup overhead, shard-list generator must re-use `test-all.sh` discovery, marginal savings over the natural 3-way runtime-axis cleavage. Revisit only if Phase 0 reveals imbalance >2:1 within a single shard. |
| **B in-script `xargs -P` parallelization** | Rejected | Confirmed sharp edges on this codebase: `process.env` leak class (`apps/web-platform/test/workspace.test.ts`), `_site/` race, single-runner OOM risk per FPE learning's 1.1 GB pre-crash spike. v1's `apps/telegram-bridge:health.test.ts:23` port-collision sharp edge is REMOVED — that file does not exist. |
| **C trim slowest suite** | Rejected as primary; deferred as complement | Bounded ceiling; only useful as Item 2 pivot if 3-way underperforms. |
| **D `bun test --max-pool-size`** | Rejected | Directly re-creates the FPE spawn-pressure pattern the sequential runner was built to mitigate. |
| **GitHub-hosted larger runner** (`ubuntu-latest-4-cores`) | Rejected | Paid; shifts cost without changing the serial-per-suite bottleneck. |
| **Touched-file-aware test selection** | Rejected | Violates orphan-suite invariant (PR #3512/#3533) without complex preservation logic. |
| **Ruleset 14145388 edit (rename required context)** | Rejected | Synthetic aggregator strategy makes this unnecessary AND keeps the change reversible. Editing the ruleset requires admin scope and leaves drift if CI is later reverted. |
| **Bun version bump bundled with matrix split** | Rejected | Would mask which change caused any regression. Probe lives in separate follow-up PR (Deferred Items Item 1). |
| **E2E `--shard=2` bundled with this PR** | Deferred | Plan review (code-simplicity) flagged independent blast radius. Ships as Deferred Item 3 follow-up PR after the test-job pattern proves stable. |
| **5-run validation phase** | Rejected | Architecture review P2-2 math: 1-in-10 flake passes 5/5 ~59%. Bumped to 10 runs. |
| **Edit ruleset 14145388 to require all three shards directly** | Rejected | Simplicity reviewer offered this for v1. Rejected: ruleset edits require admin scope and out-of-band coordination — the aggregator keeps the change self-contained in one PR (corrected framing per simplicity review; the prior "drift risk" framing was weaker). Same logic applies to 3-way split. |
| **Migrate `apps/web-platform` from Vitest to Bun** | Rejected | Different runtime, different parallelism model, large blast radius, no measurement supporting the migration. Out of scope per N11. |

## Research Insights

(Updated with replan-time verification; supersedes v1's Research Insights where they made fabricated claims.)

- **`scripts/test-all.sh` topology (verified 2026-05-12 against `c8d77adf` HEAD):** 17 named `run_suite` calls + 1 glob loop over `plugins/soleur/test/*.test.sh`. Total **38 suites**: 11 pre-suite bash/python (lines 52-62), 3 bun-named (lines 63-65), 1 vitest in `apps/web-platform` (line 66), 1 bun recursive `plugins/soleur` (line 67), 1 bash `blog-link-validation` (line 68), 21 `*.test.sh` glob. *(Corrects v1's "29 suites" claim.)*
- **`apps/web-platform` test runtime:** Vitest 3.x, NOT Bun, NOT Jest. `apps/web-platform/package.json` has `"test:ci": "vitest run"`; `apps/web-platform/vitest.config.ts` exists; 274 `.test.ts` files under apps/web-platform. The runner is invoked via `bash -c "cd apps/web-platform && npm run test:ci"` — uses the npm-installed vitest binary at `node_modules/.bin/vitest`, but the `node_modules` itself is populated by `bun install --frozen-lockfile` (line 8 of the `test` job). *(Corrects v1's "bun test apps/web-platform/" claim.)*
- **`apps/telegram-bridge` does not exist.** Verified via `ls apps/` (returns only `web-platform`) and `find . -maxdepth 3 -type d -name "*telegram*"` (returns nothing). v1 plan and brainstorm Phase 1.1 references are fabricated. *(Replan finding.)*
- **Repo lockfile shape:** root `bun.lock` (text, 256 KB), `package-lock.json` (npm, used by `lockfile-sync` and `web-platform-build` jobs); `apps/web-platform/bun.lock` (text, 256 KB), `apps/web-platform/package-lock.json` (npm, 515 KB). No `*.lockb` files anywhere. *(Corrects v1's cache-key shape.)*
- **FPE constraint** (`knowledge-base/project/learnings/2026-03-20-bun-fpe-spawn-count-sensitivity.md`): Bun 1.3.5 SIGFPE at ~130+ subprocess spawns in one bun-test process. Mitigation: pin `.bun-version` to 1.3.11 AND keep per-suite isolation via sequential `test-all.sh`. Both mitigations remain load-bearing.
- **Largest bun-test invocation:** `bun test plugins/soleur/` (25 `.test.ts` files in one bun process). `apps/web-platform` would be larger (274 files) but it's vitest, not bun. *(Phase 0 probe retarget basis.)*
- **`_site/` rebuilders** (`plugins/soleur/test/seo-aeo-drift-guard.test.ts` builds via `bun test plugins/soleur/`; `scripts/validate-blog-links.sh` reads OR builds via `npx --yes @11ty/eleventy --quiet` at lines 25-29 if `_site/` is absent): co-located in the `bun` shard for perf reuse, race-free under matrix sharding.
- **Root `@11ty/eleventy` is a root devDep** (`package.json:7`, `^3.1.5`). Root `bun install --frozen-lockfile` puts it in `node_modules/`, so `npx @11ty/eleventy` resolves locally inside the `test-bun` shard — no on-the-fly download.
- **`actions/cache` precedent in repo:** ZERO (verified `grep -rn 'actions/cache@' .github/workflows/`). This PR introduces the pattern. Repo permits all actions (no allowlist gate).
- **e2e job currently runs in Playwright container** (`.github/workflows/ci.yml` lines 153+, the `e2e` job): `mcr.microsoft.com/playwright:v1.58.2-jammy@sha256:4698a73749c5848d3f5fcd42a2174d172fcad2b2283e087843b115424303a565`. Out of scope for this PR; relevant when Deferred Item 3 lands.
- **Ruleset 14145388 contexts** (verified via `gh api repos/jikig-ai/soleur/rulesets/14145388`): `test`, `e2e`, `dependency-review`, `CodeQL`, `skill-security-scan PR gate`. Only `test` and `e2e` originate from this repo's `ci.yml`; the other three are externally configured. This PR touches `test` only; `e2e` remains satisfied by the existing single-job definition.
- **`actions/cache@v4.3.0` SHA resolved and verified at replan time:** `0057852bfaa89a56745cba8c7296529d2fc39830` (via `gh api repos/actions/cache/git/refs/tags/v4 --jq .object.sha` on 2026-05-12, type `commit`).
- **`if: always() && needs.<job>.result == 'failure'` precedent** for fail-closed aggregator: `.github/workflows/scheduled-compound-promote.yml:291`. The plan adopts a per-shard loop variant of this idiom (cleaner with 3 shards than a flat conjunction).
- **`scripts/*.sh` precedent for positional-arg mode selector:** `scripts/validate-blog-links.sh:10` (`SITE_DIR="${1:-}"`), `scripts/provision-plausible-goals.sh:59` (`local method="$1"`). Env-vars in `scripts/` are reserved for ambient context (`GH_TOKEN`, `REPO_ROOT`). The plan supports both forms (`bash scripts/test-all.sh bun` AND `TEST_GROUP=bun bash scripts/test-all.sh`); workflow uses positional for grep-ability.
- **`.test.sh` files do NOT invoke `bun`** (verified `grep -l "^bun " plugins/soleur/test/*.test.sh` returns 0; `grep -l "bun " plugins/soleur/test/*.test.sh` also returns 0 across all 21 files). The `test-scripts` shard therefore needs NO `setup-bun` step. Documented in YAML comment so the constraint travels with the job definition.

## SpecFlow Analysis (skipped with rationale)

The Phase 3 SpecFlow Analyzer step is **skipped** for this plan. Rationale:

- The plan's flow surface is a CI workflow (YAML) + a single bash case-statement (`case "$TEST_GROUP" in all|webplat|bun|scripts) ... esac`). The conditional logic is shallow (4 enum values, one validation arm, no nested branches).
- The brainstorm Phase 0.5 covered flow gaps already — `_site/` race (reframed in replan as perf rather than correctness), env-leak (suite-internal, not shard-boundary), FPE-class. The 11 dropped-pre-suite gap that v1 missed is itself caught by replan AC2 (byte-identical no-args).
- The risk SpecFlow would catch (bash conditional edge case silently dropping a suite) is bounded by AC2-AC6 which mandate empirical verification of all five `TEST_GROUP` modes (all/webplat/bun/scripts/invalid) and both invocation forms (positional + env).

If review-time concerns surface a flow gap, run `Task spec-flow-analyzer` inline and amend the plan.

## Plan Review Resolution

This replan **inherits v1's plan-review resolutions** (Architecture P1/P2/P3, Pattern HIGH/MEDIUM/LOW, Code-Simplicity #1-#7). v1's resolutions remain valid because the approach class (synthetic aggregator + matrix split) is unchanged. The replan corrects factual preconditions only.

**New replan-specific items resolved at re-draft time:**

- **R1 — Suite topology correction:** 29 → 38 suites; 2-way bun/bash → 3-way webplat/bun/scripts; 11 pre-suite tests no longer dropped. Carried into G2, AC2-AC6, all Phase code blocks.
- **R2 — Telegram-bridge removal:** dropped from `run_suite` list, Phase 1b YAML, Approach B sharp edges, and Deferred-Items text. AC16 adds a drift safeguard (grep-zero post-merge).
- **R3 — `apps/web-platform` runtime correction:** Vitest, not Bun. Phase 0 spawn-count probe retargeted to `bun test plugins/soleur/`. v1's pre-Phase-1b HALT gate (Phase 0 spawn count >130 → fold in Item 2) DROPPED because matrix sharding bounds cross-suite spawn pressure regardless of intra-suite count. G5 reframed informational. Item 2 trigger condition simplified to "Phase 2 wall-clock dominates."
- **R4 — Cache-key shape correction:** `bun.lockb` → `bun.lock` (text, not binary). Per-shard cache scope documented. AC17 adds a drift safeguard.
- **R5 — TEST_GROUP enum expansion:** 3 values (all/bun/bash) → 4 values (all/webplat/bun/scripts). Validation arm message updated. AC5 added for the new `scripts` group. T4 added.

**Net change from v1:**

- Suite count: 29 → 38 throughout.
- Shard count: 2 → 3 (webplat/bun/scripts).
- TEST_GROUP enum: {all,bun,bash} → {all,webplat,bun,scripts}.
- Phase 0 spawn-count probe: HALT gate → informational.
- Phase 1b YAML: 2 jobs + aggregator → 3 jobs + aggregator; `Enforce telegram-bridge coverage` step dropped; `actions/cache` keyed on `bun.lock` not `bun.lockb`.
- Phase 2 T14 SKIPPED-shard: 1 sub-mutation → 3 sub-mutations (one per shard).
- New ACs: AC5 (scripts group), AC15 reordered, AC16 (no-telegram-bridge), AC17 (no-bun.lockb).
- Sharp Edges: 4 new entries documenting the replan findings (Vitest != Bun FPE, no telegram-bridge, bun.lock not bun.lockb, _site race reframe).
- Estimated line-count change: net +60 (reconciliation table + new Sharp Edges + 4-value enum + 3-shard YAML; offset by dropped telegram-bridge step and dropped pre-Phase-1b BLOCKER text).

---

**End of plan.** Next: regenerate `tasks.md`, commit, push.
