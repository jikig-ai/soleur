#!/usr/bin/env bash
# lint-legal-scope-block-placement.test.sh -- suite + mutation battery for gate 1.
#
# Every fixture is synthesized (cq-test-fixtures-synthesized-only). Real corpus text is
# used only for the two LIVE floors at the end (marker calibration + corpus readability),
# which assert against the working tree rather than a copied fixture.
#
# Registered by hand in scripts/test-all.sh; scripts/lint-orphan-test-suites.sh fails if
# that registration is ever dropped.

set -euo pipefail

export TMPDIR="${TMPDIR:-/var/tmp}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GATE="$REPO_ROOT/scripts/lint-legal-scope-block-placement.sh"

fails=0
passes=0
pass() { passes=$((passes + 1)); echo "[ok] $1"; }
fail() { fails=$((fails + 1)); echo "[FAIL] $1" >&2; }

if [[ ! -f "$GATE" ]]; then
  fail "gate missing at scripts/lint-legal-scope-block-placement.sh"
  echo "passed: $passes  failed: $fails" >&2
  exit 1
fi

SANDBOX_ROOT=$(mktemp -d -t legal-scope-gate.XXXXXXXX) || { echo "mktemp -d failed" >&2; exit 2; }
trap 'rm -rf "$SANDBOX_ROOT"' EXIT

# ---------------------------------------------------------------------------
# Fixture repo. A real git repo is required because the gate is added-lines-only
# and resolves its base via `git merge-base` -- a fixture that stubbed git away
# would leave the extraction (the half most likely to be wrong) untested.
# ---------------------------------------------------------------------------
#
# The fixture dir comes from `mktemp -d`, NOT an incrementing counter: every call site is
# `d=$(new_repo)`, and command substitution runs the function in a SUBSHELL, so a counter
# increment is discarded the moment it is made. Every case would then reuse one directory
# and collide on the second `git checkout -b`.
new_repo() {
  local d
  d=$(mktemp -d "$SANDBOX_ROOT/case-XXXXXXXX") || return 1
  mkdir -p "$d/docs/legal" "$d/plugins/soleur/docs/pages/legal" || return 1
  git -C "$d" init -q -b main
  git -C "$d" config user.email t@t
  git -C "$d" config user.name t
  cp "$GATE" "$d/gate.sh"
  printf '%s\n' "$d"
}

commit_all() { git -C "$1" add -A && git -C "$1" -c core.hooksPath=/dev/null commit -q -m "$2"; }

# Commit the base state on main, then move onto a feature branch. Without the branch,
# HEAD *is* main, so merge-base(HEAD, main) == HEAD and the added-lines diff is empty --
# every case would pass for the reason that it examined nothing.
commit_base() { commit_all "$1" base && git -C "$1" checkout -q -b feat; }

# Run the gate inside a fixture repo against its own main. Echoes "<rc>|<output>".
run_gate() {
  local d="$1" out rc=0
  out=$(cd "$d" && bash ./gate.sh --base main 2>&1) || rc=$?
  printf '%s|%s' "$rc" "$out"
}

# A base document whose section 4.1 genuinely governs cloud processing: the
# marker sits on a line the scope block does not own.
CLOUD_SECTION=$'## 4. Data\n\n### 4.1 Processing\n\nThe Soleur Web Platform stores account data on Jikigai infrastructure.\n\nMore prose.\n'
# A section with no cloud marker anywhere.
LOCAL_SECTION=$'## 4. Data\n\n### 4.1 Processing\n\nThe Plugin runs on your machine.\n\nMore prose.\n'

# ---------------------------------------------------------------------------
# Arm (a) -- referent/section agreement.
# ---------------------------------------------------------------------------

