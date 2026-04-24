---
title: hr-rule retirement guard — tasks
feature: feat-hr-rule-retirement-guard
issue: 2871
plan: knowledge-base/project/plans/2026-04-24-feat-hr-rule-retirement-guard-plan.md
---

# Tasks — hr-rule retirement guard

## Phase 1 — Core guard (TDD)

- [ ] **1.1 RED** — Add `TestHrRetirementGuard` class in `tests/scripts/test_lint_rule_ids.py` with 4 tests:
  - [ ] 1.1.1 `test_rejects_single_hr_retired_id` (exit 1, stderr names the id + "hard-rule" + "lint-rule-ids.py")
  - [ ] 1.1.2 `test_rejects_multiple_hr_retired_ids` (exit 1, stderr lists both ids sorted)
  - [ ] 1.1.3 `test_rejects_bom_prefixed_hr_retired_id` (`﻿hr-foo` → exit 1)
  - [ ] 1.1.4 `test_mixed_hr_and_cq_retired_ids` (exit 1, stderr names only the hr-*)
  - [ ] 1.1.5 Run `python3 -m unittest tests.scripts.test_lint_rule_ids.TestHrRetirementGuard -v` → all 4 must fail (block not implemented)
- [ ] **1.2 RED (swap)** — In `tests/scripts/test_lint_rule_ids.py`:
  - [ ] 1.2.1 `test_retired_id_passes_when_in_allowlist`: change fixture id `hr-rule-two` → `cq-rule-two`; move from `## Hard Rules` to `## Code Quality` section in both head and working fixtures
  - [ ] 1.2.2 `test_reintroduced_retired_id_fails`: same swap and section move
  - [ ] 1.2.3 Run the two tests individually; both must still pass
- [ ] **1.3 GREEN** — Implement block + BOM strip in `scripts/lint-rule-ids.py`:
  - [ ] 1.3.1 In `load_retired_ids`, change `stripped = line.strip()` → `stripped = line.lstrip("﻿").strip()`
  - [ ] 1.3.2 In `main()`, immediately after `retired_ids = load_retired_ids(args.retired_file)` (line 149): compute `hr_retired = sorted(r for r in retired_ids if r.startswith("hr-"))`. If non-empty, print error message to stderr and `return 1`. Place before `paths = args.paths or ...` (line 151).
  - [ ] 1.3.3 Use the exact 3-line error message from the plan
- [ ] **1.4 GREEN verification** — `python3 -m unittest tests.scripts.test_lint_rule_ids -v` exits 0 (all tests including existing)

## Phase 2 — Bypass closure

- [ ] **2.1 Lefthook** — In `lefthook.yml` `rule-id-lint`:
  - [ ] 2.1.1 `glob: "AGENTS.md"` → `glob: ["AGENTS.md", "scripts/retired-rule-ids.txt"]`
  - [ ] 2.1.2 `run: ... {staged_files}` → `run: python3 scripts/lint-rule-ids.py --retired-file scripts/retired-rule-ids.txt AGENTS.md`
  - [ ] 2.1.3 Verify: stage only `scripts/retired-rule-ids.txt` (touch a comment), run `lefthook run pre-commit`, confirm `rule-id-lint` executes. Unstage before commit.
- [ ] **2.2 CI-side invocation** — In `scripts/test-all.sh`, after existing line 54 (`run_suite "tests/scripts/lint-rule-ids" python3 -m unittest ...`), add:
  ```bash
  run_suite "scripts/lint-rule-ids-live" python3 scripts/lint-rule-ids.py --retired-file scripts/retired-rule-ids.txt AGENTS.md
  ```
- [ ] **2.3** Run `bash scripts/test-all.sh` locally → exits 0 (including both lint-rule-ids suites)

## Phase 3 — Documentation

- [ ] **3.1 Learning file** — Append `## hr-* caveat (added 2026-04-24, PR #2877)` section to `knowledge-base/project/learnings/2026-04-21-agents-md-rule-retirement-deprecation-pattern.md` (exact body in plan step 7)

## Phase 4 — Final gate

- [ ] **4.1** `lefthook run pre-commit` passes against the staged manifest (all edited files)
- [ ] **4.2** `bash scripts/test-all.sh` exits 0
- [ ] **4.3** PR body contains `Closes #2871`
- [ ] **4.4** Mark draft PR #2877 ready
