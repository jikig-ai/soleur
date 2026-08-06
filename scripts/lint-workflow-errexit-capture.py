#!/usr/bin/env python3
"""Fail when a workflow `run:` step reads an exit status while errexit is still in effect.

WHY THIS EXISTS
---------------
GitHub invokes a `run:` block that declares no `shell:` key as `/usr/bin/bash -e {0}`.
Errexit is therefore ALREADY ON before the first line of the body runs, and the house-standard
opening line `set -uo pipefail` only ADDS flags -- it cannot clear one. So a body that means to
treat a command's exit code as DATA:

    terraform plan -no-color -input=false -out=tfplan
    rc=$?
    if [[ $rc -ne 0 ]]; then echo "::error::..."; fi

does not reach `rc=$?` at all when the command fails. The shell dies at the command, and every
line below it -- the rc read, the `$GITHUB_OUTPUT` write, the `::error::` annotation, the issue
filing, the email -- is unreachable. The failure is perfectly silent: the step just stops.

This class is invisible until the failure path runs, which is exactly when it must work. That is
what makes it worth a dedicated gate rather than a code-review habit.

THE MEASURED CASE FOR A MECHANICAL GATE
---------------------------------------
This defect has now shipped SIX times in this repository:

  1. reusable-release.yml            token-preflight
  2. apply-web-platform-infra.yml    GHCR restore
  3. git-data-rung2-rehearsal.yml    capture poll            (#7025, 2026-07-30)
  4. scheduled-supabase-advisor-scan.yml                     (2026-07-30)
  5. follow-through-closure-guard.yml                        (2026-07-30)
  6. scheduled-prod-version-drift.yml                        (#7304, 2026-08-06)

Occurrence 6 is the one that made the case. It is the repo's production-staleness alarm, and the
checker it calls returns 0 for the two QUIET verdicts and 1/2 for the two that ALERT -- so
errexit killed the step on exactly the two verdicts the alarm exists to raise, and let the
silent ones through. It failed 8 of 8 scheduled runs emitting zero diagnostic output while
looking, from the outside, like a monitor that simply had nothing to report.

Before occurrence 6 the repo had already accumulated four learnings and six in-workflow comments
about this exact rule, plus two hand sweeps. Occurrence 6 landed six days after the most recent
sweep. Documentation-only enforcement of a shell-semantics invariant is measurably not working;
a mechanical detector is the only intervention not yet tried. ADR-166 is the in-repo precedent
for the shape (a recurring operator-facing CI defect class earns a `scripts/lint-*` gate).

WHY NOT shellcheck / actionlint
-------------------------------
Neither models the runner-injected `-e`. Both see a standalone shell snippet with no knowledge
of how Actions invokes it, so the construct looks correct to them. `actionlint` already runs in
this repo's CI and caught none of the six.

THE RULE: ANCHOR ON THE READ, NOT ON THE ASSIGNMENT SHAPE
---------------------------------------------------------
A line that reads an exit status into a variable -- `X=$?` or `X=${PIPESTATUS[n]}` -- while
errexit is in effect is the trigger. The immediately preceding logical command is then inspected.

This wording is load-bearing and was arrived at by measurement. The obvious rule ("a
command-substitution assignment is a finding") was prototyped against the real tree and found
2 of the 17 sites, because 9 of them are BARE COMMANDS followed by `rc=$?`, not assignments.
Shipping that rule would have produced a gate passing over most of the class it was built to
catch, while reading as full coverage.

`${PIPESTATUS[n]}` is not optional either: `git-data-rung2-rehearsal.yml` (occurrence 3) and
`web-platform-release.yml` both read `rc=${PIPESTATUS[0]}` and never touch `$?`. A `$?`-only
rule is blind to one of the six occurrences that justify this gate.

The `$?` read is also what keeps the gate quiet: it fires only where the code ITSELF proves the
author expected to handle a failure. A body that never reads an exit status is not making the
mistake this gate is about.

DIRECTION OF ERROR
------------------
Prefer FALSE NEGATIVES. A missed finding leaves today's (zero) coverage unchanged. A false
positive blocks an unrelated PR, and a gate that blocks unrelated PRs gets disabled -- at which
point it protects nothing. Every exemption below is therefore deliberately generous.

Exit 0 = clean. Exit 1 = findings. Exit 2 = usage/parse error.
"""

