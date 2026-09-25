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
  S4 (leak tail)   a function's last statement is `(( expr )) && act` or
                   `[ expr ]`/`[[ expr ]]`/`test expr && act` with no `||` arm: the
                   false arm returns the TEST's non-zero status to a `set -e` caller,
                   and a normal "nothing to report" outcome reads as a crash.

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
  * Function bodies are found by `name() {` / `function name` openers and `}`-ONLY
    closers; a `cmd; }` sharing the tail's line is a miss, `name() (`
    paren-bodied functions are never tracked for S4, and a `})`-form close is
    never a pop (the function simply stays open).
  * `depth` counts raw `(`/`)` characters; pathological paren text (case-arm heads
    inside multi-line `$( )`, parens in literals) can skew it. Comments and heredoc
    bodies are already blanked before counting.
  * A `}`-ONLY line inside a function closes the innermost tracked `{` group; a
    `{`-bearing line whose closer shares a line with other text can still mis-pop.
    A `{`-grouped command as the read's antecedent (`{ cmd; rc=$?; }`) is a miss.
  * A `set` line inside a multi-line SINGLE-quoted string (`bash -c 'set -e; ...'`)
    still spoofs the state model -- quote context is checked per-line, not across
    lines.
  * The statement-segment model splits only on `;`. `x=pre$?` (literal prefix)
    under-matches; a pipeline as the antecedent is reported whole (`a | b`) rather
    than per-stage.
  * `PIPESTATUS` reads after a pipeline are judged live when `set -o pipefail` is
    not armed at the command's line -- the pipeline's status is then its last
    stage's, so earlier stages' failures never trip errexit.
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
PRINTS_ON_FAILURE_RE = re.compile(r"\bgrep\s+(?:-\w*\s+)*-\w*c|\bgrep\s+(?:-\w*\s+)*--count")

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
    r"""(?P<q>["']?)\$\((?P<body>.*)\)(?P=q)(?P<tail>\s*(?:\|\||&&)\s*\S.*)?\s*$"""
)

SET_RE = re.compile(r"^\s*set\s+(.*)$")
CONTROL_PREFIX_RE = re.compile(
    r"^\s*(if|elif|while|until|then|else|fi|do|done|case|esac|for|select"
    r"|return|exit|break|continue|local\s+-r)\b"
)
HEREDOC_RE = re.compile(r"<<-?\s*(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\1")
# A decision attached to the OUTER command: `... || true`, `|| :`, `|| x=0`, `|| continue`.
OUTER_DECIDES_RE = re.compile(r"\|\|")
# `|| echo <literal>` / `|| printf <literal>` -- adds a value rather than choosing one.
ADDS_A_VALUE_RE = re.compile(r"\|\|\s*(?:echo|printf)\b")

# A read of an exit status, captured into a variable. The VALUE forms: `$?`, `${?}`,
# `$PIPESTATUS`, `${PIPESTATUS[n]}`, each optionally DOUBLE-quoted. The NAME side
# covers indexed and attributed forms alike: `rc=$?`, `rc="$?"`, `rc[0]=$?`,
# `declare -i rc=$?`, `local rc=$?`. A SINGLE-quoted value (`rc='$?'`) is a literal
# two-character string, not a read, and is correctly not matched.
#
# This is the ASSIGNMENT anchor only. Bare in-argument reads (`echo "rc=$?"`,
# `[[ $? -ne 0 ]]`, `exit $?`) are real but noisier (`exit $?` is idiomatic) and stay
# scoped out -- see the docstring's WHAT IS DELIBERATELY NOT FLAGGED.
_STATUS = r'"?(?:\$\?|\$\{\?\}|\$\{PIPESTATUS\[[@*a-zA-Z0-9_]+\]\}|\$PIPESTATUS\b)"?'
READ_RE = re.compile(r"[A-Za-z_][A-Za-z0-9_]*(?:\[[^\]]*\])?=" + _STATUS)

# A `local`/`declare`/`typeset`/`readonly`/`export` prefix on the read itself -- a
# modifier of the assignment, not a command whose status the read is about.
DECL_PREFIX_RE = re.compile(
    r"^(?:local|declare|typeset|readonly|export)(?:\s+-[A-Za-z]+)*\s*$"
)

