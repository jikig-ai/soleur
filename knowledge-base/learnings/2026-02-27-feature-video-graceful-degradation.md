# Learning: Feature Video Graceful Degradation

## Problem

The `feature-video` skill chains three external dependencies (agent-browser, ffmpeg, rclone). When any was missing, the skill either failed with a raw shell error or silently skipped steps with no feedback to the user. There was no preflight check, so failures surfaced deep into the workflow rather than at the start.

## Solution

1. Created `plugins/soleur/skills/feature-video/scripts/check_deps.sh` -- a preflight dependency checker following the existing `rclone/scripts/check_setup.sh` pattern.
2. agent-browser is a hard dependency (exit 1 if missing) because recording is impossible without it. ffmpeg and rclone are soft dependencies (print `[skip]`, continue) because the skill degrades gracefully without them.
3. Updated SKILL.md with a Phase 0 dependency check, conditional logic in steps 4-8, three PR description cases (uploaded/local/screenshots-only), and conditional cleanup.
4. Version bumped to 3.5.2.

## Key Insight

Hard vs soft dependency classification should follow capability loss, not convenience. agent-browser cannot be worked around (the entire purpose of the skill is to record browser sessions), so it must be a hard failure. ffmpeg and rclone only affect post-processing and upload -- the skill can still produce value (screenshots, local video) without them. This distinction should be made explicit in the script with clear `[skip]` output rather than silent omission.

Dedicated script files are preferable to inline checks when the check logic is reusable for diagnostics. A user can run `./check_deps.sh` directly to understand what is missing before attempting the full skill workflow.

## Review Findings

- For-loops with tool-specific inner branches are less readable than flat if-blocks when there are only two tools to check. Prefer clarity over DRY in small sets.
- Scripts should either have `set -e` at the top or include a comment explaining why it is absent. Omitting it silently changes error propagation behavior.
- Bash invocation paths should use a leading `./` (e.g., `./scripts/check_deps.sh`) for consistency with other skills in the plugin.
- When a check script reports a healthy state, it should print a positive confirmation message, not just the absence of an error. Silent success is ambiguous in diagnostic scripts.

## Session Errors

1. The Edit tool requires a prior Read of the file in the same conversation. Attempted to edit `README.md` and `bug_report.yml` without reading them first, which caused tool failures.
2. Wrong path assumed for `marketplace.json` -- looked under `plugins/soleur/.claude-plugin/` instead of the repo root `.claude-plugin/`. Use glob to locate files when the exact path is uncertain.
3. Pre-existing version drift: `marketplace.json` was at 3.5.0 while `plugin.json` was already at 3.5.1 before this session began. This went undetected until the version bump step.

## Prevention

- Always read files before editing. This is a tool requirement, not an optional step.
- Use glob to find files when the exact path is uncertain rather than guessing directory structure.
- The version quad (plugin.json, CHANGELOG.md, marketplace.json, README badge, bug_report.yml) must all be checked during every bump. Grep for the current version string across all five files before and after the bump to catch drift.
- Do not assume a file is at its expected version at session start. Fetch and inspect before editing.

## Tags
category: integration-issues
module: feature-video
