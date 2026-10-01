#!/usr/bin/env python3
"""Fail when a shell script captures a command whose non-zero exit is a NORMAL outcome.

WHY THIS EXISTS
---------------
`grep`, `diff`, `cmp` and friends use a non-zero exit to report a NEGATIVE ANSWER, not an
error. "No match" is exit 1. Under `set -e` that answer is indistinguishable from a crash,
so the script dies at the moment it asks a question it was designed to ask:

    count=$(grep -c 'pattern' "$file")     # no match -> grep exits 1 -> script DIES here
    if [ "$count" -eq 0 ]; then ...        # never reached

The assignment does not protect it: for a bare `x=$(cmd)` the exit status OF THE ASSIGNMENT
IS the exit status of the command substitution. That surprises people who read `x=$(...)` as
"store a value" rather than "run a command".

THE MEASURED CASE FOR A MECHANICAL GATE
---------------------------------------
This class hit THREE distinct times inside a single PR (#7332 / PR #7336), in three different
disguises, and TWICE while writing the fixes for the earlier instances:

  1. `x=$(cmd)` aborting under `set -e`.
  2. `grep ... | wc -l` aborting inside a NEWLY ADDED guard -- with `pipefail` on, the
     pipeline's status is grep's, so `| wc -l` does not launder it.
  3. `grep -c` printing `0` AND exiting 1, so `count=$(grep -c ...) || echo 0` yielded the
     two-line string `"0\n0"`. Here the `||` did suppress errexit -- and produced a WRONG
     VALUE instead of a dead script, which is the worse failure.

One root cause in all three: a command that legitimately exits non-zero, captured without
deciding what its exit status MEANS. Three comments were added over the same PR and the class
recurred anyway; per ADR-166, a recurring defect class that documentation has failed to stop
earns a `scripts/lint-*` gate.

RELATIONSHIP TO lint-workflow-errexit-capture.py -- SIBLING, NOT EXTENSION
--------------------------------------------------------------------------
That gate covers GitHub Actions `run:` blocks, where the runner injects `bash -e` before the
first line. It anchors on the READ (`rc=$?`, `${PIPESTATUS[n]}`) and its docstring records a
measurement worth repeating here: the naive rule "a command-substitution assignment is a
finding" was prototyped against the real tree and found only 2 of its 17 sites, because 9 were
bare commands followed by `rc=$?`.

That measurement is why this is a SEPARATE gate rather than a widened one. In shell scripts
the distribution is inverted -- the capture IS the idiom -- so the rule that was wrong there
is the one that is right here. Anchoring both classes on one regex would mean each covering
the other's blind spot badly. Two gates, two anchors, two calibrations.

WHY NOT shellcheck
------------------
SC2312 (`check-extra-masked-returns`) is opt-in, off by default, and aims at the opposite
problem -- a status being MASKED. It does not model "this specific command's non-zero exit is
a legitimate answer that the surrounding `set -e` will misread". shellcheck runs in this
repo's CI and flagged none of the three instances above.

THE RULE
--------
Under errexit, flag a command substitution whose command is in NONZERO_IS_AN_ANSWER, unless
the site explicitly decides what a non-zero exit means. Four finding classes:

  S1 (abort)       an unprotected capture -- the script dies on a normal answer.
  S2 (double-emit) a capture protected by `|| echo <literal>` where the command already
                   PRINTS a value on failure (`grep -c`). The guard fires ON TOP of the
                   command's own output and the variable gets two lines.
  S3 (dead read)   a status read (`rc=$?`, `rc="$?"`, `rc=${PIPESTATUS[n]}`,
                   `local rc=$?`, `declare -i rc=$?`) whose command already ran armed:
                   under `set -e` the command aborts BEFORE the read runs, so the read
                   can only ever see 0. Judged at the COMMAND's line, not the read's --
                   `cmd` then `set +e` then `rc=$?` is the mis-fix, not a fix.
  S3 (cont.)       the antecedent may also be a compound's closer: `fi`, `done`,
                   `esac`, or a group `}`/`);` is reclassified as the just-closed
                   compound -- unprotected, judged armed at the closer. A `}`/`)`
                   that closed a function DEFINITION is exempt: a definition's
                   status is the definition's, not an executed command's.
  S4 (leak tail)   a function's last statement is `(( expr )) && act` or
                   `[ expr ]`/`[[ expr ]]`/`test expr && act` with no `||` arm: the
                   false arm returns the TEST's non-zero status to a `set -e` caller,
                   and a normal "nothing to report" outcome reads as a crash. All
                   definition shapes are tracked -- `name() {`, `name() (`,
                   `function name`, deferred `name()` newline `{`/`(` -- and
                   closers are recognised at segment granularity (`cmd; }`,
                   `}; rest`).

S3 has TWO context arms and one fix. `cmd` followed by `rc=$?` is dead when the enclosing
code runs under plain `set -e`, and FRAGILE when the enclosing function is only ever
invoked in a condition/`||` context (errexit is suppressed for the whole call tree, so the
read works today and breaks the day somebody calls the function plainly). The rewrite
`if cmd; then rc=0; else rc=$?; fi` is correct in both, so flagging unconditionally is
honest.

WHAT IS DELIBERATELY NOT FLAGGED (each would be a false positive)
------------------------------------------------------------------
  * `if x=$(grep ...); then`      -- the condition consumes the status; errexit never fires.
  * `x=$(grep ...) || true`       -- `|| :`, `|| x=0`, `|| continue` etc. all decide.
  * `x=$(grep ... || true)`       -- decided inside the substitution.
  * `local x=$(grep ...)`         -- `local`/`export`/`declare`/`readonly` RETURN THEIR OWN
                                     status, which masks the substitution's. Not an abort
                                     risk, so not an S1. (It hides real errors, but that is
                                     shellcheck SC2155's rule, not this gate's.)
  * `cmd || rc=$?` / `cmd && rc=$?` -- the read is an operator's right operand. `||`
                                     decides; `&&` short-circuits on failure, so the read
                                     is SKIPPED, not dead. A different class entirely.
  * `local rc=$?` at a function   -- the read sits at the head of a `name() {`/brace block
     head / brace head               and captures the CALLER's status on purpose (trap
                                     handlers, status passthrough).
  * reads inside `$( )` / `( )`   -- the carry-status-out idiom; depth is tracked and
                                     the read is inside a still-open group.
  * bare `$?` in arguments or     -- `echo "rc=$?"`, `[[ $? -ne 0 ]]`, `exit $?`: real but
     conditions                      noisier (`exit $?` is idiomatic); scoped out.
  * bare `[[ cond ]]` tails       -- the predicate idiom; `&&` INSIDE the brackets is not
                                     the leak.
  * `test && act || fallback`     -- the `||` arm decides the status.
  * `[[ c ]] && return|exit|break|continue` -- explicit status flow, not a leak.
  * predicate-named functions     -- `is_*`, `has_*`, `check_*`, `assert_*`, `can_*`,
                                     `should_*`, `need_*`, `same_*`, `valid*`, `*_ok`
                                     contract to return the test's status.
  * anything under `set +e`       -- state is tracked, not assumed.
  * scripts with no `set -e`      -- the premise does not hold.

HEURISTIC LIMITS (fail-silent direction, deliberately)
------------------------------------------------------
  * The quote tracker is a real context stack (`'`/`"`/`$(`/`(` frames,
    carried across lines, with `$(`-inside-`"` re-lexing), so most nesting is
    modelled. Residuals: the code after a mid-line closing quote on a
    carried-`'`/`"` line is scanned as a continuation of quote state in the
    per-LINE helpers (`_tail_state`/`_segments` get only the simplified
    innermost carry), and `$'…'` ANSI-C strings share the `'` tracker while
    their `\\'`-escape semantics differ -- `$'don\\'t'`-style strings can
    still resync a line early.
  * `name() cmd` single-command bodies are never opened (the opener is `{`/`(`
    only); their tails are a miss.
  * `;;` inside a `case` arm is not modelled -- an arm tail past `;;` merges
    into the next segment.
  * A `{`-grouped command as the read's antecedent (`{ cmd; rc=$?; }`) is a
    miss -- the group `}`/`;` frame hides the inner command.
  * Command-position tracking for the frame walk is token-approximate -- a
    `{`/`(`/`}`/`)` token is structural only at segment start or after an
    operator/reserved word, which can miss exotic placements.
  * The statement-segment model splits only on `;` (quote-aware). A pipeline as
    the antecedent is reported whole (`a | b`) rather than per-stage.
  * `PIPESTATUS` reads after a pipeline are judged live when `set -o pipefail` is
    not armed at the command's line -- the pipeline's status is then its last
    stage's, so earlier stages' failures never trip errexit.
  * `depth` counts the statement-visible parens: a `(`/`)` inside a literal or
    escaped (`\\(`) does not move it, but an unclosed `(` inside an UNQUOTED
    construct (case-arm heads inside multi-line `$( )`) can still skew it.
"""

from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys

# Commands whose non-zero exit is a NEGATIVE ANSWER rather than a failure. Kept deliberately
# short: every entry must be a command a reader would agree "exits 1 to mean no". Adding a
# command that exits non-zero only on real errors would manufacture false positives.
NONZERO_IS_AN_ANSWER = {
    "grep", "egrep", "fgrep", "rg", "ug", "ugrep", "zgrep",
    "diff", "cmp",
    "pgrep", "pidof",
    "test",
}

