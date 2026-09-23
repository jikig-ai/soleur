#!/usr/bin/env bash
# Guard 1 (#8377, ADR-235) — resolve-regenerable-conflicts.sh fails CLOSED.
#
# ── THE PROPERTY ────────────────────────────────────────────────────────────────────────────
# The resolver commits a merge ONLY when every conflicted path is a CONTENT conflict on a
# resolvable path, the renderer rendered each one from the merged tree's tracked sources, and
# nothing else moved. On any other input the tree is byte-identical to entry and nothing is
# committed. Every non-happy row asserts BOTH a non-zero exit AND an unchanged tree fingerprint.
#
# ── THE ARM CONTRACT (ADR-235 amendment 2026-09-23) ─────────────────────────────────────────
# An arm is an argv PREFIX; the resolver appends `--root <staging> --out <file>`. <staging>
# holds ONLY the tracked LikeC4 sources copied out of the merged tree's objects; the arm writes
# its artifact to <file>, never to the worktree. The stubs below refuse any other argv shape.
#
# ── WHY THE SUT RUNS FROM A SANDBOX PLUGIN COPY ─────────────────────────────────────────────
# The production arm runs render-c4-model.sh from BESIDE THE RESOLVER. A stub is injected the
# way a real install is laid out: a copy of the SUT in <root>/scripts/ with the stub as its
# sibling and a <root>/.claude-plugin/plugin.json. Copies are taken from $SUT at run time, so a
# mutation battery that edits $SUT is measured by every row; the ratchet rows read $SUT itself.
#
# tree_fp = HEAD + porcelain status (incl. untracked) + every index entry + MERGE_HEAD presence.
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
SANDBOX="$(cd "$SANDBOX" && pwd -P)"
trap 'rm -rf "$SANDBOX"' EXIT
# The resolver's staging dir lives under XDG_CACHE_HOME; keep it inside the sandbox.
export XDG_CACHE_HOME="$SANDBOX/xdg-cache"

DIAG="knowledge-base/engineering/architecture/diagrams"
MODEL="$DIAG/model.likec4.json"
SRC="$DIAG/model.c4"
SECOND="$DIAG/second.json"

_git() { git -C "$1" -c user.email=t@t -c user.name=t "${@:2}"; }

tree_fp() {
  local r="$1"
  {
    _git "$r" rev-parse HEAD 2>/dev/null || echo "NOHEAD"
    _git "$r" status --porcelain --untracked-files=all 2>/dev/null
    _git "$r" ls-files -s 2>/dev/null
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

# _write_renderer <file> <mode> — a stub with the real renderer's CONTRACT as the resolver
# calls it: exactly `--root <existing dir> --out <path>` (exit 64 otherwise). The `ok` output
# DERIVES from the staged model.c4 and names its author, so the committed artifact shows WHICH
# tree it saw and WHICH renderer wrote it.
_write_renderer() {
  local f="$1" mode="$2"; assert_fixture_dir "$f"
  {
    printf '#!/usr/bin/env bash\nset -euo pipefail\n'
    printf '[[ "$#" -eq 4 && "$1" == "--root" && -d "$2" && "$3" == "--out" ]] || { echo "stub renderer: bad argv: $*" >&2; exit 64; }\n'
    printf 'R="$2"; O="$4"\n'
    case "$mode" in
      ok) _emit_ok_body "plugin" ;;
      ok-alt) _emit_ok_body "alt-plugin" ;;
      second) printf 'echo "{\\"second\\":\\"regenerated\\"}" | tee "$O" >/dev/null\n' ;;
      fail) printf 'echo "Invalid model.c4"; echo "    Line 3: boom (stub diagnostic)"; echo "ERROR: stub renderer refused" >&2; exit 9\n' ;;
      noop) printf 'exit 0\n' ;;
      markers) printf 'printf "%%s\\n" "<<<<<<< ours" "x" "=======" "y" ">>>>>>> theirs" | tee "$O" >/dev/null\n' ;;
      slow) printf 'touch "%s/slow.started"; sleep 5\n' "$SANDBOX"; _emit_ok_body "plugin" ;;
      listroot) printf '(cd "$R" && find . -mindepth 1 -print) | tee "%s/listroot.txt" >/dev/null\n' "$SANDBOX"; _emit_ok_body "plugin" ;;
      *) echo "[FATAL] unknown renderer mode $mode" >&2; exit 2 ;;
    esac
    true
  } > "$f"
  chmod +x "$f"
}
_emit_ok_body() {  # <author>
  printf 'f="$R/%s"\n' "$SRC"
  printf 'printf %s "$(head -1 "$f")" "$(tail -1 "$f")" | tee "$O" >/dev/null\n' "'{\"from\":\"%s|%s\",\"by\":\"$1\"}\\n'"
}

