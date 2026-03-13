---
title: "fix: add quota-specific error detection to gemini-imagegen scripts"
type: fix
date: 2026-03-10
semver: patch
---

## Enhancement Summary

**Deepened on:** 2026-03-10
**Sections enhanced:** 5 (Proposed Solution, Technical Considerations, Implementation Approach, Test Scenarios, Dependencies & Risks)
**Research sources:** google-genai SDK source (errors.py), google-api-core exceptions docs, SDK issue #2024 (IMAGE_SAFETY hang), Gemini safety settings docs

### Key Improvements
1. **Corrected exception classes:** The plan originally proposed catching `google.api_core.exceptions.ResourceExhausted` -- this is wrong. The `google-genai` SDK uses its own `google.genai.errors.ClientError` (HTTP 429) and `google.genai.errors.APIError` hierarchy, not `google.api_core` exceptions.
2. **Discovered SDK hang bug:** Accessing `response.candidates[0].finish_reason` on IMAGE_SAFETY responses causes an indefinite hang (SDK issue #2024). Safety detection must avoid direct `finish_reason` access or use a timeout guard.
3. **Simplified error detection:** Since `google.genai.errors.ClientError` carries a `.code` attribute (HTTP status), detection reduces to `e.code == 429` (quota) and `e.code == 403` (permission) -- no need for separate exception class imports.

### New Considerations Discovered
- The SDK's `ClientError.code` attribute gives the HTTP status code directly -- check `429` for quota, `403` for permission, `400` for invalid request
- `ClientError.message` contains the API's error description which should be forwarded to the user
- IMAGE_SAFETY finish reasons can hang the SDK indefinitely -- do not access `finish_reason` without a timeout or guard

---

# fix: Add Quota-Specific Error Detection to gemini-imagegen Scripts

## Overview

All 5 gemini-imagegen Python scripts produce a misleading "check your prompt" error when the real problem is API quota exhaustion or permission denial. This fix replaces the generic catchall with differentiated error handling that names the actual cause.

## Problem Statement / Motivation

During the X banner session (#483), the scripts wasted time because a free-tier Gemini API key passed the `GEMINI_API_KEY` presence check and `genai.Client()` initialization, but failed on `generate_content()` with a quota error. The scripts caught the empty response and blamed the prompt: "No image was generated. Check your prompt and try again."

This is the wrong diagnosis. The prompt was fine -- the key had zero image generation quota. Docs-level mitigations (SKILL.md Phase 0 pre-flight, constitution rule) were already shipped in PR #489, but the scripts themselves still produce the misleading error.

## Proposed Solution

### 1. Wrap `generate_content()` / `send_message()` calls with specific exception handling

Catch `google.genai.errors.ClientError` and inspect `.code` to differentiate quota (429), permission (403), and other client errors. The `google-genai` SDK uses its own error hierarchy (`APIError` > `ClientError` / `ServerError`), **not** `google.api_core.exceptions`.

### Research Insights

**Correct exception hierarchy** (from `google/genai/errors.py` source):
- `google.genai.errors.APIError` -- base class, has `.code` (HTTP status), `.message`, `.status`
- `google.genai.errors.ClientError(APIError)` -- 4xx errors (quota, permission, invalid request)
- `google.genai.errors.ServerError(APIError)` -- 5xx errors (service unavailable)

**Error detection pattern:**
```python
from google.genai import errors

try:
    response = client.models.generate_content(...)
except errors.ClientError as e:
    if e.code == 429:
        # Quota exhausted / rate limited
        raise SystemExit(f"QUOTA EXHAUSTED: {e.message}")
    elif e.code == 403:
        # Permission denied / insufficient tier
        raise SystemExit(f"PERMISSION DENIED: {e.message}")
    else:
        raise SystemExit(f"API CLIENT ERROR ({e.code}): {e.message}")
except errors.ServerError as e:
    raise SystemExit(f"API SERVER ERROR ({e.code}): {e.message}")
```

### 2. Differentiate the "no image in response" path

When no exception is thrown but no image part is returned, check for safety filter indicators in the response text parts before defaulting to a generic message.

**Warning -- SDK hang bug (issue #2024):** Accessing `response.candidates[0].finish_reason` when the API returns `IMAGE_SAFETY` or `NO_IMAGE` causes an indefinite hang due to an unrecognized enum value in the SDK's validation logic. Safety detection must NOT access `finish_reason` directly. Instead, check:
1. Whether `response.parts` is empty or None
2. Whether any text part contains safety-related keywords ("blocked", "safety", "policy")
3. Whether `response.text` is available without hanging (text access is safe)

Error categories:

| Condition | Exception/Signal | Proposed Message |
|-----------|-----------------|------------------|
| Quota exhausted | `ClientError` with `.code == 429` | `QUOTA EXHAUSTED: Image generation quota is zero or exceeded. Free-tier keys may not include image generation. API: {e.message}` |
| Permission denied | `ClientError` with `.code == 403` | `PERMISSION DENIED: API key lacks image generation access. Check your Gemini API tier. API: {e.message}` |
| Invalid request | `ClientError` with `.code == 400` | `INVALID REQUEST: {e.message}` |
| Safety filter | No image parts + safety-related text in response | `SAFETY FILTER: Image was blocked by content policy. Rephrase the prompt.` |
| Empty response (other) | No image parts, no clear cause | `NO IMAGE IN RESPONSE: Model returned text only. Try a different model or prompt.` |
| Server error | `ServerError` | `API SERVER ERROR ({e.code}): {e.message}` |

### 3. Add `--check-quota` flag to `generate_image.py`

A dry-run mode that sends a minimal image generation request to verify quota before the caller commits to the full pipeline. Exit 0 on success, exit 1 on failure with a clear message.

### 4. Extract shared error handling into a helper module

All 5 scripts repeat the same `generate_content()` call-and-parse pattern. Extract the try/except and response-parsing logic into a shared helper (e.g., `_error_handling.py` or add methods to the existing `gemini_images.py` library class) to avoid duplicating the error-handling code 5 times.

## Technical Considerations

- **Exception classes:** Use `google.genai.errors.ClientError` and `google.genai.errors.ServerError`, NOT `google.api_core.exceptions`. The `google-genai` SDK has its own error module. Import with `from google.genai import errors`. No additional dependencies needed -- `errors` is part of the `google-genai` package itself.
- **HTTP status code detection:** `ClientError.code` gives the HTTP status directly: `429` = quota/rate limit, `403` = permission denied, `400` = invalid request. This is simpler and more robust than catching separate exception subclasses.
- **SDK hang bug (issue #2024):** Do NOT access `response.candidates[0].finish_reason` on image generation responses -- the SDK hangs indefinitely on unrecognized enum values like `IMAGE_SAFETY` and `NO_IMAGE`. Detect safety blocks by checking for empty `response.parts` and parsing text content for safety-related keywords instead.
- **`gemini_images.py` (library class):** The `GeminiImageGenerator` class methods (`generate`, `edit`, `compose`) and `ImageChat.send` all call `generate_content()` or `send_message()` but do NOT currently check for image presence -- they silently return `(output, None)` if no image part is found. This is a separate bug: the library silently fails where the CLI scripts raise. The fix should make the library raise too, matching CLI behavior.
- **`multi_turn_chat.py`:** Uses `chat.send_message()` which raises the same exception types (`ClientError`, `ServerError`). The error handling wraps identically.
- **No regression risk:** The new code paths only activate on error conditions. When quota is available and the response contains an image, behavior is unchanged.
- **`--check-quota` implementation:** Reuse the Phase 0 snippet from SKILL.md -- send `"Generate a 1x1 pixel red square"` with `response_modalities=["TEXT", "IMAGE"]` and check for either a `ClientError` (code 429/403) or the presence of an image part.
- **Graceful degradation:** If `google.genai.errors` cannot be imported (unlikely since it is part of the same package as `google.genai`), fall through to a bare `except Exception` that still surfaces the error message rather than showing "check your prompt".

## Non-Goals

- **Pillow fallback flag (`--fallback pillow`):** The issue mentions this as lower priority. The immediate fix is surfacing the real error. Pillow fallback can be a follow-up.
- **Retry logic for transient quota errors:** Rate-limit retries with backoff are out of scope. The scripts should report the error clearly and exit.
- **Changes to SKILL.md or constitution.md:** Already shipped in PR #489. This plan covers code-level fixes only.
- **Fixing the SDK hang bug (issue #2024):** That is an upstream SDK issue. The plan avoids triggering it by not accessing `finish_reason` directly.

## Acceptance Criteria

- [x] All 5 scripts catch `google.genai.errors.ClientError` with code 429 and display a "QUOTA EXHAUSTED" message (`generate_image.py`, `edit_image.py`, `compose_images.py`, `gemini_images.py`, `multi_turn_chat.py`)
- [x] All 5 scripts catch `ClientError` with code 403 and display a "PERMISSION DENIED" message
- [x] Generic "check your prompt" / silent failure replaced with specific error categories (safety filter, empty response)
- [x] `generate_image.py --check-quota` validates quota before generation (exit 0 on success, exit 1 on failure)
- [x] `gemini_images.py` library class raises on missing image parts instead of silently returning
- [x] Error handling logic is shared (not duplicated 5 times) -- either via a helper module or centralized in `gemini_images.py`
- [x] Existing functionality unchanged when quota is available (no regression)
- [x] No code accesses `response.candidates[N].finish_reason` (avoids SDK hang bug #2024)

## Test Scenarios

- Given a free-tier API key with zero image quota, when `generate_image.py` is run, then the output contains "QUOTA EXHAUSTED" and the API error message (not "check your prompt")
- Given an API key with valid quota, when `generate_image.py` is run with a valid prompt, then the image is saved and behavior is identical to current
- Given a prompt that triggers safety filters, when `generate_image.py` is run, then the output contains "SAFETY FILTER" (detected via empty parts + text inspection, not via `finish_reason`)
- Given `generate_image.py --check-quota`, when the key has valid quota, then exit code is 0 and output contains "[ok]"
- Given `generate_image.py --check-quota`, when the key has zero quota, then exit code is 1 and output contains "QUOTA EXHAUSTED"
- Given the `GeminiImageGenerator.generate()` library method, when the response contains no image parts, then it raises `RuntimeError` (not silent return)
- Given a `ClientError` with code 400 (invalid request), when any script is run, then the error message includes "INVALID REQUEST" and the API's message
- Given a `ServerError` (5xx), when any script is run, then the error message includes "API SERVER ERROR" and the status code

### Research Insights -- Edge Cases

- **429 with `Retry-After` header:** Some 429 responses include a `Retry-After` header. While retry logic is out of scope, the error message should mention "try again later" for transient rate limits vs. "quota is zero" for permanent exhaustion. Differentiate by checking if `e.message` contains "quota" or "rate limit".
- **Empty `response.parts`:** The `response.parts` attribute can be `None` (no candidates at all) or an empty list. Check both: `if not response.parts:`.
- **`response.text` for safety detection:** `response.text` is a convenience property that concatenates text parts. If the response has no text parts, it may raise. Wrap in try/except.

## Dependencies & Risks

- **Low risk:** Changes are additive exception handlers. No existing logic is removed or restructured.
- **Dependency:** `google.genai.errors` is part of the `google-genai` package (already required). No new dependencies needed.
- **Testing constraint:** Full integration testing requires both a valid-quota key and a zero-quota key. Unit tests can mock the exceptions by raising `errors.ClientError` with the appropriate code.
- **SDK hang risk:** The IMAGE_SAFETY finish_reason hang (issue #2024) means safety detection cannot use `finish_reason`. Text-based detection is less precise but avoids the hang.

## Implementation Approach

### Phase 1: Shared error handling helper

Create `plugins/soleur/skills/gemini-imagegen/scripts/_error_handling.py` with:

```python
"""Shared error handling for Gemini image generation scripts."""

from google.genai import errors


class QuotaExhaustedError(RuntimeError):
    """API key has zero or exceeded image generation quota."""
    pass


class PermissionDeniedError(RuntimeError):
    """API key lacks image generation access."""
    pass


class SafetyFilterError(RuntimeError):
    """Image was blocked by content policy."""
    pass


class NoImageError(RuntimeError):
    """Model returned no image in response."""
    pass


_SAFETY_KEYWORDS = ("blocked", "safety", "policy", "prohibited", "harmful")


def handle_api_error(e: errors.APIError) -> None:
    """Raise a descriptive error based on API error code."""
    if isinstance(e, errors.ClientError):
        if e.code == 429:
            raise QuotaExhaustedError(
                f"QUOTA EXHAUSTED: Image generation quota is zero or exceeded. "
                f"Free-tier keys may not include image generation.\n"
                f"API error: {e.message}"
            ) from e
        elif e.code == 403:
            raise PermissionDeniedError(
                f"PERMISSION DENIED: API key lacks image generation access. "
                f"Check your Gemini API tier.\n"
                f"API error: {e.message}"
            ) from e
        else:
            raise RuntimeError(
                f"API CLIENT ERROR ({e.code}): {e.message}"
            ) from e
    elif isinstance(e, errors.ServerError):
        raise RuntimeError(
            f"API SERVER ERROR ({e.code}): {e.message}"
        ) from e
    else:
        raise RuntimeError(f"API ERROR: {e.message}") from e


def check_response_for_image(response, output_path: str) -> tuple:
    """Parse response for image and text parts. Raise on missing image."""
    text_response = None
    image_saved = False

    if not response.parts:
        raise NoImageError(
            "NO IMAGE IN RESPONSE: Model returned empty response. "
            "Try a different model or prompt."
        )

    for part in response.parts:
        if part.text is not None:
            text_response = part.text
        elif part.inline_data is not None:
            image = part.as_image()
            image.save(output_path)
            image_saved = True

    if not image_saved:
        # Check for safety filter via text content
        if text_response and any(kw in text_response.lower() for kw in _SAFETY_KEYWORDS):
            raise SafetyFilterError(
                "SAFETY FILTER: Image was blocked by content policy. "
                "Rephrase the prompt."
            )
        raise NoImageError(
            "NO IMAGE IN RESPONSE: Model returned text only. "
            "Try a different model or prompt."
        )

    return text_response, image_saved


def check_quota(client, model: str = "gemini-2.5-flash-image") -> None:
    """Verify image generation quota with a minimal test request."""
    from google.genai import types

    try:
        response = client.models.generate_content(
            model=model,
            contents=["Generate a 1x1 pixel red square"],
            config=types.GenerateContentConfig(
                response_modalities=["TEXT", "IMAGE"]
            ),
        )
        # Check if image was actually generated
        has_image = response.parts and any(
            p.inline_data is not None for p in response.parts
        )
        if has_image:
            print(f"[ok] Image generation quota available (model: {model})")
        else:
            print(f"[WARN] No image in response -- quota may be unavailable")
            raise SystemExit(1)
    except errors.ClientError as e:
        handle_api_error(e)
```

### Phase 2: Update all 5 scripts

1. `generate_image.py` -- import from `_error_handling`, wrap `generate_content()` in try/except, add `--check-quota` argparse flag
2. `edit_image.py` -- import from `_error_handling`, wrap `generate_content()` in try/except, replace generic error
3. `compose_images.py` -- import from `_error_handling`, wrap `generate_content()` in try/except, replace generic error
4. `gemini_images.py` -- integrate error handling into `generate()`, `edit()`, `compose()`, and `ImageChat.send()`; raise on missing image parts
5. `multi_turn_chat.py` -- wrap `send_message()` calls with error handling from `_error_handling`

### Phase 3: Verify

1. Run `python3 -m py_compile` on all 6 files (5 existing + `_error_handling.py`) to verify no syntax errors
2. Run `python3 generate_image.py --check-quota` to validate the flag (requires GEMINI_API_KEY in env)
3. Verify `--help` output includes `--check-quota` documentation

## References & Research

### Internal References
- Issue #494: This issue
- PR #489: Docs-level fix (SKILL.md Phase 0 pre-flight, constitution rule)
- `knowledge-base/learnings/2026-03-10-x-banner-session-error-prevention.md`: Error 3 documents the root cause
- `plugins/soleur/skills/gemini-imagegen/scripts/generate_image.py:82`: Current misleading error message
- `plugins/soleur/skills/gemini-imagegen/scripts/gemini_images.py:107-113`: Silent failure in library class

### External References
- [google-genai SDK errors.py source](https://github.com/googleapis/python-genai/blob/main/google/genai/errors.py): Defines `APIError`, `ClientError`, `ServerError` with `.code`, `.message`, `.status` attributes
- [google-api-core exceptions docs](https://googleapis.dev/python/google-api-core/latest/exceptions.html): Documents `ResourceExhausted` (429) and `PermissionDenied` (403) -- these are NOT used by google-genai SDK
- [SDK issue #2024 -- IMAGE_SAFETY hang](https://github.com/googleapis/python-genai/issues/2024): Accessing `finish_reason` on IMAGE_SAFETY responses hangs indefinitely
- [Gemini safety settings docs](https://ai.google.dev/gemini-api/docs/safety-settings): Documents prompt_feedback and candidate safety ratings
- [Gemini quota error 429 guide](https://www.aifreeapi.com/en/posts/gemini-3-pro-image-generation-quota-exceeded): Documents common quota exhaustion patterns