# A function opener: `name() {`, `function name {`, `function name() {`. The group
# carries the function name for S4's predicate-name exemption.
FUNC_OPEN_RE = re.compile(
    r"^\s*(?:(?:function\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*\(\s*\)"
    r"|function\s+([A-Za-z_][A-Za-z0-9_]*))\s*\{"
)

# A line that is ONLY a closing brace -- the S4 function-body heuristic's closer. A
# `cmd; }` sharing the tail's line is a documented miss (see the docstring).
BRACE_CLOSE_RE = re.compile(r"^}\s*$")

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
        # Only opens a heredoc if the `<<` is not itself inside a comment we already blanked.
        m = HEREDOC_RE.search(line)
        if m and not line.lstrip().startswith("#"):
            terminator = m.group(2)
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
            if cluster.endswith("o") and i + 1 < len(toks):
                name = toks[i + 1]
                if name in ("errexit", "pipefail"):
                    out[name] = sign
                i += 2
                cluster = cluster[:-1]
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


def _unquoted(text: str) -> str:
    """Quoted spans blanked, so `||`/`&&`/`|` inside `'...'`/`"..."` are not
    read as operators. A `\\` inside double quotes escapes the next char; a
    lone unclosed quote blanks to EOL -- both documented limits."""
    out = []
    i = 0
    in_s = in_d = False
    while i < len(text):
        ch = text[i]
        if ch == "\\" and in_d and i + 1 < len(text):
            out.append(" ")
            i += 2
            continue
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


def substituted_commands(body: str) -> list[str]:
    """Split a substitution body into its pipeline stages, ignoring `||`/`&&` right operands.

    Only the stages that can set the substitution's exit status matter. With `pipefail` any
    stage can; without it only the last can. This gate does not try to prove which -- it
    inspects every stage, because a repo that sets `-o pipefail` in its house preamble (this
    one does) makes every stage load-bearing.
    """
    # Anything after a `||` or `&&` is a DECISION, not the question being asked.
    # Operator chars inside quotes are not operators: `grep 'a||b'` is one stage.
    head = re.split(r"\|\||&&", _unquoted(body))[0]
    return [seg.strip() for seg in head.split("|") if seg.strip()]


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
    if CONTROL_PREFIX_RE.match(c):
        return True
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


