#!/usr/bin/env bash
# meta-dir-reap.test.sh — the startup age-reap for run-scan.sh's meta_dir (#6789).
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

# A tiny, benign skill body — the scan's verdict is irrelevant here.
INPUT="$TESTROOT/skill.md"
printf '# Demo skill\n\nThis skill reads a file.\n' > "$INPUT"

run_scan() {
  SKILL_SCAN_META_BASE="$META_BASE" \
  SKILL_SCAN_META_REAP_MIN="${1:-1440}" \
    bash "$RUN_SCAN" "$INPUT" 2>/dev/null
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
# Even with an aggressively low floor (0 minutes → everything is "old"), the
# run's own dir is created AFTER the reap, so its artifact must survive.
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

echo "=== meta-dir-reap: $PASS passed, $FAIL failed ==="
[[ "$FAIL" -eq 0 ]] || exit 1
