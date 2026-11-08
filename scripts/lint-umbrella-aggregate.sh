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
#   (d) VERDICT-FLOW: coverage alone certifies wiring, not failure — the
#       aggregate must also consume its member verdicts: `failed=0` init,
#       `|| failed=1` on every member() call, and the `[ "$failed" -ne 0 ]`
#       → `exit 1` tail. The member() body's discriminating lines
#       (`skipped) ;;`, `*) any_fail=1`, the owed-verdict `return 1`, the
#       pass `return 0`) are pinned as tokens — a one-character edit that
#       flips skipped→success or drops the fail edge is a silent green.
#   (e) CENSUS: UMBRELLAS below must equal the set of jobs containing an
#       `- id: aggregate` step across .github/workflows/*.yml — a new
#       umbrella added outside the census fails until registered.
#   (f) CANONICAL-SOURCE: member() exists ONCE, in
#       scripts/lib/umbrella-member.sh (#12276 — the five inline copies were
#       one shared arbiter's worth of drift waiting to happen). Each
#       aggregate run block must source it exactly once via the
#       `${GITHUB_WORKSPACE:?}` form and must NOT carry an inline
#       `member() {` redefinition — a shadow body after the source line
#       silently re-opens the five-way drift the dedup closed. The semantics
#       tokens of (d) are pinned against the lib file, once, not per block.
#
#   (g) NO CONTINUE-ON-ERROR (REQUIRED umbrellas): no step, and not the job,
#       of a required umbrella may carry a `continue-on-error:` key, whatever
#       its value. `member()` reads `conclusion`, and `continue-on-error: true`
#       turns a failed step's conclusion into `success` (the failure survives
#       only in `outcome`, which member() merely prints): the member goes green
#       and the PR is never blocked, with (a)-(f) all still satisfied. Measured
#       against the tree: the ONLY umbrella that legitimately uses it is the
#       advisory `guards-advisory` (harness-discovery et al.: its verdicts are
#       non-blocking by design and it is not a required context), so the rule
#       is scoped to every umbrella NOT in ADVISORY_UMBRELLAS below.
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
import os
import re
import sys

UMBRELLAS = {
    ".github/workflows/ci.yml": ["guards-ruleset", "guards-advisory"],
    ".github/workflows/pr-quality-guards.yml": ["quality-guards", "quality-advisory"],
    ".github/workflows/secret-scan.yml": ["secret-guards"],
}

# Umbrellas that are NOT required contexts and may carry continue-on-error (see (g)).
ADVISORY_UMBRELLAS = {"guards-advisory", "quality-advisory"}

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

        # (g) no continue-on-error key anywhere in a required umbrella (job level or any step,
        # including the id-less checkout step). A comment line starts with `#`, so it never matches.
        if job not in ADVISORY_UMBRELLAS:
            for ln in body:
                if re.match(r"\s+continue-on-error\s*:", ln):
                    fail(
                        f"{path} `{job}`: `continue-on-error` in a required umbrella turns a red member "
                        f"into conclusion=success ({ln.strip()})"
                    )

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

        # (d) verdict-flow — the verdict→exit edge; (f) canonical-source pin
        rb = "\n".join(run_block(agg[0]))
        for tok in ("failed=0", 'if [ "$failed" -ne 0 ]', "exit 1"):
            if tok not in rb:
                fail(f"{path} `{job}` aggregate: verdict-flow token `{tok}` missing")
        for mline in run_block(agg[0]):
            if member_re.match(mline) and "|| failed=1" not in mline:
                fail(f"{path} `{job}` aggregate: member() call lacks `|| failed=1`")
        src_n = rb.count('source "${GITHUB_WORKSPACE:?}/scripts/lib/umbrella-member.sh"')
        if src_n != 1:
            fail(f"{path} `{job}` aggregate: canonical member() source line present {src_n}x (want 1)")
        if "member() {" in rb:
            fail(f"{path} `{job}` aggregate: inline member() redefinition shadows the canonical lib")

# (d-continued) member() semantics, pinned ONCE against the canonical lib —
# they used to be checked per run block when each umbrella carried its own
# copy. A missing lib means every umbrella's source line fails at CI time;
# report it here first with the file it cannot source.
lib_path = "scripts/lib/umbrella-member.sh"
if os.path.isfile(lib_path):
    lib = open(lib_path, encoding="utf-8").read()
    if "member() {" not in lib:
        fail(f"{lib_path}: no member() definition")
    for tok in ("skipped) ;;", "*) any_fail=1", "owed a verdict", "return 1", "return 0"):
        if tok not in lib:
            fail(f"{lib_path}: member() semantics token `{tok}` missing")
else:
    fail(f"{lib_path}: canonical member() library absent — umbrellas cannot source it")

# (e) census — every `- id: aggregate` step in the tree must be a registered umbrella
import glob

discovered = set()
for path in glob.glob(".github/workflows/*.yml"):
    lines = open(path, encoding="utf-8").read().splitlines()
    for i, l in enumerate(lines):
        if re.match(r"\s+- id: aggregate\s*$", l):
            job = None
            for j in range(i, -1, -1):
                m = re.match(r"^  ([A-Za-z0-9_-]+):\s*$", lines[j])
                if m:
                    job = m.group(1)
                    break
            if job:
                discovered.add((path, job))
census = {(p, j) for p, jobs in UMBRELLAS.items() for j in jobs}
for path, job in sorted(discovered - census):
    fail(f"{path}: `- id: aggregate` in unregistered umbrella `{job}` — add to UMBRELLAS")
for path, job in sorted(census - discovered):
    fail(f"{path}: registered umbrella `{job}` has no `- id: aggregate` step")

if failures:
    print(f"lint-umbrella-aggregate: FAIL ({len(failures)} finding(s))")
    sys.exit(1)
print(f"lint-umbrella-aggregate: OK ({sum(len(v) for v in UMBRELLAS.values())} umbrella jobs verified)")
PYEOF
