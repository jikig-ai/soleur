#!/usr/bin/env bash
# lint-diagnosis-claims.sh — an operator-facing CI message may not name a cause the job did
# not measure (#7242, ADR-166).
#
# WHY A LINT AND NOT A REVIEW NOTE. This defect has now shipped three times on ONE code
# path. Iteration one (2026-07-15) and iteration two (2026-07-29) were each fixed by
# rewriting the offending sentence, and each re-drifted; iteration three
# ("stale-service-token shape") blocked three production releases and sent the
# investigation to a credential the same job had already verified live. Rewriting it a
# fourth time generalizes nothing — every other ::error:: / ::warning:: in the repo stays
# free to assert a cause nobody checked. Prose is not an enforcement mechanism.
#
# WHAT IT FLAGS. A message literal containing a causal-claim phrase, where the surrounding
# block shows no sign that the claim was MEASURED. "Measured" means one of:
#   - the block references a verdict/outcome variable, or
#   - the line carries an explicit `# MEASURED-BY: <what measured it>` marker.
#
# SCOPE. Both .github/workflows/ AND .github/actions/. The actions directory is the reason
# this matters: lint-workflows.sh and lint-workflow-step-env-refs.py both scan
# `workflows/*.yml` only, which is exactly why the two offending ::error:: lines in
# cf-tunnel-registry-bridge/action.yml went unexamined through two prior fixes.
#
# RATCHET. Ships with a .highwater baseline so it lands green over a pre-existing
# population and drives that population down. Blocking upward, advisory downward — a
# regression fails; an improvement prints a note asking you to lower the baseline.
#
# ENFORCEMENT LEVEL: BLOCKING. This suite is registered in scripts/test-all.sh, whose
# `scripts` shard feeds the aggregate `test` job, and `test` IS in the CI Required ruleset.
# That is deliberate and is NOT the same as the repo's other linters, which live in the
# `lint-bot-statuses` job that ci.yml documents as advisory (absent from both
# required-checks.txt and the Terraform ruleset, so a PR merges with it red). A lint that
# cannot block is a lint that gets ignored, and this one exists precisely because two
# non-blocking corrections did not hold.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# LINT_DIAGNOSIS_ROOT is the TEST SEAM, and it exists so the suite can drive this scanner
# over fixtures rather than over the repo. A lint whose only input is the live tree cannot
# be proven to FAIL — and a guard that has never been observed failing is indistinguishable
# from one that cannot (this repo's own recurring finding). The suite uses it to assert both
# arms: a message that MUST trip, and one that MUST NOT.
REPO_ROOT="${LINT_DIAGNOSIS_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
HIGHWATER_FILE="$SCRIPT_DIR/lint-diagnosis-claims.highwater"

MODE="${1:-scan}"