# Commands that PRINT a value even when they exit non-zero. `grep -c` prints `0` and exits 1
# on no-match, which is what makes `|| echo 0` emit two lines instead of one.
PRINTS_ON_FAILURE_RE = re.compile(
    r"\b(?:[a-z]*grep|rg)\s+(?:-\w*\s+)*(?:-\w*c|--count)"
)

# `X=$(...)`, `X="$(...)"`, plus indexed/attributed forms, and an OPTIONAL trailing decision
# clause (`|| true`, `|| echo 0`, `&& ...`).
#
# The trailing clause is not optional-for-tidiness -- it is load-bearing, and its absence was a
# real blind spot caught by this gate's own suite. An earlier revision anchored the match at
# `\)` + end-of-line, so `count=$(grep -c x f) || echo 0` -- the EXACT #7332 instance (c), and
# the whole reason class S2 exists -- did not match the assignment pattern at all and was
# reported as clean. `body` stays greedy so it backtracks to the LAST `)` that still leaves a
# well-formed tail.
ASSIGN_SUBST_RE = re.compile(
    r"""(?P<decl>\b(?:local|export|declare|readonly|typeset)\s+(?:-\w+\s+)*)?"""
    r"""(?P<name>[A-Za-z_][A-Za-z0-9_]*)(?:\[[^\]]*\])?="""
    r"""(?P<q>["']?)[^\s;&|'"()$\\]*\$\((?P<body>.*)\)(?P=q)"""
    r"""(?P<tail>\s*(?:\|\||&&|;)\s*\S.*)?\s*;?\s*$"""
)

SET_RE = re.compile(r"^\s*set\s+(.*)$")
CONTROL_PREFIX_RE = re.compile(
    r"^\s*(if|elif|while|until|then|else|fi|do|done|case|esac|for|select"
    r"|return|exit|break|continue|local\s+-r)\b"
)
HEREDOC_RE = re.compile(r"<<-?\s*(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\1")
# `|| echo <literal>` / `|| printf <literal>` -- adds a value rather than choosing one.
ADDS_A_VALUE_RE = re.compile(r"\|\|\s*(?:echo|printf)\b")

# A read of an exit status, captured into a variable. The VALUE forms: `$?`, `${?}`,
# `$PIPESTATUS`, `${PIPESTATUS[n]}`, each optionally DOUBLE-quoted and optionally
# carrying a LITERAL PREFIX -- `x=pre$?` embeds the same read as `x=$?` (the
# prefix class excludes `$`, quotes, whitespace, shell operators and `\\`, so an
# escaped `\$` or a single-quoted literal still does not match). The NAME side
# covers indexed and attributed forms alike: `rc=$?`, `rc="$?"`, `rc[0]=$?`,
# `declare -i rc=$?`, `local rc=$?`. A SINGLE-quoted value (`rc='$?'`,
# `rc='pre$?'`) is a literal string, not a read, and is correctly not matched.
#
# This is the ASSIGNMENT anchor only. Bare in-argument reads (`echo "rc=$?"`,
# `[[ $? -ne 0 ]]`, `exit $?`) are real but noisier (`exit $?` is idiomatic) and stay
# scoped out -- see the docstring's WHAT IS DELIBERATELY NOT FLAGGED.
_STATUS = r'"?(?:\$\?|\$\{\?\}|\$\{PIPESTATUS\[[@*a-zA-Z0-9_]+\]\}|\$PIPESTATUS\b)"?'
# Literal value prefix before a status read: `x=pre$?`, `x="pre$?"`,
# `x=$v$?`, `x=${v}$?` all read `?`/`PIPESTATUS` the same. Shell-syntax
# delimiters stay excluded (`;`/`&`/`|`/`'`/backtick end the word, `\` could
# escape the read token), but `$`/`{}`/`()`/`"` interior text is fair game.
_READ_PREFIX = r"[^\s';&|<>\\`]*"
READ_RE = re.compile(
    r"[A-Za-z_][A-Za-z0-9_]*(?:\[[^\]]*\])?=" + _READ_PREFIX + _STATUS
)

# A `local`/`declare`/`typeset`/`readonly`/`export` prefix on the read itself -- a
# modifier of the assignment, not a command whose status the read is about.
DECL_PREFIX_RE = re.compile(
    r"^(?:local|declare|typeset|readonly|export)(?:\s+-[A-Za-z]+)*\s*$"
)

# A `set` verdict inside a `;`-segment, allowing the shell introducers that can
# precede it (`{ set +e; }`, `then set +e`, `x && set -e`, `time set -e`).
# Deliberately NOT `(`: `( set -e … )` scopes to the subshell, so a `set` after
# a `(` opener must NOT touch the outer model.
_SET_SEG_RE = re.compile(
    r"^\s*(?:(?:&&|\|\||\||&|!|then|do|else|elif|fi|done|esac|time"
    r"|coproc|command|builtin|exec|\{)\s+)*set\s+(.*)$"
)

# A function opener: `name() {`, `name() (`, `function name {`,
# `function name() {`, `function name (`. Group 3 is the opener char (`{` or
# `(`) so the caller knows which closer the body ends with; groups 1/2 carry
# the function name for S4's predicate-name exemption.
FUNC_OPEN_RE = re.compile(
    r"^\s*(?:(?:function\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*\(\s*\)"
    r"|function\s+([A-Za-z_][A-Za-z0-9_]*))\s*([{(])"
)

# A bare function head with the opener DEFERRED to the next line:
# `name()`, `name ()`, `function name`, `function name()`. It records a
# pending function; the next non-blank logical line leading with `{` or `(`
# opens the body, anything else discards the pending record.
FUNC_HEAD_RE = re.compile(
    r"^\s*(?:(?:function\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*\(\s*\)"
    r"|function\s+([A-Za-z_][A-Za-z0-9_]*))\s*$"
)

# A compound's closer word followed only by redirects/`;` or an operator
# continuation (`fi`, `done < f`, `esac`, `done 2>&1`, `done | tee`,
# `done && x`). Anything else after the word means the text is not a closer
# (an `fi x` is malformed shell, not a compound tail) and falls back to the
# ordinary protection checks.
_WORD_CLOSER_RE = re.compile(r"^(fi|done|esac)(?=$|[\s;])")
_REDIRECT_OP_RE = re.compile(r"^(?:[0-9]*[<>]{1,3}|&>>?|>>&?)")
_REDIRECT_OP_ONLY_RE = re.compile(r"^(?:[0-9]*[<>]{1,3}&?-?|&>>?)$")


def _closer_tail_ok(tail: str) -> bool:
    """A word closer's tail may carry only redirects or an operator
    continuation. Token-per-token scan -- deliberately NOT one nested regex,
    which measured exponential backtracking on `done <a <b … ; x` inputs."""
    toks = tail.replace(";", " ").split()
    i = 0
    while i < len(toks):
        t = toks[i]
        if t in ("|", "|&", "&&", "||", "&"):
            return True
        if not _REDIRECT_OP_RE.match(t):
            return False
        i += 1
        # An operator-alone token (`>`, `2>`, `<`) consumes the next word as
        # its target; `>f`/`2>&1` carry theirs inline.
        if _REDIRECT_OP_ONLY_RE.fullmatch(t) and i < len(toks):
            i += 1
    return True


def _closer_head(cand: str) -> str | None:
    """Return 'word', 'brace' or 'paren' when `cand` is a compound's closer
    rather than a command, else None.

    `fi`/`done`/`esac` may carry trailing redirects, `;`, and operator
    continuations. A bare `}`/`};` or `)`/`);` is a GROUP close -- whether it
    instead closed a function DEFINITION is the caller's frame question
    (close_info), not decidable from the text. A `)` that is NOT a standalone
    token (case-arm heads like `start)`, `x=($(cmd))`) is filtered by
    requiring the `)` to lead the text.
    """
    c = cand.strip()
    m = _WORD_CLOSER_RE.match(c)
    if m:
        return "word" if _closer_tail_ok(c[m.end() :]) else None
    if c.startswith("}"):
        return "brace"
    if re.match(r"^\)(?=$|[\s;])", c):
        return "paren"
    return None

# The S4 tail shapes: a test builtin whose `&&` sits STRICTLY OUTSIDE the test. `[[ a
# && b ]]` alone does not match -- the leak is the unguarded `&&` between the test and
# the action, not a conjunction inside the predicate.
S4_TAIL_RES = (
    re.compile(r"^\(\(.*\)\)\s*&&\s*(?P<act>.+)$"),        # (( expr )) && act
    re.compile(r"^\[\[.*\]\]\s*&&\s*(?P<act>.+)$"),       # [[ expr ]] && act
    re.compile(r"^\[(?!\[)[^\]]*\]\s*&&\s*(?P<act>.+)$"),  # [ expr ] && act
    re.compile(r"^test\s+.*&&\s*(?P<act>.+)$"),            # test expr && act
)

# Actions that make a tail an explicit status flow rather than a leak.
S4_FLOW_WORDS = {"return", "exit", "break", "continue"}

# Names declaring the function's status IS the answer -- a test tail is the contract.
PREDICATE_NAME_RE = re.compile(
    r"^(?:is_|has_|check_|assert_|can_|should_|need_|same_|valid)|_ok$"
)


