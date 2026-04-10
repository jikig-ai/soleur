#!/usr/bin/env python3
"""Backfill YAML frontmatter on learnings files to match constitution schema.

Required fields: title, date, category, tags
Optional preserved: symptoms, module, synced_to, and any CORA-specific fields

Idempotent: safe to run multiple times with identical results.
"""

import hashlib
import os
import re
import subprocess
import sys
import yaml

LEARNINGS_DIR = "knowledge-base/project/learnings"

# --- Statistics ---
stats = {"processed": 0, "created": 0, "augmented": 0, "skipped": 0, "errors": 0}


# --- Category Inference ---

def infer_category(slug):
    """Infer category from filename slug. Most specific patterns first."""
    patterns = [
        # Compound patterns (most specific)
        (r"github-action|gha-|claude-code-action", "ci-cd"),
        (r"worktree|merge-pr|ship-|cleanup-merged", "workflow-patterns"),
        (r"agent-description|agent-prompt|disambiguation", "agent-design"),
        # Domain-specific
        (r"gdpr|cla-|license|privacy|legal-", "legal"),
        (r"marketing|seo-|aeo-|brand-", "marketing"),
        (r"mcp|pencil|terraform|discord|telegram", "infrastructure"),
        (r"docs-site|landing-page|css-|grid-|font-", "ui-css"),
        # General patterns
        (r"ci-|release|version-bump|workflow-security", "ci-cd"),
        (r"merge|pr-|commit|branch|git-|rebase", "workflow-patterns"),
        (r"agent|prompt|subagent|domain-leader", "agent-design"),
        (r"shell|bash|grep|sed|jq|pipefail|shebang|awk", "shell-scripting"),
        (r"plugin|skill|command|loader", "plugin-architecture"),
        (r"security|secret|api-key|leak", "security"),
        (r"docs|brand|constitution", "documentation"),
        (r"strategy|pricing|competitive|growth", "marketing"),
    ]
    for pattern, category in patterns:
        if re.search(pattern, slug):
            return category
    return "engineering"


# --- Metadata Extraction ---

def extract_title(content):
    """Extract title from first # heading, stripping common prefixes."""
    match = re.search(r"^# (.+)$", content, re.MULTILINE)
    if not match:
        return ""
    title = match.group(1).strip()
    title = re.sub(r"^(Learning|Learnings|Troubleshooting):\s*", "", title)
    return title


def extract_date_from_filename(filename):
    """Extract YYYY-MM-DD date from filename prefix."""
    match = re.match(r"(\d{4}-\d{2}-\d{2})-", filename)
    return match.group(1) if match else ""


def extract_inline_date(content):
    """Extract date from **Date:** inline format."""
    match = re.search(r"\*\*Date:\*\*\s*(\d{4}-\d{2}-\d{2})", content)
    return match.group(1) if match else ""


def extract_inline_tags(content):
    """Extract tags from **Tags:** or ## Tags section."""
    # Check **Tags:** inline format (comma-separated)
    match = re.search(r"\*\*Tags:\*\*\s*(.+)", content)
    if match:
        raw = match.group(1).strip()
        return normalize_tags(raw)

    # Check ## Tags section
    match = re.search(r"^## Tags[ \t]*\n((?:[^\n]|\n(?!\n|#))+)", content, re.MULTILINE)
    if match:
        raw = match.group(1).strip()
        if raw:
            # Detect key: value format (CORA-style inline metadata)
            lines = raw.strip().split("\n")
            if all(":" in line for line in lines if line.strip()):
                # Extract values as tags, split comma-separated values
                tags = []
                for line in lines:
                    if ":" not in line:
                        continue
                    val = line.split(":", 1)[1].strip()
                    # Split comma-separated values into individual tags
                    for part in val.split(","):
                        part = part.strip().replace("_", "-").lower()
                        # Remove YAML-unsafe chars
                        part = re.sub(r"[#\[\]{}()$\"']", "", part).strip()
                        if part:
                            tags.append(part)
                return tags
            return normalize_tags(raw)

    return []


