#!/usr/bin/env bash
# apex-single-node-replace-mutation.test.sh — falsifiability evidence for
# apex-single-node-replace.test.sh (#7640, ADR-194 plan §Guard Contract → Guard 2).
#
# WHAT AN EARLIER REVISION OF THIS FILE GOT WRONG, RECORDED SO IT IS NOT REDONE
#
# It reported 16/0 over 17 rows and that number was accurate about the fifteen
# mutations its author imagined. A review pass then measured what it could not
# see, and the gaps were all in the same place — the axes it never edited:
#
#   * VERDICT ROUTING. Rewriting the guard's wrapper to `CASES=$((CASES+1));
#     pass "$2"` left every assertion reporting PASS with create_before_destroy
#     planted on the live apex, exit 0. CASES still reached its exact floor and
#     PASS+FAIL still equalled it, so all three anti-vacuity mechanisms were
#     satisfied. The guard now carries a positive control for this; row D4
#     is what proves the control works.
#   * ATTRIBUTION. `score()` read only the process exit code, so a row could
#     report "RED as required" for an assertion other than the one it names.
#     Every row now names the FAIL string it expects and the harness greps for
#     it — the discipline the sibling batteries in this directory already carry.
#   * UNWITNESSED CASES. Five of the guard's cases could each be pinned
#     permanently-true with this battery still reporting all-green. The worst
#     was the pre-flip for_each key case, which is the entire anchor for the
#     two-merge contract literal.
#   * THE FIXTURE ROW'S OWN LANDED-CHECK. The one row exempted from the
#     harness's `cmp` discipline was the row that needed it most: a silently
#     no-op `make_post_flip` made it score the PRE-flip tree while claiming to
#     have verified a post-flip fixture.
#
# HARNESS DISCIPLINE
#
# - Restore from a PRISTINE COPY, never `git checkout` — the fix under test is
#   frequently uncommitted, and `git checkout` would revert it and make every
#   later row score the defect against itself.
# - Assert each mutation LANDED (`cmp` against pristine). A mutation that does
#   not land reports the BASELINE, indistinguishable from a pass.
# - Run the UNMUTATED control FIRST. A red baseline voids every row below it.
# - Name the expected FAIL string per row. `rc != 0` is a symptom several
#   assertions share; it is not attribution.
# - `TMPDIR` defaults to /var/tmp: /tmp is a machine-global tmpfs shared by
#   parallel worktrees, and a direct invocation of this file inherits the bare
#   /tmp that the registered runners override.
# - The guard scans a DIRECTORY, so the sandbox is a directory too.
set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
GUARD="$SCRIPT_DIR/apex-single-node-replace.test.sh"
SRC_APPLY="$REPO_ROOT/.github/workflows/apply-web-platform-infra.yml"
SRC_VALID="$REPO_ROOT/.github/workflows/infra-validation.yml"

for required in "$GUARD" "$SRC_APPLY" "$SRC_VALID"; do
  [[ -r "$required" ]] || { printf '[FATAL] not readable: %s\n' "$required" >&2; exit 2; }
done

