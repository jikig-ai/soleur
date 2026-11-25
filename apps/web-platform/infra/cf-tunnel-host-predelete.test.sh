#!/usr/bin/env bash
# cf-tunnel-host-predelete.test.sh: battery for scripts/cf-tunnel-host-predelete.sh (#12931, plan Guard 5).
#
# HARNESS. curl is a PATH stub that serves one record file per id, logs every call, and refuses any
# argv it does not model (exit 64, refused.log). The committed script's pin list is empty until the
# six ids are committed, so the happy-path rows run a COPY with synthesized ids written into the list:
# the script has no seam through which the environment could choose what it deletes.
set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../../.." && pwd)"
SUT="$HERE/scripts/cf-tunnel-host-predelete.sh"
[[ -f "$SUT" ]] || { printf '[FATAL] script under test missing: %s\n' "$SUT" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { printf '[FATAL] jq is required\n' >&2; exit 2; }

SBX="$(mktemp -d -t cf-predelete.XXXXXXXX)" || { printf '[FATAL] mktemp failed\n' >&2; exit 2; }
trap 'rm -rf -- "$SBX"' EXIT INT TERM HUP
mkdir -p "$SBX/bin" "$SBX/runs" "$SBX/tree/apps/web-platform/infra/scripts" "$SBX/tree/scripts/lib" || exit 2
ln -s "$REPO/scripts/lib/bearer-curl.sh" "$SBX/tree/scripts/lib/bearer-curl.sh" || exit 2

NZ=951ce525552201ec6c696b24251abed7
OZ=5af02a2f394e9ba6e0ea23c381a26b67
TOKEN="synthetic-predelete-token-do-not-print"
IDS=()
for n in 1 2 3 4 5 6; do IDS+=("$(printf '%032x' "$((0xa0 + n))")"); done

PASS=0; FAIL=0
ok() { PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
no() { FAIL=$((FAIL + 1)); printf '  FAIL %s\n' "$1"; if [[ -n "${D:-}" && -f "$D/out" ]]; then sed 's/^/    /' "$D/out" | tail -n 8; fi; }
check() { if [[ "$1" -eq 0 ]]; then ok "$2"; else no "$2"; fi; }
_p=$PASS; _f=$FAIL; ok "instrument probe" >/dev/null; no "instrument probe" >/dev/null
if [[ "$PASS" -ne $((_p + 1)) || "$FAIL" -ne $((_f + 1)) ]]; then printf '[FATAL] instrument\n' >&2; exit 2; fi
PASS=$_p; FAIL=$_f

cat >"$SBX/bin/curl" <<'STUB'
#!/usr/bin/env bash
set -uo pipefail
D="${STUB_DIR:?}"
no() { printf 'curl %s\n' "$*" >>"$D/refused.log"; exit 64; }
method=GET; url=""; cfg=0; wfmt=""; prev=""
for a in "$@"; do
  case "$prev" in -X) method="$a" ;; -w) wfmt="$a" ;; --config) [[ "$a" == - ]] && cfg=1 ;; esac
  [[ "$a" == https://* ]] && url="$a"
  prev="$a"
done
printf '%s\n' "$*" >>"$D/argv.log"
[[ "$cfg" -eq 1 && "$wfmt" == '\n%{http_code}' ]] || no "$@"
hdr="$(cat)"
[[ "$hdr" == "header = \"Authorization: Bearer ${STUB_TOKEN:?}\"" ]] || no "(bad bearer)"
[[ "$url" =~ ^https://api\.cloudflare\.com/client/v4/zones/951ce525552201ec6c696b24251abed7/dns_records/([0-9a-f]{32})$ ]] || no "$@"
id="${BASH_REMATCH[1]}"
printf '%s %s\n' "$method" "$id" >>"$D/calls.log"
case "$method" in
  GET)
    if [[ -f "$D/getrc.$id" ]]; then exit "$(cat "$D/getrc.$id")"; fi
    if [[ -f "$D/getcode.$id" ]]; then printf '{"success":false}\n%s' "$(cat "$D/getcode.$id")"; exit 0; fi
    if [[ -f "$D/rec.$id" ]]; then printf '%s\n200' "$(cat "$D/rec.$id")"
    else printf '{"success":false,"errors":[{"code":81044}]}\n404'; fi ;;
  DELETE)
    if [[ -f "$D/delcode.$id" ]]; then printf '{"success":false}\n%s' "$(cat "$D/delcode.$id")"; exit 0; fi
    [[ -f "$D/stuck.$id" ]] || rm -f "$D/rec.$id"
    printf '{"success":true,"result":{"id":"%s"}}\n200' "$id" ;;
  *) no "$@" ;;
esac
STUB
chmod +x "$SBX/bin/curl"

rec() { # <id> <name> <type> <proxied> <content>
  jq -nc --arg id "$1" --arg n "$2" --arg t "$3" --argjson p "$4" --arg c "$5" \
    '{success:true,result:{id:$id,name:$n,type:$t,proxied:$p,content:$c}}'
}
# new_case <label>: the six pinned records, in the live broken shape.
CASE_N=0
new_case() {
  CASE_N=$((CASE_N + 1))
  D="$SBX/runs/$CASE_N-${1//[^A-Za-z0-9_-]/_}"
  mkdir -p "$D" || exit 2
  : >"$D/calls.log"; : >"$D/argv.log"
  local i ips=(104.26.10.163 104.26.11.163 172.67.73.132)
  for i in 0 1 2; do
    rec "${IDS[$i]}" ssh.soleur.ai A true "${ips[$i]}" >"$D/rec.${IDS[$i]}"
    rec "${IDS[$((i + 3))]}" registry.soleur.ai A true "${ips[$i]}" >"$D/rec.${IDS[$((i + 3))]}"
  done
}
# pinned_copy <out-name> [<id>...]: a copy of the script with exactly those ids in its list.
pinned_copy() {
  local out="$SBX/tree/apps/web-platform/infra/scripts/$1" id; shift
  { sed -n '1,/^readonly PINNED_IDS=($/p' "$SUT"
    for id in "$@"; do printf '  %s\n' "$id"; done
    sed -n '/^readonly PINNED_IDS=($/,$p' "$SUT" | sed '1d' | sed -n '/^)$/,$p'
  } >"$out" || exit 2
  printf '%s' "$out"
}
run() { # <script> [args...]; output in $D/out, rc in RC
  local s="$1"; shift
  env PATH="$SBX/bin:$PATH" STUB_DIR="$D" STUB_TOKEN="$TOKEN" CF_API_TOKEN="$TOKEN" bash "$s" "$@" >"$D/out" 2>&1
  RC=$?
}
gets() { grep -c '^GET ' "$D/calls.log"; }
dels() { grep -c '^DELETE ' "$D/calls.log"; }
has() { grep -qF -- "$1" "$D/out"; }
clean() { [[ ! -s "$D/refused.log" ]] && ! grep -qF -- "$TOKEN" "$D/out" "$D/argv.log"; }

PINNED="$(pinned_copy pinned.sh "${IDS[@]}")"
bash -n "$PINNED"; check "$?" "fixture: the pinned copy parses"
[[ "$(sed -n '/^readonly PINNED_IDS=($/,/^)$/p' "$PINNED" | grep -cE '^  [0-9a-f]{32}$')" -eq 6 ]]
check "$?" "fixture: the pinned copy holds exactly the six synthesized ids"

printf '\n[committed list]\n'
n_pins="$(sed -n '/^readonly PINNED_IDS=($/,/^)$/p' "$SUT" | grep -cE '^  [0-9a-f]{32}$')"
if [[ "$n_pins" -eq 0 ]]; then
  for mode in "" --apply --check-pins; do
    new_case "real${mode}"; cp "$SUT" "$SBX/tree/apps/web-platform/infra/scripts/real.sh"
    # shellcheck disable=SC2086 # an empty mode is no argument
    run "$SBX/tree/apps/web-platform/infra/scripts/real.sh" $mode
    r=1; [[ "$RC" -eq 1 ]] && has 'verdict=refuse reason=pins-missing' && [[ ! -s "$D/argv.log" ]] && r=0
    check "$r" "the committed empty list refuses (${mode:-dry-run}) with no API call"
  done
elif [[ "$n_pins" -eq 6 ]]; then
  ok "the committed list holds six ids"
else
  no "the committed list holds $n_pins ids, want 0 or 6"
fi

printf '\n[pin shape] refused before any request\n'
for spec in five dup badhex; do
  case "$spec" in
    five) s="$(pinned_copy p-five.sh "${IDS[@]:0:5}")" ;;
    dup) s="$(pinned_copy p-dup.sh "${IDS[0]}" "${IDS[@]:0:5}")" ;;
    badhex) s="$(pinned_copy p-bad.sh "${IDS[@]:0:5}" "ZZ${IDS[5]:2}")" ;;
  esac
  new_case "pins-$spec"; run "$s" --apply
  r=1; [[ "$RC" -eq 1 ]] && has 'reason=pins-missing' && [[ ! -s "$D/argv.log" ]] && r=0
  check "$r" "a $spec pin list refuses with no API call"
