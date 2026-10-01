#!/usr/bin/env bash
#
# Drift-guards for the fresh-boot LUKS credentials (#6931, ADR-143 R3): the fresh-host read token, the
# soak marker's dedicated Doppler config, its write token and the GitHub secret carrying it
# (workspaces-luks-fresh-boot.tf).
#
# WHY A SEPARATE SUITE. workspaces-luks.test.sh A11 asserts FILE-SCOPED exact cardinality over
# workspaces-luks.tf (one doppler_service_token, `config = "prd"` nowhere), so these resources live in
# their own file and carry their own pins here — the workspaces-luks-header.test.sh precedent.
#
# Every assertion is MUTATION-TESTED: the predicate is re-run against a deliberately broken copy and
# MUST flip to failing. Anchoring is on the syntactic construct inside a brace-depth-extracted resource
# block, on comment-stripped code, never a bare token (cq-assert-anchor-not-bare-token): this file's
# subject is a set of constructs the .tf must also DISCUSS in prose (create_before_destroy above all).
#
# Run: bash apps/web-platform/infra/workspaces-luks-fresh-boot.test.sh
# Presence under apps/web-platform/infra/ IS registration (run-registered-suites.sh, ADR-252).
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# FRESH_BOOT_TF is a test seam so the RED state (file absent) can be demonstrated without editing the tree.
TF="${FRESH_BOOT_TF:-$DIR/workspaces-luks-fresh-boot.tf}"
LUKS_TF="$DIR/workspaces-luks.tf"
WF="$DIR/../../../.github/workflows/apply-web-platform-infra.yml"

[ -f "$TF" ] || { echo "FAIL: workspaces-luks-fresh-boot.tf not found at $TF" >&2; exit 1; }
[ -f "$LUKS_TF" ] || { echo "FAIL: workspaces-luks.tf not found at $LUKS_TF" >&2; exit 1; }

# One scratch dir owns every temp file this suite makes; the EXIT trap removes it however the run ends.
WLFB_SCR="$(mktemp -d "${TMPDIR:-/var/tmp}/wlfb.XXXXXXXX")"
trap 'rm -rf "${WLFB_SCR:?}"' EXIT

passes=0
fails=0
pass() { passes=$((passes + 1)); }
fail() { fails=$((fails + 1)); echo "FAIL: $1" >&2; }

strip_comments() {
  sed -E -e 's~/\*.*\*/~~g' -e 's~^[[:space:]]*(#|//).*$~~' "$1"
}

# Brace-depth extraction (an `awk /^}/` range truncates at the first column-0 `}` of a nested block).
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

# attr <block> <name> -> the value text of a top-level `name = value` line.
attr() {
  printf '%s\n' "$1" | sed -nE "s/^[[:space:]]*$2[[:space:]]*=[[:space:]]*(.*[^[:space:]])[[:space:]]*\$/\\1/p" | head -1
}

# --- Predicates: each takes a file, echoes 1 (holds) / 0 (does not hold) -------------------------

# F1 — the fresh-host token is a read token on the passphrase config, project soleur.
p_fresh_token_shape() {
  local b; b="$(block_of "$1" doppler_service_token workspaces_luks_fresh_boot)"
  [ -n "$b" ] || { echo 0; return; }
  [ "$(attr "$b" project)" = '"soleur"' ] || { echo 0; return; }
  [ "$(attr "$b" config)" = '"prd_workspaces_luks"' ] || { echo 0; return; }
  [ "$(attr "$b" access)" = '"read"' ] || { echo 0; return; }
  echo 1
}

# F2 — NO create_before_destroy on the fresh-host token. It is never co-rotated with
# doppler_service_token.workspaces_luks (whose CBD procedure reaches web-1 only): a CBD replace would
# destroy the predecessor in the same apply and leave a host holding a dead token, whose next reboot
# fails luksOpen and goes dark. Rotation of this token IS a host replacement.
p_fresh_token_no_cbd() {
  local b; b="$(block_of "$1" doppler_service_token workspaces_luks_fresh_boot)"
  [ -n "$b" ] || { echo 0; return; }
  if printf '%s\n' "$b" | grep -Eq 'create_before_destroy'; then echo 0; return; fi
  # Nothing in a lifecycle block may suppress a rename-driven replace either.
  if printf '%s\n' "$b" | grep -Eq 'ignore_changes|prevent_destroy[[:space:]]*=[[:space:]]*false'; then echo 0; return; fi
  echo 1
}

