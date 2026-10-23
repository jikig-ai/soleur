#!/usr/bin/env bash
# Battery for scripts/lint-hcloud-token-readonly-no-fallback.sh: the Hetzner read-only-token
# no-fallback scan (#10664, ADR-241 D4 and its 2026-10-23 entry). The scanner is the guard; this
# suite proves it can fail and cannot over-fire: a harness canary and an instrument-control pair
# first (abort on failure), a mutation matrix over a SYNTHETIC fixture tree, the expiry-warning clock
# rows (dates DERIVED from the scanner's ALLOW_EXPIRY, so renewing it never turns this suite red),
# then L1: the scanner against the REAL tree (findings=0, one allowlisted read). The live row is
# embedded here, not a separate -live suite. M2 is the RED proof of the pre-change fallback shape.
# Row ids are non-contiguous by design (M4, M5 and M10b-d were cut; J2 never existed). Fixtures live under ONE mktemp -d (EXIT
# trap first); git runs under git_fixture_env; fixture rows pin HCLOUD_SCAN_TODAY before the expiry
# window. The case-count floor is enforced with printf+exit, never through the fail() counter it
# audits. No xtrace refusal here on purpose: a red suite must be debuggable with `bash -x`.
# shellcheck disable=SC2016,SC2329
set -uo pipefail

T=""
cleanup() { if [ -n "$T" ]; then rm -rf -- "$T"; fi; }
trap cleanup EXIT
T="$(mktemp -d -t hcloud-ro-scan.XXXXXX)" || { printf 'FAIL SETUP: mktemp -d failed\n' >&2; exit 2; }

SUITE_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd -P "$SUITE_DIR/../.." && pwd -P)"
# shellcheck source=/dev/null
source "$REPO_ROOT/plugins/soleur/test/test-helpers.sh"
set +e
assert_fixture_dir "$T"
SCANNER="$REPO_ROOT/scripts/lint-hcloud-token-readonly-no-fallback.sh"
[ -f "$SCANNER" ] || { printf 'FAIL SETUP: scanner missing: %s\n' "$SCANNER" >&2; exit 2; }
FX="$T/fx"
mkdir -p "$FX" "$T/out" && assert_fixture_dir "$FX" && git_fixture_env "$FX" || { printf 'FAIL SETUP: fixture root\n' >&2; exit 2; }

PASSES=0 FAILS=0 CASES=0
skip() { CASES=$((CASES + 1)); printf '[skip] %s\n' "$1"; } # counted toward the floor, not a pass
pass() { PASSES=$((PASSES + 1)); CASES=$((CASES + 1)); printf '[ok] %s\n' "$1"; }
fail() { FAILS=$((FAILS + 1)); CASES=$((CASES + 1)); printf '[FAIL] %s\n' "$1"; [ -n "${2-}" ] && printf '       %s\n' "$2"; }
abort_setup() { printf 'FAIL SETUP (instrument control): %s\n' "$1" >&2; [ -n "${2-}" ] && printf '%s\n' "$2" >&2; exit 2; }

BARE="HCLOUD_TOKEN"
RO="HCLOUD_TOKEN_READONLY"
DSG="doppler secrets get"
TODAY_PIN="2026-10-23"
GREEN='live: findings=0 allowlisted=1'
GREEN2="$GREEN scanned=2"   # the pristine fixture scans exactly two files (test-bare.sh is test-class)
SCAN_WRAP=()

