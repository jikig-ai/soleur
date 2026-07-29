#!/usr/bin/env bash
#
# (#7025) Test suite for scripts/followthroughs/git-data-rung2-evidence-capture.sh.
#
# EVERY ARM STUBS betterstack-query.sh. The script under test is the thing that decides
# whether a production host holding every connected user's source code is allowed to be
# born, so its decision function has to be exercised against every shape the log source can
# return — including the shapes a real rehearsal would be unlucky to produce.
#
# THE PROPERTY THAT MATTERS MOST IS THE ONE ABOUT SILENCE. A Better Stack query returning
# zero rows for a brand-new host is ambiguous between "the host booted dark" and "my query,
# my credentials or the source itself is broken". Reading the first as the second grounds a
# rehearsal that actually failed; reading the second as the first writes evidence for a boot
# nobody observed. The script resolves it with a SOURCE-LIVENESS anchor, and the arms below
# pin both directions.

set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${DIR}/../.." && pwd)"
SUT="${ROOT}/scripts/followthroughs/git-data-rung2-evidence-capture.sh"

TMP="$(mktemp -d -t gdr2cap.XXXXXXXX)" || { echo "mktemp failed" >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT

passes=0
fails=0
pass() { passes=$((passes + 1)); printf '  ok   %s\n' "$1"; }
fail() {
  fails=$((fails + 1))
  printf '  FAIL %s\n' "$1"
  [[ -n "${2:-}" ]] && printf '       rc=%s\n' "$2"
  [[ -n "${3:-}" ]] && printf '       out=%s\n' "$3"
  return 0
}

printf '\n=== git-data-rung2-evidence-capture ===\n\n'

if [[ ! -f "$SUT" ]]; then
  fail "the capture script exists at ${SUT}" "n/a" "not found"
  printf '\n=== 0 passed, 1 failed ===\n\n'
  exit 1
fi

HOST="soleur-git-data-rehearsal-17250000001"
URL="https://github.com/jikig-ai/soleur/actions/runs/17250000001"

# A minimal fixture tree the SHARED hash helper can resolve: the template, the render module
# with nine bindings, and the nine payloads. Mirrors production's layout because the helper
# resolves `${path.module}/../../` against the module directory.
FIX="$TMP/fix"; mkdir -p "$FIX/modules/git-data-userdata"
printf '#cloud-config\nruncmd:\n  - [ bash, -c, "curl -sf ${sentry_dsn}" ]\n' > "$FIX/cloud-init-git-data.yml"
_payloads=(git-data-bootstrap.sh git-data-provision.sh git-data-transport-wrapper.sh
           git-data-remove.sh git-data-gc.sh git-data-pre-receive-placeholder.sh
           git-data-gc.service git-data-gc-failure.service git-data-gc.timer)
{
  printf 'locals {\n  rendered = templatefile("${path.module}/../../cloud-init-git-data.yml", {\n'
  for _p in "${_payloads[@]}"; do
    printf '    %s = replace(file("${path.module}/../../%s"), local.git_data_rationale_strip, "")\n' \
      "${_p//[-.]/_}" "$_p"
  done
  printf '  })\n}\n'
} > "$FIX/modules/git-data-userdata/main.tf"
for _p in "${_payloads[@]}"; do printf '#!/usr/bin/env bash\ntrue\n' > "$FIX/$_p"; done

# ── The stub ──────────────────────────────────────────────────────────────────────
#
# It answers by MATCHING THE SQL IT IS HANDED, not by call ordinal. A counter-based stub
# encodes the script's current call ORDER into the fixture, so any reordering breaks every
# arm for a reason unrelated to the property under test — and, worse, a stub that returns the
# right rows in the wrong order can make a broken script look correct.
#
# Each canned response is a file of JSONEachRow lines, keyed by which query shape asked.
make_stub() {  # $1=stubpath  $2=anchor-rows-file  $3=host-rows-file
  cat > "$1" <<STUB
#!/usr/bin/env bash
sql="\$1"
if printf '%s' "\$sql" | grep -q '__ANCHOR__'; then
  cat "$2"
elif printf '%s' "\$sql" | grep -q '__HOSTROWS__'; then
  cat "$3"
else
  echo "STUB: unrecognised query shape" >&2
  exit 3
fi
STUB
  chmod +x "$1"
}

row() {  # $1=stage $2=level [k=v ...]
  local stage="$1" level="$2"; shift 2
  local extra="" kv
  for kv in "$@"; do extra="${extra},\"${kv%%=*}\":\"${kv#*=}\""; done
  printf '{"dt":"2026-07-29 12:00:00","stage":"%s","level":"%s","host_name":"%s"%s}\n' \
    "$stage" "$level" "$HOST" "$extra"
}

# --divergence is REQUIRED (#7066 review). The script used to echo the gate's own allowlist
# back out, which made the gate's check allowlist-subset-of-allowlist and refused nothing; it
# reads Better Stack, not terraform state, so it cannot derive the set and must be told.
DIVERGENCE="host_name,git_data_volume_id,doppler_token"
run_sut() {  # remaining args appended
  BETTERSTACK_QUERY_SH="$STUB" \
  BETTERSTACK_QUERY_HOST=stub BETTERSTACK_QUERY_USERNAME=stub BETTERSTACK_QUERY_PASSWORD=stub \
    bash "$SUT" --host-name "$HOST" --evidence-url "$URL" --divergence "$DIVERGENCE" \
      --cloud-init "$FIX/cloud-init-git-data.yml" "$@" 2>&1
}

STUB="$TMP/bs-stub.sh"
ANCHOR_LIVE="$TMP/anchor-live.jsonl"
ANCHOR_DEAD="$TMP/anchor-dead.jsonl"
printf '{"dt":"2026-07-29 11:59:00","host_name":"soleur-web-1"}\n' > "$ANCHOR_LIVE"
: > "$ANCHOR_DEAD"

# ── ARM 1: the PASS path ──────────────────────────────────────────────────────────
HOSTROWS="$TMP/rows-pass.jsonl"
row boot_complete info luks_mounted=yes repo_root=yes hooks_path=yes provision=yes > "$HOSTROWS"
make_stub "$STUB" "$ANCHOR_LIVE" "$HOSTROWS"
OUT="$TMP/evidence-pass.env"
out="$(run_sut --out "$OUT")"; rc=$?
if [[ "$rc" -eq 0 ]]; then pass "all-positive boot_complete => exit 0 (PASS)"; else
  fail "all-positive boot_complete => exit 0 (PASS)" "$rc" "$out"; fi
if [[ -f "$OUT" ]]; then pass "PASS writes the evidence file"; else
  fail "PASS writes the evidence file" "$rc" "$out"; fi

# The evidence must be ACCEPTED BY THE GATE, not merely written. This is the arm that binds
# producer to consumer: a capture script whose output the gate refuses is a rehearsal that
# cost a real host and released nothing.
if [[ -f "$OUT" ]]; then
  # shellcheck source=/dev/null
  source "${ROOT}/tests/scripts/lib/git-data-birth-readiness-gate.sh"
  if gate_out="$(git_data_rung2_rehearsal_gate "$FIX/cloud-init-git-data.yml" "$OUT" 2>&1)"; then
    pass "the written evidence RELEASES the rung-2 gate (producer/consumer are bound)"
  else
    fail "the written evidence does not satisfy the gate it exists to release" "1" "$gate_out"
  fi
fi

for _k in RUNG2_BOOT_REHEARSAL RUNG2_EVIDENCE_URL RUNG2_TEMPLATE_SHA256 RUNG2_VAR_DIVERGENCE; do
  if grep -qE "^${_k}=" "$OUT" 2>/dev/null; then pass "evidence carries ${_k}"; else
    fail "evidence carries ${_k}" "n/a" "$(cat "$OUT" 2>/dev/null)"; fi
done

# Each artifact must be recorded WITH THE QUERY THAT RETRIEVED IT. An evidence file that
# asserts a result without the question is unreproducible: the next reader cannot tell a
# real observation from a typo in a WHERE clause.
if grep -q 'QUERY' "$OUT" 2>/dev/null; then
  pass "evidence records the queries that produced it"
else
  fail "evidence records the queries that produced it" "n/a" "$(cat "$OUT" 2>/dev/null)"
fi

# ── ARM 2: the FAIL path — a fatal from this host ─────────────────────────────────
#
# (#7025, R5) THE FAIL ARM IS `level=fatal`, NOT a `\bno\b` MATCH ON THE BOOLEANS.
# git-data-bootstrap.sh emits boot_complete's four booleans as HARDCODED LITERALS -- its own
# comment says "The booleans are all `yes` by construction here" -- so a dark boot produces
# NO boot_complete at all, and the inherited `\bno\b` arm is dead against real telemetry. What
# a dark boot actually produces is a fatal at luks_open or bootstrap.
HOSTROWS_FAIL="$TMP/rows-fail.jsonl"
row luks_open fatal detail="cryptsetup luksOpen failed rc=1" > "$HOSTROWS_FAIL"
make_stub "$STUB" "$ANCHOR_LIVE" "$HOSTROWS_FAIL"
OUT_FAIL="$TMP/evidence-fail.env"
out="$(run_sut --out "$OUT_FAIL")"; rc=$?
if [[ "$rc" -eq 1 ]]; then pass "a fatal at luks_open => exit 1 (FAIL)"; else
  fail "a fatal at luks_open => exit 1 (FAIL)" "$rc" "$out"; fi
if [[ ! -f "$OUT_FAIL" ]]; then pass "FAIL writes NO evidence file"; else
  fail "FAIL writes NO evidence file" "$rc" "an evidence file was written on a FAIL"; fi
if [[ "$out" == *"luks_open"* ]]; then pass "the FAIL names the stage that died"; else
  fail "the FAIL names the stage that died" "$rc" "$out"; fi

# A fatal alongside a later boot_complete is still a FAIL. The boot recovered enough to
# report completion, but something in the chain hit its trap -- and this rehearsal exists to
# find exactly that, so "ended fine" must not overwrite "went wrong".
HOSTROWS_BOTH="$TMP/rows-both.jsonl"
{ row bootstrap fatal detail="transient"
  row boot_complete info luks_mounted=yes repo_root=yes hooks_path=yes provision=yes; } > "$HOSTROWS_BOTH"
make_stub "$STUB" "$ANCHOR_LIVE" "$HOSTROWS_BOTH"
OUT_BOTH="$TMP/evidence-both.env"
out="$(run_sut --out "$OUT_BOTH")"; rc=$?
if [[ "$rc" -eq 1 ]]; then pass "a fatal ALONGSIDE a boot_complete => still FAIL"; else
  fail "a fatal ALONGSIDE a boot_complete => still FAIL" "$rc" "$out"; fi

# The inherited `\bno\b` check is retained as a SECOND FAIL trigger, because it costs nothing
# and it is the arm that fires if the consumer's assertions are ever weakened to real values.
HOSTROWS_NO="$TMP/rows-no.jsonl"
row boot_complete info luks_mounted=no repo_root=yes hooks_path=yes provision=yes > "$HOSTROWS_NO"
make_stub "$STUB" "$ANCHOR_LIVE" "$HOSTROWS_NO"
out="$(run_sut --out "$TMP/evidence-no.env")"; rc=$?
if [[ "$rc" -eq 1 ]]; then pass "boot_complete with a FALSE assertion => FAIL"; else
  fail "boot_complete with a FALSE assertion => FAIL" "$rc" "$out"; fi

# ── ARM 3: TRANSIENT — the host said nothing, but the channel is demonstrably live ──
HOSTROWS_EMPTY="$TMP/rows-empty.jsonl"
: > "$HOSTROWS_EMPTY"
make_stub "$STUB" "$ANCHOR_LIVE" "$HOSTROWS_EMPTY"
OUT_T="$TMP/evidence-transient.env"
out="$(run_sut --out "$OUT_T")"; rc=$?
if [[ "$rc" -eq 2 ]]; then pass "no rows from this host, live channel => exit 2 (TRANSIENT)"; else
  fail "no rows from this host, live channel => exit 2 (TRANSIENT)" "$rc" "$out"; fi
if [[ ! -f "$OUT_T" ]]; then pass "TRANSIENT writes NO evidence file"; else
  fail "TRANSIENT writes NO evidence file" "$rc" "an evidence file was written on a TRANSIENT"; fi

# ── ARM 4: THE EMPTY-QUERY DISCIPLINE ─────────────────────────────────────────────
#
# The anchor is dead AND the host said nothing. Zero rows everywhere is the shape a broken
# credential, an unreachable source or a typo'd table produces -- indistinguishable from a
# dark boot by looking at the host's rows alone. It must NOT be reported as a finding about
# the host, and it must never write evidence.
make_stub "$STUB" "$ANCHOR_DEAD" "$HOSTROWS_EMPTY"
OUT_D="$TMP/evidence-dead.env"
out="$(run_sut --out "$OUT_D")"; rc=$?
if [[ "$rc" -eq 2 ]]; then pass "a DEAD source anchor => TRANSIENT, never FAIL"; else
  fail "a DEAD source anchor => TRANSIENT, never FAIL" "$rc" "$out"; fi
if [[ "$out" == *"anchor"* || "$out" == *"source"* ]]; then
  pass "the TRANSIENT distinguishes a dead channel from a silent host"
else
  fail "the TRANSIENT distinguishes a dead channel from a silent host" "$rc" "$out"
fi
if [[ ! -f "$OUT_D" ]]; then pass "a dead anchor writes NO evidence file"; else
  fail "a dead anchor writes NO evidence file" "$rc" "evidence written with no live channel"; fi

# THE ANCHOR MUST NOT BE SATISFIED BY THE HOST'S OWN ROWS. If it were, "this host emitted
# nothing" would make the anchor dead too, collapsing the two states the anchor exists to
# separate -- and the script would report TRANSIENT forever on a genuinely dark boot.
ANCHOR_SELF="$TMP/anchor-self.jsonl"
printf '{"dt":"2026-07-29 11:59:00","host_name":"%s"}\n' "$HOST" > "$ANCHOR_SELF"
make_stub "$STUB" "$ANCHOR_SELF" "$HOSTROWS_EMPTY"
out="$(run_sut --out "$TMP/evidence-self.env")"; rc=$?
if [[ "$rc" -eq 2 ]]; then pass "an anchor carrying only this host's rows still => TRANSIENT"; else
  fail "an anchor carrying only this host's rows still => TRANSIENT" "$rc" "$out"; fi

# ── ARM 5: the query transport failing is TRANSIENT, never FAIL ───────────────────
cat > "$STUB" <<'STUB'
#!/usr/bin/env bash
echo "connection refused" >&2
exit 7
STUB
chmod +x "$STUB"
out="$(run_sut --out "$TMP/evidence-unreach.env")"; rc=$?
if [[ "$rc" -eq 2 ]]; then pass "an unreachable/unauthorised query => TRANSIENT"; else
  fail "an unreachable/unauthorised query => TRANSIENT" "$rc" "$out"; fi

# ── ARM 6: fail-closed input ──────────────────────────────────────────────────────
make_stub "$STUB" "$ANCHOR_LIVE" "$HOSTROWS"
out="$(BETTERSTACK_QUERY_SH="$STUB" BETTERSTACK_QUERY_HOST=stub \
       BETTERSTACK_QUERY_USERNAME=stub BETTERSTACK_QUERY_PASSWORD=stub \
       bash "$SUT" --evidence-url "$URL" --cloud-init "$FIX/cloud-init-git-data.yml" 2>&1)"; rc=$?
if [[ "$rc" -ne 0 ]]; then pass "a missing --host-name refuses"; else
  fail "a missing --host-name refuses" "$rc" "$out"; fi

# An evidence URL that the GATE would refuse must be refused HERE, at write time. Writing a
# file the consumer rejects converts a rehearsal that succeeded into one that has to be re-run
# on real hardware -- the expensive way to learn about a typo.
out="$(BETTERSTACK_QUERY_SH="$STUB" BETTERSTACK_QUERY_HOST=stub \
       BETTERSTACK_QUERY_USERNAME=stub BETTERSTACK_QUERY_PASSWORD=stub \
       bash "$SUT" --host-name "$HOST" --evidence-url "https://example.com/nope" \
         --divergence "$DIVERGENCE" \
         --cloud-init "$FIX/cloud-init-git-data.yml" --out "$TMP/evidence-badurl.env" 2>&1)"; rc=$?
