#!/usr/bin/env bash
# Guard 1 (#12008 item 2): host-kernel-cadence-12008.sh decides, per host row of the #12007 reader, whether
# the host is past its kernel patch cadence, and prints exactly one of three fixed lines.
#
# PROPERTY. No input in which any host row is past its cadence prints the all-clear line; no unknown, stale,
# absent, misshapen or unreadable evidence is ever read as within-cadence; an ignored role is never graded; stdout
# is always exactly one of three fixed lines (no class name, no digit, no reader stderr), and the probe never
# exits 0 or 1. The cadence numbers are READ from the probe's constants (the owner edits those four lines), so
# this suite pins the mechanism at whatever value the owner sets, not the values themselves.
#
# The probe reads the reader (plugins/soleur/skills/cve-exposure/scripts/host-state.sh) through a stub that
# this suite synthesizes (HKC_TEST=1 + HKC_READER, honoured only under HKC_TEST). Rows are synthesized
# with placeholder kernel text. No network, no gh, no Doppler, no SSH, no real role output.
#
# MUTANTS (each is applied to a copy of the probe and must turn at least one discriminating case RED):
#   M1 review-needed mapped to exit 2   M2 precedence swapped (unknown beats overdue)
#   M3 reader exit code ignored         M4 a missing role row is skipped, not unknown
#   M5 boundary < instead of <=          M6 marker_state check dropped
#   M7 kernel_state check dropped        M8 unknown rows yield the all-clear
#   M9 reader stderr passed through     M10 extra digit on stdout
#   M11 cannot-establish exits 1         M12 duplicate role rows accepted
#   M13 kernel column shape check dropped  M14 age column shape check dropped
#   M15 field-count floor lowered to 3     M16 kernel_age shape check dropped
#   M17-M19 marker_state / kernel_state / uptime shape checks dropped (graded on an ignored role's row)
# Floors: the case count, the mutant count and the assertion count are reported with printf + exit.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
PROBE="$HERE/host-kernel-cadence-12008.sh"
RUNBOOK="$ROOT/knowledge-base/engineering/operations/runbooks/host-kernel-patch-cadence.md"
REAL_TF="$ROOT/apps/web-platform/infra"

pass=0; fail=0
FAILURES=()
ok()  { pass=$((pass + 1)); printf '[ok] %s\n' "$1"; }
bad() { fail=$((fail + 1)); FAILURES+=("$1"); printf '[FAIL] %s\n' "$1"; }

D="$(mktemp -d -t soleur-run.$$.XXXXXXXX)" || { printf '[FATAL] mktemp failed\n' >&2; exit 1; }
trap 'chmod -R u+rwx "$D" 2>/dev/null; rm -rf "$D"' EXIT
export TMPDIR="$D"

SEC=86400
ALL_ROLES='web-1 web-2 inngest registry git-data'
LINE_REVIEW='host-kernel-cadence: review-needed'
LINE_CLEAR='host-kernel-cadence: nothing-to-report'
LINE_CANNOT='host-kernel-cadence: cannot-establish'

row() { printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" 5 kern-x "$4" 5 src-x; }
sumline() { printf 'SOLEUR_CVE_HOST_STATE hosts=5 fresh=5 stale=0 silent=0 unknown=0\n'; }
# Cadence days are READ from the probe's four constants; a value that is not a plain number fails the suite.
cad() { sed -n "s/^readonly CADENCE_DAYS_$1=\([0-9]\{1,3\}\)\$/\1/p" "$PROBE" | head -1; }
CAD_WEB="$(cad WEB)"; CAD_INNGEST="$(cad INNGEST)"; CAD_REGISTRY="$(cad REGISTRY)"; CAD_GIT_DATA="$(cad GIT_DATA)"
cad_of() { case "$1" in git-data) echo "$CAD_GIT_DATA" ;; inngest) echo "$CAD_INNGEST" ;; registry) echo "$CAD_REGISTRY" ;; *) echo "$CAD_WEB" ;; esac; }
up_w() { echo "$SEC"; }
up_o() { echo $((($(cad_of "$1") + 1) * SEC)); }
mkcase() { # name reader-exit-code ; rows on stdin
  mkdir -p "$D/$1"; cat > "$D/$1/rows"
  printf '#!/usr/bin/env bash\ncat %q\nprintf "LEAKTOKEN-ZZ\\n" >&2\nexit %s\n' "$D/$1/rows" "$2" > "$D/$1/reader.sh"
}
build() { # name rc [role=ms/ks/up ...]  (up: w | o | literal; role=DROP removes the row)
  local n="$1" rc="$2" r spec v ms ks up skip; shift 2
  {
    for r in $ALL_ROLES; do
      ms=fresh; ks=observed; up="$(up_w "$r")"; skip=0
      for spec in "$@"; do
        case "$spec" in
          "$r="*)
            v="${spec#*=}"
            if [ "$v" = DROP ]; then skip=1
            else
              IFS=/ read -r ms ks up <<<"$v"
              case "$up" in w) up="$(up_w "$r")" ;; o) up="$(up_o "$r")" ;; esac
            fi ;;
        esac
      done
      [ "$skip" = 1 ] || row "$r" "$ms" "$ks" "$up"
    done
    sumline
  } | mkcase "$n" "$rc"
}

