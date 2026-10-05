#!/usr/bin/env bash
# legal-normalise.test.sh -- unit + parity suite for the shared legal-corpus normaliser.
#
# The engine is pinned against a SYNTHESIZED fixture pair, not against live corpus content
# and not against `git show main:<file>` -- see the rationale at the pin itself. Both are
# traps: a live-content pin reds on every legal edit, and a `git show main:` baseline flips
# from "old engine" to "new engine" the moment this lands, so it is green on the branch and
# red on main for the next contributor.
#
# The extraction's byte-for-byte parity against the pre-extraction implementation was
# verified independently at review time (all 18 corpus hashes reproduced from the functions
# as they existed at cdc42a5df^). That was a one-time claim about a refactor; it is recorded
# in the commit rather than re-asserted on every CI run against a moving corpus.
#
# Auto-globbed by test-all.sh (`scripts/lib/*.test.sh`); no run_suite line needed.

set -euo pipefail

# A direct invocation of this suite inherits the bare /tmp (a machine-global, RAM-backed
# tmpfs shared by every parallel worktree); test-all.sh and run-registered-suites.sh both
# default TMPDIR to /var/tmp. Without this, verdicts become a function of another
# session's disk usage.
export TMPDIR="${TMPDIR:-/var/tmp}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LIB="$REPO_ROOT/scripts/lib/legal-normalise.sh"
CANONICAL_DIR="$REPO_ROOT/docs/legal"
MIRROR_DIR="$REPO_ROOT/plugins/soleur/docs/pages/legal"

fails=0
passes=0
pass() { passes=$((passes + 1)); echo "[ok] $1"; }
fail() { fails=$((fails + 1)); echo "[FAIL] $1" >&2; }

# ---------------------------------------------------------------------------
# Engine pin.
#
# WHY THIS IS ANCHORED TO A SYNTHESIZED FIXTURE AND NOT TO THE LIVE CORPUS.
# The first version of this suite pinned the sha256 of `normalize_*(<live document>)` for all
# nine pairs. Its stated purpose was proving the EXTRACTION was behaviour-preserving -- an
# engine claim, true once -- but a hash is a function of the engine AND the document. So a
# one-word edit to any legal document turned the required `test` context red with the message
# `parity: canonical <doc> changed`, framed as an extraction failure, with no remediation text
# anywhere in the file and no bypass. That made it a THIRD content pin over the corpus,
# alongside tc-version.ts and legal-doc-shas.ts, and the only one with no documented refresh
# path. #7349 edits this corpus next.
#
# The fixture is immutable, so the pin stays a pure engine assertion and is invariant to
# corpus edits -- while KEEPING the property that made the table worth having: gate 2 measures
# both surfaces with the HEAD normaliser, so a weakened `collapse()` shrinks both sides
# together and the ratchet cannot see it. This pin can. The suite proves that below by
# weakening the engine and asserting the hash moves.
#
# The fixture pair is built to exercise every collapse rule: both link notations, the
# template-var expansions, the agent/skill/department counts, the soleur.ai vs www variants,
# frontmatter, the Eleventy page-hero scaffolding, and a double blank line.
FIXTURE_DIR="$REPO_ROOT/scripts/lib/fixtures/legal-normalise"
FIXTURE_NORMALISED_SHA="a90acb1a46fdf6ed"

# ---------------------------------------------------------------------------
# 1. The library exists and defines exactly the three documented functions.
# ---------------------------------------------------------------------------
if [[ -f "$LIB" ]]; then
  pass "library exists at scripts/lib/legal-normalise.sh"
else
  fail "library missing at scripts/lib/legal-normalise.sh"
  echo "suite cannot continue without the library" >&2
  echo "passed: $passes  failed: $fails" >&2
  exit 1
fi

# shellcheck source=/dev/null
. "$LIB"

for fn in normalize_canonical normalize_plugin collapse; do
  if [[ "$(type -t "$fn")" == "function" ]]; then
    pass "sourcing defines $fn"
  else
    fail "sourcing did not define $fn"
  fi
done

# ---------------------------------------------------------------------------
# 2. Double-source guard. Sourcing twice must be a silent no-op that leaves the
#    functions intact -- check-tc-document-sha.sh and both gates may all source
#    it in one process.
# ---------------------------------------------------------------------------
double_rc=0
# shellcheck source=/dev/null
. "$LIB" || double_rc=$?
if [[ "$double_rc" == "0" && "$(type -t collapse)" == "function" ]]; then
  pass "double-source is a no-op and leaves functions defined"
else
  fail "double-source failed (rc=$double_rc) or clobbered the functions"
fi

# ---------------------------------------------------------------------------
# 3. Direct-execution guard. The library is not a program; running it must fail
#    loudly rather than silently exiting 0 and reading as a passing check.
# ---------------------------------------------------------------------------
direct_out=$(bash "$LIB" 2>&1) && direct_rc=0 || direct_rc=$?
if [[ "$direct_rc" != "0" ]]; then
  pass "direct execution exits non-zero (rc=$direct_rc)"
