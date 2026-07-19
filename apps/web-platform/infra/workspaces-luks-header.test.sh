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
# #6649 — the escrow rehearsal autonomy + content-carrier delivery spans more files:
YML_VERIFY="$REPO/.github/workflows/workspaces-luks-verify.yml"
TF_MAIN="$DIR/workspaces-luks.tf"
SVC="$DIR/luks-monitor.service"

for f in "$TF" "$SH" "$YML" "$YML_VERIFY" "$TF_MAIN" "$SVC"; do
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
  grep -Eq '^[[:space:]]*name[[:space:]]*=[[:space:]]*"soleur-workspaces-luks-header"[[:space:]]*$' <<<"$b" || { echo 0; return; }
  # must NOT name the tfstate bucket anywhere in the block
  grep -Eq '"soleur-terraform-state"' <<<"$b" && { echo 0; return; }
  echo 1
}

# H2 — WORKSPACES_HEADER_BUCKET's value is a REFERENCE to the bucket resource, never a string
# literal (spec-flow F9: at PR time nothing "resolves" — assert the argument FORM).
p_bucket_is_reference() {
  local b; b="$(block_of "$1" doppler_secret workspaces_luks_header_bucket)"
  [ -n "$b" ] || { echo 0; return; }
  grep -Eq '^[[:space:]]*value[[:space:]]*=[[:space:]]*cloudflare_r2_bucket\.workspaces_luks_header\.name[[:space:]]*$' <<<"$b" && echo 1 || echo 0
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

# H4 — the script reads bucket + all 3 R2 creds via the pinned scoped-config form. strip_comments
# first so a pinned-form string surviving only in a COMMENT cannot satisfy the check vacuously
# (cq-assert-anchor-not-bare-token).
p_script_reads_pinned() {
  local f="$1" body name
  body="$(strip_comments "$f")"
  for name in WORKSPACES_HEADER_BUCKET WORKSPACES_HEADER_R2_ACCESS_KEY_ID WORKSPACES_HEADER_R2_SECRET_ACCESS_KEY WORKSPACES_HEADER_R2_ENDPOINT; do
    grep -Eq "doppler secrets get ${name} --plain --config prd_workspaces_luks" <<<"$body" || { echo 0; return; }
  done
  echo 1
}

# H5 — the script NEVER uses doppler run / secrets download (the CWE-522 hole). Tolerate intervening
# global flags so `doppler --config X run …` is caught too, not just the bare `doppler run` form
# (blacklist-evasion surfaced by the test-design review).
p_no_doppler_run() {
  strip_comments "$1" | grep -Eq 'doppler[[:space:]]+([^[:space:]]+[[:space:]]+)*(run|secrets[[:space:]]+download)([[:space:]]|$)' && echo 0 || echo 1
}

# H6 — every R2-targeting aws invocation carries --endpoint-url pointed at "$HEADER_R2_ENDPOINT".
# Anchoring on the VALUE (not just the flag) closes the vacuity where `--endpoint-url
# "https://s3.amazonaws.com"` would satisfy a flag-only check while shipping the header to real AWS.
p_endpoint_on_aws() {
  local f="$1" bad
  bad="$(strip_comments "$f" | grep -E 'aws s3(api)? ' | grep -vcF -- '--endpoint-url "$HEADER_R2_ENDPOINT"' || true)"
  [ "$bad" = "0" ] && echo 1 || echo 0
}

# H7 — the escrow creds NEVER appear on the workflow's sudo argv NOR in the workflow env.
p_creds_not_in_workflow() {
  strip_comments "$1" | grep -Eq 'AWS_ACCESS_KEY_ID|AWS_SECRET_ACCESS_KEY|WORKSPACES_HEADER_R2_(ACCESS|SECRET)_|WORKSPACES_HEADER_BUCKET' && echo 0 || echo 1
}

# H9 — ensure_aws SHA256-verifies the installer BEFORE running it as root (the supply-chain gate).
# A `sha256sum -c` must exist AND precede `./aws/install` (else an unpinned root installer runs).
# strip_comments FIRST (strip blanks comment lines in place, so line numbers are preserved): a mere
# COMMENT mentioning `sha256sum -c` must not satisfy the gate (test-design review — the only predicate
# that was grepping the raw file, the exact comment-false-match class this file's header disclaims).
p_sha_pin_gated() {
  local f="$1" sha_ln inst_ln stripped
  stripped="$(strip_comments "$f")"
  sha_ln="$(grep -nE 'sha256sum -c' <<<"$stripped" | head -1 | cut -d: -f1)"
  inst_ln="$(grep -nF './aws/install' <<<"$stripped" | head -1 | cut -d: -f1)"
  [ -n "$sha_ln" ] && [ -n "$inst_ln" ] && [ "$sha_ln" -lt "$inst_ln" ] && echo 1 || echo 0
}

# H10 — escrow_probe carries the NEGATIVE over-scope leg (head-bucket against $TFSTATE_BUCKET → die
# escrow_creds_overscoped) AND the probe-PUT. This is the SOLE runtime control against an over-scoped
# token reaching the passphrase-bearing state bucket; without a guard, deleting it stays CI-green.
p_negprobe_present() {
  local f="$1" body
  body="$(strip_comments "$f")"
  grep -Eq 'head-bucket --bucket "\$TFSTATE_BUCKET"' <<<"$body" || { echo 0; return; }
  grep -q 'escrow_creds_overscoped' <<<"$body" || { echo 0; return; }
  grep -q 'escrow_probe_put_failed' <<<"$body" || { echo 0; return; }
  echo 1
}

# H11 — the script enforces bucket != tfstate at runtime (defends the HOST-READ value the TF
# reference cannot constrain). Uses grep -c (reads all input) not grep -q: under `set -o pipefail`,
# grep -q closes the pipe on the first match and SIGPIPEs the streaming `sed`, turning a real match
# into a non-zero pipe exit (a false 0).
p_script_distinct() {
  [ "$(strip_comments "$1" | grep -Ec '\[ "\$HEADER_BACKUP_BUCKET" != "\$TFSTATE_BUCKET" \]' || true)" -gt 0 ] && echo 1 || echo 0
}

# H12 — the escrow doppler_secret blocks carry the EXACT secret NAMEs the script reads. Without this,
# a drift between the TF `name = "…"` and the pinned `doppler secrets get …` read passes both H2
# (reference form) and H4 (script side) and surfaces only at runtime as an empty read → fail-loud die,
# never at PR-test time (code-quality review — replicated-literal parity).
p_secret_names() {
  local f="$1" bb eb
  bb="$(block_of "$f" doppler_secret workspaces_luks_header_bucket)"
  eb="$(block_of "$f" doppler_secret workspaces_luks_header_r2_endpoint)"
  grep -Eq '^[[:space:]]*name[[:space:]]*=[[:space:]]*"WORKSPACES_HEADER_BUCKET"[[:space:]]*$' <<<"$bb" || { echo 0; return; }
  grep -Eq '^[[:space:]]*name[[:space:]]*=[[:space:]]*"WORKSPACES_HEADER_R2_ENDPOINT"[[:space:]]*$' <<<"$eb" || { echo 0; return; }
  echo 1
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
# Evasion mutant: `run` behind an intervening global flag must still be caught (test-design review).
assert_mutation_append "H5 (doppler run behind a global flag)" p_no_doppler_run "$SH" \
  'x=$(doppler --config prd_workspaces_luks run -- printf x)'

assert_holds "H6 every aws call points --endpoint-url at \$HEADER_R2_ENDPOINT" p_endpoint_on_aws "$SH"
# Test Scenario 4: missing --endpoint-url mutant.
assert_mutation "H6 (--endpoint-url stripped)" p_endpoint_on_aws "$SH" \
  's~ --endpoint-url "\$HEADER_R2_ENDPOINT"~~'
# H6 value mutant: endpoint re-pointed at real AWS S3 (flag present, wrong target) → RED.
assert_mutation "H6 (endpoint re-pointed at real AWS)" p_endpoint_on_aws "$SH" \
  's~--endpoint-url "\$HEADER_R2_ENDPOINT"~--endpoint-url "https://s3.amazonaws.com"~'

assert_holds "H7 escrow creds absent from workflow argv + env" p_creds_not_in_workflow "$YML"
# Test Scenario 2: command-line-leak mutant (a cred injected into the workflow).
assert_mutation_append "H7 (cred leaked into workflow)" p_creds_not_in_workflow "$YML" \
  '          AWS_SECRET_ACCESS_KEY: ${{ secrets.R2_SECRET }}'

# --- H8: the probe runs OUTSIDE the DRY_RUN != 1 gate (spec-flow F2) -----------
# Bespoke (not assert_mutation): the mutation is a MOVE, not a text swap. Predicate: the standalone
# `escrow_probe` call sits between the `step "escrow proof` line and the escrow `if [ "$DRY_RUN"...`
# gate. Mutation: move the call to just AFTER `then` → it becomes inert in the dry-run arm → RED.
probe_outside_gate() {  # $1 = script file
  local f="$1" step_ln gate_ln call ln
  step_ln="$(grep -nE '^step "escrow proof' "$f" | head -1 | cut -d: -f1)"
  [ -n "$step_ln" ] || { echo 0; return; }
  gate_ln="$(awk 'NR>'"$step_ln"' && /^if \[ "\$DRY_RUN" != "1" \]; then$/ { print NR; exit }' "$f")"
  [ -n "$gate_ln" ] || { echo 0; return; }
  # All three escrow-prep calls must run in BOTH arms — i.e. BEFORE the gate — or the rehearsal is
  # inert for whichever slips inside (the false-green this file exists to kill).
  for call in ensure_aws load_escrow_creds escrow_probe; do
    ln="$(awk 'NR>'"$step_ln"' && $0=="'"$call"'" { print NR; exit }' "$f")"
    { [ -n "$ln" ] && [ "$ln" -lt "$gate_ln" ]; } || { echo 0; return; }
  done
  echo 1
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

# --- H9: ensure_aws SHA-pin gates the root install ----------------------------
assert_holds "H9 sha256sum -c gates ./aws/install (supply-chain)" p_sha_pin_gated "$SH"
# Mutation: delete the sha256sum verification → an unpinned root installer runs → RED.
assert_mutation "H9 (sha256 verification removed)" p_sha_pin_gated "$SH" \
  '/sha256sum -c/d'
# Mutation: delete the REAL verification AND inject a decoy COMMENT naming sha256sum -c before the
# install → a raw-file grep would false-GREEN on the comment; strip_comments must keep it RED.
assert_mutation "H9 (real removed, sha256sum -c decoy comment injected)" p_sha_pin_gated "$SH" \
  '/sha256sum -c/d; s~(\( cd "\$tmp" && unzip)~  # sha256sum -c decoy (must not satisfy the gate)\n\1~'

# --- H10: escrow_probe carries the negative over-scope leg + probe-PUT ---------
assert_holds "H10 negative over-scope probe + probe-PUT present" p_negprobe_present "$SH"
# Mutation: strip the negative head-bucket line → the sole over-scope guard vanishes → RED.
assert_mutation "H10 (negative over-scope probe removed)" p_negprobe_present "$SH" \
  '/head-bucket --bucket "\$TFSTATE_BUCKET"/d'
# Mutation: strip the probe-PUT die leg → RED.
assert_mutation "H10 (probe-PUT guard removed)" p_negprobe_present "$SH" \
  's~escrow_probe_put_failed~escrow_probe_put_ok~'

# --- H11: runtime bucket!=tfstate distinctness enforced -----------------------
assert_holds "H11 script enforces bucket != tfstate at runtime" p_script_distinct "$SH"
# Mutation: delete every runtime distinctness compare → RED.
assert_mutation "H11 (distinctness compare removed)" p_script_distinct "$SH" \
  '/\[ "\$HEADER_BACKUP_BUCKET" != "\$TFSTATE_BUCKET" \]/d'

# --- H12: escrow secret NAMEs match the script reads (parity) -----------------
assert_holds "H12 escrow secret NAMEs match the script reads" p_secret_names "$TF"
# Mutation: drift the bucket secret's name literal → the TF `name` no longer matches the read → RED.
assert_mutation "H12 (bucket secret name drifted)" p_secret_names "$TF" \
  's~name([[:space:]]*)=([[:space:]]*)"WORKSPACES_HEADER_BUCKET"~name\1=\2"WORKSPACES_HEADER_BUCKET_X"~'

# --- Test Scenario 6: empty-cred path fails loud (stubbed aws/doppler harness) -
# Extract the readers + load_escrow_creds, stub doppler to return empty, and assert the empty-cred
# path emits header_creds_unreadable + exits non-zero (a green-cannot-stay-green predicate at PR
# time, not a post-merge hope).
readers="$(grep -E '^read_header_(bucket|key_id|secret|endpoint)\(\)' "$SH")"
loader="$(awk '/^load_escrow_creds\(\) \{/,/^\}/' "$SH")"
if [ -z "$readers" ] || [ -z "$loader" ]; then
  fail "S6: could not extract readers/load_escrow_creds from the script"
else
  # run_s6 <only-empty-secret-name | ""> — a doppler stub that returns EMPTY for the named secret
  # (or all four when ""), every other secret non-empty. Proves the per-field fail-loud: a
  # HALF-populated cred pair must die on its OWN [ -n ] check, not sail through to a mid-freeze SigV4.
  run_s6() {
    local only_empty="$1"
    (
      __empty="$only_empty"
      # doppler args: `secrets get <NAME> --plain --config …` → $3 is the secret NAME.
      doppler() {
        local nm="$3"
        if [ -z "$__empty" ] || [ "$nm" = "$__empty" ]; then return 1; fi
        printf 'nonempty-%s\n' "$nm"
      }
      emit_drift() { echo "DRIFT:$1"; }
      die() { echo "DIE:$*"; exit 1; }
      log() { :; }
      # shellcheck disable=SC2034  # consumed by the eval'd load_escrow_creds (distinctness compare)
      TFSTATE_BUCKET="soleur-terraform-state"
      eval "$readers"
      eval "$loader"
      load_escrow_creds
      echo "REACHED_END"        # must NOT print — die should have exited first
    )
  }
  # "" = all empty (bucket guard fires); the three creds = half-populated (their own guard must fire).
  # The reason slug is now per-field, so S6 asserts the RIGHT field's guard fired (discriminating),
  # not merely that some cred-unreadable die happened (test-design + observability review).
  for empty in "" WORKSPACES_HEADER_R2_ACCESS_KEY_ID WORKSPACES_HEADER_R2_SECRET_ACCESS_KEY WORKSPACES_HEADER_R2_ENDPOINT; do
    s6_out="$(run_s6 "$empty")"; s6_rc=$?
    label="${empty:-all-empty}"
    case "$empty" in
      "")                                     want=header_bucket_unreadable ;;
      WORKSPACES_HEADER_R2_ACCESS_KEY_ID)     want=header_key_id_unreadable ;;
      WORKSPACES_HEADER_R2_SECRET_ACCESS_KEY) want=header_secret_unreadable ;;
      WORKSPACES_HEADER_R2_ENDPOINT)          want=header_endpoint_unreadable ;;
    esac
    if [ "$s6_rc" != "0" ] && grep -q "DRIFT:${want}" <<<"$s6_out" \
       && ! grep -q 'REACHED_END' <<<"$s6_out"; then
      pass
    else
      fail "S6[$label]: empty-cred path did not fail loud with reason=$want (rc=$s6_rc out=$s6_out)"
    fi
  done

  # --- Test Scenario 7: positive control + endpoint/cred BINDING (test-design P1) ---------------
  # All fields populated → load_escrow_creds must REACH THE END (rc 0) AND bind HEADER_R2_ENDPOINT +
  # AWS_ACCESS_KEY_ID to exactly the values READ (a sentinel), not a hardcoded URL. This kills the
  # mutation that pins only the `--endpoint-url "$HEADER_R2_ENDPOINT"` flag text (H6) while hardcoding
  # the assignment to real AWS S3. Doubles as S6's positive control (a blanket top-of-function die
  # would fail this).
  run_s7() {
    (
      doppler() { printf 'stub-%s\n' "$3"; }
      emit_drift() { echo "DRIFT:$1"; }
      die() { echo "DIE:$*"; exit 1; }
      log() { :; }
      # shellcheck disable=SC2034
      TFSTATE_BUCKET="soleur-terraform-state"
      eval "$readers"; eval "$loader"
      load_escrow_creds
      echo "END endpoint=$HEADER_R2_ENDPOINT kid=$AWS_ACCESS_KEY_ID bucket=$HEADER_BACKUP_BUCKET"
    )
  }
  s7_out="$(run_s7)"; s7_rc=$?
  if [ "$s7_rc" = "0" ] \
     && grep -q 'END endpoint=stub-WORKSPACES_HEADER_R2_ENDPOINT kid=stub-WORKSPACES_HEADER_R2_ACCESS_KEY_ID bucket=stub-WORKSPACES_HEADER_BUCKET' <<<"$s7_out" \
     && ! grep -q 'DIE:' <<<"$s7_out"; then
    pass
  else
    fail "S7: all-populated path did not reach end with creds bound to the reads (rc=$s7_rc out=$s7_out)"
  fi

  # --- Test Scenario 8: bucket == tfstate deny path exercised behaviorally (test-design P3b) ----
  # H11 only greps that the compare TEXT exists; this proves the die actually FIRES when the
  # host-read bucket equals tfstate (kills the `… || true` mutation that neuters the deny while
  # leaving the compare text intact).
  run_s8() {
    (
      doppler() { if [ "$3" = "WORKSPACES_HEADER_BUCKET" ]; then echo "soleur-terraform-state"; else printf 'stub-%s\n' "$3"; fi; }
      emit_drift() { echo "DRIFT:$1"; }
      die() { echo "DIE:$*"; exit 1; }
      log() { :; }
      TFSTATE_BUCKET="soleur-terraform-state"
      eval "$readers"; eval "$loader"
      load_escrow_creds
      echo "REACHED_END"
    )
  }
  s8_out="$(run_s8)"; s8_rc=$?
  if [ "$s8_rc" != "0" ] && grep -q 'DRIFT:header_bucket_equals_tfstate' <<<"$s8_out" \
     && ! grep -q 'REACHED_END' <<<"$s8_out"; then
    pass
  else
    fail "S8: bucket==tfstate deny path did not fire (rc=$s8_rc out=$s8_out)"
  fi
