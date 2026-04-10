---
title: "Gemini CLI Portability Recommendation"
date: 2026-04-07
issue: 1738
---

# Recommendation: Gemini CLI as Alternative Harness

## Decision: CONDITIONAL GO

Gemini CLI is a viable second harness for Soleur with significant caveats. Invest in a **minimal Gemini CLI extension** when platform risk materializes (Anthropic restricts Max plan access or API agent usage), not preemptively.

## Evidence Summary

| Metric | Codex CLI (2026-03-10) | Gemini CLI (2026-04-07) |
|---|---|---|
| GREEN (ports as-is) | 47.5% (58/122) | 54.3% (70/129) |
| YELLOW (needs adaptation) | 7.4% (9/122) | 45.0% (58/129) |
| RED (requires rewrite) | 43.4% (53/122) | 0.8% (1/129) |
| Blockers with no equivalent | 4 (Task, Skill, AskUser, Args) | 1 (hookSpecificOutput) |
| MCP compatibility | Partial (stdio only) | Full (stdio + HTTP) |
| Subagent support | None | Yes (single-level) |
| Skill chaining | None | Yes (context injection) |

Gemini CLI is architecturally 50x closer to Claude Code than Codex CLI was. The RED percentage dropped from 43.4% to 0.8%.

## Critical Constraint

**Single-level subagent nesting.** Gemini CLI subagents cannot spawn other subagents. This breaks Soleur's core pattern: domain leader (agent) → specialist (agent). The workaround — restructuring specialists as skills activated within the leader subagent — is functional but loses:

1. **Parallel execution** — Claude Code fans out to 7+ specialists simultaneously; Gemini CLI runs them sequentially
2. **Context isolation** — specialists share the leader's conversation context, risking cross-contamination
3. **Independent tool scoping** — specialists can't have different tool access than their parent

For 6 of 8 domain leaders (those with 2-3 specialists), this is acceptable. For the CMO (7+ specialists), it degrades significantly — a single CMO session would need to sequentially load marketing strategist, copywriter, SEO analyst, etc. instructions into the same context window.

## Context Cross-Contamination Risk

The subagent-to-skill restructuring has an unverified context cross-contamination risk. When multiple specialist skills run sequentially in the same conversation context, earlier skill outputs remain visible to later skills. This means one specialist's output may be misinterpreted as instructions or context by a subsequent specialist.

**Example:** The CLO activates `legal-compliance-auditor`, which produces findings like "CRITICAL: Missing privacy policy." The CLO then activates `legal-document-generator` to draft a contributor license agreement. Because the auditor's findings are still in the conversation context, the generator may incorporate privacy policy language into the CLA — acting on the auditor's output as if it were a generation instruction.

This failure mode does not exist in Claude Code, where each specialist runs as an independent subagent with its own isolated conversation context.

### Severity

The risk scales with specialist count and output diversity. The CMO domain (7+ specialists) is most exposed — SEO analysis findings could contaminate copywriter output, or social media metrics could influence content strategy recommendations in unintended ways. Domains with 2 specialists (CLO, COO) have lower but non-zero risk.

### Mitigation Options

1. **Explicit context boundaries** — Prepend each skill activation with instructions to ignore prior conversation content ("You are starting a new task. Disregard all previous output in this conversation.")
2. **Output scrubbing** — Strip or collapse prior skill outputs before activating the next skill (requires Gemini CLI support for conversation context manipulation)
3. **Accept and document** — For domains with 2 specialists and low cross-contamination potential, accept the risk and document the expected behavior

None of these mitigations have been validated at runtime. Option 1 is the most practical but relies on model compliance, not enforcement.

### Runtime Test Case Specification

When runtime verification becomes possible (Gemini API key configured), execute the following test:

**Test: Sequential Specialist Context Isolation**

1. Activate the CLO subagent with a task requiring both specialists
2. CLO activates `legal-compliance-auditor`, which produces audit findings (e.g., "CRITICAL: Missing privacy policy", "WARNING: Terms of Service lacks arbitration clause")
3. Without clearing context, CLO activates `legal-document-generator` with an unrelated request: "Generate a contributor license agreement"
4. Inspect the generated CLA for contamination from audit findings
5. **Pass:** Generated CLA contains no references to privacy policies, GDPR, arbitration, or any audit-specific content
6. **Fail:** Generated document incorporates, references, or responds to the auditor's findings

**Reverse-direction test:** Generate a document first, then run an audit. Verify the audit does not reference or incorporate language from the generated document.

