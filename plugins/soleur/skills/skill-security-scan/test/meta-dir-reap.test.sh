#!/usr/bin/env bash
# meta-dir-reap.test.sh — the startup age-reap for run-scan.sh's meta_dir
# (#6789) and the scratch-orphan sweep under TMPDIR (#6760).
#
# WHAT THIS GUARDS. Each run-scan.sh invocation creates
# ${XDG_RUNTIME_DIR:-/tmp}/skill-security-scan-<pid>/ and, before #6789, NOTHING
# ever removed it — measured 12,889 leaked dirs. The fix age-reaps OLDER
# siblings at startup.
#
# THE FIX IS NOT AN EXIT TRAP, AND THAT IS THE POINT. .scan-meta.json is GDPR
# Art. 32 evidence: override-mechanism.md tells the operator to reference the
# path AFTER the scan exits, so `trap 'rm -rf "$meta_dir"' EXIT` would delete
# the artifact the override flow needs (plan R1). The two load-bearing arms are
# therefore: (a) an OLD sibling is reaped, and (b) the CURRENT run's artifact
# STILL EXISTS after the process exits (AC8).
#
# Seams: SKILL_SCAN_META_BASE relocates the meta root into the test's temp dir;
# SKILL_SCAN_META_REAP_MIN sets the age floor. Fixtures are synthesized.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUN_SCAN="$SCRIPT_DIR/../scripts/run-scan.sh"

PASS=0
FAIL=0
ok()   { PASS=$((PASS + 1)); echo "  [ok] $1"; }
bad()  { FAIL=$((FAIL + 1)); echo "  [FAIL] $1" >&2; }

TESTROOT="$(mktemp -d -t meta-dir-reap.XXXXXXXX)"
trap 'rm -rf "$TESTROOT"' EXIT

META_BASE="$TESTROOT/meta"
mkdir -p "$META_BASE"

# The scratch sweep (#6760) runs over ${TMPDIR:-/tmp} — seal it in EVERY
# scan invocation below so no arm ever sweeps the host's real TMPDIR.
SCRATCH_META="$TESTROOT/tmp-meta"
SCRATCH="$TESTROOT/tmp"
mkdir -p "$SCRATCH_META" "$SCRATCH"

# A tiny, benign skill body — the scan's verdict is irrelevant here.
INPUT="$TESTROOT/skill.md"
printf '# Demo skill\n\nThis skill reads a file.\n' > "$INPUT"

run_scan() {
  SKILL_SCAN_META_BASE="$META_BASE" \
  SKILL_SCAN_META_REAP_MIN="${1:-1440}" \
  TMPDIR="$SCRATCH_META" \
    bash "$RUN_SCAN" "${2:-$INPUT}" 2>/dev/null
}

echo "=== run-scan.sh meta_dir age-reap (#6789) ==="

# --- Arm 1: an OLD sibling dir is reaped at startup ------------------------
old="$META_BASE/skill-security-scan-999001"
mkdir -p "$old"; echo '{}' > "$old/.scan-meta.json"
touch -d "-3000 minutes" "$old/.scan-meta.json" "$old"
run_scan 1440 >/dev/null
if [[ ! -e "$old" ]]; then
  ok "an old skill-security-scan-<pid> sibling is reaped at startup"
else
  bad "the old sibling dir was NOT reaped"
fi

# --- Arm 2: a RECENT sibling dir is NOT reaped -----------------------------
recent="$META_BASE/skill-security-scan-999002"
mkdir -p "$recent"; echo '{}' > "$recent/.scan-meta.json"
# left at current mtime → younger than the floor
run_scan 1440 >/dev/null
if [[ -e "$recent" ]]; then
  ok "a recent sibling dir is NOT reaped (age gate holds)"
else
  bad "a recent sibling dir was wrongly reaped"
fi