# mkrepo <name> [bare|wrapper|decoy] — two branches whose .c4 SOURCE text-merges cleanly while
# the compiled single-line JSON conflicts (the real shape).
#   bare     a self-hosted repo: no scripts/, no plugins/ (AC1).
#   wrapper  a committed scripts/regenerate-c4-model.sh: not an arm (must never run).
#   decoy    a merged tree shipping its own plugins/soleur renderer + genuine-looking plugin.json.
# Extra files go in the BASE commit, so they are neither untracked nor a conflict of their own.
mkrepo() {
  local r="$SANDBOX/$1" shape="${2:-bare}"; assert_fixture_dir "$r"
  mkdir -p "$r/$DIAG"
  printf 'first\nx\nx\nx\nx\nx\nx\nx\nx\nlast\n' > "$r/$SRC"
  printf '{"v":"base"}\n' > "$r/$MODEL"
  printf '{"v":"base2"}\n' > "$r/$SECOND"
  printf 'readme base\n' > "$r/README.md"
  case "$shape" in
    bare) : ;;
    wrapper)
      mkdir -p "$r/scripts"
      printf '#!/usr/bin/env bash\ntouch "%s/WRAPPER_RAN"\n' "$SANDBOX" > "$r/scripts/regenerate-c4-model.sh"
      chmod +x "$r/scripts/regenerate-c4-model.sh" ;;
    decoy)
      mkdir -p "$r/plugins/soleur/scripts" "$r/plugins/soleur/.claude-plugin"
      printf '{\n  "name": "soleur"\n}\n' > "$r/plugins/soleur/.claude-plugin/plugin.json"
      printf '#!/usr/bin/env bash\ntouch "%s/DECOY_RAN"\n' "$SANDBOX" > "$r/plugins/soleur/scripts/render-c4-model.sh"
      chmod +x "$r/plugins/soleur/scripts/render-c4-model.sh" ;;
    *) echo "[FATAL] unknown repo shape $shape" >&2; exit 2 ;;
  esac
  _git "$r" init -q -b main
  # Identity in LOCAL config: the SUT runs its own merge and commit, which read config
  # (#8384: 14 rows failed on a CI runner without a global identity).
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
# on_main <repo> <cmd…> — run <cmd…> <repo> on the base side (main), commit, return to feature.
on_main() {
  local r="$1"; shift
  _git "$r" checkout -q main; "$@" "$r"; _git "$r" add -A >/dev/null; _git "$r" commit -q -m "main extra"
  _git "$r" checkout -q feature
}

P_OK="$(mkplugin ok ok)"
P_FAIL="$(mkplugin fail fail)"
P_NOOP="$(mkplugin noop noop)"
P_MARK="$(mkplugin markers markers)"
P_SLOW="$(mkplugin slow slow)"
P_LIST="$(mkplugin listroot listroot)"
P_SECOND="$(mkplugin second second)"
P_LONELY="$(mkplugin lonely none)"
P_NOID="$(mkplugin noid ok not-soleur)"
P_ALT="$(mkplugin alt ok-alt)"
for _p in "$P_OK" "$P_FAIL" "$P_NOOP" "$P_MARK" "$P_SLOW" "$P_LIST" "$P_SECOND" "$P_LONELY" "$P_NOID" "$P_ALT"; do
  [[ -f "$_p/scripts/resolve-regenerable-conflicts.sh" ]] || { echo "[FATAL] sandbox plugin not built: $_p" >&2; exit 2; }
done

# run_at <plugin-root> <repo> <base-ref> [resolvable-tsv] — CLAUDE_PLUGIN_ROOT is UNSET unless a
# row sets it on purpose, so an ambient value cannot rescue a broken sibling lookup.
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
run_sut() { run_at "$P_OK" "$@"; }
sut_rc()  { tail -n1 <<<"$1"; }
sut_out() { sed '$d' <<<"$1"; }
# refused <name> <res> <fp_before> <repo> [expect-substring] — the fail-closed triple.
refused() {
  local name="$1" res="$2" fpb="$3" r="$4" want="${5:-}"
  CASES_RUN=$((CASES_RUN + 1))
  [[ "$(sut_rc "$res")" != "0" ]] && pass "$name -> non-zero" \
    || fail "$name -> exited 0; the resolver committed something it should have refused"
  CASES_RUN=$((CASES_RUN + 1))
  [[ "$(tree_fp "$r")" == "$fpb" ]] && pass "$name -> tree byte-identical to entry" \
    || fail "$name -> the tree CHANGED (rc=$(sut_rc "$res")): $(_git "$r" status --porcelain --untracked-files=all | tr '\n' ' ') — $(sut_out "$res")"
  if [[ -n "$want" ]]; then
    CASES_RUN=$((CASES_RUN + 1))
    grep -qF -- "$want" <<<"$(sut_out "$res")" && pass "$name -> says '$want'" \
      || fail "$name -> did not say '$want': $(sut_out "$res")"
  fi
}

echo "=== resolve-regenerable-conflicts (Guard 1) ==="

# ── HAPPY PATH (AC1/AC2) — a bare self-hosted repo, the plugin's own renderer ───────────────
echo ""
echo "--- happy path: a lone resolvable content conflict is merged and committed ---"
r="$(mkrepo happy)"
before_head="$(_git "$r" rev-parse HEAD)"
res="$(run_sut "$r" main)"
CASES_RUN=$((CASES_RUN + 1))
[[ "$(sut_rc "$res")" == "0" ]] && pass "happy: exit 0" || fail "happy: exit $(sut_rc "$res") — $(sut_out "$res")"
CASES_RUN=$((CASES_RUN + 1))
if [[ "$(_git "$r" rev-parse HEAD^1 2>/dev/null)" == "$before_head" && "$(_git "$r" rev-parse HEAD^2 2>/dev/null)" == "$(_git "$r" rev-parse main)" ]]; then
  pass "happy: a two-parent merge commit (HEAD, main) exists"
else
  fail "happy: no merge commit with parents (HEAD, main)"
fi
CASES_RUN=$((CASES_RUN + 1))
[[ -z "$(_git "$r" status --porcelain --untracked-files=all)" ]] && pass "happy (AC2): the tree is clean after the commit" \
  || fail "happy: tree dirty after commit: $(_git "$r" status --porcelain --untracked-files=all)"
