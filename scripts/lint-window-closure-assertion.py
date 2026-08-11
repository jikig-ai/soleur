#!/usr/bin/env python3
"""Window-derived closure assertions must declare their assembly.

The defect
----------
A closure assertion (`toEqual([...])` / `toStrictEqual([...])`) whose subject is
derived from a REGEX-EXTRACTED WINDOW of a source file pins only what the window
happens to span. The originating instance is `sandboxWindow()` in
`plugins/soleur/test/preflight-discoverability-test.test.ts`, which scoped to
`BWRAP_ARGS=( … )` while `GIT_BIND`, `BWRAP_PROC` and the exec line ALSO injected
mounts. Three separate one-line edits each re-opened the operator's credential
surface with the whole suite green — verified against live bwrap reaching the
Doppler token, `~/.ssh` and the gh token store.

The helper was invented at work time and silently became the operative
definition of "the mount set".

What this lint enforces — and what it does NOT
----------------------------------------------
It enforces a DECLARATION, per helper:

    // window-assembly: <helperName> — <what the window is asserted to be
    // complete against, and how>

It does NOT prove semantic completeness. No static checker can decide whether a
regex-extracted window equals the assembly it stands for; claiming otherwise
would make this gate exactly the kind of check that certifies something narrower
than what it is read to establish. What it does is force the enumeration to be
written down at the point of the defect, per helper, in the same way the
plan-time Guard Contract forces it at design time.

Scope
-----
Both test roots — `apps/web-platform/` and `plugins/soleur/test/` — enumerated by
DIRECTORY WALK, never a fixed-depth glob: a test file relocated one directory
deeper must stay in scope. Within each file, EVERY helper whose identifier ends
in `Window`, `Region` or `Section` is examined, never only the first.

A file is in scope only when it contains BOTH a window helper AND a closure
assertion.

Grandfathering
--------------
`--allowlist <file>` takes `<repo-relative-path>::<helperName>` lines. Entries
are PER HELPER: an allowlisted helper never waives an undeclared sibling in the
same file. The committed allowlist holds the population measured when this gate
landed, so it lands green and every subsequent addition is gated.

Exit codes: 0 PASS, 1 one or more FAIL, 2 argument/IO error.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

TEST_ROOTS = ("apps/web-platform", "plugins/soleur/test")

HELPER_RE = re.compile(
    r"^\s*(?:export\s+)?(?:const|let|var|function)\s+"
    r"(?P<name>[A-Za-z_$][\w$]*(?:Window|Region|Section))\b"
)
CLOSURE_RE = re.compile(r"to(?:Strict)?Equal\(\s*\[")
DECLARATION_RE = re.compile(r"//\s*window-assembly:\s*(?P<name>[A-Za-z_$][\w$]*)")


def find_test_files(root: Path) -> list[Path]:
    """Every *.test.ts under the configured test roots, by directory walk."""
    files: list[Path] = []
    for rel in TEST_ROOTS:
        base = root / rel
        if not base.is_dir():
            continue
        files.extend(sorted(base.rglob("*.test.ts")))
    return files


def load_allowlist(path: Path) -> set[tuple[str, str]]:
    entries: set[tuple[str, str]] = set()
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if "::" not in line:
            raise SystemExit(
                f"lint-window-closure-assertion: malformed allowlist line "
                f"(want '<path>::<helper>'): {line}"
            )
        rel, helper = line.split("::", 1)
        entries.add((rel.strip(), helper.strip()))
    return entries


def check_file(
    path: Path, rel: str, allow: set[tuple[str, str]], failures: list[str]
) -> int:
    """Check one test file. Returns the number of in-scope helpers examined."""
    try:
        text = path.read_text(encoding="utf-8")
    except OSError as exc:
        raise SystemExit(f"lint-window-closure-assertion: cannot read {path}: {exc}") from exc

    if not CLOSURE_RE.search(text):
        return 0

    helpers = [m.group("name") for m in (HELPER_RE.match(l) for l in text.splitlines()) if m]
    if not helpers:
        return 0

    declared = {m.group("name") for m in DECLARATION_RE.finditer(text)}

    # EVERY helper, never the first. A per-file marker covering a whole file
    # would reintroduce exactly the first-member degradation this gate exists to
    # catch — so the declaration and the allowlist are both keyed per helper.
    for helper in dict.fromkeys(helpers):
        if (rel, helper) in allow:
            continue
        if helper in declared:
            continue
        failures.append(  # MUT:marker
            f"{rel}: `{helper}` feeds a closure assertion with no assembly "  # MUT:marker
            f"declaration — add `// window-assembly: {helper} — <what the window "  # MUT:marker
            f"is complete against>` or allowlist it"  # MUT:marker
        )  # MUT:marker
    return len(set(helpers))


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(
        prog="lint-window-closure-assertion",
        description="Window-derived closure assertions must declare their assembly.",
    )
    parser.add_argument("--repo-root", default=".", help="repository root")
    parser.add_argument("--allowlist", default=None, help="path to the grandfather allowlist")
    args = parser.parse_args(argv)

    root = Path(args.repo_root).resolve()
    if not root.is_dir():
        print(f"lint-window-closure-assertion: --repo-root not a directory: {root}", file=sys.stderr)
        return 2

    allow: set[tuple[str, str]] = set()
    if args.allowlist:
        allow_path = root / args.allowlist
        if not allow_path.is_file():
            print(f"lint-window-closure-assertion: no such allowlist: {allow_path}", file=sys.stderr)
            return 2
        allow = load_allowlist(allow_path)

    files = find_test_files(root)
    failures: list[str] = []
    helpers_checked = 0
    for f in files:
        rel = f.relative_to(root).as_posix()
        helpers_checked += check_file(f, rel, allow, failures)

    for msg in failures:
        print(f"FAIL: {msg}", file=sys.stderr)

    print(
        f"lint-window-closure-assertion: scanned {len(files)} test file(s), "
        f"{helpers_checked} in-scope window helper(s)"
    )

    # Anti-vacuity floor on this gate's OWN dispatch. A gate that examined
    # nothing must never report success — that is the fourth instance from the
    # originating evidence (a neutered gate printed "0 passed, 0 failed",
    # exited 0, and read as a clean run).
    if not files:  # MUT:floor
        print(  # MUT:floor
            "FAIL: scanned 0 test files — the walk found nothing, which is a "  # MUT:floor
            "harness/config defect, not a clean run",  # MUT:floor
            file=sys.stderr,  # MUT:floor
        )  # MUT:floor
        return 1  # MUT:floor

    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
