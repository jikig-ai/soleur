#!/usr/bin/env bash
# Battery for scripts/lint-hcloud-token-readonly-no-fallback.sh (#10664, ADR-241 D4; CTO R1/R8).
#
# The scanner is the guard (live scan only). This suite proves the scanner can fail and cannot
# over-fire: an instrument-control pair first (abort on failure), then a table-driven mutation matrix
# over a SYNTHETIC fixture tree, then the two real-tree rows:
#   L1  the scanner against the REAL tree with no override: findings=0, exactly one allowlisted read.
#       Without this row nothing guards the live tree (the fixture rows prove only the detector).
#   L2  a copy of the live population (the files the scanner scanned that mention the Doppler CLI,
#       via HCLOUD_SCAN_ROOT on a `git init` copy) with the pre-change fallback line re-inserted into
#       scripts/cutover-inngest.sh: RED with an F-literal finding. The real shape and the real floors.
# Matrix rows (see the plan's Guard Contract): M1 M2 M3 M4 M5 M6 M7 M8 M9 M10 M11, controls C1 C2 C3.
#
# Fixture hygiene: every fixture lives under ONE mktemp -d; the single EXIT trap is installed BEFORE any
# helper is sourced; every git call runs under git_fixture_env (all GIT_* location variables dropped, the
# identity and config pinned). Fixture rows run under `env -u GITHUB_ACTIONS -u GITHUB_EVENT_NAME` and
# pin HCLOUD_SCAN_TODAY to a date well before the expiry, so no verdict depends on the wall clock; the
# live rows (L1, L2) run with no clock override.
# Anti-vacuity floors are enforced with printf+exit, never through the fail() counter they would audit.
# shellcheck disable=SC2016,SC2329
set -uo pipefail

T=""
cleanup() { if [ -n "$T" ]; then rm -rf -- "$T"; fi; }
trap cleanup EXIT
T="$(mktemp -d "${TMPDIR:-/tmp}/hcloud-ro-scan.XXXXXX")" || { printf 'FAIL SETUP: mktemp -d failed\n' >&2; exit 2; }

SUITE_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd -P "$SUITE_DIR/../.." && pwd -P)"
# shellcheck source=/dev/null
source "$REPO_ROOT/plugins/soleur/test/test-helpers.sh"
set +e
assert_fixture_dir "$T"
SCANNER="$REPO_ROOT/scripts/lint-hcloud-token-readonly-no-fallback.sh"
[ -f "$SCANNER" ] || { printf 'FAIL SETUP: scanner missing: %s\n' "$SCANNER" >&2; exit 2; }

FX="$T/fx"
mkdir -p "$FX" "$T/out" || { printf 'FAIL SETUP: mkdir\n' >&2; exit 2; }
assert_fixture_dir "$FX"
git_fixture_env "$FX" || { printf 'FAIL SETUP: git_fixture_env failed\n' >&2; exit 2; }

PASSES=0
FAILS=0
CASES=0
ROWS=0
pass() { PASSES=$((PASSES + 1)); CASES=$((CASES + 1)); printf '[ok] %s\n' "$1"; }
fail() { FAILS=$((FAILS + 1)); CASES=$((CASES + 1)); printf '[FAIL] %s\n' "$1"; [ -n "${2-}" ] && printf '       %s\n' "$2"; }
abort_setup() { printf 'FAIL SETUP (instrument control): %s\n' "$1" >&2; [ -n "${2-}" ] && printf '%s\n' "$2" >&2; exit 2; }

BARE="HCLOUD_TOKEN"
RO="HCLOUD_TOKEN_READONLY"
DSG="doppler secrets get"
TODAY_PIN="2026-10-23"

