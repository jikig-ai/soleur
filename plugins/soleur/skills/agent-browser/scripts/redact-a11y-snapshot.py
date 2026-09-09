#!/usr/bin/env python3
"""Redact credential-shaped values out of an accessibility snapshot (#7947).

Reads a snapshot on stdin, writes the redacted form to stdout.

WHY THIS IS NAME-BASED AND NOT STRUCTURAL
-----------------------------------------
Phase 0.1 measured both leaking surfaces (record:
knowledge-base/project/specs/feat-one-shot-7946-7947-sentry-org-token-and-snapshot-redaction/phase-0-measurement.md).
Neither `agent-browser` 0.22.3 nor the Playwright MCP serializes the input's
`type=` into the tree -- a password box, a readonly token box and an email box
all render as `textbox`. So a structural "is this a password input" predicate
has nothing to read, and the accessible NAME is the only signal present.

That is a real ceiling, not a shortcut. This filter is defense-in-depth on one
enumerated sink; it is not a control that makes snapshotting a credential page
safe. See the STATED BYPASSES below and property P5 in the plan.

MEASURED BEHAVIOUR THIS FILTER IS BUILT AGAINST
-----------------------------------------------
  * `agent-browser` masks `type=password` itself (renders bullets) and leaks
    the readonly `type=text` credential panel -- the "Token" class, which is
    the one with a recorded in-repo incident.
  * The Playwright MCP leaks both.
  * The no-flag and `-d N` shapes emit the value TWICE: once as the `: value`
    tail and again as a nested `StaticText` child. Redacting only the tail is
    half a fix, so children of a redacted node are suppressed too.
  * `--json` carries the same text inside `data.snapshot`.

STATED BYPASSES (P5's explicit non-coverage -- do not read this filter as
closing them):
  * a localised or renamed accessible name ("Contrasena", "Clave", "Value");
  * a credential rendered outside a text-input role (a status region, a
    validation message, a `<pre>` block);
  * a value split across segmented single-character inputs;
  * every node on the Playwright-MCP runtime path, which this filter can only
    reach if a human pipes a saved snapshot through it.

FAIL-CLOSED CONTRACT (ADR-095 shape): on refusal, exit 2 with stdout EMPTY and
a reason on stderr that never quotes the offending input.
"""

from __future__ import annotations

import json
import re
import sys

REDACTED = "<redacted>"

# 4 MiB. A real snapshot is kilobytes; anything at this size is not a snapshot,
# and refusing is cheaper than trying to redact it correctly.
MAX_INPUT_BYTES = 4 * 1024 * 1024

# Roles that can carry a user-editable value. A credential does not appear in a
# `heading` or a `link`, and widening this set widens the over-redaction risk
# that the must-PASS rows exist to catch.
TEXT_INPUT_ROLES = frozenset(
    {"textbox", "searchbox", "combobox", "spinbutton", "textarea"}
)

# Credential-shaped accessible names. Word-anchored on both sides so
# "Keyboard shortcut" does not match `key` and "Pinned items" does not match
# `pin`. Deliberately broader than "password": the only node `agent-browser`
# leaks is named "Token", so a password-only list would miss the single class
# with a recorded incident here.
CREDENTIAL_NAME_RE = re.compile(
    r"(?<![a-z0-9])(?:"
    r"pass(?:word|wd|phrase|code)?"
    r"|token"
    r"|secret"
    r"|credential"
    r"|bearer"
    r"|key"
    r"|otp"
    r"|pin"
    r"|seed[\s_-]?phrase"
    r"|mnemonic"
    r"|recovery[\s_-]?code"
    r"|security[\s_-]?code"
    r")(?![a-z0-9])",
    re.IGNORECASE,
)

