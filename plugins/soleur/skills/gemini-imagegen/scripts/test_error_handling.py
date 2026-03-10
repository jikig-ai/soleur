"""Tests for _error_handling module."""

import unittest
from unittest.mock import MagicMock

from google.genai import errors

from _error_handling import (
    NoImageError,
    PermissionDeniedError,
    QuotaExhaustedError,
    SafetyFilterError,
    check_quota,
    handle_api_error,
    parse_image_response,
)


def _make_client_error(code: int, message: str = "test error"):
    """Create a ClientError with the given code using the real constructor."""
    response_json = {"error": {"message": message, "code": code}}
    return errors.ClientError(code, response_json)


def _make_server_error(code: int = 500, message: str = "server error"):
    """Create a ServerError with the given code using the real constructor."""
    response_json = {"error": {"message": message, "code": code}}
    return errors.ServerError(code, response_json)


def _make_response(parts=None):
    """Create a mock response with the given parts."""
    response = MagicMock()
    response.parts = parts
    return response


def _make_text_part(text: str):
    """Create a mock text part."""
    part = MagicMock()
    part.text = text
    part.inline_data = None
    return part


def _make_image_part():
    """Create a mock image part that returns a saveable image."""
    part = MagicMock()
    part.text = None
    part.inline_data = MagicMock()
    mock_image = MagicMock()
    part.as_image.return_value = mock_image
    return part


class TestHandleApiError(unittest.TestCase):
    def test_quota_exhausted_on_429(self):
        err = _make_client_error(429, "Rate limit exceeded")
        with self.assertRaises(QuotaExhaustedError) as ctx:
            handle_api_error(err)
        self.assertIn("QUOTA EXHAUSTED", str(ctx.exception))

    def test_permission_denied_on_403(self):
        err = _make_client_error(403, "Forbidden")
        with self.assertRaises(PermissionDeniedError) as ctx:
            handle_api_error(err)
        self.assertIn("PERMISSION DENIED", str(ctx.exception))

    def test_generic_client_error_on_400(self):
        err = _make_client_error(400, "Invalid request")
        with self.assertRaises(RuntimeError) as ctx:
            handle_api_error(err)
        self.assertIn("API CLIENT ERROR (400)", str(ctx.exception))

    def test_server_error_on_500(self):
        err = _make_server_error(500, "Internal server error")
        with self.assertRaises(RuntimeError) as ctx:
            handle_api_error(err)
        self.assertIn("API SERVER ERROR (500)", str(ctx.exception))

    def test_chains_original_exception(self):
        err = _make_client_error(429, "Rate limit")
        with self.assertRaises(QuotaExhaustedError) as ctx:
            handle_api_error(err)
        self.assertIs(ctx.exception.__cause__, err)


class TestParseImageResponse(unittest.TestCase):
    def test_raises_on_empty_parts(self):
        response = _make_response(parts=None)
        with self.assertRaises(NoImageError) as ctx:
            parse_image_response(response)
        self.assertIn("empty response", str(ctx.exception))

    def test_raises_on_empty_list(self):
        response = _make_response(parts=[])
        with self.assertRaises(NoImageError):
            parse_image_response(response)

    def test_returns_image_and_text(self):
        text_part = _make_text_part("Here's your image")
        image_part = _make_image_part()
        response = _make_response(parts=[text_part, image_part])

        image, text = parse_image_response(response)

        self.assertEqual(text, "Here's your image")
        self.assertIsNotNone(image)

    def test_safety_filter_detected_via_text(self):
        text_part = _make_text_part("The image was blocked by safety policy")
        response = _make_response(parts=[text_part])

        with self.assertRaises(SafetyFilterError) as ctx:
            parse_image_response(response)
        self.assertIn("SAFETY FILTER", str(ctx.exception))

    def test_no_image_text_only(self):
        text_part = _make_text_part("Here is some text about your request")
        response = _make_response(parts=[text_part])

        with self.assertRaises(NoImageError) as ctx:
            parse_image_response(response)
        self.assertIn("text only", str(ctx.exception))

    def test_image_only_no_text(self):
        image_part = _make_image_part()
        response = _make_response(parts=[image_part])

        image, text = parse_image_response(response)

        self.assertIsNone(text)
        self.assertIsNotNone(image)

    def test_safety_keywords_case_insensitive(self):
        text_part = _make_text_part("This content was BLOCKED by our POLICY")
        response = _make_response(parts=[text_part])

        with self.assertRaises(SafetyFilterError):
            parse_image_response(response)

    def test_no_false_positive_on_unrelated_text(self):
        text_part = _make_text_part("Just text, no special keywords present")
        response = _make_response(parts=[text_part])

        with self.assertRaises(NoImageError):
            parse_image_response(response)


class TestCheckQuota(unittest.TestCase):
    def test_quota_available(self):
        client = MagicMock()
        image_part = _make_image_part()
        response = _make_response(parts=[image_part])
        client.models.generate_content.return_value = response

        # Should not raise
        check_quota(client, model="gemini-2.5-flash-image")

    def test_quota_exhausted_via_api_error(self):
        client = MagicMock()
        err = _make_client_error(429, "Quota exceeded")
        client.models.generate_content.side_effect = err

        with self.assertRaises(QuotaExhaustedError):
            check_quota(client, model="gemini-2.5-flash-image")

    def test_no_image_in_response_raises(self):
        client = MagicMock()
        text_part = _make_text_part("no image here")
        response = _make_response(parts=[text_part])
        client.models.generate_content.return_value = response

        with self.assertRaises(NoImageError):
            check_quota(client, model="gemini-2.5-flash-image")


if __name__ == "__main__":
    unittest.main()
