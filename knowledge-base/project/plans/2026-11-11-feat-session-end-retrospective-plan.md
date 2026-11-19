---
title: "session-end retrospective skill — fresh-context transcript analysis"
date: 2026-11-11
slug: session-end-retrospective
branch: feat-session-end-retrospective
issue: 12532
---

## Overview

Create the `session-retrospective-compound` skill that spawns a fresh-context agent to analyze session transcripts and produce workflow/agent/skill improvement proposals, new-component issues, learning captures, glossary entries, and test additions. Phased: Phase 1 = degraded-run forensics; Phase 2 = broader session-mining. User-brand-critical (single-user incident threshold).

## Implementation Phases

### Phase 1 (degraded-run forensics — builds infrastructure)

1. Wire `run-health-emit.sh` calls into one-shot and test-fix-loop (TR2 prerequisite). Emit `run_health.json` + `phase_prompts/` per run.
2. Implement fail-closed redaction gate script (`plugins/soleur/scripts/retrospective-redact.sh`) reusing gitleaks-shaped patterns; fail-closed on any scrub failure (TR3).
3. Add fresh-context forensic agent `plugins/soleur/agents/engineering/research/session-retrospective-analyst.md` (haiku floor, true fresh context — spawn via Task/subagent with only transcript path + framing note; no conversation history).
4. Create skill `plugins/soleur/skills/session-retrospective-compound/SKILL.md` following compound/compound-capture header conventions: cheap triage (standard tier) → deep analysis only if flagged; pending-operator review items via heal-skill approve-before-apply; never auto-apply including --headless.
5. Trigger: manual invocation + pipeline final-step. Stop-hook auto-trigger deferred to Phase 2 (after triage threshold calibration + cost baseline).
6. Create `forensics-proposal` label for new-component issues.
7. Add tests under `plugins/soleur/test/` (bun) and skill scripts tests following `run-health-emit.test.sh`.

### Phase 2 (broader session-mining)

1. Enable Stop-hook auto-trigger (Claude Code) once triage threshold calibrated on ≥10 real degraded runs and cost baseline measured.
2. Broader mining: workflow/agent/skill proposals, new-component issues, learning captures, glossary entries, test additions.
3. Clustering/dedup across sessions.
4. Cross-harness session-end trigger parity improvements.

## Files to Create

- `plugins/soleur/skills/session-retrospective-compound/SKILL.md`
- `plugins/soleur/agents/engineering/research/session-retrospective-analyst.md`
- `plugins/soleur/scripts/retrospective-redact.sh`
- `plugins/soleur/test/session-retrospective-redact.test.sh` (or .ts)
- `knowledge-base/project/learnings/` entries as produced by the skill

## Files to Edit

- `plugins/soleur/skills/one-shot/SKILL.md` (wire run-health emission at phase boundaries)
- `plugins/soleur/skills/test-fix-loop/SKILL.md` (wire run-health emission)
- `plugins/soleur/hooks/stop-hook.sh` (Phase 2: auto-trigger)
- `plugins/soleur/.claude-plugin`? no version key (manifest versioning rule)
- `knowledge-base/project/roadmap.md` (when promoting out of Post-MVP/Later)

## Open Code-Review Overlap

None (no open code-review issues matching these file paths at plan time).

## Acceptance Criteria

- [ ] `run-health-emit.sh` invoked by one-shot and test-fix-loop; `run_health.json` + `phase_prompts/` present after a run.
- [ ] Redaction gate fail-closes on any scrub failure; tests verify absence of secrets in output.
- [ ] Fresh-context analyst spawned with no conversation history; proposals produced as pending-operator items.
- [ ] Skill never auto-applies proposals, including under `--headless`.
- [ ] New components filed as `forensics-proposal`-labeled issues, not scaffolded in-session.
- [ ] Cross-harness triggers documented honestly (Stop hook Claude-Code-only).
- [ ] Tests pass (`bun test`, bash script tests).

