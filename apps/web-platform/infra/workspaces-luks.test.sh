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

# --- Helpers ------------------------------------------------------------------

# Strip ALL THREE HCL comment forms. This file's entire job is to forbid constructs
# that workspaces-luks.tf must also DISCUSS in prose, so every predicate that greps
# for a forbidden token must see code only. Knowing just `#` is what let A9
# false-FAIL on its own .tf's comment once already; `//` and `/* */` are the same
# trap wearing different hats.
strip_comments() {
  sed -E -e 's~/\*.*\*/~~g' -e 's~^[[:space:]]*(#|//).*$~~' "$1"
}

# Extract one resource block by BRACE DEPTH, not by an `awk /^}/` range.
# The range form terminates at the first column-0 `}`, so a nested block closed at
# column 0 truncates the extraction and hides everything after it — a proven
# false-PASS (a `labels` block closed at col 0 with `for_each` after it reported
# 20/20 green on a for_each'd volume). `terraform fmt` would reject that layout, but
# fmt runs in a DIFFERENT CI job (validate) from this guard (deploy-script-tests),
# so relying on it makes this suite's soundness depend on a gate it never names.
# Brace depth removes the coupling.
block_of() {
  local file="$1" type="$2" name="$3"
  strip_comments "$file" | awk -v t="$type" -v n="$name" '
    $0 ~ "^resource[[:space:]]+\"" t "\"[[:space:]]+\"" n "\"" { inb = 1 }
    inb {
      print
      d += gsub(/\{/, "{")
      d -= gsub(/\}/, "}")
      if (d <= 0 && NR > 1 && /\}/) { inb = 0 }
    }
  '
}

# --- Predicates: each takes a file, echoes 1 (holds) / 0 (does not hold) -------

# A1 — the passphrase is terraform-minted, never an operator-supplied variable
# (hr-tf-variable-no-operator-mint-default).
# BLOCK-SCOPED. A whole-file grep here false-PASSED: drifting the real passphrase to
# `length = 12` and adding ONE unrelated random_password carrying `length = 40`
# satisfied the grep on the sibling's behalf — fmt-clean, valid HCL, 20/20 green.
# Assert the property OF THE RESOURCE YOU MEAN, never of the file.
p_tf_random() {
  local b
  b="$(block_of "$1" random_password workspaces_luks)"
  if [ -z "$b" ]; then echo 0; return; fi
  if printf '%s' "$b" | grep -Eq '^[[:space:]]*length[[:space:]]*=[[:space:]]*40[[:space:]]*$'; then echo 1; else echo 0; fi
}

# A2 — `special = false` keeps the passphrase shell/stdin-safe for the
# `printf %s | cryptsetup --key-file -` pipe. A special char breaks that pipe.
# BLOCK-SCOPED — same scope-leak as A1 (a sibling random_password carrying
# `special = false` laundered a real `special = true` drift to green).
p_special_false() {
  local b
  b="$(block_of "$1" random_password workspaces_luks)"
  if [ -z "$b" ]; then echo 0; return; fi
  if printf '%s' "$b" | grep -Eq '^[[:space:]]*special[[:space:]]*=[[:space:]]*false[[:space:]]*$'; then echo 1; else echo 0; fi
}

# A3 — the Doppler secret is masked.
# BLOCK-SCOPED — same scope-leak as A1/A2 (a sibling doppler_secret carrying
# `visibility = "masked"` laundered a real `visibility = "unmasked"` drift to green).
p_masked() {
  local b
  b="$(block_of "$1" doppler_secret workspaces_luks_key)"
  if [ -z "$b" ]; then echo 0; return; fi
  if printf '%s' "$b" | grep -Eq '^[[:space:]]*visibility[[:space:]]*=[[:space:]]*"masked"[[:space:]]*$'; then echo 1; else echo 0; fi
}