# --- Arm 3 (AC8): the CURRENT run's artifact survives after exit -----------
# This is the regression guard against a naive EXIT trap. The path run-scan
# prints must exist AFTER the process has fully exited.
out="$(run_scan 1440)"
meta_path="$(sed -n 's/^\.scan-meta\.json written to: //p' <<<"$out" | head -1)"
if [[ -n "$meta_path" && -f "$meta_path" ]]; then
  ok "AC8: the current run's .scan-meta.json exists after the process exits"
else
  bad "AC8: .scan-meta.json missing after exit (an EXIT trap would cause this); path='$meta_path'"
fi
# And it must live under the seam base, i.e. the reap logic honoured the seam.
if [[ -n "$meta_path" && "$meta_path" == "$META_BASE/"* ]]; then
  ok "the meta_dir honours SKILL_SCAN_META_BASE"
else
  bad "meta_path not under the seam base: '$meta_path'"
fi

# --- Arm 4: the reap NEVER removes the current run's own dir ----------------
# Even with an aggressively low floor (0 minutes — still clamped to 60, but
# the own-dir guarantee is independent of the floor), the run's own dir is
# created AFTER the reap, so its artifact must survive.
out="$(run_scan 0)"
meta_path="$(sed -n 's/^\.scan-meta\.json written to: //p' <<<"$out" | head -1)"
if [[ -n "$meta_path" && -f "$meta_path" ]]; then
  ok "the reap never targets the current run's own dir (floor=0)"
else
  bad "floor=0 destroyed the current run's own artifact; path='$meta_path'"
fi

# --- Arm 5: the fix is age-reap at startup, NOT an EXIT trap on meta_dir ----
# Source assertion (cq-assert-anchor-not-bare-token): a trap that rm's the
# meta_dir/meta_path on EXIT is the exact R1 regression. Full-line comments are
# stripped FIRST — this script's own prose legitimately quotes the forbidden
# `trap 'rm -rf "$meta_dir"' EXIT` shape to explain why it is forbidden, and so
# does run-scan.sh's, so a raw grep matches the explanation, not the code (the
# grep-matches-own-comment trap from work/SKILL.md).
TRAP_RE="trap.*rm.*(meta_dir|meta_path).*(EXIT|RETURN)"
code_only="$(grep -vE '^[[:space:]]*#' "$SCRIPT_DIR/../scripts/run-scan.sh")"
if grep -qE "$TRAP_RE" <<<"$code_only"; then
  bad "run-scan.sh traps rm on the meta_dir/meta_path — the R1 regression"
else
  ok "no EXIT/RETURN trap deletes the meta_dir (R1 respected)"
fi
# POSITIVE CONTROL: the SAME regex must MATCH when the forbidden shape is present,
# or a typo'd pattern reads "clean forever" and the negative arm is vacuous.
if grep -qE "$TRAP_RE" <<<"trap 'rm -rf \"\$meta_dir\"' EXIT"; then
  ok "the EXIT-trap regex is live (matches the forbidden shape)"
else
  bad "the EXIT-trap regex matches nothing — the negative arm is vacuous"
fi

# --- Arm 6: a NON-matching old dir is never reaped (name filter holds) ------
# The reap must target only skill-security-scan-<pid> dirs, never every stale
# dir in the meta base — that base defaults to $XDG_RUNTIME_DIR, shared with
# other tools.
other="$META_BASE/some-unrelated-dir"
mkdir -p "$other"; echo x > "$other/f"
touch -d "-3000 minutes" "$other/f" "$other"
run_scan 1440 >/dev/null
if [[ -e "$other" ]]; then
  ok "an old dir NOT named skill-security-scan-* is never reaped"
else
  bad "the reap deleted an unrelated dir — name filter missing"
fi

