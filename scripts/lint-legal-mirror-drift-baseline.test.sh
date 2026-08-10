#!/usr/bin/env bash
# lint-legal-mirror-drift-baseline.test.sh -- suite + mutation battery for gate 2.
#
# Fixtures are synthesized (cq-test-fixtures-synthesized-only); the live corpus is used
# only for the readability floor and the real-tree no-fire check at the end.
#
# Registered by hand in scripts/test-all.sh; scripts/lint-orphan-test-suites.sh fails if
# that registration is ever dropped.

set -euo pipefail

export TMPDIR="${TMPDIR:-/var/tmp}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GATE="$REPO_ROOT/scripts/lint-legal-mirror-drift-baseline.sh"
NORMALISE_LIB="$REPO_ROOT/scripts/lib/legal-normalise.sh"

fails=0
passes=0
pass() { passes=$((passes + 1)); echo "[ok] $1"; }
fail() { fails=$((fails + 1)); echo "[FAIL] $1" >&2; }

if [[ ! -f "$GATE" ]]; then
  fail "gate missing at scripts/lint-legal-mirror-drift-baseline.sh"
  echo "passed: $passes  failed: $fails" >&2
  exit 1
fi
if [[ ! -f "$NORMALISE_LIB" ]]; then
  fail "shared normaliser missing at scripts/lib/legal-normalise.sh"
  echo "passed: $passes  failed: $fails" >&2
  exit 1
fi

SANDBOX_ROOT=$(mktemp -d -t legal-drift-gate.XXXXXXXX) || { echo "mktemp -d failed" >&2; exit 2; }
trap 'rm -rf "$SANDBOX_ROOT"' EXIT

# mktemp, not a counter: `d=$(new_repo)` runs in a subshell, so a counter increment would
# be discarded and every case would collide on one directory.
new_repo() {
  local d
  d=$(mktemp -d "$SANDBOX_ROOT/case-XXXXXXXX") || return 1
  mkdir -p "$d/docs/legal" "$d/plugins/soleur/docs/pages/legal" "$d/scripts/lib" || return 1
  git -C "$d" init -q -b main
  git -C "$d" config user.email t@t
  git -C "$d" config user.name t
  cp "$GATE" "$d/gate.sh"
  cp "$NORMALISE_LIB" "$d/scripts/lib/legal-normalise.sh"
  printf '%s\n' "$d"
}

commit_all() { git -C "$1" add -A && git -C "$1" -c core.hooksPath=/dev/null commit -q -m "$2"; }
commit_base() { commit_all "$1" base && git -C "$1" checkout -q -b feat; }

run_gate() {
  local d="$1" out rc=0
  out=$(cd "$d" && bash ./gate.sh --base main 2>&1) || rc=$?
  printf '%s|%s' "$rc" "$out"
}

# Canonical and mirror bodies that normalise to comparable text. The mirror carries the
# Eleventy scaffolding the shared normaliser strips.
#
# The H1 is a CAPITALISED display title, deliberately not the (lowercase) file stem:
# normalize_canonical strips `^# [A-Z]...`, so a lowercase heading survives on the
# canonical side while normalize_plugin always strips the mirror's <h1>. That asymmetry
# would inject one line of permanent synthetic drift into every fixture and make the
# zero-drift cases unsatisfiable for a reason that has nothing to do with the gate.
canon_doc() { printf -- '---\ntitle: %s\n---\n\n# Legal Document\n\n%s\n' "$1" "$2"; }
mirror_doc() {
  printf -- '---\nlayout: legal.njk\ntitle: %s\n---\n\n<section class="page-hero">\n  <div class="container">\n    <h1>Legal Document</h1>\n  </div>\n</section>\n\n%s\n' "$1" "$2"
}

write_pair() {
  local d="$1" name="$2" canon_body="$3" mirror_body="$4"
  canon_doc "$name" "$canon_body" > "$d/docs/legal/$name.md"
  mirror_doc "$name" "$mirror_body" > "$d/plugins/soleur/docs/pages/legal/$name.md"
}

