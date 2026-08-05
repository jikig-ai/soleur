#!/usr/bin/env bash
# AC3 mutation battery for zot-image-staleness.test.sh.
# Runs on a SANDBOX COPY of apps/web-platform/infra so the real tree is never mutated.
# Every setup command is checked: a harness that fails to set up must abort, never
# continue — otherwise case N runs against case N-1's mutation and reports a confident
# WRONG verdict about the SUT.
export TMPDIR="${TMPDIR:-/var/tmp}"   # /tmp is a shared 4GiB tmpfs; sibling worktrees contend
set -uo pipefail

SRC="${1:?usage: $0 <abs path to apps/web-platform/infra>}"
[[ -d "$SRC" ]] || { echo "SETUP-FAIL: no such dir $SRC" >&2; exit 2; }

PRISTINE="$(mktemp -d -t zotmut-pristine.XXXXXXXX)" || { echo "SETUP-FAIL: mktemp pristine" >&2; exit 2; }
cp -a "$SRC/." "$PRISTINE/" || { echo "SETUP-FAIL: cp pristine" >&2; exit 2; }
trap 'rm -rf "$PRISTINE"' EXIT

GATE=zot-image-staleness.test.sh
PROV=zot-image.provenance.md
TF=zot-registry.tf

AMD='sha256:95a837a0afacf5b7edc0c92493f04beee6891989b8d2fd50a00cf65a1e6d4fd5'
ARM='sha256:56230c5a589eb55acc57afc34307f6ea1b2efe5cf8e0057ccca64099ba837ff6'

RED=0; GREENFAIL=0; N=0

# baseline: the pristine copy MUST be green, or every "mutant is red" below is meaningless
base_log="$(mktemp -t zotmut-base.XXXXXXXX.log)" || exit 2
bash "$PRISTINE/$GATE" > "$base_log" 2>&1; base_rc=$?
if [[ "$base_rc" != "0" ]]; then
  echo "SETUP-FAIL: baseline is NOT green (rc=$base_rc) — mutation results would be meaningless" >&2
  grep -E 'FAIL|DETECTOR' "$base_log" >&2
  exit 2
fi
echo "baseline: GREEN (rc=0) — $(grep -oE 'RESULT: .*' "$base_log")"
echo

run_mutation() { # $1=id  $2=description  $3=expected-check  $4=mutator-fn
  N=$((N+1))
  local id="$1" desc="$2" expect="$3" fn="$4"
  local box; box="$(mktemp -d -t "zotmut-$id.XXXXXXXX")" || { echo "SETUP-FAIL: mktemp $id" >&2; exit 2; }
  cp -a "$PRISTINE/." "$box/" || { echo "SETUP-FAIL: cp $id" >&2; exit 2; }

  "$fn" "$box" || { echo "SETUP-FAIL: mutator $id returned non-zero" >&2; exit 2; }

  # Prove the mutation actually LANDED. A no-op sed that silently changes nothing would
  # otherwise be scored as "the gate did not detect this".
  if diff -rq "$PRISTINE" "$box" >/dev/null 2>&1; then
    echo "SETUP-FAIL: mutation $id did not change anything (mutator is a no-op)" >&2
    exit 2
  fi

  local log; log="$(mktemp -t "zotmut-$id.XXXXXXXX.log")"
  bash "$box/$GATE" > "$log" 2>&1; local rc=$?
  if [[ "$rc" == "0" ]]; then
    GREENFAIL=$((GREENFAIL+1))
    printf '  %-3s %-52s SURVIVED (rc=0)  <-- GATE IS BLIND\n' "$id" "$desc"
  else
    RED=$((RED+1))
    printf '  %-3s %-52s RED (rc=%s) [%s]\n' "$id" "$desc" "$rc" "$expect"
  fi
  rm -rf "$box" "$log"
}

m_a() { sed -i "s|$AMD|sha256:$(printf 'a%.0s' {1..64})|" "$1/$TF"; }
m_b() { sed -i "s|zot-linux-amd64:v2\.1\.20|zot-linux-amd64:v2.1.19|" "$1/$TF"; }
m_c() { sed -i 's@\*\*2026-08-05\*\*@**2025-01-01**@' "$1/$PROV"; }
m_d() { sed -i "s|$AMD|__TMP__|; s|$ARM|$AMD|; s|__TMP__|$ARM|" "$1/$TF"; }   # SWAP
m_e() { sed -i "s|$ARM|$AMD|" "$1/$TF"; }                                      # same digest both slots
m_f() { sed -i 's@^\( *\)zot_image_amd64\( *\)=@\1# zot_image_amd64\2=@' "$1/$TF"; }
m_g() { sed -i 's|\*\*2026-08-05\*\*|**2099-01-01**|' "$1/$PROV"; }
m_h() { sed -i 's@\*\*2026-08-05\*\*@**not-a-date**@' "$1/$PROV"; }
m_i() { sed -i 's|^## Previous known-good pin|## Removed section|' "$1/$PROV"; }
m_j() { sed -i 's|pinned zot v2\.1\.20|pinned zot (v2.1.2)|' "$1/ci-deploy.test.sh"; }

echo "mutations (each applied to a fresh sandbox copy, each must go RED):"
run_mutation a "one arch's digest changed"                 "check5"   m_a
run_mutation b "one arch's version tag changed"            "check3/5" m_b
run_mutation c "capture date back-dated past MAX_AGE_DAYS" "check6a"  m_c
run_mutation d "DIGESTS SWAPPED BETWEEN ARCHES"            "check2/5" m_d
run_mutation e "one digest pasted into BOTH slots"         "check4"   m_e
run_mutation f "commented-out second pin (decoy)"          "check2"   m_f
run_mutation g "capture date in the FUTURE"                "check6b"  m_g
run_mutation h "capture date unparseable garbage"          "check6c"  m_h
run_mutation i "'Previous known-good pin' section deleted" "check8"   m_i
run_mutation j "version-scoped claim reverted (paren form)" "check7"  m_j

echo
echo "RESULT: $RED/$N mutations detected, $GREENFAIL survived"
[[ "$GREENFAIL" -eq 0 ]]