fi

# --- Test Scenario 9: escrow_probe behavioral coverage (test-design P2) --------------------------
# escrow_probe is the SOLE runtime guard against an over-scoped token reaching the passphrase bucket,
# yet H8/H10 only assert placement + token PRESENCE — every leg is defeatable by `if false`/`|| true`
# while the token survives. Extract the function, stub aws() per-leg, and assert each die actually
# fires on its condition (and the all-clean path reaches the end).
probe_fn="$(awk '/^escrow_probe\(\) \{/,/^\}/' "$SH")"
if [ -z "$probe_fn" ]; then
  fail "S9: could not extract escrow_probe from the script"
else
  run_s9() {
    local case="$1"
    (
      S9C="$case"
      aws() {
        case "$1 $2" in
          "s3 cp")             [ "$S9C" = put_fail ] && return 1 || return 0 ;;
          "s3api head-object") [ "$S9C" = readback_fail ] && return 1 || return 0 ;;
          "s3 rm")             return 0 ;;
          "s3api head-bucket")
            case "$S9C" in
              overscoped)   return 0 ;;                                                    # 200 → over-scoped
              inconclusive) echo "Could not connect to the endpoint URL: timed out" >&2; return 255 ;;  # non-auth
              *)            echo "An error occurred (403) when calling the HeadBucket operation: Forbidden" >&2; return 254 ;;
            esac ;;
        esac
      }
      emit_drift() { echo "DRIFT:$1"; }
      die() { echo "DIE:$*"; exit 1; }
      log() { echo "LOG:$*"; }
      HEADER_BACKUP_BUCKET="soleur-workspaces-luks-header"
      HEADER_R2_ENDPOINT="https://acct.r2.cloudflarestorage.com"
      # shellcheck disable=SC2034  # both consumed by the eval'd escrow_probe (negative probe + run_id)
      TFSTATE_BUCKET="soleur-terraform-state"
      # shellcheck disable=SC2034
      GITHUB_RUN_ID="s9test"
      eval "$probe_fn"
      escrow_probe
      echo "PROBE_END"
    )
  }
  for c in put_fail:escrow_probe_put_failed readback_fail:escrow_probe_readback_failed \
           overscoped:escrow_creds_overscoped inconclusive:escrow_negprobe_inconclusive; do
    cse="${c%%:*}"; want="${c##*:}"
    o="$(run_s9 "$cse")"; rc=$?
    if [ "$rc" != "0" ] && grep -q "DRIFT:${want}" <<<"$o" && ! grep -q 'PROBE_END' <<<"$o"; then
      pass
    else
      fail "S9[$cse]: escrow_probe did not die with ${want} (rc=$rc out=$o)"
    fi
  done
  # positive: every leg clean (PUT ok, read-back ok, negative probe DENIED via 403) → reaches the end.
  o="$(run_s9 ok)"; rc=$?
  if [ "$rc" = "0" ] && grep -q 'PROBE_END' <<<"$o" && ! grep -q 'DRIFT:' <<<"$o"; then
    pass
  else
    fail "S9[ok]: clean probe did not reach the end (rc=$rc out=$o)"
  fi
