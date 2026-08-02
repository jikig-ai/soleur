# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-08-02-fix-hook-input-eval-jq-rce-plan.md
- Status: complete

### Errors
- Two `gh` calls hit transient TLS timeouts; both succeeded on retry.
- The subagent's own reproducer run created three stray `TOOL_NAME=Bash` / `FILE_PATH=` / `SESSION_ID=` files in the worktree root (the payload's trailing words reach `touch`). Removed; tree verified clean. The plan carries this as a Phase 0 constraint plus an acceptance criterion.
- Both artifacts initially picked up literal control bytes (RS/NUL/U+2028) where escape notation was intended, flagging them as binary. Sanitized and verified clean.
- `test-design-reviewer` and `code-simplicity-reviewer` returned after the first revision, forcing a second full rewrite (v2 -> v3).

### Decisions
- **Type-assert, never coerce.** The issue's first suggested fix (`tojson`) was falsified against the real guard regexes: it closes the RCE but leaves all 18 Bash-matcher hooks evaded by the identical payload, because `tojson` turns `["git","stash"]` into a string no anchored guard regex matches.
- **One posture, no silent disarm.** A hook that cannot fully parse its input returns `ask` — it never continues silently and never denies. Fail-open, the size cap, the surrogate scrub, the per-session counter and the three-status protocol were all cut once `ask` covered every failure mode.
- **Measured, not assumed.** `explode` was a 12x CPU / 4x RSS regression; `read -d` a 2.5x one; the micro-benchmark hid an ~8-16% in-situ regression that AC8 is written against. The `echo`-vs-`printf` "second bug" did not reproduce and the claim was dropped.
- **Telemetry is the real defect-2 fix.** The orphan-gate exclusion the plan originally prescribed would have deleted the only surface showing the fault; the plan instead adds a first-class aggregator counter and widens compound's filter.
- **Scope: 20 hooks + 2 mirrors across 3 commits**, with 10 advisory hooks explicitly exempted and listed. Shipping only the 10 named in the issue would have retired it while most gates stayed evadable.
- Design de-risked by a working prototype (23/23 cases, shellcheck-clean, spliced into a real hook) left in the scratchpad for `/work` to port rather than re-derive.

### Components Invoked
- `Skill: soleur:plan`, `Skill: soleur:deepen-plan`
- Agents: `Explore` x2 (test infrastructure; learnings/ADRs), `soleur:engineering:cto`, `soleur:engineering:review:security-sentinel`, `soleur:engineering:review:architecture-strategist`, `soleur:engineering:review:test-design-reviewer`, `soleur:engineering:review:code-simplicity-reviewer`, `pr-review-toolkit:silent-failure-hunter`, `general-purpose` (20-claim verify-the-negative sweep)
- Direct verification: reproducer across all 10 hooks, 7 measurement probes (delimiter/portability, extraction-design matrix, read-mechanism benchmark, in-situ hook splice, helper prototype v1/v2), `gh issue view`, `lint-agents-rule-budget.py`, deepen-plan gates 4.5-4.10
