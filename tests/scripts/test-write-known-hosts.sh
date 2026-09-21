#!/usr/bin/env bash
# Guard 3 (bash site) for .github/actions/cf-tunnel-ssh-bridge/write-known-hosts.sh (#7226).
#
# The writer is the ONE place every CI bash ssh path turns a committed or published pin into a
# known_hosts line. A pin is accepted only when it is exactly one key line of a supported
# algorithm (ecdsa-sha2-nistp256 for web-1, ssh-ed25519 for git-data) with no host pattern,
# marker, comment or second line -- a mis-shaped pin could otherwise inject a known_hosts
# wildcard (`* ssh-rsa …`) that trusts an attacker key for every host.
#
# Every key used here is GENERATED AT TEST TIME (cq-test-fixtures-synthesized-only), except the
# committed pin file, which is exercised as the real production input.
#
# Rows:
#   P*  must-PASS: committed pin, generated ECDSA-P256, generated ED25519, CRLF + header +
#       blank lines, the two-alias append the cutover workflow performs.
#   R*  must-REJECT (no file written): Guard 3 mutation rows 1-4 plus the out-path, alias,
#       symlink, duplicate-alias and missing-file arms; R15-R21 refuse to EXTEND an out file
#       holding any line the writer could not have written (@cert-authority, a host pattern, a
#       duplicate alias on a later line, a CR), an out path that is a directory or has a `..`
#       segment, and ED25519 pins with a trailing comment or space. R22 pins the refusal
#       annotation (`verdict=pin_refused alias=<alias> reason=<word>`, never file bytes).
#   Q   the writer with `$RE` QUOTED must reject a must-PASS pin. A quoted RHS makes `=~` a
#       literal string compare, so this row proves the unquoted form is load-bearing.
#   S*  structure: `# twin:` comments, the unquoted `=~ $RE` form, mode 0444, fingerprint-only
#       stdout (the raw key body is never printed).
# shellcheck disable=SC2016
# ^ the single-quoted `$RE` patterns below are deliberately literal (they match the writer's source).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WRITER="$REPO_ROOT/.github/actions/cf-tunnel-ssh-bridge/write-known-hosts.sh"
PIN="$REPO_ROOT/apps/web-platform/infra/web-1-ssh-host-key.pub"
export TMPDIR="${TMPDIR:-/var/tmp}"
pass=0; fail=0; cases=0
FAILURES=()

_report() {
  local label="$1" status="$2" detail="${3:-}"
  if [[ "$status" == "ok" ]]; then pass=$((pass + 1)); echo "[ok] $label"
  else fail=$((fail + 1)); FAILURES+=("$label"); echo "[FAIL] $label $detail" >&2; fi
}

# INSTRUMENT SELF-TEST (ADR-193): both reporter arms must move their counters.
_report "instrument self-test (pass arm)" ok
_report "instrument self-test (fail arm)" bad "expected -- unwound below"
if (( pass < 1 || fail < 1 )); then
  printf 'FAIL: instrument self-test did not move both counters\n' >&2; exit 1
fi
pass=0; fail=0; FAILURES=()

[[ -r "$WRITER" ]] || { printf 'FAIL: writer not readable at %s\n' "$WRITER" >&2; exit 1; }
[[ -r "$PIN" ]] || { printf 'FAIL: committed pin not readable at %s\n' "$PIN" >&2; exit 1; }
command -v ssh-keygen >/dev/null || { printf 'FAIL: ssh-keygen required\n' >&2; exit 1; }

# The canonical fixture-dir assertion, byte-equal to plugins/soleur/test/test-helpers.sh
# (fixture-dir-operand-assert.test.sh compares every tracked copy against it).
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

SANDBOX="$(mktemp -d -t writekh.XXXXXXXX)"
trap 'chmod -R u+w "$SANDBOX" 2>/dev/null; rm -rf "$SANDBOX"' EXIT

