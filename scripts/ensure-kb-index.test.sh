#!/usr/bin/env bash
# Unit suite for scripts/ensure-kb-index.sh — the regen-if-stale gate in front of
# the untracked knowledge-base index (#8377, ADR-235). Implements Guard 2.
#
# ── WHAT THIS PINS, AND WHY A "DOES IT RUN" TEST WOULD BE WORTHLESS ─────────────────────────
# The SUT exists because INDEX.md, kb-tags.txt and kb-categories.txt stopped being committed.
# Every reader (kb-search, learnings-researcher, the retrieval bench) now calls this script
# first and trusts what it leaves behind. The whole value is therefore in the STALENESS
# DECISION, and a staleness decision has exactly two ways to be wrong:
#
#   MISSES a change  -> a reader greps an index that does not list a file that exists, and
#                       reports "no prior art" for a learning written ten minutes ago. That is
#                       the #8177 failure, and it is SILENT: the index looks fine.
#   REGENERATES always -> every reader pays 3-11 s, so callers stop calling it.
#
# Rows 1-4 drive the first; the AC2 row drives the second. Row 4 is the load-bearing one: it
# edits a tracked file's CONTENT and then moves its mtime BACKWARDS (`touch -d '2 years ago'`),
# which an mtime-based probe cannot see by construction. The SUT uses a content fingerprint
# precisely so that row can pass, and an earlier draft of the plan paired it with an mtime probe
# that this row would have made redundant.
#
# ── FIXTURE SHAPE ───────────────────────────────────────────────────────────────────────────
# Each case builds a throwaway git repo under a per-run `mktemp -d` and COPIES BOTH SCRIPTS
# into its scripts/ directory. The copy is not incidental: the SUT resolves its own
# REPO_ROOT and its sibling generator from ${BASH_SOURCE[0]}, so relocating it without
# carrying generate-kb-index.sh would exercise the missing-generator path in every row.
# A git repo (not a bare directory) because the fingerprint is built from `git ls-files -s`
# plus `git status --porcelain`, and outside a checkout both are empty.
#
# ── TRAPS DELIBERATELY AVOIDED (work/SKILL.md) ──────────────────────────────────────────────
#   1. A non-zero command inside `$( )` aborts under `set -e` before fail() prints. Every SUT
#      invocation is `rc=0; out=$(…) || rc=$?`, and the suite runs under `set -uo pipefail`
#      WITHOUT `-e`.
#   2. `grep -q` on a PIPE can SIGPIPE the producer on an early match and read as NO match
#      under pipefail. Every predicate here greps a FILE directly.
#   3. A loop over an empty data source exits 0 with zero coverage — CASES_RUN is reconciled
#      against the verdict counters at the bottom, and both are floored.
#   4. `/tmp` is a shared 4 GiB tmpfs that is actively reaped here; default TMPDIR to /var/tmp.
export TMPDIR="${TMPDIR:-/var/tmp}"

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$SCRIPT_DIR/ensure-kb-index.sh"
GEN="$SCRIPT_DIR/generate-kb-index.sh"

passes=0
fails=0
CASES_RUN=0
# APPEND-ONLY FAILURE LEDGER (ADR-193). `passes + fails == CASES_RUN` is INVARIANT under the
# one substitution it must detect — redirect fail()'s increment into `passes` and the sum is
# unchanged. An entry here can only be APPENDED, so silencing a verdict means deleting
# evidence rather than moving a number between two buckets that are summed together.
FAILED=()

pass() { passes=$((passes + 1)); echo "  PASS: $1"; }
fail() { fails=$((fails + 1)); FAILED+=("$1"); echo "  FAIL: $1" >&2; }

# INSTRUMENT SELF-TEST — drive BOTH helpers once and require all three observables to move,
# before any real case, so the unwind is a reset to zero rather than a slice.
_iv_p="$passes"; _iv_f="$fails"; _iv_n="${#FAILED[@]}"
{ pass "instrument self-test: pass() records"
  fail "instrument self-test: fail() records"
} >/dev/null 2>&1
if [[ "$passes" -ne $((_iv_p + 1)) || "$fails" -ne $((_iv_f + 1)) || "${#FAILED[@]}" -ne $((_iv_n + 1)) ]]; then
  printf '[FATAL] instrument self-test: the verdict helpers did not both record (passes %s->%s, fails %s->%s, ledger %s->%s)\n' \
    "$_iv_p" "$passes" "$_iv_f" "$fails" "$_iv_n" "${#FAILED[@]}" >&2
  exit 1