fi

# ==============================================================================
# #6649 — escrow rehearsal autonomy + content-carrier delivery (BLOCKER 3/4/5 + gate).
# Every predicate anchors on the syntactic construct (cq-assert-anchor-not-bare-token) and is
# mutation-tested below. strip_comments FIRST so a form surviving only in a COMMENT cannot satisfy
# a check vacuously (and a forbidden form in a comment cannot false-fail a negative check).
# ==============================================================================

# H13 — the cutover runs workspaces-cutover.sh AS A FILE from a tar-shipped bundle (content-carrier),
# with NO stdin pipe of the script body (the pre-#6649 model that left ${BASH_SOURCE[0]} unbound).
# The positive anchor requires `bash` to INVOKE the file by path (execution, not a stray `rm` mention),
# closing the bare-`bash`-reads-stdin evasion (a piped script to `bash` never names the file by path).
# The negative uses a word boundary so `bash -s` (stdin) is forbidden without false-failing an
# unrelated flag token that merely starts with `-s`.
p_file_execution() {
  local f="$1" body
  body="$(strip_comments "$f")"
  grep -q 'tar xzf - -C' <<<"$body" || { echo 0; return; }
  grep -Eq 'bash .{0,3}REMOTE_DIR/workspaces-cutover\.sh' <<<"$body" || { echo 0; return; }
  grep -Eq 'bash -s([[:space:]"'"'"']|$)' <<<"$body" && { echo 0; return; }   # forbid the stdin-pipe re-introduction
  echo 1
}