CASES_RUN=$((CASES_RUN + 1))
committed="$(_git "$r" show HEAD:"$MODEL")"
if [[ "$committed" == *'first-MAIN|last-FEATURE'*'"by":"plugin"'* ]]; then
  pass "happy (AC1): the artifact was rendered by the PLUGIN renderer from the MERGED sources"
else
  fail "happy: unexpected artifact content: $committed"
fi
CASES_RUN=$((CASES_RUN + 1))
if grep -qxF "SOLEUR_REGEN_ON_CONFLICT paths=$MODEL arm=plugin root_src=sibling rc=0" <<<"$(sut_out "$res")"; then
  pass "happy: the success marker names the path, arm=plugin and root_src=sibling (no filesystem path)"
else
  fail "happy: success marker missing or reshaped: $(sut_out "$res")"
fi
CASES_RUN=$((CASES_RUN + 1))
grep -q '\[regen-on-conflict\] regenerating ' <<<"$(sut_out "$res")" \
  && pass "happy: a progress line precedes the (minutes-long) render" \
  || fail "happy: no progress line before the render"
CASES_RUN=$((CASES_RUN + 1))
[[ -z "$(find "$XDG_CACHE_HOME/soleur" -mindepth 1 -maxdepth 1 2>/dev/null)" ]] \
  && pass "happy: the private staging dir was removed" \
  || fail "happy: staging left behind: $(ls "$XDG_CACHE_HOME/soleur")"

# P1 (must-PASS): the base ref given as a raw SHA.
r="$(mkrepo p1)"
res="$(run_sut "$r" "$(_git "$r" rev-parse main)")"
CASES_RUN=$((CASES_RUN + 1))
[[ "$(sut_rc "$res")" == "0" ]] && pass "P1: a SHA base ref exits 0 and merges" \
  || fail "P1: a SHA base ref exited $(sut_rc "$res") — $(sut_out "$res")"

# Two resolvable members, each regenerated by its own arm (arm-agnostic success).
_main_second() { printf '{"v":"main2"}\n' > "$1/$SECOND"; }
r="$(mkrepo twomembers)"
on_main "$r" _main_second
printf '{"v":"feature2"}\n' > "$r/$SECOND"; _git "$r" commit -q -am f2
printf '%s\tbash\t%s\n%s\tbash\t%s\n' "$MODEL" "$P_OK/scripts/render-c4-model.sh" \
  "$SECOND" "$P_SECOND/scripts/render-c4-model.sh" > "$r.tsv"
res="$(run_sut "$r" main "$r.tsv")"
CASES_RUN=$((CASES_RUN + 1))
if [[ "$(sut_rc "$res")" == "0" && "$(_git "$r" show HEAD:"$MODEL")" == *'"by":"plugin"'* \
      && "$(_git "$r" show HEAD:"$SECOND")" == *'"second":"regenerated"'* ]]; then
  pass "two members: each path is written by ITS OWN arm and both are committed"
else
  fail "two members: rc=$(sut_rc "$res") — $(sut_out "$res")"
fi

# ── FAILURES OF THE RENDER: all happen before the worktree is touched ──────────────────────
echo ""
echo "--- a failing / empty / marker-laden render refuses with the tree untouched ---"
r="$(mkrepo row2)"; fpb="$(tree_fp "$r")"; res="$(run_at "$P_FAIL" "$r" main)"
refused "row 2: the renderer fails" "$res" "$fpb" "$r" "regen failed"
CASES_RUN=$((CASES_RUN + 1))
grep -q 'Line 3: boom' <<<"$(sut_out "$res")" \
  && pass "AC6: the refusal carries the renderer's diagnostic text, not only an exit code" \
  || fail "AC6: the diagnostic was swallowed: $(sut_out "$res")"
CASES_RUN=$((CASES_RUN + 1))
grep -qx 'SOLEUR_REGEN_ON_CONFLICT rc=1 class=failed reason=render-failed' <<<"$(sut_out "$res")" \
  && pass "row 2: the stdout marker says class=failed reason=render-failed" \
  || fail "row 2: no machine-readable refusal marker: $(sut_out "$res")"

r="$(mkrepo noop)"; fpb="$(tree_fp "$r")"; res="$(run_at "$P_NOOP" "$r" main)"
refused "a renderer that writes nothing" "$res" "$fpb" "$r" "did not produce"

r="$(mkrepo markers)"; fpb="$(tree_fp "$r")"; res="$(run_at "$P_MARK" "$r" main)"
refused "a renderer that emits conflict markers" "$res" "$fpb" "$r" "still contains conflict markers"

# ── FAIL-CLOSED TABLE: inputs that are not a lone content conflict on a resolvable path ────
echo ""
echo "--- fail-closed table ---"
_main_readme() { printf 'readme MAIN\n' > "$1/README.md"; }
r="$(mkrepo row1)"; on_main "$r" _main_readme
printf 'readme FEATURE\n' > "$r/README.md"; _git "$r" commit -q -am readme
fpb="$(tree_fp "$r")"; res="$(run_sut "$r" main)"
refused "row 1: a non-resolvable path also conflicts" "$res" "$fpb" "$r" "not regenerable: README.md"

r="$(mkrepo row4)"; : > "$r.tsv"; fpb="$(tree_fp "$r")"; res="$(run_sut "$r" main "$r.tsv")"
refused "row 4: the resolvable set is empty" "$res" "$fpb" "$r" "reason=not-regenerable"

