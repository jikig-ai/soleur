#!/usr/bin/env bash
# Harness for inngest-luks-property-8296.sh (#8296 PR-2, Guard 3) and the rollback-NEXT placement
# check for scripts/cutover-inngest.sh (AC-32).
#
# WHAT THE PROBE IS. A NOTIFY-ONLY daily check enrolled on tracker #8285: the ledger's claim for
# hcloud_volume.inngest_redis_luks must agree with the device the Inngest store is measured on.
# The sweeper CLOSES a tracker on status 0 and treats 1 as its reopen trigger, so the one property
# that matters more than any verdict is that NO path through the probe ends in 0 or 1. This suite
# pins that three ways: a static allowlist over every `exit` token, a literal trailing `exit 3`,
# and behavioural runs of mutants that fall off the end, reference an unset variable, and turn an
# `exit 2` into `exit 0` -- each must come back 3 via the EXIT trap.
#
# EVERY CASE PINS A BRANCH MARKER as well as the status. Several arms share 3 and three share 5; a
# status-only suite collapses them, and a probe that routes a rollback into `under_claim` would
# still read green.
#
# THE STUB IS A FAKE-TREE FILE DROP (the registry-luks-live-8386.test.sh idiom). The probe is
# copied to $root/scripts/followthroughs/ and resolves its repo from its own location, so the
# fixture ledger at $root/scripts/encryption-posture-ledger.json and the stub at
# $root/scripts/betterstack-query.sh are what it reads. The stub asserts its argv by VALUE and
# answers 64 otherwise. It deliberately IGNORES --grep and returns every fixture row (harness row
# H1): a stub that applied the filter would hide a probe that does not.
#
# THE REAL LEDGER IS NEVER READ. Every case builds its own fixture ledger. The real one is flipped
# in the same PR, and a suite that graded it would change verdict with the flip.
#
# THE CLOCK IS PINNED. Every case sets SOLEUR_FT_NOW; fixture times sit 2h50m vs 3h10m from the
# staleness edge and a day either side of expires_on, so nothing here depends on the real date.
#
# CODE MUTATIONS ARE COMMITTED, NOT HAND-RUN (mutation rows 5, 7, 8, 9, 10 and H1's filter
# removal). Each is applied to a scratch copy under mktemp -d -- never to a tracked file -- is
# asserted to have LANDED inside the target line range, and is then expected to red. A known-
# positive and a known-negative run prove the red-detector first.
#
# Values are synthesized (cq-test-fixtures-synthesized-only): every volume alias, boot id,
# instance id and credential-shaped string below is fabricated.

set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
PROBE_NAME="inngest-luks-property-8296.sh"
PROBE_SRC="$HERE/$PROBE_NAME"
CUTOVER_SRC="$REPO/scripts/cutover-inngest.sh"

fails=0
passes=0
cases=0
pass() { printf '  PASS: %s\n' "$1"; passes=$((passes + 1)); }
fail() { printf '  FAIL: %s\n' "$1" >&2; fails=$((fails + 1)); }

[[ -f "$PROBE_SRC" ]] || { echo "FATAL: probe not found at $PROBE_SRC" >&2; exit 1; }
[[ -f "$CUTOVER_SRC" ]] || { echo "FATAL: cutover script not found at $CUTOVER_SRC" >&2; exit 1; }