BODY_A=$'Alpha clause.\n\nBeta clause.\n\nGamma clause.'
# Pre-existing drift: the mirror is missing the Beta clause. This is the shape of the real
# corpus, which carries substantial legitimate drift -- a zero assertion is unshippable.
BODY_A_DRIFTED=$'Alpha clause.\n\nGamma clause.'

# ---------------------------------------------------------------------------
# Baseline: an untouched corpus keeps its drift and passes.
# ---------------------------------------------------------------------------

d=$(new_repo)
write_pair "$d" privacy-policy "$BODY_A" "$BODY_A_DRIFTED"
commit_base "$d"
printf 'unrelated\n' > "$d/README.md"
commit_all "$d" unrelated
res=$(run_gate "$d"); rc=${res%%|*}
if [[ "$rc" == "0" ]]; then
  pass "baseline: pre-existing drift is frozen, not required to be zero"
else
  fail "baseline: pre-existing drift red-lined an untouched corpus (rc=$rc) -- ${res#*|}"
fi

# ---------------------------------------------------------------------------
# One surface edited without the other -- drift GROWS. This is the core case.
# ---------------------------------------------------------------------------

d=$(new_repo)
write_pair "$d" privacy-policy "$BODY_A" "$BODY_A_DRIFTED"
commit_base "$d"
write_pair "$d" privacy-policy "$BODY_A"$'\n\nDelta clause added only to canonical.' "$BODY_A_DRIFTED"
commit_all "$d" canonical-only
res=$(run_gate "$d"); rc=${res%%|*}; out=${res#*|}
if [[ "$rc" == "1" ]]; then
  pass "fires when one surface is edited without the other"
else
  fail "did not fire on a canonical-only edit (rc=$rc) -- $out"
fi
if grep -qE 'privacy-policy' <<<"$out"; then
  pass "failure message names the drifting document"
else
  fail "failure message does not name the drifting document: $out"
fi
if grep -qE 'docs/legal/privacy-policy\.md' <<<"$out" && grep -qE 'plugins/soleur/docs/pages/legal/privacy-policy\.md' <<<"$out"; then
  pass "failure message names BOTH surface paths"
else
  fail "failure message does not name both paths: $out"
fi

# ---------------------------------------------------------------------------
# Lockstep edit -- both surfaces gain the same clause. Drift is unchanged, so this
# must NOT fire. A full-diff or SHA-based comparison false-fires here because every
# position header shifts; this is why the primitive strips positions.
# ---------------------------------------------------------------------------

d=$(new_repo)
write_pair "$d" privacy-policy "$BODY_A" "$BODY_A_DRIFTED"
commit_base "$d"
write_pair "$d" privacy-policy $'Preamble added to both.\n\n'"$BODY_A" $'Preamble added to both.\n\n'"$BODY_A_DRIFTED"
commit_all "$d" lockstep
res=$(run_gate "$d"); rc=${res%%|*}
if [[ "$rc" == "0" ]]; then
  pass "lockstep edit shifting every position does not fire"
else
  fail "lockstep edit false-fired (rc=$rc) -- ${res#*|}"
fi

# ---------------------------------------------------------------------------
# Reduction -- the mirror is synced toward canonical. Drift shrinks. This MUST pass,
# or the gate blocks the very remediation it exists to make safe (#7349).
# ---------------------------------------------------------------------------

d=$(new_repo)
write_pair "$d" privacy-policy "$BODY_A" "$BODY_A_DRIFTED"
commit_base "$d"
write_pair "$d" privacy-policy "$BODY_A" "$BODY_A"
commit_all "$d" reduce
res=$(run_gate "$d"); rc=${res%%|*}
if [[ "$rc" == "0" ]]; then
  pass "drift reduction passes (the remediation is never blocked)"
else
  fail "drift reduction was blocked (rc=$rc) -- ${res#*|}"
fi

# ---------------------------------------------------------------------------
# THE CASE THIS GATE EXISTS FOR. Same content, different ORDER on the two surfaces.
# The canonical and mirror both contain every clause, so a set-only or count-only
# comparison sees nothing; the published page presents the rights in a sequence the
# record does not. legal-doc-consistency compares heading sequence and the SHA guard
# compares canonical hashes -- neither sees a mirror-side reordering of body text.
# ---------------------------------------------------------------------------

d=$(new_repo)
write_pair "$d" privacy-policy "$BODY_A" "$BODY_A"
commit_base "$d"
write_pair "$d" privacy-policy "$BODY_A" $'Gamma clause.\n\nAlpha clause.\n\nBeta clause.'
commit_all "$d" reorder
res=$(run_gate "$d"); rc=${res%%|*}
if [[ "$rc" == "1" ]]; then
  pass "fires when the same content lands in a different position on the two surfaces"
else
  fail "reordering on the mirror was invisible (rc=$rc) -- ${res#*|}"
fi

# PURE order change: the drift MULTISET is identical between base and HEAD and only the
# SEQUENCE differs. The case above is also caught by growth, so it cannot distinguish an
# order-sensitive gate from an order-blind one; this one can, and it is what the
# `order-blind` mutation is measured against.
ORDER_BASE_CANON=$'P clause.\n\nQ clause.'
ORDER_BASE_MIRROR=$'P clause.\n\nQ clause.\n\nX clause.\n\nY clause.'
ORDER_HEAD_MIRROR=$'P clause.\n\nQ clause.\n\nY clause.\n\nX clause.'

d=$(new_repo)
write_pair "$d" privacy-policy "$ORDER_BASE_CANON" "$ORDER_BASE_MIRROR"
commit_base "$d"
write_pair "$d" privacy-policy "$ORDER_BASE_CANON" "$ORDER_HEAD_MIRROR"
commit_all "$d" pure-reorder
res=$(run_gate "$d"); rc=${res%%|*}; out=${res#*|}
if [[ "$rc" == "1" ]]; then
  pass "fires on a PURE reorder (identical drift multiset, different sequence)"
else
  fail "pure reorder was invisible (rc=$rc) -- $out"
fi
if grep -qE 'ORDER change' <<<"$out"; then
  pass "pure reorder is diagnosed as an order change, not as growth"
else
  fail "pure reorder was not diagnosed as an order change: $out"
fi

# ---------------------------------------------------------------------------
# Pair lifecycle.
# ---------------------------------------------------------------------------

# A pair that did not exist at the base has no baseline to ratchet against, so it must
# start clean. This is also how a RENAME is handled without consulting git history: the
# renamed doc is simply a new pair at HEAD and must have zero drift. A history-based
# rule would read a head-side rename as a shrink and silently hide the drift.
d=$(new_repo)
write_pair "$d" privacy-policy "$BODY_A" "$BODY_A"
commit_base "$d"
write_pair "$d" cookie-policy "$BODY_A" "$BODY_A_DRIFTED"
commit_all "$d" new-pair-drifting
res=$(run_gate "$d"); rc=${res%%|*}; out=${res#*|}
if [[ "$rc" == "1" ]]; then
  pass "a NEW pair carrying drift fails (no baseline to inherit)"
else
  fail "new drifting pair passed (rc=$rc) -- $out"
fi

d=$(new_repo)
write_pair "$d" privacy-policy "$BODY_A" "$BODY_A"
commit_base "$d"
write_pair "$d" cookie-policy "$BODY_A" "$BODY_A"
commit_all "$d" new-pair-clean
res=$(run_gate "$d"); rc=${res%%|*}
if [[ "$rc" == "0" ]]; then
  pass "a NEW pair with zero drift passes"
else
  fail "clean new pair was rejected (rc=$rc) -- ${res#*|}"
fi

# Deleting one surface leaves the other published with no counterpart.
d=$(new_repo)
write_pair "$d" privacy-policy "$BODY_A" "$BODY_A"
write_pair "$d" cookie-policy "$BODY_A" "$BODY_A"
commit_base "$d"
rm "$d/plugins/soleur/docs/pages/legal/cookie-policy.md"
commit_all "$d" one-sided-delete
res=$(run_gate "$d"); rc=${res%%|*}; out=${res#*|}
if [[ "$rc" == "1" ]]; then
  pass "a one-sided delete fails"
else
  fail "one-sided delete passed (rc=$rc) -- $out"
fi

# Deleting BOTH surfaces is a legitimate retirement.
d=$(new_repo)
write_pair "$d" privacy-policy "$BODY_A" "$BODY_A"
write_pair "$d" cookie-policy "$BODY_A" "$BODY_A"
commit_base "$d"
rm "$d/docs/legal/cookie-policy.md" "$d/plugins/soleur/docs/pages/legal/cookie-policy.md"
commit_all "$d" retire
res=$(run_gate "$d"); rc=${res%%|*}
if [[ "$rc" == "0" ]]; then
  pass "retiring BOTH surfaces of a pair passes"
else
  fail "full retirement was rejected (rc=$rc) -- ${res#*|}"
fi

# ---------------------------------------------------------------------------
# Fail-closed paths. Exit 2 is "cannot decide" and must never collapse into 0.
# ---------------------------------------------------------------------------

d=$(new_repo)
write_pair "$d" privacy-policy "$BODY_A" "$BODY_A"
commit_base "$d"
out=$(cd "$d" && bash ./gate.sh --base does-not-exist 2>&1) && rc=0 || rc=$?
if [[ "$rc" == "2" ]]; then
  pass "exit 2 on an unresolvable base ref"
else
  fail "unresolvable base gave rc=$rc, expected 2 -- $out"
fi

d=$(new_repo)
commit_base "$d"
out=$(cd "$d" && bash ./gate.sh --base main 2>&1) && rc=0 || rc=$?
if [[ "$rc" == "2" ]]; then
  pass "exit 2 on an empty corpus (never a vacuous 0)"
else
  fail "empty corpus gave rc=$rc, expected 2 -- $out"
fi

# A canonical doc with no mirror at all is unpaired -- undecidable, not clean.
d=$(new_repo)
write_pair "$d" privacy-policy "$BODY_A" "$BODY_A"
printf -- '---\ntitle: Orphan\n---\n\n# Orphan\n\nText.\n' > "$d/docs/legal/orphan.md"
commit_base "$d"
printf 'unrelated\n' > "$d/README.md"
commit_all "$d" unrelated
res=$(run_gate "$d"); rc=${res%%|*}
if [[ "$rc" == "2" ]]; then
  pass "exit 2 on an unpaired canonical document"
else
  fail "unpaired document gave rc=$rc, expected 2 -- ${res#*|}"
fi

# A missing shared normaliser must fail closed, not silently skip normalisation.
d=$(new_repo)
write_pair "$d" privacy-policy "$BODY_A" "$BODY_A"
commit_base "$d"
rm "$d/scripts/lib/legal-normalise.sh"
res=$(run_gate "$d"); rc=${res%%|*}
if [[ "$rc" == "2" ]]; then
  pass "exit 2 when the shared normaliser is absent"
else
  fail "missing normaliser gave rc=$rc, expected 2 -- ${res#*|}"
fi

# ---------------------------------------------------------------------------
# The frozen-drift header must name what it freezes and carry the remediation date.
# A permanent freeze with no date is documentary evidence that the divergence was
# measured, understood, and institutionalised (Art. 83(2)(b)/(c)).
# ---------------------------------------------------------------------------

for token in '7349' '2026-09-30' 'Anthropic'; do
  if grep -qF -- "$token" "$GATE"; then
    pass "gate header carries '$token'"
  else
    fail "gate header does not mention '$token' -- the freeze reads as permanent"
  fi
done

# ---------------------------------------------------------------------------
# Live floors.
# ---------------------------------------------------------------------------

canon_n=$(find "$REPO_ROOT/docs/legal" -maxdepth 1 -name '*.md' | grep -cE '.' || true)
mirror_n=$(find "$REPO_ROOT/plugins/soleur/docs/pages/legal" -maxdepth 1 -name '*.md' | grep -cE '.' || true)
if (( canon_n >= 1 && mirror_n >= 1 && canon_n == mirror_n )); then
  pass "live corpus is fully paired: $canon_n canonical / $mirror_n mirror"
else
  fail "live corpus pairing is broken: canonical=$canon_n mirror=$mirror_n"
fi

# ---------------------------------------------------------------------------
# Mutation battery. Every row proves the mutation LANDED and that the pristine gate
# actually fails the fixture, before any verdict is trusted.
# ---------------------------------------------------------------------------

MUT_DIR="$SANDBOX_ROOT/mutations"
mkdir -p "$MUT_DIR" || { echo "mkdir failed" >&2; exit 2; }
PRISTINE="$MUT_DIR/pristine.sh"
cp "$GATE" "$PRISTINE" || { echo "cp failed" >&2; exit 2; }

mutate_and_check() {
  local label="$1" sedprog="$2" builder="$3"
  local mdir="$MUT_DIR/$label"
  mkdir -p "$mdir" || return 2
  sed -E "$sedprog" "$PRISTINE" > "$mdir/gate.sh" || return 2

  if cmp -s "$PRISTINE" "$mdir/gate.sh"; then
    fail "mutation '$label' did not land (file unchanged) -- verdict would be meaningless"
    return 0
  fi

  local d res rc
  d=$("$builder") || return 2
  res=$(run_gate "$d"); rc=${res%%|*}
  if [[ "$rc" != "1" ]]; then
    fail "mutation '$label': positive control did not fail (rc=$rc) -- verdict is vacuous"
    return 0
  fi

  d=$("$builder") || return 2
  cp "$mdir/gate.sh" "$d/gate.sh"
  res=$(run_gate "$d"); rc=${res%%|*}
  if [[ "$rc" == "1" ]]; then
    fail "mutation '$label' SURVIVED -- the fixtures cannot detect this defect"
  else
    pass "mutation '$label' killed (verdict moved 1 -> $rc)"
  fi
}

build_grow() {
  local d; d=$(new_repo) || return 1
  write_pair "$d" privacy-policy "$BODY_A" "$BODY_A_DRIFTED"
  commit_base "$d" >/dev/null
  write_pair "$d" privacy-policy "$BODY_A"$'\n\nDelta only on canonical.' "$BODY_A_DRIFTED"
  commit_all "$d" grow >/dev/null
  printf '%s\n' "$d"
}
# PURE reorder: base and HEAD carry the identical drift multiset, differing only in
# sequence. A fixture that also grows drift would be caught by the ratchet alone and could
# never distinguish an order-sensitive gate from an order-blind one.
build_reorder() {
  local d; d=$(new_repo) || return 1
  write_pair "$d" privacy-policy "$ORDER_BASE_CANON" "$ORDER_BASE_MIRROR"
  commit_base "$d" >/dev/null
  write_pair "$d" privacy-policy "$ORDER_BASE_CANON" "$ORDER_HEAD_MIRROR"
  commit_all "$d" reorder >/dev/null
  printf '%s\n' "$d"
}
build_new_pair() {
  local d; d=$(new_repo) || return 1
  write_pair "$d" privacy-policy "$BODY_A" "$BODY_A"
  commit_base "$d" >/dev/null
  write_pair "$d" cookie-policy "$BODY_A" "$BODY_A_DRIFTED"
  commit_all "$d" newpair >/dev/null
  printf '%s\n' "$d"
}

# Neuter the ratchet: accept any HEAD drift regardless of the baseline.
mutate_and_check "ratchet-neutered" 's/^RATCHET_ENABLED=1$/RATCHET_ENABLED=0/' build_grow
# Neuter order sensitivity: compare drift as an unordered set, which is exactly the
# blindness that let the real ordering defect through three green gates.
mutate_and_check "order-blind" 's/^ORDER_SENSITIVE=1$/ORDER_SENSITIVE=0/' build_reorder
# Neuter the new-pair rule: inherit an empty baseline instead of requiring zero drift.
mutate_and_check "new-pair-unchecked" 's/^NEW_PAIR_MUST_BE_CLEAN=1$/NEW_PAIR_MUST_BE_CLEAN=0/' build_new_pair
# The silent-pass shape: a gate that always exits 0.
mutate_and_check "always-exit-zero" 's/^[[:space:]]*exit 1$/  exit 0/' build_grow

echo "passed: $passes  failed: $fails"
(( fails == 0 )) || exit 1