if [[ "$rc" -ne 0 ]]; then pass "a non-Actions evidence URL refuses at capture time"; else
  fail "a non-Actions evidence URL refuses at capture time" "$rc" "$out"; fi
if [[ ! -f "$TMP/evidence-badurl.env" ]]; then pass "a refused URL writes no evidence"; else
  fail "a refused URL writes no evidence" "$rc" "evidence written with a gate-refused URL"; fi

# The credential preflight is what turns "I queried and saw nothing" into "I never queried".
out="$(BETTERSTACK_QUERY_SH="$STUB" BETTERSTACK_QUERY_HOST='' \
       BETTERSTACK_QUERY_USERNAME='' BETTERSTACK_QUERY_PASSWORD='' \
       bash "$SUT" --host-name "$HOST" --evidence-url "$URL" --divergence "$DIVERGENCE" \
         --cloud-init "$FIX/cloud-init-git-data.yml" 2>&1)"; rc=$?
if [[ "$rc" -eq 2 ]]; then pass "absent Better Stack credentials => TRANSIENT, not a verdict"; else
  fail "absent Better Stack credentials => TRANSIENT, not a verdict" "$rc" "$out"; fi

# ── ARM 7: the declared divergence must be gate-acceptable ────────────────────────
#
# The capture script WRITES RUNG2_VAR_DIVERGENCE, and the gate refuses anything outside its
# identity-only allowlist. If the script can emit a set the gate rejects, the rehearsal
# produces evidence that cannot release -- so the two must agree, and this arm is what says so.
make_stub "$STUB" "$ANCHOR_LIVE" "$HOSTROWS"
OUT_DIV="$TMP/evidence-div.env"
run_sut --out "$OUT_DIV" >/dev/null 2>&1
_div="$(grep -E '^RUNG2_VAR_DIVERGENCE=' "$OUT_DIV" 2>/dev/null | sed 's/^[^=]*=//')"
if [[ "$_div" == "$DIVERGENCE" ]]; then
  pass "the evidence records the CALLER's declared divergence verbatim"
