#!/usr/bin/env bash
# Mutation battery for inngest-cli-staleness.test.sh (#7463).
#
# Runs on a SANDBOX COPY of apps/web-platform/infra; the tracked tree is never
# mutated. Every setup command is checked: a harness that fails to set up must abort,
# never continue — otherwise case N runs against case N-1's mutation and reports a
# confident WRONG verdict. Cloned discipline from zot-image-staleness-mutation.test.sh.
export TMPDIR="${TMPDIR:-/var/tmp}"   # /tmp is a shared tmpfs; sibling worktrees contend
set -uo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ -d "$SRC" ]] || { echo "SETUP-FAIL: no such dir $SRC" >&2; exit 2; }

PRISTINE="$(mktemp -d -t inngestmut-pristine.XXXXXXXX)" || { echo "SETUP-FAIL: mktemp pristine" >&2; exit 2; }
cp -a "$SRC/." "$PRISTINE/" || { echo "SETUP-FAIL: cp pristine" >&2; exit 2; }
trap 'rm -rf "$PRISTINE"' EXIT

GATE=inngest-cli-staleness.test.sh
PROV=inngest-cli.provenance.md
TF=inngest.tf

# DERIVED, not pasted. Hardcoded literals here rot the moment anyone runs the bump
# procedure this whole change exists to enable — and the `diff -rq` landing check then
# turns that into a SETUP-FAIL that reads as "the battery is broken".
VER="$(grep -oE '^[[:space:]]*inngest_cli_version[[:space:]]*=[[:space:]]*"v[0-9]+\.[0-9]+\.[0-9]+"' "$PRISTINE/$TF" | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
AMD="$(grep -oE '^[[:space:]]*inngest_cli_sha256[[:space:]]*=[[:space:]]*"[0-9a-f]{64}"' "$PRISTINE/$TF" | grep -oE '[0-9a-f]{64}' | head -1)"
ARM="$(grep -oE '^[[:space:]]*inngest_cli_sha256_arm64[[:space:]]*=[[:space:]]*"[0-9a-f]{64}"' "$PRISTINE/$TF" | grep -oE '[0-9a-f]{64}' | head -1)"
_cur="$(awk '/^## Current pin/{f=1;next} /^## /{f=0} f' "$PRISTINE/$PROV")"
PREV_SEC="$(awk '/^## Previous known-good pin/{f=1;next} /^## /{f=0} f' "$PRISTINE/$PROV")"
PAMD="$(printf '%s\n' "$PREV_SEC" | grep -oE '\| *amd64 *\|[^|]*`[0-9a-f]{64}`' | grep -oE '[0-9a-f]{64}' | head -1)"
PARM="$(printf '%s\n' "$PREV_SEC" | grep -oE '\| *arm64 *\|[^|]*`[0-9a-f]{64}`' | grep -oE '[0-9a-f]{64}' | head -1)"
PVER="$(printf '%s\n' "$PREV_SEC" | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
CAPDATE="$(grep -oE 'Capture date \(UTC\) \| \*\*[0-9]{4}-[0-9]{2}-[0-9]{2}\*\*' "$PRISTINE/$PROV" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | head -1)"
for v in VER AMD ARM PAMD PARM PVER CAPDATE; do
  [[ -n "${!v}" ]] || { echo "SETUP-FAIL: could not derive $v from $TF/$PROV" >&2; exit 2; }
done

RED=0; GREENFAIL=0; N=0

base_log="$(mktemp -t inngestmut-base.XXXXXXXX.log)" || { echo "SETUP-FAIL: mktemp base_log" >&2; exit 2; }
bash "$PRISTINE/$GATE" > "$base_log" 2>&1; base_rc=$?
if [[ "$base_rc" != "0" ]]; then
  echo "SETUP-FAIL: baseline is NOT green (rc=$base_rc) — every mutation result below would be meaningless" >&2
  grep -E 'FAIL|DETECTOR' "$base_log" >&2
  rm -f "$base_log"; exit 2
fi
echo "baseline: GREEN (rc=0) — $(grep -oE 'RESULT: .*' "$base_log")"
rm -f "$base_log"
echo