from __future__ import annotations

import argparse
import os
import re
import sys

try:
    import yaml
except ImportError:  # pragma: no cover - PyYAML is a CI-image guarantee
    print("lint-workflow-errexit-capture: PyYAML is required", file=sys.stderr)
    sys.exit(2)


# A read of an exit status. The VALUE forms first: `$?`, `${?}`, `$PIPESTATUS`,
# `${PIPESTATUS[n]}`, each optionally wrapped in double quotes.
#
# The quoting is not a detail. An earlier revision required the identifier to be preceded by
# start-of-line, `[;&|]` or whitespace, which a `"` is none of -- so `echo "rc=$?"` was
# invisible, and TWO LIVE SITES in the scanned tree
# (`.github/workflows/fix-constraints-stage-a.yml:85` and `:139`) were being reported as
# covered while the gate could not see them. A gate certifying its own blind spot as scanned
# is the defining failure of this kind of tool.
_STATUS = r'"?(?:\$\?|\$\{\?\}|\$\{PIPESTATUS\[[@*0-9]+\]\}|\$PIPESTATUS\b)"?'

# Form A -- captured into a variable: `rc=$?`, `rc="$?"`, `rc[0]=$?`, `declare -i rc=$?`.
READ_ANCHOR_RE = re.compile(r"[A-Za-z_][A-Za-z0-9_]*(?:\[[^\]]*\])?=" + _STATUS)
# Form B -- read directly by a command or a test, with no assignment at all:
# `if [[ $? -ne 0 ]]`, `case $? in`, `echo "rc=$?" >> "$GITHUB_OUTPUT"`, `exit $?`.
# The docstring's justification for anchoring on the read -- "it fires only where the code
# ITSELF proves the author expected to handle a failure" -- applies verbatim to these, so
# excluding them was an artifact of the regex rather than a principled scope decision.
READ_BARE_RE = re.compile(r"(?:^|[;&|(\s\[])" + _STATUS)
READ_RE = re.compile(READ_ANCHOR_RE.pattern + "|" + READ_BARE_RE.pattern)

# A `set` statement. Captures the argument list so compound forms are handled by inspecting
# tokens rather than by matching a literal string.
SET_RE = re.compile(r"^\s*set\s+(.*)$")

# Openers whose exit status is consumed by the shell's own control flow, never by errexit.
CONTROL_PREFIX_RE = re.compile(r"^\s*(if|elif|while|until|then|else|fi|do|done|case|esac)\b")

HEREDOC_RE = re.compile(r"<<-?\s*(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\1")


def strip_comment_lines(body: str) -> list[str]:
    """Blank out comment lines, PRESERVING line numbering.

    Deliberately line-based: a `#` inside a string literal is not a comment. Blanking rather
    than deleting keeps every index equal to its physical offset in the body, which is what
    makes the reported line numbers correct.
    """
    out = []
    for line in body.split("\n"):
        out.append("" if line.lstrip().startswith("#") else line)
    return out


def drop_heredocs(lines: list[str]) -> list[str]:
    """Blank out heredoc bodies.

    A heredoc body is data handed to a command's stdin, not commands the step's shell executes,
    so a `rc=$?` appearing inside one is text. Quoted and unquoted alike are skipped: the
    difference is interpolation, and neither is executed by this shell.
    """
    out = list(lines)
    i = 0
    while i < len(out):
        m = _heredoc_opener(out[i])
        if m:
            term = m
            j = i + 1
            while j < len(out) and out[j].strip() != term:
                j += 1
            if j < len(out):
                # Terminator found: blank the body AND the terminator.
                for k in range(i + 1, j + 1):
                    out[k] = ""
                i = j
            # UNTERMINATED: blank NOTHING and keep scanning.
            #
            # The previous behaviour blanked every remaining line, which turned any false
            # opener into an unbounded, silent disarm of the rest of the body -- one
            # `echo "usage: send <<EOF"` and every capture below it went invisible. Failing
            # toward "scan it as code" is the fail-closed direction: at worst the gate reports
            # a finding inside heredoc data, which is loud and fixable, rather than reporting
            # clean over real code, which is not.
        i += 1
    return out


