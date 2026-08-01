#!/usr/bin/env python3
"""Fail when a workflow `run:` step reads a variable nothing in scope ever sets (#7136).

WHY THIS EXISTS. `.github/workflows/web-platform-release.yml`'s "Email the operator
(release did NOT reach production)" step read `${R_DEPLOY}`, but `R_DEPLOY` was declared
in the `env:` of a DIFFERENT step. Step-level `env:` does not cross step boundaries, so
under `set -u` bash killed the step at that line -- BEFORE the curl that sends the mail.
Every failed release since #7097 went unannounced, and the downstream "mirror to Sentry"
step was `skipped` (it inherits `success()`), so both alert channels died together.

This class is invisible until the failure path runs, which is exactly when it must work.
That is what makes it worth a dedicated gate rather than a code-review habit.

WHY NOT SHELLCHECK. actionlint already pipes every `run:` body through shellcheck, and
shellcheck has SC2154 ("referenced but not assigned") -- it does not fire here, by design:
SC2154 deliberately exempts ALL_CAPS names as presumed-environment, and shellcheck cannot
see the workflow's `env:` blocks at all. Measured on the pre-fix step body: zero findings.
The workflow-awareness is the whole point; there is no actionlint setting that buys it.

THE RULE. Within one `run:` step, an ALL_CAPS shell variable reference is a finding when
ALL of these hold:
  * it is never guarded (`${X:-}` / `${X-}` / `${X:+}` / `${X:?}`) ANYWHERE in that step;
  * it is not declared in the step's, job's, or workflow's `env:`;
  * it is not assigned anywhere in that step's own body;
  * it was not exported to `$GITHUB_ENV` by an EARLIER step of the same job;
  * it is not runner-provided (GITHUB_*, RUNNER_*, HOME, ...).

Each exemption is measured, not assumed -- counts are against the 20 workflows on main at
the time of writing, and each one is the difference between a usable gate and noise:

  restrict to ALL_CAPS ............ ~977 findings without it (jq --arg names, lowercase
                                     locals -- shellcheck's SC2154 domain, not ours)
  $GITHUB_ENV carry-forward .......   41 findings without it (the standard cross-step export)
  "guarded anywhere" exemption ....   16 findings without it (`[[ -n "${X:-}" ]] || exit 1`
                                     followed by a bare `${X}` is correct, deliberate code)
  quote/escape lexer ..............    6 findings without it (literal `$VAR` text inside
                                     single quotes or written `\\$VAR` -- never expanded)

With all four, the sweep over main returns EXACTLY ONE finding: the R_DEPLOY bug. So this
ships fail-closed with no allowlist and no highwater baseline -- if it ever prints anything
again, that is a new defect, not accumulated debt.

DIRECTION OF ERROR. The lexer can mis-track quote state inside an unquoted heredoc and
under-report. That is the acceptable direction: a false negative leaves today's (zero)
coverage unchanged, while a false positive would block an unrelated PR and get the gate
disabled. Findings are precise or absent, never approximate.

Usage:  python3 scripts/lint-workflow-step-env-refs.py [<path>...]   # default: .github/workflows/*.yml
Exit:   0 = clean, 1 = findings or nothing scanned.
"""

from __future__ import annotations

import glob
import re
import sys

import yaml

# GitHub expression -- must go before any shell parsing, since `${{` starts with `${`.
GH_EXPR = re.compile(r"\$\{\{.*?\}\}", re.DOTALL)
# A QUOTED heredoc body ( <<'EOF' / <<"EOF" ) is literal: bash expands nothing inside it.
QUOTED_HEREDOC = re.compile(r"<<-?\s*(['\"])(\w+)\1(.*?)^\s*\2\s*$", re.DOTALL | re.MULTILINE)

