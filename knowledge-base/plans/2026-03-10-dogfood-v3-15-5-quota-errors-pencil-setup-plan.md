---
title: "dogfood: verify v3.15.5 changes -- gemini quota errors and pencil-setup three-tier detection"
type: fix
date: 2026-03-10
semver: patch
---

# Dogfood v3.15.5: Gemini Quota Errors and Pencil Setup Three-Tier Detection

## Overview

Verify the two v3.15.5 changes in a real environment:

1. **fix(gemini-imagegen): quota-specific error detection (#498)** -- trigger and verify quota/permission/safety/no-image error paths
2. **feat(pencil-setup): Pencil Desktop standalone MCP target (#493/#499)** -- run pencil-setup and verify three-tier detection targets Pencil Desktop correctly

This is a dogfood plan -- no new code is written. The goal is to exercise the merged changes, confirm they work as intended, and capture any issues found.

## Problem Statement / Motivation

PR #498 replaced generic "check your prompt" errors with specific error categories (QUOTA EXHAUSTED, PERMISSION DENIED, SAFETY FILTER, NO IMAGE) across all 5 gemini-imagegen scripts. PR #499 restructured `check_deps.sh` with a three-tier detection cascade (CLI > Desktop binary > IDE extension) so Pencil MCP works without an IDE. Both PRs have unit tests but have not been exercised end-to-end in the actual development environment.

## Environment State

Current environment:
- `GEMINI_API_KEY`: **not set** -- must be set for live quota verification
- `google-genai` SDK: installed system-wide
- Pencil Desktop: **not installed**
- Pencil CLI: **not in PATH**
- Cursor: available at `/usr/bin/cursor` with Pencil extension at `~/.cursor/extensions/highagency.pencildev-0.6.28-universal/`
- VS Code: available at `/snap/bin/code`
- Pencil MCP: **not registered** with Claude Code

## Part 1: Gemini Imagegen Quota Error Verification

### 1.1 Run Unit Tests

Run the 16 existing unit tests to confirm they pass in this environment.

**File:** `plugins/soleur/skills/gemini-imagegen/scripts/test_error_handling.py`

```bash
cd plugins/soleur/skills/gemini-imagegen/scripts && python3 -m pytest test_error_handling.py -v
```

Or with unittest:

```bash
cd plugins/soleur/skills/gemini-imagegen/scripts && python3 -m unittest test_error_handling -v
```

**Expected:** All 16 tests pass (3 TestCheckQuota + 5 TestHandleApiError + 8 TestParseImageResponse).

### 1.2 Verify `--check-quota` Flag

Test the `--check-quota` flag on `generate_image.py`:

**Precondition:** `GEMINI_API_KEY` must be set.

```bash
cd plugins/soleur/skills/gemini-imagegen/scripts
GEMINI_API_KEY="<key>" python3 generate_image.py --check-quota
```

**Scenarios:**

| Scenario | Expected Output |
|----------|----------------|
| Valid API key with image quota | `[ok] Image generation quota available (model: gemini-2.5-flash-image)` |
| Valid API key without image quota (free tier) | `[FAIL] QUOTA EXHAUSTED: Image generation quota is zero or exceeded...` |
| Invalid API key | `[FAIL] PERMISSION DENIED: API key lacks image generation access...` or `[FAIL] API CLIENT ERROR (400): ...` |
| No API key set | `GEMINI_API_KEY environment variable not set` |

### 1.3 Trigger Quota Error Path (Live)

Attempt image generation without quota to verify the error message is actionable:

```bash
cd plugins/soleur/skills/gemini-imagegen/scripts
python3 generate_image.py "A red square" /tmp/test_quota.png
```

If the API key has no image quota, the output should show `QUOTA EXHAUSTED` with the original API error message, not the generic "check your prompt" message.

### 1.4 Verify Error Handling Integration in All 5 Scripts

Confirm all 5 scripts import from `_error_handling` and use the shared `handle_api_error` and `parse_image_response` functions:

| Script | Imports `handle_api_error` | Imports `parse_image_response` |
|--------|---------------------------|-------------------------------|
| `generate_image.py` | Yes | Yes |
| `edit_image.py` | Yes | Yes |
| `compose_images.py` | Yes | Yes |
| `multi_turn_chat.py` | Yes (+ `NoImageError`) | Yes |
| `gemini_images.py` | Yes | Yes |

Verify with:

```bash
grep -l "from _error_handling import" plugins/soleur/skills/gemini-imagegen/scripts/*.py
```

Expected: all 5 scripts listed.

### 1.5 Verify SDK Hang Bug Avoidance

Confirm no script accesses `response.candidates[N].finish_reason` (SDK hang bug #2024):

```bash
grep -r "finish_reason" plugins/soleur/skills/gemini-imagegen/scripts/
```

Expected: no matches.

## Part 2: Pencil Setup Three-Tier Detection Verification

### 2.1 Run `check_deps.sh` Without Arguments

Test the interactive flow:

```bash
bash plugins/soleur/skills/pencil-setup/scripts/check_deps.sh
```

**Expected output** (given environment: no CLI, no Desktop, Cursor with extension):

```
=== Pencil Setup Dependency Check ===

  [ok] IDE: cursor
  [ok] Pencil extension

=== Check Complete ===

PREFERRED_MODE=ide
PREFERRED_BINARY=/home/jean/.cursor/extensions/highagency.pencildev-0.6.28-universal/out/mcp-server-linux-x64
PREFERRED_APP=cursor
```

**Key verifications:**
- [ ] Tier 1 (CLI) is skipped silently (no `pencil` in PATH)
- [ ] Tier 2 (Desktop) is skipped silently (no Desktop installed)
- [ ] Tier 3 (IDE) succeeds with Cursor and extension
- [ ] `PREFERRED_APP` is `cursor` (not `code`)
- [ ] MCP binary path points to the actual extension binary

### 2.2 Run `check_deps.sh --auto`

Test the automated/pipeline flow:

```bash
bash plugins/soleur/skills/pencil-setup/scripts/check_deps.sh --auto
```

**Expected:** Same as 2.1 (no Desktop to auto-launch, extension already installed).

### 2.3 Verify VS Code `--app` Flag Value

If VS Code were the only IDE, the `--app` value should be `visual_studio_code` (not `code`):

```bash
grep -A1 'code)' plugins/soleur/skills/pencil-setup/scripts/check_deps.sh | head -5
```

**Expected:** `echo "visual_studio_code"` in the `ide_to_app_value` function.

### 2.4 Verify Evolus/Pencil Collision Guard

If an unrelated `pencil` binary exists in PATH:

```bash
# Simulate: create a fake pencil binary
mkdir -p /tmp/fake-pencil && echo '#!/bin/bash' > /tmp/fake-pencil/pencil && echo 'echo "Evolus Pencil 3.0"' >> /tmp/fake-pencil/pencil && chmod +x /tmp/fake-pencil/pencil
PATH="/tmp/fake-pencil:$PATH" bash plugins/soleur/skills/pencil-setup/scripts/check_deps.sh
rm -rf /tmp/fake-pencil
```

**Expected:**
- `[info] pencil CLI found but is not pencil.dev (possible evolus/pencil)` message appears
- Tier 1 (CLI) is skipped, falls through to Tier 3 (IDE)

### 2.5 Run Full `pencil-setup` Skill Flow

Execute the full SKILL.md flow:

1. Run `check_deps.sh` to get `PREFERRED_MODE`, `PREFERRED_BINARY`, `PREFERRED_APP`
2. Check if `pencil` MCP is already registered: `claude mcp list -s user 2>&1 | grep -q "pencil"`
3. If not registered, register with: `claude mcp add -s user pencil -- <PREFERRED_BINARY> --app <PREFERRED_APP>`
4. Verify registration: `claude mcp list -s user 2>&1 | grep pencil`

**Expected:** Pencil MCP registered in IDE mode with the Cursor extension binary.

### 2.6 Verify Desktop Binary Detection (Negative)

With no Desktop installed, the `detect_desktop_binary` function should return empty:

```bash
bash -c 'source plugins/soleur/skills/pencil-setup/scripts/check_deps.sh 2>/dev/null; detect_desktop_binary; echo "exit: $?"'
```

The script does not support sourcing (it runs main flow on source), so verify via code inspection that:
- macOS checks `/Applications/Pencil.app/Contents/Resources/app.asar.unpacked/out/mcp-server-darwin-*`
- Linux checks `/usr/lib/pencil/resources/app.asar.unpacked/out/mcp-server-linux-*` (deb) and extracted AppImage paths

## Acceptance Criteria

- [ ] All 16 unit tests in `test_error_handling.py` pass
- [ ] `--check-quota` flag works and prints actionable message for each error category
- [ ] All 5 gemini-imagegen scripts import from `_error_handling`
- [ ] No script accesses `response.candidates[N].finish_reason`
- [ ] `check_deps.sh` detects Cursor + extension as IDE tier correctly
- [ ] `check_deps.sh` outputs correct `PREFERRED_MODE=ide`, `PREFERRED_BINARY`, `PREFERRED_APP=cursor`
- [ ] VS Code `--app` value is `visual_studio_code` (not `code`)
- [ ] Evolus/pencil collision guard prints info message and falls through
- [ ] Full pencil-setup skill flow completes MCP registration

## Test Scenarios

- Given no GEMINI_API_KEY, when running `generate_image.py`, then exit with "GEMINI_API_KEY environment variable not set"
- Given a valid key with no image quota, when running `--check-quota`, then print QUOTA EXHAUSTED with the original API error
- Given a valid key with quota, when running `--check-quota`, then print `[ok] Image generation quota available`
- Given no Pencil CLI or Desktop, when running `check_deps.sh`, then detect IDE tier (Cursor + extension)
- Given a fake evolus/pencil in PATH, when running `check_deps.sh`, then print collision warning and fall through to IDE
- Given `--auto` flag, when running `check_deps.sh` with no Desktop installed, then skip auto-launch gracefully

## Non-Goals

- Writing new code or modifying existing implementations
- Testing on macOS or with Pencil Desktop installed (not available in this environment)
- Testing the Gemini Pro model (quota may not cover it)
- Registering Pencil MCP permanently (this is verification only)

## References

- PR #498: fix(gemini-imagegen): add quota-specific error detection and actionable messages
- PR #499: feat(pencil-setup): use Pencil Desktop as standalone MCP target (#493)
- PR #493: Original issue for Pencil Desktop standalone MCP
- Learning: `knowledge-base/learnings/2026-03-10-gemini-sdk-error-handling-patterns.md`
- Learning: `knowledge-base/learnings/2026-03-10-pencil-desktop-standalone-mcp-three-tier-detection.md`
- Error handling module: `plugins/soleur/skills/gemini-imagegen/scripts/_error_handling.py`
- Check deps script: `plugins/soleur/skills/pencil-setup/scripts/check_deps.sh`
- Test file: `plugins/soleur/skills/gemini-imagegen/scripts/test_error_handling.py`
