---
title: hr-rule retirement guard
date: 2026-04-24
feature: feat-hr-rule-retirement-guard
issue: 2871
draft_pr: 2877
brainstorm: knowledge-base/project/brainstorms/2026-04-24-hr-rule-retirement-guard-brainstorm.md
spec: knowledge-base/project/specs/feat-hr-rule-retirement-guard/spec.md
status: ready-for-work
---

# Plan: hr-rule retirement guard (#2871)

## Overview

Add a hard-block in `scripts/lint-rule-ids.py` that rejects any `hr-*` id appearing in `scripts/retired-rule-ids.txt`. Retiring a security-critical hard-rule becomes a two-step, visible-in-diff operation: the retiring PR must also edit `lint-rule-ids.py` to remove the guard. The linter edit is the review gate.

Approach **D** from issue #2871 (hard-block, no escape valve). Rejected A (CODEOWNERS overhead for one-file protection), B (trailer is fakeable), C (signed manifest overkill). Rationale lives in `knowledge-base/project/brainstorms/2026-04-24-hr-rule-retirement-guard-brainstorm.md`.

## Research Reconciliation — Spec vs. Codebase

| Spec claim | Reality | Plan response |
|---|---|---|
| FR6: "Tests in `tests/scripts/test_lint_rule_ids.py` (or equivalent pytest path)" | Repo uses `unittest`, not pytest. Test file already exists with `_run_with_retired` + `_run_git_seeded` helpers. | Extend the existing file; use `unittest`. |
| FR4: "AGENTS.md `cq-rule-ids-are-immutable` MUST gain a concise note" | AGENTS.md rule `wg-every-session-error-must-produce-either` has a discoverability exit: when an agent discovers the constraint via a clear error, a learning file alone suffices. The new error message IS that clear error. | **Drop the AGENTS.md edit.** Keep the learning-file caveat only. Self-consistency with our own rule beats spec literalism. |
| TR3: "exit code 2 (usage/policy error)" | Existing reintroduction check (content violation in the same file) returns 1. | Use **exit 1** for consistency with sibling content-violation checks. |
| TR5: "No changes to `lefthook.yml` — existing pre-commit already covers" | Lefthook glob is `AGENTS.md` only. A PR that adds `hr-*` to `retired-rule-ids.txt` without touching AGENTS.md bypasses pre-commit. | One-line lefthook fix: extend glob to include `scripts/retired-rule-ids.txt` and pin the lint target to `AGENTS.md` (glob decides WHEN, command decides WHAT). |
| TR6: "If `scripts/rule-prune.sh` has parallel retired-id parsing" | `rule-prune.sh` has zero "retired" references. | Scoped out. |
| (Implicit) Existing tests compatible with the new block | Two existing tests (`test_retired_id_passes_when_in_allowlist`, `test_reintroduced_retired_id_fails`) use `hr-rule-two` as retired-id fixture. Will break under new hard-block. | Swap fixtures to `cq-rule-two`; move from `## Hard Rules` to `## Code Quality` section for prefix-consistency. |
| (Implicit) CI re-runs `lint-rule-ids.py` against real data | CI runs the `unittest` suite but NOT the linter against real `retired-rule-ids.txt` + `AGENTS.md`. `git commit -n` bypass escapes both lefthook and CI. | **Add one line to `scripts/test-all.sh`** invoking the linter against real files. Closes the CI bypass — load-bearing, not scope creep. |
| (Implicit) `startswith("hr-")` case-sensitivity is a concern | Active-rule regex `^(hr\|wg\|cq\|rf\|pdr\|cm)-` is case-sensitive lowercase. Uppercase `HR-` would already fail the active-rule validator. | Use `startswith("hr-")`; no `.lower()` needed. |
| (New — Kieran review) BOM handling | `\uFEFF` + `hr-foo` on line 1 bypasses `startswith("hr-")`. Real silent-drop. | `load_retired_ids` strips `\uFEFF` defensively; test scenario locks it. |
| (New — discovered at GREEN) "No `hr-*` currently retired" was wrong | `scripts/retired-rule-ids.txt` already contains two `hr-*` from PR #2865 (`hr-before-running-git-commands-on-a`, `hr-never-use-sleep-2-seconds-in-foreground`) — retired via the discoverability litmus (tools surface the constraint via clear errors). | Introduced `HR_RETIREMENT_ALLOWLIST` frozenset in `lint-rule-ids.py` grandfathering the two pre-existing entries. Any future hr-* retirement must add to this set — the script edit IS the review gate, same protection as "edit the guard wholesale." |

