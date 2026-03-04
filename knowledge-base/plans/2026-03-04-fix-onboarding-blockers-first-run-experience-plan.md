---
title: "fix: onboarding blockers for first-time external users"
type: fix
date: 2026-03-04
semver: patch
---

# Fix Onboarding Blockers for First-Time External Users

## Overview

Three onboarding blockers prevent a stranger from having a good first-run experience after installing Soleur. These were identified in the product strategy onboarding audit (issue #430) and tracked in issue #432. The blockers are: (P0) no post-install guidance, (P1) Getting Started page structure issues, and (P2) `/soleur:go` routing gap for non-engineering tasks.

## Problem Statement

A new user who runs `claude plugin install soleur` gets zero feedback. They must already know to type `/soleur:go` or `/soleur:help`. The Getting Started page separates engineering and non-engineering workflows into two tiers, creating a misleading impression that non-engineering features are secondary. The `go` command's 3-intent model (explore/build/review) forces non-engineering tasks like "generate our privacy policy" through the brainstorm flow rather than routing directly to the appropriate domain skill.

## Proposed Solution

### P0: Post-install guidance via SessionStart hook + Getting Started callout

**Research finding:** Claude Code's plugin spec does **not** support PostInstall hooks. The supported hook events are: SessionStart, UserPromptSubmit, PreToolUse, PermissionRequest, PostToolUse, PostToolUseFailure, Notification, SubagentStart, SubagentStop, Stop, TeammateIdle, TaskCompleted, ConfigChange, WorktreeCreate, WorktreeRemove, PreCompact, SessionEnd. The feature request for PostInstall/PostUninstall hooks is tracked in [anthropics/claude-code#9394](https://github.com/anthropics/claude-code/issues/9394) (open).

**Two-pronged approach:**

1. **SessionStart hook (one-time welcome):** Add a SessionStart hook to `plugins/soleur/hooks/hooks.json` that checks for a sentinel file (`.claude/soleur-welcomed.local`). On first session after install (no sentinel), the hook outputs a welcome system message: "Soleur installed. Run /soleur:sync to analyze your project, or /soleur:help to see all commands." Then creates the sentinel file so the message only appears once. Subsequent sessions skip the hook silently.

2. **"After Installing" section on Getting Started page:** Add a prominent callout section immediately after the Installation code block, telling users their recommended first action is `/soleur:sync` for existing projects or `/soleur:go` for new ones. This catches users who miss the SessionStart message or who read the docs site directly.

**Files:**
- `plugins/soleur/hooks/hooks.json` -- add SessionStart hook entry
- `plugins/soleur/hooks/welcome-hook.sh` -- new script (sentinel check + welcome message)
- `plugins/soleur/docs/pages/getting-started.md` -- add "After Installing" section

### P1: Getting Started page restructure

1. **Position `/soleur:sync` as Step 1:** Add a "First Steps" section after install that positions `/soleur:sync` as the recommended first action for existing projects, with `/soleur:go` as the follow-up.

2. **Merge workflow sections:** Combine "Common Workflows" and "Beyond Engineering" into a single "Example Workflows" section. Interleave engineering and non-engineering examples rather than segregating them. This removes the two-tier impression.

3. **Add "Try this first" callout:** Include a visually distinct callout (using existing CSS patterns from the docs site) that highlights the recommended first-run sequence: sync, then go.

**Files:**
- `plugins/soleur/docs/pages/getting-started.md`

### P2: `/soleur:go` routing gap for non-engineering tasks

The current `go.md` has 3 intents: explore (brainstorm), build (one-shot), review (review). A user typing "generate our privacy policy" matches "build" because of the word "generate", routing to one-shot which treats it as an engineering task. The correct route is through brainstorm's domain detection (Phase 0.5) which recognizes legal domain and routes to the CLO.

**Fix: Add a "generate/create" intent** that detects domain-specific generation requests and routes through brainstorm with a hint that domain detection should prioritize direct routing.

The current routing table becomes:

| Intent | Trigger Signals | Delegates To |
|--------|----------------|--------------|
| explore | Questions, "brainstorm", "think about", "let's explore", vague scope, no clear deliverable | `soleur:brainstorm` skill |
| build | Bug fix, feature request, issue reference (#N), clear engineering requirements, "fix", "add", "implement", "build" | `soleur:one-shot` skill |
| review | "review PR", "check this code", "review #N", PR number reference | `soleur:review` skill |
| generate | "generate", "create", "draft", "write" + non-code artifact (legal doc, brand guide, policy, report, strategy, plan, analysis) | `soleur:brainstorm` skill (domain detection routes to correct leader) |

The key change: "generate" intent signals are distinguished from "build" by checking whether the target is a code artifact or a business artifact. "Generate a REST API" maps to build. "Generate our privacy policy" maps to generate (which routes through brainstorm's domain detection).

**Why brainstorm and not a direct skill?** Brainstorm's Phase 0.5 domain detection already has the full routing table for all 8 domains. Adding a parallel routing system in `go.md` would duplicate this logic. Instead, the generate intent routes to brainstorm with context that signals "this is a domain-specific generation request" so brainstorm can fast-track through domain detection without the full exploration flow.

**Files:**
- `plugins/soleur/commands/go.md` -- add generate intent row, update classification logic

## Acceptance Criteria

- [ ] P0: First session after install displays a welcome message with `/soleur:sync` and `/soleur:help` suggestions
- [ ] P0: Welcome message only appears once (sentinel file prevents repeats)
- [ ] P0: Getting Started page has an "After Installing" callout section immediately after the install code block
- [ ] P1: "Common Workflows" and "Beyond Engineering" merged into a single "Example Workflows" section
- [ ] P1: `/soleur:sync` positioned as the first recommended action after install
- [ ] P1: "Try this first" callout is visually distinct
- [ ] P2: `/soleur:go generate our privacy policy` routes through brainstorm domain detection to CLO, not through one-shot
- [ ] P2: `/soleur:go generate a REST API` still routes to one-shot (build intent)
- [ ] P2: Ambiguous inputs still prompt the user to choose

## Test Scenarios

- Given a fresh install with no `.claude/soleur-welcomed.local` file, when a session starts, then the welcome message appears and the sentinel file is created
- Given a previous session has already shown the welcome, when a new session starts, then no welcome message appears
- Given the Getting Started page, when a user reads it, then engineering and non-engineering workflows appear in a single unified section
- Given the Getting Started page, when a user reads it, then `/soleur:sync` is positioned as Step 1 after install
- Given `/soleur:go generate our privacy policy`, when intent is classified, then it routes to brainstorm (not one-shot) and domain detection identifies legal domain
- Given `/soleur:go generate a REST API`, when intent is classified, then it routes to one-shot (build intent)
- Given `/soleur:go write a blog post`, when intent is classified, then it routes to brainstorm and domain detection identifies marketing domain
- Given `/soleur:go fix the login bug`, when intent is classified, then it routes to one-shot (build intent, unchanged behavior)

## Non-goals

- **Full PostInstall hook implementation** -- that requires upstream changes to Claude Code plugin spec (tracked in anthropics/claude-code#9394). The SessionStart hook is a pragmatic workaround.
- **Rewriting brainstorm's domain detection** -- the existing Phase 0.5 detection works well. The fix is in `go.md` routing, not in brainstorm internals.
- **Adding new skills for non-engineering domains** -- the existing domain leader agents (CLO, CMO, etc.) and brainstorm routing handle domain-specific work. No new skills needed.
- **Redesigning the `/soleur:go` command architecture** -- per the learning in `knowledge-base/learnings/2026-02-22-simplify-workflow-command-routing.md`, the 3-intent model was deliberately reduced from 7. Adding one more intent (generate) is a minimal extension, not a redesign.

## MVP

### plugins/soleur/hooks/welcome-hook.sh

```bash
#!/usr/bin/env bash
set -euo pipefail

# --- Sentinel Check ---
SENTINEL_FILE=".claude/soleur-welcomed.local"

if [[ -f "$SENTINEL_FILE" ]]; then
  # Already welcomed -- allow session start without output
  exit 0
fi

# --- First-Time Welcome ---
mkdir -p .claude
touch "$SENTINEL_FILE"

# Output JSON with system message for first-time users
cat <<'WELCOME_JSON'
{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "systemMessage": "Welcome to Soleur! Run /soleur:sync to analyze your project, or /soleur:help to see all commands."
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

### plugins/soleur/commands/go.md (intent table update)

```markdown
| Intent | Trigger Signals | Delegates To |
|--------|----------------|--------------|
| explore | Questions, "brainstorm", "think about", "let's explore", vague scope, no clear deliverable | `soleur:brainstorm` skill |
| build | Bug fix, feature request, issue reference (#N), clear engineering requirements, "fix", "add", "implement", "build" -- AND the target is code, infrastructure, or technical implementation | `soleur:one-shot` skill |
| generate | "generate", "create", "draft", "write" + non-code business artifact (legal document, brand guide, policy, report, strategy, marketing content, financial plan) | `soleur:brainstorm` skill |
| review | "review PR", "check this code", "review #N", PR number reference | `soleur:review` skill |
```

### plugins/soleur/docs/pages/getting-started.md (After Installing section)

```html
<div class="commands-list">
  <div class="command-item" style="border-left: 3px solid var(--color-brand-primary, #6366f1);">
    <code>Try this first</code>
    <p><strong>Existing project?</strong> Run <code>/soleur:sync</code> to analyze your codebase.<br>
    <strong>New project?</strong> Run <code>/soleur:go</code> and describe what you need.</p>
  </div>
</div>
```

## SpecFlow Analysis

### SessionStart hook edge cases

- **Multiple plugins with SessionStart hooks:** Claude Code runs all SessionStart hooks from all plugins. Soleur's hook must not interfere with other plugins' hooks. The sentinel file is namespaced (`soleur-welcomed.local`) to avoid collisions.
- **Sentinel file location:** `.claude/soleur-welcomed.local` is relative to the project directory. A user installing Soleur in multiple projects gets the welcome once per project, which is correct behavior.
- **Hook output format:** SessionStart hooks output JSON with `hookSpecificOutput.systemMessage` to inject a system message. This is the documented API per Claude Code hooks reference.
- **`.gitignore` compliance:** The sentinel file uses `.local` suffix and lives in `.claude/` which is typically gitignored. Verify `.gitignore` includes `.claude/*.local` or add an entry.

### Intent classification edge cases

- **"Create a new component"** -- "create" trigger word but code artifact. Should route to build. The disambiguation is "non-code business artifact" qualifier on the generate intent.
- **"Write tests for the login flow"** -- "write" trigger word but code artifact. Should route to build.
- **"Draft a marketing email"** -- "draft" trigger word + non-code artifact. Should route to generate (brainstorm domain detection identifies marketing).
- **"Generate a migration script"** -- "generate" trigger word but code artifact. Should route to build.
- **Ambiguous: "Create our company values"** -- could be explore or generate. The AskUserQuestion fallback handles this.

## Dependencies and Risks

- **Risk: SessionStart hook format changes.** The Claude Code hooks API is evolving. The `hookSpecificOutput.systemMessage` field for SessionStart may change format. Mitigation: the hook is a thin shell script, easy to update.
- **Risk: Sentinel file not writable.** If `.claude/` directory doesn't exist or isn't writable, `mkdir -p` + `touch` handles the common case. Read-only filesystems would fail silently (exit 0 on any error).
- **Dependency: `.gitignore` must exclude sentinel file.** Check if `.claude/*.local` or `*.local` is already in `.gitignore`.

## References

- Issue: #432
- Parent issue: #430
- Claude Code hooks reference: https://code.claude.com/docs/en/hooks
- PostInstall hook feature request: https://github.com/anthropics/claude-code/issues/9394
- Learning: `knowledge-base/learnings/2026-02-22-simplify-workflow-command-routing.md` (go command routing design decisions)
- Current go.md: `plugins/soleur/commands/go.md`
- Current hooks.json: `plugins/soleur/hooks/hooks.json`
- Current getting-started.md: `plugins/soleur/docs/pages/getting-started.md`
- Brainstorm domain config: `plugins/soleur/skills/brainstorm/references/brainstorm-domain-config.md`
