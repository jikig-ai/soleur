#!/usr/bin/env bash
# Test suite for scripts/registry-pull-path-health.sh (D10, #6929 / #7277).
#
# ── THE CONTRACT THIS SUITE ENFORCES, IN ORDER ───────────────────────────────────────────────
#
# 1. THE GATE CAN GO GREEN. Asserted first, deliberately, because its absence is how the
#    previous revision shipped. That suite had 23 green assertions and NO row asserting rc == 0
#    on a healthy fixture — so when the gate was changed to refuse unconditionally, every
#    assertion still passed. A gate that cannot pass is not a safe gate; it is an unfireable one,
#    and it left the recut unusable during the incident it exists to recover from.
#
# 2. THE GATE CAN GO RED, once per abort class, each asserting its SPECIFIC classified message
#    rather than a bare non-zero rc. A gate that aborts for the wrong reason is a gate whose
#    operator message is a lie.
#
# 3. A5'S ASYMMETRY, pinned in BOTH directions. This is the most dangerous line in the design:
#    an availability failure of the sink (reset / timeout / 5xx) must DEGRADE and proceed, while
#    an authorisation or correctness failure must ABORT. An earlier draft of the plan had
#    `connection reset mid-upload` in the ABORT bucket — that is the literal signature of the
#    live incident (run 30988480437), so it would have deadlocked the gate exactly when needed.
#    Both directions are asserted so a future reader cannot "fix" it back into a deadlock.
#
# The gate protects an IRREVERSIBLE destroy of production's only image store, so every
# could-not-measure outcome is its own aborting class, evaluated BEFORE any comparison.
export TMPDIR="${TMPDIR:-/var/tmp}"

set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${DIR}/../.." && pwd)"
GATE="${ROOT}/scripts/registry-pull-path-health.sh"

