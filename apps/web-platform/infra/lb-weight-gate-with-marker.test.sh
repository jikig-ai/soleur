#!/usr/bin/env bash
# Tests for lb-weight-gate-with-marker.sh (#9358) — the ONE seam through which
# WORKSPACES_LUKS_CUTOVER_AT reaches lb-weight-gate.sh. See the wrapper's header for the contract.
#
# ASSEMBLY (Guard 5). Every scenario runs the wrapper in a SANDBOX: a copy of the wrapper (its pinned
# PATH prefixed with the sandbox bin so the stub `doppler` is found — the pin itself is asserted
# separately), a copy of the REAL gate (or a spy that records its environment), and a stub `doppler`
# that replays the real CLI contract: output shape (`secrets --only-names` prints a NAME header and
# one name per line, or a boxed table; `secrets get NAME --plain` prints the value), exit codes
# (1 = a Doppler Error, 64 = a request this stub was not taught), last-value-wins flags over ambient
# DOPPLER_PROJECT/DOPPLER_CONFIG, and a decoy answer for any config other than
# prd_workspaces_luks_marker. The stub records every argv and the environment it saw.
#
# CONTRACT ASSUMPTION, recorded because it cannot be measured offline: the stub's `--only-names`
# output shape is the documented plain listing. The wrapper tolerates the boxed-table spelling too.
# The first live read (the orchestrator's, tracked on #9358) is the real measurement.
#
# MUTATION MATRIX (each row edits a COPY of the wrapper and must turn its scenario RED; a row whose
# edit lands nothing is itself a failure; each mutant must still pass the CONTROL scenario, so a dead
# script cannot score as a catch):
#   1 the caller-supplied marker is no longer unset      2 --config prd / --config dropped
#   3 a second script invokes the gate directly (census) 4 a transport error is treated as absent
#   5a a prefix-colliding name satisfies the membership test  5b the exec is dropped (rc not propagated)
#   5c the env -i allowlist is dropped (DOPPLER_*, DOPPLER-API-HOST, BASH_FUNC_* reach the gate)
#   5d an allowlisted gate input is dropped              5e set-but-empty collapsed to unset
#   5f the allowlist grows past what the gate reads      6  PATH not pinned
#   7 a get failure after a positive membership test is read as absent   8 the shape check is dropped
#   9 the token requirement is dropped
#   10 DOPPLER_CONFIG_DIR no longer points the Doppler calls at an empty private dir
#   11 exported functions are no longer purged           12 the private dir leaks past the exec
#   13a/13b the exact-path check (DOPPLER_BIN == ${RUNNER_TEMP}/doppler-cli/doppler) is dropped (wrong path / RUNNER_TEMP
#       mismatch accepted)                                13c the `..`-free RUNNER_TEMP check is dropped
#   14a the not-a-symlink check on the binary is dropped  14b the owned-by-euid check is dropped (skipped as a case unless root)
#   14c the executable check is dropped                   14d the not-a-symlink check on the directory is dropped
#   14e the dir-not-group/world-writable check is dropped 14f the regular-file check is dropped
#   15 an invalid DOPPLER_BIN falls back silently to the pinned PATH (fail-closed contract broken)
#   13c/13e RUNNER_TEMP shape + realpath dropped ('..' / relative accepted)   13d exact-path loosened to a prefix match
#   14g..14p binary mode check dropped / dir+binary masks narrowed (020, 002) / over-strict dir mode / the -O operands
#       (binary, directory) changed to the temp root (structural pins, since a foreign owner needs root)
#   14i the realpath check dropped (symlinked RUNNER_TEMP or intermediate component accepted)
#   17 the function purge runs after a plain `unset DOPPLER_BIN` (a shadowing unset runs)
#   16 doppler_ro ignores the validated absolute path (calls bare `doppler` again)
#   5g DOPPLER_BIN is allowlisted AND no longer unset (it would reach the gate)
#   H1 HARNESS: a stub that records nothing must fail the argv assertion
#   H2 MUST-PASS: a valid marker 4 days old yields the gate's authorized-shape exit 0
#
# DOPPLER_BIN (#12167, CTO ruling 2026-11-07, option A). On the GitHub runner the pinned Doppler CLI lives in
# ${RUNNER_TEMP}/doppler-cli (added via $GITHUB_PATH only), which is NOT in the wrapper's pinned PATH, so the wrapper
# died with names_rc_127 and the gate never ran. The workflow now passes DOPPLER_BIN; the wrapper accepts it ONLY
# when it is exactly ${RUNNER_TEMP}/doppler-cli/doppler and passes the file/dir checks, else exit 3
# `bad_doppler_bin`, never a fallback to PATH. Each negative scenario keeps a working stub on the pinned PATH, so a
# silent fallback would RUN the gate and turn the scenario RED.
set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
WRAPPER="$SCRIPT_DIR/lb-weight-gate-with-marker.sh"
GATE="$SCRIPT_DIR/lb-weight-gate.sh"
ROWS_LIB="$REPO_ROOT/scripts/lib/web2-luks-rows.sh"

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
TMP="$(mktemp -d)" || exit 2
TMP="$(cd "$TMP" && pwd -P)" || exit 2 # physical path: the wrapper rejects a symlinked RUNNER_TEMP, so fixtures must not sit under a symlink
assert_fixture_dir "$TMP"
trap 'rm -rf "$TMP"' EXIT

passes=0
fails=0
# INDEPENDENT CASE COUNTER (ADR-193 #2): incremented at the call site of assert/mutate, never in ok/no.
cases=0
# APPEND-ONLY TRANSCRIPT of every verdict ("ok|name" / "FAIL|name"); the instrument self-test below
# requires assert/refute to move BOTH their counter and this ledger.
LEDGER=()
ok() { passes=$((passes + 1)); LEDGER+=("ok|$1"); printf '  ok   %s\n' "$1"; }
# skip <name> [why] — a case that could NOT run here. NOT a pass: it moves neither passes nor cases, so the
# anti-vacuity floor cannot be met by skipping. It lands in the ledger as "skip|..." and in the final tally.
skips=0
skip() { skips=$((skips + 1)); LEDGER+=("skip|$1"); printf '  SKIP %s\n' "$1"; [ -n "${2:-}" ] && printf '       %s\n' "$2"; return 0; }
no() { fails=$((fails + 1)); LEDGER+=("FAIL|$1"); printf '  FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '       %s\n' "$2"; return 0; }

# assert <name> <command...> — passes when the command exits 0.
assert() { local name="$1"; shift; cases=$((cases + 1)); if "$@"; then ok "$name"; else no "$name"; fi; }
# refute <name> <command...> — passes when the command exits non-zero.
refute() { local name="$1"; shift; cases=$((cases + 1)); if "$@"; then no "$name"; else ok "$name"; fi; }

# ── INSTRUMENT SELF-TEST (assert / refute) ───────────────────────────────────────────
# Every verdict here is owned by assert()/refute() (and mutate(), which calls ok/no directly). A helper
# that always records a pass would leave every case green and the case counter + conservation floor
# below cannot see it (a neutered helper still counts its case and records one verdict). So drive each
# helper ONCE with an input that MUST fail and ONCE with one that MUST pass, and require the failure/pass
# counter AND the append-only ledger to move. Reported with printf + exit (never through the helper under
# test); counters and ledger are then unwound so the self-test is not a case.
_st_instrument() { # <helper> <must-fail-cmd> <must-pass-cmd>
  local h="$1" p0 f0 c0 l0
  p0=$passes; f0=$fails; c0=$cases; l0=${#LEDGER[@]}
  eval "$2" >/dev/null 2>&1
  if [ "$fails" -ne $((f0 + 1)) ] || [ "$passes" -ne "$p0" ] || [ "${#LEDGER[@]}" -ne $((l0 + 1)) ] || [ "${LEDGER[$l0]%%|*}" != "FAIL" ]; then
    printf '[FATAL] instrument self-test: %s() did not record a FAIL (fail counter + ledger) for an input that must fail\n' "$h" >&2; exit 2
  fi
  eval "$3" >/dev/null 2>&1
  if [ "$passes" -ne $((p0 + 1)) ] || [ "$fails" -ne $((f0 + 1)) ] || [ "${#LEDGER[@]}" -ne $((l0 + 2)) ] || [ "${LEDGER[$((l0 + 1))]%%|*}" != "ok" ] || [ "$cases" -ne $((c0 + 2)) ]; then
    printf '[FATAL] instrument self-test: %s() did not record an ok (pass counter + ledger) for an input that must pass\n' "$h" >&2; exit 2
  fi
  passes=$p0; fails=$f0; cases=$c0; LEDGER=("${LEDGER[@]:0:$l0}")
}
_st_instrument assert 'assert "self-test" false' 'assert "self-test" true'
_st_instrument refute 'refute "self-test" true' 'refute "self-test" false'

printf '\n=== lb-weight-gate-with-marker ===\n\n'

for f in "$WRAPPER" "$GATE" "$ROWS_LIB"; do
  [ -f "$f" ] || { echo "required file missing: $f" >&2; exit 2; }
done

# ── time anchors, computed from a real `now` (never date-faked) ─────────────────────
NOW=$(date -u +%s)
ISO() { date -u -d "@$1" +%Y-%m-%dT%H:%M:%SZ; }
OLD4D="$(ISO $((NOW - 4 * 86400)))"
FRESH1D="$(ISO $((NOW - 1 * 86400)))"
FUTURE="$(ISO $((NOW + 2 * 86400)))"

MARKER=WORKSPACES_LUKS_CUTOVER_AT
CFG=prd_workspaces_luks_marker
BASEPATH="$PATH"

# ── the stub doppler (FX path baked in at build time: the wrapper runs it under `env -i`) ──────
write_stub() { # <file> <fx> [norecord]
  cat > "$1" <<STUB
#!/usr/bin/env bash
FX="$2"
NORECORD="${3:-}"
[ -n "\$NORECORD" ] || printf '%s\n' "\$*" >> "\$FX/calls"
printf 'config=%s project=%s bash_env=%s extra=%s confdir=%s entries=%s\n' "\${DOPPLER_CONFIG:-}" "\${DOPPLER_PROJECT:-}" "\${BASH_ENV:-}" "\${SOLEUR_WEB2_SERVING_WEIGHT:-}" "\${DOPPLER_CONFIG_DIR:-}" "\$( if [ -d "\${DOPPLER_CONFIG_DIR:-/nonexistent}" ]; then ls -A "\$DOPPLER_CONFIG_DIR" | wc -l; else echo nodir; fi )" >> "\$FX/envseen"
if [ -z "\${DOPPLER_TOKEN:-}" ]; then echo "Doppler Error: You must provide a token" >&2; exit 1; fi
printf '%s\n' "\$DOPPLER_TOKEN" >> "\$FX/tokens"
project="\${DOPPLER_PROJECT:-}"; config="\${DOPPLER_CONFIG:-}"
only_names=0; getmode=0; name=""
args=("\$@"); i=0
[ "\${args[0]:-}" = secrets ] || { echo "stub: REFUSED \$*" >&2; exit 64; }
i=1
while [ "\$i" -lt "\${#args[@]}" ]; do
  a="\${args[\$i]}"
  case "\$a" in
    --only-names) only_names=1 ;;
    --plain) : ;;
    --project) i=\$((i + 1)); project="\${args[\$i]}" ;;
    --config) i=\$((i + 1)); config="\${args[\$i]}" ;;
    get) getmode=1; i=\$((i + 1)); name="\${args[\$i]}" ;;
    *) echo "stub: REFUSED flag \$a" >&2; exit 64 ;;
  esac
  i=\$((i + 1))
