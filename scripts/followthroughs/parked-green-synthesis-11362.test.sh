#!/usr/bin/env bash
# Companion suite for scripts/followthroughs/parked-green-synthesis-11362.sh.
#
# Registered EXPLICITLY in scripts/test-all.sh (the orphan-suite class —
# scripts/followthroughs/*.test.sh is not in SUITE_GLOBS). The probe is
# NOTIFY-ONLY (never 0/1): its verdicts are the sweeper's words NOT YET /
# CANNOT ESTABLISH / ACTION REQUIRED, and the convention requires a notify-only
# probe to assert that contract in its own suite — an exit-code contract
# nothing drives is a comment. A vacuous PASS here lets a wrong verdict either
# stall the wake silently or cry wolf daily on the #11362 tracker.
#
# ── WHY THE ARMS RUN OVER A SANDBOX TREE ─────────────────────────────────────
# The probe resolves REPO_ROOT from BASH_SOURCE and reads ONE repo-relative
# path (knowledge-base/marketing/distribution-content/<file>). Copying the
# probe plus a per-row fixture under a mktemp tree drives every status the
# state space has — the live tree's file is committed `status: parked`, so
# draft/scheduled/bogus/missing rows are unreachable without writing the real
# file mid-suite (a suite that mutates the corpus it measures is the #6760
# class). SOLEUR_PROBE_TODAY is the probe's own documented clock seam: the
# sweeper forwards only PATH + declared secrets, so in production the real
# clock wins and only this harness can hold it still.

set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

REPO_ROOT="$(git rev-parse --show-toplevel)"
PROBE="$REPO_ROOT/scripts/followthroughs/parked-green-synthesis-11362.sh"
DIST_REL="knowledge-base/marketing/distribution-content/2026-11-19-first-we-made-green-mean-something.md"
WINDOW="2026-11-19"

passes=0
fails=0
pass() { passes=$((passes + 1)); echo "[ok]   $1"; }
fail() { fails=$((fails + 1)); echo "[FAIL] $1"; }
abort() { printf 'harness: %s\n' "$1" >&2; exit 2; }

[[ -x "$PROBE" ]] || abort "the probe is missing or not executable at $PROBE"

SBX="$(mktemp -d "$TMPDIR/pgs-11362.XXXXXX")" || abort "mktemp failed"
trap 'rm -rf "$SBX"' EXIT
mkdir -p "$SBX/scripts/followthroughs" "$SBX/knowledge-base/marketing/distribution-content" \
  || abort "sandbox layout failed"
cp "$PROBE" "$SBX/scripts/followthroughs/" || abort "probe copy failed"
SPROBE="$SBX/scripts/followthroughs/parked-green-synthesis-11362.sh"
DF="$SBX/$DIST_REL"

# mkfx <status> — one well-formed distribution file carrying the given status.
mkfx() {
  cat > "$DF" <<EOF
---
title: "T"
type: pillar
publish_date: 2026-11-19
channels: x, bluesky
status: $1
issue_reference: "#11362"
---

## X/Twitter Thread
body
EOF
}

# expect <name> <today> <fixture-statement> <want-rc>
# Every row also asserts the never-0/never-1 invariant: a notify-only probe
# must never take the sweeper's close (0) or FAIL (1) verbs.
run_row() {
  local name="$1" today="$2" want="$3"
  local rc out
  out="$(SOLEUR_PROBE_TODAY="$today" bash "$SPROBE" 2>&1)"
  rc=$?
  if [[ $rc -eq 0 || $rc -eq 1 ]]; then
    fail "$name: never-0/never-1 violated (rc=$rc)"
    return
  fi
  if [[ "$rc" == "$want" ]]; then
    pass "$name (rc=$rc)"
  else
    fail "$name: want rc=$want got rc=$rc — ${out:0:120}"
  fi
}

# ── Mutation matrix (plan Guard Contract rows) ──────────────────────────────
mkfx parked;    run_row "M2 pre-window parked is NOT YET"            "2026-10-28" 2
mkfx parked;    run_row "M2 in-window parked is ACTION REQUIRED"     "$WINDOW"    5
mkfx parked;    run_row "M2 day-after-window parked is ACTION REQ"   "2026-11-20" 5
mkfx draft;     run_row "M3 in-window draft is ACTION REQUIRED"      "2026-11-20" 5
mkfx scheduled; run_row "M4 in-window scheduled must-PASS at 2"      "2026-11-20" 2
mkfx published; run_row "in-window published is NOT YET"             "2026-11-25" 2
mkfx bogus;     run_row "unexpected status fails safe at 5"          "2026-11-20" 5
mkfx scheduled; run_row "early flip pre-window is NOT YET"           "2026-10-28" 2

# ── M5: the probe names its inability, never improvises ─────────────────────
rm -f "$DF";    run_row "M5 missing file is CANNOT ESTABLISH"        "2026-11-20" 3
printf 'no frontmatter\n' > "$DF"; run_row "no frontmatter is CANNOT ESTABLISH" "2026-11-20" 3
printf -- '---\nstatus: parked\n' > "$DF"; run_row "unterminated fm is CANNOT ESTABLISH" "2026-11-20" 3
mkfx parked; sed -i '/^status:/d' "$DF"; run_row "no status field is CANNOT ESTABLISH" "2026-11-20" 3
printf -- '---\ntitle: "T"\nstatus: parked\n## body section\nstatus: scheduled\n---\nrest\n' > "$DF"
run_row "unterminated fm + body --- + body status: is CANNOT ESTABLISH" "2026-11-20" 3

# ── The clock seam itself is bounded ────────────────────────────────────────
mkfx parked; run_row "bogus SOLEUR_PROBE_TODAY is CANNOT ESTABLISH"  "bogus"      3
mkfx parked; run_row "window-1 day is still NOT YET"                 "2026-11-18" 2

# ── The wake message carries the re-date obligation ─────────────────────────
# A flip landing after the day's 14:00 UTC publisher run leaves publish_date
# in the past and the file goes `stale`; the message must say so or the
# responder produces the stale path thinking they published.
mkfx parked
out="$(SOLEUR_PROBE_TODAY="$WINDOW" bash "$SPROBE" 2>&1)"; rc=$?
if [[ $rc -eq 5 && "$out" == *"re-date"* && "$out" == *"stale"* ]]; then
  pass "ACTION REQUIRED message names the re-date/stale path"
else
  fail "ACTION REQUIRED message lacks re-date/stale guidance (rc=$rc): ${out:0:160}"
fi

echo
echo "parked-green-synthesis-11362: $passes passed, $fails failed"
[[ $fails -eq 0 ]]
