#!/usr/bin/env bash
# Mutation battery for zot-image-staleness.test.sh (#7282).
#
# RENAMED from `zot-image-staleness.mutation.sh` after review. The original name was chosen
# so the file would NOT auto-glob into CI runners — which is exactly backwards for this repo:
# five of five sibling bash mutation batteries are `*-mutation.test.sh` AND registered
# (workspaces-luks-g4, web-host-provisioner-parity, inngest-rls, scan-workflow,
# cf-tunnel-liveness-gate). The one `*.mutation.py` precedent is Python, where the EXTENSION
# is what keeps it out of the glob, not the name. `test-infra-suite-registration.sh` makes
# registration merge-blocking for every tracked `infra/**/*.test.sh`, and its own header says
# auto-globbing is the feature: "a harness in THIS directory is auto-globbed and therefore
# cannot be orphaned". Under the old name no gate could see this file, no runner enumerated
# it, and no orphan reporter would ever have named it.
#
# Runs on a SANDBOX COPY of apps/web-platform/infra; the tracked tree is never mutated.
# Every setup command is checked: a harness that fails to set up must abort, never continue —
# otherwise case N runs against case N-1's mutation and reports a confident WRONG verdict.
export TMPDIR="${TMPDIR:-/var/tmp}"   # /tmp is a shared 4GiB tmpfs; sibling worktrees contend
set -uo pipefail

SRC="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
[[ -d "$SRC" ]] || { echo "SETUP-FAIL: no such dir $SRC" >&2; exit 2; }

PRISTINE="$(mktemp -d -t zotmut-pristine.XXXXXXXX)" || { echo "SETUP-FAIL: mktemp pristine" >&2; exit 2; }
cp -a "$SRC/." "$PRISTINE/" || { echo "SETUP-FAIL: cp pristine" >&2; exit 2; }
trap 'rm -rf "$PRISTINE"' EXIT

GATE=zot-image-staleness.test.sh
PROV=zot-image.provenance.md
TF=zot-registry.tf

# DERIVED, not pasted. Hardcoded literals here rot the moment anyone runs the bump procedure
# this whole change exists to enable — and the `diff -rq` landing check then turns that into a
# SETUP-FAIL that reads as "the battery is broken". Deriving from the sidecar means the battery
# survives both a bump and the sanctioned Refresh recipe.
_cur="$(awk '/^## Current pin/{f=1;next} /^## /{f=0} f' "$PRISTINE/$PROV")"
AMD="$(printf '%s\n' "$_cur" | grep -oE 'zot-linux-amd64:v[0-9.]+@sha256:[0-9a-f]{64}' | grep -oE 'sha256:[0-9a-f]{64}' | head -1)"
ARM="$(printf '%s\n' "$_cur" | grep -oE 'zot-linux-arm64:v[0-9.]+@sha256:[0-9a-f]{64}' | grep -oE 'sha256:[0-9a-f]{64}' | head -1)"
VER="$(printf '%s\n' "$_cur" | grep -oE ':v[0-9]+\.[0-9]+\.[0-9]+@' | tr -d ':@' | head -1)"
CAPDATE="$(grep -oE 'Capture date \(UTC\) \| \*\*[0-9]{4}-[0-9]{2}-[0-9]{2}\*\*' "$PRISTINE/$PROV" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | head -1)"
for v in AMD ARM VER CAPDATE; do
  [[ -n "${!v}" ]] || { echo "SETUP-FAIL: could not derive $v from $PROV" >&2; exit 2; }
done

RED=0; GREENFAIL=0; N=0

