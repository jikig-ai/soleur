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
_real_q="${ROOT}/scripts/betterstack-query.sh"
_seen="$TMP/sql-seen"; mkdir -p "$_seen"
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
    timeout 20 env BETTERSTACK_QUERY_HOST=127.0.0.1 BETTERSTACK_QUERY_USERNAME=u \
      BETTERSTACK_QUERY_PASSWORD=p bash "$_real_q" "$(cat "$_q")" >/dev/null 2>&1
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
  timeout 20 env BETTERSTACK_QUERY_HOST=127.0.0.1 BETTERSTACK_QUERY_USERNAME=u \
    BETTERSTACK_QUERY_PASSWORD=p bash "$_real_q" "
  /* __ANCHOR__ leading-comment shape */
  SELECT 1" >/dev/null 2>&1
  if [[ $? -eq 64 ]]; then
    pass "the leading-comment shape IS rejected (64) — this arm can tell the two apart"
  else
    fail "the leading-comment shape was NOT rejected — this arm cannot fail and pins nothing" "n/a" ""
  fi
fi

# ── Minimum-cardinality floor ─────────────────────────────────────────────────────
# Developer-incremented, and a FLOOR rather than an equality so a legitimately added arm does
# not redden the suite and train the next person to bump it unread. Counts passes+fails, so a
# genuine failure still reports as a failure rather than as an empty suite.
#
# RAISED 30 -> 33 WITH THE ARMS THAT MADE IT NECESSARY (#7227 item 4). ARM 6b constrains
# --host-name to rehearsal hosts, and is three arms because the constraint has three
# separable ways to be wrong: the production name must be REFUSED (rc 64), the legitimate
# ${REHEARSAL_PREFIX}${GITHUB_RUN_ID} name must still be ACCEPTED (a too-tight regex would
# break the only real call site), and a rehearsal-prefixed name carrying a quote must STILL
# be refused (the SQL-interpolation property must survive the narrowing, not be traded for
# it). 30 + 3 = 33. Measured: 33 passed, 0 failed.

# ── ARMS S1-S4: THE SENTRY SECOND CHANNEL (#7116) ──────────────────────────────────────
#
# The parent shell runs OUTSIDE `doppler run`, so BETTERSTACK_LOGS_TOKEN is absent and the
# five parent-shell stages (gitdata_runcmd_early, sshd_config, volume_mount,
# gitdata_doppler_dl, gc_timer) reach SENTRY ONLY. Polling Better Stack alone, this script
# returned TRANSIENT for a host that had already reported a fatal — and each TRANSIENT costs
# one of only two sanctioned rehearsal dispatches.
#
# PLACEMENT IS THE POINT. The two paths where Sentry is the ONLY surviving channel — the
# transport failing, and the anchor returning zero rows — both exit BEFORE the host-rows
# query runs. An arm wired only to the boot_complete branch would be unreachable in exactly
# the case that justifies it, so S1 drives the DEAD-anchor path specifically.
SENTRY_HITS="$TMP/sentry-hits.sh"
cat > "$SENTRY_HITS" <<'EOS'
#!/usr/bin/env bash
printf '%s' '[{"id":"6123456789","title":"gitdata_runcmd_early fatal","culprit":"git-data-emit"}]'
EOS
chmod +x "$SENTRY_HITS"

SENTRY_EMPTY="$TMP/sentry-empty.sh"
printf '#!/usr/bin/env bash\nprintf %%s "[]"\n' > "$SENTRY_EMPTY"; chmod +x "$SENTRY_EMPTY"

SENTRY_BROKEN="$TMP/sentry-broken.sh"
printf '#!/usr/bin/env bash\necho "curl: (22) 401 Unauthorized" >&2\nexit 2\n' > "$SENTRY_BROKEN"; chmod +x "$SENTRY_BROKEN"

# S1: dead anchor (Better Stack blind) + Sentry HAS a fatal => FAIL, not TRANSIENT.
make_stub "$STUB" "$ANCHOR_DEAD" "$HOSTROWS_EMPTY"
OUT_S1="$TMP/evidence-s1.env"
out="$(SENTRY_ISSUES_SH="$SENTRY_HITS" run_sut --out "$OUT_S1")"; rc=$?
if [[ "$rc" -eq 1 ]]; then pass "dead Better Stack anchor + Sentry fatal => exit 1 (FAIL), not TRANSIENT"; else
  fail "dead Better Stack anchor + Sentry fatal => exit 1 (FAIL)" "$rc" "$out"; fi
if [[ ! -f "$OUT_S1" ]]; then pass "a Sentry-sourced FAIL writes NO evidence file"; else
  fail "a Sentry-sourced FAIL writes NO evidence file" "$rc" "an evidence file was written"; fi

# S2: Sentry queried cleanly with nothing found => the prior TRANSIENT verdict survives.
OUT_S2="$TMP/evidence-s2.env"
out="$(SENTRY_ISSUES_SH="$SENTRY_EMPTY" run_sut --out "$OUT_S2")"; rc=$?
if [[ "$rc" -eq 2 ]]; then pass "Sentry queried cleanly, no issues => TRANSIENT preserved"; else
  fail "Sentry queried cleanly, no issues => TRANSIENT preserved" "$rc" "$out"; fi
if [[ "$out" == *"queried cleanly"* ]]; then pass "a clean Sentry query says so explicitly"; else
  fail "a clean Sentry query says so explicitly" "$rc" "$out"; fi

# S3: THE FAIL-OPEN ARM. A broken Sentry query must read as "no verdict", never as "nothing
# found" — a broken instrument reporting a clean bill of health is worse than no instrument.
OUT_S3="$TMP/evidence-s3.env"
out="$(SENTRY_ISSUES_SH="$SENTRY_BROKEN" run_sut --out "$OUT_S3")"; rc=$?
if [[ "$rc" -eq 2 ]]; then pass "a FAILING Sentry query => TRANSIENT (never PASS, never a clean bill)"; else
  fail "a FAILING Sentry query => TRANSIENT" "$rc" "$out"; fi
if [[ "$out" == *"COULD NOT CONSULT"* ]]; then pass "a failed Sentry query is reported as not-consulted, not as empty"; else
  fail "a failed Sentry query is reported as not-consulted" "$rc" "$out"; fi

# S4: the boot_complete-missing path (live anchor, silent host) also consults Sentry.
make_stub "$STUB" "$ANCHOR_LIVE" "$HOSTROWS_EMPTY"
OUT_S4="$TMP/evidence-s4.env"
out="$(SENTRY_ISSUES_SH="$SENTRY_HITS" run_sut --out "$OUT_S4")"; rc=$?
if [[ "$rc" -eq 1 ]]; then pass "live anchor + silent host + Sentry fatal => exit 1 (FAIL)"; else
  fail "live anchor + silent host + Sentry fatal => exit 1 (FAIL)" "$rc" "$out"; fi
if [[ "$out" == *"6123456789"* ]]; then pass "the FAIL names the Sentry issue id it found"; else
  fail "the FAIL names the Sentry issue id it found" "$rc" "$out"; fi

_ran=$((passes + fails))
if [[ "$_ran" -lt 41 ]]; then
  fails=$((fails + 1))
  printf '  FAIL ANTI-VACUITY: only %s assertions ran, floor is 33. Arms were deleted, skipped, or the suite exited early.\n' "$_ran"
else
  printf '  ok   anti-vacuity floor: %s assertions ran (floor 41)\n' "$_ran"
fi

printf '\n=== %d passed, %d failed ===\n\n' "$passes" "$fails"
[[ "$fails" -eq 0 ]]
