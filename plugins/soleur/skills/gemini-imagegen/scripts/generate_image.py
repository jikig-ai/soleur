#!/usr/bin/env python3
"""
Generate images from text prompts using Gemini API.

Usage:
    python generate_image.py "prompt" output.png [--model MODEL] [--aspect RATIO] [--size SIZE]

Examples:
    python generate_image.py "A cat in space" cat.png
    python generate_image.py "A logo for Acme Corp" logo.png --model gemini-3-pro-image-preview --aspect 1:1
    python generate_image.py "Epic landscape" landscape.png --aspect 16:9 --size 2K

Environment:
    GEMINI_API_KEY - Required API key
"""

import argparse
import os
import sys

from google import genai
from google.genai import errors, types

from _error_handling import check_quota, check_response_for_image, handle_api_error


def generate_image(
    prompt: str,
    output_path: str,
    model: str = "gemini-2.5-flash-image",
    aspect_ratio: str | None = None,
    image_size: str | None = None,
) -> str | None:
    """Generate an image from a text prompt.
    
    Args:
        prompt: Text description of the image to generate
        output_path: Path to save the generated image
        model: Gemini model to use
        aspect_ratio: Aspect ratio (1:1, 16:9, 9:16, etc.)
        image_size: Resolution (1K, 2K, 4K - 4K only for pro model)
    
    Returns:
        Any text response from the model, or None
    """
    api_key = os.environ.get("GEMINI_API_KEY")
    if not api_key:
        raise EnvironmentError("GEMINI_API_KEY environment variable not set")
    
    client = genai.Client(api_key=api_key)
    
    # Build config
    config_kwargs = {"response_modalities": ["TEXT", "IMAGE"]}
    
    image_config_kwargs = {}
    if aspect_ratio:
        image_config_kwargs["aspect_ratio"] = aspect_ratio
    if image_size:
        image_config_kwargs["image_size"] = image_size
    
    if image_config_kwargs:
        config_kwargs["image_config"] = types.ImageConfig(**image_config_kwargs)
    
    config = types.GenerateContentConfig(**config_kwargs)
    
    try:
        response = client.models.generate_content(
            model=model,
            contents=[prompt],
            config=config,
        )
    except errors.ClientError as e:
        handle_api_error(e)
    except errors.ServerError as e:
        handle_api_error(e)

    text_response, _ = check_response_for_image(response, output_path)
    return text_response


def main():
    parser = argparse.ArgumentParser(
        description="Generate images from text prompts using Gemini API",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__
    )
    parser.add_argument("prompt", nargs="?", help="Text prompt describing the image")
    parser.add_argument("output", nargs="?", help="Output file path (e.g., output.png)")
    parser.add_argument(
        "--model", "-m",
        default="gemini-2.5-flash-image",
        choices=["gemini-2.5-flash-image", "gemini-3-pro-image-preview"],
        help="Model to use (default: gemini-2.5-flash-image)"
    )
    parser.add_argument(
        "--aspect", "-a",
        choices=["1:1", "2:3", "3:2", "3:4", "4:3", "4:5", "5:4", "9:16", "16:9", "21:9"],
        help="Aspect ratio"
    )
    parser.add_argument(
        "--size", "-s",
        choices=["1K", "2K", "4K"],
        help="Image resolution (4K only available with pro model)"
    )
    parser.add_argument(
        "--check-quota",
        action="store_true",
        help="Verify image generation quota without generating an image"
    )

    args = parser.parse_args()

    if not args.check_quota and (not args.prompt or not args.output):
        parser.error("prompt and output are required (unless --check-quota is used)")

    if args.check_quota:
        try:
            api_key = os.environ.get("GEMINI_API_KEY")
            if not api_key:
                print("GEMINI_API_KEY environment variable not set", file=sys.stderr)
                sys.exit(1)
            client = genai.Client(api_key=api_key)
            check_quota(client, model=args.model)
        except SystemExit:
            raise
        except Exception as e:
            print(f"[FAIL] {e}", file=sys.stderr)
            sys.exit(1)
        return

    try:
        text = generate_image(
            prompt=args.prompt,
            output_path=args.output,
            model=args.model,
            aspect_ratio=args.aspect,
            image_size=args.size,
        )

        print(f"Image saved to: {args.output}")
        if text:
            print(f"Model response: {text}")

    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
