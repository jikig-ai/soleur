"""Shared shell-source scanner for the infra-config gates (#7104 PR-B review, D1/D3).

WHY THIS FILE EXISTS. Three hand-rolled mini-parsers shipped in this directory, each with its
own noise-stripping policy: the loop-depth scanner stripped comments and quotes but NOT `[[ ]]`
test spans, the allow-list sweep stripped all three, and the actuation sweep was a bare `grep`
that stripped nothing. The panel's D1 is the cost of that divergence, and it was executed rather
than argued: two balanced phantom lines

    for _n in 1; do :; done            # restores done_count == 1
    [[ $PHASE == done ]] || :          # depth 1 -> 0
    adjudicate_infra_config ... && break
    [[ $PHASE == do ]] || :            # rebalance

zero the depth at the assert and rebalance the file, restoring #6594's any-of-3 coin flip with
the suite reporting `132 passed, 0 failed`. Neither the positive control nor the balance check
protects: maxdepth reads HIGHER than baseline, and the phantoms are balanced by construction.

The fix is not "teach the loop scanner about `[[ ]]`" — that leaves three policies and repeats
the failure the next time one of them learns something the others do not. There is one
`strip_noise` here and every caller uses it.

WHAT IT DOES NOT DO. It is not a shell parser. It cannot see through `eval`, process
substitution, or a variable holding a command name — the last of which it reports as a hit
rather than pretending to resolve. Its contract is: over the code it CAN see, a token in command
position is reported, and anything it cannot classify is reported rather than skipped.
"""

import re

# ------------------------------------------------------------------------------------------
# THE ONE NOISE POLICY
# ------------------------------------------------------------------------------------------

def _blank(text, *, blank_quotes):
    """One tokenizer pass, two policies.

    Both stripping modes below come from THIS function rather than from two hand-rolled loops —
    that is the whole point of the consolidation. Quote state is tracked ACROSS lines, which is
    what stops a multi-line jq program from looking like code, and newlines are preserved inside
    every blanked span so line numbers and offsets survive unchanged.

    `blank_quotes=False` removes comments only. It exists because blanking quotes is exactly
    wrong for one question: a redirection target is usually quoted (`>> "$GITHUB_OUTPUT"`), so a
    detector run over quote-blanked text sees `>>` followed by nothing and walks forward into the
    next line. The awk/sed trampoline detectors need the same thing for the same reason — an awk
    program body lives inside a quoted span, so the allow list had removed the evidence before
    looking for it.
    """
    out, i, n, q = [], 0, len(text), None
    while i < n:
        c = text[i]
        if q is None:
            if c == '#':
                while i < n and text[i] != '\n':
                    out.append(' ')
                    i += 1
                continue
            if c in ('"', "'"):
                q = c
                out.append(' ' if blank_quotes else c)
                i += 1
                continue
            out.append(c)
            i += 1
        else:
            if c == '\\' and q == '"' and i + 1 < n:
                if blank_quotes:
                    # PRESERVE THE NEWLINE (#7546 review). This emitted two SPACES, so a
                    # backslash-newline (a line continuation inside a double-quoted string)
                    # destroyed a newline while preserving length -- and `loop_depth_map`
                    # keys `depth_at` by LINE NUMBER while its callers look up RAW line
                    # numbers, so every line below such a construct shifted and the D1 depth
                    # check read the wrong line. Measured: 33 of 163 infra/*.sh diverged.
                    out.append(' ' + ('\n' if text[i + 1] == '\n' else ' '))
                else:
                    out.append(text[i:i + 2])
                i += 2
                continue
            if c == q:
                q = None
                out.append(' ' if blank_quotes else c)
                i += 1
                continue
            if blank_quotes:
                out.append('\n' if c == '\n' else ' ')
            else:
                out.append(c)
            i += 1
    return ''.join(out)


def strip_comments(text):
    """Blank comments only, preserving quoted spans and all offsets."""
    return _blank(text, blank_quotes=False)