# scan_in <dir> <outfile> [ENV=VAL ...] -- [scanner args ...]; sets SCAN_RC; stdout+stderr land in <outfile>
scan_in() {
  local d="$1" out="$2"
  shift 2
  local -a envs=()
  while [ "$#" -gt 0 ] && [ "$1" != "--" ]; do envs+=("$1"); shift; done
  [ "$#" -gt 0 ] && shift
  env -u GITHUB_ACTIONS -u GITHUB_EVENT_NAME -u HCLOUD_SCAN_ROOT -u HCLOUD_SCAN_TODAY \
    HCLOUD_SCAN_ROOT="$d" ${envs[@]+"${envs[@]}"} bash "$SCANNER" "$@" > "$out" 2>&1
  SCAN_RC=$?
}
ctr() { sed -n 's/^counters: //p' "$1" | tr ' ' '\n' | sed -n "s/^$2=//p"; }
tree_md5() {
  assert_fixture_dir "$1"
  (cd "$1" && find . -path ./.git -prune -o -type f -print0 | LC_ALL=C sort -z | xargs -0 md5sum | md5sum | cut -d' ' -f1)
}
diff_lines() { diff -rN -x .git "$1" "$2" | awk '/^[<>]/ { n++ } END { print n + 0 }'; }
diff_paths() { diff -rqN -x .git "$1" "$2" | awk 'END { print NR + 0 }'; }

# expect_all <outfile> <~-separated expectations>: prints the failures (empty = all met); a leading ! = must be absent
expect_all() {
  local part
  while IFS= read -r part; do
    [ -n "$part" ] || continue
    if [ "${part#!}" != "$part" ]; then
      if grep -qF -- "${part#!}" "$1"; then printf '; unexpected: %s' "${part#!}"; fi
    elif ! grep -qF -- "$part" "$1"; then printf '; missing: %s' "$part"; fi
  done < <(printf '%s' "$2" | tr '~' '\n')
}

# ---- the pristine fixture ----------------------------------------------------------------------------
PRISTINE="$FX/pristine"
build_pristine() {
  local d="$1" i
  assert_fixture_dir "$d"
  mkdir -p "$d/scripts" "$d/tests/scripts" || return 1
  git init -q "$d" || return 1
  {
    printf '#!/usr/bin/env bash\n'
    printf '# the compliant read-only reader: Tier A only\n'
    printf 'tok="$(%s %s -p soleur -c prd_terraform --plain 2>/dev/null || true)"\n' "$DSG" "$RO"
  } > "$d/scripts/reader.sh"
  {
    printf '#!/usr/bin/env bash\n'
    printf 'case "$1" in\n'
    printf '  backup)\n'
    printf '    %s=$(%s %s --plain)\n' "$BARE" "$DSG" "$BARE"
    printf '    ;;\n'
    printf 'esac\n'
  } > "$d/scripts/cutover-inngest.sh"
  {
    printf '#!/usr/bin/env bash\n'
    printf '# an unrelated channel-key read in a file that names only %s elsewhere\n' "$RO"
    printf 'CK=INNGEST_CHANNEL_KEY\n'
    printf 'APP_CK=$(%s "$CK" --plain 2>/dev/null || true)\n' "$DSG"
  } > "$d/scripts/ck.sh"
  {
    printf '#!/usr/bin/env bash\n'
    for i in $(seq 1 20); do
      printf 'v%s=$(%s PAD_NAME_%s -p soleur -c prd --plain)\n' "$i" "$DSG" "$i"
    done
  } > "$d/scripts/pad.sh"
  printf '#!/usr/bin/env bash\n%s %s --plain\n' "$DSG" "$BARE" > "$d/tests/scripts/test-bare.sh"
  git -C "$d" add -A || return 1
}
build_pristine "$PRISTINE" || abort_setup "cannot build the pristine fixture"
PRISTINE_SCRIPT_LINES="$(cat "$PRISTINE"/scripts/* | wc -l | tr -d ' ')"

