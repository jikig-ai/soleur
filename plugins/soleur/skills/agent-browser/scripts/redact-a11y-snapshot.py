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

# Descendant roles that repeat a PARENT's value rather than carrying a label
# of their own. Measured: the no-flag and `-d N` shapes emit the value twice,
# the second time as a StaticText child. Everything else under a redacted
# node (an `option` label, say) is a label and must survive.
VALUE_CARRYING_CHILD_ROLES = frozenset({"StaticText"})

# Credential-shaped accessible names. Word-anchored on both sides so
# "Keyboard shortcut" does not match `key` and "Pinned items" does not match
# `pin`. Deliberately broader than "password": the only node `agent-browser`
# leaks is named "Token", so a password-only list would miss the single class
# with a recorded incident here.
CREDENTIAL_NAME_RE = re.compile(
    r"\b(?:"
    r"pass(?:word|wd|phrase|code)?"
    r"|token"
    r"|secret"
    r"|credential"
    r"|key"
    r"|bearer"
    r"|otp"
    r"|pin"
    r"|seed[\s_-]?phrase"
    r"|mnemonic"
    r"|(?:verification|confirmation|one[\s_-]?time|backup|access|recovery|security|sms|auth(?:entication)?)[\s_-]?code"
    r"|connection[\s_-]?string"
    r"|dsn"
    r"|signature"
    r"|authorization"
    r"|session"
    r"|cookie"
    r")e?s?\b",
    re.IGNORECASE,
)

def _fmt_name(name: str | None) -> str:
    """Re-emit the name exactly as it arrived, including its absence."""
    return "" if name is None else f' "{name}"'


_CAMEL_BOUNDARY_RE = re.compile(r"(?<=[a-z0-9])(?=[A-Z])")


def _normalise_name(name: str) -> str:
    """Split camelCase so `apiKey` and `clientSecret` match the same list.

    Measured: the previous lookbehind form rejected `apiKey` (the char before
    `Key` is a letter, so the boundary never fired) and every English plural --
    `API Keys`, `Tokens`, `Secrets`, `Recovery codes`, `Passcodes` all passed
    through in clear. `API Keys` is the literal label on the Cloudflare and
    Sentry token pages this filter was written for, and `Token` is the class
    with a recorded in-repo incident, so both failed on their own plural.
    """
    return _CAMEL_BOUNDARY_RE.sub(" ", name)

# `- <role> "<name>" [attrs]: <value>` with the value and the attribute bracket
# both optional. Anchored on the list-dash so prose lines are never rewritten.
NODE_RE = re.compile(
    r"^(?P<indent>\s*)(?P<bullet>[-+])\s+(?P<role>[A-Za-z][A-Za-z0-9_]*)"
    r'(?:\s+"(?P<name>(?:[^"\\]|\\.)*)")?'
    r"(?P<attrs>(?:\s+\[[^\]]*\])*)"
    r"(?P<sep>:\s*)(?P<value>.*)$"
)

# A bare quoted child, e.g. `  - StaticText "the value"`.
QUOTED_CHILD_RE = re.compile(
    r"^(?P<indent>\s*)(?P<bullet>[-+])\s+(?P<role>[A-Za-z][A-Za-z0-9_]*)"
    r'\s+"(?P<text>(?:[^"\\]|\\.)*)"(?P<rest>.*)$'
)

INDENT_RE = re.compile(r"^(\s*)")


