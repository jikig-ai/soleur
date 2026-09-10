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
# THE VERDICT READS AN APPEND-ONLY LEDGER, NOT A COUNTER (#7481 review, V1/V2).
# Measured: swapping one token in fail() — `fails=$((fails+1))` -> `passes=$((passes+1))` —
# left this suite reporting all-green with real defects injected, and the assertion floor
# CANNOT see it because the floor sums both buckets. The runcmd suite already carried this
# hardening; it was never propagated here, which is the single-instance-not-the-class miss.
# The ledger length is asserted against the counter too: deleting just the append leaves an
# accurate FAIL line printed and rc=0 (measured on the sibling suite).
FAILURES=()
fail() {
  FAILURES+=("$1")
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
# $4 (fatal-rows) MODELS THE UNLIMITED FATAL QUERY, and defaults to the fatal rows PRESENT IN
# $3 rather than to $3 itself. That default is the faithful production model for every arm
# where the row window is not truncating: the fatal query is a SUPERSET of the windowed one,
# and when nothing fell out of the window the two agree on exactly the fatal rows. Passing $4
# explicitly is what lets an arm model a CHATTY boot — a fatal that the newest-50 window drops
# while the unlimited query still returns it (#7460 §5.0).
make_stub() {  # $1=stubpath  $2=anchor-rows-file  $3=host-rows-file  [$4=fatal-rows-file]
  local _fatal="${4:-}"
  if [[ -z "$_fatal" ]]; then
    _fatal="${3}.derived-fatal"
    grep '"level":"fatal"' "$3" > "$_fatal" 2>/dev/null || : > "$_fatal"
  fi
  cat > "$1" <<STUB
#!/usr/bin/env bash
sql="\$1"
if printf '%s' "\$sql" | grep -q '__ANCHOR__'; then
  cat "$2"
elif printf '%s' "\$sql" | grep -q '__FATALROWS__'; then
  # SEMANTIC DISPATCH, not marker dispatch. Keying only on the marker comment left EVERY clause
  # of FATAL_SQL unreachable by any fixture: the query could be reverted to be semantically
  # identical to HOST_SQL -- level filter dropped, ORDER BY DESC, LIMIT 50 -- and ARM 24 still
  # passed, i.e. the whole §5.0 fix was silently revertible. The marker was one I added myself,
  # so the arm was asserting the presence of my own comment. Measured, five separate ways.
  if printf '%s' "\$sql" | grep -q "level') = 'fatal'" \
     && printf '%s' "\$sql" | grep -q "host_name') = '" \
     && printf '%s' "\$sql" | grep -qE 'LIMIT (1000|[0-9]{4,})'; then
    cat "$_fatal"
  else
    echo "STUB: the FATAL query lost a load-bearing clause (level filter / host filter / LIMIT >= 1000)" >&2
    exit 4
  fi
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

# ── THE INGEST PROBE, STUBBED (#7772) ─────────────────────────────────────────────
# The foreign-host anchor is no longer the sole liveness instrument; when it returns nothing,
# the script asks scripts/betterstack-ingest-probe.sh whether the SOURCE is accepting. Every
# arm below pins that probe to a stub for two reasons: an unstubbed arm would make a real
# network call to a production ingest endpoint from a unit test, and its verdict would depend
# on whether credentials happened to be in the environment — the run would be green on this
# machine and a different colour in CI, for reasons unrelated to the code.
PROBE="$TMP/ingest-probe.sh"
make_probe() {  # $1 = exit code the stub reports (0 accepting | 4 refused | 2 unreachable)
  printf '#!/usr/bin/env bash\nexit %s\n' "$1" > "$PROBE"
  chmod +x "$PROBE"
}
make_probe 0
export BETTERSTACK_INGEST_PROBE="$PROBE"

ANCHOR_LIVE="$TMP/anchor-live.jsonl"
ANCHOR_DEAD="$TMP/anchor-dead.jsonl"
# THE REAL ROW SHAPE. ANCHOR_SQL selects `JSONExtractString(raw,'host_name') AS host`, so
# FORMAT JSONEachRow emits `host`, never `host_name`. The fixture modelled a shape the query
# cannot produce, which only stopped mattering because the liveness check was a bare
# `grep -q 'host'` that `host_name` happened to satisfy — a fixture and a predicate agreeing
# with each other while both disagreed with production.
printf '{"dt":"2026-07-29 11:59:00","host":"soleur-web-1"}\n' > "$ANCHOR_LIVE"
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

# ── ARM 4b: THE SINGLE-TENANT DEADLOCK (#7772) ────────────────────────────────────
#
# THIS IS THE ARM THE SOURCE SPLIT MADE NECESSARY, and it fails against the pre-#7772 script.
#
# The foreign-host anchor asks "is the source answering?" by requiring a row from a host OTHER
# than this one. That worked only because source 2457081 was SHARED and its other tenants were
# chatty. git-data now ships to its OWN source 2734275, whose only possible writers are the prod
# host (never born) and rehearsal hosts -- which the `!=` clause excludes BY DESIGN, and whose
# HOST_NAME embeds a per-run id so no two rehearsals share one.
#
# So on a single-tenant source the predicate is UNSATISFIABLE, and a PERFECT rehearsal lands on
# TRANSIENT: no evidence file, no verdict, RUNG2_BOOT_REHEARSAL=PASS structurally unreachable,
# and every retry costs another real Hetzner host and another environment approval. The failure
# is indistinguishable from a dark boot -- the one distinction this whole script exists to make.
#
# The fix keeps the foreign-host read as SUFFICIENT and adds the ingest probe as the necessary
# condition. These four arms pin every branch of that, in both directions.
make_stub "$STUB" "$ANCHOR_DEAD" "$HOSTROWS"          # zero foreign rows, a PERFECT boot
make_probe 0                                          # ...and the source is demonstrably live
OUT_ST="$TMP/evidence-singletenant.env"
out="$(run_sut --out "$OUT_ST")"; rc=$?
if [[ "$rc" -eq 0 ]]; then pass "zero foreign rows + a LIVE ingest probe => a VERDICT, not TRANSIENT"; else
  fail "zero foreign rows + a LIVE ingest probe => a VERDICT, not TRANSIENT" "$rc" "$out"; fi
if [[ -f "$OUT_ST" ]]; then pass "the single-tenant PASS writes its evidence file"; else
  fail "the single-tenant PASS writes its evidence file" "$rc" "a perfect rehearsal produced no evidence — this is the deadlock"; fi

# REFUSED is a statement about the INSTRUMENT, so it must stay TRANSIENT. Without this arm the
# fix above would be a fail-open: "no foreign rows" would simply stop meaning anything.
make_probe 4
out="$(run_sut --out "$TMP/evidence-refused.env")"; rc=$?
if [[ "$rc" -eq 2 ]]; then pass "zero foreign rows + a REFUSING source => TRANSIENT"; else
  fail "zero foreign rows + a REFUSING source => TRANSIENT" "$rc" "$out"; fi
if [[ "$out" == *"REFUSING"* ]]; then pass "the refused TRANSIENT names the refusal, not the host"; else
  fail "the refused TRANSIENT names the refusal, not the host" "$rc" "$out"; fi

make_probe 2
out="$(run_sut --out "$TMP/evidence-unreachprobe.env")"; rc=$?
if [[ "$rc" -eq 2 ]]; then pass "zero foreign rows + an UNREACHABLE source => TRANSIENT"; else
  fail "zero foreign rows + an UNREACHABLE source => TRANSIENT" "$rc" "$out"; fi

# AND THE INSTRUMENT ITSELF MUST FAIL CLOSED. An absent probe is "cannot tell", never "fine".
#
# THE ASSIGNMENT GOES INSIDE THE SUBSHELL (#7855, found at ship). `VAR=x out="$(...)"` is an
# ASSIGNMENT LIST, not a command with an environment prefix — bash assigns both names in THIS
# shell, and since BETTERSTACK_INGEST_PROBE is exported above, the export persisted. Every later
# arm that reached the probe leg therefore ran against a probe that does not exist, and the
# `make_probe 0` on the next line rewrote a file nothing read any more. Measured: that made
# GUARD1/H3b vacuous — it passed on "the ingest probe is unreadable", not on the property it
# names, and the identical input against a READABLE acknowledging probe exits 0 and writes
# RUNG2_BOOT_REHEARSAL=PASS.
out="$(BETTERSTACK_INGEST_PROBE="$TMP/no-such-probe.sh" run_sut --out "$TMP/evidence-noprobe.env")"; rc=$?
if [[ "$rc" -eq 2 ]]; then pass "zero foreign rows + an UNREADABLE probe => TRANSIENT, not a verdict"; else
  fail "zero foreign rows + an UNREADABLE probe => TRANSIENT, not a verdict" "$rc" "$out"; fi
make_probe 0

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

# ── ARM 6b (#7227 item 4): --host-name IS CONSTRAINED TO REHEARSAL HOSTS ──────────
#
# The charset check above is necessary (the name reaches the WHERE clause of every Better
# Stack query) but says nothing about WHICH host. `soleur-git-data` — the production store
# holding every connected user's source code — satisfies `^[A-Za-z0-9._-]+$` perfectly, and
# the rehearsal workflow projects this script's `detail` output into a PUBLIC Actions log on
# a PUBLIC repo. A reader aimed at production is a one-flag path from boot telemetry about
# real user data to a world-readable artifact.
#
# NO OVERRIDE FLAG. Reading production boot telemetry is a different tool with a different
# output contract, not a flag on this one — an `--allow-production` escape reopens the hole
# for exactly the caller most likely to be in a hurry.
#
# The 180-byte emit-time bound is NOT a substitute: it bounds VOLUME, not CONTENT, and it is
# applied on the host at emit time. This script is a reader and inherits whatever shipped.
_hn_probe() {  # $1 = host name under test; echoes "rc=<n> <first line of stderr>"
  local _o _r
  _o="$(BETTERSTACK_QUERY_SH="$STUB" BETTERSTACK_QUERY_HOST=stub \
        BETTERSTACK_QUERY_USERNAME=stub BETTERSTACK_QUERY_PASSWORD=stub \
        bash "$SUT" --host-name "$1" --evidence-url "$URL" --divergence "$DIVERGENCE" \
          --cloud-init "$FIX/cloud-init-git-data.yml" --out "$TMP/evidence-hn.env" 2>&1)"; _r=$?
  printf 'rc=%s %s' "$_r" "$(printf '%s' "$_o" | grep -m1 'refusing: --host-name' || true)"
}

_hn="$(_hn_probe 'soleur-git-data')"
if [[ "$_hn" == rc=64*refusing:\ --host-name* ]]; then
  pass "the PRODUCTION host name soleur-git-data is refused (rc 64)"
else
  fail "the PRODUCTION host name soleur-git-data is refused (rc 64)" "$_hn" \
    "This script projects detail rows into a public Actions log; aimed at production it exports real boot telemetry."
fi

# The constraint must be strictly NARROWER, not merely different: the legitimate call site
# passes ${REHEARSAL_PREFIX}${GITHUB_RUN_ID}, which must still be accepted.
_hn="$(_hn_probe 'soleur-git-data-rehearsal-17250000001')"
if [[ "$_hn" != *'refusing: --host-name'* ]]; then
  pass "a rehearsal host name is still accepted by the --host-name gate"
else
  fail "a rehearsal host name is still accepted by the --host-name gate" "$_hn" \
    "The constraint is too tight — it would refuse the only production call site (\${REHEARSAL_PREFIX}\${GITHUB_RUN_ID})."
fi

# AND THE CHARSET PROPERTY MUST SURVIVE. A prefix check written as a bare `case`/`==` glob
# would accept `soleur-git-data-rehearsal-1" OR 1=1 --`, trading the SQL-interpolation
# property for the scope one. Both, or neither.
_hn="$(_hn_probe 'soleur-git-data-rehearsal-1"quote')"
if [[ "$_hn" == rc=64*refusing:\ --host-name* ]]; then
  pass "a rehearsal-prefixed name carrying a quote is STILL refused (charset property kept)"
else
  fail "a rehearsal-prefixed name carrying a quote is STILL refused (charset property kept)" "$_hn" \
    "The name is interpolated into the Better Stack SQL WHERE clause; a quote changes which rows the verdict is read from."
fi

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
# `:-` GUARD. Under `set -u` an unset allowlist aborted the whole suite here, so a run that
# had ALREADY produced a real FAIL above died before printing its verdict line -- the failure
# was reported as "no output" rather than as the finding it was. Surfaced while mutation-testing
# the FATAL query: four genuine reddenings all looked like crashes.
_allow_csv="${GIT_DATA_RUNG2_DIVERGENCE_ALLOWLIST:-}"; _allow_csv="${_allow_csv// /,}"
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

# ── Mode 1 admissibility, against the REAL transport ──────────────────────────────
#
# THE ONE ARM THAT DOES NOT STUB betterstack-query.sh, and the reason it exists: every other
# arm does, and the stub dispatches on `__ANCHOR__`/`__HOSTROWS__` — tokens that live INSIDE
# the SQL comment. So the stub was satisfied by exactly the construct that made the real
# transport reject, and 28 green assertions certified a route that could not execute.
#
# The queries are RECORDED from a live run rather than re-parsed out of the SUT's source: a
# re-parsed copy is a second pin on the same value, and a second pin goes stale silently and
# fails GREEN — the defect class this arm exists to close.
#
# (#7898 §6) THE HOST IS NOW VENDOR-SHAPED AND `curl` IS SHIMMED ON PATH, and the two changes
# are one change. betterstack-query.sh refuses any BETTERSTACK_QUERY_HOST outside
# `*.betterstackdata.com` before it examines the SQL, so this arm's previous
# `BETTERSTACK_QUERY_HOST=127.0.0.1` would now exit 2 at the host check — ABOVE the flag
# parsing and archive derivation that produce the 64 this arm discriminates on. `_rejected`
# would stay empty and the loop would pass VACUOUSLY while claiming every query is admitted;
# only the verify-the-verifier row below would go red. So the host has to become one the pin
# admits, and the moment it does, the loopback-refuses-fast property that kept this arm offline
# is gone: a vendor-shaped host with real `curl` would perform a genuine outbound TLS handshake
# at Better Stack's production endpoint carrying fabricated Basic-auth credentials.
#
# The shim closes that. Precedent: scripts/compound-promote.test.sh › make_mock_curl(), which
# writes the request to a capture file. curl is betterstack-query.sh's sole egress site, so
# shimming it means no packet leaves AND the capture file is the evidence that the admitted
# queries actually reached the boundary — which is what makes "admitted" an observation rather
# than an inference. That third assertion is the Guard 2 row pinning that the destination
# refusal must not swallow the exit-64 discrimination.
_real_q="${ROOT}/scripts/betterstack-query.sh"
_seen="$TMP/sql-seen"; mkdir -p "$_seen"
_shim_dir="$TMP/curl-shim"; mkdir -p "$_shim_dir"
_curl_calls="$TMP/curl-invocations.log"
: > "$_curl_calls"
cat > "$_shim_dir/curl" <<SHIM
#!/usr/bin/env bash
# Records the destination of every invocation and emits nothing. Exit 0: this arm asks whether
# the query is ADMITTED, not what the warehouse would answer.
for _a in "\$@"; do
  case "\$_a" in http://*|https://*) printf '%s\n' "\$_a" >> "$_curl_calls" ;; esac
done
exit 0
SHIM
chmod +x "$_shim_dir/curl"
# Synthetic; satisfies the allowlist, is never resolved, and is never dialled (the shim is
# first on PATH). NOT a seam in the script under test — the script has no host-override seam.
_ADM_HOST="stub.betterstackdata.com"
_adm_rows="$TMP/rows-adm.jsonl"
row boot_complete info luks_mounted=yes repo_root=yes hooks_path=yes provision=yes > "$_adm_rows"
cat > "$TMP/bs-record.sh" <<RECSTUB
#!/usr/bin/env bash
printf '%s' "\$1" > "${_seen}/\$(date +%s%N)-\$\$.sql"
if printf '%s' "\$1" | grep -q '__ANCHOR__'; then cat "$ANCHOR_LIVE"; else cat "$_adm_rows"; fi
RECSTUB
chmod +x "$TMP/bs-record.sh"
BETTERSTACK_QUERY_SH="$TMP/bs-record.sh" BETTERSTACK_QUERY_HOST=stub \
  BETTERSTACK_QUERY_USERNAME=stub BETTERSTACK_QUERY_PASSWORD=stub \
  bash "$SUT" --host-name "$HOST" --evidence-url "$URL" --divergence "$DIVERGENCE" \
    --cloud-init "$FIX/cloud-init-git-data.yml" --out "$TMP/evidence-adm.env" >/dev/null 2>&1

_nq="$(find "$_seen" -name '*.sql' 2>/dev/null | wc -l)"
if [[ ! -r "$_real_q" ]]; then
  fail "the real betterstack-query.sh is unreadable at ${_real_q}" "n/a" "admissibility arm could not run"
elif [[ "$_nq" -lt 2 ]]; then
  # Positive-work floor: zero recorded queries would make the check below vacuously clean.
  fail "recorded only ${_nq} queries from the SUT (expected >=2) — this arm asserted on nothing" "n/a" ""
else
  _rejected=""
  for _q in "$_seen"/*.sql; do
    # `timeout` because an ADMITTED query proceeds to curl; rejection is decided before any
    # connection, so 64 still arrives instantly. rc 124 means admitted-then-timed-out, not 64.
    timeout 20 env PATH="${_shim_dir}:$PATH" BETTERSTACK_QUERY_HOST="$_ADM_HOST" \
      BETTERSTACK_QUERY_USERNAME=u BETTERSTACK_QUERY_PASSWORD=p \
      bash "$_real_q" "$(cat "$_q")" >/dev/null 2>&1
    [[ $? -eq 64 ]] && _rejected="${_rejected} $(head -c 50 "$_q" | tr '\n' ' ')"
  done
  if [[ -z "$_rejected" ]]; then
    pass "all ${_nq} queries the SUT builds are admitted as Mode 1 SQL by the real transport"
  else
    fail "a query the SUT builds is REJECTED by betterstack-query.sh (exit 64) — the route cannot run" \
      "64" "$_rejected"
  fi
  # Verify-the-verifier: the same check MUST reject the leading-comment shape, or the arm above
  # would pass against any implementation and pin nothing.
  timeout 20 env PATH="${_shim_dir}:$PATH" BETTERSTACK_QUERY_HOST="$_ADM_HOST" \
    BETTERSTACK_QUERY_USERNAME=u BETTERSTACK_QUERY_PASSWORD=p bash "$_real_q" "
  /* __ANCHOR__ leading-comment shape */
  SELECT 1" >/dev/null 2>&1
  if [[ $? -eq 64 ]]; then
    pass "the leading-comment shape IS rejected (64) — this arm can tell the two apart"
  else
    fail "the leading-comment shape was NOT rejected — this arm cannot fail and pins nothing" "n/a" ""
  fi
  # (#7898 §6) THE DESTINATION REFUSAL MUST NOT SWALLOW THE EXIT-64 DISCRIMINATION. The host
  # check sits ABOVE flag parsing, so a host the allowlist rejects makes every query exit 2 and
  # the "all N admitted" row above pass on nothing. An admitted query proceeds to curl; a
  # refused one never does. So a non-zero shim invocation count is the proof that the queries
  # were admitted rather than pre-empted — assert it, or a future tightening of the pin
  # re-breaks exactly this coupling silently.
  _hits="$(wc -l < "$_curl_calls" | tr -d ' ')"
  if [[ "$_hits" -ge "$_nq" ]]; then
    pass "the admitted queries reached the egress boundary (${_hits} curl invocations) — the host pin did not pre-empt the Mode-1 check"
  else
    fail "only ${_hits} of ${_nq} queries reached curl: the destination refusal pre-empts the exit-64 check, so the admissibility row above passed vacuously" \
      ">=${_nq}" "$_hits"
  fi
fi

# ── ARM 12: the derivation-fault path, EXECUTED ───────────────────────────────────
#
# AN EXECUTING ARM, NOT A GREP OVER THE SOURCE. A grep is satisfied whether or not the branch
# is REACHABLE, and this branch sits after the whole Better Stack verdict — so "the label was
# corrected" and "the label is reached" are two independent claims and only running it proves
# both. It also binds the message to the lib's abort text: the capture script promises the
# diagnostic below names the offending file, and that promise is only true if the lib's abort
# actually flows through.
#
# The stub is re-armed with the PASS rows deliberately: the run has to get all the way PAST
# boot_complete to reach the derivation, which is exactly why this fault is expensive in
# production — it is discovered after the host has already booted.
FIX_BROKEN="$TMP/fix-broken"
cp -r "$FIX" "$FIX_BROKEN" || { echo "HARNESS ABORT: could not copy the fixture tree" >&2; exit 2; }
rm -f "$FIX_BROKEN/git-data-gc.timer" \
  || { echo "HARNESS ABORT: could not remove the A12 payload" >&2; exit 2; }
HOSTROWS_DERIV="$TMP/rows-deriv.jsonl"
row boot_complete info luks_mounted=yes repo_root=yes hooks_path=yes provision=yes > "$HOSTROWS_DERIV"
make_stub "$STUB" "$ANCHOR_LIVE" "$HOSTROWS_DERIV"
out="$(BETTERSTACK_QUERY_SH="$STUB" BETTERSTACK_QUERY_HOST=stub \
       BETTERSTACK_QUERY_USERNAME=stub BETTERSTACK_QUERY_PASSWORD=stub \
       bash "$SUT" --host-name "$HOST" --evidence-url "$URL" --divergence "$DIVERGENCE" \
         --cloud-init "$FIX_BROKEN/cloud-init-git-data.yml" \
         --out "$TMP/evidence-deriv.env" 2>&1)"; rc=$?
if [[ "$rc" -eq 2 \
      && "$out" == *"DERIVATION FAULT (deterministic, NOT transient)"* \
      && "$out" == *"references payload '../../git-data-gc.timer'"* ]]; then
  pass "an unresolvable payload => exit 2, labelled deterministic and naming the payload"
else
  fail "an unresolvable payload => exit 2, labelled deterministic and naming the payload" "$rc" "$out"
fi

# ── Minimum-cardinality floor ─────────────────────────────────────────────────────
# Developer-incremented, and a FLOOR rather than an equality so a legitimately added arm does
# not redden the suite and train the next person to bump it unread. Counts passes+fails, so a
# genuine failure still reports as a failure rather than as an empty suite.
#
# RAISED 34 -> 48 (#7481), ITEMISED — ARMS 13-23, the second channel:
#     2  13, 13b  placement as a CLASS, plus the floor that keeps it non-vacuous
#     1  14       the redaction tuple names all ten credentials (merge blocker)
#     2  15, 15b  no header-dumping curl flags; no token-in-URL and no env dump
#     1  16       zero eyeball instructions, with a file-count floor
#     2  17       a Sentry fatal upgrades TRANSIENT to FAIL, and writes no evidence
#     1  18       ... and prints stage, rc AND the cause
#     1  19       an EMPTY cause is reported as empty (#7204's DETAIL=[] class)
#     1  20       silent-both stays TRANSIENT
#     1  21       401/403 reported as DETERMINISTIC
#     1  22       the call shape carries --host-events and a window (defect 5)
#     1  23       an absent token is a named skip, not a clean bill
#   ----
#    14   (re-derived from a measured run against the as-written file: 34 + 14 = 48)
#
# RAISED 48 -> 54 (#7481 review), ITEMISED — the branch review found untested:
#     2  ARM 24  a Sentry fatal on an otherwise-PASSing read => FAIL, and no evidence written
#     1  ARM 25  a PASS records RUNG2_SENTRY_CROSSCHECK durably
#     2  ARM 26  --since reaches the reader as --start/--end, and says so
#     1  ARM 27  a malformed --since is refused, not widened
#     1  ARM 23b the uploaded artifact is the REDACTED file, not the raw capture log
#   ----
#     7
#
# RAISED 33 -> 34 (#7485): ARM 12, the executing derivation-fault arm.
#
# RAISED 30 -> 33 WITH THE ARMS THAT MADE IT NECESSARY (#7227 item 4). ARM 6b constrains
# --host-name to rehearsal hosts, and is three arms because the constraint has three
# separable ways to be wrong: the production name must be REFUSED (rc 64), the legitimate
# ${REHEARSAL_PREFIX}${GITHUB_RUN_ID} name must still be ACCEPTED (a too-tight regex would
# break the only real call site), and a rehearsal-prefixed name carrying a quote must STILL
# be refused (the SQL-interpolation property must survive the narrowing, not be traded for
# it). 30 + 3 = 33. Measured: 33 passed, 0 failed.
# ── ARMS 13–23 — the SECOND CHANNEL (#7481) ────────────────────────────────────────
#
# The route's originating incident is a verdict with no cause. These arms cover BOTH halves:
# who consults Sentry (13, 17–21) and WHAT the consult prints (18, 19) — because fixing only
# the first reproduces the incident with a better exit code.

WF="${ROOT}/.github/workflows/git-data-rung2-rehearsal.yml"
RUNBOOK="${ROOT}/knowledge-base/engineering/operations/runbooks/git-data-rung2-rehearsal.md"
READER="${ROOT}/scripts/sentry-issue.sh"

# ARM 13 — PLACEMENT, asserted as a CLASS. The previous design enumerated the no-verdict call
# sites and got the list wrong twice, so the guard here is not "these six sites call
# transient()" but "no bare `exit 2` survives outside transient() and the derivation-fault
# site". A seventh no-verdict path added next year is covered without editing this arm.
# The derivation fault is excluded BY NAME because it is genuinely deterministic — it is not a
# channel failure and consulting Sentry about it would be nonsense.
_bare_exit2_lines() {
  awk '
    /^transient\(\) \{/      { in_t = 1 }
    in_t && /^\}/            { in_t = 0; next }
    /DERIVATION FAULT/       { df = NR }
    # WIDENED (#7481 review, V10). `^[[:space:]]*exit 2[[:space:]]*$` was blind to the class
    # it claims to cover: a seventh no-verdict path written `exit 2  # nothing known`, or
    # `exit 2;`, or `exit "$rc"`, all evaded it while ARM 13b still counted 6.
    /^[[:space:]]*exit[[:space:]]+["$]?2\b/ {
      if (!in_t && !(df && NR - df < 6)) print NR ": " $0
    }
  ' "$SUT"
}
_n_bare=$(_bare_exit2_lines | grep -c . || true)
if [[ "$_n_bare" -eq 0 ]]; then
  pass "no bare 'exit 2' outside transient() and the derivation-fault site"
else
  fail "no bare 'exit 2' outside transient() and the derivation-fault site" "$_n_bare" "$(_bare_exit2_lines | head -3)"
fi

# ARM 13b — THE FLOOR THAT KEEPS ARM 13 NON-VACUOUS. Arm 13 passes trivially against a file
# that routes nothing through transient() — deleting every call site satisfies "no bare exit 2"
# perfectly. Six is the measured no-verdict site count.
# COMMENT LINES STRIPPED FIRST. The `|| ` alternative matches anywhere on a line, so a
# future comment documenting the idiom (`# every no-verdict path is \`… || transient "…"\``)
# inflates the count and satisfies this floor without a call site existing — the same
# self-match class R1-PIN and ARM 16 already carry treatments for.
_n_transient=$(sed 's/^[[:space:]]*#.*$//' "$SUT" | grep -cE '(^|\|\| )[[:space:]]*transient ' || true)
if [[ "$_n_transient" -ge 6 ]]; then
  pass "transient() is reached from >= 6 no-verdict sites (found ${_n_transient})"
else
  fail "transient() is reached from >= 6 no-verdict sites" "$_n_transient" "a no-verdict path was un-routed or the anchor drifted"
fi

# ARM 14 — THE REDACTION TUPLE (merge blocker). The workflow writes BOTH R2 credentials into
# $GITHUB_ENV, so they are in the capture step's environment, and that step tee's stdout AND
# stderr verbatim into a 7-day artifact on a PUBLIC repo. `::add-mask::` does not help: it
# scrubs the log STREAM and tee writes bytes to disk first. Asserted per NAME so a partial
# widening cannot pass.
# SCOPED TO THE TUPLE, NOT THE FILE. `grep -qF '"NAME"' "$WF"` asserted only that a
# credential name appears double-quoted SOMEWHERE in a 500-line YAML — a comment, an echo,
# or a Python string elsewhere satisfies it, and the 20-line rationale block this PR added
# sits directly above the list discussing those exact names. The failure direction is a
# GREEN arm over a partially-deleted tuple, on the assertion carrying the merge-blocking
# property. Extract the `for var in (...)` block first (cq-assert-anchor-not-bare-token).
_tuple_block="$(sed -n '/^ *for var in (/,/):$/p' "$WF")"
_tuple_missing=""
_tuple_n=0
for _n in BETTERSTACK_QUERY_HOST BETTERSTACK_QUERY_USERNAME BETTERSTACK_QUERY_PASSWORD \
          SENTRY_ISSUE_RO_TOKEN SENTRY_ISSUE_RW_TOKEN AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY \
          DOPPLER_TOKEN HCLOUD_TOKEN BETTERSTACK_LOGS_TOKEN GIT_DATA_LUKS_KEY; do
  if printf '%s\n' "$_tuple_block" | grep -qF "\"${_n}\""; then
    _tuple_n=$((_tuple_n + 1))
  else
    _tuple_missing="${_tuple_missing} ${_n}"
  fi
done
# A FLOOR, because a name-by-name check is one-directional: it cannot see the block being
# emptied and rebuilt with fewer members, and every sibling guard in this PR carries one.
if [[ "$_tuple_n" -lt 11 ]]; then
  _tuple_missing="${_tuple_missing} (only ${_tuple_n} of 11 names found in the extracted tuple block — did the block anchor drift?)"
fi
if [[ -z "$_tuple_missing" ]]; then
  pass "the capture-log redaction tuple names all eleven credentials, inside the tuple block itself"
else
  fail "the capture-log redaction tuple names all eleven credentials, inside the tuple block itself" "" "missing:${_tuple_missing}"
fi

# ARM 15 — NO HEADER-DUMPING CURL FLAGS. curl's ordinary stderr echoes scheme and host only and
# is kept for diagnosis, but -v and --trace* dump the Authorization header VERBATIM — and this
# route pipes stderr into the public artifact. Scoped to the reader, which is the only file
# that builds an authenticated request.
if grep -nE 'curl[^|]*(-v[[:space:]]|--verbose|--trace)' "$READER" >/dev/null 2>&1; then
  fail "the Sentry curl carries no -v/--trace* (they dump Authorization verbatim)" "" "$(grep -nE 'curl[^|]*(-v[[:space:]]|--verbose|--trace)' "$READER" | head -2)"
else
  pass "the Sentry curl carries no -v/--trace* (they dump Authorization verbatim)"
fi

# ARM 15b — NO TOKEN IN A URL, and no whole-environment dump. A token in a query string lands
# in the artifact, in curl's stderr, and in any proxy log between here and Sentry.
_leaky=$(grep -nE 'https://[^"]*(TOKEN|token)=' "$READER" "$SUT" 2>/dev/null | grep -c . || true)
_dumpy=$(grep -nE '^[[:space:]]*(set[[:space:]]+-[a-z]*x([[:space:]]|$)|printenv|env[[:space:]]*\|)' "$READER" "$SUT" 2>/dev/null | grep -c . || true)
if [[ "$_leaky" -eq 0 && "$_dumpy" -eq 0 ]]; then
  pass "no token interpolated into a URL, and no set -x / printenv / env| in either script"
else
  fail "no token interpolated into a URL, and no set -x / printenv / env| in either script" "" "url=${_leaky} dump=${_dumpy}"
fi

# ARM 16 — THE EYEBALL CLASS, greped rather than enumerated. Three earlier passes at this
# hand-listed the sites and found two, then three, then seven; the tell that enumeration was
# the wrong method. hr-no-dashboard-eyeball-pull-data-yourself is the rule being enforced.
# CASE-INSENSITIVE AND BACKTICK-TOLERANT, because the first version of this arm was not and
# reported a FALSE CLEAN. It read `check the DOPPLER_TOKEN secret` literally; the runbook's
# copy is "Check the \`DOPPLER_TOKEN\` secret" — capitalised, with the identifier in backticks
# — so the arm passed while a real eyeball instruction survived in one of the three files it
# was written to sweep. Anchor on the CLAIM (an imperative to go and inspect a named channel),
# not on one file's spelling of it; cq-assert-anchor-not-bare-token, one level up.
# THE BOUND IS 8, AND BOTH DIRECTIONS ARE MEASURED. At 4 this arm reported a CLEAN sweep
# while `git-data-rung2-rehearsal.yml` still carried "check the \`DOPPLER_TOKEN\` secret" — the
# gap there is `the \`` = 6 characters, because the YAML-escaped backtick is two bytes. That
# was the THIRD false clean from this arm (case-sensitivity, then backticks, then width), so
# the bound is now measured rather than guessed.
#
# It is NOT widened further, and that is also measured: at 12 it starts matching
# "download the capture-log artifact and check whether the Better Stack anchor answered" —
# an instruction to read THIS RUN'S OWN OUTPUT, which is the sanctioned behaviour
# hr-no-dashboard-eyeball-pull-data-yourself prescribes, not the behaviour it forbids. A
# guard that reddens on the remedy is worse than one that misses a site.
_EYEBALL_RE='[Cc]onfirm against .{0,4}(Sentry|Better Stack)|[Cc]heck .{0,8}(Sentry|Better Stack|DOPPLER_TOKEN)'
_eyeball_hits=0
_eyeball_files=0
for _f in "$WF" "$RUNBOOK" "$SUT"; do
  if [[ -r "$_f" ]]; then
    _eyeball_files=$((_eyeball_files + 1))
    # SELF-EXCLUDING, for the same reason R1-PIN is: an arm that forbids a phrase must
    # quote that phrase to explain itself, and the SUT is one of the files it sweeps.
    _eyeball_hits=$(( _eyeball_hits + $(grep -E "$_EYEBALL_RE" "$_f" | grep -vc '_EYEBALL_RE\|used to hand the reader\|used to end by telling' || true) ))
  fi
done
# THE FILE-COUNT FLOOR IS THE ANTI-VACUITY HALF: a renamed or moved file would make the hit
# count 0 for the best possible reason and the worst possible one, indistinguishably.
if [[ "$_eyeball_files" -eq 3 && "$_eyeball_hits" -eq 0 ]]; then
  pass "zero eyeball instructions across the workflow, the runbook and the capture script"
else
  fail "zero eyeball instructions across the workflow, the runbook and the capture script" "" \
       "files_read=${_eyeball_files}/3 hits=${_eyeball_hits}"
fi

# ── the consult, driven end to end through the real transient() ─────────────────────
#
# A STUB, because these verdicts are not reachable against the live API from a suite that must
# run offline. It records its argv so the CALL SHAPE is assertable too: a stub that answered
# identically regardless of arguments could not detect the caller dropping the window, which is
# defect 5. Fixtures model the measured production schema (cq-test-fixtures-synthesized-only);
# no live token appears in any of them.
SENTRY_STUB="$TMP/sentry-stub.sh"
SENTRY_ARGV="$TMP/sentry-argv.txt"
cat > "$SENTRY_STUB" <<'STUBEOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$SENTRY_ARGV_FILE"
[[ -n "${STUB_RC:-}" && "${STUB_RC}" != "0" ]] && { echo "stubbed refusal"; exit "$STUB_RC"; }
printf '%s\n' "${STUB_BODY:-{\"data\":[]\}}"
exit 0
STUBEOF
chmod +x "$SENTRY_STUB"

run_sut_sentry() {  # $1 = STUB_RC, $2 = STUB_BODY, rest appended to the SUT
  local rc="$1" body="$2"; shift 2
  # SOLEUR_TEST_MODE IS REQUIRED, and that it is required is the point: the SUT honours
  # SOLEUR_SENTRY_READER only under this marker, because the script runs under
  # `doppler run -c prd_terraform` where a bare env override would be an arbitrary-command
  # sink one config entry away (CWE-427). These arms are what prove the gate is load-bearing:
  # drop SOLEUR_TEST_MODE and all four Sentry arms redden, measured.
  SOLEUR_TEST_MODE=1 \
  SOLEUR_SENTRY_READER="$SENTRY_STUB" SENTRY_ARGV_FILE="$SENTRY_ARGV" \
  SENTRY_ISSUE_RO_TOKEN='stub-token-not-a-real-credential' \
  STUB_RC="$rc" STUB_BODY="$body" \
    run_sut "$@"
}

# The measured production shape: stage, rc and detail per EVENT.
_FATAL_WITH_CAUSE='{"data":[{"timestamp":"2026-07-31T17:11:22+00:00","level":"fatal","host_name":"H","stage":"luks_open","rc":"32","detail":"mount: /mnt/git-data-luks: mount(2) system call failed: No such process."}]}'
_FATAL_NO_CAUSE='{"data":[{"timestamp":"2026-07-31T17:11:22+00:00","level":"fatal","host_name":"H","stage":"luks_open","rc":"32","detail":""}]}'
_NO_FATAL='{"data":[]}'

# ARM 17 — A SENTRY FATAL UPGRADES A BETTER-STACK-SILENT TRANSIENT TO A NAMED FAIL. This is
# #7481's whole thesis: the 2026-07-31 rehearsal died at luks_open, which is BEFORE
# `doppler run`, so Better Stack never saw it and the route reported TRANSIENT — sending the
# operator to re-dispatch a paid host over a knowable failure.
: > "$SENTRY_ARGV"
make_stub "$STUB" "$ANCHOR_LIVE" "$HOSTROWS_EMPTY"
out="$(run_sut_sentry 0 "$_FATAL_WITH_CAUSE" --out "$TMP/ev-17.env")"; rc=$?
if [[ "$rc" -eq 1 ]]; then pass "a Sentry fatal turns a Better-Stack-silent TRANSIENT into FAIL (rc 1)"; else
  fail "a Sentry fatal turns a Better-Stack-silent TRANSIENT into FAIL (rc 1)" "$rc" "$out"; fi
if [[ ! -f "$TMP/ev-17.env" ]]; then pass "a Sentry-derived FAIL writes NO evidence file"; else
  fail "a Sentry-derived FAIL writes NO evidence file" "$rc" "evidence was written on a FAIL"; fi

# ARM 18 — AND IT PRINTS THE CAUSE, not only the verdict. THE ORIGINATING INCIDENT IS EXACTLY
# THIS: the 2026-07-31 artifact carried `stage:luks_open level:fatal` and no detail, and the
# real cause had to be re-queried by hand afterwards. A verdict without a cause is the defect.
if [[ "$out" == *"luks_open"* && "$out" == *"32"* && "$out" == *"mount(2) system call failed"* ]]; then
  pass "the Sentry-derived FAIL prints stage, rc AND the cause text"
else
  fail "the Sentry-derived FAIL prints stage, rc AND the cause text" "$rc" "$out"
fi

# ARM 19 — AN EMPTY CAUSE IS REPORTED AS EMPTY. #7204's DETAIL=[] regression class: a verdict
# that silently omits its cause is worse than one that says it has none, because the reader
# cannot tell "no cause was sent" from "the reader dropped it".
: > "$SENTRY_ARGV"
make_stub "$STUB" "$ANCHOR_LIVE" "$HOSTROWS_EMPTY"
out="$(run_sut_sentry 0 "$_FATAL_NO_CAUSE" --out "$TMP/ev-19.env")"; rc=$?
if [[ "$rc" -eq 1 && "$out" == *"EMPTY"* ]]; then
  pass "a Sentry fatal with no detail reports the cause as EMPTY rather than blank"
else
  fail "a Sentry fatal with no detail reports the cause as EMPTY rather than blank" "$rc" "$out"
fi

# ARM 20 — SILENT-BOTH IS TRANSIENT, NEVER PASS. Better Stack silent AND Sentry clean must
# still decline: nothing is known. This holds by construction today (PASS requires
# boot_complete) but nothing asserted it, and "by construction" is what stops being true.
: > "$SENTRY_ARGV"
make_stub "$STUB" "$ANCHOR_LIVE" "$HOSTROWS_EMPTY"
out="$(run_sut_sentry 0 "$_NO_FATAL" --out "$TMP/ev-20.env")"; rc=$?
if [[ "$rc" -eq 2 && ! -f "$TMP/ev-20.env" ]]; then
  pass "both channels silent => TRANSIENT (rc 2) and no evidence file"
else
  fail "both channels silent => TRANSIENT (rc 2) and no evidence file" "$rc" "$out"
fi

# ARM 21 — A TERMINAL REFUSAL SAYS SO. 401/403 are repo/credential-side and identical on every
# attempt; the workflow retries rc=2 twenty times over ~16 minutes against a paid cpx22, so a
# message that does not say "do not retry" costs a host to learn nothing.
: > "$SENTRY_ARGV"
make_stub "$STUB" "$ANCHOR_LIVE" "$HOSTROWS_EMPTY"
out="$(run_sut_sentry 78 "" --out "$TMP/ev-21.env")"; rc=$?
if [[ "$rc" -eq 2 && "$out" == *"DETERMINISTIC"* ]]; then
  pass "a 403 from Sentry is reported as DETERMINISTIC and does not become a host verdict"
else
  fail "a 403 from Sentry is reported as DETERMINISTIC and does not become a host verdict" "$rc" "$out"
fi

# ARM 23b — THE UPLOADED FILE IS THE REDACTED ONE. The whole redaction tuple protects
# `/tmp/rung2/capture.redacted.log`; nothing asserted that is what `upload-artifact` takes.
# Repointing it at `capture.log` publishes every value the redactor would have scrubbed into
# a 7-day artifact on a PUBLIC repo, with the tuple arm still green. Measured: zero hits for
# "redacted" anywhere in this suite before this arm.
if grep -qF 'path: /tmp/rung2/capture.redacted.log' "$WF" \
   && ! grep -qE '^\s*path:\s*/tmp/rung2/capture\.log\s*$' "$WF"; then
  pass "the capture-log artifact uploads the REDACTED file, never the raw one"
else
  fail "the capture-log artifact uploads the REDACTED file, never the raw one" "" \
       "$(grep -nE '^\s*path:\s*/tmp/rung2/' "$WF" | head -3)"
fi

# ARM 24 — THE PASS PATH CROSS-CHECK. THE BLOCKER, and the branch that had no coverage at
# all: every other Sentry arm sets up HOSTROWS_EMPTY, i.e. the Better-Stack-SILENT path, so
# fourteen arms covered the route that already had a verdict and ZERO covered the one that
# writes the artifact releasing the git-data birth hold. A host that died early, was retried
# by cloud-init, and later reached boot_complete produces exactly this shape.
: > "$SENTRY_ARGV"
make_stub "$STUB" "$ANCHOR_LIVE" "$HOSTROWS"          # a full, all-positive boot_complete
out="$(run_sut_sentry 0 "$_FATAL_WITH_CAUSE" --out "$TMP/ev-24.env")"; rc=$?
if [[ "$rc" -eq 1 ]]; then
  pass "a Sentry fatal on an otherwise-PASSing Better Stack read => FAIL (rc 1)"
else
  fail "a Sentry fatal on an otherwise-PASSing Better Stack read => FAIL (rc 1)" "$rc" "$out"
fi
if [[ ! -f "$TMP/ev-24.env" ]]; then
  pass "that FAIL writes NO evidence — the birth hold is not released"
else
  fail "that FAIL writes NO evidence — the birth hold is not released" "$rc" "evidence was written over a Sentry fatal"
fi

# ARM 25 — a PASS records the cross-check verdict DURABLY. Without this the evidence file is
# byte-identical whether the cross-check ran CLEAN or was skipped, and the capture log that
# would have said so is not even uploaded on a PASS.
: > "$SENTRY_ARGV"
make_stub "$STUB" "$ANCHOR_LIVE" "$HOSTROWS"
out="$(run_sut_sentry 0 "$_NO_FATAL" --out "$TMP/ev-25.env")"; rc=$?
if [[ "$rc" -eq 0 ]] && grep -q '^RUNG2_SENTRY_CROSSCHECK=' "$TMP/ev-25.env" 2>/dev/null; then
  pass "a PASS records RUNG2_SENTRY_CROSSCHECK in the evidence file"
else
  fail "a PASS records RUNG2_SENTRY_CROSSCHECK in the evidence file" "$rc" "$(cat "$TMP/ev-25.env" 2>/dev/null | head -3)"
fi

# ARM 26 — THE RUN-PINNED WINDOW REACHES THE READER. Defect 5's fix had no coverage at all:
# `--since` appeared nowhere in this suite, so the --start/--end branch never executed and
# ARM 22's disjunction was satisfied by --stats-period in every single arm — it proved the
# DEGRADED path while its comment described the pinned one.
: > "$SENTRY_ARGV"
make_stub "$STUB" "$ANCHOR_LIVE" "$HOSTROWS_EMPTY"
out="$(run_sut_sentry 0 "$_NO_FATAL" --since 2026-09-02T10:00:00 --out "$TMP/ev-26.env")"; rc=$?
if grep -qE -- '--start 2026-09-02T10:00:00' "$SENTRY_ARGV" && grep -qE -- '--end [0-9]{4}-' "$SENTRY_ARGV"; then
  pass "--since produces a run-pinned --start/--end pair at the reader"
else
  fail "--since produces a run-pinned --start/--end pair at the reader" "$rc" "$(cat "$SENTRY_ARGV" 2>/dev/null | head -2)"
fi
if [[ "$out" == *"pinned to this run"* ]]; then
  pass "--since says so in the log, so a pinned read is distinguishable from a widened one"
else
  fail "--since says so in the log, so a pinned read is distinguishable from a widened one" "$rc" "$out"
fi

# ARM 27 — a malformed --since is REFUSED, not silently widened. The value is interpolated
# into the Sentry window, and which rows the query returns is the verdict.
out="$(run_sut_sentry 0 "$_NO_FATAL" --since 'yesterday' --out "$TMP/ev-27.env" 2>&1)"; rc=$?
if [[ "$rc" -eq 64 && ! -f "$TMP/ev-27.env" ]]; then
  pass "a malformed --since is refused (rc 64), never widened to the fallback window"
else
  fail "a malformed --since is refused (rc 64), never widened to the fallback window" "$rc" "$out"
fi

# ARM 22 — THE CALL SHAPE. A stub that answers regardless of argv cannot detect the caller
# dropping the window, and an unwindowed read is defect 5: host_name embeds the run id, which
# is STABLE across GitHub re-run attempts, so attempt 2 of a fixed host would read attempt 1's
# fatal. Assert the window reached the reader, and that the host was passed.
# The disjunct stays (this arm runs on a fallback-window case), but ARM 26 is what pins
# the RUN-PINNED shape — this one only proves a window of SOME kind reached the reader.
# THE HOST IS PINNED, NOT JUST THE FLAG. `grep -- '--host-events '` matched the flag name,
# so repointing the consult at `soleur-git-data` — the PRODUCTION store holding every
# connected user's source code — left this arm green. ARM 6b spends three assertions
# refusing that host on the Better Stack channel because the SUT projects `detail` into a
# public log; the second channel projects it the same way and had no such guard.
if grep -qF -- "--host-events ${HOST}" "$SENTRY_ARGV" && grep -qE -- '(--stats-period |--start )' "$SENTRY_ARGV"; then
  pass "the consult passes --host-events AND a window to the reader"
else
  fail "the consult passes --host-events AND a window to the reader" "" "$(cat "$SENTRY_ARGV" 2>/dev/null | head -2)"
fi

# ARM 23 — AN ABSENT TOKEN IS A NAMED SKIP, NOT A CLEAN BILL. Without this the consult would
# silently contribute nothing and the route would report plain TRANSIENT, which reads as "we
# looked and Sentry was quiet" — the strongest form of the silence-is-health defect.
: > "$SENTRY_ARGV"
make_stub "$STUB" "$ANCHOR_LIVE" "$HOSTROWS_EMPTY"
out="$(SOLEUR_TEST_MODE=1 SOLEUR_SENTRY_READER="$SENTRY_STUB" SENTRY_ARGV_FILE="$SENTRY_ARGV" \
        SENTRY_ISSUE_RO_TOKEN='' run_sut --out "$TMP/ev-23.env")"; rc=$?
if [[ "$rc" -eq 2 && "$out" == *"SENTRY_ISSUE_RO_TOKEN is unset"* ]]; then
  pass "an absent SENTRY_ISSUE_RO_TOKEN is reported as a named skip, not read as silence"
else
  fail "an absent SENTRY_ISSUE_RO_TOKEN is reported as a named skip, not read as silence" "$rc" "$out"
fi

# ARM 28 (#7460 §5.0) — A CHATTY BOOT MUST NOT BURY ITS OWN FATAL.
# (Numbered 28, not 24: ARM 24 was already taken by PR A's PASS-path cross-check and 25-27
# exist too. Two arms sharing a label makes "which arm bought the floor raise" unanswerable
# by grep, which is how the floor bookkeeping is audited.)
#
# HOST_SQL ends `ORDER BY dt DESC LIMIT 50`. That bound was safe only while the channel split
# held: ADR-149 recorded that "on a successful boot the only Better Stack row a git-data host
# produces is boot_complete itself". Phase 5 bakes the ingest token, so every post-write_files
# stage now emits — and the emitter fires far more often than once per stage (sshd warn, mount,
# gc-timer, the LUKS trap, per-stage on_err).
#
# So an EARLY fatal followed by enough later rows falls OUT of the newest-50 window. The fatal
# arm then finds nothing, control reaches the boot_complete check, and the script writes
# RUNG2_BOOT_REHEARSAL=PASS over an unread fatal — the exact artifact ## User-Brand Impact
# names as the failure this route exists to prevent.
#
# THE FIXTURE ENCODES THE TRUNCATION, because that is what production does: the host fixture is
# what the WINDOWED query returns (fatal already dropped), and the fatal fixture is what the
# UNLIMITED query returns. An arm that put the fatal in both files would pass against the
# defect and prove nothing.
HOSTROWS_CHATTY="$TMP/rows-chatty.jsonl"
: > "$HOSTROWS_CHATTY"
for _i in $(seq 1 50); do
  row mount info "detail=routine emit ${_i}" >> "$HOSTROWS_CHATTY"
done
row boot_complete info luks_mounted=yes repo_root=yes hooks_path=yes provision=yes >> "$HOSTROWS_CHATTY"
FATALROWS_CHATTY="$TMP/rows-chatty-fatal.jsonl"
row luks_open fatal "rc=32" "detail=mount(2) ESRCH" > "$FATALROWS_CHATTY"

make_stub "$STUB" "$ANCHOR_LIVE" "$HOSTROWS_CHATTY" "$FATALROWS_CHATTY"
OUT_CHATTY="$TMP/evidence-chatty.env"
out="$(run_sut --out "$OUT_CHATTY")"; rc=$?
if [[ "$rc" -eq 1 && "$out" == *"FATAL"* && ! -f "$OUT_CHATTY" ]]; then
  pass "ARM 24: a fatal outside the newest-50 window still FAILs, and writes no evidence file"
else
  fail "ARM 24: a fatal outside the newest-50 window still FAILs, and writes no evidence file" "$rc" "$out"
fi

# ── GUARD 1 (#7855): the capture never names a cause it did not measure ───────────
#
# Run 33888071954 printed, twenty times:
#   "TRANSIENT: the Better Stack query transport exited 22 (unreachable or unauthorised)."
# Neither cause was measured. The transport was reachable and the credential was valid — the
# read failed because the SOURCE'S TABLE DOES NOT EXIST, which Better Stack creates lazily on
# the first stored row. Measured live on 2026-09-04, and re-measured while writing these arms:
#
#   remote(t520508_soleur_git_data_prd_logs)            -> rc 22, Code: 701 CLUSTER_DOESNT_EXIST
#   s3Cluster(primary, t520508_soleur_git_data_prd_s3)  -> rc 22, Code: 669 NAMED_COLLECTION_DOESNT_EXIST
#   remote(t520508_soleur_inngest_vector_prd_3_logs)    -> rc 0,  {"n":0}
#
# The hot and archive arms fail with DIFFERENT codes, so a classifier keyed on either string is
# half a classifier. The CONTROL READ is the discriminator; the codes ride along as the reason.
#
# The three states below are the whole property. Only the middle one is about the rehearsal
# host, and before this change all three printed the same sentence.
export G1_MODE_FILE="$TMP/g1-mode"
cat > "$TMP/g1-stub.sh" <<'G1STUB'
#!/usr/bin/env bash
mode="$(cat "$G1_MODE_FILE" 2>/dev/null || echo dark)"
# Mode 2 (flag form) is the control read bs_absence_classify performs. It is answered on
# BEHALF OF WHATEVER $BS_TABLE NAMES — which is what makes mutation 4 detectable: the capture
# exports BS_TABLE=<git-data> process-wide, so a classify call that does not override it reads
# the ABSENT target and can only ever answer TRANSPORT_FAIL.
if [[ "${1:-}" == --* ]]; then
  if [[ "${BS_TABLE:-}" != t520508_soleur_inngest_vector_prd_3_logs ]]; then
    echo "curl: (22) The requested URL returned error: 500" >&2
    exit 22
  fi
  case "$mode" in
    dark) exit 0 ;;
    live) printf '{"dt":"2026-09-04 12:00:00","raw":"{}"}\n'; exit 0 ;;
    fail) echo "connection refused" >&2; exit 7 ;;
  esac