done
if [ "\$project" != soleur ]; then echo "stub: REFUSED project '\$project'" >&2; exit 64; fi
if [ "\$config" = prd ]; then
  # A decoy: the shared prd config shows a DIFFERENT, planted value. Reading it is the defect.
  if [ "\$only_names" -eq 1 ]; then printf 'NAME\n$MARKER\n'; exit 0; fi
  if [ "\$getmode" -eq 1 ]; then cat "\$FX/decoy"; printf '\n'; exit 0; fi
fi
if [ "\$config" != $CFG ]; then echo "stub: REFUSED config '\$config'" >&2; exit 64; fi
if [ "\$only_names" -eq 1 ]; then
  rc="\$(cat "\$FX/names_rc" 2>/dev/null || echo 0)"
  if [ "\$rc" != 0 ]; then echo "Doppler Error: request failed (names)" >&2; exit "\$rc"; fi
  if [ -f "\$FX/names_table" ]; then
    printf '┌──────┐\n│ NAME │\n├──────┤\n'; while IFS= read -r n; do printf '│ %s │\n' "\$n"; done < "\$FX/names"; printf '└──────┘\n'
  else printf 'NAME\n'; cat "\$FX/names"; fi
  exit 0
fi
if [ "\$getmode" -eq 1 ]; then
  rc="\$(cat "\$FX/get_rc" 2>/dev/null || echo 0)"
  if [ "\$rc" != 0 ]; then echo "Doppler Error: request failed (get)" >&2; exit "\$rc"; fi
  if ! grep -qxF -- "\$name" "\$FX/names"; then echo "Doppler Error: Could not find requested secret: \$name" >&2; exit 1; fi
  cat "\$FX/value"; printf '\n'; exit 0
fi
echo "stub: REFUSED \$*" >&2; exit 64
STUB
  chmod +x "$1"
}

# build_sb <wrapper-file> <real|spy> [norecord] — sets SB (sandbox dir) and FX.
build_sb() {
  local wrapper="$1" kind="$2" norecord="${3:-}"
  SB="$(mktemp -d "$TMP/sb.XXXXXX")"; FX="$SB/fx"
  mkdir -p "$SB/bin" "$FX"
  sed "s|^PINNED_PATH=\"|PINNED_PATH=\"$SB/bin:|" "$wrapper" > "$SB/lb-weight-gate-with-marker.sh"
  if [ "$kind" = real ]; then cp "$GATE" "$SB/lb-weight-gate.sh"
  else
    printf '#!/usr/bin/env bash\nenv > "%s/gate.env"\nexit "$(cat "%s/gate_rc" 2>/dev/null || echo 42)"\n' "$FX" "$FX" > "$SB/lb-weight-gate.sh"
  fi
  write_stub "$SB/bin/doppler" "$FX" "$norecord"
  : > "$FX/calls"; : > "$FX/names"; printf '%s' "$FRESH1D" > "$FX/decoy"
}
# set_marker <value|ABSENT> — the sandbox's Doppler state for the marker config.
set_marker() {
  if [ "$1" = ABSENT ]; then : > "$FX/names"; else printf '%s\n' "$MARKER" > "$FX/names"; printf '%s' "$1" > "$FX/value"; fi
}

RC=0; OUT=""; ERR=""
# run_wb [VAR=value ...] — run the sandboxed wrapper under a CLEAN environment holding only the
# default pooled-gate env, the token, and the extras (extras may override or add; `-VAR` removes).
run_wb() {
  local -a e=(
    PATH="$BASEPATH" HOME="$TMP/home"
    DOPPLER_TOKEN="dp.st.fixture0token"
    SOLEUR_WEB2_SERVING_WEIGHT=1 SOLEUR_GATED_HOST=web-2 SOLEUR_SERVING_ROTATION="web-1,web-2"
    SOLEUR_PROXY_PEER_ALLOWLIST=10.0.1.11
    SOLEUR_HOST_ROSTER='{"web-1":"10.0.1.10","web-2":"10.0.1.11"}'
    GIT_DATA_STORE_ENABLED=true GIT_DATA_LUKS_CUTOVER_AT="$OLD4D"
  )
  local x
  for x in "$@"; do
    case "$x" in
      -*) local drop="${x#-}"; local -a n=(); local y; for y in "${e[@]}"; do [ "${y%%=*}" = "$drop" ] || n+=("$y"); done; e=("${n[@]}") ;;
      *) e+=("$x") ;;
    esac
  done
  mkdir -p "$TMP/home"
  local errf="$TMP/err.$$.$RANDOM"
  OUT="$(env -i "${e[@]}" bash "$SB/lb-weight-gate-with-marker.sh" 2>"$errf")"; RC=$?
  ERR="$(cat "$errf")"; rm -f "$errf"
}

# ── the two argv lines the wrapper must issue (and nothing else) ───────────────────────────────
ARGV_NAMES="secrets --only-names --project soleur --config $CFG"
ARGV_GET="secrets get $MARKER --plain --project soleur --config $CFG"
argv_is() { # <expected newline-joined list> against $FX/calls
  [ "$(cat "$FX/calls")" = "$1" ]
}

# ═══ scenarios: each returns 0 when the CORRECT behaviour holds for the wrapper file given ════════
scn_happy() { # H2 + control: a valid marker 4 days old yields the gate's authorized-shape exit 0
  build_sb "$1" real; set_marker "$OLD4D"; run_wb
  [ "$RC" -eq 0 ] && [[ "$OUT" == *"requires_runtime_bind_probe=true"* ]]
}
scn_argv() { # the exact argv, exactly twice, from the exact config; never run/download
  build_sb "$1" real; set_marker "$OLD4D"; run_wb
  argv_is "$(printf '%s\n%s' "$ARGV_NAMES" "$ARGV_GET")" \
    && ! grep -qE 'doppler run|secrets download| run ' "$FX/calls" && [ "$RC" -eq 0 ]
}
scn_unset_caller() { # a caller-supplied marker is discarded: Doppler says absent => the gate fails closed
  build_sb "$1" real; set_marker ABSENT; run_wb "WORKSPACES_LUKS_CUTOVER_AT=$OLD4D"
  [ "$RC" -eq 1 ] && [[ "$ERR" == *"sub_condition=B_workspaces_luks_marker_absent"* ]]
}
scn_caller_not_preferred() { # Doppler's fresh value governs even when the caller offers an old, valid one
  build_sb "$1" real; set_marker "$FRESH1D"; run_wb "WORKSPACES_LUKS_CUTOVER_AT=$OLD4D"
  [ "$RC" -eq 1 ] && [[ "$ERR" == *"sub_condition=B_workspaces_luks_soak_not_elapsed"* ]]
}
scn_names_fail() { # a transport error: rc 3 and the gate NEVER runs
  build_sb "$1" spy; set_marker "$OLD4D"; echo 1 > "$FX/names_rc"; run_wb
  [ "$RC" -eq 3 ] && [ ! -e "$FX/gate.env" ] && [[ "$ERR" == *"class=names_rc_1"* ]] && [[ "$ERR" != *"request failed"* ]]
}
scn_prefix() { # a prefix-colliding name is NOT the marker: absent, and `get` is never issued
  build_sb "$1" real; printf '%s_OLD\n' "$MARKER" > "$FX/names"; printf '%s' "$OLD4D" > "$FX/value"; run_wb
  [ "$RC" -eq 1 ] && [[ "$ERR" == *"sub_condition=B_workspaces_luks_marker_absent"* ]] && ! grep -q 'secrets get' "$FX/calls"
}
scn_exec_rc() { # the gate's own rc propagates, success included (a spy exits 42, then 0)
  build_sb "$1" spy; set_marker "$OLD4D"; run_wb
  [ "$RC" -eq 42 ] || return 1
  echo 0 > "$FX/gate_rc"; run_wb
  [ "$RC" -eq 0 ]
}
scn_doppler_scrub() { # no DOPPLER_* and no BASH_ENV/ENV reaches the gate; the marker and the orchestrator's env do
  build_sb "$1" spy; set_marker "$OLD4D"
  run_wb DOPPLER_API_HOST=https://x.invalid DOPPLER_CONFIG=prd DOPPLER_PROJECT=other DOPPLER_FOO=1 BASH_ENV="$TMP/nonexistent.sh" ENV="$TMP/nonexistent.sh"
  [ "$RC" -eq 42 ] && [ -f "$FX/gate.env" ] \
    && ! grep -q '^DOPPLER_' "$FX/gate.env" && ! grep -q '^BASH_ENV=' "$FX/gate.env" && ! grep -q '^ENV=' "$FX/gate.env" \
    && grep -qx "$MARKER=$OLD4D" "$FX/gate.env" && grep -qx 'SOLEUR_WEB2_SERVING_WEIGHT=1' "$FX/gate.env"
}
scn_ambient_config() { # an ambient DOPPLER_CONFIG/PROJECT must not steer the read, nor reach the stub's env
  build_sb "$1" real; set_marker "$OLD4D"; run_wb DOPPLER_CONFIG=prd DOPPLER_PROJECT=other
  argv_is "$(printf '%s\n%s' "$ARGV_NAMES" "$ARGV_GET")" && [ "$RC" -eq 0 ] \
    && ! grep -qE 'config=prd|project=other|config=.*bash_env=[^ ]' "$FX/envseen"
}
scn_path_pinned() { # a doppler earlier on the CALLER's PATH is never run
  build_sb "$1" real; set_marker "$OLD4D"
  mkdir -p "$TMP/evil"; printf '#!/usr/bin/env bash\necho EVIL-RAN >> "%s/evil.ran"\nexit 0\n' "$TMP" > "$TMP/evil/doppler"; chmod +x "$TMP/evil/doppler"
  rm -f "$TMP/evil.ran"
  run_wb "PATH=$TMP/evil:$BASEPATH"
  [ ! -e "$TMP/evil.ran" ] && [ "$RC" -eq 0 ]
}
scn_get_fail() { # get fails AFTER a positive membership test: rc 3, the gate never runs (never "absent")
  build_sb "$1" spy; set_marker "$OLD4D"; echo 1 > "$FX/get_rc"; run_wb
  [ "$RC" -eq 3 ] && [ ! -e "$FX/gate.env" ] && [[ "$ERR" == *"class=get_rc_1"* ]]
}
scn_shape() { # a malformed or empty value is never exported: rc 4, the gate never runs
  build_sb "$1" spy; set_marker "not-a-date"; run_wb
  [ "$RC" -eq 4 ] && [ ! -e "$FX/gate.env" ]
}
scn_token() { # no token: rc 3 and Doppler is never called
  build_sb "$1" spy; set_marker "$OLD4D"; run_wb -DOPPLER_TOKEN
  [ "$RC" -eq 3 ] && [ ! -s "$FX/calls" ] && [[ "$ERR" == *"class=no_token"* ]]
}

