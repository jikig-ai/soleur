---
title: "feat(engineering): session-end retrospective skill — fresh-context transcript analysis for workflow/agent/skill improvements"
date: 2026-11-10
slug: session-retrospective-compound
branch: feat-12532-degraded-run-forensics
issue: 12532
---

## Overview

Create the `session-retrospective-compound` skill that spawns a fresh-context agent to analyze session transcripts and produce workflow/agent/skill improvement proposals, new-component issues, learning captures, glossary entries, and test additions. Triggered via Stop hook (Claude Code), pipeline final-step (all harnesses), or manual invocation. Two-tier analysis: cheap triage first, deep only if flagged. Raw transcript input with scrubbed output. All structural changes are pending-operator review items. Phased: Phase 1 = degraded-run forensics (builds infrastructure); Phase 2 = broader session-mining.