# ---- instrument controls (abort on failure) ----------------------------------------------------------
c0="$T/out/control-pristine"
scan_in "$PRISTINE" "$c0" "HCLOUD_SCAN_TODAY=$TODAY_PIN" --
if [ "$SCAN_RC" -ne 0 ] \
  || [ "$(ctr "$c0" inspected)" != 23 ] || [ "$(ctr "$c0" files)" != 4 ] || [ "$(ctr "$c0" skipped_test)" != 1 ] \
  || [ "$(ctr "$c0" skipped_comment)" != 0 ] || [ "$(ctr "$c0" operands)" != 23 ] || [ "$(ctr "$c0" nonliteral)" != 1 ] \
  || ! grep -qxF 'live: findings=0 allowlisted=1' "$c0" \
  || ! grep -qF "HCLOUD_SCAN_TODAY override active: $TODAY_PIN" "$c0"; then
  abort_setup "the pristine fixture is not GREEN with the exact counters (rc=$SCAN_RC)" "$(cat "$c0")"
fi
pass "control 1: the pristine fixture is GREEN with exact counters (files=4 inspected=23 operands=23 nonliteral=1 skipped_comment=0 skipped_test=1), the allowlisted read found once, the clock override announced"

ONE="$FX/one-bare"
cp -a "$PRISTINE" "$ONE" || abort_setup "cannot copy the pristine fixture"
printf '#!/usr/bin/env bash\n%s %s --plain\n' "$DSG" "$BARE" > "$ONE/scripts/extra.sh"
c1="$T/out/control-one-bare"
scan_in "$ONE" "$c1" "HCLOUD_SCAN_TODAY=$TODAY_PIN" --
if [ "$SCAN_RC" -ne 1 ] || [ "$(grep -c '^FINDING F-literal ' "$c1")" != 1 ] || [ "$(grep -c '^FINDING ' "$c1")" != 1 ] \
  || ! grep -qxF 'live: findings=1 allowlisted=1' "$c1"; then
  abort_setup "a fixture with exactly one bare read is not RED with one F-literal (rc=$SCAN_RC)" "$(cat "$c1")"
fi
pass "control 2: a fixture with exactly one bare read is RED with exactly one F-literal"