## Files to Edit

- `scripts/lint-rule-ids.py` — add `hr-*` hard-block immediately after `retired_ids = load_retired_ids(...)` in `main()`; add BOM strip to `load_retired_ids`.
- `tests/scripts/test_lint_rule_ids.py` — (a) add new tests for the `hr-*` block and BOM, (b) swap `hr-rule-two` → `cq-rule-two` in two existing tests, moving the fixture rule to a `## Code Quality` section for prefix-consistency.
- `lefthook.yml` — extend `rule-id-lint` glob to include `scripts/retired-rule-ids.txt`; replace `{staged_files}` with explicit `AGENTS.md`.
- `scripts/test-all.sh` — add one line invoking the linter against real `retired-rule-ids.txt` + `AGENTS.md` to close the CI-side bypass.
- `knowledge-base/project/learnings/2026-04-21-agents-md-rule-retirement-deprecation-pattern.md` — append `## hr-* caveat` section.

## Files to Create

None.

## Implementation Steps (TDD, sequenced)

1. **RED** — in `tests/scripts/test_lint_rule_ids.py`, add one `TestHrRetirementGuard` class with four tests: (a) single `hr-*` retired id → exit 1, stderr names the id; (b) two `hr-*` retired ids → exit 1, stderr names both; (c) BOM-prefixed `\uFEFF` + `hr-foo` retired id → exit 1 (defensive); (d) mixed `hr-*` + `cq-*` → block fires on hr-only. Use the existing `_run_with_retired` helper. Run; all four must fail (block not implemented).
2. **RED (swap)** — in `test_retired_id_passes_when_in_allowlist` and `test_reintroduced_retired_id_fails`: change the fixture rule id from `hr-rule-two` to `cq-rule-two` and move it to a `## Code Quality` section in the fixture string (not `## Hard Rules`). Run the two tests; they must still pass (swap is mechanical).
3. **GREEN** — implement in `scripts/lint-rule-ids.py`:
   - In `load_retired_ids`, strip `\uFEFF` defensively: replace `stripped = line.strip()` with `stripped = line.lstrip("\uFEFF").strip()`.
   - In `main()`, immediately after `retired_ids = load_retired_ids(args.retired_file)` on line 149: add `hr_retired = sorted(r for r in retired_ids if r.startswith("hr-"))`. If non-empty, print the error message (below) to stderr and `return 1`. Place before `paths = args.paths or ...` so FR3 holds (block fires before any `lint()` call).
4. **GREEN** — run `python3 -m unittest tests.scripts.test_lint_rule_ids -v`. All tests pass (new + swapped + existing).
5. **Lefthook edit** — in `lefthook.yml` under `rule-id-lint`:
   - `glob: "AGENTS.md"` → `glob: ["AGENTS.md", "scripts/retired-rule-ids.txt"]`.
   - `run: ... {staged_files}` → `run: python3 scripts/lint-rule-ids.py --retired-file scripts/retired-rule-ids.txt AGENTS.md`.
   - Verify: stage only `scripts/retired-rule-ids.txt` (touch a comment) and run `lefthook run pre-commit` — `rule-id-lint` must execute. Unstage before committing the plan deliverables.
6. **CI bypass closure** — in `scripts/test-all.sh`, after the existing unittest line (line 54), add:

   ```bash
   run_suite "scripts/lint-rule-ids-live" python3 scripts/lint-rule-ids.py --retired-file scripts/retired-rule-ids.txt AGENTS.md
   ```

   (Match the `run_suite` helper pattern used elsewhere in the file. Verify by running `bash scripts/test-all.sh` locally.)