# A4 — THE ISSUE'S ACCEPTANCE CRITERION. The new volume must carry NO `format`
# attribute. C7: `format = "ext4"` makes a fresh volume byte-indistinguishable from
# the live plaintext volume (both TYPE=ext4), which destroys the only sound
# luksFormat guard — "format only a device with no filesystem signature". A raw
# device makes the discriminator exist. A `format` line here IS the plaintext-birth
# drift this guard names.
p_no_format() {
  # Comment-stripped: this .tf DISCUSSES the omitted `format` at length, and a
  # `/* format = "ext4" ... */` note would otherwise false-FAIL the guard. Documenting
  # WHY a construct is absent must never redden the guard that forbids it.
  if strip_comments "$1" | grep -Eq '^[[:space:]]*format[[:space:]]*='; then echo 0; else echo 1; fi
}

# A5 — the volume resource exists and is a SINGLETON, not `for_each`. C18: a
# for_each'd attachment lands outside web2_allow in
# destroy-guard-filter-web-platform.jq and permanently bricks the web-2-recreate
# path; `moved` also wants a singleton source.
p_singleton_volume() {
  local block
  block="$(block_of "$1" hcloud_volume workspaces_luks)"
  if [ -z "$block" ]; then echo 0; return; fi
  if printf '%s' "$block" | grep -Eq '^[[:space:]]*for_each[[:space:]]*='; then echo 0; else echo 1; fi
}

# A6 — the attachment pins to web-1 explicitly. web-1 is the sole live origin
# (app.soleur.ai is a hard-pinned singleton A record); web-2 has never served.
p_attach_web1() {
  local block
  block="$(block_of "$1" hcloud_volume_attachment workspaces_luks)"
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
  block="$(block_of "$1" doppler_secret workspaces_luks_key)"
  if [ -z "$block" ]; then echo 0; return; fi
  if printf '%s' "$block" | grep -Eq '^[[:space:]]*config[[:space:]]*=[[:space:]]*"prd_workspaces_luks"'; then
    echo 1
  else
    echo 0
  fi
}

# A8 — the boot token cannot WRITE secrets.
#
# NOT "least privilege" — that framing is false and this assertion does not carry it.
# `prd_workspaces_luks` is a BRANCH config, and branch configs inherit the root, so
# this token still READS all ~116 prd secrets (#6167;
# learnings/security-issues/2026-07-07-doppler-branch-config-does-not-isolate-secrets.md).
# What A8 actually pins is the write leg: `access = "admin"` would let a compromised
# host rewrite the escrowed passphrase, and re-minting the key without re-keying the
# LUKS header is the terminal mode ADR-118 §(f) names.
p_token_read_only() {
  local block
  block="$(block_of "$1" doppler_service_token workspaces_luks)"
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
  # HCL accepts `#` AND `//` line comments — strip both. NOTE the `~` delimiter: a
  # `|` delimiter collides with the alternation's own `|` and sed dies with
  # "unknown option to `s'" — which `set -uo pipefail` does NOT abort on, so the
  # predicate silently degraded to grepping the unstripped file.
  if sed -E 's~^[[:space:]]*(#|//).*$~~' "$1" | grep -Eq 'ignore_changes[[:space:]]*='; then
    echo 0
  else
    echo 1
  fi
}