## Non-Goals

- Clustering/dedup across sessions (Phase 2)
- Auto-application of any proposal
- In-session scaffolding of new agents/skills
- Real-time session-end firing on non-Claude-Code harnesses

## Research Insights

### Repo research (repo-research-analyst)
- Skills flat at `plugins/soleur/skills/<name>/SKILL.md`; compliance checklist in `plugins/soleur/AGENTS.md`.
- Closest analogs: `compound` (orchestrator, self-reported error inventory — the gap), `compound-capture` (terminal capture, YAML schema gate, route-to-definition), `heal-skill` (approve-before-apply), `eval-harness` (gated edits, verdict math).
- Run-health: `plugins/soleur/scripts/run-health-emit.sh` writes `.soleur/runs/<run-id>/run_health.json` + `phase_prompts/` (gitignored). Not yet wired into one-shot/test-fix-loop (TR2 prereq). Schema: run_id, issue, branch, harness, started_at, phases[], errors[], completed_at, reviewed_coverage.
- Stop hook: `plugins/soleur/hooks/stop-hook.sh` (Ralph loop gate) + `hooks.json`. Claude-Code-only; OpenCode has no Stop hook (completion advisory).
- Redaction: ADR-095 secret-scanning floor, gitleaks `.gitleaks.toml` (13 custom rules), fail-closed `eval-gate.cjs` / `prepush-secret-scan.sh` exit codes. Asterisk-redacted passwords canonical.
- Agent definitions: `plugins/soleur/agents/<domain>/<name>.md`, `model: inherit` (research agents pinned `haiku`). New agents/skills proposed via `forensics-proposal`-labeled issues, not in-session.
- Harness: OpenCode uses `subagent` tool with path-derived ids, `skill` tool bare id, `shell` tool. Cloud (Devin): sequential fallback + disclosure.

### Learnings research (learnings-researcher)
- Fresh-context: fork inherits pending actions; spawn fresh agent with no inherited context for independent advisory.
- Resume preserves transcripts; respawn discards them — persist report paths in fix brief.
- Redaction: fail-closed 4-layer stack (deny-list → input sanitization → pre-write sentinel → post-write verifier); redaction tests must check absence, not marker presence; per-leaf redaction insufficient for structured JSON → key-aware redaction.
- Pending-operator: boundary is possession of credentials; everything downstream is Soleur's responsibility. Solo-operator sign-off gate defaults to noop (5-panel plan-review IS the sign-off).
- Transcript mining: hook-deferred Bash calls silently end subagents (transcript says which); workflow-runtime subagents invisible to PostToolUse hooks (transcript dir is evidence channel).
- Stale worktrees: add recovery at session start, not reliability at end.

### Premise validation
- Issue #12532 OPEN, Post-MVP/Later milestone, priority/p3-low.
- Worktree `feat-session-end-retrospective` created; draft PR #12670.
- Sibling worktree `feat-12574-fresh-context-forensic-agent` exists (agent carved out).
- `run-health-emit.sh` exists but one-shot/test-fix-loop do not emit (prerequisite).
- No `session-retrospective` skill file exists yet on main.

### Property list (Phase 0.6b)
1. Degraded runs produce prompt-correlated proposals (fresh-context, not self-report).
2. Every session-end can triage cheaply; deep analysis only when warranted.
3. No structural change auto-applies (pending-operator, including --headless).
4. Output scrubbed fail-closed before persistence (raw in, scrubbed out).
5. New components filed as `forensics-proposal` issues, not scaffolded in-session.
6. Cross-harness honest triggers (Stop hook Claude-Code-only; pipeline final-step + manual universal).

### Cut list
- Auto-application of proposals (heal-skill contract forbids).
- Clustering/dedup in Phase 1 (deferred to Phase 2).
- Real-time session-end firing on non-Claude-Code harnesses (pipeline final-step + manual only).
- In-session scaffolding of new agents/skills (filed as issues).

