#!/usr/bin/env bash
#
# Guard 3 (host-replace window prework, #10112 item 1 / Ref #9927) -- the retired plaintext-to-LUKS cutover
# vocabulary is absent from every image-baked carrier, and the retired trio is named nowhere on a delivery path.
#
# PROPERTY. No file the inngest-bootstrap image bakes (and no member of the signed config-refresh set) names the
# retired plaintext volume, the staging mapper or mount, or the cutover state paths, and none of the retired cutover
# trio (inngest-luks-cutover.{sh,service,timer}) is staged, baked, installed, refreshed or pushed any more.
#
# ASSEMBLY. The carrier set is DERIVED, never listed (derive_carriers): the `cp apps/web-platform/infra/<file>` lines of
# build-inngest-bootstrap-image.yml (the same extraction the mint script and cloud-init-inngest-bootstrap.test.sh
# GuardA use) UNION the members of inngest-config-refresh-set.txt. One scan function (g3_scan) takes a repo root, so the
# SAME code judges the real tree and every mutated fixture copy. Two scans, over different populations:
#   - VOCABULARY (exact retired identifiers, comments NOT stripped: a needle in a comment of a baked file is still baked)
#     over every derived carrier plus the build recipe and its check twin.
#   - TRIO STEM (`inngest-luks-cutover`, no extension, comment lines stripped so history prose stays legal) over every
#     derived carrier plus the build recipe, the check twin and the delivery-path files (DEST_SPEC, FILE_MAP, the push
#     payload, the hook template, the web-host trigger set). The stem, not `.sh|.service|.timer`, so a brace form, a
#     bare unit name or a name built from `$e` is caught.
#
# NOT COVERED HERE (deliberately). (1) The STAGED list and quiesce loop in cloud-init-inngest.yml still name the
# retired trio until the user_data PR (PR-D) lands; that file is user_data and is out of this change, PR-D adds it to the
# scan. Until then a stale STAGED entry is harmless: the staging copy is `docker cp ... || true` and the bootstrap no
# longer looks for the files. (2) The scan judges the SOURCE tree, never the pinned image a host boots or an already
# published bundle (GuardA binds tag to source). (3) A name assembled from two quoted halves, and a lowercase or
# otherwise respelled needle, are not matched: the needles are exact strings.
#
# Run: bash apps/web-platform/infra/inngest-carrier-vocabulary.test.sh
#
# Synthesized fixtures only (cq-test-fixtures-synthesized-only): the fixture tree is a copy of the real files into a
# temp dir; the real tree is never written.

set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$DIR/../../.." && pwd)"

passes=0
fails=0
total=0
pass() { passes=$((passes + 1)); total=$((total + 1)); printf '[ok] %s\n' "$1"; }
fail() { fails=$((fails + 1)); total=$((total + 1)); printf '[FAIL] %s\n' "$1" >&2; }

# Instrument self-test: drive both helpers once and require both counters to move, then reset.
pass "instrument self-test (pass arm)" >/dev/null
fail "instrument self-test (fail arm)" 2>/dev/null
if [[ "$passes" -ne 1 || "$fails" -ne 1 || "$total" -ne 2 ]]; then
  printf 'FATAL: instrument self-test failed: passes=%s fails=%s total=%s\n' "$passes" "$fails" "$total" >&2
  exit 2
fi
passes=0
fails=0
total=0

# Canonical assert_fixture_dir -- byte-identical copy (fixture-scan.py requires the verbatim body).
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

