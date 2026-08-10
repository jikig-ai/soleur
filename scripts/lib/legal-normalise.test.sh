#!/usr/bin/env bash
# legal-normalise.test.sh -- unit + parity suite for the shared legal-corpus normaliser.
#
# WHY THE PARITY BASELINE IS A FROZEN LITERAL AND NOT `git show main:<file>`:
# the file this suite proves equivalence against (check-tc-document-sha.sh) BECOMES the
# post-extraction implementation at merge, so a `git show main:` baseline flips from
# "old engine" to "new engine" the moment this lands -- green on the branch, red on main
# for the next contributor. The 18 SHAs below were measured against the pre-extraction
# tree and are committed as constants.
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
# Pre-extraction parity baseline. Measured on the tree immediately before the
# functions moved out of check-tc-document-sha.sh. `<name> <canonical> <mirror>`,
# each a sha256 of `normalize_* | collapse`.
# ---------------------------------------------------------------------------
BASELINE=(
  "acceptable-use-policy 9809739ac2519c3f 2095f728bf007ca3"
  "cookie-policy f3e21f21356175fb e460ba6050407d3a"
  "corporate-cla 540994d513155ddb bfbb8e015ae53819"
  "data-protection-disclosure 9b8edfe33264bf54 e5b6a58b8d96edde"
  "disclaimer 15871117be1a047a 5c4f3de12b6cbff9"
  "gdpr-policy f7093acaed6e89e0 e648212ed2525e85"
  "individual-cla eca28d482fe92b0f 10ba3796533c2f5e"
  "privacy-policy fa4df13fd4b77c15 d9fa044ae0caf263"
  "terms-and-conditions bae2422886453166 bae2422886453166"
)

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
# 6. Parity against the pre-extraction baseline, over the live corpus.
#    Minimum-cardinality guard: a loop whose data source silently yields zero
#    rows exits 0 with no coverage, which is the failure this suite exists to
#    make impossible.
# ---------------------------------------------------------------------------
checked=0
for row in "${BASELINE[@]}"; do
  read -r name want_canon want_mirror <<<"$row"
  cpath="$CANONICAL_DIR/$name.md"
  mpath="$MIRROR_DIR/$name.md"

  if [[ ! -f "$cpath" ]]; then
    fail "parity: canonical missing for $name"
    continue
  fi
  if [[ ! -f "$mpath" ]]; then
    fail "parity: mirror missing for $name"
    continue
  fi

  got_canon=$(normalize_canonical "$cpath" | collapse | sha256sum | awk '{print $1}')
  got_mirror=$(normalize_plugin "$mpath" | collapse | sha256sum | awk '{print $1}')
  checked=$((checked + 1))

  if [[ "${got_canon:0:16}" == "$want_canon" ]]; then
    pass "parity: canonical $name unchanged by the extraction"
  else
    fail "parity: canonical $name changed (${got_canon:0:16} != $want_canon)"
  fi
  if [[ "${got_mirror:0:16}" == "$want_mirror" ]]; then
    pass "parity: mirror $name unchanged by the extraction"
  else
    fail "parity: mirror $name changed (${got_mirror:0:16} != $want_mirror)"
  fi
done

if (( checked >= 9 )); then
  pass "parity covered $checked document pairs"
else
  fail "parity covered only $checked pairs -- expected at least 9"
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
(( fails == 0 )) || exit 1
