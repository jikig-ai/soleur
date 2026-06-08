---
title: Portability Scans — Re-verify Target Architecture and Watch the Agent Carrier Format
date: 2026-06-08
category: engineering
tags: [implementation-patterns, plugin-architecture, portability]
issue: 5034
---

# Learning: Portability Scans Must Re-verify the Target's Current Architecture, and GREEN% Is Driven by Agent Carrier Format

## Problem

Running the fourth platform portability scan (`deepagents`, after Codex CLI #509, Gemini CLI #1738, OpenHands #1770). Two assumptions baked into the brief would have produced a wrong analysis if accepted:

1. **Stale category framing.** The brief framed deepagents as "a LangChain *library*, a different architectural category from the interactive harnesses." That was true at some earlier snapshot but false by 2026-06: deepagents v0.6.8 had shipped `deepagents-code`/`dcode`, an interactive terminal harness self-described as *"similar to Claude Code,"* with the repo tagline *"the batteries-included agent harness."* Had the scan accepted the "library, different category" premise, it would have under-scoped deepagents as a non-harness and skipped the harness-level comparison entirely.

2. **Implicit "zero-RED ≈ cheap port" assumption.** OpenHands was zero-RED and cheap to port (1-2 wk). The natural prior is that another zero-RED target is similarly cheap. False.

## Solution

Two methodology rules for the next portability scan:

### Rule 1 — Re-verify the target's current architecture before scanning; a platform's *category* can change between assessments.

A platform analyzed N months ago may have crossed the library↔harness boundary, gained/lost a plugin system, or added a structured-prompt primitive. Always WebFetch the current README + version + docs index FIRST and re-confirm the category, not just the per-primitive equivalents. The premise-correction is cheap (one fetch) and load-bearing — it determines whether you scan against an SDK, a harness, or both.

### Rule 2 — GREEN% is governed by the agent *carrier format*, not by primitive coverage. Zero-RED ≠ cheap port.

deepagents is the second zero-RED target (every Soleur primitive has an equivalent) yet has the **lowest GREEN% of any platform** (19.7% vs OpenHands' 46.5%). The entire delta is one fact: deepagents subagents are **Python `SubAgent` dicts** and there is **no markdown-agent loader**, so all 67 markdown agents flip GREEN→YELLOW (carrier rewrite), even though their prose system prompts port verbatim. Meanwhile skills port *better* than on any prior target because the `SKILL.md` carrier is identical.

**The classification driver is: does the target read the same carrier file (markdown agent / SKILL.md), or must the component be re-authored in another language/format?** Primitive coverage (does `task`/`write_todos`/MCP exist?) determines RED-vs-not; carrier format determines GREEN-vs-YELLOW. Separate the two axes explicitly in the inventory, or you will conflate "every capability exists" with "everything ports cheaply."

Corollary: report the verdict **by goal**, not as a single go/no-go. deepagents is no-go for a mechanical port (carrier rewrite + no plugin distribution → 6-10 wk) but conditional-go for a strategic rebuild (model-agnostic, durable checkpointer persistence). OpenHands wins harness-redundancy; deepagents wins model-agnosticism. A single verdict hides this.

## Key Insight

When the prior scans all share a property (markdown agents → GREEN), that property becomes an invisible assumption. The first target that breaks it (Python-dict agents) tanks GREEN% without adding a single RED. Audit the *carrier format* as a first-class primitive row in the mapping table — this scan added an explicit "Agent authoring format" row, which is the row that explains the whole result.

## Session Errors

1. **Stale "different category" premise in the brief.** Recovery: WebFetch'd the deepagents README/docs first (per brainstorm Phase 1.0 external-platform verification), discovered `dcode`, corrected the framing before classifying. Prevention: Rule 1 above — re-verify target architecture every scan.
2. **`platform-portability-comparison.md` edit failed "file not read."** Read the bare-root copy at session start, then edited the worktree copy — different tracked path (`hr-when-in-a-worktree-never-read-from-bare`). Recovery: Read the worktree copy first. Prevention: after worktree creation, all reads/edits use the worktree path; never carry a bare-root Read into a worktree Edit.

## Tags

category: implementation-patterns
module: plugin-architecture