run_probe() { # probe name [extra env assignments...] -> RC OUT ERR
  local pr="$1" n="$2"; shift 2
  OUT="$(env -i PATH="$PATH" TMPDIR="$D" HKC_TEST=1 HKC_READER="$D/$n/reader.sh" "$@" bash "$pr" 2>"$D/$n/err")"; RC=$?
  ERR="$(cat "$D/$n/err")"
}
expect() { # label probe name want-rc want-line [env...]
  local lbl="$1" pr="$2" n="$3" wrc="$4" wl="$5"; shift 5
  run_probe "$pr" "$n" "$@"
  if [ "$RC" -ne "$wrc" ]; then bad "$lbl -> rc $RC (want $wrc)"; return; fi
  if [ "$OUT" != "$wl" ]; then bad "$lbl -> rc ok but stdout '$OUT' (want '$wl')"; return; fi
  ok "$lbl -> rc $RC"
}

# Instrument self-test: expect() must accept, reject on rc and reject on stdout (reported without the helpers).
build ctl 0
_p=$pass; _f=$fail
expect "ctl-positive" "$PROBE" ctl 2 "$LINE_CLEAR" >/dev/null
expect "ctl-wrong-rc" "$PROBE" ctl 5 "$LINE_CLEAR" >/dev/null
expect "ctl-wrong-line" "$PROBE" ctl 2 "$LINE_REVIEW" >/dev/null
if [ "$pass" -ne $((_p + 1)) ] || [ "$fail" -ne $((_f + 2)) ]; then
  printf '[FATAL] instrument self-test: expect() did not accept, reject on rc and reject on stdout (pass %s->%s fail %s->%s)\n' "$_p" "$pass" "$_f" "$fail" >&2
  exit 1
fi
pass=$_p; fail=$_f; FAILURES=()

