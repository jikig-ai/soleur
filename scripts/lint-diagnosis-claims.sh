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
# SCOPE. .github/workflows/, .github/actions/, scripts/ AND apps/web-platform/infra/. The
# actions directory is the reason this matters: lint-workflows.sh and
# lint-workflow-step-env-refs.py both scan `workflows/*.yml` only, which is exactly why the
# two offending ::error:: lines in cf-tunnel-registry-bridge/action.yml went unexamined
# through two prior fixes. `scripts/` is included because that is where this PR MOVED the
# canonical message text — a lint that skipped it would have enforced nothing over the very
# prose it was built for. `apps/web-platform/infra/` was added by #7310 for the same reason
# both of the others were: nobody had pointed a scanner at it, and a message there
# ("registry_rationale_strip is the fix") named a cause the job never measured — one that
# was wrong, and that propagated into the recut runbook and into #7287's precondition for
# re-provisioning the sole container-registry pull path.
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
# `scripts/` is not optional garnish — it is where THIS PR moved every operator-facing
# causal claim (scripts/zot-mirror-diagnosis.sh). A lint written because "prose is not an
# enforcement mechanism", that does not read the file the prose now lives in, enforces
# nothing over its own canonical text: inserting a fresh "Most likely cause: …" into the
# `live` arm left the census at 0 and the unit suite fully green.
# `scripts/zot-restart-loop-alarm.sh` likewise emits NIC_CAUSE strings ("serving is fine",
# "not an outage") that reach ::error:: and issue bodies through the workflow.
# `apps/web-platform/infra/` is the same lesson a third time (#7310): it holds ~70 operator-
# facing shell gates that no lint read, and one of them spent a production-recovery window
# telling the operator that a strip which had ALREADY been applied was the remedy. Widening
# to it costs 71 more walked files and, at the time it landed, zero new hits.
DIRS = [".github/workflows", ".github/actions", "scripts", "apps/web-platform/infra"]
SCAN_EXTS = (".yml", ".yaml", ".sh")

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
#
# `\bis the (?:fix|cause)\b` catches the shape that asserts a cause by prescribing its
# remedy — "X is the fix" — which is why it matched none of the alternatives above even
# though several of them are about causes. Both word boundaries are load-bearing: the
# leading one stops "This the fix" / "Analysis the fix" (both end in a bare "is"), and the
# trailing one stops "is the fixture" / "is the fixed value" / "is the causes".
    r"this means (?:a|the|that)|indicates (?:a|the|that)|caused by|"
    r"\bis the (?:fix|cause)\b",
    re.IGNORECASE)

# Evidence that the claim rests on something the job computed. A verdict variable, an
# outcome, a measured count, or an explicit marker.
MEASURED = re.compile(
    r"MEASURED-BY:|TOKEN_VERDICT|token-verdict|steps\.[A-Za-z0-9_-]+\.(outcome|conclusion)|"
    r"steps\.[A-Za-z0-9_-]+\.outputs\.[A-Za-z0-9_]+|"
    r"outputs\.verdict|\$\{?VERDICT|zot_mirror_diagnosis|verdict=|_VERDICT\b",
    re.IGNORECASE)

# Only lines that actually SPEAK to an operator.
#
# The last alternative is the one that matters, and its absence made the first version of
# this lint catch ONE of the two historical offenders. The acute site was an `echo
# "::error::…"` and was caught; the site the whole #7242 narrative quotes —
#
#   degraded bridge "n/a" "… Most likely cause: a Cloudflare Access service token was
#   rotated and the new value never reached Doppler. …"
#
# — is a HELPER CALL whose message rides in an argument, and it matched none of the
# annotation shapes. A lint built to catch a specific line, that does not catch that line,
# reports `.highwater = 0` and reads as "the class is enforced" while the next regression
# ships green in exactly the shape the last one had.
#
# `[a-z_][a-z0-9_]*` + a quoted argument is deliberately broad: on this corpus the FALSE
# positives are cheap (a causal-claim phrase must also be present, and the measured-basis
# escape hatch is one comment away) and the false NEGATIVE is the entire point of the lint.
EVIDENCE_LINES_BEFORE = 16
EVIDENCE_LINES_AFTER = 4