# scan_in <dir> <outfile> [ENV=VAL ...]; sets SCAN_RC; stdout+stderr land in <outfile>
scan_in() {
  local d="$1" out="$2"; shift 2
  assert_fixture_dir "$out"
  env -u GITHUB_ACTIONS -u HCLOUD_SCAN_ROOT -u HCLOUD_SCAN_TODAY HCLOUD_SCAN_ROOT="$d" "$@" ${SCAN_WRAP[@]+"${SCAN_WRAP[@]}"} bash "$SCANNER" > "$out" 2>&1; SCAN_RC=$?
}
tree_md5() { assert_fixture_dir "$1" && (cd "$1" && find . -path ./.git -prune -o \( -type f -o -type l \) -print0 | LC_ALL=C sort -z | xargs -0 md5sum 2>/dev/null | md5sum | cut -d' ' -f1); }
# expect_all <outfile> <~-separated expectations>: prints the failures (empty = all met); a leading ! = must be absent
expect_all() {
  local part
  while IFS= read -r part; do
    [ -n "$part" ] || continue
    if [ "${part#!}" != "$part" ]; then
      if grep -qF -- "${part#!}" "$1"; then printf '; unexpected: %s' "${part#!}"; fi
    elif ! grep -qF -- "$part" "$1"; then printf '; missing: %s' "$part"; fi
  done < <(printf '%s\n' "$2" | tr '~' '\n') # the trailing newline matters: read skips an unterminated last line
}
# verdict <id> <desc> <want rc> <expectations> <outfile>: judges SCAN_RC and the output; a failure prints the WHOLE output
verdict() {
  local why=""
  [ "$SCAN_RC" = "$3" ] || why="rc=$SCAN_RC want $3"
  why="$why$(expect_all "$5" "$4")"
  if [ -z "$why" ]; then pass "$1: $2"; else fail "$1: $2" "$why"; sed 's/^/        | /' "$5"; fi
}

# T1 harness canary, BEFORE the matrix: the verdict machinery must be able to fail. Reported with
# printf+exit 2 directly (never through the helpers under test); counters are unwound afterwards.
canary() {
  local f="$T/out/canary" tx="$T/out/canary.tx" p0=$PASSES f0=$FAILS c0=$CASES bad="" fb pb
  printf 'live: findings=0\n' > "$f"
  fb=$FAILS; SCAN_RC=0; verdict k1 d 1 'live:' "$f" > "$tx"
  [ "$FAILS" -eq $((fb + 1)) ] || bad="$bad verdict() ignored a wrong rc;"
  fb=$FAILS; SCAN_RC=0; verdict k2 d 0 'absent-string' "$f" > "$tx"
  [ "$FAILS" -eq $((fb + 1)) ] || bad="$bad verdict() ignored a missing expectation;"
  fb=$FAILS; SCAN_RC=0; verdict k3 d 0 '!live:' "$f" > "$tx"
  [ "$FAILS" -eq $((fb + 1)) ] || bad="$bad verdict() ignored a present !expectation;"
  fb=$FAILS; pb=$PASSES; SCAN_RC=0; verdict k4 d 0 'live:' "$f" > "$tx"
  { [ "$PASSES" -eq $((pb + 1)) ] && [ "$FAILS" -eq "$fb" ]; } || bad="$bad verdict() did not pass a matching case;"
  [ -n "$(expect_all "$f" 'absent-string')" ] || bad="$bad expect_all() is a no-op;"
  [ -z "$(expect_all "$f" 'live:')" ] || bad="$bad expect_all() reports a met expectation;"
  pb=$PASSES; fb=$FAILS; pass k5 > "$tx"; fail k6 > "$tx"
  { [ "$PASSES" -eq $((pb + 1)) ] && [ "$FAILS" -eq $((fb + 1)) ]; } || bad="$bad pass()/fail() counters did not move;"
  PASSES=$p0 FAILS=$f0 CASES=$c0
  [ -z "$bad" ] || { printf 'FAIL SETUP (harness canary):%s\n' "$bad" >&2; exit 2; }
  pass "T1: the harness canary ran (verdict, expect_all, pass and fail can each fail or count); it is counted so the floor sees a deleted or neutered canary"
}
canary

# ---- the pristine fixture (cutover-inngest.sh line 3 = read-only read, line 7 = allowlisted read) ----
PRISTINE="$FX/pristine"
build_pristine() {
  local d="$1"
  assert_fixture_dir "$d"
  mkdir -p "$d/scripts" "$d/tests/scripts" && git init -q "$d" || return 1
  {
    printf '#!/usr/bin/env bash\n_tok() {\n  tok="$(%s %s -p soleur -c prd_terraform --plain 2>/dev/null || true)"\n' "$DSG" "$RO"
    printf '}\ncase "$1" in\n  backup)\n    %s=$(%s %s --plain)\n    ;;\nesac\n' "$BARE" "$DSG" "$BARE"
  } > "$d/scripts/cutover-inngest.sh"
  printf '#!/usr/bin/env bash\n# an unrelated channel-key read\nCK=INNGEST_CHANNEL_KEY\nAPP_CK=$(%s "$CK" --plain 2>/dev/null || true)\n' "$DSG" > "$d/scripts/ck.sh"
  printf '#!/usr/bin/env bash\n%s %s --plain\n' "$DSG" "$BARE" > "$d/tests/scripts/test-bare.sh"
  git -C "$d" add -A
}
build_pristine "$PRISTINE" || abort_setup "cannot build the pristine fixture"