# Canonical guard, copied byte-for-byte from plugins/soleur/test/test-helpers.sh: every scratch
# write below is rooted at $WORK, and this refuses an empty, relative or root-resolving one.
assert_fixture_dir() {
  case "${1-}" in
    "") printf 'FATAL: fixture dir is EMPTY; git -C "" would operate on %s\n' "$PWD" >&2; exit 2 ;;
    */../*|*/..) printf 'FATAL: fixture dir %s contains ..; refusing\n' "$1" >&2; exit 2 ;;
    /proc/*|/sys/*|/dev/*) printf 'FATAL: fixture dir %s is a synthetic-fs path; refusing\n' "$1" >&2; exit 2 ;;
    /|//|/.) printf 'FATAL: fixture dir resolves to the filesystem root; refusing\n' >&2; exit 2 ;;
    /*) : ;;
    *)  printf 'FATAL: fixture dir %s is RELATIVE; refusing\n' "$1" >&2; exit 2 ;;
  esac
}
WORK="$(mktemp -d "${TMPDIR}/inngest-luks-property-8296.XXXXXXXX")" || { echo "FATAL: mktemp failed" >&2; exit 1; }
assert_fixture_dir "$WORK"
trap 'rm -rf -- "$WORK"' EXIT
mkdir -p "$WORK/fx" "$WORK/mut"

# ── fabricated identities and the pinned clock ────────────────────────────────────────────────
BOOT="3c9e1f07-5a2b-4d68-9e41-7b0c2d5a8f13"
VOL="scsi-0HC_Volume_100000077"
FAKE_CRED="dp.ct.NOT_A_REAL_TOKEN_8296_synthetic"
NOW="2026-10-01T12:00:00Z"
DT_OLDEST="2026-10-01 05:00:00.000000"
DT_OLDER="2026-10-01 07:00:00.000000"
DT_STALE="2026-10-01 08:50:00.000000"   # 3h10m before NOW: past the 3h edge
DT_FRESH="2026-10-01 09:10:00.000000"   # 2h50m before NOW: inside it
DT_NEWEST="2026-10-01 11:30:00.000000"
EXP_FUTURE="2026-10-02"                 # NOW is a day BEFORE expiry
EXP_PAST="2026-09-30"                   # NOW is a day AFTER expiry
LUKS_SRC="/dev/mapper/inngest-redis"
PLAIN_SRC="/dev/sdb"
LEAD="backstop is the LIVE store — do NOT destroy hcloud_volume.inngest_redis"

# ── fixture builders ──────────────────────────────────────────────────────────────────────────
msg() { # <host_role> <data_mount_src> <data_mount_devid> [tail]
  printf 'SOLEUR_INNGEST_SERVER_PROBE http_code=200 server_active=active vector_active=active redis_active=active uptime_s=900 boot_id=%s image_ref=synthetic instance_id=hetzner-100000001 cli_version=1.0.0 cutover_flag=done probe_schema=8 host_role=%s flush_latched=true redis_keys=10 redis_expires=9 redis_key_patterns=synthetic:* data_mount_src=%s data_bytes=1000 data_mount_base=/dev/sdb data_mount_devid=%s registry_fns=7%s' \
    "$BOOT" "$1" "$2" "$3" "${4:+ $4}"
}
row() { # <dt> <message> [host] -> one JSONEachRow line with the documented double-encoded raw
  jq -cn --arg dt "$1" --arg m "$2" --arg h "${3:-soleur-inngest}" \
    '{dt: $dt, raw: ({host: $h, host_name: "soleur-inngest-prd", message: $m} | tojson)}'
}
ded()  { row "$1" "$(msg dedicated "$2" "${3:-$VOL}" "${4:-}")"; }
web()  { row "$1" "$(msg web "$2" "${3:-$VOL}")" soleur-web-1; }
# A web-ROLE row stamped with the dedicated host: isolates the role filter from the host pin.
sweb() { row "$1" "$(msg web "$2" "${3:-$VOL}")"; }
# A DEDICATED-role row from another host: isolates the host pin from the role filter.
odd()  { row "$1" "$(msg dedicated "$2" "${3:-$VOL}")" soleur-web-1; }
fx() { # <name> < rows on stdin -> path
  cat > "$WORK/fx/$1.jsonl"
  printf '%s' "$WORK/fx/$1.jsonl"
}
ledger() { # <out> <luks-mechanism> <luks-mapper> <backstop-expires|__none__>
  jq -n --arg m "$2" --arg mp "$3" --arg e "$4" '{
    schema_version: 1,
    stores: ([
      {store: "hcloud_volume.other", device_binding: {mapper: "decoy"}, at_rest: {mechanism: "luks"}},
      {store: "hcloud_volume.inngest_redis_luks", device_binding: {mapper: $mp}, at_rest: {mechanism: $m}}
    ] + (if $e == "__none__" then [] else [
      {store: "hcloud_volume.inngest_redis", device_binding: {mapper: "inngest-redis-plain"},
       at_rest: {mechanism: "plaintext-exception", exception: {expires_on: $e}}}
    ] end))
  }' > "$1"
}

# ── the runner ────────────────────────────────────────────────────────────────────────────────
# Per-case seams (reset_case clears them):
#   C_ROWS    fixture rows file the stub cats            C_LEDGER  ledger spec "mech mapper exp",
#   C_STUB    ok | fail | garbage | none                           or raw:<file>, or absent
#   C_NOW     SOLEUR_FT_NOW (default $NOW; "__unset__")  C_PROBE   probe source (default shipped)
#   C_XTRACE  1 -> run under bash -x                     C_UNSET   a BETTERSTACK_QUERY_* to blank
reset_case() {
  C_ROWS="/dev/null"; C_LEDGER="luks inngest-redis $EXP_FUTURE"; C_STUB="ok"; C_NOW="$NOW"
  C_PROBE="$PROBE_SRC"; C_XTRACE=0; C_UNSET=""; C_REQUIRE=""; C_LEAD=0; C_ARGS=""
}
reset_case

OUT="$WORK/out"
run_probe() { # -> echoes the status; combined output in $OUT
  local root="$WORK/root" probe
  probe="$root/scripts/followthroughs/$PROBE_NAME"
  case "$root" in "$WORK"/root) rm -rf -- "$root" ;; *) echo 199; return ;; esac
  mkdir -p "$root/scripts/followthroughs"
  cp "$C_PROBE" "$probe"

  case "$C_LEDGER" in
    absent) : ;;
    raw:*)  cp "${C_LEDGER#raw:}" "$root/scripts/encryption-posture-ledger.json" ;;
    *)      # shellcheck disable=SC2086
            ledger "$root/scripts/encryption-posture-ledger.json" $C_LEDGER ;;
  esac

  if [[ "$C_STUB" != "none" ]]; then
    cat > "$root/scripts/betterstack-query.sh" <<STUB
#!/usr/bin/env bash
argv="\$*"
# Asserted as the EXACT argument list: a substring check lets a suffixed grep value or a repeated
# --since/--limit (the helper keeps the last one) pass silently.
[[ "\$argv" == "--since 26h --grep SOLEUR_INNGEST_SERVER_PROBE --limit 5000" ]] || { echo "STUB: unexpected argv: \$argv" >&2; exit 64; }
case "$C_STUB" in
  fail)
    echo "betterstack-query: auth failed for user=stub password=$FAKE_CRED" >&2
    echo "curl: (22) https://stub/?token=$FAKE_CRED"
    exit 7 ;;
  garbage)
    echo "<html>502 Bad Gateway</html>"
    echo "Code: 62. DB::Exception: Syntax error"
    exit 0 ;;
esac
# H1: --grep is IGNORED on purpose; every fixture row comes back.
cat "$C_ROWS"
STUB
    chmod +x "$root/scripts/betterstack-query.sh"
  fi

  local -a envv=(PATH="$PATH" HOME="$HOME" TMPDIR="$TMPDIR")
  local v
  for v in BETTERSTACK_QUERY_HOST BETTERSTACK_QUERY_USERNAME BETTERSTACK_QUERY_PASSWORD; do
    if [[ "$C_UNSET" == "$v" ]]; then envv+=("$v="); else envv+=("$v=stub"); fi
  done
  [[ "$C_NOW" == "__unset__" ]] || envv+=("SOLEUR_FT_NOW=$C_NOW")
  local -a sh=(bash)
  [[ "$C_XTRACE" == "1" ]] && sh=(bash -x)
  # env -i mirrors the sweeper: no ambient SOLEUR_FT_* reaches the probe.
  # shellcheck disable=SC2086
  env -i "${envv[@]}" "${sh[@]}" "$probe" $C_ARGS >"$OUT" 2>&1
  echo $?
}

# 0 is the sweeper's CLOSE verb and 1 its reopen trigger. Shape reused from
# ccla-representative-icla-7922.test.sh; self-tested below with a synthetic 0.
assert_never_close_verb() { # <rc> <label>
  if [[ "$1" == "0" || "$1" == "1" ]]; then
    fail "INVARIANT: the probe returned rc=$1 ($2) — 0 closes #8285 and 1 reopens it; neither may EVER be taken"
    return 1
  fi
  return 0
}

markers_of() { grep -oE 'verdict=[a-z_]+' "$OUT" | cut -d= -f2 | paste -sd, - || true; }

expect() { # <name> <rc> <marker>
  cases=$((cases + 1))
  local name="$1" want="$2" marker="$3" got ok=1 all
  got="$(run_probe)"
  [[ -s "$OUT" ]] || { fail "$name — the probe produced NO output; did it run?"; return; }
  assert_never_close_verb "$got" "$name" >&2 || return
  [[ "$got" == "$want" ]] || ok=0
  grep -qE "verdict=${marker}( |\$)" "$OUT" || ok=0
  all="$(cat "$OUT")"
  if [[ "$C_XTRACE" != "1" ]] && grep -qiE '\bexit' <<<"$all"; then
    ok=0; printf '        | human-readable output contains the word "exit"\n' >&2
  fi
  if grep -qF "$FAKE_CRED" <<<"$all"; then
    ok=0; printf '        | the query tool'"'"'s credential-shaped output was passed through\n' >&2
  fi
  if grep -qF "$VOL" <<<"$all"; then
    ok=0; printf '        | the volume alias leaked into public output\n' >&2
  fi
  if [[ -n "$C_REQUIRE" ]] && ! grep -qF -- "$C_REQUIRE" <<<"$all"; then
    ok=0; printf '        | missing required text: %s\n' "$C_REQUIRE" >&2
  fi
  if [[ "$C_LEAD" == "1" ]] && [[ "$(grep -v '^inngest-luks-property\[' "$OUT" | head -1)" != "ACTION REQUIRED: $LEAD"* ]]; then
    ok=0; printf '        | the first human-readable line does not LEAD with the backstop warning\n' >&2
  fi
  if (( ok )); then
    pass "$name (status $got, verdict $marker)"
  else
    fail "$name — expected status $want + verdict=$marker, got status $got [$(markers_of)]"
    sed 's/^/        | /' "$OUT" >&2
  fi
}

# ── self-tests of the machinery ───────────────────────────────────────────────────────────────
_p0=$passes; _f0=$fails
pass "SELFTEST pass() moves its counter"
fail "SELFTEST fail() moves its counter (expected, reversed below)" 2>/dev/null
assert_never_close_verb 0 SELFTEST 2>/dev/null
if (( passes != _p0 + 1 || fails != _f0 + 2 )); then
  echo "FATAL: the verdict helpers do not move their counters — every assertion below is unbacked." >&2
  exit 1
fi
passes=$_p0; fails=$_f0

echo "== static: never-0 / never-1 =="
# The allowlist scan. Comment lines are BLANKED (not deleted) so line numbers survive; the capture
# excludes quotes, `;` and `)` so `trap '…; exit 3' EXIT` and `2) exit 2 ;;` both parse.
allowlist_violations() { # <file> -> "line:token" for every exit token not followed by 2|3|5|64|78
  sed -E 's/^[[:space:]]*#.*$//' "$1" \
    | grep -noE "\bexit\b[[:space:]]*[^[:space:];)'\"]*" \
    | sed -E 's/[[:space:]]+$//' \
    | grep -vE ':exit[[:space:]]+(2|3|5|64|78)$' || true
}
last_nonblank() { grep -vE '^[[:space:]]*$' "$1" | tail -1; }

printf '#!/usr/bin/env bash\nexit 2\nfoo; exit 1\nexit "$rc"\n' > "$WORK/scan-positive.sh"
cases=$((cases + 1))
_v="$(allowlist_violations "$WORK/scan-positive.sh")"
if [[ "$_v" == $'3:exit 1\n4:exit' ]]; then pass "scanner known-positive: flags exit 1 and a bare/variable exit"
else fail "scanner known-positive: got [$_v]"; fi

cases=$((cases + 1))
_v="$(allowlist_violations "$PROBE_SRC")"
if [[ -z "$_v" ]]; then pass "probe: every exit token is in {2,3,5,64,78}"
else fail "probe: non-allowlisted exit token(s): $_v"; fi

cases=$((cases + 1))
if [[ "$(last_nonblank "$PROBE_SRC")" == "exit 3" ]]; then pass "probe: last non-blank line is literally 'exit 3'"
else fail "probe: last non-blank line is '$(last_nonblank "$PROBE_SRC")', not 'exit 3'"; fi

cases=$((cases + 1))
if grep -qE '^trap on_exit EXIT$' "$PROBE_SRC" && grep -qE '^on_exit\(\) \{$' "$PROBE_SRC"; then
  pass "probe: an EXIT trap (on_exit) is installed"
else fail "probe: no 'trap on_exit EXIT' / on_exit() found"; fi

STRIPPED="$(sed -E 's/^[[:space:]]*#.*$//' "$PROBE_SRC")"
cases=$((cases + 1))
if [[ "$(grep -cE '(^|[;&|[:space:]])trap[[:space:]]' <<<"$STRIPPED" || true)" == 1 ]]; then pass "probe: exactly one trap statement (no trap -, trap '', or re-trap)"
else fail "probe: expected exactly one trap statement, found $(grep -cE '(^|[;&|[:space:]])trap[[:space:]]' <<<"$STRIPPED" || true)"; fi
cases=$((cases + 1))
if ! grep -qE '(^|[;&|[:space:](])(exec|kill)([[:space:]]|$)' <<<"$STRIPPED"; then pass "probe: no exec or kill (both bypass the EXIT trap's remap)"
else fail "probe: exec/kill found: $(grep -nE '(^|[;&|[:space:](])(exec|kill)([[:space:]]|$)' <<<"$STRIPPED" | head -3)"; fi
cases=$((cases + 1))
_tl="$(grep -nxF 'trap on_exit EXIT' "$PROBE_SRC" | cut -d: -f1)"
_xe="$(grep -nxF 'esac' "$PROBE_SRC" | head -1 | cut -d: -f1)"
_first="$(awk -v x="${_xe:-0}" 'NR > x' "$PROBE_SRC" | grep -nvE '^[[:space:]]*(#.*)?$|^marker\(\) \{( |$)|^on_exit\(\) \{( |$)|^  |^\}$' | head -1 | cut -d: -f1)"
[[ -n "$_first" ]] && _first=$(( _first + _xe ))
if [[ -n "$_tl" && -n "$_xe" && "$_tl" == "$_first" ]]; then pass "probe: the trap is the first top-level statement after the xtrace refusal"
else fail "probe: the first top-level statement is line $_first, the trap is line $_tl"; fi
printf '#!/usr/bin/env bash\nexec true\nfoo; kill -9 $$\n' > "$WORK/ban-positive.sh"
cases=$((cases + 1))
if [[ "$(sed -E 's/^[[:space:]]*#.*$//' "$WORK/ban-positive.sh" | grep -cE '(^|[;&|[:space:](])(exec|kill)([[:space:]]|$)' || true)" == 2 ]]; then pass "ban scan known-positive: flags exec and kill"
else fail "ban scan known-positive: did not flag both"; fi

cases=$((cases + 1))
if [[ -x "$PROBE_SRC" ]]; then pass "probe is executable"; else fail "probe is not executable"; fi

echo "== static: header =="
HEADER="$(sed -n '1,/^set -uo pipefail$/p' "$PROBE_SRC")"
RETIRE="$(awk '/^# RETIREMENT:/{on=1} on && /^#[[:space:]]*$/{on=0} on && /^#/{print} on && !/^#/{on=0}' "$PROBE_SRC" | tr '\n' ' ')"
for want in 'NOTIFY-ONLY' 'never closes #8285'; do
  cases=$((cases + 1))
  if grep -qF -- "$want" <<<"$HEADER"; then pass "header carries '$want'"; else fail "header lacks '$want'"; fi
done
for want in '#8285 closes' 'inngest-luks-property-8296.test.sh' 'run_suite "scripts/inngest-luks-property-8296"' 'scripts/test-all.sh' 'directive'; do
  cases=$((cases + 1))
  if grep -qF -- "$want" <<<"$RETIRE"; then pass "RETIREMENT: names '$want'"; else fail "RETIREMENT: paragraph lacks '$want' [$RETIRE]"; fi
done
cases=$((cases + 1))
if grep -qE '^set -uo pipefail$' "$PROBE_SRC" && ! grep -qE '^set -e' "$PROBE_SRC"; then pass "probe uses set -uo pipefail, never -e"
else fail "probe must use 'set -uo pipefail' and no -e"; fi
cases=$((cases + 1))
if grep -qF 'REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"' "$PROBE_SRC" && ! grep -q 'rev-parse' "$PROBE_SRC"; then
  pass "probe resolves REPO_ROOT from its own location (no git rev-parse)"
else fail "probe must derive REPO_ROOT from BASH_SOURCE, not git"; fi

echo "== decision table =="
# Row 1: xtrace with a live credential.
reset_case; C_XTRACE=1
expect "row1 traced with a credential set" 78 xtrace_refused

# Row 2: the query failed or answered garbage.
reset_case; C_STUB=fail
expect "row2 helper failed (credential-shaped output withheld)" 3 query_failed
reset_case; C_STUB=garbage
expect "row2 helper answered non-JSON" 3 query_failed
reset_case; C_STUB=none
expect "row2 helper missing" 3 query_failed
reset_case; C_UNSET=BETTERSTACK_QUERY_PASSWORD
expect "row2 credential unset" 3 query_failed

# Row 3: no dedicated probe row in the window.
reset_case; C_ROWS="$(: | fx empty)"
expect "row3 empty window" 3 no_rows
reset_case; C_ROWS="$(web "$DT_FRESH" "$PLAIN_SRC" | fx webonly)"
expect "row3 only web-role rows" 3 no_rows
reset_case; C_ROWS="$(row "$DT_FRESH" "{\"action\":\"opened\",\"body\":\"$(msg dedicated "$LUKS_SRC" "$VOL")\"}" | fx echoonly)"
expect "row3 only a webhook row QUOTING the marker" 3 no_rows

# Row 4: newest row older than 3h. (Mutation row 3: on the LUKS mapper, ledger luks.)
reset_case; C_ROWS="$(ded "$DT_STALE" "$LUKS_SRC" | fx stale)"
expect "row4 / mut3 newest row 3h10m old, on LUKS, ledger luks" 3 producer_silent

# Row 5: the newest row is unusable. (Mutation row 6.)
for bad in "__UNREADABLE__" "n/a" "" "sdb" ; do
  reset_case; C_ROWS="$(ded "$DT_FRESH" "$bad" | fx "src-$RANDOM")"
  expect "row5 / mut6 data_mount_src='$bad'" 3 row_unusable
done
for bad in "__NOMATCH__" "__AMBIGUOUS__" "scsi-0HC_Volume_" "n/a"; do
  reset_case; C_ROWS="$(ded "$DT_FRESH" "$LUKS_SRC" "$bad" | fx "devid-$RANDOM")"
  expect "row5 data_mount_devid='$bad'" 3 row_unusable
done
reset_case; C_ROWS="$(row "$DT_FRESH" "SOLEUR_INNGEST_SERVER_PROBE http_code=200 host_role=dedicated data_mount_src=$LUKS_SRC" | fx nodevid)"
expect "row5 data_mount_devid absent" 3 row_unusable

# Row 6: the ledger cannot be read.
_fresh_luks="$(ded "$DT_FRESH" "$LUKS_SRC" | fx fresh-luks)"
reset_case; C_ROWS="$_fresh_luks"; C_LEDGER=absent
expect "row6 ledger absent" 3 ledger_unreadable
printf '{"stores":[{"store": not-json\n' > "$WORK/fx/ledger-malformed.json"
reset_case; C_ROWS="$_fresh_luks"; C_LEDGER="raw:$WORK/fx/ledger-malformed.json"
expect "row6 ledger malformed" 3 ledger_unreadable
jq -n '{stores:[{store:"hcloud_volume.inngest_redis", at_rest:{mechanism:"plaintext-exception"}}]}' > "$WORK/fx/ledger-norow.json"
reset_case; C_ROWS="$_fresh_luks"; C_LEDGER="raw:$WORK/fx/ledger-norow.json"
expect "row6 inngest_redis_luks row missing" 3 ledger_unreadable
jq -n '{stores:[{store:"hcloud_volume.inngest_redis_luks", device_binding:{mapper:"inngest-redis"}, at_rest:{}}]}' > "$WORK/fx/ledger-nomech.json"
reset_case; C_ROWS="$_fresh_luks"; C_LEDGER="raw:$WORK/fx/ledger-nomech.json"
expect "row6 at_rest.mechanism missing" 3 ledger_unreadable
jq -n '{stores:[{store:"hcloud_volume.inngest_redis_luks", at_rest:{mechanism:"luks"}}]}' > "$WORK/fx/ledger-nomapper.json"
reset_case; C_ROWS="$_fresh_luks"; C_LEDGER="raw:$WORK/fx/ledger-nomapper.json"
expect "row6 device_binding.mapper missing" 3 ledger_unreadable

# Row 7: claims luks, store not on the mapper.
reset_case; C_ROWS="$(ded "$DT_FRESH" "$PLAIN_SRC" | fx plain)"; C_LEAD=1
C_REQUIRE="inngest-luks-cutover-6894.md"
expect "row7 claims luks, store on /dev/sdb (leads with the backstop warning, cites the runbook)" 5 rollback_inversion
reset_case; C_ROWS="$(ded "$DT_FRESH" "/dev/mapper/inngest-redis-plain" | fx prefix)"; C_LEAD=1
expect "mut1 src /dev/mapper/inngest-redis-plain vs mapper inngest-redis (no prefix match)" 5 rollback_inversion
reset_case; C_ROWS="$(ded "$DT_FRESH" "$PLAIN_SRC" "$VOL" "data_mount_src=$LUKS_SRC" | fx firstwins)"
expect "row7 an appended tail cannot override data_mount_src (first-wins)" 5 rollback_inversion
# Mutation row 4: the newest (last line) on plaintext, an older one on LUKS.
reset_case; C_ROWS="$({ ded "$DT_OLDER" "$LUKS_SRC"; ded "$DT_FRESH" "$PLAIN_SRC"; } | fx twoRows)"
expect "mut4 newest row plaintext, older row LUKS" 5 rollback_inversion
reset_case; C_ROWS="$({ ded "$DT_FRESH" "$PLAIN_SRC"; ded "$DT_OLDER" "$LUKS_SRC"; } | fx twoRowsDesc)"
expect "mut4b newest-by-dt is plaintext even when listed first" 5 rollback_inversion

# Row 8: does not claim luks, store on the mapper. (Mutation row 2.)
reset_case; C_ROWS="$_fresh_luks"; C_LEDGER="plaintext-exception inngest-redis $EXP_FUTURE"
expect "row8 / mut2 ledger plaintext-exception, store on LUKS" 5 under_claim

# Row 9: encrypted and agreeing, backstop past its expiry.
reset_case; C_ROWS="$_fresh_luks"; C_LEDGER="luks inngest-redis $EXP_PAST"
C_REQUIRE="Destroy the backstop under #8285"
expect "row9 luks + on mapper + a day past expires_on + backstop row present" 5 backstop_expired
reset_case; C_ROWS="$_fresh_luks"; C_LEDGER="luks inngest-redis 2026-13-45"
expect "row9 backstop expires_on malformed in the agreeing state" 3 ledger_unreadable

# Row 10: agreement.
reset_case; C_ROWS="$_fresh_luks"; C_REQUIRE="healthy: nothing to do; this probe never closes #8285"
expect "row10 luks + on mapper, a day before expires_on" 2 agree
reset_case; C_ROWS="$_fresh_luks"; C_LEDGER="luks inngest-redis __none__"
expect "row10 luks + on mapper, past expiry but the backstop row is gone" 2 agree

# Clock.
reset_case; C_ROWS="$_fresh_luks"; C_NOW="yesterday"
expect "clock SOLEUR_FT_NOW malformed" 3 clock_malformed
reset_case; C_ROWS="$_fresh_luks"; C_NOW=""
expect "clock SOLEUR_FT_NOW set but empty" 3 clock_malformed

# expect() OWNS the verdict, so it gets its own known-negative: a wrong status and a wrong marker
# must each move fails. Counters and the case tally are unwound so the floor stays exact.
_p0=$passes; _f0=$fails; _c0=$cases
reset_case; C_ROWS="$_fresh_luks"; expect "SELFTEST expect() wrong status" 5 agree 2>/dev/null >/dev/null
_f1=$fails
reset_case; C_ROWS="$_fresh_luks"; expect "SELFTEST expect() wrong marker" 2 under_claim 2>/dev/null >/dev/null
if (( _f1 != _f0 + 1 || fails != _f0 + 2 || passes != _p0 )); then
  printf 'FATAL: expect() did not reject a wrong status and a wrong marker -- every decision-table case is unbacked.\n' >&2
  exit 1
fi
passes=$_p0; fails=$_f0; cases=$_c0

# The other direction of mut4: newest on LUKS, an older dedicated row on plaintext (the day after a
# re-cutover) must be 2 agree, whichever order the helper lists them in.
reset_case; C_ROWS="$({ ded "$DT_OLDER" "$PLAIN_SRC"; ded "$DT_FRESH" "$LUKS_SRC"; } | fx twoRowsLuksNewest)"
expect "mut4c newest row LUKS, older row plaintext" 2 agree
reset_case; C_ROWS="$({ ded "$DT_FRESH" "$LUKS_SRC"; ded "$DT_OLDER" "$PLAIN_SRC"; } | fx twoRowsLuksNewestDesc)"
expect "mut4d newest-by-dt is LUKS even when listed first" 2 agree
# A 'T'-separated dt sorts with the ' '-separated ones (normalised), so the newer row still wins.
reset_case; C_ROWS="$({ ded "2026-10-01T09:00:00Z" "$LUKS_SRC"; ded "$DT_OLDER" "$PLAIN_SRC"; } | fx mixedDt)"
expect "dt 'T' vs ' ' forms compare as instants, not strings" 2 agree

# dt that cannot be read, or lies in the future.
reset_case; C_ROWS="$(ded "not-a-date" "$LUKS_SRC" | fx dtBad)"
expect "row5 newest dt unreadable" 3 row_unusable
reset_case; C_ROWS="$({ ded "$DT_FRESH" "$PLAIN_SRC"; ded "2027-01-01 00:00:00.000000" "$LUKS_SRC"; } | fx dtFuture)"
C_REQUIRE="field=dt_future"
expect "row5 newest dt in the future never decides" 3 row_unusable

# Usage.
reset_case; C_ROWS="$_fresh_luks"; C_ARGS="extra"
expect "usage: any argument" 64 usage

# First host_role token wins; an appended role cannot promote a web row.
reset_case; C_ROWS="$(row "$DT_FRESH" "$(msg web "$LUKS_SRC" "$VOL" "host_role=dedicated")" | fx roleTail)"
expect "row3 appended host_role=dedicated cannot promote a web-role row" 3 no_rows

# Ledger shape: duplicate luks rows, duplicate backstop rows.
jq -n '{stores:[
  {store:"hcloud_volume.inngest_redis_luks", device_binding:{mapper:"inngest-redis"}, at_rest:{mechanism:"luks"}},
  {store:"hcloud_volume.inngest_redis_luks", device_binding:{mapper:"inngest-redis"}, at_rest:{mechanism:"luks"}}]}' > "$WORK/fx/ledger-twoluks.json"
reset_case; C_ROWS="$_fresh_luks"; C_LEDGER="raw:$WORK/fx/ledger-twoluks.json"; C_REQUIRE="reason=luks_row_count"
expect "row6 two luks rows" 3 ledger_unreadable
jq -n --arg a "$EXP_FUTURE" --arg b "$EXP_PAST" '{stores:[
  {store:"hcloud_volume.inngest_redis_luks", device_binding:{mapper:"inngest-redis"}, at_rest:{mechanism:"luks"}},
  {store:"hcloud_volume.inngest_redis", at_rest:{mechanism:"plaintext-exception", exception:{expires_on:$a}}},
  {store:"hcloud_volume.inngest_redis", at_rest:{mechanism:"plaintext-exception", exception:{expires_on:$b}}}]}' > "$WORK/fx/ledger-twoback.json"
reset_case; C_ROWS="$_fresh_luks"; C_LEDGER="raw:$WORK/fx/ledger-twoback.json"; C_REQUIRE="reason=backstop_row_count"
expect "row6 two backstop rows (a stale duplicate cannot hide a sooner expiry)" 3 ledger_unreadable

# Expiry boundary: expires_on == today is not yet past.
reset_case; C_ROWS="$_fresh_luks"; C_LEDGER="luks inngest-redis 2026-10-01"
expect "row9 boundary: expires_on is today -> still agree" 2 agree

# The REAL ledger, read by the shipped probe: it must parse and agree with a fresh LUKS row.
reset_case; C_ROWS="$_fresh_luks"; C_LEDGER="raw:$REPO/scripts/encryption-posture-ledger.json"
expect "the committed ledger parses and agrees with a fresh LUKS row (row names, paths, mapper)" 2 agree

# The runbook every ACTION message points at exists and carries the revert section.
cases=$((cases + 1))
if [[ -f "$REPO/knowledge-base/engineering/operations/runbooks/inngest-luks-cutover-6894.md" ]] \
   && grep -qE '^## 5a\. .*op=luks-rollback' "$REPO/knowledge-base/engineering/operations/runbooks/inngest-luks-cutover-6894.md"; then
  pass "runbook inngest-luks-cutover-6894.md exists and carries section 5a for op=luks-rollback"
else fail "runbook or its section 5a (op=luks-rollback) is missing -- the ACTION messages point nowhere"; fi

echo "== harness rows =="
# H1: a web-1 row on plaintext is the NEWEST; the dedicated row is on LUKS. The stub returned both.
_h1="$({ ded "$DT_FRESH" "$LUKS_SRC"; web "$DT_NEWEST" "$PLAIN_SRC"; } | fx h1)"
reset_case; C_ROWS="$_h1"
expect "H1 newest web-role row on plaintext is ignored; the dedicated row decides" 2 agree
# H1r: the same host, a web ROLE (isolates the role filter from the host pin).
_h1r="$({ ded "$DT_FRESH" "$LUKS_SRC"; sweb "$DT_NEWEST" "$PLAIN_SRC"; } | fx h1r)"
reset_case; C_ROWS="$_h1r"
expect "H1r newest same-host web-role row is ignored" 2 agree
# H1h: another HOST claiming host_role=dedicated (isolates the host pin from the role filter).
_h1h="$({ ded "$DT_FRESH" "$LUKS_SRC"; odd "$DT_NEWEST" "$PLAIN_SRC"; } | fx h1h)"
reset_case; C_ROWS="$_h1h"
expect "H1h newest other-host row claiming host_role=dedicated is ignored" 2 agree
# H2: non-canonical mapper, read from the ledger, plus unrelated rows around the fresh newest.
reset_case
C_ROWS="$({ ded "$DT_OLDEST" "/dev/mapper/vault-x"; web "$DT_OLDER" "$PLAIN_SRC";
  row "$DT_NEWEST" "{\"action\":\"opened\",\"body\":\"$(msg dedicated "$PLAIN_SRC" "$VOL")\"}";
  row "$DT_NEWEST" "SOLEUR_INNGEST_LUKS_STAGE stage=verify host_role=dedicated data_mount_src=$PLAIN_SRC";
  ded "$DT_FRESH" "/dev/mapper/vault-x"; } | fx h2)"
C_LEDGER="luks vault-x $EXP_FUTURE"
expect "H2 mapper read from the ledger (vault-x), unrelated rows ignored" 2 agree
# H3: a reverted pair, before expiry.
reset_case; C_ROWS="$(ded "$DT_FRESH" "$PLAIN_SRC" | fx h3)"; C_LEDGER="plaintext-exception inngest-redis $EXP_FUTURE"
expect "H3 reverted pair (plaintext claim, plaintext store)" 2 agree
# H5: a reverted pair a day AFTER expiry is still agree, never backstop_expired.
reset_case; C_ROWS="$WORK/fx/h3.jsonl"; C_LEDGER="plaintext-exception inngest-redis $EXP_PAST"
expect "H5 reverted pair past expiry" 2 agree

# ── mutation machinery ────────────────────────────────────────────────────────────────────────
echo "== mutation runner self-test =="
# verdict_holds: did the last run produce exactly <rc> + verdict=<marker>?
verdict_holds() { [[ "$1" == "$LAST_RC" ]] && grep -qE "verdict=$2( |\$)" "$OUT"; }
run_case() { LAST_RC="$(run_probe)"; }

# landed_within <orig> <mutant> "<lo>-<hi> [<lo>-<hi> …]": the diff is non-empty and every hunk's
# ORIGINAL-side line numbers sit inside one of the ranges.
landed_within() {
  local hunks
  hunks="$(diff "$1" "$2" | grep -E '^[0-9]' || true)"
  [[ -n "$hunks" ]] || return 1
  awk -v ranges="$3" '
    BEGIN { n = split(ranges, R, " ") }
    { split($0, p, /[acd]/); k = split(p[1], ab, ","); a = ab[1] + 0; b = (k > 1) ? ab[2] + 0 : a
      ok = 0
      for (i = 1; i <= n; i++) { split(R[i], lh, "-"); if (a >= lh[1] + 0 && b <= lh[2] + 0) ok = 1 }
      if (!ok) bad = 1 }
    END { if (bad) print "out" }' <<<"$hunks" | grep -q out && return 1
  return 0
}
fn_range() { # <file> <fn-name> -> "start-end" of `name() {` … first `}` at column 0
  awk -v f="$2" '$0 == f "() {" { s = NR } s && !e && NR > s && $0 == "}" { e = NR } END { if (s && e) print s "-" e }' "$1"
}
line_of() { grep -nxF -- "$2" "$1" | cut -d: -f1; }
count_x() { grep -cxF -- "$2" "$1" || true; }

MUT_TABLE="$WORK/mutations.tsv"
: > "$MUT_TABLE"
expect_red() { # <row> <name> <orig-rc> <orig-marker>  (runs the current C_* seams)
  cases=$((cases + 1))
  run_case
  local seen; seen="$(markers_of)"
  printf '%s\t%s\t%s\t%s\n' "$1" "$2" "${seen:-none}" "$LAST_RC" >> "$MUT_TABLE"
  if verdict_holds "$3" "$4"; then
    fail "mutation row $1 ($2) SURVIVED: still status $3 + verdict=$4"
  else
    pass "mutation row $1 ($2) is RED: status $LAST_RC, verdicts [$seen]"
  fi
}

# Known-positive: the shipped probe on the agree fixture HOLDS (the detector must say "survived").
reset_case; C_ROWS="$_fresh_luks"; run_case
cases=$((cases + 1))
if verdict_holds 2 agree; then pass "runner known-positive: shipped probe + agree fixture holds"
else fail "runner known-positive: shipped probe did not give 2 agree (status $LAST_RC)"; fi
# Known-negative: the same detector on a rollback fixture does NOT hold 2 agree.
reset_case; C_ROWS="$WORK/fx/plain.jsonl"; run_case
cases=$((cases + 1))
if ! verdict_holds 2 agree; then pass "runner known-negative: a rollback fixture does not read as 2 agree"
else fail "runner known-negative: the detector reports 2 agree on a rollback fixture"; fi

DECIDE_R="$(fn_range "$PROBE_SRC" decide)"
MEASURE_R="$(fn_range "$PROBE_SRC" measure)"
MAIN_START="$(line_of "$PROBE_SRC" '# ── MAIN')"
TOTAL="$(wc -l < "$PROBE_SRC")"
MAIN_R="${MAIN_START:-0}-$TOTAL"
cases=$((cases + 1))
if [[ -n "$DECIDE_R" && -n "$MEASURE_R" && -n "$MAIN_START" ]] \
   && [[ "$(count_x "$PROBE_SRC" measure)" == 1 && "$(count_x "$PROBE_SRC" read_ledger)" == 1 && "$(count_x "$PROBE_SRC" decide)" == 1 ]]; then
  pass "mutation seams located (decide $DECIDE_R, measure $MEASURE_R, main $MAIN_R)"
else
  fail "mutation seams not found: decide='$DECIDE_R' measure='$MEASURE_R' main='$MAIN_START' — every code mutation below would be vacuous"
fi

assert_landed() { # <row> <mutant> <ranges>
  cases=$((cases + 1))
  if landed_within "$PROBE_SRC" "$2" "$3"; then pass "mutation row $1 landed inside $3"
  else fail "mutation row $1 did NOT land inside $3 — its RED would be vacuous"; return 1; fi
}

echo "== committed mutation rows =="
# Row 5 (order): both reads broken; the shipped order must say query_failed …
reset_case; C_STUB=fail; C_LEDGER=absent
expect "mut5 both reads broken -> the measurement's verdict wins" 3 query_failed
# … and the reversed order (read_ledger before measure) must not.
M="$WORK/mut/row5.sh"
awk '$0 == "measure" { held = $0; next } $0 == "read_ledger" { print; print held; next } { print }' "$PROBE_SRC" > "$M"
cases=$((cases + 1))
if (( $(line_of "$M" read_ledger) < $(line_of "$M" measure) )); then pass "mutation row 5: order swapped in the copy"
else fail "mutation row 5: the swap did not land"; fi
assert_landed 5 "$M" "$MAIN_R"
reset_case; C_STUB=fail; C_LEDGER=absent; C_PROBE="$M"
expect_red 5 "ledger read before the measurement" 3 query_failed

# Row 7a: the agree arm's `exit 2` becomes `exit 0`. Static AND behavioural red; never 0/1.
M="$WORK/mut/row7a.sh"
sed -E 's/^    exit 2$/    exit 0/' "$PROBE_SRC" > "$M"
cases=$((cases + 1))
if [[ "$(grep -cxE '    exit 2' "$PROBE_SRC")" == 1 ]]; then pass "mutation row 7a: exactly one agree-arm 'exit 2' to target"
else fail "mutation row 7a: expected exactly one '    exit 2' line"; fi
assert_landed 7a "$M" "$DECIDE_R"
cases=$((cases + 1))
if allowlist_violations "$M" | grep -qE ':exit 0$'; then pass "mutation row 7a: static allowlist reds on exit 0"
else fail "mutation row 7a: static allowlist missed exit 0"; fi
reset_case; C_ROWS="$_fresh_luks"; C_PROBE="$M"
expect_red 7a "exit 2 -> exit 0 in the agree arm" 2 agree
cases=$((cases + 1))
if [[ "$LAST_RC" == 3 ]] && grep -qE 'verdict=trap_remapped( |$)' "$OUT"; then pass "mutation row 7a: the EXIT trap remapped 0 to 3"
else assert_never_close_verb "$LAST_RC" "row 7a" >/dev/null; fail "mutation row 7a: expected 3 trap_remapped, got $LAST_RC [$(markers_of)]"; fi

# Row 7b: the trailing `exit 3` deleted and decide() made to fall off its end (fall-through).
M="$WORK/mut/row7b.sh"
sed -E 's/^    exit 2$/    return 0/' "$PROBE_SRC" | awk -v last="$TOTAL" 'NR == last && $0 == "exit 3" { next } { print }' > "$M"
assert_landed 7b "$M" "$DECIDE_R $TOTAL-$TOTAL"
cases=$((cases + 1))
if [[ "$(last_nonblank "$M")" != "exit 3" ]]; then pass "mutation row 7b: static last-line check reds"
else fail "mutation row 7b: the trailing exit 3 is still there"; fi
reset_case; C_ROWS="$_fresh_luks"; C_PROBE="$M"
expect_red 7b "trailing exit 3 deleted, agree arm falls off" 2 agree
cases=$((cases + 1))
if [[ "$LAST_RC" == 3 ]] && grep -qE 'verdict=trap_remapped( |$)' "$OUT"; then pass "mutation row 7b (fall-through): 3 trap_remapped, never 0/1"
else assert_never_close_verb "$LAST_RC" "row 7b" >/dev/null; fail "mutation row 7b: expected 3 trap_remapped, got $LAST_RC [$(markers_of)]"; fi

# Row 7c: an unset variable referenced before the decision.
M="$WORK/mut/row7c.sh"
awk '$0 == "decide" { print ": \"$SOLEUR_8296_NEVER_SET\"" } { print }' "$PROBE_SRC" > "$M"
assert_landed 7c "$M" "$MAIN_R"
reset_case; C_ROWS="$_fresh_luks"; C_PROBE="$M"
expect_red 7c "unset variable referenced" 2 agree
cases=$((cases + 1))
if [[ "$LAST_RC" == 3 ]] && grep -qE 'verdict=trap_remapped( |$)' "$OUT"; then pass "mutation row 7c (unset variable): 3 trap_remapped, never 0/1"
else assert_never_close_verb "$LAST_RC" "row 7c" >/dev/null; fail "mutation row 7c: expected 3 trap_remapped, got $LAST_RC [$(markers_of)]"; fi

# The fall-through tail itself (must-PASS): with the decide call removed, the file's own last
# lines answer 3 unreachable.
M="$WORK/mut/fallthrough.sh"
awk '$0 == "decide" { next } { print }' "$PROBE_SRC" > "$M"
assert_landed fallthrough "$M" "$MAIN_R"
reset_case; C_ROWS="$_fresh_luks"; C_PROBE="$M"
expect "fall-through tail reached" 3 unreachable

# Row 8: a second, non-allowlisted exit after a compliant first, on one new arm's line.
M="$WORK/mut/row8.sh"
_d0="${DECIDE_R%-*}"
awk -v at="$_d0" '{ print } NR == at { print "  if [[ \"$MECH\" == __m8__ ]]; then marker m8; exit 3; exit 1; fi" }' "$PROBE_SRC" > "$M"
assert_landed 8 "$M" "$DECIDE_R"
cases=$((cases + 1))
_v="$(allowlist_violations "$M")"
_row8_line=$((_d0 + 1))
printf '8\tsecond exit token on one line\tstatic:%s\tn/a\n' "${_v:-none}" >> "$MUT_TABLE"
if [[ "$_v" == "$_row8_line:exit 1" ]]; then pass "mutation row 8 is RED: the scan flags the SECOND member ($_v)"
else fail "mutation row 8: expected exactly '$_row8_line:exit 1', got [$_v]"; fi

# Row 9: the backstop_expired arm deleted, NOW after expires_on.
M="$WORK/mut/row9.sh"
sed -E '/^  # ARM-BEGIN backstop_expired$/,/^  # ARM-END backstop_expired$/d' "$PROBE_SRC" > "$M"
assert_landed 9 "$M" "$DECIDE_R"
cases=$((cases + 1))
if ! grep -qF 'marker "backstop_expired"' "$M" && grep -qF 'marker "backstop_expired"' "$PROBE_SRC"; then pass "mutation row 9: the arm is gone from the copy"
else fail "mutation row 9: backstop_expired still present in the copy"; fi
reset_case; C_ROWS="$_fresh_luks"; C_LEDGER="luks inngest-redis $EXP_PAST"; C_PROBE="$M"
expect_red 9 "backstop_expired arm deleted" 5 backstop_expired

# H1 code mutations: remove the probe's OWN role filter, then its OWN host pin; each isolating
# fixture must turn.
M="$WORK/mut/h1r.sh"
grep -vF 'host_role=(?<r>' "$PROBE_SRC" > "$M"
assert_landed H1r "$M" "$MEASURE_R"
reset_case; C_ROWS="$_h1r"; C_PROBE="$M"
expect_red H1r "probe's host_role filter removed" 2 agree
M="$WORK/mut/h1h.sh"
grep -vF 'select(.host == $h and .host_name == $hn)' "$PROBE_SRC" > "$M"
assert_landed H1h "$M" "$MEASURE_R"
reset_case; C_ROWS="$_h1h"; C_PROBE="$M"
expect_red H1h "probe's host pin removed" 2 agree

echo "== rollback NEXT placement (AC-32) =="
# placement_check <file>: prints a reason and returns 1 on any violation.
placement_check() {
  local f="$1" label_re='^([[:space:]]*)luks-cutover\|luks-rollback\)[[:space:]]*$' n start indent end body
  n="$(grep -cE "$label_re" "$f" || true)"
  [[ "$n" == 1 ]] || { echo "case label found $n times (want exactly 1)"; return 1; }
  start="$(grep -nE "$label_re" "$f" | cut -d: -f1)"
  indent="$(sed -n "${start}p" "$f" | sed -E 's/^([[:space:]]*).*/\1/')"
  end="$(awk -v s="$start" -v t="${indent}  ;;" 'NR > s && ($0 == t || $0 ~ ("^" t "[[:space:]]*$")) { print NR; exit }' "$f")"
  [[ -n "$end" ]] || { echo "no ';;' terminator for the arm"; return 1; }
  body="$(sed -n "$((start + 1)),$((end - 1))p" "$f")"
  [[ -n "$(grep -vE '^[[:space:]]*(#.*)?$' <<<"$body")" ]] || { echo "extracted arm body is empty"; return 1; }
  [[ "$(grep -cF 'NEXT (not automatic)' "$f" || true)" == 1 ]] || { echo "file-wide 'NEXT (not automatic)' count is not 1"; return 1; }
  local nl cl el gl
  [[ "$(grep -cF 'NEXT (not automatic)' <<<"$body" || true)" == 1 ]] || { echo "the NEXT line is not inside the arm"; return 1; }
  nl="$(grep -nF 'NEXT (not automatic)' <<<"$body" | cut -d: -f1)"
  [[ "$(grep -cF "FSM confirmed '\$LK_EXPECT'" <<<"$body" || true)" == 1 ]] || { echo "confirm notice not found exactly once"; return 1; }
  cl="$(grep -nF "FSM confirmed '\$LK_EXPECT'" <<<"$body" | cut -d: -f1)"
  [[ "$(grep -cE 'if \[\[ "\$LK_STATE" == "\$LK_EXPECT" \]\]; then' <<<"$body" || true)" == 1 ]] || { echo "LK_STATE==LK_EXPECT branch not found exactly once"; return 1; }
  el="$(grep -nE 'if \[\[ "\$LK_STATE" == "\$LK_EXPECT" \]\]; then' <<<"$body" | cut -d: -f1)"
  gl="$(head -n "$((nl - 1))" <<<"$body" | grep -nE '^[[:space:]]*(el)?if[[:space:]]' | tail -1 | cut -d: -f1)"
  [[ -n "$gl" ]] || { echo "no enclosing if above the NEXT line"; return 1; }
  sed -n "${gl}p" <<<"$body" | grep -qE '^[[:space:]]*if \[\[ "?\$OP"? == "?luks-rollback"? \]\]; then[[:space:]]*$' \
    || { echo "the nearest guard above NEXT is not the luks-rollback guard: $(sed -n "${gl}p" <<<"$body")"; return 1; }
  (( el < cl && cl < gl && gl < nl )) || { echo "order violated (success-branch $el, confirm $cl, guard $gl, NEXT $nl)"; return 1; }
  if sed -n "$((el + 1)),$((nl - 1))p" <<<"$body" | grep -vE '^[[:space:]]*#' \
      | grep -qE '^[[:space:]]*(else|elif|fi|esac)\b|;;|REFUSING|::error::|\bexit\b'; then
    echo "a branch boundary or refusal sits between the success branch and NEXT"; return 1
  fi
  sed -n "${nl}p" <<<"$body" | grep -qE '^[[:space:]]*echo "::notice::NEXT \(not automatic\):[^"]*"$' \
    || { echo "NEXT is not a bare echo \"::notice::NEXT (not automatic): ...\" line (redirected, conditional or reshaped)"; return 1; }
  if (( gl + 1 <= nl - 1 )) && sed -n "$((gl + 1)),$((nl - 1))p" <<<"$body" | grep -qvE '^[[:space:]]*(#.*)?$'; then
    echo "something other than comments sits between the luks-rollback guard and NEXT (a loop, heredoc or function would make it dead)"; return 1
  fi
  if sed -n "${nl}p" <<<"$body" | grep -qE 'REFUSING|::error::'; then echo "NEXT sits on a refusal line"; return 1; fi
  return 0
}

