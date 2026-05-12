---
title: "CI test-job speedup — bun-vs-bash matrix split with synthetic aggregator"
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
---

# Plan: CI test-job speedup — bun-vs-bash matrix split with synthetic aggregator

**Issue:** #3680
**Branch:** `feat-ci-test-job-speedup`
**Draft PR:** #3672
**Brainstorm:** [`knowledge-base/project/brainstorms/2026-05-12-ci-test-job-speedup-brainstorm.md`](../brainstorms/2026-05-12-ci-test-job-speedup-brainstorm.md)
**Spec:** [`knowledge-base/project/specs/feat-ci-test-job-speedup/spec.md`](../specs/feat-ci-test-job-speedup/spec.md)

## Overview

Cut the `test` job in `.github/workflows/ci.yml` from ~199s → <130s (stretch <100s) by:

1. Refactoring `scripts/test-all.sh` to accept a `TEST_GROUP` selector (positional arg `$1` OR env-var, default `all`) so the workflow can request just the bun-side or bash-side suites without inlining the suite list in CI.
2. Splitting the `test` CI job into two parallel jobs (`test-bun`, `test-bash`) + a synthetic aggregator job named `test` that satisfies the existing branch-protection ruleset 14145388 required-context contract.
3. Adding `actions/cache@v4` (new pattern in this repo) keyed on `bun.lockb` to skip redundant `bun install` work on shard re-runs.

The Phase 0 measurement step instruments `test-all.sh` with per-suite `EPOCHREALTIME` boundaries AND a subprocess spawn-count probe over `apps/web-platform/` (the largest single-process bun-test invocation), so the per-suite timing table AND the FPE-class-residual-risk number appear in PR #3672's body before any workflow restructure ships.

Branch-protection ruleset 14145388 is NOT edited. The synthetic-aggregator strategy makes any ruleset change unnecessary — the load-bearing reason is that ruleset edits require admin scope and out-of-band coordination, not the weaker "drift risk" framing.

**E2E sharding deferred.** The brainstorm originally bundled `e2e --shard=2`, but plan review flagged it as scope creep with an independent blast radius. It's moved to Deferred Items (Item 3) — separate follow-up PR.

## Research Reconciliation — Spec vs. Codebase

The brainstorm captured most of the codebase state correctly. Three claims need explicit reconciliation, found at plan time, before they propagate into implementation:

| Claim source | Brainstorm/spec said | Codebase reality | Plan response |
|---|---|---|---|
| Original feature description | "37 test suites" | 29 suites (7 named + 22 bash globs) — verified `wc -l plugins/soleur/test/*.test.sh` | Spec/plan use 29 throughout. Already corrected. |
| Original feature description | "marketing-content-drift.test.ts rebuilds `_site/` mid-test" | No file by that name. Actual `_site/` rebuilders: `plugins/soleur/test/seo-aeo-drift-guard.test.ts` (bun, gated by `SEO_AEO_SKIP_BUILD=1`) + `scripts/validate-blog-links.sh` (bash, reads `_site/`). | FR4 in spec already names the correct files; this plan keeps that pairing intact. |
| Brainstorm "Capability Gaps" | "`actions/cache` is in the repo's permitted-actions allowlist (used in other workflows for Playwright caches)" | `grep -rn 'actions/cache@' .github/workflows/` returns ZERO matches. `actions/cache` is unused in this repo. The repo's GitHub Actions policy allows all actions (`gh api repos/.../actions/permissions/selected-actions` → 409 "All actions and workflows are allowed"). | Plan treats `actions/cache@v4` as a **new pattern introduction**, not a precedent-follow. SHA pin required. Add to Files to Create as "first cache-action usage in this repo". |