CASES=0
case_decision() {
  CASES=$((CASES + 1))
  build all_within 0;                         expect "all five rows within cadence" "$PROBE" all_within 2 "$LINE_CLEAR"
  local r
  for r in $ALL_ROLES; do
    build "over_$r" 0 "$r=fresh/observed/o";  expect "$r alone past cadence" "$PROBE" "over_$r" 5 "$LINE_REVIEW"
  done
  build unk_silent 0 "inngest=silent/unknown/unknown"; expect "a silent row is unknown, never within" "$PROBE" unk_silent 3 "$LINE_CANNOT"
  build unk_stale 0 "registry=stale/stale/w";          expect "a stale row is unknown, never within" "$PROBE" unk_stale 3 "$LINE_CANNOT"
  build unk_ks 0 "git-data=fresh/unknown/w";           expect "kernel_state unknown is unknown" "$PROBE" unk_ks 3 "$LINE_CANNOT"
  build unk_ms 0 "web-2=stale/observed/w";             expect "marker_state stale with an observed kernel is unknown" "$PROBE" unk_ms 3 "$LINE_CANNOT"
  build unk_ks2 0 "web-1=fresh/stale/w";                expect "a stale kernel_state with a fresh marker is unknown" "$PROBE" unk_ks2 3 "$LINE_CANNOT"
  build unk_ms2 0 "inngest=silent/observed/o";         expect "marker_state silent with an observed, overdue-looking uptime is unknown, not overdue" "$PROBE" unk_ms2 3 "$LINE_CANNOT"
}
case_precedence() {
  CASES=$((CASES + 1))
  build prec_a 0 "web-1=fresh/observed/o" "web-2=silent/unknown/unknown"; expect "web-1 overdue, web-2 unknown" "$PROBE" prec_a 5 "$LINE_REVIEW"
  build prec_b 0 "web-1=silent/unknown/unknown" "web-2=fresh/observed/o"; expect "web-1 unknown, web-2 overdue (other order)" "$PROBE" prec_b 5 "$LINE_REVIEW"
}
case_boundary() {
  CASES=$((CASES + 1))
  local r
  for r in web-1 web-2 inngest registry git-data; do
    build "b_eq_$r" 0 "$r=fresh/observed/$(($(cad_of "$r") * SEC))";     expect "$r: uptime exactly at its cadence is within" "$PROBE" "b_eq_$r" 2 "$LINE_CLEAR"
    build "b_plus_$r" 0 "$r=fresh/observed/$(($(cad_of "$r") * SEC + 1))"; expect "$r: one second over its cadence is overdue" "$PROBE" "b_plus_$r" 5 "$LINE_REVIEW"
  done
  [[ "$CAD_WEB$CAD_INNGEST$CAD_REGISTRY$CAD_GIT_DATA" =~ ^[0-9]+$ ]] && [ "$CAD_WEB" -ge 1 ] && [ "$CAD_INNGEST" -ge 1 ] && [ "$CAD_REGISTRY" -ge 1 ] && [ "$CAD_GIT_DATA" -ge 1 ] \
    && ok "the four cadence constants are plain positive day counts" || bad "a cadence constant is missing or not a plain positive number"
  build b_big 0 "web-1=fresh/observed/1234567890123"; expect "a 13-digit uptime is unknown, not within" "$PROBE" b_big 3 "$LINE_CANNOT"
}
case_reader_problems() {
  CASES=$((CASES + 1))
  build rd4 4;  expect "reader exit 4 with otherwise-clean rows" "$PROBE" rd4 3 "$LINE_CANNOT"
  build rd2 2;  expect "reader exit 2 (dark source)" "$PROBE" rd2 3 "$LINE_CANNOT"
  build rd3 3;  expect "reader exit 3 (credentials absent)" "$PROBE" rd3 3 "$LINE_CANNOT"
  build rd4over 4 "web-1=fresh/observed/o"; expect "reader exit 4 never hides an overdue row from the all-clear" "$PROBE" rd4over 3 "$LINE_CANNOT"
  : | mkcase zero 0;                     expect "zero rows, reader exit 0" "$PROBE" zero 3 "$LINE_CANNOT"
  sumline | mkcase sumonly 0;            expect "only the summary line" "$PROBE" sumonly 3 "$LINE_CANNOT"
  mkdir -p "$D/noreader"; expect "reader script missing" "$PROBE" noreader 3 "$LINE_CANNOT"
}
case_census() {
  CASES=$((CASES + 1))
  build extra_role 0; row newrole fresh observed 5 >> "$D/extra_role/rows"
  expect "a role row the script has never seen is unknown, not ignored" "$PROBE" extra_role 3 "$LINE_CANNOT"
  build unm 0; row unmapped fresh observed 5 >> "$D/unm/rows"
  expect "an unmapped row is unknown" "$PROBE" unm 3 "$LINE_CANNOT"
  build drop_row 0 "inngest=DROP"; expect "a required role row missing" "$PROBE" drop_row 3 "$LINE_CANNOT"
  build dup 0; row web-1 fresh observed 5 >> "$D/dup/rows"
  expect "a duplicate role row" "$PROBE" dup 3 "$LINE_CANNOT"
  build nan 0 "web-1=fresh/observed/12abc"; expect "non-numeric uptime" "$PROBE" nan 3 "$LINE_CANNOT"
  build nan2 0 "web-1=fresh/observed/unknown"; expect "uptime unknown" "$PROBE" nan2 3 "$LINE_CANNOT"
  build neg 0 "web-1=fresh/observed/-5"; expect "negative uptime" "$PROBE" neg 3 "$LINE_CANNOT"
  mkcase short 0 < <(for r in web-1 web-2 inngest registry; do printf '%s\tfresh\tobserved\t5\n' "$r"; done; row git-data fresh observed "$(up_w git-data)")
  expect "rows with too few fields are unknown" "$PROBE" short 3 "$LINE_CANNOT"
  build shifted 0 "web-1=DROP"; printf 'web-1\tinserted\tfresh\tobserved\t5\tkern-x\t%s\t5\tsrc-x\n' "$(up_w web-1)" >> "$D/shifted/rows"
  expect "a column inserted before the fixed columns makes the row a problem, not a shifted reading" "$PROBE" shifted 3 "$LINE_CANNOT"
  local a b c e f g
  local sh_defects=("bogus|observed|5|kern-x|7|5" "fresh|bogus|5|kern-x|7|5" "fresh|observed|x5|kern-x|7|5" "fresh|observed|5|bad kern!|7|5" "fresh|observed|5|kern-x|7x|5" "fresh|observed|5|kern-x|7|x") d i=2
  for d in "${sh_defects[@]}"; do
    build "sh$i" 0 "web-1=DROP"
    IFS='|' read -r a b c e f g <<<"$d"
    printf 'web-1\t%s\t%s\t%s\t%s\t%s\t%s\tsrc-x\n' "$a" "$b" "$c" "$e" "$f" "$g" >> "$D/sh$i/rows"
    expect "single-defect row $i (one fixed column breaks its shape) is a problem, not a reading" "$PROBE" "sh$i" 3 "$LINE_CANNOT"
    i=$((i + 1))
  done
  build sh_nf 0 "web-1=DROP"; printf 'web-1\tfresh\tobserved\t5\tkern-x\t7\t5\n' >> "$D/sh_nf/rows"
  expect "a row one field short (dropped column) is a problem" "$PROBE" sh_nf 3 "$LINE_CANNOT"
  build junk 0; printf 'garbage without tabs\n' >> "$D/junk/rows"
  expect "one malformed line is a problem even when every required role is present" "$PROBE" junk 3 "$LINE_CANNOT"
  local k
  for k in 2 3 6; do
    build "ign_c$k" 0
    case "$k" in
      2) printf 'grok-dogfood\tbogus\tunknown\tunknown\tkern-x\tunknown\tunknown\tnone\n' ;;
      3) printf 'grok-dogfood\tunknown\tbogus\tunknown\tkern-x\tunknown\tunknown\tnone\n' ;;
      6) printf 'grok-dogfood\tunknown\tunknown\tunknown\tkern-x\tbad\tunknown\tnone\n' ;;
    esac >> "$D/ign_c$k/rows"
    expect "an ignored role's row with a malformed column $k is still a problem (the shape gate runs before the ignore)" "$PROBE" "ign_c$k" 3 "$LINE_CANNOT"
  done
  build ign3 0; row grok fresh observed 5 >> "$D/ign3/rows"
  expect "a near-miss of an ignored role (grok) is an unknown role, not ignored" "$PROBE" ign3 3 "$LINE_CANNOT"
  build ign4 0; row dogfood fresh observed 5 >> "$D/ign4/rows"
  expect "a near-miss of an ignored role (dogfood) is an unknown role, not ignored" "$PROBE" ign4 3 "$LINE_CANNOT"
  build ign 0; printf 'grok-dogfood\tunknown\tunknown\tunknown\tunknown\tunknown\tunknown\tnone\n' >> "$D/ign/rows"
  expect "the reader's default-off dogfood row is skipped, so the all-clear stays reachable against the real row set" "$PROBE" ign 2 "$LINE_CLEAR"
  build ign2 0; row grok-dogfood fresh observed "$((900 * SEC))" >> "$D/ign2/rows"
  expect "an ignored role is never graded, even with an old uptime" "$PROBE" ign2 2 "$LINE_CLEAR"
}
case_non_canonical() {
  CASES=$((CASES + 1))
  { sumline
    row git-data fresh observed "$(up_w git-data)"
    row registry fresh observed "$(up_w registry)"
    printf '%s\textra-field\tanother\n' "$(row inngest fresh observed "$(up_w inngest)")"
    row web-2 fresh observed "$(up_w web-2)"
    printf '\n'
    row web-1 fresh observed "$(up_w web-1)"
    printf '\n'
  } | mkcase noncanon 0
  expect "reordered rows, the summary first, extra trailing fields and a blank line still resolve" "$PROBE" noncanon 2 "$LINE_CLEAR"
}
case_output_contract() {
  CASES=$((CASES + 1))
  local n bad_out=""
  for n in all_within over_web-1 over_git-data unk_silent prec_a b_plus_web-1 rd4 zero extra_role dup noncanon; do
    run_probe "$PROBE" "$n"
    case "$OUT" in "$LINE_REVIEW"|"$LINE_CLEAR"|"$LINE_CANNOT") : ;; *) bad_out="$bad_out $n" ;; esac
    [ "$(printf '%s\n' "$OUT" | wc -l)" -eq 1 ] || bad_out="$bad_out $n(lines)"
    grep -qE '[0-9]' <<<"$OUT" && bad_out="$bad_out $n(digit)"
    grep -qE 'web|inngest|registry|git' <<<"$OUT" && bad_out="$bad_out $n(class)"
    grep -q 'LEAKTOKEN' <<<"$OUT$ERR" && bad_out="$bad_out $n(leak)"
    [ -z "$ERR" ] || bad_out="$bad_out $n(stderr)"
    case "$RC" in 2|3|5) : ;; *) bad_out="$bad_out $n(rc=$RC)" ;; esac
  done
  [ -z "$bad_out" ] && ok "stdout is exactly one fixed line, no digit or class name, nothing on stderr, no reader token, rc in {2,3,5}" || bad "output contract broken for:$bad_out"
}
case_reader_contract() {
  CASES=$((CASES + 1))
  local reader="$ROOT/plugins/soleur/skills/cve-exposure/scripts/host-state.sh" roles have r missing="" extra="" hdr want
  roles="$(awk -v q="'" '/^readonly ROLE_TABLE=/ { inb = 1; sub(/^readonly ROLE_TABLE=./, "") } inb { l = $0; e = (substr(l, length(l), 1) == q); if (e) l = substr(l, 1, length(l) - 1); split(l, a, "|"); print a[1]; if (e) exit }' "$reader")"
  have="$(sed -n -e "s/^REQUIRED_ROLES='\(.*\)'\$/\1/p" -e "s/^IGNORED_ROLES='\(.*\)'\$/\1/p" "$PROBE" | tr '\n' ' ')"
  [ "$(printf '%s\n' "$roles" | grep -c .)" -ge 5 ] && ok "contract: the reader's role table was read (at least five roles)" || bad "contract: the reader's role table was not read"
  for r in $roles; do case " $have " in *" $r "*) : ;; *) missing="$missing $r" ;; esac; done
  [ -z "$missing" ] && ok "contract: every role the reader prints is required or ignored by the probe" || bad "contract: reader roles the probe does not know:$missing"
  for r in $have; do case " $(printf '%s ' $roles) " in *" $r "*) : ;; *) extra="$extra $r" ;; esac; done
  [ -z "$extra" ] && ok "contract: every role the probe requires or ignores exists in the reader" || bad "contract: probe roles absent from the reader:$extra"
  hdr="$(sed -n 's/^#   host_role /host_role /p' "$reader" | head -1)"
  want="host_role marker_state kernel_state age_hours kernel uptime_s kernel_age_hours source_marker"
  case "$hdr" in "$want"*) ok "contract: the reader's documented column order starts with the eight columns the probe indexes" ;; *) bad "contract: reader column header is '$hdr' (probe indexes: $want)" ;; esac
  # the header is a comment; the row is what the reader's printf emits, so pin that argument list too
  grep -qF "printf '%s\\t%s\\t%s\\t%s\\t%s\\t%s\\t%s\\t%s\\n' \"\$role\" \"\$ms\" \"\$ks\" \"\$age\" \"\$kernel\" \"\$up\" \"\$kage\" \"\$src\"" "$reader" \
    && ok "contract: the reader's row printf emits the eight columns in the documented order" || bad "contract: the reader's row printf no longer matches the documented column order"
  # the reader's web roles are the Terraform web_hosts keys; a new web host must reach this probe's role lists
  local tfkeys rdkeys
  tfkeys="$(awk '/^variable "web_hosts"/ { b = 1 } b && /^}/ { b = 0 } b' "$REAL_TF/variables.tf" | grep -oE '"?web-[0-9]+"?[[:space:]]*=[[:space:]]*\{' | grep -oE 'web-[0-9]+' | sort -u | tr '\n' ' ')"
  rdkeys="$(printf '%s\n' "$roles" | grep -E '^web-[0-9]+$' | sort -u | tr '\n' ' ')"
  [ -n "$tfkeys" ] && [ "$tfkeys" = "$rdkeys" ] && ok "contract: the reader's web roles equal the Terraform web_hosts keys" || bad "contract: web roles differ (terraform: '$tfkeys' reader: '$rdkeys')"
}
case_units() { # the two decision functions, extracted from the probe and driven directly
  CASES=$((CASES + 1))
  local fn
  fn="$(sed -n -e '/^readonly CADENCE_DAYS_/p' -e '/^cadence_days()/,/^}/p' -e '/^classify_row()/,/^}/p' -e '/^aggregate()/,/^}/p' "$PROBE")"
  [ "$(grep -c '^aggregate()' <<<"$fn")" -eq 1 ] && [ "$(grep -c '^classify_row()' <<<"$fn")" -eq 1 ] && ok "units: both decision functions were extracted from the probe" || bad "units: the decision functions were not found in the probe"
  [ "$( (eval "$fn"; aggregate within within) )" = nothing-to-report ] && ok "units: all within is the all-clear" || bad "units: all within is not the all-clear"
  [ "$( (eval "$fn"; aggregate) )" = cannot-establish ] && ok "units: no classes at all is never the all-clear" || bad "units: an empty class list produced the all-clear"
  [ "$( (eval "$fn"; aggregate within '') )" = cannot-establish ] && ok "units: an empty class string is never the all-clear" || bad "units: an empty class string produced the all-clear"
  [ "$( (eval "$fn"; aggregate within garbage) )" = cannot-establish ] && ok "units: an unrecognised class string is never the all-clear" || bad "units: an unrecognised class produced the all-clear"
  [ "$( (eval "$fn"; aggregate unknown overdue within) )" = review-needed ] && ok "units: overdue beats unknown" || bad "units: overdue did not beat unknown"
  [ "$( (eval "$fn"; classify_row newrole fresh observed 5) )" = unknown ] && ok "units: a role with no cadence arm is unknown, never within" || bad "units: a role without a cadence arm was graded"
  grep -qE '^out="\$\(timeout -k [0-9]+ [0-9]+ bash "\$READER" 2>/dev/null\)"; rc=\$\?$' "$PROBE" && ok "units: the reader call is bounded by a timeout" || bad "units: the reader call has no timeout"
}
case_override_gate() {
  CASES=$((CASES + 1))
  local shim="$D/shim"; mkdir -p "$shim" "$D/ovr"
  printf '#!/bin/sh\nexit 1\n' > "$shim/curl"; chmod +x "$shim/curl"
  build ovr 0
  # HKC_TEST unset: the override must be ignored. The real reader is then reached; a curl shim makes it
  # fail closed at once (offline-safe), so the all-clear can never be produced through the override.
  OUT="$(env -i PATH="$shim:$PATH" TMPDIR="$D" HKC_READER="$D/ovr/reader.sh" bash "$PROBE" 2>/dev/null)"; RC=$?
  [ "$OUT" = "$LINE_CANNOT" ] && [ "$RC" -eq 3 ] && ok "HKC_READER is ignored without HKC_TEST (the stub's all-clear is not reachable)" || bad "override honoured without HKC_TEST: rc=$RC out='$OUT'"
  OUT="$(env -i PATH="$shim:$PATH" TMPDIR="$D" HKC_TEST=0 HKC_READER="$D/ovr/reader.sh" bash "$PROBE" 2>/dev/null)"; RC=$?
  [ "$OUT" = "$LINE_CANNOT" ] && [ "$RC" -eq 3 ] && ok "HKC_TEST=0 does not open the override" || bad "override honoured under HKC_TEST=0: rc=$RC out='$OUT'"
}
case_invocation() {
  CASES=$((CASES + 1))
  build inv 0
  OUT="$(env -i PATH="$PATH" TMPDIR="$D" HKC_TEST=1 HKC_READER="$D/inv/reader.sh" bash "$PROBE" extra-arg 2>/dev/null)"; RC=$?
  [ "$OUT" = "$LINE_CANNOT" ] && [ "$RC" -eq 3 ] && ok "an argument is refused with the fixed cannot-establish line" || bad "argument not refused: rc=$RC out='$OUT'"
  OUT="$(env -i PATH="$PATH" TMPDIR="$D" HKC_TEST=1 HKC_READER="$D/inv/reader.sh" bash -x "$PROBE" 2>/dev/null)"; RC=$?
  [ "$RC" -eq 78 ] && ok "xtrace refusal exits 78" || bad "xtrace run exited $RC (want 78)"
  local m
  m="$(git -C "$HERE" ls-files -s -- host-kernel-cadence-12008.sh 2>/dev/null | awk '{print $1}')"
  if [ -z "$m" ]; then [ -x "$PROBE" ] && ok "probe is executable (untracked checkout)" || bad "probe is not executable"
  else [ "$m" = 100755 ] && ok "probe is committed with mode 100755" || bad "probe mode is $m, want 100755"; fi
  [ "$(grep -c '^readonly CADENCE_DAYS_' "$PROBE")" -eq 4 ] && ok "four cadence constants, one per class" || bad "cadence constant count is not four"
  grep -q '^# soleur:followthrough-stub v1' "$PROBE" && ok "carries the follow-through stub marker" || bad "stub marker missing"
}
case_env_i() {
  CASES=$((CASES + 1))
  build envi 0 "web-1=fresh/observed/o"
  OUT="$(env -i PATH=/usr/bin:/bin HKC_TEST=1 HKC_READER="$D/envi/reader.sh" /usr/bin/env bash "$PROBE" 2>/dev/null)"; RC=$?
  [ "$OUT" = "$LINE_REVIEW" ] && [ "$RC" -eq 5 ] && ok "runs under the sweeper's environment (no HOME, CI, HEADLESS_MODE or TMPDIR)" || bad "env -i run: rc=$RC out='$OUT'"
}

