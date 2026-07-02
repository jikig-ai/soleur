#!/usr/bin/env bash
#
# Drift guard for the git-data LUKS-at-rest cutover volume (Sub-PR 3.D / ADR-068,
# #5274 Phase 3). Asserts the SECURITY-LOAD-BEARING shape of the cloud-init LUKS
# block (cloud-init-git-data.yml) and git-data-luks.tf:
#   * cryptsetup `isLuks` idempotency guard present (2nd cloud-init run is a no-op);
#   * the LUKS passphrase is delivered via stdin (`--key-file -`) and NEVER appears
#     as a bare argv token on any luksFormat/luksOpen line (leak via `ps`/argv);
#   * the mapper /dev/mapper/git-data is mounted at /mnt/git-data-luks (the cutover
#     FRESH_ROOT git-data-cutover.sh asserts);
#   * fail-loud on an empty key — never an unencrypted fallback;
#   * the key arrives from the Doppler-injected env (doppler run), and the passphrase
#     literal is NOT baked into user_data (only random_password → doppler_secret).
#
# Each assertion is MUTATION-TESTED: the predicate is re-run against a deliberately
# broken copy and MUST flip to failing (a green test that cannot go red is worthless
# — the bash-gate-authoring foot-gun). Deliberately-nonzero commands are wrapped in
# `$(… || true)` command-subs so `set -e` never aborts the harness mid-suite.
#
# Run: bash apps/web-platform/infra/git-data-luks.test.sh
# Registered as a step in .github/workflows/infra-validation.yml.

set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLOUD_INIT="${DIR}/cloud-init-git-data.yml"
LUKS_TF="${DIR}/git-data-luks.tf"

passes=0
fails=0
pass() { passes=$((passes + 1)); }
fail() { fails=$((fails + 1)); echo "FAIL: $1" >&2; }

[ -f "$CLOUD_INIT" ] || { echo "FAIL: cloud-init-git-data.yml not found at $CLOUD_INIT" >&2; exit 1; }
[ -f "$LUKS_TF" ]    || { echo "FAIL: git-data-luks.tf not found at $LUKS_TF" >&2; exit 1; }

# --- Predicates (each takes a file, echoes "1" if the property holds, else "0") ---

# isLuks idempotency guard present.
p_isluks() {
  if grep -Eq 'cryptsetup[[:space:]]+isLuks' "$1"; then echo 1; else echo 0; fi
}

# Every luksFormat/luksOpen line pipes the key via `--key-file -` (stdin) AND carries
# NO `$GIT_DATA_LUKS_KEY` as an argv token (the key must arrive on stdin, not argv).
p_keyfile_stdin() {
  local f="$1" luks_args n_lines n_keyfile n_argvkey
  # Isolate the `cryptsetup luks…` command portion of each line (drop the legitimate
  # `printf '%s' "$GIT_DATA_LUKS_KEY" |` stdin-pipe PREFIX so it is not miscounted as
  # an argv occurrence). We assert against the cryptsetup argv ONLY.
  luks_args="$(grep -E 'cryptsetup[[:space:]]+luks(Format|Open)' "$f" | sed -E 's/.*(cryptsetup[[:space:]]+luks)/\1/' || true)"
  n_lines="$(printf '%s\n' "$luks_args" | grep -c 'cryptsetup' || true)"
  # Must have at least one luksFormat AND one luksOpen line.
  if [ "$n_lines" -lt 2 ]; then echo 0; return; fi
  # Every such cryptsetup argv must contain `--key-file -`.
  n_keyfile="$(printf '%s\n' "$luks_args" | grep -c -- '--key-file -' || true)"
  if [ "$n_keyfile" -ne "$n_lines" ]; then echo 0; return; fi
  # NO cryptsetup argv may carry the key var as a positional (the key belongs on
  # stdin via the printf pipe, NEVER on the cryptsetup command line / argv).
  n_argvkey="$(printf '%s\n' "$luks_args" | grep -c 'GIT_DATA_LUKS_KEY' || true)"
  if [ "$n_argvkey" -ne 0 ]; then echo 0; return; fi
  echo 1
}

# The key IS piped from a printf of $GIT_DATA_LUKS_KEY (proves stdin delivery exists).
p_printf_pipe() {
  if grep -Eq "printf[[:space:]]+'%s'[[:space:]]+\"\\\$GIT_DATA_LUKS_KEY\"[[:space:]]*\|[[:space:]]*cryptsetup" "$1"; then echo 1; else echo 0; fi
}

# Mapper mounted at the cutover FRESH_ROOT.
p_mapper_mount() {
  if grep -Eq 'mount[[:space:]]+/dev/mapper/git-data[[:space:]]+/mnt/git-data-luks' "$1"; then echo 1; else echo 0; fi
}

