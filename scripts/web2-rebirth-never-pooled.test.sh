#!/usr/bin/env bash
# Tests for scripts/web2-rebirth-never-pooled.sh (#9372): absent passes, present refuses, an unreadable config is NOT
# "absent", the match is exact-name, and the script never reaches a Doppler write verb.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="${DIR}/web2-rebirth-never-pooled.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"
fails=0
# doppler shim: MODE selects the answer; every call is logged so a write verb is visible.
cat > "$TMP/bin/doppler" <<'SH'
#!/usr/bin/env bash
echo "$*" >> "$CALLS"
case "$MODE" in
  fail) exit 1 ;;
  html) echo "<html>" ;;
  array_absent) echo '["OTHER_NAME"]' ;;
  array_present) echo '["WORKSPACES_LUKS_CUTOVER_AT","X"]' ;;
  obj_present) echo '{"WORKSPACES_LUKS_CUTOVER_AT":{},"X":{}}' ;;
  prefix) echo '["WORKSPACES_LUKS_CUTOVER_AT_OLD"]' ;;
  empty_array) echo '[]' ;;
  empty_object) echo '{}' ;;
  wrapped_upper) echo '{"NAMES":["OTHER_NAME"]}' ;;
  wrapped_names) echo '{"names":["WORKSPACES_LUKS_CUTOVER_AT"]}' ;;
  wrapped_secrets) echo '{"secrets":{"WORKSPACES_LUKS_CUTOVER_AT":{}}}' ;;
  array_of_objects) echo '[{"name":"WORKSPACES_LUKS_CUTOVER_AT"}]' ;;
  lowercase) echo '["workspaces_luks_cutover_at"]' ;;
  number_array) echo '[1,2]' ;;
  string_body) echo '"WORKSPACES_LUKS_CUTOVER_AT"' ;;
  string_other) echo '"x"' ;;
esac
SH
chmod +x "$TMP/bin/doppler"
runs=0
run() { # <name> <want-rc> <mode> [token]
  runs=$((runs + 1)); : > "$TMP/calls"
  out="$(env -i PATH="$TMP/bin:/usr/bin:/bin" HOME="$TMP" CALLS="$TMP/calls" MODE="$3" ${4-DOPPLER_TOKEN=tok} bash "$SCRIPT" 2>&1)"; rc=$?
  if [[ "$rc" -eq "$2" ]]; then echo "  ok   $1"; else echo "  FAIL $1 (rc=$rc want=$2): ${out:0:160}"; fails=$((fails + 1)); fi
}
run "marker absent (array form) -> 0" 0 array_absent
run "marker present (array form) -> REFUSED 1" 1 array_present
run "marker present (object form) -> REFUSED 1" 1 obj_present
run "a prefix-colliding name is not the marker -> 0" 0 prefix
run "an empty array is a legitimate absent (the config holds only the marker) -> 0" 0 empty_array
run "an empty object is a legitimate absent -> 0" 0 empty_object
run "a wrapper object {names:[marker]} is still a PRESENT marker (quoted anywhere) -> REFUSED 1" 1 wrapped_names
run "a wrapper object {secrets:{marker}} is a PRESENT marker -> REFUSED 1" 1 wrapped_secrets
run "an array of objects naming the marker is a PRESENT marker -> REFUSED 1" 1 array_of_objects
run "an uppercase wrapper object that does NOT hold the marker is a legitimate absent -> 0" 0 wrapped_upper
run "a lowercase name list -> 3" 3 lowercase
run "an array of numbers -> 3" 3 number_array
run "a bare JSON string that IS the marker name is a PRESENT marker -> REFUSED 1" 1 string_body
run "a bare JSON string that is not the marker is a shape we cannot read -> 3" 3 string_other
run "a failed list is not 'absent' -> 3" 3 fail
run "a non-JSON body is not 'absent' -> 3" 3 html
run "no token -> 3 and no doppler call" 3 array_absent ""
[[ ! -s "$TMP/calls" ]] && echo "  ok   no doppler call without a token" || { echo "  FAIL the script called doppler without a token"; fails=$((fails + 1)); }
run "absent run" 0 array_absent
if grep -qE ' (set|delete|upload|run|download)( |$)' "$TMP/calls" || ! grep -q -- '--only-names' "$TMP/calls"; then echo "  FAIL the call was not a names-only read: $(cat "$TMP/calls")"; fails=$((fails + 1)); else echo "  ok   only a names-only list was issued"; fi
if grep -nE 'secrets[^#]*(get|set|delete|upload|download)\b|doppler run' "$SCRIPT" | grep -v '^[0-9]*:#' | grep -c >/dev/null .; then echo "  FAIL the script mentions a value read or a write verb"; fails=$((fails + 1)); else echo "  ok   the script carries no value read and no write verb"; fi
# mutation: dropping the exact-name test must go red
cp "$SCRIPT" "$TMP/mut.sh"; mkdir -p "$TMP/lib"; cp "$DIR/lib/"*.sh "$TMP/lib/"; cp "$TMP/mut.sh" "$TMP/web2-rebirth-never-pooled.sh"
sed -i -E 's/any\(\. == \$n\)/any(. != $n)/' "$TMP/web2-rebirth-never-pooled.sh"
SCRIPT="$TMP/web2-rebirth-never-pooled.sh"; before=$fails; run "MUTANT (membership inverted) fails the absent row" 0 array_absent
if [[ "$fails" -gt "$before" ]]; then echo "  ok   mutation killed: inverted membership"; fails=$before; else echo "  FAIL mutation survived"; fails=$((fails + 1)); fi
# floor: the number of driven rows (deleting rows must not pass)
[[ "$runs" -ge 19 ]] || { echo "  FAIL row floor: ran ${runs} < 19"; fails=$((fails + 1)); }
[[ "$fails" -eq 0 ]] && { echo "web2-rebirth-never-pooled: all assertions passed"; exit 0; }
echo "web2-rebirth-never-pooled: ${fails} FAILED"; exit 1
