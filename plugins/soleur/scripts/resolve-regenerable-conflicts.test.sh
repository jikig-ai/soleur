#!/usr/bin/env bash
# Guard 1 (#8377, ADR-230) — resolve-regenerable-conflicts.sh fails CLOSED.
#
# ── THE PROPERTY ────────────────────────────────────────────────────────────────────────────
# The resolver commits a merge ONLY when every conflicted path is a CONTENT conflict on a
# resolvable path, every regen command exited 0, and no conflict survives. On any other input
# the tree is byte-identical to entry and nothing is committed.
#
# That asymmetry is the whole design. This script runs unattended from three sync paths, and
# the thing it commits is an artifact a human will not read -- a single-line compiled JSON. A
# resolver that is merely USUALLY right silently ships a wrong model to the web-platform C4
# viewer, which renders it for repos that have no compiler to check it with. So every row below
# that is not the exact happy path asserts BOTH a non-zero exit AND an unchanged tree; "it
# errored" alone is not the property, because a half-applied merge left behind also errors.
#
# ── WHY ROWS 1/3/4/6/7/8 ARE ONE LOOP ──────────────────────────────────────────────────────
# They are not six properties; they are six INPUTS to one property (fail closed on anything
# that is not the happy path). Writing them as six hand-rolled cases invites six slightly
# different notions of "unchanged", and the one that drifts is the one that stops asserting.
# The loop applies a single tree-fingerprint comparison to all of them.
#
# ── WHAT THE TREE FINGERPRINT COVERS ───────────────────────────────────────────────────────
# HEAD sha + porcelain status + the content hash of every tracked file. HEAD alone would miss
# a left-behind merge (MERGE_HEAD with a dirty index does not move HEAD); status alone would
# miss a commit; content alone would miss both.
export TMPDIR="${TMPDIR:-/var/tmp}"

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$SCRIPT_DIR/resolve-regenerable-conflicts.sh"

passes=0; fails=0; CASES_RUN=0; FAILED=()
pass() { passes=$((passes + 1)); echo "  PASS: $1"; }
fail() { fails=$((fails + 1)); FAILED+=("$1"); echo "  FAIL: $1" >&2; }

_iv_p="$passes"; _iv_f="$fails"; _iv_n="${#FAILED[@]}"
{ pass "self-test"; fail "self-test"; } >/dev/null 2>&1
if [[ "$passes" -ne $((_iv_p + 1)) || "$fails" -ne $((_iv_f + 1)) || "${#FAILED[@]}" -ne $((_iv_n + 1)) ]]; then
  printf '[FATAL] instrument self-test: the verdict helpers did not both record\n' >&2; exit 1
fi
passes=0; fails=0; FAILED=(); CASES_RUN=0

[[ -f "$SUT" ]] || { echo "[FATAL] SUT not found at $SUT" >&2; exit 1; }

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

SANDBOX="$(mktemp -d)"; assert_fixture_dir "$SANDBOX"
trap 'rm -rf "$SANDBOX"' EXIT

MODEL="knowledge-base/engineering/architecture/diagrams/model.likec4.json"
SRC="knowledge-base/engineering/architecture/diagrams/model.c4"

_git() { git -C "$1" -c user.email=t@t -c user.name=t "${@:2}"; }

# tree_fp <repo> — HEAD + status + every tracked file's content hash.
tree_fp() {
  local r="$1"
  {
    _git "$r" rev-parse HEAD 2>/dev/null || echo "NOHEAD"
    _git "$r" status --porcelain 2>/dev/null
    _git "$r" ls-files -s 2>/dev/null
    # MERGE_HEAD is not visible in any of the above when the index is clean.
    [[ -f "$r/.git/MERGE_HEAD" ]] && echo "MERGE_IN_PROGRESS"
  } | git hash-object --stdin
}

