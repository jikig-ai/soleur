#!/usr/bin/env bash
# Hermetic suite for ensure-semgrep.sh (#9964): a resolvable-but-dead semgrep
# must NOT read as present. PATH-shimmed stubs only; no real brew/pipx/pip.

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$SCRIPT_DIR/ensure-semgrep.sh"
PASS=0; FAIL=0; TOTAL=0

ok()   { PASS=$((PASS+1)); TOTAL=$((TOTAL+1)); echo "  PASS: $1"; }
no()   { FAIL=$((FAIL+1)); TOTAL=$((TOTAL+1)); echo "  FAIL: $1"; }
assert() { local desc="$1" cond="$2"; if eval "$cond"; then ok "$desc"; else no "$desc"; fi; }

# A shim dir is built per arm: stubs named `semgrep`/`brew`/`pipx`/`python3`
# live there; the arm runs the SUT with PATH=<dir>:/usr/bin:/bin.
mkbin() { local dir="$1"; shift; for name in "$@"; do printf '#!/bin/sh\nexit 0\n' >"$dir/$name"; chmod +x "$dir/$name"; done; }
dead_semgrep() { printf '#!/bin/sh\necho "ModuleNotFoundError: No module named %s" >&2\nexit 1\n' semgrep >"$1/semgrep"; chmod +x "$1/semgrep"; }
live_semgrep() { printf '#!/bin/sh\nif [ "$1" = "--version" ]; then echo "1.99.0"; exit 0; fi\nexit 0\n' >"$1/semgrep"; chmod +x "$1/semgrep"; }
# A brew stub that "installs" a live semgrep into $dir (the script's own PATH
# order puts the shim dir first, so installing means replacing the shim file).
install_brew() { local dir="$1"; printf '#!/bin/sh\necho brew >>"%s/called"\nif [ "$2" = "semgrep" ]; then cat >"%s/semgrep" <<EOF\n#!/bin/sh\necho 1.99.0\nEOF\nchmod +x "%s/semgrep"; echo brewed >&2; exit 0; fi\nexit 1\n' "$dir" "$dir" "$dir" >"$dir/brew"; chmod +x "$dir/brew"; }

# --- arm A: live semgrep on PATH → rc 0, no installer invoked --------------
D="$(mktemp -d)"; trap 'rm -rf "$D" "$D2" "$D3" "$D4" "$D5" "$D6" "$D7"' EXIT
live_semgrep "$D"
printf '#!/bin/sh\necho INSTALLED-BREW >>"%s/called"\nexit 1\n' "$D" >"$D/brew"; chmod +x "$D/brew"
PATH="$D:/usr/bin:/bin" bash "$SUT" >/tmp/es-a.out 2>/tmp/es-a.err; RC=$?
assert "live semgrep: exit 0 and its path printed" "[ $RC -eq 0 ] && grep -q semgrep /tmp/es-a.out"
assert "live semgrep: NO installer invoked" "[ ! -f '$D/called' ]"

# --- arm B: dead shim + working brew → installs, re-probes, rc 0 -----------
D2="$(mktemp -d)"; dead_semgrep "$D2"; install_brew "$D2"
PATH="$D2:/usr/bin:/bin" bash "$SUT" >/tmp/es-b.out 2>/tmp/es-b.err; RC=$?
assert "dead shim + brew: exit 0 after install" "[ $RC -eq 0 ] && grep -q brew '$D2/called'"
assert "dead shim + brew: stderr mentions installing" "grep -qi install /tmp/es-b.err"

# --- arm C: dead shim + no installer → rc 2, NOT reported present ---------
D3="$(mktemp -d)"; dead_semgrep "$D3"
PATH="$D3:/usr/bin:/bin" bash "$SUT" >/tmp/es-c.out 2>/tmp/es-c.err; RC=$?
assert "dead shim + no installer: exit 2 (shim reads as absent)" "[ $RC -eq 2 ]"
assert "dead shim + no installer: diagnostic names the dead shim" "grep -q '$D3/semgrep' /tmp/es-c.err || grep -qi shim /tmp/es-c.err"

# --- arm D: installer produces a still-dead binary → falls through, rc 1 ---
D4="$(mktemp -d)"; dead_semgrep "$D4"
printf '#!/bin/sh\nexit 0\n' >"$D4/brew"; chmod +x "$D4/brew"   # brew "succeeds" but shim stays dead (shadowed)
printf '#!/bin/sh\nexit 1\n' >"$D4/pipx"; chmod +x "$D4/pipx"
printf '#!/bin/sh\nexit 1\n' >"$D4/python3"; chmod +x "$D4/python3"
PATH="$D4:/usr/bin:/bin" bash "$SUT" >/tmp/es-d.out 2>/tmp/es-d.err; RC=$?
assert "install-success-but-still-dead: exit 1 (attempted, still dead)" "[ $RC -eq 1 ]"
assert "install-success-but-still-dead: diagnostic names the dead path" "grep -q 'semgrep' /tmp/es-d.err"

# --- arm E: absent semgrep + working brew → rc 0 (regression) --------------
D5="$(mktemp -d)"; install_brew "$D5"
PATH="$D5:/usr/bin:/bin" bash "$SUT" >/tmp/es-e.out 2>/tmp/es-e.err; RC=$?
assert "absent + brew: exit 0" "[ $RC -eq 0 ]"

# --- arm F: dead shim + brew fails + pipx succeeds → rc 0 ------------------
D6="$(mktemp -d)"; dead_semgrep "$D6"
printf '#!/bin/sh\nexit 1\n' >"$D6/brew"; chmod +x "$D6/brew"
printf '#!/bin/sh\necho pipx >>"%s/called"\ncat >"%s/semgrep" <<EOF\n#!/bin/sh\necho 1.99.0\nEOF\nchmod +x "%s/semgrep"; exit 0\n' "$D6" "$D6" "$D6" >"$D6/pipx"; chmod +x "$D6/pipx"
printf '#!/bin/sh\nexit 1\n' >"$D6/python3"; chmod +x "$D6/python3"
PATH="$D6:/usr/bin:/bin" bash "$SUT" >/tmp/es-f.out 2>/tmp/es-f.err; RC=$?
assert "dead shim + brew fails + pipx installs: exit 0" "[ $RC -eq 0 ] && grep -q pipx '$D6/called'"

# --- arm G: the probe RUNS on every rc-0 path (vacuity pin) ----------------
# A probe that never executes semgrep cannot prove runs-ability: instrument
# the shim to record --version invocations.
D7="$(mktemp -d)"
printf '#!/bin/sh\necho "$1" >>"%s/probe-log"\nif [ "$1" = "--version" ]; then echo 1.99.0; exit 0; fi\nexit 0\n' "$D7" >"$D7/semgrep"; chmod +x "$D7/semgrep"
PATH="$D7:/usr/bin:/bin" bash "$SUT" >/dev/null 2>&1; RC=$?
assert "probe runs semgrep --version on the rc-0 path" "[ $RC -eq 0 ] && grep -q -- '--version' '$D7/probe-log'"

echo
echo "=== ensure-semgrep.test.sh: $PASS passed, $FAIL failed ($TOTAL assertions) ==="
[ "$FAIL" -eq 0 ]
