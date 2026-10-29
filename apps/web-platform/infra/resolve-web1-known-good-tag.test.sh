#!/usr/bin/env bash
# Network-free unit tests for the pure web-1 known-good tag resolver
# (apps/web-platform/infra/scripts/resolve-web1-known-good-tag.sh).
#
# #6147 — the web_2_recreate pin-gate used to read web-1's running tag from the
# shared /hooks/deploy-status `.tag` slot, which a non-web writer (an inngest
# restart stamping {component:inngest,tag:latest}) wedges to a non-semver value,
# hard-aborting the recreate with `got 'latest'`. The fix resolves web-1's running
# tag from its public /health `.version` (ADR-079 #5955's already-adopted pattern)
# and drops the deploy-status read. This resolver is the PURE core of that path:
# it takes the fetched `/health` version STRING (no network I/O here — the caller
# does the bounded curl retry) and emits `v<semver>` iff it is strict three-part
# semver, else exits non-zero with a diagnostic.
#
# The strict `^v[0-9]+\.[0-9]+\.[0-9]+$` guard is load-bearing: the loose pin regex
# the old code used (`^v[0-9][A-Za-z0-9._-]*$`) would ACCEPT a prerelease
# `v1.2.3-rc1` and a floating build, silently pinning a non-released image. The
# release pipeline only ever pushes strict `vX.Y.Z` (reusable-release.yml:597,686),
# so no legitimate tag is rejected.
#
# Fixtures are synthesized inline strings (no real tokens; cq-test-fixtures-synthesized-only).
#
# Run: bash apps/web-platform/infra/resolve-web1-known-good-tag.test.sh
# Registered in .github/workflows/infra-validation.yml.
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$DIR/scripts/resolve-web1-known-good-tag.sh"

passes=0
fails=0
pass() { passes=$((passes + 1)); }
fail() {
  fails=$((fails + 1))
  echo "FAIL: $1" >&2
}

[ -f "$SCRIPT" ] || { echo "FAIL: resolver not found at $SCRIPT" >&2; exit 1; }
[ -x "$SCRIPT" ] || { echo "FAIL: resolver not executable at $SCRIPT" >&2; exit 1; }

# Run the resolver with the version passed as an ARGUMENT.
# Captures OUT (stdout) and RC (exit code) as globals.
run_arg() {
  OUT="$(bash "$SCRIPT" "$1" 2>/dev/null)"
  RC=$?
}

# Run the resolver with the version fed on STDIN (the alternate seam).
run_stdin() {
  OUT="$(printf '%s' "$1" | bash "$SCRIPT" 2>/dev/null)"
  RC=$?
}

# ── (a) valid three-part semver → prints v<semver>, exit 0 ────────────────────
run_arg "1.2.3"
if [[ "$RC" -eq 0 && "$OUT" == "v1.2.3" ]]; then pass; else fail "(a) valid 1.2.3 → expected rc=0 OUT=v1.2.3, got rc=$RC OUT='$OUT'"; fi

# Live-observed production version (app.soleur.ai/health → 0.200.2 on 2026-07-07).
run_arg "0.200.2"
if [[ "$RC" -eq 0 && "$OUT" == "v0.200.2" ]]; then pass; else fail "(a2) live 0.200.2 → expected rc=0 OUT=v0.200.2, got rc=$RC OUT='$OUT'"; fi

# ── (b) empty version (unreachable /health, jq '.version // ""') → non-zero, no tag ──
run_arg ""
if [[ "$RC" -eq 1 && -z "$OUT" ]]; then pass; else fail "(b) empty → expected rc=1 and empty OUT, got rc=$RC OUT='$OUT'"; fi

# ── (c) non-released build ('dev' → 'vdev') → non-zero, no tag ─────────────────
run_arg "dev"
if [[ "$RC" -eq 1 && -z "$OUT" ]]; then pass; else fail "(c) dev → expected rc=1 and empty OUT, got rc=$RC OUT='$OUT'"; fi

# ── (d) prerelease (1.2.3-rc1) → non-zero (the loose regex would wrongly accept) ──
run_arg "1.2.3-rc1"
if [[ "$RC" -eq 1 && -z "$OUT" ]]; then pass; else fail "(d) 1.2.3-rc1 prerelease → expected rc=1 and empty OUT, got rc=$RC OUT='$OUT'"; fi

# ── (e) the actual #6147 bug: an inngest restart stamps tag=latest → non-zero ──
run_arg "latest"
if [[ "$RC" -eq 1 && -z "$OUT" ]]; then pass; else fail "(e) latest (the wedge value) → expected rc=1 and empty OUT, got rc=$RC OUT='$OUT'"; fi

# ── (f) two-part semver (1.2) → non-zero (strict three-part required) ──────────
run_arg "1.2"
if [[ "$RC" -eq 1 && -z "$OUT" ]]; then pass; else fail "(f) two-part 1.2 → expected rc=1 and empty OUT, got rc=$RC OUT='$OUT'"; fi

