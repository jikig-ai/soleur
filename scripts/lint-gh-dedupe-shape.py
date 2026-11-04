#!/usr/bin/env python3
"""Fail when a `VAR=$(gh issue|pr list|search …)` dedupe capture in a workflow
carries no failure disposition: no `if`/`while`/`until` condition context, no
`||` handler on its logical line, and no `# dedupe:` marker within 2 lines.

WHY THIS EXISTS
---------------
#9612 normalized its enumerated `EXISTING=$(gh issue list …)` dedupe sites and
#9659 closed the residual: under `set -euo pipefail` a transient `gh` fault at a
bare `VAR=$(gh …)` capture aborts the step mid-alarm with no breadcrumb — the
dedupe lookup dies, the alarm never files, and the run log shows a step that
simply stopped. The class kept growing past #9612's enumeration (76 sites
across 19 workflow files measured 2026-11-04) because nothing mechanical
classified new sites; a document-only fix re-grows the next one (ADR-166 is the
in-repo precedent for the mechanical gate).

The ratcheted contract per site is one of three dispositions:

  * FAIL-OPEN (normalized): `VAR=$(gh …) || { echo "::error::<slug>: dedupe
    query failed — filing without dedupe"; VAR=""; }`, or the `if ! VAR=$(…)`
    wrapped form — a failed lookup is loud AND files anyway, the deliberate
    duplicate trade against filing nothing.
  * FAIL-CLOSED (deliberate): an `|| rc=$?`/`|| LIST_RC=$?` handler that
    refuses to act on an unreadable read, documented by a
    `# dedupe: fail-closed <reason>` marker.
  * BENIGN (deliberate): a close/staleness/age read whose failure direction
    keeps the alarm (a skipped close leaves the issue open — visible), marked
    `# dedupe: benign <reason>`.

A `||` INSIDE the `$(…)` substitution (`$(gh … || true)`, `$(gh … 2>/dev/null
|| true)`) is NOT a disposition: the substitution itself can never abort, so
the read collapses "API fault" into "nothing found" silently — the exact
defect #9659 names on `scheduled-cron-artifact-age.yml`'s filing path. The
handler must sit OUTSIDE the capture.

SCOPE
-----
`.github/workflows/*.yml|yaml` — the filing-path census class of #9659. The
census class is the UNQUOTED assignment capture `IDENT=$(` — the abort-capable
form. A `$(gh …)` in word-expansion position (`for n in $(…)`, `echo "$(…)"`)
cannot abort the step — the substitution's rc is not the command's rc — so it
is outside the class by construction, not by exemption.

THE QUOTED TWIN. `IDENT="$(gh …)"` IS abort-capable (the assignment still takes
the substitution's rc) and is the same defect, but it is deliberately outside
this ratchet's census: the #9659 enumeration and the fail-closed/benign
markers predate it, and ~26 quoted sites live in files outside the issue's
scope. They are measured, never hidden: every run prints an ADVISORY list of
quoted captures that carry no disposition (it is data, not a gate — the
normalized shape deliberately stays unquoted so every normalized site REMAINS
inside the ratchet).

SCAN MODEL (per file)
---------------------
1. Physical lines are joined on trailing `\\` continuations into logical
   lines; the site line reported is the physical line carrying `IDENT=$(`.
2. `#` comments are stripped quote-aware (same convention as
   lint-gh-argv-arg.py) before site/handling analysis — a `=$(gh` shape
   inside a comment is data. `# dedupe:` markers are detected on the RAW
   physical lines (they ARE comments by design).
3. Heredoc bodies are skipped entirely — `<<'EOF' … EOF` content is stdin
   data, never executed argv.
4. Each `$(` is located quote-aware. A site is a `$(` whose interior command
   begins `gh (issue|pr) (list|search)`. It is a CENSUS site when `IDENT=`
   abuts the `$(` unquoted; a QUOTED site when `IDENT="` abuts it (or the
   `$(` sits inside a double-quoted assignment value).
5. A site is CLASSIFIED when the logical line binds its failure: the capture
   is in an `if`/`elif`/`while`/`until`/`!` condition context (set -e exempt
   by POSIX), or a `||` appears outside the `$(…)` span on the same logical
   line. Otherwise it is classified only by a `# dedupe:` marker on the
   site's own line or within 2 physical lines above it.

DIRECTION OF ERROR: unclassified sites are findings (the class cannot
silently re-grow). A construct this linter cannot model stays unclassified
and loud — the marker is how a deliberate exotic shape stays green.

VACUITY. A root with no `.github/workflows` directory is a usage error
(rc=2). A tree that scans workflows but finds ZERO census sites also exits
rc=2 — a 0-match census is a broken detector, not a clean tree (Guard 1
mutation row 4).
"""