WF_REL=".github/workflows/build-inngest-bootstrap-image.yml"
SET_REL="apps/web-platform/infra/inngest-config-refresh-set.txt"
BOOT_REL="apps/web-platform/infra/inngest-bootstrap.sh"
VEC_REL="apps/web-platform/infra/vector.toml"
CHECK_SH_REL=".github/scripts/check-inngest-bootstrap-build.sh"
CHECK_YML_REL=".github/workflows/check-inngest-bootstrap-build.yml"
INSTALL_REL="apps/web-platform/infra/infra-config-install.sh"
SERVER_TF_REL="apps/web-platform/infra/server.tf"
FLIP_SH_REL="apps/web-platform/infra/inngest-cutover-flip.sh"
FLIP_SVC_REL="apps/web-platform/infra/inngest-cutover-flip.service"
# Files outside the derived carrier set that the scans also read: the build recipe, its twin and the refresh set (VOCABULARY + STEM),
# and the delivery path of the retired trio (STEM only).
RECIPE_FILES=("$WF_REL" "$CHECK_SH_REL" "$CHECK_YML_REL" "$SET_REL")
DELIVERY_FILES=(
  "apps/web-platform/infra/infra-config-apply.sh"
  "$INSTALL_REL"
  "apps/web-platform/infra/push-infra-config.sh"
  "apps/web-platform/infra/hooks.json.tmpl"
  "$SERVER_TF_REL"
  ".github/workflows/apply-deploy-pipeline-fix.yml"
)

# The retired identifiers, EXACT (a carrier may still say "plaintext" in an unrelated comment). One per element:
# the plaintext volume the FSM copied from, the staging mapper and mount, and the FSM's state paths and markers.
NEEDLES=(
  PLAIN_ID INNGEST_LUKS_PLAIN_VOLUME_ID
  STAGING_NAME inngest-redis-staging /mnt/data-luks STAGING_MNT
  PLAIN_MNT /mnt/data-plain INNGEST_LUKS_ADDITIVE_VOLUME_ID
  frozen-active /var/lib/inngest-luks-cutover /etc/default/inngest-luks-volumes SOLEUR_INNGEST_LUKS_CUTOVER
)
# The retired trio's stem, as code (comment lines are stripped before this match, so history prose stays legal).
TRIO_STEM='inngest-luks-cutover'
# Floor on the derived carrier set, set to the MEASURED green count (never below it): a derivation that silently drops a
# carrier must not read as clean. Retiring a carrier lowers this deliberately, in the same commit.
CARRIER_FLOOR=10

strip_comments() { grep -vE '^[[:space:]]*#' "$1" || true; }

# derive_carriers <repo-root> -> the carrier set, one repo-relative path per line (build recipe cp lines UNION refresh set).
derive_carriers() {
  local root="$1"
  { grep -oE '^[[:space:]]*cp apps/web-platform/infra/[A-Za-z0-9._-]+ ' "$root/$WF_REL" | awk '{print $2}'
    grep -vE '^[[:space:]]*(#|$)' "$root/$SET_REL"; } | sort -u
}

# g3_scan <repo-root> -> prints one `VIOLATION <tag> <detail>` line per finding and `CARRIERS <n>`; rc 0 iff none.
g3_scan() {
  local root="$1" n=0 v=0 rel f carriers hits
  [[ -r "$root/$WF_REL" ]] || { printf 'VIOLATION unreadable-workflow %s\n' "$WF_REL"; return 1; }
  [[ -r "$root/$SET_REL" ]] || { printf 'VIOLATION unreadable-refresh-set %s\n' "$SET_REL"; return 1; }
  carriers="$(derive_carriers "$root")"
  while IFS= read -r rel; do
    [[ -n "$rel" ]] || continue
    n=$((n + 1))
    f="$root/$rel"
    if [[ ! -r "$f" ]]; then
      printf 'VIOLATION carrier-missing %s\n' "$rel"; v=$((v + 1)); continue
    fi
    hits="$(grep -noF -f <(printf '%s\n' "${NEEDLES[@]}") -- "$f" | head -3 | tr '\n' ' ')"
    if [[ -n "$hits" ]]; then
      printf 'VIOLATION vocabulary %s: %s\n' "$rel" "$hits"; v=$((v + 1))
    fi
    if strip_comments "$f" | grep -qF -- "$TRIO_STEM"; then
      printf 'VIOLATION trio-named %s\n' "$rel"; v=$((v + 1))
    fi
  done <<< "$carriers"
  printf 'CARRIERS %s\n' "$n"
  if [[ "$n" -lt "$CARRIER_FLOOR" ]]; then
    printf 'VIOLATION carrier-floor derived %s carriers, floor %s\n' "$n" "$CARRIER_FLOOR"; v=$((v + 1))
  fi
  # The build recipe and its check twin carry both scans; the delivery path carries the stem scan only.
  for rel in "${RECIPE_FILES[@]}" "${DELIVERY_FILES[@]}"; do
    f="$root/$rel"
    [[ -r "$f" ]] || { printf 'VIOLATION unreadable %s\n' "$rel"; v=$((v + 1)); continue; }
    if strip_comments "$f" | grep -qF -- "$TRIO_STEM"; then
      printf 'VIOLATION trio-named %s\n' "$rel"; v=$((v + 1))
    fi
  done
  for rel in "${RECIPE_FILES[@]}"; do
    hits="$(grep -noF -f <(printf '%s\n' "${NEEDLES[@]}") -- "$root/$rel" | head -3 | tr '\n' ' ')"
    if [[ -n "$hits" ]]; then
      printf 'VIOLATION vocabulary %s: %s\n' "$rel" "$hits"; v=$((v + 1))
    fi
  done
  [[ "$v" -eq 0 ]]
}