def normalize_tags(raw):
    """Normalize comma/space-separated tags to lowercase hyphenated list."""
    tags = re.split(r"[,\n]+", raw)
    result = []
    for tag in tags:
        tag = tag.strip().strip("`").lower()
        tag = re.sub(r"\s+", "-", tag)
        tag = re.sub(r"[^a-z0-9-]", "", tag)
        if tag and tag != "-":
            result.append(tag)
    return result


def tags_from_slug(filename):
    """Derive tags from filename slug when no inline tags found."""
    slug = re.sub(r"^\d{4}-\d{2}-\d{2}-", "", filename)
    slug = slug.removesuffix(".md")
    parts = slug.split("-")
    # Filter out very short or common words
    stopwords = {"the", "a", "an", "in", "on", "at", "to", "for", "of", "and", "or", "is", "not"}
    return [p for p in parts if len(p) > 1 and p not in stopwords]


# --- Frontmatter Parsing ---

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


# --- Processing ---

def process_file_no_frontmatter(filepath, filename):
    """Add frontmatter to a file that has none."""
    with open(filepath) as f:
        content = f.read()

    body_hash = hashlib.md5(content.encode()).hexdigest()

    date = extract_date_from_filename(filename) or extract_inline_date(content)
    title = extract_title(content)
    slug = re.sub(r"^\d{4}-\d{2}-\d{2}-", "", filename).removesuffix(".md")
    category = infer_category(slug)
    tags = extract_inline_tags(content) or tags_from_slug(filename)

    fm = {
        "title": title or slug.replace("-", " ").title(),
        "date": date or "unknown",
        "category": category,
        "tags": tags,
    }

    fm_str = serialize_frontmatter(fm)
    new_content = fm_str + "\n\n" + content

    # Verify body is unchanged
    # The body is everything after frontmatter in the new content
    _, new_body, _ = parse_frontmatter(new_content)
    new_body_stripped = new_body.lstrip("\n")
    content_stripped = content.lstrip("\n")
    new_body_hash = hashlib.md5(content_stripped.encode()).hexdigest()
    if body_hash != new_body_hash:
        print(f"  ERROR: Body hash mismatch for {filename}", file=sys.stderr)
        stats["errors"] += 1
        return

    with open(filepath, "w") as f:
        f.write(new_content)

    stats["created"] += 1


def process_file_with_frontmatter(filepath, filename):
    """Augment existing frontmatter with missing required fields."""
    with open(filepath) as f:
        content = f.read()

    fm, body, raw_fm = parse_frontmatter(content)
    if fm is None:
        print(f"  ERROR: Could not parse frontmatter in {filename}", file=sys.stderr)
        stats["errors"] += 1
        return

    body_hash = hashlib.md5(body.encode()).hexdigest()
    modified = False

    # Check if YAML was parsed via fallback (broken YAML) -- needs rewrite
    try:
        yaml.safe_load(raw_fm)
    except yaml.YAMLError:
        modified = True  # Force rewrite to fix broken YAML

    # Add missing required fields
    if "title" not in fm:
        fm["title"] = extract_title(body) or filename.removesuffix(".md")
        modified = True

    if "date" not in fm:
        date = extract_date_from_filename(filename) or extract_inline_date(body)
        fm["date"] = date or "unknown"
        modified = True

    if "category" not in fm:
        slug = re.sub(r"^\d{4}-\d{2}-\d{2}-", "", filename).removesuffix(".md")
        fm["category"] = infer_category(slug)
        modified = True

    if "tags" not in fm:
        tags = extract_inline_tags(body) or tags_from_slug(filename)
        fm["tags"] = tags
        modified = True

    # Normalize symptom (singular) to symptoms (plural array)
    if "symptom" in fm:
        symptom_val = fm.pop("symptom")
        if "symptoms" not in fm:
            if isinstance(symptom_val, list):
                fm["symptoms"] = symptom_val
            else:
                fm["symptoms"] = [str(symptom_val)]
        modified = True

    if not modified:
        stats["skipped"] += 1
        return

    fm_str = serialize_frontmatter(fm)
    new_content = fm_str + "\n" + body

    # Verify body unchanged
    _, new_body, _ = parse_frontmatter(new_content)
    new_body_hash = hashlib.md5(new_body.encode()).hexdigest()
    if body_hash != new_body_hash:
        print(f"  ERROR: Body hash mismatch for {filename}", file=sys.stderr)
        stats["errors"] += 1
        return

    with open(filepath, "w") as f:
        f.write(new_content)

    stats["augmented"] += 1