def _heredoc_opener(line: str) -> str | None:
    """Return the terminator word if this line opens a heredoc OUTSIDE quotes, else None.

    Scanning for `<<WORD` anywhere on the line matched inside string literals (`echo "usage:
    send <<EOF"`) and inside arithmetic (`mask=$(( 1 << n ))`), both of which are ordinary
    lines that then disarmed the scanner. Track quote state so only a real redirection counts.
    """
    in_single = in_double = False
    i = 0
    n = len(line)
    while i < n:
        c = line[i]
        if c == "\\" and not in_single:
            i += 2
            continue
        if c == "'" and not in_double:
            in_single = not in_single
        elif c == '"' and not in_single:
            in_double = not in_double
        elif c == "<" and not in_single and not in_double and line.startswith("<<", i):
            rest = line[i + 2 :]
            if rest.startswith("<"):  # `<<<` is a herestring, not a heredoc.
                i += 3
                continue
            m = re.match(r"-?\s*\\?(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\1", rest)
            if m:
                return m.group(2)
            # `<<` followed by an arithmetic operand (`1 << n`) is a shift, not a redirection.
            i += 2
            continue
        i += 1
    return None


def join_continuations(lines: list[str]) -> list[tuple[int, str]]:
    """Fold `\\`-continued physical lines into logical ones.

    Returns (physical_line_index_of_first_line, logical_text).

    Load-bearing, not tidiness: `scheduled-inngest-health.yml` opens `response="$(curl \\` and
    reads `curl_rc=$?` NINE physical lines later. A physical-line matcher misses that site
    entirely, and it is one of the confirmed 17.
    """
    logical: list[tuple[int, str]] = []
    buf = ""
    start = 0
    for idx, line in enumerate(lines):
        if not buf:
            start = idx
        stripped = line.rstrip()
        if stripped.endswith("\\"):
            buf += stripped[:-1] + " "
            continue
        buf += stripped
        logical.append((start, buf))
        buf = ""
    if buf:
        logical.append((start, buf))
    return logical


def clears_errexit(args: str) -> bool | None:
    """True if this `set` clears -e, False if it re-arms it, None if it says nothing about -e.

    Matching the COMPOUND forms is what makes linear tracking honest. A matcher keyed on the
    exact string `set -e` misses `set -euo pipefail`, which would let a `set +e` followed by the
    house-dominant `set -euo pipefail` read as "still cleared" while errexit is in fact back on
    -- shipping an inert fix that looks correct in the diff.

    `-o NAME` / `+o NAME` are consumed as PAIRS. Without that, `set -o errexit` -- a real re-arm
    -- parses as "says nothing" and a preceding `set +e` reads as still in effect, which is the
    same silent-cancellation hole the compound-form matching above exists to close, in its long
    form. Symmetrically `set +o errexit` is a real clear, and treating it as silent produced a
    false positive on correct code.
    """
    verdict = None
    toks = args.split()
    i = 0
    while i < len(toks):
        tok = toks[i]
        if tok in ("-o", "+o") and i + 1 < len(toks):
            if toks[i + 1] == "errexit":
                verdict = tok.startswith("+")
            i += 2
            continue
        if tok == "--":
            # Everything after `--` is a positional parameter, not an option.
            break
        if tok.startswith(("-", "+")) and not tok.startswith("--"):
            # A single-dash CHARACTER CLUSTER. `o` inside it introduces a long-option name
            # that was handled above; here it is only a cluster member.
            if "e" in tok[1:]:
                verdict = tok.startswith("+")
        i += 1
    return verdict