d=$(new_repo)
printf '%s' "$CLOUD_SECTION" > "$d/docs/legal/privacy-policy.md"
commit_base "$d"
printf 'This section applies to the Plugin only. See elsewhere.\n' >> "$d/docs/legal/privacy-policy.md"
commit_all "$d" add
res=$(run_gate "$d"); rc=${res%%|*}; out=${res#*|}
if [[ "$rc" == "1" ]]; then
  pass "arm (a): fires on an added section-scoped block inside a marker-bearing section"
else
  fail "arm (a): expected rc=1, got rc=$rc"
fi
if grep -qE 'arm \(a\)|referent' <<<"$out"; then
  pass "arm (a): failure message names the arm"
else
  fail "arm (a): failure message does not name the arm: $out"
fi

# THE CALIBRATION CASE. Measured on main 2026-08-10: at all four canonical
# locality-assertion sites the ONLY marker in the enclosing section is on the
# scope block's OWN line, and it is a cross-reference pointer ("For the Web
# Platform, see Section 4.3 below"). Scanning that line would red three of four
# blocks the corpus already treats as correct -- the same false-positive class
# the CLO caught in this gate's first draft.
d=$(new_repo)
printf '%s' "$LOCAL_SECTION" > "$d/docs/legal/privacy-policy.md"
commit_base "$d"
printf 'This section applies to the Plugin only. For the Web Platform, see Section 4.3 below.\n' >> "$d/docs/legal/privacy-policy.md"
commit_all "$d" add
res=$(run_gate "$d"); rc=${res%%|*}
if [[ "$rc" == "0" ]]; then
  pass "arm (a): a marker on the block's OWN cross-reference line does not fire"
else
  fail "arm (a): fired on the main-corpus cross-reference shape (rc=$rc) -- ${res#*|}"
fi

# The CLO's prescribed remedy form: narrow the referent in place. A
# paragraph-scoped referent is excluded from arm (a) entirely.
d=$(new_repo)
printf '%s' "$CLOUD_SECTION" > "$d/docs/legal/privacy-policy.md"
commit_base "$d"
printf 'The paragraph above applies to the Plugin only and must not be read as covering it.\n' >> "$d/docs/legal/privacy-policy.md"
commit_all "$d" add
res=$(run_gate "$d"); rc=${res%%|*}
if [[ "$rc" == "0" ]]; then
  pass "arm (a): paragraph-scoped referent in a marker-bearing section does not fire"
else
  fail "arm (a): red-lined the ruling's prescribed remedy form (rc=$rc) -- ${res#*|}"
fi

# ---------------------------------------------------------------------------
# Arm (b) -- attachment must match referent.
# ---------------------------------------------------------------------------

d=$(new_repo)
printf '%s' "$LOCAL_SECTION" > "$d/docs/legal/privacy-policy.md"
commit_base "$d"
printf -- '- **(a)** A limb.\n  This section applies to the Plugin only. See Section 9.\n' >> "$d/docs/legal/privacy-policy.md"
commit_all "$d" add
res=$(run_gate "$d"); rc=${res%%|*}; out=${res#*|}
if [[ "$rc" == "1" ]]; then
  pass "arm (b): fires when a section referent is list-indented"
else
  fail "arm (b): expected rc=1 on indented section referent, got rc=$rc"
fi
if grep -qE 'arm \(b\)|attach' <<<"$out"; then
  pass "arm (b): failure message names the arm"
else
  fail "arm (b): failure message does not name the arm: $out"
fi

# A limb-scoped rider is LEGITIMATELY indented -- forcing it flush-left would
# silently re-scope it to the whole enumeration, the same defect running the
# other way.
d=$(new_repo)
printf '%s' "$LOCAL_SECTION" > "$d/docs/legal/privacy-policy.md"
commit_base "$d"
printf -- '- **(a)** A limb.\n  The paragraph above applies to the Plugin only and must not be read as covering it.\n' >> "$d/docs/legal/privacy-policy.md"
commit_all "$d" add
res=$(run_gate "$d"); rc=${res%%|*}
if [[ "$rc" == "0" ]]; then
  pass "arm (b): an indented paragraph-scoped rider is legitimate"
else
  fail "arm (b): red-lined a legitimate indented limb rider (rc=$rc) -- ${res#*|}"
fi

# ---------------------------------------------------------------------------
# Arm (c) -- the block must discharge its own scope.
#
# The plan specified "lacks a NEGATIVE DELIMITER fails". Measured on main, three
# of the four canonical scope blocks carry no negative delimiter; they discharge
# scope with a cross-reference instead ("For the Web Platform, see Section 4.3").
# Shipping the literal rule would red text the corpus already treats as correct,
# which is the exact defect the CLO withdrew this gate's first draft over. So the
# requirement is a discharging clause: a negative delimiter OR a cross-reference.
# ---------------------------------------------------------------------------

d=$(new_repo)
printf '%s' "$LOCAL_SECTION" > "$d/docs/legal/privacy-policy.md"
commit_base "$d"
printf 'This section applies to the Plugin only.\n' >> "$d/docs/legal/privacy-policy.md"
commit_all "$d" add
res=$(run_gate "$d"); rc=${res%%|*}; out=${res#*|}
if [[ "$rc" == "1" ]]; then
  pass "arm (c): fires on a scope block that discharges nothing"
else
  fail "arm (c): expected rc=1 on an undischarged block, got rc=$rc"
fi
if grep -qE 'arm \(c\)|discharg' <<<"$out"; then
  pass "arm (c): failure message names the arm"
else
  fail "arm (c): failure message does not name the arm: $out"
fi

for discharge in \
  'This section applies to the Plugin only and must not be read as covering it.' \
  'This section applies to the Plugin only. For the Web Platform, see Section 4.3 below.'
do
  d=$(new_repo)
  printf '%s' "$LOCAL_SECTION" > "$d/docs/legal/privacy-policy.md"
  commit_base "$d"
  printf '%s\n' "$discharge" >> "$d/docs/legal/privacy-policy.md"
  commit_all "$d" add
  res=$(run_gate "$d"); rc=${res%%|*}
  if [[ "$rc" == "0" ]]; then
    pass "arm (c): discharged via '$(cut -c41-70 <<<"$discharge")...'"
  else
    fail "arm (c): red-lined a discharged block (rc=$rc): $discharge"
  fi
done

# ---------------------------------------------------------------------------
# Added-lines-only. A pre-existing violation in the base must never fire -- the
# gate ratchets, it does not audit.
# ---------------------------------------------------------------------------

d=$(new_repo)
printf '%s' "$CLOUD_SECTION" > "$d/docs/legal/privacy-policy.md"
printf 'This section applies to the Plugin only.\n' >> "$d/docs/legal/privacy-policy.md"
commit_base "$d"
printf '\nAn unrelated added line.\n' >> "$d/docs/legal/privacy-policy.md"
commit_all "$d" add
res=$(run_gate "$d"); rc=${res%%|*}
if [[ "$rc" == "0" ]]; then
  pass "added-lines-only: a pre-existing violation does not fire"
else
  fail "added-lines-only: fired on unchanged base text (rc=$rc) -- ${res#*|}"
fi

# ---------------------------------------------------------------------------
# Hunk-header shapes. `-U0` emits count-omitted forms (`@@ -2,0 +3 @@`) whose
# absent `,N` means 1; a parser assuming `,N` is always present silently drops
# those added lines and the gate reports clean.
# ---------------------------------------------------------------------------

d=$(new_repo)
printf '%s' "$CLOUD_SECTION" > "$d/docs/legal/privacy-policy.md"
commit_base "$d"
# A single-line insertion in the middle produces the count-omitted `+N` shape.
awk 'NR==5{print "This section applies to the Plugin only."} {print}' \
  "$d/docs/legal/privacy-policy.md" > "$d/tmp" && mv "$d/tmp" "$d/docs/legal/privacy-policy.md"
commit_all "$d" add
res=$(run_gate "$d"); rc=${res%%|*}
if [[ "$rc" == "1" ]]; then
  pass "hunk shapes: count-omitted single-line insertion is seen"
else
  fail "hunk shapes: count-omitted insertion was dropped (rc=$rc)"
fi

# A pure deletion hunk (`+c,0`) carries no added lines and must not crash or
# be misread as an addition.
d=$(new_repo)
printf '%s' "$CLOUD_SECTION" > "$d/docs/legal/privacy-policy.md"
commit_base "$d"
grep -v 'More prose' "$d/docs/legal/privacy-policy.md" > "$d/tmp" && mv "$d/tmp" "$d/docs/legal/privacy-policy.md"
commit_all "$d" del
res=$(run_gate "$d"); rc=${res%%|*}
if [[ "$rc" == "0" ]]; then
  pass "hunk shapes: pure-deletion hunk handled without a false fire"
else
  fail "hunk shapes: deletion hunk produced rc=$rc -- ${res#*|}"
fi

# A deleted file emits `+++ /dev/null`; keying the path off that yields a
# nonexistent file and, unguarded, a crash mid-run.
d=$(new_repo)
printf '%s' "$CLOUD_SECTION" > "$d/docs/legal/privacy-policy.md"
printf '%s' "$LOCAL_SECTION" > "$d/docs/legal/cookie-policy.md"
commit_base "$d"
rm "$d/docs/legal/cookie-policy.md"
commit_all "$d" rm
res=$(run_gate "$d"); rc=${res%%|*}
if [[ "$rc" == "0" ]]; then
  pass "deleted file (+++ /dev/null) is skipped cleanly"
else
  fail "deleted file produced rc=$rc -- ${res#*|}"
fi

# ---------------------------------------------------------------------------
# Section resolution: a block before the first heading has no enclosing section.
# It must be handled, not crash, and must not inherit a later section's markers.
# ---------------------------------------------------------------------------

d=$(new_repo)
printf 'Preamble prose.\n\n%s' "$CLOUD_SECTION" > "$d/docs/legal/privacy-policy.md"
commit_base "$d"
awk 'NR==1{print "This section applies to the Plugin only. See Section 9."} {print}' \
  "$d/docs/legal/privacy-policy.md" > "$d/tmp" && mv "$d/tmp" "$d/docs/legal/privacy-policy.md"
commit_all "$d" add
res=$(run_gate "$d"); rc=${res%%|*}
if [[ "$rc" == "0" ]]; then
  pass "preamble: a block with no enclosing heading does not inherit later markers"
else
  fail "preamble block inherited a later section's markers (rc=$rc) -- ${res#*|}"
fi

# `max(last_h2, last_h3)`: an h2 appearing AFTER an h3 must reset the section,
# or the block is scanned against a stale (and possibly marker-bearing) scope.
d=$(new_repo)
printf '## 1. Cloud\n\nThe Soleur Web Platform is cloud-hosted.\n\n### 1.1 Sub\n\nSub prose.\n\n## 2. Local\n\nPlugin prose.\n' \
  > "$d/docs/legal/privacy-policy.md"
commit_base "$d"
printf 'This section applies to the Plugin only. See Section 1.\n' >> "$d/docs/legal/privacy-policy.md"
commit_all "$d" add
res=$(run_gate "$d"); rc=${res%%|*}
if [[ "$rc" == "0" ]]; then
  pass "section resolution: a later h2 resets the enclosing section"
else
  fail "section resolution: stale section carried markers past an h2 (rc=$rc)"
fi

# ---------------------------------------------------------------------------
# Exit codes. 2 is reserved for "cannot decide" and must never collapse into 0.
# ---------------------------------------------------------------------------

d=$(new_repo)
printf '%s' "$LOCAL_SECTION" > "$d/docs/legal/privacy-policy.md"
commit_base "$d"
out=$(cd "$d" && bash ./gate.sh --base does-not-exist 2>&1) && rc=0 || rc=$?
if [[ "$rc" == "2" ]]; then
  pass "exit 2 on an unresolvable base ref"
else
  fail "unresolvable base gave rc=$rc, expected 2 -- $out"
fi

# The mirror surface is scanned too, not just the canonical one.
d=$(new_repo)
printf '%s' "$CLOUD_SECTION" > "$d/plugins/soleur/docs/pages/legal/privacy-policy.md"
commit_base "$d"
printf 'This section applies to the Plugin only. See Section 9.\n' >> "$d/plugins/soleur/docs/pages/legal/privacy-policy.md"
commit_all "$d" add
res=$(run_gate "$d"); rc=${res%%|*}
if [[ "$rc" == "1" ]]; then
  pass "the Eleventy mirror surface is scanned"
else
  fail "mirror surface was not scanned (rc=$rc)"
fi

# A non-legal markdown file must be out of scope. The corpus itself must still be present:
# an empty corpus is a legitimate exit 2 ("cannot decide"), so omitting it here would test
# the readability floor rather than the scoping.
d=$(new_repo)
mkdir -p "$d/docs/other"
printf '%s' "$LOCAL_SECTION" > "$d/docs/legal/privacy-policy.md"
printf '%s' "$CLOUD_SECTION" > "$d/docs/other/notes.md"
commit_base "$d"
printf 'This section applies to the Plugin only.\n' >> "$d/docs/other/notes.md"
commit_all "$d" add
res=$(run_gate "$d"); rc=${res%%|*}
if [[ "$rc" == "0" ]]; then
  pass "files outside the legal corpus are out of scope"
else
  fail "fired on a non-corpus file (rc=$rc)"
fi

# ---------------------------------------------------------------------------
# LIVE floors. These assert against the working tree, and they are floors, never
# equalities: an equality would red the moment the corpus legitimately grows.
# ---------------------------------------------------------------------------

markers_declared=0
markers_matched=0
while IFS= read -r m; do
  [[ -n "$m" ]] || continue
  markers_declared=$((markers_declared + 1))
  n=$(grep -rhoE -- "$m" "$REPO_ROOT/docs/legal" "$REPO_ROOT/plugins/soleur/docs/pages/legal" 2>/dev/null | grep -cE '.' || true)
  if (( n >= 1 )); then
    markers_matched=$((markers_matched + 1))
  else
    fail "marker calibration: declared marker matches nothing in the live corpus: $m"
  fi
done < <(bash "$GATE" --print-markers)

if (( markers_declared >= 3 )); then
  pass "marker calibration: $markers_declared markers declared, $markers_matched matched (floor, not equality)"
else
  fail "marker calibration: only $markers_declared markers declared -- --print-markers is likely broken"
fi

canon_n=$(find "$REPO_ROOT/docs/legal" -maxdepth 1 -name '*.md' | grep -cE '.' || true)
mirror_n=$(find "$REPO_ROOT/plugins/soleur/docs/pages/legal" -maxdepth 1 -name '*.md' | grep -cE '.' || true)
if (( canon_n >= 1 && mirror_n >= 1 )); then
  pass "corpus readable: $canon_n canonical / $mirror_n mirror documents"
else
  fail "corpus unreadable: canonical=$canon_n mirror=$mirror_n"
fi

# ---------------------------------------------------------------------------
# Mutation battery. Each mutation is proven to have LANDED (cmp against the
# pristine copy) before its verdict is trusted -- a mutation that silently
# failed to apply reports SURVIVED and reads as a gap in the fixtures.
# ---------------------------------------------------------------------------

MUT_DIR="$SANDBOX_ROOT/mutations"
mkdir -p "$MUT_DIR" || { echo "mkdir failed" >&2; exit 2; }
PRISTINE="$MUT_DIR/pristine.sh"
cp "$GATE" "$PRISTINE" || { echo "cp failed" >&2; exit 2; }

# mutate_and_check <label> <sed program> <fixture-builder>
#
# Each builder produces a fixture whose PRISTINE verdict is rc=1 (a real violation). The
# mutant is KILLED when it no longer reaches that verdict, and SURVIVES when it still
# reports rc=1 despite the mutation -- i.e. the fixtures cannot tell the two apart.
#
# The pristine verdict is re-established per row rather than assumed: a builder that
# silently stopped producing a violation would make every mutant look killed, which is the
# vacuity this battery exists to rule out.
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
  # Positive control: the unmutated gate must actually fail this fixture.
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

build_arm_a() {
  local d; d=$(new_repo) || return 1
  printf '%s' "$CLOUD_SECTION" > "$d/docs/legal/privacy-policy.md"
  commit_base "$d" >/dev/null
  printf 'This section applies to the Plugin only. See Section 9.\n' >> "$d/docs/legal/privacy-policy.md"
  commit_all "$d" add >/dev/null
  printf '%s\n' "$d"
}
build_arm_b() {
  local d; d=$(new_repo) || return 1
  printf '%s' "$LOCAL_SECTION" > "$d/docs/legal/privacy-policy.md"
  commit_base "$d" >/dev/null
  printf -- '- **(a)** A limb.\n  This section applies to the Plugin only. See Section 9.\n' >> "$d/docs/legal/privacy-policy.md"
  commit_all "$d" add >/dev/null
  printf '%s\n' "$d"
}
build_arm_c() {
  local d; d=$(new_repo) || return 1
  printf '%s' "$LOCAL_SECTION" > "$d/docs/legal/privacy-policy.md"
  commit_base "$d" >/dev/null
  printf 'This section applies to the Plugin only.\n' >> "$d/docs/legal/privacy-policy.md"
  commit_all "$d" add >/dev/null
  printf '%s\n' "$d"
}

# Neuter each arm independently by forcing its verdict variable to the pass value.
mutate_and_check "arm-a-neutered" 's/^ARM_A_ENABLED=1$/ARM_A_ENABLED=0/' build_arm_a
mutate_and_check "arm-b-neutered" 's/^ARM_B_ENABLED=1$/ARM_B_ENABLED=0/' build_arm_b
mutate_and_check "arm-c-neutered" 's/^ARM_C_ENABLED=1$/ARM_C_ENABLED=0/' build_arm_c
# Neuter the exit path: a gate that always exits 0 is the silent-pass shape.
mutate_and_check "always-exit-zero" 's/^[[:space:]]*exit 1$/  exit 0/' build_arm_a

echo "passed: $passes  failed: $fails"
(( fails == 0 )) || exit 1