def strip_comment_lines(lines: list[str]) -> list[str]:
    """Blank comment-only lines, PRESERVING numbering (a `#` inside a string is not a comment)."""
    return ["" if ln.lstrip().startswith("#") else ln for ln in lines]


def drop_heredocs(lines: list[str]) -> list[str]:
    """Blank heredoc BODIES. Their contents are data, not commands of this shell."""
    out: list[str] = []
    terminator: str | None = None
    for line in lines:
        if terminator is not None:
            out.append("")
            if line.strip() == terminator:
                terminator = None
            continue
        out.append(line)
        # `<<` inside a quoted string, a comment tail, or arithmetic
        # (`x=$((a<<b))`) opens NOTHING: test each candidate position against
        # the quote-masked text, and require paren depth 0. The name itself is
        # read from the RAW line (`_unquoted` blanks a `<<'EOF'` delimiter).
        if "<<" not in line or line.lstrip().startswith("#"):
            continue
        uq = _unquoted(line)
        for m in HEREDOC_RE.finditer(line):
            if m.start() >= len(uq) or uq[m.start()] != "<":
                continue
            if uq[: m.start()].count("(") > uq[: m.start()].count(")"):
                continue
            terminator = m.group(2)
            break
    return out


def join_continuations(lines: list[str]) -> list[tuple[int, str]]:
    """Fold `\\`-continued physical lines into one logical line, keyed by its FIRST line number."""
    out: list[tuple[int, str]] = []
    buf = ""
    start = 0
    for idx, line in enumerate(lines, start=1):
        if not buf:
            start = idx
        if line.rstrip().endswith("\\"):
            buf += line.rstrip()[:-1] + " "
            continue
        out.append((start, buf + line))
        buf = ""
    if buf:
        out.append((start, buf))
    return out


def _strip_comment_tail(args: str) -> str:
    """Drop an unquoted `# ...` tail from a `set` argument string.

    `set -uo pipefail  # deliberately NOT -e` used to tokenize the `-e` inside the
    comment as an ARGUMENT and phantom-arm the errexit model for the rest of the file.
    A `#` outside quotes starts a comment only at a word boundary, so the tail is
    data, not flags.
    """
    in_single = in_double = False
    for i, ch in enumerate(args):
        if ch == "'" and not in_double:
            in_single = not in_single
        elif ch == '"' and not in_single:
            in_double = not in_double
        elif (
            ch == "#" and not in_single and not in_double
            and (i == 0 or args[i - 1] in " \t")
        ):
            return args[:i]
    return args


def set_verdicts(args: str) -> dict[str, bool]:
    """Option deltas from a `set` line: `{name: True}` for CLEARED, `{name: False}`
    for ARMED -- `set +e` -> `{'errexit': True}`, `set -o pipefail` ->
    `{'pipefail': False}`.

    Compound forms are matched by token, never by literal string: `set -euo pipefail`
    re-arms errexit AND pipefail, `set +o errexit` clears, and a cluster-FINAL `o`
    consumes the NEXT token as the option name (`set -o errexit`, `set -euo
    pipefail`) rather than being parsed as a cluster member. Tokens after `--` are
    positional parameters, not options.
    """
    out: dict[str, bool] = {}
    toks = _strip_comment_tail(args).split()
    i = 0
    while i < len(toks):
        tok = toks[i]
        if tok == "--":
            break
        if tok.startswith("--"):
            i += 1
            continue
        if tok.startswith(("-", "+")):
            sign = tok.startswith("+")
            cluster = tok[1:]
            opt_i = cluster.find("o")
            if opt_i != -1:
                # `o` consumes the REST OF THE WORD (or the next token, when it
                # is the cluster's last letter) as the option name:
                # `set -o pipefail`, `set -euo pipefail`, `set -opipefail`,
                # `set -onounset` all parse this way -- only the name field
                # matters; the leftover cluster still carries `e` if present.
                name = cluster[opt_i + 1:] or (toks[i + 1] if i + 1 < len(toks) else "")
                if name in ("errexit", "pipefail"):
                    out[name] = sign
                i += 1 if cluster[opt_i + 1:] else 2
                cluster = cluster[:opt_i]
            else:
                i += 1
            if "e" in cluster:
                out["errexit"] = sign
            continue
        i += 1
    return out


def set_errexit_verdict(args: str) -> bool | None:
    """True if this `set` CLEARS -e, False if it ARMS it, None if it says nothing."""
    return set_verdicts(args).get("errexit")


def _quote_scan(
    text: str, qstack: list[str]
) -> tuple[str, list[bool], list[bool], list[str]]:
    """One-pass quote tracker over a carried context STACK.

    `qstack` frames, innermost last: `'sq'`/`'dq'` quote spans, `'sub'` a
    `$(` substitution context, `'paren'` a plain `(` inside a substitution.
    A `'sub'` frame's interior lexes as CODE even under `'dq'` -- bash
    re-lexes `"$(cmd 'x' "$y" ...)"`, so quotes there are real toggles, and
    nested `"$(a "$(b)")"` shapes need an actual stack, not flag pairs.

    Returns `(vis, sq, sub, qstack)` with `qstack` updated in place for
    the next line:

      * `vis` -- `text` with every position under a `'sq'`/`'dq'` frame
        blanked (delimiters included) and every comment tail blanked, at
        preserved positions, so `set`/`;`/`(`/`)` inside either is invisible
        to the state model and the segmenter.
      * `sq` -- per-position flags for chars inside a SINGLE-quoted span:
        `$( )` and `$?` inside `'...'` are data for another interpreter,
        while inside `"..."` they still expand, so the two interiors differ.
      * `sub` -- per-position flags for chars inside a `'sub'`/`'paren'`
        frame (`$(` interior, quoted or not): `$?`/`$()` there belong to the
        substitution's shell, not this line's statement flow.
      * positions under `'sub'`/`'paren'` alone are VISIBLE in `vis` -- code
        in an unquoted `$(` runs under this shell's line-level model.

    Escape rule (adopted from `_heredoc_opener` in
    lint-workflow-errexit-capture.py): `\\` escapes the next char everywhere
    except inside single quotes, so `don\\'t` does not open a quote and
    `"a\\"b"` does not close one. The escaped char is blanked in `vis` too,
    so `\\;`/`\\(` cannot spoof a boundary or a depth step. An unquoted `#`
    at a word boundary (see `_is_comment_start`) starts a comment: the rest
    of the line is blanked, so an apostrophe in `# don't` can never open a
    phantom string.
    """
    vis: list[str] = []
    sq: list[bool] = []
    sub: list[bool] = []
    i = 0
    n = len(text)
    # Fast paths: empty stack and no quote/escape/comment chars (the common
    # case), or a line wholly inside a carried single-quote with no close.
    if not qstack and not re.search(r"['\"\\#]", text):
        return text, [False] * n, [False] * n, qstack
    if qstack == ["sq"] and "'" not in text:
        return " " * n, [True] * n, [False] * n, qstack
    while i < n:
        ch = text[i]
        top = qstack[-1] if qstack else "code"
        quoted = "sq" in qstack or "dq" in qstack
        in_sub = "sub" in qstack or "paren" in qstack
        if top == "sq":
            sq.append(True)
            sub.append(in_sub)
            vis.append(" ")
            if ch == "'":
                qstack.pop()
            i += 1
            continue
        if top == "dq":
            sq.append(False)
            sub.append(in_sub)
            vis.append(" ")
            if ch == "\\" and i + 1 < n:
                vis.append(" ")
                sq.append(False)
                sub.append(in_sub)
                i += 2
                continue
            if ch == '"':
                qstack.pop()
                i += 1
                continue
            if ch == "$" and i + 1 < n and text[i + 1] == "(":
                qstack.append("sub")
                vis.append(" ")
                sq.append(False)
                sub.append(True)
                i += 2
                continue
            i += 1
            continue
        # code context: real lexing (`top` is 'code'/'sub'/'paren')
        if ch == "\\" and i + 1 < n:
            vis.append(ch + " ")
            sq.extend((False, False))
            sub.extend((in_sub, in_sub))
            i += 2
            continue
        if ch == "#" and _is_comment_start(text, i):
            # Unquoted `#` at a word boundary opens a comment to EOL.
            vis.extend(" " * (n - i))
            sq.extend(False for _ in range(n - i))
            sub.extend([in_sub] * (n - i))
            break
        if ch == "'":
            # The delimiter is part of the quoted span -- masked, sq-flagged.
            qstack.append("sq")
            vis.append(" ")
            sq.append(True)
            sub.append(in_sub)
            i += 1
            continue
        if ch == '"':
            qstack.append("dq")
            vis.append(" ")
            sq.append(False)
            sub.append(in_sub)
            i += 1
            continue
        sq.append("sq" in qstack)
        vis.append(" " if quoted else ch)
        if ch == "$" and i + 1 < n and text[i + 1] == "(":
            qstack.append("sub")
            sub.append(True)
            vis.append(" ")
            sq.append(False)
            sub.append(True)
            i += 1
        elif ch == "(" and top != "code":
            qstack.append("paren")
            sub.append(True)
        elif ch == ")" and top in ("sub", "paren"):
            qstack.pop()
            sub.append(in_sub)
        else:
            sub.append(in_sub)
        i += 1
    return "".join(vis), sq, sub, qstack


