#!/usr/bin/env python3
"""Inventory and shrink-only ratchet for signal helpers inside shell test suites.

WHY THIS EXISTS
---------------
A helper that walks `$PPID` upwards and signals the outermost ancestor whose argv matches is bounded
only by its own predicate. Mutate the predicate (invert it, drop it, make it a catch-all) and every
ancestor matches: the walk reaches the top of the user's desktop session. That happened four times on
2026-10-09 (knowledge-base/project/learnings/test-failures/2026-10-09-an-inverted-match-mutant-of-an-
ancestor-walking-helper-ended-the-desktop-session-four-times.md). This scan lists the suites that
contain such a helper, and the other signal-to-ancestors patterns, BEFORE anyone mutates them, and
fails the full battery when a new one lands unbaselined or an unbounded walker is baselined.

USAGE
-----
  scan-ancestor-signal-helpers.py [--root DIR] [--baseline FILE] [--list] [--write-baseline FILE] [PATH ...]

  * Population: the tracked files matching the two pathspecs `*.test.sh` and `:(glob)**/test-*.sh`,
    read from ONE git listing (NUL separated) made with every GIT_* variable removed from the child
    environment, or the explicit PATHs given (paths are used as given and shown as given).
  * Without --baseline the scan is list-only: rc 0 and the notice `no baseline: listing only`, so a
    plugin consumer running it on their own repository does not see every site as new.
  * With --baseline the verdict is gated on classes W, P and G (below). Exit 0 clean, 1 findings,
    3 UNRESOLVED (empty population, failed git, unreadable or malformed baseline, a listed member that
    is missing, or ANY uncaught exception: a traceback can never read as rc 1 "findings").
  * --list prints `class TAB bounded TAB path TAB text` for every finding of every class (bounded is
    yes or no for W and a dash for the others); `--list PATH...` scopes it to the given files, which is
    how a mutation seat checks the one file it is about to mutate.
  * --write-baseline FILE writes the gated rows (overwrites the whole file: review the diff) and
    refuses while any W is unbounded.
  * In explicit-PATH mode only baseline rows whose path is among the given PATHs are judged stale.

CLASSES (a finding is one source line, content-keyed)
-----------------------------------------------------
  W (gated)  ancestor walk with a signal: a self-referential cursor assignment (v=$(... /proc/$v/stat
             ...), v=$(ps -o ppid= -p $v), v=$(... $v ... PPid ...)) with kill, pkill or killall within
             40 lines either side (raw text, so heredoc and string-embedded helpers count). Reported
             bounded=yes only when a NON-COMMENT line from 15 lines above to 3 lines below the cursor
             line mentions SOLEUR_TEST_SUITE_PID in a comparison (!=, ==, =, =~, -ne, -eq, [ -n, [ -z)
             together with exit, break or return on that line, or in a while/until loop condition. A
             mention only in a comment, an echo or a printf reads bounded=no. bounded=yes is a LEXICAL
             check: it cannot see that an unset variable means "signal nothing" or that a trailing
             `|| true` defeats the comparison.
  P (gated)  a signal to the parent: kill and $PPID (or ps -o ppid=) on one line, or a variable assigned
             from $PPID / ps -o ppid= within 20 lines above a kill that names it.
  G (gated)  an all-process or own-group signal at command position: kill [-SIG] 0 and kill [-SIG] -1.
             A line over 4 KB that contains a signal verb is reported here too (fail closed).
  L (listed) targeted group signals (kill -- -<pgid>) and name-pattern signals (pkill, killall). Never
             gated, no baseline: they are not signals to ancestors.
  Never findings: comment lines, signal verbs inside quoted spans, kill -0, kill -l.

READING MODEL
-------------
Files are decoded with errors="surrogateescape" and split on "\\n" only (never str.splitlines(), which
splits on separators bash does not), with "\\r" stripped. A line over 4 KB gets no regex work (counted as
overlong; a substring pre-filter still reports a signal verb on it), a file over 2 MB, a symlink or a
special file is counted skipped. Only the Python standard library is used and nothing from the scanned
tree is imported or executed: the scan reads text and sends no signal.

BASELINE ROWS
-------------
`<path> TAB <class> TAB <normalised line>` (whitespace collapsed, a trailing comment cut), matched as a
multiset against the live gated findings. New, stale and unbounded are red; a baselined W that reads
bounded=no is red (an unbounded walker cannot be baselined).

DOCUMENTED BLIND SPOTS
----------------------
Multi-line quoted strings and backslash-newline continuations (kill \\ then -1); a walk written in
another language (os.getppid); a two-step cursor (parent=$(...); cur=$parent); a kill more than 40 lines
from the cursor or reached through a function; kill $(...) and xargs kill; helpers sourced from a
non-suite file; suites that match neither name shape; fixtures stored under another extension; signal
verbs inside a single-quoted printf that writes a helper (masked as quoted text). The scan is a finding
aid plus a ratchet on the lines it can see, not a proof of absence. The producer lists tracked files
only: an untracked suite is not scanned until it is added.
"""