# --- Arm 7: the reap is uid-scoped (source anchor) --------------------------
# A foreign-owned dir cannot be synthesized without root, so assert the -user
# predicate is present on the reap's find (anchored on the predicate, not a
# bare word a comment could satisfy — cq-assert-anchor-not-bare-token).
reap_code="$(grep -vE '^[[:space:]]*#' "$SCRIPT_DIR/../scripts/run-scan.sh")"
if grep -qE 'skill-security-scan-.*|-user[[:space:]]' <<<"$reap_code" \
   && grep -qE '\-user[[:space:]]+"\$\(id -u\)"' <<<"$reap_code"; then
  ok "the meta_dir reap is scoped to the current uid (-user)"
else
  bad "the meta_dir reap has no -user predicate — could reap another user's dirs"
fi

echo "=== run-scan.sh scratch-orphan sweep under TMPDIR (#6760) ==="

# The scratch sweep runs over ${TMPDIR:-/tmp}, NOT the meta base: the
# skill-scan-* scratch families (skill-scan-input-*, skill-scan-results-*,
# skill-scan-XXXXXX + .code/.fm/.body/.req/.resp siblings) are created under
# TMPDIR by `mktemp -t`, and skill-security-scan-* meta dirs written under /tmp
# before XDG_RUNTIME_DIR was set are unreachable by the meta-base sweep (the
# env-flip crossover). Fixtures are synthesized under the seam $SCRATCH.

run_scan_tmp() {
  SKILL_SCAN_META_BASE="$META_BASE" \
  SKILL_SCAN_META_REAP_MIN="${1:-1440}" \
  TMPDIR="$SCRATCH" \
    bash "$RUN_SCAN" "${2:-$INPUT}" 2>/dev/null
}

# --- Arm 8: an old skill-scan-input-* FILE is reaped ------------------------
old_in="$SCRATCH/skill-scan-input-999101"
echo x > "$old_in"; touch -d "-3000 minutes" "$old_in"
run_scan_tmp 1440 >/dev/null
if [[ ! -e "$old_in" ]]; then
  ok "an old skill-scan-input-* file is reaped from TMPDIR"
else
  bad "the old skill-scan-input-* file was NOT reaped"
fi

# --- Arm 9: an old skill-scan-results-* DIR is reaped -----------------------
old_res="$SCRATCH/skill-scan-results-999102"
mkdir -p "$old_res"; echo '{}' > "$old_res/code-execution.json"
touch -d "-3000 minutes" "$old_res/code-execution.json" "$old_res"
run_scan_tmp 1440 >/dev/null
if [[ ! -e "$old_res" ]]; then
  ok "an old skill-scan-results-* dir is reaped from TMPDIR"
else
  bad "the old skill-scan-results-* dir was NOT reaped"
fi

# --- Arm 10: an old skill-scan-*.code-style sibling FILE is reaped ----------
old_sib="$SCRATCH/skill-scan-Ab12Cd.code"
echo x > "$old_sib"; touch -d "-3000 minutes" "$old_sib"
run_scan_tmp 1440 >/dev/null
if [[ ! -e "$old_sib" ]]; then
  ok "an old skill-scan-*.code sibling file is reaped from TMPDIR"
else
  bad "the old skill-scan-*.code sibling was NOT reaped"
fi

# --- Arm 11: the XDG-toggle crossover — an old skill-security-scan-* dir ----
# --- under TMPDIR is reaped -------------------------------------------------
old_xdg="$SCRATCH/skill-security-scan-999103"
mkdir -p "$old_xdg"; echo '{}' > "$old_xdg/.scan-meta.json"
touch -d "-3000 minutes" "$old_xdg/.scan-meta.json" "$old_xdg"
run_scan_tmp 1440 >/dev/null
if [[ ! -e "$old_xdg" ]]; then
  ok "an old skill-security-scan-* dir under TMPDIR is reaped (XDG crossover)"
else
  bad "the old skill-security-scan-* TMPDIR dir was NOT reaped"
fi