# ── DOPPLER_BIN: the runner's pinned CLI lives outside the pinned PATH (#12167) ─────────────────
# mk_rt — a fake RUNNER_TEMP holding a valid doppler-cli/doppler stub (after build_sb: the stub bakes in $FX).
# Sets RT (the RUNNER_TEMP) and DB (the binary). The stub lives ONLY here when the caller removes $SB/bin/doppler.
mk_rt() {
  RT="$(mktemp -d "$TMP/rt.XXXXXX")"; assert_fixture_dir "$RT"
  mkdir -p "$RT/doppler-cli"; chmod 755 "$RT/doppler-cli"
  write_stub "$RT/doppler-cli/doppler" "$FX"
  DB="$RT/doppler-cli/doppler"
}
scn_dbin_pass() { # REPRO (fixed): the stub exists ONLY under RUNNER_TEMP/doppler-cli; DOPPLER_BIN makes the gate chain run
  build_sb "$1" real; set_marker "$OLD4D"; rm -f "$SB/bin/doppler"; mk_rt
  run_wb "RUNNER_TEMP=$RT" "DOPPLER_BIN=$DB"
  [ "$RC" -eq 0 ] && [[ "$OUT" == *"requires_runtime_bind_probe=true"* ]] \
    && argv_is "$(printf '%s\n%s' "$ARGV_NAMES" "$ARGV_GET")"
}
scn_dbin_unset_127() { # REPRO (defect): without DOPPLER_BIN the pinned PATH has no doppler => names_rc_127, the gate never ran
  build_sb "$1" spy; set_marker "$OLD4D"; rm -f "$SB/bin/doppler"; mk_rt
  run_wb "RUNNER_TEMP=$RT"
  [ "$RC" -eq 3 ] && [ ! -e "$FX/gate.env" ] && [[ "$ERR" == *"class=names_rc_127"* ]]
}
# dbin_rejected — the common verdict of every negative: exit 3, class=bad_doppler_bin, the gate never ran, and NO
# doppler (neither the supplied one nor the decoy on the pinned PATH) was executed.
dbin_rejected() {
  [ "$RC" -eq 3 ] && [ ! -e "$FX/gate.env" ] && [[ "$ERR" == *"class=bad_doppler_bin"* ]] && [ ! -s "$FX/calls" ]
}
dbin_neg_sb() { build_sb "$1" spy; set_marker "$OLD4D"; mk_rt; } # keeps a working stub on the pinned PATH (fallback detector)
scn_dbin_wrongpath() { # a valid-looking binary that is not RUNNER_TEMP/doppler-cli/doppler
  dbin_neg_sb "$1"; run_wb "RUNNER_TEMP=$RT" "DOPPLER_BIN=$SB/bin/doppler"; dbin_rejected
}
scn_dbin_rt_mismatch() { # DOPPLER_BIN is valid under ANOTHER temp root than the RUNNER_TEMP the wrapper is given
  dbin_neg_sb "$1"; local db1="$DB"; mk_rt
  run_wb "RUNNER_TEMP=$RT" "DOPPLER_BIN=$db1"; dbin_rejected
}
scn_dbin_dotdot() { # RUNNER_TEMP carrying `..` is refused even though DOPPLER_BIN equals RUNNER_TEMP/doppler-cli/doppler literally
  dbin_neg_sb "$1"; mkdir -p "$RT/x"
  run_wb "RUNNER_TEMP=$RT/x/.." "DOPPLER_BIN=$RT/x/../doppler-cli/doppler"; dbin_rejected
}
scn_dbin_symlink() { # the binary is a symlink (to a perfectly good stub)
  dbin_neg_sb "$1"; rm -f "$DB"; ln -s "$SB/bin/doppler" "$DB"
  run_wb "RUNNER_TEMP=$RT" "DOPPLER_BIN=$DB"; dbin_rejected
}
scn_dbin_notexec() { # the binary is a regular file that is not executable
  dbin_neg_sb "$1"; chmod 644 "$DB"
  run_wb "RUNNER_TEMP=$RT" "DOPPLER_BIN=$DB"; dbin_rejected
}
scn_dbin_notfile() { # the path is a directory (executable bit set), not a regular file
  dbin_neg_sb "$1"; rm -f "$DB"; mkdir "$DB"
  run_wb "RUNNER_TEMP=$RT" "DOPPLER_BIN=$DB"; dbin_rejected
}
dbin_owner_constructible() { [ "$(id -u)" -eq 0 ]; } # chown to another uid needs root; the CI runner is not
scn_dbin_foreign_owner() { # the binary is owned by another user
  dbin_neg_sb "$1"; chown 65534 "$DB"
  run_wb "RUNNER_TEMP=$RT" "DOPPLER_BIN=$DB"; dbin_rejected
}
scn_dbin_foreign_dir_owner() { # the doppler-cli DIRECTORY is owned by another user
  dbin_neg_sb "$1"; chown 65534 "$RT/doppler-cli"
  run_wb "RUNNER_TEMP=$RT" "DOPPLER_BIN=$DB"; dbin_rejected
}
scn_dbin_dir_writable() { # the binary's directory is world-writable, then group-writable
  # 777 and 775 (group bit set), 757 and 703 (world-writable ONLY: the group bit is clear), 772 (group-writable only)
  dbin_neg_sb "$1"; local m
  for m in 777 775 757 703 772; do
    chmod "$m" "$RT/doppler-cli"; : > "$FX/calls"
    run_wb "RUNNER_TEMP=$RT" "DOPPLER_BIN=$DB"; dbin_rejected || { printf '       dir mode %s was accepted\n' "$m"; return 1; }
  done
}
scn_dbin_bin_writable() { # the BINARY is group-writable / world-writable (alone and together)
  dbin_neg_sb "$1"; local m
  for m in 775 757 777 703 772; do
    chmod "$m" "$DB"; : > "$FX/calls"
    run_wb "RUNNER_TEMP=$RT" "DOPPLER_BIN=$DB"; dbin_rejected || { printf '       binary mode %s was accepted\n' "$m"; return 1; }
  done
}
scn_dbin_modes_pass() { # MUST-PASS: any dir/binary mode without a group/world write bit works (an over-strict validator is RED)
  build_sb "$1" real; set_marker "$OLD4D"; rm -f "$SB/bin/doppler"; mk_rt
  local pair dm bm
  for pair in "755 755" "750 755" "700 755" "755 700" "750 700" "700 700" "755 555"; do
    dm="${pair% *}"; bm="${pair#* }"
    chmod "$dm" "$RT/doppler-cli"; chmod "$bm" "$DB"
    [ "$bm" = 555 ] && chmod 555 "$DB"
    run_wb "RUNNER_TEMP=$RT" "DOPPLER_BIN=$DB"
    { [ "$RC" -eq 0 ] && [[ "$OUT" == *"requires_runtime_bind_probe=true"* ]]; } || { printf '       dir %s / binary %s was refused (rc %s)\n' "$dm" "$bm" "$RC"; chmod 755 "$RT/doppler-cli"; return 1; }
  done
  chmod 755 "$RT/doppler-cli"
}
scn_dbin_exact_variants() { # only EXACTLY .../doppler-cli/doppler is accepted: another name, a dir-hopping spelling, a ./ spelling
  dbin_neg_sb "$1"
  cp "$DB" "$RT/doppler-cli/other"; chmod 755 "$RT/doppler-cli/other"
  local v
  for v in "$RT/doppler-cli/other" "$RT/doppler-cli/../doppler-cli/doppler" "$RT/doppler-cli/doppler/../doppler" "$RT/doppler-cli/./doppler"; do
    : > "$FX/calls"; run_wb "RUNNER_TEMP=$RT" "DOPPLER_BIN=$v"
    dbin_rejected || { printf '       accepted %s\n' "$v"; return 1; }
  done
}
scn_dbin_rel_rt() { # a RELATIVE RUNNER_TEMP with a matching relative DOPPLER_BIN (everything else valid) is refused
  dbin_neg_sb "$1"
  local here="$PWD" rrt="${RT#"$TMP"/}" rdb="${DB#"$TMP"/}"
  cd "$TMP" || return 1
  run_wb "RUNNER_TEMP=$rrt" "DOPPLER_BIN=$rdb"
  cd "$here" || return 1
  dbin_rejected
}
scn_dbin_empty_rt() { # an EMPTY RUNNER_TEMP with DOPPLER_BIN=/doppler-cli/doppler reaches the RUNNER_TEMP check and is refused
  dbin_neg_sb "$1"; run_wb "RUNNER_TEMP=" "DOPPLER_BIN=/doppler-cli/doppler"; dbin_rejected
}
scn_dbin_symlinked_rt() { # RUNNER_TEMP itself a symlink, then a symlinked INTERMEDIATE component: both refused
  dbin_neg_sb "$1"
  local base; base="$(mktemp -d "$TMP/lnk.XXXXXX")"; assert_fixture_dir "$base"
  mv "$RT" "$base/real"; ln -s real "$base/lnk"
  run_wb "RUNNER_TEMP=$base/lnk" "DOPPLER_BIN=$base/lnk/doppler-cli/doppler"; dbin_rejected || { printf '       a symlinked RUNNER_TEMP was accepted\n'; return 1; }
  mkdir "$base/real/tmp"; mv "$base/real/doppler-cli" "$base/real/tmp/doppler-cli"; : > "$FX/calls"
  run_wb "RUNNER_TEMP=$base/lnk/tmp" "DOPPLER_BIN=$base/lnk/tmp/doppler-cli/doppler"; dbin_rejected || { printf '       a symlinked intermediate component was accepted\n'; return 1; }
}
scn_fn_unset() { # exported functions shadowing unset/export never run (DOPPLER_BIN is set, so the wrapper reaches its unset)
  build_sb "$1" real; set_marker "$OLD4D"; rm -f "$SB/bin/doppler"; mk_rt; rm -f "$TMP/fn2.canary"
  run_wb "RUNNER_TEMP=$RT" "DOPPLER_BIN=$DB" \
    "BASH_FUNC_unset%%=() { echo \"\$*\" >> $TMP/fn2.canary; builtin unset \"\$@\"; }" \
    "BASH_FUNC_export%%=() { echo \"\$*\" >> $TMP/fn2.canary; builtin export \"\$@\"; }"
  [ ! -e "$TMP/fn2.canary" ] && [ "$RC" -eq 0 ] && [[ "$OUT" == *"requires_runtime_bind_probe=true"* ]]
}
# structural pins on the SOURCE (comment-stripped): the ownership tests name the exact operand. An -O on the wrong
# operand (the temp root, say) is owned by the caller too, so no behavioural case can tell it apart without root.
wrapper_code() { grep -vE '^[[:space:]]*#' "$1"; }
scn_owner_pin_bin() {
  local c l; c="$(wrapper_code "$1")"
  l="$(grep -F -- '-O "$p"' <<<"$c" || true)"
  [ "$(grep -cF -- '-O "$p"' <<<"$c")" -eq 1 ] && grep -qF '[[ -f "$p" &&' <<<"$l"
}
scn_owner_pin_dir() {
  local c l; c="$(wrapper_code "$1")"
  l="$(grep -F -- '-O "$dir"' <<<"$c" || true)"
  [ "$(grep -cF -- '-O "$dir"' <<<"$c")" -eq 1 ] && grep -qF '[[ -d "$dir" &&' <<<"$l"
}
scn_dbin_dir_symlink() { # the doppler-cli directory is a symlink to a good directory
  dbin_neg_sb "$1"; mv "$RT/doppler-cli" "$RT/real-cli"; ln -s real-cli "$RT/doppler-cli"
  run_wb "RUNNER_TEMP=$RT" "DOPPLER_BIN=$DB"; dbin_rejected
}
scn_dbin_empty_or_no_rt() { # set-but-empty DOPPLER_BIN, and a DOPPLER_BIN with no RUNNER_TEMP, both fail closed
  dbin_neg_sb "$1"; run_wb "RUNNER_TEMP=$RT" "DOPPLER_BIN="; dbin_rejected || return 1
  : > "$FX/calls"; run_wb -RUNNER_TEMP "DOPPLER_BIN=$DB"; dbin_rejected
}