def _s3_exempt_command(cmd: str) -> bool:
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
      * a `trap`/`eval`-family line -- a read inside its string argument is evaluated
        by a different context (the trap's fire-time status, not this line's);
      * a case-arm head (`start)`, `stop|restart)`, `*)`) -- an unmatched close-paren,
        not a command. The paren-count check keeps `x=$(cmd)` (balanced) out of this.
    """
    c = cmd.strip()
    if FUNC_OPEN_RE.match(c):
        return True
    if c.startswith(("{", "}")) or c.endswith("{"):
        return True
    if re.match(r"^\S+\)", c) and c.count("(") < c.count(")"):
        return True
    if first_word(c) in ("trap", "eval"):
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
        if "||" in act:
            return
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

    Two passes, ported from lint-workflow-errexit-capture.py's scan_body(): pass 1
    computes the errexit state and unclosed-paren depth BEFORE each logical line;
    pass 2 judges each construct against the state at ITS line -- the state at the
    COMMAND's line, not at the read's, because `cmd` then `set +e` then `rc=$?` is the
    canonical mis-fix and judging at the read would make it invisible.
    """
    try:
        raw = open(path, encoding="utf-8", errors="replace").read().split("\n")
    except OSError:
        return []

    lines = drop_heredocs(strip_comment_lines(raw))
    logical = join_continuations(lines)

    # --- pass 1: errexit/pipefail state and paren depth before each line ------
    state: list[bool] = []
    pipefail_at: list[bool] = []
    depth_at: list[int] = []
    errexit = False
    pipefail = False
    depth = 0  # unclosed `(` -- a `set` inside `$( )`/`( )` is scoped to the subshell
    for _idx, text in logical:
        state.append(errexit)
        pipefail_at.append(pipefail)
        depth_at.append(depth)
        m = SET_RE.match(text)
        if m and depth == 0:
            # Honour `set` verdicts only at this nesting level: a `set` inside a
            # subshell or command substitution is scoped to it and never leaks
            # out -- the same rule for clears AND arms.
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
        depth += text.count("(") - text.count(")")
        if depth < 0:
            depth = 0

    # --- pass 2: S1/S2 captures, S3 dead reads, S4 leaking tails ---------------
    findings: list[tuple[int, str, str]] = []
    s1s2_positions: set[int] = set()  # logical positions that already emitted S1/S2
    # (name, open_pos, inner_group_depth, same-line body prefix)
    func_stack: list[tuple[str, int, int, str]] = []
    last_nonempty: int | None = None

    for pos, (lineno, text) in enumerate(logical):
        stripped = text.strip()
        if not stripped:
            continue

        if SET_RE.match(text):
            last_nonempty = pos
            continue

        # --- function-boundary tracking for S4 --------------------------------
        # This bookkeeping is ADDITIVE: opener and group lines still run the
        # S1/S2/S3 checks below (`f() { x=$(grep p f); }` is an S1 on any tree).
        fm = FUNC_OPEN_RE.match(stripped)
        if fm:
            func_name = fm.group(1) or fm.group(2)
            inner = stripped[fm.end():]
            close = inner.rfind("}")
            if close != -1:
                # `name() { ...; }` on one line: the tail is the last `;`-separated
                # segment before the closer. `;` inside the segment text is a
                # documented heuristic limit.
                segments = [s for s in inner[:close].split(";") if s.strip()]
                if segments and state[pos]:
                    _s4_check(segments[-1].strip(), lineno, func_name, findings)
            else:
                func_stack.append((func_name, pos, 0, inner.strip()))
        elif func_stack and stripped.endswith("{"):
            # An inner `{` group opener inside the body (`cmd || {`, a bare `{`):
            # its `}` closes the GROUP, not the function.
            n, o, g, s0 = func_stack[-1]
            func_stack[-1] = (n, o, g + 1, s0)
        elif BRACE_CLOSE_RE.match(stripped) and func_stack:
            func_name, open_pos, groups, open_body = func_stack[-1]
            if groups > 0:
                func_stack[-1] = (func_name, open_pos, groups - 1, open_body)
            else:
                func_stack.pop()
                # The tail is the last logical line before this `}` -- judged against
                # the state at ITS line, so a `set +e` region disarms it honestly.
                if last_nonempty is not None and state[last_nonempty]:
                    t_lineno, t_text = logical[last_nonempty]
                    tail = t_text.strip()
                    if last_nonempty == open_pos:
                        # Two-line `f() { tail` form: the tail shares the opener
                        # line; check the part AFTER the `{`.
                        tail = open_body
                    _s4_check(tail, t_lineno, func_name, findings)

        # --- S1/S2: the capture itself must run armed --------------------------
        if state[pos] and not CONTROL_PREFIX_RE.match(text):
            m = ASSIGN_SUBST_RE.search(stripped)
            if m:
                body = m.group("body")
                stages = substituted_commands(body)
                if any(first_word(s) in NONZERO_IS_AN_ANSWER for s in stages):
                    # S2 first: a `|| echo`-style guard on a command that already prints
                    # on failure is a WRONG VALUE, and reporting it as a mere abort
                    # risk would misname the defect.
                    adds_value = ADDS_A_VALUE_RE.search(stripped)
                    if adds_value and PRINTS_ON_FAILURE_RE.search(body):
                        findings.append((lineno, "S2", stripped))
                        s1s2_positions.add(pos)
                    # `local`/`export`/... return their OWN status, so the substitution
                    # cannot abort. `... || <anything>` decides; `$( ... || ... )`
                    # decides inside.
                    elif not m.group("decl") and not (
                        OUTER_DECIDES_RE.search(stripped[m.end("body"):])
                        or re.search(r"\|\||&&", _unquoted(body))
                    ):
                        findings.append((lineno, "S1", stripped))
                        s1s2_positions.add(pos)

        # --- S3: a status read whose command already ran armed -----------------
        anchor = READ_RE.search(stripped)
        if anchor:
            before = stripped[: anchor.start()].rstrip()
            # The read's OWN statement context: the text between the last `;` and
            # the read itself. Only `;` splits statements here -- `|`, `||`, `&&`
            # and `&` belong to the command being resolved (a pipeline, an
            # operand, a `2>&1` redirect), not to statement boundaries.
            region = before.split(";")[-1].strip()

            if "||" in region or "&&" in region:
                # The canonical `cmd || rc=$?` protection idiom and the documented
                # `cmd && rc=$?` exclusion: the read is the right-hand operand of
                # the command it reads. A `||`/`&&` BEFORE the last `;` is an
                # earlier statement (`a || b; rc=$?` -- still dead).
                pass
            elif before.endswith("{"):
                # The read sits at a brace/function head on this same line
                # (`f() { rc=$?`, `{ rc=$?`) -- caller-status idiom. `${var}` and
                # `{a,b}` mid-line are not brace heads.
                pass
            elif (
                before.count("'") % 2 == 1 or before.count('"') % 2 == 1
                or before.count("(") > before.count(")")
            ):
                # The read sits inside an unclosed QUOTED STRING or `$( )`/`( )` group
                # opened on this same line: `trap 'rc=$?; ...'`, `bash -c '...'`,
                # `echo "rc=$?"`, `x=$(cmd; rc=$?; echo $rc)`. It is evaluated by a
                # different context -- the trap's fire-time shell, the -c'd
                # interpreter, the substitution -- never by this line's errexit.
                pass
            elif (
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
                pass
            else:
                # Whose exit status is this? Resolve the antecedent: the last
                # non-`set` statement segment before the read on this line,
                # else the previous non-`set` logical line (back-walk). `set`
                # verdicts fold FORWARD through the segments so `set +e;
                # out=$(cmd); rc=$?` is judged disarmed -- while `cmd; set +e;
                # rc=$?` still fires, because the clear ran AFTER the armed
                # command.
                segs = [s.strip() for s in before.split(";") if s.strip()]
                seg_state: list[bool] = [state[pos]] * len(segs)
                run_state = state[pos]
                clear_idx = -1  # last segment index holding a `set +e` clear
                last_idx = -1
                for idx, seg in enumerate(segs):
                    m_seg_set = SET_RE.match(seg)
                    if m_seg_set:
                        ev = set_verdicts(m_seg_set.group(1)).get("errexit")
                        if ev is True and depth_at[pos] == 0:
                            run_state = False
                            clear_idx = idx
                        elif ev is False:
                            run_state = True
                        continue
                    seg_state[idx] = run_state
                    last_idx = idx

                cmd, cmd_pos, cmd_state = None, None, run_state
                if last_idx >= 0:
                    # Drop a trailing declaration prefix -- it modifies the READ
                    # (`cmd; local rc=$?` resolves `cmd`, not the line above).
                    while last_idx >= 0 and DECL_PREFIX_RE.match(segs[last_idx]):
                        last_idx -= 1
                if last_idx >= 0:
                    cand = segs[last_idx]
                    # Rejoin fragments the `;` split cut open inside `$(`/`(`:
                    # `x=$(a; b); rc=$?` leaves `b)` as a phantom segment.
                    while last_idx > 0 and cand.count(")") > cand.count("("):
                        last_idx -= 1
                        cand = segs[last_idx] + ";" + cand
                    cmd, cmd_pos, cmd_state = cand, pos, seg_state[last_idx]
                cleared_after = clear_idx > last_idx
                if cmd is None:
                    for back in range(pos - 1, -1, -1):
                        cand = logical[back][1].strip()
                        if not cand or SET_RE.match(cand):
                            continue
                        cmd, cmd_pos, cmd_state = cand, back, state[back]
                        break

                if (
                    cmd is not None
                    and cmd_state               # the COMMAND ran armed -- judged at its line
                    and depth_at[pos] == 0      # the read is not inside an open `$( )`/`( )`
                    and cmd_pos not in s1s2_positions  # same defect, one report (S1/S2 won)
                    and not is_protected(cmd)
                    and not _s3_exempt_command(cmd)
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