# instrument controls (abort on failure)
control() { # <dir> <want rc> <expectations> <description>
  scan_in "$1" "$T/out/control" "HCLOUD_SCAN_TODAY=$TODAY_PIN"
  if [ "$SCAN_RC" != "$2" ] || [ -n "$(expect_all "$T/out/control" "$3")" ]; then abort_setup "$4 (rc=$SCAN_RC)" "$(cat "$T/out/control")"; fi
  pass "$4"
}
control "$PRISTINE" 0 "$GREEN2~HCLOUD_SCAN_TODAY override active: $TODAY_PIN" "control 1: the pristine fixture is GREEN, the allowlisted read found once, the clock override announced"
ONE="$FX/one-bare"
cp -a "$PRISTINE" "$ONE" || abort_setup "cannot copy the pristine fixture"
printf '#!/usr/bin/env bash\n%s %s --plain\n' "$DSG" "$BARE" > "$ONE/scripts/extra.sh"
control "$ONE" 1 "FINDING F-literal scripts/extra.sh:2:~live: findings=1 allowlisted=1 scanned=3" "control 2: a fixture with exactly one bare read is RED with exactly one F-literal"

# edit functions edit the mutant dir in place; a non-zero return means the edit's own post-condition failed
readbare() { printf '%s %s --plain\n' "$DSG" "$BARE"; } # one violating bare read line
e_m1() { printf '    %s=$(%s %s --plain)\n' "$BARE" "$DSG" "$BARE" >> "$1/scripts/cutover-inngest.sh"; }
e_m2() { sed -i "3a\\
  tok=\"\$($DSG $BARE -p soleur -c prd_terraform --plain 2>/dev/null || true)\"" "$1/scripts/cutover-inngest.sh"; }
