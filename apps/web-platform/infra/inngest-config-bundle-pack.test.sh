#!/usr/bin/env bash
#
# Tests for inngest-config-bundle-pack.sh — the ADR-133 config-refresh bundle packager (#6780).
# Deterministic, hermetic (synthesized fixtures only, cq-test-fixtures-synthesized-only; no live
# prod writes, no network, no LLM). Registered in .github/workflows/infra-validation.yml.
#
# Run: bash apps/web-platform/infra/inngest-config-bundle-pack.test.sh
#
# Invariants asserted (each mutation-checked against the production script):
#   H2   — VERSION is line 1 of manifest.txt (the SIGNED blob) → a signed field (HARD-2).
#   SHA  — every refresh-set file appears with its real sha256 keyed by basename.
#   SORT — manifest body is LC_ALL=C-sorted by line, independent of argv order.
#   DET  — two runs over identical inputs produce byte-identical manifest.txt (ADR-128 coherence).
#   FC-* — fail-closed arms (HARD-10): non-integer/zero/leading-zero/decimal/empty VERSION,
#          missing input, duplicate basename, zero inputs — each exits non-zero and writes no
#          usable manifest.

set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACK="${DIR}/inngest-config-bundle-pack.sh"

passes=0
fails=0
pass() { passes=$((passes + 1)); }
fail() { fails=$((fails + 1)); echo "FAIL: $1" >&2; }

[[ -f "$PACK" ]] || { echo "FAIL: pack script not found: $PACK" >&2; exit 1; }

WORK="$(mktemp -d -t inngest-pack-test.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

# --- synthesized fixtures (basenames deliberately NOT in sorted order vs argv) ---------------
mkdir -p "${WORK}/src"
printf 'echo zulu\n'  > "${WORK}/src/zulu.sh"     # sorts last
printf 'echo alpha\n' > "${WORK}/src/alpha.sh"    # sorts first
printf 'echo mike\n'  > "${WORK}/src/mike.sh"     # sorts middle
SHA_ZULU="$(sha256sum "${WORK}/src/zulu.sh"  | cut -d' ' -f1)"
SHA_ALPHA="$(sha256sum "${WORK}/src/alpha.sh" | cut -d' ' -f1)"
SHA_MIKE="$(sha256sum "${WORK}/src/mike.sh"  | cut -d' ' -f1)"

# ============================================================================================
# Happy path — VERSION 7, argv order zulu, alpha, mike (unsorted on purpose).
# ============================================================================================
OUT1="${WORK}/out1"
MPATH="$(bash "$PACK" 7 "$OUT1" "${WORK}/src/zulu.sh" "${WORK}/src/alpha.sh" "${WORK}/src/mike.sh")"
rc=$?
if [[ $rc -eq 0 && -f "$OUT1/manifest.txt" ]]; then pass; else fail "happy-path pack exit 0 + manifest written (rc=$rc)"; fi
# the script prints the manifest path
[[ "$MPATH" == "$OUT1/manifest.txt" ]] && pass || fail "pack prints the manifest path"

# H2: VERSION is line 1 (the signed blob leads with it).
first_line="$(head -1 "$OUT1/manifest.txt")"
[[ "$first_line" == "VERSION=7" ]] && pass || fail "H2: line 1 of manifest is 'VERSION=7' (got '$first_line')"

# SHA: each file present with its real sha256, keyed by basename.
grep -qxF "${SHA_ZULU}  zulu.sh"   "$OUT1/manifest.txt" && pass || fail "SHA: zulu.sh sha line present"
grep -qxF "${SHA_ALPHA}  alpha.sh" "$OUT1/manifest.txt" && pass || fail "SHA: alpha.sh sha line present"
grep -qxF "${SHA_MIKE}  mike.sh"   "$OUT1/manifest.txt" && pass || fail "SHA: mike.sh sha line present"

# SORT: manifest body (lines 2..N) is LC_ALL=C-sorted, so basenames come out alpha, mike, zulu
# regardless of argv order (which was zulu, alpha, mike).
bodies="$(tail -n +2 "$OUT1/manifest.txt" | awk '{print $2}')"
expected_order=$'alpha.sh\nmike.sh\nzulu.sh'
[[ "$bodies" == "$expected_order" ]] && pass || fail "SORT: manifest body sorted by basename (got: $(echo "$bodies" | tr '\n' ' '))"

# staged files copied alongside the manifest
[[ -f "$OUT1/zulu.sh" && -f "$OUT1/alpha.sh" && -f "$OUT1/mike.sh" ]] && pass || fail "staged refresh-set files copied to out dir"

# ============================================================================================
# DET: a second run over identical inputs is byte-identical (reproducible).
# ============================================================================================
OUT2="${WORK}/out2"
bash "$PACK" 7 "$OUT2" "${WORK}/src/zulu.sh" "${WORK}/src/alpha.sh" "${WORK}/src/mike.sh" >/dev/null
if cmp -s "$OUT1/manifest.txt" "$OUT2/manifest.txt"; then pass; else fail "DET: repeated pack is byte-identical"; fi

# ============================================================================================
# Fail-closed arms (HARD-10). Each must exit non-zero AND leave no usable manifest.
# ============================================================================================
# non-integer / malformed VERSION → exit 1, no manifest
for badv in "abc" "0" "007" "3.1" "-4" "v3" ""; do
  o="${WORK}/badv-$RANDOM"
  bash "$PACK" "$badv" "$o" "${WORK}/src/alpha.sh" >/dev/null 2>&1
  rc=$?
  if [[ $rc -ne 0 && ! -f "$o/manifest.txt" ]]; then pass
  else fail "FC-version: VERSION='$badv' must reject (rc=$rc, manifest-exists=$([[ -f "$o/manifest.txt" ]] && echo y || echo n))"; fi
done

# missing input file → non-zero, no manifest
o="${WORK}/missing-$RANDOM"
bash "$PACK" 5 "$o" "${WORK}/src/alpha.sh" "${WORK}/src/does-not-exist.sh" >/dev/null 2>&1
rc=$?
[[ $rc -ne 0 && ! -f "$o/manifest.txt" ]] && pass || fail "FC-missing: missing input file must reject (rc=$rc)"

# duplicate basename (same basename from two different dirs) → non-zero, no manifest
mkdir -p "${WORK}/other"
printf 'echo other-alpha\n' > "${WORK}/other/alpha.sh"
o="${WORK}/dup-$RANDOM"
bash "$PACK" 5 "$o" "${WORK}/src/alpha.sh" "${WORK}/other/alpha.sh" >/dev/null 2>&1
rc=$?
[[ $rc -ne 0 && ! -f "$o/manifest.txt" ]] && pass || fail "FC-dup: duplicate basename must reject (rc=$rc)"

# zero refresh-set files (only version + outdir) → usage, non-zero
o="${WORK}/none-$RANDOM"
bash "$PACK" 5 "$o" >/dev/null 2>&1
rc=$?
[[ $rc -ne 0 && ! -f "$o/manifest.txt" ]] && pass || fail "FC-empty: zero refresh-set files must reject (rc=$rc)"

# ============================================================================================
echo "inngest-config-bundle-pack.test.sh: ${passes} passed, ${fails} failed"
[[ $fails -eq 0 ]] || exit 1