fi
# Mode 1: the git-data target read, transcribed from the live 2026-09-04 response.
echo "curl: (22) The requested URL returned error: 500" >&2
echo '{"exception":"Code: 701. DB::Exception: Requested cluster '"'"'t520508_soleur_git_data_prd_logs'"'"' not found. (CLUSTER_DOESNT_EXIST)"}'
exit 22
G1STUB
chmod +x "$TMP/g1-stub.sh"
_g1_mode() { printf '%s' "$1" > "$G1_MODE_FILE"; cp "$TMP/g1-stub.sh" "$STUB"; }

# ARM 25 — the state run 33888071954 was actually in. The target read fails; the control read
# answers and the warehouse holds nothing from ANY producer. That is #7811, not a git-data fact.
_g1_mode dark
out="$(run_sut --out "$TMP/evidence-g1-dark.env")"; rc=$?
if [[ "$rc" -eq 2 && "$out" == *"DARK FOR EVERY PRODUCER"* ]]; then
  pass "GUARD1/1: target read fails + control dark => names the warehouse, not the host"
else
  fail "GUARD1/1: target read fails + control dark => names the warehouse, not the host" "$rc" "$out"
fi
if [[ "$out" != *"unreachable or unauthorised"* ]]; then
  pass "GUARD1/1: the two unmeasured causes are gone from the dark arm"
