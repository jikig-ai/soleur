#!/usr/bin/env bash
# Mutation harness for Guard 1 (tests/scripts/test-no-tofu-ssh.sh), #7226 / ADR-237.
#
# Every row runs the REAL guard against a TEMP COPY of the tree (tracked + new files,
# minus knowledge-base/**), mutated one way, then restored from the copy's index. The
# real worktree is never written.
#
#   (SHKC = the StrictHost-KeyChecking option, UKHF = the UserKnown-HostsFile option,
#   KHC = the KnownHosts-Command option; spelled split here so this header is not itself
#   a Guard 1 hit)
#
#   row  mutation                                                        expected
#   1    the bridge's pinned SHKC=yes flipped back to accept-new          RED
#   2    enumeration over an empty tree (0 files scanned)                RED
#   3    bridge compliant; lower-case `shkc no` in a NEW file            RED
#   4    ssh_config-form `UKHF /dev/null` in git-data-cutover.yml        RED
#   5    a second TOFU literal in git-auth.ts (count 2 != 1)             RED
#   5b   a second TOFU literal appended to the SAME allow-listed line     RED (per-match count)
#   6    an allow-list entry for a path with zero hits                   RED
#   7    keyscan appended into "$KH" in a workflow                       RED
#   8    quoted space form  -o "SHKC accept-new"                         RED
#   9    GIT_SSH_COMMAND carrying SHKC=no in a script                    RED
#   10   -o GlobalKnownHostsFile=/dev/null alone                         PASS
#   A*   one NEW file per header arm (each file matches only that arm):  RED
#        tee -a, pipe on a known-hosts line, `SHKC off`, `=false`, `UKHF none`, YAML
#        `SHKC: no`, `1>`, `|& tee`, `| sudo -n tee`, `| dd of=`, `| sponge`,
#        KHC=<command>
#   A-pass  KHC none                                                     PASS
#   D-<dir> one hit planted in a new file under plugins/ apps/ scripts/ .github/ tests/  RED
#   H-a  guard's verdict stubbed to `exit 0`: the row-1 must-RED check must itself fail
#   H-b  SHKC=yes + UKHF=/tmp/kh                                         PASS
#   K-pass  keyscan into a variable / into ssh-keygen -lf                PASS
#
# Every banned literal below is built by concatenation, so this file has zero Guard 1
# hits and needs no allow-list entry.
#
# The unmutated copy must be GREEN first; a RED baseline aborts (a RED row proves
# nothing when the tree is already red).
#
# Env: NO_TOFU_SRC  tree to copy (default: this repo's toplevel).
set -euo pipefail

export TMPDIR="${TMPDIR:-/var/tmp}"
SRC="${NO_TOFU_SRC:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}"
GUARD_REL="tests/scripts/test-no-tofu-ssh.sh"

SHKC="StrictHost""KeyChecking"
UKHF="UserKnown""HostsFile"
GKHF="GlobalKnown""HostsFile"
KHC="KnownHosts""Command"
KS="ssh-""keyscan"
AN="accept""-new"
KH_REF='"$''KH"'                 # the text "$KH", as a workflow would spell it
GT='>'                             # a redirect operator, kept out of this file's own code

pass=0; fail=0; FAILURES=()
_report() {
  if [[ "$2" == ok ]]; then pass=$((pass + 1)); echo "[ok] $1"
  else fail=$((fail + 1)); FAILURES+=("$1"); echo "[FAIL] $1 ${3:-}" >&2; fi
}
# Instrument self-test (ADR-193): both reporter arms must move a counter, then unwind.
_report "instrument self-test (pass arm)" ok
_report "instrument self-test (fail arm)" bad "(expected; unwound)"
(( pass == 1 && fail == 1 )) || { echo "FAIL: reporter self-test" >&2; exit 1; }
pass=0; fail=0; FAILURES=()

WORK="$(mktemp -d "$TMPDIR/no-tofu-mut.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
COPY="$WORK/tree"; EMPTY="$WORK/empty"
mkdir -p "$COPY" "$EMPTY"

git -C "$SRC" ls-files -z --cached --others --exclude-standard -- . ':(exclude)knowledge-base/**' \
  | (cd "$SRC" && tar --null --ignore-failed-read -T - -cf - 2>/dev/null) | tar -C "$COPY" -xf -
git -C "$COPY" init -q
git -C "$COPY" add -A >/dev/null 2>&1
git -C "$EMPTY" init -q

GUARD="$COPY/$GUARD_REL"
[[ -r "$GUARD" ]] || { echo "FAIL: guard not found in copy at $GUARD_REL" >&2; exit 1; }

_restore() { git -C "$COPY" checkout -q -- . && git -C "$COPY" clean -fdq; }
_run_guard() { bash "$GUARD" >"$WORK/out" 2>&1; }   # rc of the guard

