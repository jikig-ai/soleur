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
if [[ "$RC" -ne 0 && -z "$OUT" ]]; then pass; else fail "(b) empty → expected rc!=0 and empty OUT, got rc=$RC OUT='$OUT'"; fi

# ── (c) non-released build ('dev' → 'vdev') → non-zero, no tag ─────────────────
run_arg "dev"
if [[ "$RC" -ne 0 && -z "$OUT" ]]; then pass; else fail "(c) dev → expected rc!=0 and empty OUT, got rc=$RC OUT='$OUT'"; fi

# ── (d) prerelease (1.2.3-rc1) → non-zero (the loose regex would wrongly accept) ──
run_arg "1.2.3-rc1"
if [[ "$RC" -ne 0 && -z "$OUT" ]]; then pass; else fail "(d) 1.2.3-rc1 prerelease → expected rc!=0 and empty OUT, got rc=$RC OUT='$OUT'"; fi

# ── (e) the actual #6147 bug: an inngest restart stamps tag=latest → non-zero ──
run_arg "latest"
if [[ "$RC" -ne 0 && -z "$OUT" ]]; then pass; else fail "(e) latest (the wedge value) → expected rc!=0 and empty OUT, got rc=$RC OUT='$OUT'"; fi

# ── (f) two-part semver (1.2) → non-zero (strict three-part required) ──────────
run_arg "1.2"
if [[ "$RC" -ne 0 && -z "$OUT" ]]; then pass; else fail "(f) two-part 1.2 → expected rc!=0 and empty OUT, got rc=$RC OUT='$OUT'"; fi

# ── (g) already-v-prefixed input (v1.2.3 → vv1.2.3) → non-zero ────────────────
# Contract: input is the BARE /health .version; a leading v means a caller bug.
run_arg "v1.2.3"
if [[ "$RC" -ne 0 && -z "$OUT" ]]; then pass; else fail "(g) already-prefixed v1.2.3 → expected rc!=0 and empty OUT, got rc=$RC OUT='$OUT'"; fi

# ── (h) stdin seam parity: a valid version on stdin resolves identically ──────
run_stdin "4.5.6"
if [[ "$RC" -eq 0 && "$OUT" == "v4.5.6" ]]; then pass; else fail "(h) stdin 4.5.6 → expected rc=0 OUT=v4.5.6, got rc=$RC OUT='$OUT'"; fi

# ── (h2) stdin reject parity: an invalid version on stdin rejects like the arg path ──
run_stdin "latest"
if [[ "$RC" -ne 0 && -z "$OUT" ]]; then pass; else fail "(h2) stdin latest → expected rc!=0 and empty OUT, got rc=$RC OUT='$OUT'"; fi

# ── (j) trailing whitespace → non-zero (pins the resolver's documented "no trimming" contract) ──
run_arg "1.2.3 "
if [[ "$RC" -ne 0 && -z "$OUT" ]]; then pass; else fail "(j) trailing-space '1.2.3 ' → expected rc!=0 and empty OUT, got rc=$RC OUT='$OUT'"; fi

# ── (k) four-part version → non-zero (pins the trailing \$ anchor) ─────────────
run_arg "1.2.3.4"
if [[ "$RC" -ne 0 && -z "$OUT" ]]; then pass; else fail "(k) four-part 1.2.3.4 → expected rc!=0 and empty OUT, got rc=$RC OUT='$OUT'"; fi

# ── (i) diagnostic quality: rejection message names the rejected version inside the quoted slot + surfaces ::error:: ──
STDERR="$(bash "$SCRIPT" "latest" 2>&1 >/dev/null)"
if echo "$STDERR" | grep -q "::error::" && echo "$STDERR" | grep -q "version='latest'"; then
  pass
else
  fail "(i) rejection diagnostic → expected ::error:: with version='latest', got: $STDERR"
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo "resolve-web1-known-good-tag: $passes passed, $fails failed"
[ "$fails" -eq 0 ] || exit 1