e_m3() { printf 'a=$(%s %s %s --plain)\nb=$(%s %s --plain %s)\n' "$DSG" "$RO" "$BARE" "$DSG" "$BARE" "$RO" > "$1/scripts/m3.sh"; }
e_m6() {
  printf 'a=$(%s \\\n  %s --plain)\nb=$(%s --plain -p soleur -c prd_terraform %s)\nc=$(doppler secrets -p soleur -c prd_terraform get %s)\n' \
    "$DSG" "$BARE" "$DSG" "$BARE" "$BARE" > "$1/scripts/m6.sh"
  printf "d=\$(%s \"%s\" --plain)\ne=\$(%s '%s' --plain)\n" "$DSG" "$BARE" "$DSG" "$BARE" >> "$1/scripts/m6.sh"
}
e_m7() { printf 'echo "to read it run: %s %s --plain"\n' "$DSG" "$BARE" > "$1/scripts/m7.sh"; }
e_m8a() { sed -i "s/get $BARE --plain/get $BARE -p soleur --plain/" "$1/scripts/cutover-inngest.sh"; }
e_m8b() { sed -i '7d' "$1/scripts/cutover-inngest.sh"; }
e_m9() { assert_fixture_dir "$1"; mv "$1/scripts" "$1/knowledge-base"; }
e_b1() { printf 'for v in %s %s; do %s "$v" --plain; done\n' "$RO" "$BARE" "$DSG" > "$1/scripts/b1.sh"; }
e_b2() { printf 'for v in %s; do %s "$v" --plain; done\n' "$RO" "$DSG" > "$1/scripts/b2.sh"; }
e_s1() { assert_fixture_dir "$1"; rm -f "$1/scripts/ck.sh"; ln -s "$1/does/not/exist" "$1/scripts/ck.sh"; [ -L "$1/scripts/ck.sh" ] && [ ! -e "$1/scripts/ck.sh" ]; }
e_c1() { for n in "${BARE}_RW" "${BARE}S" "X_$BARE" "$RO"; do printf 'a=$(%s %s -p soleur --plain)\n' "$DSG" "$n"; done > "$1/scripts/c1.sh"; }
e_c2() { printf '# %s %s --plain\n' "$DSG" "$BARE" >> "$1/scripts/ck.sh"; for f in foo.test.sh test-foo.sh; do readbare > "$1/scripts/$f"; done; }
# a single & (2>&1, &>, >&2) is a redirection, not a segment boundary
e_a1() { printf 'a=$(%s 2>&1 %s --plain)\nb=$(%s &>/dev/null %s)\nc=$(%s >&2 %s --plain)\n' "$DSG" "$BARE" "$DSG" "$BARE" "$DSG" "$BARE" > "$1/scripts/a1.sh"; }
# the real boundaries still end the segment: the bare name after them is not an operand of the get
e_a2() { for b in '&&' ';' '|' '||' '|&'; do printf 'x=$(%s %s %s echo %s)\n' "$DSG" "$RO" "$b" "$BARE"; done > "$1/scripts/a2.sh"; }
# continuation = backslash-newline DELETED (bash): a name or the command split mid-word is still the read
e_j1() { printf 'a=$(%s HCLOUD_\\\nTOKEN --plain)\nb=$(dopp\\\nler secrets get %s --plain)\n' "$DSG" "$BARE" > "$1/scripts/j1.sh"; }
e_j3() { printf '%s\\\nHCLOUD_TOKEN --plain\n' "$DSG" > "$1/scripts/j3.sh"; } # bash sees getHCLOUD_TOKEN: not a read
e_n1() { printf '#!/usr/bin/env bash\n\000\n%s %s --plain\n' "$DSG" "$BARE" > "$1/scripts/nul.sh"; }
e_big() { { readbare; head -c 5300000 /dev/zero | tr '\0' ' '; printf '\n'; } > "$1/scripts/big.sh"; }
e_bigok() { { readbare; head -c 4900000 /dev/zero | tr '\0' ' '; printf '\n'; } > "$1/scripts/bigok.sh"; } # under the 5 MB cap: scanned
e_o1() { printf '%s=$(%s %s -p soleur -c prd_terraform --plain)\n' "$BARE" "$DSG" "$RO" > "$1/scripts/o1.sh"; } # the bare name BEFORE doppler is not a read
e_l1() { printf 'x-%s %s --plain\n.%s %s --plain\n%sx %s --plain\n' "$DSG" "$BARE" "$DSG" "$BARE" "$DSG" "$BARE" > "$1/scripts/l1.sh"; } # lookbehind and \bget\b
e_k1() { printf '%s \\\\\n%s --plain\n' "$DSG" "$BARE" > "$1/scripts/k1.sh"; } # an EVEN backslash run is not a continuation
e_k2() { printf 'dop\000pler secrets get %s --plain\n' "$BARE" > "$1/scripts/k2.sh"; } # NUL stripped mid-token
e_j4() { printf 'true #a\\\n%s %s --plain\n%s a#b HCLOUD_\\\nTOKEN --plain\n' "$DSG" "$BARE" "$DSG" > "$1/scripts/j4.sh"; } # comment ends the line; a# in a word joins
e_g1() { assert_fixture_dir "$1" && printf 'hidden.sh\n' > "$1/.gitignore" && readbare > "$1/scripts/hidden.sh" && git -C "$1" add -f scripts/hidden.sh .gitignore; } # tracked AND ignored
e_u1() { chmod 000 "$1/scripts/ck.sh"; }
e_p1() { { printf 'doppler'; for ((i = 0; i < 8000; i++)); do printf ' secrets get'; done; printf ' %s --plain\n' "$BARE"; } > "$1/scripts/patho.sh"; SCAN_WRAP=(timeout 3); }
e_d1() { mkdir -p "$1/tests/scripts/lib" && readbare > "$1/tests/scripts/lib/gate.sh"; }
e_d3() { mkdir -p "$1/tests/fixtures/lib" "$1/tests/lib" && readbare > "$1/tests/fixtures/lib/x.sh" && readbare > "$1/tests/lib/y.sh"; }
e_d2() { # test-class, docs and markdown paths with a violating read each: none is scanned
  local f
  for f in tests/other/x.sh fixtures/x.sh scripts/fixtures/y.sh docs/z.sh scripts/docs/w.sh scripts/foo.spec.sh README.md scripts/runbook.md; do
    mkdir -p "$1/$(dirname "$f")" && readbare > "$1/$f" || return 1
  done
}
e_t2() { # the population is by selection, not by extension
  local f
  for f in x/deep/cloud-init.yml a.service main.tf .claude/hooks/h bin/runner .github/workflows/w.yml; do
    mkdir -p "$1/$(dirname "$f")" && readbare > "$1/$f" || return 1
  done
}
e_t3a() { printf '%s=$(%s %s --plain)\n' "$BARE" "$DSG" "$BARE" > "$1/scripts/other.sh"; }
e_t3b() { e_t3a "$1" && e_m8b "$1"; }