BRACED_REF = re.compile(r"\$\{([A-Za-z_][A-Za-z0-9_]*)([^}]*)\}")
BARE_REF = re.compile(r"\$([A-Za-z_][A-Za-z0-9_]*)")
# Any `NAME=` / `NAME+=` / `NAME[` at a position where it can be an assignment. Deliberately
# over-approximating: counting a non-assignment as an assignment only SUPPRESSES a finding,
# and this gate prefers silence to noise (see DIRECTION OF ERROR above).
ASSIGNMENT = re.compile(r"(?<![\w$.-])([A-Za-z_][A-Za-z0-9_]*)\s*(?:\+?=|\[)")
FOR_LOOP_VAR = re.compile(r"\bfor\s+([A-Za-z_][A-Za-z0-9_]*)\s+in\b")
READ_VARS = re.compile(r"\bread\s+(?:-\w+\s+)*([A-Za-z_][A-Za-z0-9_ ]*)")
PRINTF_VAR = re.compile(r"\bprintf\s+-v\s+([A-Za-z_][A-Za-z0-9_]*)")
# `mapfile -t -d '' ARR < …`: take the whole line and harvest every identifier on it, rather
# than modelling the option grammar. A pattern like `(?:-\w+\s+\S*\s*)*` for the flags is
# exponentially backtrackable (CodeQL py/redos, flagged on this file's first revision) —
# `\S*` can consume the next `-flag`, so each option is parseable two ways. Since counting a
# non-assignment as assigned only SUPPRESSES a finding, the over-broad linear scan is both
# safer and simpler than a precise ambiguous one.
MAPFILE_LINE = re.compile(r"\b(?:mapfile|readarray)\b([^\n]*)")
IDENTIFIER = re.compile(r"(?<![\w$-])([A-Za-z_][A-Za-z0-9_]*)")

ENV_STYLE_NAME = re.compile(r"[A-Z][A-Z0-9_]*")
# `${X:-}`, `${X-}`, `${X:+}`, `${X:=}`, `${X:?}` all mean "the author considered unset".
GUARD_PREFIXES = (":-", ":=", ":+", ":?", "-", "+", "?")

# Provided by the runner or the shell itself; never declared in `env:`.
RUNNER_PROVIDED = re.compile(
    r"^(GITHUB_|RUNNER_|ACTIONS_|INPUT_|BASH_|CI$|HOME$|PATH$|PWD$|OLDPWD$|USER$|SHELL$|"
    r"HOSTNAME$|TMPDIR$|LANG$|LC_|TERM$|IFS$|RANDOM$|LINENO$|PPID$|UID$|EUID$|OSTYPE$|"
    r"HOSTTYPE$|SECONDS$|FUNCNAME$|PIPESTATUS$|REPLY$|OPTARG$|OPTIND$|_$|EDITOR$|TZ$)"
)

SHELLS_WE_PARSE = (None, "bash", "sh")


def strip_unexpanded(body: str) -> str:
    """Drop the text bash would never expand: single-quoted regions and backslash escapes.

    Without this, a literal `\\$HCLOUD_TOKEN` inside an error message, a `$BS_TABLE` inside a
    single-quoted SQL string, and a `$CF_ACCOUNT_ID` inside a single-quoted printf format all
    read as live references. Tracking double-quote state matters too: an apostrophe inside
    "don't" must not open a single-quoted region.
    """
    out: list[str] = []
    i, n = 0, len(body)
    in_single = in_double = False
    while i < n:
        ch = body[i]
        if in_single:
            if ch == "'":
                in_single = False
            i += 1
            continue
        if ch == "\\":  # escaped char is literal; drop the pair
            out.append(" ")
            i += 2
            continue
        if ch == "'" and not in_double:
            in_single = True
            i += 1
            continue
        if ch == '"':
            in_double = not in_double
            i += 1
            continue
        out.append(ch)
        i += 1
    return "".join(out)


def strip_comments(body: str) -> str:
    return "\n".join(ln for ln in body.split("\n") if not ln.lstrip().startswith("#"))


def env_keys(*scopes) -> set[str]:
    names: set[str] = set()
    for scope in scopes:
        if isinstance(scope, dict):
            names |= {str(k) for k in scope}
    return names


