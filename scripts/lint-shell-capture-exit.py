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
the site explicitly decides what a non-zero exit means. Two finding classes:

  S1 (abort)       an unprotected capture -- the script dies on a normal answer.
  S2 (double-emit) a capture protected by `|| echo <literal>` where the command already
                   PRINTS a value on failure (`grep -c`). The guard fires ON TOP of the
                   command's own output and the variable gets two lines.

WHAT IS DELIBERATELY NOT FLAGGED (each would be a false positive)
------------------------------------------------------------------
  * `if x=$(grep ...); then`      -- the condition consumes the status; errexit never fires.
  * `x=$(grep ...) || true`       -- `|| :`, `|| x=0`, `|| continue` etc. all decide.
  * `x=$(grep ... || true)`       -- decided inside the substitution.
  * `local x=$(grep ...)`         -- `local`/`export`/`declare`/`readonly` RETURN THEIR OWN
                                     status, which masks the substitution's. Not an abort
                                     risk, so not an S1. (It hides real errors, but that is
                                     shellcheck SC2155's rule, not this gate's.)
  * anything under `set +e`       -- state is tracked, not assumed.
  * scripts with no `set -e`      -- the premise does not hold.
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
    r"^\s*(if|elif|while|until|then|else|fi|do|done|case|esac|return|local\s+-r)\b"
)
HEREDOC_RE = re.compile(r"<<-?\s*(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\1")
# A decision attached to the OUTER command: `... || true`, `|| :`, `|| x=0`, `|| continue`.
OUTER_DECIDES_RE = re.compile(r"\|\|")
# `|| echo <literal>` / `|| printf <literal>` -- adds a value rather than choosing one.
ADDS_A_VALUE_RE = re.compile(r"\|\|\s*(?:echo|printf)\b")


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


def errexit_after(args: str, current: bool) -> bool:
    """Apply a `set` statement's tokens to the current errexit state."""
    state = current
    for tok in args.split():
        if tok.startswith("--"):
            continue
        if tok.startswith("-") and not tok.startswith("-o") and "e" in tok[1:]:
            state = True
        elif tok.startswith("+") and "e" in tok[1:]:
            state = False
        elif tok == "-o":
            continue
    if re.search(r"(?<![\w-])-o\s+errexit", args):
        state = True
    if re.search(r"(?<![\w-])\+o\s+errexit", args):
        state = False
    return state


def substituted_commands(body: str) -> list[str]:
    """Split a substitution body into its pipeline stages, ignoring `||`/`&&` right operands.

    Only the stages that can set the substitution's exit status matter. With `pipefail` any
    stage can; without it only the last can. This gate does not try to prove which -- it
    inspects every stage, because a repo that sets `-o pipefail` in its house preamble (this
    one does) makes every stage load-bearing.
    """
    # Anything after a `||` or `&&` is a DECISION, not the question being asked.
    head = re.split(r"\|\||&&", body)[0]
    return [seg.strip() for seg in head.split("|") if seg.strip()]


def first_word(cmd: str) -> str:
    """The command name, skipping env-var prefixes like `LC_ALL=C grep ...`."""
    for tok in cmd.split():
        if "=" in tok and not tok.startswith("-") and re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", tok):
            continue
        return os.path.basename(tok.strip("\"'"))
    return ""


def scan(path: str) -> list[tuple[int, str, str]]:
    """Return (line, code, logical_line) findings for one script."""
    try:
        raw = open(path, encoding="utf-8", errors="replace").read().split("\n")
    except OSError:
        return []

    lines = drop_heredocs(strip_comment_lines(raw))
    findings: list[tuple[int, str, str]] = []
    errexit = False

    for lineno, logical in join_continuations(lines):
        stripped = logical.strip()
        if not stripped:
            continue

        m_set = SET_RE.match(logical)
        if m_set:
            errexit = errexit_after(m_set.group(1), errexit)
            continue

        if not errexit:
            continue
        if CONTROL_PREFIX_RE.match(logical):
            continue

        m = ASSIGN_SUBST_RE.search(stripped)
        if not m:
            continue

        body = m.group("body")
        stages = substituted_commands(body)
        if not any(first_word(s) in NONZERO_IS_AN_ANSWER for s in stages):
            continue

        # S2 first: a `|| echo`-style guard on a command that already prints on failure is a
        # WRONG VALUE, and reporting it as a mere abort risk would misname the defect.
        adds_value = ADDS_A_VALUE_RE.search(stripped)
        if adds_value and PRINTS_ON_FAILURE_RE.search(body):
            findings.append((lineno, "S2", stripped))
            continue

        # `local`/`export`/... return their OWN status, so the substitution cannot abort.
        if m.group("decl"):
            continue
        # `... || <anything>` decides; `$( ... || ... )` decides inside.
        if OUTER_DECIDES_RE.search(stripped[m.end("body"):]) or re.search(r"\|\||&&", body):
            continue

        findings.append((lineno, "S1", stripped))

    return findings


def collect_targets(root: str, explicit: list[str]) -> list[str]:
    if explicit:
        return explicit
    try:
        out = subprocess.run(
            ["git", "-C", root, "ls-files", "-z", "*.sh"],
            capture_output=True, text=True, check=True,
        ).stdout
    except (OSError, subprocess.CalledProcessError):
        return []
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
        keys = sorted(
            fingerprint(os.path.relpath(p, args.root), c, t) for p, _, c, t in findings
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
        else:
            why = ("`grep -c` PRINTS `0` and exits 1, so this `|| echo` appends a SECOND value "
                   "-- the variable gets two lines")
            fix = "drop the `|| echo <literal>` and use `|| true`, which keeps the `0` the command already printed"
        print(f"{rel}:{lineno}: [{code}] {why}")
        print(f"    {text}")
        print(f"    fix: {fix}")

    print(f"\n[REJECT] lint-shell-capture-exit: {len(findings)} NEW finding(s) "
          f"across {len({f[0] for f in findings})} file(s)"
          + (f" ({suppressed} baselined)." if suppressed else "."))
    return 1


if __name__ == "__main__":
    sys.exit(main())
