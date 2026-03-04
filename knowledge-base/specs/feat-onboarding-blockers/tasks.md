# Tasks: Fix Onboarding Blockers

## Phase 1: Setup

- [ ] 1.1 Verify `.gitignore` includes `.claude/*.local` pattern for sentinel files
  - Check `/home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-onboarding-blockers/.gitignore`
  - Add `*.local` or `.claude/*.local` entry if missing

## Phase 2: P0 -- Post-install guidance

- [ ] 2.1 Create welcome hook script
  - Create `plugins/soleur/hooks/welcome-hook.sh`
  - Implement sentinel check (`.claude/soleur-welcomed.local`)
  - Output JSON with `hookSpecificOutput.systemMessage` on first session
  - Make script executable (`chmod +x`)
- [ ] 2.2 Register SessionStart hook in hooks.json
  - Edit `plugins/soleur/hooks/hooks.json`
  - Add `SessionStart` entry with matcher and command pointing to welcome-hook.sh
  - Preserve existing `Stop` hook entry
- [ ] 2.3 Add "After Installing" callout to Getting Started page
  - Edit `plugins/soleur/docs/pages/getting-started.md`
  - Insert callout section immediately after the Installation code block
  - Position `/soleur:sync` as first action for existing projects
  - Position `/soleur:go` as first action for new projects

## Phase 3: P1 -- Getting Started page restructure

- [ ] 3.1 Merge workflow sections
  - Combine "Common Workflows" and "Beyond Engineering" into single "Example Workflows" section
  - Interleave engineering and non-engineering examples
  - Remove the separate "Beyond Engineering" heading
- [ ] 3.2 Add "Try this first" callout
  - Add visually distinct callout at the top of the workflow section
  - Highlight recommended first-run sequence: sync then go
- [ ] 3.3 Position `/soleur:sync` as Step 1
  - Update "The Workflow" section to lead with sync as the recommended first action
  - Reframe the section to reflect the full user journey (sync -> go -> workflow)

## Phase 4: P2 -- `/soleur:go` routing gap

- [ ] 4.1 Add "generate" intent to go.md
  - Edit `plugins/soleur/commands/go.md`
  - Add generate intent row to the classification table
  - Update classification logic to distinguish code vs. business artifact targets
  - Ensure generate routes to `soleur:brainstorm` (not one-shot)
- [ ] 4.2 Refine build intent signals
  - Add "AND the target is code/infrastructure/technical" qualifier to build intent
  - Ensure "generate a REST API" still routes to build
  - Ensure "generate our privacy policy" routes to generate

## Phase 5: Testing

- [ ] 5.1 Manual test welcome hook
  - Remove sentinel file if present
  - Verify welcome message appears on session start
  - Verify sentinel file is created
  - Start a second session and verify no welcome message
- [ ] 5.2 Verify Getting Started page renders correctly
  - Build docs site (`npx @11ty/eleventy`)
  - Verify merged workflow section displays correctly
  - Verify "Try this first" callout is visually distinct
- [ ] 5.3 Test go command routing
  - Test: `/soleur:go generate our privacy policy` routes to brainstorm
  - Test: `/soleur:go generate a REST API` routes to one-shot
  - Test: `/soleur:go fix the login bug` routes to one-shot
  - Test: `/soleur:go write a blog post` routes to brainstorm