import argparse
import os
import re
import sys

# `gh` noun + verb that constitute the dedupe-read class.
GH_DEDUPE_HEAD = re.compile(r"^\s*gh\s+(issue|pr)\s+(list|search)\b")

# A `IDENT=` token abutting a `$(` or a `"` (the census class, and the quoted
# twin's assignment detection). The `=` must sit at a word boundary — `x=$(`
# inside a larger word is not an assignment.
ASSIGN_TAIL = re.compile(r"(?:^|[\s;|&({!])([A-Za-z_][A-Za-z0-9_]*)=$")

# Condition-context keywords: in `if`/`elif`/`while`/`until` the command's rc
# drives the branch, so the capture is set -e exempt and its failure is bound.
CONDITION_RE = re.compile(r"(?:^|[\s;|&({])(?:if|elif|while|until)\b")

MARKER_RE = re.compile(r"#\s*dedupe:\s*\S")

SHELL_KEYWORDS = {"if", "then", "elif", "else", "while", "until", "do",
                  "done", "for", "in", "time", "{", "}", "!", "select"}


def _find_heredocs(line: str):
    """Return heredoc delimiters opened on this line, quote-aware.

    Verbatim convention of lint-gh-argv-arg.py: a `<<` inside quotes or part
    of `<<<` (herestring) is not a heredoc opener.
    """
    delims = []
    q = None
    i = 0
    n = len(line)
    while i < n:
        ch = line[i]
        if q:
            if ch == q:
                q = None
            i += 1
            continue
        if ch in "'\"":
            q = ch
            i += 1
            continue
        if ch == "\\" and i + 1 < n:
            i += 2
            continue
        if ch == "<" and i + 1 < n and line[i + 1] == "<":
            j = i + 2
            if j < n and line[j] == "<":   # <<< is a herestring, not a heredoc
                i += 3
                continue
            if j < n and line[j] == "-":   # <<- strips leading tabs
                j += 1
            while j < n and line[j] in " \t":
                j += 1
            if j < n and line[j] in "'\"":
                j += 1
            m = re.match(r"[A-Za-z_][\w]*", line[j:])
            if m:
                delims.append(m.group(0))
                i = j + m.end()
                continue
            i += 2
            continue
        i += 1
    return delims


def _strip_comment(line: str) -> str:
    """Return the line with a shell `#` comment removed, quote-aware.

    `#` opens a comment only where it would start a new word: at position 0,
    or immediately after whitespace or a shell operator -- never mid-token
    (`${x#y}`, `a#b`, `'quoted # text'` are all data). Same convention as
    lint-gh-argv-arg.py — the `# dedupe:` markers themselves are comments and
    are matched on raw lines, not here.
    """
    out = []
    q = None
    prev_op = True
    i = 0
    n = len(line)
    while i < n:
        ch = line[i]
        if q:
            out.append(ch)
            if ch == "\\" and q == '"' and i + 1 < n:
                out.append(line[i + 1])
                i += 2
                continue
            if ch == q:
                q = None
            i += 1
            continue
        if ch in "'\"":
            q = ch
            out.append(ch)
            prev_op = False
            i += 1
            continue
        if ch == "\\" and i + 1 < n:
            out.append(ch)
            out.append(line[i + 1])
            prev_op = False
            i += 2
            continue
        if ch == "#" and prev_op:
            break
        out.append(ch)
        prev_op = ch.isspace() or ch in "|&;()<>"
        i += 1
    return "".join(out)


def _subst_end(text: str, dollar_idx: int) -> int:
    """Return the index just past the `)` closing `$(` at dollar_idx, or -1.

    Frame stack of quote states: the top frame is the active context. A `$(`
    opens a FRESH command context even inside double quotes — the outer
    double-quote does not carry into it (the sibling parser's `_segments`
    makes the same cut: `--label "$(sed -E '…' <<<"$T")"` single-quotes inside
    the nested subst are real quotes, and the `)` after them is a paren, not
    data). A bare `(` opens a subshell — likewise a fresh context. Inside a
    double-quote frame, `'` is literal, `\\` escapes the next char, and `$(`
    still nests.
    """
    i = dollar_idx + 2
    n = len(text)
    stack = [None]  # None=unquoted, "'"=sq, '"'=dq
    while i < n:
        ch = text[i]
        top = stack[-1]
        if top == "'":
            if ch == "'":
                stack[-1] = None
            i += 1
            continue
        if ch == "\\" and i + 1 < n:
            i += 2
            continue
        if top == '"':
            if ch == '"':
                stack[-1] = None
                i += 1
                continue
            if ch == "$" and i + 1 < n and text[i + 1] == "(":
                stack.append(None)
                i += 2
                continue
            i += 1
            continue
        if ch == "'":
            stack[-1] = "'"
            i += 1
            continue
        if ch == '"':
            stack[-1] = '"'
            i += 1
            continue
        if ch == "$" and i + 1 < n and text[i + 1] == "(":
            stack.append(None)
            i += 2
            continue
        if ch == "(":
            stack.append(None)
            i += 1
            continue
        if ch == ")":
            stack.pop()
            i += 1
            if not stack:
                return i
            continue
        i += 1
    return -1