else
  fail "GUARD1/1: the two unmeasured causes are gone from the dark arm" "$rc" "$out"
fi
# The vendor code is carried as the REASON. It must be present (a reader has to know what
# failed) and it must not be the decision — ARM 26 proves the decision actually moved.
if [[ "$out" == *"CLUSTER_DOESNT_EXIST"* ]]; then
  pass "GUARD1/1: the ClickHouse code rides along as the reason"
else
  fail "GUARD1/1: the ClickHouse code rides along as the reason" "$rc" "$out"
fi

# ARM 26 — the only state that is about this source. The warehouse is demonstrably storing rows
# from other producers, and this source's table still does not exist: nothing has ever been
# stored to it, or it is misaddressed. It does NOT license blaming the producer (H1).
#
# THIS ARM IS ALSO THE MUTATION-4 DETECTOR. Delete the BS_TABLE override on the classify call
# and the control read is pointed at the absent target, so it can only answer TRANSPORT_FAIL —
# this arm goes red while the rest of the suite stays green.
_g1_mode live
out="$(run_sut --out "$TMP/evidence-g1-live.env")"; rc=$?
if [[ "$rc" -eq 2 && "$out" == *"NEVER STORED A ROW"* ]]; then
  pass "GUARD1/2: target read fails + control LIVE => names this source, not the warehouse"
