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
# `.github/actions/` was: no lint read it FOR THIS RULE CLASS. (It is not unlinted —
# lint-trap-tempfile-ownership.py walks every tracked *.sh in the repo, including these —
# but nothing checked its operator-facing messages for unmeasured causal claims.) A message
# there, `registry-userdata-budget.sh:131`, told operators that "#7280's
# registry_rationale_strip is the fix" while #7280 had merged 6 h 22 m earlier and the strip
# was already applied. It stood on main ~10.5 h (#7283 14:40Z -> #7300 01:16Z) and took two
# PRs (#7300, #7303) to unwind, the second because the claim had propagated into the recut
# runbook. Deliberately NOT claimed here: that any operator acted on it. #7287 was opened
# 08:38Z, six hours BEFORE the message reached main, so it cannot have been mis-steered by
# it — an attribution the first draft of this comment made without measuring, which is the
# exact defect this file exists to stop.
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
# `apps/web-platform/infra/` (#7310) holds 66 shell gates and 5 workflow fragments — 71
# walked files, after 100 *.test.sh are excluded — and nothing checked their messages for
# unmeasured causal claims. One of them asserted a remedy that had already been applied; see
# the SCOPE note above for the measured timeline and for what is deliberately NOT claimed.
# Widening cost 71 more walked files and, at the time it landed, zero new hits.
#
# Every entry must EXIST. os.walk on a missing directory yields nothing and returns quietly,
# so a typo or an `apps/` restructure silently drops a whole scope while the run stays green
# — measured: renaming this entry to `infras` loses all 71 files and still prints
# `OK — 1 unmeasured causal claims`. MIN_FILES cannot catch that (any single directory can
# vanish and the remainder still clears the floor), so the existence check below is the only
# thing standing between a scope typo and a permanently vacuous gate.
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
#
# The last alternative (#7310) catches the shape that asserts a cause by PRESCRIBING ITS
# REMEDY — "X is the fix" — which is why it matched none of the alternatives above even
# though several of them are about causes.
#
# The adjective list is CLOSED on purpose. Without it, one intervening word defeats the
# whole alternative, and the asymmetry runs the wrong way: `is the likely cause` is already
# caught (by `likely cause`), so the HEDGED form was covered while the CONFIDENT forms
# `is the root cause` / `is the actual cause` / `is the real cause` were not. #7242 has
# re-drifted three times through exactly this kind of rewording. `likely` is omitted because
# `likely cause` already covers it and a line must not be counted twice.
#
# An OPEN slot `(?:[a-z]+ )?` was measured and rejected: it costs +2, and both are the
# permanent-false-positive shape described above — `out-of-stock is the documented cause`
# (a citation of prior art on a line whose point is "do not assume") and `is the usual
# cause` (a real offender that deserves its own fix, not a baseline entry).
#
# `\s+` rather than a literal space so a wrapped printf splitting `is  the` cannot evade.
# Both word boundaries are load-bearing: the leading one stops "This the fix" / "Analysis
# the fix" (words ending in a bare "is"; note this holds for \w-terminated words only, so
# `token-is the fix` still matches), and the trailing one stops "is the fixture" / "is the
# fixed value" / "is the causes". Measured: this form adds 0 hits over the live corpus.
CLAIM = re.compile(
    r"most likely cause|likely cause|the cause is|"
    r"which is the [a-z]+(?:-[a-z]+)+ shape\b|"
    r"serving is fine|not an outage|= the EDGE|which means the|"
    r"this means (?:a|the|that)|indicates (?:a|the|that)|caused by|"
    r"\b(?:is|was|are|were)\s+the\s+(?:root |actual |real |only |underlying |true )?"
    r"(?:fix|cause|culprit)\b",
    re.IGNORECASE)