else
  fail "the evidence's divergence set is not the caller's" "n/a" "got '$_div' want '$DIVERGENCE'"
fi

# THE TAUTOLOGY IS GONE. The script used to write GIT_DATA_RUNG2_DIVERGENCE_ALLOWLIST back out,
# so the gate compared the allowlist against itself and R6 could only refuse a hand-edited file.
_allow_csv="${GIT_DATA_RUNG2_DIVERGENCE_ALLOWLIST// /,}"
if [[ "$_div" != "$_allow_csv" ]]; then
  pass "the evidence does NOT echo the gate's whole allowlist back (tautology closed)"
else
  fail "the evidence echoes the gate's entire allowlist — the R6 check is a tautology" "n/a" "$_div"
fi

# And omitting it is refused rather than defaulted, so a caller cannot get the old behavior back
# by saying less.
_out_nodiv="$(BETTERSTACK_QUERY_SH="$STUB" BETTERSTACK_QUERY_HOST=stub \
  BETTERSTACK_QUERY_USERNAME=stub BETTERSTACK_QUERY_PASSWORD=stub \
  bash "$SUT" --host-name "$HOST" --evidence-url "$URL" \
    --cloud-init "$FIX/cloud-init-git-data.yml" --out "$TMP/evidence-nodiv.env" 2>&1)"; _rc_nodiv=$?