else
  fail "GUARD1/2: target read fails + control LIVE => names this source, not the warehouse" "$rc" "$out"
fi
if [[ "$out" != *"DARK FOR EVERY PRODUCER"* && "$out" != *"unreachable or unauthorised"* ]]; then
  pass "GUARD1/2: does not borrow the dark-warehouse sentence or the unmeasured causes"
else
  fail "GUARD1/2: does not borrow the dark-warehouse sentence or the unmeasured causes" "$rc" "$out"
fi
# A misaddressed source produces this identical pair, so the arm must not assert the host failed.
if [[ "$out" != *"the rehearsal host failed"* && "$out" != *"producer is at fault"* ]]; then
  pass "GUARD1/2: declines to blame the producer — a misaddressed source looks identical"
else
  fail "GUARD1/2: declines to blame the producer — a misaddressed source looks identical" "$rc" "$out"
fi

# ARM 27 — both reads failed. Nothing was learned about anything.
_g1_mode fail
out="$(run_sut --out "$TMP/evidence-g1-fail.env")"; rc=$?
if [[ "$rc" -eq 2 && "$out" == *"CONTROL READ ALSO FAILED"* ]]; then
  pass "GUARD1/3: both reads fail => names the instrument"
else
  fail "GUARD1/3: both reads fail => names the instrument" "$rc" "$out"