# ---- hygiene: durable new files carry no CVE id, kernel version, address, host name or hold marker -----
server_names() {
  local f
  for f in "$REAL_TF"/*.tf; do
    awk '/^resource "hcloud_server"/ { b = 1 } b && /^[[:space:]]*name[[:space:]]*=[[:space:]]*"/ { match($0, /"[^"]*"/); v = substr($0, RSTART + 1, RLENGTH - 2); if (v !~ /\$/) print v } /^}/ { b = 0 }' "$f"
  done | sort -u
}
VERDICT_RE='not'' affected|not'' exposed|is'' patched|are'' patched'
SERVER_NAMES=""
hygiene() { # file... -> prints one token per violation class found
  local f names n
  [ -n "$SERVER_NAMES" ] || SERVER_NAMES="$(server_names)"
  names="$SERVER_NAMES"
  for f in "$@"; do
    grep -qE 'CVE-[0-9]{4}-[0-9]{4,}' "$f" && echo "cve-id:${f##*/}"
    grep -qE '[0-9]+\.[0-9]+\.[0-9]+-[0-9]+(-generic)?' "$f" && echo "kernel-version:${f##*/}"
    grep -qE '([0-9]{1,3}\.){3}[0-9]{1,3}' "$f" && echo "ipv4:${f##*/}"
    grep -qiE "$VERDICT_RE" "$f" && echo "verdict-words:${f##*/}"
    while IFS= read -r n; do
      [ -n "$n" ] || continue
      grep -qF -- "$n" "$f" && echo "host-name:${f##*/}"
    done <<<"$names"
  done
}
case_hygiene() {
  CASES=$((CASES + 1))
  local nn out f
  SERVER_NAMES="$(server_names)"
  nn="$(grep -c . <<<"$SERVER_NAMES")"
  [ "$nn" -ge 3 ] && ok "hygiene: the scan read at least three server name values from the Terraform directory (liveness)" || bad "hygiene: fewer than three server names read ($nn)"
  # positive controls: each pattern class must fire on a synthesized offender
  mkdir -p "$D/hyg"
  printf 'see CVE-%s-%s here\n' 2099 123456 > "$D/hyg/cve.txt"
  printf 'running %s.%s.%s-%s-generic\n' 9 9 9 99 > "$D/hyg/kern.txt"
  printf 'addr %s.%s.%s.%s\n' 10 0 0 1 > "$D/hyg/ip.txt"
  printf 'the fleet is %s %s\n' 'not' 'affected' > "$D/hyg/verdict.txt"
  out="$(hygiene "$D/hyg/cve.txt" "$D/hyg/kern.txt" "$D/hyg/ip.txt" "$D/hyg/verdict.txt")"
  for f in cve-id kernel-version ipv4 verdict-words; do
    grep -q "^$f:" <<<"$out" && ok "hygiene control: $f fires on a synthesized offender" || bad "hygiene control: $f did not fire"
  done
  local first; first="$(head -1 <<<"$SERVER_NAMES")"
  printf 'host %s\n' "$first" > "$D/hyg/name.txt"
  grep -q '^host-name:' <<<"$(hygiene "$D/hyg/name.txt")" && ok "hygiene control: a real server name fires" || bad "hygiene control: a server name did not fire"
  [ -f "$RUNBOOK" ] && ok "the runbook exists" || bad "the runbook is missing: $RUNBOOK"
  local l
  for l in "$LINE_REVIEW" "$LINE_CLEAR" "$LINE_CANNOT"; do
    grep -qF -- "$l" "$RUNBOOK" 2>/dev/null && ok "the runbook documents the public line '${l#host-kernel-cadence: }'" || bad "the runbook does not document the public line '$l'"
  done
  local files=("$PROBE" "$HERE/host-kernel-cadence-12008.test.sh" "$ROOT/scripts/host-tcp-exposure.test.sh")
  [ -f "$RUNBOOK" ] && files+=("$RUNBOOK")
  out="$(hygiene "${files[@]}")"
  [ -z "$out" ] && ok "hygiene: no CVE id, kernel version, address, server name or verdict words in the durable new files" || bad "hygiene violations: $(tr '\n' ' ' <<<"$out")"
  if [ -f "$RUNBOOK" ]; then
    grep -qiE '^[[:space:]]*(-[[:space:]]*)?(hold|gate|operator-reserved):' "$RUNBOOK" \
      && bad "the runbook has a line starting with a hold or gate marker" || ok "the runbook has no line starting with a hold or gate marker"
  fi
}