# H14 — the boot token (+ device + flags) is delivered via a mode-0600 stdin env file, NEVER as a
# `VAR=val` command-line assignment (the full-prd-capable token must not enter the host process list).
# Asserts the GOOD form EXCLUSIVELY, sudo-INDEPENDENT: the session lands `-l root` so the realistic
# next regression is a sudo-LESS `DOPPLER_TOKEN=$x bash …` argv leak, which a `sudo …`-anchored regex
# misses entirely. The ONLY permitted `<sensitive>=` occurrence is the printf placeholder `=%s` (the
# stdin .env payload); any `=` NOT immediately followed by `%` is an argv/expansion leak, with or
# without sudo, with or without an intervening `-E`/`--preserve-env`/`FOO=bar`.
p_token_via_stdin() {
  local f="$1" body
  body="$(strip_comments "$f")"
  grep -q 'install -m600 /dev/stdin' <<<"$body" || { echo 0; return; }
  grep -Eq '(DOPPLER_TOKEN|WORKSPACES_LUKS_BOOT_TOKEN)=([^%]|$)' <<<"$body" && { echo 0; return; }
  echo 1
}

# H15 — the 0600 .env is shredded on a host-local EXIT trap (covers an SSH drop; F7 discipline).
# Herestring (not a pipe): under `set -o pipefail`, `strip_comments | grep -q` SIGPIPEs the sed on an
# early match and false-reports 0 (this suite's own SIGPIPE learning).
p_env_shred_trap() {
  local body; body="$(strip_comments "$1")"
  grep -Eq 'trap .*shred -u.*EXIT' <<<"$body" && echo 1 || echo 0
}