# ── the exec environment is an ALLOWLIST (security P3-1) ────────────────────────────────────────
# The variables lb-weight-gate.sh reads, DERIVED FROM THE GATE ITSELF (never typed here): every NAME the
# gate expands in a code line as ${NAME-, ${NAME:- or ${NAME+. Comment lines are skipped (a comment names a
# placeholder VAR).
gate_read_vars() { # the gate's INPUTS: every variable it expands in ANY form ($NAME, ${NAME}, ${NAME-, ${NAME:-, ${NAME+, ${NAME:?, ...)
  # that it does not itself assign (NAME=..., local/declare/typeset/readonly, for NAME in, read NAME). Reading the
  # gate's own derived variables is not an input; reading a name nobody assigns is, whatever the expansion form.
  local body reads assigned
  body="$(sed -E '/^[[:space:]]*#/d' "$GATE")"
  reads="$(grep -oE '\$\{?[A-Za-z_][A-Za-z0-9_]*' <<<"$body" | sed -E 's/^\$\{?//')"
  assigned="$({
    grep -oE '(^|[;[:space:](])[A-Za-z_][A-Za-z0-9_]*\+?=' <<<"$body" | sed -E 's/^[;[:space:](]//; s/\+?=$//'
    grep -E '^[[:space:]]*(local|declare|typeset|readonly)[[:space:]]' <<<"$body" | tr -s ' ;' '\n\n' | sed -E 's/=.*//'
    grep -oE '(^|[;[:space:]])for[[:space:]]+[A-Za-z_][A-Za-z0-9_]*[[:space:]]+in' <<<"$body" | awk '{print $(NF-1)}'
    grep -E '(^|[;[:space:]])read[[:space:]]' <<<"$body" | tr -s ' ' '\n' | sed -E 's/[^A-Za-z0-9_].*//'
  })"
  comm -23 <(sort -u <<<"$reads") <(sort -u <<<"$assigned")
}
wrapper_allow_vars() { # the NAMEs inside the wrapper's GATE_ENV_ALLOW=( ... ) array
  sed -n '/^GATE_ENV_ALLOW=(/,/^)/p' "$1" | sed '1d;$d' | tr -s ' \n' '\n\n' | sed '/^$/d' | sort -u
}
# names an `env` run by a bash gate prints besides what was passed in
BASH_ADDED='^(PWD|SHLVL|_|OLDPWD)$'
scn_allow_parity() { # the wrapper's allowlist equals the gate's own read set (a drift either way is RED)
  local d w; d="$(gate_read_vars)"; w="$(wrapper_allow_vars "$1")"
  [ -n "$d" ] && [ "$(wc -l <<<"$d")" -eq 11 ] && [ "$d" = "$w" ]  # +1 SOLEUR_GATED_HOST, +1 WORKSPACES_LUKS_MARKER_HOST (#9421)
}
scn_derive_sees_every_form() { # PLANTED reads in every expansion form are derived as inputs; the gate's own variables are not
  local real="$GATE" planted="$TMP/gate.planted.sh" got
  { cat "$real"; printf '%s\n' 'x_plain=$PLANT_PLAIN' 'x_brace="${PLANT_BRACE}"' 'x_req="${PLANT_REQ:?missing}"' 'x_dflt="${PLANT_DFLT:-d}"' 'PLANT_OWN=1' 'x_own="$PLANT_OWN"' '# $PLANT_COMMENT'; } > "$planted"
  GATE="$planted"; got="$(gate_read_vars)"; GATE="$real"
  grep -qxF PLANT_PLAIN <<<"$got" && grep -qxF PLANT_BRACE <<<"$got" && grep -qxF PLANT_REQ <<<"$got" && grep -qxF PLANT_DFLT <<<"$got" \
    && ! grep -qxF PLANT_OWN <<<"$got" && ! grep -qxF PLANT_COMMENT <<<"$got" && [ "$(wc -l <<<"$got")" -eq 15 ]
}
scn_survivors() { # nothing but PATH + allowlisted gate inputs reaches the gate, INCLUDING non-identifier names and functions
  # DOPPLER_BIN (and RUNNER_TEMP) are SET and VALID here, with the only working doppler under RUNNER_TEMP: the chain
  # runs through DOPPLER_BIN, and neither name may reach the gate.
  build_sb "$1" spy; set_marker "$OLD4D"; rm -f "$SB/bin/doppler"; mk_rt
  run_wb "RUNNER_TEMP=$RT" "DOPPLER_BIN=$DB" 'DOPPLER-API-HOST=https://evil.invalid' 'BASH_FUNC_date%%=() { echo pwn; }' 'BASH_FUNC_jq%%=() { echo pwn; }' \
    DOPPLER_API_HOST=https://x.invalid doppler_token=lower FOO_UNRELATED=1 TMPDIR=/var/tmp/x LC_ALL=C.UTF-8 TZ=Asia/Tokyo
  [ "$RC" -eq 42 ] && [ -f "$FX/gate.env" ] || return 1
  ! grep -q '^DOPPLER' "$FX/gate.env" && ! grep -qi '^doppler' "$FX/gate.env" && ! grep -q 'BASH_FUNC' "$FX/gate.env" \
    && ! grep -qE '^(DOPPLER_BIN|RUNNER_TEMP)=' "$FX/gate.env" && ! grep -qF -- "$DB" "$FX/gate.env" \
    && ! grep -qE '^(FOO_UNRELATED|HOME|TMPDIR|LC_ALL|TZ)=' "$FX/gate.env" || return 1
  local allowed names n; allowed="$(gate_read_vars)"; names="$(sed -nE 's/^([^=]+)=.*/\1/p' "$FX/gate.env")"
  for n in $names; do
    [[ "$n" == PATH ]] && continue; [[ "$n" =~ $BASH_ADDED ]] && continue
    grep -qxF -- "$n" <<<"$allowed" || { printf '       gate env holds %s, which the gate does not read\n' "$n"; return 1; }
  done
  grep -qx "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" "$FX/gate.env" || grep -qE '^PATH=.*:/usr/bin' "$FX/gate.env"
}
scn_allow_passthrough() { # every allowlisted input the caller SET reaches the gate verbatim; set-but-empty stays set; unset stays unset
  build_sb "$1" spy; set_marker "$OLD4D"
  local v i=0 -a args 2>/dev/null; local -a ex=()
  for v in $(gate_read_vars); do
    case "$v" in "$MARKER"|WORKSPACES_LUKS_MARKER_HOST) continue ;; esac  # both are seam-owned, never caller-passed
    i=$((i + 1)); ex+=("$v=sentinel-$i")
  done
  run_wb "${ex[@]}" GIT_DATA_LUKS_SOAK_DAYS=
  [ "$RC" -eq 42 ] || return 1
  local x; for x in "${ex[@]}"; do
    [[ "$x" == GIT_DATA_LUKS_SOAK_DAYS=* ]] && continue
    grep -qxF -- "$x" "$FX/gate.env" || { printf '       %s did not reach the gate\n' "${x%%=*}"; return 1; }
  done
  grep -qx 'GIT_DATA_LUKS_SOAK_DAYS=' "$FX/gate.env" || { printf '       a SET-BUT-EMPTY input was collapsed to unset\n'; return 1; }
  # unset stays unset: the gate treats an UNSET SOLEUR_SERVING_ROTATION as fail-closed, distinct from empty
  build_sb "$1" spy; set_marker "$OLD4D"; run_wb -SOLEUR_SERVING_ROTATION
  [ "$RC" -eq 42 ] && ! grep -q '^SOLEUR_SERVING_ROTATION' "$FX/gate.env"
}
scn_marker_host_seam_owned() { # the marker's host comes from the seam alone: a caller value is discarded, present -> web-2, absent -> unset
  build_sb "$1" spy; set_marker "$OLD4D"; run_wb WORKSPACES_LUKS_MARKER_HOST=web-3
  [ "$RC" -eq 42 ] && grep -qx 'WORKSPACES_LUKS_MARKER_HOST=web-2' "$FX/gate.env" || return 1
  build_sb "$1" spy; set_marker ABSENT; run_wb WORKSPACES_LUKS_MARKER_HOST=web-2
  [ "$RC" -eq 42 ] && ! grep -q '^WORKSPACES_LUKS_MARKER_HOST' "$FX/gate.env"
}
scn_proxy_bind_not_forwarded() { # SOLEUR_PROXY_BIND (no longer a gate input, CTO ruling #12167) never reaches the gate, and does not steer the real one
  build_sb "$1" spy; set_marker "$OLD4D"; run_wb SOLEUR_PROXY_BIND=10.0.1.10
  [ "$RC" -eq 42 ] && [ -f "$FX/gate.env" ] || return 1
  ! grep -q '^SOLEUR_PROXY_BIND' "$FX/gate.env" || return 1
  # GATE-ONLY check (it does not exercise the wrapper's forwarding; the spy half above does that): the REAL gate,
  # fed an empty SOLEUR_PROXY_BIND, still reaches the pooled authorized-shape exit 0
  build_sb "$1" real; set_marker "$OLD4D"; run_wb SOLEUR_PROXY_BIND=
  [ "$RC" -eq 0 ] && [[ "$OUT" == *"requires_runtime_bind_probe=true"* ]]
}
scn_rotation_unset_fails_closed() { # end-to-end through the REAL gate: unset stays unset, so the gate refuses
  build_sb "$1" real; set_marker "$OLD4D"; run_wb -SOLEUR_SERVING_ROTATION
  [ "$RC" -eq 1 ] && [[ "$ERR" == *"sub_condition=TOP_serving_rotation_absent"* ]]
}
scn_rotation_empty_standby() { # a SET-BUT-EMPTY rotation ("no rotation") reaches the real gate as empty: standby passes
  build_sb "$1" real; set_marker ABSENT; run_wb SOLEUR_WEB2_SERVING_WEIGHT=0 SOLEUR_SERVING_ROTATION=
  [ "$RC" -eq 0 ] && [[ "$OUT" == *"web2_standby=true"* ]]
}
scn_function_purge() { # an exported function shadowing env/mktemp/rm in the CALLER's environment never runs inside the wrapper
  build_sb "$1" real; set_marker "$OLD4D"; rm -f "$TMP/fn.canary"
  run_wb "BASH_FUNC_mktemp%%=() { touch $TMP/fn.canary; command mktemp \"\$@\"; }" \
         "BASH_FUNC_env%%=() { touch $TMP/fn.canary; command env \"\$@\"; }" \
         "BASH_FUNC_rm%%=() { touch $TMP/fn.canary; command rm \"\$@\"; }"
  [ ! -e "$TMP/fn.canary" ] && [ "$RC" -eq 0 ] && [[ "$OUT" == *"requires_runtime_bind_probe=true"* ]]
}
conf_dirs() { sed -nE 's/.* confdir=([^ ]*) entries=.*/\1/p' "$FX/envseen" | sort -u; }
scn_confdir() { # the Doppler calls get an EMPTY PRIVATE DOPPLER_CONFIG_DIR, not the caller's and not under HOME; it is removed afterwards
  build_sb "$1" real; set_marker "$OLD4D"
  mkdir -p "$TMP/home/.doppler"; printf 'api-host: https://evil.invalid\n' > "$TMP/home/.doppler/.doppler.yaml"
  run_wb "DOPPLER_CONFIG_DIR=$TMP/home/.doppler"
  [ "$RC" -eq 0 ] || return 1
  [ "$(wc -l < "$FX/envseen")" -eq 2 ] && [ "$(conf_dirs | wc -l)" -eq 1 ] || return 1
  local d; d="$(conf_dirs)"
  [ -n "$d" ] && [ "$d" != "$TMP/home/.doppler" ] && [[ "$d" != "$TMP/home"* ]] \
    && ! grep -qv 'entries=0$' "$FX/envseen" && [ ! -e "$d" ]
}
scn_confdir_cleanup() { # the private dir is also removed on a failure exit (names fail, rc 3)
  build_sb "$1" spy; set_marker "$OLD4D"; echo 1 > "$FX/names_rc"; run_wb
  local d; d="$(conf_dirs)"
  [ "$RC" -eq 3 ] && [ -n "$d" ] && [ ! -e "$d" ]
}