else
  fail "direct execution exited 0 -- the guard is absent or inert"
fi
if grep -qE 'source|sourced' <<<"$direct_out"; then
  pass "direct-execution guard explains it must be sourced"
else
  fail "direct-execution guard printed no actionable message: $direct_out"
fi

# ---------------------------------------------------------------------------
# 4. LC_ALL is pinned. An unpinned collation changes `sort`/character-class
#    behaviour and therefore the drift hash -- gate 2 compares hashes across
#    two checkouts, so a locale-dependent normaliser makes drift a function of
#    the runner's environment.
# ---------------------------------------------------------------------------
if grep -qE '^[[:space:]]*(export[[:space:]]+)?LC_ALL=C([[:space:]]|$)' "$LIB"; then
  pass "LC_ALL=C pinned in the library"
else
  fail "LC_ALL=C is not pinned at line-start in the library"
fi

# Behavioural companion: the same input under a different inherited locale must
# produce a byte-identical hash.
locale_fixture=$(mktemp -t legal-norm-locale.XXXXXXXX)
trap 'rm -f "$locale_fixture"' EXIT
cat > "$locale_fixture" <<'FIXTURE'
---
title: Fixture
---

# Fixture Heading

Body with an accented word: resume vs resume.
FIXTURE
h_c=$(LC_ALL=C bash -c ". '$LIB'; normalize_canonical '$locale_fixture' | collapse | sha256sum" | awk '{print $1}')
h_u=$(LC_ALL=en_US.UTF-8 bash -c ". '$LIB'; normalize_canonical '$locale_fixture' | collapse | sha256sum" | awk '{print $1}')
if [[ "$h_c" == "$h_u" ]]; then
  pass "normalisation is locale-invariant"
else
  fail "normalisation differs by inherited locale ($h_c vs $h_u)"
fi

# ---------------------------------------------------------------------------
# 5. Unit behaviour on synthesized fixtures (cq-test-fixtures-synthesized-only).
#    Each asserts one documented transform, so a regression names itself.
# ---------------------------------------------------------------------------
unit_dir=$(mktemp -d -t legal-norm-unit.XXXXXXXX) || { echo "mktemp -d failed" >&2; exit 2; }
trap 'rm -f "$locale_fixture"; rm -rf "$unit_dir"' EXIT

cat > "$unit_dir/canon.md" <<'FIXTURE'
---
title: Synth
effective: 2026-01-01
---

# Synth Document

First paragraph.


Second paragraph after a double blank.

See [the policy](privacy-policy.md) for detail.
FIXTURE

canon_out=$(normalize_canonical "$unit_dir/canon.md" | collapse)

if ! grep -qE '^title: Synth$' <<<"$canon_out"; then
  pass "canonical: frontmatter stripped"
else
  fail "canonical: frontmatter survived normalisation"
fi

if ! grep -qE '^# Synth Document[[:space:]]*$' <<<"$canon_out"; then
  pass "canonical: top-level heading stripped"
else
  fail "canonical: top-level heading survived normalisation"
fi

if grep -qE '\(LINK_PRIVACY\)' <<<"$canon_out"; then
  pass "collapse: canonical link form rewritten to LINK_PRIVACY"
else
  fail "collapse: canonical link form not rewritten"
fi

# Blank-run collapse: no two consecutive empty lines survive, and the body does
# not start with one.
blank_runs=$(awk 'BEGIN{prev=1;n=0} {if (NF==0 && prev==1) n++; prev=(NF==0)} END{print n}' <<<"$canon_out")
if [[ "$blank_runs" == "0" ]]; then
  pass "collapse: consecutive blank lines collapsed and leading blank stripped"
else
  fail "collapse: $blank_runs consecutive-blank run(s) survived"
fi

# The mirror normaliser must strip Eleventy scaffolding that has no canonical
# counterpart, and must reach the SAME collapsed body for equivalent content.
cat > "$unit_dir/mirror.md" <<'FIXTURE'
---
layout: legal.njk
title: Synth
---

<section class="page-hero">
  <div class="container">
    <h1>Synth Document</h1>
    <p>Effective 2026-01-01</p>
  </div>
</section>

First paragraph.


Second paragraph after a double blank.

See [the policy](/legal/privacy-policy/) for detail.
FIXTURE

mirror_out=$(normalize_plugin "$unit_dir/mirror.md" | collapse)
if [[ "$canon_out" == "$mirror_out" ]]; then
  pass "canonical and mirror normalise to an identical body"
else
  fail "canonical/mirror normalisation diverged on equivalent content"
  diff <(printf '%s\n' "$canon_out") <(printf '%s\n' "$mirror_out") | head -20 >&2 || true
fi

# ---------------------------------------------------------------------------
# 6. Engine pin against the synthesized fixture, and a live SMOKE check.
# ---------------------------------------------------------------------------

if [[ -f "$FIXTURE_DIR/canonical.md" && -f "$FIXTURE_DIR/mirror.md" ]]; then
  pass "parity fixtures present"