done
new_case check-pins-ok; run "$PINNED" --check-pins
r=1; [[ "$RC" -eq 0 ]] && has 'verdict=pins-ok count=6' && [[ ! -s "$D/argv.log" ]] && r=0
check "$r" "--check-pins on a well-formed list passes with no API call and needs no token"

printf '\n[dry run]\n'
new_case dry; run "$PINNED"
r=1; [[ "$RC" -eq 0 ]] && has 'verdict=dry-run would_delete=6 absent=0' && [[ "$(gets)" -eq 6 && "$(dels)" -eq 0 ]] && clean && r=0
check "$r" "the default is a dry run: six GETs, zero DELETEs"

printf '\n[apply]\n'
new_case apply; run "$PINNED" --apply
r=1; [[ "$RC" -eq 0 ]] && has 'verdict=ok deleted=6 absent=0' && [[ "$(dels)" -eq 6 && "$(gets)" -eq 12 ]] && clean && r=0
check "$r" "--apply deletes all six and re-reads each"
r=1; [[ "$(grep -n '^DELETE ' "$D/calls.log" | head -n1 | cut -d: -f1)" -gt 6 ]] && r=0
check "$r" "every pre-check GET completes before the first DELETE"
new_case rerun; rm -f "$D"/rec.*; run "$PINNED" --apply
r=1; [[ "$RC" -eq 0 ]] && has 'verdict=ok deleted=0 absent=6' && [[ "$(dels)" -eq 0 ]] && clean && r=0
check "$r" "a re-run that finds all six gone exits 0 with no DELETE"
new_case resume; rm -f "$D/rec.${IDS[0]}" "$D/rec.${IDS[1]}" "$D/rec.${IDS[2]}"; run "$PINNED" --apply
r=1; [[ "$RC" -eq 0 ]] && has 'verdict=ok deleted=3 absent=3' && [[ "$(dels)" -eq 3 ]] && clean && r=0
check "$r" "resuming after a partial delete removes only the records still present"

