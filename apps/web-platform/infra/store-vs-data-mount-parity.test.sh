#!/usr/bin/env bash
# Guard 3 (#8386) — every MOUNT-SOURCE RESOLUTION in the repo agrees on the three invariants
# that were each wrong in production and were fixed together in 0d97ede5c (#8019, probe_schema=8).
#
# PROPERTY. A block that resolves *a mount source to the Hetzner volume alias backing it* --
# an `lsblk` inverse walk plus a `scsi-0HC_Volume_*` reverse map -- must (1) COUNT THE LEAVES of
# the inverse tree rather than take the last row, (2) scope the reverse map to the Hetzner
# namespace, and (3) COUNT the by-id hits rather than accept the first match. Each of those was
# a confident answer naming a volume the mount was NOT on, on a gate whose next step destroys
# that volume.
#
# THE POPULATION IS DERIVED, NEVER LISTED. Precedent: scripts/betterstack-ingest-parity.test.sh,
# whose first revision carried a hand-written six-file array that modelled ONE of two sources and
# so "reports agreement it never checked".
#
# AND THE DERIVATION IS SCOPED TO THE RESOLUTION SHAPE, NOT TO THE `scsi-0HC_Volume_*` GLOB --
# that distinction is this guard's correctness, not a detail. Ten-plus files mention that glob,
# and apps/web-platform/infra/git-data-bootstrap.sh deliberately does a first-match `break` over
# it. That code is RIGHT: it answers a different question ("which attached volume is LUKS?",
# discriminated by `cryptsetup isLuks`), not "which volume backs this mount?". A glob-scoped
# guard would redden correct code, which is the precedent's other recorded failure mode. So the
# predicate is: an `lsblk` inverse walk (`-s` with `-o NAME`) AND a `scsi-0HC_Volume_*` reverse
# map inside the SAME resolution block. git-data-bootstrap.sh is asserted as a must-PASS control
# below, so a re-scoped predicate that swept it back in would red HERE rather than in CI.
#
# Parity is over the three INVARIANTS, not over bytes: the two copies legitimately differ in
# variable names (data_mount_base vs STORE_MOUNT_BASE), comments, whitespace, and in one copy's
# Terraform `$${...}` escaping.
#
# Static + pure bash. No network, no docker, no root.
# Run: bash apps/web-platform/infra/store-vs-data-mount-parity.test.sh
set -uo pipefail
export LC_ALL=C

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$ROOT" || { printf '[FATAL] cannot cd to repo root\n' >&2; exit 2; }

PASS=0
FAIL=0
pass() { PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf 'FAIL: %s\n' "$1"; }

# Positive control (ADR-193): drive both helpers once and refuse to continue unless both
# counters move. Reported with printf + exit, never through the helpers it backstops.
_p=$PASS; _f=$FAIL
pass 'self-check: pass() increments (expected)'
fail 'self-check: fail() increments (EXPECTED, not a defect)'
if [ $((PASS - _p)) -ne 1 ] || [ $((FAIL - _f)) -ne 1 ]; then
  printf '[FATAL] verdict helpers are not counting\n' >&2
  exit 1
fi
PASS=$_p; FAIL=$_f

# The inverse walk, as the shipped command spells it: -s (inverse tree) with -o NAME, and no -d.
WALK_RE='lsblk[[:space:]]+-[a-z]*s[a-z]*o[[:space:]]+NAME'
# The reverse map's own loop header. DERIVATION is deliberately scoped to "a by-id walk", not to
# the Hetzner-namespaced glob: making the namespace part of the MEMBERSHIP test would let
# mutation 2 (drop the scope from one copy) shrink the population instead of reddening an
# invariant, so the guard would go green the moment a third member covered the floor. Membership
# asks "is this a mount-source resolution?"; the namespace is an INVARIANT asserted below.
# `by[-_]?id` because one copy globs a LITERAL /dev/disk/by-id root and the other globs a
# variable named byid_dir -- membership must not turn on which spelling a copy chose.
MAP_RE='for[[:space:]]+[A-Za-z_][A-Za-z0-9_]*[[:space:]]+in[[:space:]]+[^#]*by[-_]?id'
# The scoped form, which every derived member must use.
SCOPED_MAP_RE='for[[:space:]]+[A-Za-z_][A-Za-z0-9_]*[[:space:]]+in[[:space:]]+.*scsi-0HC_Volume_\*'
# How far past the walk the reverse map may live before this stops being "the same block".
WINDOW=90

