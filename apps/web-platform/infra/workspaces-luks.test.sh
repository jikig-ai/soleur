#!/usr/bin/env bash
#
# Drift-guards for the LUKS-at-rest /workspaces volume (#6588, ADR-119).
#
# WHY THIS EXISTS
# ---------------
# `hcloud_volume.workspaces` holds every user's checked-out source code and is
# plaintext ext4, while the published privacy policy tells data subjects it is
# LUKS-encrypted. ADR-119 births an ADDITIVE encrypted volume rather than mutating
# the live one. These guards assert the new volume can never be born plaintext, and
# that the passphrase can never reach the agent container.
#
# The issue's acceptance criterion — "a drift guard so a future volume can't be born
# plaintext (mutation-tested: a plaintext volume must go RED)" — is A4 + A5 below.
#
# Guard B4 (#6604 step 7, ADR-119): web-1's plaintext volume is wiped and deleted, so
# server.tf must never plan it back (both workspaces for_each's exclude web-1; web-1
# renders the "retired-6604" sentinel), and the LUKS volume — now the sole copy — must
# carry delete_protection = true and prevent_destroy = true, its attachment prevent_destroy =
# true (a replace detaches it), and the root must hold no *override.tf / *.tf.json that could
# override any of these behind the HCL this suite reads.
#
# Each assertion is MUTATION-TESTED: the predicate is re-run against a deliberately
# broken copy and MUST flip to failing. A green test that cannot go red is worthless
# (the bash-gate-authoring foot-gun). Anchoring is on CONTENT, never line numbers
# (cq-cite-content-anchor-not-line-number), and on the syntactic construct rather
# than a bare token — a bare token also matches this file's own explanatory comments
# (cq-assert-anchor-not-bare-token).
#
# Run: bash apps/web-platform/infra/workspaces-luks.test.sh
# Presence under apps/web-platform/infra/ IS registration — derived and run by run-registered-suites.sh (#8736).
#
# `set -e` is deliberately ABSENT: deliberately-nonzero greps are wrapped so the
# harness never aborts mid-suite.
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF="$DIR/workspaces-luks.tf"
# Guard B4 (#6604 step 7) also reads server.tf: web-1's plaintext volume is retired there.
SERVER_TF="$DIR/server.tf"

[ -f "$TF" ] || { echo "FAIL: workspaces-luks.tf not found at $TF" >&2; exit 1; }
[ -f "$SERVER_TF" ] || { echo "FAIL: server.tf not found at $SERVER_TF" >&2; exit 1; }

passes=0
fails=0
pass() { passes=$((passes + 1)); }
fail() { fails=$((fails + 1)); echo "FAIL: $1" >&2; }

# Reporter self-test (the harness_selftest pattern, workspaces-luks-harness.sh). pass()/fail() are
# the instrument every verdict below runs through, so prove them first: one pass() must add exactly
# one pass and no fail, one fail() exactly one fail and no pass. Runs in a SUBSHELL so the real
# counters are untouched, and reports through printf + exit 2, never through fail(), the very
# function under suspicion.
suite_selftest() {
  local got
  got="$( passes=0; fails=0; pass selftest-pass; fail selftest-fail 2>/dev/null; printf '%s/%s' "$passes" "$fails" )"
  if [ "$got" != "1/1" ]; then
    printf 'INSTRUMENT FAIL - workspaces-luks.test.sh: pass()/fail() self-test got passes/fails=%s, want 1/1; every verdict below would be meaningless\n' "$got" >&2
    exit 2
  fi
}
suite_selftest

# Canonical fixture-path guard (fixture-relative-assert P1b; byte-identical to every tracked copy).
# SUITE_TMP below and Guard B4's helpers write to a mktemp path; this refuses an empty or relative one.
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

# ONE owning trap for every mutation copy below (lint-trap-tempfile-ownership rule (c)): each helper
# allocates inside SUITE_TMP and still removes its own file, but a run that dies between allocation
# and cleanup leaves nothing behind.
SUITE_TMP="$(mktemp -d "${TMPDIR:-/tmp}/wsluks-suite.XXXXXX")" || { printf 'FATAL: mktemp -d failed\n' >&2; exit 2; }
assert_fixture_dir "$SUITE_TMP"
trap 'rm -rf "$SUITE_TMP"' EXIT