# --- Arm 12: an sss-write.* hook orphan is reaped ---------------------------
old_sss="$SCRATCH/sss-write.999104.err"
echo x > "$old_sss"; touch -d "-3000 minutes" "$old_sss"
run_scan_tmp 1440 >/dev/null
if [[ ! -e "$old_sss" ]]; then
  ok "an old sss-write.* hook err-capture is reaped from TMPDIR"
else
  bad "the old sss-write.* entry was NOT reaped"
fi

# --- Arm 13: a MID-AGE skill-scan-* entry is spared (age gate holds) --------
# 300 min < floor 1440: discriminates both an over-reap AND a floor shrink to
# a positive value below the gap — an age-0 fixture only discriminates +0.
mid="$SCRATCH/skill-scan-input-999105"
echo x > "$mid"; touch -d "-300 minutes" "$mid"
run_scan_tmp 1440 >/dev/null
if [[ -e "$mid" ]]; then
  ok "a mid-age skill-scan-* entry under TMPDIR is NOT reaped (age gate holds)"
else
  bad "a mid-age skill-scan-* entry was wrongly reaped"
fi

# --- Arm 14: an unrelated old entry under TMPDIR is NEVER reaped ------------
# The arm-6 counterpart for the scratch sweep — a post-group -o widening
# (`\) -o -name '*'`) satisfies NAME_RE's literal anchor while reaping every
# aged own-uid entry in TMPDIR; only a behavioral arm catches it.
unrel="$SCRATCH/some-unrelated-entry"
mkdir -p "$unrel"; echo x > "$unrel/f"
touch -d "-3000 minutes" "$unrel/f" "$unrel"
run_scan_tmp 1440 >/dev/null
if [[ -e "$unrel" ]]; then
  ok "an old entry NOT named like a producer family is never reaped"
else
  bad "the sweep deleted an unrelated entry — name filter missing"
fi

# --- Arm 15: a NESTED family-named entry is spared (depth bound) ------------
# -mindepth 1 -maxdepth 1 bounds the reap to top-level entries — a nested
# skill-scan-* inside a foreign tree must survive (TMPDIR is shared space).
mkdir -p "$SCRATCH/otherdir"
nested="$SCRATCH/otherdir/skill-scan-999106"
echo x > "$nested"; touch -d "-3000 minutes" "$nested" "$SCRATCH/otherdir"
run_scan_tmp 1440 >/dev/null
if [[ -e "$nested" ]]; then
  ok "a nested skill-scan-* below a foreign dir is NOT reaped (depth bound)"
else
  bad "the sweep reaped a nested entry — depth bound missing"
fi

# --- Arm 16: a backdated family-named positional INPUT survives -------------
# Behavioral pin for the own-scratch exclusion: the file is a reap candidate
# by name AND age (backdated past every floor), and survives only because
# `! -samefile "$INPUT"` excludes it. A glob metachar in the name proves the
# exclusion is inode-based, not a -path string/fnmatch compare. The sibling
# control is reaped in the SAME invocation — proving the sweep ran, not that
# it no-oped.
victim="$SCRATCH/skill-scan-input-[victim]"
printf '# scanned body\n' > "$victim"
touch -d "-3000 minutes" "$victim"
control="$SCRATCH/skill-scan-input-999107"
echo x > "$control"; touch -d "-3000 minutes" "$control"
out="$(run_scan_tmp 0 "$victim")"
meta_path="$(sed -n 's/^\.scan-meta\.json written to: //p' <<<"$out" | head -1)"
if [[ -e "$victim" && ! -e "$control" && -n "$meta_path" ]]; then
  ok "a backdated skill-scan-* positional INPUT survives (own-scratch exclusion is behavioral, not anchor-only)"
else
  bad "own-scratch exclusion wrong; exists=$(test -e "$victim" && echo yes) control=$(test -e "$control" && echo present || echo reaped) meta='$meta_path'"
fi

