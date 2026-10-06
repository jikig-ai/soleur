#!/usr/bin/env python3
"""Fail when a jq-flag token (--arg, --argjson, --argfile, --slurpfile, --rawfile)
appears inside a `gh` command's own argv.

WHY THIS EXISTS
---------------
`gh --jq` takes exactly ONE expression; it does not forward jq's
argument-passing flags (cli/cli#10263; repo learning
2026-03-04-gh-jq-does-not-support-arg-flag.md). An `--arg` that lands in gh's
argv is rejected as an unknown flag -- and under `set -euo pipefail`, a bare
`VAR=$(gh ... --arg ...)` aborts the step before whatever filing or
diagnostic the block exists to run. This is the dedupe-filing variant of the
silent-abort class: the dedupe lookup dies, the alarm never files, and the
run log shows a step that simply stopped.

The canonical correct shape -- `gh ... | jq -r --arg t "$T" '...'` -- puts the
flag in JQ's argv, which is where it belongs. The repo normalized on it after
#9533; this sentinel exists because the wrong shape kept re-appearing
anyway (docs-only enforcement of a shell-semantics invariant does not work;
ADR-166 is the in-repo precedent for the mechanical gate).

SCOPE
-----
Every `.github/workflows/*.yml|yaml` and every `**/*.sh` in the tree —
hooks, plugin scripts, tests and followthroughs execute the same gh argv, so
"repo-wide" means the whole tree, not `scripts/` alone. Excluded: `.git`,
`.worktrees`, `node_modules`, `dist`, `.next`, `__pycache__`, venvs, and any
`fixtures/` directory -- fixture trees are canned inputs to OTHER linters;
their "violations" are intentional data, never executed argv.

SCAN MODEL (per file)
---------------------
1. Physical lines are joined on trailing `\\` continuations into logical
   lines (a `gh ... \\` + `--arg t` split across two lines is one invocation).
2. `#` comments are stripped -- but only where `#` starts a word (position 0
   or whitespace-preceded, outside quotes). `#` inside `${var#pat}` or inside
   a quoted string is data. This matters in practice: the files that carry the
   fix also carry comments QUOTING the defect ("`gh --jq` does not forward
   `--arg`"), and a non-quote-aware stripper either flags them or, worse,
   teaches the next author to remove the explanation.
3. Heredoc bodies are skipped entirely -- `<<'EOF' ... EOF` content is stdin
   data, never argv (test fixtures and generated-file writes embed gh-shaped
   text routinely).
4. Each logical line splits into command segments at unquoted `|`, `||`,
   `&&`, `;`, `&`, `(`, and `$(`. The pipe split is what keeps the canonical
   `gh ... | jq --arg` form green: the flag lives in jq's segment.
5. Within a segment, transparent prefixes are peeled (VAR=value assignments,
   `!`, YAML list dash `-` and `key:` tokens, shell keywords
   if/then/elif/while/until/do, and wrappers command/builtin/env/nice/nohup/
   sudo/doas/exec + timeout-with-args) until the command word. A segment
   whose command word is `gh` and whose remaining tokens contain a
   standalone jq-flag-family token is a finding.

DIRECTION OF ERROR: false negatives preferred over false positives. A
shell-shaped construct this linter cannot model (e.g. `gh` reached through a
variable indirection) is silent by design; a noisy gate gets bypassed.
"""

import argparse
import os
import re
import sys

JQ_FLAG_TOKENS = {"--arg", "--argjson", "--argfile", "--slurpfile", "--rawfile"}
JQ_FLAG_PREFIX = re.compile(r"^--(arg|argjson|argfile|slurpfile|rawfile)=")

# Transparent prefixes peeled before the command word. `timeout` is special:
# it consumes option tokens AND a duration before the wrapped command.
SHELL_KEYWORDS = {"if", "then", "elif", "else", "while", "until", "do",
                  "done", "for", "in", "time", "{", "}", "!", "select"}
WRAPPERS = {"command", "builtin", "exec", "env", "nice", "nohup", "sudo",
            "doas", "stdbuf"}
ASSIGN_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")
YAML_KEY_RE = re.compile(r"^[A-Za-z_][\w.-]*:$")
DURATION_RE = re.compile(r"^[0-9.]+[smhd]?$")