# --- Helpers ------------------------------------------------------------------

# strip_comments, block_of, _b4_block_range, B4_TAIL, _b4_attr_true, _b4_prevent_destroy_of and
# p_b4_no_override_files live in the shared lexer (#9879), also sourced by
# apps/web-platform/infra/inngest-luks-sole-copy.test.sh. Resolved from the REPO ROOT, not this
# suite's own directory. Neutering strip_comments there must redden this suite (rows B4-8a/8b/8c).
REPO_ROOT="$(cd "$DIR/../../.." && pwd)"
HCL_LIB="$REPO_ROOT/tests/scripts/lib/hcl-effective-text.sh"
[ -f "$HCL_LIB" ] || { printf 'FATAL: shared HCL lexer not found at %s\n' "$HCL_LIB" >&2; exit 2; }
# shellcheck source=../../../tests/scripts/lib/hcl-effective-text.sh
. "$HCL_LIB" || { printf 'FATAL: could not source %s\n' "$HCL_LIB" >&2; exit 2; }

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
  if printf '%s' "$b" | grep -Ec '^[[:space:]]*length[[:space:]]*=[[:space:]]*40[[:space:]]*$' >/dev/null; then echo 1; else echo 0; fi
}

# A2 — `special = false` keeps the passphrase shell/stdin-safe for the
# `printf %s | cryptsetup --key-file -` pipe. A special char breaks that pipe.
# BLOCK-SCOPED — same scope-leak as A1 (a sibling random_password carrying
# `special = false` laundered a real `special = true` drift to green).
p_special_false() {
  local b
  b="$(block_of "$1" random_password workspaces_luks)"
  if [ -z "$b" ]; then echo 0; return; fi
  if printf '%s' "$b" | grep -Ec '^[[:space:]]*special[[:space:]]*=[[:space:]]*false[[:space:]]*$' >/dev/null; then echo 1; else echo 0; fi
}

# A3 — the Doppler secret is masked.
# BLOCK-SCOPED — same scope-leak as A1/A2 (a sibling doppler_secret carrying
# `visibility = "masked"` laundered a real `visibility = "unmasked"` drift to green).
p_masked() {
  local b
  b="$(block_of "$1" doppler_secret workspaces_luks_key)"
  if [ -z "$b" ]; then echo 0; return; fi
  if printf '%s' "$b" | grep -Ec '^[[:space:]]*visibility[[:space:]]*=[[:space:]]*"masked"[[:space:]]*$' >/dev/null; then echo 1; else echo 0; fi
}

# A4 — THE ISSUE'S ACCEPTANCE CRITERION. The new volume must carry NO `format`
# attribute. C7: `format = "ext4"` makes a fresh volume byte-indistinguishable from
# a plaintext source volume (both TYPE=ext4), which destroys the only sound
# luksFormat guard — "format only a device with no filesystem signature". A raw
# device makes the discriminator exist. A `format` line here IS the plaintext-birth
# drift this guard names.
p_no_format() {
  # Comment-stripped: this .tf DISCUSSES the omitted `format` at length, and a
  # `/* format = "ext4" ... */` note would otherwise false-FAIL the guard. Documenting
  # WHY a construct is absent must never redden the guard that forbids it.
  if strip_comments "$1" | grep -Ec '^[[:space:]]*format[[:space:]]*=' >/dev/null; then echo 0; else echo 1; fi
}

# A5 — the volume resource exists and is a SINGLETON, not `for_each`. C18: a
# for_each'd attachment lands outside web2_allow in
# destroy-guard-filter-web-platform.jq and permanently bricks the web-2-recreate
# path; `moved` also wants a singleton source.
p_singleton_volume() {
  local block
  block="$(block_of "$1" hcloud_volume workspaces_luks)"
  if [ -z "$block" ]; then echo 0; return; fi
  if printf '%s' "$block" | grep -Ec '^[[:space:]]*for_each[[:space:]]*=' >/dev/null; then echo 0; else echo 1; fi
}