# mkrepo <name> — two branches whose .c4 SOURCE text-merges cleanly while the compiled
# single-line JSON conflicts. That is the real shape: .c4 edits land in different regions,
# and the artifact is one line, so it collides on every concurrent edit.
mkrepo() {  # <name> [ok|fail]
  local r="$SANDBOX/$1"; assert_fixture_dir "$r"
  mkdir -p "$r/knowledge-base/engineering/architecture/diagrams" "$r/scripts"
  printf 'first\nx\nx\nx\nx\nx\nx\nx\nx\nlast\n' > "$r/$SRC"
  printf '{"v":"base"}\n' > "$r/$MODEL"
  printf '{"v":"base2"}\n' > "$r/knowledge-base/engineering/architecture/diagrams/second.json"
  printf 'readme base\n' > "$r/README.md"
  # THE REGEN STUB GOES IN THE BASE COMMIT, and that placement is load-bearing twice over.
  # (a) Untracked, it makes the tree dirty and every case refuses on the clean-tree
  #     precondition -- passing the fail-closed rows for entirely the wrong reason.
  # (b) Committed on ONE branch only, it DIFFERS between the sides and becomes a conflict of
  #     its own on `scripts/regenerate-c4-model.sh` -- a non-resolvable path, so rows that
  #     should fail on their own subject instead fail on the harness. Measured: row 3 was
  #     green that way while never reaching the logic it exists to test.
  _write_regen_stub "$r" "${2:-ok}"
  _git "$r" init -q -b main
  _git "$r" add -A >/dev/null; _git "$r" commit -q -m base

  _git "$r" checkout -q -b feature
  sed -i 's/^last$/last-FEATURE/' "$r/$SRC"
  printf '{"v":"feature"}\n' > "$r/$MODEL"
  _git "$r" add -A >/dev/null; _git "$r" commit -q -m feature

  _git "$r" checkout -q main
  sed -i 's/^first$/first-MAIN/' "$r/$SRC"
  printf '{"v":"main"}\n' > "$r/$MODEL"
  _git "$r" add -A >/dev/null; _git "$r" commit -q -m main

  _git "$r" checkout -q feature
  printf '%s' "$r"
}

# The `ok` stub DERIVES its output from the .c4 source on disk, so the committed artifact
# reveals WHICH tree the regen saw. Regen-after-merge yields first-MAIN|last-FEATURE;
# regen-before-merge would yield first|last-FEATURE. That is row 5.
_write_regen_stub() {
  local r="$1" mode="$2"
  if [[ "$mode" == "fail" ]]; then
    printf '#!/usr/bin/env bash\necho "stub regen: deliberate failure" >&2\nexit 9\n' \
      > "$r/scripts/regenerate-c4-model.sh"
    chmod +x "$r/scripts/regenerate-c4-model.sh"
    return
  fi
  _write_regen_stub_ok "$r"
}
_write_regen_stub_ok() {
  cat > "$1/scripts/regenerate-c4-model.sh" <<STUB
#!/usr/bin/env bash
set -euo pipefail
R="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")/.." && pwd)"
f="\$R/$SRC"
printf '{"from":"%s|%s"}\n' "\$(head -1 "\$f")" "\$(tail -1 "\$f")" > "\$R/$MODEL"
STUB
  chmod +x "$1/scripts/regenerate-c4-model.sh"
}

run_sut() {  # <repo> <base-ref> [extra env assignments via RESOLVABLE_OVERRIDE]
  local r="$1" base="$2"; shift 2
  local out rc=0
  out="$(cd "$r" && env "$@" bash "$SUT" "$base" 2>&1)" || rc=$?
  printf '%s\n%s' "$out" "$rc"
}
sut_rc()  { tail -n1 <<<"$1"; }
sut_out() { sed '$d' <<<"$1"; }

echo "=== resolve-regenerable-conflicts (Guard 1) ==="

# ── HAPPY PATH + row 5 (order) + H1 ────────────────────────────────────────────────────────
echo ""
echo "--- happy path: a lone resolvable content conflict is merged and committed ---"
r="$(mkrepo happy)"
before_head="$(_git "$r" rev-parse HEAD)"
res="$(run_sut "$r" main)"
CASES_RUN=$((CASES_RUN + 1))
[[ "$(sut_rc "$res")" == "0" ]] && pass "happy: exit 0" || fail "happy: exit $(sut_rc "$res") — $(sut_out "$res")"
CASES_RUN=$((CASES_RUN + 1))
if [[ "$(_git "$r" rev-parse HEAD)" != "$before_head" ]]; then
  pass "happy: a merge commit exists (H1 — this is the assertion a missing resolver call breaks)"
