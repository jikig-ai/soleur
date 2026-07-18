#!/usr/bin/env bash
#
# Drift-guards for the /workspaces LUKS header-escrow wiring (#6649, part of #6604 / ADR-119).
#
# WHY THIS EXISTS
# ---------------
# The freeze (workspaces-cutover.sh) uploads the LUKS header off-host to an R2 bucket DISTINCT
# from the tfstate bucket (C4 — "the LUKS header is an independent terminal limb"). This guards
# the WIRING that makes that escrow real and safe:
#   - the bucket is provisioned + distinct from soleur-terraform-state (by REFERENCE, not literal);
#   - the R2 creds reach web-1 ONLY via the pinned prd_workspaces_luks Doppler read — never on the
#     sudo argv, never in the workflow env, never via doppler run/download (CWE-522);
#   - both aws calls target R2 (--endpoint-url), not real AWS;
#   - the DRY_RUN-safe probe runs OUTSIDE the `DRY_RUN != 1` gate (so a green dry-run can't hide an
#     unusable escrow — the false-green this issue fixes);
#   - the empty-cred path fails loud (emit_drift + die) instead of a mid-freeze SigV4 error.
#
# Escrow resources live in workspaces-luks-header.tf, NOT workspaces-luks.tf, because that file's
# A11 guard asserts file-scoped exact cardinality; this file carries the parallel addition-blind
# guard for the escrow file.
#
# Each assertion is MUTATION-TESTED: the predicate is re-run against a deliberately broken copy and
# MUST flip to failing. Anchoring is on the syntactic construct, never a bare token that this file's
# own prose also contains (cq-assert-anchor-not-bare-token).
#
# Run: bash apps/web-platform/infra/workspaces-luks-header.test.sh
# Registered as a step in .github/workflows/infra-validation.yml.
#
# `set -e` is deliberately ABSENT: deliberately-nonzero greps are wrapped so the harness never
# aborts mid-suite.
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$DIR/../../.." && pwd)"
TF="$DIR/workspaces-luks-header.tf"
SH="$DIR/workspaces-cutover.sh"
YML="$REPO/.github/workflows/workspaces-luks-cutover.yml"

for f in "$TF" "$SH" "$YML"; do
  [ -f "$f" ] || { echo "FAIL: required file not found: $f" >&2; exit 1; }
done

passes=0
fails=0
pass() { passes=$((passes + 1)); }
fail() { fails=$((fails + 1)); echo "FAIL: $1" >&2; }

# --- Helpers (mirrors workspaces-luks.test.sh) --------------------------------

strip_comments() {
  sed -E -e 's~/\*.*\*/~~g' -e 's~^[[:space:]]*(#|//).*$~~' "$1"
}

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

# H1 — the bucket exists and its name literal is soleur-workspaces-luks-header, which is NOT the
# tfstate bucket. (Distinctness at the source; the runtime :185 compare is the second layer.)
p_bucket_distinct() {
  local b; b="$(block_of "$1" cloudflare_r2_bucket workspaces_luks_header)"
  [ -n "$b" ] || { echo 0; return; }
  printf '%s' "$b" | grep -Eq '^[[:space:]]*name[[:space:]]*=[[:space:]]*"soleur-workspaces-luks-header"[[:space:]]*$' || { echo 0; return; }
  # must NOT name the tfstate bucket anywhere in the block
  printf '%s' "$b" | grep -Eq '"soleur-terraform-state"' && { echo 0; return; }
  echo 1
}

# H2 — WORKSPACES_HEADER_BUCKET's value is a REFERENCE to the bucket resource, never a string
# literal (spec-flow F9: at PR time nothing "resolves" — assert the argument FORM).
p_bucket_is_reference() {
  local b; b="$(block_of "$1" doppler_secret workspaces_luks_header_bucket)"
  [ -n "$b" ] || { echo 0; return; }
  printf '%s' "$b" | grep -Eq '^[[:space:]]*value[[:space:]]*=[[:space:]]*cloudflare_r2_bucket\.workspaces_luks_header\.name[[:space:]]*$' && echo 1 || echo 0
}

# H3 — addition-blind guard on the escrow file: no `config = "prd"` (end-anchored — a naive
# grep would false-match "prd_workspaces_luks"); exactly 2 escrow doppler_secrets, both masked.
p_no_prd_and_masked() {
  local f="$1"
  grep -Eq '^[[:space:]]*config[[:space:]]*=[[:space:]]*"prd"[[:space:]]*$' "$f" && { echo 0; return; }
  [ "$(strip_comments "$f" | grep -Ec '^resource "doppler_secret"')" = "2" ] || { echo 0; return; }
  # every doppler_secret block must be masked: count masked == count of doppler_secret
  [ "$(strip_comments "$f" | grep -Ec '^[[:space:]]*visibility[[:space:]]*=[[:space:]]*"masked"[[:space:]]*$')" = "2" ] || { echo 0; return; }
  echo 1
}