cases=$((cases + 1))
_nx="$(grep -F 'NEXT (not automatic)' "$CUTOVER_SRC")"
if grep -qF 'scripts/encryption-posture-ledger.json' <<<"$_nx" && grep -qF 'knowledge-base/legal/article-30-register.md' <<<"$_nx" \
   && grep -qF 'inngest-luks-cutover-6894.md section 5a' <<<"$_nx" && grep -qF 'do NOT destroy' <<<"$_nx"; then
  pass "AC-32 the NEXT line names the ledger, the register, runbook section 5a and the do-not-destroy warning"
else fail "AC-32 the NEXT line lacks a required anchor: $_nx"; fi
for _dead in 'while false; do' '_next_unused() {'; do
  _m="$WORK/mut/cut-dead-$RANDOM.sh"
  awk -v nl="$(grep -nF 'NEXT (not automatic)' "$CUTOVER_SRC" | cut -d: -f1)" -v w="$_dead" 'NR == nl { print "      " w } { print }' "$CUTOVER_SRC" > "$_m"
  cases=$((cases + 1))
  if [[ -n "$(placement_check "$_m")" ]]; then pass "placement check reds when '$_dead' wraps the NEXT line"
  else fail "placement check PASSED with '$_dead' above the NEXT line"; fi
done