printf '\n[refusal] one mismatch deletes none\n'
mismatch() { # <label> <name> <type> <proxied> <content> <field>
  new_case "mm-$1"; rec "${IDS[5]}" "$2" "$3" "$4" "$5" >"$D/rec.${IDS[5]}"; run "$PINNED" --apply
  local r=1
  [[ "$RC" -eq 1 && "$(dels)" -eq 0 ]] && has "verdict=refuse reason=record-mismatch" && has "id=${IDS[5]} field=$6" && clean && r=0
  check "$r" "sixth record $1 -> verdict=refuse, zero deletes"
}
mismatch cname registry.soleur.ai CNAME true abc.cfargotunnel.com type
mismatch origin-ip registry.soleur.ai A true 135.181.45.178 content
mismatch other-name app.soleur.ai A true 172.67.73.132 name
mismatch unproxied registry.soleur.ai A false 172.67.73.132 proxied
new_case mm-string; jq -c '.result.proxied = "true"' "$D/rec.${IDS[5]}" >"$D/x" && mv "$D/x" "$D/rec.${IDS[5]}"; run "$PINNED" --apply
r=1; [[ "$RC" -eq 1 && "$(dels)" -eq 0 ]] && has 'field=proxied' && r=0
check "$r" "proxied as the string \"true\" is not proxied -> zero deletes"
new_case mm-id; jq -c --arg o "${IDS[0]}" '.result.id = $o' "$D/rec.${IDS[5]}" >"$D/x" && mv "$D/x" "$D/rec.${IDS[5]}"; run "$PINNED" --apply
r=1; [[ "$RC" -eq 1 && "$(dels)" -eq 0 ]] && has 'field=id' && r=0
check "$r" "a response for a different record id -> zero deletes"
new_case mm-resume; rm -f "$D/rec.${IDS[0]}"; rec "${IDS[5]}" registry.soleur.ai CNAME true x.cfargotunnel.com >"$D/rec.${IDS[5]}"; run "$PINNED" --apply
r=1; [[ "$RC" -eq 1 && "$(dels)" -eq 0 ]] && has 'reason=record-mismatch' && r=0
check "$r" "one record gone and another mismatched -> zero deletes"

printf '\n[refusal] a read with no verdict deletes none\n'
for c in 403 429 500; do
  new_case "get-$c"; printf '%s' "$c" >"$D/getcode.${IDS[3]}"; run "$PINNED" --apply
  r=1; [[ "$RC" -eq 1 && "$(dels)" -eq 0 ]] && has 'verdict=refuse reason=record-unreadable' && has "id=${IDS[3]} http=$c" && r=0
  check "$r" "GET answers $c -> record-unreadable, zero deletes"
