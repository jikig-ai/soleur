#!/usr/bin/env bash
# Suite for plugins/soleur/scripts/lib/operator-script.sh (#8287 Phase 2).
#
# Written BEFORE the library, to drive Guards 3 and 4 red first.
#
# Hosts three guards (the surviving set per the plan's Deepen-Plan Ruling 1 —
# Guards 1 and 2 are cut with the inlined-library mode, Guard 5 is REDUCED to a
# single prologue/scope assertion):
#
#   Guard 3  — the library is the only secret-writing path, and it writes safely.
#   Guard 4  — every prompt has a total non-interactive path, re-specified
#              against R8's THREE carve-out classes (the destructive-write ack
#              takes NO skip variable; a guard that demanded one would go green
#              over an hr-menu-option-ack-not-prod-write-auth violation).
#   Guard 5' — every script that sources the library and acquires a credential
#              carries its xtrace/TLS prologue ABOVE its `source` line, and the
#              library itself never expands a secret-shaped variable name.
#
# EVERY mutation row is proven to LAND (md5 against a pristine copy) before it is
# asked to drive a guard red. A mutation that does not land re-runs the baseline,
# and a baseline pass is indistinguishable from a real one.
#
# `shellcheck` is NOT available on this host (a mise shim with no version set —
# it resolves on PATH but cannot execute), so `bash -n` is the syntax gate here.
# Do not add a shellcheck invocation to this suite without first proving the
# binary runs.
#
# Run via:  bash plugins/soleur/test/operator-script.test.sh
set -uo pipefail

# `/tmp` on this host is a contended 4 GiB tmpfs; every sandbox goes to /var/tmp
# unless the caller has already chosen somewhere.
export TMPDIR="${TMPDIR:-/var/tmp}"
export LC_ALL=C

SUITE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="${SUITE_DIR}/../scripts/lib/operator-script.sh"
PLUGIN_ROOT="$(cd "${SUITE_DIR}/.." && pwd)"

# The value that must NEVER appear on stdout, in the run ledger, or on argv.
# Asserted as an ABSENCE, not only as a presence somewhere else: a ledger that
# records the right key name AND the value would pass a presence-only check.
SENTINEL='SENTINEL-NEVER-PRINT-a1b2c3d4'

fails=0
asserts=0
PASS_COUNT=0
FAIL_COUNT=0

pass() { asserts=$((asserts + 1)); PASS_COUNT=$((PASS_COUNT + 1)); echo "  [ok] $1"; }
fail() { asserts=$((asserts + 1)); FAIL_COUNT=$((FAIL_COUNT + 1)); fails=$((fails + 1)); echo "  [FAIL] $1" >&2; }

# --- ADR-193 instrument self-test -------------------------------------------
# Drive BOTH assertion helpers once each and refuse to continue unless BOTH
# counters moved. Reported through `printf` + `exit`, never through the helpers
# it backstops — a self-test that reports via the instrument it is testing cannot
# fail when that instrument is the thing that is broken.
_st_p=$PASS_COUNT; _st_f=$FAIL_COUNT
pass "instrument self-test: pass() reached" >/dev/null
fail "instrument self-test: fail() reached (expected, not a real failure)" 2>/dev/null
if [[ "$PASS_COUNT" -ne $((_st_p + 1)) || "$FAIL_COUNT" -ne $((_st_f + 1)) ]]; then
  printf 'INSTRUMENT SELF-TEST FAILED: pass/fail helpers did not both move (pass %s->%s, fail %s->%s)\n' \
    "$_st_p" "$PASS_COUNT" "$_st_f" "$FAIL_COUNT" >&2
  exit 2
fi
fails=0; asserts=0; PASS_COUNT=0; FAIL_COUNT=0
echo "  [ok] instrument self-test: both helpers dispatch"
asserts=$((asserts + 1)); PASS_COUNT=$((PASS_COUNT + 1))

[[ -r "$LIB" ]] || { printf 'HARNESS: library not readable at %s\n' "$LIB" >&2; exit 2; }
command -v timeout >/dev/null 2>&1 || { printf 'HARNESS: `timeout` is required for the no-TTY probes\n' >&2; exit 2; }
command -v md5sum  >/dev/null 2>&1 || { printf 'HARNESS: `md5sum` is required for mutation-landing proof\n' >&2; exit 2; }
command -v perl    >/dev/null 2>&1 || { printf 'HARNESS: `perl` is required to apply the mutations\n' >&2; exit 2; }

SB="$(mktemp -d -t operator-script.XXXXXXXX)" || { printf 'HARNESS: mktemp failed\n' >&2; exit 2; }
trap 'chmod -R u+rwx "$SB" 2>/dev/null; rm -rf "$SB"' EXIT
mkdir -p "$SB/bin" "$SB/mut" "$SB/run" "$SB/empty" || { printf 'HARNESS: mkdir failed\n' >&2; exit 2; }

PRISTINE="$SB/pristine-operator-script.sh"
cp "$LIB" "$PRISTINE"

# --- stubs -------------------------------------------------------------------
# `gh` records its full argv, so an argv-borne secret is OBSERVED the way `ps`
# would observe it rather than merely asserted about the source text.
cat > "$SB/bin/gh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${GH_ARGV_LOG:-/dev/null}"
case "$1 $2" in
  # Consume stdin ONLY for the secret write, the one call that has a writer.
  # An unconditional `cat` blocks forever on whatever stdin the runner inherited.
  "secret set")    cat >/dev/null 2>&1 || true; exit 0 ;;
  "secret list")   printf 'STUBBED_SECRET\tupdated\n'; exit 0 ;;
  "variable list") printf 'STUBBED_VAR\tvalue\n'; exit 0 ;;
esac
exit 0
STUB
chmod +x "$SB/bin/gh"
export PATH="$SB/bin:$PATH"

# --- driver ------------------------------------------------------------------
# Sources the library named in $1 and dispatches $2 with the remaining argv, in a
# CHILD process — exit codes are part of the contract and cannot be observed from
# the suite's own shell.
cat > "$SB/drive.sh" <<'DRIVER'
#!/usr/bin/env bash
set -uo pipefail
_lib="$1"; shift
_fn="$1"; shift
# shellcheck source=/dev/null
source "$_lib"
"$_fn" "$@"
DRIVER
chmod +x "$SB/drive.sh"

# A FIFO whose write end this suite holds open forever gives the child a pipe
# that is OPEN but SILENT: `read` BLOCKS there, which is what makes "the TTY
# check must precede the read" observable. A plain `</dev/null` hands the read an
# immediate EOF, and a reordered check then looks identical to a compliant one.
#
# Held open with `exec 9<>`, NOT `< <(sleep N)`: measured, the process
# substitution made every `$(...)` capture wait for the sleep to expire and took
# the suite from ~20s to 113s.
BLOCK_FIFO="$SB/blocked-stdin.fifo"
mkfifo "$BLOCK_FIFO" || { printf 'HARNESS: mkfifo failed\n' >&2; exit 2; }
exec 9<>"$BLOCK_FIFO"

drive_blocked() {
  local lib="$1"; shift
  timeout 5 bash "$SB/drive.sh" "$lib" "$@" <"$BLOCK_FIFO" 2>&1
}

md5_of() { md5sum "$1" | cut -d' ' -f1; }

# mutate <label> <dst>  — applies the perl program on stdin to a fresh copy of the
# pristine library, then PROVES the edit landed and still parses.
mutate() {
  local label="$1" dst="$2" prog
  prog="$(cat)"
  cp "$PRISTINE" "$dst"
  perl -0777 -pi -e "$prog" "$dst"
  if [[ "$(md5_of "$dst")" == "$(md5_of "$PRISTINE")" ]]; then
    fail "mutation '${label}' did NOT land (md5 identical to pristine) — the row below would have re-run the baseline"
    return 1
  fi
  if ! bash -n "$dst" 2>/dev/null; then
    fail "mutation '${label}' produced a library that fails bash -n"
    return 1
  fi
  pass "mutation '${label}' landed (md5 differs from pristine; bash -n clean)"
  return 0
}