import argparse
import collections
import os
import re
import stat
import subprocess
import sys

TOKEN = "SOLEUR_TEST_SUITE_PID"
KILL_WINDOW = 40        # a signal within this many lines of a W cursor
BOUND_ABOVE = 15        # bound token window above the cursor line
BOUND_BELOW = 3         # bound token window below the cursor line
DERIVED_WINDOW = 20     # parent variable assigned within this many lines above its kill
MAX_LINE = 4096
MAX_FILE = 2 * 1024 * 1024
GATED = ("W", "P", "G")
PATHSPECS = ["*.test.sh", ":(glob)**/test-*.sh"]

# A signal verb at command position (the text is quote-masked first).
CMDPOS = re.compile(
    r"(?:^|[;&|(){`!]|\$\(|\b(?:then|do|else|if|elif|while|until)\b)\s*"
    r"(?:(?:sudo|exec|command|builtin|nohup|env|timeout\s+\S+)\s+|\\)*"
    r"(kill|pkill|killall)(?![\w./-])"
)
# A signal word anywhere in raw code (used only for the W window; string-embedded helpers count).
LOOSE_SIGNAL = re.compile(r"(?<![\w./-])(?:kill|pkill|killall)(?![\w./-])(?:\s+(?!-0\b|-l\b|-L\b|-s\s+0\b)|$)")
CURSOR = re.compile(r"(?:^|[\s;&|({])(?:local\s+|export\s+|declare\s+-\w+\s+)?(\w+)=(?:\$\(|`)")
PPID_ASSIGN = re.compile(
    r"(?:^|[\s;&|({])(?:local\s+|export\s+|readonly\s+|declare\s+-\w+\s+)?(\w+)=(?:\"?\$\{?PPID\b|\$\(.*\bppid=|`.*\bppid=)"
)
PPID_USE = re.compile(r"\$\{?PPID\b|\bps\b[^;|&)]*\bppid=")
TARGET_VAR = re.compile(r"^\$\{?(\w+)\}?$")
CMP = re.compile(r"(?:^|\s)(?:!=|==|=~|=|-ne|-eq)(?:\s|$)|\[\[?\s+-[nz]\s")
EXIT_WORD = re.compile(r"\b(?:exit|break|return)\b")
LOOP_WORD = re.compile(r"\b(?:while|until)\b")
# Only lines that carry one of these can matter to a detector or a window: the rest are never analysed.
KEYS = ("kill", "PPID", "ppid", "PPid", "/proc/", TOKEN)
NOT_A_BOUND = re.compile(r"^\s*(?:echo|printf|print|cat|:)\b")


class Unresolved(Exception):
    """The scan could not produce a verdict (rc 3)."""


Finding = collections.namedtuple("Finding", "path cls text bounded lineno")


def normalise(text):
    return " ".join(text.split())


def analyse(line):
    """Return (code, masked): code is the line cut at an unquoted comment start; masked is code with the
    contents of quoted spans blanked (same length, so indexes map between the two)."""
    code = []
    masked = []
    quote = None
    i = 0
    n = len(line)
    while i < n:
        c = line[i]
        if quote is None:
            if c == "\\" and i + 1 < n:
                code.append(line[i:i + 2])
                masked.append(line[i:i + 2])
                i += 2
                continue
            if c == "#" and (i == 0 or line[i - 1].isspace() or line[i - 1] in ";&|"):
                break
            if c == "'" or c == '"':
                quote = c
            code.append(c)
            masked.append(c)
        else:
            if quote == '"' and c == "\\" and i + 1 < n:
                code.append(line[i:i + 2])
                masked.append("  ")
                i += 2
                continue
            if c == quote:
                quote = None
                code.append(c)
                masked.append(c)
            else:
                code.append(c)
                masked.append(" ")
        i += 1
    return "".join(code), "".join(masked)


def arg_tokens(code, masked, start):
    """The tokens after a verb, cut at the next unquoted terminator or redirection."""
    end = len(masked)
    for j in range(start, len(masked)):
        if masked[j] in ";&|)}`<>":
            end = j
            break
    toks = []
    for raw in code[start:end].split():
        toks.append(raw.strip("'\""))
    return toks