# `- <role> "<name>" [attrs]: <value>` with the value and the attribute bracket
# both optional. Anchored on the list-dash so prose lines are never rewritten.
NODE_RE = re.compile(
    r"^(?P<indent>\s*)-\s+(?P<role>[A-Za-z][A-Za-z0-9_]*)"
    r'\s+"(?P<name>(?:[^"\\]|\\.)*)"'
    r"(?P<attrs>\s+\[[^\]]*\])?"
    r"(?P<sep>:\s*)(?P<value>.*)$"
)

# A bare quoted child, e.g. `  - StaticText "the value"`.
QUOTED_CHILD_RE = re.compile(
    r"^(?P<indent>\s*)-\s+(?P<role>[A-Za-z][A-Za-z0-9_]*)"
    r'\s+"(?P<text>(?:[^"\\]|\\.)*)"(?P<rest>.*)$'
)

INDENT_RE = re.compile(r"^(\s*)")


def _is_credential_name(name: str) -> bool:
    return bool(CREDENTIAL_NAME_RE.search(name))


def redact_text(text: str) -> str:
    """Redact credential-shaped node values in the indented-text shape."""
    out: list[str] = []
    # Indent of the node currently being suppressed, or None. Children deeper
    # than this inherit the redaction; a line at or above it ends suppression.
    suppress_indent: int | None = None

    for line in text.split("\n"):
        indent = len(INDENT_RE.match(line).group(1))

        if suppress_indent is not None and line.strip() and indent <= suppress_indent:
            suppress_indent = None

        node = NODE_RE.match(line)
        if node and node.group("role") in TEXT_INPUT_ROLES and _is_credential_name(
            node.group("name")
        ):
            out.append(
                f"{node.group('indent')}- {node.group('role')} "
                f"\"{node.group('name')}\"{node.group('attrs') or ''}"
                f"{node.group('sep')}{REDACTED}"
            )
            suppress_indent = indent
            continue

        if suppress_indent is not None and indent > suppress_indent:
            # A child of a redacted node. The measured `-d N` shape repeats the
            # value here as a StaticText, so the tail-only rewrite above is not
            # sufficient on its own.
            child = QUOTED_CHILD_RE.match(line)
            if child:
                out.append(
                    f"{child.group('indent')}- {child.group('role')} "
                    f"\"{REDACTED}\"{child.group('rest')}"
                )
                continue
            inner = NODE_RE.match(line)
            if inner:
                out.append(
                    f"{inner.group('indent')}- {inner.group('role')} "
                    f"\"{inner.group('name')}\"{inner.group('attrs') or ''}"
                    f"{inner.group('sep')}{REDACTED}"
                )
                continue

        out.append(line)

    return "\n".join(out)


def _redact_json_in_place(node: object) -> object:
    """Redact any string field named `snapshot`, at any depth."""
    if isinstance(node, dict):
        return {
            k: (redact_text(v) if k == "snapshot" and isinstance(v, str)
                else _redact_json_in_place(v))
            for k, v in node.items()
        }
    if isinstance(node, list):
        return [_redact_json_in_place(v) for v in node]
    return node


def die(reason: str) -> None:
    """Fail closed. Never quote the input -- that would re-open the leak."""
    sys.stderr.write(f"redact-a11y-snapshot: refusing to emit: {reason}\n")
    sys.exit(2)


def main() -> None:
    raw = sys.stdin.buffer.read(MAX_INPUT_BYTES + 1)
    if len(raw) > MAX_INPUT_BYTES:
        die(f"input exceeds {MAX_INPUT_BYTES} bytes")

    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError:
        die("input is not valid UTF-8")

    if not text:
        return

    stripped = text.lstrip()
    if stripped.startswith(("{", "[")):
        try:
            parsed = json.loads(text)
        except json.JSONDecodeError as exc:
            die(f"input looks like JSON but does not parse ({exc.msg})")
        sys.stdout.write(json.dumps(_redact_json_in_place(parsed)))
        return

    sys.stdout.write(redact_text(text))


if __name__ == "__main__":
    main()
