# Learning: Version bump classification when wiring existing agents

## Problem

When wiring existing but unused agents into a command, the version bump type (MINOR vs PATCH) was unclear. The agents already existed in the repository and were listed in the README, but they were never referenced by the command.

## Solution

Wiring existing agents into a command is a **MINOR** bump, not PATCH. The agents may exist in the repo, but activating them changes the command's observable behavior and output. Users will see new analysis dimensions in their reviews.

The key distinction: PATCH fixes broken behavior. MINOR adds new capabilities. Even though the agent files existed, the command gained new functionality.

## Key Insight

Version bump classification is about user-facing behavior change, not file creation. If a command produces different output after the change, it's at minimum MINOR, regardless of whether the underlying components already existed.

Also: when adding items to a numbered list with gaps (e.g., parallel agents 1-9 then conditional 14-15), renumber sequentially. Numbering gaps confuse future contributors who wonder what happened to the missing numbers.

## Tags

category: workflow-patterns
module: plugin-versioning
symptoms: version-bump-uncertainty