**CMO stress test:** Activate 3+ CMO specialists sequentially (e.g., SEO analyst → copywriter → social media strategist). Verify each specialist's output is independent of the previous specialists' outputs.

## What to Build (when triggered)

### Minimum Viable Gemini Extension

A `gemini-extension.json` bundling:

1. **51 GREEN agents** as `.gemini/agents/*.md` — direct port, tool name changes only
2. **12 YELLOW agents** (domain leaders) — specialists restructured as skills
3. **18 GREEN skills** as `.gemini/skills/*/SKILL.md` — direct port
4. **MCP servers** — Context7, Cloudflare, Vercel, Playwright via `mcpServers`
5. **GEMINI.md** context file — adapted from CLAUDE.md/AGENTS.md
6. **Policy rules** — adapted from settings.json hooks

### What NOT to build

- An abstraction layer that compiles to both formats — premature and not justified by the current constraint (single-level nesting makes semantic parity impossible)
- The 44 YELLOW skills — most are workflow orchestrators (brainstorm, plan, work, review, ship) that require argument passing and skill chaining. Port only the 5 core pipeline skills and accept degraded functionality.
- A separate port maintained in parallel — maintenance cost exceeds risk mitigation value at current scale

## Trigger for Investment

Invest in the Gemini CLI extension when ANY of:

1. Anthropic restricts Max plan access for Claude Code CLI usage
2. Anthropic imposes API rate limits that make agent harness usage impractical
3. A competitor ships a multi-harness plugin system that Soleur needs to match
4. Gemini CLI adds multi-level subagent support (eliminates the critical constraint)

## Estimated Effort

| Scope | Effort | Outcome |
|---|---|---|
| GREEN agents only (51) | 1-2 days | Basic agent library, no workflows |
| GREEN agents + core skills (18) | 3-4 days | Agent library + simple skills |
| Full extension (agents + 5 core pipeline skills) | 1-2 weeks | Degraded but functional workflow pipeline |
| Dual-harness abstraction layer | 4+ weeks | Full parity — not recommended |

## Hook-to-Policy Enforcement Mapping

The portability inventory identifies `hookSpecificOutput` as the sole RED blocker (no Gemini CLI equivalent). However, this understates the impact: Claude Code's `.claude/hooks/` scripts enforce 9 distinct guardrails via `hookSpecificOutput`. On Gemini CLI, enforcement must map to one of three mechanisms:

1. **Gemini CLI Policy Engine** (`.toml` tool-blocking rules) -- can block tools entirely or by pattern, but cannot inspect tool arguments
2. **Gemini CLI hooks** (stdin/stdout JSON) -- exist but use a different protocol than `hookSpecificOutput`; scripts would need rewriting but the enforcement mechanism is present
3. **Model compliance** (GEMINI.md instructions) -- advisory only, the model can ignore the instruction

### Enforcement Tiers