# ---- the mutation matrix -----------------------------------------------------------------------------
# edit functions: each takes the mutant dir and edits it in place; a non-zero return means the edit's own post-condition failed
e_m1() { printf '    %s=$(%s %s --plain)\n' "$BARE" "$DSG" "$BARE" >> "$1/scripts/cutover-inngest.sh"; }
e_m2() {
  {
    printf '_tok() {\n'
    printf '  local tok\n'
    printf '  tok="$(%s %s -p soleur -c prd_terraform --plain 2>/dev/null || true)"\n' "$DSG" "$RO"
    printf '  if [ -z "$tok" ]; then\n'
    printf '    tok="$(%s %s -p soleur -c prd_terraform --plain 2>/dev/null || true)"\n' "$DSG" "$BARE"
    printf '  fi\n'
    printf '}\n'
  } > "$1/scripts/m2.sh"
}
e_m3() {
  {
    printf 'a=$(%s %s %s --plain)\n' "$DSG" "$RO" "$BARE"
    printf 'b=$(%s %s --plain %s)\n' "$DSG" "$BARE" "$RO"
  } > "$1/scripts/m3.sh"
}
e_m4() {
  {
    printf 'n1=%s\n' "$BARE";                                printf 'x1=$(%s "$n1" --plain)\n' "$DSG"
    printf 'for n2 in %s %s; do :; done\n' "$RO" "$BARE";    printf 'x2=$(%s "$n2" --plain)\n' "$DSG"
    printf 'read -r n3 <<< %s\n' "$BARE";                    printf 'x3=$(%s "$n3" --plain)\n' "$DSG"
    printf "printf -v n4 '%%s' %s\n" "$BARE";                printf 'x4=$(%s "$n4" --plain)\n' "$DSG"
    printf 'names=(%s)\n' "$BARE";                           printf 'x5=$(%s "$names" --plain)\n' "$DSG"
    printf 'n6="${OVERRIDE:-%s}"\n' "$BARE";                 printf 'x6=$(%s "${n6}" --plain)\n' "$DSG"
    printf 'declare -n n7=%s\n' "$BARE";                     printf 'x7=$(%s "$n7" --plain)\n' "$DSG"
  } > "$1/scripts/m4.sh"
}
e_m5() { printf 'RO_TOK=${RO:-$(%s ${NAME:-%s})}\n' "$DSG" "$BARE" > "$1/scripts/m5.sh"; }
e_m6() {
  {
    printf 'a=$(%s \\\n' "$DSG"; printf '  %s --plain)\n' "$BARE"
    printf 'b=$(%s --plain -p soleur -c prd_terraform %s)\n' "$DSG" "$BARE"
    printf 'c=$(doppler secrets -p soleur -c prd_terraform get %s)\n' "$BARE"
    printf 'd=$(%s "%s" --plain)\n' "$DSG" "$BARE"
    printf "e=\$(%s '%s' --plain)\n" "$DSG" "$BARE"
  } > "$1/scripts/m6.sh"
}
e_m7() { printf 'echo "to read it run: %s %s --plain"\n' "$DSG" "$BARE" > "$1/scripts/m7.sh"; }
e_m8a() { sed -i "s/get $BARE --plain/get $BARE -p soleur --plain/" "$1/scripts/cutover-inngest.sh"; }
e_m8b() { sed -i '4d' "$1/scripts/cutover-inngest.sh"; }
e_m9() { assert_fixture_dir "$1"; mv "$1/scripts" "$1/knowledge-base"; }
e_m10b() { assert_fixture_dir "$1"; rm -f "$1/scripts/reader.sh"; mkdir "$1/scripts/reader.sh"; }
e_m10c() { assert_fixture_dir "$1"; rm -f "$1/scripts/reader.sh"; ln -s "$1/does/not/exist" "$1/scripts/reader.sh"; [ -L "$1/scripts/reader.sh" ] && [ ! -e "$1/scripts/reader.sh" ]; }
e_m10d() { assert_fixture_dir "$1"; rm -f "$1/scripts/reader.sh"; }
e_c1() {
  {
    printf 'a=$(%s %s_RW --plain)\n' "$DSG" "$BARE"
    printf 'b=$(%s %sS --plain)\n' "$DSG" "$BARE"
    printf 'c=$(%s X_%s --plain)\n' "$DSG" "$BARE"
    printf 'd=$(%s %s -p soleur -c prd_terraform --plain)\n' "$DSG" "$RO"
  } > "$1/scripts/c1.sh"
}
e_c2() {
  printf '# %s %s --plain\n' "$DSG" "$BARE" >> "$1/scripts/reader.sh"
  printf '%s %s --plain\n' "$DSG" "$BARE" > "$1/scripts/foo.test.sh"
  printf '%s %s --plain\n' "$DSG" "$BARE" > "$1/scripts/test-foo.sh"
}

