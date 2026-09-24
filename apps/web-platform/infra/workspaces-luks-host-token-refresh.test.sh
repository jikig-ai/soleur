#!/usr/bin/env bash
#
# Gate for the #8632 boot-token delivery path:
#   - apps/web-platform/infra/luks-monitor-token-refresh.sh (runs ON web-1 as root), and
#   - terraform_data.luks_monitor_token_install in workspaces-luks.tf, which ships and runs it in the
#     same apply that rotates doppler_service_token.workspaces_luks (ADR-119 2026-09-24 addendum).
#
# What must hold, and why each one matters:
#   (1) A token that cannot read WORKSPACES_LUKS_KEY never replaces one that can: the helper proves
#       the new token with luks-monitor.sh's pinned doppler form BEFORE it writes anything.
#   (2) The host file keeps every non-token line (the baked SOLEUR_SENTRY_DSN is what lets a Doppler
#       outage still page) and ends with exactly ONE DOPPLER_TOKEN line, mode 600.
#   (3) The token travels on STDIN only. It is never an argument to ANY program the helper runs
#       (every external command below is a recorder that logs its argv), never printed, and never
#       in the logger line that reaches Better Stack. Root sources this file, so the value is
#       restricted to the service-token alphabet.
#   (4) Every refusal reaches journald under the vector-shipped luks-monitor tag, so a failed
#       rotation is readable off-box without SSH.
#   (5) The replace code is the SAME code workspaces-cutover.sh used for the first write.
#   (6) The Terraform wiring: the only trigger is the token hash (a helper comment edit must not
#       re-provision web-1), the connection pins web-1's host key, the key reaches the helper through
#       a builtin printf on stdin, the token has create_before_destroy, the per-merge SSH apply
#       targets the resource, and nothing on this path starts luks-monitor.service.
set -euo pipefail

HELPER="apps/web-platform/infra/luks-monitor-token-refresh.sh"
CUTOVER="apps/web-platform/infra/workspaces-cutover.sh"
TF="apps/web-platform/infra/workspaces-luks.tf"
APPLY_WF=".github/workflows/apply-web-platform-infra.yml"
[[ -f "$TF" ]] || { echo "FAIL - $TF not found (run from the repo root)"; exit 1; }

pass=0
fail=0
ok() { pass=$((pass + 1)); printf 'ok   - %s\n' "$1"; }
no() { fail=$((fail + 1)); printf 'FAIL - %s\n' "$1"; }

# Instrument self-test: both helpers must move their counter, or every verdict below is noise.
ok "instrument self-test (pass arm)" > /dev/null
no "instrument self-test (fail arm)" > /dev/null
if [[ "$pass" -ne 1 || "$fail" -ne 1 ]]; then
  printf 'FATAL: verdict helpers are broken (pass=%s fail=%s)\n' "$pass" "$fail"
  exit 2
fi
pass=0
fail=0

python3 -c 'import yaml' 2>/dev/null || pip3 install --quiet pyyaml

export TMPDIR="${TMPDIR:-/var/tmp}"
SCRATCH="$(mktemp -d -t wl-token-refresh.XXXXXXXX)"
trap 'rm -rf "$SCRATCH"' EXIT INT TERM HUP
# The canonical fixture-dir assertion, byte-equal to the definition in
# plugins/soleur/test/test-helpers.sh (that file also defines assert_eq/PASS/FAIL
# counters this suite owns itself, so it is copied rather than sourced).
# plugins/soleur/test/fixture-dir-operand-assert.test.sh compares every copy in the
# tree against that one with comments stripped — edit there, then re-sync here.
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
assert_fixture_dir "$SCRATCH"
mkdir -p "$SCRATCH/bin"

# Synthesized and split across concatenation: a contiguous service-token-shaped literal trips GitHub
# push protection even though it is fake (cq-test-fixtures-synthesized-only).
TOKEN_PREFIX="dp."'st.'
NEW_TOKEN="${TOKEN_PREFIX}prd_workspaces_luks.FIXTURExNEWxTOKENxxxxxxxxxxxxxxxxxxxxxxxx"
OLD_TOKEN="${TOKEN_PREFIX}prd_workspaces_luks.FIXTURExOLDxTOKENxxxxxxxxxxxxxxxxxxxxxxxx"
DSN_LINE="SOLEUR_SENTRY_DSN=https://fixture@o0.ingest.example/1"
FIXTURE_KEY="fixture-luks-passphrase"