def shell_clears_errexit(shell: str | None) -> bool:
    """Whether an explicit `shell:` value yields a shell WITHOUT errexit.

    `shell: bash` does NOT: Actions maps it to `bash --noprofile --norc -eo pipefail {0}`.
    That is the highest-value anti-false-negative case in this gate -- writing `shell: bash`
    reads like taking control of the shell contract and changes nothing about `-e`.
    Only a custom command string that omits `-e` clears it.
    """
    if not shell:
        return False
    s = shell.strip()
    if s in ("bash", "sh", "pwsh", "python", "cmd", "powershell"):
        return False
    if "{0}" in s or s.startswith(("bash ", "sh ")):
        # A custom invocation: it clears errexit only if no -e appears among its flags.
        # `-o NAME` is consumed as a PAIR for the same reason as in clears_errexit: without it
        # `bash -o errexit {0}` read as CLEARING, and a job-level `defaults.run.shell` carrying
        # that form exempted every step in the job.
        toks = s.split()
        i = 0
        while i < len(toks):
            tok = toks[i]
            if tok == "-o" and i + 1 < len(toks):
                if toks[i + 1] == "errexit":
                    return False
                i += 2
                continue
            # Single-dash CHARACTER CLUSTERS only. A long option (`--noprofile`) or a word
            # argument is not a flag cluster, so an `e` inside `-NoProfile` or `-Verbose`
            # must not read as errexit.
            if tok.startswith("-") and not tok.startswith("--") and len(tok) > 1:
                if tok[1:].islower() and "e" in tok[1:]:
                    return False
            i += 1
        return True
    return False


def is_protected(cmd: str) -> bool:
    """Whether this command's failure is already handled, so errexit never fires on it."""
    c = cmd.strip()
    if not c:
        return True
    if CONTROL_PREFIX_RE.match(c):
        return True
    # `!`-negated commands are exempt from errexit by POSIX, so this is a real protection.
    if c.startswith("!"):
        return True
    # DELIBERATELY NOT a substring test for `||` / `&&`.
    #
    # The earlier form returned True whenever either operator appeared ANYWHERE in the command,
    # and its own comment recorded the measured contribution as ZERO additional findings. That
    # made it pure downside: it contributed nothing while making the calibration number an
    # artifact of formatting. Measured, ELEVEN of the seventeen calibration sites went invisible
    # under one ordinary edit -- `cd "$X" && bash checker.sh`, or a `bash -c "a && b"` where the
    # operator sits inside a quoted argument to another program and has no bearing on the outer
    # shell's errexit at all. It is also not even a correct approximation: under errexit
    # `a && b` DOES abort when `b` fails, so only left operands are exempt.
    #
    # The real `|| rc=$?` idiom is handled precisely at the read site (see scan_body), which is
    # where it belongs -- the protection is a property of the read's position, not of the
    # command containing an operator somewhere.
    return False


