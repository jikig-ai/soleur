---
title: "Gemini CLI portability scan methodology and findings"
date: 2026-04-07
category: implementation-patterns
tags: [portability, platform-risk, gemini-cli, multi-runtime]
module: plugin-architecture
---

# Learning: Gemini CLI Portability Scan Methodology and Findings

## Problem

Soleur is a single-runtime plugin coupled to Claude Code. If Anthropic changes pricing, deprecates the plugin API, or a competitor harness gains traction, the entire product is stranded. Issue #1738 tasked investigating Gemini CLI (v0.36.0) as an alternative runtime to quantify actual porting cost versus the theoretical risk assessed in the Codex CLI scan (which found 43.4% RED components -- too expensive to pursue).

Five critical unknowns blocked any assessment: subagent support, skill chaining depth, agent directory nesting, MCP compatibility, and argument interpolation in skills.

## Solution

Three-phase methodology, each feeding the next:

1. **Source code analysis for critical unknowns.** Examined `google-gemini/gemini-cli` source (agentLoader.ts, activate-skill.ts, local-executor.ts, registry.ts) to answer 5 unknowns structurally (no runtime needed). Findings: single-level subagent nesting only, unlimited skill chaining via context injection, flat agent directories, full MCP compatibility (stdio + HTTP), no `$ARGUMENTS` interpolation in skills.

2. **Grep-based primitive scan.** Scanned all 129 Soleur plugin components for 8 Claude Code primitives (Task/subagent, Skill tool, AskUserQuestion, $ARGUMENTS, TodoWrite, WebSearch/WebFetch, hookSpecificOutput, MCP references). Classified each against Gemini CLI equivalents: GREEN (direct equivalent exists), YELLOW (equivalent with different semantics), RED (no equivalent). Result: 54.3% GREEN (70), 45.0% YELLOW (58), 0.8% RED (1). The sole RED component was compound skill (hookSpecificOutput has no Gemini CLI equivalent).

3. **Three-component proof-of-concept port.** Ported CLO agent (simple agent), compound skill (skill chaining + file I/O), and go command (router with skill dispatch). Each port validated structural compatibility and exposed the flat-directory constraint (agents cannot nest in subdirectories).

## Key Insight

**Portability scans should measure against the actual target, not a proxy.** The Codex CLI scan (43.4% RED) nearly killed the multi-runtime strategy. The Gemini CLI scan (0.8% RED) showed the problem was Codex-specific, not inherent. If we had generalized from one data point, we would have abandoned a viable hedge.

**The generalizable assessment pattern:**

- Identify critical unknowns from the target's source code before scanning (avoids wasted effort if a blocker exists at the architecture level).
- Scan all components against concrete primitives, not abstract categories.
- Port 3 representative components (simple, medium, complex) to validate the scan's GREEN/YELLOW/RED classifications.
- A single constraint (here: single-level nesting) can be a design constraint rather than a blocker if a workaround exists (restructure specialists as skills activated by the leader subagent).

**Recommendation: conditional go.** Do not invest preemptively. Maintain the portability scan as a living artifact. Invest in actual porting only when platform risk materializes (pricing changes, API deprecation, competitor harness adoption). The 0.8% RED score means porting is a weeks-not-months effort when needed.

## Session Errors

1. **Worktree creation failed/disappeared twice.** `worktree-manager.sh feature` and `worktree-manager.sh create` behaved differently; the first created a worktree that vanished on the next command. **Prevention:** Always use the `create` subcommand explicitly with `--yes` flag, then verify with `git worktree list` before starting work.

2. **npm global install permission denied.** `npm install -g @google/gemini-cli` failed because the sandbox blocks writes to system directories. **Prevention:** Use `npx` for one-shot execution, or install to `~/.local/bin` with `--prefix`. Never attempt global installs in sandboxed sessions.

3. **Wrong Gemini CLI binary path.** Expected `gemini` binary at `node_modules/.bin/gemini` but `package.json` `bin` field mapped to a different path (`dist/cli.js`). **Prevention:** Read the target package's `package.json` `bin` field before assuming binary location.

4. **Missing ~/.gemini directory.** First-run ENOENT on config directory. Gemini CLI expects `~/.gemini/` to exist but does not create it automatically on install. **Prevention:** Create `~/.gemini/settings.json` with `{}` before first invocation.

5. **No Gemini API key available.** Runtime verification was impossible; all validation was structural (source code reading, not execution). **Prevention:** For future runtime validation, provision a Gemini API key in Doppler `dev` config before starting the session.

6. **WebFetch 404 on Gemini CLI docs URLs.** `geminicli.com` URL structure did not match expectations; documentation pages returned 404. **Prevention:** Use source code as the primary reference for CLI tools; treat external docs as supplementary.

## Tags

category: implementation-patterns
module: plugin-architecture
symptoms: platform-risk assessment, cross-runtime portability, gemini-cli compatibility