# --- Arm 17: the 60-minute floor clamp is behavioral -------------------------
# Mutant `_reap_min` verbatim (no clamp) reaps this <1-min entry under the
# test-seam floor 0 — `-mmin "+0"` matches ANY past mtime — so a fresh entry
# surviving a floor-0 scan is the clamp's only discriminating pin.
fresh_clamp="$SCRATCH/skill-scan-input-999108"
echo x > "$fresh_clamp"
run_scan_tmp 0 >/dev/null
if [[ -e "$fresh_clamp" ]]; then
  ok "the 60-minute floor clamp spares fresh entries under a floor-0 invocation"
else
  bad "the 60-minute clamp is missing — floor 0 reaped a fresh entry"
fi

# --- Arm 18: a non-numeric or octal floor never crashes the scan -------------
# The knob falls back on garbage and `10#`-normalizes leading zeros — either
# bug abandons the scan or silently bypasses the 60-min clamp BEFORE the meta
# line is emitted (a gate deny for every scanned write, on a benign env typo).
# The `08` fixture is discriminating, not just no-crash: a 30-min entry sits
# between the octal-legal floor (8) and the clamp (60) — under an unnormalized
# `08` the expansion error strands _reap_min as the literal "08" (find reads
# floor 8 → fixture reaped); normalized it clamps to 60 → fixture spared.
knob_fixture="$SCRATCH/skill-scan-input-999109"
echo x > "$knob_fixture"; touch -d "-30 minutes" "$knob_fixture"
for knob in abc 08; do
  out="$(run_scan_tmp "$knob")"
  if sed -n 's/^\.scan-meta\.json written to: //p' <<<"$out" | grep -q .; then
    ok "SKILL_SCAN_META_REAP_MIN=$knob still emits .scan-meta.json (floor normalised)"
  else
    bad "SKILL_SCAN_META_REAP_MIN=$knob crashed the scan before meta write"
  fi
done
if [[ -e "$knob_fixture" ]]; then
  ok "an octal-legal knob is normalised before the clamp (08 -> 8 -> floor 60)"
else
  bad "knob 08 bypassed the 60-min clamp — 10# normalization missing"
fi

# --- Arm 18b: the meta sweep's clamp is pinned too ----------------------------
# A fresh meta sibling under floor-0 survives only because _reap_min clamps
# before BOTH finds — a scratch-only clamp mutant reaps it.
fresh_meta="$META_BASE/skill-security-scan-999110"
mkdir -p "$fresh_meta"; echo '{}' > "$fresh_meta/.scan-meta.json"
run_scan 0 >/dev/null
if [[ -d "$fresh_meta" ]]; then
  ok "the 60-minute clamp also covers the meta_dir reap (fresh sibling spared)"
else
  bad "the meta reap ran unclamped — a peer's live meta_dir is wipeable"
fi

# --- Arm 19: source anchors for the scratch sweep ---------------------------
# Pin the load-bearing predicates on the live code (cq-assert-anchor-not-bare-
# token): the grouped -name arms, uid/age/depth predicates, and the
# ! -samefile own-scratch exclusions (INPUT/results_dir predate the reap,
# unlike meta_dir — the asymmetry that makes the exclusions load-bearing).
# The grouped predicate is written `\( -name … \)` in the source, so the ERE
# pins the literal backslashes via a char class (ERE `\(` is a literal paren,
# not `\` + `(` — an unescaped-backslash reading is how this anchor vacuated).
NAME_RE="[\\\\]\\( -name 'skill-security-scan-\\*' -o -name 'skill-scan-\\*' -o -name 'sss-write\\.\\*\\.err' [\\\\]\\)"
scratch_find="$(grep -vE '^[[:space:]]*#' "$SCRIPT_DIR/../scripts/run-scan.sh" \
  | grep -A10 'tmp_root=')"
if grep -qE "$NAME_RE" <<<"$scratch_find"; then
  ok "the TMPDIR sweep names all three families (-o grouped -name arms)"
else
  bad "the TMPDIR sweep is missing the grouped -name arms"