else
  fail "parity fixtures missing under scripts/lib/fixtures/legal-normalise/"
fi

fx_c=$(normalize_canonical "$FIXTURE_DIR/canonical.md" | collapse | sha256sum | awk '{print $1}')
fx_m=$(normalize_plugin    "$FIXTURE_DIR/mirror.md"    | collapse | sha256sum | awk '{print $1}')

if [[ "${fx_c:0:16}" == "$FIXTURE_NORMALISED_SHA" ]]; then
  pass "engine pin: canonical fixture normalises to the recorded hash"
else
  fail "engine pin: canonical fixture hash moved (${fx_c:0:16} != $FIXTURE_NORMALISED_SHA) -- the normaliser changed behaviour. If deliberate, re-derive this constant and say why in the commit."
fi
if [[ "$fx_c" == "$fx_m" ]]; then
  pass "engine pin: the two surfaces of the fixture normalise identically"
else
  fail "engine pin: fixture surfaces diverged -- a collapse rule regressed"
  diff <(normalize_canonical "$FIXTURE_DIR/canonical.md" | collapse) \
       <(normalize_plugin "$FIXTURE_DIR/mirror.md" | collapse) | head -20 >&2 || true
fi

# NON-VACUITY. A pin that cannot move is a comment. Weaken `collapse` in a subshell copy and
# assert the fixture hash changes -- this is the property gate 2 structurally cannot check,
# because it measures both surfaces with the same (weakened) engine.
weakened=$(mktemp -t legal-norm-weak.XXXXXXXX)
sed -E 's#^  \| awk .BEGIN\{blank=0\}.*#  | cat \\#' "$LIB" > "$weakened"
if cmp -s "$LIB" "$weakened"; then
  fail "non-vacuity probe: the weakening mutation did not land -- the pin is unproven"
else
  weak_sha=$(bash -c ". '$weakened' 2>/dev/null; normalize_canonical '$FIXTURE_DIR/canonical.md' | collapse | sha256sum" 2>/dev/null | awk '{print $1}')
  if [[ -n "$weak_sha" && "${weak_sha:0:16}" != "$FIXTURE_NORMALISED_SHA" ]]; then
    pass "non-vacuity: weakening collapse() moves the fixture hash (the pin is load-bearing)"
  else
    fail "non-vacuity: weakening collapse() left the fixture hash unchanged -- the pin proves nothing"
  fi
fi
rm -f "$weakened"

# LIVE SMOKE: every corpus pair must normalise to a NON-EMPTY body on both surfaces. This is a
# floor, not a content pin -- it cannot red on a legal edit, but it does catch the
# zero-byte-normalisation shape (a document with fewer than two `---`) that would otherwise
# make two unrelated surfaces compare equal.
checked=0
shopt -s nullglob
for cpath in "$CANONICAL_DIR"/*.md; do
  name=$(basename "$cpath" .md)
  mpath="$MIRROR_DIR/$name.md"
  [[ -f "$mpath" ]] || { fail "live smoke: no mirror for $name"; continue; }
  cn=$(normalize_canonical "$cpath" | collapse | grep -cE '.' || true)
  mn=$(normalize_plugin "$mpath" | collapse | grep -cE '.' || true)
  checked=$((checked + 1))
  (( cn > 0 )) || fail "live smoke: $name canonical normalises to zero lines"
  (( mn > 0 )) || fail "live smoke: $name mirror normalises to zero lines"
done
shopt -u nullglob

if (( checked >= 9 )); then
  pass "live smoke: $checked corpus pair(s) normalise to a non-empty body on both surfaces"
else
  fail "live smoke covered only $checked pairs -- expected at least 9"
fi

# ---------------------------------------------------------------------------
# 7. The extraction has exactly one implementation. A second copy of any of the
#    three function bodies is the drift this whole exercise exists to prevent.
# ---------------------------------------------------------------------------
dup=$(grep -rlE '^[[:space:]]*(normalize_canonical|normalize_plugin|collapse)\(\)' \
        "$REPO_ROOT/scripts" "$REPO_ROOT/apps/web-platform/scripts" 2>/dev/null \
      | grep -vE '\.test\.sh$' || true)
dup_count=$(printf '%s\n' "$dup" | grep -cE '.' || true)
if [[ "$dup_count" == "1" ]]; then
  pass "exactly one definition site for the normalisers"
else
  fail "expected 1 definition site, found $dup_count: $(printf '%s ' $dup)"
fi

echo "passed: $passes  failed: $fails"

# Floor, not equality: neutering pass()/fail() used to yield `passed: 0 failed: 0`, exit 0.
MIN_ASSERTIONS=20
total=$((passes + fails))
if (( total < MIN_ASSERTIONS )); then
  echo "suite ran only ${total} assertions, expected at least ${MIN_ASSERTIONS} -- assertions are not running" >&2
  exit 1
fi
(( fails == 0 )) || exit 1
