#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Guard 2 (#9729, ADR-276 S4, PR B) — "selection fails closed": scripts/ci-pr-selection.sh EXECUTED.
#
# WHAT THIS PROVES. The pr-selection driver may only ever err in one direction: any unknown yields the full battery
# (empty skip_legs, active=false). This suite does not grep the driver, it RUNS it, as the workflow does:
#   * against REAL throwaway git repositories with a genuine merge commit (HEAD = GITHUB_SHA, HEAD^2 = the PR head),
#   * with a stub test-all.sh (the PR_SELECTION_TEST_ALL seam) that replays the record shapes measured from the real
#     `--print-selection --paths=` and `--enumerate-commands --paths=` output (2026-10-14),
#   * under a PATH holding only bash, git and coreutils (no node, bun, python, jq, awk, sed, grep, perl, gh).
# Guard rows covered: G2-1 (not a merge shape / unresolvable base), G2-2 (the trigger list, derived from what
# scripts/test-all.sh sources), G2-5 (the switch is compared exactly), G2-6 / G2-12 (a step killed anywhere leaves only the
# defaults), G2-7 (a re-run), G2-9 (CI leaking into the selector call), G2-10 (empty or summary-less selector output), G2-11
# (a group with no records or a non-pr-gated decline), G2-13 (the activation lock), G2-14 (a newline or `::` in a path),
# G2-15 (docs rename/delete, diagrams, fork, >500 files, >64 KB listing, empty diff), and the must-PASS row: a legitimately
# doc-only knowledge-base diff reaches stage 2 and shows would-skip evidence while skip_legs stays EMPTY (locked).
# Also pinned here: the mode-aware stage 1 (a symlink or gitlink is `non_doc_mode`, a mode flip on a doc .md stays doc), the
# narrowed allowlist (`knowledge-base/**/*.md` or a root `*.md`, the NAME ends in `.md`), non-ASCII paths, the selector child
# never inheriting the step's output files, the notice fields (active, budget, sel_censored, groups) and the reasons
# affected_degraded / signalled / lever_error, budget sanitation (08, 010, 0, abc, empty, over 6 digits), the remaining-budget
# path (`rem`; a `timeout 0` can never occur), selection-shape fixtures, an advanced-base merge (the diff is the PR's own
# paths), the argv cap, and a leak sweep (path token, repo name, raw switch, shas) with an empty stderr on the normal path.
#
# EVERY GUARD ROW IS DRIVEN AGAINST A MUTANT. A sandbox copy of the driver has the guard deleted or neutered, the mutation
# is confirmed LANDED (the copy differs from the pristine bytes), the unmutated CONTROL runs first and must be GREEN, and the
# mutant must turn the row RED. A surviving mutant is a RESULT and is labelled fixture-gap or equivalent in the report.
#
# THE TRIGGER LIST is outcome-redundant with the allowlist today (every trigger path is already outside it). It stays as
# deliberate defense in depth and becomes load-bearing once the allowlist widens (PR C): one COMBINED behavioural mutant
# (a widened allowlist AND no trigger check) must reach stage 2 / arm a skip, which is a behavioural kill, not a label kill.
# Mutants whose ONLY red checks are reason labels are marked EQUIVALENT-LABEL in the battery below (verified with
# PRSEL_PROBE_VERBOSE=all, which names every check a mutant turned red).
#
# THE ACTIVATION LOCK IS TESTED BOTH WAYS: with the lock line present and SWITCH=on, active is false and skip_legs is
# empty (G2-13); a copy with the lock line removed and SWITCH=on on a doc-only fixture yields active=true for EXACTLY `on`.
#
# Run: bash scripts/ci-pr-selection.test.sh          (no network, no repo mutation: every repo is a throwaway)
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail

# A DIRECT invocation inherits the bare /tmp (a machine-global tmpfs shared by every worktree); the registered runners
# default to /var/tmp. Pin it so a verdict is never a function of another session's disk usage.
export TMPDIR="${TMPDIR:-/var/tmp}"

# Every GIT_* variable goes, by PREFIX, before the tripwire library is sourced (a hook-spawned run exports GIT_DIR and
# GIT_INDEX_FILE as absolute paths, and those win over cwd and `git -C`: a fixture would then act on the live repository).
for _v in ${!GIT_@}; do unset "$_v"; done
unset _v

passes=0
fails=0
# APPEND-ONLY FAILURE LEDGER: the exit status reads a list that can only be silenced by DELETING evidence, never by moving
# a number (a verdict computed as `fails -eq 0` shares its counter with the thing it guards).
FAILURES=()
pass() { passes=$((passes + 1)); }
fail() { fails=$((fails + 1)); FAILURES+=("$1"); printf 'FAIL: %s\n' "$1" >&2; }

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
DRIVER="$REPO_ROOT/scripts/ci-pr-selection.sh"
REAL_TEST_ALL="$REPO_ROOT/scripts/test-all.sh"
[ -f "$DRIVER" ] || { printf 'FAIL: %s not found\n' "$DRIVER" >&2; exit 2; }
[ -f "$REAL_TEST_ALL" ] || { printf 'FAIL: %s not found\n' "$REAL_TEST_ALL" >&2; exit 2; }

# shellcheck source=../plugins/soleur/test/lib/git-fixture-env.sh
source "$REPO_ROOT/plugins/soleur/test/lib/git-fixture-env.sh"

SANDBOX=$(mktemp -d "$TMPDIR/ci-pr-selection-test.XXXXXXXX") || {
  printf 'FAIL: could not create sandbox (mktemp -d failed)\n' >&2; exit 2; }
