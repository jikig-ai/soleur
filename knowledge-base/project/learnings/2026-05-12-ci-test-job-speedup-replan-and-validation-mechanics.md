---
date: 2026-05-12
issues: [3680]
prs: [3672, 3692, 3693, 3694]
tags: [ci, github-actions, vitest, bun, matrix-sharding, synthetic-aggregator, validation, replan]
category: best-practices
---

# CI test-job speedup — replan mechanics, synthetic aggregator, and 10-run validation pitfalls

## Problem

PR #3672 / issue #3680: cut the `test` job in `.github/workflows/ci.yml` from ~199s baseline to <130s without touching branch-protection ruleset 14145388. The plan was halted at /work Phase 1 because v1 had **five precondition-drift findings** that invalidated its Phase 0 gate, Phase 1b YAML, and TEST_GROUP enum:

1. Suite count "29" → actual **38** (11 pre-suite bash/python tests dropped under the 2-way `bun + bash` split).
2. `apps/telegram-bridge` referenced repeatedly — directory does not exist.
3. `apps/web-platform` claimed as Bun runtime — actually Vitest 3.x.
4. Cache key `bun.lockb` (binary, doesn't exist) — repo uses `bun.lock` (text); `hashFiles('bun.lockb')` silently hashes zero bytes.
5. 2-way enum `{bun, bash, all}` orphans 11 pre-suite tests under no-args invocation.

## Solution

Three-phase implementation:

### Phase 0 — Measurement
Instrumented `scripts/test-all.sh` `run_suite()` with `EPOCHREALTIME` per-suite timing. Computed `elapsed_ms` via integer math on `seconds.microseconds` (avoids `date +%N` macOS gap). Output to `${TEST_TIMING_LOG:-/dev/null}` so local runs append, default no-write.

Captured baseline: webplat=41.7s, bun=44.6s, scripts=33.2s (local sequential, total 119.4s). `max/min=1.34` → 3-way split confirmed (no 2-way collapse).

### Phase 1a — TEST_GROUP selector
4-value enum (`all` | `webplat` | `bun` | `scripts`) accepted via positional `$1` OR `TEST_GROUP` env (env wins). Invalid → exit 2 with stderr usage. `all` default preserves byte-identical no-args behavior.

```bash
TEST_GROUP="${TEST_GROUP:-${1:-all}}"
case "$TEST_GROUP" in
  all|webplat|bun|scripts) ;;
  *) echo "ERROR: ..." >&2; exit 2 ;;
esac
want_scripts() { [[ "$TEST_GROUP" == "all" || "$TEST_GROUP" == "scripts" ]]; }
# ...
if want_scripts; then run_suite ... fi
```

### Phase 1b — Workflow split + synthetic aggregator
Replaced single `test:` job with `test-webplat` / `test-bun` / `test-scripts` parallel jobs + synthetic `test:` aggregator the ruleset already requires by name:

```yaml
test:
  needs: [test-webplat, test-bun, test-scripts]
  if: always()  # load-bearing — without it, default semantics produce
                # `skipped` aggregator on any shard failure, and some
                # branch-protection configs treat skipped as success
  steps:
    - env:
        WEBPLAT_RESULT: ${{ needs.test-webplat.result }}
        BUN_RESULT: ${{ needs.test-bun.result }}
        SCRIPTS_RESULT: ${{ needs.test-scripts.result }}
      run: |
        for entry in "test-webplat:$WEBPLAT_RESULT" "test-bun:$BUN_RESULT" "test-scripts:$SCRIPTS_RESULT"; do
          shard="${entry%%:*}"; result="${entry#*:}"
          [[ "$result" != "success" ]] && { echo "$shard: $result" >&2; fail=1; }
        done
        [[ ${fail:-0} -ne 0 ]] && exit 1 || true
```

`test-scripts` runs with NO setup-bun (verified zero `.test.sh` files invoke bun); `test-webplat` and `test-bun` use SHA-pinned `actions/cache@0057852bf…` (v4.3.0, first cache use in repo) keyed on `bun.lock` (text).

### Phase 2 — T14 mutation tests + 10-run validation
Three sub-mutations (`if: false` on each shard) confirmed aggregator fails closed for each `skipped` shard (NOT `skipped` itself); `gh pr checks 3672` showed `test` failing.

Initial 10-run validation under single-shard webplat: **0/10 <130s** (webplat dominated at 134-149s). Per plan trigger condition for Item 2, pivoted to vitest `--shard=K/2` matrix with `tsc` gated to shard 1 via `strategy.job-index == 0`. Final: **7/10 <130s, 10/10 green, median 117.5s, min 99s** (~41% reduction from 199s baseline).

## Key Insights

### 1. Plan replan as a first-class workflow phase
v1 plan was committed by `/soleur:plan` after brainstorming, but `/work` Phase 1's "verify preconditions" caught 5 fabrications. The right move is to **re-write the plan in place** (`status: superseded` on the v1 commit, fresh v2 commit) rather than amending or patching — gives reviewers a clear diff between v1 and v2 framings. **`supersedes:` frontmatter pointer** in the plan + a top-of-doc banner in spec.md and brainstorm.md preserves traceability of what was corrected and why.

### 2. Synthetic aggregator with `if: always()` is load-bearing
The default GHA `needs:` semantics produce a `skipped` aggregator when any dependency fails. Some branch-protection configurations treat `skipped` as success — silent fail-open. `if: always()` + explicit per-shard `result != success` check is the canonical fail-closed pattern (precedent: `scheduled-compound-promote.yml`). **T14 mutation tests** (push `if: false` on each shard in turn) prove this property pre-merge; without them, the design is a hope.

### 3. The aggregator's name is the merge-gate contract
Ruleset 14145388 references the `test` required check by name. A rename in `ci.yml` would orphan the ruleset's required check and break every PR merge. Inline comment naming the ruleset ID is the human-discipline mitigation; mechanical guard (lint that greps for `^  test:$`) is meaningful defense-in-depth but adds new lint infrastructure for a low-rate failure mode — judgment call.

### 4. Empty validation commits + GHA push dedup
Pushing 10 commits in one push triggers ONE CI run (only the tip commit). Pushing 10 commits separately with NO delay between them gets ~3 CI runs (GHA dedupes rapid push events). For per-commit validation:
- **Push each commit individually**
- **Sleep ≥20-25s between pushes** to let GHA register the synchronize event
- **Poll for a NEW `headSha`** in the run list, not blindly `--limit 1` (the prior run may still be the newest visible)

### 5. Cost-of-filing vs fix-inline triage for review findings
Multi-agent review surfaced 16 findings (0 P1, 7 P2, 9 P3). All were under the cost-of-filing gate (≤30 lines, ≤2 files) — fixed inline as 4 `review:` commits rather than filing as scope-out issues. The rule "fix-inline default unless ≥3 files genuinely unrelated to core change" prevented this PR from generating more issues than it closed.

### 6. Vitest `--shard=K/N` for vitest matrix sharding
Native vitest support; forwards via `npm run test:ci -- --shard=K/N`. File-hash bucketing (not duration-weighted), so shard imbalance is possible — observed one outlier run with shard-2 at 136s vs typical 60-75s. Acceptable variance; mitigate by going to 3-way only if measurements demand it.

### 7. tsc gated to a single shard via `strategy.job-index == 0`
Type-checking is whole-program and shard-independent — running it once across the matrix saves ~18s per redundant shard. Use `strategy.job-index == 0` (matrix-resize-safe) rather than `matrix.shard == '1/2'` (silently stops if the matrix is renumbered to 1/3, 2/3, 3/3).

### 8. Bash script must work without bun on PATH
The `test-scripts` shard intentionally omits `setup-bun`. The version-check block at the top of `test-all.sh` invokes `bun --version` unconditionally before TEST_GROUP is parsed → exit 127. **Always gate environment-dependent guards with `command -v <tool>`** so scripts run cleanly on any runner profile. Test locally with the runtime stripped from PATH.

## Session Errors

1. **`test-scripts` CI shard failed exit 127 on first push** — `bun --version` invoked unconditionally before `TEST_GROUP` parse. Recovery: `command -v bun` guard on the version-check block. **Prevention:** when adding a CI shard that intentionally omits a runtime, locally `PATH=… (no bun)` smoke-test the script before pushing.

2. **GHA push-dedup collapsed 9 rapid pushes to 3 CI runs.** Recovery: serial-push-v2.sh with `sleep 25` between pushes. **Prevention:** ≥20-25s between consecutive pushes when each push must trigger its own CI run.

3. **`gh run list --limit 1` returned the OLD run before GHA registered the new push.** Caused duplicate run IDs in the serial-push.sh batch. Recovery: longer sleep before listing. **Prevention:** poll for a new headSha (vs blindly grabbing `--limit 1`).

4. **Batched-commit push (10 commits, 1 push) triggered only 1 CI run.** Intermediate commits never got CI events. Recovery: re-push each commit separately. **Prevention:** for per-commit CI validation, one push per commit.

5. **cwd drift after `cd apps/web-platform` in Bash tool** — subsequent relative-path commands failed. **Prevention:** absolute paths in Bash tool calls; never rely on persisted cwd across calls.

6. **First Item-1 10-run validation: 0/10 <130s.** Webplat dominated at 134-149s. Not strictly an error — triggered the plan-mandated Item 2 pivot. **Prevention:** plan should make the pivot trigger ANTICIPATED rather than reactive (estimate worst-shard wall-clock from local timings × CI-overhead multiplier; if estimate > target, recommend Item 2 fix-on-PR from the start).

7. **Plan/spec/brainstorm cited `PR #3512/#3533`** as provenance for the orphan-suite invariant — #3512 is unrelated PR, #3533 is the issue (PR is #3534). Caught by git-history-analyzer review. **Prevention:** when plan cites a PR number for provenance, `gh pr view <N> --json title` before committing the citation to docs.

8. **spec.md + brainstorm.md frozen at v1 design after replan.** FR2/FR3/TR2 still described 2-way split. Caught by data-integrity-guardian. **Prevention:** when `/work` re-plans mid-stream, update OR mark superseded both spec.md and brainstorm.md before proceeding to Phase 2, not just plan.md.

9. **PreToolUse security hook fired advisory-only on first ci.yml Edit** — second attempt succeeded with no content change. **Prevention:** hook is fail-open by design (advisory). Document this so future edits don't waste cycles diagnosing.

10. **`critical-css-gate` Docker pull failed on MCR during validation run #2** — transient registry block (`The request is blocked`). Unrelated to the PR. **Prevention:** GHA infrastructure flakes are non-actionable; document as transient and proceed with remaining green runs.

## Related

- Plan: `knowledge-base/project/plans/2026-05-12-feat-ci-test-job-speedup-plan.md`
- Spec: `knowledge-base/project/specs/feat-ci-test-job-speedup/spec.md` (superseded by replan)
- Brainstorm: `knowledge-base/project/brainstorms/2026-05-12-ci-test-job-speedup-brainstorm.md` (superseded by replan)
- FPE class: `knowledge-base/project/learnings/2026-03-20-bun-fpe-spawn-count-sensitivity.md`
- Orphan-suite invariant: `knowledge-base/project/learnings/2026-05-11-test-all-exit-gate-self-validated-on-creating-pr.md` (issue #3533, PR #3534)
- Fail-closed precedent: `.github/workflows/scheduled-compound-promote.yml`
- Squash-fallback hazard: `knowledge-base/project/learnings/2026-03-19-ci-squash-fallback-bypasses-merge-gates.md`
- Follow-up issues: #3692 (Bun version probe), #3693 (apps/web-platform internal split), #3694 (e2e --shard=2)