def classify_kill(toks, derived_vars):
    """The class of one kill invocation, or None (a probe, a listing, or a plain pid)."""
    if not toks:
        return None
    first = toks[0]
    i = 0
    if first in ("-l", "-L", "--list", "--table"):
        return None
    if first in ("-s", "-n", "--signal"):
        if len(toks) < 2:
            return None
        if toks[1] == "0":
            return None
        i = 2
    elif first == "-0":
        return None
    elif first.startswith("-") and first != "--":
        i = 1
    if i < len(toks) and toks[i] == "--":
        i += 1
    targets = toks[i:]
    if PPID_USE.search(" ".join(toks)):
        return "P"
    kind = None
    for t in targets:
        if t in ("0", "-1"):
            return "G"
        m = TARGET_VAR.match(t)
        if m and m.group(1) in derived_vars:
            return "P"
        if t.startswith("-") and kind is None:
            kind = "L"
    return kind


def is_bound_line(code):
    if TOKEN not in code or NOT_A_BOUND.match(code):
        return False
    if not CMP.search(code):
        return False
    return bool(EXIT_WORD.search(code) or LOOP_WORD.search(code))


def scan_text(path, text, counters):
    lines = [ln.rstrip("\r") for ln in text.split("\n")]
    counters["overlong"] += sum(1 for ln in lines if len(ln) > MAX_LINE)
    findings = []
    if "kill" not in text:
        return findings
    n = len(lines)
    code = [""] * n
    masked = [""] * n
    for i, ln in enumerate(lines):
        if len(ln) > MAX_LINE:
            if LOOSE_SIGNAL.search(ln):
                head = normalise(ln[:200])[:100]
                findings.append(Finding(path, "G", "<overlong line, %d chars, carries a signal verb> %s" % (len(ln), head), "-", i + 1))
            continue
        if not any(k in ln for k in KEYS):
            continue
        if ln.lstrip().startswith("#"):
            continue
        code[i], masked[i] = analyse(ln)

    assigns = collections.defaultdict(list)
    for i in range(n):
        if "PPID" in code[i] or "ppid=" in code[i]:
            for m in PPID_ASSIGN.finditer(code[i]):
                assigns[m.group(1)].append(i)

    for i in range(n):
        if not code[i]:
            continue
        # signal verbs at command position
        for m in CMDPOS.finditer(masked[i]):
            verb = m.group(1)
            toks = arg_tokens(code[i], masked[i], m.end())
            if verb in ("pkill", "killall"):
                cls = "L"
            else:
                derived = {v for v, idxs in assigns.items() if any(i - DERIVED_WINDOW <= j <= i for j in idxs)}
                cls = classify_kill(toks, derived)
            if cls:
                findings.append(Finding(path, cls, normalise(code[i]), "-", i + 1))
        # W cursor: a self-referential assignment, with a signal nearby
        if ("/proc/" in code[i] or "ppid" in code[i].lower()) and ("=$(" in code[i] or "=`" in code[i]):
            for m in CURSOR.finditer(code[i]):
                v = m.group(1)
                tail = code[i][m.end():]
                ref = re.compile(r"\$\{?%s\b" % re.escape(v))
                form1 = re.search(r"/proc/\$\{?%s\}?/(?:stat|status)" % re.escape(v), tail)
                form2 = re.search(r"\bps\b", tail) and re.search(r"ppid", tail) and ref.search(tail)
                form3 = "PPid" in tail and ref.search(tail)
                if not (form1 or form2 or form3):
                    continue
                lo = max(0, i - KILL_WINDOW)
                hi = min(n, i + KILL_WINDOW + 1)
                if not any(code[j] and LOOSE_SIGNAL.search(code[j]) for j in range(lo, hi)):
                    continue
                blo = max(0, i - BOUND_ABOVE)
                bhi = min(n, i + BOUND_BELOW + 1)
                bounded = "yes" if any(is_bound_line(code[j]) for j in range(blo, bhi)) else "no"
                findings.append(Finding(path, "W", normalise(code[i]), bounded, i + 1))
                break
    findings.sort(key=lambda f: (f.lineno, f.cls))
    return findings