# id | description | edit | diff paths | diff lines | rc | counters ("-" = none) | expectations (~ separated; leading ! = must be absent)
MATRIX=(
"M1|a second identical copy of the allowlisted line (count 2)|e_m1|1|1|1|inspected=24|FINDING F-allowlist scripts/cutover-inngest.sh~found 2~live: findings=1 allowlisted=2"
"M2|read-only read then the bare read in the same function (the removed shape), new file|e_m2|1|7|1|inspected=25|FINDING F-literal scripts/m2.sh:5:~live: findings=1 allowlisted=1"
"M3|multi-operand reads, bare name second and bare name first with a flag between|e_m3|1|2|1|inspected=25|FINDING F-literal scripts/m3.sh:1:~FINDING F-literal scripts/m3.sh:2:~live: findings=2 allowlisted=1"
"M4|one-hop definitions, one per site in the closed list (7 sites)|e_m4|1|14|1|inspected=30|FINDING F-onehop scripts/m4.sh:2:~FINDING F-onehop scripts/m4.sh:4:~FINDING F-onehop scripts/m4.sh:6:~FINDING F-onehop scripts/m4.sh:8:~FINDING F-onehop scripts/m4.sh:10:~FINDING F-onehop scripts/m4.sh:12:~FINDING F-onehop scripts/m4.sh:14:~live: findings=7 allowlisted=1"
"M5|non-literal name on a line naming the variable (nested default)|e_m5|1|1|1|inspected=24|FINDING F-sameline scripts/m5.sh:1:~live: findings=1 allowlisted=1"
"M6|literal spellings: continuation, flags first, global options, double and single quotes|e_m6|1|6|1|inspected=28|FINDING F-literal scripts/m6.sh:1:~FINDING F-literal scripts/m6.sh:3:~FINDING F-literal scripts/m6.sh:4:~FINDING F-literal scripts/m6.sh:5:~FINDING F-literal scripts/m6.sh:6:~live: findings=5 allowlisted=1"
"M7|a bare read inside an echo string (a printed recipe)|e_m7|1|1|1|inspected=24|FINDING F-literal scripts/m7.sh:1:~live: findings=1 allowlisted=1"
"M8a|the allowlisted line text edited (a flag added)|e_m8a|1|2|1|inspected=23|FINDING F-literal scripts/cutover-inngest.sh:4:~FINDING F-allowlist scripts/cutover-inngest.sh~found 0~live: findings=2 allowlisted=0"
"M8b|the allowlisted line deleted (a stale entry)|e_m8b|1|1|1|inspected=22|FINDING F-allowlist scripts/cutover-inngest.sh~found 0~live: findings=1 allowlisted=0"
"M9|the population emptied (every script moved under an excluded directory)|e_m9|8|$((PRISTINE_SCRIPT_LINES * 2))|1|inspected=0|FINDING F-floor~inspected 0 reads~live: findings=2 allowlisted=0"
"M10b|a tracked population path replaced by a directory|e_m10b|1|0|2|-|FAIL SETUP~is a directory~!live:"
"M10c|a tracked population path replaced by a dangling symlink|e_m10c|-|-|2|-|FAIL SETUP~dangling symlink~!live:"
"M10d|a tracked file deleted from the disk is skipped, not a setup failure|e_m10d|1|3|0|inspected=22 skipped_deleted=1|live: findings=0 allowlisted=1"
"C1|word boundary: HCLOUD_TOKEN_RW, HCLOUD_TOKENS, X_HCLOUD_TOKEN and the read-only name are not the bare name|e_c1|1|4|0|inspected=27 operands=27 nonliteral=1|live: findings=0 allowlisted=1"
"C2|a bare read in a whole-line comment and in three test-class files is counted, not scanned|e_c2|3|3|0|inspected=23 skipped_comment=1 skipped_test=3|live: findings=0 allowlisted=1"
)

run_row() {
  local id="$1" desc="$2" edit="$3" dpaths="$4" dlines="$5" erc="$6" ctrs="$7" exps="$8"
  local d="$FX/$id" out="$T/out/$id" before after k v e ok=1 why=""
  ROWS=$((ROWS + 1))
  cp -a "$PRISTINE" "$d" || { fail "$id: cannot copy the pristine fixture"; return; }
  before="$(tree_md5 "$d")"
  if ! "$edit" "$d"; then fail "$id: the edit's own post-condition failed"; return; fi
  after="$(tree_md5 "$d")"
  if [ "$before" = "$after" ]; then fail "$id: the edit did not land (tree md5 unchanged)"; return; fi
  if [ "$dpaths" != "-" ] && { [ "$(diff_paths "$PRISTINE" "$d")" != "$dpaths" ] || [ "$(diff_lines "$PRISTINE" "$d")" != "$dlines" ]; }; then
    fail "$id: the edit is not the expected size" "paths $(diff_paths "$PRISTINE" "$d") (want $dpaths), lines $(diff_lines "$PRISTINE" "$d") (want $dlines)"
    return
  fi
  scan_in "$d" "$out" "HCLOUD_SCAN_TODAY=$TODAY_PIN" --
  if [ "$SCAN_RC" -ne "$erc" ]; then ok=0; why="rc=$SCAN_RC want $erc"; fi
  if [ "$ctrs" != "-" ]; then
    for e in $ctrs; do
      k="${e%%=*}"; v="${e#*=}"
      if [ "$(ctr "$out" "$k")" != "$v" ]; then ok=0; why="$why; counter $k=$(ctr "$out" "$k") want $v"; fi
    done
  fi
  e="$(expect_all "$out" "$exps")"
  if [ -n "$e" ]; then ok=0; why="$why$e"; fi
  if [ "$ok" = 1 ]; then pass "$id: $desc"; else fail "$id: $desc" "$why :: $(head -c 600 "$out")"; fi
}
for row in "${MATRIX[@]}"; do
  IFS='|' read -r r_id r_desc r_edit r_dp r_dl r_rc r_ctr r_exp <<< "$row"
  run_row "$r_id" "$r_desc" "$r_edit" "$r_dp" "$r_dl" "$r_rc" "$r_ctr" "$r_exp"