def strip_noise(text):
    """Blank comments, quoted spans, arithmetic and `[[ ]]` tests.

    `[[ ]]` is stripped for the same reason quotes are: a test span holds VALUES, not commands.
    A bare word inside one is a string being compared, so `[[ $PHASE == done ]]` contains no
    loop terminator and `[[ $x == terraform ]]` invokes nothing. The loop-depth scanner did not
    strip these, which is one half of D1.
    """
    s = _blank(text, blank_quotes=True)
    # NEWLINE-PRESERVING, like the `[[ ]]` substitution below (#7546 review). ' ' * len()
    # preserves LENGTH but flattens a MULTI-LINE $(( )) into spaces, breaking the
    # newline-position half of this module's stated invariant.
    s = re.sub(r'\$?\(\([^()]*\)\)',
               lambda m: re.sub(r'[^\n]', ' ', m.group(0)), s, flags=re.S)
    s = re.sub(r'\[\[.*?\]\]',
               lambda m: re.sub(r'[^\n]', ' ', m.group(0)), s, flags=re.S)
    return s


# ------------------------------------------------------------------------------------------
# COMMAND POSITION
# ------------------------------------------------------------------------------------------
#
# THE TOKEN CHARACTER CLASS IS THE D3 FIX. It required a leading `[A-Za-z_]`, so
# `/usr/bin/terraform` and `./push-infra-config.sh` matched NOTHING AT ALL — the sweep captured
# no token and therefore reported no hit, which is the worst possible failure for an allow-list:
# silence that reads as approval. Both forms are now captured and compared on their basename.
#
# `$VAR` in command position was the same shape one step further: `TF=terraform ; $TF apply`
# captured nothing. It cannot be resolved statically, so it is captured as the sentinel
# `$INDIRECT` and reported — an allow-list that cannot classify something must say so.
_CMD_PREFIX = r'(?:^|[\n;&|(){}`]|\$\(|\b(?:if|elif|then|else|do|while|until)\s|!\s*)\s*'
# `\.` LAST, and it is not cosmetic (#7546 review): `.` is the POSIX synonym for `source`,
# and the allow-list's own comment says `eval`, `source`, `.` and `command` are
# "DELIBERATELY ABSENT" from BUILTINS because each is an arbitrary-command trampoline.
# `source` was caught and `.` was not -- `[./][A-Za-z0-9_./-]+` requires at least one
# character after the dot, so a bare `. "$P"` captured NOTHING and read as approval.
CMD = re.compile(_CMD_PREFIX + r'((?:[A-Za-z_][A-Za-z0-9_.-]*|[./][A-Za-z0-9_./-]+|\.))(?=\s|$|;)', re.M)
CMD_INDIRECT = re.compile(_CMD_PREFIX + r'(\$\{?[A-Za-z_][A-Za-z0-9_]*\}?)(?=\s|$|;)', re.M)
# KEYWORD WRAPPERS (#7546 review). `time` and `coproc` are shell KEYWORDS, so they are
# allow-listed as tokens AND the command they wrap was never in command position:
# `time terraform apply` and `coproc terraform apply` were both measured MISSED. This
# cannot be fixed by adding them to _CMD_PREFIX, because `finditer` is NON-OVERLAPPING --
# the `^`-anchored match on `time` consumes it, so the prefix is gone by the time the next
# token is scanned. A separate pass is the honest fix. Note the 12-wrapper positive-control
# battery samples twelve wrappers that all work and omits exactly these two.
CMD_WRAPPED = re.compile(r'\b(?:time|coproc)\s+'
                         r'((?:[A-Za-z_][A-Za-z0-9_.-]*|[./][A-Za-z0-9_./-]+))(?=\s|$|;)', re.M)


def _line_of(text, pos):
    return text.count('\n', 0, pos) + 1