base_log="$(mktemp -t zotmut-base.XXXXXXXX.log)" || { echo "SETUP-FAIL: mktemp base_log" >&2; exit 2; }
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
  local box; box="$(mktemp -d -t "zotmut-$id.XXXXXXXX")" || { echo "SETUP-FAIL: mktemp box $id" >&2; exit 2; }
  cp -a "$PRISTINE/." "$box/" || { echo "SETUP-FAIL: cp $id" >&2; exit 2; }

  "$fn" "$box" || { echo "SETUP-FAIL: mutator $id returned non-zero" >&2; rm -rf "$box"; exit 2; }

  # Prove the mutation LANDED, against the PRISTINE copy (never HEAD — the tree is
  # legitimately dirty during a review pass). A no-op sed leaves the baseline result, which
  # is indistinguishable from "the gate did not detect this".
  if diff -rq "$PRISTINE" "$box" >/dev/null 2>&1; then
    echo "SETUP-FAIL: mutation $id did not change anything (mutator is a no-op)" >&2
    rm -rf "$box"; exit 2
  fi

  local log; log="$(mktemp -t "zotmut-$id.XXXXXXXX.log")" || { echo "SETUP-FAIL: mktemp log $id" >&2; rm -rf "$box"; exit 2; }
  bash "$box/$GATE" > "$log" 2>&1; local rc=$?

  # ASSERT THE EXPECTED RC, not merely non-zero. Accepting any rc!=0 let a gate that could
  # never emit a drift verdict score 12/12: neutering fail() alone makes EVERY case exit 2
  # (detector failure), and the old battery reported all twelve as "detected" while the gate
  # was permanently incapable of reddening. The file it validates spends its header insisting
  # 2 and 10 must never be conflated.
  local why=""
  [[ "$rc" == "$want_rc" ]] || why="rc=$rc want=$want_rc"
  if [[ -z "$why" && -n "$marker" ]] && ! grep -qF "$marker" "$log"; then
    why="rc ok but no check named '$marker' reported"
  fi

  if [[ -n "$why" ]]; then
    GREENFAIL=$((GREENFAIL+1))
    printf '  %-3s %-54s NOT-AS-EXPECTED (%s)\n' "$id" "$desc" "$why"
  else
    RED=$((RED+1))
    printf '  %-3s %-54s RED rc=%-2s [%s]\n' "$id" "$desc" "$rc" "$marker"
  fi
  rm -rf "$box" "$log"
}

m_a() { sed -i "s|$AMD|sha256:$(printf 'a%.0s' {1..64})|" "$1/$TF"; }
m_b() { sed -i "s|zot-linux-amd64:$VER|zot-linux-amd64:v0.0.1|" "$1/$TF"; }
m_c() { sed -i "s@\*\*$CAPDATE\*\*@**2025-01-01**@" "$1/$PROV"; }
m_d() { sed -i "s|$AMD|__T__|; s|$ARM|$AMD|; s|__T__|$ARM|" "$1/$TF"; }
m_e() { sed -i "s|$ARM|$AMD|" "$1/$TF"; }
m_f() { sed -i 's@^\( *\)zot_image_amd64\( *\)=@\1# zot_image_amd64\2=@' "$1/$TF"; }
m_g() { sed -i "s@\*\*$CAPDATE\*\*@**2099-01-01**@" "$1/$PROV"; }
m_h() { sed -i "s@\*\*$CAPDATE\*\*@**not-a-date**@" "$1/$PROV"; }
m_i() { sed -i 's|^## Previous known-good pin|## Removed section|' "$1/$PROV"; }
m_j() { sed -i "s|pinned zot $VER|pinned zot (v2.1.2)|" "$1/ci-deploy.test.sh"; }
m_k() { sed -i 's|^pass() {.*|pass() { :; }|; s|^fail() {.*|fail() { :; }|' "$1/$GATE"; }
m_l() { rm -f "$1/ci-deploy.sh"; }
# --- mutations added after the review panel; each closes a case the first battery missed ---
m_m() { sed -i 's|^fail() {.*|fail() { :; }|' "$1/$GATE"; }                    # fail() ALONE: gate can never redden
m_n() { sed -i "s|$AMD|__T__|; s|$ARM|$AMD|; s|__T__|$ARM|" "$1/$TF" "$1/$PROV"; }  # COHERENT two-file swap
m_o() { sed -i 's|? local.zot_image_arm64 : local.zot_image_amd64|? local.zot_image_amd64 : local.zot_image_arm64|' "$1/$TF"; }  # inverted selector
m_p() { for f in "$1/$TF" "$1/$PROV" "$1/ci-deploy.sh" "$1/ci-deploy.test.sh" "$1/cloud-init-registry.yml"; do sed -i "s|$VER|v2.1.2|g" "$f"; done; sed -i "s|$AMD|sha256:073f30d99fbdbcd8869334231c9ca45c75e535e4bdc6e28cc8a1541abe7a3f71|; s|$ARM|sha256:c3fc47782d98b731d5928a24182b495e28cc92f9dcf1d5317f7dbd632e10bf30|" "$1/$TF" "$1/$PROV"; }  # COHERENT downgrade
m_q() { sed -i "s|zot $VER|zot version ${VER#v}|g" "$1/ci-deploy.sh"; }        # claim REWORDED away
m_r() { printf '\n## Bump log\n\n| Bump | Capture date (UTC) | **%s** |\n' "$CAPDATE" >> "$1/$PROV"; sed -i "0,/\*\*$CAPDATE\*\*/s@\*\*$CAPDATE\*\*@**2025-01-01**@" "$1/$PROV"; }  # shadowed capture date