fi
if [[ "$out" != *"DARK FOR EVERY PRODUCER"* && "$out" != *"NEVER STORED A ROW"* ]]; then
  pass "GUARD1/3: an unusable instrument is not read as either substantive state"
else
  fail "GUARD1/3: an unusable instrument is not read as either substantive state" "$rc" "$out"
fi

# ── GUARD 1 harness rows ─────────────────────────────────────────────────────────
#
# H3: a must-PASS NON-CANONICAL input. Without it the matrix cannot detect a guard that rejects
# everything — every arm above is a failure fixture, so a stub refusing all input would satisfy
# them all. The PASS path (anchor answering with foreign-host rows) is that input, and it must
# still hold with the new arm in place.
make_stub "$STUB" "$ANCHOR_LIVE" "$HOSTROWS"
out="$(run_sut --out "$TMP/evidence-g1-h3.env")"; rc=$?
if [[ "$rc" -eq 0 ]]; then
  pass "GUARD1/H3: the normal path is untouched by the new arm (must-PASS non-canonical)"
else
  fail "GUARD1/H3: the normal path is untouched by the new arm (must-PASS non-canonical)" "$rc" "$out"
fi

# H3b (Guard 2 row 4, asserted from the CONSUMER's side): ANCHOR_SQL's foreign-host predicate is
# `host_name != '' AND host_name != '<this host>'`, so ANY row carrying a host_name is
# foreign-host liveness for this capture. That is why the round-trip marker carries no host_name
# key at all — and a row without one must not satisfy this anchor.
#
# ASSERTED ON THE ANCHOR'S OWN LINE, NOT ON rc (#7855, corrected at ship). rc cannot observe this
# property: when the anchor yields no foreign-host liveness the capture consults the ingest probe
# and, on an ACKNOWLEDGED source with a clean boot_complete, still exits 0 by design. The arm
# previously read `rc -ne 0` and passed only because ARM 4b had leaked BETTERSTACK_INGEST_PROBE
# to a nonexistent path, so the run died on an unreadable instrument — a green arm measuring the
# harness. With that leak fixed, the identical input exits 0, and the property is visible exactly
# where the capture reports it.
ANCHOR_MARKER="$TMP/anchor-marker.jsonl"
printf '{"dt":"2026-09-04 12:00:00","host":""}\n' > "$ANCHOR_MARKER"
make_stub "$STUB" "$ANCHOR_MARKER" "$HOSTROWS"
out="$(run_sut --out "$TMP/evidence-g1-marker.env")"; rc=$?
if grep -q 'anchor: no foreign-host rows' <<<"$out"; then
  pass "GUARD1/H3b: a row with no host_name does not read as foreign-host liveness"
