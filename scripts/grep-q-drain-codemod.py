#!/usr/bin/env python3
"""Mechanical `grep -q` -> `grep -c ... >/dev/null` rewrite for the sigpipe sweep (#9217, Wave B).

`<producer> | grep -q<flags> ARGS` becomes `<producer> | grep -c<flags> >/dev/null ARGS`: the early-exit letter
`q` becomes `c` and one redirect is inserted right after the flag cluster. `grep -c` exits 0 iff a line was
selected, exactly like `grep -q`, but it reads its whole input, so the producer never takes SIGPIPE under
`set -o pipefail`. The form is valid in /bin/sh.

Two modes, one transform function:

  apply   dry run by default: prints per-row and per-tier counts and the hand queue (`QUEUE path:line:tier:reason`).
          `--write` edits the files. One line in, one line out, idempotent.
  verify  `verify --base REF --hand-edits FILE`: proves a slice's diff is ONLY this transform plus an enumerated
          hand-edit list, judged line by line (adjacent changed lines share one diff hunk, so the hunk is not the
          unit). A listed range must cover only hand-edited lines; a hunk that changes the line count must be listed
          with exactly its removed range. The scope is the BASE guard's rows and pathspec. It proves the TRANSFORM,
          not the classification: a data line converted by mistake still equals transform(removed) and passes, so
          classification is held by the printed queue, the demonstration-suspect rule and a per-suite pair run.

The population is the guard's own: this tool sources the guard's SWEEP_* strings (so it cannot disagree with
the guard about what a site is), runs `git grep --no-index --column -o` with the guard's pathspec, and edits
exactly the matched span.

Tiers (printed with a reason): T0 convertible; H-m `-m`/`--max-count` (output-bearing, still an early exit);
X refused (operand-q cluster, unbounded producer, redirected stdout, unknown letter); data (the match sits in a
quoted string or a heredoc body); suspect (the file names sigpipe/EPIPE/false-FAIL/broken pipe, so a
demonstration may be what the line is); unsure (the bash tokenizer did not balance, so nothing in the file is
trusted). Exit codes: 0 ok, 1 verify failure, 2 usage, 3 UNRESOLVED (nothing was measured).
"""
import argparse
import fnmatch
import itertools
import os
import re
import subprocess
import sys
import tempfile

GUARD = ".claude/hooks/grep-q-pipe-guard.test.sh"
SUSPECT_RE = re.compile(r"sigpipe|epipe|false-?fail|broken pipe", re.I)
UNBOUNDED_RE = re.compile(
    r"(^|[^\w./-])(yes|journalctl|ncat|nc|socat|sleep|timeout|inotifywait)(\s|$)"
    r"|tail\s+-[A-Za-z]*[fF]|docker\s+logs|while\s+(true|:)|/dev/(zero|urandom|random)"
)
SAFE_LETTERS = set("iEFGwxvsazIyP")   # letters whose exit-status behaviour -c leaves unchanged
OPERAND_LETTERS = set("efABCdD")      # letters that take an operand (the rest of the token, or the next token)


def die(code, msg):
    print(msg, file=sys.stderr)
    sys.exit(code)


def sh(args, cwd=None, check=True):
    # a hook runs with GIT_DIR/GIT_INDEX_FILE set, which would retarget every git call below: strip GIT_* by prefix
    env = {k: v for k, v in os.environ.items() if not k.startswith("GIT_")}
    r = subprocess.run(args, cwd=cwd, capture_output=True, env=env)
    if check and r.returncode != 0:
        die(3, "UNRESOLVED: %s exited %d: %s" % (args[:3], r.returncode, r.stderr.decode("latin-1")[:300]))
    return r


