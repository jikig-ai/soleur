#!/usr/bin/env bash
#
# Behavioral suite for install_vector_binary() in inngest-bootstrap.sh: the Vector download
# must survive a stalled transfer.
#
# WHY. On the 2026-09-24 inngest host replace (#8708), the single `curl --max-time 120` timed
# out at 11.9 of 45 MB, the checksum refused the partial file, and the sole scheduler booted
# with no log shipper. There is no way to re-run the install on a live inngest host, so the
# remedy for a lost download is a whole host replace.
#
# HOW. The function is extracted from the real script (never copied) and driven with a stub
# `curl` on PATH. The stub serves a real tarball in scripted slices per attempt, honouring
# `-C -` by appending to the partial file, so each case is a transfer shape rather than a
# mock of the function's internals.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOOTSTRAP="$DIR/inngest-bootstrap.sh"

pass=0; fail=0
ok() { pass=$((pass + 1)); echo "[ok] $1"; }
no() { fail=$((fail + 1)); echo "[FAIL] $1" >&2; }

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

# The function body: from its definition to the first line that closes it at the same indent.
FN="$(awk '/^  install_vector_binary\(\) \{$/{f=1} f{print} f&&/^  \}$/{exit}' "$BOOTSTRAP")"
if [[ -z "$FN" ]] || ! grep -q 'VECTOR_DOWNLOAD_URL' <<<"$FN"; then
  printf '[FATAL] could not extract install_vector_binary from %s\n' "$BOOTSTRAP" >&2
  exit 2
fi

WORK="$(mktemp -d "${TMPDIR:-/tmp}/inngest-vector-dl.XXXXXXXX")"
assert_fixture_dir "$WORK"
trap 'rm -rf "$WORK"' EXIT

# A real tarball with the layout the function installs from.
TRIPLE="x86_64-unknown-linux-musl"
mkdir -p "$WORK/src/vector-$TRIPLE/bin"
printf '#!/bin/sh\necho vector-stub\n' > "$WORK/src/vector-$TRIPLE/bin/vector"
head -c 200000 /dev/urandom >> "$WORK/src/vector-$TRIPLE/bin/vector"
tar -czf "$WORK/vector.tar.gz" -C "$WORK/src" "vector-$TRIPLE"
GOOD_SHA="$(sha256sum "$WORK/vector.tar.gz" | awk '{print $1}')"
SIZE="$(wc -c < "$WORK/vector.tar.gz")"

# Stub curl. PLAN is one token per attempt:
#   partial  -> append the next quarter (rounded up) of the file, exit 28 (a stall). Four
#               only complete the file when each resumes where the last one stopped.
#   rest     -> append everything that is still missing, exit 0
#   full     -> write the whole file from scratch (ignores -C -), exit 0
#   corrupt  -> write a same-sized file of wrong bytes, exit 0
#   late     -> append everything still missing, but exit 28 (the file is complete, curl says no)
#   dead     -> write nothing, exit 7
mkdir -p "$WORK/bin"
cat > "$WORK/bin/curl" <<'STUB'
#!/usr/bin/env bash
n=$(( $(cat "$STUB_DIR/attempts") + 1 )); echo "$n" > "$STUB_DIR/attempts"
out=""; prev=""
for a in "$@"; do [[ "$prev" == "-o" ]] && out="$a"; prev="$a"; done
step="$(sed -n "${n}p" "$STUB_DIR/plan")"
# Without `-C -`, real curl starts the file over; model that, so dropping resume is caught.
resume=0; for a in "$@"; do [[ "$a" == "-C" ]] && resume=1; done
[[ "$resume" -eq 1 ]] || : > "$out"
have=0; [[ -f "$out" ]] && have=$(wc -c < "$out")
case "$step" in
  partial) chunk=$(( (STUB_SIZE + 3) / 4 )); tail -c +$((have + 1)) "$STUB_SRC" | head -c "$chunk" >> "$out"; exit 28 ;;
  rest)    tail -c +$((have + 1)) "$STUB_SRC" >> "$out"; exit 0 ;;
  full)    cat "$STUB_SRC" > "$out"; exit 0 ;;
  corrupt) head -c "$STUB_SIZE" /dev/zero > "$out"; exit 0 ;;
  late)    tail -c +$((have + 1)) "$STUB_SRC" >> "$out"; exit 28 ;;
  *)       exit 7 ;;