else
  fail "GUARD1/H3b: a row with no host_name does not read as foreign-host liveness" "$rc" "$out"
fi

# ── GUARD1/H4: rc 0 IS NOT AN ANSWER (#7855, found at ship) ──────────────────────
#
# `betterstack-query.sh` runs curl with `--fail-with-body`, which returns 0 for an HTTP 200 whose
# body is a ClickHouse MID-STREAM EXCEPTION. Every read in the capture was gated on that rc
# alone. Reproduced before the fix, on the FATAL read: the body carries no `"level":"fatal"`, so
# the FAIL arm did not fire, and the script wrote RUNG2_BOOT_REHEARSAL=PASS — a host cleared for
# birth on a fatal check that never ran, while the evidence file's own header claims "CLEAN = a
# fatal read returned zero rows".
#
# One arm per read, because they are three independent call sites and a fix applied to one says
# nothing about the other two. MUTATION for each: delete that read's `_require_answer` call.
CH_EXC='Code: 241. DB::Exception: Memory limit (for query) exceeded: would use 9.31 GiB. (MEMORY_LIMIT_EXCEEDED)'
make_exc_stub() {  # $1=which marker answers with an HTTP-200-carrying-an-error
  cat > "$STUB" <<EXCSTUB
#!/usr/bin/env bash
sql="\$1"
if printf '%s' "\$sql" | grep -q '$1'; then
  echo "$CH_EXC"
  exit 0
elif printf '%s' "\$sql" | grep -q '__ANCHOR__'; then
  cat "$ANCHOR_LIVE"
elif printf '%s' "\$sql" | grep -q '__FATALROWS__'; then
  : > /dev/null
elif printf '%s' "\$sql" | grep -q '__HOSTROWS__'; then
  cat "$HOSTROWS"
else
  echo "STUB: unrecognised query shape" >&2; exit 3
fi
EXCSTUB
  chmod +x "$STUB"
}

