#!/usr/bin/env python3
"""Step-boundary error-identity census for Inngest handlers (#8764).

An error that escapes `step.run`'s callback reaches the handler's catch as the
SDK's REBUILT `StepError` — `name === "Error"`, no custom class, no custom
fields. Routing a handler decision on `instanceof <Class>` / `.name ===` /
`.status` of that caught error silently never matches in production while
passing every in-process step mock (the #8717/#8726 defect class).

This scanner walks `apps/web-platform/server/inngest/functions/*.ts` and FAILS
on two catch-clause shapes:

  A. BOUNDARY — a `catch` whose own `try` block contains a `step.run(` call and
     whose body reads the caught error's identity (`<p> instanceof <Class>`,
     `<p>.name ===`, `<p>.status`), where `<p>` is the catch parameter
     (including `(p as T)` casts). Never exempt.

  B. STEP-INTERNAL — a `catch` nested inside a `step.run(...)` callback (the
     error there is LIVE — it never crossed a boundary) that reads the caught
     error's identity. Exempt only for files in STEP_INTERNAL_ALLOWLIST: the
     named precision anchors that legitimately classify live errors inside
     their step callbacks. Adding a file to the allowlist is the census's
     conscious-registration point.

Usage: lint-inngest-step-boundary.py [dir ...]  (default: the real corpus)
Exit 0 clean, 1 on violations, 2 on misuse.
"""

from __future__ import annotations

import os
import re
import sys

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_DIR = os.path.join(
    REPO_ROOT, "apps", "web-platform", "server", "inngest", "functions"
)

# Files whose step callbacks legitimately read a LIVE caught error's identity
# (#8764): the check runs before the error crosses the boundary, which is the
# correct place for it. A boundary catch (shape A) in one of these files is
# still flagged — the allowlist covers step-internal catches only.
STEP_INTERNAL_ALLOWLIST = frozenset(
    {
        "cron-anthropic-cost-report.ts",
        "cron-anthropic-credit-probe.ts",
        "cron-gh-pages-cert-reissue.ts",
        # #8726 reworked this handler so every LeakDetectedError check lives
        # INSIDE the step callbacks (live errors) — the allowlisted shape.
        "cron-github-app-drift-guard.ts",
        # collect-corpus / load-ledger step callbacks classify a live
        # LedgerReadError by cause inside the step.
        "cron-compound-promote.ts",
    }
)

STEP_RUN_RE = re.compile(r"\bstep\.run\s*\(")
# `instanceof <Class>` — EXCEPT bare `instanceof Error`, the named precision
# anchor: a rebuilt StepError extends Error, so the check is true for every
# value that matters and cannot misroute (e.g. the non-Error normalisation
# `err instanceof Error ? err : new Error(String(err))`).
IDENT_INSTANCEOF_RE = re.compile(r"\binstanceof\s+(?!Error\b)[A-Za-z_$]")


def strip_comments(src: str) -> str:
    """Remove // and /* */ comments, preserving newlines (line numbers stay)."""
    out = []
    i, n = 0, len(src)
    state = "code"  # code | line_comment | block_comment | squote | dquote | template
    while i < n:
        c = src[i]
        nxt = src[i + 1] if i + 1 < n else ""
        if state == "code":
            if c == "/" and nxt == "/":
                state = "line_comment"
                i += 2
                continue
            if c == "/" and nxt == "*":
                state = "block_comment"
                i += 2
                continue
            if c == "'":
                state = "squote"
            elif c == '"':
                state = "dquote"
            elif c == "`":
                state = "template"
            out.append(c)
            i += 1
        elif state == "line_comment":
            if c == "\n":
                out.append(c)
                state = "code"
            i += 1
        elif state == "block_comment":
            if c == "*" and nxt == "/":
                state = "code"
                i += 2
                continue
            if c == "\n":
                out.append(c)
            i += 1
        else:  # string/template literal — keep contents (catches can name strings)
            if c == "\\":
                out.append(c)
                if i + 1 < n:
                    out.append(src[i + 1])
                i += 2
                continue
            out.append(c)
            i += 1
            if state == "squote" and c == "'":
                state = "code"
            elif state == "dquote" and c == '"':
                state = "code"
            elif state == "template" and c == "`":
                state = "code"
    return "".join(out)


def match_brace(src: str, open_idx: int) -> int:
    """Index just past the '}' matching src[open_idx]=='{'; -1 if unbalanced."""
    depth = 0
    for j in range(open_idx, len(src)):
        if src[j] == "{":
            depth += 1
        elif src[j] == "}":
            depth -= 1
            if depth == 0:
                return j + 1
    return -1