if [ ! -f "$PROBE" ]; then
  bad "probe missing: $PROBE"
else
  case_decision; case_precedence; case_boundary; case_reader_problems; case_census; case_non_canonical
  case_output_contract; case_reader_contract; case_units; case_override_gate; case_invocation; case_env_i
fi
case_hygiene

# ---- mutants: each is a copy of the probe with one edit; the discriminating cases must go RED ---------
grade() { # probe-copy -> prints KILLED:<case> for the first discriminating case that misbehaves, else ALIVE
  local mp="$1" killed="" spec n wrc
  for spec in "all_within:2" "over_web-1:5" "over_git-data:5" "unk_silent:3" "unk_stale:3" "unk_ks:3" "unk_ks2:3" "unk_ms:3" "unk_ms2:3" "prec_a:5" "prec_b:5" \
              "b_eq_web-1:2" "b_plus_web-1:5" "rd4:3" "zero:3" "extra_role:3" "drop_row:3" "dup:3" "nan:3" \
              "sh2:3" "sh3:3" "sh4:3" "sh5:3" "sh6:3" "sh7:3" "sh_nf:3" "junk:3" "ign3:3" "ign_c2:3" "ign_c3:3" "ign_c6:3" "b_big:3"; do
    n="${spec%%:*}"; wrc="${spec##*:}"
    run_probe "$mp" "$n"
    [ "$RC" -eq "$wrc" ] || killed="$n"
    case "$RC" in 2|3|5) : ;; *) killed="$n" ;; esac
    case "$OUT" in "$LINE_REVIEW"|"$LINE_CLEAR"|"$LINE_CANNOT") : ;; *) killed="$n" ;; esac
    [ -z "$ERR" ] || killed="$n"
    [ -z "$killed" ] || break
  done
  if [ -n "$killed" ]; then printf 'KILLED:%s' "$killed"; else printf 'ALIVE'; fi
}
mutate() { # name sed-expression
  local name="$1" expr="$2" mp="$D/mut-$1.sh" res
  MUTANTS=$((MUTANTS + 1))
  cp "$PROBE" "$mp"; sed -E -i "$expr" "$mp"
  if cmp -s "$PROBE" "$mp"; then bad "mutation $name did not land"; return; fi
  if ! bash -n "$mp" 2>/dev/null; then bad "mutation $name does not parse (a syntax error is not a kill)"; return; fi
  res="$(grade "$mp")"
  case "$res" in KILLED:*) ok "mutant $name is killed by ${res#KILLED:}" ;; *) bad "mutant $name SURVIVED" ;; esac
}