7. **Learning file edit** — append to `knowledge-base/project/learnings/2026-04-21-agents-md-rule-retirement-deprecation-pattern.md`:

   ```markdown
   ## hr-* caveat (added 2026-04-24, PR #<this-PR>)

   Hard-rules (prefix `hr-*`) cannot be retired via the pointer-preservation
   migration pattern OR full-body removal via `scripts/retired-rule-ids.txt`.
   `scripts/lint-rule-ids.py` hard-blocks any `hr-*` entry in the allowlist.

   To retire a hard-rule, the retiring PR must also edit `lint-rule-ids.py`
   to remove the guard — the linter change makes the one-way door explicit
   in review.

   Rationale: hard-rules are security/blast-radius critical; a plausible
   breadcrumb slipping past review under an innocuous PR title is not
   recoverable under the original id. The AGENTS.md rule itself is
   intentionally NOT updated (per `wg-every-session-error-must-produce-either`
   discoverability exit — the error message IS the discoverability signal).

   See #2871 / PR #<this-PR>.
   ```

8. **Final gate** — `bash scripts/test-all.sh` exits 0. `lefthook run pre-commit` against the staged manifest (all edited files) exits 0. Draft PR body contains `Closes #2871`.

## Error Message (exact text)

```
ERROR: hard-rule(s) cannot be retired via scripts/retired-rule-ids.txt: ['hr-<id>']
Hard-rules (hr-*) are security-critical and are linter-blocked from retirement.
To retire one, edit scripts/lint-rule-ids.py in the same PR to remove this guard.
```

## Test Scenarios

| Scenario | Fixture | Expected |
|---|---|---|
| Happy path — no hr-* | `cq-old-rule \| ...` | exit 0 |
| Block fires — single hr-* | `hr-test-fake \| ...` | exit 1; stderr contains `hr-test-fake`, "hard-rule", "lint-rule-ids.py" |
| Block fires — multiple hr-* | Two `hr-*` lines | exit 1; stderr lists both ids (sorted) |
| BOM-prefixed hr-* caught | `\uFEFF` + `hr-foo \| ...` | exit 1 (defensive BOM strip) |
| Mixed hr-*+ cq-* | One of each | exit 1; stderr names only the hr-* |
| Existing: `test_retired_id_passes_when_in_allowlist` | Swapped to `cq-rule-two` under `## Code Quality` | exit 0 (unchanged) |
| Existing: `test_reintroduced_retired_id_fails` | Swapped to `cq-rule-two` under `## Code Quality` | exit 1 (unchanged) |

## Acceptance Criteria

### Pre-merge (PR)

- [x] `scripts/lint-rule-ids.py` hard-blocks any `hr-*` entry in `retired-rule-ids.txt` with exit 1 and the specified 3-line error message. BOM strip added to `load_retired_ids`.
- [x] New `TestHrRetirementGuard` class with 4 tests (single, multiple, BOM, mixed).
- [x] Two existing tests swapped to `cq-rule-two` under `## Code Quality` and still pass.
- [x] `python3 -m unittest tests.scripts.test_lint_rule_ids -v` exits 0; `bash scripts/test-all.sh` exits 0 (including the new `scripts/lint-rule-ids-live` suite).
- [x] `lefthook.yml` `rule-id-lint` glob extended to `["AGENTS.md", "scripts/retired-rule-ids.txt"]`; command pinned to `AGENTS.md`. Verified: staging only `retired-rule-ids.txt` still triggers the hook.
- [x] `scripts/test-all.sh` invokes `lint-rule-ids.py` against real files via `run_suite`.
- [x] Learning file `2026-04-21-agents-md-rule-retirement-deprecation-pattern.md` gets the `## hr-* caveat` section.
- [x] PR body contains `Closes #2871`.
- [x] `lefthook run pre-commit` passes against the staged manifest.

### Post-merge (operator)

- [x] None. Self-contained linter + test + docs change.

## Domain Review

**Domains relevant:** Engineering.

