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

# The .env-must-be-ignored rows below create a git fixture. Sourcing this arms
# the #7833 tripwire (an inherited GIT_DIR aborts the suite, exit 97) and gives
# `git_fixture_env`, which sweeps GIT_*, pins a discovery ceiling at the sandbox
# and makes config hermetic — so no fixture `git init` can reach the live repo.
# shellcheck source=./lib/git-fixture-env.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/git-fixture-env.sh"

SUITE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="${SUITE_DIR}/../scripts/lib/operator-script.sh"
PLUGIN_ROOT="$(cd "${SUITE_DIR}/.." && pwd)"

# The value that must NEVER appear on stdout, in the run ledger, or on argv.
# Asserted as an ABSENCE, not only as a presence somewhere else: a ledger that
# records the right key name AND the value would pass a presence-only check.
SENTINEL='SENTINEL-NEVER-PRINT-a1b2c3d4'

# ONE counter per outcome. The self-test below, the anti-vacuity floor and the
# verdict at the bottom ALL read these two names — a shadow pair (`fails` next
# to `FAIL_COUNT`) let a dropped increment print [FAIL] while the verdict
# reported 0 failed and exited 0 (review P1-5).
PASS_COUNT=0
FAIL_COUNT=0

pass() { PASS_COUNT=$((PASS_COUNT + 1)); echo "  [ok] $1"; }
fail() { FAIL_COUNT=$((FAIL_COUNT + 1)); echo "  [FAIL] $1" >&2; }

# assert_red <guard> <label> <args...> — the guard must exit non-zero.
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

# assert_green <guard> <label> <args...> — the guard must exit zero.
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

# --- ADR-193 instrument self-test -------------------------------------------
# Drive all FOUR helpers through a known outcome and refuse to continue unless
# each moved the counter the verdict reads. Reported through `printf` + `exit`,
# never through the helpers it backstops — a self-test that reports via the
# instrument it is testing cannot fail when that instrument is the thing that
# is broken. Two of the four are KNOWN-NEGATIVES: `assert_red true` and
# `assert_green false` must each register a FAILURE, so an inverted comparison
# inside either helper (`-ne 0` → `-ge 0`) is caught here rather than passing
# every mutation row silently (review P2-21).
_st_p=$PASS_COUNT; _st_f=$FAIL_COUNT
pass "instrument self-test: pass() reached" >/dev/null
fail "instrument self-test: fail() reached (expected, not a real failure)" 2>/dev/null
if [[ "$PASS_COUNT" -ne $((_st_p + 1)) || "$FAIL_COUNT" -ne $((_st_f + 1)) ]]; then
  printf 'INSTRUMENT SELF-TEST FAILED: pass/fail helpers did not both move (pass %s->%s, fail %s->%s)\n' \
    "$_st_p" "$PASS_COUNT" "$_st_f" "$FAIL_COUNT" >&2
  exit 2
fi
_st_f=$FAIL_COUNT
assert_red true "instrument self-test known-negative" >/dev/null 2>&1
if [[ "$FAIL_COUNT" -ne $((_st_f + 1)) ]]; then
  printf 'INSTRUMENT SELF-TEST FAILED: assert_red did not register a failure for a guard that exited 0 (fail %s->%s)\n' \
    "$_st_f" "$FAIL_COUNT" >&2
  exit 2
fi
_st_f=$FAIL_COUNT
assert_green false "instrument self-test known-negative" >/dev/null 2>&1
if [[ "$FAIL_COUNT" -ne $((_st_f + 1)) ]]; then
  printf 'INSTRUMENT SELF-TEST FAILED: assert_green did not register a failure for a guard that exited 1 (fail %s->%s)\n' \
    "$_st_f" "$FAIL_COUNT" >&2
  exit 2
fi
_st_p=$PASS_COUNT
assert_red false "instrument self-test known-positive" >/dev/null 2>&1
assert_green true "instrument self-test known-positive" >/dev/null 2>&1
if [[ "$PASS_COUNT" -ne $((_st_p + 2)) ]]; then
  printf 'INSTRUMENT SELF-TEST FAILED: assert_red/assert_green did not register a pass for the expected outcome (pass %s->%s)\n' \
    "$_st_p" "$PASS_COUNT" >&2
  exit 2
fi
# Unwind the accounting the self-test perturbed; count the self-test itself once.
PASS_COUNT=1; FAIL_COUNT=0
echo "  [ok] instrument self-test: pass/fail dispatch; assert_red/assert_green each register a known-negative"

[[ -r "$LIB" ]] || { printf 'HARNESS: library not readable at %s\n' "$LIB" >&2; exit 2; }
command -v timeout >/dev/null 2>&1 || { printf 'HARNESS: `timeout` is required for the no-TTY probes\n' >&2; exit 2; }
command -v md5sum  >/dev/null 2>&1 || { printf 'HARNESS: `md5sum` is required for mutation-landing proof\n' >&2; exit 2; }
command -v perl    >/dev/null 2>&1 || { printf 'HARNESS: `perl` is required to apply the mutations\n' >&2; exit 2; }
command -v script  >/dev/null 2>&1 || { printf 'HARNESS: `script` (util-linux) is required to drive the prompt helpers through a pty\n' >&2; exit 2; }
script -qec true /dev/null </dev/null >/dev/null 2>&1 || { printf 'HARNESS: `script -qec` did not run (a non-util-linux script?)\n' >&2; exit 2; }

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
  # Consume stdin ONLY for the secret write, the one call that has a writer —
  # into a SECOND log, so the suite can assert the value arrived THERE and not
  # on argv. An unconditional `cat` blocks forever on whatever stdin the runner
  # inherited.
  "secret set")    cat >> "${GH_STDIN_LOG:-/dev/null}" 2>&1 || true; exit 0 ;;
  "secret list")   printf 'STUBBED_SECRET\tupdated\n'; exit 0 ;;
  "variable list") printf 'STUBBED_VAR\tvalue\n'; exit 0 ;;
esac
exit 0
STUB
chmod +x "$SB/bin/gh"
# URL openers: stubbed so no row ever launches a real browser on the host, and
# so a hang in an opener is a library defect the suite sees, not host weather.
for opener in xdg-open open wslview explorer.exe; do
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "${OPENER_LOG:-/dev/null}"\nexit 0\n' > "$SB/bin/$opener"
  chmod +x "$SB/bin/$opener"
done
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
  timeout 1 bash "$SB/drive.sh" "$lib" "$@" <"$BLOCK_FIFO" 2>&1
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

  # row 1 (behavioural half): the SECRET helper is DRIVEN against the argv-
  # logging stub. The value must be absent from argv and present on the stub's
  # stdin capture — observed the way `ps` and the receiving process would see it,
  # not inferred from the spelling of the call (review P2-22).
  local ghin="$run/gh.stdin"
  : > "$ghin"
  out="$(GH_ARGV_LOG="$ghlog" GH_STDIN_LOG="$ghin" SOLEUR_BOOTSTRAP_LEDGER="$ledger" \
          bash "$SB/drive.sh" "$lib" soleur_op_gh_secret_set owner/repo STUBBED_SECRET "$SENTINEL" </dev/null 2>&1)"; rc=$?
  if [[ "$rc" -ne 0 ]]; then
    echo "g3: soleur_op_gh_secret_set exited ${rc} against the stub: ${out}"
    v=1
  fi
  if grep -qF "$SENTINEL" "$ghlog"; then
    echo "g3: the secret VALUE reached \`gh\` argv (observed in the argv log)"
    v=1
  fi
  if ! grep -qF "$SENTINEL" "$ghin"; then
    echo "g3: the secret VALUE did not arrive on \`gh secret set\`'s stdin (the write sent nothing)"
    v=1
  fi
  if grep -qF "$SENTINEL" <<<"$out"; then
    echo "g3: the secret helper printed the VALUE"
    v=1
  fi
  if [[ -f "$ledger" ]] && grep -qF "$SENTINEL" "$ledger"; then
    echo "g3: the run ledger recorded the secret VALUE after a gh write"
    v=1
  fi

  # row 5 (behavioural half): every secret-shaped name must be refused and must
  # never reach `gh` argv — the 13 spellings the old suffix-only, case-sensitive
  # pattern admitted (review P2-10 §F2), each driven, and two legitimate names
  # that must still be ALLOWED so the rule stays a secret-shape rule and not a
  # blanket refusal.
  local name
  for name in HCLOUD_TOKEN_PRD hcloud_token SECRET_KEY_BASE API_KEYS PRIVATE_KEY_PEM \
              CREDENTIALS DB_PASSWD SENTRY_DSN Deploy_Token TOKEN_FOR_CI \
              PASSPHRASE_FILE CREDENTIAL_PATH GH_PAT_FINE_GRAINED; do
    : > "$ghlog"
    out="$(GH_ARGV_LOG="$ghlog" SOLEUR_BOOTSTRAP_LEDGER="$ledger" \
            bash "$SB/drive.sh" "$lib" soleur_op_gh_variable_set owner/repo "$name" "$SENTINEL" </dev/null 2>&1)"; rc=$?
    if [[ "$rc" -eq 0 ]]; then
      echo "g3: the variable helper ACCEPTED the secret-shaped name ${name}"
      v=1
    fi
    if grep -qF "$SENTINEL" "$ghlog"; then
      echo "g3: a secret-shaped value reached \`gh\` argv via ${name} (observed in the argv log)"
      v=1
    fi
    if ! grep -qF "SOLEUR_BOOTSTRAP_UNSAFE_VARIABLE name=${name}" <<<"$out"; then
      echo "g3: the refusal of ${name} did not name it in the marker: ${out}"
      v=1
    fi
  done
  for name in DEPLOY_REGION LOG_LEVEL; do
    : > "$ghlog"
    out="$(GH_ARGV_LOG="$ghlog" SOLEUR_BOOTSTRAP_LEDGER="$ledger" \
            bash "$SB/drive.sh" "$lib" soleur_op_gh_variable_set owner/repo "$name" eu-central </dev/null 2>&1)"; rc=$?
    if [[ "$rc" -ne 0 ]]; then
      echo "g3: the variable helper REFUSED the non-secret name ${name} (rc=${rc}): ${out}"
      v=1
    fi
    if ! grep -qF "variable set ${name}" "$ghlog"; then
      echo "g3: the non-secret ${name} never reached \`gh variable set\`"
      v=1
    fi
  done

  # row 5 (legacy behavioural half): a secret-shaped name must never reach argv.
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