fi
passes=0; fails=0; FAILED=(); CASES_RUN=0

[[ -f "$SUT" ]] || { echo "[FATAL] SUT not found at $SUT" >&2; exit 1; }
[[ -f "$GEN" ]] || { echo "[FATAL] generator not found at $GEN" >&2; exit 1; }

# The canonical fixture-dir assertion, byte-equal to the definition in
# plugins/soleur/test/test-helpers.sh. plugins/soleur/test/fixture-dir-operand-assert.test.sh
# compares every copy in the tree against that one with comments stripped — edit there, then
# re-sync here.
assert_fixture_dir() {
  case "${1-}" in
    "") printf 'FATAL: fixture dir is EMPTY; git -C "" would operate on %s\n' "$PWD" >&2; exit 2 ;;
    */../*|*/..) printf 'FATAL: fixture dir %s contains ..; refusing\n' "$1" >&2; exit 2 ;;
    /proc/*|/sys/*|/dev/*) printf 'FATAL: fixture dir %s is a synthetic-fs path; refusing\n' "$1" >&2; exit 2 ;;
    /|//|/.) printf 'FATAL: fixture dir resolves to the filesystem root; refusing\n' >&2; exit 2 ;;
    /*) : ;;
    *)  printf 'FATAL: fixture dir %s is RELATIVE; refusing\n' "$1" >&2; exit 2 ;;
  esac
}

SANDBOX="$(mktemp -d)"
assert_fixture_dir "$SANDBOX"
trap 'rm -rf "$SANDBOX"' EXIT

# mkrepo <name> — a git repo carrying both scripts and a small KB corpus.
mkrepo() {
  local r="$SANDBOX/$1"
  assert_fixture_dir "$r"
  mkdir -p "$r/scripts" "$r/knowledge-base/engineering" "$r/knowledge-base/project/learnings"
  cp "$SUT" "$r/scripts/ensure-kb-index.sh"
  cp "$GEN" "$r/scripts/generate-kb-index.sh"
  printf -- '---\ntitle: "Alpha Note"\n---\n\nbody\n' > "$r/knowledge-base/engineering/alpha.md"
  printf -- '---\ntitle: "Beta Note"\ntags: [beta-tag]\ncategory: beta-cat\n---\n\nbody\n' \
    > "$r/knowledge-base/project/learnings/beta.md"
  git -C "$r" init -q -b main
  git -C "$r" -c user.email=t@t -c user.name=t add -A >/dev/null 2>&1
  git -C "$r" -c user.email=t@t -c user.name=t commit -q -m init >/dev/null 2>&1
  printf '%s' "$r"
}

# run_sut <repo> [args...] — returns "<stdout>\n<rc>"; never aborts the suite.
run_sut() {
  local r="$1"; shift
  local out rc=0
  out="$(cd "$r" && bash scripts/ensure-kb-index.sh "$@" 2>/dev/null)" || rc=$?
  printf '%s\n%s' "$out" "$rc"
}
run_sut_err() {  # stderr instead of stdout
  local r="$1"; shift
  local out rc=0
  out="$(cd "$r" && bash scripts/ensure-kb-index.sh "$@" 2>&1 >/dev/null)" || rc=$?
  printf '%s\n%s' "$out" "$rc"
}
sut_rc()  { tail -n1 <<<"$1"; }
sut_out() { sed '$d' <<<"$1"; }

IDX="knowledge-base/INDEX.md"

echo "=== ensure-kb-index (Guard 2) ==="

# ── AC2 / P-fresh: absent -> regenerate; second call -> silent, and rewrites NOTHING ────────
echo ""
echo "--- AC2: absent regenerates, fresh is silent and idempotent ---"
r="$(mkrepo ac2)"
res="$(run_sut "$r")"
CASES_RUN=$((CASES_RUN + 1))
[[ "$(sut_rc "$res")" == "0" ]] && pass "AC2: first call exits 0" || fail "AC2: first call exited $(sut_rc "$res")"
CASES_RUN=$((CASES_RUN + 1))
if grep -q 'reason=absent' <<<"$(sut_out "$res")"; then
  pass "AC2: first call prints SOLEUR_KB_INDEX_REGEN reason=absent"
else
  fail "AC2: first call did not print reason=absent (got '$(sut_out "$res")')"
fi
for f in INDEX.md kb-tags.txt kb-categories.txt .kb-index.stamp; do
  CASES_RUN=$((CASES_RUN + 1))
  [[ -f "$r/knowledge-base/$f" ]] && pass "AC2: $f produced" || fail "AC2: $f missing after regeneration"
done
# THE PROPERTY, NOT A WALL-CLOCK NUMBER: a fresh call must rewrite nothing. Asserted by
# mtime identity across the three artifacts, so a SUT that regenerates unconditionally and
# happens to be fast still reds.
before="$(cd "$r" && ls -l --time-style=+%s knowledge-base/INDEX.md knowledge-base/kb-tags.txt knowledge-base/kb-categories.txt | awk '{print $6, $7}')"
res2="$(run_sut "$r")"
after="$(cd "$r" && ls -l --time-style=+%s knowledge-base/INDEX.md knowledge-base/kb-tags.txt knowledge-base/kb-categories.txt | awk '{print $6, $7}')"
CASES_RUN=$((CASES_RUN + 1))
[[ "$(sut_rc "$res2")" == "0" ]] && pass "AC2: second call exits 0" || fail "AC2: second call exited $(sut_rc "$res2")"
CASES_RUN=$((CASES_RUN + 1))
if [[ -z "$(sut_out "$res2")" ]]; then
  pass "AC2: a fresh index prints NOTHING (silence is the fresh signal)"
else
  fail "AC2: fresh call printed '$(sut_out "$res2")' — callers read silence as fresh"
fi
CASES_RUN=$((CASES_RUN + 1))
[[ "$before" == "$after" ]] && pass "AC2: fresh call regenerated nothing (mtimes unchanged)" \
  || fail "AC2: fresh call rewrote the artifacts — the staleness probe is not gating"

# ── Guard 2 rows 1-3: add / delete / rename an indexed file ─────────────────────────────────
echo ""
echo "--- Guard 2 rows 1-3: add, delete, rename ---"
r="$(mkrepo rows123)"; run_sut "$r" >/dev/null
printf -- '---\ntitle: "Gamma Added"\n---\n\nbody\n' > "$r/knowledge-base/engineering/gamma.md"
run_sut "$r" >/dev/null
CASES_RUN=$((CASES_RUN + 1))
grep -q 'engineering/gamma.md' "$r/$IDX" && pass "row 1: an added file appears in the index" \
  || fail "row 1: added file missing from the index — the probe missed a new file"

rm -f "$r/knowledge-base/engineering/gamma.md"
run_sut "$r" >/dev/null
CASES_RUN=$((CASES_RUN + 1))
grep -q 'engineering/gamma.md' "$r/$IDX" \
  && fail "row 2: a deleted file's row survived — only the directory mtime moved" \
  || pass "row 2: a deleted file's row is removed"

mv "$r/knowledge-base/engineering/alpha.md" "$r/knowledge-base/engineering/alpha-renamed.md"
run_sut "$r" >/dev/null
CASES_RUN=$((CASES_RUN + 1))
grep -q 'engineering/alpha-renamed.md' "$r/$IDX" && pass "row 3: the renamed path is indexed" \
  || fail "row 3: renamed path absent from the index"
CASES_RUN=$((CASES_RUN + 1))
grep -q 'engineering/alpha.md' "$r/$IDX" \
  && fail "row 3: the pre-rename row survived" \
  || pass "row 3: the pre-rename row is gone"

# ── Guard 2 row 4: a timestamp-preserving edit. THE reason the probe is a content ───────────
#    fingerprint and not an mtime comparison.
echo ""
echo "--- Guard 2 row 4: timestamp-preserving edit ---"
r="$(mkrepo row4)"; run_sut "$r" >/dev/null
CASES_RUN=$((CASES_RUN + 1))
grep -q 'Alpha Note' "$r/$IDX" && pass "row 4: precondition — the old title is indexed" \
  || fail "row 4: precondition failed, the old title was never indexed"
printf -- '---\ntitle: "Alpha Retitled"\n---\n\nbody\n' > "$r/knowledge-base/engineering/alpha.md"
touch -d '2 years ago' "$r/knowledge-base/engineering/alpha.md"
res="$(run_sut "$r")"
CASES_RUN=$((CASES_RUN + 1))
grep -q 'Alpha Retitled' "$r/$IDX" \
  && pass "row 4: a content edit with a BACKDATED mtime is detected (fingerprint, not mtime)" \
  || fail "row 4: backdated edit missed — an mtime probe would fail exactly here"
CASES_RUN=$((CASES_RUN + 1))
grep -q 'Alpha Note' "$r/$IDX" && fail "row 4: the stale title survived" \
  || pass "row 4: the stale title is gone"
CASES_RUN=$((CASES_RUN + 1))
if grep -q 'reason=stale' <<<"$(sut_out "$res")"; then
  pass "row 4: the regeneration is reported as reason=stale"
else
  fail "row 4: expected reason=stale, got '$(sut_out "$res")'"
fi

# ── Guard 2 row 3b: an exported KB_DIR must NOT steer the writes ───────────────────────────
#    KB_DIR names a `find` walk and four `mv -f` targets. It was read from the plain inherited
#    environment while THIS change wired the script into `prepare` and three SessionStart hooks
#    — so a developer with KB_DIR exported for an unrelated tool would have had four files
#    overwritten in that tree by an ordinary `bun install`, with --soft swallowing the
#    diagnostic. Same class the #8384 review closed in resolve-regenerable-conflicts.sh
#    (RESOLVABLE_OVERRIDE -> argv-only): argv cannot be inherited, an exported variable can.
echo ""
echo "--- Guard 2 row 3b: an exported KB_DIR is ignored; --kb-dir is honoured ---"
r="$(mkrepo row3b)"
mkdir -p "$r/victim"
printf 'PRECIOUS\n' > "$r/victim/INDEX.md"
# The victim tree needs an indexable file of its own, or the --kb-dir arm below asserts
# against a generator that correctly refused an empty corpus rather than against the seam.
printf -- '---\ntitle: "Victim Note"\ntags: [victim-tag]\n---\n\nbody\n' > "$r/victim/v.md"
# The fixture's OWN copy via run_sut — `bash "$SUT"` would resolve REPO_ROOT to the
# real repo and write there, so the row would assert against the wrong tree.
( cd "$r" && KB_DIR="$r/victim" bash scripts/ensure-kb-index.sh >/dev/null 2>&1 )
CASES_RUN=$((CASES_RUN + 1))
[[ "$(head -1 "$r/victim/INDEX.md")" == "PRECIOUS" ]] \
  && pass "row 3b: an exported KB_DIR does not redirect the write" \
  || fail "row 3b: exported KB_DIR steered the write — the inherited-env class is open"
CASES_RUN=$((CASES_RUN + 1))
[[ -f "$r/$IDX" ]] \
  && pass "row 3b: the default knowledge-base/ path was used instead" \
  || fail "row 3b: nothing was written to the default path"
CASES_RUN=$((CASES_RUN + 1))
( cd "$r" && bash scripts/ensure-kb-index.sh --kb-dir "$r/victim" >/dev/null 2>&1 )
[[ -f "$r/victim/kb-tags.txt" ]] \
  && pass "row 3b: --kb-dir IS honoured (the seam moved to argv, it did not disappear)" \
  || fail "row 3b: --kb-dir did not write — the argv seam is broken"

# ── Guard 2 row 4b/4c: the SECOND edit. THE case row 4 cannot reach. ───────────────────────
#    `git status --porcelain` carries a path and two status letters, never content, and
#    `ls-files -s` carries the INDEX blob, which a worktree edit does not move. So the FIRST
#    edit to a clean file is seen (a ` M` line appears) and every edit AFTER it is not --
#    nothing in the fingerprint changes. Row 4 does exactly one edit, so it is structurally
#    blind to this; measured before the fix, the second edit left the script SILENT (its
#    "the index is good" contract) with the stale tag still in kb-tags.txt.
#    Both directions matter, so each row is followed by a must-stay-silent assertion: a
#    fingerprint that regenerates unconditionally would satisfy the staleness half perfectly.
echo ""
echo "--- Guard 2 row 4b: a second edit to an already-modified TRACKED file ---"
r="$(mkrepo row4b)"; run_sut "$r" >/dev/null
printf -- '---\ntitle: "Alpha Once"\n---\n\nbody\n' > "$r/knowledge-base/engineering/alpha.md"
run_sut "$r" >/dev/null   # first edit: seen even by the pre-fix probe
printf -- '---\ntitle: "Alpha Twice"\n---\n\nbody\n' > "$r/knowledge-base/engineering/alpha.md"
res="$(run_sut "$r")"
CASES_RUN=$((CASES_RUN + 1))
grep -q 'Alpha Twice' "$r/$IDX" \
  && pass "row 4b: the SECOND edit to a tracked file is detected" \
  || fail "row 4b: second edit missed — the index still reads '$(grep -o 'Alpha [A-Za-z]*' "$r/$IDX" | head -1)'"
CASES_RUN=$((CASES_RUN + 1))
grep -q 'reason=stale' <<<"$(sut_out "$res")" \
  && pass "row 4b: reported as reason=stale" \
  || fail "row 4b: expected reason=stale, got '$(sut_out "$res")'"
CASES_RUN=$((CASES_RUN + 1))
[[ -z "$(sut_out "$(run_sut "$r")")" ]] \
  && pass "row 4b: a following no-change call stays SILENT (no over-regeneration)" \
  || fail "row 4b: regenerates when nothing changed — the fingerprint is unconditional"

echo ""
echo "--- Guard 2 row 4c: a second edit to an UNTRACKED file ---"
r="$(mkrepo row4c)"; run_sut "$r" >/dev/null
printf -- '---\ntitle: "Untracked One"\n---\n\nbody\n' > "$r/knowledge-base/engineering/new-note.md"
run_sut "$r" >/dev/null   # creation: seen (a `??` line appears)
printf -- '---\ntitle: "Untracked Two"\n---\n\nbody\n' > "$r/knowledge-base/engineering/new-note.md"
res="$(run_sut "$r")"
CASES_RUN=$((CASES_RUN + 1))
grep -q 'Untracked Two' "$r/$IDX" \
  && pass "row 4c: the SECOND edit to an untracked file is detected" \
  || fail "row 4c: second edit to an untracked file missed"
CASES_RUN=$((CASES_RUN + 1))
grep -q 'Untracked One' "$r/$IDX" \
  && fail "row 4c: the stale untracked title survived" \
  || pass "row 4c: the stale untracked title is gone"
CASES_RUN=$((CASES_RUN + 1))
[[ -z "$(sut_out "$(run_sut "$r")")" ]] \
  && pass "row 4c: a following no-change call stays SILENT (no over-regeneration)" \
  || fail "row 4c: regenerates when nothing changed"

# ── Guard 2 row 5: one target removed while the index itself is fresh ───────────────────────
echo ""
echo "--- Guard 2 row 5: per-target absence beats a fresh fingerprint ---"
r="$(mkrepo row5)"; run_sut "$r" >/dev/null
rm -f "$r/knowledge-base/kb-tags.txt"
res="$(run_sut "$r")"
CASES_RUN=$((CASES_RUN + 1))
[[ -f "$r/knowledge-base/kb-tags.txt" ]] \
  && pass "row 5: a removed facet file is recreated even though the fingerprint is unchanged" \
  || fail "row 5: kb-tags.txt was not recreated — absence is not checked per target"
CASES_RUN=$((CASES_RUN + 1))
if grep -q 'reason=absent' <<<"$(sut_out "$res")"; then
  pass "row 5: reported as reason=absent, not stale"
else
  fail "row 5: expected reason=absent, got '$(sut_out "$res")'"
fi

# ── Guard 2 row 6: the generator fails. Targets must be untouched and the temp dir gone. ────
echo ""
echo "--- Guard 2 row 6: generator failure leaves the previous index intact ---"
r="$(mkrepo row6)"; run_sut "$r" >/dev/null
pre_idx="$(md5sum < "$r/$IDX")"
pre_tags="$(md5sum < "$r/knowledge-base/kb-tags.txt")"
pre_cats="$(md5sum < "$r/knowledge-base/kb-categories.txt")"
cat > "$r/scripts/generate-kb-index.sh" <<'STUB'
#!/usr/bin/env bash
echo "stub generator: deliberate failure" >&2
exit 1
STUB
# Force staleness so the SUT actually reaches the generator.
printf -- '---\ntitle: "Forces Staleness"\n---\n\nbody\n' > "$r/knowledge-base/engineering/delta.md"
scratch="$r/scratch"; mkdir -p "$scratch"
res="$(cd "$r" && TMPDIR="$scratch" bash scripts/ensure-kb-index.sh 2>/dev/null; printf '\n%s' "$?")"
CASES_RUN=$((CASES_RUN + 1))
[[ "$(sut_rc "$res")" == "1" ]] && pass "row 6: generator failure exits 1" \
  || fail "row 6: expected exit 1, got $(sut_rc "$res")"
CASES_RUN=$((CASES_RUN + 1))
if [[ "$(md5sum < "$r/$IDX")" == "$pre_idx" \
   && "$(md5sum < "$r/knowledge-base/kb-tags.txt")" == "$pre_tags" \
   && "$(md5sum < "$r/knowledge-base/kb-categories.txt")" == "$pre_cats" ]]; then
  pass "row 6: all three targets byte-identical after a failed generation"
else
  fail "row 6: a target changed despite the generator failing — the write is not atomic"
fi
CASES_RUN=$((CASES_RUN + 1))
leftover="$(find "$scratch" -mindepth 1 -maxdepth 1 | wc -l | tr -d '[:space:]')"
[[ "$leftover" == "0" ]] && pass "row 6: the scratch directory was removed on the failure path" \
  || fail "row 6: $leftover entr(ies) left in TMPDIR — the EXIT trap does not cover this path"
CASES_RUN=$((CASES_RUN + 1))
err="$(cd "$r" && TMPDIR="$scratch" bash scripts/ensure-kb-index.sh 2>&1 >/dev/null)"
if grep -q 'ERROR' <<<"$err"; then
  pass "row 6: the failure is announced on stderr with ERROR"
else
  fail "row 6: generator failure was silent on stderr (got '$err')"
fi

# ── Guard 2 P2: --soft downgrades that same failure to a WARN and exits 0 ───────────────────
echo ""
echo "--- Guard 2 P2 (must-PASS): --soft never fails the caller ---"
CASES_RUN=$((CASES_RUN + 1))
res="$(cd "$r" && TMPDIR="$scratch" bash scripts/ensure-kb-index.sh --soft 2>/dev/null; printf '\n%s' "$?")"
[[ "$(sut_rc "$res")" == "0" ]] && pass "P2: --soft exits 0 with a failing generator" \
  || fail "P2: --soft exited $(sut_rc \"$res\") — a bun install would fail on the index"
CASES_RUN=$((CASES_RUN + 1))
softerr="$(cd "$r" && TMPDIR="$scratch" bash scripts/ensure-kb-index.sh --soft 2>&1 >/dev/null)"
if grep -q 'WARN' <<<"$softerr"; then
  pass "P2: --soft reports the failure as WARN"
else
  fail "P2: --soft swallowed the failure entirely (got '$softerr')"
fi
CASES_RUN=$((CASES_RUN + 1))
if [[ "$(md5sum < "$r/$IDX")" == "$pre_idx" ]]; then
  pass "P2: --soft left the previous index untouched"
else
  fail "P2: --soft damaged the index"
fi

# ── Guard 2 row 8: a symlinked target is refused, and the link target is untouched ──────────
echo ""
echo "--- Guard 2 row 8: symlink refusal ---"
r="$(mkrepo row8)"; run_sut "$r" >/dev/null
victim="$r/victim.txt"
printf 'DO NOT WRITE THROUGH ME\n' > "$victim"
rm -f "$r/$IDX"
ln -s "$victim" "$r/$IDX"
res="$(run_sut "$r")"
CASES_RUN=$((CASES_RUN + 1))
[[ "$(sut_rc "$res")" == "3" ]] && pass "row 8: a symlinked target exits 3" \
  || fail "row 8: expected exit 3, got $(sut_rc "$res")"
CASES_RUN=$((CASES_RUN + 1))
if [[ "$(cat "$victim")" == "DO NOT WRITE THROUGH ME" ]]; then
  pass "row 8: the link target was not written through"
else
  fail "row 8: the SUT wrote through the symlink — arbitrary-file-write"
fi
CASES_RUN=$((CASES_RUN + 1))
if grep -q 'symlink' <<<"$(run_sut_err "$r" | sed '$d')"; then
  pass "row 8: the refusal names the symlink"
else
  fail "row 8: the refusal does not say why"
fi

# ── Guard 2 P1 (must-PASS): a touched archive/ file may regenerate, but must not FAIL ───────
echo ""
echo "--- Guard 2 P1 (must-PASS): archive churn is allowed to be a redundant regen ---"
r="$(mkrepo p1)"; run_sut "$r" >/dev/null
mkdir -p "$r/knowledge-base/archive"
printf -- '---\ntitle: "Archived"\n---\n\nbody\n' > "$r/knowledge-base/archive/old.md"
res="$(run_sut "$r")"
CASES_RUN=$((CASES_RUN + 1))
[[ "$(sut_rc "$res")" == "0" ]] && pass "P1: archive churn exits 0 (a redundant regen is allowed)" \
  || fail "P1: archive churn exited $(sut_rc "$res")"
CASES_RUN=$((CASES_RUN + 1))
grep -q 'archive/old.md' "$r/$IDX" && fail "P1: an archive/ file leaked into the index" \
  || pass "P1: archive/ stays excluded from the index"

# ── AC6: no knowledge-base/ directory at all -> exit 0, write nothing ───────────────────────
echo ""
echo "--- AC6: a repo with no knowledge-base/ ---"
r="$SANDBOX/nokb"; assert_fixture_dir "$r"; mkdir -p "$r/scripts"
cp "$SUT" "$r/scripts/ensure-kb-index.sh"; cp "$GEN" "$r/scripts/generate-kb-index.sh"
git -C "$r" init -q -b main
res="$(run_sut "$r")"
CASES_RUN=$((CASES_RUN + 1))
[[ "$(sut_rc "$res")" == "0" ]] && pass "AC6: no knowledge-base/ exits 0" \
  || fail "AC6: exited $(sut_rc "$res") in a repo with no knowledge-base/"
CASES_RUN=$((CASES_RUN + 1))
[[ -d "$r/knowledge-base" ]] && fail "AC6: the SUT created a knowledge-base/ directory" \
  || pass "AC6: nothing was created"

# ── Outside a git checkout: the fingerprint is empty, so regenerate once then no-op ─────────
echo ""
echo "--- non-git checkout ---"
r="$SANDBOX/nogit"; assert_fixture_dir "$r"
mkdir -p "$r/scripts" "$r/knowledge-base/engineering"
cp "$SUT" "$r/scripts/ensure-kb-index.sh"; cp "$GEN" "$r/scripts/generate-kb-index.sh"
printf -- '---\ntitle: "Loose Note"\n---\n\nbody\n' > "$r/knowledge-base/engineering/loose.md"
res="$(run_sut "$r")"
CASES_RUN=$((CASES_RUN + 1))
[[ "$(sut_rc "$res")" == "0" ]] && pass "non-git: exits 0" || fail "non-git: exited $(sut_rc "$res")"
CASES_RUN=$((CASES_RUN + 1))
[[ -f "$r/$IDX" ]] && pass "non-git: an index is produced" || fail "non-git: no index produced"
res="$(run_sut "$r")"
CASES_RUN=$((CASES_RUN + 1))
[[ -z "$(sut_out "$res")" ]] && pass "non-git: the second call is silent (no regen loop)" \
  || fail "non-git: regenerates on every call — '$(sut_out "$res")'"

# ── Argument handling ──────────────────────────────────────────────────────────────────────
echo ""
echo "--- argument handling ---"
r="$(mkrepo args)"
res="$(run_sut "$r" --nonsense)"
CASES_RUN=$((CASES_RUN + 1))
[[ "$(sut_rc "$res")" == "2" ]] && pass "an unknown argument exits 2" \
  || fail "unknown argument exited $(sut_rc "$res"), expected 2"

# ── DISPATCH ROWS. These mutate the SUT COPY inside the fixture, never the tracked file. ────
# Row 7 (script stubbed to a no-op) and H1 (the fixture edit that creates staleness removed)
# are the suite's own dispatch checks: each asserts that a row ABOVE would have failed. A
# suite that cannot state which mutation kills which row is a suite that has not been
# mutation-tested, and these two are the ones a future edit is most likely to silently void.
echo ""
echo "--- dispatch rows 7 / H1 ---"
r="$(mkrepo row7)"; run_sut "$r" >/dev/null
printf -- '---\ntitle: "Epsilon Added"\n---\n\nbody\n' > "$r/knowledge-base/engineering/epsilon.md"
printf '#!/usr/bin/env bash\nexit 0\n' > "$r/scripts/ensure-kb-index.sh"   # row 7 mutation
run_sut "$r" >/dev/null
CASES_RUN=$((CASES_RUN + 1))
if grep -q 'engineering/epsilon.md' "$r/$IDX"; then
  fail "row 7: a no-op SUT still produced the row — row 1 is vacuous and proves nothing"
else
  pass "row 7: a no-op SUT leaves the index stale (row 1 is a real assertion)"
fi

r="$(mkrepo h1)"; run_sut "$r" >/dev/null
# H1: run the row-4 assertion with the staleness-creating edit DROPPED.
res="$(run_sut "$r")"
CASES_RUN=$((CASES_RUN + 1))
if [[ -n "$(sut_out "$res")" ]]; then
  fail "H1: the SUT regenerated without any edit — row 4's 'regenerated' assertion would pass on a fresh fixture"
else
  pass "H1: no edit means no regeneration (row 4 cannot pass vacuously)"
fi

echo ""
echo "cases_run=$CASES_RUN passes=$passes fails=$fails ledger=${#FAILED[@]}"

# Every gate below reports with `printf` + `exit 1` DIRECTLY, never through pass()/fail() — a
# floor dispatched through the helper it backstops is disarmed by the same one-line edit that
# disarms every assertion under it. `[FATAL]` is the sentinel scripts/guard-vacuity-floor.test.sh
# matches on; a bare `FATAL:` scores the mutant CONSTRUCTION rather than FIRES.
_min_cases=48
if [[ "$CASES_RUN" -lt "$_min_cases" ]]; then
  printf '[FATAL] assertion floor: only %s case(s) ran, floor is %s — the suite lost coverage\n' \
    "$CASES_RUN" "$_min_cases" >&2
  exit 1
fi
if [[ $((passes + fails)) -ne "$CASES_RUN" ]]; then
  printf '[FATAL] %s verdicts for %s cases — a case decided nothing\n' \
    "$((passes + fails))" "$CASES_RUN" >&2
  exit 1
fi
if [[ "${#FAILED[@]}" -ne "$fails" ]]; then
  printf '[FATAL] ledger/counter disagree: %s ledger entries vs fails=%s — the verdict machinery was tampered with\n' \
    "${#FAILED[@]}" "$fails" >&2
  exit 1
fi
if [[ "${#FAILED[@]}" -ne 0 ]]; then
  printf '[FATAL] %s failing assertion(s):\n' "${#FAILED[@]}" >&2
  printf '  - %s\n' "${FAILED[@]}" >&2
  exit 1
fi
echo "ensure-kb-index: all $passes assertions passed"