def scan_body(body: str, shell: str | None, defaults_shell: str | None) -> list[tuple[int, str]]:
    """Return (line_offset_within_body, logical_line) for each finding.

    THE STATE THAT MATTERS IS THE ONE AT THE COMMAND, NOT AT THE READ. An earlier revision
    evaluated errexit at the line carrying the read and skipped it whenever errexit was
    currently clear -- which made the single most likely mis-fix invisible:

        terraform plan -out=tfplan
        set +e                       # <- "clear errexit around the capture"
        rc=$?                        # dead code: the command already died

    The remediation text literally invites that shape, so it is what gets written next. Two
    passes: compute the state BEFORE each logical line, then judge each read against the state
    at its own command's line.
    """
    effective_shell = shell or defaults_shell
    if shell_clears_errexit(effective_shell):
        return []

    lines = drop_heredocs(strip_comment_lines(body))
    logical = join_continuations(lines)

    # --- pass 1: errexit state before each logical line -----------------------
    state: list[bool] = []
    errexit_on = True  # the runner's `-e`, inherited before line 1
    depth = 0          # unclosed `(` -- a `set +e` inside a subshell does not survive it
    for _idx, text in logical:
        state.append(errexit_on)
        m = SET_RE.match(text)
        if m:
            verdict = clears_errexit(m.group(1))
            # Only honour a CLEAR at the body's own nesting level. `set +e` inside `( … )` is
            # scoped to the subshell and does not leak out, and one inside an untaken `if`
            # branch never runs at all -- believing either disarms the gate for the whole rest
            # of the body. Refusing the exemption is the fail-CLOSED direction.
            if verdict is True and depth == 0:
                errexit_on = False
            elif verdict is False:
                errexit_on = True
        depth += text.count("(") - text.count(")")
        if depth < 0:
            depth = 0

    # --- pass 2: judge each read against the state at ITS command -------------
    findings: list[tuple[int, str]] = []
    for pos, (idx, text) in enumerate(logical):
        anchor = READ_RE.search(text)
        if not anchor:
            continue

        before = text[: anchor.start()].rstrip()

        # The canonical `cmd || rc=$?` protection idiom: the read is the right-hand operand,
        # so the command cannot trip errexit at all. Tested BEFORE any separator stripping --
        # stripping first turns `cmd ||` into `cmd |`, which then reads as unprotected.
        # Measured: that one ordering mistake produced 18 false positives across 7 files.
        if before.endswith("||") or before.endswith("&&"):
            continue

        # The same idiom with the read passed as an ARGUMENT rather than assigned:
        #   retry install_crane || degraded crane_install "$?" "…"
        # Any `||` / `&&` to the LEFT of the read on this logical line means the read lives in
        # the right-hand operand, so the left command's failure is already handled and errexit
        # never fires on it. Scoped to `before` deliberately -- the earlier `is_protected`
        # version tested the whole command string, which exempted a `bash -c "a && b"` whose
        # operator sits inside a quoted argument to another program and has no bearing on this
        # shell at all.
        if "||" in before or "&&" in before:
            continue

        # Whose exit status is this? Only a real command SEPARATOR makes the text on this line
        # the command; otherwise the read sits inside another command's arguments
        # (`echo "rc=$?"`, `if [[ $? -ne 0 ]]`) and refers to the PREVIOUS command.
        sep = re.search(r"(?:;|\|\||&&|\||&)\s*$", before)
        if before and sep:
            cmd, cmd_pos = re.sub(r"(?:;|\|\||&&|\||&)\s*$", "", before).strip(), pos
        else:
            cmd, cmd_pos = None, None
            for back in range(pos - 1, -1, -1):
                cand = logical[back][1].strip()
                if not cand or SET_RE.match(cand):
                    continue
                cmd, cmd_pos = cand, back
                break
            if cmd is None:
                continue

        if not state[cmd_pos]:
            continue  # errexit was already clear when the command ran -- genuinely protected
        if is_protected(cmd):
            continue

        note = ""
        if cmd_pos != pos and any(
            SET_RE.match(logical[b][1].strip())
            and clears_errexit(SET_RE.match(logical[b][1].strip()).group(1)) is True
            for b in range(cmd_pos + 1, pos)
        ):
            note = ("   [errexit cleared AFTER this command, not before it"
                    " — the command already ran armed]")
        findings.append((logical[cmd_pos][0], cmd.strip() + note))

    return findings