# F3 — the fresh-host token is a DIFFERENT resource and a DIFFERENT name from the web-1 boot token it must
# never share a rotation with (a shared name would also make a mis-targeted -replace ambiguous).
p_fresh_token_distinct() {
  local b l bn ln
  b="$(block_of "$1" doppler_service_token workspaces_luks_fresh_boot)"
  l="$(block_of "$LUKS_TF" doppler_service_token workspaces_luks)"
  [ -n "$b" ] && [ -n "$l" ] || { echo 0; return; }
  bn="$(attr "$b" name)"; ln="$(attr "$l" name)"
  [ -n "$bn" ] && [ "$bn" != "$ln" ] || { echo 0; return; }
  echo 1
}

# F4 — the marker config is a branch of prd named prd_workspaces_luks_marker in project soleur.
p_marker_config_shape() {
  local b; b="$(block_of "$1" doppler_config workspaces_luks_marker)"
  [ -n "$b" ] || { echo 0; return; }
  [ "$(attr "$b" project)" = '"soleur"' ] || { echo 0; return; }
  [ "$(attr "$b" environment)" = '"prd"' ] || { echo 0; return; }
  [ "$(attr "$b" name)" = '"prd_workspaces_luks_marker"' ] || { echo 0; return; }
  echo 1
}

# F5 — the marker write token is read/write on THAT config, by reference (an edge, so the config exists
# before the token), and on no other config. A write token on `prd` or on prd_workspaces_luks would be
# able to overwrite the passphrase's siblings.
p_marker_token_scope() {
  local b; b="$(block_of "$1" doppler_service_token workspaces_luks_marker_write)"
  [ -n "$b" ] || { echo 0; return; }
  [ "$(attr "$b" config)" = 'doppler_config.workspaces_luks_marker.name' ] || { echo 0; return; }
  [ "$(attr "$b" project)" = 'doppler_config.workspaces_luks_marker.project' ] || { echo 0; return; }
  [ "$(attr "$b" access)" = '"read/write"' ] || { echo 0; return; }
  echo 1
}

# F6 — the GitHub secret carries exactly the marker write token, as a repo secret, with no
# ignore_changes (a -replace rotation must propagate).
p_gh_secret_shape() {
  local b; b="$(block_of "$1" github_actions_secret doppler_token_workspaces_luks_marker)"
  [ -n "$b" ] || { echo 0; return; }
  [ "$(attr "$b" repository)" = '"soleur"' ] || { echo 0; return; }
  [ "$(attr "$b" secret_name)" = '"DOPPLER_TOKEN_WORKSPACES_LUKS_MARKER"' ] || { echo 0; return; }
  [ "$(attr "$b" plaintext_value)" = 'doppler_service_token.workspaces_luks_marker_write.key' ] || { echo 0; return; }
  if printf '%s\n' "$b" | grep -Eq 'ignore_changes'; then echo 0; return; fi
  echo 1
}

# F7 — ADDITION-BLINDNESS BACKSTOP for this file (the A11 shape): exactly the four known resources, no
# variable (hr-tf-variable-no-operator-mint-default), no `var.` reference, no write to shared `prd`.
p_no_laundering_resource() {
  local f="$1" code
  code="$(strip_comments "$f")"
  [ "$(printf '%s\n' "$code" | grep -Ec '^resource ')" = "4" ] || { echo 0; return; }
  [ "$(printf '%s\n' "$code" | grep -Ec '^resource "doppler_service_token"')" = "2" ] || { echo 0; return; }
  [ "$(printf '%s\n' "$code" | grep -Ec '^resource "doppler_config"')" = "1" ] || { echo 0; return; }
  [ "$(printf '%s\n' "$code" | grep -Ec '^resource "github_actions_secret"')" = "1" ] || { echo 0; return; }
  if printf '%s\n' "$code" | grep -Eq '^variable '; then echo 0; return; fi
  if printf '%s\n' "$code" | grep -Eq '(^|[^A-Za-z0-9_.])var\.[a-z_]'; then echo 0; return; fi
  if printf '%s\n' "$code" | grep -Eq '^[[:space:]]*config[[:space:]]*=[[:space:]]*"prd"[[:space:]]*$'; then echo 0; return; fi
  if printf '%s\n' "$code" | grep -Eq 'access[[:space:]]*=[[:space:]]*"admin"'; then echo 0; return; fi
  echo 1
}