ssh-keygen -q -t ecdsa -b 256 -N '' -C 'fixture-ecdsa' -f "$SANDBOX/ec" >/dev/null
ssh-keygen -q -t ed25519 -N '' -C 'fixture-ed25519' -f "$SANDBOX/ed" >/dev/null
ssh-keygen -q -t rsa -b 2048 -N '' -C 'fixture-rsa' -f "$SANDBOX/rsa" >/dev/null
# A public key line WITHOUT its comment field (ssh-keygen appends one).
EC="$(cut -d' ' -f1,2 "$SANDBOX/ec.pub")"
ED="$(cut -d' ' -f1,2 "$SANDBOX/ed.pub")"
RSA="$(cut -d' ' -f1,2 "$SANDBOX/rsa.pub")"
COMMITTED="$(awk '!/^[[:space:]]*#/ && NF' "$PIN")"

n=0
# run_writer <writer> <alias> <pin-content|@path> <out> -- sets RC, STDOUT, STDERR.
run_writer() {
  local writer="$1" alias="$2" content="$3" out="$4" pinf
  n=$((n + 1))
  if [[ "$content" == @* ]]; then pinf="${content#@}"
  else pinf="$SANDBOX/pin.$n"; assert_fixture_dir "$pinf"; printf '%s' "$content" > "$pinf"; fi
  set +e
  bash "$writer" "$alias" "$pinf" "$out" >"$SANDBOX/stdout.$n" 2>"$SANDBOX/stderr.$n"
  RC=$?
  set -e
  STDOUT="$(<"$SANDBOX/stdout.$n")"; STDERR="$(<"$SANDBOX/stderr.$n")"
}

# expect_pass <label> <alias> <content> <expected-key-line>
expect_pass() {
  local label="$1" alias="$2" content="$3" want="$4" out
  cases=$((cases + 1))
  out="$SANDBOX/kh.$((n + 1))"
  run_writer "$WRITER" "$alias" "$content" "$out"
  if [[ "$RC" -ne 0 ]]; then _report "$label" bad "writer rc=$RC stderr=[$STDERR]"; return; fi
  if [[ ! -f "$out" ]]; then _report "$label" bad "no known_hosts written"; return; fi
  local got; got="$(<"$out")"
  if [[ "$got" != "$alias $want" ]]; then _report "$label" bad "content=[$got] want=[$alias $want]"; return; fi
  _report "$label" ok
}

# expect_reject <label> <alias> <content> [out] -- nonzero rc AND no file at <out>.
expect_reject() {
  local label="$1" alias="$2" content="$3" out="${4:-$SANDBOX/kh.$((n + 1))}"
  cases=$((cases + 1))
  run_writer "$WRITER" "$alias" "$content" "$out"
  if [[ "$RC" -eq 0 ]]; then _report "$label" bad "writer ACCEPTED it (rc=0)"; return; fi
  if [[ -e "$out" || -L "$out" ]] && [[ "$out" == "$SANDBOX"/kh.* ]]; then
    _report "$label" bad "writer rejected but left a file at $out"; return
  fi
  _report "$label" ok
}

# ── P: must-PASS ───────────────────────────────────────────────────────────────────────
expect_pass "P1: the committed web-1 pin file is accepted verbatim" web-1 "@$PIN" "$COMMITTED"
expect_pass "P2: a generated ECDSA-P256 key" web-1 "$EC"$'\n' "$EC"
expect_pass "P3: a generated ED25519 key (git-data)" git-data "$ED"$'\n' "$ED"
expect_pass "P4: header comments, blank lines and CRLF endings are tolerated" web-1 \
  $'# captured by fixture\r\n#   fingerprint: SHA256:x\r\n\r\n'"$EC"$'\r\n\r\n' "$EC"
expect_pass "P5: no trailing newline" git-data "$ED" "$ED"
expect_pass "P6: an indented comment line is a comment" web-1 $'   # indented\n'"$EC"$'\n' "$EC"

# P7: the cutover workflow's two-alias append into ONE file, then mode 0444.
cases=$((cases + 1))
KH2="$SANDBOX/gd-known-hosts"
run_writer "$WRITER" web-1 "@$PIN" "$KH2"; rc1=$RC
run_writer "$WRITER" git-data "$ED"$'\n' "$KH2"; rc2=$RC
want2="$(printf 'web-1 %s\ngit-data %s' "$COMMITTED" "$ED")"
if [[ "$rc1" -eq 0 && "$rc2" -eq 0 && "$(<"$KH2")" == "$want2" ]]; then
  _report "P7: two aliases append into one known_hosts file" ok