else
  fail "happy: HEAD did not move — no merge was committed"
fi
CASES_RUN=$((CASES_RUN + 1))
[[ -z "$(_git "$r" status --porcelain)" ]] && pass "happy: tree is clean after the commit" \
  || fail "happy: tree dirty after commit: $(_git "$r" status --porcelain)"
CASES_RUN=$((CASES_RUN + 1))
if grep -q 'SOLEUR_REGEN_ON_CONFLICT' <<<"$(sut_out "$res")"; then
  pass "happy: emits the SOLEUR_REGEN_ON_CONFLICT marker"
else
  fail "happy: no marker — the run is invisible to its caller: $(sut_out "$res")"
fi
# ROW 5 — regen ran AFTER the merge, against the merged sources.
CASES_RUN=$((CASES_RUN + 1))
committed="$(cat "$r/$MODEL")"
if [[ "$committed" == *'first-MAIN|last-FEATURE'* ]]; then
  pass "row 5: the artifact was regenerated from the MERGED tree"
elif [[ "$committed" == *'first|last-FEATURE'* ]]; then
  fail "row 5: regen ran BEFORE the merge — the artifact reflects HEAD, not the merge result"
else
  fail "row 5: unexpected artifact content: $committed"
fi
CASES_RUN=$((CASES_RUN + 1))
[[ -z "$(_git "$r" diff --name-only --diff-filter=U)" ]] && pass "row 5: no conflict survives" \
  || fail "row 5: a conflicted path survived the commit"

# ── P1 (must-PASS): the base ref given as a SHA rather than a branch name ───────────────────
echo ""
echo "--- P1 (must-PASS): base ref as a raw SHA ---"
r="$(mkrepo p1)"
main_sha="$(_git "$r" rev-parse main)"
before_head="$(_git "$r" rev-parse HEAD)"
res="$(run_sut "$r" "$main_sha")"
CASES_RUN=$((CASES_RUN + 1))
[[ "$(sut_rc "$res")" == "0" ]] && pass "P1: a SHA base ref exits 0" \
  || fail "P1: a SHA base ref exited $(sut_rc "$res") — $(sut_out "$res")"
CASES_RUN=$((CASES_RUN + 1))
[[ "$(_git "$r" rev-parse HEAD)" != "$before_head" ]] && pass "P1: the merge was committed" \
  || fail "P1: HEAD did not move"

# ── ROW 2: the regen command fails ─────────────────────────────────────────────────────────
echo ""
echo "--- row 2: a failing regen command aborts the merge ---"
r="$(mkrepo row2 fail)"
fp_before="$(tree_fp "$r")"
res="$(run_sut "$r" main)"
CASES_RUN=$((CASES_RUN + 1))
[[ "$(sut_rc "$res")" != "0" ]] && pass "row 2: non-zero on regen failure" \
  || fail "row 2: exited 0 despite the regen failing"
CASES_RUN=$((CASES_RUN + 1))
[[ "$(tree_fp "$r")" == "$fp_before" ]] && pass "row 2: tree byte-identical (merge aborted)" \
  || fail "row 2: the tree changed — a failed regen left a partial merge behind"
CASES_RUN=$((CASES_RUN + 1))
if grep -q 'regen failed' <<<"$(sut_out "$res")"; then
  pass "row 2: stderr says 'regen failed' (distinct from 'not applicable')"
else
  fail "row 2: the failure class is not named: $(sut_out "$res")"
fi

# ── FAIL-CLOSED TABLE — rows 1/3/4/6/7/8, one property, one loop ───────────────────────────
echo ""
echo "--- fail-closed table (rows 1, 3, 4, 6, 7, 8) ---"