# A harness that fails to SET UP must abort: a half-built sandbox yields a confident wrong verdict about the SUT.
trap 'rm -rf "$SANDBOX"' EXIT
assert_fixture_dir() {  # every directory this suite writes into must be absolute (an empty or relative one would write into the cwd)
  case "${1-}" in
    "") printf 'FATAL: fixture dir is EMPTY\n' >&2; exit 2 ;;
    */../*|*/..) printf 'FATAL: fixture dir %s contains ..; refusing\n' "$1" >&2; exit 2 ;;
    /proc/*|/sys/*|/dev/*) printf 'FATAL: fixture dir %s is a synthetic-fs path; refusing\n' "$1" >&2; exit 2 ;;
    /|//|/.) printf 'FATAL: fixture dir resolves to the filesystem root; refusing\n' >&2; exit 2 ;;
    /*) : ;;
    *) printf 'FATAL: fixture dir %s is RELATIVE; refusing\n' "$1" >&2; exit 2 ;;
  esac
}

echo "=== Guard 2: pr-selection fails closed (#9729, ADR-276 S4) ==="

# ── INSTRUMENT SELF-TEST ─────────────────────────────────────────────────────
# Drive both helpers once and refuse to continue unless BOTH counters moved (a broken helper prints verdicts about the
# harness, not the SUT). Dispatched through pass()/fail() on purpose: it is the one check that cannot go through itself.
_p0=$passes; _f0=$fails
pass; fail "INSTRUMENT SELF-TEST (expected: this row proves fail() increments)" 2> /dev/null
if [ "$passes" -ne $((_p0 + 1)) ] || [ "$fails" -ne $((_f0 + 1)) ]; then
  printf 'FAIL: instrument self-test: pass()/fail() did not both move (passes %d->%d, fails %d->%d)\n' \
    "$_p0" "$passes" "$_f0" "$fails" >&2
  exit 2
fi
fails=$((fails - 1)); unset 'FAILURES[${#FAILURES[@]}-1]'
echo "  instrument self-test: pass() and fail() both move"

# ── The check primitive, with a PROBE mode ───────────────────────────────────
# In PROBE mode (a mutant is being driven) a failed check increments PROBE_FAILS and touches NEITHER the counters NOR the
# ledger, so the ledger stays append-only. A mutant is KILLED when PROBE_FAILS > 0.
PROBE=0
PROBE_FAILS=0
if [ -n "${PRSEL_PROBE_VERBOSE:-}" ]; then exec 3>&2; else exec 3>/dev/null; fi
record() {  # $1=label $2=ok(1|0) $3=detail
  if [ "$PROBE" = 1 ]; then
    if [ "$2" != 1 ]; then
      PROBE_FAILS=$((PROBE_FAILS + 1))
      # PRSEL_PROBE_VERBOSE=1 names the first check each mutant turned red, =all names every one (to review WHY a mutant died)
      if [ -n "${PRSEL_PROBE_VERBOSE:-}" ] && { [ "$PROBE_FAILS" -eq 1 ] || [ "${PRSEL_PROBE_VERBOSE}" = all ]; }; then printf 'probe-red[mutant %s]: %s: %s\n' "$MUT_N" "$1" "$3" >&3; fi
    fi
    return 0
  fi
  if [ "$2" = 1 ]; then pass; else fail "$1: $3"; fi
}
check_eq() {  # $1=label $2=got $3=want
  if [ "$2" = "$3" ]; then record "$1" 1 ""; else record "$1" 0 "got '$2', want '$3'"; fi
}
check_match() {  # $1=label $2=got $3=regex
  if [[ "$2" =~ $3 ]]; then record "$1" 1 ""; else record "$1" 0 "got '$2', want /$3/"; fi
}
check_contains() {  # $1=label $2=haystack $3=needle
  if [[ "$2" == *"$3"* ]]; then record "$1" 1 ""; else record "$1" 0 "'$3' not found in '${2:0:300}'"; fi
}
rc_of() { "$@" > /dev/null 2>&1; echo $?; }
check_true() {  # $1=label $2=condition-result(0=true)
  if [ "$2" -eq 0 ]; then record "$1" 1 ""; else record "$1" 0 "condition false"; fi
}

# ── The PATH the driver gets: bash, git and coreutils ONLY ───────────────────
BIN="$SANDBOX/bin"
mkdir -p "$BIN"
for _t in bash git env timeout mktemp wc tr rm cat mkdir sleep ls dirname basename head tail cut sort uniq touch cp mv \
          date id readlink pwd dd tee true false; do
  _p=$(command -v "$_t" 2>/dev/null) || continue
  case "$_p" in /*) ln -s "$_p" "$BIN/$_t" ;; esac
done
unset _t _p
_leaks=""
for _t in node bun python python3 jq awk gawk mawk sed grep egrep perl gh npm npx curl; do
  if env -i PATH="$BIN" bash -c "command -v $_t" >/dev/null 2>&1; then _leaks="$_leaks $_t"; fi
done
unset _t
if [ -n "$_leaks" ]; then
  printf 'FAIL: the restricted PATH still resolves:%s\n' "$_leaks" >&2; exit 2
fi
for _t in bash git timeout mktemp wc tr env rm; do
  [ -e "$BIN/$_t" ] || { printf 'FAIL: the restricted PATH is missing %s\n' "$_t" >&2; exit 2; }
done
unset _t
echo "  restricted PATH: bash, git and coreutils only (no node, bun, python, jq, awk, sed, grep, perl, gh)"

# ── Fixture git environment (hermetic config, discovery ceiling, synthesized identity) ──
FX="$SANDBOX/fx"
mkdir -p "$FX" "$SANDBOX/rt" "$SANDBOX/home" "$SANDBOX/tmp" "$SANDBOX/r"
git_fixture_env "$FX/_anchor" || { printf 'FAIL: git_fixture_env refused\n' >&2; exit 2; }

# ── What the real runner sources, and which of its declines are --pr-gated (DERIVED, never listed by hand) ──
SOURCED=()      # repo-relative paths scripts/test-all.sh sources
SOURCE_UNRESOLVED=()
derive_sourced() {
  local line var def op
  while IFS= read -r line; do
    case "$line" in [[:space:]]*'#'*|'#'*) continue ;; esac
    if [[ "$line" =~ ^[[:space:]]*(source|\.)[[:space:]]+\"\$([A-Za-z_][A-Za-z0-9_]*)\" ]]; then
      var="${BASH_REMATCH[2]}"
      def=$(grep -m1 -E "^[[:space:]]*(local[[:space:]]+)?${var}=" "$REAL_TEST_ALL") || def=""
      if [[ "$def" =~ \)/([A-Za-z0-9_./-]+)\"[[:space:]]*$ ]]; then
        SOURCED+=("scripts/${BASH_REMATCH[1]}")
      elif [[ "$def" =~ =\"(scripts/[A-Za-z0-9_./-]+)\" ]]; then
        SOURCED+=("${BASH_REMATCH[1]}")
      else
        SOURCE_UNRESOLVED+=("\$$var")
      fi
    elif [[ "$line" =~ ^[[:space:]]*(source|\.)[[:space:]]+\"?([A-Za-z0-9_./-]+)\"? ]]; then
      op="${BASH_REMATCH[2]}"
      SOURCED+=("$op")
    else
      SOURCE_UNRESOLVED+=("operand-of-unknown-shape")
    fi
  done < <(grep -E '^[[:space:]]*(source|\.)[[:space:]]+' "$REAL_TEST_ALL")
}
derive_sourced
mapfile -t SOURCED < <(printf '%s\n' "${SOURCED[@]}" | sort -u)

PRGATED_REAL=()
derive_pr_gated() {
  local pending=0 line
  while IFS= read -r line; do
    if [[ "$line" =~ ^[[:space:]]*if[[:space:]]+_diff_touches[[:space:]]+--pr-gated[[:space:]]+\"\$\{ ]]; then pending=1; continue; fi
    if [[ "$line" =~ ^[[:space:]]*fi[[:space:]]*$ ]]; then pending=0; continue; fi
    if [ "$pending" = 1 ] && [[ "$line" =~ ^[[:space:]]*skip_suite[[:space:]]+\"([^\"]+)\" ]]; then
      PRGATED_REAL+=("${BASH_REMATCH[1]}")
    fi
  done < "$REAL_TEST_ALL"
}
derive_pr_gated
mapfile -t PRGATED_REAL < <(printf '%s\n' "${PRGATED_REAL[@]}" | sort -u)

# The labels the DRIVER treats as pr-gated declines, read from its own is_pr_gated_decline function.
PRGATED_DRIVER=()
derive_driver_pr_gated() {
  local in=0 line
  while IFS= read -r line; do
    if [[ "$line" =~ ^is_pr_gated_decline\(\) ]]; then in=1; continue; fi
    if [ "$in" = 1 ] && [[ "$line" =~ ^\} ]]; then break; fi
    if [ "$in" = 1 ] && [[ "$line" =~ ^[[:space:]]+\"([^\"]+)\"\)[[:space:]]+return[[:space:]]+0 ]]; then
      PRGATED_DRIVER+=("${BASH_REMATCH[1]}")
    fi
  done < "$DRIVER"
}
derive_driver_pr_gated
mapfile -t PRGATED_DRIVER < <(printf '%s\n' "${PRGATED_DRIVER[@]}" | sort -u)

# ── The pristine driver, and the lock-neutralized COPY ───────────────────────
PRISTINE="$SANDBOX/drv.pristine.sh"
cp "$DRIVER" "$PRISTINE"
LOCK_RE='^readonly PR_AFFECTED_LOCKED=1  # ACTIVATION LOCK \(#9729\): PR C removes this line in its last commit$'
UNLOCKED="$SANDBOX/drv.unlocked.sh"
sed '/^readonly PR_AFFECTED_LOCKED=1  # ACTIVATION LOCK (#9729): PR C removes this line in its last commit$/d' "$PRISTINE" > "$UNLOCKED"

# ── Fixture builders ─────────────────────────────────────────────────────────
ALL="test-webplat,test-bun,test-scripts-heavy"
DEFAULTS=$'head_sha=\nbase_sha=\nactive=false\nskip_legs='

# Trigger-list entries (exact) plus one deep prefix case, plus every file the real runner sources.
TRIGGERS=(
  ".github/workflows/ci.yml"
  "scripts/ci-pr-selection.sh"
  "scripts/test-all.sh"
  "scripts/suite-shard-legs.tsv"
  "scripts/suite-shard-legs-heavy.tsv"
  "scripts/test-affected-kb-consumers.baseline.txt"
  "scripts/lib/zzleak-lib.sh"
  "scripts/lib/fixtures/zzleak-deep.txt"
)

FX_BASE="$FX/_base"
mkdir -p "$FX_BASE"
(
  cd "$FX_BASE" || exit 1
  git init -q -b main . || exit 1
  mk() { mkdir -p "$(dirname "$1")"; printf 'seed %s\n' "$1" > "$1"; }
  mk knowledge-base/project/learnings/zzleak-a.md
  mk knowledge-base/project/zzleak-b.md
  mk knowledge-base/engineering/architecture/diagrams/zzleak-c.md
  mk README.md
  mk CLAUDE.md
  mk scripts/ci-e2e-classify.sh
  mk plugins/soleur/docs/zzleak-page.md
  mk plugins/soleur/docs/zzleak-del.md
  mk apps/web-platform/zzleak-app.ts
  mk docs/legal/zzleak-terms.md
  mk Makefile
  for t in "${TRIGGERS[@]}" "${SOURCED[@]}"; do mk "$t"; done
  git add -A && git commit -q -m base || exit 1
) || { printf 'FAIL: could not build the base fixture repo\n' >&2; exit 2; }

fx_new() {  # $1=name
  cp -a "$FX_BASE" "$FX/$1" && git -C "$FX/$1" checkout -q -b pr
}
fx_op() {  # $1=name $2=op(M|A|D|R|T) $3=path [$4=path2]
  local d="$FX/$1"
  case "$2" in
    M) printf 'edit %s\n' "$RANDOM" >> "$d/$3"; git -C "$d" add -- "$3" ;;
    A) mkdir -p "$d/$(dirname -- "$3")"; printf 'new\n' > "$d/$3"; git -C "$d" add -- "$3" ;;
    D) git -C "$d" rm -q -- "$3" ;;
    R) mkdir -p "$d/$(dirname -- "$4")"; git -C "$d" mv -- "$3" "$4" ;;
    T) rm -f "$d/$3"; ln -s /etc/hostname "$d/$3"; git -C "$d" add -- "$3" ;;
    L) mkdir -p "$d/$(dirname -- "$3")"; ln -s /etc/hostname "$d/$3"; git -C "$d" add -- "$3" ;;  # a NEW symlink (A, 120000)
    G) git -C "$d" update-index --add --cacheinfo "160000,$(git -C "$d" rev-parse HEAD),$3" ;;      # a NEW gitlink (A, 160000)
    X) chmod +x "$d/$3"; git -C "$d" update-index --chmod=+x -- "$3" ;;                                               # mode flip 100644 -> 100755
  esac
}
fx_merge() {  # $1=name: commit the PR branch, then a genuine --no-ff merge commit on main
  local d="$FX/$1"
  git -C "$d" commit -q --allow-empty -m pr \
    && git -C "$d" checkout -q main \
    && git -C "$d" merge -q --no-ff -m merge pr
}
fx_case() {  # $1=name then ops as "OP:path[:path2]" words... is awkward for odd paths, so ops are separate calls
  fx_new "$1" || { printf 'FAIL: fx_new %s\n' "$1" >&2; exit 2; }
}
fx_done() { fx_merge "$1" || { printf 'FAIL: fx_merge %s\n' "$1" >&2; exit 2; }; }

KB_A="knowledge-base/project/learnings/zzleak-a.md"
KB_B="knowledge-base/project/zzleak-b.md"
KB_DIA="knowledge-base/engineering/architecture/diagrams/zzleak-c.md"

# k1: the legitimately doc-only diff (the must-PASS row's subject)
fx_case k1; fx_op k1 M "$KB_A"; fx_done k1
# k2: knowledge-base plus a root-level markdown file
fx_case k2; fx_op k2 M "$KB_A"; fx_op k2 M README.md; fx_done k2
# kad: an Added and a Deleted file, both inside the allowlist
fx_case kad; fx_op kad A "knowledge-base/zzleak-new.md"; fx_op kad D "$KB_B"; fx_done kad
# krn: a rename inside the allowlist (--no-renames makes it D + A)
fx_case krn; fx_op krn R "$KB_B" "knowledge-base/project/zzleak-b2.md"; fx_done krn
# dia: an architecture diagrams edit plus an ordinary doc edit
fx_case dia; fx_op dia M "$KB_DIA"; fx_op dia M "$KB_A"; fx_done dia
# docs: rename, delete and modify under plugins/soleur/docs (OUTSIDE the allowlist), plus other non-doc shapes
fx_case docren; fx_op docren R "plugins/soleur/docs/zzleak-page.md" "plugins/soleur/docs/zzleak-page2.md"; fx_done docren
fx_case docdel; fx_op docdel D "plugins/soleur/docs/zzleak-del.md"; fx_done docdel
fx_case docmod; fx_op docmod M "plugins/soleur/docs/zzleak-page.md"; fx_done docmod
fx_case code; fx_op code M "apps/web-platform/zzleak-app.ts"; fx_done code
fx_case legal; fx_op legal M "docs/legal/zzleak-terms.md"; fx_done legal
fx_case mk; fx_op mk M Makefile; fx_done mk
fx_case e2ec; fx_op e2ec M "scripts/ci-e2e-classify.sh"; fx_done e2ec
# odd paths
fx_case nl; fx_op nl A $'knowledge-base/zzleak-a\nb.md'; fx_done nl
fx_case cr; fx_op cr A $'knowledge-base/zzleak-cr\rx.md'; fx_done cr
fx_case tabp; fx_op tabp A $'knowledge-base/zzleak-tab\tx.md'; fx_done tabp
fx_case col; fx_op col A "knowledge-base/zzleak::warning.md"; fx_done col
fx_case com; fx_op com A "knowledge-base/zzleak,b.md"; fx_done com
# typechange (a file becomes a symlink): status T
fx_case typ; fx_op typ T "$KB_B"; fx_done typ
# modes: a new symlink and a new gitlink under knowledge-base, a symlink named *.md at the root, and a MODE-ONLY flip on a doc .md
fx_case msym; fx_op msym L "knowledge-base/project/zzleak-sym.md"; fx_done msym
fx_case mgit; fx_op mgit G "knowledge-base/project/zzleak-gl.md"; fx_done mgit
fx_case mrsym; fx_op mrsym L "zzleak-root-sym.md"; fx_done mrsym
fx_case mflip; fx_op mflip X "$KB_A"; fx_done mflip
# DELETING an existing symlink (old mode 120000, new 000000, status D): only the OLD-side mode check can refuse it
cp -a "$FX_BASE" "$FX/mdsym" && ln -s /etc/hostname "$FX/mdsym/knowledge-base/project/zzleak-oldsym.md" \
  && git -C "$FX/mdsym" add -A && git -C "$FX/mdsym" commit -q -m sym && git -C "$FX/mdsym" checkout -q -b pr \
  && git -C "$FX/mdsym" rm -q -- knowledge-base/project/zzleak-oldsym.md || { printf 'FAIL: fixture mdsym\n' >&2; exit 2; }
fx_done mdsym
# near-miss paths that are NOT on the allowlist (the NAME must end in .md under knowledge-base/ or at the root)
NEARMISS=(
  "knowledge-base-evil/zzleak-evil.md"
  "zzleak-root.mdx"
  "zzleak-x.md.sh"
  "knowledge-base/zzleak-x.md.sh"
  "knowledge-base/diagrams/zzleak-spec.c4"
  "knowledge-base/zzleak-x.json"
  "knowledge-base/zzleak-x.sh"
  "knowledge-base/zzleak-x.ts"
  "knowledge-base/zzleak-x.png"
  "knowledge-base/zzleak-x.pen"
  "knowledge-base/engineering/architecture/diagrams/zzleak-x.c4"
)
for _i in "${!NEARMISS[@]}"; do fx_case "nd$_i"; fx_op "nd$_i" A "${NEARMISS[$_i]}"; fx_done "nd$_i"; done
unset _i
# a bare FILE named `knowledge-base` (the directory goes away in the same PR)
fx_case ndbare
( cd "$FX/ndbare" && git rm -rq knowledge-base && printf 'x\n' > knowledge-base && git add knowledge-base )
fx_done ndbare
# non-ASCII paths: U+2028 (e2 80 a8), a C1 control (c2 85), a plain UTF-8 letter
fx_case nasc0; fx_op nasc0 A $'knowledge-base/zzleak-ls\xe2\x80\xa8x.md'; fx_done nasc0
fx_case nasc1; fx_op nasc1 A $'knowledge-base/zzleak-c1\xc2\x85x.md'; fx_done nasc1
fx_case nasc2; fx_op nasc2 A $'knowledge-base/zzleak-\xc3\xa9.md'; fx_done nasc2
# an ADVANCED base: main gains a non-doc commit AFTER the branch point; the PR itself is doc-only
fx_case adv; fx_op adv M "$KB_A"
git -C "$FX/adv" commit -q -m pr && git -C "$FX/adv" checkout -q main \
  && printf 'main moved\n' >> "$FX/adv/apps/web-platform/zzleak-app.ts" && git -C "$FX/adv" commit -q -am mainmove \
  && git -C "$FX/adv" merge -q --no-ff -m merge pr || { printf 'FAIL: fixture adv\n' >&2; exit 2; }
# a joined --paths list over 100000 bytes (40 files, ~2.8 KB paths: still one valid argument for the kernel) and one just under
_comp=$(printf 'a%.0s' $(seq 1 200))
_rel="knowledge-base"
for _i in $(seq 1 14); do _rel="$_rel/$_comp"; done
fx_big() {  # $1=fixture name $2=file count: that many doc files under one very deep directory
  local dir="$FX/$1/$_rel" i=0
  fx_case "$1"
  assert_fixture_dir "$dir"
  mkdir -p "$dir"
  while [ "$i" -lt "$2" ]; do printf 'x\n' > "$dir/f$i.md"; i=$((i + 1)); done
  git -C "$FX/$1" add -A
  fx_done "$1"
}
fx_big bigargv 40
fx_big bigok 33
unset _comp _rel _i
# an empty diff: a genuine merge commit whose tree equals the base tree
fx_case empty; fx_done empty
# bulk
fx_case n501
( cd "$FX/n501" && mkdir -p knowledge-base/bulk && i=0 && while [ "$i" -lt 501 ]; do printf 'x\n' > "knowledge-base/bulk/zzleak-$i.md"; i=$((i + 1)); done && git add -A )
fx_done n501
fx_case n500
( cd "$FX/n500" && mkdir -p knowledge-base/bulk && i=0 && while [ "$i" -lt 500 ]; do printf 'x\n' > "knowledge-base/bulk/zzleak-$i.md"; i=$((i + 1)); done && git add -A )
fx_done n500
# a >64 KB name-status listing inside the 500-file cap: 320 files with ~230-byte paths (about 74 KB of listing)
_long=$(printf 'd%.0s' $(seq 1 100))
_long2=$(printf 'f%.0s' $(seq 1 100))
fx_case big
( cd "$FX/big" && mkdir -p "knowledge-base/zzleak-$_long" && i=0 && while [ "$i" -lt 320 ]; do printf 'x\n' > "knowledge-base/zzleak-$_long/zzleak-$_long2-$i.md"; i=$((i + 1)); done && git add -A )
fx_done big
fx_case bigbad
( cd "$FX/bigbad" && mkdir -p "knowledge-base/zzleak-$_long" && i=0 && while [ "$i" -lt 320 ]; do printf 'x\n' > "knowledge-base/zzleak-$_long/zzleak-$_long2-$i.md"; i=$((i + 1)); done && git add -A )
fx_op bigbad M "apps/web-platform/zzleak-app.ts"
fx_done bigbad
unset _long _long2
# triggers: one fixture per entry, one per sourced file
for _i in "${!TRIGGERS[@]}"; do fx_case "trg$_i"; fx_op "trg$_i" M "${TRIGGERS[$_i]}"; fx_done "trg$_i"; done
for _i in "${!SOURCED[@]}"; do fx_case "src$_i"; fx_op "src$_i" M "${SOURCED[$_i]}"; fx_done "src$_i"; done
unset _i
# shape fixtures
fx_case nm; fx_op nm M "$KB_A"
git -C "$FX/nm" commit -q -m pr && git -C "$FX/nm" checkout -q main && git -C "$FX/nm" merge -q --ff-only pr > /dev/null 2>&1
fx_case octo; fx_op octo M "$KB_A"; git -C "$FX/octo" commit -q -m pr1
git -C "$FX/octo" checkout -q -b pr2 main && printf 'two\n' >> "$FX/octo/$KB_B" && git -C "$FX/octo" commit -q -am pr2
git -C "$FX/octo" checkout -q main && git -C "$FX/octo" merge -q --no-ff -m octopus pr pr2 > /dev/null 2>&1
git clone -q --depth 1 "file://$FX/k1" "$FX/shallow" 2>/dev/null
cp -a "$FX/k1" "$FX/broken"
_bt=$(git -C "$FX/broken" rev-parse 'HEAD^1^{tree}')
rm -f "$FX/broken/.git/objects/${_bt:0:2}/${_bt:2}"
unset _bt
mkdir -p "$FX/norepo"

# ── The stub test-all.sh: replays recorded shapes and logs what it was called with ──
STUB="$SANDBOX/stub-test-all.sh"
cat > "$STUB" <<'STUBEOF'
#!/usr/bin/env bash
# replay stub for scripts/test-all.sh (the PR_SELECTION_TEST_ALL seam). Uses only bash builtins and coreutils.
d="${STUB_DIR:?}"
n=0; [ -f "$d/count" ] && n=$(<"$d/count")
n=$((n + 1)); printf '%s' "$n" > "$d/count"
ci=UNSET; [ -n "${CI+x}" ] && ci=set
fa=UNSET; [ -n "${SOLEUR_TEST_FORCE_ALL+x}" ] && fa=set
w=""
for v in GITHUB_OUTPUT GITHUB_STEP_SUMMARY GITHUB_ENV GITHUB_PATH GITHUB_STATE; do [ -z "${!v+x}" ] || w="$w$v,"; done
[ -n "$w" ] || w=none
line="call=$n CI=$ci FORCE=$fa W=$w argv="
for a in "$@"; do
  case "$a" in
    --paths=*) printf '%s' "${a#--paths=}" > "$d/paths.$n"; line="$line[--paths=${#a}B]" ;;
    *) line="$line[$a]" ;;
  esac
done
printf '%s\n' "$line" >> "$d/log"
# a hostile child: try to forge the step's output file (only possible if the driver let it inherit GITHUB_OUTPUT)
[ -z "${STUB_WRITE_OUT:-}" ] || [ -z "${GITHUB_OUTPUT:-}" ] || printf 'active=true\nskip_legs=test-bun\n' >> "$GITHUB_OUTPUT"
[ "${STUB_HANG_AT:-0}" = "$n" ] && exec sleep 8
[ "${STUB_KILL_AT:-0}" = "$n" ] && kill -9 "$(<"$STUB_PIDFILE")"
[ "${STUB_TERM_AT:-0}" = "$n" ] && kill -TERM "$(<"$STUB_PIDFILE")"
[ -z "${STUB_SLEEP:-}" ] || exec sleep "$STUB_SLEEP"
case "${1:-}" in
  --print-selection) f="$d/sel.out"; rcf="$d/sel.rc" ;;
  --enumerate-commands) for last; do :; done; f="$d/enum-$last.out"; rcf="$d/enum-$last.rc" ;;
  *) exit 64 ;;
esac
[ ! -f "$f" ] || cat "$f"
rc=0; [ ! -f "$rcf" ] || rc=$(<"$rcf")
exit "$rc"
STUBEOF

# ── Scenarios: the selector's recorded output shapes ─────────────────────────
SC="$SANDBOX/sc"
mkdir -p "$SC"
sel_row() { printf 'AFFECTED_SELECTED\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "${4:-}"; }
enum_c() { printf 'SUITE_COMMAND\t%s\tbash\tscripts/zz.test.sh\n' "$1"; }
enum_d() { printf 'SUITE_COMMAND_DECLINED\t%s\tbash scripts/zz.test.sh\n' "$1"; }
SUMMARY_OK='AFFECTED_SUMMARY selected=116 of=619 always_on=114 edge=2 fallback=none'

mk_allskip() {  # $1=dir : every gateable group qualifies (webplat/bun by sel=0 rows, heavy by pr-gated declines + one sel=0 row)
  local d="$1"; assert_fixture_dir "$d"; mkdir -p "$d"
  {
    sel_row "apps/web-platform [repo-wide+component]" 0 edge:consumed "^apps/web-platform/"
    sel_row "apps/cla-evidence/test/ccla-add.test.sh" 0 edge:derived "^apps/cla-evidence/"
    sel_row "scripts/followthroughs/ccla-representative-icla-7922" 0 edge:derived "^scripts/followthroughs/"
    sel_row "apps/web-platform/test/destroy-ask-mutation" 0 edge:derived "^apps/web-platform/test/"
    sel_row "apps/web-platform/test/vitest-related" 0 edge:declared "^apps/web-platform/test/vitest-related.test.sh"
    sel_row "test/content-publisher" 0 edge:declared "^test/content-publisher.test.ts"
    sel_row "test/x-community" 0 edge:declared "^test/x-community.test.ts"
    sel_row "test/linkedin-community" 0 edge:declared "^test/linkedin-community.test.ts"
    sel_row "test/pre-merge-rebase" 0 edge:declared "^test/pre-merge-rebase.test.ts"
    sel_row "plugins/soleur" 0 edge:declared "^plugins/soleur/"
    sel_row "scripts/zz-heavy-example" 0 edge:declared "^scripts/zz-heavy-example.test.sh"
    sel_row "scripts/lint-rule-ids-live" 1 always_on ""
    printf '%s\n' "$SUMMARY_OK"
  } > "$d/sel.out"
  {
    printf 'ORPHAN_SCAN valid=1 stale=0\n'
    enum_c "apps/web-platform [repo-wide+component]"
    enum_c "apps/cla-evidence/test/ccla-add.test.sh"
    enum_c "scripts/followthroughs/ccla-representative-icla-7922"
    enum_c "apps/web-platform/test/destroy-ask-mutation"
    enum_c "apps/web-platform/test/vitest-related"
  } > "$d/enum-webplat.out"
  {
    enum_c "test/content-publisher"; enum_c "test/x-community"; enum_c "test/linkedin-community"
    enum_c "test/pre-merge-rebase"; enum_c "plugins/soleur"
  } > "$d/enum-bun.out"
  {
    enum_d "tests/scripts/registry-gate-mutation-battery"
    enum_d "scripts/battery-tag-authorship-mutations"
    enum_c "scripts/zz-heavy-example"
  } > "$d/enum-scripts-heavy.out"
}
mk_allskip "$SC/allskip"

# REAL: the shapes measured on 2026-10-14 for a one-file knowledge-base diff (labels, classes and record kinds verbatim;
# the long edge columns trimmed). webplat holds a plain relevance decline, bun two always-on suites, heavy a plain decline.
mkdir -p "$SC/real"
{
  sel_row "apps/web-platform [repo-wide+component]" 0 edge:consumed "^apps/web-platform/scripts/vitest-related.sh"
  sel_row "apps/cla-evidence/test/ccla-add.test.sh" 0 edge:derived "^apps/cla-evidence/test/ccla-add.test.sh"
  sel_row "scripts/followthroughs/ccla-representative-icla-7922" 0 edge:derived "^scripts/followthroughs/ccla-representative-icla-7922.test.sh"
  sel_row "apps/web-platform/test/destroy-ask-mutation" 0 edge:derived "^apps/web-platform/test/destroy-ask-mutation.test.sh"
  sel_row "apps/web-platform/test/vitest-related" 0 edge:declared "^apps/web-platform/test/vitest-related.test.sh"
  sel_row "test/content-publisher" 0 edge:declared "^test/content-publisher.test.ts"
  sel_row "test/x-community" 0 edge:declared "^test/x-community.test.ts"
  sel_row "test/linkedin-community" 0 edge:declared "^test/linkedin-community.test.ts"
  sel_row "test/pre-merge-rebase" 0 edge:declared "^test/pre-merge-rebase.test.ts"
  sel_row "plugins/soleur" 0 edge:declared "^plugins/soleur/"
  sel_row "blog-link-validation" 1 always_on ""
  sel_row "scripts/frontmatter-strip-parity" 1 always_on ""
  sel_row "scripts/test-affected-kb-consumers" 1 edge:declared "^scripts/test-affected-kb-consumers.test.sh"
  sel_row "plugins/soleur/test/operator-agent-runnable.test.sh" 1 edge:declared "^plugins/soleur/test/operator-agent-runnable.test.sh"
  printf '%s\n' "$SUMMARY_OK"
} > "$SC/real/sel.out"
{
  printf 'SUITE_COMMAND\tapps/web-platform [repo-wide+component]\tenv\tVITEST_SHARD=\tWEBPLAT_RELATED=\tbash\tapps/web-platform/scripts/vitest-related.sh\tbundle\n'
  printf 'SUITE_COMMAND_DECLINED\tapps/web-platform [unit]\tbash apps/web-platform/scripts/vitest-related.sh unit\n'
  printf 'SUITE_COMMAND\tapps/cla-evidence/test/ccla-add.test.sh\tbash\tapps/cla-evidence/test/ccla-add.test.sh\n'
  printf 'SUITE_COMMAND\tscripts/followthroughs/ccla-representative-icla-7922\tbash\tscripts/followthroughs/ccla-representative-icla-7922.test.sh\n'
  printf 'SUITE_COMMAND\tapps/web-platform/test/destroy-ask-mutation\tbash\tapps/web-platform/test/destroy-ask-mutation.test.sh\n'
  printf 'SUITE_COMMAND\tapps/web-platform/test/vitest-related\tbash\tapps/web-platform/test/vitest-related.test.sh\n'
} > "$SC/real/enum-webplat.out"
{
  printf 'SUITE_COMMAND\ttest/content-publisher\tbun\ttest\ttest/content-publisher.test.ts\n'
  printf 'SUITE_COMMAND\ttest/x-community\tbun\ttest\ttest/x-community.test.ts\n'
  printf 'SUITE_COMMAND\ttest/linkedin-community\tbun\ttest\ttest/linkedin-community.test.ts\n'
  printf 'SUITE_COMMAND\ttest/pre-merge-rebase\tbun\ttest\ttest/pre-merge-rebase.test.ts\n'
  printf 'SUITE_COMMAND\tplugins/soleur\tbun\ttest\tplugins/soleur/\n'
  printf 'SUITE_COMMAND\tblog-link-validation\tbash\tscripts/validate-blog-links.sh\n'
  printf 'SUITE_COMMAND\tscripts/frontmatter-strip-parity\tbash\tscripts/lib/frontmatter-strip.test.sh\n'
} > "$SC/real/enum-bun.out"
{
  printf 'SUITE_COMMAND_DECLINED\ttests/scripts/registry-gate-mutation-battery\tbash tests/scripts/test-registry-gate-mutation-battery.sh\n'
  printf 'SUITE_COMMAND_DECLINED\tscripts/battery-tag-authorship-mutations\tbash scripts/battery-tag-authorship-mutations.test.sh\n'
  printf 'SUITE_COMMAND_DECLINED\t.github/scripts/test/run-all.sh\tbash .github/scripts/test/run-all.sh\n'
} > "$SC/real/enum-scripts-heavy.out"

variant() {  # $1=name ; copies allskip then applies the named edit
  local d="$SC/$1"; assert_fixture_dir "$d"; mkdir -p "$d"; cp "$SC/allskip"/* "$d/"
  case "$1" in
    nosummary)   { grep -v '^AFFECTED_SUMMARY' "$SC/allskip/sel.out"; } > "$d/sel.out" ;;
    empty)       : > "$d/sel.out" ;;
    fb_both)     { sed '$d' "$SC/allskip/sel.out"; printf 'AFFECTED_FALLBACK\treason=runner-changed\n'
                   printf 'AFFECTED_SUMMARY selected=all of=all always_on=all edge=all fallback=runner-changed\n'; } > "$d/sel.out" ;;
    fb_summary)  { sed '$d' "$SC/allskip/sel.out"
                   printf 'AFFECTED_SUMMARY selected=all of=all always_on=all edge=all fallback=force-all\n'; } > "$d/sel.out" ;;
    fb_numeric)  { sed '$d' "$SC/allskip/sel.out"
                   printf 'AFFECTED_SUMMARY selected=116 of=619 always_on=114 edge=2 fallback=runner-changed\n'; } > "$d/sel.out" ;;
    fb_line)     { sed '$d' "$SC/allskip/sel.out"; printf 'AFFECTED_FALLBACK\treason=runner-changed\n'; printf '%s\n' "$SUMMARY_OK"; } > "$d/sel.out" ;;
    unresolved)  { sed '$d' "$SC/allskip/sel.out"; printf 'AFFECTED_UNRESOLVED\treason=zero-selected\n'; printf '%s\n' "$SUMMARY_OK"; } > "$d/sel.out" ;;
    garbage)     { cat "$SC/allskip/sel.out"; printf 'AFFECTED_SELECTED\tonlytwo\n'; } > "$d/sel.out" ;;
    twosummary)  { cat "$SC/allskip/sel.out"; printf '%s\n' "$SUMMARY_OK"; } > "$d/sel.out" ;;
    badsel)      { sed '$d' "$SC/allskip/sel.out"; sel_row "zz/badsel" 2 edge:declared ""; printf '%s\n' "$SUMMARY_OK"; } > "$d/sel.out" ;;
    selrc)       printf '3' > "$d/sel.rc" ;;
    emptygroup)  : > "$d/enum-bun.out" ;;
    plain)       { cat "$SC/allskip/enum-bun.out"; enum_d "some/plain-relevance-label"; } > "$d/enum-bun.out" ;;
    missing)     { cat "$SC/allskip/enum-bun.out"; enum_c "zz/not-in-the-selection"; } > "$d/enum-bun.out" ;;
    alwayson)    { sed '$d' "$SC/allskip/sel.out"; sel_row "plugins/soleur" 0 always_on ""; printf '%s\n' "$SUMMARY_OK"; } > "$d/sel.out" ;;
    selected)    { sed '$d' "$SC/allskip/sel.out"; sel_row "test/x-community" 1 edge:declared ""; printf '%s\n' "$SUMMARY_OK"; } > "$d/sel.out" ;;
    webrc)       printf '2' > "$d/enum-webplat.rc" ;;
    badrecord)   { cat "$SC/allskip/enum-bun.out"; printf 'SUITE_COMMANDX\twhat\n'; } > "$d/enum-bun.out" ;;
    noprefix)    { printf 'garbage line only\n'; } > "$d/enum-bun.out" ;;
    norows)      # a valid summary but ZERO selection rows, while every group holds only pr-gated declines (would skip all if accepted)
                 printf '%s\n' "$SUMMARY_OK" > "$d/sel.out"
                 for _g in webplat bun scripts-heavy; do
                   { enum_d "scripts/lint-orphan-test-suites-mutations-a"; enum_d "scripts/cf-tunnel-liveness-gate-mutations"; } > "$d/enum-$_g.out"
                 done ;;
    twotabs)     { sed '$d' "$SC/allskip/sel.out"; printf 'AFFECTED_SELECTED\tzz/twotabs\t0\n'; printf '%s\n' "$SUMMARY_OK"; } > "$d/sel.out" ;;
    nocls)       { sed '$d' "$SC/allskip/sel.out"; printf 'AFFECTED_SELECTED\tzz/nocls\t0\t\t^x\n'; printf '%s\n' "$SUMMARY_OK"; } > "$d/sel.out" ;;
    allnum)      { sed '$d' "$SC/allskip/sel.out"
                   printf 'AFFECTED_SUMMARY selected=all of=all always_on=all edge=all fallback=none\n'; } > "$d/sel.out" ;;
    heavydecl)   { enum_d "tests/scripts/registry-gate-mutation-battery"; enum_d "scripts/battery-tag-authorship-mutations"; } > "$d/enum-scripts-heavy.out" ;;
    heavyzero)   printf 'ORPHAN_SCAN valid=1 stale=0\n' > "$d/enum-scripts-heavy.out" ;;
  esac
}
for _v in nosummary empty fb_both fb_summary fb_numeric fb_line unresolved garbage twosummary badsel selrc emptygroup plain missing alwayson selected webrc badrecord noprefix \
          norows twotabs nocls allnum heavydecl heavyzero; do
  variant "$_v"
done
unset _v

# ── drive(): run the driver once, hermetically, and assert the invariants every run must hold ──
RUN_N=0
SCEN="$SC/allskip"
EXPECT_KILLED=0
EXPECT_STDERR=0   # 1 only for the row that INJECTS a shell error (its stderr legitimately names the unbound variable)
LEAK="zzleak"
REPO_NAME="zzleak-org/zzleak-repo"   # carries the leak token: the repository name must reach no output

drive() {  # $1=fixture $2=driver-file; remaining args: KEY=VALUE overrides (later wins)
  local name="$1" drv="$2"; shift 2
  local repo="$FX/$name" head prhead o line
  RUN_N=$((RUN_N + 1))
  o="$SANDBOX/r/$RUN_N"
  assert_fixture_dir "$o"
  mkdir -p "$o/stub"
  cp "$SCEN"/* "$o/stub/" 2>/dev/null
  : > "$o/gh.out"; : > "$o/sum.out"
  head=$(git -C "$repo" rev-parse HEAD 2>/dev/null) || head="0000000000000000000000000000000000000000"
  prhead=$(git -C "$repo" rev-parse 'HEAD^2' 2>/dev/null) || prhead="$head"
  local -a e=(
    "PATH=$BIN" "HOME=$SANDBOX/home" "TMPDIR=$SANDBOX/tmp" "LANG=C"
    "GIT_CEILING_DIRECTORIES=$GIT_CEILING_DIRECTORIES" "GIT_CONFIG_NOSYSTEM=1" "GIT_CONFIG_GLOBAL=/dev/null"
    "GIT_ATTR_NOSYSTEM=1" "XDG_CONFIG_HOME=$XDG_CONFIG_HOME" "GIT_TERMINAL_PROMPT=0"
    "EVENT_NAME=pull_request" "SWITCH=" "GITHUB_SHA=$head" "PR_HEAD_SHA=$prhead"
    "HEAD_REPO=$REPO_NAME" "GH_REPO=$REPO_NAME" "RUN_ATTEMPT=1"
    "GITHUB_OUTPUT=$o/gh.out" "GITHUB_STEP_SUMMARY=$o/sum.out" "RUNNER_TEMP=$SANDBOX/rt"
    "GITHUB_ENV=$o/gh.env" "GITHUB_PATH=$o/gh.path" "GITHUB_STATE=$o/gh.state"
    "PR_SELECTION_TEST_ALL=$STUB" "PR_SELECTION_STAGE2_TIMEOUT=30"
    "STUB_DIR=$o/stub" "STUB_PIDFILE=$o/pid" "DRV=$drv"
  )
  # shellcheck disable=SC2016  # the single-quoted body is for the child shell to expand
  { ( cd "$repo" && env -i "${e[@]}" "$@" bash -c 'printf %s "$$" | tee "$STUB_PIDFILE" > /dev/null; exec bash "$DRV"' ) > "$o/stdout" 2> "$o/stderr"; } 2> /dev/null
  RC=$?
  O="$o"
  # outputs: last value per key wins (the GITHUB_OUTPUT rule); the line count tells defaults-only from defaults+final
  O_HEAD=""; O_BASE=""; O_ACTIVE=""; O_SKIP=""; O_NLINES=0; O_TEXT=""
  while IFS= read -r line; do
    O_NLINES=$((O_NLINES + 1))
    O_TEXT="${O_TEXT:+$O_TEXT$'\n'}$line"
    case "$line" in
      head_sha=*) O_HEAD="${line#head_sha=}" ;;
      base_sha=*) O_BASE="${line#base_sha=}" ;;
      active=*) O_ACTIVE="${line#active=}" ;;
      skip_legs=*) O_SKIP="${line#skip_legs=}" ;;
    esac
  done < "$o/gh.out"
  # the annotation
  NOTICE=""; NOTICE_N=0; STDOUT_N=0
  while IFS= read -r line; do
    STDOUT_N=$((STDOUT_N + 1))
    case "$line" in '::notice title=ci-pr-selection::SOLEUR_PR_SELECTION '*) NOTICE_N=$((NOTICE_N + 1)); NOTICE="$line" ;; esac
  done < "$o/stdout"
  N_SWITCH=""; N_LOCKED=""; N_ATTEMPT=""; N_FILES=""; N_STAGE=""; N_REASON=""; N_WOULD=""; N_SELS=""
  N_CENS=""; N_BUDGET=""; N_ACTIVE=""; N_GROUPS=""
  if [[ "$NOTICE" =~ ^::notice\ title=ci-pr-selection::SOLEUR_PR_SELECTION\ switch=(unset|on|invalid)\ locked=(true|false)\ attempt=([0-9]+)\ files=([0-9]+)\ stage=([12])\ reason=([a-z_]+)\ would_skip=(none|[a-z,-]+)\ sel_s=([0-9]+)\ sel_censored=([01])\ budget=([0-9]+)\ active=(true|false)\ groups=(-|webplat:[a-z_]+,bun:[a-z_]+,scripts-heavy:[a-z_]+)$ ]]; then
    N_SWITCH="${BASH_REMATCH[1]}"; N_LOCKED="${BASH_REMATCH[2]}"; N_ATTEMPT="${BASH_REMATCH[3]}"; N_FILES="${BASH_REMATCH[4]}"
    N_STAGE="${BASH_REMATCH[5]}"; N_REASON="${BASH_REMATCH[6]}"; N_WOULD="${BASH_REMATCH[7]}"; N_SELS="${BASH_REMATCH[8]}"
    N_CENS="${BASH_REMATCH[9]}"; N_BUDGET="${BASH_REMATCH[10]}"; N_ACTIVE="${BASH_REMATCH[11]}"; N_GROUPS="${BASH_REMATCH[12]}"
    NOTICE_OK=1
  else
    NOTICE_OK=0
  fi
  STUB_CALLS=0; [ -f "$o/stub/count" ] && STUB_CALLS=$(<"$o/stub/count")
  SUMTXT=""; [ -s "$o/sum.out" ] && SUMTXT=$(<"$o/sum.out")

  # ---- invariants (every run) ----
  if [ "$EXPECT_KILLED" = 1 ]; then
    check_eq "run$RUN_N($name) killed driver exits 137" "$RC" "137"
    check_eq "run$RUN_N($name) a killed step leaves ONLY the defaults" "$O_TEXT" "$DEFAULTS"
  else
    check_eq "run$RUN_N($name) the driver exits 0" "$RC" "0"
    check_true "run$RUN_N($name) exactly one well-formed annotation" "$([ "$NOTICE_OK" = 1 ] && [ "$NOTICE_N" = 1 ] && [ "$STDOUT_N" = 1 ]; echo $?)"
    check_true "run$RUN_N($name) defaults then one final block (8 lines) or defaults only on a crash" "$([ "$O_NLINES" = 8 ] || [ "$O_NLINES" = 4 ]; echo $?)"
  fi
  check_match "run$RUN_N($name) annotation counters are numeric" "$N_ATTEMPT/$N_SELS" '^[0-9]*/[0-9]*$'
  check_match "run$RUN_N($name) head_sha grammar" "$O_HEAD" '^([0-9a-f]{40})?$'
  check_match "run$RUN_N($name) base_sha grammar" "$O_BASE" '^([0-9a-f]{40})?$'
  check_match "run$RUN_N($name) active grammar" "$O_ACTIVE" '^(true|false)$'
  check_match "run$RUN_N($name) skip_legs grammar" "$O_SKIP" '^([a-z-]+(,[a-z-]+)*)?$'
  if [ "$O_ACTIVE" = true ]; then
    check_true "run$RUN_N($name) active=true carries a non-empty skip list" "$([ -n "$O_SKIP" ]; echo $?)"
  else
    check_eq "run$RUN_N($name) skip_legs is empty unless active" "$O_SKIP" ""
  fi
  local f leaked=0 shaleak=0 base
  base=$(git -C "$repo" rev-parse 'HEAD^1' 2>/dev/null) || base="$head"
  for f in "$o/gh.out" "$o/stdout" "$o/stderr" "$o/sum.out"; do
    if grep -qF "$LEAK" "$f"; then leaked=1; fi
  done
  # the two audit shas (and the merge sha) belong in the output FILE only, never in stderr, the notice or the summary
  for f in "$o/stdout" "$o/stderr" "$o/sum.out"; do
    if grep -qF -e "$head" -e "$prhead" -e "$base" "$f"; then shaleak=1; fi
  done
  check_eq "run$RUN_N($name) no raw path, repo name or switch value in any output, annotation or summary" "$leaked" "0"
  check_eq "run$RUN_N($name) no sha in stderr, the notice or the summary" "$shaleak" "0"
  if [ "$EXPECT_KILLED" != 1 ] && [ "$EXPECT_STDERR" != 1 ]; then
    check_eq "run$RUN_N($name) stderr is empty" "$(head -c 200 "$o/stderr")" ""
  fi
}