CUT="FINDING F-allowlist scripts/cutover-inngest.sh~found 0~live: findings=1 allowlisted=0"
# id | description | edit | rc | expectations (~ separated; leading ! = must be absent)
MATRIX=(
"M1|a second identical copy of the allowlisted line (count 2)|e_m1|1|FINDING F-allowlist scripts/cutover-inngest.sh~found 2~live: findings=1 allowlisted=2"
"M2|the pre-change fallback line after the read-only read in a synthetic cutover-inngest.sh|e_m2|1|FINDING F-literal scripts/cutover-inngest.sh:4:~live: findings=1 allowlisted=1"
"M3|multi-operand reads, bare name second and bare name first with a flag between|e_m3|1|FINDING F-literal scripts/m3.sh:1:~FINDING F-literal scripts/m3.sh:2:~live: findings=2 allowlisted=1"
"M6|literal spellings: continuation, flags first, global options, double and single quotes|e_m6|1|F-literal scripts/m6.sh:1:~F-literal scripts/m6.sh:3:~F-literal scripts/m6.sh:4:~F-literal scripts/m6.sh:5:~F-literal scripts/m6.sh:6:~live: findings=5 allowlisted=1"
"M7|a bare read inside an echo string (a printed recipe) is a finding|e_m7|1|FINDING F-literal scripts/m7.sh:1:~live: findings=1 allowlisted=1"
"M8a|the allowlisted line text edited (a flag added)|e_m8a|1|FINDING F-literal scripts/cutover-inngest.sh:7:~found 0~live: findings=2 allowlisted=0"
"M8b|the allowlisted line deleted (a stale entry)|e_m8b|1|$CUT"
"M9|tracked scripts missing from disk and the replacement under an excluded dir (knowledge-base)|e_m9|1|$CUT scanned=0"
"B1|rule B: a non-literal operand on a line naming both names (the for-loop shape)|e_b1|1|FINDING F-sameline scripts/b1.sh:1:~live: findings=1 allowlisted=1"
"B2|rule B does not fire on the read-only name alone with a non-literal operand|e_b2|0|!FINDING~$GREEN"
"S1|a tracked path replaced by a dangling symlink is skipped (rc 0), not a setup failure|e_s1|0|!FAIL SETUP~$GREEN scanned=1"
"C1|word boundary: HCLOUD_TOKEN_RW, HCLOUD_TOKENS, X_HCLOUD_TOKEN and the read-only name are not the bare name|e_c1|0|$GREEN"
"C2|a bare read in a whole-line comment, two added test-class files plus the pristine one are not scanned|e_c2|0|$GREEN2"
"A1|a single & is not a boundary: 2>&1, &>/dev/null and >&2 before the bare name are findings|e_a1|1|F-literal scripts/a1.sh:1:~F-literal scripts/a1.sh:2:~F-literal scripts/a1.sh:3:~live: findings=3 allowlisted=1"
"A2|real boundaries (&& ; pipe or-or pipe-amp) still end the segment|e_a2|0|!FINDING~$GREEN"
"J1|a name split mid-word by a continuation, and a split command word, are findings|e_j1|1|F-literal scripts/j1.sh:1:~F-literal scripts/j1.sh:3:~live: findings=2 allowlisted=1"
"J3|a continuation between get and the name joins them as bash does (getHCLOUD_TOKEN): no read|e_j3|0|!FINDING~$GREEN"
"N1|a NUL byte on line 2 does not skip the file: the bare read below it is a finding|e_n1|1|F-literal scripts/nul.sh:3:~live: findings=1 allowlisted=1"
"BIG|a 5.3 MB file is skipped (named blind spot), counted in a warning, not read|e_big|0|!FINDING~::warning::skipped 1 file(s) over 5 MB (not scanned)~$GREEN2"
"BIGOK|a 4.9 MB file with a real read is under the cap and IS scanned, with no skip warning|e_bigok|1|FINDING F-literal scripts/bigok.sh:1:~!skipped~live: findings=1 allowlisted=1 scanned=3"
"P1|a pathological ~100 KB line of secrets/get tokens ending in a real read is still found, in time (timeout 3)|e_p1|1|FINDING F-literal scripts/patho.sh:1:~live: findings=1 allowlisted=1"
"O1b|the bare name BEFORE doppler on the line (an assignment capturing the read-only get) is not a read|e_o1|0|!FINDING~$GREEN scanned=3"
"L1b|x-doppler, .doppler and getx are not the command (lookbehind and word-bounded get)|e_l1|0|!FINDING~$GREEN scanned=3"
"K1|an EVEN backslash run before the newline is not a continuation|e_k1|0|!FINDING~$GREEN scanned=3"
"K2|a NUL byte inside the command word is stripped as bash does: dop<NUL>pler is a finding|e_k2|1|FINDING F-literal scripts/k2.sh:1:~live: findings=1 allowlisted=1"
"J4|a comment start ends the logical line (bash keeps no comment continuation), a# inside a word still joins|e_j4|1|FINDING F-literal scripts/j4.sh:2:~FINDING F-literal scripts/j4.sh:3:~live: findings=2 allowlisted=1"
"D1|a violating read under tests/scripts/lib/ (sourced at runtime) is scanned|e_d1|1|FINDING F-literal tests/scripts/lib/gate.sh:1:~live: findings=1 allowlisted=1 scanned=3"
"D3|a lib segment outside tests/scripts/lib/ (tests/fixtures/lib, tests/lib) does not un-exclude|e_d3|0|!FINDING~$GREEN2"
"D2|tests/other, fixtures, docs, a .spec. infix and *.md are not scanned|e_d2|0|!FINDING~$GREEN2"
"T2|population by selection: yml, .service, .tf, .claude/hooks, an extensionless file and .github/workflows are each scanned|e_t2|1|F-literal x/deep/cloud-init.yml:1:~F-literal a.service:1:~F-literal main.tf:1:~F-literal .claude/hooks/h:1:~F-literal bin/runner:1:~F-literal .github/workflows/w.yml:1:~live: findings=6 allowlisted=1 scanned=8"
"T3a|the allowlisted text in another file is a finding; the real entry still counts once|e_t3a|1|FINDING F-literal scripts/other.sh:1:~live: findings=1 allowlisted=1"
"T3b|the allowlist is keyed on the file: the text in scripts/other.sh does not satisfy it|e_t3b|1|FINDING F-literal scripts/other.sh:1:~FINDING F-allowlist scripts/cutover-inngest.sh~found 0~live: findings=2 allowlisted=0"
)
if [ "$(id -u)" -eq 0 ]; then skip "E1: an unreadable regular file is FAIL SETUP (skipped: root reads any file)"
else MATRIX+=("E1|an unreadable regular file is FAIL SETUP (rc 2), never skipped silently|e_u1|2|FAIL SETUP: cannot read scripts/ck.sh~!live:"); fi
for row in "${MATRIX[@]}"; do
  IFS='|' read -r id desc edit erc exps <<< "$row"
  d="$FX/$id"
  SCAN_WRAP=()
  cp -a "$PRISTINE" "$d" || { fail "$id: cannot copy the pristine fixture"; continue; }
  before="$(tree_md5 "$d")"
  if ! "$edit" "$d"; then fail "$id: the edit's own post-condition failed"; continue; fi
  if [ "$before" = "$(tree_md5 "$d")" ]; then fail "$id: the edit did not land (tree md5 unchanged)"; continue; fi
  scan_in "$d" "$T/out/$id" "HCLOUD_SCAN_TODAY=$TODAY_PIN"
  SCAN_WRAP=()
  verdict "$id" "$desc" "$erc" "$exps" "$T/out/$id"