# --- recorders ------------------------------------------------------------------------------------
# Every external command the helper can run is shadowed by a recorder that logs its argv and then
# execs the REAL binary (resolved to an absolute path BEFORE PATH is changed, so a recorder cannot
# re-enter itself). Property (3) is then a grep over one file of every argv the helper produced.
for cmd in grep sed cp chmod rm mktemp cat; do
  real="$(command -v "$cmd")"
  case "$real" in /*) : ;; *) printf 'FATAL: %s is not an external binary here (%s)\n' "$cmd" "$real"; exit 2 ;; esac
  printf '#!/usr/bin/env bash\nprintf "%%s %%s\\n" %q "$*" >> "${STUB_CALLS:?}"\nexec %q "$@"\n' "$cmd" "$real" > "$SCRATCH/bin/$cmd"
  chmod +x "$SCRATCH/bin/$cmd"
done
# mv additionally supports fault injection: FIXTURE_MV_CORRUPT=1 appends a stray line to the target
# after the FIRST real move, so the helper's post-write checks and its restore path are driven.
real_mv="$(command -v mv)"
cat > "$SCRATCH/bin/mv" <<EOS
#!/usr/bin/env bash
printf 'mv %s\n' "\$*" >> "\${STUB_CALLS:?}"
$real_mv "\$@" || exit \$?
if [[ "\${FIXTURE_MV_CORRUPT:-0}" == 1 && ! -e "\${STUB_CALLS}.corrupted" ]]; then
  : > "\${STUB_CALLS}.corrupted"
  printf 'STRAY=injected\n' >> "\${@: -1}"
fi
EOS
chmod +x "$SCRATCH/bin/mv"
cat > "$SCRATCH/bin/logger" <<'EOS'
#!/usr/bin/env bash
printf 'logger %s\n' "$*" >> "${STUB_CALLS:?}"
exit 0
EOS
# doppler: records argv, and records WHETHER the token it received (in its environment, where the
# helper must put it) is the expected one — never the token itself.
cat > "$SCRATCH/bin/doppler" <<'EOS'
#!/usr/bin/env bash
printf 'doppler %s\n' "$*" >> "${STUB_CALLS:?}"
if [[ "${DOPPLER_TOKEN:-}" == "${EXPECT_TOKEN:-}" ]]; then
  printf 'doppler-env-token=expected\n' >> "$STUB_CALLS"
else
  printf 'doppler-env-token=other\n' >> "$STUB_CALLS"
fi
[[ "${HOME:-}" == /root ]] && printf 'doppler-env-home=root\n' >> "$STUB_CALLS"
[[ -z "${DOPPLER_CONFIG_DIR:-}" ]] && printf 'doppler-env-no-config-dir\n' >> "$STUB_CALLS"
# Whether the EnvironmentFile existed while the token was being proven (H2's ordering property).
if [[ -e "${FIXTURE_ENVF:?}" || -L "$FIXTURE_ENVF" ]]; then
  printf 'doppler-saw-envfile=present\n' >> "$STUB_CALLS"
else
  printf 'doppler-saw-envfile=absent\n' >> "$STUB_CALLS"
fi
# H2g: another root writer creates the file while the token is being proven.
[[ "${FIXTURE_PLANT_DURING_PROOF:-0}" == 1 ]] && printf 'PLANTED=1\n' > "$FIXTURE_ENVF"
if [[ "$*" != "secrets get WORKSPACES_LUKS_KEY --plain --config prd_workspaces_luks" ]]; then
  printf 'STUB-MISS doppler %s\n' "$*" >&2
  exit 64
fi
[[ "${FIXTURE_DOPPLER_RC:-0}" == 0 ]] || exit "$FIXTURE_DOPPLER_RC"
printf '%s' "${FIXTURE_DOPPLER_OUT-fixture-luks-passphrase}"
EOS
chmod +x "$SCRATCH/bin/logger" "$SCRATCH/bin/doppler"

# run_helper <case> <stdin> [envfile-seed|__ABSENT__] [extra bash flags]
# The helper's target is a literal (it runs as root). Point a scratch COPY at the fixture file, and
# refuse to run if the rewrite did not land — an unrewritten copy would target the real path.
run_helper() {
  local c="$1" input="$2" seed="${3:-}" flags="${4:-}"
  local envf="$SCRATCH/$c.env" rc=0
  : > "$SCRATCH/$c.calls"
  if [[ "$seed" != "__ABSENT__" ]]; then
    printf '%s' "$seed" > "$envf"
    chmod 644 "$envf"
  fi
  sed "s|^ENVF=\"/etc/default/luks-monitor\"\$|ENVF=\"$envf\"|" "$HELPER" > "$SCRATCH/$c.helper.sh"
  if ! grep -qxF "ENVF=\"$envf\"" "$SCRATCH/$c.helper.sh" || [[ "$(grep -c '^ENVF=' "$SCRATCH/$c.helper.sh")" != 1 ]]; then
    printf 'FATAL: the ENVF rewrite did not land (exactly once) in the scratch copy of %s\n' "$HELPER" >&2
    exit 2
  fi
  # shellcheck disable=SC2086
  printf '%s' "$input" | PATH="$SCRATCH/bin:$PATH" STUB_CALLS="$SCRATCH/$c.calls" \
    EXPECT_TOKEN="$NEW_TOKEN" FIXTURE_ENVF="$envf" DOPPLER_CONFIG_DIR=/tmp/should-be-unset \
    FIXTURE_DOPPLER_RC="${DRC:-0}" FIXTURE_DOPPLER_OUT="${DOUT-fixture-luks-passphrase}" FIXTURE_MV_CORRUPT="${MVC:-0}" FIXTURE_PLANT_DURING_PROOF="${PLANT:-0}" \
    bash $flags "$SCRATCH/$c.helper.sh" > "$SCRATCH/$c.out" 2>&1 || rc=$?
  printf '%s\n' "$rc" > "$SCRATCH/$c.rc"
}
rc_of() { cat "$SCRATCH/$1.rc"; }
token_lines() { grep -c '^DOPPLER_TOKEN=' "$SCRATCH/$1.env" || true; }
leaks() { # leaks <case> <token> -> number of artifacts carrying the token (output, every argv)
  local n=0 f
  for f in "$SCRATCH/$1.out" "$SCRATCH/$1.calls"; do
    [[ -f "$f" ]] && grep -qF -- "$2" "$f" && n=$((n + 1))
  done
  printf '%s\n' "$n"
}
logged_reason() { grep -qE "^logger -t luks-monitor -- SOLEUR_LUKS_HOST_TOKEN_REFRESH result=fail reason=$2\$" "$SCRATCH/$1.calls"; }
unchanged() { grep -qxF "DOPPLER_TOKEN=$OLD_TOKEN" "$SCRATCH/$1.env" && [[ "$(token_lines "$1")" == 1 ]]; }

SEED="$(printf '%s\nDOPPLER_TOKEN=%s\n' "$DSN_LINE" "$OLD_TOKEN")"

if [[ ! -f "$HELPER" ]]; then
  no "the host helper $HELPER exists"
else
  ok "the host helper $HELPER exists"
  bash -n "$HELPER" && ok "helper passes bash -n" || no "helper passes bash -n"

  # H1 — the positive control.
  run_helper h1 "$NEW_TOKEN"$'\n' "$SEED"
  [[ "$(rc_of h1)" == 0 ]] && ok "H1 healthy rotation exits 0" || no "H1 healthy rotation exits 0 (rc=$(rc_of h1): $(tail -3 "$SCRATCH/h1.out" | tr '\n' ' '))"
  [[ "$(token_lines h1)" == 1 ]] && ok "H1 exactly one DOPPLER_TOKEN line remains" || no "H1 exactly one DOPPLER_TOKEN line remains (got $(token_lines h1))"
  grep -qxF "DOPPLER_TOKEN=$NEW_TOKEN" "$SCRATCH/h1.env" && ok "H1 the token line carries the NEW token" || no "H1 the token line carries the NEW token"
  grep -qF "$OLD_TOKEN" "$SCRATCH/h1.env" && no "H1 the OLD token is gone from the file" || ok "H1 the OLD token is gone from the file"
  grep -qxF "$DSN_LINE" "$SCRATCH/h1.env" && ok "H1 the SOLEUR_SENTRY_DSN line is preserved" || no "H1 the SOLEUR_SENTRY_DSN line is preserved"
  [[ "$(stat -c %a "$SCRATCH/h1.env")" == 600 ]] && ok "H1 the file ends mode 600" || no "H1 the file ends mode 600 (got $(stat -c %a "$SCRATCH/h1.env"))"
  grep -qxF "doppler secrets get WORKSPACES_LUKS_KEY --plain --config prd_workspaces_luks" "$SCRATCH/h1.calls" && ok "H1 the token is proven with luks-monitor.sh's pinned doppler form" || no "H1 the token is proven with the pinned doppler form"
  grep -qxF "doppler-env-token=expected" "$SCRATCH/h1.calls" && ok "H1 doppler receives the NEW token through its environment" || no "H1 doppler receives the NEW token through its environment"
  grep -qxF "doppler-env-home=root" "$SCRATCH/h1.calls" && ok "H1 doppler runs with HOME=/root" || no "H1 doppler runs with HOME=/root"
  grep -qxF "doppler-env-no-config-dir" "$SCRATCH/h1.calls" && ok "H1 an inherited DOPPLER_CONFIG_DIR is cleared (#6536)" || no "H1 an inherited DOPPLER_CONFIG_DIR is cleared"
  # Ordering: the proof precedes the first write to the file.
  first_doppler="$(grep -n '^doppler secrets' "$SCRATCH/h1.calls" | head -1 | cut -d: -f1)" || true
  first_mv="$(grep -n '^mv ' "$SCRATCH/h1.calls" | head -1 | cut -d: -f1)" || true
  [[ -n "$first_doppler" && -n "$first_mv" && "$first_doppler" -lt "$first_mv" ]] && ok "H1 the token is proven BEFORE the file is replaced" || no "H1 the token is proven BEFORE the file is replaced (doppler@${first_doppler:-none} mv@${first_mv:-none})"
  grep -qxF "[luks-token-refresh] result=ok" "$SCRATCH/h1.out" && ok "H1 prints the ok verdict" || no "H1 prints the ok verdict"
  grep -qxF "logger -t luks-monitor -- SOLEUR_LUKS_HOST_TOKEN_REFRESH result=ok" "$SCRATCH/h1.calls" && ok "H1 the outcome reaches journald under the luks-monitor tag" || no "H1 the outcome reaches journald under the luks-monitor tag"
  [[ "$(leaks h1 "$NEW_TOKEN")" == 0 ]] && ok "H1 the NEW token is in no output and no argv of any program" || no "H1 the NEW token leaked into output or an argv"
  [[ "$(leaks h1 "$OLD_TOKEN")" == 0 ]] && ok "H1 the OLD token is in no output and no argv of any program" || no "H1 the OLD token leaked into output or an argv"
  grep -qF "$FIXTURE_KEY" "$SCRATCH/h1.out" && no "H1 the passphrase read back is never printed" || ok "H1 the passphrase read back is never printed"
  grep -q 'STUB-MISS' "$SCRATCH/h1.out" && no "H1 no stub was asked a question it does not model" || ok "H1 no stub was asked a question it does not model"
  ls "$SCRATCH"/h1.env.* 2>/dev/null | grep -vqE '/h1\.env$' && no "H1 no sibling file (backup or tmp) holding a token is left beside the env file" || ok "H1 no sibling file (backup or tmp) holding a token is left beside the env file"

  # H2 — no EnvironmentFile (the live web-1 state on 2026-09-24, #8632's first apply): create it
  # the way workspaces-cutover.sh does (0600 root, token line only), AFTER the token is proven.
  run_helper h2 "$NEW_TOKEN"$'\n' "__ABSENT__"
  [[ "$(rc_of h2)" == 0 ]] && ok "H2 an absent EnvironmentFile is created, not refused" || no "H2 an absent EnvironmentFile is created, not refused (rc=$(rc_of h2): $(tail -2 "$SCRATCH/h2.out" | tr '\n' ' '))"
  [[ -f "$SCRATCH/h2.env" && "$(cat "$SCRATCH/h2.env")" == "DOPPLER_TOKEN=$NEW_TOKEN" ]] && ok "H2 the created file holds exactly the new token line" || no "H2 the created file holds exactly the new token line"
  [[ -f "$SCRATCH/h2.env" && "$(stat -c %a "$SCRATCH/h2.env")" == 600 ]] && ok "H2 the created file is mode 600" || no "H2 the created file is mode 600"
  grep -qxF "logger -t luks-monitor -- SOLEUR_LUKS_HOST_TOKEN_REFRESH result=ok created_envfile=1" "$SCRATCH/h2.calls" && ok "H2 the creation is recorded off-box (created_envfile=1)" || no "H2 the creation is recorded off-box (created_envfile=1)"
  [[ "$(leaks h2 "$NEW_TOKEN")" == 0 ]] && ok "H2 the token is in no output and no argv while creating the file" || no "H2 the token leaked while creating the file"
  # The creation is a shell redirect no recorder sees, so the doppler stub reports what it found.
  grep -qxF "doppler-saw-envfile=absent" "$SCRATCH/h2.calls" && ok "H2 the token is proven BEFORE the file is created" || no "H2 the token is proven BEFORE the file is created ($(grep '^doppler-saw-envfile=' "$SCRATCH/h2.calls" || echo 'doppler never ran'))"
  # H2b — a token that cannot read the key creates nothing.
  DRC=1 run_helper h2b "$NEW_TOKEN"$'\n' "__ABSENT__"
  [[ "$(rc_of h2b)" != 0 ]] && logged_reason h2b token_read_failed && ok "H2b a rejected token on an absent file is refused (token_read_failed)" || no "H2b a rejected token on an absent file is refused"
  [[ -e "$SCRATCH/h2b.env" ]] && no "H2b a rejected token creates no file" || ok "H2b a rejected token creates no file"
  # H2c — a corrupted write into a file this run created is rolled back to ABSENT, not to empty.
  MVC=1 run_helper h2c "$NEW_TOKEN"$'\n' "__ABSENT__"
  [[ "$(rc_of h2c)" != 0 ]] && logged_reason h2c envfile_other_lines_changed && ok "H2c a corrupted write into a created file is detected" || no "H2c a corrupted write into a created file is detected (rc=$(rc_of h2c))"
  [[ -e "$SCRATCH/h2c.env" ]] && no "H2c the created file is removed on rollback" || ok "H2c the created file is removed on rollback"
  # H2d — a symlink at the path (dangling or not) is refused, never written through as root.
  ln -sf "$SCRATCH/h2d.victim" "$SCRATCH/h2d.env"
  run_helper h2d "$NEW_TOKEN"$'\n' "__ABSENT__"
  [[ "$(rc_of h2d)" != 0 ]] && logged_reason h2d envfile_symlink && ok "H2d a symlinked EnvironmentFile is refused (envfile_symlink)" || no "H2d a symlinked EnvironmentFile is refused (rc=$(rc_of h2d))"
  [[ -e "$SCRATCH/h2d.victim" ]] && no "H2d nothing is written through the symlink" || ok "H2d nothing is written through the symlink"
  # H2e — a directory at the path is refused.
  mkdir -p "$SCRATCH/h2e.env"
  run_helper h2e "$NEW_TOKEN"$'\n' "__ABSENT__"
  [[ "$(rc_of h2e)" != 0 ]] && logged_reason h2e envfile_not_regular && ok "H2e a directory at the EnvironmentFile path is refused (envfile_not_regular)" || no "H2e a directory at the path is refused (rc=$(rc_of h2e))"
  # H2f — a write that fails after creation leaves the path ABSENT, not an empty file.
  mkdir -p "$SCRATCH/h2f.env.tmp"
  run_helper h2f "$NEW_TOKEN"$'\n' "__ABSENT__"
  [[ "$(rc_of h2f)" != 0 ]] && logged_reason h2f envfile_write_failed && ok "H2f a failed write after creation is reported (envfile_write_failed)" || no "H2f a failed write after creation is reported (rc=$(rc_of h2f))"
  [[ -e "$SCRATCH/h2f.env" ]] && no "H2f the created file is removed when the write fails" || ok "H2f the created file is removed when the write fails"
  # H2g — a file another writer creates DURING the proof: step 3 re-checks existence, so it is not
  # treated as ours (never removed), and its lines differ from the empty `before`, so it is restored
  # as found. (`set -C` covers only the instant between that re-check and the redirect, which no
  # fixture can drive deterministically.)
  PLANT=1 run_helper h2g "$NEW_TOKEN"$'\n' "__ABSENT__"
  [[ "$(rc_of h2g)" != 0 ]] && logged_reason h2g envfile_other_lines_changed && ok "H2g a file created during the proof is detected, not adopted (envfile_other_lines_changed)" || no "H2g a file created during the proof is detected (rc=$(rc_of h2g))"
  [[ "$(cat "$SCRATCH/h2g.env" 2>/dev/null)" == "PLANTED=1" ]] && ok "H2g the concurrently created file is left exactly as its writer left it" || no "H2g the concurrently created file is left exactly as its writer left it"

  # H3/H4 — shapes that never reach the file.
  run_helper h3 "" "$SEED"
  [[ "$(rc_of h3)" != 0 ]] && unchanged h3 && ok "H3 an empty token is refused and the file is untouched" || no "H3 an empty token is refused and the file is untouched"
  logged_reason h3 token_empty && ok "H3 token_empty reaches journald" || no "H3 token_empty reaches journald"
  run_helper h4 "dp.pt.personal-token-shape"$'\n' "$SEED"
  [[ "$(rc_of h4)" != 0 ]] && unchanged h4 && ok "H4 a personal-token shape is refused and the file is untouched" || no "H4 a personal-token shape is refused"
  logged_reason h4 token_shape_invalid && ok "H4 token_shape_invalid reaches journald" || no "H4 token_shape_invalid reaches journald"
  run_helper h4b "${TOKEN_PREFIX}"$'\n' "$SEED"
  [[ "$(rc_of h4b)" != 0 ]] && unchanged h4b && ok "H4b a bare dp.st. prefix is refused" || no "H4b a bare dp.st. prefix is refused"
  run_helper h4c "${TOKEN_PREFIX}"'$(touch${IFS}'"$SCRATCH"'/pwned)'$'\n' "$SEED"
  [[ "$(rc_of h4c)" != 0 ]] && unchanged h4c && ok "H4c a token carrying \$(...) is refused (root sources this file)" || no "H4c a token carrying \$(...) is refused"
  [[ -e "$SCRATCH/pwned" ]] && no "H4c nothing in the token was executed" || ok "H4c nothing in the token was executed"
  grep -q 'doppler secrets' "$SCRATCH/h4c.calls" && no "H4c a refused shape never reaches doppler" || ok "H4c a refused shape never reaches doppler"
  run_helper h4d "${TOKEN_PREFIX}has space"$'\n' "$SEED"
  [[ "$(rc_of h4d)" != 0 ]] && unchanged h4d && ok "H4d a token with whitespace is refused" || no "H4d a token with whitespace is refused"
  run_helper h4e "$NEW_TOKEN"$'\n'"$DSN_LINE"$'\n' "$SEED"
  [[ "$(rc_of h4e)" != 0 ]] && unchanged h4e && ok "H4e multi-line input is refused, not joined into one token" || no "H4e multi-line input is refused"
  logged_reason h4e token_multiline && ok "H4e token_multiline reaches journald" || no "H4e token_multiline reaches journald"
  run_helper h4f "$NEW_TOKEN"$'\r\n' "$SEED"
  [[ "$(rc_of h4f)" == 0 ]] && grep -qxF "DOPPLER_TOKEN=$NEW_TOKEN" "$SCRATCH/h4f.env" && ok "H4f a CRLF-terminated line is accepted with the CR stripped" || no "H4f a CRLF-terminated line is accepted with the CR stripped"

  # H5/H6 — a token that cannot read the key never replaces the working one.
  DRC=1 run_helper h5 "$NEW_TOKEN"$'\n' "$SEED"
  [[ "$(rc_of h5)" != 0 ]] && unchanged h5 && ok "H5 a token doppler rejects is refused and the old token is kept" || no "H5 a token doppler rejects is refused and the old token is kept"
  logged_reason h5 token_read_failed && ok "H5 token_read_failed reaches journald" || no "H5 token_read_failed reaches journald"
  DOUT="" run_helper h6 "$NEW_TOKEN"$'\n' "$SEED"
  [[ "$(rc_of h6)" != 0 ]] && unchanged h6 && logged_reason h6 token_read_failed && ok "H6 an EMPTY key read (rc 0) is refused and the old token is kept" || no "H6 an empty key read is refused (rc=$(rc_of h6))"

  # H7 — xtrace would print the token: refuse before reading it.
  run_helper h7 "$NEW_TOKEN"$'\n' "$SEED" "-x"
  [[ "$(rc_of h7)" == 78 ]] && ok "H7 the helper refuses to run under xtrace (exit 78)" || no "H7 the helper refuses to run under xtrace (rc=$(rc_of h7))"
  [[ "$(leaks h7 "$NEW_TOKEN")" == 0 ]] && unchanged h7 && ok "H7 no token leaked and the file is untouched under xtrace" || no "H7 no token leaked under xtrace"

  # H8 — a file that never had a token line (DSN only) gains exactly one.
  run_helper h8 "$NEW_TOKEN"$'\n' "$(printf '%s\n' "$DSN_LINE")"
  [[ "$(rc_of h8)" == 0 && "$(token_lines h8)" == 1 ]] && grep -qxF "$DSN_LINE" "$SCRATCH/h8.env" && ok "H8 a DSN-only file gains exactly one token line" || no "H8 a DSN-only file gains exactly one token line"

  # H9 — a stale .tmp symlink is not written through.
  printf 'untouched\n' > "$SCRATCH/h9.victim"
  ln -sf "$SCRATCH/h9.victim" "$SCRATCH/h9.env.tmp"
  run_helper h9 "$NEW_TOKEN"$'\n' "$SEED"
  [[ "$(rc_of h9)" == 0 && "$(cat "$SCRATCH/h9.victim")" == untouched ]] && ok "H9 a symlink planted at \${ENVF}.tmp is removed, not followed" || no "H9 a symlink planted at \${ENVF}.tmp is removed, not followed"

  # H10 — duplicate token lines collapse to one.
  run_helper h10 "$NEW_TOKEN"$'\n' "$(printf '%s\nDOPPLER_TOKEN=%s\nDOPPLER_TOKEN=%s\n' "$DSN_LINE" "$OLD_TOKEN" "$OLD_TOKEN")"
  [[ "$(rc_of h10)" == 0 && "$(token_lines h10)" == 1 ]] && ok "H10 duplicate DOPPLER_TOKEN lines collapse to one" || no "H10 duplicate DOPPLER_TOKEN lines collapse to one"

  # H11 — a write that corrupts another line is detected and the ORIGINAL file is restored.
  MVC=1 run_helper h11 "$NEW_TOKEN"$'\n' "$SEED"
  [[ "$(rc_of h11)" != 0 ]] && logged_reason h11 envfile_other_lines_changed && ok "H11 a corrupted rewrite is detected (envfile_other_lines_changed)" || no "H11 a corrupted rewrite is detected (rc=$(rc_of h11))"
  [[ "$(cat "$SCRATCH/h11.env")" == "$SEED" ]] && ok "H11 the original file is restored byte for byte" || no "H11 the original file is restored byte for byte"
  [[ "$(stat -c %a "$SCRATCH/h11.env")" == 600 ]] && ok "H11 the restored file is mode 600" || no "H11 the restored file is mode 600"

  # The helper never starts the unit (comment-stripped, so a sentence about it cannot satisfy this).
  if grep -vE '^[[:space:]]*#' "$HELPER" | grep -qE 'systemctl[[:space:]]+(start|restart)'; then
    no "the helper never starts or restarts a unit"
  else
    ok "the helper never starts or restarts a unit"
  fi
  if grep -vE '^[[:space:]]*#' "$HELPER" | grep -qE 'doppler[[:space:]]+(run|secrets[[:space:]]+download)'; then
    no "the helper uses only the pinned doppler form (no run, no download)"
  else
    ok "the helper uses only the pinned doppler form (no run, no download)"
  fi
fi

# --- (5) the replace code is the cutover's code -----------------------------------------------------
python3 - "$CUTOVER" "$HELPER" > "$SCRATCH/parity.tsv" <<'PY'
import sys, re
def core(path):
    try:
        s = open(path).read()
    except FileNotFoundError:
        return None
    lines = [re.sub(r"\s+", " ", l.strip()) for l in s.splitlines()]
    a = [l for l in lines if l.startswith("( umask 077; { grep -v '^DOPPLER_TOKEN=' \"$ENVF\"")]
    b = [l for l in lines if l.startswith("&& mv \"${ENVF}.tmp\" \"$ENVF\" && chmod 600 \"$ENVF\"")]
    return (a, b)
c, h = core(sys.argv[1]), core(sys.argv[2])
if c is None or h is None:
    print("no\treplace-code parity: a file is missing")
else:
    print(("ok" if len(c[0]) == 1 and len(h[0]) == 1 else "no") + "\teach file carries exactly one replace statement")
    print(("ok" if c[0] == h[0] and c[0] else "no") + "\tthe replace statement is identical in the cutover and the helper")
    print(("ok" if len(c[1]) == 1 and len(h[1]) == 1 else "no") + "\teach file carries exactly one mv+chmod tail")
    print(("ok" if c[1] and h[1] and c[1][0].split(" ||")[0] == h[1][0].split(" ||")[0] else "no") + "\tthe mv+chmod tail is identical in both files")
PY
while IFS=$'\t' read -r v name; do
  [[ -n "${v:-}" ]] || continue
  if [[ "$v" == ok ]]; then ok "$name"; else no "$name"; fi
done < "$SCRATCH/parity.tsv"

# --- (6) the Terraform wiring (comment-stripped HCL) -------------------------------------------------
python3 - "$TF" "$APPLY_WF" > "$SCRATCH/tf.tsv" <<'PY'
import sys, re, yaml
tf_path, wf_path = sys.argv[1:3]
out = []
def check(name, cond, detail=""):
    out.append(("ok" if cond else "no", name, " ".join(str(detail).split())[:200]))

def strip(src):
    # Remove # and // comments outside double-quoted strings, line by line.
    res = []
    for line in src.splitlines():
        buf, q, i = [], False, 0
        while i < len(line):
            ch = line[i]
            if ch == '"' and (i == 0 or line[i - 1] != "\\"):
                q = not q
            if not q and (ch == "#" or line.startswith("//", i)):
                break
            buf.append(ch); i += 1
        res.append("".join(buf))
    return "\n".join(res)

def block(src, kind, name):
    m = re.search(r'resource\s+"%s"\s+"%s"\s*\{' % (kind, name), src)
    if not m:
        return None
    depth, i = 1, m.end()
    while i < len(src) and depth:
        depth += {"{": 1, "}": -1}.get(src[i], 0); i += 1
    return src[m.end():i - 1]

src = strip(open(tf_path).read())
tok = block(src, "doppler_service_token", "workspaces_luks")
check("doppler_service_token.workspaces_luks exists", tok is not None)
if tok:
    check("the token carries lifecycle { create_before_destroy = true }",
          re.search(r'lifecycle\s*\{[^}]*create_before_destroy\s*=\s*true', tok) is not None)
inst = block(src, "terraform_data", "luks_monitor_token_install")
check("terraform_data.luks_monitor_token_install exists", inst is not None)
if inst:
    trig = re.findall(r'(?m)^\s*triggers_replace\s*=\s*(.+?)\s*$', inst)
    check("the ONLY trigger is the token hash (no file() hash, no other operand)",
          trig == ["nonsensitive(sha256(doppler_service_token.workspaces_luks.key))"], trig)
    conn = re.search(r'connection\s*\{([^}]*)\}', inst)
    cbody = conn.group(1) if conn else ""
    check("the connection dials web-1", re.search(r'(?m)^\s*host\s*=\s*hcloud_server\.web\["web-1"\]\.ipv4_address\s*$', cbody) is not None, cbody)
    check("the connection pins web-1's host key", re.search(r'(?m)^\s*host_key\s*=\s*local\.web_1_ssh_host_key\s*$', cbody) is not None)
    dest = re.findall(r'provisioner\s+"file"\s*\{[^}]*source\s*=\s*"\$\{path\.module\}/luks-monitor-token-refresh\.sh"[^}]*destination\s*=\s*"([^"]+)"', inst)
    check("a file provisioner ships the helper from the repo", len(dest) == 1, dest)
    key_lines = [l for l in inst.splitlines() if "doppler_service_token.workspaces_luks.key" in l and "triggers_replace" not in l]
    check("the key appears in exactly one command line", len(key_lines) == 1, key_lines)
    if dest and key_lines:
        want = "printf '%%s\\\\n' '${doppler_service_token.workspaces_luks.key}' | bash %s" % dest[0]
        # EXACT line equality: a containment check let the key also ride as an argument after the
        # helper path (a mutant that survived the first battery).
        check("that line pipes the key via a builtin printf into the shipped helper, and nothing else",
              key_lines[0].strip() == '"%s",' % want, key_lines[0].strip())
    check("nothing in the installer starts or restarts luks-monitor.service",
          re.search(r'systemctl\s+(start|restart)', inst) is None)
    timer_lines = [l for l in inst.splitlines() if "luks-monitor.timer" in l]
    check("the installer reports the timer's state into the apply log", len(timer_lines) >= 1, len(timer_lines))
    check("no line that reports the timer carries the key (so its output is not suppressed)",
          all("doppler_service_token" not in l for l in timer_lines))

wf = yaml.safe_load(open(wf_path))
targets = set()
for job in (wf.get("jobs") or {}).values():
    for step in job.get("steps") or []:
        run = str(step.get("run", ""))
        if "terraform_data.web_1_host_key_probe" in run:
            targets |= set(re.findall(r"-target=(terraform_data\.[a-z0-9_]+)", run))
check("the per-merge SSH apply targets terraform_data.luks_monitor_token_install",
      "terraform_data.luks_monitor_token_install" in targets, sorted(targets)[:5])
for v in out:
    print("\t".join(v))
PY
while IFS=$'\t' read -r v name detail; do
  [[ -n "${v:-}" ]] || continue
  if [[ "$v" == ok ]]; then ok "$name"; else no "$name${detail:+ ($detail)}"; fi
done < "$SCRATCH/tf.tsv"

printf '\n%s passed, %s failed\n' "$pass" "$fail"

# Anti-vacuity floor. The threshold sits on the line directly above its `if`.
MIN_ASSERTIONS=79
if [[ "$pass" -lt "$MIN_ASSERTIONS" ]]; then
  printf 'FAIL - only %s assertions passed (floor %s) — a block stopped running\n' "$pass" "$MIN_ASSERTIONS"
  exit 1
fi
[[ "$fail" -eq 0 ]] || exit 1