def _unquoted(text: str, in_s: bool = False, in_d: bool = False) -> str:
    """Quoted interiors blanked (delimiters kept), so `||`/`&&`/`|` inside
    `'...'`/`"..."` are not read as operators. Same escape rule as
    `_quote_scan`: `\\` escapes the next char everywhere except inside single
    quotes -- an unquoted `\\'` can no longer open a phantom string. A lone
    unclosed quote blanks to EOL (documented limit). `in_s`/`in_d` carry a
    quote left open by a previous logical line, so a carried-in `'`/`"` is
    correctly read as CLOSING it, not opening a new one."""
    out = []
    i = 0
    while i < len(text):
        ch = text[i]
        if ch == "\\" and not in_s and i + 1 < len(text):
            out.append("  " if in_d else ch + " ")
            i += 2
            continue
        if ch == "#" and not in_s and not in_d and _is_comment_start(text, i):
            # comment tail -- quote chars inside comments do not count for parity
            break
        if ch == "'" and not in_d:
            in_s = not in_s
            out.append("'")
        elif ch == '"' and not in_s:
            in_d = not in_d
            out.append('"')
        elif in_s or in_d:
            out.append(" ")
        else:
            out.append(ch)
        i += 1
    return "".join(out)


def _is_comment_start(text: str, i: int) -> bool:
    """Unquoted `#` at a word boundary opens a comment -- except inside
    `${#…}` length expansion, where `#` follows `${`."""
    if text[i] != "#":
        return False
    if i == 0:
        return True
    prev = text[i - 1]
    if prev not in " \t;&|(){}<>":
        return False
    return not (prev == "{" and i >= 2 and text[i - 2] == "$")


def _has_unmasked_op(tail_raw: str, sq_tail: list[bool]) -> bool:
    """`||`/`&&` present in `tail_raw` at a position not inside a
    single-quoted span (`sq` position flags for the same slice)."""
    for m in re.finditer(r"\|\||&&", tail_raw):
        if not all(sq_tail[m.start() : m.end()]):
            return True
    return False


def _tail_state(
    text: str, in_s: bool = False, in_d: bool = False
) -> tuple[bool, bool, int]:
    """Scan `text` -- which may OPEN inside a quote carried from a prior
    logical line (`in_s`/`in_d`) -- and return the quote state and unclosed
    paren depth at its end. Used to decide whether a read sits inside an
    unclosed `"`/`'` string or `$(`/`(` group; comment tails stop the scan."""
    d = 0
    i = 0
    n = len(text)
    while i < n:
        ch = text[i]
        if ch == "\\" and not in_s and i + 1 < n:
            i += 2
            continue
        if in_s:
            if ch == "'":
                in_s = False
        elif in_d:
            if ch == '"':
                in_d = False
        elif ch == "#" and _is_comment_start(text, i):
            break
        elif ch == "'":
            in_s = True
        elif ch == '"':
            in_d = True
        elif ch == "(":
            d += 1
        elif ch == ")" and d:
            d -= 1
        i += 1
    return in_s, in_d, d


def _segments(
    text: str, start_depth: int = 0, in_s: bool = False, in_d: bool = False
) -> list[tuple[str, int]]:
    """`;`-separated statement segments with the paren depth at each segment's
    START. `;` is the only separator: `|`, `||`, `&&`, `&` belong to the command
    (pipeline stages, operands, `2>&1` redirects), never to boundaries.
    `start_depth` is the outer depth the text begins under, so `;` inside a
    `$(`/`(` group still records depth > 0 for the segments it splits into.

    Quote-aware: a `;` or `(`/`)` inside `'...'`/`"..."` is literal text, and
    `in_s`/`in_d` carry a quote left open by a previous logical line (a line
    beginning inside a multi-line string keeps its text in the open quote).
    An unquoted `#` at a word boundary ends the line (comment tail): `;` or
    `set` text inside a comment is not a boundary or a verdict.
    """
    if ";" not in text:
        # No separator -- one tail segment; internal depth bookkeeping is
        # unobservable to every caller.
        tail = text.strip()
        return [(tail, start_depth)] if tail else []
    segs: list[tuple[str, int]] = []
    d = start_depth
    seg_depth = d
    cur: list[str] = []
    i = 0
    n = len(text)
    while i < n:
        ch = text[i]
        if ch == "\\" and not in_s and i + 1 < n:
            cur.append(ch + text[i + 1])
            i += 2
            continue
        if ch == "#" and not in_s and not in_d and _is_comment_start(text, i):
            break
        if ch == "'" and not in_d:
            in_s = not in_s
        elif ch == '"' and not in_s:
            in_d = not in_d
        elif ch == ";" and not in_s and not in_d:
            seg = "".join(cur).strip()
            if seg:
                segs.append((seg, seg_depth))
            cur = []
            seg_depth = d
            i += 1
            continue
        elif not in_s and not in_d:
            if ch == "(":
                d += 1
            elif ch == ")":
                d = max(0, d - 1)
        cur.append(ch)
        i += 1
    tail = "".join(cur).strip()
    if tail:
        segs.append((tail, seg_depth))
    return segs


def _segments_pair(
    text: str, in_s: bool = False, in_d: bool = False
) -> list[tuple[str, str]]:
    """`_segments` emitting `(raw_seg, masked_seg)` pairs in ONE pass.

    The masked seg blanks single- AND double-quoted interiors and comment
    tails; the raw seg keeps original text. Segmenting a line once on masked
    text and once on raw text misaligns the two lists -- a fully-quoted
    `;`-segment drops out of the masked list but stays in the raw one -- so
    consumers that need both take them from this single scan. `in_s`/`in_d`
    carry a quote left open by a previous logical line.
    """
    segs: list[tuple[str, str]] = []
    cur_r: list[str] = []
    cur_m: list[str] = []
    i = 0
    n = len(text)
    while i < n:
        ch = text[i]
        if in_s:
            cur_r.append(ch)
            cur_m.append(" ")
            if ch == "'":
                in_s = False
        elif in_d:
            cur_r.append(ch)
            cur_m.append(" ")
            if ch == "\\" and i + 1 < n:
                cur_r.append(text[i + 1])
                cur_m.append(" ")
                i += 1
            elif ch == '"':
                in_d = False
        elif ch == "#" and _is_comment_start(text, i):
            break
        elif ch == "\\" and i + 1 < n:
            cur_r.append(ch)
            cur_r.append(text[i + 1])
            cur_m.append(ch)
            cur_m.append(" ")
            i += 1
        elif ch == "'":
            in_s = True
            cur_r.append(ch)
            cur_m.append(" ")
        elif ch == '"':
            in_d = True
            cur_r.append(ch)
            cur_m.append(" ")
        elif ch == ";":
            m = "".join(cur_m).strip()
            if m:
                segs.append(("".join(cur_r).strip(), m))
            cur_r = []
            cur_m = []
        else:
            cur_r.append(ch)
            cur_m.append(ch)
        i += 1
    m = "".join(cur_m).strip()
    if m:
        segs.append(("".join(cur_r).strip(), m))
    return segs


# Command-position inducers for the frame walk: the token AFTER one of these
# (or at segment start) sits in command position, so a standalone `{`/`(`/`}`
# there is structural. `for`/`select`/`in` are deliberately absent -- a word
# after them is a list member, not a command. `;;`/`;&`/`;;&` terminator
# tokens are handled inline: what follows them is a case PATTERN.
_CMD_INDUCERS = frozenset(
    {
        "&&", "||", "|", "&", "!", "then", "do", "else", "elif", "time",
        "coproc", "command", "exec", "builtin", "noglob", "eval",
    }
)
_WORD_OPENERS = {
    "if": "fi",
    "while": "done",
    "until": "done",
    "for": "done",
    "select": "done",
    "case": "esac",
}
_WORD_CLOSER_TOKENS = frozenset({"fi", "done", "esac"})
# `{`/`(` immediately after these run in a suppressed-errexit position: the
# negation marker `!` or a compound's CONDITION head (`if { …; }; then`).
_SUPPRESS_AFTER = frozenset({"!", "if", "elif", "while", "until"})
# Gate for the per-line frame walk: only a line carrying a frameable token or
# delimiter can open/close anything.
_FRAME_TRIG = re.compile(
    r"[{}()]|\b(?:if|while|until|for|select|case|fi|done|esac)\b"
)