# Fail-loud on empty key (no unencrypted fallback).
p_fail_loud() {
  if grep -Eq '\[ -n "\$GIT_DATA_LUKS_KEY" \]' "$1"; then echo 1; else echo 0; fi
}

# Key sourced from the Doppler-injected env (doppler run wraps the LUKS setup).
p_doppler_run() {
  if grep -Eq 'doppler run .* -- bash' "$1"; then echo 1; else echo 0; fi
}

# The passphrase is generated (random_password) and pushed to Doppler — NEVER a
# hardcoded literal in the .tf.
p_tf_random() {
  if grep -Eq 'resource "random_password" "git_data_luks"' "$1" \
    && grep -Eq 'name[[:space:]]*=[[:space:]]*"GIT_DATA_LUKS_KEY"' "$1"; then echo 1; else echo 0; fi
}

# --- Assertion + mutation harness ---
# assert_holds <name> <predicate-fn> <file>            -> predicate MUST be 1
# assert_mutation <name> <predicate-fn> <file> <sed>   -> after the sed mutation the
#                                                          predicate MUST flip to 0
assert_holds() {
  local name="$1" fn="$2" file="$3" got
  got="$($fn "$file")"
  if [ "$got" = "1" ]; then pass; else fail "$name: property does not hold on the real file"; fi
}
assert_mutation() {
  local name="$1" fn="$2" file="$3" sed_expr="$4" tmp got
  tmp="$(mktemp "${TMPDIR:-/tmp}/gdluks-mut.XXXXXX")"
  sed -E "$sed_expr" "$file" > "$tmp"
  got="$($fn "$tmp")"
  if [ "$got" = "0" ]; then pass; else fail "$name: MUTATION did not flip the check to failing (predicate still passed on a broken copy)"; fi
  rm -f "$tmp"
}

# A1: isLuks idempotency guard.
assert_holds   "A1 isLuks-guard" p_isluks "$CLOUD_INIT"
assert_mutation "A1 isLuks-guard" p_isluks "$CLOUD_INIT" 's/cryptsetup isLuks/cryptsetup NOTisLuks/'

# A2: key via --key-file - stdin, never argv.
assert_holds   "A2 key-file-stdin" p_keyfile_stdin "$CLOUD_INIT"
# Mutation: rewrite a luksFormat to take the key as a positional argv token.
assert_mutation "A2 key-file-stdin" p_keyfile_stdin "$CLOUD_INIT" \
  's#cryptsetup luksFormat --batch-mode --type luks2 --key-file - "\$DEV"#cryptsetup luksFormat --batch-mode --type luks2 "\$GIT_DATA_LUKS_KEY" "\$DEV"#'

# A3: printf-pipe stdin delivery present.
assert_holds   "A3 printf-pipe" p_printf_pipe "$CLOUD_INIT"
assert_mutation "A3 printf-pipe" p_printf_pipe "$CLOUD_INIT" "s/printf '%s'/printf 'X%sX'/"

# A4: mapper mounted at FRESH_ROOT.
assert_holds   "A4 mapper-mount" p_mapper_mount "$CLOUD_INIT"
assert_mutation "A4 mapper-mount" p_mapper_mount "$CLOUD_INIT" 's#/mnt/git-data-luks#/mnt/git-data#g'

# A5: fail-loud on empty key.
assert_holds   "A5 fail-loud" p_fail_loud "$CLOUD_INIT"
assert_mutation "A5 fail-loud" p_fail_loud "$CLOUD_INIT" 's/\[ -n "\$GIT_DATA_LUKS_KEY" \]/true/'

# A6: doppler run wraps the setup (Doppler-injected env).
assert_holds   "A6 doppler-run" p_doppler_run "$CLOUD_INIT"
assert_mutation "A6 doppler-run" p_doppler_run "$CLOUD_INIT" 's/doppler run/doppler_run/g'

# A7: passphrase is random_password → doppler_secret (no literal in .tf).
assert_holds   "A7 tf-random-secret" p_tf_random "$LUKS_TF"
assert_mutation "A7 tf-random-secret" p_tf_random "$LUKS_TF" 's/random_password/static_password/g'

# --- Minimum-cardinality guard (a silent-empty harness must fail loud) ---
total=$((passes + fails))
if [ "$total" -lt 14 ]; then
  echo "FAIL: ran only ${total} assertions (<14) — suite did not execute fully" >&2
  exit 1
fi

echo "git-data-luks: ${passes} passed, ${fails} failed (${total} assertions)"
[ "$fails" -eq 0 ]
