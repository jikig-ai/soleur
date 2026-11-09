#!/usr/bin/env bash
# bot-synthetic-unreachability.test.sh — Guard 4 of #10859 (PR3b): the disjointness that makes the two
# new synthetic greens SOUND rather than fabricated (#6049 ceiling, ADR-139 per-gate rule).
#
# WHAT THIS PROVES, from the live files (never a pinned copy):
#   * ALLOWED_PATHS of .github/actions/bot-pr-with-synthetic-checks/action.yml is exactly
#     {knowledge-base/project/weakness-digest.md} — the surface every bot PR diff is confined to;
#   * the oracle surface list scripts/ci-oracle-surface.txt (the sentinel's committed list, moved
#     off the retired replay.py RATCHET_ORACLE by the S4 retirement of 2026-11-09) is non-empty and
#     names both oracle-review-required producers (scripts/ci-oracle-review.sh + its suite);
#   * ALLOWED_PATHS ∩ oracle surface = ∅ — so a bot PR's `oracle-review-required` synthetic asserts
#     the `not-oracle` verdict the real sentinel would emit;
#   * the audit input surface a bot PR could perturb (suite files) is likewise disjoint —
#     weakness-digest.md is named by no AFFECTED_*_PATHS block;
#   * oracle-review-required is in scripts/required-checks.txt (the synthetic consumer) — a name
#     missing there would silently stop being synthesized on bot PRs, and a name there without its
#     disjointness is a fabricated green. (The `affected-index-ratchet` synthetic went away with the
#     context itself in the S4 retirement.)
#
# The residual this pins: any ALLOWED_PATHS or oracle-surface or suite-edge edit that intersects the two
# sets turns the synthetic green live — the PR that does it must first reproduce the real gates in the
# action's Phase-4 ceiling (action.yml #6049).
set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

passes=0; fails=0
FAILURES=()
pass() { passes=$((passes + 1)); }
fail() { fails=$((fails + 1)); FAILURES+=("$1"); printf 'FAIL: %s\n' "$1" >&2; }
chk() { local d="$1"; shift; if "$@"; then pass; else fail "$d"; fi; }

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
ACT="$REPO_ROOT/.github/actions/bot-pr-with-synthetic-checks/action.yml"
SURFACE="$REPO_ROOT/scripts/ci-oracle-surface.txt"
REQ="$REPO_ROOT/scripts/required-checks.txt"
PATHSLIB="$REPO_ROOT/scripts/lib/test-affected-paths.sh"
for f in "$ACT" "$SURFACE" "$REQ" "$PATHSLIB"; do
  [[ -s "$f" ]] || { printf 'FATAL: %s missing\n' "$f" >&2; exit 2; }
done

SANDBOX="$(mktemp -d "$TMPDIR/bot-unreach.XXXXXXXX")" || exit 2
trap 'rm -rf "$SANDBOX"' EXIT
for _dep in python3 bash; do command -v "$_dep" >/dev/null 2>&1 || exit 2; done

# ALLOWED_PATHS: the array literal in action.yml (the lines between `ALLOWED_PATHS=(` and `)`).
awk '/ALLOWED_PATHS=\(/{f=1;next} f&&/^\s*\)/{f=0} f' "$ACT" | tr -d ' "' > "$SANDBOX/allowed.txt"
chk "ALLOWED_PATHS is exactly {knowledge-base/project/weakness-digest.md} (anti-vacuity + bound)" \
  test "$(sort "$SANDBOX/allowed.txt")" = "knowledge-base/project/weakness-digest.md"

# The oracle surface: the committed list file — a data file, so read line-wise (blank lines and
# comments dropped); a renamed or emptied file cannot pass vacuously.
grep -vE '^[[:space:]]*(#|$)' "$SURFACE" > "$SANDBOX/oracle.txt" 2>"$SANDBOX/oracle.err" || true
chk "ci-oracle-surface.txt reads as a non-empty list" \
  test -s "$SANDBOX/oracle.txt"
chk "the surface names both oracle-review-required producers" \
  bash -c 'grep -qxF "scripts/ci-oracle-review.sh" "$1" && grep -qxF "scripts/ci-oracle-review.test.sh" "$1"' _ "$SANDBOX/oracle.txt"

# The disjointness itself: a bot PR diff is confined to ALLOWED_PATHS; none of those paths is oracle surface.
chk "ALLOWED_PATHS ∩ oracle surface = ∅ (the synthetic green is not-oracle, earned by shape)" \
  bash -c '! grep -q . < <(grep -xFf "$1" "$2")' _ "$SANDBOX/allowed.txt" "$SANDBOX/oracle.txt"

# weakness-digest.md must appear in no AFFECTED_*_PATHS edge: a declared edge naming it would bind a
# bot-diff-reachable path into the selector's audit surface. (The accept-row machinery this comment
# once cited retired with S4; the edge-surface argument is unchanged — only suite text, edges and
# oracle files move the live set, none of which a bot PR can touch.)
awk '/AFFECTED_[A-Z0-9_]*_PATHS=\(/{f=1; sub(/AFFECTED_[A-Z0-9_]*_PATHS=\(/,""); print; next} f&&/^[[:space:]]*\)/{f=0} f' "$PATHSLIB" > "$SANDBOX/edge-blocks.txt"
chk "edge-block extraction is non-vacuous (the AFFECTED_*_PATHS convention still parses)" \
  test -s "$SANDBOX/edge-blocks.txt"
chk "weakness-digest.md is named by no AFFECTED_*_PATHS edge (audit surface disjoint)" \
  bash -c '! grep -q "weakness-digest.md" "$1"' _ "$SANDBOX/edge-blocks.txt"

# The synthetic consumer pin: the sentinel name in required-checks.txt (else bot PRs stop being
# synthesized). The `affected-index-ratchet` member went away with the context itself (S4 retirement).
chk "oracle-review-required is in required-checks.txt (the synthetic set)" \
  bash -c 'grep -qx "oracle-review-required" "$1"' _ "$REQ"

# mutation-shaped guard: a scratch action.yml with an oracle path in ALLOWED_PATHS MUST intersect —
# proves the disjointness check reads the real files, not a vacuous constant.
cp "$ACT" "$SANDBOX/action-mut.yml"
python3 - "$SANDBOX/action-mut.yml" <<'PY'
import sys
s = open(sys.argv[1]).read()
s = s.replace('"knowledge-base/project/weakness-digest.md"', '"knowledge-base/project/weakness-digest.md"\n          "scripts/ci-oracle-review.sh"', 1)
open(sys.argv[1], "w").write(s)
PY
awk '/ALLOWED_PATHS=\(/{f=1;next} f&&/^\s*\)/{f=0} f' "$SANDBOX/action-mut.yml" | tr -d ' "' > "$SANDBOX/allowed-mut.txt"
chk "mutation proof: an ALLOWED_PATHS carrying an oracle path DOES intersect (the check reads real sets)" \
  bash -c 'grep -q . < <(grep -xFf "$1" "$2")' _ "$SANDBOX/allowed-mut.txt" "$SANDBOX/oracle.txt"

[[ "$passes" -ge 8 ]] && pass || fail "anti-vacuity floor: only $passes checks ran"
printf '\nbot-synthetic-unreachability.test.sh: %d passed, %d failed\n' "$passes" "$fails"
[[ "$fails" -eq 0 ]] || { printf '  - %s\n' "${FAILURES[@]}" >&2; exit 1; }
exit 0