# `--untracked` because `git grep` is INDEX-scoped by default: a resolution a developer just
# wrote is invisible until staged, so a local or pre-commit run would certify parity over a
# population that excludes the new file. Tests, fixtures and knowledge-base are excluded because
# they legitimately carry historical and synthetic copies of this code.
mapfile -t CANDIDATES < <(git grep -lE --untracked "$WALK_RE" -- . \
  ':!knowledge-base' ':!tests' ':!*.test.sh' ':!*.test.ts' ':!scripts/fixtures' ':!plugins' | sort)

MEMBERS=()
declare -A WINDOW_OF=()
for f in "${CANDIDATES[@]}"; do
  start="$(grep -nE "$WALK_RE" "$f" | head -1 | cut -d: -f1)"
  [ -n "$start" ] || continue
  end=$((start + WINDOW))
  blk="$(sed -n "${start},${end}p" "$f")"
  grep -qE "$MAP_RE" <<<"$blk" || continue
  MEMBERS+=("$f")
  WINDOW_OF["$f"]="$blk"
done

# PRINT WHAT WAS DERIVED. A future third member must be visible rather than silently averaged in.
printf -- '--- derived mount-source resolutions (lsblk inverse walk + Hetzner by-id reverse map in the same block) ---\n'
for f in "${MEMBERS[@]}"; do
  printf '    %s  (block starts at line %s)\n' "$f" "$(grep -nE "$WALK_RE" "$f" | head -1 | cut -d: -f1)"
done
printf -- '--- candidates carrying the walk but no in-block reverse map: %s ---\n' \
  "$(( ${#CANDIDATES[@]} - ${#MEMBERS[@]} ))"

# A derived population can be empty for reasons that have nothing to do with the property (a
# path rename, a broken regex, a bad CWD) -- and empty would otherwise report a clean sweep over
# nothing. The floor is ABSOLUTE and ratchets upward. Measured at write time: 2
# (inngest-bootstrap.sh, and the heartbeat block in cloud-init-registry.yml).
MIN_FILES=2
if [ "${#MEMBERS[@]}" -lt "$MIN_FILES" ]; then
  printf '\n[FATAL] derived only %s mount-source resolution(s), floor is %s -- refusing to certify parity over a population this small (path rename? broken regex? wrong CWD?)\n' \
    "${#MEMBERS[@]}" "$MIN_FILES" >&2
  exit 1
fi
pass "derived ${#MEMBERS[@]} mount-source resolution(s) from the tree (floor ${MIN_FILES})"