# F8 — every new address is in the DEFAULT push-apply allow-list (so it exists in state before any web-2
# birth: a resource created inside a birth plan is an out-of-scope create to web-host-birth-gate.sh and
# aborts the birth). Scoped to the `apply` job's block, not the whole workflow: a dispatch job's -target
# does not make a resource part of the per-merge apply.
p_allow_listed() {
  local wf="$1" a job
  [ -f "$wf" ] || { echo 0; return; }
  job="$(awk '/^  [A-Za-z0-9_-]+:/ { cur = ($0 ~ /^  apply:/) } cur { print }' "$wf")"
  [ -n "$job" ] || { echo 0; return; }
  for a in doppler_service_token.workspaces_luks_fresh_boot doppler_config.workspaces_luks_marker \
           doppler_service_token.workspaces_luks_marker_write github_actions_secret.doppler_token_workspaces_luks_marker; do
    printf '%s\n' "$job" | grep -Eq -e "^[[:space:]]*-target=${a}[[:space:]\\\\]*\$" || { echo 0; return; }
  done
  echo 1
}

# --- Harness ------------------------------------------------------------------------------------

assert_holds() {
  local name="$1" fn="$2" file="$3" got
  got="$($fn "$file")"
  if [ "$got" = "1" ]; then pass; else fail "$name: property does not hold on the real file"; fi
}

assert_mutation() {
  local name="$1" fn="$2" file="$3" sed_expr="$4" tmp got
  tmp="$(mktemp "$WLFB_SCR/mut.XXXXXX")"
  sed -E "$sed_expr" "$file" > "$tmp"
  if cmp -s "$file" "$tmp"; then
    fail "$name: the mutation did not change the file (a mutation that lands nothing proves nothing)"
    rm -f "$tmp"; return
  fi
  got="$($fn "$tmp")"
  if [ "$got" = "0" ]; then pass; else fail "$name: MUTATION did not flip the check to failing"; fi
  rm -f "$tmp"
}

assert_mutation_append() {
  local name="$1" fn="$2" file="$3" line="$4" tmp got
  tmp="$(mktemp "$WLFB_SCR/mut.XXXXXX")"
  cp "$file" "$tmp"
  printf '%s\n' "$line" >> "$tmp"
  got="$($fn "$tmp")"
  if [ "$got" = "0" ]; then pass; else fail "$name: MUTATION (appended violating line) did not flip the check to failing"; fi
  rm -f "$tmp"
}

assert_holds "F1 fresh-host token is read on prd_workspaces_luks (soleur)" p_fresh_token_shape "$TF"
assert_mutation "F1 (access widened)" p_fresh_token_shape "$TF" '/"workspaces_luks_fresh_boot"/,/^}/ s/access([[:space:]]*)=([[:space:]]*)"read"/access\1=\2"read\/write"/'
assert_mutation "F1 (moved to shared prd)" p_fresh_token_shape "$TF" '/"workspaces_luks_fresh_boot"/,/^}/ s/config([[:space:]]*)=([[:space:]]*)"prd_workspaces_luks"/config\1=\2"prd"/'

assert_holds "F2 fresh-host token has NO create_before_destroy (never co-rotated with workspaces_luks)" p_fresh_token_no_cbd "$TF"
# THE mutation that matters: a lifecycle block carrying create_before_destroy added to the real resource.
assert_mutation "F2 (create_before_destroy added — the co-rotation hazard)" p_fresh_token_no_cbd "$TF" \
  '/"workspaces_luks_fresh_boot"/,/^}/ s/^([[:space:]]*)access([[:space:]]*)=([[:space:]]*)"read"/&\n\n  lifecycle {\n    create_before_destroy = true\n  }/'
assert_mutation "F2 (ignore_changes added)" p_fresh_token_no_cbd "$TF" \
  '/"workspaces_luks_fresh_boot"/,/^}/ s/^([[:space:]]*)access([[:space:]]*)=([[:space:]]*)"read"/&\n\n  lifecycle {\n    ignore_changes = [name]\n  }/'

