#!/usr/bin/env bash
# bot-synthetic-unreachability.test.sh — Guard 4 of #10859 (PR3b): the disjointness that makes the two
# new synthetic greens SOUND rather than fabricated (#6049 ceiling, ADR-139 per-gate rule).
#
# WHAT THIS PROVES, from the live files (never a pinned copy):
#   * ALLOWED_PATHS of .github/actions/bot-pr-with-synthetic-checks/action.yml is exactly
#     {knowledge-base/project/weakness-digest.md} — the surface every bot PR diff is confined to;
#   * RATCHET_ORACLE of scripts/ci-pr-affected-replay.py (imported, not grepped) is non-empty and names
#     both oracle-review-required producers (scripts/ci-oracle-review.sh + its suite);
#   * ALLOWED_PATHS ∩ RATCHET_ORACLE = ∅ — so a bot PR's `oracle-review-required` synthetic asserts the
#     `not-oracle` verdict the real sentinel would emit, and its `affected-index-ratchet` synthetic
#     asserts the unchanged-live-set verdict the real ratchet would emit;
#   * the audit input surface a bot PR could perturb (suite files + the accept file) is likewise
#     disjoint — weakness-digest.md is named by no AFFECTED_*_PATHS block and appears in no accept row;
#   * both new names are in scripts/required-checks.txt (the synthetic consumer) — a name missing there
#     would silently stop being synthesized on bot PRs, and a name here without its disjointness is a
#     fabricated green.
#
# The residual this pins: any ALLOWED_PATHS or RATCHET_ORACLE or suite-edge edit that intersects the two
# sets turns BOTH synthetic greens live — the PR that does it must first reproduce the real gates in the
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
REPLAY="$REPO_ROOT/scripts/ci-pr-affected-replay.py"
REQ="$REPO_ROOT/scripts/required-checks.txt"
PATHSLIB="$REPO_ROOT/scripts/lib/test-affected-paths.sh"
for f in "$ACT" "$REPLAY" "$REQ" "$PATHSLIB"; do
  [[ -s "$f" ]] || { printf 'FATAL: %s missing\n' "$f" >&2; exit 2; }
done

SANDBOX="$(mktemp -d "$TMPDIR/bot-unreach.XXXXXXXX")" || exit 2
trap 'rm -rf "$SANDBOX"' EXIT
for _dep in python3 bash; do command -v "$_dep" >/dev/null 2>&1 || exit 2; done

# ALLOWED_PATHS: the array literal in action.yml (the lines between `ALLOWED_PATHS=(` and `)`).
awk '/ALLOWED_PATHS=\(/{f=1;next} f&&/^\s*\)/{f=0} f' "$ACT" | tr -d ' "' > "$SANDBOX/allowed.txt"
chk "ALLOWED_PATHS is exactly {knowledge-base/project/weakness-digest.md} (anti-vacuity + bound)" \
  test "$(sort "$SANDBOX/allowed.txt")" = "knowledge-base/project/weakness-digest.md"

# RATCHET_ORACLE: imported from the replay module — never grepped, so a renamed constant cannot pass vacuously.
python3 - "$REPLAY" > "$SANDBOX/oracle.txt" 2>"$SANDBOX/oracle.err" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("replay", sys.argv[1])
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
oracle = getattr(mod, "RATCHET_ORACLE", None)
if not isinstance(oracle, (tuple, list)) or not oracle:
    sys.exit(3)
for p in oracle:
    print(p)
PY
chk "RATCHET_ORACLE imports from the live replay module and is non-empty" \
  test -s "$SANDBOX/oracle.txt"
chk "RATCHET_ORACLE names both oracle-review-required producers" \
  bash -c 'grep -qxF "scripts/ci-oracle-review.sh" "$1" && grep -qxF "scripts/ci-oracle-review.test.sh" "$1"' _ "$SANDBOX/oracle.txt"

# The disjointness itself: a bot PR diff is confined to ALLOWED_PATHS; none of those paths is oracle surface.
chk "ALLOWED_PATHS ∩ RATCHET_ORACLE = ∅ (the synthetic green is not-oracle, earned by shape)" \
  bash -c '! grep -xFf "$1" "$2" | grep -q .' _ "$SANDBOX/allowed.txt" "$SANDBOX/oracle.txt"

# weakness-digest.md must appear in no AFFECTED_*_PATHS edge: a declared edge naming it would bind a
# bot-diff-reachable path into the selector's audit surface. (It MAY appear as an accept-row TARGET —
# accept rows exempt a named path; the named file's content never moves the live set, only suite text,
# edges, oracle files and the accept file itself do — none of which a bot PR can touch.)
chk "weakness-digest.md is named by no AFFECTED_*_PATHS edge (audit surface disjoint)" \
  bash -c '! grep -n "weakness-digest.md" "$1" | grep -q "AFFECTED_.*_PATHS="' _ "$PATHSLIB"

# The synthetic consumer pins: both names in required-checks.txt (else bot PRs stop being synthesized).
chk "affected-index-ratchet is in required-checks.txt (the synthetic set)" \
  bash -c 'grep -qx "affected-index-ratchet" "$1"' _ "$REQ"
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
  bash -c 'grep -xFf "$1" "$2" | grep -q .' _ "$SANDBOX/allowed-mut.txt" "$SANDBOX/oracle.txt"

[[ "$passes" -ge 8 ]] && pass || fail "anti-vacuity floor: only $passes checks ran"
printf '\nbot-synthetic-unreachability.test.sh: %d passed, %d failed\n' "$passes" "$fails"
[[ "$fails" -eq 0 ]] || { printf '  - %s\n' "${FAILURES[@]}" >&2; exit 1; }
exit 0