expect_full() {  # $1=label $2=reason $3=expected stub calls
  check_eq "$1: reason" "$N_REASON" "$2"
  check_eq "$1: active" "$O_ACTIVE" "false"
  check_eq "$1: skip_legs" "$O_SKIP" ""
  check_eq "$1: stub calls" "$STUB_CALLS" "$3"
  check_eq "$1: notice active" "$N_ACTIVE" "false"
}

# ═══ THE ROWS ═══════════════════════════════════════════════════════════════
# Each row takes the driver file to drive ($1), so the same row runs against the pristine driver (CONTROL) and a mutant.

row_not_pr() {  # G2: only a pull_request run selects
  local d="$1" ev
  for ev in push merge_group workflow_dispatch ""; do
    drive k1 "$d" "EVENT_NAME=$ev"
    expect_full "G2-NOT-PR event='$ev'" not_pr 0
    check_eq "G2-NOT-PR event='$ev': no head_sha audit value" "$O_HEAD" ""
  done
}
row_shape_ok() {  # the validated shape emits the audit values
  local d="$1" p1 p2
  drive k1 "$d"
  p1=$(git -C "$FX/k1" rev-parse 'HEAD^1'); p2=$(git -C "$FX/k1" rev-parse 'HEAD^2')
  check_eq "G2-1 valid shape: head_sha is HEAD^2" "$O_HEAD" "$p2"
  check_eq "G2-1 valid shape: base_sha is HEAD^1" "$O_BASE" "$p1"
  check_eq "G2-1 valid shape: reaches stage 2" "$N_STAGE" "2"
}
row_shape_count() {  # G2-1: exactly two parents (an octopus whose HEAD^2 IS the PR head still fails)
  local d="$1"
  drive octo "$d"
  check_eq "G2-1 three-parent merge: precondition (4 words in rev-list)" "$(git -C "$FX/octo" rev-list --parents -n 1 HEAD | wc -w)" "4"
  expect_full "G2-1 three-parent merge" bad_merge_shape 0
  drive nm "$d"
  expect_full "G2-1 a non-merge HEAD (one parent)" bad_merge_shape 0
  check_eq "G2-1 a non-merge HEAD: no audit values" "$O_HEAD$O_BASE" ""
}
row_shape_githubsha() {  # G2-1: HEAD must be GITHUB_SHA
  local d="$1" b
  b=$(git -C "$FX/k1" rev-parse 'HEAD^1')
  drive k1 "$d" "GITHUB_SHA=$b"
  expect_full "G2-1 HEAD != GITHUB_SHA" bad_merge_shape 0
  drive k1 "$d" "GITHUB_SHA=ABCDEF"
  expect_full "G2-1 malformed GITHUB_SHA" bad_merge_shape 0
}
row_shape_prhead() {  # G2-1: HEAD^2 must be the PR head
  local d="$1" b
  b=$(git -C "$FX/k1" rev-parse 'HEAD^1')
  drive k1 "$d" "PR_HEAD_SHA=$b"
  expect_full "G2-1 HEAD^2 != PR head sha" bad_merge_shape 0
  check_eq "G2-1 HEAD^2 != PR head sha: no audit values" "$O_HEAD$O_BASE" ""
  drive k1 "$d" "PR_HEAD_SHA="
  expect_full "G2-1 empty PR head sha" bad_merge_shape 0
}
row_shape_shallow() {  # H2: a depth-1 checkout (fetch-depth broken) is full
  local d="$1"
  drive shallow "$d"
  expect_full "H2 shallow checkout" bad_merge_shape 0
  drive norepo "$d"
  expect_full "G2-1 not a repository" bad_merge_shape 0
}
row_diff_error() {  # G2-1: `git diff` fails with an otherwise valid shape (a missing tree object)
  local d="$1"
  drive broken "$d"
  expect_full "G2-1 git diff fails" diff_error 0
}
row_trigger_core() {  # G2-2: every trigger-list entry
  local d="$1" i
  for i in "${!TRIGGERS[@]}"; do
    drive "trg$i" "$d"
    expect_full "G2-2 trigger '${TRIGGERS[$i]}'" trigger 0
  done
  drive e2ec "$d"
  expect_full "G2-2 scripts/ci-e2e-classify.sh is NOT on the list (CTO trim) but is outside the allowlist" non_doc 0
}
row_trigger_sourced() {  # G2-2: everything scripts/test-all.sh sources
  local d="$1" i
  for i in "${!SOURCED[@]}"; do
    drive "src$i" "$d"
    expect_full "G2-2 sourced file '${SOURCED[$i]}'" trigger 0
  done
}
row_switch() {  # G2-5: the switch is compared EXACTLY (run against the lock-neutralized driver so the switch is what decides)
  local d="$1" v
  drive k1 "$d" "SWITCH=on"
  check_eq "G2-13/5 SWITCH=on on a doc-only diff, no lock: active" "$O_ACTIVE" "true"
  check_eq "G2-13/5 SWITCH=on, no lock: skip_legs" "$O_SKIP" "$ALL"
  check_eq "G2-13/5 SWITCH=on: annotation switch/locked" "$N_SWITCH/$N_LOCKED" "on/false"
  for v in "ON" "On" " on" "on " $'on\n' $'\non' "1" "true" "yes" "onn" "o" "off" "\"on\""; do
    drive k1 "$d" "SWITCH=$v"
    check_eq "G2-5 SWITCH='${v//$'\n'/\\n}': active" "$O_ACTIVE" "false"
    check_eq "G2-5 SWITCH='${v//$'\n'/\\n}': skip_legs" "$O_SKIP" ""
    check_eq "G2-5 SWITCH='${v//$'\n'/\\n}': annotation says invalid, never the raw value" "$N_SWITCH" "invalid"
  done
  drive k1 "$d" "SWITCH="
  check_eq "G2-5 SWITCH unset: annotation" "$N_SWITCH" "unset"
  check_eq "G2-5 SWITCH unset: active" "$O_ACTIVE" "false"
  drive empty "$d" "SWITCH=on"
  check_eq "G2-5 SWITCH=on on a full-battery diff: active stays false" "$O_ACTIVE" "false"
  drive k1 "$d" "SWITCH=on"
  check_eq "notice: active=true is reported when the arm fires" "$N_ACTIVE" "true"
  check_eq "notice: the armed run reports every group" "$N_GROUPS" "webplat:skip,bun:skip,scripts-heavy:skip"
}
row_lock() {  # G2-13: the lock is present and SWITCH=on
  local d="$1"
  drive k1 "$d" "SWITCH=on"
  check_eq "G2-13 lock present + SWITCH=on: active" "$O_ACTIVE" "false"
  check_eq "G2-13 lock present + SWITCH=on: skip_legs" "$O_SKIP" ""
  check_eq "G2-13 lock present + SWITCH=on: annotation switch/locked" "$N_SWITCH/$N_LOCKED" "on/true"
  check_eq "G2-13 the would-skip evidence is still produced under the lock" "$N_WOULD" "$ALL"
  drive k1 "$d" "SWITCH="
  check_eq "G2-13 dark: skip_legs" "$O_SKIP" ""
  check_eq "G2-13 dark: would-skip evidence" "$N_WOULD" "$ALL"
}
row_skip_gated_on_active() {  # skip_legs is written ONLY when active=true
  local d="$1"
  drive k1 "$d" "SWITCH="
  check_eq "skip_legs only when active (switch unset)" "$O_SKIP" ""
  drive k1 "$d" "SWITCH=ON"
  check_eq "skip_legs only when active (switch ON)" "$O_SKIP" ""
}
row_defaults_first() {  # G2-6 / G2-12: a step killed anywhere leaves exactly the defaults (adversarial config: unlocked + on)
  local d="$1" at
  EXPECT_KILLED=1
  for at in 1 2 3 4; do
    drive k1 "$d" "SWITCH=on" "STUB_KILL_AT=$at"
  done
  EXPECT_KILLED=0
}
row_term() {  # a SIGTERM (a cancelled job) still exits 0 and leaves the defaults
  local d="$1"
  drive k1 "$d" "SWITCH=on" "STUB_TERM_AT=2"
  check_eq "SIGTERM mid stage 2: outputs are the defaults" "$O_TEXT" "$DEFAULTS"
  check_eq "SIGTERM mid stage 2: the single notice says signalled" "$N_REASON" "signalled"
  check_eq "SIGTERM mid stage 2: the notice says active=false" "$N_ACTIVE" "false"
  check_eq "SIGTERM mid stage 2: exactly one notice" "$NOTICE_N" "1"
  # a hostile stub that appends active=true / skip_legs=test-bun to ITS inherited output file, then the job is cancelled
  drive k1 "$d" "SWITCH=on" "STUB_TERM_AT=2" "STUB_WRITE_OUT=1"
  check_eq "SIGTERM mid stage 2 + a stub that tries to write the output file: still EXACTLY the defaults" "$O_TEXT" "$DEFAULTS"
}
row_lever_error() {  # an internal abort (here an unbound variable under set -u) is lever_error: one notice, only the defaults, exit 0
  local d="$1" m="$SANDBOX/lever.$RUN_N.sh"
  sed 's|^  reason=not_pr$|&\n  : "${zz_unbound_probe}"|' "$d" > "$m"
  if cmp -s "$m" "$d"; then record "lever_error injection landed" 0 "the injected unbound expansion did not land"; return; fi
  EXPECT_STDERR=1
  drive k1 "$m" "SWITCH=on"
  EXPECT_STDERR=0
  check_eq "lever_error: the driver still exits 0" "$RC" "0"
  check_eq "lever_error: reason" "$N_REASON" "lever_error"
  check_eq "lever_error: outputs are the defaults" "$O_TEXT" "$DEFAULTS"
  check_eq "lever_error: the notice says active=false" "$N_ACTIVE" "false"
}
row_child_env() {  # the selector child must not inherit the step's output files
  local d="$1" p1 p2 n
  SCEN="$SC/real"   # nothing skippable: a forged `active=true` would be the only way to arm
  drive k1 "$d" "STUB_WRITE_OUT=1"
  p1=$(git -C "$FX/k1" rev-parse 'HEAD^1'); p2=$(git -C "$FX/k1" rev-parse 'HEAD^2')
  check_eq "child env: all 4 selector calls ran" "$STUB_CALLS" "4"
  n=$(grep -c 'W=none' "$O/stub/log"); check_eq "child env: every selector call saw NO GITHUB_OUTPUT/STEP_SUMMARY/ENV/PATH/STATE" "$n" "4"
  check_eq "child env: a stub write attempt leaves the output file at defaults plus ONE final block (8 lines)" "$O_NLINES" "8"
  check_eq "child env: the output file is exactly the defaults and the final block" "$O_TEXT" "$DEFAULTS"$'\n'"head_sha=$p2"$'\n'"base_sha=$p1"$'\n'"active=false"$'\n'"skip_legs="
  SCEN="$SC/allskip"
}
row_budget() {  # budget sanitation: digits only, <= 6 digits, decimal, >= 1; otherwise the default 120 (never `timeout 0`)
  local d="$1" v
  for v in "08:8" "010:10" "0:120" "abc:120" ":120" "1234567:120" "000123:123" "-5:120" "7x:120" "99:99" "000000:120"; do
    drive k1 "$d" "PR_SELECTION_STAGE2_TIMEOUT=${v%%:*}"
    check_eq "budget '${v%%:*}': the effective budget" "$N_BUDGET" "${v##*:}"
    check_eq "budget '${v%%:*}': the run still reaches stage 2" "$N_STAGE" "2"
  done
}
row_hang_first() {  # a hung FIRST enumerate call eats the budget: the remaining groups get rem<1 and are NOT run (never `timeout 0`)
  local d="$1" t0 t1
  t0=$SECONDS
  drive k1 "$d" "STUB_HANG_AT=2" "PR_SELECTION_STAGE2_TIMEOUT=3"
  t1=$SECONDS
  check_eq "rem: only the selection and the hung first enumerate ran" "$STUB_CALLS" "2"
  check_eq "rem: every group is a timeout token" "$N_GROUPS" "webplat:timeout,bun:timeout,scripts-heavy:timeout"
  check_eq "rem: a timeout is censored" "$N_CENS" "1"
  check_eq "rem: a degraded enumerate is never the benign 'affected'" "$N_REASON" "affected_degraded"
  check_eq "rem: nothing would be skipped" "$N_WOULD" "none"
  check_true "rem: the hung call was cut at the budget, not waited for ($((t1 - t0))s)" "$([ $((t1 - t0)) -lt 8 ]; echo $?)"
}
row_rerun() {  # G2-7
  local d="$1" v
  for v in 2 3 "" x "1 " 01 -1; do
    drive k1 "$d" "RUN_ATTEMPT=$v"
    expect_full "G2-7 RUN_ATTEMPT='$v'" rerun 0
  done
  drive k1 "$d" "RUN_ATTEMPT=2"
  check_eq "G2-7 the annotation reports the attempt number" "$N_ATTEMPT" "2"
  check_match "G2-7 a re-run still emits the validated audit shas" "$O_HEAD" '^[0-9a-f]{40}$'
}
row_odd_cntrl() {  # G2-14: a control character in a path (newline, CR, tab)
  local d="$1" f
  for f in nl cr tabp; do
    drive "$f" "$d"
    expect_full "G2-14 control character in a path ($f)" odd_path 0
  done
}
row_odd_colons() {  # G2-14: `::` in a path (a workflow-command injection if it were ever echoed)
  local d="$1"
  drive col "$d"
  expect_full "G2-14 '::' in a path" odd_path 0
}
row_odd_comma() {  # a comma would split the --paths list into different files
  local d="$1"
  drive com "$d"
  expect_full "G2-14 ',' in a path" odd_path 0
}
row_status() {  # any status letter other than M/A/D (here T: a file became a symlink) is full
  local d="$1"
  drive typ "$d"
  expect_full "G2-15 typechange status" non_doc_status 0
}
row_docs_outside() {  # G2-15: docs rename/delete/modify and the other shapes outside the allowlist
  local d="$1" f
  for f in docren docdel docmod code legal mk; do
    drive "$f" "$d"
    expect_full "G2-15 outside the allowlist ($f)" non_doc 0
  done
}
row_docs_inside() {  # inside the allowlist: M, A, D, a rename (D+A) and a root *.md all reach stage 2
  local d="$1" f
  for f in k1 k2 kad krn; do
    drive "$f" "$d"
    check_eq "G2-15 inside the allowlist ($f): reason" "$N_REASON" "affected"
    check_eq "G2-15 inside the allowlist ($f): stage 2 ran (4 selector calls)" "$STUB_CALLS" "4"
  done
  drive krn "$d"
  check_eq "G2-15 a KB rename passes BOTH the old and the new path" \
    "$(<"$O/stub/paths.1")" "knowledge-base/project/zzleak-b.md,knowledge-base/project/zzleak-b2.md"
  drive k2 "$d"
  check_eq "G2-15 a root-level *.md rides along" "$(<"$O/stub/paths.1")" "README.md,$KB_A"
}
row_diagrams() {  # G2-15: a diagrams edit never lets test-webplat be skipped
  local d="$1"
  drive dia "$d" "SWITCH=on"
  check_eq "G2-15 diagrams edit: would_skip" "$N_WOULD" "test-bun,test-scripts-heavy"
  check_eq "G2-15 diagrams edit: skip_legs" "$O_SKIP" "test-bun,test-scripts-heavy"
  check_contains "G2-15 diagrams edit: the summary names the cause" "$SUMTXT" "test-webplat=diagrams"
  drive k1 "$d" "SWITCH=on"
  check_eq "G2-15 a plain doc edit: test-webplat IS in the set" "$N_WOULD" "$ALL"
}
row_fork() {  # G2-15
  local d="$1" v
  for v in "x/other" "" "${REPO_NAME^^}"; do
    drive k1 "$d" "HEAD_REPO=$v"
    expect_full "G2-15 fork head HEAD_REPO='$v'" fork 0
  done
  drive k1 "$d" "HEAD_REPO=" "GH_REPO="
  expect_full "G2-15 both repos empty is NOT equal" fork 0
}
row_maxfiles() {  # G2-15
  local d="$1"
  drive n501 "$d"
  expect_full "G2-15 501 changed files" too_many_files 0
  check_eq "G2-15 501 changed files: the count is reported" "$N_FILES" "501"
  drive n500 "$d"
  check_eq "G2-15 500 changed files is inside the cap" "$N_REASON" "affected"
  check_eq "G2-15 500 changed files: count" "$N_FILES" "500"
}
row_bigpaths() {  # G2-15: a listing over 64 KB is classified correctly, not mis-read as non-doc or as a failure
  local d="$1" sz
  drive big "$d"
  sz=$(wc -c < <(git -C "$FX/big" diff -z --raw --no-renames --no-abbrev HEAD^1 HEAD))
  check_true "G2-15 the >64KB fixture really is over 64 KB ($sz bytes)" "$([ "$sz" -gt 65536 ]; echo $?)"
  check_eq "G2-15 a >64KB doc-only listing reaches stage 2" "$N_REASON" "affected"
  check_eq "G2-15 a >64KB doc-only listing: 4 selector calls" "$STUB_CALLS" "4"
  check_eq "G2-15 a >64KB listing: all 320 files seen" "$N_FILES" "320"
  drive bigbad "$d"
  expect_full "G2-15 a >64KB listing with a code file at the end" non_doc 0
}
row_empty() {  # G2-15
  local d="$1"
  drive empty "$d"
  expect_full "G2-15 empty diff" empty_diff 0
}
row_ci_leak() {  # G2-9: CI (and the force-all spelling) leaking into the environment must not reach the selector
  local d="$1" n
  drive k1 "$d" "CI=true" "SOLEUR_TEST_FORCE_ALL=1"
  check_eq "G2-9 stub saw 4 calls" "$STUB_CALLS" "4"
  check_eq "G2-9 every selector call saw CI unset" "$(grep -c 'CI=UNSET' "$O/stub/log")" "4"
  check_eq "G2-9 every selector call saw SOLEUR_TEST_FORCE_ALL unset" "$(grep -c 'FORCE=UNSET' "$O/stub/log")" "4"
  check_eq "G2-9 the verdict is unchanged by the leak" "$N_WOULD" "$ALL"
  n=$(grep -c -- '--print-selection' "$O/stub/log"); check_eq "G2-9 one --print-selection call" "$n" "1"
  n=$(grep -c -- '--enumerate-commands' "$O/stub/log"); check_eq "G2-9 three --enumerate-commands calls" "$n" "3"
}
row_selector_unknowns() {  # G2-10: empty, summary-less, fallback or malformed selector output
  local d="$1" v
  for v in nosummary:selector_unparsed empty:selector_unparsed garbage:selector_unparsed twosummary:selector_unparsed \
           badsel:selector_unparsed fb_both:selector_fallback fb_summary:selector_fallback fb_numeric:selector_fallback fb_line:selector_fallback \
           unresolved:selector_fallback selrc:selector_error; do
    SCEN="$SC/${v%%:*}"
    drive k1 "$d"
    check_eq "G2-10 selector output '${v%%:*}': reason" "$N_REASON" "${v##*:}"
    check_eq "G2-10 selector output '${v%%:*}': nothing would be skipped" "$N_WOULD" "none"
    check_eq "G2-10 selector output '${v%%:*}': skip_legs" "$O_SKIP" ""
  done
  SCEN="$SC/allskip"
}
row_selector_timeout() {  # G2-10: a hung selector degrades to full within the budget
  local d="$1" t0 t1
  t0=$SECONDS
  drive k1 "$d" "STUB_SLEEP=5" "PR_SELECTION_STAGE2_TIMEOUT=1"
  t1=$SECONDS
  check_eq "G2-10 a hung selector: reason" "$N_REASON" "selector_timeout"
  check_eq "G2-10 a hung selector: nothing would be skipped" "$N_WOULD" "none"
  check_eq "G2-10 a hung selector: sel_censored=1 (sel_s is a lower bound)" "$N_CENS" "1"
  check_eq "G2-10 a hung selector: budget reported" "$N_BUDGET" "1"
  check_true "G2-10 a hung selector is cut off by the budget, not waited for ($((t1 - t0))s)" "$([ $((t1 - t0)) -lt 5 ]; echo $?)"
}
row_groups() {  # G2-11: per-group rules
  local d="$1" v
  for v in emptygroup:test-webplat,test-scripts-heavy:test-bun=no_records:affected_degraded \
           plain:test-webplat,test-scripts-heavy:test-bun=plain_decline:affected \
           missing:test-webplat,test-scripts-heavy:test-bun=missing_row:affected_degraded \
           alwayson:test-webplat,test-scripts-heavy:test-bun=always_on:affected \
           selected:test-webplat,test-scripts-heavy:test-bun=selected:affected \
           badrecord:test-webplat,test-scripts-heavy:test-bun=parse:affected_degraded \
           webrc:test-bun,test-scripts-heavy:test-webplat=bad_rc:affected_degraded; do
    SCEN="$SC/${v%%:*}"
    drive k1 "$d"
    IFS=: read -r _ want tok rsn <<< "$v"
    check_eq "G2-11 group case '${v%%:*}': would_skip" "$N_WOULD" "$want"
    check_contains "G2-11 group case '${v%%:*}': the summary names the cause" "$SUMTXT" "$tok"
    check_eq "G2-11 group case '${v%%:*}': reason" "$N_REASON" "$rsn"
    gt="${tok#test-}"
    check_contains "G2-11 group case '${v%%:*}': the notice groups field names the cause" "$N_GROUPS" "${gt/=/:}"
  done
  # a stream without any record prefix is no records at all
  SCEN="$SC/noprefix"
  drive k1 "$d"
  check_eq "G2-11 a stream with no recognised record" "$N_WOULD" "test-webplat,test-scripts-heavy"
  SCEN="$SC/allskip"
}
row_real_shape() {  # the shapes measured on 2026-10-14: nothing is skippable today, with the measured reasons
  local d="$1"
  SCEN="$SC/real"
  drive k1 "$d"
  check_eq "REAL shapes: would_skip" "$N_WOULD" "none"
  check_eq "REAL shapes: reason (the selector answered cleanly)" "$N_REASON" "affected"
  check_contains "REAL shapes: webplat holds a plain relevance decline" "$SUMTXT" "test-webplat=plain_decline"
  check_contains "REAL shapes: bun holds always-on suites" "$SUMTXT" "test-bun=always_on"
  check_contains "REAL shapes: heavy holds a plain decline" "$SUMTXT" "test-scripts-heavy=plain_decline"
  SCEN="$SC/allskip"
}
row_must_pass() {  # the must-PASS row: a legitimate doc-only diff, locked: evidence yes, skip_legs EMPTY
  local d="$1"
  drive k1 "$d" "SWITCH=on"
  check_eq "MUST-PASS doc-only diff reaches stage 2" "$N_STAGE" "2"
  check_eq "MUST-PASS doc-only diff: stage-2 would-skip evidence" "$N_WOULD" "$ALL"
  check_eq "MUST-PASS doc-only diff, locked: skip_legs EMPTY" "$O_SKIP" ""
  check_eq "MUST-PASS doc-only diff, locked: active false" "$O_ACTIVE" "false"
  check_eq "MUST-PASS doc-only diff: one --print-selection and three enumerate calls" "$STUB_CALLS" "4"
  check_contains "MUST-PASS the selector is asked for the diff's own paths" "$(<"$O/stub/paths.1")" "$KB_A"
  check_eq "MUST-PASS notice: active=false under the lock" "$N_ACTIVE" "false"
  check_eq "MUST-PASS notice: the effective budget is reported" "$N_BUDGET" "30"
  check_eq "MUST-PASS notice: not censored" "$N_CENS" "0"
  check_eq "MUST-PASS notice: every group reported" "$N_GROUPS" "webplat:skip,bun:skip,scripts-heavy:skip"
  check_eq "MUST-PASS notice: reason affected (no degraded group)" "$N_REASON" "affected"
  check_contains "MUST-PASS the step summary carries the new fields" "$SUMTXT" "sel_censored=0 budget=30 groups=webplat:skip,bun:skip,scripts-heavy:skip"
}