# Each entry: <name>|<setup-fn>|<override-or-empty>
setup_row1() {  # a second, NON-resolvable path also conflicts
  local r="$1"
  _git "$r" checkout -q main; printf 'readme MAIN\n' > "$r/README.md"
  _git "$r" add -A >/dev/null; _git "$r" commit -q -m main-readme
  _git "$r" checkout -q feature; printf 'readme FEATURE\n' > "$r/README.md"
  _git "$r" add -A >/dev/null; _git "$r" commit -q -m feature-readme
}
setup_row3() {  # TWO resolvable paths conflict; the stub regenerates only the first
  local r="$1"
  local second="knowledge-base/engineering/architecture/diagrams/second.json"
  # second.json exists in the base commit (see mkrepo), so both sides MODIFY it and this is a
  # genuine content/content conflict -- the case row 3 is about. Creating it on both branches
  # instead would be add/add, which the conflict-KIND check rejects, and row 3 would go RED
  # without ever reaching the residual logic it exists to exercise.
  _git "$r" checkout -q main; printf '{"v":"main2"}\n' > "$r/$second"
  _git "$r" add -A >/dev/null; _git "$r" commit -q -m main-second
  _git "$r" checkout -q feature; printf '{"v":"feature2"}\n' > "$r/$second"
  _git "$r" add -A >/dev/null; _git "$r" commit -q -m feature-second
  printf '%s\tbash scripts/regenerate-c4-model.sh\n%s\tbash scripts/regenerate-c4-model.sh\n' \
    "$MODEL" "$second" > "${r}.override.tsv"
}
setup_row4() {  # the resolvable set is EMPTY
  local r="$1"; : > "${r}.override.tsv"
}
setup_row6() {  # modify/delete, not a content conflict
  local r="$1"
  _git "$r" checkout -q main; _git "$r" rm -q "$MODEL"
  _git "$r" commit -q -m main-deletes-model
  _git "$r" checkout -q feature
}
setup_row7() {  # the resolvable path is a symlink
  local r="$1"
  printf 'DO NOT WRITE THROUGH ME\n' > "$r/victim.txt"
  rm -f "$r/$MODEL"; ln -s "victim.txt" "$r/$MODEL"
  # COMMITTED, not left in the worktree: an untracked symlink makes the tree dirty and the
  # clean-tree precondition refuses first, so the symlink refusal is never exercised and
  # deleting it survives mutation.
  _git "$r" add -A >/dev/null; _git "$r" commit -q -m feature-symlinks-the-model
}
setup_row7b() {  # BOTH sides symlink the path, to DIFFERENT targets
  # Row 7 (one side a symlink, the other a regular file) is `CONFLICT (distinct types)`, which
  # the conflict-KIND check rejects before the loop -- so it does NOT exercise the in-loop
  # symlink refusal, and deleting that refusal survives row 7 untouched (measured).
  # Two symlinks with different targets is a CONTENT conflict on a RESOLVABLE path: the loop
  # is entered and `-L` is the only thing standing between the regen command and a write
  # through the link. This is the row that makes that guard falsifiable.
  local r="$1"
  printf 'DO NOT WRITE THROUGH ME\n' > "$r/victim.txt"
  printf 'other\n' > "$r/other.txt"
  rm -f "$r/$MODEL"; ln -s "victim.txt" "$r/$MODEL"
  _git "$r" add -A >/dev/null; _git "$r" commit -q -m feature-symlink-victim
  _git "$r" checkout -q main
  rm -f "$r/$MODEL"; ln -s "other.txt" "$r/$MODEL"
  _git "$r" add -A >/dev/null; _git "$r" commit -q -m main-symlink-other
  _git "$r" checkout -q feature
}
setup_row8() {  # a merge is already in progress at entry
  local r="$1"
  _git "$r" merge main --no-edit >/dev/null 2>&1 || true   # conflicts, leaves MERGE_HEAD
}