done
new_case get-transport; printf '28' >"$D/getrc.${IDS[3]}"; run "$PINNED" --apply
r=1; [[ "$RC" -eq 1 && "$(dels)" -eq 0 ]] && has 'reason=record-unreadable' && has 'e=28' && r=0
check "$r" "GET transport failure -> record-unreadable, zero deletes"
new_case get-notjson; printf 'not-json' >"$D/rec.${IDS[3]}"; run "$PINNED" --apply
r=1; [[ "$RC" -eq 1 && "$(dels)" -eq 0 ]] && has 'reason=record-mismatch' && r=0
check "$r" "a 200 whose body is not JSON -> zero deletes"

printf '\n[partial delete]\n'
new_case del-fail; printf '500' >"$D/delcode.${IDS[2]}"; run "$PINNED" --apply
r=1; [[ "$RC" -eq 1 && "$(dels)" -eq 3 ]] && has "verdict=partial deleted=${IDS[0]},${IDS[1]} failed=${IDS[2]} not_attempted=${IDS[3]},${IDS[4]},${IDS[5]}" && clean && r=0
check "$r" "a failed DELETE stops and names exactly what was deleted, failed and not attempted"
new_case del-stuck; : >"$D/stuck.${IDS[4]}"; run "$PINNED" --apply
r=1; [[ "$RC" -eq 1 ]] && has "verdict=refuse reason=still-present id=${IDS[4]}" && r=0
check "$r" "a record still present on the re-read refuses"

printf '\n[inputs]\n'
new_case no-token
env -u CF_API_TOKEN PATH="$SBX/bin:$PATH" STUB_DIR="$D" STUB_TOKEN="$TOKEN" bash "$PINNED" --apply >"$D/out" 2>&1; RC=$?
r=1; [[ "$RC" -eq 1 && ! -s "$D/argv.log" ]] && has 'verdict=refuse reason=no-token' && r=0
check "$r" "no CF_API_TOKEN -> refused with no request"
new_case bad-arg; run "$PINNED" --zone "$OZ"
r=1; [[ "$RC" -eq 2 && ! -s "$D/argv.log" ]] && r=0
check "$r" "an unknown argument (a zone override included) exits 2 with no request"
new_case xtrace
env PATH="$SBX/bin:$PATH" STUB_DIR="$D" STUB_TOKEN="$TOKEN" CF_API_TOKEN="$TOKEN" bash -x "$PINNED" --apply >"$D/out" 2>&1; RC=$?
r=1; [[ "$RC" -eq 78 && ! -s "$D/argv.log" ]] && ! grep -qF -- "$TOKEN" "$D/out" && r=0
check "$r" "xtrace refuses (78) before any request and prints no token"
r=1; grep -qxF "readonly ZONE_ID=\"$NZ\"" "$SUT" && ! grep -qF "$OZ" "$SUT" && r=0
check "$r" "the zone is the NEW-zone literal, and the OLD zone id appears nowhere in the script"

printf '\n[mutants] each guard is load-bearing\n'
mutant() { # <label> <sed-expr> <setup-fn>: the mutant must delete what the pristine copy refused
  local m="$SBX/tree/apps/web-platform/infra/scripts/mut.sh"
  sed -e "$2" "$PINNED" >"$m"
  if cmp -s "$m" "$PINNED"; then no "$1: the mutation did not land"; return; fi
  bash -n "$m" || { no "$1: the mutant does not parse"; return; }
  "$3"; run "$m" --apply
  if [[ "$(dels)" -gt 0 ]]; then ok "$1: RED without it (the mutant deleted)"; else no "$1: the mutant still deleted nothing"; fi
}
set_cname() { new_case mut-cname; rec "${IDS[5]}" registry.soleur.ai CNAME true x.cfargotunnel.com >"$D/rec.${IDS[5]}"; }
set_origin() { new_case mut-origin; rec "${IDS[5]}" registry.soleur.ai A true 135.181.45.178 >"$D/rec.${IDS[5]}"; }
set_403() { new_case mut-403; printf '403' >"$D/getcode.${IDS[3]}"; }
mutant "M-all-or-none" 's/^  \[\[ "\$bad" -eq 0 \]\] || refuse_checked$/  :/' set_cname
mutant "M-content" 's/^    in_set "\${content:-}" "\${ALLOWED_CONTENT\[@\]}" || field="\${field:-content}"$/    :/' set_origin
mutant "M-unreadable" 's/^  \[\[ "\$unread" -eq 0 \]\] || refuse_unread$/  :/' set_403

printf '\ncf-tunnel-host-predelete: %d passed, %d failed\n' "$PASS" "$FAIL"
MIN_CASES=35
if [[ "$((PASS + FAIL))" -lt "$MIN_CASES" ]]; then printf '[VACUITY] only %d cases ran, floor %d\n' "$((PASS + FAIL))" "$MIN_CASES" >&2; exit 1; fi
[[ "$FAIL" -eq 0 ]] || exit 1
