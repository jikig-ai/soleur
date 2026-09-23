#!/usr/bin/env bash
# Guard 1 (#8377, ADR-235) — resolve-regenerable-conflicts.sh fails CLOSED.
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
#
# ── WHY THE SUT RUNS FROM A SANDBOX PLUGIN COPY ─────────────────────────────────────────────
# The production arm executes render-c4-model.sh from BESIDE THE RESOLVER (ADR-235 amendment),
# never from the repo being merged. So a stub renderer can only be injected the way a real
# install is laid out: a copy of the SUT inside a <root>/scripts/ directory with the stub as
# its sibling and a <root>/.claude-plugin/plugin.json. Every copy is taken from $SUT at run
# time, so a mutation battery that edits $SUT is measured by every row. The ratchet rows still
# read $SUT itself.
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

# ── SANDBOX PLUGIN ROOTS ────────────────────────────────────────────────────────────────────
# mkplugin <name> <renderer-mode|none> [plugin-name] — echoes the plugin root.
mkplugin() {
  local root="$SANDBOX/plugins-$1/soleur" mode="$2" pname="${3:-soleur}"; assert_fixture_dir "$root"
  mkdir -p "$root/scripts" "$root/.claude-plugin"
  printf '{\n  "name": "%s",\n  "description": "fixture"\n}\n' "$pname" > "$root/.claude-plugin/plugin.json"
  cp "$SUT" "$root/scripts/resolve-regenerable-conflicts.sh"
  [[ "$mode" == "none" ]] || _write_renderer "$root/scripts/render-c4-model.sh" "$mode"
  (cd "$root" && pwd -P)
}

# _write_renderer <file> <mode> — a stub with the real renderer's argv contract. It REFUSES
# any argv but `--root <existing dir>` (exit 64), so a resolver that calls it with the wrong
# shape fails loudly instead of reading a fixture. The `ok` output DERIVES from the .c4 source
# on disk and names its author, so the committed artifact shows WHICH tree it saw (row 5) and
# WHICH renderer wrote it (the decoy and wrapper rows).
_write_renderer() {
  local f="$1" mode="$2"; assert_fixture_dir "$f"
  {
    printf '#!/usr/bin/env bash\nset -euo pipefail\n'
    printf '[[ "$#" -eq 2 && "${1:-}" == "--root" && -d "${2:-}" ]] || { echo "stub renderer: bad argv: $*" >&2; exit 64; }\n'
    printf 'R="$2"\n'
    case "$mode" in
      ok|extra-mod|extra-new) _emit_ok_body "plugin" ;;
      ok-alt) _emit_ok_body "alt-plugin" ;;
      fail) printf 'echo "Invalid model.c4"; echo "    Line 3: boom (stub diagnostic)"; echo "ERROR: stub renderer refused" >&2; exit 9\n' ;;
      noop) printf 'exit 0\n' ;;
      *) echo "[FATAL] unknown renderer mode $mode" >&2; exit 2 ;;
    esac
    [[ "$mode" == "extra-mod" ]] && printf 'echo stray | tee -a "$R/README.md" >/dev/null\n'
    [[ "$mode" == "extra-new" ]] && printf 'echo stray | tee "$R/stray.txt" >/dev/null\n'
    true
  } > "$f"
  chmod +x "$f"
}
_emit_ok_body() {  # <author>
  printf 'f="$R/%s"\n' "$SRC"
  printf 'printf %s "$(head -1 "$f")" "$(tail -1 "$f")" | tee "$R/%s" >/dev/null\n' "'{\"from\":\"%s|%s\",\"by\":\"$1\"}\\n'" "$MODEL"
}