census() {
  python3 - "$REPO_ROOT" <<'PY'
import sys, os, re

root = sys.argv[1]
DIRS = [".github/workflows", ".github/actions"]

# Phrases that assert a CAUSE. Deliberately narrow: each one is a claim about why
# something failed, not a description of what failed. Broadening this to every hedge word
# would bury the signal and get the lint switched off.
#
# `which is the <hyphenated-cause> shape` is deliberately narrow. An earlier draft used
# `is the .{0,24}shape`, which flagged two lines that are not claims at all: a gate saying
# "a green-but-inert monitor is the #6400 shape this gate exists to prevent" (a description
# of what it PREVENTS, on a line already reporting a measurement) and a message whose prose
# EXPLAINS this very anti-pattern. Baselining those would have parked two false positives
# in the ratchet forever, so that the count could never reach zero and every future reader
# would assume two real offenders remained.
CLAIM = re.compile(
    r"most likely cause|likely cause|the cause is|"
    r"which is the [a-z]+(?:-[a-z]+)+ shape\b|"
    r"serving is fine|not an outage|= the EDGE|which means the|"
    r"this means (?:a|the|that)|indicates (?:a|the|that)|caused by",
    re.IGNORECASE)

# Evidence that the claim rests on something the job computed. A verdict variable, an
# outcome, a measured count, or an explicit marker.
MEASURED = re.compile(
    r"MEASURED-BY:|TOKEN_VERDICT|token-verdict|steps\.[A-Za-z0-9_-]+\.(outcome|conclusion)|"
    r"outputs\.verdict|\$\{?VERDICT|zot_mirror_diagnosis|verdict=|_VERDICT\b",
    re.IGNORECASE)

# Only lines that actually SPEAK to an operator.
OPERATOR_LINE = re.compile(r"::error::|::warning::|::notice::|GITHUB_STEP_SUMMARY|body:|echo \"")

hits = []
for d in DIRS:
    base = os.path.join(root, d)
    for dirpath, _, files in os.walk(base):
        for fn in files:
            if not fn.endswith((".yml", ".yaml")):
                continue
            path = os.path.join(dirpath, fn)
            rel = os.path.relpath(path, root)
            try:
                lines = open(path, encoding="utf-8").read().splitlines()
            except Exception:
                continue
            for i, line in enumerate(lines, 1):
                stripped = line.strip()
                # A comment is documentation, not an operator-facing message. Excluding
                # them is load-bearing in BOTH directions: a comment explaining a retracted
                # claim (which this repo now has several of) must not be flagged, and the
                # bare-token grep that would flag it is the anti-pattern this repo already
                # names (cq-assert-anchor-not-bare-token).
                if stripped.startswith("#"):
                    continue
                if not OPERATOR_LINE.search(line) or not CLAIM.search(line):
                    continue
                # Evidence may sit on the line or in its immediate neighbourhood (an env:
                # mapping a few lines up, a verdict computed just above).
                lo, hi = max(0, i - 16), min(len(lines), i + 4)
                block = "\n".join(lines[lo:hi])
                if MEASURED.search(block):
                    continue
                hits.append((rel, i, stripped[:120]))

for rel, i, text in sorted(hits):
    print(f"{rel}:{i}: {text}")
print(f"COUNT={len(hits)}")
PY
}

out="$(census)"
live="$(printf '%s\n' "$out" | sed -n 's/^COUNT=//p')"
detail="$(printf '%s\n' "$out" | grep -v '^COUNT=' || true)"

case "$MODE" in
  --census)
    echo "$live"
    exit 0
    ;;
esac

# A MISSING BASELINE IS A HARD ERROR, never a pass. A ratchet whose baseline vanished would
# otherwise certify any population at all.
if [[ ! -f "$HIGHWATER_FILE" ]]; then
  echo "error: $HIGHWATER_FILE is missing — the ratchet has no baseline, so this run can certify nothing." >&2
  exit 2
fi
# Comment-tolerant parse, matching lint-trap-tempfile-ownership.py's baseline format.
allowed="$(sed 's/#.*//' "$HIGHWATER_FILE" | tr -d '[:space:]')"
if ! [[ "$allowed" =~ ^[0-9]+$ ]]; then
  echo "error: $HIGHWATER_FILE does not contain a non-negative integer (got '${allowed}')." >&2
  exit 2
fi

if [[ "$live" -gt "$allowed" ]]; then
  echo "$detail"
  echo ""
  echo "lint-diagnosis-claims: FAIL — $live operator-facing causal claims with no measured basis (baseline $allowed)."
  echo ""
  echo "  A CI message may not name a cause the job did not measure (ADR-166). Fix by either:"
  echo "    1. branching the message on a verdict the job computed, or"
  echo "    2. rewording it to state what was OBSERVED rather than why, or"
  echo "    3. adding '# MEASURED-BY: <what measured it>' if the basis is real but not visible here."
  echo ""
  echo "  Do NOT raise the baseline to make this pass. The baseline ratchets DOWN only."
  exit 1
fi

if [[ "$live" -lt "$allowed" ]]; then
  echo "note: lint-diagnosis-claims is at $live, below the baseline of $allowed."
  echo "      Lower $HIGHWATER_FILE to $live to lock the improvement in."
fi
echo "lint-diagnosis-claims: OK — $live unmeasured causal claims (baseline $allowed)."
exit 0