r="$(mkrepo row6)"
_git "$r" checkout -q main; _git "$r" rm -q "$MODEL"; _git "$r" commit -q -m del; _git "$r" checkout -q feature
fpb="$(tree_fp "$r")"; res="$(run_sut "$r" main)"
refused "row 6: modify/delete, not content" "$res" "$fpb" "$r" "reason=unresolvable-kind"

r="$(mkrepo row7)"
printf 'DO NOT WRITE THROUGH ME\n' > "$r/victim.txt"
rm -f "$r/$MODEL"; ln -s "../../../../victim.txt" "$r/$MODEL"; _git "$r" add -A >/dev/null; _git "$r" commit -q -m symlink
fpb="$(tree_fp "$r")"; res="$(run_sut "$r" main)"
refused "row 7: the resolvable path is a symlink on one side (distinct types)" "$res" "$fpb" "$r"
CASES_RUN=$((CASES_RUN + 1))
[[ "$(cat "$r/victim.txt")" == "DO NOT WRITE THROUGH ME" ]] && pass "row 7: the link target was not written through" \
  || fail "row 7: the link target was modified"

r="$(mkrepo row7b)"
printf 'victim\n' > "$r/$DIAG/victim.txt"; printf 'other\n' > "$r/$DIAG/other.txt"
rm -f "$r/$MODEL"; ln -s "victim.txt" "$r/$MODEL"; _git "$r" add -A >/dev/null; _git "$r" commit -q -m v
_git "$r" checkout -q main; rm -f "$r/$MODEL"; ln -s "other.txt" "$r/$MODEL"; _git "$r" add -A >/dev/null; _git "$r" commit -q -m o
_git "$r" checkout -q feature
fpb="$(tree_fp "$r")"; res="$(run_sut "$r" main)"
refused "row 7b: both sides symlink the artifact to different targets" "$res" "$fpb" "$r" "symlink"
CASES_RUN=$((CASES_RUN + 1))
[[ "$(cat "$r/$DIAG/victim.txt")" == "victim" ]] && pass "row 7b: the link target was not written through" \
  || fail "row 7b: the regen wrote through the symlink"

r="$(mkrepo row8)"; _git "$r" merge main --no-edit >/dev/null 2>&1 || true
fpb="$(tree_fp "$r")"; res="$(run_sut "$r" main)"
refused "row 8: a merge is already in progress" "$res" "$fpb" "$r" "merge is already in progress"

r="$(mkrepo dirty)"; printf 'operator work\n' > "$r/scratch.txt"; _git "$r" add scratch.txt >/dev/null
fpb="$(tree_fp "$r")"; res="$(run_sut "$r" main)"
refused "a dirty (staged) tree" "$res" "$fpb" "$r" "not clean"

r="$(mkrepo untrackedhidden)"; git -C "$r" config status.showUntrackedFiles no
printf 'operator notes\n' > "$r/NOTES.txt"
fpb="$(tree_fp "$r")"; res="$(run_sut "$r" main)"
refused "status.showUntrackedFiles=no cannot hide an untracked file" "$res" "$fpb" "$r" "not clean"
CASES_RUN=$((CASES_RUN + 1))
[[ "$(cat "$r/NOTES.txt" 2>/dev/null)" == "operator notes" ]] && pass "the operator's untracked file survives" \
  || fail "the operator's untracked file was lost"

r="$(mkrepo noconflict)"; _git "$r" checkout -q -B feature main >/dev/null 2>&1
fpb="$(tree_fp "$r")"; res="$(run_sut "$r" main)"
refused "no conflict at all" "$res" "$fpb" "$r" "reason=no-conflict"

r="$(mkrepo args)"; fpb="$(tree_fp "$r")"
res="$(run_sut "$r" "")"; refused "an empty base ref" "$res" "$fpb" "$r" "no base ref"
res="$(run_sut "$r" "no/such/ref")"; refused "an unresolvable base ref" "$res" "$fpb" "$r" "does not resolve"

# ── STAGING: only tracked regular LikeC4 sources from the merged tree reach the render ─────
echo ""
echo "--- staging: what reaches the renderer ---"
_main_junk() {
  mkdir -p "$1/$DIAG/node_modules/.bin" "$1/$DIAG/nested"
  printf '#!/bin/sh\n' > "$1/$DIAG/node_modules/.bin/likec4"
  printf 'script-shell=./evil.sh\n' > "$1/$DIAG/.npmrc"
  printf 'readme\n' > "$1/$DIAG/README.md"
  printf 'model {}\n' > "$1/$DIAG/extra.like-c4"
  printf 'model {}\n' > "$1/$DIAG/nested/café.c4"
  printf 'model {}\n' > "$1/$DIAG/nested/views.likec4"
}
r="$(mkrepo stagedroot)"; on_main "$r" _main_junk
printf 'machine-local\n' > "$r/$DIAG/local.c4"; printf 'local.c4\n' >> "$r/.git/info/exclude"
rm -f "$SANDBOX/listroot.txt"
res="$(run_at "$P_LIST" "$r" main)"
_list="$(cat "$SANDBOX/listroot.txt" 2>/dev/null)"
CASES_RUN=$((CASES_RUN + 1))
[[ "$(sut_rc "$res")" == "0" ]] && pass "staging: a tree carrying node_modules, .npmrc and odd names still merges" \
  || fail "staging: rc=$(sut_rc "$res") — $(sut_out "$res")"
