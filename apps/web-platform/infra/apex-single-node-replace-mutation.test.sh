#!/usr/bin/env bash
# apex-single-node-replace-mutation.test.sh — the falsifiability evidence for
# apex-single-node-replace.test.sh (#7640, ADR-194 plan §Guard Contract → Guard 2).
#
# A guard that cannot be driven RED is vacuous, and reading it is not evidence: the
# guard this battery covers was written by someone who knew that, and M3 below still
# needed a fixture to prove it fires. Every M row must drive the guard non-zero; every
# H row is a mutation of the SUITE rather than the system under test.
#
# WHY THE MUST-PASS ROWS ARE NOT OPTIONAL
#
# Without an input that DIFFERS from the canonical file in a way the contract explicitly
# permits, the RED rows cannot distinguish a correct guard from one that rejects
# everything. H2 (reflowed but correct) and H3 (the pre-PR4b shape) are those inputs.
# H3 additionally encodes the ship order: the guard lands one merge BEFORE the flip, so
# it must be green on `main` in the window between them.
#
# HARNESS DISCIPLINE
#
# - Restore from a PRISTINE COPY, never `git checkout` -- the fix under test is
#   frequently uncommitted, and `git checkout` would revert it and make every later row
#   score the defect against itself.
# - Assert each mutation LANDED (`cmp` against pristine). A mutation that does not land
#   reports the BASELINE, which is indistinguishable from a pass.
# - Run the UNMUTATED control FIRST. A red baseline voids every row below it.
# - `TMPDIR` defaults to /var/tmp: /tmp is a machine-global 4 GiB tmpfs shared by
#   parallel worktrees, and a direct invocation of this file (the inner loop while
#   editing the guard) inherits the bare /tmp that the registered runners override.
# - Every setup command is checked and aborts with exit 2. A harness that fails to SET UP
#   does not degrade into a missing result; it degrades into a confident wrong one.
set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
GUARD="$SCRIPT_DIR/apex-single-node-replace.test.sh"
SRC_DNS="$SCRIPT_DIR/dns.tf"
SRC_APPLY="$REPO_ROOT/.github/workflows/apply-web-platform-infra.yml"
SRC_VALID="$REPO_ROOT/.github/workflows/infra-validation.yml"

for required in "$GUARD" "$SRC_DNS" "$SRC_APPLY" "$SRC_VALID"; do
  [[ -r "$required" ]] || { printf '[FATAL] not readable: %s\n' "$required" >&2; exit 2; }
done

SANDBOX="$(mktemp -d -t apex-snr-mut.XXXXXXXX)" || { printf '[FATAL] mktemp failed\n' >&2; exit 2; }
trap 'rm -rf "$SANDBOX"' EXIT INT TERM HUP

PRISTINE="$SANDBOX/pristine"; WORK="$SANDBOX/work"
mkdir -p "$PRISTINE" "$WORK" || { printf '[FATAL] mkdir failed\n' >&2; exit 2; }
cp "$SRC_DNS" "$PRISTINE/dns.tf"       || { printf '[FATAL] cp dns.tf failed\n' >&2; exit 2; }
cp "$SRC_APPLY" "$PRISTINE/apply.yml"  || { printf '[FATAL] cp apply failed\n' >&2; exit 2; }
cp "$SRC_VALID" "$PRISTINE/valid.yml"  || { printf '[FATAL] cp valid failed\n' >&2; exit 2; }
cp "$GUARD" "$PRISTINE/guard.sh"       || { printf '[FATAL] cp guard failed\n' >&2; exit 2; }