MUTANTS=0
if [ -f "$PROBE" ]; then
  cp "$PROBE" "$D/mut-ctrl.sh"
  [ "$(grade "$D/mut-ctrl.sh")" = ALIVE ] && ok "grader control: the unmutated probe survives the mutant loop" || bad "grader control: the unmutated probe was graded killed"
  cp "$PROBE" "$D/mut-ctrl99.sh"; sed -E -i 's/^([[:space:]]*)exit "\$rc"$/\1exit 99/' "$D/mut-ctrl99.sh"
  case "$(grade "$D/mut-ctrl99.sh")" in KILLED:*) ok "grader control: a probe exiting 99 is graded killed" ;; *) bad "grader control: a probe exiting 99 was not graded killed" ;; esac
  mutate M1  's/review-needed\) rc=5/review-needed) rc=2/'
  mutate M2  's/= overdue \]/= __X__ ]/; s/= unknown \]/= overdue ]/; s/= __X__ \]/= unknown ]/'
  mutate M3  's/^\[ "\$rc" -eq 0 \] \|\| emit cannot-establish$/true/'
  mutate M4  's/^(.*)\[ -n "\$\{SEEN\[\$r\]:-\}" \] \|\| classes\+=\("unknown"\)/\1true/'
  mutate M5  's/-le \$\(\(days \* 86400\)\)/-lt $((days * 86400))/'
  mutate M6  's/\[ "\$ms" = fresh \] && //'
  mutate M7  's/ && \[ "\$ks" = observed \]//'
  mutate M8  's/(!= within \].*)echo cannot-establish/\1echo nothing-to-report/'
  mutate M9  's/bash "\$READER" 2>\/dev\/null/bash "$READER" 2>\&2/'
  mutate M10 "s/host-kernel-cadence: %s\\\\n/host-kernel-cadence: %s 1\\\\n/"
  mutate M11 's/cannot-establish\) rc=3/cannot-establish) rc=1/'
  mutate M12 's/^(.*)\[ -z "\$\{SEEN\[\$role\]:-\}" \] \|\| problem=1/\1true/'
  mutate M13 's# && \$5 ~ /\^\[A-Za-z0-9\._\+~:-\]\+\$/##'
  mutate M14 's# && \$4 ~ /\^\(\[0-9\]\+\|unknown\)\$/##'
  mutate M15 's/NF >= 8/NF >= 3/'
  mutate M16 's# && \$7 ~ /\^\(\[0-9\]\+\|unknown\)\$/##'
  mutate M17 's# && \$2 ~ /\^\(fresh\|stale\|silent\|unknown\)\$/##'
  mutate M18 's# && \$3 ~ /\^\(observed\|stale\|unknown\)\$/##'
  mutate M19 's# && \$6 ~ /\^\(\[0-9\]\+\|unknown\)\$/##'