# $1=id $2=desc $3=EXPECTED RC $4=marker the failing check must print $5=mutator
run_mutation() {
  N=$((N+1))
  local id="$1" desc="$2" want_rc="$3" marker="$4" fn="$5"
  local box; box="$(mktemp -d -t "inngestmut-$id.XXXXXXXX")" || { echo "SETUP-FAIL: mktemp box $id" >&2; exit 2; }
  cp -a "$PRISTINE/." "$box/" || { echo "SETUP-FAIL: cp $id" >&2; exit 2; }

  "$fn" "$box" || { echo "SETUP-FAIL: mutator $id returned non-zero" >&2; rm -rf "$box"; exit 2; }

  # Prove the mutation LANDED, against the PRISTINE copy. A no-op sed leaves the
  # baseline result, which is indistinguishable from "the gate did not detect this".
  if diff -rq "$PRISTINE" "$box" >/dev/null 2>&1; then
    echo "SETUP-FAIL: mutation $id did not change anything (mutator is a no-op)" >&2
    rm -rf "$box"; exit 2
  fi

  local log; log="$(mktemp -t "inngestmut-$id.XXXXXXXX.log")" || { echo "SETUP-FAIL: mktemp log $id" >&2; rm -rf "$box"; exit 2; }
  bash "$box/$GATE" > "$log" 2>&1; local rc=$?

  # ASSERT THE EXPECTED RC, not merely non-zero — accepting any rc!=0 lets a gate that
  # could never emit a drift verdict score full marks.
  local why=""
  [[ "$rc" == "$want_rc" ]] || why="rc=$rc want=$want_rc"
  if [[ -z "$why" && -n "$marker" ]] && ! grep -qF "$marker" "$log"; then
    why="rc ok but no check named '$marker' reported"
  fi

  if [[ -n "$why" ]]; then
    GREENFAIL=$((GREENFAIL+1))
    printf '  %-3s %-56s NOT-AS-EXPECTED (%s)\n' "$id" "$desc" "$why"
  else
    RED=$((RED+1))
    printf '  %-3s %-56s RED rc=%-2s [%s]\n' "$id" "$desc" "$rc" "$marker"
  fi
  rm -rf "$box" "$log"
}

m_a() { sed -i "s|$AMD|$(printf 'a%.0s' {1..64})|" "$1/$TF"; }                                   # amd64 sha changed in tf only
m_b() { sed -i "s|inngest_cli_version[[:space:]]*=[[:space:]]*\"$VER\"|inngest_cli_version = \"v0.0.1\"|" "$1/$TF"; }  # version moved, shas stale
m_c() { sed -i "s@\*\*$CAPDATE\*\*@**2025-01-01**@" "$1/$PROV"; }                              # capture date back-dated
m_d() { sed -i "s|$AMD|__T__|; s|$ARM|$AMD|; s|__T__|$ARM|" "$1/$TF"; }                        # swap shas in tf ONLY
m_e() { sed -i "s|$ARM|$AMD|" "$1/$TF"; }                                                      # amd64 sha pasted into arm64 slot
m_f() { sed -i 's@^\( *\)inngest_cli_version\( *\)=@\1# inngest_cli_version\2=@' "$1/$TF"; }   # real pin commented out
m_g() { sed -i "s@\*\*$CAPDATE\*\*@**2099-01-01**@" "$1/$PROV"; }                              # future capture date
m_h() { sed -i "s@\*\*$CAPDATE\*\*@**not-a-date**@" "$1/$PROV"; }                              # unparseable capture date
m_i() { printf '  inngest_cli_version = "v0.0.1" # second ACTIVE assignment\n' >> "$1/$TF"; }  # decoy that is NOT a comment
m_j() { sed -i "s|inngest $VER|inngest v0.0.9|" "$1/inngest-inventory.sh"; }                   # stale version claim in follower
m_k() { sed -i 's|^pass() {.*|pass() { :; }|; s|^fail() {.*|fail() { :; }|' "$1/$GATE"; }      # pass+fail neutered
m_l() { rm -f "$1/inngest-bootstrap.sh"; }                                                   # follower file removed
m_m() { sed -i 's|^fail() {.*|fail() { :; }|' "$1/$GATE"; }                                    # fail() ALONE neutered
# n: COHERENT two-file arch swap — sha carries no arch info, so nothing in the committed
# set binds a sha to an arch; declared offline gap, the same boundary the zot gate states.
m_n() { sed -i "s|$AMD|__T__|; s|$ARM|$AMD|; s|__T__|$ARM|" "$1/$TF" "$1/$PROV"; }
# o: FULLY coherent rollback — current pin+sidecar to the previous release AND the
# previous-pin section rotated to the superseded one AND follower claims re-stamped.
# This is the SANCTIONED rollback path and must stay GREEN offline (plan mutation row 8):
# only the PR-B upstream poll knows v_prev is not the latest.
# Section-scoped: an unscoped second pass would re-match the values just written
# into '## Current pin' (the previous pin's shas are exactly what a rollback writes
# there), double-swapping it back.
m_o() {
  sed -i "s|$VER|$PVER|g; s|$AMD|$PAMD|g; s|$ARM|$PARM|g" "$1/$TF"
  sed -i '/^## Current pin/,/^## /{
    s|'"$VER"'|'"$PVER"'|g
    s|'"$AMD"'|'"$PAMD"'|g
    s|'"$ARM"'|'"$PARM"'|g
  }' "$1/$PROV"
  sed -i '/^## Previous known-good pin/,/^## /{
    s|'"$PAMD"'|'"$AMD"'|g
    s|'"$PARM"'|'"$ARM"'|g
  }' "$1/$PROV"
  sed -i 's#Pinned version | \*\*'"$VER"'\*\*#Pinned version | **'"$PVER"'**#' "$1/$PROV"
  sed -i "s|inngest $VER|inngest $PVER|g; s|inngest ($VER|inngest ($PVER|g" \
      "$1/inngest-bootstrap.sh" "$1/inngest-inventory.sh" "$1/inngest-enumerate-reminders.sh" \
      "$1/inngest-doublefire-probe.sh" "$1/inngest-wiped-volume-verify.sh" "$1/ci-deploy.sh" \
      "$1/betterstack-logs-alerts.tf" "$1/inngest-host.tf"
}
m_p() { sed -i "s|inngest $VER|inngest version ${VER#v}|g" "$1/inngest-inventory.sh"; }        # claim REWORDED away
# q: shadowed capture date — a '## Bump log' carrying a SECOND capture-date row must be
# refused (detector failure), never silently preferred.
m_q() { printf '\n## Bump log\n\n| Bump | Capture date (UTC) | **%s** |\n' "$CAPDATE" >> "$1/$PROV"; sed -i "0,/\*\*$CAPDATE\*\*/s@\*\*$CAPDATE\*\*@**2025-01-01**@" "$1/$PROV"; }
m_r() { sed -i "/^| *arm64 *|/d" "$1/$PROV"; }                                                 # arm64 row dropped from sidecar
# s: downgrade current pin+sidecar to the previous release WITHOUT rotating the previous
# section — current==previous must read as "no rollback target", not fresh.
m_s() { sed -i "s|$VER|$PVER|g; s|$AMD|$PAMD|g; s|$ARM|$PARM|g" "$1/$TF" "$1/$PROV"; }

