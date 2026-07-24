#!/usr/bin/env bash
#
# Drift guard for the registry (zot) LUKS-at-rest store volume (#6895 / ADR-096 amendment /
# ADR-140). Asserts the SECURITY-LOAD-BEARING shape of the guest-side LUKS block in
# cloud-init-registry.yml + the Terraform apparatus in zot-registry.tf:
#   * D1/Option B `blkid TYPE` discriminator (fresh -> luksFormat; crypto_LUKS -> reuse; any
#     OTHER TYPE -> FATAL refuse, never a silent wipe — the ADR-096 preserve-path footgun);
#   * the LUKS passphrase is delivered via stdin (`--key-file -`) and NEVER appears as a bare
#     argv token on any luksFormat/luksOpen line (leak via `ps`/argv);
#   * the mapper /dev/mapper/registry is mounted at /var/lib/zot, with an fstab MAPPER line
#     (never the stale raw by-id device);
#   * fail-loud on an empty key — never an unencrypted fallback;
#   * the key arrives from the Doppler-injected env (scoped soleur-registry/prd), the passphrase
#     is random_password -> doppler_secret (no literal in .tf), and the volume is a RAW device
#     (no format="ext4"), its attachment binding the real volume;
#   * D2 (REQUIRED): an idempotent boot-time luksOpen (registry-luks-open.service) ordered after
#     network-online and BEFORE docker + the NIC-guard self-heal (the host self-reboots);
#   * P1-A: the boot isolation self-check admits REGISTRY_LUKS_KEY at cardinality 4;
#   * P1-B: the Doppler CLI env-file write precedes the LUKS mount block;
#   * the resize path targets the MAPPER (/dev/mapper/registry), not the raw device.
#
# Each assertion is MUTATION-TESTED: the predicate is re-run against a deliberately broken copy
# and MUST flip to failing (a green test that cannot go red is worthless — the bash-gate-authoring
# foot-gun). Deliberately-nonzero commands are wrapped in `$(… || true)` so `set -e` never aborts.
#
# Run: bash apps/web-platform/infra/registry-luks.test.sh
# Registered as a step in .github/workflows/infra-validation.yml (infra .test.sh are NOT globbed).

set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLOUD_INIT="${DIR}/cloud-init-registry.yml"
LUKS_TF="${DIR}/zot-registry.tf"

passes=0
fails=0
pass() { passes=$((passes + 1)); }
fail() { fails=$((fails + 1)); echo "FAIL: $1" >&2; }

[ -f "$CLOUD_INIT" ] || { echo "FAIL: cloud-init-registry.yml not found at $CLOUD_INIT" >&2; exit 1; }
[ -f "$LUKS_TF" ]    || { echo "FAIL: zot-registry.tf not found at $LUKS_TF" >&2; exit 1; }

# --- Predicates (each takes a file, echoes "1" if the property holds, else "0") ---

# D1/B blkid TYPE discriminator: reads TYPE off the RAW device, has a crypto_LUKS reuse arm, and
# an else->FATAL refuse arm (the plaintext-volume footgun). All three must be present.
p_discriminator() {
  if grep -qE 'blkid -o value -s TYPE "\$DEV"' "$1" \
    && grep -qE 'crypto_LUKS\)' "$1" \
    && grep -qF 'refusing-non-luks-device' "$1"; then echo 1; else echo 0; fi
}

