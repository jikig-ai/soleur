# Spec: Integrate Brand-Architect into Brainstorm Workflow

**Issue:** #76
**Branch:** `feat-brainstorm-brand-routing`
**Date:** 2026-02-13

## Problem Statement

The brand-architect agent is only accessible via the Task tool (assistant-initiated). Users who try `/soleur:marketing:brand-architect` get "Unknown skill." There is no user-facing entry point for brand workshops.

## Goals

- G1: Users can reach brand-architect through `/soleur:brainstorm` when their topic is brand/marketing related
- G2: Detection uses keyword matching with user confirmation (no silent auto-routing)
- G3: Brainstorm creates worktree + issue before handing off to brand-architect
- G4: Phase 0 routing pattern is extensible for future domains without a framework

## Non-Goals

- Making brand-architect a standalone skill (slash command)
- Building a generic domain-routing framework or abstraction
- Modifying the brand-architect agent itself
- Adding other marketing agents in this PR

## Functional Requirements

- **FR1:** Brainstorm Phase 0 scans feature description for brand/marketing keywords: brand, brand identity, brand guide, voice and tone, brand workshop
- **FR2:** When keywords match, AskUserQuestion offers: "Start a brand identity workshop?" with options to accept or continue normal brainstorm
- **FR3:** If accepted, brainstorm creates worktree + GitHub issue (reusing Phase 3/3.6 logic), then invokes brand-architect via Task tool
- **FR4:** Brand guide output lands at `knowledge-base/overview/brand-guide.md` inside the worktree
- **FR5:** No brainstorm document is created for brand workshop sessions (brand guide is the deliverable)

## Technical Requirements

- **TR1:** Only `plugins/soleur/commands/soleur/brainstorm.md` is modified (single file change)
- **TR2:** New "Specialized Domain Routing" section in Phase 0, between "clear requirements" check and Phase 1
- **TR3:** Pattern is structured so adding future domain routes is copy-paste obvious
- **TR4:** Plugin version bump required (MINOR — new capability in existing command)

## Files to Modify

| File | Change |
|------|--------|
| `plugins/soleur/commands/soleur/brainstorm.md` | Add Phase 0 domain routing section |
| `plugins/soleur/.claude-plugin/plugin.json` | Version bump |
| `plugins/soleur/CHANGELOG.md` | Document change |
| `plugins/soleur/README.md` | Verify/update description |
