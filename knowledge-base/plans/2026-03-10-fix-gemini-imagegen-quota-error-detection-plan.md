---
title: "fix: add quota-specific error detection to gemini-imagegen scripts"
type: fix
date: 2026-03-10
semver: patch
---

# fix: Add Quota-Specific Error Detection to gemini-imagegen Scripts

## Overview

All 5 gemini-imagegen Python scripts produce a misleading "check your prompt" error when the real problem is API quota exhaustion or permission denial. This fix replaces the generic catchall with differentiated error handling that names the actual cause.

## Problem Statement / Motivation

During the X banner session (#483), the scripts wasted time because a free-tier Gemini API key passed the `GEMINI_API_KEY` presence check and `genai.Client()` initialization, but failed on `generate_content()` with a quota error. The scripts caught the empty response and blamed the prompt: "No image was generated. Check your prompt and try again."

This is the wrong diagnosis. The prompt was fine -- the key had zero image generation quota. Docs-level mitigations (SKILL.md Phase 0 pre-flight, constitution rule) were already shipped in PR #489, but the scripts themselves still produce the misleading error.

## Proposed Solution

### 1. Wrap `generate_content()` / `send_message()` calls with specific exception handling

Catch `google.api_core.exceptions.ResourceExhausted` and `PermissionDenied` before they fall through to the generic "no image" path. The `google-genai` SDK raises these from `google-api-core` (a transitive dependency of `google-genai>=1.0.0`).

### 2. Differentiate the "no image in response" path

When no exception is thrown but no image part is returned, check for safety filter indicators in the response metadata or text parts before defaulting to a generic message.

Error categories:

| Condition | Exception/Signal | Proposed Message |
|-----------|-----------------|------------------|
| Quota exhausted | `ResourceExhausted` | `QUOTA EXHAUSTED: Image generation quota is zero or exceeded. Free-tier keys may not include image generation.` |
| Permission denied | `PermissionDenied` | `PERMISSION DENIED: API key lacks image generation access. Check your Gemini API tier.` |
| Safety filter | No image parts + safety-related text in response | `SAFETY FILTER: Image was blocked by content policy. Rephrase the prompt.` |
| Empty response (other) | No image parts, no clear cause | `NO IMAGE IN RESPONSE: Model returned text only. Try a different model or prompt.` |

### 3. Add `--check-quota` flag to `generate_image.py`

A dry-run mode that sends a minimal image generation request to verify quota before the caller commits to the full pipeline. Exit 0 on success, exit 1 on failure with a clear message.

### 4. Extract shared error handling into a helper module

All 5 scripts repeat the same `generate_content()` call-and-parse pattern. Extract the try/except and response-parsing logic into a shared helper (e.g., `_error_handling.py` or add methods to the existing `gemini_images.py` library class) to avoid duplicating the error-handling code 5 times.

## Technical Considerations

- **Exception classes:** `google.api_core.exceptions.ResourceExhausted` and `PermissionDenied` are part of `google-api-core`, a transitive dependency of `google-genai`. No new dependencies needed. However, import them with a try/except to degrade gracefully if the version is older than expected.
- **SDK version variance:** The `google-genai` SDK may surface quota errors differently across versions (exception vs. empty response with error metadata). Handle both paths.
- **`gemini_images.py` (library class):** The `GeminiImageGenerator` class methods (`generate`, `edit`, `compose`) and `ImageChat.send` all call `generate_content()` or `send_message()` but do NOT currently check for image presence -- they silently return `(output, None)` if no image part is found. This is a separate bug: the library silently fails where the CLI scripts raise. The fix should make the library raise too, matching CLI behavior.
- **`multi_turn_chat.py`:** Uses `chat.send_message()` which raises the same exception types. The error handling wraps identically.
- **No regression risk:** The new code paths only activate on error conditions. When quota is available and the response contains an image, behavior is unchanged.
- **`--check-quota` implementation:** Reuse the Phase 0 snippet from SKILL.md -- send `"Generate a 1x1 pixel red square"` with `response_modalities=["TEXT", "IMAGE"]` and check for either an exception or the presence of an image part.

## Non-Goals

- **Pillow fallback flag (`--fallback pillow`):** The issue mentions this as lower priority. The immediate fix is surfacing the real error. Pillow fallback can be a follow-up.
- **Retry logic for transient quota errors:** Rate-limit retries with backoff are out of scope. The scripts should report the error clearly and exit.
- **Changes to SKILL.md or constitution.md:** Already shipped in PR #489. This plan covers code-level fixes only.

## Acceptance Criteria

- [ ] All 5 scripts catch `ResourceExhausted` with a "QUOTA EXHAUSTED" message (`generate_image.py`, `edit_image.py`, `compose_images.py`, `gemini_images.py`, `multi_turn_chat.py`)
- [ ] All 5 scripts catch `PermissionDenied` with a "PERMISSION DENIED" message
- [ ] Generic "check your prompt" / silent failure replaced with specific error categories (safety filter, empty response)
- [ ] `generate_image.py --check-quota` validates quota before generation (exit 0 on success, exit 1 on failure)
- [ ] `gemini_images.py` library class raises on missing image parts instead of silently returning
- [ ] Error handling logic is shared (not duplicated 5 times) -- either via a helper module or centralized in `gemini_images.py`
- [ ] Existing functionality unchanged when quota is available (no regression)
- [ ] Import of `google.api_core.exceptions` degrades gracefully if unavailable

## Test Scenarios

- Given a free-tier API key with zero image quota, when `generate_image.py` is run, then the output contains "QUOTA EXHAUSTED" (not "check your prompt")
- Given an API key with valid quota, when `generate_image.py` is run with a valid prompt, then the image is saved and behavior is identical to current
- Given a prompt that triggers safety filters, when `generate_image.py` is run, then the output contains "SAFETY FILTER"
- Given `generate_image.py --check-quota`, when the key has valid quota, then exit code is 0 and output contains "[ok]"
- Given `generate_image.py --check-quota`, when the key has zero quota, then exit code is 1 and output contains "QUOTA EXHAUSTED"
- Given `google.api_core` is not importable, when any script is run and a quota error occurs, then the error still surfaces (falls through to generic handling, not a crash)
- Given the `GeminiImageGenerator.generate()` library method, when the response contains no image parts, then it raises `RuntimeError` (not silent return)

## Dependencies & Risks

- **Low risk:** Changes are additive exception handlers. No existing logic is removed or restructured.
- **Dependency:** `google-api-core` must be present (transitive via `google-genai>=1.0.0`). The `requirements.txt` already specifies `google-genai>=1.0.0`.
- **Testing constraint:** Full integration testing requires both a valid-quota key and a zero-quota key. Unit tests can mock the exceptions.

## Implementation Approach

### Phase 1: Shared error handling helper

1. Create `plugins/soleur/skills/gemini-imagegen/scripts/_error_handling.py` with:
   - `wrap_generate_content()` -- calls `generate_content()`, catches quota/permission exceptions, parses response for image parts, raises differentiated errors
   - `check_quota()` -- minimal quota validation function
2. Or alternatively, add these as private methods to `GeminiImageGenerator` in `gemini_images.py`

### Phase 2: Update all 5 scripts

1. `generate_image.py` -- use shared helper, add `--check-quota` argparse flag
2. `edit_image.py` -- use shared helper for the `generate_content()` call
3. `compose_images.py` -- use shared helper for the `generate_content()` call
4. `gemini_images.py` -- integrate error handling into `generate()`, `edit()`, `compose()`, and `ImageChat.send()`
5. `multi_turn_chat.py` -- wrap `send_message()` calls with shared error handling

### Phase 3: Verify

1. Run `python3 generate_image.py --check-quota` to validate the flag works
2. Verify no syntax errors across all 5 scripts (`python3 -m py_compile <script>`)

## References & Research

- Issue #494: This issue
- PR #489: Docs-level fix (SKILL.md Phase 0 pre-flight, constitution rule)
- `knowledge-base/learnings/2026-03-10-x-banner-session-error-prevention.md`: Error 3 documents the root cause
- `plugins/soleur/skills/gemini-imagegen/scripts/generate_image.py:82`: Current misleading error message
- `plugins/soleur/skills/gemini-imagegen/scripts/gemini_images.py:107-113`: Silent failure in library class
- `google-api-core` exceptions: `google.api_core.exceptions.ResourceExhausted`, `PermissionDenied`