# H4 — the script reads bucket + all 3 R2 creds via the pinned scoped-config form.
p_script_reads_pinned() {
  local f="$1" name
  for name in WORKSPACES_HEADER_BUCKET WORKSPACES_HEADER_R2_ACCESS_KEY_ID WORKSPACES_HEADER_R2_SECRET_ACCESS_KEY WORKSPACES_HEADER_R2_ENDPOINT; do
    grep -Eq "doppler secrets get ${name} --plain --config prd_workspaces_luks" "$f" || { echo 0; return; }
  done
  echo 1
}

# H5 — the script NEVER uses doppler run / secrets download (the CWE-522 hole).
p_no_doppler_run() {
  strip_comments "$1" | grep -Eq 'doppler (run|secrets download)' && echo 0 || echo 1
}

# H6 — both R2-targeting aws invocations carry --endpoint-url (else they hit real AWS S3, not R2).
p_endpoint_on_aws() {
  local f="$1" bad
  bad="$(strip_comments "$f" | grep -E 'aws s3(api)? ' | grep -vcE '\-\-endpoint-url' || true)"
  [ "$bad" = "0" ] && echo 1 || echo 0
}

# H7 — the escrow creds NEVER appear on the workflow's sudo argv NOR in the workflow env.
p_creds_not_in_workflow() {
  strip_comments "$1" | grep -Eq 'AWS_ACCESS_KEY_ID|AWS_SECRET_ACCESS_KEY|WORKSPACES_HEADER_R2_(ACCESS|SECRET)_|WORKSPACES_HEADER_BUCKET' && echo 0 || echo 1
}

# --- Harness (mirrors workspaces-luks.test.sh) --------------------------------

assert_holds() {
  local name="$1" fn="$2" file="$3" got
  got="$($fn "$file")"
  if [ "$got" = "1" ]; then pass; else fail "$name: property does not hold on the real file"; fi
}

assert_mutation() {
  local name="$1" fn="$2" file="$3" sed_expr="$4" tmp got
  tmp="$(mktemp "${TMPDIR:-/tmp}/wsluks-hdr-mut.XXXXXX")"
  sed -E "$sed_expr" "$file" > "$tmp"
  got="$($fn "$tmp")"
  if [ "$got" = "0" ]; then pass; else fail "$name: MUTATION did not flip the check to failing"; fi
  rm -f "$tmp"
}

assert_mutation_append() {
  local name="$1" fn="$2" file="$3" line="$4" tmp got
  tmp="$(mktemp "${TMPDIR:-/tmp}/wsluks-hdr-mut.XXXXXX")"
  cp "$file" "$tmp"
  printf '%s\n' "$line" >> "$tmp"
  got="$($fn "$tmp")"
  if [ "$got" = "0" ]; then pass; else fail "$name: MUTATION (appended violating line) did not flip the check to failing"; fi
  rm -f "$tmp"
}

# --- H1..H7 assertions --------------------------------------------------------

assert_holds "H1 bucket exists + distinct from tfstate (name literal)" p_bucket_distinct "$TF"
# Test Scenario 5: bucket == tfstate mutant.
assert_mutation "H1 (bucket renamed to the tfstate bucket)" p_bucket_distinct "$TF" \
  's~"soleur-workspaces-luks-header"~"soleur-terraform-state"~'

assert_holds "H2 WORKSPACES_HEADER_BUCKET value is a resource reference" p_bucket_is_reference "$TF"
assert_mutation "H2 (reference replaced by a string literal)" p_bucket_is_reference "$TF" \
  's~value([[:space:]]*)=([[:space:]]*)cloudflare_r2_bucket\.workspaces_luks_header\.name~value\1=\2"soleur-workspaces-luks-header"~'

assert_holds "H3 no config=prd + escrow secrets masked (addition-blind)" p_no_prd_and_masked "$TF"
# Test Scenario 1: escrow file's parallel guard reddens on a config="prd" addition.
assert_mutation_append "H3 (config=prd added)" p_no_prd_and_masked "$TF" '  config = "prd"'
assert_mutation "H3 (a secret unmasked)" p_no_prd_and_masked "$TF" \
  's~visibility([[:space:]]*)=([[:space:]]*)"masked"~visibility\1=\2"unmasked"~'

assert_holds "H4 script reads bucket + 3 R2 creds via pinned config" p_script_reads_pinned "$SH"
assert_mutation "H4 (a read switched to doppler run)" p_script_reads_pinned "$SH" \
  's~doppler secrets get WORKSPACES_HEADER_BUCKET --plain~doppler run WORKSPACES_HEADER_BUCKET --plain~'