# DERIVED, never re-typed. An earlier revision typed "185.199.108.153" into this
# file twice; a consistent rename of dns.tf + the guard constant would then have
# made the fixture row go RED and the battery abort with "[FATAL] fixture is
# RED" — a real drift reported as a broken control, the most misleading
# diagnosis available.
SURVIVING_KEY="$(grep -oE '^SURVIVING_APEX_KEY="[^"]+"' "$GUARD" | head -1 | sed 's/.*="//; s/"$//')"
if [[ ! "$SURVIVING_KEY" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  printf '[FATAL] could not derive SURVIVING_APEX_KEY from the guard (got %q)\n' "$SURVIVING_KEY" >&2
  exit 2
fi

SANDBOX="$(mktemp -d -t apex-snr-mut.XXXXXXXX)" || { printf '[FATAL] mktemp failed\n' >&2; exit 2; }
trap 'rm -rf "$SANDBOX"' EXIT INT TERM HUP

PRISTINE="$SANDBOX/pristine"; WORK="$SANDBOX/work"
mkdir -p "$PRISTINE/tf" "$WORK/tf" || { printf '[FATAL] mkdir failed\n' >&2; exit 2; }
cp "$SCRIPT_DIR"/*.tf "$PRISTINE/tf/"   || { printf '[FATAL] cp *.tf failed\n' >&2; exit 2; }

# THE PRE-FLIP BASELINE IS A FROZEN FIXTURE, NOT THE LIVE `dns.tf` (#7640 PR4b).
#
# Every pre-flip row (M14/M15/M16, H3) and `make_post_flip` itself need a tree in
# the shape PR4a left behind. Sourcing that from the live `dns.tf` worked for
# exactly one merge: PR4b flips the live file to post-flip, `make_post_flip`'s
# regex then finds no `github_pages` block, and the battery aborts at setup.
#
# It aborted LOUDLY (exit 2) rather than scoring a baseline it could not build,
# which is the property this file's own header demands — but the fix is to stop
# deriving a fixture from a file whose stage moves underneath it. Pinning the
# pristine `dns.tf` to the committed PR4a baseline makes the battery
# stage-independent: it scores the GUARD against synthetic trees, while the
# guard itself is what validates the live root (it runs against `$SCRIPT_DIR`
# in CI, unseamed).
#
# The fixture is asserted PRE-FLIP below. A baseline that had drifted post-flip
# would make every pre-flip row vacuous while all of them still reported PASS —
# the exact fail-open this battery exists to refuse.
PRE_FLIP_BASELINE="$SCRIPT_DIR/fixtures/dns.tf.pr4a-baseline"
if [[ ! -r "$PRE_FLIP_BASELINE" ]]; then
  printf '[FATAL] pre-flip baseline fixture missing: %s\n' "$PRE_FLIP_BASELINE" >&2; exit 2
fi
if ! grep -qE '^resource "cloudflare_record" "github_pages" \{' "$PRE_FLIP_BASELINE"; then
  printf '[FATAL] baseline fixture is not PRE-flip (no github_pages resource) — every pre-flip row would be vacuous\n' >&2; exit 2
fi
if grep -qE '^resource "cloudflare_record" "pages_apex" \{' "$PRE_FLIP_BASELINE"; then
  printf '[FATAL] baseline fixture is POST-flip (declares pages_apex) — it is meant to be the shape PR4a left\n' >&2; exit 2
fi
if ! grep -qF "\"$SURVIVING_KEY\"" "$PRE_FLIP_BASELINE"; then
  printf '[FATAL] baseline fixture does not carry the surviving key %s\n' "$SURVIVING_KEY" >&2; exit 2
fi
cp "$PRE_FLIP_BASELINE" "$PRISTINE/tf/dns.tf" || { printf '[FATAL] cp baseline failed\n' >&2; exit 2; }
cp "$SRC_APPLY" "$PRISTINE/apply.yml"   || { printf '[FATAL] cp apply failed\n' >&2; exit 2; }
cp "$SRC_VALID" "$PRISTINE/valid.yml"   || { printf '[FATAL] cp valid failed\n' >&2; exit 2; }
cp "$GUARD" "$PRISTINE/guard.sh"        || { printf '[FATAL] cp guard failed\n' >&2; exit 2; }

PASS=0; FAIL=0; CASES=0
pass() { PASS=$((PASS + 1)); printf '  PASS: %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf '  FAIL: %s\n' "$1"; }
verdict() { CASES=$((CASES + 1)); if [[ "$1" == "0" ]]; then pass "$2"; else fail "$2"; fi; }

# INSTRUMENT SELF-TEST (ADR-193): drive both verdict arms once each and refuse
# to continue unless both counters moved.
# Drives the WRAPPER, not pass/fail directly — a mis-routing wrapper is the
# mutation a helper-level control cannot see (row D4 proves this one can).
# Both self-test rows are then removed from the accounting entirely, so the
# identity below stays exact rather than off-by-the-deliberate-FAIL.
_p0=$PASS; _f0=$FAIL; _c0=$CASES
verdict 0 "instrument self-test: the PASS arm records"
verdict 1 "instrument self-test: the FAIL arm records (EXPECTED — subtracted)"
if [[ "$PASS" -ne $((_p0 + 1)) || "$FAIL" -ne $((_f0 + 1)) || "$CASES" -ne $((_c0 + 2)) ]]; then
  printf '[FATAL] instrument self-test: verdict did not route both arms\n' >&2; exit 2
fi
PASS=$((PASS - 1)); FAIL=$((FAIL - 1)); CASES=$((CASES - 2))
SELFTEST_CASES=2

reset_work() {
  rm -rf "$WORK/tf" && mkdir -p "$WORK/tf"    || return 1
  cp "$PRISTINE/tf/"*.tf "$WORK/tf/"          || return 1
  cp "$PRISTINE/apply.yml" "$WORK/apply.yml"  || return 1
  cp "$PRISTINE/valid.yml" "$WORK/valid.yml"  || return 1
  cp "$PRISTINE/guard.sh" "$WORK/guard.sh"    || return 1
  chmod +x "$WORK/guard.sh"
}

# `env -u CI`: the guard refuses its own test seams when CI is set (that refusal
# is itself a row, C1). Driving fixtures therefore has to clear it explicitly.
run_guard() {
  env -u CI \
    APEX_GUARD_TF_DIR="$WORK/tf" \
    APEX_GUARD_APPLY_WF="$WORK/apply.yml" \
    APEX_GUARD_VALIDATION_WF="$WORK/valid.yml" \
    bash "$WORK/guard.sh" >"$WORK/out.txt" 2>&1
  printf '%s' "$?"
}

landed() { # <relative-path-under-work>
  local f="$1"
  if [[ "$f" == "-" ]]; then return 0; fi
  local pristine_path="$PRISTINE/${f#*/}"
  [[ "$f" == tf/* ]] && pristine_path="$PRISTINE/tf/${f#tf/}"
  [[ "$f" == guard.sh ]] && pristine_path="$PRISTINE/guard.sh"
  [[ "$f" == apply.yml ]] && pristine_path="$PRISTINE/apply.yml"
  [[ "$f" == valid.yml ]] && pristine_path="$PRISTINE/valid.yml"
  if [[ ! -e "$WORK/$f" ]]; then return 0; fi          # deletion IS the mutation
  if [[ ! -e "$pristine_path" ]]; then return 0; fi    # creation IS the mutation
  ! cmp -s "$WORK/$f" "$pristine_path"
}

# <id> <RED|GREEN> <mutated-file|-> <expected-FAIL-substring|-> <description>
score() {
  local id="$1" want="$2" mfile="$3" expect="$4" desc="$5" rc
  if ! landed "$mfile"; then
    verdict 1 "$id: MUTATION DID NOT LAND in $mfile — this row scored the baseline, not the mutant"
    return
  fi
  rc="$(run_guard)"
  if [[ "$want" == "RED" ]]; then
    if [[ "$rc" -eq 0 ]]; then
      verdict 1 "$id SURVIVED (exit 0, expected non-zero) — $desc"
      return
    fi
    # ATTRIBUTION: the guard went red, but on THIS row's case?
    if [[ "$expect" != "-" ]] && ! grep -E '^  FAIL|^\[VACUITY\]|^\[FATAL\]' "$WORK/out.txt" | grep -qF -- "$expect"; then
      verdict 1 "$id MISROUTED (exit $rc, but not on the case this row targets: '$expect')"
      return
    fi
    verdict 0 "$id (RED on its own case, exit $rc) — $desc"
  else
    if [[ "$rc" -eq 0 ]]; then verdict 0 "$id (GREEN as required) — $desc"
    else verdict 1 "$id must PASS but exited $rc — $desc"; sed 's/^/      | /' "$WORK/out.txt"; fi
  fi
}

# Rewrite the pre-flip tree into the shape PR4b produces. Asserts its own
# substitution landed — a silently no-op regex here makes every post-flip row
# score the pre-flip tree.
make_post_flip() { # <moved-from-index>
  local key="$1"
  python3 - "$WORK/tf/dns.tf" "$key" <<'PY' || return 1
import re, sys
p, key = sys.argv[1], sys.argv[2]
s = open(p).read()
s2 = re.sub(
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
if s2 == s:
    sys.stderr.write("make_post_flip: substitution did not land\n")
    sys.exit(1)
open(p, 'w').write(s2)
PY
}

printf 'apex-single-node-replace mutation battery (survivor key derived: %s)\n\n' "$SURVIVING_KEY"

# --- CONTROL --------------------------------------------------------------------------
reset_work || { printf '[FATAL] reset_work failed\n' >&2; exit 2; }
rc="$(run_guard)"
if [[ "$rc" -ne 0 ]]; then
  printf '[FATAL] CONTROL IS RED (exit %s) — the battery cannot score anything:\n' "$rc" >&2
  sed 's/^/  | /' "$WORK/out.txt" >&2
  exit 2
fi
verdict 0 "CONTROL: unmutated pre-flip tree is GREEN"

# ======================================================================================
# SUT ROWS — dns.tf, pre-flip
# ======================================================================================
reset_work || exit 2
python3 - "$WORK/tf/dns.tf" <<'PY'
import sys
p=sys.argv[1]; s=open(p).read()
s=s.replace('resource "cloudflare_record" "github_pages" {',
            'resource "cloudflare_record" "github_pages" {\n  lifecycle {\n    create_before_destroy = true\n  }\n',1)
open(p,'w').write(s)
PY
score M1 RED tf/dns.tf "create_before_destroy" "create_before_destroy inverts the one ordering Cloudflare rejects (81053)"

reset_work || exit 2
python3 - "$WORK/tf/dns.tf" <<'PY'
import re,sys
p=sys.argv[1]; s=open(p).read()
s=re.sub(r'(resource "cloudflare_record" "www" \{.*?)type    = "CNAME"', r'\1type    = "A"', s, flags=re.S)
open(p,'w').write(s)
PY
score M4 RED tf/dns.tf "every www record is a CNAME" "type is ForceNew, so an A at www is a SECOND replacement racing the first"

reset_work || exit 2
cat >> "$WORK/tf/dns.tf" <<'EOF'

resource "cloudflare_record" "apex_sibling_probe" {
  zone_id = var.cf_zone_id
  name    = "soleur.ai"
  content = "203.0.113.7"
  type    = "A"
  proxied = true
  ttl     = 1
}
EOF
score M7 RED tf/dns.tf "exactly one apex address record" "a second apex address record restores A-and-CNAME at one name"

# --- the spellings an exact-string quantifier misses -----------------------------------
for spelling in 'soleur.ai.' '@' 'SOLEUR.AI'; do
  reset_work || exit 2
  cat >> "$WORK/tf/dns.tf" <<EOF

resource "cloudflare_record" "apex_spelling_probe" {
  zone_id = var.cf_zone_id
  name    = "${spelling}"
  content = "2001:db8::1"
  type    = "AAAA"
  proxied = true
  ttl     = 1
}
EOF
  score "M7-${spelling}" RED tf/dns.tf "exactly one apex address record" "apex spelled '${spelling}' is still the zone root"
done

# --- the file-scope row: Terraform reads the directory, not one file -------------------
reset_work || exit 2
cat > "$WORK/tf/zz-sibling.tf" <<'EOF'
resource "cloudflare_record" "apex_other_file" {
  zone_id = var.cf_zone_id
  name    = "soleur.ai"
  content = "203.0.113.9"
  type    = "A"
  proxied = true
  ttl     = 1
}
EOF
score M10 RED tf/zz-sibling.tf "exactly one apex address record" "an apex record in a SIBLING .tf is still in Terraform's root"

# --- the relocated-pages_apex row (stage resolution must see the whole root) -----------
reset_work || exit 2
make_post_flip "$SURVIVING_KEY" || exit 2
python3 - "$WORK/tf/dns.tf" "$WORK/tf/zz-pages-apex.tf" <<'PY'
import re,sys
src,dst=sys.argv[1],sys.argv[2]
s=open(src).read()
m=re.search(r'resource "cloudflare_record" "pages_apex" \{.*?\n\}\n', s, flags=re.S)
assert m, "pages_apex block not found"
open(dst,'w').write(m.group(0))
open(src,'w').write(s.replace(m.group(0),''))
PY
score M11 GREEN tf/zz-pages-apex.tf - "pages_apex relocated to a sibling .tf is still found (stage resolves across the root)"

# --- fail-closed on what cannot be measured -------------------------------------------
reset_work || exit 2
cat >> "$WORK/tf/dns.tf" <<'EOF'

resource "cloudflare_record" "apex_nonliteral_probe" {
  zone_id = var.cf_zone_id
  name    = local.apex_host
  content = "203.0.113.11"
  type    = var.apex_type
  proxied = true
  ttl     = 1
}
EOF
score M12 RED tf/dns.tf "literal name/type" "a record whose addressing the guard cannot READ is one it cannot vouch for"

# --- a second www record under a DIFFERENT label ---------------------------------------
reset_work || exit 2
cat >> "$WORK/tf/dns.tf" <<'EOF'

resource "cloudflare_record" "www_legacy" {
  zone_id = var.cf_zone_id
  name    = "www"
  content = "203.0.113.13"
  type    = "A"
  proxied = true
  ttl     = 1
}
EOF
score M13 RED tf/dns.tf "exactly one www record" "M4 read only the block LABELLED www; a sibling label escaped both quantifiers"

# --- previously-unwitnessed pre-flip cases ---------------------------------------------
reset_work || exit 2
python3 - "$WORK/tf/dns.tf" <<'PY'
import sys
p=sys.argv[1]; s=open(p).read()
s=s.replace('    "185.199.108.153",\n', '    "185.199.108.153",\n    "185.199.109.153",\n',1)
open(p,'w').write(s)
PY
score M14 RED tf/dns.tf "exactly the one for_each key" "a second for_each key re-opens the concurrent-delete hazard"

reset_work || exit 2
python3 - "$WORK/tf/dns.tf" <<'PY'
import re,sys
p=sys.argv[1]; s=open(p).read()
s=re.sub(r'(resource "cloudflare_record" "github_pages" \{.*?)type    = "A"', r'\1type    = "AAAA"', s, flags=re.S)
open(p,'w').write(s)
PY
score M15 RED tf/dns.tf "the apex origin is still the github_pages A record" "the pre-flip apex must still be an A record"

reset_work || exit 2
cat >> "$WORK/tf/dns.tf" <<'EOF'

moved {
  from = cloudflare_record.github_pages["185.199.108.153"]
  to   = cloudflare_record.pages_apex
}
EOF
score M16 RED tf/dns.tf "no moved block targets the apex yet" "a premature apex moved block is PR4b's change landing early"

# ======================================================================================
# WORKFLOW ROWS
# ======================================================================================
reset_work || exit 2
grep -v -E '^\s*-target=cloudflare_record\.github_pages\s*\\?\s*$' "$PRISTINE/apply.yml" > "$WORK/apply.yml"
score M5 RED apply.yml "targets cloudflare_record.github_pages" "a moved block with an untargeted endpoint HARD-ERRORS the apply"

reset_work || exit 2
grep -v -E '^\s*-target=cloudflare_record\.pages_apex\s*\\?\s*$' "$PRISTINE/apply.yml" > "$WORK/apply.yml"
score M6 RED apply.yml "targets cloudflare_record.pages_apex" "the other endpoint of the same pair"

# The prefix trap: `…github_pages` is a strict prefix of `…github_pages_challenge`.
reset_work || exit 2
grep -v -E '^\s*-target=cloudflare_record\.github_pages\s*\\?\s*$' "$PRISTINE/apply.yml" > "$WORK/apply.yml"
if grep -qE '^\s*-target=cloudflare_record\.github_pages_challenge' "$WORK/apply.yml"; then
  score M5p RED apply.yml "targets cloudflare_record.github_pages" "the surviving _challenge prefix-sibling does not satisfy the endpoint"
else
  verdict 1 "M5p: fixture invalid — the _challenge sibling is absent, so the prefix trap is not exercised"
fi

# THE SCOPE ROW. Move the endpoint out of the merge-apply plan step and re-add it
# inside a job that never runs. A file-global grep credits it; a step-scoped one
# does not. Measured GREEN before the guard was scoped.
reset_work || exit 2
python3 - "$WORK/apply.yml" <<'PY'
import re,sys
p=sys.argv[1]; s=open(p).read()
line='              -target=cloudflare_record.pages_apex \\\n'
assert s.count(line)==1, s.count(line)
s=s.replace(line,'')
s=s.rstrip('\n')+'\n\n  decoy_never_runs:\n    if: false\n    runs-on: ubuntu-latest\n    steps:\n      - name: decoy\n        run: |\n          terraform plan \\\n              -target=cloudflare_record.pages_apex\n'
open(p,'w').write(s)
PY
score M17 RED apply.yml "targets cloudflare_record.pages_apex" "an endpoint in an if:false decoy job does not satisfy the merge-apply step"

reset_work || exit 2
grep -v 'apex-single-node-replace.test.sh' "$PRISTINE/valid.yml" > "$WORK/valid.yml"
score M9 RED valid.yml "dispatched by a run: step" "a guard nobody runs passes by never running"

# THE COMMENT ROW. Delete the run: step and leave a comment naming the file.
# A bare substring search credits the comment; an invocation anchor over a
# comment-stripped view does not. Measured GREEN before this was fixed.
reset_work || exit 2
python3 - "$WORK/valid.yml" <<'PY'
import re,sys
p=sys.argv[1]; s=open(p).read()
old='''      - name: Run apex-single-node-replace drift-guard (#7640)
        run: bash apps/web-platform/infra/apex-single-node-replace.test.sh
'''
assert s.count(old)==1
s=s.replace(old,'      # DISABLED: apps/web-platform/infra/apex-single-node-replace.test.sh\n')
open(p,'w').write(s)
PY
score M18 RED valid.yml "dispatched by a run: step" "a comment naming the guard is documentation, not dispatch"

# ======================================================================================
# POST-FLIP ROWS
# ======================================================================================
reset_work || exit 2
make_post_flip "$SURVIVING_KEY" || { printf '[FATAL] post-flip fixture build failed\n' >&2; exit 2; }
score PF GREEN tf/dns.tf - "post-flip fixture (moved + pages_apex, correct index) is GREEN"

reset_work || exit 2
make_post_flip "$SURVIVING_KEY" || exit 2
python3 - "$WORK/tf/dns.tf" <<'PY'
import re,sys
p=sys.argv[1]; s=open(p).read()
s2=re.sub(r'moved \{.*?\n\}\n\n', '', s, count=1, flags=re.S)
assert s2!=s, "moved-block deletion did not land"
open(p,'w').write(s2)
PY
score M2 RED tf/dns.tf "a moved block re-addresses the survivor" "without the moved block the apex is two unrelated addresses"

reset_work || exit 2
make_post_flip "185.199.111.153" || exit 2
score M3 RED tf/dns.tf "moved.from is byte-identical" "moved.from names an index that is NOT the survivor — Terraform no-ops the move with NO error"

# THE CO-MUTATION ROW, AND IT IS A must-PASS ONE — deliberately.
#
# Changing the guard's pin AND dns.tf's for_each key TOGETHER is legal as far
# as any static reader can tell: the two agree, so every case is satisfied. It
# is recorded GREEN rather than deleted, because a reader who assumed this was
# covered would be wrong in the dangerous direction — the STATE still holds the
# OLD key, so PR4b's moved.from would name a key absent from state and Terraform
# would no-op the move with no error at all.
#
# The mechanism that covers it is PF9b against plan JSON (`previous_address`),
# a PR4b deliverable (tasks.md 2.9). This row exists so the gap is asserted
# rather than assumed.
reset_work || exit 2
sed -i 's/^SURVIVING_APEX_KEY="[^"]*"/SURVIVING_APEX_KEY="185.199.111.153"/' "$WORK/guard.sh"
python3 - "$WORK/tf/dns.tf" <<'PY'
import sys
p=sys.argv[1]; s=open(p).read()
s=s.replace('"185.199.108.153",','"185.199.111.153",',1)
open(p,'w').write(s)
PY
score M19 GREEN guard.sh - "a CONSISTENT co-mutated pin passes — the guard is state-blind by construction; PF9b covers it in PR4b"

reset_work || exit 2
make_post_flip "$SURVIVING_KEY" || exit 2
python3 - "$WORK/tf/dns.tf" <<'PY'
import re,sys
p=sys.argv[1]; s=open(p).read()
s2=re.sub(r'(resource "cloudflare_record" "pages_apex" \{\n)', r'\1  for_each = toset(["a", "b"])\n', s, count=1)
assert s2!=s
open(p,'w').write(s2)
PY
score M20 RED tf/dns.tf "single-instance CNAME" "count/for_each on pages_apex is not the single-node replace core serialises"

# ======================================================================================
# HARNESS / OWN-DISPATCH ROWS
# ======================================================================================
reset_work || exit 2
python3 - "$WORK/guard.sh" <<'PY'
import re,sys
p=sys.argv[1]; s=open(p).read()
s=re.sub(r'^(\s*)verdict ', r'\1: verdict ', s, flags=re.M)
open(p,'w').write(s)
PY
score M8 RED guard.sh "[FATAL]" "neutering every verdict call must be caught — the positive control fires before the floor is even reached"

# D4 — THE ROUTING ROW. This is the mutation the previous battery could not
# express and the accounting identity structurally cannot detect: the wrapper
# still counts, still records, and sends every verdict to the PASS arm.
reset_work || exit 2
python3 - "$WORK/guard.sh" "$WORK/tf/dns.tf" <<'PY'
import sys
g,d=sys.argv[1],sys.argv[2]
s=open(g).read()
old='  if [[ "$1" == "0" ]]; then pass "$2"; else fail "$2"; fi'
assert s.count(old)==1
open(g,'w').write(s.replace(old,'  pass "$2"'))
t=open(d).read()
open(d,'w').write(t.replace('resource "cloudflare_record" "github_pages" {',
  'resource "cloudflare_record" "github_pages" {\n  lifecycle {\n    create_before_destroy = true\n  }\n',1))
PY
score D4 RED guard.sh "[FATAL]" "a mis-ROUTING verdict wrapper must be caught by the positive control, not by the identity"

reset_work || exit 2
python3 - "$WORK/guard.sh" <<'PY'
import re,sys
p=sys.argv[1]; s=open(p).read()
s2=re.sub(r"rc=1; \[\[ -z \"\$cbd_offenders\" \]\] && rc=0\nverdict \"\$rc\" \"no apex address record declares create_before_destroy[^\n]*\n", '', s, count=1)
assert s2!=s, "H1 case-deletion did not land"
open(p,'w').write(s2)
PY
score H1 RED guard.sh "[VACUITY]" "deleting a case must trip the exact-cardinality floor"

# C1 — the seam refusal. The guard must not accept a redirected fixture under CI.
reset_work || exit 2
c1_rc=0
CI=1 APEX_GUARD_TF_DIR="$WORK/tf" bash "$WORK/guard.sh" >"$WORK/out.txt" 2>&1 || c1_rc=$?
if [[ "$c1_rc" -eq 2 ]] && grep -q 'refusing to run against a fixture' "$WORK/out.txt"; then
  verdict 0 "C1 (refused, exit 2) — the test seam is fail-closed under CI"
else
  verdict 1 "C1: guard accepted a redirected fixture under CI (exit $c1_rc)"
fi

# --- must-PASS rows --------------------------------------------------------------------
reset_work || exit 2
python3 - "$WORK/tf/dns.tf" <<'PY'
import re,sys
p=sys.argv[1]; s=open(p).read()
s=re.sub(r'^# {2,}', '#   ', s, flags=re.M)
s=s.replace('resource "cloudflare_record" "www" {', '  resource "cloudflare_record"   "www"   {',1)
s=s.replace('  type    = "CNAME"\n  proxied = true', '  type        =    "CNAME"\n  proxied     =    true',1)
open(p,'w').write(s)
PY
score H2 GREEN tf/dns.tf - "reflowed/indented-but-correct input must PASS, or the RED rows cannot distinguish a correct guard from one that rejects everything"

reset_work || exit 2
score H3 GREEN - - "the pre-PR4b shape must PASS — the guard ships a merge early and must not block main in the window"

# ---------------------------------------------------------------------------------------
# ANTI-VACUITY FLOOR — printf + exit 1, never this suite's own fail
# ---------------------------------------------------------------------------------------
# The two self-test rows are subtracted above, so this counts the real work:
# 1 control + 30 mutation/must-PASS rows = 31.
printf '\n'
EXPECTED_ROWS=31
if [[ "$CASES" -lt "$EXPECTED_ROWS" ]]; then
  printf '[VACUITY] only %d row(s) ran, expected exactly %d\n' "$CASES" "$EXPECTED_ROWS" >&2
  exit 1
fi
if [[ "$CASES" -gt "$EXPECTED_ROWS" ]]; then
  printf '[VACUITY] %d row(s) ran, expected exactly %d — bump EXPECTED_ROWS deliberately\n' "$CASES" "$EXPECTED_ROWS" >&2
  exit 1
fi
if [[ "$((PASS + FAIL))" -ne "$CASES" ]]; then
  printf '[VACUITY] accounting identity broken: PASS+FAIL=%d != CASES=%d\n' "$((PASS + FAIL))" "$CASES" >&2
  exit 1
fi

printf 'apex-single-node-replace mutation battery: %d passed, %d failed (%d rows; %d self-test rows subtracted)\n' \
  "$PASS" "$FAIL" "$CASES" "$SELFTEST_CASES"
[[ "$FAIL" -eq 0 ]] || exit 1