def assigned_names(body: str) -> set[str]:
    names: set[str] = set()
    for rx in (ASSIGNMENT, FOR_LOOP_VAR, PRINTF_VAR):
        names |= set(rx.findall(body))
    for group in READ_VARS.findall(body):
        names |= set(group.split())
    for tail in MAPFILE_LINE.findall(body):
        names |= set(IDENTIFIER.findall(tail))
    return names


def references(body: str) -> dict[str, bool]:
    """name -> guarded-anywhere-in-this-step."""
    refs: dict[str, bool] = {}
    for name, suffix in BRACED_REF.findall(body):
        guarded = suffix.startswith(GUARD_PREFIXES)
        refs[name] = refs.get(name, False) or guarded
    for name in BARE_REF.findall(body):
        refs.setdefault(name, False)  # never upgrades a guard already recorded
    return refs


def scan_workflow(path: str) -> list[tuple[str, str, str, str]]:
    with open(path, encoding="utf-8") as fh:
        doc = yaml.safe_load(fh)
    if not isinstance(doc, dict):
        return []

    workflow_env = doc.get("env")
    findings: list[tuple[str, str, str, str]] = []

    for job_id, job in (doc.get("jobs") or {}).items():
        if not isinstance(job, dict):
            continue
        job_env = job.get("env")
        # Names an EARLIER step in this job exported via `$GITHUB_ENV`. Same-step writes do
        # not count: GITHUB_ENV takes effect in the NEXT step, not the one doing the writing.
        carried: set[str] = set()

        for step in job.get("steps") or []:
            if not isinstance(step, dict) or "run" not in step:
                continue
            if step.get("shell") not in SHELLS_WE_PARSE:
                continue

            body = step["run"]
            code = strip_unexpanded(strip_comments(QUOTED_HEREDOC.sub(" ", GH_EXPR.sub(" ", body))))
            declared = env_keys(workflow_env, job_env, step.get("env")) | carried
            local = assigned_names(code)

            for name, guarded in sorted(references(code).items()):
                if not ENV_STYLE_NAME.fullmatch(name):
                    continue
                if guarded or name in declared or name in local or RUNNER_PROVIDED.match(name):
                    continue
                findings.append((path, job_id, str(step.get("name", "<unnamed step>")), name))

            if "GITHUB_ENV" in body:
                carried |= assigned_names(GH_EXPR.sub(" ", body))

    return findings


def main(argv: list[str]) -> int:
    targets = argv[1:] or sorted(glob.glob(".github/workflows/*.yml"))
    if not targets:
        # A clean sweep of nothing is indistinguishable from success, and reads as safety.
        # Same failure shape scripts/lint-workflows.sh guards against.
        print(
            "lint-workflow-step-env-refs: no workflow files found from "
            f"{__import__('os').getcwd()} — refusing to report a clean sweep of nothing.",
            file=sys.stderr,
        )
        return 1

    findings: list[tuple[str, str, str, str]] = []
    for path in targets:
        try:
            findings += scan_workflow(path)
        except (OSError, yaml.YAMLError) as exc:
            # Fail closed: an unparseable workflow is not a passing workflow.
            print(f"lint-workflow-step-env-refs: cannot parse {path}: {exc}", file=sys.stderr)
            return 1

    if not findings:
        print(f"lint-workflow-step-env-refs: 0 findings across {len(targets)} workflow file(s).")
        return 0

    print(
        f"lint-workflow-step-env-refs: {len(findings)} finding(s) — a step reads a variable "
        "that nothing in scope sets.\n",
        file=sys.stderr,
    )
    for path, job_id, step_name, name in findings:
        print(f"  {path}: job '{job_id}', step '{step_name}': ${name}", file=sys.stderr)
    print(
        "\nUnder `set -u` this kills the step at that line. Declare the variable in THIS "
        "step's own `env:` (step-level `env:` does not cross step boundaries), or guard the "
        "expansion as ${NAME:-} if being unset is legitimate.",
        file=sys.stderr,
    )
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