# ── (g) v-prefixed input canonicalizes (v1.2.3 → v1.2.3) → rc=0 ───────────────
# Contract: input is strict three-part semver, bare or `v`-prefixed — the
# resolver normalizes one leading v before prepending, so both accepted
# spellings emit the same canonical tag. This is the apply-web-platform-infra.yml
# `image_tag` contract: its input regex is ^v?[0-9]+\.[0-9]+\.[0-9]+$ — a
# v-prefixed dispatch must not abort post-approval as vvX.Y.Z (#11426, #9669).
run_arg "v1.2.3"
if [[ "$RC" -eq 0 && "$OUT" == "v1.2.3" ]]; then pass; else fail "(g) v-prefixed v1.2.3 → expected rc=0 OUT=v1.2.3, got rc=$RC OUT='$OUT'"; fi

# ── (g2) double-v input (vv1.2.3) → non-zero (the strict guard stays loud) ────
# The strip removes exactly ONE leading v; vv1.2.3 → v1.2.3 → prepend → vv1.2.3,
# which the strict guard still rejects. The double-v path stays loud.
run_arg "vv1.2.3"
if [[ "$RC" -eq 1 && -z "$OUT" ]]; then pass; else fail "(g2) double-v vv1.2.3 → expected rc=1 and empty OUT, got rc=$RC OUT='$OUT'"; fi

# ── (g3) stdin seam parity: a v-prefixed version on stdin canonicalizes too ────
run_stdin "v4.5.6"
if [[ "$RC" -eq 0 && "$OUT" == "v4.5.6" ]]; then pass; else fail "(g3) stdin v4.5.6 → expected rc=0 OUT=v4.5.6, got rc=$RC OUT='$OUT'"; fi

# ── (h) stdin seam parity: a valid version on stdin resolves identically ──────
run_stdin "4.5.6"
if [[ "$RC" -eq 0 && "$OUT" == "v4.5.6" ]]; then pass; else fail "(h) stdin 4.5.6 → expected rc=0 OUT=v4.5.6, got rc=$RC OUT='$OUT'"; fi

# ── (h2) stdin reject parity: an invalid version on stdin rejects like the arg path ──
run_stdin "latest"
if [[ "$RC" -eq 1 && -z "$OUT" ]]; then pass; else fail "(h2) stdin latest → expected rc=1 and empty OUT, got rc=$RC OUT='$OUT'"; fi

# ── (j) trailing whitespace → non-zero (pins the resolver's documented "no trimming" contract) ──
run_arg "1.2.3 "
if [[ "$RC" -eq 1 && -z "$OUT" ]]; then pass; else fail "(j) trailing-space '1.2.3 ' → expected rc=1 and empty OUT, got rc=$RC OUT='$OUT'"; fi

# ── (k) four-part version → non-zero (pins the trailing \$ anchor) ─────────────
run_arg "1.2.3.4"
if [[ "$RC" -eq 1 && -z "$OUT" ]]; then pass; else fail "(k) four-part 1.2.3.4 → expected rc=1 and empty OUT, got rc=$RC OUT='$OUT'"; fi

# ── (g4) the rejection diagnostic names the caller's RAW input, not the normalized form ──
STDERR_G4="$(bash "$SCRIPT" "vv1.2.3" 2>&1 >/dev/null)"
if echo "$STDERR_G4" | grep -c "version='vv1.2.3'" >/dev/null; then pass; else fail "(g4) vv1.2.3 diagnostic → expected version='vv1.2.3' (raw input), got: $STDERR_G4"; fi

# ── (g5) input-regex ↔ resolver-contract parity: the workflow's ^v? guard and the
# resolver's normalize-then-strict-guard are a coupled pair — pin the literal at
# BOTH workflow validation sites so a one-sided edit reintroducing the post-
# approval vv* abort class fails here (#11426/#9669). ──
WF="$(cd "$DIR/../../.." && pwd)/.github/workflows/apply-web-platform-infra.yml"
HITS="$(grep -c 'v?\[0-9\]' "$WF" 2>/dev/null || true)"
if [[ -f "$WF" && "$HITS" -ge 2 ]]; then pass; else fail "(g5) input-regex parity → expected >=2 ^v? semver guards in $WF, got $HITS"; fi

# ── (i) diagnostic quality: rejection message names the rejected version inside the quoted slot + surfaces ::error:: ──
STDERR="$(bash "$SCRIPT" "latest" 2>&1 >/dev/null)"
if echo "$STDERR" | grep -c "::error::" >/dev/null && echo "$STDERR" | grep -c "version='latest'" >/dev/null; then
  pass
else
  fail "(i) rejection diagnostic → expected ::error:: with version='latest', got: $STDERR"
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo "resolve-web1-known-good-tag: $passes passed, $fails failed"
[ "$fails" -eq 0 ] || exit 1