cases=$((cases + 1))
_why="$(placement_check "$CUTOVER_SRC")"
if [[ -z "$_why" ]]; then pass "AC-32 the real cutover-inngest.sh places NEXT under the luks-rollback guard after the confirm"
else fail "AC-32 real cutover-inngest.sh: $_why"; fi

# Extraction self-tests: a missing and a doubled label must both fail, never pass vacuously.
grep -vE '^[[:space:]]*luks-cutover\|luks-rollback\)[[:space:]]*$' "$CUTOVER_SRC" > "$WORK/mut/cut-nolabel.sh"
cases=$((cases + 1))
_why="$(placement_check "$WORK/mut/cut-nolabel.sh")"
if [[ -n "$_why" ]]; then pass "placement check reds when the case label is missing ($_why)"
else fail "placement check PASSED with no case label"; fi
awk '{ print } /^[[:space:]]*luks-cutover\|luks-rollback\)[[:space:]]*$/ && !d { print; d = 1 }' "$CUTOVER_SRC" > "$WORK/mut/cut-twolabel.sh"
cases=$((cases + 1))
_why="$(placement_check "$WORK/mut/cut-twolabel.sh")"
if [[ -n "$_why" ]]; then pass "placement check reds when the case label appears twice ($_why)"
else fail "placement check PASSED with a doubled case label"; fi