def _find_heredocs(line: str):
    """Return heredoc delimiters opened on this line, quote-aware.

    A `<<` inside quotes or part of `<<<` (herestring) is not a heredoc
    opener — measured FP: `echo 'metrics<<QH_EOF'` queued a delimiter that
    never closed and blanked the rest of the file (the sibling linter calls
    this the F13 class).
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
    (`${x#y}`, `a#b`, `'quoted # text'` are all data).
    """
    out = []
    q = None
    prev_op = True  # start-of-line counts as a word boundary
    i = 0
    n = len(line)
    while i < n:
        ch = line[i]
        if q:
            out.append(ch)
            if ch == "\\" and q == '"' and i + 1 < n:
                # inside double quotes a backslash escapes the next char
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
            # escaped char outside quotes: verbatim data, never a comment
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


def _segments(line: str):
    """Split a logical line into command segments at unquoted separators.

    Separators: |, ||, &&, ;, &, (, $(. Each `(`-style boundary opens a new
    command context (subshell / command substitution), so the piece after it
    is scanned as its own segment.
    """
    segs = []
    cur = []
    q = None
    i = 0
    n = len(line)
    while i < n:
        ch = line[i]
        if q:
            # `$(` opens a command context even inside double quotes —
            # `X="$(gh ...)"` is the house-standard assignment shape; single
            # quotes alone make it literal.
            if ch == "$" and q == '"' and i + 1 < n and line[i + 1] == "(":
                cur.append(ch)  # keep the `$` closing the quoted prefix
                segs.append("".join(cur))
                cur = []
                # The `$(` interior is a FRESH command context — the outer
                # double-quote does not carry into it (a `"` inside $(...)
                # opens its own quote). Dropping q here is what lets a `|`
                # inside `"$(gh ... | jq --arg ...)"` still split segments.
                q = None
                i += 2
                continue
            cur.append(ch)
            if ch == "\\" and q != "'" and i + 1 < n:
                cur.append(line[i + 1])
                i += 2
                continue
            if ch == q:
                q = None
            i += 1
            continue
        if ch in "'\"":
            q = ch
            cur.append(ch)
            i += 1
            continue
        if ch == "\\" and i + 1 < n:
            cur.append(ch)
            cur.append(line[i + 1])
            i += 2
            continue
        if ch in "|;&":
            segs.append("".join(cur))
            cur = []
            # consume a doubled operator (||, &&) as one boundary
            if i + 1 < n and line[i + 1] == ch:
                i += 2
            else:
                i += 1
            continue
        if ch == "(":
            # `$(` is consumed by the `$` branch above; a bare `(` opens a
            # subshell — a fresh command context either way.
            segs.append("".join(cur))
            cur = []
            i += 1
            continue
        if ch == "$" and i + 1 < n and line[i + 1] == "(":
            segs.append("".join(cur))
            cur = []
            i += 2
            continue
        cur.append(ch)
        i += 1
    segs.append("".join(cur))
    return segs


def _tokens(seg: str):
    """Whitespace tokenizer that preserves quoted spans as single tokens."""
    toks = []
    cur = []
    q = None
    i = 0
    n = len(seg)
    while i < n:
        ch = seg[i]
        if q:
            cur.append(ch)
            if ch == q:
                q = None
            i += 1
            continue
        if ch in "'\"":
            q = ch
            cur.append(ch)
            i += 1
            continue
        if ch == "\\" and i + 1 < n:
            cur.append(ch)
            cur.append(seg[i + 1])
            i += 2
            continue
        if ch.isspace():
            if cur:
                toks.append("".join(cur))
                cur = []
            i += 1
            continue
        cur.append(ch)
        i += 1
    if cur:
        toks.append("".join(cur))
    return toks


def _command_word(toks):
    """Peel transparent prefixes; return (command_word, argv_tail_index)."""
    i = 0
    n = len(toks)
    while i < n:
        t = toks[i]
        if ASSIGN_RE.match(t):
            i += 1
            continue
        if t in SHELL_KEYWORDS or t == "-":
            i += 1
            continue
        if YAML_KEY_RE.match(t):
            i += 1
            continue
        if t in WRAPPERS:
            i += 1
            continue
        if t == "timeout":
            i += 1
            while i < n and (toks[i].startswith("-") or DURATION_RE.match(toks[i])):
                i += 1
            continue
        return t, i
    return None, n


