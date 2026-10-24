#!/usr/bin/env bash
#
# Guard 3 (host-replace window prework, #10112 item 1 / Ref #9927) -- the retired plaintext-to-LUKS cutover
# vocabulary is absent from every image-baked carrier.
#
# PROPERTY. No file the inngest-bootstrap image bakes (and no member of the signed config-refresh set) names the
# retired plaintext volume, the staging mapper, or the staging mount, and none of the retired cutover trio
# (inngest-luks-cutover.{sh,service,timer}) is staged, baked, installed or refreshed any more.
#
# ASSEMBLY. The carrier set is DERIVED, never listed: the `cp apps/web-platform/infra/<file>` lines of
# build-inngest-bootstrap-image.yml (the same extraction the mint script and cloud-init-inngest-bootstrap.test.sh
# GuardA use) UNION the members of inngest-config-refresh-set.txt. One scan function (g3_scan) takes a repo root, so the
# SAME code judges the real tree and every mutated fixture copy.
#
# NOT COVERED HERE (deliberately). The STAGED list in cloud-init-inngest.yml still names the retired trio until the
# user_data PR (PR-D) lands; that file is user_data and is out of this change. PR-D adds the STAGED clause to this
# scan. Until then a stale STAGED entry is harmless: the staging copy is `docker cp ... || true` and the bootstrap no
# longer looks for the files.
#
# Run: bash apps/web-platform/infra/inngest-carrier-vocabulary.test.sh
#
# Synthesized fixtures only (cq-test-fixtures-synthesized-only): the fixture tree is a copy of the real carriers into a
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
CHECK_SH_REL=".github/scripts/check-inngest-bootstrap-build.sh"
CHECK_YML_REL=".github/workflows/check-inngest-bootstrap-build.yml"

# The retired identifiers, EXACT (a carrier may still say "plaintext" in an unrelated comment).
# PLAIN_ID / INNGEST_LUKS_PLAIN_VOLUME_ID: the plaintext volume the FSM copied from. STAGING_NAME / inngest-redis-staging:
# the staging mapper. /mnt/data-luks: the staging mount. Fixed strings, one per line (grep -F -f).
NEEDLES=$'PLAIN_ID\nINNGEST_LUKS_PLAIN_VOLUME_ID\nSTAGING_NAME\ninngest-redis-staging\n/mnt/data-luks'
# The retired trio, as code (comment lines are stripped before this match, so history prose stays legal).
TRIO_RE='inngest-luks-cutover\.(sh|service|timer)'
# Floor on the derived carrier set: a scan that derives nothing must not read as clean (10 carriers at the time of
# writing; the floor leaves room for a carrier retirement but not for a derivation that silently returns ~nothing).
CARRIER_FLOOR=8

strip_comments() { grep -vE '^[[:space:]]*#' "$1" || true; }

# g3_scan <repo-root> -> prints one `VIOLATION <tag> <detail>` line per finding and `CARRIERS <n>`; rc 0 iff none.
g3_scan() {
  local root="$1" wf set n=0 v=0 rel f carriers stripped
  wf="$root/$WF_REL"
  set="$root/$SET_REL"
  [[ -r "$wf" ]] || { printf 'VIOLATION unreadable-workflow %s\n' "$WF_REL"; return 1; }
  [[ -r "$set" ]] || { printf 'VIOLATION unreadable-refresh-set %s\n' "$SET_REL"; return 1; }
  carriers="$( { grep -oE '^[[:space:]]*cp apps/web-platform/infra/[A-Za-z0-9._-]+ ' "$wf" | awk '{print $2}'; \
                 grep -vE '^[[:space:]]*(#|$)' "$set"; } | sort -u )"
  while IFS= read -r rel; do
    [[ -n "$rel" ]] || continue
    n=$((n + 1))
    f="$root/$rel"
    if [[ ! -r "$f" ]]; then
      printf 'VIOLATION carrier-missing %s\n' "$rel"; v=$((v + 1)); continue
    fi
    if grep -nF -f <(printf '%s\n' "$NEEDLES") -- "$f" >/dev/null; then
      printf 'VIOLATION vocabulary %s: %s\n' "$rel" "$(grep -noF -f <(printf '%s\n' "$NEEDLES") -- "$f" | head -3 | tr '\n' ' ')"
      v=$((v + 1))
    fi
  done <<< "$carriers"
  printf 'CARRIERS %s\n' "$n"
  [[ "$n" -ge "$CARRIER_FLOOR" ]] || { printf 'VIOLATION carrier-floor derived %s carriers, floor %s\n' "$n" "$CARRIER_FLOOR"; v=$((v + 1)); }
  # The retired trio must not be staged, baked, installed or refreshed (comment lines stripped).
  for rel in "$WF_REL" "$SET_REL" "$BOOT_REL" "$CHECK_SH_REL" "$CHECK_YML_REL"; do
    f="$root/$rel"
    [[ -r "$f" ]] || { printf 'VIOLATION unreadable %s\n' "$rel"; v=$((v + 1)); continue; }
    stripped="$(strip_comments "$f")"
    if grep -qE "$TRIO_RE" <<<"$stripped"; then
      printf 'VIOLATION trio-named %s\n' "$rel"; v=$((v + 1))
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
if [[ "$real_n" =~ ^[0-9]+$ && "$real_n" -ge "$CARRIER_FLOOR" ]]; then pass "real tree: the derived carrier set is non-vacuous ($real_n >= $CARRIER_FLOOR)"; else fail "real tree: derived carrier count '$real_n' is below the floor $CARRIER_FLOOR"; fi

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
  mkdir -p "$dest/.github/workflows" "$dest/.github/scripts" "$dest/apps/web-platform/infra"
  for rel in "$WF_REL" "$SET_REL" "$BOOT_REL" "$CHECK_SH_REL" "$CHECK_YML_REL"; do
    cp "$REPO_ROOT/$rel" "$dest/$rel"
  done
  while IFS= read -r rel; do
    [[ -n "$rel" ]] || continue
    cp "$REPO_ROOT/$rel" "$dest/$rel"
  done < <( { grep -oE '^[[:space:]]*cp apps/web-platform/infra/[A-Za-z0-9._-]+ ' "$REPO_ROOT/$WF_REL" | awk '{print $2}'; \
              grep -vE '^[[:space:]]*(#|$)' "$REPO_ROOT/$SET_REL"; } | sort -u )
}

