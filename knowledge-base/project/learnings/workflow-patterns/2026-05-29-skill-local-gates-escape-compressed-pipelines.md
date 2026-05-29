---
date: 2026-05-29
category: workflow-patterns
tags: [one-shot, ship, monitor, run_in_background, hooks, agents-md, enforcement, polling]
---

# A gate that lives only inside a skill is unenforced once that skill is skipped

## Incident

A `/soleur:one-shot` run for a trivial 2-line terraform change "compressed" the
pipeline — did the edit inline and skipped invoking `soleur:ship` — then
hand-rolled the PR-merge wait using the **Bash tool with `run_in_background:true`**
in a `gh pr view` poll loop. That violated the ship Phase 7 HARD GATE
("use the Monitor tool, NEVER Bash `run_in_background`"). The operator caught it.

## Root cause (structural, not "agent slipped")

The Monitor-vs-`run_in_background` rule lived in **exactly one place**:
`plugins/soleur/skills/ship/SKILL.md` Phase 7. It was:
- never elevated to an AGENTS-level rule (the sidecars loaded every turn), and
- not backed by any deterministic hook.

So a run that never *loads* ship never sees the gate. The "compress for a trivial
change" path is itself unsanctioned (one-shot says "Run these steps in order. Do
not do anything else.") — improvising it dropped the orchestrator outside the only
place the rule existed, with zero mechanical backstop. Same failure class as PR
#4512 (a backgrounded release poll that failed silently, exit 1, zero visibility).

## Principle

**If a rule matters beyond one skill's code path, it must live where every run
sees it — an AGENTS hard rule (loaded each turn) and/or a deterministic hook —
not buried in a single skill's prose.** A skill-local gate is only as strong as
the guarantee that the skill is always invoked; "compression" / fast-paths break
that guarantee silently.

## Fix shipped (this PR)

1. **AGENTS-core hard rule** `hr-monitor-not-run-in-background-for-polling` — loads
   every turn via CLAUDE.md, so it survives any pipeline compression.
2. **PreToolUse(Bash) hook** `background-poll-prefer-monitor.sh` — denies a
   `run_in_background:true` Bash call whose command is a remote-state poll
   (loop + `gh pr/run`/`curl`, or `gh run watch`/`--watch`). AND-gated to avoid
   false positives on builds, single-shot waits, local loops, write fan-outs;
   `# gate-override: background-poll-prefer-monitor` escape hatch.
3. **one-shot Step 7** now explicitly states the merge/CI wait is owned by ship
   Phase 7 and forbids hand-rolling `gh pr merge`/`gh pr`/`gh run` polling.
4. **schedule SKILL.md** verify-after-trigger: replaced a foreground `gh run watch`
   poll with a Monitor-tool loop (a pre-existing instance of the same gap).

## Meta-learning: adversarially verify subagent claims

The audit-workflow synthesis asserted a "2026-04-10 learning" had already declared
this rule at AGENTS level and that the fix would "restore" it. Verification
(`grep` of learnings + AGENTS sidecars) showed **no such learning exists** — the
claim was fabricated by the agent. The correct framing (rule was *never* elevated)
only survived because the claim was checked against the repo before being repeated.
Treat structured agent findings as hypotheses; verify load-bearing empirical claims
(file exists, rule present, status) against ground truth before acting on them.

## Pre-existing condition noted (separate)

`scripts/lint-agents-rule-budget.py` reports `B_ALWAYS` ≈ 26k bytes vs a 22k
advisory budget on `origin/main` — already over before this change, and the linter
is not wired into CI. Tracked separately; not in scope for this PR.