def raw_command_tokens(clean, *, include_indirect=True):
    """Yield (line, normalised_token, raw_token), sorted by position."""
    found = []
    for m in CMD.finditer(clean):
        raw = m.group(1)
        norm = raw.rsplit('/', 1)[-1] if '/' in raw else raw
        found.append((m.start(1), _line_of(clean, m.start(1)), norm, raw))
    if include_indirect:
        for m in CMD_INDIRECT.finditer(clean):
            found.append((m.start(1), _line_of(clean, m.start(1)), '$INDIRECT', m.group(1)))
    for m in CMD_WRAPPED.finditer(clean):
        raw = m.group(1)
        norm = raw.rsplit('/', 1)[-1] if '/' in raw else raw
        found.append((m.start(1), _line_of(clean, m.start(1)), norm, raw))
    found.sort()
    for _pos, line, norm, raw in found:
        yield line, norm, raw


# ------------------------------------------------------------------------------------------
# LOOP DEPTH
# ------------------------------------------------------------------------------------------

def loop_depth_map(text):
    """Return (depth_at_line, maxdepth, final_depth) for a shell source.

    `do`/`done` are counted ONLY in command position. The previous scanner matched them as bare
    words anywhere, so `echo done` decremented the counter and `[[ $PHASE == do ]]` incremented
    it — which is one half of D1. Command position is what makes a loop keyword a loop keyword.
    """
    clean = strip_noise(text)
    total_lines = clean.count('\n') + 1
    events = []
    for line, tok, _raw in raw_command_tokens(clean, include_indirect=False):
        if tok in ('do', 'done'):
            events.append((line, tok))

    depth_at = {}
    depth = 0
    maxdepth = 0
    ev = 0
    for i in range(1, total_lines + 1):
        depth_at[i] = depth          # depth as the line BEGINS
        while ev < len(events) and events[ev][0] == i:
            if events[ev][1] == 'do':
                depth += 1
                maxdepth = max(maxdepth, depth)
            else:
                depth -= 1
            ev += 1
    return depth_at, maxdepth, depth


# ------------------------------------------------------------------------------------------
# TRAMPOLINES INSIDE THE ALLOW LIST
# ------------------------------------------------------------------------------------------
#
# D3's sharpest finding: `awk` and `sed` are on the allow list as "pure text transforms", and
# both can execute arbitrary commands. Worse, `strip_noise` blanks quoted spans, so an awk
# program body is invisible BY CONSTRUCTION — the allow list was not merely failing to look, it
# had removed the thing to look at before looking.
#
# So these run over the RAW text. They are deliberately over-eager: `awk` and `sed` are allowed
# in this codebase for pure transforms, and a flagged false positive is a comment away from
# being resolved, whereas a missed `system()` is an arbitrary-command trampoline in a file whose
# entire contract is that it adjudicates and touches nothing.