# A11 — ADDITION-BLINDNESS BACKSTOP. Every predicate above extracts THE resource
# block it knows by name, so all of them are blind to a resource ADDED BESIDE it.
# Three attacks passed 20/20 green before this existed:
#
#   1. A SECOND doppler_secret writing WORKSPACES_LUKS_KEY to config = "prd",
#      visibility = "unmasked" — i.e. THE EXACT CWE-522 DRIFT A7 IS NAMED FOR.
#   2. length = 8 on the real passphrase + a decoy random_password with length = 40
#      (A1 is a whole-file grep, so the decoy launders the weakening).
#   3. A SECOND doppler_service_token with access = "admin".
#
# A7 only reddens on RELOCATION (sed-swapping the existing value); it never saw
# ADDITION. "A green test that cannot go red is worthless" — this file's own header,
# and the standard it failed.
#
# Cardinality is the fix: exactly one of each resource type, and the literal
# `config = "prd"` must appear nowhere. Both legs matter — cardinality alone would
# permit the single secret being MOVED to "prd", and the "prd" check alone would
# permit a decoy.
p_no_laundering_resource() {
  local f="$1"
  # The key must never be written to the shared prd config, whatever the block is called.
  if grep -Eq '^[[:space:]]*config[[:space:]]*=[[:space:]]*"prd"[[:space:]]*$' "$f"; then echo 0; return; fi
  [ "$(grep -Ec '^resource "doppler_secret"' "$f")" = "1" ] || { echo 0; return; }
  [ "$(grep -Ec '^resource "doppler_service_token"' "$f")" = "1" ] || { echo 0; return; }
  [ "$(grep -Ec '^resource "random_password"' "$f")" = "1" ] || { echo 0; return; }
  [ "$(grep -Ec '^resource "hcloud_volume"' "$f")" = "1" ] || { echo 0; return; }
  echo 1
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
assert_mutation "A1 (block absent)" p_tf_random "$TF" 's/^resource "random_password" "workspaces_luks"/resource "random_password" "other"/'
# Exercise the `length` CONJUNCT. The rename mutation above exits at the block-absent
# guard and never reaches it, so the length check's logic was untested — a typo in
# that regex would have shipped green.
assert_mutation "A1 (weakened length — the conjunct)" p_tf_random "$TF" 's/^([[:space:]]*)length([[:space:]]*)=([[:space:]]*)40[[:space:]]*$/\1length\2=\3 12/'

assert_holds "A2 special = false (stdin-pipe-safe)" p_special_false "$TF"
assert_mutation "A2" p_special_false "$TF" 's/special([[:space:]]*)=([[:space:]]*)false/special\1=\2true/'

assert_holds "A3 doppler secret is masked" p_masked "$TF"
assert_mutation "A3" p_masked "$TF" 's/visibility([[:space:]]*)=([[:space:]]*)"masked"/visibility\1=\2"unmasked"/'

# THE acceptance criterion: a plaintext-born volume must go RED.
assert_holds "A4 volume carries NO format attribute (raw device — C7)" p_no_format "$TF"
assert_mutation_append "A4 (plaintext-birth drift)" p_no_format "$TF" '  format   = "ext4"'

assert_holds "A5 volume is a singleton, not for_each" p_singleton_volume "$TF"
assert_mutation "A5 (block absent)" p_singleton_volume "$TF" 's/^resource "hcloud_volume" "workspaces_luks"/resource "hcloud_volume" "gone"/'
# THE BRANCH A5 ACTUALLY ADVERTISES. The rename mutation above exits at the
# block-absent guard without ever reaching the for_each grep — so replacing that
# regex with one that can never match left the suite 20/20 green AND kept A5's own
# mutation passing. Half the issue's acceptance criterion had unprotected logic.
# Insert the real drift instead.
assert_mutation "A5 (for_each drift — the branch under test)" p_singleton_volume "$TF" \
  '/^resource "hcloud_volume" "workspaces_luks"/a\  for_each = var.web_hosts'

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

# A11's three mutation legs are the three attacks that passed 20/20 before it existed.
# Each appends a LAUNDERING resource rather than breaking the known-good one — the
# blind spot every name-scoped predicate above shares.
assert_holds "A11 no laundering resource added beside the known-good blocks" p_no_laundering_resource "$TF"
assert_mutation_append "A11 attack-1 (key to shared prd — the CWE-522 drift)" p_no_laundering_resource "$TF" \
  'resource "doppler_secret" "leak" { config = "prd" }'
assert_mutation_append "A11 attack-2 (decoy random_password launders a weakened key)" p_no_laundering_resource "$TF" \
  'resource "random_password" "decoy" { length = 40 }'
assert_mutation_append "A11 attack-3 (second admin service token)" p_no_laundering_resource "$TF" \
  'resource "doppler_service_token" "admin_leak" { access = "admin" }'

# --- Minimum-cardinality guard (a silent-empty harness must fail loud) ---------
# A1: 1 holds + 2 mutations. A5: 1 + 2. A11: 1 + 3. A2/A3/A4/A6/A7/A8/A9/A10: 1 + 1 each.
# 3 + 3 + 4 + (8 x 2) = 26.
total=$((passes + fails))
if [ "$total" -lt 26 ]; then
  echo "FAIL: ran only ${total} assertions (<26) — suite did not execute fully" >&2
  exit 1
fi

echo "workspaces-luks: ${passes} passed, ${fails} failed (${total} assertions)"
[ "$fails" -eq 0 ]