for f in "${MEMBERS[@]}"; do
  blk="${WINDOW_OF[$f]}"

  # --- Invariant 1: COUNT THE LEAVES of the inverse tree -----------------------------------
  # `lsblk -s` on md/RAID or multipath emits a FORKED inverse tree -- two ancestors at the SAME
  # depth -- and a last-non-empty read picks one ARBITRARILY. Measured against the real probe
  # body with md0 over sdb+sdc, each carrying its own Hetzner alias: the emitter reported a
  # confident base naming a volume the mount is NOT on.
  if grep -qE 'lsblk[[:space:]]+-i[a-z]*s[a-z]*o[[:space:]]+NAME' <<<"$blk"; then
    pass "$f: the walk is ASCII (-i) -- box-drawing glyphs make a byte depth differ at equal logical depth"
  else
    fail "$f: the inverse walk is not -i (ASCII); the depth prefix is locale-dependent without it"
  fi
  if grep -qE 'lsblk[[:space:]]+-[a-z]*d[a-z]*o[[:space:]]+NAME' <<<"$blk"; then
    fail "$f: the walk carries -d, which prints ONE node instead of the child->parent chain"
  else
    pass "$f: the walk has no -d (it prints the full child->parent chain)"
  fi
  if grep -qF 'dep[i + 1] <= dep[i]' <<<"$blk"; then
    pass "$f: leaves are identified by adjacency (nothing descends from the row)"
  else
    fail "$f: no leaf predicate -- a last-row read picks one ancestor of a FORKED tree arbitrarily"
  fi
  if grep -qE 'cnt[[:space:]]*>[[:space:]]*1' <<<"$blk" && grep -qF '__AMBIGUOUS__' <<<"$blk"; then
    pass "$f: more than one leaf yields __AMBIGUOUS__, never a confident base"
  else
    fail "$f: a multi-leaf tree does not resolve to __AMBIGUOUS__"
  fi

  # --- Invariant 2: the reverse map is scoped to the HETZNER NAMESPACE ----------------------
  # Measured: a whole-by-id walk returns THREE aliases for one device (an eui form and two model
  # forms), so an unconstrained map is multi-valued and needs an arbitrary tiebreak.
  if grep -qE "$SCOPED_MAP_RE" <<<"$blk"; then
    pass "$f: the reverse map is scoped to scsi-0HC_Volume_*"
  else
    fail "$f: the reverse map is not Hetzner-namespace-scoped"
  fi
  if grep -qE 'for[[:space:]]+[A-Za-z_][A-Za-z0-9_]*[[:space:]]+in[[:space:]]+[^#]*by-id[/"]*\*' <<<"$blk"; then
    fail "$f: an UNSCOPED by-id walk is present -- it is multi-valued for a single device"
  else
    pass "$f: no unscoped /dev/disk/by-id/* walk in the block"
  fi

  # --- Invariant 3: COUNT the hits, never take the first match ------------------------------
  # Counting instead of asserting single-valuedness is what keeps this a measurement rather than
  # a premise -- the #8005 class, which cost five host replaces by shipping an unverified one.
  if grep -qE '[A-Za-z_][A-Za-z0-9_]*hits[A-Za-z0-9_]*=\$\(\(' <<<"$blk"; then
    pass "$f: the reverse map increments a hit COUNTER"
  else
    fail "$f: no hit counter -- the map cannot tell one alias from several"
  fi
  if grep -qE '\-eq[[:space:]]+0' <<<"$blk" && grep -qE '\-gt[[:space:]]+1' <<<"$blk"; then
    pass "$f: the counter discriminates 0 hits (__NOMATCH__) from >1 (__AMBIGUOUS__)"
  else
    fail "$f: the hit counter is not compared against both 0 and >1"
  fi
  if grep -qE '^[[:space:]]*break([[:space:]]|$)' <<<"$blk"; then
    fail "$f: a first-match \`break\` short-circuits the reverse map -- >1 alias reads as 1"
  else
    pass "$f: no first-match break in the reverse map"
  fi
done

# --- Must-PASS control M1: the LUKS-SELECTION walk is NOT a mount-source resolution ----------
# git-data-bootstrap.sh first-matches over the same glob, correctly, because it answers "which
# attached volume is LUKS?" (discriminated by `cryptsetup isLuks`) rather than "which volume
# backs this mount?". A guard that reddens here is scoped to the wrong predicate. Asserted as
# BOTH halves: the file really does carry the glob and the break (so the control is not vacuous),
# and it is really absent from the derived population.
CONTROL="apps/web-platform/infra/git-data-bootstrap.sh"
if [ -f "$CONTROL" ]; then
  if grep -qE "$SCOPED_MAP_RE" "$CONTROL" && grep -qE '^[[:space:]]*break([[:space:]]|$)' "$CONTROL"; then
    pass "M1 control is non-vacuous: $CONTROL does carry a first-match by-id walk"
  else
    fail "M1 control is vacuous: $CONTROL no longer carries the first-match by-id walk this control exists to exempt"
  fi
  _in_pop=0
  for f in "${MEMBERS[@]}"; do [ "$f" = "$CONTROL" ] && _in_pop=1; done
  if [ "$_in_pop" -eq 0 ]; then
    pass "M1 $CONTROL is NOT in the derived population (LUKS selection, not mount-source resolution)"
  else
    fail "M1 $CONTROL was swept into the population -- the predicate is scoped to the glob, not the resolution shape"
  fi
else
  fail "M1 control file $CONTROL is missing -- the exemption this guard's scope rests on cannot be checked"
fi

printf '\nfiles=%s pass=%s fail=%s\n' "${#MEMBERS[@]}" "$PASS" "$FAIL"
if [ "$FAIL" -gt 0 ]; then
  printf 'RESULT: FAIL (%s/%s assertions failed)\n' "$FAIL" "$((PASS + FAIL))" >&2
  exit 1
fi
printf 'RESULT: PASS (%s/%s assertions over %s mount-source resolution(s))\n' \
  "$PASS" "$((PASS + FAIL))" "${#MEMBERS[@]}"