TMP="$(mktemp -d)" || { echo "harness: mktemp -d failed — refusing to report a verdict" >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT

passes=0
fails=0
pass() { passes=$((passes + 1)); printf '  ok   %s\n' "$1"; }
fail() {
  fails=$((fails + 1))
  printf '  FAIL %s\n' "$1"; printf '       rc=%s\n' "${2:-?}"; printf '       out=%s\n' "${3:-}"
}

WP="jikig-ai/soleur-web-platform"
IB="jikig-ai/soleur-inngest-bootstrap"
IC="jikig-ai/soleur-inngest-config"
D1="sha256:1111111111111111111111111111111111111111111111111111111111111111"
D2="sha256:2222222222222222222222222222222222222222222222222222222222222222"
VER="0.249.4"
SHA="f838839ef11119ac46f4d38ccf926472dee393a8"
THROWAWAY="127.0.0.1:5555"

# ── seams ────────────────────────────────────────────────────────────────────────────────────
# One per external dependency, each able to emit every classified status token INCLUDING the
# unclassifiable one. A seam that cannot express "could not measure" cannot test the arm that
# matters most here.

# health_stub <file> <body> [rc]
health_stub() {
  { printf '#!/usr/bin/env bash\n'; printf 'printf "%%s" %q\n' "$2"; printf 'exit %s\n' "${3:-0}"; } > "$1"
  chmod +x "$1" || { echo "harness: chmod failed" >&2; exit 2; }
}

# crane_stub <file> <mode> — argv-dispatching. `ok` resolves the two required pins and reports
# the conditional repo absent (which is its measured real state at GHCR).
crane_stub() {
  local f="$1" mode="$2"
  cat > "$f" <<STUB
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "\${GATE_CALLS:-/dev/null}"
sub="\${1:-}"; shift || true
ref="\${1:-}"
[[ -n "\$ref" ]] || { echo "stub: no ref" >&2; exit 64; }
case "\$ref" in
  ghcr.io/*) ;;
  *) echo "stub: A1 must resolve against ghcr.io, got '\$ref'" >&2; exit 64 ;;
esac
case "\$ref" in
  *${IC}*) echo "Error: GET https://ghcr.io/v2/${IC}/manifests/latest: MANIFEST_UNKNOWN: manifest unknown" >&2; exit 1 ;;
esac
case "$mode" in
  ok)       case "\$ref" in *${WP}*) echo "$D1" ;; *) echo "$D2" ;; esac ;;
  notfound) echo "Error: GET https://ghcr.io/v2/${WP}/manifests/v${VER}: MANIFEST_UNKNOWN: manifest unknown" >&2; exit 1 ;;
  denied)   echo "Error: GET https://ghcr.io/token: UNAUTHORIZED: authentication required" >&2; exit 1 ;;
  network)  echo 'Error: Get "https://ghcr.io/v2/": dial tcp: lookup ghcr.io: no such host' >&2; exit 1 ;;
  unknown)  echo "Error: a shape nobody has classified" >&2; exit 1 ;;
  malformed) echo "not-a-digest" ;;
esac
STUB
  chmod +x "$f" || { echo "harness: chmod failed" >&2; exit 2; }
}

# restore_stub <file> <rc> [message]
restore_stub() {
  { printf '#!/usr/bin/env bash\n'
    printf 'printf "%%s\\n" "restore invoked: $*" >> "${GATE_RESTORE_CALLS:-/dev/null}"\n'
    printf 'printf "%%s\\n" %q\n' "${3:-restore_summary result=ok}"
    printf 'exit %s\n' "$2"; } > "$1"
  chmod +x "$1" || { echo "harness: chmod failed" >&2; exit 2; }
}

# drift_stub <file> <dead> <unverifiable> <live> <rc> — mimics check-cloudflare-token-drift.sh,
# which writes its machine-readable verdict to --json-file and returns a coarse rc.
#
# ALL THREE COUNTS ARE MANDATORY. The real zot_mirror_verdict reads `dead`, `unverifiable` AND
# `live`, and treats a missing key as the -1 sentinel rather than as zero — deliberately, so a
# file that measured nothing cannot manufacture a `live` verdict. An earlier version of this
# stub emitted only two keys; every verdict silently collapsed to `unmeasured`, so the
# `stale => ABORT` row passed against a gate that never aborted. A stub that is infidelious to
# its subject's real contract tests the stub, not the subject.
drift_stub() {
  cat > "$1" <<STUB
#!/usr/bin/env bash
printf '%s\n' "detector invoked" >> "\${GATE_DRIFT_CALLS:-/dev/null}"
jf=""
while [[ \$# -gt 0 ]]; do
  case "\$1" in --json-file) jf="\${2:-}"; shift 2 ;; *) shift ;; esac
done
[[ -n "\$jf" ]] || { echo "stub: detector called without --json-file, so nothing could be graded" >&2; exit 64; }
printf '{"dead":%s,"unverifiable":%s,"live":%s}' "$2" "$3" "$4" > "\$jf"
exit $5
STUB
  chmod +x "$1" || { echo "harness: chmod failed" >&2; exit 2; }
}

# sink_stub <file> <verdict-token> — A5's live probe against prod zot.
sink_stub() {
  { printf '#!/usr/bin/env bash\n'; printf 'printf "%%s" %q\n' "$2"; } > "$1"
  chmod +x "$1" || { echo "harness: chmod failed" >&2; exit 2; }
}

OK_HEALTH="{\"status\":\"ok\",\"version\":\"${VER}\",\"build_sha\":\"${SHA}\",\"uptime\":91973}"

# world <dir> — an all-good environment; individual cases override one seam each.
world() {
  local d="$1"; mkdir -p "$d" || { echo "harness: mkdir failed" >&2; exit 2; }
  health_stub  "$d/health"  "$OK_HEALTH"
  crane_stub   "$d/crane"   ok
  restore_stub "$d/restore" 0
  drift_stub   "$d/drift"   0 0 3 0   # dead=0 unverifiable=0 live=3 rc=0 -> the `live` arm
  sink_stub    "$d/sink"    "ok"
  printf '%s' "$d"
}

# run_gate <dir> [args...]
run_gate() {
  local d="$1"; shift
  REGISTRY_GATE_HEALTH_CMD="$d/health" \
  REGISTRY_GATE_CRANE_CMD="$d/crane" \
  REGISTRY_GATE_RESTORE_CMD="$d/restore" \
  REGISTRY_GATE_DRIFT_CMD="$d/drift" \
  REGISTRY_GATE_SINK_CMD="$d/sink" \
  APP_DOMAIN_BASE="${APP_DOMAIN_BASE-soleur.ai}" \
  ZOT_PUSH_USER="${ZOT_PUSH_USER-u}" ZOT_PUSH_TOKEN="${ZOT_PUSH_TOKEN-t}" \
  GATE_CALLS="${GATE_CALLS:-/dev/null}" \
  GATE_DRIFT_CALLS="${GATE_DRIFT_CALLS:-/dev/null}" \
  GATE_RESTORE_CALLS="${GATE_RESTORE_CALLS:-/dev/null}" \
    bash "$GATE" --rehearse-target "$THROWAWAY" "$@" 2>&1
}

printf '\n=== registry-pull-path-health ===\n\n'

# ── AC4: THE GREEN ROW. First, because its absence is the defect being fixed. ────────────────
W="$(world "$TMP/w-ok")"
out="$(run_gate "$W")"; rc=$?
if [[ "$rc" -eq 0 ]]; then
  pass "all-good fixture => rc 0 (THE green row — the criterion whose absence shipped an unpassable gate)"
else
  fail "the all-good fixture MUST pass; a gate that cannot go green is unfireable" "$rc" "$out"
fi

if printf '%s' "$out" | grep -qF "verdict=AUTHORIZED"; then
  pass "the green verdict is stated in machine-readable form"
else
  fail "a passing gate must state its verdict explicitly" "$rc" "$out"
fi

# ── A0 — inventory derivation from production's OWN pins. ───────────────────────────────────
W="$(world "$TMP/w-health-down")"
health_stub "$W/health" "" 1
out="$(run_gate "$W")"; rc=$?
# Assert the exit-code guard SPECIFICALLY. The empty-.version guard downstream also emits an A0
# abort, so a row matching only "A0" passes identically against a gate that ignores health_rc.
if [[ "$rc" -ne 0 ]] && printf '%s' "$out" | grep -qF "could not read"; then
  pass "A0: /health unreachable => ABORT by the exit-code guard (could-not-measure aborts)"
else
  fail "an unreachable /health must abort, naming A0" "$rc" "$out"
fi

W="$(world "$TMP/w-health-garbage")"
health_stub "$W/health" "<html>504 Gateway Timeout</html>"
out="$(run_gate "$W")"; rc=$?
if [[ "$rc" -ne 0 ]]; then
  pass "A0: a non-JSON /health body => ABORT, never a parsed empty version"
else
  fail "an unparseable /health must not yield an empty inventory" "$rc" "$out"
fi

# build_sha as well as version: a cached edge response carrying a previous version would
# otherwise satisfy the membership assertion while the actually-running build is unrestorable.
W="$(world "$TMP/w-health-nosha")"
health_stub "$W/health" "{\"status\":\"ok\",\"version\":\"${VER}\"}"
out="$(run_gate "$W")"; rc=$?
if [[ "$rc" -ne 0 ]] && printf '%s' "$out" | grep -qF "build_sha"; then
  pass "A0: /health without build_sha => ABORT (a cached edge response cannot satisfy A0)"
else
  fail "A0 must assert build_sha as well as version" "$rc" "$out"
fi

# ── A1 — source proof. Every non-OK classification aborts, each with its own message. ───────
for mode in notfound denied network unknown malformed; do
  W="$(world "$TMP/w-a1-$mode")"
  crane_stub "$W/crane" "$mode"
  out="$(run_gate "$W")"; rc=$?
  if [[ "$rc" -ne 0 ]]; then
    pass "A1: crane '$mode' => ABORT"
  else
    fail "A1 must abort on a '$mode' source result" "$rc" "$out"
  fi
done

# The NOTFOUND message may not claim the image is gone: GHCR masks a repo that exists but is not
# visible to the credential as MANIFEST_UNKNOWN, identical to genuinely-absent (measured
# 2026-08-05). Claiming "deleted" would name a cause the gate did not measure.
W="$(world "$TMP/w-a1-wording")"
crane_stub "$W/crane" notfound
out="$(run_gate "$W")"; rc=$?
if printf '%s' "$out" | grep -qiE 'not visible|packages: read|credential'; then
  pass "A1: NOTFOUND admits 'absent OR not visible to this credential'"
else
  fail "A1's NOTFOUND must not assert the image was deleted" "$rc" "$out"
fi

# UNKNOWN is the loudest arm — an unclassified failure must read as neither 'absent' nor 'fine'.
W="$(world "$TMP/w-a1-unknown")"
crane_stub "$W/crane" unknown
out="$(run_gate "$W")"; rc=$?
if printf '%s' "$out" | grep -qF "UNKNOWN"; then
  pass "A1: an unclassifiable source failure is reported as UNKNOWN, not absent"
else
  fail "the default classifier arm must name itself UNKNOWN" "$rc" "$out"
fi

# ── A2 — the rehearsed restore. ──────────────────────────────────────────────────────────────
CALLS="$TMP/restore-calls"; : > "$CALLS"
W="$(world "$TMP/w-a2-ok")"
out="$(GATE_RESTORE_CALLS="$CALLS" run_gate "$W")"; rc=$?
if [[ -s "$CALLS" ]] && grep -qF -- "--target ${THROWAWAY}" "$CALLS"; then
  pass "A2: the rehearsal invokes the restore engine against the throwaway"
else
  fail "A2 must actually run the restore engine" "$rc" "$(cat "$CALLS")"
fi

# Every restore exit code must abort the gate — the rehearsal is the PASS condition, so any
# failure of it is a failure to establish authorisation.
for code in 2 3 4 5 6; do
  W="$(world "$TMP/w-a2-$code")"
  restore_stub "$W/restore" "$code"
  out="$(run_gate "$W")"; rc=$?
  if [[ "$rc" -ne 0 ]]; then
    pass "A2: rehearsal exit $code => ABORT (no authorisation without a proven restore)"
  else
    fail "a failed rehearsal (exit $code) must abort the gate" "$rc" "$out"
  fi
done

# The per-code operator action must be reachable from the gate's own output, or the six
# enumerated codes are a contract nobody can act on.
W="$(world "$TMP/w-a2-msg")"
restore_stub "$W/restore" 3
out="$(run_gate "$W")"; rc=$?
if printf '%s' "$out" | grep -qF "exit 3"; then
  pass "A2: the abort names the restore's specific exit code"
else
  fail "a rehearsal failure must name which exit code it was" "$rc" "$out"
fi

# ── A3 — the non-vacuity floor. ─────────────────────────────────────────────────────────────
# The single most likely way this gate fails open is an EMPTY inventory: every loop then passes
# and it goes green having proven nothing.
if grep -qE '^[[:space:]]*(readonly[[:space:]]+)?FLOOR=' "$GATE"; then
  pass "A3: FLOOR is a declared source-level constant"
else
  fail "A3 needs a declared FLOOR constant" "?" "$(grep -n 'FLOOR' "$GATE" | head -3)"
fi

# The arity self-check: the declared required-pin count must equal FLOOR, asserted in source, so
# a careless edit downgrading a `required` entry to `conditional` cannot silently shrink the
# obligation. This is the idiom the old ${#WATCHED[@]} check carried, re-pointed at the pin set.
# Structural, deliberately: this is a SOURCE-consistency self-check (the successor to the old
# signal-array arity check) and cannot fire through any runtime input, so a behavioural row for
# it would be impossible to write honestly. Assert the comparison exists, in its real form.
if grep -qE 'declared_required[[:space:]]*!=[[:space:]]*FLOOR' "$GATE"; then
  pass "A3: the declared pin set is compared to FLOOR in source (arity self-check)"
else
  fail "the arity self-check must compare the declared pin set to FLOOR" "?" ""
fi

# ── A4 — sink-credential validity, graded live at the Cloudflare Access edge. ───────────────
# `stale` is the ONLY arm on which rotation is the remedy, and the only one that aborts.
W="$(world "$TMP/w-a4-stale")"
drift_stub "$W/drift" 1 0 0 1   # a MEASURED dead count
out="$(run_gate "$W")"; rc=$?
if [[ "$rc" -ne 0 ]] && printf '%s' "$out" | grep -qF "MEASURED DEAD"; then
  pass "A4: verdict 'stale' (a MEASURED dead count) => ABORT by the stale arm specifically"
else
  fail "a measured-dead sink credential must abort before the destroy" "$rc" "$out"
fi

# `unverifiable` is a measured 'could not tell' and is explicitly NOT an accusation — the
# detector's own cause vocabulary all carries 'Do NOT rotate'. It degrades.
W="$(world "$TMP/w-a4-unver")"
drift_stub "$W/drift" 0 1 0 1   # measured "could not tell"
out="$(run_gate "$W")"; rc=$?
if [[ "$rc" -eq 0 ]]; then
  pass "A4: verdict 'unverifiable' => DEGRADE, not abort (it is not an accusation)"
else
  fail "unverifiable must not abort — it would deadlock on the detector's own blind spots" "$rc" "$out"
fi

# THE A4 TRAP. zot_mirror_verdict makes ZERO network calls: it grades a JSON file the detector
# must write first. Skipping the detector does not fail — it returns `unmeasured`, which maps to
# DEGRADE, producing a predicate that runs, prints, and can NEVER abort. That is the dark-operand
# defect this whole change exists to remove, reintroduced in the predicate meant to close it.
DCALLS="$TMP/drift-calls"; : > "$DCALLS"
W="$(world "$TMP/w-a4-detector")"
out="$(GATE_DRIFT_CALLS="$DCALLS" run_gate "$W")"; rc=$?
if [[ -s "$DCALLS" ]]; then
  pass "A4: the DETECTOR is invoked, not just the grader (else A4 can never abort)"
else
  fail "A4 must run check-cloudflare-token-drift.sh before grading its output" "$rc" "$out"
fi

if grep -qE 'zot_mirror_verdict|zot-mirror-diagnosis' "$GATE"; then
  pass "A4: the gate consumes the repo's live credential grader, not a non-emptiness check"
else
  fail "A4 must call zot_mirror_verdict" "?" ""
fi

# A verdict outside the grader's documented four-value vocabulary must not be read as either
# health or failure. Unreachable through the real grader (its vocabulary is closed), which is
# exactly why the arm needs a seam — an abort arm no test can reach is indistinguishable from a
# missing one, and a mutation deleting it survived the suite before this row existed.
W="$(world "$TMP/w-a4-vocab")"
printf '#!/usr/bin/env bash\nprintf "%%s" "probably-fine"\n' > "$W/verdict"; chmod +x "$W/verdict"
out="$(REGISTRY_GATE_VERDICT_CMD="$W/verdict" run_gate "$W")"; rc=$?
if [[ "$rc" -ne 0 ]]; then
  pass "A4: a verdict outside the closed vocabulary => ABORT (never read as health)"
else
  fail "an unrecognised credential verdict must abort" "$rc" "$out"
fi

# ── A3's outcome floor, on a REACHABLE input. ───────────────────────────────────────────────
# A required pin whose tag cannot be derived from committed config is recorded as MISSED and
# left to the floor. This is the input that makes the floor a live guard: with an immediate
# abort in its place, the floor was unreachable and a mutation deleting it went undetected.
W="$(world "$TMP/w-a3-underivable")"
out="$(REGISTRY_GATE_CLOUD_INIT="$TMP/nonexistent-cloud-init.yml" run_gate "$W")"; rc=$?
if [[ "$rc" -ne 0 ]] && printf '%s' "$out" | grep -qF "A3"; then
  pass "A3: an underivable required pin falls to the floor and ABORTS (floor is reachable)"
else
  fail "an underivable required pin must abort via the A3 floor" "$rc" "$out"
fi

if printf '%s' "$out" | grep -qF "missed:"; then
  pass "A3: the abort names WHICH required pin was missed"
else
  fail "the floor abort must name the missed pin, not just the count" "$rc" "$out"
fi

# ── The PREPARE→engine handoff. ─────────────────────────────────────────────────────────────
# The manifest this gate writes is the restore engine's only input, so its shape is a contract
# between two files that no other test spans.
W="$(world "$TMP/w-prepare")"
out="$(run_gate "$W" --prepare --tags-out "$TMP/pins-out.json")"; rc=$?
if [[ "$rc" -eq 0 ]] && jq -e . "$TMP/pins-out.json" >/dev/null 2>&1; then
  pass "PREPARE writes a manifest that parses as JSON"
else
  fail "the emitted manifest must be valid JSON" "$rc" "$out"
fi

n_req=$(jq -r '[.entries[] | select(.disposition == "required")] | length' "$TMP/pins-out.json" 2>/dev/null)
n_floor=$(jq -r '.floor' "$TMP/pins-out.json" 2>/dev/null)
if [[ "$n_req" == "$n_floor" ]]; then
  pass "the emitted manifest's required count equals its declared floor (the engine rejects otherwise)"
else
  fail "manifest required=$n_req vs floor=$n_floor — the engine would reject this" "?" ""
fi

# The conditional entry must survive into the manifest EVEN THOUGH it did not resolve. Dropping
# it makes the engine's own conditional arm unreachable in the real pipeline — the engine would
# only ever receive `required` entries, so the branch that skips an absent conditional would be
# dead code exercised solely by the engine's suite with a hand-written manifest.
if jq -e '[.entries[] | select(.disposition == "conditional")] | length >= 1' "$TMP/pins-out.json" >/dev/null 2>&1; then
  pass "an unresolved conditional pin is still EMITTED, keeping the engine's conditional arm live"
else
  fail "conditional pins must reach the manifest, or the engine's skip branch is dead code" "?" \
    "$(cat "$TMP/pins-out.json")"
fi

# ── A5 — THE ABORT/DEGRADE BOUNDARY. Both directions. ───────────────────────────────────────
# Authorisation and correctness failures abort; availability failures degrade.
W="$(world "$TMP/w-a5-rejected")"
sink_stub "$W/sink" "credential_rejected"
out="$(run_gate "$W")"; rc=$?
if [[ "$rc" -ne 0 ]]; then
  pass "A5: sink credential REJECTED => ABORT (unrecoverable after a destroy)"
else
  fail "a rejected sink credential must abort" "$rc" "$out"
fi

W="$(world "$TMP/w-a5-wrongdigest")"
sink_stub "$W/sink" "wrong_digest"
out="$(run_gate "$W")"; rc=$?
if [[ "$rc" -ne 0 ]]; then
  pass "A5: write completed with the WRONG DIGEST => ABORT (a correctness failure)"
else
  fail "a correctness failure at the sink must abort" "$rc" "$out"
fi

# The direction that matters most. `connection reset by peer` mid-upload is the literal failure
# text of run 30988480437 — the incident this gate exists to authorise recovery from. Aborting
# on it re-creates the deadlock.
W="$(world "$TMP/w-a5-reset")"
sink_stub "$W/sink" "connection_reset"
out="$(run_gate "$W")"; rc=$?
if [[ "$rc" -eq 0 ]]; then
  pass "A5: connection reset mid-upload => DEGRADE AND PROCEED (the motivating incident)"
else
  fail "A5 MUST NOT abort on an availability failure — that is the deadlock being removed" "$rc" "$out"
fi

if printf '%s' "$out" | grep -qF "sink_probe=unmeasured"; then
  pass "A5: the degradation is NAMED and logged, not silent"
else
  fail "a degraded A5 must record sink_probe=unmeasured" "$rc" "$out"
fi

W="$(world "$TMP/w-a5-timeout")"
sink_stub "$W/sink" "timeout"
out="$(run_gate "$W")"; rc=$?
if [[ "$rc" -eq 0 ]]; then
  pass "A5: sink timeout => DEGRADE AND PROCEED (availability, not authorisation)"
else
  fail "a sink timeout must degrade, not abort" "$rc" "$out"
fi

# An unclassifiable sink outcome degrades too — A5 is the deliberate INVERSE of the fail-closed
# rule used everywhere else in this gate, because here the unmeasurability IS the incident.
W="$(world "$TMP/w-a5-unknown")"
sink_stub "$W/sink" "something_new"
out="$(run_gate "$W")"; rc=$?
if [[ "$rc" -eq 0 ]]; then
  pass "A5: an unclassifiable sink outcome => DEGRADE (A5 inverts the fail-closed rule on purpose)"
else
  fail "A5's unknown arm must degrade; elsewhere unknown aborts, and that asymmetry is the point" "$rc" "$out"
fi

# ── Structural properties. ──────────────────────────────────────────────────────────────────
STRIP="$TMP/gate-nocomments.sh"
grep -vE '^[[:space:]]*#' "$GATE" > "$STRIP" || { echo "harness: could not strip comments" >&2; exit 2; }

# The mask emit must be Actions-scoped: outside a runner `::add-mask::` is a plain echo that
# prints the live prd credential to the operator's terminal, and the runbook tells them to run
# this gate locally. Measured on a comments-stripped copy — the header explains ::add-mask:: in
# prose, and a bare body-grep would count that sentence as an emit.
mask_emits=$(grep -c 'echo "::add-mask::' "$STRIP" || true)
mask_guarded=$(grep -B2 'echo "::add-mask::' "$STRIP" | grep -c 'GITHUB_ACTIONS' || true)
if [[ "$mask_emits" -ge 1 && "$mask_guarded" -ge "$mask_emits" ]]; then
  pass "every ::add-mask:: emit is guarded on GITHUB_ACTIONS (no local token echo)"
else
  fail "::add-mask:: must be Actions-scoped or it leaks the token locally" \
    "emits=$mask_emits guarded=$mask_guarded" ""
fi

# The verdict switch must have no default-pass arm.
if grep -qE '^[[:space:]]*\*\)' "$STRIP" && ! grep -qE '^[[:space:]]*\*\).*(exit 0|verdict=AUTHORIZED)' "$STRIP"; then
  pass "no classifier default arm falls through to a pass"
else
  fail "a default-pass arm would make every unclassified input read as authorisation" "?" \
    "$(grep -nE '^[[:space:]]*\*\)' "$STRIP" | head -5)"
fi

# AC8: the Sentry arm is gone, asserted mechanically.
sentry_hits=$(grep -cE 'sentry\.io|SENTRY_AUTH_TOKEN|WATCHED|sentry_count' "$GATE" || true)
if [[ "$sentry_hits" -eq 0 ]]; then
  pass "AC8: the Sentry counter arm is entirely gone"
else
  fail "AC8: no Sentry operand may remain" "$sentry_hits" \
    "$(grep -nE 'sentry\.io|SENTRY_AUTH_TOKEN|WATCHED|sentry_count' "$GATE" | head -5)"
fi

# AC1: the self-reference trap. The rewritten header wants to explain its own history and the
# literal phrase is the natural way to do it — but the runbook's done-signal is a WHOLE-FILE
# count, so a single mention in a comment re-breaks it.
if [[ "$(grep -c 'no valid PASS condition' "$GATE")" -eq 0 ]]; then
  pass "AC1: the literal 'no valid PASS condition' appears nowhere, including commentary"
else
  fail "AC1: the runbook's done-signal is a whole-file grep; even a comment breaks it" "?" \
    "$(grep -n 'no valid PASS condition' "$GATE")"
fi

# AC9: no daemon-side pull in any verification path — a local image cache would satisfy one
# without the registry being contacted at all.
if [[ "$(grep -c 'docker pull' "$GATE")" -eq 0 ]]; then
  pass "AC9: no 'docker pull' anywhere in the gate"
else
  fail "AC9: the verification path must not use a daemon-side pull" "?" \
    "$(grep -n 'docker pull' "$GATE")"
fi

# The removed arm's operands must be gone with it, not left dangling.
if [[ "$(grep -cE 'ghcr-fallback|local-cache|zot-gate-degraded' "$STRIP")" -eq 0 ]]; then
  pass "the dark ghcr-fallback operand and its siblings are gone from the gate body"
else
  fail "no removed operand may survive in executable code" "?" \
    "$(grep -nE 'ghcr-fallback|local-cache|zot-gate-degraded' "$STRIP" | head -3)"
fi

# ── Argument validation. ────────────────────────────────────────────────────────────────────
W="$(world "$TMP/w-args")"
out="$(run_gate "$W" --nope)"; rc=$?
if [[ "$rc" -ne 0 ]] && printf '%s' "$out" | grep -qiF "unknown argument"; then
  pass "unknown argument rejected"
else
  fail "an unknown argument must be rejected" "$rc" "$out"
fi

out="$(REGISTRY_GATE_HEALTH_CMD="$W/health" REGISTRY_GATE_CRANE_CMD="$W/crane" \
       REGISTRY_GATE_RESTORE_CMD="$W/restore" REGISTRY_GATE_DRIFT_CMD="$W/drift" \
       REGISTRY_GATE_SINK_CMD="$W/sink" APP_DOMAIN_BASE=soleur.ai \
       ZOT_PUSH_USER=u ZOT_PUSH_TOKEN=t bash "$GATE" 2>&1)"; rc=$?
if [[ "$rc" -ne 0 ]] && printf '%s' "$out" | grep -qF -- "--rehearse-target"; then
  pass "--rehearse-target is required for a verdict (A2 cannot be skipped)"
else
  fail "the gate must refuse to render a verdict without a rehearsal target" "$rc" "$out"
fi

printf '\n=== %d passed, %d failed ===\n\n' "$passes" "$fails"
[[ "$fails" -eq 0 ]]