def _has_or_outside(text: str, idx: int, initial_quote: str = None) -> bool:
    """Whether an unquoted `||` appears in text starting at idx.

    initial_quote is the quote context the scan STARTS in: the tail of a
    `IDENT="$(gh …)"` site begins with the `"` that CLOSES the assignment's
    quote — seeding `"` lets that char toggle dq off instead of on, which is
    the difference between finding `||` in `)" || { … }` and missing it.
    """
    i = idx
    n = len(text)
    q = initial_quote
    while i < n:
        ch = text[i]
        if q:
            if ch == q:
                q = None
            i += 1
            continue
        if ch in "'\"":
            q = ch
            i += 1
            continue
        if ch == "\\" and i + 1 < n:
            i += 2
            continue
        if ch == "|" and i + 1 < n and text[i + 1] == "|":
            return True
        i += 1
    return False


def _sites_in_line(ltext: str):
    """Yield (kind, ident, site_col, subst_end_col) for every `$(gh …)` capture.

    kind is 'census' for unquoted `IDENT=$(`, 'quoted' for `IDENT="$(` (and for
    a `$(` nested inside an open `IDENT="` value). Non-capture `$(` uses are
    skipped — not abort-capable, not the class.

    Frame stack like _subst_end's: each entry is None (unquoted), "'" (single
    quote), or ('"', assign|None) — a double-quote frame that remembers the
    IDENT whose `=` opened it, because `X="pre $(gh …)"` is still an
    abort-capable assignment capture. `$(` and `(` push fresh unquoted frames;
    `)` pops; `'`/`"` retag the current frame.
    """
    i = 0
    n = len(ltext)
    stack = [None]
    while i < n:
        ch = ltext[i]
        top = stack[-1]
        if top == "'":
            if ch == "'":
                stack[-1] = None
            i += 1
            continue
        if ch == "\\" and i + 1 < n:
            i += 2
            continue
        if isinstance(top, tuple):  # double-quote frame
            if ch == '"':
                stack[-1] = None
                i += 1
                continue
            if ch == "$" and i + 1 < n and ltext[i + 1] == "(":
                end = _subst_end(ltext, i)
                inner = ltext[i + 2:] if end == -1 else ltext[i + 2:end - 1]
                if top[1] and GH_DEDUPE_HEAD.match(inner):
                    yield ("quoted", top[1], i, end if end != -1 else n)
                stack.append(None)
                i += 2
                continue
            i += 1
            continue
        if ch == "'":
            stack[-1] = "'"
            i += 1
            continue
        if ch == '"':
            m = ASSIGN_TAIL.search(ltext[:i])
            stack[-1] = ('"', m.group(1) if m else None)
            i += 1
            continue
        if ch == "$" and i + 1 < n and ltext[i + 1] == "(":
            end = _subst_end(ltext, i)
            inner = ltext[i + 2:] if end == -1 else ltext[i + 2:end - 1]
            if GH_DEDUPE_HEAD.match(inner):
                m = ASSIGN_TAIL.search(ltext[:i])
                if m:
                    yield ("census", m.group(1), i, end if end != -1 else n)
            stack.append(None)
            i += 2
            continue
        if ch == "(":
            stack.append(None)
            i += 1
            continue
        if ch == ")":
            if len(stack) > 1:
                stack.pop()
            i += 1
            continue
        i += 1


def _has_marker(raw_lines, lineno_1based: int) -> bool:
    """`# dedupe:` on the site's own physical line or within 2 lines above."""
    lo = max(0, lineno_1based - 3)
    for k in range(lo, lineno_1based):
        if MARKER_RE.search(raw_lines[k]):
            return True
    return False