# Row 10: move the NEXT line on scratch copies.
_arm_s="$(grep -nE '^[[:space:]]*luks-cutover\|luks-rollback\)[[:space:]]*$' "$CUTOVER_SRC" | cut -d: -f1)"
_arm_e="$(awk -v s="${_arm_s:-0}" 'NR > s && $0 ~ /^    ;;[[:space:]]*$/ { print NR; exit }' "$CUTOVER_SRC")"
_nl="$(grep -nF 'NEXT (not automatic)' "$CUTOVER_SRC" | cut -d: -f1)"
_cl="$(grep -nF "FSM confirmed '\$LK_EXPECT'" "$CUTOVER_SRC" | cut -d: -f1)"
_rb="$(awk -v s="${_arm_s:-0}" -v e="${_arm_e:-0}" 'NR > s && NR < e && $0 ~ /^[[:space:]]*rolled-back\)[[:space:]]*$/ { r = NR } END { if (r) print r }' "$CUTOVER_SRC")"
cases=$((cases + 1))
if [[ -n "$_arm_s" && -n "$_arm_e" && -n "$_nl" && -n "$_cl" && -n "$_rb" && "$_nl" =~ ^[0-9]+$ ]]; then
  pass "row 10 seams located (arm $_arm_s-$_arm_e, confirm $_cl, NEXT $_nl, rolled-back $_rb)"
