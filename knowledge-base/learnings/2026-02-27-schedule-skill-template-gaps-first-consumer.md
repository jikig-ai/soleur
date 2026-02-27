# Learning: Schedule Skill Template Gaps (First Consumer)

## Problem

The `soleur:schedule` skill generates workflow YAML from a fixed template, but the first real consumer (`competitive-analysis`) exposed five gaps that required manual post-generation edits.

## Solution

After generating the workflow with `/soleur:schedule create`, manually apply these fixes:

1. **Skill-specific arguments**: The template prompt says `Run /soleur:<SKILL_NAME> on this repository.` with no way to pass arguments like `--tiers 0,3`. Edit the prompt line to include them.

2. **`--max-turns` in `claude_args`**: The template only includes `--model`. For agents that perform multiple WebSearch/WebFetch calls (competitive intelligence, growth analysis), add `--max-turns 30` (or more) to prevent premature termination.

3. **Label pre-creation**: The template instructs the agent to create an issue with a label, but `gh issue create --label foo` fails if the label doesn't exist. Add a pre-step:
   ```yaml
   - name: Ensure label exists
     env:
       GH_TOKEN: ${{ github.token }}
     run: |
       gh label create scheduled-<name> \
         --description "Description" \
         --color "0E8A16" 2>/dev/null || true
   ```

4. **`timeout-minutes`**: The template has no job-level timeout. LLM-backed workflows should set `timeout-minutes: 30` (or similar) to prevent runaway billing if the agent gets stuck.

5. **`id-token: write` permission**: `claude-code-action` requires OIDC token access for authentication. Without `id-token: write` in the permissions block, the action fails immediately with "Could not fetch an OIDC token." The existing `claude-code-review.yml` includes this permission, but the schedule skill template did not. [Updated 2026-02-27]

## Key Insight

The schedule skill template is a starting point, not a complete workflow. Every generated workflow needs a review pass for: argument passthrough, turn limits, label existence, timeout caps, and OIDC permissions. These should be added to the template itself in a future iteration.

## Session Errors

- Security reminder hook fired on first workflow file write (non-blocking, correctly identified no injection risk)

## Tags

category: integration-issues
module: schedule, github-actions