# mutate <name> <mutation-function> <expected-tag> -- the function edits the fixture tree under "$T"; the row is KILLED
# only if the scan goes non-zero AND names the expected violation tag (a crash or a wrong-reason red is not a kill).
# Each row starts from a FRESH copy, so no row inherits another's mutation.
mutate() {
  local name="$1" fn="$2" tag="$3" out rc
  T="$WORK/$name"
  make_tree "$T"
  "$fn"
  out="$(g3_scan "$T" 2>&1)"; rc=$?
  if [[ "$rc" -ne 0 ]] && grep -qE "^VIOLATION ${tag}( |$)" <<<"$out"; then
    pass "mutation $name killed (rc=$rc, tag=$tag)"
  else
    fail "mutation $name SURVIVED or died for the wrong reason (rc=$rc, wanted tag '$tag'): $out"
  fi
}
# after_flip_timer <file> <line> -- append <line> after the staging line of the flip timer in a copy of the build recipe.
after_flip_timer() {
  local f="$1" line="$2" tmp
  tmp="$f.new"
  awk -v ins="$line" '{print} /cp apps\/web-platform\/infra\/inngest-cutover-flip\.timer /{print ins}' "$f" > "$tmp" && mv "$tmp" "$f"
}

# Control: the unmutated copy is GREEN (otherwise every kill below is a pre-existing red).
CTRL="$WORK/control"
make_tree "$CTRL"
ctrl_out="$(g3_scan "$CTRL" 2>&1)"; ctrl_rc=$?
if [[ "$ctrl_rc" -eq 0 ]]; then pass "control: the pristine fixture copy is GREEN"; else fail "control: the pristine fixture copy is RED -- every mutation row is meaningless: ${ctrl_out}"; fi