row_modes() {  # stage 1 is MODE-aware: only 000000/100644/100755 on both sides; a mode flip on a doc .md is still doc
  local d="$1" f
  for f in msym mgit mrsym mdsym; do
    drive "$f" "$d"
    expect_full "MODE new symlink/gitlink ($f)" non_doc_mode 0
  done
  drive mflip "$d"
  check_eq "MODE a 100644->100755 flip on a doc .md stays doc-class (reaches stage 2)" "$N_REASON" "affected"
  check_eq "MODE a mode flip: stage 2 ran" "$STUB_CALLS" "4"
  check_eq "MODE a mode flip: the selector is asked for the doc path" "$(<"$O/stub/paths.1")" "$KB_A"
  check_eq "MODE precondition: the flip really is mode-only M 100644->100755" \
    "$(git -C "$FX/mflip" diff --raw --no-renames HEAD^1 HEAD | cut -c1-14)" ":100644 100755"
}
row_allowlist() {  # the allowlist is knowledge-base/**/*.md or a root *.md: the NAME ends in .md
  local d="$1" i
  for i in "${!NEARMISS[@]}"; do
    drive "nd$i" "$d"
    expect_full "ALLOWLIST near-miss '${NEARMISS[$i]}'" non_doc 0
  done
  drive ndbare "$d"
  expect_full "ALLOWLIST a bare file named 'knowledge-base'" non_doc 0
}
row_nonascii() {  # a byte outside printable ASCII (U+2028, a C1 control, a UTF-8 letter) is an odd path
  local d="$1" f
  for f in nasc0 nasc1 nasc2; do
    drive "$f" "$d"
    expect_full "NON-ASCII path ($f)" odd_path 0
  done
}
row_advanced_base() {  # main moved on after the branch point: the diff is HEAD^1..HEAD (the PR's OWN paths), not HEAD^1..HEAD^2
  local d="$1"
  drive adv "$d"
  check_eq "ADV-BASE a doc-only PR on an advanced base reaches stage 2" "$N_REASON" "affected"
  check_eq "ADV-BASE stage 2 ran (4 selector calls)" "$STUB_CALLS" "4"
  check_eq "ADV-BASE the selector receives the PR's own paths ONLY" "$(<"$O/stub/paths.1")" "$KB_A"
  check_eq "ADV-BASE one changed file" "$N_FILES" "1"
}
row_selection_shapes() {  # selection-output shapes beyond the recorded ones
  local d="$1" v
  for v in norows:selector_unparsed twotabs:selector_unparsed nocls:selector_unparsed allnum:selector_fallback; do
    SCEN="$SC/${v%%:*}"
    drive k1 "$d"
    check_eq "SHAPE selection '${v%%:*}': reason" "$N_REASON" "${v##*:}"
    check_eq "SHAPE selection '${v%%:*}': nothing would be skipped" "$N_WOULD" "none"
    check_eq "SHAPE selection '${v%%:*}': groups not reported" "$N_GROUPS" "-"
  done
  # a heavy group made only of pr-gated declines IS skippable (the documented behaviour) ...
  SCEN="$SC/heavydecl"
  drive k1 "$d"
  check_eq "SHAPE heavy group of only pr-gated declines is skippable" "$N_WOULD" "$ALL"
  check_eq "SHAPE heavy group of only pr-gated declines: token" "$N_GROUPS" "webplat:skip,bun:skip,scripts-heavy:skip"
  # ... a group with ZERO records is not
  SCEN="$SC/heavyzero"
  drive k1 "$d"
  check_eq "SHAPE heavy group with zero records is NOT skippable" "$N_WOULD" "test-webplat,test-bun"
  check_eq "SHAPE heavy group with zero records: token" "$N_GROUPS" "webplat:skip,bun:skip,scripts-heavy:no_records"
  check_eq "SHAPE heavy group with zero records: degraded" "$N_REASON" "affected_degraded"
  SCEN="$SC/allskip"
}
row_argv_cap() {  # the joined --paths list is bounded: over 100000 bytes is full (and never reaches the selector)
  local d="$1" plen
  plen=$(git -C "$FX/bigargv" diff --name-only HEAD^1 HEAD | wc -c)
  check_true "ARGV precondition: the joined list is over 100000 bytes ($plen)" "$([ "$plen" -gt 100001 ]; echo $?)"
  drive bigargv "$d"
  expect_full "ARGV a joined --paths list over 100000 bytes" paths_too_long 0
  plen=$(git -C "$FX/bigok" diff --name-only HEAD^1 HEAD | wc -c)
  check_true "ARGV precondition: the under-cap list is between 90000 and 100000 bytes ($plen)" "$([ "$plen" -gt 90000 ] && [ "$plen" -le 100000 ]; echo $?)"
  drive bigok "$d"
  check_eq "ARGV just under the cap reaches stage 2" "$N_REASON" "affected"
  check_true "ARGV the stub's recorded --paths= argument is under the cap" "$([ "$(grep -c -E '\[--paths=(9[0-9]{4}|10[0-9]{4})B\]' "$O/stub/log")" -ge 1 ]; echo $?)"
  check_true "ARGV the recorded paths file is under the cap" "$([ "$(wc -c < "$O/stub/paths.1")" -le 100000 ]; echo $?)"
}
row_leak() {  # the raw switch value, the repo name and the shas reach no output but the gh output file's own audit shas
  local d="$1"
  drive k1 "$d" "SWITCH=zzleak-raw-switch-value"
  check_eq "LEAK a raw switch value is reported as 'invalid' only" "$N_SWITCH" "invalid"
  check_eq "LEAK the run still reaches stage 2" "$N_STAGE" "2"
}
row_trigger_active() {  # against the UNLOCKED driver with the switch ON: a trigger path must still never arm a skip
  local d="$1" i
  for i in "${!TRIGGERS[@]}"; do
    drive "trg$i" "$d" "SWITCH=on"
    check_eq "TRIGGER-ACTIVE '${TRIGGERS[$i]}' with SWITCH=on, unlocked: active" "$O_ACTIVE" "false"
    check_eq "TRIGGER-ACTIVE '${TRIGGERS[$i]}' with SWITCH=on, unlocked: skip_legs" "$O_SKIP" ""
  done
}

