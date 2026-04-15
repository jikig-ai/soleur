#!/usr/bin/env python3
"""Backfill stable `[id: <prefix>-<slug>]` tags on every AGENTS.md rule.

Idempotent: re-running is a no-op on already-tagged rules.
Body-hash safe: the only change introduced is `[id: ...]` insertion —
stripping those tags from the output must reproduce the input.

Usage:
    python scripts/backfill-rule-ids.py [AGENTS.md] [--dry-run]
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

SECTION_PREFIXES = {
    "Hard Rules": "hr",
    "Workflow Gates": "wg",
    "Code Quality": "cq",
    "Review & Feedback": "rf",
    "Passive Domain Routing": "pdr",
    "Communication": "cm",
}

SLUG_MAX = 40
SLUG_MIN = 3
SLUG_SOURCE_MAX = 50  # chars of rule text considered for slug

ID_TAG_RE = re.compile(r"\[id: [a-z0-9-]+\]")
ENFORCED_TAG_RE = re.compile(r"\[(?:hook|skill)-enforced: [^\]]+\]")
SECTION_HEADING_RE = re.compile(r"^## (.+?)\s*$")


def section_prefix(name: str) -> str | None:
    return SECTION_PREFIXES.get(name.strip())


def slugify(text: str) -> str:
    """Kebab-case slug bounded [SLUG_MIN, SLUG_MAX]."""
    # Use only the first SLUG_SOURCE_MAX characters of the source text
    source = text[:SLUG_SOURCE_MAX]
    # Lowercase, drop backticks/quotes, replace non-alphanum with hyphens
    cleaned = re.sub(r"[`'\"]", "", source.lower())
    cleaned = re.sub(r"[^a-z0-9]+", "-", cleaned)
    cleaned = cleaned.strip("-")
    # Stopword-trim from the end while staying above SLUG_MIN
    parts = [p for p in cleaned.split("-") if p]
    # Truncate to SLUG_MAX chars on word boundaries
    result = parts[0] if parts else "rule"
    for p in parts[1:]:
        candidate = f"{result}-{p}"
        if len(candidate) > SLUG_MAX:
            break
        result = candidate
    # Pad if below min
    if len(result) < SLUG_MIN:
        result = (result + "-rule")[:SLUG_MAX]
    return result


def strip_ids(content: str) -> str:
    """Remove every `[id: <slug>]` tag and the single space that precedes it."""
    return re.sub(r" \[id: [a-z0-9-]+\]", "", content)


def _extract_rule_text(bullet_body: str) -> str:
    """Pull the leading clause of a bullet used as slug source.

    Drops existing `[hook-enforced: ...]` / `[skill-enforced: ...]` tags so
    their text doesn't bleed into the slug.
    """
    no_tags = ENFORCED_TAG_RE.sub("", bullet_body)
    # Take up to first sentence-ending period or newline
    first_clause = re.split(r"(?:\. |\n)", no_tags, maxsplit=1)[0]
    return first_clause.strip()


def _insert_id(line: str, rule_id: str) -> str:
    """Insert `[id: rule_id]` at end of first clause.

    If `[hook-enforced: ...]` or `[skill-enforced: ...]` exists on the line,
    the id tag is placed immediately before it. Otherwise it's placed before
    the first `. ` or at end of line if no period exists.
    """
    id_tag = f"[id: {rule_id}]"

    # If enforcement tag is present, insert id-tag right before it
    match = ENFORCED_TAG_RE.search(line)
    if match:
        before = line[: match.start()].rstrip()
        after = line[match.start():]
        return f"{before} {id_tag} {after}"

    # Else insert before the first ". " (end of first sentence)
    period_match = re.search(r"\. ", line)
    if period_match:
        idx = period_match.start()
        return f"{line[:idx]} {id_tag}{line[idx:]}"

    # Else insert before trailing period
    if line.rstrip().endswith("."):
        rstripped = line.rstrip()
        trailing = line[len(rstripped):]
        return f"{rstripped[:-1]} {id_tag}.{trailing}"

    # Else append at end (preserving trailing newline if any)
    if line.endswith("\n"):
        return f"{line[:-1]} {id_tag}\n"
    return f"{line} {id_tag}"


def assign_ids(content: str) -> str:
    """Insert `[id: <prefix>-<slug>]` on every untagged bullet under tagged sections.

    Idempotent: bullets already containing `[id: ...]` are left untouched.
    Collisions get a numeric `-2`, `-3`, ... suffix within the file.
    """
    lines = content.splitlines(keepends=True)
    current_prefix: str | None = None
    used_ids: set[str] = set()

    # First pass: collect already-assigned IDs to seed collision set
    for line in lines:
        for m in ID_TAG_RE.finditer(line):
            used_ids.add(m.group(0)[len("[id: "):-1])

    out: list[str] = []
    for line in lines:
        heading = SECTION_HEADING_RE.match(line)
        if heading:
            current_prefix = section_prefix(heading.group(1))
            out.append(line)
            continue

        if not current_prefix or not line.startswith("- "):
            out.append(line)
            continue

        # Already tagged? skip (idempotent)
        if ID_TAG_RE.search(line):
            out.append(line)
            continue

        rule_text = _extract_rule_text(line[2:])  # drop "- "
        if not rule_text:
            out.append(line)
            continue

        base = slugify(rule_text)
        candidate = f"{current_prefix}-{base}"
        n = 2
        while candidate in used_ids:
            candidate = f"{current_prefix}-{base}-{n}"
            n += 1
        used_ids.add(candidate)
        out.append(_insert_id(line, candidate))

    return "".join(out)


def _frontmatter_split(content: str) -> tuple[str, str]:
    """Split YAML frontmatter from body. Returns (fm_with_delim, body)."""
    if not content.startswith("---\n"):
        return "", content
    lines = content.split("\n")
    for i in range(1, min(len(lines), 50)):
        if lines[i].strip() == "---":
            fm = "\n".join(lines[: i + 1]) + "\n"
            body = "\n".join(lines[i + 1:])
            return fm, body
    return "", content


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("path", nargs="?", default="AGENTS.md")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    path = Path(args.path)
    if not path.exists():
        print(f"ERROR: {path} not found", file=sys.stderr)
        return 2

    original = path.read_text()
    updated = assign_ids(original)

    # Body-hash safety: stripping every [id:...] from the output must
    # reproduce the original (modulo pre-existing ids, which strip_ids
    # removes symmetrically from both sides).
    if strip_ids(updated) != strip_ids(original):
        print(
            "ERROR: backfill altered content beyond [id:] insertion — aborting",
            file=sys.stderr,
        )
        return 3

    # Report proposed/added IDs
    added = [
        m.group(0)
        for m in ID_TAG_RE.finditer(updated)
        if m.group(0) not in {n.group(0) for n in ID_TAG_RE.finditer(original)}
    ]

    if args.dry_run:
        print(f"Would add {len(added)} IDs:")
        for tag in added:
            print(f"  + {tag}")
        return 0

    if updated == original:
        print(f"No changes (all rules already tagged). {path}")
        return 0

    path.write_text(updated)
    print(f"Wrote {len(added)} new IDs to {path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