def match_paren(src: str, open_idx: int) -> int:
    depth = 0
    for j in range(open_idx, len(src)):
        if src[j] == "(":
            depth += 1
        elif src[j] == ")":
            depth -= 1
            if depth == 0:
                return j + 1
    return -1


def line_of(src: str, idx: int) -> int:
    return src.count("\n", 0, idx) + 1


def find_catches(src: str):
    """Yield (try_start, try_end, catch_body_start, catch_body_end, param) for
    every `try { ... } catch [(p)] { ... }`."""
    for m in re.finditer(r"\btry\s*\{", src):
        open_i = src.index("{", m.start())
        try_end = match_brace(src, open_i)
        if try_end < 0:
            continue
        cm = re.match(r"\s*catch\s*(?:\(\s*([A-Za-z_$][\w$]*)?[^)]*\))?\s*\{", src[try_end:])
        if not cm:
            continue
        param = cm.group(1) or "err"
        body_start = try_end + cm.end() - 1  # at the '{'
        body_end = match_brace(src, body_start)
        if body_end < 0:
            continue
        yield m.start(), try_end, body_start, body_end, param


def step_run_spans(src: str):
    """(start, end) of each `step.run(...)` call's paren region."""
    for m in STEP_RUN_RE.finditer(src):
        p = src.index("(", m.start())
        e = match_paren(src, p)
        if e > 0:
            yield m.start(), e


def identity_hits(body: str, param: str) -> list[str]:
    hits = []
    if IDENT_INSTANCEOF_RE.search(body):
        hits.append("instanceof")
    # `.name ===` / `.status` reads on the catch param (or a cast of it).
    if re.search(re.escape(param) + r"(?:\s+as\s+\w+)?\s*\.\s*name\s*===", body):
        hits.append(f"{param}.name ===")
    if re.search(re.escape(param) + r"(?:\s+as\s+\w+)?\s*\.\s*status\b", body):
        hits.append(f"{param}.status")
    # Also catch `X instanceof` written against a cast: `(p as T).status`
    if re.search(r"\(\s*" + re.escape(param) + r"\s+as\s+[\w.]+\s*\)\s*\.\s*(name\s*===|status)", body):
        hits.append(f"({param} as T) identity read")
    return hits


def scan_file(path: str) -> list[str]:
    src = strip_comments(open(path, encoding="utf-8").read())
    basename = os.path.basename(path)
    runs = list(step_run_spans(src))
    problems = []
    for try_s, try_e, cb_s, cb_e, param in find_catches(src):
        body = src[cb_s:cb_e]
        hits = identity_hits(body, param)
        if not hits:
            continue
        line = line_of(src, try_s)
        own_try_has_step = "step.run(" in src[try_s:try_e]
        inside_step_cb = any(rs <= try_s < re_ for rs, re_ in runs)
        if own_try_has_step:
            problems.append(
                f"{basename}:{line}: catch of a try containing step.run reads "
                f"caught-error identity ({', '.join(hits)}) — after step retries "
                "the catch sees the SDK's rebuilt StepError, so this never matches "
                "in production (#8717/#8726 class). Classify inside the step or "
                "return a tagged verdict."
            )
        elif inside_step_cb and basename not in STEP_INTERNAL_ALLOWLIST:
            problems.append(
                f"{basename}:{line}: catch INSIDE a step.run callback reads "
                f"caught-error identity ({', '.join(hits)}). The error there is "
                "live (never crossed the boundary), which is legal — but the "
                "census requires explicit registration: add this file to "
                "STEP_INTERNAL_ALLOWLIST in scripts/lint-inngest-step-boundary.py."
            )
    return problems


def main(argv: list[str]) -> int:
    dirs = argv[1:] or [DEFAULT_DIR]
    for d in dirs:
        if not os.path.isdir(d):
            print(f"lint-inngest-step-boundary: not a directory: {d}", file=sys.stderr)
            return 2
    problems: list[str] = []
    for d in dirs:
        for name in sorted(os.listdir(d)):
            if name.endswith(".ts"):
                problems.extend(scan_file(os.path.join(d, name)))
    if problems:
        print("lint-inngest-step-boundary: step-boundary error-identity violations:", file=sys.stderr)
        for p in problems:
            print(f"  {p}", file=sys.stderr)
        return 1
    print("lint-inngest-step-boundary: clean")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