for spec in \
  "row 1: a non-resolvable path also conflicts|setup_row1|" \
  "row 3: a second resolvable path is left conflicted|setup_row3|yes" \
  "row 4: the resolvable set is empty|setup_row4|yes" \
  "row 6: the conflict is modify/delete, not content|setup_row6|" \
  "row 7: the resolvable path is a symlink (distinct types)|setup_row7|" \
  "row 7b: both sides symlink the path to different targets|setup_row7b|" \
  "row 8: a merge is already in progress|setup_row8|" ; do
  name="${spec%%|*}"; rest="${spec#*|}"; fn="${rest%%|*}"; ovr="${rest#*|}"
  key="$(printf '%s' "$name" | tr -cd 'a-z0-9')"
  r="$(mkrepo "$key")"
  "$fn" "$r"
  fp_before="$(tree_fp "$r")"
  if [[ -n "$ovr" ]]; then
    res="$(run_sut "$r" main "RESOLVABLE_OVERRIDE=${r}.override.tsv")"
  else
    res="$(run_sut "$r" main)"
  fi
  CASES_RUN=$((CASES_RUN + 1))
  [[ "$(sut_rc "$res")" != "0" ]] && pass "$name -> non-zero" \
    || fail "$name -> exited 0; the resolver committed something it should have refused"
  CASES_RUN=$((CASES_RUN + 1))
  if [[ "$(tree_fp "$r")" == "$fp_before" ]]; then
    pass "$name -> tree byte-identical to entry"
  else
    fail "$name -> the tree CHANGED; fail-closed means nothing is touched"
  fi
done

# Row 8's extra observable: the refusal must NAME the in-progress merge. A conflicted merge
# also leaves a dirty tree, so without this assertion the clean-tree precondition subsumes the
# MERGE_HEAD one and deleting the latter is undetectable -- and the operator gets "working tree
# is not clean" for a state whose actual remedy is `git merge --abort`.
CASES_RUN=$((CASES_RUN + 1))
r8="$SANDBOX/row8amergeisalreadyinprogress"
res8="$(run_sut "$r8" main)"
if grep -q 'merge is already in progress' <<<"$(sut_out "$res8")"; then
  pass "row 8: the refusal names the in-progress merge (not just 'tree is not clean')"
else
  fail "row 8: refusal did not name the in-progress merge: $(sut_out "$res8")"
fi

# Row 6's extra observable: the refusal must name the unresolvable KIND. Otherwise the
# resolvable-PATH check subsumes the kind check and dropping the latter survives mutation.
CASES_RUN=$((CASES_RUN + 1))
r6="$SANDBOX/row6theconflictismodifydeletenotcontent"
res6="$(run_sut "$r6" main)"
if grep -q 'unresolvable conflict kind' <<<"$(sut_out "$res6")"; then
  pass "row 6: the refusal names the unresolvable conflict KIND"
else
  fail "row 6: refusal did not name the conflict kind: $(sut_out "$res6")"
fi

# Row 3's extra observable: the artifact the stub did NOT regenerate must never be committed
# carrying conflict markers. `git add` clears the U flag, so the residual check cannot see it.
CASES_RUN=$((CASES_RUN + 1))
r3="$SANDBOX/row3asecondresolvablepathisleftconflicted"
if grep -q 'conflict markers' <<<"$(sut_out "$(run_sut "$r3" main "RESOLVABLE_OVERRIDE=${r3}.override.tsv")")"; then
  pass "row 3: refuses a path the regen left carrying conflict markers"
else
  fail "row 3: the un-regenerated path was not detected by its markers"
fi

# Row 7b's extra observable: the in-loop refusal must NAME the symlink, and the link target
# must be untouched. This is the assertion that makes deleting the `-L` guard detectable.
CASES_RUN=$((CASES_RUN + 1))
r7b="$SANDBOX/row7bbothsidessymlinkthepathtodifferenttargets"
if grep -q 'symlink' <<<"$(sut_out "$(run_sut "$r7b" main)")"; then
  pass "row 7b: the refusal names the symlink"
else
  fail "row 7b: refusal did not name the symlink: $(sut_out "$(run_sut "$r7b" main)")"
fi
CASES_RUN=$((CASES_RUN + 1))
if [[ "$(cat "$r7b/victim.txt")" == "DO NOT WRITE THROUGH ME" ]]; then
  pass "row 7b: the link target was not written through"
else
  fail "row 7b: the regen wrote through the symlink — arbitrary-file-write"
fi

# Row 7's extra observable: the link target must be untouched.
CASES_RUN=$((CASES_RUN + 1))
r7="$SANDBOX/row7theresolvablepathisasymlinkdistincttypes"
if [[ -f "$r7/victim.txt" && "$(cat "$r7/victim.txt")" == "DO NOT WRITE THROUGH ME" ]]; then
  pass "row 7: the symlink target was not written through"
else
  fail "row 7: the link target was modified — arbitrary-file-write through a planted symlink"
fi