fi

# ---- anti-vacuity floors (reported with printf + exit, not through the helpers) ------------------
EXPECTED_CASES=13
if [ "$CASES" -lt "$EXPECTED_CASES" ]; then
  printf '[FATAL] case-count floor: ran %s cases, want >= %s (a case was deleted or the list was emptied)\n' "$CASES" "$EXPECTED_CASES" >&2
  exit 1
fi
EXPECTED_MUTANTS=19
if [ "$MUTANTS" -lt "$EXPECTED_MUTANTS" ]; then
  printf '[FATAL] mutant-count floor: ran %s mutants, want >= %s\n' "$MUTANTS" "$EXPECTED_MUTANTS" >&2
  exit 1
fi
MIN_ASSERTIONS=114
if [ "$pass" -lt "$MIN_ASSERTIONS" ]; then
  printf '[FATAL] assertion floor: %s passed, want >= %s (an assertion was deleted)\n' "$pass" "$MIN_ASSERTIONS" >&2
  exit 1
fi

printf '\n%s passed, %s failed (%s cases, %s mutants)\n' "$pass" "$fail" "$CASES" "$MUTANTS"
if [ "$fail" -gt 0 ] || [ "${#FAILURES[@]}" -gt 0 ]; then
  printf 'FAILURES:\n'; printf '  - %s\n' "${FAILURES[@]}"
  exit 1
fi
exit 0