def git_population(root):
    env = {k: v for k, v in os.environ.items() if not k.startswith("GIT_")}
    cmd = ["git", "-C", root, "ls-files", "-z", "--"] + PATHSPECS
    try:
        cp = subprocess.run(cmd, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=120)
    except (OSError, subprocess.SubprocessError) as exc:
        raise Unresolved("git listing failed: %s" % exc)
    if cp.returncode != 0:
        msg = cp.stderr.decode("utf-8", "replace").strip().splitlines()
        raise Unresolved("git listing failed (rc %d): %s" % (cp.returncode, msg[0] if msg else "no message"))
    names = sorted({os.fsdecode(p) for p in cp.stdout.split(b"\0") if p})
    if not names:
        raise Unresolved("the producer returned no files (no tracked *.test.sh or test-*.sh under %s)" % root)
    return names


def read_member(display, full, counters):
    try:
        st = os.lstat(full)
    except OSError as exc:
        raise Unresolved("listed member cannot be read: %s (%s)" % (display, exc.strerror))
    if not stat.S_ISREG(st.st_mode):
        counters["skipped"] += 1
        return None
    if st.st_size > MAX_FILE:
        counters["skipped"] += 1
        return None
    try:
        with open(full, "rb") as fh:
            data = fh.read()
    except OSError as exc:
        raise Unresolved("listed member cannot be read: %s (%s)" % (display, exc.strerror))
    return data.decode("utf-8", "surrogateescape")


def read_baseline(path):
    rows = collections.Counter()
    try:
        with open(path, "rb") as fh:
            raw = fh.read().decode("utf-8", "surrogateescape")
    except OSError as exc:
        raise Unresolved("baseline unreadable: %s (%s)" % (path, exc.strerror))
    for n, ln in enumerate(raw.split("\n"), 1):
        ln = ln.rstrip("\r")
        if not ln.strip() or ln.startswith("#"):
            continue
        parts = ln.split("\t")
        if len(parts) != 3 or parts[1] not in GATED or not parts[0]:
            raise Unresolved("baseline row %d is malformed (want path TAB class TAB text, class W/P/G): %s" % (n, path))
        rows[(parts[0], parts[1], parts[2])] += 1
    return rows


BASELINE_HEADER = """\
# ancestor-signal baseline: one row per gated finding, <path> TAB <class> TAB <normalised line>.
# Classes: W ancestor walk that signals (must read bounded=yes), P signal to the parent, G all-process signal.
# Maintenance: an in-place replacement of an existing row (same path and class, e.g. after an unrelated edit of
# that line) is allowed; a net addition needs a reviewer's read; otherwise the file may only shrink. A stale row
# (no live line) and an unbounded W are red. bounded=yes is LEXICAL (a non-comment SOLEUR_TEST_SUITE_PID
# comparison with exit, break or return near the walk), not proof of containment.
# Regenerate: python3 plugins/soleur/scripts/scan-ancestor-signal-helpers.py --write-baseline <this file>
# (overwrites the whole file: review the diff row by row).
"""

REMEDY = (
    "remedy: new W: bound the walk with a non-comment test such as [ \"$p\" = \"$SOLEUR_TEST_SUITE_PID\" ] plus exit, break or return "
    "on that line, then add one baseline row ($$ comparisons read bounded=no). "
    "new P or G: rewrite to a nonce-scoped target, or baseline it with a reviewer's read. "
    "stale: delete or swap the row. unbounded: bounding is mandatory, baselining is refused. "
    "--write-baseline overwrites the whole file, so review the diff; untracked files are not scanned "
    "(the producer lists tracked files: git add first). See the section 'Mutating a signalling or "
    "file-removing helper' in plugins/soleur/skills/work/references/work-scratch-sandboxes.md."
)


def out(msg=""):
    sys.stdout.write(msg + "\n")


