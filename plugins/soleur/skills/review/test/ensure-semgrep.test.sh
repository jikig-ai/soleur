#!/usr/bin/env bash
# Hermetic suite for ensure-semgrep.sh (#9964): a resolvable-but-dead semgrep
# must NOT read as present. Every arm runs the SUT under `env -i` with a
# curated PATH — no real brew/pipx/python3/timeout can leak in, and HOME is a
# sandbox dir so the SUT's `$HOME/.local/bin` prepend cannot see the host.

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$SCRIPT_DIR/../scripts/ensure-semgrep.sh"
PASS=0; FAIL=0; TOTAL=0

ok()   { PASS=$((PASS+1)); TOTAL=$((TOTAL+1)); echo "  PASS: $1"; }
no()   { FAIL=$((FAIL+1)); TOTAL=$((TOTAL+1)); echo "  FAIL: $1"; }
assert() { local desc="$1" cond="$2"; if eval "$cond"; then ok "$desc"; else no "$desc"; fi; }

D="" D2="" D3="" D4="" D5="" D6="" D7="" D8="" D9=""
cleanup() { [ -n "$D" ] && rm -rf "$D" "$D2" "$D3" "$D4" "$D5" "$D6" "$D7" "$D8" "$D9"; }
trap cleanup EXIT

# Each arm's dir carries: stubs (semgrep/installers), home/ (empty HOME), and
# tools/ (symlinks to the real coreutils the stubs need — nothing else).
mkarm() {
  local dir
  dir="$(mktemp -d)"
  mkdir -p "$dir/home" "$dir/tools"
  for t in chmod cat printf env ls cp mkdir; do
    command -v "$t" >/dev/null 2>&1 && ln -sf "$(command -v "$t")" "$dir/tools/$t"
  done
  printf '%s\n' "$dir"
}
# run_sut <dir> [extra PATH dirs] — curated env: PATH=dir[:extra], HOME=dir/home.
run_sut() { local dir="$1"; shift; env -i PATH="$dir:$dir/tools${1:+:$1}" HOME="$dir/home" /bin/bash "$SUT"; }

dead_semgrep() { printf '#!/bin/sh\necho "ModuleNotFoundError: No module named semgrep" >&2\nexit 1\n' >"$1/semgrep"; chmod +x "$1/semgrep"; }
live_semgrep() { printf '#!/bin/sh\nif [ "$1" = "--version" ]; then echo "1.99.0"; exit 0; fi\nexit 0\n' >"$1/semgrep"; chmod +x "$1/semgrep"; }
probe_semgrep() { printf '#!/bin/sh\necho "$1" >>"%s/probe-log"\nif [ "$1" = "--version" ]; then echo "1.99.0"; exit 0; fi\nexit 0\n' "$1" >"$1/semgrep"; chmod +x "$1/semgrep"; }
# installer stubs assert argv fidelity AND record invocation AND "install" a
# probe-logging semgrep by copying the arm's pre-written `installed` stub to
# the target (the SUT re-probes after install — every rc-0 path must show
# --version ran).
write_installed() { printf '#!/bin/sh\necho "$1" >>"%s/probe-log"\nif [ "$1" = "--version" ]; then echo "1.99.0"; exit 0; fi\nexit 0\n' "$1" >"$1/installed"; chmod +x "$1/installed"; }
install_brew() {
  write_installed "$1"
  printf '#!/bin/sh\necho "brew:$1:$2" >>"%s/called"\nif [ "$1" = "install" ] && [ "$2" = "semgrep" ]; then cp "%s/installed" "%s/semgrep"; chmod +x "%s/semgrep"; exit 0; fi\nexit 1\n' "$1" "$1" "$1" "$1" >"$1/brew"; chmod +x "$1/brew"
}
fail_stub() { printf '#!/bin/sh\necho "%s" >>"%s/called"\nexit 1\n' "$2" "$1" >"$1/$2"; chmod +x "$1/$2"; }

# --- arm A: live semgrep on PATH → rc 0, no installer invoked --------------
D="$(mkarm)"; live_semgrep "$D"; fail_stub "$D" brew; fail_stub "$D" pipx
OUT="$(run_sut "$D" 2>/dev/null)"; RC=$?
assert "live semgrep: exit 0 and its path printed" "[ $RC -eq 0 ] && printf '%s' \"$OUT\" | grep -q '/semgrep$'"
assert "live semgrep: NO installer invoked" "[ ! -f '$D/called' ]"

# --- arm B: dead shim + working brew → installs, re-probes, rc 0 -----------
D2="$(mkarm)"; dead_semgrep "$D2"; install_brew "$D2"
run_sut "$D2" >/dev/null 2>&1; RC=$?
assert "dead shim + brew: exit 0 after install" "[ $RC -eq 0 ] && grep -q 'brew:install:semgrep' '$D2/called'"
assert "dead shim + brew: the post-install re-probe ran --version" "grep -q -- '--version' '$D2/probe-log'"

