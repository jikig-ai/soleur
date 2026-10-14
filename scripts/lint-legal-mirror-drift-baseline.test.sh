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
BASE_LIB="$REPO_ROOT/scripts/lib/legal-base-ref.sh"

# Floor, not equality. Neutering pass()/fail() used to yield `passed: 0 failed: 0`, exit 0,
# and run_suite recorded [ok] -- 25 assertions and 0 assertions were indistinguishable.
MIN_ASSERTIONS=39

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
if [[ ! -f "$BASE_LIB" ]]; then
  fail "shared base resolver missing at scripts/lib/legal-base-ref.sh"
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
  mkdir -p "$d/scripts/lib"
  cp "$GATE" "$d/scripts/gate.sh"
  cp "$NORMALISE_LIB" "$d/scripts/lib/legal-normalise.sh"
  cp "$BASE_LIB" "$d/scripts/lib/legal-base-ref.sh"
  printf '%s\n' "$d"
}

commit_all() { : "${1:?fixture dir is empty; git -C <empty> would retarget this write}"; git -C "$1" add -A && git -C "$1" -c core.hooksPath=/dev/null commit -q -m "$2"; }
commit_base() { : "${1:?fixture dir is empty; git -C <empty> would retarget this write}"; commit_all "$1" base && git -C "$1" checkout -q -b feat; }

