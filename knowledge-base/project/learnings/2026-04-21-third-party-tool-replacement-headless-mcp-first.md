# Learning: Evaluate third-party tool replacements with headless-MCP-first test

## Problem

Founder asked whether Anthropic's new Claude Design (announced 2026-04-21) should
replace the existing Pencil MCP integration. Without an explicit evaluation
rubric, it is easy to be dazzled by a newer or more capable product and
recommend a migration that would silently break every agent-driven workflow.

The concrete case: Claude Design is strictly more capable than Pencil at some
things (multi-modal input, richer exports, Opus 4.7 vision), but it is
**GUI-only** — there is no MCP server, no CLI, no API. Every Soleur workflow
that touches design calls Pencil MCP tools programmatically
(`ux-design-lead` agent, `/soleur:frontend-design`, `/soleur:ux-audit`,
`/soleur:feature-video`, Product/UX Gate). Switching to Claude Design would
require Playwright-driving `claude.ai/design`, which is exactly the
fragility model we eliminated in `feat-pencil-headless-cli` (2026-03-24).

## Solution

When evaluating a replacement for an existing headless/MCP tool, apply this
rubric **before** weighing feature depth or model quality:

1. **Programmatic surface.** Does the candidate expose an MCP server, CLI, or
   HTTP API that an agent can call without a browser? If no, stop — it is
   not a viable replacement for a headless MCP tool, only a complement for
   human-led work.
2. **Headless/Linux.** Does it run without a GUI on our CI and agent
   runners? "Works in a browser" is not the same as "works for our agents."
3. **Committable source format.** Does it produce git-committable artefacts
   (like `.pen` files in `knowledge-base/project/specs/feat-*/designs/`)?
   Rasterised or binary exports (PDF, PPTX, Canva) break the review loop.
4. **Access model.** Can our headless/CI agents authenticate without
   interactive session state? Enterprise-disabled-by-default and
   session-cookie auth models are incompatible with agent pipelines.

If the candidate fails test 1, file a tracking issue with re-evaluation
triggers (API announcement, MCP announcement, compatible-export path) and
keep the existing tool. Do not build a Playwright MCP wrapper around a
GUI-only product — the fragility trade is almost always a net loss.

## Key Insight

"Newer, more capable" is not the same as "replaces our current tool." The
Soleur stack optimises for agent invocability; a GUI-only third-party tool
lives in a different product category no matter how good its output is.
Evaluation must begin with headless/MCP/CLI availability, not feature depth.

## Session Errors

1. **Bare-repo path read in worktree** — First `Read` call used the bare
   repo absolute path (`/home/.../soleur/knowledge-base/...`) instead of the
   worktree absolute path (`/home/.../soleur/.worktrees/feat-<name>/...`)
   and returned "file does not exist." Recovery: retried with the worktree
   path. Prevention: rule `hr-when-in-a-worktree-never-read-from-bare`
   already covers this; potential PreToolUse hook on `Read` that detects
   worktree context and rejects bare-repo paths would prevent it
   mechanically, but the detection logic (knowing which parent is a bare
   repo) is non-trivial and the violation rate is low — leave as prose rule.

## Tags

category: integration-issues
module: tooling-evaluation