# expect_red LABEL: the guard must exit non-zero. Returns 0 when that held.
_check_red()  { if _run_guard; then return 1; else return 0; fi; }
_check_pass() { _run_guard; }

# _row_red LABEL NEEDLE: RED, and RED for this mutation (the output names NEEDLE).
_row_red() {
  local label="$1" needle="$2"
  if _check_red; then
    if grep -qF -- "$needle" "$WORK/out"; then _report "$label -> RED" ok
    else _report "$label -> RED for the right reason" bad "(output does not name '$needle')"; sed 's/^/    /' "$WORK/out" >&2; fi
  else _report "$label -> RED" bad "(guard PASSED on a mutated tree)"; sed 's/^/    /' "$WORK/out" >&2; fi
  _restore
}
_row_pass() {
  local label="$1"
  if _check_pass; then _report "$label -> PASS" ok
  else _report "$label -> PASS" bad "(guard failed)"; sed 's/^/    /' "$WORK/out" >&2; fi
  _restore
}

# _plant <relpath> <line>: write one line into a NEW file of the copy.
_plant() { mkdir -p "$(dirname "$COPY/$1")"; printf '%s\n' "$2" > "$COPY/$1"; }

# Baseline: the unmutated copy must be green.
if ! _check_pass; then
  echo "FAIL: baseline copy is RED, so no mutation row can be interpreted. Guard output:" >&2
  sed 's/^/    /' "$WORK/out" >&2
  exit 1
fi
_report "baseline (unmutated copy) -> PASS" ok

BRIDGE="$COPY/.github/actions/cf-tunnel-ssh-bridge/action.yml"
_mutate_bridge() {
  cp "$BRIDGE" "$WORK/bridge.orig"
  sed -i "s/${SHKC}=yes/${SHKC}=${AN}/" "$BRIDGE"
  ! cmp -s "$BRIDGE" "$WORK/bridge.orig"
}

# Row 1
if _mutate_bridge; then _row_red "row 1 bridge pin flipped to ${AN}" "cf-tunnel-ssh-bridge/action.yml"
else _report "row 1 precondition" bad "(bridge carries no ${SHKC}=yes to flip)"; _restore; fi

# Row 2: empty enumeration (0 files). Run the copy's guard pointed at an empty repo.
if NO_TOFU_ROOT="$EMPTY" bash "$GUARD" >"$WORK/out" 2>&1; then
  _report "row 2 empty enumeration -> RED" bad "(guard PASSED over 0 files)"
elif grep -q 'scanned files: 0' "$WORK/out" && grep -q 'scanned-file floor' "$WORK/out" \
     && grep -q 'expects 1 hit(s) and has 0' "$WORK/out"; then
  _report "row 2 empty enumeration -> RED (floor + zero-hit allow-list)" ok
else
  _report "row 2 empty enumeration -> RED for the right reasons" bad; sed 's/^/    /' "$WORK/out" >&2
fi

# Row 3
mkdir -p "$COPY/scripts"
# lower-case key, space-separated value, in a brand-new ssh_config-shaped file
printf 'Host x\n  %s no\n' "${SHKC,,}" > "$COPY/scripts/zz-new-mutation.conf"
_row_red "row 3 lower-case ${SHKC,,} no in a new file" "zz-new-mutation.conf"

# Row 4
printf '            %s /dev/null\n' "$UKHF" >> "$COPY/.github/workflows/git-data-cutover.yml"
_row_red "row 4 ssh_config ${UKHF} /dev/null in cutover.yml" "git-data-cutover.yml:"

# Row 5
printf 'const MUTATION_OPTS = ["-o", "%s=%s"];\n' "$SHKC" "$AN" >> "$COPY/apps/web-platform/server/git-auth.ts"
_row_red "row 5 second TOFU literal in git-auth.ts" "expects 1 hit(s) and has 2"

# Row 5b: the second literal lands on the allow-listed line itself. A per-LINE count stays 1
# here; only the per-MATCH count sees it.
GA="$COPY/apps/web-platform/server/git-auth.ts"
cp "$GA" "$WORK/ga.orig"
sed -i "s/\"${SHKC}=${AN}\"\\];/\"${SHKC}=${AN}\", \"-o\", \"${SHKC}=no\"];/" "$GA"
if cmp -s "$GA" "$WORK/ga.orig"; then _report "row 5b precondition" bad "(allow-listed line not found)"; _restore
else _row_red "row 5b second literal on the SAME allow-listed line" "expects 1 hit(s) and has 2"; fi

# Row 6
sed -i "/^ALLOWLIST=/a apps/web-platform/package.json|1|mutation row 6 (zero hits)" "$GUARD"
_row_red "row 6 zero-hit allow-list entry" "'apps/web-platform/package.json' (mutation row 6 (zero hits)) expects 1 hit(s) and has 0"