# WIDENED (#7546 review). The original three alternatives covered system(), pipe-to-shell and
# `print |`, and MISSED four shapes that are equally arbitrary-command or arbitrary-write, all
# measured evading it: `awk -f prog.awk` (the whole program comes from a file this scanner never
# reads), `"cmd" | getline` (the reverse pipe direction -- execution, not output), `getline < cmd`,
# and awk's OWN redirect `print ... > "file"` / `printf ... > "file"` (a write with no shell
# redirection for the redirect detector to find, because the awk body lives inside a quoted span).
_AWK_EXEC = re.compile(r'''\bawk\b[^\n]*?(system\s*\(|\|\s*&?\s*["'](?:/bin/)?(?:ba|z|k|d)?sh["']|\bprint\s*\||-f\s+\S|\|\s*getline\b|\bgetline\s*<|\bprintf?\b[^\n]*?>\s*["'])''')
# WIDENED (#7546 review). `-i`/`--in-place` and the GNU `e` flag were covered; `sed -f prog.sed`
# (whole program from an unread file) and sed's own `w`/`W` write commands were not -- `w FILE`
# writes the pattern space to FILE, which is a write from a binary the allow list calls a "pure
# text transform".
_SED_EXEC = re.compile(r'''\bsed\b[^\n]*?(-i\b|--in-place|-f\s+\S|[;'"\s][wW]\s+[^\s;'"]+|s[^\n]*?/[a-zA-Z]*e[a-zA-Z]*(?:\s|;|$|["']))''')
# THE REDIRECTION OPERATOR, LOCATED IN QUOTE-BLANKED TEXT AND READ FROM THE RAW TEXT.
#
# Neither text alone works, and both failures were measured on the real files. Over
# quote-PRESERVING text the operator regex fires on `<absent>`, `<unset>`, `schema_version>=2`
# and a jq `($matched | length) > 1` — 30 phantom writes across two files that have none,
# because `>` is punctuation inside prose. Over quote-BLANKED text the target of
# `>> "$GITHUB_OUTPUT"` has been erased, so the detector reads forward and reports whatever it
# finds next.
#
# `_blank` preserves byte offsets exactly (every blanked character emits one space, and
# newlines survive), so the operator can be FOUND in the blanked text and its target READ from
# the original at the same offset. That is the whole reason the blanking is offset-preserving.
_REDIR_OP = re.compile(r'(?:^|[\s;|&)])[0-9]?>>?(?![&>])', re.M)
_REDIR_TARGET = re.compile(r'[ \t]*((?:"[^"\n]*"|\'[^\'\n]*\'|[^\s;|&)\n])+)')


def classify_redirect(target):
    """'devnull' | 'fd' | 'variable' | 'literal-path'.

    The three benign classes are separated from the one that matters so each caller can state
    its OWN policy instead of sharing a lowest common denominator: a pure adjudicator may write
    nothing at all, while the verify gate legitimately writes $GITHUB_OUTPUT and its own scratch
    file. A single shared verdict would have to permit the union, which permits the escape.
    """
    t = target.strip('"\'')
    if t.startswith('&'):
        return 'fd'
    if t == '/dev/null':
        return 'devnull'
    if t.startswith('$') or t.startswith('${'):
        return 'variable'
    return 'literal-path'


def find_trampolines(text):
    """Return [(line, kind, detail)] for execution/write escapes the allow list cannot see.

    Runs over COMMENT-STRIPPED, QUOTE-PRESERVING text. That is not an oversight: an awk program
    body lives inside a quoted span, so `strip_noise` blanks it and the allow list is blind to
    `awk 'BEGIN{system("terraform apply")}'` BY CONSTRUCTION — it had deleted the evidence before
    looking for it. Comments are still stripped so prose describing the prohibition is not a hit.
    """
    src = strip_comments(text)
    hits = []
    for m in _AWK_EXEC.finditer(src):
        hits.append((_line_of(src, m.start()), 'awk-exec',
                     'awk can execute here (%s) — system() and pipe-to-shell are arbitrary-command '
                     'trampolines, and awk is ON the allow list as a "pure text transform"'
                     % m.group(1).strip()))
    for m in _SED_EXEC.finditer(src):
        hits.append((_line_of(src, m.start()), 'sed-exec',
                     'sed writes or executes here (%s) — `-i` rewrites a file in place and the GNU '
                     '`e` flag executes the pattern space, and sed is ON the allow list'
                     % m.group(1).strip()))
    blanked = strip_noise(text)
    for m in _REDIR_OP.finditer(blanked):
        t = _REDIR_TARGET.match(text, m.end())
        if not t or not t.group(1):
            continue
        target = t.group(1)
        kind = classify_redirect(target)
        if kind in ('fd', 'devnull'):
            continue
        hits.append((_line_of(text, m.end()), 'redirect-' + kind,
                     'redirects to %s — shell redirection is a write and needs no command at all, '
                     'so no command-position allow list can see it' % target))
    hits.sort()
    return hits