def _seg_events(mseg: str) -> list[tuple[str, str | None]]:
    """Structural events in one `;`-segment of MASKED text, in order.

    Each event is `(kind, prev_tok)` with `kind` one of:
      `{`, `(`        -- group/subshell openers in command position
      `$(`            -- a `(` opened inside a token (`$(`, `$((`, `x=(`)
      `}`, `)`        -- group/subshell closers; `)` matches wherever a
                         standalone `)` token appears
      `)x`            -- an excess `)` inside a token (a case-arm head `x)`,
                         an `x=$(a)`/`x=(a)` body close)
      `if`/`while`/`until`/`for`/`select`/`case` -- compound openers
      `fi`/`done`/`esac`                         -- compound closers
    `prev_tok` is the preceding token, for operand/context checks (`! {`,
    `if { …; }; then` condition heads). Command-position tracking is
    approximate -- the goal is bookkeeping consistency, not full parsing.
    """
    events: list[tuple[str, str | None]] = []
    cmd_tok = True
    prev: str | None = None
    for tok in mseg.split():
        if cmd_tok and tok in ("{", "("):
            events.append((tok, prev))
            prev, cmd_tok = tok, True
            continue
        if tok == "}" and cmd_tok:
            events.append(("}", prev))
            prev, cmd_tok = tok, True
            continue
        if tok == ")":
            # A standalone `)` can only be a closer -- it is never argument
            # position inside an open `(`/`$(` frame.
            events.append((")", prev))
            prev, cmd_tok = tok, True
            continue
        if cmd_tok and tok in _WORD_OPENERS:
            events.append((tok, prev))
            prev, cmd_tok = tok, True
            continue
        if cmd_tok and tok in _WORD_CLOSER_TOKENS:
            events.append((tok, prev))
            prev, cmd_tok = tok, True
            continue
        opens = tok.count("(")
        closes = tok.count(")")
        for _ in range(opens - closes):
            events.append(("$(", prev))
        for _ in range(closes - opens):
            events.append((")x", prev))
        prev = tok
        cmd_tok = tok in _CMD_INDUCERS or closes > opens  # `x)` arm heads
        if ";;" in tok or tok.endswith(";&"):
            cmd_tok = False  # a case pattern follows, not a command
    return events


def _first_close(vis_inner: str, closer: str) -> int:
    """Index of the first `closer` at depth 0 of `vis_inner` (masked text), or
    -1. `rfind` would land on a LATER same-line closer (`f() { a; } echo ${y}`)
    and lose the body; depth counting keeps a nested `{ x; }`/`( y )` inside
    and finds the construct's own end.
    """
    open_c = "{" if closer == "}" else "("
    d = 1
    for i, ch in enumerate(vis_inner):
        if ch == open_c:
            d += 1
        elif ch == closer:
            d -= 1
            if d == 0:
                return i
    return -1


def _seg_index_of(vstrip: str, charpos: int) -> int:
    """Which `;`-segment of `vstrip` holds character `charpos`: the count of
    non-empty segments strictly before it, minus one when the position joins
    the current segment rather than starting a new one (`a }` vs `a; }`)."""
    pre = vstrip[:charpos]
    n = len(_segments(pre))
    if not pre.rstrip().endswith(";"):
        n -= 1
    return max(0, n)


def substituted_commands(body: str) -> list[str]:
    """Split a substitution body into its pipeline stages, ignoring `||`/`&&` right operands.

    Only the stages that can set the substitution's exit status matter. With `pipefail` any
    stage can; without it only the last can. This gate does not try to prove which -- it
    inspects every stage, because a repo that sets `-o pipefail` in its house preamble (this
    one does) makes every stage load-bearing.
    """
    # The substitution's status is its LAST `;`-statement's; within it EVERY
    # `|`/`||`/`&&` operand is a stage whose non-zero exit can surface:
    # `x=$(a; grep …)` fails on grep, `x=$(grep -c … || echo 0)` still sees the
    # grep (S2 double-emit). Operator chars inside quotes are not operators:
    # `grep 'a||b'` is one stage. A last statement built like `} | tr` or
    # `) | x` rejoins the group's own segments -- `x=$({ p|grep|wc; } | tr)`
    # still surfaces the grep under pipefail.
    segs = _unquoted(body).split(";")
    tail = segs.pop()
    while segs and (
        tail.count("}") > tail.count("{") or tail.count(")") > tail.count("(")
    ):
        tail = segs.pop() + ";" + tail
    return [
        seg.strip()
        for seg in re.split(r"\|\||&&|\|", tail)
        if seg.strip()
    ]


def first_word(cmd: str) -> str:
    """The command name, skipping env-var prefixes like `LC_ALL=C grep ...`."""
    for tok in cmd.split():
        if "=" in tok and not tok.startswith("-") and re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", tok):
            continue
        return os.path.basename(tok.strip("\"'"))
    return ""


def is_protected(cmd: str) -> bool:
    """Whether this command's failure is already handled, so errexit never fires on it."""
    c = cmd.strip()
    if not c:
        return True
    if CONTROL_PREFIX_RE.match(c) and (
        ";" not in c or not re.search(r"\b(fi|done|esac)\b", c)
    ):
        return True
    # A `;`-containing control cand with no closer is a condition HEAD running
    # mid-construct (`if c; then`, `for x in y; do`) -- protected. One WITH a
    # closer is a whole compound (`if c; then cmd; fi`, `while c; do cmd; done`)
    # whose armed arm can still abort -- NOT protected.
    # `!`-negated commands are exempt from errexit by POSIX -- a real protection.
    if c.startswith("!"):
        return True
    # DELIBERATELY no `||`/`&&` substring test here, ported from the sibling gate: under
    # errexit `a && b` DOES abort when `b` fails, so only left operands are exempt, and an
    # operator inside a quoted argument (`bash -c "a && b"`) has no bearing on this shell
    # at all. The real `cmd || rc=$?` idiom is judged precisely at the read site below,
    # which is where the protection lives -- a property of the read's position, not of an
    # operator somewhere in the command.
    return False


def _s3_exempt_command(cmd: str, depth: int = 0) -> bool:
    """Shell-specific S3 exemptions beyond is_protected().

    The resolved "command" is a composite boundary, so the read is not about it:

      * a function opener (`name() {`, `function name`) -- a read just inside the body
        captures the CALLER's status on purpose (`local rc=$?` at a function head, e.g.
        a trap handler reading the status it was invoked with);
      * a bare `{`/`}` -- group open or composite close: the read sees the composite's
        or the caller's status;
      * a command ending in `{` (`cmd || {`, `if c; then {`) -- the read opens the
        compound block and sees the status that SELECTED it: `cmd || { rc=$?` is the
        protection idiom itself, not a leak;
      * a case-arm head (`start)`, `stop|restart)`, `*)`) -- an unmatched close-paren,
        not a command. The paren-count check keeps `x=$(cmd)` (balanced) out of this,
        and the depth gate keeps a `$(` continuation tail (`bar)` on the line that
        closes a multi-line substitution) from masquerading as a case arm.
      * `trap`/`eval` are NOT exemptions here: reads INSIDE their string arguments
        are already scoped out by the read-side quote checks; `eval "$script"; rc=$?`
        is a real dead read.
    """
    c = cmd.strip()
    if FUNC_OPEN_RE.match(c):
        return True
    if c.startswith(("{", "}")) or c.endswith("{"):
        return True
    if (
        depth == 0
        and re.match(r"^\S+\)", c)
        and _unquoted(c).count("(") < _unquoted(c).count(")")
    ):
        return True
    return False


def _s4_check(
    tail: str, lineno: int, func_name: str, findings: list[tuple[int, str, str]]
) -> None:
    """Append an S4 finding if `tail` is a status-leaking `test-builtin && action`.

    Silent arms, in order: a `||` in the ACTION decides the tail's status (a `||`
    INSIDE the test predicate does not); the action being `return`/`exit`/`break`/
    `continue` is explicit status flow; and a predicate-named function (`is_*`,
    `check_*`, `*_ok`, ...) contracts to return the test's status.
    """
    for rex in S4_TAIL_RES:
        m = rex.match(tail)
        if not m:
            continue
        act = m.group("act").strip()
        if "||" in _unquoted(act):
            return  # a `||` arm decides; inside act's quotes it is not an arm
        toks = act.split()
        first = toks[0].rstrip(";") if toks else ""
        if first == "{" and len(toks) > 1:
            first = toks[1].rstrip(";")
        if first in S4_FLOW_WORDS or PREDICATE_NAME_RE.search(func_name):
            return
        findings.append((lineno, "S4", tail))
        return