def _is_credential_name(name: str | None) -> bool:
    """True when the accessible name marks this node as credential-bearing.

    An UNNAMED node (`name is None`) is not decidable by a name predicate, and
    an unlabeled readonly box is the commonest shape of a generated-credential
    panel. It is handled at the call site as its own case rather than folded in
    here, so the two decisions stay legible.
    """
    if name is None:
        return False
    return bool(CREDENTIAL_NAME_RE.search(_normalise_name(name)))


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
        # An UNNAMED text-input node carrying a value is redacted on the
        # fail-safe side. We cannot decide it by name -- there is no name -- and
        # an unlabeled readonly box is the commonest shape of a
        # generated-credential panel. Playwright derives an accessible name from
        # a label, placeholder or aria-label, so a genuinely unnamed input with
        # a value is rare; losing its value costs an agent little, and keeping
        # it is the class with a recorded in-repo incident.
        unnamed_input = (
            node is not None
            and node.group("name") is None
            and node.group("role") in TEXT_INPUT_ROLES
            and node.group("value").strip() != ""
        )
        if node and node.group("role") in TEXT_INPUT_ROLES and (
            unnamed_input or _is_credential_name(node.group("name"))
        ):
            out.append(
                f"{node.group('indent')}{node.group('bullet')} {node.group('role')}"
                f"{_fmt_name(node.group('name'))}{node.group('attrs') or ''}"
                f"{node.group('sep')}{REDACTED}"
            )
            suppress_indent = indent
            continue

        if suppress_indent is not None and indent > suppress_indent:
            # A descendant of a redacted node. Two distinct cases, and the
            # earlier revision got both wrong because QUOTED_CHILD_RE strictly
            # SUBSUMES NODE_RE -- it matched first, so a nested credential node
            # had its NAME redacted and its VALUE preserved. That is the exact
            # inversion of the point: it destroyed the signal and kept the
            # secret.
            inner = NODE_RE.match(line)
            if inner:
                # A node with its own `: value` tail -- redact the VALUE, keep
                # the name, exactly as for the parent.
                out.append(
                    f"{inner.group('indent')}{inner.group('bullet')} {inner.group('role')}"
                    f"{_fmt_name(inner.group('name'))}{inner.group('attrs') or ''}"
                    f"{inner.group('sep')}{REDACTED}"
                )
                continue
            child = QUOTED_CHILD_RE.match(line)
            if child and child.group("role") in VALUE_CARRYING_CHILD_ROLES:
                # The measured `-d N` / no-flag duplicate: the value repeated as
                # a StaticText child. Redact it.
                out.append(
                    f"{child.group('indent')}{child.group('bullet')} {child.group('role')} "
                    f"\"{REDACTED}\"{child.group('rest')}"
                )
                continue
            # Anything else under a redacted node is a LABEL, not a value --
            # `option "id"`, `option "email"` under a combobox named
            # "Primary key". Redacting those destroys the agent's ability to
            # pick the right option while protecting nothing, so they pass
            # through untouched.

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

    # Locate a JSON payload even when something is printed AHEAD of it.
    #
    # This is the shape the guard itself prescribes: `agent-browser snapshot -i
    # --json 2>&1 | python3 <this>`. The `2>&1` merges any agent-browser
    # diagnostic in front of the JSON, so a `startswith` test is False, the
    # input falls to the line-based path, NODE_RE never matches a single-line
    # JSON blob, and the credential passes through verbatim at exit 0.
    # Measured, and it is the highest-severity shape because our own
    # instructions steer every agent onto it.
    brace = min(
        (i for i in (text.find("{"), text.find("[")) if i != -1),
        default=-1,
    )
    if brace != -1:
        try:
            parsed = json.loads(text[brace:])
        except json.JSONDecodeError as exc:
            # Fail closed on anything that PRESENTS as a JSON document: some
            # line, after stripping, begins with `{` or `[`.
            #
            # The earlier form keyed on the literal `"snapshot"` being present,
            # so an envelope truncated BEFORE that key -- or one with a typo'd
            # key -- matched neither clause, fell through to the line-based
            # path, and was emitted verbatim at exit 0. A partial envelope is
            # exactly what a killed `agent-browser` produces, so that was the
            # likely shape, not an exotic one.
            #
            # A stray brace INSIDE an a11y node value does not begin a line, so
            # ordinary text is unaffected and does not take the run down.
            if any(ln.lstrip().startswith(("{", "[")) for ln in text.splitlines()):
                die(f"input looks like JSON but does not parse ({exc.msg})")
        else:
            prefix = redact_text(text[:brace])
            sys.stdout.write(prefix + json.dumps(_redact_json_in_place(parsed)))
            return

    sys.stdout.write(redact_text(text))


if __name__ == "__main__":
    main()