# H16 — WORKSPACES_LUKS_DEV (the by-id device) is derived + passed to the host (BLOCKER 5).
p_luks_dev_passed() {
  local f="$1" body
  body="$(strip_comments "$f")"
  grep -q 'WORKSPACES_LUKS_DEV=%s' <<<"$body" || { echo 0; return; }
  grep -q 'scsi-0HC_Volume_' <<<"$body" || { echo 0; return; }
  echo 1
}

# H17 — the environment gate is FAIL-CLOSED: EVERY destructive mode contributes its own operand,
# and the ungated branch is the empty-string arm. RED on the inverted
# `inputs.dry_run && '' || 'X'` form (which gates ALWAYS / ungates the freeze), and RED on a gate
# keyed on dry_run ALONE — which was a live hole, since `dry_run` defaults to TRUE while the
# script force-sets DRY_RUN=0 in the ROLLBACK block, so `rollback=true` took the UNGATED branch
# and performed a real umount/close/restart (#6588).
#
# Asserted by PROPERTY, not by byte-exact literal: the exact-string pin lives in
# workspaces-luks-cutover-workflow.test.sh, which parses the YAML rather than grepping (the header
# comments in that file discuss this expression at length, so a byte-grep here would also have to
# out-guess the prose). Duplicating the literal in two files would be a replicated constant with
# no parity test — the failure class this suite exists to catch.
p_env_gate_failclosed() {
  local body gate; body="$(strip_comments "$1")"   # herestrings below — avoid the pipefail+grep -q SIGPIPE flake
  gate="$(grep -m1 -E '^[[:space:]]*environment:' <<<"$body")" || { echo 0; return; }
  # the ungated branch must be the '' arm, never the environment name
  grep -qF "|| ''" <<<"$gate" || { echo 0; return; }
  grep -qF "&& 'workspaces-luks-cutover'" <<<"$gate" || { echo 0; return; }
  # every destructive mode contributes an operand
  grep -qF '!inputs.dry_run' <<<"$gate" || { echo 0; return; }
  grep -qF 'inputs.clean_stray' <<<"$gate" || { echo 0; return; }
  grep -qF 'inputs.rollback' <<<"$gate" || { echo 0; return; }
  echo 1
}

