#!/usr/bin/env bash
#
# Drift-guards for the LUKS-at-rest /workspaces volume (#6588, ADR-118).
#
# WHY THIS EXISTS
# ---------------
# `hcloud_volume.workspaces` holds every user's checked-out source code and is
# plaintext ext4, while the published privacy policy tells data subjects it is
# LUKS-encrypted. ADR-118 births an ADDITIVE encrypted volume rather than mutating
# the live one. These guards assert the new volume can never be born plaintext, and
# that the passphrase can never reach the agent container.
#
# The issue's acceptance criterion — "a drift guard so a future volume can't be born
# plaintext (mutation-tested: a plaintext volume must go RED)" — is A4 + A5 below.
#
# Each assertion is MUTATION-TESTED: the predicate is re-run against a deliberately
# broken copy and MUST flip to failing. A green test that cannot go red is worthless
# (the bash-gate-authoring foot-gun). Anchoring is on CONTENT, never line numbers
# (cq-cite-content-anchor-not-line-number), and on the syntactic construct rather
# than a bare token — a bare token also matches this file's own explanatory comments
# (cq-assert-anchor-not-bare-token).
#
# Run: bash apps/web-platform/infra/workspaces-luks.test.sh
# Registered as a step in .github/workflows/infra-validation.yml.
#
# `set -e` is deliberately ABSENT: deliberately-nonzero greps are wrapped so the
# harness never aborts mid-suite.
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF="$DIR/workspaces-luks.tf"

[ -f "$TF" ] || { echo "FAIL: workspaces-luks.tf not found at $TF" >&2; exit 1; }

passes=0
fails=0
pass() { passes=$((passes + 1)); }
fail() { fails=$((fails + 1)); echo "FAIL: $1" >&2; }

# --- Predicates: each takes a file, echoes 1 (holds) / 0 (does not hold) -------

# A1 — the passphrase is terraform-minted, never an operator-supplied variable
# (hr-tf-variable-no-operator-mint-default).
p_tf_random() {
  if grep -Eq '^resource "random_password" "workspaces_luks"' "$1" \
    && grep -Eq '^[[:space:]]*length[[:space:]]*=[[:space:]]*40' "$1"; then echo 1; else echo 0; fi
}

# A2 — `special = false` keeps the passphrase shell/stdin-safe for the
# `printf %s | cryptsetup --key-file -` pipe. A special char breaks that pipe.
p_special_false() {
  if grep -Eq '^[[:space:]]*special[[:space:]]*=[[:space:]]*false' "$1"; then echo 1; else echo 0; fi
}

# A3 — the Doppler secret is masked.
p_masked() {
  if grep -Eq '^[[:space:]]*visibility[[:space:]]*=[[:space:]]*"masked"' "$1"; then echo 1; else echo 0; fi
}

# A4 — THE ISSUE'S ACCEPTANCE CRITERION. The new volume must carry NO `format`
# attribute. C7: `format = "ext4"` makes a fresh volume byte-indistinguishable from
# the live plaintext volume (both TYPE=ext4), which destroys the only sound
# luksFormat guard — "format only a device with no filesystem signature". A raw
# device makes the discriminator exist. A `format` line here IS the plaintext-birth
# drift this guard names.
p_no_format() {
  if grep -Eq '^[[:space:]]*format[[:space:]]*=' "$1"; then echo 0; else echo 1; fi
}

# A5 — the volume resource exists and is a SINGLETON, not `for_each`. C18: a
# for_each'd attachment lands outside web2_allow in
# destroy-guard-filter-web-platform.jq and permanently bricks the web-2-recreate
# path; `moved` also wants a singleton source.
p_singleton_volume() {
  local block
  block="$(awk '/^resource "hcloud_volume" "workspaces_luks"/,/^}/' "$1")"
  if [ -z "$block" ]; then echo 0; return; fi
  if printf '%s' "$block" | grep -Eq '^[[:space:]]*for_each[[:space:]]*='; then echo 0; else echo 1; fi
}

# A6 — the attachment pins to web-1 explicitly. web-1 is the sole live origin
# (app.soleur.ai is a hard-pinned singleton A record); web-2 has never served.
p_attach_web1() {
  local block
  block="$(awk '/^resource "hcloud_volume_attachment" "workspaces_luks"/,/^}/' "$1")"
  if [ -z "$block" ]; then echo 0; return; fi
  if printf '%s' "$block" | grep -Eq 'hcloud_server\.web\["web-1"\]\.id'; then echo 1; else echo 0; fi
}

# A7 — C6, security-load-bearing. The key MUST live in a dedicated Doppler config,
# never shared `prd`. cloud-init.yml runs `doppler secrets download --config prd`
# into a TMPENV consumed by `docker run --env-file`, so EVERY prd secret is injected
# into the agent container's env. A WORKSPACES_LUKS_KEY in `prd` would be readable
# via /proc/self/environ by the very agent code whose data it encrypts (CWE-522),
# reducing the at-rest guarantee to zero against in-container compromise.
p_dedicated_config() {
  local block
  block="$(awk '/^resource "doppler_secret" "workspaces_luks_key"/,/^}/' "$1")"
  if [ -z "$block" ]; then echo 0; return; fi
  if printf '%s' "$block" | grep -Eq '^[[:space:]]*config[[:space:]]*=[[:space:]]*"prd_workspaces_luks"'; then
    echo 1
  else
    echo 0
  fi
}

# A8 — the boot token is read-only (least privilege).
p_token_read_only() {
  local block
  block="$(awk '/^resource "doppler_service_token" "workspaces_luks"/,/^}/' "$1")"
  if [ -z "$block" ]; then echo 0; return; fi
  if printf '%s' "$block" | grep -Eq '^[[:space:]]*access[[:space:]]*=[[:space:]]*"read"'; then echo 1; else echo 0; fi
}