done

# M10a: the root is not a git work tree
NOGIT="$FX/nogit"
mkdir -p "$NOGIT" && printf 'x\n' > "$NOGIT/file.sh"
scan_in "$NOGIT" "$T/out/M10a" "HCLOUD_SCAN_TODAY=$TODAY_PIN" --
ROWS=$((ROWS + 1))
if [ "$SCAN_RC" = 2 ] && grep -qF 'FAIL SETUP' "$T/out/M10a" && ! grep -qF 'live:' "$T/out/M10a"; then
  pass "M10a: a root that is not a git work tree is FAIL SETUP (rc 2), never 'no findings'"
else fail "M10a: a root that is not a git work tree" "rc=$SCAN_RC $(head -c 300 "$T/out/M10a")"; fi

# M11: the clock and root seams cannot be set from a workflow environment
ROWS=$((ROWS + 1))
scan_in "$PRISTINE" "$T/out/M11a" GITHUB_ACTIONS=true HCLOUD_SCAN_TODAY=2000-01-01 --
if [ "$SCAN_RC" = 2 ] && grep -qF 'FAIL SETUP' "$T/out/M11a" && ! grep -qF 'live:' "$T/out/M11a"; then
  pass "M11a: GITHUB_ACTIONS=true with an inherited HCLOUD_SCAN_TODAY is FAIL SETUP (rc 2)"
else fail "M11a: inherited HCLOUD_SCAN_TODAY under GITHUB_ACTIONS" "rc=$SCAN_RC $(head -c 300 "$T/out/M11a")"; fi
ROWS=$((ROWS + 1))
scan_in "$PRISTINE" "$T/out/M11b" GITHUB_ACTIONS=true --
if [ "$SCAN_RC" = 2 ] && grep -qF 'FAIL SETUP' "$T/out/M11b" && ! grep -qF 'live:' "$T/out/M11b"; then
  pass "M11b: GITHUB_ACTIONS=true with an inherited HCLOUD_SCAN_ROOT is FAIL SETUP (rc 2)"
else fail "M11b: inherited HCLOUD_SCAN_ROOT under GITHUB_ACTIONS" "rc=$SCAN_RC $(head -c 300 "$T/out/M11b")"; fi