# mkrepo <name> [bare|wrapper|decoy] — two branches whose .c4 SOURCE text-merges cleanly while
# the compiled single-line JSON conflicts. That is the real shape: .c4 edits land in different
# regions, and the artifact is one line, so it collides on every concurrent edit.
#   bare     a self-hosted repo: no scripts/, no plugins/ -- the case #8542 left dead (AC1).
#   wrapper  this repo's shape: a committed scripts/regenerate-c4-model.sh that writes
#            `by:repo-wrapper`, proving the wrapper is NOT a second arm (harness row b).
#   decoy    a merged tree that ships its OWN plugins/soleur/scripts/render-c4-model.sh and a
#            GENUINE-looking plugin.json (AC4). The decoy writes `by:decoy` and touches
#            $SANDBOX/DECOY_RAN.
# Whatever the extra files, they go in the BASE commit: untracked they make the tree dirty and
# every case refuses on the clean-tree precondition; committed on one side only they become a
# conflict of their own on a non-resolvable path.
mkrepo() {
  local r="$SANDBOX/$1" shape="${2:-bare}"; assert_fixture_dir "$r"
  mkdir -p "$r/knowledge-base/engineering/architecture/diagrams"
  printf 'first\nx\nx\nx\nx\nx\nx\nx\nx\nlast\n' > "$r/$SRC"
  printf '{"v":"base"}\n' > "$r/$MODEL"
  printf '{"v":"base2"}\n' > "$r/knowledge-base/engineering/architecture/diagrams/second.json"
  printf 'readme base\n' > "$r/README.md"
  case "$shape" in
    bare) : ;;
    wrapper)
      mkdir -p "$r/scripts"
      { printf '#!/usr/bin/env bash\nset -euo pipefail\nR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"\n'
        _emit_ok_body "repo-wrapper"; } > "$r/scripts/regenerate-c4-model.sh"
      chmod +x "$r/scripts/regenerate-c4-model.sh" ;;
    decoy)
      mkdir -p "$r/plugins/soleur/scripts" "$r/plugins/soleur/.claude-plugin"
      printf '{\n  "name": "soleur"\n}\n' > "$r/plugins/soleur/.claude-plugin/plugin.json"
      { printf '#!/usr/bin/env bash\nset -euo pipefail\nR="${2:-$(pwd)}"\ntouch "%s/DECOY_RAN"\n' "$SANDBOX"
        _emit_ok_body "decoy"; } > "$r/plugins/soleur/scripts/render-c4-model.sh"
      chmod +x "$r/plugins/soleur/scripts/render-c4-model.sh" ;;
    *) echo "[FATAL] unknown repo shape $shape" >&2; exit 2 ;;
  esac
  _git "$r" init -q -b main
  # Identity goes in the fixture repo's LOCAL config, not only on `_git`'s `-c`. The
  # `-c` form covers the harness's own commits and nothing else: the SUT runs its own
  # `git merge` inside this repo, which reads config, so it only had an identity where
  # the developer's GLOBAL config supplied one. Every row passed locally and 14 failed
  # on a CI runner with "Committer identity unknown" (#8384, run 35588718251).
  # Reproduce: HOME=$(mktemp -d) GIT_CONFIG_GLOBAL=/dev/null bash <this file>.
  git -C "$r" config user.email t@t
  git -C "$r" config user.name t
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

P_OK="$(mkplugin ok ok)"
P_FAIL="$(mkplugin fail fail)"
P_NOOP="$(mkplugin noop noop)"
P_XMOD="$(mkplugin xmod extra-mod)"
P_XNEW="$(mkplugin xnew extra-new)"
P_LONELY="$(mkplugin lonely none)"
P_NOID="$(mkplugin noid ok not-soleur)"
P_ALT="$(mkplugin alt ok-alt)"
for _p in "$P_ALT" "$P_OK" "$P_FAIL" "$P_NOOP" "$P_XMOD" "$P_XNEW" "$P_LONELY" "$P_NOID"; do
  [[ -f "$_p/scripts/resolve-regenerable-conflicts.sh" ]] || { echo "[FATAL] sandbox plugin not built: $_p" >&2; exit 2; }
done