# row 1 — the secret helper moved onto argv, via the SHORT flag `-b` that the
# static `--body` grep cannot see: the behavioural row is the guard here.
if mutate "g3-r1 secret value onto argv (-b)" "$SB/mut/g3r1.sh" <<'PROG'
s{printf '%s' "\$value" \| gh secret set "\$sec_name" -R "\$repo"}{gh secret set "\$sec_name" -R "\$repo" -b "\$value"}
PROG
then assert_red g3_check "g3-r1 secret value onto argv (-b, invisible to the static grep)" "$SB/mut/g3r1.sh" "$PLUGIN_ROOT"; fi

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
s{(  printf '%s=%s\\n' "\$key" "\$value" >> "\$tmp" \|\| \{ rm -f "\$tmp"; return 1; \}\n)(  # On success[^\n]*\n  # on failure[^\n]*\n)(  soleur_op_env_commit "\$env_file" "\$tmp" "\$before_count" "\$before_count" \|\| \{ rm -f "\$tmp"; return 1; \}\n)}{$3  printf '%s=%s\\n' "\$key" "\$value" >> "\$env_file"\n}
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

# strip_comments <file> — the file without its comment lines. Every window and
# every census below runs over THIS, so a comment naming a helper can never
# satisfy a guard (review P2-26).
strip_comments() { grep -vE '^[[:space:]]*#' "$1"; }

# The census regex: a `read` that STARTS a command — line-initial, after a
# command separator, or after an `IFS=` prefix. `read -` alone missed `IFS= read`
# and `read reply`.
READ_SITE_RE='(^[[:space:]]*|[;&|][[:space:]]*|IFS=[[:space:]]*)read([[:space:]]|$)'

# A raw `read` in a CONSUMER is gated only by an explicit TTY-check LINE right
# above it. A prompt-helper call (`soleur_op_barrier …`) in the same window is a
# different prompt with its own read inside the library and gates nothing here;
# a comment naming the helper gates nothing either (both measured to have
# satisfied the old substring match).
TTY_GATE_LINE_RE='^[[:space:]]*\[\[ -t 0 \]\] \|\| soleur_op_input_required([[:space:]]|$)'

g4_prompt_functions() {
  # Census of every read call site, keyed to its enclosing function, over the
  # comment-stripped source. Discovery, never a name list. `<UNCLASSIFIED>` is a
  # RED bucket, not a skip.
  strip_comments "$1" | awk '
    /^[a-z_]+\(\) \{/ { fn = $1; sub(/\(\)$/, "", fn); next }
    /^\}/             { fn = "" }
    /^[ \t]*read([ \t]|$)|[;&|][ \t]*read([ \t]|$)|IFS=[ \t]*read([ \t]|$)/ {
      if (fn != "") print fn; else print "<UNCLASSIFIED>"
    }
  ' | sort -u
}

# g4_class2_body_ok <fn> <comment-stripped body> — the class-2 constraints
# (review P2-23). A destructive-write ack may consult NOTHING but its prompt and
# the reply: no `printenv`, no expansion of any other name, no `-n`/`-z` test on
# anything but `$reply`. Each is a way an environment variable could buy its way
# past the gate without spelling `soleur_op_skip_value`.
g4_class2_body_ok() {
  local fn="$1" body="$2" ok=0 names bad tests
  if grep -q 'printenv' <<<"$body"; then
    echo "g4: ${fn} is a class-2 ack but calls printenv"; ok=1
  fi
  names="$(grep -oE '\$\{?[A-Za-z_][A-Za-z0-9_]*' <<<"$body" | sed -E 's/^\$\{?//' | sort -u)"
  bad="$(grep -vxE 'prompt_text|reply' <<<"$names" || true)"
  if [[ -n "$bad" ]]; then
    echo "g4: ${fn} is a class-2 ack but expands a name other than prompt_text/reply: $(tr '\n' ' ' <<<"$bad")"; ok=1
  fi
  tests="$(grep -E '\[\[ -[nz] ' <<<"$body" | grep -vE '\[\[ -[nz] "\$reply" \]\]' || true)"
  if [[ -n "$tests" ]]; then
    echo "g4: ${fn} is a class-2 ack but tests -n/-z on something other than \$reply:${tests}"; ok=1
  fi
  return "$ok"
}

g4_check() {
  local lib="$1" root="${2:-$PLUGIN_ROOT}" v=0 fn body idx_tty idx_read fns out rc klass ack_fns=""

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
    body="$(g3_fn_body "$lib" "$fn" | grep -vE '^[[:space:]]*#')"
    idx_read="$(grep -nE "$READ_SITE_RE" <<<"$body" | head -1 | cut -d: -f1)"
    idx_tty="$(grep -nE '^[[:space:]]*\[\[ -t 0 \]\] \|\| soleur_op_input_required' <<<"$body" | head -1 | cut -d: -f1)"
    if [[ -z "$idx_tty" ]]; then
      echo "g4: ${fn} reads without a no-TTY refusal (a line beginning '[[ -t 0 ]] || soleur_op_input_required')"
      v=1
    elif [[ -z "$idx_read" ]]; then
      echo "g4: ${fn} was censused as a prompt but has no read line"
      v=1
    elif [[ "$idx_tty" -ge "$idx_read" ]]; then
      echo "g4: ${fn} checks the TTY at line ${idx_tty}, AFTER its read at line ${idx_read}"
      v=1
    fi

    # Classification (review P2-27). The three library helpers are PINNED to
    # their classes by name. Anything else is classified by what its body DOES:
    # a skip-variable lookup makes it class 1/3; without one it must have the
    # class-2 shape (compare the reply to "yes", abort otherwise) — a prompt with
    # neither is a class-1 prompt missing its skip variable, whatever it is
    # called. So renaming the ack with its property intact stays green, and a
    # value prompt named *_ack_or_die does not get the class-2 exemption.
    case "$fn" in
      soleur_op_value|soleur_op_barrier)
        klass=skip
        if ! grep -q 'soleur_op_skip_value' <<<"$body"; then
          echo "g4: ${fn} is pinned class 1/3 but has no named skip variable"; v=1
        fi ;;
      soleur_op_ack_or_die)
        klass=ack
        if grep -q 'soleur_op_skip_value' <<<"$body"; then
          echo "g4: ${fn} is the class-2 destructive-write ack but consults a skip variable"; v=1
        fi ;;
      *)
        if grep -q 'soleur_op_skip_value' <<<"$body"; then
          klass=skip
        elif grep -q 'soleur_op_aborted' <<<"$body" && grep -qF '== "yes"' <<<"$body"; then
          klass=ack
        else
          klass=none
          echo "g4: ${fn} has no named skip variable and is not a destructive-write ack (no yes-check + abort) — a class-1 prompt with no non-interactive path"
          v=1
        fi ;;
    esac
    if [[ "$klass" == ack ]]; then
      g4_class2_body_ok "$fn" "$body" || v=1
      ack_fns="${ack_fns} ${fn}"
    fi
  done <<<"$fns"

  # --- consumer sweep --------------------------------------------------------
  # D12 keeps the credential prompt in the CALLER, so the caller is where the
  # census must also look — a guard scoped to the library would certify a
  # consumer that hangs. Population is DISCOVERED, and a zero population reddens.
  # Every window is cut from the COMMENT-STRIPPED file and must contain a gate
  # LINE, not a substring.
  local consumer rl ln from window scanned=0 stripped
  while IFS= read -r consumer; do
    [[ -n "$consumer" ]] || continue
    scanned=$((scanned + 1))
    stripped="$(strip_comments "$consumer")"
    while IFS= read -r rl; do
      [[ -n "$rl" ]] || continue
      ln="${rl%%:*}"
      from=$(( ln > 12 ? ln - 12 : 1 ))
      window="$(sed -n "${from},${ln}p" <<<"$stripped")"
      if ! grep -qE "$TTY_GATE_LINE_RE" <<<"$window"; then
        echo "g4: ${consumer}: read site '${rl#*:}' has no TTY-gate LINE in the 12 comment-stripped lines above it"
        v=1
      fi
    done < <(grep -nE "$READ_SITE_RE" <<<"$stripped")
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
  # on purpose — no environment variable may buy its way past this gate. Driven
  # for EVERY function the census classified as a destructive-write ack (by body
  # shape, so a renamed ack is still probed), and RED if there is none.
  if [[ -z "$ack_fns" ]]; then
    echo "g4: the census found NO destructive-write ack (class 2) in the library"
    v=1
  fi
  for fn in $ack_fns; do
    out="$(SOLEUR_BOOTSTRAP_ACK=yes SOLEUR_TEST_SKIP_ACK=yes SOLEUR_BOOTSTRAP_ASSUME_YES=1 \
            timeout 1 bash "$SB/drive.sh" "$lib" "$fn" 'Create billable server? Type yes: ' \
            <"$BLOCK_FIFO" 2>&1)"; rc=$?
    if [[ "$rc" -ne 64 ]]; then
      echo "g4: class-2 ack ${fn} exited ${rc} with skip-shaped variables set, expected 64 unconditionally"
      v=1
    fi
    if ! grep -qF 'SOLEUR_BOOTSTRAP_INPUT_REQUIRED' <<<"$out"; then
      echo "g4: class-2 ack ${fn} did not emit SOLEUR_BOOTSTRAP_INPUT_REQUIRED"
      v=1
    fi
  done

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
s{  soleur_op_run_halt input_required "\$1"\n  exit 64}{  soleur_op_run_halt input_required "\$1"\n  exit 1}
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