def rename_dateless_file():
    """Rename agent-prompt-sharp-edges-only.md with date prefix from git history."""
    dateless = os.path.join(LEARNINGS_DIR, "agent-prompt-sharp-edges-only.md")
    if not os.path.exists(dateless):
        return None

    # Get creation date from git history
    result = subprocess.run(
        ["git", "log", "--follow", "--diff-filter=A", "--format=%as", "--", dateless],
        capture_output=True, text=True
    )
    date = result.stdout.strip().split("\n")[-1] if result.stdout.strip() else ""
    if not date:
        date = "2026-02-13"  # fallback

    new_name = f"{date}-agent-prompt-sharp-edges-only.md"
    new_path = os.path.join(LEARNINGS_DIR, new_name)

    subprocess.run(["git", "add", dateless], check=True)
    subprocess.run(["git", "mv", dateless, new_path], check=True)
    print(f"  Renamed: {dateless} -> {new_path}")
    return new_name


# --- Main ---

def main():
    if not os.path.isdir(LEARNINGS_DIR):
        print(f"ERROR: {LEARNINGS_DIR} not found", file=sys.stderr)
        sys.exit(1)

    # Step 1: Rename dateless file
    renamed = rename_dateless_file()

    # Step 2: Process all files
    files = sorted(os.listdir(LEARNINGS_DIR))
    for filename in files:
        if not filename.endswith(".md"):
            continue

        filepath = os.path.join(LEARNINGS_DIR, filename)
        stats["processed"] += 1

        with open(filepath) as f:
            first_line = f.readline().strip()

        if first_line == "---":
            process_file_with_frontmatter(filepath, filename)
        else:
            process_file_no_frontmatter(filepath, filename)

    # Step 3: Post-run verification
    print(f"\nProcessed: {stats['processed']} | Created: {stats['created']} | "
          f"Augmented: {stats['augmented']} | Skipped: {stats['skipped']} | "
          f"Errors: {stats['errors']}")

    # Verify all files have frontmatter
    failed = []
    for filename in sorted(os.listdir(LEARNINGS_DIR)):
        if not filename.endswith(".md"):
            continue
        filepath = os.path.join(LEARNINGS_DIR, filename)
        with open(filepath) as f:
            if f.readline().strip() != "---":
                failed.append(filepath)

    if failed:
        print(f"\nERROR: {len(failed)} files still lack frontmatter:", file=sys.stderr)
        for f in failed:
            print(f"  {f}", file=sys.stderr)
        sys.exit(1)

    # Verify all required fields present
    missing_fields = []
    for filename in sorted(os.listdir(LEARNINGS_DIR)):
        if not filename.endswith(".md"):
            continue
        filepath = os.path.join(LEARNINGS_DIR, filename)
        with open(filepath) as f:
            content = f.read()
        fm, _, _ = parse_frontmatter(content)
        if fm is None:
            missing_fields.append((filename, ["all"]))
            continue
        missing = [field for field in ["title", "date", "category", "tags"] if field not in fm]
        if missing:
            missing_fields.append((filename, missing))

    if missing_fields:
        print(f"\nERROR: {len(missing_fields)} files missing required fields:", file=sys.stderr)
        for filename, fields in missing_fields:
            print(f"  {filename}: missing {fields}", file=sys.stderr)
        sys.exit(1)

    # Category distribution
    categories = {}
    for filename in sorted(os.listdir(LEARNINGS_DIR)):
        if not filename.endswith(".md"):
            continue
        filepath = os.path.join(LEARNINGS_DIR, filename)
        with open(filepath) as f:
            content = f.read()
        fm, _, _ = parse_frontmatter(content)
        if fm and "category" in fm:
            cat = fm["category"]
            categories[cat] = categories.get(cat, 0) + 1

    print("\nCategory distribution:")
    for cat, count in sorted(categories.items(), key=lambda x: -x[1]):
        print(f"  {count:3d}  {cat}")

    print(f"\nAll {stats['processed']} files have valid frontmatter. [ok]")


if __name__ == "__main__":
    main()