# Rows that run against the PRISTINE (locked) driver, and rows that need the lock-neutralized copy.
PRISTINE_ROWS=(row_not_pr row_shape_ok row_shape_count row_shape_githubsha row_shape_prhead row_shape_shallow row_diff_error
               row_trigger_core row_trigger_sourced row_lock row_skip_gated_on_active row_rerun row_odd_cntrl row_odd_colons
               row_odd_comma row_status row_docs_outside row_docs_inside row_fork row_maxfiles row_bigpaths row_empty
               row_ci_leak row_selector_unknowns row_selector_timeout row_groups row_real_shape row_must_pass
               row_modes row_allowlist row_nonascii row_advanced_base row_selection_shapes row_argv_cap row_leak row_budget
               row_hang_first row_child_env row_lever_error)
UNLOCKED_ROWS=(row_switch row_diagrams row_defaults_first row_term row_trigger_active)

# ── CONTROL: the unmutated driver must be GREEN before any mutant is read ────
_c0=$fails
for _r in "${PRISTINE_ROWS[@]}"; do "$_r" "$PRISTINE"; done
for _r in "${UNLOCKED_ROWS[@]}"; do "$_r" "$UNLOCKED"; done
unset _r
if [ "$fails" -ne "$_c0" ]; then
  printf '\nCONTROL ROWS FAILED: the battery is VOID, not failing. The unmutated driver does not satisfy its own\n' >&2
  printf 'contract, so every mutation verdict below would be measured against a broken baseline.\n' >&2
  printf 'rows=%d passed=%d failed=%d\n' "$((passes + fails))" "$passes" "$fails" >&2
  printf '  - %s\n' "${FAILURES[@]}" >&2
  exit 1
