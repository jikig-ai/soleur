"""Shared frontmatter parser/serializer used by repo-root scripts and plugin skills.

Extracted from scripts/backfill-frontmatter.py so /soleur:resolve-debt and any
future consumer can `from frontmatter_lib import parse_frontmatter` without
the importlib.util dance forced by a hyphenated filename.

Public API:
- parse_frontmatter(content) -> (fm_dict_or_None, body, raw_fm_text)
- serialize_frontmatter(fm)  -> "---\\n...---\\n" string
- format_field(key, value)   -> "key: value" YAML-safe line
"""

import yaml


def parse_frontmatter(content):
    """Parse YAML frontmatter from content. Returns (frontmatter_dict, body, raw_fm_text)."""
    if not content.startswith("---\n"):
        return None, content, ""

    # Find closing ---
    # Must be within first 30 lines to avoid matching horizontal rules
    lines = content.split("\n")
    end_idx = None
    for i in range(1, min(len(lines), 30)):
        if lines[i].strip() == "---":
            end_idx = i
            break

    if end_idx is None:
        return None, content, ""

    fm_text = "\n".join(lines[1:end_idx])
    body = "\n".join(lines[end_idx + 1:])

    try:
        fm = yaml.safe_load(fm_text)
        if not isinstance(fm, dict):
            return None, content, ""
        return fm, body, fm_text
    except yaml.YAMLError:
        # Fallback: parse line-by-line for files with broken YAML (e.g., nested quotes)
        fm = {}
        for line in fm_text.split("\n"):
            if ":" in line and not line.startswith("  "):
                key, _, val = line.partition(":")
                key = key.strip()
                val = val.strip()
                # Strip outer quotes
                if val.startswith('"') and val.endswith('"'):
                    val = val[1:-1]
                elif val.startswith("'") and val.endswith("'"):
                    val = val[1:-1]
                # Parse inline arrays [a, b, c]
                if val.startswith("[") and val.endswith("]"):
                    items = [v.strip().strip('"').strip("'") for v in val[1:-1].split(",")]
                    fm[key] = [i for i in items if i]
                else:
                    fm[key] = val
        if fm:
            return fm, body, fm_text
        return None, content, ""


def serialize_frontmatter(fm):
    """Serialize frontmatter dict to YAML string between --- delimiters."""
    # Custom ordering: required fields first, then optional
    required_order = ["title", "date", "category", "tags"]
    optional_order = ["symptoms", "module", "synced_to"]

    lines = ["---"]
    seen = set()

    for key in required_order:
        if key in fm:
            lines.append(format_field(key, fm[key]))
            seen.add(key)

    for key in optional_order:
        if key in fm:
            lines.append(format_field(key, fm[key]))
            seen.add(key)

    # Any remaining fields (CORA-specific, etc.)
    for key in sorted(fm.keys()):
        if key not in seen:
            lines.append(format_field(key, fm[key]))

    lines.append("---")
    return "\n".join(lines)


def format_field(key, value):
    """Format a single YAML field."""
    if isinstance(value, list):
        if all(isinstance(v, str) for v in value):
            formatted = ", ".join(value)
            return f"{key}: [{formatted}]"
        # Multi-line array
        lines = [f"{key}:"]
        for item in value:
            lines.append(f"  - {item}")
        return "\n".join(lines)
    if isinstance(value, str):
        needs_quoting = any(c in value for c in ':[]{}#&*!|>\'"@`')
        if needs_quoting:
            # Use single quotes to avoid double-quote escaping issues
            escaped = value.replace("'", "''")
            return f"{key}: '{escaped}'"
        return f"{key}: {value}"
    return f"{key}: {value}"
