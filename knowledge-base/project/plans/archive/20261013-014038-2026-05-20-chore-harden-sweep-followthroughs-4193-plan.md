---
title: "Harden scripts/sweep-followthroughs.sh — realpath canonicalization + first-directive-wins + anchored awk parser"
issue: 4193
branch: feat-one-shot-harden-sweep-followthroughs-4193
date: 2026-05-20
type: chore
lane: single-domain
requires_cpo_signoff: false
deepened: 2026-05-20
---

# Plan: Harden `scripts/sweep-followthroughs.sh` (#4193)

## Enhancement Summary

**Deepened on:** 2026-05-20
**Sections enhanced:** Overview, Research Reconciliation, Files to Edit, Implementation Phases, Acceptance Criteria, Risks, Roadmap.

### Key Improvements

1. **Corrected awk restructure logic** for Gap 2 first-directive-wins. The initial snippet had an awk evaluation-order bug (the `in_dir` body block's `gsub(/-->/, "")` ran BEFORE the `/-->/` end-match block, stripping the marker from `$0` and leaving `in_dir` permanently=1 across multiple directives). Empirically verified at deepen-pass time via `/tmp/awk-v2-debug.awk` — initial snippet emitted BOTH directives. New v3 form uses an explicit `closing` flag set BEFORE the gsub block.

2. **Discovered third copy of the parser** at `plugins/soleur/test/ship-followthrough-directive.test.sh:30-38` (shipped by PR #4191 / issue #4190). Assertion 5 in that test diff-checks its PARSER copy against the sweeper's `parse_directive()` — without updating this test's PARSER in lockstep, the modified sweeper would fail its own pre-existing test on the first PR push. Folded into Files to Edit.

3. **Corrected TR9 attribution.** Initial plan claimed the bash sweeper would be migrated to Inngest by TR9-PR2 (#3985/#4062). Verified live: PR #4062 (MERGED) migrated a DIFFERENT workflow (`scheduled-follow-through.yml`, a Claude-agent-driven cron); umbrella issue #3948 explicitly RECLASSIFIED the bash sweeper as group-(a)/(b) infra-cron that **stays on GHA permanently** (no LLM call, ADR-033 substrate doesn't fit). This hardening is therefore the permanent state of the surface, not a transitional fix.

4. **Verified all line-number citations** (sweeper L21, L36-48, L62-68, L79-85, L87, L200-205, L210; preflight SKILL.md:427; ship SKILL.md:1313, L1319) against current `main` state in the worktree.

5. **Verified all rule-ID citations** active in `AGENTS.md` + sidecars (none retired, none fabricated).

6. **Empirically validated** all four test scenarios (T1/T2/T3/T4) against the proposed v3 awk + the proposed bash diff, confirming the test design is implementable.

### New Considerations Discovered

- The parser now has THREE copies (sweeper authoritative, SKILL.md documentation, test PARSER fixture). The Phase 5 verifier must diff ALL THREE; the contract-mirror sharp edge now extends to three files, not two.
- The bash sweeper is permanent infrastructure (not a TR9 transition target), so investment in tests and observability has indefinite payback rather than 4-12 week half-life.
- The existing `plugins/soleur/test/ship-followthrough-directive.test.sh` provides PARSER-equivalence coverage; the new `scripts/sweep-followthroughs.test.sh` provides BEHAVIOR coverage. Both ship in the same PR.

Multi-agent review of PR #4191 surfaced three pre-existing security gaps in
`scripts/sweep-followthroughs.sh`. None are introduced by #4191 — the file is
not touched on that branch — but the sweeper is security-sensitive enough
(runs arbitrary referenced scripts on `ubuntu-24.04` with `issues:write`,
fans out to every open `follow-through` issue daily at 18:00 UTC) that the
hardening warrants its own focused PR.

This plan delivers three surgical changes to the sweeper, mirrors the
realpath canonicalization into the `/ship` Phase 7 Step 3.5.E precondition
gate (so the agent-time self-check matches sweep-time enforcement), and
adds a `scripts/sweep-followthroughs.test.sh` covering the three failure
modes via the existing `*.test.sh` convention.

## Overview

| Gap | Severity | Location | Fix | LOC |
|---|---|---|---|---|
| 1 — Path allowlist accepts `..` traversal | HIGH | `scripts/sweep-followthroughs.sh:79-85` | `realpath -m --relative-to=$PWD` canonicalize before the case-glob, reject if canonical path doesn't start with `scripts/followthroughs/` | ~5 |
| 2 — Multi-directive last-wins contradicts comment | MEDIUM | `scripts/sweep-followthroughs.sh:36-48` (awk) + `:62-68` (bash loop) | awk emits only the FIRST directive's fields; bash logs a warning when a second `<!-- soleur:followthrough` appears in the body | ~5 |
| 3 — Fenced markdown blocks parse as directives | LOW | `scripts/sweep-followthroughs.sh:38` (awk range start) | anchor the start-of-range regex to column 1: `/^<!-- *soleur:followthrough/` | 1 |

Cross-cutting:

- **Contract mirror.** `/ship` Phase 7 Step 3.5.E already documents the canonical realpath check (`plugins/soleur/skills/ship/SKILL.md:1313-1345`) AND embeds the awk parser verbatim. The awk-snippet in Step 3.5.E must be updated in lockstep with the sweeper awk so the agent-time precondition matches sweep-time enforcement. **Two-grep verification at /work time** confirms no drift.
- **Tests-first.** No existing tests cover this script. Three `*.test.sh` cases ship in the same PR — written RED before the fixes per `cq-write-failing-tests-before` (core).
- **No-runtime-behavior change for legitimate inputs.** Every existing canonical issue body emitted by `/ship` Phase 7 Step 3.5 (column-1 directive, single occurrence per body, no `..` segments) continues to pass through all three gates with identical parsed output.

## Research Reconciliation — Spec vs. Codebase

| Issue body claim | Codebase reality (verified at plan-write time) | Plan response |
|---|---|---|
| "PR #4191 does not touch `scripts/sweep-followthroughs.sh`" | `git diff origin/main...HEAD -- scripts/sweep-followthroughs.sh` is empty on `feat-one-shot-harden-sweep-followthroughs-4193`. PR #4191 (commit `7ed6704b`, merged) rewrote `/ship` Phase 7 Step 3.5 prose only, mirroring realpath into Step 3.5.E without touching the sweeper. | Honor the framing — pre-existing gaps, dedicated PR. |
| "Fix sketch (~5 lines): `canon=$(realpath -m --relative-to="$PWD" "$script" 2>/dev/null)`" | `realpath` is uutils coreutils 0.8.0 on the ubuntu-24.04 runner. `realpath -m --relative-to="$PWD" "scripts/followthroughs/../../bin/sh"` → `bin/sh` (rejected by `scripts/followthroughs/*` case-glob). Verified at plan-write time. | Adopt verbatim. Assign `$canon` back to `$script` after acceptance so subsequent `-f`/`-x` checks operate on the canonical path. |
| "Fix sketch (~1 line): anchor the start match to column 1 — `/^<!-- *soleur:followthrough`" | The canonical `/ship` Phase 7 Step 3.5 template emits the directive at column 1. **However:** GitHub-flavored markdown fenced code blocks do NOT indent their content — a `<!-- soleur:followthrough` line copy-pasted into a `` ```html `` fence in an issue body STILL begins at column 1 and would still match. Verified at plan-write time via test fixture `/tmp/fenced.md`. | Adopt anchoring (closes the prose-embedded-mid-line case, which is the more common accidental form). Document the residual fenced-block risk in `## Risks` and `## Sharp Edges`; do NOT add fence-state tracking to awk (gold-plating per issue body's "one-character cheap" framing). The path-allowlist (Gap 1) plus the on-disk existence check (line 87) catch the residual case at exec time for any non-existent referenced script. |
| "Multiple directives in one body: only the first is honored" (comment at line 35) | Tested at plan-write time with `/tmp/multi-directive.md`: current awk emits fields for BOTH directives; bash loop overwrites on the second pass; LAST wins. No warning logged. | Adopt fix: awk tracks `seen_count`; emits only inside the first directive range; emits a synthetic line `__sweeper_meta__ multi_directive_count <N>` when N>1 so bash can log the warning the comment promises. |
| Test framework | No `bats` installed (`command -v bats` returns empty). Existing shell tests use the `*.test.sh` convention with bash + helper functions (`scripts/compound-promote.test.sh`, `scripts/lint-agents-enforcement-tags.test.sh`, `scripts/lint-agents-rule-budget.test.sh`, `scripts/rule-metrics-aggregate.test.sh`, `scripts/skill-freshness-aggregate.test.sh` — 5 sibling files). | Use `*.test.sh` convention. Do NOT introduce bats. |
| `scripts/sweep-followthroughs.sh` on the canonical sensitive-paths regex from `plugins/soleur/skills/preflight/SKILL.md:427`? | Regex matches `apps/web-platform/server`, `apps/web-platform/supabase`, `apps/web-platform/app/api`, `middleware.ts`, `apps/[^/]+/infra/`, doppler-named `.yml`/`.sh`, and specific GH workflows. `scripts/sweep-followthroughs.sh` matches none. | `## User-Brand Impact` threshold = `none`; no scope-out note required (file is outside the sensitive-paths regex). |
| Open `code-review` issues touching `scripts/sweep-followthroughs.sh`? | `gh issue list --label code-review --state open --json number,title,body --limit 200` piped through `jq --arg path "scripts/sweep-followthroughs.sh"` returns zero rows. | `## Open Code-Review Overlap`: None. |

## User-Brand Impact

- **If this lands broken, the user experiences:** the follow-through sweeper exits non-zero at 18:00 UTC and operator-facing follow-through issues (sentry-checkins, future Phase 7 Step 3.5 dogfood issues) stop auto-closing — operator notices the next morning when `gh issue list --label follow-through --state open` returns stale entries. No end-user surface.
- **If this leaks, the operator's GitHub Actions runner is exposed via:** an attacker with `issues:write` (i.e., a repo collaborator who is ALREADY trusted) could craft an issue body whose directive points at a committed script outside `scripts/followthroughs/` via path traversal. **Bounded blast radius**: exploitation requires (a) `issues:write` on this repo, (b) a committed executable target — both already gated by PR review. The hardening is defense-in-depth, not a primary security boundary.
- **Brand-survival threshold:** `none`. Sweeper is operator infra; no end-user touches it. File is NOT on the canonical sensitive-paths regex (verified above against `plugins/soleur/skills/preflight/SKILL.md:427`), so no scope-out note is required.

## Open Code-Review Overlap

None. Verified at plan-write time via `gh issue list --label code-review --state open --json number,title,body --limit 200` piped through `jq --arg path "scripts/sweep-followthroughs.sh" '.[] | select(.body // "" | contains($path))'` — zero matches.

## Acceptance Criteria

### Pre-merge (PR)

1. **Gap 1 — realpath canonicalization at sweep time.** `scripts/sweep-followthroughs.sh` rejects path traversal. Verified by `scripts/sweep-followthroughs.test.sh` case T1: a synthetic body containing `script=scripts/followthroughs/../../bin/sh` causes the test's invocation of `run_one` to emit `script path '...' escapes scripts/followthroughs/ — refusing to run` to stderr AND `run_one` returns 2. **Canonical regex verifier:** `grep -nE 'realpath -m --relative-to' scripts/sweep-followthroughs.sh` returns ≥1 line.

2. **Gap 2 — first directive wins + warning logged.** Verified by `scripts/sweep-followthroughs.test.sh` case T2: a synthetic body with two directives (`script=scripts/followthroughs/first.sh` followed by `script=scripts/followthroughs/second.sh`) parses `script=scripts/followthroughs/first.sh` and emits `multi-directive body: 2 directives found, honoring first only` to stdout. **Canonical verifier:** the test asserts `script=scripts/followthroughs/first.sh` is exec-attempted (test stubs the script's existence via a `tmpdir` fixture) AND `second.sh` is NOT exec-attempted (no log line referencing `second.sh` other than the warning).

3. **Gap 3 — anchored awk.** Verified by `scripts/sweep-followthroughs.test.sh` case T3: a body with a directive embedded mid-prose (`See the example: <!-- soleur:followthrough script=scripts/followthroughs/embedded.sh ... -->`) produces zero parsed-directive output (the start regex `/^<!-- *soleur:followthrough/` does not match a mid-line `<!--`). **Canonical verifier:** `grep -nE '^[[:space:]]+/\^<!-- \*soleur:followthrough' scripts/sweep-followthroughs.sh` returns 1 line (the awk start-range pattern) AND `grep -nE '^[[:space:]]+/<!-- \*soleur:followthrough/, /-->/$' scripts/sweep-followthroughs.sh` returns 0 lines (no unanchored remnant).

4. **Contract mirror across all three parser copies.** The awk start-range regex (`/^<!-- *soleur:followthrough/, /-->/`) is identical across all three locations where the parser appears:

   1. `scripts/sweep-followthroughs.sh:38` (authoritative parser)
   2. `plugins/soleur/skills/ship/SKILL.md:1319` (documentation copy in Step 3.5.E)
   3. `plugins/soleur/test/ship-followthrough-directive.test.sh:30-38` (test PARSER copy)

   Verified by:

   ```bash
   grep -oE '/\^?<!-- \*soleur:followthrough[^,]*' scripts/sweep-followthroughs.sh | sort -u > /tmp/sweeper-awk-start.txt
   grep -oE '/\^?<!-- \*soleur:followthrough[^,]*' plugins/soleur/skills/ship/SKILL.md | sort -u > /tmp/ship-awk-start.txt
   grep -oE '/\^?<!-- \*soleur:followthrough[^,]*' plugins/soleur/test/ship-followthrough-directive.test.sh | sort -u > /tmp/test-awk-start.txt
   diff -u /tmp/sweeper-awk-start.txt /tmp/ship-awk-start.txt   # exit 0
   diff -u /tmp/sweeper-awk-start.txt /tmp/test-awk-start.txt   # exit 0
   ```

   AND the SKILL.md realpath snippet at lines 1339-1345 reflects the same `realpath -m --relative-to="$REPO_ROOT"` invocation already prescribed in PR #4191 (no change to that block — it is already correct; the AC verifies non-regression).

   AND `bash plugins/soleur/test/ship-followthrough-directive.test.sh` exits 0 — assertion 5 ("test PARSER and sweeper parse_directive produce equivalent output") continues to pass after the in-lockstep update.

5. **Tests-first.** `scripts/sweep-followthroughs.test.sh` lands in the same PR. The git history shows the test commit precedes the fix commit (`git log --oneline --reverse origin/main..HEAD -- scripts/sweep-followthroughs.sh scripts/sweep-followthroughs.test.sh` shows the test commit first). Either commit ordering is acceptable; the test CAN ALSO be in the same commit as the fix — what matters is that the test fails against the pre-fix sweeper. The PR description includes a `git stash` / `git revert HEAD~N` demonstration: tests fail RED on the pre-fix sweeper, pass GREEN on the post-fix sweeper.

6. **No regression for legitimate inputs.** `scripts/sweep-followthroughs.test.sh` case T4: a canonical column-1 single-directive body (mirroring `/ship` Phase 7 Step 3.5 template at SKILL.md:1263-1268) parses correctly and `run_one` proceeds to the on-disk existence check. T4 is the happy-path regression guard.

7. **`shellcheck` clean.** `shellcheck scripts/sweep-followthroughs.sh scripts/sweep-followthroughs.test.sh` exits 0. (The existing sweeper already passes shellcheck; verify the diff introduces no new findings.)

8. **PR body uses `Closes #4193`** (per `wg-use-closes-n-in-pr-body-not-title-to`; this is a code-change PR that fully resolves the issue at merge time — no post-merge operator action).

### Post-merge (operator)

None. The next scheduled sweep at 18:00 UTC will exercise the hardened sweeper against live `follow-through` issues; no manual intervention required.

**Automation note** (per `hr-exhaust-all-automated-options-before`): post-merge verification of the live sweeper is observable via `gh run list --workflow scheduled-followthrough-sweeper.yml --limit 1 --json conclusion` AFTER 18:00 UTC — this happens automatically without operator action. If the operator wants pre-18:00-UTC live verification, they can dispatch it via `gh workflow run scheduled-followthrough-sweeper.yml -f dry_run=true`.

## Files to Edit

- `scripts/sweep-followthroughs.sh` (~10 LOC net):
  - **Line 38** (awk start-range): `/<!-- *soleur:followthrough/, /-->/` → `/^<!-- *soleur:followthrough/, /-->/` (Gap 3).
  - **Lines 37-48** (awk block): restructure to track `seen_count` and emit fields only inside the first directive range; emit a synthetic `__sweeper_meta__ multi_directive_count <N>` line after the file is consumed so bash can warn (Gap 2). Concretely (**empirically verified at deepen-pass time** — see `## Research Insights` below for the evaluation-order bug discovered in the initial draft):

    ```awk
    BEGIN { in_dir = 0; seen = 0; closing = 0 }
    /^<!-- *soleur:followthrough/ {
      seen++
      if (seen == 1) in_dir = 1
      # else: subsequent directives counted but not entered
    }
    # End-of-directive check MUST run BEFORE the in_dir body block, because
    # the body's gsub(/-->/, "") strips the marker from $0 in place, which
    # would prevent /-->/ from matching on the same line. Set a flag here,
    # apply it in a post-body block.
    /-->/ && in_dir {
      closing = 1
    }
    in_dir {
      gsub(/^<!-- *soleur:followthrough/, "")
      gsub(/-->/, "")
      for (i = 1; i <= NF; i++) {
        if ($i ~ /^script=/)   { sub(/^script=/, "", $i);   print "script "   $i }
        if ($i ~ /^earliest=/) { sub(/^earliest=/, "", $i); print "earliest " $i }
        if ($i ~ /^secrets=/)  { sub(/^secrets=/, "", $i);  print "secrets "  $i }
      }
    }
    closing { in_dir = 0; closing = 0 }
    END { if (seen > 1) print "__sweeper_meta__ multi_directive_count " seen }
    ```

    **Verification under T1/T2/T3/T4** (run at deepen-pass time, expected outputs documented in `## Research Insights`):
    - T1 (single canonical directive): emits `script <path>`, `earliest <iso>`, `secrets <names>` — same as today.
    - T2 (two directives): emits ONLY the first directive's three fields PLUS `__sweeper_meta__ multi_directive_count 2`.
    - T3 (mid-prose directive): emits nothing (anchored start-range rejects).
    - T4 (canonical body identical to T1): emits identical to T1.

  - **Lines 62-68** (bash read loop): add a case branch for `__sweeper_meta__` that logs the warning (`log "issue #$issue_num: multi-directive body (N=$val) — honoring first only"`). Do NOT overwrite `script`/`earliest`/`secrets` from the meta line (Gap 2).
  - **Lines 77-85** (path-safety case): replace bare `case "$script" in "$SCRIPTS_ROOT"/*) : ok ;;` with the realpath-canonicalized form (Gap 1):

    ```bash
    local canon
    canon=$(realpath -m --relative-to="$PWD" "$script" 2>/dev/null || true)
    case "$canon" in
      "$SCRIPTS_ROOT"/*) script="$canon" ;;
      *)
        fail "issue #$issue_num: script path '$script' escapes $SCRIPTS_ROOT/ — refusing to run"
        return 2
        ;;
    esac
    ```

    Assigning `$canon` back to `$script` makes the subsequent `-f`/`-x` checks AND the `env_args` exec line operate on the canonical path. `|| true` guards against realpath failures on exotic input (returns empty `$canon`, which fails the case-glob → REJECT path).

- `plugins/soleur/skills/ship/SKILL.md` (~1 LOC):
  - **Line 1319**: anchor the awk start-range identically: `/<!-- *soleur:followthrough/, /-->/` → `/^<!-- *soleur:followthrough/, /-->/` so the precondition gate the ship skill prescribes matches the sweeper's behavior. The realpath snippet at lines 1339-1345 is already correct (landed in PR #4191) — no change there.
  - **Note:** SKILL.md continues to document the range-based form for the precondition's HUMAN-READABLE prose (the precondition only needs to extract `script`/`earliest`/`secrets` from a single canonical body the agent just composed — first-directive-wins semantics are not load-bearing at the precondition layer because the agent only ever emits one directive). The plan does NOT mirror the first-directive-wins awk restructure into SKILL.md, only the column-1 anchor. Both changes pass through any single-directive body identically; the SKILL.md doc stays as readable as possible.

- `plugins/soleur/test/ship-followthrough-directive.test.sh` (~10 LOC, contract-mirror update):
  - **Lines 30-38** (PARSER block): mirror the column-1 anchor change so test assertion 5 (`test PARSER and sweeper parse_directive produce equivalent output`) continues to pass after the sweeper restructure. The PARSER copy in this test is the THIRD copy of the awk parser in the repo; assertion 5 diff-checks it against the sweeper's `parse_directive()` (extracted at runtime via `sed -n '/^parse_directive() {/,/^}/p'`) — without an in-lockstep update, the PR breaks this pre-existing test.
  - The test's PARSER does NOT need to mirror the first-directive-wins logic because the test's golden fixture `plugins/soleur/test/fixtures/followthrough-directive/expected-issue-body.md` is a SINGLE-directive body (the canonical `/ship` Phase 7 Step 3.5 output). Mirror the FULL restructure (first-directive-wins + anchor + meta line) to keep parser equivalence rigorous; verified at deepen-pass time that the existing fixture parses identically under both old and new awk.
  - **Optional enhancement (consider at /work time):** add a SECOND fixture (`multi-directive-issue-body.md`) and a new assertion (Assertion 6) that the multi-directive case emits `__sweeper_meta__ multi_directive_count 2` from BOTH the test PARSER and the sweeper's `parse_directive()`. This extends contract coverage to the new semantics, not just preserves the old contract. Defer if /work-phase complexity creeps; the new `scripts/sweep-followthroughs.test.sh` T2 already covers behavior end-to-end.

## Files to Create

- `scripts/sweep-followthroughs.test.sh` (~120 LOC, `chmod +x`):
  - Mirrors `scripts/compound-promote.test.sh` convention: `set -euo pipefail`, PASS/FAIL counters, `assert_eq` / `assert_contains` helpers, exit non-zero if any test fails.
  - Sources the sweeper script with `SOURCED=1` guard (the sweeper currently runs `main "$@"` unconditionally — see `## Implementation Phases` Phase 0 below for the small refactor that makes it sourceable for tests).
  - Test cases:
    - **T1 (Gap 1):** invoke `run_one` with a synthetic body whose directive sets `script=scripts/followthroughs/../../bin/sh`; assert stderr contains `escapes scripts/followthroughs/` AND return code is 2.
    - **T2 (Gap 2):** invoke `run_one` with a body containing two directives; stub `scripts/followthroughs/first-test.sh` and `scripts/followthroughs/second-test.sh` via a `tmpdir` fixture and `cd` into it; assert stdout contains `multi-directive body: 2 directives` AND `first-test.sh` exec attempted AND `second-test.sh` NOT exec attempted.
    - **T3 (Gap 3):** invoke `run_one` with a body where the directive is mid-prose (no column-1 anchor); assert `run_one` logs `no directive — skipping` AND returns 0 (the awk emits nothing, bash sees empty `$script`, takes the early-return at line 70-73).
    - **T4 (happy path):** canonical column-1 single-directive body; stub the referenced script in a tmpdir fixture; assert the script gets exec'd, parsed output reaches `env_args`, and DRY_RUN=1 prevents `gh issue` calls.
  - Each test mocks `gh` via `PATH=$tmpdir:$PATH` with a `gh` stub that records args (so the test asserts no real GitHub API calls and validates the close/comment flow).
  - Reuses the codebase's parse-precedence convention from `plugins/soleur/skills/skill-security-scan/scripts/run-scan.sh:34` style — gsub-based parsing — wherever the test needs to pull values from sweeper output, NOT brittle `awk '/^k:/ {print $2}'` (per the plan-time-parsing-pattern Sharp Edge).
- `knowledge-base/project/specs/feat-one-shot-harden-sweep-followthroughs-4193/tasks.md` — derived from this plan post-review (see "Save Tasks" section).

## Implementation Phases

### Phase 0 — Source-safe refactor (~3 LOC, no behavior change)

`scripts/sweep-followthroughs.sh` line 210 runs `main "$@"` unconditionally. Test code that `source`s the file would execute `main` at import. Guard it:

```bash
# Allow tests to source this script without running main().
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
```

This is a non-behavioral change (script-invocation path unchanged) and is the prerequisite for Phase 1 tests.

### Phase 1 — RED tests (~120 LOC new file)

Write `scripts/sweep-followthroughs.test.sh` with T1, T2, T3, T4 against the pre-fix sweeper. Run it; assert T1/T2/T3 FAIL (sweeper's pre-fix behavior) and T4 PASSES (happy path already works on main).

Commit checkpoint: `test: add scripts/sweep-followthroughs.test.sh covering the 3 hardening gaps (RED)`. Push.

### Phase 2 — Gap 3 (anchor awk start-range, 1 LOC)

Change line 38 of `scripts/sweep-followthroughs.sh`: prefix `/<!-- *soleur:followthrough/` with `^`. Re-run tests; T3 flips GREEN.

Mirror the same change to `plugins/soleur/skills/ship/SKILL.md:1319` in the same commit so the Step 3.5.E precondition awk matches the sweeper.

Commit: `fix(sweeper): anchor awk directive start-range to column 1 (Gap 3)`. The single commit covers both files because they are a contract pair (see Sharp Edge in plan skill: `2026-05-10-plan-phase-order-load-bearing-when-contract-changes.md` — change AND consumer in one commit).

### Phase 3 — Gap 2 (first-directive-wins + warning, ~5 LOC)

Restructure the awk block per the snippet in `## Files to Edit`. Add the `__sweeper_meta__` case branch to the bash `read` loop. Re-run tests; T2 flips GREEN.

Commit: `fix(sweeper): honor only the first <!-- soleur:followthrough --> directive (Gap 2)`.

### Phase 4 — Gap 1 (realpath canonicalization, ~5 LOC)

Replace the path-safety case block per the snippet in `## Files to Edit`. Re-run tests; T1 flips GREEN. Verify T4 stays GREEN (canonical path round-trips through realpath unchanged).

Commit: `fix(sweeper): canonicalize directive script path via realpath before allowlist check (Gap 1)`.

### Phase 5 — Verification

```bash
# All new sweeper tests green (the new T1/T2/T3/T4 from this PR)
bash scripts/sweep-followthroughs.test.sh
echo "exit=$?"  # expect 0

# Existing ship-followthrough-directive contract test green
# (was passing pre-fix; MUST continue to pass after the PARSER restructure)
bash plugins/soleur/test/ship-followthrough-directive.test.sh
echo "exit=$?"  # expect 0

# Shellcheck clean
shellcheck scripts/sweep-followthroughs.sh scripts/sweep-followthroughs.test.sh
echo "exit=$?"  # expect 0

# Contract mirror — awk start regex matches across ALL THREE parser copies
#   1. scripts/sweep-followthroughs.sh         (authoritative parser)
#   2. plugins/soleur/skills/ship/SKILL.md     (documentation copy at line 1319)
#   3. plugins/soleur/test/ship-followthrough-directive.test.sh (test PARSER copy at lines 30-38)
grep -oE '/\^?<!-- \*soleur:followthrough[^,]*' scripts/sweep-followthroughs.sh | sort -u > /tmp/sweeper-awk-start.txt
grep -oE '/\^?<!-- \*soleur:followthrough[^,]*' plugins/soleur/skills/ship/SKILL.md | sort -u > /tmp/ship-awk-start.txt
grep -oE '/\^?<!-- \*soleur:followthrough[^,]*' plugins/soleur/test/ship-followthrough-directive.test.sh | sort -u > /tmp/test-awk-start.txt
diff -u /tmp/sweeper-awk-start.txt /tmp/ship-awk-start.txt  # expect no diff
diff -u /tmp/sweeper-awk-start.txt /tmp/test-awk-start.txt  # expect no diff

# AC verifier 1: realpath landed
grep -nE 'realpath -m --relative-to' scripts/sweep-followthroughs.sh  # expect ≥1 line

# AC verifier 3: anchored, no unanchored remnant in the sweeper
grep -cE '^[[:space:]]+/\^<!-- \*soleur:followthrough' scripts/sweep-followthroughs.sh  # expect 1
grep -cE '/<!-- \*soleur:followthrough/, /-->/' scripts/sweep-followthroughs.sh  # expect 0
```

### Phase 6 — Optional live dry-run

After PR merge (or pre-merge if the operator wants extra confidence):

```bash
gh workflow run scheduled-followthrough-sweeper.yml -f dry_run=true
gh run list --workflow scheduled-followthrough-sweeper.yml --limit 1
```

Confirm the run completes successfully and the existing follow-through issue (#3859) parses correctly under the hardened sweeper.

## Observability

```yaml
liveness_signal:
  what: scheduled-followthrough-sweeper.yml workflow run completion
  cadence: daily at 18:00 UTC (cron `0 18 * * *`)
  alert_target: GitHub Actions failure email to repo admins (default GH behavior)
  configured_in: .github/workflows/scheduled-followthrough-sweeper.yml:30
error_reporting:
  destination: workflow run logs (GH Actions UI) + fail() lines on stderr captured by the runner
  fail_loud: yes — `set -euo pipefail` at sweeper line 21; any awk/realpath/bash failure exits non-zero, the workflow job fails, GH emails the operator
failure_modes:
  - mode: Gap 1 path-traversal escape attempt
    detection: sweeper's realpath canonicalization (post-fix) rejects with `fail()` line + exit 2; bash continues to next issue (the outer for-loop at line 200-205 catches per-issue non-zero and continues)
    alert_route: workflow run logs; operator notices on the daily sweep summary
  - mode: Gap 2 multi-directive body
    detection: new `log()` line `multi-directive body: N directives found, honoring first only` in stdout (and thus GH Actions logs); the bash loop emits via the `__sweeper_meta__` case branch
    alert_route: workflow run logs
  - mode: Gap 3 fenced-block / mid-prose embedded directive
    detection: awk returns empty parse → sweeper's existing `no directive — skipping` log at line 71
    alert_route: workflow run logs (operator sees zero directives parsed for that issue; can investigate if expected)
  - mode: realpath unavailable on runner
    detection: `realpath ... || true` returns empty; case-glob rejects empty `$canon` → `fail()` + exit 2
    alert_route: workflow run logs
logs:
  where: GitHub Actions run logs for `scheduled-followthrough-sweeper` workflow
  retention: 90 days (GH Actions default); workflow run summaries persist indefinitely via the workflow runs API
discoverability_test:
  command: |
    gh workflow run scheduled-followthrough-sweeper.yml -f dry_run=true \
      && sleep 30 \
      && gh run list --workflow scheduled-followthrough-sweeper.yml --limit 1 --json conclusion --jq '.[0].conclusion'
  expected_output: |
    success
```

No SSH required. The sweeper's liveness is API-accessible via `gh run list` per `hr-no-dashboard-eyeball-pull-data-yourself`.

## Domain Review

**Domains relevant:** Engineering (CTO).

The hardening touches a security-sensitive shell script and a sibling skill prose. No product, marketing, legal, finance, operations, sales, or support implications. Engineering (CTO) review at PR-time is covered by the standard multi-agent code review (security-sentinel, pattern-recognition-specialist, code-simplicity-reviewer — same trio that surfaced these gaps on PR #4191).

### Engineering (CTO)

**Status:** carry-forward
**Assessment:** Three gaps are real, surgical, well-scoped. The fix sketches in the issue body are correct; realpath canonicalization on uutils 0.8.0 behaves as expected against the demonstrated `..` traversal vector. Tests-first via `*.test.sh` convention aligns with codebase precedent (5 sibling `.test.sh` files in `scripts/`). The mirror into `/ship` Phase 7 Step 3.5.E closes the most subtle plan-time risk: contract drift between the agent-time precondition gate and the sweep-time enforcement.

### Product/UX Gate

Skipped — Product domain not relevant (no UI, no end-user surface, no copy).

## Test Strategy

### Unit / Shell

- `scripts/sweep-followthroughs.test.sh` per `## Files to Create`. Run via `bash scripts/sweep-followthroughs.test.sh`. Exit 0 = all four tests pass; non-zero = at least one failed.
- Per the `Test Strategy` Sharp Edge, the runner is the existing project convention (`*.test.sh` shell scripts), NOT `bats` (confirmed absent via `command -v bats`).

### Integration

- Optional pre-merge live verification via `gh workflow run scheduled-followthrough-sweeper.yml -f dry_run=true` against the staging/main branch after PR merge.
- Existing #3859 follow-through issue is the live integration fixture — the daily sweep at 18:00 UTC after merge will exercise the hardened parser against real data.

### Static

- `shellcheck scripts/sweep-followthroughs.sh scripts/sweep-followthroughs.test.sh` MUST exit 0.

## Risks

1. **Realpath portability.** ubuntu-24.04 ships `uutils realpath 0.8.0` (verified). The `--relative-to` flag is supported there AND in GNU coreutils ≥8.23 (which ubuntu-24.04 also ships as fallback). Risk: if the runner image is downgraded to ubuntu-20.04 (GNU coreutils 8.30), the flag still works. **Mitigation:** Phase 5 verification asserts the realpath form succeeds at PR-time CI; if CI fails on a different runner image, the fix is to add `command -v realpath || { fail "realpath required"; exit 2; }` at the top of the sweeper. Low likelihood — the workflow pins `ubuntu-24.04`.

2. **Fenced-block residual risk.** As called out in the Research Reconciliation table, anchoring the awk start-range to column 1 does NOT prevent a directive copy-pasted at column 1 inside a `` ```html `` fenced block from being parsed. **Mitigation:** Gap 1's realpath check catches traversal targets; line 87's `[[ ! -f "$script" ]]` catches non-existent paths. The combined defense closes the practical exploit shape (issue body with fenced example → sweeper tries to run an attacker-suggested script). Documented in `## Sharp Edges` for future tightening if needed.

3. **`__sweeper_meta__` line collision.** The bash read loop's case-branch could be confused if a future directive field were named `__sweeper_meta__`. **Mitigation:** the double-underscore prefix is reserved by convention; document at the awk block comment.

4. **Test fixture path assumptions.** The tests run `cd` into a tmpdir; if the sweeper's relative paths (`$SCRIPTS_ROOT="scripts/followthroughs"`) interact with the tmpdir's working directory unexpectedly, T4 happy-path could give a false GREEN. **Mitigation:** the test creates `$tmpdir/scripts/followthroughs/test-X.sh` AND `cd` into `$tmpdir` before invoking `run_one`. T4 explicitly asserts the script-existence check at line 87 passes by `chmod +x` on the fixture.

5. **Backward compatibility for existing #3859 directive.** The single existing live follow-through directive (sentry-checkins-3859) is at column 1, single, non-traversal. **Mitigation:** T4 happy-path test mirrors this exact shape; any regression there breaks the test.

## Alternative Approaches Considered

| Approach | Decision | Rationale |
|---|---|---|
| Add fenced-block-state tracking to awk (closes Gap 3 fully, not just anchor) | Deferred | Gold-plating per issue body's "one-character cheap" framing. Path-allowlist + on-disk existence check together catch the practical exploit shape. Document residual in Sharp Edges; revisit if a real fenced-block exploit is observed. |
| Migrate sweeper to a typed parser (Python with `frontmatter`/`commonmark-py`) | Deferred | 50+ LOC rewrite vs. 10 LOC surgical fix; the bash sweeper is the right tool for the job (lives next to the workflow YAML, no Python dependency on the runner). TR9-PR2 (#3985, plan `2026-05-19-feat-tr9-pr2-...`) is already migrating this whole surface to Inngest crons; rewriting now is duplicate work. |
| Bats test framework | Rejected | Not installed; existing codebase convention is `*.test.sh`. Adding bats is a new dependency and contradicts 5 sibling files in `scripts/`. |
| Run `realpath -e` (require path exists) instead of `realpath -m` | Rejected | `-m` is correct because the existence check happens at line 87 with a clearer error message (`script '$script' missing in repo HEAD — leaving issue open`); using `-e` would conflate two failure modes (path-shape rejection vs. path-missing) under one less-informative `realpath: cannot canonicalize` message. |
| Skip the SKILL.md mirror, defer to next ship-skill PR | Rejected | Per `2026-05-10-plan-phase-order-load-bearing-when-contract-changes.md` Sharp Edge: the awk-snippet at SKILL.md:1319 IS the precondition contract that PR #4191 codified; leaving it unanchored creates a divergence the next /ship invocation would tolerate (agent emits unanchored directive position; sweeper accepts only anchored). One-line edit in the same PR. |
| Adopt fenced-block-aware parsing in awk now | Deferred | Same as row 1; track as a follow-up if a real exploit emerges. The compounding effect is small (path-allowlist closes the practical case). |

## Sharp Edges

- **Awk start-range anchoring does NOT close fenced markdown directives whose content is at column 1.** A `<!-- soleur:followthrough` line inside a `` ```html `` fence at column 1 still matches. The practical defense is the realpath path-allowlist (Gap 1 fix) plus the on-disk existence check (line 87). If a future exploit demonstrates the fenced-block residual, the fix is fence-state tracking in awk (~5 more LOC). Tracked as a deferred item; do not gold-plate now.
- **The `__sweeper_meta__` synthetic-line shape is a private contract between the awk parser and the bash read loop.** Future edits to the awk block MUST NOT introduce a real directive field with that name. Documented in an awk-block comment.
- **`/ship` Phase 7 Step 3.5.E awk snippet at SKILL.md:1319 is a verbatim mirror of the sweeper's parser.** Edits to one MUST update the other in the same commit. The Phase 5 verifier asserts equality via `diff -u`.
- **A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6.** This plan's threshold is `none` with a non-empty justification (sweeper is operator infra, file not on sensitive-paths regex) — verified above.
- **Realpath portability assumption** (Risk 1): if the workflow image changes from `ubuntu-24.04`, re-verify `realpath --version` supports `-m --relative-to`. Defense: Phase 5 verifier runs on CI; failure surfaces at PR time, not in production.

## Roadmap / Tracking

- Closes #4193.
- **Permanence:** The bash sweeper (`scripts/sweep-followthroughs.sh` + `.github/workflows/scheduled-followthrough-sweeper.yml`) is permanent infrastructure. Verified at deepen-pass time via TR9 umbrella issue #3948: the workflow was originally classified as a group-(c) agent-loop candidate but **RECLASSIFIED as group-(a)/(b) infra-cron** at PR-2 merge (2026-05-19), with the rationale "pure shell `bash scripts/sweep-followthroughs.sh`, no LLM call; ADR-033 substrate doesn't fit. Stays on GHA." No Inngest migration is planned for this surface; the hardening here is therefore the permanent state, not a transitional improvement.
- **Sibling work (informational, no coupling):** PR #4062 (MERGED 2026-05-19) migrated a SEPARATE workflow — the now-deleted `scheduled-follow-through.yml`, a claude-agent-driven cron that handled a different class of follow-through verification — to `apps/web-platform/server/inngest/functions/cron-follow-through-monitor.ts`. The two surfaces share the word "follow-through" but no code; no coordination is needed.
- **No follow-up tracking issue required.** All three gaps are closed within this PR. The Sharp Edges section documents the residual fenced-block risk (Gap 3 anchoring is necessary-but-not-sufficient at column 1 inside fences) as a known limitation; if a real fenced-block exploit emerges, file at that point.

## Build Verification

```bash
# Phase 5 verification block (executable as a single paste-able snippet)
bash scripts/sweep-followthroughs.test.sh
shellcheck scripts/sweep-followthroughs.sh scripts/sweep-followthroughs.test.sh

grep -oE '/\^?<!-- \*soleur:followthrough[^,]*' scripts/sweep-followthroughs.sh | sort -u > /tmp/sweeper-awk-start.txt
grep -oE '/\^?<!-- \*soleur:followthrough[^,]*' plugins/soleur/skills/ship/SKILL.md | sort -u > /tmp/ship-awk-start.txt
diff -u /tmp/sweeper-awk-start.txt /tmp/ship-awk-start.txt

grep -nE 'realpath -m --relative-to' scripts/sweep-followthroughs.sh
grep -cE '^[[:space:]]+/\^<!-- \*soleur:followthrough' scripts/sweep-followthroughs.sh
grep -cE '/<!-- \*soleur:followthrough/, /-->/' scripts/sweep-followthroughs.sh
```

Expected:
- Test suite exits 0.
- shellcheck exits 0.
- diff exits 0 (no output).
- realpath grep returns ≥1 line.
- anchored-form grep returns 1.
- unanchored-form grep returns 0.

## Research Insights

### Verified at plan-write time

- `realpath -m --relative-to="$PWD"` correctly rejects `scripts/followthroughs/../../bin/sh` → `bin/sh` (not under `scripts/followthroughs/`). Uutils coreutils 0.8.0 (worktree shell) AND GNU coreutils on ubuntu-24.04 both support the flag.
- Current sweeper's awk emits BOTH directives' fields when two `<!-- soleur:followthrough -->` blocks appear in one body; bash `read` loop's last-wins assignment confirms the documented behavior contradicts the line-35 comment.
- Anchoring `^<!-- ` blocks mid-prose directives (the more common accidental form) but does NOT block fenced-block directives at column 1. The issue body's "theoretical" framing is correct — the residual risk is bounded by the path-allowlist + existence-check pair.
- No open `code-review` issues reference `scripts/sweep-followthroughs.sh`.
- `scripts/sweep-followthroughs.sh` is NOT on the canonical sensitive-paths regex (`plugins/soleur/skills/preflight/SKILL.md:427`), so the `## User-Brand Impact` threshold `none` does not require a scope-out note.
- Existing shell-test convention is `*.test.sh` (5 sibling files: `compound-promote.test.sh`, `lint-agents-enforcement-tags.test.sh`, `lint-agents-rule-budget.test.sh`, `rule-metrics-aggregate.test.sh`, `skill-freshness-aggregate.test.sh`); no `bats` installed.
- PR #4191 (merged commit `7ed6704b` at 2026-05-20T17:42:32Z, title `feat(ship): rewrite Phase 7 Step 3.5 follow-through emitter to sweeper directive`) does not touch `scripts/sweep-followthroughs.sh` — the gaps are pre-existing and the issue body's framing is accurate.
- Every `gh` invocation in this plan is automatable per `wg-pm-class-followthrough-for-operator-dogfood` — no operator-dashboard-eyeball steps.

### Verified at deepen-pass time

- **Awk evaluation-order bug discovered.** The initial restructure snippet (`/-->/ { if (in_dir) in_dir = 0 }` placed AFTER the `in_dir` body block) failed empirically because the body's `gsub(/-->/, "")` strips the closing marker from `$0` in place, so the `/-->/` end-match never fires. Debug output captured at `/tmp/awk-v2-debug.awk` shows `seen=2, in_dir=1` at line 9 of the two-directive fixture — both directives' fields were emitted. Fixed by hoisting a `closing` flag check BEFORE the gsub block and applying it AFTER. Verified the corrected v3 form against T1/T2/T3/T4 fixtures.

- **Third parser copy discovered.** `plugins/soleur/test/ship-followthrough-directive.test.sh:30-38` carries a PARSER block that mirrors the sweeper's `parse_directive()`. Assertion 5 in that test diff-checks the test PARSER against the sweeper's function (extracted at runtime via `sed -n '/^parse_directive() {/,/^}/p'`). Without updating the test PARSER in lockstep, the PR breaks this pre-existing test. The contract-mirror requirement is **three files, not two**: sweeper authoritative, SKILL.md doc, test PARSER.

- **TR9 attribution corrected.** Initial plan claimed `scripts/sweep-followthroughs.sh` would be migrated to Inngest by TR9-PR2 (cited #3985). Verified via `gh pr view 4062 --json state,title` (MERGED, title `feat(runtime): TR9 PR-2 — migrate scheduled-follow-through to Inngest cron`) AND `gh issue view 3948 --json body`: the umbrella explicitly states `~~scheduled-followthrough-sweeper~~ — RECLASSIFIED group (a)/(b) infra-cron (pure shell bash scripts/sweep-followthroughs.sh, no LLM call; ADR-033 substrate doesn't fit). Stays on GHA. Dropped from TR9 scope at PR-2 merge (2026-05-19).` The bash sweeper is permanent infrastructure.

- **Line citations verified** against current `main` state via `awk 'NR==X' <file>`:
  - sweeper L21 (`set -euo pipefail`), L36-48 (awk block), L38 (range start), L62-68 (bash read loop), L70 (empty-script early return), L79-85 (case block), L87 (existence check), L200-205 (outer for-loop), L210 (main invocation) — all match the plan's references.
  - `plugins/soleur/skills/preflight/SKILL.md:427` — canonical sensitive-path regex.
  - `plugins/soleur/skills/ship/SKILL.md:1313-1345` — Step 3.5.E precondition block. Line 1319 confirmed unanchored today (the change target).

- **Rule-ID citations verified** active in `AGENTS.md` + sidecars: `cq-write-failing-tests-before`, `hr-no-dashboard-eyeball-pull-data-yourself`, `wg-use-closes-n-in-pr-body-not-title-to`, `hr-exhaust-all-automated-options-before`, `wg-pm-class-followthrough-for-operator-dogfood`, `hr-weigh-every-decision-against-target-user-impact`, `hr-observability-as-plan-quality-gate`. None retired, none fabricated.

- **Existing test baseline** captured: `bash plugins/soleur/test/ship-followthrough-directive.test.sh` exits 0 on current `main` (5 assertions pass). This is the regression baseline the new PR must preserve.

### Hard gates passed (deepen-plan Phases 4.5–4.8)

- **Phase 4.5** (network-outage trigger): no symptom-class match; the single `ssh` token in the plan is a NO-SSH-required clarification in `discoverability_test`.
- **Phase 4.6** (User-Brand Impact halt): section present, non-empty, threshold = `none`, file NOT on sensitive-paths regex (verified) → no scope-out required.
- **Phase 4.7** (Observability halt): 5-field schema present, all fields non-placeholder, `discoverability_test.command` is `gh workflow run` + `gh run list` (no SSH).
- **Phase 4.8** (PAT-shaped variable): no matches against the four PAT-pattern regexes.

### Deepen-plan quality-check verifications applied

- ✅ Self-grep scope: AC1's `grep -nE 'realpath -m --relative-to' scripts/sweep-followthroughs.sh` is correctly scoped to a single file path (NOT a directory walk), so plan-body occurrences of the literal string cannot pollute the verifier.
- ✅ Every cited PR/issue verified live via `gh pr view N --json state,title` / `gh issue view N --json state,title` (#4191, #4193, #3985, #4062, #4063, #3859, #3948).
- ✅ Every cited GitHub label verified (none prescribed — this plan creates no tracking issues post-merge).
- ✅ Every cited file/line citation re-read at deepen-pass time.
- ✅ Every cited rule ID grepped against AGENTS.md + sidecars.
- ✅ Awk start-range pathspec equivalent (anchored vs. unanchored) tested against fixture inputs covering canonical column-1 directive, mid-prose embedded directive, and multi-directive body.
- ✅ Test-framework SKILL.md sharp edge satisfied: tests use `*.test.sh` (verified installed convention, 5 sibling files), NOT bats (verified absent).
- ✅ Bash strict-mode (`set -euo pipefail`) interaction: the sweeper already runs strict-mode at line 21; the realpath `|| true` guard intentionally swallows realpath's non-zero exit on exotic input so empty `$canon` falls through to the case-glob REJECT path. Tested empirically: `realpath -m --relative-to="$PWD" ""` exits non-zero with `error: invalid value`, but the existing line-70 `[[ -z "${script:-}" ]]` guard prevents empty input from reaching the realpath call.

### Best-practices references

- **GNU/uutils realpath behavior**: `-m` accepts non-existent paths (right choice — existence check happens at line 87 with a clearer error message); `--relative-to=BASE` produces a path relative to BASE (right choice — keeps the case-glob form unchanged at `"$SCRIPTS_ROOT"/*` against a `scripts/followthroughs/...` relative form).
- **Awk evaluation order**: pattern-action blocks fire in source order, and `gsub` modifies `$0` in place. End-of-range markers that the body strips must be detected with a pre-strip flag.
- **GitHub Actions ubuntu-24.04 image**: ships both GNU coreutils (`/usr/bin/realpath`) and uutils coreutils as a fallback; `-m --relative-to` is supported in both.
