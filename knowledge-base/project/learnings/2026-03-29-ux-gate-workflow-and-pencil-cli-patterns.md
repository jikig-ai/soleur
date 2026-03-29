---
title: UX gate workflow patterns and Pencil CLI operational gotchas
date: 2026-03-29
category: integration-issues
tags: [ux-gate, pencil-cli, brand-guide, parallel-agents, doppler]
module: pencil-cli
synced_to: []
---

# Learning: UX Gate Workflow and Pencil CLI Patterns

## Problem

During the feat-repo-connection UX gate, multiple workflow gaps emerged:
(1) Pencil CLI auth failed because the agent didn't check Doppler for the
key, (2) Pencil CLI exports produced stale cached images after updating the
.pen file, (3) parallel specialist agents (ux-design-lead + copywriter)
produced misaligned artifacts because they worked independently, and
(4) UX artifacts were left untracked across sessions, risking data loss.

## Solution

1. **Doppler-first credential lookup:** The `PENCIL_CLI_KEY` was stored in
   Doppler (`soleur/dev` config). Setting `PENCIL_CLI_KEY="$(doppler secrets
   get PENCIL_CLI_KEY --project soleur --config dev --plain)"` before the
   `bun pencil` command resolved auth immediately.

2. **Stale export workaround:** When updating an existing .pen file, the CLI
   re-exported cached images with identical file sizes. Fix: generate a new
   .pen file from scratch (`--out new-file.pen` without `--in`), then replace
   the old file. Verify by reading the exported PNGs inline to confirm content
   matches expected text.

3. **Copy-first artifact flow:** The copy document must be the source of truth.
   Wireframes implement copy verbatim. When both are generated in parallel, a
   reconciliation review is mandatory. Better: generate copy first, then pass
   the copy doc as input to the wireframe agent.

4. **Commit artifacts incrementally:** UX artifacts (brainstorm, spec, copy,
   wireframes) should be committed after each review cycle, not left untracked
   until implementation. Laptop crashes and process kills have caused data loss
   in prior sessions.

## Key Insight

UX gate artifacts are high-effort, low-recoverability work products. Unlike
code (which can be regenerated from specs), design decisions, copy nuances,
and reviewer feedback are contextual and expensive to reproduce. The workflow
must treat them as first-class deliverables with incremental commits after
each revision cycle.

## Session Errors

1. **Pencil CLI auth: checked interactive login before Doppler** -- Recovery:
   searched Doppler configs and found the key in `soleur/dev`. Prevention:
   AGENTS.md rule to check Doppler before prompting for any credential.
   Filed as #1269.

2. **Pencil CLI stale exports** -- Recovery: deleted old exports, regenerated
   .pen from scratch with full prompt, re-exported. Prevention: always verify
   export content by reading the PNG inline after export. If file sizes match
   pre-update exports, regenerate from scratch.

3. **Pencil MCP empty document state** -- `get_editor_state` and
   `snapshot_layout` returned empty nodes for .pen files created by CLI agents.
   Recovery: used CLI for all operations. Prevention: known limitation; use
   Pencil CLI (with bun) for all wireframe operations, not MCP server.

4. **Copy-wireframe misalignment from parallel generation** -- 11+ text
   mismatches between independently generated copy doc and wireframe. Recovery:
   CMO and CPO reviews caught all mismatches in first review cycle. Prevention:
   generate copy doc first, then pass it as context to the wireframe agent.

## Tags

category: integration-issues
module: pencil-cli
