"""
Gemini Image Generation Library

A simple Python library for generating and editing images with the Gemini API.

Usage:
    from gemini_images import GeminiImageGenerator
    
    gen = GeminiImageGenerator()
    gen.generate("A sunset over mountains", "sunset.png")
    gen.edit("input.png", "Add clouds", "output.png")

Environment:
    GEMINI_API_KEY - Required API key
"""

import os
from pathlib import Path
from typing import Literal

from PIL import Image
from google import genai
from google.genai import errors, types

from _error_handling import check_response_for_image, check_response_parts, handle_api_error


AspectRatio = Literal["1:1", "2:3", "3:2", "3:4", "4:3", "4:5", "5:4", "9:16", "16:9", "21:9"]
ImageSize = Literal["1K", "2K", "4K"]
Model = Literal["gemini-2.5-flash-image", "gemini-3-pro-image-preview"]


class GeminiImageGenerator:
    """High-level interface for Gemini image generation."""
    
    FLASH = "gemini-2.5-flash-image"
    PRO = "gemini-3-pro-image-preview"
    
    def __init__(self, api_key: str | None = None, model: Model = FLASH):
        """Initialize the generator.
        
        Args:
            api_key: Gemini API key (defaults to GEMINI_API_KEY env var)
            model: Default model to use
        """
        self.api_key = api_key or os.environ.get("GEMINI_API_KEY")
        if not self.api_key:
            raise EnvironmentError("GEMINI_API_KEY not set")
        
        self.client = genai.Client(api_key=self.api_key)
        self.model = model
    
    def _build_config(
        self,
        aspect_ratio: AspectRatio | None = None,
        image_size: ImageSize | None = None,
        google_search: bool = False,
    ) -> types.GenerateContentConfig:
        """Build generation config."""
        kwargs = {"response_modalities": ["TEXT", "IMAGE"]}
        
        img_config = {}
        if aspect_ratio:
            img_config["aspect_ratio"] = aspect_ratio
        if image_size:
            img_config["image_size"] = image_size
        
        if img_config:
            kwargs["image_config"] = types.ImageConfig(**img_config)
        
        if google_search:
            kwargs["tools"] = [{"google_search": {}}]
        
        return types.GenerateContentConfig(**kwargs)
    
    def generate(
        self,
        prompt: str,
        output: str | Path,
        *,
        model: Model | None = None,
        aspect_ratio: AspectRatio | None = None,
        image_size: ImageSize | None = None,
        google_search: bool = False,
    ) -> tuple[Path, str | None]:
        """Generate an image from a text prompt.
        
        Args:
            prompt: Text description
            output: Output file path
            model: Override default model
            aspect_ratio: Output aspect ratio
            image_size: Output resolution
            google_search: Enable Google Search grounding (Pro only)
        
        Returns:
            Tuple of (output path, optional text response)
        """
        output = Path(output)
        config = self._build_config(aspect_ratio, image_size, google_search)

        try:
            response = self.client.models.generate_content(
                model=model or self.model,
                contents=[prompt],
                config=config,
            )
        except errors.ClientError as e:
            handle_api_error(e)
        except errors.ServerError as e:
            handle_api_error(e)

        text, _ = check_response_for_image(response, str(output))
        return output, text
    
    def edit(
        self,
        input_image: str | Path | Image.Image,
        instruction: str,
        output: str | Path,
        *,
        model: Model | None = None,
        aspect_ratio: AspectRatio | None = None,
        image_size: ImageSize | None = None,
    ) -> tuple[Path, str | None]:
        """Edit an existing image.
        
        Args:
            input_image: Input image (path or PIL Image)
            instruction: Edit instruction
            output: Output file path
            model: Override default model
            aspect_ratio: Output aspect ratio
            image_size: Output resolution
        
        Returns:
            Tuple of (output path, optional text response)
        """
        output = Path(output)

        if isinstance(input_image, (str, Path)):
            input_image = Image.open(input_image)

        config = self._build_config(aspect_ratio, image_size)

        try:
            response = self.client.models.generate_content(
                model=model or self.model,
                contents=[instruction, input_image],
                config=config,
            )
        except errors.ClientError as e:
            handle_api_error(e)
        except errors.ServerError as e:
            handle_api_error(e)

        text, _ = check_response_for_image(response, str(output))
        return output, text
    
    def compose(
        self,
        instruction: str,
        images: list[str | Path | Image.Image],
        output: str | Path,
        *,
        model: Model | None = None,
        aspect_ratio: AspectRatio | None = None,
        image_size: ImageSize | None = None,
    ) -> tuple[Path, str | None]:
        """Compose multiple images into one.
        
        Args:
            instruction: Composition instruction
            images: List of input images (up to 14)
            output: Output file path
            model: Override default model (Pro recommended)
            aspect_ratio: Output aspect ratio
            image_size: Output resolution
        
        Returns:
            Tuple of (output path, optional text response)
        """
        output = Path(output)

        # Load images
        loaded = []
        for img in images:
            if isinstance(img, (str, Path)):
                loaded.append(Image.open(img))
            else:
                loaded.append(img)

        config = self._build_config(aspect_ratio, image_size)
        contents = [instruction] + loaded

        try:
            response = self.client.models.generate_content(
                model=model or self.PRO,  # Pro recommended for composition
                contents=contents,
                config=config,
            )
        except errors.ClientError as e:
            handle_api_error(e)
        except errors.ServerError as e:
            handle_api_error(e)

        text, _ = check_response_for_image(response, str(output))
        return output, text
    
    def chat(self) -> "ImageChat":
        """Start an interactive chat session for iterative refinement."""
        return ImageChat(self.client, self.model)


class ImageChat:
    """Multi-turn chat session for iterative image generation."""
    
    def __init__(self, client: genai.Client, model: Model):
        self.client = client
        self.model = model
        self._chat = client.chats.create(
            model=model,
            config=types.GenerateContentConfig(response_modalities=["TEXT", "IMAGE"]),
        )
        self.current_image: Image.Image | None = None
    
    def send(
        self,
        message: str,
        image: Image.Image | str | Path | None = None,
    ) -> tuple[Image.Image | None, str | None]:
        """Send a message and optionally an image.
        
        Returns:
            Tuple of (generated image or None, text response or None)
        """
        contents = [message]
        if image:
            if isinstance(image, (str, Path)):
                image = Image.open(image)
            contents.append(image)

        try:
            response = self._chat.send_message(contents)
        except errors.ClientError as e:
            handle_api_error(e)
        except errors.ServerError as e:
            handle_api_error(e)

        img, text = check_response_parts(response)
        if img is not None:
            self.current_image = img

        return img, text
    
    def reset(self):
        """Reset the chat session."""
        self._chat = self.client.chats.create(
            model=self.model,
            config=types.GenerateContentConfig(response_modalities=["TEXT", "IMAGE"]),
        )
        self.current_image = None