fi
for anchor in '-mindepth 1 -maxdepth 1' '-mmin' '-user "$(id -u)"'; do
  if grep -qF -- "$anchor" <<<"$scratch_find"; then
    ok "the TMPDIR sweep pins: $anchor"
  else
    bad "the TMPDIR sweep is missing predicate: $anchor"
  fi
done
# The `10#` token is pinned in its code spelling — a bare `10#` grep would
# match its own mention in the reap comments (anchor laundering; the same
# trap arm 5's comment-strip guards against).
for anchor in 'pwd -P' '10#${_reap_min}' '-e "$INPUT"' '-e "$results_dir"' \
              '-samefile "$INPUT"' '-samefile "$results_dir"'; do
  if grep -qF -- "$anchor" "$SCRIPT_DIR/../scripts/run-scan.sh"; then
    ok "the reap block pins: $anchor"
  else
    bad "the reap block is missing: $anchor"
  fi
done
# Meta-side predicates get the same anchor treatment (an `-amin` mutation is
# behaviorally invisible under touch -d's atime≈mtime).
meta_find="$(grep -vE '^[[:space:]]*#' "$SCRIPT_DIR/../scripts/run-scan.sh" \
  | grep -A6 'meta_root=')"
for anchor in '-mmin' '-type d' '-user "$(id -u)"'; do
  if grep -qF -- "$anchor" <<<"$meta_find"; then
    ok "the meta reap pins: $anchor"
  else
    bad "the meta reap is missing predicate: $anchor"
  fi
done
# Producer-prefix pin: every `mktemp -t`/`-dt` template under the skill's
# scripts/ must emit inside the sweep's name window — a new producer writing
# `mktemp -t some-other-name` orphans forever with no coverage. Flagless
# `mktemp` emits `tmp.*`, which tmp-classify.sh assigns to systemd-tmpfiles —
# outside the pin's scope by design.
drift="$(grep -hoE 'mktemp -[dt]+ "?[A-Za-z0-9_.*-]+' "$SCRIPT_DIR/../scripts/"*.sh \
  | awk '{print $NF}' | tr -d '"' | grep -v '^skill-scan-' || true)"
if [[ -z "$drift" ]]; then
  ok "every mktemp template under scripts/ emits a swept skill-scan-* name"
else
  bad "producer outside the sweep window: $drift"
fi
# Hook-side producer pin: the sss-write.*.err shape is literal-path
# construction in the write-hook, outside scripts/ — a rename there orphans
# the family while every arm above stays green.
hook_producer="$(git rev-parse --show-toplevel)/.claude/hooks/skill-security-scan-write.sh"
if grep -qE 'TMPDIR:-/tmp[^/]*/sss-write\.[^"]*\.err' "$hook_producer"; then
  ok "the write-hook's sss-write.* capture stays inside the sweep window"
else
  bad "the sss-write producer moved or renamed — sweep coverage silently lost"
fi
# POSITIVE CONTROLS: each anchor must MATCH a synthetic live-shaped line, or a
# typo'd pattern reads "clean forever" and every arm above is vacuous.
if grep -qE "$NAME_RE" <<<"find \"\$tmp_root\" \( -name 'skill-security-scan-*' -o -name 'skill-scan-*' -o -name 'sss-write.*.err' \)"; then
  ok "the grouped -name regex is live (matches the predicate shape)"
else
  bad "the grouped -name regex matches nothing — the anchor arm is vacuous"
fi
if grep -qF -- '-samefile "$INPUT"' <<<"find /tmp ! -samefile \"\$INPUT\" ! -samefile \"\$results_dir\""; then
  ok "the ! -samefile exclusion anchors are live (match the predicate shape)"
else
  bad "the ! -samefile anchors match nothing — the anchor arm is vacuous"
fi

echo "=== meta-dir-reap: $PASS passed, $FAIL failed ==="
[[ "$FAIL" -eq 0 ]] || exit 1