# ---------------------------------------------------------------------------------------------------------------------
# 1. The real tree.
# ---------------------------------------------------------------------------------------------------------------------
real_out="$(g3_scan "$REPO_ROOT" 2>&1)"; real_rc=$?
if [[ "$real_rc" -eq 0 ]]; then pass "real tree: no baked carrier names the retired cutover vocabulary or the retired trio ($(grep -E '^CARRIERS ' <<<"$real_out"))"; else fail "real tree violates Guard 3: ${real_out}"; fi
real_n="$(sed -n 's/^CARRIERS //p' <<<"$real_out")"

# ---------------------------------------------------------------------------------------------------------------------
# 2. Fixture tree: a pristine copy of exactly the files the scan reads, mutated one row at a time.
# ---------------------------------------------------------------------------------------------------------------------
WORK="$(mktemp -d -t inngest-carrier-vocab.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT
assert_fixture_dir "$WORK"

# make_tree <dest> -- copy the scan's inputs and every derived carrier into <dest>, preserving repo-relative paths.
make_tree() {
  local dest="$1" rel
  assert_fixture_dir "$dest"
  while IFS= read -r rel; do
    [[ -n "$rel" ]] || continue
    mkdir -p "$dest/$(dirname "$rel")"
    cp "$REPO_ROOT/$rel" "$dest/$rel"
  done < <( { derive_carriers "$REPO_ROOT"; printf '%s\n' "$WF_REL" "$SET_REL" "${RECIPE_FILES[@]}" "${DELIVERY_FILES[@]}"; } | sort -u )
}

# tree_sum <dir> -> a checksum of every file's content and path, to prove a mutation landed.
tree_sum() { (cd "$1" && find . -type f -print0 | sort -z | xargs -0 cksum | cksum); }

# Mutation helpers. Each takes the fixture root from the row's global T and asserts it first.
append_line() { # <repo-relative file> <line>
  assert_fixture_dir "$T"
  printf '%s\n' "$2" >> "$T/$1"
}
drop_lines() { # <repo-relative file> <ERE of lines to delete>
  assert_fixture_dir "$T"
  grep -vE "$2" "$T/$1" > "$T/$1.new" || true
  mv "$T/$1.new" "$T/$1"
}
# cp_line <basename> -> a build-recipe staging line. The verb is assembled (c""p) because fixture-scan.py reads a literal
# `cp <path>` inside a string as a live copy and cannot prove the operand absolute.
cp_line() { printf '          %s apps/web-platform/infra/%s "$BUILD_DIR/%s"' "c""p" "$1" "$1"; }
add_carrier() { # <basename> <file content> -- a new file plus the cp line that makes it a derived carrier
  assert_fixture_dir "$T"
  printf '%s\n' "$2" > "$T/apps/web-platform/infra/$1"
  printf '%s\n' "$(cp_line "$1")" >> "$T/$WF_REL"
}