# row 7c — the census must see `IFS= read`, and a COMMENT naming the gate must
# not satisfy the window: gate line deleted, `IFS=` prefixed, comment added.
if [[ -r "$HETZNER_SRC" ]]; then
  mkdir -p "$SB/run/consumer-mut2"
  cp "$HETZNER_SRC" "$SB/run/consumer-mut2/provision-hetzner.sh"
  perl -0777 -pi -e 's{^  \[\[ -t 0 \]\] \|\| soleur_op_input_required SOLEUR_BOOTSTRAP_HCLOUD_TOKEN\n  read -rs -p }{  # gated: [[ -t 0 ]] || soleur_op_input_required SOLEUR_BOOTSTRAP_HCLOUD_TOKEN\n  IFS= read -rs -p }m' \
    "$SB/run/consumer-mut2/provision-hetzner.sh"
  if [[ "$(md5_of "$SB/run/consumer-mut2/provision-hetzner.sh")" == "$(md5_of "$HETZNER_SRC")" ]]; then
    fail "mutation 'g4-r7c IFS= read behind a comment-only gate' did NOT land"
  else
    pass "mutation 'g4-r7c IFS= read behind a comment-only gate' landed (md5 differs from the live script)"
    assert_red g4_check "g4-r7c IFS= read with the gate only in a comment" "$PRISTINE" "$SB/run/consumer-mut2"
  fi
fi

# row 8 — the ack RENAMED with its property intact must stay GREEN: the class is
# a property of the body, not of the name suffix (review P2-27).
if mutate "g4-r8 ack renamed, property intact" "$SB/mut/g4r8.sh" <<'PROG'
s{soleur_op_ack_or_die}{soleur_op_confirm_write}g
PROG
then assert_green g4_check "g4-r8 renamed ack keeps its class by body shape" "$SB/mut/g4r8.sh"; fi