# ═══ the base assertions (pristine wrapper) ═════════════════════════════════════════════════════
assert "H2: a valid marker 4 days old yields the gate's authorized-shape exit 0 (requires_runtime_bind_probe=true)" scn_happy "$WRAPPER"
assert "the exact argv, exactly two calls, the exact config prd_workspaces_luks_marker, never doppler run / secrets download" scn_argv "$WRAPPER"
assert "a caller-supplied marker is discarded (Doppler says absent => B_workspaces_luks_marker_absent)" scn_unset_caller "$WRAPPER"
assert "Doppler's value governs even when the caller offers a different valid one (soak not elapsed)" scn_caller_not_preferred "$WRAPPER"
assert "a transport error exits 3, the gate never runs, and Doppler's own stderr is not echoed" scn_names_fail "$WRAPPER"
assert "a prefix-colliding name does not satisfy the membership test and no get is issued" scn_prefix "$WRAPPER"
assert "the gate's own exit code propagates through exec (failure and success)" scn_exec_rc "$WRAPPER"
assert "no DOPPLER_*, BASH_ENV or ENV reaches the gate; the marker and the orchestrator's env do" scn_doppler_scrub "$WRAPPER"
assert "the gate's environment is an allowlist: DOPPLER-API-HOST, doppler_token, BASH_FUNC_* and every unrelated variable are dropped" scn_survivors "$WRAPPER"
assert "the wrapper's allowlist equals the set of variables lb-weight-gate.sh itself reads (derived from the gate)" scn_allow_parity "$WRAPPER"
assert "the derivation of the gate's reads sees every expansion form (\$NAME, \${NAME}, \${NAME:?, \${NAME:-) and ignores the gate's own variables and comments" scn_derive_sees_every_form
assert "every allowlisted gate input the caller set reaches the gate verbatim; set-but-empty stays set, unset stays unset" scn_allow_passthrough "$WRAPPER"
assert "the marker's host is seam-owned: a caller value is discarded; marker present -> web-2, absent -> unset" scn_marker_host_seam_owned "$WRAPPER"
assert "SOLEUR_PROXY_BIND is not a gate input: a caller-set value never reaches the gate and an empty one does not refuse the real gate" scn_proxy_bind_not_forwarded "$WRAPPER"
assert "an UNSET SOLEUR_SERVING_ROTATION stays unset through the wrapper and the real gate fails closed on it" scn_rotation_unset_fails_closed "$WRAPPER"
assert "a SET-BUT-EMPTY SOLEUR_SERVING_ROTATION reaches the real gate as empty (weight-0 standby still exits 0)" scn_rotation_empty_standby "$WRAPPER"
assert "an exported function shadowing env/mktemp/rm in the caller's environment never runs inside the wrapper" scn_function_purge "$WRAPPER"
assert "the Doppler calls get an empty private DOPPLER_CONFIG_DIR (not the caller's, not under HOME), removed before the exec" scn_confdir "$WRAPPER"
assert "the private DOPPLER_CONFIG_DIR is removed on a failure exit too" scn_confdir_cleanup "$WRAPPER"
assert "an ambient DOPPLER_CONFIG/DOPPLER_PROJECT cannot steer the read and is not passed to Doppler" scn_ambient_config "$WRAPPER"
assert "the PATH is pinned: a doppler earlier on the caller's PATH is never run" scn_path_pinned "$WRAPPER"
assert "a get failure after a positive membership test exits 3 (never 'absent'), the gate never runs" scn_get_fail "$WRAPPER"
assert "a malformed marker value exits 4 and is never exported" scn_shape "$WRAPPER"
assert "no DOPPLER_TOKEN exits 3 without calling Doppler" scn_token "$WRAPPER"
assert "REPRO (fixed): a doppler that exists only under RUNNER_TEMP/doppler-cli runs the full gate chain when DOPPLER_BIN names it" scn_dbin_pass "$WRAPPER"
assert "REPRO (defect): the same layout WITHOUT DOPPLER_BIN dies names_rc_127 and the gate never runs" scn_dbin_unset_127 "$WRAPPER"
assert "a DOPPLER_BIN that is not RUNNER_TEMP/doppler-cli/doppler exits 3 bad_doppler_bin, the gate not run, no doppler executed" scn_dbin_wrongpath "$WRAPPER"
assert "a DOPPLER_BIN valid under a DIFFERENT temp root than RUNNER_TEMP exits 3 bad_doppler_bin" scn_dbin_rt_mismatch "$WRAPPER"
assert "a RUNNER_TEMP carrying '..' exits 3 bad_doppler_bin although DOPPLER_BIN equals RUNNER_TEMP/doppler-cli/doppler literally" scn_dbin_dotdot "$WRAPPER"
assert "a DOPPLER_BIN that is a symlink exits 3 bad_doppler_bin" scn_dbin_symlink "$WRAPPER"
assert "a DOPPLER_BIN that is not executable exits 3 bad_doppler_bin" scn_dbin_notexec "$WRAPPER"
assert "a DOPPLER_BIN that is a directory, not a regular file, exits 3 bad_doppler_bin" scn_dbin_notfile "$WRAPPER"
if dbin_owner_constructible; then
  assert "a DOPPLER_BIN owned by another user exits 3 bad_doppler_bin" scn_dbin_foreign_owner "$WRAPPER"
  assert "a doppler-cli directory owned by another user exits 3 bad_doppler_bin" scn_dbin_foreign_dir_owner "$WRAPPER"
else
  skip "a DOPPLER_BIN / doppler-cli directory owned by another user exits 3 (NOT RUN: not root)" "a foreign-owned file cannot be constructed without root; the -O operands are pinned structurally below instead"
