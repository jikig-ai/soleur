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
`.github/workflows/*.yml|yaml` AND `.github/actions/*/action.yml|yaml` —
the composite-action `run:` blocks are the same filing surface (tracked
residual of #12092; a capture there fails the census identically). The
census class is the UNQUOTED assignment capture `IDENT=$(` — the abort-capable
form. A `$(gh …)` in word-expansion position (`for n in $(…)`, `echo "$(…)"`)
cannot abort the step — the substitution's rc is not the command's rc — so it
is outside the class by construction, not by exemption.

THE QUOTED TWIN. `IDENT="$(gh …)"` IS abort-capable (the assignment still takes
the substitution's rc) and is the same defect, but it is deliberately outside
this ratchet's census: the #9659 enumeration and the fail-closed/benign
markers predate it, and the quoted class (~26 sites, files outside the
issue's scope) carries only partial dispositions. They are measured, never
hidden: every run prints an ADVISORY list of quoted captures carrying no
per-line disposition (it is data, not a gate — the normalized shape
deliberately stays unquoted so every normalized site REMAINS ratcheted).

SCAN MODEL (per file)
---------------------
1. Physical lines are joined on trailing `\\` continuations into logical
   lines; the site line reported is the logical line's first physical line.
2. `#` comments are stripped quote-aware (same convention as
   lint-gh-argv-arg.py) before site/handling analysis — a `=$(gh` shape
   inside a comment is data. `# dedupe:` markers are detected on the RAW
   physical lines (they ARE comments by design).
3. Heredoc bodies are skipped entirely — `<<'EOF' … EOF` content is stdin
   data, never executed argv.
4. Each `$(` is located quote-aware. Grammar edges are loud, not silently
   misread: a `$(` spanning physical lines without a backslash join, a
   `${x:-a||b}` parameter expansion, and `${`/`(` nested frames are
   unmodelable — a construct the linter cannot resolve stays UNCLASSIFIED
   (finding), which is the direction #9659 requires. A site is a `$(` whose
   interior command
   begins `gh (issue|pr) (list|search)`. It is a CENSUS site when `IDENT=`
   abuts the `$(` unquoted; a QUOTED site when `IDENT="` abuts it (or the
   `$(` sits inside a double-quoted assignment value).
5. A site is CLASSIFIED when the logical line binds its failure: the capture sits in a
   condition list — `if`/`elif`/`while`/`until` with no `then`/`do` body
   keyword between it and the site (set -e exempt by POSIX; a `then`/`do`
   boundary re-arms the abort), or a NON-VACUOUS `||` ADJOINING the `$(…)`
   span (modulo same-command redirects and wrapping `)` closes) on the same
   logical line (`|| true`/`|| :`/bare `VAR=""` first-elements are silent
   collapses, not dispositions — the same defect as the inside-
   substitution `|| true`; an EMPTY arm is unmodelable, hence unclassified). Otherwise it is classified only by a `# dedupe:` marker on the
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

# `gh` noun + verb that constitute the dedupe-read class. The bound is
# DELIBERATE (tracked residual): `gh api` issues-GETs, `gh issue|pr view`
# existence probes, and quoted-capture twins are adjacent read surfaces
# outside #9659's enumeration — a follow-up issue names them; they are not
# silently missed. (Composite action.yml run blocks entered the scan root in
# #12092; `gh` invoked through wrapper functions — e.g. `gh_app`/`gh_gate` —
# stays unmatched, a recorded bound.)
GH_DEDUPE_HEAD = re.compile(r"^\s*gh\s+(issue|pr)\s+(list|search)\b")

# A `IDENT=` token abutting a `$(` or a `"` (the census class, and the quoted
# twin's assignment detection). The `=` must sit at a word boundary — `x=$(`
# inside a larger word is not an assignment.
ASSIGN_TAIL = re.compile(r"(?:^|[\s;|&({!])([A-Za-z_][A-Za-z0-9_]*)\+?=$")

# Condition-context keywords: in `if`/`elif`/`while`/`until` the command's rc
# drives the branch, so the capture is set -e exempt and its failure is bound.
# The keyword must IMMEDIATELY precede the assignment — `if IDENT=$(…)` is
# set -e exempt because the capture IS the condition command; `if [ -n "$X" ];
# then V=$(gh …); fi` puts the site in the THEN body where it still aborts
# (the `then`/`;` boundary ends the condition context). `if ! IDENT=$(…)` is
# still the condition command (the `!` negates but the rc still drives the
# branch — the normalized fail-open shape), while a BARE `! V=$(gh…)` with no
# condition keyword suppresses the abort entirely — a silent collapse, not a
# bound read, and it stays unclassified.
CONDITION_RE = re.compile(r"(?:^|[\s;|&({])(?:if|elif|while|until)\s")
# `then`/`do` open a BODY — a site after one is no longer in the condition
# list. `;`/`&&`/`||` between the keyword and the site are still condition
# commands (`if a; V=$(…); then` is POSIX-exempt); `else`/`elif`/`fi`/`done`
# cannot legally precede a site without a `then`/`do` already ending it.
_BODY_WORD_RE = re.compile(r"\b(?:then|do)\b")


def _in_condition(prefix: str) -> bool:
    m = CONDITION_RE.search(prefix)
    return m is not None and not _BODY_WORD_RE.search(prefix[m.end():])

# Typed dispositions only — `# dedupe: <anything>` is NOT a marker. The
# vocabulary is the two buckets this lint's docstring defines; a bogus bucket
# (`# dedupe: fine`, `# dedupe: bening`) silently classifies nothing.
MARKER_RE = re.compile(r"#\s*dedupe:\s*(?:benign|fail-closed)\s+\S")



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


def _or_status(text: str, idx: int, initial_quote: str = None) -> str:
    """Classify the `||` situation adjoining the `$(…)`: 'bound' (a
    non-vacuous handler adjoins), 'vacuous' (a `||` adjoins but its first
    element silently discharges — `true`/`:`/bare `IDENT=`), or 'none'
    (no adjacent `||` — the capture stands alone).

    A vacuous `||` is silent collapse in EVERY context, including inside a
    condition: `if X=$(gh…) || true; then` is always-then — the fault is
    eaten by the condition itself, the same defect class as `|| true` on a
    plain line. Callers treat 'vacuous' as unclassified even when the site
    sits in a condition list.

    Token-presence anywhere on the line is not binding.

    `X=$(gh …); [ -n "$X" ] || exit 0` contains a `||` that binds the `[ ]`
    while the capture still aborts the step — the `||` must be the first
    command operator after `)` (modulo whitespace, the quoted site's closing
    `"`, same-command redirect words like `2>&1`, and `)` closes of wrapping
    subshells/groups — `V=$(gh…) 2>/dev/null || rc=$?` and `( V=$(gh…) ) || rc=$?`
    are bound). Any other token — `;`, `|`, `&&`, `&` — means the capture
    stands alone.

    A vacuous FIRST element is still the silent collapse the census reds:
    `|| true` / `|| :` / `|| VAR=`/`""`/`''` discharge the rc with no
    disposition — identical to the inside-substitution `$(… || true)` — and
    the verdict is on the arm's first word, so a trailing `; next` or
    `>/dev/null` cannot launder it. `|| rc=$?`-style captures, `|| {…}`
    blocks, `|| false` (still aborts — loud), and `exit`/echo/`::error::`
    arms all carry a disposition and bind. An EMPTY arm (`||` at logical-line
    end, handler on a continued line the model cannot see) is unclassified —
    the same loud direction as every unmodelable construct.

    initial_quote is the quote context the scan STARTS in: the tail of a
    `IDENT="$(gh …)"` site begins with the `"` that CLOSES the assignment's
    quote — seeding `"` lets that char toggle dq off instead of on, and a
    `\"` inside the quoted tail is an escape, never a quote edge.
    """
    i = idx
    n = len(text)
    q = initial_quote
    while i < n:
        ch = text[i]
        if ch == "\\" and i + 1 < n:
            i += 2
            continue
        if q:
            if ch == q:
                q = None
            i += 1
            continue
        if ch in "'\"":
            q = ch
            i += 1
            continue
        if ch.isspace():
            i += 1
            continue
        if ch == "|" and i + 1 < n and text[i + 1] == "|":
            return "vacuous" if _vacuous_first(text[i + 2:]) else "bound"
        if ch == ")":
            i += 1
            continue
        # A redirect word (`2>/dev/null`, `>&1`, `>file`, `2>`) belongs to the
        # capture's own command — skip it and any whitespace before re-checking.
        m = _REDIRECT_RE.match(text, i)
        if m:
            i = m.end()
            continue
        return "none"
    return "none"


# A redirect token: optional fd digit(s), a direction char, optional `&`,
# then either a target glued on (`>/dev/null`, `2>&1`) or a bare `>`/`2>`
# whose target follows as the next word.
_REDIRECT_RE = re.compile(r"[0-9]*[<>]&?(?:[^\s;&|()]+)?")


def _vacuous_first(arm: str) -> bool:
    """Whether the first pipeline element of a `||` arm silently discharges
    the fault. `true`/`:` are no-ops regardless of arguments; a bare
    `IDENT=`/`IDENT=""`/`IDENT=''` emptying assignment discards the rc —
    `$?` does NOT match (it stores, not discards), so `rc=$?`/`list_rc=$?`
    stay dispositions.
    """
    m = re.match(r"\s*([^\s;|&]+)", arm)
    if m is None:
        return True  # empty arm — no disposition visible on this line
    return _VACUOUS_WORD_RE.match(m.group(1)) is not None


_VACUOUS_WORD_RE = re.compile(
    r"(?:true|:|[A-Za-z_][A-Za-z0-9_]*=(?:\"\"|\'\'|))$")
# `|| { :; }`-style blocks whose interior is all no-ops are unmodelled — they
# classify 'bound' (a `{` first token is a disposition shape); a deliberate
# exotic arm carries a `# dedupe:` marker, same as every unmodelled shape.


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
    """Typed `# dedupe:` marker on the site's own physical line or within 2
    lines above — and the `#` must open a REAL comment, not sit inside a
    quoted string (an echoed `"# dedupe:"` is data, not a disposition)."""
    lo = max(0, lineno_1based - 3)
    for k in range(lo, lineno_1based):
        line = raw_lines[k]
        code_len = len(_strip_comment(line).rstrip())
        for m in MARKER_RE.finditer(line):
            if m.start() >= code_len:
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
            tail = stripped[end:]
            or_status = _or_status(
                tail, 0, initial_quote='"' if kind == "quoted" else None)
            handled = or_status == "bound" or (
                _in_condition(prefix) and or_status != "vacuous")
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


def collect(root: str, quiet: bool = False):
    targets = []

    def _add(path):
        if os.path.islink(path):
            if not quiet:
                print("dedupe-shape: advisory: symlink skipped: "
                      f"{path} — the census covers tracked files, "
                      "not linked content")
            return
        targets.append(path)

    wf_dir = os.path.join(root, ".github", "workflows")
    if os.path.isdir(wf_dir):
        for name in sorted(os.listdir(wf_dir)):
            if name.endswith((".yml", ".yaml")):
                _add(os.path.join(wf_dir, name))
    # Composite actions carry the same `run:`-block capture surface; each
    # lives in its own directory under .github/actions/.
    act_dir = os.path.join(root, ".github", "actions")
    if os.path.isdir(act_dir):
        for sub in sorted(os.listdir(act_dir)):
            sub_dir = os.path.join(act_dir, sub)
            if os.path.islink(sub_dir):
                # isdir() follows links — a linked dir would let the census
                # read outside the scan root under an in-root path.
                if not quiet:
                    print("dedupe-shape: advisory: symlink skipped: "
                          f"{sub_dir} — the census covers tracked files, "
                          "not linked content")
                continue
            if not os.path.isdir(sub_dir):
                continue
            for name in ("action.yml", "action.yaml"):
                t = os.path.join(sub_dir, name)
                if os.path.isfile(t) or os.path.islink(t):
                    _add(t)
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

    targets = collect(root, args.quiet)
    if not targets:
        print(f"lint-gh-dedupe-shape: zero scan targets under {root} — "
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
        print("lint-gh-dedupe-shape: zero census sites in the scan root "
              f"under {root} — a 0-match census is a broken detector, "
              "not a clean tree (vacuity).", file=sys.stderr)
        return 2

    n_handled = sum(1 for *_, v in census if v == "handled")
    n_marked = sum(1 for *_, v in census if v == "marked")
    findings = [r for r in census if r[3] == "unclassified"]

    for rel, lineno, ident, _ in findings:
        print(f"{rel}:{lineno}: {ident}=$(gh …) — unclassified dedupe "
              "capture: no condition context, no || handler on the logical "
              "line, no '# dedupe: fail-closed|benign <reason>' marker on "
              "this line or within 2 lines above it")

    if not args.quiet:
        print(f"dedupe-shape: scanned {len(targets)} file(s), "
              f"{len(census)} census site(s): {n_handled} handled, "
              f"{n_marked} marked")
    print(f"dedupe-shape: unclassified: {len(findings)}")

    # Advisory census — the quoted `IDENT="$(` twin class. Data, never a gate:
    # the sites are outside #9659's enumerated scope, and the normalized shape
    # stays unquoted precisely so every normalized site REMAINS ratcheted.
    if advisory and not args.quiet:
        print(f"dedupe-shape: advisory: {len(advisory)} quoted-capture site(s) "
              "outside the =$( census class carry no PER-LINE disposition "
              "(residual beyond #9659's scope; step-level `set +e`/`rc` "
              "handlers outside this model's view may still bind them — "
              "informational, not a finding):")
        for rel, lineno, ident in advisory:
            print(f"  advisory: {rel}:{lineno}: {ident}=\"$(gh …)\"")

    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main())