fi
echo "  control: $((passes)) checks green against the pristine and the lock-neutralized driver"

# ── Static guards that are not mutated: lock literal, lock-copy landing, tools, derived sets ──
_lockn=$(grep -c -E "$LOCK_RE" "$PRISTINE")
check_eq "G2-13 the activation lock is ONE literal line, byte-exact" "$_lockn" "1"
_lockline=$(grep -n -E "$LOCK_RE" "$PRISTINE" | cut -d: -f1)
check_true "G2-13 the lock line sits near the top of the driver (line $_lockline)" "$(rc_of test "$_lockline" -le 90)"
check_eq "G2-13 the neutralized copy differs from the pristine driver by exactly the lock line" \
  "$(diff "$PRISTINE" "$UNLOCKED" | grep -c '^[<>]')" "1"
check_eq "G2-13 the neutralized copy has no lock line" "$(grep -c -E '^readonly PR_AFFECTED_LOCKED=' "$UNLOCKED")" "0"
check_true "G2-13 the driver READS the lock for the arm" "$(grep -q 'PR_AFFECTED_LOCKED:-' "$PRISTINE"; echo $?)"
check_eq "PRISTINE copy is byte-identical to the live driver" "$(cmp -s "$PRISTINE" "$DRIVER"; echo $?)" "0"