# --------------------------------------------------------------------------------------------- guard sourcing
def load_guard(guard_path):
    """-> (PATTERN_V2, pathspec list, ALLOW_MARKER regex, SWEEP_DEFERRALS rows). Bash evaluates the guard's own lines."""
    script = r'''
set -u
g=$1
eval "$(grep -E '^SWEEP_(LEAD|WRAP|BIN|ARG|EARLY)=' "$g")"
eval "$(grep -E '^PATTERN_V2=' "$g")"
eval "$(grep -E '^ALLOW_MARKER=' "$g")"
eval "$(awk '/^SWEEP_PATHSPEC=\(/,/^\)/' "$g")"
eval "$(awk '/^SWEEP_DEFERRALS=\(/,/^\)/' "$g")"
printf '%s\0' "$PATTERN_V2" "$ALLOW_MARKER" "${#SWEEP_PATHSPEC[@]}" "${SWEEP_PATHSPEC[@]}" "${SWEEP_DEFERRALS[@]}"
'''
    r = sh(["bash", "-c", script, "_", guard_path])
    parts = r.stdout.decode("latin-1").split("\0")[:-1]
    if len(parts) < 4 or not parts[0] or not parts[2].isdigit():
        die(3, "UNRESOLVED: could not read the guard's SWEEP_* assignments from %s" % guard_path)
    n = int(parts[2])
    pathspec = parts[3:3 + n]
    rows = parts[3 + n:]
    marker = re.compile(parts[1].replace("[[:space:]]", r"\s"))
    if not pathspec or not rows:
        die(3, "UNRESOLVED: the guard yielded an empty pathspec or deferral table")
    return parts[0], pathspec, marker, rows


def row_globs(rows):
    out = []
    for row in rows:
        g = row.split("|")[0].strip()
        out.append(g)
    return out


def owner_of(path, globs):
    for g in globs:
        if fnmatch.fnmatchcase(path, g):
            return g
    return None


# ------------------------------------------------------------------------------------------ population (git grep)
def population(root, pattern, pathspec, marker):
    """-> {path: {line_no: [(col0, span), ...]}} with the guard's comment and marker filters applied."""
    cmd = ["git", "-c", "core.excludesFile=/dev/null", "-C", root, "grep", "--no-index", "--exclude-standard",
           "-a", "-n", "-E", "--column", "-o", "-e", pattern, "--"] + pathspec
    r = sh(cmd, check=False)
    if r.returncode > 1:
        die(3, "UNRESOLVED: git grep exited %d: %s" % (r.returncode, r.stderr.decode("latin-1")[:300]))
    pop = {}
    for raw in r.stdout.decode("latin-1").splitlines():
        m = re.match(r"^(.*?):(\d+):(\d+):(.*)$", raw)
        if not m:
            continue
        path, ln, col, span = m.group(1), int(m.group(2)), int(m.group(3)), m.group(4)
        pop.setdefault(path, {}).setdefault(ln, []).append((col - 1, span))
    # comment-only lines and marked lines are dropped, exactly as the guard's _strip_comments --marker does
    for path in list(pop):
        with open(os.path.join(root, path), "rb") as f:
            lines = f.read().decode("latin-1").split("\n")
        for ln in list(pop[path]):
            text = lines[ln - 1] if ln - 1 < len(lines) else ""
            if re.match(r"^\s*#", text) or marker.search(text):
                del pop[path][ln]
        if not pop[path]:
            del pop[path]
    return pop


# ------------------------------------------------------------------------------------------------- bash tokenizer
class Frame:
    __slots__ = ("kind", "closer", "code", "pos")

    def __init__(self, kind, closer, code, pos=0):
        self.kind, self.closer, self.code, self.pos = kind, closer, code, pos