# run_at <plugin-root> <repo> <base-ref> [resolvable-tsv] — CLAUDE_PLUGIN_ROOT is UNSET for
# every row that does not set it on purpose, so a developer's ambient value cannot rescue a
# broken sibling lookup and turn a RED row green.
run_at() {
  local pr="$1" r="$2" base="$3" tsv="${4:-}"
  local out rc=0
  if [[ -n "$tsv" ]]; then
    out="$(cd "$r" && env -u CLAUDE_PLUGIN_ROOT bash "$pr/scripts/resolve-regenerable-conflicts.sh" --test-resolvable "$tsv" "$base" 2>&1)" || rc=$?
  else
    out="$(cd "$r" && env -u CLAUDE_PLUGIN_ROOT bash "$pr/scripts/resolve-regenerable-conflicts.sh" "$base" 2>&1)" || rc=$?
  fi
  printf '%s\n%s' "$out" "$rc"
}
run_sut() {  # <repo> <base-ref> [resolvable-tsv]
  # The seam is ARGV, not the environment (#8384): an inherited env var that reaches an
  # unattended `git commit` is a command-execution channel, and was demonstrated as one.
  run_at "$P_OK" "$@"
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
r="$(mkrepo row2)"
fp_before="$(tree_fp "$r")"
res="$(run_at "$P_FAIL" "$r" main)"
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
  # argv vector, TAB-separated -- the SUT splits on TAB and execs directly (no eval).
  local rr="$P_OK/scripts/render-c4-model.sh"
  printf '%s\tbash\t%s\t--root\t%s\n%s\tbash\t%s\t--root\t%s\n' \
    "$MODEL" "$rr" "$r" "$second" "$rr" "$r" > "${r}.override.tsv"
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
    res="$(run_sut "$r" main "${r}.override.tsv")"
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
    fail "$name -> the tree CHANGED; fail-closed means nothing is touched: $(sut_out "$res")"
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
_r3_out="$(sut_out "$(run_sut "$r3" main "${r3}.override.tsv")")"
if grep -qE 'did not produce|conflict markers' <<<"$_r3_out"; then
  pass "row 3: refuses a path the regen did not write"
else
  fail "row 3: the un-regenerated path was not refused: $_r3_out"
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

# ── THE RESOLVABLE SET IS RATCHETED, like CACHE_PATHS on the cache side ────────────────────
# The SUT's header says adding a second member "is an edit HERE plus an ADR-235 amendment, so
# the cache-vs-product question gets asked each time." This pins the member SET (#8384 review).
#
# ANCHORED ON A NAMED MARKER, not on the assignment's shape. This used to take `tail -1` of
# every `RESOLVABLE_PATHS=(...)` line, which is a claim about ORDER: a second default written
# above the first was invisible, and one written in any other syntax was too. The marker is a
# deliberate token the SUT carries on exactly one line; the row requires exactly one carrier.
_set_lines="$(grep -E '^[^#]*RESOLVABLE_PATHS=\(.*\)[[:space:]]+# RESOLVABLE-SET: default[[:space:]]*$' "$SUT")"
_set_n="$(grep -c 'RESOLVABLE-SET: default' "$SUT")"
_default_paths="$(sed -n 's/^[^#]*RESOLVABLE_PATHS=(\(.*\))[[:space:]]*#.*$/\1/p' <<<"$_set_lines")"
CASES_RUN=$((CASES_RUN + 1))
if [[ "$_set_n" -eq 1 && "$_default_paths" == '"knowledge-base/engineering/architecture/diagrams/model.likec4.json"' ]]; then
  pass "resolvable set: exactly one member, model.likec4.json (ratcheted; grow it deliberately + amend ADR-235)"
else
  fail "resolvable set changed: [$_default_paths] across $_set_n marker line(s) — an ADR-235 amendment is required alongside this edit"
fi

# ── EVERY ARGV THE RESOLVER CAN EXECUTE HAS A NAMED SOURCE (Guard 1, m6) ─────────────────────
# The property #8542's follow-up exists for: nothing the resolver executes comes from the repo
# being merged. Each site that PRODUCES an argv carries a trailing `# ARGV-SOURCE: <name>`
# marker, and the set of names is pinned. `plugin` is the production arm (a renderer beside
# the resolver, or under CLAUDE_PLUGIN_ROOT); `test-seam` is the argv-only --test-resolvable
# arm. Adding a third source -- or a second `plugin` site -- is a deliberate edit to this row,
# which names ADR-235 so the review asks where the new command comes from.
_argv_sources="$(grep -E '^[[:space:]]*[^#[:space:]].*[[:space:]]# ARGV-SOURCE: [a-z-]+[[:space:]]*$' "$SUT" \
  | sed -E 's/.*# ARGV-SOURCE: ([a-z-]+)[[:space:]]*$/\1/' | LC_ALL=C sort | tr '\n' ' ')"
_argv_marker_total="$(grep -c 'ARGV-SOURCE: ' "$SUT")"
CASES_RUN=$((CASES_RUN + 1))
if [[ "$_argv_sources" == "plugin test-seam " && "$_argv_marker_total" -eq 2 ]]; then
  pass "argv sources: exactly {plugin, test-seam}, one site each (ADR-235 amendment)"
else
  fail "argv sources changed: [$_argv_sources] over $_argv_marker_total marker(s) — a new command source needs an ADR-235 amendment"
fi

# ── The resolver must NEVER push. ──────────────────────────────────────────────────────────
CASES_RUN=$((CASES_RUN + 1))
if grep -v '^[[:space:]]*#' "$SUT" | grep -qE '(^|[^-[:alnum:]])git[[:space:]]+push'; then
  fail "the resolver contains a 'git push' — callers own the push and its rejection handling"
else
  pass "the resolver never pushes (callers own the push)"
fi

# ── tree_fp POSITIVE CONTROL ───────────────────────────────────────────────────────────────
# tree_fp owns 9 "the tree is byte-identical to entry" verdicts and was never driven with a
# tree that MUST differ: `tree_fp() { echo CONSTANT; }` left this suite 39/39 GREEN (#8384
# review). The instrument self-test covers pass()/fail(); it is blind to an ORACLE that has
# stopped observing. These two rows are that control.
_fpctl="$(mkrepo fpcontrol)"
_fp0="$(tree_fp "$_fpctl")"
printf 'dirty\n' >> "$_fpctl/$SRC"
CASES_RUN=$((CASES_RUN + 1))
[[ "$(tree_fp "$_fpctl")" != "$_fp0" ]] \
  && pass "tree_fp control: a modified tracked file changes the fingerprint" \
  || fail "tree_fp is not observing — every 'tree untouched' verdict in this suite is vacuous"
_git "$_fpctl" checkout -q -- "$SRC"
CASES_RUN=$((CASES_RUN + 1))
[[ "$(tree_fp "$_fpctl")" == "$_fp0" ]] \
  && pass "tree_fp control: reverting restores the fingerprint" \
  || fail "tree_fp is not stable across a revert — it cannot distinguish touched from untouched"

# ── THE SEAM IS NOT REACHABLE FROM THE ENVIRONMENT ─────────────────────────────────────────
# Regression guard for the demonstrated P1 (#8384): RESOLVABLE_OVERRIDE was an inherited env
# var whose TSV command column reached `eval` inside a script that commits unattended and
# whose callers then push. Setting it must now do NOTHING.
_envr="$(mkrepo envseam)"
# MUST map the CONFLICTED path ($MODEL). $SRC text-merges cleanly, so it is never in the
# conflicted set and the payload could never fire -- a fixture that cannot contain the thing
# it looks for. (Caught by mutation M2: this row passed against an env-reachable seam.)
printf '%s\ttouch\t%s/PWNED\n' "$MODEL" "$_envr" > "${_envr}.evil.tsv"
_env_res="$(cd "$_envr" && RESOLVABLE_OVERRIDE="${_envr}.evil.tsv" bash "$SUT" main 2>&1; printf '|rc=%s' "$?")"
CASES_RUN=$((CASES_RUN + 1))
if [[ -e "$_envr/PWNED" ]]; then
  fail "RESOLVABLE_OVERRIDE still directs the resolver from the environment: $_env_res"
else
  pass "the resolvable set is not reachable from the environment (argv-only seam)"
fi

# ── A NO-OP REGEN CANNOT COMMIT THE OURS-SIDE ARTIFACT ─────────────────────────────────────
# git writes NO conflict markers for a path it treats as BINARY -- it marks it UU and leaves
# ours-content in place -- so the marker grep alone let a regen that never wrote commit the
# ours artifact at rc=0: side-picking dressed as regeneration. The SUT now deletes the path
# before regenerating, so a non-writing command is caught as "did not produce".
_noop="$(mkrepo noopregen)"
_noop_before="$(tree_fp "$_noop")"
_noop_res="$(run_at "$P_NOOP" "$_noop" main)"
CASES_RUN=$((CASES_RUN + 1))
if [[ "$(sut_rc "$_noop_res")" != "0" ]] && grep -q 'did not produce' <<<"$(sut_out "$_noop_res")"; then
  pass "a regen that writes nothing is refused, not committed as the ours-side artifact"
else
  fail "a no-op regen was accepted (ours-side side-pick at rc=0): $(sut_out "$_noop_res")"
fi
CASES_RUN=$((CASES_RUN + 1))
[[ "$(tree_fp "$_noop")" == "$_noop_before" ]] \
  && pass "the refused no-op regen left the tree byte-identical" \
  || fail "the no-op refusal left residue behind"

# ══ ADR-235 AMENDMENT (#8542 follow-up): THE ARM IS PLUGIN-OWNED ═════════════════════════════
echo ""
echo "--- plugin-owned arm: self-hosted, wrapper, decoy, CLAUDE_PLUGIN_ROOT ---"

# AC1/AC2 + m4/m5 — the happy path above already runs in a BARE repo (no scripts/, no
# plugins/), so a repo-relative argv or a deleted arm reds it. These rows pin what it wrote.
r="$(mkrepo selfhosted)"
res="$(run_sut "$r" main)"
CASES_RUN=$((CASES_RUN + 1))
if [[ "$(sut_rc "$res")" == "0" && "$(cat "$r/$MODEL")" == *'"by":"plugin"'* ]]; then
  pass "AC1: a self-hosted repo (no repo-local renderer) merges; the artifact is the plugin renderer's"
else
  fail "AC1: rc=$(sut_rc "$res") artifact=$(cat "$r/$MODEL") — $(sut_out "$res")"
fi
CASES_RUN=$((CASES_RUN + 1))
[[ -z "$(_git "$r" status --porcelain)" ]] && pass "AC2: git status --porcelain is empty after exit 0" \
  || fail "AC2: tree dirty after exit 0: $(_git "$r" status --porcelain)"
CASES_RUN=$((CASES_RUN + 1))
if grep -qE "^SOLEUR_REGEN_ON_CONFLICT paths=[^ ]+ arm=plugin root=${P_OK} rc=0$" <<<"$(sut_out "$res")"; then
  pass "the success marker names arm=plugin and the plugin root that rendered"
else
  fail "the success marker lacks arm=/root=: $(sut_out "$res")"
fi
CASES_RUN=$((CASES_RUN + 1))
grep -q '\[regen-on-conflict\] regenerating ' <<<"$(sut_out "$res")" \
  && pass "a progress line precedes the (minutes-long) render" \
  || fail "no progress line before the render: $(sut_out "$res")"

# Harness row (b) — MUST-PASS, non-canonical: this repo's shape, with a wrapper at the old path.
r="$(mkrepo withwrapper wrapper)"
res="$(run_sut "$r" main)"
CASES_RUN=$((CASES_RUN + 1))
if [[ "$(sut_rc "$res")" == "0" && "$(cat "$r/$MODEL")" == *'"by":"plugin"'* ]]; then
  pass "a repo carrying scripts/regenerate-c4-model.sh still renders through the plugin (the wrapper is not an arm)"
else
  fail "the repo wrapper was used or the merge failed: rc=$(sut_rc "$res") artifact=$(cat "$r/$MODEL")"
fi

# AC4 + m1 — a merged tree ships its OWN plugins/soleur/scripts/render-c4-model.sh behind a
# genuine-looking plugin.json. Loaded from the plugin root, the resolver runs its sibling. The
# name check passes the decoy (ADR-179 A11) -- what excludes it is WHERE the root comes from.
rm -f "$SANDBOX/DECOY_RAN"
r="$(mkrepo decoy decoy)"
res="$(run_sut "$r" main)"
CASES_RUN=$((CASES_RUN + 1))
if [[ "$(sut_rc "$res")" == "0" && "$(cat "$r/$MODEL")" == *'"by":"plugin"'* && ! -e "$SANDBOX/DECOY_RAN" ]]; then
  pass "AC4: a decoy renderer inside the merged tree is never executed"
else
  fail "AC4: the decoy ran or the merge failed: rc=$(sut_rc "$res") artifact=$(cat "$r/$MODEL") decoy_ran=$([[ -e "$SANDBOX/DECOY_RAN" ]] && echo yes || echo no)"
fi

# m1 — the plugin dir must be absolutized BEFORE the resolver cd's to the repo root. Invoked by
# a RELATIVE path from a subdirectory, a dirname resolved after the cd points somewhere else.
r="$(mkrepo relative)"
_rel="$(realpath --relative-to="$r/knowledge-base" "$P_OK/scripts/resolve-regenerable-conflicts.sh")"
_rel_rc=0
_rel_out="$(cd "$r/knowledge-base" && env -u CLAUDE_PLUGIN_ROOT bash "$_rel" main 2>&1)" || _rel_rc=$?
CASES_RUN=$((CASES_RUN + 1))
if [[ "$_rel_rc" -eq 0 && "$(cat "$r/$MODEL")" == *'"by":"plugin"'* ]]; then
  pass "m1: a relative invocation from a subdirectory still finds the sibling renderer"
else
  fail "m1: relative invocation ($_rel) rc=$_rel_rc — $_rel_out"
fi

# CLAUDE_PLUGIN_ROOT is the FALLBACK, used only when no renderer sits beside the resolver.
r="$(mkrepo cprfallback)"
_c_rc=0
_c_out="$(cd "$r" && CLAUDE_PLUGIN_ROOT="$P_OK" bash "$P_LONELY/scripts/resolve-regenerable-conflicts.sh" main 2>&1)" || _c_rc=$?
CASES_RUN=$((CASES_RUN + 1))
if [[ "$_c_rc" -eq 0 && "$_c_out" == *"arm=plugin root=${P_OK} rc=0"* ]]; then
  pass "no sibling renderer: CLAUDE_PLUGIN_ROOT supplies the plugin root"
else
  fail "CLAUDE_PLUGIN_ROOT fallback: rc=$_c_rc — $_c_out"
fi

# ORDER IS THE CONTROL: with BOTH sources present, the sibling wins. An inherited variable is
# the weaker provenance (ADR-179), so a valid-looking CLAUDE_PLUGIN_ROOT must not displace the
# renderer that shipped with this resolver.
r="$(mkrepo cprorder)"
_o_rc=0
_o_out="$(cd "$r" && CLAUDE_PLUGIN_ROOT="$P_ALT" bash "$P_OK/scripts/resolve-regenerable-conflicts.sh" main 2>&1)" || _o_rc=$?
CASES_RUN=$((CASES_RUN + 1))
if [[ "$_o_rc" -eq 0 && "$(cat "$r/$MODEL")" == *'"by":"plugin"'* && "$_o_out" == *"root=${P_OK} rc=0"* ]]; then
  pass "a sibling renderer wins over CLAUDE_PLUGIN_ROOT when both resolve"
else
  fail "CLAUDE_PLUGIN_ROOT displaced the sibling: rc=$_o_rc artifact=$(cat "$r/$MODEL") — $_o_out"
fi

# Neither source: refuse BEFORE touching anything, and say what to run instead.
r="$(mkrepo noroot)"
fp_before="$(tree_fp "$r")"
res="$(run_at "$P_LONELY" "$r" main)"
CASES_RUN=$((CASES_RUN + 1))
[[ "$(sut_rc "$res")" != "0" && "$(tree_fp "$r")" == "$fp_before" ]] \
  && pass "no plugin root at all: refused, tree byte-identical" \
  || fail "no plugin root: rc=$(sut_rc "$res") or the tree changed"
CASES_RUN=$((CASES_RUN + 1))
if grep -q 'CLAUDE_PLUGIN_ROOT' <<<"$(sut_out "$res")" && grep -q 'render-c4-model.sh' <<<"$(sut_out "$res")"; then
  pass "the no-root refusal names the missing root and the renderer to run by hand"
else
  fail "the no-root refusal is not actionable: $(sut_out "$res")"
fi

# The identity check applies to WHICHEVER root is used -- the sibling's included.
r="$(mkrepo noid)"
fp_before="$(tree_fp "$r")"
res="$(run_at "$P_NOID" "$r" main)"
CASES_RUN=$((CASES_RUN + 1))
if [[ "$(sut_rc "$res")" != "0" && "$(tree_fp "$r")" == "$fp_before" ]] && grep -q 'soleur' <<<"$(sut_out "$res")"; then
  pass "a plugin root whose plugin.json does not name soleur is refused (sanity check, not a boundary)"
else
  fail "identity check: rc=$(sut_rc "$res") — $(sut_out "$res")"
fi
r="$(mkrepo noidenv)"
_n_rc=0
_n_out="$(cd "$r" && CLAUDE_PLUGIN_ROOT="$P_NOID" bash "$P_LONELY/scripts/resolve-regenerable-conflicts.sh" main 2>&1)" || _n_rc=$?
CASES_RUN=$((CASES_RUN + 1))
[[ "$_n_rc" -ne 0 && "$_n_out" == *soleur* ]] \
  && pass "the identity check also gates the CLAUDE_PLUGIN_ROOT fallback" \
  || fail "the env fallback skipped the identity check: rc=$_n_rc — $_n_out"

# ── AC3 / m2 — an UNTRACKED .c4 in the diagrams directory ──────────────────────────────────
# likec4 compiles every .c4 it finds, so an ignored, machine-local generated-components.c4
# would be compiled into a committed model the merge never saw (P5). IGNORED on purpose: an
# untracked non-ignored file already trips the clean-tree precondition, so it could not tell
# this guard's absence from its presence.
for _nest in "" "sub/"; do
  _key="untracked$(tr -cd 'a-z' <<<"$_nest")"
  r="$(mkrepo "$_key")"; assert_fixture_dir "$r"
  mkdir -p "$r/knowledge-base/engineering/architecture/diagrams/$_nest"
  printf 'model { extra = component %s }\n' "'Extra'" \
    > "$r/knowledge-base/engineering/architecture/diagrams/${_nest}generated-components.c4"
  printf 'generated-components.c4\n' >> "$r/.git/info/exclude"
  fp_before="$(tree_fp "$r")"
  res="$(run_sut "$r" main)"
  CASES_RUN=$((CASES_RUN + 1))
  [[ "$(sut_rc "$res")" != "0" && "$(tree_fp "$r")" == "$fp_before" ]] \
    && pass "AC3 (${_nest:-top}): an ignored .c4 source refuses the regen, tree byte-identical" \
    || fail "AC3 (${_nest:-top}): rc=$(sut_rc "$res") or the tree changed — $(sut_out "$res")"
  CASES_RUN=$((CASES_RUN + 1))
  grep -q "${_nest}generated-components.c4" <<<"$(sut_out "$res")" \
    && pass "AC3 (${_nest:-top}): the refusal names the untracked file" \
    || fail "AC3 (${_nest:-top}): the refusal does not name the file: $(sut_out "$res")"
done

# ── D4 / m3 — the regen must write EXACTLY the conflicted path (P3) ────────────────────────
# `git add` stages only that path and the residual check reads only unmerged paths, so a
# renderer that also touched another file would leave it in the tree -- or, staged by a later
# change, in the merge commit. Both a modified TRACKED file and a NEW file are refused, and
# the unwind removes them: fail-closed means byte-identical, not "the merge was aborted".
for _spec in "xmod|$P_XMOD|README.md" "xnew|$P_XNEW|stray.txt"; do
  IFS='|' read -r _k _pr _stray <<<"$_spec"
  r="$(mkrepo "stray$_k")"
  fp_before="$(tree_fp "$r")"
  res="$(run_at "$_pr" "$r" main)"
  CASES_RUN=$((CASES_RUN + 1))
  [[ "$(sut_rc "$res")" != "0" ]] && pass "P3 ($_stray): a renderer that writes a second file is refused" \
    || fail "P3 ($_stray): exited 0 with a stray write — $(sut_out "$res")"
  CASES_RUN=$((CASES_RUN + 1))
  [[ "$(tree_fp "$r")" == "$fp_before" ]] && pass "P3 ($_stray): the stray write was unwound, tree byte-identical" \
    || fail "P3 ($_stray): the tree changed: $(_git "$r" status --porcelain | tr '\n' ' ')"
  CASES_RUN=$((CASES_RUN + 1))
  grep -q "$_stray" <<<"$(sut_out "$res")" && pass "P3 ($_stray): the refusal names the stray path" \
    || fail "P3 ($_stray): the refusal does not name $_stray: $(sut_out "$res")"
done

# ── AC6 — the renderer's diagnostic reaches the operator ───────────────────────────────────
# The arm's output used to go to /dev/null, so `bail` could name only the argv. The renderer's
# diagnostic is its one observability surface; it has to survive into the refusal.
r="$(mkrepo diag)"
res="$(run_at "$P_FAIL" "$r" main)"
CASES_RUN=$((CASES_RUN + 1))
grep -q 'Line 3: boom' <<<"$(sut_out "$res")" \
  && pass "AC6: the bail message carries the renderer's diagnostic text, not only the argv" \
  || fail "AC6: the diagnostic was swallowed: $(sut_out "$res")"

echo ""
echo "cases_run=$CASES_RUN passes=$passes fails=$fails ledger=${#FAILED[@]}"

_min_cases=70
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