done

# M10a: the root is not a git work tree (the root-independent FAIL SETUP row)
mkdir -p "$FX/nogit" && printf 'x\n' > "$FX/nogit/file.sh"
scan_in "$FX/nogit" "$T/out/M10a" "HCLOUD_SCAN_TODAY=$TODAY_PIN"
verdict M10a "a root that is not a git work tree is FAIL SETUP (rc 2), never 'no findings'" 2 'FAIL SETUP~!live:' "$T/out/M10a"

# R1: a subdirectory of a work tree is not a root
scan_in "$PRISTINE/scripts" "$T/out/R1" "HCLOUD_SCAN_TODAY=$TODAY_PIN"
verdict R1 "a root that is a subdirectory of a work tree is FAIL SETUP (rc 2)" 2 'FAIL SETUP: root~is not the top of a git work tree~!live:' "$T/out/R1"
# G1: an exported GIT_INDEX_FILE must not change the verdict (a tracked-and-ignored file is only listed via the real index)
cp -a "$PRISTINE" "$FX/G1" && e_g1 "$FX/G1" || abort_setup "cannot build G1"
scan_in "$FX/G1" "$T/out/G1" "HCLOUD_SCAN_TODAY=$TODAY_PIN" "GIT_INDEX_FILE=$FX/no-such.idx"
verdict G1 "an exported GIT_INDEX_FILE does not hide a tracked-but-ignored file (GIT_DROP)" 1 'FINDING F-literal scripts/hidden.sh:1:' "$T/out/G1"