# C3: clock and event rows on the pristine fixture. today | event | changed ("-" none, "unres" = no list, no base) | rc | expectations
ADR241="knowledge-base/engineering/architecture/decisions/ADR-241-terraform-credentials-are-tiered-main-only-environment-secrets.md"
CUT="scripts/cutover-inngest.sh"
C3=(
"c3-expiry-22|2026-11-23||-|0|!::warning::~live: findings=0 allowlisted=1"
"c3-expiry-21|2026-11-24||-|0|::warning::~expires 2026-12-15 (21 day(s) left)~live: findings=0 allowlisted=1"
"c3-expiry-day-green|2026-12-15|pull_request|$CUT|0|expires 2026-12-15 (0 day(s) left)~live: findings=0 allowlisted=1"
"c3-expired-pr-cutover|2026-12-16|pull_request|$CUT|1|FINDING F-expired~live: findings=1 allowlisted=1"
"c3-expired-pr-adr|2026-12-16|pull_request|$ADR241|1|FINDING F-expired~live: findings=1 allowlisted=1"
"c3-expired-pr-scanner|2026-12-16|pull_request|scripts/lint-hcloud-token-readonly-no-fallback.sh|1|FINDING F-expired"
"c3-expired-pr-suite|2026-12-16|pull_request|tests/scripts/test-hcloud-token-readonly-no-fallback-scan.sh|1|FINDING F-expired"
"c3-expired-pr-unrelated|2026-12-16|pull_request|README.md|0|::warning::~touches no guarded file~!FINDING~live: findings=0 allowlisted=1"
"c3-expired-pr-unresolved-base|2026-12-16|pull_request|unres|1|FINDING F-expired"
"c3-expired-push|2026-12-16|push|$CUT|0|::warning::~non-blocking on event 'push'~!FINDING~live: findings=0 allowlisted=1"
"c3-expired-merge-group|2026-12-16|merge_group|$CUT|0|::warning::~non-blocking on event 'merge_group'~!FINDING"
"c3-expired-schedule|2026-12-16|schedule|$CUT|0|::warning::~non-blocking on event 'schedule'~!FINDING"
"c3-expired-local|2026-12-16||$CUT|0|::warning::~non-blocking on event 'local'~!FINDING"
"c3-bad-date-month|2026-13-45||-|2|FAIL SETUP~!live:"
"c3-bad-date-feb30|2026-02-30||-|2|FAIL SETUP~!live:"
"c3-bad-date-unpadded|2026-1-1||-|2|FAIL SETUP~!live:"
"c3-bad-date-word|tomorrow||-|2|FAIL SETUP~!live:"
"c3-bad-date-empty|||-|2|FAIL SETUP~!live:"
)
for row in "${C3[@]}"; do
  IFS='|' read -r c_id c_today c_event c_changed c_rc c_exp <<< "$row"
  ROWS=$((ROWS + 1))
  c_out="$T/out/$c_id"
  c_args=(--event-name "$c_event")
  if [ "$c_changed" != "-" ] && [ "$c_changed" != "unres" ]; then
    printf '%s\n' "$c_changed" > "$T/out/$c_id.changed"
    c_args+=(--changed-files "$T/out/$c_id.changed")
  fi
  scan_in "$PRISTINE" "$c_out" "HCLOUD_SCAN_TODAY=$c_today" -- "${c_args[@]}"
  c_ok=1; c_why=""
  [ "$SCAN_RC" = "$c_rc" ] || { c_ok=0; c_why="rc=$SCAN_RC want $c_rc"; }
  c_e="$(expect_all "$c_out" "$c_exp")"
  if [ -n "$c_e" ]; then c_ok=0; c_why="$c_why$c_e"; fi
  if [ "$c_ok" = 1 ]; then pass "C3 $c_id: today=$c_today event='${c_event:-local}' changed=$c_changed -> rc $c_rc"
  else fail "C3 $c_id" "$c_why :: $(head -c 400 "$c_out")"; fi
done

# ---- L1: the scanner against the REAL tree, no override -------------------------------------------------
L1="$T/out/L1"
CANDS="$T/out/live.candidates"
t0="$(date +%s.%N)"
env -u HCLOUD_SCAN_ROOT -u HCLOUD_SCAN_TODAY bash "$SCANNER" --emit-candidates "$CANDS" > "$L1" 2>&1
L1_RC=$?
t1="$(date +%s.%N)"
ROWS=$((ROWS + 1))
printf 'L1 scanner wall time: %s s\n' "$(awk -v a="$t0" -v b="$t1" 'BEGIN { printf "%.2f", b - a }')"
if [ "$L1_RC" = 0 ] && grep -qxF 'live: findings=0 allowlisted=1' "$L1" && ! grep -q '^FINDING ' "$L1"; then
  pass "L1: the scanner against the real tree is GREEN: exactly one allowlisted read, zero findings"
