"""Shared error handling for Gemini image generation scripts.

Error messages include raw API responses intentionally for CLI debugging.
Sanitize before surfacing in user-facing web contexts.
"""

from typing import NoReturn

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


def handle_api_error(e: errors.APIError) -> NoReturn:
    """Raise a descriptive error based on API error code.

    Converts google.genai SDK exceptions into specific error types.
    """
    if isinstance(e, errors.ClientError):
        if e.code == 429:
            raise QuotaExhaustedError(
                "QUOTA EXHAUSTED: Image generation quota is zero or exceeded. "
                "Free-tier keys may not include image generation.\n"
                f"API error: {e.message}"
            ) from e
        elif e.code == 403:
            raise PermissionDeniedError(
                "PERMISSION DENIED: API key lacks image generation access. "
                "Check your Gemini API tier.\n"
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
    # Forward-compatibility guard for future APIError subclasses
    raise RuntimeError(f"API ERROR: {e.message}") from e


def parse_image_response(response) -> tuple[object | None, str | None]:
    """Parse a Gemini response for image and text parts.

    Does NOT access response.candidates[N].finish_reason to avoid
    SDK hang bug (issue #2024).

    Args:
        response: The GenerateContentResponse or SendMessageResponse.

    Returns:
        Tuple of (PIL Image or None, text_response or None).

    Raises:
        NoImageError: If response contains no image parts.
        SafetyFilterError: If image was blocked by content policy.
    """
    if not response.parts:
        raise NoImageError(
            "NO IMAGE IN RESPONSE: Model returned empty response. "
            "Try a different model or prompt."
        )

    text_response = None
    image_result = None

    for part in response.parts:
        if part.text is not None:
            text_response = part.text
        elif part.inline_data is not None:
            image_result = part.as_image()

    if image_result is None:
        response_text = text_response or ""
        if any(kw in response_text.lower() for kw in _SAFETY_KEYWORDS):
            raise SafetyFilterError(
                "SAFETY FILTER: Image was blocked by content policy. "
                "Rephrase the prompt."
            )
        raise NoImageError(
            "NO IMAGE IN RESPONSE: Model returned text only. "
            "Try a different model or prompt."
        )

    return image_result, text_response


def check_quota(client, model: str = "gemini-2.5-flash-image") -> None:
    """Verify image generation quota with a minimal test request.

    Sends a trivial prompt and checks if the API returns an image.
    Prints status and raises on failure.

    Args:
        client: An initialized genai.Client instance.
        model: The model to test against.
    """
    from google.genai import types

    try:
        response = client.models.generate_content(
            model=model,
            contents=["Generate a 1x1 pixel red square"],
            config=types.GenerateContentConfig(
                response_modalities=["TEXT", "IMAGE"]
            ),
        )
    except errors.APIError as e:
        handle_api_error(e)

    has_image = response.parts and any(
        p.inline_data is not None for p in response.parts
    )
    if has_image:
        print(f"[ok] Image generation quota available (model: {model})")
    else:
        raise NoImageError(
            f"[FAIL] No image in response -- quota may be unavailable (model: {model})"
        )