No other spec/brainstorm claims diverge from codebase state. The orphan-suite invariant (PR #3512/#3533), the FPE constraint at Bun 1.3.11, the cross-suite shared-state inventory (`workspace.test.ts` env-leak, `_site/` race, telegram-bridge `:health.test.ts:23` port binding), and the ruleset-14145388 required-context list (`test`, `e2e`, `dependency-review`, `CodeQL`, `skill-security-scan PR gate`) all hold as documented.

## Problem Statement

The `test` job is one of five required status checks on branch-protection ruleset 14145388. Its 199s median wall-clock directly gates merge time for every PR — including PRs touching regulated surfaces (GDPR transcript persistence #3603, payment retry, auth boundaries). `scripts/test-all.sh` runs ~29 test suites strictly sequentially, by design, to defend against a Bun SIGFPE crash whose probability scales with cumulative subprocess spawn count (`knowledge-base/project/learnings/2026-03-20-bun-fpe-spawn-count-sensitivity.md`). `.bun-version` is now 1.3.11 (six patches past the FPE-1.3.5 baseline) but the sequential runner is documented as defense-in-depth and is the project's load-bearing mitigation. Direct in-process parallelism (Approach D, `bun test --max-pool-size`) re-creates the exact spawn-pressure pattern the sequential runner exists to prevent. Per-process matrix sharding sidesteps this — each shard runs in its own GitHub-hosted runner with its own Bun GC accounting.

The secondary `e2e` job (111s) runs in a Playwright container (`mcr.microsoft.com/playwright:v1.58.2-jammy`). Playwright supports `--shard=K/N` natively, so a 2-way split is mechanically simple.

## Goals

- **G1:** Reduce median `test` job wall-clock to <130s on ≥6 of 10 validation runs (60% threshold). Stretch: <100s.
- **G2:** Preserve the `test-all.sh` orphan-suite invariant. Local invocation `bash scripts/test-all.sh` with no args runs all 29 suites in the same order, with identical exit semantics.
- **G3:** Keep branch-protection ruleset 14145388 untouched. The required context `test` survives via a synthetic aggregator job. (Note: `e2e` required context remains satisfied by the existing single-job `e2e` definition; e2e sharding is deferred.)
- **G4:** Introduce no new flake class. 10/10 green validation runs + 11th green run post-merge on main (the bump from 5 to 10 follows architecture review P2-2 — at the brand-survival `single-user incident` threshold, 5/5 green admits ~59% false-pass probability for a 1-in-10 flake; 10/10 green tightens to ~35%).
- **G5:** No intra-shard FPE re-trigger risk. Phase 0 spawn-count probe over `apps/web-platform/` must report aggregate `clone(2)` count <100 (well below the ~130-spawn FPE threshold documented in `knowledge-base/project/learnings/2026-03-20-bun-fpe-spawn-count-sensitivity.md`); otherwise this PR gates on Deferred-Items Item 2 pivot before workflow restructure.

## Non-Goals

- **N1:** Bun version bump. `.bun-version` stays at 1.3.11.
- **N2:** Suite-internal split of `apps/web-platform/test/` into sub-directories. Deferred (see Deferred Items Item 2). May fire as a pre-Phase-1b gate if Phase 0 spawn-count probe trips.
- **N3:** In-script `xargs -P` parallelization (Approach B in brainstorm). Rejected.
- **N4:** `bun test --max-pool-size` (Approach D). Rejected.
- **N5:** Touched-file-aware test selection. Violates orphan-suite invariant.
- **N6:** `web-platform-build` job optimization (different bottleneck class).
- **N7:** Ruleset 14145388 edit.
- **N8:** New test framework dependencies.
- **N9:** **E2E `--shard=2` sharding.** Deferred to Item 3 follow-up PR per plan review (blast-radius isolation).

## User-Brand Impact

(Carried forward verbatim from `knowledge-base/project/specs/feat-ci-test-job-speedup/spec.md`. Per `requires_cpo_signoff: true` frontmatter, CPO sign-off on the chosen approach is satisfied by the Phase 0.5 brainstorm domain assessment — re-spawning is not required unless scope drifts.)

**If this lands broken, the user experiences:**

- Engineers/agents see intermittent red `test` runs caused by a new flake class (shard-bundling exposes a previously isolated `process.env` leak, a `_site/` race, or a port collision). Trust in the red signal erodes; a real regression eventually merges.
- If the merged regression lands in production agent surfaces (`apps/web-platform`, `apps/telegram-bridge`, `apps/cc-soleur-go`) during a compliance-sensitive window — GDPR transcript persistence #3603, payment retry, auth boundary — the failure crosses from dev-velocity into brand-survival.
- Team-wide unmergeable state if the synthetic aggregator's job name drifts from ruleset 14145388's required context `test`.

**If this leaks, the user's [data / workflow / money] is exposed via:**

- The merge gate itself is the exposure vector. A flaky-but-not-failing `test` check lets a regression in transcript persistence, payment retry, or auth-boundary handling reach production users undetected. Transcript regression → potential GDPR Art. 32 incident. Payment regression → user-facing money-flow error. Auth regression → cross-tenant read.

**Brand-survival threshold:** `single-user incident`.

**Mitigations specific to this PR:**

- Synthetic aggregator preserves the required-check contract without ruleset edit (TR1) — orphan-check failure mode bounded.
- `_site/` builders co-located (FR4) — race vector eliminated by construction.
- Aggregator MUST fail-closed (FR3, no `||` fallback per `knowledge-base/project/learnings/2026-03-19-ci-squash-fallback-bypasses-merge-gates.md`) — silent partial-success blocked.
- 5-run validation + 6th post-merge run (SC3, SC6) — flake class would surface before merge or in the first post-merge sanity check.
- `user-impact-reviewer` agent runs at PR-review time (handled by `plugins/soleur/skills/review/SKILL.md` conditional-agent block).

## Domain Review

**Domains relevant:** Engineering, Product, Legal (carried forward from brainstorm Phase 0.5).

### Engineering (CTO)

**Status:** reviewed (brainstorm carry-forward)
**Assessment:** Recommended Approach A with synthetic aggregator. Confirmed Bun 1.3.11 still treats sequential isolation as defense-in-depth. Ruled out Approach D (FPE re-trigger) and Approach B (three confirmed sharp edges). Flagged that stretch <100s requires suite-internal split of `apps/web-platform/test/`. No new technical concerns at plan time.

### Product (CPO)

**Status:** reviewed (brainstorm carry-forward)
**Assessment:** No direct product angle; defers to CTO. Treats the single-user incident threshold as a hard non-regression constraint, not a product gate. CPO sign-off on the brainstorm approach satisfies plan-time `requires_cpo_signoff: true`.

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

**None.** Queried `gh issue list --label code-review --state open --json number,title,body --limit 200` and filtered for `scripts/test-all.sh` or `.github/workflows/ci.yml` substrings — zero matches. Plan can proceed without folding in or acknowledging existing scope-outs on the planned files.

## Implementation Phases

### Phase 0 — Measurement (commit 1, BEFORE workflow restructure)

Instrument `scripts/test-all.sh` with per-suite **`EPOCHREALTIME`** boundaries (bash 5.0+ builtin, microsecond precision, portable across Linux and macOS bash 5 — no `coreutils` dependency, no `date +%N` macOS gap), AND probe the subprocess spawn count for `apps/web-platform/` so the FPE-class residual-risk number lands in the PR body before any workflow restructure.

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
# Architecture P1-2: confirm apps/web-platform doesn't blow past the FPE
# threshold inside a single bun process. ~130+ spawns = ~100% crash in 1.3.5;
# 1.3.11 is patched but defense-in-depth requires we stay well below.
strace -fe trace=clone -c bun test apps/web-platform/ 2>/tmp/strace-summary.txt 1>/dev/null
grep "clone" /tmp/strace-summary.txt
# Expected: report total clone(2) syscalls. <100 = safe; 100-130 = caution; >130 = pivot.
```

Run locally on Linux (CI is ubuntu-latest so `strace` is available there too):

```bash
TEST_TIMING_LOG=/tmp/test-timing.tsv bash scripts/test-all.sh
sort -t$'\t' -k2 -n -r /tmp/test-timing.tsv | head -10
```

**Acceptance:** PR #3672 body MUST contain:

1. A markdown table of all 29 suite wall-clock timings, with top 5 highlighted in bold and bun-side / bash-side aggregate totals computed.
2. A single line stating whether bun-vs-bash is balanced enough to proceed (`max(bun, bash) / min(bun, bash) < 2.0`). If imbalance >2:1, this plan PIVOTS to indexed 3-way matrix sharding (see Deferred Items).
3. The `apps/web-platform/` `clone(2)` spawn count from the strace probe. If <100, Phase 1b proceeds unmodified. If 100-130, Phase 1b proceeds but Sharp Edges retains the residual-risk note + the Deferred-Items Item 2 pivot moves from "follow-up" to "next PR". If >130, this PR HALTS and Deferred-Items Item 2 (suite-internal split of `apps/web-platform/`) becomes a pre-Phase-1b blocker on this same PR — bringing it into scope.

**Commit message:** `feat(ci): instrument test-all.sh with per-suite timing — #3680`

### Phase 1 — Test job split + cache (commits 2 and 3)

#### Phase 1a — TEST_GROUP selector in test-all.sh (commit 2)

Refactor `scripts/test-all.sh` so the suite invocations are gated by `TEST_GROUP`. Per pattern review MEDIUM-2, support BOTH a positional argument (idiomatic for `scripts/*.sh` per `scripts/validate-blog-links.sh:10` and `scripts/provision-plausible-goals.sh:59`) AND an env-var (composes with GitHub Actions `env:` blocks and `gh workflow run`):

```bash
# Selector: positional $1 OR TEST_GROUP env (env wins for explicit CI use).
TEST_GROUP="${TEST_GROUP:-${1:-all}}"

if [[ "$TEST_GROUP" != "all" && "$TEST_GROUP" != "bun" && "$TEST_GROUP" != "bash" ]]; then
  echo "ERROR: TEST_GROUP must be one of: all, bun, bash (got: $TEST_GROUP)" >&2
  echo "Usage: bash scripts/test-all.sh [all|bun|bash]   or   TEST_GROUP=bun bash scripts/test-all.sh" >&2
  exit 2
fi

if [[ "$TEST_GROUP" == "all" || "$TEST_GROUP" == "bun" ]]; then
  run_suite "test/content-publisher" bun test test/content-publisher.test.ts
  run_suite "test/x-community" bun test test/x-community.test.ts
  run_suite "test/pre-merge-rebase" bun test test/pre-merge-rebase.test.ts
  run_suite "apps/web-platform" bun test apps/web-platform/
  run_suite "apps/telegram-bridge" bun test apps/telegram-bridge/
  run_suite "plugins/soleur" bun test plugins/soleur/
  # _site/ builder must run BEFORE validate-blog-links reads it.
  # Keep validate-blog-links here (NOT in bash group) — co-located with
  # seo-aeo-drift-guard.test.ts which builds _site/ inside plugins/soleur.
  run_suite "blog-link-validation" bash scripts/validate-blog-links.sh
fi

if [[ "$TEST_GROUP" == "all" || "$TEST_GROUP" == "bash" ]]; then
  for f in plugins/soleur/test/*.test.sh; do
    [[ -f "$f" ]] || continue
    run_suite "$f" bash "$f"
  done
fi
```

**Also add a header comment to `scripts/validate-blog-links.sh`** (architecture P2-3 — invariant must live in the consumed file, not only in the workflow):

```bash
# INVARIANT: this script reads _site/, which is built by
# plugins/soleur/test/seo-aeo-drift-guard.test.ts. It MUST run in the same
# TEST_GROUP as that test (currently "bun"). See scripts/test-all.sh and
# the test-bun job in .github/workflows/ci.yml. Moving this to the bash
# group creates a _site/ race condition under matrix sharding.
```

**Backward compatibility:** With `TEST_GROUP` unset and no positional arg, behavior is byte-identical to today. Local invocations and the existing one-job CI path don't change.

**Acceptance:** `bash scripts/test-all.sh bun` and `TEST_GROUP=bun bash scripts/test-all.sh` both run the 7 bun-side suites (including `validate-blog-links.sh`). `bash scripts/test-all.sh bash` and `TEST_GROUP=bash bash scripts/test-all.sh` both run the 22 `.test.sh` files. `bash scripts/test-all.sh invalid` exits 2 with usage message. `TEST_GROUP` env wins if both are set (the `${TEST_GROUP:-${1:-all}}` shape evaluates the positional arg only when env is unset).

**Commit message:** `feat(ci): add TEST_GROUP selector to test-all.sh — #3680`

#### Phase 1b — CI workflow refactor (commit 3)

Replace the single `test` job in `.github/workflows/ci.yml` with three jobs:

```yaml
test-bun:
  runs-on: ubuntu-latest
  steps:
    - uses: actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5 # v4.3.1
    - uses: oven-sh/setup-bun@3d267786b128fe76c2f16a390aa2448b815359f3 # v2.1.2
      with:
        bun-version-file: ".bun-version"
    - name: Cache bun install
      uses: actions/cache@0057852bfaa89a56745cba8c7296529d2fc39830 # v4.3.0
      with:
        path: |
          ~/.bun/install/cache
          node_modules
          apps/web-platform/node_modules
        key: bun-${{ runner.os }}-${{ hashFiles('bun.lockb', 'apps/web-platform/bun.lockb') }}
        restore-keys: |
          bun-${{ runner.os }}-
    - name: Install dependencies
      run: bun install --frozen-lockfile
    - name: Install web-platform dependencies
      run: bun install --frozen-lockfile
      working-directory: apps/web-platform
    - name: Type-check web-platform
      run: bunx tsc --noEmit
      working-directory: apps/web-platform
    - name: Run bun-side tests
      run: bash scripts/test-all.sh bun
    - name: Enforce telegram-bridge coverage
      run: bun test --coverage
      working-directory: apps/telegram-bridge

test-bash:
  runs-on: ubuntu-latest
  steps:
    - uses: actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5 # v4.3.1
    - uses: oven-sh/setup-bun@3d267786b128fe76c2f16a390aa2448b815359f3 # v2.1.2
      with:
        bun-version-file: ".bun-version"
    - name: Cache bun install
      uses: actions/cache@0057852bfaa89a56745cba8c7296529d2fc39830 # v4.3.0
      with:
        path: |
          ~/.bun/install/cache
          node_modules
        key: bun-${{ runner.os }}-${{ hashFiles('bun.lockb') }}
        restore-keys: |
          bun-${{ runner.os }}-
    - name: Install dependencies
      run: bun install --frozen-lockfile
    - name: Run bash-side tests
      run: bash scripts/test-all.sh bash

test:
  # Synthetic aggregator.
  #
  # LOAD-BEARING SUB-VALUE (per 2026-05-06-defense-in-depth-recovery-mirroring-
  # sql-predicate-document-load-bearing-value.md): the aggregator is NOT
  # redundant with branch-protection ruleset 14145388's `test` required check.
  # It carries three distinct values: (a) cross-layer truing — converts two
  # shard `conclusion`s into one required-context conclusion the ruleset
  # already expects by name; (b) drift-resilience — survives a future
  # ruleset edit that changes the required-context list, as long as the
  # `test` name still gates merge; (c) observability — single PR-status row
  # to inspect, not two. Removing this job orphans ruleset 14145388's `test`
  # required check and breaks every PR merge.
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
  needs: [test-bun, test-bash]
  if: always()
  runs-on: ubuntu-latest
  steps:
    - name: Aggregate shard results
      run: |
        if [[ "${{ needs.test-bun.result }}" != "success" ]]; then
          echo "test-bun shard: ${{ needs.test-bun.result }}" >&2
          exit 1
        fi
        if [[ "${{ needs.test-bash.result }}" != "success" ]]; then
          echo "test-bash shard: ${{ needs.test-bash.result }}" >&2
          exit 1
        fi
        echo "All shards green."
```

**Critical design notes:**

- **`if: always()` + per-shard explicit checks** is the canonical GitHub Actions fail-closed aggregator pattern. Precedent: `.github/workflows/scheduled-compound-promote.yml:291`. Without `if: always()`, the default `needs:` semantics produce a `skipped` aggregator if a shard fails (or is itself skipped via `paths-ignore` / conditional `if:`) — and `skipped` is treated as success by some branch-protection configs. The `if: always()` + manual result inspection forces explicit pass/fail.
- **No `|| true`, no `continue-on-error: true`** anywhere in the aggregator. Per `knowledge-base/project/learnings/2026-03-19-ci-squash-fallback-bypasses-merge-gates.md`.
- **`actions/cache@v4.3.0` SHA-pinned inline.** SHA `0057852bfaa89a56745cba8c7296529d2fc39830` resolved at plan time per pattern review HIGH-1 (matches the SHA-pin discipline every other action in this workflow follows). Verified via `gh api repos/actions/cache/git/refs/tags/v4 --jq .object.sha` on 2026-05-12. If the v4 tag is moved before implementation, re-resolve and update.
- **Type-check step retained inside `test-bun`** rather than promoting to its own job. The 18s type-check is small relative to `test-bun`'s expected ~100-120s; promoting would add another shard's setup overhead (~10-15s) with no parallelism benefit.
- **Plain `bash scripts/test-all.sh bun` / `bash scripts/test-all.sh bash`** — positional-arg form, more grep-able than the env-var form. Per pattern review MEDIUM-2 the script supports both; we pick positional for the workflow because it's easier to grep "where is `test-all.sh bun` called from".

**Acceptance:** The aggregator job named exactly `test` appears in `gh run view <run-id> --json jobs` with `status: completed, conclusion: success` when both shards pass; `conclusion: failure` when either fails. Ruleset 14145388 unchanged.

**Commit message:** `feat(ci): split test job into bun + bash shards with synthetic aggregator — #3680`

### Phase 2 — Validation (no commit; PR-level — 10 runs)

Per architecture review P2-2, the `single-user incident` brand-survival threshold makes a 5-run validation statistically thin (a 1-in-10 flake passes 5/5 ~59% of the time). Bump to **10 runs**:

```bash
for i in 1 2 3 4 5 6 7 8 9 10; do
  git commit --allow-empty -m "ci: validation run $i"
  git push
done
```

`gh workflow run` is not available (the `ci.yml` triggers are `push` + `pull_request` + `workflow_dispatch` — workflow_dispatch is absent). Empty-commit-push cycles are the only path.

Collect timings:

```bash
gh run list --branch feat-ci-test-job-speedup --workflow ci.yml --limit 15 --json databaseId,status,conclusion,createdAt,jobs > /tmp/runs.json
jq -r '.[] | select(.status=="completed") | "\(.createdAt)\t\(.conclusion)\t\(.databaseId)"' /tmp/runs.json
```

For each run, extract the `test` aggregator duration:

```bash
gh run view <run-id> --json jobs | jq -r '.jobs[] | select(.name == "test") | "\(.startedAt)\t\(.completedAt)\t\(.conclusion)"'
```

**SKIPPED-shard mutation test (T14, per architecture review P1-1).** Before the 10 regular runs, push a single mutation: edit `.github/workflows/ci.yml` to add `if: false` to the `test-bun` job. Push. Confirm:

1. `test-bun` reaches `conclusion: skipped`.
2. The synthetic `test` aggregator reaches `conclusion: failure` (NOT `skipped`).
3. Attempting `gh pr merge` reports the `test` required check failing — branch protection blocks the merge.

Revert the mutation before continuing to the 10 validation runs. This proves the aggregator does not silently fail open on a future `paths-ignore` or conditional-`if:` edit.

**Acceptance:** `test` aggregator wall-clock <130s on ≥6 of 10 runs; 10/10 green. SKIPPED-shard test confirmed branch-protection blocks merge. If <6/10 within target, pivot to Deferred-Items Item 2 (`apps/web-platform/` internal split) in a follow-up commit on this same PR.

### Phase 3 — Post-merge sanity (no commit; gh-only)

After merge to main, verify:

1. `gh api repos/jikig-ai/soleur/rulesets/14145388 --jq '.rules[] | select(.type=="required_status_checks") | .parameters.required_status_checks[].context'` returns the identical 5-context list as pre-merge (`test`, `e2e`, `dependency-review`, `CodeQL`, `skill-security-scan PR gate`).
2. The next PR opened against main shows the `test` check running as expected, and merge is gated by it.
3. The main-branch CI run on the merge commit shows the `test` aggregator green with wall-clock within Phase 2 target (post-merge sanity = 11th green run).

If any check fails, revert PR via `git revert <merge-sha>` and re-open. The aggregator-rename failure mode is bounded: revert restores the single-job `test` definition immediately.

## Files to Edit

- `scripts/test-all.sh` — Phase 0 timing instrumentation (commit 1) + Phase 1a `TEST_GROUP` selector (commit 2).
- `scripts/validate-blog-links.sh` — header invariant comment (commit 2, alongside test-all.sh selector — co-located change because the invariant binds the two scripts).
- `.github/workflows/ci.yml` — Phase 1b matrix + aggregator (commit 3).

## Files to Create

- *(none)* — all changes land in three existing files. The `actions/cache@v4.3.0` reference is a new step inside an existing workflow file, not a new file.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1:** PR #3672 body contains (a) a markdown table of all 29 suite wall-clock timings from Phase 0 measurement with top-5 highlighted and bun-side/bash-side aggregate totals, (b) the `apps/web-platform/` strace clone-syscall count and a single-line verdict (`<100: safe / 100-130: caution / >130: HALT and pivot Item 2 inline`).
- [ ] **AC2:** `bash scripts/test-all.sh` (no args, no env) runs all 29 suites in the original order and exits 0 on success, 1 on any failure — byte-identical exit semantics to today.
- [ ] **AC3:** Both `bash scripts/test-all.sh bun` and `TEST_GROUP=bun bash scripts/test-all.sh` run only the 7 bun-side suites (including `validate-blog-links.sh`) and respect existing `[ok]`/`[FAIL]` semantics.
- [ ] **AC4:** Both `bash scripts/test-all.sh bash` and `TEST_GROUP=bash bash scripts/test-all.sh` run only the 22 `plugins/soleur/test/*.test.sh` files.
- [ ] **AC5:** `bash scripts/test-all.sh invalid` exits with code 2 and prints both error and usage lines to stderr.
- [ ] **AC6:** `.github/workflows/ci.yml` contains three jobs named `test-bun`, `test-bash`, and `test` (the synthetic aggregator). The aggregator's `needs:` lists both shards and uses `if: always()` + per-shard `result` checks to fail closed. The aggregator job body contains a comment naming the load-bearing sub-value (per architecture P2-1).
- [ ] **AC7:** `actions/cache@v4.3.0` is added to both `test-bun` and `test-bash` jobs with the literal SHA `0057852bfaa89a56745cba8c7296529d2fc39830` pinned (no `@v4` literal, no `@<SHA>` placeholder).
- [ ] **AC8:** `scripts/validate-blog-links.sh` header contains a comment naming the `_site/` co-location invariant with `seo-aeo-drift-guard.test.ts` and pointing to `test-all.sh` + `ci.yml` (per architecture P2-3).
- [ ] **AC9:** `git grep -nE "(\|\| true|continue-on-error: true)" .github/workflows/ci.yml` returns ZERO matches inside the `test`, `test-bun`, or `test-bash` job bodies. Fail-closed invariant.
- [ ] **AC10:** SKIPPED-shard mutation test (T14, architecture P1-1): a temporary `if: false` on `test-bun` produces aggregator `conclusion: failure` AND `gh pr merge` reports the `test` required check failing. Mutation reverted before AC11.
- [ ] **AC11:** Phase 2 validation: 10 independent runs of the workflow on this PR branch; ≥6 show `test` aggregator wall-clock <130s; 10/10 green (all 29 suites pass on every run).
- [ ] **AC12:** `gh api repos/jikig-ai/soleur/rulesets/14145388` returns the same `required_status_checks` context list pre- and post-merge.
- [ ] **AC13:** PR body uses `Closes #3680` (not in title; per `wg-use-closes-n-in-pr-body-not-title-to`).
- [ ] **AC14:** Three GitHub follow-up issues created and linked from the PR body (see Deferred Items: Bun version probe, `apps/web-platform/` internal split, e2e --shard=2).

### Post-merge (operator)

- [ ] **AC15:** Within 24h of merge, the main-branch CI run on the merge commit shows `test` aggregator <130s — 11th green run confirms no flake class introduced.
- [ ] **AC16:** Within 24h, the first new PR opened against main shows the `test` required check present, running, and merge-gating. If the check is missing from the merge-gate view, immediately revert the merge commit.

## Test Scenarios

### Local

- **T1:** Run `bash scripts/test-all.sh` in the worktree → all 29 suites run sequentially in the order documented in the script. Compare timing log against Phase 0 baseline ± 5%.
- **T2:** Run `TEST_GROUP=bun bash scripts/test-all.sh` → 7 suites only. Confirm `scripts/validate-blog-links.sh` is included and runs after `seo-aeo-drift-guard.test.ts`.
- **T3:** Run `TEST_GROUP=bash bash scripts/test-all.sh` → 22 `.test.sh` files only. Confirm none of the 7 bun-side suites run.
- **T4:** Run `TEST_GROUP=invalid bash scripts/test-all.sh` → exits 2 with stderr message.
- **T5:** With `_site/` deleted, run `TEST_GROUP=bun bash scripts/test-all.sh` → `seo-aeo-drift-guard.test.ts` rebuilds `_site/`, then `validate-blog-links.sh` reads from it successfully. No race.

### CI (PR #3672)

- **T6:** Push the Phase 0 instrumentation commit alone; verify CI passes (instrumentation must be backward-compatible — existing single `test` job still runs and times out cleanly on `failed=0`).
- **T7:** Push the Phase 1a `TEST_GROUP` selector commit; verify the existing single `test` job still passes (script invoked with no args defaults to `all`).
- **T8:** Push the Phase 1b workflow restructure commit; verify the new `test-bun`, `test-bash`, and synthetic `test` jobs all appear and run; verify the existing `e2e` job is unchanged.
- **T9:** Phase 2 — 10 empty-commit-push cycles; collect timings via `gh run view`; record into PR body table.

### Negative

- **T10:** Mutation test — temporarily fail one bun suite locally; confirm `bash scripts/test-all.sh bun` exits 1. In CI, confirm `test-bun` reaches `conclusion: failure` and the synthetic `test` aggregator also fails.
- **T11:** Mutation test — temporarily fail one bash suite; confirm `test-bash` fails and aggregator fails.
- **T12:** Mutation test — push a commit that breaks `actions/cache`'s `path:` field syntax; CI shows the cache step failing AND `bun install --frozen-lockfile` still runs successfully. If the cache step does NOT have implicit `continue-on-error`, document this and decide whether to add it (pure-cache failures should NOT fail the job — only test failures should).
- **T13:** Backward-compat regression — invoke `bash scripts/test-all.sh` with no args from the repo root and from any subdirectory; confirm identical 29-suite execution.
- **T14:** SKIPPED-shard mutation (architecture P1-1) — `if: false` on `test-bun`; push; confirm aggregator `conclusion: failure` (NOT `skipped`) and merge gate red.

## Sharp Edges

(Carried forward from brainstorm + supplemented by plan-time research + plan-review findings.)

- **Bun 1.3.11 FPE constraint is defense-in-depth, not eliminated.** Sequential per-suite process isolation still applies. Approaches D (`--max-pool-size`) and B (`xargs -P` within one runner) are rejected outright. Matrix sharding is safe at the **cross-suite** level because separate runners = separate Bun process accounting. **Intra-suite spawn pressure** inside a single suite (notably `apps/web-platform` running 25 `.test.ts` files in one bun process) is NOT protected by sharding — see G5 + Phase 0 spawn-count probe + Deferred-Items Item 2 trigger condition (a).
- **`_site/` race vector is real if `validate-blog-links.sh` and `seo-aeo-drift-guard.test.ts` are split across shards.** FR4 mandates co-location. The plan keeps `validate-blog-links.sh` in the `test-bun` group AND adds an invariant comment to `validate-blog-links.sh`'s header (AC8) so the constraint is discoverable from the consumed file, not only the workflow.
- **Aggregator `if: always()` is load-bearing.** Without it, the default `needs:` semantics produce a `skipped` aggregator when a shard fails OR is itself skipped (e.g., via `paths-ignore` or conditional `if:` clause added later). Some branch-protection configurations treat `skipped` as success — fail-open. Precedent for the `if: always() && needs.<job>.result == "failure"` shape: `.github/workflows/scheduled-compound-promote.yml:291`. T14 (SKIPPED-shard mutation test) proves the design fails closed on this edge case before the 10-run validation.
- **`actions/cache@v4.3.0` is a NEW PATTERN in this repo.** Brainstorm research incorrectly claimed precedent — `grep -rn 'actions/cache@' .github/workflows/` returns zero matches. SHA resolved at plan time per pattern review HIGH-1. If the v4 tag is moved before implementation, re-resolve.
- **`needs.<matrix-job>.result` aggregates across legs.** GitHub Actions documented behavior: a matrix job's `.result` is `success` only if every leg succeeded. (Relevant for the deferred Item 3 e2e shard work, not for this PR.)
- **A plan whose `## User-Brand Impact` section is empty, contains placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6.** This plan's section is fully populated and carried verbatim from spec; threshold is `single-user incident`.
- **Branch-protection rename trap.** The synthetic aggregator job MUST be named exactly `test`. Any drift orphans the required check on ruleset 14145388. CI lint check (`lint-bot-statuses` job) does NOT catch this; the only mechanical check is `gh api repos/.../rulesets/14145388` post-merge (AC12).
- **`apps/web-platform` is currently a single `run_suite` invocation that runs 25 .test.ts files in one bun process.** A′ doesn't split this — it's the dominant cost in the bun shard. If Phase 0 wall-clock reveals `apps/web-platform` alone >100s, the stretch <100s target requires the Deferred-Items Item 2 pivot (suite-internal directory split). If Phase 0 spawn-count reveals clone(2) >130, Item 2 fires as a pre-Phase-1b BLOCKER and folds into this PR.
- **`EPOCHREALTIME` is bash 5.0+.** The script's existing shebang is `#!/usr/bin/env bash`. CI runs ubuntu-latest (bash 5.x). Local macOS users on the default `/bin/bash` (3.2.x) will see `EPOCHREALTIME` as empty string and the elapsed-ms math will compute `0`. Document in script header.

## Deferred Items (follow-up issues to be filed)

The following are explicitly out of scope and MUST have a tracking issue filed BEFORE this PR merges. Each issue links back to #3680.

1. **Bun version probe** — separate exploratory PR that bumps `.bun-version` to the latest 1.3.x patch and runs `bun test test/ apps/ plugins/` (directory discovery, the original FPE-trigger pattern) to see if the FPE class still fires in 2026. If gone, Approach D (in-process `--max-pool-size`) unlocks for future use. **Tracking issue:** to be created at plan-implementation start, milestone `Post-MVP / Later`, labels: `chore`, `domain/engineering`, `priority/p3-low` (labels verified to exist via `gh label list`). Re-evaluation criteria: trigger a fresh probe after every minor-version Bun bump.

2. **Pivot: `apps/web-platform/` suite-internal split** — splits `apps/web-platform/test/` into sub-directories (`auth/`, `kb/`, `sandbox/`, ...) and updates `test-all.sh` to call each as its own `run_suite` line. This expands the bun-side to N sub-suites and lets the matrix sharding bin-pack more aggressively. Two trigger conditions: (a) Phase 0 spawn-count probe reports `apps/web-platform` clone(2) count >130 — fires as a **pre-Phase-1b BLOCKER**, fold into this PR; (b) Phase 2 validation shows `test` aggregator >130s on ≥5 of 10 runs — fires as a fix-on-same-PR follow-up commit. **Tracking issue:** to be created at plan-implementation start, milestone `Post-MVP / Later`, labels: `chore`, `domain/engineering`, `priority/p3-low`.

3. **E2E job sharding (`--shard=2`)** — separate PR that adds a 2-way Playwright `--shard` matrix to the `e2e` job + synthetic `e2e` aggregator, mirroring the test-job pattern from this PR. The brainstorm originally bundled it; plan review (code-simplicity) flagged independent blast radius. Expected savings: 111s → ~65s slow-side. **Tracking issue:** to be created at plan-implementation start, milestone `Post-MVP / Later`, labels: `chore`, `domain/engineering`, `priority/p3-low`. Re-evaluation criteria: ship after the test-job pattern proves stable in production (≥1 week post-merge with no regressions).

All three deferral issues are created with `gh issue create` during Phase 1b implementation (commit 3) and linked from PR #3672's "Out of scope" section. Each title prefix `ci:` per conventional-commit style.

## Alternatives Considered

| Approach | Decision | Rejection rationale |
|---|---|---|
| **A indexed N-way matrix sharding** | Rejected for v1 | More setup overhead, shard-list generator must re-use `test-all.sh` discovery, marginal savings over A′ given the natural bun-vs-bash cleavage. Revisit only if Phase 0 reveals imbalance >2:1. |
| **B in-script `xargs -P` parallelization** | Rejected | Three confirmed sharp edges on this codebase: `process.env` leak class (`workspace.test.ts:2-3`), `_site/` race, `:health.test.ts:23` port binding. Single-runner OOM risk per FPE learning's 1.1 GB pre-crash spike. |
| **C trim slowest suite** | Rejected as primary; deferred as complement | Bounded ceiling; only useful as Item 2 pivot if A′ underperforms. |
| **D `bun test --max-pool-size`** | Rejected | Directly re-creates the FPE spawn-pressure pattern the sequential runner was built to mitigate. |
| **GitHub-hosted larger runner** (`ubuntu-latest-4-cores`) | Rejected | Paid; shifts cost without changing the serial-per-suite bottleneck. |
| **Touched-file-aware test selection** | Rejected | Violates orphan-suite invariant (PR #3512/#3533) without complex preservation logic. |
| **Ruleset 14145388 edit (rename required context)** | Rejected | Synthetic aggregator strategy makes this unnecessary AND keeps the change reversible. Editing the ruleset requires admin scope and leaves drift if CI is later reverted. |
| **Bun version bump bundled with matrix split** | Rejected | Would mask which change caused any regression. Probe lives in separate follow-up PR (Deferred Items Item 1). |
| **E2E `--shard=2` bundled with this PR** | Deferred | Plan review (code-simplicity) flagged independent blast radius. Ships as Deferred Item 3 follow-up PR after the test-job pattern proves stable. |
| **5-run validation phase** | Rejected | Architecture review P2-2 math: 1-in-10 flake passes 5/5 ~59%. Bumped to 10 runs. |
| **Edit ruleset 14145388 to require `test-bun`+`test-bash` directly** | Rejected | Simplicity reviewer offered this as an alternative to the aggregator. Rejected: ruleset edits require admin scope and out-of-band coordination — the aggregator keeps the change self-contained in one PR (corrected framing per simplicity review; the prior "drift risk" framing was weaker). |

## Research Insights

- **`scripts/test-all.sh` topology** (`scripts/test-all.sh:34-46`): 7 named `run_suite` calls + 1 glob loop over `plugins/soleur/test/*.test.sh`. Total 29 suites currently (7 bun + 22 bash).
- **FPE constraint** (`knowledge-base/project/learnings/2026-03-20-bun-fpe-spawn-count-sensitivity.md`): Bun 1.3.5 SIGFPE at ~130+ subprocess spawns in one bun-test process. Mitigation: pin `.bun-version` to 1.3.11 AND keep per-suite isolation via sequential `test-all.sh`. Both mitigations remain load-bearing.
- **Cross-suite shared state** (`apps/web-platform/test/workspace.test.ts:2-3`): module-level `process.env.WORKSPACES_ROOT` write with no `afterEach` restore. Safe under current sequential isolation, broken under shared-process parallelism.
- **`_site/` rebuilders** (`plugins/soleur/test/seo-aeo-drift-guard.test.ts` builds, `scripts/validate-blog-links.sh` reads): must co-locate. FR4 enforces.
- **Synthetic-status precedent** (`knowledge-base/project/learnings/2026-03-20-github-required-checks-skip-ci-synthetic-status.md`): documents the recovery pattern if `if: always()` + `needs.<job>.result` aggregator design fails — fall back to `gh api repos/$REPO/statuses/$SHA` posting.
- **Fail-open trap** (`knowledge-base/project/learnings/2026-03-19-ci-squash-fallback-bypasses-merge-gates.md`): `gh pr merge --auto || gh pr merge --squash` is fail-open. Same principle applies to CI aggregators — no `||` fallback, no `continue-on-error: true` on aggregator steps.
- **Matrix precedent in repo** (`.github/workflows/infra-validation.yml:54-57` and `:122-125`): `strategy: matrix: directory: ${{ fromJSON(needs.detect-changes.outputs.directories) }}` + `fail-fast: false`. Pattern is well-trodden in this repo; new code follows it.
- **No `actions/cache` precedent in repo** (verified via `grep -rn 'actions/cache@' .github/workflows/`): zero matches. This PR introduces the pattern. Repo permits all actions (`gh api repos/.../actions/permissions/selected-actions` returns 409 "All actions allowed"), so no allowlist update needed.
- **e2e job currently runs in Playwright container** (`.github/workflows/ci.yml`, the `e2e` job): `mcr.microsoft.com/playwright:v1.58.2-jammy@sha256:...`. Out of scope for this PR; relevant when Deferred Item 3 lands.
- **Ruleset 14145388 contexts** (via `gh api repos/jikig-ai/soleur/rulesets/14145388`): `test`, `e2e`, `dependency-review`, `CodeQL` (integration 57789), `skill-security-scan PR gate`. Only `test` and `e2e` originate from this repo's `ci.yml`; the other three are externally configured. This PR touches `test` only; `e2e` remains satisfied by the existing single-job definition.
- **`actions/cache@v4.3.0` SHA resolved at plan time:** `0057852bfaa89a56745cba8c7296529d2fc39830` (via `gh api repos/actions/cache/git/refs/tags/v4 --jq .object.sha` on 2026-05-12).
- **`if: always() && needs.<job>.result == 'failure'` precedent** for fail-closed aggregator: `.github/workflows/scheduled-compound-promote.yml:291`. The plan adopts this exact idiom. 17+ other workflows use bare `if: always()` for diagnostic/cleanup steps; the conditional form on `needs.<job>.result` is what makes the aggregator load-bearing.
- **`scripts/*.sh` precedent for positional-arg mode selector:** `scripts/validate-blog-links.sh:10` (`SITE_DIR="${1:-}"`), `scripts/provision-plausible-goals.sh:59` (`local method="$1"`). Env-vars in `scripts/` are reserved for ambient context (`GH_TOKEN`, `REPO_ROOT`). The plan supports both forms (`bash scripts/test-all.sh bun` AND `TEST_GROUP=bun bash scripts/test-all.sh`); workflow uses positional for grep-ability.

## SpecFlow Analysis (skipped with rationale)

The Phase 3 SpecFlow Analyzer step is **skipped** for this plan. Rationale:

- The plan's flow surface is a CI workflow (YAML) + a single bash conditional (`if [[ "$TEST_GROUP" == "all" || "$TEST_GROUP" == "bun" ]]`). The conditional logic is shallow (3 enum values, one validation arm, no nested branches).
- The brainstorm Phase 0.5 covered flow gaps already — `_site/` race, env-leak, port-binding, FPE-class. No new flow surfaces emerge in this plan.
- The risk SpecFlow would catch (bash conditional edge case silently dropping a suite) is bounded by AC2-AC5 which mandate empirical verification of all four `TEST_GROUP` modes (all/bun/bash/invalid) and both invocation forms (positional + env).

If review-time concerns surface a flow gap, run `Task spec-flow-analyzer` inline and amend the plan.

## Plan Review Resolution

Plan review fired three reviewers (architecture-strategist, pattern-recognition-specialist, code-simplicity-reviewer — substituted from the default DHH/Kieran/simplicity triad because the plan domain is CI/bash/YAML, not Rails). Findings and disposition recorded here for the next review pass.

### Architecture P1 (blocker — applied)

- **P1-1 SKIPPED-shard fail-open** → AC10 + T14 added. `if: false` mutation proves aggregator fails closed.
- **P1-2 Intra-shard FPE re-trigger** → G5 + Phase 0 spawn-count probe + AC1 + Deferred-Items Item 2 trigger condition (a) added. If `apps/web-platform` clone(2) >130, Item 2 fires as pre-Phase-1b BLOCKER.

### Architecture P2 (should-fix — applied)

- **P2-1 Aggregator load-bearing sub-value** → inline comment in Phase 1b YAML naming cross-layer truing / drift-resilience / observability.
- **P2-2 5-run statistical thinness** → bumped to 10 runs (G1, G4, AC11, Phase 2).
- **P2-3 `validate-blog-links.sh` invariant in workflow only** → AC8 + script-header comment specified in Phase 1a.

### Architecture P3 (advisory — accepted)

- **P3-2 ADR for first `actions/cache` introduction** → SHA pin + Sharp Edges + Research Insights cite the pattern introduction. ADR creation accepted as advisory; not blocking. May be filed during /work as a side-effect.

### Pattern HIGH (applied)

- **HIGH-1 SHA pin at plan time** → `actions/cache@0057852bfaa89a56745cba8c7296529d2fc39830 # v4.3.0` resolved and embedded in Phase 1b. No `<SHA>` placeholder remains.

### Pattern MEDIUM (applied)

- **MEDIUM-2 Positional-arg + env dual form** → Phase 1a uses `TEST_GROUP="${TEST_GROUP:-${1:-all}}"`; workflow uses positional `bash scripts/test-all.sh bun` for grep-ability.
- **MEDIUM-3 `EPOCHREALTIME` instead of `date +%s%N`** → Phase 0 uses bash 5 builtin.

### Pattern LOW (applied)

- **LOW-4 `if: always()` precedent cited** → Sharp Edges + Research Insights name `.github/workflows/scheduled-compound-promote.yml:291`.
- **LOW-5 Job naming** → no change needed; conformant.
- **LOW-6 Composite-action duplication** → accepted as v1 debt; note in PR body.
- **LOW-7 Conditional shape refactor** → deferred; not preempted now.

### Code-Simplicity (mixed — applied where load-bearing-arguments supported the cut, rejected with rationale where defenses were dropped)

- **#1 Aggregator vs ruleset edit** → KEEP with reframed rationale (admin-scope coordination, not drift risk). Alternatives Considered updated.
- **#2 `actions/cache` step** → REJECT cut. Pattern HIGH-1 resolves the SHA-pin concern; ~10-20s saving for ~10 lines is net positive.
- **#3 `TEST_GROUP` env var** → REJECT cut entirely; ACCEPT pattern's dual-form compromise. Inlining suite list in workflow creates a new orphan-suite drift class (the very invariant `test-all.sh` exists to enforce, per PR #3512/#3533).
- **#4 Phase 0 instrumentation** → REJECT cut. Architecture P1-2 mandates spawn-count instrumentation — phase 0 is more, not less, load-bearing than the simplicity reviewer modeled.
- **#5 E2E sharding bundling** → APPLY cut. Move to Deferred Item 3.
- **#6 5-run validation cut to 3** → REJECT cut; architecture P2-2 says 10. Net change: 5 → 10.
- **#7 `requires_cpo_signoff: true`** → REJECT cut. Frontmatter flag is enforced by the brand-survival-threshold workflow gate; can't drop without raising threshold, which would lie about regulated-surface blast radius (CPO already cleared in brainstorm — gate is satisfied, not adding ceremony).

### Net change from initial plan

- Phase count: 4 → 3 (e2e Phase 2 deferred; old Phase 3 → Phase 2; old Phase 4 → Phase 3).
- Validation runs: 5 → 10.
- New ACs: AC10 (SKIPPED-shard mutation), AC1 augmented with spawn-count.
- New file edit: `scripts/validate-blog-links.sh` header.
- Deferred items: 2 → 3 (added e2e shard as Item 3).
- Approximate line-count change: net +60 (Phase 0 instrumentation grew by spawn-count probe; Phase 2 e2e deletion offset).

---

**End of plan.** Next: generate `tasks.md`, commit, push.