# H18 — luks-monitor.service carries HOME=/root (root doppler unit) + the EnvironmentFile that
# supplies the boot token to the daily probe.
p_service_env() {
  local f="$1" body
  body="$(strip_comments "$f")"
  grep -qE '^Environment=HOME=/root[[:space:]]*$' <<<"$body" || { echo 0; return; }
  grep -qE '^EnvironmentFile=-?/etc/default/luks-monitor[[:space:]]*$' <<<"$body" || { echo 0; return; }
  echo 1
}

# H19 — the freeze-arm reviewer set stays NON-EMPTY (a zero-reviewer environment auto-approves,
# DP-11 F8; learning 2026-07-17-workflow-env-gate-references-unprovisioned-environment-auto-approves).
# BLOCK-SCOPED to the github_repository_environment.workspaces_luks_cutover resource (a decoy
# `users = [1]` elsewhere in the file must NOT satisfy it), and newline-flattened so a `terraform fmt`
# that wraps the list (`users = [\n  54279,\n]`) does not false-RED the line-oriented grep.
p_reviewers_nonempty() {
  local body; body="$(block_of "$1" github_repository_environment workspaces_luks_cutover | tr '\n' ' ')"
  grep -Eq 'users[[:space:]]*=[[:space:]]*\[[[:space:]]*[0-9]' <<<"$body" && echo 1 || echo 0
}

