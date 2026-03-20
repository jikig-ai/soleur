# Learning: Gemini SDK Error Handling Patterns

## Problem

The `google-genai` Python SDK uses its own error hierarchy (`google.genai.errors.APIError` > `ClientError` / `ServerError`), NOT the `google.api_core.exceptions` that Google Cloud libraries typically use. Scripts catching `google.api_core.exceptions.ResourceExhausted` will silently miss quota errors. Additionally, accessing `response.candidates[N].finish_reason` on image safety responses causes an indefinite SDK hang (issue #2024).

## Solution

1. Import from `google.genai.errors`, not `google.api_core.exceptions`
2. Catch `errors.APIError` (base class) rather than separate `ClientError`/`ServerError` — both call the same handler
3. Use `e.code` for HTTP status (429=quota, 403=permission, 400=invalid) and `e.message` for details
4. Detect safety filters via text-part keyword scanning, never via `finish_reason`
5. Use `-> NoReturn` type annotation on error handlers that always raise, so callers' `response` variable is provably bound
6. When creating a shared response parser, return the image object and let callers save — avoids duplicating the function for save-to-disk vs return-image use cases

## Key Insight

When wrapping an SDK's error handling, check the actual SDK source for its exception hierarchy before assuming it follows the broader ecosystem's patterns. The `google-genai` SDK is a standalone package with its own `errors.py`, not a wrapper around `google-api-core`.

## Session Errors

1. **Wrong constructor signature in tests**: `ClientError(message)` fails — actual signature is `ClientError(code, response_json)`. Always check real constructors when writing test helpers.
2. **Safety keyword false positive**: Test text "no safety keywords here" matched "safety" in keyword detection. Test data must not accidentally contain the keywords being tested.
3. **Committed `__pycache__/`**: Python bytecode cache was staged because `.gitignore` lacked `__pycache__/`. Added to `.gitignore` and cleaned up.

## Tags
category: integration-issues
module: gemini-imagegen
