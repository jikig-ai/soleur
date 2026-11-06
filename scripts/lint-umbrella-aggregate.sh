#!/usr/bin/env bash
# #12089 review — umbrella-aggregate parity lint.
#
# Each umbrella job folds several former jobs into MEMBER steps whose verdicts
# are surfaced by one `aggregate` step's `member(...)` calls. Three invariants
# keep the fold honest:
#
#   (a) COVERAGE: every `- id:` step except `aggregate` appears in EXACTLY one
#       `member(...)` call's id list in the aggregate run: block — a member
#       step absent from every call is a verdict the job never reads (a red
#       member cannot fail the umbrella), and a step listed twice double-counts.
#   (b) ISOLATION: every member step's `if:` contains `!cancelled()` — the
#       always-run clause that keeps one red member from hiding the rest.
#   (c) EXISTENCE: an `aggregate` step exists in the job.
#
# Text-parse lint: `- id:` and `member(` tokens only, no YAML library. The
# member(...) call's THIRD argument is the single-quoted CSV of step ids.
#
# Umbrella census (three files, five jobs):
#   ci.yml                 guards-ruleset, guards-advisory
#   pr-quality-guards.yml  quality-guards, quality-advisory
#   secret-scan.yml        secret-guards
#
# Registered in scripts/test-all.sh (live lint, no .test.sh wrapper).
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

python3 - <<'PYEOF'
import re
import sys

UMBRELLAS = {
    ".github/workflows/ci.yml": ["guards-ruleset", "guards-advisory"],
    ".github/workflows/pr-quality-guards.yml": ["quality-guards", "quality-advisory"],
    ".github/workflows/secret-scan.yml": ["secret-guards"],
}

failures = []


def fail(msg):
    failures.append(msg)
    print(f"::error::lint-umbrella-aggregate: {msg}", file=sys.stderr)


def job_body(lines, job):
    """Return the line list for `  <job>:` up to the next `  <key>:` job or EOF."""
    start = None
    for i, l in enumerate(lines):
        if l == f"  {job}:":
            start = i + 1
            break
    if start is None:
        return None
    end = len(lines)
    for j in range(start, len(lines)):
        if re.match(r"^  [A-Za-z0-9_-]+:\s*$", lines[j]):
            end = j
            break
    return lines[start:end]


def step_blocks(body):
    """Yield (id, block_lines) for each `      - id: <x>` step."""
    idx = [i for i, l in enumerate(body) if re.match(r"\s+- id: \S+\s*$", l)]
    for k, i in enumerate(idx):
        end = idx[k + 1] if k + 1 < len(idx) else len(body)
        sid = re.match(r"\s+- id: (\S+)", body[i]).group(1)
        yield sid, body[i:end]


def run_block(block):
    """The step's `run: |` literal body (indented past the `run:` line)."""
    for i, l in enumerate(block):
        if re.match(r"\s+run:\s*\|", l):
            base = re.match(r"(\s*)run:", l).group(1)
            out = []
            for m in block[i + 1 :]:
                if m.strip() == "":
                    out.append(m)
                    continue
                if not m.startswith(base + "  "):
                    break
                out.append(m)
            return out
    return []


member_re = re.compile(r"^\s*member\s+(\S+)\s+(\S+)\s+'([^']*)'")


for path, jobs in UMBRELLAS.items():
    lines = open(path, encoding="utf-8").read().splitlines()
    for job in jobs:
        body = job_body(lines, job)
        if body is None:
            fail(f"{path}: umbrella job `{job}` not found")
            continue
        steps = list(step_blocks(body))
        agg = [b for sid, b in steps if sid == "aggregate"]
        members = [sid for sid, _ in steps if sid != "aggregate"]

        # (c) aggregate exists
        if not agg:
            fail(f"{path} `{job}`: no `aggregate` step")
            continue
        if len(agg) > 1:
            fail(f"{path} `{job}`: {len(agg)} `aggregate` steps (want 1)")

        # (b) every member step's if: contains !cancelled()
        for sid, block in steps:
            ifline = next(
                (l.strip() for l in block if re.match(r"\s+if:", l)), None
            )
            if ifline is None:
                fail(f"{path} `{job}` step `{sid}`: no `if:` line")
            elif "!cancelled()" not in ifline:
                fail(
                    f"{path} `{job}` step `{sid}`: if: lacks !cancelled() ({ifline})"
                )

        # (a) coverage — every non-aggregate step id in exactly one member() call
        counted = {}
        for mline in run_block(agg[0]):
            m = member_re.match(mline)
            if not m:
                continue
            for sid in m.group(3).split(","):
                sid = sid.strip()
                if sid:
                    counted[sid] = counted.get(sid, 0) + 1
        for sid in members:
            n = counted.get(sid, 0)
            if n == 0:
                fail(
                    f"{path} `{job}` step `{sid}`: absent from every member() call"
                )
            elif n > 1:
                fail(
                    f"{path} `{job}` step `{sid}`: in {n} member() calls (want 1)"
                )
        for sid, n in counted.items():
            if sid not in members:
                fail(
                    f"{path} `{job}`: member() call names step id `{sid}` that has no `- id:` step"
                )
        if not members:
            fail(f"{path} `{job}`: no member steps found (anti-vacuity floor)")

if failures:
    print(f"lint-umbrella-aggregate: FAIL ({len(failures)} finding(s))")
    sys.exit(1)
print("lint-umbrella-aggregate: OK (5 umbrella jobs verified)")
PYEOF