# Every luksFormat/luksOpen line pipes the key via `--key-file -` (stdin) AND carries NO
# $REGISTRY_LUKS_KEY as an argv token (the key must arrive on stdin, not argv).
p_keyfile_stdin() {
  local f="$1" luks_args n_lines n_keyfile n_argvkey
  # Exclude comment lines FIRST (a `# ... cryptsetup luksFormats it ...` narrative line would
  # otherwise be miscounted as a command line that lacks `--key-file -`).
  luks_args="$(grep -vE '^[[:space:]]*#' "$f" | grep -E 'cryptsetup[[:space:]]+luks(Format|Open)' | sed -E 's/.*(cryptsetup[[:space:]]+luks)/\1/' || true)"
  n_lines="$(printf '%s\n' "$luks_args" | grep -c 'cryptsetup' || true)"
  if [ "$n_lines" -lt 2 ]; then echo 0; return; fi
  n_keyfile="$(printf '%s\n' "$luks_args" | grep -c -- '--key-file -' || true)"
  if [ "$n_keyfile" -ne "$n_lines" ]; then echo 0; return; fi
  n_argvkey="$(printf '%s\n' "$luks_args" | grep -c 'REGISTRY_LUKS_KEY' || true)"
  if [ "$n_argvkey" -ne 0 ]; then echo 0; return; fi
  echo 1
}

# The key IS piped from a printf of $REGISTRY_LUKS_KEY (proves stdin delivery exists).
p_printf_pipe() {
  if grep -Eq "printf[[:space:]]+'%s'[[:space:]]+\"\\\$REGISTRY_LUKS_KEY\"[[:space:]]*\|[[:space:]]*cryptsetup" "$1"; then echo 1; else echo 0; fi
}

# Mapper mounted at the zot store root.
p_mapper_mount() {
  if grep -Eq 'mount[[:space:]]+/dev/mapper/registry[[:space:]]+/var/lib/zot' "$1"; then echo 1; else echo 0; fi
}

# fstab evidence names the MAPPER (this is what the encryption-posture linter resolves).
p_fstab_mapper() {
  if grep -Eq "echo '/dev/mapper/registry /var/lib/zot ext4 defaults,nofail 0 2' >> /etc/fstab" "$1"; then echo 1; else echo 0; fi
}

# Fail-loud on empty key (no unencrypted fallback).
p_fail_loud() {
  if grep -Eq '\[ -n "\$REGISTRY_LUKS_KEY" \]' "$1"; then echo 1; else echo 0; fi
}

# Key sourced from the Doppler-injected env, scoped to the isolated soleur-registry/prd config.
p_doppler_run() {
  if grep -Eq 'doppler run --project soleur-registry --config prd -- bash' "$1"; then echo 1; else echo 0; fi
}

# The passphrase is generated (random_password) and pushed to Doppler — NEVER a literal in the .tf.
p_tf_random() {
  if grep -Eq 'resource "random_password" "registry_luks"' "$1" \
    && grep -Eq 'name[[:space:]]*=[[:space:]]*"REGISTRY_LUKS_KEY"' "$1"; then echo 1; else echo 0; fi
}

# D1/B: the registry volume is a RAW device — NO format="ext4" (guest luksFormats it).
p_no_format_ext4() {
  if ! grep -Eq 'format[[:space:]]*=[[:space:]]*"ext4"' "$1"; then echo 1; else echo 0; fi
}

# The attachment binds the real registry volume (linter attachment_binds_volume).
p_attach_binds() {
  if grep -Eq 'volume_id[[:space:]]*=[[:space:]]*hcloud_volume\.registry\.id' "$1"; then echo 1; else echo 0; fi
}

# D2 (REQUIRED): boot-time luksOpen oneshot, ordered after network-online and BEFORE docker + cron
# (the host self-reboots, so the mapper must reopen before the self-heal / zot launch).
p_d2_bootopen() {
  if grep -qF 'Reopen the registry LUKS store mapper on boot' "$1" \
    && grep -qF '/usr/local/bin/registry-luks-open.sh' "$1" \
    && grep -qE 'After=network-online.target' "$1" \
    && grep -qF 'Before=docker.service cron.service' "$1"; then echo 1; else echo 0; fi
}

# P1-A: the boot isolation self-check admits REGISTRY_LUKS_KEY AND its cardinality is 4 (was 3).
p_isolation_card4() {
  if grep -qE "grep -Ec '.*REGISTRY_LUKS_KEY.*'" "$1" \
    && grep -qF '[ "$n_total" -ne 4 ]'  "$1"; then echo 1; else echo 0; fi
}

