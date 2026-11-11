---
name: session-retrospective-compound
description: This skill should be used when running session-end retrospectives that analyze transcripts and produce improvement proposals.
---

# Skill: session-retrospective-compound

Session-end retrospective that mines a session transcript via a **fresh-context agent** and emits improvement proposals as pending-operator review items. Never auto-applies, including under `--headless`.

## Trigger (tiered, cross-harness)

- **Claude Code:** Stop hook (`hooks/stop-hook.sh`) auto-fires at true session end (Phase 2).
- **All harnesses:** Pipeline skills invoke as their final step.
- **All harnesses:** Manual invocation (`/session-retrospective-compound`) anytime.

## Input & cost control

- **Two-tier trigger:** cheap triage agent (standard tier) decides whether deep analysis is warranted (errors, operator corrections, tool failures, abandoned approaches, long duration). Deep forensic analysis runs only if triage flags value.
- **Input:** Raw transcript for maximum signal fidelity (executing agents already saw the same data).
- **Output:** Scrubbed by a fail-closed redaction gate before persistence (raw in, scrubbed out).

## Phased delivery

- **Phase 1:** Degraded-run forensics — fresh-context agent + run-health ledger + pending-operator proposals on errored runs.
- **Phase 2:** Broader session-mining — every session end, raw transcript, workflow/agent/skill proposals + new-component issues + learnings/glossary/tests.

## Execution Flow

### Phase 0: Setup

Load `CLAUDE.md` if present. Verify a usable git repo. Determine harness (Claude Code / OpenCode / Devin / Grok).

### Phase 1: Triage

Spawn the fresh-context analyst (`engineering/research/session-retrospective-analyst`) with only the transcript path + framing note. No conversation history. The analyst runs cheap triage and returns whether deep analysis is warranted plus any flagged signals.

### Phase 2: Deep analysis (only if triaged)

If triage flags value, spawn deep analysis. Produce proposals:

1. Workflow/agent/skill improvement proposals — pending-operator review items (heal-skill approve-before-apply contract).
2. New-component proposals — filed as GitHub issues labeled `forensics-proposal`.
3. Learning captures — compound-style institutional knowledge.
4. Glossary entries — via kb-glossary.
5. Test additions — for failures that lacked tests.

### Phase 3: Redaction gate (fail-closed)

Run [scripts/retrospective-redact.sh](./scripts/retrospective-redact.sh) on all proposal text before persistence. If scrub fails, block persistence and report. Never auto-apply, including under `--headless`.

### Phase 4: Surface

Surface pending-operator review items. In cloud mode, run inline with `Reviewed-Coverage: sequential-fallback` disclosure.

## Non-Goals

- Auto-application of any proposal
- In-session scaffolding of new agents/skills
- Real-time session-end firing on non-Claude-Code harnesses (Phase 1: pipeline final-step + manual only)