# kills <name> <mutation-function> <expected-tag> -> rc 0 iff the mutation LANDED and the scan went non-zero naming the
# expected violation tag (a no-op, a crash or a wrong-reason red is not a kill). Each row starts from a FRESH copy.
kills() {
  local name="$1" fn="$2" tag="$3" before out rc
  T="$WORK/$name"
  make_tree "$T"
  before="$(tree_sum "$T")"
  "$fn"
  if [[ "$(tree_sum "$T")" == "$before" ]]; then
    printf 'row %s: the mutation did not land\n' "$name" >&2; return 1
  fi
  out="$(g3_scan "$T" 2>&1)"; rc=$?
  if [[ "$rc" -ne 0 ]] && grep -qE "^VIOLATION ${tag}( |$)" <<<"$out"; then return 0; fi
  printf 'row %s: rc=%s, wanted tag %s: %s\n' "$name" "$rc" "$tag" "$out" >&2
  return 1
}
mutate() { # <name> <fn> <tag>
  if kills "$@" 2>/dev/null; then pass "mutation $1 killed (tag=$3)"; else fail "mutation $1 SURVIVED, did not land, or died for the wrong reason (wanted tag '$3'): $(kills "$@" 2>&1 | tail -1)"; fi
}
# expect_green <name> <fn> -- the mutation must LAND and the scan must stay GREEN (the scan must not over-block).
expect_green() {
  local name="$1" fn="$2" before out rc
  T="$WORK/$name"
  make_tree "$T"
  before="$(tree_sum "$T")"
  "$fn"
  if [[ "$(tree_sum "$T")" == "$before" ]]; then fail "must-pass $name: the edit did not land"; return; fi
  out="$(g3_scan "$T" 2>&1)"; rc=$?
  if [[ "$rc" -eq 0 ]]; then pass "must-pass $name stays GREEN"; else fail "must-pass $name violated (over-block): $out"; fi
}

# Control: the unmutated copy is GREEN (otherwise every kill below is a pre-existing red).
CTRL="$WORK/control"
make_tree "$CTRL"
ctrl_out="$(g3_scan "$CTRL" 2>&1)"; ctrl_rc=$?
if [[ "$ctrl_rc" -eq 0 ]]; then pass "control: the pristine fixture copy is GREEN"; else fail "control: the pristine fixture copy is RED -- every mutation row is meaningless: ${ctrl_out}"; fi

# Negative controls for the verdict helper itself (a mutate() whose verdict `if` is neutered passes everything):
# a no-op mutation must NOT be reported killed, and a landed but irrelevant one must not be either.
noop() { :; }
irrelevant() { append_line "$FLIP_SH_REL" 'echo unrelated'; }
if kills neg-noop noop vocabulary 2>/dev/null; then fail "negative control: a no-op mutation was reported killed"; else pass "negative control: a no-op mutation is not reported killed"; fi
if kills neg-irrelevant irrelevant vocabulary 2>/dev/null; then fail "negative control: an irrelevant mutation was reported killed"; else pass "negative control: an irrelevant mutation is not reported killed"; fi

# Rows 1..N: each retired identifier alone, in its own row, in a derived carrier.
needle_row() { append_line "$FLIP_SH_REL" "X=$NEEDLE"; }
for NEEDLE in "${NEEDLES[@]}"; do
  mutate "needle-${NEEDLE//[^A-Za-z0-9]/_}" needle_row vocabulary
done
# A needle inside a COMMENT of a baked carrier still reds: it is baked into the image. (The trio stem is the opposite:
# comments are stripped there, see P2.)
m_comment() { append_line "$FLIP_SH_REL" '# STAGING_NAME was the old staging mapper'; }
mutate comment-needle m_comment vocabulary
# The per-carrier scan is not first-hit: a SECOND new carrier, after a compliant first one, carries the staging mount.
m_second() { add_carrier inngest-newcarrier-a.sh 'echo ok'; add_carrier inngest-newcarrier-b.sh 'mount /mnt/data-luks'; }
mutate second-carrier m_second vocabulary
# The guard's own dispatch: an emptied derivation ("0 checked") must be RED, not green.
m_empty() { drop_lines "$WF_REL" 'cp apps/web-platform/infra/'; drop_lines "$SET_REL" '^[^#]'; }
mutate empty-derivation m_empty carrier-floor
# A derived carrier file disappears (a swap that keeps the cp line but loses the file must not pass).
m_missing() { assert_fixture_dir "$T"; rm -f "$T/apps/web-platform/infra/inngest-redis-bootstrap.sh"; }
mutate missing-carrier m_missing carrier-missing