# S2: the root seam is refused from a workflow environment (it could point the gate at an empty tree)
scan_in "$PRISTINE" "$T/out/S2" "HCLOUD_SCAN_TODAY=$TODAY_PIN" GITHUB_ACTIONS=true
verdict S2 "HCLOUD_SCAN_ROOT under GITHUB_ACTIONS is refused (rc 2), never honoured" 2 'FAIL SETUP: GITHUB_ACTIONS is set~!live:' "$T/out/S2"

# U1 / X1: an argument is a usage error (rc 2); xtrace is refused (rc 78)
env -u GITHUB_ACTIONS -u HCLOUD_SCAN_ROOT -u HCLOUD_SCAN_TODAY bash "$SCANNER" --bogus > "$T/out/U1" 2>&1; SCAN_RC=$?
verdict U1 "an argument is a usage error (rc 2), nothing scanned" 2 'usage:~!live:' "$T/out/U1"
env -u GITHUB_ACTIONS -u HCLOUD_SCAN_ROOT -u HCLOUD_SCAN_TODAY HCLOUD_SCAN_ROOT="$PRISTINE" bash -x "$SCANNER" > "$T/out/X1" 2>&1; SCAN_RC=$?
verdict X1 "xtrace on is refused (rc 78), nothing scanned" 78 'refusing to run while xtrace is on~!live:' "$T/out/X1"

