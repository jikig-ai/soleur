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


# A read of an exit status into a variable. Both forms, anywhere on the logical line.
READ_RE = re.compile(r"(?:^|[;&|]|\s)\s*[A-Za-z_][A-Za-z0-9_]*=(?:\$\?|\$\{PIPESTATUS\[[0-9]+\]\})")
# The same, used to split a same-line `cmd; rc=$?` into command and read.
READ_ANCHOR_RE = re.compile(r"[A-Za-z_][A-Za-z0-9_]*=(?:\$\?|\$\{PIPESTATUS\[[0-9]+\]\})")

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
        m = HEREDOC_RE.search(out[i])
        if m:
            term = m.group(2)
            j = i + 1
            while j < len(out) and out[j].strip() != term:
                out[j] = ""
                j += 1
            if j < len(out):
                out[j] = ""
            i = j
        i += 1
    return out


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
    """
    verdict = None
    for tok in args.split():
        if tok.startswith(("-", "+")) and not tok.startswith("--"):
            flags = tok[1:]
            if flags in ("o", "e") and tok.startswith("-") and flags == "o":
                continue
            if "e" in flags:
                verdict = tok.startswith("+")
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
        for tok in s.split():
            if tok.startswith("-") and not tok.startswith("--") and "e" in tok[1:]:
                return False
        return True
    return False


def is_protected(cmd: str) -> bool:
    """Whether this command's failure is already handled, so errexit never fires on it."""
    c = cmd.strip()
    if not c:
        return True
    if CONTROL_PREFIX_RE.match(c):
        return True
    # `|| true`, `|| rc=$?`, `|| VAR=...`, `|| { ... }` -- any right-hand operand at all.
    # Measured contribution over the whole tree: ZERO additional findings, because the
    # read-anchor already excludes these (a `|| rc=$?` line IS the read). Kept as cheap
    # defence-in-depth; deliberately NOT claimed as load-bearing.
    if "||" in c:
        return True
    if "&&" in c:
        return True
    return False


def scan_body(body: str, shell: str | None, defaults_shell: str | None) -> list[tuple[int, str]]:
    """Return (line_offset_within_body, logical_line) for each finding."""
    effective_shell = shell or defaults_shell
    if shell_clears_errexit(effective_shell):
        return []

    lines = drop_heredocs(strip_comment_lines(body))
    logical = join_continuations(lines)

    findings: list[tuple[int, str]] = []
    errexit_on = True  # the runner's `-e`, inherited before line 1

    for pos, (idx, text) in enumerate(logical):
        # Track `set` linearly BEFORE evaluating this line, so a clear on the same logical line
        # as a read still counts, and a re-arm above a later capture does not protect it.
        m = SET_RE.match(text)
        if m:
            verdict = clears_errexit(m.group(1))
            if verdict is True:
                errexit_on = False
            elif verdict is False:
                errexit_on = True
            continue

        if not errexit_on:
            continue
        if not READ_RE.search(text):
            continue

        anchor = READ_ANCHOR_RE.search(text)
        if not anchor:
            continue

        # The command whose status is being read: whatever precedes the read on this logical
        # line, or -- if the read stands alone -- the previous logical line.
        before = text[: anchor.start()].rstrip()

        # THE READ IS THE RIGHT-HAND OPERAND -- i.e. this is the canonical `cmd || rc=$?`
        # protection idiom, and the command cannot trip errexit at all. Test this BEFORE
        # stripping any separator: stripping first turns `cmd ||` into `cmd |`, which then
        # fails the `||`-in-command test and reports the SAFE idiom as a finding. Measured:
        # that single ordering mistake produced 13 false positives across the tree, including
        # every site in the two workflows independently verified as correctly protected.
        if before.endswith("||") or before.endswith("&&"):
            continue

        before = re.sub(r"[;&|]\s*$", "", before).strip()
        if before:
            cmd = before
            cmd_idx = idx
        else:
            prev = None
            for back in range(pos - 1, -1, -1):
                cand = logical[back][1].strip()
                if cand and not SET_RE.match(cand):
                    prev = logical[back]
                    break
            if prev is None:
                continue
            cmd, cmd_idx = prev[1], prev[0]

        if is_protected(cmd):
            continue
        findings.append((cmd_idx, cmd.strip()))

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
