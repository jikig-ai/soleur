# Tasks — chore(ci): affected-gate follow-ups (PR-B recorder + re-price, PR-C runner leaf + heavy batteries, D5 shard regeneration)

Plan: `knowledge-base/project/plans/2026-10-02-chore-affected-gate-reprice-recorder-runner-leaf-plan.md`
Issue: #9307 (umbrella; stays open for PR 2 / PR 3). Branch: `feat-one-shot-shard-legs-reprice-recorder-runner-leaf`.

## Phase 0 — Baselines (no code change)

- 0.1 Capture base `--print-selection` streams for the README probe and the multi-path probe at the branch point
- 0.2 Record the sandbox parity fingerprint (enumerate order of the 8 keep-list labels; s1/s2 selected counts)
- 0.3 Fetch origin/main; check PR 9409 state; merge main if it landed
- 0.4 D1 census (suites using the `REPO_ROOT=$(cd ... /..)` idiom that miss a named repo file); decides whether D1 exists
- 0.5 Recorder prototype gate: static probe scan over the 24 re-price suites; count unresolvable operands

## Phase 1 — PR-B

- 1.1 Recorder `scripts/audit-suite-reads.sh` + `scripts/audit-suite-reads.test.sh` (Guard 1 rows first, RED)
  - 1.1.1 `verdict()` with classes demotable / uncovered / disqualified / unreliable
  - 1.1.2 `record` (detached clean worktree, `env -i`, `--max-load`, per-suite rows, trap cleanup)
  - 1.1.3 `--cover declared` and `--cover-from-selection`
- 1.2 D3 subcommand forms: fixture rows, skip list, `-c` payload loop
- 1.3 D2 ratchet breadth: measure forms against the 541 registrations, form table, fixture rows, baseline regeneration
- 1.4 B2/B3 re-price: recorder on the 23 demotions plus `scripts/domain-model-drift`; re-promote / demote; Round 2 in the audit doc; floor and f1 only if the count falls below 116
- 1.5 Register `scripts/audit-suite-reads` LAST in the scripts block; declared edge array at the end of the demotions block
- 1.6 D4 (conditional, cut-first): slash migration, census rule, declared-edge mint, m9
- 1.7 ADR-242 decision 17 (written last)

## Phase 2 — PR-C (gate: Phase 1 green on CI, fingerprint recorded)

- 2.1 A5: `AFFECTED_CLOSURE_LEAF_FILES` (two files), skip passes 2 and 3 for leaves, branch-scope and staged-scope fixture rows
- 2.2 Recorder on every derived row that reached the runner (`--cover-from-selection`) before accepting the bench
- 2.3 Bench declared-delta mode and retained-real-edge check
- 2.4 D1 (only if the census found a missed edge): own commit, own base, independent resolver
- 2.5 Phase C audit of the six heavy always-on batteries (default keep); status line for the three ADR-262 batteries
- 2.6 Floor / baseline / CPU factor report
- 2.7 ADR-242 decision 18

## Phase 3 — D5 (last commit)

- 3.1 Re-check PR 9409, merge main, re-capture fingerprint
- 3.2 Select five post-PR-A green main runs; `python3 scripts/regenerate-shard-manifest.py --runs 5 --write`
- 3.3 Read the predicted leg table; file the atomic-suite issue if a single suite exceeds the ceiling; paste run IDs and per-run timed-label counts in the PR body

## Phase 4 — Verification

- 4.1 Bench against per-phase bases; parity fingerprint comparison; targeted suites; `c4-count-parity`