assert_red() {
  local guard="$1" label="$2"; shift 2
  local out rc
  out="$("$guard" "$@" 2>&1)"; rc=$?
  if [[ "$rc" -ne 0 ]]; then
    pass "${label}: drove ${guard} RED"
  else
    fail "${label}: ${guard} stayed GREEN over the mutation — the guard does not see it"
  fi
}

assert_green() {
  local guard="$1" label="$2"; shift 2
  local out rc
  out="$("$guard" "$@" 2>&1)"; rc=$?
  if [[ "$rc" -eq 0 ]]; then
    pass "${label}: ${guard} GREEN"
  else
    fail "${label}: ${guard} unexpectedly RED:
${out}"
  fi
}

# =============================================================================
# Guard 3 — the library is the only secret-writing path, and it writes safely
# =============================================================================
#
# Property. No code path in the library or in any script sourcing it writes a
# secret to process argv, to a file more permissive than 0600, to stdout, or to
# the run ledger; and an upsert of key K never removes a different key that
# merely starts with K.
#
# The sourcing population is DISCOVERED (`grep -rl` on the source line), never
# enumerated — a frozen list stops seeing the next consumer.
# hr-write-boundary-sentinel-sweep-all-write-sites: the argv sweep covers every
# discovered consumer, not only the new library.
#
# Row 4 RE-SPECIFICATION. The plan's original row 4 mutated a secret REGISTRY and
# an output-scrub trap. R5 cut both (an output-rewriting trap fails open on
# SIGKILL and duplicates a lint that runs in CI where the trap cannot). The
# property that row bought survives and is re-keyed onto the run ledger, which
# does ship: the ledger carries NAMES, never VALUES, so the row mutates the
# ledger into recording the value.

g3_sourcing_scripts() {
  local root="$1"
  grep -rl --include='*.sh' -e 'lib/operator-script\.sh' "$root" 2>/dev/null \
    | grep -v '\.test\.sh$' \
    | grep -v 'scripts/lib/operator-script\.sh$' \
    | sort
}

# g3_fn_body <lib> <fn> — the source text of one top-level function.
g3_fn_body() {
  awk -v f="^${2}\\\\(\\\\) \\\\{" '$0 ~ f {p=1} p {print} p&&/^\}/{exit}' "$1"
}

# g3_writer_body <lib> <fn> — the function plus every `soleur_op_env_*` helper
# it calls, in call order, so a property about "the upsert" holds over the code
# the upsert actually runs rather than over the lines it happens to contain.
g3_writer_body() {
  local lib="$1" fn="$2" body helper
  body="$(g3_fn_body "$lib" "$fn")"
  [[ -n "$body" ]] || return 0
  printf '%s\n' "$body"
  while IFS= read -r helper; do
    [[ -n "$helper" && "$helper" != "$fn" ]] || continue
    g3_fn_body "$lib" "$helper"
  done < <(grep -oE '^[[:space:]]*soleur_op_env_[a-z_]+' <<<"$body" | sed 's/^[[:space:]]*//' | awk '!seen[$0]++')
}

g3_check() {
  local lib="$1" root="$2"
  local v=0 listing body idx_mv idx_chmod filter_line argv_hits f

  # --- own-dispatch: a scan that found nothing must not report "0 violations" -
  listing="$(g3_sourcing_scripts "$root")"
  if [[ -z "$listing" ]]; then
    echo "g3: the sourcing-script scan returned ZERO files — nothing was checked"
    return 1
  fi

  # --- row 1: the GitHub SECRET helper must never put the value on argv -------
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    argv_hits="$(grep -n 'gh secret set' "$f" 2>/dev/null | grep -c -- '--body')"
    if [[ "$argv_hits" -gt 0 ]]; then
      echo "g3: ${f} passes a secret to \`gh secret set\` on argv (--body) — readable in /proc/<pid>/cmdline"
      v=1
    fi
  done < <(printf '%s\n%s\n' "$lib" "$listing")

  # --- row 2: chmod 600 must land AFTER the mv that completes the upsert ------
  # `mv` replaces the inode AND its mode, so a chmod before it leaves a
  # world-readable window on the file the secret is then appended to.
  # The upsert delegates its filter and its commit to `soleur_op_env_*` helpers;
  # the body inspected here is the upsert PLUS every helper it calls, so a
  # reorder inside a helper is as visible as one inline.
  body="$(g3_writer_body "$lib" soleur_op_env_upsert)"
  if [[ -z "$body" ]]; then
    echo "g3: soleur_op_env_upsert not found in ${lib}"
    return 1
  fi
  idx_mv="$(grep -n '^[[:space:]]*mv "' <<<"$body" | head -1 | cut -d: -f1)"
  idx_chmod="$(grep -n '^[[:space:]]*chmod 600' <<<"$body" | head -1 | cut -d: -f1)"
  if [[ -z "$idx_mv" || -z "$idx_chmod" ]]; then
    echo "g3: could not locate both the mv and the chmod 600 inside soleur_op_env_upsert (or its helpers)"
    v=1
  elif [[ "$idx_chmod" -lt "$idx_mv" ]]; then
    echo "g3: chmod 600 (line ${idx_chmod}) precedes the mv (line ${idx_mv}) inside soleur_op_env_upsert"
    v=1
  fi

  # --- row 3 (static half): the upsert filter must be EXACT-key ---------------
  # The mechanism is the trailing `=` (R41); without it `^KEY` is a PREFIX match.
  filter_line="$(grep -nE 'grep( -[a-zA-Z]+)* -v' <<<"$body" | head -1 | cut -d: -f2-)"
  if [[ -z "$filter_line" ]]; then
    echo "g3: soleur_op_env_upsert has no grep -v filter line"
    v=1
  elif ! grep -qF '}=' <<<"$filter_line"; then
    echo "g3: the upsert filter is not anchored on a trailing '=' (prefix match):${filter_line}"
    v=1
  fi

  # --- row 5 (static half): the VARIABLE helper must refuse secret-shaped names
  if ! grep -q 'SOLEUR_BOOTSTRAP_UNSAFE_VARIABLE' "$lib"; then
    echo "g3: the gh-variable helper no longer refuses secret-shaped names"
    v=1
  fi

  # --- behavioural ------------------------------------------------------------
  local run="$SB/g3run"
  rm -rf "$run"; mkdir -p "$run"
  local ledger="$run/ledger.jsonl" envf="$run/.env" ghlog="$run/gh.log" out rc mode
  : > "$ghlog"
  printf 'ADJACENT_KEY_EXTRA=survivor\n' > "$envf"
  out="$(SOLEUR_BOOTSTRAP_LEDGER="$ledger" bash "$SB/drive.sh" "$lib" \
          soleur_op_env_upsert "$envf" ADJACENT_KEY "$SENTINEL" </dev/null 2>&1)"; rc=$?
  if [[ "$rc" -ne 0 ]]; then
    echo "g3: soleur_op_env_upsert exited ${rc}: ${out}"
    v=1
  fi
  if grep -qF "$SENTINEL" <<<"$out"; then
    echo "g3: the upsert printed the secret VALUE to stdout"
    v=1
  fi
  if [[ -f "$ledger" ]] && grep -qF "$SENTINEL" "$ledger"; then
    echo "g3: the run ledger recorded the secret VALUE (it must carry names only)"
    v=1
  fi
  if [[ ! -f "$ledger" ]] || ! grep -qF 'ADJACENT_KEY' "$ledger"; then
    echo "g3: the run ledger did not record the written key NAME"
    v=1
  fi
  # row 3 (behavioural half): the adjacent prefix-sharing key must survive.
  if [[ ! -f "$envf" ]] || ! grep -q '^ADJACENT_KEY_EXTRA=' "$envf"; then
    echo "g3: the upsert of ADJACENT_KEY removed ADJACENT_KEY_EXTRA (prefix match)"
    v=1
  fi
  # Observed on the produced ARTEFACT, not on the intent that claims to set it.
  mode="$(stat -c '%a' "$envf" 2>/dev/null || echo '???')"
  if [[ "$mode" != "600" ]]; then
    echo "g3: the .env is mode ${mode}, not 600"
    v=1
  fi

  # row 5 (behavioural half): a secret-shaped name must never reach `gh` argv.
  out="$(GH_ARGV_LOG="$ghlog" SOLEUR_BOOTSTRAP_LEDGER="$ledger" \
          bash "$SB/drive.sh" "$lib" soleur_op_gh_variable_set owner/repo DEPLOY_TOKEN "$SENTINEL" </dev/null 2>&1)"; rc=$?
  if [[ "$rc" -eq 0 ]]; then
    echo "g3: the variable helper ACCEPTED a secret-shaped name (DEPLOY_TOKEN)"
    v=1
  fi
  if grep -qF "$SENTINEL" "$ghlog"; then
    echo "g3: a secret-shaped value reached \`gh\` argv (observed in the argv log)"
    v=1
  fi

  rm -rf "$run"
  return "$v"
}