# #7578. A cause named as a DASH APPENDIX — `<measured facts> — <cause> / <cause>`. This is
# an extremely natural way to write a diagnosis in a shell string and the phrase list above
# models none of it, so the construction was invisible class-wide.
#
# Two bounds make it usable, both measured against the live corpus:
#
#   - The span excludes `$`. The dominant honest shape INTERPOLATES the value it is
#     explaining (`http=$code — GHCR path (zot unreachable)`, `exit $bq_rc — creds unset`) —
#     that message restates a measurement it just took. The offender's appendix was STATIC
#     PROSE, and the measurement beside it (`rc=0`) contradicted it. Measured: dropping the
#     exclusion takes the live census 12 -> 19, and all 7 of the difference are this shape.
#   - The predicate list is CLOSED, for the same reason CLAIM's adjective list is: an open
#     slot buys hits that are permanent false positives, and a ratchet carrying those can
#     never reach zero, so every future reader assumes real offenders remain.
#
# It is a SEPARATE regex rather than another alternative because the exoneration rule below
# differs for it — see the EXONERATION note.
CLAIM_APPENDIX = re.compile(
    r"[—–][^\"$]{0,60}?\b(?:unreachable|creds unset|credentials unset|token expired|"
    r"not installed|misconfigured|permission denied|quota exhausted)\b",
    re.IGNORECASE)

# Evidence that the claim rests on something the job computed. A verdict variable, an
# outcome, a measured count, or an explicit marker.
MEASURED = re.compile(
    r"MEASURED-BY:|TOKEN_VERDICT|token-verdict|steps\.[A-Za-z0-9_-]+\.(outcome|conclusion)|"
    r"steps\.[A-Za-z0-9_-]+\.outputs\.[A-Za-z0-9_]+|"
    r"outputs\.verdict|\$\{?VERDICT|zot_mirror_diagnosis|verdict=|_VERDICT\b",
    re.IGNORECASE)

# The strict standard, used for the appendix class only (see the EXONERATION note below).
# Deliberate, human-written, and auditable — unlike the inferred set above, whose members can
# be present for reasons unrelated to the cause a message names.
MEASURED_MARKER = re.compile(r"MEASURED-BY:")

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
#
# KNOWN GAP (#7318): that alternative is `^\s*`-anchored, so a helper call on a shell
# CONTINUATION line still escapes — `|| degraded sign "$?" "…"`. The repo has exactly one
# such live line (.github/workflows/reusable-release.yml:1289), and it carries the #7310
# `is the fix` phrasing, so the alternative added there currently has zero live yield. Not
# fixed here: un-anchoring moves the census 1 -> 2 and reds this blocking gate, and whether
# that line is a genuine claim or a hedged conditional is its own decision.
EVIDENCE_LINES_BEFORE = 16
EVIDENCE_LINES_AFTER = 4

# The last TWO alternatives are #7578 and #7318. Both are the same lesson as the helper-call
# alternative above, learned again: this filter must enumerate the SYNTAXES that carry a
# message to an operator, not accumulate the shapes that happened to bite. The four are
# direct emit, start-of-line helper call, continuation-line helper call, and assignment.
#
# ASSIGNMENT (#7578). A message assembled into a shell variable and emitted later was
# invisible, and for two independent reasons: the helper-call alternative requires whitespace
# immediately before the quote (`\s+"`) and an assignment has `=` there, and it is anchored to
# `[a-z_]` while shell convention uppercases variable names. Measured: `NIC_DETAIL="x"` False,
# `detail="x"` False, `detail = "x"` True — so even the lowercase form escaped. This is how
# `zot-restart-loop-alarm.sh` named two causes its own rc=0 refuted, every 30 minutes for two
# days, with the gate green. Live yield when it landed: +1.
#
# CONTINUATION (#7318). The helper-call alternative is `^\s*`-anchored, so `|| degraded sign
# "$?" "…"` escaped. Documented as a known gap since #7310 and folded in here because it is
# the same regex and the same class — kept separate it would cost a second triage pass and a
# second negotiation over the same ratchet. Live yield when it landed: +1.
OPERATOR_LINE = re.compile(
    r"::error::|::warning::|::notice::|GITHUB_STEP_SUMMARY|body:|echo \"|printf |"
    r"^\s*[a-z_][a-z0-9_]*(\s+\S+)*\s+\"|"
    r"(?:\|\||&&|;|\|)\s*[a-z_][a-z0-9_]*(\s+\S+)*\s+\"|"
    r"^\s*(?:local\s+|export\s+|readonly\s+)?[A-Za-z_][A-Za-z0-9_]*=\"")

