# Learning: Skill `!` code fence permission flow fails silently

## Problem

When a skill or command contains a ` ```! ` code fence that executes a Bash command, and that command is not in the permission allow list, the Skill tool returns an error immediately rather than surfacing an interactive approval prompt. The user never gets the chance to approve the command.

This was discovered when `/soleur:one-shot` tried to execute `setup-ralph-loop.sh` via a `!` code fence. The official ralph-loop plugin path was in the allow list, but the Soleur plugin's own copy of the same script was not.

## Solution

Two approaches:

1. **Pre-add the script path to the allow list** in `.claude/settings.local.json`:
   ```json
   "Bash(\"<full-path-to-script>\":*)"
   ```

2. **Run the blocked script manually via Bash tool first** (gets the interactive permission prompt), then execute the remaining skill steps manually.

## Key Insight

The Skill tool's `!` code fence execution path does not support interactive permission prompts -- it fails fast on any permission denial. When designing skills that use `!` blocks for setup scripts, ensure the script paths are documented so users can pre-authorize them. Alternatively, avoid burying permission-sensitive Bash calls in `!` code fences -- surface them in the skill narrative where manual Bash execution is natural.

When a plugin maintains its own copy of a utility script (rather than importing from another plugin), the permission allow list must explicitly whitelist that copy's path. Whitelisting the original location does not cascade to copies.

## Tags
category: tool-integration
module: skills, one-shot, ralph-loop
symptoms: Skill tool returns error instead of showing permission prompt for Bash command in code fence