# H20 — verify.yml ALSO uses file-execution of luks-monitor.sh + stdin-token delivery (BOTH
# workflows must not regress the discipline); the old `sudo /usr/local/bin/luks-monitor` is gone.
p_verify_file_execution() {
  local f="$1" body
  body="$(strip_comments "$f")"
  grep -q 'REMOTE_DIR/luks-monitor.sh' <<<"$body" || { echo 0; return; }
  grep -q 'install -m600 /dev/stdin' <<<"$body" || { echo 0; return; }
  # Forbid running the PRE-INSTALLED binary regardless of sudo — the session is `-l root`, so the
  # realistic regression is a sudo-LESS `/usr/local/bin/luks-monitor` call that skips the shipped
  # file (+ the boot-token .env the probe needs). Anchor on the path, not the old `sudo …` prefix.
  grep -q '/usr/local/bin/luks-monitor' <<<"$body" && { echo 0; return; }
  echo 1
}

# --- #6649 assertions (mutation-tested) ---------------------------------------

assert_holds "H13 cutover runs the script as a FILE from a tar bundle (no bash -s pipe)" p_file_execution "$YML"
assert_mutation_append "H13 (bash -s stdin pipe re-introduced)" p_file_execution "$YML" \
  '          ${WEB_HOST_SSH} "$WEB_HOST" "bash -s" < "${INFRA_DIR}/workspaces-cutover.sh"'