echo "== Guard 3 — secret-write paths =="

assert_green g3_check "pristine library" "$PRISTINE" "$PLUGIN_ROOT"

# row 1 — the secret helper moved onto argv
if mutate "g3-r1 secret value onto argv (--body)" "$SB/mut/g3r1.sh" <<'PROG'
s{printf '%s' "\$value" \| gh secret set "\$sec_name" -R "\$repo"}{gh secret set "\$sec_name" -R "\$repo" --body "\$value"}
PROG
then assert_red g3_check "g3-r1 secret value onto argv" "$SB/mut/g3r1.sh" "$PLUGIN_ROOT"; fi

# row 2 — chmod reordered ABOVE the mv (a REORDER, not a delete: the property is
# about the window between the two)
if mutate "g3-r2 chmod 600 reordered above the mv" "$SB/mut/g3r2.sh" <<'PROG'
s{(  mv "\$tmp" "\$env_file"\n)(  chmod 600 "\$env_file"\n)}{$2$1}
PROG
then assert_red g3_check "g3-r2 chmod before mv" "$SB/mut/g3r2.sh" "$PLUGIN_ROOT"; fi

# row 3 — the upsert filter generalised to the PREFIX form (one character: the `=`)
if mutate "g3-r3 upsert filter generalised to prefix" "$SB/mut/g3r3.sh" <<'PROG'
s{grep -a -v "\^\$\{key\}=" "\$env_file" > "\$tmp"}{grep -a -v "^\$\{key\}" "\$env_file" > "\$tmp"}
PROG
then assert_red g3_check "g3-r3 prefix-matching upsert filter" "$SB/mut/g3r3.sh" "$PLUGIN_ROOT"; fi

# row 4 — the ledger records the VALUE alongside the key name
if mutate "g3-r4 ledger records the value, not just the name" "$SB/mut/g3r4.sh" <<'PROG'
s{soleur_op_ledger_note env_upsert "\$key" "keys_before=\$\{before_count\}"}{soleur_op_ledger_note env_upsert "\$key" "\$value"}
PROG
then assert_red g3_check "g3-r4 secret value in the run ledger" "$SB/mut/g3r4.sh" "$PLUGIN_ROOT"; fi

# row 5 — the variable helper merged into the secret helper "for symmetry": the
# refusal prints but no longer returns, so argv becomes a secret path
if mutate "g3-r5 variable helper stops refusing secret-shaped names" "$SB/mut/g3r5.sh" <<'PROG'
s{(SOLEUR_BOOTSTRAP_UNSAFE_VARIABLE[^\n]*\n)    return 1\n}{$1}
PROG
then assert_red g3_check "g3-r5 secret-shaped name reaches gh argv" "$SB/mut/g3r5.sh" "$PLUGIN_ROOT"; fi

# row 6 — own-dispatch: the discovery walk returns zero files
assert_red g3_check "g3-r6 own-dispatch: zero sourcing scripts discovered" "$PRISTINE" "$SB/empty"

# harness (b) — must-PASS non-canonical: a consumer writing a NON-secret on argv
# passes, so the guard is a secret-path rule and not a blanket argv ban.
mkdir -p "$SB/run/nonsecret"
cat > "$SB/run/nonsecret/consumer.sh" <<'CONSUMER'
#!/usr/bin/env bash
set -euo pipefail
# sources lib/operator-script.sh
source "$(dirname "$0")/../../pristine-operator-script.sh"
gh variable set OPERATOR_GH_LOGIN -R "$1" --body "$2"
CONSUMER
if g3_check "$PRISTINE" "$SB/run/nonsecret" >/dev/null 2>&1; then
  pass "g3 harness (b): a consumer writing a NON-secret on argv passes"
else
  fail "g3 harness (b): the guard rejected a legitimate non-secret argv write"
fi

# =============================================================================
# Guard 6 — the .env writers validate input SHAPE and never shrink the file
# =============================================================================
#
# Property. `soleur_op_env_upsert` / `soleur_op_env_reset` refuse a key outside
# `^[A-Za-z_][A-Za-z0-9_]*$` and a value carrying a line break (BAD_ARG, rc 1,
# file untouched); a grep that exits 2 is ENV_READ_FAILED, never an empty file
# installed over the .env; a symlinked .env is rewritten through the link; the
# new line is in the temp file BEFORE the mv; and — measured by the review lead —
# a cp1252 byte under a UTF-8 locale or a NUL byte anywhere must not make grep's
# binary heuristic drop lines. Every row observes the ARTEFACT, not the intent.

genv_drive() {
  # genv_drive <lib> <ledger> <fn> <args...>  — stdout+stderr, rc in $?
  local lib="$1" ledger="$2"; shift 2
  SOLEUR_BOOTSTRAP_LEDGER="$ledger" bash "$SB/drive.sh" "$lib" "$@" </dev/null 2>&1
}