assert_holds "H5 script never uses doppler run/download" p_no_doppler_run "$SH"
# Test Scenario 3: doppler run/download mutant for an escrow read.
assert_mutation_append "H5 (doppler run added)" p_no_doppler_run "$SH" \
  'x=$(doppler run --config prd_workspaces_luks -- printf x)'

assert_holds "H6 both aws calls carry --endpoint-url" p_endpoint_on_aws "$SH"
# Test Scenario 4: missing --endpoint-url mutant.
assert_mutation "H6 (--endpoint-url stripped)" p_endpoint_on_aws "$SH" \
  's~ --endpoint-url "\$HEADER_R2_ENDPOINT"~~'

assert_holds "H7 escrow creds absent from workflow argv + env" p_creds_not_in_workflow "$YML"
# Test Scenario 2: command-line-leak mutant (a cred injected into the workflow).
assert_mutation_append "H7 (cred leaked into workflow)" p_creds_not_in_workflow "$YML" \
  '          AWS_SECRET_ACCESS_KEY: ${{ secrets.R2_SECRET }}'

# --- H8: the probe runs OUTSIDE the DRY_RUN != 1 gate (spec-flow F2) -----------
# Bespoke (not assert_mutation): the mutation is a MOVE, not a text swap. Predicate: the standalone
# `escrow_probe` call sits between the `step "escrow proof` line and the escrow `if [ "$DRY_RUN"...`
# gate. Mutation: move the call to just AFTER `then` → it becomes inert in the dry-run arm → RED.
probe_outside_gate() {  # $1 = script file
  local f="$1" step_ln probe_ln gate_ln
  step_ln="$(grep -nE '^step "escrow proof' "$f" | head -1 | cut -d: -f1)"
  [ -n "$step_ln" ] || { echo 0; return; }
  probe_ln="$(awk 'NR>'"$step_ln"' && /^escrow_probe$/ { print NR; exit }' "$f")"
  gate_ln="$(awk 'NR>'"$step_ln"' && /^if \[ "\$DRY_RUN" != "1" \]; then$/ { print NR; exit }' "$f")"
  [ -n "$probe_ln" ] && [ -n "$gate_ln" ] || { echo 0; return; }
  [ "$probe_ln" -lt "$gate_ln" ] && echo 1 || echo 0
}

got="$(probe_outside_gate "$SH")"
[ "$got" = "1" ] && pass || fail "H8: escrow_probe is not called before the DRY_RUN gate (probe would be inert in dry-run)"

# Mutation: relocate escrow_probe to just inside the gate (after `then`) → predicate must go RED.
mut="$(mktemp "${TMPDIR:-/tmp}/wsluks-hdr-mut.XXXXXX")"
awk '
  /^escrow_probe$/ && !moved_out { moved_out=1; next }              # drop the pre-gate call
  { print }
  /^if \[ "\$DRY_RUN" != "1" \]; then$/ && moved_out && !moved_in { print "escrow_probe"; moved_in=1 }
' "$SH" > "$mut"
got="$(probe_outside_gate "$mut")"
[ "$got" = "0" ] && pass || fail "H8 (probe moved inside gate): mutation did not flip the check to failing"
rm -f "$mut"

# --- Test Scenario 6: empty-cred path fails loud (stubbed aws/doppler harness) -
# Extract the readers + load_escrow_creds, stub doppler to return empty, and assert the empty-cred
# path emits header_creds_unreadable + exits non-zero (a green-cannot-stay-green predicate at PR
# time, not a post-merge hope).
readers="$(grep -E '^read_header_(bucket|key_id|secret|endpoint)\(\)' "$SH")"
loader="$(awk '/^load_escrow_creds\(\) \{/,/^\}/' "$SH")"
if [ -z "$readers" ] || [ -z "$loader" ]; then
  fail "S6: could not extract readers/load_escrow_creds from the script"
else
  s6_out="$(
    doppler() { return 1; }                 # every doppler read yields empty (via || true)
    emit_drift() { echo "DRIFT:$1"; }
    die() { echo "DIE:$*"; exit 1; }
    log() { :; }
    # shellcheck disable=SC2034  # consumed by the eval'd load_escrow_creds (distinctness compare)
    TFSTATE_BUCKET="soleur-terraform-state"
    eval "$readers"
    eval "$loader"
    load_escrow_creds
    echo "REACHED_END"          # must NOT print — die should have exited first
  )"
  s6_rc=$?
  if [ "$s6_rc" != "0" ] && printf '%s' "$s6_out" | grep -q 'DRIFT:header_creds_unreadable' \
     && ! printf '%s' "$s6_out" | grep -q 'REACHED_END'; then
    pass
  else
    fail "S6: empty-cred path did not fail loud (rc=$s6_rc out=$s6_out)"
  fi
fi

# --- Summary ------------------------------------------------------------------
echo "workspaces-luks-header.test.sh: $passes passed, $fails failed"
[ "$fails" -eq 0 ] || exit 1