# P1-B: the Doppler CLI env-file write precedes the LUKS mount block (else the mount `doppler run`
# has neither the CLI nor the token).
p_p1b_order() {
  local f="$1" env_ln luks_ln
  env_ln="$(grep -nF '> /etc/default/registry-doppler' "$f" | grep -F 'printf' | head -1 | cut -d: -f1)"
  luks_ln="$(grep -nE 'cryptsetup[[:space:]]+luksFormat' "$f" | head -1 | cut -d: -f1)"
  if [ -n "$env_ln" ] && [ -n "$luks_ln" ] && [ "$env_ln" -lt "$luks_ln" ]; then echo 1; else echo 0; fi
}

# The stale raw by-id fstab line for /var/lib/zot is ABSENT (only the mapper line remains).
p_no_stale_byid_fstab() {
  if ! grep -Eq 'scsi-0HC_Volume_[^ ]* /var/lib/zot ext4' "$1"; then echo 1; else echo 0; fi
}

# The resize path targets the MAPPER, never the raw $DEV (a raw resize2fs hits the LUKS header).
p_resize_mapper() {
  if grep -Eq 'resize2fs /dev/mapper/registry' "$1" \
    && ! grep -Eq 'resize2fs "\$DEV"' "$1"; then echo 1; else echo 0; fi
}

# --- Assertion + mutation harness ---
# assert_holds <name> <predicate-fn> <file>            -> predicate MUST be 1
# assert_mutation <name> <predicate-fn> <file> <sed>   -> after the sed mutation the predicate
#                                                          MUST flip to 0
assert_holds() {
  local name="$1" fn="$2" file="$3" got
  got="$($fn "$file")"
  if [ "$got" = "1" ]; then pass; else fail "$name: property does not hold on the real file"; fi
}
assert_mutation() {
  local name="$1" fn="$2" file="$3" sed_expr="$4" tmp got
  tmp="$(mktemp "${TMPDIR:-/tmp}/regluks-mut.XXXXXX")"
  sed -E "$sed_expr" "$file" > "$tmp"
  got="$($fn "$tmp")"
  if [ "$got" = "0" ]; then pass; else fail "$name: MUTATION did not flip the check to failing (predicate still passed on a broken copy)"; fi
  rm -f "$tmp"
}

# A1: blkid TYPE discriminator (fresh/crypto_LUKS/else-FATAL).
assert_holds    "A1 discriminator" p_discriminator "$CLOUD_INIT"
assert_mutation "A1 discriminator" p_discriminator "$CLOUD_INIT" 's/crypto_LUKS\)/NOTLUKS)/'

# A2: key via --key-file - stdin, never argv.
assert_holds    "A2 key-file-stdin" p_keyfile_stdin "$CLOUD_INIT"
assert_mutation "A2 key-file-stdin" p_keyfile_stdin "$CLOUD_INIT" \
  's#cryptsetup luksFormat --batch-mode --type luks2 --key-file - "\$DEV"#cryptsetup luksFormat --batch-mode --type luks2 "\$REGISTRY_LUKS_KEY" "\$DEV"#'

# A3: printf-pipe stdin delivery present.
assert_holds    "A3 printf-pipe" p_printf_pipe "$CLOUD_INIT"
assert_mutation "A3 printf-pipe" p_printf_pipe "$CLOUD_INIT" "s/printf '%s'/printf 'X%sX'/g"

# A4: mapper mounted at /var/lib/zot.
assert_holds    "A4 mapper-mount" p_mapper_mount "$CLOUD_INIT"
assert_mutation "A4 mapper-mount" p_mapper_mount "$CLOUD_INIT" 's#mount /dev/mapper/registry /var/lib/zot#mount /dev/mapper/registry /mnt/wrong#g'

# A5: fstab evidence names the mapper.
assert_holds    "A5 fstab-mapper" p_fstab_mapper "$CLOUD_INIT"
assert_mutation "A5 fstab-mapper" p_fstab_mapper "$CLOUD_INIT" 's#/dev/mapper/registry /var/lib/zot ext4 defaults,nofail 0 2#/dev/mapper/WRONG /var/lib/zot ext4 defaults,nofail 0 2#'

