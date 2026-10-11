#!/usr/bin/env bash
# redact-pii-ghs-shape.test.sh — partial-disclosure regression for redact_pii's
# GitHub-server-token arm in skill-security-scan/scripts/run-scan.sh.
#
# WHAT THIS GUARDS. GitHub rotated `ghs_` installation-access tokens to a
# ~390-520-char body over the alphabet [A-Za-z0-9._~+/=-] — the canonical
# bearer alphabet (the bc_ok class in scripts/lib/bearer-curl.sh, ADR-280).
# The legacy arm — a `ghs_` prefix plus a bare base62 `{20,}` run —
# stops at the FIRST punctuation byte: a new-shape token is masked only up to
# its first `.`/`_`/`~`/`+`/`/`/`=`/`-`, and the credential's tail survives
# UNREDACTED into .scan-meta.json — a PARTIAL disclosure, strictly worse than a
# clean miss because the output still looks redacted.
#
# WHY EXTRACTION, NOT SOURCING. run-scan.sh has no BASH_SOURCE guard — sourcing
# it would RUN the scan. The suite therefore awk-extracts the redact_pii sed
# program text (flag-based, NEVER a `sed /start/,/stop/` range: a repeated
# delimiter would silently widen the captured program), completes the function
# in a generated driver, and runs THAT. The extraction is asserted non-empty,
# and an empty-extraction run is proved incapable of printing the mask — the
# suite can never green vacuously.
#
# FIXTURE IS SYNTHESIZED (cq-test-fixtures-synthesized-only) and assembled with
# a SPLIT PREFIX — `pfx="ghs"; tok="${pfx}_…"` — so no contiguous token-shaped
# literal sits in this file (GitHub push protection and the staged-index
# scanner flag real-shaped literals). The runtime fixture is real-shaped.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUN_SCAN="$SCRIPT_DIR/../scripts/run-scan.sh"

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); echo "  [ok] $1"; }
bad() { FAIL=$((FAIL + 1)); echo "  [FAIL] $1" >&2; }

# Scratch root: TMPDIR-based (`-t` is identical to bare `mktemp -d` there), with
# its owning trap installed before ANY further work — nothing is sourced, but
# the trap still precedes every allocation under $WORK.
WORK="$(mktemp -d -t redact-pii-ghs-shape.XXXXXXXX)"
trap 'rm -rf "$WORK"' EXIT

[[ -f "$RUN_SCAN" ]] || { echo "fatal: missing $RUN_SCAN" >&2; exit 2; }

MASK="<github-server>"

