---
title: A verdict covers only the checks that ran, and every quoted dispatch command owes its required inputs
date: 2026-11-19
category: workflow-issues
module: cf-lb-overlay serve gate (lb-weight-gate.sh, web2-luks-live-6931 grader)
tags: [soak-gate, grader, operator-hold, test-flake, review-fix-rounds, lefthook]
issues: ["#12849", "#12820", "#12933", "#12970", "#12931"]
pr: "#12934"
---

# Learning: a verdict covers only the checks that ran

## Problem

PR #12934 put a 3-day floor on the serve gate's LUKS soak. It also called the per-instance grader (`web2-luks-live-6931.sh`) before the plan step. Building it surfaced five recurring traps, all in the record or in the test harness rather than in the gate itself:

1. **A grader verdict was recorded beyond its scope.** On 2026-11-19, about 70 h into a 72 h soak, the grader read `NOT YET`, and I recorded "no non-green row". That claim had no basis. The grader returns at its age check before it reads any probe row. The read that actually scanned rows was the 15:30Z `PASS` at 75 h.
2. **A quoted operator command would have been refused.** The drain command in the hold was missing `-f reason=`, which `cf-lb-overlay.yml` requires. It would have failed in exactly the situation it exists for.
3. **Wall-clock windows were anchored at suite start.** The `p_ev_age` rows allowed ±120 s around a `NOW` captured when the suite started. Under host load of about 150 the suite ran long enough that 9 rows failed every time.
4. **Fix rounds closed one instance, and the next review found the class.** Examples: one YAML key spelling (quoted `"if"` was still open), one errexit form (`exit "0"` was still open), and `BASH_ENV` alone (`SHELLOPTS` and `PS4` were still open).
5. **A scan-gate range across a merge commit scanned main's files.** `b0fbb11c31..HEAD` contained `5df95ea00c` (merge of origin/main), so the gate scanned 228 files from main.

## Solution

1. Every verdict is now recorded with the checks that ran. The #12820 PASS comment says that the earlier `NOT YET` "stopped at the age check, so it read no probe rows". The PR body's affected-gate disclosure says the same.
2. Every quoted copy of the drain command carries all required inputs: the runbook, the PR body, the hold and #12820. The correction was posted where the bad command had been quoted.
3. `p_ev_age` slack is now `elapsed since NOW + 120`, so it grows with the suite's real run time.
4. The checks now parse structure instead of matching text:
   - `sk_yaml_ok` reads the workflow with `yaml.safe_load` and asserts step key sets.
   - `SK_GATE_BODY` is an exact-body snapshot.
   - The `env -u` list covers the whole bash-startup class (`BASH_ENV ENV SHELLOPTS BASHOPTS PS4`).
   - Committed mutants (`skmut`) pin each of these.
5. The scan gate is scoped to this branch's own files: `git log --first-parent --no-merges --diff-filter=ACMR --name-only --format= <since>..HEAD`, plus the merge's own resolution paths (`git diff-tree --cc --name-only <merge>`). A first draft of this line named `git log --no-merges` alone; the fix-round review measured it at 318 files against 6, because `--no-merges` keeps every commit the merge brought in from main.

## Key Insight

A verdict's scope is the set of checks that **ran**, not the set its name suggests. "NOT YET" from a grader that returns early says nothing about the checks after its return. The same discipline applies to quoted commands: before a command is written into a hold, a runbook or an issue, diff its `-f` flags against the workflow's `required: true` inputs.

## Session Errors