echo "mutations (fresh sandbox copy each; expected rc AND the named check are both asserted):"
run_mutation a "one arch's digest changed"                  10 "sidecar amd64 digest"        m_a
run_mutation b "one arch's version tag changed"             10 "cross-arch version mismatch" m_b
run_mutation c "capture date back-dated past MAX_AGE_DAYS"  10 "analysis is"                 m_c
run_mutation d "digests swapped in the .tf ONLY"            10 "sidecar amd64 digest"        m_d
run_mutation e "one digest pasted into BOTH slots"          10 "IDENTICAL"                   m_e
run_mutation f "the real pin commented out (decoy guard)"   10 "expected exactly 1"          m_f
run_mutation g "capture date in the FUTURE"                 10 "FUTURE"                      m_g
run_mutation h "capture date unparseable garbage"           10 "could not parse"             m_h
run_mutation i "'Previous known-good pin' section deleted"  10 "rollback target"             m_i
run_mutation j "version-scoped claim reverted (paren form)" 10 "name a version we no longer" m_j
run_mutation k "pass()+fail() neutered (dispatch layer)"     2 ""                            m_k
run_mutation l "a follower file removed"                    10 "follower file missing"       m_l
run_mutation m "fail() ALONE neutered (gate cannot redden)"  2 ""                            m_m
# n is the ONLY stay-green case, and it is deliberate: a coherent two-file swap is NOT
# offline-detectable, because nothing in the committed file set binds a digest to an arch.
# Asserting rc=0 here pins that boundary — if a future change makes this red, the offline
# gate learned something and this expectation should be revisited. The case IS closed, over
# the network, by the digest<->repository probe in rule-audit.yml (correct pairing 200,
# swapped 404). Without this fixture every case asserts should-red and nothing pins where
# the offline gate legitimately stops.
run_mutation n "coherent BOTH-file swap (known offline gap)"  0 ""                            m_n
run_mutation o "arch selector ternary INVERTED"             10 "selector"                    m_o
run_mutation p "coherent DOWNGRADE to v2.1.2"               10 "BELOW the sidecar"           m_p
run_mutation q "claim REWORDED so the regex cannot see it"  10 "0 version-scoped claims"     m_q
run_mutation r "capture date SHADOWED by a '## Bump log'"    2 ""                            m_r

echo
echo "RESULT: $RED/$N mutations behaved as expected, $GREENFAIL did not"
[[ "$GREENFAIL" -eq 0 ]]