def run(argv):
    ap = argparse.ArgumentParser(prog="scan-ancestor-signal-helpers.py", description="Inventory of signal helpers in shell test suites.")
    ap.add_argument("--root", default=".", help="repository root for the tracked-file listing (default: the current directory)")
    ap.add_argument("--baseline", help="baseline file; without it the scan is list-only")
    ap.add_argument("--list", action="store_true", help="print every finding of every class and exit 0")
    ap.add_argument("--write-baseline", metavar="FILE", help="write the gated rows to FILE")
    ap.add_argument("paths", nargs="*", metavar="PATH", help="scan these files instead of the tracked listing")
    args = ap.parse_args(argv)

    counters = collections.Counter()
    explicit = bool(args.paths)
    names = list(args.paths) if explicit else git_population(args.root)

    findings = []
    roots = set()
    nfiles = 0
    for name in names:
        full = name if explicit else os.path.join(args.root, name)
        text = read_member(name, full, counters)
        if text is None:
            continue
        nfiles += 1
        if "/" in name:
            roots.add(name.split("/", 1)[0])
        findings.extend(scan_text(name, text, counters))
    findings.sort(key=lambda f: (f.path, f.lineno, f.cls))

    gated = [f for f in findings if f.cls in GATED]
    listed = [f for f in findings if f.cls == "L"]
    skipped = counters["skipped"]

    if args.write_baseline:
        bad = [f for f in gated if f.cls == "W" and f.bounded == "no"]
        if bad:
            for f in bad:
                out("UNBOUNDED W %s:%d: %s" % (f.path, f.lineno, f.text))
            out("ancestor-signal scan: refusing to write a baseline that certifies an unbounded walker (UNBOUNDED above)")
            out("ancestor-signal scan: " + REMEDY)
            return 1
        rows = sorted((f.path, f.cls, f.text) for f in gated)
        tmp = args.write_baseline + ".tmp-%d" % os.getpid()
        with open(tmp, "wb") as fh:
            fh.write(BASELINE_HEADER.encode("utf-8", "surrogateescape"))
            for r in rows:
                fh.write(("\t".join(r) + "\n").encode("utf-8", "surrogateescape"))
        os.replace(tmp, args.write_baseline)
        out("ancestor-signal scan: wrote %d baseline rows to %s" % (len(rows), args.write_baseline))
        return 0

    if args.list or not args.baseline:
        for f in findings:
            out("\t".join((f.cls, f.bounded, f.path, f.text)))
        if counters["overlong"]:
            out("ancestor-signal scan: overlong lines: %d" % counters["overlong"])
        out("ancestor-signal scan: roots: %s" % " ".join(sorted(roots)))
        out("ancestor-signal scan: %d files, %d findings, no baseline: listing only, %d skipped" % (nfiles, len(findings), skipped))
        return 0

    base = read_baseline(args.baseline)
    live = collections.Counter((f.path, f.cls, f.text) for f in gated)
    if explicit:
        scanned = set(names)
        base = collections.Counter({k: v for k, v in base.items() if k[0] in scanned})
    matched = sum((live & base).values())
    new = live - base
    stale = base - live
    unbounded = [f for f in gated if f.cls == "W" and f.bounded == "no"]

    seen = collections.Counter()
    for f in gated:
        key = (f.path, f.cls, f.text)
        seen[key] += 1
        if seen[key] > matched_of(base, key):
            out("NEW %s %s:%d: %s" % (f.cls, f.path, f.lineno, f.text))
            out("  row: %s" % "\t".join(key))
    for key, cnt in sorted(stale.items()):
        for _ in range(cnt):
            out("STALE %s %s: %s" % (key[1], key[0], key[2]))
    for f in unbounded:
        out("UNBOUNDED W %s:%d: %s" % (f.path, f.lineno, f.text))
    red = bool(new or stale or unbounded)

    if counters["overlong"]:
        out("ancestor-signal scan: overlong lines: %d" % counters["overlong"])
    out("ancestor-signal scan: listed-only (class L): %d" % len(listed))
    out("ancestor-signal scan: roots: %s" % " ".join(sorted(roots)))
    out("ancestor-signal scan: %d files, %d findings, %d baselined, %d new, %d stale, %d unbounded, %d skipped" % (
        nfiles, len(gated), matched, sum(new.values()), sum(stale.values()), len(unbounded), skipped))
    if red:
        out("ancestor-signal scan: " + REMEDY)
        return 1
    out("ancestor-signal scan: CLEAN")
    return 0


def matched_of(base, key):
    return base.get(key, 0)


def main():
    try:
        try:
            sys.stdout.reconfigure(errors="surrogateescape")
            sys.stderr.reconfigure(errors="surrogateescape")
        except AttributeError:
            pass
        rc = run(sys.argv[1:])
        sys.stdout.flush()
        return rc
    except SystemExit:
        raise
    except Unresolved as exc:
        sys.stderr.write("ancestor-signal scan: UNRESOLVED: %s\n" % exc)
        sys.stderr.flush()
        os._exit(3)
    except BaseException as exc:  # an uncaught exception must read as rc 3, never as rc 1 "findings"
        try:
            import traceback
            traceback.print_exc()
            sys.stderr.write("ancestor-signal scan: UNRESOLVED: uncaught %s: %s\n" % (type(exc).__name__, exc))
            sys.stderr.flush()
        finally:
            os._exit(3)


if __name__ == "__main__":
    sys.exit(main())
