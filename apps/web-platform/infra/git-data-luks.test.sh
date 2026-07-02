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
CUTOVER="${DIR}/git-data-cutover.sh"
PRERECEIVE="${DIR}/git-data-pre-receive.sh"

passes=0
fails=0
pass() { passes=$((passes + 1)); }
fail() { fails=$((fails + 1)); echo "FAIL: $1" >&2; }

[ -f "$CLOUD_INIT" ]   || { echo "FAIL: cloud-init-git-data.yml not found at $CLOUD_INIT" >&2; exit 1; }
[ -f "$LUKS_TF" ]      || { echo "FAIL: git-data-luks.tf not found at $LUKS_TF" >&2; exit 1; }
[ -f "$CUTOVER" ]      || { echo "FAIL: git-data-cutover.sh not found at $CUTOVER" >&2; exit 1; }
[ -f "$PRERECEIVE" ]   || { echo "FAIL: git-data-pre-receive.sh not found at $PRERECEIVE" >&2; exit 1; }

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

# --- Cutover-script predicates (GAP-1/2/3 + DI-HIGH review) -----------------

# GAP-1: repoint_luks_mount exists AND re-points the mapper to the hardcoded path
# (/dev/mapper/git-data mounted at /mnt/git-data) AND rewrites /etc/fstab.
p_repoint() {
  if grep -Eq '^repoint_luks_mount\(\)' "$1" \
    && grep -Eq 'mount "\$LUKS_MAPPER" "\$OLD_ROOT"' "$1" \
    && grep -Eq '/etc/fstab' "$1"; then echo 1; else echo 0; fi
}

# GAP-1: a canary asserts /mnt/git-data's source device is the LUKS mapper, AND the
# DL-2 wipe is gated on it (CANARY_OK).
p_canary_gate() {
  if grep -Eq '^canary_luks_device\(\)' "$1" \
    && grep -Eq 'findmnt -no SOURCE "\$OLD_ROOT"' "$1" \
    && grep -Eq 'CANARY_OK' "$1" \
    && grep -Eq '\[ "\$CANARY_OK" != "1" \]' "$1"; then echo 1; else echo 0; fi
}

# GAP-2: prepare_luks_target idempotently luksOpens+mounts, key via stdin --key-file -
# (never argv), fail-loud on empty key.
p_prepare_luks() {
  local f="$1"
  if grep -Eq '^prepare_luks_target\(\)' "$f" \
    && grep -Eq 'cryptsetup luksOpen --key-file - "\$luks_dev"' "$f" \
    && grep -Eq 'GIT_DATA_LUKS_KEY.*empty' "$f" \
    && ! grep -Eq 'cryptsetup luks(Open|Format)[^|]*\$GIT_DATA_LUKS_KEY' "$f"; then echo 1; else echo 0; fi
}

# GAP-3: an EXIT trap auto-recovers (rollback on flip + release freeze), and a
# ROLLBACK-only mode exists.
p_trap_rollback() {
  if grep -Eq 'trap cleanup EXIT' "$1" \
    && grep -Eq 'FLIP_DONE" = "1" \].*rollback' "$1" \
    && grep -Eq '\[ "\$ROLLBACK" = "1" \]' "$1"; then echo 1; else echo 0; fi
}

# DI-HIGH: the delta-rsync + set-identity verify that gate the flip run AFTER the
# drain (acquire_freeze before delta_rsync before verify before flip in main()).
# Matches the indented call-sites (which carry trailing comments), not the col-0
# function definitions (`name() {`).
p_postdrain_gate() {
  local f="$1" a d v ff
  a="$(grep -nE '^[[:space:]]+acquire_freeze([[:space:]]|$)' "$f" | head -1 | cut -d: -f1)"
  d="$(grep -nE '^[[:space:]]+delta_rsync([[:space:]]|$)' "$f" | head -1 | cut -d: -f1)"
  v="$(grep -nE '^[[:space:]]+verify_set_identity([[:space:]]|$)' "$f" | head -1 | cut -d: -f1)"
  ff="$(grep -nE '^[[:space:]]+flip_flag_and_reload([[:space:]]|$)' "$f" | head -1 | cut -d: -f1)"
  if [ -n "$a" ] && [ -n "$d" ] && [ -n "$v" ] && [ -n "$ff" ] \
    && [ "$a" -lt "$d" ] && [ "$d" -lt "$v" ] && [ "$v" -lt "$ff" ]; then echo 1; else echo 0; fi
}

# DI-HIGH: the pre-receive hook honours the cutover freeze sentinel (fail-closed).
p_prereceive_freeze() {
  if grep -Eq 'cutover_freeze=' "$1" \
    && grep -Eq 'if \[ -e "\$cutover_freeze" \]; then' "$1"; then echo 1; else echo 0; fi
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

# A8 (GAP-1): repoint_luks_mount re-points the mapper to the hardcoded path.
assert_holds    "A8 repoint-mount" p_repoint "$CUTOVER"
assert_mutation "A8 repoint-mount" p_repoint "$CUTOVER" 's#mount "\$LUKS_MAPPER" "\$OLD_ROOT"#mount "\$LUKS_MAPPER" "\$FRESH_ROOT"#'

# A9 (GAP-1): canary asserts the LUKS device AND gates the wipe on CANARY_OK.
assert_holds    "A9 canary-gate" p_canary_gate "$CUTOVER"
assert_mutation "A9 canary-gate" p_canary_gate "$CUTOVER" 's/CANARY_OK/CANARY_NOPE/g'

# A10 (GAP-2): prepare_luks_target unlocks via stdin --key-file -, key never argv.
assert_holds    "A10 prepare-luks" p_prepare_luks "$CUTOVER"
assert_mutation "A10 prepare-luks" p_prepare_luks "$CUTOVER" \
  's#cryptsetup luksOpen --key-file - "\$luks_dev" git-data#cryptsetup luksOpen "\$GIT_DATA_LUKS_KEY" "\$luks_dev" git-data#'

# A11 (GAP-3): EXIT-trap auto-rollback + ROLLBACK-only mode.
assert_holds    "A11 trap-rollback" p_trap_rollback "$CUTOVER"
assert_mutation "A11 trap-rollback" p_trap_rollback "$CUTOVER" 's/trap cleanup EXIT/trap - EXIT/'

# A12 (DI-HIGH): the flip-gating rsync+verify run AFTER the drain (main() order).
assert_holds    "A12 postdrain-gate" p_postdrain_gate "$CUTOVER"
# Mutation: neutralize the drain call-site so the ordered gate can no longer be
# proven (models the pre-fix "verify races live writers" arrangement) → flips to 0.
assert_mutation "A12 postdrain-gate" p_postdrain_gate "$CUTOVER" \
  's/^([[:space:]]+)acquire_freeze([[:space:]])/\1XdrainX\2/'

# A13 (DI-HIGH): the pre-receive hook denies receive-pack while the freeze sentinel exists.
assert_holds    "A13 prereceive-freeze" p_prereceive_freeze "$PRERECEIVE"
assert_mutation "A13 prereceive-freeze" p_prereceive_freeze "$PRERECEIVE" 's/cutover_freeze=/cutover_nofreeze=/g'

# --- Minimum-cardinality guard (a silent-empty harness must fail loud) ---
total=$((passes + fails))
if [ "$total" -lt 26 ]; then
  echo "FAIL: ran only ${total} assertions (<26) — suite did not execute fully" >&2
  exit 1
fi

echo "git-data-luks: ${passes} passed, ${fails} failed (${total} assertions)"
[ "$fails" -eq 0 ]