Brainstorm carried forward: Engineering (CTO) assessment — small, self-contained linter extension; architectural concern is avoiding drift between `load_retired_ids()` and `scripts/rule-prune.sh` (confirmed no-op in this plan's Research Reconciliation). No new hook; lefthook already runs `lint-rule-ids.py` pre-commit.

### Engineering

**Status:** reviewed (carried forward from brainstorm)
**Assessment:** Low-risk linter extension. One function addition in `main()`, two new test cases, two existing test fixtures swapped, one lefthook glob extension, two doc edits (AGENTS.md rule + learning file). No new file, no new dependency, no new CI step.

### Product/UX Gate

**Not applicable.** Zero user-facing surface. Mechanical check of new file-path list: `Files to Create` is empty; `Files to Edit` contains only `.py`, `.yml`, `.md` under `scripts/`, `tests/`, `knowledge-base/`, and root. No `components/**`, `app/**/page.tsx`, `app/**/layout.tsx` matches. Tier **NONE** per the mechanical escalation rule.

## Open Code-Review Overlap

**None.** `gh issue list --label code-review --state open` returned zero matches for any of: `scripts/lint-rule-ids.py`, `retired-rule-ids.txt`, `cq-rule-ids-are-immutable`. Query run 2026-04-24.

## SpecFlow Decision

**Skipped.** The single-branch check (`if id.lower().startswith("hr-")`) has no silent-drop conditional risk. Comment-line, whitespace, and case variants are handled either by the existing `load_retired_ids()` parser or by the defensive `.lower()`; covered in Test Scenarios above. Brainstorm + spec + this plan's Research Reconciliation together exhaust the edge space.

## Risks

- **"Why build this at all?" (DHH challenge).** Engaged in plan review. The threat model isn't "reviewer asleep during security-critical retirement PR" — it's skim-approval of a 1-line `retired-rule-ids.txt` diff under an innocuous title ("cleanup: drop obsolete rule"). The linter catches it automatically at pre-commit AND CI. Cost: ≤1h; benefit: permanent, one-way-door protection. Ship.
- **`git commit -n` + `--no-verify` bypass.** Previously acknowledged-only; now CLOSED by the new `scripts/test-all.sh` line — CI runs the linter against real files, so a bypassed pre-commit still fails on push.
- **Future refactor drops the guard silently.** Mitigated by the 4 new tests — any refactor that removes the check breaks them.
- **Someone retires a legitimate hr-* rule.** Expected workflow: that PR edits `lint-rule-ids.py` to remove/narrow the guard. The diff is plainly visible and reviewed. The hard-block IS the review gate.
- **AGENTS.md byte-budget.** Zero impact — this plan explicitly does NOT edit AGENTS.md (per `wg-every-session-error-must-produce-either` discoverability exit).

## Alternatives Considered (brief)

| Alternative | Rejected because |
|---|---|
| Option A (CODEOWNERS) | First-ever CODEOWNERS file for one-file protection; branch-protection coupling unjustified at solo-founder scale |
| Option B (commit-trailer) | Trailer is fakeable; weaker than hard-block |
| Option C (signed manifest) | Overhead disproportionate to threat model |
| Escape-valve allowlist file | Reintroduces the "plausible breadcrumb" attack surface we're closing |
| Extend block to `wg-*`/`cq-*`/etc. | Hard-rules are uniquely load-bearing; lower-prefix retirement is routine and discoverability-litmus'd |

## References

- Issue #2871 — parent tracking issue
- PR #2862 — shipped retired-ids allowlist; security-sentinel finding #4 origin
- PR #2754, Issue #2686 — earlier pointer-preservation migration pattern
- PR #2877 — draft PR for this feature
- `knowledge-base/project/brainstorms/2026-04-24-hr-rule-retirement-guard-brainstorm.md`
- `knowledge-base/project/specs/feat-hr-rule-retirement-guard/spec.md`
- `knowledge-base/project/learnings/2026-04-21-agents-md-rule-retirement-deprecation-pattern.md`
- `scripts/lint-rule-ids.py`, `scripts/retired-rule-ids.txt`, `lefthook.yml`, `tests/scripts/test_lint_rule_ids.py`
- AGENTS.md rules: `cq-rule-ids-are-immutable`, `cq-agents-md-why-single-line`, `wg-when-fixing-a-workflow-gates-detection`