# A9 — no `ignore_changes` on the passphrase. Both precedents agree rotation must be
# operator-explicit via -replace, and an ignore_changes would silently mask drift.
#
# ANCHORED ON THE ASSIGNMENT, NOT THE BARE TOKEN — and comment lines are stripped
# first. A bare `grep -Eq 'ignore_changes'` false-FAILED here on the .tf's own prose
# ("NO ignore_changes — rotation is operator-explicit"), which is the exact
# cq-assert-anchor-not-bare-token collision: the moment a file must BOTH omit a
# construct AND document why, a bare-token grep cannot tell the two apart. `#`-led
# lines carry no config; only a real HCL attribute has `ignore_changes =`.
p_no_ignore_changes() {
  if sed -E 's/^[[:space:]]*#.*$//' "$1" | grep -Eq 'ignore_changes[[:space:]]*='; then
    echo 0
  else
    echo 1
  fi
}

# A10 — the key never appears as a terraform variable (it is minted, not supplied).
# Scoped to the passphrase: a legitimate `workspaces_luks_volume_size` variable must
# not trip this (C18 LOW — AC19's original grep collided with exactly that).
p_no_operator_variable() {
  if grep -Eq '^variable "workspaces_luks_key"' "$1"; then echo 0; else echo 1; fi
}

# --- Harness ------------------------------------------------------------------

assert_holds() {
  local name="$1" fn="$2" file="$3" got
  got="$($fn "$file")"
  if [ "$got" = "1" ]; then pass; else fail "$name: property does not hold on the real file"; fi
}

assert_mutation() {
  local name="$1" fn="$2" file="$3" sed_expr="$4" tmp got
  tmp="$(mktemp "${TMPDIR:-/tmp}/wsluks-mut.XXXXXX")"
  sed -E "$sed_expr" "$file" > "$tmp"
  got="$($fn "$tmp")"
  if [ "$got" = "0" ]; then
    pass
  else
    fail "$name: MUTATION did not flip the check to failing (predicate still passed on a broken copy)"
  fi
  rm -f "$tmp"
}

# A mutation that ADDS a violating line (the inverse shape: guards whose violation is
# a PRESENCE, not an absence). A deletion-based sed cannot test these.
assert_mutation_append() {
  local name="$1" fn="$2" file="$3" line="$4" tmp got
  tmp="$(mktemp "${TMPDIR:-/tmp}/wsluks-mut.XXXXXX")"
  cp "$file" "$tmp"
  printf '%s\n' "$line" >> "$tmp"
  got="$($fn "$tmp")"
  if [ "$got" = "0" ]; then
    pass
  else
    fail "$name: MUTATION (appended violating line) did not flip the check to failing"
  fi
  rm -f "$tmp"
}

assert_holds "A1 passphrase is terraform-minted (length 40)" p_tf_random "$TF"
assert_mutation "A1" p_tf_random "$TF" 's/^resource "random_password" "workspaces_luks"/resource "random_password" "other"/'

assert_holds "A2 special = false (stdin-pipe-safe)" p_special_false "$TF"
assert_mutation "A2" p_special_false "$TF" 's/special([[:space:]]*)=([[:space:]]*)false/special\1=\2true/'

assert_holds "A3 doppler secret is masked" p_masked "$TF"
assert_mutation "A3" p_masked "$TF" 's/visibility([[:space:]]*)=([[:space:]]*)"masked"/visibility\1=\2"unmasked"/'

# THE acceptance criterion: a plaintext-born volume must go RED.
assert_holds "A4 volume carries NO format attribute (raw device — C7)" p_no_format "$TF"
assert_mutation_append "A4 (plaintext-birth drift)" p_no_format "$TF" '  format   = "ext4"'

assert_holds "A5 volume is a singleton, not for_each" p_singleton_volume "$TF"
assert_mutation "A5" p_singleton_volume "$TF" 's/^resource "hcloud_volume" "workspaces_luks"/resource "hcloud_volume" "gone"/'

assert_holds "A6 attachment pins to web-1" p_attach_web1 "$TF"
assert_mutation "A6" p_attach_web1 "$TF" 's/hcloud_server\.web\["web-1"\]\.id/hcloud_server.web["web-2"].id/'

assert_holds "A7 key lives in dedicated prd_workspaces_luks config (C6/CWE-522)" p_dedicated_config "$TF"
assert_mutation "A7 (key leaks into agent container env)" p_dedicated_config "$TF" 's/config([[:space:]]*)=([[:space:]]*)"prd_workspaces_luks"/config\1=\2"prd"/'

assert_holds "A8 boot service token is read-only" p_token_read_only "$TF"
assert_mutation "A8" p_token_read_only "$TF" 's/access([[:space:]]*)=([[:space:]]*)"read"/access\1=\2"admin"/'

assert_holds "A9 no ignore_changes (rotation is -replace-explicit)" p_no_ignore_changes "$TF"
assert_mutation_append "A9" p_no_ignore_changes "$TF" '  lifecycle { ignore_changes = [result] }'

assert_holds "A10 passphrase is never an operator-supplied variable" p_no_operator_variable "$TF"
assert_mutation_append "A10" p_no_operator_variable "$TF" 'variable "workspaces_luks_key" {}'

# --- Minimum-cardinality guard (a silent-empty harness must fail loud) ---------
total=$((passes + fails))
if [ "$total" -lt 20 ]; then
  echo "FAIL: ran only ${total} assertions (<20) — suite did not execute fully" >&2
  exit 1
fi

echo "workspaces-luks: ${passes} passed, ${fails} failed (${total} assertions)"
[ "$fails" -eq 0 ]