for _want in "./$DIAG/model.c4" "./$DIAG/extra.like-c4" "./$DIAG/nested/café.c4" "./$DIAG/nested/views.likec4"; do
  CASES_RUN=$((CASES_RUN + 1))
  grep -qxF -- "$_want" <<<"$_list" && pass "staging: $_want is rendered" || fail "staging: $_want is missing from the render root: $_list"
done
for _never in node_modules .npmrc README.md local.c4 model.likec4.json; do
  CASES_RUN=$((CASES_RUN + 1))
  grep -qF -- "$_never" <<<"$_list" && fail "staging: $_never reached the render root" || pass "staging: $_never never reaches the render root"
done

_refuse_tree() {  # <name> <want> <setup-fn> — a base-side addition that must be refused
  local name="$1" want="$2" setup="$3" rr fpb res
  rr="$(mkrepo "$(printf '%s' "$name" | tr -cd 'a-z0-9')")"
  on_main "$rr" "$setup"
  rm -f "$SANDBOX/listroot.txt"
  fpb="$(tree_fp "$rr")"
  res="$(run_at "$P_LIST" "$rr" main)"
  refused "$name" "$res" "$fpb" "$rr" "$want"
  CASES_RUN=$((CASES_RUN + 1))
  [[ ! -e "$SANDBOX/listroot.txt" ]] && pass "$name -> refused BEFORE the renderer ran" \
    || fail "$name -> the renderer ran anyway"
}
_add_link_file() { ln -s /etc/hostname "$1/$DIAG/leak.c4"; }
_add_link_dir()  { mkdir -p "$1/outside"; printf 'model {}\n' > "$1/outside/o.c4"; ln -s ../../../../outside "$1/$DIAG/ext"; }
_add_config()    { printf 'import "node:fs"; export default {}\n' > "$1/$DIAG/likec4.config.mjs"; }
_add_rc()        { printf '{}\n' > "$1/$DIAG/.likec4rc"; }
_add_gitlink()   { mkdir -p "$1/$DIAG/sub"; git -C "$1" update-index --add --cacheinfo "160000,$(git -C "$1" rev-parse HEAD),$DIAG/sub"; }
_refuse_tree "a tracked symlinked source file" "reason=symlink-source" _add_link_file
_refuse_tree "a tracked symlinked source directory" "reason=symlink-source" _add_link_dir
_refuse_tree "a likec4 js config" "reason=likec4-config" _add_config
_refuse_tree "a likec4rc config" "reason=likec4-config" _add_rc
_refuse_tree "a submodule under the diagrams dir" "reason=gitlink-source" _add_gitlink

# A path the merge ADDS that exists here ignored would be overwritten by `git merge`.
_main_env() { printf 'from main\n' > "$1/local.env"; }
r="$(mkrepo collide)"; on_main "$r" _main_env
printf 'OPERATOR SECRET\n' > "$r/local.env"; printf 'local.env\n' >> "$r/.git/info/exclude"
fpb="$(tree_fp "$r")"; res="$(run_sut "$r" main)"
refused "the merge would overwrite an ignored local file" "$res" "$fpb" "$r" "reason=would-overwrite"
CASES_RUN=$((CASES_RUN + 1))
[[ "$(cat "$r/local.env")" == "OPERATOR SECRET" ]] && pass "the ignored local file is untouched" \
  || fail "the ignored local file was overwritten"

# ── THE RENDER WINDOW: the operator keeps working; nothing of theirs is lost or committed ──
echo ""
echo "--- the render window ---"
_slow_run() {  # <repo> <action-fn> — runs the resolver on P_SLOW, calls <action-fn> <repo> <pid> mid-render
  local rr="$1" action="$2" pid rc=0
  rm -f "$SANDBOX/slow.started"
  ( cd "$rr" && exec env -u CLAUDE_PLUGIN_ROOT bash "$P_SLOW/scripts/resolve-regenerable-conflicts.sh" main ) \
    > "$SANDBOX/slow.out" 2>&1 &
  pid=$!
  for _ in $(seq 1 100); do [[ -e "$SANDBOX/slow.started" ]] && break; sleep 0.1; done
  "$action" "$rr" "$pid"
  wait "$pid" || rc=$?
  printf '%s\n%s' "$(cat "$SANDBOX/slow.out")" "$rc"
}
_act_edit()   { printf 'mid-render edit\n' >> "$1/README.md"; printf 'new\n' > "$1/NEW.txt"; }
_act_stage()  { printf 'x\n' > "$1/staged.txt"; git -C "$1" add staged.txt; }
_act_commit() { git -C "$1" -c user.email=t@t -c user.name=t commit -q --allow-empty -m mid; }
_act_term()   { kill -TERM "$2" 2>/dev/null; }
_act_kill()   { kill -KILL "$2" 2>/dev/null; }

r="$(mkrepo editduring)"
res="$(_slow_run "$r" _act_edit)"
CASES_RUN=$((CASES_RUN + 1))
[[ "$(sut_rc "$res")" != "0" ]] && grep -q 'reason=dirty-tree' <<<"$(sut_out "$res")" \
  && pass "an edit made during the render refuses the merge" \
  || fail "edit during render: rc=$(sut_rc "$res") — $(sut_out "$res")"
CASES_RUN=$((CASES_RUN + 1))
if [[ "$(tail -1 "$r/README.md")" == "mid-render edit" && -f "$r/NEW.txt" && ! -f "$r/.git/MERGE_HEAD" \
      && "$(_git "$r" rev-parse HEAD)" == "$(_git "$r" rev-parse feature)" ]]; then
  pass "the operator's mid-render edit and new file both survive, nothing was merged"
else
  fail "operator work lost or a merge happened: $(_git "$r" status --porcelain --untracked-files=all | tr '\n' ' ')"
