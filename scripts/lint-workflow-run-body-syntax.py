#!/usr/bin/env python3
"""Every `run:` body in every workflow must PARSE as bash.

WHY THIS EXISTS AS ITS OWN LINT

`scripts/lint-workflows.sh` runs actionlint, and actionlint DOES flag this class
(SC1073/SC1072). But that script treats `rc=1` as an accepted outcome -- the finding
census and ratchet are tracked in #7042 -- so it exits 0 with the error printed and
CI stays green. A gate whose failure mode is "prints the finding and passes" cannot
close a class.

THE DEFECT THAT MOTIVATED IT (#7695 review)

Three lines in apply-web-platform-infra.yml's `inngest_volume_recut` "Dispatch
summary" step used the `'"'"'` idiom -- which escapes an apostrophe inside a
SINGLE-quoted string -- inside DOUBLE-quoted strings, where a bare `'` is already
literal. The sequence closed the double quote and left one dangling to EOF, so the
ENTIRE step body failed to parse:

    line 22: unexpected EOF while looking for matching `"'

Nothing in it executed -- not even the `>> "$GITHUB_STEP_SUMMARY"` redirect. The step
is `if: always()`, and its failure branch is the only place the recut's recovery route
is written into the run. A half-failed recut destroys the sole copy of the Inngest AOF
and would have printed nothing about how to recover.

A syntax error is not a style finding: the body cannot run at all, and a `run:` body
that cannot run is indistinguishable from one that ran and did nothing.

SCOPE AND LIMITS

`bash -n` parses; it does not execute, so `${{ }}` expressions are left as-is. GitHub
substitutes those BEFORE bash sees them, so a body that only parses after substitution
is out of scope here -- this catches the far more common case of unbalanced quotes in
literal text. Bodies whose `shell:` is explicitly not bash/sh are skipped.
"""
import subprocess
import sys
from pathlib import Path

import yaml

SKIP_SHELLS = {"python", "pwsh", "powershell", "cmd", "node", "ruby"}


def main() -> int:
    roots = [Path(a) for a in sys.argv[1:]] or [Path(".github/workflows")]
    files: list[Path] = []
    for r in roots:
        files.extend(sorted(r.rglob("*.yml")) + sorted(r.rglob("*.yaml"))) if r.is_dir() else files.append(r)

    checked = 0
    findings = 0
    for f in files:
        try:
            doc = yaml.safe_load(f.read_text())
        except Exception as exc:  # noqa: BLE001 - a malformed workflow is its own loud failure
            print(f"{f}: SKIPPED (YAML did not parse: {exc})", file=sys.stderr)
            continue
        if not isinstance(doc, dict):
            continue
        jobs = doc.get("jobs") or {}
        if not isinstance(jobs, dict):
            continue
        for job_name, job in jobs.items():
            if not isinstance(job, dict):
                continue
            default_shell = ((job.get("defaults") or {}).get("run") or {}).get("shell", "")
            for idx, step in enumerate(job.get("steps") or []):
                if not isinstance(step, dict):
                    continue
                body = step.get("run")
                if not isinstance(body, str):
                    continue
                shell = (step.get("shell") or default_shell or "bash").split()[0]
                if shell in SKIP_SHELLS:
                    continue
                checked += 1
                proc = subprocess.run(
                    ["bash", "-n"], input=body, text=True, capture_output=True, check=False
                )
                if proc.returncode != 0:
                    findings += 1
                    tail = proc.stderr.strip().splitlines()
                    print(
                        f"{f}: job={job_name} step[{idx}] name={step.get('name')!r} "
                        f"-- run: body is not valid bash",
                        file=sys.stderr,
                    )
                    for line in tail[-3:]:
                        print(f"    {line}", file=sys.stderr)

    if findings:
        print(
            f"lint-workflow-run-body-syntax: {findings} run body/bodies do not parse "
            f"(of {checked} checked). The step cannot execute at all.",
            file=sys.stderr,
        )
        return 1
    print(f"lint-workflow-run-body-syntax: clean -- {checked} run bodies parse as bash")
    return 0


if __name__ == "__main__":
    sys.exit(main())