fi
assert "STRUCTURE: the binary's ownership test is -O \"\$p\" inside the [[ -f \"\$p\" ... ]] test (comment-stripped source)" scn_owner_pin_bin "$WRAPPER"
assert "STRUCTURE: the directory's ownership test is -O \"\$dir\" inside the [[ -d \"\$dir\" ... ]] test (comment-stripped source)" scn_owner_pin_dir "$WRAPPER"
assert "a doppler-cli directory with mode 777, 775, 757, 703 or 772 (group- or world-writable, each bit alone too) exits 3 bad_doppler_bin" scn_dbin_dir_writable "$WRAPPER"
assert "a DOPPLER_BIN with mode 775, 757, 777, 703 or 772 (group- or world-writable) exits 3 bad_doppler_bin" scn_dbin_bin_writable "$WRAPPER"
assert "MUST-PASS: dir 755/750/700 with binary 755/700/555 (no group/world write bit) all run the gate chain" scn_dbin_modes_pass "$WRAPPER"
assert "only EXACTLY RUNNER_TEMP/doppler-cli/doppler is accepted (another name, ../ hop, doppler/../ and ./ spellings exit 3)" scn_dbin_exact_variants "$WRAPPER"
assert "a RELATIVE RUNNER_TEMP with a matching relative DOPPLER_BIN exits 3 bad_doppler_bin" scn_dbin_rel_rt "$WRAPPER"
assert "an EMPTY RUNNER_TEMP with DOPPLER_BIN=/doppler-cli/doppler reaches the RUNNER_TEMP check and exits 3 bad_doppler_bin" scn_dbin_empty_rt "$WRAPPER"
assert "a symlinked RUNNER_TEMP, and a symlinked intermediate component, exit 3 bad_doppler_bin" scn_dbin_symlinked_rt "$WRAPPER"
assert "exported functions shadowing unset/export in the caller's environment never run (DOPPLER_BIN set)" scn_fn_unset "$WRAPPER"
assert "a doppler-cli directory that is a symlink exits 3 bad_doppler_bin" scn_dbin_dir_symlink "$WRAPPER"
assert "a set-but-empty DOPPLER_BIN, and a DOPPLER_BIN with no RUNNER_TEMP, exit 3 bad_doppler_bin" scn_dbin_empty_or_no_rt "$WRAPPER"

# a boxed-table listing is tolerated
scn_table() { build_sb "$1" real; set_marker "$OLD4D"; : > "$FX/names_table"; run_wb; [ "$RC" -eq 0 ] && [[ "$OUT" == *"requires_runtime_bind_probe=true"* ]]; }
assert "a boxed-table name listing is read the same way" scn_table "$WRAPPER"

# the wrapper judges nothing about the soak: a FUTURE value is valid in shape and the gate refuses it
scn_future() { build_sb "$1" real; set_marker "$FUTURE"; run_wb; [ "$RC" -eq 1 ] && [[ "$ERR" == *"sub_condition=B_workspaces_luks_marker_future"* ]]; }
assert "a future-dated value passes the wrapper's shape check and the gate refuses it (the wrapper does not judge the soak)" scn_future "$WRAPPER"

# the weight-0 standby path still passes with the marker absent (the wrapper changes no gate semantic)
scn_standby() { build_sb "$1" real; set_marker ABSENT; run_wb SOLEUR_WEB2_SERVING_WEIGHT=0 SOLEUR_SERVING_ROTATION=web-1; [ "$RC" -eq 0 ] && [[ "$OUT" == *"web2_standby=true"* ]]; }
assert "standby (weight 0, web-2 not in rotation) still exits 0 with the marker absent" scn_standby "$WRAPPER"

# ═══ constants parity and static properties ═════════════════════════════════════════════════════
const_of() { sed -nE "s/^$2=\"([^\"]*)\".*/\1/p" "$1" | head -1; }
parity() { [ -n "$(const_of "$WRAPPER" "$1")" ] && [ "$(const_of "$WRAPPER" "$1")" = "$(const_of "$ROWS_LIB" "$2")" ]; }
assert "MARKER_NAME equals W2L_MARKER_NAME in scripts/lib/web2-luks-rows.sh" parity MARKER_NAME W2L_MARKER_NAME
assert "MARKER_PROJECT equals W2L_MARKER_PROJECT" parity MARKER_PROJECT W2L_MARKER_PROJECT
assert "MARKER_CONFIG equals W2L_MARKER_CONFIG and is prd_workspaces_luks_marker" parity MARKER_CONFIG W2L_MARKER_CONFIG
assert "MARKER_CONFIG is the literal prd_workspaces_luks_marker (never prd)" test "$(const_of "$WRAPPER" MARKER_CONFIG)" = prd_workspaces_luks_marker
host_parity() { [ -n "$(const_of "$WRAPPER" MARKER_HOST)" ] && [ "soleur-$(const_of "$WRAPPER" MARKER_HOST)" = "$(const_of "$ROWS_LIB" W2L_HOST_NAME)" ]; }
assert "MARKER_HOST is the key of the host the marker's writer probes (soleur-<key> = W2L_HOST_NAME)" host_parity
iso_parity() { [ -n "$(grep -m1 '^ISO_RE=' "$WRAPPER")" ] && [ "$(grep -m1 '^ISO_RE=' "$WRAPPER")" = "$(grep -m1 '^ISO_RE=' "$GATE")" ]; }
assert "the wrapper's ISO_RE is byte-identical to the gate's" iso_parity
pinned_path_ok() {
  local p; p="$(const_of "$WRAPPER" PINNED_PATH)"; local e
  [ -n "$p" ] || return 1
  IFS=':' read -ra parts <<<"$p"
  for e in "${parts[@]}"; do case "$e" in /*) : ;; *) return 1 ;; esac; done
  return 0
}
assert "the pinned PATH holds only absolute entries (no empty or relative element)" pinned_path_ok
no_write_verbs() { # the wrapper only READS: no secrets set/delete/upload, no API write, no run/download
  ! grep -vE '^[[:space:]]*#' "$WRAPPER" | grep -ciE >/dev/null 'secrets[^|]*[[:space:]](set|delete|upload|download)\b|doppler[^|]*[[:space:]]run\b|api\.doppler\.com|curl|-X[[:space:]]*(POST|PUT|PATCH|DELETE)'
}
assert "the wrapper carries no Doppler write verb, no doppler run, no secrets download, no HTTP write" no_write_verbs
one_doppler_site() { # exactly the two read forms, both through the single doppler_ro helper
  [ "$(grep -vE '^[[:space:]]*#' "$WRAPPER" | grep -c 'doppler_ro secrets')" -eq 2 ] \
    && [ "$(grep -vE '^[[:space:]]*#' "$WRAPPER" | grep -cF '"${DOPPLER_RESOLVED:-doppler}" "$@"')" -eq 1 ] \
    && [ "$(grep -vE '^[[:space:]]*#' "$WRAPPER" | grep -cE '(^|[^_a-z])doppler[[:space:]]+"?\$@')" -eq 0 ]
}
assert "the wrapper holds exactly one doppler invocation site (through the validated DOPPLER_RESOLVED path) and two read call forms" one_doppler_site

# ═══ the census (Guard 5 / task 2.3) ════════════════════════════════════════════════════════════
# A LITERAL-STRING SCAN, NOT PROOF that nothing else feeds the gate: it flags the spellings it knows. No
# file other than the wrapper, the gate itself and *.test.* files may, in a CODE line, name the literal
# lb-weight-gate.sh, or assign/export/map WORKSPACES_LUKS_CUTOVER_AT into an environment (bare assignment,
# `export`, a `NAME:` mapping, or an env-assignment prefix `env "NAME=..."` / `env 'NAME=...'` / `env NAME=...`).
# Comment-only mentions are prose and do not count (they explain the seam); everything else is a finding.
# The scan covers every source/config file under the root, minus vendored and generated trees.
# KNOWN BLIND SPOTS (demonstrated, not fixed here): an ASSEMBLED gate path with no literal
# (`lb-weight-${G}.sh`, a glob) that does not also assign the marker; files with an extension outside the
# include list (Makefile, extension-less scripts, .cjs, .rb); `read -r NAME`; `export "NAME"`. The gate
# itself accepts any environment, so "one seam" is a convention this scan helps keep, not a mechanism.
census() { # <root> -> prints findings, one path per line
  local root="$1" f rel code
  while IFS= read -r f; do
    rel="${f#"$root"/}"
    case "$rel" in
      apps/web-platform/infra/lb-weight-gate-with-marker.sh|apps/web-platform/infra/lb-weight-gate.sh) continue ;;
      *.test.*|*/test/*|knowledge-base/*) continue ;;
    esac
    code="$(grep -vE '^[[:space:]]*(#|//)' "$f" | sed -e ':a' -e '/\\$/N; s/\\\n[[:space:]]*/ /; ta')"
    if grep -qE 'lb-weight-gate\.sh' <<<"$code" \
      || grep -qE '(^|[^A-Za-z0-9_"'"'"'])WORKSPACES_LUKS_CUTOVER_AT[[:space:]]*[=:]|export[[:space:]]+WORKSPACES_LUKS_CUTOVER_AT' <<<"$code" \
      || grep -qE '(^|[[:space:]])env[[:space:]]+(-[^[:space:]]+[[:space:]]+)*(["'"'"']?[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*["'"'"']WORKSPACES_LUKS_CUTOVER_AT=' <<<"$code"; then
      printf '%s\n' "$rel"
    fi
  done < <(grep -rIlE --include='*.sh' --include='*.bash' --include='*.yml' --include='*.yaml' --include='*.py' --include='*.ts' --include='*.tsx' --include='*.js' --include='*.mjs' --include='*.tf' --include='*.service' --include='*.json' --include='*.tpl' \
             --exclude-dir=node_modules --exclude-dir=.git --exclude-dir=.worktrees --exclude-dir=.terraform --exclude-dir=.next --exclude-dir=dist --exclude-dir=_site --exclude-dir=__pycache__ \
             'lb-weight-gate\.sh|WORKSPACES_LUKS_CUTOVER_AT' "$root" 2>/dev/null)
}
census_clean() { local out; out="$(census "$REPO_ROOT")"; [ -z "$out" ] || { printf '       census findings: %s\n' "$(tr '\n' ' ' <<<"$out")"; return 1; }; }
assert "census: no file other than the wrapper, the gate and *.test.* files invokes lb-weight-gate.sh or assigns the marker into an environment" census_clean