run_gate() {
  local d="$1" out rc=0
  out=$(cd "$d" && bash ./scripts/gate.sh --base main 2>&1) || rc=$?
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
if grep -qE 'REORDERED' <<<"$out"; then
  pass "pure reorder is diagnosed as REORDERED, not as growth"
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
out=$(cd "$d" && bash ./scripts/gate.sh --base does-not-exist 2>&1) && rc=0 || rc=$?
if [[ "$rc" == "2" ]]; then
  pass "exit 2 on an unresolvable base ref"
else
  fail "unresolvable base gave rc=$rc, expected 2 -- $out"
fi

d=$(new_repo)
commit_base "$d"
out=$(cd "$d" && bash ./scripts/gate.sh --base main 2>&1) && rc=0 || rc=$?
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

# Assert the RUNTIME OUTPUT, not the file text: a grep over the whole script is satisfied by
# a comment, so the operator-visible disclosure could be deleted while the suite stayed green.
d=$(new_repo)
write_pair "$d" privacy-policy "$BODY_A" "$BODY_A_DRIFTED"
commit_base "$d"
printf 'unrelated\n' > "$d/README.md"
commit_all "$d" unrelated
res=$(run_gate "$d"); out=${res#*|}
for token in '#7465' '2026-09-30'; do
  if grep -qF -- "$token" <<<"$out"; then
    pass "clean-run output carries '$token' (the freeze reads as dated, not permanent)"
  else
    fail "clean-run output omits '$token' -- the freeze reads as permanent"
  fi
done
# The withdrawn claim must not reappear: the mirror DOES disclose the Anthropic/US transfer
# (gdpr-policy.md:206), so asserting it as an omission is a false compliance claim.
# The header legitimately DISCUSSES Anthropic when recording the withdrawal, so the assertion
# is on the gate's OUTPUT, where a live claim would actually reach a reader.
if grep -qiE 'Anthropic' <<<"$out"; then
  fail "the runtime output re-asserts the withdrawn Anthropic/US omission -- the mirror discloses it"
else
  pass "the withdrawn Anthropic/US omission claim is absent from the runtime output"
fi

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
# Surface direction. The drift primitive keeps `<` (canonical) and `>` (mirror), so moving a
# clause BETWEEN surfaces is visible. With the markers stripped, deleting a clause from the
# canonical record and publishing it only on the mirror produced a byte-identical drift
# sequence and passed -- the inversion of the posture the gate's GDPR argument rests on.
# ---------------------------------------------------------------------------

d=$(new_repo)
write_pair "$d" privacy-policy "$BODY_A" "$BODY_A_DRIFTED"
commit_base "$d"
write_pair "$d" privacy-policy "$BODY_A_DRIFTED" "$BODY_A"
commit_all "$d" side-swap
res=$(run_gate "$d"); rc=${res%%|*}
if [[ "$rc" == "1" ]]; then
  pass "moving a clause from the canonical record to the mirror fires"
else
  fail "a record-side deletion published only on the mirror passed (rc=$rc) -- surface direction is unpinned"
fi

# ---------------------------------------------------------------------------
# Report quality on the failure path -- the only code no live run exercises.
# ---------------------------------------------------------------------------

# A large drift growth must still REPORT. `comm | head -12` took SIGPIPE above the 64 KiB
# pipe buffer, so under pipefail the gate aborted with rc=141 and zero output: it detected
# the drift and said nothing, outside its documented 0/1/2 contract.
big_canon="$BODY_A"
for i in $(seq 1 1200); do big_canon="${big_canon}"$'\n\nCanonical-only clause '"$i"' with enough text to exceed the pipe buffer comfortably.'; done
d=$(new_repo)
write_pair "$d" privacy-policy "$BODY_A" "$BODY_A_DRIFTED"
commit_base "$d"
write_pair "$d" privacy-policy "$big_canon" "$BODY_A_DRIFTED"
commit_all "$d" bigdrift
res=$(run_gate "$d"); rc=${res%%|*}; out=${res#*|}
if [[ "$rc" == "1" ]]; then
  pass "a 1200-line drift growth still exits 1 (no SIGPIPE abort)"
else
  fail "large drift gave rc=$rc -- expected 1 (141 means the report pipeline aborted)"
fi
if grep -qE 'Remediation|remediation|Drift lines present' <<<"$out"; then
  pass "a large drift growth still prints a report"
else
  fail "large drift printed no report (${#out} bytes) -- the failure path aborted silently"
fi

# The evidence list must show real drift lines, not the blank lines `sort` floats to the top.
d=$(new_repo)
blanky=$'Alpha clause.\n\nBeta clause.\n\nGamma clause.\n\nDelta clause.\n\nEpsilon clause.'
write_pair "$d" privacy-policy "$BODY_A" "$BODY_A_DRIFTED"
commit_base "$d"
write_pair "$d" privacy-policy "$blanky" "$BODY_A_DRIFTED"
commit_all "$d" blankdrift
res=$(run_gate "$d"); out=${res#*|}
if grep -qE '^\s+\+ [<>].*clause' <<<"$out"; then
  pass "the evidence list shows real drift lines, not blank rows"
else
  fail "the evidence list shows no content lines -- blanks consumed the budget: $(grep -c '+ *$' <<<"$out") blank rows"
fi

# ---------------------------------------------------------------------------
# Verdict must be DERIVED, not guessed from counts.
# ---------------------------------------------------------------------------

d=$(new_repo)
write_pair "$d" privacy-policy "$BODY_A" "$BODY_A_DRIFTED"
commit_base "$d"
write_pair "$d" privacy-policy $'Alpha clause.\n\nBeta clause REWORDED.\n\nGamma clause.' "$BODY_A_DRIFTED"
commit_all "$d" reword
res=$(run_gate "$d"); rc=${res%%|*}; out=${res#*|}
if [[ "$rc" == "1" ]] && grep -qE 'CONTENT CHANGED' <<<"$out"; then
  pass "an in-place reword of a drifting line is diagnosed as CONTENT CHANGED"
else
  fail "in-place reword misdiagnosed (rc=$rc): $(grep -E 'GREW|REORDERED|CONTENT' <<<"$out" | head -1)"
fi
if grep -qE 'drift grew \([0-9]+ line\(s\) -> [0-9]+' <<<"$out"; then
  fail "the self-contradicting 'grew (N -> N)' headline is back"
else
  pass "no self-contradicting headline"
fi

# ---------------------------------------------------------------------------
# Empty-normalisation floor: a doc with fewer than two `---` normalises to zero bytes, so
# two surfaces sharing NO content reported "checked, drift within the baseline".
# ---------------------------------------------------------------------------

d=$(new_repo)
write_pair "$d" privacy-policy "$BODY_A" "$BODY_A"
commit_base "$d"
printf 'We transfer your data to a third country under SCCs.\n' > "$d/docs/legal/privacy-policy.md"
printf 'We keep everything forever and tell you nothing.\n' > "$d/plugins/soleur/docs/pages/legal/privacy-policy.md"
commit_all "$d" nofrontmatter
res=$(run_gate "$d"); rc=${res%%|*}
if [[ "$rc" == "2" ]]; then
  pass "a surface that normalises to zero lines exits 2, never 'within baseline'"
else
  fail "zero-line normalisation gave rc=$rc, expected 2 -- two unrelated surfaces would pass"
fi

# ---------------------------------------------------------------------------
# Break-glass: a revert of a merged drift-reducing PR is otherwise unrevertable.
# ---------------------------------------------------------------------------

d=$(new_repo)
write_pair "$d" privacy-policy "$BODY_A" "$BODY_A_DRIFTED"
commit_base "$d"
write_pair "$d" privacy-policy "$BODY_A"$'\n\nDelta only on canonical.' "$BODY_A_DRIFTED"
commit_all "$d" grow
out=$(cd "$d" && SOLEUR_LEGAL_DRIFT_ACCEPT='revert of #1234' bash ./scripts/gate.sh --base main 2>&1) && rc=0 || rc=$?
if [[ "$rc" == "0" ]] && grep -qF 'revert of #1234' <<<"$out"; then
  pass "the break-glass downgrades to a warning and records the reason"
else
  fail "break-glass did not apply (rc=$rc)"
fi
res=$(run_gate "$d"); rc=${res%%|*}
[[ "$rc" == "1" ]] && pass "without the break-glass the same tree still fails" \
  || fail "the break-glass is on by default (rc=$rc)"

# ---------------------------------------------------------------------------
# The freeze must not outlive its remediation date silently.
# ---------------------------------------------------------------------------

d=$(new_repo)
write_pair "$d" privacy-policy "$BODY_A" "$BODY_A_DRIFTED"
commit_base "$d"
printf 'unrelated\n' > "$d/README.md"
commit_all "$d" unrelated
out=$(cd "$d" && SOLEUR_LEGAL_DRIFT_TODAY=2026-10-01 bash ./scripts/gate.sh --base main 2>&1) && rc=0 || rc=$?
if [[ "$rc" == "0" ]] && grep -qE 'passed its .* remediation target' <<<"$out"; then
  pass "past the remediation target with drift remaining, the gate warns"
else
  fail "no expiry warning past the target (rc=$rc) -- the freeze reads as managed forever"
fi
out=$(cd "$d" && SOLEUR_LEGAL_DRIFT_TODAY=2026-01-01 bash ./scripts/gate.sh --base main 2>&1) && rc=0 || rc=$?
if grep -qE 'passed its .* remediation target' <<<"$out" && grep -qF '#7465' <<<"$out"; then
  fail "the expiry warning fires before the target date"
else
  pass "before the target date the expiry warning is silent"
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
  cp "$mdir/gate.sh" "$d/scripts/gate.sh"
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
build_sideswap() {
  local d; d=$(new_repo) || return 1
  write_pair "$d" privacy-policy "$BODY_A" "$BODY_A_DRIFTED"
  commit_base "$d" >/dev/null
  write_pair "$d" privacy-policy "$BODY_A_DRIFTED" "$BODY_A"
  commit_all "$d" swap >/dev/null
  printf '%s\n' "$d"
}
build_reword() {
  local d; d=$(new_repo) || return 1
  write_pair "$d" privacy-policy "$BODY_A" "$BODY_A_DRIFTED"
  commit_base "$d" >/dev/null
  write_pair "$d" privacy-policy $'Alpha clause.\n\nBeta clause REWORDED.\n\nGamma clause.' "$BODY_A_DRIFTED"
  commit_all "$d" reword >/dev/null
  printf '%s\n' "$d"
}

# Real axes: the drift primitive, the surface marker, the empty-normalisation floor.
mutate_and_check "surface-marker-stripped" 's/printf "%s%s\\n", side, text/printf "%s\\n", text/' build_sideswap
# The empty-normalisation floor's pristine verdict is rc=2, which mutate_and_check cannot
# express (its contract is an rc=1 positive control), and its defect needs a frontmatter-less
# pair rather than a reword. Both are why the first attempt at this row reported SURVIVED
# against a fixture that could not exhibit the defect.
_enf_dir="$MUT_DIR/empty-norm-floor-removed"
mkdir -p "$_enf_dir"
sed -E 's/if \(\( c_norm_n == 0 \|\| m_norm_n == 0 \)\); then/if (( 0 )); then/' "$PRISTINE" > "$_enf_dir/gate.sh"
if cmp -s "$PRISTINE" "$_enf_dir/gate.sh"; then
  fail "mutation 'empty-norm-floor-removed' did not land -- verdict would be meaningless"
else
  _mk_emptynorm() {
    local d; d=$(new_repo) || return 1
    write_pair "$d" privacy-policy "$BODY_A" "$BODY_A"
    commit_base "$d" >/dev/null
    printf 'We transfer your data to a third country under SCCs.\n' > "$d/docs/legal/privacy-policy.md"
    printf 'We keep everything forever and tell you nothing.\n' > "$d/plugins/soleur/docs/pages/legal/privacy-policy.md"
    commit_all "$d" nofm >/dev/null
    printf '%s\n' "$d"
  }
  _d=$(_mk_emptynorm); _res=$(run_gate "$_d"); _rc=${_res%%|*}
  if [[ "$_rc" != "2" ]]; then
    fail "mutation 'empty-norm-floor-removed': positive control did not exit 2 (rc=$_rc) -- verdict vacuous"
  else
    _d=$(_mk_emptynorm); cp "$_enf_dir/gate.sh" "$_d/scripts/gate.sh"
    _res=$(run_gate "$_d"); _rc=${_res%%|*}
    if [[ "$_rc" == "2" ]]; then
      fail "mutation 'empty-norm-floor-removed' SURVIVED -- two unrelated surfaces would pass as 'within baseline'"
    else
      pass "mutation 'empty-norm-floor-removed' killed (verdict moved 2 -> $_rc)"
    fi
  fi
fi
mutate_and_check "ratchet-neutered" 's/^RATCHET_ENABLED=1$/RATCHET_ENABLED=0/' build_grow
# Neuter order sensitivity: compare drift as an unordered set, which is exactly the
# blindness that let the real ordering defect through three green gates.
mutate_and_check "order-blind" 's/^ORDER_SENSITIVE=1$/ORDER_SENSITIVE=0/' build_reorder
# Neuter the new-pair rule: inherit an empty baseline instead of requiring zero drift.
mutate_and_check "new-pair-unchecked" 's/^NEW_PAIR_MUST_BE_CLEAN=1$/NEW_PAIR_MUST_BE_CLEAN=0/' build_new_pair
# The silent-pass shape: a gate that always exits 0.
mutate_and_check "always-exit-zero" 's/^[[:space:]]*exit 1$/  exit 0/' build_grow

# ---------------------------------------------------------------------------
# PUBLISHED LINK FORM (#7349). The mirror is served at /legal/<slug>/, so a relative
# `.md` target resolves under that route and 404s; the canonical copy keeps `.md`
# because it is read on GitHub. The drift check CANNOT see this -- normalize_*()
# collapses both link forms to one token, correctly, for body equivalence.
# ---------------------------------------------------------------------------

# L1: a bare .md link on the MIRROR is caught.
d=$(new_repo)
write_pair "$d" cookie-policy "$BODY_A" "$BODY_A"
commit_base "$d"
mirror_doc cookie-policy "$BODY_A"$'\n\nSee [the AUP](acceptable-use-policy.md).' \
  > "$d/plugins/soleur/docs/pages/legal/cookie-policy.md"
commit_all "$d" link >/dev/null
r=$(run_gate "$d"); rc="${r%%|*}"; out="${r#*|}"
if [[ "$rc" != "0" ]] && grep -q "PUBLISHED LINK 404s" <<<"$out"; then
  pass "L1: bare .md link on the mirror is rejected"
else
  fail "L1: bare .md link on the mirror was NOT rejected (rc=$rc)"
fi

# L2: the ANCHORED form. The first regex missed it, and a cross-reference INTO a rights
# section is exactly where an anchor gets used -- so the likeliest shape was the blind one.
d=$(new_repo)
write_pair "$d" cookie-policy "$BODY_A" "$BODY_A"
commit_base "$d"
mirror_doc cookie-policy "$BODY_A"$'\n\nSee [rights](gdpr-policy.md#your-rights).' \
  > "$d/plugins/soleur/docs/pages/legal/cookie-policy.md"
commit_all "$d" anchor >/dev/null
r=$(run_gate "$d"); rc="${r%%|*}"; out="${r#*|}"
if [[ "$rc" != "0" ]] && grep -q "PUBLISHED LINK 404s" <<<"$out"; then
  pass "L2: anchored .md link on the mirror is rejected"
else
  fail "L2: anchored .md link (#frag) slipped through (rc=$rc)"
fi

# L3: the ../ form.
d=$(new_repo)
write_pair "$d" cookie-policy "$BODY_A" "$BODY_A"
commit_base "$d"
mirror_doc cookie-policy "$BODY_A"$'\n\nSee [pp](../legal/privacy-policy.md).' \
  > "$d/plugins/soleur/docs/pages/legal/cookie-policy.md"
commit_all "$d" dotdot >/dev/null
r=$(run_gate "$d"); rc="${r%%|*}"; out="${r#*|}"
if [[ "$rc" != "0" ]] && grep -q "PUBLISHED LINK 404s" <<<"$out"; then
  pass "L3: ../ .md link on the mirror is rejected"
else
  fail "L3: ../ .md link slipped through (rc=$rc)"
fi

# L4: the SERVED form passes, and so does a .md link on the CANONICAL side -- the
# canonical copy is GitHub-rendered, where `.md` is the correct form. A check that
# flagged it would be wrong, and would push authors to break the record.
d=$(new_repo)
canon_doc cookie-policy "$BODY_A"$'\n\nSee [the AUP](acceptable-use-policy.md).' \
  > "$d/docs/legal/cookie-policy.md"
mirror_doc cookie-policy "$BODY_A"$'\n\nSee [the AUP](/legal/acceptable-use-policy/).' \
  > "$d/plugins/soleur/docs/pages/legal/cookie-policy.md"
commit_base "$d"
r=$(run_gate "$d"); rc="${r%%|*}"; out="${r#*|}"
if [[ "$rc" == "0" ]]; then
  pass "L4: canonical .md + mirror /legal/<slug>/ both pass (no false positive)"
else
  fail "L4: FALSE POSITIVE on correct link forms (rc=$rc): $out"
fi

# L5: BOTH defects at once. The link check used to `exit 1` before the drift report, so a
# PR with both learned about only the link -- fix, push, wait for CI, learn about the
# drift. Two serial round-trips, and the same regression class the gate's own comment
# records having fixed once. This asserts BOTH findings appear in ONE run.
d=$(new_repo)
write_pair "$d" cookie-policy "$BODY_A" "$BODY_A_DRIFTED"
commit_base "$d"
mirror_doc cookie-policy $'Alpha clause.\n\nDelta clause.'$'\n\nSee [the AUP](acceptable-use-policy.md).' \
  > "$d/plugins/soleur/docs/pages/legal/cookie-policy.md"
commit_all "$d" both >/dev/null
r=$(run_gate "$d"); rc="${r%%|*}"; out="${r#*|}"
if [[ "$rc" != "0" ]] && grep -q "PUBLISHED LINK 404s" <<<"$out" \
   && grep -qE "GREW|CONTENT CHANGED|REORDERED" <<<"$out"; then
  pass "L5: link AND drift findings both reported in a single run"
else
  fail "L5: one finding suppressed the other (rc=$rc): $out"
fi

echo "passed: $passes  failed: $fails"

total=$((passes + fails))
if (( total < MIN_ASSERTIONS )); then
  echo "suite ran only ${total} assertions, expected at least ${MIN_ASSERTIONS} -- assertions are not running" >&2
  exit 1
fi
(( fails == 0 )) || exit 1