def classify(text):
    """-> (kinds, ok). kinds[i] is 'c' code, 'q' quoted string, 'h' heredoc body, 'm' comment. ok False when the
    scan did not end balanced; the caller then trusts nothing in the file."""
    n = len(text)
    kinds = ["c"] * n
    stack = [Frame("base", None, True)]
    pending = []   # (delimiter, strip_tabs) heredocs waiting for the end of the line
    i = 0

    def mark(a, b, k):
        for j in range(a, min(b, n)):
            kinds[j] = k

    def arith_open():
        return any(f.kind == "arith" for f in stack)

    while i < n:
        top = stack[-1]
        ch = text[i]
        if top.kind == "sq":
            kinds[i] = "q"
            if ch == "'":
                stack.pop()
            i += 1
            continue
        if top.kind == "ansi":
            kinds[i] = "q"
            if ch == "\\":
                mark(i, i + 2, "q")
                i += 2
                continue
            if ch == "'":
                stack.pop()
            i += 1
            continue
        if top.kind == "dq":
            kinds[i] = "q"
            if ch == "\\":
                mark(i, i + 2, "q")
                i += 2
                continue
            if ch == '"':
                stack.pop()
                i += 1
                continue
            if text.startswith("$(", i):
                mark(i, i + 2, "q")
                stack.append(Frame("cmdsub", ")", True, i))
                i += 2
                continue
            if text.startswith("${", i):
                mark(i, i + 2, "q")
                stack.append(Frame("param", "}", False, i))
                i += 2
                continue
            if ch == "`":
                kinds[i] = "q"
                stack.append(Frame("bq", "`", True, i))
                i += 1
                continue
            i += 1
            continue
        # code-like frames: base, cmdsub, paren, arith, param, bq
        kinds[i] = "c" if top.code else "q"
        if ch == "\\":
            mark(i, i + 2, "c" if top.code else "q")
            i += 2
            continue
        if ch == "\n":
            i += 1
            if pending:
                for delim, strip in pending:
                    while i < n:
                        eol = text.find("\n", i)
                        eol = n if eol < 0 else eol
                        line = text[i:eol]
                        mark(i, min(eol + 1, n), "h")
                        i = eol + 1
                        if (line.lstrip("\t") if strip else line) == delim:
                            break
                pending = []
            continue
        if top.closer is not None and ch == top.closer:
            stack.pop()
            i += 1
            continue
        if ch == "'":
            stack.append(Frame("sq", "'", False, i))
            kinds[i] = "q"
            i += 1
            continue
        if ch == '"':
            stack.append(Frame("dq", '"', False, i))
            kinds[i] = "q"
            i += 1
            continue
        if text.startswith("$'", i):
            stack.append(Frame("ansi", "'", False, i))
            mark(i, i + 2, "q")
            i += 2
            continue
        if text.startswith("$((", i):
            stack.append(Frame("arith", ")", top.code, i))
            stack.append(Frame("arith", ")", top.code, i))
            i += 3
            continue
        if text.startswith("$(", i):
            stack.append(Frame("cmdsub", ")", True, i))
            i += 2
            continue
        if text.startswith("${", i):
            stack.append(Frame("param", "}", top.code, i))
            i += 2
            continue
        if ch == "(" and top.kind != "param":
            stack.append(Frame("paren", ")", top.code, i))
            i += 1
            continue
        if ch == "`":
            stack.append(Frame("bq", "`", True, i))
            i += 1
            continue
        if ch == "#" and top.kind != "param":
            prev = text[i - 1] if i else "\n"
            if prev in " \t\n;&|(" and prev != "$":
                eol = text.find("\n", i)
                eol = n if eol < 0 else eol
                mark(i, eol, "m")
                i = eol
                continue
        if text.startswith("<<<", i):
            i += 3
            continue
        if text.startswith("<<", i) and not arith_open() and top.kind in ("base", "cmdsub", "paren", "bq"):
            j = i + 2
            strip = False
            if j < n and text[j] == "-":
                strip = True
                j += 1
            while j < n and text[j] in " \t":
                j += 1
            m = re.match(r"""(?:'([^'\n]*)'|"([^"\n]*)"|([^\s;&|()<>]+))""", text[j:])
            if m:
                delim = m.group(1) if m.group(1) is not None else (m.group(2) if m.group(2) is not None else m.group(3))
                pending.append((delim.replace("\\", ""), strip))
                i = j + m.end()
                continue
        i += 1
    ok = len(stack) == 1 and not pending
    classify.last_open = [(f.kind, f.pos) for f in stack[1:]]
    return kinds, ok