for _which in __ANCHOR__ __HOSTROWS__ __FATALROWS__; do
  make_exc_stub "$_which"
  _exc_out="$TMP/evidence-exc-${_which//_/}.env"
  rm -f "$_exc_out"
  out="$(run_sut --out "$_exc_out")"; rc=$?
  if [[ "$rc" -eq 2 && ! -f "$_exc_out" ]]; then
    pass "GUARD1/H4 ${_which}: an HTTP 200 carrying a ClickHouse error is TRANSIENT, not a result set"
  else
    fail "GUARD1/H4 ${_which}: an HTTP 200 carrying a ClickHouse error is TRANSIENT, not a result set" \
         "rc=$rc evidence_written=$([[ -f "$_exc_out" ]] && echo yes || echo no)" "$out"
  fi
done

# And the FATAL read specifically must never be read as a clean bill — the arm that reproduced
# as a PASS. Asserted on the operator-facing text, not only on rc.
make_exc_stub __FATALROWS__
out="$(run_sut --out "$TMP/evidence-exc-fatal2.env")"; rc=$?
if grep -q 'not a result set' <<<"$out" && ! grep -q 'RUNG2_BOOT_REHEARSAL=PASS' <<<"$out"; then
  pass "GUARD1/H4b: the unbounded fatal query answering with an error names it, and does not PASS"