# --- Extract the redact_pii sed program --------------------------------------
# Flag-based: `capture` turns on at the function opener and the capture ends at
# the first line that is ONLY the program's closing single quote. Printed text
# is the complete function minus its closing `}`, i.e. `redact_pii() {` +
# `sed -E '` + program + `'`. run-scan.sh is never sourced or executed here.
EXTRACTED="$(awk -v q="'" '
  /^redact_pii\(\)[[:space:]]*\{/ { capture = 1 }
  capture {
    print
    if ($0 ~ "^[[:space:]]*" q "[[:space:]]*$") exit
  }
' "$RUN_SCAN")"

echo "=== redact_pii new-shape ghs_ token coverage ==="

# --- Anti-vacuity arm 1: the extraction must yield a REAL program ------------
# An empty capture means the opener or the closing-quote line drifted — every
# behavioural row below would then run a broken driver, so this suite must go
# RED here rather than pass on nothing.
if [[ -n "$EXTRACTED" ]]; then
  ok "awk extraction of the redact_pii sed program is non-empty"
else
  bad "awk extraction of redact_pii yielded EMPTY — the function text drifted and the rows below cannot pass legitimately"
fi

# The capture must END at the lone-quote line — if the closing-quote terminator
# drifts, the extractor runs into run-scan.sh's top-level tail (mkdir, a
# `find -exec rm -rf` reaper, jq writes) and the generated driver would
# EXECUTE it. Assert the captured program's last line is exactly `'`.
last_line="$(printf '%s\n' "$EXTRACTED" | tail -1)"
if [[ "$last_line" =~ ^[[:space:]]*\'[[:space:]]*$ ]]; then
  ok "extraction is bounded: the captured program ends at its lone-quote terminator"
else
  bad "extraction overran the lone-quote terminator (last line: ${last_line:0:60}) — the driver would execute run-scan.sh tail code"
  echo "fatal: refusing to execute an overrun capture" >&2
  exit 1
fi

# The capture must run the FULL program: the ghs_ arm sits mid-list, so also
# pin the LAST arm (AKIA) to prove the closing-quote terminator was not
# reached early. `${pfx}_` keeps `ghs_` non-contiguous even in assertions.
pfx="ghs"
if [[ "$EXTRACTED" == *"sed -E"* && "$EXTRACTED" == *"${pfx}_"* \
   && "$EXTRACTED" == *"$MASK"* && "$EXTRACTED" == *"AKIA"* \
   && "$EXTRACTED" == *"<aws-access-key>"* ]]; then
  ok "extracted program spans sed -E through the final AKIA arm, including the ${pfx}_ arm + its mask"
else
  bad "extracted program is truncated or missing the ${pfx}_/$MASK arm — behavioural rows would test the wrong program"
fi

# POSITIVE CONTROL for arm 1: the same awk on input lacking the function MUST
# yield empty — otherwise the non-empty assertion above cannot discriminate.
control_empty="$(awk -v q="'" '
  /^redact_pii\(\)[[:space:]]*\{/ { capture = 1 }
  capture {
    print
    if ($0 ~ "^[[:space:]]*" q "[[:space:]]*$") exit
  }
' /dev/null)"
if [[ -z "$control_empty" ]]; then
  ok "the same extraction on /dev/null yields empty (the non-empty check discriminates)"
else
  bad "extraction on /dev/null was NON-empty — the non-empty assertion is not live"
fi

# --- Build the runnable driver ----------------------------------------------
# Completing the function with `}` and a bare `redact_pii` call makes the
# extracted text a self-contained stdin filter.
DRIVER="$WORK/redact-pii.driver.sh"
{ printf '%s\n' "$EXTRACTED"; printf '}\nredact_pii\n'; } > "$DRIVER"
if bash -n "$DRIVER" 2>/dev/null; then
  ok "the extracted program forms a syntactically valid driver"
else
  bad "the extracted program does not parse (bash -n) — the capture is malformed"
  echo "fatal: refusing to execute a malformed driver" >&2
  exit 1
fi

# --- Anti-vacuity arm 2 (extraction dispatch): an EMPTY extraction must RED ---
# Drive the SAME generate-and-run path with an empty program. If the mask can
# appear anyway, row (a) below could green on a missing arm.
EMPTY_DRIVER="$WORK/empty.driver.sh"
{ printf 'redact_pii() { :; }\nredact_pii\n'; } > "$EMPTY_DRIVER"
empty_out="$(printf '%s\n' 'anything' | bash "$EMPTY_DRIVER" 2>/dev/null || true)"
if [[ "$empty_out" != *"$MASK"* ]]; then
  ok "an empty extraction cannot emit $MASK (empty extraction => RED, never vacuous green)"
else
  bad "an empty extraction emitted $MASK — row (a) would pass vacuously"
fi

# --- Synthesized fixture ------------------------------------------------------
# Post-prefix body ~395 chars: 6 x 62 base62 + 10 base62 + the canonical
# punctuation tail `._~+/=-` + 6 base62. Every canonical byte is present, and
# the tail is out-of-class for the legacy [A-Za-z0-9] alphabet — a base62-only
# fixture would be fully masked by the OLD arm and prove nothing.
B62="0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
body=""
for _i in 1 2 3 4 5 6; do body+="$B62"; done      # 372
body+="${B62:0:10}"                               # 382
body+='._~+/=-'                                   # 389 — every canonical byte
body+="${B62:0:6}"                                # 395
# Inter-arm probes: AB12CDEF matches the IBAN arm and 1.2.3.4 the IPv4 arm —
# arms that ran BEFORE the gh arms pre-ordering; `.` separators give each a
# word boundary, and the trailing lowercase run matches NO generic arm, so a
# regression to generic-first ordering leaves it in clear and the zero-tail
# row goes RED.
body+="AB12CDEF.1.2.3.4.xyzzy42"
tok="${pfx}_${body}"

blen="$(printf '%s' "$body" | wc -c)"
if [[ "$blen" -ge 395 ]]; then
  ok "fixture post-prefix body is ${blen} B (>= 395, new-shape length class incl. inter-arm probes)"
else
  bad "fixture post-prefix body is only ${blen} B (< 395) — too short to exercise the new-shape class + inter-arm probes"
fi

missing_bytes=""
for c in '.' '_' '~' '+' '/' '=' '-'; do
  [[ "$body" == *"$c"* ]] || missing_bytes+="$c "
done
if [[ -z "$missing_bytes" ]]; then
  ok "fixture tail carries every canonical byte: . _ ~ + / = -"
else
  bad "fixture tail is missing canonical byte(s): ${missing_bytes% }— it does not span the rotated alphabet"
fi

if [[ "$body" =~ [^A-Za-z0-9] ]]; then
  ok "fixture body is OUT-OF-CLASS for the legacy [A-Za-z0-9] alphabet (non-vacuous)"
else
  bad "fixture body is base62-only — the OLD arm would mask it whole and this suite would prove nothing"
fi

newshape="^${pfx}_[A-Za-z0-9._~+/=-]{20,}\$"
if [[ "$tok" =~ $newshape ]]; then
  ok "fixture matches the new-shape anchored regex (canonical alphabet, >= 20 body chars)"
else
  bad "fixture does NOT match the new-shape regex — the fixture itself is malformed"
fi

# FIXTURE ADEQUACY, demonstrated: the LEGACY arm must leave a surviving tail on
# this fixture. If it masked the whole token, row (a) could never have gone RED
# on the unpatched program.
legacy_out="$(printf '%s\n' "$tok" | sed -E "s/\\b${pfx}_[A-Za-z0-9]{20,}/${MASK}/g")"
if [[ "$legacy_out" == "$MASK"* && "$legacy_out" != "$MASK" ]]; then
  ok "the legacy [A-Za-z0-9] arm leaves a surviving tail on this fixture (pre-fix defect is live)"
else
  bad "the legacy arm did not reproduce the partial-disclosure shape on this fixture (got: ${legacy_out:0:60})"
fi

# --- Row (a): the new-shape token must mask COMPLETELY ------------------------
out_a="$(printf '%s\n' "$tok" | bash "$DRIVER" 2>/dev/null)"
if [[ "$out_a" == *"$MASK"* ]]; then
  ok "new-shape ${pfx}_ token produces the $MASK mask"
else
  bad "new-shape ${pfx}_ token produced NO $MASK mask (output: ${out_a:0:80})"
fi

# ZERO tail bytes survive: the output is exactly the mask, nothing after it.
# Pre-fix this was `<github-server>._~+/=-<tail>` — the credential tail in
# clear text.
tail_probe="${body: -13}"   # the `._~+/=-` remnant + trailing base62 the old arm leaked
if [[ "$out_a" == "$MASK" && "$out_a" != *"$tail_probe"* ]]; then
  ok "zero tail bytes survive — output is exactly $MASK"
else
  bad "tail bytes SURVIVED the mask (partial disclosure; output: ${out_a:0:100})"
fi

# --- Row (a2): embedded context — the token mid-line must mask exactly ------
# The real call site scans multi-field lines; a token inside `x <tok> y` text
# must collapse to `x <github-server> y` with the surrounding bytes intact.
out_a2="$(printf 'x %s y\n' "$tok" | bash "$DRIVER" 2>/dev/null)"
if [[ "$out_a2" == "x $MASK y" ]]; then
  ok "embedded token mid-line masks to exactly 'x $MASK y'"
else
  bad "embedded token mid-line did not mask cleanly (output: ${out_a2:0:100})"
fi

# --- Row (b): a legacy base62 token still masks (positive control) ------------
# Proves the widened arm did not become a tautology that only this fixture
# satisfies: the ~40-char base62 shape must still collapse to the mask.
legacy_tok="${pfx}_${B62:0:40}"
out_b="$(printf '%s\n' "$legacy_tok" | bash "$DRIVER" 2>/dev/null)"
if [[ "$out_b" == "$MASK" ]]; then
  ok "legacy ~40-char base62 ${pfx}_ token still masks to exactly $MASK (positive control)"
else
  bad "legacy base62 ${pfx}_ token no longer masks cleanly (output: ${out_b:0:80})"
fi

# Anti-gutting floor: a neutered suite (deleted behavioural rows) greens
# silently without a counted-assertions ratchet (ADR-193's failure shape).
if [[ $((PASS + FAIL)) -ge 15 ]]; then
  ok "assertion floor: $((PASS + FAIL)) rows executed (floor 15)"
else
  bad "only $((PASS + FAIL)) assertions ran — rows were silently dropped (floor 15)"
fi

echo "=== redact-pii-ghs-shape: $PASS passed, $FAIL failed ==="
if [[ "$FAIL" -eq 0 ]]; then
  echo "redact-pii-ghs-shape: ok"
else
  exit 1
fi