def scan(path: str) -> list[tuple[int, str, str]]:
    """Return (line, code, logical_line) findings for one script.

    A lexical pass first builds the per-line quote context (`_quote_scan`'s
    carried stack), then pass 1 computes the errexit state and unclosed-paren
    depth BEFORE each logical line on the quote-masked text; pass 2 judges
    each construct against the state at ITS line -- the state at the COMMAND's
    line, not at the read's, because `cmd` then `set +e` then `rc=$?` is the
    canonical mis-fix and judging at the read would make it invisible.
    """
    try:
        raw = open(path, encoding="utf-8", errors="replace").read().split("\n")
    except OSError:
        return []

    lines = drop_heredocs(strip_comment_lines(raw))
    logical = join_continuations(lines)

    # --- quote model ----------------------------------------------------------
    # `quote_at[pos]` is True when logical line `pos` BEGINS inside an open
    # `'…'`/`"…"` string carried from an earlier line; `vis[pos]` is the line's
    # statement-visible text (every quoted span and every comment tail blanked,
    # positions preserved); `sq[pos]` flags positions inside a SINGLE-quoted
    # span (their `$( )`/`$?`/`set` are data for another interpreter -- a
    # `"…"` interior's are NOT, they still expand in this shell); `qs_in_s`/
    # `qs_in_d` carry the quote state each line BEGINS under, so a `'`/`"`
    # opening the line's text correctly reads as CLOSING it.
    vis_lines: list[str] = []
    sq_masks: list[list[bool]] = []
    sub_masks: list[list[bool]] = []
    quote_at: list[bool] = []
    qs_in_s: list[bool] = []
    qs_in_d: list[bool] = []
    qstack: list[str] = []
    qstart: int | None = None
    for pos_i, (_ln, text) in enumerate(logical):
        quote_at.append("sq" in qstack or "dq" in qstack)
        # The carried-in state for the per-line helpers, simplified to the
        # innermost frame: `'`/`"` continuations carry their quote; a
        # `$(`-in-`"` sub frame lexes as code, so it carries unquoted.
        qs_in_s.append(bool(qstack and qstack[-1] == "sq"))
        qs_in_d.append(bool(qstack and qstack[-1] == "dq"))
        vis, sq, subm, qstack = _quote_scan(text, qstack)
        # Position-mask alignment is load-bearing (segs, sq lookups, close
        # keys index by raw position) -- a per-char append bug desyncs
        # silently, so assert it loud here.
        assert len(vis) == len(sq) == len(subm) == len(text), (
            f"mask alignment broke at {path}:{_ln}"
        )
        vis_lines.append(vis)
        sq_masks.append(sq)
        sub_masks.append(subm)
        if "sq" in qstack or "dq" in qstack:
            if not quote_at[-1]:
                qstart = pos_i
        else:
            qstart = None
    if qstart is not None:
        # A quote still open at EOF almost certainly was never a quote: re-judge
        # the whole open-quoted tail as code -- fail toward "scan it", mirroring
        # the sibling gate's unterminated-heredoc rule.
        for i in range(qstart, len(logical)):
            vis_lines[i] = logical[i][1]
            quote_at[i] = False
            sq_masks[i] = [False] * len(logical[i][1])
            sub_masks[i] = [False] * len(logical[i][1])

    # --- pass 1: errexit/pipefail state and paren depth before each line ------
    state: list[bool] = []
    pipefail_at: list[bool] = []
    depth_at: list[int] = []
    errexit = False
    pipefail = False
    depth = 0  # unclosed `(` -- a `set` inside `$( )`/`( )` is scoped to the subshell
    for pos_i, (_idx, text) in enumerate(logical):
        state.append(errexit)
        pipefail_at.append(pipefail)
        depth_at.append(depth)
        # `vis` blanks only the still-quoted head of a carried-quote line; the
        # code tail after a mid-line closing quote (`" 2>&1)`) is real code --
        # its `set` verdicts and paren balance MUST be counted, or the state
        # model freezes for the rest of the file.
        vtext = vis_lines[pos_i]
        # `set` verdicts are per-SEGMENT, not just line-initial: `foo; set -e`
        # arms like a line-initial set, while a `set` inside `$( )`/`( )` scopes
        # to the group -- the same depth rule for clears AND arms.
        if "set" in vtext:
            for seg, sdep in _segments(vtext, depth):
                if sdep != 0:
                    continue
                m = _SET_SEG_RE.match(seg)
                if not m:
                    continue
                v = set_verdicts(m.group(1))
                ev = v.get("errexit")
                if ev is True:
                    errexit = False
                elif ev is False:
                    errexit = True
                pv = v.get("pipefail")
                if pv is True:
                    pipefail = False
                elif pv is False:
                    pipefail = True
        # Depth counts the statement-visible parens: `(`/`)` inside a literal
        # (`echo 'a(b'`) or escaped (`x=\(`) do not open groups.
        depth += vtext.count("(") - vtext.count(")")
        if depth < 0:
            depth = 0

    # --- pass 2: S1/S2 captures, S3 dead reads, S4 leaking tails ---------------
    findings: list[tuple[int, str, str]] = []
    s1s2_positions: set[int] = set()  # logical positions that already emitted S1/S2
    # Frame stack: (kind, closer, armed, name, open_pos, open_body). kind is
    # 'func' (S4 tail judgment on pop), 'group' (`{ }`/`( )`), 'word'
    # (`if`/`while`/`for`/`case` compounds), or 'subst' (`$(`/`x=(`/`((` opened
    # inside a token). `armed` records whether the construct ran in a
    # suppressed-errexit position (`!`-negated, or a condition head like
    # `if { …; }; then`) so the S3 resolver can tell an armed compound tail
    # from a suppressed one.
    frames: list[tuple[str, str, bool, str, int, str]] = []
    # (pos, seg_idx) -> (kind, armed) for the construct closed at that segment
    # -- the S3 antecedent resolver consults it: a read after a function
    # DEFINITION close sees the definition's status (boring, not dead), and a
    # read after a suppressed construct (`! { … }`) is live.
    close_info: dict[tuple[int, int], tuple[str, bool]] = {}
    # A bare `name()` / `function name` head awaiting its deferred opener.
    pending_name: str | None = None
    last_nonempty: int | None = None

    def _push_inner_events(inner_vis: str) -> None:
        """Walk the text after a `name() {`/`(` opener for same-line inner
        opens, so a later `)`/`fi`/`}` matches the inner frame, not the func."""
        for mseg, _d in _segments(inner_vis):
            for ev, ptok in _seg_events(mseg):
                if ev in ("{", "("):
                    frames.append(("group", "}" if ev == "{" else ")",
                                   ptok not in _SUPPRESS_AFTER, "", -1, ""))
                elif ev == "$(":
                    frames.append(("subst", ")", True, "", -1, ""))
                elif ev in _WORD_OPENERS:
                    frames.append(("word", _WORD_OPENERS[ev], ptok != "!",
                                   "", -1, ""))

    def _pop_func_tail(
        fr: tuple[str, str, bool, str, int, str],
        si: int,
        pairs: list[tuple[str, str]],
        pos: int,
        lineno: int,
    ) -> None:
        """S4 tail judgment when a 'func' frame pops at (pos, seg si)."""
        tail = ""
        tail_lineno = lineno
        tail_state = False
        if si > 0 and pairs[si - 1][0].strip():
            # The tail is the `;`-segment just before this closer on the same
            # line (`cmd; }`; `}; rest` falls through to the prior line).
            tail = pairs[si - 1][0].strip()
            if re.match(r"^[{]|^\(\s", tail):
                tail = tail[1:].strip()  # a leading `{`/`( ` is the group opener
            tail_state = state[pos]
        elif last_nonempty is not None:
            tail_lineno, t_text = logical[last_nonempty]
            tsegs = _segments(t_text)
            tail = tsegs[-1][0].strip() if tsegs else t_text.strip()
            tail_state = state[last_nonempty]
            if last_nonempty == fr[4]:
                # Two-line `f() { tail` form: the tail shares the opener
                # line; check the part AFTER the opener.
                osegs = _segments(fr[5])
                tail = osegs[-1][0].strip() if osegs else fr[5]
        if tail_state:
            _s4_check(tail, tail_lineno, fr[3], findings)

    for pos, (lineno, text) in enumerate(logical):
        stripped = text.strip()
        if not stripped:
            continue
        # Statement-visible shadow of `stripped` (quoted spans and comment
        # tails blanked) at the SAME positions, so an index into one slices
        # the other.
        lead = len(text) - len(text.lstrip())
        vline = vis_lines[pos]
        vstrip = vline[lead : lead + len(stripped)]
        sqline = sq_masks[pos]

        # --- function-boundary + construct-frame bookkeeping ------------------
        # Every POSIX definition shape: `name() {`, `name() (`, `function
        # name`, and deferred openers (`name()` / `function name` on their own
        # line, then `{`/`(` on the next). Frame tokens are recognised per
        # `;`-segment on the masked text in approximate command position --
        # the first token of a segment or the token after an operator/reserved
        # word. `${x}`/`{a,b}`, quoted braces and `x)` case-arm heads never
        # reach this code (masked out or non-standalone). Runs for EVERY line
        # (top-level constructs produce `close_info` for the S3 resolver) and
        # BEFORE the `set`-line skip (`set +u; }` still closes a function).
        def_open = False
        fm = FUNC_OPEN_RE.match(vstrip)
        if fm:
            pending_name = None  # a real opener discards any pending head
            func_name = fm.group(1) or fm.group(2)
            closer = "}" if fm.group(3) == "{" else ")"
            inner = stripped[fm.end() :]
            inner_vis = vstrip[fm.end() :]
            close = _first_close(inner_vis, closer)
            if close != -1:
                # `name() { ...; }` on one line: the tail is the last
                # `;`-separated segment before the closer.
                close_info[(pos, _seg_index_of(vstrip, fm.end() + close))] = (
                    "func",
                    True,
                )
                segments = [s for s, _d in _segments(inner[:close]) if s.strip()]
                if segments and state[pos]:
                    _s4_check(segments[-1].strip(), lineno, func_name, findings)
            else:
                frames.append(("func", closer, True, func_name, pos,
                               inner.strip()))
                _push_inner_events(inner_vis)
            def_open = True
        elif pending_name is not None and vstrip[:1] in ("{", "("):
            # Deferred opener: `name()` / `function name` on its own line, then
            # `{`/`(` leading this one. The opener char chooses the closer.
            func_name = pending_name
            pending_name = None
            closer = "}" if vstrip[0] == "{" else ")"
            inner = stripped[1:]
            inner_vis = vstrip[1:]
            close = _first_close(inner_vis, closer)
            if close != -1:
                close_info[(pos, _seg_index_of(vstrip, 1 + close))] = (
                    "func",
                    True,
                )
                segments = [s for s, _d in _segments(inner[:close]) if s.strip()]
                if segments and state[pos]:
                    _s4_check(segments[-1].strip(), lineno, func_name, findings)
            else:
                frames.append(("func", closer, True, func_name, pos,
                               inner.strip()))
                _push_inner_events(inner_vis)
            def_open = True
        if not def_open:
            pending_name = None
            if "(" in vstrip or vstrip.startswith("function"):
                head = FUNC_HEAD_RE.match(vstrip)
                if head:
                    pending_name = head.group(1) or head.group(2)
            if frames or _FRAME_TRIG.search(vstrip):
                # `_segments` on the masked text and `_segments_pair` on the
                # raw text drop the same (empty-after-masking) segments, so si
                # aligns; pairs are built lazily only when a func pops.
                pairs: list[tuple[str, str]] | None = None
                for si, (mseg, _sd) in enumerate(_segments(vstrip)):
                    for ev, ptok in _seg_events(mseg):
                        if ev in ("{", "("):
                            frames.append(("group", "}" if ev == "{" else ")",
                                           ptok not in _SUPPRESS_AFTER,
                                           "", -1, ""))
                        elif ev == "$(":
                            frames.append(("subst", ")", True, "", -1, ""))
                        elif ev in _WORD_OPENERS:
                            frames.append(("word", _WORD_OPENERS[ev],
                                           ptok != "!", "", -1, ""))
                        else:
                            ct = ")" if ev == ")x" else ev
                            if frames and frames[-1][1] == ct:
                                fr = frames.pop()
                                if fr[0] == "func":
                                    close_info[(pos, si)] = ("func", True)
                                    if pairs is None:
                                        pairs = _segments_pair(
                                            stripped,
                                            qs_in_s[pos],
                                            qs_in_d[pos],
                                        )
                                    _pop_func_tail(fr, si, pairs, pos, lineno)
                                else:
                                    close_info[(pos, si)] = (fr[0], fr[2])

        if SET_RE.match(vstrip):
            if not quote_at[pos]:
                last_nonempty = pos
            continue

        # --- S1/S2: the capture itself must run armed --------------------------
        # `!`-negated captures never trip errexit (the negation consumes the
        # status). Reads inside a SINGLE-quoted span are data for another
        # interpreter (`sq`); inside a double-quoted span `$( )` still runs
        # under THIS shell's errexit, so those are evaluated.
        if (
            state[pos]
            and not CONTROL_PREFIX_RE.match(vstrip)
            and not vstrip.startswith("!")
        ):
            m = ASSIGN_SUBST_RE.search(stripped)
            if (
                m
                and not sqline[lead + m.start("name")]
                and not sqline[lead + m.start("body")]
            ):
                body = m.group("body")
                stages = substituted_commands(body)
                if any(first_word(s) in NONZERO_IS_AN_ANSWER for s in stages):
                    # S2 first: a `|| echo`-style guard on a command that already prints
                    # on failure is a WRONG VALUE, and reporting it as a mere abort
                    # risk would misname the defect.
                    adds_value = ADDS_A_VALUE_RE.search(vstrip)
                    if adds_value and PRINTS_ON_FAILURE_RE.search(body):
                        findings.append((lineno, "S2", stripped))
                        s1s2_positions.add(pos)
                    # `local`/`export`/... return their OWN status, so the substitution
                    # cannot abort. `... || <anything>` decides; `x=$(cmd) && next`
                    # puts the assignment in exempt non-final position;
                    # `$( ... || ... )` decides inside. The outer tail is judged on
                    # the RAW text gated by the sq mask -- `vstrip` can lose a real
                    # `||` to a quote-spanning `$(…)` relex limit, while `sq` only
                    # exempts single-quote interiors.
                    elif not m.group("decl") and not (
                        _has_unmasked_op(
                            stripped[m.end("body") :],
                            sqline[lead + m.end("body") :],
                        )
                        or re.search(r"\|\||&&", _unquoted(body))
                    ):
                        findings.append((lineno, "S1", stripped))
                        s1s2_positions.add(pos)

        # --- S3: a status read whose command already ran armed -----------------
        # EVERY read on the line is evaluated -- `echo rc=$?; rc2=$?` skips the
        # first (arg-position) and still judges the second. Reads inside a
        # single-quoted span (`sq`) are data for another interpreter.
        for anchor in READ_RE.finditer(stripped):
            if (
                sqline[lead + anchor.start()]
                or sub_masks[pos][lead + anchor.start()]
            ):
                # single-quoted interior, or inside a `$( … )` substitution --
                # either way the read does not run in this statement's flow
                continue
            before = stripped[: anchor.start()].rstrip()
            vbefore = vline[lead : lead + anchor.start()].rstrip()
            # The read's OWN statement context: the text between the last `;` and
            # the read itself. Only `;` splits statements here -- `|`, `||`, `&&`
            # and `&` belong to the command being resolved (a pipeline, an
            # operand, a `2>&1` redirect), not to statement boundaries. The
            # `;` that matters is the last UNQUOTED one (found on `vbefore`,
            # sliced back out of `before` so the check sees the real text).
            region = before[vbefore.rfind(";") + 1 :].strip()

            if "||" in region or "&&" in region:
                # The canonical `cmd || rc=$?` protection idiom and the documented
                # `cmd && rc=$?` exclusion: the read is the right-hand operand of
                # the command it reads. A `||`/`&&` BEFORE the last `;` is an
                # earlier statement (`a || b; rc=$?` -- still dead).
                continue
            if before.endswith("{"):
                # The read sits at a brace/function head on this same line
                # (`f() { rc=$?`, `{ rc=$?`) -- caller-status idiom. `${var}` and
                # `{a,b}` mid-line are not brace heads.
                continue
            r_in_s, r_in_d, r_paren = _tail_state(
                before, qs_in_s[pos], qs_in_d[pos]
            )
            if r_in_s or r_in_d or r_paren > 0:
                # The read sits inside an unclosed QUOTED STRING or `$( )`/`( )` group
                # opened on this same line: `trap 'rc=$?; ...'`, `bash -c '...'`,
                # `echo "rc=$?"`, `x=$(cmd; rc=$?; echo $rc)`. It is evaluated by a
                # different context -- the trap's fire-time shell, the -c'd
                # interpreter, the substitution -- never by this line's errexit.
                # Quoted spans are blanked first so `don't` / `"("` cannot spoof
                # the parity counts.
                continue
            if (
                region
                and not DECL_PREFIX_RE.match(region)
                and not SET_RE.match(region)
            ):
                # A word between the last `;` and the read that is not a
                # declaration prefix or a `set` statement means the read is an
                # ARGUMENT of an enclosing command (`echo rc=$?`, `env rc=$? x`)
                # or a control word's arm (`then`, `else`) -- the
                # bare-in-arguments class, deliberately scoped out. `set +e;
                # rc=$?` is NOT an argument -- it resolves through the segments.
                continue

            # Whose exit status is this? Resolve the antecedent: the last
            # non-`set` statement segment before the read on this line,
            # else the previous non-`set` logical line (back-walk). `set`
            # verdicts fold FORWARD through the segments so `set +e;
            # out=$(cmd); rc=$?` is judged disarmed -- while `cmd; set +e;
            # rc=$?` still fires, because the clear ran AFTER the armed
            # command. A `set` segment inside `$(`/`(` scopes to the group.
            segs = _segments(before, in_s=qs_in_s[pos], in_d=qs_in_d[pos])
            seg_state: list[bool] = [state[pos]] * len(segs)
            run_state = state[pos]
            clear_idx = -1  # last segment index holding a `set +e` clear
            last_idx = -1
            for idx, (seg, sdep) in enumerate(segs):
                m_seg_set = _SET_SEG_RE.match(seg)
                if m_seg_set:
                    ev = set_verdicts(m_seg_set.group(1)).get("errexit")
                    if sdep == 0 and depth_at[pos] == 0:
                        if ev is True:
                            run_state = False
                            clear_idx = idx
                        elif ev is False:
                            run_state = True
                    continue
                seg_state[idx] = run_state
                last_idx = idx

            cmd, cmd_pos, cmd_state, cand_si = None, None, run_state, 0
            if last_idx >= 0:
                # Drop trailing declaration prefixes and `set` statements --
                # they modify the READ (`cmd; local rc=$?` resolves `cmd`),
                # they are never the antecedent.
                while last_idx >= 0 and (
                    DECL_PREFIX_RE.match(segs[last_idx][0])
                    or _SET_SEG_RE.match(segs[last_idx][0])
                ):
                    last_idx -= 1
            if last_idx >= 0:
                cand = segs[last_idx][0]
                # Rejoin fragments the `;` split cut open inside `$(`/`(`:
                # `x=$(a; b); rc=$?` leaves `b)` as a phantom segment.
                while last_idx > 0 and cand.count(")") > cand.count("("):
                    last_idx -= 1
                    cand = segs[last_idx][0] + ";" + cand
                cmd, cmd_pos, cmd_state = cand, pos, seg_state[last_idx]
                cand_si = last_idx
            cleared_after = clear_idx > last_idx
            if cmd is None:
                for back in range(pos - 1, -1, -1):
                    if quote_at[back]:
                        # A line beginning inside a multi-line quote is data
                        # for another interpreter -- it cannot be the read's
                        # antecedent (the antecedent is the command whose line
                        # OPENED the quote).
                        continue
                    cand = logical[back][1].strip()
                    if not cand:
                        continue
                    c_last = _segments(cand)
                    # A `set`-led line may still carry a construct closer
                    # (`set +u; }`) -- skip it as an antecedent only when its
                    # LAST segment is the set itself.
                    if SET_RE.match(cand) and (
                        not c_last or _SET_SEG_RE.match(c_last[-1][0])
                    ):
                        continue
                    cmd, cmd_pos, cmd_state = cand, back, state[back]
                    cand_si = len(c_last) - 1
                    break

            # A resolved antecedent whose LAST `;`-segment is a compound
            # closer is the just-closed construct -- judged armed at the
            # closer's position, symmetric with the already-flagged one-line
            # `if c; then cmd; fi`. `close_info` records which frame that
            # closer popped: a function DEFINITION (`cmd; }` counts) is dropped
            # (a definition's status is boring, not dead) and a SUPPRESSED
            # construct (`! { … }`, `if { …; }; then` condition) is live, not
            # dead. When the closer's segment carries further statements
            # (`}; rest`, `fi; x`), the read is about the LAST segment.
            compound = False
            if cmd is not None:
                c_segs = _segments(cmd)
                last_ck = _closer_head(c_segs[-1][0])
                if last_ck is not None:
                    info = close_info.get((cmd_pos, cand_si))
                    if info is not None and info[0] == "func":
                        cmd = None  # function-definition close
                    elif info is None or info[1]:
                        compound = True  # armed (or untracked) construct
                elif _closer_head(c_segs[0][0]) is not None:
                    if len(c_segs) > 1:
                        cmd = c_segs[-1][0]
                    else:
                        info = close_info.get((cmd_pos, cand_si))
                        if info is not None and info[0] == "func":
                            cmd = None
                        elif info is None or info[1]:
                            compound = True

            if (
                cmd is not None
                and cmd_state               # the COMMAND ran armed -- judged at its line
                and depth_at[pos] == 0      # the read is not inside an open `$( )`/`( )`
                and cmd_pos not in s1s2_positions  # same defect, one report (S1/S2 won)
                and (compound
                     or (not is_protected(cmd)
                         and not _s3_exempt_command(cmd, depth_at[cmd_pos])))
                # A PIPESTATUS read is live unless pipefail is armed: without
                # it a pipeline's status is its LAST stage's, so the earlier
                # stages' failures never trip errexit and the read sees them.
                and not (
                    "PIPESTATUS" in stripped
                    and "|" in cmd
                    and not pipefail_at[cmd_pos]
                )
            ):
                note = ""
                if cleared_after or (
                    cmd_pos != pos and any(
                        SET_RE.match(logical[b][1].strip())
                        and set_errexit_verdict(
                            SET_RE.match(logical[b][1].strip()).group(1)
                        ) is True
                        for b in range(cmd_pos + 1, pos)
                    )
                ):
                    note = ("   [errexit cleared AFTER this command, not before it"
                            " -- the command already ran armed]")
                findings.append(
                    (lineno, "S3", cmd.strip() + note + "   << read: " + stripped)
                )
                break  # one S3 finding per line is enough

        if not quote_at[pos]:
            # A quote-interior line is data -- it can be no one's S4 tail.
            last_nonempty = pos

    return findings