# ------------------------------------------------------------------------------------------- span transform
def parse_span(span):
    """-> ('T0', new_cluster_token_replacement) or (tier, reason). Looks only at the matched span."""
    toks = span.split()
    bi = None
    for k, t in enumerate(toks):
        if re.fullmatch(r"(\\|/\S*/)?(e|f)?grep", t):
            bi = k
            break
    if bi is None:
        return "X", "bin-not-found"
    flags = toks[bi + 1:]
    if not flags:
        return "X", "no-flags"
    last = flags[-1]
    # earlier tokens: -m anywhere is an output-bearing early exit; operand letters swallow the next token
    k = 0
    while k < len(flags) - 1:
        t = flags[k]
        if t.startswith("--"):
            if t.startswith("--max-count"):
                return "H-m", "max-count"
            k += 1
            continue
        if re.fullmatch(r"-[efABCm]", t):
            if t == "-m":
                return "H-m", "-m"
            k += 2
            continue
        letters = t[1:]
        for p, c in enumerate(letters):
            if c == "m":
                return "H-m", "-m"
            if c in OPERAND_LETTERS:
                break
            if c not in SAFE_LETTERS and c not in "0123456789":
                return "X", "letter-%s" % c
        k += 1
    if k != len(flags) - 1:
        return "X", "operand-q"   # the last token was consumed as an operand: the early flag is not a flag
    if last in ("--quiet", "--silent"):
        return "T0", ("long", last)
    if last.startswith("--max-count"):
        return "H-m", "max-count"
    if not re.fullmatch(r"-[A-Za-z0-9]+", last):
        return "X", "unparsed-token"
    letters = last[1:]
    qpos = None
    for p, c in enumerate(letters):
        if c == "m":
            return "H-m", "-m"
        if c == "q":
            qpos = p if qpos is None else qpos
            continue
        if c in OPERAND_LETTERS:
            if qpos is None:
                return "X", "operand-q"   # -eq is -e with the pattern q
            break
        if c in "0123456789":
            continue
        if c not in SAFE_LETTERS:
            return "X", "letter-%s" % c
    if qpos is None:
        return "X", "no-q"
    return "T0", ("short", qpos)


def rewrite_span_token(line, abs_start, span, how):
    """-> the line with the early token rewritten and the redirect inserted, or None if the span does not line up."""
    end = abs_start + len(span)
    tok_start = max(line.rfind(" ", abs_start, end), line.rfind("\t", abs_start, end)) + 1
    if tok_start <= abs_start:
        return None
    tok = line[tok_start:end]
    if how[0] == "long":
        if tok != how[1]:
            return None
        new = "-c"
    else:
        qpos = how[1]
        if len(tok) < 2 or tok[0] != "-" or tok[1 + qpos] != "q":
            return None
        new = tok[:1 + qpos] + "c" + tok[2 + qpos:]
    return line[:tok_start] + new + " >/dev/null" + line[end:]


def stdout_redirected(line, kinds, base, end):
    """True when a code-context `>` (not `2>`..`9>`) follows the span before the command ends on this line."""
    p = end
    while p < len(line):
        c = line[p]
        k = kinds[base + p] if base + p < len(kinds) else "c"
        if k == "c":
            if c in "|;)" or line.startswith("&&", p) or line.startswith("<<", p):
                return False
            if c == ">":
                prev = line[p - 1] if p > 0 else " "
                if not (prev in "23456789" and (p < 2 or line[p - 2] in " \t")):
                    return True
        p += 1
    return False


def producer_text(lines, idx, abs_start):
    head = lines[idx][:abs_start]
    if head.strip(" \t&|(") == "" and idx > 0:
        return lines[idx - 1] + " " + head
    return head


def convert_line(line, hits, decide):
    """Apply decided hits right to left. decide(col0, span) -> ('T0', how) | (tier, reason). Returns (newline, report)."""
    report = []
    out = line
    for col0, span in sorted(hits, reverse=True):
        verdict = decide(col0, span)
        if verdict[0] != "T0":
            report.append((col0, verdict[0], verdict[1]))
            continue
        res = rewrite_span_token(out, col0, span, verdict[1])
        if res is None:
            report.append((col0, "X", "span-mismatch"))
            continue
        out = res
        report.append((col0, "T0", ""))
    return out, report