OPERATOR_LINE = re.compile(
    r"::error::|::warning::|::notice::|GITHUB_STEP_SUMMARY|body:|echo \"|printf |"
    r"^\s*[a-z_][a-z0-9_]*(\s+\S+)*\s+\"")

hits = []
scanned_files = 0
for d in DIRS:
    base = os.path.join(root, d)
    for dirpath, _, files in os.walk(base):
        for fn in files:
            if not fn.endswith(SCAN_EXTS):
                continue
            path = os.path.join(dirpath, fn)
            # A test file is not an operator-facing CI message. Excluding them is a SCOPE
            # decision, not a suppression: this lint's own suite deliberately contains the
            # verbatim historical offenders as fixtures (that is how it proves it can still
            # catch them), and sibling suites quote causal prose inside assertion
            # descriptions. Scanning them would force the ratchet to carry permanent false
            # positives, so the count could never reach zero and every future reader would
            # assume real offenders remained.
            if fn.endswith((".test.sh", ".test.yml")) or "/test/" in path.replace(os.sep, "/"):
                continue
            # os.walk does not RECURSE symlinked directories, but it does list symlinked
            # FILES, and this scanner open()s and echoes up to 120 chars of any line it
            # flags — so a `.github/workflows/x.yml -> /etc/shadow` symlink is a read
            # primitive. Nothing legitimate here is a symlink.
            if os.path.islink(path):
                continue
            scanned_files += 1
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
                # EVIDENCE_LINES_BEFORE is sized to the longest `env:` block in .github/ —
                # the evidence for a message is usually a mapping a few lines above it.
                lo, hi = max(0, i - EVIDENCE_LINES_BEFORE), min(len(lines), i + EVIDENCE_LINES_AFTER)
                # Comments are stripped from the evidence window for the same reason they are
                # skipped as claims: otherwise a comment explaining a RETRACTED claim
                # ("the verdict= plumbing used to live here") exonerates the live claim next
                # to it. `# MEASURED-BY:` is the one deliberate comment-borne exception.
                block = "\n".join(
                    ln for ln in lines[lo:hi]
                    if not ln.strip().startswith("#") or "MEASURED-BY:" in ln
                )
                if MEASURED.search(block):
                    continue
                hits.append((rel, i, stripped[:120]))

for rel, i, text in sorted(hits):
    print(f"{rel}:{i}: {text}")
print(f"FILES={scanned_files}")
print(f"COUNT={len(hits)}")
PY
}

out="$(census)"
live="$(printf '%s\n' "$out" | sed -n 's/^COUNT=//p')"
files="$(printf '%s\n' "$out" | sed -n 's/^FILES=//p')"
detail="$(printf '%s\n' "$out" | grep -vE '^(COUNT|FILES)=' || true)"

# ANTI-VACUITY. `os.walk` on a missing directory yields nothing, so a renamed tree, a
# relocated scripts/ or a typo in SCAN_EXTS produces COUNT=0 — byte-identical to a clean
# repo — and this gate would certify silence forever. "Zero offenders" and "walked zero
# files" must not be the same answer. A floor, not equality: the corpus only grows.
# Overridable ONLY so the suite can drive small fixture trees through the same code path —
# and the suite also asserts the floor itself fires, so making it configurable does not make
# it bypassable in anger. Default is sized well under the live corpus and only grows.
MIN_FILES="${LINT_DIAGNOSIS_MIN_FILES:-40}"
if ! [[ "$files" =~ ^[0-9]+$ ]] || [[ "$files" -lt "$MIN_FILES" ]]; then
  echo "error: lint-diagnosis-claims walked ${files:-<none>} files, expected >= ${MIN_FILES}." >&2
  echo "       A clean result from a walk that found nothing is not a clean result." >&2
  exit 2
fi

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
