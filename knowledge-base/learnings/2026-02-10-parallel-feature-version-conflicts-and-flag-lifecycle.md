# Learning: Parallel feature branches create version bump conflicts; experimental flags should self-manage

## Problem

Two parallel feature branches (`feat-agent-team` and `community-contributor-audit`) both planned to bump the plugin version to 1.12.0. The community audit merged first via PR #36, consuming the version number. When the agent-team branch was ready to implement, the planned version was already taken.

Separately, the initial design required users to manually set `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` before running `/soleur:work`. This added friction and was unnecessary since the consent prompt already gates the feature.

## Solution

**Version conflict:** Defer the version bump decision until implementation time, not planning time. The agent-team plan was updated from 1.12.0 to 1.13.0 after rebasing onto main revealed the conflict. Always check `plugin.json` on the target branch before committing a version number in a plan.

**Flag lifecycle:** Auto-manage the experimental flag within the execution scope:
- `export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` when user accepts Agent Teams (Step A2)
- `unset CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` on shutdown (Step A4) or `spawnTeam` failure

## Key Insight

Plans should specify _intent_ (MINOR bump) not _exact versions_ (1.12.0) when parallel work is possible. Experimental feature flags should be activated on user consent and deactivated on completion/failure -- never require manual setup for features that already have a consent prompt.

## Tags

category: integration-issues
module: plugin-versioning, work-command
symptoms: version already taken, user friction for experimental features