# The driver uses no tool beyond bash, git and coreutils: a static scan of its CODE lines (comments stripped), command
# positions only (a group NAME such as `bun` in a for-list is not a command). The scanner proves it can fire first.
TOOL_RE='(^|[|;&(`]|[[:space:]](then|do|else))[[:space:]]*(node|bun|python3?|jq|awk|gawk|sed|perl|npm|npx|gh|curl|grep|egrep)([[:space:]]|$)'
scan_tools() { grep -v -E '^[[:space:]]*#' "$1" | sed -E 's/[[:space:]]#.*$//' | grep -n -E "$TOOL_RE" || true; }
printf 'x=$(jq .a b)\nif true; then awk 1; fi\nfor g in a bun c; do :; done\n' > "$SANDBOX/toolscan.sample"
_ts=$(scan_tools "$SANDBOX/toolscan.sample")
check_eq "tool scanner self-test: it flags jq and awk in command position and not a 'bun' list word" "$(printf '%s' "$_ts" | grep -c .)" "2"
check_eq "the driver's code lines name no node/bun/python/jq/awk/sed/perl/gh/grep command" "$(scan_tools "$DRIVER")" ""
unset _ts

# G2-2: every file the real scripts/test-all.sh sources is derived and sits under scripts/lib/ (a future-proof failure
# otherwise: the trigger list must learn the new location). The per-file full-run behaviour is row_trigger_sourced.
check_true "G2-2 the derivation found the sourced files (${#SOURCED[@]}): vacuity floor" "$(rc_of test "${#SOURCED[@]}" -ge 6)"
check_eq "G2-2 every sourced operand resolved (unresolved: ${SOURCE_UNRESOLVED[*]:-none})" "${#SOURCE_UNRESOLVED[@]}" "0"
for _s in "${SOURCED[@]}"; do
  case "$_s" in
    scripts/lib/*) record "G2-2 sourced '$_s' is under scripts/lib/" 1 "" ;;
    *) record "G2-2 sourced '$_s' is OUTSIDE scripts/lib/" 0 "scripts/test-all.sh now sources '$_s'; add it to the trigger list in scripts/ci-pr-selection.sh and to TRIGGERS here" ;;
  esac
done
unset _s

# The pr-gated decline labels the driver hard-codes must be exactly what scripts/test-all.sh declines through --pr-gated.
check_true "G2-11 the derivation found the real --pr-gated declines (${#PRGATED_REAL[@]}): vacuity floor" "$(rc_of test "${#PRGATED_REAL[@]}" -ge 5)"
check_eq "G2-11 the driver's pr-gated decline labels equal those derived from scripts/test-all.sh" \
  "$(printf '%s|' "${PRGATED_DRIVER[@]}")" "$(printf '%s|' "${PRGATED_REAL[@]}")"

# ═══ MUTATION BATTERY ═══════════════════════════════════════════════════════
# Each row mutates a COPY, asserts the mutation LANDED (a mutation that does not land measures the BASELINE), drives the
# relevant rows in PROBE mode, and requires at least one check to FAIL. Surviving mutants are labelled in the report.
MUT_TOTAL=0; MUT_KILLED=0; MUT_SURVIVED=()
MUT_N=0

mutate() {  # $1=label $2=base driver file $3=sed expression $4...=row functions to drive
  local label="$1" base="$2" expr="$3"; shift 3
  local m="$SANDBOX/mut.$((++MUT_N)).sh" fn
  MUT_TOTAL=$((MUT_TOTAL + 1))
  sed "$expr" "$base" > "$m"
  if cmp -s "$m" "$base"; then
    fail "MUTATION DID NOT LAND: $label (the sed expression matched nothing, so this row measured the BASELINE)"
    return
  fi
  if ! bash -n "$m" 2> /dev/null; then
    fail "MUTANT NOT WELL-FORMED: $label (a syntax error would kill every row for the wrong reason)"
    return
  fi
  [ -z "${PRSEL_PROBE_VERBOSE:-}" ] || printf 'probe-mutant %s: %s\n' "$MUT_N" "$label" >&3
  PROBE=1; PROBE_FAILS=0
  for fn in "$@"; do "$fn" "$m" > /dev/null 2>&1; done
  PROBE=0
  if [ "$PROBE_FAILS" -gt 0 ]; then
    pass; MUT_KILLED=$((MUT_KILLED + 1))
  else
    fail "MUTANT SURVIVED: $label (the guard rows did not detect this edit)"
    MUT_SURVIVED+=("$label")
  fi
}
kill_guard() { printf 's|^.*# GUARD:%s$|  : # MUTATED|' "$1"; }       # replace the whole guard line with a no-op
drop_return() { printf 's@[[:space:]]*|| return 0[[:space:]]*# GUARD:%s$@  # MUTATED@' "$1"; }  # keep the command, drop its failure exit

# G2-1
mutate "G2-1 parent count not checked"            "$PRISTINE" "$(kill_guard G2-1-TWO-PARENTS)"             row_shape_count
mutate "G2-1 HEAD == GITHUB_SHA not checked"      "$PRISTINE" "$(kill_guard G2-1-HEAD-IS-GITHUB-SHA)"      row_shape_githubsha
mutate "G2-1 HEAD^2 == PR head not checked"       "$PRISTINE" "$(kill_guard G2-1-PARENT2-IS-PR-HEAD)"      row_shape_prhead
mutate "G2-1 git diff failure ignored"            "$PRISTINE" "$(drop_return G2-1-DIFF-RC)"                row_diff_error   # EQUIVALENT-LABEL (verified, PRSEL_PROBE_VERBOSE=all: only reason labels turn red): an empty listing is still full (empty_diff)
mutate "G2-1 only a pull_request run selects"     "$PRISTINE" "$(kill_guard G2-NOT-PR)"                    row_not_pr
# G2-2
mutate "G2-2 trigger list neutered"               "$PRISTINE" "$(kill_guard G2-2-TRIGGER)"                 row_trigger_core row_trigger_sourced   # EQUIVALENT-LABEL (verified, PRSEL_PROBE_VERBOSE=all: only reason labels turn red): the trigger paths are outside the allowlist, so non_doc is still full
mutate "G2-2 scripts/lib/** prefix dropped"       "$PRISTINE" '/^    scripts\/lib\/\*) return 0 ;;$/d'     row_trigger_core row_trigger_sourced   # EQUIVALENT-LABEL (verified, PRSEL_PROBE_VERBOSE=all: only reason labels turn red): same: non_doc is still full
mutate "G2-2 heavy manifest dropped from the list" "$PRISTINE" '/^    scripts\/suite-shard-legs-heavy.tsv) return 0 ;;$/d' row_trigger_core   # EQUIVALENT-LABEL (verified, PRSEL_PROBE_VERBOSE=all: only reason labels turn red): same
mutate "G2-2 scripts/test-all.sh dropped from the list" "$PRISTINE" '/^    scripts\/test-all.sh) return 0 ;;$/d' row_trigger_core   # EQUIVALENT-LABEL (verified, PRSEL_PROBE_VERBOSE=all: only reason labels turn red): same
mutate "G2-2 ci.yml dropped from the list"        "$PRISTINE" '/^    \.github\/workflows\/ci.yml) return 0 ;;$/d' row_trigger_core   # EQUIVALENT-LABEL (verified, PRSEL_PROBE_VERBOSE=all: only reason labels turn red): same
# G2-5 / G2-13 (against the lock-neutralized copy so the switch is what decides)
mutate "G2-5 switch lowercased and trimmed"       "$UNLOCKED" 's|^\[ -z "\${SWITCH:-}" \] \|\| sw=invalid$|SWITCH="${SWITCH:-}"; SWITCH="${SWITCH//[[:space:]]/}"; SWITCH="${SWITCH,,}"\n&|' row_switch
mutate "G2-5 switch matched by prefix"            "$UNLOCKED" 's|^\[ "\${SWITCH:-}" = on \] && sw=on  # GUARD:G2-5-SWITCH-EXACT$|[[ "${SWITCH:-}" == on* ]] \&\& sw=on|' row_switch
mutate "G2-5 any non-empty switch arms"           "$UNLOCKED" 's|^\[ "\${SWITCH:-}" = on \] && sw=on  # GUARD:G2-5-SWITCH-EXACT$|[ -n "${SWITCH:-}" ] \&\& sw=on|' row_switch
mutate "G2-13 the lock is not read (locked stays false)" "$PRISTINE" "$(kill_guard G2-13-LOCK-READ)"       row_lock row_must_pass
mutate "G2-13 the arm ignores the lock"          "$PRISTINE" 's| \&\& \[ "\$locked" = false \]; then  # GUARD:G2-13-ARM$|; then|' row_lock row_must_pass
_e1='s|^# Re-validate every value.*$|skip_legs="$would_skip"\n&|'
_e2='s|^if \[ "\$active" != true \] \|\| ! |if ! |'
mutate "G2-13 skip_legs written when not active (arm gating AND final validation removed)" "$PRISTINE" "$_e1"$'\n'"$_e2" row_skip_gated_on_active
unset _e1 _e2
# G2-6 / G2-12
mutate "G2-6 the fail-closed defaults are not written first" "$PRISTINE" "$(kill_guard G2-6-DEFAULTS)"      row_defaults_first
RD='>>'  # a redirect token spelled inside a sed script is TEXT for the mutant, not a redirect of this suite
mutate "G2-12 skip_legs is written progressively, per group" "$UNLOCKED" 's|^\(    if \[ "\$tok" = skip \]; then list=.*\)$|\1\n    printf "skip_legs=%s\\n" "$list" '"$RD"' "$OUT"|' row_defaults_first
mutate "G2 the EXIT trap (always exit 0) removed" "$PRISTINE" "$(kill_guard ALWAYS-EXIT-0)"                row_term row_lever_error
mutate "G2 the HUP/INT/TERM trap removed (a signal is not 'signalled')" "$PRISTINE" "$(kill_guard ALWAYS-EXIT-0-SIGNAL)" row_term
# G2-7
mutate "G2-7 a re-run is not full"                "$PRISTINE" "$(kill_guard G2-7-RERUN)"                   row_rerun
# G2-9
mutate "G2-9 CI not unset on the --print-selection call" "$PRISTINE" 's|^\(  timeout -k 5 "\$budget" \)env -u CI -u SOLEUR_TEST_FORCE_ALL |\1env |' row_ci_leak
mutate "G2-9 CI not unset on the --enumerate-commands call" "$PRISTINE" 's|^\(      timeout -k 5 "\$rem" \)env -u CI -u SOLEUR_TEST_FORCE_ALL |\1env |' row_ci_leak
mutate "G2-9 SOLEUR_TEST_FORCE_ALL not unset"     "$PRISTINE" 's| -u SOLEUR_TEST_FORCE_ALL||g'              row_ci_leak
mutate "G2-9 GITHUB_OUTPUT inherited by the --print-selection child" "$PRISTINE" 's|^\(  timeout -k 5 "\$budget" env.*\) -u GITHUB_OUTPUT\( .*GUARD:G2-9-CI-UNSET\)$|\1\2|' row_child_env
mutate "G2-9 GITHUB_OUTPUT inherited by the --enumerate-commands child" "$PRISTINE" 's|^\(      timeout -k 5 "\$rem" env.*\) -u GITHUB_OUTPUT\( .*GUARD:G2-9-CI-UNSET-ENUM\)$|\1\2|' row_child_env
mutate "G2-9 GITHUB_OUTPUT inherited, SIGTERM mid stage 2 (a forged active=true survives)" "$UNLOCKED" 's| -u GITHUB_OUTPUT||g' row_term
mutate "G2-9 the other step files (SUMMARY/ENV/PATH/STATE) inherited" "$PRISTINE" 's| -u GITHUB_STEP_SUMMARY -u GITHUB_ENV -u GITHUB_PATH -u GITHUB_STATE||g' row_child_env
# G2-10
mutate "G2-10 a summary-less selector output is accepted" "$PRISTINE" "$(kill_guard G2-10-SUMMARY-COUNT)"   row_selector_unknowns
mutate "G2-10 any AFFECTED_SUMMARY fallback is accepted" "$PRISTINE" 's|\\ fallback=none\$ \]\]|\\ fallback=[a-z-]+$ ]]|' row_selector_unknowns
mutate "G2-10 AFFECTED_FALLBACK/UNRESOLVED lines ignored" "$PRISTINE" 's|^      AFFECTED_FALLBACK\*\|AFFECTED_UNRESOLVED\*) sel_fallback_seen=1 ;;$|      AFFECTED_FALLBACK*\|AFFECTED_UNRESOLVED*) : ;;|' row_selector_unknowns
mutate "G2-10 a selector failure rc is ignored"   "$PRISTINE" 's|^  \[ "\$rc" -eq 0 \] \|\| return 0$|  :|' row_selector_unknowns
mutate "G2-10 the stage-2 budget is not enforced"  "$PRISTINE" 's|timeout -k 5 "\$budget" env|timeout -k 500 3000 env|' row_selector_timeout
mutate "G2-10 zero selection rows are accepted"   "$PRISTINE" "$(kill_guard G2-10-ZERO-ROWS)"                row_selection_shapes
mutate "G2-10 a row with fewer than 3 tabs is accepted" "$PRISTINE" "$(kill_guard G2-10-TABS)"              row_selection_shapes
mutate "G2-10 a row with an empty class is accepted" "$PRISTINE" "$(kill_guard G2-10-CLS)"                  row_selection_shapes
mutate "G2-10 non-numeric summary fields are accepted" "$PRISTINE" '/GUARD:G2-10-SUMMARY$/ s/\[0-9\]+/[a-z0-9]+/g' row_selection_shapes
mutate "G2-10 the censor flag is not set on a selector timeout" "$PRISTINE" 's|then sel_censored=1; reason=selector_timeout|then reason=selector_timeout|' row_selector_timeout
# G2-11
mutate "G2-11 a non-pr-gated decline is accepted" "$PRISTINE" "$(kill_guard G2-11-PLAIN-DECLINE)"          row_groups row_real_shape
mutate "G2-11 a record absent from the selection is accepted" "$PRISTINE" "$(kill_guard G2-11-MISSING-ROW)" row_groups
mutate "G2-11 an always_on class row is accepted"  "$PRISTINE" "$(kill_guard G2-11-ALWAYS-ON)"             row_groups row_real_shape
mutate "G2-11 a selected (sel=1) row is accepted"  "$PRISTINE" "$(kill_guard G2-11-SELECTED)"               row_groups row_real_shape
mutate "G2-11 an empty stream is accepted"         "$PRISTINE" "$(kill_guard G2-11-NO-RECORDS)"            row_groups
mutate "G2-11 a decline needs no pr-gated label"   "$PRISTINE" 's|^    "scripts/test-all-affected") return 0 ;;$|    *) return 0 ;;|' row_groups row_real_shape
# G2-14
mutate "G2-14 control characters accepted in a path" "$PRISTINE" "$(kill_guard G2-14-CNTRL)"               row_odd_cntrl
mutate "G2-14 '::' accepted in a path"            "$PRISTINE" "$(kill_guard G2-14-COLONS)"                 row_odd_colons
mutate "G2-14 ',' accepted in a path"             "$PRISTINE" "$(kill_guard G2-14-COMMA)"                  row_odd_comma
# G2-15
mutate "G2-15 the allowlist is not enforced"      "$PRISTINE" "$(kill_guard G2-15-ALLOWLIST)"              row_docs_outside row_allowlist
mutate "G2-15 plugins/soleur/docs is allowlisted" "$PRISTINE" 's|^    knowledge-base/?\*\.md) return 0 ;;$|    plugins/soleur/docs/*) return 0 ;;\n&|' row_docs_outside
mutate "G2-15 the .md suffix is not required under knowledge-base/" "$PRISTINE" 's|^    knowledge-base/?\*\.md) return 0 ;;$|    knowledge-base/?*) return 0 ;;|' row_allowlist
mutate "G2-15 the .md suffix is not required at the root" "$PRISTINE" 's|^    ?\*\.md) return 0 ;;$|    *) return 0 ;;|' row_docs_outside row_allowlist
mutate "G2-15 the knowledge-base prefix needs no slash" "$PRISTINE" 's|^    knowledge-base/?\*\.md) return 0 ;;$|    knowledge-base*.md) return 0 ;;|' row_allowlist
mutate "G2-15 a root file named *.mdx is a markdown file" "$PRISTINE" 's|^    ?\*\.md) return 0 ;;$|    ?*.md*) return 0 ;;|' row_allowlist
# the trigger list is outcome-redundant with the allowlist today: a widened allowlist AND no trigger check must be a BEHAVIOURAL
# kill (a trigger path reaches stage 2 and ARMS a skip), proving the list is the load-bearing layer once the allowlist widens (PR C)
mutate "COMBINED allowlist widened to scripts/** AND the trigger check removed" "$UNLOCKED" "$(kill_guard G2-2-TRIGGER)"$'\n''s|^    knowledge-base/?\*\.md) return 0 ;;$|    scripts/*) return 0 ;;\n&|' row_trigger_core row_trigger_active
mutate "MODE the symlink/gitlink mode check on the NEW side is removed" "$PRISTINE" "$(kill_guard G2-MODE-NEW)" row_modes
mutate "MODE the mode check on the OLD side is removed" "$PRISTINE" "$(kill_guard G2-MODE-OLD)" row_modes
mutate "MODE 100755 is not an accepted mode (a flip on a doc .md must stay doc)" "$PRISTINE" 's#000000|100644|100755#000000|100644#g' row_modes
mutate "MODE every mode is accepted" "$PRISTINE" 's#000000|100644|100755#*#g' row_modes
mutate "NON-ASCII only ASCII control characters are rejected" "$PRISTINE" 's#\[\[ "\$p" =~ \[^\\ -~\] \]\]#[[ "$p" == *[[:cntrl:]]* ]]#' row_nonascii
mutate "G2-15 a nested markdown file counts as root-level" "$PRISTINE" '/^    \*\/\*) return 1 ;;$/d'   row_docs_outside
mutate "G2-15 any status letter is accepted"      "$PRISTINE" "$(kill_guard G2-STATUS)"                    row_status   # EQUIVALENT-LABEL (verified, PRSEL_PROBE_VERBOSE=all: only reason labels turn red): a typechange to a symlink is refused by the mode check, still full
mutate "G2-15 diagrams edits do not block test-webplat" "$PRISTINE" "$(kill_guard G2-15-DIAGRAMS)"         row_diagrams
mutate "G2-15 the diagrams path is not flagged"   "$PRISTINE" "$(kill_guard G2-15-DIAGRAMS-FLAG)"         row_diagrams
mutate "G2-1 the diff is taken against the PR head (HEAD^1 HEAD^2), not the merge" "$PRISTINE" 's|HEAD^1 HEAD --|HEAD^1 HEAD^2 --|' row_advanced_base
mutate "G2-1 the diff is taken HEAD^2..HEAD (main's own movement leaks in)" "$PRISTINE" 's|HEAD^1 HEAD --|HEAD^2 HEAD --|' row_advanced_base
mutate "G2-15 the joined --paths cap is not enforced" "$PRISTINE" "$(kill_guard G2-15-PATHS-CAP)" row_argv_cap
mutate "G2-15 the joined --paths cap is 90000" "$PRISTINE" 's|\[ "\${#paths}" -le 100000 \]|[ "${#paths}" -le 90000 ]|' row_argv_cap
mutate "G2-15 a fork head is not full"            "$PRISTINE" "$(kill_guard G2-FORK)"                      row_fork
mutate "G2-15 the 500-file cap is not enforced"   "$PRISTINE" "$(kill_guard G2-15-MAX-FILES)"              row_maxfiles
mutate "G2-15 the cap is 501"                     "$PRISTINE" 's|\[ "\$files" -le 500 \]|[ "$files" -le 501 ]|' row_maxfiles
mutate "G2-15 an empty diff is not full by its own reason" "$PRISTINE" "$(kill_guard G2-15-EMPTY-DIFF)"    row_empty   # EQUIVALENT-LABEL (verified, PRSEL_PROBE_VERBOSE=all: only reason labels turn red): an empty listing falls to malformed_diff, still full

# budget sanitation and the remaining-budget path
mutate "BUDGET a leading zero is read as octal" "$PRISTINE" 's|^budget=\$((10#\$budget))$|budget=$((budget + 0))|' row_budget
mutate "BUDGET the 6-digit cap is removed" "$PRISTINE" '/^\[ "\${#budget}" -le 6 \] || budget=120$/d' row_budget
mutate "BUDGET a zero budget (timeout 0 = unlimited) is accepted" "$PRISTINE" '/^\[ "\$budget" -ge 1 \] || budget=120$/d' row_budget
mutate "BUDGET a non-numeric budget is accepted as is" "$PRISTINE" "s#^case \"\$budget\" in ''|\*\[!0-9\]\*) budget=120 ;; esac\$#:#" row_budget
mutate "REM an exhausted remaining budget still runs the group (timeout 0 = unlimited)" "$PRISTINE" 's|if \[ "\$rem" -lt 1 \]; then tok=timeout|if false; then tok=timeout|' row_hang_first
mutate "REM the enumerate call is not bounded by the remaining budget" "$PRISTINE" 's|timeout -k 5 "\$rem" env|timeout -k 500 3000 env|' row_hang_first
# the notice fields (reason labels: EQUIVALENT-LABEL by design, the reason IS the signal)
mutate "NOTICE a degraded enumerate reads as plain 'affected'" "$PRISTINE" 's|if \[ "\$degraded" = 1 \]; then reason=affected_degraded; else reason=affected; fi|reason=affected|' row_groups row_hang_first row_selection_shapes
mutate "NOTICE a timed-out group is not censored" "$PRISTINE" 's|case "\$tok" in timeout) sel_censored=1; degraded=1 ;;|case "$tok" in timeout) degraded=1 ;;|' row_hang_first
mutate "NOTICE the groups field is never filled" "$PRISTINE" 's|^  groups="\$groups_n"$|  groups=-|' row_groups row_must_pass
# the leak sweep: each operand must reach no output
mutate "LEAK the raw switch value reaches the step summary" "$PRISTINE" 's|"\$groups" '"$RD"' "\$SUMMARY"|"$groups" "${SWITCH:-}" '"$RD"' "$SUMMARY"|' row_leak
mutate "LEAK the repository name reaches the step summary" "$PRISTINE" 's|"\$groups" '"$RD"' "\$SUMMARY"|"$groups" "${HEAD_REPO:-}" '"$RD"' "$SUMMARY"|' row_leak
mutate "LEAK a sha reaches the step summary" "$PRISTINE" 's|"\$groups" '"$RD"' "\$SUMMARY"|"$groups" "$head_sha" '"$RD"' "$SUMMARY"|' row_leak
mutate "LEAK the base sha reaches stderr" "$PRISTINE" 's|^finished=1$|printf "%s\\n" "$base_sha" >\&2\n&|' row_leak

# ── Verdict ──────────────────────────────────────────────────────────────────
TOTAL=$((passes + fails))
echo
echo "mutation battery: $MUT_KILLED/$MUT_TOTAL killed"
if [ "${#MUT_SURVIVED[@]}" -gt 0 ]; then
  printf 'surviving mutants (fixture-gap or equivalent: label which):\n' >&2
  printf '  - %s\n' "${MUT_SURVIVED[@]}" >&2
fi

# ASSERTION FLOOR, reported with printf + exit rather than through the helpers it backstops (ADR-193): a floor dispatched
# through pass()/fail() is silenced by the same edit that silences everything else. DERIVED FROM A MEASURED GREEN RUN, not
# guessed: a floor above the real count is a broken instrument that reds a correct tree, a floor below it is slack in
# which an undispatched row can hide. Re-derive after adding a row:  bash scripts/ci-pr-selection.test.sh | tail -1
# MEASURED green run (2026-10-14): 2765 rows = BASE_ROWS + ROWS_PER_SOURCED_FILE * 7 sourced files, with 84 mutant
# verdicts counted among them. ROWS_PER_SOURCED_FILE is MEASURED, not estimated: running this suite on a copy of the repo whose
# scripts/test-all.sh has ONE fewer `source` line moved the total by exactly 18 rows (one `drive` of the file's trigger
# fixture with its 12 invariants, the 5 expect_full checks, and the 1 "sourced file is under scripts/lib/" row). BASE_ROWS is
# the remainder. An unrelated `source` edit in scripts/test-all.sh therefore no longer reds the suite; removing rows from the
# fixed part still does. Re-derive BASE_ROWS after adding or removing a row:
#   bash scripts/ci-pr-selection.test.sh | tail -1     then   BASE_ROWS = total - ROWS_PER_SOURCED_FILE * sourced_count
ROWS_PER_SOURCED_FILE=18
BASE_ROWS=2639
MIN_ROWS=$((BASE_ROWS + ROWS_PER_SOURCED_FILE * ${#SOURCED[@]}))
if [ "$TOTAL" -lt "$MIN_ROWS" ]; then
  printf 'FAIL: assertion floor: %d rows executed, at least %d required. Rows were removed or a loop stopped early.\n' \
    "$TOTAL" "$MIN_ROWS" >&2
  exit 1
fi
MIN_MUTANTS=84
if [ "$MUT_TOTAL" -lt "$MIN_MUTANTS" ]; then
  printf 'FAIL: mutation floor: %d mutants executed, at least %d required.\n' "$MUT_TOTAL" "$MIN_MUTANTS" >&2
  exit 1
fi

echo "ci-pr-selection.test.sh: $TOTAL rows, $passes passed, $fails failed"
if [ "${#FAILURES[@]}" -gt 0 ]; then
  printf '\nfailures:\n' >&2
  printf '  - %s\n' "${FAILURES[@]}" >&2
  exit 1
fi
exit 0