# --------------------------------------------------------------------------------------------------- apply mode
def select_rows(args, globs):
    if not args.row:
        return globs
    missing = [g for g in args.row if g not in globs]
    if missing:
        die(2, "usage: --row %s is not a row of the guard's SWEEP_DEFERRALS" % missing[0])
    return args.row


def do_apply(args):
    root = os.path.abspath(args.root)
    pattern, pathspec, marker, rows = load_guard(os.path.join(root, GUARD) if os.path.exists(os.path.join(root, GUARD)) else args.guard)
    globs = row_globs(rows)
    wanted = set(select_rows(args, globs))
    pop = population(root, pattern, pathspec, marker)
    total_lines = sum(len(v) for v in pop.values())
    if total_lines == 0:
        die(3, "UNRESOLVED: the guard's pattern found no site under %s; nothing was measured" % root)
    reviewed = set(args.reviewed_suspect)
    per_row = {}
    queue = []
    changed_lines = 0
    changed_files = 0
    tiers = {}

    def bump(row, tier):
        per_row.setdefault(row, {}).setdefault(tier, 0)
        per_row[row][tier] += 1
        tiers[tier] = tiers.get(tier, 0) + 1

    for path in sorted(pop):
        row = owner_of(path, globs)
        if row not in wanted or path in args.exclude:
            continue
        with open(os.path.join(root, path), "rb") as f:
            text = f.read().decode("latin-1")
        lines = text.split("\n")
        starts = [0]
        for ln in lines[:-1]:
            starts.append(starts[-1] + len(ln) + 1)
        kinds, ok = classify(text)
        suspect = bool(SUSPECT_RE.search(text)) and path not in reviewed
        file_changed = False
        for ln in sorted(pop[path]):
            idx = ln - 1
            line = lines[idx]
            hits = pop[path][ln]

            def decide(col0, span, idx=idx, line=line):
                if not ok:
                    return "unsure", "tokenizer-unbalanced"
                kind = kinds[starts[idx] + col0 + span.index("|")] if "|" in span else "c"
                if kind != "c":
                    return "data", {"q": "quoted", "h": "heredoc", "m": "comment"}.get(kind, kind)
                if suspect:
                    return "suspect", "file-names-sigpipe"
                v = parse_span(span)
                if v[0] != "T0":
                    return v
                prod = producer_text(lines, idx, col0)
                if UNBOUNDED_RE.search(prod):
                    return "X", "unbounded-producer"
                if stdout_redirected(line, kinds, starts[idx], col0 + len(span)):
                    return "X", "stdout-redirected"
                return v

            new, report = convert_line(line, hits, decide)
            status = "T0"
            for col0, tier, reason in report:
                if tier != "T0":
                    status = tier
                    queue.append((path, ln, tier, reason))
            for col0, tier, reason in report:
                if tier == "T0":
                    bump(row, "T0")
                else:
                    bump(row, tier)
            if new != line:
                lines[idx] = new
                file_changed = True
                changed_lines += 1
        if file_changed and args.write:
            with open(os.path.join(root, path), "wb") as f:
                f.write("\n".join(lines).encode("latin-1"))
            changed_files += 1
        elif file_changed:
            changed_files += 1
    print("POPULATION: %d lines in %d files (the guard's own pattern, comment and marker lines dropped)" % (total_lines, len(pop)))
    for g in globs:
        if g in wanted and g in per_row:
            parts = " ".join("%s=%d" % (k, v) for k, v in sorted(per_row[g].items()))
            print("ROW %s %s" % (g, parts))
    print("SUMMARY %s" % (" ".join("%s=%d" % (k, v) for k, v in sorted(tiers.items())) or "none"))
    for path, ln, tier, reason in queue:
        print("QUEUE %s:%d:%s:%s" % (path, ln, tier, reason))
    verb = "CHANGED" if args.write else "WOULD-CHANGE"
    print("%s: %d lines in %d files" % (verb, changed_lines, changed_files))
    return 0