echo "mutations (fresh sandbox copy each; expected rc AND the named check are both asserted):"
run_mutation a "amd64 sha changed in .tf only"                    10 "sidecar amd64 checksum" m_a
run_mutation b "version bumped, shas left stale"                10 "sidecar current-pin version" m_b
run_mutation c "capture date back-dated past MAX_AGE_DAYS"      10 "analysis is" m_c
run_mutation d "shas swapped in the .tf ONLY"                   10 "sidecar amd64 checksum" m_d
run_mutation e "one sha pasted into BOTH slots"                 10 "IDENTICAL" m_e
run_mutation f "the real pin commented out (decoy guard)"       10 "expected exactly 1" m_f
run_mutation g "capture date in the FUTURE"                     10 "FUTURE" m_g
run_mutation h "capture date unparseable garbage"               10 "could not parse" m_h
run_mutation i "a SECOND active version assignment"             10 "expected exactly 1" m_i
run_mutation j "version-scoped claim reverted"                  10 "name a version we no longer" m_j
run_mutation k "pass()+fail() neutered (dispatch layer)"         2 "" m_k
run_mutation l "a follower file removed"                        10 "follower file missing" m_l
run_mutation m "fail() ALONE neutered (gate cannot redden)"      2 "" m_m
run_mutation n "coherent BOTH-file arch swap (offline gap)"      0 "" m_n
run_mutation o "FULLY coherent rollback to previous pin"         0 "" m_o
run_mutation p "claim REWORDED so the regex cannot see it"      10 "0 version-scoped claims" m_p
run_mutation q "capture date SHADOWED by a '## Bump log'"        2 "" m_q
run_mutation r "arm64 row dropped from the sidecar"             10 "sidecar arm64 checksum" m_r
run_mutation s "downgrade WITHOUT rotating previous-pin"        10 "SAME" m_s

echo
echo "RESULT: $RED/$N mutations behaved as expected, $GREENFAIL did not"
[[ "$GREENFAIL" -eq 0 ]]