else
  fail "GUARD1/H4b: the unbounded fatal query answering with an error names it, and does not PASS" "$rc" "$out"
fi

make_stub "$STUB" "$ANCHOR_LIVE" "$HOSTROWS"

# ── GUARD 1 arm enumerator ───────────────────────────────────────────────────────
#
# The property is about EVERY arm that turns a failed read into operator-facing text, not only
# the one this issue fixed. The chokepoint is transient(), so the population is its call sites.
#
# ANCHORED ON THE CALL SHAPE, not on `transient(`: that pattern matches only the DEFINITION, so
# an enumerator keyed on it would report one arm forever and could never see a new one. The plan
# named `transient(` as shorthand for the chokepoint; the assembly it describes is the call sites.
# ANCHORED ON THE CALL SHAPE for the ARM COUNT, but the PHRASE scan runs over the whole file's
# non-comment lines. Measured: the previous form grepped only lines matching `^\s*transient `,
# i.e. the FIRST line of each call — and all three arms this issue adds are multi-line
# continuations, so a cause-naming phrase on a continuation line scored ZERO. The guard was
# narrower than the property it names, which is the defect class this whole PR is about.
#
# COMMENTS ARE STRIPPED FIRST. The capture documents the retired phrase in prose explaining why
# it was wrong, so a raw whole-file grep matches that comment and fails a correct file — the
# collision that always arises when a task requires both "assert X absent" and "document X".
_g1_arms=$(grep -cE '^[[:space:]]*transient ' "$SUT")
_g1_bad=$(grep -vE '^[[:space:]]*#' "$SUT" | grep -cE 'unreachable or unauthorised' || true)
if [[ "$_g1_bad" -eq 0 ]]; then
  pass "GUARD1/enum: no executable line names a cause the run did not measure (${_g1_arms} transient arms)"
else
  fail "GUARD1/enum: ${_g1_bad} executable line(s) name an unmeasured cause"
fi
# ANTI-VACUITY FLOOR FOR THE ENUMERATOR ITSELF (mutation 6). Change either pattern to a token
# present nowhere and the scan reports "0 arms" and passes. The floor fires on its own emptiness.
# It reports with printf + exit, NEVER through fail() — a floor routed through the helper it
# backstops cannot witness that helper being disarmed (ADR-193, AP-023).
if [[ "$_g1_arms" -lt 6 ]]; then
  printf '  FAIL GUARD1/enum floor: only %s transient() arms enumerated (floor 6) — the pattern matched nothing.\n' "$_g1_arms" >&2
  exit 1
fi

# INSTRUMENT SELF-TEST, before any verdict is read. Drives BOTH helpers once and requires each
# counter AND the ledger to move. A floor that sums passes+fails cannot witness a fail() that
# routes its count into passes, and a ledger check cannot witness a fail() whose append was
# removed -- this catches both, and it reports directly rather than through the helpers it tests.
_canary_p=$passes _canary_f=$fails _canary_l=${#FAILURES[@]}
pass "instrument self-test: pass() moves its counter"
fail "instrument self-test: fail() moves its counter (EXPECTED, retracted)"
if [[ "$passes" -ne $((_canary_p + 1)) || "$fails" -ne $((_canary_f + 1)) || "${#FAILURES[@]}" -ne $((_canary_l + 1)) ]]; then
  printf '  FAIL INSTRUMENT: pass/fail/ledger did not all move (p=%s->%s f=%s->%s ledger=%s->%s). This suite cannot certify anything.\n' \
    "$_canary_p" "$passes" "$_canary_f" "$fails" "$_canary_l" "${#FAILURES[@]}" >&2
  exit 1
fi
fails=$((fails - 1)); unset 'FAILURES[${#FAILURES[@]}-1]'
printf '  ok   instrument self-test: pass(), fail() and the ledger all moved (control retracted)\n'

_ran=$((passes + fails))
# FLOOR = main's 62 + the 11 assertions #7855 adds (GUARD1 arms 25-27, two harness rows, the
# enumerator). Stated as a derivation rather than a bare literal because a sibling PR raising
# the base silently invalidates a copied number — re-read `git show origin/main:<this file>`
# at ship rather than trusting this comment's arithmetic.
#
# The message's own figure is interpolated from the same variable the test uses. It previously
# read "floor is 56" against a `-lt 62` test — a floor whose report contradicted its own
# predicate, which is the shape that makes a drifting number invisible.
_FLOOR=75  # 73 + the instrument self-test + the #7898 §6 egress-reachability row
if [[ "$_ran" -lt "$_FLOOR" ]]; then
  # REPORTS DIRECTLY, never through fail(): a floor that increments the counter a disarmed fail()
  # owns cannot witness that fail() being disarmed (ADR-193, AP-023).
  printf '  FAIL ANTI-VACUITY: only %s assertions ran, floor is %s. Arms were deleted, skipped, or the suite exited early.\n' "$_ran" "$_FLOOR" >&2
  exit 1
else
  printf '  ok   anti-vacuity floor: %s assertions ran (floor %s)\n' "$_ran" "$_FLOOR"
fi

# LEDGER RECONCILIATION. A stalled append or a stalled counter each break this; neither is
# visible to the pass/fail totals or to the floor.
if [[ "${#FAILURES[@]}" -ne "$fails" ]]; then
  printf '  FAIL LEDGER: %s failures counted but %s recorded — fail() was tampered with.\n' \
    "$fails" "${#FAILURES[@]}"
  exit 1
fi
printf '\n=== %d passed, %d failed ===\n\n' "$passes" "$fails"
# THE VERDICT IS AN `exit`, NOT A TRAILING TEST EXPRESSION. A bare `[[ "$fails" -eq 0 ]]` as the
# final statement makes the exit status a property of which line happens to be LAST: measured,
# appending any single command after it (a printf, a stray echo) permanently greens the suite
# while it goes on printing accurate failure text, and run_suite() classifies on the exit code
# alone. Deleting the line has the same effect. An explicit exit cannot be defeated by an append.
exit $(( ${#FAILURES[@]} > 0 ))