fi

r="$(mkrepo stageduring)"
res="$(_slow_run "$r" _act_stage)"
CASES_RUN=$((CASES_RUN + 1))
if [[ "$(sut_rc "$res")" != "0" ]] && ! _git "$r" log -1 --name-only --format= | grep -q staged.txt \
     && _git "$r" diff --cached --name-only | grep -qx staged.txt; then
  pass "a file staged during the render is never committed and stays staged"
else
  fail "a mid-render staged file was committed or lost: $(sut_out "$res")"
fi

r="$(mkrepo headmoved)"
res="$(_slow_run "$r" _act_commit)"
CASES_RUN=$((CASES_RUN + 1))
[[ "$(sut_rc "$res")" != "0" ]] && grep -q 'reason=head-moved' <<<"$(sut_out "$res")" && [[ ! -f "$r/.git/MERGE_HEAD" ]] \
  && pass "a commit made during the render refuses the (now stale) merge" \
  || fail "HEAD moved during render: rc=$(sut_rc "$res") — $(sut_out "$res")"

r="$(mkrepo sigterm)"; fpb="$(tree_fp "$r")"
_t0=$SECONDS
res="$(_slow_run "$r" _act_term)"
_dt=$((SECONDS - _t0))
refused "SIGTERM during the render" "$res" "$fpb" "$r" "reason=signal"
CASES_RUN=$((CASES_RUN + 1))
[[ "$_dt" -lt 5 ]] && pass "SIGTERM is handled at once, not after the render finishes (${_dt}s)" \
  || fail "SIGTERM waited for the render (${_dt}s)"
CASES_RUN=$((CASES_RUN + 1))
[[ -z "$(find "$XDG_CACHE_HOME/soleur" -mindepth 1 -maxdepth 1 2>/dev/null)" ]] \
  && pass "SIGTERM: the staging dir was removed" || fail "SIGTERM left staging behind"

r="$(mkrepo sigkill)"; fpb="$(tree_fp "$r")"
res="$(_slow_run "$r" _act_kill)"
CASES_RUN=$((CASES_RUN + 1))
[[ "$(tree_fp "$r")" == "$fpb" ]] && pass "SIGKILL during the render leaves the tree byte-identical (no MERGE_HEAD)" \
  || fail "SIGKILL left the tree changed: $(_git "$r" status --porcelain | tr '\n' ' ')"
sleep 5; rm -rf "${XDG_CACHE_HOME:?}/soleur"

# ── A COMMIT HOOK THAT REWRITES THE MERGE is undone and refused ─────────────────────────────
r="$(mkrepo hook)"; mkdir -p "$r/.git/hooks"
printf '#!/bin/sh\necho hooked >> README.md\ngit add README.md\n' > "$r/.git/hooks/pre-commit"; chmod +x "$r/.git/hooks/pre-commit"
fpb="$(tree_fp "$r")"; res="$(run_sut "$r" main)"
refused "a pre-commit hook that changes the merge commit" "$res" "$fpb" "$r" "reason=commit-hook-changed-tree"

# ══ PLUGIN ROOT: where the renderer comes from ═════════════════════════════════════════════
echo ""
echo "--- plugin root: self-hosted, wrapper, decoy, CLAUDE_PLUGIN_ROOT ---"
rm -f "$SANDBOX/WRAPPER_RAN" "$SANDBOX/DECOY_RAN"
r="$(mkrepo withwrapper wrapper)"; res="$(run_sut "$r" main)"
CASES_RUN=$((CASES_RUN + 1))
[[ "$(sut_rc "$res")" == "0" && ! -e "$SANDBOX/WRAPPER_RAN" && "$(_git "$r" show HEAD:"$MODEL")" == *'"by":"plugin"'* ]] \
  && pass "a repo carrying scripts/regenerate-c4-model.sh still renders through the plugin (the wrapper is not an arm)" \
  || fail "the repo wrapper ran or the merge failed: rc=$(sut_rc "$res")"

r="$(mkrepo decoy decoy)"; res="$(run_sut "$r" main)"
CASES_RUN=$((CASES_RUN + 1))
[[ "$(sut_rc "$res")" == "0" && ! -e "$SANDBOX/DECOY_RAN" && "$(_git "$r" show HEAD:"$MODEL")" == *'"by":"plugin"'* ]] \
  && pass "AC4: a decoy renderer inside the merged tree is never executed" \
  || fail "AC4: the decoy ran or the merge failed: rc=$(sut_rc "$res")"

# m1 — the plugin dir is absolutized BEFORE the cd; invoked by a RELATIVE path from a subdir.
r="$(mkrepo relative)"
_rel="$(realpath --relative-to="$r/knowledge-base" "$P_OK/scripts/resolve-regenerable-conflicts.sh")"
_rel_rc=0; _rel_out="$(cd "$r/knowledge-base" && env -u CLAUDE_PLUGIN_ROOT bash "$_rel" main 2>&1)" || _rel_rc=$?
CASES_RUN=$((CASES_RUN + 1))
[[ "$_rel_rc" -eq 0 ]] && pass "m1: a relative invocation from a subdirectory still finds the sibling renderer" \
  || fail "m1: relative invocation rc=$_rel_rc — $_rel_out"