genv_check() {
  local lib="$1" v=0 run="$SB/genvrun" out rc envf ledger
  rm -rf "$run"; mkdir -p "$run"
  ledger="$run/ledger.jsonl"

  # --- row 1: a regex-metacharacter key is refused, and the file is untouched --
  envf="$run/meta.env"; printf 'AXB=1\nA_B=2\n' > "$envf"
  out="$(genv_drive "$lib" "$ledger" soleur_op_env_upsert "$envf" 'A.B' v)"; rc=$?
  if [[ "$rc" -eq 0 ]] || ! grep -qF 'SOLEUR_BOOTSTRAP_BAD_ARG key=A.B' <<<"$out"; then
    echo "genv: upsert accepted the key 'A.B' (rc=${rc}): ${out}"; v=1
  fi
  if [[ "$(cat "$envf")" != $'AXB=1\nA_B=2' ]]; then
    echo "genv: a refused upsert of 'A.B' changed the file: $(tr '\n' ' ' <"$envf")"; v=1
  fi
  # --- row 2: a key that is a BROKEN regex (grep exit 2) is refused up front ---
  out="$(genv_drive "$lib" "$ledger" soleur_op_env_upsert "$envf" '[BAD' v)"; rc=$?
  if [[ "$rc" -eq 0 ]] || ! grep -qF 'SOLEUR_BOOTSTRAP_BAD_ARG' <<<"$out"; then
    echo "genv: upsert accepted the key '[BAD' (rc=${rc})"; v=1
  fi
  if [[ ! -s "$envf" ]]; then
    echo "genv: the '[BAD' key emptied the .env (the grep-exit-2 wipe)"; v=1
  fi
  # --- row 3: the same validator guards reset -------------------------------
  out="$(genv_drive "$lib" "$ledger" soleur_op_env_reset "$envf" 'A.B')"; rc=$?
  if [[ "$rc" -eq 0 ]] || ! grep -qF 'SOLEUR_BOOTSTRAP_BAD_ARG key=A.B' <<<"$out"; then
    echo "genv: reset accepted the key 'A.B' (rc=${rc})"; v=1
  fi
  if ! grep -q '^AXB=1$' "$envf" || ! grep -q '^A_B=2$' "$envf"; then
    echo "genv: a refused reset of 'A.B' removed a key (metachar matched AXB/A_B)"; v=1
  fi
  # --- row 4: a value with a line break would inject a second KEY= line --------
  out="$(genv_drive "$lib" "$ledger" soleur_op_env_upsert "$envf" GOOD $'one\nEVIL=two')"; rc=$?
  if [[ "$rc" -eq 0 ]] || ! grep -qF 'SOLEUR_BOOTSTRAP_BAD_ARG key=GOOD' <<<"$out"; then
    echo "genv: upsert accepted a value containing a newline (rc=${rc})"; v=1
  fi
  if grep -q '^EVIL=' "$envf"; then
    echo "genv: the newline value injected an EVIL= line"; v=1
  fi
  out="$(genv_drive "$lib" "$ledger" soleur_op_env_upsert "$envf" GOOD $'one\rtwo')"; rc=$?
  if [[ "$rc" -eq 0 ]]; then
    echo "genv: upsert accepted a value containing a carriage return"; v=1
  fi

  # --- row 5: an unreadable .env is ENV_READ_FAILED, not an empty file ---------
  # A directory where the file should be makes grep exit 2 on every platform,
  # root or not.
  mkdir -p "$run/dir.env"
  out="$(genv_drive "$lib" "$ledger" soleur_op_env_upsert "$run/dir.env" KEY1 v)"; rc=$?
  if [[ "$rc" -eq 0 ]] || ! grep -qF 'SOLEUR_BOOTSTRAP_ENV_READ_FAILED' <<<"$out"; then
    echo "genv: an unreadable .env did not produce ENV_READ_FAILED (rc=${rc}): ${out}"; v=1
  fi
  if ls "$run"/dir.env.tmp.* >/dev/null 2>&1; then
    echo "genv: a refused upsert left its temp file behind"; v=1
  fi

  # --- row 6: a symlinked .env stays a symlink; the target gets the key --------
  printf 'OLD=1\n' > "$run/target.env"; ln -s "$run/target.env" "$run/link.env"
  out="$(genv_drive "$lib" "$ledger" soleur_op_env_upsert "$run/link.env" NEWK "$SENTINEL")"; rc=$?
  if [[ "$rc" -ne 0 ]]; then echo "genv: upsert through a symlink exited ${rc}: ${out}"; v=1; fi
  if [[ ! -L "$run/link.env" ]]; then
    echo "genv: the upsert replaced the symlink with a regular file"; v=1
  fi
  if ! grep -q "^NEWK=${SENTINEL}$" "$run/target.env" || ! grep -q '^OLD=1$' "$run/target.env"; then
    echo "genv: the symlink target does not hold both keys after the upsert"; v=1
  fi

  # --- row 7 (static): the new line is appended BEFORE the mv (atomic upsert) -
  local body idx_append idx_commit
  body="$(g3_writer_body "$lib" soleur_op_env_upsert)"
  idx_append="$(grep -nE "printf '%s=%s\\\\n' \"\\\$key\" \"\\\$value\" >> \"\\\$tmp\"" <<<"$body" | head -1 | cut -d: -f1)"
  idx_commit="$(grep -nE '^[[:space:]]*(mv "\$tmp"|soleur_op_env_commit )' <<<"$body" | head -1 | cut -d: -f1)"
  if [[ -z "$idx_append" || -z "$idx_commit" ]]; then
    echo "genv: could not locate the KEY=value append into \$tmp and the mv/commit in soleur_op_env_upsert"; v=1
  elif [[ "$idx_append" -gt "$idx_commit" ]]; then
    echo "genv: the KEY=value line is appended AFTER the mv (line ${idx_append} > ${idx_commit}) — a Ctrl-C between them loses the key"; v=1
  fi
  if ls "$run"/*.env.tmp.* >/dev/null 2>&1; then
    echo "genv: a successful upsert left a temp file behind"; v=1
  fi

  # --- row 8: a cp1252 byte in a comment, under a UTF-8 locale -----------------
  # Without `grep -a`, grep's binary heuristic drops the line with rc 0.
  envf="$run/cp1252.env"
  printf '# founder\x92s note\nKEEP_A=1\nKEEP_B=2\n' > "$envf"
  out="$(LC_ALL=C.UTF-8 genv_drive "$lib" "$ledger" soleur_op_env_upsert "$envf" KEEP_C 3)"; rc=$?
  if [[ "$rc" -ne 0 ]]; then echo "genv: cp1252 fixture upsert exited ${rc}: ${out}"; v=1; fi
  if ! cmp -s "$envf" <(printf '# founder\x92s note\nKEEP_A=1\nKEEP_B=2\nKEEP_C=3\n'); then
    echo "genv: the cp1252 .env lost content under LC_ALL=C.UTF-8: $(od -c "$envf" | head -3 | tr '\n' ' ')"; v=1
  fi
  # --- row 9: a NUL byte anywhere in the .env -------------------------------------
  envf="$run/nul.env"
  printf 'KEEP_A=1\n# stray\x00byte\nKEEP_B=2\n' > "$envf"
  out="$(genv_drive "$lib" "$ledger" soleur_op_env_upsert "$envf" KEEP_C 3)"; rc=$?
  if [[ "$rc" -ne 0 ]]; then echo "genv: NUL fixture upsert exited ${rc}: ${out}"; v=1; fi
  if ! cmp -s "$envf" <(printf 'KEEP_A=1\n# stray\x00byte\nKEEP_B=2\nKEEP_C=3\n'); then
    echo "genv: the NUL .env lost content: $(tr '\0' '@' <"$envf" | tr '\n' ' ')"; v=1
  fi
  out="$(LC_ALL=C.UTF-8 genv_drive "$lib" "$ledger" soleur_op_env_upsert "$envf" KEEP_A 9)"; rc=$?
  if [[ "$rc" -ne 0 ]] || ! cmp -s "$envf" <(printf '# stray\x00byte\nKEEP_B=2\nKEEP_C=3\nKEEP_A=9\n'); then
    echo "genv: replacing a key in the NUL .env under UTF-8 lost content (rc=${rc})"; v=1
  fi

  # A mutation that mv's into the directory row and chmod-600s it leaves an
  # unlistable dir; restore modes so the sandbox reaps cleanly.
  chmod -R u+rwx "$run" 2>/dev/null || true
  rm -rf "$run"
  return "$v"
}

echo "== Guard 6 — .env writers validate shape, never shrink =="

assert_green genv_check "pristine library" "$PRISTINE"

# row A — the validator loses its anchor: any key is accepted
if mutate "genv-rA key validator anchors removed" "$SB/mut/genvA.sh" <<'PROG'
s{=~ \^\[A-Za-z_\]\[A-Za-z0-9_\]\*\$ \]\]}{=~ . ]]}
PROG
then assert_red genv_check "genv-rA any key accepted" "$SB/mut/genvA.sh"; fi

# row B — grep exit 2 swallowed again (the `|| true` the review found)
if mutate "genv-rB grep exit 2 swallowed" "$SB/mut/genvB.sh" <<'PROG'
s{  if \(\( rc > 1 \)\); then\n    printf 'SOLEUR_BOOTSTRAP_ENV_READ_FAILED}{  if (( rc > 2 )); then\n    printf 'SOLEUR_BOOTSTRAP_ENV_READ_FAILED}
PROG
then assert_red genv_check "genv-rB ENV_READ_FAILED never fires" "$SB/mut/genvB.sh"; fi

# row C — the `-a` is dropped from the filter: binary heuristic returns
if mutate "genv-rC grep -a dropped from the filter" "$SB/mut/genvC.sh" <<'PROG'
s{grep -a -v "\^\$\{key\}="}{grep -v "^\$\{key\}="}
PROG
then assert_red genv_check "genv-rC binary heuristic drops lines (cp1252 / NUL fixtures)" "$SB/mut/genvC.sh"; fi

# row D — the symlink is no longer resolved: mv replaces the link
if mutate "genv-rD symlink resolution removed from upsert" "$SB/mut/genvD.sh" <<'PROG'
s{(soleur_op_env_upsert\(\) \{.*?)  env_file="\$\(readlink -f -- "\$env_file" 2>/dev/null \|\| printf '%s' "\$env_file"\)"\n}{$1}s
PROG
then assert_red genv_check "genv-rD symlinked .env replaced by a regular file" "$SB/mut/genvD.sh"; fi

# row E — the append moves back AFTER the commit (non-atomic upsert)
if mutate "genv-rE KEY=value appended after the mv" "$SB/mut/genvE.sh" <<'PROG'
s{(  printf '%s=%s\\n' "\$key" "\$value" >> "\$tmp"\n)(  soleur_op_env_commit "\$env_file" "\$tmp" "\$before_count" "\$before_count" \|\| return 1\n)}{$2  printf '%s=%s\\n' "\$key" "\$value" >> "\$env_file"\n}
PROG
then assert_red genv_check "genv-rE non-atomic upsert" "$SB/mut/genvE.sh"; fi

# row F — the value line-break check is removed
if mutate "genv-rF newline value accepted" "$SB/mut/genvF.sh" <<'PROG'
s{  if \[\[ "\$value" == \*\$'\\n'\* \|\| "\$value" == \*\$'\\r'\* \]\]; then}{  if false; then}
PROG
then assert_red genv_check "genv-rF newline in value injects a second line" "$SB/mut/genvF.sh"; fi

# =============================================================================
# Ledger — every line is JSON a reader can parse, and one run lands in one file
# =============================================================================

echo "== ledger shape =="

ledger_json_ok() {
  # ledger_json_ok <file> — every line parses as a JSON object.
  if command -v jq >/dev/null 2>&1; then
    jq -e 'type == "object"' "$1" >/dev/null 2>&1
  else
    python3 -c 'import json,sys
for l in open(sys.argv[1]):
    assert isinstance(json.loads(l), dict)' "$1" >/dev/null 2>&1
  fi
}

lj="$SB/ledger-json.jsonl"
SOLEUR_BOOTSTRAP_LEDGER="$lj" bash -c '
  set -uo pipefail
  source "$1"
  soleur_op_ledger_init abc "$(printf "probe\nwith \"quotes\" and\rCR")"
  soleur_op_stage_begin 1 "$(printf "line\xe2\x80\xa8sep")"
  soleur_op_stage_end 1 "name" ok "not-a-number"
' _ "$LIB" >/dev/null 2>&1
if ledger_json_ok "$lj"; then
  pass "ledger: every line parses as JSON with a newline, a CR, quotes, U+2028 and non-numeric integers in the inputs"
else
  fail "ledger: at least one line is not valid JSON: $(cat "$lj" 2>/dev/null | tr '\n' ' ')"
fi
if grep -qF '"total_stages":0' "$lj" && grep -qF '"exit_code":0' "$lj"; then
  pass "ledger: a non-integer total_stages / exit_code is substituted with 0, never emitted raw"
else
  fail "ledger: non-integer fields were emitted raw: $(cat "$lj" 2>/dev/null | tr '\n' ' ')"
fi
if grep -q $'\xe2\x80\xa8' "$lj"; then
  fail "ledger: U+2028 survived into the ledger line"
else
  pass "ledger: U+2028 is stripped from string fields"
fi

# --reset before any init: the ledger line must still carry a run_id.
lr="$SB/ledger-reset.jsonl"; printf 'K=1\n' > "$SB/ledger-reset.env"
SOLEUR_BOOTSTRAP_LEDGER="$lr" bash "$SB/drive.sh" "$LIB" soleur_op_env_reset "$SB/ledger-reset.env" K >/dev/null 2>&1
if grep -qE '"run_id":"[^"]+"' "$lr" 2>/dev/null; then
  pass "ledger: a write before soleur_op_ledger_init carries a non-empty run_id (the --reset path)"
else
  fail "ledger: the --reset path wrote an empty run_id: $(cat "$lr" 2>/dev/null)"
fi

# One run, one file: the default path is resolved ONCE and survives a `cd`.
mkdir -p "$SB/relrun/sub"
cat > "$SB/relrun/main.sh" <<'MAIN'
#!/usr/bin/env bash
set -uo pipefail
source "$1"
soleur_op_ledger_init 1 main.sh
cd sub
soleur_op_stage_begin 1 "after cd"
MAIN
( cd "$SB/relrun" && env -u SOLEUR_BOOTSTRAP_LEDGER bash ./main.sh "$LIB" ) >/dev/null 2>&1
rel_lines="$(grep -c . "$SB/relrun/bootstrap-runs.jsonl" 2>/dev/null || true)"
if [[ "$rel_lines" -eq 2 && ! -e "$SB/relrun/sub/bootstrap-runs.jsonl" ]]; then
  pass "ledger: the default path is resolved once — a cd inside the run does not split the file"
else
  fail "ledger: expected 2 lines in relrun/bootstrap-runs.jsonl and none in sub/ (got ${rel_lines}; sub exists: $([[ -e "$SB/relrun/sub/bootstrap-runs.jsonl" ]] && echo yes || echo no))"
fi

# =============================================================================
# Guard 4 — every prompt has a total non-interactive path (R8, three classes)
# =============================================================================
#
# Property, re-specified against R8's THREE carve-out classes:
#   class 1 (ladder value / credential entry)   — named skip variable;
#   class 2 (per-command destructive-write ack) — NO skip variable at all;
#   class 3 (out-of-band completion barrier)    — named skip variable, and the
#           caller must follow it with an independent verification.
# For all three: stdin not a TTY and no skip value ⇒ emit
# SOLEUR_BOOTSTRAP_INPUT_REQUIRED and exit 64 BEFORE reading. Never a hang.
#
# The plan's ORIGINAL Guard 4 property ("every prompt has a skip variable") is
# exactly what R8 showed would leave the guard GREEN over an
# hr-menu-option-ack-not-prod-write-auth violation, so it is not asserted here —
# row 6 drives the inverse.
#
# ANCHOR (R24): the exit=64 no-TTY probe — an exit status and a stdout marker
# observed from a CHILD PROCESS, independent of the source text claiming them.

g4_prompt_functions() {
  # Census of every `read` call site, keyed to its enclosing function.
  # Discovery, never a name list. `<UNCLASSIFIED>` is a RED bucket, not a skip.
  awk '
    /^[a-z_]+\(\) \{/                { fn = $1; sub(/\(\)$/, "", fn); next }
    /^\}/                            { fn = "" }
    /^[[:space:]]*read[[:space:]]+-/ { if (fn != "") print fn; else print "<UNCLASSIFIED>" }
  ' "$1" | sort -u
}

g4_check() {
  local lib="$1" root="${2:-$PLUGIN_ROOT}" v=0 fn body idx_tty idx_read fns out rc

  fns="$(g4_prompt_functions "$lib")"

  # --- own-dispatch: a census that found no prompts must not exit 0 ----------
  if [[ -z "$fns" ]]; then
    echo "g4: the prompt census found ZERO read sites — nothing was checked"
    return 1
  fi
  if grep -qx '<UNCLASSIFIED>' <<<"$fns"; then
    echo "g4: a read call site sits outside any prompt helper (unclassified)"
    v=1
  fi

  while IFS= read -r fn; do
    [[ -n "$fn" && "$fn" != "<UNCLASSIFIED>" ]] || continue
    body="$(awk -v f="^${fn}\\\\(\\\\) \\\\{" '$0 ~ f {p=1} p {print} p&&/^\}/{exit}' "$lib")"
    idx_read="$(grep -n '^[[:space:]]*read -' <<<"$body" | head -1 | cut -d: -f1)"
    idx_tty="$(grep -n 'soleur_op_input_required' <<<"$body" | head -1 | cut -d: -f1)"
    if [[ -z "$idx_tty" ]]; then
      echo "g4: ${fn} reads without a no-TTY refusal"
      v=1
    elif [[ -z "$idx_read" ]]; then
      echo "g4: ${fn} was censused as a prompt but has no read line"
      v=1
    elif [[ "$idx_tty" -ge "$idx_read" ]]; then
      echo "g4: ${fn} checks the TTY at line ${idx_tty}, AFTER its read at line ${idx_read}"
      v=1
    fi
    if [[ "$fn" == *_ack_or_die ]]; then
      # CLASS 2 — NO skip variable. An environment variable set once is exactly
      # the "prior approval extending to a new command" that
      # hr-menu-option-ack-not-prod-write-auth forbids.
      if grep -q 'soleur_op_skip_value' <<<"$body"; then
        echo "g4: ${fn} is a class-2 destructive-write ack but consults a skip variable"
        v=1
      fi
    else
      # CLASS 1 / CLASS 3 — named skip variable required.
      if ! grep -q 'soleur_op_skip_value' <<<"$body"; then
        echo "g4: ${fn} has no named skip variable"
        v=1
      fi
    fi
  done <<<"$fns"

  # --- consumer sweep --------------------------------------------------------
  # D12 keeps the credential prompt in the CALLER, so the caller is where the
  # census must also look — a guard scoped to the library would certify a
  # consumer that hangs. Population is DISCOVERED, and a zero population reddens.
  local consumer rl ln from window scanned=0
  while IFS= read -r consumer; do
    [[ -n "$consumer" ]] || continue
    scanned=$((scanned + 1))
    while IFS= read -r rl; do
      [[ -n "$rl" ]] || continue
      ln="${rl%%:*}"
      from=$(( ln > 12 ? ln - 12 : 1 ))
      window="$(sed -n "${from},${ln}p" "$consumer")"
      if ! grep -q 'soleur_op_input_required\|soleur_op_barrier\|soleur_op_ack_or_die\|soleur_op_value' <<<"$window"; then
        echo "g4: ${consumer}:${ln} reads with no no-TTY refusal in the 12 lines above it"
        v=1
      fi
    done < <(grep -nE '^[[:space:]]*read([[:space:]]|$)' "$consumer")
  done < <(g3_sourcing_scripts "$root")
  if [[ "$scanned" -eq 0 ]]; then
    echo "g4: the consumer scan returned ZERO sourcing scripts — the caller-side census checked nothing"
    v=1
  fi

  # --- ANCHOR: the exit=64 no-TTY probes, in a child, under `timeout` --------
  out="$(drive_blocked "$lib" soleur_op_barrier SOLEUR_TEST_SKIP_BARRIER 'Token created? Type yes: ')"; rc=$?
  if [[ "$rc" -ne 64 ]]; then
    echo "g4: class-3 barrier with no TTY and no skip value exited ${rc}, expected 64"
    v=1
  fi
  if ! grep -qF 'SOLEUR_BOOTSTRAP_INPUT_REQUIRED' <<<"$out"; then
    echo "g4: class-3 barrier did not emit SOLEUR_BOOTSTRAP_INPUT_REQUIRED"
    v=1
  fi
  if ! grep -qF 'SOLEUR_TEST_SKIP_BARRIER' <<<"$out"; then
    echo "g4: the no-TTY refusal did not NAME the missing skip variable"
    v=1
  fi

  out="$(drive_blocked "$lib" soleur_op_value SOLEUR_TEST_SKIP_VALUE 'Region: ' REGION_OUT)"; rc=$?
  if [[ "$rc" -ne 64 ]]; then
    echo "g4: class-1 value prompt with no TTY and no skip value exited ${rc}, expected 64"
    v=1
  fi

  # CLASS 2: no TTY ⇒ 64 UNCONDITIONALLY. Both plausible skip names are set here
  # on purpose — no environment variable may buy its way past this gate.
  out="$(SOLEUR_BOOTSTRAP_ACK=yes SOLEUR_TEST_SKIP_ACK=yes \
          timeout 5 bash "$SB/drive.sh" "$lib" soleur_op_ack_or_die 'Create billable server? Type yes: ' \
          <"$BLOCK_FIFO" 2>&1)"; rc=$?
  if [[ "$rc" -ne 64 ]]; then
    echo "g4: class-2 ack exited ${rc} with skip-shaped variables set, expected 64 unconditionally"
    v=1
  fi
  if ! grep -qF 'SOLEUR_BOOTSTRAP_INPUT_REQUIRED' <<<"$out"; then
    echo "g4: class-2 ack did not emit SOLEUR_BOOTSTRAP_INPUT_REQUIRED"
    v=1
  fi

  return "$v"
}

echo "== Guard 4 — total non-interactive path =="

assert_green g4_check "pristine library" "$PRISTINE"

# row 1 — a prompt with no corresponding skip variable, inserted BEFORE the
# compliant helpers (the FIRST censused prompt is the bad one)
if mutate "g4-r1 prompt with no skip variable (before the compliant set)" "$SB/mut/g4r1.sh" <<'PROG'
s{\n# --- MUTATION ANCHOR: start of prompt helpers ---}{\nsoleur_op_aardvark_prompt() {\n  local reply\n  [[ -t 0 ]] || soleur_op_input_required "rogue"\n  read -r -p "rogue: " reply\n  printf '%s' "\$reply"\n}\n\n# --- MUTATION ANCHOR: start of prompt helpers ---}
PROG
then assert_red g4_check "g4-r1 prompt with no skip variable" "$SB/mut/g4r1.sh"; fi

# row 2 — the no-TTY exit becomes a mute 1, which is today's unattributed
# provision-hetzner.sh behaviour
if mutate "g4-r2 no-TTY exit 64 -> 1" "$SB/mut/g4r2.sh" <<'PROG'
s{tty=0\\n' "\$1"\n  exit 64}{tty=0\\n' "\$1"\n  exit 1}
PROG
then assert_red g4_check "g4-r2 unattributed exit 1 instead of 64" "$SB/mut/g4r2.sh"; fi

# row 3 — REORDER (not a delete): the TTY check moves BELOW the read. A
# delete-only battery goes green while the script still hangs, because a case
# that observes only after the function returns can never see the hang.
if mutate "g4-r3 TTY check reordered below the read" "$SB/mut/g4r3.sh" <<'PROG'
s{(  \[\[ -t 0 \]\] \|\| soleur_op_input_required "\$var_name"\n)(  read -r -p "\$prompt_text" reply\n)}{$2$1}g
PROG
then assert_red g4_check "g4-r3 TTY check after the read (hang, caught by timeout)" "$SB/mut/g4r3.sh"; fi

# row 4 — a SECOND prompt AFTER a compliant first: the census must not stop at
# the first prompt
if mutate "g4-r4 second prompt after a compliant first" "$SB/mut/g4r4.sh" <<'PROG'
s{\n# --- MUTATION ANCHOR: end of prompt helpers ---}{\nsoleur_op_zulu_prompt() {\n  local reply\n  [[ -t 0 ]] || soleur_op_input_required "second"\n  read -r -p "second: " reply\n  printf '%s' "\$reply"\n}\n\n# --- MUTATION ANCHOR: end of prompt helpers ---}
PROG
then assert_red g4_check "g4-r4 second unguarded prompt" "$SB/mut/g4r4.sh"; fi

# row 5 — own-dispatch: the prompt census returns zero prompts
if mutate "g4-r5 own-dispatch: every read site removed" "$SB/mut/g4r5.sh" <<'PROG'
s{^  read -r -p [^\n]*\n}{  reply=""\n}gm
PROG
then assert_red g4_check "g4-r5 own-dispatch: zero prompts censused" "$SB/mut/g4r5.sh"; fi

# row 6 — R8's inversion: the destructive-write ack is GIVEN a skip variable.
# The plan's original Guard 4 would have gone GREEN here, and a refactored
# provision-hetzner.sh would then create a real billable server fully unattended.
if mutate "g4-r6 destructive-write ack gains a skip variable" "$SB/mut/g4r6.sh" <<'PROG'
s{(soleur_op_ack_or_die\(\) \{\n  local prompt_text="\$1" reply\n)}{$1  [[ -z "\$(soleur_op_skip_value SOLEUR_BOOTSTRAP_ACK)" ]] || return 0\n}
PROG
then assert_red g4_check "g4-r6 ack with a skip variable (hr-menu-option-ack violation)" "$SB/mut/g4r6.sh"; fi

# row 7 — the CONSUMER-side census. Two claims, because the sweep can fail two
# ways: it can find nothing (own-dispatch), and it can find a real caller
# regression. The second copies the live proving consumer into a sandbox and
# deletes the TTY gate above its `read -rs` — the exact edit a "tidy-up" of the
# refactor would make.
assert_red g4_check "g4-r7a consumer sweep own-dispatch: zero sourcing scripts" "$PRISTINE" "$SB/empty"

mkdir -p "$SB/run/consumer-mut"
HETZNER_SRC="${PLUGIN_ROOT}/skills/provision-hetzner/scripts/provision-hetzner.sh"
if [[ -r "$HETZNER_SRC" ]]; then
  cp "$HETZNER_SRC" "$SB/run/consumer-mut/provision-hetzner.sh"
  perl -0777 -pi -e 's{^  \[\[ -t 0 \]\] \|\| soleur_op_input_required SOLEUR_BOOTSTRAP_HCLOUD_TOKEN\n}{}m' \
    "$SB/run/consumer-mut/provision-hetzner.sh"
  if [[ "$(md5_of "$SB/run/consumer-mut/provision-hetzner.sh")" == "$(md5_of "$HETZNER_SRC")" ]]; then
    fail "mutation 'g4-r7b consumer TTY gate deleted' did NOT land (md5 identical to the live script)"
  else
    pass "mutation 'g4-r7b consumer TTY gate deleted' landed (md5 differs from the live script)"
    assert_red g4_check "g4-r7b consumer reads with no TTY gate above it" "$PRISTINE" "$SB/run/consumer-mut"
  fi
else
  fail "g4-r7b: the proving consumer is missing at ${HETZNER_SRC}"
fi

# harness (a) — the no-TTY case runs under `timeout`. Asserted two ways, because
# the literal "remove the timeout wrapper" would hang this runner:
#   (i)  the probe helper's own definition names `timeout`;
#   (ii) the COMPLIANT library exits **64**, not 124, against the SAME blocked
#        stdin — so row 3's RED is the reorder being caught, not the wrapper
#        killing every run alike. A generous 30s bound stays on this probe rather
#        than removing it literally: an unwrapped probe against a regressed
#        library would hang the runner, which is the failure the wrapper exists
#        to prevent.
if grep -q 'timeout 5 bash' <<<"$(declare -f drive_blocked)"; then
  pass "g4 harness (a.i): the no-TTY probe is wrapped in \`timeout\`"
else
  fail "g4 harness (a.i): the no-TTY probe lost its \`timeout\` wrapper — a reorder mutation would hang the runner"
fi
unwrapped_out="$(timeout 30 bash "$SB/drive.sh" "$PRISTINE" soleur_op_barrier SOLEUR_TEST_SKIP_BARRIER 'x: ' <"$BLOCK_FIFO" 2>&1)"
unwrapped_rc=$?
if [[ "$unwrapped_rc" -eq 64 ]]; then
  pass "g4 harness (a.ii): the compliant library exits 64 (not 124) against the same blocked stdin — row 3's RED is the reorder, not the kill"
else
  fail "g4 harness (a.ii): blocked-stdin probe exited ${unwrapped_rc}, expected 64"
fi

# harness (b) — must-PASS non-canonical: a prompt whose skip variable IS set
# proceeds silently and exits 0, proving the guard does not reject the automated
# path it exists to protect.
skip_out="$(SOLEUR_TEST_SKIP_BARRIER=yes timeout 5 bash "$SB/drive.sh" "$PRISTINE" \
             soleur_op_barrier SOLEUR_TEST_SKIP_BARRIER 'Token created? Type yes: ' <"$BLOCK_FIFO" 2>&1)"
skip_rc=$?
if [[ "$skip_rc" -eq 0 ]]; then
  pass "g4 harness (b): a class-3 barrier with its skip variable set exits 0"
else
  fail "g4 harness (b): skip-variable path exited ${skip_rc}, expected 0. Output: ${skip_out}"
fi
if grep -qF 'SOLEUR_BOOTSTRAP_INPUT_REQUIRED' <<<"$skip_out"; then
  fail "g4 harness (b): the skipped path still emitted the input-required marker"
else
  pass "g4 harness (b): the skipped path emits no input-required marker"
fi

# =============================================================================
# Guard 5' — prologue placement and library scope (Deepen-Plan Ruling 1)
# =============================================================================
#
# ONE assertion, not five rows: the union of the two properties R18 and R26
# established as real, minus the four rows that tested the linter rather than
# this change.
#   (a) every script that sources the library AND acquires a credential carries
#       its xtrace refusal ABOVE its `source` line. `PROLOGUE_MAX_CMDS = 0` in
#       scripts/lint-shell-trace-credential-refusal.py makes a `source` line
#       itself a counted command, so the prologue is DUPLICATED above it and
#       never moved into the library;
#   (b) the library never expands a secret-shaped variable name. The linter's
#       `^scripts/lib/` exclusion is repo-root-anchored, so a library under
#       plugins/soleur/scripts/lib/ IS scanned — and if it came into scope it
#       would need its own `exit 78`, which on a `source` kills the CALLER.

echo "== Guard 5' — prologue above source, library out of credential scope =="

g5_violations=""

lib_body="$(grep -vE '^[[:space:]]*#' "$LIB")"
if grep -qE '\$\{?[A-Za-z_][A-Za-z0-9_]*_(TOKEN|KEY|SECRET|PASSWORD|PAT)\}?' <<<"$lib_body"; then
  g5_violations="${g5_violations} library-expands-secret-shaped-name"
fi
if grep -qE '\$\{!' <<<"$lib_body"; then
  g5_violations="${g5_violations} library-uses-indirect-expansion"
fi
if grep -qE 'doppler secrets get|gh auth token' <<<"$lib_body"; then
  g5_violations="${g5_violations} library-acquires-a-credential"
fi

while IFS= read -r consumer; do
  [[ -n "$consumer" ]] || continue
  acquires="$(grep -cE 'read -[a-z]*s |doppler secrets get|gh auth token|Authorization: *Bearer' "$consumer")"
  [[ "$acquires" -gt 0 ]] || continue
  src_ln="$(grep -n '^[[:space:]]*source ' "$consumer" | head -1 | cut -d: -f1)"
  ref_ln="$(grep -n '^[[:space:]]*case "\$-" in' "$consumer" | head -1 | cut -d: -f1)"
  if [[ -z "$ref_ln" ]]; then
    g5_violations="${g5_violations} ${consumer}:no-xtrace-refusal"
  elif [[ -n "$src_ln" && "$ref_ln" -gt "$src_ln" ]]; then
    g5_violations="${g5_violations} ${consumer}:refusal-below-source"
  fi
done < <(g3_sourcing_scripts "$PLUGIN_ROOT")

if [[ -z "$g5_violations" ]]; then
  pass "Guard 5': prologue sits above every credential-acquiring consumer's source line, and the library expands no secret-shaped name"
else
  fail "Guard 5' violations:${g5_violations}"
fi

# =============================================================================
# Library contract assertions the guards do not cover
# =============================================================================

echo "== library contract =="

# Line-1 convention shared with the three sibling libraries in scripts/lib/
# (proc.sh, session-state.sh, domain-model-lib.sh): a shebang, so shellcheck
# infers the dialect. Sourced-only is a property of the exec bit, not of line 1.
if [[ "$(head -1 "$LIB")" == "#!/usr/bin/env bash" ]]; then
  pass "line 1 is the sibling-library shebang"
else
  fail "line 1 must be '#!/usr/bin/env bash' (sibling convention); got: $(head -1 "$LIB")"
fi

if grep -q '^umask 077' "$LIB"; then
  pass "umask 077 is set inside the library"
else
  fail "umask 077 is not set inside the library"
fi

# F6 — the API contract is a runtime export, observed after a source.
api_got="$(bash -c 'set -uo pipefail; source "$1"; printf "%s" "${SOLEUR_OP_LIB_API:-unset}"' _ "$LIB" 2>/dev/null)"
if [[ "$api_got" =~ ^[0-9]+$ && "$api_got" -ge 1 ]]; then
  pass "library exports SOLEUR_OP_LIB_API=${api_got} after source"
else
  fail "library does not export a numeric SOLEUR_OP_LIB_API >= 1 (got '${api_got}')"
fi

# open_url must be ADDITIVE-ONLY: the URL is printed first and the opener's exit
# code is never branched on. Plus the new WSL arm.
openurl_body="$(awk '/^soleur_op_open_url\(\) \{/{f=1} f{print} f&&/^\}/{exit}' "$LIB")"
if [[ "$(grep -n 'printf' <<<"$openurl_body" | head -1 | cut -d: -f1)" -lt \
      "$(grep -n 'command -v' <<<"$openurl_body" | head -1 | cut -d: -f1)" ]]; then
  pass "open_url prints the URL BEFORE attempting any opener"
else
  fail "open_url attempts an opener before printing the URL"
fi
for arm in wslview explorer.exe xdg-open open; do
  if grep -qF "command -v ${arm}" <<<"$openurl_body"; then
    pass "open_url carries the '${arm}' arm"
  else
    fail "open_url is missing the '${arm}' arm"
  fi
done
openurl_true="$(grep -c '|| true' <<<"$openurl_body")"
if [[ "$openurl_true" -ge 4 ]]; then
  pass "open_url never branches on an opener's exit code (${openurl_true} '|| true' arms)"
else
  fail "open_url branches on an opener's exit code (only ${openurl_true} '|| true' arms)"
fi

# R21a — the founder-facing dead end the library closes: a wrong credential is
# otherwise permanent. Behavioural: the key is gone after a reset.
reset_env="$SB/reset-probe.env"
printf 'KEEP_ME=1\nFORGET_ME=2\n' > "$reset_env"
SOLEUR_BOOTSTRAP_LEDGER="$SB/reset-probe.jsonl" bash "$SB/drive.sh" "$LIB" soleur_op_env_reset "$reset_env" FORGET_ME >/dev/null 2>&1
if grep -q '^KEEP_ME=1$' "$reset_env" && ! grep -q '^FORGET_ME=' "$reset_env"; then
  pass "R21a: soleur_op_env_reset removes exactly the named key"
else
  fail "R21a: soleur_op_env_reset left: $(cat "$reset_env" 2>/dev/null | tr '\n' ' ')"
fi

# F1 — a GENERATED script must find the library from its documented home,
# knowledge-base/project/specs/feat-<name>/bootstrap.sh, with neither
# CLAUDE_PLUGIN_ROOT nor SOLEUR_OP_LIB in the environment (a founder's terminal).
# The generation-time bake is what makes that reachable; the unsubstituted
# template in the same location is the negative control proving the bake is
# load-bearing rather than decorative.
TEMPLATE="${PLUGIN_ROOT}/skills/operator-bootstrap/template.sh"
gen_home="$SB/founder-repo/knowledge-base/project/specs/feat-x"
mkdir -p "$gen_home"
if [[ -r "$TEMPLATE" ]]; then
  lib_abs="$(realpath "$LIB")"
  sed "s|^SOLEUR_OP_LIB_BAKED=.*|SOLEUR_OP_LIB_BAKED=\"${lib_abs}\"|" "$TEMPLATE" > "$gen_home/bootstrap.sh"
  if grep -qF "SOLEUR_OP_LIB_BAKED=\"${lib_abs}\"" "$gen_home/bootstrap.sh"; then
    pass "F1: the bake substitution landed in the generated copy"
  else
    fail "F1: the bake substitution did NOT land (placeholder line not matched)"
  fi
  gen_out="$(cd "$SB/founder-repo" && env -u CLAUDE_PLUGIN_ROOT -u SOLEUR_OP_LIB timeout 10 bash knowledge-base/project/specs/feat-x/bootstrap.sh --help 2>&1)"; gen_rc=$?
  if [[ "$gen_rc" -eq 0 ]]; then
    pass "F1: baked generated script resolves the library from its documented home (--help exits 0)"
  else
    fail "F1: baked generated script exited ${gen_rc} from its documented home: ${gen_out}"
  fi
  if grep -qF 'SOLEUR_BOOTSTRAP_LIB_MISSING' <<<"$gen_out"; then
    fail "F1: baked generated script still reported LIB_MISSING"
  else
    pass "F1: baked generated script did not report LIB_MISSING"
  fi

  # Negative control: the raw template, placeholder intact, same location.
  cp "$TEMPLATE" "$gen_home/bootstrap-unbaked.sh"
  raw_out="$(cd "$SB/founder-repo" && env -u CLAUDE_PLUGIN_ROOT -u SOLEUR_OP_LIB timeout 10 bash knowledge-base/project/specs/feat-x/bootstrap-unbaked.sh --help 2>&1)"; raw_rc=$?
  if [[ "$raw_rc" -eq 64 ]] && grep -qF 'SOLEUR_BOOTSTRAP_LIB_MISSING' <<<"$raw_out"; then
    pass "F1 negative control: the UNBAKED template in the same location exits 64 with LIB_MISSING (the bake is load-bearing)"
  else
    fail "F1 negative control: unbaked template exited ${raw_rc} (expected 64 + LIB_MISSING): ${raw_out}"
  fi

  # F6 — the consumer-side contract refuses a library that predates the API.
  : > "$SB/empty-lib.sh"
  api_out="$(cd "$SB/founder-repo" && env -u CLAUDE_PLUGIN_ROOT SOLEUR_OP_LIB="$SB/empty-lib.sh" timeout 10 bash knowledge-base/project/specs/feat-x/bootstrap.sh --help 2>&1)"; api_rc=$?
  if [[ "$api_rc" -eq 64 ]] && grep -qF 'SOLEUR_BOOTSTRAP_LIB_INCOMPATIBLE need=1 got=0' <<<"$api_out"; then
    pass "F6: a library without SOLEUR_OP_LIB_API is refused with LIB_INCOMPATIBLE, exit 64"
  else
    fail "F6: pre-API library was not refused (rc=${api_rc}): ${api_out}"
  fi
else
  fail "F1: template.sh not readable at ${TEMPLATE}"
fi

# Ledger: one line BEFORE and one AFTER each stage.
ledger_probe="$SB/ledger-probe.jsonl"
SOLEUR_BOOTSTRAP_LEDGER="$ledger_probe" bash -c '
  set -uo pipefail
  source "$1"
  soleur_op_ledger_init 2 probe
  soleur_op_stage_begin 1 "mint the token"
  soleur_op_stage_end 1 "mint the token" ok 0
' _ "$LIB" >/dev/null 2>&1
begin_n="$(grep -c '"phase":"begin"' "$ledger_probe" 2>/dev/null || true)"
settle_n="$(grep -c '"phase":"settle"' "$ledger_probe" 2>/dev/null || true)"
if [[ "$begin_n" -eq 1 && "$settle_n" -eq 1 ]]; then
  pass "run ledger writes one line before and one line after each stage"
else
  fail "run ledger wrote ${begin_n} begin / ${settle_n} settle lines, expected 1 / 1"
fi
if grep -qF '"total_stages":2' "$ledger_probe"; then
  pass "run ledger declares TOTAL_STAGES (a completed-set vs declared-total comparison is decidable from the artifact alone)"
else
  fail "run ledger does not declare total_stages"
fi

# F7 — a ledger write that fails is non-fatal but never silent.
mkdir -p "$SB/f7"
unwritable_ledger="$SB/f7/not-a-dir/ledger.jsonl"
: > "$SB/f7/not-a-dir"   # a FILE where the directory must be: mkdir -p and the append both fail
f7_out="$(SOLEUR_BOOTSTRAP_LEDGER="$unwritable_ledger" bash -c '
  set -uo pipefail
  source "$1"
  soleur_op_ledger_init 1 probe
  echo "STILL-RUNNING"
' _ "$LIB" 2>&1)"
if grep -qF "SOLEUR_BOOTSTRAP_LEDGER_WRITE_FAILED path=${unwritable_ledger}" <<<"$f7_out"; then
  pass "F7: an unwritable ledger path emits SOLEUR_BOOTSTRAP_LEDGER_WRITE_FAILED naming the path"
else
  fail "F7: no LEDGER_WRITE_FAILED marker for an unwritable ledger path. Output: ${f7_out}"
fi
if grep -qF 'STILL-RUNNING' <<<"$f7_out"; then
  pass "F7: the ledger write failure is non-fatal (the caller continued)"
else
  fail "F7: the ledger write failure aborted the caller"
fi

# bash -n is the syntax gate on this host (shellcheck is a non-executable shim).
if bash -n "$LIB" 2>/dev/null; then
  pass "library parses (bash -n)"
else
  fail "library fails bash -n"
fi

# --- Anti-vacuity floor ------------------------------------------------------
# Appends to `fails`, the SAME variable the verdict below reads. A floor that
# bumped a separate counter would not change the exit status it claims to guard.
FLOOR=73
if [[ "$asserts" -lt "$FLOOR" ]]; then
  printf '  [FAIL] anti-vacuity floor: %s assertions ran, expected at least %s\n' "$asserts" "$FLOOR" >&2
  fails=$((fails + 1))
fi

echo "Total: ${asserts} assertions, ${fails} failed"
[[ "$fails" -eq 0 ]]
