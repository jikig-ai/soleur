---
title: X Banner Session Error Prevention Strategies
date: 2026-03-10
category: runtime-errors
tags: [google-fonts, pillow, gemini-api, pencil-mcp, pip, banner-sizing, image-generation]
symptoms:
  - "Google Fonts download URL returned non-zip/non-font file"
  - "TTF URL returned HTML redirect instead of font binary"
  - "Gemini API key set but zero quota for image generation"
  - "Pencil MCP WebSocket not connected"
  - "pip install blocked by PEP 668"
  - "Banner text too small after first render"
module: community
---

# Learning: X Banner Session Error Prevention Strategies

Six distinct errors occurred during the X/Twitter banner generation session (#483). Each error class, its prevention strategy, detection method, and recommended approach is documented below.

## Error 1: Google Fonts Download URLs Returned Non-Zip Files

### What Happened

`fonts.google.com/download?family=Inter` returned an HTML page, not a downloadable ZIP. The Google Fonts website uses JavaScript-driven download flows that do not work with `curl` or `wget`.

### Prevention Strategy

Never use `fonts.google.com/download` for programmatic font acquisition. This endpoint is for browser-interactive use only.

### Detection Method

```bash
# After downloading, check the file type before using it
file downloaded-font.ttf
# Expected: "TrueType Font data" or "OpenType font data"
# Bad: "HTML document" or "Zip archive" with unexpected contents
```

### Recommended Approach

Use the Google Fonts CSS API to extract direct font file URLs:

```bash
# 1. Query the CSS API with a browser user-agent to get woff2 URLs
curl -s "https://fonts.googleapis.com/css2?family=Inter:wght@400;500;700&display=swap" \
  -H "User-Agent: Mozilla/5.0" | grep -oP 'url\(\K[^)]+\.woff2'

# 2. For TTF files, request with an older user-agent
curl -s "https://fonts.googleapis.com/css2?family=Inter:wght@400;500;700&display=swap" \
  -H "User-Agent: Python-urllib/3.0" | grep -oP 'url\(\K[^)]+\.ttf'

# 3. Alternatively, use the GitHub releases for google/fonts
# https://github.com/google/fonts/tree/main/ofl/<font-name>
```

For Pillow specifically, TTF is required (Pillow cannot render from woff2). The GitHub `google/fonts` repository hosts the raw TTF/OTF files directly.

---

## Error 2: Cormorant Garamond TTF URL Returned HTML Redirect

### What Happened

A direct URL to a Cormorant Garamond TTF file returned an HTML redirect page instead of the font binary. The CDN had changed its URL structure, and the old path redirected to a landing page.

### Prevention Strategy

Always validate downloaded font files before passing them to Pillow. Never assume a URL that worked previously still returns the same content.

### Detection Method

```bash
# Check HTTP response content-type before saving
curl -sI "https://example.com/font.ttf" | grep -i content-type
# Expected: application/font-sfnt, font/ttf, or application/octet-stream
# Bad: text/html

# After download, verify with file command
file font.ttf
# Expected: "TrueType Font data"
# Bad: "HTML document, ASCII text"
```

### Recommended Approach

Use the `google/fonts` GitHub repository as the canonical source for raw font files:

```bash
# Direct raw file download from GitHub (reliable, versioned)
curl -L -o cormorant-garamond.ttf \
  "https://raw.githubusercontent.com/google/fonts/main/ofl/cormorantgaramond/CormorantGaramond-Medium.ttf"

# Validate immediately
file cormorant-garamond.ttf | grep -q "TrueType" || echo "ERROR: Not a valid TTF file"
```

---

## Error 3: GEMINI_API_KEY Set but Zero Quota for Image Generation

### What Happened

`GEMINI_API_KEY` was present in the environment and validated against the text API, but image generation returned a quota error. The free tier has zero quota for image generation endpoints.

### Prevention Strategy

Before designing a pipeline that depends on Gemini image generation, verify that the API key has image generation quota -- not just text generation quota. Free tier keys authenticate successfully but return quota errors on image endpoints.

### Detection Method

```bash
# Test image generation quota with a minimal request BEFORE starting the pipeline
python3 -c "
import os
from google import genai
from google.genai import types

client = genai.Client(api_key=os.environ['GEMINI_API_KEY'])
try:
    response = client.models.generate_content(
        model='gemini-2.5-flash-image',
        contents=['Generate a 1x1 pixel red square'],
        config=types.GenerateContentConfig(response_modalities=['TEXT', 'IMAGE']),
    )
    print('Image generation quota: OK')
except Exception as e:
    print(f'Image generation quota: FAILED - {e}')
"
```

### Recommended Approach

1. Run the quota check as Phase 0 of any image generation pipeline -- before downloading fonts, creating mockups, or designing prompts
2. If quota is unavailable, fall back to Pillow-only generation (see "General Best Practices" below)
3. Add the quota check to the gemini-imagegen skill's SKILL.md as a required pre-flight step

---

## Error 4: Pencil MCP Failed Because .pen Tab Was Not Visible

### What Happened

Pencil MCP tools (`batch_design`, `batch_get`) failed with "WebSocket not connected" because the `.pen` file tab was not actively focused in Cursor IDE. The MCP server process was running, but the editor webview had no active connection.

### Prevention Strategy

This is a documented constraint (see `knowledge-base/project/learnings/2026-02-27-pencil-editor-operational-requirements.md`). Before any Pencil MCP operation:

1. Ask the user to open and focus the `.pen` tab in Cursor
2. Verify connection with `mcp__pencil__get_editor_state` before proceeding

### Detection Method

```
# Call get_editor_state first -- if it fails, the tab is not visible
mcp__pencil__get_editor_state
# Success: returns editor state JSON
# Failure: "WebSocket not connected to app: cursor"
```

### Recommended Approach

1. Always gate Pencil MCP operations behind a `get_editor_state` check
2. If check fails, output a clear instruction: "Open the .pen file tab in Cursor and click on it to activate the WebSocket connection"
3. For pipelines that may not need Pencil (like direct Pillow rendering), skip the Pencil step entirely rather than blocking on IDE state
4. Constitution.md already documents this requirement -- no new rule needed

---

## Error 5: pip install Blocked by PEP 668 on Modern Linux

### What Happened

`pip install Pillow google-genai` failed with "externally-managed-environment" error. PEP 668 (adopted by Ubuntu 24.04+, Fedora 38+, Arch) prevents `pip install` in the system Python environment to avoid breaking system packages.

### Prevention Strategy

Never use bare `pip install` on modern Linux. Always use a virtual environment or `pipx`.

### Detection Method

```bash
# Check if the system enforces PEP 668
python3 -c "import sysconfig; print(sysconfig.get_path('stdlib'))" 2>/dev/null
ls /usr/lib/python*/EXTERNALLY-MANAGED 2>/dev/null && echo "PEP 668 enforced" || echo "PEP 668 not enforced"
```

### Recommended Approach

```bash
# Create a project-local venv (preferred)
python3 -m venv .venv
source .venv/bin/activate
pip install Pillow google-genai

# Alternative: use pipx for CLI tools
pipx install <package>

# Alternative: use --user flag (works on some systems)
pip install --user Pillow
```

For scripts in `plugins/soleur/skills/gemini-imagegen/scripts/`, document the venv requirement in the skill's SKILL.md Phase 0.

---

## Error 6: Banner Text Too Small -- Required 2 Iterations

### What Happened

Initial text sizes (wordmark 28px, thesis 44px, metrics 16px) were unreadable at 1500x500 banner scale. Two rounds of increase were needed:

- Round 1: 28/44/16 (too small)
- Round 2: 42/64/22 (still small)
- Round 3: 52/82/26 (acceptable)

The final sizes were roughly 2x the initial guesses.

### Prevention Strategy

Use the **1% rule** as a baseline for banner text sizing: primary text height should be approximately 10-16% of the image height, secondary text 6-10%. For a 500px-tall banner:

- Primary text (thesis/headline): 50-80px (10-16% of 500)
- Secondary text (wordmark): 40-60px (8-12% of 500)
- Tertiary text (metrics/labels): 20-30px (4-6% of 500)

### Detection Method

```python
# Before rendering, validate font sizes against image dimensions
def validate_text_sizes(image_height, sizes):
    """Check that text sizes are proportional to image dimensions."""
    for label, size in sizes.items():
        pct = (size / image_height) * 100
        if pct < 4:
            print(f"WARNING: {label} at {size}px is {pct:.1f}% of image height -- likely too small")
        elif pct > 20:
            print(f"WARNING: {label} at {size}px is {pct:.1f}% of image height -- likely too large")

validate_text_sizes(500, {"wordmark": 52, "thesis": 82, "metrics": 26})
```

### Recommended Approach

Start with the proportional sizing table below and adjust from there (one iteration instead of three):

| Element Type | % of Image Height | At 500px height | At 1080px height |
|-------------|-------------------|-----------------|-----------------|
| Primary headline | 12-16% | 60-80px | 130-170px |
| Secondary text | 8-12% | 40-60px | 85-130px |
| Tertiary/label | 4-6% | 20-30px | 43-65px |
| Fine print | 2-3% | 10-15px | 22-32px |

---

## General Best Practices

### Font File Acquisition for Programmatic Use

1. **Primary source:** `github.com/google/fonts` repository -- raw TTF/OTF files, versioned, no redirects
2. **Secondary source:** Google Fonts CSS API with `User-Agent: Python-urllib/3.0` header to get TTF URLs (woff2 is default for modern browsers)
3. **Never use:** `fonts.google.com/download` (browser-only), direct CDN URLs from old documentation (may redirect)
4. **Always validate:** Run `file <downloaded.ttf>` immediately after download; abort if not "TrueType Font data"
5. **Cache locally:** Store validated font files in `tmp/` or `assets/fonts/` to avoid re-downloading on retry
6. **Variable fonts:** Check if the CSS API returns the same URL for multiple weights -- if so, use one file with `font-weight: <min> <max>` range syntax (see `knowledge-base/project/learnings/2026-02-14-google-fonts-variable-font-deduplication.md`)

### Pillow Banner/Image Generation Sizing Guidelines

1. **Text sizing:** Use percentage-of-image-height, not absolute pixel values. Start at 12-16% for headlines
2. **Safe zones:** For social media banners, keep all text within the center 60% horizontally and center 80% vertically
3. **Letter spacing:** For wide-spaced wordmarks, calculate `textbbox` after adding spacing characters (e.g., "S O L E U R" not "SOLEUR") to get accurate centering
4. **Anti-aliasing:** Pillow's text rendering benefits from rendering at 2x resolution then downscaling with `Image.LANCZOS` for smoother edges
5. **Color mode:** Use RGBA for compositing layers, convert to RGB only for final save as JPEG
6. **Preview at actual size:** Pillow images look different zoomed in an image viewer vs. displayed at actual pixel size in a browser -- always check at 100% zoom

### Graceful Fallback When AI Image Generation is Unavailable

When Gemini (or any AI image generation API) is unavailable due to quota, pricing tier, or network issues:

1. **Pillow-only pipeline:** Generate the entire image programmatically with Pillow
   - Solid or gradient backgrounds (`ImageDraw.rectangle`, linear gradient via pixel manipulation)
   - Text overlay with `ImageDraw.text` and `ImageFont.truetype`
   - Geometric decorative elements (lines, rectangles, circles)
2. **Hybrid downgrade:** If AI was planned for texture/background only, use a solid brand-color background and proceed with the text overlay pipeline unchanged
3. **Quality comparison:** AI-generated backgrounds add visual richness but are not required for a professional banner. A clean solid-color design with well-set typography is superior to a failed or low-quality AI generation
4. **Retry strategy:** If quota is temporarily exhausted, log the error and offer to retry later rather than blocking the entire workflow. Save the Pillow-only version as an interim deliverable

## Tags

category: runtime-errors
module: community