mk_census_root() { # a minimal tree: the real wrapper + gate, then a planted file
  CR="$(mktemp -d "$TMP/cr.XXXXXX")"; assert_fixture_dir "$CR"; mkdir -p "$CR/apps/web-platform/infra" "$CR/scripts" "$CR/.github/workflows"
  assert_fixture_dir "$CR/apps/web-platform/infra"
  assert_fixture_dir "$WRAPPER"; assert_fixture_dir "$GATE"
  cp "$WRAPPER" "$GATE" "$CR/apps/web-platform/infra/"
}
census_flags() { # <relpath> <content> -> 0 when the planted file is flagged
  mk_census_root; mkdir -p "$(dirname "$CR/$1")"; printf '%s\n' "$2" > "$CR/$1"
  [[ "$(census "$CR")" == *"$1"* ]]
}
census_silent() { # <relpath> <content> -> 0 when the planted file is NOT flagged
  mk_census_root; mkdir -p "$(dirname "$CR/$1")"; printf '%s\n' "$2" > "$CR/$1"
  [ -z "$(census "$CR")" ]
}
census_control() { mk_census_root; [ -z "$(census "$CR")" ]; }
assert "census control: the minimal tree (wrapper + gate only) has no finding" census_control
assert "row 3: a second script that invokes the gate directly is flagged" census_flags scripts/evil.sh $'#!/usr/bin/env bash\nbash apps/web-platform/infra/lb-weight-gate.sh'
assert "row 3: a gate path held in a variable and invoked later is flagged" census_flags scripts/evil2.sh $'#!/usr/bin/env bash\nG="${ROOT}/apps/web-platform/infra/lb-weight-gate.sh"\n"$G"'
assert "a workflow step that invokes the gate is flagged" census_flags .github/workflows/evil.yml $'jobs:\n  j:\n    steps:\n      - run: bash apps/web-platform/infra/lb-weight-gate.sh'
assert "a line-continued invocation is flagged" census_flags scripts/evil3.sh $'#!/usr/bin/env bash\nbash \\\n  apps/web-platform/infra/lb-weight-gate.sh'
assert "a script that assigns the marker into an environment is flagged" census_flags scripts/evil4.sh $'#!/usr/bin/env bash\nWORKSPACES_LUKS_CUTOVER_AT=2026-01-01 bash gate'
assert "a script that exports the marker is flagged" census_flags scripts/evil5.sh $'#!/usr/bin/env bash\nexport WORKSPACES_LUKS_CUTOVER_AT'
assert "a workflow env mapping of the marker is flagged" census_flags .github/workflows/evil2.yml $'jobs:\n  j:\n    steps:\n      - run: x\n        env:\n          WORKSPACES_LUKS_CUTOVER_AT: ${{ secrets.X }}'
assert "an env-assignment prefix with a DOUBLE-quoted assignment and an assembled gate path is flagged" census_flags scripts/evil6.sh $'#!/usr/bin/env bash\nenv "WORKSPACES_LUKS_CUTOVER_AT=2026-01-01" bash "$(dirname "$0")/../apps/web-platform/infra/lb-weight-${G}.sh"'
assert "an env-assignment prefix with a SINGLE-quoted assignment and an assembled gate path is flagged" census_flags scripts/evil7.sh $'#!/usr/bin/env bash\nenv \'WORKSPACES_LUKS_CUTOVER_AT=2026-01-01\' bash "$ROOT/apps/web-platform/infra/lb-weight-${G}.sh"'
assert "an env-assignment prefix with an UNQUOTED assignment and an assembled gate path is flagged" census_flags scripts/evil8.sh $'#!/usr/bin/env bash\nenv WORKSPACES_LUKS_CUTOVER_AT=2026-01-01 bash "$ROOT/apps/web-platform/infra/lb-weight-${G}.sh"'
assert "an env-assignment prefix after other assignments and flags (env -i FOO=1 \"NAME=..\") is flagged" census_flags scripts/evil9.sh $'#!/usr/bin/env bash\nenv -i FOO=1 "WORKSPACES_LUKS_CUTOVER_AT=2026-01-01" bash "$G"'
assert "a quoted assignment in a workflow run step is flagged" census_flags .github/workflows/evil3.yml $'jobs:\n  j:\n    steps:\n      - run: env "WORKSPACES_LUKS_CUTOVER_AT=${{ secrets.X }}" bash "$G"'
assert "an env prefix naming a DIFFERENT variable is NOT flagged" census_silent scripts/envok.sh $'#!/usr/bin/env bash\nenv "OTHER_VAR=1" bash run.sh'
assert "a comment-only mention is prose and is NOT flagged" census_silent scripts/harmless.sh $'#!/usr/bin/env bash\n# see lb-weight-gate.sh and WORKSPACES_LUKS_CUTOVER_AT=<iso> in the wrapper\necho ok'
assert "a *.test.sh file that names the gate is excluded by design" census_silent scripts/x.test.sh $'#!/usr/bin/env bash\nbash apps/web-platform/infra/lb-weight-gate.sh'
assert "naming the marker as a quoted constant (not an assignment into an environment) is NOT flagged" census_silent scripts/const.sh $'#!/usr/bin/env bash\nW2L_MARKER_NAME="WORKSPACES_LUKS_CUTOVER_AT"'
assert "a vendored dependency is not scanned" census_silent node_modules/pkg/evil.sh $'#!/usr/bin/env bash\nbash lb-weight-gate.sh'