# Prove the POSITIVE execution anchor is load-bearing: if `bash <file>` no longer invokes the script
# by path (e.g. it is piped to a bare `bash` instead), the guard must go RED.
assert_mutation "H13 (file no longer executed by path — bare-bash-stdin evasion)" p_file_execution "$YML" \
  's~bash (.{0,3}REMOTE_DIR/workspaces-cutover)~source \1~'

assert_holds "H14 boot token via install -m600 /dev/stdin, never a VAR=val argv (sudo-independent)" p_token_via_stdin "$YML"
assert_mutation "H14 (install -m600 /dev/stdin removed)" p_token_via_stdin "$YML" \
  's~install -m600 /dev/stdin~install /dev/stdin~'
assert_mutation_append "H14 (token leaked onto a SUDO argv)" p_token_via_stdin "$YML" \
  '          ${WEB_HOST_SSH} "$WEB_HOST" "sudo DOPPLER_TOKEN=$WORKSPACES_LUKS_BOOT_TOKEN bash x.sh"'
# The sudo-LESS argv leak is the realistic next regression (the -l root session dropped sudo):
assert_mutation_append "H14 (token leaked onto a sudo-LESS argv)" p_token_via_stdin "$YML" \
  '          ${WEB_HOST_SSH} "$WEB_HOST" "DOPPLER_TOKEN=$WORKSPACES_LUKS_BOOT_TOKEN bash x.sh"'
assert_mutation_append "H14 (token leaked via sudo --preserve-env argv)" p_token_via_stdin "$YML" \
  '          ${WEB_HOST_SSH} "$WEB_HOST" "sudo --preserve-env DOPPLER_TOKEN=$WORKSPACES_LUKS_BOOT_TOKEN bash x.sh"'

assert_holds "H15 .env shredded on a host-local EXIT trap (cutover)" p_env_shred_trap "$YML"
assert_mutation "H15 (shred removed from the cutover trap)" p_env_shred_trap "$YML" 's~shred -u~rm -f~g'
# H15b — verify.yml's .env ALSO carries the boot token, so its shred trap must be guarded too (the
# quality review found H20 asserted only file-execution + install, never the shred trap for verify).
assert_holds "H15b .env shredded on a host-local EXIT trap (verify)" p_env_shred_trap "$YML_VERIFY"
assert_mutation "H15b (shred removed from the verify trap)" p_env_shred_trap "$YML_VERIFY" 's~shred -u~rm -f~g'

assert_holds "H16 WORKSPACES_LUKS_DEV (by-id device) derived + passed" p_luks_dev_passed "$YML"
assert_mutation "H16 (WORKSPACES_LUKS_DEV no longer passed)" p_luks_dev_passed "$YML" \
  's~WORKSPACES_LUKS_DEV=%s~WORKSPACES_LUKS_UNPASSED=%s~'

assert_holds "H17 environment gate is fail-closed (real freeze arm only)" p_env_gate_failclosed "$YML"
assert_mutation "H17 (gate expression inverted to always-gated/ungated-freeze)" p_env_gate_failclosed "$YML" \
  's~!inputs\.dry_run~inputs.dry_run~'

assert_holds "H18 luks-monitor.service has HOME=/root + EnvironmentFile" p_service_env "$SVC"
assert_mutation "H18 (HOME=/root removed)" p_service_env "$SVC" 's~^Environment=HOME=/root~Environment=FOO=bar~'

assert_holds "H19 freeze-arm reviewer set stays non-empty" p_reviewers_nonempty "$TF_MAIN"
assert_mutation "H19 (reviewers emptied → auto-approve)" p_reviewers_nonempty "$TF_MAIN" \
  's~users[[:space:]]*=[[:space:]]*\[[0-9]+\]~users = []~'

assert_holds "H20 verify.yml uses file-execution + stdin token (no sudo binary)" p_verify_file_execution "$YML_VERIFY"
assert_mutation_append "H20 (old sudo /usr/local/bin/luks-monitor re-introduced)" p_verify_file_execution "$YML_VERIFY" \
  '          ${WEB_HOST_SSH} "$WEB_HOST" "sudo /usr/local/bin/luks-monitor"'

# --- Summary ------------------------------------------------------------------
echo "workspaces-luks-header.test.sh: $passes passed, $fails failed"
[ "$fails" -eq 0 ] || exit 1