# A6 — the attachment pins to web-1 explicitly. web-1 is the sole live origin
# (app.soleur.ai is a hard-pinned singleton A record); web-2 has never served.
p_attach_web1() {
  local block
  block="$(block_of "$1" hcloud_volume_attachment workspaces_luks)"
  if [ -z "$block" ]; then echo 0; return; fi
  if printf '%s' "$block" | grep -Ec 'hcloud_server\.web\["web-1"\]\.id' >/dev/null; then echo 1; else echo 0; fi
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
  if printf '%s' "$block" | grep -Ec '^[[:space:]]*config[[:space:]]*=[[:space:]]*"prd_workspaces_luks"' >/dev/null; then
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
# LUKS header is the terminal mode ADR-119 §(f) names.
p_token_read_only() {
  local block
  block="$(block_of "$1" doppler_service_token workspaces_luks)"
  if [ -z "$block" ]; then echo 0; return; fi
  if printf '%s' "$block" | grep -Ec '^[[:space:]]*access[[:space:]]*=[[:space:]]*"read"' >/dev/null; then echo 1; else echo 0; fi
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
  if sed -E 's~^[[:space:]]*(#|//).*$~~' "$1" | grep -Ec 'ignore_changes[[:space:]]*=' >/dev/null; then
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

# --- Guard B4 (#6604 step 7): web-1 has no plaintext volume; the sole copy cannot be destroyed ---
#
# web-1's plaintext workspaces volume (105149570) was wiped and deleted, and its two state
# addresses were forgotten. server.tf must never plan it back: both workspaces for_each's
# range over local.plaintext_workspaces_hosts (var.web_hosts minus web-1) and web-1's
# cloud-init workspaces_volume_id is the "retired-6604" sentinel. The LUKS volume is now the
# SOLE copy of every workspace, so it carries delete_protection AND prevent_destroy, and its
# attachment carries prevent_destroy (rows 9a/9b/8c).
#
# Every attribute is anchored INSIDE its block (leading whitespace, never column 0) on
# comment-stripped text, and each value check tolerates extra spacing plus a trailing
# comment (row H1), because strip_comments drops only whole-line comments.

# B4-1/2: BOTH members (the volume AND its attachment) range over the narrowed local.
# Exactly one for_each line per block, and it names local.plaintext_workspaces_hosts.
p_b4_for_each_narrowed() {
  local f="$1" t b
  for t in hcloud_volume hcloud_volume_attachment; do
    b="$(block_of "$f" "$t" workspaces)"
    if [ -z "$b" ]; then echo 0; return; fi
    [ "$(printf '%s\n' "$b" | grep -Ec '^[[:space:]]+for_each[[:space:]]*=')" = "1" ] || { echo 0; return; }
    grep -Eq "^[[:space:]]+for_each[[:space:]]*=[[:space:]]*local\.plaintext_workspaces_hosts${B4_TAIL}" <<<"$b" \
      || { echo 0; return; }
  done
  echo 1
}

# B4-3: the local exists exactly once and filters out web-1 (not some other host).
p_b4_local_excludes_web1() {
  local code
  code="$(strip_comments "$1")"
  [ "$(printf '%s\n' "$code" | grep -Ec '^[[:space:]]+plaintext_workspaces_hosts[[:space:]]*=')" = "1" ] || { echo 0; return; }
  if grep -Eq "^[[:space:]]+plaintext_workspaces_hosts[[:space:]]*=[[:space:]]*\{[[:space:]]*for[[:space:]]+k[[:space:]]*,[[:space:]]*v[[:space:]]+in[[:space:]]+var\.web_hosts[[:space:]]*:[[:space:]]*k[[:space:]]*=>[[:space:]]*v[[:space:]]+if[[:space:]]+k[[:space:]]*!=[[:space:]]*\"web-1\"[[:space:]]*\}${B4_TAIL}" <<<"$code"; then
    echo 1
  else
    echo 0
  fi
}

# B4-4: hcloud_server.web's templatefile argument gives web-1 the "retired-6604" sentinel
# (never an index into the narrowed map, which would be a plan error for web-1).
p_b4_sentinel() {
  local b
  b="$(block_of "$1" hcloud_server web)"
  if [ -z "$b" ]; then echo 0; return; fi
  [ "$(printf '%s\n' "$b" | grep -Ec '^[[:space:]]+workspaces_volume_id[[:space:]]*=')" = "1" ] || { echo 0; return; }
  if grep -Eq "^[[:space:]]+workspaces_volume_id[[:space:]]*=[[:space:]]*contains\(keys\(local\.plaintext_workspaces_hosts\),[[:space:]]*each\.key\)[[:space:]]*\?[[:space:]]*hcloud_volume\.workspaces\[each\.key\]\.id[[:space:]]*:[[:space:]]*\"retired-6604\"${B4_TAIL}" <<<"$b"; then
    echo 1
  else
    echo 0
  fi
}

p_b4_prevent_destroy() { _b4_prevent_destroy_of "$1" hcloud_volume workspaces_luks; }
p_b4_delete_protection() { _b4_attr_true "$1" hcloud_volume workspaces_luks delete_protection; }
# B4-9: the ATTACHMENT carries prevent_destroy too. Its server_id and volume_id are both ForceNew,
# so any replace of it (a web-1 server replace, a volume address that fell out of state, a re-pointed
# server_id) DETACHES the sole copy from web-1. delete_protection does not stop a detach.
p_b4_attach_prevent_destroy() { _b4_prevent_destroy_of "$1" hcloud_volume_attachment workspaces_luks; }

# --- Harness ------------------------------------------------------------------

assert_holds() {
  local name="$1" fn="$2" file="$3" got
  got="$($fn "$file")"
  if [ "$got" = "1" ]; then pass; else fail "$name: property does not hold on the real file"; fi
}

assert_mutation() {
  local name="$1" fn="$2" file="$3" sed_expr="$4" tmp got
  tmp="$(mktemp "$SUITE_TMP/wsluks-mut.XXXXXX")"
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
  tmp="$(mktemp "$SUITE_TMP/wsluks-mut.XXXXXX")"
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

# Guard B4 mutation: like assert_mutation, but a sed that matched nothing is a FAIL (a vacuous
# mutation proves nothing), and with a scope (type name) every changed line must sit inside that
# resource block — so the "second member" row really mutates only the attachment.
assert_b4_mutation() {
  local name="$1" fn="$2" file="$3" sed_expr="$4" stype="${5:-}" sname="${6:-}" tmp got range changed
  tmp="$(mktemp "$SUITE_TMP/wsluks-b4.XXXXXX")"
  assert_fixture_dir "$tmp"
  sed -E "$sed_expr" "$file" > "$tmp"
  if cmp -s "$file" "$tmp"; then
    fail "$name: mutation sed changed nothing (vacuous row)"; rm -f "$tmp"; return
  fi
  if [ -n "$stype" ]; then
    range="$(_b4_block_range "$file" "$stype" "$sname")"
    changed="$(awk 'NR==FNR { a[FNR] = $0; n = FNR; next } { if (a[FNR] != $0) print FNR } END { if (FNR != n) print "count" }' "$file" "$tmp")"
    if [ -z "$range" ] || printf '%s\n' "$changed" | awk -v r="$range" '
        BEGIN { split(r, x, " ") } $0 == "count" || $0 + 0 < x[1] || $0 + 0 > x[2] { bad = 1 } END { exit !bad }'; then
      fail "$name: mutation was not confined to resource \"$stype\" \"$sname\""; rm -f "$tmp"; return
    fi
  fi
  got="$($fn "$tmp")"
  if [ "$got" = "0" ]; then
    pass
  else
    fail "$name: MUTATION did not flip the check to failing (predicate still passed on a broken copy)"
  fi
  rm -f "$tmp"
}

# Guard B4 must-PASS row: a cosmetic rewrite (extra spacing, trailing comment) must stay green.
# The rewrite itself must apply, or the row is vacuous.
assert_b4_holds_variant() {
  local name="$1" fn="$2" file="$3" sed_expr="$4" tmp got
  tmp="$(mktemp "$SUITE_TMP/wsluks-b4.XXXXXX")"
  assert_fixture_dir "$tmp"
  sed -E "$sed_expr" "$file" > "$tmp"
  if cmp -s "$file" "$tmp"; then
    fail "$name: cosmetic sed changed nothing (vacuous row)"; rm -f "$tmp"; return
  fi
  got="$($fn "$tmp")"
  if [ "$got" = "1" ]; then pass; else fail "$name: a cosmetic rewrite (spacing / trailing comment) false-REDDENED the check"; fi
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

# --- Guard B4 rows (#6604 step 7) ---------------------------------------------
# Numbering follows the plan's Guard B4 mutation matrix (1-7 RED, H1 must-PASS).
assert_holds "B4 both workspaces for_each's range over local.plaintext_workspaces_hosts" p_b4_for_each_narrowed "$SERVER_TF"
assert_b4_mutation "B4-1 (volume for_each reverted to var.web_hosts)" p_b4_for_each_narrowed "$SERVER_TF" \
  '/^resource "hcloud_volume" "workspaces"/,/^}/ s/(for_each[[:space:]]*=[[:space:]]*)local\.plaintext_workspaces_hosts/\1var.web_hosts/' \
  hcloud_volume workspaces
# The SECOND member: the volume stays compliant and the diff is confined to the attachment
# block, so a predicate that checked only the first block cannot pass this row.
assert_b4_mutation "B4-2 (attachment-only for_each reverted; volume compliant)" p_b4_for_each_narrowed "$SERVER_TF" \
  '/^resource "hcloud_volume_attachment" "workspaces"/,/^}/ s/(for_each[[:space:]]*=[[:space:]]*)local\.plaintext_workspaces_hosts/\1var.web_hosts/' \
  hcloud_volume_attachment workspaces
assert_b4_mutation "B4-7a (volume block absent)" p_b4_for_each_narrowed "$SERVER_TF" \
  's/^resource "hcloud_volume" "workspaces"/resource "hcloud_volume" "gone"/'
assert_b4_mutation "B4-7b (attachment block absent)" p_b4_for_each_narrowed "$SERVER_TF" \
  's/^resource "hcloud_volume_attachment" "workspaces"/resource "hcloud_volume_attachment" "gone"/'

assert_holds "B4 local.plaintext_workspaces_hosts excludes web-1" p_b4_local_excludes_web1 "$SERVER_TF"
assert_b4_mutation "B4-3 (local filters web-2 instead of web-1)" p_b4_local_excludes_web1 "$SERVER_TF" \
  '/^[[:space:]]+plaintext_workspaces_hosts[[:space:]]*=/ s/(k[[:space:]]*!=[[:space:]]*)"web-1"/\1"web-2"/'
assert_b4_mutation "B4-7c (local absent)" p_b4_local_excludes_web1 "$SERVER_TF" \
  's/^([[:space:]]+)plaintext_workspaces_hosts([[:space:]]*=)/\1other_hosts\2/'

assert_holds "B4 web-1 workspaces_volume_id is the retired-6604 sentinel" p_b4_sentinel "$SERVER_TF"
assert_b4_mutation "B4-4 (sentinel reverted to a bare index)" p_b4_sentinel "$SERVER_TF" \
  's/^([[:space:]]+workspaces_volume_id[[:space:]]*=[[:space:]]*).*$/\1hcloud_volume.workspaces[each.key].id/' \
  hcloud_server web
assert_b4_mutation "B4-7d (hcloud_server.web block absent)" p_b4_sentinel "$SERVER_TF" \
  's/^resource "hcloud_server" "web"/resource "hcloud_server" "gone"/'

assert_holds "B4 workspaces_luks carries lifecycle prevent_destroy = true" p_b4_prevent_destroy "$TF"
assert_b4_mutation "B4-5 (prevent_destroy = false: token present, property false)" p_b4_prevent_destroy "$TF" \
  '/^resource "hcloud_volume" "workspaces_luks"/,/^}/ s/(prevent_destroy[[:space:]]*=[[:space:]]*)true/\1false/' \
  hcloud_volume workspaces_luks
assert_b4_mutation "B4-7e (workspaces_luks block absent — prevent_destroy)" p_b4_prevent_destroy "$TF" \
  's/^resource "hcloud_volume" "workspaces_luks"/resource "hcloud_volume" "gone"/'

assert_holds "B4 workspaces_luks carries delete_protection = true" p_b4_delete_protection "$TF"
assert_b4_mutation "B4-6 (delete_protection = false)" p_b4_delete_protection "$TF" \
  '/^resource "hcloud_volume" "workspaces_luks"/,/^}/ s/(delete_protection[[:space:]]*=[[:space:]]*)true/\1false/' \
  hcloud_volume workspaces_luks
assert_b4_mutation "B4-7f (workspaces_luks block absent — delete_protection)" p_b4_delete_protection "$TF" \
  's/^resource "hcloud_volume" "workspaces_luks"/resource "hcloud_volume" "gone"/'

# H1 must-PASS: the same lines with extra spacing and a trailing comment stay green.
B4_H1_SERVER='s/^([[:space:]]+for_each)[[:space:]]*=[[:space:]]*(local\.plaintext_workspaces_hosts)[[:space:]]*$/\1   =   \2   # H1 note/'
B4_H1_SERVER="$B4_H1_SERVER"';s/^([[:space:]]+plaintext_workspaces_hosts)[[:space:]]*=[[:space:]]*(.*[^[:space:]])[[:space:]]*$/\1   =   \2  # H1 note/'
B4_H1_SERVER="$B4_H1_SERVER"';s/^([[:space:]]+workspaces_volume_id)[[:space:]]*=[[:space:]]*(.*[^[:space:]])[[:space:]]*$/\1  =   \2 # H1 note/'
B4_H1_LUKS='s/^([[:space:]]+(prevent_destroy|delete_protection))[[:space:]]*=[[:space:]]*true.*$/\1   =   true   # H1 note/'
assert_b4_holds_variant "B4-H1 for_each (spacing + trailing comment)" p_b4_for_each_narrowed "$SERVER_TF" "$B4_H1_SERVER"
assert_b4_holds_variant "B4-H1 local (spacing + trailing comment)" p_b4_local_excludes_web1 "$SERVER_TF" "$B4_H1_SERVER"
assert_b4_holds_variant "B4-H1 sentinel (spacing + trailing comment)" p_b4_sentinel "$SERVER_TF" "$B4_H1_SERVER"
assert_b4_holds_variant "B4-H1 prevent_destroy (spacing + trailing comment)" p_b4_prevent_destroy "$TF" "$B4_H1_LUKS"
assert_b4_holds_variant "B4-H1 delete_protection (spacing + trailing comment)" p_b4_delete_protection "$TF" "$B4_H1_LUKS"

# B4-9: the attachment's own prevent_destroy (see p_b4_attach_prevent_destroy).
assert_holds "B4 workspaces_luks ATTACHMENT carries lifecycle prevent_destroy = true" p_b4_attach_prevent_destroy "$TF"
assert_b4_mutation "B4-9a (attachment prevent_destroy = false)" p_b4_attach_prevent_destroy "$TF" \
  '/^resource "hcloud_volume_attachment" "workspaces_luks"/,/^}/ s/(prevent_destroy[[:space:]]*=[[:space:]]*)true/\1false/' \
  hcloud_volume_attachment workspaces_luks
assert_b4_mutation "B4-9b (attachment block absent)" p_b4_attach_prevent_destroy "$TF" \
  's/^resource "hcloud_volume_attachment" "workspaces_luks"/resource "hcloud_volume_attachment" "gone"/'
assert_b4_holds_variant "B4-H1 attachment prevent_destroy (spacing + trailing comment)" p_b4_attach_prevent_destroy "$TF" "$B4_H1_LUKS"

# B4-8: the protections wrapped in a MULTI-LINE /* */ comment. terraform validate honours it, so
# this is a real, fmt-clean way to drop them. Each sed keeps the line count (the opener and closer
# take the blank line beside the guarded lines), so the confinement check still applies.
# B4-8a: `/*` on the blank line above delete_protection, `*/` on the blank line below it.
assert_b4_mutation "B4-8a (delete_protection wrapped in a multi-line /* */)" p_b4_delete_protection "$TF" \
  '/^resource "hcloud_volume" "workspaces_luks"/,/^}/ { /^$/ { N; /\n[[:space:]]+delete_protection[[:space:]]*=[[:space:]]*true$/ { N; s/^\n/  \/*\n/; s/\n$/\n  *\// } } }' \
  hcloud_volume workspaces_luks
# B4-8b/8c: `/*` on the blank line above `lifecycle {`, `*/` after the lifecycle block's `}`.
B4_ML_LIFECYCLE='{ /^$/ { N; /\n[[:space:]]+lifecycle[[:space:]]*\{$/ { N; N; s/^\n/  \/*\n/; s/\n([[:space:]]+\})$/\n\1 *\// } } }'
assert_b4_mutation "B4-8b (volume lifecycle block wrapped in a multi-line /* */)" p_b4_prevent_destroy "$TF" \
  '/^resource "hcloud_volume" "workspaces_luks"/,/^}/ '"$B4_ML_LIFECYCLE" \
  hcloud_volume workspaces_luks
assert_b4_mutation "B4-8c (attachment lifecycle block wrapped in a multi-line /* */)" p_b4_attach_prevent_destroy "$TF" \
  '/^resource "hcloud_volume_attachment" "workspaces_luks"/,/^}/ '"$B4_ML_LIFECYCLE" \
  hcloud_volume_attachment workspaces_luks
# H2 must-PASS: a multi-line comment that CLOSES before the guarded lines, plus a string holding
# `/*`, must not eat them (a comment stripper that over-strips false-REDs the real file).
B4_H2='s~^(resource "hcloud_volume(_attachment)?" "workspaces_luks" \{)$~\1\n  /* H2 note: a multi-line comment\n     that closes before the guarded lines */\n  h2_note = "glob /mnt/*"~'
assert_b4_holds_variant "B4-H2 prevent_destroy (multi-line comment + /* in a string)" p_b4_prevent_destroy "$TF" "$B4_H2"
assert_b4_holds_variant "B4-H2 delete_protection (multi-line comment + /* in a string)" p_b4_delete_protection "$TF" "$B4_H2"
assert_b4_holds_variant "B4-H2 attachment prevent_destroy (multi-line comment + /* in a string)" p_b4_attach_prevent_destroy "$TF" "$B4_H2"

# B4-10: no override / JSON config in the root. The mutation copies the root's *.tf into a scratch
# dir, requires the predicate to HOLD there first (else the row is vacuous), then plants one file.
assert_b4_dir_mutation() {
  local name="$1" fn="$2" plant="$3" d got
  d="$(mktemp -d "$SUITE_TMP/wsluks-root.XXXXXX")"
  assert_fixture_dir "$d"
  cp "$DIR"/*.tf "$d"/
  if [ "$($fn "$d")" != "1" ]; then fail "$name: the unplanted copy already fails (vacuous row)"; rm -rf "$d"; return; fi
  printf '%s\n' '# planted by workspaces-luks.test.sh' > "$d/$plant"
  got="$($fn "$d")"
  if [ "$got" = "0" ]; then pass; else fail "$name: MUTATION (planted $plant) did not flip the check to failing"; fi
  rm -rf "$d"
}
assert_holds "B4 no *override.tf / *.tf.json in apps/web-platform/infra" p_b4_no_override_files "$DIR"
assert_b4_dir_mutation "B4-10a (zz_override.tf planted)" p_b4_no_override_files zz_override.tf
assert_b4_dir_mutation "B4-10b (extra.tf.json planted)" p_b4_no_override_files extra.tf.json

# --- Minimum-cardinality guard (a silent-empty harness must fail loud) ---------
# Reported by printf + exit 1, NEVER through fail(): a neutered fail() must not silence the floor.
# A1: 1 holds + 2 mutations. A5: 1 + 2. A11: 1 + 3. A2/A3/A4/A6/A7/A8/A9/A10: 1 + 1 each.
# 3 + 3 + 4 + (8 x 2) = 26.
# Guard B4: for_each 1 + 4, local 1 + 2, sentinel 1 + 2, prevent_destroy 1 + 2,
# delete_protection 1 + 2, H1 5 → 5 + 3 + 3 + 3 + 3 + 5 = 22.
# Guard B4 (review fix-forward): attachment 1 + 2 + H1 1 = 4, multi-line 8a/8b/8c 3, H2 3,
# override 1 + 2 = 3 → 13. 26 + 22 + 13 = 61.
total=$((passes + fails))
if [ "$total" -lt 61 ]; then
  printf 'FAIL: ran only %s assertions (<61) — suite did not execute fully\n' "$total" >&2
  exit 1
fi

echo "workspaces-luks: ${passes} passed, ${fails} failed (${total} assertions)"
[ "$fails" -eq 0 ]