# Row 1: re-add PLAIN_ID= to a carrier.
m1() { printf 'PLAIN_ID="${X:-}"\n' >> "$T/apps/web-platform/infra/inngest-cutover-flip.sh"; }
mutate m1-plain-id m1 vocabulary
# Row 1b: the staging mapper name in a different carrier (a unit file): the scan is per-carrier, not first-hit.
m1b() { printf 'readonly STAGING_NAME=inngest-redis-staging\n' >> "$T/apps/web-platform/infra/inngest-cutover-flip.service"; }
mutate m1b-staging-name m1b vocabulary
# Row 2: re-add the retired script to the refresh set.
m2() { printf 'apps/web-platform/infra/inngest-luks-cutover.sh\n' >> "$T/$SET_REL"; }
mutate m2-refresh-set m2 trio-named
# Row 3: a SECOND new carrier, after a compliant first one, whose file carries the staging mount.
m3() {
  printf 'echo ok\n' > "$T/apps/web-platform/infra/inngest-newcarrier-a.sh"
  printf 'mount /mnt/data-luks\n' > "$T/apps/web-platform/infra/inngest-newcarrier-b.sh"
  after_flip_timer "$T/$WF_REL" '          cp apps/web-platform/infra/inngest-newcarrier-a.sh "$BUILD_DIR/inngest-newcarrier-a.sh"'
  after_flip_timer "$T/$WF_REL" '          cp apps/web-platform/infra/inngest-newcarrier-b.sh "$BUILD_DIR/inngest-newcarrier-b.sh"'
}
mutate m3-second-carrier m3 vocabulary
# Row 4: the guard's own dispatch -- an emptied derivation ("0 checked") must be RED, not green.
m4() {
  grep -v 'cp apps/web-platform/infra/' "$T/$WF_REL" > "$T/wf.new" || true; mv "$T/wf.new" "$T/$WF_REL"
  grep -E '^[[:space:]]*(#|$)' "$T/$SET_REL" > "$T/set.new" || true; mv "$T/set.new" "$T/$SET_REL"
}
mutate m4-empty-derivation m4 carrier-floor
# Row 5: a cp line of the retired trio comes back in the build workflow.
m5() { after_flip_timer "$T/$WF_REL" '          cp apps/web-platform/infra/inngest-luks-cutover.timer "$BUILD_DIR/inngest-luks-cutover.timer"'; }
mutate m5-workflow-trio m5 trio-named
# Row 6: the bootstrap install of the retired trio comes back.
m6() { printf 'install -m 0755 /tmp/inngest-luks-cutover.sh /usr/local/bin/inngest-luks-cutover.sh\n' >> "$T/$BOOT_REL"; }
mutate m6-bootstrap-install m6 trio-named
# Row 7: the check script (the build workflow's twin) re-stages the retired trio.
m7() { printf 'cp apps/web-platform/infra/inngest-luks-cutover.service "$BUILD_DIR/inngest-luks-cutover.service"\n' >> "$T/$CHECK_SH_REL"; }
mutate m7-check-script m7 trio-named
# Row 8: a derived carrier file disappears (a swap that keeps the cp line but loses the file must not pass).
m8() { rm -f "$T/apps/web-platform/infra/inngest-redis-bootstrap.sh"; }
mutate m8-missing-carrier m8 carrier-missing

# Must-PASS (non-canonical) rows: the scan must not over-block.
# P1: a carrier that says "plaintext" in an unrelated comment is allowed (the match is on the exact retired identifiers).
P1="$WORK/pass-plaintext-comment"
make_tree "$P1"
printf '# the plaintext path of the old design is gone; nothing here names it\n' >> "$P1/apps/web-platform/infra/inngest-cutover-flip.sh"
p1_out="$(g3_scan "$P1" 2>&1)"; p1_rc=$?
if [[ "$p1_rc" -eq 0 ]]; then pass "must-pass: a carrier mentioning 'plaintext' in an unrelated comment stays GREEN"; else fail "must-pass violated (over-block on the word 'plaintext'): $p1_out"; fi
# P2: a prose comment that names the retired trio in the bootstrap (history) is allowed; only code lines count.
P2="$WORK/pass-trio-in-comment"
make_tree "$P2"
printf '# history: inngest-luks-cutover.sh was retired from the image\n' >> "$P2/$BOOT_REL"
p2_out="$(g3_scan "$P2" 2>&1)"; p2_rc=$?
if [[ "$p2_rc" -eq 0 ]]; then pass "must-pass: a comment that names the retired trio in the bootstrap stays GREEN"; else fail "must-pass violated (over-block on a history comment): $p2_out"; fi
# P3: a compliant NEW carrier (non-canonical set member) is accepted.
P3="$WORK/pass-new-carrier"
make_tree "$P3"
printf 'echo ok\n' > "$P3/apps/web-platform/infra/inngest-newcarrier-c.sh"
after_flip_timer "$P3/$WF_REL" '          cp apps/web-platform/infra/inngest-newcarrier-c.sh "$BUILD_DIR/inngest-newcarrier-c.sh"'
p3_out="$(g3_scan "$P3" 2>&1)"; p3_rc=$?
if [[ "$p3_rc" -eq 0 && "$(sed -n 's/^CARRIERS //p' <<<"$p3_out")" -eq $((real_n + 1)) ]]; then pass "must-pass: a compliant new carrier is derived and accepted ($((real_n + 1)) carriers)"; else fail "must-pass violated (new carrier rejected or not derived): $p3_out"; fi

echo ""
echo "inngest-carrier-vocabulary.test.sh: ${passes} passed, ${fails} failed (${total} assertions)"

# Anti-vacuity floor (ADR-193): reports directly, never through pass/fail. 2 real-tree + control + 9 mutation rows
# + 3 must-pass rows = 15.
[[ "$total" -ge 15 ]] || { printf '[FATAL] anti-vacuity floor: only %s assertions ran, floor is 15\n' "$total" >&2; exit 1; }
[[ "$fails" -eq 0 ]] || exit 1
exit 0