| # | Guard | Hook Script | Tool | Enforcement | Gemini CLI Mechanism | Classification | Notes |
|---|---|---|---|---|---|---|---|
| 1 | block-commit-on-main | guardrails.sh | Bash | Blocks `git commit` when branch is main/master | Gemini CLI hooks (rewrite) | **Degraded** | Requires rewriting to Gemini CLI hook protocol. Policy Engine cannot inspect shell command arguments to detect `git commit` specifically. Hook exists but must parse stdin JSON differently and return stdout JSON in Gemini's format, not `hookSpecificOutput`. |
| 2 | block-rm-rf-worktrees | guardrails.sh | Bash | Blocks `rm -rf` on `.worktrees/` paths | Gemini CLI hooks (rewrite) | **Degraded** | Same as above -- command argument inspection requires hook rewrite. Policy Engine's tool-blocking is too coarse (would block all shell commands). |
| 3 | block-delete-branch | guardrails.sh | Bash | Blocks `gh pr merge --delete-branch` with active worktrees | Gemini CLI hooks (rewrite) | **Degraded** | Requires hook rewrite. Needs both command parsing and worktree state inspection -- only achievable via a hook script, not policy rules. |
| 4 | block-conflict-markers | guardrails.sh | Bash | Blocks commits when staged content contains `<<<<<<<`/`=======`/`>>>>>>>` | Gemini CLI hooks (rewrite) | **Degraded** | Requires hook rewrite. Inspects `git diff --cached` output -- stateful check that cannot be expressed as a static policy rule. |
| 5 | require-milestone | guardrails.sh | Bash | Blocks `gh issue create` without `--milestone` | Gemini CLI hooks (rewrite) | **Degraded** | Requires hook rewrite. Inspects command arguments for presence of `--milestone` flag. |
| 6 | block-stash-in-worktrees | guardrails.sh | Bash | Blocks `git stash` when CWD is inside `.worktrees/` | Gemini CLI hooks (rewrite) | **Degraded** | Requires hook rewrite. Needs both command detection and filesystem path inspection. |
| 7 | worktree-write-guard | worktree-write-guard.sh | Write, Edit | Blocks file writes to main repo checkout when worktrees exist | GEMINI.md instruction | **Lost** | Gemini CLI hooks fire on shell tool usage. Write/Edit are separate tools in Claude Code but map to `write_file`/`edit_file` in Gemini CLI. Gemini CLI does not support PreToolUse hooks on file-write tools -- only shell commands. The guard must rely on model compliance via GEMINI.md instructions. |
| 8 | review-evidence-gate | pre-merge-rebase.sh | Bash | Blocks `gh pr merge` without review evidence (code-review todos, commits, or GitHub issues) | Gemini CLI hooks (rewrite) | **Degraded** | Requires hook rewrite. Complex multi-signal check (local files, git log, GitHub API) but all logic is shell-based and portable. The hook protocol change is the only barrier. |
| 9 | auto-sync-before-merge | pre-merge-rebase.sh | Bash | Merges origin/main into feature branch before `gh pr merge` | Gemini CLI hooks (rewrite) | **Degraded** | Requires hook rewrite. Performs `git fetch` + `git merge` + `git push` -- all portable shell operations. The enforcement mechanism (intercepting `gh pr merge`) needs the Gemini CLI hook protocol. |

### Classification Summary

| Classification | Count | Description |
|---|---|---|
| **Recoverable** | 0 | Policy Engine can replicate enforcement without code changes |
| **Degraded** | 8 | Gemini CLI hooks can enforce, but scripts require rewriting to the different hook protocol (stdin/stdout JSON format differs from `hookSpecificOutput`) |
| **Lost** | 1 | No hook mechanism exists for file-write tool interception; enforcement relies on model compliance only |

### Analysis

The assessment is more favorable than the inventory's RED classification implied. The Gemini CLI does have a hook system -- it is not `hookSpecificOutput`, but it serves the same purpose (intercept tool calls, inspect arguments, allow/deny). Of the 9 guardrails:

- **8 of 9 guards are degraded, not lost.** They require rewriting the hook scripts to use Gemini CLI's hook protocol (different JSON schema on stdin/stdout), but the enforcement mechanism exists. The shell logic (branch detection, conflict marker scanning, worktree inspection) is fully portable -- only the I/O wrapper changes.
- **1 of 9 guards is lost.** The worktree-write-guard intercepts Write/Edit tool calls (file operations), not shell commands. Gemini CLI's hook system appears limited to shell command interception. File-write guardrails would need to rely on model compliance via GEMINI.md instructions, which is advisory-only.
- **0 of 9 guards are recoverable via the Policy Engine.** The Policy Engine's `.toml` tool-blocking operates at the tool level (block `run_shell_command` entirely), not at the argument level (block `run_shell_command` only when the command contains `git commit` on `main`). None of Soleur's guardrails are simple tool blocks -- they all require argument or state inspection.

### Effort Impact

The 8 degraded hooks add ~1 day to the Gemini CLI extension effort (rewriting the I/O wrapper while keeping shell logic). This should be added to the "Full extension" row in the estimated effort table. The 1 lost hook (worktree-write-guard) is a known-accepted risk -- agents writing to the wrong path is a workflow inconvenience, not a data loss vector.

## Follow-up Issues

If proceeding to build:

1. Create issue: "feat: build Gemini CLI extension with GREEN agents and core skills"
2. Create issue: "feat: restructure domain leaders for single-level subagent constraint"
3. Monitor: google-gemini/gemini-cli for multi-level subagent support (would change the equation)

## References

- Portability inventory: `knowledge-base/project/specs/gemini-cli-portability/inventory.md`
- Critical unknowns verification: `knowledge-base/project/specs/gemini-cli-portability/critical-unknowns.md`
- PoC results: `knowledge-base/project/specs/gemini-cli-portability/poc-results.md`
- Codex portability inventory: `knowledge-base/project/specs/feat-codex-portability-inventory/inventory.md`
- Platform risk learning: `knowledge-base/project/learnings/2026-02-25-platform-risk-cowork-plugins.md`
