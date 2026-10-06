---
name: help
description: "List all available Soleur commands, agents, and skills"
argument-hint: ""
---

# Soleur Help

Display a formatted overview of all available Soleur capabilities. Read the plugin manifest to get current counts rather than relying on hardcoded values.

## Step 1: Read Plugin Manifest

Use the **Read tool** to read `${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json` to get the plugin name, description, and metadata.

**The manifest carries no `version` key** — that is deliberate, not an omission (a constant version string makes `claude plugin update` compare equal and no-op while reporting success, #7471). Do not report a version read from it. If a version is wanted, it comes from the latest plugin release tag (`gh release list --exclude-drafts --exclude-pre-releases --limit 30 --json tagName --jq '[.[] | select(.tagName | test("^v[0-9]"))][0].tagName'` — the repo also publishes `web-v*` and `zot-image-*` releases); if that is unavailable, print no version rather than guessing one.

If `CLAUDE_PLUGIN_ROOT` is not set or the path does not exist, try reading from `plugins/soleur/.claude-plugin/plugin.json` (monorepo checkout) or `~/.claude/plugins/*/soleur/.claude-plugin/plugin.json` (legacy installed path).

## Step 2: Count Components

Use the **Glob tool** to count components. Make all five calls in parallel in a single message:

1. **Count agents:** Use pattern `**/*.md` with path `${CLAUDE_PLUGIN_ROOT}/agents` -- count the returned file paths
2. **Count commands:** Use pattern `*.md` with path `${CLAUDE_PLUGIN_ROOT}/commands` -- count the returned file paths
3. **Count skills:** Use pattern `**/SKILL.md` with path `${CLAUDE_PLUGIN_ROOT}/skills` -- count the returned file paths (one SKILL.md per skill)
4. **Count agent domains:** From the agent file paths in result 1, extract the unique top-level directory names (the first path segment after `agents/`) and count them
5. **Find user-invoked skills:** Use the **Grep tool** with pattern `^disable-model-invocation: true` over `**/SKILL.md` under `${CLAUDE_PLUGIN_ROOT}/skills`, output mode `files_with_matches`. That set drives the `(type /soleur:<name>)` marker below. These skills' descriptions are absent from your skill listing, so Read each matched SKILL.md's `description:` to describe it.

If `CLAUDE_PLUGIN_ROOT` is not set or those paths do not exist, fall back to `plugins/soleur/...` (monorepo checkout) or `~/.claude/plugins/*/soleur/...` (legacy installed path).

## Step 2.5: Harness-aware command names

Detect the active harness before printing commands:

- **Claude Code:** commands use the `/soleur:` prefix (`/soleur:go`, `/soleur:sync`, `/soleur:help`). Workflow skills are invoked via the **Skill tool** (`soleur:<skill>`).
- **Grok Build:** commands are unqualified (`/go`, `/sync`, `/help`). Workflow skills are invoked via **slash commands** (`/brainstorm`, `/one-shot`, …) — not `/soleur:go`.
- **Devin CLI:** commands use the `/soleur:` prefix (`/soleur:go`, `/soleur:sync`, `/soleur:help`). Workflow skills are invoked via the same **slash commands** (`/soleur:<skill>`).
- Implementation reference: `plugins/soleur/lib/harness.ts` (`routingInstructions`, `formatSkillInvocation`).
- **Codex:** entry points are `$soleur:go`, `$soleur:sync`, and `$soleur:help`.
  Read [Codex compatibility instructions](../codex/INSTRUCTIONS.md) and resolve
  component paths from the installed plugin root. Render the Claude block below
  with Codex skill mentions and skill-loading instructions substituted. Omit the
  `(type /soleur:<name>)` user-invoked marker: Codex ignores the key (ADR-236).
  Render the HOW THE SKILLS FIT TOGETHER map verbatim.
- **Cursor CLI:** `/go` and `/sync` stay bare. Every other skill is `/soleur-<name>`, including `/soleur-help`, `/soleur-plan`, and `/soleur-review`. Cursor's `/plan`, `/help`, `/review`, and `/shell` are built-ins; do not type them for Soleur. Do not call the Skill tool, the Task tool, `run_subagent`, or AwaitShell. Slice 1 does not run hooks and does not classify the session as cursor. Read [Cursor compatibility instructions](../cursor/INSTRUCTIONS.md).

Use the matching column in Step 3 below.

<!-- The HOW THE SKILLS FIT TOGETHER map below is inspired by the ask-matt flow map in mattpocock/skills (MIT, Copyright (c) 2026 Matt Pocock). -->

## Step 3: Output the Help Reference

Present one harness-appropriate overview. Replace placeholder counts with actual values from Step 2, using the naming rules in Step 2.5.

### Claude Code

```text
Soleur - The Company-as-a-Service Platform

COMMANDS:
  /soleur:go <what you want>  The recommended way to use Soleur
  /soleur:sync                Populate knowledge-base from existing codebase
  /soleur:help                This help listing

WORKFLOW SKILLS (invoked via /soleur:go or directly via Skill tool):
  brainstorm                  Explore requirements and approaches
  plan                        Create an implementation plan
  work                        Execute the plan systematically
  review                      Run multi-agent code review
  compound                    Capture learnings from solved problems
  one-shot                    Full autonomous engineering workflow

HOW THE SKILLS FIT TOGETHER:
  Main flow:   go -> brainstorm -> plan -> work -> review -> ship -> postmerge
               (go starts at brainstorm by default; qa, when the plan needs it,
               and compound run between review and ship)
  On-ramps:    one-shot              plan through postmerge in one run (go sends
                                     fixes and scoped builds here)
               drain-labeled-backlog one-shot on one code-area cluster of a backlog
               drain-prs             takes open PRs through review to merge
               product-roadmap       its "next" step says where to enter the flow
  Standalone:  most other skills run on their own, for example the legal, flag,
               cron and operator families, invoice and community

AGENTS: [N] agents across [M] categories
  review    ([count])  Code review, security, performance, patterns
  research  ([count])  Codebase analysis, best practices, docs
  design    ([count])  Domain-driven design
  workflow  ([count])  PR comments, spec analysis

SKILLS: [N] skills
  Start here: /soleur:go <what you want> picks the right skill for you.
  The operator-* family is not routed from /soleur:go; invoke it via the Skill tool.
  Mark each skill whose SKILL.md frontmatter sets `disable-model-invocation: true` with
  `(type /soleur:<name>)`: it is user-invoked, so only the operator can run it (ADR-236).
  [List all skills found with brief descriptions, grouped by the token before the
   first hyphen: flag-*, cron-*, provision-*, release-*, resolve-*, legal-*,
   operator-*, kb-*, questionnaire-*, and so on. Order the families largest first. List skills with
   no prefix last, under the heading "Core workflow".]

MCP SERVERS:
  context7                    Framework documentation lookup
  playwright                  Wrapped browser automation (mcp__plugin_soleur_playwright__*)

Quick start: /soleur:go <what you want to do>
Full docs:   See plugins/soleur/README.md
```

### Devin CLI

```text
Soleur - The Company-as-a-Service Platform

COMMANDS:
  /soleur:go <what you want>  The recommended way to use Soleur
  /soleur:sync                Populate knowledge-base from existing codebase
  /soleur:help                This help listing

WORKFLOW SKILLS (invoked via /soleur:go or directly as /soleur:<skill>):
  brainstorm                  Explore requirements and approaches
  plan                        Create an implementation plan
  work                        Execute the plan systematically
  review                      Run multi-agent code review
  compound                    Capture learnings from solved problems
  one-shot                    Full autonomous engineering workflow

HOW THE SKILLS FIT TOGETHER:
  Main flow:   go -> brainstorm -> plan -> work -> review -> ship -> postmerge
               (go starts at brainstorm by default; qa, when the plan needs it,
               and compound run between review and ship)
  On-ramps:    one-shot              plan through postmerge in one run (go sends
                                     fixes and scoped builds here)
               drain-labeled-backlog one-shot on one code-area cluster of a backlog
               drain-prs             takes open PRs through review to merge
               product-roadmap       its "next" step says where to enter the flow
  Standalone:  most other skills run on their own, for example the legal, flag,
               cron and operator families, invoice and community

AGENTS: [N] agents across [M] categories
  review    ([count])  Code review, security, performance, patterns
  research  ([count])  Codebase analysis, best practices, docs
  design    ([count])  Domain-driven design
  workflow  ([count])  PR comments, spec analysis

SKILLS: [N] skills
  Start here: /soleur:go <what you want> picks the right skill for you.
  The operator-* family is not routed from /soleur:go; invoke it as /soleur:<skill>.
  Mark each skill whose SKILL.md frontmatter sets `disable-model-invocation: true` with
  `(type /soleur:<name>)`: it is user-invoked, so only the operator can run it (ADR-236).
  [List all skills found with brief descriptions, grouped by the token before the
   first hyphen: flag-*, cron-*, provision-*, release-*, resolve-*, legal-*,
   operator-*, kb-*, questionnaire-*, and so on. Order the families largest first. List skills with
   no prefix last, under the heading "Core workflow".]

MCP SERVERS:
  context7                    Framework documentation lookup
  playwright                  Wrapped browser automation (plugin-root .mcp.json)

Quick start: /soleur:go <what you want to do>
Full docs:   See plugins/soleur/README.md
```

### Grok Build

```text
Soleur - The Company-as-a-Service Platform

COMMANDS:
  /go <what you want>   The recommended way to use Soleur
  /sync                 Populate knowledge-base from existing codebase
  /help                 This help listing

WORKFLOW SKILLS (invoked via /go or directly via slash command):
  brainstorm            Explore requirements and approaches
  plan                  Create an implementation plan
  work                  Execute the plan systematically
  review                Run multi-agent code review
  compound              Capture learnings from solved problems
  one-shot              Full autonomous engineering workflow

HOW THE SKILLS FIT TOGETHER:
  Main flow:   go -> brainstorm -> plan -> work -> review -> ship -> postmerge
               (go starts at brainstorm by default; qa, when the plan needs it,
               and compound run between review and ship)
  On-ramps:    one-shot              plan through postmerge in one run (go sends
                                     fixes and scoped builds here)
               drain-labeled-backlog one-shot on one code-area cluster of a backlog
               drain-prs             takes open PRs through review to merge
               product-roadmap       its "next" step says where to enter the flow
  Standalone:  most other skills run on their own, for example the legal, flag,
               cron and operator families, invoice and community

AGENTS: [N] agents across [M] categories
  (same category breakdown as Claude block)

SKILLS: [N] skills
  Start here: /go <what you want> picks the right skill for you.
  The operator-* family is not routed from /go; invoke it as /<skill-name>.
  (list all skills — invoke as /<skill-name> — grouped by the token before the
   first hyphen: flag-*, cron-*, provision-*, release-*, resolve-*, legal-*,
   operator-*, kb-*, questionnaire-*, and so on. Order the families largest first. List skills with
   no prefix last, under the heading "Core workflow".)

MCP SERVERS:
  context7              Framework documentation lookup

Quick start: /go <what you want to do>
Full docs:   See plugins/soleur/README.md and knowledge-base/engineering/grok-onboarding.md
```

### Cursor CLI

```text
Soleur - The Company-as-a-Service Platform

COMMANDS:
  /go <what you want>         The recommended way to use Soleur
  /sync                       Populate knowledge-base from existing codebase
  /soleur-help                This help listing

Do not type Cursor's built-ins /plan, /help, /review, or /shell for Soleur.
Do not call the Skill tool, the Task tool, run_subagent, or AwaitShell.

WORKFLOW SKILLS (read the canonical file the stub names):
  /soleur-brainstorm          Explore requirements and approaches
  /soleur-plan                Create an implementation plan
  /soleur-work                Execute the plan systematically
  /soleur-review              Run multi-agent code review
  /soleur-compound            Capture learnings from solved problems
  /soleur-one-shot            Full autonomous engineering workflow

HOW THE SKILLS FIT TOGETHER:
  Main flow:   /go -> /soleur-brainstorm -> /soleur-plan -> /soleur-work -> /soleur-review -> /soleur-ship -> /soleur-postmerge

AGENTS: [N] agents across [M] categories
  Invoke each as /soleur-<stem>, for example /soleur-engineering-cto.

SKILLS: [N] skills
  Start here: /go <what you want> picks the right skill for you.
  /go and /sync stay bare. Every other skill is /soleur-<name>.
  Slice 1 does not run hooks and does not classify the session as cursor.

Quick start: /go <what you want to do>
Full docs:   See plugins/soleur/cursor/INSTRUCTIONS.md
```

Replace all `[N]`, `[M]`, and `[count]` placeholders with actual values from Step 2. List all skills found, not just a subset.

## Output Rules

- Keep the output compact and scannable
- Use fixed-width alignment for command names and descriptions
- Do not add emoji
- Do not truncate any commands or skills -- list everything found