else _report "P7: two aliases append into one known_hosts file" bad "rc=$rc1/$rc2 content=[$(<"$KH2")]"; fi

# ── S: structure of the written file and stdout ──────────────────────────────────────
cases=$((cases + 1))
mode="$(stat -c '%a' "$KH2" 2>/dev/null || stat -f '%Lp' "$KH2")"
if [[ "$mode" == 444 ]]; then _report "S1: known_hosts is mode 0444" ok
else _report "S1: known_hosts is mode 0444" bad "mode=$mode"; fi

cases=$((cases + 1))
run_writer "$WRITER" web-1 "$EC"$'\n' "$SANDBOX/kh.s2"
ec_body="$(cut -d' ' -f2 <<<"$EC")"
want_fp="$(ssh-keygen -lf "$SANDBOX/ec.pub" | awk '{ print $2 }')"
if [[ "$RC" -eq 0 && "$STDOUT" == *" $want_fp"* && "$STDOUT$STDERR" != *"$ec_body"* ]]; then
  _report "S2: output names the SHA256 fingerprint and never prints the key body" ok
else _report "S2: output names the SHA256 fingerprint and never prints the key body" bad "rc=$RC out=[$STDOUT]"; fi

cases=$((cases + 1))
if grep -qE '\[\[ \$[A-Za-z_]+ =~ \$RE \]\]' "$WRITER" && ! grep -qE '=~ "\$RE"' "$WRITER"; then
  _report "S3: the writer matches with an UNQUOTED \$RE" ok
else _report "S3: the writer matches with an UNQUOTED \$RE" bad "expected \`[[ \$pin =~ \$RE ]]\`"; fi

cases=$((cases + 1))
twins="$(grep -c '# twin:' "$WRITER" || true)"
if [[ "$twins" -ge 2 ]]; then _report "S4: each regex carries a '# twin:' comment ($twins)" ok
else _report "S4: each regex carries a '# twin:' comment" bad "found $twins"; fi

# ── R: must-REJECT (Guard 3 mutation rows + writer arms) ─────────────────────────────
expect_reject "R1 (G3 row 1): valid pin plus an injected '* ssh-rsa' wildcard line" web-1 \
  "$EC"$'\n'"* $RSA"$'\n'
expect_reject "R1b: valid pin with a CR-smuggled second key on the same line" web-1 \
  "$EC"$'\r'"* $RSA"$'\n'
expect_reject "R2 (G3 row 2): trailing comment 'host@x'" web-1 "$EC host@x"$'\n'
expect_reject "R2b: trailing whitespace" web-1 "$EC "$'\n'
expect_reject "R3 (G3 row 3): an ssh-rsa key" web-1 "$RSA"$'\n'
expect_reject "R3b (G3 row 3): a truncated ECDSA key (139-char body)" web-1 "${EC:0:$((${#EC} - 2))}="$'\n'
expect_reject "R3c: a truncated ED25519 key" git-data "${ED:0:$((${#ED} - 1))}"$'\n'
expect_reject "R3d: an ECDSA key with one extra base64 char" web-1 "${EC%=}A="$'\n'
expect_reject "R4 (G3 row 4): two key lines (exactly one required)" web-1 "$EC"$'\n'"$EC"$'\n'
expect_reject "R4b: an ECDSA and an ED25519 line together" web-1 "$EC"$'\n'"$ED"$'\n'
expect_reject "R5: zero key lines (comments only)" web-1 $'# PLACEHOLDER\n# nothing here\n'
expect_reject "R5b: empty file" web-1 ""
expect_reject "R6: a leading space before the key" web-1 " $EC"$'\n'
expect_reject "R7: a host-pattern prefix ('* ecdsa…')" web-1 "* $EC"$'\n'
expect_reject "R7b: an @cert-authority marker" web-1 "@cert-authority * $EC"$'\n'
expect_reject "R7c: a tab between type and body" web-1 "${EC/ /$'\t'}"$'\n'
expect_reject "R8: an unsupported algorithm name with a valid-looking body" web-1 \
  "ecdsa-sha2-nistp384 ${EC#* }"$'\n'