def collect_targets(root: str, explicit: list[str]) -> "list[str] | None":
    if explicit:
        return explicit
    try:
        out = subprocess.run(
            ["git", "-C", root, "ls-files", "-z", "*.sh"],
            capture_output=True, text=True, check=True,
        ).stdout
    except (OSError, subprocess.CalledProcessError):
        return None
    return [os.path.join(root, p) for p in out.split("\0") if p]


def fingerprint(rel: str, code: str, text: str) -> str:
    """Baseline key: path + class + normalised source text -- deliberately NOT the line number.

    Line numbers churn on every edit above a finding, which would make the baseline produce
    spurious "new" findings for untouched code and train readers to regenerate it reflexively.
    The trade-off is explicit: an IDENTICAL new line added to an already-baselined file is
    grandfathered. That is the cheaper error -- the class this gate exists to stop recurred by
    being newly WRITTEN, and a byte-identical duplicate of an existing line is the rarest form
    of that.
    """
    return f"{rel}\t{code}\t{' '.join(text.split())}"


def load_baseline(path: str | None) -> set[str]:
    if not path or not os.path.exists(path):
        return set()
    with open(path, encoding="utf-8") as fh:
        return {ln.rstrip("\n") for ln in fh if ln.strip() and not ln.startswith("#")}


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("paths", nargs="*", help="scripts to scan (default: all tracked *.sh)")
    ap.add_argument("--root", default=".", help="repo root for the default file set")
    ap.add_argument("--baseline", help="file of grandfathered findings to suppress")
    ap.add_argument("--write-baseline", action="store_true",
                    help="rewrite --baseline from the current findings, then exit 0")
    args = ap.parse_args()

    targets = collect_targets(args.root, args.paths)
    if targets is None:
        # Collection failed (bad --root, no git). Report a failure, not an
        # empty scan -- a silently-green gate that never looked at a file is
        # the worst shape of green.
        print("lint-shell-capture-exit: could not enumerate scripts under "
              f"{args.root!r} (git ls-files failed)", file=sys.stderr)
        return 2
    if not targets:
        print("lint-shell-capture-exit: no shell scripts to scan.")
        return 0

    findings: list[tuple[str, int, str, str]] = []
    for path in targets:
        for lineno, code, text in scan(path):
            findings.append((path, lineno, code, text))

    if args.write_baseline:
        if not args.baseline:
            print("--write-baseline requires --baseline PATH", file=sys.stderr)
            return 2
        if args.paths:
            # Baseline regeneration must see the WHOLE tree -- a subset run
            # would write only those files' keys and silently truncate the
            # grandfathered set. Same refusal the sibling gate enforces.
            print("--write-baseline refuses explicit paths (would truncate "
                  "the baseline)", file=sys.stderr)
            return 2
        # set() dedup: an identical line at two sites in one file is ONE key --
        # duplicates would bloat the count and read as new entries on every diff.
        keys = sorted(
            {fingerprint(os.path.relpath(p, args.root), c, t) for p, _, c, t in findings}
        )
        with open(args.baseline, "w", encoding="utf-8") as fh:
            fh.write(
                "# lint-shell-capture-exit baseline -- grandfathered pre-existing findings.\n"
                "# Keyed by path + class + normalised text, NOT line number (see fingerprint()).\n"
                "# This file may only SHRINK. Burn-down tracker: see the gate's registration\n"
                "# in scripts/test-all.sh. Regenerating it to admit a NEW finding defeats the\n"
                "# gate -- fix the finding instead.\n"
            )
            fh.write("\n".join(keys) + "\n")
        print(f"lint-shell-capture-exit: wrote {len(keys)} baseline entries to {args.baseline}")
        return 0

    baseline = load_baseline(args.baseline)
    suppressed = 0
    kept: list[tuple[str, int, str, str]] = []
    for path, lineno, code, text in findings:
        if fingerprint(os.path.relpath(path, args.root), code, text) in baseline:
            suppressed += 1
        else:
            kept.append((path, lineno, code, text))
    findings = kept

    if not findings:
        note = f", {suppressed} baselined" if suppressed else ""
        print(f"[OK] lint-shell-capture-exit: {len(targets)} script(s) scanned, "
              f"0 new findings{note}.")
        return 0

    for path, lineno, code, text in findings:
        rel = os.path.relpath(path, args.root)
        if code == "S1":
            why = ("captures a command whose non-zero exit is a normal answer; under `set -e` "
                   "the script dies on 'no match'")
            fix = "decide what the exit means: `x=$(cmd) || true`, `x=$(cmd || echo)`, or `if x=$(cmd); then`"
        elif code == "S2":
            why = ("`grep -c` PRINTS `0` and exits 1, so this `|| echo` appends a SECOND value "
                   "-- the variable gets two lines")
            fix = "drop the `|| echo <literal>` and use `|| true`, which keeps the `0` the command already printed"
        elif code == "S3":
            why = ("this status read can never see a failure: under `set -e` the command "
                   "above aborts the script BEFORE the read runs -- it is dead code")
            fix = ("decide the status explicitly: `if cmd; then rc=0; else rc=$?; fi`, or "
                   "protect the command itself with `cmd || rc=$?`")
        else:
            why = ("this `test && action` is the function's last statement: on the false arm "
                   "the function returns the TEST's non-zero status, so a `set -e` caller "
                   "dies on a normal 'nothing to report' outcome")
            fix = ("give the tail an explicit status: append `|| true` (or `|| :`), or end "
                   "the function with a real `return`")
        print(f"{rel}:{lineno}: [{code}] {why}")
        print(f"    {text}")
        print(f"    fix: {fix}")

    print(f"\n[REJECT] lint-shell-capture-exit: {len(findings)} NEW finding(s) "
          f"across {len({f[0] for f in findings})} file(s)"
          + (f" ({suppressed} baselined)." if suppressed else "."))
    return 1


if __name__ == "__main__":
    sys.exit(main())
