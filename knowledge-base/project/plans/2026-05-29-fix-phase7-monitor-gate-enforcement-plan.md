---
title: "Elevate the Monitor-vs-run_in_background gate out of ship Phase 7"
date: 2026-05-29
branch: feat-fix-phase7-monitor-gate-enforcement
status: complete
labels: [domain/engineering, semver:patch]
---

# Elevate the Monitor-vs-`run_in_background` gate out of ship Phase 7

## Overview

The HARD GATE "use the Monitor tool, never Bash `run_in_background` for polling"
lived only in `ship/SKILL.md` Phase 7. A compressed `/soleur:one-shot` run that
skipped invoking ship hand-rolled a backgrounded `gh pr view` merge poll —
escaping the gate (PR #4512 failure class). This change moves the rule to
always-loaded + deterministic enforcement so no run can route around it.

## Root cause

Skill-local prose gate → unenforced once the skill isn't loaded. Not elevated to
an AGENTS rule, not hook-backed. See learning
`knowledge-base/project/learnings/workflow-patterns/2026-05-29-skill-local-gates-escape-compressed-pipelines.md`.

## Changes (all four from the audit synthesis)

1. **AGENTS-core hard rule** `hr-monitor-not-run-in-background-for-polling`
   (`AGENTS.md` index + `AGENTS.core.md` body, 566B). Loads every turn.
2. **PreToolUse(Bash) hook** `.claude/hooks/background-poll-prefer-monitor.sh` +
   `.test.sh` (13 cases) + `settings.json` registration. Denies
   `run_in_background:true` + remote-poll signature; AND-gated; override marker.
3. **one-shot Step 7** ownership rule: merge/CI wait owned by ship Phase 7; no
   hand-rolling `gh pr merge`/`gh pr`/`gh run` polling; no trivial-change fast-path.
4. **schedule SKILL.md** verify-after-trigger: foreground `gh run watch` →
   Monitor-tool loop (pre-existing instance of the same gap).

## Acceptance criteria

- [x] New rule id in BOTH AGENTS.md index and AGENTS.core.md body (1 each); body ≤600B.
- [x] `lint-agents-enforcement-tags.py` exits 0 (hook + skill cites resolve).
- [x] Hook test suite green (13/13): denies bg-polls, allows builds/single-shot/local/write-loops/override.
- [x] `hookeventname-coverage.test.sh` green; `settings.json` valid JSON; hook registered.
- [x] schedule no longer prescribes foreground `gh run watch`.
- [x] Learning file written (workflow-gap durable artifact).
- [ ] Pre-existing `B_ALWAYS` budget overage filed as a separate tracking issue.

## Observability

Enforcement is build/edit-time (hook + linters), not a runtime production path —
no `## Observability` server block applies. Discoverability test (no SSH):
`bash .claude/hooks/background-poll-prefer-monitor.test.sh` and
`python3 scripts/lint-agents-enforcement-tags.py`.

## Test scenarios

None (browser/API QA N/A). Verification is the hook test + linters above.