hits = []
scanned_files = 0
for d in DIRS:
    base = os.path.join(root, d)
    # SCOPE LOSS IS A HARD ERROR, not a quiet zero. This is strictly stronger than
    # MIN_FILES, which is a floor over the TOTAL and therefore cannot see any single
    # directory disappearing while the others still clear it.
    if not os.path.isdir(base):
        print(f"error: DIRS entry {d!r} does not exist under {root} — scope lost.",
              file=sys.stderr)
        sys.exit(2)
    for dirpath, dirnames, files in os.walk(base):
        # `.terraform/` is gitignored (apps/web-platform/infra/.gitignore) but os.walk
        # descends into it anyway, so after a local `terraform init` this gate would read
        # vendored module sources CI never sees — inflating FILES and risking a local-only
        # RED. Prune it in place so the walk matches the tracked tree.
        dirnames[:] = [dn for dn in dirnames if dn != ".terraform"]
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
            # assume real offenders remained. `.bench.sh` is the same category — a benchmark
            # harness narrates causes and is not an operator-facing CI message.
            #
            # The path rule is `/tests?/` because `/test/` matched NOTHING: the newly-scoped
            # tree uses `tests/`, `test-fixtures/` and `fixtures/`, so the singular-only form
            # was a dead guard whose name implied coverage it did not have.
            norm = path.replace(os.sep, "/")
            if fn.endswith((".test.sh", ".test.yml", ".bench.sh")) or re.search(r"/tests?/", norm):
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
                if not OPERATOR_LINE.search(line):
                    continue
                claim_phrase = bool(CLAIM.search(line))
                claim_appendix = bool(CLAIM_APPENDIX.search(line))
                if not (claim_phrase or claim_appendix):
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
                # EXONERATION — and this is the factor the #7578 diagnosis missed entirely.
                #
                # The detector is a THREE-factor conjunction: carrier AND claim AND NOT
                # exonerated. A line escapes if any ONE factor misses it, so widening the two
                # regexes above is not enough on its own — measured: with both widened and
                # this rule left alone, BOTH verbatim offender lines are still cleared.
                # `VERDICT="TRANSIENT"` on the offending line matches `verdict=`
                # case-insensitively; its sibling's window carries `NIC_VERDICT`, matching
                # `_VERDICT\b`. The two escaped through different alternatives of the same
                # regex, which is why fixing one would not have revealed the other.
                #
                # PROXIMITY IS NOT EVIDENCE. A verdict variable in the neighbourhood shows the
                # job measured SOMETHING; it does not show it measured the cause this line
                # NAMES. For the phrase-list forms that heuristic has held. For a static-prose
                # appendix it demonstrably has not — and the failure runs the worst possible
                # way round, because the measurement the offender sat next to (rc=0) was the
                # very thing that REFUTED the causes it named. That is this repo's own
                # cq-assert-anchor-not-bare-token anti-pattern, on the exoneration side.
                #
                # So: a line matched ONLY by the appendix needs the deliberate marker, which a
                # human had to write and can be held to. A line matched by the phrase list
                # keeps the inferred token set exactly as before — the narrowing is
                # appendix-only, and the suite pins that with a must-PASS case so a future
                # edit cannot quietly extend it to the whole corpus.
                exonerated = (MEASURED if claim_phrase else MEASURED_MARKER).search(block)
                if exonerated:
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
  # `rel:line: text` per hit. Exists so the suite can assert WHICH file tripped, not just
  # how many did: a bare count cannot tell "the infra fixture tripped" from "some other
  # fixture tripped", so a later edit relocating a fixture out of the scope it was written
  # to pin would keep the assertion green while removing the coverage.
  --detail)
    echo "$detail"
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