def scan_file(path: str, rel: str):
    """Return (census_rows, advisory_rows).

    census_rows:   (rel, lineno, ident, verdict) per `IDENT=$(gh …)` site —
                   verdict is 'handled', 'marked', or 'unclassified'.
    advisory_rows: (rel, lineno, ident) per UNCLASSIFIED `IDENT="$(gh …)` site.
    """
    census_rows = []
    advisory_rows = []
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as f:
            phys = f.read().split("\n")
    except OSError as e:
        print(f"{rel}:0: unreadable ({e})", file=sys.stderr)
        return census_rows, advisory_rows

    # 1. logical lines joined on trailing backslash continuations.
    logical = []  # (start_lineno_1based, text)
    buf = ""
    start = 1
    for idx, pl in enumerate(phys, 1):
        if not buf:
            start = idx
        if pl.endswith("\\"):
            buf += pl[:-1] + " "
            continue
        buf += pl
        logical.append((start, buf))
        buf = ""
    if buf:
        logical.append((start, buf))

    # 2-3. per logical line: strip comments for analysis, skip heredoc bodies.
    pending_hd = []
    for lineno, ltext in logical:
        if pending_hd:
            if ltext.strip() == pending_hd[0]:
                pending_hd.pop(0)
            continue
        stripped = _strip_comment(ltext)
        pending_hd.extend(_find_heredocs(stripped))

        for kind, ident, col, end in _sites_in_line(stripped):
            prefix = stripped[:col]
            tail = stripped[end:] if end != -1 else ""
            handled = bool(CONDITION_RE.search(prefix)) \
                or _has_or_outside(
                    tail, 0, initial_quote='"' if kind == "quoted" else None)
            if kind == "census":
                if handled:
                    verdict = "handled"
                elif _has_marker(phys, lineno):
                    verdict = "marked"
                else:
                    verdict = "unclassified"
                census_rows.append((rel, lineno, ident, verdict))
            else:  # quoted — advisory class, never a gate finding
                if not handled and not _has_marker(phys, lineno):
                    advisory_rows.append((rel, lineno, ident))
    return census_rows, advisory_rows


def collect(root: str):
    targets = []
    wf_dir = os.path.join(root, ".github", "workflows")
    if os.path.isdir(wf_dir):
        for name in sorted(os.listdir(wf_dir)):
            if name.endswith((".yml", ".yaml")):
                targets.append(os.path.join(wf_dir, name))
    return targets


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--root", default=".", help="repository root to scan")
    ap.add_argument("--quiet", action="store_true",
                    help="print findings and the unclassified count only")
    args = ap.parse_args()

    root = os.path.abspath(args.root)
    if not os.path.isdir(os.path.join(root, ".github", "workflows")):
        print("lint-gh-dedupe-shape: no .github/workflows directory under "
              f"{root} — refusing to report a clean sweep of nothing.",
              file=sys.stderr)
        return 2

    targets = collect(root)
    if not targets:
        print(f"lint-gh-dedupe-shape: zero workflow files under {root} — "
              "refusing to report a clean sweep of nothing.", file=sys.stderr)
        return 2

    census = []
    advisory = []
    for t in targets:
        rel = os.path.relpath(t, root)
        c, a = scan_file(t, rel)
        census.extend(c)
        advisory.extend(a)

    if not census:
        print("lint-gh-dedupe-shape: zero census sites under "
              f"{root}/.github/workflows — a 0-match census is a broken "
              "detector, not a clean tree (vacuity).", file=sys.stderr)
        return 2

    n_handled = sum(1 for *_, v in census if v == "handled")
    n_marked = sum(1 for *_, v in census if v == "marked")
    findings = [r for r in census if r[3] == "unclassified"]

    for rel, lineno, ident, _ in findings:
        print(f"{rel}:{lineno}: {ident}=$(gh …) — unclassified dedupe "
              "capture: no condition context, no || handler on the logical "
              "line, no '# dedupe:' marker within 2 lines")

    if not args.quiet:
        print(f"dedupe-shape: scanned {len(targets)} workflow(s), "
              f"{len(census)} census site(s): {n_handled} handled, "
              f"{n_marked} marked")
    print(f"dedupe-shape: unclassified: {len(findings)}")

    # Advisory census — the quoted `IDENT="$(` twin class. Data, never a gate:
    # the sites are outside #9659's enumerated scope, and the normalized shape
    # stays unquoted precisely so every normalized site REMAINS ratcheted.
    if advisory:
        print(f"dedupe-shape: advisory: {len(advisory)} quoted-capture site(s) "
              "outside the =$( census class carry no disposition (residual "
              "beyond #9659's scope — informational, not a finding):")
        for rel, lineno, ident in advisory:
            print(f"  advisory: {rel}:{lineno}: {ident}=\"$(gh …)\"")

    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main())