esac
STUB
chmod +x "$WORK/bin/curl"
printf '#!/bin/sh\nexit 0\n' > "$WORK/bin/sleep"; chmod +x "$WORK/bin/sleep"

# run_case <name> <plan...> -> sets RC, ATTEMPTS, INSTALLED
run_case() {
  local name="$1"; shift
  local c="$WORK/case-$name"
  assert_fixture_dir "$c"
  mkdir -p "$c"
  printf '%s\n' "$@" > "$c/plan"
  echo 0 > "$c/attempts"
  RC=0
  PATH="$WORK/bin:$PATH" STUB_DIR="$c" STUB_SRC="$WORK/vector.tar.gz" STUB_SIZE="$SIZE" \
    VECTOR_CLI_VERSION=0.43.1 VECTOR_CLI_SHA256="$GOOD_SHA" vec_triple="$TRIPLE" \
    VECTOR_DOWNLOAD_URL="https://packages.example.invalid/vector.tar.gz" \
    VECTOR_INSTALL_PATH="$c/vector" VECTOR_VERSION_FILE="$c/version" \
    bash -c 'set -euo pipefail; log() { echo "[inngest-bootstrap] $*"; }; eval "$1"; install_vector_binary' _ "$FN" \
    > "$c/log" 2>&1 || RC=$?
  ATTEMPTS="$(cat "$c/attempts")"
  INSTALLED=0
  if [[ -x "$c/vector" ]] && grep -q 'vector-stub' "$c/vector"; then INSTALLED=1; fi
}

# 1. The incident: a stalled transfer, then the rest. Resumes and installs.
run_case stall-then-resume partial rest
if [[ "$RC" -eq 0 && "$INSTALLED" -eq 1 && "$ATTEMPTS" -eq 2 ]]; then
  ok "stall then resume: installs on attempt 2 (the 2026-09-24 shape)"
else
  no "stall then resume: rc=$RC installed=$INSTALLED attempts=$ATTEMPTS"
fi

# 2. Every attempt stalls after a quarter of the file. Only resuming (-C -) ever completes it.
run_case four-stalls partial partial partial partial
if [[ "$RC" -eq 0 && "$INSTALLED" -eq 1 && "$ATTEMPTS" -eq 4 ]]; then
  ok "four stalls: progress accumulates across attempts, installs on attempt 4"
else
  no "four stalls: rc=$RC installed=$INSTALLED attempts=$ATTEMPTS"
fi

# 3. The network never answers: bounded at 4 attempts, returns non-zero, installs nothing.
run_case dead dead dead dead dead dead
if [[ "$RC" -ne 0 && "$INSTALLED" -eq 0 && "$ATTEMPTS" -eq 4 ]]; then
  ok "dead network: gives up after 4 attempts with a non-zero return"
else
  no "dead network: rc=$RC installed=$INSTALLED attempts=$ATTEMPTS"
fi

# 4. Wrong bytes with rc 0 are discarded, never resumed onto; the next attempt starts clean.
run_case corrupt-then-good corrupt rest
if [[ "$RC" -eq 0 && "$INSTALLED" -eq 1 && "$ATTEMPTS" -eq 2 ]] \
  && grep -q 'sha256 mismatch; discarding' "$WORK/case-corrupt-then-good/log"; then
  ok "wrong bytes: discarded, clean retry installs"
else
  no "wrong bytes: rc=$RC installed=$INSTALLED attempts=$ATTEMPTS"
fi

# 5. A complete file that comes back with a non-zero rc is still accepted on its checksum,
#    and the loop stops there rather than asking for a range past the end.
run_case complete-but-late partial late
if [[ "$RC" -eq 0 && "$INSTALLED" -eq 1 && "$ATTEMPTS" -eq 2 ]]; then
  ok "complete file: accepted on its checksum and stops retrying"
else
  no "complete file: rc=$RC installed=$INSTALLED attempts=$ATTEMPTS"
fi

# 6. Consistently wrong bytes never install.
run_case always-corrupt corrupt corrupt corrupt corrupt
if [[ "$RC" -ne 0 && "$INSTALLED" -eq 0 && "$ATTEMPTS" -eq 4 ]]; then
  ok "always-wrong bytes: never installs"
else
  no "always-wrong bytes: rc=$RC installed=$INSTALLED attempts=$ATTEMPTS"
fi

echo "=== inngest-vector-download: $pass passed, $fail failed ==="
[[ "$fail" -eq 0 ]]