# --- arm C: dead shim + NO installer → rc 2, NOT reported present ----------
D3="$(mkarm)"; dead_semgrep "$D3"
ERR="$(run_sut "$D3" 2>&1 >/dev/null)"; RC=$?
assert "dead shim + no installer: exit 2 (shim reads as absent)" "[ $RC -eq 2 ]"
assert "dead shim + no installer: diagnostic names the dead shim" "printf '%s' \"$ERR\" | grep -q 'resolves at'"
assert "dead shim + no installer: points at shim removal, not a missing installer" "printf '%s' \"$ERR\" | grep -qi 'shim'"

# --- arm D: installer produces a still-dead binary → falls through, rc 1 ---
D4="$(mkarm)"; dead_semgrep "$D4"
printf '#!/bin/sh\necho "brew" >>"%s/called"\nexit 0\n' "$D4" >"$D4/brew"; chmod +x "$D4/brew"   # brew "succeeds" but shim stays dead (shadowed)
fail_stub "$D4" pipx; fail_stub "$D4" python3
ERR="$(run_sut "$D4" 2>&1 >/dev/null)"; RC=$?
assert "install-success-but-still-dead: exit 1 (attempted, still dead)" "[ $RC -eq 1 ]"
assert "install-success-but-still-dead: diagnostic names the dead path" "printf '%s' \"$ERR\" | grep -q 'still does not run'"

# --- arm E: absent semgrep + working brew → rc 0 (regression) --------------
D5="$(mkarm)"; install_brew "$D5"
run_sut "$D5" >/dev/null 2>&1; RC=$?
assert "absent + brew: exit 0 with installer invoked AND re-probed" "[ $RC -eq 0 ] && grep -q 'brew:install:semgrep' '$D5/called' && grep -q -- '--version' '$D5/probe-log'"

# --- arm F: dead shim + brew fails + pipx succeeds → rc 0 ------------------
D6="$(mkarm)"; dead_semgrep "$D6"; fail_stub "$D6" brew; fail_stub "$D6" python3
write_installed "$D6"
printf '#!/bin/sh\necho "pipx:$1:$2" >>"%s/called"\nif [ "$1" = "install" ] && [ "$2" = "semgrep" ]; then cp "%s/installed" "%s/home/.local/bin/semgrep"; chmod +x "%s/home/.local/bin/semgrep"; exit 0; fi\nexit 1\n' "$D6" "$D6" "$D6" "$D6" >"$D6/pipx"; chmod +x "$D6/pipx"
mkdir -p "$D6/home/.local/bin"
run_sut "$D6" >/dev/null 2>&1; RC=$?
assert "dead shim + brew fails + pipx installs to HOME/.local/bin: exit 0" "[ $RC -eq 0 ] && grep -q 'pipx:install:semgrep' '$D6/called'"
assert "arm F: the HOME/.local/bin prepend is what made the install visible" "grep -q -- '--version' '$D6/home/.local/bin/probe-log' 2>/dev/null || grep -q -- '--version' '$D6/probe-log'"

# --- arm G: the probe RUNS on every rc-0 path (vacuity pin) ----------------
D7="$(mkarm)"; probe_semgrep "$D7"
run_sut "$D7" >/dev/null 2>&1; RC=$?
assert "probe runs semgrep --version on the rc-0 path" "[ $RC -eq 0 ] && grep -q -- '--version' '$D7/probe-log'"

# --- arm H: python3 -m pip install --user success path, argv-faithful ------
D8="$(mkarm)"; dead_semgrep "$D8"; fail_stub "$D8" brew; fail_stub "$D8" pipx
write_installed "$D8"
printf '#!/bin/sh\necho "python3:$*" >>"%s/called"\nif [ "$1" = "-m" ] && [ "$2" = "pip" ] && [ "$3" = "install" ] && [ "$4" = "--user" ] && [ "$5" = "semgrep" ]; then cp "%s/installed" "%s/home/.local/bin/semgrep"; chmod +x "%s/home/.local/bin/semgrep"; exit 0; fi\nexit 1\n' "$D8" "$D8" "$D8" "$D8" >"$D8/python3"; chmod +x "$D8/python3"
mkdir -p "$D8/home/.local/bin"
run_sut "$D8" >/dev/null 2>&1; RC=$?
assert "dead shim + python3 -m pip --user success: exit 0, argv-faithful" "[ $RC -eq 0 ] && grep -q 'python3:-m pip install --user semgrep' '$D8/called'"
assert "arm H: re-probe ran the pip-installed binary" "grep -q -- '--version' '$D8/probe-log' 2>/dev/null || grep -q -- '--version' '$D8/home/.local/bin/probe-log'"

# --- arm I: installer present but FAILED (nothing installed) → rc 1 ------
D9="$(mkarm)"; dead_semgrep "$D9"; fail_stub "$D9" brew
ERR="$(run_sut "$D9" 2>&1 >/dev/null)"; RC=$?
assert "dead shim + brew fails + nothing else: exit 1 (attempted)" "[ $RC -eq 1 ]"
assert "arm I: rc 1 not rc 2 — an installer WAS attempted" "printf '%s' "$ERR" | grep -q 'still does not run'"

echo
echo "=== ensure-semgrep.test.sh: $PASS passed, $FAIL failed ($TOTAL assertions) ==="
[ "$FAIL" -eq 0 ]