# -------------------------------------------------------------------------------------------------- verify mode
def transform_variants(line, spans):
    """All results of converting some subset of the line's convertible spans (right to left)."""
    conv = []
    for col0, span in spans:
        v = parse_span(span)
        if v[0] == "T0":
            conv.append((col0, span, v[1]))
    results = set()
    for r in range(1, min(len(conv), 6) + 1):
        for subset in itertools.combinations(conv, r):
            out = line
            okk = True
            for col0, span, how in sorted(subset, reverse=True):
                res = rewrite_span_token(out, col0, span, how)
                if res is None:
                    okk = False
                    break
                out = res
            if okk:
                results.add(out)
    return results


def do_verify(args):
    root = os.path.abspath(args.root)
    # the rows that scope a slice are the BASE guard's: the branch's guard has already deleted the rows this slice took to zero
    shown = sh(["git", "-C", root, "show", "%s:%s" % (args.base, GUARD)], check=False)
    guard_src = os.path.join(root, GUARD) if os.path.exists(os.path.join(root, GUARD)) else args.guard
    if shown.returncode == 0:
        tf = tempfile.NamedTemporaryFile(prefix="gq-base-guard-", suffix=".sh", dir="/var/tmp", delete=False)
        tf.write(shown.stdout)
        tf.close()
        guard_src = tf.name
    pattern, pathspec, marker, rows = load_guard(guard_src)
    if shown.returncode == 0:
        os.unlink(guard_src)
    globs = row_globs(rows)
    wanted = set(select_rows(args, globs))
    entries = []   # [path, raw range text, set(lines) or None for an insertion, used-lines set]
    if args.hand_edits:
        with open(args.hand_edits, "r", encoding="latin-1") as f:
            for raw in f:
                raw = raw.strip()
                if not raw or raw.startswith("#"):
                    continue
                m = re.match(r"^(.+?):(\d+)(?:-(\d+)|(\+))?:(.+)$", raw)
                if not m:
                    die(2, "usage: bad hand-edit entry %r (want path:OLD[-OLD2|+]:reason)" % raw)
                lo = int(m.group(2))
                hi = int(m.group(3)) if m.group(3) else lo
                text = "%d+" % lo if m.group(4) else (str(lo) if hi == lo else "%d-%d" % (lo, hi))
                entries.append([m.group(1), text, None if m.group(4) else set(range(lo, hi + 1)), set()])
    base = args.base
    if sh(["git", "-C", root, "rev-parse", "--verify", "--quiet", base + "^{commit}"], check=False).returncode != 0:
        die(3, "UNRESOLVED: base %r does not resolve to a commit; nothing was verified" % base)
    ns = sh(["git", "-C", root, "diff", "--name-status", "--no-renames", "--no-color", base]).stdout.decode("latin-1")
    # only files the guard's own pathspec sweeps are in scope (the guard file itself, this tool and docs are not)
    swept = set(sh(["git", "-C", root, "ls-files", "--"] + pathspec).stdout.decode("latin-1").split("\n"))
    files = []
    unexplained = []
    for raw in ns.splitlines():
        status, _, path = raw.partition("\t")
        row = owner_of(path, globs)
        if row not in wanted or path in args.exclude or path not in swept:
            continue
        if status != "M":
            unexplained.append("%s: status %s (only modifications of existing files are a transform)" % (path, status))
            continue
        files.append(path)

    def entry_for(path, line):
        for e in entries:
            if e[0] == path and e[2] is not None and line in e[2]:
                return e
        return None

    verified = 0
    hand_edited = 0
    for path in files:
        diff = sh(["git", "-C", root, "diff", "-U0", "--no-color", "--no-ext-diff", base, "--", path]).stdout.decode("latin-1")
        for h in re.split(r"^@@ ", diff, flags=re.M)[1:]:
            head, _, body = h.partition("\n")
            m = re.match(r"-(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@", head)
            if not m:
                unexplained.append("%s: unreadable hunk header %r" % (path, head))
                continue
            a = int(m.group(1))
            b = int(m.group(2)) if m.group(2) is not None else 1
            removed = [l[1:] for l in body.split("\n") if l.startswith("-")]
            added = [l[1:] for l in body.split("\n") if l.startswith("+")]
            if len(removed) != len(added) or not removed:
                # a hunk that changes the line count is a hand edit and must be listed with EXACTLY its removed range
                key = "%d+" % a if b == 0 else (str(a) if b == 1 else "%d-%d" % (a, a + b - 1))
                hit = [e for e in entries if e[0] == path and e[1] == key]
                if not hit:
                    unexplained.append("%s:%d: hunk changes the line count (%d removed, %d added) and is not a listed hand edit" % (path, a, len(removed), len(added)))
                    continue
                if hit[0][2] is not None:
                    hit[0][3].update(range(a, a + b))
                else:
                    hit[0][3].add(a)
                hand_edited += max(len(removed), len(added))
                continue
            # equal counts: judge line by line (adjacent changed lines share one hunk, so the hunk is not the unit)
            with tempfile.TemporaryDirectory(prefix="gq-verify-", dir="/var/tmp") as td:
                with open(os.path.join(td, "r.sh"), "wb") as f:
                    f.write(("\n".join(removed) + "\n").encode("latin-1"))
                r = sh(["git", "-C", td, "grep", "--no-index", "-a", "-n", "-E", "--column", "-o", "-e", pattern, "--", "r.sh"], check=False)
            spans = {}
            for raw in r.stdout.decode("latin-1").splitlines():
                mm = re.match(r"^r\.sh:(\d+):(\d+):(.*)$", raw)
                if mm:
                    spans.setdefault(int(mm.group(1)), []).append((int(mm.group(2)) - 1, mm.group(3)))
            for i, (rem, add) in enumerate(zip(removed, added)):
                ln = a + i
                e = entry_for(path, ln)
                if add in transform_variants(rem, spans.get(i + 1, [])):
                    if e is not None:
                        unexplained.append("%s:%d: hand-edit entry covers a line that is a plain transform (the entry is wider than the hand edit)" % (path, ln))
                    verified += 1
                elif e is not None:
                    e[3].add(ln)
                    hand_edited += 1
                else:
                    unexplained.append("%s:%d: added line is not the transform of its base line" % (path, ln))
    for path, text, lines_, used in entries:
        if lines_ is None:
            if not used:
                unexplained.append("%s:%s: stale hand-edit entry (no hunk inserts there)" % (path, text))
        elif not used:
            unexplained.append("%s:%s: stale hand-edit entry (no changed line falls in that range)" % (path, text))
        elif used != lines_:
            unexplained.append("%s:%s: hand-edit entry covers lines that are not hand edits: %s" % (path, text, ",".join(str(x) for x in sorted(lines_ - used))))
    print("verified: %d" % verified)
    print("hand-edited: %d" % hand_edited)
    for u in unexplained:
        print("UNEXPLAINED %s" % u)
    print("unexplained: %d" % len(unexplained))
    if unexplained:
        return 1
    if verified + hand_edited == 0:
        print("UNRESOLVED: nothing was verified (empty diff or no in-scope file changed)", file=sys.stderr)
        return 3
    return 0


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    sub = ap.add_subparsers(dest="mode", required=True)
    for name in ("apply", "verify"):
        p = sub.add_parser(name)
        p.add_argument("--root", default=".")
        p.add_argument("--guard", default=GUARD)
        p.add_argument("--row", action="append", default=[], help="restrict to this SWEEP_DEFERRALS glob (repeatable)")
        p.add_argument("--exclude", action="append", default=[], help="exact path to leave alone (repeatable)")
        if name == "apply":
            p.add_argument("--write", action="store_true")
            p.add_argument("--reviewed-suspect", action="append", default=[], help="a demonstration-suspect file a human has read")
        else:
            p.add_argument("--base", required=True)
            p.add_argument("--hand-edits")
    args = ap.parse_args()
    if args.mode == "apply":
        return do_apply(args)
    return do_verify(args)


if __name__ == "__main__":
    sys.exit(main())
