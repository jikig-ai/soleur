---
title: "ops(ci): extend lint-bot-synthetic-completeness glob beyond scheduled-*.yml"
issue: 3548
branch: feat-one-shot-3548-lint-glob-extend
type: ops-tooling
classification: ci-lint
brand_survival_threshold: none
requires_cpo_signoff: false
created: 2026-05-11
labels: [domain/engineering, chore, deferred-scope-out, priority/p3-low]
ref: [#3542, #3543, #3546, #3583, #3586, #2719]
---

# ops(ci): extend lint-bot-synthetic-completeness glob beyond scheduled-*.yml (#3548)

## Enhancement Summary

**Deepened on:** 2026-05-11
**Sections enhanced:** Predicate definition, Risks, Verification

### Key Improvements (from deepen-pass verification)

1. **Predicate refined from "bare `check-runs`" to "`gh api .../check-runs` inside a `run:` block".** Live grep showed `rule-metrics-aggregate.yml` (line 4) and `scheduled-content-vendor-drift.yml` (line 45) contain bare `check-runs` substrings in their header-comment blocks. A naïve `grep -q check-runs` predicate would pull both composite-consumers into the linted set — the opposite of intent. Fixed in the predicate definition.
2. **Inline-pattern canonical form verified.** `scheduled-content-publisher.yml` lines 142-170 demonstrate the multi-line `gh api "repos/${{ github.repository }}/check-runs"` continuation; `scheduled-disk-io-24h-recheck.yml` lines 197-200 demonstrate the single-line form. A per-line scan inside the `run:` block matching both `gh api` AND `check-runs` on the same line is sufficient — multi-line continuations end at the line break and the next call repeats both tokens.
3. **`pr-auto-close-scanner.yml` confirmed safe.** Only `gh pr create` reference is in `#`-prefixed comments at file scope (lines 23-24), well outside the `run:` block at line 55. The existing `has_shell_pr_create` indentation walker correctly returns false for this file. An explicit "comment-only `gh pr create`" test fixture is added to Phase 1 to lock this in.
4. **Label `ci` removed from frontmatter.** `gh label list` showed no `ci` label exists in the repo (only compound labels like `ci/main-broken`, `ci/auth-broken`). Replaced with the existing `domain/engineering` + `chore` + `priority/p3-low` + `deferred-scope-out` set.
5. **Live PR/issue resolution.** All cited references (#3548 OPEN, #3542 CLOSED, #3543 MERGED, #3546 CLOSED, #3583 MERGED, #3586 MERGED, #2719 OPEN, #826 CLOSED, #842 CLOSED, #1014 MERGED, #1468 CLOSED) resolved live via `gh issue view` / `gh pr view`.
6. **AGENTS.md rule citations.** Plan body has zero `\b(hr|wg|cq|rf|pdr|cm)-` citations — no fabricated/retired-ID risk.

### New Considerations Discovered

- The `has_inline_check_runs_post` helper is small but load-bearing: a future bot workflow that copies `gh api ... check-runs` *outside* a `run:` block (e.g., a `prompt:` block describing what the agent should do) would be incorrectly flagged. Mitigated by reusing `has_shell_pr_create`'s indentation walk rather than a flat `grep`.
- The CI job already invokes the lint at `.github/workflows/ci.yml:25-27`. No CI wiring change required — the widened scope is transparent to the job invocation.

## Overview

`scripts/lint-bot-synthetic-completeness.sh` and `scripts/lint-bot-synthetic-statuses.sh` both hardcode `PATTERN="scheduled-*.yml"`. Any bot workflow whose filename does not start with `scheduled-` is invisible to the lint. Today, `rule-metrics-aggregate.yml` is the only non-`scheduled-*` bot PR-creator, and it is covered indirectly via the `bot-pr-with-synthetic-checks` composite action (its synthetics are gated by the action, not the workflow file). A future `monthly-*.yml`, `hourly-*.yml`, `weekly-*.yml`, or `release-*.yml` bot workflow that posts synthetics inline (not via the composite) would deadlock auto-merge silently — the lint would print "ok" and the bot PR would block on missing required checks.

This plan widens both lint scripts' enumeration to **content-based detection**: a workflow is in scope iff it contains a shell-level `gh pr create` (the existing `has_shell_pr_create` helper for `lint-bot-synthetic-completeness.sh`) AND posts synthetic check-runs via `gh api .../check-runs`. The composite-action consumers continue to be exempt (their composite call site does not match the inline synthetic-posting heuristic; coverage is provided by the action itself).

The change is small (~30 LOC across two scripts), purely additive in coverage, and has no production runtime impact. The test harness adds a sibling `.test.sh` file for `lint-bot-synthetic-completeness.sh` matching the existing `.test.sh` pattern.

## Research Reconciliation — Spec vs. Codebase

| Spec / issue claim | Codebase reality | Plan response |
|---|---|---|
| Issue body: "`rule-metrics-aggregate.yml` is the only current non-`scheduled-` prefixed bot workflow" | Verified: `grep -l "gh pr create" .github/workflows/*.yml \| grep -v "scheduled-"` returns `pr-auto-close-scanner.yml` only — and that file's only `gh pr create` reference is inside a comment block (line 23), not a real call. `rule-metrics-aggregate.yml` is the only real non-`scheduled-*` bot PR-creator. | Plan correct. `pr-auto-close-scanner.yml` is not bot-PR-creator and will be skipped by the new content-based heuristic (no `check-runs` post, no shell-level `gh pr create`). |
| Context hint: `rule-metrics-aggregate.yml` "is already covered by the composite action update from #3542" | Verified: `grep -l 'uses:.*bot-pr-with-synthetic-checks' .github/workflows/*.yml` returns 5 consumers including `rule-metrics-aggregate.yml`. Coverage is on the composite action surface (`CHECK_NAMES` array in `action.yml`). | The widened lint MUST continue to skip composite-action consumers. The heuristic relies on inline `gh api .../check-runs` to identify the synthetic-posting surface — composite consumers have no such inline call, so they fall through to the App-token / non-applicable bucket. Explicitly verify in tests. |
| Context hint: "skipping `skill-security-scan-pr-trailer.yml` which is real CI not bot" | Verified: `.github/workflows/skill-security-scan-pr-trailer.yml` exists and runs on `pull_request_target` (not a bot workflow). | Plan correct. `audit-bot-codeql-coverage.sh::enumerate_workflows()` already excludes it explicitly; the lint scripts can reuse the same logic. |
| Runbook (`lint-bot-statuses.md` line 32, post-#3583): "A future `monthly-*.yml`, `hourly-*.yml`, or one-off `release-*.yml` is invisible to the lint." | Verified verbatim. | Plan closes the gap the runbook flagged. After this PR lands, update the runbook to remove the "Is not" caveat and add the new content-based scope to "The as-built behavior." |
| `lint-bot-synthetic-completeness.sh` has a `has_shell_pr_create` helper that walks YAML indentation | Verified at lines 59-92. The helper is the load-bearing heuristic separating real PR-creators from claude-code-action `prompt:` mentions. | The widened lint reuses `has_shell_pr_create` and adds a sibling `has_inline_check_runs_post` predicate. Both predicates AND together. |
| `audit-bot-codeql-coverage.sh::enumerate_workflows()` uses a similar union of (a) composite-action consumers via `uses:` grep + (b) inline-pattern scheduled-* with `check-runs` + `name=test` | Verified at lines 70-93. | The widened lint is the **inline-pattern half** of this union (excludes composite consumers because they are covered by the action's synthetic-posting). Do NOT copy the composite-consumer enumeration — composite consumers are exempt from the lint. |
| Existing tests: only `plugins/soleur/test/lint-bot-synthetic-statuses.test.sh` exists | Verified: `lint-bot-synthetic-completeness.test.sh` does NOT exist. | Add new `lint-bot-synthetic-completeness.test.sh` covering existing behavior + new glob-widened behavior. Extend `lint-bot-synthetic-statuses.test.sh` for parity. |

## Open Code-Review Overlap

Ran the planned-file overlap check against open `code-review` issues:

```bash
gh issue list --label code-review --state open --json number,title,body --limit 200 > /tmp/open-review-issues.json
for path in scripts/lint-bot-synthetic-completeness.sh scripts/lint-bot-synthetic-statuses.sh plugins/soleur/test/lint-bot-synthetic-statuses.test.sh plugins/soleur/test/lint-bot-synthetic-completeness.test.sh knowledge-base/engineering/ops/runbooks/lint-bot-statuses.md; do
  jq -r --arg p "$path" '.[] | select(.body // "" | contains($p)) | "#\(.number): \(.title)"' /tmp/open-review-issues.json
done
```

**Result:** None. (#3548 itself is labeled `deferred-scope-out`, not `code-review`.)

## User-Brand Impact

**If this lands broken, the user experiences:** the next `scheduled-*.yml` author lands a workflow without synthetic check-runs; bot PR opens; required check `test` never posts; auto-merge stalls indefinitely; operator hits the lint-bot-statuses runbook on second occurrence (per #3546 re-evaluation gate). Internal-only — no end-user surface, no production data path.

**If this leaks, the user's data is exposed via:** N/A. This change touches only CI lint scripts on bot-authored PR-creation workflows; no user data, no auth flow, no secrets in scope.

**Brand-survival threshold:** none

**Reason for `threshold: none` on a CI lint:** This change widens a pre-merge scope; it does NOT add a regulated-data surface, change auth/billing/PII, or affect any production user surface. The lint scripts run only in CI on bot-workflow files in `.github/workflows/`. Sensitive-path regex defined in `plugins/soleur/skills/preflight/SKILL.md` Check 6 does not match `scripts/lint-bot-*` or `.github/workflows/scheduled-*.yml`.

## Hypotheses

(Not applicable — this is a definite known-scope tooling fix, not a debugging investigation.)

## Acceptance Criteria

### Pre-merge (PR)

- [x] `scripts/lint-bot-synthetic-completeness.sh` no longer references `PATTERN="scheduled-*.yml"`. Replaced with content-based enumeration over `.github/workflows/*.yml`.
- [x] New enumeration predicate: `(grep -q "gh pr create" "$file")` AND `has_shell_pr_create "$file"` AND `has_inline_check_runs_post "$file"` AND `[[ "$file" != *skill-security-scan-pr-trailer* ]]`.
- [x] `has_inline_check_runs_post` is a new helper that returns 0 iff the file contains a `gh api .../check-runs` invocation (regex: `gh api[^|]*check-runs`) inside a shell `run:` block — NOT a bare `check-runs` token in a YAML comment. Bare-token detection would false-positive on `rule-metrics-aggregate.yml` (header comment line 4 mentions "synthetic check-runs") and `scheduled-content-vendor-drift.yml` (header comment line 45 references the composite action's behavior), both of which are composite-consumers that must remain skipped. The helper SHOULD reuse `has_shell_pr_create`'s YAML-indentation walk; effectively, it walks `run:` blocks and returns 0 iff one of those blocks contains the literal substring `gh api` AND `check-runs` on the same line (multi-line `gh api ... check-runs` continuations use line-continuations `\`, so a per-line scan inside the `run:` block is sufficient — see `scheduled-content-publisher.yml` lines 142-170 for the canonical inline pattern). Verified by grep: only `scheduled-content-publisher.yml`, `scheduled-disk-io-24h-recheck.yml`, `scheduled-disk-io-7d-recheck.yml` have `gh api .../check-runs` inside their `run:` blocks today.
- [x] Composite-action consumers (`grep -l 'uses:.*bot-pr-with-synthetic-checks' .github/workflows/*.yml`) are excluded by the predicate (no inline `check-runs` post). Verified against current 5 consumers: `rule-metrics-aggregate.yml`, `scheduled-content-vendor-drift.yml`, `scheduled-skill-freshness.yml`, `scheduled-rule-prune.yml`, `scheduled-weekly-analytics.yml`.
- [x] `scripts/lint-bot-synthetic-statuses.sh` is widened analogously. Predicate: any `.github/workflows/*.yml` with `gh pr create` and excluding `skill-security-scan-pr-trailer.yml`. (Statuses lint is broader because `[skip ci]` in a commit message is dangerous regardless of synthetic-posting surface.)
- [x] Both scripts continue to honor `WORKFLOW_DIR` env override (used by the test harness).
- [x] No regression on existing lint scope. Running both scripts against `main`'s current `.github/workflows/` yields the same `ok`/`skip`/`FAIL` set as before (modulo the new ability to enumerate non-`scheduled-*` files, which on current main is zero additional files because `rule-metrics-aggregate.yml` is composite-consumer-only).
- [x] New file `plugins/soleur/test/lint-bot-synthetic-completeness.test.sh` exists and covers: (a) `scheduled-foo.yml` with full synthetics passes (regression), (b) `scheduled-foo.yml` missing a required check fails (regression), (c) `monthly-foo.yml` with full synthetics passes (new — non-scheduled prefix is now in scope), (d) `release-foo.yml` missing a required check fails (new), (e) `skill-security-scan-pr-trailer.yml` is excluded even when it contains `gh pr create` + `check-runs` (new), (f) composite-action-only consumer is excluded — fixture mimics the live shape: header comment mentioning "check-runs" + a `uses: ./.github/actions/bot-pr-with-synthetic-checks` step + no inline `gh api .../check-runs` in any `run:` block (locks in the bare-substring false-positive fix), (g) workflow with `gh pr create` in `prompt:` block only (App-token path) is skipped, (h) `pr-auto-close-scanner.yml`-shaped fixture: `gh pr create` only in `#` file-scope comments — must be skipped (locks in `has_shell_pr_create` correctness under widened glob).
- [x] `plugins/soleur/test/lint-bot-synthetic-statuses.test.sh` extended with at least one new test case covering a non-`scheduled-*` filename with `gh pr create` and `[skip ci]` — must fail. One case is sufficient because the statuses lint has no synthetic-posting complexity to fork on filename prefix.
- [x] Lint scripts and tests pass locally: `bash scripts/lint-bot-synthetic-completeness.sh && bash scripts/lint-bot-synthetic-statuses.sh && bash plugins/soleur/test/lint-bot-synthetic-completeness.test.sh && bash plugins/soleur/test/lint-bot-synthetic-statuses.test.sh` all exit 0.
- [x] `.github/workflows/ci.yml` `lint-bot-statuses` job continues to pass on the PR.
- [x] `knowledge-base/engineering/ops/runbooks/lint-bot-statuses.md` updated to drop the "Is not: A check on non-`scheduled-*.yml` workflows" caveat and update "The as-built behavior" to describe content-based detection.
- [x] PR body uses `Closes #3548` on its own line.

### Post-merge (operator)

- [x] Verify `ci.yml` runs green on `main` after merge (`gh run list --workflow=ci.yml --branch=main --limit=1`).
- [x] No post-merge operator action required — this is a pre-merge gate widening, not an apply-time change.

## Files to Edit

- `scripts/lint-bot-synthetic-completeness.sh` — replace `PATTERN="scheduled-*.yml"` glob with content-based enumeration; add `has_inline_check_runs_post` helper; thread `skill-security-scan-pr-trailer.yml` exclusion through the loop.
- `scripts/lint-bot-synthetic-statuses.sh` — replace `PATTERN="scheduled-*.yml"` glob with `.github/workflows/*.yml` walk + `skill-security-scan-pr-trailer.yml` exclusion. (Simpler than the completeness widening — no synthetic-posting heuristic needed.)
- `plugins/soleur/test/lint-bot-synthetic-statuses.test.sh` — add Test 8 covering a non-`scheduled-*` filename with `[skip ci]`. Add Test 9 confirming `skill-security-scan-pr-trailer.yml` is excluded.
- `knowledge-base/engineering/ops/runbooks/lint-bot-statuses.md` — update §"Is not" (drop the `scheduled-*.yml`-only caveat), §"The as-built behavior" (describe content-based detection), §"How to extend / Adding a new bot workflow" (drop the `scheduled-*` filename convention mention).

## Files to Create

- `plugins/soleur/test/lint-bot-synthetic-completeness.test.sh` — new bash test harness modeled on the sibling `lint-bot-synthetic-statuses.test.sh`. Sources `test-helpers.sh`, runs against `WORKFLOW_DIR` and `CONFIG_FILE` overrides (the lint script already supports both).

## Implementation Phases

### Phase 1 — Tests first (RED)

1. Create `plugins/soleur/test/lint-bot-synthetic-completeness.test.sh` with all 7 test cases enumerated in Acceptance Criteria. Each test sets up a tmp workflow dir, drops in fixture `.yml` files, writes a fixture `required-checks.txt` (or uses the real one), invokes the lint with `WORKFLOW_DIR=<tmp> CONFIG_FILE=<tmp-config>` env, and asserts exit code + grep-able output substrings.
2. Add Test 8 + Test 9 to `plugins/soleur/test/lint-bot-synthetic-statuses.test.sh`.
3. Run the test suites. They should fail because the lint scripts still glob only `scheduled-*.yml` — non-scheduled-prefixed fixtures will be silently skipped.

**Verification:** `bash plugins/soleur/test/lint-bot-synthetic-completeness.test.sh && bash plugins/soleur/test/lint-bot-synthetic-statuses.test.sh` both exit non-zero, with specific assertion failures pointing at the new monthly-/release-prefix cases.

### Phase 2 — Widen `lint-bot-synthetic-completeness.sh` (GREEN-1)

1. Replace `PATTERN="scheduled-*.yml"` with iteration over all `.github/workflows/*.yml`. The loop becomes:

    ```bash
    for file in "$WORKFLOW_DIR"/*.yml; do
      [[ -f "$file" ]] || continue
      [[ "$file" == *"skill-security-scan-pr-trailer"* ]] && continue
      grep -q "gh pr create" "$file" || continue
      # ... existing has_shell_pr_create + per-check grep logic ...
    done
    ```

2. The existing `has_shell_pr_create` already separates shell-`run:` from `prompt:` blocks — no new helper required for the App-token escape hatch (it stays load-bearing).
3. The existing per-required-check grep loop (lines 117-130) already handles the "missing synthetics" detection — it does NOT need to change. The content-based filter is purely at the enumeration boundary.
4. Update the "No scheduled workflows…" final-message string at line 148 to drop the word "scheduled" (e.g., "No bot workflows with shell-based PR creation found"). Cosmetic but operator-facing.

**Verification:** Re-run completeness test suite. All 7 cases pass.

### Phase 3 — Widen `lint-bot-synthetic-statuses.sh` (GREEN-2)

1. Replace `PATTERN="scheduled-*.yml"` with the same `.github/workflows/*.yml` walk + `skill-security-scan-pr-trailer` exclusion. The statuses lint logic itself stays simple (grep for `[skip ci]`).
2. Update the "No scheduled bot workflow(s)" final-message string at line 42.

**Verification:** Re-run statuses test suite. All Test 8 and Test 9 pass.

### Phase 4 — Full local lint sweep against `main`

1. Run both scripts against the live `.github/workflows/` to confirm zero regression on real workflows:

    ```bash
    bash scripts/lint-bot-synthetic-completeness.sh
    bash scripts/lint-bot-synthetic-statuses.sh
    ```

2. Expected: same `ok`/`skip` output as pre-change (no new "FAIL" introduced). The 3 inline-pattern workflows (`scheduled-content-publisher.yml`, `scheduled-disk-io-24h-recheck.yml`, `scheduled-disk-io-7d-recheck.yml`) continue to be the only "checked" entries.

### Phase 5 — Runbook update

1. Edit `knowledge-base/engineering/ops/runbooks/lint-bot-statuses.md`:
   - §"Is not" — delete the third bullet ("A check on non-`scheduled-*.yml` workflows…").
   - §"The as-built behavior / `lint-bot-synthetic-completeness.sh`" — change "Greps each `.github/workflows/scheduled-*.yml` file for `gh pr create`" to "Walks `.github/workflows/*.yml`, excludes `skill-security-scan-pr-trailer.yml`, and applies the content-based predicate (shell `gh pr create` AND inline `gh api .../check-runs`)."
   - §"How to extend / Adding a new bot workflow" — drop the "Create `.github/workflows/scheduled-<feature>.yml`" filename hint; replace with "Create `.github/workflows/<feature>.yml` (any filename other than `skill-security-scan-pr-trailer.yml`)."
   - Bump `last_updated:` to today.
2. The runbook's existing operator-debug commands (Phase 0.5) and `re-evaluation` gate remain unchanged.

### Phase 6 — Compound + ship

1. Run `/soleur:compound` to capture any learnings (likely: "Content-based workflow enumeration is more durable than filename-prefix conventions").
2. Push branch, ensure CI green, mark PR ready, queue auto-merge.

## Test Strategy

- **Framework:** plain `bash` test files in `plugins/soleur/test/*.test.sh`. The repo's existing convention (verified via `ls plugins/soleur/test/`); no new dependency.
- **Helpers:** source `plugins/soleur/test/test-helpers.sh` for `assert_eq`, `assert_contains`. Already present.
- **Fixture strategy:** `mktemp -d` per test, drop fixture `.yml` files into `<tmp>/.github/workflows/`, invoke the lint with `WORKFLOW_DIR=<tmp>` env. Use a fixture `required-checks.txt` (write 3-4 names — `test`, `dependency-review`, `cla-check`) via `CONFIG_FILE=<tmp-config>` env to keep tests deterministic across real-config drift. Both env vars are already supported by the lint scripts.
- **No CI wiring change required:** `lint-bot-statuses` job in `.github/workflows/ci.yml` already invokes both scripts, and CI uses `bash` (no framework install).

## Risks

- **`grep -q "gh pr create"` false-positives on comments — VERIFIED SAFE.** `pr-auto-close-scanner.yml` has `gh pr create` in comments at lines 23-24, but file-scope comments precede `jobs:` (line 40) and `run:` (line 55). `has_shell_pr_create` enters the `in_run=true` state only when it matches `^([[:space:]]*)run:` — file-scope `#` lines do not trigger that state, so the literal-token check at line 85 of the script is never reached for these comments. Locked in by an explicit "comment-only `gh pr create`" test fixture in Phase 1 Test (h).
- **`grep -q check-runs` false-positives on header comments — FIXED in predicate refinement.** `rule-metrics-aggregate.yml` (line 4: "synthetic check-runs satisfy") and `scheduled-content-vendor-drift.yml` (line 45: "posts synthetic check-runs") contain bare `check-runs` substrings in header comments. The widened predicate uses `gh api[^|]*check-runs` (or equivalent same-line co-occurrence inside a `run:` block), NOT a flat `check-runs` grep. Test fixture (f) in Phase 1 (`composite-action-only consumer is excluded`) locks this in.
- **Composite-action consumer drift.** If a future PR migrates a composite-action consumer to inline synthetic-posting, the widened lint will catch it (correctly — that's the design). Conversely, if an inline-pattern bot workflow is migrated to the composite action and the inline `gh api .../check-runs` is removed, the lint will silently stop enforcing that workflow (correctly — coverage moves to the composite action). No special handling needed.
- **Cosmetic drift in error messages.** Existing "scheduled workflows" wording in error/summary strings will be updated. Operators searching the codebase for "scheduled bot workflow" may need to find the new phrasing. Mitigated by the runbook update in Phase 5.
- **`skill-security-scan-pr-trailer.yml` exclusion is hardcoded.** Same shape as `audit-bot-codeql-coverage.sh::enumerate_workflows()` line 85. If a future workflow has the same "real CI not bot" shape, the operator must add it to the exclusion list in both lint scripts. Plan acknowledges this; no allowlist file is introduced (single-entry hardcoding is fine for now).
- **CLI-form verification.** The plan does not introduce new CLI invocations to operator-facing docs. The runbook's existing `bash scripts/lint-*.sh` and `gh run list` invocations are unchanged.

## Sharp Edges

- **Plan numerics:** N/A — no aggregate numeric target in AC.
- **External-state claims:** AC asserts `bash` script behavior and runbook content, not Doppler/Cloudflare/Supabase state. No API verification needed.
- **AC verification grep scope:** the runbook edit drops a single caveat sentence; no class-of-bug retirement-sweep is in scope.
- **A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6.** This plan's threshold is `none` with a one-sentence reason (CI lint scope, no production surface) — see §User-Brand Impact above.
- **Defense-relaxation:** N/A — this plan *widens* a defense, does not relax one. Original defense (block `[skip ci]`, require synthetics) is preserved; surface widens from `scheduled-*` to `*`.
- **Phase order:** Tests first (Phase 1), then implementation (Phase 2-3), then verification (Phase 4), then docs (Phase 5). Standard TDD order; no contract change.
- **`yamllint`/`bash -n` traps:** N/A — Phase 1 tests run `bash plugins/soleur/test/*.test.sh`, not `bash -n` on YAML.

## Domain Review

**Domains relevant:** Engineering (CTO)

### Engineering (CTO)

**Status:** carry-forward from issue framing — no fresh assessment needed.
**Assessment:** This is a CI-lint scope-widening on an internal tooling surface. No architectural decisions in scope, no new dependencies, no external integrations. The change reuses an established pattern (`audit-bot-codeql-coverage.sh::enumerate_workflows`) for content-based workflow detection. Risk surface is bounded to the lint scripts and their tests. CTO sign-off implicit via issue framing in #3548 (deferral D5 of R15 follow-up).

No Product, Legal, Marketing, Operations, Finance, Sales, or Support implications. This is internal tooling that runs only in CI on bot-workflow files.

## SpecFlow Notes

- **Edge case enumerated:** `pr-auto-close-scanner.yml` (non-scheduled, comment-only `gh pr create`) — covered by the Risks section + an explicit test fixture.
- **Edge case enumerated:** composite-action consumers — explicitly excluded by the inline `check-runs` predicate.
- **Edge case enumerated:** `skill-security-scan-pr-trailer.yml` — explicitly excluded by name.
- **Edge case enumerated:** future inline-pattern bot workflow with non-`scheduled-*` prefix (e.g., `monthly-roi-audit.yml`) — caught by the widened lint. This is the primary win.

## Refs

- #3548 (this issue, deferred-scope-out from #3542's D5)
- #3542 (R15 mitigation parent — added `skill-security-scan PR gate` required check)
- #3543 (composite-action update that landed `rule-metrics-aggregate.yml` coverage)
- #3546 (lint-bot-statuses runbook PR)
- #3583 (#3546 merge PR)
- #3586 (CI wiring confirmation — `lint-bot-statuses` job in `ci.yml`)
- #2719 (R15 origin)
- #826, #842, #1014, #1468 (lint-bot-synthetics history)