if [[ "$_rc_nodiv" -ne 0 && ! -f "$TMP/evidence-nodiv.env" ]]; then
  pass "an omitted --divergence is refused and writes no evidence"
else
  fail "an omitted --divergence is refused" "$_rc_nodiv" "$_out_nodiv"
fi
_bad=""
for _t in ${_div//,/ }; do
  case " $GIT_DATA_RUNG2_DIVERGENCE_ALLOWLIST " in *" $_t "*) ;; *) _bad="${_bad} ${_t}" ;; esac
done
if [[ -z "$_bad" ]]; then
  pass "every declared divergence is on the gate's allowlist"
else
  fail "the capture script declares divergence the gate refuses:${_bad}" "n/a" "$_div"
fi

# ── Minimum-cardinality floor ─────────────────────────────────────────────────────
# Developer-incremented, and a FLOOR rather than an equality so a legitimately added arm does
# not redden the suite and train the next person to bump it unread. Counts passes+fails, so a
# genuine failure still reports as a failure rather than as an empty suite.
_ran=$((passes + fails))
if [[ "$_ran" -lt 28 ]]; then
  fails=$((fails + 1))
  printf '  FAIL ANTI-VACUITY: only %s assertions ran, floor is 28. Arms were deleted, skipped, or the suite exited early.\n' "$_ran"
else
  printf '  ok   anti-vacuity floor: %s assertions ran (floor 28)\n' "$_ran"
fi

printf '\n=== %d passed, %d failed ===\n\n' "$passes" "$fails"
[[ "$fails" -eq 0 ]]