# row 9 — a class-1 VALUE prompt that happens to be named *_ack_or_die, with no
# skip variable: the old suffix rule exempted it; the body rule must RED it.
if mutate "g4-r9 class-1 prompt misnamed *_ack_or_die" "$SB/mut/g4r9.sh" <<'PROG'
s{\n# --- MUTATION ANCHOR: end of prompt helpers ---}{\nsoleur_op_region_ack_or_die() {\n  local prompt_text="\$1" out_name="\$2" reply\n  [[ -t 0 ]] || soleur_op_input_required "region"\n  read -r -p "\$prompt_text" reply\n  printf -v "\$out_name" '%s' "\$reply"\n}\n\n# --- MUTATION ANCHOR: end of prompt helpers ---}
PROG
then assert_red g4_check "g4-r9 misnamed class-1 prompt without a skip variable" "$SB/mut/g4r9.sh"; fi

# row 10 — the ack bypassed by a plain environment test, never spelling
# `soleur_op_skip_value` (review P2-23).
if mutate "g4-r10 ack bypass via a bare environment test" "$SB/mut/g4r10.sh" <<'PROG'
s{(soleur_op_ack_or_die\(\) \{\n  local prompt_text="\$1" reply\n)}{$1  [[ -z "\$\{SOLEUR_BOOTSTRAP_ASSUME_YES:-\}" ]] || return 0\n}
PROG
then assert_red g4_check "g4-r10 ASSUME_YES bypass without soleur_op_skip_value" "$SB/mut/g4r10.sh"; fi

# row 11 — the same bypass through printenv
if mutate "g4-r11 ack bypass via printenv" "$SB/mut/g4r11.sh" <<'PROG'
s{(soleur_op_ack_or_die\(\) \{\n  local prompt_text="\$1" reply\n)}{$1  [[ -z "\$(printenv SOLEUR_BOOTSTRAP_ASSUME_YES)" ]] || return 0\n}
PROG
then assert_red g4_check "g4-r11 printenv bypass" "$SB/mut/g4r11.sh"; fi

# harness (a) — the no-TTY case runs under `timeout`. Asserted two ways, because
# the literal "remove the timeout wrapper" would hang this runner:
#   (i)  the probe helper's own definition names `timeout`;
#   (ii) the COMPLIANT library exits **64**, not 124, against the SAME blocked
#        stdin — so row 3's RED is the reorder being caught, not the wrapper
#        killing every run alike (the compliant path exits in ~10ms, so 1s is
#        generous; two expiries under the old 5s were 10 of the suite's 11s). A
#        30s bound stays on THIS probe rather
#        than removing it literally: an unwrapped probe against a regressed
#        library would hang the runner, which is the failure the wrapper exists
#        to prevent.
if grep -q 'timeout 1 bash' <<<"$(declare -f drive_blocked)"; then
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
# Guard 8 — the decline path, driven through a real pty (review P1-4)
# =============================================================================
#
# Property. Answered `no` or nothing, the barrier and the ack exit 1 with
# SOLEUR_BOOTSTRAP_ABORTED stage=<kind>, the founder sentence, and a run_halt
# ledger line; answered `yes`, they exit 0. Observed by typing into a pty with
# script(1), because `[[ -t 0 ]]` is true there and the read actually runs — the
# blocked-FIFO probes above can only ever see the no-TTY branch.

pty_drive() {
  # pty_drive <answer> <ledger> <lib> <fn> <args...>  — stdout+stderr (CRLF
  # stripped), rc in $?. The answer is fed through script's stdin.
  local answer="$1" ledger="$2"; shift 2
  local cmd
  printf -v cmd '%q ' bash "$SB/drive.sh" "$@"
  printf '%s' "$answer" | SOLEUR_BOOTSTRAP_LEDGER="$ledger" timeout 5 script -qec "$cmd" /dev/null 2>&1 | tr -d '\r'
  return "${PIPESTATUS[1]}"
}

gdecline_check() {
  local lib="$1" v=0 out rc fn kind ledger="$SB/decline.jsonl"
  for fn in soleur_op_ack_or_die soleur_op_barrier; do
    kind="ack"; [[ "$fn" == soleur_op_barrier ]] && kind="barrier"
    local -a args=("$fn")
    [[ "$fn" == soleur_op_barrier ]] && args=("$fn" SOLEUR_TEST_SKIP_DECLINE)
    args+=("Type yes: ")

    : > "$ledger"
    out="$(pty_drive $'no\n' "$ledger" "$lib" "${args[@]}")"; rc=$?
    if [[ "$rc" -ne 1 ]]; then echo "gdecline: ${fn} answered 'no' exited ${rc}, expected 1: ${out}"; v=1; fi
    if ! grep -qF "SOLEUR_BOOTSTRAP_ABORTED stage=${kind}" <<<"$out"; then
      echo "gdecline: ${fn} answered 'no' did not emit ABORTED stage=${kind}: ${out}"; v=1
    fi
    if ! grep -qF 'Stopped. Nothing was created.' <<<"$out"; then
      echo "gdecline: ${fn} answered 'no' printed no founder sentence"; v=1
    fi
    if ! grep -qE "\"event\":\"run_halt\",\"reason\":\"aborted\",\"var\":\"${kind}\"" "$ledger"; then
      echo "gdecline: ${fn} answered 'no' wrote no run_halt line: $(cat "$ledger")"; v=1
    fi

    out="$(pty_drive $'\n' "$ledger" "$lib" "${args[@]}")"; rc=$?
    if [[ "$rc" -ne 1 ]] || ! grep -qF 'SOLEUR_BOOTSTRAP_ABORTED' <<<"$out"; then
      echo "gdecline: ${fn} answered EMPTY exited ${rc}, expected 1 + ABORTED: ${out}"; v=1
    fi

    out="$(pty_drive $'yes\n' "$ledger" "$lib" "${args[@]}")"; rc=$?
    if [[ "$rc" -ne 0 ]]; then echo "gdecline: ${fn} answered 'yes' exited ${rc}, expected 0: ${out}"; v=1; fi
    if grep -qF 'SOLEUR_BOOTSTRAP_ABORTED' <<<"$out"; then
      echo "gdecline: ${fn} answered 'yes' still emitted ABORTED"; v=1
    fi
  done
  return "$v"
}

echo "== Guard 8 — decline path through a pty =="

assert_green gdecline_check "pristine library" "$PRISTINE"

# row 1 — the ack's yes-check replaced by `:` (every answer accepted)
if mutate "gdecline-r1 ack yes-check replaced by ':'" "$SB/mut/gd1.sh" <<'PROG'
s{  \[\[ "\$reply" == "yes" \]\] \|\| soleur_op_aborted ack\n}{  :\n}
PROG
then assert_red gdecline_check "gdecline-r1 ack accepts any answer" "$SB/mut/gd1.sh"; fi

# row 2 — the barrier's yes-check replaced by `:`
if mutate "gdecline-r2 barrier yes-check replaced by ':'" "$SB/mut/gd2.sh" <<'PROG'
s{  \[\[ "\$reply" == "yes" \]\] \|\| soleur_op_aborted barrier\n}{  :\n}
PROG
then assert_red gdecline_check "gdecline-r2 barrier accepts any answer" "$SB/mut/gd2.sh"; fi

# row 3 — the decline no longer reaches the ledger
if mutate "gdecline-r3 aborted writes no run_halt" "$SB/mut/gd3.sh" <<'PROG'
s{  soleur_op_run_halt aborted "\$1"\n}{}
PROG
then assert_red gdecline_check "gdecline-r3 decline invisible in the ledger" "$SB/mut/gd3.sh"; fi

# =============================================================================
# Guard 9 — every destructive write in a consumer sits under an ack (P1-3)
# =============================================================================
#
# Property. In every DISCOVERED consumer, each `hcloud server create`,
# `gh secret set`, `gh variable set`, Doppler secret write, `terraform apply`
# and each `soleur_op_gh_*_set` call has `soleur_op_ack_or_die` within the 15
# comment-stripped lines above it. Quoted output (`echo "… hcloud server create
# …"`) is not a call. Zero destructive sites across the population is RED: the
# proving consumer has one, so a census that sees none is broken.

DESTRUCTIVE_RE='(^|[^A-Za-z0-9_"'"'"'])(hcloud server create|gh secret set|gh variable set|doppler secrets (set|upload)|terraform apply|soleur_op_gh_(secret|variable)_set)([[:space:]]|$)'

gack_check() {
  local root="$1" v=0 consumer stripped rl ln from window sites=0
  while IFS= read -r consumer; do
    [[ -n "$consumer" ]] || continue
    stripped="$(strip_comments "$consumer" | grep -vE '^[[:space:]]*(echo|printf)[[:space:]]')"
    while IFS= read -r rl; do
      [[ -n "$rl" ]] || continue
      sites=$((sites + 1))
      ln="${rl%%:*}"
      from=$(( ln > 15 ? ln - 15 : 1 ))
      window="$(sed -n "${from},$((ln - 1))p" <<<"$stripped")"
      if ! grep -qE '^[[:space:]]*soleur_op_ack_or_die([[:space:]]|$)' <<<"$window"; then
        echo "gack: ${consumer}: destructive write '${rl#*:}' has no soleur_op_ack_or_die in the 15 comment-stripped lines above it"
        v=1
      fi
    done < <(grep -nE "$DESTRUCTIVE_RE" <<<"$stripped")
  done < <(g3_sourcing_scripts "$root")
  if [[ "$sites" -eq 0 ]]; then
    echo "gack: the census found ZERO destructive-write sites across the sourcing scripts — nothing was checked"
    v=1
  fi
  return "$v"
}

echo "== Guard 9 — destructive writes sit under an ack =="

assert_green gack_check "live consumers" "$PLUGIN_ROOT"
assert_red gack_check "gack own-dispatch: zero consumers" "$SB/empty"

if [[ -r "$HETZNER_SRC" ]]; then
  mkdir -p "$SB/run/ack-mut"
  cp "$HETZNER_SRC" "$SB/run/ack-mut/provision-hetzner.sh"
  perl -0777 -pi -e 's{^soleur_op_ack_or_die "Create the billable probe server[^\n]*\n}{}m' "$SB/run/ack-mut/provision-hetzner.sh"
  if [[ "$(md5_of "$SB/run/ack-mut/provision-hetzner.sh")" == "$(md5_of "$HETZNER_SRC")" ]]; then
    fail "mutation 'gack-r1 hetzner ack line deleted' did NOT land"
  else
    pass "mutation 'gack-r1 hetzner ack line deleted' landed (md5 differs from the live script)"
    assert_red gack_check "gack-r1 billable create with no ack above it" "$SB/run/ack-mut"
  fi
  # A comment naming the ack must not satisfy the window.
  mkdir -p "$SB/run/ack-mut2"
  cp "$HETZNER_SRC" "$SB/run/ack-mut2/provision-hetzner.sh"
  perl -0777 -pi -e 's{^soleur_op_ack_or_die "Create the billable probe server[^\n]*\n}{# soleur_op_ack_or_die "Create the billable probe server" (commented out)\n}m' "$SB/run/ack-mut2/provision-hetzner.sh"
  if [[ "$(md5_of "$SB/run/ack-mut2/provision-hetzner.sh")" != "$(md5_of "$HETZNER_SRC")" ]]; then
    assert_red gack_check "gack-r2 ack present only as a comment" "$SB/run/ack-mut2"
  else
    fail "mutation 'gack-r2 ack commented out' did NOT land"
  fi
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

# The acquire set is what the linter knows PLUS `read -s` (the shape both the
# template's stages and provision-hetzner.sh use): `read -rs`, `read -s`, `curl
# -u`, `doppler secrets get`, `gh auth token`, `Authorization: Bearer`. The
# source anchor accepts `source ` and `. `.
ACQUIRES_RE='read -[a-z]*s( |$)|read -s( |$)|curl -u|doppler secrets get|gh auth token|Authorization: *Bearer'

g5_check() {
  # g5_check <lib> <root> <template>  — the template is FORCE-INCLUDED (review
  # P2-25): it acquires nothing itself, so the population walk skipped the one
  # prologue every generated script inherits.
  local lib="$1" root="$2" template="$3" v=0 lib_body consumer acquires src_ln ref_ln
  lib_body="$(grep -vE '^[[:space:]]*#' "$lib")"
  if grep -qE '\$\{?[A-Za-z_][A-Za-z0-9_]*_(TOKEN|KEY|SECRET|PASSWORD|PAT)\}?([^A-Za-z0-9_]|$)' <<<"$lib_body"; then
    echo "g5: library-expands-secret-shaped-name"; v=1
  fi
  if grep -qE '\$\{!' <<<"$lib_body"; then
    echo "g5: library-uses-indirect-expansion"; v=1
  fi
  if grep -qE 'doppler secrets get|gh auth token' <<<"$lib_body"; then
    echo "g5: library-acquires-a-credential"; v=1
  fi
  while IFS= read -r consumer; do
    [[ -n "$consumer" ]] || continue
    if [[ "$consumer" != "$template" ]]; then
      acquires="$(grep -vE '^[[:space:]]*#' "$consumer" | grep -cE "$ACQUIRES_RE" || true)"
      [[ "$acquires" -gt 0 ]] || continue
    fi
    src_ln="$(grep -nE '^[[:space:]]*(source|\.)[[:space:]]' "$consumer" | head -1 | cut -d: -f1)"
    ref_ln="$(grep -n '^[[:space:]]*case "\$-" in' "$consumer" | head -1 | cut -d: -f1)"
    if [[ -z "$ref_ln" ]]; then
      echo "g5: ${consumer}: no-xtrace-refusal"; v=1
    elif [[ -n "$src_ln" && "$ref_ln" -gt "$src_ln" ]]; then
      echo "g5: ${consumer}: refusal-below-source"; v=1
    fi
  done < <(printf '%s\n%s\n' "$template" "$(g3_sourcing_scripts "$root")" | awk 'NF && !seen[$0]++')
  return "$v"
}

echo "== Guard 5' — prologue above source, library out of credential scope =="

assert_green g5_check "pristine library + live consumers + template" "$PRISTINE" "$PLUGIN_ROOT" "${PLUGIN_ROOT}/skills/operator-bootstrap/template.sh"

# row 1 — the template's prologue deleted: the one every generated script inherits
cp "${PLUGIN_ROOT}/skills/operator-bootstrap/template.sh" "$SB/mut/tpl-noprologue.sh"
perl -0777 -pi -e 's{case "\$-" in\n  \*x\*\)\n.*?\nesac\n}{}s' "$SB/mut/tpl-noprologue.sh"
if [[ "$(md5_of "$SB/mut/tpl-noprologue.sh")" == "$(md5_of "${PLUGIN_ROOT}/skills/operator-bootstrap/template.sh")" ]]; then
  fail "mutation 'g5-r1 template prologue deleted' did NOT land"
else
  pass "mutation 'g5-r1 template prologue deleted' landed (md5 differs from the live template)"
  assert_red g5_check "g5-r1 template without its xtrace refusal" "$PRISTINE" "$PLUGIN_ROOT" "$SB/mut/tpl-noprologue.sh"
fi

# row 2 — the template's prologue moved BELOW its source line
cp "${PLUGIN_ROOT}/skills/operator-bootstrap/template.sh" "$SB/mut/tpl-below.sh"
perl -0777 -pi -e 's{(case "\$-" in\n  \*x\*\)\n.*?\nesac\n)(.*?)(source "\$SOLEUR_OP_LIB"\n)}{$2$3$1}s' "$SB/mut/tpl-below.sh"
if [[ "$(md5_of "$SB/mut/tpl-below.sh")" == "$(md5_of "${PLUGIN_ROOT}/skills/operator-bootstrap/template.sh")" ]]; then
  fail "mutation 'g5-r2 template prologue below source' did NOT land"
else
  pass "mutation 'g5-r2 template prologue below source' landed"
  assert_red g5_check "g5-r2 template refusal below its source line" "$PRISTINE" "$PLUGIN_ROOT" "$SB/mut/tpl-below.sh"
fi

# row 3 — a consumer acquiring via `curl -u` with no prologue (the widened set)
mkdir -p "$SB/run/curlu"
cat > "$SB/run/curlu/consumer.sh" <<'CONSUMER'
#!/usr/bin/env bash
set -euo pipefail
. "$(dirname "$0")/../../pristine-operator-script.sh"   # lib/operator-script.sh
curl -u "user:$1" https://example.invalid/
CONSUMER
assert_red g5_check "g5-r3 consumer acquiring via curl -u, no refusal, sourced with '.'" "$PRISTINE" "$SB/run/curlu" "${PLUGIN_ROOT}/skills/operator-bootstrap/template.sh"

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

# The API surface: the three prompt helpers exist under their pinned names (Guard
# 4 classifies by body so a rename stays green THERE; the consumers call these
# names, so a rename is an API break caught HERE).
for api_fn in soleur_op_value soleur_op_barrier soleur_op_ack_or_die soleur_op_env_upsert soleur_op_env_reset \
              soleur_op_gh_secret_set soleur_op_gh_variable_set soleur_op_ledger_init soleur_op_stage_begin soleur_op_stage_end; do
  if bash -c 'set -uo pipefail; source "$1"; declare -F "$2" >/dev/null' _ "$LIB" "$api_fn" 2>/dev/null; then
    pass "API: ${api_fn} is defined after source"
  else
    fail "API: ${api_fn} is not defined after source — a consumer calling it dies mid-stage"
  fi
done

# The API number is hand-replicated in every consumer's gate and marker. All of
# them must agree with the value the library exports, or a correct library is
# refused (or an incompatible one admitted) on a spelling mismatch.
api_exported="$(bash -c 'set -uo pipefail; source "$1"; printf "%s" "${SOLEUR_OP_LIB_API:-0}"' _ "$LIB" 2>/dev/null)"
api_consumers=0
api_bad=""
while IFS= read -r consumer; do
  [[ -n "$consumer" ]] || continue
  grep -q 'SOLEUR_OP_LIB_API' "$consumer" || continue
  api_consumers=$((api_consumers + 1))
  grep -qE "\[\[ \\\$\{SOLEUR_OP_LIB_API:-0\} -eq ${api_exported} \]\]" "$consumer" \
    || api_bad="${api_bad} ${consumer}:gate"
  grep -qF "SOLEUR_BOOTSTRAP_LIB_INCOMPATIBLE need=${api_exported} got=" "$consumer" \
    || api_bad="${api_bad} ${consumer}:marker"
done < <(printf '%s\n%s\n' "${PLUGIN_ROOT}/skills/operator-bootstrap/template.sh" "$(g3_sourcing_scripts "$PLUGIN_ROOT")" | awk 'NF && !seen[$0]++')
if [[ "$api_consumers" -lt 2 ]]; then
  fail "API: only ${api_consumers} consumer(s) assert SOLEUR_OP_LIB_API — the census is broken"
elif [[ -n "$api_bad" ]]; then
  fail "API: consumers disagree with the exported SOLEUR_OP_LIB_API=${api_exported}:${api_bad}"
else
  pass "API: all ${api_consumers} consumers gate on -eq ${api_exported} and spell need=${api_exported} in the marker"
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

# P2-11 — an opener that never returns (xdg-open handing the URL to a terminal
# browser on a box with no DISPLAY) must not stall the caller or eat its stdin.
# Observed: a blocking xdg-open stub, and the caller must reach its next line.
cat > "$SB/bin/xdg-open" <<'STUB'
#!/usr/bin/env bash
cat >/dev/null   # seize stdin like w3m would
sleep 20
STUB
chmod +x "$SB/bin/xdg-open"
ou_out="$(printf 'the-next-answer\n' | env -u WSL_DISTRO_NAME -u WSL_INTEROP timeout 5 bash -c '
  set -uo pipefail
  source "$1"
  soleur_op_open_url "https://example.invalid/x"
  read -r nxt
  printf "RETURNED next=%s\n" "$nxt"
' _ "$LIB" 2>&1)"; ou_rc=$?
if [[ "$ou_rc" -eq 0 ]] && grep -qF 'RETURNED next=the-next-answer' <<<"$ou_out"; then
  pass "open_url: a blocking opener neither stalls the caller nor consumes the caller's stdin (background, stdin detached)"
else
  fail "open_url: caller stalled or lost its stdin behind a blocking opener (rc=${ou_rc}): ${ou_out}"
fi
printf '#!/usr/bin/env bash\nexit 0\n' > "$SB/bin/xdg-open"

# SOLEUR_OP_NO_OPEN=1 — the URL is still printed, no opener runs. Observed
# through a logging stub on every arm; the log must stay empty. Negative
# control: the same call without the variable does reach the stub. The stubs
# live in their OWN directory: the P2-11 arm above leaves a backgrounded
# `sleep 20` reading $SB/bin/xdg-open, and bash re-reads a script file it is
# still executing, so rewriting that file mid-run is a race.
no_open_log="$SB/no-open.log"
mkdir -p "$SB/bin-noopen"
for opener in xdg-open open wslview explorer.exe; do
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "%s"\nexit 0\n' "$no_open_log" > "$SB/bin-noopen/$opener"
  chmod +x "$SB/bin-noopen/$opener"
done
no_out="$(PATH="$SB/bin-noopen:$PATH" SOLEUR_OP_NO_OPEN=1 env -u WSL_DISTRO_NAME -u WSL_INTEROP bash "$SB/drive.sh" "$LIB" soleur_op_open_url "https://example.invalid/no-open" 2>&1)"
sleep 1
if grep -qF 'https://example.invalid/no-open' <<<"$no_out" && [[ ! -s "$no_open_log" ]]; then
  pass "open_url: SOLEUR_OP_NO_OPEN=1 prints the URL and launches no opener"
else
  fail "open_url: SOLEUR_OP_NO_OPEN=1 leaked to an opener or dropped the URL: out=${no_out} log=$(cat "$no_open_log" 2>/dev/null)"
fi
PATH="$SB/bin-noopen:$PATH" env -u SOLEUR_OP_NO_OPEN -u WSL_DISTRO_NAME -u WSL_INTEROP bash "$SB/drive.sh" "$LIB" soleur_op_open_url "https://example.invalid/do-open" >/dev/null 2>&1
sleep 1
if grep -qF 'https://example.invalid/do-open' "$no_open_log" 2>/dev/null; then
  pass "open_url: without SOLEUR_OP_NO_OPEN the opener is reached (negative control for the escape hatch)"
else
  fail "open_url: negative control — the opener stub was never reached: log=$(cat "$no_open_log" 2>/dev/null)"
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

  # F6b — the consumer-side contract refuses a library whose API number moved
  # PAST the one it was generated against, BEFORE any ledger write. The library
  # ships with the plugin and updates under a frozen script, so "newer" is the
  # only incompatibility that can happen; `-ge` admitted it and the script died
  # mid-stage on the renamed helper instead (review, lead's coverage consult).
  newer_lib="$SB/newer-lib.sh"
  { cat "$LIB"; printf '\nexport SOLEUR_OP_LIB_API=2\nunset -f soleur_op_barrier\n'; } > "$newer_lib"
  newer_ledger="$SB/newer-api-ledger.jsonl"
  rm -f "$newer_ledger"
  newer_out="$(cd "$SB/founder-repo" && env -u CLAUDE_PLUGIN_ROOT SOLEUR_OP_LIB="$newer_lib" \
    SOLEUR_BOOTSTRAP_LEDGER="$newer_ledger" SOLEUR_BOOTSTRAP_SKIP_ACCOUNT_BARRIER=1 \
    SOLEUR_BOOTSTRAP_ACCOUNT_ID=a timeout 10 bash knowledge-base/project/specs/feat-x/bootstrap.sh </dev/null 2>&1)"; newer_rc=$?
  if [[ "$newer_rc" -eq 64 ]] && grep -qF 'SOLEUR_BOOTSTRAP_LIB_INCOMPATIBLE need=1 got=2' <<<"$newer_out"; then
    pass "F6b: a library whose API moved to 2 is refused with LIB_INCOMPATIBLE need=1 got=2, exit 64"
  else
    fail "F6b: a newer-API library was not refused (rc=${newer_rc}): ${newer_out}"
  fi
  if [[ ! -e "$newer_ledger" ]]; then
    pass "F6b: the refusal happens BEFORE any ledger write (no ledger file exists)"
  else
    fail "F6b: the refused run still wrote a ledger: $(cat "$newer_ledger")"
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

# =============================================================================
# Terminal outcome — every refusal is a marker PLUS a sentence, and the ledger
# can say something other than "ok" (review P2-12, P2-13)
# =============================================================================

echo "== terminal outcome =="

rb_out="$(bash "$SB/drive.sh" "$LIB" soleur_op_require_bins grep nonexistent-bin-xyz </dev/null 2>/dev/null)"; rb_rc=$?
if [[ "$rb_rc" -eq 64 ]] && grep -qF 'SOLEUR_BOOTSTRAP_MISSING_BINARY bin=nonexistent-bin-xyz' <<<"$rb_out"; then
  pass "require_bins: a missing binary emits SOLEUR_BOOTSTRAP_MISSING_BINARY on STDOUT and exits 64"
else
  fail "require_bins: expected the marker on stdout and rc 64 (rc=${rb_rc}): ${rb_out}"
fi
if grep -qF 'Install nonexistent-bin-xyz first, then run again.' <<<"$rb_out"; then
  pass "require_bins: the marker is followed by the plain-language remedy"
else
  fail "require_bins: no plain-language remedy after the marker: ${rb_out}"
fi

to_ledger="$SB/to-ledger.jsonl"
to_out="$(SOLEUR_BOOTSTRAP_LEDGER="$to_ledger" drive_blocked "$LIB" soleur_op_barrier SOLEUR_TEST_SKIP_BARRIER 'x: ')"
if grep -qF 'This step needs you to type an answer. Run this script in your own terminal, or set SOLEUR_TEST_SKIP_BARRIER and run again.' <<<"$to_out"; then
  pass "INPUT_REQUIRED (class 1/3): the sentence names the variable to set"
else
  fail "INPUT_REQUIRED (class 1/3): no founder sentence naming the variable: ${to_out}"
fi
if grep -qE '"event":"run_halt","reason":"input_required","var":"SOLEUR_TEST_SKIP_BARRIER"' "$to_ledger" 2>/dev/null; then
  pass "INPUT_REQUIRED: the ledger carries a run_halt line naming the variable"
else
  fail "INPUT_REQUIRED: no run_halt line in the ledger: $(cat "$to_ledger" 2>/dev/null)"
fi
to_out="$(SOLEUR_BOOTSTRAP_LEDGER="$to_ledger" drive_blocked "$LIB" soleur_op_ack_or_die 'Create? ')"
if grep -qF 'no setting can answer it for you' <<<"$to_out" && ! grep -qF 'or set ' <<<"$to_out"; then
  pass "INPUT_REQUIRED (class 2): the sentence hands the run to a person and names NO variable to set"
else
  fail "INPUT_REQUIRED (class 2): wrong remedy sentence for the ack: ${to_out}"
fi

# The template's EXIT trap, observed on the baked copy from F1: a run that stops
# inside a stage prints the stage, the fact that nothing else changed, and the
# resume command; the ledger settles the stage as failed with the exit code.
if [[ -r "$gen_home/bootstrap.sh" ]]; then
  tpl_env_dir="$SB/founder-repo/knowledge-base/project/specs/feat-x"
  rm -f "$tpl_env_dir/.env" "$tpl_env_dir/bootstrap-runs.jsonl"
  tpl_out="$(cd "$SB/founder-repo" && env -u CLAUDE_PLUGIN_ROOT -u SOLEUR_OP_LIB \
    SOLEUR_BOOTSTRAP_SKIP_ACCOUNT_BARRIER=1 SOLEUR_BOOTSTRAP_ACCOUNT_ID=acct-1 \
    timeout 10 bash knowledge-base/project/specs/feat-x/bootstrap.sh </dev/null 2>&1)"; tpl_rc=$?
  if [[ "$tpl_rc" -eq 64 ]] && grep -qF 'Stopped during stage 2 (provision the resource). Nothing else was changed. Run: bash ' <<<"$tpl_out" \
     && grep -qF 'already-done steps are skipped.' <<<"$tpl_out"; then
    pass "template trap: a stop inside stage 2 prints the stage, 'nothing else was changed' and the resume command (rc 64)"
  else
    fail "template trap: expected the 'Stopped during stage 2' banner and rc 64 (rc=${tpl_rc}): ${tpl_out}"
  fi
  if grep -qE '"phase":"settle","stage_index":2,.*"outcome":"failed","exit_code":64' "$tpl_env_dir/bootstrap-runs.jsonl" 2>/dev/null \
     && grep -qF '"event":"run_halt"' "$tpl_env_dir/bootstrap-runs.jsonl"; then
    pass "template trap: the ledger settles stage 2 as failed/64 and carries the run_halt line"
  else
    fail "template trap: ledger lacks the failed settle or the run_halt: $(cat "$tpl_env_dir/bootstrap-runs.jsonl" 2>/dev/null)"
  fi
  # The partial-write arm. `SOLEUR_BOOTSTRAP_SECRET_VERIFY_FAILED` means the
  # write MAY be live, so the trap must not say nothing changed — that sentence
  # is what stops a founder revoking. Driven through the flag the library
  # raises on that path.
  rm -f "$tpl_env_dir/.env" "$tpl_env_dir/bootstrap-runs.jsonl"
  tpl_warn_out="$(cd "$SB/founder-repo" && env -u CLAUDE_PLUGIN_ROOT -u SOLEUR_OP_LIB \
    SOLEUR_OP_WRITE_MAY_HAVE_LANDED=1 \
    SOLEUR_BOOTSTRAP_SKIP_ACCOUNT_BARRIER=1 SOLEUR_BOOTSTRAP_ACCOUNT_ID=acct-1 \
    timeout 10 bash knowledge-base/project/specs/feat-x/bootstrap.sh </dev/null 2>&1)"
  if grep -qF 'A credential may already have been written' <<<"$tpl_warn_out" \
     && ! grep -qF 'Nothing else was changed' <<<"$tpl_warn_out"; then
    pass "template trap: a run where a write may have landed does NOT claim nothing changed"
  else
    fail "template trap: the may-have-landed run still claimed nothing changed: ${tpl_warn_out}"
  fi
  # The library must be what raises the flag, not only the harness.
  if grep -qF 'SOLEUR_OP_WRITE_MAY_HAVE_LANDED=1' "$LIB" \
     && [[ "$(grep -c 'SOLEUR_OP_WRITE_MAY_HAVE_LANDED' "$LIB")" -ge 2 ]]; then
    pass "library raises SOLEUR_OP_WRITE_MAY_HAVE_LANDED on the verify-failed path"
  else
    fail "library never sets SOLEUR_OP_WRITE_MAY_HAVE_LANDED — the trap branch is unreachable in production"
  fi

  if grep -qF 'Stopped during stage 1' <<<"$tpl_out"; then
    fail "template trap: stage 1 completed but was reported as stopped"
  else
    pass "template trap: a completed stage is not reported as stopped"
  fi
  help_out="$(cd "$SB/founder-repo" && env -u CLAUDE_PLUGIN_ROOT -u SOLEUR_OP_LIB timeout 10 bash knowledge-base/project/specs/feat-x/bootstrap.sh --bogus 2>&1)"
  if grep -qF 'Stopped during stage' <<<"$help_out"; then
    fail "template trap: a usage error printed the stage banner (the trap is installed above argument validation)"
  else
    pass "template trap: a usage error prints no stage banner"
  fi
else
  fail "terminal outcome: the baked template copy from F1 is missing"
fi

# =============================================================================
# Guard 7 — the credentials file must be gitignored before the first write (P1-1)
# =============================================================================
#
# The generated script lives in a TRACKED directory. Observed on a real git
# fixture, never on the source text: a repo whose .gitignore does not cover the
# .env (or its `.tmp.XXXXXX` sibling) must stop with ENV_NOT_IGNORED and write
# nothing; a repo that covers both proceeds to the first stage.

echo "== Guard 7 — .env gitignored before the first write =="

gign_run() {
  # gign_run <repo> <script-rel> — runs the baked script inside the fixture repo
  # with the class-1/3 skip variables set and no TTY.
  ( cd "$1" && env -u CLAUDE_PLUGIN_ROOT -u SOLEUR_OP_LIB \
      SOLEUR_BOOTSTRAP_SKIP_ACCOUNT_BARRIER=1 SOLEUR_BOOTSTRAP_ACCOUNT_ID=acct-1 \
      timeout 10 bash "$2" </dev/null 2>&1 )
}

gign_check() {
  # gign_check <baked-script>  — three fixtures, one property.
  local script="$1" v=0 repo rel="knowledge-base/project/specs/feat-y/bootstrap.sh" out rc
  repo="$SB/gitrepo"
  rm -rf "$repo"; mkdir -p "$repo/knowledge-base/project/specs/feat-y"
  cp "$script" "$repo/$rel"
  git_fixture_env "$repo" >/dev/null 2>&1 || { echo "gign: git_fixture_env refused the fixture"; return 1; }
  git -C "$repo" init -q . || { echo "gign: git init failed"; return 1; }

  # (a) nothing ignored → refuse, name the .env, write nothing
  out="$(gign_run "$repo" "$rel")"; rc=$?
  if [[ "$rc" -ne 64 ]] || ! grep -qF "SOLEUR_BOOTSTRAP_ENV_NOT_IGNORED path=" <<<"$out" || ! grep -qF '/feat-y/.env' <<<"$out"; then
    echo "gign: un-ignored .env was not refused with ENV_NOT_IGNORED + rc 64 (rc=${rc}): ${out}"; v=1
  fi
  if ! grep -qF 'The credentials file would be committed. Add it to .gitignore first' <<<"$out"; then
    echo "gign: no plain-language sentence after the marker"; v=1
  fi
  if [[ -e "$repo/knowledge-base/project/specs/feat-y/.env" ]]; then
    echo "gign: the refused run still created the .env"; v=1
  fi
  # (b) .env ignored, its temp sibling not → refuse, name the sibling
  printf '.env\n' > "$repo/.gitignore"
  out="$(gign_run "$repo" "$rel")"; rc=$?
  if [[ "$rc" -ne 64 ]] || ! grep -qF 'SOLEUR_BOOTSTRAP_ENV_NOT_IGNORED path=' <<<"$out" || ! grep -qF '.env.tmp.XXXXXX' <<<"$out"; then
    echo "gign: un-ignored .env.tmp.XXXXXX sibling was not refused (rc=${rc}): ${out}"; v=1
  fi
  # (c) both ignored → proceeds to stage 1, writes the .env, stops at the ack
  printf '.env*\n' > "$repo/.gitignore"
  out="$(gign_run "$repo" "$rel")"; rc=$?
  if grep -qF 'SOLEUR_BOOTSTRAP_ENV_NOT_IGNORED' <<<"$out"; then
    echo "gign: an ignored .env was refused"; v=1
  fi
  if ! grep -q '^EXAMPLE_ACCOUNT_ID=acct-1$' "$repo/knowledge-base/project/specs/feat-y/.env" 2>/dev/null; then
    echo "gign: the ignored-.env run did not proceed to write stage 1's key (rc=${rc}): ${out}"; v=1
  fi
  if [[ -n "$(git -C "$repo" status --porcelain --untracked-files=all -- knowledge-base/project/specs/feat-y/.env 2>/dev/null)" ]]; then
    echo "gign: the .env is visible to git status in the ignored fixture"; v=1
  fi

  # (d) THE PROBE MUST FOLLOW THE SYMLINK, because the WRITER does.
  # `soleur_op_env_upsert` resolves with `readlink -f` before writing, so a
  # probe of the link NAME asks git about a file the write never touches. A
  # founder keeping credentials in one place symlinks .env at a shared file;
  # `.env*` ignores the NAME, the probe passes, and the value lands on a target
  # git reports as untracked-and-not-ignored — the next `git add .` commits it.
  # Fixture: `.env*` is ignored, `config/` is NOT, and .env points into it.
  rm -f "$repo/knowledge-base/project/specs/feat-y/.env"
  mkdir -p "$repo/knowledge-base/project/specs/feat-y/config"
  ln -s config/local.env "$repo/knowledge-base/project/specs/feat-y/.env"
  out="$(gign_run "$repo" "$rel")"; rc=$?
  if [[ "$rc" -ne 64 ]] || ! grep -qF 'SOLEUR_BOOTSTRAP_ENV_NOT_IGNORED' <<<"$out"; then
    echo "gign: a .env symlinked at an UN-ignored target was not refused (rc=${rc}): ${out}"; v=1
  fi
  if [[ -s "$repo/knowledge-base/project/specs/feat-y/config/local.env" ]]; then
    echo "gign: the refused symlink run still wrote the credential to the un-ignored target"; v=1
  fi
  rm -f "$repo/knowledge-base/project/specs/feat-y/.env"
  return "$v"
}

if [[ -r "$gen_home/bootstrap.sh" ]]; then
  assert_green gign_check "baked template" "$gen_home/bootstrap.sh"
  # Mutation (P1-1): the check block deleted from the generated script.
  cp "$gen_home/bootstrap.sh" "$SB/mut/gign-nocheck.sh"
  perl -0777 -pi -e 's{for probe in "\$ENV_FILE_RESOLVED" "\$\{ENV_FILE_RESOLVED\}\.tmp\.XXXXXX"; do\n.*?\ndone\n}{}s' "$SB/mut/gign-nocheck.sh"
  if [[ "$(md5_of "$SB/mut/gign-nocheck.sh")" == "$(md5_of "$gen_home/bootstrap.sh")" ]]; then
    fail "mutation 'gign check block deleted' did NOT land"
  else
    pass "mutation 'gign check block deleted' landed (md5 differs from the baked template)"
    assert_red gign_check "gign: template without the check writes an un-ignored .env" "$SB/mut/gign-nocheck.sh"
  fi
  # Mutation: the probe stops following the symlink (the pre-fix shape) while
  # the writer still resolves. Case (d) is the only row that can see it.
  cp "$gen_home/bootstrap.sh" "$SB/mut/gign-unresolved.sh"
  perl -0777 -pi -e 's{^ENV_FILE_RESOLVED="\$\(readlink -f -- "\$ENV_FILE".*?\)"$}{ENV_FILE_RESOLVED="$ENV_FILE"}m' "$SB/mut/gign-unresolved.sh"
  if [[ "$(md5_of "$SB/mut/gign-unresolved.sh")" == "$(md5_of "$gen_home/bootstrap.sh")" ]]; then
    fail "mutation 'gign probe stops resolving the symlink' did NOT land"
  else
    pass "mutation 'gign probe stops resolving the symlink' landed (md5 differs from the baked template)"
    assert_red gign_check "gign: unresolved probe passes a symlinked .env onto an un-ignored target" "$SB/mut/gign-unresolved.sh"
  fi
else
  fail "Guard 7: the baked template copy from F1 is missing"
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

# =============================================================================
# Guard 10 — an unattended run of a live consumer cannot reach a billable create
# =============================================================================
#
# Guard 9 is a TEXT census: it asks whether a `soleur_op_ack_or_die` LINE sits
# above each destructive site. Its anchor tolerates leading whitespace (a stage
# may legitimately live inside a function), and that is exactly what admits the
# bypass it exists to forbid — wrap the ack in `if [[ -z "${SOME_VAR:-}" ]]`,
# set SOME_VAR, and the call is still there, still matches, and never runs.
# Measured: both Guard 9 and the Guard 4 consumer sweep stay GREEN over that
# mutation while `hcloud server create` bills a real server unattended.
#
# No spelling rule closes it, because the dodge is control flow rather than
# text. This guard asserts the PROPERTY instead: drive the real consumer with
# stdin closed and EVERY escape variable the script itself mentions set, and
# require that the billable command was never invoked. A future bypass keyed on
# a NEW variable is covered too — the variable set is derived from the script
# under test, so the mutant hands the guard its own escape hatch.
HETZ_FIXTURE_KB="${PLUGIN_ROOT}/skills/provision-hetzner/test/fixture/knowledge-base"

gunatt_check() {
  local script="$1" v=0 run stub_log vars var
  # The run directory must NOT be the script's own directory — an earlier
  # revision derived it from `dirname "$script"` and `rm -rf`'d the script it
  # was about to drive, so every arm (including the positive control) reported
  # GREEN over a run that never happened. The own-dispatch row below is what
  # caught it; keep the two trees disjoint.
  run="$SB/unattrun/$(basename "$(dirname "$script")")"
  rm -rf "$run"; mkdir -p "$run/bin"
  cp -r "$HETZ_FIXTURE_KB" "$run/" || { echo "gunatt: fixture register copy failed"; return 1; }
  stub_log="$run/hcloud.argv"
  : > "$stub_log"
  # Logging stub, NOT a refusal: a stub that exits non-zero would mask the
  # create behind an error path. It records and succeeds, so reaching it is
  # observable and the run continues exactly as a real create would.
  { printf '#!/usr/bin/env bash\n'
    printf 'printf "%%s\\n" "$*" >> "%s"\n' "$stub_log"
    printf 'exit 0\n'
  } > "$run/bin/hcloud"
  chmod +x "$run/bin/hcloud"

  # DISCOVERED population: every escape variable the script names. `_LEDGER` is
  # a path, not an escape, and is pointed at the sandbox instead.
  vars="$(grep -oE 'SOLEUR_BOOTSTRAP_[A-Z0-9_]+' "$script" | sort -u | grep -v '_LEDGER$' || true)"
  (
    cd "$run" || exit 2
    export PATH="$run/bin:$PATH"
    export SOLEUR_BOOTSTRAP_LEDGER="$run/ledger.jsonl"
    # The script is driven from a COPY, so its relative library path does not
    # resolve; without this it exits 64 at SOLEUR_BOOTSTRAP_LIB_MISSING and
    # every arm reports "no create" over a run that reached nothing. The
    # reached-the-stage assertion below is the standing guard against that.
    export SOLEUR_OP_LIB="$LIB"
    for var in $vars; do export "$var=1"; done
    timeout 60 bash "$script" fixture-tenant </dev/null >"$run/out" 2>&1
  )
  if grep -qE '(^| )server create( |$)' "$stub_log"; then
    echo "gunatt: $(basename "$script") reached a BILLABLE create with no human in the loop: $(cat "$stub_log")"
    v=1
  fi
  # ANTI-VACUITY: "no create happened" is satisfied perfectly by a run that
  # died at the library load, at the DPA gate, or on a usage error. Require
  # positive evidence that the run actually got as far as the billable stage,
  # so a green here means the ack stopped it rather than something upstream.
  # The bare-create probe has no stages and is exempt by construction — it is
  # judged solely on the create it performs.
  if grep -qE 'soleur_op_stage_begin|soleur_op_ack_or_die' "$script" \
     && ! grep -qF 'write-class smoke test (billable)' "$run/out" 2>/dev/null; then
    echo "gunatt: $(basename "$script") never reached the billable stage — the run proves nothing: $(tail -3 "$run/out" 2>/dev/null)"
    v=1
  fi
  return "$v"
}

echo "== Guard 10 — no unattended billable create (behavioural) =="

if [[ -r "$HETZNER_SRC" && -d "$HETZ_FIXTURE_KB" ]]; then
  mkdir -p "$SB/unatt/live"; cp "$HETZNER_SRC" "$SB/unatt/live/provision-hetzner.sh"
  assert_green gunatt_check "live consumer, fully unattended" "$SB/unatt/live/provision-hetzner.sh"

  # OWN-DISPATCH: the stub and the log must be able to SEE a create, or the
  # green above is a measurement of nothing.
  mkdir -p "$SB/unatt/probe"
  printf '#!/usr/bin/env bash\nhcloud server create --name probe\n' > "$SB/unatt/probe/provision-hetzner.sh"
  assert_red gunatt_check "gunatt own-dispatch: a bare create is observed" "$SB/unatt/probe/provision-hetzner.sh"

  # MUTATION: the ack survives as a LINE but under a condition the run clears.
  # This is the mutation Guard 9 and the Guard 4 consumer sweep both miss.
  mkdir -p "$SB/unatt/condack"
  cp "$HETZNER_SRC" "$SB/unatt/condack/provision-hetzner.sh"
  perl -0777 -pi -e 's{^(soleur_op_ack_or_die "Create the billable probe server[^\n]*)\n}{if [[ -z "\$\{SOLEUR_BOOTSTRAP_ASSUME_YES:-\}" ]]; then\n  $1\nfi\n}m' "$SB/unatt/condack/provision-hetzner.sh"
  if [[ "$(md5_of "$SB/unatt/condack/provision-hetzner.sh")" == "$(md5_of "$HETZNER_SRC")" ]]; then
    fail "mutation 'consumer ack wrapped in a condition' did NOT land"
  else
    pass "mutation 'consumer ack wrapped in a condition' landed (md5 differs from the live script)"
    assert_red gunatt_check "gunatt: a conditionally-skipped ack reaches the billable create" "$SB/unatt/condack/provision-hetzner.sh"
  fi
else
  fail "Guard 10: the live consumer or its fixture register is missing"
fi

# --- Anti-vacuity floor ------------------------------------------------------
# REPORTS DIRECTLY (printf + exit 1), never by incrementing FAIL_COUNT (ADR-193).
# The floor exists to backstop the assertion machinery, so routing it THROUGH
# that machinery makes it disarmable by the same one-line edit it is supposed to
# catch: neuter pass()/fail() and the counters stay 0, the floor's own increment
# is the only thing left, and a verdict read from those counters is exactly what
# an attacker of the guard would neuter next. scripts/guard-vacuity-floor.test.sh
# measures this shape across the repo and reddens on the fail()-routed form.
ASSERT_TOTAL=$((PASS_COUNT + FAIL_COUNT))
FLOOR=136
if [[ "$ASSERT_TOTAL" -lt "$FLOOR" ]]; then
  printf '  [FAIL] anti-vacuity floor: only %s assertions ran, floor is %s\n' "$ASSERT_TOTAL" "$FLOOR" >&2
  printf 'Total: %s assertions, %s failed\n' "$ASSERT_TOTAL" "$((FAIL_COUNT + 1))"
  exit 1
fi
# Conservation: the two counters must account for every assertion the run made.
if [[ "$ASSERT_TOTAL" -ne $((PASS_COUNT + FAIL_COUNT)) ]]; then
  printf '  [FAIL] accounting: pass=%s fail=%s do not reconcile to %s\n' "$PASS_COUNT" "$FAIL_COUNT" "$ASSERT_TOTAL" >&2
  exit 1
fi

echo "Total: $((PASS_COUNT + FAIL_COUNT)) assertions, ${FAIL_COUNT} failed"
[[ "$FAIL_COUNT" -eq 0 ]]