1. **A NOT YET grader read was recorded as "no non-green row"** — Recovery: re-read after 72 h (PASS, with the rows scanned), and posted a corrected record on #12820 and in the ADR-263 amendment. — **Prevention:** when recording a grader or gate verdict, name the last check it reached (age, rows, boot join) and claim nothing past it.
2. **The drain command in the operator hold had no `-f reason=`** — Recovery: corrected on #12820, in the runbook and in the PR body. — **Prevention:** before quoting a `gh workflow run` command, list the workflow's required inputs (`yq '.on.workflow_dispatch.inputs | to_entries[] | select(.value.required) | .key'`) and check that each one has an `-f`. Routed to ship/references/operator-holds.md.
3. **Suite wall-clock rows anchored on a start-of-suite NOW failed under load** — Recovery: slack now follows elapsed time. — **Prevention:** a time window in a test is measured from the moment the assertion reads the clock, or its slack includes elapsed time. A fixed slack from a captured NOW is a load-dependent flake.
4. **Fix rounds closed instances, not classes** — Recovery: parsed-YAML checks, an exact-body snapshot, the full `env -u` class, and committed mutants. — **Prevention:** already in review/SKILL.md ("A FIX COMMIT IS THE LEAST-AUDITED SURFACE"). Apply it to your own fix rounds before the review panel sees them.
5. **A scan-gate range spanning a merge from main scanned main's files** — Recovery: re-ran on own files only. — **Prevention:** routed to review/SKILL.md (scan gate: a fix-round range that contains a merge commit passes the `--first-parent --no-merges --diff-filter=ACMR` path list plus `git diff-tree --cc --name-only <merge>`).
6. **`emit-review-trailer.sh --agents-ran` was given names** — Recovery: re-ran with integer counts. — **Prevention:** one-off. The script's error message already names the contract.
7. **Accidentally sourced a test file (63 KB of output)** — Recovery: no tree damage, discarded. — **Prevention:** one-off. Run suites with `bash <file>`, never `source`.
8. **A hook blocked `pgrep -f`** — Recovery: read the task output file instead. — **Prevention:** one-off, already hook-enforced.
9. **The issue-filing gates refused three times** (milestone / filing exit; `User-Impact` must name a route and `Fix-Size` must read `N lines / M files`; a filing inside the inline threshold is refused) — Recovery: the Cloudflare Email Obfuscation finding (CSP blocks `email-decode.min.js` on /dashboard, then React #418) went to #12931 as a comment, because that issue migrates those config rules. — **Prevention:** already hook-enforced. Write the two lines in gate form on the first try, and route a small finding in another subsystem to the open issue that owns that subsystem.
10. **The soak follow-through enrollment gate blocked `gh pr ready`** — Recovery: a `gate-override: soak-followthrough-enrollment` line in the PR body with a one-line justification (no soak close criterion; #12820 tracks the live soak). — **Prevention:** already gate-enforced. Write the override (or enroll) when drafting a PR body that discusses a soak.
11. **`lint-infra-no-human-steps` failed only in CI** (a runbook table row paired the human-actor class label with a host-restart verb) — Recovery: renamed the class to `HOLD` and reworded the clause (566feb5441). — **Root cause:** the shared repository config sets `core.hooksPath=/dev/null` (local scope, `/data/git-repositories/jikig-ai/soleur/.git/config`), so lefthook's pre-commit lint never runs in any worktree. The lint has failed on this file since b0fbb11c31. — **Prevention (null-guardrail, unwired):** the check exists (lefthook `lint-infra-no-human-steps`, CI `lint-bot-statuses`), but nothing runs it locally while `hooksPath` is disabled. Run `python3 scripts/lint-infra-no-human-steps.py <changed runbooks/ADRs/plans>` before pushing a docs change, or restore hooks once the operator confirms why they were disabled.
12. **Playwright: first navigate hit a closed browser; screenshot path outside the allowed roots** — Recovery: retried, and saved under `/data/git-repositories/jikig-ai/soleur/.playwright-mcp/`. — **Prevention:** one-off. Covered by `hr-mcp-tools-playwright-etc-resolve-paths`. The allowed roots are the repo and `.playwright-mcp`, not the scratchpad.
13. **Forwarded from the plan phase:** `gh issue view --comments --json` flag clash; issue-create hook blocks; the plan named `bash` for a `.py` lint; G13-scope wrongly classed as an operator decision (reclassified as technical by CTO ruling) — **Prevention:** all already covered (hooks, `hr-technical-fork-is-not-an-operator-question`).
14. **A merge conflict on `BASELINE_DECLARED_PROBES`** in `preflight-discoverability-test.test.ts` (#12897 also moved it) — Recovery: kept both comments and took the measured value of 100. — **Prevention:** one-off. The PR body's merge-order note covers the sibling floor collision with #12918.

## Tags

category: workflow-issues
module: cf-lb-overlay serve gate