_cpr() {  # <plugin-for-resolver> <repo> <CLAUDE_PLUGIN_ROOT value>
  local rc=0 out; out="$(cd "$2" && CLAUDE_PLUGIN_ROOT="$3" bash "$1/scripts/resolve-regenerable-conflicts.sh" main 2>&1)" || rc=$?
  printf '%s\n%s' "$out" "$rc"
}
r="$(mkrepo cprfallback)"; res="$(_cpr "$P_LONELY" "$r" "$P_OK")"
CASES_RUN=$((CASES_RUN + 1))
[[ "$(sut_rc "$res")" == "0" && "$(sut_out "$res")" == *"root_src=env rc=0"* ]] \
  && pass "no sibling renderer: an absolute CLAUDE_PLUGIN_ROOT supplies the plugin root" \
  || fail "CLAUDE_PLUGIN_ROOT fallback: $(sut_out "$res")"

r="$(mkrepo cprorder)"; res="$(_cpr "$P_OK" "$r" "$P_ALT")"
CASES_RUN=$((CASES_RUN + 1))
[[ "$(sut_rc "$res")" == "0" && "$(_git "$r" show HEAD:"$MODEL")" == *'"by":"plugin"'* && "$(sut_out "$res")" == *"root_src=sibling"* ]] \
  && pass "a sibling renderer wins over CLAUDE_PLUGIN_ROOT when both resolve" \
  || fail "CLAUDE_PLUGIN_ROOT displaced the sibling: $(sut_out "$res")"

# A RELATIVE CLAUDE_PLUGIN_ROOT resolves against the repo being merged: never used. The fixture
# makes it resolve to a VALID plugin inside the repo (ignored, so the tree stays clean), so a
# resolver that accepted it would render and commit — the refusal is the only thing in the way.
r="$(mkrepo cprrelative)"
mkdir -p "$r/rel"; cp -R "$P_OK/." "$r/rel/"; printf 'rel/\n' >> "$r/.git/info/exclude"
fpb="$(tree_fp "$r")"
res="$(_cpr "$P_LONELY" "$r" "rel")"
refused "a RELATIVE CLAUDE_PLUGIN_ROOT (resolving to a valid plugin inside the repo)" "$res" "$fpb" "$r" "reason=no-plugin-root"

r="$(mkrepo noroot)"; fpb="$(tree_fp "$r")"; res="$(run_at "$P_LONELY" "$r" main)"
refused "no plugin root at all" "$res" "$fpb" "$r" "reason=no-plugin-root"
CASES_RUN=$((CASES_RUN + 1))
grep -q 'set CLAUDE_PLUGIN_ROOT' <<<"$(sut_out "$res")" && pass "the no-root refusal names the remedy" \
  || fail "the no-root refusal is not actionable: $(sut_out "$res")"

r="$(mkrepo noid)"; fpb="$(tree_fp "$r")"; res="$(run_at "$P_NOID" "$r" main)"
refused "a sibling plugin.json that does not name soleur" "$res" "$fpb" "$r" "does not name soleur"
r="$(mkrepo noidenv)"; fpb="$(tree_fp "$r")"; res="$(_cpr "$P_LONELY" "$r" "$P_NOID")"
refused "a CLAUDE_PLUGIN_ROOT whose plugin.json does not name soleur" "$res" "$fpb" "$r" "does not name soleur"

# A no-conflict run never needs a plugin root: classification comes first.
r="$(mkrepo rootlast)"; _git "$r" checkout -q -B feature main >/dev/null 2>&1
res="$(run_at "$P_LONELY" "$r" main)"
CASES_RUN=$((CASES_RUN + 1))
grep -q 'reason=no-conflict' <<<"$(sut_out "$res")" && pass "a missing plugin root does not mask 'no conflict' (classification first)" \
  || fail "classification did not come first: $(sut_out "$res")"

# ── THE SEAM IS NOT REACHABLE FROM THE ENVIRONMENT (and the seam itself does execute) ──────
printf '%s\tbash\t-c\ttouch "$0/PWNED"\t%s\n' "$MODEL" "$SANDBOX" > "$SANDBOX/evil.tsv"
rm -f "$SANDBOX/PWNED"
r="$(mkrepo envseam)"
(cd "$r" && RESOLVABLE_OVERRIDE="$SANDBOX/evil.tsv" bash "$P_OK/scripts/resolve-regenerable-conflicts.sh" main >/dev/null 2>&1)
CASES_RUN=$((CASES_RUN + 1))
[[ ! -e "$SANDBOX/PWNED" ]] && pass "the resolvable set is not reachable from the environment (argv-only seam)" \
  || fail "RESOLVABLE_OVERRIDE still directs the resolver from the environment"
r="$(mkrepo envseamctl)"
res="$(run_sut "$r" main "$SANDBOX/evil.tsv")"
CASES_RUN=$((CASES_RUN + 1))
[[ -e "$SANDBOX/PWNED" ]] && pass "control: the same TSV through --test-resolvable DOES execute (the row above can fail)" \
  || fail "control: the test seam did not execute — the env-seam row proves nothing: $(sut_out "$res")"

# ── RATCHETS ────────────────────────────────────────────────────────────────────────────────
# Every assignment to the resolvable set or its argvs must carry a named marker, and the marker
# set is pinned. Structural: a new assignment site WITHOUT a marker fails too.
_sites="$(grep -nE '^[^#]*RESOLVABLE_(PATHS|ARGVS)(\[[^]]*\])?\+?=' "$SUT" | grep -vE 'RESOLVABLE_(PATHS|ARGVS)=\(\)')"
_n_sites="$(grep -c . <<<"$_sites")"
_unmarked="$(grep -vE '# (ARGV-SOURCE|RESOLVABLE-SET): [a-z-]+[[:space:]]*$' <<<"$_sites" || true)"
CASES_RUN=$((CASES_RUN + 1))
if [[ "$_n_sites" -eq 3 && -z "$_unmarked" ]]; then
  pass "every resolvable-set/argv assignment site carries a marker (3 sites)"
