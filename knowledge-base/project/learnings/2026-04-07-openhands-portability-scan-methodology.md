# Learning: OpenHands Portability Scan Methodology

## Problem

Needed to assess Soleur portability to OpenHands (third platform after Codex and Gemini CLI). The existing Codex scan methodology (10 primitives, grep-based) needed adaptation for a platform with fundamentally different capability levels.

## Solution

Reused the same 10-primitive grep scan with a "delta" overlay showing how each component's classification shifts across all three platforms. Key methodological improvements over the Codex scan:

1. **Broader grep patterns for agent spawning** — The Codex scan used narrow patterns (`Task tool`, `subagent_type`). For cross-platform analysis, broader patterns (`spawn.*agent`, `parallel.*agent`, `fan-out`) catch implicit delegation that doesn't reference specific tool names.

2. **Three-way comparison table** — Instead of standalone classification, each component shows its status on all three platforms. This immediately reveals which platform-specific constraints drive each classification.

3. **Primitive mapping table with delta column** — Each primitive's OpenHands equivalent is compared to the Gemini CLI equivalent, showing where OpenHands is better (subagents, hooks) or worse (no ask_user, no write_todos).

4. **Critical unknowns gated by verification method** — Unlike the Gemini CLI analysis (verified against source code), OpenHands unknowns are flagged as "docs-only confidence" requiring PoC verification before investment.

## Key Insight

When running portability scans across multiple platforms, the spec directory naming should be consistent (all use `<platform>-portability/` not `feat-<platform>-portability-inventory/`). The Codex spec lives at `feat-codex-portability-inventory/` while Gemini CLI and OpenHands use `gemini-cli-portability/` and `openhands-portability/` respectively. Also: always search `specs/` not just `brainstorms/` when looking for prior art — the Gemini CLI analysis was missed initially because the glob only searched brainstorms.

## Session Errors

1. **Gemini CLI portability directory missed by initial search** — Glob searched `brainstorms/*gemini*` but the artifact was in `specs/gemini-cli-portability/`. Recovery: User corrected the path. Prevention: When searching for prior art, glob both `brainstorms/` and `specs/` directories.

2. **OpenHands docs 404 on initial fetch** — Docs had been restructured from `/modules/usage/` to `/sdk/arch/` paths. Recovery: Fetched the docs index (`llms.txt`) to discover correct paths. Prevention: Always fetch the docs index/sitemap first before deep-linking into docs pages.

3. **P3 scan returned too few results** — Initial grep for `subagent_type|Agent tool|TaskCreate|run_in_background` found only 7 files (should have been 27+). Recovery: Broadened to include `spawn.*agent|parallel.*agent`. Prevention: Use the broader pattern set from the start — the Codex learning already documented this (grep returns exit code 1 on no match, use `|| true`).

## Tags

category: implementation-patterns
module: plugin-architecture