else
  fail "row 10 seams not found (arm '$_arm_s'-'$_arm_e' confirm '$_cl' NEXT '$_nl' rolled-back '$_rb')"
fi
move_next() { # <out> <mode: after-confirm | before-confirm | rolled-back>
  NEXT_TEXT="$(sed -n "${_nl}p" "$CUTOVER_SRC")" awk -v nl="$_nl" -v cl="$_cl" -v rb="$_rb" -v mode="$2" '
    NR == nl { next }
    mode == "before-confirm" && NR == cl { print ENVIRON["NEXT_TEXT"] }
    { print }
    mode == "after-confirm" && NR == cl { print ENVIRON["NEXT_TEXT"] }
    mode == "rolled-back" && NR == rb { print ENVIRON["NEXT_TEXT"] }' "$CUTOVER_SRC" > "$1"
}
row10() { # <mode> <expected new NEXT line>
  local m="$WORK/mut/cut-$1.sh" at why
  move_next "$m" "$1"
  cases=$((cases + 1))
  at="$(grep -nF 'NEXT (not automatic)' "$m" | cut -d: -f1 | paste -sd, -)"
  if [[ "$at" == "$2" ]] && landed_within "$CUTOVER_SRC" "$m" "$_arm_s-$_arm_e"; then
    pass "mutation row 10 ($1) landed: NEXT now at line $at, inside the arm"
  else
    fail "mutation row 10 ($1) did not land (NEXT at '$at', want $2)"; return
  fi
  cases=$((cases + 1))
  why="$(placement_check "$m")"
  printf '10\t%s\tplacement:%s\tn/a\n' "$1" "${why:-PASSED}" >> "$MUT_TABLE"
  if [[ -n "$why" ]]; then pass "mutation row 10 ($1) is RED: $why"
  else fail "mutation row 10 ($1) SURVIVED the placement check"; fi
}
row10 after-confirm "$((_cl + 1))"
row10 before-confirm "$_cl"
row10 rolled-back "$_rb"

echo
echo "== measured mutation verdicts (row, edit, verdicts seen, status) =="
sed 's/^/  /' "$MUT_TABLE"

# ── conservation and the floor ────────────────────────────────────────────────────────────────
echo
echo "=== $passes passed, $fails failed, $cases cases ==="
if (( passes + fails != cases )); then
  printf 'FATAL: verdict conservation violated — %s+%s != %s cases.\n' "$passes" "$fails" "$cases" >&2
  exit 1
fi
# H4: a HARD-CODED floor. A runtime-derived one falls when a case is deleted.
MIN_PASSES=114
if (( passes < MIN_PASSES )); then
  printf 'FATAL: only %s passes, below the floor of %s -- the suite was truncated, so a 0-failure tally proves nothing.\n' "$passes" "$MIN_PASSES" >&2
  exit 1
fi
(( fails == 0 )) || exit 1
echo "All $cases cases passed."