# A6: fail-loud on empty key.
assert_holds    "A6 fail-loud" p_fail_loud "$CLOUD_INIT"
assert_mutation "A6 fail-loud" p_fail_loud "$CLOUD_INIT" 's/\[ -n "\$REGISTRY_LUKS_KEY" \]/true/g'

# A7: doppler run (scoped soleur-registry/prd) wraps the setup.
assert_holds    "A7 doppler-run" p_doppler_run "$CLOUD_INIT"
assert_mutation "A7 doppler-run" p_doppler_run "$CLOUD_INIT" 's/doppler run/doppler_run/g'

# A8: passphrase is random_password -> doppler_secret (no literal in .tf).
assert_holds    "A8 tf-random-secret" p_tf_random "$LUKS_TF"
assert_mutation "A8 tf-random-secret" p_tf_random "$LUKS_TF" 's/random_password/static_password/g'

# A9: the registry volume is RAW — no format="ext4" (D1/B).
assert_holds    "A9 no-format-ext4" p_no_format_ext4 "$LUKS_TF"
assert_mutation "A9 no-format-ext4" p_no_format_ext4 "$LUKS_TF" 's#resource "hcloud_volume" "registry" \{#resource "hcloud_volume" "registry" {\n  format = "ext4"#'

# A10: the attachment binds the real registry volume.
assert_holds    "A10 attach-binds" p_attach_binds "$LUKS_TF"
assert_mutation "A10 attach-binds" p_attach_binds "$LUKS_TF" 's/hcloud_volume\.registry\.id/hcloud_volume.wrong.id/g'

# A11 (D2): boot-time luksOpen ordered before the self-heal + zot launch.
assert_holds    "A11 d2-bootopen" p_d2_bootopen "$CLOUD_INIT"
assert_mutation "A11 d2-bootopen" p_d2_bootopen "$CLOUD_INIT" 's/Before=docker.service cron.service/After=docker.service/'

# A12 (P1-A): the isolation self-check admits REGISTRY_LUKS_KEY at cardinality 4.
assert_holds    "A12 isolation-card4" p_isolation_card4 "$CLOUD_INIT"
# Mutation (plan-specified): leave the count at 3 => the guard would FATAL a valid 4-secret boot.
assert_mutation "A12 isolation-card4" p_isolation_card4 "$CLOUD_INIT" 's/-ne 4/-ne 3/g'

# A13 (P1-B): the Doppler env-file write precedes the LUKS mount block.
assert_holds    "A13 p1b-order" p_p1b_order "$CLOUD_INIT"
# Mutation: delete the env-file write -> the "precedes" relation can no longer be proven.
assert_mutation "A13 p1b-order" p_p1b_order "$CLOUD_INIT" '/printf .HOME=.root.*registry-doppler/d'

# A14: the stale raw by-id fstab line for /var/lib/zot is absent.
assert_holds    "A14 no-stale-byid-fstab" p_no_stale_byid_fstab "$CLOUD_INIT"
assert_mutation "A14 no-stale-byid-fstab" p_no_stale_byid_fstab "$CLOUD_INIT" 's#/dev/mapper/registry /var/lib/zot ext4#/dev/disk/by-id/scsi-0HC_Volume_x /var/lib/zot ext4#'

# A15: the resize path targets the mapper, not the raw device.
assert_holds    "A15 resize-mapper" p_resize_mapper "$CLOUD_INIT"
assert_mutation "A15 resize-mapper" p_resize_mapper "$CLOUD_INIT" 's#resize2fs /dev/mapper/registry#resize2fs "$DEV"#g'

# --- Minimum-cardinality guard (a silent-empty harness must fail loud) ---
total=$((passes + fails))
if [ "$total" -lt 30 ]; then
  echo "FAIL: ran only ${total} assertions (<30) — suite did not execute fully" >&2
  exit 1
fi

echo "registry-luks: ${passes} passed, ${fails} failed (${total} assertions)"
[ "$fails" -eq 0 ]