def _bare(tok: str) -> str:
    """Strip one layer of surrounding quotes so '"--arg"' still reads as a flag."""
    if len(tok) >= 2 and tok[0] in "'\"" and tok[-1] == tok[0]:
        return tok[1:-1]
    return tok


def scan_file(path: str, rel: str):
    findings = []
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as f:
            phys = f.read().split("\n")
    except OSError as e:
        print(f"{rel}:0: unreadable ({e})", file=sys.stderr)
        return findings

    # 1. logical lines: join trailing backslash continuations, tracking the
    #    physical start line of each logical line.
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

    # 2-3. per logical line: strip comments, skip heredoc bodies.
    pending_hd = []
    for lineno, ltext in logical:
        # heredoc bodies terminate on a physical line equal to the delimiter;
        # each logical line maps to >=1 physical lines, and a delimiter is only
        # seen on its own physical line, so approximate: check whether the
        # logical line ENDS at a delimiter physical line.
        if pending_hd:
            # is this logical line a bare delimiter line?
            if ltext.strip() == pending_hd[0]:
                pending_hd.pop(0)
            continue
        stripped = _strip_comment(ltext)
        pending_hd.extend(_find_heredocs(stripped))
        for seg in _segments(stripped):
            toks = _tokens(seg)
            if not toks:
                continue
            cmd, ci = _command_word(toks)
            if cmd != "gh":
                continue
            for tok in toks[ci + 1:]:
                b = _bare(tok)
                if b in JQ_FLAG_TOKENS or JQ_FLAG_PREFIX.match(b):
                    findings.append(
                        (rel, lineno, b,
                         "gh argv carries jq flag; gh's --jq takes one "
                         "expression and does not forward jq flags "
                         "(cli/cli#10263) — move the flag to a downstream jq"))
                    break
    return findings


SKIP_DIRS = {".git", ".worktrees", "node_modules", "dist", ".next",
             "__pycache__", ".venv", "venv", "fixtures"}


def collect(root: str):
    targets = []
    wf_dir = os.path.join(root, ".github", "workflows")
    if os.path.isdir(wf_dir):
        for name in sorted(os.listdir(wf_dir)):
            if name.endswith((".yml", ".yaml")):
                targets.append(os.path.join(wf_dir, name))
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = sorted(d for d in dirnames if d not in SKIP_DIRS)
        for name in sorted(filenames):
            if name.endswith(".sh"):
                targets.append(os.path.join(dirpath, name))
    return targets


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--root", default=".", help="repository root to scan")
    ap.add_argument("--quiet", action="store_true", help="print findings only")
    args = ap.parse_args()

    root = os.path.abspath(args.root)
    if not os.path.isdir(os.path.join(root, ".github", "workflows")) \
            and not os.path.isdir(os.path.join(root, "scripts")):
        print("lint-gh-argv-arg: no .github/workflows or scripts directory "
              f"under {root} — refusing to report a clean sweep of nothing.",
              file=sys.stderr)
        return 2

    targets = collect(root)
    if not targets:
        print(f"lint-gh-argv-arg: zero scan targets under {root} — "
              "refusing to report a clean sweep of nothing.", file=sys.stderr)
        return 2

    all_findings = []
    n_wf = 0
    n_sh = 0
    for t in targets:
        rel = os.path.relpath(t, root)
        if rel.startswith(".github/workflows/"):
            n_wf += 1
        else:
            n_sh += 1
        all_findings.extend(scan_file(t, rel))

    for rel, lineno, tok, msg in all_findings:
        print(f"{rel}:{lineno}: {tok} — {msg}")

    if all_findings:
        print(f"lint-gh-argv-arg: {len(all_findings)} finding(s)")
        return 1
    if not args.quiet:
        print(f"lint-gh-argv-arg: scanned {n_wf} workflow(s), "
              f"{n_sh} shell script(s) — 0 findings")
    return 0


if __name__ == "__main__":
    sys.exit(main())