PASS=0; FAIL=0; CASES=0
pass() { PASS=$((PASS + 1)); printf '  PASS: %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf '  FAIL: %s\n' "$1"; }
verdict() { CASES=$((CASES + 1)); if [[ "$1" -eq 0 ]]; then pass "$2"; else fail "$2"; fi; }

# INSTRUMENT SELF-TEST (ADR-193): drive both verdict arms once each and refuse to continue
# unless both counters moved. A battery whose helpers are stubbed reports every row as it
# pleases, so this runs before any row does.
_p0=$PASS; _f0=$FAIL
verdict 0 "instrument self-test: the PASS arm records"
verdict 1 "instrument self-test: the FAIL arm records (this FAIL is EXPECTED and is subtracted)"
if [[ "$PASS" -ne $((_p0 + 1)) || "$FAIL" -ne $((_f0 + 1)) ]]; then
  printf '[FATAL] instrument self-test did not move both counters\n' >&2; exit 2
fi
FAIL=$((FAIL - 1))   # the deliberate FAIL above is not a real failure
SELFTEST_CASES=2

reset_work() {
  cp "$PRISTINE/dns.tf" "$WORK/dns.tf"      || return 1
  cp "$PRISTINE/apply.yml" "$WORK/apply.yml" || return 1
  cp "$PRISTINE/valid.yml" "$WORK/valid.yml" || return 1
  cp "$PRISTINE/guard.sh" "$WORK/guard.sh"   || return 1
  chmod +x "$WORK/guard.sh"
}

run_guard() {
  APEX_GUARD_DNS_TF="$WORK/dns.tf" \
  APEX_GUARD_APPLY_WF="$WORK/apply.yml" \
  APEX_GUARD_VALIDATION_WF="$WORK/valid.yml" \
    bash "$WORK/guard.sh" >"$WORK/out.txt" 2>&1
  printf '%s' "$?"
}

# <id> <expected: RED|GREEN> <mutated-file-basename> <description>
# The mutation is applied by the caller before invoking this.
score() {
  local id="$1" want="$2" mfile="$3" desc="$4" rc
  if [[ "$mfile" != "-" ]]; then
    if cmp -s "$WORK/$mfile" "$PRISTINE/$(basename "$mfile")"; then
      verdict 1 "$id: MUTATION DID NOT LAND in $mfile — this row scored the baseline, not the mutant"
      return
    fi
  fi
  rc="$(run_guard)"
  if [[ "$want" == "RED" ]]; then
    if [[ "$rc" -ne 0 ]]; then verdict 0 "$id (RED as required, exit $rc) — $desc"
    else verdict 1 "$id SURVIVED (exit 0, expected non-zero) — $desc"; fi
  else
    if [[ "$rc" -eq 0 ]]; then verdict 0 "$id (GREEN as required) — $desc"
    else verdict 1 "$id must PASS but exited $rc — $desc"; printf '%s\n' "$(sed 's/^/      | /' "$WORK/out.txt")"; fi
  fi
}

# Rewrite the pre-flip dns.tf into the shape PR4b produces: github_pages gone, pages_apex
# declared, a moved block joining them. Synthesized, never captured (cq-test-fixtures-synthesized-only).
make_post_flip() { # <moved-from-index>
  local key="$1"
  python3 - "$WORK/dns.tf" "$key" <<'PY' || return 1
import re, sys
p, key = sys.argv[1], sys.argv[2]
s = open(p).read()
s = re.sub(
    r'resource "cloudflare_record" "github_pages" \{.*?\n\}\n',
    'moved {\n'
    '  from = cloudflare_record.github_pages["%s"]\n'
    '  to   = cloudflare_record.pages_apex\n'
    '}\n\n'
    'resource "cloudflare_record" "pages_apex" {\n'
    '  zone_id = var.cf_zone_id\n'
    '  name    = "soleur.ai"\n'
    '  content = cloudflare_pages_project.docs.subdomain\n'
    '  type    = "CNAME"\n'
    '  proxied = true\n'
    '  ttl     = 1\n'
    '}\n' % key,
    s, flags=re.S)
open(p, 'w').write(s)
PY
}

printf 'apex-single-node-replace mutation battery\n\n'

# --- CONTROL: unmutated must be GREEN, or every row below is void ------------------------
# Row accounting for EXPECTED_ROWS below: 2 self-test + 1 control + 8 M-rows (M1 M4 M5 M6
# M5p M7 M8 M9) + 1 post-flip fixture + 2 post-flip M-rows (M2 M3) + 3 harness rows = 17.
reset_work || { printf '[FATAL] reset_work failed\n' >&2; exit 2; }
rc="$(run_guard)"
if [[ "$rc" -ne 0 ]]; then
  printf '[FATAL] CONTROL IS RED (exit %s) — the battery cannot score anything. Guard output:\n' "$rc" >&2
  sed 's/^/  | /' "$WORK/out.txt" >&2
  exit 2
fi
verdict 0 "CONTROL: unmutated pre-flip tree is GREEN (rows below are scored against a live baseline)"

# --- M1: create_before_destroy on the apex record ---------------------------------------
reset_work || exit 2
python3 - "$WORK/dns.tf" <<'PY'
import sys
p=sys.argv[1]; s=open(p).read()
s=s.replace('resource "cloudflare_record" "github_pages" {',
            'resource "cloudflare_record" "github_pages" {\n  lifecycle {\n    create_before_destroy = true\n  }\n',1)
open(p,'w').write(s)
PY
score M1 RED dns.tf "create_before_destroy inverts the one ordering Cloudflare rejects (81053)"

# --- M4: www becomes an A record (Camp B) ------------------------------------------------
reset_work || exit 2
python3 - "$WORK/dns.tf" <<'PY'
import re,sys
p=sys.argv[1]; s=open(p).read()
s=re.sub(r'(resource "cloudflare_record" "www" \{.*?)type    = "CNAME"', r'\1type    = "A"', s, flags=re.S)
open(p,'w').write(s)
PY
score M4 RED dns.tf "type is ForceNew, so an A at www is a SECOND replacement racing the first"

# --- M5/M6: allow-list endpoints ---------------------------------------------------------
reset_work || exit 2
grep -v -E '^\s*-target=cloudflare_record\.github_pages\s*\\?\s*$' "$PRISTINE/apply.yml" > "$WORK/apply.yml"
score M5 RED apply.yml "a moved block with an untargeted endpoint HARD-ERRORS the apply"

reset_work || exit 2
grep -v -E '^\s*-target=cloudflare_record\.pages_apex\s*\\?\s*$' "$PRISTINE/apply.yml" > "$WORK/apply.yml"
score M6 RED apply.yml "the other endpoint of the same pair"

# --- M5-prefix: the _challenge sibling must NOT satisfy the github_pages assertion -------
# This is the row that proves the line anchor is load-bearing rather than decorative:
# `-target=cloudflare_record.github_pages` is a strict prefix of the _challenge target.
reset_work || exit 2
grep -v -E '^\s*-target=cloudflare_record\.github_pages\s*\\?\s*$' "$PRISTINE/apply.yml" > "$WORK/apply.yml"
if grep -qE '^\s*-target=cloudflare_record\.github_pages_challenge' "$WORK/apply.yml"; then
  score M5p RED apply.yml "the surviving _challenge prefix-sibling does not satisfy the github_pages endpoint"
else
  verdict 1 "M5p: fixture invalid — the _challenge sibling is absent, so the prefix trap is not exercised"
fi

# --- M7: a SECOND apex address record ----------------------------------------------------
reset_work || exit 2
cat >> "$WORK/dns.tf" <<'EOF'

resource "cloudflare_record" "apex_sibling_probe" {
  zone_id = var.cf_zone_id
  name    = "soleur.ai"
  content = "203.0.113.7"
  type    = "A"
  proxied = true
  ttl     = 1
}
EOF
score M7 RED dns.tf "a second apex address record restores A-and-CNAME at one name"

# --- M8: own-dispatch — empty the assertion list -----------------------------------------
reset_work || exit 2
python3 - "$WORK/guard.sh" <<'PY'
import re,sys
p=sys.argv[1]; s=open(p).read()
# Neuter every verdict call site; the floor must still fire on CASES == 0.
s=re.sub(r'^(\s*)verdict ', r'\1: verdict ', s, flags=re.M)
open(p,'w').write(s)
PY
score M8 RED guard.sh "a guard reporting 0 assertions and exiting 0 is vacuous — the floor must fire"

# --- M9: own-dispatch — remove the guard's registration ----------------------------------
reset_work || exit 2
grep -v 'apex-single-node-replace.test.sh' "$PRISTINE/valid.yml" > "$WORK/valid.yml"
score M9 RED valid.yml "a guard nobody runs passes by never running"

# --- POST-FLIP ROWS ----------------------------------------------------------------------
# M2 and M3 exist only after the flip, so they need the post-flip fixture. Build it and
# confirm it is GREEN before mutating it, or the two rows below score a broken fixture.
reset_work || exit 2
make_post_flip "185.199.108.153" || { printf '[FATAL] post-flip fixture build failed\n' >&2; exit 2; }
rc="$(run_guard)"
if [[ "$rc" -ne 0 ]]; then
  printf '[FATAL] post-flip FIXTURE is RED (exit %s) — M2/M3 would score a broken fixture:\n' "$rc" >&2
  sed 's/^/  | /' "$WORK/out.txt" >&2
  exit 2
fi
verdict 0 "post-flip fixture (moved + pages_apex, correct index) is GREEN"

# --- M2: delete the moved block ----------------------------------------------------------
reset_work || exit 2
make_post_flip "185.199.108.153" || exit 2
python3 - "$WORK/dns.tf" <<'PY'
import re,sys
p=sys.argv[1]; s=open(p).read()
s=re.sub(r'moved \{.*?\n\}\n\n', '', s, count=1, flags=re.S)
open(p,'w').write(s)
PY
score M2 RED dns.tf "without the moved block the apex is two unrelated addresses, dispatched concurrently"

# --- M3: the silent-failure row ----------------------------------------------------------
reset_work || exit 2
make_post_flip "185.199.111.153" || exit 2
score M3 RED dns.tf "moved.from names an index that is NOT the surviving key — Terraform no-ops the move with NO error"

# --- H1: delete the M1 case from the guard's case list -----------------------------------
reset_work || exit 2
python3 - "$WORK/guard.sh" <<'PY'
import re,sys
p=sys.argv[1]; s=open(p).read()
s=re.sub(r'rc=1; \[\[ -z "\$cbd_offenders" \]\] && rc=0\nverdict "\$rc" "no apex address record declares create_before_destroy[^\n]*\n', '', s, count=1)
open(p,'w').write(s)
PY
score H1 RED guard.sh "deleting a case must trip the exact-cardinality floor, not silently shrink coverage"

# --- H2: must-PASS, reflowed but correct -------------------------------------------------
reset_work || exit 2
python3 - "$WORK/dns.tf" <<'PY'
import re,sys
p=sys.argv[1]; s=open(p).read()
# Reflow: collapse the contract comment, and pad whitespace inside the www block. The
# guard asserts content anchors, not byte-equality, so this must stay GREEN.
s=re.sub(r'^# {2,}', '#   ', s, flags=re.M)
s=s.replace('resource "cloudflare_record" "www" {', 'resource "cloudflare_record"   "www"   {',1)
s=s.replace('  type    = "CNAME"\n  proxied = true', '  type        =    "CNAME"\n  proxied     =    true',1)
open(p,'w').write(s)
PY
score H2 GREEN dns.tf "reflowed-but-correct input must PASS, or the RED rows cannot distinguish a correct guard from one that rejects everything"

# --- H3: must-PASS, the pre-PR4b shape ---------------------------------------------------
# This IS the pristine tree (PR4a's output), so it is byte-identical to the control by
# construction. Scored with mfile "-" because the landed-mutation check does not apply.
reset_work || exit 2
score H3 GREEN - "the pre-PR4b shape must PASS — the guard ships a merge early and must not block main in the window"

# ---------------------------------------------------------------------------------------
# ANTI-VACUITY FLOOR (AP-023 / ADR-193) — printf + exit 1, never this suite's own fail
# ---------------------------------------------------------------------------------------
printf '\n'
EXPECTED_ROWS=17
if [[ "$CASES" -lt "$EXPECTED_ROWS" ]]; then
  printf '[VACUITY] only %d row(s) ran, expected exactly %d — a row was deleted or skipped\n' "$CASES" "$EXPECTED_ROWS" >&2
  exit 1
fi
if [[ "$CASES" -gt "$EXPECTED_ROWS" ]]; then
  printf '[VACUITY] %d row(s) ran, expected exactly %d — bump EXPECTED_ROWS deliberately\n' "$CASES" "$EXPECTED_ROWS" >&2
  exit 1
fi

printf 'apex-single-node-replace mutation battery: %d passed, %d failed (%d rows, incl. %d self-test)\n' \
  "$PASS" "$FAIL" "$CASES" "$SELFTEST_CASES"
[[ "$FAIL" -eq 0 ]] || exit 1