# Row 7
_plant .github/workflows/zz-mutation.yml "      - run: $KS 10.0.1.10 ${GT}${GT} ${KH_REF}"
_row_red "row 7 keyscan appended into \$KH in a workflow" "zz-mutation.yml"

# Row 8
printf 'ssh -o "%s %s" host true\n' "$SHKC" "$AN" > "$COPY/scripts/zz-mutation-8.sh"
_row_red "row 8 quoted space form" "zz-mutation-8.sh"

# Row 9
printf 'GIT_SSH_COMMAND="ssh -o %s=no" git fetch\n' "$SHKC" > "$COPY/scripts/zz-mutation-9.sh"
_row_red "row 9 GIT_SSH_COMMAND with =no" "zz-mutation-9.sh"

# A*: one NEW file per arm the header promises. Each line matches only its own arm, so a
# deleted arm leaves its row GREEN and this harness RED.
_arm() { # <n> <label> <line>
  _plant "scripts/zz-arm-$1.txt" "$3"
  _row_red "A$1 $2" "zz-arm-$1.txt"
}
_arm 1  "keyscan | tee -a"                 "$KS -t ecdsa h | tee -a ${KH_REF}"
_arm 2  "keyscan pipe on a known-hosts line" "$KS h 2${GT}/dev/null | install -m 600 /dev/stdin ~/.ssh/known""_hosts"
_arm 3  "ssh_config ${SHKC} off"           "  ${SHKC} off"
_arm 4  "${SHKC}=false"                    "ssh -o ${SHKC}=false host true"
_arm 5  "${UKHF} none"                     "  ${UKHF} none"
_arm 6  "YAML ${SHKC}: no"                 "    ${SHKC}: no"
_arm 7  "keyscan 1${GT}\$KH"               "$KS h 1${GT}${KH_REF}"
_arm 8  "keyscan |& tee"                   "$KS h |& tee kh"
_arm 9  "keyscan | sudo -n tee"            "$KS h | sudo -n tee -a /etc/ssh/pinned"
_arm 10 "keyscan | dd of="                 "$KS h | dd of=/root/.ssh/kh status=none"
_arm 11 "keyscan | sponge"                 "$KS h | sponge /root/.ssh/kh"
_arm 12 "${KHC}=<command>"                 "ssh -o ${KHC}=/usr/local/bin/print-keys host true"
_arm 13 "ssh_config ${KHC} <command>"      "  ${KHC} /usr/local/bin/print-keys %H"
_plant scripts/zz-arm-pass.txt "ssh -o ${KHC}=none host true"
_row_pass "A-pass ${KHC}=none"

# D-<dir>: the enumeration reaches every top-level code directory.
for d in plugins apps scripts .github tests; do
  _plant "$d/zz-dir-probe.sh" "ssh -o ${SHKC}=no host true"
  _row_red "D-$d one hit planted under $d/" "$d/zz-dir-probe.sh"
done

# Row 10
printf 'ssh -o %s=/dev/null host true\n' "$GKHF" > "$COPY/scripts/zz-mutation-10.sh"
_row_pass "row 10 ${GKHF}=/dev/null alone"

# H-b
printf 'ssh -o %s=yes -o %s=/tmp/kh host true\n' "$SHKC" "$UKHF" > "$COPY/scripts/zz-mutation-hb.sh"
_row_pass "H-b ${SHKC}=yes + ${UKHF}=/tmp/kh"

# K-pass: a keyscan captured by command substitution (the capture-script shape) and a
# keyscan piped into ssh-keygen for a fingerprint write no known-hosts file.
# shellcheck disable=SC2016  # the $(...) is literal text written into the planted file
printf 'pin="$(%s -T 10 -t ecdsa 192.0.2.1 2>/dev/null)"\n%s -t ecdsa 192.0.2.1 2>/dev/null | ssh-keygen -lf -\n' "$KS" "$KS" \
  > "$COPY/scripts/zz-mutation-kpass.sh"
_row_pass "K-pass keyscan into a variable / into ssh-keygen -lf"

# H-a: neuter the guard's verdict, then apply row 1. The must-RED check must now FAIL
# (return non-zero), proving the harness cannot be satisfied by a guard that always passes.
sed -i '0,/^set -euo pipefail$/s//set -euo pipefail\nexit 0/' "$GUARD"
if _mutate_bridge; then
  if _check_red; then _report "H-a stubbed guard is caught" bad "(must-RED check still succeeded)"
  else _report "H-a stubbed guard (exit 0) fails the row-1 must-RED check" ok; fi
else
  _report "H-a precondition" bad "(bridge carries no ${SHKC}=yes to flip)"
fi
_restore

echo "test-no-tofu-ssh-mutation: $pass passed, $fail failed"
if (( fail )); then printf '  - %s\n' "${FAILURES[@]}" >&2; exit 1; fi