# The retired trio, by every delivery path and every respelling.
m_set() { append_line "$SET_REL" 'apps/web-platform/infra/inngest-luks-cutover.sh'; }
mutate trio-refresh-set m_set trio-named
m_wf() { append_line "$WF_REL" "$(cp_line inngest-luks-cutover.timer)"; }
mutate trio-build-workflow m_wf trio-named
m_boot() { append_line "$BOOT_REL" 'install -m 0755 /tmp/inngest-luks-cutover.sh /usr/local/bin/inngest-luks-cutover.sh'; }
mutate trio-bootstrap-install m_boot trio-named
m_brace() { append_line "$BOOT_REL" 'install -m 0755 /tmp/inngest-luks-cutover.{sh,service,timer} /usr/local/bin/'; }
mutate trio-brace-form m_brace trio-named
m_loop() { append_line "$BOOT_REL" 'for e in sh service timer; do install /tmp/inngest-luks-cutover.$e /usr/local/bin/; done'; }
mutate trio-loop-form m_loop trio-named
m_bare() { append_line "$FLIP_SVC_REL" 'ExecStartPost=/bin/systemctl enable --now inngest-luks-cutover'; }
mutate trio-bare-unit-name-in-other-carrier m_bare trio-named
m_vec() { append_line "$VEC_REL" '  "inngest-luks-cutover",'; }
mutate trio-vector-tag m_vec trio-named
m_chk_sh() { append_line "$CHECK_SH_REL" "$(cp_line inngest-luks-cutover.service)"; }
mutate trio-check-script m_chk_sh trio-named
m_chk_yml() { append_line "$CHECK_YML_REL" '      - "apps/web-platform/infra/inngest-luks-cutover.sh"'; }
mutate trio-check-workflow m_chk_yml trio-named
m_dest() { append_line "$INSTALL_REL" '  ["/usr/local/bin/inngest-luks-cutover.sh"]="755 root:root"'; }
mutate trio-dest-spec m_dest trio-named
m_tf() { append_line "$SERVER_TF_REL" '      file("${path.module}/inngest-luks-cutover.sh"),'; }
mutate trio-web-trigger-set m_tf trio-named

# Must-PASS (non-canonical) rows: the scan must not over-block.
# P1: a carrier that says "plaintext" in an unrelated comment is allowed (the match is on the exact retired identifiers).
p1() { append_line "$FLIP_SH_REL" '# the plaintext path of the old design is gone; nothing here names it'; }
expect_green pass-plaintext-comment p1
# P2: a prose comment that names the retired trio (history) is allowed in a carrier and in the bootstrap; only code lines count.
p2() { append_line "$BOOT_REL" '# history: inngest-luks-cutover.sh was retired from the image'; append_line "$FLIP_SH_REL" '# sibling of the retired inngest-luks-cutover FSM'; }
expect_green pass-trio-in-comment p2
# P3: a compliant NEW carrier (non-canonical set member) is accepted and derived.
p3() { add_carrier inngest-newcarrier-c.sh 'echo ok'; }
expect_green pass-new-carrier p3
p3_out="$(g3_scan "$WORK/pass-new-carrier" 2>&1)"
if [[ "$(sed -n 's/^CARRIERS //p' <<<"$p3_out")" -eq $((real_n + 1)) ]]; then pass "must-pass: the new carrier is DERIVED (carrier count $((real_n + 1)))"; else fail "the new carrier was not derived: $p3_out"; fi

echo ""
echo "inngest-carrier-vocabulary.test.sh: ${passes} passed, ${fails} failed (${total} assertions)"

# Anti-vacuity floor (ADR-193): reports directly, never through pass/fail. 1 real-tree + 1 control + 2 negative controls
# + 13 needle rows + 1 comment-needle + 3 carrier-set rows + 11 trio rows + 4 must-pass = 36.
if [[ "$total" -lt 36 ]]; then
  printf '[FATAL] anti-vacuity floor: only %s assertions ran, floor is 36\n' "$total" >&2
  exit 1
fi
if [[ "$fails" -ne 0 ]]; then exit 1; fi
exit 0