# ── Argument handling ──────────────────────────────────────────────────────────────────────
echo ""
echo "--- argument handling ---"
r="$(mkrepo args)"
res="$(run_sut "$r" "")"
CASES_RUN=$((CASES_RUN + 1))
[[ "$(sut_rc "$res")" != "0" ]] && pass "an empty base ref is refused" \
  || fail "an empty base ref was accepted"
fp_before="$(tree_fp "$r")"
res="$(run_sut "$r" "no/such/ref")"
CASES_RUN=$((CASES_RUN + 1))
[[ "$(sut_rc "$res")" != "0" ]] && pass "an unresolvable base ref is refused" \
  || fail "an unresolvable base ref was accepted"
CASES_RUN=$((CASES_RUN + 1))
[[ "$(tree_fp "$r")" == "$fp_before" ]] && pass "an unresolvable base ref leaves the tree untouched" \
  || fail "the tree changed on an unresolvable base ref"

# ── A DIRTY TREE AT ENTRY is not applicable, and must not be swept into the merge. ─────────
echo ""
echo "--- dirty tree at entry ---"
r="$(mkrepo dirty)"
printf 'uncommitted operator work\n' > "$r/scratch.txt"
_git "$r" add scratch.txt >/dev/null
fp_before="$(tree_fp "$r")"
res="$(run_sut "$r" main)"
CASES_RUN=$((CASES_RUN + 1))
[[ "$(sut_rc "$res")" != "0" ]] && pass "a dirty tree is refused" \
  || fail "the resolver ran on a dirty tree and would have committed the operator's staged work"
CASES_RUN=$((CASES_RUN + 1))
[[ "$(tree_fp "$r")" == "$fp_before" ]] && pass "the dirty tree is untouched" \
  || fail "the resolver modified a dirty tree"

# ── NO CONFLICT AT ALL: nothing was resolved, so the answer is not 0. ──────────────────────
echo ""
echo "--- no conflict: a run that resolves nothing never returns 0 ---"
r="$(mkrepo noconflict)"
_git "$r" checkout -q -B feature main >/dev/null 2>&1
fp_before="$(tree_fp "$r")"
res="$(run_sut "$r" main)"
CASES_RUN=$((CASES_RUN + 1))
[[ "$(sut_rc "$res")" != "0" ]] && pass "a clean merge-tree is 'not applicable', not success" \
  || fail "exited 0 without resolving anything — the caller would push an empty sync"
CASES_RUN=$((CASES_RUN + 1))
[[ "$(tree_fp "$r")" == "$fp_before" ]] && pass "no-conflict leaves the tree untouched" \
  || fail "the tree changed on a no-op run"

# ── The resolver must NEVER push. ──────────────────────────────────────────────────────────
CASES_RUN=$((CASES_RUN + 1))
if grep -qE '(^|[^-[:alnum:]])git[[:space:]]+push' "$SUT"; then
  fail "the resolver contains a 'git push' — callers own the push and its rejection handling"
else
  pass "the resolver never pushes (callers own the push)"
fi

echo ""
echo "cases_run=$CASES_RUN passes=$passes fails=$fails ledger=${#FAILED[@]}"

_min_cases=34
if [[ "$CASES_RUN" -lt "$_min_cases" ]]; then
  printf '[FATAL] assertion floor: only %s case(s) ran, floor is %s\n' "$CASES_RUN" "$_min_cases" >&2; exit 1
fi
if [[ $((passes + fails)) -ne "$CASES_RUN" ]]; then
  printf '[FATAL] %s verdicts for %s cases — a case decided nothing\n' "$((passes + fails))" "$CASES_RUN" >&2; exit 1
fi
if [[ "${#FAILED[@]}" -ne "$fails" ]]; then
  printf '[FATAL] ledger/counter disagree: %s vs %s\n' "${#FAILED[@]}" "$fails" >&2; exit 1
fi
if [[ "${#FAILED[@]}" -ne 0 ]]; then
  printf '[FATAL] %s failing assertion(s):\n' "${#FAILED[@]}" >&2
  printf '  - %s\n' "${FAILED[@]}" >&2; exit 1
fi
echo "resolve-regenerable-conflicts: all $passes assertions passed"