else fail "L1: the scanner against the real tree" "rc=$L1_RC $(head -c 1500 "$L1")"; fi
L1_INSPECTED="$(ctr "$L1" inspected)"
if [ "${L1_INSPECTED:-0}" -ge 20 ] 2>/dev/null; then pass "L1 floor: the real tree inspected $L1_INSPECTED reads (floor 20)"
else fail "L1 floor: the real tree inspected too few reads" "inspected=${L1_INSPECTED:-none}"; fi

# ---- L2: a copy of the live population with the pre-change fallback line re-inserted --------------------
L2="$FX/l2"
mkdir -p "$L2"
assert_fixture_dir "$L2"
ROWS=$((ROWS + 1))
if [ -s "$CANDS" ] && git init -q "$L2" && tar -C "$REPO_ROOT" --null -T "$CANDS" -cf - | tar -C "$L2" -xf - ; then
  git -C "$L2" add -A
  scan_in "$L2" "$T/out/L2-control" "HCLOUD_SCAN_TODAY=$TODAY_PIN" --
  if [ "$SCAN_RC" = 0 ] && grep -qxF 'live: findings=0 allowlisted=1' "$T/out/L2-control"; then
    pass "L2 control: the unmodified population copy is GREEN (findings=0 allowlisted=1)"
  else fail "L2 control: the unmodified population copy" "rc=$SCAN_RC $(head -c 800 "$T/out/L2-control")"; fi
  L2_FILE="$L2/scripts/cutover-inngest.sh"
  L2_ANCHOR="$(grep -n "$DSG $RO " "$L2_FILE" | head -n 1 | cut -d: -f1)"
  if [ -n "$L2_ANCHOR" ]; then
    l2_before="$(tree_md5 "$L2")"
    cp -a "$L2_FILE" "$T/out/cutover.orig"
    sed -i "${L2_ANCHOR}a\\
  tok=\"\$($DSG $BARE -p soleur -c prd_terraform --plain 2>/dev/null || true)\"" "$L2_FILE"
    l2_after="$(tree_md5 "$L2")"
    l2_dl="$(diff "$T/out/cutover.orig" "$L2_FILE" | awk '/^[<>]/ { n++ } END { print n + 0 }')"
    scan_in "$L2" "$T/out/L2" "HCLOUD_SCAN_TODAY=$TODAY_PIN" --
    if [ "$l2_before" != "$l2_after" ] && [ "$l2_dl" = 1 ] && [ "$SCAN_RC" = 1 ] \
      && grep -qF "FINDING F-literal scripts/cutover-inngest.sh:$((L2_ANCHOR + 1)):" "$T/out/L2" \
      && grep -qxF 'live: findings=1 allowlisted=1' "$T/out/L2"; then
      pass "L2: the live population with the pre-change fallback line re-inserted is RED with F-literal on scripts/cutover-inngest.sh:$((L2_ANCHOR + 1))"
    else fail "L2: re-inserted fallback" "landed=$([ "$l2_before" != "$l2_after" ] && echo yes || echo no) diff=$l2_dl rc=$SCAN_RC $(head -c 800 "$T/out/L2")"; fi
  else fail "L2: cannot find the read-only read in the population copy to anchor the insertion"; fi
else fail "L2: cannot assemble the population copy (candidates file empty or the copy failed)"; fi

# ---- anti-vacuity floors (printf + exit, never through fail()) ----------------------------------------
printf '\n%s passed, %s failed (%s cases, %s matrix/clock/live rows)\n' "$PASSES" "$FAILS" "$CASES" "$ROWS"
if [ "$CASES" -lt 42 ]; then printf 'FATAL: only %s cases ran; floor is 42 (the suite went quiet)\n' "$CASES" >&2; exit 1; fi
if [ "$ROWS" -lt 38 ]; then printf 'FATAL: only %s rows ran; floor is 38\n' "$ROWS" >&2; exit 1; fi
if [ $((PASSES + FAILS)) -ne "$CASES" ]; then printf 'FATAL: verdict accounting does not reconcile (%s + %s != %s)\n' "$PASSES" "$FAILS" "$CASES" >&2; exit 1; fi
[ "$FAILS" -eq 0 ] || exit 1
exit 0