else
  fail "resolvable-set/argv assignment sites changed ($_n_sites; unmarked: $_unmarked) — an ADR-235 amendment is required"
fi
_default_paths="$(grep -E 'RESOLVABLE-SET: default[[:space:]]*$' "$SUT" | sed -n 's/^[^#]*RESOLVABLE_PATHS=(\(.*\))[[:space:]]*#.*$/\1/p')"
CASES_RUN=$((CASES_RUN + 1))
[[ "$(grep -c 'RESOLVABLE-SET: default' "$SUT")" -eq 1 && "$_default_paths" == "\"$MODEL\"" ]] \
  && pass "resolvable set: exactly one member, model.likec4.json (grow it deliberately + amend ADR-235)" \
  || fail "resolvable set changed: [$_default_paths]"
_argv_sources="$(grep -E '# ARGV-SOURCE: [a-z-]+[[:space:]]*$' "$SUT" | sed -E 's/.*# ARGV-SOURCE: ([a-z-]+)[[:space:]]*$/\1/' | LC_ALL=C sort | tr '\n' ' ')"
CASES_RUN=$((CASES_RUN + 1))
[[ "$_argv_sources" == "plugin test-seam " ]] && pass "argv sources: exactly {plugin, test-seam}" \
  || fail "argv sources changed: [$_argv_sources]"

# The resolver must NEVER push — in any git spelling (options before the subcommand count).
_PUSH_RE='(^|[^-[:alnum:]])git([[:space:]]+(-[Cc][[:space:]]+[^[:space:]]+|--?[[:alnum:]-]+(=[^[:space:]]+)?))*[[:space:]]+push([[:space:]]|$)'
CASES_RUN=$((CASES_RUN + 1))
if grep -v '^[[:space:]]*#' "$SUT" | grep -qE "$_PUSH_RE"; then
  fail "the resolver contains a git push — callers own the push"
else
  pass "the resolver never pushes"
fi
CASES_RUN=$((CASES_RUN + 1))
grep -qE "$_PUSH_RE" <<<'git -C "$REPO_ROOT" push -q origin HEAD' && pass "control: the no-push pattern sees an option-prefixed push" \
  || fail "control: the no-push pattern misses git -C <dir> push"

# ── tree_fp POSITIVE CONTROL ────────────────────────────────────────────────────────────────
_fpctl="$(mkrepo fpcontrol)"; _fp0="$(tree_fp "$_fpctl")"
printf 'dirty\n' >> "$_fpctl/$SRC"
CASES_RUN=$((CASES_RUN + 1))
[[ "$(tree_fp "$_fpctl")" != "$_fp0" ]] && pass "tree_fp control: a modified tracked file changes the fingerprint" \
  || fail "tree_fp is not observing — every 'tree untouched' verdict is vacuous"
_git "$_fpctl" checkout -q -- "$SRC"; printf 'u\n' > "$_fpctl/untracked.txt"
CASES_RUN=$((CASES_RUN + 1))
[[ "$(tree_fp "$_fpctl")" != "$_fp0" ]] && pass "tree_fp control: an untracked file changes the fingerprint" \
  || fail "tree_fp cannot see untracked files"

# ── AC9: NO DOCUMENTED INVOCATION IS REPO-RELATIVE ─────────────────────────────────────────
# Scoped to what an agent or hook executes; ADRs, plans and learnings quote history.
_REPO="$(cd "$SCRIPT_DIR/../../.." && pwd)"
_AC9_RE='(bash|sh|source|\.)[[:space:]]+["'"'"']?(\./)?(plugins/soleur/scripts/(resolve-regenerable-conflicts|render-c4-model)|scripts/regenerate-c4-model)\.sh'
_ac9_rc=0
_ac9="$(git -C "$_REPO" grep -nE "$_AC9_RE" -- plugins/soleur/skills plugins/soleur/commands plugins/soleur/agents \
  plugins/soleur/hooks AGENTS.rules.md ':!*.test.sh' ':!*.test.ts' 2>&1)" || _ac9_rc=$?
CASES_RUN=$((CASES_RUN + 1))
if [[ "$_ac9_rc" -eq 1 && -z "$_ac9" ]]; then
  pass "AC9: no skill, command, agent, plugin hook or rule invokes the resolver or renderer repo-relatively"
elif [[ "$_ac9_rc" -eq 0 ]]; then
  fail "AC9: repo-relative invocation(s) remain — use \"\${CLAUDE_PLUGIN_ROOT}/scripts/…\": $(tr '\n' ' ' <<<"$_ac9")"
else
  fail "AC9: git grep could not run (rc=$_ac9_rc): $_ac9"
fi
for _ctl in 'bash plugins/soleur/scripts/resolve-regenerable-conflicts.sh origin/main' \
            'bash "plugins/soleur/scripts/render-c4-model.sh"' 'bash scripts/regenerate-c4-model.sh'; do
  CASES_RUN=$((CASES_RUN + 1))
  grep -qE "$_AC9_RE" <<<"$_ctl" && pass "AC9 control: the sweep sees: $_ctl" \
    || fail "AC9 control: the sweep cannot match: $_ctl"
done

echo ""
echo "cases_run=$CASES_RUN passes=$passes fails=$fails ledger=${#FAILED[@]}"

_min_cases=134
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
