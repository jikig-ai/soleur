# Tasks: Fix Onboarding Blockers

## Phase 1: Setup

- [ ] 1.1 Add `.claude/soleur-welcomed.local` to `.gitignore`
  - Current `.gitignore` only covers `.claude/settings.local.json` -- NOT all `.local` files
  - Add explicit `.claude/soleur-welcomed.local` entry after the `.claude/settings.local.json` line

## Phase 2: P0 -- Post-install guidance

- [ ] 2.1 Create welcome hook script
  - Create `plugins/soleur/hooks/welcome-hook.sh`
  - Implement sentinel check (`.claude/soleur-welcomed.local`)
  - Use `additionalContext` (NOT `systemMessage`) in `hookSpecificOutput` -- SessionStart uses `additionalContext` for context injection
  - Add `|| true` error suppression on `mkdir -p` and `touch` for read-only filesystem graceful degradation
  - Make script executable (`chmod +x`)
- [ ] 2.2 Register SessionStart hook in hooks.json
  - Edit `plugins/soleur/hooks/hooks.json`
  - Add `SessionStart` entry with `"matcher": "startup"` (prevents firing on resume/clear/compact)
  - Command: `${CLAUDE_PLUGIN_ROOT}/hooks/welcome-hook.sh`
  - Preserve existing `Stop` hook entry
- [ ] 2.3 Add `.callout` CSS class to docs site stylesheet
  - Edit `plugins/soleur/docs/css/style.css`
  - Add `.callout` class inside `@layer components` (no inline styles per constitution)
  - Properties: left border accent, secondary background, rounded corners
- [ ] 2.4 Add "After Installing" callout to Getting Started page
  - Edit `plugins/soleur/docs/pages/getting-started.md`
  - Insert `.callout` div immediately after the Installation code block
  - Position `/soleur:sync` as first action for existing projects
  - Position `/soleur:go` as first action for new projects

## Phase 3: P1 -- Getting Started page restructure

- [ ] 3.1 Merge workflow sections
  - Combine "Common Workflows" and "Beyond Engineering" into single "Example Workflows" section
  - Interleave engineering and non-engineering examples (order by user journey likelihood)
  - Remove the separate "Beyond Engineering" heading
- [ ] 3.2 Position `/soleur:sync` in workflow introduction
  - Update "The Workflow" section to lead with sync as the recommended first action
  - Reframe the section to reflect the full user journey (sync -> go -> workflow)

## Phase 4: P2 -- `/soleur:go` routing gap

- [ ] 4.1 Add "generate" intent to go.md
  - Edit `plugins/soleur/commands/go.md`
  - Add generate intent row to Step 2 classification table
  - Use semantic description ("non-code business artifact"), not keyword list -- LLM does semantic classification
  - Ensure generate routes to `soleur:brainstorm` (not one-shot)
- [ ] 4.2 Refine build intent description
  - Add "AND the target is code/infrastructure/technical" qualifier to build intent
  - Ensure "generate a REST API" still routes to build
  - Ensure "generate our privacy policy" routes to generate
- [ ] 4.3 Update Step 4 delegation mapping
  - Add `generate: skill: soleur:brainstorm` to the delegation list

## Phase 5: Testing

- [ ] 5.1 Manual test welcome hook
  - Remove sentinel file if present
  - Verify welcome message appears as additional context on new session start
  - Verify sentinel file is created at `.claude/soleur-welcomed.local`
  - Verify sentinel file is gitignored (`git check-ignore .claude/soleur-welcomed.local`)
  - Start a second session and verify no welcome message
- [ ] 5.2 Verify Getting Started page renders correctly
  - Run `npm install` in worktree (worktrees do not share node_modules)
  - Build docs site (`npx @11ty/eleventy`)
  - Verify merged workflow section displays correctly
  - Verify `.callout` class renders with left border accent
- [ ] 5.3 Test go command routing
  - Test: `/soleur:go generate our privacy policy` routes to brainstorm
  - Test: `/soleur:go generate a REST API` routes to one-shot
  - Test: `/soleur:go fix the login bug` routes to one-shot
  - Test: `/soleur:go write a blog post` routes to brainstorm
  - Test: `/soleur:go create a new React component` routes to one-shot
  - Test: `/soleur:go draft our pricing strategy` routes to brainstorm