assert_holds "F3 fresh-host token name differs from the web-1 boot token" p_fresh_token_distinct "$TF"
assert_mutation "F3 (name collides with workspaces_luks)" p_fresh_token_distinct "$TF" \
  "/\"workspaces_luks_fresh_boot\"/,/^}/ s/name([[:space:]]*)=([[:space:]]*)\"[^\"]+\"/name\\1=\\2\"$(sed -nE 's/^[[:space:]]*name[[:space:]]*=[[:space:]]*"(workspaces-luks-boot[^"]*)".*/\1/p' "$LUKS_TF" | head -1)\"/"

assert_holds "F4 marker config is prd_workspaces_luks_marker (branch of prd, soleur)" p_marker_config_shape "$TF"
assert_mutation "F4 (wrong config name)" p_marker_config_shape "$TF" 's/name([[:space:]]*)=([[:space:]]*)"prd_workspaces_luks_marker"/name\1=\2"prd_workspaces_luks"/'
assert_mutation "F4 (wrong environment)" p_marker_config_shape "$TF" 's/environment([[:space:]]*)=([[:space:]]*)"prd"/environment\1=\2"dev"/'

assert_holds "F5 marker write token is read/write on the marker config ONLY, by reference" p_marker_token_scope "$TF"
assert_mutation "F5 (write token moved to the passphrase config)" p_marker_token_scope "$TF" \
  's/config([[:space:]]*)=([[:space:]]*)doppler_config\.workspaces_luks_marker\.name/config\1=\2"prd_workspaces_luks"/'
assert_mutation "F5 (write token moved to shared prd)" p_marker_token_scope "$TF" \
  's/config([[:space:]]*)=([[:space:]]*)doppler_config\.workspaces_luks_marker\.name/config\1=\2"prd"/'
assert_mutation "F5 (access narrowed — the verify leg could no longer write)" p_marker_token_scope "$TF" \
  's/access([[:space:]]*)=([[:space:]]*)"read\/write"/access\1=\2"read"/'

assert_holds "F6 GitHub secret carries exactly the marker write token (repo secret, rotation propagates)" p_gh_secret_shape "$TF"
assert_mutation "F6 (publishes the passphrase-config token instead)" p_gh_secret_shape "$TF" \
  's/plaintext_value([[:space:]]*)=([[:space:]]*)doppler_service_token\.workspaces_luks_marker_write\.key/plaintext_value\1=\2doppler_service_token.workspaces_luks_fresh_boot.key/'
assert_mutation_append "F6 (ignore_changes appended inside the secret)" p_gh_secret_shape "$TF" \
  'resource "github_actions_secret" "doppler_token_workspaces_luks_marker" { lifecycle { ignore_changes = [plaintext_value] } }'

assert_holds "F7 exactly the four known resources, no variable, no var., no write to shared prd" p_no_laundering_resource "$TF"
assert_mutation_append "F7 attack-1 (a fifth resource: a secret written to shared prd)" p_no_laundering_resource "$TF" \
  'resource "doppler_secret" "leak" { config = "prd" }'
assert_mutation_append "F7 attack-2 (an operator-supplied variable)" p_no_laundering_resource "$TF" \
  'variable "luks_marker_token" {}'
assert_mutation_append "F7 attack-3 (a third, admin service token)" p_no_laundering_resource "$TF" \
  'resource "doppler_service_token" "admin_leak" { access = "admin" }'
assert_mutation "F7 attack-4 (a var. reference smuggled into a value)" p_no_laundering_resource "$TF" \
  's/^([[:space:]]*)repository([[:space:]]*)=([[:space:]]*)"soleur"/\1repository\2=\3var.repo/'

assert_holds "F8 the four addresses are in the DEFAULT push-apply -target allow-list" p_allow_listed "$WF"
for addr in doppler_service_token.workspaces_luks_fresh_boot doppler_config.workspaces_luks_marker \
            doppler_service_token.workspaces_luks_marker_write github_actions_secret.doppler_token_workspaces_luks_marker; do
  assert_mutation "F8 (-target=$addr dropped)" p_allow_listed "$WF" "/^[[:space:]]*-target=${addr}[[:space:]\\\\]*\$/d"
done

# --- Minimum-cardinality guard (a silent-empty harness must fail loud) ---------------------------
# F1 1+2, F2 1+2, F3 1+1, F4 1+2, F5 1+3, F6 1+2, F7 1+4, F8 1+4.
# 3 + 3 + 2 + 3 + 4 + 3 + 5 + 5 = 28.
total=$((passes + fails))
if [ "$total" -lt 28 ]; then
  echo "FAIL: ran only ${total} assertions (<28) — suite did not execute fully" >&2
  exit 1
fi

echo "workspaces-luks-fresh-boot: ${passes} passed, ${fails} failed (${total} assertions)"
[ "$fails" -eq 0 ]