expect_reject "R9: a relative out path" web-1 "$EC"$'\n' "relative/known_hosts"
expect_reject "R9b: an out path with a space (callers expand \${WEB_HOST_SSH} unquoted)" web-1 \
  "$EC"$'\n' "$SANDBOX/kh with space"
expect_reject "R9c: an out path with a shell metacharacter" web-1 "$EC"$'\n' "$SANDBOX/kh;x"
expect_reject "R10: an alias carrying a host pattern" '*' "$EC"$'\n'
expect_reject "R10b: an alias with a space" 'web 1' "$EC"$'\n'
expect_reject "R10c: an empty alias" '' "$EC"$'\n'
expect_reject "R11: a missing pin file" web-1 "@$SANDBOX/does-not-exist"

# R12: an out path that is a symlink is refused (and its target is not written).
cases=$((cases + 1))
: > "$SANDBOX/victim"
ln -s "$SANDBOX/victim" "$SANDBOX/kh.link"
run_writer "$WRITER" web-1 "$EC"$'\n' "$SANDBOX/kh.link"
if [[ "$RC" -ne 0 && ! -s "$SANDBOX/victim" ]]; then _report "R12: a symlinked out path is refused" ok
else _report "R12: a symlinked out path is refused" bad "rc=$RC victim=[$(<"$SANDBOX/victim")]"; fi

# R13: a second entry for an alias already present is refused, and the file is unchanged.
cases=$((cases + 1))
before="$(<"$KH2")"
run_writer "$WRITER" web-1 "$EC"$'\n' "$KH2"
if [[ "$RC" -ne 0 && "$(<"$KH2")" == "$before" ]]; then _report "R13: a duplicate alias is refused" ok
else _report "R13: a duplicate alias is refused" bad "rc=$RC"; fi

# R15-R21: the writer refuses to EXTEND an out file it cannot vouch for, and the file is unchanged.
# expect_refuse_extend <label> <alias> <pin-content> <pre-seeded out content> <want-reason>
expect_refuse_extend() {
  local label="$1" alias="$2" content="$3" seed="$4" reason="$5" f
  cases=$((cases + 1))
  f="$SANDBOX/seed.$((n + 1))"
  assert_fixture_dir "$f"
  printf '%s' "$seed" > "$f"
  run_writer "$WRITER" "$alias" "$content" "$f"
  if [[ "$RC" -ne 0 && "$(<"$f")" == "${seed%$'\n'}" && "$STDOUT" == *"reason=$reason"* ]]; then _report "$label" ok
  else _report "$label" bad "rc=$RC stdout=[$STDOUT] file-changed=$([[ "$(<"$f")" == "${seed%$'\n'}" ]] && echo no || echo yes)"; fi
}
expect_refuse_extend "R15: a pre-seeded @cert-authority line refuses the append" git-data "$ED"$'\n' \
  "@cert-authority * $EC"$'\n' foreign_line
expect_refuse_extend "R16: a duplicate alias on line 2 refuses" web-1 "$EC"$'\n' \
  "git-data $ED"$'\n'"web-1 $EC"$'\n' alias_present
expect_refuse_extend "R16b: a host-pattern line naming the alias ('web-1,foo') refuses" web-1 "$EC"$'\n' \
  "web-1,foo $EC"$'\n' alias_present
expect_refuse_extend "R16c: a wildcard host line ('*') refuses" web-1 "$EC"$'\n' \
  "* $EC"$'\n' alias_present
expect_refuse_extend "R16d: a foreign pattern line for ANOTHER host ('other,web-2') refuses" web-1 "$EC"$'\n' \
  "other,web-2 $EC"$'\n' foreign_line
expect_refuse_extend "R16e: a comment line in the out file refuses" web-1 "$EC"$'\n' \
  "# seeded"$'\n'"git-data $ED"$'\n' foreign_line
expect_refuse_extend "R16f: a CR on an otherwise valid prior line refuses" web-1 "$EC"$'\n' \
  "git-data $ED"$'\r\n' foreign_line
expect_refuse_extend "R16g: a prior ssh-rsa line refuses" web-1 "$EC"$'\n' \
  "git-data $RSA"$'\n' foreign_line