# ═══ mutation rows ══════════════════════════════════════════════════════════════════════════════
# mutate <label> <sed-expr> <scenario-fn>
mutate() {
  local label="$1" sed_expr="$2" scn="$3" mf
  cases=$((cases + 1))
  mf="$TMP/mutant.$cases.sh"
  sed "$sed_expr" "$WRAPPER" > "$mf"
  if cmp -s "$mf" "$WRAPPER"; then no "$label — the mutation matched NOTHING in the wrapper (byte-identical copy); the guard is missing or the sed expression drifted"; return; fi
  # CONTROL FIRST: the mutant must still be a LIVE script (parses, and a plain run reaches the gate or a
  # structured refusal with no shell fault), else a dead script scores as a catch. It is deliberately not
  # "still passes the happy path": several defects (a wrong config, a dropped exec) legitimately change it.
  if ! bash -n "$mf" 2>/dev/null; then no "$label — the mutant does not parse (it measured a dead script, not the defect)"; return; fi
  build_sb "$mf" real; set_marker "$OLD4D"; run_wb
  if [[ "$ERR" == *"syntax error"* || "$ERR" == *"unbound variable"* || "$ERR" == *"command not found"* || "$ERR" == *"No such file"* ]]; then
    no "$label — the mutant faults at run time (it measured a dead script, not the defect)" "$ERR"; return
  fi
  if "$scn" "$mf"; then no "$label — the mutant stayed GREEN: the battery cannot see this defect"; else ok "$label -> RED"; fi
}
mutate "row 1: the caller-supplied marker is no longer unset" '/# seam:unset-caller$/d' scn_unset_caller
mutate "row 2a: the read uses --config prd" 's/^MARKER_CONFIG="prd_workspaces_luks_marker"/MARKER_CONFIG="prd"/' scn_argv
mutate "row 2b: --config is dropped from the names call" 's/ --config "\$MARKER_CONFIG" 2>\/dev\/null)" || names_rc/ 2>\/dev\/null)" || names_rc/' scn_argv
mutate "row 4: a transport error is treated as absent (the gate runs)" 's/then src_fail "names_rc_\${names_rc}"; fi # seam:names-fail/then names=""; fi # seam:names-fail/' scn_names_fail
mutate "row 5a: a prefix-colliding name satisfies the membership test" 's/if \[\[ "\$line" == "\$MARKER_NAME" \]\]; then present=1; fi # seam:exact-name/if [[ "$line" == "$MARKER_NAME"* ]]; then present=1; fi # seam:exact-name/' scn_prefix
mutate "row 5b: the exec is dropped (the gate rc is not propagated)" 's/^exec env -i "\${gate_env\[@\]}" bash "\$GATE" # seam:exec/bash "$GATE" # seam:exec/' scn_exec_rc
mutate "row 5c: the env -i allowlist is dropped (DOPPLER_* survives into the gate)" 's/^exec env -i "\${gate_env\[@\]}" bash "\$GATE" # seam:exec/exec bash "$GATE" # seam:exec/' scn_doppler_scrub
mutate "row 5c2: the env -i allowlist is dropped (DOPPLER-API-HOST / BASH_FUNC_* / unrelated names survive)" 's/^exec env -i "\${gate_env\[@\]}" bash "\$GATE" # seam:exec/exec bash "$GATE" # seam:exec/' scn_survivors
mutate "row 5d: an allowlisted gate input is dropped from GATE_ENV_ALLOW" 's/^  WORKSPACES_LUKS_SOAK_DAYS WORKSPACES_LUKS_CUTOVER_AT$/  WORKSPACES_LUKS_CUTOVER_AT/' scn_allow_passthrough
mutate "row 5d2: an allowlisted gate input is dropped from GATE_ENV_ALLOW (parity with the gate)" 's/^  WORKSPACES_LUKS_SOAK_DAYS WORKSPACES_LUKS_CUTOVER_AT$/  WORKSPACES_LUKS_CUTOVER_AT/' scn_allow_parity
mutate "row 5d3: SOLEUR_PROXY_BIND is re-added to GATE_ENV_ALLOW (a stale A.1 input is forwarded)" 's/^  SOLEUR_PROXY_PEER_ALLOWLIST SOLEUR_HOST_ROSTER$/  SOLEUR_PROXY_BIND SOLEUR_PROXY_PEER_ALLOWLIST SOLEUR_HOST_ROSTER/' scn_proxy_bind_not_forwarded
mutate "row 5d4: SOLEUR_PROXY_BIND is re-added to GATE_ENV_ALLOW (parity with the gate)" 's/^  SOLEUR_PROXY_PEER_ALLOWLIST SOLEUR_HOST_ROSTER$/  SOLEUR_PROXY_BIND SOLEUR_PROXY_PEER_ALLOWLIST SOLEUR_HOST_ROSTER/' scn_allow_parity
mutate "row 5e: a set-but-empty input is collapsed to unset" 's/if \[\[ -n "\${!v+x}" \]\]; then gate_env/if [[ -n "${!v-}" ]]; then gate_env/' scn_allow_passthrough
mutate "row 5e2: a set-but-empty input is collapsed to unset (the real gate then fails closed on standby)" 's/if \[\[ -n "\${!v+x}" \]\]; then gate_env/if [[ -n "${!v-}" ]]; then gate_env/' scn_rotation_empty_standby
mutate "row 5f: the allowlist grows past what the gate reads (HOME)" 's/^  SOLEUR_WEB2_SERVING_WEIGHT SOLEUR_GATED_HOST SOLEUR_SERVING_ROTATION$/  HOME SOLEUR_WEB2_SERVING_WEIGHT SOLEUR_GATED_HOST SOLEUR_SERVING_ROTATION/' scn_allow_parity
mutate "row 5f2: the allowlist grows past what the gate reads (HOME reaches the gate)" 's/^  SOLEUR_WEB2_SERVING_WEIGHT SOLEUR_GATED_HOST SOLEUR_SERVING_ROTATION$/  HOME SOLEUR_WEB2_SERVING_WEIGHT SOLEUR_GATED_HOST SOLEUR_SERVING_ROTATION/' scn_survivors
mutate "row 10: DOPPLER_CONFIG_DIR no longer points the Doppler calls at the private dir" 's/ DOPPLER_CONFIG_DIR="\$DOPPLER_CFG_DIR"//' scn_confdir
mutate "row 11: exported functions are no longer purged" '/# seam:purge-functions$/d' scn_function_purge
mutate "row 12: the private dir leaks past the exec" 's/^rm -rf "\$DOPPLER_CFG_DIR"$/:/' scn_confdir
mutate "row 12b: the private dir leaks on a failure exit" 's/^trap .rm -rf "\$DOPPLER_CFG_DIR". EXIT$/:/' scn_confdir_cleanup
mutate "row 6a: the PATH is not pinned for the Doppler call" 's/env -i PATH="\$PINNED_PATH"/env -i PATH="$PATH"/; s/^PATH="\$PINNED_PATH"$/PATH="$PATH"/' scn_path_pinned
mutate "row 7: a get failure after a positive membership test is read as absent" 's/if \[\[ "\$get_rc" -ne 0 \]\]; then src_fail "get_rc_\${get_rc}"; fi # seam:get-fail/if false; then :; fi # seam:get-fail/' scn_get_fail
mutate "row 8: the shape check is dropped" 's/^  if \[\[ -z "\$value" || ! "\$value" =~ \$ISO_RE \]\]; then # seam:shape/  if false; then # seam:shape/' scn_shape
mutate "row 9: the token requirement is dropped" 's/^\[\[ -n "\${DOPPLER_TOKEN-}" \]\] || src_fail "no_token" # seam:token-required/: # seam:token-required/' scn_token
mutate "row 13a: the exact-path check is dropped (a wrong path is accepted)" '/# seam:dbin-exact$/d' scn_dbin_wrongpath
mutate "row 13b: the exact-path check is dropped (a RUNNER_TEMP mismatch is accepted)" '/# seam:dbin-exact$/d' scn_dbin_rt_mismatch
# The RUNNER_TEMP shape terms (non-empty, absolute, no '..') overlap with the realpath check by design (defence in depth):
# a mutant that drops ONLY the shape line is behaviourally equivalent, so rows 13c/13e drop BOTH lines; row 14i drops
# the realpath line alone (a symlinked ancestor is invisible to every other check). The empty-string term is
# unkillable on its own (DOPPLER_BIN=/doppler-cli/doppler then fails the -f test with the same class), so
# scn_dbin_empty_rt pins the behaviour but no mutation row claims to kill it.
mutate "row 13c: the RUNNER_TEMP shape check and the realpath check are dropped ('..' accepted)" '/# seam:dbin-rt$/d; /# seam:dbin-real$/d' scn_dbin_dotdot
mutate "row 13e: the RUNNER_TEMP shape check and the realpath check are dropped (relative RUNNER_TEMP accepted)" '/# seam:dbin-rt$/d; /# seam:dbin-real$/d' scn_dbin_rel_rt
mutate "row 13d: the exact-path check is loosened to a doppler-cli/ prefix match" 's|\[\[ "\$p" == "\${rt}/doppler-cli/doppler" \]\]|[[ "$p" == "${rt}/doppler-cli/"* ]]|' scn_dbin_exact_variants
mutate "row 14i: the realpath (symlinked ancestor) check is dropped" '/# seam:dbin-real$/d' scn_dbin_symlinked_rt
mutate "row 14j: the binary group/world-writable check is dropped" '/# seam:dbin-bmode$/d' scn_dbin_bin_writable
mutate "row 14k: the directory mask is narrowed to the group bit (8#020)" 's|8#\$mode \& 8#022|8#$mode \& 8#020|' scn_dbin_dir_writable
mutate "row 14l: the directory mask is narrowed to the world bit (8#002)" 's|8#\$mode \& 8#022|8#$mode \& 8#002|' scn_dbin_dir_writable
mutate "row 14m: the binary mask is narrowed to the group bit (8#020)" 's|8#\$bmode \& 8#022|8#$bmode \& 8#020|' scn_dbin_bin_writable
mutate "row 14m2: the binary mask is narrowed to the world bit (8#002)" 's|8#\$bmode \& 8#022|8#$bmode \& 8#002|' scn_dbin_bin_writable
mutate "row 14n: the directory mode is over-strict (must be exactly 755)" 's|(( (8#\$mode \& 8#022) == 0 ))|(( 8#$mode == 8#755 ))|' scn_dbin_modes_pass
mutate "row 14n2: the binary mode is over-strict (must be exactly 755)" 's|(( (8#\$bmode \& 8#022) == 0 ))|(( 8#$bmode == 8#755 ))|' scn_dbin_modes_pass
mutate "row 14o: the -O test on the binary names the wrong operand (the temp root)" 's|-O "\$p"|-O "$rt"|' scn_owner_pin_bin
mutate "row 14p: the -O test on the directory names the wrong operand (the temp root)" 's|-O "\$dir"|-O "$rt"|' scn_owner_pin_dir
mutate "row 17: exported-function purge runs AFTER the DOPPLER_BIN unset, which is a plain unset (a shadowing unset runs)" 's|^builtin unset DOPPLER_BIN|unset DOPPLER_BIN|; /# seam:purge-functions$/{h;d}; /# seam:unset-dbin$/{p;x}' scn_fn_unset
mutate "row 14a: the not-a-symlink check on the binary is dropped" 's| \&\& ! -L "\$p"||' scn_dbin_symlink
if dbin_owner_constructible; then
  mutate "row 14b: the owned-by-euid check on the binary is dropped" 's| \&\& -O "\$p"||' scn_dbin_foreign_owner
  mutate "row 14b2: the owned-by-euid check on the directory is dropped" 's| \&\& -O "\$dir"||' scn_dbin_foreign_dir_owner
else
  skip "row 14b/14b2: the -O mutants (NOT RUN: not root); rows 14o/14p pin the operands structurally" "behavioural -O coverage needs root"
fi
mutate "row 14c: the executable check on the binary is dropped" 's| \&\& -x "\$p"||' scn_dbin_notexec
mutate "row 14d: the not-a-symlink check on the directory is dropped" 's| \&\& ! -L "\$dir"||' scn_dbin_dir_symlink
mutate "row 14e: the directory group/world-writable check is dropped" '/# seam:dbin-dirmode$/d' scn_dbin_dir_writable
mutate "row 14f: the regular-file check on the binary is dropped" 's|\[\[ -f "\$p" \&\& |[[ |' scn_dbin_notfile
mutate "row 15: an invalid DOPPLER_BIN falls back silently to the pinned PATH" 's|then src_fail "bad_doppler_bin"; fi # seam:dbin-reject|then _dbin=""; fi # seam:dbin-reject|' scn_dbin_wrongpath
mutate "row 16: doppler_ro ignores the validated absolute path" 's|"\${DOPPLER_RESOLVED:-doppler}" "\$@"|doppler "$@"|' scn_dbin_pass
mutate "row 5g: DOPPLER_BIN is allowlisted and no longer unset (it reaches the gate)" 's|^  SOLEUR_WEB2_SERVING_WEIGHT SOLEUR_GATED_HOST SOLEUR_SERVING_ROTATION$|  DOPPLER_BIN SOLEUR_WEB2_SERVING_WEIGHT SOLEUR_GATED_HOST SOLEUR_SERVING_ROTATION|; /# seam:unset-dbin$/d' scn_survivors

# row 3 as a mutation of the census input: a second invoker planted next to the real files turns it RED
cases=$((cases + 1))
mk_census_root; printf '#!/usr/bin/env bash\nbash apps/web-platform/infra/lb-weight-gate.sh\n' > "$CR/scripts/second.sh"
if [[ "$(census "$CR")" == *"scripts/second.sh"* ]]; then ok "row 3: a second script invoking the gate directly -> RED (census names it)"; else no "row 3: the census did not name a planted second invoker"; fi

# H1 — HARNESS: a stub that records NOTHING must fail the argv assertion (a recorder that records
# nothing would otherwise pass every argv check vacuously).
h1_harness() { build_sb "$WRAPPER" real norecord; set_marker "$OLD4D"; run_wb; ! argv_is "$(printf '%s\n%s' "$ARGV_NAMES" "$ARGV_GET")"; }
assert "H1: a stub that records nothing FAILS the argv assertion (the assertion is not vacuous)" h1_harness

# ═══ anti-vacuity floor + conservation ══════════════════════════════════════════════════════════
# Reported by printf + exit 1 and never through ok()/no(): a floor routed through the helpers it backstops
# goes quiet with them (ADR-193).
verdicts=$((passes + fails))
if [ "$cases" -ne "$verdicts" ]; then
  printf '  FAIL CONSERVATION: %s cases ran but %s verdicts were recorded.\n' "$cases" "$verdicts" >&2
  exit 1
fi
CASES_FLOOR=125
if [ "$cases" -lt "$CASES_FLOOR" ]; then
  printf '  FAIL ANTI-VACUITY: only %s cases ran, floor is %s.\n' "$cases" "$CASES_FLOOR" >&2
  exit 1
fi
printf '  ok   anti-vacuity floor: %s cases ran, each recorded one verdict (floor %s)\n' "$cases" "$CASES_FLOOR"

printf '\n=== lb-weight-gate-with-marker: %d passed, %d failed, %d skipped (skips are not cases and do not count toward the floor) ===\n\n' "$passes" "$fails" "$skips"
[ "$fails" -eq 0 ] || exit 1
exit 0