# C3: the expiry is warning-only. Every date is DERIVED from the scanner's ALLOW_EXPIRY.
EXPIRY="$(sed -n 's/^ALLOW_EXPIRY = datetime\.date(\([0-9]*\), *\([0-9]*\), *\([0-9]*\))$/\1 \2 \3/p' "$SCANNER" | xargs python3 -I -c 'import datetime, sys; print(datetime.date(*map(int, sys.argv[1:4])).isoformat())' 2>/dev/null)"
[[ "$EXPIRY" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || abort_setup "cannot extract ALLOW_EXPIRY from the scanner (got '$EXPIRY')"
shift_days() { python3 -I -c 'import datetime, sys; print((datetime.date.fromisoformat(sys.argv[1]) + datetime.timedelta(int(sys.argv[2]))).isoformat())' "$EXPIRY" "$1"; }
D_BEFORE="$(shift_days -22)" D_START="$(shift_days -21)" D_AFTER="$(shift_days 31)"
# id | today | rc | expectations
C3=(
"c3-before-window|$D_BEFORE|0|!::warning::~!see ADR-241~scan: HCLOUD_SCAN_ROOT override active: $PRISTINE~$GREEN2"
"c3-window-start|$D_START|0|::warning::~expires $EXPIRY (21 days left)~$GREEN2"
"c3-expiry-day|$EXPIRY|0|::warning::~expires $EXPIRY (0 days left)~$GREEN2"
"c3-after-expiry|$D_AFTER|0|::warning::~expired $EXPIRY~!expires~!FINDING~$GREEN2"
"c3-bad-date|2026-02-30|2|FAIL SETUP~!live:"
"c3-bad-format|20261023|2|FAIL SETUP~!live:"
)
for row in "${C3[@]}"; do
  IFS='|' read -r id today erc exps <<< "$row"
  scan_in "$PRISTINE" "$T/out/$id" "HCLOUD_SCAN_TODAY=$today"
  verdict "C3 $id" "today=$today -> rc $erc" "$erc" "$exps" "$T/out/$id"
done

# X2 / X3: expiry parity. A silent edit of ALLOW_EXPIRY (say to 2099) must be noticed: the date is also in the ADR entry and the allowlisted line's comment.
ADR="$REPO_ROOT/knowledge-base/engineering/architecture/decisions/ADR-241-terraform-credentials-are-tiered-main-only-environment-secrets.md"
sed -n '/^### 2026-10-23 (#10664 Site C)/,/^### /p' "$ADR" 2>/dev/null > "$T/out/X2"
SCAN_RC=0; verdict X2 "the scanner's ALLOW_EXPIRY ($EXPIRY) appears in the ADR-241 2026-10-23 entry" 0 "$EXPIRY" "$T/out/X2"
grep -B10 -F -- "$BARE=\$($DSG $BARE --plain)" "$REPO_ROOT/scripts/cutover-inngest.sh" 2>/dev/null > "$T/out/X3"
SCAN_RC=0; verdict X3 "the scanner's ALLOW_EXPIRY ($EXPIRY) appears in the comment above the allowlisted line in scripts/cutover-inngest.sh" 0 "$EXPIRY" "$T/out/X3"

# O1: output order is FINDING lines, the expiry warning, the live: summary, then the remedy line last
scan_in "$ONE" "$T/out/O1" "HCLOUD_SCAN_TODAY=$EXPIRY"
verdict O1 "a finding at the expiry day prints the finding, the warning, the summary and the remedy line" 1 "FINDING F-literal~::warning::~see ADR-241 2026-10-23 entry: read HCLOUD_TOKEN_READONLY only~live: findings=1 allowlisted=1 scanned=3" "$T/out/O1"
if awk '/^FINDING/ && !f { f = NR } /^::warning::/ { w = NR } /^live:/ { l = NR } /^see ADR-241/ { r = NR } END { exit !(f && w && l && r && f < w && w < l && l < r) }' "$T/out/O1"; then
  pass "O2: the output order is findings, warning, summary, remedy"
else
  fail "O2: the output order is findings, warning, summary, remedy"; sed 's/^/        | /' "$T/out/O1"
fi

# L1: the scanner against the REAL tree, no override
t0="$(date +%s.%N)"
env -u HCLOUD_SCAN_ROOT -u HCLOUD_SCAN_TODAY bash "$SCANNER" > "$T/out/L1" 2>&1
SCAN_RC=$?
printf 'L1 scanner wall time: %s s\n' "$(awk -v a="$t0" -v b="$(date +%s.%N)" 'BEGIN { printf "%.2f", b - a }')"
verdict L1 "the scanner against the real tree is GREEN: exactly one allowlisted read, zero findings" 0 "!FINDING~$GREEN scanned=" "$T/out/L1"
grep '^::warning::' "$T/out/L1" || true # re-emit so the expiry warning reaches the CI log and annotations

printf '\n%s passed, %s failed\n' "$PASSES" "$FAILS"
if [ "$CASES" -lt 53 ]; then printf 'FATAL: only %s cases ran; floor is 53 (the suite went quiet)\n' "$CASES" >&2; exit 1; fi
[ "$FAILS" -eq 0 ] || exit 1
exit 0
