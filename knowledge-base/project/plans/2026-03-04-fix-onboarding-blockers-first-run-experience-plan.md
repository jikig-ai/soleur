---
title: "fix: onboarding blockers for first-time external users"
type: fix
date: 2026-03-04
semver: patch
---

# Fix Onboarding Blockers for First-Time External Users

## Enhancement Summary

**Deepened on:** 2026-03-04
**Sections enhanced:** 6 (P0 hook implementation, P1 docs restructure, P2 routing, SpecFlow, MVP, Dependencies)

### Key Improvements

1. **Corrected SessionStart hook output format** -- the original plan used `systemMessage` under `hookSpecificOutput`, but the Claude Code API uses `additionalContext` for SessionStart hooks. This would have caused a silent failure where the welcome message never appears.
2. **Added `startup` matcher** to prevent welcome message from firing on resume/clear/compact events -- only on genuine new sessions.
3. **Fixed `.gitignore` gap** -- `.claude/soleur-welcomed.local` is not covered by the current `.gitignore` (only `.claude/settings.local.json` is listed). Added explicit gitignore entry requirement.
4. **Replaced inline CSS with component class** -- the "Try this first" callout used `style="border-left: ..."` which violates the constitution rule about adding CSS classes to `@layer components` instead of inline styles.
5. **Added error handling to welcome hook** -- sentinel file creation can fail silently in constrained environments. Added trap-based error suppression.
6. **Expanded routing edge case coverage** -- added 4 additional test scenarios for intent disambiguation.

### New Considerations Discovered

- SessionStart hooks fire on `startup`, `resume`, `clear`, and `compact` events. Without a `startup` matcher, the welcome message would reappear after every `/clear` or context compaction.
- The `go.md` command uses LLM-based semantic intent classification, not keyword substring matching. The "generate" intent should be described semantically, not as a keyword list -- per constitution: "prefer semantic assessment questions over keyword substring matching."
- The existing brainstorm Phase 0.5 domain config table already handles routing for all 8 domains. The go command's generate intent only needs to route to brainstorm; brainstorm's domain detection handles the rest.

## Overview