def iter_run_steps(path: str):
    """Yield (line_number_of_run_body_start, run_body, shell, defaults_shell) per step."""
    with open(path, "r", encoding="utf-8") as fh:
        raw = fh.read()
    try:
        node = yaml.compose(raw)
    except Exception as exc:
        raise ValueError(str(exc).replace("\n", " "))
    if node is None:
        return

    def scalar(n):
        return n.value if isinstance(n, yaml.ScalarNode) else None

    def mapping_items(n):
        if not isinstance(n, yaml.MappingNode):
            return []
        return [(scalar(k), v) for k, v in n.value]

    # workflow-level defaults.run.shell
    wf_defaults = None
    for k, v in mapping_items(node):
        if k == "defaults":
            for dk, dv in mapping_items(v):
                if dk == "run":
                    for rk, rv in mapping_items(dv):
                        if rk == "shell":
                            wf_defaults = scalar(rv)

    def walk(n, defaults_shell):
        if isinstance(n, yaml.MappingNode):
            items = mapping_items(n)
            keys = {k for k, _ in items}
            local_defaults = defaults_shell
            for k, v in items:
                if k == "defaults":
                    for dk, dv in mapping_items(v):
                        if dk == "run":
                            for rk, rv in mapping_items(dv):
                                if rk == "shell":
                                    local_defaults = scalar(rv)
            if "run" in keys:
                run_node = next(v for k, v in items if k == "run")
                shell_val = next((scalar(v) for k, v in items if k == "shell"), None)
                if isinstance(run_node, yaml.ScalarNode):
                    # For a BLOCK scalar (`run: |`) PyYAML anchors start_mark on the `|`
                    # indicator itself, so the body's first line is the line AFTER it; for a
                    # plain scalar (`run: echo hi`) the mark is already on the body. Getting
                    # this wrong is not cosmetic -- every reported line would point one line
                    # above the offending command, which is where its explanatory comment
                    # usually sits, so the gate would read as flagging prose.
                    base = run_node.start_mark.line + 1
                    if run_node.style in ("|", ">"):
                        base += 1
                    yield (base, run_node.value, shell_val, local_defaults)
            for _, v in items:
                yield from walk(v, local_defaults)
        elif isinstance(n, yaml.SequenceNode):
            for v in n.value:
                yield from walk(v, defaults_shell)

    yield from walk(node, wf_defaults)


def collect_targets(root: str) -> list[str]:
    targets: list[str] = []
    wf_dir = os.path.join(root, ".github", "workflows")
    if os.path.isdir(wf_dir):
        for name in sorted(os.listdir(wf_dir)):
            if name.endswith((".yml", ".yaml")):
                targets.append(os.path.join(wf_dir, name))
    # Composite actions run their `run:` bodies under the same shell contract.
    act_dir = os.path.join(root, ".github", "actions")
    if os.path.isdir(act_dir):
        for dirpath, _dirnames, filenames in os.walk(act_dir):
            for name in sorted(filenames):
                if name in ("action.yml", "action.yaml"):
                    targets.append(os.path.join(dirpath, name))
    return targets


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--root", default=".", help="repository root to scan")
    ap.add_argument("--quiet", action="store_true", help="print findings only")
    args = ap.parse_args()

    root = os.path.abspath(args.root)
    targets = collect_targets(root)
    if not targets:
        print(f"lint-workflow-errexit-capture: no workflow or action files under {root}", file=sys.stderr)
        return 2

    findings = []
    bodies = 0
    workflows = 0
    actions = 0
    for path in targets:
        rel = os.path.relpath(path, root)
        if os.path.basename(path).startswith("action."):
            actions += 1
        else:
            workflows += 1
        try:
            steps = list(iter_run_steps(path))
        except ValueError as exc:
            print(f"{rel}: could not parse as YAML: {exc}", file=sys.stderr)
            return 2
        for start_line, body, shell, defaults_shell in steps:
            bodies += 1
            for offset, cmd in scan_body(body, shell, defaults_shell):
                findings.append((rel, start_line + offset, cmd))

    if not args.quiet:
        print(
            f"lint-workflow-errexit-capture: scanned {workflows} workflow(s), "
            f"{actions} composite action(s), {bodies} run: body/bodies"
        )

    if findings:
        print("")
        print("An exit status is read while the runner's inherited errexit is still in effect.")
        print("The shell dies AT the command below, so the read -- and every line after it --")
        print("never runs. Clear errexit around the capture (`set +e` ... `set -e`), or protect")
        print("the command with `|| rc=$?`.")
        print("")
        for rel, line, cmd in findings:
            shown = cmd if len(cmd) <= 100 else cmd[:97] + "..."
            print(f"  {rel}:{line}: {shown}")
        print("")
        print(f"{len(findings)} finding(s). See ADR-170.")
        return 1

    if not args.quiet:
        print("lint-workflow-errexit-capture: clean")
    return 0


if __name__ == "__main__":
    sys.exit(main())
