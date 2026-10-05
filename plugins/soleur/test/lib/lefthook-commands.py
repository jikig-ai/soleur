#!/usr/bin/env python3
"""Emit one line per lefthook `run:` command, NUL-free and comment-stripped.

Guard 2 previously read lefthook.yml with a `grep` for `run:` plus an `awk` range for block
scalars. That hand-rolled parse was wrong in five measured ways, every one of them fail-OPEN:

  * `awk '/run:[[:space:]]*\\|/'` matches only LITERAL block scalars, so a FOLDED scalar
    (`run: >` / `run: >-`) — identical YAML semantics for this purpose — was never read at all.
  * the continuation test `^[[:space:]]{8,}` hard-codes one indentation depth, so the same file
    written with a different (equally valid) indent is invisible.
  * a BLANK LINE inside a block scalar failed the continuation test, hit the `{inblk=0}` default
    and silently terminated the sweep — dropping every command line after it.
  * matching RUNNER_RE and SCRUB_RE per PHYSICAL LINE made the correct multi-line spelling
    (`unset …` on line 1, the runner on line 3) FAIL, which is a fail-closed bug that pushes an
    author toward the fail-open spellings above.
  * a TRAILING comment on a `run:` line was matched as if it were code.

Reading the YAML with a real parser removes all five at once: a command becomes one logical
string regardless of scalar style or indentation, and comments are gone before any matching.

Output: one command per line, newlines within a command folded to spaces, so the caller can keep
matching line-by-line. Commands containing no non-whitespace are skipped.
"""

from __future__ import annotations

import sys

try:
    import yaml
except ModuleNotFoundError:  # pragma: no cover - environment guard
    sys.stderr.write(
        "FATAL: PyYAML is required to parse lefthook.yml. Guard 2 fails CLOSED rather than "
        "falling back to a regex parse whose blind spots are the reason this exists.\n"
    )
    raise SystemExit(2)


def walk(node) -> list[str]:
    """Collect every `run:` value anywhere in the document.

    Recursive rather than keyed on `pre-commit`/`pre-push`: lefthook accepts `run:` under any hook
    name, and a guard that enumerates the hook names it knows about is narrower than the property
    ("every command lefthook can execute"). A new hook type joins the corpus by existing.
    """
    found: list[str] = []
    if isinstance(node, dict):
        for key, value in node.items():
            if key == "run" and isinstance(value, str):
                found.append(value)
            else:
                found.extend(walk(value))
    elif isinstance(node, list):
        for item in node:
            found.extend(walk(item))
    return found


def main() -> int:
    if len(sys.argv) != 2:
        sys.stderr.write("usage: lefthook-commands.py <lefthook.yml>\n")
        return 2
    with open(sys.argv[1], encoding="utf-8") as handle:
        doc = yaml.safe_load(handle)
    if doc is None:
        sys.stderr.write("FATAL: lefthook.yml parsed as empty\n")
        return 2

    commands = walk(doc)
    if not commands:
        sys.stderr.write("FATAL: parsed lefthook.yml but found zero `run:` commands\n")
        return 2

    for cmd in commands:
        # A newline is a STATEMENT SEPARATOR in shell, so a literal block scalar's lines must not
        # be folded together with a space -- that would turn `unset A B C` + `bun test x` into the
        # single malformed statement `unset A B C bun test x`. Emit `;` so the joined form stays
        # shell-equivalent AND the caller can still split it back into ordered statements, which is
        # what lets "the scrub precedes the runner, in the same shell" be checked at all.
        #
        # A FOLDED scalar (`run: >`) is already newline-free by the time PyYAML returns it -- YAML
        # folds those to spaces itself -- so this only affects literal blocks, correctly.
        raw = cmd.splitlines()
        statements: list[str] = []
        pending = ""
        for line in raw:
            text = " ".join(line.split())
            if text.endswith("\\"):
                # Trailing backslash: a line continuation, so this and the next physical line are
                # ONE statement. Joining them with ";" instead would cut a command in half and the
                # caller would see two malformed fragments.
                pending += text[:-1].rstrip() + " "
                continue
            statements.append((pending + text).strip())
            pending = ""
        if pending.strip():
            statements.append(pending.strip())
        flat = " ; ".join(s for s in statements if s)
        if flat:
            print(flat)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