Three onboarding blockers prevent a stranger from having a good first-run experience after installing Soleur. These were identified in the product strategy onboarding audit (issue #430) and tracked in issue #432. The blockers are: (P0) no post-install guidance, (P1) Getting Started page structure issues, and (P2) `/soleur:go` routing gap for non-engineering tasks.

## Problem Statement

A new user who runs `claude plugin install soleur` gets zero feedback. They must already know to type `/soleur:go` or `/soleur:help`. The Getting Started page separates engineering and non-engineering workflows into two tiers, creating a misleading impression that non-engineering features are secondary. The `go` command's 3-intent model (explore/build/review) forces non-engineering tasks like "generate our privacy policy" through the brainstorm flow rather than routing directly to the appropriate domain skill.

## Proposed Solution

### P0: Post-install guidance via SessionStart hook + Getting Started callout

**Research finding:** Claude Code's plugin spec does **not** support PostInstall hooks. The supported hook events are: SessionStart, UserPromptSubmit, PreToolUse, PermissionRequest, PostToolUse, PostToolUseFailure, Notification, SubagentStart, SubagentStop, Stop, TeammateIdle, TaskCompleted, ConfigChange, WorktreeCreate, WorktreeRemove, PreCompact, SessionEnd. The feature request for PostInstall/PostUninstall hooks is tracked in [anthropics/claude-code#9394](https://github.com/anthropics/claude-code/issues/9394) (open).

**Two-pronged approach:**

1. **SessionStart hook (one-time welcome):** Add a SessionStart hook to `plugins/soleur/hooks/hooks.json` with a `startup` matcher (so it only fires on new sessions, not on resume/clear/compact). The hook checks for a sentinel file (`.claude/soleur-welcomed.local`). On first session after install (no sentinel), the hook outputs additional context for Claude: "Soleur installed. Run /soleur:sync to analyze your project, or /soleur:help to see all commands." Then creates the sentinel file so the message only appears once. Subsequent sessions skip the hook silently.

2. **"After Installing" section on Getting Started page:** Add a prominent callout section immediately after the Installation code block, telling users their recommended first action is `/soleur:sync` for existing projects or `/soleur:go` for new ones. This catches users who miss the SessionStart message or who read the docs site directly.

**Files:**

- `plugins/soleur/hooks/hooks.json` -- add SessionStart hook entry with `startup` matcher
- `plugins/soleur/hooks/welcome-hook.sh` -- new script (sentinel check + welcome message using `additionalContext`)
- `plugins/soleur/docs/pages/getting-started.md` -- add "After Installing" section
- `.gitignore` -- add `.claude/soleur-welcomed.local` entry

#### Research Insights (P0)

**SessionStart hook API (from Claude Code docs):**

- SessionStart hooks run on 4 event types: `startup` (new session), `resume` (continued session), `clear` (`/clear`), `compact` (context compaction). Use `"matcher": "startup"` to fire only on new sessions.
- For SessionStart, any text printed to stdout is added as context that Claude can see. JSON output with `hookSpecificOutput.additionalContext` is the structured way to inject context.
- The `systemMessage` field on `hookSpecificOutput` shows a warning to the user but is NOT the correct field for SessionStart context injection -- use `additionalContext` instead.
- `CLAUDE_ENV_FILE` is available in SessionStart hooks for persisting environment variables across the session.
- Exit code 0 = success (stdout parsed for JSON). Exit code 2 = blocking error (stderr shown to user). Any other code = non-blocking error (continue).

**Sentinel file considerations:**

- `.claude/soleur-welcomed.local` uses the `.local` convention but is NOT covered by the current `.gitignore` (which only has `.claude/settings.local.json`). Must add an explicit entry.
- The sentinel is per-project (relative path), so users who install Soleur in multiple projects get the welcome once per project. This is correct behavior.
- If `.claude/` directory does not exist, `mkdir -p` creates it. If the filesystem is read-only, the hook should fail gracefully (exit 0 with no output, no welcome).

### P1: Getting Started page restructure

1. **Position `/soleur:sync` as Step 1:** Add a "First Steps" section after install that positions `/soleur:sync` as the recommended first action for existing projects, with `/soleur:go` as the follow-up.

2. **Merge workflow sections:** Combine "Common Workflows" and "Beyond Engineering" into a single "Example Workflows" section. Interleave engineering and non-engineering examples rather than segregating them. This removes the two-tier impression.

3. **Add "Try this first" callout:** Add a new `.callout` CSS class to `style.css` under `@layer components` for a visually distinct callout. Do NOT use inline styles (constitution rule: "Add CSS classes to `style.css` `@layer components` instead of inline styles in Nunjucks templates").

**Files:**

- `plugins/soleur/docs/pages/getting-started.md`
- `plugins/soleur/docs/css/style.css` -- add `.callout` class to `@layer components`

#### Research Insights (P1)

**Docs site patterns (from learnings):**

- Reuse existing CSS classes (`.page-hero`, `.catalog-grid`, `.component-card`, `.category-section`) where possible -- the docs-site learnings emphasize minimal custom CSS.
- The `.command-item` class already provides the card-like appearance. The `.callout` class needs only a left border accent and slightly different background.
- No existing callout/alert/tip classes exist in `style.css`. A new `.callout` class is needed.
- The page uses markdown inside HTML sections (`<section class="content"><div class="prose">`) -- markdown is rendered by Eleventy's markdown pipeline within this wrapper.
- Per the adding-docs-pages pattern, use existing HTML structure patterns. The page is `.md` not `.njk`, so template features are limited.

**Information architecture (from constitution):**

- "Audit information architecture separately from visual polish -- check navigation order matches user journey" -- the merged workflow section should order examples by likelihood of first use, not by domain.
- Suggested order: sync (first action) -> build a feature -> fix a bug -> generate legal docs -> define brand -> review PR. This follows the new-user journey from onboarding through exploration.

### P2: `/soleur:go` routing gap for non-engineering tasks

The current `go.md` has 3 intents: explore (brainstorm), build (one-shot), review (review). A user typing "generate our privacy policy" matches "build" because of the word "generate", routing to one-shot which treats it as an engineering task. The correct route is through brainstorm's domain detection (Phase 0.5) which recognizes legal domain and routes to the CLO.

**Fix: Add a "generate/create" intent** that detects domain-specific generation requests and routes through brainstorm with a hint that domain detection should prioritize direct routing.

The current routing table becomes:

| Intent | Trigger Signals | Delegates To |
|--------|----------------|--------------|
| explore | Questions, "brainstorm", "think about", "let's explore", vague scope, no clear deliverable | `soleur:brainstorm` skill |
| build | Bug fix, feature request, issue reference (#N), clear engineering requirements, "fix", "add", "implement", "build" -- AND the target is code, infrastructure, or technical implementation | `soleur:one-shot` skill |
| review | "review PR", "check this code", "review #N", PR number reference | `soleur:review` skill |
| generate | The user wants to create a non-code business artifact -- legal documents, brand guides, policies, reports, strategies, marketing content, financial plans. Distinguished from "build" by the artifact type: if the output is a document or business deliverable rather than code/infrastructure, this is the correct intent. | `soleur:brainstorm` skill (domain detection routes to correct leader) |

The key change: "generate" intent signals are distinguished from "build" by checking whether the target is a code artifact or a business artifact. "Generate a REST API" maps to build. "Generate our privacy policy" maps to generate (which routes through brainstorm's domain detection).

**Why brainstorm and not a direct skill?** Brainstorm's Phase 0.5 domain detection already has the full routing table for all 8 domains. Adding a parallel routing system in `go.md` would duplicate this logic. Instead, the generate intent routes to brainstorm with context that signals "this is a domain-specific generation request" so brainstorm can fast-track through domain detection without the full exploration flow.

**Files:**

- `plugins/soleur/commands/go.md` -- add generate intent row, update classification logic

#### Research Insights (P2)

**Routing architecture (from learnings):**

- Per `2026-02-22-simplify-workflow-command-routing.md`: The go command was deliberately reduced from 7 intents to 3. Adding a 4th intent (generate) is a minimal extension that maintains the thin-router philosophy.
- Per `2026-02-22-simplify-workflow-thin-router-over-migration.md`: "The simplification users want is in the experience (fewer entry points), not the architecture (fewer files)." The generate intent improves the experience without architectural changes.
- Per `2026-02-13-brainstorm-domain-routing-pattern.md`: "Route through an existing command rather than creating a new skill or command. The brainstorm command becomes a router." This validates routing generate through brainstorm.
- Per `2026-02-22-domain-prerequisites-refactor-table-driven-routing.md`: Brainstorm's domain routing was refactored to a table-driven config. Adding a new domain now requires one table row. The go command should NOT duplicate this table.

**Semantic intent classification (from constitution):**

- "Prefer semantic assessment questions over keyword substring matching" -- the go command uses LLM-based classification, not grep. The intent description should be semantic ("the user wants to create a non-code business artifact") rather than a keyword list ("generate", "create", "draft", "write"). The LLM understands intent from context, not from trigger words.
- The existing go.md uses trigger signal keywords as guidance for the LLM's semantic understanding, not as literal matching rules. The generate intent should follow this same pattern.

**Step 4 delegation (from current go.md):**

- The generate intent delegates to brainstorm with the original user input text. Brainstorm's Phase 0.5 domain assessment then detects the relevant domain (legal, marketing, etc.) and routes to the appropriate domain leader.
- The user input should be passed unmodified -- brainstorm does its own parsing.

## Acceptance Criteria

- [x] P0: First session after install displays a welcome message with `/soleur:sync` and `/soleur:help` suggestions
- [x] P0: Welcome message only appears once (sentinel file prevents repeats)
- [x] P0: Welcome message does NOT appear on resume/clear/compact (only on `startup` sessions)
- [x] P0: Getting Started page has an "After Installing" callout section immediately after the install code block
- [x] P0: `.gitignore` includes `.claude/soleur-welcomed.local` entry
- [x] P1: "Common Workflows" and "Beyond Engineering" merged into a single "Example Workflows" section
- [x] P1: `/soleur:sync` positioned as the first recommended action after install
- [x] P1: "Try this first" callout uses a CSS class (no inline styles)
- [x] P2: `/soleur:go generate our privacy policy` routes through brainstorm domain detection to CLO, not through one-shot
- [x] P2: `/soleur:go generate a REST API` still routes to one-shot (build intent)
- [x] P2: Ambiguous inputs still prompt the user to choose

## Test Scenarios

- Given a fresh install with no `.claude/soleur-welcomed.local` file, when a new session starts (`startup`), then the welcome message appears as additional context and the sentinel file is created
- Given a previous session has already shown the welcome, when a new session starts, then no welcome message appears
- Given a session was resumed (`/resume`), when SessionStart fires, then no welcome message appears (matcher only matches `startup`)
- Given a context compaction event, when SessionStart fires, then no welcome message appears
- Given the Getting Started page, when a user reads it, then engineering and non-engineering workflows appear in a single unified section
- Given the Getting Started page, when a user reads it, then `/soleur:sync` is positioned as Step 1 after install
- Given `/soleur:go generate our privacy policy`, when intent is classified, then it routes to brainstorm (not one-shot) and domain detection identifies legal domain
- Given `/soleur:go generate a REST API`, when intent is classified, then it routes to one-shot (build intent)
- Given `/soleur:go write a blog post`, when intent is classified, then it routes to brainstorm and domain detection identifies marketing domain
- Given `/soleur:go fix the login bug`, when intent is classified, then it routes to one-shot (build intent, unchanged behavior)
- Given `/soleur:go create a new React component`, when intent is classified, then it routes to one-shot (build intent -- code artifact)
- Given `/soleur:go draft our pricing strategy`, when intent is classified, then it routes to brainstorm (generate intent -- business artifact)
- Given `/soleur:go write tests for the auth module`, when intent is classified, then it routes to one-shot (build intent -- code artifact)
- Given `/soleur:go help me think about our sales approach`, when intent is classified, then it routes to brainstorm (explore intent)

## Non-goals

- **Full PostInstall hook implementation** -- that requires upstream changes to Claude Code plugin spec (tracked in anthropics/claude-code#9394). The SessionStart hook is a pragmatic workaround.
- **Rewriting brainstorm's domain detection** -- the existing Phase 0.5 detection works well. The fix is in `go.md` routing, not in brainstorm internals.
- **Adding new skills for non-engineering domains** -- the existing domain leader agents (CLO, CMO, etc.) and brainstorm routing handle domain-specific work. No new skills needed.
- **Redesigning the `/soleur:go` command architecture** -- per the learning in `knowledge-base/project/learnings/2026-02-22-simplify-workflow-command-routing.md`, the 3-intent model was deliberately reduced from 7. Adding one more intent (generate) is a minimal extension, not a redesign.
- **Adding "generate" intent support inside brainstorm itself** -- brainstorm's Phase 0.5 domain detection already handles all domain routing via its table-driven config. No changes to brainstorm needed.

## MVP

### plugins/soleur/hooks/welcome-hook.sh

```bash
#!/usr/bin/env bash
set -euo pipefail

# --- Sentinel Check ---
# Sentinel file tracks whether the welcome message has been shown.
# Uses .local suffix to stay gitignored; per-project (relative path).
SENTINEL_FILE=".claude/soleur-welcomed.local"

if [[ -f "$SENTINEL_FILE" ]]; then
  # Already welcomed -- allow session start without output
  exit 0
fi

# --- First-Time Welcome ---
# Create sentinel file. If this fails (read-only filesystem, permissions),
# the welcome message will repeat next session -- acceptable degradation.
mkdir -p .claude 2>/dev/null || true
touch "$SENTINEL_FILE" 2>/dev/null || true

# Output JSON with additional context for Claude.
# SessionStart uses additionalContext (not systemMessage) to inject context
# that Claude can see and act on.
cat <<'WELCOME_JSON'
{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": "Welcome to Soleur! This appears to be the first session with Soleur installed. Suggest the user run /soleur:sync to analyze their project, or /soleur:help to see all available commands."
  }
}
WELCOME_JSON

exit 0
```

### plugins/soleur/hooks/hooks.json (updated)

```json
{
  "description": "Soleur plugin hooks",
  "hooks": {
    "SessionStart": [
      {
        "matcher": "startup",
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/hooks/welcome-hook.sh"
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/hooks/stop-hook.sh"
          }
        ]
      }
    ]
  }
}
```

### plugins/soleur/commands/go.md (Step 2 intent table update)

The updated classification table in Step 2:

```markdown
| Intent | Trigger Signals | Delegates To |
|--------|----------------|--------------|
| explore | Questions, "brainstorm", "think about", "let's explore", vague scope, no clear deliverable | `soleur:brainstorm` skill |
| build | Bug fix, feature request, issue reference (#N), clear engineering requirements, "fix", "add", "implement", "build" -- AND the target is code, infrastructure, or technical implementation | `soleur:one-shot` skill |
| generate | The user wants to produce a non-code business artifact: legal documents, brand guides, policies, reports, strategies, marketing content, financial plans, or similar business deliverables. Distinguished from "build" by artifact type (document vs. code). | `soleur:brainstorm` skill |
| review | "review PR", "check this code", "review #N", PR number reference | `soleur:review` skill |
```

Step 4 delegation updated:

```markdown
- explore: `skill: soleur:brainstorm`
- build: `skill: soleur:one-shot`
- generate: `skill: soleur:brainstorm`
- review: `skill: soleur:review`
```

### plugins/soleur/docs/css/style.css (new .callout class)

Add to `@layer components`:

```css
  /* Callout box for important guidance */
  .callout {
    padding: var(--space-4) var(--space-5);
    background: var(--color-bg-secondary);
    border-radius: 8px;
    border-left: 3px solid var(--color-accent);
    margin: var(--space-4) 0;
  }
  .callout code { font-weight: 600; color: var(--color-accent); }
  .callout strong { color: var(--color-text); }
```

### plugins/soleur/docs/pages/getting-started.md (restructured)

Key structural changes:

1. Add "After Installing" callout using `.callout` class:

```html
<div class="callout">
  <strong>Existing project?</strong> Run <code>/soleur:sync</code> to analyze your codebase and populate the knowledge base.<br>
  <strong>Starting fresh?</strong> Run <code>/soleur:go</code> and describe what you need.
</div>
```

2. Merge "Common Workflows" and "Beyond Engineering" into "Example Workflows" with interleaved examples:

```html
## Example Workflows

<div class="commands-list">
  <div class="command-item">
    <code>Building a Feature</code>
    <p>/soleur:go build [feature] &rarr; brainstorm &rarr; plan &rarr; work &rarr; review &rarr; compound</p>
  </div>
  <div class="command-item">
    <code>Generating Legal Documents</code>
    <p>/soleur:go generate legal documents &rarr; Terms, Privacy Policy, GDPR Policy, and more</p>
  </div>
  <div class="command-item">
    <code>Fixing a Bug</code>
    <p>/soleur:go fix [bug] &rarr; autonomous fix from plan to PR</p>
  </div>
  <div class="command-item">
    <code>Defining Your Brand</code>
    <p>/soleur:go define our brand identity &rarr; interactive workshop producing a brand guide</p>
  </div>
  <div class="command-item">
    <code>Reviewing a PR</code>
    <p>/soleur:go review &rarr; multi-agent review on existing PR</p>
  </div>
  <div class="command-item">
    <code>Validating a Business Idea</code>
    <p>/soleur:go validate our business idea &rarr; 6-gate validation workshop</p>
  </div>
  <div class="command-item">
    <code>Tracking Expenses</code>
    <p>/soleur:go review our expenses &rarr; routed to ops-advisor agent</p>
  </div>
</div>
```

### .gitignore (new entry)

Add after the `.claude/settings.local.json` line:

```text
.claude/soleur-welcomed.local
```

## SpecFlow Analysis

### SessionStart hook edge cases

- **Multiple plugins with SessionStart hooks:** Claude Code runs all SessionStart hooks from all plugins. Soleur's hook must not interfere with other plugins' hooks. The sentinel file is namespaced (`soleur-welcomed.local`) to avoid collisions.
- **Sentinel file location:** `.claude/soleur-welcomed.local` is relative to the project directory. A user installing Soleur in multiple projects gets the welcome once per project, which is correct behavior.
- **Hook output format:** SessionStart hooks use `hookSpecificOutput.additionalContext` to inject context that Claude can see. The `systemMessage` field is for warnings shown to the user, not for context injection. Using the wrong field would cause a silent failure.
- **Matcher filtering:** SessionStart supports 4 matcher values: `startup`, `resume`, `clear`, `compact`. Without a `startup` matcher, the hook fires on every session event including context compaction, causing the sentinel check to run dozens of times per session. Using `"matcher": "startup"` limits execution to genuine new sessions.
- **`.gitignore` compliance:** The sentinel file uses `.local` suffix but `.gitignore` only covers `.claude/settings.local.json` specifically -- NOT all `.local` files. Must add explicit `.claude/soleur-welcomed.local` entry.
- **Error handling:** `mkdir -p` and `touch` failures (read-only filesystem, permissions) are suppressed with `|| true`. The hook still exits 0, so the session continues. Worst case: welcome message repeats on next session.
- **Hook input:** SessionStart provides `session_id`, `transcript_path`, `cwd`, `permission_mode`, `source`, and `model` on stdin as JSON. The welcome hook does not need to parse this input -- it only checks the sentinel file.

### Intent classification edge cases

- **"Create a new component"** -- "create" trigger word but code artifact. Should route to build. The LLM uses semantic understanding: a React/UI component is code, not a business document.
- **"Write tests for the login flow"** -- "write" trigger word but code artifact. Should route to build.
- **"Draft a marketing email"** -- business artifact (marketing content). Should route to generate (brainstorm domain detection identifies marketing).
- **"Generate a migration script"** -- "generate" trigger word but code artifact. Should route to build.
- **"Create a financial report"** -- business artifact. Should route to generate (brainstorm domain detection identifies finance).
- **"Write a blog post about our launch"** -- business artifact (marketing content). Should route to generate.
- **Ambiguous: "Create our company values"** -- could be explore or generate. The AskUserQuestion fallback handles this.
- **"Generate API documentation"** -- arguably a business artifact but closely tied to code. The LLM will likely classify as build, which is acceptable since one-shot can handle doc generation. If the user disagrees, Step 3's confirmation prompt allows correction.

## Dependencies and Risks

- **Risk: SessionStart hook API changes.** The Claude Code hooks API is evolving. The `additionalContext` field for SessionStart may change. Mitigation: the hook is a thin shell script, easy to update. The field name is documented in the official hooks reference.
- **Risk: Sentinel file not writable.** Suppressed with `|| true`. Worst case is a repeating welcome message, not a crash.
- **Risk: `.gitignore` not updated.** If the sentinel file is committed, it would prevent the welcome from firing in new clones. Tracked as an explicit acceptance criterion.
- **Risk: Intent classification accuracy.** The LLM may misclassify edge cases between build and generate. Mitigation: Step 3 always confirms the classification with the user before delegation. Misclassification is a 1-click correction, not a dead end.
- **Dependency: CSS changes require docs site rebuild.** The `.callout` class must be added to `style.css` before the Getting Started page can use it. Build with `npx @11ty/eleventy` in the worktree (after `npm install`).

## References

- Issue: #432
- Parent issue: #430
- Claude Code hooks reference: <https://code.claude.com/docs/en/hooks>
- PostInstall hook feature request: <https://github.com/anthropics/claude-code/issues/9394>
- Learning: `knowledge-base/project/learnings/2026-02-22-simplify-workflow-command-routing.md` (go command routing design decisions)
- Learning: `knowledge-base/project/learnings/2026-02-22-simplify-workflow-thin-router-over-migration.md` (thin router philosophy)
- Learning: `knowledge-base/project/learnings/2026-02-13-brainstorm-domain-routing-pattern.md` (route through existing commands)
- Learning: `knowledge-base/project/learnings/2026-02-22-domain-prerequisites-refactor-table-driven-routing.md` (table-driven domain config)
- Learning: `knowledge-base/project/learnings/docs-site/2026-02-19-adding-docs-pages-pattern.md` (docs site conventions)
- Current go.md: `plugins/soleur/commands/go.md`
- Current hooks.json: `plugins/soleur/hooks/hooks.json`
- Current getting-started.md: `plugins/soleur/docs/pages/getting-started.md`
- Brainstorm domain config: `plugins/soleur/skills/brainstorm/references/brainstorm-domain-config.md`