# R17: an out path that is a directory.
cases=$((cases + 1))
mkdir -p "$SANDBOX/kh.dir"
run_writer "$WRITER" web-1 "$EC"$'\n' "$SANDBOX/kh.dir"
if [[ "$RC" -ne 0 && "$STDOUT" == *"reason=out_not_regular"* && -z "$(ls -A "$SANDBOX/kh.dir")" ]]; then
  _report "R17: an out path that is a directory is refused" ok
else _report "R17: an out path that is a directory is refused" bad "rc=$RC stdout=[$STDOUT]"; fi

expect_reject "R18: ED25519 with a trailing comment ' host@x'" git-data "$ED host@x"$'\n'
expect_reject "R18b: ED25519 with a trailing space" git-data "$ED "$'\n'
expect_reject "R19: an out path with a '..' segment" web-1 "$EC"$'\n' "$SANDBOX/sub/../kh.dots"

# R22: the refusal annotation is fixed-vocabulary and never carries file bytes.
cases=$((cases + 1))
f="$SANDBOX/seed.r22"
printf '@cert-authority * %s\n' "$EC" > "$f"
run_writer "$WRITER" git-data "$ED"$'\n' "$f"
if [[ "$RC" -eq 1 && "$STDOUT" == "::error title=write-known-hosts::verdict=pin_refused alias=git-data reason=foreign_line" \
      && "$STDOUT$STDERR" != *"$ec_body"* && "$STDOUT$STDERR" != *"cert-authority"* ]]; then
  _report "R22: refusal annotation is 'verdict=pin_refused alias=<alias> reason=<word>' with no file bytes" ok
else _report "R22: refusal annotation shape" bad "rc=$RC stdout=[$STDOUT] stderr=[$STDERR]"; fi
cases=$((cases + 1))
run_writer "$WRITER" 'web 1' "$EC"$'\n' "$SANDBOX/kh.r22b"
if [[ "$RC" -eq 1 && "$STDOUT" == *"alias=invalid reason=alias_invalid"* && "$STDOUT" != *"web 1"* ]]; then
  _report "R22b: an invalid alias is never echoed into the annotation" ok
else _report "R22b: an invalid alias is never echoed into the annotation" bad "stdout=[$STDOUT]"; fi

# R14: wrong argc.
cases=$((cases + 1))
set +e; bash "$WRITER" web-1 "$PIN" >/dev/null 2>&1; rc=$?; set -e
if [[ "$rc" -ne 0 ]]; then _report "R14: two arguments are refused" ok
else _report "R14: two arguments are refused" bad "rc=0"; fi

# ── Q: the quoted-$RE variant must go RED on must-PASS input ─────────────────────────
cases=$((cases + 1))
QUOTED="$SANDBOX/writer-quoted.sh"
sed -E 's/=~ \$RE \]\]/=~ "$RE" ]]/' "$WRITER" > "$QUOTED"
if cmp -s "$WRITER" "$QUOTED"; then
  _report "Q: quoted-\$RE variant rejects a must-PASS pin" bad "mutation did not land"
else
  run_writer "$QUOTED" web-1 "$EC"$'\n' "$SANDBOX/kh.q"
  if [[ "$RC" -ne 0 ]]; then _report "Q: quoted-\$RE variant rejects a must-PASS pin (unquoted form is load-bearing)" ok
  else _report "Q: quoted-\$RE variant rejects a must-PASS pin" bad "the quoted variant ACCEPTED it -- the test cannot tell the forms apart"; fi
fi

# ── Accounting (ADR-193) ─────────────────────────────────────────────────────────────
if [[ $((pass + fail)) -ne "$cases" ]]; then
  printf '[FATAL] accounting: pass+fail (%d) != cases (%d)\n' "$((pass + fail))" "$cases" >&2; exit 1
fi
FLOOR=53
if (( cases < FLOOR )); then
  printf '[FATAL] anti-vacuity floor: only %d cases ran, expected >= %d\n' "$cases" "$FLOOR" >&2; exit 1
fi
echo "=== write-known-hosts: $pass passed, $fail failed ($cases cases) ==="
if (( fail > 0 )); then printf '  - %s\n' "${FAILURES[@]}" >&2; exit 1; fi
